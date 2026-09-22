# Mise en distribution TestFlight

Tout ce qui pouvait être préparé dans le dépôt l'est : manifeste de
confidentialité, conformité export, icône conforme, signature paramétrable,
script d'archivage. Reste ce qui exige un compte Apple — c'est la partie 1.

---

## 1. Ce que seul le titulaire du compte peut faire

Aucune de ces étapes n'est automatisable depuis le dépôt : elles engagent une
identité juridique et un moyen de paiement.

| # | Action | Où | Note |
|---|---|---|---|
| 1 | Adhérer à l'**Apple Developer Program** (99 $/an) | developer.apple.com | Compter 24 à 48 h de validation, davantage pour une entité morale (numéro D-U-N-S requis) |
| 2 | Relever le **Team ID** et le poser dans `Krezus/Config/Secrets.xcconfig` → `KREZUS_TEAM_ID` | Membership details | Le fichier n'est pas versionné |
| 3 | Enregistrer l'**App ID** `com.krezus.app` avec les capacités **Sign in with Apple** et **Push Notifications** | Certificates, IDs & Profiles | Les capacités doivent correspondre à `Krezus.entitlements`, sinon la signature échoue |
| 4 | Créer une **clé APNs** (.p8) et la déposer côté Supabase | Keys | Sans elle, les push partent dans le vide — l'app fonctionne, les notifications non |
| 5 | Créer la **fiche d'app** (nom, langue principale : français, bundle ID, SKU) | App Store Connect | Le nom « Krezus » doit être disponible |
| 6 | Créer l'**abonnement** `com.krezus.hercule.monthly` à 5,99 €/mois | App Store Connect → Monétisation | Tant qu'il n'existe pas, `Product.products(for:)` rend une liste vide et le paywall affiche « Abonnement indisponible » — comportement voulu, mais à vérifier une fois créé |
| 7 | Créer une **clé d'API App Store Connect** pour l'envoi en ligne de commande | Users and Access → Integrations | Voir §3 |
| 8 | Publier les pages **CGU** et **confidentialité** | krezus-card.com | Le paywall y renvoie (`legal.terms_url`, `legal.privacy_url`) : des liens morts sont un motif de rejet |
| 9 | Ouvrir la boîte **bonjour@krezus-card.com** et brancher l'envoi (voir `docs/emails.md`) | — | Adresse affichée dans le Centre d'aide |

**Décision à prendre avant d'archiver** : renseigner ou non les secrets Supabase
dans `Secrets.xcconfig`. À vide, la build TestFlight tourne en **mode démo**
(données locales, aucun compte) — parfait pour faire essayer l'interface, mais
les testeurs ne verront ni l'authentification, ni la synchronisation, ni les
notifications.

---

## 2. Archiver et envoyer

```bash
tools/archive.sh            # archive + .ipa dans build/export/
tools/archive.sh --validate # + validation par App Store Connect, sans publier
tools/archive.sh --upload   # + envoi sur TestFlight
```

Le script refuse de démarrer si `KREZUS_TEAM_ID` est vide, vérifie le catalogue
de traductions, puis horodate le numéro de build (`202607291530`) — App Store
Connect rejette tout `CFBundleVersion` déjà vu, même après suppression du build.
Forcer une valeur : `KREZUS_BUILD_NUMBER=42 tools/archive.sh`.

Pour l'envoi, une clé d'API App Store Connect (`.p8` dans
`~/.appstoreconnect/private_keys/`) :

```bash
export ASC_KEY_ID=XXXXXXXXXX
export ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
tools/archive.sh --upload
```

### Vérification après export

L'entitlement `aps-environment` vaut `development` dans les sources — c'est ce
qu'il faut pour lancer depuis Xcode. Xcode le bascule sur `production` en
signant pour l'App Store. **Le vérifier plutôt que le supposer** : des push
muets en TestFlight n'ont pas d'autre cause fréquente.

```bash
unzip -q build/export/Krezus.ipa -d /tmp/krezus-ipa
codesign -d --entitlements :- /tmp/krezus-ipa/Payload/Krezus.app | grep -A1 aps-environment
```

---

## 3. Réponses à préparer dans App Store Connect

### Conformité export

La question ne sera pas posée : `ITSAppUsesNonExemptEncryption = false` est dans
l'`Info.plist`. Krezus n'utilise que HTTPS et les primitives du système —
chiffrement exempté.

### App Privacy

À saisir à l'identique du manifeste `Krezus/Resources/PrivacyInfo.xcprivacy` ;
une divergence entre les deux est relevée automatiquement.

| Donnée | Collectée | Liée à l'identité | Suivi publicitaire | Finalité |
|---|---|---|---|---|
| Adresse e-mail | oui | oui | **non** | Fonctionnement de l'app |
| Nom | oui | oui | **non** | Fonctionnement de l'app |
| Identifiant utilisateur | oui | oui | **non** | Fonctionnement de l'app |
| Identifiant d'appareil (jeton APNs) | oui | oui | **non** | Fonctionnement de l'app |
| Autre contenu utilisateur (portefeuille fictif, progression, questions à Hercule) | oui | oui | **non** | Fonctionnement de l'app |

