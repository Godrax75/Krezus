import Testing
import Foundation
@testable import Krezus

/// Moteur d'ordres papier — le miroir local du mode démo.
///
/// Ces cas reprennent un à un ceux de `supabase/tests/paper_engine_test.sql` :
/// les deux moteurs doivent rendre les mêmes chiffres, sans quoi un portefeuille
/// vu en démo puis rechargé depuis un compte changerait sous les yeux de
/// l'utilisateur. Quand l'un des deux fichiers bouge, l'autre doit suivre.
@MainActor
struct PaperOrderTests {

    /// Portefeuille propre : sans les deux positions de départ du prototype,
    /// qui rendraient chaque assertion dépendante du cours simulé de Nvidia.
    private func makeStore() -> TradingStore {
        let store = TradingStore()
        store.resetForTesting(cashCents: 100_000, catalog: [Self.stock(price: 200)])
        return store
    }

    private static func stock(symbol: String = "TEST", price: Double,
                              open: Double? = nil) -> StockInfo {
        StockInfo(symbol: symbol, name: "Titre de test", cc: "FR", sector: "Test",
                  founded: "1900", dividendYield: nil, mcap: "—", pe: nil, peg: nil,
                  ceo: "—", what: "", hercule: "", logoAsset: nil, initials: "TE",
                  tileHex: 0, open: open ?? price, price: price)
    }

    // MARK: Achat

    @Test("Un achat de 100 € à 200 € l'action donne une demi-part")
    func buysFractionalShares() throws {
        let store = makeStore()
        let qty = try store.demoBuy(symbol: "TEST", amountCents: 10_000)

        #expect(qty == 0.5)
        #expect(store.quantity("TEST") == 0.5)
        #expect(store.cashCents == 90_000)
    }

    @Test("La quantité est arrondie à 8 décimales, comme le moteur SQL")
    func roundsQuantityLikeServer() throws {
        let store = TradingStore()
        // 100 € à 3 € l'action = 33,3333333333… parts.
        store.resetForTesting(cashCents: 100_000, catalog: [Self.stock(price: 3)])
        let qty = try store.demoBuy(symbol: "TEST", amountCents: 10_000)

        #expect(qty == 33.33333333)
        #expect(qty == TradingStore.roundedQuantity(100.0 / 3.0))
    }

