class_name Rulers
extends RefCounted
## Souverains (étude « Souverain et dynastie », 2026-11-16 ; data/rulers.json).
## Chaque empire a un souverain, sur une place à part (hors limite de héros, jamais renvoyé) : nom,
## portrait tiré de la galerie propre aux souverains, âge, quatre aptitudes de 0 à 6 (Gestion, Guerre,
## Éloquence, Intrigue), un archétype de règne avec son pouvoir à recharge, une légitimité de 0 à 100,
## des surnoms gagnés par le règne et une ambition choisie à l'avènement. Il vieillit et meurt ; la
## succession suit la couche gouvernement (voir RulersSuccession). La dynastie, la Cour, la régence, les
## mariages, les héritages et les prétendants : RulersDynasty. Les ponts avec les autres piliers :
## RulersBridges. La mort des héros au combat : HeroFall.
##
## Réglage « Souverains » : Mortels (défaut d'une nouvelle partie), Immortels (pas de succession) ou
## Aucun. Sans l'option (tests), pas de souverain.
##
## État : state.rulers = {"mode", "e": {"empire": E}}. E = {"r": souverain ({} = trône vacant),
##  "adj": ajustement de légitimité, "law", "reigns": [règnes passés], "acts": {acte: n} du règne,
##  "base": {mesure: valeur à l'avènement}, "amb": {"id", "base"}, "amb_done": [ambitions réussies],
##  "amb_next": jour de la prochaine ambition, "power_cd", "power_until", "power_arch", "vacant": jour de
##  fin d'interrègne (0 = aucun), "vacant_kind", "wobbly": fin de la Couronne vacillante, "terms",
##  "term_end", "iter_next", "inc": [revenus d'énergie des derniers trimestres], "fun": {"id", "key",
##  "i", "until"}, "cap": capitale suivie, "sys_n": systèmes au dernier bilan, "lost": systèmes perdus
##  sous le règne, "cap_lost", "wound": jour de guérison, "notes": {"id d'événement": textes des cartes},
##  "used_pics": portraits déjà pris, "house", plus la dynastie (RulersDynasty)}.
## Souverain : {"name", "g" (m | f | n), "portrait", "born", "life" (années, 0 = sans limite), "arch",
##  "apt": {aptitude: 0-6}, "cogs": [surnoms], "post" ("" | fleet | capital), "target", "how" (clé de
##  legit_start), "house", "ord", "from", "hero" (identifiant du héros d'origine, -1)}.

