import Foundation

/// Règle du versement hebdomadaire, côté affichage. Le versement lui-même
/// est décidé par `claim_weekly_bonus` (0021) : ici, seulement de quoi en
/// parler — montant, dotation de départ et date du prochain.
enum WeeklyBonus {
    /// Dotation d'ouverture, en centimes (1 000 €).
    static let welcomeCents = PortfolioHistory.initialCashCents
    /// Versement de chaque semaine, en centimes (300 €).
    static let weeklyCents = 30_000

    /// La semaine se compte à l'heure de Paris, comme au serveur.
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }()

    /// Lundi 0 h (Paris) qui suit `date`.
    static func nextMonday(after date: Date = Date()) -> Date {
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
        return calendar.date(byAdding: .day, value: 7, to: weekStart) ?? date
    }

    /// « 2026-09-21 » → lundi 0 h, heure de Paris.
    static func parseDay(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: string)
    }

    /// « lundi 21 septembre ».
    static func label(for date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).day().month(.wide)
            .locale(L10n.locale))
    }
}
