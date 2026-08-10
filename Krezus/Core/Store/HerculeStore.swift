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
///
/// En mode serveur, c'est la Edge Function `hercule` qui répond, elle seule
/// détenant la clé Anthropic — et elle seule décomptant le quota.
@MainActor
@Observable
final class HerculeStore {

    enum Source: Equatable { case demo, server }

    private(set) var source: Source = .demo
    private(set) var lastError: String?

    private(set) var messages: [HerculeMessage] = []
    private(set) var isThinking = false

    /// Crédits restants aujourd'hui ; `nil` = illimité (abonné).
    private(set) var remaining: Int? = HerculeStore.freeDailyQuota
    var isPremium = false

    // Mode serveur
    private let repository = HerculeRepository()
    private var userID: UUID?

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

    // MARK: Source de données

    func connect(userID: UUID) async {
        guard AppConfig.isConfigured else { return }
        self.userID = userID
        source = .server
        await reload()
    }

    func disconnect() {
        userID = nil
        source = .demo
        lastError = nil
        isPremium = false
        remaining = Self.freeDailyQuota
        messages = [.init(role: .hercule, text: t("hercule.greeting"))]
    }

    /// Relit le quota du jour et l'historique de la conversation.
    func reload() async {
        guard source == .server, let userID else { return }
        do {
            let quota = try await repository.fetchQuota(userID: userID)
            isPremium = quota.isPremium
            remaining = quota.isPremium ? nil : quota.remaining

            let history = try await repository.fetchHistory(userID: userID)
            if history.isEmpty {
                messages = [.init(role: .hercule, text: t("hercule.greeting"))]
            } else {
                // Le salut n'est pas stocké : il ouvre la conversation, il n'en
                // fait pas partie. On le remet en tête de l'historique relu.
                messages = [.init(role: .hercule, text: t("hercule.greeting"))]
                    + history.map {
                        HerculeMessage(role: $0.role == "user" ? .user : .hercule,
                                       text: $0.content)
                    }
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
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

        let sent = String(trimmed.prefix(Self.maxMessageChars))
        messages.append(.init(role: .user, text: sent))
        isThinking = true
        lastError = nil

        Task {
            defer { isThinking = false }

            switch source {
            case .demo:
                // Latence simulée : sans elle, l'indicateur de réflexion
                // clignote et l'échange paraît faux.
                try? await Task.sleep(for: .milliseconds(900))
                messages.append(Self.scriptedAnswer(for: sent))
                if !isPremium, let left = remaining { remaining = max(0, left - 1) }

            case .server:
                do {
                    let reply = try await repository.ask(sent)
                    messages.append(.init(role: .hercule, text: reply.answer,
                                          refused: reply.refused ?? false))
                    // Le quota vient du serveur : ne jamais le décrémenter ici,
                    // sinon l'affichage dérive dès qu'une requête échoue.
                    remaining = isPremium ? nil : reply.remaining
                } catch {
                    lastError = error.localizedDescription
                    // La question reste affichée : la retirer donnerait
                    // l'impression qu'elle n'a jamais été posée, alors qu'il
                    // suffit peut-être de réessayer.
                    if case KrezusError.herculeQuotaReached = error { remaining = 0 }
                }
            }
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
