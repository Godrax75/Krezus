# Krezus — app iOS de paper investing

Application iOS native (SwiftUI) de **paper trading** (argent fictif), portée depuis le
prototype Claude Design « Krezus mobile app design v1 ». Univers d'actions US + Euronext
Paris, gamification (rangs romains, XP, leçons), assistant pédagogique Hercule.

Plan complet : `~/.claude/plans/use-the-claude-design-mcp-recursive-lake.md`.

## État — Lots 0 à 10 (i18n, dark mode et accessibilité livrés)

**Lot 2 (backend)** : moteur d'ordres papier vérifié (6/6 tests sur Postgres réel), stack SQL
complet qui s'applique proprement (81 titres, 27 leçons, 6 rangs), et couche Swift complète
(client Supabase, auth Apple/Google, modèles, repositories, store) qui **compile, link et
tourne** avec le SDK `supabase-swift`. L'app fonctionne en mode démo tant que les secrets
Supabase ne sont pas renseignés — voir `supabase/README.md` pour brancher un vrai projet EU.

**Branchement des données** : les cinq stores portent chacun deux sources
derrière la même interface. Sans secrets Supabase ou sans session, c'est le
**mode démo** (contenu embarqué, prix simulés, logique locale). Avec un compte,
c'est le **mode serveur**. La bascule se fait dans `KrezusApp`, à la
restauration de session, et nulle part ailleurs.

| Store | Mode serveur |
|---|---|
| `TradingStore` | référentiel `securities`, `quotes_cache` différé de 15 min relu toutes les 60 s, ordres par `execute_paper_buy` / `_sell` |
| `LearningStore` | `complete_lesson` accorde l'XP et la série ; leçons, missions et badges relus depuis `v_academy_progress` |
| `OracleStore` | profil investisseur via `save_investor_profile` |
| `ArenaStore` | amis, demandes, groupes et feed ; classement par `v_arena_leaderboard` |
| `HerculeStore` | Edge Function `hercule` (Claude API), quota décompté en base |

La règle commune : **le client ne calcule ni montant, ni XP, ni quota**. Il
envoie l'événement et relit l'état. Rejouer une requête ne doit pouvoir
fabriquer ni cash, ni rang, ni messages gratuits.

⚠️ Le chemin serveur compile et est couvert par des tests unitaires, mais n'a
**pas encore tourné contre un vrai projet Supabase** : les secrets sont restés
sur les placeholders. C'est la première chose à vérifier après avoir créé le
projet EU — et le seul moyen de valider les requêtes PostgREST des quatre
repositories les plus récents (Academy, Oracle, Arena, Hercule), qu'aucun test
ne peut exercer sans base.

**Tests** : `xcodebuild test -scheme Krezus -destination 'name=iPhone 17 Pro'`
— 42 tests (moteur d'ordres papier en miroir du SQL, fraîcheur des cotations,
mapping référentiel → fiche, localisation, formats et parité du contenu éditorial
FR/EN).

**Lot 10 (i18n · dark mode · accessibilité)** : l'interface est intégralement bilingue
(505 clés FR/EN dans `Localizable.xcstrings`), la langue se change dans Réglages et
s'applique immédiatement, les montants et dates suivent la locale (« 1 000,51 € » ⇄
« €1,000.51 »), la typographie suit Dynamic Type jusqu'à AX5 et la palette passe le
contraste AA. Vérifié au simulateur en FR/EN × clair/sombre × tailles L et XXXL.

Générer/ouvrir le projet, puis lancer :

```bash
xcodegen generate && open Krezus.xcodeproj
```

### Distribution

Le dépôt est prêt pour TestFlight : manifeste de confidentialité, conformité
export, icône sans canal alpha, signature paramétrable et script d'archivage.

```bash
tools/archive.sh --upload
```

Ce qui reste dépend d'un compte Apple Developer (App ID, fiche d'app,
abonnement, clé APNs) — la marche à suivre et les réponses à saisir dans App
Store Connect sont dans [`docs/testflight.md`](docs/testflight.md).

### Logos d'entreprises

`KrzSecurityBadge` affiche le logo quand l'imageset existe et retombe sur les initiales
sinon — silencieusement, donc un logo manquant ne se voit qu'à l'œil. 6 des 40 logos
référencés par `securities.sql` sont importés ; les autres attendent l'export du dossier
`assets/` depuis claude.ai/design.

```bash
python3 tools/import_design_assets.py <dossier-exporté>
```

Le script porte la table de correspondance entre le nom de fichier du design
(« Capgemini.png ») et la valeur `logo_asset` du seed (« capgemini »), réduit les sources
— jusqu'à 3840×3072 pour une pastille rendue à 40 pt — et les décline en @1x/@2x/@3x. Il
liste en sortie ce qui manque encore.

### Traductions

