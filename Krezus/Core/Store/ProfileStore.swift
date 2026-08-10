import SwiftUI
import Observation

/// Identité du compte : pseudo, prénom/nom, date d'inscription.
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

    private(set) var isSaving = false
    private(set) var lastError: String?

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
        guard AppConfig.isConfigured, let userID else { return }
        guard let profile = try? await repository.fetch(userID: userID) else { return }
        apply(profile)
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
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
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
            try await repository.updateUsername(userID: userID, username: trimmed)
        }
        username = trimmed
        lastError = nil
    }
}
