import SwiftUI

/// « Acheter » — montants prédéfinis, curseur libre, parts obtenues, solde, puis
/// écran de confirmation. Le montant est plafonné par le solde disponible.
struct BuyScreen: View {
    let symbol: String
    @Environment(TradingStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss

    @State private var amountEuros: Double = 50
    @State private var done = false
    @State private var error: String?
    /// L'ordre part vers le serveur : le bouton doit dire qu'il travaille, et
    /// surtout refuser un second appui qui passerait un deuxième achat.
    @State private var isSubmitting = false

    private var stock: StockInfo? { store.stock(symbol) }
    private var maxEuros: Double { Double(store.cashCents) / 100 }
    private var amountCents: Int { Int((amountEuros * 100).rounded()) }
    private var sharesGet: Double { (stock.map { amountEuros / $0.price }) ?? 0 }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: done ? "" : t("buy.title", stock?.name ?? "")) { dismiss() }
            if done {
                successView
            } else if let s = stock {
                form(s)
            }
        }
        .background(KrezusColor.surface.ignoresSafeArea())
        // Un cours frais avant de saisir un montant : le moteur refuse une
        // cotation de plus de quinze minutes.
        .task { await store.refreshQuotes([symbol]) }
    }

    private func form(_ s: StockInfo) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(t("buy.price_per_share", Money.euros(s.price)))
                    .font(KrezusFont.bodyMd).foregroundStyle(KrezusColor.fg3)

                Text(t("buy.how_much")).font(KrezusFont.cardTitle).foregroundStyle(KrezusColor.ink)

                HStack(spacing: 8) {
                    ForEach([25.0, 50.0, 100.0, 250.0], id: \.self) { amount in
                        let disabled = amount > maxEuros
                        Button { amountEuros = amount } label: {
                            Text(Money.eurosShort(amount))
                                .font(KrezusFont.display(14, .bold))
                                .foregroundStyle(amountEuros == amount ? .white : KrezusColor.brandText)
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                                .background(amountEuros == amount ? KrezusColor.brandFill : KrezusColor.tint)
                                .clipShape(RoundedRectangle(cornerRadius: KrezusRadius.sm, style: .continuous))
                                .opacity(disabled ? 0.4 : 1)
                        }
                        .buttonStyle(.plain).disabled(disabled)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(t("buy.amount")).font(KrezusFont.bodySm).foregroundStyle(KrezusColor.fg3)
                        Spacer()
                        Text(Money.euros(amountEuros)).font(KrezusFont.display(16, .bold))
                            .foregroundStyle(KrezusColor.ink).tabularNumbers()
                    }
                    Slider(value: $amountEuros, in: 1...max(1, maxEuros), step: 1)
                        .tint(KrezusColor.brandFill)
                    HStack {
                        Text(Money.eurosShort(1)).font(KrezusFont.caption).foregroundStyle(KrezusColor.fg3)
                        Spacer()
                        Text(Money.euros(maxEuros)).font(KrezusFont.caption).foregroundStyle(KrezusColor.fg3)
                    }
                }
                .padding(14)
                .background(KrezusColor.tint)
                .clipShape(RoundedRectangle(cornerRadius: KrezusRadius.md, style: .continuous))

                VStack(spacing: 8) {
                    summaryRow(t("buy.you_get"), Money.shares(sharesGet))
                    summaryRow(t("buy.paper_balance"), Money.euros(cents: store.cashCents))
                }

                if let error {
                    Text(error).font(KrezusFont.caption).foregroundStyle(KrezusColor.down)
                }

                Text(t("buy.execution_note"))
                    .font(KrezusFont.caption).foregroundStyle(KrezusColor.fg3)

                KrzPrimaryButton(title: isSubmitting
                                 ? t("common.sending")
                                 : t("buy.cta", Money.euros(amountEuros))) {
                    Task { await confirm() }
                }
                .opacity(isSubmitting ? 0.6 : 1)
                .disabled(isSubmitting)
            }
            .padding(.horizontal, KrezusSpacing.s4)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
    }

    private var successView: some View {
        VStack(spacing: 16) {
            Spacer()
            Circle().fill(KrezusColor.upBg).frame(width: 84, height: 84)
                .overlay(Image(systemName: "checkmark").font(.system(size: 38, weight: .heavy))
                    .foregroundStyle(KrezusColor.up))
            Text(t("buy.success_title")).font(KrezusFont.display(22, .heavy)).foregroundStyle(KrezusColor.ink)
            Text(t("buy.success_body", stock?.name ?? ""))
                .font(KrezusFont.bodyMd).foregroundStyle(KrezusColor.fg3)
                .multilineTextAlignment(.center)
            Spacer()
            KrzPrimaryButton(title: t("buy.success_cta")) { dismiss() }
                .padding(.horizontal, KrezusSpacing.s4)
        }
        .padding(.bottom, 32)
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(KrezusFont.bodySm).foregroundStyle(KrezusColor.fg2)
            Spacer()
            Text(value).font(KrezusFont.body(13, .bold)).foregroundStyle(KrezusColor.ink).tabularNumbers()
        }
    }

    private func confirm() async {
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await store.buy(symbol: symbol, amountCents: amountCents)
            withAnimation { done = true }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// En-tête de feuille modale : titre + bouton fermer.
struct SheetHeader: View {
    let title: String
    let onClose: () -> Void
    var body: some View {
        ZStack {
            Text(title).font(KrezusFont.display(17, .bold)).foregroundStyle(KrezusColor.ink)
            HStack {
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold)).foregroundStyle(KrezusColor.fg3)
                        .frame(width: 32, height: 32)
                        .background(KrezusColor.tint).clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(t("common.close"))
            }
        }
        .padding(.horizontal, KrezusSpacing.s4)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }
}
