class_name Archaeology
extends RefCounted
## Archéologie et fouilles, « les Strates » (étude du 2026-11-17, 44 propositions ; données :
## data/archaeology.json). Le pilier prolonge les fouilles de Relics (prop. 1) au lieu de les remplacer :
## Relics garde le moteur (phases, jets, indices, relique), Archaeology ajoute ce qui l'entoure.
##
## Réglage « Archéologie » (prop. 4) : Complète (state.archaeo rempli), Classique (state.archaeo vide,
## les fouilles d'avant), Désactivée (aucun site). Sans l'option (tests, bancs) : Classique.
##
## Champs ajoutés aux sites (state.digs[système], mode Complète) : "at" type de site (prop. 7), "sr" strate
## 0 Première / 1 Moyenne / 2 Récente (prop. 3), "or" origine ("d:<Disparu>", "g" sans nom, "a:<ancienne>",
## "e:<id>:<nom>" empire de la partie, "c:<crise>", "b" bataille, "l" Lointains, "m" ruine de mégastructure),
## "nm" nom, "seal" site scellé (prop. 17), "only" empire seul à le voir (-1 tous), "me" méthode (prop. 14),
## "stu" études choisies (prop. 15), "pend" 1 quand la fin attend le choix Extraire / Classer (prop. 21),
## "hist" 1 pour un site né de l'histoire de la partie (prop. 9), "rw" 1 sur un monde-relique (prop. 10).
##
## État global : state.archaeo = {"mode", "disp": Disparus tirés, "next": prochain identifiant d'antiquité,
##  "aq": {"id": antiquité}, "tr": vestiges {"eid": {"d": n}}, "cr": Mondes-berceaux, "sec": Secrets,
##  "anc": technologies anciennes, "gab": gabarits, "warn": Avertissements, "reco": Reconstitutions,
##  "hl": Hauts lieux, "dep": gisements, "cd": délais des actions, "fx": effets temporaires, "hist": file
##  des sites à naître, "rw": mondes-reliques, "permits": permis de fouille, "heirs": héritiers, "aster":
##  prêts de la Bibliothèque, "plans": Plans de mégastructure, "insitu": reliques laissées en place,
##  "st": statistiques, "col": le Collectionneur, "rivals": fouilles concurrentes}.
## Tout est déterministe : entiers, tirages par hachage de la graine, ordres par SimCommands.

const SUBS := ["aq", "tr", "cr", "sec", "anc", "gab", "warn", "reco", "hl", "dep", "cd", "fx", "rw", "permits", "heirs", "aster",
		"plans", "insitu", "st", "col", "rivals", "fakes", "nat"]
const STRATA := [0, 1, 2]


static func data() -> Dictionary:
	return GameData.archaeology()


static func cfg(section: String) -> Dictionary:
	var v: Variant = data().get(section, {})
	return v if v is Dictionary else {}


static func r_int(key: String, def := 0) -> int:
	var v: Variant = cfg("rules").get(key, def)
	return int(v) if (v is int or v is float) else def


static func rule(key: String) -> Variant:
	return cfg("rules").get(key, null)


static func mode_defs() -> Array:
	return data().get("modes", [])


static func default_mode() -> String:
	return String(data().get("default_mode", "complete"))


static func enabled(state: GameState) -> bool:
	return state != null and not state.archaeo.is_empty()


## Mode Complète (les autres modes laissent state.archaeo vide).
static func full(state: GameState) -> bool:
	return enabled(state)


static func applies(state: GameState, eid: int) -> bool:
	var e := state.get_empire(eid) if enabled(state) and eid >= 0 else null
	return e != null and not e.is_npc() and not e.eliminated


static func _h(state: GameState, parts: Array) -> int:
	return absi(hash([state.seed_value, "archeo"] + parts))


static func sub(state: GameState, k: String) -> Dictionary:
	if state.archaeo.is_empty():
		return {}  # pilier désactivé : ne jamais le rallumer en écrivant
	if not state.archaeo.has(k) or not (state.archaeo[k] is Dictionary):
		state.archaeo[k] = {}
	return state.archaeo[k]


static func emp(state: GameState, k: String, eid: int) -> Dictionary:
	var s := sub(state, k)
	if s.is_empty() and state.archaeo.is_empty():
		return {}
	if not s.has(str(eid)):
		s[str(eid)] = {}
	return s[str(eid)]


static func touch(state: GameState) -> void:
	state.relic_rev += 1  # les effets (Research.effects) se recalculent


static func _stat(state: GameState, eid: int, k: String, n := 1) -> void:
	if not enabled(state) or eid < 0:
		return
	var d := emp(state, "st", eid)
	d[k] = int(d.get(k, 0)) + n


static func stat(state: GameState, eid: int, k: String) -> int:
	return int((sub(state, "st").get(str(eid), {}) as Dictionary).get(k, 0))


## Niveau des technologies d'archéologie (0 à 3 : Archéologie stellaire, Déchiffrement, Paléo-ingénierie).
static func lvl(state: GameState, eid: int) -> int:
	return Research.fx_int(state, eid, "archaeo_lvl")


# --- Talents (prop. 40) ------------------------------------------------------------------------

static func talent(state: GameState, eid: int) -> Dictionary:
	var e := state.get_empire(eid)
	if e == null or GameState.is_npc(eid):
		return {}
	var v: Variant = cfg("talents").get(Genetics.root(e.faction_id), null)
	return v if v is Dictionary else {}


static func t_int(state: GameState, eid: int, key: String) -> int:
	var v: Variant = talent(state, eid).get(key, 0)
	return int(v) if (v is int or v is float) else 0


static func t_bool(state: GameState, eid: int, key: String) -> bool:
	return bool(talent(state, eid).get(key, false))


# --- Réglage, sauvegarde -----------------------------------------------------------------------

## Après Relics.setup et les autres piliers (anciennes, mineurs, mégastructures, Contact).
static func setup(state: GameState, mode_id: String) -> void:
	state.archaeo = {}
	if mode_id == "desactivee":
		state.digs.clear()
		return
	if mode_id != "complete":
		return  # Classique : les fouilles d'avant
	state.archaeo = {"mode": "complete", "next": 1, "disp": [], "hist": [], "hist_last": -99999}
	for k in SUBS:
		state.archaeo[k] = {}
	ArchaeoWorld.pick_disparus(state)
	var keys := state.digs.keys()
	keys.sort()
	for k in keys:
		enrich_site(state, int(k), {})
	ArchaeoWorld.place_relic_worlds(state)
	ArchaeoWorld.place_cradles(state)
	ArchaeoWorld.pick_heirs(state)


