#!/usr/bin/env python3
"""Alimente `quotes_cache` depuis EODHD, en tenant compte du quota.

Sert de remplacement à la Edge Function `quotes` tant que le plan EODHD est le
plan **gratuit** : celui-ci autorise 20 appels par jour, là où la Edge Function
est écrite pour un rafraîchissement toutes les 60 s en séance (~480/jour).

Le point à connaître : **un appel groupé coûte un appel par symbole.** Grouper
50 titres dans une seule URL économise des allers-retours HTTP, pas du quota.
Rafraîchir les 51 titres mappés consomme donc 51 appels, soit deux jours et
demi de quota gratuit. D'où le jeu par défaut, volontairement court.

    export KREZUS_DB_URL='postgresql://postgres:MOTDEPASSE@db.<ref>.supabase.co:5432/postgres'
    export EODHD_API_TOKEN='...'

    python3 tools/refresh_quotes.py              # jeu par défaut (~15 appels)
    python3 tools/refresh_quotes.py --all        # les 51 titres mappés
    python3 tools/refresh_quotes.py --symbols NVDA,AI,MC
    python3 tools/refresh_quotes.py --dry-run    # n'appelle rien, montre le coût

Le moteur d'ordres rejette une cotation de plus de 15 minutes (KR004) : après
un passage, l'app peut donc passer des ordres pendant un quart d'heure.
"""

import argparse
import json
import os
import subprocess
import sys
import urllib.parse
import urllib.request
from datetime import datetime, timezone

BASE = "https://eodhd.com/api"
FX_PAIR = "EURUSD.FOREX"
ACCOUNT_CURRENCY = "EUR"

# Titres rafraîchis par défaut : ceux que les premiers écrans montrent. Tenir la
# liste courte est ce qui rend l'outil utilisable sur le plan gratuit.
DEFAULT_SYMBOLS = [
    "NVDA", "AAPL", "MSFT", "AI", "MC", "OREAL",
    "TTE", "SAF", "SAN", "SU", "BNP", "AIRB",
]


def psql(db_url: str, sql: str) -> str:
    """Exécute du SQL via le client `psql`.

    Plutôt que `psycopg2` : le dépôt n'utilise que la bibliothèque standard, et
    installer un paquet dans un Python géré par le système (PEP 668) demanderait
    de forcer la main à l'environnement de la machine.
    """
    result = subprocess.run(
        ["psql", db_url, "-v", "ON_ERROR_STOP=1", "-tA", "-F", "\t", "-c", sql],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip())
    return result.stdout


def sql_literal(value) -> str:
    """Littéral SQL. Les valeurs viennent d'une API tierce : tout est échappé."""
    if value is None:
        return "null"
    if isinstance(value, (int, float)):
        return repr(value)
    return "'" + str(value).replace("'", "''") + "'"


def fetch(url: str):
    with urllib.request.urlopen(url, timeout=30) as response:
        return json.loads(response.read().decode())


def quota(token: str) -> tuple[int, int, int]:
    """(consommés, plafond quotidien, réserve) — cet appel ne coûte rien."""
    d = fetch(f"{BASE}/user?api_token={token}&fmt=json")
    return d.get("apiRequests", 0), d.get("dailyRateLimit", 0), d.get("extraLimit", 0)


def real_time(symbols: list[str], token: str) -> list[dict]:
    """Un seul aller-retour HTTP ; le quota, lui, compte un appel par symbole."""
    head, rest = symbols[0], symbols[1:]
    url = f"{BASE}/real-time/{urllib.parse.quote(head)}?api_token={token}&fmt=json"
    if rest:
        url += "&s=" + urllib.parse.quote(",".join(rest))
    payload = fetch(url)
    return payload if isinstance(payload, list) else [payload]


