import SwiftUI

/// « Vendre » — pourcentages prédéfinis (25/50/100 %), parts et produit de la
/// vente, puis confirmation. La vente crédite le solde papier.
struct SellScreen: View {
    let symbol: String
    @Environment(TradingStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss

    @State private var pct = 50
    @State private var done = false
    @State private var error: String?
    @State private var isSubmitting = false

    private var stock: StockInfo? { store.stock(symbol) }
    private var ownedQty: Double { store.quantity(symbol) }
    private var sellQty: Double { ownedQty * Double(pct) / 100 }
    private var sellValue: Double { (stock.map { sellQty * $0.price }) ?? 0 }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: done ? "" : t("sell.title", stock?.name ?? "")) { dismiss() }
            if done {
                successView
            } else if let s = stock {
                form(s)
            }
        }
        .background(KrezusColor.surface.ignoresSafeArea())
    }

    private func form(_ s: StockInfo) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(t("sell.position", Money.shares(ownedQty), Money.euros(store.positionValue(symbol))))
                    .font(KrezusFont.bodyMd).foregroundStyle(KrezusColor.fg3)

                Text(t("sell.how_much")).font(KrezusFont.cardTitle).foregroundStyle(KrezusColor.ink)

                HStack(spacing: 8) {
                    ForEach([25, 50, 100], id: \.self) { value in
                        Button { pct = value } label: {
                            Text(value == 100 ? t("sell.all") : t("format.percent_int", value))
                                .font(KrezusFont.display(14, .bold))
                                .foregroundStyle(pct == value ? .white : KrezusColor.brandText)
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                                .background(pct == value ? KrezusColor.brandFill : KrezusColor.tint)
                                .clipShape(RoundedRectangle(cornerRadius: KrezusRadius.sm, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }

                VStack(spacing: 8) {
                    summaryRow(t("sell.shares_sold"), Money.shares(sellQty))
                    summaryRow(t("sell.you_receive"), Money.euros(sellValue))
                }
                .padding(14)
                .background(KrezusColor.tint)
                .clipShape(RoundedRectangle(cornerRadius: KrezusRadius.md, style: .continuous))

                if let error {
                    Text(error).font(KrezusFont.caption).foregroundStyle(KrezusColor.down)
                }

                Text(t("sell.execution_note"))
                    .font(KrezusFont.caption).foregroundStyle(KrezusColor.fg3)

                KrzPrimaryButton(title: isSubmitting
                                 ? t("common.sending")
                                 : t("sell.cta", pct == 100
                                    ? t("sell.all_lowercase")
                                    : t("format.percent_int", pct))) {
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
            Text(t("sell.success_title")).font(KrezusFont.display(22, .heavy)).foregroundStyle(KrezusColor.ink)
            Text(t("sell.success_body"))
                .font(KrezusFont.bodyMd).foregroundStyle(KrezusColor.fg3)
                .multilineTextAlignment(.center)
            Spacer()
            KrzPrimaryButton(title: t("sell.success_cta")) { dismiss() }
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
            try await store.sell(symbol: symbol, pct: pct)
            withAnimation { done = true }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
