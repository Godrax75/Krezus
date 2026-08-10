import Foundation
import SwiftUI

/// Langues livrées en v1. Le libellé reste dans la langue elle-même — un
/// sélecteur qui affiche « Anglais » quand l'interface est déjà en anglais
/// n'aide personne.
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case fr, en

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fr: return "Français"
        case .en: return "English"
        }
    }

    /// Locale de formatage (montants, dates, séparateurs décimaux).
    var locale: Locale {
        switch self {
        case .fr: return Locale(identifier: "fr_FR")
        case .en: return Locale(identifier: "en_US")
        }
    }

    /// Langue de départ déduite des préférences système, avant tout choix
    /// explicite de l'utilisateur.
    static var systemDefault: AppLanguage {
        let preferred = Locale.preferredLanguages.first ?? "fr"
        return preferred.hasPrefix("en") ? .en : .fr
    }
}

/// Résolution des chaînes dans la langue **choisie dans l'app**, qui peut
/// différer de celle du système : le sélecteur des réglages doit basculer
/// l'interface sans passer par Réglages iOS. On garde donc le bundle de langue
/// sous la main plutôt que de s'en remettre à `NSLocalizedString`, qui suit la
/// préférence système.
enum L10n {

    /// Écrit uniquement depuis `SettingsStore` (main actor) au lancement puis à
    /// chaque changement de langue ; lu partout, y compris hors main actor par
    /// les formatteurs. `nonisolated(unsafe)` documente ce contrat.
    nonisolated(unsafe) private(set) static var language: AppLanguage = .fr
    nonisolated(unsafe) private static var bundle: Bundle = .main

    static func use(_ language: AppLanguage) {
        Self.language = language
        Self.bundle = Bundle.main.path(forResource: language.rawValue, ofType: "lproj")
            .flatMap(Bundle.init(path:)) ?? .main
    }

    static var locale: Locale { language.locale }

    /// Chaîne localisée. Une clé absente du catalogue est une erreur de
    /// développement : on la signale en debug plutôt que d'afficher la clé brute
    /// à l'utilisateur au bout de six mois.
    static func string(_ key: String) -> String {
        let missing = "\u{0}"
        let value = bundle.localizedString(forKey: key, value: missing, table: nil)
        guard value != missing else {
            assertionFailure("Clé de traduction absente : \(key)")
            return key
        }
        return value
    }

    /// Variante tolérante, pour les clés construites à l'exécution (codes pays,
    /// codes d'erreur du serveur) : une clé inconnue rend `nil` au lieu de
    /// déclencher une assertion, à charge de l'appelant de prévoir un repli.
    static func optional(_ key: String) -> String? {
        let missing = "\u{0}"
        let value = bundle.localizedString(forKey: key, value: missing, table: nil)
        return value == missing ? nil : value
    }

    /// Chaîne à paramètres (`%@`, `%d`, `%.2f`). Le format est interpolé avec la
    /// locale choisie pour que les nombres insérés portent la bonne virgule.
    static func string(_ key: String, _ arguments: [CVarArg]) -> String {
        String(format: string(key), locale: locale, arguments: arguments)
    }

    /// Choisit la clé accordée en nombre. Le français bascule au pluriel à partir
    /// de 2 (« 1,5 action » reste au singulier), l'anglais dès que la valeur
    /// diffère de 1 — d'où deux règles distinctes plutôt qu'un `count > 1`
    /// universel. Renvoie la clé et non la chaîne : l'appelant a presque toujours
    /// un paramètre à interpoler derrière.
    static func plural(_ count: Double, one: String, other: String) -> String {
        let isSingular: Bool
        switch language {
        case .fr: isSingular = abs(count) < 2
        case .en: isSingular = abs(count) == 1
        }
        return isSingular ? one : other
    }
}

/// Raccourci de lecture d'une chaîne localisée.
///
/// Volontairement une fonction libre et courte : elle apparaît des centaines de
/// fois dans les vues, où `L10n.string("…")` alourdirait chaque ligne.
func t(_ key: String) -> String {
    L10n.string(key)
}

func t(_ key: String, _ arguments: CVarArg...) -> String {
    L10n.string(key, arguments)
}
