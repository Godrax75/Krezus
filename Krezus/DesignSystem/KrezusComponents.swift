import SwiftUI

// MARK: - Carte surface

/// Carte blanche à coins arrondis et ombre légère — le conteneur de base du design.
struct KrzCard<Content: View>: View {
    var radius: CGFloat = KrezusRadius.lg
    var padding: CGFloat = KrezusSpacing.s4
    var shadow: KrezusShadow.Spec = KrezusShadow.level1
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(KrezusColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .krezusShadow(shadow)
    }
}

// MARK: - Boutons

/// Bouton primaire pleine largeur (navy, texte blanc, ombre marque).
struct KrzPrimaryButton: View {
    let title: String
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(KrezusFont.display(15.5, .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(KrezusColor.brandFill)
                .clipShape(RoundedRectangle(cornerRadius: KrezusRadius.md, style: .continuous))
                .krezusShadow(KrezusShadow.brand)
        }
        .buttonStyle(.plain)
    }
}

/// Pastille cliquable (fond teinté, texte coloré) — filtres, badges, actions secondaires.
struct KrzPill: View {
    let title: String
    var fg: Color = KrezusColor.brandText
    var bg: Color = KrezusColor.tintStrong
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(KrezusFont.body(12.5, .semibold))
                .foregroundStyle(fg)
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background(bg)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Barre de progression

/// Barre de progression arrondie (XP, allocation, scénarios).
///
/// VoiceOver annonce le pourcentage : une barre muette ne transmet rien, et
/// c'est souvent la seule information de la ligne (progression de rang,
/// pondération d'un axe du radar).
struct KrzProgressBar: View {
    var value: Double            // 0...1
    var height: CGFloat = 7
    var fill: Color = KrezusColor.brandFill
    var track: Color = KrezusColor.tint

    private var clamped: Double { max(0, min(1, value)) }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(fill)
                    .frame(width: clamped * geo.size.width)
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityValue(t("format.percent_int", Int((clamped * 100).rounded())))
    }
}

// MARK: - Ligne d'action (holding / position / marché)

/// Logo carré ou initiales en repli, quand l'asset logo est absent.
struct KrzSecurityBadge: View {
    var logoAsset: String?
    /// Logo servi par le réseau, pour les titres sans image embarquée. Le
    /// chargement est confié à `AsyncImage` : le cache d'URLSession évite de
    /// retélécharger le même logo à chaque défilement.
    var logoURL: URL?
    var initials: String
    var tileColor: Color = KrezusColor.brandFill
    var size: CGFloat = 40

    var body: some View {
        Group {
            if let logoAsset, UIImage(named: logoAsset) != nil {
                Image(logoAsset).resizable().scaledToFit().padding(5)
            } else if let logoURL {
                AsyncImage(url: logoURL) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFit().padding(5)
                    } else {
                        // Pendant le chargement, et si le logo manque : les
                        // initiales, jamais un carré vide.
                        initialsTile
                    }
                }
            } else {
                initialsTile
            }
        }
        .frame(width: size, height: size)
        .background(KrezusColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: KrezusRadius.sm, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: KrezusRadius.sm, style: .continuous)
                .stroke(KrezusColor.brandText.opacity(0.1), lineWidth: 1))
        // Le logo répète le nom du titre, lu juste à côté : l'annoncer une
        // seconde fois allongerait chaque ligne de liste sans rien apporter.
        .accessibilityHidden(true)
    }

    private var initialsTile: some View {
        RoundedRectangle(cornerRadius: KrezusRadius.xs, style: .continuous)
            .fill(tileColor)
            .overlay(
                Text(initials)
                    .font(KrezusFont.display(9.5, .heavy))
                    .foregroundStyle(.white))
    }
}

