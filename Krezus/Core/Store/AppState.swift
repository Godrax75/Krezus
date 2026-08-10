import SwiftUI
import Observation

/// Onglets principaux du shell — ordre du design.
enum KrezusTab: Int, CaseIterable, Identifiable {
    case home, portfolio, oracle, arena, academy
    var id: Int { rawValue }

    /// Libellé court de la tab bar.
    var label: String {
        switch self {
        case .home:      return t("tab.home")
        case .portfolio: return t("tab.portfolio")
        // Oracle, Arena et Academy sont des noms de marque : identiques en FR
        // comme en EN, ils n'entrent pas dans le catalogue.
        case .oracle:    return "Oracle"
        case .arena:     return "Arena"
        case .academy:   return "Academy"
        }
    }

    /// SF Symbol de repli (les icônes de marque seront embarquées ultérieurement).
    var systemImage: String {
        switch self {
        case .home:      return "house.fill"
        case .portfolio: return "chart.pie.fill"
        case .oracle:    return "sparkles"
        case .arena:     return "trophy.fill"
        case .academy:   return "book.fill"
        }
    }
}

/// Mode d'investissement. Real money reste verrouillé en v1.
enum KrezusMode {
    case paper, real
    var label: String { self == .paper ? t("mode.paper") : t("mode.real") }
}

/// État global de l'application. `@Observable` (framework Observation) : les vues
/// qui lisent une propriété se recomposent quand elle change, sans `@Published`.
@Observable
final class AppState {
    var tab: KrezusTab = .home
    var mode: KrezusMode = .paper

    // Les préférences (apparence, langue, notifications, verrou) vivent dans
    // `SettingsStore` — elles sont persistées et doivent survivre à une
    // déconnexion. La progression appartient au `LearningStore`, le compteur de
    // notifications au `NotificationStore` : une seule source par domaine.
}
