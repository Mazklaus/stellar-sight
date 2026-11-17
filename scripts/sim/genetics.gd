class_name Genetics
extends RefCounted
## Ingénierie des espèces (étude du 2026-11-16, 43 propositions validées le 2026-11-17 ; données :
## data/genetics.json).
##
## Chaque empire tient un GÉNOME par espèce qui vit chez lui (Empire.genome) : traits ajoutés, traits
## retirés, second biome, drapeaux (cybernétique, synthétique après le Grand Transfert, greffes). La
## fiche de l'espèce porte ce génome (Empire.faction() pour l'espèce fondatrice, Empire.species_fiche
## pour les autres) : le reste du jeu le voit sans rien changer. Un autre empire de la même espèce garde
## la sienne. Les mécaniques propres des peuples (fiefs, Biomasse, Voile, Échos, ferveur…) ne sont
## jamais touchées : seuls les traits d'espèce (catalogue de l'éditeur et traits façonnés) changent.
##
## Programmes (prop. 6) : un changement se paie en Savoir (matériaux pour une espèce synthétique), en
## mensualités prises sur le stock avant la recherche ; l'effet tombe à la fin. Marge (prop. 4) : 0 au
## départ, +1 par technologie du pilier (4 au plus), +1 par Codex des origines, +2 au couronnement
## génétique ; un défaut ajouté rend ses points.
##
## Réglage « Ingénierie des espèces » : Complète (lignées, hybrides, greffe, abrutissement en plus),
## Simple, Désactivée (state.genetics vide). Sans l'option (tests, bancs) : désactivée.
##
## État : state.genetics = {"mode", "prog": {"eid": [programme]}, "seq": numéro du prochain programme,
##  "done": {"eid": programmes achevés}, "lin": {lignée: {"base", "owner", "name", "add", "rem", "bio"}},
##  "hyb": {"eid": hybrides nés}, "bfree": {"eid": dernière ère d'acclimatation gratuite},
##  "renounce": {"eid": jour de fin de la crise}, "stolen": {"eid": [traits volés ou achetés]},
##  "contam": {"eid": jour de fin}, "samples": {"eid": [traits uniques]}, "grief": {"a:b": jour de fin},
##  "digest": {"eid": peuples digérés depuis la dernière greffe}, "st": {"eid": {statistiques}}}.
## Programme : {"id", "kind": "mod" | "cyber" | "transfer" | "lineage" | "heir" | "gift" | "hybrid",
##  "fid", "add", "rem", "bio", "res": "knowledge" | "materials", "cost", "paid", ... }.

const SUBS := ["prog", "done", "lin", "hyb", "bfree", "renounce", "stolen", "contam", "samples", "grief", "digest", "st"]
const LAYERS := ["traits", "registre", "archetype", "gouvernement", "credo"]
## Champs qui s'additionnent (les autres champs façonnés se multiplient en pourcentage).
const SUM_KEYS := ["hab_plus", "stability", "life_years", "detect_bonus", "cloak_bonus"]
const MUL_KEYS := ["plague_pct", "savoury", "echoes_pct", "hero_xp_pct"]
const PCT_KEYS := ["growth_pct", "food_upkeep_pct", "fleet_speed_pct"]

static var _talent_cache := {}


static func data() -> Dictionary:
	return GameData.genetics()


static func cfg(section: String) -> Dictionary:
	return data().get(section, {})


static func c_int(section: String, key: String, def := 0) -> int:
	return int(cfg(section).get(key, def))


static func mode_defs() -> Array:
	return data().get("modes", [])


static func default_mode() -> String:
	return String(data().get("default_mode", "complete"))


static func mode(state: GameState) -> String:
	return String(state.genetics.get("mode", "desactivee"))


static func enabled(state: GameState) -> bool:
	return state != null and not state.genetics.is_empty()


static func full(state: GameState) -> bool:
	return enabled(state) and mode(state) == "complete"


static func applies(state: GameState, eid: int) -> bool:
	var e := state.get_empire(eid) if enabled(state) and eid >= 0 else null
	return e != null and not e.is_npc() and not e.eliminated


static func mode_label(state: GameState) -> String:
	for m: Dictionary in mode_defs():
		if String(m["id"]) == mode(state):
			return String(m["label"])
	return "Désactivée"


# --- Réglage, sauvegarde -----------------------------------------------------------------------

static func setup(state: GameState, mode_id: String) -> void:
	state.genetics = {}
	var ok := false
	for m: Dictionary in mode_defs():
		if String(m["id"]) == mode_id:
			ok = true
	if not ok or mode_id == "desactivee":
		return
	state.genetics = {"mode": mode_id, "seq": 1}
	for k in SUBS:
		state.genetics[k] = {}


static func worth_saving(state: GameState) -> bool:
	return enabled(state)


static func to_dict(state: GameState) -> Dictionary:
	return state.genetics.duplicate(true)


static func from_dict(state: GameState, d: Dictionary) -> void:
	if d.is_empty():
		state.genetics = {}
		return
	state.genetics = GameData._to_ints(d.duplicate(true))
	for k in SUBS:
		if not state.genetics.has(k):
			state.genetics[k] = {}
	if not state.genetics.has("seq"):
		state.genetics["seq"] = 1


static func sub(state: GameState, k: String) -> Dictionary:
	if state.genetics.is_empty():
		return {}  # pilier désactivé : ne jamais le rallumer en écrivant
	if not state.genetics.has(k):
		state.genetics[k] = {}
	return state.genetics[k]


## Génome d'un empire, trié pour la sauvegarde : [[espèce, génome]].
static func genome_to_list(e: Empire) -> Array:
	var out := []
	var ks := e.genome.keys()
	ks.sort()
	for k in ks:
		out.append([String(k), (e.genome[k] as Dictionary).duplicate(true)])
	return out


static func genome_from_list(e: Empire, l: Array) -> void:
	e.genome = {}
	for pair in l:
		e.genome[String(pair[0])] = GameData._to_ints((pair[1] as Dictionary).duplicate(true))
	e.genome_rev += 1


# --- Catalogue ---------------------------------------------------------------------------------

static var _trait_index := {}


static func trait_def(id: String) -> Dictionary:
	if _trait_index.is_empty():
		for t: Dictionary in data().get("traits", []):
			_trait_index[String(t["id"])] = t
	if _trait_index.has(id):
		return _trait_index[id]
	var c := Species.trait_def(id)
	if c.is_empty():
		return {}
	# Trait de l'éditeur : même forme que les traits façonnés (voie « création »).
	var out := c.duplicate()
	out["voie"] = "creation"
	if not out.has("label"):
		out["label"] = id
	return out


