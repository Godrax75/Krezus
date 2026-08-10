#!/usr/bin/env python3
"""Génère `Krezus/Resources/Localizable.xcstrings` et vérifie sa couverture.

Le catalogue de chaînes d'Xcode est un JSON verbeux, pénible à relire en revue :
la source de vérité est donc la table `STRINGS` ci-dessous, une clé par ligne
avec ses deux traductions côte à côte — un oubli se voit à l'œil nu.

    python3 tools/build_strings.py            # régénère le catalogue
    python3 tools/build_strings.py --check    # vérifie sans écrire (CI)

La vérification compare la table aux clés réellement appelées par `t("…")` dans
les sources Swift, y compris les familles construites à l'exécution
(`locked.<cas>.title`, `help.faq.<n>.q`…), déclarées dans `DYNAMIC_FAMILIES`.
"""

import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
CATALOG = ROOT / "Krezus" / "Resources" / "Localizable.xcstrings"
SOURCES = ROOT / "Krezus"

# clé -> (français, anglais)
STRINGS: dict[str, tuple[str, str]] = {}


def add(section: dict[str, tuple[str, str]]) -> None:
    for key, value in section.items():
        if key in STRINGS:
            raise SystemExit(f"Clé dupliquée : {key}")
        STRINGS[key] = value


# ---------------------------------------------------------------- Générique

add({
    "common.back":      ("Retour", "Back"),
    "common.close":     ("Fermer", "Close"),
    "common.cancel":    ("Annuler", "Cancel"),
    "common.continue":  ("Continuer", "Continue"),
    "common.go_back":   ("Revenir", "Go back"),
    "common.validate":  ("Valider", "Check answer"),
    "common.save":      ("Enregistrer", "Save"),
    "common.saving":    ("Enregistrement…", "Saving…"),
    "common.sending":   ("Envoi…", "Sending…"),
    "common.create":    ("Créer", "Create"),
    "common.buy":       ("Acheter", "Buy"),
    "common.sell":      ("Vendre", "Sell"),
    "common.see_all":   ("Voir tout →", "See all →"),
    "common.live":      ("Live", "Live"),
    "common.premium":   ("Premium", "Premium"),
    "common.enabled":   ("Activées", "On"),
    "common.disabled":  ("Désactivées", "Off"),
    "common.xp_badge":  ("+%d XP", "+%d XP"),
})

# Formats courts. Le pourcentage colle au nombre en anglais (« 25% ») et s'en
# sépare par une espace insécable en français (« 25 % ») — la typographie n'est
# pas une préférence, c'est la règle de chaque langue.
add({
    "format.percent_int":    ("%d %%", "%d%%"),
    "format.xp":             ("%d XP", "%d XP"),
    "format.minutes_short":  ("%d min", "%dm"),
    "format.hours_short":    ("%d h", "%dh"),
    "format.days_short":     ("%d j", "%dd"),
    "format.weeks_short":    ("%d sem", "%dw"),
    "unit.percent_suffix":   (" %", "%"),
    "unit.shares.one":       ("%@ action", "%@ share"),
    "unit.shares.other":     ("%@ actions", "%@ shares"),
})

add({
    "date.today":      ("Aujourd'hui", "Today"),
    "date.yesterday":  ("Hier", "Yesterday"),
    "date.earlier":    ("Plus tôt", "Earlier"),
    "time.just_now":   ("à l'instant", "just now"),
    "time.ago_minutes": ("il y a %d min", "%d min ago"),
    "time.ago_hours":  ("il y a %d h", "%dh ago"),
    "time.ago_days":   ("il y a %d j", "%dd ago"),
})

add({
    "tab.home":       ("Accueil", "Home"),
    "tab.portfolio":  ("Portefeuille", "Portfolio"),
    "mode.paper":     ("Virtuel", "Paper"),
    "mode.real":      ("Réel", "Real"),
    "mode.active":    ("ACTIF", "ACTIVE"),
})

# Familles de secteurs du camembert d'allocation.
add({
    "sector.technology": ("Technologie", "Technology"),
    "sector.luxury":     ("Luxe", "Luxury"),
    "sector.finance":    ("Finance", "Finance"),
    "sector.energy":     ("Énergie", "Energy"),
    "sector.industry":   ("Industrie", "Industrials"),
})

# Pays de l'univers de titres. Le reste retombe sur la table de l'OS.
add({
    "country.FR": ("France", "France"),
    "country.US": ("États-Unis", "United States"),
    "country.NL": ("Pays-Bas", "Netherlands"),
    "country.DE": ("Allemagne", "Germany"),
    "country.GB": ("Royaume-Uni", "United Kingdom"),
    "country.CH": ("Suisse", "Switzerland"),
    "country.IE": ("Irlande", "Ireland"),
    "country.LU": ("Luxembourg", "Luxembourg"),
    "country.BE": ("Belgique", "Belgium"),
    "country.IT": ("Italie", "Italy"),
    "country.ES": ("Espagne", "Spain"),
})

add({
    "disclaimer.paper_money": (
        "Argent 100 % fictif · aucune transaction réelle · cours différés 15 min",
        "100% paper money · no real transactions · quotes delayed 15 min"),
    "disclaimer.not_advice": (
        "Argent fictif. Ceci n'est pas un conseil en investissement.",
        "Paper money. This is not investment advice."),
})

add({
    "a11y.streak":              ("Série de %d jours", "%d-day streak"),
    "a11y.notifications":       ("Notifications", "Notifications"),
    "a11y.notifications_unread": ("Notifications, %d non lues", "Notifications, %d unread"),
    "a11y.profile":             ("Profil", "Profile"),
    "a11y.search":              ("Rechercher", "Search"),
    "a11y.hercule_fab":         ("Hercule", "Hercule"),
    "a11y.hercule_fab.hint":    ("Ouvre le chat avec Hercule", "Opens the chat with Hercule"),
    "a11y.expand":              ("Déplier", "Expand"),
    "a11y.collapse":            ("Replier", "Collapse"),
    "a11y.open_portfolio":      ("Ouvre le portefeuille", "Opens the portfolio"),
    "a11y.radar":               ("Radar du portefeuille", "Portfolio radar"),
})

# ------------------------------------------------------------------ Accueil

add({
    "home.portfolio_value":   ("Valeur du portefeuille", "Portfolio value"),
    "home.change_today":      ("%@ aujourd'hui", "%@ today"),
    "home.missions":          ("Missions du jour", "Today's missions"),
    "home.next_lesson":       ("Leçon %d · %@", "Lesson %d · %@"),
    "home.my_stocks":         ("Mes actions", "My stocks"),
    "home.paper_balance":     ("SOLDE PAPIER", "PAPER BALANCE"),
    "home.explore_cta":       ("Explorer les actions", "Explore stocks"),
    "home.hercule_tip.label": ("LE CONSEIL D'HERCULE", "HERCULE'S TIP"),
    "home.hercule_tip.body": (
        "Ton portefeuille est concentré sur la tech. Une action défensive comme "
        "Air Liquide équilibrerait le risque.",
        "Your portfolio leans heavily on tech. A defensive stock like Air Liquide "
        "would balance the risk."),
    "home.hercule_tip.cta":   ("Poser une question", "Ask a question"),
})

add({
    "mission.activate": ("Activer ton compte", "Activate your account"),
    "mission.lesson":   ("Terminer une leçon du jour", "Finish today's lesson"),
    "mission.quiz":     ("Réussir le quiz du jour", "Pass today's quiz"),
})

# -------------------------------------------------------------- Portefeuille

add({
    "portfolio.title":             ("Mon portefeuille", "My portfolio"),
    "portfolio.available_balance": ("SOLDE DISPONIBLE", "AVAILABLE BALANCE"),
    "portfolio.allocation":        ("Répartition", "Allocation"),
    "portfolio.positions":         ("Positions", "Positions"),
    "portfolio.explore_link":      ("Explorer →", "Explore →"),
    "portfolio.empty": (
        "Aucune position. Explore le marché pour commencer.",
        "No positions yet. Explore the market to get started."),
})

# ------------------------------------------------------------------- Marché

add({
    "market.title":              ("Explorer les actions", "Explore stocks"),
    "market.search_placeholder": ("Rechercher une action…", "Search for a stock…"),
    "market.already_owned":      ("Déjà en portefeuille", "Already in your portfolio"),
    "market.delayed_note": (
        "Cours différés d'environ 15 minutes. Argent fictif.",
        "Quotes delayed by about 15 minutes. Paper money."),
})

