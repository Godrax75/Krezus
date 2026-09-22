# Envoi des e-mails de compte

Trois messages partent de Krezus, tous via **Supabase Auth** : confirmation
d'inscription, réinitialisation de mot de passe, et changement d'adresse.

Sans serveur d'envoi à soi, Supabase utilise le sien, **bridé à deux ou trois
messages par heure pour tout le projet** et signé d'une adresse
`noreply@mail.app.supabase.io`. À quelques inscriptions simultanées, les
suivantes ne reçoivent plus rien — et personne ne voit d'erreur : ni le
serveur, ni l'app, ni l'utilisateur, qui attend un mail qui ne viendra pas.
C'est la raison de cette page.

Le service retenu est **Resend** (3 000 messages par mois gratuits, trois
enregistrements DNS, bonne réputation d'expédition). Le domaine d'envoi est
**krezus-card.com**, celui qui héberge déjà les CGV et la politique de
confidentialité vers lesquelles l'app renvoie.

## 1. Créer le compte Resend et vérifier le domaine

À faire depuis ton compte — je ne crée pas de compte et ne saisis aucune clé.

1. Ouvrir un compte sur resend.com, puis **Domains → Add Domain** :
   `krezus-card.com`, région **EU (Ireland)** pour que les données restent
   dans l'Union.
2. Resend affiche **trois enregistrements** à créer chez IONOS (Domaines →
   krezus-card.com → DNS). Ils portent tous sur le sous-domaine `send`, donc
   **ils ne touchent ni ta boîte IONOS ni le SPF existant** :

   | Type | Nom | Valeur |
   |---|---|---|
   | MX | `send` | `feedback-smtp.eu-west-1.amazonses.com` (priorité 10) |
   | TXT | `send` | `v=spf1 include:amazonses.com ~all` |
   | TXT | `resend._domainkey` | la clé DKIM affichée par Resend (longue) |

   Les valeurs exactes sont celles de ton écran Resend : recopie-les, ne les
   invente pas.
3. Attendre la pastille **Verified** (quelques minutes, parfois une heure).
4. **API Keys → Create API Key**, droit *Sending access*, domaine
   `krezus-card.com`. La clé (`re_…`) ne s'affiche qu'une fois.

Pendant que tu y es, ajoute un DMARC : aujourd'hui le domaine n'en a aucun,
ce qui laisse n'importe qui usurper l'adresse.

| Type | Nom | Valeur |
|---|---|---|
| TXT | `_dmarc` | `v=DMARC1; p=none; rua=mailto:bonjour@krezus-card.com` |

`p=none` observe sans rien bloquer. Après quelques semaines de rapports, on
peut passer à `p=quarantine`.

## 2. Brancher Supabase

Dashboard → **Project Settings → Authentication → SMTP Settings** → *Enable
Custom SMTP* :

| Champ | Valeur |
|---|---|
| Host | `smtp.resend.com` |
| Port | `587` |
| Username | `resend` |
| Password | la clé d'API `re_…` |
| Sender email | `bonjour@krezus-card.com` |
| Sender name | `Krezus` |

L'adresse d'expédition doit appartenir au domaine vérifié, sinon Resend
refuse le message. `bonjour@` plutôt qu'un `no-reply@` : les réponses
arrivent dans ta boîte IONOS, et un utilisateur qui répond à un mail de
service a en général une bonne raison.

Juste en dessous, **Rate limits → Emails per hour** : la valeur par défaut
(30) devient trop basse dès le premier jour de mise en avant. 200 laisse de
la marge sans ouvrir la porte à un abus.

## 3. Poser les gabarits

Dashboard → **Authentication → Emails → Templates**. Un onglet par message,
à remplir avec les fichiers de `supabase/email_templates/` :

| Onglet | Fichier | Objet à saisir |
|---|---|---|
| Confirm signup | `confirm_signup.html` | `Confirme ton adresse — Krezus` |
| Reset password | `reset_password.html` | `Nouveau mot de passe — Krezus` |
| Magic link | `magic_link.html` | `Ta connexion à Krezus` |
| Change email address | `email_change.html` | `Confirme ta nouvelle adresse — Krezus` |

Les gabarits sont bilingues : français d'abord, anglais ensuite. Supabase ne
sait pas quelle langue parle un destinataire avant son inscription, et deux
paragraphes coûtent moins cher qu'un message incompréhensible.

## 4. Vérifier

1. Dans l'app, créer un compte avec une adresse à toi : le message doit
   arriver en moins d'une minute, expédié par `bonjour@krezus-card.com`.
2. Ouvrir le lien depuis le téléphone : il doit ouvrir Krezus (schéma
   `com.krezus.app://login-callback`), pas le navigateur.
3. Demander une réinitialisation de mot de passe, même contrôle avec
   `com.krezus.app://reset-callback`.
4. Regarder l'en-tête du message reçu (Gmail : « Afficher l'original ») :
   `SPF: PASS`, `DKIM: PASS`, `DMARC: PASS`.
5. Resend → **Logs** : chaque envoi y figure, avec son statut de remise.

Si un message part mais n'arrive pas, la réponse est presque toujours dans
les logs Resend (rejet du destinataire) ou dans l'en-tête (SPF ou DKIM en
échec, donc un enregistrement DNS mal recopié).

## Ce qui reste à surveiller

- **Le quota gratuit** (3 000 par mois, 100 par jour) suffit à quelques
  centaines d'inscriptions ; au-delà, le premier palier payant est à 20 $.
- **Les adresses jetables** : Supabase ne les filtre pas. Si l'inscription
  devient un vecteur d'abus, il faudra y regarder.
- **La boîte `bonjour@krezus-card.com`** doit exister côté IONOS : c'est
  aussi l'adresse affichée dans le Centre d'aide de l'app.