const APTS := ["gestion", "guerre", "eloquence", "intrigue"]
const DAYS_PER_YEAR := 360
const ROMAN := ["", "", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII", "XIII", "XIV", "XV"]


static func data() -> Dictionary:
	return GameData.rulers()


static func rules() -> Dictionary:
	return data()["rules"]


static func r_int(key: String) -> int:
	return int(rules().get(key, 0))


static func mode_defs() -> Array:
	return data().get("modes", [])


static func default_mode() -> String:
	return String(data().get("default_mode", "mortels"))


static func arch_def(id: String) -> Dictionary:
	return (data()["archetypes"] as Dictionary).get(id, {})


static func arch_ids() -> Array:
	var ids := (data()["archetypes"] as Dictionary).keys()
	return ids


static var _cog_index: Dictionary = {}
static var _amb_index: Dictionary = {}


static func cog_def(id: String) -> Dictionary:
	if _cog_index.is_empty():
		for c: Dictionary in data()["cognomens"]:
			_cog_index[String(c["id"])] = c
	if id.begins_with("amb:"):
		var a := amb_def(id.substr(4))
		return {"id": id, "m": String(a.get("cog", {}).get("m", "")), "f": String(a.get("cog", {}).get("f", "")), "legit": 0,
				"fam": "ambition", "src": "amb", "k": "", "n": 0}
	if id.begins_with("deed:"):
		var lbl := Deeds.title_label(id.substr(5))
		return {"id": id, "m": "le " + lbl, "f": "la " + lbl, "legit": 10, "fam": "haut fait", "src": "deed", "k": "", "n": 0}
	return _cog_index.get(id, {})


static func amb_def(id: String) -> Dictionary:
	if _amb_index.is_empty():
		for a: Dictionary in data()["ambitions"]:
			_amb_index[String(a["id"])] = a
	return _amb_index.get(id, {})


# --- Réglage, sauvegarde -----------------------------------------------------------------------

static func mode(state: GameState) -> String:
	return String(state.rulers.get("mode", "aucun"))


static func enabled(state: GameState) -> bool:
	return not state.rulers.is_empty()


static func mortal(state: GameState) -> bool:
	return mode(state) == "mortels"


static func worth_saving(state: GameState) -> bool:
	return not state.rulers.is_empty()


static func setup(state: GameState, mode_id: String) -> void:
	state.rulers = {}
	var ok := false
	for m: Dictionary in mode_defs():
		if String(m["id"]) == mode_id:
			ok = true
	if not ok or mode_id == "aucun":
		return
	state.rulers = {"mode": mode_id, "e": {}}
	for e in state.empires:
		if e.eliminated or e.is_npc():
			continue
		found(state, e.id)


## Le premier souverain d'un empire (début de partie, ou empire né en cours de partie).
static func found(state: GameState, eid: int, how := "fondateur") -> Dictionary:
	var en := _blank(state, eid)
	(state.rulers["e"] as Dictionary)[str(eid)] = en
	var r := make_ruler(state, eid, ["fond", eid], how)
	crown(state, eid, r, [], false)
	return en


static func _blank(state: GameState, eid: int) -> Dictionary:
	var houses: Array = data()["houses"]
	return {"r": {}, "adj": 0, "law": String(data().get("default_law", "primogeniture")), "reigns": [], "acts": {}, "base": {},
			"amb": {}, "amb_done": [], "amb_next": 0, "power_cd": 0, "power_until": 0, "power_arch": "", "vacant": 0,
			"vacant_kind": "", "wobbly": 0, "terms": 0, "term_end": 0, "iter_next": 0, "inc": [], "fun": {}, "cap": -1,
			"sys_n": -1, "lost": 0, "cap_lost": 0, "wound": 0, "notes": {}, "used_pics": [],
			"house": String(houses[_h(state, ["maison", eid]) % houses.size()]),
			"heirs": [], "next_child": 0, "consort": "", "spouse": -1, "renown": 0, "legacies": {}, "regent": {},
			"star": -1, "star_seen": [], "low_since": 0, "unrest": 0, "child_n": 0}


static func to_dict(state: GameState) -> Dictionary:
	return Ancients._sorted(state.rulers)


static func from_dict(state: GameState, d: Dictionary) -> void:
	state.rulers = {}
	if d.is_empty():
		return
	state.rulers = GameData._to_ints(d.duplicate(true))


static func _h(state: GameState, parts: Array) -> int:
	return absi(hash([state.seed_value, "souverain"] + parts))


# --- Lecture -----------------------------------------------------------------------------------

static func entry(state: GameState, eid: int) -> Dictionary:
	if state.rulers.is_empty():
		return {}
	return (state.rulers["e"] as Dictionary).get(str(eid), {})


static func ruler(state: GameState, eid: int) -> Dictionary:
	return entry(state, eid).get("r", {})


static func has_ruler(state: GameState, eid: int) -> bool:
	return not ruler(state, eid).is_empty()


static func government(state: GameState, eid: int) -> String:
	var e := state.get_empire(eid)
	return String(e.faction().get("species", {}).get("gouvernement", "feodalite")) if e else "feodalite"


static func succession(state: GameState, eid: int) -> Dictionary:
	var s: Dictionary = data()["succession"]
	return s.get(government(state, eid), s["feodalite"])


static func kind(state: GameState, eid: int) -> String:
	return String(succession(state, eid)["kind"])


static func immortal_kind(state: GameState, eid: int) -> bool:
	return (data()["immortal_kinds"] as Array).has(kind(state, eid))


static func hereditary(state: GameState, eid: int) -> bool:
	return (data()["hereditary_kinds"] as Array).has(kind(state, eid))


static func title(state: GameState, eid: int, r: Dictionary) -> String:
	var t: Array = succession(state, eid)["title"]
	return String(t[1] if _form(state, eid, r) == "f" else t[0])


static func _form(state: GameState, eid: int, r: Dictionary) -> String:
	var g := String(r.get("g", "m"))
	if g == "n":
		return "f" if kind(state, eid) == "reine" else "m"
	return g


static func cog_text(state: GameState, eid: int, r: Dictionary, cid: String) -> String:
	var c := cog_def(cid)
	return String(c.get(_form(state, eid, r), c.get("m", "")))


## Le surnom affiché : celui qui vaut le plus de légitimité (le dernier obtenu à égalité).
static func main_cog(r: Dictionary) -> String:
	var best := ""
	var bv := -1000
	for cid in r.get("cogs", []):
		var v := int(cog_def(String(cid)).get("legit", 0))
		if String(cid).begins_with("amb:"):
			v = 12
		if v >= bv:
			bv = v
			best = String(cid)
	return best


## « Aldra II la Vaillante ».
static func name_of(state: GameState, eid: int, r: Dictionary) -> String:
	if r.is_empty():
		return "Trône vacant"
	var s := String(r["name"])
	var o := int(r.get("ord", 1))
	if o >= 2:
		s += " " + String(ROMAN[mini(o, ROMAN.size() - 1)])
	var mc := main_cog(r)
	if mc != "":
		s += " " + cog_text(state, eid, r, mc)
	return s


## « Reine Aldra II la Vaillante ».
static func full_name(state: GameState, eid: int, r: Dictionary = {}) -> String:
	if r.is_empty():
		r = ruler(state, eid)
	if r.is_empty():
		return "Trône vacant"
	return "%s %s" % [title(state, eid, r), name_of(state, eid, r)]


static func age(state: GameState, r: Dictionary) -> int:
	@warning_ignore("integer_division")
	return (state.tick - int(r.get("born", state.tick))) / DAYS_PER_YEAR


static func reign_years(state: GameState, r: Dictionary) -> int:
	@warning_ignore("integer_division")
	return (state.tick - int(r.get("from", state.tick))) / DAYS_PER_YEAR


static func vacant(state: GameState, eid: int) -> bool:
	return enabled(state) and not entry(state, eid).is_empty() and ruler(state, eid).is_empty()


static func is_wounded(state: GameState, eid: int) -> bool:
	return int(entry(state, eid).get("wound", 0)) > state.tick


# --- Création ----------------------------------------------------------------------------------

static func _sp_arch(state: GameState, eid: int) -> String:
	return Heroes._archetype_raw(state, eid)


## Portraits de la galerie des souverains pour l'archétype d'espèce (ceux des humanoïdes si aucun).
static func portraits_for(sp_arch: String) -> Array[String]:
	var out: Array[String] = []
	for p: Dictionary in data()["portraits"]:
		if (p.get("archetypes", []) as Array).has(sp_arch):
			out.append(String(p["id"]))
	if out.is_empty() and sp_arch != "humanoide":
		return portraits_for("humanoide")
	return out


static func portrait_def(id: String) -> Dictionary:
	for p: Dictionary in data()["portraits"]:
		if String(p["id"]) == id:
			return p
	return {}


## Un portrait que l'empire n'a pas encore donné à un souverain (la galerie est assez grande pour
## éviter les doublons sur plusieurs générations) ; on repart de zéro quand tout a servi.
static func _pick_portrait(state: GameState, eid: int, salt: Array) -> String:
	var pics := portraits_for(_sp_arch(state, eid))
	if pics.is_empty():
		return ""
	var en := entry(state, eid)
	var used: Array = en.get("used_pics", [])
	var free: Array[String] = []
	for p in pics:
		if not used.has(p):
			free.append(p)
	if free.is_empty():
		used.clear()
		free = pics
	var got := free[_h(state, salt + ["pic"]) % free.size()]
	if not en.is_empty():
		used.append(got)
	return got


static func _name_pick(state: GameState, eid: int, salt: Array, want_g := "") -> Array:
	var names: Dictionary = data()["names"]
	var t: Dictionary = names.get(_sp_arch(state, eid), names["humanoide"])
	if t.has("n"):
		var l: Array = t["n"]
		return [String(l[_h(state, salt + ["nom"]) % l.size()]), "n"]
	var g := want_g if want_g == "m" or want_g == "f" else ("f" if _h(state, salt + ["genre"]) % 2 == 1 else "m")
	var l2: Array = t[g]
	return [String(l2[_h(state, salt + ["nom"]) % l2.size()]), g]


## Archétype de règne tiré par affinités : credo du peuple, courant au pouvoir.
static func _pick_arch(state: GameState, eid: int, salt: Array, prefer_current := "") -> String:
	var e := state.get_empire(eid)
	var credo := String(e.faction().get("species", {}).get("credo", "")) if e else ""
	var lead := prefer_current
	if lead == "" and e and Politics.applies(state, eid):
		lead = Politics.current_id(Politics.lead(state, eid))
	var ids := arch_ids()
	var total := 0
	var weights: Array[int] = []
	for a in ids:
		var d := arch_def(String(a))
		var w := 10
		if (d.get("credo", []) as Array).has(credo):
			w += 15
		if lead != "" and String(d.get("current", "")) == lead:
			w += 25 if prefer_current != "" else 10
		weights.append(w)
		total += w
	var roll := _h(state, salt + ["arch"]) % maxi(1, total)
	for i in ids.size():
		roll -= weights[i]
		if roll < 0:
			return String(ids[i])
	return String(ids[0])


static func apt_of_cls(cls: String) -> String:
	for a in APTS:
		if String(data()["aptitudes"][a].get("cls", "")) == cls:
			return a
	return "gestion"


## Aptitudes tirées : l'aptitude de l'archétype d'abord, le reste au hasard ; plafond apt_max.
static func roll_apts(state: GameState, salt: Array, arch: String, bonus := 0) -> Dictionary:
	var mx := int(data().get("apt_max", 6))
	var apt := {"gestion": 0, "guerre": 0, "eloquence": 0, "intrigue": 0}
	var main := apt_of_cls(String((arch_def(arch).get("cls", ["intendant"]) as Array)[0]))
	apt[main] = 2
	var pts := 5 + _h(state, salt + ["pts"]) % 5 + bonus
	for i in pts:
		var a: String = APTS[_h(state, salt + ["apt", i]) % APTS.size()]
		if int(apt[a]) >= mx:
			a = main if int(apt[main]) < mx else a
		apt[a] = mini(mx, int(apt[a]) + 1)
	return apt


static func life_of(state: GameState, eid: int) -> int:
	if not mortal(state) or immortal_kind(state, eid):
		return 0
	var y := Heroes.life_years(state, eid)
	if y <= 0:
		return 0
	return y + RulersDynasty.legacy_sum(state, eid, "life")


## Un souverain tiré par hachage (salt : graine propre). how : clé de legit_start.
static func make_ruler(state: GameState, eid: int, salt: Array, how: String, age_years := -1, arch := "", want_g := "") -> Dictionary:
	var ages: Array = rules()["start_age"]
	var a := age_years if age_years >= 0 else int(ages[0]) + _h(state, salt + ["age"]) % (int(ages[1]) - int(ages[0]) + 1)
	if arch == "":
		arch = _pick_arch(state, eid, salt)
	var nm := _name_pick(state, eid, salt, want_g)
	return {"name": nm[0], "g": nm[1], "portrait": _pick_portrait(state, eid, salt), "born": state.tick - a * DAYS_PER_YEAR,
			"life": life_of(state, eid), "arch": arch, "apt": roll_apts(state, salt, arch), "cogs": [], "post": "", "target": -1,
			"how": how, "house": String(entry(state, eid).get("house", "")), "ord": 1, "from": state.tick, "hero": -1}


## Un héros monte sur le trône (Épreuve, Conclave, Directeur, nouvelle maison…) : il quitte les héros.
static func from_hero(state: GameState, eid: int, h: Dictionary, how: String, arch := "") -> Dictionary:
	var cls := String(h["cls"])
	if arch == "":
		arch = _arch_for_cls(state, eid, cls, ["h", int(h["id"])])
	var apt := roll_apts(state, ["hero", int(h["id"])], arch, 0)
	var main := apt_of_cls(cls)
	apt[main] = mini(int(data().get("apt_max", 6)), int(apt[main]) + int(h.get("lvl", 1)) / 2 + 1)
	var g := "n" if not (data()["names"] as Dictionary).get(_sp_arch(state, eid), {}).has("m") else ("f" if _h(state, ["hg", int(h["id"])]) % 2 == 1 else "m")
	var name := String(h["name"]).split(",")[0]
	var r := {"name": name, "g": g, "portrait": _pick_portrait(state, eid, ["hero", int(h["id"])]), "born": int(h["born"]),
			"life": life_of(state, eid), "arch": arch, "apt": apt, "cogs": [], "post": "", "target": -1, "how": how,
			"house": String(entry(state, eid).get("house", "")), "ord": 1, "from": state.tick, "hero": int(h["id"])}
	state.heroes.erase(int(h["id"]))
	Relics.on_hero_gone(state, int(h["id"]))
	return r


static func _arch_for_cls(state: GameState, eid: int, cls: String, salt: Array) -> String:
	var fit: Array[String] = []
	for a in arch_ids():
		if (arch_def(String(a)).get("cls", []) as Array).has(cls):
			fit.append(String(a))
	if fit.is_empty():
		return _pick_arch(state, eid, salt)
	return fit[_h(state, salt + ["ac"]) % fit.size()]


## Numéro de règne : combien de prédécesseurs ont porté ce nom, plus un.
static func _ordinal(en: Dictionary, name: String) -> int:
	var n := 1
	for rg: Dictionary in en.get("reigns", []):
		if String(rg.get("first", "")) == name:
			n += 1
	return n


# --- Avènement ---------------------------------------------------------------------------------

## Mesures « sd » à garder à l'avènement (gagnées depuis).
static func _sd_keys() -> Array[String]:
	var out: Array[String] = []
	for c: Dictionary in data()["cognomens"]:
		if String(c["src"]) == "sd" and not out.has(String(c["k"])):
			out.append(String(c["k"]))
	for a: Dictionary in data()["ambitions"]:
		if String(a["src"]) == "sd" and not out.has(String(a["k"])):
			out.append(String(a["k"]))
	return out


## Couronne un souverain. card : carte d'avènement avec le choix de l'ambition.
static func crown(state: GameState, eid: int, r: Dictionary, added: Array[Dictionary], card := true) -> void:
	var en := entry(state, eid)
	if en.is_empty():
		return
	var had := not (en.get("reigns", []) as Array).is_empty()
	r["ord"] = _ordinal(en, String(r["name"]))
	r["from"] = state.tick
	if String(r.get("house", "")) == "":
		r["house"] = String(en["house"])
	en["r"] = r
	en["acts"] = {}
	en["vacant"] = 0
	en["vacant_kind"] = ""
	en["amb"] = {}
	en["amb_done"] = []
	en["amb_next"] = state.tick + r_int("ambition_days")
	en["power_cd"] = state.tick
	en["power_until"] = 0
	en["lost"] = 0
	en["cap_lost"] = 0
	en["wound"] = 0
	en["adj"] = 0
	en["low_since"] = 0
	var base := {}
	for k in _sd_keys():
		base[k] = DeedsEval.value(state, eid, k)
	en["base"] = base
	var e := state.get_empire(eid)
	en["cap"] = e.capital_planet if e else -1
	en["sys_n"] = DeedsEval.value(state, eid, "systems") if e else 0
	if had and mortal(state):
		en["wobbly"] = state.tick + r_int("wobbly_days")
	# Surnoms d'avènement.
	var cogs: Array = r["cogs"]
	if String(r["how"]) == "usurpateur" and not cogs.has("usurpateur"):
		cogs.append("usurpateur")
	if age(state, r) < r_int("majority") + 4 and not cogs.has("jeune") and hereditary(state, eid):
		cogs.append("jeune")
	# Mandats (république), itérations (conscience).
	match kind(state, eid):
		"election":
			en["terms"] = 1
			en["term_end"] = state.tick + r_int("republic_term_days")
		"iteration":
			en["iter_next"] = state.tick + r_int("iteration_years") * DAYS_PER_YEAR
		"conseil":
			en["inc"] = []
	RulersDynasty.on_crown(state, eid, r)
	Relics.touch(state)
	if card:
		offer_ambition(state, eid, added, true)


## Trois ambitions tirées selon l'archétype (et les conditions de couche) ; carte d'avènement.
static func offer_ambition(state: GameState, eid: int, added: Array[Dictionary], accession := false) -> void:
	var en := entry(state, eid)
	var r: Dictionary = en["r"]
	var mine: Array[String] = []
	var rest: Array[String] = []
	for a: Dictionary in data()["ambitions"]:
		var id := String(a["id"])
		if (en["amb_done"] as Array).has(id):
			continue
		if a.has("cond") and not Events._layers_ok(state, eid, a["cond"]):
			continue
		if _amb_progress(state, eid, a, _amb_base(state, eid, a)) >= int(a["n"]):
			continue
		if (a.get("arch", []) as Array).has(String(r["arch"])):
			mine.append(id)
		else:
			rest.append(id)
	var salt := ["amb", eid, state.tick]
	var sorter := func(x: String, y: String) -> bool:
		return _h(state, salt + [x]) < _h(state, salt + [y])
	mine.sort_custom(sorter)
	rest.sort_custom(sorter)
	var pick: Array = []
	for id in mine:
		if pick.size() < 2:
			pick.append(id)
	for id in rest:
		if pick.size() < 3:
			pick.append(id)
	for id in mine:
		if pick.size() < 3 and not pick.has(id):
			pick.append(id)
	if pick.is_empty():
		en["amb_next"] = state.tick + 4 * r_int("ambition_days")
		return
	while pick.size() < 3:
		pick.append(pick[0])
	var eid_ev := state.next_event_id
	Events.push(state, eid, "ruler_accession", {}, added)
	_note(state, eid, eid_ev, {"amb": pick, "accession": 1 if accession else 0})
	en["amb_next"] = 0


static func _note(state: GameState, eid: int, ev_id: int, d: Dictionary) -> void:
	var notes: Dictionary = entry(state, eid)["notes"]
	notes[str(ev_id)] = d
	var keys := notes.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return int(a) < int(b))
	while keys.size() > 12:
		notes.erase(keys.pop_front())


