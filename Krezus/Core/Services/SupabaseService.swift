import Foundation
import Supabase

/// Point d'accès unique au client Supabase. `nil` tant que les secrets ne sont
/// pas renseignés — l'app tourne alors en mode démo (données locales, Lot 1).
@MainActor
final class SupabaseService {
    static let shared = SupabaseService()

    let client: SupabaseClient?

    private init() {
        if let url = AppConfig.supabaseURL, AppConfig.isConfigured {
            client = SupabaseClient(supabaseURL: url, supabaseKey: AppConfig.supabaseAnonKey)
        } else {
            client = nil
        }
    }

    /// Client garanti non-nil ; lève si l'app n'est pas configurée.
    func requireClient() throws -> SupabaseClient {
        guard let client else { throw KrezusError.notConfigured }
        return client
    }
}

/// Erreurs applicatives, dont le mapping des codes SQLSTATE « KR » du moteur d'ordres.
enum KrezusError: LocalizedError {
    case notConfigured
    case insufficientFunds      // KR001
    case notFound               // KR002
    case quoteUnavailable       // KR003
    case quoteStale             // KR004
    case invalidParameter       // KR010
    case server(String)

    /// Mappe un code SQLSTATE renvoyé par PostgREST vers une erreur typée.
    static func from(sqlState: String, message: String) -> KrezusError {
        switch sqlState {
        case "KR001": return .insufficientFunds
        case "KR002": return .notFound
        case "KR003": return .quoteUnavailable
        case "KR004": return .quoteStale
        case "KR010": return .invalidParameter
        default:      return .server(message)
        }
    }

    var errorDescription: String? {
        switch self {
        case .notConfigured:     return t("backend.error.not_configured")
        case .insufficientFunds: return t("order.error.insufficient_funds")
        case .notFound:          return t("backend.error.not_found")
        case .quoteUnavailable:  return t("backend.error.quote_unavailable")
        case .quoteStale:        return t("backend.error.quote_stale")
        case .invalidParameter:  return t("backend.error.invalid_amount")
        case .server(let m):     return m
        }
    }
}
