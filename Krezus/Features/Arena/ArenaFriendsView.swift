import SwiftUI

/// Amis et demandes reçues. Les demandes passent en premier : une demande en
/// attente est une action à faire, la liste d'amis est de la consultation.
struct ArenaFriendsView: View {
    @Environment(ArenaStore.self) private var arena
    @Environment(Router.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !arena.requests.isEmpty { requestsCard }
            friendsCard
        }
    }

    private var requestsCard: some View {
        KrzCard(padding: KrezusSpacing.s4) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(t("arena.requests.title")).font(KrezusFont.cardTitle)
                        .foregroundStyle(KrezusColor.ink)
                    Spacer()
                    Text("\(arena.requests.count)")
                        .font(KrezusFont.body(11.5, .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(KrezusColor.amberText).clipShape(Capsule())
                }
                .padding(.bottom, 6)

                ForEach(Array(arena.requests.enumerated()), id: \.element.id) { index, request in
                    if index > 0 { Divider().overlay(KrezusColor.divider) }
                    requestRow(request)
                }
            }
        }
    }

    private func requestRow(_ request: FriendRequest) -> some View {
        HStack(spacing: 11) {
            Text(request.rankEmoji).font(.system(size: 22))

            VStack(alignment: .leading, spacing: 1) {
                Text(request.username)
                    .font(KrezusFont.body(13.5, .semibold)).foregroundStyle(KrezusColor.ink)
                Text(request.mutualFriends > 0
                     ? t(L10n.plural(Double(request.mutualFriends),
                                     one: "arena.mutual_friends.one",
                                     other: "arena.mutual_friends.other"), request.mutualFriends)
                     : t("arena.mutual_friends.none"))
                    .font(KrezusFont.caption).foregroundStyle(KrezusColor.fg3)
            }

            Spacer(minLength: 0)

            Button {
                arena.decline(request)
                router.showToast(t("arena.toast.request_declined"))
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(KrezusColor.fg3)
                    .frame(width: 32, height: 32)
                    .background(KrezusColor.tint).clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(t("arena.decline_request"))

            Button {
                arena.accept(request)
                router.showToast(t("arena.toast.request_accepted", request.username))
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(KrezusColor.brandFill).clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(t("arena.accept_request"))
        }
        .padding(.vertical, 9)
    }

    private var friendsCard: some View {
        KrzCard(padding: KrezusSpacing.s4) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(t("arena.friends.title")).font(KrezusFont.cardTitle).foregroundStyle(KrezusColor.ink)
                    Spacer()
                    Text("\(arena.friends.count)")
                        .font(KrezusFont.body(11.5)).foregroundStyle(KrezusColor.fg3)
                }
                .padding(.bottom, 6)

                if arena.friends.isEmpty {
                    Text(t("arena.friends.empty"))
                        .font(KrezusFont.bodyMd).foregroundStyle(KrezusColor.fg3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 8)
                } else {
                    ForEach(Array(arena.friends.enumerated()), id: \.element.id) { index, friend in
                        if index > 0 { Divider().overlay(KrezusColor.divider) }
                        friendRow(friend)
                    }
                }
            }
        }
    }

    private func friendRow(_ friend: ArenaPlayer) -> some View {
        HStack(spacing: 11) {
            Text(friend.rankEmoji).font(.system(size: 22))

            VStack(alignment: .leading, spacing: 1) {
                Text(friend.username)
                    .font(KrezusFont.body(13.5, .semibold)).foregroundStyle(KrezusColor.ink)
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill").font(.system(size: 9))
                    Text(t(L10n.plural(Double(friend.streakDays),
                                       one: "arena.streak.one", other: "arena.streak.other"),
                           friend.streakDays))
                        .font(KrezusFont.caption)
                }
                .foregroundStyle(KrezusColor.fg3)
            }

            Spacer(minLength: 0)

            Text(Money.percent(friend.performancePct))
                .font(KrezusFont.body(13, .bold))
                .foregroundStyle(friend.performancePct >= 0 ? KrezusColor.up : KrezusColor.down)
                .tabularNumbers()

            Menu {
                Button(t("arena.remove_friend"), role: .destructive) {
                    arena.removeFriend(friend)
                    router.showToast(t("arena.toast.friend_removed", friend.username))
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(KrezusColor.fg4)
                    .frame(width: 28, height: 28)
            }
        }
        .padding(.vertical, 9)
    }
}