add({
    "stock.fallback_title":       ("Action", "Stock"),
    "stock.your_position":        ("VOTRE POSITION", "YOUR POSITION"),
    "stock.gain_since_purchase":  ("%@ depuis l'achat", "%@ since purchase"),
    "stock.hercule_explains":     ("HERCULE EXPLIQUE", "HERCULE EXPLAINS"),
    "stock.about_title":          ("Que fait l'entreprise ?", "What does the company do?"),
    "stock.fact.country":         ("Pays", "Country"),
    "stock.fact.founded":         ("Fondée", "Founded"),
    "stock.fact.dividend":        ("Dividende", "Dividend"),
    "stock.fact.market_cap":      ("Capitalisation", "Market cap"),
    "stock.fact.pe":              ("P/E", "P/E"),
    "stock.fact.peg":             ("PEG (croissance)", "PEG (growth)"),
    "stock.fact.ceo":             ("Dirigeant", "CEO"),
})

# ------------------------------------------------------------ Achat / vente

add({
    "buy.title":          ("Acheter %@", "Buy %@"),
    "buy.price_per_share": ("%@ par action", "%@ per share"),
    "buy.how_much":       ("Combien veux-tu investir ?", "How much do you want to invest?"),
    "buy.amount":         ("Montant", "Amount"),
    "buy.you_get":        ("Tu obtiens", "You get"),
    "buy.paper_balance":  ("Solde papier", "Paper balance"),
    "buy.execution_note": (
        "Achat immédiat au cours affiché. Argent fictif.",
        "Executed immediately at the displayed price. Paper money."),
    "buy.cta":            ("Acheter pour %@", "Buy %@ worth"),
    "buy.success_title":  ("Achat effectué !", "Purchase complete!"),
    "buy.success_body":   ("Ta position %@ a été mise à jour.", "Your %@ position has been updated."),
    "buy.success_cta":    ("Voir ma position", "View my position"),
})

add({
    "sell.title":          ("Vendre %@", "Sell %@"),
    "sell.position":       ("Position : %@ · %@", "Position: %@ · %@"),
    "sell.how_much":       ("Quelle part veux-tu vendre ?", "How much do you want to sell?"),
    "sell.all":            ("Tout", "All"),
    "sell.all_lowercase":  ("tout", "everything"),
    "sell.shares_sold":    ("Parts vendues", "Shares sold"),
    "sell.you_receive":    ("Tu reçois", "You receive"),
    "sell.execution_note": (
        "Vente immédiate au cours affiché. Argent fictif.",
        "Sold immediately at the displayed price. Paper money."),
    "sell.cta":            ("Vendre %@", "Sell %@"),
    "sell.success_title":  ("Vente effectuée !", "Sale complete!"),
    "sell.success_body": (
        "Le produit a été crédité sur ton solde papier.",
        "The proceeds have been credited to your paper balance."),
    "sell.success_cta":    ("Retour au portefeuille", "Back to portfolio"),
})

add({
    "order.error.insufficient_funds": ("Solde insuffisant pour cet achat.", "Not enough cash for this purchase."),
    "order.error.no_position":        ("Aucune position à vendre.", "No position to sell."),
    "order.error.unknown_stock":      ("Action inconnue.", "Unknown stock."),
    "order.error.not_signed_in":      ("Session expirée. Reconnecte-toi pour passer un ordre.",
                                       "Session expired. Sign in again to place an order."),
})

# ------------------------------------------------------------------ Academy

add({
    "academy.your_rank":         ("TON RANG", "YOUR RANK"),
    "academy.xp_to_next":        ("Plus que %d XP pour devenir %@", "%d XP to go to reach %@"),
    "academy.max_rank":          ("Rang maximal atteint", "Highest rank reached"),
    "academy.all_ranks":         ("Tous les rangs →", "All ranks →"),
    "academy.streak_days.one":   ("jour de série", "day streak"),
    "academy.streak_days.other": ("jours de série", "day streak"),
    "academy.lessons_done":      ("leçons terminées", "lessons completed"),
    "academy.lessons":           ("Les leçons", "Lessons"),
    "academy.lessons_total":     ("%d au total", "%d in total"),
    "academy.quiz_passed":       ("· quiz réussi", "· quiz passed"),
})

add({
    "lesson.nav_title":  ("Leçon %d", "Lesson %d"),
    "lesson.not_found":  ("Leçon introuvable", "Lesson not found"),
    "lesson.completed":  ("Terminée", "Completed"),
    "lesson.concretely": ("CONCRÈTEMENT", "IN PRACTICE"),
    "lesson.go_to_quiz": ("Passer au quiz", "Take the quiz"),
    "lesson.finish":     ("Terminer la leçon", "Finish lesson"),
    "lesson.toast":      ("Leçon terminée", "Lesson completed"),
    "lesson.toast_xp":   ("Leçon terminée · +%d XP", "Lesson completed · +%d XP"),
    "learning.error.locked": (
        "Leçon réservée aux abonnés Premium.",
        "This lesson is reserved for Premium subscribers."),
})

add({
    "quiz.nav_title": ("Quiz", "Quiz"),
    "quiz.none":      ("Cette leçon n'a pas de quiz.", "This lesson has no quiz."),
    "quiz.correct":   ("Bonne réponse !", "Correct!"),
    "quiz.not_saved": ("Progression non enregistrée : %@", "Progress not saved: %@"),
    "quiz.incorrect": ("Pas tout à fait", "Not quite"),
})

add({
    "ranks.nav_title":    ("Tous les rangs", "All ranks"),
    "ranks.current":      ("ACTUEL", "CURRENT"),
    "ranks.xp_range":     ("%d – %d XP", "%d – %d XP"),
    "ranks.xp_and_above": ("%d XP et au-delà", "%d XP and above"),
    "ranks.xp_missing":   ("−%d XP", "−%d XP"),
    "ranks.intro": (
        "Chaque palier se franchit tous les 200 XP. Les leçons, les quiz et ta "
        "série quotidienne y contribuent.",
        "Each tier is 200 XP apart. Lessons, quizzes and your daily streak all "
        "count towards it."),
})

# ------------------------------------------------------------------- Oracle

add({
    "oracle.tab.analysis":  ("Analyse", "Analysis"),
    "oracle.tab.scenarios": ("Scénarios", "Scenarios"),
    "oracle.tab.coach":     ("Coach", "Coach"),
    "oracle.tab.profile":   ("Profil", "Profile"),
    "oracle.disclaimer": (
        "Krezus présente des chiffres publics et des mécanismes économiques à but "
        "pédagogique. Ceci n'est pas un conseil en investissement.",
        "Krezus presents public figures and economic mechanisms for educational "
        "purposes. This is not investment advice."),
    "oracle.movers.title":    ("Les mouvements du jour", "Today's movers"),
    "oracle.movers.subtitle": ("Variation depuis l'ouverture.", "Change since the open."),
    "oracle.movers.empty":    ("Aucun mouvement pour l'instant.", "Nothing moving right now."),
    "oracle.valuation.title": ("Repères de valorisation", "Valuation markers"),
    "oracle.valuation.subtitle": (
        "PER médian des titres disponibles : %@. Un PER élevé traduit des attentes "
        "de croissance fortes — ce n'est ni un signal d'achat, ni un signal de vente.",
        "Median P/E across available stocks: %@. A high P/E reflects strong growth "
        "expectations — it is neither a buy signal nor a sell signal."),
    "oracle.valuation.pe":         ("PER %@", "P/E %@"),
    "oracle.valuation.pe_missing": ("PER non disponible", "P/E not available"),
    "oracle.valuation.none": (
        "Aucun PER disponible dans le référentiel actuel.",
        "No P/E available in the current reference data."),
    "oracle.dividends.title": ("Les meilleurs rendements", "Highest yields"),
    "oracle.dividends.subtitle": (
        "Dividende annuel rapporté au cours, tel que publié par l'entreprise.",
        "Annual dividend relative to the share price, as published by the company."),
    "oracle.scenarios.intro": (
        "Quatre situations qui reviennent régulièrement sur les marchés, et ce "
        "qu'elles impliquent mécaniquement. Aucune n'est une prévision.",
        "Four situations that come up regularly in the markets, and what they "
        "mechanically imply. None of them is a forecast."),
    "oracle.scenario.trigger":   ("LE DÉCLENCHEUR", "THE TRIGGER"),
    "oracle.scenario.mechanism": ("CE QUI SE PASSE", "WHAT HAPPENS"),
    "oracle.scenario.portfolio": ("CÔTÉ PORTEFEUILLE", "FOR A PORTFOLIO"),
})

