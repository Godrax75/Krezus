import Foundation
import Supabase
import PostgREST

/// Social de l'Arena : amis, demandes, classement, feed, groupes (0007_arena.sql).
///
/// Le classement passe par `v_arena_leaderboard`, qui n'expose **jamais** de
/// montant — pseudo, rang, série, XP et performance en pourcent. C'est une vue
/// lue par des tiers : toute colonne en centimes qu'on y ajouterait ferait
/// fuiter le portefeuille d'autrui.
@MainActor
struct ArenaRepository {

    /// Ligne de `v_arena_leaderboard`.
    struct LeaderboardRow: Decodable, Sendable {
        let userID: UUID
        let username: String?
        let rankLevel: Int
        let streakDays: Int
        let performancePct: Double?

        enum CodingKeys: String, CodingKey {
            case userID = "user_id"
            case username
            case rankLevel = "rank_level"
            case streakDays = "streak_days"
            case performancePct = "performance_pct"
        }
    }

    /// Demande d'ami reçue, en attente.
    struct PendingRequest: Sendable {
        let requesterID: UUID
        let username: String
        let rankLevel: Int
    }

    struct GroupRow: Sendable {
        let id: UUID
        let name: String
        let inviteCode: String
        let memberCount: Int
    }

    struct FeedRow: Sendable {
        let id: UUID
        let actorID: UUID
        let actorName: String
        let kind: String
        let subject: String
        let createdAt: Date
    }

    // MARK: Amis et classement

    /// Identifiants des amis acceptés. Le lien est stocké orienté
    /// (demandeur → destinataire) mais une amitié acceptée est symétrique :
    /// il faut donc regarder les deux colonnes.
    func fetchFriendIDs(userID: UUID) async throws -> [UUID] {
        struct Row: Decodable {
            let userID: UUID
            let friendID: UUID
            enum CodingKeys: String, CodingKey {
                case userID = "user_id"
                case friendID = "friend_id"
            }
        }
        let client = try SupabaseService.shared.requireClient()
        do {
            let rows: [Row] = try await client
                .from("friendships")
                .select("user_id, friend_id")
                .eq("status", value: "accepted")
                .or("user_id.eq.\(userID.uuidString),friend_id.eq.\(userID.uuidString)")
                .execute()
                .value
            return rows.map { $0.userID == userID ? $0.friendID : $0.userID }
        } catch { throw mapPostgrestError(error) }
    }

    /// Classement des identifiants donnés. Appelé avec la liste d'amis (plus
    /// soi-même) : la vue ne filtre pas, c'est à l'appelant de borner.
    func fetchLeaderboard(userIDs: [UUID]) async throws -> [LeaderboardRow] {
        guard !userIDs.isEmpty else { return [] }
        let client = try SupabaseService.shared.requireClient()
        do {
            return try await client
                .from("v_arena_leaderboard")
                .select()
                .in("user_id", values: userIDs.map(\.uuidString))
                .execute()
                .value
        } catch { throw mapPostgrestError(error) }
    }

    func fetchPendingRequests(userID: UUID) async throws -> [PendingRequest] {
        struct Row: Decodable {
            let userID: UUID
            enum CodingKeys: String, CodingKey { case userID = "user_id" }
        }
        let client = try SupabaseService.shared.requireClient()
        do {
            let rows: [Row] = try await client
                .from("friendships")
                .select("user_id")
                .eq("friend_id", value: userID)
                .eq("status", value: "pending")
                .execute()
                .value
            let profiles = try await fetchProfiles(ids: rows.map(\.userID))
            return rows.map {
                let profile = profiles[$0.userID]
                return PendingRequest(requesterID: $0.userID,
                                      username: profile?.username ?? "—",
                                      rankLevel: profile?.rankLevel ?? 1)
            }
        } catch { throw mapPostgrestError(error) }
    }

