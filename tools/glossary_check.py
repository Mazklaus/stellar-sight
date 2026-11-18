#!/usr/bin/env python3
"""Mots en gras du manuel qui n'ont pas d'article dans le glossaire (prop. 39 du glossaire en jeu).

    python3 tools/glossary_check.py            # liste, du plus fréquent au plus rare
    python3 tools/glossary_check.py --min 3    # seulement ceux qui reviennent 3 fois ou plus

Chaque nouveau pilier ajoute ses termes à data/glossary.json (prop. 40), puis relance
docs/manuel/build.py --codex. Ce relevé aide à repérer les oublis ; tout mot en gras n'a pas
vocation à devenir un terme (titres, mises en valeur ponctuelles).
"""
import collections
import json
import os
import re
import sys

ICI = os.path.dirname(os.path.abspath(__file__))
RACINE = os.path.dirname(ICI)


def main() -> None:
    mini = 1
    if "--min" in sys.argv:
        mini = int(sys.argv[sys.argv.index("--min") + 1])
    with open(os.path.join(RACINE, "data", "glossary.json"), encoding="utf-8") as f:
        glo = json.load(f)
    formes = set()
    for t in glo["terms"]:
        for fm in t.get("forms", []) + [t["name"]]:
            formes.add(fm.lower())
    vus = collections.Counter()
    ou = collections.defaultdict(set)
    dossier = os.path.join(RACINE, "docs", "manuel", "chapitres")
    for nom in sorted(os.listdir(dossier)):
        if not nom.endswith(".md"):
            continue
        with open(os.path.join(dossier, nom), encoding="utf-8") as f:
            texte = f.read()
        for m in re.finditer(r"\*\*([^*]{2,60})\*\*", texte):
            mot = m.group(1).strip()
            bas = mot.lower()
            if bas in formes or bas.rstrip("sx") in formes:
                continue
            vus[mot] += 1
            ou[mot].add(nom[:-3])
    for mot, n in vus.most_common():
        if n < mini:
            break
        print(f"{n:3d}  {mot}  ({', '.join(sorted(ou[mot])[:4])})")
    print(f"\n{sum(1 for n in vus.values() if n >= mini)} mots en gras sans article.", file=sys.stderr)


if __name__ == "__main__":
    main()
