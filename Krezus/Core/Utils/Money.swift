import Foundation

/// Formatage monétaire et de pourcentages dans la langue choisie : virgule
/// décimale et symbole en suffixe en français (« 1 000,00 € »), point décimal et
/// symbole en préfixe en anglais (« €1,000.00 »). Les formatteurs sont
/// reconstruits quand la langue change — `NumberFormatter` fige sa locale à la
/// création, un cache global renverrait des montants à la française après une
/// bascule en anglais.
enum Money {

    /// Formatteur de devise mémorisé pour un couple (code devise, langue).
    private static var cache: [String: NumberFormatter] = [:]
    private static let cacheLock = NSLock()

    private static func formatter(currency: String) -> NumberFormatter {
        let locale = L10n.locale
        let key = "\(currency)-\(locale.identifier)"

        cacheLock.lock()
        defer { cacheLock.unlock() }

        if let cached = cache[key] { return cached }
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currency
        f.locale = locale
        cache[key] = f
        return f
    }

    /// Centimes -> « 1 000,00 € ».
    static func euros(cents: Int) -> String {
        euros(Double(cents) / 100)
    }

    /// Valeur en euros (Double) -> « 74,44 € ».
    static func euros(_ value: Double) -> String {
        formatter(currency: "EUR").string(from: NSNumber(value: value)) ?? "—"
    }

    /// Montant rond, sans centimes -> « 25 € », « €25 ». Réservé aux montants
    /// choisis par l'utilisateur (paliers d'achat, capital de départ) : afficher
    /// « 25,00 € » sur un bouton de raccourci alourdit sans rien apprendre.
    static func eurosShort(_ value: Double) -> String {
        let f = formatter(currency: "EUR")
        // `NumberFormatter` n'est pas réentrant : on copie plutôt que de modifier
        // l'instance partagée, qui sert aussi aux montants au centime près.
        guard let copy = f.copy() as? NumberFormatter else { return euros(value) }
        copy.maximumFractionDigits = 0
        return copy.string(from: NSNumber(value: value)) ?? "—"
    }

    /// Montant dans une devise de cotation -> « 178,45 $ », « 27,82 € ».
    /// Utilisé pour afficher un titre étranger dans son unité d'origine, à côté
    /// de sa contrepartie en euros.
    static func amount(_ value: Double, currency: String) -> String {
        let code = currency.uppercased()
        guard code != "EUR" else { return euros(value) }
        return formatter(currency: code).string(from: NSNumber(value: value)) ?? "—"
    }

    /// Pourcentage signé -> « +1,40 % » / « −0,39 % ».
    static func percent(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : "−"
        let number = abs(value).formatted(
            .number.precision(.fractionLength(2)).locale(L10n.locale))
        return "\(sign)\(number)\(t("unit.percent_suffix"))"
    }

    /// Quantité de parts -> « 0,45 action » / « 2 actions ».
    static func shares(_ quantity: Double) -> String {
        let n = quantity.formatted(
            .number.precision(.fractionLength(0...2)).locale(L10n.locale))
        return t(L10n.plural(quantity, one: "unit.shares.one", other: "unit.shares.other"), n)
    }
}
