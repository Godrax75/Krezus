#!/bin/bash
#
# Archive Krezus, exporte un .ipa signé pour App Store Connect, et — si des
# identifiants d'API sont fournis — l'envoie sur TestFlight.
#
#   tools/archive.sh                 # archive + export du .ipa
#   tools/archive.sh --upload        # + envoi vers App Store Connect
#   tools/archive.sh --validate      # + validation seule, sans envoi
#
# Envoi : il faut une clé d'API App Store Connect (Users and Access → Integrations
# → App Store Connect API). Poser le .p8 dans ~/.appstoreconnect/private_keys/
# puis exporter :
#
#   export ASC_KEY_ID=XXXXXXXXXX
#   export ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
#
# Une clé d'API évite de coller un mot de passe d'application dans un terminal
# et se révoque d'un clic — préférable à --username/--password.

set -euo pipefail

cd "$(dirname "$0")/.."

SCHEME="Krezus"
ARCHIVE_PATH="build/Krezus.xcarchive"
EXPORT_DIR="build/export"
SECRETS="Krezus/Config/Secrets.xcconfig"

# ---------------------------------------------------------------- Vérifications

if [[ ! -f "$SECRETS" ]]; then
  echo "✗ $SECRETS manquant. Copier Secrets.example.xcconfig et le renseigner." >&2
  exit 1
fi

TEAM_ID="$(sed -n 's/^KREZUS_TEAM_ID *= *//p' "$SECRETS" | tr -d ' \r')"
if [[ -z "$TEAM_ID" ]]; then
  echo "✗ KREZUS_TEAM_ID est vide dans $SECRETS." >&2
  echo "  Le récupérer sur developer.apple.com → Membership details → Team ID." >&2
  exit 1
fi

# Le numéro de build doit croître strictement d'un envoi à l'autre : App Store
# Connect rejette un CFBundleVersion déjà vu, même après suppression du build.
BUILD_NUMBER="${KREZUS_BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"
MARKETING_VERSION="$(sed -n 's/^ *MARKETING_VERSION: *"\(.*\)"/\1/p' project.yml)"

echo "▸ Krezus $MARKETING_VERSION (build $BUILD_NUMBER) · équipe $TEAM_ID"

# --------------------------------------------------------------------- Archive

echo "▸ Génération du projet"
xcodegen generate >/dev/null

echo "▸ Vérification du catalogue de traductions"
python3 tools/build_strings.py --check

rm -rf "$ARCHIVE_PATH" "$EXPORT_DIR"

echo "▸ Archivage (Release, generic/platform=iOS)"
xcodebuild archive \
  -project Krezus.xcodeproj \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE_PATH" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  | grep -E '^(\*\*|.*error:|.*warning: .*deprecat)' || true

if [[ ! -d "$ARCHIVE_PATH" ]]; then
  echo "✗ L'archive n'a pas été produite." >&2
  exit 1
fi

# ---------------------------------------------------------------------- Export

OPTIONS="build/ExportOptions.plist"
sed "s/TEAM_ID_PLACEHOLDER/$TEAM_ID/" tools/ExportOptions.plist > "$OPTIONS"

echo "▸ Export du .ipa"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$OPTIONS" \
  | grep -E '^(\*\*|.*error:)' || true

IPA="$(find "$EXPORT_DIR" -name '*.ipa' -maxdepth 1 | head -1)"
if [[ -z "$IPA" ]]; then
  echo "✗ Aucun .ipa exporté — voir la sortie ci-dessus." >&2
  exit 1
fi
echo "✓ $IPA ($(du -h "$IPA" | cut -f1))"

# ----------------------------------------------------------------------- Envoi

MODE="${1:-}"
if [[ "$MODE" != "--upload" && "$MODE" != "--validate" ]]; then
  echo
  echo "Pour envoyer sur TestFlight : tools/archive.sh --upload"
  exit 0
fi

if [[ -z "${ASC_KEY_ID:-}" || -z "${ASC_ISSUER_ID:-}" ]]; then
  echo "✗ ASC_KEY_ID et ASC_ISSUER_ID doivent être exportés (voir l'en-tête)." >&2
  exit 1
fi

ACTION="--upload-app"
[[ "$MODE" == "--validate" ]] && ACTION="--validate-app"

echo "▸ ${ACTION#--} vers App Store Connect"
xcrun altool "$ACTION" \
  --type ios \
  --file "$IPA" \
  --apiKey "$ASC_KEY_ID" \
  --apiIssuer "$ASC_ISSUER_ID"

echo "✓ Terminé. Le traitement du build prend ensuite 5 à 30 minutes côté Apple."
