import SwiftUI
import Observation

/// Fiche titre telle que l'affichent les écrans, quelle qu'en soit la source :
/// le catalogue de démonstration ou la table `securities` de Supabase.
struct StockInfo: Identifiable, Sendable {
    var id: String { symbol }
    let symbol: String
    let name: String
    let cc: String            // code pays (US, FR…)
    /// Secteur tel qu'il est écrit dans `securities.sector`, en français. C'est
    /// une donnée de référence, pas un libellé d'affichage : le regroupement du
    /// portefeuille s'appuie dessus (voir `TradingStore.groupOf`).
    let sector: String
    /// Traduction anglaise du secteur, purement d'affichage (`sector_en`).
    /// `nil` = pas encore traduit, on retombe sur le français.
    var sectorEn: String?
    let founded: String
    /// Rendement du dividende en pourcentage (2,9 = 2,9 %). `nil` = non publié.
    ///
    /// Ces trois ratios étaient stockés en texte déjà mis en forme à la
    /// française (« 2,9 % », « 22,4 ») : illisible en anglais, et l'Oracle
    /// devait les reparser pour calculer une médiane. La donnée est un nombre ;
    /// sa mise en forme appartient à l'affichage.
    let dividendYield: Double?
    /// Libellé de capitalisation (« 112 Md€ ») : une échelle, pas un nombre nu.
    let mcap: String
    let pe: Double?
    let peg: Double?
    let ceo: String
    /// Textes éditoriaux : la version française est la rédaction d'origine, la
    /// version anglaise vient en regard. `nil` = pas encore traduit, on retombe
    /// alors sur le français plutôt que d'afficher un blanc.
    let what: String
    let hercule: String
    var whatEn: String?
    var herculeEn: String?
    let logoAsset: String?
    let initials: String
    let tileHex: UInt32
    let open: Double
    var price: Double

    /// Vrai quand le titre a une cotation exploitable.
    ///
    /// Un titre sans cotation n'a pas un cours de 0 € : il a un cours **inconnu**.
    /// Les 30 ETF du référentiel n'ont pas encore de symbole EODHD, et sur le
    /// plan gratuit on ne rafraîchit qu'une poignée de titres par jour — le cas
    /// est donc la règle plutôt que l'exception.
    var hasQuote: Bool { price > 0 }

    /// Variation du jour en %, `nil` quand elle n'a pas de sens.
    ///
    /// Sans cotation, `price` et `open` valent tous deux 0 : la division donnait
    /// `0 / 0`, soit NaN, affiché tel quel à l'écran (« –NaN% »). Renvoyer 0 à la
    /// place serait un autre mensonge — « inchangé » et « cours inconnu » ne
    /// sont pas la même information.
    var changePct: Double? {
        guard hasQuote, open > 0 else { return nil }
        return (price - open) / open * 100
    }

    /// Le secteur dans la langue de l'interface. À n'utiliser qu'à l'affichage :
    /// tout ce qui compare ou regroupe des secteurs lit `sector`.
    var sectorLocalized: String {
        L10n.language == .en ? (sectorEn ?? sector) : sector
    }

    /// « Que fait l'entreprise ? » dans la langue de l'interface.
    var whatLocalized: String {
        L10n.language == .en ? (whatEn ?? what) : what
    }

    /// L'éclairage d'Hercule dans la langue de l'interface.
    var herculeLocalized: String {
        L10n.language == .en ? (herculeEn ?? hercule) : hercule
    }
}