static func note_of(state: GameState, eid: int, item: Dictionary) -> Dictionary:
	return (entry(state, eid).get("notes", {}) as Dictionary).get(str(int(item.get("id", -1))), {})


# --- Légitimité --------------------------------------------------------------------------------

## Légitimité 0-100 : départ selon la succession, surnoms (ceux des prédécesseurs à 1/2, 1/3…),
## ajustements (victoires, défaites, ambition, régence…), héritages, Couronne vacillante.
static func legitimacy(state: GameState, eid: int) -> int:
	var en := entry(state, eid)
	var r: Dictionary = en.get("r", {})
	if r.is_empty():
		return 0
	var v := int((data()["legit_start"] as Dictionary).get(String(r.get("how", "heritier")), 50))
	v += int(en.get("adj", 0))
	for cid in r.get("cogs", []):
		v += int(cog_def(String(cid)).get("legit", 0))
	v += _past_cogs(en)
	v += RulersDynasty.legacy_sum(state, eid, "legit")
	v += RulersBridges.legit_bonus(state, eid)
	if int(en.get("wobbly", 0)) > state.tick:
		v -= 10
	return clampi(v, 0, r_int("legit_max"))


## Surnoms des prédécesseurs : le meilleur de chacun, divisé par 2, 3, 4… (Old World).
static func _past_cogs(en: Dictionary) -> int:
	var reigns: Array = en.get("reigns", [])
	var v := 0
	var n := 0
	for i in range(reigns.size() - 1, -1, -1):
		n += 1
		if n > r_int("past_cognomen_ruler"):
			break
		var best := 0
		for cid in (reigns[i] as Dictionary).get("cogs", []):
			best = maxi(best, int(cog_def(String(cid)).get("legit", 0)))
		@warning_ignore("integer_division")
		v += best / (n + 1)
	return v


