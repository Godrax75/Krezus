import Foundation

/// Configuration d'exécution, lue depuis l'Info.plist (valeurs injectées par
/// `Secrets.xcconfig` au build). Aucune clé n'est codée en dur dans le binaire
/// source ; le fichier de secrets n'est pas versionné.
enum AppConfig {

    /// Référence du projet Supabase (ex. « abcdefgh »).
    static let supabaseProjectRef = infoString("SUPABASE_PROJECT_REF")

    /// Clé publique « anon » (JWT) — sûre côté client, les droits sont bornés par RLS.
    static let supabaseAnonKey = infoString("SUPABASE_ANON_KEY")

    /// ID client Google OAuth (vide = connexion Google masquée).
    static let googleClientID = infoString("GOOGLE_OAUTH_CLIENT_ID")

    /// URL du projet Supabase, reconstruite depuis la référence.
    static var supabaseURL: URL? {
        guard isConfigured else { return nil }
        return URL(string: "https://\(supabaseProjectRef).supabase.co")
    }

    /// Vrai si les secrets Supabase ont été renseignés (pas les placeholders).
    static var isConfigured: Bool {
        !supabaseProjectRef.isEmpty
            && supabaseProjectRef != "your-project-ref"
            && !supabaseAnonKey.isEmpty
            && supabaseAnonKey != "your-anon-key-jwt"
    }

    private static func infoString(_ key: String) -> String {
        (Bundle.main.object(forInfoDictionaryKey: key) as? String)?
            .trimmingCharacters(in: .whitespaces) ?? ""
    }
}
