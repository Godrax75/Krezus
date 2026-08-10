import Foundation

/// Reformate les libellés chiffrés du référentiel `securities`.
///
/// Ces valeurs sont stockées telles qu'elles ont été rédigées, à la française :
/// « 2,9 % », « 112 Md€ », « 3 900 Md$ ». Ce sont des chaînes, pas des nombres —
/// les convertir en base coûterait une migration et perdrait l'unité. On les
/// relit donc à l'affichage pour les rendre dans la langue courante, et on rend
/// la chaîne d'origine dès qu'on n'est pas certain de l'avoir comprise : un
/// chiffre mal réécrit est pire qu'un chiffre à la française.
enum MarketLabel {

    /// 2,9 -> « 2,9 % » (fr) · « 2.9% » (en). `nil` rend le tiret cadratin du
    /// référentiel : une donnée absente doit se voir.
    static func percent(_ value: Double?) -> String {
        guard let value else { return "—" }
        let formatted = value.formatted(
            .number.precision(.fractionLength(0...2)).locale(L10n.locale))
        return formatted + t("unit.percent_suffix")
    }

    /// Ratio nu (PER, PEG) : « 22,4 » (fr) · « 22.4 » (en).
    static func ratio(_ value: Double?) -> String {
        guard let value else { return "—" }
        return value.formatted(.number.precision(.fractionLength(0...1)).locale(L10n.locale))
    }

    /// « 112 Md€ » -> « 112 Md€ » (fr) · « €112B » (en).
    /// « 3 900 Md$ » -> « 3 900 Md$ » (fr) · « $3,900B » (en).
    static func marketCap(_ raw: String) -> String {
        guard L10n.language != .fr else { return raw }
        guard let value = number(in: raw), let symbol = currencySymbol(in: raw) else { return raw }

        let scale = raw.contains("Md") ? "B" : (raw.contains("M") ? "M" : "")
        let formatted = value.formatted(
            .number.precision(.fractionLength(0...1)).locale(L10n.locale))
        return "\(symbol)\(formatted)\(scale)"
    }

    // MARK: Lecture

    /// Premier nombre écrit à la française, espaces de milliers compris
    /// (« 3 900 » et son espace insécable).
    private static func number(in raw: String) -> Double? {
        let cleaned = raw
            .replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: "\u{202F}", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        let digits = cleaned.prefix { $0.isNumber || $0 == "." }
        return Double(digits)
    }

    private static func currencySymbol(in raw: String) -> String? {
        if raw.contains("€") { return "€" }
        if raw.contains("$") { return "$" }
        if raw.contains("£") { return "£" }
        return nil
    }
}
