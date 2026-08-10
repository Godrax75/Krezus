import Foundation
import Supabase

/// Lecture du référentiel titres et des cotations en cache (différé 15 min).
/// Le rafraîchissement du cache est fait par la Edge Function `quotes` (Lot 3),
/// pas par le client.
@MainActor
struct SecuritiesRepository {

    func fetchAll() async throws -> [Security] {
        let client = try SupabaseService.shared.requireClient()
        return try await client
            .from("securities")
            .select()
            .order("name", ascending: true)
            .execute()
            .value
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

    /// Cotations en cache pour un ensemble de symboles (un seul aller-retour).
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