La source de vérité est la table de `tools/build_strings.py`, qui génère le catalogue Xcode
et vérifie qu'aucune clé appelée dans le code ne manque (et inversement) :

```bash
python3 tools/build_strings.py
```

**Le contenu éditorial est traduit** — il ne restait que les fichiers à écrire, la
mécanique de bascule était déjà en place :

| Contenu | Où vit la traduction |
|---|---|
| Les 27 leçons Academy et leurs quiz | `Krezus/Resources/lessons.en.json` |
| Les 81 fiches action de la base | `securities.description_en` / `hercule_note_en`, remplies par `supabase/seed/securities_en.sql` |
| Les libellés de secteur (« Gaz industriels » → « Industrial gases ») | colonne `sector_en` (migration `0010`), dédoublée du français |

Le français reste la langue de rédaction : une colonne `*_en` ou un fichier `.en.json`
absent fait retomber l'écran sur le français plutôt que sur du vide. `sector` garde sa
valeur française même en anglais — c'est la donnée qui sert au regroupement du
portefeuille et aux médianes sectorielles de l'Oracle ; seul l'affichage est traduit.

Un test vérifie que les leçons anglaises reprennent exactement la mécanique des
françaises (position, gratuité, index de la bonne réponse) — un quiz faux en anglais
serait invisible autrement.

Les 14 fiches du catalogue de démonstration, les 6 rangs, les 4 scénarios Oracle et les
6 questions du profil investisseur sont traduits eux aussi.

```
Krezus/
  App/                   KrezusApp, RootView (header + tab bar + FAB Hercule)
  DesignSystem/          tokens couleur/typo/métriques + composants (carte, boutons, stock row…)
  Features/              Home + Portfolio (fidèles), Oracle/Arena/Academy (placeholders)
  Core/Store/            AppState (@Observable)
  Resources/Assets.xcassets  mascotte + AppIcon + couleurs light/dark
supabase/
  migrations/
    0001_init.sql        schéma complet (titres, portefeuille papier, academy, arena…)
    0002_paper_engine.sql moteur d'ordres transactionnel (buy/sell/reset) en PL/pgSQL
    0003_rls.sql         Row Level Security + trigger de création de compte
  seed/
    securities.sql       81 titres (actions FR/US mappées EODHD + 30 ETF à mapper)
    securities_en.sql    traduction anglaise des 81 fiches + libellés de secteur
    lessons.sql          27 leçons + quiz, FR
    ranks_missions_badges.sql  6 rangs, 3 missions, 5 badges
tools/
  extract_design_content.py  régénère les seeds depuis le script du prototype
```

## Contenu récupéré depuis le prototype

Le fichier canonique `Krezus App.dc.html` (264 KiB) dépasse le plafond de 256 KiB de
`DesignSync.get_file` et est tronqué au milieu du `<script>`. En croisant les trois
variantes exportées (`.dc.html`, `-base44-`, `-lovable-`), on a récupéré :

- **81 fiches actions** (nom, secteur, pays, dividende, capitalisation, P/E, PEG,
  dirigeant, description FR, note pédagogique d'Hercule) — variante `-base44-`, la plus complète
- **27 leçons Academy** avec quiz — variante `-lovable-`
- Les **tokens du design** (couleurs, typo, rayons, ombres) — `colors_and_type.css`
- Le **frame iOS** de référence — `ios-frame.jsx`

## Encore inaccessible (à récupérer avant les lots concernés)

Ces éléments sont au-delà du point de troncature dans les trois variantes. Les récupérer
en exportant le fichier complet depuis claude.ai/design (pas via l'API plafonnée) :

| Contenu | Bloque le lot |
|---|---|
| Table de traduction **FR ⇄ EN** (toutes les clés `t_*`) | 10 (i18n) |
| Réponses scriptées d'**Hercule** + chips de chat | 8 |
| Scénarios **Oracle** (Amundi) et listes sous/sur-évaluées | 6 |
| Machine à états du prototype (transitions d'écrans) | 4 (référence) |
| 82ᵉ fiche action **GS** (Goldman Sachs), tronquée en fin de bloc | 4 (mineur) |
| Leçon 28 « Comment une entreprise entre en bourse », tronquée | 5 (mineur) |

Rien de bloquant pour démarrer les Lots 1–3 (design system, backend, données marché).

## Régénérer les seeds

```bash
python3 tools/extract_design_content.py <script-base44.js> <script-lovable.js>
```

## Prérequis manquants sur cette machine

Xcode est installé et la suite de tests passe. Restent les comptes tiers, dont dépend
tout le mode serveur :

- Compte **Supabase** (région EU), clé **EODHD** (plan EOD+Intraday, 29,99 €/mois),
  clé **Claude API** — à placer en variables d'environnement des Edge Functions, jamais dans l'app.