add({
    "coach.axis.diversification": ("Diversification", "Diversification"),
    "coach.axis.balance":         ("Équilibre", "Balance"),
    "coach.axis.regularity":      ("Régularité", "Consistency"),
    "coach.axis.knowledge":       ("Connaissance", "Knowledge"),
    "coach.axis.openness":        ("Ouverture", "Reach"),
    "coach.detail.sectors.one":   ("%d secteur représenté", "%d sector represented"),
    "coach.detail.sectors.other": ("%d secteurs représentés", "%d sectors represented"),
    "coach.detail.top_line":      ("Plus grosse ligne : %d %% du portefeuille",
                                   "Largest holding: %d%% of the portfolio"),
    "coach.detail.no_position":   ("Aucune position", "No positions"),
    "coach.detail.streak.one":    ("%d jour de série", "%d-day streak"),
    "coach.detail.streak.other":  ("%d jours de série", "%d-day streak"),
    "coach.detail.lessons.one":   ("%d leçon sur %d", "%d lesson out of %d"),
    "coach.detail.lessons.other": ("%d leçons sur %d", "%d lessons out of %d"),
    "coach.detail.foreign_share": ("%d %% hors France", "%d%% outside France"),
    "coach.attention_point":      ("LE POINT D'ATTENTION", "WORTH A LOOK"),
    "coach.advice.diversification": (
        "Ton portefeuille repose sur peu de secteurs. La leçon « La diversification » "
        "explique pourquoi ça compte.",
        "Your portfolio rests on few sectors. The lesson “Diversification” "
        "explains why that matters."),
    "coach.advice.balance": (
        "Une ligne pèse une grande part de ton portefeuille : sa variation entraîne "
        "presque tout le reste.",
        "One holding carries a large share of your portfolio: its moves drag almost "
        "everything else along."),
    "coach.advice.regularity": (
        "Revenir régulièrement compte plus que le montant investi. C'est le sujet de "
        "la leçon sur les intérêts composés.",
        "Coming back regularly matters more than the amount invested. That is what "
        "the lesson on compound interest is about."),
    "coach.advice.knowledge": (
        "Il te reste des leçons à découvrir dans l'Academy — chacune éclaire une "
        "décision que tu prendras tôt ou tard.",
        "You still have lessons to discover in the Academy — each one sheds light on "
        "a decision you will face sooner or later."),
    "coach.advice.openness": (
        "Ton portefeuille est concentré sur une seule zone géographique. D'autres "
        "marchés suivent des cycles différents.",
        "Your portfolio is concentrated in a single region. Other markets follow "
        "different cycles."),
})

add({
    "investor_profile.intro": (
        "Six questions pour cerner ton tempérament d'investisseur. Il n'y a pas de "
        "bonne réponse — seulement la tienne.",
        "Six questions to pin down your investing temperament. There is no right "
        "answer — only yours."),
    "investor_profile.your_profile": ("TON PROFIL", "YOUR PROFILE"),
    "investor_profile.dna_title":    ("Ton ADN d'investisseur", "Your investor DNA"),
    "investor_profile.restart":      ("Refaire le questionnaire", "Retake the questionnaire"),
    "investor_profile.disclaimer": (
        "Ce profil oriente les explications que Krezus te propose. Il ne restreint "
        "aucune fonctionnalité et ne constitue pas une évaluation réglementaire.",
        "This profile shapes the explanations Krezus offers you. It restricts no "
        "feature and is not a regulatory assessment."),
    "dna.patience":   ("Patience", "Patience"),
    "dna.prudence":   ("Prudence", "Caution"),
    "dna.curiosity":  ("Curiosité", "Curiosity"),
    "dna.regularity": ("Régularité", "Consistency"),
    "archetype.guardian.name": ("Le Gardien", "The Guardian"),
    "archetype.guardian.summary": (
        "Tu privilégies la sécurité avant le rendement. Les baisses te coûtent plus "
        "qu'elles ne t'attirent — c'est un tempérament, pas un défaut.",
        "You put safety before return. Drops cost you more than they tempt you — "
        "that is a temperament, not a flaw."),
    "archetype.explorer.name": ("L'Explorateur", "The Explorer"),
    "archetype.explorer.summary": (
        "Tu es à l'aise avec le mouvement et tu aimes comprendre ce qui bouge. Ton "
        "risque, c'est de confondre activité et progrès.",
        "You are comfortable with movement and like to understand what is shifting. "
        "Your risk is mistaking activity for progress."),
    "archetype.builder.name": ("Le Bâtisseur", "The Builder"),
    "archetype.builder.summary": (
        "Tu construis par petites touches régulières. C'est le tempérament qui "
        "profite le plus des intérêts composés.",
        "You build in small, regular steps. That is the temperament compound "
        "interest rewards most."),
    "archetype.balanced.name": ("L'Équilibré", "The Balanced"),
    "archetype.balanced.summary": (
        "Tu cherches un compromis entre sécurité et croissance, sans excès dans un "
        "sens ou dans l'autre.",
        "You look for a middle ground between safety and growth, without going too "
        "far either way."),
})

# -------------------------------------------------------------------- Arena

add({
    "arena.tab.leaderboard": ("Classement", "Leaderboard"),
    "arena.tab.friends":     ("Amis", "Friends"),
    "arena.tab.feed":        ("Feed", "Feed"),
    "arena.tab.groups":      ("Groupes", "Groups"),
    "arena.me":              ("Toi", "You"),
    "arena.group_filter":    ("Groupe : %@", "Group: %@"),
    "arena.see_all_friends": ("Voir tous mes amis", "See all my friends"),
    "arena.performance_title": ("Performance depuis le départ", "Performance since day one"),
    "arena.performance_subtitle": (
        "Écart au capital de %@. Les montants ne sont jamais partagés.",
        "Change from the starting %@. Amounts are never shared."),
    "arena.disclaimer": (
        "Portefeuilles en argent fictif. Les classements comparent des progressions "
        "en pourcentage, jamais des sommes investies.",
        "Paper-money portfolios. Leaderboards compare percentage progress, never "
        "the amounts invested."),
    "arena.feed.title": ("Activité récente", "Recent activity"),
    "arena.feed.empty": (
        "Rien à afficher. L'activité de tes amis apparaîtra ici.",
        "Nothing yet. Your friends' activity will show up here."),
    "arena.requests.title":       ("Demandes reçues", "Friend requests"),
    "arena.mutual_friends.one":   ("%d ami en commun", "%d mutual friend"),
    "arena.mutual_friends.other": ("%d amis en commun", "%d mutual friends"),
    "arena.mutual_friends.none":  ("Aucun ami en commun", "No mutual friends"),
    "arena.accept_request":       ("Accepter la demande", "Accept request"),
    "arena.decline_request":      ("Refuser la demande", "Decline request"),
    "arena.friends.title":        ("Mes amis", "My friends"),
    "arena.friends.empty": (
        "Personne pour l'instant. Accepte une demande ou rejoins un groupe pour "
        "comparer ta progression.",
        "Nobody yet. Accept a request or join a group to compare your progress."),
    "arena.streak.one":   ("%d jour de série", "%d-day streak"),
    "arena.streak.other": ("%d jours de série", "%d-day streak"),
    "arena.remove_friend": ("Retirer de mes amis", "Remove friend"),
    "arena.join.title":    ("Rejoindre un groupe", "Join a group"),
    "arena.join.subtitle": (
        "Entre le code à 6 caractères que t'a transmis un ami.",
        "Enter the 6-character code a friend sent you."),
    "arena.join.cta":              ("Rejoindre", "Join"),
    "arena.group_name_placeholder": ("Nom du groupe", "Group name"),
    "arena.create_group":          ("Créer mon propre groupe", "Create my own group"),
    "arena.my_groups":             ("Mes groupes", "My groups"),
    "arena.group_code":            ("Code %@", "Code %@"),
    "arena.leave_group":           ("Quitter le groupe", "Leave group"),
    "arena.toast.request_accepted": ("%@ a rejoint ton cercle", "%@ joined your circle"),
    "arena.toast.request_declined": ("Demande refusée", "Request declined"),
    "arena.toast.friend_removed":   ("%@ retiré", "%@ removed"),
    "arena.toast.joined":           ("Bienvenue dans %@", "Welcome to %@"),
    "arena.toast.group_created":    ("Groupe créé · code %@", "Group created · code %@"),
    "arena.toast.group_left":       ("Groupe quitté", "Left the group"),
    "arena.toast.filtered":         ("Classement filtré sur %@", "Leaderboard filtered to %@"),
    "arena.error.already_friends":  ("Vous êtes déjà amis.", "You are already friends."),
    "arena.error.unknown_code":     ("Code d'invitation invalide.", "Invalid invite code."),
    "arena.error.already_member":   ("Tu fais déjà partie de ce groupe.", "You are already in this group."),
    "arena.error.empty_name":       ("Donne un nom à ton groupe.", "Give your group a name."),
    "arena.error.demo_unavailable": ("Crée un compte pour rejoindre l’Arena.",
                                     "Create an account to join the Arena."),
    "feed.verb.buy":     ("a acheté", "bought"),
    "feed.verb.sell":    ("a vendu", "sold"),
    "feed.verb.lesson":  ("a terminé", "completed"),
    "feed.verb.rank_up": ("est passé", "reached"),
    "demo_feed.rank":    ("Sénateur", "Senator"),
    "demo_feed.lesson":  ("La diversification", "Diversification"),
})

