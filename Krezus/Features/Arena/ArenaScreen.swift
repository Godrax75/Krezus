import SwiftUI

/// Onglet Arena — quatre sections : Classement, Amis, Feed, Groupes.
///
/// Règle qui traverse tout l'écran : on compare des **performances en
/// pourcentage**, jamais des montants. Le portefeuille d'un ami ne regarde
/// personne ; sa progression, si.
struct ArenaScreen: View {
    @Environment(ArenaStore.self) private var arena
    @Environment(TradingStore.self) private var trading
    @Environment(LearningStore.self) private var learning

    @State private var section: Section = .leaderboard
    @State private var period: RankingPeriod = .week
    @State private var scope: RankingScope = .global

    enum Section: String, CaseIterable, Identifiable {
        case leaderboard, friends, feed, groups
        var id: String { rawValue }

        var label: String {
            switch self {
            case .leaderboard: return t("arena.tab.leaderboard")
            case .friends:     return t("arena.tab.friends")
            case .feed:        return t("arena.tab.feed")
            case .groups:      return t("arena.tab.groups")
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                KrzSectionTitle(systemImage: "trophy.fill", title: "Krezus Arena")
                picker

                switch section {
                case .leaderboard: leaderboardSection
                case .friends:     ArenaFriendsView()
                case .feed:        ArenaFeedView()
                case .groups:      ArenaGroupsView()
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

    // MARK: Classement

    /// Performance mesurée contre le capital de départ (1 000 €), comme le
    /// serveur. La rapporter au solde courant permettrait de figer un bon
    /// score en vendant tout. Ne sert qu'en démo : en mode serveur, chacun est
    /// mesuré par `arena_leaderboard`.
    private var myPerformance: Double {
        (Double(trading.totalValueCents) - 100_000) / 1_000
    }

    /// Clé de rechargement : période, portée et groupe filtré.
    private var rankingKey: String {
        "\(period.rawValue)-\(scope.rawValue)-\(arena.selectedGroup?.id.uuidString ?? "")"
    }

    private var leaderboardSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let group = arena.selectedGroup {
                HStack(spacing: 8) {
                    Text(t("arena.group_filter", group.name))
                        .font(KrezusFont.body(12.5, .semibold))
                        .foregroundStyle(KrezusColor.brandText)
                    Spacer()
                    Button { arena.selectedGroup = nil } label: {
                        Text(t("arena.see_all_friends"))
                            .font(KrezusFont.body(12)).foregroundStyle(KrezusColor.amberText)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                KrzSegmented(options: RankingScope.allCases.map { ($0, $0.label) }, selection: $scope)
            }

            periodPicker

            KrzCard(padding: KrezusSpacing.s4) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text(t("arena.performance_title"))
                            .font(KrezusFont.cardTitle).foregroundStyle(KrezusColor.ink)
                        Spacer()
                        if arena.isRankingLoading { ProgressView().controlSize(.small) }
                    }
                    Text(period.subtitle)
                        .font(KrezusFont.caption).foregroundStyle(KrezusColor.fg3)
                        .padding(.bottom, 10)
                        .fixedSize(horizontal: false, vertical: true)

                    let players = arena.ranking
                    ForEach(Array(players.enumerated()), id: \.element.id) { index, player in
                        if index > 0 {
                            // Hors des cent premiers, on se voit quand même : un
                            // trait pointillé signale le saut de places.
                            if let place = player.place, let previous = players[index - 1].place, place > previous + 1 {
                                Text("⋯").font(KrezusFont.body(14, .bold)).foregroundStyle(KrezusColor.fg4)
                                    .frame(maxWidth: .infinity).padding(.vertical, 2)
                            } else {
                                Divider().overlay(KrezusColor.divider)
                            }
                        }
                        row(rank: player.place ?? index + 1, player: player)
                    }
                    if players.count <= 1 && !arena.isRankingLoading {
                        Text(scope == .friends ? t("arena.ranking.empty_friends") : t("arena.ranking.empty_global"))
                            .font(KrezusFont.bodySm).foregroundStyle(KrezusColor.fg3)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 8)
                    }
                }
            }
        }
        .task(id: rankingKey) {
            await arena.loadRanking(period: period, scope: scope,
                                    myPerformance: myPerformance,
                                    myStreak: learning.streakDays,
                                    myRank: learning.rankLevel,
                                    myEmoji: learning.currentRank?.emoji ?? "🏛️")
            await arena.loadAvatars(for: arena.ranking.map(\.id))
        }
    }

    private var periodPicker: some View {
        HStack(spacing: 4) {
            ForEach(RankingPeriod.allCases) { item in
                Button { period = item } label: {
                    Text(item.label)
                        .font(KrezusFont.body(12.5, .bold))
                        .foregroundStyle(item == period ? KrezusColor.brandText : KrezusColor.fg3)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(item == period ? KrezusColor.tintStrong : .clear)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(item == period ? [.isButton, .isSelected] : .isButton)
            }
        }
    }

    private func row(rank: Int, player: ArenaPlayer) -> some View {
        HStack(spacing: 11) {
            Text(medal(rank))
                .font(KrezusFont.display(14, .bold))
                .foregroundStyle(rank <= 3 ? KrezusColor.ink : KrezusColor.fg3)
                .frame(width: 26, alignment: .leading)
                .tabularNumbers()

            // La photo plutôt que l'emoji de rang : on reconnaît un ami à
            // son visage, pas à son niveau.
            KrzAvatar(initial: initial(player.username), size: 30,
                      image: arena.avatars[player.id])

            VStack(alignment: .leading, spacing: 1) {
                Text(player.username)
                    .font(KrezusFont.body(13.5, player.isMe ? .bold : .semibold))
                    .foregroundStyle(player.isMe ? KrezusColor.brandText : KrezusColor.ink)
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill").font(.system(size: 9))
                    Text(t("format.days_short", player.streakDays)).font(KrezusFont.caption)
                }
                .foregroundStyle(KrezusColor.fg3)
            }

            Spacer(minLength: 0)

            Text(Money.percent(player.performancePct))
                .font(KrezusFont.body(13.5, .bold))
                .foregroundStyle(player.performancePct >= 0 ? KrezusColor.up : KrezusColor.down)
                .tabularNumbers()
        }
        .padding(.vertical, 10)
        .background(player.isMe ? KrezusColor.tintStrong.opacity(0.5) : .clear)
    }

    /// Initiale affichée à défaut de photo.
    private func initial(_ username: String) -> String {
        String(username.first.map(String.init)?.uppercased() ?? "?")
    }

    private func medal(_ rank: Int) -> String {
        switch rank {
        case 1: return "🥇"
        case 2: return "🥈"
        case 3: return "🥉"
        default: return "\(rank)"
        }
    }

    private var disclaimer: some View {
        Text(t("arena.disclaimer"))
            .font(KrezusFont.caption).foregroundStyle(KrezusColor.fg3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)
    }
}