static func adjust(state: GameState, eid: int, n: int) -> void:
	var en := entry(state, eid)
	if en.is_empty() or (en["r"] as Dictionary).is_empty() or n == 0:
		return
	en["adj"] = clampi(int(en["adj"]) + n, r_int("legit_adj_min"), r_int("legit_adj_max"))


# --- Effets ------------------------------------------------------------------------------------

## Aptitudes qui comptent pour l'empire : celles du souverain (ou du régent), plus la moitié de celles
## de la Cour (voir RulersDynasty).
static func apts(state: GameState, eid: int) -> Dictionary:
	var out := {"gestion": 0, "guerre": 0, "eloquence": 0, "intrigue": 0}
	var en := entry(state, eid)
	if en.is_empty():
		return out
	var src: Dictionary = {}
	if not (en.get("regent", {}) as Dictionary).is_empty():
		src = en["regent"].get("apt", {})
	elif not (en["r"] as Dictionary).is_empty():
		src = en["r"]["apt"]
	for a in APTS:
		out[a] = int(src.get(a, 0))
	var court := RulersDynasty.court_apts(state, eid)
	for a in APTS:
		out[a] = int(out[a]) + int(court.get(a, 0))
	return out


static func per(apt: String) -> int:
	return int(data()["aptitudes"][apt].get("per", 1))


## Effets au format des technologies (fusionnés dans Research.effects) ; la stabilité va dans
## stability_parts (ligne à part).
static func effects(state: GameState, eid: int) -> Dictionary:
	var out := {}
	var en := entry(state, eid)
	if en.is_empty():
		return out
	var a := apts(state, eid)
	if int(a["gestion"]) > 0:
		out["production_pct"] = {"all": int(a["gestion"]) * per("gestion")}
	if int(a["guerre"]) > 0:
		out["damage_pct"] = int(a["guerre"]) * per("guerre")
	if int(a["intrigue"]) > 0:
		out["spy_cost_pct"] = -int(a["intrigue"]) * per("intrigue")
	var r: Dictionary = en["r"]
	if not r.is_empty():
		_add_fx(out, arch_def(String(r["arch"])).get("fx", {}))
		if int(en.get("power_until", 0)) > state.tick:
			_add_fx(out, arch_def(String(en.get("power_arch", r["arch"]))).get("power", {}).get("fx", {}))
	elif String(en.get("vacant_kind", "")) == "reine":
		_add_fx(out, rules().get("queenless_fx", {}))
	var fun: Dictionary = en.get("fun", {})
	if not fun.is_empty() and int(fun.get("until", 0)) > state.tick:
		_add_fx(out, funeral_def(String(fun["key"]), int(fun["i"])).get("fx", {}))
	_add_fx(out, RulersDynasty.legacy_fx(state, eid))
	return out


static func _add_fx(into: Dictionary, fx: Dictionary) -> void:
	var f := fx.duplicate(true)
	f.erase("stability")
	Research._merge(into, f)


## Lignes de stabilité (toute l'empire) : légitimité, interrègne, zélote, funérailles, héritages.
static func stability_parts(state: GameState, eid: int) -> Array:
	var out := []
	var en := entry(state, eid)
	if en.is_empty():
		return out
	var r: Dictionary = en["r"]
	if r.is_empty():
		out.append(["Interrègne", -5])
	else:
		var l := legitimacy(state, eid)
		if l >= r_int("legit_high"):
			out.append(["Souverain légitime", r_int("legit_high_stab")])
		elif l <= r_int("legit_low"):
			out.append(["Souverain contesté", r_int("legit_low_stab")])
		var st := int(arch_def(String(r["arch"])).get("fx", {}).get("stability", 0))
		if st != 0:
			out.append(["Souverain " + String(arch_def(String(r["arch"]))["label"]).to_lower(), st])
		if int(en.get("power_until", 0)) > state.tick:
			var ps := int(arch_def(String(en.get("power_arch", r["arch"]))).get("power", {}).get("fx", {}).get("stability", 0))
			if ps != 0:
				out.append([String(arch_def(String(en.get("power_arch", r["arch"]))).get("power", {}).get("label", "Pouvoir")), ps])
		if not (en.get("regent", {}) as Dictionary).is_empty():
			out.append(["Régence", -2])
	var fun: Dictionary = en.get("fun", {})
	if not fun.is_empty() and int(fun.get("until", 0)) > state.tick:
		var fs := int(funeral_def(String(fun["key"]), int(fun["i"])).get("fx", {}).get("stability", 0))
		if fs != 0:
			out.append(["Funérailles : " + String(funeral_def(String(fun["key"]), int(fun["i"])).get("label", "")), fs])
	var ls := int(RulersDynasty.legacy_fx(state, eid, true).get("stability", 0))
	if ls != 0:
		out.append([RulersDynasty.legacy_label(state, eid), ls])
	if int(en.get("unrest", 0)) > state.tick:
		out.append(["Nouvelle maison contestée", -5])
	return out


## Influence de l'Éloquence (par mois, comme les Orateurs du conseil).
static func income(state: GameState, eid: int) -> Dictionary:
	if state.rulers.is_empty():
		return {}
	var n := int(apts(state, eid)["eloquence"]) * per("eloquence")
	return {"influence": n} if n > 0 else {}


## Le souverain commande-t-il cette flotte ?
static func commands(state: GameState, eid: int, fleet_id: int) -> bool:
	var r := ruler(state, eid)
	return not r.is_empty() and String(r.get("post", "")) == "fleet" and int(r.get("target", -1)) == fleet_id


## Dégâts en plus pour la flotte qu'il commande (son aptitude Guerre compte double).
static func fleet_damage_pct(state: GameState, f: Fleet) -> int:
	if state.rulers.is_empty() or not commands(state, f.owner, f.id):
		return 0
	return int(ruler(state, f.owner)["apt"].get("guerre", 0)) * per("guerre")


## Production en plus du système capital quand il le gouverne (Gestion double).
static func capital_prod_pct(state: GameState, owner: int, system_id: int) -> int:
	if state.rulers.is_empty():
		return 0
	var r := ruler(state, owner)
	if r.is_empty() or String(r.get("post", "")) != "capital" or FactionTraits.capital_system(state, owner) != system_id:
		return 0
	return int(r["apt"].get("gestion", 0)) * per("gestion")


## Chiffrement en plus (Intrigue : un point par tranche de deux).
static func encryption(state: GameState, eid: int) -> int:
	if state.rulers.is_empty():
		return 0
	@warning_ignore("integer_division")
	return int(apts(state, eid)["intrigue"]) / 2


