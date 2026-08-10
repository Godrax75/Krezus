import Foundation
import Supabase
import PostgREST

/// Profil investisseur : lecture et enregistrement via `save_investor_profile`
/// (0006_oracle.sql).
///
/// Ce n'est **pas** un profil de risque réglementaire (MiFID) et il ne
/// conditionne aucun accès — il n'existe que pour adapter le discours
/// pédagogique de l'Oracle.
@MainActor
struct OracleRepository {

    /// Ce que la base retient du profil. `archetypeKey` est une clé stable
    /// (« guardian »), jamais le libellé traduit : le stocker traduit figerait
    /// le profil dans la langue où il a été rempli.
    struct StoredProfile: Sendable {
        let answers: [String: Int]
        let archetypeKey: String?
        let dna: [String: Int]
    }

    func fetchProfile(userID: UUID) async throws -> StoredProfile? {
        struct Row: Decodable {
            let answers: [String: Int]
            let archetype: String?
            let dna: [String: Int]?
        }
        let client = try SupabaseService.shared.requireClient()
        do {
            let rows: [Row] = try await client
                .from("investor_profile")
                .select("answers, archetype, dna")
                .eq("user_id", value: userID)
                .limit(1)
                .execute()
                .value
            // Un profil jamais rempli n'est pas une erreur : la plupart des
            // comptes n'ont pas encore répondu aux six questions.
            guard let row = rows.first else { return nil }
            return StoredProfile(answers: row.answers,
                                 archetypeKey: row.archetype,
                                 dna: row.dna ?? [:])
        } catch { throw mapPostgrestError(error) }
    }

    /// Enregistre le profil. Le serveur refuse un archétype vide (KR030) : on
    /// n'appelle donc qu'une fois le questionnaire complet.
    func saveProfile(userID: UUID,
                     answers: [String: Int],
                     archetypeKey: String,
                     dna: [String: Int]) async throws {
        let client = try SupabaseService.shared.requireClient()
        do {
            try await client.rpc("save_investor_profile", params: [
                "p_user": AnyJSON.string(userID.uuidString),
                "p_answers": .object(answers.mapValues { .integer($0) }),
                "p_archetype": .string(archetypeKey),
                "p_dna": .object(dna.mapValues { .integer($0) }),
            ]).execute()
        } catch { throw mapPostgrestError(error) }
    }
}
