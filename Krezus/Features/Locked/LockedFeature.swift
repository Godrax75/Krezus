import SwiftUI

/// Les dix écrans que le prototype garde **visibles mais verrouillés**.
///
/// Ils appartiennent tous au mode réel (carte, KYC, fiscalité, virements) et
/// n'ont aucun sens tant qu'aucun partenariat courtier n'est signé. Les
/// masquer donnerait une app amputée ; les câbler à moitié promettrait une
/// fonctionnalité inexistante. Le design tranche : on les montre, on les
/// explique, et on assume le « bientôt disponible ».
enum LockedFeature: String, CaseIterable, Identifiable, Hashable, Sendable {
    case kyc
    case activateCard
    case reveal
    case giftBox
    case recurringInvestment
    case myCards
    case referral
    case taxDocuments
    case bankDetails
    case realCode

    var id: String { rawValue }

    var title: String { t("locked.\(rawValue).title") }

    var icon: String {
        switch self {
        case .kyc:                 return "person.text.rectangle.fill"
        case .activateCard:        return "creditcard.and.123"
        case .reveal:              return "wand.and.stars"
        case .giftBox:             return "gift.fill"
        case .recurringInvestment: return "calendar.badge.clock"
        case .myCards:             return "creditcard.fill"
        case .referral:            return "person.2.fill"
        case .taxDocuments:        return "doc.text.fill"
        case .bankDetails:         return "building.columns.fill"
        case .realCode:            return "key.fill"
        }
    }

    /// Ce que fera l'écran une fois ouvert — annoncé au futur, jamais au présent.
    var promise: String { t("locked.\(rawValue).promise") }

    /// Pourquoi c'est verrouillé — la raison est réglementaire, pas technique,
    /// et le dire évite de passer pour une app inachevée. Trois écrans ont leur
    /// propre motif ; les autres partagent celui du mode réel.
    var reason: String {
        switch self {
        case .taxDocuments, .reveal, .referral:
            return t("locked.\(rawValue).reason")
        default:
            return t("locked.reason.real_mode")
        }
    }
}

/// Écran vitrine : la fonctionnalité est présentée, jamais simulée.
struct ComingSoonScreen: View {
    let feature: LockedFeature

    @Environment(Router.self) private var router

    var body: some View {
        ZStack {
            KrezusColor.bg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: KrezusSpacing.s4) {
                    Image(systemName: feature.icon)
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(KrezusColor.brandText)
                        .frame(width: 76, height: 76)
                        .background(KrezusColor.tintStrong)
                        .clipShape(Circle())
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 26, height: 26)
                                .background(KrezusColor.amber500)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(KrezusColor.bg, lineWidth: 2.5))
                        }
                        .padding(.top, KrezusSpacing.s5)

                    Text(feature.title)
                        .font(KrezusFont.display(21, .heavy))
                        .foregroundStyle(KrezusColor.ink)
                        .multilineTextAlignment(.center)

                    Text(t("locked.badge"))
                        .font(KrezusFont.body(11.5, .bold)).tracking(0.6)
                        .foregroundStyle(KrezusColor.amberText)
                        .padding(.horizontal, 11).padding(.vertical, 5)
                        .background(KrezusColor.amberTint)
                        .clipShape(Capsule())

                    KrzCard {
                        VStack(alignment: .leading, spacing: KrezusSpacing.s3) {
                            Text(feature.promise)
                                .font(KrezusFont.bodyMd).foregroundStyle(KrezusColor.fg2)
                                .fixedSize(horizontal: false, vertical: true)

                            Divider().overlay(KrezusColor.divider)

                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "info.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(KrezusColor.fg4)
                                Text(feature.reason)
                                    .font(KrezusFont.caption).foregroundStyle(KrezusColor.fg3)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(.top, KrezusSpacing.s2)

                    KrzPrimaryButton(title: t("locked.continue_paper")) {
                        router.popToRoot()
                    }
                    .padding(.top, KrezusSpacing.s2)

                    KrzPaperMoneyNote()
                }
                .padding(.horizontal, KrezusSpacing.s4)
                .padding(.bottom, 60)
            }
            .scrollIndicators(.hidden)
        }
        .krezusNavBar(feature.title)
    }
}
