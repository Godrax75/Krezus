import Foundation
import Observation
import AuthenticationServices
import Supabase

/// Gère l'authentification via Supabase Auth : Sign in with Apple, Google, et
/// e-mail avec mot de passe. Le paper trading exige un compte (portefeuille
/// rattaché à `auth.users`), mais aucune donnée réelle n'est manipulée.
@MainActor
@Observable
final class AuthService {
    private(set) var session: Session?
    var isSignedIn: Bool { session != nil }
    var userID: UUID? { session?.user.id }

    /// Vrai entre l'ouverture d'un lien de réinitialisation et l'enregistrement
    /// du nouveau mot de passe : l'aiguillage racine affiche alors l'écran
    /// dédié plutôt que l'app. Le lien ouvre une session valide — sans ce
    /// drapeau, l'utilisateur entrerait dans l'app sans jamais choisir son
    /// nouveau mot de passe.
    private(set) var isRecoveringPassword = false

    /// Retour des e-mails de confirmation et des connexions OAuth. Doit figurer
    /// dans les « Redirect URLs » de Supabase, sans quoi le lien retombe sur la
    /// Site URL.
    static let loginCallback = URL(string: "com.krezus.app://login-callback")!

    /// Retour des e-mails de réinitialisation. Une adresse distincte, parce
    /// qu'en flux PKCE le lien revient avec un simple `?code=` : rien d'autre
    /// ne le distingue d'une connexion ordinaire. Doit aussi figurer dans les
    /// « Redirect URLs » de Supabase.
    static let resetCallback = URL(string: "com.krezus.app://reset-callback")!

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
            case .passwordRecovery:
                // Flux implicite : le SDK reconnaît lui-même le lien.
                session = newSession
                isRecoveringPassword = true
            case .signedOut:
                session = nil
                isRecoveringPassword = false
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
        try await client.auth.signInWithOAuth(provider: .google, redirectTo: Self.loginCallback)
    }

    // MARK: E-mail et mot de passe

    enum SignUpOutcome {
        /// Le projet ne demande pas de confirmation : la session est ouverte.
        case signedIn
        /// Un e-mail de confirmation est parti ; aucune session tant qu'il
        /// n'est pas ouvert.
        case confirmationSent
    }

    func signUp(email: String, password: String) async throws -> SignUpOutcome {
        let client = try SupabaseService.shared.requireClient()
        let response = try await client.auth.signUp(
            email: email, password: password, redirectTo: Self.loginCallback)
        if let newSession = response.session {
            session = newSession
            return .signedIn
        }
        return .confirmationSent
    }

    func signIn(email: String, password: String) async throws {
        let client = try SupabaseService.shared.requireClient()
        session = try await client.auth.signIn(email: email, password: password)
    }

    func resendConfirmation(email: String) async throws {
        let client = try SupabaseService.shared.requireClient()
        try await client.auth.resend(email: email, type: .signup, emailRedirectTo: Self.loginCallback)
    }

    func sendPasswordReset(email: String) async throws {
        let client = try SupabaseService.shared.requireClient()
        try await client.auth.resetPasswordForEmail(email, redirectTo: Self.resetCallback)
    }

    /// Enregistre le nouveau mot de passe, puis rend la main à l'app : la
    /// session ouverte par le lien est déjà la bonne.
    func updatePassword(_ newPassword: String) async throws {
        let client = try SupabaseService.shared.requireClient()
        _ = try await client.auth.update(user: UserAttributes(password: newPassword))
        isRecoveringPassword = false
    }

    /// Termine un flux ouvert hors de l'app — connexion OAuth, confirmation
    /// d'e-mail ou réinitialisation de mot de passe (deep link de retour).
    func handleOAuthCallback(_ url: URL) async {
        guard let client = SupabaseService.shared.client else { return }
        // Le drapeau se lève avant l'échange : le SDK émet `.signedIn` pendant
        // l'appel, et l'aiguillage montrerait l'app un instant avant l'écran
        // du nouveau mot de passe.
        let isReset = url.host == Self.resetCallback.host
        if isReset { isRecoveringPassword = true }
        guard let newSession = try? await client.auth.session(from: url) else {
            if isReset { isRecoveringPassword = false }
            return
        }
        session = newSession
    }

    func signOut() async {
        guard let client = SupabaseService.shared.client else { return }
        try? await client.auth.signOut()
        session = nil
        isRecoveringPassword = false
    }
}
