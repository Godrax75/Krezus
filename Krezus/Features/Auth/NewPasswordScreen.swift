import SwiftUI

/// Affiché après ouverture d'un lien de réinitialisation. Le lien a déjà ouvert
/// une session : il ne reste qu'à choisir le nouveau mot de passe, après quoi
/// l'aiguillage racine laisse entrer dans l'app.
struct NewPasswordScreen: View {
    @Environment(AuthService.self) private var auth

    @State private var password = ""
    @State private var showPassword = false
    @State private var isWorking = false
    @State private var error: String?

    private var canSave: Bool {
        password.count >= AccountFormScreen.minimumPasswordLength && !isWorking
    }

    var body: some View {
        VStack(alignment: .leading, spacing: KrezusSpacing.s4) {
            Text(t("account.new_password.title"))
                .font(KrezusFont.display(28, .heavy))
                .foregroundStyle(KrezusColor.ink)
            Text(t("account.new_password.body"))
                .font(KrezusFont.bodyMd)
                .foregroundStyle(KrezusColor.fg3)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Group {
                    if showPassword {
                        TextField(t("account.password.placeholder"), text: $password)
                    } else {
                        SecureField(t("account.password.placeholder"), text: $password)
                    }
                }
                .textContentType(.newPassword)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

                Button { showPassword.toggle() } label: {
                    Image(systemName: showPassword ? "eye.slash" : "eye")
                        .foregroundStyle(KrezusColor.fg3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel((showPassword ? t("account.password.hide") : t("account.password.show")))
            }
            .font(KrezusFont.body(16, .medium))
            .foregroundStyle(KrezusColor.ink)
            .padding(.horizontal, KrezusSpacing.s4)
            .frame(height: 52)
            .background(KrezusColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: KrezusRadius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: KrezusRadius.md, style: .continuous)
                .stroke(KrezusColor.border, lineWidth: 1))

            Text(t("account.password.hint", AccountFormScreen.minimumPasswordLength))
                .font(KrezusFont.caption)
                .foregroundStyle(KrezusColor.fg3)

            if let error {
                Text(error).font(KrezusFont.caption).foregroundStyle(KrezusColor.down)
            }

            Spacer()

            KrzPrimaryButton(title: isWorking ? t("account.working") : t("account.new_password.cta")) {
                Task { await save() }
            }
            .disabled(!canSave)
            .opacity(canSave ? 1 : 0.5)
        }
        .padding(KrezusSpacing.s6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(KrezusColor.bg.ignoresSafeArea())
    }

    private func save() async {
        isWorking = true
        error = nil
        defer { isWorking = false }
        do { try await auth.updatePassword(password) }
        catch { self.error = AuthErrorMessage.text(for: error) }
    }
}
