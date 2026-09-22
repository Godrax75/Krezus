#!/usr/bin/env bash
# Dépose la clé APNs côté Supabase, sans qu'elle passe par ailleurs.
#
#   tools/setup_push.sh ~/Downloads/AuthKey_ABCD123456.p8
#
# La clé va de ton disque aux secrets du projet, directement. Elle ne
# s'affiche nulle part, ne part dans aucun journal, et n'entre pas dans le
# dépôt. Le Team ID est lu dans Secrets.xcconfig, l'identifiant de clé dans
# le nom du fichier, comme le nomme Apple.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_REF="nxvqupjaqkdulhddnlvy"
KEY_PATH="${1:-}"

if [ -z "$KEY_PATH" ]; then
  cat >&2 <<'USAGE'
Usage : tools/setup_push.sh <chemin du .p8>

La clé se crée sur developer.apple.com → Certificates, IDs & Profiles →
Keys → +, en cochant « Apple Push Notifications service (APNs) ».
Apple ne propose son téléchargement qu'une fois.
USAGE
  exit 1
fi

[ -f "$KEY_PATH" ] || { echo "✗ Fichier introuvable : $KEY_PATH" >&2; exit 1; }

# Une clé APNs est une clé privée P-256 au format PKCS#8.
grep -q "BEGIN PRIVATE KEY" "$KEY_PATH" \
  || { echo "✗ $KEY_PATH n'est pas une clé .p8 (en-tête PKCS#8 absent)" >&2; exit 1; }
if command -v openssl >/dev/null; then
  openssl pkey -in "$KEY_PATH" -noout 2>/dev/null \
    || { echo "✗ Clé illisible : le fichier est peut-être tronqué" >&2; exit 1; }
fi

KEY_ID="$(basename "$KEY_PATH" | sed -n 's/^AuthKey_\([A-Z0-9]\{10\}\)\.p8$/\1/p')"
if [ -z "$KEY_ID" ]; then
  read -r -p "Identifiant de la clé (10 caractères) : " KEY_ID
fi

TEAM_ID="$(sed -n 's/^KREZUS_TEAM_ID *= *//p' "$ROOT/Krezus/Config/Secrets.xcconfig" | tr -d ' \r')"
[ -n "$TEAM_ID" ] || { echo "✗ KREZUS_TEAM_ID absent de Krezus/Config/Secrets.xcconfig" >&2; exit 1; }

echo "▸ Clé $KEY_ID · équipe $TEAM_ID · app com.krezus.app"
npx supabase secrets set --project-ref "$PROJECT_REF" \
  APNS_KEY_ID="$KEY_ID" \
  APNS_TEAM_ID="$TEAM_ID" \
  APNS_TOPIC="com.krezus.app" \
  APNS_ENV="production" \
  APNS_KEY_P8="$(cat "$KEY_PATH")" >/dev/null

echo "✓ Secrets déposés"
echo "▸ Vérification de la fonction d'envoi"
SECRET="$(sed -n 's/^MARKET_DATA_SECRET=//p' "$ROOT/supabase/functions/.env")"
sleep 5
RESPONSE="$(curl -s -m 60 -H "x-market-data-secret: $SECRET" \
  "https://$PROJECT_REF.functions.supabase.co/push?campaign=weekly_bonus")"

case "$RESPONSE" in
  *APNS_KEY*)   echo "✗ La fonction ne voit pas encore la clé — réessaie dans une minute" ;;
  *targets*)    echo "✓ $RESPONSE" ;;
  *)            echo "? Réponse inattendue : $RESPONSE" ;;
esac

cat <<'NEXT'

Ensuite :
  - range le .p8 ailleurs que dans Téléchargements, il ne se retélécharge pas ;
  - accepte les notifications dans l'app sur un vrai iPhone (le simulateur
    n'en reçoit pas), puis relance la commande ci-dessus : « targets » doit
    passer à 1.
NEXT
