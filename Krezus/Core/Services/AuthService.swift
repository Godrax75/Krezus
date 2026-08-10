import Foundation
import Observation
import AuthenticationServices
import Supabase

/// Gère l'authentification via Supabase Auth : Sign in with Apple et Google.
/// Le paper trading exige un compte (portefeuille rattaché à `auth.users`), mais
/// aucune donnée réelle n'est manipulée.
@MainActor
@Observable
final class AuthService {
    private(set) var session: Session?
    var isSignedIn: Bool { session != nil }
    var userID: UUID? { session?.user.id }

    /// Restaure une session existante au démarrage (jeton conservé par le SDK).
    func restore() async {
        guard let client = SupabaseService.shared.client else { return }
        session = try? await client.auth.session
    }

    /// Écoute les changements de session (login/logout/refresh).
    func observe() async {
        guard let client = SupabaseService.shared.client else { return }
        for await (event, newSession) in client.auth.authStateChanges {
            switch event {
            case .signedIn, .tokenRefreshed, .initialSession:
                session = newSession
            case .signedOut:
                session = nil
            default:
                break
            }
        }
    }

    // MARK: Sign in with Apple

    /// À appeler depuis le `onCompletion` d'un `SignInWithAppleButton`.
    func signInWithApple(_ credential: ASAuthorizationAppleIDCredential) async throws {
        guard let tokenData = credential.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8) else {
            throw KrezusError.server(t("auth.error.apple_token"))
        }
        let client = try SupabaseService.shared.requireClient()
        session = try await client.auth.signInWithIdToken(
            credentials: .init(provider: .apple, idToken: idToken))
    }

    // MARK: Sign in with Google

    /// Connexion Google via OAuth (flux web + redirection vers le schéma de l'app).
    func signInWithGoogle() async throws {
        let client = try SupabaseService.shared.requireClient()
        guard let redirect = URL(string: "com.krezus.app://login-callback") else { return }
        try await client.auth.signInWithOAuth(provider: .google, redirectTo: redirect)
    }

    /// Termine un flux OAuth ouvert dans le navigateur (deep link de retour).
    func handleOAuthCallback(_ url: URL) async {
        guard let client = SupabaseService.shared.client else { return }
        session = try? await client.auth.session(from: url)
    }

    func signOut() async {
        guard let client = SupabaseService.shared.client else { return }
        try? await client.auth.signOut()
        session = nil
    }
}
