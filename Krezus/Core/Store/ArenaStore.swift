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
@MainActor
@Observable
final class ArenaStore {

    private(set) var friends: [ArenaPlayer] = []
    private(set) var requests: [FriendRequest] = []
    private(set) var feed: [FeedEvent] = []
    private(set) var groups: [ArenaGroup] = []

    /// Groupe dont le classement est affiché ; `nil` = cercle d'amis.
    var selectedGroup: ArenaGroup?

    init() { seedDemo() }

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
            pool = friends.filter { Self.groupMembers[group.id]?.contains($0.id) ?? false }
        }

        return (pool + [me]).sorted { $0.performancePct > $1.performancePct }
    }

    // MARK: Demandes d'ami

    enum ArenaError: LocalizedError {
        case alreadyFriends, unknownCode, alreadyMember, emptyName
        var errorDescription: String? {
            switch self {
            case .alreadyFriends: return t("arena.error.already_friends")
            case .unknownCode:    return t("arena.error.unknown_code")
            case .alreadyMember:  return t("arena.error.already_member")
            case .emptyName:      return t("arena.error.empty_name")
            }
        }
    }

    /// Accepte une demande : elle disparaît de la liste et l'ami rejoint le
    /// classement. Idempotent — une demande déjà traitée ne fait rien.
    func accept(_ request: FriendRequest) {
        guard let index = requests.firstIndex(where: { $0.id == request.id }) else { return }
        requests.remove(at: index)

        friends.append(ArenaPlayer(
            id: request.id, username: request.username, rankLevel: 2,
            rankEmoji: request.rankEmoji, streakDays: 1,
            performancePct: Double.random(in: -4...6).rounded(toPlaces: 2)))
    }

    func decline(_ request: FriendRequest) {
        requests.removeAll { $0.id == request.id }
    }

    /// Retire un ami. La suppression est symétrique côté serveur : le lien
    /// disparaît quel que soit celui qui l'avait initié.
    func removeFriend(_ player: ArenaPlayer) {
        friends.removeAll { $0.id == player.id }
        for key in Self.groupMembers.keys {
            Self.groupMembers[key]?.remove(player.id)
        }
    }

    // MARK: Groupes

    @discardableResult
    func createGroup(named name: String) throws -> ArenaGroup {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { throw ArenaError.emptyName }

        let group = ArenaGroup(id: UUID(), name: trimmed,
                               inviteCode: Self.makeInviteCode(), memberCount: 1)
        groups.append(group)
        Self.groupMembers[group.id] = []
        return group
    }

    /// Rejoint un groupe par code. La comparaison ignore la casse : le code se
    /// transmet à l'oral, personne ne retient s'il était en majuscules.
    @discardableResult
    func joinGroup(code: String) throws -> ArenaGroup {
        let normalized = code.trimmingCharacters(in: .whitespaces).uppercased()
        guard let group = Self.joinableGroups.first(where: { $0.inviteCode == normalized }) else {
            throw ArenaError.unknownCode
        }
        guard !groups.contains(where: { $0.id == group.id }) else {
            throw ArenaError.alreadyMember
        }
        groups.append(group)
        Self.groupMembers[group.id] = Set(friends.prefix(2).map(\.id))
        return group
    }

    func leaveGroup(_ group: ArenaGroup) {
        groups.removeAll { $0.id == group.id }
        if selectedGroup?.id == group.id { selectedGroup = nil }
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

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let factor = pow(10.0, Double(places))
        return (self * factor).rounded() / factor
    }
}
