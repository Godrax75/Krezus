import Testing
import Foundation
@testable import Krezus

/// Localisation : catalogue, accord en nombre et mise en forme des chiffres.
///
/// Ces tests s'exécutent dans le processus de l'app, donc contre le vrai
/// catalogue compilé — une clé retirée du catalogue les fait tomber ici, pas
/// devant l'utilisateur.
@MainActor
struct LocalizationTests {

    /// Chaque cas repart du français, langue de rédaction.
    private func withLanguage(_ language: AppLanguage, _ body: () -> Void) {
        L10n.use(language)
        defer { L10n.use(.fr) }
        body()
    }

    // MARK: Catalogue

    @Test("Le catalogue rend les deux langues pour une même clé")
    func resolvesBothLanguages() {
        withLanguage(.fr) { #expect(t("common.buy") == "Acheter") }
        withLanguage(.en) { #expect(t("common.buy") == "Buy") }
    }

    @Test("Une clé inconnue est signalée, pas rendue silencieusement")
    func unknownKeyIsDetectable() {
        #expect(L10n.optional("clé.qui.n.existe.pas") == nil)
        #expect(L10n.optional("common.buy") != nil)
    }

    @Test("Les paramètres sont interpolés dans l'ordre du format")
    func interpolatesArguments() {
        withLanguage(.fr) {
            #expect(t("home.next_lesson", 3, "Les dividendes") == "Leçon 3 · Les dividendes")
        }
        withLanguage(.en) {
            #expect(t("home.next_lesson", 3, "Dividends") == "Lesson 3 · Dividends")
        }
    }

    // MARK: Accord en nombre

    @Test("Le français passe au pluriel à partir de deux, l'anglais dès qu'il diffère de un")
    func pluralRulesDifferByLanguage() {
        withLanguage(.fr) {
            #expect(L10n.plural(0, one: "un", other: "autre") == "un")
            #expect(L10n.plural(1.5, one: "un", other: "autre") == "un")
            #expect(L10n.plural(2, one: "un", other: "autre") == "autre")
        }
        withLanguage(.en) {
            #expect(L10n.plural(0, one: "un", other: "autre") == "autre")
            #expect(L10n.plural(1, one: "un", other: "autre") == "un")
            #expect(L10n.plural(1.5, one: "un", other: "autre") == "autre")
        }
    }

    @Test("Une part fractionnée reste au singulier en français")
    func fractionalSharesStaySingularInFrench() {
        withLanguage(.fr) { #expect(Money.shares(0.45) == "0,45 action") }
        withLanguage(.en) { #expect(Money.shares(0.45) == "0.45 shares") }
    }

    // MARK: Montants

    /// Espaces typographiques françaises, écrites en clair pour que l'intention
    /// soit lisible : `U+202F` (espace fine insécable) sépare les milliers,
    /// `U+00A0` (espace insécable) précède le symbole monétaire et le pourcent.
    /// Une espace ordinaire à leur place autoriserait un retour à la ligne entre
    /// le nombre et son unité.
    private static let thin = "\u{202F}"
    private static let nbsp = "\u{00A0}"

    @Test("Les montants suivent la langue, symbole et séparateurs compris")
    func formatsAmountsPerLanguage() {
        withLanguage(.fr) {
            #expect(Money.euros(cents: 100_051) == "1\(Self.thin)000,51\(Self.nbsp)€")
            #expect(Money.eurosShort(25) == "25\(Self.nbsp)€")
        }
        withLanguage(.en) {
            #expect(Money.euros(cents: 100_051) == "€1,000.51")
            #expect(Money.eurosShort(25) == "€25")
        }
    }

    @Test("Le formatteur n'est pas figé sur la première langue employée")
    func formatterFollowsLanguageChange() {
        // Le cache de `Money` est indexé par devise ET par locale : une bascule
        // après un premier appel doit changer le rendu, pas resservir le format
        // de la langue précédente.
        withLanguage(.fr) { _ = Money.euros(12.34) }
        withLanguage(.en) { #expect(Money.euros(12.34) == "€12.34") }
    }

    @Test("Le pourcentage porte son espace insécable en français, pas en anglais")
    func percentSpacingFollowsTypography() {
        withLanguage(.fr) { #expect(Money.percent(1.4) == "+1,40\(Self.thin)%") }
        withLanguage(.en) { #expect(Money.percent(1.4) == "+1.40%") }
    }

    @Test("Une baisse porte le signe moins typographique, jamais le trait d'union")
    func negativeUsesMinusSign() {
        withLanguage(.fr) { #expect(Money.percent(-0.39).hasPrefix("−")) }
    }

    // MARK: Données de référence

    @Test("Le rendement et les ratios sont remis en forme selon la langue")
    func reformatsReferenceFigures() {
        withLanguage(.fr) {
            #expect(MarketLabel.percent(2.9) == "2,9\(Self.thin)%")
            #expect(MarketLabel.ratio(22.4) == "22,4")
        }
        withLanguage(.en) {
            #expect(MarketLabel.percent(2.9) == "2.9%")
            #expect(MarketLabel.ratio(22.4) == "22.4")
        }
    }

    @Test("Une donnée absente s'affiche, elle ne disparaît pas")
    func missingFigureShows() {
        #expect(MarketLabel.percent(nil) == "—")
        #expect(MarketLabel.ratio(nil) == "—")
    }

    @Test("La capitalisation change d'échelle et de place du symbole en anglais")
    func rewritesMarketCap() {
        withLanguage(.fr) { #expect(MarketLabel.marketCap("112 Md€") == "112 Md€") }
        withLanguage(.en) { #expect(MarketLabel.marketCap("112 Md€") == "€112B") }
        // Séparateur de milliers à l'anglaise sur une capitalisation à quatre chiffres.
        withLanguage(.en) { #expect(MarketLabel.marketCap("3 900 Md$") == "$3,900B") }
    }

    @Test("Un libellé de capitalisation non reconnu est rendu tel quel")
    func keepsUnparsableMarketCap() {
        withLanguage(.en) { #expect(MarketLabel.marketCap("n/d") == "n/d") }
    }

    // MARK: Contenu éditorial

    /// Les leçons sont du contenu, pas des clés de catalogue : la traduction
    /// vit dans `lessons.en.json`. Ce qui doit rester rigoureusement identique
    /// d'une langue à l'autre, c'est la *mécanique* — position, gratuité, index
    /// de la bonne réponse. Une divergence là-dessus rendrait un quiz faux en
    /// anglais sans que rien ne le signale.
    @Test("Les leçons anglaises reprennent la mécanique des leçons françaises")
    func englishLessonsMirrorFrenchMechanics() {
        let store = LearningStore()

        L10n.use(.fr)
        store.loadContent()
        let fr = store.lessons
        L10n.use(.en)
        store.loadContent()
        let en = store.lessons
        defer { L10n.use(.fr) }

        #expect(fr.count == 27)
        #expect(en.count == fr.count)

        for (f, e) in zip(fr, en) {
            #expect(f.position == e.position)
            #expect(f.isFree == e.isFree)
            #expect(f.duration == e.duration)
            #expect(f.paragraphs.count == e.paragraphs.count)
            #expect(f.examples.count == e.examples.count)
            #expect(f.quiz?.a == e.quiz?.a)
            #expect(f.quiz?.opts.count == e.quiz?.opts.count)
            // Traduite, pas recopiée : un repli sur le français passerait
            // silencieusement les vérifications de structure ci-dessus.
            #expect(f.title != e.title)
        }
    }

    /// Les fiches du catalogue de démonstration portent leurs deux langues en
    /// dur : sans traduction, l'app retomberait sur le français en anglais.
    @Test("Chaque fiche de démonstration est traduite, secteur compris")
    func demoCatalogIsFullyTranslated() {
        for stock in DemoCatalog.stocks {
            #expect(stock.whatEn != nil)
            #expect(stock.herculeEn != nil)
            #expect(stock.sectorEn != nil)
        }
    }

    @Test("Le secteur s'affiche traduit, mais reste français comme donnée")
    func sectorTranslationIsDisplayOnly() {
        guard let nvidia = DemoCatalog.stocks.first(where: { $0.symbol == "NVDA" }) else {
            Issue.record("NVDA absent du catalogue de démonstration")
            return
        }
        withLanguage(.fr) { #expect(nvidia.sectorLocalized == "Semi-conducteurs · IA") }
        withLanguage(.en) { #expect(nvidia.sectorLocalized == "Semiconductors · AI") }
        // La donnée de regroupement ne bouge pas avec la langue.
        withLanguage(.en) { #expect(nvidia.sector == "Semi-conducteurs · IA") }
    }

    // MARK: Pays

    @Test("Les pays sont traduits, et un code inconnu ne casse rien")
    func translatesCountries() {
        withLanguage(.fr) { #expect(Country.name("US") == "États-Unis") }
        withLanguage(.en) { #expect(Country.name("US") == "United States") }
        #expect(Country.name(nil) == "—")
        // Hors catalogue : la table de l'OS prend le relais.
        #expect(Country.name("JP").isEmpty == false)
    }
}
