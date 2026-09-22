import SwiftUI
import Observation
import Supabase
import PostgREST

/// Historique d'un titre, en euros, pour la courbe de sa fiche.
///
/// Les clôtures de `price_history` sont en devise de cotation. Un titre en
/// dollars est converti au taux EURUSD de chaque date : la fiche affiche un
/// cours en euros, la courbe doit parler la même unité, et c'est bien ce qu'a
/// vécu un investisseur en euros — change compris.
@MainActor
@Observable
final class StockHistoryModel {
    private(set) var daily: [PortfolioPoint] = []
    private(set) var intraday: [PortfolioPoint]?
    private(set) var isLoading = false
    private(set) var failed = false

    let symbol: String
    private var loaded = false

    init(symbol: String) { self.symbol = symbol }

    /// PostgREST plafonne une réponse à 1 000 lignes ; cinq ans de séances en
    /// font environ 1 270.
    private static let pageSize = 1_000

    func load(currency: String, livePrice: Double) async {
        guard !loaded else { return }
        guard AppConfig.isConfigured else {
            loadDemo(livePrice: livePrice)
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let client = try SupabaseService.shared.requireClient()
            var closes: [PricePoint] = []
            var offset = 0
            while true {
                let page: [PricePoint] = try await client
                    .from("price_history")
                    .select("symbol, date, close")
                    .eq("symbol", value: symbol)
                    .order("date", ascending: true)
                    .range(from: offset, to: offset + Self.pageSize - 1)
                    .execute().value
                closes += page
                if page.count < Self.pageSize { break }
                offset += Self.pageSize
            }

            // Toute la série de change, par pages : lue d'un bloc, elle
            // s'arrêtait à ses mille premières lignes, et les cours récents
            // se convertissaient au taux de 2010.
            let fxRepository = FxHistoryRepository()
            let fxKey = PortfolioHistory.fxCurrency(for: currency)
            let fx = try await fxRepository.series(for: [currency])[fxKey ?? ""] ?? []
            let fallback = fxKey == nil ? nil : await fxRepository.latestRates(for: [currency])[fxKey!]

            daily = closes.compactMap { point in
                guard let day = point.day,
                      let euros = PortfolioHistory.toEuros(
                        point.close, currency: currency,
                        rate: PortfolioHistory.lastValue(in: fx, onOrBefore: day) ?? fx.first?.value ?? fallback)
                else { return nil }
                return PortfolioPoint(date: day, valueCents: Int((euros * 100).rounded()))
            }
            failed = false
            loaded = true
        } catch {
            failed = daily.isEmpty
        }
    }

    func loadIntradayIfNeeded() async {
        guard intraday == nil, AppConfig.isConfigured else { return }
        do {
            let client = try SupabaseService.shared.requireClient()
            let since = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-86_400))
            let rows: [IntradayRow] = try await client
                .from("price_intraday")
                .select("ts, price")
                .eq("symbol", value: symbol)
                .gte("ts", value: since)
                .order("ts", ascending: true)
                .execute().value
            intraday = rows.map { PortfolioPoint(date: $0.ts, valueCents: Int(($0.price * 100).rounded())) }
        } catch {
            intraday = []
        }
    }

    /// Points de la période, terminés par le cours en direct.
    func series(for range: PortfolioRange, livePrice: Double, now: Date = Date()) -> [PortfolioPoint] {
        var points = range == .day
            ? (intraday ?? [])
            : PortfolioHistory.slice(daily, from: range.start(now: now))
        points.removeAll { $0.date >= now }
        if livePrice > 0 {
            points.append(PortfolioPoint(date: now, valueCents: Int((livePrice * 100).rounded())))
        }
        return points
    }

    /// Sans serveur : cinq ans de marche aléatoire propre au titre, et une
    /// journée de relevés, jusqu'au cours affiché.
    private func loadDemo(livePrice: Double) {
        guard !loaded, livePrice > 0 else { return }
        let now = Date()
        let cents = Int((livePrice * 100).rounded())
        let seed = DemoSeries.seed(symbol)
        daily = DemoSeries.walk(count: 1_260, step: 86_400 * 365 / 252, end: now, from: cents * 55 / 100,
                                to: cents, volatility: Double(cents) * 0.012, seed: seed)
        intraday = DemoSeries.walk(count: 100, step: 300, end: now, from: cents * 995 / 1000,
                                   to: cents, volatility: Double(cents) * 0.0012, seed: seed &+ 1)
        loaded = true
    }

    private struct IntradayRow: Decodable { let ts: Date; let price: Double }
}

/// Cours, variation sur la période, courbe et sélecteur, pour la fiche action.
struct StockChartCard: View {
    let stock: StockInfo
    @Environment(TradingStore.self) private var store
    @State private var model: StockHistoryModel
    @State private var range: PortfolioRange = .year
    @State private var selectedDate: Date?

    init(stock: StockInfo) {
        self.stock = stock
        _model = State(initialValue: StockHistoryModel(symbol: stock.symbol))
    }

    var body: some View {
        let points = model.series(for: range, livePrice: stock.price)
        let dayPending = range == .day && model.intraday == nil && AppConfig.isConfigured
        let live = Int((stock.price * 100).rounded())
        let summary = PerformanceSummary(points: points, selectedDate: selectedDate, fallbackCents: live)

        VStack(alignment: .leading, spacing: KrezusSpacing.s3) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(stock.hasQuote || summary.selected != nil ? Money.euros(cents: summary.valueCents) : "—")
                        .font(KrezusFont.display(30, .heavy))
                        .foregroundStyle(stock.hasQuote ? KrezusColor.ink : KrezusColor.fg4)
                        .tabularNumbers()
                        .contentTransition(.numericText())
                    // La pastille ne qualifie que le cours en direct, et dit
                    // son âge dès qu'il en a un.
                    if stock.hasQuote && summary.selected == nil {
                        KrzQuoteAge(age: store.quoteAge(stock.symbol))
                    }
                }
                if points.count >= 2 {
                    HStack(spacing: 6) {
                        Text(summary.gainLabel)
                            .font(KrezusFont.body(13.5, .semibold))
                            .foregroundStyle(summary.tint)
                            .tabularNumbers()
                        Text(summary.caption(for: range))
                            .font(KrezusFont.body(13, .medium))
                            .foregroundStyle(KrezusColor.fg3)
                    }
                }
            }
            .accessibilityElement(children: .combine)

            PerformanceChart(points: dayPending ? [] : points, range: range,
                             selectedDate: $selectedDate,
                             isLoading: model.isLoading || dayPending,
                             emptyText: model.failed ? t("stock.chart.error") : t("stock.chart.empty"))
                .frame(height: 180)

            PerformanceRangePicker(range: $range, selectedDate: $selectedDate)
        }
        .task { await model.load(currency: stock.currency, livePrice: stock.price) }
        .task(id: range) {
            if range == .day { await model.loadIntradayIfNeeded() }
        }
    }
}
