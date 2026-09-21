import Foundation

// MARK: - Périodes

/// Périodes proposées au-dessus de la courbe du portefeuille.
enum PortfolioRange: String, CaseIterable, Identifiable, Sendable {
    case day, week, month, ytd, year, fiveYears, max

    var id: String { rawValue }

    /// Libellé court du sélecteur (« 1J », « 1S »… / « 1D », « 1W »…).
    var label: String { t("portfolio.range.\(rawValue)") }

    /// Complément du gain (« sur 1 mois », « depuis le 1er janvier »…).
    var caption: String { t("portfolio.range_caption.\(rawValue)") }

    /// Début de la période ; `nil` = depuis l'ouverture du portefeuille.
    /// « 1 jour » glisse sur 24 heures : la veille d'un lundi est un dimanche
    /// sans cotation, et une courbe réduite à la séance du jour serait vide
    /// chaque matin avant l'ouverture.
    func start(now: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case .day:       return now.addingTimeInterval(-86_400)
        case .week:      return calendar.date(byAdding: .day, value: -7, to: now)
        case .month:     return calendar.date(byAdding: .month, value: -1, to: now)
        case .ytd:       return calendar.date(from: calendar.dateComponents([.year], from: now))
        case .year:      return calendar.date(byAdding: .year, value: -1, to: now)
        case .fiveYears: return calendar.date(byAdding: .year, value: -5, to: now)
        case .max:       return nil
        }
    }
}

// MARK: - Données sources

/// Ordre exécuté, tel que lu dans `public.orders`.
struct PortfolioOrder: Decodable, Sendable {
    let symbol: String
    let side: String
    /// Montant en centimes d'euro : débité à l'achat, crédité à la vente.
    let amountCents: Int
    let quantity: Double
    let createdAt: Date

    var isBuy: Bool { side == "buy" }

    enum CodingKeys: String, CodingKey {
        case symbol, side, quantity
        case amountCents = "amount_cents"
        case createdAt = "created_at"
    }
}

/// Versement de liquidités (bonus hebdomadaire), tel que lu dans
/// `public.cash_deposits`. C'est un apport, pas un gain : la courbe le
/// compte dans la valeur, le gain l'en retire.
struct PortfolioDeposit: Decodable, Sendable {
    let amountCents: Int
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case amountCents = "amount_cents"
        case createdAt = "created_at"
    }
}

/// Valeur datée : une clôture, un taux, un cours intraday.
struct DatedValue: Sendable, Equatable {
    let date: Date
    let value: Double
}

/// Point de la courbe.
struct PortfolioPoint: Identifiable, Sendable, Equatable {
    let date: Date
    let valueCents: Int
    /// Cumul des versements reçus à cette date : ce qui, dans la valeur,
    /// n'est pas de la performance.
    var depositedCents: Int = 0
    var id: Date { date }
}

// MARK: - Reconstitution

/// Reconstitue la valeur passée du portefeuille à partir de ses ordres et des
/// cours de ses titres.
///
/// Rien n'enregistre la valeur jour après jour : on la recalcule. À chaque
/// instant, valeur = liquidités + Σ quantité détenue × cours du titre, en
/// euros. Les liquidités partent de 1 000 € et suivent les ordres ; les
/// quantités aussi. C'est rétroactif, et juste dès le premier ordre.
///
/// Deux approximations, assumées :
///   - les clôtures sont ajustées des dividendes, que le portefeuille papier
///     ne verse pas : avant une date de détachement, le titre paraît valoir un
///     peu moins qu'il ne valait ;
///   - un titre acheté avant la première clôture connue est valorisé à son
///     prix d'achat jusqu'à ce qu'elle existe.
enum PortfolioHistory {

    /// Dotation d'un portefeuille papier, à l'ouverture comme après remise à zéro.
    static let initialCashCents = 100_000

    /// Calendrier des dates de clôture : `price_history` date en jours ISO,
    /// sans fuseau.
    static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    // MARK: Série quotidienne

