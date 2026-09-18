import SwiftUI

/// Coach — radar du portefeuille.
///
/// Chaque axe est une mesure que l'utilisateur peut retrouver lui-même dans
/// ses positions : le détail sous le radar donne le chiffre brut. Un radar qui
/// afficherait une « note » sans dire d'où elle sort serait une opinion
/// déguisée en donnée.
struct OracleCoachView: View {
    @Environment(OracleStore.self) private var oracle
    @Environment(TradingStore.self) private var trading
    @Environment(LearningStore.self) private var learning

    private var axes: [RadarAxis] { oracle.radar(trading: trading, learning: learning) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            KrzCard(shadow: KrezusShadow.level2) {
                VStack(spacing: 14) {
                    RadarChart(axes: axes)
                        .frame(height: 240)
                        .padding(.top, 4)

                    VStack(spacing: 0) {
                        ForEach(Array(axes.enumerated()), id: \.element.id) { index, axis in
                            if index > 0 { Divider().overlay(KrezusColor.divider) }
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(axis.label)
                                        .font(KrezusFont.body(13, .semibold))
                                        .foregroundStyle(KrezusColor.ink)
                                    Text(axis.detail)
                                        .font(KrezusFont.caption)
                                        .foregroundStyle(KrezusColor.fg3)
                                }
                                Spacer(minLength: 0)
                                KrzProgressBar(value: axis.value, height: 6)
                                    .frame(width: 90)
                            }
                            .padding(.vertical, 9)
                        }
                    }
                }
            }

            weakestAxisCard
        }
    }

    /// Une seule piste, tirée de l'axe le plus bas, formulée comme une question
    /// à se poser — pas comme un ordre d'achat sur un titre.
    @ViewBuilder
    private var weakestAxisCard: some View {
        if let weakest = axes.min(by: { $0.value < $1.value }) {
            KrzCard {
                HStack(alignment: .top, spacing: 12) {
                    HerculeAvatar(size: 40)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(t("coach.attention_point"))
                            .font(KrezusFont.body(10, .bold)).tracking(0.8)
                            .foregroundStyle(KrezusColor.fg3)
                        Text(advice(for: weakest))
                            .font(KrezusFont.bodyMd).foregroundStyle(KrezusColor.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func advice(for axis: RadarAxis) -> String {
        t("coach.advice.\(axis.kind.rawValue)")
    }
}

/// Radar polygonal. Dessiné à la main plutôt qu'avec Charts : la forme
/// (toile d'araignée à N axes) n'existe pas dans le framework, et l'enjeu
/// visuel tient en trois `Path`.
struct RadarChart: View {
    let axes: [RadarAxis]

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = size / 2 - 26

            ZStack {
                // Toile de fond : quatre anneaux de repère.
                ForEach(1...4, id: \.self) { ring in
                    polygon(center: center, radius: radius * CGFloat(ring) / 4, values: nil)
                        .stroke(KrezusColor.border.opacity(0.5), lineWidth: 0.8)
                }

                // Rayons.
                Path { path in
                    for index in axes.indices {
                        path.move(to: center)
                        path.addLine(to: point(center: center, radius: radius, index: index, value: 1))
                    }
                }
                .stroke(KrezusColor.border.opacity(0.5), lineWidth: 0.8)

                // Surface mesurée.
                polygon(center: center, radius: radius, values: axes.map(\.value))
                    .fill(KrezusColor.brandFill.opacity(0.22))
                polygon(center: center, radius: radius, values: axes.map(\.value))
                    .stroke(KrezusColor.brandFill, lineWidth: 2)

                // Étiquettes.
                ForEach(Array(axes.enumerated()), id: \.element.id) { index, axis in
                    let position = point(center: center, radius: radius + 16, index: index, value: 1)
                    Text(axis.label)
                        .font(KrezusFont.body(9.5, .semibold))
                        .foregroundStyle(KrezusColor.fg3)
                        .position(position)
                }
            }
            // Le radar ne se raconte pas axe par axe : VoiceOver lit un résumé,
            // et le détail chiffré vit dans la liste juste en dessous.
            .accessibilityElement()
            .accessibilityLabel(t("a11y.radar"))
            .accessibilityValue(axes.map { "\($0.label) \(Int(($0.value * 100).rounded())) %" }
                                    .joined(separator: ", "))
        }
    }

    private func polygon(center: CGPoint, radius: CGFloat, values: [Double]?) -> Path {
        Path { path in
            guard !axes.isEmpty else { return }
            for index in axes.indices {
                let value = values.map { CGFloat($0[index]) } ?? 1
                let p = point(center: center, radius: radius, index: index, value: value)
                if index == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            path.closeSubpath()
        }
    }

    /// Premier axe en haut, puis sens horaire.
    private func point(center: CGPoint, radius: CGFloat, index: Int, value: CGFloat) -> CGPoint {
        let angle = -CGFloat.pi / 2 + 2 * .pi * CGFloat(index) / CGFloat(max(axes.count, 1))
        let clamped = min(max(value, 0), 1)
        return CGPoint(x: center.x + cos(angle) * radius * clamped,
                       y: center.y + sin(angle) * radius * clamped)
    }
}
