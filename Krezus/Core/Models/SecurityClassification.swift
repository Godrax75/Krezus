import Foundation

/// Nature d'un titre, lue dans `securities.asset_type`.
enum AssetType: String, Sendable {
    case stock, etf
}

/// Famille de secteur (`securities.sector_group`, migration 0018).
///
/// `sector` compte 45 libellés pour 51 actions : trop fin pour trier ou
/// regrouper. Ces treize familles servent au marché comme à la répartition du
/// portefeuille. Les trois dernières n'ont de sens que pour les ETF.
enum SectorGroup: String, CaseIterable, Sendable {
    case technology, finance, consumer, industry, energy, health, auto,
         materials, telecom, realestate, broad, bonds, commodities

    var label: String { t("sector.\(rawValue)") }

    /// Repli tant que la colonne est vide — référentiel pas encore migré, ou
    /// catalogue de démonstration. Les mots-clés portent sur le libellé
    /// français de `sector`, la donnée de référence.
    static func guess(fromSector sector: String, isETF: Bool) -> SectorGroup {
        let s = sector.lowercased()
        if isETF {
            if s.contains("obligation") { return .bonds }
            if s.contains("matières") || s.contains("agricult") { return .commodities }
        }
        if s.contains("semi") || s.contains("logiciel") || s.contains("techno")
            || s.contains("internet") || s.contains("informatique") { return .technology }
        if s.contains("banqu") || s.contains("assur") || s.contains("paiement")
            || s.contains("financ") { return .finance }
        if s.contains("luxe") || s.contains("cosmét") || s.contains("boisson")
            || s.contains("agroalim") || s.contains("distribution") || s.contains("hôtel") { return .consumer }
        if s.contains("pétrole") || s.contains("énergie") || s.contains("eau") { return .energy }
        if s.contains("pharma") || s.contains("santé") || s.contains("optique")
            || s.contains("laborat") || s.contains("biotech") { return .health }
        if s.contains("auto") || s.contains("pneu") { return .auto }
        if s.contains("gaz") || s.contains("métaux") || s.contains("matériaux") { return .materials }
        if s.contains("télécom") || s.contains("publicité") { return .telecom }
        if s.contains("immobilier") { return .realestate }
        return isETF ? .broad : .industry
    }
}

/// Zone géographique d'exposition (`securities.region`, migration 0018).
///
/// Pour un ETF, c'est la zone où il investit : son `country_code` est son
/// pays de domiciliation, l'Irlande pour la plupart, sans rapport avec ce
/// qu'il détient.
enum Region: String, CaseIterable, Sendable {
    case fr, europe, us, asia_em, world

    var label: String { t("region.\(rawValue)") }

    /// Repli tant que la colonne est vide : le pays du siège pour une action,
    /// « monde » pour un ETF, faute de mieux.
    static func guess(countryCode: String, isETF: Bool) -> Region {
        if isETF { return .world }
        switch countryCode.uppercased() {
        case "FR": return .fr
        case "US": return .us
        default:   return .europe
        }
    }
}