static func worth_saving(state: GameState) -> bool:
	return enabled(state)


static func to_dict(state: GameState) -> Dictionary:
	return state.archaeo.duplicate(true)


static func from_dict(state: GameState, d: Dictionary) -> void:
	if d.is_empty():
		state.archaeo = {}
		return
	state.archaeo = GameData._to_ints(d.duplicate(true))
	for k in SUBS:
		if not state.archaeo.has(k) or not (state.archaeo[k] is Dictionary):
			state.archaeo[k] = {}
	for k in ["disp", "hist"]:
		if not state.archaeo.has(k) or not (state.archaeo[k] is Array):
			state.archaeo[k] = []


# --- Sites (prop. 3, 7, 8) ----------------------------------------------------------------------

static func types() -> Dictionary:
	return cfg("site_types")


static func type_ids() -> Array[String]:
	var out: Array[String] = []
	for k in types():
		out.append(String(k))
	return out


static func type_def(t: String) -> Dictionary:
	var v: Variant = types().get(t, {})
	return v if v is Dictionary else {}


static func type_label(t: String) -> String:
	return String(type_def(t).get("label", t))


static func strata_def(sr: int) -> Dictionary:
	var a: Array = data().get("strata", [])
	return a[clampi(sr, 0, a.size() - 1)] if not a.is_empty() else {}


static func strata_label(sr: int) -> String:
	return String(strata_def(sr).get("label", ""))


static func disparus() -> Dictionary:
	return cfg("disparus")


static func disparu_def(d: String) -> Dictionary:
	var v: Variant = disparus().get(d, {})
	return v if v is Dictionary else {}


static func in_game_disparus(state: GameState) -> Array[String]:
	var out: Array[String] = []
	for d in state.archaeo.get("disp", []):
		out.append(String(d))
	return out


static func disparu_of(o: String) -> String:
	return o.substr(2) if o.begins_with("d:") else ""


## Libellé d'une origine (« les Tisserands de Hel », « un peuple sans nom »…).
static func origin_label(state: GameState, o: String) -> String:
	if o.begins_with("d:"):
		return String(disparu_def(o.substr(2)).get("label", o))
	if o.begins_with("a:"):
		var kd := Ancients.kind_def(o.substr(2))
		return String(kd.get("name", kd.get("label", "une puissance ancienne")))
	if o.begins_with("e:"):
		var parts := o.split(":", false, 2)
		if parts.size() >= 3:
			return String(parts[2])
		var e := state.get_empire(int(parts[1])) if parts.size() >= 2 else null
		return e.display_name() if e != null else "un empire disparu"
	if o.begins_with("c:"):
		return Crisis.name_of(o.substr(2))
	match o:
		"b":
			return "les morts d'une grande bataille"
		"l":
			return "ceux qui appellent d'au-delà"
		"m":
			return "les bâtisseurs d'une mégastructure"
	return String(cfg("generic_origin").get("label", "un peuple sans nom"))


## Empire de la partie à l'origine d'un site (-1 sinon).
static func origin_empire(o: String) -> int:
	if not o.begins_with("e:"):
		return -1
	var parts := o.split(":", false, 2)
	return int(parts[1]) if parts.size() >= 2 else -1


static func _pick_weighted(state: GameState, salt: Array, pool: Dictionary) -> String:
	var total := 0
	var keys := pool.keys()
	keys.sort()
	for k in keys:
		total += maxi(0, int(pool[k]))
	if total <= 0:
		return String(keys[0]) if not keys.is_empty() else ""
	var r := _h(state, salt) % total
	for k in keys:
		r -= maxi(0, int(pool[k]))
		if r < 0:
			return String(k)
	return String(keys[keys.size() - 1])


## Complète un site de fouille (type, strate, origine, scellé, nom). opts peut forcer "at", "sr", "or",
## "only", "hist", "rw", "seal".
static func enrich_site(state: GameState, sid: int, opts: Dictionary) -> void:
	if not state.digs.has(sid) or not enabled(state):
		return
	var d: Dictionary = state.digs[sid]
	var o := String(opts.get("or", ""))
	if o == "":
		var ow: Dictionary = cfg("origin_weights")
		var pool := {"disparu": int(ow.get("disparu", 55)), "generic": int(ow.get("generic", 30))}
		if Ancients.enabled(state) and not Ancients.ids(state).is_empty():
			pool["ancient"] = int(ow.get("ancient", 15))
		if not state.megas.is_empty():
			for m in Megastructures.in_system(state, sid):
				if Megastructures.is_ruin(m):
					pool = {"ruin": 1}
		var pick := _pick_weighted(state, ["origin", sid], pool)
		var disp := in_game_disparus(state)
		match pick:
			"disparu":
				o = "d:" + disp[_h(state, ["disp", sid]) % disp.size()] if not disp.is_empty() else "g"
			"ancient":
				var ids := Ancients.ids(state)
				o = "a:" + Ancients.kind_of(state, ids[_h(state, ["anc", sid]) % ids.size()])
			"ruin":
				o = "d:tisserands" if disp.has("tisserands") else "m"
			_:
				o = "g"
	var t := String(opts.get("at", ""))
	if t == "":
		var dn := disparu_of(o)
		var pref: Array = disparu_def(dn).get("types", []) if dn != "" else []
		if not pref.is_empty() and _h(state, ["pref", sid]) % 100 < 60:
			t = String(pref[_h(state, ["preft", sid]) % pref.size()])
		else:
			var pool2 := {}
			for k in type_ids():
				pool2[k] = int(type_def(k).get("weight", 10))
			t = _pick_weighted(state, ["type", sid], pool2)
	var sr := int(opts.get("sr", -1))
	if sr < 0:
		var pool3 := {}
		var sa: Array = data().get("strata", [])
		for i in sa.size():
			pool3[str(i)] = int((sa[i] as Dictionary).get("weight", 10))
		sr = int(_pick_weighted(state, ["strata", sid], pool3))
	d["at"] = t
	d["sr"] = sr
	d["or"] = o
	d["seal"] = int(opts.get("seal", 1 if _h(state, ["seal", sid]) % maxi(1, r_int("seal_one_in", 8)) == 0 else 0))
	d["only"] = int(opts.get("only", -1))
	d["stu"] = 0
	d["me"] = ""
	if opts.has("hist"):
		d["hist"] = 1
	if opts.has("rw"):
		d["rw"] = 1
	d["diff"] = int(d.get("diff", 1)) + int(strata_def(sr).get("diff", 0))
	var names: Array = type_def(t).get("names", [])
	var base := String(names[_h(state, ["nm", sid]) % names.size()]) if not names.is_empty() else "Site oublié"
	if o != "g" and _h(state, ["nmo", sid]) % 2 == 0:
		base = "%s %s" % [type_label(t), _de(origin_short(state, o))]
	d["nm"] = base


