#!/usr/bin/env python3
"""Génère le manuel de Stellar Sight (HTML mis en page, puis PDF).

    python3 docs/manuel/build.py            # manuel.html + manuel.pdf
    python3 docs/manuel/build.py --html     # seulement le HTML
    python3 docs/manuel/build.py --clair    # variante claire, économe en encre

Le texte vit dans chapitres/*.md, les tableaux viennent de data/*.json,
les images Midjourney de images/MJ-xx.(png|jpg|webp) (cadre pointillé tant
qu'elles manquent, voir prompts.json). Le PDF est imprimé par Chromium via
Playwright (node print.js) avec Paged.js pour la pagination.
Aucune dépendance Python hors bibliothèque standard.
"""
import datetime
import html
import json
import os
import re
import subprocess
import sys

ICI = os.path.dirname(os.path.abspath(__file__))
RACINE = os.path.normpath(os.path.join(ICI, "..", ".."))
DATA = os.path.join(RACINE, "data")

# --- Réglages d'édition --------------------------------------------------
EDITION = "1.3"
# Formes des encarts d'image : droit, arrondi, coupe, asym, arche, medaillon.
# Une ligne à changer pour tout le manuel.
FORMES = {"grande": "coupe", "portrait": "arche", "medaillon": "medaillon", "capture": "droit"}


def charger(nom):
    with open(os.path.join(DATA, nom), encoding="utf-8") as f:
        return json.load(f)


def esc(t):
    return html.escape(str(t), quote=True)


# --- Markdown minimal ------------------------------------------------------
def inline(t):
    t = esc(t)
    t = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", t)
    t = re.sub(r"(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?![\w*])", r"<em>\1</em>", t)
    t = re.sub(r"`(.+?)`", r"<code>\1</code>", t)
    t = re.sub(r"\[\[(.+?)\]\]", r'<span class="kbd">\1</span>', t)
    # espaces insécables avant la ponctuation haute française
    t = re.sub(r" ([:;!?»%])", "\u00a0\\1", t)
    t = re.sub(r"(«) ", "\\1\u00a0", t)
    return t


def markdown(texte):
    out, para, liste, table = [], [], None, []

    def flush():
        nonlocal para, liste, table
        if para:
            out.append("<p>" + inline(" ".join(para)) + "</p>")
            para = []
        if liste:
            tag, items = liste
            out.append(f"<{tag}>" + "".join(f"<li>{inline(i)}</li>" for i in items) + f"</{tag}>")
            liste = None
        if table:
            rows = [r for r in table if not re.match(r"^\|\s*:?-", r)]
            h = "<table class='grille'>"
            for i, r in enumerate(rows):
                cells = [c.strip() for c in r.strip().strip("|").split("|")]
                tag = "th" if i == 0 else "td"
                h += "<tr>" + "".join(f"<{tag}>{inline(c)}</{tag}>" for c in cells) + "</tr>"
            out.append(h + "</table>")
            table = []

    for ligne in texte.split("\n"):
        s = ligne.rstrip()
        if not s.strip():
            flush()
            continue
        if s.startswith("<"):
            flush()
            out.append(s)
            continue
        m = re.match(r"^(#{2,4}) (.+)$", s)
        if m:
            flush()
            n = len(m.group(1))
            out.append(f"<h{n}>{inline(m.group(2))}</h{n}>")
            continue
        if s.startswith("|"):
            if para or liste:
                flush()
            table.append(s)
            continue
        m = re.match(r"^(- |\d+\. )(.+)$", s)
        if m:
            tag = "ul" if m.group(1) == "- " else "ol"
            if para or table:
                flush()
            if liste and liste[0] != tag:
                flush()
            if not liste:
                liste = (tag, [])
            liste[1].append(m.group(2))
            continue
        if liste and ligne.startswith("  "):
            liste[1][-1] += " " + s.strip()
            continue
        para.append(s.strip())
    flush()
    return "\n".join(out)


# --- Encarts d'image Midjourney -------------------------------------------
PROMPTS = {p["id"]: p for p in json.load(open(os.path.join(ICI, "prompts.json"), encoding="utf-8"))["encarts"]}
UTILISES = []