« Suivi » : **non** partout. Aucun SDK d'attribution, aucun identifiant
publicitaire, aucune donnée transmise à un courtier — donc pas de fenêtre ATT.

### Classification par âge

Répondre **non** à « jeux d'argent simulés » : Krezus ne comporte ni mise, ni
gain, ni hasard rémunéré. Le portefeuille est fictif et le dit sur chaque écran.

⚠️ Point à trancher avant la mise en vente : le plan retient **16 ans** comme
âge minimum d'inscription (en France, le consentement parental est requis
en dessous de 15 ans). Cette contrainte n'est pas encore appliquée dans le
parcours d'inscription.

---

## 4. Informations de test bêta

### Français

> **Krezus, c'est quoi**
> Une app pour apprendre à investir avec de l'argent 100 % fictif. Tu démarres
> avec 1 000 € virtuels sur de vraies actions (Paris et New York), aux vrais
> cours différés de 15 minutes. Aucune transaction réelle, aucun risque.
>
> **Ce qu'on aimerait que tu testes**
> 1. L'achat et la vente : va dans Explorer, choisis une action, achète pour
>    100 €, vérifie ton portefeuille, puis revends la moitié. Les chiffres
>    tombent-ils juste ?
> 2. L'Academy : fais une leçon et son quiz. La progression d'XP et le rang
>    bougent-ils comme annoncé ?
> 3. Le changement de langue et de thème (Profil → Apparence et langue). La
>    bascule est-elle instantanée, et le français impeccable ?
> 4. Hercule (le bouton flottant) : pose-lui une question. En bêta, ses réponses
>    sont scriptées et volontairement limitées.
>
> **Ce qui est encore incomplet**
> Les réponses d'Hercule sont scriptées en bêta. Les écrans du mode réel
> (carte, KYC, fiscalité) sont volontairement verrouillés : aucun partenariat
> courtier n'est signé.
>
> Un souci, une idée : bonjour@krezus-card.com

### English

> **What Krezus is**
> An app for learning to invest with 100% paper money. You start with €1,000 in
> virtual cash on real stocks (Paris and New York), at real prices delayed by 15
> minutes. No real transactions, no risk.
>
> **What we'd like you to test**
> 1. Buying and selling: go to Explore, pick a stock, buy €100 worth, check your
>    portfolio, then sell half. Do the numbers add up?
> 2. The Academy: take a lesson and its quiz. Do XP and rank move as announced?
> 3. Switching language and theme (Profile → Appearance and language). Is the
>    switch instant, and the English clean?
> 4. Hercule (the floating button): ask a question. In beta his answers are
>    scripted and deliberately limited.
>
> **What's still incomplete**
> Hercule's answers are scripted in beta. Real-mode screens (card, KYC, tax)
> are deliberately locked: no broker partnership is signed.
>
> Anything broken, any idea: bonjour@krezus-card.com

### Notes pour la revue (test externe uniquement)

Le test **interne** (jusqu'à 100 membres de l'équipe) démarre sans revue. Le
test **externe** (jusqu'à 10 000 testeurs) passe par une revue Apple, plus
rapide que celle de l'App Store mais réelle. À écrire dans les notes :

> Krezus est une application **pédagogique** de paper trading. Aucun argent réel
> n'est manipulé : les portefeuilles sont fictifs, aucun ordre n'est transmis à
> un marché, aucun titre n'est conservé. L'app n'est pas un service
> d'investissement et ne fournit aucun conseil personnalisé — l'assistant
> Hercule refuse explicitement toute recommandation d'achat ou de vente.
>
> Les cours proviennent d'un fournisseur de données de marché sous licence, avec
> le différé de 15 minutes exigé par les conditions de redistribution, mentionné
> partout où un prix apparaît.
>
> L'abonnement « Hercule Premium » (5,99 €/mois) passe exclusivement par
> StoreKit 2 et débloque du contenu pédagogique. Aucun paiement web, aucun lien
> sortant.
>
> Connexion : Sign in with Apple suffit, aucun compte de démonstration n'est
> nécessaire. Sans configuration serveur, l'app fonctionne en mode démo autonome.

---

## 5. Avant de couper la première build

- [ ] `python3 tools/build_strings.py --check` — aucune clé manquante
- [ ] `tools/archive.sh` — l'archive et l'export passent
- [ ] `KREZUS_TEAM_ID` renseigné
- [ ] Icône sans canal alpha : `sips -g hasAlpha Krezus/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png` → `no`
      (au besoin : `python3 tools/flatten_app_icon.py`)
- [ ] `MARKETING_VERSION` cohérent dans `project.yml`
- [ ] Pages CGU et confidentialité en ligne
- [ ] Abonnement créé dans App Store Connect
- [ ] Décision prise sur les secrets Supabase (mode démo ou compte réel)
