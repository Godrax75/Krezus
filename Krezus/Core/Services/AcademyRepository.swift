import Foundation
import Supabase
import PostgREST

/// Progression Academy côté serveur : XP, rang, série, leçons, missions, badges.
///
/// Comme pour le portefeuille, **rien n'est calculé ici**. L'XP est accordée par
/// `complete_lesson` (0005), qui plafonne le gain aux missions du jour : sans ce
/// plafond côté serveur, enchaîner les 27 leçons d'un coup donnerait le rang
/// maximal en une session, et un client rejouant l'appel s'en fabriquerait
/// autant qu'il veut. Le client envoie l'événement et relit l'état.
@MainActor
struct AcademyRepository {

    /// Agrégat de `v_academy_progress`.
    struct Progress: Decodable, Sendable {
        let xp: Int
        let rankLevel: Int
        let streakDays: Int
        let lessonsDone: Int
        let quizzesPassed: Int

        enum CodingKeys: String, CodingKey {
            case xp
            case rankLevel = "rank_level"
            case streakDays = "streak_days"
            case lessonsDone = "lessons_done"
            case quizzesPassed = "quizzes_passed"
        }
    }

    /// Une leçon terminée, ramenée à sa **position** — la clé qu'utilise toute
    /// l'app (et les fichiers `lessons.json`). L'UUID ne sort pas d'ici.
    struct LessonProgress: Sendable {
        let position: Int
        let quizCorrect: Bool
    }

    /// Retour de `complete_lesson`.
    struct LessonOutcome: Decodable, Sendable {
        let xpGained: Int
        let xpTotal: Int
        let rankLevel: Int
        let streakDays: Int

        enum CodingKeys: String, CodingKey {
            case xpGained = "xp_gained"
            case xpTotal = "xp_total"
            case rankLevel = "rank_level"
            case streakDays = "streak_days"
        }
    }

    // MARK: Lecture

    func fetchProgress(userID: UUID) async throws -> Progress {
        let client = try SupabaseService.shared.requireClient()
        do {
            return try await client
                .from("v_academy_progress")
                .select()
                .eq("user_id", value: userID)
                .single()
                .execute()
                .value
        } catch { throw mapPostgrestError(error) }
    }

    /// Leçons terminées, avec le résultat de leur quiz.
    func fetchLessonProgress(userID: UUID) async throws -> [LessonProgress] {
        struct Row: Decodable {
            let quizCorrect: Bool?
            let lessons: Nested
            struct Nested: Decodable { let position: Int }
            enum CodingKeys: String, CodingKey {
                case quizCorrect = "quiz_correct"
                case lessons
            }
        }
        let client = try SupabaseService.shared.requireClient()
        do {
            let rows: [Row] = try await client
                .from("lesson_progress")
                .select("quiz_correct, lessons(position)")
                .eq("user_id", value: userID)
                // `is.null` attend le littéral PostgREST, pas un nil Swift :
                // le SDK sérialise la valeur telle quelle dans la query.
                .not("completed_at", operator: .is, value: "null")
                .execute()
                .value
            return rows.map {
                LessonProgress(position: $0.lessons.position, quizCorrect: $0.quizCorrect ?? false)
            }
        } catch { throw mapPostgrestError(error) }
    }

    /// Codes des missions validées **aujourd'hui**. Le serveur indexe
    /// `mission_progress` par jour ; filtrer sur la date évite de rapatrier
    /// tout l'historique pour n'en afficher que trois pastilles.
    ///
    /// ⚠️ Écart connu : `complete_mission` écrit `current_date`, évalué dans le
    /// fuseau de la base (UTC chez Supabase), alors que le filtre ci-dessous
    /// utilise le jour de l'appareil. Entre minuit et 2 h en France, les deux
    /// divergent et les pastilles peuvent se réarmer avec quelques heures
    /// d'avance. C'est cosmétique — l'XP, elle, reste plafonnée par le serveur,
    /// qui refuse de la créditer deux fois. Le vrai correctif est côté base
    /// (fuseau de session explicite, ou `current_date` renvoyé par la vue) ;
    /// il n'est pas fait ici pour ne pas modifier seul le contrat SQL.
    func fetchMissionsDone(userID: UUID, on day: Date = Date()) async throws -> Set<String> {
        struct Row: Decodable {
            let missions: Nested
            struct Nested: Decodable { let code: String }
        }
        let client = try SupabaseService.shared.requireClient()
        do {
            let rows: [Row] = try await client
                .from("mission_progress")
                .select("missions(code)")
                .eq("user_id", value: userID)
                .eq("day", value: Self.dayFormatter.string(from: day))
                .not("done_at", operator: .is, value: "null")
                .execute()
                .value
            return Set(rows.map(\.missions.code))
        } catch { throw mapPostgrestError(error) }
    }

    func fetchBadges(userID: UUID) async throws -> Set<String> {
        struct Row: Decodable {
            let badges: Nested
            struct Nested: Decodable { let code: String }
        }
        let client = try SupabaseService.shared.requireClient()
        do {
            let rows: [Row] = try await client
                .from("user_badges")
                .select("badges(code)")
                .eq("user_id", value: userID)
                .execute()
                .value
            return Set(rows.map(\.badges.code))
        } catch { throw mapPostgrestError(error) }
    }

    // MARK: Écriture

    /// Termine une leçon désignée par sa position.
    ///
    /// `complete_lesson` attend l'UUID de la leçon ; l'app ne connaît que les
    /// positions, qui sont la clé stable du contenu éditorial (`position` est
    /// `unique` dans `lessons`). La résolution se fait donc ici, en un aller
    /// supplémentaire — plutôt que d'infiltrer des UUID serveur dans des
    /// fichiers JSON embarqués, qui seraient faux dès le premier reseed.
    @discardableResult
    func completeLesson(userID: UUID,
                        position: Int,
                        quizCorrect: Bool?) async throws -> LessonOutcome {
        let client = try SupabaseService.shared.requireClient()
        do {
            let lessonID = try await lessonID(position: position)
            var params: [String: AnyJSON] = [
                "p_user": .string(userID.uuidString),
                "p_lesson": .string(lessonID.uuidString),
            ]
            // `default null` côté SQL : ne rien envoyer quand la leçon n'a pas
            // de quiz, plutôt qu'un `false` qui signifierait « raté ».
            if let quizCorrect { params["p_quiz_correct"] = .bool(quizCorrect) }

            return try await client.rpc("complete_lesson", params: params)
                .single().execute().value
        } catch { throw mapPostgrestError(error) }
    }

    /// Historise une tentative de quiz (écran de progression).
    func recordQuizAttempt(userID: UUID, score: Int, total: Int) async throws {
        let client = try SupabaseService.shared.requireClient()
        do {
            try await client.rpc("record_quiz_attempt", params: [
                "p_user": AnyJSON.string(userID.uuidString),
                "p_score": .integer(score),
                "p_total": .integer(total),
            ]).execute()
        } catch { throw mapPostgrestError(error) }
    }

    // MARK: Interne

    private func lessonID(position: Int) async throws -> UUID {
        struct Row: Decodable { let id: UUID }
        let client = try SupabaseService.shared.requireClient()
        let row: Row = try await client
            .from("lessons")
            .select("id")
            .eq("position", value: position)
            .single()
            .execute()
            .value
        return row.id
    }

    /// `mission_progress.day` est une `date` nue : la formater en UTC
    /// produirait la veille pour un utilisateur français avant 2 h du matin.
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
