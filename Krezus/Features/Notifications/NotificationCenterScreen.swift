import SwiftUI

/// « Centre de notifications » — l'historique, groupé par jour.
///
/// Il existe indépendamment des push : une notification manquée parce que
/// l'utilisateur les a refusées reste consultable ici.
struct NotificationCenterScreen: View {
    @Environment(NotificationStore.self) private var notifications
    @Environment(AuthService.self) private var auth

    var body: some View {
        ZStack {
            KrezusColor.bg.ignoresSafeArea()

            if notifications.items.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: KrezusSpacing.s3) {
                        ForEach(groups, id: \.title) { group in
                            KrzGroupLabel(text: group.title)
                            KrzSettingsGroup {
                                ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                                    row(item)
                                    if index < group.items.count - 1 { KrzRowDivider() }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, KrezusSpacing.s4)
                    .padding(.bottom, 60)
                }
                .scrollIndicators(.hidden)
            }
        }
        .krezusNavBar(t("profile.row.notifications")) {
            if notifications.unreadCount > 0 {
                Button {
                    notifications.markAllRead(userID: auth.userID)
                } label: {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(KrezusColor.brandText)
                        .frame(width: 36, height: 36)
                        .background(KrezusColor.surface).clipShape(Circle())
                        .krezusShadow(KrezusShadow.level1)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(t("notif_center.mark_all_read"))
            }
        }
        .task { await notifications.load(userID: auth.userID) }
    }

    // MARK: Regroupement

    private struct DayGroup {
        let title: String
        let items: [KrezusNotification]
    }

    /// Aujourd'hui / Hier / Plus tôt — trois seaux suffisent : au-delà, une date
    /// exacte informe moins qu'elle n'encombre.
    private var groups: [DayGroup] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else {
            return [DayGroup(title: t("profile.row.notifications"), items: notifications.items)]
        }

        var byBucket: [Int: [KrezusNotification]] = [:]
        for item in notifications.items {
            let day = calendar.startOfDay(for: item.createdAt)
            let bucket = day >= today ? 0 : (day >= yesterday ? 1 : 2)
            byBucket[bucket, default: []].append(item)
        }

        return [(0, t("date.today")), (1, t("date.yesterday")), (2, t("date.earlier"))]
            .compactMap { bucket, title in
                guard let items = byBucket[bucket], !items.isEmpty else { return nil }
                return DayGroup(title: title, items: items)
            }
    }

    // MARK: Ligne

    private func row(_ item: KrezusNotification) -> some View {
        Button {
            notifications.markRead(item.id, userID: auth.userID)
        } label: {
            HStack(alignment: .top, spacing: KrezusSpacing.s3) {
                Image(systemName: item.kind.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(item.kind.tint)
                    .frame(width: 32, height: 32)
                    .background(KrezusColor.tint)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text(item.title)
                            .font(KrezusFont.display(14, item.isUnread ? .bold : .semibold))
                            .foregroundStyle(KrezusColor.ink)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 4)
                        Text(Self.relative(item.createdAt))
                            .font(KrezusFont.caption).foregroundStyle(KrezusColor.fg3)
                    }
                    if let body = item.body {
                        Text(body)
                            .font(KrezusFont.bodySm).foregroundStyle(KrezusColor.fg3)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if item.isUnread {
                    Circle().fill(KrezusColor.amber500)
                        .frame(width: 7, height: 7)
                        .padding(.top, 6)
                        .accessibilityLabel(t("notif_center.unread"))
                }
            }
            .padding(.horizontal, KrezusSpacing.s4)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Ancienneté compacte : « 41 min », « 3 h », « 2 j ».
    ///
    /// `RelativeDateTimeFormatter` en style abrégé rend « -41 min » en
    /// français — un signe moins qui se lit comme une perte sur un écran plein
    /// de variations de cours. Le format est donc écrit à la main.
    private static func relative(_ date: Date) -> String {
        let seconds = max(0, Date().timeIntervalSince(date))
        switch seconds {
        case ..<60:      return t("time.just_now")
        case ..<3_600:   return t("format.minutes_short", Int(seconds / 60))
        case ..<86_400:  return t("format.hours_short", Int(seconds / 3_600))
        case ..<604_800: return t("format.days_short", Int(seconds / 86_400))
        default:         return t("format.weeks_short", Int(seconds / 604_800))
        }
    }

    // MARK: Vide

    private var emptyState: some View {
        VStack(spacing: KrezusSpacing.s3) {
            Image(systemName: "bell.slash")
                .font(.system(size: 26))
                .foregroundStyle(KrezusColor.fg4)
                .frame(width: 68, height: 68)
                .background(KrezusColor.tint).clipShape(Circle())
            Text(t("notif_center.empty_title"))
                .font(KrezusFont.display(17, .bold)).foregroundStyle(KrezusColor.ink)
            Text(t("notif_center.empty_body"))
                .font(KrezusFont.bodyMd).foregroundStyle(KrezusColor.fg3)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, KrezusSpacing.s6)
        }
        .padding(.bottom, 60)
    }
}
