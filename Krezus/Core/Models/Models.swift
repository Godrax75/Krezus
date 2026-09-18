import Foundation

/// Modèles Codable alignés sur le schéma Postgres (`supabase/migrations/0001_init.sql`).
/// Les colonnes snake_case sont mappées via `CodingKeys`. Les montants monétaires
/// arrivent en centimes (Int) et sont convertis à l'affichage par `Money`.

struct Profile: Codable, Identifiable, Sendable {
    let id: UUID
    var username: String?
    var firstName: String?
    var lastName: String?
    var locale: String
    var darkMode: Bool
    var xp: Int
    var rankLevel: Int
    var streakDays: Int
    var premiumUntil: Date?
    /// Date de la dernière photo de profil ; nil = pas de photo.
    var avatarUpdatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, username, locale, xp
        case firstName = "first_name"
        case lastName = "last_name"
        case darkMode = "dark_mode"
        case rankLevel = "rank_level"
        case streakDays = "streak_days"
        case premiumUntil = "premium_until"
        case avatarUpdatedAt = "avatar_updated_at"
    }
}

struct Security: Codable, Identifiable, Sendable {
    var id: String { symbol }
    let symbol: String
    let eodhdSymbol: String?
    let currency: String
    let assetType: String
    let name: String
    let countryCode: String?
    let country: String?
    let sector: String?
    /// Libellé de secteur en anglais (`sector_en`, migration 0010). `sector`
    /// reste la donnée de référence en français : le regroupement du
    /// portefeuille s'appuie dessus.
    let sectorEn: String?
    let founded: String?
    let logoAsset: String?
    let initials: String?
    let dividendYield: Double?
    let marketCapLabel: String?
    let peRatio: Double?
    let pegRatio: Double?
    let ceo: String?
    let descriptionFr: String?
    let descriptionEn: String?
    let herculeNoteFr: String?
    let herculeNoteEn: String?

    enum CodingKeys: String, CodingKey {
        case symbol, currency, name, country, sector, founded, initials, ceo
        case eodhdSymbol = "eodhd_symbol"
        case sectorEn = "sector_en"
        case assetType = "asset_type"
        case countryCode = "country_code"
        case logoAsset = "logo_asset"
        case dividendYield = "dividend_yield"
        case marketCapLabel = "market_cap_label"
        case peRatio = "pe_ratio"
        case pegRatio = "peg_ratio"
        case descriptionFr = "description_fr"
        case descriptionEn = "description_en"
        case herculeNoteFr = "hercule_note_fr"
        case herculeNoteEn = "hercule_note_en"
    }
}

/// Cotation en cache. `price` est TOUJOURS en euros (devise de compte) : c'est
/// la valeur sur laquelle le moteur d'ordres calcule les parts. `priceNative`
/// garde le cours de cotation pour l'affichage — « 178,45 $ » pour Nvidia.
struct Quote: Codable, Sendable {
    let symbol: String
    let price: Double
    let priceNative: Double
    let currency: String
    let fxRate: Double
    let open: Double?
    let changePct: Double?
    let previousClose: Double?
    /// Horodatage de la cotation chez le fournisseur (différé 15 min).
    let quotedAt: Date?
    /// Horodatage de l'écriture en cache par la Edge Function.
    let fetchedAt: Date

    enum CodingKeys: String, CodingKey {
        case symbol, price, open, currency
        case priceNative = "price_native"
        case fxRate = "fx_rate"
        case changePct = "change_pct"
        case previousClose = "previous_close"
        case quotedAt = "quoted_at"
        case fetchedAt = "fetched_at"
    }
}

/// Point de la courbe quotidienne, dans la devise de cotation (non converti).
///
/// `date` reste une chaîne : la colonne Postgres est un `date` nu (« 2026-07-21 »),
/// que le décodeur de supabase-swift — réglé sur l'ISO 8601 horodaté — refuse
/// de lire comme `Date`. La conversion est explicite via `day`.
struct PricePoint: Codable, Sendable {
    let symbol: String
    let date: String
    let close: Double

    var day: Date? { PricePoint.formatter.date(from: date) }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

/// Taux de change différé. `rate` = unités de la devise cotée pour 1 EUR.
struct FxRate: Codable, Sendable {
    let pair: String
    let rate: Double
    let fetchedAt: Date

    enum CodingKeys: String, CodingKey {
        case pair, rate
        case fetchedAt = "fetched_at"
    }
}

struct Portfolio: Codable, Identifiable, Sendable {
    let id: UUID
    let userId: UUID
    let mode: String
    var cashCents: Int

    enum CodingKeys: String, CodingKey {
        case id, mode
        case userId = "user_id"
        case cashCents = "cash_cents"
    }
}

struct Position: Codable, Identifiable, Sendable {
    var id: String { symbol }
    let portfolioId: UUID
    let symbol: String
    let quantity: Double
    let avgCostCents: Int

    enum CodingKeys: String, CodingKey {
        case symbol, quantity
        case portfolioId = "portfolio_id"
        case avgCostCents = "avg_cost_cents"
    }
}

struct Order: Codable, Identifiable, Sendable {
    let id: UUID
    let portfolioId: UUID
    let symbol: String
    let side: String
    let amountCents: Int
    let quantity: Double
    let executedPrice: Double
    let status: String
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, symbol, side, quantity, status
        case portfolioId = "portfolio_id"
        case amountCents = "amount_cents"
        case executedPrice = "executed_price"
        case createdAt = "created_at"
    }
}

struct Lesson: Codable, Identifiable, Sendable {
    let id: UUID
    let position: Int
    let titleFr: String
    let titleEn: String?
    let durationLabel: String?
    let paragraphsFr: [String]
    let paragraphsEn: [String]?
    let examplesFr: [String]
    let examplesEn: [String]?
    let quizFr: Quiz?
    let quizEn: Quiz?
    let isFree: Bool

    /// Contenu servi dans la langue de l'interface, avec repli sur le français
    /// tant que la traduction n'est pas rédigée — une leçon lisible dans l'autre
    /// langue vaut mieux qu'un écran vide.
    var title: String { L10n.language == .en ? (titleEn ?? titleFr) : titleFr }
    var paragraphs: [String] { L10n.language == .en ? (paragraphsEn ?? paragraphsFr) : paragraphsFr }
    var examples: [String] { L10n.language == .en ? (examplesEn ?? examplesFr) : examplesFr }
    var quiz: Quiz? { L10n.language == .en ? (quizEn ?? quizFr) : quizFr }

    struct Quiz: Codable, Sendable {
        let q: String
        let opts: [String]
        let a: Int
        let why: String
    }

    enum CodingKeys: String, CodingKey {
        case id, position
        case titleFr = "title_fr"
        case titleEn = "title_en"
        case durationLabel = "duration_label"
        case paragraphsFr = "paragraphs_fr"
        case paragraphsEn = "paragraphs_en"
        case examplesFr = "examples_fr"
        case examplesEn = "examples_en"
        case quizFr = "quiz_fr"
        case quizEn = "quiz_en"
        case isFree = "is_free"
    }
}
