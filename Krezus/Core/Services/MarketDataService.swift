import Foundation

/// Accès aux données de marché côté app.
///
/// L'app ne parle jamais à EODHD : le jeton serait extractible du binaire et la
/// licence interdit de redistribuer le flux brut. Tout passe par le cache
/// Postgres alimenté par la Edge Function `quotes` (voir `supabase/functions/`).
///
/// Les cours sont **différés de 15 minutes** — la mention doit rester visible
/// partout où un prix est affiché (condition de redistribution EODHD).
@MainActor
final class MarketDataService {
    static let shared = MarketDataService()

    private let securities = SecuritiesRepository()

    private init() {}

    // MARK: Fraîcheur

    /// Le moteur d'ordres rejette une cotation de plus de 15 minutes (KR004).
    /// On qualifie l'état côté client pour prévenir l'utilisateur *avant* qu'il
    /// remplisse un formulaire d'achat qui échouera à la validation.
    /// `nonisolated` : cette constante est lue par `freshness(of:)`, elle-même
    /// appelable depuis n'importe quel contexte. L'isolation implicite au main
    /// actor deviendrait une erreur en mode Swift 6.
    nonisolated static let staleThreshold: TimeInterval = 15 * 60

    enum Freshness {
        /// Rafraîchie au dernier tick de la Edge Function.
        case live
        /// Encore acceptée par le moteur, mais le cache prend du retard.
        case lagging
        /// Au-delà du seuil : tout ordre sera rejeté.
        case stale

        var allowsTrading: Bool { self != .stale }
    }

    nonisolated static func freshness(of quote: Quote, now: Date = Date()) -> Freshness {
        let age = now.timeIntervalSince(quote.fetchedAt)
        if age < 120 { return .live }
        if age < staleThreshold { return .lagging }
        return .stale
    }

    // MARK: Cotations

    /// Cotations en cache des symboles demandés, indexées par symbole interne.
    func quotes(for symbols: [String]) async throws -> [String: Quote] {
        let wanted = Set(symbols)
        let rows = try await securities.fetchQuotes()
        return Dictionary(uniqueKeysWithValues:
            rows.filter { wanted.contains($0.symbol) }.map { ($0.symbol, $0) })
    }

    /// Historique quotidien d'un titre, du plus ancien au plus récent.
    ///
    /// Les points sont dans la **devise de cotation** (non convertis) : une
    /// courbe doit rester lisible dans sa propre unité, et reconvertir chaque
    /// point au taux du jour introduirait un mouvement de change parasite dans
    /// une courbe censée montrer le titre.
    func history(symbol: String, range: ChartRange) async throws -> [PricePoint] {
        let client = try SupabaseService.shared.requireClient()
        var query = client
            .from("price_history")
            .select()
            .eq("symbol", value: symbol)

        if let days = range.days,
           let from = Calendar.current.date(byAdding: .day, value: -days, to: Date()) {
            query = query.gte("date", value: Self.isoDay.string(from: from))
        }

        let points: [PricePoint] = try await query
            .order("date", ascending: true)
            .execute()
            .value
        return points
    }

    enum ChartRange: String, CaseIterable, Sendable {
        case month = "1M"
        case year = "1A"
        case all = "Tout"

        /// Profondeur en jours calendaires ; `nil` = tout l'historique connu.
        var days: Int? {
            switch self {
            case .month: return 31
            case .year:  return 366
            case .all:   return nil
            }
        }
    }

    /// Dernier taux de change connu (`EURUSD` = dollars pour 1 euro).
    func fxRate(pair: String = "EURUSD") async throws -> FxRate? {
        let client = try SupabaseService.shared.requireClient()
        let rows: [FxRate] = try await client
            .from("fx_rates")
            .select()
            .eq("pair", value: pair)
            .limit(1)
            .execute()
            .value
        return rows.first
    }

    private static let isoDay: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

// MARK: - Affichage

extension Quote {

    /// Vrai si le titre cote dans une autre devise que celle du compte.
    var isForeignCurrency: Bool { currency.uppercased() != "EUR" }

    /// Cours tel qu'il est coté sur sa place — « 178,45 $ » pour Nvidia.
    /// C'est ce que l'utilisateur retrouve sur n'importe quel site boursier ;
    /// afficher l'équivalent euro à la place serait déroutant.
    var nativeLabel: String { Money.amount(priceNative, currency: currency) }

    /// Contrepartie en euros — « 164,59 € ». C'est la valeur sur laquelle
    /// l'ordre est réellement exécuté.
    var accountLabel: String { Money.euros(price) }

    /// Libellé complet d'un titre étranger : « 178,45 $ · 164,59 € ».
    var priceLabel: String {
        isForeignCurrency ? "\(nativeLabel) · \(accountLabel)" : accountLabel
    }
}