# ------------------------------------------------------------------ Hercule

add({
    "hercule.greeting": (
        "Salut ! Je suis Hercule. Pose-moi une question sur la bourse — comment se "
        "lit un cours, ce que mesure un PER, pourquoi un dividende existe. Je "
        "t'explique, je ne te dis pas quoi acheter.",
        "Hi! I'm Hercule. Ask me anything about the stock market — how to read a "
        "quote, what a P/E measures, why dividends exist. I explain things; I don't "
        "tell you what to buy."),
    "hercule.answer.refusal": (
        "Je ne te dirai pas quoi acheter ou vendre — ce serait un conseil en "
        "investissement, et ce n'est pas mon rôle. En revanche je peux t'expliquer "
        "comment se juge une entreprise : ce que raconte son PER, d'où vient son "
        "dividende, ou pourquoi son secteur bouge. Par quoi tu veux commencer ?",
        "I won't tell you what to buy or sell — that would be investment advice, and "
        "it isn't my role. What I can do is explain how a company is assessed: what "
        "its P/E says, where its dividend comes from, or why its sector is moving. "
        "Where would you like to start?"),
    "hercule.answer.pe_ratio": (
        "Le PER compare le prix d'une action à ce que l'entreprise gagne chaque "
        "année. Un PER de 20 veut dire que tu paies 20 années de bénéfices actuels. "
        "Élevé, il traduit des attentes de croissance fortes ; bas, il signale soit "
        "une action délaissée, soit une entreprise en difficulté. Ce n'est pas un "
        "signal en soi, c'est un point de comparaison entre entreprises d'un même secteur.",
        "The P/E compares a share price with what the company earns each year. A P/E "
        "of 20 means you are paying 20 years of current profits. High, it reflects "
        "strong growth expectations; low, it signals either an overlooked stock or a "
        "struggling company. It isn't a signal in itself — it's a way to compare "
        "companies within the same sector."),
    "hercule.answer.dividend": (
        "Un dividende, c'est une part des bénéfices que l'entreprise reverse à ses "
        "actionnaires, en général une ou plusieurs fois par an. Toutes n'en versent "
        "pas : celles qui grandissent vite préfèrent réinvestir. Air Liquide, que tu "
        "as en portefeuille, en augmente le sien depuis plus de trente ans — c'est "
        "ce qu'on appelle un profil de rendement.",
        "A dividend is a share of profits the company pays back to its shareholders, "
        "usually once or several times a year. Not every company pays one: fast "
        "growers prefer to reinvest. Air Liquide, which you hold, has raised its own "
        "for over thirty years — that's what's called an income profile."),
    "hercule.answer.diversify": (
        "Diversifier, c'est répartir entre plusieurs entreprises, secteurs et pays, "
        "pour qu'une mauvaise nouvelle sur l'une ne fasse pas plonger l'ensemble. "
        "Nvidia et Air Liquide, c'est déjà deux mondes différents : la tech "
        "américaine et l'industrie française ne réagissent pas aux mêmes signaux. Le "
        "risque ne disparaît pas, il devient moins concentré.",
        "Diversifying means spreading across several companies, sectors and "
        "countries, so bad news about one doesn't sink the whole. Nvidia and Air "
        "Liquide are already two different worlds: US tech and French industry don't "
        "react to the same signals. The risk doesn't disappear, it just becomes less "
        "concentrated."),
    "hercule.answer.price_move": (
        "Un cours, c'est le prix auquel acheteurs et vendeurs se mettent d'accord, "
        "en continu pendant la séance. Il bouge parce que les attentes bougent : un "
        "résultat publié, une décision de banque centrale, une rumeur. La variation "
        "du jour compare simplement le cours actuel à la clôture de la veille.",
        "A quote is the price buyers and sellers agree on, continuously through the "
        "session. It moves because expectations move: published earnings, a central "
        "bank decision, a rumour. The daily change simply compares the current price "
        "with yesterday's close."),
    "hercule.answer.fallback": (
        "Bonne question. En mode démo je n'ai que quelques réponses préparées — "
        "essaie « c'est quoi le PER ? », « comment marche un dividende ? » ou "
        "« pourquoi un cours varie ? ». Une fois le backend branché, je répondrai à "
        "tout, en m'appuyant sur ton portefeuille et tes leçons.",
        "Good question. In demo mode I only have a few prepared answers — try “what "
        "is the P/E?”, “how does a dividend work?” or “why does a price move?”. Once "
        "the backend is connected I'll answer anything, drawing on your portfolio "
        "and your lessons."),
    "hercule.quota.premium":    ("Premium · questions illimitées", "Premium · unlimited questions"),
    "hercule.quota.left.one":   ("%d question restante aujourd'hui", "%d question left today"),
    "hercule.quota.left.other": ("%d questions restantes aujourd'hui", "%d questions left today"),
    "hercule.quota.exhausted":  ("Quota du jour atteint", "Daily limit reached"),
    "hercule.input_placeholder": ("Pose ta question…", "Ask your question…"),
    "hercule.send":             ("Envoyer", "Send"),
    "hercule.paywall_card.title": ("Tu as utilisé tes %d questions du jour",
                                   "You've used your %d questions for today"),
    "hercule.paywall_card.body": (
        "Hercule Premium débloque les questions illimitées et les 23 leçons "
        "réservées aux abonnés.",
        "Hercule Premium unlocks unlimited questions and the 23 subscriber-only "
        "lessons."),
    "hercule.paywall_card.cta": ("Découvrir Premium · %@/mois", "See Premium · %@/month"),
    "hercule.disclaimer": (
        "Hercule explique le fonctionnement des marchés. Il ne donne aucun conseil "
        "en investissement et ne recommande jamais d'acheter ou de vendre un titre.",
        "Hercule explains how markets work. He gives no investment advice and never "
        "recommends buying or selling a stock."),
})

