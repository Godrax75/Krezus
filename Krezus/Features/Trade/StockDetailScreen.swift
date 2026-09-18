import SwiftUI

/// « Détail action » — en-tête, prix live, courbe, achat/vente, position détenue,
/// éclairage d'Hercule, fiche « Que fait l'entreprise ? », avertissement.
struct StockDetailScreen: View {
    let symbol: String
    @Environment(TradingStore.self) private var store
    @Environment(Router.self) private var router

    private var stock: StockInfo? { store.stock(symbol) }

    var body: some View {
        VStack(spacing: 0) {
            PushHeader(title: stock?.name ?? t("stock.fallback_title"))
            if let s = stock {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        identity(s)
                        priceBlock(s)
                        actions(s)
                        if store.owns(symbol) { positionCard(s) }
                        herculeCard(s)
                        aboutCard(s)
                        Text(t("disclaimer.not_advice"))
                            .font(KrezusFont.caption).foregroundStyle(KrezusColor.fg3)
                    }
                    .padding(.horizontal, KrezusSpacing.s4)
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
            }
        }
        .background(KrezusColor.surface.ignoresSafeArea())
        .navigationBarBackButtonHidden()
    }

    private func identity(_ s: StockInfo) -> some View {
        HStack(spacing: 12) {
            KrzSecurityBadge(logoAsset: s.logoAsset, initials: s.initials,
                             tileColor: Color(hex: s.tileHex), size: 44)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(s.name).font(KrezusFont.display(18, .bold)).foregroundStyle(KrezusColor.ink)
                    Text(s.cc).font(KrezusFont.body(10, .bold)).foregroundStyle(KrezusColor.fg3)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(KrezusColor.tint).clipShape(RoundedRectangle(cornerRadius: 4))
                }
                Text(s.sectorLocalized).font(KrezusFont.bodySm).foregroundStyle(KrezusColor.fg3)
            }
            Spacer()
        }
        .padding(.top, 4)
    }

    /// Cours, variation et courbe sur la période choisie.
    private func priceBlock(_ s: StockInfo) -> some View {
        StockChartCard(stock: s)
            .id(s.symbol)
    }

    private func actions(_ s: StockInfo) -> some View {
        HStack(spacing: 8) {
            Button { router.sheet = .buy(symbol) } label: {
                Text(t("common.buy")).font(KrezusFont.display(15, .bold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(KrezusColor.brandFill)
                    .clipShape(RoundedRectangle(cornerRadius: KrezusRadius.md, style: .continuous))
            }.buttonStyle(.plain)
            if store.owns(symbol) {
                Button { router.sheet = .sell(symbol) } label: {
                    Text(t("common.sell")).font(KrezusFont.display(15, .bold)).foregroundStyle(KrezusColor.brandText)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(KrezusColor.tintStrong)
                        .clipShape(RoundedRectangle(cornerRadius: KrezusRadius.md, style: .continuous))
                }.buttonStyle(.plain)
            }
        }
    }

    private func positionCard(_ s: StockInfo) -> some View {
        let qty = store.quantity(symbol)
        let gain = store.positionGain(symbol)
        return KrzCard {
            VStack(alignment: .leading, spacing: 4) {
                Text(t("stock.your_position")).font(KrezusFont.body(10, .bold)).tracking(0.8)
                    .foregroundStyle(KrezusColor.fg3)
                HStack(spacing: 6) {
                    Text(Money.shares(qty)).font(KrezusFont.stockName).foregroundStyle(KrezusColor.ink)
                    Text("· \(Money.euros(store.positionValue(symbol)))")
                        .font(KrezusFont.bodyMd).foregroundStyle(KrezusColor.fg2)
                }
                Text(t("stock.gain_since_purchase", (gain >= 0 ? "+" : "−") + Money.euros(abs(gain))))
                    .font(KrezusFont.body(12.5, .semibold))
                    .foregroundStyle(gain >= 0 ? KrezusColor.up : KrezusColor.down)
            }
        }
    }

    private func herculeCard(_ s: StockInfo) -> some View {
        KrzCard {
            HStack(alignment: .top, spacing: 12) {
                HerculeAvatar(size: 40)
                VStack(alignment: .leading, spacing: 6) {
                    Text(t("stock.hercule_explains")).font(KrezusFont.body(10, .bold)).tracking(0.8)
                        .foregroundStyle(KrezusColor.amberText)
                    Text(s.herculeLocalized).font(KrezusFont.bodyMd).foregroundStyle(KrezusColor.ink)
                }
            }
        }
    }

    private func aboutCard(_ s: StockInfo) -> some View {
        KrzCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(t("stock.about_title")).font(KrezusFont.cardTitle).foregroundStyle(KrezusColor.ink)
                Text(s.whatLocalized).font(KrezusFont.bodyMd).foregroundStyle(KrezusColor.fg2)
                factRow(t("stock.fact.country"), Country.name(s.cc))
                factRow(t("stock.fact.founded"), s.founded)
                factRow(t("stock.fact.dividend"), MarketLabel.percent(s.dividendYield))
                factRow(t("stock.fact.market_cap"), MarketLabel.marketCap(s.mcap))
                factRow(t("stock.fact.pe"), MarketLabel.ratio(s.pe))
                factRow(t("stock.fact.peg"), MarketLabel.ratio(s.peg))
                factRow(t("stock.fact.ceo"), s.ceo)
            }
        }
    }

    private func factRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(KrezusFont.bodySm).foregroundStyle(KrezusColor.fg3)
            Spacer()
            Text(value).font(KrezusFont.body(12.5, .semibold)).foregroundStyle(KrezusColor.ink)
        }
        .padding(.top, 2)
    }
}
