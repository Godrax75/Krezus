import Foundation
import Supabase
import PostgREST

/// Charge ce qu'il faut pour reconstituer la courbe du portefeuille : ses
/// ordres, les clôtures et relevés intraday des titres concernés, et les
/// taux EURUSD. Le calcul lui-même est dans `PortfolioHistory`.
@MainActor
struct PortfolioHistoryRepository {

    /// Tout ce que demande la série quotidienne.
    struct DailySource: Sendable {
        let inception: Date
        let orders: [PortfolioOrder]
        let closes: [String: [DatedValue]]
        let currencies: [String: String]
        let eurUsd: [DatedValue]
        let fallbackEurUsd: Double?

        var symbols: [String] { Array(Set(orders.map(\.symbol))).sorted() }
    }

    /// PostgREST plafonne une réponse à 1 000 lignes. Trois titres suivis un an
    /// dépassent déjà ce plafond : les lectures longues se font par pages.
    private static let pageSize = 1_000

    func loadDaily(userID: UUID) async throws -> DailySource {
        let client = try SupabaseService.shared.requireClient()

        let meta: PortfolioMeta = try await client
            .from("portfolios")
            .select("id, created_at, reset_at")
            .eq("user_id", value: userID)
            .eq("mode", value: "paper")
            .single()
            .execute()
            .value
        // Une remise à zéro repart de 1 000 € : ce qui la précède n'a plus cours.
        let inception = max(meta.createdAt, meta.resetAt ?? meta.createdAt)
        let since = ISO8601DateFormatter().string(from: inception)

        let orders: [PortfolioOrder] = try await client
            .from("orders")
            .select("symbol, side, amount_cents, quantity, created_at")
            .eq("portfolio_id", value: meta.id)
            .eq("status", value: "filled")
            .gte("created_at", value: since)
            .order("created_at", ascending: true)
            .execute()
            .value

        let symbols = Array(Set(orders.map(\.symbol)))
        guard !symbols.isEmpty else {
            return DailySource(inception: inception, orders: [], closes: [:],
                               currencies: [:], eurUsd: [], fallbackEurUsd: nil)
        }

        // Une semaine de marge avant l'ouverture : le premier jour doit
        // trouver une clôture antérieure à reporter (week-end, jour férié).
        let fromDay = Self.isoDay(PortfolioHistory.utc.date(byAdding: .day, value: -7, to: inception) ?? inception)

        let closeRows: [PricePoint] = try await fetchAll { from, to in
            client.from("price_history")
                .select("symbol, date, close")
                .in("symbol", values: symbols)
                .gte("date", value: fromDay)
                .order("date", ascending: true)
                .range(from: from, to: to)
        }
        var closes: [String: [DatedValue]] = [:]
        for row in closeRows {
            guard let day = row.day else { continue }
            closes[row.symbol, default: []].append(DatedValue(date: day, value: row.close))
        }

        let currencyRows: [SecurityCurrency] = try await client
            .from("securities")
            .select("symbol, currency")
            .in("symbol", values: symbols)
            .execute()
            .value
        let currencies = Dictionary(uniqueKeysWithValues: currencyRows.map { ($0.symbol, $0.currency) })

        // Le change ne compte que si un titre en dollars a été détenu.
        var eurUsd: [DatedValue] = []
        var fallback: Double?
        if currencies.values.contains(where: { $0.uppercased() == "USD" }) {
            let fxRows: [FxClose] = try await client
                .from("fx_history")
                .select("date, rate")
                .eq("pair", value: "EURUSD")
                .gte("date", value: fromDay)
                .order("date", ascending: true)
                .execute()
                .value
            eurUsd = fxRows.compactMap { row in
                Self.parseDay(row.date).map { DatedValue(date: $0, value: row.rate) }
            }
            fallback = try await MarketDataService.shared.fxRate()?.rate
        }

        return DailySource(inception: inception, orders: orders, closes: closes,
                           currencies: currencies, eurUsd: eurUsd, fallbackEurUsd: fallback)
    }

    /// Relevés intraday en euros depuis `since`, par symbole.
    func loadIntraday(symbols: [String], since: Date) async throws -> [String: [DatedValue]] {
        guard !symbols.isEmpty else { return [:] }
        let client = try SupabaseService.shared.requireClient()
        let rows: [IntradayRow] = try await fetchAll { from, to in
            client.from("price_intraday")
                .select("symbol, ts, price")
                .in("symbol", values: symbols)
                .gte("ts", value: ISO8601DateFormatter().string(from: since))
                .order("ts", ascending: true)
                .range(from: from, to: to)
        }
        var prices: [String: [DatedValue]] = [:]
        for row in rows {
            prices[row.symbol, default: []].append(DatedValue(date: row.ts, value: row.price))
        }
        return prices
    }

    // MARK: Pagination

    private func fetchAll<T: Decodable>(
        _ page: (Int, Int) -> PostgrestTransformBuilder
    ) async throws -> [T] {
        var all: [T] = []
        var offset = 0
        while true {
            let rows: [T] = try await page(offset, offset + Self.pageSize - 1).execute().value
            all.append(contentsOf: rows)
            if rows.count < Self.pageSize { return all }
            offset += Self.pageSize
        }
    }

    // MARK: Lignes

    private struct PortfolioMeta: Decodable {
        let id: UUID
        let createdAt: Date
        let resetAt: Date?
        enum CodingKeys: String, CodingKey {
            case id
            case createdAt = "created_at"
            case resetAt = "reset_at"
        }
    }

    private struct SecurityCurrency: Decodable {
        let symbol: String
        let currency: String
    }

    private struct FxClose: Decodable {
        let date: String
        let rate: Double
    }

    private struct IntradayRow: Decodable {
        let symbol: String
        let ts: Date
        let price: Double
    }

    // MARK: Dates ISO

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static func isoDay(_ date: Date) -> String { dayFormatter.string(from: date) }
    private static func parseDay(_ string: String) -> Date? { dayFormatter.date(from: string) }
}
