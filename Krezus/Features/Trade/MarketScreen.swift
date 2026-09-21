import SwiftUI

/// « Explorer » — le catalogue, actions et ETF séparés, filtrables par zone
/// géographique, regroupés par famille de secteur ou par zone, avec
/// recherche, prix, variation et badge « déjà en portefeuille ».
struct MarketScreen: View {
    @Environment(TradingStore.self) private var store
    @Environment(Router.self) private var router
    @State private var query = ""
    @State private var searchOpen = false
    @State private var kind: AssetType = .stock
    @State private var grouping: Grouping = .sector
    /// `nil` = toutes les zones.
    @State private var zone: MarketZone?

    enum Grouping: Hashable { case sector, region }

    /// Titres du type choisi, regroupés dans l'ordre fixe des familles ou des
    /// zones. Un ordre stable vaut mieux qu'un tri par effectif : on retrouve
    /// « Finance » au même endroit d'une visite à l'autre.
    private var sections: [(id: String, title: String, items: [StockInfo])] {
        let shown = results.filter { $0.assetType == kind && (zone == nil || $0.zone == zone) }
        let byName: (StockInfo, StockInfo) -> Bool = {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        switch grouping {
        case .sector:
            let groups = Dictionary(grouping: shown, by: \.sectorGroup)
            return SectorGroup.allCases.compactMap { group in
                guard let items = groups[group], !items.isEmpty else { return nil }
                return (group.rawValue, group.label, items.sorted(by: byName))
            }
        case .region:
            let groups = Dictionary(grouping: shown, by: \.zone)
            return MarketZone.allCases.compactMap { zone in
                guard let items = groups[zone], !items.isEmpty else { return nil }
                return (zone.rawValue, "\(zone.emoji) \(zone.label)", items.sorted(by: byName))
            }
        }
    }

    private func count(_ type: AssetType) -> Int {
        results.filter { $0.assetType == type && (zone == nil || $0.zone == zone) }.count
    }

    /// Titres de chaque zone pour le type choisi : une zone vide n'est pas
    /// proposée, un filtre qui ne renvoie rien ne sert à rien.
    private var zoneCounts: [(zone: MarketZone, count: Int)] {
        let counts = Dictionary(grouping: results.filter { $0.assetType == kind }, by: \.zone)
            .mapValues(\.count)
        return MarketZone.allCases.compactMap { zone in
            guard let count = counts[zone], count > 0 else { return nil }
            return (zone, count)
        }
    }

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

            VStack(spacing: KrezusSpacing.s2) {
                KrzSegmented(
                    options: [(AssetType.stock, t("market.kind.stocks", count(.stock))),
                              (AssetType.etf, t("market.kind.etfs", count(.etf)))],
                    selection: $kind)

                zoneFilter

                HStack(spacing: 6) {
                    Text(t("market.group_by"))
                        .font(KrezusFont.body(12.5, .medium))
                        .foregroundStyle(KrezusColor.fg3)
                    groupingChip(.sector, label: t("market.group.sector"))
                    groupingChip(.region, label: t("market.group.region"))
                    Spacer()
                }
            }
            .padding(.horizontal, KrezusSpacing.s4)
            .padding(.bottom, KrezusSpacing.s2)

            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    if sections.isEmpty {
                        Text(kind == .etf ? t("market.empty.etfs") : t("market.empty.stocks"))
                            .font(KrezusFont.bodySm).foregroundStyle(KrezusColor.fg3)
                            .multilineTextAlignment(.center)
                            .padding(.vertical, 40)
                    }
                    ForEach(sections, id: \.id) { section in
                        Section {
                            ForEach(Array(section.items.enumerated()), id: \.element.id) { index, s in
                                if index > 0 { Divider().overlay(KrezusColor.tint).padding(.leading, 64) }
                                Button { router.push(.stock(s.symbol)) } label: {
                                    marketRow(s)
                                }
                                .buttonStyle(.plain)
                            }
                        } header: {
                            sectionHeader(section.title, count: section.items.count)
                        }
                    }
                }
                .padding(.horizontal, KrezusSpacing.s4)

