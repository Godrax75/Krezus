import SwiftUI

/// Porte d'entrée des visiteurs sans session : deux chemins nettement séparés,
/// créer un compte ou retrouver le sien.
///
/// L'ancien écran proposait les mêmes boutons Apple et Google à tout le monde :
/// rien ne disait si l'on s'inscrivait ou si l'on se connectait, et sans
/// compte Apple ni Google, on ne pouvait pas entrer du tout. Chacun des deux
/// chemins propose désormais les trois moyens — Apple, Google, e-mail.
///
/// L'écran reprend l'univers de l'onboarding qui le précède : la mascotte sur
/// le bleu profond, le bouton blanc. Les formulaires, eux, reviennent au fond
/// clair de l'app, plus confortable pour taper.
struct SignInScreen: View {
    @State private var path: [AccountFormScreen.Mode] = []

    var body: some View {
        NavigationStack(path: $path) {
            landing
                .navigationDestination(for: AccountFormScreen.Mode.self) { mode in
                    AccountFormScreen(mode: mode) { other in
                        // Bascule « déjà un compte ? » : on remplace l'écran
                        // plutôt que d'empiler, sans quoi le retour ferait
                        // alterner les deux formulaires à l'infini.
                        path = [other]
                    }
                }
        }
    }

    private var landing: some View {
        ZStack(alignment: .bottom) {
            KrezusColor.navyDeep.ignoresSafeArea()

            Image("onboarding-1")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea()
                .overlay {
                    LinearGradient(
                        stops: [
                            .init(color: KrezusColor.navyDeep.opacity(0.35), location: 0.0),
                            .init(color: .clear, location: 0.18),
                            .init(color: .clear, location: 0.38),
                            .init(color: KrezusColor.navyDeep.opacity(0.85), location: 0.58),
                            .init(color: KrezusColor.navyDeep, location: 0.70),
                        ],
                        startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                }
                .accessibilityHidden(true)

            VStack(spacing: KrezusSpacing.s3) {
                Text("Krezus")
                    .font(KrezusFont.display(38, .heavy))
                    .foregroundStyle(.white)
                Text(t("signin.tagline"))
                    .font(KrezusFont.bodyMd)
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.bottom, KrezusSpacing.s5)

                NavigationLink(value: AccountFormScreen.Mode.signUp) {
                    Text(t("signin.create_account"))
                        .font(KrezusFont.display(15.5, .bold))
                        .foregroundStyle(KrezusColor.navyDeep)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(colors: [.white, Color(hex: 0xDFE4F0)],
                                           startPoint: .top, endPoint: .bottom))
                        .clipShape(RoundedRectangle(cornerRadius: KrezusRadius.md, style: .continuous))
                        .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
                }
                .buttonStyle(.plain)

                NavigationLink(value: AccountFormScreen.Mode.signIn) {
                    Text(t("signin.have_account"))
                        .font(KrezusFont.display(15.5, .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .overlay(
                            RoundedRectangle(cornerRadius: KrezusRadius.md, style: .continuous)
                                .stroke(.white.opacity(0.45), lineWidth: 1.2))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Text(t("signin.paper_note"))
                    .font(KrezusFont.caption)
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.top, KrezusSpacing.s2)
            }
            .padding(.horizontal, KrezusSpacing.s6)
            .padding(.bottom, KrezusSpacing.s6)
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}