# --- Compteurs et surnoms ----------------------------------------------------------------------

## Un acte de l'empire (voir Heroes.act) compte pour le règne.
static func note(state: GameState, eid: int, kind_: String, n := 1) -> void:
	if state.rulers.is_empty() or n <= 0:
		return
	var en := entry(state, eid)
	if en.is_empty() or (en["r"] as Dictionary).is_empty():
		return
	var acts: Dictionary = en["acts"]
	acts[kind_] = int(acts.get(kind_, 0)) + n
	if kind_ == "battles_won":
		adjust(state, eid, r_int("victory_adj") * n)


static func on_battle(state: GameState, b: Dictionary, winner: int) -> void:
	if state.rulers.is_empty() or winner < 0:
		return
	for s: Dictionary in b.get("sides", []):
		var loser := int(s["empire"])
		if loser != winner and Combat.at_war(state, winner, loser):
			adjust(state, loser, r_int("defeat_adj"))


## Valeur d'une mesure pour un surnom ou une ambition.
static func measure(state: GameState, eid: int, src: String, k: String, cache: Dictionary = {}) -> int:
	var en := entry(state, eid)
	var r: Dictionary = en.get("r", {})
	match src:
		"r":
			return int((en.get("acts", {}) as Dictionary).get(k, 0))
		"sd":
			return _state_value(state, eid, k, cache) - int((en.get("base", {}) as Dictionary).get(k, 0))
		"s":
			return _state_value(state, eid, k, cache)
		"sp":
			match k:
				"reign_years":
					return reign_years(state, r)
				"age":
					return age(state, r)
				"peace_years":
					return _peace_years(state, eid, r)
				"lost_systems":
					return int(en.get("lost", 0))
				"capital_lost":
					return int(en.get("cap_lost", 0))
				"perjury":
					return _perjury(state, eid, r)
				"weak":
					return 1 if reign_years(state, r) >= 2 and legitimacy(state, eid) <= r_int("legit_low") else 0
				"idle":
					var n := 0
					for a in en.get("acts", {}):
						n += int(en["acts"][a])
					return 1 if reign_years(state, r) >= 5 and n < 3 else 0
				"terms":
					return int(en.get("terms", 0))
				"legit":
					return legitimacy(state, eid)
	return 0


static func _state_value(state: GameState, eid: int, k: String, cache: Dictionary) -> int:
	if cache.has(k):
		return int(cache[k])
	var v := DeedsEval.value(state, eid, k)
	cache[k] = v
	return v


static func _peace_years(state: GameState, eid: int, r: Dictionary) -> int:
	var e := state.get_empire(eid)
	if e == null or not e.wars.is_empty():
		return 0
	var since := maxi(int(r.get("from", 0)), int((state.stab_meta.get("peace", {}) as Dictionary).get(eid, 0)))
	@warning_ignore("integer_division")
	return (state.tick - since) / DAYS_PER_YEAR


static func _perjury(state: GameState, eid: int, r: Dictionary) -> int:
	for m in state.memories:
		if int(m["about"]) == eid and String(m["kind"]) == "broke_treaty" and int(m["tick"]) >= int(r.get("from", 0)):
			return 1
	return 0


## Surnoms du mois : chaque surnom dont la mesure est atteinte (un de même mesure plus fort remplace
## le plus faible), au plus max_cognomens.
static func _check_cognomens(state: GameState, eid: int, added: Array[Dictionary]) -> void:
	var en := entry(state, eid)
	var r: Dictionary = en["r"]
	var cogs: Array = r["cogs"]
	var cache := {}
	for c: Dictionary in data()["cognomens"]:
		var cid := String(c["id"])
		if cogs.has(cid) or bool(c.get("posthumous", false)) or bool(c.get("accession", false)):
			continue
		if String(c["k"]) in ["front_death", "murdered", "short_reign", "usurper", "young"]:
			continue
		if c.has("cond") and not Events._layers_ok(state, eid, c["cond"]):
			continue
		if measure(state, eid, String(c["src"]), String(c["k"]), cache) < int(c["n"]):
			continue
		var weaker := ""
		for o in cogs:
			var od := cog_def(String(o))
			if String(od.get("k", "")) == String(c["k"]) and String(od.get("src", "")) == String(c["src"]) and int(od.get("n", 0)) < int(c["n"]):
				weaker = String(o)
		if weaker != "":
			cogs.erase(weaker)
		elif cogs.size() >= r_int("max_cognomens"):
			continue
		cogs.append(cid)
		Relics.touch(state)
		var e := state.get_empire(eid)
		added.append(state.add_chronicle("On l'appelle désormais %s : %s. Les graveurs de médailles se frottent les mains." % [
				cog_text(state, eid, r, cid), full_name(state, eid)], Espionage.private_to(state, [eid])))
		if e != null and not e.is_ai():
			pass


## Un surnom donné d'ailleurs (titre de haut fait, sacre…).
static func give_cognomen(state: GameState, eid: int, cid: String) -> void:
	var r := ruler(state, eid)
	if r.is_empty() or (r["cogs"] as Array).has(cid):
		return
	if (r["cogs"] as Array).size() >= r_int("max_cognomens") + 1:
		return
	(r["cogs"] as Array).append(cid)
	Relics.touch(state)


# --- Ambitions ---------------------------------------------------------------------------------

static func _amb_base(state: GameState, eid: int, a: Dictionary) -> int:
	match String(a["src"]):
		"r", "sd":
			return measure(state, eid, String(a["src"]), String(a["k"]))
	return 0


static func _amb_progress(state: GameState, eid: int, a: Dictionary, base: int) -> int:
	return measure(state, eid, String(a["src"]), String(a["k"])) - base


static func amb_progress(state: GameState, eid: int) -> Array:
	var en := entry(state, eid)
	var am: Dictionary = en.get("amb", {})
	if am.is_empty():
		return []
	var a := amb_def(String(am["id"]))
	return [maxi(0, _amb_progress(state, eid, a, int(am.get("base", 0)))), int(a.get("n", 1))]


static func choose_ambition(state: GameState, eid: int, id: String) -> void:
	var en := entry(state, eid)
	var a := amb_def(id)
	if en.is_empty() or a.is_empty() or (en["r"] as Dictionary).is_empty():
		return
	en["amb"] = {"id": id, "base": _amb_base(state, eid, a)}


static func _check_ambition(state: GameState, eid: int, added: Array[Dictionary]) -> void:
	var en := entry(state, eid)
	var am: Dictionary = en.get("amb", {})
	if am.is_empty():
		if int(en.get("amb_next", 0)) > 0 and state.tick >= int(en["amb_next"]):
			offer_ambition(state, eid, added)
		return
	var a := amb_def(String(am["id"]))
	if a.is_empty() or _amb_progress(state, eid, a, int(am.get("base", 0))) < int(a["n"]):
		return
	var r: Dictionary = en["r"]
	(en["amb_done"] as Array).append(String(am["id"]))
	en["amb"] = {}
	en["amb_next"] = state.tick + r_int("ambition_days")
	adjust(state, eid, r_int("ambition_legit"))
	give_cognomen(state, eid, "amb:" + String(am["id"]))
	added.append(state.add_chronicle("%s accomplit son ambition (%s) : légitimité +%d. On dit maintenant %s." % [
			full_name(state, eid), String(a["label"]).to_lower(), r_int("ambition_legit"), cog_text(state, eid, r, "amb:" + String(am["id"]))],
			Espionage.private_to(state, [eid])))


# --- Pouvoir de l'archétype --------------------------------------------------------------------

