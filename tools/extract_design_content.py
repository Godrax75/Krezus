#!/usr/bin/env python3
"""
Extrait le contenu éditorial du prototype Claude Design vers des seeds Supabase.

Sources (récupérées via DesignSync.get_file) :
  - script.js          bloc STOCKS du fichier canonique « Krezus App.dc.html »
  - script-lovable.js  bloc LESSONS de la variante « -lovable- », qui va plus loin
                       dans le script avant le plafond de 256 KiB de l'API

Sorties :
  - supabase/seed/securities.sql
  - supabase/seed/lessons.sql

Le mapping id-prototype -> symbole EODHD est explicite : 8 des 38 titres ont un
ticker Euronext différent de l'identifiant utilisé dans le prototype.
"""

import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

# id prototype -> (symbole EODHD, place, devise)
# Vérifié ticker par ticker : ne jamais dériver le suffixe du champ `cc` du design.
EODHD = {
    "NVDA":  ("NVDA.US",  "NASDAQ", "USD"),
    "AAPL":  ("AAPL.US",  "NASDAQ", "USD"),
    "MSFT":  ("MSFT.US",  "NASDAQ", "USD"),
    "GOOG":  ("GOOG.US",  "NASDAQ", "USD"),
    "AMZN":  ("AMZN.US",  "NASDAQ", "USD"),
    "TSLA":  ("TSLA.US",  "NASDAQ", "USD"),
    "AI":    ("AI.PA",    "XPAR",   "EUR"),   # Air Liquide
    "MC":    ("MC.PA",    "XPAR",   "EUR"),   # LVMH
    "AC":    ("AC.PA",    "XPAR",   "EUR"),   # Accor
    "AIRB":  ("AIR.PA",   "XPAR",   "EUR"),   # Airbus — cote à Paris, pas à Amsterdam
    "MT":    ("MT.AS",    "XAMS",   "EUR"),   # ArcelorMittal — Amsterdam
    "CS":    ("CS.PA",    "XPAR",   "EUR"),   # AXA
    "BNP":   ("BNP.PA",   "XPAR",   "EUR"),
    "BOUY":  ("EN.PA",    "XPAR",   "EUR"),   # Bouygues -> EN
    "BVI":   ("BVI.PA",   "XPAR",   "EUR"),
    "CAPG":  ("CAP.PA",   "XPAR",   "EUR"),   # Capgemini -> CAP
    "CARR":  ("CA.PA",    "XPAR",   "EUR"),   # Carrefour -> CA
    "BN":    ("BN.PA",    "XPAR",   "EUR"),   # Danone
    "FGR":   ("FGR.PA",   "XPAR",   "EUR"),   # Eiffage
    "ENGI":  ("ENGI.PA",  "XPAR",   "EUR"),
    "EFX":   ("EL.PA",    "XPAR",   "EUR"),   # EssilorLuxottica -> EL
    "ERF":   ("ERF.PA",   "XPAR",   "EUR"),   # Eurofins
    "ENX":   ("ENX.PA",   "XPAR",   "EUR"),   # Euronext
    "RMS":   ("RMS.PA",   "XPAR",   "EUR"),   # Hermès
    "KER":   ("KER.PA",   "XPAR",   "EUR"),   # Kering
    "OREAL": ("OR.PA",    "XPAR",   "EUR"),   # L'Oréal -> OR
    "LR":    ("LR.PA",    "XPAR",   "EUR"),   # Legrand
    "ML":    ("ML.PA",    "XPAR",   "EUR"),   # Michelin
    "ORAN":  ("ORA.PA",   "XPAR",   "EUR"),   # Orange -> ORA
    "RI":    ("RI.PA",    "XPAR",   "EUR"),   # Pernod Ricard
    "PUB":   ("PUB.PA",   "XPAR",   "EUR"),   # Publicis
    "RNO":   ("RNO.PA",   "XPAR",   "EUR"),   # Renault
    "SAF":   ("SAF.PA",   "XPAR",   "EUR"),   # Safran
    "SGO":   ("SGO.PA",   "XPAR",   "EUR"),   # Saint-Gobain
    "SAN":   ("SAN.PA",   "XPAR",   "EUR"),   # Sanofi
    "SU":    ("SU.PA",    "XPAR",   "EUR"),   # Schneider Electric
    "GLE":   ("GLE.PA",   "XPAR",   "EUR"),   # Société Générale
    "STLA":  ("STLAP.PA", "XPAR",   "EUR"),   # Stellantis -> STLAP depuis 2024
    "STM":   ("STMPA.PA", "XPAR",   "EUR"),   # STMicroelectronics -> STMPA à Paris
    "HO":    ("HO.PA",    "XPAR",   "EUR"),   # Thales
    "TTE":   ("TTE.PA",   "XPAR",   "EUR"),   # TotalEnergies
    "URW":   ("URW.PA",   "XPAR",   "EUR"),   # Unibail-Rodamco-Westfield
    "VIE":   ("VIE.PA",   "XPAR",   "EUR"),   # Veolia
    "DG":    ("DG.PA",    "XPAR",   "EUR"),   # Vinci
    "DSY":   ("DSY.PA",   "XPAR",   "EUR"),   # Dassault Systèmes
    # Financières US
    "BRKB":  ("BRK-B.US", "NYSE",   "USD"),   # Berkshire Hathaway B
    "JPM":   ("JPM.US",   "NYSE",   "USD"),
    "V":     ("V.US",     "NYSE",   "USD"),
    "MA":    ("MA.US",    "NYSE",   "USD"),
    "BAC":   ("BAC.US",   "NYSE",   "USD"),
    "WFC":   ("WFC.US",   "NYSE",   "USD"),
    "GS":    ("GS.US",    "NYSE",   "USD"),
    # ETF : les identifiants du prototype (ETF500, ETFCAC…) sont fictifs. Le vrai
    # symbole EODHD de chaque fonds doit être vérifié une par une contre Euronext
    # (ISIN + place de cotation) avant activation — ne pas deviner. Laissé NULL ici.
}