extension StockInfo {
    /// Construit la fiche depuis le référentiel serveur et sa cotation en cache.
    ///
    /// Les colonnes facultatives retombent sur le tiret cadratin utilisé partout
    /// dans l'app pour « donnée non publiée » : un champ vide laisserait croire
    /// à un bug d'affichage.
    init(security: Security, quote: Quote?) {
        // `price` est déjà converti en euros par la Edge Function ; `open` sert
        // uniquement à calculer la variation du jour, d'où le repli en cascade
        // sur la clôture de la veille puis sur le cours courant (variation nulle
        // plutôt que -100 % au premier chargement d'un titre sans historique).
        let price = quote?.price ?? 0
        self.init(
            symbol: security.symbol,
            name: security.name,
            cc: security.countryCode ?? "",
            sector: security.sector ?? "",
            sectorEn: security.sectorEn,
            founded: security.founded ?? "—",
            dividendYield: security.dividendYield,
            mcap: security.marketCapLabel ?? "—",
            pe: security.peRatio,
            peg: security.pegRatio,
            ceo: security.ceo ?? "—",
            what: security.descriptionFr ?? "",
            hercule: security.herculeNoteFr ?? "",
            whatEn: security.descriptionEn,
            herculeEn: security.herculeNoteEn,
            logoAsset: security.logoAsset,
            initials: security.initials ?? Self.initials(from: security.name),
            tileHex: Self.tileColor(for: security.symbol),
            open: quote?.open ?? quote?.previousClose ?? price,
            price: price)
    }

    /// Deux lettres de repli quand le référentiel n'en fournit pas.
    static func initials(from name: String) -> String {
        String(name.replacingOccurrences(of: " ", with: "").prefix(2)).uppercased()
    }

    /// Couleur de pastille dérivée du symbole : stable d'un lancement à l'autre,
    /// et distincte d'un titre à l'autre sans qu'il faille la stocker en base.
    /// Utilisée uniquement quand aucun logo n'est embarqué.
    static func tileColor(for symbol: String) -> UInt32 {
        let palette: [UInt32] = [0x1F2A44, 0x0F3D6E, 0x0D1B3C, 0x5A3210, 0xB01818,
                                 0x14324F, 0x1C1C1E, 0x2E7D32, 0x00875A, 0x1B3A6B,
                                 0x6A2C8F, 0x0072CE]
        let hash = symbol.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFFFF }
        return palette[hash % palette.count]
    }
}

/// Portefeuille papier et catalogue de titres — la source unique des écrans.
///
/// Deux sources possibles derrière la même interface :
///
/// - **démo** (aucun secret Supabase, ou session absente) : catalogue embarqué,
///   prix simulés par marche aléatoire, ordres exécutés en mémoire ;
/// - **serveur** : référentiel `securities`, cotations `quotes_cache` différées
///   de 15 minutes, et ordres passés par les fonctions transactionnelles
///   `execute_paper_buy` / `_sell`.
///
/// Le calcul monétaire n'est **jamais** refait côté client en mode serveur :
/// rejouer une requête ne doit pas pouvoir fabriquer du cash. Le miroir local
/// n'existe que pour le mode démo, où il n'y a pas de serveur à tromper.
@MainActor
@Observable
final class TradingStore {

    enum Source: Equatable { case demo, server }

    private(set) var source: Source = .demo
    private(set) var isLoading = false
    /// Dernière erreur de chargement, affichable ; les erreurs d'ordre sont
    /// levées à l'appelant, qui les montre dans son propre formulaire.
    private(set) var lastError: String?

    private(set) var catalog: [StockInfo] = DemoCatalog.stocks
    private(set) var cashCents: Int = 100_000                 // 1 000,00 €
    /// symbole -> (quantité, coût de revient moyen en centimes/part)
    private(set) var positions: [String: (qty: Double, avgCostCents: Int)] = [:]

    private var ticker: Timer?

    // Mode serveur
    private let portfolioRepo = PortfolioRepository()
    private let securitiesRepo = SecuritiesRepository()
    private var userID: UUID?
    private var securities: [Security] = []
    private var quotes: [String: Quote] = [:]

    init() { seedInitialPositions() }

    // MARK: Source de données

    /// Bascule sur le serveur pour l'utilisateur connecté et charge tout.
    func connect(userID: UUID) async {
        guard AppConfig.isConfigured else { return }
        self.userID = userID
        source = .server
        await reload()
        restartTicker()
    }