static func check_power(state: GameState, eid: int) -> String:
	var en := entry(state, eid)
	if en.is_empty():
		return "pas de souverain dans cette partie"
	if (en["r"] as Dictionary).is_empty():
		return "le trône est vacant"
	if not (en.get("regent", {}) as Dictionary).is_empty():
		return "un régent ne peut pas user du pouvoir du souverain"
	if state.tick < int(en["power_cd"]):
		return "pouvoir en recharge encore %d jours" % (int(en["power_cd"]) - state.tick)
	return ""


static func use_power(state: GameState, eid: int, added: Array[Dictionary]) -> void:
	var en := entry(state, eid)
	var r: Dictionary = en["r"]
	var p: Dictionary = arch_def(String(r["arch"])).get("power", {})
	en["power_cd"] = state.tick + r_int("power_cooldown_days")
	en["power_arch"] = String(r["arch"])
	en["power_until"] = state.tick + int(p.get("days", 0))
	var e := state.get_empire(eid)
	var extra := ""
	if int(p.get("research_pct", 0)) > 0:
		extra = " " + Events.give_research(state, eid, int(p["research_pct"])) + "."
	if int(p.get("fervor", 0)) > 0 and FactionTraits.has_fervor(e.faction()):
		e.fervor = mini(int(e.faction()["fervor"]["max"]), e.fervor + int(p["fervor"]))
	Relics.touch(state)
	added.append(state.add_chronicle("%s use de son pouvoir : %s.%s" % [full_name(state, eid), String(p.get("label", "")), extra],
			Espionage.private_to(state, [eid])))


# --- Postes ------------------------------------------------------------------------------------

static func check_post(state: GameState, eid: int, post: String, target: int) -> String:
	var en := entry(state, eid)
	if en.is_empty() or (en["r"] as Dictionary).is_empty():
		return "pas de souverain"
	if not (en.get("regent", {}) as Dictionary).is_empty():
		return "un souverain mineur reste au palais"
	if is_wounded(state, eid):
		return "le souverain se remet de ses blessures"
	match post:
		"":
			return ""
		"capital":
			return "" if FactionTraits.capital_system(state, eid) >= 0 else "pas de capitale"
		"fleet":
			if (data()["no_front_kinds"] as Array).has(kind(state, eid)):
				return "%s ne quitte jamais la ruche" % title(state, eid, en["r"])
			var f: Fleet = state.fleets.get(target)
			if f == null or f.owner != eid:
				return "flotte inconnue"
			if not Combat.is_armed(f):
				return "il faut une flotte armée"
			return ""
	return "poste inconnu"


static func set_post(state: GameState, eid: int, post: String, target: int) -> void:
	var r := ruler(state, eid)
	r["post"] = post
	r["target"] = target if post == "fleet" else -1


## Pertes d'une flotte qu'il commande (voir HeroFall.on_losses) : coup du lendemain.
static func on_fleet_losses(state: GameState, f: Fleet, destroyed: bool, flagship: bool, surv: bool) -> void:
	if not commands(state, f.owner, f.id):
		return
	var en := entry(state, f.owner)
	en["front_hit"] = "fleet" if destroyed else ("flagship" if flagship else String(en.get("front_hit", "")))
	en["front_surv"] = 1 if surv else 0


## Le souverain au front : mort possible (et succession), sinon blessure.
static func _front(state: GameState, eid: int, en: Dictionary, added: Array[Dictionary]) -> void:
	var r: Dictionary = en["r"]
	var hit := String(en.get("front_hit", ""))
	if String(r.get("post", "")) == "fleet":
		var f: Fleet = state.fleets.get(int(r["target"]))
		if f == null or f.owner != eid:
			hit = "fleet"
	if hit == "":
		return
	en.erase("front_hit")
	var surv := int(en.get("front_surv", 0)) > 0
	en.erase("front_surv")
	var base := r_int("front_death_pct") * 100 if hit == "fleet" else int(HeroFall.cfg().get("flagship", 3)) * 100
	var mp := HeroFall.mode_pct(state) if not state.hero_death.is_empty() else 100
	@warning_ignore("integer_division")
	base = base * mp / 100
	if surv:
		base -= int(HeroFall.cfg().get("capsule_minus", 3)) * 100
	var dies := mortal(state) and not immortal_kind(state, eid) and base > 0 and _h(state, ["front", eid, state.tick]) % 10000 < base
	if dies:
		die(state, eid, "tombé au combat à la tête de sa flotte", added, "front")
		return
	if hit == "fleet":
		r["post"] = ""
		r["target"] = -1
		en["wound"] = state.tick + r_int("front_wound_days")
		added.append(state.add_chronicle("%s survit à la perte de sa flotte, blessé ; il lui faudra %d jours pour reprendre les armes." % [
				full_name(state, eid), r_int("front_wound_days")], Espionage.private_to(state, [eid])))


# --- Jour par jour -----------------------------------------------------------------------------

static func daily(state: GameState) -> Array[Dictionary]:
	var added: Array[Dictionary] = []
	if state.rulers.is_empty():
		return added
	var monthly := posmod(state.tick, r_int("check_days")) == r_int("offset")
	var keys := (state.rulers["e"] as Dictionary).keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return int(a) < int(b))
	for k in keys:
		var eid := int(k)
		var e := state.get_empire(eid)
		if e == null or e.eliminated:
			continue
		var en: Dictionary = state.rulers["e"][k]
		if int(en.get("power_until", 0)) > 0 and state.tick == int(en["power_until"]):
			Relics.touch(state)
		var fun: Dictionary = en.get("fun", {})
		if not fun.is_empty() and state.tick == int(fun.get("until", 0)):
			Relics.touch(state)
		if not (en["r"] as Dictionary).is_empty():
			_front(state, eid, en, added)
		_capital(state, eid, en, added)
		if monthly:
			_month(state, eid, en, added)
	if monthly:
		RulersDynasty.monthly_all(state, added)
	return added


## Capitale perdue : légitimité, Reine-mère qui meurt, itération forcée.
static func _capital(state: GameState, eid: int, en: Dictionary, added: Array[Dictionary]) -> void:
	var cap := int(en.get("cap", -1))
	var e := state.get_empire(eid)
	if cap < 0:
		en["cap"] = e.capital_planet
		return
	var c: Colony = state.colonies.get(cap)
	var lost := c == null or c.owner != eid
	if not lost:
		return
	en["cap"] = e.capital_planet
	var taker := c.owner if c != null else -1
	if taker < 0 or taker == eid or GameState.is_npc(taker) and taker != GameState.NPC_ID:
		pass
	if (en["r"] as Dictionary).is_empty():
		return
	en["cap_lost"] = 1
	adjust(state, eid, r_int("capital_lost_adj"))
	match kind(state, eid):
		"reine":
			if mortal(state):
				die(state, eid, "périt quand la capitale tombe", added, "capital")
		"iteration":
			adjust(state, eid, r_int("iteration_capital_adj"))
			en["iter_next"] = state.tick


static func _month(state: GameState, eid: int, en: Dictionary, added: Array[Dictionary]) -> void:
	if int(en.get("vacant", 0)) > 0 and state.tick >= int(en["vacant"]):
		RulersSuccession.resolve(state, eid, added)
	var r: Dictionary = en["r"]
	if r.is_empty():
		return
	# Systèmes perdus sous le règne.
	var sys_n := DeedsEval.value(state, eid, "systems")
	if int(en.get("sys_n", -1)) >= 0 and sys_n < int(en["sys_n"]):
		var lost := int(en["sys_n"]) - sys_n
		en["lost"] = int(en.get("lost", 0)) + lost
		adjust(state, eid, r_int("system_lost_adj") * mini(lost, 5))
	en["sys_n"] = sys_n
	if _age_month(state, eid, en, r, added):
		return
	_check_cognomens(state, eid, added)
	_check_ambition(state, eid, added)
	RulersBridges.monthly(state, eid)
	RulersSuccession.monthly(state, eid, added)


