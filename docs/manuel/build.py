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
EDITION = "2.42"
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


def _signe(v):
    return f"+{v}" if v > 0 else f"{v}"


def texte_fx_relique(fx):
    out = []
    for k, v in fx.items():
        if k == "production_pct":
            out += [f"{FX_TEXTE.get(r, r).capitalize()} {_signe(n)} %" for r, n in v.items()]
        elif k == "defense_pct":
            noms = {"armor": "blindage", "shield": "boucliers", "pd": "défense ponctuelle"}
            out += [f"{noms.get(r, r).capitalize()} {_signe(n)} %" for r, n in v.items()]
        elif k == "hab_bonus":
            out.append(f"Habitabilité {_signe(list(v.values())[0])} %")
        else:
            lib = {"stability": ("Stabilité", ""), "growth_pct": ("Croissance", " %"), "damage_pct": ("Dégâts", " %"),
                   "garrison_pct": ("Garnisons", " %"), "fleet_speed_pct": ("Vitesse des flottes", " %"),
                   "repair_pct": ("Réparations", " %"), "troops_pct": ("Troupes", " %"),
                   "upkeep_pct": ("Entretien", " %"), "building_cost_pct": ("Coût des bâtiments", " %"),
                   "ship_cost_pct": ("Coût des vaisseaux", " %"), "ship_days_pct": ("Temps de construction", " %"),
                   "trade_income_pct": ("Routes commerciales", " %"), "opinion_all": ("Opinion de tous", ""),
                   "council_seats": ("Sièges au conseil", ""), "curio_power": ("Puissance d'expédition", ""),
                   "curio_detect": ("Curiosités repérées de plus loin", ""), "claim_vision": ("Vision autour des revendications", "")}
            nom, unite = lib.get(k, (k, ""))
            out.append(f"{nom} {_signe(v)}{unite}" if isinstance(v, (int, float)) and not isinstance(v, bool) else nom)
    return ", ".join(out)


def gen_reliques():
    r = charger("relics.json")
    lignes = ""
    for x in sorted(r["relics"], key=lambda x: x["name"]):
        t = x.get("triumph", {})
        tri = esc(t.get("label", ""))
        fx_t = texte_fx_relique(t.get("fx", {}))
        lignes += (f"<tr><td><b>{esc(x['name'])}</b><br><i>{inline(x.get('text', ''))}</i></td>"
                   f"<td>{esc(texte_fx_relique(x.get('fx', {})) or '—')}</td>"
                   f"<td>{tri}{(' : ' + esc(fx_t)) if fx_t else ''} ({t.get('cost', '?')} influence)</td></tr>")
    return (f"<table class='grille reliques'><tr><th>Relique</th><th>Effet permanent</th><th>Triomphe</th></tr>"
            f"{lignes}</table>")


def gen_lois():
    p = charger("politics.json")
    courants = {c["id"]: c for c in p["currents"]}
    lignes = ""
    for cid, bloc_l in p["laws"].items():
        c = courants.get(cid, {"short": cid, "color": "#888"})
        tete = f"<span class='pastille' style='background:{c['color']}'></span>{esc(c['short'])}"
        pw = bloc_l["power"]
        lignes += f"<tr><td>{tete}</td><td>Pouvoir</td><td><b>{esc(pw['label'])}</b> {inline(pw['text'])}</td></tr>"
        for l in bloc_l["laws"]:
            lignes += f"<tr><td></td><td>{l['level']}</td><td><b>{esc(l['label'])}</b> {inline(l['text'])}</td></tr>"
    for l in p["independent_laws"]:
        lignes += f"<tr><td>Indépendante</td><td>—</td><td><b>{esc(l['label'])}</b> {inline(l['text'])}</td></tr>"
    return (f"<table class='grille lois'><tr><th>Courant</th><th>Niveau</th><th>Loi</th></tr>{lignes}</table>")


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
    "plaisir": "Plaisir",
}
BIOMES = {"arctic": "Glaciaire", "desert": "Désert", "ocean": "Océan", "jungle": "Jungle", "toxic": "Toxique",
          "barren": "Stérile", "terran": "Tempéré", "tundra": "Toundra", "gas": "Géante gazeuse", "volcanic": "Volcanique",
          "arid": "Aride", "continental": "Continental", "savanna": "Savane", "tropical": "Tropical", "glacial": "Glaciaire"}


# --- Talents de chaque peuple, lus dans les données (couches d'espèce) -------
def _couches(f):
    sp = f.get("species", {})
    return {"archetype": sp.get("archetype", ""), "gouvernement": sp.get("gouvernement", ""),
            "credo": sp.get("credo", ""), "registre": f.get("registre", ""), "traits": sp.get("traits", [])}


def _exige(c, req):
    for couche, voulu in (req or {}).items():
        voulu = voulu if isinstance(voulu, list) else [voulu]
        val = c.get(couche, "")
        if couche == "traits":
            if not any(t in voulu for t in val):
                return False
        elif val not in voulu:
            return False
    return True


def _par_couche(c, bloc_t):
    """Talents rangés par couche : {couche: {valeur: {label, text, requires?}}}."""
    out = []
    for couche, valeurs in bloc_t.items():
        if couche.startswith("_") or not isinstance(valeurs, dict):
            continue
        for val, t in valeurs.items():
            if not isinstance(t, dict) or "label" not in t:
                continue
            ok = (val in c["traits"]) if couche == "traits" else (c.get(couche) == val)
            if ok and _exige(c, t.get("requires")):
                out.append(t)
    return out


def talents_du_peuple(f):
    c = _couches(f)
    res = []

    def ajoute(cat, liste):
        for t in liste:
            lab = re.sub(r"^[^:]+ : ", "", t["label"]) if cat == "Peuples mêlés" else t["label"]
            lab = lab[:1].upper() + lab[1:]
            res.append((cat, lab, t.get("text", "")))
    ajoute("Diplomatie", [t for t in charger("diplomacy.json")["abilities"].values()
                          if isinstance(t, dict) and _exige(c, t.get("requires"))])
    ajoute("Commerce", _par_couche(c, charger("trade.json").get("talents", {})))
    ajoute("Stabilité", _par_couche(c, charger("stability.json").get("talents", {})))
    ajoute("Peuples mêlés", _par_couche(c, charger("rules.json")["movements"].get("talents", {})))
    ajoute("Héros", _par_couche(c, charger("heroes.json").get("talents", {})))
    ajoute("Ombres", _par_couche(c, charger("espionage.json").get("talents", {})))
    foi = charger("faiths.json").get("bridges", {}).get("talents", {}).get(f["id"])
    ajoute("Foi", [foi] if isinstance(foi, dict) else [])
    ajoute("Amphictyonie", [t for t in charger("amphictyony.json").get("talents", []) if _exige(c, t.get("requires"))])
    ajoute("Suzerain", _par_couche(c, charger("vassals.json").get("talents", {})))
    ajoute("Pirates", _par_couche(c, charger("pirates.json").get("talents", {})))
    ajoute("Créatures", _par_couche(c, charger("creatures.json").get("talents", {})))
    ajoute("Logistique", _par_couche(c, charger("logistics.json").get("talents", {})))
    ajoute("Administration", _par_couche(c, charger("administration.json").get("talents", {})))
    ajoute("Trésor", _par_couche(c, charger("finance.json").get("talents", {})))
    ajoute("Économie privée", _par_couche(c, charger("private.json").get("talents", {})))
    ajoute("Spatioports", _par_couche(c, charger("ports.json").get("talents", {})))
    ajoute("Portails", _par_couche(c, charger("portals.json").get("talents", {})))
    ajoute("Génome", _par_couche(c, charger("genetics.json").get("talents", {})))
    ajoute("Songe", _par_couche(c, charger("psionics.json").get("talents", {})))
    tr = charger("transcendence.json").get("talents", {}).get(f["id"])
    ajoute("Transcendance", [tr] if isinstance(tr, dict) else [])
    mg = charger("megastructures.json").get("talents", {}).get(f["id"])
    ajoute("Mégastructures", [mg] if isinstance(mg, dict) else [])
    ct = charger("contact.json").get("talents", {}).get(f["id"])
    ajoute("Contact", [ct] if isinstance(ct, dict) else [])
    wf = charger("worldforge.json").get("talents", {}).get(f["id"])
    ajoute("Forge des mondes", [wf] if isinstance(wf, dict) else [])
    lw = charger("livingworlds.json").get("talents", {}).get(f["id"])
    ajoute("Mondes vivants", [lw] if isinstance(lw, dict) else [])
    cu = charger("culture.json").get("talents", {})
    peuple = cu.get("peoples", {}).get(f["id"])
    ajoute("Rayonnement", _par_couche(c, {k: v for k, v in cu.items() if k != "peoples"}) + ([peuple] if isinstance(peuple, dict) else []))
    return res


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
  <div class="boxtitle">Talents à travers la galaxie</div>
  <div class="talents-peuple">{''.join(f"<div class='tp'><span class='tp-cat'>{esc(cat)}</span><b>{esc(lab)}</b> {inline(txt)}</div>" for cat, lab, txt in talents_du_peuple(f))}</div>
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

def gen_logistique():
    """Talents de logistique par couche d'espèce (data/logistics.json)."""
    noms = {"traits": "Trait", "archetype": "Archétype", "gouvernement": "Gouvernement",
            "credo": "Credo", "registre": "Registre"}
    lignes = ""
    for couche, valeurs in charger("logistics.json").get("talents", {}).items():
        if couche.startswith("_") or not isinstance(valeurs, dict):
            continue
        for val, t in valeurs.items():
            nom = val if couche == "registre" else NOMS_COUCHE.get(val, val.capitalize())
            lignes += (f"<tr><td>{esc(noms.get(couche, couche))} {esc(nom)}</td><td><b>{esc(t['label'])}</b></td>"
                       f"<td>{inline(t['text'])}</td></tr>")
    return (f"<table class='grille'><tr><th>Couche</th><th>Talent</th><th>Effet</th></tr>{lignes}</table>")


def gen_terrains():
    """Catalogue des terrains et des tempêtes (data/terrain.json)."""
    familles = {"star": "Étoile", "zone": "Zone", "dynamic": "Né des batailles", "storm": "Tempête"}
    lignes = ""
    for tid, t in charger("terrain.json").get("terrains", {}).items():
        if tid.startswith("_"):
            continue
        lignes += (f"<tr><td><b>{esc(t['label'])}</b><br><small>{esc(familles.get(t.get('family', ''), ''))}</small></td>"
                   f"<td>{inline(t.get('bad', ''))}</td><td>{inline(t.get('good', ''))}</td></tr>")
    return (f"<table class='grille'><tr><th>Terrain</th><th>Inconvénient</th><th>Avantage</th></tr>{lignes}</table>")


def gen_terrain_talents():
    """Talents de terrain par couche d'espèce (data/terrain.json)."""
    noms = {"traits": "Trait", "archetype": "Archétype", "gouvernement": "Gouvernement",
            "credo": "Credo", "registre": "Registre"}
    lignes = ""
    for couche, valeurs in charger("terrain.json").get("talents", {}).items():
        if couche.startswith("_") or not isinstance(valeurs, dict):
            continue
        for val, t in valeurs.items():
            nom = val if couche == "registre" else NOMS_COUCHE.get(val, val.replace("_", " ").capitalize())
            lignes += (f"<tr><td>{esc(noms.get(couche, couche))} {esc(nom)}</td><td><b>{esc(t['label'])}</b></td>"
                       f"<td>{inline(t['text'])}</td></tr>")
    return (f"<table class='grille'><tr><th>Couche</th><th>Talent</th><th>Effet</th></tr>{lignes}</table>")


def gen_anciennes():
    """Catalogue des puissances anciennes (data/ancients.json)."""
    d = charger("ancients.json")
    lignes = ""
    for k in d.get("kinds", {}).values():
        postes = "<br>".join(f"<b>{esc(p['label'])}</b> : {inline(p.get('text', ''))}" for p in k.get("posts", []))
        lignes += (f"<tr><td><b>{esc(k['name'])}</b><br><small>{esc(k.get('register', ''))}</small></td>"
                   f"<td>{inline(k.get('angers_text', ''))}</td><td>{inline(k.get('wants_text', ''))}<br><small>Mission : {inline(k.get('mission', {}).get('text', ''))}</small></td>"
                   f"<td>{postes}</td></tr>")
    return (f"<table class='grille'><tr><th>Ancienne</th><th>Ce qui la fâche</th><th>Ce qu'elle veut</th><th>Ses postes</th></tr>{lignes}</table>")


def gen_anciennes_batiments():
    """Bâtiments uniques des mondes anciens (data/ancients.json)."""
    lignes = "".join(f"<tr><td><b>{esc(b['label'])}</b></td><td>{inline(b.get('text', ''))}</td></tr>"
                     for bid, b in charger("ancients.json").get("buildings", {}).items() if not bid.startswith("_"))
    return f"<table class='grille'><tr><th>Bâtiment</th><th>Ce qu'on en dit</th></tr>{lignes}</table>"


def gen_mineurs_modes():
    """Réglage Peuples mineurs (data/minors.json, modes)."""
    d = charger("minors.json")
    lignes = "".join(f"<tr><td><b>{esc(m['label'])}</b>{' (défaut)' if m['id'] == d.get('default_mode') else ''}</td><td>{inline(m.get('text', ''))}</td></tr>"
                     for m in d.get("modes", []))
    return f"<table class='grille'><tr><th>Choix</th><th>Effet</th></tr>{lignes}</table>"


