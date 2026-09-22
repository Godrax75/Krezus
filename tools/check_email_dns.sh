#!/usr/bin/env bash
# Vérifie que le domaine d'envoi est prêt, avant de cliquer sur « Verify »
# chez Resend — et dit lequel des enregistrements manque ou est mal recopié.
#
#   tools/check_email_dns.sh [domaine]        (défaut : krezus-card.com)
set -euo pipefail

DOMAIN="${1:-krezus-card.com}"
ok=0
ko=0

check() {                                   # check <libellé> <condition> <détail>
  if [ "$2" = "1" ]; then
    printf "  ✓ %s\n" "$1"; ok=$((ok + 1))
  else
    printf "  ✗ %s — %s\n" "$1" "$3"; ko=$((ko + 1))
  fi
}

echo "▸ $DOMAIN"

MX="$(dig +short MX "send.$DOMAIN" | tr 'A-Z' 'a-z')"
check "MX sur send (retours de remise)" \
  "$(echo "$MX" | grep -c 'amazonses.com' || true)" \
  "attendu feedback-smtp.<région>.amazonses.com, lu : ${MX:-rien}"

SPF="$(dig +short TXT "send.$DOMAIN" | tr -d '"')"
check "SPF sur send (droit d'expédier)" \
  "$(echo "$SPF" | grep -c 'include:amazonses.com' || true)" \
  "attendu v=spf1 include:amazonses.com ~all, lu : ${SPF:-rien}"

DKIM="$(dig +short TXT "resend._domainkey.$DOMAIN" | tr -d '"')"
check "DKIM (signature des messages)" \
  "$(echo "$DKIM" | grep -c 'p=' || true)" \
  "attendu la clé p=MIGfMA0… donnée par Resend, lu : ${DKIM:-rien}"

DMARC="$(dig +short TXT "_dmarc.$DOMAIN" | tr -d '"')"
check "DMARC (interdit l'usurpation)" \
  "$(echo "$DMARC" | grep -c 'v=DMARC1' || true)" \
  "attendu v=DMARC1; p=none; rua=mailto:…, lu : ${DMARC:-rien}"

# Le SPF du domaine racine ne doit pas avoir été écrasé : c'est lui qui
# autorise la messagerie existante.
ROOT_SPF="$(dig +short TXT "$DOMAIN" | tr -d '"' | grep '^v=spf1' || true)"
check "SPF du domaine racine intact (messagerie IONOS)" \
  "$(echo "$ROOT_SPF" | grep -c 'v=spf1' || true)" \
  "le SPF de $DOMAIN a disparu : la messagerie existante risque d'être rejetée"

echo
if [ "$ko" -eq 0 ]; then
  echo "✓ Tout est en place. Chez Resend : Domains → $DOMAIN → Verify."
else
  echo "$ko enregistrement(s) à corriger, $ok en place."
  echo "Rappel : chez IONOS, saisir « send » et non « send.$DOMAIN » —"
  echo "le domaine est ajouté automatiquement."
fi
