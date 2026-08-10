import SwiftUI

/// « Notifications » — autorisation système puis choix des catégories.
///
/// Les interrupteurs par catégorie restent visibles mais inertes tant que
/// l'autorisation n'est pas accordée : les masquer donnerait un écran vide
/// sans expliquer ce qu'on rate.
struct NotificationSettingsScreen: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(PushNotificationService.self) private var push
    @Environment(Router.self) private var router

    var body: some View {
        ZStack {
            KrezusColor.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: KrezusSpacing.s3) {
                    authorizationCard

                    KrzGroupLabel(text: t("notif_settings.group.topics"))
                    topicsGroup

                    KrzGroupLabel(text: t("notif_settings.group.in_app"))
                    KrzSettingsGroup {
                        KrzSettingsRow(icon: "tray.full.fill",
                                       title: t("notif_center.title"),
                                       subtitle: t("notif_settings.center_detail")) {
                            router.push(.notificationCenter)
                        }
                    }

                    Text(t("notif_settings.policy"))
                        .font(KrezusFont.caption).foregroundStyle(KrezusColor.fg3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4).padding(.top, KrezusSpacing.s3)
                }
                .padding(.horizontal, KrezusSpacing.s4)
                .padding(.bottom, 60)
            }
            .scrollIndicators(.hidden)
        }
        .krezusNavBar(t("profile.row.notifications"))
        .task { await push.refreshStatus() }
    }

    // MARK: Autorisation système

    @ViewBuilder
    private var authorizationCard: some View {
        KrzCard(shadow: push.isAuthorized ? KrezusShadow.level1 : KrezusShadow.brand) {
            VStack(alignment: .leading, spacing: KrezusSpacing.s3) {
                HStack(spacing: KrezusSpacing.s3) {
                    Image(systemName: push.isAuthorized ? "bell.badge.fill" : "bell.slash.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(push.isAuthorized ? KrezusColor.up : KrezusColor.fg3)
                        .frame(width: 38, height: 38)
                        .background(push.isAuthorized ? KrezusColor.upBg : KrezusColor.tint)
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        Text(push.isAuthorized ? t("notif_settings.on") : t("notif_settings.off"))
                            .font(KrezusFont.cardTitle).foregroundStyle(KrezusColor.ink)
                        Text(statusDetail)
                            .font(KrezusFont.caption).foregroundStyle(KrezusColor.fg3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }

                if !push.isAuthorized {
                    KrzPrimaryButton(title: push.isDenied
                                     ? t("notif_settings.open_ios_settings")
                                     : t("notif_settings.enable")) {
                        if push.isDenied {
                            push.openSystemSettings()
                        } else {
                            Task { await push.requestAuthorization() }
                        }
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    private var statusDetail: String {
        if push.isDenied {
            return t("notif_settings.status.denied")
        }
        if push.isAuthorized {
            return push.deviceToken == nil
                ? t("notif_settings.status.no_token")
                : t("notif_settings.status.registered")
        }
        return t("notif_settings.status.default")
    }

    // MARK: Catégories

    private var topicsGroup: some View {
        KrzSettingsGroup {
            ForEach(Array(NotificationTopic.allCases.enumerated()), id: \.element.id) { index, topic in
                KrzToggleRow(
                    icon: topic.icon,
                    title: topic.title,
                    subtitle: topic.subtitle,
                    isEnabled: push.isAuthorized,
                    isOn: Binding(
                        get: { settings.isTopicEnabled(topic) },
                        set: { settings.setTopic(topic, enabled: $0) }))

                if index < NotificationTopic.allCases.count - 1 {
                    KrzRowDivider()
                }
            }
        }
        .opacity(push.isAuthorized ? 1 : 0.55)
    }
}
