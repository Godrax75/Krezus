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
/// En mode démo c'est la source de vérité. La logique reproduit celle des
/// fonctions Postgres de `0005_academy.sql` — notamment le fait que l'XP vient
/// des **missions du jour** et non de chaque leçon : sans ce plafond, enchaîner
/// les 27 leçons d'un coup donnerait le rang maximal en une session.
@MainActor
@Observable
final class LearningStore {

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

    init() {
        loadContent()
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
        case locked, unknownLesson
        var errorDescription: String? {
            switch self {
            case .locked:        return t("learning.error.locked")
            case .unknownLesson: return t("lesson.not_found")
            }
        }
    }

    /// Termine une leçon et renvoie l'XP réellement gagnée (0 si les missions
    /// du jour étaient déjà validées). Miroir de `complete_lesson`.
    @discardableResult
    func complete(lesson position: Int, quizCorrect: Bool?) throws -> Int {
        guard let lesson = lesson(at: position) else { throw LearningError.unknownLesson }
        guard isUnlocked(lesson) else { throw LearningError.locked }

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
    private func rolloverIfNeeded() {
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
