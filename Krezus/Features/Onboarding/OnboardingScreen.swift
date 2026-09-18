import SwiftUI

/// Onboarding en cinq écrans illustrés.
///
/// Il précède la connexion : on montre ce qu'est Krezus avant de demander une
/// identité. Chaque page est une illustration qui occupe tout l'écran, encoche
/// comprise, avec le nom, le mot-repère, le titre et l'accroche composés par
/// l'app par-dessus.
///
/// Le texte est redessiné plutôt que peint dans l'image : il suit ainsi la
/// langue de l'appareil, la taille de texte du système et la police du design
/// system, ce qu'une maquette aplatie ne saurait faire. Les illustrations ne
/// portent donc que le décor.
///
/// Deux dégradés tiennent la lisibilité : l'un descend du haut, où se pose le
/// texte, l'autre remonte du bas, sous le bouton. Ils reprennent le bleu
/// profond de la marque, celui-là même vers lequel les illustrations
/// s'assombrissent.
///
/// Le mode est fixé à « papier » à la sortie : c'est le seul ouvert en v1.
struct OnboardingScreen: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(AppState.self) private var app

    @State private var page = 0

    /// Une étape ne porte que son rang : l'image suit la nomenclature du
    /// catalogue, les textes viennent de la table de chaînes.
    private struct Step: Identifiable {
        let id: Int
        var image: String { "onboarding-\(id + 1)" }
        var badge: String { t("onboarding.\(id).badge") }
        var title: String { t("onboarding.\(id).title") }
        var body: String { t("onboarding.\(id).body") }
    }

    private static let steps: [Step] = (0..<5).map(Step.init(id:))

    /// Index de la dernière page du carrousel.
    private static var lastPage: Int { steps.count - 1 }

    /// Sortie unique : le mode papier est le seul ouvert en v1.
    private func finish() {
        app.mode = .paper
        settings.completeOnboarding()
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            KrezusColor.navyDeep.ignoresSafeArea()

            TabView(selection: $page) {
                ForEach(Self.steps) { step in
                    stepView(step).tag(step.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            footer
                .padding(.horizontal, KrezusSpacing.s6)
                .padding(.bottom, KrezusSpacing.s6)
        }
        .overlay(alignment: .topTrailing) { skipButton }
    }

    // MARK: Passer

    private var skipButton: some View {
        Group {
            if page < Self.lastPage {
                Button(t("onboarding.skip")) { finish() }
                    .font(KrezusFont.body(13, .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .buttonStyle(.plain)
                    .padding(.horizontal, KrezusSpacing.s5)
                    .padding(.top, KrezusSpacing.s2)
            }
        }
    }

    // MARK: Étapes

    private func stepView(_ step: Step) -> some View {
        Image(step.image)
            .resizable()
            // Ajusté, pas rempli : les illustrations sont en 9:16 et l'écran
            // d'un iPhone récent est plus étroit. Les remplir coûtait un
            // neuvième de largeur de chaque côté — assez pour couper un
            // personnage. Les bandes qui restent tombent dans les voiles, donc
            // ne se voient pas.
            .scaledToFit()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(KrezusColor.navyDeep)
            .ignoresSafeArea()
            .overlay { veils }
            .overlay(alignment: .top) { caption(step) }
    }

    /// Les deux voiles. Celui du haut couvre le tiers où se pose le texte, puis
    /// s'efface avant les personnages ; celui du bas ne mord que le dallage,
    /// sous le bouton. Sans eux, un titre blanc passerait sur un ciel clair.
    private var veils: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: KrezusColor.navyDeep, location: 0.0),
                    .init(color: KrezusColor.navyDeep.opacity(0.97), location: 0.20),
                    .init(color: KrezusColor.navyDeep.opacity(0.75), location: 0.31),
                    .init(color: .clear, location: 0.44),
                ],
                startPoint: .top, endPoint: .bottom)

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.62),
                    .init(color: KrezusColor.navyDeep.opacity(0.80), location: 0.80),
                    // Opaque dès 90 % : l'illustration ajustée s'arrête vers
                    // cette hauteur, et sa lisière doit tomber dans un bleu plein.
                    .init(color: KrezusColor.navyDeep, location: 0.90),
                ],
                startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    /// Nom, mot-repère, titre et accroche — la composition des maquettes,
    /// rejouée avec les fontes du design system.
    private func caption(_ step: Step) -> some View {
        VStack(spacing: KrezusSpacing.s2) {
            Text("Krezus")
                .font(KrezusFont.display(26, .heavy))
                .foregroundStyle(.white)

            Text(step.badge.uppercased())
                .font(KrezusFont.body(11, .semibold))
                .tracking(2.2)
                .foregroundStyle(KrezusColor.gold)
                .padding(.horizontal, 18)
                .padding(.vertical, 7)
                .overlay(
                    Capsule().stroke(KrezusColor.gold.opacity(0.75), lineWidth: 1.2))

            Text(step.title)
                .font(KrezusFont.display(31, .heavy))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineSpacing(-2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, KrezusSpacing.s2)

            Text(step.body)
                .font(KrezusFont.bodyMd)
                .foregroundStyle(.white.opacity(0.88))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                // Bornée : sur un iPhone large, l'accroche tiendrait sur une
                // seule ligne d'un bord à l'autre, là où la maquette la casse
                // en deux.
                .frame(maxWidth: 300)
        }
        .padding(.horizontal, KrezusSpacing.s5)
        .padding(.top, KrezusSpacing.s2)
        .accessibilityElement(children: .combine)
    }

    // MARK: Pied

    private var pageDots: some View {
        HStack(spacing: 7) {
            ForEach(0..<Self.steps.count, id: \.self) { index in
                Capsule()
                    .fill(index == page ? Color.white : Color.white.opacity(0.35))
                    .frame(width: index == page ? 20 : 7, height: 7)
                    .animation(.snappy(duration: 0.2), value: page)
            }
        }
        .accessibilityHidden(true)
    }

    /// Le bouton du design system est un aplat bleu : posé sur le voile bleu
    /// profond, il s'y fondait au point de disparaître. Celui-ci passe au
    /// blanc, adouci d'un dégradé vers un gris bleuté pour ne pas trancher
    /// comme une découpe.
    private func ctaButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(KrezusFont.display(15.5, .bold))
                .foregroundStyle(KrezusColor.navyDeep)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [.white, Color(hex: 0xDFE4F0)],
                        startPoint: .top, endPoint: .bottom))
                .clipShape(RoundedRectangle(cornerRadius: KrezusRadius.md, style: .continuous))
                .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        VStack(spacing: KrezusSpacing.s3) {
            pageDots

            ctaButton(page < Self.lastPage ? t("common.continue") : t("onboarding.start")) {
                if page < Self.lastPage {
                    withAnimation(.snappy) { page += 1 }
                } else {
                    finish()
                }
            }

            // La mention du design system se lit en gris sur fond clair ; ici
            // le fond est une image assombrie, d'où la reprise en blanc.
            HStack(spacing: 7) {
                Image(systemName: "info.circle.fill").font(.system(size: 11))
                Text(t("disclaimer.paper_money"))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(KrezusFont.caption)
            .foregroundStyle(.white.opacity(0.65))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
        }
    }
}
