#!/usr/bin/env python3
"""Génère `supabase/seed/sp500.sql` : les 500 sociétés du S&P 500.

    python3 tools/build_sp500_seed.py            # regénère le seed
    python3 tools/build_sp500_seed.py --offline  # réutilise le cache réseau

Trois sources, toutes publiques :

  - **Wikipédia** (« List of S&P 500 companies ») donne la composition de
    l'indice, le nom de chaque société et son secteur GICS. C'est la liste
    de référence ; EODHD ne l'expose que dans son offre Fundamentals, que
    l'abonnement Krezus ne comprend pas.
  - **EODHD** (`exchange-symbol-list/US`) valide chaque ticker et donne sa
    place de cotation et sa devise. Un ticker absent de cette liste ne
    serait pas cotable dans l'app : il est écarté.
  - **Wikidata / Wikimedia Commons** fournit les logos (propriété P154).
    Seules les images du domaine public, sous CC0 ou déposées comme simples
    marques sont retenues : les licences à attribution obligeraient à citer
    l'auteur sous chaque ligne de liste. À défaut, le logo EODHD s'il
    existe, sinon les initiales.

Le fichier produit est idempotent : les titres déjà présents (Apple,
Microsoft…) gardent leurs fiches rédigées à la main, seul leur logo est
complété. Trois tickers américains entrent en collision avec des valeurs
de Paris déjà au catalogue (Carrefour, Vinci, Eiffage) : leurs homonymes
américains prennent le suffixe « .US ».
"""

import argparse
import json
import pathlib
import re
import sys
import time
import urllib.parse
import urllib.request

CURRENT_YEAR = time.gmtime().tm_year
ROOT = pathlib.Path(__file__).resolve().parent.parent
CACHE = ROOT / "build" / "sp500-cache"
SEED = ROOT / "supabase" / "seed" / "sp500.sql"
UA = "KrezusApp/0.1 (contact: louisgodron45@gmail.com)"

# Licences acceptées : aucune ne demande de citer un auteur.
FREE_LICENSES = ("public domain", "pd-", "cc0", "trademark")

# Secteur GICS -> (libellé français, libellé anglais, famille `sector_group`).
SECTORS = {
    "Information Technology": ("Technologies de l'information", "Information technology", "technology"),
    "Health Care":            ("Santé", "Health care", "health"),
    "Financials":             ("Finance", "Financials", "finance"),
    "Consumer Discretionary": ("Consommation discrétionnaire", "Consumer discretionary", "consumer"),
    "Consumer Staples":       ("Consommation courante", "Consumer staples", "consumer"),
    "Communication Services": ("Communication-médias", "Communication services", "telecom"),
    "Industrials":            ("Industrie", "Industrials", "industry"),
    "Energy":                 ("Énergie-pétrole", "Energy and oil", "energy"),
    "Materials":              ("Matériaux", "Materials", "materials"),
    "Real Estate":            ("Immobilier", "Real estate", "realestate"),
    "Utilities":              ("Services aux collectivités", "Utilities", "utilities"),
}

# La sous-industrie affine la famille quand le secteur GICS la noie : une
# marque automobile n'est pas « consommation discrétionnaire » dans la
# répartition d'un portefeuille, elle est automobile.
INDUSTRY_GROUPS = {
    "auto": ("automobile", "automotive"),
    "technology": ("semiconductor", "software", "internet"),
    "realestate": ("reit",),
}

# Tickers déjà au catalogue pour la même société : on ne touche pas à leur
# fiche, seulement au logo.
ALREADY_LISTED = {
    "AAPL": "AAPL", "MSFT": "MSFT", "NVDA": "NVDA", "GOOGL": None, "GOOG": "GOOG",
    "AMZN": "AMZN", "TSLA": "TSLA", "JPM": "JPM", "BAC": "BAC", "WFC": "WFC",
    "V": "V", "MA": "MA", "BRK.B": "BRKB",
}

# Tickers américains homonymes d'une valeur de Paris déjà listée.
CLASHES = {"CARR": "CARR.US", "DG": "DG.US", "EFX": "EFX.US"}


def fetch(url: str, cache_name: str, offline: bool) -> bytes:
    CACHE.mkdir(parents=True, exist_ok=True)
    path = CACHE / cache_name
    if path.exists():
        return path.read_bytes()
    if offline:
        raise SystemExit(f"Cache absent en mode hors ligne : {cache_name}")
    request = urllib.request.Request(url, headers={"User-Agent": UA})
    data = urllib.request.urlopen(request, timeout=60).read()
    path.write_bytes(data)
    time.sleep(0.2)          # courtoisie envers des API publiques gratuites
    return data


def api(url: str, cache_name: str, offline: bool) -> dict:
    return json.loads(fetch(url, cache_name, offline))


# --------------------------------------------------------------- Composition

