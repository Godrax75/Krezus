import SwiftUI

// MARK: - Barre de navigation

/// Barre de titre des écrans poussés. Le `NavigationStack` de `RootView` masque
/// la barre système (`.toolbar(.hidden)`) pour garder le rendu du prototype :
/// chaque écran empilé porte donc sa propre barre, posée en `safeAreaInset`
/// pour que le contenu défile dessous sans la recouvrir.
struct KrzNavBar<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(KrezusColor.brandText)
                    .frame(width: 36, height: 36)
                    .background(KrezusColor.surface).clipShape(Circle())
                    .krezusShadow(KrezusShadow.level1)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(t("common.back"))

            Spacer()
            Text(title)
                .font(KrezusFont.display(15, .bold)).foregroundStyle(KrezusColor.ink)
            Spacer()

            // Réserve la largeur du bouton de retour pour que le titre reste
            // optiquement centré, avec ou sans action à droite.
            trailing().frame(width: 36, height: 36)
        }
        .padding(.horizontal, KrezusSpacing.s4)
        .padding(.vertical, KrezusSpacing.s2)
        .background(KrezusColor.bg)
    }
}

extension KrzNavBar where Trailing == EmptyView {
    init(title: String) {
        self.init(title: title, trailing: { EmptyView() })
    }
}

extension View {
    func krezusNavBar(_ title: String) -> some View {
        navigationBarBackButtonHidden(true)
            .safeAreaInset(edge: .top) { KrzNavBar(title: title) }
    }

    func krezusNavBar<T: View>(_ title: String, @ViewBuilder trailing: @escaping () -> T) -> some View {
        navigationBarBackButtonHidden(true)
            .safeAreaInset(edge: .top) { KrzNavBar(title: title, trailing: trailing) }
    }
}

// MARK: - Groupes de réglages

/// Intitulé d'un groupe de réglages (petites capitales, hors carte).
struct KrzGroupLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(KrezusFont.body(10.5, .bold)).tracking(0.7)
            .foregroundStyle(KrezusColor.fg3)
            .padding(.horizontal, 4)
            .padding(.top, KrezusSpacing.s3)
    }
}

/// Carte regroupant des lignes de réglage.
///
/// Les séparateurs sont posés explicitement par l'appelant (`KrzRowDivider`)
/// plutôt que déduits du nombre d'enfants : plusieurs de ces groupes affichent
/// des lignes conditionnelles (Premium, mode démo), et un filet dérivé se
/// retrouverait orphelin sous la dernière ligne dès qu'une condition bascule.
struct KrzSettingsGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(KrezusColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: KrezusRadius.lg, style: .continuous))
            .krezusShadow(KrezusShadow.level1)
    }
}

/// Filet entre deux lignes de réglage, aligné sur le texte (après l'icône).
struct KrzRowDivider: View {
    var body: some View {
        Rectangle()
            .fill(KrezusColor.divider)
            .frame(height: 0.5)
            .padding(.leading, 58)
    }
}

/// Ligne de réglage : pastille d'icône, libellé, sous-titre et accessoire.
struct KrzSettingsRow: View {
    let icon: String
    let title: String
    var subtitle: String?
    var value: String?
    var tint: Color = KrezusColor.brandText
    /// Verrouillée : accessoire cadenas et libellé grisé (écrans vitrine).
    var isLocked: Bool = false
    var isDestructive: Bool = false
    var showsChevron: Bool = true
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            HStack(spacing: KrezusSpacing.s3) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isDestructive ? KrezusColor.down : tint)
                    .frame(width: 30, height: 30)
                    .background(isDestructive ? KrezusColor.downBg : KrezusColor.tint)
                    .clipShape(RoundedRectangle(cornerRadius: KrezusRadius.xs, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(KrezusFont.display(14, .semibold))
                        .foregroundStyle(titleColor)
                        .multilineTextAlignment(.leading)
                    if let subtitle {
                        Text(subtitle)
                            .font(KrezusFont.caption).foregroundStyle(KrezusColor.fg3)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 8)

                if let value {
                    Text(value)
                        .font(KrezusFont.body(12.5, .semibold))
                        .foregroundStyle(KrezusColor.fg3)
                }
                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(KrezusColor.fg4)
                } else if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(KrezusColor.fg4)
                }
            }
            .padding(.horizontal, KrezusSpacing.s4)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var titleColor: Color {
        if isDestructive { return KrezusColor.down }
        return isLocked ? KrezusColor.fg3 : KrezusColor.ink
    }
}

/// Ligne de réglage à interrupteur.
struct KrzToggleRow: View {
    let icon: String
    let title: String
    var subtitle: String?
    var isEnabled: Bool = true
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: KrezusSpacing.s3) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(KrezusColor.brandText)
                .frame(width: 30, height: 30)
                .background(KrezusColor.tint)
                .clipShape(RoundedRectangle(cornerRadius: KrezusRadius.xs, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(KrezusFont.display(14, .semibold))
                    .foregroundStyle(isEnabled ? KrezusColor.ink : KrezusColor.fg3)
                if let subtitle {
                    Text(subtitle)
                        .font(KrezusFont.caption).foregroundStyle(KrezusColor.fg3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(KrezusColor.brandFill)
                .disabled(!isEnabled)
        }
        .padding(.horizontal, KrezusSpacing.s4)
        .padding(.vertical, 11)
    }
}

/// Sélecteur segmenté aux couleurs de la marque (apparence, langue).
struct KrzSegmented<Value: Hashable>: View {
    let options: [(value: Value, label: String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.value) { option in
                let isSelected = option.value == selection
                Button { selection = option.value } label: {
                    Text(option.label)
                        .font(KrezusFont.body(12.5, .semibold))
                        .foregroundStyle(isSelected ? .white : KrezusColor.fg2)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(isSelected ? KrezusColor.brandFill : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: KrezusRadius.sm, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(KrezusColor.tint)
        .clipShape(RoundedRectangle(cornerRadius: KrezusRadius.md, style: .continuous))
    }
}

// MARK: - Avatar

/// Pastille d'initiale, du header (32 pt) à l'en-tête du profil (72 pt).
struct KrzAvatar: View {
    let initial: String
    var size: CGFloat = 32

    var body: some View {
        Text(initial)
            .font(KrezusFont.display(size * 0.42, .bold))
            .foregroundStyle(KrezusColor.brandText)
            .frame(width: size, height: size)
            .background(KrezusColor.tintStrong)
            .clipShape(Circle())
    }
}

// MARK: - Bandeau « argent fictif »

/// Rappel réglementaire affiché en pied des écrans de compte. Le paper trading
/// n'exige aucun statut PSI, mais l'ambiguïté sur la nature des fonds est, elle,
/// un motif de rejet App Store.
struct KrzPaperMoneyNote: View {
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "info.circle.fill").font(.system(size: 11))
            Text(t("disclaimer.paper_money"))
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(KrezusFont.caption)
        .foregroundStyle(KrezusColor.fg3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }
}
