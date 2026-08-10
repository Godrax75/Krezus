import SwiftUI
import AuthenticationServices

/// Écran de connexion — Sign in with Apple + Google, comme « Création de compte »
/// du design. Affiché uniquement quand l'app est configurée (Supabase) et
/// qu'aucune session n'est active.
struct SignInScreen: View {
    @Environment(AuthService.self) private var auth
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Image("krezus-mascot").resizable().scaledToFit().frame(width: 72, height: 72)
            Text("Krezus")
                .font(KrezusFont.display(34, .heavy))
                .foregroundStyle(KrezusColor.brandText)
                .padding(.top, 12)
            Text(t("signin.tagline"))
                .font(KrezusFont.bodyMd).foregroundStyle(KrezusColor.fg3)
                .padding(.top, 4)

            Spacer()

            VStack(spacing: 12) {
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    handleApple(result)
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 52)
                .clipShape(RoundedRectangle(cornerRadius: KrezusRadius.md, style: .continuous))

                if !AppConfig.googleClientID.isEmpty {
                    Button {
                        Task { await signInGoogle() }
                    } label: {
                        HStack {
                            Image(systemName: "globe")
                            Text(t("signin.google"))
                        }
                        .font(KrezusFont.display(15.5, .semibold))
                        .foregroundStyle(KrezusColor.ink)
                        .frame(maxWidth: .infinity).frame(height: 52)
                        .background(KrezusColor.surface)
                        .clipShape(RoundedRectangle(cornerRadius: KrezusRadius.md, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: KrezusRadius.md)
                            .stroke(KrezusColor.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }

                if let error {
                    Text(error).font(KrezusFont.caption).foregroundStyle(KrezusColor.down)
                }
            }
            .padding(.horizontal, KrezusSpacing.s6)

            Text(t("signin.paper_note"))
                .font(KrezusFont.caption).foregroundStyle(KrezusColor.fg3)
                .padding(.top, 20).padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(KrezusColor.bg.ignoresSafeArea())
    }

    private func handleApple(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential
            else { return }
            Task {
                do { try await auth.signInWithApple(credential) }
                catch { self.error = error.localizedDescription }
            }
        case .failure(let err):
            // L'annulation par l'utilisateur n'est pas une erreur à afficher.
            if (err as? ASAuthorizationError)?.code != .canceled {
                self.error = err.localizedDescription
            }
        }
    }

    private func signInGoogle() async {
        do { try await auth.signInWithGoogle() }
        catch { self.error = error.localizedDescription }
    }
}
