import SwiftUI
import PhotosUI

/// Accueil d'un nouveau compte, entre la connexion et l'app : trois étapes.
///
/// 1. **Identité** — prénom et pseudo. Le pseudo est public (classement,
///    amis) et unique : sa disponibilité se vérifie pendant la frappe. Un
///    code de parrainage peut s'y glisser.
/// 2. **Cadeau** — une boîte à ouvrir, d'où sortent les 1 000 € de départ.
/// 3. **Versement hebdomadaire** — 300 € de plus chaque semaine, à condition
///    de passer ; ils ne comptent pas comme des gains.
///
/// Le pseudo est enregistré à la fin de la première étape : quitter l'app
/// ensuite ne fait pas perdre le choix, et l'accueil ne se rouvre plus.
struct WelcomeFlowScreen: View {
    @Environment(ProfileStore.self) private var profile
    @Environment(AuthService.self) private var auth
    @Environment(AppState.self) private var app

    enum Step: Int, CaseIterable { case identity, gift, weekly }
    @State private var step: Step = .identity

    var body: some View {
        ZStack {
            WelcomeBackground()

            Group {
                switch step {
                case .identity: WelcomeIdentityStep { advance() }
                case .gift:     WelcomeGiftStep { advance() }
                case .weekly:   WelcomeWeeklyStep { finish() }
                }
            }
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)))
            .id(step)

            VStack {
                Spacer()
                pageDots.padding(.bottom, 6)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(Step.allCases, id: \.self) { item in
                Capsule()
                    .fill(item == step ? KrezusColor.gold : Color.white.opacity(0.15))
                    .frame(width: 30, height: 6)
            }
        }
        .animation(.snappy, value: step)
        .accessibilityHidden(true)
    }

    private func advance() {
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        withAnimation(.snappy(duration: 0.4)) { step = next }
    }

    private func finish() {
        app.tab = .home
        withAnimation(.easeInOut(duration: 0.3)) { profile.finishSetup() }
    }
}

// MARK: - 1. Identité

private struct WelcomeIdentityStep: View {
    @Environment(ProfileStore.self) private var profile
    @Environment(AuthService.self) private var auth

    let onDone: () -> Void

    @State private var firstName = ""
    @State private var username = ""
    @State private var availability: Availability = .idle
    @State private var showsReferral = false
    @State private var referralCode = ""
    @State private var error: String?
    @State private var isSubmitting = false
    @State private var photoItem: PhotosPickerItem?

    @FocusState private var focus: Field?
    private enum Field { case firstName, username, referral }

    enum Availability: Equatable { case idle, checking, available, taken, invalid(String) }