static func trait_label(id: String) -> String:
	return String(trait_def(id).get("label", id))


static func trait_cost(id: String) -> int:
	var t := trait_def(id)
	return int(t.get("cost", 0))


static func is_flaw(id: String) -> bool:
	return trait_cost(id) < 0


static func catalogue() -> Array:
	return data().get("traits", [])


## Voies ouvertes à une fiche d'espèce (archétype), et implants si elle est cybernétique.
static func voies_of(f: Dictionary, path := "") -> Array[String]:
	var out: Array[String] = []
	var arch := String(FactionTraits.species(f).get("archetype", "humanoide"))
	for v in (cfg("voies").get(arch, ["genetique"]) as Array):
		out.append(String(v))
	if bool(f.get("cyber", false)) and not out.has("synthetique"):
		out.append("cybernetique")
	if path == "genetique" and out.has("genetique"):
		out.append("elite")
	return out


static func is_organic(f: Dictionary) -> bool:
	var arch := String(FactionTraits.species(f).get("archetype", "humanoide"))
	return arch != "synthetique" and arch != "energetique"


## Traits actuels d'une fiche (couche « traits » de l'espèce).
static func traits_of(f: Dictionary) -> Array:
	return (FactionTraits.species(f).get("traits", []) as Array)


## Espèce racine d'une lignée (« base~L~empire~n ») ; l'identifiant lui-même sinon.
static func root(fid: String) -> String:
	var i := fid.find("~L~")
	return fid.substr(0, i) if i > 0 else fid


static func is_lineage(fid: String) -> bool:
	return fid.find("~L~") > 0


# --- Fiche : le génome posé sur le peuple ------------------------------------------------------

## Fiche d'une espèce qui vit chez un empire (génome compris).
static func fiche(state: GameState, eid: int, fid: String) -> Dictionary:
	var e := state.get_empire(eid) if eid >= 0 else null
	if e == null or e.is_npc():
		return GameData.faction(fid)
	return e.species_fiche(fid)


## La fiche d'un peuple, génome g posé dessus (base intacte si rien ne change).
static func apply_genome(base: Dictionary, g: Dictionary, path: String, founder: bool) -> Dictionary:
	if base.is_empty():
		return base
	var path_fx := path == "genetique" or (path == "purete" and founder)
	if g.is_empty() and not path_fx:
		return base
	var f := base.duplicate(true)
	var sp: Dictionary = (f.get("species", {}) as Dictionary).duplicate(true)
	var ts: Array = (sp.get("traits", []) as Array).duplicate()
	var shown: Array = (f.get("traits", []) as Array).duplicate(true)
	for tid in g.get("rem", []):
		var t := trait_def(String(tid))
		if t.is_empty():
			continue
		unmerge(f, t.get("fields", {}))
		ts.erase(String(tid))
		for i in range(shown.size() - 1, -1, -1):
			if String((shown[i] as Dictionary).get("name", "")) == String(t.get("label", "")):
				shown.remove_at(i)
				break
	if bool(g.get("synth", false)):
		# Grand Transfert : le corps devient synthétique (champs de l'archétype de l'éditeur).
		var arch := Species.brick("archetype", "synthetique")
		merge(f, arch.get("fields", {}).duplicate(true))
		f.erase("biomass")
		sp["archetype"] = "synthetique"
		f["transferred"] = true
		var tr := cfg("transfer")
		shown.append({"name": String(tr.get("label", "Grand Transfert")), "text": "Esprits transférés dans des châssis : plus de nourriture, une population assemblée."})
	for tid in g.get("add", []):
		var t := trait_def(String(tid))
		if t.is_empty():
			continue
		merge(f, t.get("fields", {}))
		if not ts.has(String(tid)):
			ts.append(String(tid))
		shown.append({"name": String(t.get("label", tid)), "text": String(t.get("text", ""))})
	if bool(g.get("cyber", false)):
		f["cyber"] = true
		shown.append({"name": String(cfg("cyber").get("trait", "Cybernétique")), "text": String(cfg("cyber").get("text", ""))})
	var bio := String(g.get("bio", ""))
	if bio != "":
		var pref: Array = (f.get("preferred", []) as Array).duplicate()
		if pref.size() >= 2:
			pref[1] = bio
		else:
			pref.append(bio)
		f["preferred"] = pref
	var gr: Dictionary = g.get("graft", {})
	if not gr.is_empty():
		var pp: Dictionary = (f.get("production_pct", {}) as Dictionary).duplicate()
		for r in gr:
			pp[r] = _mul(int(pp.get(r, 100)), 100 + int(gr[r]))
		f["production_pct"] = pp
		f["food_upkeep_pct"] = _mul(int(f.get("food_upkeep_pct", 100)), 100 + int(g.get("gfood", 0)))
		shown.append({"name": "Greffes", "text": "Gènes pris à d'autres peuples : %s." % GameData.format_amounts(gr)})
	if path == "genetique":
		f["growth_pct"] = _mul(int(f.get("growth_pct", 100)), 100 + int(path_def("genetique").get("growth_pct", 25)))
	if path == "purete" and founder:
		var strong := strong_of(f)
		var pp2: Dictionary = (f.get("production_pct", {}) as Dictionary).duplicate()
		pp2[strong] = _mul(int(pp2.get(strong, 100)), int(path_def("purete").get("strong_pct", 110)))
		f["production_pct"] = pp2
	sp["traits"] = ts
	f["species"] = sp
	f["traits"] = shown
	f["engineered"] = not g.is_empty()
	return f


## Ressource où la fiche excelle (plus fort pourcentage de production, sinon le Savoir).
static func strong_of(f: Dictionary) -> String:
	var pct: Dictionary = f.get("production_pct", {})
	var best := "knowledge"
	var best_v := 100
	var ks := pct.keys()
	ks.sort()
	for r in ks:
		if int(pct[r]) > best_v:
			best = String(r)
			best_v = int(pct[r])
	return best


## Ajoute les champs d'un trait à une fiche (règles de l'éditeur, plus les champs façonnés).
static func merge(f: Dictionary, fields: Dictionary) -> void:
	var rest := {}
	for k in fields:
		var v: Variant = fields[k]
		if k in SUM_KEYS:
			f[k] = int(f.get(k, 0)) + int(v)
		elif k in MUL_KEYS:
			f[k] = _mul(int(f.get(k, 100)), int(v))
		elif k == "combat" and (v as Dictionary).has("ground_pct"):
			var c: Dictionary = (f.get("combat", {}) as Dictionary).duplicate(true)
			c["ground_pct"] = _mul(int(c.get("ground_pct", 100)), int(v["ground_pct"]))
			f["combat"] = c
			var v2: Dictionary = (v as Dictionary).duplicate()
			v2.erase("ground_pct")
			if not v2.is_empty():
				rest["combat"] = v2
		else:
			rest[k] = v
	if not rest.is_empty():
		_species_merge(f, rest)