def image_mj(ident, extra=""):
    p = PROMPTS[ident]
    if ident not in UTILISES:
        UTILISES.append(ident)
    forme = FORMES.get(p.get("forme", "grande"), p.get("forme", "grande"))
    fichier = None
    for ext in ("png", "jpg", "jpeg", "webp"):
        if os.path.exists(os.path.join(ICI, "images", f"{ident}.{ext}")):
            fichier = f"images/{ident}.{ext}"
            break
    ratio = p["format"].replace(":", " / ")
    style = f"aspect-ratio:{ratio};"
    if fichier:
        dedans = f'<img src="{fichier}" alt="{esc(p["titre"])}">'
    else:
        dedans = (f'<div class="vide"><b>Encart {ident}</b><span>{esc(p["titre"])} · {p["format"]}</span>'
                  f'<i>{esc(p["sujet"])}</i></div>')
    return (f'<figure class="mj forme-{forme} {p.get("classe", "")} {extra}" style="{style}">'
            f'<div class="cadre">{dedans}</div></figure>')


# --- Captures du jeu annotées ----------------------------------------------
def capture(fichier, legende, pins):
    h = f'<figure class="capture forme-{FORMES["capture"]}"><div class="cadre"><img src="../../{fichier}" alt="">'
    for n, x, y, _ in pins:
        h += f'<span class="pin" style="left:{x}%;top:{y}%">{n}</span>'
    h += "</div>"
    if legende:
        h += f'<figcaption>{inline(legende)}</figcaption>'
    if pins:
        h += "<ol class='pins'>" + "".join(f"<li value='{n}'>{inline(t)}</li>" for n, _, _, t in pins) + "</ol>"
    return h + "</figure>"


# --- Blocs ::: ---------------------------------------------------------------
def bloc(nom, arg, corps):
    if nom == "chronique":
        return (f'<aside class="chronique"><div class="lbl">Fragment · {inline(arg.split("|")[0])}</div>'
                f'{markdown(corps)}<div class="sig">{inline(arg.split("|")[1]) if "|" in arg else ""}</div></aside>')
    if nom == "transmission":
        return (f'<aside class="transmission"><div class="lbl">Transmission interceptée · {inline(arg)}</div>'
                f'{markdown(corps)}</aside>')
    if nom == "marge":
        return f'<aside class="marge">{markdown(corps)}<div class="sig">— Cdt. A. Varrek</div></aside>'
    if nom == "conseil":
        return f'<aside class="conseil"><div class="lbl">Conseil</div>{markdown(corps)}</aside>'
    if nom == "attention":
        return f'<aside class="attention"><div class="lbl">{inline(arg or "Attention")}</div>{markdown(corps)}</aside>'
    if nom == "encadre":
        return f'<aside class="encadre"><div class="lbl">{inline(arg)}</div>{markdown(corps)}</aside>'
    if nom == "image":
        parts = arg.split()
        return image_mj(parts[0], " ".join(parts[1:]))
    if nom == "capture":
        f, _, leg = arg.partition("|")
        pins = []
        for l in corps.strip().split("\n"):
            m = re.match(r"^(\d+)\s+([\d.]+)\s+([\d.]+)\s+(.+)$", l.strip())
            if m:
                pins.append((m.group(1), m.group(2), m.group(3), m.group(4)))
        return capture(f.strip(), leg.strip(), pins)
    if nom == "colonnes":
        return f'<div class="colonnes">{markdown(corps)}</div>'
    raise ValueError(f"bloc inconnu : {nom}")


def rendre(texte):
    # Le HTML produit par les générateurs et les blocs est mis de côté pendant
    # le passage du mini-markdown, puis remis en place tel quel.
    reserve = []

    def garde(html):
        reserve.append(html)
        return f"\n@@HTML{len(reserve) - 1}@@\n"
    # 1. générateurs {{nom}}
    texte = re.sub(r"^\{\{(\w+)\}\}$", lambda m: garde(GENERATEURS[m.group(1)]()), texte, flags=re.M)
    # 2. blocs ::: (non imbriqués)
    texte = re.sub(r"^::: (\w+)(.*?)\n(.*?)^:::$",
                   lambda m: garde(bloc(m.group(1), m.group(2).strip(), m.group(3))), texte, flags=re.M | re.S)
    texte = texte.replace("\n---saut---\n", '\n<div class="saut"></div>\n')
    html = markdown(texte)
    for i, morceau in enumerate(reserve):
        html = html.replace(f"<p>@@HTML{i}@@</p>", morceau).replace(f"@@HTML{i}@@", morceau)
    return html


