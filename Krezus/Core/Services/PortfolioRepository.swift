import Foundation
import Supabase
import PostgREST

/// Accès au portefeuille papier : lecture de l'état, passage d'ordres via les
/// fonctions RPC transactionnelles (`execute_paper_buy` / `_sell` / `reset`).
/// Toute la logique monétaire est côté serveur — le client ne fait qu'appeler.
@MainActor
struct PortfolioRepository {

    func fetchPortfolio(userID: UUID) async throws -> Portfolio {
        let client = try SupabaseService.shared.requireClient()
        return try await client
            .from("portfolios")
            .select()
            .eq("user_id", value: userID)
            .eq("mode", value: "paper")
            .single()
            .execute()
            .value
    }

    func fetchPositions(portfolioID: UUID) async throws -> [Position] {
        let client = try SupabaseService.shared.requireClient()
        return try await client
            .from("positions")
            .select()
            .eq("portfolio_id", value: portfolioID)
            .execute()
            .value
    }

    func fetchRecentOrders(portfolioID: UUID, limit: Int = 50) async throws -> [Order] {
        let client = try SupabaseService.shared.requireClient()
        return try await client
            .from("orders")
            .select()
            .eq("portfolio_id", value: portfolioID)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value
    }

    // MARK: Versement hebdomadaire (0021)

    struct WeeklyBonusClaim: Decodable, Sendable {
        /// 30 000 au premier passage de la semaine, 0 ensuite.
        let creditedCents: Int
        /// Lundi du prochain versement, heure de Paris (« 2026-09-21 »).
        let nextWeekStart: String

        enum CodingKeys: String, CodingKey {
            case creditedCents = "credited_cents"
            case nextWeekStart = "next_week_start"
        }
    }

    /// Réclame le versement de la semaine. Idempotent : le serveur ne verse
    /// qu'une fois par semaine, quel que soit le nombre d'appels.
    func claimWeeklyBonus() async throws -> WeeklyBonusClaim {
        let client = try SupabaseService.shared.requireClient()
        do {
            let rows: [WeeklyBonusClaim] = try await client.rpc("claim_weekly_bonus").execute().value
            guard let claim = rows.first else { throw KrezusError.notFound }
            return claim
        } catch {
            throw mapPostgrestError(error)
        }
    }

    // MARK: Ordres (RPC)

    /// Achat pour un montant (centimes). Renvoie l'ordre exécuté.
    @discardableResult
    func buy(userID: UUID, symbol: String, amountCents: Int) async throws -> Order {
        try await callOrderRPC("execute_paper_buy", params: [
            "p_user_id": AnyJSON.string(userID.uuidString),
            "p_symbol": .string(symbol),
            "p_amount_cents": .integer(amountCents),
        ])
    }

    /// Vente d'un pourcentage (1...100) de la position.
    @discardableResult
    func sell(userID: UUID, symbol: String, pct: Int) async throws -> Order {
        try await callOrderRPC("execute_paper_sell", params: [
            "p_user_id": AnyJSON.string(userID.uuidString),
            "p_symbol": .string(symbol),
            "p_pct": .integer(pct),
        ])
    }

    func reset(userID: UUID) async throws {
        let client = try SupabaseService.shared.requireClient()
        do {
            try await client.rpc("reset_paper_portfolio",
                                 params: ["p_user_id": userID.uuidString]).execute()
        } catch {
            throw Self.mapped(error)
        }
    }

    private func callOrderRPC(_ name: String, params: [String: AnyJSON]) async throws -> Order {
        let client = try SupabaseService.shared.requireClient()
        do {
            return try await client.rpc(name, params: params).single().execute().value
        } catch {
            throw Self.mapped(error)
        }
    }

    /// Traduit une erreur PostgREST (portant le code SQLSTATE « KR ») en `KrezusError`.
    private static func mapped(_ error: Error) -> Error {
        if let pg = error as? PostgrestError, let code = pg.code {
            return KrezusError.from(sqlState: code, message: pg.message)
        }
        return error
    }
}