static func origin_short(state: GameState, o: String) -> String:
	if o.begins_with("d:"):
		return String(disparu_def(o.substr(2)).get("short", o))
	if o == "g":
		return String(cfg("generic_origin").get("short", "Sans-Nom"))
	return origin_label(state, o)


static func _de(name: String) -> String:
	var low := name.to_lower()
	if low.begins_with("les "):
		return "des " + name.substr(4)
	if low.begins_with("le "):
		return "du " + name.substr(3)
	if low.begins_with("la ") or low.begins_with("l'"):
		return "de " + name
	if "aeiouyéèêàâîôûh".contains(low.substr(0, 1)):
		return "d'" + name
	return "des " + name if not name.begins_with("un ") else "d'" + name


## Crée un site (sans relique s'il n'en reste pas) dans ce système, puis le complète. Remplace un site
## déjà terminé. Renvoie false si un site y est encore ouvert ou si le système n'a pas de planète.
static func create_site(state: GameState, sid: int, opts: Dictionary) -> bool:
	if not enabled(state) or sid < 0 or sid >= state.galaxy.systems.size():
		return false
	if state.galaxy.systems[sid].planet_ids.is_empty():
		return false
	if state.digs.has(sid):
		if Relics.is_open(state, sid):
			return false
		state.digs.erase(sid)
	var with_relic := bool(opts.get("relic", true)) and not state.relics.is_empty()
	if not (with_relic and Relics.create_site(state, sid)):
		var dg: Dictionary = Relics.data()["digs"]
		var ch: Array = dg["chapters"]
		var bd: Array = dg["base_diff"]
		state.digs[sid] = {"relic": "", "name": 0, "chapters": int(ch[0]) + _h(state, ["chap", sid, state.tick]) % (int(ch[1]) - int(ch[0]) + 1),
				"ch": 0, "clues": 0, "diff": int(bd[0]) + _h(state, ["diff", sid, state.tick]) % (int(bd[1]) - int(bd[0]) + 1),
				"by": -1, "next": -1, "done": -1, "pillage": -999}
	enrich_site(state, sid, opts)
	return true


## L'empire voit-il ce site (en plus d'avoir exploré le système) ? Strate Première : détection 3
## (prop. 8) ; sites de piste réservés (prop. 27).
static func can_see(state: GameState, eid: int, sid: int) -> bool:
	if not enabled(state) or not state.digs.has(sid):
		return true
	var d: Dictionary = state.digs[sid]
	var only := int(d.get("only", -1))
	if only >= 0 and only != eid:
		return false
	if int(d.get("by", -1)) == eid or int(d.get("done", -1)) == eid:
		return true
	if int(d.get("sr", 1)) == 0 and Curios.detect(state, eid) < r_int("first_detect", 3) and not t_bool(state, eid, "see_first"):
		return false
	return true


static func site_type(state: GameState, sid: int) -> String:
	return String(state.digs.get(sid, {}).get("at", ""))


static func site_origin(state: GameState, sid: int) -> String:
	return String(state.digs.get(sid, {}).get("or", "g"))


## Description courte d'un site pour l'interface (type, strate, origine si lue).
static func site_desc(state: GameState, eid: int, sid: int) -> String:
	if not enabled(state) or not state.digs.has(sid):
		return ""
	var d: Dictionary = state.digs[sid]
	var parts: Array[String] = [type_label(String(d.get("at", "")))]
	var read := int(d.get("ch", 0)) >= 1 and (int(d.get("by", -1)) == eid or int(d.get("done", -1)) == eid) or lvl(state, eid) >= 1
	if read:
		parts.append("strate %s" % strata_label(int(d.get("sr", 1))).to_lower())
		parts.append(origin_label(state, String(d.get("or", "g"))))
	if int(d.get("seal", 0)) == 1:
		parts.append("quelque chose dort ici")
	if int(d.get("rw", 0)) == 1:
		parts.append("monde-relique")
	if int(d.get("hist", 0)) == 1:
		parts.append("né de notre histoire")
	return " · ".join(parts)


# --- Lancer et poursuivre une fouille (prop. 11, 14) ---------------------------------------------

static func methods() -> Dictionary:
	return cfg("methods")


static func method_label(m: String) -> String:
	return String((methods().get(m, {}) as Dictionary).get("label", "Méthodique"))


## Un empire a-t-il un camp (une flotte à l'arrêt) dans ce système ?
static func has_camp(state: GameState, eid: int, sid: int) -> bool:
	for f in Fleets.empire_fleets(state, eid):
		if f.system_id == sid and not f.is_moving():
			return true
	return false


static func permit_key(host: int, guest: int) -> String:
	return "%d:%d" % [host, guest]


static func has_permit(state: GameState, host: int, guest: int) -> bool:
	if not enabled(state):
		return false
	if state.amph_on and Amphictyony.is_member(state, host) and Amphictyony.is_member(state, guest) and Amphictyony.level_sum(state, "archaeo_free") > 0:
		return true  # Fouilles libres entre membres (famille Patrimoine, voie b)
	var p: Variant = sub(state, "permits").get(permit_key(host, guest), null)
	return p is Dictionary and int((p as Dictionary).get("until", 0)) > state.tick


## Raison qui empêche cet empire de fouiller ici (prop. 11), "" si c'est permis.
static func dig_reason(state: GameState, eid: int, sid: int) -> String:
	var owner := state.system_owner(sid)
	if owner == eid:
		return ""
	if not enabled(state):
		return "il faut posséder le système"
	if owner < 0 or GameState.is_npc(owner):
		if owner >= 0:
			return "le système est tenu par une puissance qui ne signe pas de permis"
		return "" if has_camp(state, eid, sid) else "système libre : il faut une flotte à l'arrêt sur place"
	if has_permit(state, owner, eid):
		return ""
	return "il faut un permis de fouille de %s" % state.get_empire(owner).short_name()


