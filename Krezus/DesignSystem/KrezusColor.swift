import SwiftUI

/// Jetons de couleur Krezus, portés 1:1 depuis `colors_and_type.css` du design.
/// Chaque couleur a une variante claire et sombre ; le système bascule via le
/// `UITraitCollection` — pas de flag manuel à propager dans les vues.
enum KrezusColor {

    // MARK: Surfaces
    static let bg          = dynamic(light: 0xF7F8FC, dark: 0x0B0E1D)
    static let surface     = dynamic(light: 0xFFFFFF, dark: 0x161A2E)
    static let bgSoft      = dynamic(light: 0xFBFBFE, dark: 0x12162A)
    static let tint        = dynamic(light: 0xF2F4FB, dark: 0x1E2440)
    static let tintStrong  = dynamic(light: 0xE6EAF7, dark: 0x26315C)

    // MARK: Texte
    static let ink   = dynamic(light: 0x0A0D24, dark: 0xEEF1FB)
    static let fg2   = dynamic(light: 0x3B4161, dark: 0xC3C9E2)
    static let fg3   = dynamic(light: 0x6B7190, dark: 0x8C93B4)
    /// Gris le plus clair. Réservé aux **glyphes** — chevrons, cadenas, points
    /// d'attente : à ce niveau de contraste (3,5:1 en clair, 4,8:1 en sombre) il
    /// passe le seuil des composants d'interface, pas celui du texte. Toute
    /// chaîne lisible utilise `fg3` ou plus foncé.
    static let fg4   = dynamic(light: 0x7D839C, dark: 0x767DA0)

    // MARK: Bordures
    static let border  = dynamic(light: 0xD5D9E5, dark: 0x343C5E)
    static let divider = dynamic(light: 0xE4E6EF, dark: 0x252C4A)

    // MARK: Marque (navy)
    static let brandText = dynamic(light: 0x0F2572, dark: 0xA5B7FF)
    static let brandFill = dynamic(light: 0x0F2572, dark: 0x2E4BC6)
    static let navyDeep  = Color(hex: 0x081541)

    /// Or des illustrations d'onboarding, emprunté aux couronnes de laurier de
    /// la mascotte. Fixe dans les deux thèmes : il ne se pose jamais que sur le
    /// bleu profond, lui-même fixe.
    static let gold      = Color(hex: 0xDDB064)
    static let goldLight = Color(hex: 0xF4DCA2)

    // MARK: Accent (ambre)
    static let amberTint = dynamic(light: 0xFFE9DD, dark: 0x3A2A20)
    static let amberSoft = dynamic(light: 0xFFF6F0, dark: 0x2C231C)
    static let amberText = dynamic(light: 0xB8471E, dark: 0xFFA477)
    static let amber500  = Color(hex: 0xF7773E)
    static let amber600  = Color(hex: 0xE27243)

    // MARK: Sémantique marché
    // Le vert du design (#16A34A) ne donne que 3,3:1 sur blanc : illisible en
    // petit corps pour une variation de cours, qui est précisément une
    // information à lire. On retient la nuance profonde en thème clair.
    static let up     = dynamic(light: 0x15803D, dark: 0x4ADE80)
    static let upDeep = dynamic(light: 0x15803D, dark: 0x4ADE80)
    static let upBg   = dynamic(light: 0xE8F6ED, dark: 0x15301F)
    static let down   = dynamic(light: 0xDC2626, dark: 0xF87171)
    static let downBg = dynamic(light: 0xFDECEC, dark: 0x3A1D1D)

    /// Fond de la tab bar translucide (valeurs distinctes light/dark avec alpha).
    static let tabbar = dynamic(
        light: UIColor(white: 1, alpha: 0.82),
        dark: UIColor(red: 16/255, green: 20/255, blue: 38/255, alpha: 0.85)
    )

    // MARK: Dégradés signature
    static let gradientNavy = LinearGradient(
        colors: [Color(hex: 0x0F2572), Color(hex: 0x081541)],
        startPoint: .top, endPoint: .bottom)

    static let gradientAmber = LinearGradient(
        colors: [Color(hex: 0xFFB27A), Color(hex: 0xF7773E), Color(hex: 0xB8471E)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    // MARK: Fabriques
    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        dynamic(light: UIColor(hex: light), dark: UIColor(hex: dark))
    }

    private static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
}

extension Color {
    /// Couleur opaque depuis un entier hexadécimal 0xRRGGBB.
    init(hex: UInt32) {
        self.init(UIColor(hex: hex))
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha)
    }
}