add({
    "paywall.title":    ("Hercule Premium", "Hercule Premium"),
    "paywall.subtitle": ("Ton compagnon d'apprentissage, sans limite de questions.",
                         "Your learning companion, with no question limit."),
    "paywall.benefit.unlimited.title":  ("Questions illimitées", "Unlimited questions"),
    "paywall.benefit.unlimited.detail": ("Au lieu de %d par jour.", "Instead of %d a day."),
    "paywall.benefit.lessons.title":    ("Les 27 leçons", "All 27 lessons"),
    "paywall.benefit.lessons.detail":   ("Dont les 23 réservées aux abonnés.",
                                         "Including the 23 subscriber-only ones."),
    "paywall.benefit.analysis.title":   ("Analyses de portefeuille", "Portfolio insights"),
    "paywall.benefit.analysis.detail": (
        "Hercule s'appuie sur tes positions pour illustrer ses explications.",
        "Hercule draws on your holdings to illustrate his explanations."),
    "paywall.unavailable.title": ("Abonnement indisponible", "Subscription unavailable"),
    "paywall.unavailable.body": (
        "Le produit n'est pas encore publié sur App Store Connect.",
        "The product isn't published on App Store Connect yet."),
    "paywall.unavailable.short": ("Abonnement indisponible pour le moment.",
                                  "Subscription unavailable right now."),
    "paywall.purchasing":     ("Achat en cours…", "Purchase in progress…"),
    "paywall.subscribe_cta":  ("S'abonner · %@/mois", "Subscribe · %@/month"),
    "paywall.restore":        ("Restaurer mes achats", "Restore purchases"),
    "paywall.pending":        ("Achat en attente d'autorisation.", "Purchase awaiting approval."),
    "paywall.toast_welcome":  ("Bienvenue dans Hercule Premium", "Welcome to Hercule Premium"),
    "paywall.legal": (
        "Abonnement mensuel reconductible, facturé sur ton compte Apple. Il se "
        "renouvelle automatiquement sauf résiliation au moins 24 h avant la fin de "
        "la période en cours. Tu peux le gérer et le résilier dans les réglages de "
        "ton compte App Store.",
        "Monthly auto-renewing subscription, billed to your Apple account. It renews "
        "automatically unless cancelled at least 24 hours before the end of the "
        "current period. You can manage and cancel it in your App Store account "
        "settings."),
    "paywall.paper_note": (
        "Krezus utilise de l'argent fictif. L'abonnement donne accès à du contenu "
        "pédagogique, pas à un service d'investissement.",
        "Krezus uses paper money. The subscription gives access to educational "
        "content, not to an investment service."),
    "legal.terms":       ("Conditions d'utilisation", "Terms of use"),
    "legal.terms_url":   ("https://krezus.app/cgu", "https://krezus.app/terms"),
    "legal.privacy":     ("Confidentialité", "Privacy"),
    "legal.privacy_url": ("https://krezus.app/confidentialite", "https://krezus.app/privacy"),
    "storekit.error.product_missing": ("Produit introuvable. Vérifie la configuration StoreKit.",
                                       "Product not found. Check the StoreKit configuration."),
    "storekit.error.unverified":      ("Transaction non vérifiée.", "Unverified transaction."),
    "storekit.error.unexpected":      ("Réponse inattendue de l'App Store.",
                                       "Unexpected response from the App Store."),
})

# ------------------------------------------------------------------- Profil

add({
    "profile.title":            ("Profil", "Profile"),
    "profile.default_username": ("Investisseur", "Investor"),
    "profile.member_since":     ("Membre depuis %@", "Member since %@"),
    "profile.premium_badge":    ("HERCULE PREMIUM", "HERCULE PREMIUM"),
    "profile.edit_username":    ("Modifier le pseudo", "Edit username"),
    "profile.max_rank":         ("Rang maximal atteint — Empereur.", "Highest rank reached — Emperor."),
    "profile.next_rank":        ("Encore %d XP avant %@.", "%d XP to go before %@."),
    "profile.stat.lessons":     ("Leçons", "Lessons"),
    "profile.stat.positions":   ("Positions", "Positions"),
    "profile.stat.badges":      ("Badges", "Badges"),
    "profile.group.account":     ("Compte", "Account"),
    "profile.group.preferences": ("Préférences", "Preferences"),
    "profile.group.real_mode":   ("Mode réel · bientôt disponible", "Real mode · coming soon"),
    "profile.group.discover":    ("Découvrir", "Discover"),
    "profile.group.support":     ("Aide", "Help"),
    "profile.row.username":      ("Pseudo", "Username"),
    "profile.row.streak":        ("Ma série", "My streak"),
    "profile.row.streak.one":    ("%d jour d'affilée", "%d day in a row"),
    "profile.row.streak.other":  ("%d jours d'affilée", "%d days in a row"),
    "profile.row.mode":          ("Mode d'investissement", "Investing mode"),
    "profile.row.appearance":    ("Apparence et langue", "Appearance and language"),
    "profile.row.notifications": ("Notifications", "Notifications"),
    "profile.row.security":      ("Sécurité", "Security"),
    "profile.row.help":          ("Centre d'aide", "Help centre"),
    "profile.row.reset":         ("Réinitialiser le portefeuille", "Reset portfolio"),
    "profile.row.reset_detail":  ("Repartir de %@ virtuels", "Start over with %@ in paper money"),
    "profile.premium.active":        ("Abonnement actif", "Subscription active"),
    "profile.premium.active_detail": (
        "Les 27 leçons, le brief du jour et l'analyse comportementale sont débloqués.",
        "All 27 lessons, the daily brief and behavioural insights are unlocked."),
    "profile.premium.upgrade":        ("Passer à Hercule Premium", "Upgrade to Hercule Premium"),
    "profile.premium.upgrade_detail": (
        "Débloque les 27 leçons, le brief du jour et l'analyse comportementale.",
        "Unlock all 27 lessons, the daily brief and behavioural insights."),
    "profile.reset.title":   ("Réinitialiser le portefeuille virtuel ?", "Reset the paper portfolio?"),
    "profile.reset.confirm": ("Réinitialiser", "Reset"),
    "profile.reset.toast":   ("Portefeuille remis à %@ virtuels", "Portfolio reset to %@ in paper money"),
    "profile.reset.message": (
        "Tes positions seront soldées et ton solde ramené à %@ fictifs. Ta "
        "progression Academy et ton rang sont conservés.",
        "Your positions will be closed and your balance reset to %@ in paper money. "
        "Your Academy progress and rank are kept."),
    "profile.sign_out":       ("Se déconnecter", "Sign out"),
    "profile.sign_out.title": ("Se déconnecter ?", "Sign out?"),
    "profile.delete.title":   ("Supprimer définitivement ton compte ?", "Permanently delete your account?"),
    "profile.delete.confirm": ("Supprimer mon compte", "Delete my account"),
    "profile.delete.message": (
        "Portefeuille, progression, badges, amis et conversations avec Hercule "
        "seront effacés sans possibilité de récupération.",
        "Portfolio, progress, badges, friends and conversations with Hercule will be "
        "erased with no way to recover them."),
    "profile.footer_version": ("Krezus %@ · conçu à Paris", "Krezus %@ · made in Paris"),
})

add({
    "username.field_label": ("PSEUDO", "USERNAME"),
    "username.placeholder": ("ton pseudo", "your username"),
    "username.counter":     ("%d/20", "%d/20"),
    "username.hint":        ("3 à 20 caractères, sans espace.", "3 to 20 characters, no spaces."),
    "username.note": (
        "Ton pseudo est visible par tes amis dans l'Arena et au classement. Ton "
        "prénom et ton nom, eux, ne le sont jamais.",
        "Your username is visible to friends in the Arena and on the leaderboard. "
        "Your first and last name never are."),
    "username.toast_saved":            ("Pseudo mis à jour", "Username updated"),
    "username.error.too_short":        ("Au moins 3 caractères.", "At least 3 characters."),
    "username.error.too_long":         ("20 caractères maximum.", "20 characters maximum."),
    "username.error.invalid_characters": ("Lettres, chiffres, tiret et tiret bas uniquement.",
                                          "Letters, digits, hyphen and underscore only."),
})

add({
    "streak.title":                ("Ma série", "My streak"),
    "streak.days_in_a_row.one":    ("jour", "day"),
    "streak.days_in_a_row.other":  ("jours d'affilée", "days in a row"),
    "streak.record.one":           ("Record : %d jour", "Record: %d day"),
    "streak.record.other":         ("Record : %d jours", "Record: %d days"),
    "streak.this_week":            ("Cette semaine", "This week"),
    "streak.safe_title":           ("Série sauvée pour aujourd'hui", "Streak secured for today"),
    "streak.safe_body":            ("Reviens demain pour la porter à %d jours.",
                                    "Come back tomorrow to take it to %d days."),
    "streak.at_risk_title":        ("Ta série est en jeu", "Your streak is at risk"),
    "streak.at_risk_body":         ("Une leçon de 2 minutes suffit à la prolonger.",
                                    "A 2-minute lesson is enough to keep it going."),
    "streak.do_lesson":            ("Faire la leçon du jour", "Take today's lesson"),
    "streak.how_it_works":         ("Comment ça marche", "How it works"),
    "streak.rule.lesson": (
        "Une leçon terminée dans la journée fait avancer la série d'un jour.",
        "One lesson finished during the day moves the streak forward by one day."),
    "streak.rule.miss": (
        "Un jour sans activité la remet à 1 — mais ton record, lui, reste.",
        "A day without activity resets it to 1 — but your record stays."),
    "streak.rule.xp": (
        "La série ne rapporte pas d'XP par elle-même : l'XP vient des missions du "
        "jour, plafonnées à 50 XP.",
        "The streak earns no XP by itself: XP comes from the daily missions, capped "
        "at 50 XP."),
})