    @Test("Un achat au-delà du solde est refusé, et ne touche à rien")
    func rejectsInsufficientFunds() {
        let store = makeStore()

        #expect(throws: TradingStore.OrderError.insufficientFunds) {
            try store.demoBuy(symbol: "TEST", amountCents: 100_001)
        }
        #expect(store.cashCents == 100_000)
        #expect(store.positions.isEmpty)
    }

    @Test("Un montant nul ou négatif est refusé")
    func rejectsNonPositiveAmount() {
        let store = makeStore()

        #expect(throws: TradingStore.OrderError.insufficientFunds) {
            try store.demoBuy(symbol: "TEST", amountCents: 0)
        }
        #expect(throws: TradingStore.OrderError.insufficientFunds) {
            try store.demoBuy(symbol: "TEST", amountCents: -500)
        }
    }

    @Test("Un titre absent du catalogue est refusé")
    func rejectsUnknownStock() {
        let store = makeStore()

        #expect(throws: TradingStore.OrderError.unknownStock) {
            try store.demoBuy(symbol: "INCONNU", amountCents: 1_000)
        }
    }

    @Test("Deux achats à des cours différents donnent un coût de revient pondéré")
    func averagesCostAcrossPurchases() throws {
        let store = makeStore()
        try store.demoBuy(symbol: "TEST", amountCents: 10_000)   // 0,5 part à 200 €

        store.setPriceForTesting(symbol: "TEST", price: 100)
        try store.demoBuy(symbol: "TEST", amountCents: 10_000)   // 1 part à 100 €

        // 1,5 part pour 200 € investis → 133,33 € la part.
        #expect(store.quantity("TEST") == 1.5)
        #expect(store.positions["TEST"]?.avgCostCents == 13_333)
        #expect(store.cashCents == 80_000)
    }

    // MARK: Vente

    @Test("Vendre 25 %, puis 50 % du reste, laisse la bonne quantité",
          arguments: [(25, 0.375), (50, 0.25), (100, 0.0)])
    func sellsRequestedShare(pct: Int, expectedRemaining: Double) throws {
        let store = makeStore()
        try store.demoBuy(symbol: "TEST", amountCents: 10_000)   // 0,5 part

        try store.demoSell(symbol: "TEST", pct: pct)

        #expect(store.quantity("TEST") == expectedRemaining)
    }

    @Test("Une vente totale supprime la ligne plutôt que d'en laisser une à zéro")
    func fullSaleRemovesPosition() throws {
        let store = makeStore()
        try store.demoBuy(symbol: "TEST", amountCents: 10_000)

        let proceeds = try store.demoSell(symbol: "TEST", pct: 100)

        #expect(proceeds == 10_000)
        #expect(store.positions["TEST"] == nil)
        #expect(store.owns("TEST") == false)
        #expect(store.cashCents == 100_000)
    }

    @Test("Une vente sur une position inexistante est refusée")
    func rejectsSaleWithoutPosition() {
        let store = makeStore()

        #expect(throws: TradingStore.OrderError.noPosition) {
            try store.demoSell(symbol: "TEST", pct: 50)
        }
    }

    @Test("Une vente partielle conserve le coût de revient d'origine")
    func partialSaleKeepsAverageCost() throws {
        let store = makeStore()
        try store.demoBuy(symbol: "TEST", amountCents: 10_000)
        let costBefore = store.positions["TEST"]?.avgCostCents

        try store.demoSell(symbol: "TEST", pct: 50)

        #expect(store.positions["TEST"]?.avgCostCents == costBefore)
    }

    @Test("Le produit d'une vente suit le cours du moment, pas le prix d'achat")
    func saleUsesCurrentPrice() throws {
        let store = makeStore()
        try store.demoBuy(symbol: "TEST", amountCents: 10_000)   // 0,5 part à 200 €

        store.setPriceForTesting(symbol: "TEST", price: 300)
        let proceeds = try store.demoSell(symbol: "TEST", pct: 100)

        #expect(proceeds == 15_000)                              // 0,5 × 300 €
        #expect(store.cashCents == 105_000)
    }

    // MARK: Agrégats du portefeuille

    @Test("La valeur totale additionne le solde et la valeur de marché")
    func totalValueAddsCashAndHoldings() throws {
        let store = makeStore()
        try store.demoBuy(symbol: "TEST", amountCents: 10_000)

        #expect(store.totalValueCents == 100_000)                // rien n'a bougé

        store.setPriceForTesting(symbol: "TEST", price: 240)
        #expect(store.totalValueCents == 102_000)                // 0,5 × 40 € de plus
    }

    @Test("La variation du jour est pondérée par les positions, pas par le nombre de lignes")
    func dayChangeIsWeighted() throws {
        let store = TradingStore()
        store.resetForTesting(cashCents: 100_000, catalog: [
            Self.stock(symbol: "GROSSE", price: 110, open: 100),   // +10 %
            Self.stock(symbol: "PETITE", price: 90, open: 100),    // −10 %
        ])
        try store.demoBuy(symbol: "GROSSE", amountCents: 90_000)
        try store.demoBuy(symbol: "PETITE", amountCents: 10_000)

        // La grosse ligne pèse neuf fois la petite : la variation penche vers elle.
        #expect(store.dayChangePct > 7)
        #expect(store.dayChangePct < 9)
    }

    @Test("La plus-value se mesure contre le coût de revient")
    func positionGainUsesAverageCost() throws {
        let store = makeStore()
        try store.demoBuy(symbol: "TEST", amountCents: 10_000)

        store.setPriceForTesting(symbol: "TEST", price: 260)

        // 0,5 part achetée 200 €, valant 260 € → +30 €.
        #expect(abs(store.positionGain("TEST") - 30) < 0.01)
    }

    @Test("La réinitialisation ramène le solde de départ")
    func resetRestoresStartingCash() async throws {
        let store = makeStore()
        try store.demoBuy(symbol: "TEST", amountCents: 50_000)

        try await store.reset()

        #expect(store.source == .demo)
        #expect(store.cashCents == 100_000)
        #expect(store.positions.isEmpty)
    }
}
