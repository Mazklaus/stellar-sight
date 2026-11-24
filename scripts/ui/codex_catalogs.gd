class_name CodexCatalogs
extends RefCounted
## Les fiches du Codex lues directement dans les données du jeu (glossaire en jeu, prop. 5 et 26) :
## rien n'est recopié, une donnée changée change sa fiche. Chaque fiche a un identifiant
## « cat:<catalogue>:<clé> », un nom, une famille, un résumé, un texte et quelques lignes chiffrées.
## Les fiches « locked » (peuples, anciennes, faune, gardiens, crises) restent cachées en partie tant
## qu'on ne les a pas rencontrées (CodexProgress) ; les gardiens et les crises sont des secrets.

## Catalogues dans l'ordre du Codex : id, famille, libellé, verrouillé, secret, reconnu dans les textes.
const CATALOGS := [
	{"id": "peuples", "family": "univers", "label": "Les huit peuples", "locked": true, "link": true},
	{"id": "anciennes", "family": "univers", "label": "Puissances anciennes", "locked": true, "link": true},
	{"id": "faune", "family": "bestiaire", "label": "Faune de l'espace", "locked": true, "link": true},
	{"id": "gardiens", "family": "bestiaire", "label": "Gardiens", "locked": true, "secret": true, "link": true},
	{"id": "crises", "family": "bestiaire", "label": "Crises de fin de partie", "locked": true, "secret": true, "link": true},
	{"id": "technologies", "family": "meca", "label": "Technologies"},
	{"id": "batiments", "family": "meca", "label": "Bâtiments"},
	{"id": "mondes", "family": "meca", "label": "Types de mondes"},
	{"id": "terrains", "family": "meca", "label": "Terrains"},
	{"id": "vaisseaux", "family": "meca", "label": "Vaisseaux"},
	{"id": "merveilles", "family": "meca", "label": "Merveilles", "link": true},
	{"id": "reliques", "family": "meca", "label": "Reliques"},
	{"id": "biens", "family": "meca", "label": "Luxes et stratégiques"},
	{"id": "lois", "family": "meca", "label": "Lois des courants"},
	{"id": "pouvoirs", "family": "meca", "label": "Pouvoirs psioniques"},
]

static var _cache: Dictionary = {}
static var _json: Dictionary = {}


static func _data(file: String) -> Variant:
	if not _json.has(file):
		var f := FileAccess.open("res://" + file, FileAccess.READ)
		_json[file] = JSON.parse_string(f.get_as_text()) if f else {}
	return _json[file]


static func catalog_def(cid: String) -> Dictionary:
	for c: Dictionary in CATALOGS:
		if String(c["id"]) == cid:
			return c
	return {}


