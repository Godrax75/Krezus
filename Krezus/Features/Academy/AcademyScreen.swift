import SwiftUI

/// Onglet Academy — carte de rang, série, et les 27 leçons.
/// Les 4 premières sont gratuites ; les suivantes portent le cadenas Premium.
struct AcademyScreen: View {
    @Environment(LearningStore.self) private var learning
    @Environment(Router.self) private var router

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                KrzSectionTitle(systemImage: "book.fill", title: "Krezus Academy")
                rankCard
                statsRow
                lessonsCard
            }
            .padding(.horizontal, KrezusSpacing.s4)
            .padding(.top, 6)
            .padding(.bottom, 140)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: Rang

    private var rankCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                RankBadge(rank: learning.currentRank, size: 58, disc: .white.opacity(0.14))
                VStack(alignment: .leading, spacing: 2) {
                    Text(t("academy.your_rank"))
                        .font(KrezusFont.body(10, .bold)).tracking(0.8)
                        .foregroundStyle(.white.opacity(0.65))
                    Text(learning.currentRank?.name ?? "")
                        .font(KrezusFont.display(22, .heavy)).foregroundStyle(.white)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(learning.xp)")
                        .font(KrezusFont.display(24, .heavy)).foregroundStyle(.white)
                        .tabularNumbers()
                    Text("XP").font(KrezusFont.body(11, .bold))
                        .foregroundStyle(.white.opacity(0.65))
                }
            }

            KrzProgressBar(value: learning.rankProgress, height: 8,
                           fill: KrezusColor.amber500, track: .white.opacity(0.18))

            HStack {
                if let remaining = learning.xpToNextRank, let next = learning.nextRank {
                    Text(t("academy.xp_to_next", remaining, next.name))
                        .font(KrezusFont.body(12)).foregroundStyle(.white.opacity(0.8))
                } else {
                    Text(t("academy.max_rank"))
                        .font(KrezusFont.body(12)).foregroundStyle(.white.opacity(0.8))
                }
                Spacer()
                Button { router.push(.ranks) } label: {
                    Text(t("academy.all_ranks"))
                        .font(KrezusFont.body(12, .semibold))
                        .foregroundStyle(KrezusColor.amber500)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KrezusColor.gradientNavy)
        .clipShape(RoundedRectangle(cornerRadius: KrezusRadius.lg, style: .continuous))
        .krezusShadow(KrezusShadow.brand)
    }

    // MARK: Série et progression

    private var statsRow: some View {
        HStack(spacing: 12) {
            statTile(icon: "flame.fill", value: "\(learning.streakDays)",
                     label: t(L10n.plural(Double(learning.streakDays), one: "academy.streak_days.one", other: "academy.streak_days.other")),
                     tint: KrezusColor.amberText, bg: KrezusColor.amberTint)
            statTile(icon: "checkmark.seal.fill",
                     value: "\(learning.completedCount)/\(learning.lessons.count)",
                     label: t("academy.lessons_done"),
                     tint: KrezusColor.brandText, bg: KrezusColor.tintStrong)
        }
    }

    private func statTile(icon: String, value: String, label: String,
                          tint: Color, bg: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 18)).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(value).font(KrezusFont.display(18, .heavy))
                    .foregroundStyle(tint).tabularNumbers()
                Text(label).font(KrezusFont.body(11)).foregroundStyle(KrezusColor.fg3)
            }
            Spacer(minLength: 0)
        }
        .padding(KrezusSpacing.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(bg)
        .clipShape(RoundedRectangle(cornerRadius: KrezusRadius.md, style: .continuous))
    }

    // MARK: Liste des leçons

    private var lessonsCard: some View {
        KrzCard(padding: KrezusSpacing.s4) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(t("academy.lessons")).font(KrezusFont.cardTitle).foregroundStyle(KrezusColor.ink)
                    Spacer()
                    Text(t("academy.lessons_total", learning.lessons.count))
                        .font(KrezusFont.body(11.5)).foregroundStyle(KrezusColor.fg3)
                }
                .padding(.bottom, 8)

                ForEach(Array(learning.lessons.enumerated()), id: \.element.id) { index, lesson in
                    if index > 0 { Divider().overlay(KrezusColor.divider) }
                    lessonRow(lesson)
                }
            }
        }
    }

    private func lessonRow(_ lesson: AcademyLesson) -> some View {
        let unlocked = learning.isUnlocked(lesson)
        let done = learning.isCompleted(lesson)

        return Button {
            if unlocked { router.push(.lesson(lesson.position)) }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(done ? KrezusColor.up : (unlocked ? KrezusColor.tintStrong : KrezusColor.tint))
                    if done {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .heavy)).foregroundStyle(.white)
                    } else if unlocked {
                        Text("\(lesson.position)")
                            .font(KrezusFont.display(12.5, .bold))
                            .foregroundStyle(KrezusColor.brandText)
                    } else {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 11)).foregroundStyle(KrezusColor.fg4)
                    }
                }
                .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text(lesson.title)
                        .font(KrezusFont.body(13.5, .semibold))
                        .foregroundStyle(unlocked ? KrezusColor.ink : KrezusColor.fg3)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 6) {
                        if let duration = lesson.duration {
                            Text(duration).font(KrezusFont.caption).foregroundStyle(KrezusColor.fg3)
                        }
                        if learning.quizPassed.contains(lesson.position) {
                            Text(t("academy.quiz_passed"))
                                .font(KrezusFont.caption).foregroundStyle(KrezusColor.up)
                        }
                    }
                }

                Spacer(minLength: 0)

                if unlocked {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(KrezusColor.fg4)
                } else {
                    Text(t("common.premium"))
                        .font(KrezusFont.body(10, .bold))
                        .foregroundStyle(KrezusColor.amberText)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(KrezusColor.amberTint).clipShape(Capsule())
                }
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!unlocked)
    }
}
