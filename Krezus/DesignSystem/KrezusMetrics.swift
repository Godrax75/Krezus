import SwiftUI

/// Rayons, espacements et ombres — portés du design (grille 4px, 4 niveaux d'ombre).
enum KrezusRadius {
    static let xs: CGFloat = 6
    static let sm: CGFloat = 10
    static let md: CGFloat = 14
    static let lg: CGFloat = 20
    static let xl: CGFloat = 28
    static let pill: CGFloat = 999
}

enum KrezusSpacing {
    static let s1: CGFloat = 4
    static let s2: CGFloat = 8
    static let s3: CGFloat = 12
    static let s4: CGFloat = 16
    static let s5: CGFloat = 20
    static let s6: CGFloat = 24
}

/// Ombres teintées navy (rgba(15,37,114,·)). SwiftUI ne compose pas plusieurs
/// ombres nativement ; on garde le stop principal de chaque niveau du design.
enum KrezusShadow {
    struct Spec {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
    }

    static let level1 = Spec(color: Color(hex: 0x0F2572).opacity(0.06), radius: 2, x: 0, y: 1)
    static let level2 = Spec(color: Color(hex: 0x0F2572).opacity(0.08), radius: 12, x: 0, y: 4)
    static let level3 = Spec(color: Color(hex: 0x0F2572).opacity(0.12), radius: 32, x: 0, y: 12)
    static let brand  = Spec(color: Color(hex: 0x0F2572).opacity(0.25), radius: 24, x: 0, y: 10)
}

extension View {
    func krezusShadow(_ spec: KrezusShadow.Spec) -> some View {
        self.shadow(color: spec.color, radius: spec.radius, x: spec.x, y: spec.y)
    }
}
