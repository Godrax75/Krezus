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
    case technology, finance, consumer, industry, energy, utilities, health, auto,
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
        // L'eau, l'électricité et le gaz distribués sont des services
        // régulés : ils ne suivent pas le baril.
        if s.contains("collectivit") || s.contains("électricité-distribution")
            || s.contains("environnement") { return .utilities }
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

/// Zone géographique affichée dans « Explorer » : le filtre et le
/// regroupement par zone.
///
/// Plus fine que `Region` (cinq grandes familles, qui sert au calcul de
/// l'exposition du portefeuille) : avec plus de mille titres, « Europe »
/// ou « Asie et émergents » ne suffisent plus à s'y retrouver. Une action
/// est rangée selon le pays de son siège ; un ETF selon ce qu'il détient,
/// son pays de domiciliation (souvent l'Irlande) ne disant rien de son
/// exposition.
enum MarketZone: String, CaseIterable, Identifiable, Sendable {
    case france, europe, usa, americas, japan, china, asiaPacific, world

    var id: String { rawValue }
    var label: String { t("zone.\(rawValue)") }

    var emoji: String {
        switch self {
        case .france:      return "🇫🇷"
        case .europe:      return "🇪🇺"
        case .usa:         return "🇺🇸"
        case .americas:    return "🌎"
        case .japan:       return "🇯🇵"
        case .china:       return "🇨🇳"
        case .asiaPacific: return "🌏"
        case .world:       return "🌐"
        }
    }

    private static let europeCodes: Set<String> = [
        "AT", "BE", "CH", "CY", "CZ", "DE", "DK", "EE", "ES", "FI", "GB", "GR", "HU",
        "IE", "IS", "IT", "JE", "LT", "LU", "LV", "MC", "MT", "NL", "NO", "PL", "PT",
        "RO", "SE", "SI", "SK",
    ]
    private static let americasCodes: Set<String> = ["CA", "BR", "MX", "AR", "CL", "CO", "PE", "UY"]
    private static let chinaCodes: Set<String> = ["CN", "HK", "MO"]
    private static let asiaPacificCodes: Set<String> = [
        "KR", "TW", "IN", "SG", "AU", "NZ", "ID", "TH", "MY", "PH", "VN", "IL", "AE", "SA",
    ]

    static func of(countryCode: String, region: Region, isETF: Bool) -> MarketZone {
        if isETF {
            switch region {
            case .fr:      return .france
            case .europe:  return .europe
            case .us:      return .usa
            case .asia_em: return .asiaPacific
            case .world:   return .world
            }
        }
        let code = countryCode.uppercased()
        if code == "FR" { return .france }
        if code == "US" { return .usa }
        if code == "JP" { return .japan }
        if europeCodes.contains(code) { return .europe }
        if americasCodes.contains(code) { return .americas }
        if chinaCodes.contains(code) { return .china }
        if asiaPacificCodes.contains(code) { return .asiaPacific }
        return .world
    }
}
