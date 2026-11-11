class_name Species
extends RefCounted
## Éditeur d'espèces, côté règles : un peuple créé (« spec ») est assemblé à partir des briques de
## data/species_parts.json en une fiche au même format que data/factions.json. Le reste du jeu ne fait
## donc aucune différence entre un peuple officiel et un peuple créé.
##
## Spec (ce que l'éditeur enregistre, voir SpeciesLibrary) :
##   {"format": 1, "id": "p_…", "name", "short", "lore", "color": "#rrggbb", "portrait", "ship_style",
##    "temperament": -1 | 0 | 1, "registre", "archetype", "gouvernement", "credo", "origine",
##    "biomes": [monde natal (100 %), second biome (80 %)], "traits": [identifiants]}
##
## Budget (bloc "budget") : les traits positifs coûtent des points, les défauts en rendent (plafonnés),
## un trait de croissance coûte un point de plus et un seul est permis, un défaut annulé par une autre
## couche est refusé. errors() applique ces règles ; un fichier hors règles n'est jamais chargé.
##
## Fusion des champs (build) : les pourcentages se multiplient (production_pct, growth_pct,
## food_upkeep_pct, fleet_speed_pct, combat.*_pct, research.*_cost_pct), les biais d'IA s'additionnent,
## le reste est posé (les traits, appliqués en dernier, l'emportent).

const FORMAT := 1
const PCT_KEYS := ["growth_pct", "food_upkeep_pct", "fleet_speed_pct"]
const AI_SUM_KEYS := ["colony_bonus", "outpost_bonus", "crystal_bonus", "food_margin", "scouts"]
const NAME_MAX := 40
const SHORT_MAX := 16
const LORE_MAX := 1200


static func parts() -> Dictionary:
	return GameData.species_parts()


static func budget() -> Dictionary:
	return parts()["budget"]


static func layers() -> Array:
	return parts()["layers"]


## Choix possibles pour une couche ("registre", "archetype", "gouvernement", "credo", "origine").
static func options(layer: String) -> Array:
	return parts().get(layer, [])


static func brick(layer: String, id: String) -> Dictionary:
	for b: Dictionary in options(layer):
		if String(b["id"]) == id:
			return b
	return {}


static func trait_ids() -> Array[String]:
	var out: Array[String] = []
	for t: Dictionary in parts()["traits"]:
		out.append(String(t["id"]))
	return out


static func trait_def(id: String) -> Dictionary:
	for t: Dictionary in parts()["traits"]:
		if String(t["id"]) == id:
			return t
	return {}


## Portraits dessinés pour un archétype (tous si archetype == "").
static func portraits(archetype := "") -> Array:
	var out := []
	for p: Dictionary in parts()["portraits"]:
		if archetype == "" or (p.get("archetypes", []) as Array).has(archetype):
			out.append(p)
	return out


## Toute la galerie, ceux de l'archétype en premier : le joueur choisit librement.
static func gallery(archetype: String) -> Array:
	var out := portraits(archetype)
	for p: Dictionary in parts()["portraits"]:
		if not out.has(p):
			out.append(p)
	return out


static func portrait_def(id: String) -> Dictionary:
	for p: Dictionary in parts()["portraits"]:
		if String(p["id"]) == id:
			return p
	return {}


static func temperament_def(v: int) -> Dictionary:
	for t: Dictionary in parts()["temperaments"]:
		if int(t["id"]) == v:
			return t
	return {}


# --- Budget ------------------------------------------------------------------------------------

## Décompte du budget : {"budget": points disponibles (origine comprise), "used": points dépensés
## (défauts déduits, croissance comprise), "left", "flaws": points rendus par les défauts,
## "growth": traits de croissance, "count": nombre de traits}.
static func cost(spec: Dictionary) -> Dictionary:
	var b := budget()
	var avail := int(b["points"]) + int(brick("origine", String(spec.get("origine", ""))).get("points", 0))
	var used := 0
	var flaws := 0
	var growth := 0
	var ts: Array = spec.get("traits", [])
	for tid in ts:
		var t := trait_def(String(tid))
		if t.is_empty():
			continue
		var c := int(t.get("cost", 0))
		used += c
		if c < 0:
			flaws -= c
		if bool(t.get("growth", false)):
			growth += 1
			used += int(b["growth_extra"])
	return {"budget": avail, "used": used, "left": avail - used, "flaws": flaws, "growth": growth, "count": ts.size()}


