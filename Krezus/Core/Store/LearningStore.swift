import SwiftUI
import Observation

/// Leçon Academy. Chargée depuis `Resources/lessons.json`, lui-même exporté de
/// la table `lessons` de Supabase — les deux sources ne peuvent donc pas diverger.
struct AcademyLesson: Identifiable, Codable, Sendable {
    let position: Int
    let title: String
    let duration: String?
    let paragraphs: [String]
    let examples: [String]
    let quiz: Quiz?
    let isFree: Bool

    var id: Int { position }

    struct Quiz: Codable, Sendable {
        let q: String
        let opts: [String]
        /// Index de la bonne réponse dans `opts`.
        let a: Int
        /// Explication affichée après la réponse — c'est là que se joue la pédagogie.
        let why: String
    }

    enum CodingKeys: String, CodingKey {
        case position, title, duration, paragraphs, examples, quiz
        case isFree = "is_free"
    }
}

/// Rang romain. Paliers de 200 XP, alignés sur `public.ranks` et sur la
/// fonction `rank_for_xp` — toute modification doit toucher les deux.
struct AcademyRank: Identifiable, Codable, Sendable {
    let level: Int
    let emoji: String
    let name: String
    let minXp: Int
    let maxXp: Int?
    let imageAsset: String

    var id: Int { level }

    enum CodingKeys: String, CodingKey {
        case level, emoji, name
        case minXp = "min_xp"
        case maxXp = "max_xp"
        case imageAsset = "image_asset"
    }
}

/// Mission quotidienne ou ponctuelle, telle qu'affichée sur l'Accueil.
struct AcademyMission: Identifiable, Sendable {
    /// Identifiant partagé avec `public.missions` — c'est lui qui donne le
    /// libellé, via le catalogue de traductions.
    let code: String
    let xp: Int
    /// Une mission ponctuelle reste acquise ; une mission quotidienne se rejoue.
    let isDaily: Bool

    var id: String { code }
    var title: String { t("mission.\(code)") }
}

/// Progression de l'apprenant : XP, rang, série, missions, badges.
///
/// Deux sources derrière la même interface, comme pour `TradingStore` :
///
/// - **démo** — source de vérité en mémoire. La logique reproduit celle des
///   fonctions Postgres de `0005_academy.sql`, notamment le fait que l'XP vient
///   des **missions du jour** et non de chaque leçon : sans ce plafond,
///   enchaîner les 27 leçons d'un coup donnerait le rang maximal en une session.
/// - **serveur** — `complete_lesson` accorde l'XP et la série, l'app relit.
///   Aucun calcul d'XP côté client : c'est la même règle que pour le cash,
///   rejouer un appel ne doit rien fabriquer.
///
/// La bascule se fait dans `KrezusApp`, à la restauration de session.
@MainActor
@Observable
final class LearningStore {

    enum Source: Equatable { case demo, server }

    private(set) var source: Source = .demo
    private(set) var isLoading = false
    /// Dernière erreur de chargement, affichable. Les erreurs de validation de
    /// leçon sont levées à l'appelant, qui les montre dans son propre écran.
    private(set) var lastError: String?

    private(set) var lessons: [AcademyLesson] = []
    private(set) var ranks: [AcademyRank] = []

    private(set) var xp: Int = 0
    private(set) var streakDays: Int = 0
    /// Plus longue série atteinte — ce qui reste après un jour manqué, et la
    /// seule mesure qui rende la remise à zéro supportable.
    private(set) var bestStreakDays: Int = 0
    private(set) var completed: Set<Int> = []      // positions de leçons terminées
    private(set) var quizPassed: Set<Int> = []
    private(set) var earnedBadges: Set<String> = []

    /// Abonnement Hercule Premium — débloque les leçons 5 et suivantes (Lot 8).
    var isPremium: Bool = false

    /// Missions validées, et jour de référence pour les missions quotidiennes.
    private(set) var missionsDone: Set<String> = []
    private var missionsDay: Date = Calendar.current.startOfDay(for: Date())
    private var lastActivityDay: Date?

    static let missions: [AcademyMission] = [
        .init(code: "activate", xp: 50, isDaily: false),
        .init(code: "lesson",   xp: 20, isDaily: true),
        .init(code: "quiz",     xp: 30, isDaily: true),
    ]

    // Mode serveur
    private let repository = AcademyRepository()
    private var userID: UUID?

    init() {
        loadContent()
        seedDemoProgress()
    }

    // MARK: Source de données

    /// Bascule sur le serveur pour l'utilisateur connecté et charge tout.
    func connect(userID: UUID) async {
        guard AppConfig.isConfigured else { return }
        self.userID = userID
        source = .server
        await reload()
    }

    /// Repasse en démo — déconnexion, ou app non configurée.
    func disconnect() {
        userID = nil
        source = .demo
        lastError = nil
        seedDemoProgress()
    }

