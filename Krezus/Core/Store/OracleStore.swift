import SwiftUI
import Observation

/// Scénario pédagogique. Aucune probabilité, aucune échéance : ce sont des
/// mécanismes expliqués (« si ceci, alors historiquement cela »), pas des
/// prévisions. Le bloc « Powered by Amundi » du prototype supposait un
/// partenariat — la marque est retirée, le contenu est celui de Krezus.
struct OracleScenario: Identifiable, Codable, Sendable {
    let id: String
    let emoji: String
    let title: String
    /// Ce qui déclenche le scénario.
    let trigger: String
    /// Le mécanisme économique en jeu.
    let mechanism: String
    /// Ce que ça change pour un portefeuille, en général — jamais pour *ton*
    /// portefeuille nommément, ce qui relèverait du conseil personnalisé.
    let portfolio: String
    let lesson: String
}

/// Question du profil investisseur. Chaque option porte directement ses
/// coordonnées d'ADN : le calcul reste une moyenne, sans pondération cachée
/// que l'utilisateur ne pourrait pas comprendre.
struct InvestorQuestion: Identifiable, Codable, Sendable {
    let id: String
    let question: String
    let options: [Option]

    struct Option: Codable, Sendable {
        let label: String
        let patience: Int
        let prudence: Int
        let curiosite: Int
        let regularite: Int
    }
}

/// Résultat du questionnaire. Oriente le ton pédagogique — ce n'est **pas** un
/// profil de risque réglementaire (MiFID) et il ne conditionne aucun accès.
struct InvestorArchetype: Sendable {
    let name: String
    let emoji: String
    let summary: String
    /// Quatre axes 0…100.
    let dna: [DnaTrait]

    struct DnaTrait: Identifiable, Sendable {
        var id: String { key }
        /// Clé de catalogue — le libellé affiché en découle.
        let key: String
        let value: Int

        var label: String { t(key) }
    }
}

/// Un repère de valorisation : un chiffre public mis en regard d'une médiane.
struct ValuationRow: Identifiable, Sendable {
    var id: String { symbol }
    let symbol: String
    let name: String
    let pe: Double?
    /// Écart au repère, en % ; `nil` si le PER n'est pas connu.
    let gapToMedian: Double?
}

/// Axe du radar Coach. `value` est une mesure, pas une note : `detail` doit
/// permettre à l'utilisateur de la retrouver dans ses propres positions.
///
/// `kind` est l'identité de l'axe ; `label` n'en est que l'affichage. Les vues
/// qui adaptent leur discours à l'axe le plus faible se branchent sur `kind` :
/// tester le libellé traduit casserait tout dès la bascule en anglais.
struct RadarAxis: Identifiable, Sendable {
    enum Kind: String, Sendable {
        case diversification, balance, regularity, knowledge, openness
    }

    var id: String { kind.rawValue }
    let kind: Kind
    /// 0…1.
    let value: Double
    let detail: String

    var label: String { t("coach.axis.\(kind.rawValue)") }
}

@MainActor
@Observable
final class OracleStore {

    private(set) var scenarios: [OracleScenario] = []
    private(set) var questions: [InvestorQuestion] = []

    enum Source: Equatable { case demo, server }

    private(set) var source: Source = .demo
    private(set) var lastError: String?

    /// Réponses en cours : identifiant de question → index d'option choisie.
    private(set) var answers: [String: Int] = [:]
    private(set) var archetype: InvestorArchetype?

    /// Clé stable de l'archétype courant (« guardian »), dont `archetype`
    /// n'est que l'habillage traduit. C'est elle qu'on enregistre.
    private(set) var archetypeKey: String?

    // Mode serveur
    private let repository = OracleRepository()
    private var userID: UUID?

    init() {
        loadContent()
    }

    // MARK: Source de données