## Fiches d'un catalogue, dans l'ordre des données.
static func entries(cid: String) -> Array:
	if _cache.has(cid):
		return _cache[cid]
	var out: Array = []
	match cid:
		"peuples":
			var lore: Dictionary = _data("docs/manuel/peuples.json")
			for f: Dictionary in _data("data/factions.json"):
				var l: Dictionary = lore.get(String(f["id"]), {})
				var body := String(l.get("histoire", ""))
				if l.has("victoire"):
					body += "\n\n[b]Victoire de peuple.[/b] " + String(l["victoire"])
				if l.has("conseil"):
					body += "\n\n[b]Conseil.[/b] " + String(l["conseil"])
				out.append(_e(cid, String(f["id"]), String(f["name"]), String(f.get("short", "")), body,
						[["Registre", String(f.get("registre", ""))], ["Difficulté", String(l.get("difficulte", ""))]],
						String(l.get("devise", "")), [String(f["name"])], ["17-peuples"]))
		"anciennes":
			var kinds: Dictionary = _data("data/ancients.json").get("kinds", {})
			for k: String in kinds:
				var a: Dictionary = kinds[k]
				out.append(_e(cid, k, String(a["name"]), String(a.get("blurb", a.get("short", ""))),
						"[b]Ce qui la fâche.[/b] %s\n\n[b]Ce qu'elle veut.[/b] %s" % [String(a.get("angers_text", "")), String(a.get("wants_text", ""))],
						[["Registre", String(a.get("register", ""))], ["Monde", String(a.get("home_name", ""))]], "", [String(a["name"])], ["15b-anciennes"]))
		"faune":
			var sp: Dictionary = _data("data/creatures.json").get("species", {})
			var tempers := {"passive": "Paisible", "territorial": "Territoriale", "predator": "Prédatrice"}
			for k: String in sp:
				var s: Dictionary = sp[k]
				out.append(_e(cid, k, String(s["label"]), String(s.get("text", "")),
						"%s\n\n[b]Point faible.[/b] %s" % [String(s.get("text", "")), String(s.get("weakness", ""))],
						[["Tempérament", String(tempers.get(String(s.get("temper", "")), ""))], ["Apprivoisable", "oui" if bool(s.get("tamable", false)) else "non"]],
						"", [String(s["label"])], ["19-faune"]))
		"gardiens":
			for g: Dictionary in _data("data/guardians.json").get("guardians", []):
				out.append(_e(cid, String(g["id"]), String(g["name"]), String(g.get("text", "")),
						"%s\n\n[b]Particularité.[/b] %s" % [String(g.get("text", "")), String(g.get("trait", ""))],
						[["Repaire", String(g.get("where", ""))], ["Registre", String(g.get("register", ""))]], "", [String(g["name"])], ["19-faune", "20-zone-scellee"]))
		"crises":
			var ck: Dictionary = _data("data/crises.json").get("kinds", {})
			for k: String in ck:
				var c: Dictionary = ck[k]
				var body := String(c.get("text", ""))
				if c.has("wants"):
					body += "\n\n[b]Ce qu'elle veut.[/b] " + String(c["wants"])
				if c.has("weak"):
					body += "\n\n[b]Faiblesse.[/b] " + String(c["weak"])
				if c.has("tip"):
					body += "\n\n[b]Conseil.[/b] " + String(c["tip"])
				out.append(_e(cid, k, String(c["name"]), String(c.get("short", "")), body,
						[["Registre", String(c.get("register", ""))]], "", [String(c["name"])], ["15a-crises", "20-zone-scellee"]))
		"technologies":
			# Une page par technologie (prop. 112 de l'étude de l'arbre) : image, ce qu'elle débloque,
			# prérequis et suites, Maîtrise, eurêka, peuple. Les noms de technologies ne sont pas
			# soulignés dans les autres textes (catalogue sans « link »).
			var t: Dictionary = GameData.technologies()
			var techs: Dictionary = t.get("technologies", {})
			var nexts := {}
			for k: String in techs:
				for p in techs[k].get("pre", []):
					if not nexts.has(String(p)):
						nexts[String(p)] = []
					nexts[String(p)].append(k)
			for k: String in techs:
				var x: Dictionary = techs[k]
				out.append(_e(cid, k, String(x["label"]), String(x.get("text", "")), _tech_body(k, x, techs, nexts),
						[["Domaine", "Peuple (Destinée)" if x.has("victory") else String(Research.domain(String(x.get("domain", ""))).get("label", ""))],
						["Champ", Research.field_label(String(x.get("domain", "")), String(x.get("field", ""))) if not x.has("victory") else ""],
						["Ère", _roman(int(x.get("era", 1)))], ["Sorte", _tech_kind(x)],
						["Courant", String(GameData.politics()["currents"][Politics.index_of(String(x["current"]))]["short"]) if Politics.index_of(String(x.get("current", ""))) >= 0 else ""],
						["Requiert", _tech_names(x.get("pre", []), techs)]],
						String(x.get("flavor", "")) if Research.shows_flavor(x) else "", [], ["07-recherche"]))
		"batiments":
			var b: Dictionary = _data("data/buildings.json")
			for k: String in b:
				if k.begins_with("_") or not b[k] is Dictionary or not (b[k] as Dictionary).has("label"):
					continue
				var x: Dictionary = b[k]
				out.append(_e(cid, k, String(x["label"]), String(x.get("lore", x.get("text", ""))), GameData.lore_then(String(x.get("lore", "")), String(x.get("text", "")), "**En jeu.** "),
						[["Coût", _amounts(x.get("cost", {}))], ["Délai", ("%d jours" % int(x["days"])) if x.has("days") else ""], ["Produit", _amounts(x.get("yields", {}))], ["Entretien", _amounts(x.get("upkeep", {}))]],
						"", [], ["04-colonies"]))
		"vaisseaux":
			var sh: Dictionary = _data("data/ships.json")
			for k: String in sh:
				if k.begins_with("_") or not sh[k] is Dictionary or not (sh[k] as Dictionary).has("label"):
					continue
				var x: Dictionary = sh[k]
				out.append(_e(cid, k, String(x["label"]), String(x.get("description", "")), String(x.get("description", "")),
						[["Coût", _amounts(x.get("cost", {}))], ["Délai", ("%d jours" % int(x["days"])) if x.has("days") else ""], ["Coque", str(x.get("hp", ""))], ["Vitesse", str(x.get("speed", ""))]],
						"", [], ["06-flottes", "08-chantier"]))
		"merveilles":
			var w: Dictionary = _data("data/wonders.json").get("wonders", {})
			for k: String in w:
				var x: Dictionary = w[k]
				out.append(_e(cid, k, String(x["label"]), String(x.get("text", "")), String(x.get("text", "")),
						[["Ère", _roman(int(x.get("era", 1)))], ["Coût", _amounts(x.get("cost", {}))]],
						String(x.get("quote", "")), [String(x["label"])], ["15e-merveilles"]))
		"reliques":
			for r: Dictionary in _data("data/relics.json").get("relics", []):
				out.append(_e(cid, String(r["id"]), String(r["name"]), String(r.get("text", "")), String(r.get("text", "")), [], "", [], ["14-perils"]))
		"mondes":
			var pt: Dictionary = _data("data/planet_types.json")
			for k: String in pt:
				if not pt[k] is Dictionary or not (pt[k] as Dictionary).has("label"):
					continue
				var x: Dictionary = pt[k]
				var sizes: Array = x.get("sizes", [])
				out.append(_e(cid, k, String(x["label"]), String(x.get("lore", "")), String(x.get("lore", "")),
						[["Habitabilité de base", "%d %%" % int(x.get("base_hab", 0))], ["Tailles", "%d à %d" % [int(sizes[0]), int(sizes[1])] if sizes.size() == 2 else ""],
						["Par citoyen", _amounts(x.get("pop_yields", x.get("city_pop_yields", {})))], ["Avant-poste", _amounts(x.get("outpost_yields", {}))]],
						"", [], ["04-colonies"]))
		"terrains":
			var tr: Dictionary = (_data("data/terrain.json") as Dictionary).get("terrains", {})
			for k: String in tr:
				var x: Dictionary = tr[k]
				out.append(_e(cid, k, String(x["label"]), String(x.get("lore", "")), String(x.get("lore", "")),
						[["Inconvénient", String(x.get("bad", ""))], ["Avantage", String(x.get("good", ""))]], "", [], []))
		"biens":
			var g: Dictionary = _data("data/goods.json")
			for x: Dictionary in g.get("luxuries", []):
				out.append(_e(cid, String(x["id"]), String(x["label"]), String(x.get("text", "")), String(x.get("text", "")), [["Type", "luxe"]], "", [], ["10a-commerce"]))
			for x: Dictionary in g.get("strategic", []):
				out.append(_e(cid, String(x["id"]), String(x["label"]), String(x.get("text", "")), String(x.get("text", "")), [["Type", "stratégique"], ["Ère", _roman(int(x.get("era", 1)))]], "", [], ["10a-commerce"]))
		"lois":
			var p: Dictionary = _data("data/politics.json")
			var names := {}
			for c: Dictionary in p.get("currents", []):
				names[String(c["id"])] = String(c.get("short", c["id"]))
			for cid2: String in p.get("laws", {}):
				var bl: Dictionary = p["laws"][cid2]
				for l: Dictionary in bl.get("laws", []):
					out.append(_e(cid, "%s_%s" % [cid2, String(l.get("id", l["label"]))], String(l["label"]), String(l.get("text", "")), String(l.get("text", "")),
							[["Courant", String(names.get(cid2, cid2))], ["Niveau", str(l.get("level", ""))]], "", [], ["12-politique"]))
		"pouvoirs":
			for x: Dictionary in _data("data/psionics.json").get("powers", []):
				out.append(_e(cid, String(x["id"]), String(x["label"]), String(x.get("text", "")), String(x.get("text", "")),
						[["Coût", "%d Résonance" % int(x.get("cost", 0))], ["Recharge", "%d jours" % int(x.get("cooldown", 0))], ["Fêlure", "%d %%" % int(x.get("felure", 0))]],
						"", [], ["15q-psionique"]))
	_cache[cid] = out
	return out


