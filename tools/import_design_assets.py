#!/usr/bin/env python3
"""Importe les logos du projet Claude Design dans `Assets.xcassets`.

Les logos vivent dans le projet Design (`assets/*.png`), en très haute
définition — jusqu'à 3840×3072 pour une pastille affichée à 40 pt. Les
embarquer tels quels gonflerait l'app de plusieurs mégaoctets pour un rendu
identique : ce script les réduit et les décline en @1x/@2x/@3x.

    python3 tools/import_design_assets.py <dossier-source>

Le dossier source contient les fichiers exportés depuis claude.ai/design. La
correspondance entre le nom de fichier du design et la valeur `logo_asset` du
seed `securities.sql` est explicite ci-dessous : le design nomme « Capgemini.png »
là où la base dit « capgemini », et rien ne permet de deviner l'un depuis l'autre.
"""

import json
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
CATALOG = ROOT / "Krezus" / "Resources" / "Assets.xcassets"

# Taille de la pastille : 40 pt dans `KrzSecurityBadge`, donc 120 px en @3x.
BASE_POINTS = 40

# logo_asset (securities.sql) -> nom du fichier dans le projet Design.
LOGOS = {
    "accor": "accor.png",
    "airbus": "airbus.png",
    "arcellor": "arcellor.png",
    "axa": "axa.png",
    "bnp": "bnp.svg",
    "bouygues": "bouygues.png",
    "bureauveritas": "bureauveritas.png",
    "capgemini": "Capgemini.png",
    "carrefour": "carrefour.png",
    "danone": "danone.png",
    "dassault": "dassault.png",
    "eiffage": "eiffage.png",
    "engie": "engie.png",
    "essilor": "essilor.webp",
    "eurofins": "eurofins.png",
    "euronext": "euronext.png",
    "hermes": "Hermes.png",
    "kering": "kering.png",
    "legrand": "legrand.png",
    "logo-airliquide": "logo-airliquide.png",
    "logo-nvidia": "logo-nvidia.png",
    "loreal": "l'oreal.png",
    "lvmh": "lvmh.png",
    "michelin": "Michelin.png",
    "orange": "Orange.png",
    "pernodricard": "Pernod Ricard.png",
    "publicis": "Publicis.png",
    "renault": "renault.png",
    "safran": "safran.png",
    "saintgobain": "SaintGobain.png",
    "sanofi": "Sanofi.png",
    "schneider": "Schneider.png",
    "societegenerale": "SocieteGenerale.png",
    "stellantis": "Stellantis.png",
    "stmicro": "StMicro.png",
    "thales": "thales.png",
    "total": "total.png",
    "unibail": "Unibail.png",
    "veolia": "Veolia.png",
    "vinci": "Vinci.png",
}


def imageset(name: str, source: pathlib.Path) -> bool:
    """Crée `<name>.imageset` avec ses trois échelles. Faux si la source manque."""
    if not source.exists():
        return False

    directory = CATALOG / f"{name}.imageset"
    directory.mkdir(parents=True, exist_ok=True)

    images = []
    for scale in (1, 2, 3):
        filename = f"{name}@{scale}x.png" if scale > 1 else f"{name}.png"
        target = directory / filename
        subprocess.run(
            ["sips", "-Z", str(BASE_POINTS * scale), str(source),
             "--out", str(target)],
            check=True, capture_output=True,
        )
        images.append({"idiom": "universal", "filename": filename,
                       "scale": f"{scale}x"})

    (directory / "Contents.json").write_text(
        json.dumps({"images": images,
                    "info": {"author": "xcode", "version": 1}}, indent=2) + "\n",
        encoding="utf-8",
    )
    return True


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 2

    source_dir = pathlib.Path(sys.argv[1]).expanduser()
    if not source_dir.is_dir():
        print(f"Dossier introuvable : {source_dir}")
        return 2

    written, missing = [], []
    for name, filename in sorted(LOGOS.items()):
        if imageset(name, source_dir / filename):
            written.append(name)
        else:
            missing.append(f"{name} ({filename})")

    print(f"{len(written)} logos importés sur {len(LOGOS)}")
    if missing:
        print("\nManquants — à exporter depuis claude.ai/design :")
        for entry in missing:
            print(f"  {entry}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
