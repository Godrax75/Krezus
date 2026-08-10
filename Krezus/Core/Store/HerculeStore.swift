import SwiftUI
import Observation

/// Message du chat Hercule.
struct HerculeMessage: Identifiable, Sendable {
    let id = UUID()
    let role: Role
    let text: String
    /// Vrai quand le modèle a décliné la demande — l'app le rend comme une
    /// réponse normale plutôt que comme une erreur technique.
    var refused: Bool = false

    enum Role: Sendable { case user, hercule }
}

/// Conversation avec Hercule et état de l'abonnement.
///
/// En mode démo, les réponses viennent d'un jeu scripté : la Claude API n'est
/// jamais appelée depuis l'app (la clé serait extractible du binaire), et sans
/// backend configuré il n'y a personne pour l'appeler à sa place.
@MainActor
@Observable
final class HerculeStore {

    private(set) var messages: [HerculeMessage] = []
    private(set) var isThinking = false

    /// Crédits restants aujourd'hui ; `nil` = illimité (abonné).
    private(set) var remaining: Int? = HerculeStore.freeDailyQuota
    var isPremium = false

    /// Miroir de `hercule_limits.free_daily_quota`.
    static let freeDailyQuota = 5
    static let maxMessageChars = 2000

    /// Prix affiché au paywall. La source de vérité reste App Store Connect —
    /// StoreKit renvoie le prix localisé, celui-ci n'est qu'un repli, formaté
    /// selon la langue de l'app (« 5,99 € » / « €5.99 »).
    static var subscriptionPrice: String { Money.euros(5.99) }

    init() {
        messages = [.init(role: .hercule, text: t("hercule.greeting"))]
    }

    var canSend: Bool {
        guard !isThinking else { return false }
        return isPremium || (remaining ?? 0) > 0
    }

    /// Envoie une question. En démo, la réponse est scriptée ; en mode connecté
    /// c'est la Edge Function `hercule` qui répond, elle seule détenant la clé.
    func send(_ question: String) {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, canSend else { return }

        messages.append(.init(role: .user, text: String(trimmed.prefix(Self.maxMessageChars))))
        isThinking = true

        Task {
            // Latence simulée : sans elle, l'indicateur de réflexion clignote
            // et l'échange paraît faux.
            try? await Task.sleep(for: .milliseconds(900))
            let reply = Self.scriptedAnswer(for: trimmed)
            messages.append(reply)
            if !isPremium, let left = remaining { remaining = max(0, left - 1) }
            isThinking = false
        }
    }

    func unlockPremium() {
        isPremium = true
        remaining = nil
    }

    // MARK: Réponses de démonstration

    /// Jeu de réponses scriptées, calquées sur le prompt système de la Edge
    /// Function : registre pédagogique, et refus net dès qu'on demande quoi
    /// acheter. C'est le comportement qu'il faut pouvoir montrer sans backend.
    private static func scriptedAnswer(for question: String) -> HerculeMessage {
        let q = question.lowercased()

        if asksForRecommendation(q) {
            return .init(role: .hercule, text: t("hercule.answer.refusal"), refused: true)
        }
        if let topic = topic(of: q) {
            return .init(role: .hercule, text: t("hercule.answer.\(topic)"))
        }
        return .init(role: .hercule, text: t("hercule.answer.fallback"))
    }

    /// Sujet reconnu dans la question. Les deux langues sont testées quelle que
    /// soit celle de l'interface : on tape « dividend » aussi bien dans une app
    /// en français, et la démo doit répondre.
    private static func topic(of q: String) -> String? {
        let topics: [(String, [String])] = [
            ("pe_ratio",   ["per", "price earning", "p/e", "earnings ratio"]),
            ("dividend",   ["dividende", "dividend"]),
            ("diversify",  ["diversif", "risque", "risk", "spread"]),
            ("price_move", ["cours", "prix", "varie", "price", "quote", "move"]),
        ]
        return topics.first { _, keys in keys.contains(where: q.contains) }?.0
    }

    /// Détecte une demande de recommandation. Volontairement large : mieux vaut
    /// refuser une question ambiguë que produire un conseil déguisé.
    private static func asksForRecommendation(_ q: String) -> Bool {
        let asks = ["j'achète", "jachete", "j'achete", "acheter", "vendre", "je vends",
                    "faut-il", "dois-je", "tu conseilles", "conseille-moi",
                    "bon moment", "ça va monter", "ca va monter", "va baisser",
                    "quelle action", "quel titre", "rentable",
                    "should i buy", "should i sell", "should i", "worth buying",
                    "good time", "will it go up", "will it rise", "will it drop",
                    "which stock", "what stock", "recommend", "advise"]
        return asks.contains { q.contains($0) }
    }
}
