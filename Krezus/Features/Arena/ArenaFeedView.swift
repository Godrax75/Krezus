import SwiftUI

/// Feed d'activité des amis.
///
/// Chaque ligne dit **quoi**, jamais **combien** : « Camille a acheté Nvidia »
/// et non « Camille a mis 300 € sur Nvidia ». C'est la même règle que côté
/// serveur, où les payloads de `arena_feed` ne portent aucun montant.
struct ArenaFeedView: View {
    @Environment(ArenaStore.self) private var arena

    var body: some View {
        KrzCard(padding: KrezusSpacing.s4) {
            VStack(alignment: .leading, spacing: 0) {
                Text(t("arena.feed.title"))
                    .font(KrezusFont.cardTitle).foregroundStyle(KrezusColor.ink)
                    .padding(.bottom, 8)

                if arena.feed.isEmpty {
                    Text(t("arena.feed.empty"))
                        .font(KrezusFont.bodyMd).foregroundStyle(KrezusColor.fg3)
                        .padding(.vertical, 8)
                } else {
                    ForEach(Array(arena.feed.enumerated()), id: \.element.id) { index, event in
                        if index > 0 { Divider().overlay(KrezusColor.divider) }
                        row(event)
                    }
                }
            }
        }
    }

    private func row(_ event: FeedEvent) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: event.kind.icon)
                .font(.system(size: 15))
                .foregroundStyle(tint(event.kind))
                .frame(width: 30, height: 30)
                .background(tintBackground(event.kind))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                // Le sujet est mis en gras dans une phrase, plutôt qu'isolé :
                // « Camille a acheté **Nvidia** » se lit d'un coup d'œil.
                (Text(event.actor).font(KrezusFont.body(13.5, .semibold))
                 + Text(" \(event.kind.verb) ").font(KrezusFont.body(13.5))
                 + Text(subjectLabel(event)).font(KrezusFont.body(13.5, .semibold)))
                    .foregroundStyle(KrezusColor.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Text(relativeTime(event.minutesAgo))
                    .font(KrezusFont.caption).foregroundStyle(KrezusColor.fg3)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
    }

    private func subjectLabel(_ event: FeedEvent) -> String {
        event.kind == .rankUp ? "\(event.subject)" : event.subject
    }

    private func tint(_ kind: FeedEvent.Kind) -> Color {
        switch kind {
        case .buy:    return KrezusColor.up
        case .sell:   return KrezusColor.down
        case .lesson: return KrezusColor.brandText
        case .rankUp: return KrezusColor.amberText
        }
    }

    private func tintBackground(_ kind: FeedEvent.Kind) -> Color {
        switch kind {
        case .buy:    return KrezusColor.upBg
        case .sell:   return KrezusColor.downBg
        case .lesson: return KrezusColor.tintStrong
        case .rankUp: return KrezusColor.amberTint
        }
    }

    private func relativeTime(_ minutes: Int) -> String {
        if minutes < 60 { return t("time.ago_minutes", minutes) }
        let hours = minutes / 60
        if hours < 24 { return t("time.ago_hours", hours) }
        return t("time.ago_days", hours / 24)
    }
}
