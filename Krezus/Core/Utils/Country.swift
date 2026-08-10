import Foundation

/// Nom de pays affichable à partir d'un code ISO 3166-1 alpha-2.
///
/// La table `securities` stocke déjà un libellé (« États-Unis »), mais rédigé en
/// français une fois pour toutes : il ne peut pas servir en anglais. Le code,
/// lui, est neutre — on le traduit ici, avec les quinze pays de l'univers en
/// catalogue et un repli sur la table de l'OS pour les titres ajoutés plus tard.
enum Country {
    static func name(_ code: String?) -> String {
        guard let code, !code.isEmpty else { return "—" }
        let key = code.uppercased()
        if let translated = L10n.optional("country.\(key)") { return translated }
        return L10n.locale.localizedString(forRegionCode: key) ?? key
    }
}
