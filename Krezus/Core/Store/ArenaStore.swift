import SwiftUI
import Observation

/// Joueur au classement. Ne porte **aucun montant** — pseudo, rang, série et
/// performance en pourcentage, comme la vue `v_arena_leaderboard`. Savoir
/// qu'un ami a « 1 240 € » n'ajoute rien à la comparaison et transforme un
/// jeu en étalage.
struct ArenaPlayer: Identifiable, Sendable {
    let id: UUID
    let username: String
    let rankLevel: Int
    let rankEmoji: String
    let streakDays: Int
    let performancePct: Double
    var isMe: Bool = false
    /// Place au classement, quand elle vient du serveur (qui classe tout le
    /// monde, pas seulement les lignes renvoyées).
    var place: Int? = nil
}

/// Période du classement : la performance se mesure depuis la clôture qui
/// la précède (0020), ou depuis les 1 000 € de départ pour « all ».
enum RankingPeriod: String, CaseIterable, Identifiable, Sendable {
    case day, week, month, ytd, all
    var id: String { rawValue }
    var label: String { t("arena.period.\(rawValue)") }
    var subtitle: String { t("arena.period_subtitle.\(rawValue)") }
}

enum RankingScope: String, CaseIterable, Sendable {
    case global, friends
    var label: String { t("arena.scope.\(rawValue)") }
}

/// Joueur trouvé par la recherche, avec où l'on en est avec lui.
struct PlayerSearchResult: Identifiable, Sendable {
    let id: UUID
    let username: String
    let rankEmoji: String
    var relation: Relation

    enum Relation: String, Sendable { case none, sent, received, friend }
}

/// Demande d'ami reçue, en attente de réponse.
struct FriendRequest: Identifiable, Sendable {
    let id: UUID
    let username: String
    let rankEmoji: String
    let mutualFriends: Int
}

/// Événement du feed. Le `payload` serveur ne contient jamais de montant :
/// « Camille a acheté Nvidia », pas « Camille a mis 300 € sur Nvidia ».
struct FeedEvent: Identifiable, Sendable {
    let id: UUID
    let actor: String
    let kind: Kind
    /// Nom du titre, de la leçon ou du rang selon le type.
    let subject: String
    let minutesAgo: Int

    enum Kind: String, Sendable {
        case buy, sell, lesson, rankUp

        var icon: String {
            switch self {
            case .buy:    return "arrow.down.circle.fill"
            case .sell:   return "arrow.up.circle.fill"
            case .lesson: return "book.fill"
            case .rankUp: return "crown.fill"
            }
        }

        var verb: String {
            switch self {
            case .buy:    return t("feed.verb.buy")
            case .sell:   return t("feed.verb.sell")
            case .lesson: return t("feed.verb.lesson")
            case .rankUp: return t("feed.verb.rank_up")
            }
        }
    }
}

/// Groupe privé, rejoint par code d'invitation.
struct ArenaGroup: Identifiable, Sendable {
    let id: UUID
    let name: String
    let inviteCode: String
    let memberCount: Int
}

/// État social de l'Arena.
///
/// En mode démo, source de vérité en mémoire. La logique reproduit celle de
/// `0007_arena.sql` : amitié symétrique, demandes non rejouables, adhésion par
/// code insensible à la casse.
///
/// En mode serveur, tout passe par `ArenaRepository`. Le classement vient de
/// `v_arena_leaderboard`, qui n'expose aucun montant : on ne peut donc pas
/// afficher la fortune d'un ami, même par erreur.
@MainActor
@Observable
final class ArenaStore {

    enum Source: Equatable { case demo, server }

    private(set) var source: Source = .demo
    private(set) var isLoading = false
    private(set) var lastError: String?

    private(set) var friends: [ArenaPlayer] = []
    private(set) var requests: [FriendRequest] = []
    private(set) var feed: [FeedEvent] = []
    private(set) var groups: [ArenaGroup] = []

    /// Classement affiché, déjà trié et numéroté.
    private(set) var ranking: [ArenaPlayer] = []
    private(set) var isRankingLoading = false

