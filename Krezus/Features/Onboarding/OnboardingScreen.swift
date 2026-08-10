import SwiftUI

/// Onboarding en trois étapes, suivi du choix du mode.
///
/// Il précède la connexion : on explique ce qu'est Krezus avant de demander
/// une identité. Les illustrations du prototype ne sont pas encore embarquées
/// dans l'`Assets.xcassets` ; on tient le même parti que le reste du design
/// system — symboles système teintés — plutôt que de bloquer sur les images.
struct OnboardingScreen: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(AppState.self) private var app

    @State private var page = 0

    /// Une étape ne porte que son icône : titre et corps viennent du catalogue.
    private struct Step: Identifiable {
        let id: Int
        let icon: String
        var title: String { t("onboarding.\(id).title") }
        var body: String { t("onboarding.\(id).body") }
    }

    private static let steps: [Step] = [
        .init(id: 0, icon: "eurosign.circle.fill"),
        .init(id: 1, icon: "book.fill"),
        .init(id: 2, icon: "trophy.fill"),
    ]

    var body: some View {
        ZStack {
            KrezusColor.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                TabView(selection: $page) {
                    ForEach(Self.steps) { step in
                        stepView(step).tag(step.id)
                    }
                    modeChoice.tag(Self.steps.count)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                pageDots
                    .padding(.bottom, KrezusSpacing.s4)

                footer
                    .padding(.horizontal, KrezusSpacing.s6)
                    .padding(.bottom, KrezusSpacing.s6)
            }
        }
    }

    // MARK: En-tête

    private var header: some View {
        HStack {
            Image("krezus-mascot").resizable().scaledToFit().frame(width: 28, height: 28)
            Text("Krezus")
                .font(KrezusFont.display(18, .heavy))
                .foregroundStyle(KrezusColor.brandText)
            Spacer()
            if page < Self.steps.count {
                Button(t("onboarding.skip")) { page = Self.steps.count }
                    .font(KrezusFont.body(13, .semibold))
                    .foregroundStyle(KrezusColor.fg3)
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, KrezusSpacing.s5)
        .padding(.top, KrezusSpacing.s3)
    }

    // MARK: Étapes

    private func stepView(_ step: Step) -> some View {
        VStack(spacing: KrezusSpacing.s4) {
            Spacer()

            Image(systemName: step.icon)
                .font(.system(size: 46, weight: .semibold))
                .foregroundStyle(KrezusColor.brandText)
                .frame(width: 132, height: 132)
                .background(KrezusColor.tintStrong)
                .clipShape(Circle())

            Text(step.title)
                .font(KrezusFont.display(25, .heavy))
                .foregroundStyle(KrezusColor.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text(step.body)
                .font(KrezusFont.bodyMd).foregroundStyle(KrezusColor.fg3)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(.horizontal, KrezusSpacing.s6)
    }

    // MARK: Choix du mode

    private var modeChoice: some View {
        VStack(spacing: KrezusSpacing.s3) {
            Spacer()

            Text(t("onboarding.mode.title"))
                .font(KrezusFont.display(25, .heavy))
                .foregroundStyle(KrezusColor.ink)

            Text(t("onboarding.mode.subtitle"))
                .font(KrezusFont.bodyMd).foregroundStyle(KrezusColor.fg3)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, KrezusSpacing.s2)

            modeCard(
                icon: "gamecontroller.fill",
                title: t("mode.paper"),
                subtitle: t("onboarding.mode.paper_detail", Money.euros(1000)),
                isSelected: true,
                isLocked: false)

            modeCard(
                icon: "banknote.fill",
                title: t("mode.real"),
                subtitle: t("onboarding.mode.real_detail"),
                isSelected: false,
                isLocked: true)

            Spacer()
        }
        .padding(.horizontal, KrezusSpacing.s6)
    }

    private func modeCard(icon: String, title: String, subtitle: String,
                          isSelected: Bool, isLocked: Bool) -> some View {
        HStack(spacing: KrezusSpacing.s3) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isLocked ? KrezusColor.fg4 : KrezusColor.brandText)
                .frame(width: 42, height: 42)
                .background(isLocked ? KrezusColor.tint : KrezusColor.tintStrong)
                .clipShape(RoundedRectangle(cornerRadius: KrezusRadius.sm, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(KrezusFont.display(16, .bold))
                    .foregroundStyle(isLocked ? KrezusColor.fg3 : KrezusColor.ink)
                Text(subtitle)
                    .font(KrezusFont.caption).foregroundStyle(KrezusColor.fg3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Image(systemName: isLocked ? "lock.fill" : (isSelected ? "checkmark.circle.fill" : "circle"))
                .font(.system(size: 17))
                .foregroundStyle(isLocked ? KrezusColor.fg4 : KrezusColor.up)
        }
        .padding(KrezusSpacing.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KrezusColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: KrezusRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: KrezusRadius.lg, style: .continuous)
                .stroke(isSelected ? KrezusColor.brandFill : Color.clear, lineWidth: 1.5))
        .krezusShadow(isSelected ? KrezusShadow.level2 : KrezusShadow.level1)
    }

    // MARK: Pied

    private var pageDots: some View {
        HStack(spacing: 7) {
            ForEach(0...Self.steps.count, id: \.self) { index in
                Capsule()
                    .fill(index == page ? KrezusColor.brandFill : KrezusColor.border)
                    .frame(width: index == page ? 20 : 7, height: 7)
                    .animation(.snappy(duration: 0.2), value: page)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: KrezusSpacing.s3) {
            KrzPrimaryButton(title: page < Self.steps.count ? t("common.continue") : t("onboarding.start")) {
                if page < Self.steps.count {
                    withAnimation(.snappy) { page += 1 }
                } else {
                    app.mode = .paper
                    settings.completeOnboarding()
                }
            }
            KrzPaperMoneyNote()
        }
    }
}
