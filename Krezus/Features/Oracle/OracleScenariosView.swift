import SwiftUI
import Observation

// MARK: - Modèle d'écran

/// Charge les cours de la crise choisie et rejoue le portefeuille dessus.
///
/// Une crise chargée est gardée : revenir dessus ne relance pas la lecture de
/// six ans de cotations.
@MainActor
@Observable
final class CrisisBacktestModel {
    private(set) var results: [String: BacktestResult] = [:]
    private(set) var loadingCrisis: String?
    private(set) var failed = false

    private let repository = CrisisHistoryRepository()

    func result(for crisis: MarketCrisis) -> BacktestResult? { results[crisis.id] }

    func load(_ crisis: MarketCrisis, holdings: [BacktestHolding]) async {
        guard results[crisis.id] == nil, loadingCrisis != crisis.id,
              let start = crisis.startDate, let end = crisis.endDate,
              !holdings.isEmpty, AppConfig.isConfigured else { return }
        loadingCrisis = crisis.id
        failed = false
        defer { loadingCrisis = nil }
        do {
            let closes = try await repository.closesInEuros(
                symbols: holdings.map(\.symbol), from: start, to: min(end, Date()))
            results[crisis.id] = CrisisBacktest.run(holdings: holdings, closes: closes,
                                                    start: start, end: min(end, Date()))
            failed = results[crisis.id] == nil
        } catch {
            failed = true
        }
    }

    /// Les positions changent (achat, vente) : les rejouées ne valent plus.
    func invalidate() { results.removeAll() }
}

// MARK: - Écran

/// Onglet Scénarios : rejouer une crise passée sur son portefeuille, puis
/// lire ce que d'autres chocs lui feraient.
///
/// Deux registres, tenus séparés :
///   - **la crise rejouée** est du calcul sur des cours réels ;
///   - **le scénario projeté** est une estimation, à partir d'hypothèses
///     affichées. Aucune probabilité n'est montrée : un « 42 % de risque »
///     aurait l'air d'une mesure sans en être une.
struct OracleScenariosView: View {
    @Environment(OracleStore.self) private var oracle
    @Environment(TradingStore.self) private var trading

    @State private var model = CrisisBacktestModel()
    @State private var selected: String?

    private var holdings: [BacktestHolding] {
        trading.holdingSymbols.compactMap { symbol in
            guard let stock = trading.stock(symbol) else { return nil }
            return BacktestHolding(symbol: symbol, name: stock.name,
                                   valueEuros: trading.positionValue(symbol))
        }
    }