def constituents(offline: bool) -> list[dict]:
    """Ticker, nom, article Wikipédia et secteur GICS des 500 sociétés."""
    page = api(
        "https://en.wikipedia.org/w/api.php?action=parse&page=List_of_S%26P_500_companies"
        "&prop=wikitext&section=1&format=json", "wikipedia-list.json", offline)
    wikitext = page["parse"]["wikitext"]["*"]

    rows = []
    for block in wikitext.split("|-")[1:]:
        cells = [c.strip() for c in block.split("||")][1:]
        if len(cells) < 4:
            continue
        ticker = re.search(r"\{\{\w+Symbol\|([A-Za-z.\-]+)\}\}", cells[0])
        link = re.search(r"\[\[([^\]|]+)(?:\|([^\]]+))?\]\]", cells[1])
        if not ticker or not link:
            continue
        rows.append({
            "ticker": ticker.group(1),
            "article": link.group(1).strip(),
            "name": (link.group(2) or link.group(1)).strip(),
            "sector": cells[2].strip(),
            "industry": cells[3].strip(),
        })
    if len(rows) < 450:
        raise SystemExit(f"Liste Wikipédia inattendue : {len(rows)} lignes")
    return rows


def eodhd_index(offline: bool) -> dict[str, dict]:
    token = None
    env = ROOT / "supabase" / "functions" / ".env"
    if env.exists():
        for line in env.read_text().splitlines():
            if line.startswith("EODHD_API_TOKEN="):
                token = line.split("=", 1)[1].strip()
    if token is None and not (CACHE / "eodhd-us.json").exists():
        raise SystemExit("EODHD_API_TOKEN introuvable dans supabase/functions/.env")
    rows = api(f"https://eodhd.com/api/exchange-symbol-list/US?api_token={token}&fmt=json",
               "eodhd-us.json", offline)
    return {row["Code"]: row for row in rows}


# --------------------------------------------------------------------- Logos

def wikidata_logos(rows: list[dict], offline: bool) -> dict[str, str]:
    """Article Wikipédia -> URL de logo réutilisable sans attribution."""
    titles = [row["article"] for row in rows]
    qids: dict[str, str] = {}
    redirects: dict[str, str] = {}
    for start in range(0, len(titles), 50):
        batch = titles[start:start + 50]
        data = api("https://en.wikipedia.org/w/api.php?action=query&prop=pageprops&titles="
                   + urllib.parse.quote("|".join(batch)) + "&format=json&redirects=1",
                   f"pageprops-{start}.json", offline)
        for item in data["query"].get("redirects", []):
            redirects[item["from"]] = item["to"]
        for page in data["query"]["pages"].values():
            qid = page.get("pageprops", {}).get("wikibase_item")
            if qid:
                qids[page["title"]] = qid

    by_article = {}
    for row in rows:
        title = redirects.get(row["article"], row["article"])
        if title in qids:
            by_article[row["article"]] = qids[title]

    # Fichier de logo (P154) de chaque entité.
    files: dict[str, str] = {}
    unique = sorted(set(by_article.values()))
    for start in range(0, len(unique), 50):
        batch = unique[start:start + 50]
        data = api("https://www.wikidata.org/w/api.php?action=wbgetentities&ids="
                   + "|".join(batch) + "&props=claims&format=json",
                   f"wikidata-{start}.json", offline)
        for qid, entity in data.get("entities", {}).items():
            for claim in entity.get("claims", {}).get("P154", []):
                value = claim["mainsnak"].get("datavalue", {}).get("value")
                if value:
                    files[qid] = value
                    break

    # Licence du fichier : on écarte tout ce qui demande une attribution.
    licenses: dict[str, str] = {}
    names = sorted(set(files.values()))
    for start in range(0, len(names), 40):
        batch = names[start:start + 40]
        data = api("https://commons.wikimedia.org/w/api.php?action=query&titles="
                   + urllib.parse.quote("|".join(f"File:{n}" for n in batch))
                   + "&prop=imageinfo&iiprop=extmetadata&format=json",
                   f"commons-{start}.json", offline)
        for page in data["query"]["pages"].values():
            info = (page.get("imageinfo") or [{}])[0].get("extmetadata", {})
            name = page.get("title", "")[len("File:"):]
            licenses[name] = (info.get("LicenseShortName", {}).get("value", "")
                              or info.get("License", {}).get("value", "")).lower()

    logos = {}
    for article, qid in by_article.items():
        name = files.get(qid)
        if not name:
            continue
        license_name = licenses.get(name, "")
        if not any(tag in license_name for tag in FREE_LICENSES):
            continue
        # Wikidata garde parfois un logo d'époque (« Microsoft logo (1980) »).
        # Un millésime ancien dans le nom de fichier le trahit.
        years = [int(y) for y in re.findall(r"(?:19|20)\d{2}", name)]
        if years and max(years) < CURRENT_YEAR - 3:
            continue
        quoted = urllib.parse.quote(name.replace(" ", "_"))
        logos[article] = f"https://commons.wikimedia.org/wiki/Special:FilePath/{quoted}?width=160"
    return logos