    /// Recharge XP, rang, série, leçons terminées, missions du jour et badges.
    func reload() async {
        guard source == .server, let userID else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let progress = try await repository.fetchProgress(userID: userID)
            let lessonRows = try await repository.fetchLessonProgress(userID: userID)

            xp = progress.xp
            streakDays = progress.streakDays
            bestStreakDays = max(bestStreakDays, progress.streakDays)
            completed = Set(lessonRows.map(\.position))
            quizPassed = Set(lessonRows.filter(\.quizCorrect).map(\.position))

            try await refreshMissionsAndBadges(userID: userID)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Missions du jour et badges — ce que `complete_lesson` fait bouger sans
    /// le renvoyer. Relire ces deux listes coûte moins qu'un `reload()` complet
    /// après chaque leçon.
    private func refreshMissionsAndBadges(userID: UUID) async throws {
        missionsDone = try await repository.fetchMissionsDone(userID: userID)
        missionsDay = Calendar.current.startOfDay(for: Date())
        earnedBadges = try await repository.fetchBadges(userID: userID)
    }

    /// Remet l'état de démonstration : progression vierge, activation acquise,
    /// série d'usage du prototype.
    private func seedDemoProgress() {
        xp = 0
        completed = []
        quizPassed = []
        earnedBadges = []
        missionsDone = []
        missionsDay = Calendar.current.startOfDay(for: Date())
        lastActivityDay = nil
        streakDays = 0

        // L'activation est acquise à la création du compte, comme le fait le
        // trigger `profiles_activate_mission` côté serveur.
        _ = completeMission("activate")
        // Série de départ du prototype : un acquis d'usage, pas une récompense,
        // donc elle ne crédite aucune XP.
        seedDemoStreak(5)
    }

    /// (Re)charge leçons et rangs dans la langue courante. Appelé au lancement
    /// puis à chaque changement de langue : la progression (XP, leçons
    /// terminées) est indexée par position, elle survit au rechargement.
    func loadContent() {
        lessons = Bundle.main.decodeJSON("lessons.json") ?? []
        ranks = Bundle.main.decodeJSON("ranks.json") ?? []
    }

    // MARK: Rangs

    var rankLevel: Int { min(6, max(1, 1 + xp / 200)) }

    var currentRank: AcademyRank? { ranks.first { $0.level == rankLevel } }
    var nextRank: AcademyRank? { ranks.first { $0.level == rankLevel + 1 } }

    /// Avancement vers le rang suivant, 0…1. Vaut 1 au dernier rang.
    var rankProgress: Double {
        guard let rank = currentRank, let ceiling = rank.maxXp else { return 1 }
        let span = Double(ceiling - rank.minXp + 1)
        guard span > 0 else { return 1 }
        return min(1, max(0, Double(xp - rank.minXp) / span))
    }

    /// XP restante avant le rang suivant ; `nil` au dernier rang.
    var xpToNextRank: Int? {
        guard let next = nextRank else { return nil }
        return max(0, next.minXp - xp)
    }

    // MARK: Leçons

    func lesson(at position: Int) -> AcademyLesson? {
        lessons.first { $0.position == position }
    }

    func isUnlocked(_ lesson: AcademyLesson) -> Bool { lesson.isFree || isPremium }
    func isCompleted(_ lesson: AcademyLesson) -> Bool { completed.contains(lesson.position) }

    var completedCount: Int { completed.count }

    /// Prochaine leçon à suivre : la première non terminée et accessible.
    var nextLesson: AcademyLesson? {
        lessons.first { !completed.contains($0.position) && isUnlocked($0) }
    }

    enum LearningError: LocalizedError {
        case locked, unknownLesson, notSignedIn
        var errorDescription: String? {
            switch self {
            case .locked:        return t("learning.error.locked")
            case .unknownLesson: return t("lesson.not_found")
            case .notSignedIn:   return t("order.error.not_signed_in")
            }
        }
    }

    /// Termine une leçon et renvoie l'XP réellement gagnée (0 si les missions
    /// du jour étaient déjà validées).
    ///
    /// En mode serveur, l'appel part vers `complete_lesson` et l'état revient
    /// de la base. Le client n'additionne rien : c'est le serveur qui décide si
    /// la mission du jour était déjà validée, donc si cette leçon rapporte.
    @discardableResult
    func complete(lesson position: Int, quizCorrect: Bool?) async throws -> Int {
        guard let lesson = lesson(at: position) else { throw LearningError.unknownLesson }
        guard isUnlocked(lesson) else { throw LearningError.locked }

        switch source {
        case .demo:
            return demoComplete(position: position, quizCorrect: quizCorrect)
        case .server:
            guard let userID else { throw LearningError.notSignedIn }
            let outcome = try await repository.completeLesson(
                userID: userID, position: position, quizCorrect: quizCorrect)

            xp = outcome.xpTotal
            streakDays = outcome.streakDays
            bestStreakDays = max(bestStreakDays, outcome.streakDays)
            lastActivityDay = Calendar.current.startOfDay(for: Date())
            completed.insert(position)
            if quizCorrect == true { quizPassed.insert(position) }

            // Missions et badges ont pu bouger dans la même transaction.
            // Un échec ici ne doit pas faire croire que la leçon a échoué :
            // elle est validée côté serveur, seuls les compteurs d'affichage
            // sont en retard, et le prochain reload les rattrapera.
            try? await refreshMissionsAndBadges(userID: userID)

            return outcome.xpGained
        }
    }

    /// Miroir local de `complete_lesson`, pour le mode démo.
    private func demoComplete(position: Int, quizCorrect: Bool?) -> Int {
        completed.insert(position)
        if quizCorrect == true { quizPassed.insert(position) }

        touchStreak()

        var gained = completeMission("lesson")
        if quizCorrect == true { gained += completeMission("quiz") }

        if completed.count >= 4 { earnedBadges.insert("academy_4") }

        return gained
    }

    // MARK: Missions

    func isMissionDone(_ code: String) -> Bool {
        rolloverIfNeeded()
        return missionsDone.contains(code)
    }

    var missionsDoneCount: Int {
        Self.missions.filter { isMissionDone($0.code) }.count
    }

    /// Valide une mission et crédite son XP une seule fois. Renvoie l'XP
    /// accordée — 0 si elle l'était déjà.
    @discardableResult
    private func completeMission(_ code: String) -> Int {
        rolloverIfNeeded()
        guard let mission = Self.missions.first(where: { $0.code == code }) else { return 0 }
        guard !missionsDone.contains(code) else { return 0 }

        missionsDone.insert(code)
        award(xp: mission.xp)
        return mission.xp
    }

    /// Au changement de jour, seules les missions quotidiennes se réarment.
    ///
    /// Sans effet en mode serveur : c'est `mission_progress.day` qui fait foi,
    /// et réarmer localement afficherait des missions à refaire que le serveur
    /// refuserait ensuite de créditer.
    private func rolloverIfNeeded() {
        guard source == .demo else { return }
        let today = Calendar.current.startOfDay(for: Date())
        guard today != missionsDay else { return }
        missionsDay = today
        let permanent = Set(Self.missions.filter { !$0.isDaily }.map(\.code))
        missionsDone.formIntersection(permanent)
    }

    // MARK: XP, rang, série

    private func award(xp amount: Int) {
        let before = rankLevel
        xp = max(0, xp + amount)
        if rankLevel > before { earnedBadges.insert("rank_up") }
    }

    /// Une activité par jour fait avancer la série ; un jour manqué la remet à 1.
    private func touchStreak() {
        let today = Calendar.current.startOfDay(for: Date())
        guard lastActivityDay != today else { return }

        if let last = lastActivityDay,
           let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today),
           last == yesterday {
            streakDays += 1
        } else {
            streakDays = 1
        }
        lastActivityDay = today
        bestStreakDays = max(bestStreakDays, streakDays)

        if streakDays >= 7 { earnedBadges.insert("streak_7") }
    }

