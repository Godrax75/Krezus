import SwiftUI
import UIKit
import Observation

/// Identité du compte : pseudo, photo, prénom/nom, date d'inscription.
///
/// La progression (XP, rang, série) reste dans `LearningStore` — une seule
/// source de vérité — et les montants dans `TradingStore`. Ce store ne porte
/// que ce qui identifie l'utilisateur.
@MainActor
@Observable
final class ProfileStore {

    private(set) var username: String = "Louis"
    private(set) var firstName: String?
    private(set) var lastName: String?
    private(set) var memberSince: Date = Calendar.current.date(
        byAdding: .day, value: -34, to: Date()) ?? Date()

    /// Le compte a-t-il choisi son pseudo ? Tant qu'on ne le sait pas, on
    /// attend ; un compte sans pseudo passe par l'accueil avant l'app.
    enum Setup: Equatable { case unknown, needed, done }
    private(set) var setup: Setup = .unknown

    private(set) var isSaving = false
    private(set) var lastError: String?

    /// Photo de profil, déjà décodée. Nil = initiale dans une pastille.
    private(set) var avatar: UIImage?
    private(set) var isUpdatingAvatar = false

    private let repository = ProfileRepository()

    /// Initiale affichée dans l'avatar. Repli sur « K » plutôt que sur une
    /// pastille vide si le pseudo est effacé côté serveur.
    var initial: String {
        String(username.first.map(String.init)?.uppercased() ?? "K")
    }

    var memberSinceLabel: String {
        memberSince.formatted(.dateTime.month(.wide).year().locale(L10n.locale))
    }

    // MARK: Chargement

    func load(userID: UUID?) async {
        guard AppConfig.isConfigured, let userID else {
            // Mode démo : la photo ne vit que sur l'appareil.
            if avatar == nil { avatar = AvatarCache.loadDemo() }
            setup = userID == nil ? .unknown : .done
            return
        }
        guard let profile = try? await repository.fetch(userID: userID) else {
            // Sans réseau, on n'enferme pas l'utilisateur dans l'accueil :
            // il le reverra au prochain lancement si le pseudo manque.
            if setup == .unknown { setup = .done }
            return
        }
        apply(profile)
        // L'accueil en cours ne se referme pas sous les pieds de
        // l'utilisateur quand son pseudo vient d'être enregistré.
        if setup != .needed { setup = profile.username == nil ? .needed : .done }
        await loadAvatar(userID: userID, version: profile.avatarUpdatedAt)
    }

    /// Le cache est indexé sur la date de la photo : une photo changée depuis
    /// un autre appareil porte une autre date, donc se retélécharge.
    private func loadAvatar(userID: UUID, version: Date?) async {
        guard let version else {
            avatar = nil
            AvatarCache.clear(userID: userID)
            return
        }
        if let cached = AvatarCache.load(userID: userID, version: version) {
            avatar = cached
            return
        }
        guard let data = try? await repository.downloadAvatar(userID: userID),
              let image = UIImage(data: data) else { return }
        avatar = image
        AvatarCache.store(data, userID: userID, version: version)
    }

    // MARK: Photo de profil

    /// Recadre, réduit, envoie. L'image affichée change immédiatement, mais
    /// n'est gardée qu'une fois l'envoi réussi : sinon on reprend l'ancienne.
    func setAvatar(_ image: UIImage, userID: UUID?) async throws {
        guard let jpeg = AvatarImage.prepare(image), let prepared = UIImage(data: jpeg) else {
            throw KrezusError.server(t("avatar.error.unreadable"))
        }
        let previous = avatar
        avatar = prepared
        isUpdatingAvatar = true
        defer { isUpdatingAvatar = false }

        guard AppConfig.isConfigured, let userID else {
            AvatarCache.storeDemo(jpeg)
            return
        }
        do {
            let version = try await repository.uploadAvatar(userID: userID, jpeg: jpeg)
            AvatarCache.store(jpeg, userID: userID, version: version)
        } catch {
            avatar = previous
            throw error
        }
    }

    func removeAvatar(userID: UUID?) async throws {
        isUpdatingAvatar = true
        defer { isUpdatingAvatar = false }
        guard AppConfig.isConfigured, let userID else {
            AvatarCache.clearDemo()
            avatar = nil
            return
        }
        try await repository.removeAvatar(userID: userID)
        AvatarCache.clear(userID: userID)
        avatar = nil
    }

    private func apply(_ profile: Profile) {
        username = profile.username ?? profile.firstName ?? t("profile.default_username")
        firstName = profile.firstName
        lastName = profile.lastName
    }

    // MARK: Pseudo

    enum UsernameError: LocalizedError {
        case tooShort, tooLong, invalidCharacters

        var errorDescription: String? {
            switch self {
            case .tooShort:          return t("username.error.too_short")
            case .tooLong:           return t("username.error.too_long")
            case .invalidCharacters: return t("username.error.invalid_characters")
            }
        }
    }

    /// Valide un pseudo sans l'enregistrer — utilisé pour l'aide à la saisie.
    ///
    /// Le pseudo est public : il apparaît au classement Arena et dans le feed
    /// des amis. On le contraint donc à un jeu de caractères sobre, sans
    /// espaces ni emoji, qui ne casse ni le tri ni la lecture des lignes.
    static func validate(_ raw: String) -> UsernameError? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.count < 3 { return .tooShort }
        if trimmed.count > 20 { return .tooLong }
        // Même règle que `is_valid_username` (0021) : ASCII seulement, un
        // « é » ou un chiffre arabe passeraient `alphanumerics`, pas le serveur.
        let allowed = CharacterSet(charactersIn:
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
        if trimmed.unicodeScalars.contains(where: { !allowed.contains($0) }) {
            return .invalidCharacters
        }
        return nil
    }

    /// Enregistre le pseudo. Lève si la validation échoue ; l'écriture serveur
    /// n'est tentée qu'ensuite, pour ne pas propager une valeur invalide.
    func updateUsername(_ raw: String, userID: UUID?) async throws {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if let error = Self.validate(trimmed) { throw error }

        isSaving = true
        defer { isSaving = false }

        if AppConfig.isConfigured, let userID {
            try await repository.setIdentity(firstName: nil, username: trimmed)
        }
        username = trimmed
        lastError = nil
    }

    // MARK: Accueil

    /// Disponibilité d'un pseudo : `nil` si le serveur n'a pas répondu (ou en
    /// démo), auquel cas c'est l'enregistrement qui tranchera.
    func isUsernameAvailable(_ raw: String) async -> Bool? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard Self.validate(trimmed) == nil else { return false }
        guard AppConfig.isConfigured else { return nil }
        return try? await repository.isUsernameAvailable(trimmed)
    }

    /// Prénom et pseudo choisis à l'accueil.
    func saveIdentity(firstName raw: String, username rawUsername: String, userID: UUID?) async throws {
        let trimmed = rawUsername.trimmingCharacters(in: .whitespaces)
        if let error = Self.validate(trimmed) { throw error }
        let first = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        isSaving = true
        defer { isSaving = false }

        if AppConfig.isConfigured, userID != nil {
            try await repository.setIdentity(firstName: first.isEmpty ? nil : first, username: trimmed)
        }
        username = trimmed
        if !first.isEmpty { firstName = first }
    }

    /// Fin de l'accueil : l'app s'ouvre.
    func finishSetup() { setup = .done }
}