    private var crisis: MarketCrisis? {
        oracle.crises.first { $0.id == selected } ?? oracle.crises.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            backtestSection
            projectionSection
        }
        .onChange(of: trading.holdingSymbols) { _, _ in model.invalidate() }
    }

    // MARK: Rejouer une crise

    private var backtestSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(t("oracle.backtest.title"), t("oracle.backtest.subtitle"))

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(oracle.crises) { item in
                        let isSelected = item.id == crisis?.id
                        Button { selected = item.id } label: {
                            Text("\(item.emoji) \(item.label)")
                                .font(KrezusFont.body(12.5, .semibold))
                                .foregroundStyle(isSelected ? .white : KrezusColor.fg2)
                                .lineLimit(1)
                                .padding(.horizontal, 14).padding(.vertical, 9)
                                .background(isSelected ? KrezusColor.brandFill : KrezusColor.tint)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                    }
                }
                .padding(.horizontal, 1)
            }
            .scrollIndicators(.hidden)

            if let crisis { crisisCard(crisis) }
        }
    }

    private func crisisCard(_ crisis: MarketCrisis) -> some View {
        KrzCard(shadow: KrezusShadow.level2) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(crisis.label)
                            .font(KrezusFont.display(18, .heavy)).foregroundStyle(KrezusColor.ink)
                        Text(t("oracle.backtest.window", crisis.yearLabel, String(crisis.end.prefix(4))))
                            .font(KrezusFont.caption).foregroundStyle(KrezusColor.fg3)
                    }
                    Spacer(minLength: 8)
                    Text(crisis.emoji).font(.system(size: 26))
                }

                if holdings.isEmpty {
                    emptyState(t("oracle.backtest.no_positions"))
                } else if !AppConfig.isConfigured {
                    emptyState(t("oracle.backtest.demo"))
                } else if let result = model.result(for: crisis) {
                    resultBody(result, crisis: crisis)
                } else if model.failed {
                    emptyState(t("oracle.backtest.error"))
                } else {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(t("oracle.backtest.loading"))
                            .font(KrezusFont.bodySm).foregroundStyle(KrezusColor.fg3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 24)
                }

                Text(crisis.summary)
                    .font(KrezusFont.bodySm).foregroundStyle(KrezusColor.fg2)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task(id: "\(crisis.id)-\(holdings.count)") {
            await model.load(crisis, holdings: holdings)
        }
    }

    @ViewBuilder
    private func resultBody(_ result: BacktestResult, crisis: MarketCrisis) -> some View {
        PerformanceChart(points: result.points, range: .max,
                         selectedDate: .constant(nil), isLoading: false,
                         emptyText: t("oracle.backtest.error"))
            .frame(height: 150)

        HStack(alignment: .top, spacing: 10) {
            stat(t("oracle.backtest.drawdown"), Money.percent(result.drawdownPct), KrezusColor.down)
            stat(t("oracle.backtest.low"), Money.euros(cents: result.troughValueCents), KrezusColor.ink)
            stat(t("oracle.backtest.recovery"), recoveryLabel(result), KrezusColor.ink)
        }

        // Ce que la baisse aurait coûté, en euros d'aujourd'hui : c'est le
        // chiffre qui parle, plus qu'un pourcentage.
        let lossCents = result.troughValueCents - Int((result.covered.reduce(0) { $0 + $1.valueEuros } * 100).rounded())
        Text(t("oracle.backtest.loss", Money.signedEuros(cents: lossCents)))
            .font(KrezusFont.body(13.5, .semibold)).foregroundStyle(KrezusColor.fg2)
            .fixedSize(horizontal: false, vertical: true)

        if let worst = result.perHolding.first, result.perHolding.count > 1,
           let best = result.perHolding.last {
            VStack(spacing: 0) {
                holdingRow(t("oracle.backtest.worst"), worst)
                Divider().overlay(KrezusColor.divider)
                holdingRow(t("oracle.backtest.best"), best)
            }
        }

        if !result.missing.isEmpty {
            let names = result.missing.map(\.name).joined(separator: ", ")
            let share = Int((result.coverage * 100).rounded())
            Text(result.missing.count == 1
                 ? t("oracle.backtest.missing_one", names, share)
                 : t("oracle.backtest.missing", names, share))
                .font(KrezusFont.caption).foregroundStyle(KrezusColor.fg3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func holdingRow(_ label: String, _ item: (holding: BacktestHolding, changePct: Double)) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(KrezusFont.body(10, .bold)).tracking(0.7)
                .foregroundStyle(KrezusColor.fg3)
                .frame(width: 56, alignment: .leading)
            Text(item.holding.name)
                .font(KrezusFont.body(13, .semibold)).foregroundStyle(KrezusColor.ink)
                .lineLimit(1)
            Spacer(minLength: 0)
            Text(Money.percent(item.changePct))
                .font(KrezusFont.body(13, .bold))
                .foregroundStyle(item.changePct >= 0 ? KrezusColor.up : KrezusColor.down)
                .tabularNumbers()
        }
        .padding(.vertical, 8)
    }

    private func recoveryLabel(_ result: BacktestResult) -> String {
        guard let months = result.recoveryMonths else { return t("oracle.backtest.no_recovery") }
        return months < 1 ? t("oracle.backtest.recovery_weeks") : t("format.months_short", months)
    }

    private func stat(_ label: String, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(KrezusFont.body(9.5, .bold)).tracking(0.6)
                .foregroundStyle(KrezusColor.fg3)
                .fixedSize(horizontal: false, vertical: true)
            Text(value)
                .font(KrezusFont.display(15.5, .heavy)).foregroundStyle(tint)
                // Deux lignes : « Pas encore repassé au-dessus » ne tient pas
                // sur une, et une reprise inconnue mérite d'être lisible.
                .lineLimit(2).minimumScaleFactor(0.65)
                .fixedSize(horizontal: false, vertical: true)
                .tabularNumbers()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10).padding(.horizontal, 11)
        .background(KrezusColor.tint)
        .clipShape(RoundedRectangle(cornerRadius: KrezusRadius.sm, style: .continuous))
    }

    // MARK: Scénarios projetés

    private var projectionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(t("oracle.scenarios.title"), t("oracle.scenarios.intro"))

            ForEach(oracle.scenarios) { scenario in
                ScenarioCard(scenario: scenario,
                             weightsBySector: weightsBySector,
                             totalEuros: holdings.reduce(0) { $0 + $1.valueEuros },
                             analogue: oracle.crises.first { $0.id == scenario.analogue },
                             onReplay: { id in withAnimation(.snappy) { selected = id } })
            }
        }
    }

    /// Poids du portefeuille par famille de secteur, en euros.
    private var weightsBySector: [SectorGroup: Double] {
        var weights: [SectorGroup: Double] = [:]
        for symbol in trading.holdingSymbols {
            guard let stock = trading.stock(symbol) else { continue }
            weights[stock.sectorGroup, default: 0] += trading.positionValue(symbol)
        }
        return weights
    }

    // MARK: Éléments partagés

    private func sectionTitle(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(KrezusFont.cardTitle).foregroundStyle(KrezusColor.ink)
            Text(subtitle)
                .font(KrezusFont.caption).foregroundStyle(KrezusColor.fg3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
    }

    private func emptyState(_ text: String) -> some View {
        Text(text)
            .font(KrezusFont.bodySm).foregroundStyle(KrezusColor.fg3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 12)
    }
}

// MARK: - Carte d'un scénario projeté