    /// Repasse en démo — déconnexion, ou app non configurée.
    func disconnect() {
        userID = nil
        source = .demo
        securities = []
        quotes = [:]
        catalog = DemoCatalog.stocks
        cashCents = 100_000
        positions = [:]
        lastError = nil
        seedInitialPositions()
        restartTicker()
    }

    /// Recharge référentiel, portefeuille, positions et cotations.
    func reload() async {
        guard source == .server, let userID else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let portfolio = try await portfolioRepo.fetchPortfolio(userID: userID)
            let rows = try await portfolioRepo.fetchPositions(portfolioID: portfolio.id)
            securities = try await securitiesRepo.fetchAll()

            cashCents = portfolio.cashCents
            positions = Dictionary(uniqueKeysWithValues: rows.map {
                ($0.symbol, (qty: $0.quantity, avgCostCents: $0.avgCostCents))
            })
            try await refreshQuotes()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Rafraîchit les seules cotations — c'est ce que fait le tick en mode
    /// serveur, plutôt que de retélécharger le référentiel toutes les minutes.
    private func refreshQuotes() async throws {
        let rows = try await securitiesRepo.fetchQuotes(symbols: securities.map(\.symbol))
        quotes = Dictionary(uniqueKeysWithValues: rows.map { ($0.symbol, $0) })
        catalog = securities.map { StockInfo(security: $0, quote: quotes[$0.symbol]) }
    }

    // MARK: Fraîcheur des cotations

    /// Cotation en cache d'un titre, en mode serveur uniquement.
    func quote(_ symbol: String) -> Quote? { quotes[symbol] }

    /// Vrai quand le cours est trop vieux pour que le moteur accepte un ordre
    /// (KR004). On le sait avant que l'utilisateur remplisse le formulaire ;
    /// le laisser saisir un montant pour échouer à l'envoi serait cruel.
    func isTradable(_ symbol: String) -> Bool {
        guard source == .server else { return true }
        guard let quote = quotes[symbol] else { return false }
        return MarketDataService.freshness(of: quote).allowsTrading
    }

    // MARK: Requêtes

    func stock(_ symbol: String) -> StockInfo? { catalog.first { $0.symbol == symbol } }
    func quantity(_ symbol: String) -> Double { positions[symbol]?.qty ?? 0 }
    func owns(_ symbol: String) -> Bool { (positions[symbol]?.qty ?? 0) > 0 }

    /// Valeur de marché d'une position (euros).
    func positionValue(_ symbol: String) -> Double {
        guard let p = positions[symbol], let s = stock(symbol) else { return 0 }
        return p.qty * s.price
    }

    /// Plus/moins-value d'une position (euros).
    func positionGain(_ symbol: String) -> Double {
        guard let p = positions[symbol] else { return 0 }
        return positionValue(symbol) - p.qty * Double(p.avgCostCents) / 100
    }

    var holdingSymbols: [String] {
        positions.keys.sorted { positionValue($0) > positionValue($1) }
    }

    /// Valeur totale = cash + valeur de marché des positions (centimes).
    var totalValueCents: Int {
        let holdings = positions.keys.reduce(0.0) { $0 + positionValue($1) }
        return cashCents + Int((holdings * 100).rounded())
    }

    /// Variation du jour du portefeuille, en % (pondérée par les positions).
    var dayChangePct: Double {
        var value = 0.0, base = 0.0
        for (sym, p) in positions {
            guard let s = stock(sym) else { continue }
            value += p.qty * s.price
            base += p.qty * s.open
        }
        guard base > 0 else { return 0 }
        return (value - base) / base * 100
    }

    /// Répartition par secteur (label, part 0…1) pour l'écran Portefeuille.
    var allocation: [(label: String, pct: Double)] {
        let byGroup = Dictionary(grouping: positions.keys) { sym in
            groupOf(stock(sym)?.sector ?? "")
        }
        let total = positions.keys.reduce(0.0) { $0 + positionValue($1) }
        guard total > 0 else { return [] }
        return byGroup.map { (label, syms) in
            (label, syms.reduce(0.0) { $0 + positionValue($1) } / total)
        }.sorted { $0.pct > $1.pct }
    }

    // MARK: Ordres

    enum OrderError: LocalizedError {
        case insufficientFunds, noPosition, unknownStock, notSignedIn
        var errorDescription: String? {
            switch self {
            case .insufficientFunds: return t("order.error.insufficient_funds")
            case .noPosition:        return t("order.error.no_position")
            case .unknownStock:      return t("order.error.unknown_stock")
            case .notSignedIn:       return t("order.error.not_signed_in")
            }
        }
    }

    /// Achat pour un montant en centimes.
    ///
    /// En mode serveur, l'ordre part vers `execute_paper_buy` et l'état est
    /// relu : le client n'écrit rien lui-même, il constate. C'est plus lent
    /// d'un aller-retour, et c'est le prix d'un solde qu'on ne peut pas forger.
    func buy(symbol: String, amountCents: Int) async throws {
        switch source {
        case .demo:
            try demoBuy(symbol: symbol, amountCents: amountCents)
        case .server:
            guard let userID else { throw OrderError.notSignedIn }
            try await portfolioRepo.buy(userID: userID, symbol: symbol, amountCents: amountCents)
            await reload()
        }
    }

    /// Vente d'un pourcentage (1…100) de la position.
    func sell(symbol: String, pct: Int) async throws {
        switch source {
        case .demo:
            try demoSell(symbol: symbol, pct: pct)
        case .server:
            guard let userID else { throw OrderError.notSignedIn }
            try await portfolioRepo.sell(userID: userID, symbol: symbol, pct: pct)
            await reload()
        }
    }

    func reset() async throws {
        switch source {
        case .demo:
            positions.removeAll()
            cashCents = 100_000
            seedInitialPositions()
        case .server:
            guard let userID else { throw OrderError.notSignedIn }
            try await portfolioRepo.reset(userID: userID)
            await reload()
        }
    }

    // MARK: Moteur local (mode démo uniquement)

    /// Miroir du moteur serveur `execute_paper_buy`, pour le mode démo.
    /// Les deux doivent rester d'accord : c'est ce que vérifient
    /// `PaperOrderTests` côté Swift et `paper_engine_test.sql` côté Postgres.
    @discardableResult
    func demoBuy(symbol: String, amountCents: Int) throws -> Double {
        guard let s = stock(symbol) else { throw OrderError.unknownStock }
        guard amountCents > 0, amountCents <= cashCents else { throw OrderError.insufficientFunds }
        let qty = Self.roundedQuantity((Double(amountCents) / 100) / s.price)
        cashCents -= amountCents
        if let existing = positions[symbol] {
            let newQty = existing.qty + qty
            let newAvg = Int(((existing.qty * Double(existing.avgCostCents) + Double(amountCents)) / newQty).rounded())
            positions[symbol] = (newQty, newAvg)
        } else {
            positions[symbol] = (qty, Int((Double(amountCents) / qty).rounded()))
        }
        return qty
    }

    /// Miroir du moteur serveur `execute_paper_sell`.
    @discardableResult
    func demoSell(symbol: String, pct: Int) throws -> Int {
        guard let p = positions[symbol], let s = stock(symbol) else { throw OrderError.noPosition }
        let sellQty = pct >= 100 ? p.qty : Self.roundedQuantity(p.qty * Double(pct) / 100)
        let proceeds = Int((sellQty * s.price * 100).rounded())
        cashCents += proceeds
        let remaining = p.qty - sellQty
        if pct >= 100 || remaining <= 0.00000001 {
            positions[symbol] = nil
        } else {
            positions[symbol] = (remaining, p.avgCostCents)
        }
        return proceeds
    }

    /// Quantité arrondie à 8 décimales, comme `round(…, 8)` dans
    /// `execute_paper_buy`. Sans cet arrondi, le miroir local et le moteur
    /// serveur divergent dès la première décimale perdue, et un portefeuille
    /// migré de la démo vers un compte n'aurait pas exactement les mêmes parts.
    static func roundedQuantity(_ value: Double) -> Double {
        (value * 100_000_000).rounded() / 100_000_000
    }

    // MARK: Rafraîchissement périodique

    /// Démarre le tick correspondant à la source courante : marche aléatoire
    /// toutes les 2,5 s en démo (le prototype le faisait déjà), relecture du
    /// cache toutes les 60 s en mode serveur — la Edge Function `quotes` ne
    /// l'alimente pas plus vite, interroger davantage ne ferait que consommer.
    func startLiveTicks() {
        guard ticker == nil else { return }
        restartTicker()
    }

    func stopLiveTicks() { ticker?.invalidate(); ticker = nil }

    private func restartTicker() {
        ticker?.invalidate()
        let interval: TimeInterval = source == .demo ? 2.5 : 60
        ticker = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.tick() }
        }
    }

    private func tick() async {
        switch source {
        case .demo:
            for i in catalog.indices {
                let drift = Double.random(in: -0.004...0.004)
                catalog[i].price = max(0.01, catalog[i].price * (1 + drift))
            }
        case .server:
            try? await refreshQuotes()
        }
    }

    // MARK: Privé

    private func seedInitialPositions() {
        // Position de départ = « coffret » d'activation, comme dans le prototype.
        if let nvda = stock("NVDA") {
            let amount = Int((nvda.price * 0.45 * 100).rounded())
            positions["NVDA"] = (0.45, Int((Double(amount) / 0.45).rounded()))
            cashCents -= amount
        }
        if let ai = stock("AI") {
            let amount = Int((ai.price * 0.21 * 100).rounded())
            positions["AI"] = (0.21, Int((Double(amount) / 0.21).rounded()))
            cashCents -= amount
        }
    }

    /// Regroupe les secteurs en cinq familles. Le test porte sur le libellé
    /// français de `securities.sector` — c'est la donnée, pas de l'affichage ;
    /// seul le libellé rendu est traduit.
    private func groupOf(_ sector: String) -> String {
        let s = sector.lowercased()
        if s.contains("semi") || s.contains("logiciel") || s.contains("techno") || s.contains("internet") {
            return t("sector.technology")
        }
        if s.contains("luxe") { return t("sector.luxury") }
        if s.contains("banqu") || s.contains("assur") { return t("sector.finance") }
        if s.contains("énergie") || s.contains("pétrole") || s.contains("gaz") { return t("sector.energy") }
        return t("sector.industry")
    }
}

#if DEBUG
extension TradingStore {
    /// Points d'accès réservés aux tests unitaires.
    ///
    /// `catalog`, `cashCents` et `positions` sont en lecture seule pour les vues
    /// — c'est le moteur qui les fait bouger, et c'est bien l'intérêt. Les tests
    /// ont malgré tout besoin de partir d'un portefeuille connu, avec un cours
    /// fixe : sans ce point d'entrée, chaque assertion dépendrait du tirage
    /// aléatoire de la simulation. Compilé hors du binaire livré.
    func resetForTesting(cashCents: Int, catalog: [StockInfo]) {
        stopLiveTicks()
        source = .demo
        self.catalog = catalog
        self.cashCents = cashCents
        positions = [:]
    }

    /// Fixe le cours d'un titre pour observer un gain ou une perte décidés.
    func setPriceForTesting(symbol: String, price: Double) {
        guard let index = catalog.firstIndex(where: { $0.symbol == symbol }) else { return }
        catalog[index].price = price
    }
}
#endif
