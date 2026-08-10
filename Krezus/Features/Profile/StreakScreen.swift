import SwiftUI

/// « Série » — les sept derniers jours, le record, et ce qui la fait avancer.
///
/// L'écran dit explicitement qu'une série ne rapporte pas d'XP : c'est le
/// plafond quotidien des missions qui en donne, et laisser croire l'inverse
/// pousserait à enchaîner les leçons pour rien.
struct StreakScreen: View {
    @Environment(LearningStore.self) private var learning
    @Environment(Router.self) private var router

    /// Initiales des sept jours, du lundi au dimanche, dans la langue choisie
    /// (« L M M J V S D » en français, « M T W T F S S » en anglais). Le
    /// calendrier fournit ses symboles à partir du dimanche : on fait tourner
    /// d'un cran plutôt que de coder les lettres en dur par langue.
    private static var weekdayInitials: [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = L10n.locale
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        return Array(symbols[1...] + symbols[...0])
    }

    var body: some View {
        ZStack {
            KrezusColor.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: KrezusSpacing.s3) {
                    hero
                    weekStrip
                    statusCard
                    explanation
                }
                .padding(.horizontal, KrezusSpacing.s4)
                .padding(.bottom, 60)
            }
            .scrollIndicators(.hidden)
        }
        .krezusNavBar(t("streak.title"))
    }

    // MARK: Bandeau

    private var hero: some View {
        KrzCard(shadow: KrezusShadow.brand) {
            VStack(spacing: 6) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(KrezusColor.amber500)
                Text("\(learning.streakDays)")
                    .font(KrezusFont.display(46, .heavy))
                    .foregroundStyle(KrezusColor.ink).tabularNumbers()
                Text(t(L10n.plural(Double(learning.streakDays),
                                   one: "streak.days_in_a_row.one",
                                   other: "streak.days_in_a_row.other")))
                    .font(KrezusFont.bodyMd).foregroundStyle(KrezusColor.fg3)
                Text(t(L10n.plural(Double(learning.bestStreakDays),
                                   one: "streak.record.one", other: "streak.record.other"),
                       learning.bestStreakDays))
                    .font(KrezusFont.caption).foregroundStyle(KrezusColor.fg3)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, KrezusSpacing.s3)
        }
        .padding(.top, 4)
    }

    // MARK: Semaine

    /// Sept pastilles, du lundi à aujourd'hui. Un jour est marqué actif s'il
    /// tombe dans la série en cours — on n'a pas d'historique jour par jour,
    /// et en inventer un afficherait des jours actifs qui ne l'ont pas été.
    private var weekStrip: some View {
        KrzCard {
            VStack(alignment: .leading, spacing: KrezusSpacing.s3) {
                Text(t("streak.this_week"))
                    .font(KrezusFont.cardTitle).foregroundStyle(KrezusColor.ink)

                HStack(spacing: 0) {
                    ForEach(Array(Self.weekdayInitials.enumerated()), id: \.offset) { index, letter in
                        VStack(spacing: 7) {
                            Text(letter)
                                .font(KrezusFont.caption).foregroundStyle(KrezusColor.fg3)
                            dayDot(isActive: isActive(weekdayIndex: index),
                                   isToday: index == todayIndex)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private func dayDot(isActive: Bool, isToday: Bool) -> some View {
        ZStack {
            Circle()
                .fill(isActive ? KrezusColor.amberTint : KrezusColor.tint)
                .frame(width: 32, height: 32)
            if isActive {
                Image(systemName: "flame.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(KrezusColor.amber500)
            }
        }
        .overlay(
            Circle()
                .stroke(isToday ? KrezusColor.brandFill : Color.clear, lineWidth: 2)
                .frame(width: 32, height: 32))
    }

    /// Index du jour courant, lundi = 0.
    private var todayIndex: Int {
        let weekday = Calendar.current.component(.weekday, from: Date()) // dimanche = 1
        return (weekday + 5) % 7
    }

    private func isActive(weekdayIndex index: Int) -> Bool {
        guard index <= todayIndex else { return false }
        // Le jour courant ne compte que si une activité y a déjà été enregistrée.
        if index == todayIndex { return learning.isStreakSafeToday }
        return todayIndex - index < learning.streakDays
    }

    // MARK: État du jour

    private var statusCard: some View {
        let safe = learning.isStreakSafeToday
        return KrzCard {
            VStack(alignment: .leading, spacing: KrezusSpacing.s3) {
                HStack(spacing: KrezusSpacing.s3) {
                    Image(systemName: safe ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(safe ? KrezusColor.up : KrezusColor.amber500)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(safe ? t("streak.safe_title") : t("streak.at_risk_title"))
                            .font(KrezusFont.cardTitle).foregroundStyle(KrezusColor.ink)
                        Text(safe
                             ? t("streak.safe_body", learning.streakDays + 1)
                             : t("streak.at_risk_body"))
                            .font(KrezusFont.caption).foregroundStyle(KrezusColor.fg3)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                }

                if !safe, let next = learning.nextLesson {
                    KrzPrimaryButton(title: t("streak.do_lesson")) {
                        router.push(.lesson(next.position))
                    }
                }
            }
        }
    }

    // MARK: Règles

    private var explanation: some View {
        KrzCard {
            VStack(alignment: .leading, spacing: KrezusSpacing.s3) {
                Text(t("streak.how_it_works"))
                    .font(KrezusFont.cardTitle).foregroundStyle(KrezusColor.ink)

                rule("flame.fill", t("streak.rule.lesson"))
                rule("moon.zzz.fill", t("streak.rule.miss"))
                rule("bolt.fill", t("streak.rule.xp"))
            }
        }
    }

    private func rule(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(KrezusColor.amberText)
                .frame(width: 22, height: 22)
                .background(KrezusColor.amberTint).clipShape(Circle())
            Text(text)
                .font(KrezusFont.bodySm).foregroundStyle(KrezusColor.fg2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
