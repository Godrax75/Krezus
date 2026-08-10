import SwiftUI

/// Quiz d'une leçon : une question, trois options, puis l'explication.
///
/// L'explication (`why`) s'affiche que la réponse soit juste ou fausse — se
/// tromper doit apprendre quelque chose, pas seulement sanctionner. La leçon
/// est validée dans les deux cas ; seule la mission « quiz du jour » exige
/// une bonne réponse.
struct QuizScreen: View {
    let position: Int

    @Environment(LearningStore.self) private var learning
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss

    @State private var selected: Int?
    @State private var validated = false
    @State private var xpGained = 0

    private var lesson: AcademyLesson? { learning.lesson(at: position) }
    private var quiz: AcademyLesson.Quiz? { lesson?.quiz }
    private var isCorrect: Bool { selected == quiz?.a }

    var body: some View {
        ZStack {
            KrezusColor.bg.ignoresSafeArea()

            if let quiz {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        question(quiz)
                        options(quiz)
                        if validated { feedback(quiz) }
                    }
                    .padding(.horizontal, KrezusSpacing.s4)
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
                .safeAreaInset(edge: .bottom) { bottomBar }
            } else {
                Text(t("quiz.none"))
                    .font(KrezusFont.bodyMd).foregroundStyle(KrezusColor.fg3)
            }
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
            Text(t("quiz.nav_title")).font(KrezusFont.display(15, .bold)).foregroundStyle(KrezusColor.ink)
            Spacer()
            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.horizontal, KrezusSpacing.s4)
        .padding(.vertical, KrezusSpacing.s2)
        .background(KrezusColor.bg)
    }

    private func question(_ quiz: AcademyLesson.Quiz) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(lesson?.title ?? "")
                .font(KrezusFont.body(11.5, .bold)).tracking(0.6)
                .foregroundStyle(KrezusColor.amberText)
            Text(quiz.q)
                .font(KrezusFont.display(20, .heavy)).foregroundStyle(KrezusColor.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    private func options(_ quiz: AcademyLesson.Quiz) -> some View {
        VStack(spacing: 10) {
            ForEach(Array(quiz.opts.enumerated()), id: \.offset) { index, text in
                Button {
                    guard !validated else { return }
                    selected = index
                } label: {
                    HStack(spacing: 11) {
                        ZStack {
                            Circle().stroke(borderColor(index), lineWidth: 1.8)
                            if let icon = iconName(index) {
                                Image(systemName: icon)
                                    .font(.system(size: 12, weight: .heavy))
                                    .foregroundStyle(borderColor(index))
                            }
                        }
                        .frame(width: 22, height: 22)

                        Text(text)
                            .font(KrezusFont.bodyMd).foregroundStyle(KrezusColor.ink)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(KrezusSpacing.s3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(background(index))
                    .clipShape(RoundedRectangle(cornerRadius: KrezusRadius.md, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: KrezusRadius.md, style: .continuous)
                            .stroke(borderColor(index), lineWidth: selected == index || isRevealed(index) ? 1.5 : 0))
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Après validation, la bonne réponse est toujours révélée — même si
    /// l'utilisateur a choisi autre chose.
    private func isRevealed(_ index: Int) -> Bool {
        validated && index == quiz?.a
    }

    private func borderColor(_ index: Int) -> Color {
        guard validated else {
            return selected == index ? KrezusColor.brandFill : KrezusColor.border
        }
        if index == quiz?.a { return KrezusColor.up }
        if index == selected { return KrezusColor.down }
        return KrezusColor.border
    }

    private func background(_ index: Int) -> Color {
        guard validated else {
            return selected == index ? KrezusColor.tintStrong : KrezusColor.surface
        }
        if index == quiz?.a { return KrezusColor.upBg }
        if index == selected { return KrezusColor.downBg }
        return KrezusColor.surface
    }

    private func iconName(_ index: Int) -> String? {
        guard validated else { return selected == index ? "circle.fill" : nil }
        if index == quiz?.a { return "checkmark" }
        if index == selected { return "xmark" }
        return nil
    }

    private func feedback(_ quiz: AcademyLesson.Quiz) -> some View {
        KrzCard(shadow: KrezusShadow.level2) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: isCorrect ? "checkmark.seal.fill" : "lightbulb.fill")
                        .foregroundStyle(isCorrect ? KrezusColor.up : KrezusColor.amberText)
                    Text(isCorrect ? t("quiz.correct") : t("quiz.incorrect"))
                        .font(KrezusFont.display(15, .bold))
                        .foregroundStyle(isCorrect ? KrezusColor.upDeep : KrezusColor.ink)
                    Spacer()
                    if xpGained > 0 {
                        Text(t("common.xp_badge", xpGained))
                            .font(KrezusFont.body(12, .bold))
                            .foregroundStyle(KrezusColor.amberText)
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background(KrezusColor.amberTint).clipShape(Capsule())
                    }
                }
                Text(quiz.why)
                    .font(KrezusFont.bodyMd).foregroundStyle(KrezusColor.fg2)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 0) {
            if validated {
                KrzPrimaryButton(title: t("common.continue")) {
                    router.path.removeLast(min(2, router.path.count))
                }
            } else {
                KrzPrimaryButton(title: t("common.validate")) { validate() }
                    .opacity(selected == nil ? 0.45 : 1)
                    .disabled(selected == nil)
            }
        }
        .padding(.horizontal, KrezusSpacing.s4)
        .padding(.top, KrezusSpacing.s3)
        .padding(.bottom, KrezusSpacing.s4)
        .background(KrezusColor.bg)
    }

    private func validate() {
        guard selected != nil else { return }
        validated = true
        xpGained = (try? learning.complete(lesson: position, quizCorrect: isCorrect)) ?? 0
    }
}
