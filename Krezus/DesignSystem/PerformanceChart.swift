import SwiftUI
import Charts

/// Courbe de performance partagée par le portefeuille et la fiche action :
/// ligne lissée, aire en dégradé, ligne pointillée à la valeur de départ, et
/// sélection au doigt. La couleur suit le sens de la période.
///
/// Les points sont en centimes d'euro : valeur d'un portefeuille ou cours
/// d'une action, la mise en forme est la même.
struct PerformanceChart: View {
    let points: [PortfolioPoint]
    /// Change à chaque période : sert à animer le passage de l'une à l'autre.
    let range: PortfolioRange
    @Binding var selectedDate: Date?
    var isLoading = false
    /// Message quand il n'y a pas de quoi tracer une courbe.
    var emptyText = ""

    var body: some View {
        let summary = PerformanceSummary(points: points, selectedDate: selectedDate)
        if points.count < 2 {
            ZStack {
                if isLoading {
                    ProgressView()
                } else {
                    Text(emptyText)
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
            let tint = summary.tint

            Chart {
                RuleMark(y: .value("base", Double(summary.startCents) / 100))
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

                if let selected = summary.selected {
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
            .sensoryFeedback(.selection, trigger: summary.selected?.date)
            .accessibilityLabel(t("portfolio.chart.a11y", range.caption))
        }
    }
}

/// Ce qu'affiche l'en-tête d'une courbe : la valeur au point touché (ou la
/// dernière), et l'écart avec le début de la période.
struct PerformanceSummary {
    let startCents: Int
    let valueCents: Int
    /// Versements reçus pendant la période : dans la valeur, pas dans le gain.
    let addedCents: Int
    let selected: PortfolioPoint?

    init(points: [PortfolioPoint], selectedDate: Date?, fallbackCents: Int = 0) {
        startCents = points.first?.valueCents ?? fallbackCents
        if let selectedDate {
            selected = points.min {
                abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate))
            }
        } else {
            selected = nil
        }
        let end = selected ?? points.last
        valueCents = end?.valueCents ?? fallbackCents
        addedCents = max(0, (end?.depositedCents ?? 0) - (points.first?.depositedCents ?? 0))
    }

    var gainCents: Int { valueCents - startCents - addedCents }
    /// Rapporté à la mise de départ augmentée des versements : 300 € versés
    /// en cours de route agrandissent la base, ils ne font pas de gain.
    var gainPct: Double {
        let base = startCents + addedCents
        return base > 0 ? Double(gainCents) / Double(base) * 100 : 0
    }
    var tint: Color { gainCents >= 0 ? KrezusColor.up : KrezusColor.down }

    /// « +12,40 € (+3,21 %) ».
    var gainLabel: String { "\(Money.signedEuros(cents: gainCents)) (\(Money.percent(gainPct)))" }

    /// Complément du gain : la date touchée, sinon la période.
    func caption(for range: PortfolioRange) -> String {
        guard let selected else { return range.caption }
        let style: Date.FormatStyle = range == .day
            ? .dateTime.hour().minute().locale(L10n.locale)
            : .dateTime.day().month(.abbreviated).year().locale(L10n.locale)
        return selected.date.formatted(style)
    }
}

/// Sélecteur 1J · 1S · 1M · YTD · 1A · 5A · Max.
struct PerformanceRangePicker: View {
    @Binding var range: PortfolioRange
    /// Remis à zéro au changement de période : un point touché sur 1 an n'a
    /// pas de sens sur 1 jour.
    @Binding var selectedDate: Date?

    var body: some View {
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
}

// MARK: - Données de démonstration

/// Marche aléatoire reproductible, pour montrer une courbe sans serveur.
enum DemoSeries {
    /// `count` points espacés de `step`, finissant à `end`, de `from` à `to`.
    /// Les pas sont tirés librement puis une rampe recale l'arrivée.
    static func walk(count: Int, step: TimeInterval, end: Date, from: Int, to: Int,
                     volatility: Double, seed: UInt64) -> [PortfolioPoint] {
        var generator = SeededGenerator(seed: seed)
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

    /// Graine stable tirée d'un texte (le symbole d'un titre, par exemple).
    static func seed(_ text: String) -> UInt64 {
        text.unicodeScalars.reduce(1_469_598_103_934_665_603) { ($0 ^ UInt64($1.value)) &* 1_099_511_628_211 }
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }
}
