#!/usr/bin/env python3
"""Génère le référentiel titres d'un indice : `supabase/seed/<indice>.sql`.

    python3 tools/build_index_seed.py sp500
    python3 tools/build_index_seed.py sbf120 --offline   # cache réseau seul

Sources, toutes publiques :

  - **Wikipédia** donne la composition de l'indice. Pour le S&P 500, la
    liste anglaise porte aussi le secteur GICS de chaque société ; pour le
    SBF 120, la liste française ne donne que les noms. EODHD exposerait ces
    compositions dans son offre Fundamentals, que l'abonnement Krezus ne
    comprend pas.
  - **Wikidata** relie chaque article à son code ISIN, à son secteur
    d'activité et à son logo. C'est ce qui permet de retrouver un titre
    dans le référentiel du fournisseur de cours sans se fier aux noms.
  - **EODHD** (`exchange-symbol-list`) valide chaque ligne de cotation et
    donne son mnémonique et sa devise. Un titre introuvable est écarté :
    il ne serait pas cotable dans l'app.
  - **Wikimedia Commons** fournit les logos. Seules les images du domaine
    public, sous CC0 ou déposées comme simples marques sont retenues : une
    licence à attribution obligerait à citer l'auteur sous chaque ligne de
    liste. À défaut, le logo EODHD s'il existe, sinon les initiales.

Le fichier produit est rejouable : les titres déjà présents gardent leurs
fiches rédigées à la main, seul leur logo est complété.
"""

import argparse
import html.parser
import json
import pathlib
import re
import time
import unicodedata
import urllib.parse
import urllib.request

CURRENT_YEAR = time.gmtime().tm_year
ROOT = pathlib.Path(__file__).resolve().parent.parent
CACHE = ROOT / "build" / "index-seed-cache"
UA = "KrezusApp/0.1 (contact: louisgodron45@gmail.com)"

# Licences acceptées : aucune ne demande de citer un auteur.
FREE_LICENSES = ("public domain", "pd-", "cc0", "trademark")

