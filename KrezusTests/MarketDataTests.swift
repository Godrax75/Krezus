import Testing
import Foundation
@testable import Krezus

/// Fraîcheur des cotations et traduction du référentiel serveur en fiche
/// affichable. Ces deux points décident de ce que voit l'utilisateur quand le
/// cache prend du retard ou qu'une colonne est vide en base.
@MainActor
struct MarketDataTests {

    private static func quote(ageInSeconds: TimeInterval,
                              price: Double = 100,
                              open: Double? = 95,
                              previousClose: Double? = nil) -> Quote {
        Quote(symbol: "TEST", price: price, priceNative: price, currency: "EUR",
              fxRate: 1, open: open, changePct: nil, previousClose: previousClose,
              quotedAt: nil, fetchedAt: Date().addingTimeInterval(-ageInSeconds))
    }

    // MARK: Fraîcheur

    @Test("Une cotation de moins de deux minutes est fraîche")
    func recentQuoteIsLive() {
        #expect(MarketDataService.freshness(of: Self.quote(ageInSeconds: 30)) == .live)
    }

    @Test("Entre deux et quinze minutes, le cache est en retard mais négociable")
    func laggingQuoteStillTrades() {
        let freshness = MarketDataService.freshness(of: Self.quote(ageInSeconds: 10 * 60))
        #expect(freshness == .lagging)
        #expect(freshness.allowsTrading)
    }

    @Test("Au-delà de quinze minutes, le moteur refusera l'ordre")
    func staleQuoteBlocksTrading() {
        let freshness = MarketDataService.freshness(of: Self.quote(ageInSeconds: 16 * 60))
        #expect(freshness == .stale)
        #expect(freshness.allowsTrading == false)
    }

    @Test("Le seuil correspond à celui du moteur SQL : quinze minutes")
    func thresholdMatchesServer() {
        #expect(MarketDataService.staleThreshold == 15 * 60)
    }

    // MARK: Référentiel → fiche affichable

    private static func security(
        dividendYield: Double? = 2.9,
        initials: String? = "AL",
        countryCode: String? = "FR",
        descriptionEn: String? = "Air Liquide produces industrial gases."
    ) -> Security {
        Security(symbol: "AI", eodhdSymbol: "AI.PA", currency: "EUR", assetType: "stock",
                 name: "Air Liquide", countryCode: countryCode, country: "France",
                 sector: "Gaz industriels", sectorEn: "Industrial gases",
                 founded: "1902", logoAsset: nil,
                 initials: initials, dividendYield: dividendYield,
                 marketCapLabel: "112 Md€", peRatio: nil, pegRatio: nil,
                 ceo: "François Jackow",
                 descriptionFr: "Air Liquide produit les gaz industriels.",
                 descriptionEn: descriptionEn,
                 herculeNoteFr: "L'oxygène des hôpitaux français.",
                 herculeNoteEn: "The oxygen in French hospitals.")
    }

    @Test("Une fiche serveur reprend cours, référentiel et textes")
    func mapsSecurityAndQuote() {
        let stock = StockInfo(security: Self.security(),
                              quote: Self.quote(ageInSeconds: 60, price: 181.95, open: 179.6))

        #expect(stock.symbol == "AI")
        #expect(stock.price == 181.95)
        #expect(stock.open == 179.6)
        #expect(stock.dividendYield == 2.9)
        #expect(stock.cc == "FR")
        #expect(stock.initials == "AL")
        // Les colonnes `*_en` du référentiel arrivent bien jusqu'à la fiche :
        // le secteur anglais vient de `securities.sector_en` (migration 0010),
        // pas d'une table de traduction côté client.
        #expect(stock.sectorEn == "Industrial gases")
        #expect(stock.whatEn == "Air Liquide produces industrial gases.")
    }

    @Test("Sans cotation, la fiche existe quand même et n'affiche aucune variation")
    func mapsWithoutQuote() {
        let stock = StockInfo(security: Self.security(), quote: nil)

        #expect(stock.price == 0)
        // `open == price` : une variation de 0 %, pas une chute de 100 %.
        #expect(stock.open == stock.price)
    }

    @Test("Sans cours d'ouverture, la clôture de la veille sert de base")
    func fallsBackToPreviousClose() {
        let quote = Self.quote(ageInSeconds: 60, price: 100, open: nil, previousClose: 98)
        let stock = StockInfo(security: Self.security(), quote: quote)

        #expect(stock.open == 98)
    }

    @Test("Les initiales manquantes sont dérivées du nom")
    func derivesMissingInitials() {
        let stock = StockInfo(security: Self.security(initials: nil), quote: nil)

        #expect(stock.initials == "AI")
    }

    @Test("La couleur de pastille est stable pour un même symbole")
    func tileColorIsStable() {
        #expect(StockInfo.tileColor(for: "NVDA") == StockInfo.tileColor(for: "NVDA"))
        #expect(StockInfo.tileColor(for: "NVDA") != StockInfo.tileColor(for: "AI"))
    }

    @Test("Le texte anglais sert en anglais, et retombe sur le français sans traduction")
    func editorialFallsBackToFrench() {
        L10n.use(.en)
        defer { L10n.use(.fr) }

        let translated = StockInfo(security: Self.security(), quote: nil)
        #expect(translated.whatLocalized == "Air Liquide produces industrial gases.")

        let untranslated = StockInfo(security: Self.security(descriptionEn: nil), quote: nil)
        #expect(untranslated.whatLocalized == "Air Liquide produit les gaz industriels.")
    }
}