def sql_str(value):
    """Littéral SQL : NULL, ou chaîne avec quotes doublées."""
    if value is None or value == "":
        return "NULL"
    return "'" + str(value).replace("'", "''") + "'"


def sql_num(value):
    """Nombre écrit à la française dans le prototype ('2,9 %', '3 900 Md$')."""
    if not value or value == "—":
        return "NULL"
    cleaned = re.sub(r"[^\d,.\-]", "", str(value)).replace(",", ".")
    try:
        return repr(float(cleaned))
    except ValueError:
        return "NULL"


def field(entry, key):
    """Lit `key: '...'` ou `key: "..."` dans un littéral d'objet JS."""
    match = re.search(
        rf"\b{key}:\s*(?P<q>['\"])(?P<val>(?:\\.|(?!(?P=q)).)*)(?P=q)", entry
    )
    if not match:
        return None
    return match.group("val").replace("\\'", "'").replace('\\"', '"')


def parse_stocks(source):
    """Découpe le littéral STOCKS en entrées, en ignorant l'éventuelle dernière
    entrée tronquée par le plafond de l'API."""
    start = source.index("const STOCKS")
    body = source[start:]
    entries = {}
    for match in re.finditer(r"^  ([A-Z0-9]+):\s*\{", body, re.M):
        key = match.group(1)
        depth, index = 0, match.end() - 1
        while index < len(body):
            char = body[index]
            if char == "{":
                depth += 1
            elif char == "}":
                depth -= 1
                if depth == 0:
                    entries[key] = body[match.end() - 1 : index + 1]
                    break
            index += 1
        else:
            print(f"  ! entrée tronquée, ignorée : {key}", file=sys.stderr)
    return entries


