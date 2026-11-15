class_name Ground
extends RefCounted
## Combat au sol et armées (étude du 2026-11-15, 34 propositions validées ; data/ground.json).
##
## Option de partie « Combat au sol » : "simplifie" (règles d'avant : un nombre de troupes porté par
## les vaisseaux, invasion réussie dès qu'il dépasse la garnison) ou "complet" :
## - les colonies fournissent chaque mois des recrues à la réserve de l'empire ; un régiment se
##   recrute dans un système peuplé (coût, recrues, délai), prend l'espèce de la colonie et ses traits ;
## - un régiment est au sol (dans un système) ou à bord d'une flotte, dont la valeur « troupes » des
##   coques et la Soute à troupes donnent les places ; un transport détruit emporte ses passagers ;
## - ENVAHIR débarque les régiments : après quelques jours de débarquement, bataille au sol contre la
##   milice (la garnison d'avant, que le siège use) et les régiments du défenseur ; front limité par
##   le nombre de colonies, réserve derrière, dégâts quotidiens en santé et en moral ; renforts des deux
##   côtés, retraite risquée de l'attaquant ; la victoire prend ou occupe le système ;
## - entretien : une part des régiments est gratuite (selon la population, plus large pour les couches
##   guerrières), les suivants coûtent leur entretien.
##
## state.ground = {"mode", "r": {"<id>": régiment}, "nid", "q": [recrutements], "rec": {"<empire>": recrues},
##   "b": {"<système>": bataille}, "rep": [rapports], "brid"}
## Régiment : {"id", "o" (empire), "t" (type), "sp" (espèce), "hp", "mo" (moral), "xp", "s" (système),
##   "f" (flotte, -1 au sol)}.
## Bataille : {"s", "a" (attaquant), "d" (défenseur), "st" (début), "land" (fin du débarquement),
##   "mil": [[santé, moral]...] (milice), "units": [unités du rapport], "ux": {"r<id>"|"m<i>": indice},
##   "shots": [[jour, tireur, cible, dégâts, tué]], "lost": [santé perdue attaquant, défenseur], "id"}.
## Tout est déterministe : parcours dans l'ordre des identifiants, aléatoire par state.rng.

const SIMPLE := "simplifie"
const FULL := "complet"
const MODES: Array[String] = ["simplifie", "complet"]
const SHOTS_MAX := 900


static func data() -> Dictionary:
	return GameData.ground()


static func _cfg(k: String) -> Dictionary:
	return data().get(k, {})


static func mode_defs() -> Array:
	return data().get("modes", [])


static func _blank() -> Dictionary:
	return {"mode": SIMPLE, "r": {}, "nid": 1, "q": [], "rec": {}, "b": {}, "rep": [], "brid": 1,
			"fort": {}, "bomb": {}, "dev": {}, "surr": {}, "sortie": {}, "tac": {}, "marks": {}, "res": {}}


static func setup(state: GameState, mode: String) -> void:
	state.ground = _blank()
	state.ground["mode"] = mode if MODES.has(mode) else SIMPLE
	if full(state):
		for e in state.empires:
			state.ground["rec"][str(e.id)] = int(_cfg("recruits").get("start", 6))


static func to_dict(state: GameState) -> Dictionary:
	return state.ground.duplicate(true)


static func from_dict(state: GameState, d: Dictionary) -> void:
	state.ground = _blank()
	for k in d:
		state.ground[k] = Vassals._ints(d[k])
	if not MODES.has(String(state.ground.get("mode", ""))):
		state.ground["mode"] = SIMPLE


static func worth_saving(state: GameState) -> bool:
	return full(state)


static func full(state: GameState) -> bool:
	return String(state.ground.get("mode", SIMPLE)) == FULL


static func _g(state: GameState) -> Dictionary:
	var blank := _blank()
	for k in blank:
		if not state.ground.has(k):
			state.ground[k] = blank[k]
	return state.ground


static func _name(state: GameState, eid: int) -> String:
	var e := state.get_empire(eid)
	return e.display_name() if e != null else "?"


static func _sys(state: GameState, sid: int) -> String:
	return state.galaxy.systems[sid].system_name


# --- Types de régiments ---------------------------------------------------------------------------

static func type_def(t: String) -> Dictionary:
	return _cfg("types").get(t, {})


static func type_label(t: String) -> String:
	return String(type_def(t).get("label", t))


## Types recrutables, dans l'ordre des données.
static func type_ids() -> Array[String]:
	var out: Array[String] = []
	for t in _cfg("types"):
		if bool(_cfg("types")[t].get("recruitable", true)):
			out.append(String(t))
	return out


## Le type est-il ouvert à cet empire (technologies, couches d'espèce de l'espèce recrutée) ?
static func type_allowed(state: GameState, eid: int, t: String, species := "") -> bool:
	var d := type_def(t)
	if d.is_empty() or not bool(d.get("recruitable", true)):
		return false
	if not Research.knows_all(state, eid, d.get("requires_tech", [])):
		return false
	var req: Dictionary = d.get("requires", {})
	if req.has("species"):
		var fid := species if species != "" else Peoples.founder_of(state, eid)
		if not FactionTraits.species_matches(GameData.faction(fid), req["species"]):
			return false
	return true


static func size_of(t: String) -> int:
	return int(type_def(t).get("size", 4))


## Bonus d'une espèce au sol (couches d'espèce : combat.damage_pct, combat.ground_damage_pct…).
static func _species_pct(fid: String, key: String) -> int:
	if fid == "":
		return 100
	return int(GameData.faction(fid).get("combat", {}).get(key, 100))


static func max_hp(r: Dictionary) -> int:
	var base := int(type_def(String(r["t"])).get("hp", 100))
	@warning_ignore("integer_division")
	return maxi(1, base * _species_pct(String(r.get("sp", "")), "ground_hp_pct") / 100)


## Moral maximal : type, rang, technologies (state facultatif pour les technologies).
static func max_morale(r: Dictionary, state: GameState = null) -> int:
	var pct := 100 + rank_pct(r)
	if state != null and r.has("o"):
		pct += Research.fx_int(state, int(r["o"]), "ground_morale_pct")
	@warning_ignore("integer_division")
	return maxi(1, int(type_def(String(r["t"])).get("morale", 200)) * pct / 100)