def gen_mineurs():
    """Catalogue des peuples mineurs (data/minors.json, kinds)."""
    d = charger("minors.json")
    ori = d.get("orientations", {})
    fam = {"pre": "Pré-spatial", "space": "Cité-État spatiale"}
    lignes = ""
    for k in d.get("kinds", {}).values():
        if not isinstance(k, dict):
            continue
        g, t = k.get("gift", {}), k.get("trait", {})
        lignes += (f"<tr><td><b>{esc(k['name'])}</b><br><small>{esc(fam.get(k.get('family'), ''))} · {esc(ori.get(k.get('orientation'), {}).get('label', ''))}</small></td>"
                   f"<td>{inline(k.get('blurb', ''))}</td>"
                   f"<td><b>{esc(g.get('label', ''))}</b> : {inline(g.get('text', ''))}</td>"
                   f"<td><b>{esc(t.get('label', ''))}</b> : {inline(t.get('text', ''))}</td></tr>")
    return (f"<table class='grille'><tr><th>Peuple</th><th>Qui ils sont</th><th>Cadeau de suzerain</th><th>Trait d'assimilation</th></tr>{lignes}</table>")


def gen_mineurs_quetes():
    """Quêtes des peuples mineurs."""
    lignes = "".join(f"<tr><td><b>{esc(q['label'])}</b></td><td>{inline(q.get('text', ''))}</td></tr>"
                     for q in charger("minors.json").get("quests", {}).get("list", []))
    return f"<table class='grille'><tr><th>Quête</th><th>Ce qu'ils demandent</th></tr>{lignes}</table>"


def _mineurs_liste(cle):
    lignes = "".join(f"<tr><td><b>{esc(v['label'])}</b></td><td>{inline(v.get('text', ''))}</td></tr>"
                     for k, v in charger("minors.json").get(cle, {}).items() if not k.startswith("_") and isinstance(v, dict))
    return f"<table class='grille'><tr><th>Nom</th><th>Effet</th></tr>{lignes}</table>"


def gen_mineurs_accords():
    """Accords avec les pré-spatiaux."""
    return _mineurs_liste("accords")


def gen_mineurs_programmes():
    """Programmes avec les cités-États."""
    return _mineurs_liste("programs")


def gen_mineurs_talents():
    """Talents de peuple face aux peuples mineurs, par couche."""
    noms = {"gouvernement": "Gouvernement", "credo": "Credo", "archetype": "Archétype", "registre": "Registre"}
    lignes = ""
    for couche, valeurs in charger("minors.json").get("talents", {}).items():
        if couche.startswith("_") or not isinstance(valeurs, dict):
            continue
        for val, t in valeurs.items():
            nom = val if couche == "registre" else NOMS_COUCHE.get(val, val.replace("_", " ").capitalize())
            lignes += (f"<tr><td>{esc(noms.get(couche, couche))} {esc(nom)}</td><td><b>{esc(t['label'])}</b></td>"
                       f"<td>{inline(t['text'])}</td></tr>")
    return (f"<table class='grille'><tr><th>Couche</th><th>Talent</th><th>Effet</th></tr>{lignes}</table>")


def gen_rayonnement_modes():
    """Réglages Rayonnement culturel et Défection culturelle (data/culture.json)."""
    d = charger("culture.json")
    lignes = "".join(f"<tr><td>Rayonnement culturel</td><td><b>{esc(m['label'])}</b>{' (défaut)' if m['id'] == d.get('default_mode') else ''}</td><td>{inline(m.get('text', ''))}</td></tr>"
                     for m in d.get("modes", []))
    lignes += "".join(f"<tr><td>Défection culturelle</td><td><b>{esc(m['label'])}</b>{' (défaut)' if m['id'] == d.get('default_defect') else ''}</td><td>{inline(m.get('text', ''))}</td></tr>"
                      for m in d.get("defect_modes", []))
    return f"<table class='grille'><tr><th>Réglage</th><th>Choix</th><th>Effet</th></tr>{lignes}</table>"


def gen_rayonnement_paliers():
    """Les six paliers (data/culture.json, tiers)."""
    lignes = "".join(f"<tr><td><b>{esc(t['label'])}</b></td><td>{t['min']} %</td><td>{inline(t.get('text', ''))}</td></tr>"
                     for t in charger("culture.json").get("tiers", []))
    return f"<table class='grille'><tr><th>Palier</th><th>Cumul ÷ Patrimoine</th><th>Ce qu'on en dit</th></tr>{lignes}</table>"


def gen_rayonnement_merveilles():
    """Musée, villégiature et merveilles culturelles (data/buildings.json, champ culture)."""
    tech = charger("technologies.json")["technologies"]
    lignes = ""
    batiments = list(charger("buildings.json").items()) + list(charger("wonders.json")["wonders"].items())
    for bid, b in batiments:
        if not isinstance(b, dict) or not b.get("culture"):
            continue
        req = ", ".join(tech.get(t, {}).get("label", t) for t in b.get("requires_tech", []))
        cout = ", ".join(f"{v} {k}" for k, v in b.get("cost", {}).items())
        lignes += f"<tr><td><b>{esc(b['label'])}</b></td><td>{esc(req)}</td><td>{esc(cout)}</td><td>{inline(b.get('text', ''))}</td></tr>"
    return f"<table class='grille'><tr><th>Bâtiment</th><th>Technologie</th><th>Coût</th><th>Effet</th></tr>{lignes}</table>"


def gen_rayonnement_talents():
    """Talents de rayonnement par couche et par peuple (data/culture.json, talents)."""
    noms = {"gouvernement": "Gouvernement", "credo": "Credo", "archetype": "Archétype", "registre": "Registre", "traits": "Trait", "peoples": "Peuple"}
    peuples = {f["id"]: f.get("name", f["id"]) for f in charger("factions.json")}
    lignes = ""
    for couche, valeurs in charger("culture.json").get("talents", {}).items():
        if couche.startswith("_") or not isinstance(valeurs, dict):
            continue
        for val, t in valeurs.items():
            nom = peuples.get(val, val) if couche == "peoples" else NOMS_COUCHE.get(val, val.replace("_", " ").capitalize())
            lignes += (f"<tr><td>{esc(noms.get(couche, couche))} {esc(nom)}</td><td><b>{esc(t['label'])}</b></td>"
                       f"<td>{inline(t['text'])}</td></tr>")
    return (f"<table class='grille'><tr><th>Couche</th><th>Talent</th><th>Effet</th></tr>{lignes}</table>")


NOMS_RES = {**FX_TEXTE, "crystals": "cristaux"}


def gen_merveilles_modes():
    """Réglage Merveilles (data/wonders.json, modes)."""
    d = charger("wonders.json")
    lignes = "".join(f"<tr><td><b>{esc(m['label'])}</b>{' (défaut)' if m['id'] == d.get('default_mode') else ''}</td><td>{inline(m.get('text', ''))}</td></tr>"
                     for m in d.get("modes", []))
    return f"<table class='grille'><tr><th>Merveilles</th><th>Effet</th></tr>{lignes}</table>"


def site_texte(site):
    """Condition de site d'une merveille, en clair."""
    types = {p: v.get("label", p) for p, v in charger("planet_types.json").items() if isinstance(v, dict)}
    morceaux = []
    for k, v in site.items():
        if k == "capital": morceaux.append("capitale")
        elif k == "min_pop": morceaux.append(f"{v} population")
        elif k == "min_size": morceaux.append(f"planète de taille {v}+")
        elif k == "crossroads": morceaux.append(f"carrefour de {v} routes")
        elif k == "border": morceaux.append("monde frontalier")
        elif k == "building": morceaux.append(f"avec {charger('buildings.json').get(v, {}).get('label', v).lower()}")
        elif k == "or_building": morceaux.append(f"ou {charger('buildings.json').get(v, {}).get('label', v).lower()}")
        elif k == "planet": morceaux.append("monde " + " ou ".join(types.get(p, p).lower() for p in v))
        elif k == "star": morceaux.append("étoile : " + ", ".join({"blue_giant": "géante bleue", "black_hole": "trou noir"}.get(s, s) for s in v))
        elif k == "or_star": morceaux.append("ou trou noir")
        elif k == "terrain": morceaux.append("terrain : " + ", ".join(t.replace("_", " ") for t in v))
        elif k == "storm_or_terrain": morceaux.append("terrain difficile")
        elif k == "nest": morceaux.append("nid de créatures proche")
        elif k == "ancient_near": morceaux.append(f"ancienne à {v} sauts")
        elif k == "min_species": morceaux.append(f"{v} peuples sur le monde")
        elif k == "holy": morceaux.append("monde saint")
        elif k == "trade_route": morceaux.append("sur une route commerciale")
        elif k == "no_habitable": morceaux.append("étoile sans monde habitable")
        elif k == "amph": morceaux.append("membre de l'Amphictyonie")
        elif k == "amph_seat": morceaux.append("capitale d'un amphictyon")
        elif k == "outpost_ok": morceaux.append("avant-poste possible")
        elif k == "distinct_system": morceaux.append("un par système")
    return ", ".join(morceaux) or "partout"


def gen_merveilles():
    """Catalogue des merveilles par famille (data/wonders.json)."""
    d = charger("wonders.json")
    tech = charger("technologies.json")["technologies"]
    out = ""
    for fam, nom in d["families"].items():
        lignes = ""
        for wid, w in d["wonders"].items():
            if w.get("family") != fam:
                continue
            if w.get("requires_tech"):
                deb = ", ".join(tech.get(t, {}).get("label", t) for t in w["requires_tech"])
            else:
                deb = f"ère {w.get('unlock_era', w.get('era', 1))}"
            extra = w.get("registre") or w.get("credo") or ""
            if extra:
                deb += f" ({extra})"
            cout = ", ".join(f"{v} {NOMS_RES.get(k, k)}" for k, v in w.get("cost", {}).items())
            lignes += (f"<tr><td><b>{esc(w['label'])}</b><br><span class='petit'>ère {w.get('era', 1)}, {w.get('days', 360)} j</span></td>"
                       f"<td>{esc(deb)}</td><td>{esc(site_texte(w.get('site', {})))}</td><td>{esc(cout)}</td><td>{inline(w.get('text', ''))}</td></tr>")
        if lignes:
            out += (f"<h4>{esc(nom)}</h4><table class='grille'><tr><th>Merveille</th><th>Déblocage</th><th>Site</th><th>Coût</th><th>Effet</th></tr>{lignes}</table>")
    return out


def gen_hauts_faits_modes():
    """Réglage Hauts faits (data/deeds.json, modes)."""
    d = charger("deeds.json")
    lignes = "".join(f"<tr><td><b>{esc(m['label'])}</b>{' (défaut)' if m['id'] == 'tous' else ''}</td><td>{inline(m.get('text', ''))}</td></tr>"
                     for m in d.get("modes", []))
    return f"<table class='grille'><tr><th>Hauts faits</th><th>Effet</th></tr>{lignes}</table>"


SORTES_HF = {"first": "Première", "record": "Record", "layer": "Couche", "infamous": "Infâme", "secret": "Secret"}
ERES_HF = ["I", "II", "III", "IV", "V"]


def gen_hauts_faits():
    """Catalogue des hauts faits par famille (data/deeds.json) ; les secrets restent cachés."""
    d = charger("deeds.json")
    out = ""
    for fam, f in d["families"].items():
        aff = f.get("affinity", {})
        qui = ", ".join([f"credo {c}" for c in aff.get("credo", [])] + [f"registre {r}" for r in aff.get("registre", [])])
        lignes = ""
        secrets = 0
        for hid, h in d["deeds"].items():
            if h.get("family") != fam:
                continue
            if h["sort"] == "secret":
                secrets += 1
                continue
            sorte = SORTES_HF.get(h["sort"], h["sort"])
            if h["sort"] == "record":
                sorte += f" ère {ERES_HF[int(h.get('era', 1)) - 1]}"
            if h.get("layer"):
                sorte += " (" + ", ".join(str(v) for v in h["layer"].values()) + ")"
            titre = d["titles"].get(h.get("title", ""), {}).get("label", "")
            texte = h.get("text", "") + (f" Titre : {titre}." if titre else "")
            lignes += f"<tr><td><b>{esc(h['label'])}</b></td><td>{esc(sorte)}</td><td>{inline(texte)}</td></tr>"
        if secrets:
            lignes += f"<tr><td><b>???</b></td><td>Secret</td><td>{secrets} haut{'s' if secrets > 1 else ''} fait{'s' if secrets > 1 else ''} secret{'s' if secrets > 1 else ''}, à découvrir.</td></tr>"
        if lignes:
            out += (f"<h4>{esc(f['label'])}</h4><p class='petit'>Gloire doublée pour : {esc(qui) if qui else 'personne'}</p>"
                    f"<table class='grille'><tr><th>Haut fait</th><th>Sorte</th><th>Condition</th></tr>{lignes}</table>")
    return out


