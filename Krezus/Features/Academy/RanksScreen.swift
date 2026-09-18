import SwiftUI

/// « Tous les rangs » — les six paliers romains, du Plébéien à l'Empereur.
/// Le rang courant est mis en avant ; les suivants indiquent l'XP qui manque.
struct RanksScreen: View {
    @Environment(LearningStore.self) private var learning
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            KrezusColor.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(t("ranks.intro"))
                        .font(KrezusFont.bodyMd).foregroundStyle(KrezusColor.fg3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)

                    ForEach(learning.ranks) { rank in
                        rankRow(rank)
                    }
                }
                .padding(.horizontal, KrezusSpacing.s4)
                .padding(.bottom, 60)
            }
            .scrollIndicators(.hidden)
        }
        .navigationBarBackButtonHidden(true)
        .safeAreaInset(edge: .top) { navBar }
    }

    private var navBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(KrezusColor.brandText)
                    .frame(width: 36, height: 36)
                    .background(KrezusColor.surface).clipShape(Circle())
                    .krezusShadow(KrezusShadow.level1)
            }
            .buttonStyle(.plain)
            Spacer()
            Text(t("ranks.nav_title"))
                .font(KrezusFont.display(15, .bold)).foregroundStyle(KrezusColor.ink)
            Spacer()
            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.horizontal, KrezusSpacing.s4)
        .padding(.vertical, KrezusSpacing.s2)
        .background(KrezusColor.bg)
    }

    private func rankRow(_ rank: AcademyRank) -> some View {
        let isCurrent = rank.level == learning.rankLevel
        let isReached = learning.xp >= rank.minXp

        return KrzCard(shadow: isCurrent ? KrezusShadow.brand : KrezusShadow.level1) {
            HStack(spacing: 13) {
                // Buste du personnage, posé dans une pastille : calé en bas, il
                // en déborde par les cornes. Un rang non atteint passe en
                // gris — il se devine sans se montrer encore.
                Image(rank.imageAsset)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                    .saturation(isReached ? 1 : 0)
                    .opacity(isReached ? 1 : 0.45)
                    .background(
                        Circle()
                            .fill(isCurrent ? KrezusColor.amberTint : KrezusColor.tint)
                            .frame(width: 58, height: 58)
                            .offset(y: 3))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text(rank.name)
                            .font(KrezusFont.display(16, .bold))
                            .foregroundStyle(isReached ? KrezusColor.ink : KrezusColor.fg3)
                        if isCurrent {
                            Text(t("ranks.current"))
                                .font(KrezusFont.body(9.5, .bold)).tracking(0.6)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7).padding(.vertical, 2.5)
                                .background(KrezusColor.brandFill).clipShape(Capsule())
                        }
                    }
                    Text(rangeLabel(rank))
                        .font(KrezusFont.caption).foregroundStyle(KrezusColor.fg3)
                        .tabularNumbers()
                }

                Spacer(minLength: 0)

                if isReached {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18)).foregroundStyle(KrezusColor.up)
                } else {
                    Text(t("ranks.xp_missing", rank.minXp - learning.xp))
                        .font(KrezusFont.body(11.5, .semibold))
                        .foregroundStyle(KrezusColor.fg3).tabularNumbers()
                }
            }
        }
    }

    private func rangeLabel(_ rank: AcademyRank) -> String {
        if let max = rank.maxXp { return t("ranks.xp_range", rank.minXp, max) }
        return t("ranks.xp_and_above", rank.minXp)
    }
}
