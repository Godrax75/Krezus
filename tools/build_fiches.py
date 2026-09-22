#!/usr/bin/env python3
"""Rédige la fiche « Que fait l'entreprise ? » de chaque action.

    python3 tools/build_fiches.py            # complète les fiches manquantes
    python3 tools/build_fiches.py --all      # refait tout
    python3 tools/build_fiches.py --limit 20 # essai sur vingt titres

Le catalogue est passé de quatre-vingts titres rédigés à la main à plus de
mille : les nouveaux arrivent sans un mot de description. L'offre
Fundamentals d'EODHD, qui en fournirait, n'est pas dans l'abonnement.

La source est donc **Wikipédia**, dont le premier paragraphe dit
précisément ce que fait une société. Il n'est pas recopié : Claude le
condense en deux phrases dans chaque langue, à partir de ce seul texte.
Un fait absent du paragraphe n'a pas à apparaître dans la fiche — c'est la
consigne, et c'est ce qui sépare un résumé d'une invention.

Les entreprises sont retrouvées par leur article, connu des listes
d'indices déjà en cache (`build/index-seed-cache/`), sinon par leur code
ISIN auprès de Wikidata.

Produit `supabase/seed/descriptions.sql`, rejouable : seules les fiches
vides sont complétées, les textes écrits à la main ne bougent pas.
"""

import argparse
import concurrent.futures
import json
import pathlib
import re
import subprocess
import sys
import time
import urllib.parse
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
CACHE = ROOT / "build" / "fiches-cache"
SEED = ROOT / "supabase" / "seed" / "descriptions.sql"
PROJECT_REF = "nxvqupjaqkdulhddnlvy"
UA = "KrezusApp/0.1 (contact: louisgodron45@gmail.com)"
MODEL = "claude-haiku-4-5-20251001"

sys.path.insert(0, str(ROOT / "tools"))
import importlib.util

_spec = importlib.util.spec_from_file_location("index_seed", ROOT / "tools" / "build_index_seed.py")
index_seed = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(index_seed)


# ------------------------------------------------------------------ Sources

def catalogue() -> list[dict]:
    """Les actions du référentiel, lues en base (lecture seule)."""
    query = ("select symbol, name, isin, sector, country_code, "
             "coalesce(description_fr, '') as description_fr "
             "from securities where asset_type = 'stock' order by symbol")
    out = subprocess.run(
        ["npx", "supabase", "db", "query", "--linked", "--project-ref", PROJECT_REF, query],
        capture_output=True, text=True, cwd=ROOT, check=True).stdout
    return json.loads(out[out.index("{"):out.rindex("}") + 1])["rows"]


def articles_by_name() -> dict[str, tuple[str, str]]:
    """Nom normalisé -> (article Wikipédia, langue), d'après les listes en cache."""
    mapping: dict[str, tuple[str, str]] = {}
    for row in index_seed.sp500_constituents(True):
        mapping[index_seed.normalized_name(row["name"])] = (row["article"], "en")
    for key in index_seed.WIKI_INDICES:
        for row in index_seed.wiki_index_rows(key, True):
            mapping.setdefault(index_seed.normalized_name(row["name"]), (row["article"], "en"))
    for row in index_seed.sbf120_constituents(True):
        mapping[index_seed.normalized_name(row["name"])] = (row["article"], "fr")
    return mapping


def articles_by_isin(isins: list[str]) -> dict[str, tuple[str, str]]:
    """ISIN -> (article, langue), demandé à Wikidata par paquets."""
    found: dict[str, tuple[str, str]] = {}
    for start in range(0, len(isins), 150):
        batch = isins[start:start + 150]
        values = " ".join(f'"{isin}"' for isin in batch)
        query = f"""
        SELECT ?isin ?fr ?en WHERE {{
          VALUES ?isin {{ {values} }}
          ?item wdt:P946 ?isin .
          OPTIONAL {{ ?fr schema:about ?item ; schema:isPartOf <https://fr.wikipedia.org/> }}
          OPTIONAL {{ ?en schema:about ?item ; schema:isPartOf <https://en.wikipedia.org/> }}
        }}"""
        data = fetch_json("https://query.wikidata.org/sparql?format=json&query="
                          + urllib.parse.quote(query), f"wikidata-isin-{start}.json")
        for binding in data["results"]["bindings"]:
            isin = binding["isin"]["value"]
            if "fr" in binding:
                found[isin] = (title_of(binding["fr"]["value"]), "fr")
            elif "en" in binding:
                found[isin] = (title_of(binding["en"]["value"]), "en")
    return found


