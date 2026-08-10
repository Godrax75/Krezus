import SwiftUI

/// Une leçon : paragraphes pédagogiques puis exemples concrets, avant le quiz.
/// Les exemples du prototype citent le portefeuille de l'utilisateur (« vos
/// 0,45 action Nvidia ») — c'est ce qui rend la leçon vivante, on les garde tels quels.
struct LessonScreen: View {
    let position: Int

    @Environment(LearningStore.self) private var learning
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss

    private var lesson: AcademyLesson? { learning.lesson(at: position) }

    var body: some View {
        ZStack {
            KrezusColor.bg.ignoresSafeArea()

            if let lesson {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header(lesson)
                        paragraphs(lesson)
                        if !lesson.examples.isEmpty { examples(lesson) }
                        actionButton(lesson)
                    }
                    .padding(.horizontal, KrezusSpacing.s4)
                    .padding(.bottom, 60)
                }
                .scrollIndicators(.hidden)
            } else {
                Text(t("lesson.not_found")).font(KrezusFont.bodyMd)
                    .foregroundStyle(KrezusColor.fg3)
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
            Text(t("lesson.nav_title", position))
                .font(KrezusFont.display(15, .bold)).foregroundStyle(KrezusColor.ink)
            Spacer()
            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.horizontal, KrezusSpacing.s4)
        .padding(.vertical, KrezusSpacing.s2)
        .background(KrezusColor.bg)
    }

    private func header(_ lesson: AcademyLesson) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(lesson.title)
                .font(KrezusFont.display(24, .heavy)).foregroundStyle(KrezusColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                if let duration = lesson.duration {
                    Label(duration, systemImage: "clock")
                        .font(KrezusFont.body(12)).foregroundStyle(KrezusColor.fg3)
                }
                if learning.isCompleted(lesson) {
                    Label(t("lesson.completed"), systemImage: "checkmark.seal.fill")
                        .font(KrezusFont.body(12, .semibold)).foregroundStyle(KrezusColor.up)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    private func paragraphs(_ lesson: AcademyLesson) -> some View {
        KrzCard(shadow: KrezusShadow.level2) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(lesson.paragraphs.enumerated()), id: \.offset) { _, text in
                    Text(text)
                        .font(KrezusFont.body(14.5))
                        .foregroundStyle(KrezusColor.fg2)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func examples(_ lesson: AcademyLesson) -> some View {
        KrzCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(t("lesson.concretely"))
                    .font(KrezusFont.body(10, .bold)).tracking(0.8)
                    .foregroundStyle(KrezusColor.amberText)

                ForEach(Array(lesson.examples.enumerated()), id: \.offset) { _, text in
                    HStack(alignment: .top, spacing: 9) {
                        Circle().fill(KrezusColor.amber500)
                            .frame(width: 5, height: 5).padding(.top, 7)
                        Text(text)
                            .font(KrezusFont.bodyMd).foregroundStyle(KrezusColor.fg2)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func actionButton(_ lesson: AcademyLesson) -> some View {
        if lesson.quiz != nil {
            KrzPrimaryButton(title: t("lesson.go_to_quiz")) {
                router.push(.quiz(lesson.position))
            }
        } else {
            // Une leçon sans quiz se valide directement : elle compte pour la
            // mission du jour, mais pas pour celle du quiz.
            KrzPrimaryButton(title: learning.isCompleted(lesson) ? t("common.go_back") : t("lesson.finish")) {
                if learning.isCompleted(lesson) {
                    dismiss()
                } else if let gained = try? learning.complete(lesson: lesson.position, quizCorrect: nil) {
                    router.showToast(gained > 0 ? t("lesson.toast_xp", gained) : t("lesson.toast"))
                    dismiss()
                }
            }
        }
    }
}
