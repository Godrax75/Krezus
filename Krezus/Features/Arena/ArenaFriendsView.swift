import SwiftUI

/// Amis et demandes reçues. Les demandes passent en premier : une demande en
/// attente est une action à faire, la liste d'amis est de la consultation.
struct ArenaFriendsView: View {
    @Environment(ArenaStore.self) private var arena
    @Environment(Router.self) private var router

    @State private var query = ""
    @State private var results: [PlayerSearchResult] = []
    @State private var isSearching = false
    @State private var searchError: String?
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            searchCard
            if !arena.requests.isEmpty { requestsCard }
            friendsCard
        }
        // Les photos des amis et des demandes reçues, à l'ouverture.
        .task(id: arena.friends.count + arena.requests.count) {
            await arena.loadAvatars(for: arena.friends.map(\.id) + arena.requests.map(\.id))
        }
        // Celles des résultats de recherche, quand ils arrivent.
        .task(id: results.map(\.id)) {
            await arena.loadAvatars(for: results.map(\.id))
        }
        // Recherche après une courte pause de frappe : pas un appel par lettre.
        .task(id: query) {
            let trimmed = query.trimmingCharacters(in: .whitespaces)
            guard trimmed.count >= 2 else {
                results = []
                searchError = nil
                return
            }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            isSearching = true
            defer { isSearching = false }
            do {
                results = try await arena.searchPlayers(trimmed)
                searchError = nil
            } catch {
                searchError = error.localizedDescription
            }
        }
    }

    // MARK: Recherche

    private var searchCard: some View {
        KrzCard(padding: KrezusSpacing.s4) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(KrezusColor.fg3)
                    TextField(t("arena.search.placeholder"), text: $query)
                        .font(KrezusFont.bodyMd)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .focused($searchFocused)
                    if isSearching {
                        ProgressView().controlSize(.small)
                    } else if !query.isEmpty {
                        Button { query = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(KrezusColor.fg4)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(t("arena.search.clear"))
                    }
                }
                .padding(12)
                .background(KrezusColor.tint)
                .clipShape(RoundedRectangle(cornerRadius: KrezusRadius.md, style: .continuous))

                if let searchError {
                    Text(searchError).font(KrezusFont.caption).foregroundStyle(KrezusColor.down)
                        .padding(.top, 8)
                } else if query.trimmingCharacters(in: .whitespaces).count >= 2 && !isSearching && results.isEmpty {
                    Text(t("arena.search.no_result"))
                        .font(KrezusFont.bodySm).foregroundStyle(KrezusColor.fg3)
                        .padding(.top, 10)
                }

                ForEach(Array(results.enumerated()), id: \.element.id) { index, player in
                    if index > 0 { Divider().overlay(KrezusColor.divider) }
                    searchRow(player, index: index)
                }
                .padding(.top, results.isEmpty ? 0 : 4)
            }
        }
    }

    /// Initiale affichée à défaut de photo.
    private func initial(_ username: String) -> String {
        String(username.first.map(String.init)?.uppercased() ?? "?")
    }

    private func searchRow(_ player: PlayerSearchResult, index: Int) -> some View {
        HStack(spacing: 11) {
            KrzAvatar(initial: initial(player.username), size: 32,
                      image: arena.avatars[player.id])
            Text(player.username)
                .font(KrezusFont.body(13.5, .semibold)).foregroundStyle(KrezusColor.ink)
            Spacer(minLength: 0)
            relationButton(player, index: index)
        }
        .padding(.vertical, 9)
    }

    @ViewBuilder
    private func relationButton(_ player: PlayerSearchResult, index: Int) -> some View {
        switch player.relation {
        case .friend:
            Label(t("arena.search.friend"), systemImage: "checkmark")
                .font(KrezusFont.body(12, .semibold)).foregroundStyle(KrezusColor.up)
        case .sent:
            pill(t("arena.search.sent"), filled: false) {
                Task {
                    do {
                        try await arena.cancelRequest(to: player)
                        setRelation(.none, at: index)
                    } catch { searchError = error.localizedDescription }
                }
            }
        case .received:
            pill(t("arena.search.accept"), filled: true) {
                arena.acceptRequest(from: player)
                setRelation(.friend, at: index)
                router.showToast(t("arena.toast.request_accepted", player.username))
            }
        case .none:
            pill(t("arena.search.add"), filled: true) {
                Task {
                    do {
                        try await arena.sendRequest(to: player)
                        setRelation(.sent, at: index)
                        router.showToast(t("arena.toast.request_sent", player.username))
                    } catch { searchError = error.localizedDescription }
                }
            }
        }
    }

    private func pill(_ title: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(KrezusFont.body(12, .semibold))
                .foregroundStyle(filled ? .white : KrezusColor.fg3)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(filled ? KrezusColor.brandFill : KrezusColor.tint)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func setRelation(_ relation: PlayerSearchResult.Relation, at index: Int) {
        guard results.indices.contains(index) else { return }
        results[index].relation = relation
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
            KrzAvatar(initial: initial(request.username), size: 32,
                      image: arena.avatars[request.id])

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
            KrzAvatar(initial: initial(friend.username), size: 32,
                      image: arena.avatars[friend.id])

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