/// Ligne de titre : badge · nom + sous-titre · valeur + variation.
struct KrzStockRow: View {
    let name: String
    let subtitle: String
    let value: String
    let change: String
    var changeColor: Color
    var logoAsset: String?
    var logoURL: URL?
    var initials: String
    var badgeText: String?          // ex. le code pays « US »
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            HStack(spacing: KrezusSpacing.s3) {
                KrzSecurityBadge(logoAsset: logoAsset, logoURL: logoURL, initials: initials)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(name).font(KrezusFont.stockName).foregroundStyle(KrezusColor.ink)
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        if let badgeText {
                            Text(badgeText)
                                .font(KrezusFont.body(9.5, .bold))
                                .foregroundStyle(KrezusColor.fg3)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(KrezusColor.tint)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                    Text(subtitle).font(KrezusFont.bodySm).foregroundStyle(KrezusColor.fg3)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(value).font(KrezusFont.numeric).foregroundStyle(KrezusColor.ink)
                        .tabularNumbers()
                        .lineLimit(1).minimumScaleFactor(0.75)
                    Text(change).font(KrezusFont.body(12, .semibold))
                        .foregroundStyle(changeColor).tabularNumbers()
                        .lineLimit(1).minimumScaleFactor(0.75)
                }
            }
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // « Nvidia, 0,45 action, 74,44 €, +1,40 % » d'une traite, plutôt que
        // quatre arrêts successifs sur des fragments dont l'ordre n'a de sens
        // que visuellement.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([name, subtitle, value, change].joined(separator: ", "))
        .accessibilityAddTraits(.isButton)
    }
}

/// En-tête de section (icône + titre), en tête de chaque onglet.
struct KrzSectionTitle: View {
    let systemImage: String
    let title: String
    var tint: Color = KrezusColor.amber500

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage).font(.system(size: 22)).foregroundStyle(tint)
            Text(title).font(KrezusFont.h1).foregroundStyle(KrezusColor.ink)
        }
        .padding(.top, 4)
    }
}

// MARK: - Hercule

/// Portrait d'Hercule, le coach IA, dans sa pastille. Partout où il parle —
/// bouton flottant, chat, abonnement, conseil de l'accueil — pour qu'il ait
/// partout le même visage.
///
/// Le portrait remplit le cercle, cadré sur le visage : réduit au centre
/// d'une pastille, comme l'ancienne tête de mascotte, il deviendrait
/// illisible sous 40 points. Le fond est crème et non orange : le taureau
/// est orange, il s'y fondrait.
struct HerculeAvatar: View {
    var size: CGFloat = 56
    /// Liseré blanc, pour les pastilles posées sur un contenu qui défile.
    var ring: Bool = false

    var body: some View {
        Image("hercule-avatar")
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .background(
                LinearGradient(colors: [Color(hex: 0xFFF6EC), Color(hex: 0xFFE3CC)],
                               startPoint: .top, endPoint: .bottom))
            .clipShape(Circle())
            .overlay {
                if ring { Circle().stroke(.white, lineWidth: 2.5) }
            }
            .accessibilityHidden(true)
    }
}

/// Âge d'une cotation, en pastille.
///
/// Le catalogue ne se rafraîchit plus à la minute depuis qu'il compte plus de
/// mille titres : un cours peut avoir un quart d'heure. Afficher « En direct »
/// par-dessus serait un mensonge d'interface — celui qu'on s'interdit partout
/// ailleurs dans l'app.
struct KrzQuoteAge: View {
    /// `nil` = cours simulé (mode démo) : il est bien en direct.
    let age: TimeInterval?

    private var minutes: Int { Int((age ?? 0) / 60) }

    private var tint: Color {
        guard let age else { return KrezusColor.upDeep }
        if age < 120 { return KrezusColor.upDeep }
        return age < MarketDataService.staleThreshold ? KrezusColor.amberText : KrezusColor.fg3
    }

    private var label: String {
        guard let age, age >= 120 else { return t("common.live") }
        return minutes < 60 ? t("quote.minutes_ago", minutes) : t("quote.hours_ago", minutes / 60)
    }

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(tint).frame(width: 6, height: 6)
            Text(label).font(KrezusFont.body(10.5, .semibold))
        }
        .foregroundStyle(tint)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(t("a11y.quote_age", label))
    }
}