## La fouille en cours peut-elle continuer pour celui qui la mène ?
static func may_continue(state: GameState, sid: int, d: Dictionary) -> bool:
	var by := int(d["by"])
	var owner := state.system_owner(sid)
	if owner == by:
		return true
	if not enabled(state):
		return false
	if owner < 0:
		return has_camp(state, by, sid)
	return not GameState.is_npc(owner) and has_permit(state, owner, by)


static func method_reason(state: GameState, eid: int, sid: int, m: String) -> String:
	if m == "" or m == "methodique" or not enabled(state):
		return ""
	if not methods().has(m):
		return "méthode inconnue"
	if m == "pillage" and state.amph_on and Amphictyony.is_member(state, eid) and Amphictyony.banned(state, "archaeo_pillage"):
		return "la Convention du Patrimoine interdit le pillage"
	if m == "pillage" and int(state.digs.get(sid, {}).get("rw", 0)) == 1:
		return "on ne pille pas un monde-relique : il n'en resterait rien à coloniser"
	return ""


static func on_start(state: GameState, eid: int, sid: int, m: String, added: Array[Dictionary]) -> void:
	if not enabled(state) or not state.digs.has(sid):
		return
	var d: Dictionary = state.digs[sid]
	d["me"] = m if m != "" else "methodique"
	d["clues"] = mini(int(Relics.data()["digs"]["clue_max"]), int(d["clues"]) + t_int(state, eid, "start_clue"))
	ArchaeoBridges.on_start(state, eid, sid, String(d["me"]), added)


## Durée d'une phase (prop. 14 ; talent des Kh'thari).
static func phase_days(state: GameState, eid: int, sid: int) -> int:
	var base := int(Relics.data()["digs"]["phase_days"])
	if not enabled(state) or not state.digs.has(sid):
		return base
	match String(state.digs[sid].get("me", "")):
		"prudente":
			@warning_ignore("integer_division")
			base = base * r_int("phase_pct_prudente", 150) / 100
		"pillage":
			base = r_int("pillage_days", 45)
	@warning_ignore("integer_division")
	return maxi(15, base * (100 + t_int(state, eid, "phase_pct")) / 100)


## Bonus au jet en plus de l'Intendant : trait Archéologue (prop. 6), prêt d'Aster (prop. 33), talent.
static func skill_bonus(state: GameState, eid: int, sid: int) -> int:
	if not enabled(state):
		return 0
	var n := t_int(state, eid, "skill")
	var h := Heroes.at_post(state, "system", sid, eid)
	if not h.is_empty():
		n += Heroes.trait_fx(h, "dig_skill")
	if int(sub(state, "aster").get(str(eid), 0)) > state.tick:
		n += r_int("aster_skill", 2)
	return n


# --- Chapitres, incidents, fin (prop. 15, 18, 20, 21) ---------------------------------------------

static func _who(state: GameState, eid: int, sid: int) -> Variant:
	return Espionage.private_to(state, [eid], sid)


## Un chapitre vient d'être fini (avant le dernier).
static func on_chapter(state: GameState, sid: int, eid: int, added: Array[Dictionary]) -> void:
	if not enabled(state) or not state.digs.has(sid):
		return
	var d: Dictionary = state.digs[sid]
	var m := String(d.get("me", ""))
	if m == "pillage":
		@warning_ignore("integer_division")
		Relics.add_fragments(state, eid, -int(Relics.data()["digs"]["chapter_fragments"]) / 2)
	# Antiquité (prop. 20) : avec la techno, une chance par chapitre (Prudente plus, Pillage moitié moins).
	if lvl(state, eid) >= 1:
		var pct := r_int("antiq_pct", 35) + (r_int("antiq_prudente_pct", 15) if m == "prudente" else 0)
		if m == "pillage":
			@warning_ignore("integer_division")
			pct = pct / 2
		if _h(state, ["antiq", sid, int(d["ch"]), state.tick]) % 100 < pct:
			var aid := add_antiq(state, eid, sid)
			added.append(state.add_chronicle("Fouilles de %s : on remonte %s. Il ira très bien au musée, une fois dépoussiéré." % [
					Relics.site_name(state, sid), antiq_name(state, aid)], _who(state, eid, sid)))
	_hero_xp(state, eid, sid, added)
	add_nature(state, eid, sid, 1)
	ArchaeoWorld.add_vestiges(state, eid, disparu_of(String(d.get("or", ""))), r_int("vestige_chapter", 1), added)
	# Un chapitre sur deux : Étudier ou Exploiter (prop. 15, 16).
	if int(d["ch"]) % 2 == 0 and m != "pillage":
		Events.push(state, eid, "archeo_etude", {"system": sid}, added)


static func _hero_xp(state: GameState, eid: int, sid: int, added: Array[Dictionary]) -> void:
	var h := Heroes.at_post(state, "system", sid, eid)
	if h.is_empty():
		return
	Heroes.gain_xp(state, h, r_int("hero_xp", 30))
	var traits: Array = h.get("traits", [])
	if traits.has("archeologue") or traits.size() >= int(Heroes.data().get("max_traits", 6)):
		return
	if _h(state, ["trait", int(h.get("id", 0)), sid, state.tick]) % 100 < r_int("hero_trait_pct", 20):
		traits.append("archeologue")
		h["traits"] = traits
		added.append(state.add_chronicle("%s a pris goût à la poussière : le voilà Archéologue (+2 aux jets de fouille)." % String(h["name"]), _who(state, eid, sid)))


## Incident enrichi (prop. 18). Renvoie true si l'archéologie l'a pris en charge.
static func incident(state: GameState, sid: int, eid: int, added: Array[Dictionary]) -> bool:
	if not enabled(state) or not state.digs.has(sid):
		return false
	var d: Dictionary = state.digs[sid]
	var pool := {}
	var by_id := {}
	for inc: Dictionary in data().get("incidents", []):
		pool[String(inc["id"])] = int(inc.get("weight", 10))
		by_id[String(inc["id"])] = inc
	var pick := _pick_weighted(state, ["incident", sid, state.tick], pool)
	var inc: Dictionary = by_id.get(pick, {})
	if bool(inc.get("grave", false)) and String(d.get("me", "")) == "prudente":
		return true  # Prudente : rien de grave, la phase est simplement perdue
	var clue_max := int(Relics.data()["digs"]["clue_max"])
	d["clues"] = clampi(int(d["clues"]) + int(inc.get("clues", 0)), 0, clue_max)
	if bool(inc.get("wound", false)):
		var h := Heroes.at_post(state, "system", sid, eid)
		if not h.is_empty() and _h(state, ["blessure", sid, state.tick]) % 100 < r_int("wound_pct", 50):
			var out: Array[Dictionary] = []
			Heroes._wound(state, h, out, "blessé dans un éboulement")
			added.append_array(out)
	if String(inc.get("card", "")) != "":
		Events.push(state, eid, String(inc["card"]), {"system": sid}, added)
	added.append(state.add_chronicle("Fouilles de %s : %s" % [Relics.site_name(state, sid), String(inc.get("text", ""))], _who(state, eid, sid)))
	return true