## Retire les champs d'un trait (pourcentages divisés, sommes soustraites ; ce qui ne s'inverse pas,
## comme un plancher d'habitabilité, revient à la valeur par défaut).
static func unmerge(f: Dictionary, fields: Dictionary) -> void:
	for k in fields:
		var v: Variant = fields[k]
		if k in SUM_KEYS:
			f[k] = int(f.get(k, 0)) - int(v)
		elif k in MUL_KEYS or k in PCT_KEYS:
			f[k] = _div(int(f.get(k, 100)), int(v))
		elif k == "production_pct":
			var pp: Dictionary = (f.get(k, {}) as Dictionary).duplicate()
			for r in v:
				pp[r] = _div(int(pp.get(r, 100)), int(v[r]))
			f[k] = pp
		elif k == "combat" or k == "research":
			var sub_d: Dictionary = (f.get(k, {}) as Dictionary).duplicate(true)
			for kk in v:
				var vv: Variant = v[kk]
				if String(kk).ends_with("_pct") and not (vv is Dictionary) and not (vv is bool):
					sub_d[kk] = _div(int(sub_d.get(kk, 100)), int(vv))
			f[k] = sub_d
		elif k == "ai":
			continue
		else:
			f.erase(k)


static func _species_merge(f: Dictionary, fields: Dictionary) -> void:
	Species._merge(f, fields)


@warning_ignore("integer_division")
static func _mul(a: int, b: int) -> int:
	return a * b / 100


@warning_ignore("integer_division")
static func _div(a: int, b: int) -> int:
	return a * 100 / maxi(1, b)


# --- Talents de peuple (prop. 37) --------------------------------------------------------------

static func talent(state: GameState, eid: int) -> Dictionary:
	var e := state.get_empire(eid) if eid >= 0 else null
	if e == null or e.is_npc():
		return {}
	var ck := "%s:%s" % [e.faction_id, str(e.faction().get("species", {}))]
	if _talent_cache.has(ck):
		return _talent_cache[ck]
	var out := {}
	var sp := FactionTraits.species(e.faction())
	var table: Dictionary = cfg("talents")
	for layer in LAYERS:
		var t: Dictionary = table.get(layer, {})
		if t.is_empty():
			continue
		var values: Array = sp.get("traits", []) if layer == "traits" else [String(sp.get(layer, ""))]
		for v in values:
			if not t.has(String(v)):
				continue
			var d: Dictionary = t[String(v)]
			out["labels"] = (out.get("labels", []) as Array) + [[String(d["label"]), String(d["text"])]]
			for k in d:
				if k != "label" and k != "text":
					out[k] = int(out.get(k, 0)) + int(d[k])
	_talent_cache[ck] = out
	return out


static func talent_labels(state: GameState, eid: int) -> Array:
	return talent(state, eid).get("labels", [])


# --- Technologies, marge, plafonds ---------------------------------------------------------------

static func tech_for(power: String) -> String:
	var t: Dictionary = cfg("techs")
	for k in t:
		if String(t[k]) == power:
			return String(k)
	return ""


static func has_power(state: GameState, eid: int, power: String) -> bool:
	var e := state.get_empire(eid)
	return e != null and e.techs.has(tech_for(power))


static func tech_count(state: GameState, eid: int) -> int:
	var e := state.get_empire(eid)
	if e == null:
		return 0
	var n := 0
	for k in cfg("techs"):
		if k != "_doc" and e.techs.has(String(k)):
			n += 1
	return mini(n, c_int("margin", "tech_max", 4))


## Points de marge d'une espèce chez un empire (avant ce que le génome a déjà dépensé).
static func margin_total(state: GameState, eid: int, fid: String) -> int:
	var e := state.get_empire(eid)
	if e == null:
		return 0
	var n := tech_count(state, eid)
	n += c_int("margin", "relic", 1) * relic_count(state, eid)
	if e.gene_path == "genetique":
		n += c_int("margin", "crown_genetique", 2)
	n += int(GameData.faction(root(fid)).get("hybrid_margin", 0))
	return n


## Points déjà dépensés par le génome (traits ajoutés moins traits retirés).
static func margin_used(g: Dictionary) -> int:
	var n := 0
	for tid in g.get("add", []):
		n += trait_cost(String(tid))
	for tid in g.get("rem", []):
		n -= trait_cost(String(tid))
	return n


static func margin_left(state: GameState, eid: int, fid: String) -> int:
	var e := state.get_empire(eid)
	if e == null:
		return 0
	return margin_total(state, eid, fid) - margin_used(e.genome.get(fid, {}))


## Plafond de traits (ceux qui coûtent ou rendent des points) d'une espèce chez un empire.
static func trait_cap(state: GameState, eid: int, fid: String, g := {}) -> int:
	var e := state.get_empire(eid)
	var n := c_int("margin", "max_traits", 5)
	var gg: Dictionary = g if not g.is_empty() else (e.genome.get(fid, {}) if e else {})
	if bool(gg.get("cyber", false)) or (e != null and e.gene_path == "cybernetique" and is_organic(GameData.faction(root(fid)))):
		n += c_int("margin", "cap_cyber", 1)
	if e != null and (e.gene_path == "genetique" or e.gene_path == "cybernetique"):
		n += c_int("margin", "cap_path", 1)
	n += int(GameData.faction(root(fid)).get("hybrid_cap", 0))
	return n


static func counted_traits(ts: Array) -> int:
	var n := 0
	for tid in ts:
		if trait_cost(String(tid)) != 0:
			n += 1
	return n


static func relic_count(state: GameState, eid: int) -> int:
	var rid := String(cfg("relic").get("id", ""))
	if rid == "" or state.relics.is_empty():
		return 0
	return 1 if Relics.owned(state, eid).has(rid) else 0


# --- Espèces d'un empire -----------------------------------------------------------------------

## Espèces qu'un empire peut modifier : la sienne, celles qui vivent chez lui, ses lignées.
static func species_of(state: GameState, eid: int) -> Array[String]:
	var out: Array[String] = []
	var e := state.get_empire(eid)
	if e == null:
		return out
	out.append(e.faction_id)
	if state.peoples_on:
		var cnt := Peoples.empire_counts(state, eid)
		var ks := cnt.keys()
		ks.sort()
		for fid in ks:
			if String(fid) != e.faction_id and int(cnt[fid]) > 0 and not is_lineage(String(fid)) and not out.has(String(fid)):
				out.append(String(fid))
	return out