                Text(t("market.delayed_note"))
                    .font(KrezusFont.caption).foregroundStyle(KrezusColor.fg3)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            }
            .scrollIndicators(.hidden)
            .animation(.snappy(duration: 0.2), value: kind)
            .animation(.snappy(duration: 0.2), value: grouping)
            .animation(.snappy(duration: 0.2), value: zone)
        }
        .background(KrezusColor.bg.ignoresSafeArea())
        .navigationBarBackButtonHidden()
    }

    /// Filtre par zone : « Toutes », puis chaque zone représentée, avec son
    /// effectif. Défile horizontalement, la liste des zones dépassant la
    /// largeur d'un iPhone.
    private var zoneFilter: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                zoneChip(nil, label: t("zone.all"), count: nil)
                ForEach(zoneCounts, id: \.zone) { item in
                    zoneChip(item.zone, label: "\(item.zone.emoji) \(item.zone.label)", count: item.count)
                }
            }
            .padding(.horizontal, 1)
        }
        .scrollIndicators(.hidden)
        // Un filtre devenu vide (après un changement de type) retombe sur
        // « Toutes » plutôt que d'afficher une liste blanche.
        .onChange(of: kind) { _, _ in
            if let zone, !zoneCounts.contains(where: { $0.zone == zone }) { self.zone = nil }
        }
    }

    private func zoneChip(_ value: MarketZone?, label: String, count: Int?) -> some View {
        let selected = zone == value
        return Button { zone = value } label: {
            HStack(spacing: 5) {
                Text(label).lineLimit(1)
                if let count {
                    Text("\(count)")
                        .foregroundStyle(selected ? KrezusColor.brandText.opacity(0.7) : KrezusColor.fg4)
                        .tabularNumbers()
                }
            }
            .font(KrezusFont.body(12.5, .semibold))
            .foregroundStyle(selected ? KrezusColor.brandText : KrezusColor.fg2)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(selected ? KrezusColor.tintStrong : KrezusColor.tint)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private func groupingChip(_ value: Grouping, label: String) -> some View {
        let selected = grouping == value
        return Button { grouping = value } label: {
            Text(label)
                .font(KrezusFont.body(12.5, .semibold))
                .foregroundStyle(selected ? KrezusColor.brandText : KrezusColor.fg3)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(selected ? KrezusColor.tintStrong : KrezusColor.tint)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    /// En-tête de section, épinglé en haut pendant le défilement : on sait
    /// toujours dans quelle famille on se trouve.
    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack {
            Text(title.uppercased())
                .font(KrezusFont.body(11, .bold)).tracking(0.8)
                .foregroundStyle(KrezusColor.fg3)
            Spacer()
            Text("\(count)")
                .font(KrezusFont.body(11, .bold))
                .foregroundStyle(KrezusColor.fg4)
                .tabularNumbers()
        }
        .padding(.top, 16).padding(.bottom, 6)
        .background(KrezusColor.bg)
        .accessibilityAddTraits(.isHeader)
    }

    private func marketRow(_ s: StockInfo) -> some View {
        HStack(spacing: KrezusSpacing.s3) {
            KrzSecurityBadge(logoAsset: s.logoAsset, logoURL: s.logoURL, initials: s.initials,
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
                // Un titre sans cotation affiche le tiret cadratin utilisé
                // partout pour « donnée non publiée », pas un cours de 0 €.
                Text(s.hasQuote ? Money.euros(s.price) : "—").font(KrezusFont.numeric)
                    .foregroundStyle(s.hasQuote ? KrezusColor.ink : KrezusColor.fg4)
                    .tabularNumbers()
                if let chg = s.changePct {
                    Text(Money.percent(chg)).font(KrezusFont.body(12, .semibold))
                        .foregroundStyle(chg >= 0 ? KrezusColor.up : KrezusColor.down)
                        .tabularNumbers()
                }
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