    /// Photos des joueurs affichés, déjà décodées. Un joueur sans photo n'y
    /// figure pas : la vue retombe sur son initiale.
    private(set) var avatars: [UUID: UIImage] = [:]
    /// Comptes déjà interrogés — avec ou sans photo — pour ne pas redemander
    /// à chaque défilement.
    private var avatarsChecked: Set<UUID> = []

    /// Groupe dont le classement est affiché ; `nil` = cercle d'amis.
    var selectedGroup: ArenaGroup?

    // Mode serveur
    private let repository = ArenaRepository()
    /// Sert à télécharger la photo d'un joueur : le dépôt est le même que
    /// celui du profil, seule la politique de lecture a changé (0027).
    private let profiles = ProfileRepository()
    private var userID: UUID?
    /// Appartenance aux groupes du serveur, pour restreindre le classement.
    private var serverGroupMembers: [UUID: Set<UUID>] = [:]
    /// Rangs embarqués, pour traduire un niveau en emoji : le classement
    /// renvoie `rank_level`, pas l'emoji, et rapatrier la table des rangs à
    /// chaque ligne serait absurde pour six valeurs fixes.
    ///
    /// `@ObservationIgnored` est obligatoire : `@Observable` transforme les
    /// propriétés stockées en propriétés calculées, et `lazy` ne s'applique pas
    /// à une propriété calculée. Ce n'est de toute façon pas un état d'interface.
    @ObservationIgnored
    private lazy var rankEmojis: [Int: String] = {
        let ranks: [AcademyRank] = Bundle.main.decodeJSON("ranks.json") ?? []
        return Dictionary(uniqueKeysWithValues: ranks.map { ($0.level, $0.emoji) })
    }()

    init() { seedDemo() }

    // MARK: Source de données

    func connect(userID: UUID) async {
        guard AppConfig.isConfigured else { return }
        self.userID = userID
        source = .server
        await reload()
    }

    func disconnect() {
        userID = nil
        source = .demo
        lastError = nil
        serverGroupMembers = [:]
        selectedGroup = nil
        seedDemo()
    }

