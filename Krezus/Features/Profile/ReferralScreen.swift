import SwiftUI

/// « Parrainer un ami » : son code, de quoi le partager, ce qu'il a rapporté,
/// et — les sept premiers jours — la saisie du code d'un ami.
///
/// La récompense est en XP, pour le parrain comme pour le filleul. Le mois
/// d'Hercule Premium offert viendra quand l'abonnement sera en vente : il
/// passera par les codes d'offre de l'App Store, seul moyen qu'Apple admette
/// pour offrir un contenu payant.
struct ReferralScreen: View {
    @Environment(Router.self) private var router
    @Environment(LearningStore.self) private var learning

    @State private var status: ReferralRepository.Status?
    @State private var loadFailed = false
    @State private var friendCode = ""
    @State private var isRedeeming = false
    @State private var redeemError: String?
    @State private var redeemedMessage: String?

    private let repository = ReferralRepository()

    /// XP gagnés par chacun, et nombre de filleuls récompensés au plus : les
    /// mêmes constantes que `redeem_referral_code`.
    static let rewardXP = 100
    static let rewardedMax = 10

    /// En démo, sans serveur, un code d'exemple pour voir l'écran.
    private var code: String? {
        AppConfig.isConfigured ? status?.code : "KRZ4Q7"
    }

    private var shareMessage: String {
        t("referral.share_message", code ?? "", AppConfig.appStoreURL.absoluteString)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KrezusSpacing.s4) {
                intro
                codeCard
                if AppConfig.isConfigured, let status { statsRow(status) }
                if let status, status.canRedeem || redeemedMessage != nil { redeemCard }
                if let parent = status?.referredBy, redeemedMessage == nil {
                    Label(t("referral.referred_by", parent), systemImage: "person.2.fill")
                        .font(KrezusFont.bodySm).foregroundStyle(KrezusColor.fg3)
                }
                Text(t("referral.premium_soon"))
                    .font(KrezusFont.caption).foregroundStyle(KrezusColor.fg3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, KrezusSpacing.s4)
            .padding(.top, KrezusSpacing.s2)
            .padding(.bottom, 60)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(KrezusColor.bg.ignoresSafeArea())
        .krezusNavBar(t("referral.title"))
        .task { await load() }
    }

    // MARK: Sections

