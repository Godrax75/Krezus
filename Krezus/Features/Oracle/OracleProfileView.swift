import SwiftUI

/// Profil investisseur — questionnaire puis archétype et « ADN ».
///
/// Ce profil oriente le ton pédagogique. Ce n'est **pas** un profil de risque
/// réglementaire (MiFID) : il ne conditionne l'accès à aucun produit et ne doit
/// jamais être présenté comme une évaluation d'aptitude à investir.
struct OracleProfileView: View {
    @Environment(OracleStore.self) private var oracle

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let archetype = oracle.archetype, oracle.isComplete {
                resultCard(archetype)
                restartButton
            } else {
                intro
                ForEach(Array(oracle.questions.enumerated()), id: \.element.id) { index, question in
                    questionCard(index: index, question: question)
                }
            }
        }
    }

    private var intro: some View {
        Text(t("investor_profile.intro"))
            .font(KrezusFont.bodySm).foregroundStyle(KrezusColor.fg3)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func questionCard(index: Int, question: InvestorQuestion) -> some View {
        KrzCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("\(index + 1)")
                        .font(KrezusFont.display(11.5, .bold)).foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(KrezusColor.brandFill).clipShape(Circle())
                    Text(question.question)
                        .font(KrezusFont.body(14, .semibold)).foregroundStyle(KrezusColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ForEach(Array(question.options.enumerated()), id: \.offset) { optionIndex, option in
                    let selected = oracle.answers[question.id] == optionIndex
                    Button {
                        oracle.select(question: question.id, option: optionIndex)
                    } label: {
                        HStack(spacing: 10) {
                            ZStack {
                                Circle().stroke(selected ? KrezusColor.brandFill : KrezusColor.border,
                                                lineWidth: 1.6)
                                if selected {
                                    Circle().fill(KrezusColor.brandFill).padding(5)
                                }
                            }
                            .frame(width: 20, height: 20)

                            Text(option.label)
                                .font(KrezusFont.bodyMd).foregroundStyle(KrezusColor.ink)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func resultCard(_ archetype: InvestorArchetype) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Text(archetype.emoji).font(.system(size: 38))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t("investor_profile.your_profile"))
                            .font(KrezusFont.body(10, .bold)).tracking(0.8)
                            .foregroundStyle(.white.opacity(0.65))
                        Text(archetype.name)
                            .font(KrezusFont.display(22, .heavy)).foregroundStyle(.white)
                    }
                }
                Text(archetype.summary)
                    .font(KrezusFont.bodyMd).foregroundStyle(.white.opacity(0.88))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(KrezusColor.gradientNavy)
            .clipShape(RoundedRectangle(cornerRadius: KrezusRadius.lg, style: .continuous))
            .krezusShadow(KrezusShadow.brand)

            KrzCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text(t("investor_profile.dna_title"))
                        .font(KrezusFont.cardTitle).foregroundStyle(KrezusColor.ink)

                    ForEach(archetype.dna) { trait in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(trait.label)
                                    .font(KrezusFont.body(12.5, .semibold))
                                    .foregroundStyle(KrezusColor.fg2)
                                Spacer()
                                Text("\(trait.value)")
                                    .font(KrezusFont.body(12.5, .bold))
                                    .foregroundStyle(KrezusColor.brandText).tabularNumbers()
                            }
                            KrzProgressBar(value: Double(trait.value) / 100, height: 7)
                        }
                    }

                    Text(t("investor_profile.disclaimer"))
                        .font(KrezusFont.caption).foregroundStyle(KrezusColor.fg3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
            }
        }
    }

    private var restartButton: some View {
        Button { oracle.reset() } label: {
            Text(t("investor_profile.restart"))
                .font(KrezusFont.body(13, .semibold))
                .foregroundStyle(KrezusColor.brandText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(KrezusColor.tintStrong)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
