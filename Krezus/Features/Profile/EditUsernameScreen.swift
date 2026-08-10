import SwiftUI

/// « Modifier le pseudo ». Le pseudo est public — classement Arena, feed des
/// amis — d'où la validation stricte affichée en direct plutôt qu'un refus
/// serveur après coup.
struct EditUsernameScreen: View {
    @Environment(ProfileStore.self) private var profile
    @Environment(AuthService.self) private var auth
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss

    @State private var draft = ""
    @State private var error: String?
    @FocusState private var isFocused: Bool

    private var trimmed: String { draft.trimmingCharacters(in: .whitespaces) }
    private var validationError: ProfileStore.UsernameError? { ProfileStore.validate(draft) }
    private var canSave: Bool {
        validationError == nil && trimmed != profile.username && !profile.isSaving
    }

    var body: some View {
        ZStack {
            KrezusColor.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: KrezusSpacing.s3) {
                    HStack {
                        Spacer()
                        KrzAvatar(initial: initialPreview, size: 72)
                        Spacer()
                    }
                    .padding(.vertical, KrezusSpacing.s4)

                    KrzCard {
                        VStack(alignment: .leading, spacing: KrezusSpacing.s2) {
                            Text(t("username.field_label"))
                                .font(KrezusFont.body(10, .bold)).tracking(0.7)
                                .foregroundStyle(KrezusColor.fg3)

                            TextField(t("username.placeholder"), text: $draft)
                                .font(KrezusFont.display(17, .semibold))
                                .foregroundStyle(KrezusColor.ink)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .submitLabel(.done)
                                .focused($isFocused)
                                .onSubmit { Task { await save() } }

                            Rectangle()
                                .fill(underlineColor)
                                .frame(height: 1.5)

                            HStack(spacing: 6) {
                                Text(hint)
                                    .font(KrezusFont.caption)
                                    .foregroundStyle(hintColor)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 8)
                                Text(t("username.counter", trimmed.count))
                                    .font(KrezusFont.caption)
                                    .foregroundStyle(KrezusColor.fg3).tabularNumbers()
                            }
                        }
                    }

                    Text(t("username.note"))
                        .font(KrezusFont.caption).foregroundStyle(KrezusColor.fg3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)

                    KrzPrimaryButton(title: profile.isSaving ? t("common.saving") : t("common.save")) {
                        Task { await save() }
                    }
                    .opacity(canSave ? 1 : 0.45)
                    .disabled(!canSave)
                    .padding(.top, KrezusSpacing.s2)
                }
                .padding(.horizontal, KrezusSpacing.s4)
                .padding(.bottom, 60)
            }
            .scrollIndicators(.hidden)
        }
        .krezusNavBar(t("profile.edit_username"))
        .onAppear {
            draft = profile.username
            isFocused = true
        }
    }

    private var initialPreview: String {
        String(trimmed.first.map(String.init)?.uppercased() ?? profile.initial)
    }

    private var hint: String {
        if let error { return error }
        if let validationError, !trimmed.isEmpty {
            return validationError.localizedDescription
        }
        return t("username.hint")
    }

    private var hintColor: Color {
        (error != nil || (validationError != nil && !trimmed.isEmpty))
            ? KrezusColor.down : KrezusColor.fg3
    }

    private var underlineColor: Color {
        if error != nil || (validationError != nil && !trimmed.isEmpty) { return KrezusColor.down }
        return isFocused ? KrezusColor.brandFill : KrezusColor.border
    }

    private func save() async {
        guard canSave else { return }
        do {
            try await profile.updateUsername(draft, userID: auth.userID)
            error = nil
            router.showToast(t("username.toast_saved"))
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