def gen_hauts_faits_recompenses():
    """Récompenses au choix (data/deeds.json, rewards)."""
    d = charger("deeds.json")
    lignes = ""
    for rid, r in d["rewards"].items():
        if r["k"] == "res":
            eff = ", ".join(f"{v} {NOMS_RES.get(k, k)}" for k, v in r["res"].items()) + " (selon l'ère)"
        elif r["k"] == "research":
            eff = f"{r['pct']} % du coût de la recherche en cours"
        elif r["k"] == "trophy":
            eff = "un Trophée encore libre, posé dans la capitale"
        elif r["k"] == "ships":
            eff = f"{r['n']} vaisseaux à la capitale (croiseurs avec Coques lourdes, sinon frégates)"
        else:
            eff = "un héros qui rejoint l'empire, déjà expérimenté (s'il reste de la place)"
        lignes += f"<tr><td><b>{esc(r['label'])}</b></td><td>{esc(eff)}</td></tr>"
    return f"<table class='grille'><tr><th>Récompense</th><th>Ce qu'elle donne</th></tr>{lignes}</table>"


def gen_hauts_faits_trophees():
    """Trophées (data/deeds.json, trophies)."""
    d = charger("deeds.json")
    lignes = "".join(f"<tr><td><b>{esc(t['label'])}</b></td><td>{inline(t.get('text', ''))}</td></tr>" for t in d["trophies"].values())
    return f"<table class='grille'><tr><th>Trophée</th><th>Effet</th></tr>{lignes}</table>"


def gen_souverains_modes():
    """Réglages Souverains et Mort au combat (data/rulers.json, data/heroes.json)."""
    d = charger("rulers.json")
    h = charger("heroes.json")["combat_death"]
    l1 = "".join(f"<tr><td><b>{esc(m['label'])}</b>{' (défaut)' if m['id'] == d.get('default_mode') else ''}</td><td>{inline(m.get('text', ''))}</td></tr>" for m in d["modes"])
    l2 = "".join(f"<tr><td><b>{esc(m['label'])}</b>{' (défaut)' if m['id'] == h.get('default') else ''}</td><td>{inline(m.get('text', ''))}</td></tr>" for m in h["modes"])
    return (f"<table class='grille'><tr><th>Souverains</th><th>Effet</th></tr>{l1}</table>"
            f"<table class='grille'><tr><th>Mort au combat</th><th>Effet</th></tr>{l2}</table>")


NOMS_GOUV = {"feodalite": "Féodalité", "theocratie": "Théocratie", "republique": "République", "syndicat": "Syndicat",
             "horde": "Horde", "ruche": "Ruche", "conscience": "Conscience"}


def gen_successions():
    """Succession selon le gouvernement (data/rulers.json, succession)."""
    d = charger("rulers.json")
    lignes = "".join(f"<tr><td><b>{esc(NOMS_GOUV.get(g, g))}</b></td><td>{esc(v['label'])}</td><td>{esc(' / '.join(dict.fromkeys(v['title'])))}</td><td>{inline(v['text'])}</td></tr>"
                     for g, v in d["succession"].items())
    return f"<table class='grille'><tr><th>Gouvernement</th><th>Succession</th><th>Titre</th><th>Règle</th></tr>{lignes}</table>"


NOMS_COURANTS = {"forge": "Forge", "academie": "Académie", "concorde": "Concorde", "seve": "Sève", "autel": "Autel", "glaive": "Glaive"}


def gen_archetypes_regne():
    """Archétypes de règne et leurs pouvoirs (data/rulers.json, archetypes)."""
    d = charger("rulers.json")
    lignes = "".join(f"<tr><td><b>{esc(a['label'])}</b><br><span class='petit'>{esc(a['text'])}</span></td><td><b>{esc(a['power']['label'])}</b> : {inline(a['power']['text'])}</td><td>{esc(NOMS_COURANTS.get(a.get('current', ''), ''))}</td></tr>"
                     for a in d["archetypes"].values())
    return f"<table class='grille'><tr><th>Archétype</th><th>Pouvoir (recharge de deux ans)</th><th>Courant</th></tr>{lignes}</table>"


FAM_SURNOMS = {"guerre": "Guerre", "paix": "Paix", "batir": "Bâtir", "savoir": "Savoir", "foi": "Foi", "echange": "Échanges",
               "ombre": "Ombres", "malheur": "Malheurs", "temps": "Le temps", "gloire": "Gloire", "couche": "Propres à un peuple"}


def gen_surnoms():
    """Les surnoms, par famille (data/rulers.json, cognomens)."""
    d = charger("rulers.json")
    fams = {}
    for c in d["cognomens"]:
        fams.setdefault(c.get("fam", "regne"), []).append(c)
    out = ""
    for fam, cs in fams.items():
        noms = ", ".join(esc(c["m"]) + (f" / {esc(c['f'])}" if c.get("f") and c["f"] != c["m"] else "") for c in cs)
        out += f"<p><b>{esc(FAM_SURNOMS.get(fam, fam.capitalize()))}</b> ({len(cs)}) : {noms}.</p>"
    amb = ", ".join(esc(a["cog"]["m"]) for a in d["ambitions"] if a.get("cog"))
    return out + f"<p><b>Ambitions accomplies</b> ({len(d['ambitions'])}) : {amb}.</p>"


def gen_ambitions():
    """Ambitions du souverain (data/rulers.json, ambitions)."""
    d = charger("rulers.json")
    lignes = "".join(f"<tr><td><b>{esc(a['label'])}</b></td><td>{inline(a.get('text', ''))}</td><td>{esc(a['cog']['m'])}</td></tr>" for a in d["ambitions"])
    return f"<table class='grille'><tr><th>Ambition</th><th>Condition</th><th>Surnom</th></tr>{lignes}</table>"


def gen_heritages():
    """Héritages de la maison, ou traditions d'État (data/rulers.json, legacies)."""
    d = charger("rulers.json")
    lignes = ""
    for t in d["legacies"].values():
        niv = " ; ".join(f"<b>{esc(l['label'])}</b> ({l['cost']}) : {inline(l.get('text', ''))}" for l in t["levels"])
        lignes += f"<tr><td><b>{esc(t['label'])}</b></td><td>{niv}</td></tr>"
    return f"<table class='grille'><tr><th>Voie</th><th>Niveaux (coût en renom)</th></tr>{lignes}</table>"


def gen_cour_modes():
    """Réglage Grandes Maisons (data/court.json)."""
    d = charger("court.json")
    l1 = "".join(f"<tr><td><b>{esc(m['label'])}</b>{' (défaut)' if m['id'] == d.get('default_mode') else ''}</td><td>{inline(m.get('text', ''))}</td></tr>" for m in d["modes"])
    return f"<table class='grille'><tr><th>Grandes Maisons</th><th>Effet</th></tr>{l1}</table>"


APT_NOMS = {"gestion": "Gestion", "guerre": "Guerre", "eloquence": "Éloquence", "intrigue": "Intrigue"}


def gen_cour_vocations():
    """Vocations des maisons (data/court.json, vocations)."""
    d = charger("court.json")
    g = {x["id"]: x["label"] for x in charger("goods.json").get("luxuries", [])} if isinstance(charger("goods.json").get("luxuries"), list) else {}
    lignes = ""
    for v in d["vocations"]:
        regs = v.get("registres", [])
        aime = ", ".join(esc(c["label"]) for c in v.get("likes", []))
        hait = ", ".join(esc(c["label"]) for c in v.get("dislikes", []))
        luxes = ", ".join(esc(g.get(x, x.replace("_", " "))) for x in v.get("goods", []))
        lignes += (f"<tr><td><b>{esc(v['label'])}</b>{('<br><span class=petit>' + esc(', '.join(regs)) + '</span>') if regs else ''}</td>"
                   f"<td>{esc(v['text'])}<br><span class='petit'>Aime : {aime}. Déteste : {hait}. Luxes : {luxes}.</span></td>"
                   f"<td>{esc(v.get('seat_text', ''))}</td><td>{esc(NOMS_COURANTS.get(v.get('current', ''), ''))}</td></tr>")
    return f"<table class='grille'><tr><th>Vocation</th><th>Ce qu'elle fait, aime et déteste</th><th>Siège</th><th>Courant</th></tr>{lignes}</table>"


def gen_cour_offices():
    """Grands offices (data/court.json, offices)."""
    d = charger("court.json")
    lignes = ""
    for o in d["offices"]:
        noms = " / ".join(dict.fromkeys(o.get("labels", {}).values()))
        lignes += (f"<tr><td><b>{esc(o['label'])}</b>{('<br><span class=petit>' + esc(noms) + '</span>') if noms else ''}"
                   f"{'<br><span class=petit>théocratie seulement</span>' if o.get('governments') else ''}</td>"
                   f"<td>{esc(APT_NOMS.get(o['apt'], o['apt']))}</td><td>{inline(o.get('text', ''))}</td></tr>")
    return f"<table class='grille'><tr><th>Office</th><th>Aptitude</th><th>Effet</th></tr>{lignes}</table>"


def gen_cour_talents():
    """Talents de cour par couche (data/court.json, talents)."""
    d = charger("court.json")
    lignes = ""
    for couche, t in d["talents"].items():
        for k, v in t.items():
            lignes += f"<tr><td>{esc(couche.capitalize())}</td><td>{esc(v['label'])}</td></tr>"
    return f"<table class='grille'><tr><th>Couche</th><th>Talent</th></tr>{lignes}</table>"


def gen_admin_modes():
    """Réglage Administration (data/administration.json)."""
    d = charger("administration.json")
    l1 = "".join(f"<tr><td><b>{esc(m['label'])}</b>{' (défaut)' if m['id'] == d.get('default_mode') else ''}</td><td>{inline(m.get('text', ''))}</td></tr>" for m in d["modes"])
    return f"<table class='grille'><tr><th>Administration</th><th>Effet</th></tr>{l1}</table>"


def gen_admin_efforts():
    """Effort administratif (data/administration.json, efforts)."""
    d = charger("administration.json")
    l1 = "".join(f"<tr><td><b>{esc(m['label'])}</b>{' (défaut)' if m['id'] == d.get('default_effort') else ''}</td><td>{inline(m.get('text', ''))}</td></tr>" for m in d["efforts"])
    return f"<table class='grille'><tr><th>Effort</th><th>Effet</th></tr>{l1}</table>"


def gen_admin_talents():
    """Talents d'administration par couche (data/administration.json, talents)."""
    d = charger("administration.json")
    lignes = ""
    for couche, t in d["talents"].items():
        for k, v in t.items():
            lignes += f"<tr><td>{esc(couche.capitalize())}</td><td>{esc(k.capitalize())}</td><td><b>{esc(v['label'])}</b> : {inline(v.get('text', ''))}</td></tr>"
    return f"<table class='grille'><tr><th>Couche</th><th>Valeur</th><th>Talent</th></tr>{lignes}</table>"


def gen_fisc_modes():
    """Réglage Fiscalité (data/finance.json)."""
    d = charger("finance.json")
    l1 = "".join(f"<tr><td><b>{esc(m['label'])}</b>{' (défaut)' if m['id'] == d.get('default_mode') else ''}</td><td>{inline(m.get('text', ''))}</td></tr>" for m in d["modes"])
    return f"<table class='grille'><tr><th>Fiscalité</th><th>Effet</th></tr>{l1}</table>"


def gen_fisc_crans():
    """Crans d'impôt (data/finance.json, taxes)."""
    d = charger("finance.json")["taxes"]
    l1 = "".join(f"<tr><td><b>{esc(m['label'])}</b>{' (défaut)' if m['id'] == d.get('default') else ''}</td><td>{m['energy_pct']:+d} %</td><td>{m['stability']:+d}</td><td>{m['growth_pct']:+d} %</td></tr>" for m in d["levels"])
    return f"<table class='grille'><tr><th>Cran</th><th>Énergie</th><th>Stabilité</th><th>Croissance</th></tr>{l1}</table>"


def gen_fisc_cotes():
    """Cotes de crédit (data/finance.json, rating)."""
    d = charger("finance.json")["rating"]["grades"]
    l1 = ""
    prev = 0
    for g in d:
        borne = f"jusqu'à {g['max_ratio']} %" if g["max_ratio"] < 1000 else "faillite, répudiation, ou au-delà"
        l1 += f"<tr><td><b>{esc(g['id'])}</b></td><td>{borne}</td><td>×{g['rate_pct']} %</td><td>×{g['cap_pct']} %</td></tr>"
    return f"<table class='grille'><tr><th>Cote</th><th>Dette / plafond</th><th>Taux</th><th>Plafond</th></tr>{l1}</table>"


def gen_fisc_paliers():
    """Paliers de la crise de la dette et approches (data/finance.json, crisis)."""
    d = charger("finance.json")["crisis"]
    l1 = "".join(f"<tr><td><b>{esc(s['label'])}</b></td><td>{inline(s.get('text', ''))}</td></tr>" for s in d["stages"])
    l2 = "".join(f"<tr><td><b>{esc(a['label'])}</b></td><td>{inline(a.get('text', ''))}</td></tr>" for a in d["approaches"])
    return (f"<table class='grille'><tr><th>Palier</th><th>Effet</th></tr>{l1}</table>"
            f"<table class='grille'><tr><th>Approche</th><th>Effet</th></tr>{l2}</table>")