    /// Pseudos et rangs, indexés par identifiant.
    ///
    /// En deux temps et non par imbrication PostgREST : `friendships.user_id`
    /// et `arena_feed.actor_id` référencent `auth.users`, pas `public.profiles`.
    /// Il n'existe donc aucune clé étrangère entre ces tables et `profiles`, et
    /// PostgREST ne sait embarquer que le long d'une relation déclarée.
    func fetchProfiles(ids: [UUID]) async throws -> [UUID: (username: String?, rankLevel: Int)] {
        guard !ids.isEmpty else { return [:] }
        struct Row: Decodable {
            let id: UUID
            let username: String?
            let rankLevel: Int
            enum CodingKeys: String, CodingKey {
                case id, username
                case rankLevel = "rank_level"
            }
        }
        let client = try SupabaseService.shared.requireClient()
        do {
            let rows: [Row] = try await client
                .from("profiles")
                .select("id, username, rank_level")
                .in("id", values: Array(Set(ids)).map(\.uuidString))
                .execute()
                .value
            return Dictionary(uniqueKeysWithValues: rows.map {
                ($0.id, (username: $0.username, rankLevel: $0.rankLevel))
            })
        } catch { throw mapPostgrestError(error) }
    }

    /// Résout un pseudo en identifiant. `profiles` est lisible par tous les
    /// authentifiés (policy « profiles readable »), précisément pour permettre
    /// d'ajouter quelqu'un par son pseudo.
    func findUser(username: String) async throws -> UUID {
        struct Row: Decodable { let id: UUID }
        let client = try SupabaseService.shared.requireClient()
        do {
            let rows: [Row] = try await client
                .from("profiles")
                .select("id")
                .ilike("username", pattern: username.trimmingCharacters(in: .whitespaces))
                .limit(1)
                .execute()
                .value
            guard let row = rows.first else { throw KrezusError.userNotFound }
            return row.id
        } catch { throw mapPostgrestError(error) }
    }

    func sendFriendRequest(from userID: UUID, to otherID: UUID) async throws {
        try await call("send_friend_request", params: [
            "p_from": .string(userID.uuidString),
            "p_to": .string(otherID.uuidString),
        ])
    }

    func acceptFriendRequest(userID: UUID, requesterID: UUID) async throws {
        try await call("accept_friend_request", params: [
            "p_user": .string(userID.uuidString),
            "p_requester": .string(requesterID.uuidString),
        ])
    }

    /// Refuser, c'est supprimer le lien en attente. Aucune RPC dédiée côté
    /// serveur : la policy « friendship update party » autorise le destinataire
    /// à agir sur la ligne, et un refus ne doit rien laisser derrière lui.
    func declineFriendRequest(userID: UUID, requesterID: UUID) async throws {
        let client = try SupabaseService.shared.requireClient()
        do {
            try await client
                .from("friendships")
                .delete()
                .eq("user_id", value: requesterID)
                .eq("friend_id", value: userID)
                .eq("status", value: "pending")
                .execute()
        } catch { throw mapPostgrestError(error) }
    }

    func removeFriend(userID: UUID, otherID: UUID) async throws {
        try await call("remove_friend", params: [
            "p_user": .string(userID.uuidString),
            "p_other": .string(otherID.uuidString),
        ])
    }

    // MARK: Groupes

    func fetchGroups(userID: UUID) async throws -> [GroupRow] {
        struct Row: Decodable {
            let groups: Nested
            struct Nested: Decodable {
                let id: UUID
                let name: String
                let inviteCode: String
                enum CodingKeys: String, CodingKey {
                    case id, name
                    case inviteCode = "invite_code"
                }
            }
            enum CodingKeys: String, CodingKey { case groups = "arena_groups" }
        }
        let client = try SupabaseService.shared.requireClient()
        do {
            let rows: [Row] = try await client
                .from("arena_group_members")
                .select("arena_groups(id, name, invite_code)")
                .eq("user_id", value: userID)
                .execute()
                .value
            // Le nombre de membres se compte à part : l'imbriquer dans la même
            // requête obligerait à rapatrier la liste complète des membres.
            var out: [GroupRow] = []
            for row in rows {
                let count = try await memberCount(groupID: row.groups.id)
                out.append(GroupRow(id: row.groups.id, name: row.groups.name,
                                    inviteCode: row.groups.inviteCode, memberCount: count))
            }
            return out
        } catch { throw mapPostgrestError(error) }
    }

    func memberCount(groupID: UUID) async throws -> Int {
        let client = try SupabaseService.shared.requireClient()
        let response = try await client
            .from("arena_group_members")
            .select("user_id", head: true, count: .exact)
            .eq("group_id", value: groupID)
            .execute()
        return response.count ?? 0
    }