# --- Générateurs depuis les données du jeu ---------------------------------
def gen_ressources():
    r = charger("rules.json")
    lignes = "".join(f"<tr><td>{esc(x['label'])}</td><td class='court'>{esc(x['short'])}</td>"
                     f"<td>{esc(r['start_resources'].get(x['id'], '—'))}</td></tr>" for x in r["resources"])
    return f"<table class='grille'><tr><th>Ressource</th><th>Abrégé</th><th>Stock de départ</th></tr>{lignes}</table>"


FX_TEXTE = {"influence": "influence", "food": "nourriture", "energy": "énergie", "materials": "matériaux",
            "knowledge": "Savoir", "all": "toute production"}


def texte_fx(fx):
    out = []
    for k, v in fx.items():
        if k == "production_pct":
            out += [f"+{n} % {FX_TEXTE.get(r, r)}" for r, n in v.items()]
        else:
            out.append({"growth_pct": f"+{v} % croissance", "building_cost_pct": f"{v} % coût des bâtiments",
                        "ship_days_pct": f"{v} % temps de construction des vaisseaux",
                        "damage_pct": f"+{v} % dégâts", "upkeep_pct": f"{v} % entretien"}.get(k, k))
    return ", ".join(out)


def gen_luxes():
    g = charger("goods.json")
    paliers = {t["id"]: t for t in g["tiers"]}
    lignes = "".join(f"<tr><td>{esc(x['label'])}</td><td>{esc(paliers[x['tier']]['label'])}</td>"
                     f"<td>+{paliers[x['tier']]['stability']}</td><td>{esc(texte_fx(x['fx']))}</td></tr>"
                     for x in g["luxuries"])
    return (f"<table class='grille'><tr><th>Luxe</th><th>Palier</th><th>Stabilité</th><th>Effet</th></tr>"
            f"{lignes}</table>")


def gen_strategiques():
    g = charger("goods.json")
    lignes = "".join(f"<tr><td>{esc(x['label'])}</td><td>{x['era']}</td><td>{x['price']}</td>"
                     f"<td>{inline(x['text'])}</td></tr>" for x in g["strategic"])
    return (f"<table class='grille'><tr><th>Stratégique</th><th>Ère</th><th>Prix</th><th>Description</th></tr>"
            f"{lignes}</table>")


def gen_stabilite():
    s = charger("stability.json")
    lignes = "".join(f"<tr><td><span class='pastille' style='background:{t['color']}'></span>{esc(t['label'])}</td>"
                     f"<td>{t['min']}+</td><td>{esc(t['text'])}</td></tr>" for t in s["tiers"])
    return f"<table class='grille'><tr><th>Palier</th><th>Dès</th><th>Effet</th></tr>{lignes}</table>"


def gen_courants():
    p = charger("politics.json")
    lignes = "".join(f"<tr><td><span class='pastille' style='background:{c['color']}'></span>{esc(c['short'])}</td>"
                     f"<td>{esc(c['text'])}</td><td>{esc(c.get('acts', ''))}</td></tr>" for c in p["currents"])
    return (f"<table class='grille'><tr><th>Courant</th><th>Ce qu'il veut</th><th>Ce qui le nourrit</th></tr>"
            f"{lignes}</table>")


def gen_faune():
    c = charger("creatures.json")
    h = "<div class='fiches'>"
    noms = {"passive": "Paisible", "territorial": "Territoriale", "predator": "Prédatrice"}
    for k, s in c["species"].items():
        h += (f"<div class='fiche'><div class='fiche-t'>{esc(s['label'])}<span>{noms.get(s.get('temper'), '')}</span></div>"
              f"<p>{inline(s['text'])}</p><p class='faible'><b>Point faible</b> {inline(s['weakness'])}</p></div>")
    return h + "</div>"