def gen_fisc_talents():
    """Talents fiscaux par couche (data/finance.json, talents)."""
    d = charger("finance.json")
    lignes = ""
    for couche, t in d["talents"].items():
        for k, v in t.items():
            lignes += f"<tr><td>{esc(couche.capitalize())}</td><td>{esc(k.capitalize())}</td><td><b>{esc(v['label'])}</b> : {inline(v.get('text', ''))}</td></tr>"
    return f"<table class='grille'><tr><th>Couche</th><th>Valeur</th><th>Talent</th></tr>{lignes}</table>"


def gen_priv_modes():
    """Réglage Économie privée (data/private.json)."""
    d = charger("private.json")
    l1 = "".join(f"<tr><td><b>{esc(m['label'])}</b>{' (défaut)' if m['id'] == d.get('default_mode') else ''}</td><td>{inline(m.get('text', ''))}</td></tr>" for m in d["modes"])
    return f"<table class='grille'><tr><th>Économie privée</th><th>Effet</th></tr>{l1}</table>"


def gen_priv_impot():
    """Impôt sur les bénéfices selon le cran (data/private.json, tax)."""
    t = charger("private.json")["tax"]
    noms = {"tres_bas": "Très bas", "bas": "Bas", "normal": "Normal", "eleve": "Élevé", "ecrasant": "Écrasant"}
    l1 = "".join(f"<tr><td><b>{noms.get(k, k)}</b></td><td>{v} %</td><td>{t['invest_pct'].get(k, 100)} %</td></tr>" for k, v in t["rates"].items())
    return f"<table class='grille'><tr><th>Cran de l'impôt</th><th>Impôt sur les bénéfices</th><th>Chance d'investir chaque mois</th></tr>{l1}</table>"


def gen_priv_secteurs():
    """Secteurs des compagnies (data/private.json, companies.sectors)."""
    d = charger("private.json")["companies"]["sectors"]
    lois = {l["id"]: l["label"] for l in charger("politics.json")["independent_laws"]}
    l1 = "".join(f"<tr><td><b>{esc(s['label'])}</b></td><td>{inline(s.get('text', ''))}</td><td>{esc(lois.get(s.get('law', ''), s.get('law', '')))}</td><td><i>{esc(s['names'][0].replace('%s', '…'))}</i></td></tr>" for s in d)
    return f"<table class='grille'><tr><th>Secteur</th><th>Effet (prospérité 60+)</th><th>Loi réclamée</th><th>Exemple de nom</th></tr>{l1}</table>"


def gen_priv_chartes():
    """Chartes et traits des dirigeants (data/private.json)."""
    d = charger("private.json")
    l1 = "".join(f"<tr><td><b>{esc(c['label'])}</b></td><td>{inline(c.get('text', ''))}</td></tr>" for c in d["charters"]["list"])
    l2 = "".join(f"<tr><td><b>{esc(c['label'])}</b></td><td>{inline(c.get('text', ''))}</td></tr>" for c in d["directors"]["traits"])
    return (f"<table class='grille'><tr><th>Charte</th><th>Effet</th></tr>{l1}</table>"
            f"<table class='grille'><tr><th>Dirigeant</th><th>Trait</th></tr>{l2}</table>")


def gen_priv_talents():
    """Talents de l'économie privée par couche (data/private.json, talents)."""
    d = charger("private.json")
    lignes = ""
    for couche, t in d["talents"].items():
        for k, v in t.items():
            lignes += f"<tr><td>{esc(couche.capitalize())}</td><td>{esc(k.capitalize())}</td><td><b>{esc(v['label'])}</b> : {inline(v.get('text', ''))}</td></tr>"
    return f"<table class='grille'><tr><th>Couche</th><th>Valeur</th><th>Talent</th></tr>{lignes}</table>"


def gen_port_modes():
    """Réglage Spatioports (data/ports.json)."""
    d = charger("ports.json")
    l1 = "".join(f"<tr><td><b>{esc(m['label'])}</b>{' (défaut)' if m['id'] == d.get('default_mode') else ''}</td><td>{inline(m.get('text', ''))}</td></tr>" for m in d["modes"])
    return f"<table class='grille'><tr><th>Spatioports</th><th>Effet</th></tr>{l1}</table>"


def gen_port_niveaux():
    """Ports : niveau, portée, réserve, coût (data/ports.json et buildings.json)."""
    d = charger("ports.json")
    b = charger("buildings.json")
    lv = d["levels"]
    w = d["warehouse"]
    noms = {"materials": "matériaux", "energy": "énergie"}
    lignes = ""
    for bid, n in sorted(lv["buildings"].items(), key=lambda x: x[1]):
        bd = b.get(bid, {})
        cout = ", ".join(f"{v} {noms.get(k, k)}" for k, v in bd.get("cost", {}).items())
        res = "-" if n == 0 else f"{w['days_per_level'] * n * (w['grand_mult'] if n >= 3 else 1)} jours"
        lignes += f"<tr><td><b>{esc(lv['labels'][n])}</b></td><td>{lv['range'][n]} saut{'s' if lv['range'][n] > 1 else ''}</td><td>{res}</td><td>{esc(cout)}</td></tr>"
    return f"<table class='grille'><tr><th>Port</th><th>Portée</th><th>Réserve (complet)</th><th>Coût</th></tr>{lignes}</table>"


def gen_port_talents():
    """Talents des spatioports par couche (data/ports.json, talents)."""
    d = charger("ports.json")
    lignes = ""
    for couche, t in d["talents"].items():
        if couche.startswith("_"):
            continue
        for k, v in t.items():
            lignes += f"<tr><td>{esc(couche.capitalize())}</td><td>{esc(k.capitalize())}</td><td><b>{esc(v['label'])}</b> : {inline(v.get('text', ''))}</td></tr>"
    return f"<table class='grille'><tr><th>Couche</th><th>Valeur</th><th>Talent</th></tr>{lignes}</table>"


def gen_def_modes():
    """Réglage Défenses spatiales (data/defenses.json)."""
    d = charger("defenses.json")
    l1 = "".join(f"<tr><td><b>{esc(m['label'])}</b>{' (défaut)' if m['id'] == d.get('default_mode') else ''}</td><td>{inline(m.get('text', ''))}</td></tr>" for m in d["modes"])
    return f"<table class='grille'><tr><th>Défenses spatiales</th><th>Effet</th></tr>{l1}</table>"


def gen_def_stations():
    """Paliers de la station et leur cœur (data/defenses.json, stations et core)."""
    d = charger("defenses.json")
    b = charger("buildings.json")
    l1 = ""
    for t in ["1", "2", "3"]:
        st, c = d["stations"][t], d["core"][t]
        bd = b.get(st["building"], {})
        armes = ", ".join(f"{k} {v}" for k, v in c["weapons"].items())
        l1 += (f"<tr><td><b>{esc(st['label'])}</b></td><td>{st['slots']}</td><td>{st['capacity']}</td>"
               f"<td>{c['hp']} PV, blindage {c['armor']}, bouclier {c['shield']}</td><td>{esc(armes)}</td>"
               f"<td>{d['cover']['pct'][int(t)]} %</td><td>+{bd.get('garrison', 0)}</td></tr>")
    return ("<table class='grille'><tr><th>Palier</th><th>Modules</th><th>Places</th><th>Cœur</th><th>Armes</th>"
            f"<th>Couverture</th><th>Garnison</th></tr>{l1}</table>")


def gen_def_elements():
    """Modules, plates-formes et défenses planétaires (data/buildings.json, rôle « defense »)."""
    b = charger("buildings.json")
    noms = {"module": "Module", "platform": "Plate-forme", "planetary": "Planétaire", "shield": "Bouclier"}
    l1 = ""
    for k, v in b.items():
        r = v.get("defense") if isinstance(v, dict) else None
        if not isinstance(r, str):
            continue
        cout = ", ".join(f"{n} {r2}" for r2, n in v.get("cost", {}).items())
        l1 += f"<tr><td><b>{esc(v['label'])}</b></td><td>{noms.get(r, r)}</td><td>{esc(cout)}</td><td>{inline(v.get('text', ''))}</td></tr>"
    return f"<table class='grille'><tr><th>Élément</th><th>Rôle</th><th>Coût</th><th>Effet</th></tr>{l1}</table>"


def gen_def_talents():
    """Talents de défense par couche (data/defenses.json, talents)."""
    d = charger("defenses.json")
    lignes = ""
    for couche, t in d["talents"].items():
        if couche.startswith("_"):
            continue
        for k, v in t.items():
            lignes += f"<tr><td>{esc(couche.capitalize())}</td><td>{esc(k.capitalize())}</td><td><b>{esc(v['label'])}</b> : {inline(v.get('text', ''))}</td></tr>"
    return f"<table class='grille'><tr><th>Couche</th><th>Valeur</th><th>Talent</th></tr>{lignes}</table>"


def gen_st_modes():
    """Réglage Furtivité (data/stealth.json)."""
    d = charger("stealth.json")
    l1 = "".join(f"<tr><td><b>{esc(m['label'])}</b>{' (défaut)' if m['id'] == d.get('default_mode') else ''}</td><td>{inline(m.get('text', ''))}</td></tr>" for m in d["modes"])
    return f"<table class='grille'><tr><th>Furtivité</th><th>Effet</th></tr>{l1}</table>"


def gen_st_modules():
    """Modules de furtivité (data/designs.json, drapeau « stealth »)."""
    d = charger("designs.json")
    tech = charger("technologies.json")["technologies"]
    l1 = ""
    for k, m in d["modules"].items():
        if not isinstance(m, dict) or not m.get("stealth"):
            continue
        tailles = ", ".join({"small": "petite", "medium": "moyenne", "large": "grande", "titan": "titan"}[t] for t in m.get("sizes", ["small", "medium", "large", "titan"]))
        req = ", ".join(tech.get(t, {}).get("label", t) for t in m.get("requires_tech", []))
        l1 += f"<tr><td><b>{esc(m['label'])}</b></td><td>{esc(tailles)}</td><td>{esc(req)}</td><td>{inline(m.get('text', ''))}</td></tr>"
    return f"<table class='grille'><tr><th>Module</th><th>Coques</th><th>Technologie</th><th>Effet</th></tr>{l1}</table>"


def gen_st_talents():
    """Talents de furtivité par couche (data/stealth.json, talents)."""
    d = charger("stealth.json")
    lignes = ""
    for couche, t in d["talents"].items():
        if couche.startswith("_"):
            continue
        for k, v in t.items():
            lignes += f"<tr><td>{esc(couche.capitalize())}</td><td>{esc(k.capitalize())}</td><td><b>{esc(v['label'])}</b> : {inline(v.get('text', ''))}</td></tr>"
    return f"<table class='grille'><tr><th>Couche</th><th>Valeur</th><th>Talent</th></tr>{lignes}</table>"


def gen_portail_modes():
    """Réglage Portails de saut (data/portals.json)."""
    d = charger("portals.json")
    l1 = "".join(f"<tr><td><b>{esc(m['label'])}</b>{' (défaut au menu)' if m['id'] == d.get('default_mode') else ''}</td><td>{inline(m.get('text', ''))}</td></tr>" for m in d["modes"])
    return f"<table class='grille'><tr><th>Portails de saut</th><th>Effet</th></tr>{l1}</table>"


def gen_portail_batiments():
    """Relais, portails, ancres (data/buildings.json, drapeau « portals », et data/portals.json)."""
    b = charger("buildings.json")
    d = charger("portals.json")
    techs = charger("technologies.json")["technologies"]
    req = {"relais_hyper": "relais_hyperspatiaux", "portail_saut": "portails_saut", "grand_portail": "grands_portails",
           "portail_ancien": "stabilisation_ver", "ancre_ver": "stabilisation_ver"}
    portee = d["gates"]["range"]
    l1 = ""
    for k, v in b.items():
        if not isinstance(v, dict) or not v.get("portals"):
            continue
        noms = {"materials": "matériaux", "energy": "énergie", "crystals": "cristaux de saut", "influence": "influence"}
        cout = ", ".join(f"{n} {noms.get(r2, r2)}" for r2, n in v.get("cost", {}).items())
        tech = techs.get(req.get(k, ""), {}).get("label", "—")
        p = f"{portee[k]} sauts" if k in portee else "—"
        l1 += f"<tr><td><b>{esc(v['label'])}</b></td><td>{esc(tech)}</td><td>{esc(cout)}</td><td>{p}</td><td>{inline(v.get('text', ''))}</td></tr>"
    return f"<table class='grille'><tr><th>Bâtiment</th><th>Technologie</th><th>Coût</th><th>Portée</th><th>Effet</th></tr>{l1}</table>"


def gen_portail_talents():
    """Talents des portails par couche (data/portals.json, talents)."""
    d = charger("portals.json")
    lignes = ""
    for couche, t in d["talents"].items():
        if couche.startswith("_"):
            continue
        for k, v in t.items():
            lignes += f"<tr><td>{esc(couche.capitalize())}</td><td>{esc(k.capitalize())}</td><td><b>{esc(v['label'])}</b> : {inline(v.get('text', ''))}</td></tr>"
    return f"<table class='grille'><tr><th>Couche</th><th>Valeur</th><th>Talent</th></tr>{lignes}</table>"


def gen_gen_modes():
    """Réglage Ingénierie des espèces (data/genetics.json)."""
    d = charger("genetics.json")
    l1 = "".join(f"<tr><td><b>{esc(m['label'])}</b>{' (défaut au menu)' if m['id'] == d.get('default_mode') else ''}</td><td>{inline(m.get('text', ''))}</td></tr>" for m in d["modes"])
    return f"<table class='grille'><tr><th>Ingénierie des espèces</th><th>Effet</th></tr>{l1}</table>"


