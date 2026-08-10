import SwiftUI

/// « Switch de mode » — la feuille ouverte par la pastille Virtuel / Réel de
/// l'en-tête.
///
/// Le mode réel n'est pas une bascule cachée : il suppose un partenariat
/// courtier sous licence MiFID II, un parcours KYC et une conservation de
/// titres. Tant que ce n'est pas signé, la ligne reste verrouillée et le dit.
struct ModeSwitchSheet: View {
    @Environment(AppState.self) private var app
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                KrezusColor.bg.ignoresSafeArea()

                VStack(alignment: .leading, spacing: KrezusSpacing.s3) {
                    Text(t("mode.sheet.title"))
                        .font(KrezusFont.display(21, .heavy))
                        .foregroundStyle(KrezusColor.ink)
                        .padding(.top, KrezusSpacing.s4)

                    Text(t("mode.sheet.intro"))
                        .font(KrezusFont.bodyMd).foregroundStyle(KrezusColor.fg3)
                        .fixedSize(horizontal: false, vertical: true)

                    modeRow(
                        icon: "gamecontroller.fill",
                        title: t("mode.paper"),
                        subtitle: t("mode.paper.detail", Money.euros(1000)),
                        isActive: app.mode == .paper,
                        isLocked: false) {
                            app.mode = .paper
                            dismiss()
                        }

                    modeRow(
                        icon: "banknote.fill",
                        title: t("mode.real"),
                        subtitle: t("mode.real.detail"),
                        isActive: false,
                        isLocked: true) {
                            dismiss()
                            router.push(.locked(.realCode))
                        }

                    KrzCard {
                        HStack(alignment: .top, spacing: 9) {
                            Image(systemName: "info.circle.fill")
                                .font(.system(size: 12)).foregroundStyle(KrezusColor.fg4)
                                .padding(.top, 1)
                            Text(t("mode.sheet.legal"))
                                .font(KrezusFont.caption).foregroundStyle(KrezusColor.fg3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Spacer()
                }
                .padding(.horizontal, KrezusSpacing.s4)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(t("common.close")) { dismiss() }
                        .font(KrezusFont.body(13.5, .semibold))
                        .foregroundStyle(KrezusColor.brandText)
                }
            }
            .navigationTitle(t("profile.row.mode"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.height(480)])
        .presentationDragIndicator(.visible)
    }

    private func modeRow(icon: String, title: String, subtitle: String,
                         isActive: Bool, isLocked: Bool,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: KrezusSpacing.s3) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isLocked ? KrezusColor.fg4 : KrezusColor.brandText)
                    .frame(width: 42, height: 42)
                    .background(isLocked ? KrezusColor.tint : KrezusColor.tintStrong)
                    .clipShape(RoundedRectangle(cornerRadius: KrezusRadius.sm, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(KrezusFont.display(16, .bold))
                            .foregroundStyle(isLocked ? KrezusColor.fg3 : KrezusColor.ink)
                        if isActive {
                            Text(t("mode.active"))
                                .font(KrezusFont.body(9, .bold)).tracking(0.6)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6).padding(.vertical, 2.5)
                                .background(KrezusColor.up).clipShape(Capsule())
                        }
                    }
                    Text(subtitle)
                        .font(KrezusFont.caption).foregroundStyle(KrezusColor.fg3)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Image(systemName: isLocked ? "lock.fill" : (isActive ? "checkmark.circle.fill" : "circle"))
                    .font(.system(size: 17))
                    .foregroundStyle(isLocked ? KrezusColor.fg4 : KrezusColor.up)
            }
            .padding(KrezusSpacing.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(KrezusColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: KrezusRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: KrezusRadius.lg, style: .continuous)
                    .stroke(isActive ? KrezusColor.brandFill : Color.clear, lineWidth: 1.5))
            .krezusShadow(KrezusShadow.level1)
        }
        .buttonStyle(.plain)
    }
}