static func pop_of(state: GameState, eid: int, fid: String) -> int:
	var e := state.get_empire(eid)
	if e == null:
		return 0
	if not state.peoples_on:
		var n := 0
		for pid in state.sorted_colony_ids():
			var c: Colony = state.colonies[pid]
			if c.owner == eid and c.is_colony() and c.is_established():
				n += c.population
		return n if fid == e.faction_id else 0
	return int(Peoples.empire_counts(state, eid).get(fid, 0))


static func label(state: GameState, eid: int, fid: String) -> String:
	var f := fiche(state, eid, fid)
	return String(f.get("short", f.get("name", fid)))


# --- Programmes : vérification -----------------------------------------------------------------

static func programs(state: GameState, eid: int) -> Array:
	return sub(state, "prog").get(str(eid), [])


static func max_programs(state: GameState, eid: int) -> int:
	var n := c_int("cost", "max_programs", 1)
	if has_power(state, eid, "directed"):
		n = maxi(n, c_int("directed", "programs", 2))
	return n


## Génome après un changement (sans l'appliquer).
static func preview_genome(g: Dictionary, add: Array, rem: Array, bio: String) -> Dictionary:
	var out := g.duplicate(true)
	var a: Array = (out.get("add", []) as Array).duplicate()
	var r: Array = (out.get("rem", []) as Array).duplicate()
	for tid in rem:
		if a.has(String(tid)):
			a.erase(String(tid))
		elif not r.has(String(tid)):
			r.append(String(tid))
	for tid in add:
		if r.has(String(tid)):
			r.erase(String(tid))
		elif not a.has(String(tid)):
			a.append(String(tid))
	out["add"] = a
	out["rem"] = r
	if bio != "":
		out["bio"] = bio
	_clean(out)
	return out


static func _clean(g: Dictionary) -> void:
	for k in ["add", "rem"]:
		if g.has(k) and (g[k] as Array).is_empty():
			g.erase(k)
	if String(g.get("bio", "")) == "":
		g.erase("bio")


## Points changés par un programme (au moins 1).
static func points_changed(add: Array, rem: Array) -> int:
	var n := 0
	for tid in add + rem:
		n += absi(trait_cost(String(tid)))
	return maxi(1, n)


## "" si l'empire peut lancer ce programme sur cette espèce, sinon la raison.
static func check_mod(state: GameState, eid: int, fid: String, add: Array, rem: Array, bio: String) -> String:
	if not applies(state, eid):
		return "l'ingénierie des espèces n'est pas en jeu"
	var e := state.get_empire(eid)
	if e.gene_path == "purete":
		return "votre serment de Pureté interdit tout programme"
	if GeneticsBridges.moratorium(state, eid):
		return "le Moratoire génétique de l'Amphictyonie interdit tout programme"
	if not species_of(state, eid).has(fid):
		return "cette espèce ne vit pas chez vous"
	if GeneticsBridges.flesh_sacred(state, eid, fid):
		return "votre foi tient la chair natale pour sacrée (Sainteté de la chair)"
	if fid != e.faction_id and GeneticsBridges.foreign_banned(state, eid, fid):
		return "l'Intégrité des peuples (Nomos) interdit de façonner une espèce née chez un autre empire"
	if programs(state, eid).size() >= max_programs(state, eid):
		return "déjà %d programme(s) en cours" % max_programs(state, eid)
	for p: Dictionary in programs(state, eid):
		if String(p.get("fid", "")) == fid:
			return "un programme travaille déjà cette espèce"
	if add.is_empty() and rem.is_empty() and bio == "":
		return "rien à changer"
	if state.politics_on and fid != e.faction_id and Peoples.is_citizen(state, eid, fid) and Laws.is_enacted(state, eid, "charte_genome"):
		return "la Charte du génome interdit de modifier vos citoyens d'autres espèces"
	var base := fiche(state, eid, fid)
	var voies := voies_of(base, e.gene_path)
	var synth := String(FactionTraits.species(base).get("archetype", "")) == "synthetique"
	var cur := traits_of(base)
	var extra: Array = sub(state, "stolen").get(str(eid), []) + sub(state, "samples").get(str(eid), [])
	for tid in add:
		var t := trait_def(String(tid))
		if t.is_empty():
			return "trait inconnu : %s" % tid
		if cur.has(String(tid)):
			return "%s : l'espèce l'a déjà" % trait_label(String(tid))
		var v := String(t.get("voie", "creation"))
		if v == "special" and not extra.has(String(tid)):
			return "%s ne s'obtient pas par un programme" % trait_label(String(tid))
		if v != "creation" and v != "special" and not voies.has(v) and not extra.has(String(tid)):
			return "%s : voie %s fermée à cette espèce" % [trait_label(String(tid)), voie_label(v)]
		var need := _power_for_add(String(tid), synth)
		if need != "" and not has_power(state, eid, need):
			return "%s demande la technologie %s" % [trait_label(String(tid)), Research.tech(tech_for(need)).get("label", need)]
		for o in t.get("opposes", []):
			if cur.has(String(o)) and not rem.has(String(o)):
				return "%s et %s s'excluent" % [trait_label(String(tid)), trait_label(String(o))]
		if t.has("requires_archetype") and not (t["requires_archetype"] as Array).has(String(FactionTraits.species(base).get("archetype", ""))):
			return "%s : pas pour ce corps" % trait_label(String(tid))
	for tid in rem:
		if not cur.has(String(tid)):
			return "%s : l'espèce ne l'a pas" % trait_label(String(tid))
		if trait_def(String(tid)).is_empty():
			return "trait inconnu : %s" % tid
		var need2 := _power_for_rem(String(tid), e.genome.get(fid, {}), synth)
		if need2 != "" and not has_power(state, eid, need2):
			return "retirer %s demande la technologie %s" % [trait_label(String(tid)), Research.tech(tech_for(need2)).get("label", need2)]
	if bio != "":
		if not has_power(state, eid, "biome") and not free_biome_ready(state, eid):
			return "l'acclimatation demande la technologie %s" % Research.tech(tech_for("biome")).get("label", "")
		var pref: Array = base.get("preferred", [])
		if not (Species.parts()["biomes"] as Array).has(bio):
			return "biome inconnu : %s" % bio
		if not pref.is_empty() and String(pref[0]) == bio:
			return "le monde natal ne change jamais"
		if pref.size() >= 2 and String(pref[1]) == bio:
			return "c'est déjà son second biome"
	# Règles de la fiche après le changement.
	var g2 := preview_genome(e.genome.get(fid, {}), add, rem, bio)
	var after := apply_genome(GameData.faction(fid), g2, e.gene_path, fid == e.faction_id)
	var ts := traits_of(after)
	if counted_traits(ts) > trait_cap(state, eid, fid, g2):
		return "%d traits au plus pour cette espèce" % trait_cap(state, eid, fid, g2)
	var growth := 0
	var flaws := 0
	for tid in ts:
		var t2 := trait_def(String(tid))
		if bool(t2.get("growth", false)):
			growth += 1
		if int(t2.get("cost", 0)) < 0:
			flaws -= int(t2["cost"])
	if growth > c_int("margin", "max_growth", 1):
		return "un seul trait de croissance par espèce"
	if flaws > c_int("margin", "max_flaws", 3):
		return "les défauts rendent %d points au plus" % c_int("margin", "max_flaws", 3)
	var left := margin_total(state, eid, fid) - margin_used(g2)
	if left < 0:
		return "marge dépassée de %d point(s)" % -left
	return ""


