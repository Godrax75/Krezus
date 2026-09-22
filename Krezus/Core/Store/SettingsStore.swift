import SwiftUI
import Observation

/// Apparence choisie. « Système » est le défaut : forcer un thème au premier
/// lancement contredirait le réglage iOS de l'utilisateur.
enum KrezusAppearance: String, CaseIterable, Sendable {
    case system, light, dark

    var label: String {
        switch self {
        case .system: return t("appearance.system")
        case .light:  return t("appearance.light")
        case .dark:   return t("appearance.dark")
        }
    }

    /// `nil` laisse la main au réglage système.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

/// Catégories de notifications, telles qu'exposées dans les réglages et
/// telles que filtrées côté serveur avant l'envoi d'un push.
enum NotificationTopic: String, CaseIterable, Identifiable, Sendable {
    case bonus, market, academy, arena, hercule

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bonus:   return t("topic.bonus.title")
        case .market:  return t("topic.market.title")
        case .academy: return t("topic.academy.title")
        case .arena:   return t("topic.arena.title")
        case .hercule: return t("topic.hercule.title")
        }
    }

    var subtitle: String {
        switch self {
        case .bonus:   return t("topic.bonus.subtitle")
        case .market:  return t("topic.market.subtitle")
        case .academy: return t("topic.academy.subtitle")
        case .arena:   return t("topic.arena.subtitle")
        case .hercule: return t("topic.hercule.subtitle")
        }
    }

    var icon: String {
        switch self {
        case .bonus:   return "banknote.fill"
        case .market:  return "chart.line.uptrend.xyaxis"
        case .academy: return "book.fill"
        case .arena:   return "trophy.fill"
        case .hercule: return "sparkles"
        }
    }
}

/// Préférences de l'utilisateur : apparence, langue, notifications, verrou.
///
/// Persistées dans `UserDefaults` — elles doivent survivre à une déconnexion et
/// s'appliquer avant même que la session Supabase soit restaurée, sinon l'app
/// s'ouvrirait systématiquement en thème clair le temps d'un aller-retour
/// réseau. La copie serveur (`profiles.dark_mode` / `locale`) est un miroir
/// pour les futurs envois de push, pas la source de vérité.
@MainActor
@Observable
final class SettingsStore {

    var appearance: KrezusAppearance = .system {
        didSet { persist(appearance.rawValue, .appearance); syncProfile() }
    }

    /// Langue de l'interface, indépendante de celle du système : le sélecteur
    /// des réglages doit suffire. `L10n` est prévenu à chaque changement, et la
    /// racine des vues est reconstruite via son `id` (voir `KrezusApp`).
    var language: AppLanguage = .fr {
        didSet {
            L10n.use(language)
            persist(language.rawValue, .locale)
            syncProfile()
        }
    }

    /// Autorisation système accordée (miroir de `UNAuthorizationStatus`).
    var pushAuthorized: Bool = false

    var enabledTopics: Set<NotificationTopic> = Set(NotificationTopic.allCases) {
        didSet { persist(enabledTopics.map(\.rawValue).sorted().joined(separator: ","), .topics) }
    }

    /// Verrou biométrique à l'ouverture de l'app.
    var biometricLock: Bool = false {
        didSet { persist(biometricLock, .biometricLock) }
    }

    /// Onboarding vu — coupe les 3 étapes d'introduction aux lancements suivants.
    private(set) var hasSeenOnboarding: Bool = false

    /// Identifiant du profil dont on miroite les préférences ; renseigné après
    /// connexion pour que `syncProfile` sache où écrire.
    var userID: UUID?

    private let defaults = UserDefaults.standard
    private let repository = ProfileRepository()

    private enum Key: String {
        case appearance     = "krz.appearance"
        case locale         = "krz.locale"
        case topics         = "krz.notificationTopics.v2"
        case legacyTopics   = "krz.notificationTopics"
        case biometricLock  = "krz.biometricLock"
        case onboarding     = "krz.hasSeenOnboarding"
    }

    init() {
        if let raw = defaults.string(forKey: Key.appearance.rawValue),
           let value = KrezusAppearance(rawValue: raw) {
            appearance = value
        }
        // Premier lancement : on suit la langue du téléphone plutôt que d'imposer
        // le français à un utilisateur anglophone.
        language = defaults.string(forKey: Key.locale.rawValue)
            .flatMap(AppLanguage.init(rawValue:)) ?? .systemDefault
        L10n.use(language)
        // Les thèmes sont enregistrés en toutes lettres. Un thème ajouté après
        // coup manquerait de la liste d'un ancien réglage, et se trouverait
        // désactivé sans que personne l'ait demandé : la clé porte donc une
        // version, et une liste d'avant la reprend avec les nouveaux thèmes
        // activés.
        if let raw = defaults.string(forKey: Key.topics.rawValue) {
            enabledTopics = Set(raw.split(separator: ",").compactMap {
                NotificationTopic(rawValue: String($0))
            })
        } else if let legacy = defaults.string(forKey: Key.legacyTopics.rawValue) {
            let known = Set(legacy.split(separator: ",").compactMap {
                NotificationTopic(rawValue: String($0))
            })
            enabledTopics = known.union([.bonus])
        }
        biometricLock = defaults.bool(forKey: Key.biometricLock.rawValue)
        hasSeenOnboarding = defaults.bool(forKey: Key.onboarding.rawValue)
    }

    func isTopicEnabled(_ topic: NotificationTopic) -> Bool {
        enabledTopics.contains(topic)
    }

    func setTopic(_ topic: NotificationTopic, enabled: Bool) {
        if enabled { enabledTopics.insert(topic) } else { enabledTopics.remove(topic) }
        // Le rappel du versement part d'un cron : c'est le serveur, pas
        // l'app, qui doit savoir si on en veut encore.
        if topic == .bonus { syncProfile() }
    }

    func completeOnboarding() {
        hasSeenOnboarding = true
        persist(true, .onboarding)
    }

    /// Réinitialise l'onboarding — utilisé par « Revoir la présentation ».
    func replayOnboarding() {
        hasSeenOnboarding = false
        persist(false, .onboarding)
    }

    // MARK: Persistance

    private func persist(_ value: Any, _ key: Key) {
        defaults.set(value, forKey: key.rawValue)
    }

    /// Vrai tant que le rappel hebdomadaire est accepté.
    var weeklyBonusPush: Bool { enabledTopics.contains(.bonus) }

    /// Recopie apparence, langue et consentement au rappel dans `profiles`. Silencieux : un échec
    /// réseau ne doit pas empêcher le réglage local de s'appliquer.
    private func syncProfile() {
        guard let userID, AppConfig.isConfigured else { return }
        let darkMode = appearance == .dark
        let locale = language.rawValue
        Task {
            try? await repository.updatePreferences(
                userID: userID, darkMode: darkMode, locale: locale,
                weeklyBonusPush: weeklyBonusPush)
        }
    }
}
