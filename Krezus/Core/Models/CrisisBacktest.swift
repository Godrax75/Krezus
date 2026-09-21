import Foundation

/// Crise passée qu'on peut rejouer sur un portefeuille. Les dates sont des
/// jours ISO : `start` est le sommet d'avant-crise, `end` la fin de la
/// fenêtre observée — assez tard pour que la reprise, quand elle a eu lieu,
/// tienne dedans.
struct MarketCrisis: Identifiable, Codable, Sendable {
    let id: String
    let emoji: String
    let label: String
    /// Ce qui s'est passé, en deux phrases.
    let summary: String
    let start: String
    let end: String

    var startDate: Date? { MarketCrisis.day(start) }
    var endDate: Date? { MarketCrisis.day(end) }

    /// « 2008 » — repère affiché sur la carte.
    var yearLabel: String { String(start.prefix(4)) }

    static func day(_ iso: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: iso)
    }
}

/// Position telle qu'elle pèse aujourd'hui dans le portefeuille.
struct BacktestHolding: Sendable, Equatable {
    let symbol: String
    let name: String
    /// Valeur de marché actuelle, en euros.
    let valueEuros: Double
}

/// Ce que la crise aurait fait au portefeuille d'aujourd'hui.
struct BacktestResult: Sendable {
    /// Valeur rejouée, jour par jour, en centimes.
    let points: [PortfolioPoint]
    /// Baisse maximale depuis le plus haut atteint, en % (valeur négative).
    let drawdownPct: Double
    let troughDate: Date
    let troughValueCents: Int
    /// Jours entre le point bas et le retour au niveau de départ ; `nil` si
    /// la fenêtre observée s'arrête avant.
    let recoveryDays: Int?
    /// Variation entre le début de la fenêtre et sa fin, en %.
    let endChangePct: Double
    /// Titres rejoués, et titres écartés faute de cotation à l'époque.
    let covered: [BacktestHolding]
    let missing: [BacktestHolding]
    /// Variation de chaque titre rejoué sur la fenêtre, du pire au meilleur.
    let perHolding: [(holding: BacktestHolding, changePct: Double)]

    /// Part du portefeuille effectivement rejouée (0…1).
    var coverage: Double {
        let total = (covered + missing).reduce(0) { $0 + $1.valueEuros }
        guard total > 0 else { return 0 }
        return covered.reduce(0) { $0 + $1.valueEuros } / total
    }

    var recoveryMonths: Int? { recoveryDays.map { Int((Double($0) / 30.44).rounded()) } }
}

/// Rejoue une crise passée sur la répartition actuelle du portefeuille.
///
/// La méthode tient en une phrase : on garde les poids d'aujourd'hui, et on
/// leur applique les cours de l'époque. Ce n'est pas une prévision, et ce
/// n'est pas non plus ce qu'aurait fait l'utilisateur — qui aurait vendu,
/// acheté, changé d'avis. C'est la sensibilité de sa répartition actuelle à
/// un choc déjà survenu.
///
/// Les titres qui n'étaient pas cotés au début de la fenêtre sont écartés, et
/// les poids des autres renormalisés : les valoriser à leur premier cours
/// connu ferait passer une introduction en bourse pour une performance.
enum CrisisBacktest {