def title_of(url: str) -> str:
    return urllib.parse.unquote(url.rsplit("/wiki/", 1)[-1]).replace("_", " ")


def extracts(titles: list[str], language: str) -> dict[str, str]:
    """Titre -> premier paragraphe de l'article, en texte brut."""
    found: dict[str, str] = {}
    for start in range(0, len(titles), 20):
        batch = titles[start:start + 20]
        data = fetch_json(
            f"https://{language}.wikipedia.org/w/api.php?action=query&prop=extracts"
            "&exintro=1&explaintext=1&exlimit=20&redirects=1&format=json&formatversion=2"
            "&titles=" + urllib.parse.quote("|".join(batch)),
            f"extracts-{language}-{start}.json")
        for page in data.get("query", {}).get("pages", []):
            text = (page.get("extract") or "").strip()
            if text:
                found[page["title"]] = text
        # Les redirections changent le titre : on garde les deux entrées.
        for item in data.get("query", {}).get("redirects", []):
            if item["to"] in found:
                found[item["from"]] = found[item["to"]]
    return found


def fetch_json(url: str, cache_name: str) -> dict:
    CACHE.mkdir(parents=True, exist_ok=True)
    path = CACHE / cache_name
    if path.exists():
        return json.loads(path.read_text())
    request = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "application/json"})
    data = urllib.request.urlopen(request, timeout=60).read()
    path.write_text(data.decode())
    time.sleep(0.2)
    return json.loads(data)


# -------------------------------------------------------------------- Claude

PROMPT = """Tu rédiges la fiche d'une action pour Krezus, une app française qui \
apprend à investir avec de l'argent fictif. Le lecteur est débutant.

Société : {name} ({country}, secteur : {sector})

Extrait de Wikipédia :
\"\"\"{extract}\"\"\"

Écris deux phrases en français et deux en anglais qui disent ce que fait cette \
société : ce qu'elle vend ou produit, à qui, et son ordre de grandeur si \
l'extrait le donne.

Règles :
- ne dis rien que l'extrait ne dise pas ; pas de chiffre inventé, pas de date \
approximative ;
- pas de jugement ni de conseil (« valeur solide », « à surveiller » sont \
proscrits) : la fiche décrit une entreprise, elle ne recommande pas un titre ;
- pas de superlatif publicitaire repris tel quel (« leader mondial » ne passe \
que si l'extrait l'établit) ;
- phrases courtes, présent de l'indicatif, pas de jargon ;
- si l'extrait ne parle pas de l'activité, écris une seule phrase factuelle \
avec ce qu'il y a.

Réponds uniquement par un objet JSON : {{"fr": "...", "en": "..."}}"""


def summarise(entry: dict, api_key: str) -> dict | None:
    cache = CACHE / f"fiche-{entry['symbol'].replace('/', '_')}.json"
    if cache.exists():
        return json.loads(cache.read_text())

    body = json.dumps({
        "model": MODEL,
        "max_tokens": 500,
        "messages": [{"role": "user", "content": PROMPT.format(
            name=entry["name"], country=entry.get("country_code") or "",
            sector=entry.get("sector") or "", extract=entry["extract"][:1800])}],
    }).encode()
    request = urllib.request.Request(
        "https://api.anthropic.com/v1/messages", data=body,
        headers={"content-type": "application/json", "anthropic-version": "2023-06-01",
                 "x-api-key": api_key})
    try:
        payload = json.load(urllib.request.urlopen(request, timeout=90))
    except Exception as error:                       # noqa: BLE001 — on note et on passe
        print(f"  {entry['symbol']} : {error}")
        return None

    text = "".join(part.get("text", "") for part in payload.get("content", []))
    match = re.search(r"\{.*\}", text, re.S)
    if not match:
        return None
    try:
        fiche = json.loads(match.group(0))
    except json.JSONDecodeError:
        return None
    if not fiche.get("fr") or not fiche.get("en"):
        return None
    cache.write_text(json.dumps(fiche, ensure_ascii=False))
    return fiche


