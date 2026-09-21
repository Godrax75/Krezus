import Testing
import Foundation
@testable import Krezus

/// Rejeu d'une crise sur la répartition actuelle. Les séries sont rondes :
/// chaque attente se vérifie de tête.
@MainActor
struct CrisisBacktestTests {

    private static let utc = PortfolioHistory.utc

    private static func day(_ day: Int) -> Date {
        utc.date(from: DateComponents(year: 2008, month: 1, day: day))!
    }

    private static func series(_ values: [(Int, Double)]) -> [DatedValue] {
        values.map { DatedValue(date: day($0.0), value: $0.1) }
    }

    private static let alpha = BacktestHolding(symbol: "A", name: "Alpha", valueEuros: 600)
    private static let beta = BacktestHolding(symbol: "B", name: "Beta", valueEuros: 400)

    @Test func laBaisseMaximaleSuitLesPoidsActuels() throws {
        // Alpha (60 %) tombe de moitié, Beta (40 %) perd un quart, puis
        // les deux reviennent à leur cours de départ.
        let closes = [
            "A": Self.series([(1, 100), (2, 50), (3, 100)]),
            "B": Self.series([(1, 20), (2, 15), (3, 20)]),
        ]
        let result = try #require(CrisisBacktest.run(
            holdings: [Self.alpha, Self.beta], closes: closes,
            start: Self.day(1), end: Self.day(3)))

        // 0,6 × 0,5 + 0,4 × 0,75 = 0,60 → −40 %.
        #expect(abs(result.drawdownPct + 40) < 0.001)
        #expect(result.troughDate == Self.day(2))
        #expect(result.troughValueCents == 60_000)
        #expect(abs(result.endChangePct) < 0.001)
        #expect(result.recoveryDays == 1)
        #expect(result.missing.isEmpty)
        #expect(result.coverage == 1)
    }

    @Test func unTitreNonCoteALEpoqueEstEcarteEtLesPoidsRenormalises() throws {
        // Beta n'est coté qu'après la fenêtre : tout repose sur Alpha.
        let closes = [
            "A": Self.series([(1, 100), (2, 50)]),
            "B": Self.series([(20, 20)]),
        ]
        let result = try #require(CrisisBacktest.run(
            holdings: [Self.alpha, Self.beta], closes: closes,
            start: Self.day(1), end: Self.day(3)))

        #expect(result.missing.map(\.symbol) == ["B"])
        #expect(abs(result.drawdownPct + 50) < 0.001)
        // La valeur rejouée ne porte que sur les 600 € couverts.
        #expect(result.troughValueCents == 30_000)
        #expect(abs(result.coverage - 0.6) < 0.001)
    }

    @Test func sansRetourAuNiveauDeDepartLaRecuperationResteInconnue() throws {
        let closes = ["A": Self.series([(1, 100), (2, 40), (3, 60)])]
        let result = try #require(CrisisBacktest.run(
            holdings: [Self.alpha], closes: closes, start: Self.day(1), end: Self.day(3)))

        #expect(result.recoveryDays == nil)
        #expect(result.recoveryMonths == nil)
        #expect(abs(result.endChangePct + 40) < 0.001)
        #expect(result.perHolding.first?.holding.symbol == "A")
    }

    @Test func lImpactProjeteSuitLePoidsDesSecteurs() {
        // 75 % de tech à −40 %, 25 % de santé à −10 % : −32,5 %.
        let impact = ScenarioImpact.estimate(
            weightsBySector: [.technology: 750, .health: 250],
            shocks: ["technology": -40, "health": -10], fallback: -20)
        #expect(abs(impact.pct + 32.5) < 0.001)
        #expect(impact.rows.first?.sector == .technology)

        // Un secteur absent de la table retombe sur la valeur par défaut.
        let fallback = ScenarioImpact.estimate(
            weightsBySector: [.auto: 100], shocks: ["technology": -40], fallback: -20)
        #expect(abs(fallback.pct + 20) < 0.001)
    }
}