    /// Bascule sur le serveur et recharge le profil déjà rempli, s'il existe.
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
        reset()
    }

    /// Relit le profil enregistré. Seules les **réponses** sont restaurées :
    /// l'archétype et l'ADN en sont recalculés, ce qui garantit qu'ils suivent
    /// la langue courante et la version actuelle du questionnaire.
    func reload() async {
        guard source == .server, let userID else { return }
        do {
            guard let stored = try await repository.fetchProfile(userID: userID) else {
                answers = [:]
                archetype = nil
                archetypeKey = nil
                return
            }
            answers = stored.answers
            if isComplete { computeArchetype() } else { archetype = nil; archetypeKey = nil }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// (Re)charge scénarios et questionnaire dans la langue courante. Les
    /// réponses déjà données sont indexées par identifiant de question : elles
    /// restent valides après un changement de langue, et l'archétype est
    /// recalculé pour que son texte suive.
    func loadContent() {
        scenarios = Bundle.main.decodeJSON("oracle_scenarios.json") ?? []
        questions = Bundle.main.decodeJSON("investor_questions.json") ?? []
        if isComplete { computeArchetype() }
    }

    // MARK: Analyse — uniquement des chiffres réellement disponibles

    /// Plus fortes variations du jour. Purement factuel : c'est la variation
    /// depuis l'ouverture, rien de plus.
    func movers(_ catalog: [StockInfo], rising: Bool, limit: Int = 3) -> [StockInfo] {
        let quoted = catalog.filter { $0.open > 0 }
        let ordered = rising
            ? quoted.sorted { changePct($0) > changePct($1) }
            : quoted.sorted { changePct($0) < changePct($1) }
        return ordered
            .filter { rising ? changePct($0) > 0 : changePct($0) < 0 }
            .prefix(limit)
            .map { $0 }
    }

    func changePct(_ stock: StockInfo) -> Double {
        guard stock.open > 0 else { return 0 }
        return (stock.price - stock.open) / stock.open * 100
    }

    /// Médiane des PER connus. Le catalogue de démonstration compte autant de
    /// secteurs que de titres : une médiane *sectorielle* n'y aurait aucun sens,
    /// on prend donc l'univers entier — et on le dit à l'écran.
    func medianPE(_ catalog: [StockInfo]) -> Double? {
        let values = catalog.compactMap(\.pe).sorted()
        guard !values.isEmpty else { return nil }
        let middle = values.count / 2
        return values.count.isMultiple(of: 2)
            ? (values[middle - 1] + values[middle]) / 2
            : values[middle]
    }

    /// Titres classés par écart au PER médian. Les titres sans PER connu sont
    /// renvoyés avec `nil` plutôt qu'écartés : une donnée manquante doit se
    /// voir, sinon la liste laisse croire à une couverture complète.
    func valuationRows(_ catalog: [StockInfo]) -> [ValuationRow] {
        let median = medianPE(catalog)
        return catalog.map { stock in
            let pe = stock.pe
            let gap: Double? = {
                guard let pe, let median, median > 0 else { return nil }
                return (pe - median) / median * 100
            }()
            return ValuationRow(symbol: stock.symbol, name: stock.name, pe: pe, gapToMedian: gap)
        }
        .sorted { ($0.pe ?? .greatestFiniteMagnitude) < ($1.pe ?? .greatestFiniteMagnitude) }
    }

    /// Meilleurs rendements du dividende — un fait, pas une préconisation.
    func dividendLeaders(_ catalog: [StockInfo], limit: Int = 4) -> [(stock: StockInfo, yield: Double)] {
        catalog
            .compactMap { stock -> (StockInfo, Double)? in
                guard let value = stock.dividendYield, value > 0 else { return nil }
                return (stock, value)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map { (stock: $0.0, yield: $0.1) }
    }

    // MARK: Coach — mesures vérifiables du portefeuille

    func radar(trading: TradingStore, learning: LearningStore) -> [RadarAxis] {
        let symbols = trading.holdingSymbols
        let total = symbols.reduce(0.0) { $0 + trading.positionValue($1) }

        let sectors = Set(symbols.compactMap { trading.stock($0)?.sector })
        let topWeight = total > 0
            ? (symbols.map { trading.positionValue($0) }.max() ?? 0) / total
            : 0
        let foreign = symbols.filter { trading.stock($0)?.cc != "FR" }
        let foreignShare = total > 0
            ? foreign.reduce(0.0) { $0 + trading.positionValue($1) } / total
            : 0

        return [
            RadarAxis(
                kind: .diversification,
                value: min(1, Double(sectors.count) / 5),
                detail: t(L10n.plural(Double(sectors.count),
                                      one: "coach.detail.sectors.one",
                                      other: "coach.detail.sectors.other"), sectors.count)),
            RadarAxis(
                kind: .balance,
                value: total > 0 ? max(0, 1 - topWeight) : 0,
                detail: total > 0
                    ? t("coach.detail.top_line", Int((topWeight * 100).rounded()))
                    : t("coach.detail.no_position")),
            RadarAxis(
                kind: .regularity,
                value: min(1, Double(learning.streakDays) / 30),
                detail: t(L10n.plural(Double(learning.streakDays),
                                      one: "coach.detail.streak.one",
                                      other: "coach.detail.streak.other"), learning.streakDays)),
            RadarAxis(
                kind: .knowledge,
                value: learning.lessons.isEmpty
                    ? 0
                    : Double(learning.completedCount) / Double(learning.lessons.count),
                detail: t(L10n.plural(Double(learning.completedCount),
                                      one: "coach.detail.lessons.one",
                                      other: "coach.detail.lessons.other"),
                          learning.completedCount, learning.lessons.count)),
            RadarAxis(
                kind: .openness,
                value: min(1, foreignShare * 2),
                detail: total > 0
                    ? t("coach.detail.foreign_share", Int((foreignShare * 100).rounded()))
                    : t("coach.detail.no_position")),
        ]
    }

    // MARK: Profil investisseur

    func select(question id: String, option index: Int) {
        answers[id] = index
        guard answers.count == questions.count else { return }
        computeArchetype()
        save()
    }

    var isComplete: Bool { !questions.isEmpty && answers.count == questions.count }

    /// Recommence le questionnaire.
    ///
    /// En mode serveur, le profil déjà enregistré n'est **pas** supprimé : il
    /// le sera par écrasement quand les six réponses seront à nouveau
    /// complètes. Abandonner en cours de route retrouve donc l'ancien profil au
    /// prochain lancement, ce qui vaut mieux que de perdre un profil rempli
    /// parce qu'on a touché « Recommencer » par curiosité.
    func reset() {
        answers.removeAll()
        archetype = nil
        archetypeKey = nil
    }

    /// Enregistre le profil complété. Volontairement sans `await` à l'appelant :
    /// répondre à la sixième question doit afficher l'archétype tout de suite,
    /// l'aller-retour réseau n'a pas à retenir l'écran. Un échec se lit dans
    /// `lastError` plutôt que d'interrompre le parcours.
    private func save() {
        guard source == .server, let userID,
              let key = archetypeKey, let archetype else { return }
        let dna = Dictionary(uniqueKeysWithValues: archetype.dna.map { ($0.key, $0.value) })
        let answers = answers
        Task {
            do {
                try await repository.saveProfile(userID: userID, answers: answers,
                                                 archetypeKey: key, dna: dna)
                lastError = nil
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func computeArchetype() {
        var patience = 0, prudence = 0, curiosite = 0, regularite = 0, count = 0

        for question in questions {
            guard let index = answers[question.id],
                  question.options.indices.contains(index) else { continue }
            let option = question.options[index]
            patience += option.patience
            prudence += option.prudence
            curiosite += option.curiosite
            regularite += option.regularite
            count += 1
        }
        guard count > 0 else { archetype = nil; archetypeKey = nil; return }

        let dna = [
            InvestorArchetype.DnaTrait(key: "dna.patience",   value: patience / count),
            InvestorArchetype.DnaTrait(key: "dna.prudence",   value: prudence / count),
            InvestorArchetype.DnaTrait(key: "dna.curiosity",  value: curiosite / count),
            InvestorArchetype.DnaTrait(key: "dna.regularity", value: regularite / count),
        ]

        // Le libellé décrit une tendance de comportement, jamais une aptitude
        // à investir dans tel ou tel produit.
        let (key, emoji): (String, String)
        if dna[1].value >= 75 {
            (key, emoji) = ("guardian", "🛡️")
        } else if dna[2].value >= 75 && dna[1].value < 45 {
            (key, emoji) = ("explorer", "🧭")
        } else if dna[3].value >= 75 {
            (key, emoji) = ("builder", "🧱")
        } else {
            (key, emoji) = ("balanced", "⚖️")
        }

        archetypeKey = key
        archetype = InvestorArchetype(
            name: t("archetype.\(key).name"),
            emoji: emoji,
            summary: t("archetype.\(key).summary"),
            dna: dna)
    }

}
