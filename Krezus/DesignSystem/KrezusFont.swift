import SwiftUI

/// Typographie Krezus.
///
/// Le design utilise **Plus Jakarta Sans** (display + chiffres, tabular) et
/// **Inter** (corps). Ces fontes (SIL OFL, redistribuables) sont à embarquer
/// dans `Resources/Fonts/` puis déclarées dans `UIAppFonts` — voir README.
///
/// En attendant l'embarquement, on retombe sur les fontes système : SF Rounded
/// pour le display (rendu géométrique proche du Plus Jakarta) et SF pour le corps.
/// `displayName` / `bodyName` sont les seuls points à changer une fois les
/// fontes réelles présentes.
///
/// **Dynamic Type.** Le design est spécifié en points fixes, et
/// `Font.system(size:)` ne suit pas le réglage de taille de texte d'iOS : une
/// app entière en tailles figées est inutilisable pour qui a besoin de gros
/// caractères. Chaque taille est donc mise à l'échelle par `UIFontMetrics`,
/// rattachée au style de texte le plus proche pour que la hiérarchie du design
/// se conserve aux grandes tailles. Le facteur est plafonné : au-delà, les
/// nombres à quatre chiffres du portefeuille cassent leurs lignes.
enum KrezusFont {

    /// Nom PostScript de la fonte display embarquée, ou nil pour la fonte système.
    static let displayName: String? = nil   // ex. "PlusJakartaSans-Bold" une fois embarquée
    static let bodyName: String? = nil       // ex. "Inter-Regular"

    /// Plafond d'agrandissement. À AX5 (la plus grande taille d'accessibilité),
    /// `UIFontMetrics` multiplie par ~3,1 : un titre de 34 pt passerait à 105 pt,
    /// soit deux caractères par ligne. 1,6 laisse un gain net et lisible.
    private static let maxScale: CGFloat = 1.6

    // MARK: Display (Plus Jakarta Sans) — titres et chiffres
    static func display(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        if let name = displayName {
            return .custom(name, size: size, relativeTo: textStyle(for: size))
        }
        return .system(size: scaled(size), weight: weight, design: .rounded)
    }

    // MARK: Corps (Inter)
    static func body(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        if let name = bodyName {
            return .custom(name, size: size, relativeTo: textStyle(for: size))
        }
        return .system(size: scaled(size), weight: weight, design: .default)
    }

    // MARK: Échelle sémantique (tailles portées du design)
    static var h1: Font        { display(24, .heavy) }   // titres d'écran « Krezus Forum »
    static var totalValue: Font { display(34, .heavy) }  // valeur du portefeuille (home)
    static var portfolio: Font { display(32, .heavy) }
    static var cardTitle: Font { display(15, .bold) }
    static var stockName: Font { display(14.5, .bold) }
    static var numeric: Font   { display(14.5, .bold) }
    static var wordmark: Font  { display(20, .heavy) }

    static var bodyMd: Font    { body(13.5) }
    static var bodySm: Font    { body(12.5) }
    static var caption: Font   { body(11) }

    // MARK: Mise à l'échelle

    /// Taille du design, mise à l'échelle selon le réglage système et plafonnée.
    private static func scaled(_ size: CGFloat) -> CGFloat {
        let metrics = UIFontMetrics(forTextStyle: uiTextStyle(for: size))
        return min(metrics.scaledValue(for: size), size * maxScale)
    }

    /// Style de texte de référence, choisi par proximité de taille : il fixe la
    /// courbe d'agrandissement (les titres grossissent moins vite que le corps).
    private static func uiTextStyle(for size: CGFloat) -> UIFont.TextStyle {
        switch size {
        case 30...:    return .largeTitle
        case 22..<30:  return .title1
        case 19..<22:  return .title2
        case 16..<19:  return .title3
        case 14..<16:  return .body
        case 12.5..<14: return .subheadline
        case 11..<12.5: return .footnote
        default:       return .caption1
        }
    }

    private static func textStyle(for size: CGFloat) -> Font.TextStyle {
        switch uiTextStyle(for: size) {
        case .largeTitle:  return .largeTitle
        case .title1:      return .title
        case .title2:      return .title2
        case .title3:      return .title3
        case .body:        return .body
        case .subheadline: return .subheadline
        case .footnote:    return .footnote
        default:           return .caption
        }
    }
}

extension View {
    /// Chiffres alignés (tabular) — pour les prix, montants, variations.
    func tabularNumbers() -> some View {
        self.monospacedDigit()
    }
}