## Technologie qu'il faut pour ajouter ce trait ("" : aucune).
static func _power_for_add(tid: String, synth: bool) -> String:
	var t := trait_def(tid)
	var v := String(t.get("voie", "creation"))
	if v == "cybernetique":
		return "cyber"
	if int(t.get("cost", 0)) < 0:
		return "reseq"
	if v == "synthetique" or synth:
		return "reprogram"
	return "add"


static func _power_for_rem(tid: String, g: Dictionary, synth: bool) -> String:
	if (g.get("add", []) as Array).has(tid):
		return "reprogram" if synth else "add"
	if trait_cost(tid) > 0:
		return "reseq"
	return "reprogram" if synth else "add"


static func voie_label(v: String) -> String:
	return String(cfg("voie_labels").get(v, v))


# --- Coût ---------------------------------------------------------------------------------------

## Ressource d'un programme : matériaux pour une espèce synthétique, Savoir sinon.
static func resource_for(state: GameState, eid: int, fid: String) -> String:
	var f := fiche(state, eid, fid)
	return "materials" if String(FactionTraits.species(f).get("archetype", "")) == "synthetique" else "knowledge"


## Pourcentage de remise (négatif) sur un programme de cette voie.
static func cost_pct(state: GameState, eid: int, voie: String) -> int:
	var e := state.get_empire(eid)
	var pct := 0
	if has_power(state, eid, "directed"):
		pct += c_int("directed", "cost_pct", -25)
	var tal := talent(state, eid)
	match voie:
		"genetique":
			pct += int(tal.get("gen_pct", 0))
		"cybernetique":
			pct += int(tal.get("cyber_pct", 0))
			if e != null and e.gene_path == "cybernetique":
				pct += int(path_def("cybernetique").get("cost_pct", 0))
		"synthetique":
			pct += int(tal.get("syn_pct", 0))
			if e != null and e.gene_path == "synthetique":
				pct += int(path_def("synthetique").get("cost_pct", 0))
		"harmoniques":
			pct += int(tal.get("harm_pct", 0))
	pct += GeneticsBridges.cost_pct(state, eid)
	return maxi(-75, pct)


## Voie dominante d'un changement (pour les remises).
static func voie_of_change(state: GameState, eid: int, fid: String, add: Array) -> String:
	var f := fiche(state, eid, fid)
	var arch := String(FactionTraits.species(f).get("archetype", ""))
	if arch == "synthetique":
		return "synthetique"
	if arch == "energetique":
		return "harmoniques"
	for tid in add:
		if String(trait_def(String(tid)).get("voie", "")) == "cybernetique":
			return "cybernetique"
	return "genetique"


@warning_ignore("integer_division")
static func mod_cost(state: GameState, eid: int, fid: String, add: Array, rem: Array, bio: String) -> int:
	var c := cfg("cost")
	var pop := maxi(1, pop_of(state, eid, fid))
	var v := int(c.get("base", 120)) + int(c.get("per_pop", 2)) * pop
	if not add.is_empty() or not rem.is_empty():
		v += int(c.get("per_point", 10)) * pop * points_changed(add, rem)
	if bio != "":
		v += int(c.get("biome", 30)) * pop
	v = v * (100 + cost_pct(state, eid, voie_of_change(state, eid, fid, add))) / 100
	if resource_for(state, eid, fid) == "materials":
		v = v * int(c.get("materials_pct", 100)) / 100
	return maxi(1, v)


# --- Programmes : lancement et paiement ---------------------------------------------------------

static func _new_prog(state: GameState, eid: int, kind: String, fid: String, cost: int, res: String) -> Dictionary:
	var id := int(state.genetics.get("seq", 1))
	state.genetics["seq"] = id + 1
	var p := {"id": id, "kind": kind, "fid": fid, "res": res, "cost": cost, "paid": 0, "start": state.tick}
	var key := str(eid)
	var l: Array = sub(state, "prog").get(key, [])
	l.append(p)
	sub(state, "prog")[key] = l
	return p


static func start_mod(state: GameState, eid: int, fid: String, add: Array, rem: Array, bio: String) -> void:
	var free := bio != "" and not has_power(state, eid, "biome") and free_biome_ready(state, eid)
	var cost := mod_cost(state, eid, fid, add, rem, bio)
	var p := _new_prog(state, eid, "mod", fid, cost, resource_for(state, eid, fid))
	p["add"] = add.duplicate()
	p["rem"] = rem.duplicate()
	p["bio"] = bio
	if free or (bio != "" and add.is_empty() and rem.is_empty() and free_biome_ready(state, eid)):
		# La mue (horde) : une acclimatation gratuite par ère.
		p["cost"] = 1
		sub(state, "bfree")[str(eid)] = Research.current_era(state, eid)


## Une acclimatation gratuite est-elle prête (talent « La mue ») ?
static func free_biome_ready(state: GameState, eid: int) -> bool:
	if int(talent(state, eid).get("free_biome", 0)) <= 0:
		return false
	return int(sub(state, "bfree").get(str(eid), 0)) < Research.current_era(state, eid)


static func check_cancel(state: GameState, eid: int, pid: int) -> String:
	for p: Dictionary in programs(state, eid):
		if int(p["id"]) == pid:
			return ""
	return "programme inconnu"


## Annule un programme : la moitié de ce qui a été versé revient.
@warning_ignore("integer_division")
static func cancel(state: GameState, eid: int, pid: int) -> void:
	var l: Array = programs(state, eid)
	for i in l.size():
		var p: Dictionary = l[i]
		if int(p["id"]) == pid:
			var e := state.get_empire(eid)
			var res := String(p.get("res", "knowledge"))
			e.resources[res] = int(e.resources.get(res, 0)) + int(p.get("paid", 0)) / 2
			l.remove_at(i)
			break