def parse_lessons(source):
    """Découpe le littéral LESSONS en objets complets."""
    start = source.index("const LESSONS")
    body = source[start:]
    lessons, index = [], body.index("[")
    while True:
        opening = body.find("{", index)
        if opening == -1:
            break
        depth, cursor = 0, opening
        while cursor < len(body):
            char = body[cursor]
            if char == "{":
                depth += 1
            elif char == "}":
                depth -= 1
                if depth == 0:
                    lessons.append(body[opening : cursor + 1])
                    break
            cursor += 1
        else:
            print("  ! dernière leçon tronquée, ignorée", file=sys.stderr)
            break
        index = cursor + 1
        # Ne descend pas dans les objets imbriqués (quiz) : on repart après l'objet.
    return lessons


def js_array(entry, key):
    """Lit `key: ["a","b"]` et renvoie une liste Python."""
    match = re.search(rf"\b{key}:\s*(\[)", entry)
    if not match:
        return []
    depth, cursor = 0, match.start(1)
    while cursor < len(entry):
        if entry[cursor] == "[":
            depth += 1
        elif entry[cursor] == "]":
            depth -= 1
            if depth == 0:
                raw = entry[match.start(1) : cursor + 1]
                try:
                    return json.loads(raw)
                except json.JSONDecodeError:
                    return re.findall(r'"((?:\\.|[^"])*)"', raw)
        cursor += 1
    return []


def build_securities(entries):
    lines = [
        "-- Généré par tools/extract_design_content.py — ne pas éditer à la main.",
        "-- Source : bloc STOCKS de la variante « Krezus App -base44-.dc.html »",
        "-- (univers complet : 82 titres, contre 38 dans le fichier canonique tronqué).",
        "-- Les valeurs fondamentales sont un instantané éditorial : le plan EODHD",
        "-- à 29,99 €/mois ne fournit pas les fondamentaux. Rafraîchir chaque trimestre.",
        "-- ETF : eodhd_symbol NULL — tickers réels à vérifier contre Euronext avant activation.",
        "",
        "insert into public.securities (symbol, eodhd_symbol, mic, currency, asset_type,",
        "  name, country_code, country, sector, founded, logo_asset, initials, dividend_yield,",
        "  market_cap_label, pe_ratio, peg_ratio, ceo, description_fr, hercule_note_fr)",
        "values",
    ]
    rows = []
    etfs_without_symbol = []
    for key, entry in entries.items():
        is_etf = key.startswith("ETF") or (field(entry, "sector") or "").startswith("ETF")
        asset_type = "etf" if is_etf else "stock"
        if key in EODHD:
            eodhd_symbol, mic, currency = EODHD[key]
            eodhd_sql = sql_str(eodhd_symbol)
            mic_sql, currency_sql = sql_str(mic), sql_str(currency)
        elif is_etf:
            eodhd_sql, mic_sql, currency_sql = "NULL", "NULL", sql_str("EUR")
            etfs_without_symbol.append(key)
        else:
            print(f"  ! pas de mapping EODHD pour {key}, ignoré", file=sys.stderr)
            continue
        logo = field(entry, "logo")
        if logo is None:
            match = re.search(r"logo:\s*R\('([^']+)'", entry)
            logo = match.group(1) if match else None
        rows.append(
            "  ({}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {})".format(
                sql_str(key),
                eodhd_sql,
                mic_sql,
                currency_sql,
                sql_str(asset_type),
                sql_str(field(entry, "name")),
                sql_str(field(entry, "cc")),
                sql_str(field(entry, "country")),
                sql_str(field(entry, "sector")),
                sql_str(field(entry, "founded")),
                sql_str(logo),
                sql_str(field(entry, "initials")),
                sql_num(field(entry, "div")),
                sql_str(field(entry, "mcap")),
                sql_num(field(entry, "pe")),
                sql_num(field(entry, "pg")),
                sql_str(field(entry, "ceo")),
                sql_str(field(entry, "what")),
                sql_str(field(entry, "herc")),
            )
        )
    if etfs_without_symbol:
        print(f"  ! {len(etfs_without_symbol)} ETF sans symbole EODHD (à mapper "
              f"manuellement) : {', '.join(etfs_without_symbol)}", file=sys.stderr)
    lines.append(",\n".join(rows))
    lines.append("on conflict (symbol) do update set")
    lines.append("  eodhd_symbol = excluded.eodhd_symbol,")
    lines.append("  pe_ratio = excluded.pe_ratio,")
    lines.append("  peg_ratio = excluded.peg_ratio,")
    lines.append("  dividend_yield = excluded.dividend_yield,")
    lines.append("  market_cap_label = excluded.market_cap_label,")
    lines.append("  updated_at = now();")
    return "\n".join(lines) + "\n"


