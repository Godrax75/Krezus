#!/usr/bin/env bash
# Relève les tickers du S&P 500 pour lesquels EODHD sert un logo.
# Le résultat alimente tools/build_sp500_seed.py (cache eodhd-logos.txt).
#
#   tools/check_sp500_logos.sh
#
# Une requête toutes les 0,3 s sur trois fils : au-delà, le CDN répond 429.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CACHE="$ROOT/build/sp500-cache"
SEED="$ROOT/supabase/seed/sp500.sql"

[ -f "$CACHE/wikipedia-list.json" ] || { echo "Cache absent : lancer d'abord build_sp500_seed.py" >&2; exit 1; }

python3 - "$CACHE" <<'PY' > "$CACHE/tickers.txt"
import json, re, sys
w = json.load(open(f"{sys.argv[1]}/wikipedia-list.json"))['parse']['wikitext']['*']
for block in w.split('|-')[1:]:
    m = re.search(r'\{\{\w+Symbol\|([A-Za-z.\-]+)\}\}', block)
    if m:
        print(m.group(1).replace('.', '-').lower())
PY

: > "$CACHE/eodhd-logos.txt"
xargs -P 3 -I{} sh -c 'sleep 0.3; code=$(curl -s -o /dev/null -m 20 -w "%{http_code}" "https://eodhd.com/img/logos/US/{}.png"); echo "{} $code"' \
  < "$CACHE/tickers.txt" \
  | awk '$2 == "200" { gsub(/-/, ".", $1); print toupper($1), $2 }' \
  | sort -u > "$CACHE/eodhd-logos.txt"

echo "✓ $(wc -l < "$CACHE/eodhd-logos.txt") logos disponibles chez EODHD"
echo "  Regénérer ensuite : python3 tools/build_sp500_seed.py --offline  → $SEED"
