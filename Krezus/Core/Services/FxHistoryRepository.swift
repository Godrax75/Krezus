import Foundation
import Supabase
import PostgREST

/// Clôtures de change quotidiennes (`fx_history`), une série par devise.
///
/// Une série se désigne par la devise de sa paire (« USD » pour EURUSD,
/// « GBP » pour EURGBP) : c'est la clé qu'attend `PortfolioHistory`. Les
/// pence de Londres (GBX) partagent la série de la livre.
@MainActor
struct FxHistoryRepository {

    /// PostgREST s'arrête à 1 000 lignes ; vingt ans de change en font plus
    /// de cinq mille. Lire sans paginer, c'était convertir 2026 au taux de
    /// 2010.
    private static let pageSize = 1_000

    /// Séries des devises demandées (clés = devise de paire), sur la fenêtre
    /// donnée. L'euro n'a pas de série.
    func series(for currencies: some Sequence<String>, from: Date? = nil,
                to: Date? = nil) async throws -> [String: [DatedValue]] {
        let keys = Set(currencies.compactMap(PortfolioHistory.fxCurrency(for:)))
        guard !keys.isEmpty else { return [:] }
        let client = try SupabaseService.shared.requireClient()

        var result: [String: [DatedValue]] = [:]
        for key in keys.sorted() {
            var rows: [Row] = []
            var offset = 0
            while true {
                var query = client.from("fx_history")
                    .select("date, rate")
                    .eq("pair", value: "EUR\(key)")
                if let from { query = query.gte("date", value: Self.isoDay(from)) }
                if let to { query = query.lte("date", value: Self.isoDay(to)) }
                let page: [Row] = try await query
                    .order("date", ascending: true)
                    .range(from: offset, to: offset + Self.pageSize - 1)
                    .execute().value
                rows += page
                if page.count < Self.pageSize { break }
                offset += Self.pageSize
            }
            result[key] = rows.compactMap { row in
                Self.parseDay(row.date).map { DatedValue(date: $0, value: row.rate) }
            }
        }
        return result
    }

    /// Dernier taux connu de chaque devise (`fx_rates`), en repli quand
    /// l'historique ne couvre pas encore le jour demandé.
    func latestRates(for currencies: some Sequence<String>) async -> [String: Double] {
        var rates: [String: Double] = [:]
        for key in Set(currencies.compactMap(PortfolioHistory.fxCurrency(for:))) {
            if let rate = try? await MarketDataService.shared.fxRate(pair: "EUR\(key)")?.rate {
                rates[key] = rate
            }
        }
        return rates
    }

    private struct Row: Decodable {
        let date: String
        let rate: Double
    }

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
