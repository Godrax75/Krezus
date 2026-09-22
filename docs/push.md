# Notifications

## Ce qui est en place

L'app demande l'autorisation, enregistre le jeton de l'appareil dans
`device_tokens`, et la boîte de réception (`notifications`) se remplit déjà :
ordre exécuté, montée de rang, badge, demande d'ami, parrainage. Jusqu'ici,
**rien ne sortait du serveur** — ces messages n'existaient que dans l'app,
visibles seulement par quelqu'un qui l'ouvrait.

La fonction `push` (0026) envoie maintenant de vraies notifications, à
commencer par le rappel du versement hebdomadaire : les 300 € ne se
réclament qu'en ouvrant l'app et ne se reportent pas d'une semaine sur
l'autre. Sans rappel, la récompense ne profite qu'à ceux qui y pensaient
déjà.

| Cadence | Campagne | Message |
|---|---|---|
| Lundi 9 h (Paris) | `weekly_bonus` | « Tes 300 € de la semaine » |
| Samedi 11 h (Paris) | `weekly_bonus_last_chance` | « 300 € t'attendent encore » — uniquement pour ceux qui ne sont pas passés |

Qui reçoit : un compte avec au moins un appareil enregistré, qui n'a pas
coupé le rappel dans les réglages (`profiles.push_weekly_bonus`), dont le
portefeuille est ouvert depuis la semaine précédente au moins, et qui n'a pas
encore touché le versement de la semaine. Un envoi réussi s'inscrit dans
`push_campaigns` : rejouer le cron n'enverra pas deux fois le même rappel.

## Ce qu'il reste à faire une fois : la clé APNs

Tant que la clé n'est pas déposée, la fonction répond **503** avec le message
`APNS_KEY_P8 … sont requis`. C'est voulu : un cron qui échoue franchement se
remarque, un cron qui n'envoie rien en silence, non.

1. **developer.apple.com → Certificates, IDs & Profiles → Keys → +**
   Nom : `Krezus APNs`. Cocher **Apple Push Notifications service (APNs)**,
   puis *Continue* et *Register*.
2. **Télécharger le fichier `AuthKey_XXXXXXXXXX.p8`** — Apple ne le propose
   qu'une fois. Les dix caractères du nom sont le *Key ID*.
3. Relever le **Team ID** (Membership details) — le même que dans
   `Secrets.xcconfig`.
4. Déposer le tout côté Supabase, en une commande :

   ```bash
   tools/setup_push.sh ~/Downloads/AuthKey_XXXXXXXXXX.p8
   ```

   Le script vérifie que la clé est lisible, lit l'identifiant dans le nom du
   fichier et le Team ID dans `Secrets.xcconfig`, dépose les secrets, puis
   appelle la fonction pour confirmer qu'elle ne répond plus 503. La clé ne
   quitte pas ton disque autrement : elle ne s'affiche pas, n'entre pas dans
   le dépôt. Range ensuite le `.p8` ailleurs que dans Téléchargements — Apple
   ne le propose qu'une fois.

`APNS_ENV` vaut `production` pour une build TestFlight ou App Store, et
`sandbox` pour une build lancée depuis Xcode : ce sont deux réseaux de jetons
distincts, et un jeton de l'un est refusé par l'autre.

## Vérifier

```bash
# Un appareil enregistré ? (0 tant que personne n'a accepté les notifications)
npx supabase db query --linked --project-ref nxvqupjaqkdulhddnlvy \
  "select count(*) from device_tokens"

# Déclencher la campagne à la main, sans attendre lundi
curl -s -H "x-market-data-secret: $MARKET_DATA_SECRET" \
  "https://nxvqupjaqkdulhddnlvy.functions.supabase.co/push?campaign=weekly_bonus"
```

La réponse donne le nombre de cibles, d'envois et de jetons périmés. Un jeton
qu'Apple déclare inconnu (410, `BadDeviceToken`) est supprimé de la base :
l'app a été désinstallée.

Pour se remettre en situation de test après coup :

```sql
-- Oublier le rappel déjà envoyé cette semaine
delete from push_campaigns where campaign like 'weekly_bonus%';
```

## Points de vigilance

- **Le premier envoi doit être testé sur un vrai appareil**, jamais sur le
  simulateur : il ne reçoit pas d'APNs.
- **Le consentement est réglable dans l'app** (Réglages → Notifications →
  Versement hebdomadaire) et recopié dans `profiles.push_weekly_bonus`. Le
  serveur ne lit que cette colonne.
- **L'heure est en UTC dans le cron** : le rappel du lundi part à 9 h en
  hiver, 10 h en été. Sans conséquence pour un rappel hebdomadaire, mais
  c'est à savoir avant de s'étonner.
- **Ne pas multiplier les campagnes.** Deux notifications par semaine au
  maximum, toutes deux liées à une récompense réelle ; au-delà, c'est
  l'autorisation elle-même que l'utilisateur retire, et elle ne se redemande
  pas.
