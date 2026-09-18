import SwiftUI

/// Buste de la mascotte dans le costume d'un rang, posé sur une pastille.
/// Calé en bas, il en déborde par les cornes, comme dans « Tous les rangs ».
struct RankBadge: View {
    let rank: AcademyRank?
    var size: CGFloat = 44
    /// Fond de la pastille : clair sur fond sombre, teinté sur fond clair.
    var disc: Color = KrezusColor.amberTint

    var body: some View {
        Group {
            if let rank {
                Image(rank.imageAsset)
                    .resizable()
                    .scaledToFit()
            } else {
                Color.clear
            }
        }
        .frame(width: size, height: size)
        .background(
            Circle()
                .fill(disc)
                .frame(width: size * 0.9, height: size * 0.9)
                .offset(y: size * 0.05))
        .accessibilityHidden(true)
    }
}
