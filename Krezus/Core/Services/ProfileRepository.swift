import Foundation
import Supabase

/// Lecture / mise à jour du profil utilisateur (créé automatiquement à
/// l'inscription par le trigger `handle_new_user`).
@MainActor
struct ProfileRepository {

    func fetch(userID: UUID) async throws -> Profile {
        let client = try SupabaseService.shared.requireClient()
        return try await client
            .from("profiles")
            .select()
            .eq("id", value: userID)
            .single()
            .execute()
            .value
    }

    func updatePreferences(userID: UUID, darkMode: Bool, locale: String) async throws {
        let client = try SupabaseService.shared.requireClient()
        try await client
            .from("profiles")
            .update(["dark_mode": AnyJSON.bool(darkMode), "locale": .string(locale)])
            .eq("id", value: userID)
            .execute()
    }

    func updateUsername(userID: UUID, username: String) async throws {
        let client = try SupabaseService.shared.requireClient()
        try await client
            .from("profiles")
            .update(["username": username])
            .eq("id", value: userID)
            .execute()
    }
}