    /// Recharge amis, classement, demandes, groupes et feed.
    func reload() async {
        guard source == .server, let userID else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let friendIDs = try await repository.fetchFriendIDs(userID: userID)
            let rows = try await repository.fetchLeaderboard(userIDs: friendIDs)
            friends = rows.map { player(from: $0) }

            requests = try await repository.fetchPendingRequests(userID: userID).map {
                FriendRequest(id: $0.requesterID,
                              username: $0.username,
                              rankEmoji: emoji(for: $0.rankLevel),
                              // Les amis en commun ne sont pas calculés côté
                              // serveur : afficher un nombre inventé serait pire
                              // que de ne rien afficher.
                              mutualFriends: 0)
            }

            let groupRows = try await repository.fetchGroups(userID: userID)
            groups = groupRows.map {
                ArenaGroup(id: $0.id, name: $0.name,
                           inviteCode: $0.inviteCode, memberCount: $0.memberCount)
            }
            for group in groupRows {
                serverGroupMembers[group.id] = try await repository.memberIDs(groupID: group.id)
            }

            feed = try await repository.fetchFeed().map { row in
                FeedEvent(id: row.id,
                          actor: row.actorName,
                          kind: FeedEvent.Kind(rawValue: row.kind) ?? .buy,
                          subject: row.subject,
                          minutesAgo: max(0, Int(Date().timeIntervalSince(row.createdAt) / 60)))
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func player(from row: ArenaRepository.LeaderboardRow) -> ArenaPlayer {
        ArenaPlayer(id: row.userID,
                    username: row.username ?? "—",
                    rankLevel: row.rankLevel,
                    rankEmoji: emoji(for: row.rankLevel),
                    streakDays: row.streakDays,
                    performancePct: row.performancePct ?? 0)
    }

    private func emoji(for level: Int) -> String { rankEmojis[level] ?? "🏛️" }

    // MARK: Photos

    /// Charge les photos manquantes des joueurs donnés.
    ///
    /// Le cache local est indexé sur la date de la photo : une photo changée
    /// depuis un autre appareil porte une autre date, donc se retélécharge.
    /// Les téléchargements partent ensemble, mais par groupes de six : une
    /// liste de cent joueurs ne doit pas ouvrir cent connexions.
    func loadAvatars(for ids: [UUID]) async {
        guard source == .server else { return }
        let wanted = ids.filter { !avatarsChecked.contains($0) }
        guard !wanted.isEmpty else { return }
        avatarsChecked.formUnion(wanted)

        guard let versions = try? await repository.fetchAvatarVersions(ids: wanted) else {
            // Rien d'appris : on pourra redemander.
            avatarsChecked.subtract(wanted)
            return
        }

        for group in stride(from: 0, to: versions.count, by: 6) {
            let slice = Array(versions)[group..<min(group + 6, versions.count)]
            await withTaskGroup(of: (UUID, UIImage?).self) { tasks in
                for (id, version) in slice {
                    tasks.addTask { [profiles] in
                        if let cached = AvatarCache.load(userID: id, version: version) {
                            return (id, cached)
                        }
                        guard let data = try? await profiles.downloadAvatar(userID: id),
                              let image = UIImage(data: data) else { return (id, nil) }
                        AvatarCache.store(data, userID: id, version: version)
                        return (id, image)
                    }
                }
                for await (id, image) in tasks {
                    if let image { avatars[id] = image }
                }
            }
        }
    }

    // MARK: Classement

    /// Classement trié par performance décroissante, l'utilisateur inclus.
    ///
    /// La performance de l'utilisateur vient du `TradingStore` : elle se mesure
    /// contre les 1 000 € de départ, jamais contre le solde courant — sinon
    /// vendre toutes ses positions afficherait un score figé et avantageux.
    func leaderboard(myPerformance: Double, myStreak: Int, myRank: Int, myEmoji: String) -> [ArenaPlayer] {
        let me = ArenaPlayer(
            id: Self.meID, username: t("arena.me"), rankLevel: myRank, rankEmoji: myEmoji,
            streakDays: myStreak, performancePct: myPerformance, isMe: true)

        var pool = friends
        if let group = selectedGroup {
            // Un groupe restreint le classement à ses membres.
            let members = source == .server
                ? serverGroupMembers[group.id]
                : Self.groupMembers[group.id]
            pool = friends.filter { members?.contains($0.id) ?? false }
        }

        return (pool + [me]).sorted { $0.performancePct > $1.performancePct }
    }

    // MARK: Classement par période

    /// Charge le classement. En mode serveur, `arena_leaderboard` mesure
    /// chaque joueur contre sa propre valeur au début de la période ; en démo,
    /// les amis inventés et une poignée de joueurs fictifs, pour voir l'écran.
    func loadRanking(period: RankingPeriod, scope: RankingScope,
                     myPerformance: Double, myStreak: Int, myRank: Int, myEmoji: String) async {
        let groupMembers: Set<UUID>? = selectedGroup.flatMap {
            source == .server ? serverGroupMembers[$0.id] : Self.groupMembers[$0.id]
        }

        guard source == .server else {
            let me = ArenaPlayer(id: Self.meID, username: t("arena.me"), rankLevel: myRank,
                                 rankEmoji: myEmoji, streakDays: myStreak,
                                 performancePct: myPerformance * period.demoScale, isMe: true)
            var pool = friends.map { friend in
                ArenaPlayer(id: friend.id, username: friend.username, rankLevel: friend.rankLevel,
                            rankEmoji: friend.rankEmoji, streakDays: friend.streakDays,
                            performancePct: (friend.performancePct * period.demoScale).rounded(toPlaces: 2))
            }
            if let groupMembers { pool = pool.filter { groupMembers.contains($0.id) } }
            if scope == .global && groupMembers == nil { pool += Self.demoStrangers(period) }
            ranking = (pool + [me]).sorted { $0.performancePct > $1.performancePct }
                .enumerated().map { index, player in
                    var ranked = player
                    ranked.place = index + 1
                    return ranked
                }
            return
        }

        isRankingLoading = true
        defer { isRankingLoading = false }
        do {
            let effectiveScope = groupMembers == nil ? scope : .friends
            let rows = try await repository.fetchRanking(period: period.rawValue, scope: effectiveScope.rawValue)
            var players = rows.map { row in
                ArenaPlayer(id: row.userID,
                            username: row.isMe ? t("arena.me") : (row.username ?? "—"),
                            rankLevel: row.rankLevel,
                            rankEmoji: emoji(for: row.rankLevel),
                            streakDays: row.streakDays,
                            performancePct: row.performancePct,
                            isMe: row.isMe,
                            place: row.place)
            }
            // Un groupe restreint le classement à ses membres ; les places
            // sont alors recomptées dans le groupe.
            if let groupMembers {
                players = players.filter { $0.isMe || groupMembers.contains($0.id) }
                    .enumerated().map { index, player in
                        var ranked = player
                        ranked.place = index + 1
                        return ranked
                    }
            }
            ranking = players
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Joueurs fictifs du classement général en démo.
    private static func demoStrangers(_ period: RankingPeriod) -> [ArenaPlayer] {
        let base: [(String, Int, String, Int, Double)] = [
            ("maxime_trader", 5, "👑", 44, 23.4), ("jade.b", 4, "📜", 18, 15.1),
            ("theo_invest", 3, "⚔️", 9, 11.8), ("ines", 3, "⚔️", 30, 6.6),
            ("lucas92", 2, "🛡️", 4, 3.2), ("emma_l", 2, "🛡️", 6, 0.9),
            ("adam", 1, "🏛️", 2, -2.4), ("zoe_bourse", 1, "🏛️", 1, -7.9),
        ]
        return base.map { name, level, emoji, streak, pct in
            ArenaPlayer(id: UUID(), username: name, rankLevel: level, rankEmoji: emoji,
                        streakDays: streak, performancePct: (pct * period.demoScale).rounded(toPlaces: 2))
        }
    }

    // MARK: Recherche

    /// Joueurs dont le pseudo contient `query` (deux caractères au moins).
    func searchPlayers(_ query: String) async throws -> [PlayerSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { return [] }
        guard source == .server else {
            let known = friends.map { ($0.username, $0.rankEmoji, PlayerSearchResult.Relation.friend) }
                + requests.map { ($0.username, $0.rankEmoji, PlayerSearchResult.Relation.received) }
                + Self.demoStrangers(.all).map { ($0.username, $0.rankEmoji, PlayerSearchResult.Relation.none) }
            return known
                .filter { $0.0.localizedCaseInsensitiveContains(trimmed) }
                .map { PlayerSearchResult(id: UUID(), username: $0.0, rankEmoji: $0.1, relation: $0.2) }
        }
        return try await repository.searchUsers(trimmed).map {
            PlayerSearchResult(id: $0.userID, username: $0.username,
                               rankEmoji: emoji(for: $0.rankLevel),
                               relation: PlayerSearchResult.Relation(rawValue: $0.relation) ?? .none)
        }
    }

    /// Envoie une demande depuis la recherche. En démo, rien ne part.
    func sendRequest(to player: PlayerSearchResult) async throws {
        guard source == .server, let userID else { return }
        try await repository.sendFriendRequest(from: userID, to: player.id)
    }

    /// Annule une demande envoyée : la même suppression qu'une amitié.
    func cancelRequest(to player: PlayerSearchResult) async throws {
        guard source == .server, let userID else { return }
        try await repository.removeFriend(userID: userID, otherID: player.id)
    }

    /// Accepte depuis la recherche une demande reçue.
    func acceptRequest(from player: PlayerSearchResult) {
        accept(FriendRequest(id: player.id, username: player.username,
                             rankEmoji: player.rankEmoji, mutualFriends: 0))
    }

    // MARK: Demandes d'ami

    enum ArenaError: LocalizedError {
        case alreadyFriends, unknownCode, alreadyMember, emptyName
        /// Action qui n'a pas de sens hors compte : en démo, il n'y a personne
        /// en face. Le dire vaut mieux que d'échouer en silence.
        case demoUnavailable
        var errorDescription: String? {
            switch self {
            case .alreadyFriends:  return t("arena.error.already_friends")
            case .unknownCode:     return t("arena.error.unknown_code")
            case .alreadyMember:   return t("arena.error.already_member")
            case .emptyName:       return t("arena.error.empty_name")
            case .demoUnavailable: return t("arena.error.demo_unavailable")
            }
        }
    }

    /// Envoie une demande d'ami par pseudo. Uniquement en mode serveur : en
    /// démo il n'y a personne à qui l'envoyer.
    func sendRequest(to username: String) async throws {
        guard source == .server, let userID else { throw ArenaError.demoUnavailable }
        let otherID = try await repository.findUser(username: username)
        try await repository.sendFriendRequest(from: userID, to: otherID)
    }

    /// Accepte une demande : elle disparaît de la liste et l'ami rejoint le
    /// classement. Idempotent — une demande déjà traitée ne fait rien.
    func accept(_ request: FriendRequest) {
        guard let index = requests.firstIndex(where: { $0.id == request.id }) else { return }
        requests.remove(at: index)

        switch source {
        case .demo:
            friends.append(ArenaPlayer(
                id: request.id, username: request.username, rankLevel: 2,
                rankEmoji: request.rankEmoji, streakDays: 1,
                performancePct: Double.random(in: -4...6).rounded(toPlaces: 2)))
        case .server:
            guard let userID else { return }
            // La demande disparaît tout de suite — c'est un geste, il doit
            // répondre — et le classement se remplit au rechargement, une fois
            // que le serveur a la performance réelle du nouvel ami.
            Task {
                do {
                    try await repository.acceptFriendRequest(userID: userID,
                                                             requesterID: request.id)
                    await reload()
                } catch {
                    lastError = error.localizedDescription
                    await reload()
                }
            }
        }
    }

    func decline(_ request: FriendRequest) {
        requests.removeAll { $0.id == request.id }
        guard source == .server, let userID else { return }
        Task {
            do {
                try await repository.declineFriendRequest(userID: userID,
                                                          requesterID: request.id)
            } catch {
                lastError = error.localizedDescription
                await reload()
            }
        }
    }

    /// Retire un ami. La suppression est symétrique côté serveur : le lien
    /// disparaît quel que soit celui qui l'avait initié.
    func removeFriend(_ player: ArenaPlayer) {
        friends.removeAll { $0.id == player.id }
        for key in Self.groupMembers.keys {
            Self.groupMembers[key]?.remove(player.id)
        }
        for key in serverGroupMembers.keys {
            serverGroupMembers[key]?.remove(player.id)
        }

        guard source == .server, let userID else { return }
        Task {
            do {
                try await repository.removeFriend(userID: userID, otherID: player.id)
            } catch {
                lastError = error.localizedDescription
                await reload()
            }
        }
    }

    // MARK: Groupes

    @discardableResult
    func createGroup(named name: String) async throws -> ArenaGroup {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { throw ArenaError.emptyName }

        switch source {
        case .demo:
            let group = ArenaGroup(id: UUID(), name: trimmed,
                                   inviteCode: Self.makeInviteCode(), memberCount: 1)
            groups.append(group)
            Self.groupMembers[group.id] = []
            return group
        case .server:
            guard let userID else { throw ArenaError.demoUnavailable }
            let row = try await repository.createGroup(userID: userID, name: trimmed)
            let group = ArenaGroup(id: row.id, name: row.name,
                                   inviteCode: row.inviteCode, memberCount: row.memberCount)
            groups.append(group)
            serverGroupMembers[group.id] = [userID]
            return group
        }
    }

    /// Rejoint un groupe par code. La comparaison ignore la casse : le code se
    /// transmet à l'oral, personne ne retient s'il était en majuscules.
    @discardableResult
    func joinGroup(code: String) async throws -> ArenaGroup {
        let normalized = code.trimmingCharacters(in: .whitespaces).uppercased()

        switch source {
        case .demo:
            guard let group = Self.joinableGroups.first(where: { $0.inviteCode == normalized })
            else { throw ArenaError.unknownCode }
            guard !groups.contains(where: { $0.id == group.id }) else {
                throw ArenaError.alreadyMember
            }
            groups.append(group)
            Self.groupMembers[group.id] = Set(friends.prefix(2).map(\.id))
            return group
        case .server:
            guard let userID else { throw ArenaError.demoUnavailable }
            let row = try await repository.joinGroup(userID: userID, code: normalized)
            let group = ArenaGroup(id: row.id, name: row.name,
                                   inviteCode: row.inviteCode, memberCount: row.memberCount)
            groups.append(group)
            serverGroupMembers[group.id] = try await repository.memberIDs(groupID: group.id)
            return group
        }
    }

    func leaveGroup(_ group: ArenaGroup) {
        groups.removeAll { $0.id == group.id }
        serverGroupMembers[group.id] = nil
        if selectedGroup?.id == group.id { selectedGroup = nil }

        guard source == .server, let userID else { return }
        Task {
            do {
                try await repository.leaveGroup(userID: userID, groupID: group.id)
            } catch {
                lastError = error.localizedDescription
                await reload()
            }
        }
    }

    // MARK: Démo

    private static let meID = UUID()
    /// Appartenance aux groupes, indexée par groupe. Statique pour survivre aux
    /// recréations de vue pendant la démo.
    private static var groupMembers: [UUID: Set<UUID>] = [:]

    /// Groupes rejoignables en démo, pour que le champ « code » ait un effet.
    private static let joinableGroups: [ArenaGroup] = [
        .init(id: UUID(), name: "Promo 2026", inviteCode: "KRZ26A", memberCount: 12),
        .init(id: UUID(), name: "Club Bourse Lyon", inviteCode: "LYON42", memberCount: 7),
    ]

    private static func makeInviteCode() -> String {
        // Alphabet sans caractères ambigus (0/O, 1/I), comme côté serveur.
        let alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        return String((0..<6).map { _ in alphabet.randomElement()! })
    }

    private func seedDemo() {
        friends = [
            .init(id: UUID(), username: "camille", rankLevel: 3, rankEmoji: "⚔️",
                  streakDays: 12, performancePct: 8.42),
            .init(id: UUID(), username: "hugo", rankLevel: 2, rankEmoji: "🛡️",
                  streakDays: 3, performancePct: 2.15),
            .init(id: UUID(), username: "lina", rankLevel: 4, rankEmoji: "📜",
                  streakDays: 21, performancePct: -1.87),
            .init(id: UUID(), username: "noah", rankLevel: 1, rankEmoji: "🏛️",
                  streakDays: 1, performancePct: -5.30),
        ]

        requests = [
            .init(id: UUID(), username: "sofia", rankEmoji: "🛡️", mutualFriends: 2),
            .init(id: UUID(), username: "yanis", rankEmoji: "🏛️", mutualFriends: 1),
        ]

        feed = [
            .init(id: UUID(), actor: "camille", kind: .buy, subject: "Nvidia", minutesAgo: 4),
            .init(id: UUID(), actor: "lina", kind: .rankUp, subject: t("demo_feed.rank"), minutesAgo: 26),
            .init(id: UUID(), actor: "hugo", kind: .lesson, subject: t("demo_feed.lesson"), minutesAgo: 51),
            .init(id: UUID(), actor: "camille", kind: .sell, subject: "TotalEnergies", minutesAgo: 96),
            .init(id: UUID(), actor: "noah", kind: .buy, subject: "Air Liquide", minutesAgo: 180),
        ]
    }
}

private extension RankingPeriod {
    /// En démo, une performance sur une période courte est plus petite.
    var demoScale: Double {
        switch self {
        case .day:   return 0.08
        case .week:  return 0.25
        case .month: return 0.6
        case .ytd:   return 0.9
        case .all:   return 1
        }
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let factor = pow(10.0, Double(places))
        return (self * factor).rounded() / factor
    }
}
