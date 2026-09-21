import Foundation
import Supabase
import PostgREST

/// Clôtures d'une fenêtre passée, converties en euros — de quoi rejouer une
/// crise sur le portefeuille. Le calcul est dans `CrisisBacktest`.
///
/// Les titres en dollars sont convertis au taux de **leur** date : convertir
/// 2008 au taux d'aujourd'hui ferait passer une variation de change pour une
/// performance boursière.
@MainActor
struct CrisisHistoryRepository {

    /// PostgREST plafonne à 1 000 lignes : six ans de cotations pour cinq
    /// titres dépassent largement, d'où la lecture par pages.
    private static let pageSize = 1_000

    func closesInEuros(symbols: [String], from: Date, to: Date) async throws -> [String: [DatedValue]] {
        guard !symbols.isEmpty else { return [:] }
        let client = try SupabaseService.shared.requireClient()

        // Un mois de marge avant la fenêtre : le premier jour doit trouver une
        // clôture antérieure à reporter.
        let fromDay = Self.isoDay(from.addingTimeInterval(-31 * 86_400))
        let toDay = Self.isoDay(to)

        let rows: [PriceRow] = try await fetchAll { start, end in
            client.from("price_history")
                .select("symbol, date, close")
                .in("symbol", values: symbols)
                .gte("date", value: fromDay)
                .lte("date", value: toDay)
                .order("date", ascending: true)
                .range(from: start, to: end)
        }

        let currencyRows: [SecurityCurrency] = try await client
            .from("securities")
            .select("symbol, currency")
            .in("symbol", values: symbols)
            .execute()
            .value
        let currencies = Dictionary(uniqueKeysWithValues: currencyRows.map { ($0.symbol, $0.currency) })

        var eurUsd: [DatedValue] = []
        if currencies.values.contains(where: { $0.uppercased() == "USD" }) {
            let fxRows: [FxRow] = try await fetchAll { start, end in
                client.from("fx_history")
                    .select("date, rate")
                    .eq("pair", value: "EURUSD")
                    .gte("date", value: fromDay)
                    .lte("date", value: toDay)
                    .order("date", ascending: true)
                    .range(from: start, to: end)
            }
            eurUsd = fxRows.compactMap { row in
                Self.parseDay(row.date).map { DatedValue(date: $0, value: row.rate) }
            }
        }

        var closes: [String: [DatedValue]] = [:]
        for row in rows {
            guard let day = Self.parseDay(row.date) else { continue }
            let currency = currencies[row.symbol] ?? "EUR"
            guard let euros = PortfolioHistory.toEuros(
                row.close, currency: currency,
                rate: PortfolioHistory.lastValue(in: eurUsd, onOrBefore: day)) else { continue }
            closes[row.symbol, default: []].append(DatedValue(date: day, value: euros))
        }
        return closes
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

    private struct PriceRow: Decodable {
        let symbol: String
        let date: String
        let close: Double
    }

    private struct SecurityCurrency: Decodable {
        let symbol: String
        let currency: String
    }

    private struct FxRow: Decodable {
        let date: String
        let rate: Double
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