## Fin d'un site (dernier chapitre). Renvoie true si la relique attend le choix Extraire / Classer.
static func on_finish(state: GameState, sid: int, eid: int, added: Array[Dictionary]) -> bool:
	if not enabled(state) or not state.digs.has(sid):
		return false
	var d: Dictionary = state.digs[sid]
	var m := String(d.get("me", ""))
	var dn := disparu_of(String(d.get("or", "")))
	ArchaeoWorld.add_vestiges(state, eid, dn, r_int("vestige_site", 2), added)
	add_nature(state, eid, sid, 2)
	_stat(state, eid, "sites")
	# La fin dépend du nombre d'études (prop. 15).
	if int(d.get("stu", 0)) >= r_int("finish_study_need", 2):
		var txt := Events.give_research(state, eid, r_int("finish_study_research_pct", 15))
		added.append(state.add_chronicle("À %s, des années de notes patientes se recoupent enfin : %s." % [Relics.site_name(state, sid), txt], _who(state, eid, sid)))
	else:
		var res: Dictionary = type_def(String(d.get("at", ""))).get("res", {})
		var e := state.get_empire(eid)
		for r in res:
			var n := Events.era_scaled(state, eid, int(res[r]))
			if m == "pillage":
				@warning_ignore("integer_division")
				n = n / 2
			e.resources[r] = int(e.resources.get(r, 0)) + n
	# Gisement (prop. 13) : deux sites sur trois, jamais après un pillage.
	if m != "pillage" and _h(state, ["dep", sid]) % 100 < r_int("deposit_pct", 67):
		var vals: Array = rule("deposit_values") if rule("deposit_values") is Array else [[1, 100]]
		var roll := _h(state, ["depv", sid]) % 100
		var v := 1
		for pair in vals:
			roll -= int(pair[1])
			if roll < 0:
				v = int(pair[0])
				break
		sub(state, "dep")[str(sid)] = v
	ArchaeoWorld.on_finish(state, sid, eid, added)
	ArchaeoBridges.on_finish(state, sid, eid, added)
	if m == "pillage":
		extract(state, eid, sid, added)
		return true
	d["pend"] = 1
	Events.push(state, eid, "archeo_fin", {"system": sid}, added)
	return true


## Extraire (prop. 21) : la relique et une antiquité (deux en méthode Prudente) partent pour l'empire,
## ou pour l'hôte si le permis prévoit le partage.
static func extract(state: GameState, eid: int, sid: int, added: Array[Dictionary]) -> void:
	var d: Dictionary = state.digs.get(sid, {})
	if d.is_empty():
		return
	d.erase("pend")
	var rid := String(d.get("relic", ""))
	if rid != "" and int(state.relics.get(rid, {}).get("owner", -2)) == -1:
		Relics.gain(state, eid, rid)
	var dest := eid
	var owner := state.system_owner(sid)
	if owner >= 0 and owner != eid and int((sub(state, "permits").get(permit_key(owner, eid), {}) as Dictionary).get("share", 0)) == 1:
		dest = owner
	var names: Array[String] = []
	if lvl(state, eid) >= 1:
		var n := 2 if String(d.get("me", "")) == "prudente" else 1
		for i in n:
			names.append(antiq_name(state, add_antiq(state, dest, sid)))
	if String(d.get("me", "")) == "pillage":
		ArchaeoBridges.on_pillage(state, eid, sid, added)
	added.append(state.add_chronicle("%s rapporte de %s %s%s." % [state.get_empire(eid).short_name(), Relics.site_name(state, sid),
			String(Relics.def(rid).get("name", "")) if rid != "" else "ses trouvailles",
			(" et %s" % ", ".join(names)) if not names.is_empty() else ""], _who(state, eid, sid)))
	touch(state)


static func can_classify(state: GameState, sid: int) -> bool:
	var d: Dictionary = state.digs.get(sid, {})
	return not d.is_empty() and int(d.get("pend", 0)) == 1 and String(d.get("me", "")) != "pillage"


## Classer en Haut lieu (prop. 21) : rien n'est emporté ; la relique reste en place.
static func classify(state: GameState, eid: int, sid: int, added: Array[Dictionary]) -> void:
	var d: Dictionary = state.digs.get(sid, {})
	if d.is_empty():
		return
	d.erase("pend")
	sub(state, "hl")[str(sid)] = {"by": eid, "day": state.tick, "sr": int(d.get("sr", 1)), "nm": Relics.site_name(state, sid)}
	var rid := String(d.get("relic", ""))
	if rid != "":
		sub(state, "insitu")[rid] = sid
	sub(state, "dep").erase(str(sid))
	_stat(state, eid, "classified")
	Research.count_stat(state, eid, "archaeo_classified")
	added.append(state.add_chronicle("%s classe %s en Haut lieu : on n'y touchera plus. Les visiteurs, eux, y toucheront avec les yeux." % [
			state.get_empire(eid).short_name(), Relics.site_name(state, sid)], Espionage.public_to(state, [eid])))
	touch(state)


static func relic_locked(state: GameState, rid: String) -> bool:
	return enabled(state) and sub(state, "insitu").has(rid)


## Rayonnement et stabilité d'un Haut lieu (croissent avec l'écart entre la strate et l'ère du maître).
static func high_place_value(state: GameState, sid: int, owner: int) -> int:
	var hl: Dictionary = sub(state, "hl").get(str(sid), {})
	if hl.is_empty():
		return 0
	var ages: Array = rule("classify_age") if rule("classify_age") is Array else [3, 2, 1]
	@warning_ignore("integer_division")
	return r_int("classify_base", 2) + int(ages[clampi(int(hl.get("sr", 1)), 0, ages.size() - 1)]) + Research.current_era(state, owner) / 2