def build_lessons(entries):
    lines = [
        "-- Généré par tools/extract_design_content.py — ne pas éditer à la main.",
        "-- Source : bloc LESSONS de la variante « Krezus App -lovable-.dc.html ».",
        "-- Les 4 premières leçons sont gratuites ; les suivantes sont derrière le paywall.",
        "",
        "insert into public.lessons (position, title_fr, duration_label, paragraphs_fr,",
        "  examples_fr, quiz_fr, is_free)",
        "values",
    ]
    rows = []
    for index, entry in enumerate(entries, start=1):
        quiz = "NULL"
        quiz_match = re.search(r"\bqz:\s*(\{)", entry)
        if quiz_match:
            depth, cursor = 0, quiz_match.start(1)
            while cursor < len(entry):
                if entry[cursor] == "{":
                    depth += 1
                elif entry[cursor] == "}":
                    depth -= 1
                    if depth == 0:
                        raw = entry[quiz_match.start(1) : cursor + 1]
                        try:
                            quiz = sql_str(json.dumps(json.loads(raw),
                                           ensure_ascii=False)) + "::jsonb"
                        except json.JSONDecodeError:
                            quiz = "NULL"
                        break
                cursor += 1
        rows.append(
            "  ({}, {}, {}, {}::jsonb, {}::jsonb, {}, {})".format(
                index,
                sql_str(field(entry, "t")),
                sql_str(field(entry, "time")),
                sql_str(json.dumps(js_array(entry, "pars"), ensure_ascii=False)),
                sql_str(json.dumps(js_array(entry, "examples"), ensure_ascii=False)),
                quiz,
                "true" if index <= 4 else "false",
            )
        )
    lines.append(",\n".join(rows))
    lines.append("on conflict (position) do update set")
    lines.append("  title_fr = excluded.title_fr,")
    lines.append("  paragraphs_fr = excluded.paragraphs_fr,")
    lines.append("  examples_fr = excluded.examples_fr,")
    lines.append("  quiz_fr = excluded.quiz_fr;")
    return "\n".join(lines) + "\n"


def main():
    if len(sys.argv) != 3:
        sys.exit("usage: extract_design_content.py <script.js> <script-lovable.js>")

    stocks_source = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
    lessons_source = pathlib.Path(sys.argv[2]).read_text(encoding="utf-8")

    stocks = parse_stocks(stocks_source)
    lessons = parse_lessons(lessons_source)
    print(f"  {len(stocks)} titres, {len(lessons)} leçons")

    seed_dir = ROOT / "supabase" / "seed"
    seed_dir.mkdir(parents=True, exist_ok=True)
    (seed_dir / "securities.sql").write_text(build_securities(stocks), encoding="utf-8")
    (seed_dir / "lessons.sql").write_text(build_lessons(lessons), encoding="utf-8")

    missing = sorted(set(EODHD) - set(stocks))
    if missing:
        print(f"  ! titres attendus mais absents de la source : {', '.join(missing)}",
              file=sys.stderr)


if __name__ == "__main__":
    main()
