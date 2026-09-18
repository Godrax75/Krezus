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

    // MARK: Photo de profil

    /// Bucket privé : seul le propriétaire lit et écrit son dossier.
    static let avatarBucket = "avatars"

    /// Un seul fichier par utilisateur, écrasé à chaque changement.
    static func avatarPath(for userID: UUID) -> String {
        "\(userID.uuidString.lowercased())/avatar.jpg"
    }

    /// Envoie la photo puis date le profil. Deux écritures sans transaction :
    /// si la seconde échoue, le fichier existe mais le profil l'ignore, et le
    /// prochain envoi l'écrasera — l'inverse (profil daté, fichier absent)
    /// afficherait une photo introuvable.
    func uploadAvatar(userID: UUID, jpeg: Data) async throws -> Date {
        let client = try SupabaseService.shared.requireClient()
        try await client.storage
            .from(Self.avatarBucket)
            .upload(Self.avatarPath(for: userID), data: jpeg,
                    options: FileOptions(contentType: "image/jpeg", upsert: true))
        let now = Date()
        try await client
            .from("profiles")
            .update(["avatar_updated_at": AnyJSON.string(ISO8601DateFormatter().string(from: now))])
            .eq("id", value: userID)
            .execute()
        return now
    }

    func downloadAvatar(userID: UUID) async throws -> Data {
        let client = try SupabaseService.shared.requireClient()
        return try await client.storage
            .from(Self.avatarBucket)
            .download(path: Self.avatarPath(for: userID))
    }

    /// Retire la date du profil d'abord : une photo qui échoue à se supprimer
    /// cesse au moins d'être affichée.
    func removeAvatar(userID: UUID) async throws {
        let client = try SupabaseService.shared.requireClient()
        try await client
            .from("profiles")
            .update(["avatar_updated_at": AnyJSON.null])
            .eq("id", value: userID)
            .execute()
        _ = try await client.storage
            .from(Self.avatarBucket)
            .remove(paths: [Self.avatarPath(for: userID)])
    }
}
