import Testing
import Foundation
@testable import Krezus

/// Reconstitution de la courbe du portefeuille. Chaque cas se vérifie de
/// tête : 1 000 € de départ, des cours ronds, un taux EURUSD simple.
@MainActor
struct PortfolioHistoryTests {

    private static let utc = PortfolioHistory.utc

    private static func at(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        utc.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    private static func order(_ symbol: String, _ side: String, cents: Int, qty: Double, at date: Date) -> PortfolioOrder {
        let json = """
        {"symbol":"\(symbol)","side":"\(side)","amount_cents":\(cents),"quantity":\(qty),
         "created_at":"\(ISO8601DateFormatter().string(from: date))"}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try! decoder.decode(PortfolioOrder.self, from: Data(json.utf8))
    }

    private static func daily(_ orders: [PortfolioOrder],
                              closes: [String: [DatedValue]],
                              currencies: [String: String] = [:],
                              eurUsd: [DatedValue] = []) -> [PortfolioPoint] {
        PortfolioHistory.daily(orders: orders, closes: closes, currencies: currencies,
                               eurUsd: eurUsd, fallbackEurUsd: nil,
                               inception: at(1, 8), now: at(4, 12))
    }

    @Test func sansOrdreLaCourbeResteADixMilleCentimes() {
        let points = Self.daily([], closes: [:])
        #expect(points.map(\.valueCents) == [100_000])
    }

    @Test func unAchatSuitLeCoursDuTitre() {
        // 500 € d'un titre à 50 € : 10 parts. Clôtures 50 puis 55.
        let orders = [Self.order("AI", "buy", cents: 50_000, qty: 10, at: Self.at(1, 10))]
        let closes = ["AI": [DatedValue(date: Self.at(1), value: 50),
                             DatedValue(date: Self.at(2), value: 55)]]
        let points = Self.daily(orders, closes: closes, currencies: ["AI": "EUR"])
        #expect(points.map(\.valueCents) == [100_000, 100_000, 105_000])
    }

    @Test func unTitreEnDollarsEstConvertiAuTauxDeSaDate() {
        // 100 € à 110 $ quand 1 € = 1,10 $ : une part. Le lendemain, même
        // cours de 121 $ mais deux taux différents.
        let orders = [Self.order("NVDA", "buy", cents: 10_000, qty: 1, at: Self.at(1, 15))]
        let closes = ["NVDA": [DatedValue(date: Self.at(1), value: 110),
                               DatedValue(date: Self.at(2), value: 121),
                               DatedValue(date: Self.at(3), value: 121)]]
        let fx = [DatedValue(date: Self.at(1), value: 1.10),
                  DatedValue(date: Self.at(2), value: 1.10),
                  DatedValue(date: Self.at(3), value: 1.21)]
        let points = Self.daily(orders, closes: closes, currencies: ["NVDA": "USD"], eurUsd: fx)
        // 900 € + 110 $/1,10 = 1 000 € · 900 € + 121 $/1,10 = 1 010 € · 900 € + 121 $/1,21 = 1 000 €
        #expect(points.map(\.valueCents) == [100_000, 100_000, 101_000, 100_000])
    }

    @Test func uneVenteRendLesLiquidites() {
        let orders = [
            Self.order("AI", "buy", cents: 50_000, qty: 10, at: Self.at(1, 10)),
            Self.order("AI", "sell", cents: 60_000, qty: 10, at: Self.at(2, 10)),
        ]
        let closes = ["AI": [DatedValue(date: Self.at(1), value: 50),
                             DatedValue(date: Self.at(2), value: 60),
                             DatedValue(date: Self.at(3), value: 70)]]
        let points = Self.daily(orders, closes: closes, currencies: ["AI": "EUR"])
        // Après la vente, plus rien n'expose au cours de 70 €.
        #expect(points.map(\.valueCents) == [100_000, 100_000, 110_000, 110_000])
    }

    @Test func sansClotureLeTitreEstValoriseAuPrixDAchat() {
        // Acheté la veille de sa première clôture connue.
        let orders = [Self.order("AI", "buy", cents: 30_000, qty: 2, at: Self.at(1, 10))]
        let closes = ["AI": [DatedValue(date: Self.at(2), value: 160)],
                      "MC": [DatedValue(date: Self.at(1), value: 700)]]
        let points = Self.daily(orders, closes: closes, currencies: ["AI": "EUR"])
        // Jour 1 : 700 € + 2 × 150 € (prix payé) ; jour 2 : 700 € + 2 × 160 €.
        #expect(points.map(\.valueCents) == [100_000, 100_000, 102_000])
    }

    @Test func laDecoupeRepartDeLaValeurAuDebutDeLaPeriode() {
        let points = [PortfolioPoint(date: Self.at(1), valueCents: 100_000),
                      PortfolioPoint(date: Self.at(2), valueCents: 104_000),
                      PortfolioPoint(date: Self.at(4), valueCents: 110_000)]
        let sliced = PortfolioHistory.slice(points, from: Self.at(3))
        // Le 3 n'a pas de point : il reprend la valeur du 2.
        #expect(sliced.map(\.valueCents) == [104_000, 110_000])
        #expect(sliced.first?.date == Self.at(3))
    }

    @Test func laCourbeIntradaySuitLesReleves() {
        let orders = [Self.order("AI", "buy", cents: 50_000, qty: 10, at: Self.at(2, 9))]
        let prices = ["AI": [DatedValue(date: Self.at(2, 9, 30), value: 51),
                             DatedValue(date: Self.at(2, 10, 0), value: 49)]]
        let points = PortfolioHistory.intraday(orders: orders, prices: prices,
                                               from: Self.at(2, 8), inception: Self.at(1, 8),
                                               now: Self.at(2, 11))
        #expect(points.map(\.valueCents) == [100_000, 101_000, 99_000])
    }

    @Test func leChangeNeConvertitQueLeDollar() {
        // 110 / 1,1 = 99,999… en virgule flottante : la valeur est arrondie
        // au centime par la suite, on compare donc à un millième près.
        #expect(abs((PortfolioHistory.toEuros(110, currency: "USD", rate: 1.1) ?? 0) - 100) < 0.001)
        #expect(PortfolioHistory.toEuros(110, currency: "EUR", rate: 1.1) == 110)
        #expect(PortfolioHistory.toEuros(110, currency: "USD", rate: nil) == nil)
    }

    // MARK: Versements hebdomadaires

    private static func deposit(cents: Int, at date: Date) -> PortfolioDeposit {
        let json = """
        {"amount_cents":\(cents),"created_at":"\(ISO8601DateFormatter().string(from: date))"}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try! decoder.decode(PortfolioDeposit.self, from: Data(json.utf8))
    }

    @Test func unVersementEntreDansLaValeurEtDansLeCumul() {
        // 500 € d'un titre à 50 € le 1er, 300 € versés le 2 : la valeur
        // monte de 300 €, le cumul des versements aussi.
        let orders = [Self.order("AI", "buy", cents: 50_000, qty: 10, at: Self.at(1, 10))]
        let closes = ["AI": [DatedValue(date: Self.at(1), value: 50),
                             DatedValue(date: Self.at(2), value: 50),
                             DatedValue(date: Self.at(3), value: 55)]]
        let points = PortfolioHistory.daily(
            orders: orders, deposits: [Self.deposit(cents: 30_000, at: Self.at(2, 9))],
            closes: closes, currencies: ["AI": "EUR"], eurUsd: [], fallbackEurUsd: nil,
            inception: Self.at(1, 8), now: Self.at(4, 12))
        #expect(points.map(\.valueCents) == [100_000, 100_000, 130_000, 135_000])
        #expect(points.map(\.depositedCents) == [0, 0, 30_000, 30_000])
    }

    @Test func leGainDUnePeriodeNeCompteNiLeVersementNiNeLeRateDansLaBase() {
        // 1 000 € au départ, 1 350 € à l'arrivée dont 300 € versés :
        // 50 € de gain, rapportés à 1 300 €.
        let points = [PortfolioPoint(date: Self.at(1), valueCents: 100_000),
                      PortfolioPoint(date: Self.at(3), valueCents: 135_000, depositedCents: 30_000)]
        let summary = PerformanceSummary(points: points, selectedDate: nil)
        #expect(summary.gainCents == 5_000)
        #expect(abs(summary.gainPct - 5_000.0 / 130_000 * 100) < 1e-9)
    }

    @Test func unVersementAnterieurALaPeriodeNEstPasRetireDeuxFois() {
        let points = [PortfolioPoint(date: Self.at(1), valueCents: 130_000, depositedCents: 30_000),
                      PortfolioPoint(date: Self.at(3), valueCents: 132_600, depositedCents: 30_000)]
        let summary = PerformanceSummary(points: points, selectedDate: nil)
        #expect(summary.gainCents == 2_600)
        #expect(abs(summary.gainPct - 2.0) < 1e-9)
    }
}