add({
    "mode.sheet.title": ("Ton argent sur Krezus", "Your money on Krezus"),
    "mode.sheet.intro": (
        "Le mode virtuel est complet : mêmes titres, mêmes cours, mêmes mécaniques "
        "d'ordre. Seules les conséquences sont fictives.",
        "Paper mode is complete: same stocks, same prices, same order mechanics. "
        "Only the consequences are fictional."),
    "mode.paper.detail": ("%@ fictifs, rechargeables à volonté",
                          "%@ in paper money, top up whenever you like"),
    "mode.real.detail": (
        "Ouvert dès qu'un partenariat courtier agréé sera en place",
        "Opening as soon as a licensed broker partnership is in place"),
    "mode.sheet.legal": (
        "Krezus n'exécute aucun ordre sur un instrument financier réel et ne "
        "conserve aucun titre. Aucune garantie de dépôt ne s'applique — il n'y a "
        "rien à garantir.",
        "Krezus executes no orders on real financial instruments and holds no "
        "securities. No deposit guarantee applies — there is nothing to guarantee."),
})

# ------------------------------------------------------------------ Réglages

add({
    "settings.appearance":      ("Apparence", "Appearance"),
    "appearance.system":        ("Système", "System"),
    "appearance.light":         ("Clair", "Light"),
    "appearance.dark":          ("Sombre", "Dark"),
    "settings.appearance_note": (
        "« Système » suit le réglage d'iOS et bascule avec lui au coucher du soleil.",
        "“System” follows your iOS setting and switches with it at sunset."),
    "settings.language": ("Langue", "Language"),
    "settings.language_note": (
        "Le changement s'applique immédiatement, leçons et fiches d'entreprise comprises.",
        "The change applies immediately, lessons and company profiles included."),
    "settings.discovery":                ("Découverte", "Discovery"),
    "settings.replay_onboarding":        ("Revoir la présentation", "Replay the intro"),
    "settings.replay_onboarding_detail": ("Les trois écrans d'introduction", "The three intro screens"),
    "settings.replay_toast": ("La présentation s'affichera au prochain lancement",
                              "The intro will show on next launch"),
})

add({
    "security.group.access":  ("Accès à l'app", "App access"),
    "security.lock_with":     ("Verrouiller avec %@", "Lock with %@"),
    "security.lock_detail":   ("Demandé à chaque retour dans l'app.", "Asked every time you come back to the app."),
    "security.lock_unavailable": ("Indisponible : aucun code n'est configuré sur cet appareil.",
                                  "Unavailable: no passcode is set on this device."),
    "security.device_passcode": ("Code de l'appareil", "Device passcode"),
    "security.group.session":   ("Session", "Session"),
    "security.signed_in_with":  ("Connecté avec", "Signed in with"),
    "security.email":           ("Adresse e-mail", "Email address"),
    "security.demo_mode":       ("Mode démo", "Demo mode"),
    "security.demo_mode_detail": ("Aucun compte n'est rattaché : tout vit sur cet appareil.",
                                  "No account is attached: everything lives on this device."),
    "security.group.data":      ("Tes données", "Your data"),
    "security.hosting":         ("Hébergement", "Hosting"),
    "security.hosting_detail":  ("Union européenne (Francfort). Aucune donnée ne quitte l'UE.",
                                 "European Union (Frankfurt). No data leaves the EU."),
    "security.never_shared":    ("Ce qui n'est jamais partagé", "What is never shared"),
    "security.never_shared_detail": (
        "Tes montants et tes positions restent privés : l'Arena n'expose que ton "
        "pseudo, ton rang et une performance en pourcentage.",
        "Your amounts and holdings stay private: the Arena only exposes your "
        "username, your rank and a percentage performance."),
    "security.privacy_terms": ("Confidentialité et conditions", "Privacy and terms"),
    "lock.title":             ("Krezus est verrouillé", "Krezus is locked"),
    "lock.unlock_with":       ("Déverrouiller avec %@", "Unlock with %@"),
    "lock.reason":            ("Déverrouiller Krezus", "Unlock Krezus"),
})

add({
    "notif_settings.group.topics":   ("Ce que tu veux recevoir", "What you want to receive"),
    "notif_settings.group.in_app":   ("Dans l'app", "In the app"),
    "notif_settings.center_detail":  ("L'historique reste consultable même sans push",
                                      "History stays available even without push"),
    "notif_settings.on":             ("Notifications activées", "Notifications on"),
    "notif_settings.off":            ("Notifications désactivées", "Notifications off"),
    "notif_settings.enable":         ("Activer les notifications", "Turn on notifications"),
    "notif_settings.open_ios_settings": ("Ouvrir les réglages iOS", "Open iOS Settings"),
    "notif_settings.status.denied": (
        "Tu les as refusées : seule l'app Réglages d'iOS peut les réactiver.",
        "You declined them: only the iOS Settings app can turn them back on."),
    "notif_settings.status.no_token": (
        "Cet appareil n'est pas encore enregistré auprès d'APNs — normal au simulateur.",
        "This device isn't registered with APNs yet — expected on the simulator."),
    "notif_settings.status.registered": (
        "Cet appareil est enregistré et recevra les alertes cochées ci-dessous.",
        "This device is registered and will receive the alerts ticked below."),
    "notif_settings.status.default": (
        "Rappels de leçon, ordres exécutés, demandes d'amis : rien ne partira sans "
        "ton accord.",
        "Lesson reminders, executed orders, friend requests: nothing goes out "
        "without your consent."),
    "notif_settings.policy": (
        "Krezus n'envoie jamais de notification à caractère promotionnel sur un "
        "titre, ni d'alerte incitant à passer un ordre. Les seules alertes de marché "
        "portent sur les positions que tu détiens déjà.",
        "Krezus never sends promotional notifications about a stock, nor alerts "
        "nudging you to place an order. The only market alerts concern positions you "
        "already hold."),
    "topic.market.title":     ("Marché", "Market"),
    "topic.market.subtitle":  ("Mouvements marquants sur tes positions", "Notable moves on your holdings"),
    "topic.academy.title":    ("Academy", "Academy"),
    "topic.academy.subtitle": ("Rappel de la leçon du jour et série en danger",
                               "Daily lesson reminder and streak at risk"),
    "topic.arena.title":      ("Arena", "Arena"),
    "topic.arena.subtitle":   ("Demandes d'amis et dépassements au classement",
                               "Friend requests and leaderboard overtakes"),
    "topic.hercule.title":    ("Hercule", "Hercule"),
    "topic.hercule.subtitle": ("Brief du jour et réponses d'Hercule", "Daily brief and Hercule's replies"),
})

add({
    "notif_center.title":          ("Centre de notifications", "Notification centre"),
    "notif_center.mark_all_read":  ("Tout marquer comme lu", "Mark all as read"),
    "notif_center.unread":         ("Non lue", "Unread"),
    "notif_center.empty_title":    ("Aucune notification", "No notifications"),
    "notif_center.empty_body": (
        "Les ordres exécutés, les passages de rang et les demandes d'amis "
        "apparaîtront ici.",
        "Executed orders, rank-ups and friend requests will show up here."),
    "demo_notif.rank_up.title": ("Tu passes Légionnaire", "You've reached Legionary"),
    "demo_notif.rank_up.body":  ("200 XP franchis. Le rang suivant, Centurion, est à 400 XP.",
                                 "200 XP passed. The next rank, Centurion, is at 400 XP."),
    "demo_notif.lesson.title":  ("Ta leçon du jour t'attend", "Your lesson of the day is waiting"),
    "demo_notif.lesson.body":   ("2 minutes suffisent pour garder ta série de 5 jours.",
                                 "2 minutes are enough to keep your 5-day streak."),
    "demo_notif.order.title":   ("Achat exécuté · Nvidia", "Order filled · Nvidia"),
    "demo_notif.order.body":    ("%@ investis, %@ au portefeuille virtuel.",
                                 "%@ invested, %@ in the paper portfolio."),
    "demo_notif.friend.title":  ("Camille veut rejoindre ton Arena", "Camille wants to join your Arena"),
    "demo_notif.friend.body":   ("Vous avez %d amis en commun.", "You have %d mutual friends."),
})

