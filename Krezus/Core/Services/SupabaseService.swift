import Foundation
import Supabase
import PostgREST

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

/// Erreurs applicatives, dont le mapping de la classe SQLSTATE privée « KR »
/// que se partagent les migrations.
///
/// Le mapping n'est pas une commodité : les messages levés par PL/pgSQL sont
/// **rédigés en français en dur** dans les migrations. Un code non mappé tombe
/// dans `.server(message)` et affiche donc du français à un utilisateur
/// anglophone. Toute nouvelle exception `using errcode = 'KR…'` doit arriver
/// ici en même temps que dans le SQL.
enum KrezusError: LocalizedError {
    case notConfigured

    // Moteur d'ordres papier (0002)
    case insufficientFunds      // KR001
    case notFound               // KR002
    case quoteUnavailable       // KR003
    case quoteStale             // KR004
    case invalidParameter       // KR010

    // Academy (0005)
    case lessonNotFound         // KR020
    case lessonPremiumOnly      // KR021
    case unknownMission         // KR022

    // Oracle (0006)
    case invalidInvestorProfile // KR030

    // Arena (0007)
    case userNotFound           // KR040
    case friendRequestRejected  // KR041 — soi-même, ou lien déjà existant
    case noPendingRequest       // KR042
    case invalidInviteCode      // KR043
    case alreadyInGroup         // KR044

    // Hercule (0008)
    case herculeQuotaReached    // KR050
    case herculeInvalidMessage  // KR051
    case invalidReceipt         // KR052

    // Parrainage (0019)
    case referralUnknownCode    // KR070
    case referralNotAllowed     // KR071 — son propre code, ou celui de son filleul
    case referralAlreadyUsed    // KR072
    case referralExpired        // KR073 — plus de sept jours après l'inscription

    case server(String)

    /// Mappe un code SQLSTATE renvoyé par PostgREST vers une erreur typée.
    static func from(sqlState: String, message: String) -> KrezusError {
        switch sqlState {
        case "KR001": return .insufficientFunds
        case "KR002": return .notFound
        case "KR003": return .quoteUnavailable
        case "KR004": return .quoteStale
        case "KR010": return .invalidParameter
        case "KR020": return .lessonNotFound
        case "KR021": return .lessonPremiumOnly
        case "KR022": return .unknownMission
        case "KR030": return .invalidInvestorProfile
        case "KR040": return .userNotFound
        case "KR041": return .friendRequestRejected
        case "KR042": return .noPendingRequest
        case "KR043": return .invalidInviteCode
        case "KR044": return .alreadyInGroup
        case "KR050": return .herculeQuotaReached
        case "KR051": return .herculeInvalidMessage
        case "KR052": return .invalidReceipt
        case "KR070": return .referralUnknownCode
        case "KR071": return .referralNotAllowed
        case "KR072": return .referralAlreadyUsed
        case "KR073": return .referralExpired
        default:      return .server(message)
        }
    }

    var errorDescription: String? {
        switch self {
        case .notConfigured:          return t("backend.error.not_configured")
        case .insufficientFunds:      return t("order.error.insufficient_funds")
        case .notFound:               return t("backend.error.not_found")
        case .quoteUnavailable:       return t("backend.error.quote_unavailable")
        case .quoteStale:             return t("backend.error.quote_stale")
        case .invalidParameter:       return t("backend.error.invalid_amount")
        case .lessonNotFound:         return t("lesson.not_found")
        case .lessonPremiumOnly:      return t("learning.error.locked")
        case .unknownMission:         return t("backend.error.unknown_mission")
        case .invalidInvestorProfile: return t("backend.error.invalid_profile")
        case .userNotFound:           return t("backend.error.user_not_found")
        case .friendRequestRejected:  return t("backend.error.friend_request_rejected")
        case .noPendingRequest:       return t("backend.error.no_pending_request")
        case .invalidInviteCode:      return t("backend.error.invalid_invite_code")
        case .alreadyInGroup:         return t("backend.error.already_in_group")
        case .herculeQuotaReached:    return t("backend.error.hercule_quota")
        case .herculeInvalidMessage:  return t("backend.error.hercule_message")
        case .invalidReceipt:         return t("backend.error.invalid_receipt")
        case .referralUnknownCode:    return t("referral.error.unknown")
        case .referralNotAllowed:     return t("referral.error.not_allowed")
        case .referralAlreadyUsed:    return t("referral.error.already_used")
        case .referralExpired:        return t("referral.error.expired")
        case .server(let m):          return m
        }
    }
}

/// Traduit une erreur PostgREST portant un code SQLSTATE « KR » en `KrezusError`.
/// Partagé par tous les repositories : le mapping ne doit exister qu'une fois.
func mapPostgrestError(_ error: Error) -> Error {
    if let pg = error as? PostgrestError, let code = pg.code {
        return KrezusError.from(sqlState: code, message: pg.message)
    }
    return error
}
