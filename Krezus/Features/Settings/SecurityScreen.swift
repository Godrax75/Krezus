import SwiftUI

/// « Sécurité » — verrou biométrique, session, données personnelles.
struct SecurityScreen: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(AuthService.self) private var auth
    @Environment(BiometricLock.self) private var lock
    @Environment(PushNotificationService.self) private var push
    @Environment(Router.self) private var router

    @State private var confirmingSignOut = false
    @State private var confirmingDeletion = false
    @State private var deletionError: String?

    var body: some View {
        @Bindable var settings = settings

        return ZStack {
            KrezusColor.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: KrezusSpacing.s3) {
                    KrzGroupLabel(text: t("security.group.access"))
                    KrzSettingsGroup {
                        KrzToggleRow(
                            icon: "faceid",
                            title: t("security.lock_with", lock.biometryLabel),
                            subtitle: lock.isAvailable
                                ? t("security.lock_detail")
                                : t("security.lock_unavailable"),
                            isEnabled: lock.isAvailable,
                            isOn: $settings.biometricLock)
                    }

                    KrzGroupLabel(text: t("security.group.session"))
                    sessionGroup

                    KrzGroupLabel(text: t("security.group.data"))
                    dataGroup

                    if AppConfig.isConfigured {
                        KrzSettingsGroup {
                            KrzSettingsRow(icon: "trash.fill", title: t("profile.delete.confirm"),
                                           subtitle: deletionError, isDestructive: true,
                                           showsChevron: false) {
                                confirmingDeletion = true
                            }
                        }
                        .padding(.top, KrezusSpacing.s3)
                    }

                    KrzPaperMoneyNote().padding(.top, KrezusSpacing.s4)
                }
                .padding(.horizontal, KrezusSpacing.s4)
                .padding(.bottom, 60)
            }
            .scrollIndicators(.hidden)
        }
        .krezusNavBar(t("profile.row.security"))
        .confirmationDialog(t("profile.sign_out.title"), isPresented: $confirmingSignOut,
                            titleVisibility: .visible) {
            Button(t("profile.sign_out"), role: .destructive) { Task { await signOut() } }
            Button(t("common.cancel"), role: .cancel) {}
        }
        .confirmationDialog(t("profile.delete.title"),
                            isPresented: $confirmingDeletion, titleVisibility: .visible) {
            Button(t("profile.delete.confirm"), role: .destructive) { Task { await deleteAccount() } }
            Button(t("common.cancel"), role: .cancel) {}
        } message: {
            Text(t("profile.delete.message"))
        }
    }

    // MARK: Session

    @ViewBuilder
    private var sessionGroup: some View {
        if AppConfig.isConfigured {
            KrzSettingsGroup {
                KrzSettingsRow(icon: "person.badge.key.fill", title: t("security.signed_in_with"),
                               value: providerLabel, showsChevron: false) {}
                if let email = auth.session?.user.email {
                    KrzRowDivider()
                    KrzSettingsRow(icon: "envelope.fill", title: t("security.email"),
                                   subtitle: email, showsChevron: false) {}
                }
                KrzRowDivider()
                KrzSettingsRow(icon: "rectangle.portrait.and.arrow.right",
                               title: t("profile.sign_out"), showsChevron: false) {
                    confirmingSignOut = true
                }
            }
        } else {
            KrzSettingsGroup {
                KrzSettingsRow(icon: "wifi.slash", title: t("security.demo_mode"),
                               subtitle: t("security.demo_mode_detail"),
                               showsChevron: false) {}
            }
        }
    }

    /// Fournisseur d'identité. Apple et Google sont les deux seuls déclarés
    /// côté Supabase ; tout autre libellé signalerait une config inattendue.
    private var providerLabel: String {
        switch auth.session?.user.appMetadata["provider"]?.stringValue {
        case "apple":  return "Apple"
        case "google": return "Google"
        case let other?: return other.capitalized
        case nil:      return "—"
        }
    }

    // MARK: Données

    private var dataGroup: some View {
        KrzSettingsGroup {
            KrzSettingsRow(icon: "server.rack", title: t("security.hosting"),
                           subtitle: t("security.hosting_detail"),
                           showsChevron: false) {}
            KrzRowDivider()
            KrzSettingsRow(icon: "eye.slash.fill", title: t("security.never_shared"),
                           subtitle: t("security.never_shared_detail"),
                           showsChevron: false) {}
            KrzRowDivider()
            KrzSettingsRow(icon: "doc.text.fill", title: t("security.privacy_terms")) {
                router.push(.help)
            }
        }
    }

    // MARK: Actions

    private func signOut() async {
        await push.unregisterCurrentDevice()
        await auth.signOut()
        router.popToRoot()
    }

    private func deleteAccount() async {
        do {
            try await NotificationsRepository().deleteAccount()
            await push.unregisterCurrentDevice()
            await auth.signOut()
            router.popToRoot()
        } catch {
            deletionError = error.localizedDescription
        }
    }
}