def eodhd_logos() -> set[str]:
    """Tickers dont EODHD sert un logo (relevé par tools/check_sp500_logos.sh)."""
    path = CACHE / "eodhd-logos.txt"
    if not path.exists():
        return set()
    found = set()
    for line in path.read_text().splitlines():
        parts = line.split()
        if len(parts) == 2 and parts[1] == "200":
            found.add(parts[0].upper())
    return found


# ----------------------------------------------------------------------- SQL

def sql_string(value) -> str:
    if value is None:
        return "null"
    return "'" + str(value).replace("'", "''") + "'"


def group_for(row: dict) -> str:
    industry = row["industry"].lower()
    for group, keywords in INDUSTRY_GROUPS.items():
        if any(keyword in industry for keyword in keywords):
            return group
    return SECTORS[row["sector"]][2]


def build(offline: bool) -> str:
    rows = constituents(offline)
    eodhd = eodhd_index(offline)
    logos = wikidata_logos(rows, offline)
    eodhd_logo_tickers = eodhd_logos()

    inserts, updates, skipped = [], [], []
    for row in rows:
        ticker = row["ticker"]
        code = ticker.replace(".", "-")
        listing = eodhd.get(code)
        if listing is None or row["sector"] not in SECTORS:
            skipped.append(ticker)
            continue

        logo = logos.get(row["article"])
        if ticker.upper() in eodhd_logo_tickers:
            # Le logo du fournisseur de cours est à jour plus souvent que
            # celui de Wikidata, qui garde parfois une version historique.
            logo = f"https://eodhd.com/img/logos/US/{code.lower()}.png"

        if ticker in ALREADY_LISTED:
            symbol = ALREADY_LISTED[ticker]
            if symbol and logo:
                updates.append((symbol, logo))
            continue

        symbol = CLASHES.get(ticker, ticker.replace(".", ""))
        sector_fr, sector_en, _ = SECTORS[row["sector"]]
        initials = re.sub(r"[^A-Z0-9]", "", row["name"].upper())[:2] or ticker[:2]
        inserts.append({
            "symbol": symbol,
            "eodhd_symbol": f"{code}.US",
            "currency": listing.get("Currency") or "USD",
            "name": row["name"],
            "country_code": "US",
            "country": "États-Unis",
            "sector": sector_fr,
            "sector_en": sector_en,
            "sector_group": group_for(row),
            "region": "us",
            "initials": initials,
            "logo_url": logo,
        })

    lines = [
        "-- =====================================================================",
        "-- Les 500 sociétés du S&P 500.",
        "--",
        "-- Fichier GÉNÉRÉ par tools/build_sp500_seed.py — ne pas éditer à la",
        "-- main. Composition et secteurs : Wikipédia. Place de cotation et",
        "-- devise : EODHD. Logos : Wikimedia Commons (domaine public ou marque",
        "-- déposée) ou EODHD.",
        "--",
        "-- Rejouable : les fiches déjà rédigées ne sont pas écrasées, seul leur",
        "-- logo est complété.",
        "-- =====================================================================",
        "",
        "insert into public.securities",
        "  (symbol, eodhd_symbol, currency, asset_type, name, country_code, country,",
        "   sector, sector_en, sector_group, region, initials, logo_url)",
        "values",
    ]
    values = []
    for item in inserts:
        values.append(
            "  ({symbol}, {eodhd}, {currency}, 'stock', {name}, 'US', {country},"
            " {sector}, {sector_en}, {group}, 'us', {initials}, {logo})".format(
                symbol=sql_string(item["symbol"]), eodhd=sql_string(item["eodhd_symbol"]),
                currency=sql_string(item["currency"]), name=sql_string(item["name"]),
                country=sql_string(item["country"]), sector=sql_string(item["sector"]),
                sector_en=sql_string(item["sector_en"]), group=sql_string(item["sector_group"]),
                initials=sql_string(item["initials"]), logo=sql_string(item["logo_url"])))
    lines.append(",\n".join(values))
    lines.append("on conflict (symbol) do update set")
    lines.append("  logo_url = coalesce(public.securities.logo_url, excluded.logo_url);")
    lines.append("")

    if updates:
        lines.append("-- Logos des titres déjà au catalogue.")
        lines.append("update public.securities set logo_url = v.logo")
        lines.append("from (values")
        lines.append(",\n".join(f"  ({sql_string(s)}, {sql_string(u)})" for s, u in updates))
        lines.append(") as v(symbol, logo)")
        lines.append("where public.securities.symbol = v.symbol")
        lines.append("  and public.securities.logo_url is distinct from v.logo;")
        lines.append("")

    print(f"{len(inserts)} titres ajoutés · {len(updates)} logos complétés "
          f"· {len(skipped)} écartés {skipped if skipped else ''}")
    with_logo = sum(1 for item in inserts if item["logo_url"])
    print(f"{with_logo}/{len(inserts)} nouveaux titres ont un logo")
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--offline", action="store_true",
                        help="n'utilise que le cache réseau déjà téléchargé")
    args = parser.parse_args()
    SEED.parent.mkdir(parents=True, exist_ok=True)
    SEED.write_text(build(args.offline) + "\n")
    print(f"→ {SEED.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
