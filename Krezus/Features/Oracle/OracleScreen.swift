import SwiftUI

/// Onglet Oracle — quatre sous-onglets : Analyse, Scénarios, Coach, Profil.
///
/// Règle qui traverse tout l'écran : l'Oracle rapproche des chiffres publics et
/// explique des mécanismes. Il ne dit jamais quoi acheter. Une recommandation
/// personnalisée sur titre nommé relèverait du conseil en investissement, qui
/// exige un statut CIF que Krezus n'a pas.
struct OracleScreen: View {
    @Environment(OracleStore.self) private var oracle

    @State private var section: Section = .analysis

    enum Section: String, CaseIterable, Identifiable {
        case analysis, scenarios, coach, profile
        var id: String { rawValue }

        var label: String {
            switch self {
            case .analysis:  return t("oracle.tab.analysis")
            case .scenarios: return t("oracle.tab.scenarios")
            case .coach:     return t("oracle.tab.coach")
            case .profile:   return t("oracle.tab.profile")
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                KrzSectionTitle(systemImage: "sparkles", title: "Krezus Oracle")
                picker

                switch section {
                case .analysis:  OracleAnalysisView()
                case .scenarios: OracleScenariosView()
                case .coach:     OracleCoachView()
                case .profile:   OracleProfileView()
                }

                disclaimer
            }
            .padding(.horizontal, KrezusSpacing.s4)
            .padding(.top, 6)
            .padding(.bottom, 140)
        }
        .scrollIndicators(.hidden)
    }

    private var picker: some View {
        HStack(spacing: 6) {
            ForEach(Section.allCases) { item in
                Button { section = item } label: {
                    Text(item.label)
                        .font(KrezusFont.body(12.5, .semibold))
                        .foregroundStyle(section == item ? .white : KrezusColor.fg3)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(section == item ? KrezusColor.brandFill : Color.clear)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(KrezusColor.tint)
        .clipShape(Capsule())
    }

    private var disclaimer: some View {
        Text(t("oracle.disclaimer"))
            .font(KrezusFont.caption)
            .foregroundStyle(KrezusColor.fg3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)
    }
}

// MARK: - Analyse

/// Trois blocs, tous adossés à des données réellement présentes dans le
/// référentiel. Les listes « sous-évaluées / surévaluées » prévues au plan
/// auraient exigé des objectifs de cours analystes, absents du seed : les
/// inventer aurait produit une liste d'achats sur titres nommés fabriquée de
/// toutes pièces.
struct OracleAnalysisView: View {
    @Environment(OracleStore.self) private var oracle
    @Environment(TradingStore.self) private var trading

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            moversCard
            valuationCard
            dividendCard
        }
    }

    private var moversCard: some View {
        KrzCard {
            VStack(alignment: .leading, spacing: 10) {
                cardHeader(t("oracle.movers.title"), t("oracle.movers.subtitle"))

                let up = oracle.movers(trading.catalog, rising: true)
                let down = oracle.movers(trading.catalog, rising: false)

                if up.isEmpty && down.isEmpty {
                    Text(t("oracle.movers.empty"))
                        .font(KrezusFont.bodySm).foregroundStyle(KrezusColor.fg3)
                }
                ForEach(up, id: \.symbol) { moverRow($0) }
                if !up.isEmpty && !down.isEmpty {
                    Divider().overlay(KrezusColor.divider)
                }
                ForEach(down, id: \.symbol) { moverRow($0) }
            }
        }
    }

    private func moverRow(_ stock: StockInfo) -> some View {
        let change = oracle.changePct(stock)
        return HStack(spacing: 10) {
            Text(stock.name)
                .font(KrezusFont.body(13.5, .semibold)).foregroundStyle(KrezusColor.ink)
                .lineLimit(1)
            Spacer(minLength: 0)
            Text(Money.euros(stock.price))
                .font(KrezusFont.body(12.5)).foregroundStyle(KrezusColor.fg3).tabularNumbers()
            Text(Money.percent(change))
                .font(KrezusFont.body(12.5, .bold))
                .foregroundStyle(change >= 0 ? KrezusColor.up : KrezusColor.down)
                .tabularNumbers()
        }
        .padding(.vertical, 5)
    }

    private var valuationCard: some View {
        KrzCard {
            VStack(alignment: .leading, spacing: 10) {
                if let median = oracle.medianPE(trading.catalog) {
                    cardHeader(
                        t("oracle.valuation.title"),
                        t("oracle.valuation.subtitle", format(median)))

                    ForEach(oracle.valuationRows(trading.catalog).prefix(6)) { row in
                        HStack(spacing: 10) {
                            Text(row.name)
                                .font(KrezusFont.body(13.5, .semibold))
                                .foregroundStyle(KrezusColor.ink).lineLimit(1)
                            Spacer(minLength: 0)
                            if let pe = row.pe {
                                Text(t("oracle.valuation.pe", format(pe)))
                                    .font(KrezusFont.body(12.5)).foregroundStyle(KrezusColor.fg2)
                                    .tabularNumbers()
                                if let gap = row.gapToMedian {
                                    Text(Money.percent(gap))
                                        .font(KrezusFont.body(11.5, .semibold))
                                        .foregroundStyle(KrezusColor.fg3)
                                        .padding(.horizontal, 7).padding(.vertical, 2.5)
                                        .background(KrezusColor.tint).clipShape(Capsule())
                                        .tabularNumbers()
                                }
                            } else {
                                // Une donnée absente doit se voir : la masquer
                                // laisserait croire à une couverture complète.
                                Text(t("oracle.valuation.pe_missing"))
                                    .font(KrezusFont.body(11.5)).foregroundStyle(KrezusColor.fg3)
                            }
                        }
                        .padding(.vertical, 5)
                    }
                } else {
                    cardHeader(t("oracle.valuation.title"),
                               t("oracle.valuation.none"))
                }
            }
        }
    }

    private var dividendCard: some View {
        KrzCard {
            VStack(alignment: .leading, spacing: 10) {
                cardHeader(t("oracle.dividends.title"),
                           t("oracle.dividends.subtitle"))

                ForEach(oracle.dividendLeaders(trading.catalog), id: \.stock.symbol) { item in
                    HStack(spacing: 10) {
                        Text(item.stock.name)
                            .font(KrezusFont.body(13.5, .semibold))
                            .foregroundStyle(KrezusColor.ink).lineLimit(1)
                        Spacer(minLength: 0)
                        Text(MarketLabel.percent(item.stock.dividendYield))
                            .font(KrezusFont.body(13, .bold))
                            .foregroundStyle(KrezusColor.brandText).tabularNumbers()
                    }
                    .padding(.vertical, 5)
                }
            }
        }
    }

    private func cardHeader(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(KrezusFont.cardTitle).foregroundStyle(KrezusColor.ink)
            Text(subtitle)
                .font(KrezusFont.caption).foregroundStyle(KrezusColor.fg3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)).locale(L10n.locale))
    }
}
