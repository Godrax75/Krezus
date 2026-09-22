# Gabarits d'e-mails d'authentification

Ces fichiers sont la source de vérité des e-mails envoyés par Supabase Auth.
Ils se collent dans **Authentication → Emails → Templates**, un onglet par
message. Supabase ne gère pas les langues : chaque message est donc bilingue,
français d'abord, anglais après un filet — c'est la solution la plus simple
tant qu'on ne connaît pas la langue du destinataire avant son inscription.

Règles suivies :
- **styles en ligne**, tableaux plutôt que flexbox : c'est ce que comprennent
  Outlook et les webmails ;
- **aucune image** : les clients de messagerie les bloquent par défaut, et un
  mail dont le sens dépend d'une image bloquée ne veut plus rien dire ;
- **le lien apparaît aussi en toutes lettres**, pour les clients qui
  n'affichent pas le HTML ;
- **un seul bouton**, une seule action : un mail transactionnel n'est pas une
  newsletter ;
- pas de pixel de suivi, pas de lien de désabonnement — ce sont des messages
  de service, pas de la prospection.

Variables Supabase utilisées : `{{ .ConfirmationURL }}` (lien signé, qui
redirige ensuite vers l'app), `{{ .Token }}` (code à six chiffres, utile si le
lien ne s'ouvre pas), `{{ .Email }}`.