## Mensualité d'un programme.
@warning_ignore("integer_division")
static func installment(p: Dictionary) -> int:
	var m := maxi(1, c_int("cost", "min_months", 3))
	return maxi(1, (int(p["cost"]) + m - 1) / m)


## Mois restants estimés d'un programme.
@warning_ignore("integer_division")
static func months_left(p: Dictionary) -> int:
	var need := int(p["cost"]) - int(p.get("paid", 0))
	return maxi(0, (need + installment(p) - 1) / installment(p))


## Bilan mensuel d'un empire : les programmes prennent leur mensualité sur le stock (avant la
## recherche), ceux qui sont payés s'achèvent.
static func monthly_empire(state: GameState, e: Empire, added: Array[Dictionary]) -> void:
	if not applies(state, e.id):
		return
	var l: Array = programs(state, e.id)
	if l.is_empty():
		return
	var paused := GeneticsBridges.contaminated(state, e.id)
	var done := []
	for p: Dictionary in l:
		if paused:
			break
		var res := String(p.get("res", "knowledge"))
		var need := int(p["cost"]) - int(p.get("paid", 0))
		var pay := mini(mini(installment(p), need), maxi(0, int(e.resources.get(res, 0))))
		if pay > 0:
			e.resources[res] = int(e.resources.get(res, 0)) - pay
			p["paid"] = int(p.get("paid", 0)) + pay
		if int(p["paid"]) >= int(p["cost"]):
			done.append(p)
	for p: Dictionary in done:
		l.erase(p)
		complete(state, e.id, p, added)


## Achève un programme (aussi appelé par les tests).
static func complete(state: GameState, eid: int, p: Dictionary, added: Array[Dictionary]) -> void:
	var e := state.get_empire(eid)
	if e == null:
		return
	var fid := String(p.get("fid", ""))
	var kind := String(p.get("kind", "mod"))
	var pts := 0
	match kind:
		"mod":
			var g := preview_genome(e.genome.get(fid, {}), p.get("add", []), p.get("rem", []), String(p.get("bio", "")))
			_set_genome(state, e, fid, g)
			pts = points_changed(p.get("add", []), p.get("rem", []))
			if fid != e.faction_id and Peoples.is_citizen(state, eid, fid):
				_citizens_malus(state, eid, fid)
			var parts := PackedStringArray()
			for tid in p.get("add", []):
				parts.append("+" + trait_label(String(tid)))
			for tid in p.get("rem", []):
				parts.append("-" + trait_label(String(tid)))
			if String(p.get("bio", "")) != "":
				parts.append("second biome : %s" % String(GameData.planet_type(String(p["bio"])).get("label", p["bio"])).to_lower())
			added.append(state.add_chronicle("Programme d'ingénierie achevé chez %s : les %s changent (%s). Les anciens disent que c'était mieux avant ; les nouveaux ne se souviennent pas d'avant." % [
					e.display_name(), label(state, eid, fid), ", ".join(parts)], Espionage.private_to(state, [eid])))
			GeneticsBridges.on_program(state, eid, fid, p, added)
		"cyber":
			var g := (e.genome.get(fid, {}) as Dictionary).duplicate(true)
			g["cyber"] = true
			_set_genome(state, e, fid, g)
			pts = 1
			added.append(state.add_chronicle("%s : « Chair et acier ». Les %s naissent désormais avec leurs implants, et trouvent ça normal." % [e.display_name(), label(state, eid, fid)], Espionage.private_to(state, [eid])))
		"transfer":
			_transfer(state, e, fid, added)
			pts = 3
		_:
			GeneticsBridges.complete_other(state, eid, p, added)
			pts = 1
	var dk := str(eid)
	sub(state, "done")[dk] = int(sub(state, "done").get(dk, 0)) + 1
	_politics(state, eid, pts, "per_point")
	_stat(state, eid, "programs", 1)


static func _citizens_malus(state: GameState, eid: int, fid: String) -> void:
	var d := c_int("citizens", "integ", -10)
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner == eid and c.species.has(fid):
			c.integ[fid] = clampi(Peoples.integration(c, fid) + d, 0, 100)


static func _set_genome(state: GameState, e: Empire, fid: String, g: Dictionary) -> void:
	_clean(g)
	if g.is_empty():
		e.genome.erase(fid)
	else:
		e.genome[fid] = g
	e.genome_rev += 1
	e.hab_cache.clear()
	e.hab_cache_n = -1
	_talent_cache.clear()
	GeneticsBridges.refresh_lineages(state, e.id, fid)


static func _politics(state: GameState, eid: int, pts: int, key: String) -> void:
	if not state.politics_on or not Politics.applies(state, eid):
		return
	var pp: Dictionary = cfg("politics").get(key, {})
	var ks := pp.keys()
	ks.sort()
	for cur in ks:
		var v := int(pp[cur]) * maxi(1, pts)
		if v <= 0:
			continue
		var i := Politics.index_of(String(cur))
		for sid in Stability.systems_of(state, eid):
			Politics.push(state, sid, i, v)


static func _stat(state: GameState, eid: int, k: String, n: int) -> void:
	var key := str(eid)
	var st: Dictionary = sub(state, "st").get(key, {})
	st[k] = int(st.get(k, 0)) + n
	sub(state, "st")[key] = st


static func stat(state: GameState, eid: int, k: String) -> int:
	return int(sub(state, "st").get(str(eid), {}).get(k, 0))


# --- Cybernétique, Grand Transfert (prop. 10, 12) -----------------------------------------------

static func check_cyber(state: GameState, eid: int, fid: String) -> String:
	if not applies(state, eid):
		return "l'ingénierie des espèces n'est pas en jeu"
	var e := state.get_empire(eid)
	if e.gene_path == "purete":
		return "votre serment de Pureté interdit tout programme"
	if GeneticsBridges.moratorium(state, eid):
		return "le Moratoire génétique de l'Amphictyonie interdit tout programme"
	if not species_of(state, eid).has(fid):
		return "cette espèce ne vit pas chez vous"
	if not has_power(state, eid, "cyber"):
		return "il faut la technologie %s" % Research.tech(tech_for("cyber")).get("label", "")
	var f := fiche(state, eid, fid)
	if not is_organic(f):
		return "seuls les corps organiques reçoivent des implants"
	if bool(f.get("cyber", false)):
		return "cette espèce est déjà cybernétique"
	if programs(state, eid).size() >= max_programs(state, eid):
		return "déjà %d programme(s) en cours" % max_programs(state, eid)
	return ""


