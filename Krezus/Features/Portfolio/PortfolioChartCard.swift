import SwiftUI
import Charts
import Observation

// MARK: - Modèle

/// Données de la courbe, chargées une fois par apparition de l'onglet.
///
/// La série quotidienne couvre toute la vie du portefeuille : chaque période
/// (1S, 1M, YTD…) n'en est qu'une découpe, sans nouvel appel. Seule la vue
/// « 1 jour » demande ses propres relevés, chargés à la première sélection.
@MainActor
@Observable
final class PortfolioHistoryModel {
    private(set) var daily: [PortfolioPoint] = []
    private(set) var intraday: [PortfolioPoint]?
    private(set) var isLoading = false
    private(set) var failed = false

    private var source: PortfolioHistoryRepository.DailySource?
    private let repository = PortfolioHistoryRepository()

    func load(userID: UUID?, liveValueCents: Int) async {
        guard AppConfig.isConfigured, let userID else {
            loadDemo(liveValueCents: liveValueCents)
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let source = try await repository.loadDaily(userID: userID)
            self.source = source
            daily = PortfolioHistory.daily(
                orders: source.orders, closes: source.closes, currencies: source.currencies,
                eurUsd: source.eurUsd, fallbackEurUsd: source.fallbackEurUsd,
                inception: source.inception, now: Date())
            intraday = nil
            failed = false
        } catch {
            failed = daily.isEmpty
        }
    }

    func loadIntradayIfNeeded() async {
        guard intraday == nil, let source else { return }
        let now = Date()
        let since = now.addingTimeInterval(-86_400)
        do {
            let prices = try await repository.loadIntraday(symbols: source.symbols, since: since)
            intraday = PortfolioHistory.intraday(
                orders: source.orders, prices: prices, from: since,
                inception: source.inception, now: now)
        } catch {
            intraday = []
        }
    }

    /// Points de la période, terminés par la valeur en direct.
    func series(for range: PortfolioRange, liveValueCents: Int, now: Date = Date()) -> [PortfolioPoint] {
        var points: [PortfolioPoint]
        if range == .day {
            points = intraday ?? []
        } else {
            points = PortfolioHistory.slice(daily, from: range.start(now: now))
        }
        points.removeAll { $0.date >= now }
        points.append(PortfolioPoint(date: now, valueCents: liveValueCents))
        return points
    }

    // MARK: Démo

    /// Sans serveur : une marche aléatoire déterministe, de 1 000 € il y a
    /// cinq semaines jusqu'à la valeur affichée. De quoi voir la courbe.
    private func loadDemo(liveValueCents: Int) {
        guard daily.isEmpty else { return }
        let now = Date()
        daily = DemoSeries.walk(count: 35, step: 86_400, end: now, from: PortfolioHistory.initialCashCents,
                                to: liveValueCents, volatility: 900, seed: 42)
        intraday = DemoSeries.walk(count: 288, step: 300, end: now, from: liveValueCents - 420,
                                   to: liveValueCents, volatility: 90, seed: 43)
    }
}

// MARK: - Carte

/// Valeur du portefeuille, gain sur la période en euros et en pourcentage,
/// courbe et sélecteur de période. Glisser le doigt sur la courbe affiche la
/// valeur et le gain à cet instant.
struct PortfolioChartCard: View {
    let model: PortfolioHistoryModel
    let liveValueCents: Int

    @State private var range: PortfolioRange = .month
    @State private var selectedDate: Date?

    var body: some View {
        let points = model.series(for: range, liveValueCents: liveValueCents)
        let dayPending = range == .day && model.intraday == nil
        let summary = PerformanceSummary(points: points, selectedDate: selectedDate,
                                         fallbackCents: liveValueCents)

        VStack(alignment: .leading, spacing: KrezusSpacing.s3) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Money.euros(cents: summary.valueCents))
                    .font(KrezusFont.portfolio)
                    .foregroundStyle(KrezusColor.brandText)
                    .tabularNumbers()
                    .contentTransition(.numericText())
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
            .accessibilityElement(children: .combine)

            PerformanceChart(points: dayPending ? [] : points, range: range,
                             selectedDate: $selectedDate,
                             isLoading: model.isLoading || dayPending,
                             emptyText: model.failed ? t("portfolio.chart.error") : t("portfolio.chart.empty"))
                .frame(height: 190)

            PerformanceRangePicker(range: $range, selectedDate: $selectedDate)
        }
        .task(id: range) {
            if range == .day { await model.loadIntradayIfNeeded() }
        }
    }
}