static func high_places_of(state: GameState, eid: int) -> Array[int]:
	var out: Array[int] = []
	for k in sub(state, "hl"):
		if state.system_owner(int(k)) == eid:
			out.append(int(k))
	out.sort()
	return out


static func stability_parts(state: GameState, sid: int, _owner: int) -> Array:
	if not enabled(state) or not sub(state, "hl").has(str(sid)):
		return []
	return [["Haut lieu", r_int("classify_stab", 3)]]


## Rayonnement (Culture.source_parts) : antiquités exposées et Hauts lieux.
static func culture_parts(state: GameState, eid: int) -> Array:
	var out := []
	if not enabled(state):
		return out
	var hl := 0
	for sid in high_places_of(state, eid):
		hl += high_place_value(state, sid, eid)
	if hl > 0:
		out.append(["Hauts lieux (%d)" % high_places_of(state, eid).size(), hl])
	out.append_array(ArchaeoWorld.museum_parts(state, eid))
	return out


# --- Cartes d'événement (Events, effet « ar ») ------------------------------------------------------

static func choice_ok(state: GameState, _eid: int, item: Dictionary, key: String) -> bool:
	match key:
		"classify":
			return can_classify(state, int(item.get("system", -1)))
	return true


static func event_act(state: GameState, eid: int, item: Dictionary, act: String, added: Array[Dictionary]) -> void:
	if not enabled(state):
		return
	var sid := int(item.get("system", -1))
	var d: Dictionary = state.digs.get(sid, {})
	var e := state.get_empire(eid)
	match act:
		"study":
			Events.give_research(state, eid, r_int("study_research_pct", 10))
			if not d.is_empty():
				d["stu"] = int(d.get("stu", 0)) + 1
		"catalog":
			Events.give_research(state, eid, r_int("study_research_pct", 10) * 2)
			if not d.is_empty():
				d["stu"] = int(d.get("stu", 0)) + 1
		"exploit":
			var res: Dictionary = type_def(String(d.get("at", ""))).get("res", {})
			for r in res:
				e.resources[r] = int(e.resources.get(r, 0)) + Events.era_scaled(state, eid, int(res[r]))
		"faith":
			if FactionTraits.has_fervor(e.faction()):
				e.fervor = clampi(e.fervor + 8, 0, int(e.faction()["fervor"].get("max", 100)))
		"sell":
			e.resources["energy"] = int(e.resources.get("energy", 0)) + Events.era_scaled(state, eid, 150)
			Relics.add_fragments(state, eid, 10)
		"listen":
			if Echoes.has(e.faction()):
				e.echoes += 15
			else:
				Events.give_research(state, eid, 10)
		"interface":
			Events.give_research(state, eid, 15)
		"extract":
			if int(d.get("pend", 0)) == 1:
				extract(state, eid, sid, added)
		"classify":
			if can_classify(state, sid):
				classify(state, eid, sid, added)
			elif int(d.get("pend", 0)) == 1:
				extract(state, eid, sid, added)
		"clues_up":
			if not d.is_empty():
				d["clues"] = mini(int(Relics.data()["digs"]["clue_max"]), int(d["clues"]) + 3)
		"clues_down":
			if not d.is_empty():
				d["clues"] = maxi(0, int(d["clues"]) - 2)
		"permit_ok":
			ArchaeoBridges.grant_permit(state, eid, int(item.get("rival", -1)), int(item.get("n", 0)), added)
		"permit_no":
			var g := state.get_empire(int(item.get("rival", -1)))
			if g != null:
				added.append(state.add_chronicle("%s refuse le permis de fouille de %s." % [e.short_name(), g.short_name()],
						Espionage.private_to(state, [eid, g.id])))


static func event_line(state: GameState, eid: int, item: Dictionary, act: String) -> String:
	var sid := int(item.get("system", -1))
	var d: Dictionary = state.digs.get(sid, {})
	match act:
		"study":
			return "+%d %% de la recherche en cours ; une étude de plus pour la fin du site" % r_int("study_research_pct", 10)
		"catalog":
			return "+%d %% de la recherche en cours ; une étude de plus" % (r_int("study_research_pct", 10) * 2)
		"exploit":
			var res: Dictionary = type_def(String(d.get("at", ""))).get("res", {})
			var scaled := {}
			for r in res:
				scaled[r] = Events.era_scaled(state, eid, int(res[r]))
			return "+%s" % GameData.format_amounts(scaled)
		"faith":
			return "Ferveur +8"
		"sell":
			return "+%d énergie, +10 fragments" % Events.era_scaled(state, eid, 150)
		"listen":
			return "Échos +15 (ou Savoir)"
		"interface":
			return "+15 % de la recherche en cours"
		"extract":
			return "La relique%s part pour l'empire" % (" et une antiquité" if lvl(state, eid) >= 1 else "")
		"classify":
			return "Haut lieu : Rayonnement et +%d de stabilité dans le système, rien n'est emporté" % r_int("classify_stab", 3)
		"clues_up":
			return "+3 indices"
		"clues_down":
			return "-2 indices"
		"permit_ok":
			return "Permis de fouille pour dix ans"
		"permit_no":
			return "Pas de permis"
	return ""


static func ai_value(state: GameState, eid: int, item: Dictionary, act: String) -> int:
	var sid := int(item.get("system", -1))
	match act:
		"study", "catalog":
			return 500 if act == "study" else 900
		"exploit":
			return 450
		"faith", "sell", "listen", "interface":
			return 600
		"extract":
			return 1200
		"classify":
			# Un peuple tourné vers le Rayonnement, ou un site chez soi, aime les Hauts lieux.
			return 1400 if state.system_owner(sid) == eid and not state.culture.is_empty() else 300
		"clues_up":
			return 350
		"clues_down":
			return -200
		"permit_ok":
			var g := int(item.get("rival", -1))
			return 400 if g >= 0 and Diplomacy.opinion(state, eid, g) >= r_int("permit_min_opinion", 0) else -400
		"permit_no":
			return 0
	return 0


## Jetons {site} et {origin} des cartes d'archéologie.
static func fill(state: GameState, _eid: int, item: Dictionary, s: String) -> String:
	if not s.contains("{site}") and not s.contains("{origin}"):
		return s
	var sid := int(item.get("system", -1))
	var out := s.replace("{site}", Relics.site_name(state, sid) if state.digs.has(sid) else "?")
	return out.replace("{origin}", origin_label(state, site_origin(state, sid)))