## Vieillesse : au-delà de l'espérance de vie moins dix ans, risque mensuel croissant ; sans limite
## (synthétiques), un accident rare (5 % tous les dix ans).
static func _age_month(state: GameState, eid: int, en: Dictionary, r: Dictionary, added: Array[Dictionary]) -> bool:
	if not mortal(state) or immortal_kind(state, eid):
		return false
	var life := int(r.get("life", 0))
	var a := age(state, r)
	if life <= 0:
		if _h(state, ["accident", eid, state.tick]) % 10000 < r_int("accident_per_10000_month"):
			die(state, eid, "victime d'un accident que personne n'avait prévu, pas même les calculs", added, "accident")
			return true
		return false
	var from := life - int(Heroes.data()["life"]["warn"])
	if a < from:
		return false
	var per_mille := (a - from + 1) * int(Heroes.data()["life"]["per_year_pct"]) * 10 / 12
	per_mille = per_mille * (100 - Court.medic_pct(state, eid)) / 100  # Médecin de la cour
	if _h(state, ["mort", eid, state.tick]) % 1000 >= per_mille:
		return false
	die(state, eid, "s'éteint à %d ans" % a, added, "age")
	return true


# --- Mort et funérailles -----------------------------------------------------------------------

## Le souverain meurt (ou quitte le trône : how = deposed, abdicate). Surnoms posthumes, règne
## inscrit, funérailles au choix, succession.
static func die(state: GameState, eid: int, why: String, added: Array[Dictionary], how := "age", killer := -1, successor: Dictionary = {}) -> void:
	var en := entry(state, eid)
	var r: Dictionary = en.get("r", {})
	if r.is_empty():
		return
	var leaves := how == "deposed" or how == "abdicate" or how == "term" or how == "seized"
	var cogs: Array = r["cogs"]
	if not leaves:
		if how == "front" and not cogs.has("brave"):
			cogs.append("brave")
		if how == "murdered" and not cogs.has("assassine"):
			cogs.append("assassine")
		if reign_years(state, r) < 3 and not cogs.has("bref") and cogs.is_empty():
			cogs.append("bref")
	var legit := legitimacy(state, eid)
	var dead_name := full_name(state, eid, r)
	(en["reigns"] as Array).append({"name": name_of(state, eid, r), "first": String(r["name"]), "g": String(r["g"]), "cogs": cogs.duplicate(),
			"arch": String(r["arch"]), "from": int(r["from"]), "to": state.tick, "end": how, "house": String(r.get("house", "")),
			"legit": legit, "portrait": String(r["portrait"]), "ord": int(r.get("ord", 1)), "title": title(state, eid, r),
			"born": int(r["born"]), "killer": killer})
	RulersDynasty.on_reign_end(state, eid, r, legit, how)
	en["r"] = {}
	en["power_until"] = 0
	en["amb"] = {}
	en["regent"] = {}
	Relics.touch(state)
	RulersBridges.on_ruler_death(state, eid, r, how, killer, added)
	if not leaves:
		_halve_memories(state, eid)
	var e := state.get_empire(eid)
	Announce.next(state, "ruler_death", {"target": eid, "name": dead_name, "portrait": String(r.get("portrait", "")), "born": int(r.get("born", 0)), "from": int(r.get("from", 0)), "why": why})
	added.append(state.add_chronicle("%s %s." % [dead_name, why], Espionage.public_to(state, [eid])))
	# Succession (peut couronner tout de suite ou ouvrir un interrègne).
	if not successor.is_empty():
		crown(state, eid, successor, added)
	else:
		RulersSuccession.on_vacancy(state, eid, how, added)
	if leaves:
		return
	# Funérailles : 2 ou 3 cérémonies selon le credo.
	var ev := state.next_event_id
	Events.push(state, eid, "ruler_death", {}, added)
	var nr := ruler(state, eid)
	var next_text := "Le trône reste vacant pour l'instant." if nr.is_empty() else "%s lui succède." % full_name(state, eid, nr)
	_note(state, eid, ev, {"dead_title": "%s est mort" % dead_name if _form(state, eid, r) != "f" else "%s est morte" % dead_name,
			"dead_text": "%s %s, après %d ans de règne." % [dead_name, why, reign_years(state, r)], "next_text": next_text,
			"fun": funeral_offer(state, eid)})
	if e != null:
		pass


## Les souvenirs diplomatiques de l'empire sont divisés par deux (prop. 22) : le nouveau souverain a
## ses propres rancunes.
static func _halve_memories(state: GameState, eid: int) -> void:
	for m in state.memories:
		if int(m["about"]) != eid and int(m["who"]) != eid:
			continue
		var md: Dictionary = Diplomacy.data()["memories"].get(String(m["kind"]), {})
		var d := maxi(1, int(md.get("days", 360)))
		var age_ := state.tick - int(m["tick"])
		if age_ >= d:
			continue
		@warning_ignore("integer_division")
		var new_age := d - (d - age_) / 2
		m["tick"] = state.tick - new_age


static func funeral_offer(state: GameState, eid: int) -> Array:
	var f: Dictionary = data()["funerals"]
	var out: Array = []
	var gest := ["ruche", "conscience"].has(government(state, eid))
	var credo := String(state.get_empire(eid).faction().get("species", {}).get("credo", ""))
	if gest:
		for i in (f["_gestalt"] as Array).size():
			out.append(["_gestalt", i])
	for i in (f.get(credo, []) as Array).size():
		out.append([credo, i])
	for i in (f["_any"] as Array).size():
		if out.size() < 3:
			out.append(["_any", i])
	return out.slice(0, 3)


static func funeral_def(key: String, i: int) -> Dictionary:
	var l: Array = (data()["funerals"] as Dictionary).get(key, [])
	return l[i] if i >= 0 and i < l.size() else {}


# --- Cartes (voir Events) ----------------------------------------------------------------------

static func fill(state: GameState, eid: int, item: Dictionary, s: String) -> String:
	if not s.contains("{ruler_"):
		return s
	var n := note_of(state, eid, item)
	var r := ruler(state, eid)
	var out := s
	for k in ["dead_title", "dead_text", "next_text", "star_text", "star_cost", "marriage_text", "regency_text", "regent"]:
		out = out.replace("{ruler_%s}" % k, String(n.get(k, "")))
	out = out.replace("{ruler_name}", full_name(state, eid))
	out = out.replace("{ruler_title_name}", "Avènement : " + full_name(state, eid) if not r.is_empty() else "Le trône")
	var acc := ""
	if not r.is_empty():
		var al := String(arch_def(String(r["arch"])).get("label", ""))
		acc = "%s monte sur le trône à %d ans. Archétype de règne : %s (%s). Légitimité : %d." % [full_name(state, eid), age(state, r), al.to_lower(),
				String(arch_def(String(r["arch"])).get("text", "")).trim_suffix("."), legitimacy(state, eid)]
		if int(n.get("accession", 1)) == 0:
			acc = "%s a mené son ambition à bien. Le règne continue." % full_name(state, eid)
	out = out.replace("{ruler_accession_text}", acc)
	var ambs: Array = n.get("amb", [])
	for i in 3:
		var a := amb_def(String(ambs[i])) if i < ambs.size() else {}
		out = out.replace("{ruler_amb_%d}" % i, "%s (%s)" % [String(a.get("label", "?")), String(a.get("text", "")).trim_suffix(".")] if not a.is_empty() else "?")
	var archs: Array = n.get("arch", [])
	for i in 3:
		var ad := arch_def(String(archs[i])) if i < archs.size() else {}
		out = out.replace("{ruler_arch_%d}" % i, "%s : %s" % [String(ad.get("label", "?")), String(ad.get("power", {}).get("text", ""))] if not ad.is_empty() else "?")
	var funs: Array = n.get("fun", [])
	for i in 3:
		var fd := funeral_def(String(funs[i][0]), int(funs[i][1])) if i < funs.size() else {}
		out = out.replace("{ruler_fun_%d}" % i, String(fd.get("label", "?")))
	return out