# Secteur GICS -> (libellé français, libellé anglais, famille `sector_group`).
GICS = {
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

# Famille de secteur devinée depuis un libellé d'activité en français, quand
# aucune classification GICS n'accompagne la liste. Premier mot-clé trouvé,
# dans cet ordre : « banque de détail » doit tomber dans la finance avant que
# « détail » ne l'envoie dans la consommation.
KEYWORD_GROUPS = [
    ("finance",    ("banque", "assurance", "gestion d'actifs", "financ", "bourse",
                    "paiement", "capital-investissement", "crédit")),
    ("realestate", ("immobili", "foncièr", "société d'investissement immobilier")),
    ("utilities",  ("service public", "collectivit", "distribution d'eau",
                    "traitement des eaux", "électricité", "gestion des déchets")),
    ("energy",     ("pétrol", "gaz naturel", "énergie", "forage", "raffin")),
    ("health",     ("pharmac", "santé", "biotechnolog", "médic", "laboratoire",
                    "hôpital", "diagnostic", "optique")),
    ("auto",       ("automobile", "équipementier automobile", "pneumatique")),
    ("technology", ("logiciel", "informatique", "semi-conducteur", "internet",
                    "numérique", "électronique", "technolog", "conseil en technologie")),
    ("telecom",    ("télécommunication", "média", "publicité", "audiovisuel",
                    "édition", "jeu vidéo", "presse")),
    ("materials",  ("chimi", "métallurgie", "sidérurgie", "matériaux", "ciment",
                    "minier", "acier", "papier", "verre", "plastique", "caoutchouc",
                    "emballage")),
    ("consumer",   ("luxe", "distribution", "agroalimentaire", "boisson", "cosmét",
                    "hôtel", "restauration", "textile", "habillement", "tourisme",
                    "grande distribution", "commerce", "loisir", "parfum")),
    ("industry",   ("industrie", "construction", "bâtiment", "transport", "logistique",
                    "aéronautique", "défense", "ingénierie", "aérospatial", "manufactur",
                    "équipement", "services aux entreprises", "intérim", "certification")),
]

# La sous-industrie affine la famille quand le secteur GICS la noie : une
# marque automobile n'est pas « consommation discrétionnaire » dans la
# répartition d'un portefeuille, elle est automobile.
GICS_INDUSTRY_GROUPS = {
    "auto": ("automobile", "automotive"),
    "technology": ("semiconductor", "software", "internet"),
    "realestate": ("reit",),
}

# S&P 500 : tickers déjà au catalogue pour la même société. On ne touche pas
# à leur fiche, seulement au logo.
SP500_ALREADY_LISTED = {
    "AAPL": "AAPL", "MSFT": "MSFT", "NVDA": "NVDA", "GOOGL": None, "GOOG": "GOOG",
    "AMZN": "AMZN", "TSLA": "TSLA", "JPM": "JPM", "BAC": "BAC", "WFC": "WFC",
    "V": "V", "MA": "MA", "BRK.B": "BRKB",
}

# Tickers américains homonymes d'une valeur de Paris déjà listée.
SP500_CLASHES = {"CARR": "CARR.US", "DG": "DG.US", "EFX": "EFX.US"}

# SBF 120 : places où chercher la ligne de cotation. Quelques membres de
# l'indice cotent à Amsterdam ou à Bruxelles (Aperam, Solvay).
SBF120_EXCHANGES = ("PA", "AS", "BR")
COUNTRY_BY_EXCHANGE = {"PA": "FR", "AS": "NL", "BR": "BE"}
COUNTRY_NAMES = {"PA": "France", "AS": "Pays-Bas", "BR": "Belgique"}
REGION_BY_EXCHANGE = {"PA": "fr", "AS": "europe", "BR": "europe"}

# Libellé générique d'une famille, quand Wikidata ne donne qu'une case de
# nomenclature (« Activités des sièges sociaux ») qui n'apprend rien.
GROUP_LABELS = {
    "technology": ("Technologies de l'information", "Information technology"),
    "finance":    ("Finance", "Financials"),
    "consumer":   ("Consommation", "Consumer"),
    "industry":   ("Industrie", "Industrials"),
    "energy":     ("Énergie-pétrole", "Energy and oil"),
    "utilities":  ("Services aux collectivités", "Utilities"),
    "health":     ("Santé", "Health care"),
    "auto":       ("Automobile", "Automotive"),
    "materials":  ("Matériaux", "Materials"),
    "telecom":    ("Communication-médias", "Communication services"),
    "realestate": ("Immobilier", "Real estate"),
}

# Cases de nomenclature statistique : elles décrivent une forme juridique ou
# un fourre-tout, pas un métier.
GENERIC_LABELS = ("activités des", "activité des", "autres ", "n.c.a", "holding",
                  "siège social", "sièges sociaux")

# Sociétés dont le nom d'usage ne ressemble pas au libellé de la place.
SBF120_ALIASES = {"TF1": "Télévision Française 1"}

# Secteur des sociétés que Wikidata ne classe pas, ou range dans une case
# trompeuse : une société de capital-investissement n'est pas une industrie,
# un éditeur de jeux n'est pas un fabricant.
SBF120_SECTORS = {
    "Argan":             ("Immobilier logistique", "Logistics property", "realestate"),
    "ID Logistics Group": ("Transport-logistique", "Transport and logistics", "industry"),
    "Remy Cointreau":    ("Boissons-spiritueux", "Drinks and spirits", "consumer"),
    "SEB":               ("Électroménager", "Home appliances", "consumer"),
    "Technip Energies":  ("Ingénierie · Énergie", "Engineering · Energy", "energy"),
    "TF1":               ("Médias-audiovisuel", "Media and broadcasting", "telecom"),
    "Ayvens":            ("Location longue durée", "Vehicle leasing", "finance"),
    "Bolloré":           ("Holding · Transport", "Holding · Transport", "industry"),
    "Eurazeo":           ("Capital-investissement", "Private equity", "finance"),
    "FDJ":               ("Jeux d'argent", "Gaming and lotteries", "consumer"),
    "Imerys":            ("Minéraux industriels", "Industrial minerals", "materials"),
    "Maurel & Prom":     ("Énergie-pétrole", "Energy and oil", "energy"),
    "MedinCell":         ("Pharmaceutique", "Pharmaceuticals", "health"),
    "Pluxee":            ("Services aux salariés", "Employee benefits", "finance"),
    "Rexel":             ("Distribution professionnelle", "Industrial distribution", "industry"),
    "Robertet":          ("Arômes et parfums", "Flavours and fragrances", "materials"),
    "Teleperformance":   ("Services aux entreprises", "Business services", "industry"),
    "Trigano":           ("Véhicules de loisirs", "Leisure vehicles", "consumer"),
    "Vivendi":           ("Médias", "Media", "telecom"),
    "Vusion":            ("Étiquettes électroniques", "Digital shelf labels", "technology"),
    "Wendel":            ("Capital-investissement", "Private equity", "finance"),
    "Worldline":         ("Paiements", "Payments", "finance"),
}


# ------------------------------------------------------------------- Réseau

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
    data = fetch(url, cache_name, offline)
    try:
        return json.loads(data)
    except json.JSONDecodeError:
        (CACHE / cache_name).unlink(missing_ok=True)
        raise SystemExit(f"{cache_name} : réponse non JSON — {data[:120]!r}")


def eodhd_token() -> str | None:
    env = ROOT / "supabase" / "functions" / ".env"
    if not env.exists():
        return None
    for line in env.read_text().splitlines():
        if line.startswith("EODHD_API_TOKEN="):
            return line.split("=", 1)[1].strip()
    return None


def eodhd_listings(exchange: str, offline: bool) -> list[dict]:
    cache = f"eodhd-{exchange.lower()}.json"
    token = eodhd_token()
    if token is None and not (CACHE / cache).exists():
        raise SystemExit("EODHD_API_TOKEN introuvable dans supabase/functions/.env")
    rows = api(f"https://eodhd.com/api/exchange-symbol-list/{exchange}"
               f"?api_token={token}&fmt=json", cache, offline)
    if not isinstance(rows, list):
        # Quota épuisé ou place inconnue : on ne garde pas la réponse en cache.
        (CACHE / cache).unlink(missing_ok=True)
        raise SystemExit(f"EODHD {exchange} : réponse inattendue {str(rows)[:120]}")
    return rows


# -------------------------------------------------------------- Compositions

def sp500_constituents(offline: bool) -> list[dict]:
    """Ticker, nom, article et secteur GICS des sociétés du S&P 500."""
    page = api(
        "https://en.wikipedia.org/w/api.php?action=parse&page=List_of_S%26P_500_companies"
        "&prop=wikitext&section=1&format=json", "wikipedia-sp500.json", offline)
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


def sbf120_constituents(offline: bool) -> list[dict]:
    """Nom et article des sociétés du SBF 120 (liste française, sans ticker)."""
    page = api("https://fr.wikipedia.org/w/api.php?action=parse&page=SBF_120"
               "&prop=wikitext&format=json", "wikipedia-sbf120.json", offline)
    wikitext = page["parse"]["wikitext"]["*"]
    section = wikitext[wikitext.find("Liste des entreprises"):]

    rows, seen = [], set()
    for match in re.finditer(r"^#\s*\[\[([^\]|]+)(?:\|([^\]]+))?\]\]", section, re.MULTILINE):
        article = match.group(1).strip()
        if article in seen:
            continue
        seen.add(article)
        rows.append({
            "article": article,
            "name": (match.group(2) or article).strip(),
        })
    if len(rows) < 100:
        raise SystemExit(f"Liste Wikipédia inattendue : {len(rows)} lignes")
    return rows


# -------------------------------------------------------------- Wikidata

def wikidata_claims(rows: list[dict], wiki: str, tag: str, offline: bool) -> dict[str, dict]:
    """Article -> {isin, industries (QID), logo (fichier Commons)}."""
    titles = [row["article"] for row in rows]
    qids: dict[str, str] = {}
    redirects: dict[str, str] = {}
    for start in range(0, len(titles), 50):
        data = api(f"https://{wiki}/w/api.php?action=query&prop=pageprops&titles="
                   + urllib.parse.quote("|".join(titles[start:start + 50]))
                   + "&format=json&redirects=1", f"{tag}-pageprops-{start}.json", offline)
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

    claims: dict[str, dict] = {}
    unique = sorted(set(by_article.values()))
    for start in range(0, len(unique), 50):
        data = api("https://www.wikidata.org/w/api.php?action=wbgetentities&ids="
                   + "|".join(unique[start:start + 50]) + "&props=claims&format=json",
                   f"{tag}-wikidata-{start}.json", offline)
        for qid, entity in data.get("entities", {}).items():
            entity_claims = entity.get("claims", {})
            claims[qid] = {
                "isins": values_of(entity_claims, "P946"),
                "industries": [v["id"] for v in values_of(entity_claims, "P452") if isinstance(v, dict)],
                "logo": (values_of(entity_claims, "P154") or [None])[0],
            }

    return {article: claims.get(qid, {}) for article, qid in by_article.items()}


def values_of(claims: dict, prop: str) -> list:
    out = []
    for claim in claims.get(prop, []):
        value = claim["mainsnak"].get("datavalue", {}).get("value")
        if value is not None:
            out.append(value)
    return out


def wikidata_labels(qids: list[str], tag: str, offline: bool) -> dict[str, tuple[str, str]]:
    """QID -> (libellé français, libellé anglais)."""
    labels = {}
    unique = sorted(set(qids))
    for start in range(0, len(unique), 50):
        data = api("https://www.wikidata.org/w/api.php?action=wbgetentities&ids="
                   + "|".join(unique[start:start + 50])
                   + "&props=labels&languages=fr|en&format=json",
                   f"{tag}-labels-{start}.json", offline)
        for qid, entity in data.get("entities", {}).items():
            entity_labels = entity.get("labels", {})
            labels[qid] = (entity_labels.get("fr", {}).get("value"),
                           entity_labels.get("en", {}).get("value"))
    return labels


def commons_logos(files: dict[str, str], tag: str, offline: bool) -> dict[str, str]:
    """Article -> URL du logo, quand sa licence n'impose pas d'attribution."""
    licenses: dict[str, str] = {}
    names = sorted({name for name in files.values() if name})
    for start in range(0, len(names), 40):
        data = api("https://commons.wikimedia.org/w/api.php?action=query&titles="
                   + urllib.parse.quote("|".join(f"File:{n}" for n in names[start:start + 40]))
                   + "&prop=imageinfo&iiprop=extmetadata&format=json",
                   f"{tag}-commons-{start}.json", offline)
        for page in data["query"]["pages"].values():
            info = (page.get("imageinfo") or [{}])[0].get("extmetadata", {})
            name = page.get("title", "")[len("File:"):]
            licenses[name] = (info.get("LicenseShortName", {}).get("value", "")
                              or info.get("License", {}).get("value", "")).lower()

    logos = {}
    for article, name in files.items():
        if not name or not any(tag_ in licenses.get(name, "") for tag_ in FREE_LICENSES):
            continue
        # Wikidata garde parfois un logo d'époque (« Microsoft logo (1980) »).
        # Un millésime ancien dans le nom de fichier le trahit.
        years = [int(y) for y in re.findall(r"(?:19|20)\d{2}", name)]
        if years and max(years) < CURRENT_YEAR - 3:
            continue
        quoted = urllib.parse.quote(name.replace(" ", "_"))
        logos[article] = f"https://commons.wikimedia.org/wiki/Special:FilePath/{quoted}?width=160"
    return logos


def eodhd_logo_tickers() -> set[str]:
    """Tickers dont EODHD sert un logo (relevé par tools/check_index_logos.sh)."""
    path = CACHE / "eodhd-logos.txt"
    if not path.exists():
        return set()
    return {line.split()[0].upper() for line in path.read_text().splitlines()
            if len(line.split()) == 2 and line.split()[1] == "200"}


# ----------------------------------------------------------------------- SQL

LEGAL_SUFFIXES = ("sa", "se", "sca", "sas", "scs", "plc", "nv", "ag", "spa",
                  "societe anonyme", "sa a directoire", "et cie")

# Mots qui n'aident pas à reconnaître une société dans un libellé de place.
NAME_NOISE = ("compagnie generale des etablissements", "groupe", "group",
              "compagnie", "societe", "etablissements")


def normalized_name(name: str) -> str:
    """Nom comparable d'une société : sans accent, sans forme juridique."""
    text = unicodedata.normalize("NFKD", name.lower())
    text = "".join(c for c in text if not unicodedata.combining(c))
    text = re.sub(r"[^a-z0-9 ]+", " ", text)
    for noise in NAME_NOISE:
        text = text.replace(noise, " ")
    words = [w for w in text.split() if w]
    while words and words[-1] in LEGAL_SUFFIXES:
        words.pop()
    return " ".join(words)


def find_listing(row: dict, isins: list[str], by_isin: dict, by_name: dict,
                 taken: set[str]) -> dict | None:
    """Ligne de cotation d'une société : par ISIN, sinon par nom.

    Wikidata garde parfois un ISIN périmé — une fusion ou un regroupement
    d'actions en crée un nouveau (Air France-KLM, Michelin, Dassault
    Systèmes) — ou même celui de la maison mère dont la société a été
    détachée : Pluxee porte encore l'ISIN de Sodexo. D'où les deux gardes :
    une ligne déjà attribuée n'est pas réattribuée, et le nom ne vaut que
    s'il ne désigne qu'une seule ligne. Deux candidats valent mieux écartés
    qu'un titre inscrit sous le mauvais code.
    """
    def free(listing: dict | None) -> dict | None:
        if listing is None:
            return None
        return None if f"{listing['Code']}.{listing['Exchange']}" in taken else listing

    # Le nom d'abord, l'ISIN ensuite : c'est le nom qui distingue une
    # société de la maison mère dont elle vient d'être détachée, quand
    # Wikidata leur donne encore le même code.
    for name in (SBF120_ALIASES.get(row["name"], row["name"]), row["article"]):
        candidates = [c for c in by_name.get(normalized_name(name), []) if free(c)]
        if len(candidates) == 1:
            return candidates[0]
    for isin in isins:
        if isin in by_isin and free(by_isin[isin]):
            return by_isin[isin]
    return None


def sql_string(value) -> str:
    if value is None:
        return "null"
    return "'" + str(value).replace("'", "''") + "'"


def group_from_keywords(labels: list[str]) -> str | None:
    text = " ".join(label.lower() for label in labels if label)
    for group, keywords in KEYWORD_GROUPS:
        if any(keyword in text for keyword in keywords):
            return group
    return None


def emit(title: str, inserts: list[dict], updates: list[tuple[str, str]]) -> str:
    lines = [
        "-- =====================================================================",
        f"-- {title}",
        "--",
        "-- Fichier GÉNÉRÉ par tools/build_index_seed.py — ne pas éditer à la",
        "-- main. Composition : Wikipédia. ISIN et secteur d'activité :",
        "-- Wikidata. Mnémonique et devise : EODHD. Logos : Wikimedia Commons",
        "-- (domaine public ou marque déposée) ou EODHD.",
        "--",
        "-- Rejouable : les fiches déjà rédigées ne sont pas écrasées, seul leur",
        "-- logo est complété.",
        "-- =====================================================================",
        "",
        "insert into public.securities",
        "  (symbol, eodhd_symbol, currency, asset_type, name, country_code, country,",
        "   sector, sector_en, sector_group, region, initials, logo_url, isin)",
        "values",
    ]
    values = []
    for item in inserts:
        values.append(
            "  ({symbol}, {eodhd}, {currency}, 'stock', {name}, {cc}, {country},"
            " {sector}, {sector_en}, {group}, {region}, {initials}, {logo}, {isin})".format(
                symbol=sql_string(item["symbol"]), eodhd=sql_string(item["eodhd_symbol"]),
                currency=sql_string(item["currency"]), name=sql_string(item["name"]),
                cc=sql_string(item["country_code"]), country=sql_string(item["country"]),
                sector=sql_string(item["sector"]), sector_en=sql_string(item["sector_en"]),
                group=sql_string(item["sector_group"]), region=sql_string(item["region"]),
                initials=sql_string(item["initials"]), logo=sql_string(item["logo_url"]),
                isin=sql_string(item.get("isin"))))
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

    return "\n".join(lines)


# ------------------------------------------------------ Tables de Wikipédia

class WikiTables(html.parser.HTMLParser):
    """Tables `wikitable` d'une page rendue : texte et premier lien de chaque
    cellule. Plus sûr que le wikicode, où chaque indice a ses modèles."""

    def __init__(self):
        super().__init__()
        self.tables: list[list[list[dict]]] = []
        self._table = None
        self._depth = 0
        self._row = None
        self._cell = None

    def handle_starttag(self, tag, attrs):
        attributes = dict(attrs)
        if tag == "table":
            if self._table is None and "wikitable" in (attributes.get("class") or ""):
                self._table, self._depth = [], 1
            elif self._table is not None:
                self._depth += 1
            return
        if self._table is None or self._depth != 1:
            return
        if tag == "tr":
            self._row = []
        elif tag in ("td", "th") and self._row is not None:
            self._cell = {"text": "", "link": None}
        elif tag == "a" and self._cell is not None and self._cell["link"] is None:
            href = attributes.get("href", "")
            if href.startswith("/wiki/") and ":" not in href[6:]:
                self._cell["link"] = urllib.parse.unquote(href[6:]).replace("_", " ")

    def handle_endtag(self, tag):
        if self._table is None:
            return
        if tag == "table":
            self._depth -= 1
            if self._depth == 0:
                self.tables.append(self._table)
                self._table = None
        elif self._depth == 1 and tag in ("td", "th") and self._cell is not None:
            self._cell["text"] = re.sub(r"\s+", " ", self._cell["text"]).strip()
            if self._row is not None:
                self._row.append(self._cell)
            self._cell = None
        elif self._depth == 1 and tag == "tr" and self._row is not None:
            if self._row:
                self._table.append(self._row)
            self._row = None

    def handle_data(self, data):
        if self._cell is not None:
            self._cell["text"] += data


def wiki_tables(page: str, cache_name: str, offline: bool) -> list:
    data = api("https://en.wikipedia.org/w/api.php?action=parse&page="
               + urllib.parse.quote(page) + "&prop=text&format=json&formatversion=2",
               cache_name, offline)
    parser = WikiTables()
    parser.feed(data["parse"]["text"])
    return parser.tables


# Indices européens, canadien et hongkongais : une table de composition par
# page Wikipédia, un mnémonique par ligne. `ticker`, `name` et `sector`
# nomment les colonnes ; `country` est le pays du siège par défaut.
WIKI_INDICES = {
    "ftse100": dict(page="FTSE 100 Index", exchange="LSE", country="GB",
                    ticker="Ticker", name="Company", sector="FTSE industry"),
    "dax":     dict(page="DAX", exchange="XETRA", country="DE",
                    ticker="Ticker", name="Company", sector="Prime Standard Sector"),
    "smi":     dict(page="Swiss Market Index", exchange="SW", country="CH",
                    ticker="Ticker", name="Name", sector="Sector"),
    "aex":     dict(page="AEX index", exchange="AS", country="NL",
                    ticker="Ticker", name="Company", sector="ICB Sector"),
    "ibex35":  dict(page="IBEX 35", exchange="MC", country="ES",
                    ticker="Ticker", name="Company", sector="Sector"),
    "ftsemib": dict(page="FTSE MIB", exchange="MI", country="IT",
                    ticker="Ticker", name="Company", sector="ICB Sector"),
    "omxs30":  dict(page="OMX Stockholm 30", exchange="ST", country="SE",
                    ticker="Ticker", name="Company", sector="GICS sector"),
    "c25":     dict(page="OMX Copenhagen 25", exchange="CO", country="DK",
                    ticker="Ticker symbol", name="Company", sector="ICB Sector"),
    "omxh25":  dict(page="OMX Helsinki 25", exchange="HE", country="FI",
                    ticker="Ticker", name="Company", sector="GICS sector"),
    "bel20":   dict(page="BEL 20", exchange="BR", country="BE",
                    ticker="Ticker symbol", name="Company", sector="ICB Sector"),
    "tsx60":   dict(page="S&P/TSX 60", exchange="TO", country="CA",
                    ticker="Symbol", name="Company", sector="Sector"),
    "hsi":     dict(page="Hang Seng Index", exchange="HK", country="HK",
                    ticker="Ticker", name="Name", sector="Sub-index"),
}

COUNTRY_NAMES_FR = {
    "GB": "Royaume-Uni", "DE": "Allemagne", "CH": "Suisse", "NL": "Pays-Bas",
    "ES": "Espagne", "IT": "Italie", "SE": "Suède", "DK": "Danemark",
    "FI": "Finlande", "BE": "Belgique", "CA": "Canada", "HK": "Hong Kong",
    "US": "États-Unis", "JP": "Japon", "TW": "Taïwan", "IN": "Inde",
    "BR": "Brésil", "CN": "Chine", "KR": "Corée du Sud", "SG": "Singapour",
    "AR": "Argentine", "MX": "Mexique", "IE": "Irlande", "LU": "Luxembourg",
    "IL": "Israël", "UY": "Uruguay", "FR": "France",
}

REGION_BY_COUNTRY = {
    "FR": "fr", "US": "us", "CA": "world", "HK": "asia_em", "CN": "asia_em",
    "JP": "asia_em", "TW": "asia_em", "IN": "asia_em", "KR": "asia_em",
    "SG": "asia_em", "BR": "asia_em", "AR": "asia_em", "MX": "asia_em",
    "UY": "asia_em", "IL": "world",
}

# Secteur en anglais (ICB, GICS, Prime Standard) -> famille. Même logique
# que KEYWORD_GROUPS : premier mot-clé trouvé.
EN_KEYWORD_GROUPS = [
    ("realestate", ("real estate", "reit", "property", "properties")),
    ("utilities",  ("utilit", "electricity", "water", "gas, water")),
    ("finance",    ("bank", "insurance", "financ", "investment", "asset manage",
                    "exchange", "payment", "capital", "life assurance")),
    ("energy",     ("oil", "energy", "gas producer", "petrol", "coal")),
    ("health",     ("health", "pharma", "biotech", "medical", "drug", "life science")),
    ("auto",       ("automobile", "auto", "car", "tyre", "tire")),
    ("technology", ("technology", "software", "semiconductor", "information",
                    "internet", "electronic", "computer", "it ")),
    ("telecom",    ("telecom", "media", "communication", "broadcast", "publishing",
                    "advertising", "entertainment")),
    ("materials",  ("chemical", "material", "mining", "metal", "steel", "paper",
                    "forest", "construction material", "cement", "packaging", "gold")),
    ("consumer",   ("consumer", "retail", "food", "beverage", "drink", "tobacco",
                    "apparel", "luxury", "personal", "household", "leisure", "travel",
                    "hotel", "restaurant", "cosmetic", "properties & conglomerates",
                    "properties and conglomerates", "gaming")),
    ("industry",   ("industrial", "aerospace", "defence", "defense", "transport",
                    "construction", "engineering", "logistic", "machinery", "airline",
                    "shipping", "conglomerate", "business services", "support services")),
]


def group_from_english(sector: str) -> str:
    text = f" {sector.lower()} "
    for group, keywords in EN_KEYWORD_GROUPS:
        if any(keyword in text for keyword in keywords):
            return group
    return "industry"


def normalize_ticker(raw: str, exchange: str) -> str | None:
    """Mnémonique de Wikipédia -> code EODHD de la place."""
    text = raw.strip()
    # « Euronext Brussels: ABI », « SEHK: 5 »
    if ":" in text:
        text = text.split(":")[-1].strip()
    text = text.split()[0] if exchange not in ("ST", "CO") else text
    # Suffixe de place déjà présent (« ADS.DE », « ACS.MC »).
    text = re.sub(r"\.(DE|AS|MC|MI|ST|CO|HE|BR|L|SW|TO|HK)$", "", text, flags=re.I)
    if exchange == "HK":
        digits = re.sub(r"\D", "", text)
        return digits.zfill(4) if digits else None
    text = text.replace(" ", "-").replace(".", "-").rstrip("-")
    return text.upper() or None


def wiki_index_rows(key: str, offline: bool) -> list[dict]:
    spec = WIKI_INDICES[key]
    for table in wiki_tables(spec["page"], f"wikipedia-{key}.json", offline):
        header = [cell["text"] for cell in table[0]]
        def column(label):
            for index, text in enumerate(header):
                if text.lower().startswith(label.lower()):
                    return index
            return None
        ticker_col, name_col, sector_col = column(spec["ticker"]), column(spec["name"]), column(spec["sector"])
        if ticker_col is None or name_col is None:
            continue
        rows = []
        for row in table[1:]:
            if len(row) <= max(ticker_col, name_col):
                continue
            name_cell = row[name_col]
            rows.append({
                "ticker": row[ticker_col]["text"],
                "name": re.sub(r"\[\d+\]", "", name_cell["text"]).strip(),
                "article": name_cell["link"] or name_cell["text"],
                "sector": row[sector_col]["text"] if sector_col is not None and sector_col < len(row) else "",
            })
        return rows
    raise SystemExit(f"{key} : table de composition introuvable")


# Valeurs très connues cotées à New York hors S&P 500 : les géants
# japonais, taïwanais, indiens et latino-américains qu'aucune place couverte
# ne liste, et les favoris des particuliers américains. Choisies à la main ;
# EODHD valide chaque ticker, un ticker inconnu est écarté.
# (ticker, nom, pays du siège, famille)
US_EXTRAS = [
    ("TM", "Toyota", "JP", "auto"), ("SONY", "Sony", "JP", "technology"),
    ("HMC", "Honda", "JP", "auto"), ("MUFG", "Mitsubishi UFJ", "JP", "finance"),
    ("SMFG", "Sumitomo Mitsui", "JP", "finance"), ("MFG", "Mizuho", "JP", "finance"),
    ("TAK", "Takeda", "JP", "health"), ("NMR", "Nomura", "JP", "finance"),
    ("IX", "ORIX", "JP", "finance"),
    ("TSM", "TSMC", "TW", "technology"), ("UMC", "United Microelectronics", "TW", "technology"),
    ("ASX", "ASE Technology", "TW", "technology"),
    ("INFY", "Infosys", "IN", "technology"), ("HDB", "HDFC Bank", "IN", "finance"),
    ("IBN", "ICICI Bank", "IN", "finance"), ("WIT", "Wipro", "IN", "technology"),
    ("RDY", "Dr. Reddy's", "IN", "health"),
    ("KB", "KB Financial", "KR", "finance"), ("PKX", "POSCO", "KR", "materials"),
    ("SKM", "SK Telecom", "KR", "telecom"),
    ("PDD", "PDD Holdings (Temu)", "CN", "consumer"), ("NIO", "NIO", "CN", "auto"),
    ("BILI", "Bilibili", "CN", "telecom"), ("FUTU", "Futu", "HK", "finance"),
    ("TME", "Tencent Music", "CN", "telecom"), ("ZTO", "ZTO Express", "CN", "industry"),
    ("BEKE", "KE Holdings", "CN", "realestate"), ("YUMC", "Yum China", "CN", "consumer"),
    ("MELI", "MercadoLibre", "UY", "consumer"), ("NU", "Nu Holdings", "BR", "finance"),
    ("VALE", "Vale", "BR", "materials"), ("PBR", "Petrobras", "BR", "energy"),
    ("ITUB", "Itaú Unibanco", "BR", "finance"), ("BBD", "Bradesco", "BR", "finance"),
    ("ABEV", "Ambev", "BR", "consumer"), ("AMX", "América Movil", "MX", "telecom"),
    ("FMX", "FEMSA", "MX", "consumer"), ("CX", "Cemex", "MX", "materials"),
    ("GGAL", "Grupo Galicia", "AR", "finance"), ("YPF", "YPF", "AR", "energy"),
    ("SQM", "SQM", "CL", "materials"), ("EC", "Ecopetrol", "CO", "energy"),
    ("TEVA", "Teva", "IL", "health"), ("CHKP", "Check Point", "IL", "technology"),
    ("MNDY", "monday.com", "IL", "technology"), ("NICE", "NICE", "IL", "technology"),
    ("WIX", "Wix", "IL", "technology"),
    ("SE", "Sea Limited", "SG", "consumer"), ("GRAB", "Grab", "SG", "industry"),
    ("SPOT", "Spotify", "LU", "telecom"), ("ARM", "Arm Holdings", "GB", "technology"),
    ("ONON", "On Holding", "CH", "consumer"), ("TEAM", "Atlassian", "US", "technology"),
    ("RIVN", "Rivian", "US", "auto"), ("LCID", "Lucid", "US", "auto"),
    ("RBLX", "Roblox", "US", "telecom"), ("SNOW", "Snowflake", "US", "technology"),
    ("NET", "Cloudflare", "US", "technology"), ("MDB", "MongoDB", "US", "technology"),
    ("ZS", "Zscaler", "US", "technology"), ("OKTA", "Okta", "US", "technology"),
    ("TWLO", "Twilio", "US", "technology"), ("DOCU", "DocuSign", "US", "technology"),
    ("ZM", "Zoom", "US", "technology"), ("PINS", "Pinterest", "US", "telecom"),
    ("SNAP", "Snap", "US", "telecom"), ("RDDT", "Reddit", "US", "telecom"),
    ("DUOL", "Duolingo", "US", "consumer"), ("SOFI", "SoFi", "US", "finance"),
    ("AFRM", "Affirm", "US", "finance"), ("UPST", "Upstart", "US", "finance"),
    ("TOST", "Toast", "US", "technology"), ("U", "Unity", "US", "technology"),
    ("ROKU", "Roku", "US", "telecom"), ("ETSY", "Etsy", "US", "consumer"),
    ("CHWY", "Chewy", "US", "consumer"), ("W", "Wayfair", "US", "consumer"),
    ("PTON", "Peloton", "US", "consumer"), ("GME", "GameStop", "US", "consumer"),
    ("AMC", "AMC Entertainment", "US", "telecom"), ("HIMS", "Hims & Hers", "US", "health"),
    ("IONQ", "IonQ", "US", "technology"), ("RKLB", "Rocket Lab", "US", "industry"),
    ("JOBY", "Joby Aviation", "US", "industry"), ("ACHR", "Archer Aviation", "US", "industry"),
    ("SOUN", "SoundHound AI", "US", "technology"), ("CELH", "Celsius", "US", "consumer"),
    ("MSTR", "Strategy", "US", "technology"), ("MARA", "MARA Holdings", "US", "finance"),
    ("RIOT", "Riot Platforms", "US", "finance"), ("PATH", "UiPath", "US", "technology"),
    ("AI", "C3.ai", "US", "technology"), ("PLUG", "Plug Power", "US", "energy"),
    ("CRWV", "CoreWeave", "US", "technology"), ("CAVA", "Cava", "US", "consumer"),
    ("CROX", "Crocs", "US", "consumer"), ("DKNG", "DraftKings", "US", "consumer"),
    ("SHOP", "Shopify", "CA", "technology"), ("BIDU", "Baidu", "CN", "technology"),
]


def listing_isins(lists: dict[str, list[dict]]) -> dict[str, str]:
    """`CODE.PLACE` -> ISIN, d'après les référentiels EODHD chargés."""
    return {f"{row['Code']}.{exchange}": row["Isin"]
            for exchange, rows in lists.items() for row in rows if row.get("Isin")}


def build_global(offline: bool, existing: dict[str, str]) -> str:
    exchanges = sorted({spec["exchange"] for spec in WIKI_INDICES.values()} | {"US", "PA"})
    lists = {exchange: eodhd_listings(exchange, offline) for exchange in exchanges}
    by_code = {exchange: {row["Code"].upper(): row for row in rows}
               for exchange, rows in lists.items()}
    by_name = {exchange: {} for exchange in lists}
    for exchange, rows in lists.items():
        for row in rows:
            if row.get("Type") == "Common Stock":
                by_name[exchange].setdefault(normalized_name(row["Name"]), []).append(row)

    isin_of = listing_isins(lists)
    # Une société déjà au catalogue — même cotée ailleurs — n'entre pas deux
    # fois : Airbus est au DAX, mais déjà listé à Paris.
    seen_isins = {isin_of[e] for e in existing if e in isin_of}
    existing_names = set()
    used_symbols = set(existing.values())
    seen_articles: set[str] = set()

    inserts, skipped = [], []

    # 1. Indices de Wikipédia.
    all_rows = []
    for key, spec in WIKI_INDICES.items():
        for row in wiki_index_rows(key, offline):
            all_rows.append((key, spec, row))
    claims = wikidata_claims([row for _, _, row in all_rows], "en.wikipedia.org", "global", offline)
    logos = commons_logos({article: claim.get("logo") for article, claim in claims.items()},
                          "global", offline)

    for key, spec, row in all_rows:
        exchange = spec["exchange"]
        if row["article"] in seen_articles:
            continue
        code = normalize_ticker(row["ticker"], exchange)
        listing = by_code[exchange].get(code or "")
        if listing is None:
            candidates = by_name[exchange].get(normalized_name(row["name"]), [])
            listing = candidates[0] if len(candidates) == 1 else None
        if listing is None or listing.get("Type") not in ("Common Stock", "Preferred Stock"):
            skipped.append(f"{key}:{row['ticker']}")
            continue
        eodhd_symbol = f"{listing['Code']}.{exchange}"
        isin = listing.get("Isin")
        if eodhd_symbol in existing or (isin and isin in seen_isins):
            continue
        seen_articles.add(row["article"])
        if isin:
            seen_isins.add(isin)

        symbol = listing["Code"].upper()
        if symbol in used_symbols:
            symbol = f"{symbol}.{exchange}"
        if symbol in used_symbols:
            skipped.append(f"{key}:{row['ticker']} (symbole pris)")
            continue
        used_symbols.add(symbol)

        group = group_from_english(row["sector"])
        country = spec["country"]
        sector_en = row["sector"][:1].upper() + row["sector"][1:] if row["sector"] else GROUP_LABELS[group][1]
        inserts.append({
            "symbol": symbol, "eodhd_symbol": eodhd_symbol,
            "currency": listing.get("Currency") or "EUR", "name": row["name"],
            "country_code": country, "country": COUNTRY_NAMES_FR.get(country, country),
            "sector": GROUP_LABELS[group][0], "sector_en": sector_en,
            "sector_group": group, "region": REGION_BY_COUNTRY.get(country, "europe"),
            "initials": re.sub(r"[^A-Z0-9]", "", row["name"].upper())[:2] or symbol[:2],
            "logo_url": logos.get(row["article"]), "isin": isin,
        })
        existing_names.add(normalized_name(row["name"]))

    # 2. Valeurs choisies cotées à New York.
    for ticker, name, country, group in US_EXTRAS:
        listing = by_code["US"].get(ticker)
        if listing is None:
            skipped.append(f"us:{ticker}")
            continue
        eodhd_symbol = f"{ticker}.US"
        isin = listing.get("Isin")
        if (eodhd_symbol in existing or (isin and isin in seen_isins)
                or normalized_name(name) in existing_names):
            continue
        if isin:
            seen_isins.add(isin)
        symbol = ticker if ticker not in used_symbols else f"{ticker}.US"
        if symbol in used_symbols:
            continue
        used_symbols.add(symbol)
        inserts.append({
            "symbol": symbol, "eodhd_symbol": eodhd_symbol,
            "currency": listing.get("Currency") or "USD", "name": name,
            "country_code": country, "country": COUNTRY_NAMES_FR.get(country, country),
            "sector": GROUP_LABELS[group][0], "sector_en": GROUP_LABELS[group][1],
            "sector_group": group, "region": REGION_BY_COUNTRY.get(country, "europe"),
            "initials": re.sub(r"[^A-Z0-9]", "", name.upper())[:2] or ticker[:2],
            "logo_url": None, "isin": isin,
        })

    report(inserts, [], skipped)
    return emit("Grandes valeurs mondiales : Europe, Canada, Hong Kong et "
                "valeurs connues cotées à New York.", inserts, [])


# ------------------------------------------------------------------- Indices

def build_sp500(offline: bool) -> str:
    rows = sp500_constituents(offline)
    listings = {row["Code"]: row for row in eodhd_listings("US", offline)}
    claims = wikidata_claims(rows, "en.wikipedia.org", "sp500", offline)
    logos = commons_logos({article: claim.get("logo") for article, claim in claims.items()},
                          "sp500", offline)
    eodhd_logos = eodhd_logo_tickers()

    inserts, updates, skipped = [], [], []
    for row in rows:
        ticker = row["ticker"]
        code = ticker.replace(".", "-")
        listing = listings.get(code)
        if listing is None or row["sector"] not in GICS:
            skipped.append(ticker)
            continue

        logo = logos.get(row["article"])
        if ticker.upper() in eodhd_logos:
            # Le logo du fournisseur de cours est à jour plus souvent que
            # celui de Wikidata, qui garde parfois une version historique.
            logo = f"https://eodhd.com/img/logos/US/{code.lower()}.png"

        if ticker in SP500_ALREADY_LISTED:
            symbol = SP500_ALREADY_LISTED[ticker]
            if symbol and logo:
                updates.append((symbol, logo))
            continue

        sector_fr, sector_en, sector_group = GICS[row["sector"]]
        industry = row["industry"].lower()
        for group, keywords in GICS_INDUSTRY_GROUPS.items():
            if any(keyword in industry for keyword in keywords):
                sector_group = group
                break

        inserts.append({
            "symbol": SP500_CLASHES.get(ticker, ticker.replace(".", "")),
            "eodhd_symbol": f"{code}.US",
            "currency": listing.get("Currency") or "USD",
            "name": row["name"],
            "country_code": "US",
            "country": "États-Unis",
            "sector": sector_fr,
            "sector_en": sector_en,
            "sector_group": sector_group,
            "region": "us",
            "initials": re.sub(r"[^A-Z0-9]", "", row["name"].upper())[:2] or ticker[:2],
            "logo_url": logo,
        })

    report(inserts, updates, skipped)
    return emit("Les 500 sociétés du S&P 500.", inserts, updates)


def build_sbf120(offline: bool, existing: set[str]) -> str:
    rows = sbf120_constituents(offline)
    listings = [listing for exchange in SBF120_EXCHANGES
                for listing in eodhd_listings(exchange, offline)]
    by_isin = {row["Isin"]: row for row in listings if row.get("Isin")}
    by_name: dict[str, list[dict]] = {}
    for listing in listings:
        if listing.get("Type") == "Common Stock":
            by_name.setdefault(normalized_name(listing["Name"]), []).append(listing)
    claims = wikidata_claims(rows, "fr.wikipedia.org", "sbf120", offline)
    logos = commons_logos({article: claim.get("logo") for article, claim in claims.items()},
                          "sbf120", offline)
    labels = wikidata_labels(
        [qid for claim in claims.values() for qid in claim.get("industries", [])],
        "sbf120", offline)

    inserts, updates, skipped = [], [], []
    used = set(existing.values())
    taken: set[str] = set()
    for row in rows:
        claim = claims.get(row["article"], {})
        listing = find_listing(row, claim.get("isins", []), by_isin, by_name, taken)
        if listing is None or listing.get("Type") != "Common Stock":
            skipped.append(row["name"])
            continue

        code = listing["Code"]
        eodhd_symbol = f"{code}.{listing['Exchange']}"
        taken.add(eodhd_symbol)
        logo = logos.get(row["article"])
        if eodhd_symbol in existing:
            # Déjà au catalogue : sa fiche a été rédigée à la main.
            if logo:
                updates.append((existing[eodhd_symbol], logo))
            continue

        # Secteur : le premier libellé d'activité qui tombe dans une de nos
        # familles. Aucun ne convient -> l'industrie, par défaut, et le nom
        # d'activité reste celui de Wikidata pour que ce soit vérifiable.
        industries = [labels.get(qid, (None, None)) for qid in claim.get("industries", [])]
        group = None
        sector_fr = sector_en = None
        if row["name"] in SBF120_SECTORS:
            sector_fr, sector_en, group = SBF120_SECTORS[row["name"]]
            industries = []
        for fr, en in industries:
            candidate = group_from_keywords([fr])
            if candidate and group is None:
                group, sector_fr, sector_en = candidate, fr, en
        if group is None and industries:
            sector_fr, sector_en = industries[0]
        if sector_fr and any(g in sector_fr.lower() for g in GENERIC_LABELS):
            sector_fr = sector_en = None
        if sector_fr is None:
            sector_fr, sector_en = GROUP_LABELS.get(group or "industry", (None, None))
        if sector_fr:
            sector_fr = sector_fr[0].upper() + sector_fr[1:]
        if sector_en:
            sector_en = sector_en[0].upper() + sector_en[1:]

        symbol = code if code not in used else f"{code}.{listing['Exchange']}"
        if symbol in used:
            skipped.append(f"{row['name']} (symbole {symbol} déjà pris)")
            continue
        used.add(symbol)
        inserts.append({
            "symbol": symbol,
            "eodhd_symbol": eodhd_symbol,
            "currency": listing.get("Currency") or "EUR",
            "name": row["name"],
            "country_code": COUNTRY_BY_EXCHANGE.get(listing["Exchange"], "FR"),
            "country": COUNTRY_NAMES.get(listing["Exchange"], "France"),
            "sector": sector_fr,
            "sector_en": sector_en,
            "sector_group": group or "industry",
            "region": REGION_BY_EXCHANGE.get(listing["Exchange"], "fr"),
            "initials": re.sub(r"[^A-Z0-9]", "", row["name"].upper())[:2] or code[:2],
            "logo_url": logo,
        })

    report(inserts, updates, skipped)
    missing_sector = [i["name"] for i in inserts if not i["sector"]]
    if missing_sector:
        print(f"sans secteur : {missing_sector}")
    return emit("Les sociétés du SBF 120.", inserts, updates)


def report(inserts: list[dict], updates: list, skipped: list) -> None:
    print(f"{len(inserts)} titres ajoutés · {len(updates)} logos complétés "
          f"· {len(skipped)} écartés")
    if skipped:
        print(f"écartés : {skipped}")
    with_logo = sum(1 for item in inserts if item["logo_url"])
    print(f"{with_logo}/{len(inserts)} nouveaux titres ont un logo")


def existing_listings() -> dict[str, str]:
    """`eodhd_symbol` -> symbole interne, tel qu'il est déjà en base.

    Relevé à la main pour rester hors ligne : le script ne se connecte pas
    à la base de production.
    """
    path = ROOT / "tools" / "existing_listings.json"
    return json.loads(path.read_text()) if path.exists() else {}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("index", choices=["sp500", "sbf120", "global"])
    parser.add_argument("--offline", action="store_true",
                        help="n'utilise que le cache réseau déjà téléchargé")
    args = parser.parse_args()

    if args.index == "sp500":
        sql = build_sp500(args.offline)
    elif args.index == "sbf120":
        sql = build_sbf120(args.offline, existing_listings())
    else:
        sql = build_global(args.offline, existing_listings())

    seed = ROOT / "supabase" / "seed" / f"{args.index}.sql"
    seed.parent.mkdir(parents=True, exist_ok=True)
    seed.write_text(sql + "\n")
    print(f"→ {seed.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