def gen_gen_techs():
    """Technologies du pilier (data/genetics.json « techs », data/technologies.json)."""
    d = charger("genetics.json")
    techs = charger("technologies.json")["technologies"]
    eres = {1: "I", 2: "II", 3: "III", 4: "IV", 5: "V"}
    l1 = ""
    for k in d["techs"]:
        if k.startswith("_"):
            continue
        t = techs.get(k, {})
        l1 += f"<tr><td><b>{esc(t.get('label', k))}</b></td><td>{eres.get(t.get('era'), '')}</td><td>{inline(t.get('text', ''))}</td></tr>"
    return f"<table class='grille'><tr><th>Technologie</th><th>Ère</th><th>Ce qu'elle ouvre</th></tr>{l1}</table>"


def gen_gen_voies():
    """Voies ouvertes par archétype (data/genetics.json « voies »)."""
    d = charger("genetics.json")
    lab = d["voie_labels"]
    arch = {"humanoide": "Humanoïde", "reptilien": "Reptilien", "ruche": "Ruche", "lithoide": "Lithoïde", "synthetique": "Synthétique", "energetique": "Énergétique"}
    l1 = "".join(f"<tr><td><b>{esc(arch.get(k, k))}</b></td><td>{esc(', '.join(lab.get(v, v) for v in vs))}</td></tr>" for k, vs in d["voies"].items() if not k.startswith("_"))
    return f"<table class='grille'><tr><th>Archétype</th><th>Voies</th></tr>{l1}</table>"


def gen_gen_traits():
    """Catalogue des traits façonnés (data/genetics.json « traits »), rangés par voie."""
    d = charger("genetics.json")
    lab = d["voie_labels"]
    l1 = ""
    for t in d["traits"]:
        l1 += f"<tr><td>{esc(lab.get(t['voie'], t['voie']))}</td><td><b>{esc(t['label'])}</b></td><td>{t.get('cost', 0):+d}</td><td>{inline(t.get('text', ''))}</td></tr>"
    return f"<table class='grille'><tr><th>Voie</th><th>Trait</th><th>Points</th><th>Effet</th></tr>{l1}</table>"


def gen_gen_paths():
    """Voies d'élévation (data/genetics.json « paths »)."""
    d = charger("genetics.json")
    l1 = "".join(f"<tr><td><b>{esc(p['label'])}</b></td><td>{inline(p.get('text', ''))}</td></tr>" for p in d["paths"]["list"])
    return f"<table class='grille'><tr><th>Voie</th><th>Effet</th></tr>{l1}</table>"


def gen_gen_talents():
    """Talents du génome par couche (data/genetics.json, talents)."""
    d = charger("genetics.json")
    lignes = ""
    for couche, t in d["talents"].items():
        if couche.startswith("_"):
            continue
        for k, v in t.items():
            lignes += f"<tr><td>{esc(couche.capitalize())}</td><td>{esc(k.capitalize())}</td><td><b>{esc(v['label'])}</b> : {inline(v.get('text', ''))}</td></tr>"
    return f"<table class='grille'><tr><th>Couche</th><th>Valeur</th><th>Talent</th></tr>{lignes}</table>"


def gen_psi_modes():
    """Réglage Pouvoirs psioniques (data/psionics.json)."""
    d = charger("psionics.json")
    l1 = "".join(f"<tr><td><b>{esc(m['label'])}</b>{' (défaut au menu)' if m['id'] == d.get('default_mode') else ''}</td><td>{inline(m.get('text', ''))}</td></tr>" for m in d["modes"])
    return f"<table class='grille'><tr><th>Pouvoirs psioniques</th><th>Effet</th></tr>{l1}</table>"


def gen_psi_niveaux():
    """Échelle des espèces (data/psionics.json « levels »)."""
    d = charger("psionics.json")
    l1 = "".join(f"<tr><td><b>{esc(l['label'])}</b></td><td>{inline(l.get('text', ''))}</td><td>{d['resonance']['per_pop'][l['id']] / 10:g}</td></tr>" for l in d["levels"])
    return f"<table class='grille'><tr><th>Niveau</th><th>Ce que cela veut dire</th><th>Résonance par habitant et par mois</th></tr>{l1}</table>"


def gen_psi_techs():
    """Technologies du pilier (data/psionics.json « techs »)."""
    d = charger("psionics.json")
    techs = charger("technologies.json")["technologies"]
    eres = {1: "I", 2: "II", 3: "III", 4: "IV", 5: "V"}
    l1 = ""
    for k in d["techs"]:
        if k.startswith("_"):
            continue
        t = techs.get(k, {})
        l1 += f"<tr><td><b>{esc(t.get('label', k))}</b></td><td>{eres.get(t.get('era'), '')}</td><td>{inline(t.get('text', ''))}</td></tr>"
    return f"<table class='grille'><tr><th>Technologie</th><th>Ère</th><th>Ce qu'elle ouvre</th></tr>{l1}</table>"


def gen_psi_pouvoirs():
    """Catalogue des pouvoirs (data/psionics.json « powers »)."""
    d = charger("psionics.json")
    techs = charger("technologies.json")["technologies"]
    l1 = ""
    for p in d["powers"]:
        t = techs.get(p.get("tech", ""), {}).get("label", p.get("tech", ""))
        l1 += f"<tr><td><b>{esc(p['label'])}</b></td><td>{esc(t)}</td><td>{p['cost']}</td><td>{p['cooldown']} j</td><td>{p['felure']} %</td><td>{inline(p.get('text', ''))}</td></tr>"
    n = d["navigation"]
    l1 += f"<tr><td><b>{esc(n['label'])}</b></td><td>{esc(techs.get(n['tech'], {}).get('label', n['tech']))}</td><td>{n['cost']}</td><td>{n['cooldown']} j</td><td>{n['felure']} %</td><td>{inline(n.get('text', ''))}</td></tr>"
    return f"<table class='grille'><tr><th>Pouvoir</th><th>Technologie</th><th>Résonance</th><th>Recharge</th><th>Fêlure</th><th>Effet</th></tr>{l1}</table>"


def gen_psi_felures():
    """Fêlures (data/psionics.json « felures »)."""
    d = charger("psionics.json")["felures"]
    l1 = "".join(f"<tr><td><b>{esc(f['label'])}</b></td><td>Toujours</td><td>{f['weight']}</td><td>{inline(f.get('text', ''))}</td></tr>" for f in d["table"])
    l1 += "".join(f"<tr><td><b>{esc(f['label'])}</b></td><td>Complet</td><td>{f['weight']}</td><td>{inline(f.get('text', ''))}</td></tr>" for f in d.get("grave", []))
    return f"<table class='grille'><tr><th>Fêlure</th><th>Réglage</th><th>Poids</th><th>Effet</th></tr>{l1}</table>"


def gen_psi_postures():
    """Postures de plongée (data/psionics.json « dream »)."""
    d = charger("psionics.json")["dream"]
    l1 = "".join(f"<tr><td><b>{esc(p['label'])}</b></td><td>{p['odds'][0]} %</td><td>{p['odds'][1]} %</td><td>{p['odds'][2]} %</td><td>{inline(p.get('text', ''))}</td></tr>" for p in d["postures"])
    return f"<table class='grille'><tr><th>Posture</th><th>Bienfait</th><th>Rien</th><th>Malédiction</th><th></th></tr>{l1}</table>"


def gen_psi_visions():
    """Catalogue des visions (data/psionics.json « visions »)."""
    d = charger("psionics.json")
    post = [p["label"] for p in d["dream"]["postures"]]
    sortes = {"boon": "Bienfait", "none": "Rien", "curse": "Malédiction"}
    l1 = "".join(f"<tr><td>{sortes.get(v['kind'], v['kind'])}</td><td><b>{esc(v['label'])}</b></td><td>{esc(post[v.get('tier', 0)]) if v['kind'] != 'none' else ''}</td><td>{inline(v.get('text', ''))}</td></tr>" for v in d["visions"]["list"])
    return f"<table class='grille'><tr><th>Sorte</th><th>Vision</th><th>Posture minimale</th><th>Effet</th></tr>{l1}</table>"


def _psi_fx(fx):
    noms = {"growth_pct": "croissance", "damage_pct": "dégâts", "stability": "stabilité", "trade_income_pct": "commerce", "repair_pct": "réparations"}
    res = {"knowledge": "Savoir", "food": "nourriture", "materials": "matériaux", "energy": "énergie", "all": "production"}
    out = []
    for k, v in fx.items():
        if isinstance(v, dict):
            out += [f"{res.get(r, r)} {x:+d} %" for r, x in v.items()]
        else:
            out.append(f"{noms.get(k, k)} {v:+d}{' %' if k.endswith('_pct') else ''}")
    return ", ".join(out)


def gen_psi_puissances():
    """Les Puissances du Songe (data/psionics.json « entities »)."""
    d = charger("psionics.json")["entities"]
    noms = {"credo": "credo", "gouvernement": "gouvernement"}
    actes = {"war": "la guerre", "peace": "la paix", "genome": "le génome façonné", "lecture": "la Lecture des esprits", "prescience": "la Préscience", "powers": "les pouvoirs"}
    l1 = ""
    for p in d["list"]:
        likes = ", ".join(NOMS_COUCHE.get(v, v) for vs in p.get("likes", {}).values() for v in vs)
        paliers = " ; ".join(f"faveur {t['favor']} : {_psi_fx(t['fx'])}{' et un Élu' if t.get('elu') else ''}" for t in p["tiers"])
        prix = ", ".join(x["label"] for x in p["price"])
        l1 += f"<tr><td><b>{esc(p['label'])}</b><br>{esc(p['domain'])}</td><td>{esc(likes)} ; {esc(', '.join(actes.get(a, a) for a in p.get('acts', {})))}</td><td>{esc(paliers)}</td><td>{esc(prix)}</td></tr>"
    last = d["last"]
    l1 += f"<tr><td><b>{esc(last['label'])}</b><br>{esc(last['domain'])}</td><td>2 % des rencontres</td><td>{esc(_psi_fx(last['fx']))} pendant {last['last_years']} ans</td><td>Le Solde</td></tr>"
    return f"<table class='grille'><tr><th>Puissance</th><th>Ce qui lui plaît</th><th>Paliers</th><th>Prix</th></tr>{l1}</table>"


def gen_psi_talents():
    """Talents psioniques par couche (data/psionics.json « talents »)."""
    d = charger("psionics.json")
    lignes = ""
    for couche, t in d["talents"].items():
        if couche.startswith("_"):
            continue
        for k, v in t.items():
            lignes += f"<tr><td>{esc(couche.capitalize())}</td><td>{esc(NOMS_COUCHE.get(k, k).capitalize())}</td><td><b>{esc(v['label'])}</b> : {inline(v.get('text', ''))}</td></tr>"
    return f"<table class='grille'><tr><th>Couche</th><th>Valeur</th><th>Talent</th></tr>{lignes}</table>"


def gen_tr_modes():
    """Réglages Transcendance et issue (data/transcendence.json)."""
    d = charger("transcendence.json")
    l1 = "".join(f"<tr><td><b>{esc(m['label'])}</b>{' (défaut au menu)' if m['id'] == d.get('default_mode') else ''}</td><td>{inline(m.get('text', ''))}</td></tr>" for m in d["modes"])
    l2 = "".join(f"<tr><td><b>{esc(m['label'])}</b>{' (défaut au menu)' if m['id'] == d.get('default_outcome') else ''}</td><td>{inline(m.get('text', ''))}</td></tr>" for m in d["outcomes"])
    return f"<table class='grille'><tr><th>Transcendance</th><th>Effet</th></tr>{l1}</table><table class='grille'><tr><th>Issue</th><th>Effet</th></tr>{l2}</table>"


def gen_tr_voies():
    """Les cinq voies (data/transcendence.json « paths »)."""
    d = charger("transcendence.json")
    src = {"resonance": "Résonance", "knowledge": "Savoir", "faith": "Fidèles", "pop": "Population", "industry": "Matériaux et énergie"}
    l1 = "".join(f"<tr><td><b>{esc(p['label'])}</b></td><td>{esc(src.get(p['source'], p['source']))}</td><td>{inline(p.get('text', ''))}</td></tr>" for p in d["paths"]["list"])
    return f"<table class='grille'><tr><th>Voie</th><th>Nourrie par</th><th>En bref</th></tr>{l1}</table>"


def gen_tr_oeuvres():
    """L'Œuvre de chaque voie (data/transcendence.json « paths », « oeuvre »)."""
    d = charger("transcendence.json")
    res = {"materials": "matériaux", "energy": "énergie", "influence": "influence", "food": "nourriture", "knowledge": "Savoir"}
    sites = {"capital": "le monde capital", "star": "un système tenu", "holy": "le monde saint", "ship": "un chantier spatial"}
    l1 = ""
    for p in d["paths"]["list"]:
        o = p["oeuvre"]
        et = " ; ".join(f"{', '.join(f'{v} {res.get(k, k)}' for k, v in s['cost'].items())} en {s['days']} j" for s in o["stages"])
        l1 += f"<tr><td><b>{esc(o['label'][:1].upper() + o['label'][1:])}</b><br>{esc(p['label'])}</td><td>{esc(sites.get(o['site'], o['site']))}</td><td>{esc(et)}</td></tr>"
    return f"<table class='grille'><tr><th>Œuvre</th><th>Où</th><th>Trois étapes</th></tr>{l1}</table>"


