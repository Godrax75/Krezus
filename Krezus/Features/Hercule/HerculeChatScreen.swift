import SwiftUI

/// Chat avec Hercule. Ouvert par le FAB depuis n'importe quel onglet.
struct HerculeChatScreen: View {
    @Environment(HerculeStore.self) private var hercule
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss

    @State private var draft = ""
    /// Le paywall se présente depuis le chat, pas via le `Router` : le chat est
    /// lui-même une feuille, et pousser sur la pile de navigation racine
    /// empilerait un écran invisible derrière elle.
    @State private var showPaywall = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        ZStack {
            KrezusColor.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                conversation
                composer
            }
        }
        .sheet(isPresented: $showPaywall) { PaywallScreen() }
    }

    // MARK: En-tête

    private var header: some View {
        HStack(spacing: 11) {
            HerculeAvatar(size: 48)

            VStack(alignment: .leading, spacing: 1) {
                Text("Hercule").font(KrezusFont.display(17, .heavy))
                    .foregroundStyle(KrezusColor.ink)
                Text(quotaLabel).font(KrezusFont.caption).foregroundStyle(KrezusColor.fg3)
            }

            Spacer()

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(KrezusColor.fg3)
                    .frame(width: 34, height: 34)
                    .background(KrezusColor.tint).clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(t("common.close"))
        }
        .padding(.horizontal, KrezusSpacing.s4)
        .padding(.vertical, KrezusSpacing.s3)
        .background(KrezusColor.surface)
        .krezusShadow(KrezusShadow.level1)
    }

    private var quotaLabel: String {
        if hercule.isPremium { return t("hercule.quota.premium") }
        let left = hercule.remaining ?? 0
        guard left > 0 else { return t("hercule.quota.exhausted") }
        return t(L10n.plural(Double(left), one: "hercule.quota.left.one",
                             other: "hercule.quota.left.other"), left)
    }

    // MARK: Conversation

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(hercule.messages) { message in
                        bubble(message).id(message.id)
                    }
                    if hercule.isThinking { thinkingBubble.id("thinking") }
                    if !hercule.isPremium && (hercule.remaining ?? 0) == 0 { paywallCard }
                    disclaimer
                }
                .padding(.horizontal, KrezusSpacing.s4)
                .padding(.vertical, KrezusSpacing.s4)
            }
            .scrollIndicators(.hidden)
            .onChange(of: hercule.messages.count) {
                withAnimation { proxy.scrollTo(hercule.messages.last?.id, anchor: .bottom) }
            }
        }
    }

    private func bubble(_ message: HerculeMessage) -> some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }

            Text(message.text)
                .font(KrezusFont.body(14))
                .foregroundStyle(message.role == .user ? .white : KrezusColor.ink)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14).padding(.vertical, 11)
                .background(bubbleBackground(message))
                .clipShape(RoundedRectangle(cornerRadius: KrezusRadius.md, style: .continuous))

            if message.role == .hercule { Spacer(minLength: 40) }
        }
    }

    private func bubbleBackground(_ message: HerculeMessage) -> Color {
        switch (message.role, message.refused) {
        case (.user, _):        return KrezusColor.brandFill
        // Un refus se distingue visuellement sans ressembler à une erreur :
        // c'est une réponse volontaire, pas une panne.
        case (.hercule, true):  return KrezusColor.amberSoft
        case (.hercule, false): return KrezusColor.surface
        }
    }

    private var thinkingBubble: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                Circle().fill(KrezusColor.fg4).frame(width: 6, height: 6)
                    .opacity(0.4)
                    .animation(
                        .easeInOut(duration: 0.6).repeatForever().delay(Double(index) * 0.15),
                        value: hercule.isThinking)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 13)
        .background(KrezusColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: KrezusRadius.md, style: .continuous))
    }

    private var paywallCard: some View {
        KrzCard(shadow: KrezusShadow.level2) {
            VStack(alignment: .leading, spacing: 9) {
                Text(t("hercule.paywall_card.title", HerculeStore.freeDailyQuota))
                    .font(KrezusFont.cardTitle).foregroundStyle(KrezusColor.ink)
                Text(t("hercule.paywall_card.body"))
                    .font(KrezusFont.bodyMd).foregroundStyle(KrezusColor.fg3)
                    .fixedSize(horizontal: false, vertical: true)
                KrzPrimaryButton(title: t("hercule.paywall_card.cta", HerculeStore.subscriptionPrice)) {
                    showPaywall = true
                }
            }
        }
    }

    private var disclaimer: some View {
        Text(t("hercule.disclaimer"))
            .font(KrezusFont.caption).foregroundStyle(KrezusColor.fg3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 6)
    }

    // MARK: Saisie

    private var composer: some View {
        HStack(spacing: 9) {
            TextField(t("hercule.input_placeholder"), text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .font(KrezusFont.bodyMd)
                .focused($inputFocused)
                .padding(.horizontal, 14).padding(.vertical, 11)
                .background(KrezusColor.tint)
                .clipShape(RoundedRectangle(cornerRadius: KrezusRadius.md, style: .continuous))
                .disabled(!hercule.canSend)

            Button { submit() } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(KrezusColor.brandFill).clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(t("hercule.send"))
            .opacity(canSubmit ? 1 : 0.4)
            .disabled(!canSubmit)
        }
        .padding(.horizontal, KrezusSpacing.s4)
        .padding(.top, KrezusSpacing.s3)
        .padding(.bottom, KrezusSpacing.s4)
        .background(KrezusColor.surface)
    }

    private var canSubmit: Bool {
        hercule.canSend && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() {
        guard canSubmit else { return }
        hercule.send(draft)
        draft = ""
        inputFocused = false
    }
}