    private var trimmedUsername: String { username.trimmingCharacters(in: .whitespaces) }
    private var canSubmit: Bool {
        availability == .available || (availability == .idle && ProfileStore.validate(trimmedUsername) == nil)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                avatar
                firstNameField
                usernameField
                referral
                if let error {
                    Text(error)
                        .font(KrezusFont.body(13, .semibold))
                        .foregroundStyle(Color(hex: 0xFF9B9B))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, KrezusSpacing.s5)
            .padding(.top, KrezusSpacing.s5)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            WelcomeButton(title: t("common.next"), enabled: canSubmit, isLoading: isSubmitting) {
                Task { await submit() }
            }
            .padding(.horizontal, KrezusSpacing.s5)
            .padding(.bottom, 34)
        }
        .task(id: username) { await checkAvailability() }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            photoItem = nil
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else { return }
                try? await profile.setAvatar(image, userID: auth.userID)
            }
        }
        .onAppear {
            if firstName.isEmpty, let known = profile.firstName { firstName = known }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Krezus.")
                .font(KrezusFont.display(20, .heavy))
                .foregroundStyle(KrezusColor.gold)
            VStack(alignment: .leading, spacing: 0) {
                Text(t("welcome.identity.title_1")).foregroundStyle(.white)
                Text(t("welcome.identity.title_2")).foregroundStyle(KrezusColor.gold)
            }
            .font(KrezusFont.display(38, .heavy))
            .lineLimit(1).minimumScaleFactor(0.6)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
        }
    }

    /// La photo est facultative : l'initiale du pseudo en tient lieu.
    private var avatar: some View {
        HStack(spacing: 16) {
            PhotosPicker(selection: $photoItem, matching: .images) {
                ZStack(alignment: .bottomTrailing) {
                    Group {
                        if let image = profile.avatar {
                            Image(uiImage: image).resizable().scaledToFill()
                        } else {
                            Text(String(trimmedUsername.first ?? firstName.first ?? "K").uppercased())
                                .font(KrezusFont.display(32, .heavy))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(LinearGradient(colors: [Color(hex: 0x3B4BD8), Color(hex: 0x1D2152)],
                                                           startPoint: .topLeading, endPoint: .bottomTrailing))
                        }
                    }
                    .frame(width: 78, height: 78)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(KrezusColor.gold, lineWidth: 2))

                    Image(systemName: profile.isUpdatingAvatar ? "hourglass" : "camera.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(KrezusColor.navyDeep)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(.white))
                        .offset(x: 2, y: 2)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(t("welcome.identity.photo"))

            Text(t("welcome.identity.photo_hint"))
                .font(KrezusFont.body(13.5, .medium))
                .foregroundStyle(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var firstNameField: some View {
        VStack(alignment: .leading, spacing: 10) {
            WelcomeFieldLabel(title: t("welcome.identity.first_name"))
            TextField("", text: $firstName,
                      prompt: Text(t("welcome.identity.first_name_placeholder")).foregroundStyle(.white.opacity(0.35)))
                .textContentType(.givenName)
                .submitLabel(.next)
                .focused($focus, equals: .firstName)
                .onSubmit { focus = .username }
                .welcomeField()
        }
    }

    private var usernameField: some View {
        VStack(alignment: .leading, spacing: 10) {
            WelcomeFieldLabel(title: t("welcome.identity.username"),
                              trailing: t("welcome.identity.username_public"))
            HStack(spacing: 2) {
                Text("@").foregroundStyle(.white.opacity(0.45))
                TextField("", text: $username,
                          prompt: Text(t("welcome.identity.username_placeholder")).foregroundStyle(.white.opacity(0.35)))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.nickname)
                    .submitLabel(.done)
                    .focused($focus, equals: .username)
                    .onSubmit { focus = nil }
                availabilityBadge
            }
            .welcomeField(border: borderColor)

            if case .invalid(let message) = availability {
                Text(message)
                    .font(KrezusFont.body(12.5, .medium))
                    .foregroundStyle(Color(hex: 0xFF9B9B))
            }
        }
    }

    @ViewBuilder
    private var availabilityBadge: some View {
        switch availability {
        case .checking:
            ProgressView().controlSize(.small).tint(.white)
        case .available:
            Label(t("welcome.identity.available"), systemImage: "checkmark")
                .font(KrezusFont.body(14, .bold))
                .foregroundStyle(Color(hex: 0x4ADE80))
                .transition(.scale.combined(with: .opacity))
        case .taken:
            Label(t("welcome.identity.taken"), systemImage: "xmark")
                .font(KrezusFont.body(14, .bold))
                .foregroundStyle(Color(hex: 0xFF9B9B))
                .transition(.scale.combined(with: .opacity))
        case .idle, .invalid:
            EmptyView()
        }
    }

    private var borderColor: Color {
        switch availability {
        case .available:         return Color(hex: 0x4ADE80).opacity(0.55)
        case .taken, .invalid:   return Color(hex: 0xFF9B9B).opacity(0.55)
        case .idle, .checking:   return .clear
        }
    }

    @ViewBuilder
    private var referral: some View {
        if showsReferral {
            VStack(alignment: .leading, spacing: 10) {
                WelcomeFieldLabel(title: t("welcome.identity.referral"))
                TextField("", text: $referralCode,
                          prompt: Text(t("referral.redeem.placeholder")).foregroundStyle(.white.opacity(0.35)))
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .focused($focus, equals: .referral)
                    .welcomeField()
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        } else {
            Button {
                withAnimation(.snappy) { showsReferral = true }
                focus = .referral
            } label: {
                Label(t("welcome.identity.invited"), systemImage: "gift")
                    .font(KrezusFont.body(15, .bold))
                    .foregroundStyle(KrezusColor.gold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Actions

    /// Attend que la frappe se pose avant d'interroger le serveur.
    private func checkAvailability() async {
        let candidate = trimmedUsername
        error = nil
        guard !candidate.isEmpty else { availability = .idle; return }
        if let invalid = ProfileStore.validate(candidate) {
            // « Trop court » ne s'affiche pas pendant qu'on tape les deux
            // premières lettres.
            availability = candidate.count < 3 ? .idle : .invalid(invalid.localizedDescription)
            return
        }
        availability = .checking
        try? await Task.sleep(for: .milliseconds(400))
        guard !Task.isCancelled else { return }
        let result = await profile.isUsernameAvailable(candidate)
        guard !Task.isCancelled else { return }
        withAnimation(.snappy) {
            switch result {
            case .some(true):  availability = .available
            case .some(false): availability = .taken
            case .none:        availability = .idle   // l'enregistrement tranchera
            }
        }
    }

    private func submit() async {
        focus = nil
        error = nil
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await profile.saveIdentity(firstName: firstName, username: username, userID: auth.userID)
        } catch KrezusError.usernameTaken {
            withAnimation(.snappy) { availability = .taken }
            return
        } catch {
            self.error = error.localizedDescription
            return
        }

        // Le code se valide après le pseudo : le parrain reçoit une
        // notification qui le nomme. Un code refusé n'efface pas le pseudo,
        // il se corrige ou s'efface.
        let code = referralCode.trimmingCharacters(in: .whitespaces)
        if !code.isEmpty, AppConfig.isConfigured {
            do {
                _ = try await ReferralRepository().redeem(code: code)
            } catch {
                self.error = error.localizedDescription
                return
            }
        }
        onDone()
    }
}

// MARK: - 2. Cadeau

private struct WelcomeGiftStep: View {
    let onDone: () -> Void

    @State private var opened = false
    @State private var cents: Double = 0
    @State private var wiggle = false
    @State private var showsText = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [KrezusColor.gold.opacity(opened ? 0.45 : 0.22), .clear],
                                         center: .center, startRadius: 5, endRadius: 170))
                    .frame(width: 340, height: 340)
                    .scaleEffect(opened ? 1.15 : 1)

                CelebrationBurst(fired: opened)

                if opened {
                    VStack(spacing: 6) {
                        Text("💎").font(.system(size: 64))
                            .transition(.scale(scale: 0.2).combined(with: .opacity))
                        CountingEuros(cents: cents)
                    }
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                } else {
                    Text("🎁")
                        .font(.system(size: 120))
                        .rotationEffect(.degrees(wiggle ? 7 : -7), anchor: .bottom)
                        .scaleEffect(wiggle ? 1.04 : 0.97)
                        .animation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true), value: wiggle)
                        .transition(.scale(scale: 1.8).combined(with: .opacity))
                }
            }
            .frame(height: 300)

            VStack(spacing: 14) {
                if opened {
                    Text(t("welcome.gift.ready"))
                        .font(KrezusFont.display(26, .heavy))
                        .foregroundStyle(KrezusColor.gold)
                    Text(t("welcome.gift.body"))
                        .font(KrezusFont.body(16, .medium))
                        .foregroundStyle(.white.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(t("welcome.gift.title"))
                        .font(KrezusFont.display(28, .heavy))
                        .foregroundStyle(.white)
                    Text(t("welcome.gift.tap"))
                        .font(KrezusFont.body(16, .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, KrezusSpacing.s6)
            .opacity(!opened || showsText ? 1 : 0)
            .offset(y: !opened || showsText ? 0 : 12)

            Spacer()
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture { open() }
        .safeAreaInset(edge: .bottom) {
            WelcomeButton(title: t("common.next"), action: onDone)
                .padding(.horizontal, KrezusSpacing.s5)
                .padding(.bottom, 34)
                .opacity(showsText ? 1 : 0)
                .allowsHitTesting(showsText)
        }
        .sensoryFeedback(.success, trigger: opened)
        .onAppear { wiggle = true }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: t("welcome.gift.tap")) { open() }
    }

    private func open() {
        guard !opened else { return }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { opened = true }
        withAnimation(.easeOut(duration: 1.6).delay(0.25)) { cents = Double(WeeklyBonus.welcomeCents) }
        withAnimation(.easeOut(duration: 0.4).delay(1.1)) { showsText = true }
    }
}

// MARK: - 3. Versement hebdomadaire

private struct WelcomeWeeklyStep: View {
    let onDone: () -> Void

    /// Nombre de semaines déjà « versées » dans l'animation (0…4).
    @State private var lit = 0
    @State private var cents = Double(WeeklyBonus.welcomeCents)

    private static let weeks = 4

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(t("welcome.weekly.title_1")).foregroundStyle(.white)
                    Text(t("welcome.weekly.title_2")).foregroundStyle(KrezusColor.gold)
                }
                .font(KrezusFont.display(36, .heavy))
                .lineLimit(1).minimumScaleFactor(0.6)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)

                timeline

                VStack(alignment: .leading, spacing: 16) {
                    rule("calendar", t("welcome.weekly.rule_login"))
                    rule("hourglass", t("welcome.weekly.rule_lost"))
                    rule("chart.line.uptrend.xyaxis", t("welcome.weekly.rule_perf"))
                }
            }
            .padding(.horizontal, KrezusSpacing.s5)
            .padding(.top, KrezusSpacing.s6)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .bottom) {
            WelcomeButton(title: t("welcome.weekly.start"), action: onDone)
                .padding(.horizontal, KrezusSpacing.s5)
                .padding(.bottom, 34)
        }
        .task { await play() }
    }

    /// Quatre semaines qui s'allument une à une, et le solde qui monte.
    private var timeline: some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                ForEach(1...Self.weeks, id: \.self) { week in
                    let on = week <= lit
                    VStack(spacing: 8) {
                        Text(t("welcome.weekly.week_short", week))
                            .font(KrezusFont.body(11.5, .bold)).tracking(0.8)
                            .foregroundStyle(on ? KrezusColor.navyDeep.opacity(0.7) : .white.opacity(0.45))
                        Text("+300")
                            .font(KrezusFont.display(17, .heavy))
                            .foregroundStyle(on ? KrezusColor.navyDeep : .white.opacity(0.35))
                        Image(systemName: on ? "checkmark.circle.fill" : "circle.dashed")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(on ? KrezusColor.navyDeep : .white.opacity(0.3))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: KrezusRadius.md, style: .continuous)
                            .fill(on ? AnyShapeStyle(LinearGradient(colors: [Color(hex: 0xF3D08A), KrezusColor.gold],
                                                                    startPoint: .top, endPoint: .bottom))
                                     : AnyShapeStyle(Color.white.opacity(0.07))))
                    .scaleEffect(on ? 1 : 0.94)
                    .animation(.spring(response: 0.35, dampingFraction: 0.6), value: lit)
                }
            }

            HStack(alignment: .firstTextBaseline) {
                Text(t("welcome.weekly.in_a_month"))
                    .font(KrezusFont.body(14, .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                CountingEuros(cents: cents, font: KrezusFont.display(30, .heavy))
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: KrezusRadius.lg, style: .continuous)
            .fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: KrezusRadius.lg, style: .continuous)
            .strokeBorder(Color.white.opacity(0.08)))
        .sensoryFeedback(.increase, trigger: lit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(t("welcome.weekly.a11y_timeline"))
    }

    private func rule(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(KrezusColor.gold)
                .frame(width: 36, height: 36)
                .background(Circle().fill(KrezusColor.gold.opacity(0.14)))
            Text(text)
                .font(KrezusFont.body(15, .medium))
                .foregroundStyle(.white.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func play() async {
        try? await Task.sleep(for: .milliseconds(450))
        for week in 1...Self.weeks {
            guard !Task.isCancelled else { return }
            lit = week
            withAnimation(.easeOut(duration: 0.45)) {
                cents = Double(WeeklyBonus.welcomeCents + week * WeeklyBonus.weeklyCents)
            }
            try? await Task.sleep(for: .milliseconds(520))
        }
    }
}