@warning_ignore("integer_division")
static func cyber_cost(state: GameState, eid: int, fid: String) -> int:
	var pop := maxi(1, pop_of(state, eid, fid))
	var v := c_int("cost", "cyber_entry", 150) + c_int("cost", "per_pop", 2) * pop + c_int("cost", "per_point", 10) * pop
	return maxi(1, v * (100 + cost_pct(state, eid, "cybernetique")) / 100)


static func start_cyber(state: GameState, eid: int, fid: String) -> void:
	_new_prog(state, eid, "cyber", fid, cyber_cost(state, eid, fid), "knowledge")


static func check_transfer(state: GameState, eid: int, fid: String) -> String:
	if not applies(state, eid):
		return "l'ingénierie des espèces n'est pas en jeu"
	var e := state.get_empire(eid)
	if e.gene_path != "synthetique":
		return "il faut s'être voué à la voie synthétique"
	if not has_power(state, eid, "transfer"):
		return "il faut la technologie %s" % Research.tech(tech_for("transfer")).get("label", "")
	if GeneticsBridges.moratorium(state, eid):
		return "le Moratoire génétique de l'Amphictyonie interdit tout programme"
	if not species_of(state, eid).has(fid):
		return "cette espèce ne vit pas chez vous"
	if not is_organic(fiche(state, eid, fid)):
		return "cette espèce n'est pas organique"
	if programs(state, eid).size() >= max_programs(state, eid):
		return "déjà %d programme(s) en cours" % max_programs(state, eid)
	return ""


@warning_ignore("integer_division")
static func transfer_cost(state: GameState, eid: int, fid: String) -> int:
	var pop := maxi(1, pop_of(state, eid, fid))
	var v := c_int("cost", "transfer_base", 600) + c_int("cost", "transfer_per_pop", 20) * pop
	return maxi(1, v * (100 + cost_pct(state, eid, "synthetique")) / 100)


static func start_transfer(state: GameState, eid: int, fid: String) -> void:
	_new_prog(state, eid, "transfer", fid, transfer_cost(state, eid, fid), "knowledge")


## Le Grand Transfert : l'espèce devient synthétique. Ses traits façonnés génétiques ou poussés
## deviennent des modules (les autres restent), les implants tombent (le châssis les remplace).
static func _transfer(state: GameState, e: Empire, fid: String, added: Array[Dictionary]) -> void:
	var g := (e.genome.get(fid, {}) as Dictionary).duplicate(true)
	g["synth"] = true
	g.erase("cyber")
	var keep := []
	for tid in g.get("add", []):
		var v := String(trait_def(String(tid)).get("voie", ""))
		if v == "cybernetique":
			continue
		keep.append(tid)
	g["add"] = keep
	_set_genome(state, e, fid, g)
	var tr := cfg("transfer")
	var pp: Dictionary = tr.get("politics", {})
	if state.politics_on and Politics.applies(state, e.id):
		for cur in ["academie", "forge"]:
			if int(pp.get(cur, 0)) > 0:
				for sid in Stability.systems_of(state, e.id):
					Politics.push(state, sid, Politics.index_of(cur), int(pp[cur]))
	added.append(state.add_chronicle("Le Grand Transfert chez %s : les %s quittent leurs corps pour des châssis. Les derniers repas sont servis ; personne n'a faim." % [
			e.display_name(), label(state, e.id, fid)], Espionage.private_to(state, [e.id])))
	_stat(state, e.id, "transfers", 1)
	if fid == e.faction_id:
		_stat(state, e.id, "founder_transfer", 1)


# --- Voie d'élévation (prop. 17-18) --------------------------------------------------------------

static func path_defs() -> Array:
	return cfg("paths").get("list", [])


static func path_def(id: String) -> Dictionary:
	for p: Dictionary in path_defs():
		if String(p["id"]) == id:
			return p
	return {}


static func programs_done(state: GameState, eid: int) -> int:
	return int(sub(state, "done").get(str(eid), 0))


static func check_path(state: GameState, eid: int, id: String) -> String:
	if not applies(state, eid):
		return "l'ingénierie des espèces n'est pas en jeu"
	var e := state.get_empire(eid)
	if e.gene_path != "":
		return "votre empire s'est déjà voué à une voie"
	if path_def(id).is_empty():
		return "voie inconnue : %s" % id
	if sub(state, "renounce").has(str(eid)):
		return "un serment renié ne se reprend pas"
	if id == "purete":
		if programs_done(state, eid) > 0 or not programs(state, eid).is_empty() or not e.genome.is_empty():
			return "la Pureté se jure avant tout programme"
		return ""
	var need := int(cfg("paths").get("min_programs", 3))
	if programs_done(state, eid) < need:
		return "il faut %d programmes achevés (%d)" % [need, programs_done(state, eid)]
	return ""


static func choose_path(state: GameState, eid: int, id: String, added: Array[Dictionary] = []) -> void:
	var e := state.get_empire(eid)
	e.gene_path = id
	e.genome_rev += 1
	e.hab_cache.clear()
	e.hab_cache_n = -1
	if id == "cybernetique":
		for fid in species_of(state, eid):
			if is_organic(fiche(state, eid, fid)):
				var g := (e.genome.get(fid, {}) as Dictionary).duplicate(true)
				g["cyber"] = true
				e.genome[fid] = g
		e.genome_rev += 1
	if id == "purete":
		_politics(state, eid, 1, "purete")
	GeneticsBridges.refresh_lineages(state, eid, "")
	var pd := path_def(id)
	added.append(state.add_chronicle("%s se voue à la voie « %s ». %s" % [e.display_name(), String(pd.get("label", id)), String(pd.get("text", ""))], Espionage.private_to(state, [eid])))


static func check_renounce(state: GameState, eid: int) -> String:
	var e := state.get_empire(eid)
	if e == null or e.gene_path != "purete":
		return "vous n'avez pas juré la Pureté"
	return ""


## Renier la Pureté : la voie s'efface, crise de stabilité, plus aucun serment possible.
static func renounce(state: GameState, eid: int) -> void:
	var e := state.get_empire(eid)
	e.gene_path = ""
	e.genome_rev += 1
	sub(state, "renounce")[str(eid)] = state.tick + int(cfg("paths").get("renounce", {}).get("days", 720))