def gen_gardiens():
    g = charger("guardians.json")
    h = "<div class='fiches'>"
    for s in g["guardians"]:
        h += (f"<div class='fiche'><div class='fiche-t'>{esc(s['name'])}<span>{esc(s.get('where', ''))}</span></div>"
              f"<p>{inline(s['text'])}</p><p class='faible'><b>Particularité</b> {inline(s.get('trait', ''))}</p></div>")
    return h + "</div>"


def gen_technologies():
    t = charger("technologies.json")
    techs = t["technologies"]
    nb = len(techs) if not isinstance(techs, dict) else len(techs)
    doms = t["domains"]
    dom_l = [d.get("label", d.get("id")) if isinstance(d, dict) else str(d) for d in (doms if isinstance(doms, list) else doms.values())]
    return (f"<p class='donnee'>L'arbre compte actuellement <strong>{nb} technologies</strong> réparties en "
            f"{len(dom_l)} domaines ({esc(', '.join(dom_l))}) sur cinq ères.</p>")


PEUPLES_EXTRA = json.load(open(os.path.join(ICI, "peuples.json"), encoding="utf-8"))
REGISTRE_COULEUR = {
    "Grimdark": "#c0392b", "Médiéval spatial": "#d8b46a", "Space opera héroïque": "#4fa3e0",
    "Horreur biologique": "#7cc46a", "Classique / hard SF": "#7fd3e6", "Picaresque / pulp": "#e0884a",
    "Cosmique / étrange": "#a98be0",
}
NOMS_COUCHE = {
    "humanoide": "Humanoïde", "ruche": "Ruche", "synthetique": "Synthétique", "reptilien": "Reptilien",
    "energetique": "Énergétique", "lithoide": "Lithoïde", "feodalite": "Féodalité", "theocratie": "Théocratie",
    "republique": "République", "conscience": "Conscience distribuée", "horde": "Horde", "syndicat": "Syndicat",
    "honneur": "Honneur", "foi": "Foi", "raison": "Raison", "survie": "Survie", "profit": "Profit",
}
BIOMES = {"arctic": "Glaciaire", "desert": "Désert", "ocean": "Océan", "jungle": "Jungle", "toxic": "Toxique",
          "barren": "Stérile", "terran": "Tempéré", "tundra": "Toundra", "gas": "Géante gazeuse", "volcanic": "Volcanique",
          "arid": "Aride", "continental": "Continental", "savanna": "Savane", "tropical": "Tropical", "glacial": "Glaciaire"}


def gen_peuples():
    h = ""
    for f in charger("factions.json"):
        x = PEUPLES_EXTRA.get(f["id"], {})
        sp = f.get("species", {})
        reg = f.get("registre", "")
        coul = REGISTRE_COULEUR.get(reg, "#d8b46a")
        traits = "".join(f"<div class='trait'><b>{esc(t['name'])}</b> {inline(t['text'])}</div>" for t in f.get("traits", []))
        lore = f.get("lore", "")
        donnees = [
            ("Registre", reg),
            ("Archétype", NOMS_COUCHE.get(sp.get("archetype"), sp.get("archetype", "—"))),
            ("Gouvernement", NOMS_COUCHE.get(sp.get("gouvernement"), sp.get("gouvernement", "—"))),
            ("Credo", NOMS_COUCHE.get(sp.get("credo"), sp.get("credo", "—"))),
            ("Mondes préférés", ", ".join(BIOMES.get(b, b) for b in f.get("preferred", [])) or "—"),
            ("Recherche", f.get("research", {}).get("name", "—")),
            ("Tempérament IA", f.get("ai", {}).get("temperament", {}).get("label", "—")),
            ("Prise en main", x.get("difficulte", "—")),
        ]
        grille = "".join(f"<div class='row'><div class='k'>{esc(k)}</div><div class='v'>{esc(v)}</div></div>" for k, v in donnees)
        victoire = x.get("victoire", "")
        h += f"""
<section class="peuple" style="--accent:{coul}">
  <div class="peuple-tete">
    <div class="reg">Registre {esc(reg)} · {esc(NOMS_COUCHE.get(sp.get('gouvernement'), ''))} · Credo {esc(NOMS_COUCHE.get(sp.get('credo'), ''))}</div>
    <h3 class="peuple-nom">{esc(f['name'])}</h3>
    <div class="devise">« {esc(x.get('devise', ''))} »</div>
  </div>
  <div class="peuple-grille">
    <div class="peuple-texte">
      <p class="lettrine">{inline(lore)}</p>
      {markdown(x.get('histoire', ''))}
    </div>
    <div class="peuple-cote">
      {image_mj(x['portrait']) if x.get('portrait') else ''}
      <div class="data">{grille}</div>
    </div>
  </div>
  <div class="boxtitle">Traits du peuple</div>
  <div class="traits">{traits}</div>
  {f'<div class="boxtitle">Victoire de peuple</div><p class="victoire-peuple">{inline(victoire)}</p>' if victoire else ''}
  {bloc('chronique', x['chronique_source'], x['chronique']) if x.get('chronique') else ''}
  {bloc('conseil', '', x['conseil']) if x.get('conseil') else ''}
</section>"""
    return h