def main() -> int:
    parser = argparse.ArgumentParser(add_help=True)
    parser.add_argument("--all", action="store_true", help="tous les titres mappés")
    parser.add_argument("--symbols", help="liste de symboles Krezus, séparés par des virgules")
    parser.add_argument("--dry-run", action="store_true", help="montre le coût sans appeler")
    args = parser.parse_args()

    token = os.environ.get("EODHD_API_TOKEN")
    db_url = os.environ.get("KREZUS_DB_URL")
    if not token or not db_url:
        print("EODHD_API_TOKEN et KREZUS_DB_URL doivent être définis.", file=sys.stderr)
        return 2

    if args.all:
        where = ""
    else:
        wanted = [s.strip() for s in (args.symbols.split(",") if args.symbols
                                      else DEFAULT_SYMBOLS)]
        where = f" and symbol in ({', '.join(sql_literal(s) for s in wanted)})"

    rows = [line.split("\t") for line in psql(
        db_url,
        "select symbol, eodhd_symbol, currency from securities "
        f"where eodhd_symbol is not null{where} order by symbol",
    ).splitlines() if line.strip()]

    if not rows:
        print("Aucun titre à rafraîchir.")
        return 1

    by_eodhd = {eodhd: (symbol, currency) for symbol, eodhd, currency in rows}
    needs_fx = any(currency != ACCOUNT_CURRENCY for _, _, currency in rows)
    cost = len(rows) + (1 if needs_fx else 0)

    used, daily, extra = quota(token)
    remaining = max(0, daily - used) + extra
    print(f"Quota : {used}/{daily} consommés aujourd'hui · réserve {extra} "
          f"→ {remaining} disponibles")
    print(f"Coût de ce passage : {cost} appels ({len(rows)} titres"
          f"{' + 1 taux de change' if needs_fx else ''})")

    if args.dry_run:
        return 0
    if cost > remaining:
        print(f"Refus : {cost} appels demandés pour {remaining} disponibles.", file=sys.stderr)
        return 1

    fx_rate = 1.0
    if needs_fx:
        fx = real_time([FX_PAIR], token)
        fx_rate = float(fx[0]["close"])
        print(f"EUR/USD = {fx_rate}")

    quotes = real_time([eodhd for _, eodhd, _ in rows], token)

    values, skipped = [], []
    now = datetime.now(timezone.utc).isoformat()
    for quote in quotes:
        code = quote.get("code")
        if code not in by_eodhd:
            continue
        symbol, currency = by_eodhd[code]
        native = quote.get("close")
        if not isinstance(native, (int, float)) or native <= 0:
            # EODHD rend « NA » hors séance sur certains titres.
            skipped.append(symbol)
            continue

        rate = fx_rate if currency != ACCOUNT_CURRENCY else 1.0
        opened = quote.get("open")
        quoted_at = (datetime.fromtimestamp(quote["timestamp"], timezone.utc).isoformat()
                     if isinstance(quote.get("timestamp"), (int, float)) else now)
        values.append("(" + ", ".join(sql_literal(v) for v in (
            symbol,
            round(float(native) / rate, 4),
            round(float(opened) / rate, 4) if isinstance(opened, (int, float)) else None,
            quote.get("change_p"),
            now,
            float(native),
            currency,
            rate,
            quote.get("previousClose"),
            quoted_at,
        )) + ")")

    if not values:
        print("Aucun cours exploitable — rien n'a été écrit.")
        return 1

    psql(db_url, f"""
        insert into quotes_cache (symbol, price, open, change_pct, fetched_at,
                                  price_native, currency, fx_rate,
                                  previous_close, quoted_at)
        values {", ".join(values)}
        on conflict (symbol) do update set
          price = excluded.price, open = excluded.open,
          change_pct = excluded.change_pct, fetched_at = excluded.fetched_at,
          price_native = excluded.price_native, currency = excluded.currency,
          fx_rate = excluded.fx_rate, previous_close = excluded.previous_close,
          quoted_at = excluded.quoted_at
    """)
    written = len(values)

    print(f"{written} cotations écrites — valables 15 minutes pour le moteur d'ordres.")
    if skipped:
        print(f"Sans cours exploitable : {', '.join(skipped)}")
    used_after, _, extra_after = quota(token)
    print(f"Quota après : {used_after}/{daily} · réserve {extra_after}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