private struct ScenarioCard: View {
    let scenario: OracleScenario
    let weightsBySector: [SectorGroup: Double]
    let totalEuros: Double
    let analogue: MarketCrisis?
    let onReplay: (String) -> Void

    @State private var showsAssumptions = false

    private var impact: (pct: Double, rows: [(sector: SectorGroup, weight: Double, shock: Double)])? {
        guard let shocks = scenario.shocks, !weightsBySector.isEmpty else { return nil }
        return ScenarioImpact.estimate(weightsBySector: weightsBySector,
                                       shocks: shocks, fallback: scenario.fallback ?? 0)
    }

    var body: some View {
        KrzCard(shadow: KrezusShadow.level2) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Text(scenario.emoji).font(.system(size: 26))
                    Text(scenario.title)
                        .font(KrezusFont.display(16, .bold))
                        .foregroundStyle(KrezusColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let impact { impactBar(impact.pct) }

                block(t("oracle.scenario.trigger"), scenario.trigger)
                block(t("oracle.scenario.mechanism"), scenario.mechanism)
                block(t("oracle.scenario.portfolio"), scenario.portfolio)

                if let impact, !impact.rows.isEmpty { assumptions(impact.rows) }

                if let analogue {
                    Button { onReplay(analogue.id) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "clock.arrow.circlepath")
                            Text(t("oracle.scenario.replay", analogue.label))
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .font(KrezusFont.body(13, .semibold))
                        .foregroundStyle(KrezusColor.brandText)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 13)).foregroundStyle(KrezusColor.amberText)
                    Text(scenario.lesson)
                        .font(KrezusFont.body(13, .semibold))
                        .foregroundStyle(KrezusColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(KrezusSpacing.s3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(KrezusColor.amberSoft)
                .clipShape(RoundedRectangle(cornerRadius: KrezusRadius.sm, style: .continuous))
            }
        }
    }

    /// Impact estimé, en pourcentage et en euros. La barre est graduée à
    /// 40 % : au-delà, elle sature plutôt que de sortir de la carte.
    private func impactBar(_ pct: Double) -> some View {
        let tint = pct >= 0 ? KrezusColor.up : KrezusColor.down
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(t("oracle.scenario.impact"))
                    .font(KrezusFont.body(10, .bold)).tracking(0.7)
                    .foregroundStyle(KrezusColor.fg3)
                Spacer()
                Text(Money.percent(pct))
                    .font(KrezusFont.display(15, .heavy)).foregroundStyle(tint).tabularNumbers()
                Text("(\(Money.signedEuros(cents: Int((totalEuros * pct).rounded()))))")
                    .font(KrezusFont.body(12.5, .semibold)).foregroundStyle(KrezusColor.fg3)
                    .tabularNumbers()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(KrezusColor.tint)
                    Capsule().fill(tint)
                        .frame(width: geo.size.width * min(abs(pct) / 40, 1))
                }
            }
            .frame(height: 7)
        }
        .accessibilityElement(children: .combine)
    }

    /// Les hypothèses, secteur par secteur : sans elles, le pourcentage
    /// ci-dessus serait un oracle au sens propre.
    private func assumptions(_ rows: [(sector: SectorGroup, weight: Double, shock: Double)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { withAnimation(.snappy) { showsAssumptions.toggle() } } label: {
                HStack(spacing: 6) {
                    Text(t("oracle.scenario.assumptions"))
                    Image(systemName: showsAssumptions ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                    Spacer(minLength: 0)
                }
                .font(KrezusFont.body(12.5, .semibold))
                .foregroundStyle(KrezusColor.fg3)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showsAssumptions {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.sector) { index, row in
                        if index > 0 { Divider().overlay(KrezusColor.divider) }
                        HStack(spacing: 8) {
                            Text(row.sector.label)
                                .font(KrezusFont.body(12.5, .semibold)).foregroundStyle(KrezusColor.ink)
                            Text(t("oracle.scenario.weight", Int((row.weight * 100).rounded())))
                                .font(KrezusFont.caption).foregroundStyle(KrezusColor.fg3)
                            Spacer(minLength: 0)
                            // Hypothèse ronde : « −12 % », pas « −12,00 % »,
                            // qui donnerait à une estimation la précision
                            // d'une mesure.
                            Text((row.shock > 0 ? "+" : "") + t("format.percent_int", Int(row.shock.rounded())))
                                .font(KrezusFont.body(12.5, .bold))
                                .foregroundStyle(row.shock >= 0 ? KrezusColor.up : KrezusColor.down)
                                .tabularNumbers()
                        }
                        .padding(.vertical, 6)
                    }
                }
                Text(t("oracle.scenario.assumptions_note"))
                    .font(KrezusFont.caption).foregroundStyle(KrezusColor.fg3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func block(_ label: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(KrezusFont.body(9.5, .bold)).tracking(0.7)
                .foregroundStyle(KrezusColor.fg3)
            Text(text)
                .font(KrezusFont.bodyMd).foregroundStyle(KrezusColor.fg2)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
