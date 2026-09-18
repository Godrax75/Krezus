import SwiftUI
import PhotosUI

/// Écran « Profil » — identité, progression, réglages, vitrine du mode réel.
///
/// La mention « Titres conservés par Alpaca Securities LLC · Membre FINRA/SIPC »
/// du prototype n'est **pas** reprise : aucun contrat courtier n'est signé, et
/// une garantie de dépôt affichée à tort est une allégation trompeuse, pas un
/// détail de maquette.
struct ProfileScreen: View {
    @Environment(AppState.self) private var app
    @Environment(AuthService.self) private var auth
    @Environment(ProfileStore.self) private var profile
    @Environment(LearningStore.self) private var learning
    @Environment(TradingStore.self) private var trading
    @Environment(SubscriptionService.self) private var subscriptions
    @Environment(PushNotificationService.self) private var push
    @Environment(Router.self) private var router

    @State private var confirmingReset = false
    @State private var choosingPhotoSource = false
    @State private var showingLibrary = false
    @State private var showingCamera = false
    @State private var libraryItem: PhotosPickerItem?
    @State private var avatarError: String?
    @State private var confirmingSignOut = false
    @State private var confirmingDeletion = false
    @State private var deletionError: String?

    private var isPremium: Bool { subscriptions.isSubscribed || learning.isPremium }