static func _e(cid: String, key: String, name: String, summary: String, body: String, rows: Array, quote: String, forms: Array, chapters: Array) -> Dictionary:
	var c := catalog_def(cid)
	var clean_rows: Array = []
	for r in rows:
		if String(r[1]) != "":
			clean_rows.append(r)
	var e := {"id": "cat:%s:%s" % [cid, key], "name": name, "family": String(c["family"]), "summary": _first_sentences(summary),
			"body": body, "rows": clean_rows, "quote": quote, "cat": cid, "chapters": chapters, "forms": forms if bool(c.get("link", false)) else []}
	if bool(c.get("locked", false)):
		e["locked"] = true
	if bool(c.get("secret", false)):
		e["secret"] = true
	return e


static func _first_sentences(s: String) -> String:
	if s.length() <= 220:
		return s
	var cut := s.find(". ", 120)
	return s.left(cut + 1) if cut > 0 and cut < 260 else s.left(217) + "…"


## Texte de la page d'une technologie.
static func _tech_body(k: String, x: Dictionary, techs: Dictionary, nexts: Dictionary) -> String:
	var parts := PackedStringArray()
	if String(x.get("lore", "")) != "":
		parts.append(String(x["lore"]))
		parts.append("**En jeu.** " + String(x.get("text", "")))
	else:
		parts.append(String(x.get("text", "")))
	var owner := {}
	for f: Dictionary in GameData.factions():
		if Research.is_visible(f, k):
			owner = f
			break
	if not owner.is_empty():
		var un := PackedStringArray()
		for u: Dictionary in Research.unlock_entries(owner, k):
			if String(u["kind"]) != "maitrise":
				un.append(String(u["text"]))
		if not un.is_empty():
			parts.append("**Débloque.** %s." % ", ".join(un))
	var ms := Research.masteries_of(k)
	if not ms.is_empty():
		parts.append("**Maîtrise.** %s." % _tech_names(ms, techs))
	if x.has("mastery"):
		parts.append("**Maîtrise de %s.** Facultative : elle n'est jamais prérequise et ne compte pas pour ouvrir l'ère suivante." % String(techs.get(String(x["mastery"]), {}).get("label", x["mastery"])))
	if nexts.has(k):
		parts.append("**Ouvre la voie à.** %s." % _tech_names(nexts[k], techs))
	if x.has("eureka"):
		var eu := Research.eureka_text(k)
		parts.append("**Eurêka.** %s%s : 40 %% du coût payé d'avance." % [eu.left(1).to_upper(), eu.substr(1)])
	if x.has("requires"):
		var who := PackedStringArray()
		for f: Dictionary in GameData.factions():
			if Research.is_visible(f, k):
				who.append(String(f.get("short", f.get("name", ""))))
		parts.append("**Peuple.** Propre aux peuples qui en ont les couches%s." % (" (aujourd'hui : %s)" % ", ".join(who) if not who.is_empty() else ""))
		if x.has("replaces"):
			parts.append("Elle remplace pour eux %s, à sa place dans l'arbre." % String(techs.get(String(x["replaces"]), {}).get("label", x["replaces"])))
	if x.has("spec"):
		var mates := PackedStringArray()
		for o in Research.spec_members(String(x["spec"])):
			if o != k:
				mates.append(String(techs[o]["label"]))
		parts.append("**Spécialisation.** La choisir ferme %s ; l'autre branche ne s'obtient plus que par échange, vol, épaves ou trouvaille." % ", ".join(mates))
	if x.has("find"):
		parts.append("**Trouvaille.** Elle ne se recherche pas : curiosités, ruines, Strates, quêtes, prises ou hauts faits la livrent.")
	if Research.is_dangerous(k):
		parts.append("**Dangereuse.** %s" % Research.danger_text(k))
	if x.has("pillar"):
		parts.append("Elle n'apparaît que si le pilier %s est en jeu." % Research.pillar_label(String(x["pillar"])))
	return "\n\n".join(parts)


