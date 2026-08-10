import SwiftUI

/// « Explorer les actions » — liste du catalogue avec recherche, prix et
/// variation, badge « déjà en portefeuille ». Reproduit l'écran Marché du design.
struct MarketScreen: View {
    @Environment(TradingStore.self) private var store
    @Environment(Router.self) private var router
    @State private var query = ""
    @State private var searchOpen = false

    private var results: [StockInfo] {
        guard !query.isEmpty else { return store.catalog }
        return store.catalog.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.symbol.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            PushHeader(title: t("market.title")) {
                Button { withAnimation { searchOpen.toggle() } } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(KrezusColor.brandText)
                }
                .accessibilityLabel(t("a11y.search"))
            }

            if searchOpen {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(KrezusColor.fg3)
                    TextField(t("market.search_placeholder"), text: $query)
                        .font(KrezusFont.bodyMd)
                        .autocorrectionDisabled()
                }
                .padding(12)
                .background(KrezusColor.tint)
                .clipShape(RoundedRectangle(cornerRadius: KrezusRadius.md, style: .continuous))
                .padding(.horizontal, KrezusSpacing.s4)
                .padding(.bottom, 8)
            }

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, s in
                        if index > 0 { Divider().overlay(KrezusColor.tint).padding(.leading, 64) }
                        Button { router.push(.stock(s.symbol)) } label: {
                            marketRow(s)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, KrezusSpacing.s4)

                Text(t("market.delayed_note"))
                    .font(KrezusFont.caption).foregroundStyle(KrezusColor.fg3)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            }
            .scrollIndicators(.hidden)
        }
        .background(KrezusColor.bg.ignoresSafeArea())
        .navigationBarBackButtonHidden()
    }

    private func marketRow(_ s: StockInfo) -> some View {
        HStack(spacing: KrezusSpacing.s3) {
            KrzSecurityBadge(logoAsset: s.logoAsset, initials: s.initials,
                             tileColor: Color(hex: s.tileHex))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(s.name).font(KrezusFont.stockName).foregroundStyle(KrezusColor.ink)
                    Text(s.cc).font(KrezusFont.body(9.5, .bold)).foregroundStyle(KrezusColor.fg3)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(KrezusColor.tint).clipShape(RoundedRectangle(cornerRadius: 4))
                }
                if store.owns(s.symbol) {
                    Text(t("market.already_owned"))
                        .font(KrezusFont.body(11, .semibold)).foregroundStyle(KrezusColor.brandText)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(Money.euros(s.price)).font(KrezusFont.numeric)
                    .foregroundStyle(KrezusColor.ink).tabularNumbers()
                let chg = (s.price - s.open) / s.open * 100
                Text(Money.percent(chg)).font(KrezusFont.body(12, .semibold))
                    .foregroundStyle(chg >= 0 ? KrezusColor.up : KrezusColor.down).tabularNumbers()
            }
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

/// En-tête d'écran poussé : flèche retour + titre centré + action optionnelle.
struct PushHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing
    @Environment(Router.self) private var router

    init(title: String, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        ZStack {
            Text(title).font(KrezusFont.display(17, .bold)).foregroundStyle(KrezusColor.ink)
            HStack {
                Button { if !router.path.isEmpty { router.path.removeLast() } } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(KrezusColor.brandText)
                        .frame(width: 32, height: 32)
                        .background(KrezusColor.surface).clipShape(Circle())
                        .krezusShadow(KrezusShadow.level1)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(t("common.back"))
                Spacer()
                trailing
            }
        }
        .padding(.horizontal, KrezusSpacing.s4)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }
}
