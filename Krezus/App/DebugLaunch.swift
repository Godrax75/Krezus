import Foundation

/// Arguments de lancement pour revoir un écran sans rejouer le parcours qui
/// y mène (Xcode › Scheme › Arguments, ou `simctl launch … -krzWelcome`).
/// Toujours faux hors build Debug.
enum DebugLaunch {
    /// Ouvre l'accueil d'un nouveau compte.
    static var welcome: Bool { flag("-krzWelcome") }
    /// Ouvre l'app sans connexion, sur les données de démo.
    static var home: Bool { flag("-krzHome") }
    /// Montre la célébration du versement hebdomadaire, seule à l'écran.
    static var bonus: Bool { flag("-krzBonus") }

    private static func flag(_ name: String) -> Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains(name)
        #else
        false
        #endif
    }
}
