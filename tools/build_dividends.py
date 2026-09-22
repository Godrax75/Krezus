#!/usr/bin/env python3
"""Calcule le rendement du dividende de chaque action.

    python3 tools/build_dividends.py             # tout le catalogue
    python3 tools/build_dividends.py --limit 20  # essai

La fiche d'une action affiche un rendement de dividende. Il venait du seed
écrit à la main ; les mille titres arrivés depuis n'en ont pas, et l'offre
Fundamentals d'EODHD — qui le fournirait tout calculé — n'est pas dans
l'abonnement.

Il se calcule pourtant à partir de données que l'abonnement couvre : la
somme des dividendes **effectivement versés sur les douze derniers mois**,
rapportée au cours actuel. C'est la définition du rendement courant, et
elle a l'avantage de ne rien anticiper : un dividende annoncé mais pas
encore versé n'y figure pas.

Les dividendes et le cours doivent être dans la même devise, sinon le
rapport n'a pas de sens : les rares cas contraires sont écartés.

Produit `supabase/seed/dividends.sql`.
"""

import argparse
import concurrent.futures
import datetime as dt
import json
import pathlib
import subprocess
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
SEED = ROOT / "supabase" / "seed" / "dividends.sql"
PROJECT_REF = "nxvqupjaqkdulhddnlvy"


def eodhd_token() -> str:
    for line in (ROOT / "supabase" / "functions" / ".env").read_text().splitlines():
        if line.startswith("EODHD_API_TOKEN="):
            return line.split("=", 1)[1].strip()
    raise SystemExit("EODHD_API_TOKEN introuvable")


def catalogue() -> list[dict]:
    """Actions cotées, avec leur cours natif et sa devise."""
    query = ("select s.symbol, s.eodhd_symbol, s.currency, q.price_native "
             "from securities s join quotes_cache q on q.symbol = s.symbol "
             "where s.asset_type = 'stock' and s.eodhd_symbol is not null "
             "and q.price_native > 0 order by s.symbol")
    out = subprocess.run(
        ["npx", "supabase", "db", "query", "--linked", "--project-ref", PROJECT_REF, query],
        capture_output=True, text=True, cwd=ROOT, check=True).stdout
    return json.loads(out[out.index("{"):out.rindex("}") + 1])["rows"]


def yield_of(row: dict, token: str, since: str) -> tuple[str, float] | None:
    url = (f"https://eodhd.com/api/div/{row['eodhd_symbol']}"
           f"?api_token={token}&fmt=json&from={since}")
    try:
        payments = json.load(urllib.request.urlopen(url, timeout=60))
    except Exception:                                # noqa: BLE001 — titre sans dividende connu
        return None
    if not isinstance(payments, list):
        return None

    # Le dividende est servi dans l'unité du cours, quelle que soit la devise
    # annoncée : Pearson verse « 17.4 GBP » pour 17,4 pence, sur un cours de
    # 1 198 pence. Convertir sur la foi du libellé donnait des rendements de
    # 200 %. On divise donc sans rien convertir.
    total = sum(float(payment["value"]) for payment in payments
                if payment.get("value") is not None)
    if total <= 0:
        return None
    computed = total / float(row["price_native"]) * 100
    # Au-delà de vingt pour cent, c'est presque toujours une unité qui ne
    # correspond pas, pas un dividende exceptionnel : on préfère ne rien
    # afficher qu'un chiffre faux.
    if computed > 20:
        print(f"  écarté : {row['symbol']} → {computed:.0f} %")
        return None
    return row["symbol"], round(computed, 2)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--limit", type=int, default=0)
    args = parser.parse_args()

    rows = catalogue()
    if args.limit:
        rows = rows[:args.limit]
    token = eodhd_token()
    since = (dt.date.today() - dt.timedelta(days=366)).isoformat()
    print(f"{len(rows)} actions à interroger")

    results: list[tuple[str, float]] = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
        futures = [pool.submit(yield_of, row, token, since) for row in rows]
        for done, future in enumerate(concurrent.futures.as_completed(futures), 1):
            found = future.result()
            if found:
                results.append(found)
            if done % 200 == 0:
                print(f"  {done}/{len(rows)}…")

    results.sort()
    lines = [
        "-- =====================================================================",
        "-- Rendement du dividende, sur les douze derniers mois.",
        "--",
        "-- Fichier GÉNÉRÉ par tools/build_dividends.py — ne pas éditer à la main.",
        "-- Somme des dividendes versés sur un an, rapportée au cours du jour.",
        "-- Un titre absent de la liste n'a rien versé sur la période : sa fiche",
        "-- affiche « — », ce qui est la vérité, et non un rendement de zéro.",
        "-- =====================================================================",
        "",
        "-- Les rendements d'hier ne valent plus : on repart de rien.",
        "update public.securities set dividend_yield = null where asset_type = 'stock';",
        "",
        "update public.securities s set dividend_yield = v.yield",
        "from (values",
        ",\n".join(f"  ('{symbol}', {value})" for symbol, value in results),
        ") as v(symbol, yield)",
        "where s.symbol = v.symbol;",
    ]
    SEED.write_text("\n".join(lines) + "\n")
    print(f"{len(results)} rendements calculés → {SEED.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