    /// Amorce la démo avec la série visible dans le prototype, sans fausser
    /// l'XP : la série y est un acquis d'usage, pas une récompense.
    func seedDemoStreak(_ days: Int) {
        streakDays = days
        bestStreakDays = max(bestStreakDays, days)
        lastActivityDay = Calendar.current.startOfDay(for: Date())
    }

    /// Vrai si une activité a déjà été enregistrée aujourd'hui — la série est
    /// donc à l'abri jusqu'à demain.
    var isStreakSafeToday: Bool {
        lastActivityDay == Calendar.current.startOfDay(for: Date())
    }
}

// MARK: - Chargement des ressources

extension Bundle {
    /// Décode un JSON de contenu embarqué, dans la langue choisie.
    ///
    /// `lessons.json` est la version française — la langue de rédaction ; une
    /// traduction s'ajoute en déposant `lessons.en.json` à côté, sans toucher au
    /// code. Tant qu'elle n'existe pas, on retombe sur le français : mieux vaut
    /// une leçon lisible dans l'autre langue qu'un écran vide.
    ///
    /// Un échec sur la version française, en revanche, est une erreur de build
    /// (ressource absente ou malformée) : on le signale en console plutôt que de
    /// faire planter l'app.
    func decodeJSON<T: Decodable>(_ name: String) -> T? {
        if L10n.language != .fr,
           let translated: T = decodeJSONFile(localizedName(name, language: L10n.language)) {
            return translated
        }
        return decodeJSONFile(name, required: true)
    }

    /// « lessons.json » + `.en` -> « lessons.en.json ».
    private func localizedName(_ name: String, language: AppLanguage) -> String {
        guard let dot = name.lastIndex(of: ".") else { return "\(name).\(language.rawValue)" }
        return name[..<dot] + ".\(language.rawValue)" + name[dot...]
    }

    private func decodeJSONFile<T: Decodable>(_ name: String, required: Bool = false) -> T? {
        guard let url = url(forResource: name, withExtension: nil),
              let data = try? Data(contentsOf: url) else {
            if required { assertionFailure("Ressource introuvable : \(name)") }
            return nil
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            assertionFailure("Décodage de \(name) impossible : \(error)")
            return nil
        }
    }
}