def gen_prompts():
    h = ""
    for ident in sorted(PROMPTS):
        p = PROMPTS[ident]
        h += (f"<div class='prompt'><div class='prompt-t'><b>{ident}</b> {esc(p['titre'])}"
              f"<span>{p['format']} · {esc(p['emplacement'])}</span></div>"
              f"<p class='prompt-en'>{esc(p['prompt'])} {esc(STYLE_MJ)} --ar {p['format']}</p></div>")
    return h


STYLE_MJ = json.load(open(os.path.join(ICI, "prompts.json"), encoding="utf-8"))["style_commun"]

GENERATEURS = {
    "ressources": gen_ressources, "stabilite": gen_stabilite, "courants": gen_courants,
    "faune": gen_faune, "gardiens": gen_gardiens, "technologies": gen_technologies,
    "peuples": gen_peuples, "prompts": gen_prompts,
    "luxes": gen_luxes, "strategiques": gen_strategiques,
}


# --- Chapitres ---------------------------------------------------------------
def lire_chapitre(chemin):
    with open(chemin, encoding="utf-8") as f:
        brut = f.read()
    meta = {}
    m = re.match(r"^---\n(.*?)\n---\n", brut, re.S)
    if m:
        for l in m.group(1).split("\n"):
            k, _, v = l.partition(":")
            meta[k.strip()] = v.strip()
        brut = brut[m.end():]
    return meta, brut


def commit_courant():
    try:
        return subprocess.check_output(["git", "-C", RACINE, "rev-parse", "--short", "HEAD"], text=True).strip()
    except Exception:
        return "?"


