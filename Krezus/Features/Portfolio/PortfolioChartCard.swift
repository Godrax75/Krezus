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
        var generator = SeededGenerator(seed: 42)
        let now = Date()
        daily = Self.demoWalk(count: 35, step: 86_400, end: now, from: PortfolioHistory.initialCashCents,
                              to: liveValueCents, volatility: 900, generator: &generator)
        intraday = Self.demoWalk(count: 288, step: 300, end: now, from: liveValueCents - 420,
                                 to: liveValueCents, volatility: 90, generator: &generator)
    }

    /// Marche aléatoire de `from` à `to` : les pas sont tirés librement, puis
    /// une rampe linéaire recale l'arrivée sur la valeur affichée sans toucher
    /// au départ.
    private static func demoWalk(count: Int, step: TimeInterval, end: Date, from: Int, to: Int,
                                 volatility: Double,
                                 generator: inout SeededGenerator) -> [PortfolioPoint] {
        var walk: [Double] = [0]
        for _ in 1..<count {
            walk.append(walk.last! + Double.random(in: -volatility...(volatility * 1.08), using: &generator))
        }
        let correction = Double(to - from) - walk.last!
        return walk.enumerated().map { index, offset in
            let ramp = correction * Double(index) / Double(count - 1)
            return PortfolioPoint(date: end.addingTimeInterval(-Double(count - index) * step),
                                  valueCents: from + Int((offset + ramp).rounded()))
        }
    }
}

/// Générateur reproductible : la courbe de démo ne change pas à chaque visite.
private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
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

    private var points: [PortfolioPoint] {
        model.series(for: range, liveValueCents: liveValueCents)
    }

    /// Point le plus proche du doigt.
    private var selected: PortfolioPoint? {
        guard let selectedDate else { return nil }
        return points.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }

    var body: some View {
        let points = self.points
        let first = points.first?.valueCents ?? liveValueCents
        let shown = selected ?? points.last
        let value = shown?.valueCents ?? liveValueCents
        let gain = value - first
        let pct = first > 0 ? Double(gain) / Double(first) * 100 : 0
        let tint = gain >= 0 ? KrezusColor.up : KrezusColor.down

        VStack(alignment: .leading, spacing: KrezusSpacing.s3) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Money.euros(cents: value))
                    .font(KrezusFont.portfolio)
                    .foregroundStyle(KrezusColor.brandText)
                    .tabularNumbers()
                    .contentTransition(.numericText())
                HStack(spacing: 6) {
                    Text("\(Money.signedEuros(cents: gain)) (\(Money.percent(pct)))")
                        .font(KrezusFont.body(13.5, .semibold))
                        .foregroundStyle(tint)
                        .tabularNumbers()
                    Text(selected.map { caption(for: $0.date) } ?? range.caption)
                        .font(KrezusFont.body(13, .medium))
                        .foregroundStyle(KrezusColor.fg3)
                }
            }
            .accessibilityElement(children: .combine)

            chart(points: points, baseline: first, tint: tint)
                .frame(height: 190)

            rangePicker
        }
        .task(id: range) {
            if range == .day { await model.loadIntradayIfNeeded() }
        }
    }

    // MARK: Courbe

    @ViewBuilder
    private func chart(points: [PortfolioPoint], baseline: Int, tint: Color) -> some View {
        if points.count < 2 || (range == .day && model.intraday == nil) {
            ZStack {
                if model.isLoading || (range == .day && model.intraday == nil) {
                    ProgressView()
                } else {
                    Text(model.failed ? t("portfolio.chart.error") : t("portfolio.chart.empty"))
                        .font(KrezusFont.bodySm).foregroundStyle(KrezusColor.fg3)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let values = points.map { Double($0.valueCents) / 100 }
            let low = values.min() ?? 0, high = values.max() ?? 0
            // L'échelle suit l'amplitude de la série, avec 18 % de marge pour
            // que la courbe ne touche pas les bords. Une série plate garde un
            // écart minimal de 50 centimes, sans quoi l'échelle serait nulle.
            let pad = max((high - low) * 0.18, 0.5)

            Chart {
                RuleMark(y: .value("base", Double(baseline) / 100))
                    .foregroundStyle(KrezusColor.fg4.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))

                ForEach(points) { point in
                    AreaMark(x: .value("date", point.date),
                             yStart: .value("min", low - pad),
                             yEnd: .value("valeur", Double(point.valueCents) / 100))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(LinearGradient(
                            colors: [tint.opacity(0.22), tint.opacity(0)],
                            startPoint: .top, endPoint: .bottom))

                    LineMark(x: .value("date", point.date),
                             y: .value("valeur", Double(point.valueCents) / 100))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(tint)
                        .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                }

                if let selected {
                    RuleMark(x: .value("date", selected.date))
                        .foregroundStyle(KrezusColor.fg4.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                    PointMark(x: .value("date", selected.date),
                              y: .value("valeur", Double(selected.valueCents) / 100))
                        .foregroundStyle(tint)
                        .symbolSize(70)
                }
            }
            .chartYScale(domain: (low - pad)...(high + pad))
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
            .chartXSelection(value: $selectedDate)
            .animation(.easeInOut(duration: 0.25), value: range)
            .sensoryFeedback(.selection, trigger: selected?.date)
            .accessibilityLabel(t("portfolio.chart.a11y", range.caption))
        }
    }

    // MARK: Sélecteur

    private var rangePicker: some View {
        HStack(spacing: 4) {
            ForEach(PortfolioRange.allCases) { item in
                Button {
                    selectedDate = nil
                    withAnimation(.snappy(duration: 0.2)) { range = item }
                } label: {
                    Text(item.label)
                        .font(KrezusFont.body(12.5, .bold))
                        .foregroundStyle(item == range ? KrezusColor.brandText : KrezusColor.fg3)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(item == range ? KrezusColor.tintStrong : .clear)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(item == range ? [.isButton, .isSelected] : .isButton)
            }
        }
    }

    /// Date du point touché : l'heure en vue « 1 jour », le jour sinon.
    private func caption(for date: Date) -> String {
        let style: Date.FormatStyle = range == .day
            ? .dateTime.hour().minute().locale(L10n.locale)
            : .dateTime.day().month(.abbreviated).year().locale(L10n.locale)
        return date.formatted(style)
    }
}
