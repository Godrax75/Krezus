import SwiftUI
import Observation

/// Notification affichée dans le centre de notifications.
///
/// `kind` reprend les valeurs écrites par les déclencheurs Postgres
/// (`0009_notifications.sql`) : c'est lui qui porte l'icône et la teinte, pas
/// un champ de présentation stocké en base — sinon un changement de charte
/// imposerait une migration de données.
struct KrezusNotification: Identifiable, Sendable {
    let id: UUID
    let kind: Kind
    let title: String
    let body: String?
    let createdAt: Date
    var readAt: Date?

    var isUnread: Bool { readAt == nil }

    enum Kind: String, Codable, Sendable {
        case order, rankUp = "rank_up", badge, friendRequest = "friend_request"
        case lessonReminder = "lesson_reminder", market, hercule

        var icon: String {
            switch self {
            case .order:          return "arrow.left.arrow.right"
            case .rankUp:         return "crown.fill"
            case .badge:          return "rosette"
            case .friendRequest:  return "person.badge.plus"
            case .lessonReminder: return "book.fill"
            case .market:         return "chart.line.uptrend.xyaxis"
            case .hercule:        return "sparkles"
            }
        }

        var tint: Color {
            switch self {
            case .order, .market:          return KrezusColor.brandText
            case .rankUp, .badge:          return KrezusColor.amberText
            case .friendRequest:           return KrezusColor.up
            case .lessonReminder, .hercule: return KrezusColor.brandText
            }
        }

        /// Catégorie de réglage qui gouverne l'envoi d'un push pour ce type.
        var topic: NotificationTopic {
            switch self {
            case .order, .market:           return .market
            case .rankUp, .badge, .lessonReminder: return .academy
            case .friendRequest:            return .arena
            case .hercule:                  return .hercule
            }
        }
    }
}

/// Boîte de réception des notifications.
///
/// En mode démo, source de vérité en mémoire. Branchée sur Supabase, elle lit
/// `public.notifications` (RLS « propriétaire uniquement ») et marque la
/// lecture côté serveur pour que le badge suive d'un appareil à l'autre.
@MainActor
@Observable
final class NotificationStore {

    private(set) var items: [KrezusNotification] = []
    private(set) var isLoading = false

    private let repository = NotificationsRepository()

    var unreadCount: Int { items.filter(\.isUnread).count }

    init() {
        items = Self.demoInbox()
    }

    /// Charge la boîte réelle ; conserve la démo si l'app n'est pas configurée.
    func load(userID: UUID?) async {
        guard AppConfig.isConfigured, let userID else { return }
        isLoading = true
        defer { isLoading = false }
        if let fetched = try? await repository.fetch(userID: userID) {
            items = fetched
        }
    }

    func markRead(_ id: UUID, userID: UUID?) {
        guard let index = items.firstIndex(where: { $0.id == id }), items[index].isUnread
        else { return }
        items[index].readAt = Date()
        persistRead(ids: [id], userID: userID)
    }

    func markAllRead(userID: UUID?) {
        let unread = items.filter(\.isUnread).map(\.id)
        guard !unread.isEmpty else { return }
        let now = Date()
        for index in items.indices where items[index].isUnread {
            items[index].readAt = now
        }
        persistRead(ids: unread, userID: userID)
    }

    /// Ajoute une notification produite localement (mode démo).
    func append(kind: KrezusNotification.Kind, title: String, body: String?) {
        items.insert(
            .init(id: UUID(), kind: kind, title: title, body: body,
                  createdAt: Date(), readAt: nil),
            at: 0)
    }

    private func persistRead(ids: [UUID], userID: UUID?) {
        guard AppConfig.isConfigured, let userID else { return }
        Task { try? await repository.markRead(ids: ids, userID: userID) }
    }

    // MARK: Démo

    /// Inbox de démonstration — reproduit les deux non-lues du prototype.
    private static func demoInbox() -> [KrezusNotification] {
        let now = Date()
        func ago(_ minutes: Int) -> Date { now.addingTimeInterval(-Double(minutes) * 60) }

        return [
            .init(id: UUID(), kind: .rankUp,
                  title: t("demo_notif.rank_up.title"),
                  body: t("demo_notif.rank_up.body"),
                  createdAt: ago(35), readAt: nil),
            .init(id: UUID(), kind: .lessonReminder,
                  title: t("demo_notif.lesson.title"),
                  body: t("demo_notif.lesson.body"),
                  createdAt: ago(190), readAt: nil),
            .init(id: UUID(), kind: .order,
                  title: t("demo_notif.order.title"),
                  body: t("demo_notif.order.body", Money.euros(100), Money.shares(0.45)),
                  createdAt: ago(1_450), readAt: ago(1_400)),
            .init(id: UUID(), kind: .friendRequest,
                  title: t("demo_notif.friend.title"),
                  body: t("demo_notif.friend.body", 3),
                  createdAt: ago(2_900), readAt: ago(2_800)),
        ]
    }
}