def construire(clair=False):
    fichiers = sorted(f for f in os.listdir(os.path.join(ICI, "chapitres")) if f.endswith(".md"))
    corps, toc = [], []
    for nom in fichiers:
        meta, brut = lire_chapitre(os.path.join(ICI, "chapitres", nom))
        ident = "s-" + re.sub(r"\W", "-", nom[:-3])
        typ = meta.get("type", "chapitre")
        if typ == "brut":
            corps.append(rendre(brut))
            continue
        if typ == "partie":
            toc.append(("partie", ident, meta["titre"], meta.get("numero", "")))
            corps.append(f"""
<section class="partie" id="{ident}">
  <div class="partie-fond">{image_mj(meta['image'], 'plein') if meta.get('image') else ''}</div>
  <div class="partie-texte">
    <div class="kicker">Partie {esc(meta.get('numero', ''))}</div>
    <h1 class="partie-titre" data-partie="{esc(meta['titre'])}">{esc(meta['titre'])}</h1>
    <div class="rule"></div>
    <div class="partie-intro">{rendre(brut)}</div>
  </div>
</section>""")
            continue
        toc.append(("chapitre", ident, meta["titre"], meta.get("numero", "")))
        epi = ""
        if meta.get("epigraphe"):
            epi = (f'<blockquote class="epigraphe"><p>{inline(meta["epigraphe"])}</p>'
                   f'<cite>{inline(meta.get("signature", ""))}</cite></blockquote>')
        img = image_mj(meta["image"], "bandeau") if meta.get("image") else ""
        num = f'<div class="chap-num">{esc(meta.get("etiquette", "Chapitre"))} {esc(meta["numero"])}</div>' if meta.get("numero") else ""
        corps.append(f"""
<section class="chapitre" id="{ident}">
  <header class="chap-tete">
    {img}
    {num}
    <h2 class="chap-titre">{esc(meta['titre'])}</h2>
    {epi}
  </header>
  <div class="chap-corps">{rendre(brut)}</div>
</section>""")

    toc_html = ""
    for typ, ident, titre, num in toc:
        if typ == "partie":
            toc_html += f'<li class="toc-partie"><a href="#{ident}"><span>{esc(num)} · {esc(titre)}</span></a></li>'
        else:
            toc_html += (f'<li class="toc-chap"><a href="#{ident}"><span class="n">{esc(num)}</span>'
                         f'<span class="t">{esc(titre)}</span></a></li>')

    date = datetime.date.today()
    mois = ["janvier", "février", "mars", "avril", "mai", "juin", "juillet", "août", "septembre", "octobre", "novembre", "décembre"][date.month - 1]
    gabarit = open(os.path.join(ICI, "gabarit.html"), encoding="utf-8").read()
    page = (gabarit.replace("{{CSS}}", "{{CSS}}").replace("{{CORPS}}", "\n".join(corps))
            .replace("{{SOMMAIRE}}", toc_html)
            .replace("{{EDITION}}", EDITION)
            .replace("{{DATE}}", f"{mois} {date.year}")
            .replace("{{COMMIT}}", commit_courant())
            .replace("{{COUVERTURE}}", image_mj("MJ-01", "plein"))
            .replace("{{CLASSE}}", "clair" if clair else "")
            .replace("{{FOND}}", "#f4f0e6" if clair else "#0a0f1c")
            .replace("{{CSS}}", open(os.path.join(ICI, "style.css"), encoding="utf-8").read()))
    sortie = os.path.join(ICI, "manuel.html")
    with open(sortie, "w", encoding="utf-8") as f:
        f.write(page)
    manquants = [i for i in UTILISES if not any(os.path.exists(os.path.join(ICI, "images", f"{i}.{e}")) for e in ("png", "jpg", "jpeg", "webp"))]
    print(f"manuel.html écrit ({len(UTILISES)} encarts, {len(manquants)} images encore à générer)")
    return sortie


def ecrire_prompts_md():
    lignes = ["# Encarts Midjourney du manuel", "",
              "Déposer chaque image dans `docs/manuel/images/` sous le nom de son identifiant (`MJ-07.png`),",
              "puis relancer `python3 docs/manuel/build.py` : le cadre pointillé est remplacé par l'image.", "",
              f"Bloc de style commun, déjà ajouté à chaque prompt : `{STYLE_MJ}`", ""]
    for ident in sorted(PROMPTS):
        p = PROMPTS[ident]
        lignes += [f"## {ident} · {p['titre']}", "",
                   f"- Format : {p['format']} · Forme du cadre : {FORMES.get(p.get('forme', 'grande'), p.get('forme'))}",
                   f"- Emplacement : {p['emplacement']}", f"- Sujet : {p['sujet']}", "",
                   "```", f"{p['prompt']} {STYLE_MJ} --ar {p['format']}", "```", ""]
    with open(os.path.join(ICI, "PROMPTS-MIDJOURNEY.md"), "w", encoding="utf-8") as f:
        f.write("\n".join(lignes))


if __name__ == "__main__":
    clair = "--clair" in sys.argv
    sortie = construire(clair)
    ecrire_prompts_md()
    if "--html" not in sys.argv:
        pdf = os.path.join(ICI, "manuel-clair.pdf" if clair else "manuel.pdf")
        subprocess.check_call(["node", os.path.join(ICI, "print.js"), sortie, pdf])
        print("PDF :", pdf)
