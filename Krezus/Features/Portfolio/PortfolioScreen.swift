import SwiftUI

/// Onglet Portefeuille — valeur totale, solde disponible, courbe, répartition,
/// positions. Branché sur le `TradingStore`.
struct PortfolioScreen: View {
    @Environment(TradingStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(t("portfolio.title")).font(KrezusFont.h1).foregroundStyle(KrezusColor.ink)
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(Money.euros(cents: store.totalValueCents)).font(KrezusFont.portfolio)
                            .foregroundStyle(KrezusColor.brandText).tabularNumbers()
                        Text(Money.percent(store.dayChangePct)).font(KrezusFont.body(13.5, .semibold))
                            .foregroundStyle(store.dayChangePct >= 0 ? KrezusColor.up : KrezusColor.down)
                            .tabularNumbers()
                    }
                }
                .padding(.top, 4)

                availableBalance
                if !store.allocation.isEmpty { allocationCard }
                positionsCard
            }
            .padding(.horizontal, KrezusSpacing.s4)
            .padding(.top, 6)
            .padding(.bottom, 140)
        }
        .scrollIndicators(.hidden)
    }

    private var availableBalance: some View {
        HStack(spacing: 12) {
            Circle().fill(KrezusColor.surface).frame(width: 42, height: 42)
                .overlay(Image(systemName: "creditcard.fill").foregroundStyle(KrezusColor.brandText))
            VStack(alignment: .leading, spacing: 2) {
                Text(t("portfolio.available_balance")).font(KrezusFont.body(11, .bold)).tracking(0.6)
                    .foregroundStyle(KrezusColor.brandText)
                Text(Money.euros(cents: store.cashCents)).font(KrezusFont.display(22, .heavy))
                    .foregroundStyle(KrezusColor.brandText).tabularNumbers()
            }
            Spacer()
        }
        .padding(KrezusSpacing.s4)
        .background(KrezusColor.tintStrong)
        .clipShape(RoundedRectangle(cornerRadius: KrezusRadius.lg, style: .continuous))
    }

    private var allocationCard: some View {
        let palette: [Color] = [KrezusColor.brandFill, KrezusColor.amber500, KrezusColor.up,
                                KrezusColor.brandText, KrezusColor.amber600]
        return KrzCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(t("portfolio.allocation")).font(KrezusFont.cardTitle).foregroundStyle(KrezusColor.ink)
                ForEach(Array(store.allocation.enumerated()), id: \.element.label) { index, item in
                    VStack(spacing: 5) {
                        HStack {
                            Text(item.label).font(KrezusFont.bodySm).foregroundStyle(KrezusColor.fg2)
                            Spacer()
                            Text(t("format.percent_int", Int((item.pct * 100).rounded())))
                                .font(KrezusFont.body(12.5, .bold)).foregroundStyle(KrezusColor.ink)
                                .tabularNumbers()
                        }
                        KrzProgressBar(value: item.pct, fill: palette[index % palette.count])
                    }
                }
            }
        }
    }

    private var positionsCard: some View {
        KrzCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(t("portfolio.positions")).font(KrezusFont.cardTitle).foregroundStyle(KrezusColor.ink)
                    Spacer()
                    Button { router.push(.market) } label: {
                        Text(t("portfolio.explore_link")).font(KrezusFont.body(12.5, .semibold))
                            .foregroundStyle(KrezusColor.brandText)
                    }.buttonStyle(.plain)
                }
                .padding(.bottom, 4)
                if store.holdingSymbols.isEmpty {
                    Text(t("portfolio.empty"))
                        .font(KrezusFont.bodySm).foregroundStyle(KrezusColor.fg3)
                        .padding(.vertical, 12)
                }
                ForEach(Array(store.holdingSymbols.enumerated()), id: \.element) { index, symbol in
                    if let s = store.stock(symbol) {
                        if index > 0 { Divider().overlay(KrezusColor.tint) }
                        let chg = (s.price - s.open) / s.open * 100
                        KrzStockRow(
                            name: s.name,
                            subtitle: "\(Money.shares(store.quantity(symbol))) · \(Money.euros(s.price))",
                            value: Money.euros(store.positionValue(symbol)),
                            change: Money.percent(chg),
                            changeColor: chg >= 0 ? KrezusColor.up : KrezusColor.down,
                            logoAsset: s.logoAsset, initials: s.initials, badgeText: nil,
                            action: { router.push(.stock(symbol)) })
                    }
                }
            }
        }
    }
}
