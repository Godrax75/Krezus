import SwiftUI
import AuthenticationServices
import Supabase

/// Formulaire d'inscription ou de connexion — un seul écran, deux modes, pour
/// que les deux chemins restent strictement parallèles : mêmes moyens (Apple,
/// Google, e-mail), même disposition, seuls les libellés changent.
struct AccountFormScreen: View {
    enum Mode: Hashable {
        case signUp, signIn

        var other: Mode { self == .signUp ? .signIn : .signUp }
    }

    let mode: Mode
    /// Bascule vers l'autre mode (« Déjà un compte ? Se connecter »).
    let switchMode: (Mode) -> Void

    @Environment(AuthService.self) private var auth

    @State private var email = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var isWorking = false
    @State private var error: String?
    @State private var confirmationSentTo: String?
    @State private var showForgotPassword = false

    @FocusState private var focus: Field?
    private enum Field { case email, password }

    /// Supabase accepte six caractères ; huit est le plancher couramment
    /// recommandé, et le vérifier ici évite un aller-retour pour rien.
    static let minimumPasswordLength = 8

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var isEmailPlausible: Bool {
        let parts = trimmedEmail.split(separator: "@")
        return parts.count == 2 && parts[1].contains(".") && !parts[0].isEmpty
    }

    private var canSubmit: Bool {
        guard isEmailPlausible, !isWorking else { return false }
        return mode == .signUp
            ? password.count >= Self.minimumPasswordLength
            : !password.isEmpty
    }

    var body: some View {
        Group {
            if let sentTo = confirmationSentTo {
                CheckEmailView(email: sentTo) { confirmationSentTo = nil }
            } else {
                form
            }
        }
        .background(KrezusColor.bg.ignoresSafeArea())
        .krezusNavBar("")
        .sheet(isPresented: $showForgotPassword) {
            ForgotPasswordSheet(initialEmail: trimmedEmail)
                .presentationDetents([.medium])
        }
    }