    /// Une valeur par jour de cotation, en fin de journée, de l'ouverture du
    /// portefeuille jusqu'à la veille. Le point du jour est la valeur en
    /// direct, que l'appelant ajoute.
    ///
    /// - Parameters:
    ///   - closes: clôtures en devise de cotation, par symbole, triées.
    ///   - currencies: devise de cotation par symbole (« EUR », « USD »).
    ///   - eurUsd: clôtures EURUSD (dollars pour un euro), triées.
    ///   - fallbackEurUsd: taux du jour, si l'historique manque.
    static func daily(orders: [PortfolioOrder],
                      deposits: [PortfolioDeposit] = [],
                      closes: [String: [DatedValue]],
                      currencies: [String: String],
                      eurUsd: [DatedValue] = [],
                      fallbackEurUsd: Double? = nil,
                      fx: [String: [DatedValue]] = [:],
                      fallbackFx: [String: Double] = [:],
                      inception: Date,
                      now: Date) -> [PortfolioPoint] {
        // Taux d'une devise un jour donné. `eurUsd` reste accepté seul pour
        // le dollar ; les autres devises passent par `fx`.
        func rate(for currency: String, on day: Date) -> Double? {
            guard let key = fxCurrency(for: currency) else { return 1 }
            let series = fx[key] ?? (key == "USD" ? eurUsd : [])
            return lastValue(in: series, onOrBefore: day)
                ?? fallbackFx[key] ?? (key == "USD" ? fallbackEurUsd : nil)
        }

        let events = LedgerEvent.merge(orders: orders, deposits: deposits)
        let today = utc.startOfDay(for: now)

        // Jours de cotation des titres détenus, de l'ouverture à hier.
        let firstDay = utc.startOfDay(for: inception)
        var days = Set<Date>()
        for series in closes.values {
            for point in series where point.date >= firstDay && point.date < today {
                days.insert(utc.startOfDay(for: point.date))
            }
        }

        var points = [PortfolioPoint(date: inception, valueCents: initialCashCents)]
        var ledger = Ledger()
        var eventIndex = 0

        for day in days.sorted() {
            guard let endOfDay = utc.date(byAdding: .day, value: 1, to: day),
                  endOfDay > inception else { continue }
            while eventIndex < events.count, events[eventIndex].date < endOfDay {
                ledger.apply(events[eventIndex])
                eventIndex += 1
            }
            let value = ledger.valueCents { symbol in
                guard let close = lastValue(in: closes[symbol] ?? [], onOrBefore: day) else { return nil }
                let currency = currencies[symbol] ?? "EUR"
                return toEuros(close, currency: currency, rate: rate(for: currency, on: day))
            }
            // Horodaté en fin de séance plutôt qu'à minuit : le point du
            // vendredi ne doit pas tomber sur le samedi.
            let stamp = min(utc.date(byAdding: .hour, value: 18, to: day) ?? day, now)
            points.append(PortfolioPoint(date: max(stamp, inception), valueCents: value,
                                         depositedCents: ledger.depositedCents))
        }
        return points
    }

    // MARK: Série intraday

    /// Un point par relevé de cours (regroupés par tranche de cinq minutes),
    /// depuis `from`.
    ///
    /// - Parameter prices: cours déjà convertis en euros, par symbole, triés.
    static func intraday(orders: [PortfolioOrder],
                         deposits: [PortfolioDeposit] = [],
                         prices: [String: [DatedValue]],
                         from: Date,
                         inception: Date,
                         now: Date) -> [PortfolioPoint] {
        let start = max(from, inception)
        let events = LedgerEvent.merge(orders: orders, deposits: deposits)

        var stamps = Set<Date>()
        for series in prices.values {
            for point in series where point.date > start && point.date <= now {
                stamps.insert(bucket(point.date))
            }
        }

        var ledger = Ledger()
        var eventIndex = 0
        func point(at instant: Date) -> PortfolioPoint {
            while eventIndex < events.count, events[eventIndex].date <= instant {
                ledger.apply(events[eventIndex])
                eventIndex += 1
            }
            let value = ledger.valueCents { symbol in
                lastValue(in: prices[symbol] ?? [], onOrBefore: instant)
            }
            return PortfolioPoint(date: instant, valueCents: value, depositedCents: ledger.depositedCents)
        }

        var points = [point(at: start)]
        for stamp in stamps.sorted() where stamp > start {
            points.append(point(at: stamp))
        }
        return points
    }

