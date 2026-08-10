import SwiftUI

/// Hercule Premium — 5,99 €/mois.
///
/// Aucun lien de paiement sortant : tout passe par StoreKit (guideline 3.1.1).
/// Le bouton de restauration et les liens CGU/confidentialité sont exigés par
/// la revue App Store pour tout écran d'abonnement.
struct PaywallScreen: View {
    @Environment(SubscriptionService.self) private var store
    @Environment(HerculeStore.self) private var hercule
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss

    @State private var message: String?

    var body: some View {
        ZStack {
            KrezusColor.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    hero
                    benefits
                    if let message {
                        Text(message)
                            .font(KrezusFont.bodyMd).foregroundStyle(KrezusColor.amberText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    purchaseSection
                    legal
                }
                .padding(.horizontal, KrezusSpacing.s4)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .navigationBarBackButtonHidden(true)
        .safeAreaInset(edge: .top) { navBar }
        .task { await store.load() }
    }

    private var navBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(KrezusColor.fg3)
                    .frame(width: 36, height: 36)
                    .background(KrezusColor.surface).clipShape(Circle())
                    .krezusShadow(KrezusShadow.level1)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(t("common.close"))
            Spacer()
        }
        .padding(.horizontal, KrezusSpacing.s4)
        .padding(.vertical, KrezusSpacing.s2)
        .background(KrezusColor.bg)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image("krezus-mascot").resizable().scaledToFit()
                .frame(width: 54, height: 54)
                .padding(12)
                .background(KrezusColor.gradientAmber)
                .clipShape(Circle())
                .krezusShadow(KrezusShadow.brand)

            Text(t("paywall.title"))
                .font(KrezusFont.display(28, .heavy)).foregroundStyle(KrezusColor.ink)
            Text(t("paywall.subtitle"))
                .font(KrezusFont.body(15)).foregroundStyle(KrezusColor.fg2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
    }

    private var benefits: some View {
        KrzCard(shadow: KrezusShadow.level2) {
            VStack(alignment: .leading, spacing: 14) {
                benefit("infinity", t("paywall.benefit.unlimited.title"),
                        t("paywall.benefit.unlimited.detail", HerculeStore.freeDailyQuota))
                benefit("book.fill", t("paywall.benefit.lessons.title"),
                        t("paywall.benefit.lessons.detail"))
                benefit("chart.pie.fill", t("paywall.benefit.analysis.title"),
                        t("paywall.benefit.analysis.detail"))
            }
        }
    }

    private func benefit(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15)).foregroundStyle(KrezusColor.amberText)
                .frame(width: 32, height: 32)
                .background(KrezusColor.amberTint).clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(KrezusFont.body(14, .semibold)).foregroundStyle(KrezusColor.ink)
                Text(detail).font(KrezusFont.caption).foregroundStyle(KrezusColor.fg3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var purchaseSection: some View {
        VStack(spacing: 10) {
            if store.isUnavailable {
                // Un bouton d'achat qui ne peut rien acheter est pire qu'une
                // explication : on dit ce qui manque.
                KrzCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(t("paywall.unavailable.title"))
                            .font(KrezusFont.body(13.5, .semibold)).foregroundStyle(KrezusColor.ink)
                        Text(store.loadError ?? t("paywall.unavailable.body"))
                            .font(KrezusFont.caption).foregroundStyle(KrezusColor.fg3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                KrzPrimaryButton(title: store.isPurchasing
                                 ? t("paywall.purchasing")
                                 : t("paywall.subscribe_cta", store.displayPrice)) {
                    Task { await buy() }
                }
                .opacity(store.isPurchasing ? 0.6 : 1)
                .disabled(store.isPurchasing)
            }

            Button { Task { await store.restore() } } label: {
                Text(t("paywall.restore"))
                    .font(KrezusFont.body(13, .semibold)).foregroundStyle(KrezusColor.brandText)
            }
            .buttonStyle(.plain)
        }
    }

    private var legal: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(t("paywall.legal"))
                .font(KrezusFont.caption).foregroundStyle(KrezusColor.fg3)
                .fixedSize(horizontal: false, vertical: true)

            // Les adresses viennent du catalogue de traductions : une faute de
            // frappe côté traduction ne doit pas faire tomber l'écran de
            // paiement. Le lien disparaît, le reste des mentions légales tient.
            HStack(spacing: 14) {
                if let terms = URL(string: t("legal.terms_url")) {
                    Link(t("legal.terms"), destination: terms)
                }
                if let privacy = URL(string: t("legal.privacy_url")) {
                    Link(t("legal.privacy"), destination: privacy)
                }
            }
            .font(KrezusFont.caption).foregroundStyle(KrezusColor.brandText)

            Text(t("paywall.paper_note"))
                .font(KrezusFont.caption).foregroundStyle(KrezusColor.fg3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
    }

    private func buy() async {
        message = nil
        switch await store.purchase() {
        case .success:
            hercule.unlockPremium()
            router.showToast(t("paywall.toast_welcome"))
            dismiss()
        case .cancelled:
            break                                   // rien à dire : l'utilisateur a annulé
        case .pending:
            message = t("paywall.pending")
        case .unavailable:
            message = t("paywall.unavailable.short")
        case .failed(let reason):
            message = reason
        }
    }
}