    private var intro: some View {
        HStack(alignment: .top, spacing: KrezusSpacing.s3) {
            HerculeAvatar(size: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(t("referral.headline"))
                    .font(KrezusFont.display(20, .heavy)).foregroundStyle(KrezusColor.ink)
                Text(t("referral.explainer", Self.rewardXP, Self.rewardedMax))
                    .font(KrezusFont.bodySm).foregroundStyle(KrezusColor.fg3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var codeCard: some View {
        KrzCard(shadow: KrezusShadow.level2) {
            VStack(spacing: KrezusSpacing.s3) {
                Text(t("referral.your_code"))
                    .font(KrezusFont.body(11, .bold)).tracking(0.8)
                    .foregroundStyle(KrezusColor.fg3)

                Group {
                    if let code {
                        Text(code)
                            .font(KrezusFont.display(36, .heavy))
                            .tracking(6)
                            .foregroundStyle(KrezusColor.brandText)
                            .textSelection(.enabled)
                            .accessibilityLabel(code.map(String.init).joined(separator: " "))
                    } else if loadFailed {
                        Text(t("referral.load_error"))
                            .font(KrezusFont.bodySm).foregroundStyle(KrezusColor.fg3)
                    } else {
                        ProgressView().frame(height: 44)
                    }
                }

                HStack(spacing: KrezusSpacing.s2) {
                    Button {
                        UIPasteboard.general.string = code
                        router.showToast(t("referral.copied"))
                    } label: {
                        Label(t("referral.copy"), systemImage: "doc.on.doc")
                            .font(KrezusFont.body(14, .semibold))
                            .foregroundStyle(KrezusColor.brandText)
                            .frame(maxWidth: .infinity).padding(.vertical, 13)
                            .background(KrezusColor.tintStrong)
                            .clipShape(RoundedRectangle(cornerRadius: KrezusRadius.md, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    ShareLink(item: shareMessage) {
                        Label(t("referral.share"), systemImage: "square.and.arrow.up")
                            .font(KrezusFont.body(14, .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 13)
                            .background(KrezusColor.brandFill)
                            .clipShape(RoundedRectangle(cornerRadius: KrezusRadius.md, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .disabled(code == nil)
                .opacity(code == nil ? 0.5 : 1)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func statsRow(_ status: ReferralRepository.Status) -> some View {
        HStack(spacing: KrezusSpacing.s3) {
            stat(value: "\(status.referredCount)", label: t("referral.stat.friends"))
            stat(value: t("format.xp", status.xpEarned), label: t("referral.stat.xp"))
        }
    }

    private func stat(value: String, label: String) -> some View {
        KrzCard {
            VStack(spacing: 4) {
                Text(value).font(KrezusFont.display(22, .heavy)).foregroundStyle(KrezusColor.ink)
                    .tabularNumbers()
                Text(label).font(KrezusFont.caption).foregroundStyle(KrezusColor.fg3)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var redeemCard: some View {
        KrzCard {
            VStack(alignment: .leading, spacing: KrezusSpacing.s3) {
                Text(t("referral.redeem.title"))
                    .font(KrezusFont.cardTitle).foregroundStyle(KrezusColor.ink)

                if let redeemedMessage {
                    Label(redeemedMessage, systemImage: "checkmark.seal.fill")
                        .font(KrezusFont.bodySm).foregroundStyle(KrezusColor.up)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(t("referral.redeem.body"))
                        .font(KrezusFont.bodySm).foregroundStyle(KrezusColor.fg3)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: KrezusSpacing.s2) {
                        TextField(t("referral.redeem.placeholder"), text: $friendCode)
                            .font(KrezusFont.display(17, .bold))
                            .tracking(3)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .onSubmit { Task { await redeem() } }
                            .onChange(of: friendCode) { _, value in
                                // Six caractères utiles : on ignore espaces et tirets
                                // qu'un copier-coller aurait pu apporter.
                                let cleaned = String(value.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(6))
                                if cleaned != value { friendCode = cleaned }
                            }
                            .padding(.horizontal, KrezusSpacing.s4)
                            .frame(height: 48)
                            .background(KrezusColor.tint)
                            .clipShape(RoundedRectangle(cornerRadius: KrezusRadius.md, style: .continuous))

                        Button { Task { await redeem() } } label: {
                            Group {
                                if isRedeeming { ProgressView().tint(.white) }
                                else { Text(t("referral.redeem.cta")) }
                            }
                            .font(KrezusFont.body(14, .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 96, height: 48)
                            .background(KrezusColor.brandFill)
                            .clipShape(RoundedRectangle(cornerRadius: KrezusRadius.md, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(friendCode.count != 6 || isRedeeming)
                        .opacity(friendCode.count == 6 ? 1 : 0.5)
                    }

                    if let redeemError {
                        Text(redeemError).font(KrezusFont.caption).foregroundStyle(KrezusColor.down)
                    }
                }
            }
        }
    }

    // MARK: Actions

    private func load() async {
        guard AppConfig.isConfigured else { return }
        do {
            status = try await repository.status()
            loadFailed = false
        } catch {
            loadFailed = status == nil
        }
    }

    private func redeem() async {
        guard friendCode.count == 6, !isRedeeming else { return }
        isRedeeming = true
        redeemError = nil
        defer { isRedeeming = false }
        do {
            let result = try await repository.redeem(code: friendCode)
            redeemedMessage = result.referrerUsername.map { t("referral.redeem.success_named", result.xpAwarded, $0) }
                ?? t("referral.redeem.success", result.xpAwarded)
            await learning.reload()
            await load()
        } catch {
            redeemError = error.localizedDescription
        }
    }
}
