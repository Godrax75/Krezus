import SwiftUI

/// « Aide » — questions fréquentes, contact et mentions légales.
///
/// Les avertissements du prototype (`t_stock_disc`, `t_chat_disc`,
/// `t_prof_disclaimer`) sont regroupés ici plutôt que dispersés : ce sont eux
/// qui tiennent la frontière entre pédagogie et conseil en investissement.
struct HelpScreen: View {
    @Environment(\.openURL) private var openURL

    @State private var expanded: Set<Int> = []

    /// Une entrée de FAQ n'est qu'une paire de clés : le texte vit dans le
    /// catalogue, avec le reste de l'interface.
    private struct FAQ: Identifiable {
        let id: Int
        var question: String { t("help.faq.\(id).q") }
        var answer: String { t("help.faq.\(id).a") }
    }

    private static let faqs: [FAQ] = (0...6).map(FAQ.init(id:))

    var body: some View {
        ZStack {
            KrezusColor.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: KrezusSpacing.s3) {
                    KrzGroupLabel(text: t("help.group.faq"))
                    KrzSettingsGroup {
                        ForEach(Array(Self.faqs.enumerated()), id: \.element.id) { index, faq in
                            faqRow(faq)
                            if index < Self.faqs.count - 1 { KrzRowDivider() }
                        }
                    }

                    KrzGroupLabel(text: t("help.group.contact"))
                    KrzSettingsGroup {
                        KrzSettingsRow(icon: "envelope.fill", title: t("help.contact_support"),
                                       subtitle: "bonjour@krezus.app") {
                            if let url = URL(string: "mailto:bonjour@krezus.app") { openURL(url) }
                        }
                        KrzRowDivider()
                        KrzSettingsRow(icon: "exclamationmark.bubble.fill",
                                       title: t("help.report_issue"),
                                       subtitle: t("help.report_issue_detail")) {
                            if let url = URL(string: "mailto:bonjour@krezus.app?subject=Signalement") {
                                openURL(url)
                            }
                        }
                    }

                    KrzGroupLabel(text: t("help.group.legal"))
                    disclaimerCard

                    KrzPaperMoneyNote().padding(.top, KrezusSpacing.s4)
                }
                .padding(.horizontal, KrezusSpacing.s4)
                .padding(.bottom, 60)
            }
            .scrollIndicators(.hidden)
        }
        .krezusNavBar(t("profile.group.support"))
    }

    private func faqRow(_ faq: FAQ) -> some View {
        let isOpen = expanded.contains(faq.id)

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.22)) {
                    if isOpen { expanded.remove(faq.id) } else { expanded.insert(faq.id) }
                }
            } label: {
                HStack(spacing: KrezusSpacing.s3) {
                    Text(faq.question)
                        .font(KrezusFont.display(14, .semibold))
                        .foregroundStyle(KrezusColor.ink)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(KrezusColor.fg4)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                }
                .padding(.horizontal, KrezusSpacing.s4)
                .padding(.vertical, 13)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(isOpen ? t("a11y.collapse") : t("a11y.expand"))

            if isOpen {
                Text(faq.answer)
                    .font(KrezusFont.bodySm).foregroundStyle(KrezusColor.fg2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, KrezusSpacing.s4)
                    .padding(.bottom, 14)
            }
        }
    }

    private var disclaimerCard: some View {
        KrzCard {
            VStack(alignment: .leading, spacing: KrezusSpacing.s3) {
                disclaimer(t("help.legal.educational"))
                disclaimer(t("help.legal.oracle"))
                disclaimer(t("help.legal.quotes"))

                Divider().overlay(KrezusColor.divider)

                Text("Krezus · Paris, France")
                    .font(KrezusFont.caption).foregroundStyle(KrezusColor.fg3)
            }
        }
    }

    private func disclaimer(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11)).foregroundStyle(KrezusColor.amberText)
                .padding(.top, 2)
            Text(text)
                .font(KrezusFont.caption).foregroundStyle(KrezusColor.fg2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
