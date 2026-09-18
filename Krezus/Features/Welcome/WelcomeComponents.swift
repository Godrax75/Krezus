import SwiftUI

// Briques partagées par l'accueil et la célébration du versement
// hebdomadaire : fond bleu nuit, montant qui défile, gerbe de confettis,
// bouton blanc.

// MARK: - Fond

/// Bleu profond de la marque, éclairé d'un halo au centre et d'une lueur
/// violette en bas à gauche : le décor de l'onboarding illustré, sans image.
struct WelcomeBackground: View {
    var body: some View {
        ZStack {
            KrezusColor.navyDeep
            RadialGradient(colors: [Color(hex: 0x2A3590).opacity(0.85), .clear],
                           center: UnitPoint(x: 0.5, y: 0.32), startRadius: 10, endRadius: 420)
            RadialGradient(colors: [Color(hex: 0x4A1F5C).opacity(0.55), .clear],
                           center: UnitPoint(x: 0.1, y: 0.78), startRadius: 10, endRadius: 320)
            LinearGradient(colors: [.clear, Color(hex: 0x050B26).opacity(0.9)],
                           startPoint: UnitPoint(x: 0.5, y: 0.6), endPoint: .bottom)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Montant qui défile

/// Montant en euros qui s'anime d'une valeur à l'autre, chiffre après
/// chiffre : `Animatable` interpole la valeur, le texte suit à chaque image.
struct CountingEuros: View, Animatable {
    var cents: Double
    var font: Font = KrezusFont.display(72, .heavy)

    var animatableData: Double {
        get { cents }
        set { cents = newValue }
    }

    var body: some View {
        Text(Money.eurosShort((cents / 100).rounded()))
            .font(font)
            .foregroundStyle(.white)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }
}

// MARK: - Gerbe

/// Confettis et pièces projetés depuis le centre, une seule fois, quand
/// `fired` passe à vrai.
struct CelebrationBurst: View {
    let fired: Bool
    var count = 34

    private struct Piece: Identifiable {
        let id: Int
        let angle: Double
        let distance: CGFloat
        let size: CGFloat
        let color: Color
        let spin: Double
        let isCoin: Bool
    }

    private let pieces: [Piece] = {
        var generator = BurstGenerator(seed: 7)
        let colors: [Color] = [KrezusColor.gold, .white, Color(hex: 0x7C8CFF),
                               Color(hex: 0x4ADE80), Color(hex: 0xF5C451)]
        return (0..<34).map { index in
            Piece(id: index,
                  angle: Double(index) / 34 * 2 * .pi + Double.random(in: -0.15...0.15, using: &generator),
                  distance: CGFloat.random(in: 130...240, using: &generator),
                  size: CGFloat.random(in: 7...13, using: &generator),
                  color: colors[index % colors.count],
                  spin: Double.random(in: -300...300, using: &generator),
                  isCoin: index % 5 == 0)
        }
    }()

    var body: some View {
        ZStack {
            ForEach(pieces.prefix(count)) { piece in
                Group {
                    if piece.isCoin {
                        // Pièce d'or dessinée : l'emoji 🪙 sort argenté.
                        Circle()
                            .fill(LinearGradient(colors: [Color(hex: 0xF7D98B), KrezusColor.gold],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                            .overlay(Text("€").font(.system(size: piece.size, weight: .heavy))
                                .foregroundStyle(Color(hex: 0x9A6B1F)))
                            .frame(width: piece.size * 1.8, height: piece.size * 1.8)
                    } else {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(piece.color)
                            .frame(width: piece.size, height: piece.size * 0.45)
                    }
                }
                .rotationEffect(.degrees(fired ? piece.spin : 0))
                .offset(x: fired ? cos(piece.angle) * piece.distance : 0,
                        y: fired ? sin(piece.angle) * piece.distance + 40 : 0)
                .opacity(fired ? 0 : 1)
                .scaleEffect(fired ? 1 : 0.2)
                .animation(.easeOut(duration: 1.6).delay(Double(piece.id % 6) * 0.02), value: fired)
            }
        }
        .opacity(fired ? 1 : 0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Générateur déterministe : la gerbe est la même à chaque lancement, ce
/// qui la rend relisible en revue et stable dans les captures.
private struct BurstGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

// MARK: - Bouton

/// Le bouton blanc de l'onboarding : l'aplat bleu du design system
/// disparaîtrait sur ce fond.
struct WelcomeButton: View {
    let title: String
    var enabled = true
    var isLoading = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(title).opacity(isLoading ? 0 : 1)
                if isLoading { ProgressView().tint(KrezusColor.navyDeep) }
            }
            .font(KrezusFont.display(16, .bold))
            .foregroundStyle(KrezusColor.navyDeep)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(LinearGradient(colors: [.white, Color(hex: 0xDFE4F0)],
                                       startPoint: .top, endPoint: .bottom))
            .clipShape(RoundedRectangle(cornerRadius: KrezusRadius.lg, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
            .opacity(enabled ? 1 : 0.35)
        }
        .buttonStyle(.plain)
        .disabled(!enabled || isLoading)
    }
}

// MARK: - Champ

/// Libellé en capitales espacées, au-dessus d'un champ sombre.
struct WelcomeFieldLabel: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(KrezusFont.body(12, .bold)).tracking(1.6)
                .foregroundStyle(.white.opacity(0.55))
            Spacer()
            if let trailing {
                Text(trailing.uppercased())
                    .font(KrezusFont.body(10.5, .semibold)).tracking(1.2)
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
    }
}

extension View {
    /// Fond de champ sombre, bordé de la couleur d'état.
    func welcomeField(border: Color = .clear) -> some View {
        self
            .font(KrezusFont.body(17, .medium))
            .foregroundStyle(.white)
            .tint(KrezusColor.gold)
            .padding(.horizontal, 18)
            .padding(.vertical, 17)
            .background(Color.white.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: KrezusRadius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: KrezusRadius.lg, style: .continuous)
                .strokeBorder(border, lineWidth: 1.2))
    }
}