def anthropic_key() -> str:
    env = ROOT / "supabase" / "functions" / ".env"
    for line in env.read_text().splitlines():
        if line.startswith("ANTHROPIC_API_KEY="):
            return line.split("=", 1)[1].strip()
    raise SystemExit("ANTHROPIC_API_KEY introuvable dans supabase/functions/.env")


# ----------------------------------------------------------------------- SQL

def emit(fiches: list[tuple[str, dict]]) -> str:
    lines = [
        "-- =====================================================================",
        "-- Fiches « Que fait l'entreprise ? »",
        "--",
        "-- Fichier GÉNÉRÉ par tools/build_fiches.py — ne pas éditer à la main.",
        "-- Source : premier paragraphe de l'article Wikipédia de chaque société,",
        "-- condensé en deux phrases par langue. Aucun fait n'est ajouté à ce que",
        "-- l'article dit.",
        "--",
        "-- Les fiches rédigées à la main ne sont pas écrasées.",
        "-- =====================================================================",
        "",
        "update public.securities s set",
        "  description_fr = coalesce(nullif(s.description_fr, ''), v.fr),",
        "  description_en = coalesce(nullif(s.description_en, ''), v.en)",
        "from (values",
    ]
    rows = ",\n".join(
        f"  ({index_seed.sql_string(symbol)}, {index_seed.sql_string(fiche['fr'])}, "
        f"{index_seed.sql_string(fiche['en'])})" for symbol, fiche in fiches)
    lines.append(rows)
    lines.append(") as v(symbol, fr, en)")
    lines.append("where s.symbol = v.symbol;")
    return "\n".join(lines) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--all", action="store_true", help="refait aussi les fiches existantes")
    parser.add_argument("--limit", type=int, default=0, help="s'arrête après N titres")
    args = parser.parse_args()

    rows = catalogue()
    todo = [row for row in rows if args.all or not row["description_fr"].strip()]
    if args.limit:
        todo = todo[:args.limit]
    print(f"{len(rows)} actions au catalogue · {len(todo)} fiches à écrire")

    by_name = articles_by_name()
    matched: dict[str, tuple[str, str]] = {}
    unmatched = []
    for row in todo:
        hit = by_name.get(index_seed.normalized_name(row["name"]))
        if hit:
            matched[row["symbol"]] = hit
        elif row.get("isin"):
            unmatched.append(row)
    if unmatched:
        by_isin = articles_by_isin([row["isin"] for row in unmatched])
        for row in unmatched:
            hit = by_isin.get(row["isin"])
            if hit:
                matched[row["symbol"]] = hit
    print(f"{len(matched)} articles Wikipédia retrouvés")

    # Extraits, groupés par langue d'article.
    texts: dict[str, str] = {}
    for language in ("fr", "en"):
        titles = sorted({article for article, lang in matched.values() if lang == language})
        if not titles:
            continue
        found = extracts(titles, language)
        for symbol, (article, lang) in matched.items():
            if lang == language and article in found:
                texts[symbol] = found[article]
    print(f"{len(texts)} extraits récupérés")

    entries = [dict(row, extract=texts[row["symbol"]]) for row in todo if row["symbol"] in texts]
    key = anthropic_key()
    fiches: list[tuple[str, dict]] = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
        futures = {pool.submit(summarise, entry, key): entry for entry in entries}
        for done, future in enumerate(concurrent.futures.as_completed(futures), 1):
            entry = futures[future]
            fiche = future.result()
            if fiche:
                fiches.append((entry["symbol"], fiche))
            if done % 50 == 0:
                print(f"  {done}/{len(entries)}…")

    if not fiches:
        raise SystemExit("aucune fiche produite")
    fiches.sort()
    SEED.write_text(emit(fiches))
    print(f"{len(fiches)} fiches écrites → {SEED.relative_to(ROOT)}")
    missing = [row["symbol"] for row in todo if row["symbol"] not in dict(fiches)]
    if missing:
        print(f"{len(missing)} sans fiche (aucun article trouvé) : {missing[:12]}…")


if __name__ == "__main__":
    main()