def gen_tr_talents():
    """Talents des peuples (data/transcendence.json « talents »)."""
    d = charger("transcendence.json")
    noms = {f["id"]: f.get("name", f["id"]) for f in charger("factions.json")}
    l1 = "".join(f"<tr><td>{esc(noms.get(k, k))}</td><td><b>{esc(v['label'])}</b> : {inline(v.get('text', ''))}</td></tr>" for k, v in d["talents"].items() if not k.startswith("_"))
    return f"<table class='grille'><tr><th>Peuple</th><th>Talent</th></tr>{l1}</table>"


def gen_mg_modes():
    """Réglages Mégastructures et ruines (data/megastructures.json)."""
    d = charger("megastructures.json")
    l1 = "".join(f"<tr><td><b>{esc(m['label'])}</b>{' (défaut au menu)' if m['id'] == d.get('default_mode') else ''}</td><td>{inline(m.get('text', ''))}</td></tr>" for m in d["modes"])
    l2 = "".join(f"<tr><td><b>{esc(m['label'])}</b>{' (défaut au menu)' if m['id'] == d.get('default_ruins') else ''}</td><td>{'aucune ruine' if not m.get('per_systems') else 'une ruine pour %d systèmes environ' % m['per_systems']}</td></tr>" for m in d["ruin_opts"])
    return f"<table class='grille'><tr><th>Mégastructures</th><th>Effet</th></tr>{l1}</table><table class='grille'><tr><th>Ruines</th><th>Combien</th></tr>{l2}</table>"


def gen_mg_catalogue():
    """Le catalogue des mégastructures (data/megastructures.json « kinds »)."""
    d = charger("megastructures.json")
    corps = {"star": "étoile", "planet": "planète libre", "colony": "colonie peuplée"}
    l1 = ""
    for k, v in d["kinds"].items():
        site = corps.get(v["site"].get("body", "star"), "")
        etapes = " · ".join(s["label"] for s in v["stages"])
        marque = " (superarme)" if v.get("weapon") else (" (trouvaille)" if v.get("ruin_only") else (" (classique)" if v.get("classic") else ""))
        l1 += f"<tr><td><b>{esc(v['label'])}</b>{esc(marque)}<br>ère {v['era']}, {esc(site)}</td><td>{inline(v.get('text', ''))}<br><i>{esc(etapes)}</i></td></tr>"
    return f"<table class='grille'><tr><th>Mégastructure</th><th>Ce qu'elle fait, et ses étapes</th></tr>{l1}</table>"


def gen_mg_talents():
    """Talents des peuples (data/megastructures.json « talents »)."""
    d = charger("megastructures.json")
    noms = {f["id"]: f.get("name", f["id"]) for f in charger("factions.json")}
    l1 = "".join(f"<tr><td>{esc(noms.get(k, k))}</td><td><b>{esc(v['label'])}</b> : {inline(v.get('text', ''))}</td></tr>" for k, v in d["talents"].items() if not k.startswith("_"))
    return f"<table class='grille'><tr><th>Peuple</th><th>Talent</th></tr>{l1}</table>"


def gen_kd_modes():
    """Réglages Échelle de Kardashev et rythme (data/kardashev.json)."""
    d = charger("kardashev.json")
    out = ""
    for titre, cle, defaut in [("Échelle de Kardashev", "modes", "default_mode"), ("Rythme", "paces", "default_pace")]:
        lignes = "".join(f"<tr><td><b>{esc(m['label'])}</b>{' (défaut au menu)' if m['id'] == d.get(defaut) else ''}</td><td>{inline(m.get('text', ''))}</td></tr>" for m in d[cle])
        out += f"<table class='grille'><tr><th>{titre}</th><th>Effet</th></tr>{lignes}</table>"
    return out


def gen_eco_modes():
    """Réglage Écologie (data/ecology.json)."""
    d = charger("ecology.json")
    lignes = "".join(f"<tr><td><b>{esc(m['label'])}</b>{' (défaut au menu)' if m['id'] == d.get('default_mode') else ''}</td><td>{inline(m.get('text', ''))}</td></tr>" for m in d["modes"])
    return f"<table class='grille'><tr><th>Écologie</th><th>Effet</th></tr>{lignes}</table>"


def gen_eco_types():
    """Vitalité des mondes vivants, basculement et reverdissement (data/ecology.json)."""
    d = charger("ecology.json")
    pt = charger("planet_types.json")
    nom = lambda k: pt.get(k, {}).get("label", k)
    l1 = ""
    for k, v in d["types"].items():
        bas = nom(d["shift"][k]) if k in d["shift"] else "—"
        rev = nom(d["regreen"][k]) if k in d["regreen"] else "—"
        l1 += f"<tr><td>{esc(nom(k))}</td><td>{v['vitality']}</td><td>{esc(bas)}</td><td>{esc(rev)}</td></tr>"
    return f"<table class='grille'><tr><th>Monde vivant</th><th>Vitalité</th><th>Bascule vers</th><th>Reverdit vers</th></tr>{l1}</table>"


def gen_eco_empreinte():
    """Empreinte des bâtiments et soins (data/ecology.json)."""
    d = charger("ecology.json")
    b = charger("buildings.json")
    l1 = "".join(f"<tr><td>{esc(b.get(k, {}).get('label', k))}</td><td>{v}</td></tr>" for k, v in sorted(d["footprint"].items(), key=lambda kv: -kv[1]))
    l1 += "".join(f"<tr><td>{esc(b.get(k, {}).get('label', k))}</td><td>−{v} (soins)</td></tr>" for k, v in d["care"].items())
    return f"<table class='grille'><tr><th>Bâtiment</th><th>Empreinte</th></tr>{l1}</table>"


def gen_eco_paliers():
    """Paliers de la biosphère (data/ecology.json « tiers »)."""
    d = charger("ecology.json")
    def eff(t):
        out = []
        if t["food_pct"]:
            out.append(f"{t['food_pct']:+d} % nourriture")
        if t["stab"]:
            out.append(f"{t['stab']:+d} stabilité")
        if t["growth_pct"] <= -100:
            out.append("croissance arrêtée")
        elif t["growth_pct"]:
            out.append(f"{t['growth_pct']:+d} % croissance")
        return ", ".join(out) or "aucun"
    l1 = "".join(f"<tr><td><b>{esc(t['label'])}</b></td><td>{t['min']} et plus</td><td>{esc(eff(t))}</td></tr>" for t in d["tiers"])
    return f"<table class='grille'><tr><th>Palier</th><th>Biosphère</th><th>Effets</th></tr>{l1}</table>"


def gen_eco_doctrines():
    """Doctrines environnementales (data/ecology.json « doctrines »)."""
    d = charger("ecology.json")
    l1 = "".join(f"<tr><td><b>{esc(x['label'])}</b>{' (au départ)' if x['id'] == d.get('default_doctrine') else ''}</td><td>{inline(x.get('text', ''))}</td></tr>" for x in d["doctrines"])
    return f"<table class='grille'><tr><th>Doctrine</th><th>Effet</th></tr>{l1}</table>"


def gen_kd_echelle():
    """Ancres de puissance, verrous et Rayonnement de chaque type (data/kardashev.json)."""
    d = charger("kardashev.json")
    a = d["power"]["anchors"]
    lk = d["locks"]
    verrous = ["aucun",
               f"la technologie Fusion compacte et {lk['1']['capital_buildings']} bâtiments sur un monde de la capitale",
               f"une Sphère de Dyson achevée ou {lk['2']['swarms']} Essaims de Dyson achevés",
               f"le verrou II, {lk['3']['great']} grandes mégastructures achevées (ère IV et plus) dont {lk['3']['era5']} de l'ère V, et {lk['3']['systems_pct']} % des systèmes de la galaxie"]
    l1 = ""
    for t in range(4):
        val = "0,70" if t == 0 else f"{t},00"
        l1 += f"<tr><td><b>{val}</b><br>{esc(d['titles'][t])}</td><td>{a[t]:,}".replace(",", " ") + f"</td><td>{esc(verrous[t])}</td><td>+{d['culture_pct'][t]} %</td></tr>"
    return f"<table class='grille'><tr><th>Indice</th><th>Puissance (rythme Normal)</th><th>Verrou</th><th>Rayonnement</th></tr>{l1}</table>"


def gen_kd_capture():
    """Puissance captée par étape de mégastructure (data/kardashev.json « power.capture »)."""
    d = charger("kardashev.json")
    noms = {k: v["label"] for k, v in charger("megastructures.json")["kinds"].items()}
    noms.update({"era4": "Autre grande mégastructure de l'ère IV", "era5": "Autre mégastructure de l'ère V"})
    l1 = "".join(f"<tr><td>{esc(noms.get(k, k))}</td><td>{v}</td></tr>" for k, v in d["power"]["capture"].items())
    return f"<table class='grille'><tr><th>Mégastructure</th><th>Puissance par étape achevée</th></tr>{l1}</table>"


def gen_kd_prerogatives():
    """Les prérogatives de chaque demi-palier (data/kardashev.json « perks »)."""
    d = charger("kardashev.json")
    lv = d["levels"]
    l1 = ""
    for n in range(1, len(lv) + 1):
        ps = [v for k, v in d["perks"].items() if not k.startswith("_") and v.get("level") == n]
        val = f"{lv[n - 1] // 100},{lv[n - 1] % 100:02d}"
        l1 += f"<tr><td><b>{val}</b></td><td>" + "<br>".join(f"<b>{esc(p['label'])}</b> : {inline(p.get('text', ''))}" for p in ps) + "</td></tr>"
    return f"<table class='grille'><tr><th>Palier</th><th>Prérogatives (une au choix)</th></tr>{l1}</table>"


def gen_ar_modes():
    """Réglage Archéologie (data/archaeology.json)."""
    d = charger("archaeology.json")
    l1 = "".join(f"<tr><td><b>{esc(m['label'])}</b>{' (défaut au menu)' if m['id'] == d.get('default_mode') else ''}</td><td>{inline(m.get('text', ''))}</td></tr>" for m in d["modes"])
    return f"<table class='grille'><tr><th>Archéologie</th><th>Effet</th></tr>{l1}</table>"


def gen_ar_types():
    """Les sept types de sites (data/archaeology.json « site_types »)."""
    d = charger("archaeology.json")
    lab = {"stability": "stabilité", "production_pct": "production", "curio_power": "puissance d'expédition", "damage_pct": "dégâts",
           "growth_pct": "croissance", "repair_pct": "réparations", "knowledge": "Savoir", "influence": "influence", "energy": "énergie",
           "materials": "matériaux", "food": "nourriture"}
    def fx(f):
        out = []
        for k, v in f.items():
            if isinstance(v, dict):
                out += [f"{lab.get(k, k)} {lab.get(kk, kk)} +{vv} %" for kk, vv in v.items()]
            else:
                out.append(f"{lab.get(k, k)} +{v}{' %' if k.endswith('_pct') else ''}")
        return ", ".join(out)
    l1 = ""
    for k, v in d["site_types"].items():
        if k.startswith("_"):
            continue
        res = ", ".join(f"{n} {lab.get(r, r)}" for r, n in v.get("res", {}).items())
        l1 += f"<tr><td><b>{esc(v['label'])}</b></td><td>{inline(v.get('text', ''))}</td><td>{esc(res)}</td><td>{esc(fx(v.get('antiq_fx', {})))}</td></tr>"
    return f"<table class='grille'><tr><th>Type</th><th>Ce qu'on y trouve</th><th>Exploiter</th><th>Antiquité</th></tr>{l1}</table>"


def gen_ar_actions():
    """Actions de fragments (data/archaeology.json « actions »)."""
    d = charger("archaeology.json")
    l1 = "".join(f"<tr><td><b>{esc(v['label'])}</b></td><td>{v['cost']} fragments, puis {v['cd']} jours</td><td>{inline(v.get('text', ''))}</td></tr>" for k, v in d["actions"].items() if not k.startswith("_"))
    return f"<table class='grille'><tr><th>Action</th><th>Coût et délai</th><th>Effet</th></tr>{l1}</table>"


def gen_ar_disparus():
    """Les cinq Disparus (data/archaeology.json « disparus »)."""
    d = charger("archaeology.json")
    crises = charger("crises.json").get("kinds", {})
    l1 = ""
    for k, v in d["disparus"].items():
        if k.startswith("_"):
            continue
        chute = crises.get(v.get("fall", ""), {}).get("name", v.get("fall", ""))
        l1 += (f"<tr><td><b>{esc(v['label'])}</b><br><i>Chute : {esc(chute)}</i></td><td>{inline(v.get('lore', ''))}</td>"
               f"<td><b>{esc(v['civ']['label'])}</b> : {inline(v['civ']['text'])}<br><b>{esc(v['ship']['label'])}</b> : {inline(v['ship']['text'])}<br>"
               f"<b>{esc(v['reco']['label'])}</b> : {inline(v['reco']['text'])}</td></tr>")
    return f"<table class='grille'><tr><th>Disparu</th><th>Ce qu'on en sait</th><th>Technologies anciennes et Reconstitution</th></tr>{l1}</table>"