    var body: some View {
        ZStack {
            KrezusColor.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: KrezusSpacing.s3) {
                    identityCard
                    statsRow

                    KrzGroupLabel(text: t("profile.group.account"))
                    accountGroup

                    KrzGroupLabel(text: "Hercule")
                    premiumGroup

                    KrzGroupLabel(text: t("profile.group.preferences"))
                    preferencesGroup

                    KrzGroupLabel(text: t("profile.group.real_mode"))
                    realModeGroup

                    KrzGroupLabel(text: t("profile.group.discover"))
                    discoverGroup

                    KrzGroupLabel(text: t("profile.group.support"))
                    supportGroup

                    dangerGroup
                        .padding(.top, KrezusSpacing.s3)

                    footer
                }
                .padding(.horizontal, KrezusSpacing.s4)
                .padding(.bottom, 60)
            }
            .scrollIndicators(.hidden)
        }
        .krezusNavBar(t("profile.title"))
        .task { await profile.load(userID: auth.userID) }
        .confirmationDialog(t("profile.reset.title"),
                            isPresented: $confirmingReset, titleVisibility: .visible) {
            Button(t("profile.reset.confirm"), role: .destructive) {
                Task {
                    do {
                        try await trading.reset()
                        router.showToast(t("profile.reset.toast", Money.euros(1000)))
                    } catch {
                        router.showToast(error.localizedDescription)
                    }
                }
            }
            Button(t("common.cancel"), role: .cancel) {}
        } message: {
            Text(t("profile.reset.message", Money.euros(1000)))
        }
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
        .confirmationDialog(t("avatar.dialog.title"), isPresented: $choosingPhotoSource,
                            titleVisibility: .visible) {
            if CameraPicker.isAvailable {
                Button(t("avatar.take_photo")) { showingCamera = true }
            }
            Button(t("avatar.choose_photo")) { showingLibrary = true }
            if profile.avatar != nil {
                Button(t("avatar.remove"), role: .destructive) {
                    Task { await removeAvatar() }
                }
            }
            Button(t("common.cancel"), role: .cancel) {}
        }
        // Le sélecteur de photos tourne hors du processus de l'app : il ne
        // demande aucune autorisation d'accès à la photothèque, et l'app ne
        // voit que la photo choisie.
        .photosPicker(isPresented: $showingLibrary, selection: $libraryItem,
                      matching: .images, preferredItemEncoding: .compatible)
        .onChange(of: libraryItem) { _, item in
            guard let item else { return }
            libraryItem = nil
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else {
                    avatarError = t("avatar.error.unreadable")
                    return
                }
                await setAvatar(image)
            }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPicker { image in Task { await setAvatar(image) } }
                .ignoresSafeArea()
        }
        .alert(t("avatar.error.title"), isPresented: Binding(
            get: { avatarError != nil }, set: { if !$0 { avatarError = nil } })) {
            Button(t("common.ok"), role: .cancel) {}
        } message: {
            Text(avatarError ?? "")
        }
    }

    // MARK: Photo de profil

    /// L'avatar ouvre le choix de la source ; un badge appareil photo signale
    /// qu'il est modifiable, et une roue remplace la photo pendant l'envoi.
    private var avatarButton: some View {
        Button { choosingPhotoSource = true } label: {
            KrzAvatar(initial: profile.initial, size: 62, image: profile.avatar)
                .overlay {
                    if profile.isUpdatingAvatar {
                        Circle().fill(.black.opacity(0.35))
                        ProgressView().tint(.white)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(KrezusColor.brandFill)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(KrezusColor.surface, lineWidth: 2))
                        .offset(x: 2, y: 2)
                }
        }
        .buttonStyle(.plain)
        .disabled(profile.isUpdatingAvatar)
        .accessibilityLabel(t("avatar.a11y"))
    }

    private func setAvatar(_ image: UIImage) async {
        do { try await profile.setAvatar(image, userID: auth.userID) }
        catch { avatarError = t("avatar.error.upload") }
    }

    private func removeAvatar() async {
        do { try await profile.removeAvatar(userID: auth.userID) }
        catch { avatarError = t("avatar.error.upload") }
    }

    // MARK: Identité

    private var identityCard: some View {
        KrzCard(shadow: KrezusShadow.level2) {
            VStack(spacing: KrezusSpacing.s3) {
                HStack(spacing: KrezusSpacing.s3) {
                    avatarButton

                    VStack(alignment: .leading, spacing: 3) {
                        Text(profile.username)
                            .font(KrezusFont.display(19, .heavy))
                            .foregroundStyle(KrezusColor.ink)
                        Text(t("profile.member_since", profile.memberSinceLabel))
                            .font(KrezusFont.caption).foregroundStyle(KrezusColor.fg3)
                        if isPremium {
                            Text(t("profile.premium_badge"))
                                .font(KrezusFont.body(9, .bold)).tracking(0.7)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(KrezusColor.gradientAmber)
                                .clipShape(Capsule())
                                .padding(.top, 2)
                        }
                    }

                    Spacer(minLength: 0)

                    Button { router.push(.editUsername) } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(KrezusColor.brandText)
                            .frame(width: 32, height: 32)
                            .background(KrezusColor.tint).clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(t("profile.edit_username"))
                }

                Button { router.push(.ranks) } label: {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 7) {
                            RankBadge(rank: learning.currentRank, size: 30)
                            Text(learning.currentRank?.name ?? "")
                                .font(KrezusFont.display(14, .bold))
                                .foregroundStyle(KrezusColor.ink)
                            Spacer()
                            Text(t("format.xp", learning.xp))
                                .font(KrezusFont.body(12, .semibold))
                                .foregroundStyle(KrezusColor.fg3).tabularNumbers()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(KrezusColor.fg4)
                        }
                        KrzProgressBar(value: learning.rankProgress)
                        Text(nextRankLabel)
                            .font(KrezusFont.caption).foregroundStyle(KrezusColor.fg3)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var nextRankLabel: String {
        guard let remaining = learning.xpToNextRank, let next = learning.nextRank else {
            return t("profile.max_rank")
        }
        return t("profile.next_rank", remaining, next.name)
    }

    private var statsRow: some View {
        HStack(spacing: KrezusSpacing.s2) {
            statTile(value: "\(learning.completedCount)", label: t("profile.stat.lessons"), icon: "book.fill")
            statTile(value: "\(trading.holdingSymbols.count)", label: t("profile.stat.positions"), icon: "chart.pie.fill")
            statTile(value: "\(learning.earnedBadges.count)", label: t("profile.stat.badges"), icon: "rosette")
        }
    }

    private func statTile(value: String, label: String, icon: String) -> some View {
        KrzCard(padding: KrezusSpacing.s3) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 13)).foregroundStyle(KrezusColor.amber500)
                Text(value)
                    .font(KrezusFont.display(19, .heavy))
                    .foregroundStyle(KrezusColor.ink).tabularNumbers()
                Text(label)
                    .font(KrezusFont.caption).foregroundStyle(KrezusColor.fg3)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Groupes

    private var accountGroup: some View {
        KrzSettingsGroup {
            KrzSettingsRow(icon: "person.fill", title: t("profile.row.username"), value: profile.username) {
                router.push(.editUsername)
            }
            KrzRowDivider()
            KrzSettingsRow(icon: "gift.fill", title: t("profile.row.referral"),
                           subtitle: t("profile.row.referral_detail")) {
                router.push(.referral)
            }
            KrzRowDivider()
            KrzSettingsRow(icon: "flame.fill", title: t("profile.row.streak"),
                           subtitle: t(L10n.plural(Double(learning.streakDays),
                                                   one: "profile.row.streak.one",
                                                   other: "profile.row.streak.other"),
                                       learning.streakDays)) {
                router.push(.streak)
            }
            KrzRowDivider()
            KrzSettingsRow(icon: "arrow.left.arrow.right", title: t("profile.row.mode"),
                           value: app.mode.label) {
                router.cover = .modeSwitch
            }
        }
    }

    private var premiumGroup: some View {
        KrzSettingsGroup {
            KrzSettingsRow(
                icon: "sparkles",
                title: isPremium ? t("profile.premium.active") : t("profile.premium.upgrade"),
                subtitle: isPremium
                    ? t("profile.premium.active_detail")
                    : t("profile.premium.upgrade_detail"),
                tint: KrezusColor.amberText
            ) {
                router.push(.paywall)
            }
        }
    }

    private var preferencesGroup: some View {
        KrzSettingsGroup {
            KrzSettingsRow(icon: "paintbrush.fill", title: t("profile.row.appearance")) {
                router.push(.settings)
            }
            KrzRowDivider()
            KrzSettingsRow(icon: "bell.fill", title: t("profile.row.notifications"),
                           value: push.isAuthorized ? t("common.enabled") : t("common.disabled")) {
                router.push(.notificationSettings)
            }
            KrzRowDivider()
            KrzSettingsRow(icon: "lock.shield.fill", title: t("profile.row.security")) {
                router.push(.security)
            }
        }
    }

    private var realModeGroup: some View {
        KrzSettingsGroup {
            lockedRow(.kyc)
            KrzRowDivider()
            lockedRow(.activateCard)
            KrzRowDivider()
            lockedRow(.myCards)
            KrzRowDivider()
            lockedRow(.bankDetails)
            KrzRowDivider()
            lockedRow(.recurringInvestment)
            KrzRowDivider()
            lockedRow(.realCode)
        }
    }

    private var discoverGroup: some View {
        KrzSettingsGroup {
            lockedRow(.reveal)
            KrzRowDivider()
            lockedRow(.giftBox)
            KrzRowDivider()
            lockedRow(.referral)
            KrzRowDivider()
            lockedRow(.taxDocuments)
        }
    }

    private var supportGroup: some View {
        KrzSettingsGroup {
            KrzSettingsRow(icon: "questionmark.circle.fill", title: t("profile.row.help")) {
                router.push(.help)
            }
        }
    }

    private var dangerGroup: some View {
        KrzSettingsGroup {
            KrzSettingsRow(icon: "arrow.counterclockwise", title: t("profile.row.reset"),
                           subtitle: t("profile.row.reset_detail", Money.euros(1000)),
                           showsChevron: false) {
                confirmingReset = true
            }
            if AppConfig.isConfigured {
                KrzRowDivider()
                KrzSettingsRow(icon: "rectangle.portrait.and.arrow.right",
                               title: t("profile.sign_out"), showsChevron: false) {
                    confirmingSignOut = true
                }
                KrzRowDivider()
                KrzSettingsRow(icon: "trash.fill", title: t("profile.delete.confirm"),
                               subtitle: deletionError, isDestructive: true,
                               showsChevron: false) {
                    confirmingDeletion = true
                }
            }
        }
    }

    private func lockedRow(_ feature: LockedFeature) -> some View {
        KrzSettingsRow(icon: feature.icon, title: feature.title, isLocked: true) {
            router.push(.locked(feature))
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: KrezusSpacing.s2) {
            KrzPaperMoneyNote()
            Text(t("profile.footer_version", Self.version))
                .font(KrezusFont.caption).foregroundStyle(KrezusColor.fg3)
                .padding(.horizontal, 4)
        }
        .padding(.top, KrezusSpacing.s4)
    }

    private static var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return "\(short ?? "0.1.0") (\(build ?? "1"))"
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
