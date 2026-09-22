import Foundation
import Supabase
import PostgREST

/// Lecture du référentiel titres et des cotations en cache (différé 15 min).
/// Le rafraîchissement du cache est fait par la Edge Function `quotes` (Lot 3),
/// pas par le client.
@MainActor
struct SecuritiesRepository {

    /// PostgREST plafonne une réponse à 1 000 lignes : le référentiel les
    /// dépasse depuis l'entrée du S&P 500, d'où la lecture par pages.
    private static let pageSize = 1_000

    /// Colonnes du catalogue, description exclue.
    ///
    /// Les fiches pèsent quelques centaines de caractères chacune : sur mille
    /// deux cents titres, les embarquer au lancement ajouterait près d'un
    /// mégaoctet à chaque ouverture de l'app, pour un texte qu'on ne lit que
    /// sur la fiche d'une action. Elles se chargent donc à l'ouverture de
    /// celle-ci (`fetch(symbol:)`).
    private static let listColumns = "symbol, eodhd_symbol, currency, asset_type, name, country_code, country, sector, sector_en, sector_group, region, founded, logo_asset, logo_url, initials, dividend_yield, market_cap_label, pe_ratio, peg_ratio, ceo"

    func fetchAll() async throws -> [Security] {
        let client = try SupabaseService.shared.requireClient()
        return try await fetchPaged { from, to in
            client.from("securities")
                .select(Self.listColumns)
                .order("name", ascending: true)
                .range(from: from, to: to)
        }
    }

    func fetch(symbol: String) async throws -> Security {
        let client = try SupabaseService.shared.requireClient()
        return try await client
            .from("securities")
            .select()
            .eq("symbol", value: symbol)
            .single()
            .execute()
            .value
    }

    /// Toutes les cotations en cache.
    ///
    /// Le cache compte une ligne par titre du référentiel : les filtrer par
    /// symbole mettrait cinq cents valeurs dans l'URL, pour le même résultat.
    func fetchQuotes() async throws -> [Quote] {
        let client = try SupabaseService.shared.requireClient()
        return try await fetchPaged { from, to in
            client.from("quotes_cache")
                .select()
                .range(from: from, to: to)
        }
    }

    /// Cotations de quelques titres seulement : après un rafraîchissement à
    /// la demande, inutile de relire tout le cache.
    func fetchQuotes(symbols: [String]) async throws -> [Quote] {
        guard !symbols.isEmpty else { return [] }
        let client = try SupabaseService.shared.requireClient()
        return try await client
            .from("quotes_cache")
            .select()
            .in("symbol", values: symbols)
            .execute()
            .value
    }

    /// Demande au serveur de rafraîchir ces cotations (`quote-refresh`) : le
    /// cron ne tient plus tout le catalogue à la minute, il faut un cours
    /// frais au moment de consulter ou d'acheter un titre.
    func requestRefresh(symbols: [String]) async throws {
        struct Body: Encodable { let symbols: [String] }
        let client = try SupabaseService.shared.requireClient()
        try await client.functions.invoke(
            "quote-refresh", options: FunctionInvokeOptions(body: Body(symbols: symbols)))
    }

    private func fetchPaged<T: Decodable>(
        _ page: (Int, Int) -> PostgrestTransformBuilder
    ) async throws -> [T] {
        var all: [T] = []
        var offset = 0
        while true {
            let rows: [T] = try await page(offset, offset + Self.pageSize - 1).execute().value
            all.append(contentsOf: rows)
            if rows.count < Self.pageSize { return all }
            offset += Self.pageSize
        }
    }
}

/// Lecture des leçons Academy (contenu seedé depuis le prototype).
@MainActor
struct LessonRepository {
    func fetchAll() async throws -> [Lesson] {
        let client = try SupabaseService.shared.requireClient()
        return try await client
            .from("lessons")
            .select()
            .order("position", ascending: true)
            .execute()
            .value
    }
}