## Coût affiché d'un trait (croissance comprise).
static func trait_cost(id: String) -> int:
	var t := trait_def(id)
	return int(t.get("cost", 0)) + (int(budget()["growth_extra"]) if bool(t.get("growth", false)) else 0)


# --- Vérification ------------------------------------------------------------------------------

## "" si le peuple respecte toutes les règles, sinon la première raison du refus.
static func check(spec: Dictionary) -> String:
	var errs := errors(spec)
	return "" if errs.is_empty() else errs[0]


## Toutes les raisons qui empêchent d'enregistrer ce peuple (vide = valide).
static func errors(spec: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var id := String(spec.get("id", ""))
	if not is_valid_id(id):
		out.append("identifiant invalide : « %s » (p_ suivi de lettres minuscules, chiffres ou _)" % id)
	var nm := String(spec.get("name", "")).strip_edges()
	if nm == "" or nm.length() > NAME_MAX:
		out.append("le nom doit faire de 1 à %d caractères" % NAME_MAX)
	var sh := String(spec.get("short", "")).strip_edges()
	if sh == "" or sh.length() > SHORT_MAX:
		out.append("le nom court doit faire de 1 à %d caractères" % SHORT_MAX)
	if String(spec.get("lore", "")).length() > LORE_MAX:
		out.append("l'histoire dépasse %d caractères" % LORE_MAX)
	if not Color.html_is_valid(String(spec.get("color", ""))):
		out.append("couleur invalide")
	for layer in layers():
		if brick(String(layer), String(spec.get(layer, ""))).is_empty():
			out.append("choix manquant ou inconnu pour la couche « %s »" % layer)
	if not out.is_empty():
		return out
	# Exigences et exclusions entre couches.
	for layer in layers():
		var b := brick(String(layer), String(spec[layer]))
		var req: Dictionary = b.get("requires", {})
		for l2 in req:
			if not (req[l2] as Array).has(String(spec.get(l2, ""))):
				out.append("%s demande : %s" % [b["label"], _labels(String(l2), req[l2])])
		var exc: Dictionary = b.get("excludes", {})
		for l2 in exc:
			if (exc[l2] as Array).has(String(spec.get(l2, ""))):
				out.append("%s est incompatible avec %s" % [b["label"], brick(String(l2), String(spec[l2])).get("label", spec[l2])])
	var biomes: Array = spec.get("biomes", [])
	var allowed: Array = parts()["biomes"]
	if biomes.size() != 2 or String(biomes[0]) == String(biomes[1]) or not allowed.has(String(biomes[0])) or not allowed.has(String(biomes[1])):
		out.append("il faut deux biomes différents parmi : %s" % ", ".join(PackedStringArray(allowed)))
	var p := portrait_def(String(spec.get("portrait", "")))
	# Tout portrait va avec tout peuple : les archétypes d'un portrait ne servent qu'à l'ordre de la galerie.
	if p.is_empty():
		out.append("portrait inconnu")
	if not (parts()["ship_styles"] as Array).has(String(spec.get("ship_style", ""))):
		out.append("style de vaisseaux inconnu")
	if temperament_def(int(spec.get("temperament", 99))).is_empty():
		out.append("tempérament inconnu")
	out.append_array(trait_errors(spec))
	return out


## Règles des traits seulement (budget, oppositions, défauts annulés, croissance).
static func trait_errors(spec: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var b := budget()
	var ts: Array = spec.get("traits", [])
	var seen := {}
	for tid in ts:
		var t := trait_def(String(tid))
		if t.is_empty():
			out.append("trait inconnu : %s" % tid)
			continue
		if seen.has(tid):
			out.append("trait en double : %s" % t["label"])
		seen[tid] = true
		for o in t.get("opposes", []):
			if ts.has(o) and String(tid) < String(o):
				out.append("%s et %s s'excluent" % [t["label"], trait_def(String(o)).get("label", o)])
		var nb: Dictionary = t.get("neutralized_by", {})
		for layer in nb:
			if (nb[layer] as Array).has(String(spec.get(layer, ""))):
				out.append("%s ne coûterait rien avec %s : défaut refusé" % [t["label"], brick(String(layer), String(spec[layer])).get("label", spec[layer])])
	if not out.is_empty():
		return out
	var c := cost(spec)
	if int(c["count"]) > int(b["max_traits"]):
		out.append("%d traits au plus" % int(b["max_traits"]))
	if int(c["growth"]) > int(b["max_growth"]):
		out.append("un seul trait de croissance par peuple")
	if int(c["flaws"]) > int(b["max_flaws"]):
		out.append("les défauts rendent %d points au plus" % int(b["max_flaws"]))
	if int(c["left"]) < 0:
		out.append("budget dépassé de %d point(s)" % -int(c["left"]))
	return out


static func is_valid_id(id: String) -> bool:
	if not id.begins_with("p_") or id.length() < 3 or id.length() > 48 or GameData.is_official(id):
		return false
	for ch in id.substr(2):
		if not ((ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch == "_"):
			return false
	return true


## Identifiant libre tiré du nom : « Les Fils d'Orme » -> p_les_fils_d_orme (suffixé si déjà pris).
static func make_id(name: String, taken: Array) -> String:
	var base := "p_"
	for ch in name.to_lower().strip_edges():
		var c := String(_ASCII.get(ch, ch))
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			base += c
		elif not base.ends_with("_"):
			base += "_"
	base = base.rstrip("_").substr(0, 40)
	if base == "p" or base == "p_":
		base = "p_peuple"
	var id := base
	var n := 2
	while taken.has(id) or GameData.is_official(id):
		id = "%s_%d" % [base, n]
		n += 1
	return id


const _ASCII := {"à": "a", "â": "a", "ä": "a", "é": "e", "è": "e", "ê": "e", "ë": "e", "î": "i", "ï": "i",
		"ô": "o", "ö": "o", "ù": "u", "û": "u", "ü": "u", "ç": "c", "œ": "oe", "æ": "ae", "ÿ": "y"}


static func _labels(layer: String, ids: Array) -> String:
	var out := PackedStringArray()
	for v in ids:
		out.append(String(brick(layer, String(v)).get("label", v)))
	return " ou ".join(out)


# --- Assemblage --------------------------------------------------------------------------------

## Fiche de faction du peuple (format de data/factions.json). Suppose un spec valide (check() == "").
static func build(spec: Dictionary) -> Dictionary:
	var f := {
		"id": String(spec["id"]), "name": String(spec["name"]).strip_edges(), "short": String(spec["short"]).strip_edges(),
		"registre": String(spec["registre"]), "color": String(spec["color"]), "lore": String(spec.get("lore", "")),
		"preferred": (spec["biomes"] as Array).duplicate(), "portrait": String(spec["portrait"]),
		"ship_style": String(spec["ship_style"]), "custom": true,
		"species": {"archetype": String(spec["archetype"]), "gouvernement": String(spec["gouvernement"]),
			"credo": String(spec["credo"]), "traits": (spec.get("traits", []) as Array).duplicate()},
		"growth_pct": 100, "food_upkeep_pct": 100, "production_pct": {}, "research": {}, "combat": {}, "ai": {},
		"traits": [],
	}
	for layer in ["archetype", "gouvernement", "credo", "origine"]:
		var b := brick(layer, String(spec[layer]))
		_merge(f, b.get("fields", {}))
		var w: Dictionary = b.get("with", {})
		for l2 in w:
			var extra: Dictionary = w[l2].get(String(spec.get(l2, "")), {})
			_merge(f, extra)
		for t: Dictionary in b.get("traits", []):
			f["traits"].append(t.duplicate())
	for tid in spec.get("traits", []):
		var t := trait_def(String(tid))
		_merge(f, t.get("fields", {}))
		f["traits"].append({"name": String(t["label"]), "text": String(t["text"])})
	var origin := brick("origine", String(spec["origine"]))
	f["traits"].append({"name": String(origin["label"]), "text": String(origin["text"])})
	var gov := brick("gouvernement", String(spec["gouvernement"]))
	var credo := brick("credo", String(spec["credo"]))
	var tp := temperament_def(int(spec["temperament"]))
	var ai: Dictionary = f["ai"]
	var temper: Dictionary = ai.get("temperament", {})
	temper["label"] = String(tp["label"])
	temper["aggression"] = int(tp["id"])
	temper["text"] = String(tp["text"])
	ai["temperament"] = temper
	ai["style"] = "%s, %s : %s" % [gov["label"], String(credo["label"]).to_lower(), gov["text"]]
	f["trait"] = "%s, %s, %s." % [brick("archetype", String(spec["archetype"]))["label"], String(gov["label"]).to_lower(), String(credo["label"]).to_lower()]
	f["spec"] = spec.duplicate(true)
	return GameData._to_ints(f)


static func _merge(dst: Dictionary, src: Dictionary) -> void:
	for k in src:
		var v: Variant = src[k]
		if k in PCT_KEYS:
			dst[k] = _mul(int(dst.get(k, 100)), int(v))
		elif k == "production_pct":
			var pp: Dictionary = dst.get(k, {})
			for r in v:
				pp[r] = _mul(int(pp.get(r, 100)), int(v[r]))
			dst[k] = pp
		elif k == "combat" or k == "research":
			var sub: Dictionary = dst.get(k, {})
			for kk in v:
				var vv: Variant = v[kk]
				if vv is Dictionary:
					var inner: Dictionary = sub.get(kk, {})
					for x in vv:
						if String(kk).ends_with("_pct"):
							inner[x] = _mul(int(inner.get(x, 100)), int(vv[x]))
						else:
							inner[x] = int(inner.get(x, 0)) + int(vv[x])
					sub[kk] = inner
				elif String(kk).ends_with("_pct") and sub.has(kk) and not (vv is bool):
					sub[kk] = _mul(int(sub[kk]), int(vv))
				else:
					sub[kk] = vv
			dst[k] = sub
		elif k == "ai":
			var ai: Dictionary = dst.get(k, {})
			for kk in v:
				var vv: Variant = v[kk]
				if kk == "research_bias":
					var rb: Dictionary = ai.get(kk, {})
					for x in vv:
						rb[x] = int(rb.get(x, 0)) + int(vv[x])
					ai[kk] = rb
				elif kk == "temperament":
					var tp: Dictionary = ai.get(kk, {})
					tp.merge(vv, true)
					ai[kk] = tp
				elif kk in AI_SUM_KEYS:
					ai[kk] = int(ai.get(kk, 0)) + int(vv)
				else:
					ai[kk] = vv
			dst[k] = ai
		elif v is Dictionary:
			dst[k] = (v as Dictionary).duplicate(true)
		elif v is Array:
			dst[k] = (v as Array).duplicate(true)
		else:
			dst[k] = v


@warning_ignore("integer_division")
static func _mul(a: int, b: int) -> int:
	return a * b / 100


# --- Modèles -----------------------------------------------------------------------------------

## Spec de départ tiré de la combinaison déclarée d'un peuple officiel (« Partir de… »), ou un peuple
## neutre si preset == "". Nom et identifiant restent à donner.
static func from_preset(preset: String) -> Dictionary:
	var p: Dictionary = parts()["presets"].get(preset, {})
	var spec := {"format": FORMAT, "id": "", "name": "", "short": "", "lore": "", "color": "#9b7fd4",
		"portrait": "humanoide_1", "ship_style": "vael", "temperament": 0,
		"registre": "Classique / hard SF", "archetype": "humanoide", "gouvernement": "republique", "credo": "raison",
		"origine": "sans_heritage", "biomes": ["continental", "ocean"], "traits": []}
	for k in p:
		spec[k] = p[k].duplicate(true) if p[k] is Array else p[k]
	if p.has("registre"):
		var f := GameData.faction(preset)
		spec["color"] = String(f.get("color", spec["color"]))
	return spec


## Ce que la combinaison débloque, pour l'aperçu de l'éditeur : {"victories": [libellés],
## "ships": [classes propres], "abilities": [talents diplomatiques]}.
static func unlocks(spec: Dictionary) -> Dictionary:
	var f := {"registre": String(spec.get("registre", "")), "species": {"archetype": String(spec.get("archetype", "")),
		"gouvernement": String(spec.get("gouvernement", "")), "credo": String(spec.get("credo", "")), "traits": spec.get("traits", [])}}
	var vics := []
	for vid in Victory.people_ids_for(f):
		vics.append(String(Victory.info(vid).get("label", vid)))
	var ships := []
	for sid in GameData.class_ids():
		var req: Dictionary = GameData.ship(sid).get("requires", {}).get("species", {})
		if not req.is_empty() and FactionTraits.species_matches(f, req):
			ships.append(String(GameData.ship(sid).get("label", sid)))
	var abilities := []
	for a in Diplomacy.faction_abilities(f):
		abilities.append(String(a["label"]))
	return {"victories": vics, "ships": ships, "abilities": abilities}