    // MARK: Formulaire

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KrezusSpacing.s4) {
                VStack(alignment: .leading, spacing: 6) {
                    Text((mode == .signUp ? t("account.signup.title") : t("account.signin.title")))
                        .font(KrezusFont.display(28, .heavy))
                        .foregroundStyle(KrezusColor.ink)
                    Text((mode == .signUp ? t("account.signup.subtitle") : t("account.signin.subtitle")))
                        .font(KrezusFont.bodyMd)
                        .foregroundStyle(KrezusColor.fg3)
                }
                .padding(.bottom, KrezusSpacing.s2)

                providerButtons

                orDivider

                emailFields

                if let error {
                    Text(error)
                        .font(KrezusFont.caption)
                        .foregroundStyle(KrezusColor.down)
                        .fixedSize(horizontal: false, vertical: true)
                }

                submitButton

                if mode == .signUp {
                    legalNote
                }

                switchLink
                    .frame(maxWidth: .infinity)
                    .padding(.top, KrezusSpacing.s2)
            }
            .padding(.horizontal, KrezusSpacing.s6)
            .padding(.top, KrezusSpacing.s2)
            .padding(.bottom, KrezusSpacing.s6 * 2)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: Apple et Google

    private var providerButtons: some View {
        VStack(spacing: KrezusSpacing.s3) {
            SignInWithAppleButton(mode == .signUp ? .signUp : .signIn) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                handleApple(result)
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 52)
            .clipShape(RoundedRectangle(cornerRadius: KrezusRadius.md, style: .continuous))
            // Le bouton système fige son libellé à sa création : sans cette
            // identité, la bascule vers la connexion garderait « S'inscrire
            // avec Apple ».
            .id(mode)

            if !AppConfig.googleClientID.isEmpty {
                Button {
                    Task { await run { try await auth.signInWithGoogle() } }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "globe")
                        Text((mode == .signUp ? t("account.google.signup") : t("account.google.signin")))
                    }
                    .font(KrezusFont.display(15.5, .semibold))
                    .foregroundStyle(KrezusColor.ink)
                    .frame(maxWidth: .infinity).frame(height: 52)
                    .background(KrezusColor.surface)
                    .clipShape(RoundedRectangle(cornerRadius: KrezusRadius.md, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: KrezusRadius.md, style: .continuous)
                        .stroke(KrezusColor.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var orDivider: some View {
        HStack(spacing: KrezusSpacing.s3) {
            Rectangle().fill(KrezusColor.divider).frame(height: 1)
            Text(t("account.or_email"))
                .font(KrezusFont.caption)
                .foregroundStyle(KrezusColor.fg3)
                .fixedSize()
            Rectangle().fill(KrezusColor.divider).frame(height: 1)
        }
        .padding(.vertical, KrezusSpacing.s1)
    }

    // MARK: E-mail et mot de passe

    private var emailFields: some View {
        VStack(alignment: .leading, spacing: KrezusSpacing.s3) {
            field {
                TextField(t("account.email.placeholder"), text: $email)
                    .keyboardType(.emailAddress)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .focused($focus, equals: .email)
                    .onSubmit { focus = .password }
            }

            field {
                HStack {
                    Group {
                        if showPassword {
                            TextField(t("account.password.placeholder"), text: $password)
                        } else {
                            SecureField(t("account.password.placeholder"), text: $password)
                        }
                    }
                    // `.newPassword` déclenche la suggestion de mot de passe
                    // fort d'iOS à l'inscription ; `.password` propose le
                    // trousseau à la connexion.
                    .textContentType(mode == .signUp ? .newPassword : .password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .focused($focus, equals: .password)
                    .onSubmit { if canSubmit { Task { await submit() } } }

                    Button { showPassword.toggle() } label: {
                        Image(systemName: showPassword ? "eye.slash" : "eye")
                            .foregroundStyle(KrezusColor.fg3)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel((showPassword ? t("account.password.hide") : t("account.password.show")))
                }
            }

            HStack {
                if mode == .signUp {
                    Text(t("account.password.hint", Self.minimumPasswordLength))
                        .font(KrezusFont.caption)
                        .foregroundStyle(KrezusColor.fg3)
                } else {
                    Spacer()
                    Button(t("account.forgot_password")) { showForgotPassword = true }
                        .font(KrezusFont.body(13, .semibold))
                        .foregroundStyle(KrezusColor.brandText)
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private func field<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .font(KrezusFont.body(16, .medium))
            .foregroundStyle(KrezusColor.ink)
            .padding(.horizontal, KrezusSpacing.s4)
            .frame(height: 52)
            .background(KrezusColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: KrezusRadius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: KrezusRadius.md, style: .continuous)
                .stroke(KrezusColor.border, lineWidth: 1))
    }

    private var submitButton: some View {
        KrzPrimaryButton(title: isWorking
                         ? t("account.working")
                         : (mode == .signUp ? t("account.signup.cta") : t("account.signin.cta"))) {
            Task { await submit() }
        }
        .disabled(!canSubmit)
        .opacity(canSubmit ? 1 : 0.5)
    }

    // MARK: Mentions et bascule

    /// Les liens vivent dans le catalogue, avec le reste du texte légal.
    private var legalNote: some View {
        Text(legalAttributed)
            .font(KrezusFont.caption)
            .foregroundStyle(KrezusColor.fg3)
            .tint(KrezusColor.brandText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var legalAttributed: AttributedString {
        let markdown = t("account.legal", t("legal.terms_url"), t("legal.privacy_url"))
        return (try? AttributedString(markdown: markdown)) ?? AttributedString(markdown)
    }

    private var switchLink: some View {
        HStack(spacing: 4) {
            Text((mode == .signUp ? t("account.signup.switch_prompt") : t("account.signin.switch_prompt")))
                .foregroundStyle(KrezusColor.fg3)
            Button((mode == .signUp ? t("account.signup.switch_cta") : t("account.signin.switch_cta"))) {
                switchMode(mode.other)
            }
            .foregroundStyle(KrezusColor.brandText)
            .buttonStyle(.plain)
        }
        .font(KrezusFont.body(14, .semibold))
    }

    // MARK: Actions

    private func submit() async {
        focus = nil
        let address = trimmedEmail
        await run {
            switch mode {
            case .signUp:
                if try await auth.signUp(email: address, password: password) == .confirmationSent {
                    confirmationSentTo = address
                }
            case .signIn:
                try await auth.signIn(email: address, password: password)
            }
        }
    }

    private func handleApple(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential
            else { return }
            Task { await run { try await auth.signInWithApple(credential) } }
        case .failure(let err):
            // L'annulation par l'utilisateur n'est pas une erreur à afficher.
            if (err as? ASAuthorizationError)?.code != .canceled {
                error = AuthErrorMessage.text(for: err)
            }
        }
    }

    /// Enveloppe commune : indicateur d'activité, effacement puis affichage
    /// de l'erreur.
    private func run(_ action: () async throws -> Void) async {
        isWorking = true
        error = nil
        defer { isWorking = false }
        do { try await action() }
        catch { self.error = AuthErrorMessage.text(for: error) }
    }
}

// MARK: - Confirmation d'e-mail

/// Affiché quand Supabase attend la confirmation de l'adresse. Le lien ouvre
/// l'app et y termine l'inscription — à condition de l'ouvrir sur le même
/// appareil : le flux PKCE y a laissé la moitié de la clé d'échange.
private struct CheckEmailView: View {
    let email: String
    let back: () -> Void

    @Environment(AuthService.self) private var auth
    @State private var resent = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: KrezusSpacing.s4) {
            Spacer()

            Image(systemName: "envelope.badge.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(KrezusColor.brandText)
                .frame(width: 112, height: 112)
                .background(KrezusColor.tintStrong)
                .clipShape(Circle())

            Text(t("account.check_email.title"))
                .font(KrezusFont.display(25, .heavy))
                .foregroundStyle(KrezusColor.ink)
                .multilineTextAlignment(.center)

            Text(t("account.check_email.body", email))
                .font(KrezusFont.bodyMd)
                .foregroundStyle(KrezusColor.fg3)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let error {
                Text(error).font(KrezusFont.caption).foregroundStyle(KrezusColor.down)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            Button((resent ? t("account.check_email.resent") : t("account.check_email.resend"))) {
                Task {
                    do {
                        try await auth.resendConfirmation(email: email)
                        resent = true
                    } catch {
                        self.error = AuthErrorMessage.text(for: error)
                    }
                }
            }
            .font(KrezusFont.body(14, .semibold))
            .foregroundStyle(KrezusColor.brandText)
            .buttonStyle(.plain)
            .disabled(resent)

            KrzPrimaryButton(title: t("account.check_email.back"), action: back)
        }
        .padding(.horizontal, KrezusSpacing.s6)
        .padding(.bottom, KrezusSpacing.s6)
    }
}

// MARK: - Mot de passe oublié

private struct ForgotPasswordSheet: View {
    let initialEmail: String

    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var sent = false
    @State private var isWorking = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: KrezusSpacing.s4) {
            Text(t("account.reset.title"))
                .font(KrezusFont.display(22, .heavy))
                .foregroundStyle(KrezusColor.ink)

            if sent {
                // Même message qu'il existe un compte ou non : sans quoi ce
                // formulaire dirait à n'importe qui quelles adresses sont
                // inscrites.
                Text(t("account.reset.sent", email))
                    .font(KrezusFont.bodyMd)
                    .foregroundStyle(KrezusColor.fg3)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                KrzPrimaryButton(title: t("common.close")) { dismiss() }
            } else {
                Text(t("account.reset.body"))
                    .font(KrezusFont.bodyMd)
                    .foregroundStyle(KrezusColor.fg3)
                    .fixedSize(horizontal: false, vertical: true)

                TextField(t("account.email.placeholder"), text: $email)
                    .keyboardType(.emailAddress)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(KrezusFont.body(16, .medium))
                    .padding(.horizontal, KrezusSpacing.s4)
                    .frame(height: 52)
                    .background(KrezusColor.surface)
                    .clipShape(RoundedRectangle(cornerRadius: KrezusRadius.md, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: KrezusRadius.md, style: .continuous)
                        .stroke(KrezusColor.border, lineWidth: 1))

                if let error {
                    Text(error).font(KrezusFont.caption).foregroundStyle(KrezusColor.down)
                }

                Spacer()

                KrzPrimaryButton(title: isWorking ? t("account.working") : t("account.reset.cta")) {
                    Task { await send() }
                }
                .disabled(isWorking || !email.contains("@"))
                .opacity(isWorking || !email.contains("@") ? 0.5 : 1)
            }
        }
        .padding(KrezusSpacing.s6)
        .background(KrezusColor.bg.ignoresSafeArea())
        .onAppear { email = initialEmail }
    }

    private func send() async {
        isWorking = true
        error = nil
        defer { isWorking = false }
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        do {
            try await auth.sendPasswordReset(email: address)
            email = address
            sent = true
        } catch {
            self.error = AuthErrorMessage.text(for: error)
        }
    }
}

// MARK: - Messages d'erreur

/// Traduit les erreurs de Supabase Auth en phrases lisibles. Les messages
/// bruts du serveur sont en anglais et techniques (« Invalid login
/// credentials ») : ils ne doivent jamais atteindre l'écran.
enum AuthErrorMessage {
    static func text(for error: Error) -> String {
        guard let authError = error as? AuthError else {
            return t("auth.error.generic")
        }
        switch authError.errorCode {
        case .invalidCredentials:
            return t("auth.error.invalid_credentials")
        case .emailNotConfirmed:
            return t("auth.error.email_not_confirmed")
        case .userAlreadyExists, .emailExists:
            return t("auth.error.already_exists")
        case .weakPassword:
            return t("auth.error.weak_password")
        case .overEmailSendRateLimit, .overRequestRateLimit:
            return t("auth.error.rate_limit")
        // Code renvoyé par le serveur mais absent des constantes du SDK.
        case ErrorCode(rawValue: "email_address_invalid"), .validationFailed:
            return t("auth.error.invalid_email")
        default:
            return t("auth.error.generic")
        }
    }
}
