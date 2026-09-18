import Foundation
import Supabase

/// Parrainage (migration 0019) : l'état du compte et la saisie d'un code.
/// Toute la règle — délai, plafond, XP — vit dans `redeem_referral_code`.
@MainActor
struct ReferralRepository {

    struct Status: Decodable, Sendable {
        let code: String
        let referredCount: Int
        let xpEarned: Int
        /// Vrai tant que le compte a moins de sept jours et n'a pas de parrain.
        let canRedeem: Bool
        /// Pseudo du parrain, s'il y en a un.
        let referredBy: String?

        enum CodingKeys: String, CodingKey {
            case code
            case referredCount = "referred_count"
            case xpEarned = "xp_earned"
            case canRedeem = "can_redeem"
            case referredBy = "referred_by"
        }
    }

    struct Redeemed: Decodable, Sendable {
        let referrerUsername: String?
        let xpAwarded: Int

        enum CodingKeys: String, CodingKey {
            case referrerUsername = "referrer_username"
            case xpAwarded = "xp_awarded"
        }
    }

    func status() async throws -> Status {
        let client = try SupabaseService.shared.requireClient()
        do {
            let rows: [Status] = try await client.rpc("referral_status").execute().value
            guard let status = rows.first else { throw KrezusError.notFound }
            return status
        } catch {
            throw mapPostgrestError(error)
        }
    }

    func redeem(code: String) async throws -> Redeemed {
        let client = try SupabaseService.shared.requireClient()
        do {
            let rows: [Redeemed] = try await client
                .rpc("redeem_referral_code", params: ["p_code": code])
                .execute().value
            guard let redeemed = rows.first else { throw KrezusError.notFound }
            return redeemed
        } catch {
            throw mapPostgrestError(error)
        }
    }
}