# ---------------------------------------------------------------------- Aide

add({
    "help.group.faq":            ("Questions fréquentes", "Frequently asked questions"),
    "help.group.contact":        ("Nous écrire", "Get in touch"),
    "help.group.legal":          ("Mentions légales", "Legal"),
    "help.contact_support":      ("Contacter le support", "Contact support"),
    "help.report_issue":         ("Signaler un problème", "Report a problem"),
    "help.report_issue_detail":  ("Une erreur de cours, un contenu inexact",
                                  "A wrong quote, an inaccurate piece of content"),
    "help.faq.0.q": ("L'argent est-il réel ?", "Is the money real?"),
    "help.faq.0.a": (
        "Non. Krezus fonctionne exclusivement en argent fictif : 1 000 € virtuels au "
        "départ, aucune transaction sur un instrument financier réel, aucun gain ni "
        "aucune perte. Rien n'est à déclarer aux impôts.",
        "No. Krezus runs entirely on paper money: €1,000 in virtual cash to start, "
        "no transaction on a real financial instrument, no gain and no loss. There "
        "is nothing to declare to the tax authorities."),
    "help.faq.1.q": ("D'où viennent les cours ?", "Where do the prices come from?"),
    "help.faq.1.a": (
        "Des places US et Euronext Paris, avec un différé de 15 minutes imposé par "
        "la licence de redistribution. La pastille « différé 15 min » est affichée "
        "partout où un prix apparaît.",
        "From US exchanges and Euronext Paris, with a 15-minute delay required by "
        "the redistribution licence. The “delayed 15 min” badge appears wherever a "
        "price is shown."),
    "help.faq.2.q": ("Comment gagne-t-on de l'XP ?", "How do you earn XP?"),
    "help.faq.2.a": (
        "Par les missions du jour : 50 XP à l'activation du compte, 20 XP pour une "
        "leçon terminée et 30 XP pour un quiz réussi. Enchaîner dix leçons d'affilée "
        "ne rapporte donc pas dix fois 20 XP — le plafond est quotidien, pour que la "
        "régularité compte plus que le marathon.",
        "Through the daily missions: 50 XP when you activate your account, 20 XP for "
        "a finished lesson and 30 XP for a passed quiz. Running through ten lessons "
        "in a row therefore doesn't earn ten times 20 XP — the cap is daily, so that "
        "consistency counts more than marathons."),
    "help.faq.3.q": ("Que voient mes amis dans l'Arena ?", "What do my friends see in the Arena?"),
    "help.faq.3.a": (
        "Ton pseudo, ton rang, ta série et ta performance en pourcentage. Jamais un "
        "montant, jamais la composition de ton portefeuille.",
        "Your username, your rank, your streak and your percentage performance. "
        "Never an amount, never what your portfolio holds."),
    "help.faq.4.q": ("Hercule peut-il me dire quoi acheter ?", "Can Hercule tell me what to buy?"),
    "help.faq.4.a": (
        "Non, et c'est délibéré. Hercule explique ce que fait une entreprise, ce que "
        "signifie un ratio, comment lire une variation. Il ne formule aucune "
        "recommandation personnalisée d'achat ou de vente : ce serait du conseil en "
        "investissement, un métier réglementé.",
        "No, and that is deliberate. Hercule explains what a company does, what a "
        "ratio means, how to read a change. He makes no personalised buy or sell "
        "recommendation: that would be investment advice, a regulated profession."),
    "help.faq.5.q": ("Comment fonctionne l'abonnement Premium ?", "How does the Premium subscription work?"),
    "help.faq.5.a": (
        "5,99 € par mois via l'App Store, résiliable à tout moment depuis les "
        "réglages de ton compte Apple. Il débloque les 27 leçons, le brief du jour "
        "et l'analyse comportementale.",
        "€5.99 a month through the App Store, cancellable at any time from your "
        "Apple account settings. It unlocks all 27 lessons, the daily brief and "
        "behavioural insights."),
    "help.faq.6.q": ("Puis-je repartir de zéro ?", "Can I start over?"),
    "help.faq.6.a": (
        "Oui : Profil → Réinitialiser le portefeuille remet le solde à 1 000 € "
        "fictifs et solde les positions. Ta progression Academy, ton rang et tes "
        "badges sont conservés.",
        "Yes: Profile → Reset portfolio puts the balance back to €1,000 in paper "
        "money and closes your positions. Your Academy progress, rank and badges are "
        "kept."),
    "help.legal.educational": (
        "Krezus est une application pédagogique. Les performances passées ne "
        "préjugent pas des performances futures, et aucun contenu de l'app ne "
        "constitue un conseil en investissement personnalisé.",
        "Krezus is an educational app. Past performance does not predict future "
        "performance, and no content in the app constitutes personalised investment "
        "advice."),
    "help.legal.oracle": (
        "Les analyses, scénarios et prédictions présentés dans l'Oracle sont fournis "
        "à titre informatif. Les données de prédiction proviennent de marchés "
        "publics et ne sont reliées à aucune plateforme de paris.",
        "The analyses, scenarios and predictions shown in the Oracle are provided "
        "for information only. Prediction data comes from public markets and is not "
        "linked to any betting platform."),
    "help.legal.quotes": (
        "Les cours sont différés de 15 minutes et ne peuvent pas être redistribués. "
        "Les logos d'entreprises sont utilisés à titre d'identification des titres.",
        "Prices are delayed by 15 minutes and may not be redistributed. Company "
        "logos are used to identify securities."),
})

# ------------------------------------------------------------ Écrans vitrine

add({
    "locked.badge":            ("Bientôt disponible", "Coming soon"),
    "locked.continue_paper":   ("Continuer en mode virtuel", "Continue in paper mode"),
    "locked.reason.real_mode": (
        "Disponible avec le mode réel, soumis à un partenariat courtier agréé.",
        "Available with real mode, subject to a licensed broker partnership."),
    "locked.kyc.title":   ("Vérifier mon identité", "Verify my identity"),
    "locked.kyc.promise": (
        "Vérifier ton identité sera l'étape d'entrée du mode réel : pièce "
        "d'identité, justificatif de domicile et questionnaire d'adéquation, exigés "
        "par la réglementation européenne.",
        "Verifying your identity will be the entry step into real mode: ID document, "
        "proof of address and a suitability questionnaire, as required by European "
        "regulation."),
    "locked.activateCard.title":   ("Activer une carte", "Activate a card"),
    "locked.activateCard.promise": (
        "Activer une carte permettra d'alimenter un compte réel. En mode virtuel, "
        "ton solde de 1 000 € fictifs se recharge d'un simple appui sur "
        "« Réinitialiser ».",
        "Activating a card will let you fund a real account. In paper mode, your "
        "€1,000 paper balance tops up with a single tap on “Reset”."),
    "locked.reveal.title":   ("Révélation", "The Reveal"),
    "locked.reveal.promise": (
        "La Révélation dévoilera chaque semaine une entreprise choisie pour ce "
        "qu'elle enseigne, avec l'éclairage d'Hercule.",
        "The Reveal will unveil one company a week, chosen for what it teaches, with "
        "Hercule's commentary."),
    "locked.reveal.reason": ("Le rendez-vous hebdomadaire est en cours d'écriture.",
                             "The weekly feature is still being written."),
    "locked.giftBox.title":   ("Offrir un coffret", "Gift a box"),
    "locked.giftBox.promise": (
        "Offrir un coffret permettra de transmettre quelques actions à un proche, "
        "emballage et mot d'accompagnement compris.",
        "Gifting a box will let you pass a few shares to someone close, wrapping and "
        "handwritten note included."),
    "locked.recurringInvestment.title":   ("Investissement programmé", "Recurring investment"),
    "locked.recurringInvestment.promise": (
        "L'investissement programmé placera automatiquement le même montant chaque "
        "mois — le geste qui fait la différence sur dix ans.",
        "Recurring investment will automatically place the same amount every month — "
        "the habit that makes the difference over ten years."),
    "locked.myCards.title":   ("Mes cartes", "My cards"),
    "locked.myCards.promise": (
        "Tes cartes physique et virtuelle apparaîtront ici, avec leurs plafonds et "
        "leur code.",
        "Your physical and virtual cards will appear here, with their limits and "
        "their PIN."),
    "locked.referral.title":   ("Parrainage", "Referrals"),
    "locked.referral.promise": ("Le parrainage récompensera les amis que tu amènes dans l'Arena.",
                                "Referrals will reward the friends you bring into the Arena."),
    "locked.referral.reason":  ("Le programme de récompenses n'est pas encore ouvert.",
                                "The rewards programme isn't open yet."),
    "locked.taxDocuments.title":   ("Documents fiscaux", "Tax documents"),
    "locked.taxDocuments.promise": (
        "L'IFU et le récapitulatif annuel seront téléchargeables ici. Le mode "
        "virtuel ne génère aucune obligation fiscale : aucun gain n'est réel.",
        "The annual tax statement and summary will be downloadable here. Paper mode "
        "creates no tax obligation: no gain is real."),
    "locked.taxDocuments.reason": ("Rien à déclarer : Krezus n'utilise que de l'argent fictif.",
                                   "Nothing to declare: Krezus only uses paper money."),
    "locked.bankDetails.title":   ("Coordonnées bancaires", "Bank details"),
    "locked.bankDetails.promise": (
        "Tes coordonnées bancaires serviront aux virements entrants et sortants du "
        "mode réel.",
        "Your bank details will be used for incoming and outgoing transfers in real "
        "mode."),
    "locked.realCode.title":   ("Code d'accès au mode réel", "Real-mode access code"),
    "locked.realCode.promise": (
        "Le mode réel s'ouvrira par invitation. Ce code y donnera accès une fois le "
        "partenariat courtier finalisé.",
        "Real mode will open by invitation. This code will grant access once the "
        "broker partnership is finalised."),
})