## Rang de vétérance (prop. 16) selon l'expérience.
static func rank(r: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	for rk: Dictionary in _cfg("veterancy").get("ranks", []):
		if int(r.get("xp", 0)) >= int(rk.get("xp", 0)):
			best = rk
	return best


static func rank_pct(r: Dictionary) -> int:
	return int(rank(r).get("pct", 0))


static func label(state: GameState, r: Dictionary) -> String:
	var sp := String(r.get("sp", ""))
	var who := Peoples.label(sp) if sp != "" else ""
	var rk := rank(r)
	var rl := (" %s" % String(rk["label"]).to_lower()) if not rk.is_empty() and rank_pct(r) > 0 else ""
	return "%s %d%s%s" % [type_label(String(r["t"])), int(r["id"]), rl, (" (%s)" % who) if who != "" and who != sp else ""]


# --- Terrain et tactiques (lot 2, prop. 14-15) -----------------------------------------------------

## Terrain d'une bataille dans un système : la planète la plus peuplée du défenseur (sinon la première).
static func terrain_of(state: GameState, sid: int, defender: int) -> String:
	var best: Colony = null
	var best_type := ""
	for pid in state.galaxy.systems[sid].planet_ids:
		var c: Colony = state.colonies.get(pid)
		var p := state.galaxy.get_planet(pid)
		if best_type == "":
			best_type = p.type
		if c != null and c.owner == defender and c.is_established() and (best == null or c.population > best.population):
			best = c
			best_type = p.type
	return best_type


static func terrain_def(t: String) -> Dictionary:
	return _cfg("terrain").get(t, {})


static func tactic_ids(side: String) -> Array:
	return (_cfg("tactics").get(side, {}) as Dictionary).keys()


static func tactic_def(side: String, t: String) -> Dictionary:
	return _cfg("tactics").get(side, {}).get(t, {})


static func tactic_label(side: String, t: String) -> String:
	return String(tactic_def(side, t).get("label", t))


## Tactique par défaut d'un empire pour un camp ("attack" ou "defense").
static func default_tactic(state: GameState, eid: int, side: String) -> String:
	var d: Dictionary = _g(state)["tac"].get(str(eid), {})
	var t := String(d.get(side, ""))
	if t == "" or tactic_def(side, t).is_empty():
		return "assaut" if side == "attack" else "defense"
	return t


static func check_default_tactic(state: GameState, eid: int, side: String, t: String) -> String:
	if side != "attack" and side != "defense":
		return "camp inconnu"
	if tactic_def(side, t).is_empty():
		return "tactique inconnue"
	if state.get_empire(eid) == null:
		return "empire inconnu"
	return ""


static func set_default_tactic(state: GameState, eid: int, side: String, t: String) -> void:
	var tac: Dictionary = _g(state)["tac"]
	if not tac.has(str(eid)):
		tac[str(eid)] = {}
	tac[str(eid)][side] = t


## Changer la tactique d'une bataille : seulement pendant le débarquement, pour son camp.
static func check_battle_tactic(state: GameState, eid: int, sid: int, t: String) -> String:
	var b := battle(state, sid)
	if b.is_empty():
		return "aucune bataille au sol ici"
	var side := "attack" if int(b["a"]) == eid else "defense" if int(b["d"]) == eid else ""
	if side == "":
		return "vous ne combattez pas ici"
	if tactic_def(side, t).is_empty():
		return "tactique inconnue"
	if state.tick >= int(b["land"]):
		return "la bataille a commencé : trop tard pour changer de tactique"
	return ""


static func set_battle_tactic(state: GameState, eid: int, sid: int, t: String) -> void:
	var b := battle(state, sid)
	if int(b["a"]) == eid:
		var old := String(b.get("ta", "assaut"))
		b["ta"] = t
		# Le débarquement s'allonge ou raccourcit avec la tactique.
		b["land"] = maxi(state.tick, int(b["land"]) + _landing_days(state, eid, t) - _landing_days(state, eid, old))
	else:
		b["td"] = t
		_capitulate(state, b)


static func _landing_days(state: GameState, eid: int, tactic: String) -> int:
	var days := int(tactic_def("attack", tactic).get("landing_days", _cfg("battle").get("landing_days", 3)))
	return maxi(1, days + Research.fx_int(state, eid, "landing_days"))


## Capitulation : le défenseur sans régiment rend le monde dès le débarquement.
static func _capitulate(state: GameState, b: Dictionary) -> bool:
	if not bool(tactic_def("defense", String(b.get("td", ""))).get("surrender", false)):
		return false
	if not on_ground(state, int(b["s"]), int(b["d"])).is_empty():
		return false
	state.add_chronicle("%s capitule sans combattre devant %s : les clés de la ville sont remises sur un coussin." % [_sys(state, int(b["s"])), _name(state, int(b["a"]))])
	b["mil"] = []
	b["land"] = state.tick
	_end(state, b, int(b["a"]))
	return true


## Tir au débarquement (prop. 8, 22) : bâtiments du défenseur et technologie, moins le sabotage des commandos.
static func landing_fire_pct(state: GameState, sid: int, attacker: int, regs: Array) -> int:
	var defender := WarPeace.holder(state, sid)
	var n := 0
	var has_col := false
	for pid in state.galaxy.systems[sid].planet_ids:
		var c: Colony = state.colonies.get(pid)
		if c == null or c.owner != defender or not c.is_established():
			continue
		has_col = true
		for bid in c.buildings:
			n += int(GameData.building(bid).get("landing_fire", 0))
	if has_col and defender >= 0:
		n += Research.fx_int(state, defender, "landing_fire_pct")
	var sab := 0
	for r in regs:
		sab += int(type_def(String(r["t"])).get("abilities", {}).get("sabotage", 0))
	var sc := _cfg("siege")
	return maxi(0, n - mini(sab, int(sc.get("sabotage_max", 3))) * int(sc.get("sabotage_pct", 20)))


# --- Régiments : où ils sont ----------------------------------------------------------------------

static func regiment(state: GameState, rid: int) -> Dictionary:
	return _g(state)["r"].get(str(rid), {})


static func _sorted_ids(state: GameState) -> Array[int]:
	var out: Array[int] = []
	for k in _g(state)["r"]:
		out.append(int(k))
	out.sort()
	return out


static func regiments_of(state: GameState, eid: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for rid in _sorted_ids(state):
		var r: Dictionary = state.ground["r"][str(rid)]
		if int(r["o"]) == eid:
			out.append(r)
	return out


static func aboard(state: GameState, fid: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for rid in _sorted_ids(state):
		var r: Dictionary = state.ground["r"][str(rid)]
		if int(r["f"]) == fid:
			out.append(r)
	return out


## Régiments au sol dans un système (d'un empire, ou de tous si eid < 0).
static func on_ground(state: GameState, sid: int, eid := -1) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for rid in _sorted_ids(state):
		var r: Dictionary = state.ground["r"][str(rid)]
		if int(r["f"]) < 0 and int(r["s"]) == sid and (eid < 0 or int(r["o"]) == eid):
			out.append(r)
	return out


static func used_places(state: GameState, fid: int) -> int:
	var n := 0
	for r in aboard(state, fid):
		n += size_of(String(r["t"]))
	return n


static func capacity(state: GameState, f: Fleet) -> int:
	return Combat.max_troops(f, state)


static func free_places(state: GameState, f: Fleet) -> int:
	return capacity(state, f) - used_places(state, f.id)


## En mode complet, la valeur « troupes » d'une flotte compte les places occupées par ses régiments.
static func sync_fleet(state: GameState, f: Fleet) -> void:
	if full(state) and f != null:
		f.troops = used_places(state, f.id)


static func sync_all(state: GameState) -> void:
	if not full(state):
		return
	var used := {}
	for rid in _sorted_ids(state):
		var r: Dictionary = state.ground["r"][str(rid)]
		var fid := int(r["f"])
		if fid >= 0:
			used[fid] = int(used.get(fid, 0)) + size_of(String(r["t"]))
	for fid in state.sorted_fleet_ids():
		var f: Fleet = state.fleets[fid]
		f.troops = int(used.get(f.id, 0))


## Force d'un groupe de régiments (santé × dégâts moyens) : pour l'IA et l'affichage.
static func strength(regs: Array) -> int:
	var n := 0
	for r: Dictionary in regs:
		var d: Array = type_def(String(r["t"])).get("dmg", [5, 10])
		@warning_ignore("integer_division")
		n += int(r["hp"]) * (int(d[0]) + int(d[1])) / 20
	return n


## Force de la milice d'un système (selon sa garnison actuelle).
static func militia_strength(state: GameState, sid: int) -> int:
	var units := militia_units(state, sid)
	var m := type_def("milice")
	var d: Array = m.get("dmg", [3, 6])
	@warning_ignore("integer_division")
	return units * int(m.get("hp", 60)) * (int(d[0]) + int(d[1])) / 20


static func militia_units(state: GameState, sid: int) -> int:
	var per := maxi(1, int(_cfg("battle").get("militia_per_unit", 15)))
	var g := Combat.garrison(state, sid)
	@warning_ignore("integer_division")
	return mini(int(_cfg("battle").get("militia_max", 30)), (g + per - 1) / per)


# --- Recrues et entretien -------------------------------------------------------------------------

static func population(state: GameState, eid: int) -> int:
	var n := 0
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner == eid and c.is_colony() and c.is_established():
			n += c.population
	return n


static func recruits(state: GameState, eid: int) -> int:
	return int(_g(state)["rec"].get(str(eid), 0))


static func recruits_cap(state: GameState, eid: int) -> int:
	var rc := _cfg("recruits")
	return maxi(int(rc.get("cap_min", 6)), population(state, eid) * int(rc.get("cap_per_pop", 1)))


static func recruits_gain(state: GameState, eid: int) -> int:
	var rc := _cfg("recruits")
	var peopled := 0
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner == eid and c.is_colony() and c.is_established() and c.population > 0:
			peopled += 1
	@warning_ignore("integer_division")
	var g := maxi(peopled, population(state, eid) / maxi(1, int(rc.get("every_pop", 4))))
	return Research.scaled(g, Research.fx_int(state, eid, "recruits_pct")) if g > 0 else 0


static func _monthly(state: GameState) -> void:
	for e in state.empires:
		if e.eliminated:
			continue
		var k := str(e.id)
		var cur := recruits(state, e.id)
		var cap := recruits_cap(state, e.id)
		if cur < cap:
			state.ground["rec"][k] = mini(cap, cur + recruits_gain(state, e.id))


## Nombre de régiments sans entretien.
static func free_regiments(state: GameState, eid: int) -> int:
	var u := _cfg("upkeep")
	@warning_ignore("integer_division")
	var n := int(u.get("free_base", 2)) + population(state, eid) / maxi(1, int(u.get("free_every_pop", 6)))
	var e := state.get_empire(eid)
	var pct := int(e.faction().get("combat", {}).get("army_free_pct", 100)) if e != null else 100
	@warning_ignore("integer_division")
	return n * pct / 100


## Entretien mensuel des régiments (les premiers recrutés sont gratuits).
static func upkeep(state: GameState, eid: int) -> Dictionary:
	var out := {}
	if not full(state):
		return out
	var free := free_regiments(state, eid)
	var i := 0
	for r in regiments_of(state, eid):
		if int(r.get("merc", 0)) == 0:
			i += 1
			if i <= free:
				continue
		var up: Dictionary = type_def(String(r["t"])).get("upkeep", {})
		for res in up:
			out[res] = int(out.get(res, 0)) + int(up[res])
	return out


# --- Recrutement ----------------------------------------------------------------------------------

## Espèce recrutée par défaut dans un système : la plus nombreuse de la plus grande colonie.
static func default_species(state: GameState, eid: int, sid: int) -> String:
	var best: Colony = null
	for pid in state.galaxy.systems[sid].planet_ids:
		var c: Colony = state.colonies.get(pid)
		if c != null and c.owner == eid and c.is_colony() and c.is_established() and (best == null or c.population > best.population):
			best = c
	if best == null:
		return Peoples.founder_of(state, eid)
	if state.peoples_on:
		var cnt := Peoples.counts(state, best)
		var top := ""
		var keys := cnt.keys()
		keys.sort()
		for fid in keys:
			if top == "" or int(cnt[fid]) > int(cnt[top]):
				top = String(fid)
		if top != "":
			return top
	return Peoples.founder_of(state, eid)


## Espèces qu'un système peut fournir.
static func species_in(state: GameState, eid: int, sid: int) -> Array[String]:
	var out: Array[String] = []
	for pid in state.galaxy.systems[sid].planet_ids:
		var c: Colony = state.colonies.get(pid)
		if c == null or c.owner != eid or not c.is_colony() or not c.is_established():
			continue
		if state.peoples_on:
			for fid in Peoples.counts(state, c):
				if not out.has(String(fid)):
					out.append(String(fid))
		else:
			var f := Peoples.founder_of(state, eid)
			if not out.has(f):
				out.append(f)
	out.sort()
	return out


static func check_recruit(state: GameState, eid: int, sid: int, t: String, species := "") -> String:
	if not full(state):
		return "les armées ne sont pas en jeu (combat au sol simplifié)"
	var e := state.get_empire(eid)
	if e == null or e.eliminated:
		return "empire inconnu"
	if sid < 0 or sid >= state.galaxy.systems.size():
		return "système inconnu"
	if WarPeace.holder(state, sid) != eid:
		return "ce système n'est pas à vous"
	var sp := species_in(state, eid, sid)
	if sp.is_empty():
		return "il faut une colonie peuplée pour recruter"
	if species != "" and not sp.has(species):
		return "cette espèce ne vit pas dans ce système"
	if battle(state, sid).size() > 0:
		return "on se bat déjà au sol ici"
	var d := type_def(t)
	if d.is_empty() or not bool(d.get("recruitable", true)):
		return "type de régiment inconnu"
	if not type_allowed(state, eid, t, species if species != "" else default_species(state, eid, sid)):
		var techs: Array = d.get("requires_tech", [])
		if not Research.knows_all(state, eid, techs):
			return "il faut la technologie %s" % ", ".join(PackedStringArray(techs.map(func(x: Variant) -> String: return String(Research.tech(String(x)).get("label", x)))))
		return "votre peuple ne lève pas ce régiment"
	if int(d.get("unique", 0)) > 0:
		var n := 0
		for r in regiments_of(state, eid):
			if String(r["t"]) == t:
				n += 1
		for q: Dictionary in queue_of(state, eid):
			if String(q["t"]) == t:
				n += 1
		if n >= int(d["unique"]):
			return "un seul %s par empire" % type_label(t).to_lower()
	var need := int(d.get("recruits", 2))
	if recruits(state, eid) < need:
		return "%d recrues nécessaires (réserve : %d)" % [need, recruits(state, eid)]
	if not Economy.can_afford(e, d.get("cost", {})):
		return "ressources insuffisantes"
	return ""


static func recruit(state: GameState, eid: int, sid: int, t: String, species := "") -> void:
	var d := type_def(t)
	var e := state.get_empire(eid)
	Economy.pay(e, d.get("cost", {}))
	var k := str(eid)
	state.ground["rec"][k] = recruits(state, eid) - int(d.get("recruits", 2))
	var sp := species if species != "" else default_species(state, eid, sid)
	(_g(state)["q"] as Array).append({"e": eid, "s": sid, "t": t, "sp": sp, "d": state.tick + recruit_days(state, eid, t)})


## Délai de formation d'un régiment (technologies comprises).
static func recruit_days(state: GameState, eid: int, t: String) -> int:
	@warning_ignore("integer_division")
	return maxi(1, int(type_def(t).get("days", 30)) * maxi(10, 100 + Research.fx_int(state, eid, "recruit_days_pct")) / 100)


## Espèce la plus nombreuse d'une colonie (celle qu'on y recrute).
static func colony_species(state: GameState, c: Colony) -> String:
	if not state.peoples_on:
		return Peoples.founder_of(state, c.owner)
	var cnt := Peoples.counts(state, c)
	var keys := cnt.keys()
	keys.sort()
	var top := ""
	for fid in keys:
		if top == "" or int(cnt[fid]) > int(cnt[top]):
			top = String(fid)
	return top if top != "" else Peoples.founder_of(state, c.owner)


## Recrutements en cours d'un empire (dans un système, ou partout si sid < 0).
static func queue_of(state: GameState, eid: int, sid := -1) -> Array:
	var out := []
	for q: Dictionary in _g(state)["q"]:
		if int(q["e"]) == eid and (sid < 0 or int(q["s"]) == sid):
			out.append(q)
	return out


static func _new_regiment(state: GameState, eid: int, t: String, sp: String, sid: int, fid := -1) -> Dictionary:
	var g := _g(state)
	var rid := int(g["nid"])
	g["nid"] = rid + 1
	var r := {"id": rid, "o": eid, "t": t, "sp": sp, "hp": 0, "mo": 0, "xp": 0, "s": sid, "f": fid}
	r["hp"] = max_hp(r)
	r["mo"] = max_morale(r)
	g["r"][str(rid)] = r
	return r


static func _process_queue(state: GameState, added: Array[Dictionary]) -> void:
	var q: Array = _g(state)["q"]
	var keep := []
	for item: Dictionary in q:
		if state.tick < int(item["d"]):
			keep.append(item)
			continue
		var eid := int(item["e"])
		var sid := int(item["s"])
		if WarPeace.holder(state, sid) != eid:
			continue  # le système a changé de mains : le régiment ne naît pas
		var r := _new_regiment(state, eid, String(item["t"]), String(item["sp"]), sid)
		var _unused := r
	state.ground["q"] = keep
	var _a := added


static func check_demobilize(state: GameState, eid: int, rid: int) -> String:
	var r := regiment(state, rid)
	if r.is_empty() or int(r["o"]) != eid:
		return "ce régiment n'est pas à vous"
	if int(r["f"]) >= 0:
		return "débarquez-le d'abord dans un de vos systèmes"
	if WarPeace.holder(state, int(r["s"])) != eid:
		return "il faut être chez vous pour rendre les soldats à la vie civile"
	if not battle(state, int(r["s"])).is_empty():
		return "on se bat ici"
	return ""


static func demobilize(state: GameState, eid: int, rid: int) -> void:
	var r := regiment(state, rid)
	var back := int(type_def(String(r["t"])).get("recruits", 2)) * int(_cfg("recruits").get("demob_refund_pct", 50)) / 100
	state.ground["rec"][str(eid)] = mini(recruits_cap(state, eid), recruits(state, eid) + back)
	state.ground["r"].erase(str(rid))


# --- Embarquer, débarquer -------------------------------------------------------------------------

static func check_embark(state: GameState, eid: int, fid: int) -> String:
	if not full(state):
		return "les armées ne sont pas en jeu"
	var f: Fleet = state.fleets.get(fid)
	if f == null or f.owner != eid:
		return "cette flotte ne vous appartient pas"
	if f.is_moving():
		return "la flotte doit être à l'arrêt"
	if not battle(state, f.system_id).is_empty():
		return "on se bat au sol ici"
	if on_ground(state, f.system_id, eid).is_empty():
		return "aucun de vos régiments n'attend ici"
	if capacity(state, f) <= 0:
		return "aucune place de troupes à bord (transports, croiseurs, soutes)"
	var room := free_places(state, f)
	for r in on_ground(state, f.system_id, eid):
		if size_of(String(r["t"])) <= room:
			return ""
	return "plus de place à bord (%d place%s libre%s)" % [room, "s" if room > 1 else "", "s" if room > 1 else ""]


static func embark(state: GameState, eid: int, fid: int) -> void:
	var f: Fleet = state.fleets[fid]
	var room := free_places(state, f)
	for r in on_ground(state, f.system_id, eid):
		var sz := size_of(String(r["t"]))
		if sz <= room:
			r["f"] = fid
			room -= sz
	sync_fleet(state, f)


static func check_disembark(state: GameState, eid: int, fid: int) -> String:
	if not full(state):
		return "les armées ne sont pas en jeu"
	var f: Fleet = state.fleets.get(fid)
	if f == null or f.owner != eid:
		return "cette flotte ne vous appartient pas"
	if f.is_moving():
		return "la flotte doit être à l'arrêt"
	if aboard(state, fid).is_empty():
		return "aucun régiment à bord"
	if WarPeace.holder(state, f.system_id) != eid:
		return "on ne débarque en garnison que chez soi (pour attaquer : ENVAHIR)"
	return ""


static func disembark(state: GameState, eid: int, fid: int) -> void:
	var f: Fleet = state.fleets[fid]
	for r in aboard(state, fid):
		r["f"] = -1
		r["s"] = f.system_id
	sync_fleet(state, f)


## Fusion de flottes : les régiments suivent.
static func on_merge(state: GameState, from_id: int, into_id: int) -> void:
	if not full(state):
		return
	for r in aboard(state, from_id):
		r["f"] = into_id
	sync_fleet(state, state.fleets.get(into_id))


## Flotte scindée : les régiments passent dans la nouvelle tant qu'ils n'ont plus la place dans l'ancienne.
static func on_split(state: GameState, f: Fleet, nf: Fleet) -> void:
	if not full(state):
		return
	var cap := capacity(state, f)
	var used := 0
	var room := capacity(state, nf)
	for r in aboard(state, f.id):
		var sz := size_of(String(r["t"]))
		if used + sz <= cap:
			used += sz
		elif sz <= room:
			r["f"] = nf.id
			room -= sz
	sync_fleet(state, f)
	sync_fleet(state, nf)


# --- Invasion -------------------------------------------------------------------------------------

static func battle(state: GameState, sid: int) -> Dictionary:
	return _g(state)["b"].get(str(sid), {})


static func battles(state: GameState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var keys: Array = _g(state)["b"].keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return int(a) < int(b))
	for k in keys:
		out.append(state.ground["b"][k])
	return out


## Les troupes peuvent-elles débarquer ? (appelé par Combat.check_invade une fois l'orbite dégagée)
static func check_land(state: GameState, eid: int, f: Fleet) -> String:
	if aboard(state, f.id).is_empty():
		return "aucun régiment à bord : recrutez-en sur une colonie et embarquez-les"
	var b := battle(state, f.system_id)
	if not b.is_empty() and int(b["a"]) != eid:
		return "une autre armée assaille déjà ce monde"
	return ""


## Débarquement (ordre ENVAHIR) : bataille au sol, ou renfort d'une bataille en cours.
static func land(state: GameState, f: Fleet) -> void:
	var sid := f.system_id
	var eid := f.owner
	var landing := aboard(state, f.id)
	var cur := battle(state, sid)
	var ta := String(cur.get("ta", default_tactic(state, eid, "attack")))
	var fire := 0 if bool(tactic_def("attack", ta).get("no_landing_fire", false)) else landing_fire_pct(state, sid, eid, landing)
	var shot := 0
	for r in landing:
		r["f"] = -1
		r["s"] = sid
		if fire > 0:
			@warning_ignore("integer_division")
			r["hp"] = maxi(1, int(r["hp"]) - max_hp(r) * fire / 100)
			shot += 1
	if shot > 0:
		state.add_chronicle("Les batteries de %s ouvrent le feu sur les péniches de %s : %d régiment%s touché%s avant même de toucher le sol." % [
				_sys(state, sid), _name(state, eid), shot, "s" if shot > 1 else "", "s" if shot > 1 else ""], [eid, WarPeace.holder(state, sid)])
	sync_fleet(state, f)
	if not battle(state, sid).is_empty():
		_note(battle(state, sid), state)
		return
	var defender := WarPeace.holder(state, sid)
	var mil := []
	var m := type_def("milice")
	for i in militia_units(state, sid):
		mil.append([int(m.get("hp", 60)), int(m.get("morale", 120))])
	# La faune défend les mondes sauvages qu'elle hante (prop. 31).
	for ff in Fleets.fleets_at(state, sid, GameState.FAUNA_ID):
		if Fauna.hostile(state, ff, eid):
			for i in int(_cfg("battle").get("fauna_militia", 2)):
				mil.append([int(m.get("hp", 60)), int(m.get("morale", 120))])
			break
	var b := start_battle(state, sid, eid, defender, mil, ta)
	state.add_chronicle("Les régiments de %s débarquent sur %s : %d contre %d défenseurs. Les péniches rasent les toits, les sirènes répondent." % [
			_name(state, eid), _sys(state, sid), on_ground(state, sid, eid).size(), mil.size() + on_ground(state, sid, defender).size()],
			Espionage.public_to(state, [eid, defender]) if state.empires.size() > 0 else null)
	if _capitulate(state, b):
		return
	# Personne pour défendre : le monde tombe sans combat.
	if mil.is_empty() and on_ground(state, sid, defender).is_empty():
		b["land"] = state.tick
		_end(state, b, eid)


## Ouvre une bataille au sol (débarquement, ou insurrection : voir GroundOccupation).
static func start_battle(state: GameState, sid: int, eid: int, defender: int, mil: Array, ta := "") -> Dictionary:
	if ta == "":
		ta = default_tactic(state, eid, "attack")
	var bid := int(_g(state)["brid"])
	state.ground["brid"] = bid + 1
	var td := default_tactic(state, defender, "defense")
	var b := {"id": bid, "s": sid, "a": eid, "d": defender, "st": state.tick,
			"land": state.tick + _landing_days(state, eid, ta), "mil": mil,
			"units": [], "ux": {}, "shots": [], "lost": [0, 0], "dsp": Peoples.founder_of(state, defender),
			"ter": terrain_of(state, sid, defender), "ta": ta, "td": td, "dev0": GroundSiege.dev(state, sid)}
	state.ground["b"][str(sid)] = b
	_note(b, state)
	return b


## Inscrit les unités nouvelles dans le rapport de la bataille.
static func _note(b: Dictionary, state: GameState) -> void:
	var ux: Dictionary = b["ux"]
	var units: Array = b["units"]
	for r in on_ground(state, int(b["s"])):
		var o := int(r["o"])
		if o != int(b["a"]) and o != int(b["d"]):
			continue
		var k := "r%d" % int(r["id"])
		if not ux.has(k):
			ux[k] = units.size()
			units.append({"k": k, "side": 0 if o == int(b["a"]) else 1, "t": String(r["t"]), "sp": String(r.get("sp", "")),
					"hp": max_hp(r), "n": label(state, r)})
	var mil: Array = b["mil"]
	for i in mil.size():
		var k := "m%d" % i
		if not ux.has(k):
			ux[k] = units.size()
			units.append({"k": k, "side": 1, "t": "milice", "sp": String(b.get("dsp", "")), "hp": int(type_def("milice").get("hp", 60)),
					"n": "Milice %d" % (i + 1)})


static func check_retreat(state: GameState, eid: int, sid: int) -> String:
	var b := battle(state, sid)
	if b.is_empty() or int(b["a"]) != eid:
		return "vous n'assaillez pas ce monde"
	var left := int(b["st"]) + int(_cfg("battle").get("retreat_min_days", 10)) - state.tick
	if left > 0:
		return "les péniches ne reviendront pas avant %d jour%s" % [left, "s" if left > 1 else ""]
	return ""


## Retraite : chaque régiment risque de périr au rembarquement (d'autant plus qu'il est blessé) ;
## les survivants remontent dans les flottes de l'empire sur place, s'il y a de la place.
static func retreat(state: GameState, eid: int, sid: int) -> void:
	var b := battle(state, sid)
	var loss := int(_cfg("battle").get("retreat_loss_pct", 60))
	var fleets := Fleets.fleets_at(state, sid, eid)
	var lost := 0
	var saved := 0
	for r in on_ground(state, sid, eid):
		var hurt := 100 - int(r["hp"]) * 100 / max_hp(r)
		if state.rng.randi_range(1, 100) <= hurt * loss / 100:
			state.ground["r"].erase(str(int(r["id"])))
			lost += 1
			continue
		var placed := false
		for f in fleets:
			if not f.is_moving() and free_places(state, f) >= size_of(String(r["t"])):
				r["f"] = f.id
				sync_fleet(state, f)
				placed = true
				break
		if placed:
			saved += 1
		else:
			state.ground["r"].erase(str(int(r["id"])))
			lost += 1
	state.add_chronicle("%s sonne la retraite sur %s : %d régiment%s rembarqué%s, %d perdu%s sur les plages." % [
			_name(state, eid), _sys(state, sid), saved, "s" if saved > 1 else "", "s" if saved > 1 else "", lost, "s" if lost > 1 else ""])
	_finish(state, b, int(b["d"]), "retreat")


# --- Journée ---------------------------------------------------------------------------------------

## Chaque jour (mode complet) : recrutements terminés, régiments perdus en mer ou en trop, batailles,
## santé et moral. Renvoie les entrées de chronique.
static func daily(state: GameState) -> Array[Dictionary]:
	var added: Array[Dictionary] = []
	if not full(state):
		return added
	# Repère : la dernière entrée existante (la chronique est plafonnée, un indice de départ ne
	# suffit pas une fois pleine).
	var last: Variant = state.chronicle.back() if not state.chronicle.is_empty() else null
	_g(state)
	if state.tick % int(GameData.rules()["month_days"]) == 0:
		_monthly(state)
		GroundOccupation.monthly(state)
	_process_queue(state, added)
	_check_transport(state)
	for b in battles(state):
		_fight(state, b)
	GroundSiege.daily(state)
	_strays(state)
	_recover(state)
	sync_all(state)
	var fresh: Array[Dictionary] = []
	for i in range(state.chronicle.size() - 1, -1, -1):
		if last != null and is_same(state.chronicle[i], last):
			break
		fresh.push_front(state.chronicle[i])
	added.append_array(fresh)
	return added


## Régiments à bord d'une flotte disparue, ou de trop pour les places qui restent : perdus.
static func _check_transport(state: GameState) -> void:
	var lost := {}
	for rid in _sorted_ids(state):
		var r: Dictionary = state.ground["r"][str(rid)]
		var fid := int(r["f"])
		if fid >= 0 and not state.fleets.has(fid):
			lost[int(r["o"])] = int(lost.get(int(r["o"]), 0)) + 1
			state.ground["r"].erase(str(rid))
	for fid in state.sorted_fleet_ids():
		var f: Fleet = state.fleets[fid]
		var regs := aboard(state, fid)
		if regs.is_empty():
			continue
		var cap := capacity(state, f)
		var used := used_places(state, fid)
		var i := regs.size() - 1
		while used > cap and i >= 0:
			used -= size_of(String(regs[i]["t"]))
			state.ground["r"].erase(str(int(regs[i]["id"])))
			lost[f.owner] = int(lost.get(f.owner, 0)) + 1
			i -= 1
	var owners := lost.keys()
	owners.sort()
	for o in owners:
		var n := int(lost[o])
		state.add_chronicle("%s perd %d régiment%s avec ses transports : les soutes n'étaient pas faites pour couler." % [_name(state, int(o)), n, "s" if n > 1 else ""], [int(o)])


## Régiments au sol dans un système qu'ils ne tiennent pas, hors bataille (paix signée, système cédé) :
## rapatriés vers la capitale, ou dissous s'il n'y en a plus.
static func _strays(state: GameState) -> void:
	for rid in _sorted_ids(state):
		if not state.ground["r"].has(str(rid)):
			continue
		var r: Dictionary = state.ground["r"][str(rid)]
		if int(r["f"]) >= 0:
			continue
		var sid := int(r["s"])
		var o := int(r["o"])
		if WarPeace.holder(state, sid) == o:
			continue
		var b := battle(state, sid)
		if not b.is_empty() and (int(b["a"]) == o or int(b["d"]) == o):
			continue
		var home := FactionTraits.capital_system(state, o)
		if home >= 0 and WarPeace.holder(state, home) == o:
			r["s"] = home
		else:
			state.ground["r"].erase(str(rid))


static func _recover(state: GameState) -> void:
	var rc := _cfg("recovery")
	var fighting := {}
	for b in battles(state):
		fighting[int(b["s"])] = true
	for rid in _sorted_ids(state):
		var r: Dictionary = state.ground["r"][str(rid)]
		var sid := int(r["s"])
		if int(r["f"]) < 0 and fighting.has(sid):
			continue
		if int(r["f"]) < 0 and Logistics.ground_unsupplied(state, int(r["o"]), sid):
			continue  # logistique complète : régiments sans ravitaillement, aucun renfort
		var home := int(r["f"]) < 0 and WarPeace.holder(state, sid) == int(r["o"])
		var pct := int(rc.get("home_pct", 10)) if home else int(rc.get("away_pct", 3))
		@warning_ignore("integer_division")
		pct = pct * maxi(10, 100 + Research.fx_int(state, int(r["o"]), "ground_recovery_pct")) / 100
		var mh := max_hp(r)
		var mm := max_morale(r, state)
		@warning_ignore("integer_division")
		r["hp"] = mini(mh, int(r["hp"]) + maxi(1, mh * pct / 100))
		@warning_ignore("integer_division")
		r["mo"] = mini(mm, int(r["mo"]) + maxi(1, mm * pct / 100))


# --- Bataille --------------------------------------------------------------------------------------

## Unité de bataille : {"k", "r" (régiment, {} pour la milice), "mi" (indice de milice), "t", "sp", "hp", "mo", "mh", "mm"}.
static func _units(state: GameState, b: Dictionary, side: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var eid := int(b["a"]) if side == 0 else int(b["d"])
	for r in on_ground(state, int(b["s"]), eid):
		out.append({"k": "r%d" % int(r["id"]), "r": r, "mi": -1, "t": String(r["t"]), "sp": String(r.get("sp", "")),
				"hp": int(r["hp"]), "mo": int(r["mo"]), "mh": max_hp(r), "mm": max_morale(r, state)})
	if side == 1:
		var mil: Array = b["mil"]
		var m := type_def("milice")
		for i in mil.size():
			if int(mil[i][0]) <= 0:
				continue
			out.append({"k": "m%d" % i, "r": {}, "mi": i, "t": "milice", "sp": String(b.get("dsp", "")),
					"hp": int(mil[i][0]), "mo": int(mil[i][1]), "mh": int(m.get("hp", 60)), "mm": int(m.get("morale", 120))})
	return out


static func front_width(state: GameState, sid: int) -> int:
	var bc := _cfg("battle")
	var cols := 0
	for pid in state.galaxy.systems[sid].planet_ids:
		var c: Colony = state.colonies.get(pid)
		if c != null and c.is_established():
			cols += 1
	return mini(int(bc.get("front_max", 10)), int(bc.get("front_base", 3)) + cols * int(bc.get("front_per_colony", 1)))


static func _front(units: Array[Dictionary], width: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for u in units:
		if int(u["mo"]) > 0 and out.size() < width:
			out.append(u)
	if out.is_empty():
		# Plus personne en état de tenir le front : les débandés sont pris à partie.
		for u in units:
			if out.size() < width:
				out.append(u)
	return out


static func _pick(state: GameState, front: Array[Dictionary]) -> int:
	var w := int(_cfg("battle").get("wounded_weight", 2))
	var total := 0
	for u in front:
		total += w if int(u["hp"]) * 2 < int(u["mh"]) else 1
	var roll := state.rng.randi_range(1, maxi(1, total))
	for i in front.size():
		roll -= w if int(front[i]["hp"]) * 2 < int(front[i]["mh"]) else 1
		if roll <= 0:
			return i
	return front.size() - 1


static func _damage(state: GameState, b: Dictionary, side: int, u: Dictionary, target: Dictionary) -> int:
	var d := type_def(String(u["t"]))
	var dmg: Array = d.get("dmg", [5, 10])
	var n := state.rng.randi_range(int(dmg[0]), int(dmg[1]))
	var pct := 100
	var vs: Dictionary = d.get("vs", {})
	var tfam := String(type_def(String(target["t"])).get("family", target["t"]))
	pct = pct * int(vs.get(String(target["t"]), vs.get(tfam, 100))) / 100
	var eid0 := int(b["a"]) if side == 0 else int(b["d"])
	var fam := String(d.get("family", ""))
	if fam == "infanterie" and tfam == "aerien" and Research.fx_int(state, eid0, "inf_vs_air") > 0:
		pct = pct * Research.fx_int(state, eid0, "inf_vs_air") / 100
	# Terrain (prop. 14), tactiques (prop. 15), vétérance (prop. 16).
	var ter := terrain_def(String(b.get("ter", "")))
	pct = pct * int(ter.get("mods", {}).get(fam, 100)) / 100
	if side == 1:
		pct = pct * int(ter.get("defender", 100)) / 100
	var day := state.tick - int(b["land"]) + 1
	var mine_t := tactic_def("attack" if side == 0 else "defense", String(b.get("ta" if side == 0 else "td", "")))
	if int(mine_t.get("dmg_days", 0)) == 0 or day <= int(mine_t.get("dmg_days", 0)):
		pct = pct * (100 + int(mine_t.get("dmg_pct", 0))) / 100
	var their_t := tactic_def("defense" if side == 0 else "attack", String(b.get("td" if side == 0 else "ta", "")))
	pct = pct * (100 + int(their_t.get("taken_pct", 0))) / 100
	var ur: Dictionary = u.get("r", {})
	if not ur.is_empty():
		pct = pct * (100 + rank_pct(ur)) / 100
	# Régiments de peuple (prop. 9) : fanatiques chez eux, troupes de choc les premiers jours.
	if side == 1 and int(d.get("home_dmg_pct", 0)) > 0:
		pct = pct * int(d["home_dmg_pct"]) / 100
	if int(d.get("first_days_pct", 0)) > 0 and day <= int(d.get("first_days", 3)):
		pct = pct * (100 + int(d["first_days_pct"])) / 100
	pct += general_pct(state, eid0, int(b["s"]))
	var bc := _cfg("battle")
	if int(u["mo"]) * 2 < int(u["mm"]):
		pct = pct * int(bc.get("low_morale_pct", 75)) / 100
	if int(u["mo"]) <= 0:
		pct = pct * int(bc.get("broken_pct", 25)) / 100
	var sp := String(u.get("sp", ""))
	pct = pct * _species_pct(sp, "damage_pct") / 100
	pct = pct * _species_pct(sp, "ground_damage_pct") / 100
	var eid := int(b["a"]) if side == 0 else int(b["d"])
	pct += Research.fx_int(state, eid, "ground_damage_pct")
	@warning_ignore("integer_division")
	return maxi(1, n * maxi(10, pct) / 100)


static func _fight(state: GameState, b: Dictionary) -> void:
	var sid := int(b["s"])
	var a := int(b["a"])
	var d := int(b["d"])
	# La guerre est finie, ou le système a changé de mains autrement : on rentre.
	if not Combat.at_war(state, a, d) or WarPeace.holder(state, sid) != d:
		state.add_chronicle("La bataille au sol de %s s'achève sans vainqueur : %s et %s ne sont plus en guerre pour ce monde." % [_sys(state, sid), _name(state, a), _name(state, d)])
		_finish(state, b, -1, "peace")
		return
	if state.tick < int(b["land"]):
		return
	if not b.has("open"):
		_open(state, b)
	_note(b, state)
	_collateral(state, b)
	var width := front_width(state, sid)
	var sides := [_units(state, b, 0), _units(state, b, 1)]
	if (sides[1] as Array).is_empty():
		_end(state, b, a)
		return
	if (sides[0] as Array).is_empty():
		_end(state, b, d)
		return
	var fronts := [_front(sides[0], width), _front(sides[1], width)]
	var day := state.tick - int(b["land"]) + 1
	var hits := []  # [côté visé, indice dans le front, dégâts, tireur]
	for s in 2:
		var mine: Array[Dictionary] = fronts[s]
		var theirs: Array[Dictionary] = fronts[1 - s]
		for u in mine:
			var ti := _pick(state, theirs)
			hits.append([1 - s, ti, _damage(state, b, s, u, theirs[ti]), u])
	var shots: Array = b["shots"]
	var ux: Dictionary = b["ux"]
	var lost: Array = b["lost"]
	for h: Array in hits:
		var tu: Dictionary = fronts[int(h[0])][int(h[1])]
		var dmg := int(h[2])
		tu["hp"] = int(tu["hp"]) - dmg
		var src0: Dictionary = h[3]
		var mdmg := dmg * int(type_def(String(src0["t"])).get("morale_dmg_pct", 100)) / 100
		if not bool(type_def(String(tu["t"])).get("no_morale", false)):
			tu["mo"] = maxi(0, int(tu["mo"]) - mdmg)
		lost[int(h[0])] = int(lost[int(h[0])]) + dmg
		var src: Dictionary = h[3]
		if shots.size() < SHOTS_MAX:
			shots.append([day, int(ux.get(String(src["k"]), -1)), int(ux.get(String(tu["k"]), -1)), dmg, 1 if int(tu["hp"]) <= 0 and int(tu.get("dead", 0)) == 0 else 0])
		if int(tu["hp"]) <= 0 and int(tu.get("dead", 0)) == 0:
			tu["dead"] = 1
		var r: Dictionary = src.get("r", {})
		if not r.is_empty():
			r["xp"] = int(r.get("xp", 0)) + 2
	# Écrire les états : morts, blessés, débandés.
	var bc := _cfg("battle")
	var per_hp := maxi(1, int(bc.get("score_per_hp", 10)))
	for s in 2:
		for u: Dictionary in fronts[s]:
			var r: Dictionary = u["r"]
			if int(u["hp"]) <= 0:
				var winner := a if s == 1 else d
				var loser := d if s == 1 else a
				@warning_ignore("integer_division")
				Wars.on_battle(state, winner, loser, maxi(1, int(u["mh"]) / per_hp))
				if r.is_empty():
					b["mil"][int(u["mi"])] = [0, 0]
				else:
					state.ground["r"].erase(str(int(r["id"])))
			elif r.is_empty():
				b["mil"][int(u["mi"])] = [int(u["hp"]), int(u["mo"])]
			else:
				r["hp"] = int(u["hp"])
				r["mo"] = int(u["mo"])
	# Garnison du système : ce qui reste de la milice.
	var alive := 0
	for m: Array in b["mil"]:
		if int(m[0]) > 0:
			alive += 1
	state.garrisons[sid] = alive * int(bc.get("militia_per_unit", 15))
	if _units(state, b, 1).is_empty():
		_end(state, b, a)
	elif _units(state, b, 0).is_empty():
		_end(state, b, d)


## Premier jour de combat : tactiques (milice renforcée ou pilonnée, dévastation) et sabotage des commandos.
static func _open(state: GameState, b: Dictionary) -> void:
	b["open"] = 1
	var sid := int(b["s"])
	var ta := tactic_def("attack", String(b.get("ta", "")))
	var td := tactic_def("defense", String(b.get("td", "")))
	var mil: Array = b["mil"]
	var m := type_def("milice")
	# Résistance locale : plus de miliciens.
	var extra := int(td.get("militia_pct", 0))
	if extra > 0 and not mil.is_empty():
		@warning_ignore("integer_division")
		for i in maxi(1, mil.size() * extra / 100):
			mil.append([int(m.get("hp", 60)), int(m.get("morale", 120))])
	var cut := -int(ta.get("militia_pct", 0))
	var sc := _cfg("siege")
	var sab := 0
	for r in on_ground(state, sid, int(b["a"])):
		sab += int(type_def(String(r["t"])).get("abilities", {}).get("sabotage", 0))
	for r in on_ground(state, sid, int(b["d"])):
		sab -= int(type_def(String(r["t"])).get("abilities", {}).get("sabotage", 0))
	cut += clampi(sab, 0, int(sc.get("sabotage_max", 3))) * int(sc.get("sabotage_pct", 20))
	if cut > 0:
		for i in mil.size():
			@warning_ignore("integer_division")
			mil[i][0] = maxi(1, int(mil[i][0]) * maxi(0, 100 - cut) / 100)
	if int(ta.get("dev", 0)) > 0:
		GroundSiege.add_dev(state, sid, int(ta["dev"]))


## Dévastation des combats (prop. 21) : terrain et tactiques des deux camps.
static func _collateral(state: GameState, b: Dictionary) -> void:
	var pct := int(terrain_def(String(b.get("ter", ""))).get("collateral", 100))
	for side in ["attack", "defense"]:
		var t := tactic_def(side, String(b.get("ta" if side == "attack" else "td", "")))
		if t.has("collateral"):
			pct = pct * int(t["collateral"]) / 100
	var n := int(_cfg("devastation").get("battle_per_day", 1)) * pct
	@warning_ignore("integer_division")
	var whole := n / 100
	if state.rng.randi_range(1, 100) <= n % 100:
		whole += 1
	GroundSiege.add_dev(state, int(b["s"]), whole)


## Fin d'une bataille gagnée par winner.
static func _end(state: GameState, b: Dictionary, winner: int) -> void:
	var sid := int(b["s"])
	var a := int(b["a"])
	var d := int(b["d"])
	if winner == a:
		state.add_chronicle("%s emporte la bataille au sol de %s : les derniers défenseurs déposent les armes, le drapeau change de mât." % [_name(state, a), _sys(state, sid)])
		_finish(state, b, a, "won")
		# La prise : occupation (buts de guerre) ou conquête, comme l'ancienne invasion.
		if not WarPeace.invade(state, sid, a):
			Combat.capture_system(state, sid, a)
		state.garrisons.erase(sid)
	else:
		state.add_chronicle("%s repousse l'assaut de %s sur %s : les plages sont jonchées de péniches éventrées." % [_name(state, d), _name(state, a), _sys(state, sid)])
		_finish(state, b, d, "held")


## Archive le rapport et clôt la bataille.
static func _finish(state: GameState, b: Dictionary, winner: int, how: String) -> void:
	var sid := int(b["s"])
	var civ := GroundOccupation.civilians(state, b) if how != "peace" else 0
	if how == "won":
		GroundOccupation.loot(state, b)
	_general_after(state, b, winner, how)
	var rep := {"id": int(b["id"]), "s": sid, "a": int(b["a"]), "d": int(b["d"]), "st": int(b["st"]), "land": int(b["land"]), "civ": civ,
			"end": state.tick, "w": winner, "how": how, "units": (b["units"] as Array).duplicate(true),
			"shots": (b["shots"] as Array).duplicate(true), "lost": (b["lost"] as Array).duplicate(),
			"ter": String(b.get("ter", "")), "ta": String(b.get("ta", "")), "td": String(b.get("td", ""))}
	var reps: Array = _g(state)["rep"]
	reps.append(rep)
	var keep := int(_cfg("battle").get("report_keep", 12))
	while reps.size() > keep:
		reps.pop_front()
	state.ground["b"].erase(str(sid))
	if how != "won":
		# La milice survivante redevient la garnison.
		var alive := 0
		for m: Array in b["mil"]:
			if int(m[0]) > 0:
				alive += 1
		state.garrisons[sid] = alive * int(_cfg("battle").get("militia_per_unit", 15))
	if how == "peace":
		var home := FactionTraits.capital_system(state, int(b["a"]))
		for r in on_ground(state, sid, int(b["a"])):
			if home >= 0:
				r["s"] = home
			else:
				state.ground["r"].erase(str(int(r["id"])))


## Héros général (prop. 28) : les généraux de l'empire dont la flotte est à l'arrêt dans ce système.
static func generals_at(state: GameState, eid: int, sid: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if state.heroes.is_empty():
		return out
	var ids := state.heroes.keys()
	ids.sort()
	for id in ids:
		var h: Dictionary = state.heroes[id]
		if int(h["owner"]) != eid or String(h["post"]) != "army" or not Heroes.active(state, h):
			continue
		var f: Fleet = state.fleets.get(int(h["target"]))
		if f != null and not f.is_moving() and f.system_id == sid:
			out.append(h)
	return out


## Bonus de dégâts (%) des généraux présents.
static func general_pct(state: GameState, eid: int, sid: int) -> int:
	var pct := 0
	for h in generals_at(state, eid, sid):
		@warning_ignore("integer_division")
		pct += int(Heroes.data()["per_level"].get("army_damage_pct", 5)) * Heroes.half_levels(h, "army") / 2
		pct += Heroes.trait_fx(h, "ground_damage_pct")
	return pct


## Après la bataille : le général vainqueur gagne de l'expérience, le vaincu peut être pris.
static func _general_after(state: GameState, b: Dictionary, winner: int, how: String) -> void:
	var sid := int(b["s"])
	var a := int(b["a"])
	for h in generals_at(state, a, sid):
		if winner == a:
			Heroes.gain_xp(state, h, int(Heroes.data()["xp"].get("battle_won", 60)))
		elif how == "held" or how == "retreat":
			var out: Array[Dictionary] = []
			Heroes._wound(state, h, out, "défait au sol sur %s" % _sys(state, sid), int(b["d"]))


## Rapports de bataille au sol qu'un empire peut lire (les siens), du plus récent au plus ancien.
static func reports_for(state: GameState, eid: int) -> Array:
	var out := []
	var reps: Array = _g(state)["rep"]
	for i in range(reps.size() - 1, -1, -1):
		var r: Dictionary = reps[i]
		if eid < 0 or int(r["a"]) == eid or int(r["d"]) == eid:
			out.append(r)
	return out


static func report(state: GameState, rid: int) -> Dictionary:
	for r: Dictionary in _g(state)["rep"]:
		if int(r["id"]) == rid:
			return r
	return {}


## Ligne d'état d'une bataille en cours, pour l'interface.
static func battle_text(state: GameState, b: Dictionary) -> String:
	var sid := int(b["s"])
	var aa := strength(on_ground(state, sid, int(b["a"])))
	var dd := strength(on_ground(state, sid, int(b["d"])))
	var mil := 0
	for m: Array in b["mil"]:
		if int(m[0]) > 0:
			mil += 1
	if state.tick < int(b["land"]):
		return "%s : débarquement de %s (encore %d j)" % [_sys(state, sid), _name(state, int(b["a"])), int(b["land"]) - state.tick]
	return "%s : %s (%d rég., force %d) contre %s (%d rég. et %d milices, force %d), jour %d" % [
			_sys(state, sid), _name(state, int(b["a"])), on_ground(state, sid, int(b["a"])).size(), aa,
			_name(state, int(b["d"])), on_ground(state, sid, int(b["d"])).size(), mil, dd + militia_strength_from(b),
			state.tick - int(b["land"]) + 1]


static func militia_strength_from(b: Dictionary) -> int:
	var m := type_def("milice")
	var dm: Array = m.get("dmg", [3, 6])
	var n := 0
	for x: Array in b["mil"]:
		@warning_ignore("integer_division")
		n += int(x[0]) * (int(dm[0]) + int(dm[1])) / 20
	return n


# --- Ordres ----------------------------------------------------------------------------------------

static func check_act(state: GameState, eid: int, act: String, x: int, s: String, s2: String) -> String:
	if not full(state):
		return "les armées ne sont pas en jeu (combat au sol simplifié)"
	match act:
		"recruit":
			return check_recruit(state, eid, x, s, s2)
		"embark":
			return check_embark(state, eid, x)
		"disembark":
			return check_disembark(state, eid, x)
		"demob":
			return check_demobilize(state, eid, x)
		"retreat":
			return check_retreat(state, eid, x)
		"bomb":
			return GroundSiege.check_posture(state, eid, x, s)
		"sortie":
			return GroundSiege.check_sortie(state, eid, x)
		"tactic":
			return check_battle_tactic(state, eid, x, s)
		"default_tactic":
			return check_default_tactic(state, eid, s, s2)
		"hire":
			return GroundOccupation.check_hire(state, eid, x)
	return "ordre inconnu"


static func act(state: GameState, eid: int, what: String, x: int, s: String, s2: String) -> void:
	match what:
		"recruit":
			recruit(state, eid, x, s, s2)
		"embark":
			embark(state, eid, x)
		"disembark":
			disembark(state, eid, x)
		"demob":
			demobilize(state, eid, x)
		"retreat":
			retreat(state, eid, x)
		"bomb":
			GroundSiege.set_posture(state, x, s)
		"sortie":
			GroundSiege.sortie(state, eid, x)
		"tactic":
			set_battle_tactic(state, eid, x, s)
		"default_tactic":
			set_default_tactic(state, eid, s, s2)
		"hire":
			GroundOccupation.hire(state, eid, x)