def gen_ar_talents():
    """Talents des peuples (data/archaeology.json « talents »)."""
    d = charger("archaeology.json")
    noms = {f["id"]: f.get("name", f["id"]) for f in charger("factions.json")}
    l1 = "".join(f"<tr><td>{esc(noms.get(k, k))}</td><td><b>{esc(v['label'])}</b> : {inline(v.get('text', ''))}</td></tr>" for k, v in d["talents"].items() if not k.startswith("_"))
    return f"<table class='grille'><tr><th>Peuple</th><th>Talent</th></tr>{l1}</table>"


def gen_wf_modes():
    """Réglages Forge des mondes et mondes-reliquaires (data/worldforge.json)."""
    d = charger("worldforge.json")
    l1 = "".join(f"<tr><td><b>{esc(m['label'])}</b>{' (défaut au menu)' if m['id'] == d.get('default_mode') else ''}</td><td>{inline(m.get('text', ''))}</td></tr>" for m in d["modes"])
    l2 = "".join(f"<tr><td><b>{esc(m['label'])}</b>{' (défaut au menu)' if m['id'] == d.get('default_ancients') else ''}</td><td>{'aucun' if not m.get('per') else 'un pour %d systèmes environ' % m['per']}</td></tr>" for m in d["ancient_opts"])
    return f"<table class='grille'><tr><th>Forge des mondes</th><th>Effet</th></tr>{l1}</table><table class='grille'><tr><th>Mondes-reliquaires</th><th>Combien</th></tr>{l2}</table>"


def gen_wf_ops():
    """Les chantiers planétaires (data/worldforge.json « ops »)."""
    d = charger("worldforge.json")
    techs = {k: v.get("label", k) for k, v in charger("technologies.json")["technologies"].items()}
    noms = {"materials": "matériaux", "energy": "énergie", "influence": "influence"}
    l1 = ""
    for k, v in d["ops"].items():
        cout = ", ".join(f"{n} {noms.get(r, r)}" for r, n in v.get("cost", {}).items())
        if v.get("mass"):
            cout += f", {v['mass']} Masse"
        if "days_base" in v:
            duree = f"{v['days_base'] + v['days_per_size']} à {v['days_base'] + 5 * v['days_per_size']} jours"
        else:
            duree = f"{v.get('days', 0)} jours"
        tech = " + ".join(techs.get(t, t) for t in v.get("tech", []))
        l1 += f"<tr><td><b>{esc(v['label'])}</b><br><i>{esc(tech)}</i></td><td>{esc(cout)}<br>{esc(duree)}</td><td>{inline(v.get('text', ''))}</td></tr>"
    return f"<table class='grille'><tr><th>Chantier</th><th>Coût et durée</th><th>Ce qu'il fait</th></tr>{l1}</table>"


def gen_wf_instant():
    """Les ordres immédiats (data/worldforge.json « instant »)."""
    d = charger("worldforge.json")
    l1 = "".join(f"<tr><td><b>{esc(v['label'])}</b></td><td>{inline(v.get('text', ''))}</td></tr>" for k, v in d["instant"].items() if not k.startswith("_"))
    return f"<table class='grille'><tr><th>Ordre</th><th>Effet</th></tr>{l1}</table>"


def gen_wf_talents():
    """Talents des peuples (data/worldforge.json « talents »)."""
    d = charger("worldforge.json")
    noms = {f["id"]: f.get("name", f["id"]) for f in charger("factions.json")}
    l1 = "".join(f"<tr><td>{esc(noms.get(k, k))}</td><td><b>{esc(v['label'])}</b> : {inline(v.get('text', ''))}</td></tr>" for k, v in d["talents"].items() if not k.startswith("_"))
    return f"<table class='grille'><tr><th>Peuple</th><th>Talent</th></tr>{l1}</table>"


def gen_lw_modes():
    """Réglages Mondes vivants et Monde-Ego (data/livingworlds.json)."""
    d = charger("livingworlds.json")
    l1 = "".join(f"<tr><td><b>{esc(m['label'])}</b>{' (défaut au menu)' if m['id'] == d.get('default_mode') else ''}</td><td>{inline(m.get('text', ''))}</td></tr>" for m in d["modes"])
    l2 = "".join(f"<tr><td><b>{esc(m['label'])}</b>{' (défaut au menu)' if m['id'] == d.get('default_ego') else ''}</td><td>{inline(m.get('text', ''))}</td></tr>" for m in d["ego_opts"])
    return f"<table class='grille'><tr><th>Mondes vivants</th><th>Effet</th></tr>{l1}</table><table class='grille'><tr><th>Monde-Ego</th><th>Effet</th></tr>{l2}</table>"


def gen_lw_paliers():
    """Les cinq paliers d'humeur et leurs effets sur la colonie de l'hôte (data/livingworlds.json « rules.tiers »)."""
    d = charger("livingworlds.json")
    l1 = ""
    bas = -100
    for t in d["rules"]["tiers"]:
        l1 += f"<tr><td><b>{esc(t['label'])}</b></td><td>{bas} à {t['max']}</td><td>{t['pop']:+d}</td><td>{t['stab']:+d}</td><td>{t['food']:+d}</td></tr>"
        bas = t["max"] + 1
    return f"<table class='grille'><tr><th>Palier</th><th>Humeur</th><th>Population</th><th>Stabilité</th><th>Nourriture / mois</th></tr>{l1}</table>"


def gen_lw_origines():
    """Origines et tempéraments (catalogues ouverts, data/livingworlds.json)."""
    d = charger("livingworlds.json")
    faune = {k: v.get("label", k) for k, v in charger("creatures.json").get("species", {}).items()}
    l1 = "".join(f"<tr><td><b>{esc(v['label'])}</b></td><td>{inline(v.get('text', ''))}</td><td>{esc(faune.get(v.get('antibody', ''), v.get('antibody', '')))}</td></tr>" for k, v in d["origins"].items() if not k.startswith("_"))
    l2 = "".join(f"<tr><td><b>{esc(v['label'])}</b></td><td>{inline(v.get('text', ''))}</td></tr>" for k, v in d["temperaments"].items() if not k.startswith("_"))
    return f"<table class='grille'><tr><th>Origine</th><th>Ce qu'il est</th><th>Anticorps</th></tr>{l1}</table><table class='grille'><tr><th>Tempérament</th><th>Ce qu'il aime</th></tr>{l2}</table>"


def gen_lw_demandes():
    """Les demandes d'un monde vivant (data/livingworlds.json « requests »)."""
    d = charger("livingworlds.json")
    l1 = "".join(f"<tr><td><b>{esc(v['label'])}</b></td><td>{inline(v.get('ask', '').replace('{lw_rival}', 'un ennemi').replace('{lw_people}', 'un autre peuple'))}</td></tr>" for k, v in d["requests"].items() if not k.startswith("_"))
    return f"<table class='grille'><tr><th>Demande</th><th>Ce qu'il veut</th></tr>{l1}</table>"


def gen_lw_talents():
    """Talents des peuples (data/livingworlds.json « talents »)."""
    d = charger("livingworlds.json")
    noms = {f["id"]: f.get("name", f["id"]) for f in charger("factions.json")}
    l1 = "".join(f"<tr><td>{esc(noms.get(k, k))}</td><td><b>{esc(v['label'])}</b> : {inline(v.get('text', ''))}</td></tr>" for k, v in d["talents"].items() if not k.startswith("_"))
    return f"<table class='grille'><tr><th>Peuple</th><th>Talent</th></tr>{l1}</table>"


def gen_an_familles():
    """Les dix familles d'annonces et leurs types (data/announcements.json)."""
    d = charger("announcements.json")
    grav = {g["id"]: g["label"] for g in d["gravities"]}
    l1 = ""
    for fid, f in d["families"].items():
        if fid.startswith("_"):
            continue
        types = []
        for k, v in d["kinds"].items():
            if k.startswith("_") or v.get("family") != fid:
                continue
            g = v.get("g", [1, 0, 0])
            types.append(f"{esc(v.get('title', k))} <i>({grav.get(g[0], '?')} / {grav.get(g[1], '?')} / {grav.get(g[2], '?')})</i>")
        l1 += f"<tr><td><b>{esc(f['label'])}</b><br><i>{inline(f.get('lead', ''))}</i></td><td>{'<br>'.join(types)}</td></tr>"
    return f"<table class='grille'><tr><th>Famille</th><th>Types (vous concerne / un voisin connu / lointain)</th></tr>{l1}</table>"


def gen_an_presets():
    """Préréglages des annonces (data/announcements.json « presets »)."""
    d = charger("announcements.json")
    l1 = "".join(f"<tr><td><b>{esc(v['label'])}</b>{' (défaut)' if k == 'stratege' else ''}</td><td>{inline(v.get('text', ''))}</td></tr>" for k, v in d["presets"].items())
    return f"<table class='grille'><tr><th>Préréglage</th><th>Effet</th></tr>{l1}</table>"


def gen_ct_modes():
    """Réglages Contact, Lointains et Issue (data/contact.json)."""
    d = charger("contact.json")
    out = ""
    for titre, cle, defaut in [("Contact", "modes", "default_mode"), ("Lointains", "nature_modes", "default_nature_mode"), ("Issue", "outcomes", "default_outcome")]:
        lignes = "".join(f"<tr><td><b>{esc(m['label'])}</b>{' (défaut au menu)' if m['id'] == d.get(defaut) else ''}</td><td>{inline(m.get('text', ''))}</td></tr>" for m in d[cle])
        out += f"<table class='grille'><tr><th>{titre}</th><th>Effet</th></tr>{lignes}</table>"
    return out


def gen_ct_couches():
    """Les quatre couches du Signal (data/contact.json « layers »)."""
    d = charger("contact.json")
    voix = d.get("names", {}).get("default", {})
    l1 = "".join(f"<tr><td><b>{esc(c['label'])}</b><br>{c['at'] // 10} %</td><td>{inline(c.get('text', ''))}</td><td><i>« {esc(voix.get(c['id'], ''))} »</i></td></tr>" for c in d["layers"])
    return f"<table class='grille'><tr><th>Couche</th><th>Ce qu'elle apporte</th><th>Ce qu'on y lit</th></tr>{l1}</table>"


def gen_ct_natures():
    """Les cinq natures des Lointains (data/contact.json « natures »)."""
    d = charger("contact.json")
    issue = {"victory": "Victoire de Contact, partagée avec le Consortium", "archive": "Une archive répond : victoire douce-amère",
             "trap": "Victoire si les Plans ont été audités ; sinon l'émetteur devient l'Hôte", "loop": "Victoire : la boucle se ferme",
             "crisis": "Pas de victoire : l'Outre-Nuit arrive en trois ans et vise l'émetteur"}
    l1 = "".join(f"<tr><td><b>{esc(n['label'])}</b><br>poids {n.get('weight', 0)}</td><td>{inline(n.get('text', ''))}</td><td>{inline(n.get('hint', ''))}</td><td>{esc(issue.get(n.get('outcome', ''), ''))}</td></tr>" for n in d["natures"]["list"])
    return f"<table class='grille'><tr><th>Nature</th><th>Qui ils sont</th><th>Indices</th><th>Si l'on répond</th></tr>{l1}</table>"


def gen_ct_talents():
    """Talents des peuples et nom du Signal (data/contact.json « talents », « names »)."""
    d = charger("contact.json")
    noms = {f["id"]: f.get("name", f["id"]) for f in charger("factions.json")}
    signal = d.get("names", {})
    l1 = "".join(f"<tr><td>{esc(noms.get(k, k))}</td><td><i>{esc(signal.get(k, {}).get('name', ''))}</i></td><td><b>{esc(v['label'])}</b> : {inline(v.get('text', ''))}</td></tr>" for k, v in d["talents"].items() if not k.startswith("_"))
    return f"<table class='grille'><tr><th>Peuple</th><th>Nom du Signal</th><th>Talent</th></tr>{l1}</table>"


def _numeros_chapitres():
    """Fichier de chapitre (sans .md) -> son numéro (« 15 », « B »)."""
    out = {}
    for nom in sorted(os.listdir(os.path.join(ICI, "chapitres"))):
        if nom.endswith(".md"):
            meta, _ = lire_chapitre(os.path.join(ICI, "chapitres", nom))
            if meta.get("numero"):
                out[nom[:-3]] = meta["numero"]
    return out


def gen_lexique():
    """Annexe B, tirée du glossaire du jeu (data/glossary.json), comme le Codex en jeu."""
    g = charger("glossary.json")
    nums = _numeros_chapitres()
    lignes = ""
    for t in g["terms"]:
        nom = t["name"] + (f" ({t['qualifier']})" if t.get("qualifier") else "")
        ch = ", ".join(nums.get(c, "") for c in t.get("chapters", []) if nums.get(c))
        lignes += f"<tr><td><b>{esc(nom)}</b></td><td>{inline(t['summary'])}</td><td class='court'>{esc(ch)}</td></tr>"
    return f"<table class='grille lexique'><tr><th>Terme</th><th>En bref</th><th>Ch.</th></tr>{lignes}</table>"