static func _tech_kind(x: Dictionary) -> String:
	if x.has("victory"):
		return "Destinée"
	if x.has("mastery"):
		return "Maîtrise"
	if x.has("find"):
		return "Trouvaille"
	if x.has("ultimate"):
		return "Ultime"
	if x.has("spec"):
		return "Spécialisation"
	return "Technologie de peuple" if x.has("requires") else ""


static func _roman(n: int) -> String:
	return ["I", "II", "III", "IV", "V", "VI"][clampi(n - 1, 0, 5)]


static func _tech_names(req: Variant, techs: Dictionary) -> String:
	var names := PackedStringArray()
	if req is Array:
		for r in req:
			names.append(String((techs.get(String(r), {}) as Dictionary).get("label", r)))
	return ", ".join(names)


static func _amounts(d: Variant) -> String:
	if not d is Dictionary or (d as Dictionary).is_empty():
		return ""
	var labels := {"energy": "énergie", "materials": "matériaux", "food": "nourriture", "influence": "influence", "crystals": "cristaux", "knowledge": "Savoir", "credits": "crédits"}
	var parts := PackedStringArray()
	for k in d:
		var v: Variant = d[k]
		if v is float or v is int:
			parts.append("%s %s" % [str(snappedf(float(v), 0.01)).trim_suffix(".0"), labels.get(String(k), String(k))])
	return ", ".join(parts)


## Toutes les fiches, catalogue par catalogue.
static func all_entries() -> Array:
	var out: Array = []
	for c: Dictionary in CATALOGS:
		out.append_array(entries(String(c["id"])))
	return out


## Fiches reconnues dans les textes (leurs noms deviennent des liens), pour Glossary.
static func linkables() -> Array:
	var out: Array = []
	for c: Dictionary in CATALOGS:
		if bool(c.get("link", false)):
			out.append_array(entries(String(c["id"])))
	return out


static func entry(id: String) -> Dictionary:
	var parts := id.split(":")
	if parts.size() < 3:
		return {}
	for e: Dictionary in entries(parts[1]):
		if String(e["id"]) == id:
			return e
	return {}
