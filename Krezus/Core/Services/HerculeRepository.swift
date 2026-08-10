import Foundation
import Supabase
import Functions
import PostgREST

/// Chat Hercule : quota, historique, et appel de la Edge Function `hercule`.
///
/// L'app ne parle **jamais** à la Claude API directement : la clé Anthropic
/// vivrait alors dans le binaire, extractible en quelques minutes. La fonction
/// serveur détient la clé, vérifie le JWT, décompte le quota en base — puis
/// appelle le modèle. Le quota se compte côté serveur pour la même raison que
/// le cash : un client qui rejoue une requête ne doit pas s'offrir de messages.
@MainActor
struct HerculeRepository {

    /// Retour de `hercule_quota`.
    struct Quota: Decodable, Sendable {
        let isPremium: Bool
        let usedToday: Int
        let dailyQuota: Int
        let remaining: Int

        enum CodingKeys: String, CodingKey {
            case isPremium = "is_premium"
            case usedToday = "used_today"
            case dailyQuota = "daily_quota"
            case remaining
        }
    }

    /// Réponse de la Edge Function.
    struct Reply: Decodable, Sendable {
        let answer: String
        /// `nil` quand l'abonnement rend le décompte sans objet.
        let remaining: Int?
        /// Vrai quand le modèle a décliné : l'app le rend comme une réponse
        /// normale plutôt que comme une panne.
        let refused: Bool?
    }

    struct StoredMessage: Sendable {
        let role: String
        let content: String
        let createdAt: Date
    }

    func fetchQuota(userID: UUID) async throws -> Quota {
        let client = try SupabaseService.shared.requireClient()
        do {
            return try await client
                .rpc("hercule_quota", params: ["p_user": userID.uuidString])
                .single()
                .execute()
                .value
        } catch { throw mapPostgrestError(error) }
    }

    /// Historique de la conversation, du plus ancien au plus récent.
    func fetchHistory(userID: UUID, limit: Int = 40) async throws -> [StoredMessage] {
        struct Row: Decodable {
            let role: String
            let content: String
            let createdAt: Date
            enum CodingKeys: String, CodingKey {
                case role, content
                case createdAt = "created_at"
            }
        }
        let client = try SupabaseService.shared.requireClient()
        do {
            // Trié décroissant pour que la limite garde les messages **récents**,
            // puis remis à l'endroit : une limite sur un tri croissant
            // couperait la fin de la conversation au lieu du début.
            let rows: [Row] = try await client
                .from("hercule_messages")
                .select("role, content, created_at")
                .eq("user_id", value: userID)
                .order("created_at", ascending: false)
                .limit(limit)
                .execute()
                .value
            return rows.reversed().map {
                StoredMessage(role: $0.role, content: $0.content, createdAt: $0.createdAt)
            }
        } catch { throw mapPostgrestError(error) }
    }

    /// Pose une question. C'est la fonction serveur qui enregistre l'échange et
    /// renvoie le quota restant — le client ne décompte rien lui-même.
    func ask(_ question: String) async throws -> Reply {
        struct Body: Encodable { let question: String }
        let client = try SupabaseService.shared.requireClient()
        do {
            return try await client.functions.invoke(
                "hercule", options: FunctionInvokeOptions(body: Body(question: question)))
        } catch let error as FunctionsError {
            throw Self.mapped(error)
        }
    }

    /// La Edge Function répond 429 avec `{ error: "quota_exhausted" }` quand le
    /// quota est épuisé. Sans ce mapping, l'utilisateur verrait une erreur HTTP
    /// brute là où le message métier existe déjà.
    private static func mapped(_ error: FunctionsError) -> Error {
        if case .httpError(let code, _) = error, code == 429 {
            return KrezusError.herculeQuotaReached
        }
        return error
    }
}