    /// - Parameters:
    ///   - holdings: positions actuelles, en euros.
    ///   - closes: clôtures **en euros**, par symbole, triées par date.
    ///   - start: sommet d'avant-crise. `end` borne la fenêtre observée.
    static func run(holdings: [BacktestHolding],
                    closes: [String: [DatedValue]],
                    start: Date,
                    end: Date) -> BacktestResult? {
        let total = holdings.reduce(0) { $0 + $1.valueEuros }
        guard total > 0, start < end else { return nil }

        // Un titre compte s'il cotait déjà à l'ouverture de la fenêtre. Une
        // semaine de battement absorbe les jours fériés d'une place à l'autre.
        let grace = start.addingTimeInterval(7 * 86_400)
        var covered: [BacktestHolding] = []
        var missing: [BacktestHolding] = []
        var basePrices: [String: Double] = [:]
        for holding in holdings {
            let series = closes[holding.symbol] ?? []
            var base: Double?
            if let onOrBefore = PortfolioHistory.lastValue(in: series, onOrBefore: start) {
                base = onOrBefore
            } else if let first = series.first, first.date <= grace {
                base = first.value
            }
            if let base, base > 0 {
                covered.append(holding)
                basePrices[holding.symbol] = base
            } else {
                missing.append(holding)
            }
        }
        let coveredValue = covered.reduce(0) { $0 + $1.valueEuros }
        guard coveredValue > 0 else { return nil }

        // Jours de cotation de la fenêtre, tous titres rejoués confondus.
        var days = Set<Date>()
        for holding in covered {
            for point in closes[holding.symbol] ?? [] where point.date >= start && point.date <= end {
                days.insert(point.date)
            }
        }
        let sortedDays = days.sorted()
        guard sortedDays.count > 1 else { return nil }

        var points: [PortfolioPoint] = []
        var indexes: [Double] = []
        for day in sortedDays {
            var index = 0.0
            for holding in covered {
                guard let base = basePrices[holding.symbol],
                      let price = PortfolioHistory.lastValue(in: closes[holding.symbol] ?? [], onOrBefore: day)
                else { continue }
                index += holding.valueEuros / coveredValue * (price / base)
            }
            indexes.append(index)
            points.append(PortfolioPoint(date: day, valueCents: Int((coveredValue * index * 100).rounded())))
        }

        // Baisse maximale : le pire écart au plus haut déjà atteint, comme le
        // vivrait quelqu'un qui regarde son portefeuille chaque jour.
        var peak = indexes[0]
        var drawdown = 0.0
        var troughIndexPosition = 0
        for (position, index) in indexes.enumerated() {
            peak = max(peak, index)
            let gap = index / peak - 1
            if gap < drawdown {
                drawdown = gap
                troughIndexPosition = position
            }
        }

        // Reprise : retour au niveau du premier jour, après le point bas.
        var recoveryDays: Int?
        if let recovery = indexes[troughIndexPosition...].firstIndex(where: { $0 >= indexes[0] }) {
            let days = sortedDays[recovery].timeIntervalSince(sortedDays[troughIndexPosition]) / 86_400
            recoveryDays = Int(days.rounded())
        }

        let perHolding = covered.map { holding -> (BacktestHolding, Double) in
            let series = closes[holding.symbol] ?? []
            let base = basePrices[holding.symbol] ?? 0
            let last = PortfolioHistory.lastValue(in: series, onOrBefore: sortedDays[troughIndexPosition]) ?? base
            return (holding, base > 0 ? (last / base - 1) * 100 : 0)
        }.sorted { $0.1 < $1.1 }

        return BacktestResult(
            points: points,
            drawdownPct: drawdown * 100,
            troughDate: sortedDays[troughIndexPosition],
            troughValueCents: points[troughIndexPosition].valueCents,
            recoveryDays: recoveryDays,
            endChangePct: (indexes[indexes.count - 1] - 1) * 100,
            covered: covered,
            missing: missing,
            perHolding: perHolding.map { (holding: $0.0, changePct: $0.1) })
    }
}

// MARK: - Scénarios projetés

/// Impact estimé d'un scénario sur un portefeuille, à partir de chocs par
/// secteur posés dans le contenu éditorial.
///
/// C'est une estimation, pas une prévision : aucune probabilité n'est
/// affichée, et les hypothèses sont montrées telles quelles. Un pourcentage
/// de risque inventé aurait l'air d'une mesure alors qu'il n'en serait pas une.
enum ScenarioImpact {

    /// - Parameters:
    ///   - shocks: variation supposée par secteur (clé `SectorGroup`), en %.
    ///   - fallback: variation appliquée aux secteurs absents de la table.
    /// - Returns: impact en % du portefeuille, et le détail par secteur présent.
    static func estimate(weightsBySector: [SectorGroup: Double],
                         shocks: [String: Double],
                         fallback: Double) -> (pct: Double, rows: [(sector: SectorGroup, weight: Double, shock: Double)]) {
        let total = weightsBySector.values.reduce(0, +)
        guard total > 0 else { return (0, []) }
        var pct = 0.0
        var rows: [(SectorGroup, Double, Double)] = []
        for (sector, weight) in weightsBySector {
            let shock = shocks[sector.rawValue] ?? fallback
            let share = weight / total
            pct += share * shock
            rows.append((sector, share, shock))
        }
        return (pct, rows.sorted { $0.1 > $1.1 }.map { (sector: $0.0, weight: $0.1, shock: $0.2) })
    }
}
