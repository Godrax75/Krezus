import SwiftUI

/// Onglet Accueil — « Krezus Forum ». Carte conseil Hercule, valeur du portefeuille,
/// missions du jour, mes actions, solde papier. Branché sur le `TradingStore`.
struct HomeScreen: View {
    @Environment(AppState.self) private var app
    @Environment(TradingStore.self) private var store
    @Environment(LearningStore.self) private var learning
    @Environment(Router.self) private var router

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                title
                herculeTip
                portfolioValueCard
                missionsCard
                myStocksCard
                cashCard
            }
            .padding(.horizontal, KrezusSpacing.s4)
            .padding(.top, 6)
            .padding(.bottom, 140)
        }
        .scrollIndicators(.hidden)
    }

    private var title: some View {
        HStack(spacing: 10) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 22)).foregroundStyle(KrezusColor.amber500)
            Text("Krezus Forum").font(KrezusFont.h1).foregroundStyle(KrezusColor.ink)
        }
        .padding(.top, 4)
    }

    private var herculeTip: some View {
        KrzCard(radius: KrezusRadius.lg, shadow: KrezusShadow.level2) {
            HStack(alignment: .top, spacing: 12) {
                HerculeAvatar(size: 46)
                VStack(alignment: .leading, spacing: 6) {
                    Text(t("home.hercule_tip.label"))
                        .font(KrezusFont.body(10, .bold)).tracking(0.8)
                        .foregroundStyle(KrezusColor.fg3)
                    Text(t("home.hercule_tip.body"))
                        .font(KrezusFont.bodyMd).foregroundStyle(KrezusColor.ink)
                    KrzPill(title: t("home.hercule_tip.cta"), bg: KrezusColor.tintStrong) {
                        router.cover = .hercule
                    }
                }
            }
        }
    }

    private var portfolioValueCard: some View {
        Button { app.tab = .portfolio } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(t("home.portfolio_value"))
                        .font(KrezusFont.body(12)).foregroundStyle(.white.opacity(0.65))
                    Spacer()
                    HStack(spacing: 5) {
                        Circle().fill(Color(hex: 0x6EE7A0)).frame(width: 6, height: 6)
                        Text(t("common.live")).font(KrezusFont.body(10.5, .semibold))
                    }
                    .foregroundStyle(Color(hex: 0x6EE7A0))
                }
                Text(Money.euros(cents: store.totalValueCents))
                    .font(KrezusFont.totalValue).foregroundStyle(.white)
                    .tabularNumbers().padding(.top, 4)
                Text(t("home.change_today", Money.percent(store.dayChangePct)))
                    .font(KrezusFont.body(13, .semibold))
                    .foregroundStyle(store.dayChangePct >= 0 ? Color(hex: 0x6EE7A0) : Color(hex: 0xFF9B9B))
                    .tabularNumbers()
                sparkline.padding(.top, 10)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(KrezusColor.gradientNavy)
            .clipShape(RoundedRectangle(cornerRadius: KrezusRadius.lg, style: .continuous))
            .krezusShadow(KrezusShadow.brand)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(t("a11y.open_portfolio"))
    }

    private var sparkline: some View {
        GeometryReader { geo in
            let pts: [CGFloat] = [0.5, 0.42, 0.55, 0.38, 0.6, 0.32, 0.45, 0.2, 0.3, 0.12]
            Path { p in
                for (i, v) in pts.enumerated() {
                    let x = geo.size.width * CGFloat(i) / CGFloat(pts.count - 1)
                    let y = geo.size.height * v
                    if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
                    else { p.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(.white.opacity(0.85), style: StrokeStyle(lineWidth: 2, lineJoin: .round))
        }
        .frame(height: 48)
        .accessibilityHidden(true)
    }

    private var missionsCard: some View {
        KrzCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(t("home.missions")).font(KrezusFont.cardTitle).foregroundStyle(KrezusColor.ink)
                    Spacer()
                    Text("\(learning.missionsDoneCount)/\(LearningStore.missions.count)")
                        .font(KrezusFont.display(12.5, .bold)).foregroundStyle(KrezusColor.amber600)
                }
                .padding(.bottom, 6)

                ForEach(LearningStore.missions) { mission in
                    let done = learning.isMissionDone(mission.code)
                    let action = done ? nil : missionAction(mission.code)
                    Button { action?() } label: {
                    HStack(spacing: 11) {
                        ZStack {
                            Circle().fill(done ? KrezusColor.up : Color.clear)
                                .overlay(Circle().stroke(done ? Color.clear : KrezusColor.border, lineWidth: 1.5))
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .heavy))
                                .foregroundStyle(done ? .white : KrezusColor.fg4)
                        }
                        .frame(width: 22, height: 22)
                        Text(mission.title)
                            .font(KrezusFont.bodyMd)
                            .foregroundStyle(done ? KrezusColor.fg3 : KrezusColor.ink)
                            .strikethrough(done, color: KrezusColor.fg3)
                        Spacer()
                        Text(t("common.xp_badge", mission.xp))
                            .font(KrezusFont.body(11.5, .bold))
                            .foregroundStyle(KrezusColor.amberText)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(KrezusColor.amberTint).clipShape(Capsule())
                        // Le chevron dit qu'on peut y aller : une mission faite,
                        // ou sans destination, n'en a pas.
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(KrezusColor.fg4)
                            .opacity(action == nil ? 0 : 1)
                    }
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(action == nil)
                }

                // Raccourci vers la leçon à suivre : les missions restent
                // décoratives si rien ne mène à l'action qui les valide.
                if let next = learning.nextLesson, learning.missionsDoneCount < LearningStore.missions.count {
                    Divider().overlay(KrezusColor.divider).padding(.vertical, 2)
                    Button { router.push(.lesson(next.position)) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "play.circle.fill")
                                .foregroundStyle(KrezusColor.brandText)
                            Text(t("home.next_lesson", next.position, next.title))
                                .font(KrezusFont.body(12.5, .semibold))
                                .foregroundStyle(KrezusColor.brandText)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(KrezusColor.fg4)
                        }
                        .padding(.top, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Où mène chaque mission. La leçon et le quiz du jour s'accomplissent
    /// sur la prochaine leçon à suivre ; sans leçon accessible (toutes faites,
    /// ou la suite réservée à Premium), l'Academy montre où en est l'élève.
    /// « Activer ton compte » est validée d'office à l'inscription : rien à
    /// ouvrir.
    private func missionAction(_ code: String) -> (() -> Void)? {
        switch code {
        case "lesson":
            if let next = learning.nextLesson { return { router.push(.lesson(next.position)) } }
            return { app.tab = .academy }
        case "quiz":
            if let next = learning.nextLesson {
                return next.quiz != nil
                    ? { router.push(.quiz(next.position)) }
                    : { router.push(.lesson(next.position)) }
            }
            return { app.tab = .academy }
        default:
            return nil
        }
    }

    private var myStocksCard: some View {
        KrzCard(padding: KrezusSpacing.s4) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(t("home.my_stocks")).font(KrezusFont.cardTitle).foregroundStyle(KrezusColor.ink)
                    Spacer()
                    Button { app.tab = .portfolio } label: {
                        Text(t("common.see_all")).font(KrezusFont.body(12.5, .semibold))
                            .foregroundStyle(KrezusColor.brandText)
                    }.buttonStyle(.plain)
                }
                .padding(.bottom, 4)
                ForEach(Array(store.holdingSymbols.enumerated()), id: \.element) { index, symbol in
                    if let s = store.stock(symbol) {
                        if index > 0 { Divider().overlay(KrezusColor.tint) }
                        let chg = (s.price - s.open) / s.open * 100
                        KrzStockRow(
                            name: s.name, subtitle: Money.shares(store.quantity(symbol)),
                            value: Money.euros(store.positionValue(symbol)),
                            change: Money.percent(chg),
                            changeColor: chg >= 0 ? KrezusColor.up : KrezusColor.down,
                            logoAsset: s.logoAsset, initials: s.initials, badgeText: s.cc,
                            action: { router.push(.stock(symbol)) })
                    }
                }
            }
        }
    }

    private var cashCard: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(t("home.paper_balance")).font(KrezusFont.body(11, .bold)).tracking(0.6)
                        .foregroundStyle(KrezusColor.brandText)
                    Text(Money.euros(cents: store.cashCents)).font(KrezusFont.display(28, .heavy))
                        .foregroundStyle(KrezusColor.brandText).tabularNumbers()
                }
                Spacer()
            }
            // Rappel du versement hebdomadaire : c'est lui qui fait revenir.
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.plus")
                    .foregroundStyle(KrezusColor.amberText)
                Text(t("home.weekly_bonus", WeeklyBonus.label(for: store.nextBonusDate)))
                    .font(KrezusFont.body(12.5, .semibold))
                    .foregroundStyle(KrezusColor.brandText)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            KrzPrimaryButton(title: t("home.explore_cta")) { router.push(.market) }
        }
        .padding(KrezusSpacing.s4)
        .background(KrezusColor.tintStrong)
        .clipShape(RoundedRectangle(cornerRadius: KrezusRadius.lg, style: .continuous))
    }
}