    // MARK: Découpage par période

    /// Garde les points de la période, précédés de la valeur à son début :
    /// sans ce point d'ancrage, le gain se mesurerait depuis le premier jour
    /// de cotation de la période, pas depuis son début.
    static func slice(_ points: [PortfolioPoint], from start: Date?) -> [PortfolioPoint] {
        guard let start, let first = points.first, start > first.date else { return points }
        let before = points.last { $0.date <= start }
        var sliced = points.filter { $0.date > start }
        if let before {
            sliced.insert(PortfolioPoint(date: start, valueCents: before.valueCents,
                                         depositedCents: before.depositedCents), at: 0)
        }
        return sliced
    }

    // MARK: Outils

    /// Ordre ou versement, rejoués dans l'ordre chronologique.
    private enum LedgerEvent {
        case order(PortfolioOrder)
        case deposit(PortfolioDeposit)

        var date: Date {
            switch self {
            case .order(let order):     return order.createdAt
            case .deposit(let deposit): return deposit.createdAt
            }
        }

        static func merge(orders: [PortfolioOrder], deposits: [PortfolioDeposit]) -> [LedgerEvent] {
            (orders.map(LedgerEvent.order) + deposits.map(LedgerEvent.deposit))
                .sorted { $0.date < $1.date }
        }
    }

    /// Liquidités et quantités après une suite d'ordres et de versements.
    private struct Ledger {
        var cashCents = PortfolioHistory.initialCashCents
        var depositedCents = 0
        var quantities: [String: Double] = [:]
        /// Dernier prix unitaire payé ou encaissé, en euros : valorisation de
        /// repli tant qu'aucun cours n'existe pour le titre.
        var lastUnitEuros: [String: Double] = [:]

        mutating func apply(_ event: LedgerEvent) {
            switch event {
            case .order(let order):
                apply(order)
            case .deposit(let deposit):
                cashCents += deposit.amountCents
                depositedCents += deposit.amountCents
            }
        }

        mutating func apply(_ order: PortfolioOrder) {
            if order.isBuy {
                cashCents -= order.amountCents
                quantities[order.symbol, default: 0] += order.quantity
            } else {
                cashCents += order.amountCents
                quantities[order.symbol, default: 0] -= order.quantity
            }
            if order.quantity > 0 {
                lastUnitEuros[order.symbol] = Double(order.amountCents) / 100 / order.quantity
            }
        }

        func valueCents(price: (String) -> Double?) -> Int {
            var total = Double(cashCents)
            for (symbol, quantity) in quantities where quantity > 1e-9 {
                guard let unit = price(symbol) ?? lastUnitEuros[symbol] else { continue }
                total += quantity * unit * 100
            }
            return Int(total.rounded())
        }
    }

    /// Dernière valeur datée au plus tard de `date` (série triée).
    static func lastValue(in series: [DatedValue], onOrBefore date: Date) -> Double? {
        var low = 0, high = series.count - 1, found: Double?
        while low <= high {
            let mid = (low + high) / 2
            if series[mid].date <= date {
                found = series[mid].value
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return found
    }

    /// Devise de la paire de change qui convertit une devise de cotation en
    /// euros : « USD » pour le dollar, « GBP » pour la livre **et** pour les
    /// pence de Londres (GBX). `nil` pour l'euro.
    static func fxCurrency(for currency: String) -> String? {
        switch currency.uppercased() {
        case "EUR": return nil
        case "GBX": return "GBP"
        case let code: return code
        }
    }

    /// Cours en euros. `rate` = unités de la devise de la paire pour un euro
    /// (dollars, livres, yens…). Les pence valent un centième de livre.
    static func toEuros(_ value: Double, currency: String, rate: Double?) -> Double? {
        let code = currency.uppercased()
        if code == "EUR" { return value }
        guard let rate, rate > 0 else { return nil }
        return code == "GBX" ? value / 100 / rate : value / rate
    }

    private static func bucket(_ date: Date) -> Date {
        let seconds = date.timeIntervalSinceReferenceDate
        return Date(timeIntervalSinceReferenceDate: (seconds / 300).rounded(.down) * 300)
    }
}
