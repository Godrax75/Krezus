import SwiftUI
import Observation

/// Destinations empilables (écrans « push » du prototype).
enum Route: Hashable {
    case market
    case stock(String)   // symbole
    case lesson(Int)     // position de la leçon
    case quiz(Int)
    case ranks
    case paywall

    // Lot 9 — compte, réglages et vitrine
    case profile
    case editUsername
    case streak
    case settings
    case security
    case notificationSettings
    case notificationCenter
    case help
    case referral
    case locked(LockedFeature)
}

/// Feuilles présentées par-dessus l'onglet courant (le chat Hercule est
/// accessible partout via le FAB, il ne s'empile donc pas dans la navigation).
enum Cover: Identifiable {
    case hercule
    /// Bascule Virtuel / Réel, ouverte depuis la pastille de mode de l'en-tête.
    case modeSwitch

    var id: String {
        switch self {
        case .hercule:    return "hercule"
        case .modeSwitch: return "mode-switch"
        }
    }
}

/// Feuilles modales plein écran (achat / vente).
enum Sheet: Identifiable {
    case buy(String)
    case sell(String)
    var id: String {
        switch self {
        case .buy(let s):  return "buy-\(s)"
        case .sell(let s): return "sell-\(s)"
        }
    }
}

/// Navigation de l'app. `path` pilote un `NavigationStack` ; `sheet` les couvertures
/// plein écran d'achat/vente. Un `toast` transitoire confirme les actions.
@MainActor
@Observable
final class Router {
    var path: [Route] = []
    var sheet: Sheet?
    var cover: Cover?
    var toast: String?

    func push(_ route: Route) { path.append(route) }
    func popToRoot() { path.removeAll() }

    func showToast(_ message: String) {
        toast = message
        Task {
            try? await Task.sleep(for: .seconds(2))
            if toast == message { toast = nil }
        }
    }
}
