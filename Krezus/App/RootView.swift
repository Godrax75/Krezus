import SwiftUI

/// Shell de l'application : en-tête, contenu de l'onglet actif, tab bar flottante
/// et FAB Hercule, le tout dans un `NavigationStack` qui pousse les écrans de
/// trading. Reproduit la structure `App` du prototype.
struct RootView: View {
    @Environment(AppState.self) private var app
    @Environment(TradingStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.path) {
            rootContent
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .market:              MarketScreen()
                    case .stock(let symbol):   StockDetailScreen(symbol: symbol)
                    case .lesson(let position): LessonScreen(position: position)
                    case .quiz(let position):   QuizScreen(position: position)
                    case .ranks:               RanksScreen()
                    case .paywall:             PaywallScreen()
                    case .profile:             ProfileScreen()
                    case .editUsername:        EditUsernameScreen()
                    case .streak:              StreakScreen()
                    case .settings:            SettingsScreen()
                    case .security:            SecurityScreen()
                    case .notificationSettings: NotificationSettingsScreen()
                    case .notificationCenter:  NotificationCenterScreen()
                    case .help:                HelpScreen()
                    case .referral:            ReferralScreen()
                    case .locked(let feature): ComingSoonScreen(feature: feature)
                    }
                }
        }
        .fullScreenCover(item: $router.sheet) { sheet in
            switch sheet {
            case .buy(let symbol):  BuyScreen(symbol: symbol)
            case .sell(let symbol): SellScreen(symbol: symbol)
            }
        }
        .sheet(item: $router.cover) { cover in
            switch cover {
            case .hercule:    HerculeChatScreen()
            case .modeSwitch: ModeSwitchSheet()
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = router.toast {
                Text(toast)
                    .font(KrezusFont.body(13, .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .background(KrezusColor.ink).clipShape(Capsule())
                    .padding(.bottom, 120)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .task { store.startLiveTicks() }
    }

    private var rootContent: some View {
        ZStack(alignment: .bottom) {
            KrezusColor.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                KrezusHeader()
                content
            }

            // Fondu sous la barre flottante : sans lui, le contenu défilait
            // jusqu'au bord de l'écran et se montrait coupé entre la barre et
            // l'indicateur d'accueil.
            // Le conteneur, et non le dégradé, ignore la zone sûre : un cadre
            // de hauteur fixe ne s'étend pas sous l'indicateur d'accueil.
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                LinearGradient(
                    stops: [
                        .init(color: KrezusColor.bg.opacity(0), location: 0),
                        .init(color: KrezusColor.bg.opacity(0.94), location: 0.38),
                        .init(color: KrezusColor.bg, location: 0.5),
                    ],
                    startPoint: .top, endPoint: .bottom)
                    .frame(height: 160)
            }
            .ignoresSafeArea(edges: .bottom)
            .allowsHitTesting(false)

            KrezusTabBar()

            HerculeFab()
                .padding(.trailing, KrezusSpacing.s4)
                .padding(.bottom, 96)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: Binding(
            get: { store.freshBonusCents != nil },
            set: { if !$0 { store.freshBonusCents = nil } })) {
            WeeklyBonusSheet(cents: store.freshBonusCents ?? WeeklyBonus.weeklyCents,
                             nextDate: store.nextBonusDate) {
                store.freshBonusCents = nil
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch app.tab {
        case .home:      HomeScreen()
        case .portfolio: PortfolioScreen()
        case .oracle:    OracleScreen()
        case .arena:     ArenaScreen()
        case .academy:   AcademyScreen()
        }
    }
}

// MARK: - En-tête

struct KrezusHeader: View {
    @Environment(AppState.self) private var app
    @Environment(LearningStore.self) private var learning
    @Environment(NotificationStore.self) private var notifications
    @Environment(ProfileStore.self) private var profile
    @Environment(Router.self) private var router

    var body: some View {
        HStack(spacing: KrezusSpacing.s2) {
            Image("krezus-mascot").resizable().scaledToFit().frame(width: 30, height: 30)
                .accessibilityHidden(true)
            Text("Krezus")
                .font(KrezusFont.wordmark)
                .foregroundStyle(KrezusColor.brandText)
                // Aux plus grandes tailles de texte, l'en-tête doit loger le
                // wordmark, la pastille de mode et trois actions : la marque
                // rétrécit plutôt que de se couper en deux.
                .lineLimit(1).minimumScaleFactor(0.6)

            Button { router.cover = .modeSwitch } label: {
                HStack(spacing: 5) {
                    Circle().fill(KrezusColor.amberText).frame(width: 6, height: 6)
                    // « Paper » ne doit pas se couper en deux quand la place
                    // manque : la pastille garde sa largeur, c'est au titre
                    // d'écran de céder.
                    Text(app.mode.label).font(KrezusFont.display(10.5, .heavy))
                        .lineLimit(1).fixedSize()
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .heavy))
                }
                .foregroundStyle(KrezusColor.amberText)
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(KrezusColor.amberTint)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Spacer()

            Button { router.push(.streak) } label: {
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill").font(.system(size: 13))
                    Text("\(learning.streakDays)").font(KrezusFont.display(12, .bold))
                }
                .foregroundStyle(KrezusColor.amberText)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(KrezusColor.amberTint)
                .clipShape(Capsule())
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(t("a11y.streak", learning.streakDays))

            circleButton(system: "bell.fill", badge: notifications.unreadCount) {
                router.push(.notificationCenter)
            }
            .accessibilityLabel(notifications.unreadCount > 0
                                ? t("a11y.notifications_unread", notifications.unreadCount)
                                : t("a11y.notifications"))

            Button { router.push(.profile) } label: {
                KrzAvatar(initial: profile.initial, image: profile.avatar)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(t("a11y.profile"))
        }
        .padding(.horizontal, KrezusSpacing.s4)
        .padding(.top, KrezusSpacing.s2)
        .padding(.bottom, KrezusSpacing.s2)
    }

    private func circleButton(system: String, badge: Int,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(KrezusColor.brandText)
                .frame(width: 32, height: 32)
                .background(KrezusColor.surface)
                .clipShape(Circle())
                .krezusShadow(KrezusShadow.level1)
                .overlay(alignment: .topTrailing) {
                    if badge > 0 {
                        Text("\(badge)")
                            .font(KrezusFont.display(10, .bold))
                            .foregroundStyle(.white)
                            .frame(minWidth: 16, minHeight: 16)
                            .background(KrezusColor.amberText)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(KrezusColor.bg, lineWidth: 2))
                            .offset(x: 3, y: -3)
                    }
                }
                // La pastille visible fait 32 pt ; la zone tactile est portée au
                // minimum de 44 pt recommandé, sans déplacer le dessin.
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tab bar

struct KrezusTabBar: View {
    @Environment(AppState.self) private var app
    @Environment(Router.self) private var router
    @Environment(\.colorScheme) private var scheme
    @Namespace private var selection

    /// Clair : verre blanc, texte encre, onglet actif bleu marque sur une
    /// pastille grise. Sombre : verre bleu nuit, onglet actif orange Hercule.
    private var isDark: Bool { scheme == .dark }
    private var accent: Color { isDark ? KrezusColor.amber500 : KrezusColor.brandText }
    private var idle: Color { isDark ? .white.opacity(0.92) : KrezusColor.fg2 }
    private var pill: Color { isDark ? .white.opacity(0.13) : .black.opacity(0.07) }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(KrezusTab.allCases) { tab in
                let isSelected = app.tab == tab
                Button {
                    router.popToRoot()
                    withAnimation(.snappy(duration: 0.28)) { app.tab = tab }
                } label: {
                    VStack(spacing: 4) {
                        // Hauteur fixe : chaque symbole a la sienne, et sans
                        // cadre commun les libellés ne s'alignaient pas.
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 20, weight: .semibold))
                            .frame(height: 24)
                        Text(tab.label)
                            .font(KrezusFont.body(10.5, isSelected ? .bold : .medium))
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(isSelected ? accent : idle)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background {
                        // Pastille de l'onglet actif : elle glisse d'un onglet
                        // à l'autre plutôt que de disparaître et réapparaître.
                        if isSelected {
                            Capsule()
                                .fill(pill)
                                .matchedGeometryEffect(id: "selection", in: selection)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.label)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(6)
        .modifier(TabBarGlass(isDark: isDark))
        .padding(.horizontal, KrezusSpacing.s3)
    }
}

/// Fond de la barre. En clair, le verre liquide d'iOS 26 (un flou blanc
/// sur les versions antérieures) ; en sombre, le verre bleu nuit.
private struct TabBarGlass: ViewModifier {
    let isDark: Bool

    func body(content: Content) -> some View {
        if isDark {
            content
                .background {
                    ZStack {
                        Capsule().fill(.ultraThinMaterial).environment(\.colorScheme, .dark)
                        Capsule().fill(
                            LinearGradient(colors: [Color(hex: 0x1D2152).opacity(0.92),
                                                    Color(hex: 0x0D1030).opacity(0.94)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                }
                .overlay {
                    // Liseré plus vif à gauche, qui s'éteint vers la droite.
                    Capsule().strokeBorder(
                        LinearGradient(colors: [Color(hex: 0x6A6FE0).opacity(0.75), .white.opacity(0.10)],
                                       startPoint: .leading, endPoint: .trailing),
                        lineWidth: 1.2)
                }
                .shadow(color: Color(hex: 0x0D1030).opacity(0.35), radius: 18, y: 8)
        } else if #available(iOS 26, *) {
            content
                .glassEffect(.regular, in: .capsule)
                .shadow(color: .black.opacity(0.10), radius: 16, y: 6)
        } else {
            content
                .background {
                    ZStack {
                        Capsule().fill(.ultraThinMaterial)
                        Capsule().fill(.white.opacity(0.55))
                    }
                }
                .overlay {
                    // Reflet en haut, gris en bas : l'épaisseur d'un verre.
                    Capsule().strokeBorder(
                        LinearGradient(colors: [.white, .black.opacity(0.08)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.10), radius: 16, y: 6)
        }
    }
}

// MARK: - FAB Hercule

struct HerculeFab: View {
    @Environment(Router.self) private var router

    var body: some View {
        Button { router.cover = .hercule } label: {
            HerculeAvatar(size: 58, ring: true)
                .krezusShadow(KrezusShadow.brand)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(t("a11y.hercule_fab"))
        .accessibilityHint(t("a11y.hercule_fab.hint"))
    }
}
