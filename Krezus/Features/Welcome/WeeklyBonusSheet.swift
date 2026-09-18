import SwiftUI

/// Le versement de la semaine vient d'arriver : la gerbe, le montant qui
/// défile, et la date du suivant — pour donner envie de revenir.
struct WeeklyBonusSheet: View {
    let cents: Int
    let nextDate: Date
    let onClose: () -> Void

    @State private var fired = false
    @State private var shown: Double = 0

    var body: some View {
        ZStack {
            WelcomeBackground()
            VStack(spacing: 18) {
                Spacer(minLength: 12)
                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [KrezusColor.gold.opacity(0.4), .clear],
                                             center: .center, startRadius: 5, endRadius: 120))
                        .frame(width: 240, height: 240)
                    CelebrationBurst(fired: fired)
                    VStack(spacing: 2) {
                        Text("💶").font(.system(size: 54))
                        HStack(spacing: 0) {
                            Text("+").font(KrezusFont.display(56, .heavy)).foregroundStyle(.white)
                            CountingEuros(cents: shown, font: KrezusFont.display(56, .heavy))
                        }
                    }
                }
                .frame(height: 200)

                Text(t("weekly_bonus.title"))
                    .font(KrezusFont.display(24, .heavy))
                    .foregroundStyle(KrezusColor.gold)
                Text(t("weekly_bonus.body", WeeklyBonus.label(for: nextDate)))
                    .font(KrezusFont.body(15.5, .medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, KrezusSpacing.s4)

                Spacer(minLength: 8)
                WelcomeButton(title: t("weekly_bonus.cta"), action: onClose)
            }
            .padding(.horizontal, KrezusSpacing.s5)
            .padding(.bottom, KrezusSpacing.s5)
        }
        .preferredColorScheme(.dark)
        .sensoryFeedback(.success, trigger: fired)
        .task {
            try? await Task.sleep(for: .milliseconds(250))
            withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { fired = true }
            withAnimation(.easeOut(duration: 1.2)) { shown = Double(cents) }
        }
        .accessibilityElement(children: .combine)
    }
}