    func memberIDs(groupID: UUID) async throws -> Set<UUID> {
        struct Row: Decodable {
            let userID: UUID
            enum CodingKeys: String, CodingKey { case userID = "user_id" }
        }
        let client = try SupabaseService.shared.requireClient()
        do {
            let rows: [Row] = try await client
                .from("arena_group_members")
                .select("user_id")
                .eq("group_id", value: groupID)
                .execute()
                .value
            return Set(rows.map(\.userID))
        } catch { throw mapPostgrestError(error) }
    }

    func createGroup(userID: UUID, name: String) async throws -> GroupRow {
        struct Row: Decodable {
            let id: UUID
            let inviteCode: String
            enum CodingKeys: String, CodingKey {
                case id
                case inviteCode = "invite_code"
            }
        }
        let client = try SupabaseService.shared.requireClient()
        do {
            let row: Row = try await client.rpc("create_arena_group", params: [
                "p_owner": AnyJSON.string(userID.uuidString),
                "p_name": .string(name),
            ]).single().execute().value
            return GroupRow(id: row.id, name: name.trimmingCharacters(in: .whitespaces),
                            inviteCode: row.inviteCode, memberCount: 1)
        } catch { throw mapPostgrestError(error) }
    }

    func joinGroup(userID: UUID, code: String) async throws -> GroupRow {
        let client = try SupabaseService.shared.requireClient()
        do {
            let groupID: UUID = try await client.rpc("join_arena_group", params: [
                "p_user": AnyJSON.string(userID.uuidString),
                "p_code": .string(code),
            ]).execute().value

            struct Row: Decodable {
                let id: UUID
                let name: String
                let inviteCode: String
                enum CodingKeys: String, CodingKey {
                    case id, name
                    case inviteCode = "invite_code"
                }
            }
            let row: Row = try await client
                .from("arena_groups")
                .select("id, name, invite_code")
                .eq("id", value: groupID)
                .single()
                .execute()
                .value
            let count = try await memberCount(groupID: groupID)
            return GroupRow(id: row.id, name: row.name,
                            inviteCode: row.inviteCode, memberCount: count)
        } catch { throw mapPostgrestError(error) }
    }

    func leaveGroup(userID: UUID, groupID: UUID) async throws {
        try await call("leave_arena_group", params: [
            "p_user": .string(userID.uuidString),
            "p_group": .string(groupID.uuidString),
        ])
    }

    // MARK: Feed

    /// Événements visibles. Le filtrage est fait par la policy
    /// « feed readable by friends » : inutile de le refaire ici, et dangereux
    /// de croire qu'un filtre client protège quoi que ce soit.
    func fetchFeed(limit: Int = 20) async throws -> [FeedRow] {
        struct Row: Decodable {
            let id: UUID
            let actorID: UUID
            let kind: String
            /// Seul `name` est lu. Un `[String: String]` échouerait au décodage :
            /// le payload de `rank_up` porte aussi un `level` numérique.
            let payload: Payload
            let createdAt: Date
            struct Payload: Decodable { let name: String? }
            enum CodingKeys: String, CodingKey {
                case id, kind, payload
                case actorID = "actor_id"
                case createdAt = "created_at"
            }
        }
        let client = try SupabaseService.shared.requireClient()
        do {
            let rows: [Row] = try await client
                .from("arena_feed")
                .select("id, actor_id, kind, payload, created_at")
                .order("created_at", ascending: false)
                .limit(limit)
                .execute()
                .value
            let profiles = try await fetchProfiles(ids: rows.map(\.actorID))
            return rows.map {
                FeedRow(id: $0.id,
                        actorID: $0.actorID,
                        actorName: profiles[$0.actorID]?.username ?? "—",
                        kind: $0.kind,
                        // Les triggers écrivent le libellé sous `name` ; jamais
                        // de montant, par construction (0007).
                        subject: $0.payload.name ?? "",
                        createdAt: $0.createdAt)
            }
        } catch { throw mapPostgrestError(error) }
    }

    // MARK: Interne

    private func call(_ name: String, params: [String: AnyJSON]) async throws {
        let client = try SupabaseService.shared.requireClient()
        do {
            try await client.rpc(name, params: params).execute()
        } catch { throw mapPostgrestError(error) }
    }
}