# --------------------------------------------------------- Onboarding / auth

add({
    "onboarding.skip":  ("Passer", "Skip"),
    "onboarding.start": ("Commencer en virtuel", "Start in paper mode"),
    "onboarding.0.title": ("Investis sans risquer un euro", "Invest without risking a cent"),
    "onboarding.0.body": (
        "Tu démarres avec 1 000 € fictifs sur de vraies actions, aux vrais cours. "
        "Tout se joue comme en réel — sauf les conséquences.",
        "You start with €1,000 in paper money on real stocks, at real prices. "
        "Everything plays out like the real thing — except the consequences."),
    "onboarding.1.title": ("Comprends ce que tu achètes", "Understand what you're buying"),
    "onboarding.1.body": (
        "27 leçons de deux minutes, un quiz après chacune, et Hercule pour "
        "t'expliquer un ratio ou un secteur quand tu bloques.",
        "27 two-minute lessons, a quiz after each one, and Hercule to explain a "
        "ratio or a sector whenever you get stuck."),
    "onboarding.2.title": ("Progresse avec les autres", "Progress alongside others"),
    "onboarding.2.body": (
        "Du Plébéien à l'Empereur : six rangs à gravir, une série quotidienne à "
        "tenir, et une Arena où comparer ta progression à celle de tes amis.",
        "From Plebeian to Emperor: six ranks to climb, a daily streak to keep, and "
        "an Arena to compare your progress with your friends'."),
    "onboarding.mode.title":    ("Choisis ton mode", "Choose your mode"),
    "onboarding.mode.subtitle": (
        "Un seul est ouvert en v1 — et c'est celui qui permet de se tromper.",
        "Only one is open in v1 — the one where you're allowed to get it wrong."),
    "onboarding.mode.paper_detail": ("%@ fictifs · vrais cours · aucun risque",
                                     "%@ in paper money · real prices · no risk"),
    "onboarding.mode.real_detail": (
        "Nécessite un partenariat courtier agréé — bientôt disponible",
        "Requires a licensed broker partnership — coming soon"),
    "signin.tagline":    ("Apprends à investir sans risque.", "Learn to invest, risk-free."),
    "signin.google":     ("Continuer avec Google", "Continue with Google"),
    "signin.paper_note": ("Argent 100 % fictif · aucune transaction réelle",
                          "100% paper money · no real transactions"),
    "auth.error.apple_token": ("Jeton Apple manquant", "Missing Apple token"),
})

add({
    "backend.error.not_configured":   ("Application non configurée (Supabase).",
                                       "App not configured (Supabase)."),
    "backend.error.not_found":        ("Portefeuille ou position introuvable.",
                                       "Portfolio or position not found."),
    "backend.error.quote_unavailable": ("Cours indisponible pour le moment.",
                                        "Price unavailable right now."),
    "backend.error.quote_stale":      ("Cours trop ancien, réessaie dans un instant.",
                                       "Price too old, try again in a moment."),
    "backend.error.invalid_amount":   ("Montant invalide.", "Invalid amount."),

    # Codes KR020 et suivants. Les messages levés par PL/pgSQL sont en français
    # dans les migrations : sans ces clés, un anglophone lirait le SQL brut.
    "backend.error.unknown_mission":  ("Mission inconnue.", "Unknown mission."),
    "backend.error.invalid_profile":  ("Réponses de profil incomplètes.",
                                       "Incomplete profile answers."),
    "backend.error.user_not_found":   ("Utilisateur introuvable.", "User not found."),
    # KR041 couvre deux cas volontairement fondus côté serveur (soi-même, ou
    # lien déjà existant) : le message doit rester vrai pour les deux.
    "backend.error.friend_request_rejected": ("Cette demande d’ami n’est pas possible.",
                                              "That friend request isn’t possible."),
    "backend.error.no_pending_request": ("Aucune demande en attente de cette personne.",
                                         "No pending request from that person."),
    "backend.error.invalid_invite_code": ("Code d’invitation invalide.",
                                          "Invalid invite code."),
    "backend.error.already_in_group": ("Tu fais déjà partie de ce groupe.",
                                       "You’re already in this group."),
    "backend.error.hercule_quota":    ("Quota de questions épuisé pour aujourd’hui.",
                                       "You’ve used today’s questions."),
    "backend.error.hercule_message":  ("Message vide ou trop long.",
                                       "Message empty or too long."),
    "backend.error.invalid_receipt":  ("Reçu d’achat invalide.", "Invalid purchase receipt."),
})

# --------------------------------------------------------------- Génération

LANGUAGES = ("fr", "en")

# Familles de clés assemblées à l'exécution : le vérificateur ne peut pas les
# lire dans le code, on les déclare ici pour qu'une clé manquante se voie.
DYNAMIC_FAMILIES = (
    "locked.", "mission.", "coach.advice.", "coach.axis.", "help.faq.",
    "onboarding.", "archetype.", "hercule.answer.", "country.", "dna.",
)


def build_catalog() -> dict:
    strings = {}
    for key, (fr, en) in sorted(STRINGS.items()):
        strings[key] = {
            # « manual » : les clés ne sont pas extraites des sources par Xcode
            # (elles transitent par `t(…)`), il ne doit donc pas les élaguer.
            "extractionState": "manual",
            "localizations": {
                lang: {"stringUnit": {"state": "translated", "value": value}}
                for lang, value in zip(LANGUAGES, (fr, en))
            },
        }
    return {"sourceLanguage": "fr", "strings": strings, "version": "1.0"}


def keys_used_in_sources() -> set[str]:
    used: set[str] = set()
    pattern = re.compile(r'\bt\(\s*"([^"]+)"|(?:one|other):\s*"([^"]+)"')
    for path in SOURCES.rglob("*.swift"):
        for match in pattern.finditer(path.read_text()):
            key = match.group(1) or match.group(2)
            if "\\(" not in key:
                used.add(key)
    return used


def check() -> int:
    used = keys_used_in_sources()
    missing = sorted(used - STRINGS.keys())
    unused = sorted(
        key for key in STRINGS.keys() - used
        if not any(key.startswith(prefix) for prefix in DYNAMIC_FAMILIES)
    )

    for key in missing:
        print(f"MANQUANTE  {key}   (appelée dans le code, absente de la table)")
    for key in unused:
        print(f"INUTILISÉE {key}   (dans la table, appelée nulle part)")

    print(f"{len(STRINGS)} clés traduites · {len(used)} appelées statiquement")
    return 1 if missing else 0


def main() -> int:
    status = check()
    if "--check" not in sys.argv:
        CATALOG.write_text(
            json.dumps(build_catalog(), ensure_ascii=False, indent=2) + "\n")
        print(f"→ {CATALOG.relative_to(ROOT)}")
    return status


if __name__ == "__main__":
    raise SystemExit(main())