GENERATEURS = {
    "ressources": gen_ressources, "stabilite": gen_stabilite, "courants": gen_courants,
    "faune": gen_faune, "gardiens": gen_gardiens, "technologies": gen_technologies,
    "peuples": gen_peuples, "prompts": gen_prompts,
    "luxes": gen_luxes, "strategiques": gen_strategiques,
    "lois": gen_lois, "reliques": gen_reliques, "logistique": gen_logistique,
    "terrains": gen_terrains, "terrain_talents": gen_terrain_talents,
    "anciennes": gen_anciennes, "anciennes_batiments": gen_anciennes_batiments,
    "mineurs_modes": gen_mineurs_modes, "mineurs": gen_mineurs, "mineurs_quetes": gen_mineurs_quetes,
    "mineurs_accords": gen_mineurs_accords, "mineurs_programmes": gen_mineurs_programmes,
    "mineurs_talents": gen_mineurs_talents,
    "rayonnement_modes": gen_rayonnement_modes, "rayonnement_paliers": gen_rayonnement_paliers,
    "rayonnement_merveilles": gen_rayonnement_merveilles, "rayonnement_talents": gen_rayonnement_talents,
    "merveilles_modes": gen_merveilles_modes, "merveilles": gen_merveilles,
    "hauts_faits_modes": gen_hauts_faits_modes, "hauts_faits": gen_hauts_faits,
    "hauts_faits_recompenses": gen_hauts_faits_recompenses, "hauts_faits_trophees": gen_hauts_faits_trophees,
    "souverains_modes": gen_souverains_modes, "cour_modes": gen_cour_modes, "cour_vocations": gen_cour_vocations,
    "cour_offices": gen_cour_offices, "cour_talents": gen_cour_talents, "successions": gen_successions, "archetypes_regne": gen_archetypes_regne,
    "surnoms": gen_surnoms, "ambitions_souverain": gen_ambitions, "heritages": gen_heritages,
    "admin_modes": gen_admin_modes, "admin_efforts": gen_admin_efforts, "admin_talents": gen_admin_talents,
    "fisc_modes": gen_fisc_modes, "fisc_crans": gen_fisc_crans, "fisc_cotes": gen_fisc_cotes,
    "fisc_paliers": gen_fisc_paliers, "fisc_talents": gen_fisc_talents,
    "priv_modes": gen_priv_modes, "priv_impot": gen_priv_impot, "priv_secteurs": gen_priv_secteurs,
    "priv_chartes": gen_priv_chartes, "priv_talents": gen_priv_talents,
    "port_modes": gen_port_modes, "port_niveaux": gen_port_niveaux, "port_talents": gen_port_talents,
    "def_modes": gen_def_modes, "def_stations": gen_def_stations, "def_elements": gen_def_elements,
    "def_talents": gen_def_talents,
    "st_modes": gen_st_modes, "st_modules": gen_st_modules, "st_talents": gen_st_talents,
    "gen_modes": gen_gen_modes, "gen_techs": gen_gen_techs, "gen_voies": gen_gen_voies, "gen_traits": gen_gen_traits,
    "gen_paths": gen_gen_paths, "gen_talents": gen_gen_talents,
    "psi_modes": gen_psi_modes, "psi_niveaux": gen_psi_niveaux, "psi_techs": gen_psi_techs, "psi_pouvoirs": gen_psi_pouvoirs,
    "psi_felures": gen_psi_felures, "psi_postures": gen_psi_postures, "psi_visions": gen_psi_visions, "psi_puissances": gen_psi_puissances,
    "psi_talents": gen_psi_talents,
    "mg_modes": gen_mg_modes, "mg_catalogue": gen_mg_catalogue, "mg_talents": gen_mg_talents,
    "an_familles": gen_an_familles, "an_presets": gen_an_presets,
    "eco_modes": gen_eco_modes, "eco_types": gen_eco_types, "eco_empreinte": gen_eco_empreinte, "eco_paliers": gen_eco_paliers, "eco_doctrines": gen_eco_doctrines,
    "kd_modes": gen_kd_modes, "kd_echelle": gen_kd_echelle, "kd_capture": gen_kd_capture, "kd_prerogatives": gen_kd_prerogatives,
    "ar_modes": gen_ar_modes, "ar_types": gen_ar_types, "ar_actions": gen_ar_actions, "ar_disparus": gen_ar_disparus, "ar_talents": gen_ar_talents, "wf_modes": gen_wf_modes, "wf_ops": gen_wf_ops, "wf_instant": gen_wf_instant, "wf_talents": gen_wf_talents,
    "lw_modes": gen_lw_modes, "lw_paliers": gen_lw_paliers, "lw_origines": gen_lw_origines, "lw_demandes": gen_lw_demandes, "lw_talents": gen_lw_talents,
    "ct_modes": gen_ct_modes, "ct_couches": gen_ct_couches, "ct_natures": gen_ct_natures, "ct_talents": gen_ct_talents,
    "tr_modes": gen_tr_modes, "tr_voies": gen_tr_voies, "tr_oeuvres": gen_tr_oeuvres, "tr_talents": gen_tr_talents,
    "lexique": gen_lexique,
    "portail_modes": gen_portail_modes, "portail_batiments": gen_portail_batiments, "portail_talents": gen_portail_talents,
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


# --- Codex de l'Archonte en jeu (data/codex_manual.json) ---------------------
# Le jeu lit le manuel découpé en articles (une section ### par article), avec ses tableaux déjà
# calculés depuis les données et ses fragments de lore : le manuel et le Codex disent la même chose.
from html.parser import HTMLParser

CODEX_SANS = {"22a-lexique", "25-encarts"}


class _VersBBCode(HTMLParser):
    """HTML du manuel -> BBCode de RichTextLabel (Godot)."""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.out = []
        self.listes = []
        self.table = None
        self.cell = None
        self.saute = 0

    def _w(self, t):
        if self.saute:
            return
        if self.cell is not None:
            self.cell.append(t)
        else:
            self.out.append(t)

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        cls = a.get("class", "") or ""
        if self.saute:
            if tag in ("figure", "div"):
                self.saute += 1
            return
        if tag == "figure" and "mj" in cls:
            self.saute = 1
            return
        if tag == "img" and a.get("src", "").startswith("../../"):
            self._w("[[CAPTURE:" + a["src"][6:] + "]]")
        elif tag in ("strong", "b"):
            self._w("[b]")
        elif tag in ("em", "i", "cite"):
            self._w("[i]")
        elif tag == "span" and "kbd" in cls:
            self._w("[b]")
        elif tag in ("ul", "ol"):
            self.listes.append([tag, 0])
        elif tag == "li":
            if self.listes:
                self.listes[-1][1] += 1
                self._w("\n" + ("   " * (len(self.listes) - 1)) + ("• " if self.listes[-1][0] == "ul" else f"{self.listes[-1][1]}. "))
        elif tag in ("h3", "h4"):
            self._w("\n[b]")
        elif tag == "br":
            self._w("\n")
        elif tag == "table":
            self.table = []
        elif tag == "tr" and self.table is not None:
            self.table.append([])
        elif tag in ("td", "th") and self.table is not None:
            self.cell = ["[b]"] if tag == "th" else []
        elif tag == "aside":
            lbl = {"conseil": "Conseil", "marge": "Note du commandant", "chronique": "Fragment", "transmission": "Transmission", "attention": "Attention"}
            k = next((v for c, v in lbl.items() if c in cls), "")
            self._w("\n\n[i]" + (f"[b]{k}[/b] · " if k else ""))
        elif tag == "figcaption":
            self._w("\n[i]")
        elif tag == "div" and ("fiche-t" in cls or "lbl" in cls):
            self._w("\n[b]")

    def handle_endtag(self, tag):
        if self.saute:
            if tag in ("figure", "div"):
                self.saute -= 1
            return
        if tag in ("strong", "b"):
            self._w("[/b]")
        elif tag in ("em", "i", "cite"):
            self._w("[/i]")
        elif tag == "span":
            # Seules les touches ouvrent un [b] sur un span : on le referme si besoin.
            buf = self.cell if self.cell is not None else self.out
            if buf and "[b]" in "".join(buf[-3:]) and not "".join(buf[-3:]).endswith("[/b]"):
                self._w("[/b]")
        elif tag in ("ul", "ol"):
            if self.listes:
                self.listes.pop()
            if not self.listes:
                self._w("\n")
        elif tag in ("h3", "h4"):
            self._w("[/b]\n")
        elif tag == "p":
            self._w("\n\n")
        elif tag in ("td", "th") and self.table is not None and self.cell is not None:
            if tag == "th":
                self.cell.append("[/b]")
            self.table[-1].append("".join(self.cell).strip())
            self.cell = None
        elif tag == "table" and self.table is not None:
            rows = [r for r in self.table if r]
            n = max((len(r) for r in rows), default=0)
            t = f"\n[table={n}]" if n else ""
            for r in rows:
                for c in r + [""] * (n - len(r)):
                    t += f"[cell padding=6,3,6,3 border=#ffffff1c]{c}[/cell]"
            self.table = None
            self.out.append(t + ("[/table]\n" if n else ""))
        elif tag == "aside":
            self._w("[/i]\n")
        elif tag == "figcaption":
            self._w("[/i]\n")
        elif tag == "div":
            pass

    def handle_data(self, data):
        if self.saute:
            return
        data = data.replace("[", "[lb]")
        if self.cell is None and not data.strip() and "\n" in data:
            return
        self._w(data)

    def texte(self):
        t = "".join(self.out)
        # [b] restés ouverts dans un div de titre de fiche : on les referme en fin de ligne.
        t = re.sub(r"\n\[b\]([^\[\n]*?)(?=\n)", lambda m: "\n[b]" + m.group(1) + "[/b]", t)
        t = re.sub(r"[ \t]+\n", "\n", t)
        t = re.sub(r"\n{3,}", "\n\n", t)
        return t.strip()


def _bbcode(html_):
    p = _VersBBCode()
    p.feed(html_)
    p.close()
    return p.texte()


def construire_codex():
    """Écrit data/codex_manual.json : chapitres découpés en sections, et fragments de lore."""
    chapitres, fragments = [], []
    for nom in sorted(os.listdir(os.path.join(ICI, "chapitres"))):
        if not nom.endswith(".md") or nom[:-3] in CODEX_SANS:
            continue
        meta, brut = lire_chapitre(os.path.join(ICI, "chapitres", nom))
        fid = nom[:-3]
        if meta.get("type") == "partie":
            continue
        if meta.get("epigraphe"):
            fragments.append({"id": f"{fid}:epi", "chapter": fid, "kind": "epigraphe",
                              "source": meta.get("signature", ""), "text": meta["epigraphe"]})
        for k, m in enumerate(re.finditer(r"^::: (chronique|transmission|marge)(.*?)\n(.*?)^:::$", brut, re.M | re.S)):
            arg = m.group(2).strip()
            src = {"chronique": arg.split("|")[0], "transmission": arg, "marge": "Notes du commandant A. Varrek"}[m.group(1)]
            sig = arg.split("|")[1] if m.group(1) == "chronique" and "|" in arg else ""
            corps = re.sub(r"\s*\n\s*", " ", m.group(3).strip())
            fragments.append({"id": f"{fid}:{k}", "chapter": fid, "kind": m.group(1), "source": src, "signature": sig,
                              "text": re.sub(r"\*\*(.+?)\*\*", r"\1", re.sub(r"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)", r"\1", corps))})
        morceaux = re.split(r"^### (.+)$", brut, flags=re.M)
        sections = []
        for i in range(0, len(morceaux), 2):
            titre = meta.get("titre", fid) if i == 0 else morceaux[i - 1].strip()
            texte = _bbcode(rendre(morceaux[i]))
            if not texte.strip():
                continue
            caps = re.findall(r"\[\[CAPTURE:([^\]]+)\]\]", texte)
            texte = re.sub(r"\[\[CAPTURE:[^\]]+\]\]", "", texte).strip()
            sid = re.sub(r"\W+", "-", titre.lower()).strip("-")
            sections.append({"id": f"{fid}#{sid}" if i else fid, "title": titre if i else "Présentation",
                             "text": texte, "captures": caps})
        chapitres.append({"file": fid, "num": meta.get("numero", ""), "label": meta.get("etiquette", "Chapitre"),
                          "title": meta.get("titre", fid), "epigraph": meta.get("epigraphe", ""),
                          "signature": meta.get("signature", ""), "secret": fid.startswith("20-"), "sections": sections})
    sortie = os.path.join(DATA, "codex_manual.json")
    with open(sortie, "w", encoding="utf-8") as f:
        json.dump({"_doc": "Généré par docs/manuel/build.py --codex : ne pas modifier à la main.", "edition": EDITION,
                   "chapters": chapitres, "fragments": fragments}, f, ensure_ascii=False, indent=0)
    print(f"codex_manual.json écrit ({len(chapitres)} chapitres, {sum(len(c['sections']) for c in chapitres)} sections, {len(fragments)} fragments)")


if __name__ == "__main__":
    if "--codex" in sys.argv:
        construire_codex()
        sys.exit(0)
    clair = "--clair" in sys.argv
    sortie = construire(clair)
    ecrire_prompts_md()
    construire_codex()
    if "--html" not in sys.argv:
        pdf = os.path.join(ICI, "manuel-clair.pdf" if clair else "manuel.pdf")
        subprocess.check_call(["node", os.path.join(ICI, "print.js"), sortie, pdf])
        print("PDF :", pdf)
