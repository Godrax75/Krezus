import Foundation
import Supabase

/// Accès à `public.notifications` et à l'enregistrement du jeton de push.
///
/// Le jeton passe par la RPC `upsert_device_token` plutôt que par un `insert`
/// direct : la fonction gère la reprise d'un jeton réattribué à un autre compte
/// (réinstallation, appareil revendu), ce qu'un `upsert` client ne saurait pas
/// faire sans droit d'écriture sur les lignes d'autrui.
@MainActor
struct NotificationsRepository {

    /// Ligne brute de `public.notifications`.
    private struct Row: Codable {
        let id: UUID
        let kind: String
        let title: String
        let body: String?
        let readAt: Date?
        let createdAt: Date

        enum CodingKeys: String, CodingKey {
            case id, kind, title, body
            case readAt = "read_at"
            case createdAt = "created_at"
        }
    }

    func fetch(userID: UUID, limit: Int = 50) async throws -> [KrezusNotification] {
        let client = try SupabaseService.shared.requireClient()
        let rows: [Row] = try await client
            .from("notifications")
            .select()
            .eq("user_id", value: userID)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value

        return rows.compactMap { row in
            // Un `kind` inconnu du client vient d'un serveur plus récent :
            // l'ignorer vaut mieux qu'afficher une ligne sans icône ni sens.
            guard let kind = KrezusNotification.Kind(rawValue: row.kind) else { return nil }
            return KrezusNotification(
                id: row.id, kind: kind, title: row.title, body: row.body,
                createdAt: row.createdAt, readAt: row.readAt)
        }
    }

    func markRead(ids: [UUID], userID: UUID) async throws {
        guard !ids.isEmpty else { return }
        let client = try SupabaseService.shared.requireClient()
        try await client
            .from("notifications")
            .update(["read_at": AnyJSON.string(ISO8601DateFormatter().string(from: Date()))])
            .eq("user_id", value: userID)
            .in("id", values: ids.map(\.uuidString))
            .execute()
    }

    // MARK: Jeton de push

    func registerDeviceToken(_ token: String, userID: UUID) async throws {
        let client = try SupabaseService.shared.requireClient()
        try await client.rpc("upsert_device_token", params: [
            "p_user_id": AnyJSON.string(userID.uuidString),
            "p_token": .string(token),
            "p_platform": .string("ios"),
        ]).execute()
    }

    func unregisterDeviceToken(_ token: String) async throws {
        let client = try SupabaseService.shared.requireClient()
        try await client.rpc("delete_device_token",
                             params: ["p_token": token]).execute()
    }

    // MARK: Suppression de compte

    /// Supprime le compte et toutes ses données (guideline App Store 5.1.1(v)
    /// et droit à l'effacement du RGPD). Le `on delete cascade` du schéma fait
    /// le reste : portefeuille, ordres, progression, messages Hercule.
    func deleteAccount() async throws {
        let client = try SupabaseService.shared.requireClient()
        try await client.rpc("delete_own_account").execute()
    }
}