# --- Antiquités (prop. 20) -------------------------------------------------------------------------

static func antiqs(state: GameState) -> Dictionary:
	return sub(state, "aq")


static func antiq(state: GameState, id: int) -> Dictionary:
	var v: Variant = antiqs(state).get(str(id), {})
	return v if v is Dictionary else {}


static func add_antiq(state: GameState, eid: int, sid: int, force_o := "") -> int:
	if not enabled(state):
		return -1
	var d: Dictionary = state.digs.get(sid, {})
	var o := force_o if force_o != "" else String(d.get("or", "g"))
	var dn := disparu_of(o)
	var objs: Array = disparu_def(dn).get("objects", []) if dn != "" else cfg("generic_origin").get("objects", [])
	var id := int(state.archaeo.get("next", 1))
	state.archaeo["next"] = id + 1
	var obj := String(objs[_h(state, ["obj", id, sid]) % objs.size()]) if not objs.is_empty() else "Antiquité"
	var name := "%s %s" % [obj, _de(origin_short(state, o))]
	antiqs(state)[str(id)] = {"n": name, "o": o, "d": dn, "t": String(d.get("at", "cite")), "sr": int(d.get("sr", 1)), "own": eid, "day": state.tick}
	_stat(state, eid, "antiqs")
	ArchaeoWorld.add_vestiges(state, eid, dn, 1, [] as Array[Dictionary])  # une antiquité vaut un vestige
	touch(state)
	return id


static func antiq_name(state: GameState, id: int) -> String:
	return String(antiq(state, id).get("n", "une antiquité"))


static func antiqs_of(state: GameState, eid: int) -> Array[int]:
	var out: Array[int] = []
	for k in antiqs(state):
		if int((antiqs(state)[k] as Dictionary).get("own", -1)) == eid:
			out.append(int(k))
	out.sort()
	return out


static func give_antiq(state: GameState, id: int, to: int) -> void:
	var a := antiq(state, id)
	if a.is_empty():
		return
	a["own"] = to
	touch(state)


static func remove_antiq(state: GameState, id: int) -> void:
	antiqs(state).erase(str(id))
	touch(state)


static func antiq_fx(state: GameState, id: int) -> Dictionary:
	return type_def(String(antiq(state, id).get("t", ""))).get("antiq_fx", {})


# --- Trois natures de fragments (prop. 5) ------------------------------------------------------------

static func natures() -> Dictionary:
	var out := {}
	var n := cfg("natures")
	for k in n:
		if not String(k).begins_with("_"):
			out[k] = n[k]
	return out


static func nature_ids() -> Array[String]:
	var out: Array[String] = []
	for k in natures():
		out.append(String(k))
	return out


static func nature_def(k: String) -> Dictionary:
	var v: Variant = natures().get(k, {})
	return v if v is Dictionary else {}


## Nature des fragments d'un type de site ("" si aucune).
static func nature_of_type(t: String) -> String:
	for k in nature_ids():
		if (nature_def(k).get("types", []) as Array).has(t):
			return k
	return ""


static func nat(state: GameState, eid: int, k: String) -> int:
	return int((sub(state, "nat").get(str(eid), {}) as Dictionary).get(k, 0))


static func add_nature(state: GameState, eid: int, sid: int, n: int) -> void:
	if not applies(state, eid) or not state.digs.has(sid):
		return
	var k := nature_of_type(String(state.digs[sid].get("at", "")))
	if k == "":
		return
	if String(state.digs[sid].get("me", "")) == "pillage":
		n = maxi(0, n - 1)
	var m := emp(state, "nat", eid)
	m[k] = int(m.get(k, 0)) + n


static func forge_need() -> int:
	return int(data().get("nature_forge", 3))


## Relique encore libre que trois fragments identiques peuvent forger ("" sinon).
static func forge_relic(state: GameState, eid: int, k: String) -> String:
	var free: Array[String] = []
	for rid in Relics.ids():
		var r: Dictionary = state.relics.get(rid, {})
		if r.is_empty() or int(r["owner"]) != -1 or Relics._buried(state, rid) or relic_locked(state, rid):
			continue
		if Relics.is_quest(rid) or Relics.is_trophy(rid) or Relics.is_ancient_relic(rid) or Relics.is_disparu(rid):
			continue
		free.append(rid)
	if free.is_empty():
		return ""
	return free[_h(state, ["forge", eid, k, state.tick]) % free.size()]


static func _forge(state: GameState, eid: int, k: String, added: Array[Dictionary]) -> void:
	var e := state.get_empire(eid)
	var nd := nature_def(k)
	emp(state, "nat", eid)[k] = nat(state, eid, k) - forge_need()
	var who := Espionage.private_to(state, [eid])
	var rid := forge_relic(state, eid, k)
	if rid != "":
		Relics.gain(state, eid, rid)
		added.append(state.add_chronicle("Trois fragments %s s'emboîtent chez %s : %s, entière, comme si elle n'avait jamais été brisée." % [
				String(nd.get("label", k)).to_lower(), e.short_name(), String(Relics.def(rid).get("name", rid))], who))
		touch(state)
		return
	match String(nd.get("fallback", "")):
		"research":
			var txt := Events.give_research(state, eid, int(nd.get("pct", 30)))
			added.append(state.add_chronicle("Les fragments de Savoir de %s se recoupent : %s." % [e.short_name(), txt], who))
		"influence":
			var n := Events.era_scaled(state, eid, int(nd.get("n", 150)))
			e.resources["influence"] = int(e.resources.get("influence", 0)) + n
			added.append(state.add_chronicle("Les fragments d'Art de %s forment une fresque entière : +%d influence." % [e.short_name(), n], who))
		_:
			emp(state, "fx", eid)["nat:" + k] = state.tick + int(nd.get("days", 1800))
			touch(state)
			added.append(state.add_chronicle("Les fragments d'Arme de %s reconstituent un mécanisme de tir : les arsenaux en tirent leçon." % e.short_name(), who))


# --- Actions de fragments (prop. 24) et ordres ------------------------------------------------------

static func actions() -> Dictionary:
	var out := {}
	var a := cfg("actions")
	for k in a:
		if not String(k).begins_with("_"):
			out[k] = a[k]
	return out


static func action_def(act: String) -> Dictionary:
	var v: Variant = actions().get(act, {})
	return v if v is Dictionary else {}