## Stabilité d'empire : Pureté, serment renié.
static func empire_stability_parts(state: GameState, eid: int) -> Array:
	var out := []
	if not applies(state, eid):
		return out
	var e := state.get_empire(eid)
	if e.gene_path == "purete":
		out.append(["Serment de Pureté", int(path_def("purete").get("stability", 5))])
	if state.tick < int(sub(state, "renounce").get(str(eid), 0)):
		out.append(["Pureté reniée", int(cfg("paths").get("renounce", {}).get("stability", -20))])
	return out


## Stabilité d'un système : espèce « Dociles » majoritaire.
static func system_stability_parts(state: GameState, sid: int, owner: int) -> Array:
	var out := []
	if not applies(state, owner):
		return out
	var e := state.get_empire(owner)
	if e.genome.is_empty():
		return out
	var cnt := {}
	for pid in state.galaxy.systems[sid].planet_ids:
		var c: Colony = state.colonies.get(pid)
		if c == null or c.owner != owner or not c.is_colony():
			continue
		var pc := Peoples.counts(state, c) if not c.species.is_empty() else {e.faction_id: c.population}
		for fid in pc:
			cnt[fid] = int(cnt.get(fid, 0)) + int(pc[fid])
	var best := ""
	var best_n := 0
	var ks := cnt.keys()
	ks.sort()
	for fid in ks:
		if int(cnt[fid]) > best_n:
			best = String(fid)
			best_n = int(cnt[fid])
	if best == "":
		return out
	var v := int(fiche(state, owner, best).get("stability", 0))
	if v != 0:
		out.append(["Espèce façonnée docile", v])
	return out


# --- Effets lus ailleurs -----------------------------------------------------------------------

## Habitabilité en plus (trait Adaptables) d'une fiche.
static func hab_plus(f: Dictionary) -> int:
	return int(f.get("hab_plus", 0))


## Entretien des implants d'une espèce pour n habitants : {"energy": …}.
@warning_ignore("integer_division")
static func implant_upkeep(f: Dictionary, n: int) -> int:
	var k := 0
	for tid in traits_of(f):
		if bool(trait_def(String(tid)).get("implant", false)):
			k += 1
	if k == 0 or n <= 0:
		return 0
	return k * c_int("implant_upkeep", "energy", 1) * n / maxi(1, c_int("implant_upkeep", "per_pop", 10))


## Années de vie en plus (ou en moins) des héros et souverains d'une espèce.
static func life_years(state: GameState, eid: int, fid: String) -> int:
	if not applies(state, eid):
		return 0
	return int(fiche(state, eid, fid if fid != "" else state.get_empire(eid).faction_id).get("life_years", 0))


# --- Commandes ---------------------------------------------------------------------------------

## Vérifie un ordre "genetics" : act et paramètres (d : dictionnaire).
static func check(state: GameState, eid: int, act: String, d: Dictionary) -> String:
	if not applies(state, eid):
		return "l'ingénierie des espèces n'est pas en jeu"
	match act:
		"mod":
			return check_mod(state, eid, String(d.get("fid", "")), d.get("add", []), d.get("rem", []), String(d.get("bio", "")))
		"cyber":
			return check_cyber(state, eid, String(d.get("fid", "")))
		"transfer":
			return check_transfer(state, eid, String(d.get("fid", "")))
		"cancel":
			return check_cancel(state, eid, int(d.get("id", -1)))
		"path":
			return check_path(state, eid, String(d.get("path", "")))
		"renounce":
			return check_renounce(state, eid)
	return GeneticsBridges.check(state, eid, act, d)


static func apply(state: GameState, eid: int, act: String, d: Dictionary) -> Array[Dictionary]:
	var added: Array[Dictionary] = []
	match act:
		"mod":
			start_mod(state, eid, String(d["fid"]), d.get("add", []), d.get("rem", []), String(d.get("bio", "")))
		"cyber":
			start_cyber(state, eid, String(d["fid"]))
		"transfer":
			start_transfer(state, eid, String(d["fid"]))
		"cancel":
			cancel(state, eid, int(d["id"]))
		"path":
			choose_path(state, eid, String(d["path"]), added)
		"renounce":
			renounce(state, eid)
		_:
			GeneticsBridges.apply(state, eid, act, d, added)
	return added


## Bilan mensuel global (hybrides, griefs).
static func monthly(state: GameState, added: Array[Dictionary]) -> void:
	if not enabled(state):
		return
	GeneticsBridges.monthly(state, added)


## Expérience en plus (en points de pourcentage) des héros d'un empire (Mémoire étendue).
static func hero_xp_bonus(state: GameState, eid: int) -> int:
	if not applies(state, eid):
		return 0
	return int(state.get_empire(eid).faction().get("hero_xp_pct", 100)) - 100


## Combat au sol : bonus façonné (combat.ground_pct) des régiments de cette espèce.
static func ground_pct(state: GameState, eid: int, fid: String) -> int:
	if not applies(state, eid):
		return 100
	var f := fiche(state, eid, fid if fid != "" else state.get_empire(eid).faction_id)
	if not bool(f.get("engineered", false)):
		return 100
	return int(f.get("combat", {}).get("ground_pct", 100))


## Régiments clonés (voie génétique) : recrutement plus rapide (pourcentage négatif de durée).
static func clone_days_pct(state: GameState, eid: int) -> int:
	if not applies(state, eid) or state.get_empire(eid).gene_path != "genetique":
		return 0
	return -c_int("clones", "speed_pct", 50)


## Fléaux : habitants perdus (trait Résistants : moitié moins).
@warning_ignore("integer_division")
static func plague_loss(state: GameState, eid: int, pop: int) -> int:
	if pop <= 0 or not applies(state, eid):
		return pop
	return maxi(1, pop * int(state.get_empire(eid).faction().get("plague_pct", 100)) / 100)


## Furtivité : détection en plus (Yeux-senseurs) et camouflage en plus (Résonance du Voile).
static func detect_bonus(state: GameState, eid: int) -> int:
	if not applies(state, eid):
		return 0
	return int(state.get_empire(eid).faction().get("detect_bonus", 0))


static func cloak_bonus(state: GameState, eid: int) -> int:
	if eid >= state.empires.size() or not applies(state, eid):
		return 0
	return int(state.get_empire(eid).faction().get("cloak_bonus", 0))


## Registre cosmique : pourcentage des échos gagnés (Chœur d'échos).
static func echoes_pct(state: GameState, eid: int) -> int:
	if not applies(state, eid):
		return 100
	return int(state.get_empire(eid).faction().get("echoes_pct", 100))


## Biomasse tirée d'un peuple digéré (trait Savoureux de son espèce fondatrice), en pourcentage.
static func savoury_pct(state: GameState, eid: int) -> int:
	if not applies(state, eid):
		return 100
	return int(state.get_empire(eid).faction().get("savoury", 100))