## Lignes lisibles d'un effet « ruler » (Events.fx_lines).
static func fx_lines(state: GameState, eid: int, item: Dictionary, fx: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var n := note_of(state, eid, item)
	var i := int(fx.get("i", 0))
	match String(fx.get("act", "")):
		"ambition":
			var ambs: Array = n.get("amb", [])
			if i < ambs.size():
				out.append("Réussie : légitimité +%d et le surnom « %s »" % [r_int("ambition_legit"),
						String(amb_def(String(ambs[i])).get("cog", {}).get(_form(state, eid, ruler(state, eid)), ""))])
		"funeral":
			var funs: Array = n.get("fun", [])
			if i < funs.size():
				var fd := funeral_def(String(funs[i][0]), int(funs[i][1]))
				var t := Relics.fx_text(fd.get("fx", {}))
				@warning_ignore("integer_division")
				out.append("%s pendant %d ans" % [t.capitalize() if t != "" else "Rien", r_int("funeral_days") / DAYS_PER_YEAR])
				if fd.has("cost"):
					out.append("Coût : %s" % GameData.format_amounts(fd["cost"]))
				if fd.has("gain"):
					out.append(GameData.format_amounts(fd["gain"], true))
		"iterate":
			var archs: Array = n.get("arch", [])
			if i < archs.size():
				out.append("Nouvel archétype : %s" % String(arch_def(String(archs[i])).get("label", "")))
		"star_buy":
			out.append("Coût : %s" % GameData.format_amounts(rules()["star_buy"]))
		"star_away":
			out.append("Les autres héros perdent %d de loyauté" % -r_int("star_set_aside_loyalty"))
		"star_crown":
			out.append("Le souverain abdique, l'étoile montante est couronnée")
		"marry_yes":
			out.append("Opinion +%d, revendication réciproque sur le trône" % r_int("marriage_opinion"))
	return out


## Ce qui empêche un choix « ruler » ("" si possible).
static func fx_problem(state: GameState, eid: int, item: Dictionary, fx: Dictionary) -> String:
	var e := state.get_empire(eid)
	var n := note_of(state, eid, item)
	match String(fx.get("act", "")):
		"funeral":
			var funs: Array = n.get("fun", [])
			var i := int(fx.get("i", 0))
			if i >= funs.size():
				return "cérémonie indisponible"
			var fd := funeral_def(String(funs[i][0]), int(funs[i][1]))
			if fd.has("cost") and not Economy.can_afford(e, fd["cost"]):
				return "pas assez de ressources"
		"star_buy":
			if not Economy.can_afford(e, rules()["star_buy"]):
				return "pas assez d'influence"
		"ambition", "iterate":
			if ruler(state, eid).is_empty():
				return "le trône est vacant"
	return ""


static func apply_fx(state: GameState, eid: int, item: Dictionary, fx: Dictionary, added: Array[Dictionary]) -> void:
	var en := entry(state, eid)
	if en.is_empty():
		return
	var n := note_of(state, eid, item)
	var i := int(fx.get("i", 0))
	var e := state.get_empire(eid)
	match String(fx.get("act", "")):
		"ambition":
			var ambs: Array = n.get("amb", [])
			if i < ambs.size():
				choose_ambition(state, eid, String(ambs[i]))
		"funeral":
			var funs: Array = n.get("fun", [])
			if i < funs.size():
				var fd := funeral_def(String(funs[i][0]), int(funs[i][1]))
				if fd.has("cost"):
					Economy.pay(e, fd["cost"])
				for res in fd.get("gain", {}):
					e.resources[res] = int(e.resources.get(res, 0)) + int(fd["gain"][res])
				en["fun"] = {"key": String(funs[i][0]), "i": int(funs[i][1]), "until": state.tick + r_int("funeral_days")}
				RulersBridges.on_funeral(state, eid)
				Relics.touch(state)
		"iterate":
			var archs: Array = n.get("arch", [])
			var r: Dictionary = en["r"]
			if i < archs.size() and not r.is_empty():
				r["arch"] = String(archs[i])
				en["power_cd"] = state.tick
				Relics.touch(state)
				added.append(state.add_chronicle("%s s'est réécrit : il sera %s pour les vingt prochaines années." % [full_name(state, eid),
						String(arch_def(String(archs[i]))["label"]).to_lower()], Espionage.private_to(state, [eid])))
		_:
			RulersDynasty.apply_fx(state, eid, item, fx, n, added)


## Valeur d'un choix « ruler » pour l'IA (voir AiEvents).
static func ai_value(state: GameState, eid: int, item: Dictionary, fx: Dictionary) -> int:
	var n := note_of(state, eid, item)
	var i := int(fx.get("i", 0))
	match String(fx.get("act", "")):
		"ambition":
			var ambs: Array = n.get("amb", [])
			if i < ambs.size():
				var a := amb_def(String(ambs[i]))
				# Plus elle est proche, mieux c'est ; l'archétype aime les siennes.
				var v := 100 - mini(100, int(a.get("n", 1)) * 10)
				if (a.get("arch", []) as Array).has(String(ruler(state, eid).get("arch", ""))):
					v += 40
				return v
		"funeral":
			var funs: Array = n.get("fun", [])
			if i < funs.size():
				var fd := funeral_def(String(funs[i][0]), int(funs[i][1]))
				var v2 := 50
				for k in fd.get("cost", {}):
					v2 -= int(fd["cost"][k]) / 4
				return v2 + (30 if fd.has("gain") else 0) + (20 if not fd.has("cost") else 0)
		"iterate":
			return 50 + _h(state, ["ai_it", eid, i]) % 20
		"star_crown":
			return -50
		"star_buy":
			return 20
		"star_away":
			return 10
		"marry_yes":
			return 60
		"marry_no":
			return 0
		"regent_yes":
			return 30
		"regent_council":
			return 20
	return 0


# --- Ordres ------------------------------------------------------------------------------------

## act : power | post | law | educate | legacy | marry | abdicate.
static func check_act(state: GameState, eid: int, act: String, x: int, s: String) -> String:
	if state.rulers.is_empty() or entry(state, eid).is_empty():
		return "pas de souverain dans cette partie"
	match act:
		"power":
			return check_power(state, eid)
		"post":
			return check_post(state, eid, s, x)
	return RulersDynasty.check_act(state, eid, act, x, s)


static func act(state: GameState, eid: int, act_: String, x: int, s: String, added: Array[Dictionary]) -> void:
	match act_:
		"power":
			use_power(state, eid, added)
		"post":
			set_post(state, eid, s, x)
		_:
			RulersDynasty.act(state, eid, act_, x, s, added)


# --- Résumés -----------------------------------------------------------------------------------

## Fiche pour l'écran Trône et la barre d'empire.
static func summary(state: GameState, eid: int) -> Dictionary:
	var en := entry(state, eid)
	if en.is_empty():
		return {}
	var r: Dictionary = en["r"]
	var out := {"vacant": r.is_empty(), "title": "", "name": "Trône vacant", "kind": kind(state, eid),
			"kind_label": String(succession(state, eid).get("label", "")), "kind_text": String(succession(state, eid).get("text", ""))}
	if r.is_empty():
		out["until"] = int(en.get("vacant", 0))
		return out
	out["title"] = title(state, eid, r)
	out["name"] = full_name(state, eid, r)
	out["portrait"] = String(r["portrait"])
	out["age"] = age(state, r)
	out["reign"] = reign_years(state, r)
	out["legit"] = legitimacy(state, eid)
	out["arch"] = String(r["arch"])
	out["apt"] = r["apt"]
	return out