static func cooldown_left(state: GameState, eid: int, act: String) -> int:
	return maxi(0, int((sub(state, "cd").get(str(eid), {}) as Dictionary).get(act, 0)) - state.tick)


static func frag_cap(state: GameState) -> int:
	return r_int("frag_cap", 500) if enabled(state) else 1 << 30


## Ordres (SimCommands.ar_act) : actions de fragments "fa_*", "permit" (host, share), "reco" (d),
## "secrets" (d), "restitute" (id), "sell_antiq" (id), "aster", "collector_buy" (i), "collector_sell" (id).
static func check(state: GameState, eid: int, act: String, d: Dictionary) -> String:
	if not applies(state, eid):
		return "l'archéologie n'est pas en jeu"
	if act.begins_with("fa_"):
		var ad := action_def(act)
		if ad.is_empty():
			return "action inconnue"
		if lvl(state, eid) < int(ad.get("lvl", 2)):
			return "il faut la technologie Déchiffrement des Strates"
		if cooldown_left(state, eid, act) > 0:
			return "encore %d jours avant de recommencer" % cooldown_left(state, eid, act)
		if Relics.fragments(state, eid) < int(ad.get("cost", 0)):
			return "il faut %d fragments" % int(ad.get("cost", 0))
		if act == "fa_query" and ArchaeoWorld.query_target(state, eid) < 0:
			return "aucun système où cacher un site"
		if act == "fa_sell" and not Relics.can_trade(state, eid):
			return "votre peuple ne vend pas ces choses-là"
		return ""
	match act:
		"forge":
			var k := String(d.get("k", ""))
			if nature_def(k).is_empty():
				return "nature inconnue"
			if nat(state, eid, k) < forge_need():
				return "il faut %d fragments %s" % [forge_need(), String(nature_def(k).get("label", k)).to_lower()]
			return ""
		"reco":
			return ArchaeoWorld.check_reco(state, eid, String(d.get("d", "")))
		"secrets":
			return ArchaeoWorld.check_secrets(state, eid, String(d.get("d", "")))
	return ArchaeoBridges.check(state, eid, act, d)


static func apply(state: GameState, eid: int, act: String, d: Dictionary) -> Array[Dictionary]:
	var added: Array[Dictionary] = []
	if act.begins_with("fa_"):
		_do_action(state, eid, act, added)
		return added
	match act:
		"forge":
			_forge(state, eid, String(d["k"]), added)
		"reco":
			ArchaeoWorld.reco(state, eid, String(d["d"]), added)
		"secrets":
			ArchaeoWorld.start_secrets(state, eid, String(d["d"]), added)
		_:
			ArchaeoBridges.apply(state, eid, act, d, added)
	return added


static func _do_action(state: GameState, eid: int, act: String, added: Array[Dictionary]) -> void:
	var ad := action_def(act)
	var e := state.get_empire(eid)
	Relics.add_fragments(state, eid, -int(ad.get("cost", 0)))
	emp(state, "cd", eid)[act] = state.tick + int(ad.get("cd", 360))
	var who := Espionage.private_to(state, [eid])
	match act:
		"fa_sell":
			var n := Events.era_scaled(state, eid, int(ad.get("energy", 400)))
			e.resources["energy"] = int(e.resources.get("energy", 0)) + n
			added.append(state.add_chronicle("Des collectionneurs privés achètent un lot de fragments à %s : %d énergie, et des sourires gênés." % [e.short_name(), n], who))
		"fa_reverse":
			var txt := Events.give_research(state, eid, int(ad.get("pct", 25)))
			var anc := ""
			if _h(state, ["rev", eid, state.tick]) % 100 < int(ad.get("ancient_pct", 10)):
				anc = ArchaeoWorld.grant_random_ancient(state, eid, added)
			added.append(state.add_chronicle("Rétro-ingénierie chez %s : %s%s." % [e.short_name(), txt, (" ; et surtout %s" % anc) if anc != "" else ""], who))
		"fa_military", "fa_proclaim":
			emp(state, "fx", eid)[act] = state.tick + int(ad.get("days", 1800))
			if act == "fa_proclaim" and FactionTraits.has_fervor(e.faction()):
				e.fervor = clampi(e.fervor + int(ad.get("fervor", 15)), 0, int(e.faction()["fervor"].get("max", 100)))
			added.append(state.add_chronicle("%s : %s." % [e.short_name(), String(ad.get("label", act))], who))
			touch(state)
		"fa_query":
			var sid := ArchaeoWorld.query_target(state, eid)
			if sid >= 0 and create_site(state, sid, {"only": eid}):
				added.append(state.add_chronicle("Les Strates parlent à %s : un site oublié attend à %s." % [e.short_name(), state.galaxy.systems[sid].system_name], who))


# --- Effets (Research.effects) ------------------------------------------------------------------

static func effects(state: GameState, eid: int) -> Dictionary:
	var out := {}
	if not enabled(state):
		return out
	# Antiquités (prop. 20) : les plus anciennes acquises comptent, au plus antiq_cap_fx.
	var mine := antiqs_of(state, eid)
	for i in mini(mine.size(), r_int("antiq_cap_fx", 8)):
		Research._merge(out, antiq_fx(state, mine[i]))
	# Actions de fragments en cours.
	var fx: Dictionary = sub(state, "fx").get(str(eid), {})
	for act in fx:
		if int(fx[act]) > state.tick:
			if String(act).begins_with("nat:"):
				Research._merge(out, nature_def(String(act).substr(4)).get("fx", {}))
			else:
				Research._merge(out, action_def(String(act)).get("fx", {}))
	Research._merge(out, ArchaeoWorld.effects(state, eid))
	return out


# --- Chaque jour --------------------------------------------------------------------------------

static func daily(state: GameState) -> Array[Dictionary]:
	var added: Array[Dictionary] = []
	if not enabled(state):
		return added
	var month := int(GameData.rules()["month_days"])
	if posmod(state.tick, month) == 0:
		_deposits(state)
	ArchaeoWorld.daily(state, added)
	ArchaeoBridges.daily(state, added)
	return added


static func _deposits(state: GameState) -> void:
	var keys := sub(state, "dep").keys()
	keys.sort()
	for k in keys:
		var owner := state.system_owner(int(k))
		if owner >= 0 and not GameState.is_npc(owner):
			Relics.add_fragments(state, owner, int(sub(state, "dep")[k]))
