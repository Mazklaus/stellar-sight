class_name Megastructures
extends RefCounted
## Les mégastructures (étude du 2026-11-17, 46 propositions validées ; données : data/megastructures.json).
##
## Un pilier à part des merveilles (prop. 1) : la Sphère de Dyson, le Nexus du savoir et le Monde-anneau
## ont quitté data/wonders.json (les anciennes sauvegardes sont converties, voir migrate_wonders).
## Chaque mégastructure se pose sur un astre précis d'un système tenu (prop. 2) : l'étoile (p = -1),
## une planète, ou une colonie peuplée pour les petites. Un Vaisseau-architecte pose le Chantier
## (étape 0) et doit rester sur place jusqu'à ce qu'il tienne (prop. 3) ; les étapes suivantes se lancent
## une à une, payées au lancement (prop. 4), et l'empire n'en avance qu'un nombre limité à la fois
## (prop. 5 : rules.slots + effet « mega_slots » des technologies, de la cour et des talents).
##
## Réglage « Mégastructures » (prop. 45) : Complètes, Sans superarmes, Classiques (les trois anciennes),
## Désactivées (state.megas vide) ; ruines Aucune, Peu, Beaucoup. Sans l'option (tests, bancs) : désactivées.
##
## État : state.megas = {"mode", "ruins_opt", "next": prochain identifiant, "list": {"id": entrée},
##  "kard": {"eid": indice ×10}, "plans": {"flotte": {"k", "s", "p"}}, "st": {"eid": {statistiques}}}.
## Entrée : {"id", "k": type, "o": propriétaire (-1 = ruine sans maître), "s": système, "p": planète
##  (-1 = l'étoile), "st": étapes achevées (0 à n), "w": jours restants de l'étape en cours (0 = rien),
##  "f": Vaisseau-architecte du Chantier, "dmg": 1 si l'étape la plus haute est ruinée, "rp": 1 pendant
##  une réparation, "ruin": 1 pour une ruine, "rs": 1 pendant sa restauration, "mod": module, "wear":
##  usure en %, "cd": jour de fin de recharge, "sg": mois de siège, "wk": jours de point faible}.
## Tout est déterministe : entiers, tirages par hachage de la graine, ordres par SimCommands.

const SUBS := ["list", "kard", "plans", "st", "first"]


static func data() -> Dictionary:
	return GameData.megastructures()


static func cfg(section: String) -> Dictionary:
	var v: Variant = data().get(section, {})
	return v if v is Dictionary else {}


static func r_int(key: String, def := 0) -> int:
	return int(cfg("rules").get(key, def))


static func kinds() -> Dictionary:
	return cfg("kinds")


static func kind_ids() -> Array[String]:
	var out: Array[String] = []
	for k in kinds():
		out.append(String(k))
	return out


static func kind_def(k: String) -> Dictionary:
	var v: Variant = kinds().get(k, {})
	return v if v is Dictionary else {}


static func is_kind(k: String) -> bool:
	return kinds().has(k)


static func label(k: String) -> String:
	return String(kind_def(k).get("label", k))


static func stages(k: String) -> Array:
	return kind_def(k).get("stages", [])


static func stage_count(k: String) -> int:
	return stages(k).size()


static func stage_def(k: String, n: int) -> Dictionary:
	var sts := stages(k)
	return sts[n] if n >= 0 and n < sts.size() else {}


static func body(k: String) -> String:
	return String((kind_def(k).get("site", {}) as Dictionary).get("body", "star"))


static func mode_defs() -> Array:
	return data().get("modes", [])


static func default_mode() -> String:
	return String(data().get("default_mode", "completes"))


static func ruin_defs() -> Array:
	return data().get("ruin_opts", [])


static func default_ruins() -> String:
	return String(data().get("default_ruins", "peu"))


static func mode(state: GameState) -> String:
	return String(state.megas.get("mode", "desactivees"))


static func enabled(state: GameState) -> bool:
	return state != null and not state.megas.is_empty()


## Complètes ou Sans superarmes : ruines, trouvailles, événements et ponts en jeu.
static func full(state: GameState) -> bool:
	return enabled(state) and mode(state) != "classiques"


static func mode_label(state: GameState) -> String:
	for m: Dictionary in mode_defs():
		if String(m["id"]) == mode(state):
			return String(m["label"])
	return "Désactivées"


## Ce type est-il en jeu dans cette partie (réglage) ?
static func kind_allowed(state: GameState, k: String) -> bool:
	if not enabled(state) or not is_kind(k):
		return false
	var d := kind_def(k)
	match mode(state):
		"classiques":
			return bool(d.get("classic", false))
		"sans_armes":
			return not bool(d.get("weapon", false))
	return true


static func applies(state: GameState, eid: int) -> bool:
	var e := state.get_empire(eid) if enabled(state) and eid >= 0 else null
	return e != null and not e.is_npc() and not e.eliminated


# --- Réglage, sauvegarde -----------------------------------------------------------------------

static func setup(state: GameState, mode_id: String, ruins_id := "") -> void:
	state.megas = {}
	var ok := false
	for m: Dictionary in mode_defs():
		if String(m["id"]) == mode_id:
			ok = true
	if not ok or mode_id == "desactivees":
		return
	var ro := ruins_id
	var ro_ok := false
	for r: Dictionary in ruin_defs():
		if String(r["id"]) == ro:
			ro_ok = true
	if not ro_ok:
		ro = default_ruins()
	state.megas = {"mode": mode_id, "ruins_opt": ro, "next": 1}
	for k in SUBS:
		state.megas[k] = {}
	if full(state):
		MegasWorld.place_ruins(state)


static func worth_saving(state: GameState) -> bool:
	return enabled(state)


static func to_dict(state: GameState) -> Dictionary:
	return state.megas.duplicate(true)


static func from_dict(state: GameState, d: Dictionary) -> void:
	if d.is_empty():
		state.megas = {}
		return
	state.megas = GameData._to_ints(d.duplicate(true))
	for k in SUBS:
		if not state.megas.has(k):
			state.megas[k] = {}


static func sub(state: GameState, k: String) -> Dictionary:
	if state.megas.is_empty():
		return {}  # pilier désactivé : ne jamais le rallumer en écrivant
	if not state.megas.has(k):
		state.megas[k] = {}
	return state.megas[k]


static func _h(state: GameState, parts: Array) -> int:
	return absi(hash([state.seed_value, "mega"] + parts))


static func _stat(state: GameState, eid: int, k: String, n: int) -> void:
	if state.megas.is_empty() or eid < 0:
		return
	var st := sub(state, "st")
	var d: Dictionary = st.get(str(eid), {})
	d[k] = int(d.get(k, 0)) + n
	st[str(eid)] = d


static func stat(state: GameState, eid: int, k: String) -> int:
	return int((sub(state, "st").get(str(eid), {}) as Dictionary).get(k, 0))


static func touch(state: GameState) -> void:
	state.relic_rev += 1  # les effets (Research.effects) se recalculent


# --- Talents -----------------------------------------------------------------------------------

## Talent de mégastructures du peuple (prop. 40, data « talents » par peuple).
static func talent(state: GameState, eid: int) -> Dictionary:
	var e := state.get_empire(eid)
	if e == null or GameState.is_npc(eid):
		return {}
	var v: Variant = cfg("talents").get(Genetics.root(e.faction_id), null)
	return v if v is Dictionary else {}


static func t_int(state: GameState, eid: int, key: String) -> int:
	var v: Variant = talent(state, eid).get(key, 0)
	return int(v) if (v is int or v is float) else 0


# --- Entrées -----------------------------------------------------------------------------------

static func entries(state: GameState) -> Dictionary:
	return sub(state, "list")


static func get_m(state: GameState, id: int) -> Dictionary:
	var v: Variant = entries(state).get(str(id), {})
	return v if v is Dictionary else {}


## Identifiants triés (ordre déterministe).
static func ids(state: GameState) -> Array[int]:
	var out: Array[int] = []
	for k in entries(state):
		out.append(int(k))
	out.sort()
	return out


static func all_sorted(state: GameState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in ids(state):
		out.append(get_m(state, id))
	return out


static func owned_by(state: GameState, eid: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for m in all_sorted(state):
		if int(m["o"]) == eid:
			out.append(m)
	return out


static func in_system(state: GameState, sid: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for m in all_sorted(state):
		if int(m["s"]) == sid:
			out.append(m)
	return out


static func is_ruin(m: Dictionary) -> bool:
	return bool(m.get("ruin", 0))


## Étapes achevées qui comptent : une étape ruinée ne compte plus (prop. 32).
static func eff_stage(m: Dictionary) -> int:
	if m.is_empty() or is_ruin(m):
		return 0
	return maxi(0, int(m["st"]) - (1 if bool(m.get("dmg", 0)) else 0))


static func complete(m: Dictionary) -> bool:
	return not m.is_empty() and not is_ruin(m) and int(m["st"]) >= stage_count(String(m["k"])) and not bool(m.get("dmg", 0))


static func running(m: Dictionary) -> bool:
	return int(m.get("w", 0)) > 0


## Définition de l'étape la plus haute qui compte (vide s'il n'y en a pas).
static func top_def(m: Dictionary) -> Dictionary:
	var n := eff_stage(m)
	return stage_def(String(m["k"]), n - 1) if n > 0 else {}


static func special(m: Dictionary, key: String, def: Variant = null) -> Variant:
	return (top_def(m).get("special", {}) as Dictionary).get(key, def)


static func count_kind(state: GameState, eid: int, k: String) -> int:
	var n := 0
	for m in owned_by(state, eid):
		if String(m["k"]) == k:
			n += 1
	return n


static func complete_count(state: GameState, eid: int, k: String) -> int:
	var n := 0
	for m in owned_by(state, eid):
		if String(m["k"]) == k and complete(m):
			n += 1
	return n


static func at_star(state: GameState, sid: int, k := "") -> Dictionary:
	for m in in_system(state, sid):
		if int(m["p"]) == -1 and (k == "" or String(m["k"]) == k):
			return m
	return {}


## Premier empire à avoir achevé ce type (-1 si personne).
static func first_of(state: GameState, k: String) -> int:
	return int(sub(state, "first").get(k, -1))


static func site_name(state: GameState, m: Dictionary) -> String:
	var sid := int(m["s"])
	if int(m["p"]) < 0:
		return "l'étoile de %s" % state.galaxy.systems[sid].system_name
	return state.galaxy.get_planet(int(m["p"])).display_name(state.galaxy)


static func name_of(state: GameState, m: Dictionary) -> String:
	return "%s (%s)" % [label(String(m["k"])), site_name(state, m)]


# --- Chantiers : capacité, coûts, durées --------------------------------------------------------

## Étapes qu'un empire peut avancer à la fois (prop. 5, 41).
static func slots(state: GameState, eid: int) -> int:
	return r_int("slots", 1) + Research.fx_int(state, eid, "mega_slots") + t_int(state, eid, "slots") + MegasBridges.slots_bonus(state, eid)


static func busy(state: GameState, eid: int) -> int:
	var n := 0
	for m in owned_by(state, eid):
		if running(m):
			n += 1
	return n


static func unlocked(state: GameState, eid: int, k: String) -> bool:
	return Research.knows_all(state, eid, kind_def(k).get("tech", []))


## Pour cent de coût d'une étape (talents, Sphère posée sur un Essaim, ponts).
static func cost_pct(state: GameState, eid: int, k: String, sid := -1) -> int:
	var pct := 0
	if k == "monde_anneau":
		pct += t_int(state, eid, "ring_cost_pct")
	if k == "matriochka":
		pct += t_int(state, eid, "matriochka_cost_pct")
	if k == "sphere_dyson" and sid >= 0:
		var sw := at_star(state, sid, "essaim_dyson")
		if not sw.is_empty() and int(sw["o"]) == eid and complete(sw):
			pct -= 100 - int(kind_def(k).get("on_swarm_pct", 60))
	pct += MegasBridges.cost_pct(state, eid, k)
	pct += Research.fx_int(state, eid, "mega_cost_pct")  # Métier des Tisserands (archéologie)
	return pct


static func stage_cost(state: GameState, eid: int, k: String, n: int, sid := -1) -> Dictionary:
	return Research.scaled_amounts(stage_def(k, n).get("cost", {}), cost_pct(state, eid, k, sid))


## Pour cent de vitesse des étapes (talent, héros, ponts).
static func speed_pct(state: GameState, eid: int, sid := -1) -> int:
	return t_int(state, eid, "speed_pct") + MegasBridges.speed_pct(state, eid, sid)


@warning_ignore("integer_division")
static func stage_days(state: GameState, eid: int, k: String, n: int, sid := -1) -> int:
	return maxi(1, int(stage_def(k, n).get("days", 90)) * 100 / maxi(25, 100 + speed_pct(state, eid, sid)))


# --- Sites (prop. 2, 6) ------------------------------------------------------------------------

static func _holds(state: GameState, eid: int, sid: int) -> bool:
	if state.system_owner(sid) != eid:
		return false
	var occ := WarPeace.occupier(state, sid)
	if occ >= 0 and occ != eid:
		return false
	for pid in state.galaxy.systems[sid].planet_ids:
		var c: Colony = state.colonies.get(pid)
		if c != null and c.owner == eid and c.is_established():
			return true
	return false


## Raison pour laquelle l'empire ne peut pas poser ce type ici ("" = possible). pid = -1 : l'étoile.
## Ne regarde ni l'architecte, ni les ressources, ni la capacité (voir check_pose).
static func site_reason(state: GameState, eid: int, k: String, sid: int, pid: int) -> String:
	if not kind_allowed(state, k):
		return "pas en jeu dans cette partie"
	var d := kind_def(k)
	if bool(d.get("ruin_only", false)):
		return "ne se bâtit pas : on ne peut que relever une ruine"
	if not unlocked(state, eid, k):
		return "technologie requise : %s" % Research.missing_text(state, eid, d.get("tech", []))
	if sid < 0 or sid >= state.galaxy.systems.size():
		return "système inconnu"
	if not _holds(state, eid, sid):
		return "il faut tenir le système (une colonie ou un avant-poste établi, sans occupant)"
	var site: Dictionary = d.get("site", {})
	var s := state.galaxy.systems[sid]
	var b := String(site.get("body", "star"))
	if b == "star":
		if pid != -1:
			return "se pose autour de l'étoile"
		var allowed: Array = site.get("stars", [])
		if not allowed.is_empty() and not allowed.has(s.star_type):
			return "seulement autour d'une %s" % " ou ".join(PackedStringArray(allowed.map(func(x: Variant) -> String: return star_label(String(x)))))
		if (site.get("not_stars", []) as Array).has(s.star_type):
			return "impossible autour d'une %s" % star_label(s.star_type)
		var on := String(site.get("on_kind", ""))
		var here := at_star(state, sid)
		if on != "":
			var base := at_star(state, sid, on)
			if base.is_empty() or int(base["o"]) != eid or not complete(base):
				return "il faut ici votre %s achevée" % label(on)
			for m in in_system(state, sid):
				if String(m["k"]) == k:
					return "déjà là"
		elif not here.is_empty():
			var swarm_ok := k == "sphere_dyson" and String(here["k"]) == "essaim_dyson" and int(here["o"]) == eid and complete(here)
			if not swarm_ok:
				return "l'étoile porte déjà : %s" % label(String(here["k"]))
	else:
		if pid < 0 or not s.planet_ids.has(pid):
			return "choisissez une planète du système"
		var p := state.galaxy.get_planet(pid)
		var c: Colony = state.colonies.get(pid)
		if b == "colony":
			if c == null or c.owner != eid or not c.is_colony() or not c.is_established():
				return "seulement sur une de vos colonies peuplées"
			for m in in_system(state, sid):
				if int(m["p"]) == pid and String(m["k"]) == k:
					return "déjà sur cette colonie"
		else:
			var types: Array = site.get("planet_types", [])
			if not types.is_empty() and not types.has(p.type):
				return "seulement sur : %s" % ", ".join(PackedStringArray(types.map(func(x: Variant) -> String: return planet_label(String(x)))))
			if c != null and c.is_colony() and c.population > 0:
				return "pas sur une planète peuplée"
			for m in in_system(state, sid):
				if int(m["p"]) == pid:
					return "la planète porte déjà : %s" % label(String(m["k"]))
	if bool(site.get("no_foreign_pop", false)) or bool(site.get("no_pop", false)):
		for opid in s.planet_ids:
			var oc: Colony = state.colonies.get(opid)
			if oc != null and oc.is_colony() and oc.population > 0 and (bool(site.get("no_pop", false)) or oc.owner != eid):
				return "impossible : un monde du système est peuplé" if bool(site.get("no_pop", false)) else "impossible : un peuple étranger vit dans ce système"
	var lim: Dictionary = d.get("limit", {})
	if lim.has("empire") and count_kind(state, eid, k) >= int(lim["empire"]):
		return "limite atteinte : %d par empire" % int(lim["empire"])
	if lim.has("per_system"):
		for m in in_system(state, sid):
			if String(m["k"]) == k:
				return "déjà une dans ce système"
	var w := MegasBridges.site_reason(state, eid, k, sid, pid)
	if w != "":
		return w
	return ""


## Tous les sites possibles d'un type pour un empire : [[système, planète], …] (prop. 3 « Trouver un site »).
static func sites(state: GameState, eid: int, k: String, max_n := 99) -> Array:
	var out: Array = []
	if not kind_allowed(state, k) or not unlocked(state, eid, k):
		return out
	var b := body(k)
	var seen := {}
	var sys_ids: Array[int] = []
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner != eid:
			continue
		var sid := state.galaxy.get_planet(pid).system_id
		if not seen.has(sid):
			seen[sid] = true
			sys_ids.append(sid)
	sys_ids.sort()
	for sid in sys_ids:
		if b == "star":
			if site_reason(state, eid, k, sid, -1) == "":
				out.append([sid, -1])
		else:
			for pid in state.galaxy.systems[sid].planet_ids:
				if site_reason(state, eid, k, sid, pid) == "":
					out.append([sid, pid])
		if out.size() >= max_n:
			break
	return out


static func star_label(st: String) -> String:
	return String(cfg("star_labels").get(st, st))


static func planet_label(t: String) -> String:
	var d: Dictionary = GameData.planet_types().get(t, {}) if GameData.planet_types() is Dictionary else {}
	return String(d.get("label", t)).to_lower()


# --- Vaisseau-architecte (prop. 3) ---------------------------------------------------------------

static func ship_id() -> String:
	return String(cfg("rules").get("ship", "architecte"))


static func is_architect_fleet(f: Fleet) -> bool:
	if f == null:
		return false
	for s in f.ships:
		if GameData.ship(s).get("architect", false):
			return true
	return false


## Flottes d'architectes d'un empire dans un système, à l'arrêt (triées par identifiant).
static func architects_at(state: GameState, eid: int, sid: int) -> Array[Fleet]:
	var out: Array[Fleet] = []
	for fid in state.sorted_fleet_ids():
		var f: Fleet = state.fleets[fid]
		if f.owner == eid and f.system_id == sid and not f.is_moving() and is_architect_fleet(f):
			out.append(f)
	return out


static func architects_of(state: GameState, eid: int) -> Array[Fleet]:
	var out: Array[Fleet] = []
	for fid in state.sorted_fleet_ids():
		var f: Fleet = state.fleets[fid]
		if f.owner == eid and is_architect_fleet(f):
			out.append(f)
	return out


## L'architecte est-il retenu par un Chantier ou un ordre ?
static func architect_busy(state: GameState, f: Fleet) -> bool:
	for m in all_sorted(state):
		if int(m.get("f", -1)) == f.id and int(m["st"]) == 0:
			return true
	return sub(state, "plans").has(str(f.id))


# --- Ordres ------------------------------------------------------------------------------------

## Ordres (SimCommands.mega_act) : "plan" (k, s, p, f?), "pose" (f, k, p), "advance" (id), "repair" (id),
## "restore" (id), "cancel" (id), "module" (id, m), "launch" (id, f, t), "fire" (id, t), "purge" (id),
## et ceux des ponts (MegasBridges).
static func check(state: GameState, eid: int, act: String, d: Dictionary) -> String:
	if not applies(state, eid):
		return "les mégastructures ne sont pas en jeu"
	match act:
		"plan":
			return check_plan(state, eid, String(d.get("k", "")), int(d.get("s", -1)), int(d.get("p", -1)), int(d.get("f", -1)))
		"pose":
			return check_pose(state, eid, int(d.get("f", -1)), String(d.get("k", "")), int(d.get("p", -1)))
		"advance":
			return check_advance(state, eid, int(d.get("id", -1)))
		"repair":
			return check_repair(state, eid, int(d.get("id", -1)))
		"restore":
			return MegasWorld.check_restore(state, eid, int(d.get("id", -1)))
		"cancel":
			return check_cancel(state, eid, int(d.get("id", -1)))
		"module":
			return check_module(state, eid, int(d.get("id", -1)), String(d.get("m", "")))
		"launch":
			return MegasWorld.check_launch(state, eid, int(d.get("id", -1)), int(d.get("f", -1)), int(d.get("t", -1)))
		"fire":
			return MegasWorld.check_fire(state, eid, int(d.get("id", -1)), int(d.get("t", -1)))
		"purge":
			return MegasWorld.check_purge(state, eid, int(d.get("id", -1)))
	return MegasBridges.check(state, eid, act, d)


static func apply(state: GameState, eid: int, act: String, d: Dictionary) -> Array[Dictionary]:
	var added: Array[Dictionary] = []
	match act:
		"plan":
			plan(state, eid, String(d["k"]), int(d["s"]), int(d.get("p", -1)), int(d.get("f", -1)), added)
		"pose":
			pose(state, eid, int(d["f"]), String(d["k"]), int(d.get("p", -1)), added)
		"advance":
			advance(state, eid, int(d["id"]), added)
		"repair":
			repair(state, eid, int(d["id"]), added)
		"restore":
			MegasWorld.restore(state, eid, int(d["id"]), added)
		"cancel":
			cancel(state, eid, int(d["id"]), added)
		"module":
			set_module(state, eid, int(d["id"]), String(d["m"]), added)
		"launch":
			MegasWorld.launch(state, eid, int(d["id"]), int(d["f"]), int(d["t"]), added)
		"fire":
			MegasWorld.fire(state, eid, int(d["id"]), int(d["t"]), added)
		"purge":
			MegasWorld.purge(state, eid, int(d["id"]), added)
		_:
			MegasBridges.apply(state, eid, act, d, added)
	return added


static func _free_architect(state: GameState, eid: int, sid: int) -> Fleet:
	for f in architects_at(state, eid, sid):
		if not architect_busy(state, f):
			return f
	return null


## Envoyer un architecte vers un site : il y posera le Chantier en arrivant (prop. 3).
static func check_plan(state: GameState, eid: int, k: String, sid: int, pid: int, fid := -1) -> String:
	var why := site_reason(state, eid, k, sid, pid)
	if why != "":
		return why
	var f := _plan_fleet(state, eid, sid, fid)
	if f == null:
		return "aucun Vaisseau-architecte libre (construisez-en un dans un chantier spatial)"
	if Fleets.plan_route(state, f, sid).is_empty() and f.system_id != sid:
		return "aucune route connue jusque-là"
	return ""


static func _plan_fleet(state: GameState, eid: int, sid: int, fid: int) -> Fleet:
	if fid >= 0:
		var f: Fleet = state.fleets.get(fid)
		if f == null or f.owner != eid or not is_architect_fleet(f) or architect_busy(state, f):
			return null
		return f
	var best: Fleet = null
	var best_d := 1 << 30
	var j := FactionTraits.jumps_from(state.galaxy, sid)
	for f in architects_of(state, eid):
		if architect_busy(state, f):
			continue
		var dd := int(j.get(f.system_id, 999))
		if dd < best_d:
			best_d = dd
			best = f
	return best


static func plan(state: GameState, eid: int, k: String, sid: int, pid: int, fid: int, added: Array[Dictionary]) -> void:
	var f := _plan_fleet(state, eid, sid, fid)
	if f == null:
		return
	sub(state, "plans")[str(f.id)] = {"k": k, "s": sid, "p": pid}
	if f.system_id != sid:
		var r := Fleets.plan_route(state, f, sid)
		f.standing_order = ""
		f.system_id = int(r["system"])
		f.path.assign(r["path"])
		f.progress = int(r["progress"])
	_try_plan(state, f, added)


## Poser le Chantier (étape 0) avec un architecte présent.
static func check_pose(state: GameState, eid: int, fid: int, k: String, pid: int) -> String:
	var f: Fleet = state.fleets.get(fid)
	if f == null or f.owner != eid or not is_architect_fleet(f):
		return "il faut un Vaisseau-architecte"
	if f.is_moving():
		return "l'architecte doit être à l'arrêt dans le système"
	var why := site_reason(state, eid, k, f.system_id, pid)
	if why != "":
		return why
	if busy(state, eid) >= slots(state, eid):
		return "trop d'étapes en chantier (%d à la fois)" % slots(state, eid)
	var e := state.get_empire(eid)
	var cost := stage_cost(state, eid, k, 0, f.system_id)
	if not Economy.can_afford(e, cost):
		return "il faut %s" % GameData.format_amounts(cost)
	return ""


static func pose(state: GameState, eid: int, fid: int, k: String, pid: int, added: Array[Dictionary]) -> void:
	var f: Fleet = state.fleets[fid]
	var sid := f.system_id
	var e := state.get_empire(eid)
	Economy.pay(e, stage_cost(state, eid, k, 0, sid))
	var id := int(state.megas.get("next", 1))
	state.megas["next"] = id + 1
	var m := {"id": id, "k": k, "o": eid, "s": sid, "p": pid, "st": 0, "w": stage_days(state, eid, k, 0, sid), "f": fid}
	# Sphère sur un Essaim achevé : l'Essaim est absorbé (prop. 11).
	if k == "sphere_dyson":
		var sw := at_star(state, sid, "essaim_dyson")
		if not sw.is_empty():
			entries(state).erase(str(int(sw["id"])))
	entries(state)[str(id)] = m
	sub(state, "plans").erase(str(fid))
	_stat(state, eid, "posed", 1)
	touch(state)
	added.append(state.add_chronicle("%s pose le chantier d'un(e) %s sur %s. Les géomètres plantent leurs jalons ; l'architecte reste jusqu'à ce que ça tienne." % [
			e.short_name(), label(k), site_name(state, m)], _who(state, eid, sid, k)))
	MegasBridges.on_pose(state, m, added)


## Qui voit la nouvelle : tout le monde pour une grande mégastructure achevée, sinon le réseau
## habituel ; les Murmurants cachent leurs chantiers (prop. 40).
static func _who(state: GameState, eid: int, sid: int, _k := "", public := false) -> Variant:
	if bool(talent(state, eid).get("hidden", false)) and not public:
		return [eid]
	return null if public else Espionage.private_to(state, [eid], sid)


## Lancer l'étape suivante (payée au lancement, prop. 4).
static func check_advance(state: GameState, eid: int, id: int) -> String:
	var m := get_m(state, id)
	if m.is_empty() or int(m["o"]) != eid:
		return "ce n'est pas votre mégastructure"
	if is_ruin(m):
		return "c'est une ruine : relevez-la d'abord"
	if running(m):
		return "une étape est déjà en cours"
	if bool(m.get("dmg", 0)):
		return "réparez d'abord l'étape ruinée"
	var k := String(m["k"])
	var n := int(m["st"])
	if n >= stage_count(k):
		return "déjà achevée"
	if not unlocked(state, eid, k):
		return "technologie requise pour l'étendre : %s" % Research.missing_text(state, eid, kind_def(k).get("tech", []))
	if not kind_allowed(state, k):
		return "pas en jeu dans cette partie"
	var occ := WarPeace.occupier(state, int(m["s"]))
	if occ >= 0 and occ != eid:
		return "le système est occupé"
	if busy(state, eid) >= slots(state, eid):
		return "trop d'étapes en chantier (%d à la fois)" % slots(state, eid)
	var w := MegasBridges.advance_reason(state, eid, m)
	if w != "":
		return w
	var cost := stage_cost(state, eid, k, n, int(m["s"]))
	if not Economy.can_afford(state.get_empire(eid), cost):
		return "il faut %s" % GameData.format_amounts(cost)
	return ""


static func advance(state: GameState, eid: int, id: int, added: Array[Dictionary]) -> void:
	var m := get_m(state, id)
	var k := String(m["k"])
	var n := int(m["st"])
	Economy.pay(state.get_empire(eid), stage_cost(state, eid, k, n, int(m["s"])))
	m["w"] = stage_days(state, eid, k, n, int(m["s"]))
	added.append(state.add_chronicle("%s lance l'étape « %s » de son %s." % [state.get_empire(eid).short_name(), String(stage_def(k, n).get("label", "")), name_of(state, m)],
			_who(state, eid, int(m["s"]), k)))


## Réparer l'étape ruinée : la moitié de son coût (prop. 32).
static func repair_cost(state: GameState, eid: int, m: Dictionary) -> Dictionary:
	var k := String(m["k"])
	return Research.scaled_amounts(stage_cost(state, eid, k, maxi(0, int(m["st"]) - 1), int(m["s"])), r_int("repair_pct", 50) - 100)


static func check_repair(state: GameState, eid: int, id: int) -> String:
	var m := get_m(state, id)
	if m.is_empty() or int(m["o"]) != eid:
		return "ce n'est pas votre mégastructure"
	if not bool(m.get("dmg", 0)):
		return "rien à réparer"
	if running(m):
		return "déjà en chantier"
	if not unlocked(state, eid, String(m["k"])):
		return "technologie requise pour la réparer : %s" % Research.missing_text(state, eid, kind_def(String(m["k"])).get("tech", []))
	var occ := WarPeace.occupier(state, int(m["s"]))
	if occ >= 0 and occ != eid:
		return "le système est occupé"
	if busy(state, eid) >= slots(state, eid):
		return "trop d'étapes en chantier (%d à la fois)" % slots(state, eid)
	var cost := repair_cost(state, eid, m)
	if not Economy.can_afford(state.get_empire(eid), cost):
		return "il faut %s" % GameData.format_amounts(cost)
	return ""


@warning_ignore("integer_division")
static func repair(state: GameState, eid: int, id: int, added: Array[Dictionary]) -> void:
	var m := get_m(state, id)
	Economy.pay(state.get_empire(eid), repair_cost(state, eid, m))
	m["w"] = maxi(1, stage_days(state, eid, String(m["k"]), maxi(0, int(m["st"]) - 1), int(m["s"])) / 2)
	m["rp"] = 1
	added.append(state.add_chronicle("%s répare son %s." % [state.get_empire(eid).short_name(), name_of(state, m)], _who(state, eid, int(m["s"]))))


## Abandonner un Chantier pas encore tenu : la moitié du coût revient.
static func check_cancel(state: GameState, eid: int, id: int) -> String:
	var m := get_m(state, id)
	if m.is_empty() or int(m["o"]) != eid:
		return "ce n'est pas votre mégastructure"
	if int(m["st"]) > 0 or is_ruin(m):
		return "seul un Chantier qui ne tient pas encore s'abandonne"
	return ""


@warning_ignore("integer_division")
static func cancel(state: GameState, eid: int, id: int, added: Array[Dictionary]) -> void:
	var m := get_m(state, id)
	var back := Research.scaled_amounts(stage_cost(state, eid, String(m["k"]), 0, int(m["s"])), r_int("cancel_refund_pct", 50) - 100)
	var e := state.get_empire(eid)
	for r in back:
		e.resources[r] = int(e.resources.get(r, 0)) + int(back[r])
	entries(state).erase(str(id))
	touch(state)
	added.append(state.add_chronicle("%s abandonne le chantier de %s. Les jalons restent plantés, pour les archéologues." % [e.short_name(), name_of(state, m)], [eid]))


## Module de l'Anneau orbital (prop. 16).
static func check_module(state: GameState, eid: int, id: int, mod: String) -> String:
	var m := get_m(state, id)
	if m.is_empty() or int(m["o"]) != eid:
		return "ce n'est pas votre mégastructure"
	if not (kind_def(String(m["k"])).get("modules", {}) as Dictionary).has(mod):
		return "module inconnu"
	if not bool(special(m, "module", false)):
		return "l'anneau doit être achevé"
	if String(m.get("mod", "")) == mod:
		return "déjà ce module"
	return ""


static func set_module(state: GameState, eid: int, id: int, mod: String, added: Array[Dictionary]) -> void:
	var m := get_m(state, id)
	m["mod"] = mod
	touch(state)
	var md: Dictionary = (kind_def(String(m["k"])).get("modules", {}) as Dictionary).get(mod, {})
	added.append(state.add_chronicle("%s équipe son %s : %s." % [state.get_empire(eid).short_name(), name_of(state, m), String(md.get("label", mod)).to_lower()], [eid]))


# --- Chaque jour : chantiers, ordres d'architectes ----------------------------------------------

static func daily(state: GameState) -> Array[Dictionary]:
	var added: Array[Dictionary] = []
	if state.megas.is_empty():
		return added
	# Ordres d'architectes arrivés à destination.
	var pk := sub(state, "plans").keys()
	pk.sort()
	for k in pk:
		var f: Fleet = state.fleets.get(int(k))
		if f == null:
			sub(state, "plans").erase(k)
			continue
		_try_plan(state, f, added)
	for id in ids(state):
		var m := get_m(state, id)
		if m.is_empty() or not running(m):
			continue
		_work(state, m, added)
	MegasWorld.daily(state, added)
	return added


static func _try_plan(state: GameState, f: Fleet, added: Array[Dictionary]) -> void:
	var pl: Dictionary = sub(state, "plans").get(str(f.id), {})
	if pl.is_empty() or f.is_moving() or f.system_id != int(pl["s"]):
		return
	var why := check_pose(state, f.owner, f.id, String(pl["k"]), int(pl["p"]))
	if why == "":
		pose(state, f.owner, f.id, String(pl["k"]), int(pl["p"]), added)
	elif not why.begins_with("il faut ") and not why.begins_with("trop d'étapes"):
		sub(state, "plans").erase(str(f.id))
		added.append(state.add_chronicle("%s : l'architecte renonce à poser %s ici (%s)." % [state.get_empire(f.owner).short_name(), label(String(pl["k"])), why], [f.owner]))


static func _work(state: GameState, m: Dictionary, added: Array[Dictionary]) -> void:
	var eid := int(m["o"])
	var e := state.get_empire(eid)
	if e == null or e.eliminated:
		return
	if e.blackout:
		return
	var sid := int(m["s"])
	var occ := WarPeace.occupier(state, sid)
	if occ >= 0 and occ != eid:
		return  # chantier bloqué pendant l'occupation
	if int(m["st"]) == 0 and not is_ruin(m):
		var f: Fleet = state.fleets.get(int(m.get("f", -1)))
		if f == null or f.system_id != sid or f.is_moving() or not is_architect_fleet(f):
			var other := _free_architect(state, eid, sid)
			if other == null:
				return  # sans architecte sur place, le Chantier ne tient pas : il attend
			m["f"] = other.id
	m["w"] = int(m["w"]) - 1
	if int(m["w"]) > 0:
		return
	m["w"] = 0
	if bool(m.get("rs", 0)):
		MegasWorld.restored(state, m, added)
		return
	if bool(m.get("rp", 0)):
		m.erase("rp")
		m.erase("dmg")
		touch(state)
		added.append(state.add_chronicle("%s : %s est réparé." % [e.short_name(), name_of(state, m)], _who(state, eid, sid)))
		return
	finish_stage(state, m, added)


## Une étape s'achève : effets d'étape (segments, gel, absorption), chronique, hauts faits.
static func finish_stage(state: GameState, m: Dictionary, added: Array[Dictionary]) -> void:
	var eid := int(m["o"])
	var k := String(m["k"])
	var n := int(m["st"])
	m["st"] = n + 1
	if n == 0:
		m.erase("f")
	touch(state)
	var sd := stage_def(k, n)
	var sp: Dictionary = sd.get("special", {})
	if bool(sp.get("ring", false)):
		_ring_segment(state, m, added)
	if bool(sp.get("absorb", false)):
		_ring_absorb(state, m)
	if bool(sp.get("freeze", false)):
		_freeze(state, m, added)
	var e := state.get_empire(eid)
	if complete(m):
		_stat(state, eid, "done", 1)
		var first := sub(state, "first")
		var pub := int(kind_def(k).get("era", 1)) >= 4
		if not first.has(k):
			first[k] = eid
		Announce.next(state, "mega_done", {"actor": eid, "system": int(m["s"])})
		added.append(state.add_chronicle("%s achève son %s : « %s »" % [e.short_name(), name_of(state, m), String(kind_def(k).get("quote", ""))],
				_who(state, eid, int(m["s"]), k, pub)))
		MegasBridges.on_complete(state, m, added)
	elif n == 0:
		added.append(state.add_chronicle("%s : le chantier de %s tient debout. L'architecte peut repartir." % [e.short_name(), name_of(state, m)], _who(state, eid, int(m["s"]), k)))
	else:
		added.append(state.add_chronicle("%s : étape « %s » achevée pour %s." % [e.short_name(), String(sd.get("label", "")), name_of(state, m)], _who(state, eid, int(m["s"]), k)))


## Monde-anneau : une planète du système devient un segment d'anneau (prop. 14).
static func _ring_segment(state: GameState, m: Dictionary, added: Array[Dictionary]) -> void:
	var sid := int(m["s"])
	var eid := int(m["o"])
	var best := -1
	for pid in state.galaxy.systems[sid].planet_ids:
		var p := state.galaxy.get_planet(pid)
		if p.type == "anneau":
			continue
		var c: Colony = state.colonies.get(pid)
		if c != null and c.owner != eid:
			continue
		best = pid
		break
	if best < 0:
		return
	state.override_planet(best, {"type": "anneau"})
	var e := state.get_empire(eid)
	if e != null:
		e.hab_cache.clear()
	added.append(state.add_chronicle("%s : un segment d'anneau se referme autour de %s. Il y a de la place pour tout le monde, et de la vue." % [
			e.short_name(), state.galaxy.systems[sid].system_name], _who(state, eid, sid)))


## Anneau fermé : les planètes libres restantes sont reprises par l'anneau (ceinture de matière).
static func _ring_absorb(state: GameState, m: Dictionary) -> void:
	for pid in state.galaxy.systems[int(m["s"])].planet_ids:
		var p := state.galaxy.get_planet(pid)
		if p.type == "anneau" or p.type == "asteroids" or state.colonies.has(pid):
			continue
		state.override_planet(pid, {"type": "asteroids"})


## Sphère achevée : les planètes rocheuses du système gèlent (prop. 11, Stellaris).
static func _freeze(state: GameState, m: Dictionary, added: Array[Dictionary]) -> void:
	var sid := int(m["s"])
	var n := 0
	for pid in state.galaxy.systems[sid].planet_ids:
		var p := state.galaxy.get_planet(pid)
		if ["gas_giant", "asteroids", "anneau", "barren", "arctic"].has(p.type):
			continue
		var c: Colony = state.colonies.get(pid)
		state.override_planet(pid, {"type": "arctic" if (c != null and c.is_colony()) else "barren"})
		n += 1
	for e in state.empires:
		e.hab_cache.clear()
	if n > 0:
		added.append(state.add_chronicle("Nuit éternelle sur %s : la Sphère s'est refermée, %d monde%s gèle%s. Les météorologues ont enfin une prévision fiable." % [
				state.galaxy.systems[sid].system_name, n, "s" if n > 1 else "", "nt" if n > 1 else ""], _who(state, int(m["o"]), sid)))


# --- Effets : ressources, technologies ----------------------------------------------------------

## Multiplicateur de l'étoile en pour cent (prop. 10, GalCiv IV : la couleur de l'étoile compte).
static func star_pct(state: GameState, m: Dictionary) -> int:
	if not bool(kind_def(String(m["k"])).get("star_mult", false)):
		return 100
	return int(cfg("stars").get(state.galaxy.systems[int(m["s"])].star_type, 100))


## Rendement mensuel d'une mégastructure (étape qui compte, étoile, usure, Matriochka).
@warning_ignore("integer_division")
static func yields_of(state: GameState, m: Dictionary) -> Dictionary:
	var out := {}
	var td := top_def(m)
	if td.is_empty():
		return out
	var y: Dictionary = td.get("yields", {})
	var k := String(m["k"])
	var pct := star_pct(state, m) * (100 - int(m.get("wear", 0))) / 100
	if k == "matriochka":
		pct = 100 + t_int(state, int(m["o"]), "matriochka_pct")
	pct = pct * (100 - MegasBridges.company_share(state, m)) / 100  # part de la compagnie qui a financé
	for r in y:
		out[r] = int(y[r]) * pct / 100
	# Le Cerveau Matriochka mange l'énergie de sa Sphère (prop. 12).
	if k == "sphere_dyson":
		var mat := {}
		for o in in_system(state, int(m["s"])):
			if String(o["k"]) == "matriochka" and eff_stage(o) > 0:
				mat = o
		if not mat.is_empty():
			out.erase("energy")
	if k == "monde_anneau":
		var ri := t_int(state, int(m["o"]), "ring_influence")
		if ri > 0:
			out["influence"] = int(out.get("influence", 0)) + ri * maxi(0, eff_stage(m) - 1)
	return out


## Revenus des mégastructures d'un empire : {"gross": {}, "upkeep": {}} (Economy.empire_income).
static func income(state: GameState, eid: int) -> Dictionary:
	var gross := {}
	var upkeep := {}
	if state.megas.is_empty():
		return {"gross": gross, "upkeep": upkeep}
	for m in owned_by(state, eid):
		if is_ruin(m):
			continue
		var y := yields_of(state, m)
		for r in y:
			gross[r] = int(gross.get(r, 0)) + int(y[r])
		if eff_stage(m) > 1:
			var u: Dictionary = kind_def(String(m["k"])).get("upkeep", {})
			for r in u:
				upkeep[r] = int(upkeep.get(r, 0)) + int(u[r])
	return {"gross": gross, "upkeep": upkeep}


## Effets pour Research.effects (même empreinte relic_rev) : fx des étapes, plafonnés par type,
## nébuleuse et talents, palier de Kardashev.
@warning_ignore("integer_division")
static func effects(state: GameState, eid: int) -> Dictionary:
	var out := {}
	if state.megas.is_empty() or eid < 0 or GameState.is_npc(eid):
		return out
	var per_kind := {}
	for m in owned_by(state, eid):
		var td := top_def(m)
		if td.is_empty():
			continue
		var fx: Dictionary = td.get("fx", {})
		var k := String(m["k"])
		var x := 100
		if k == "oeuvre_monumentale":
			if Terrain.zone(state, int(m["s"])) == "nebula":
				x = int(kind_def(k).get("nebula_pct", 150))
			x *= maxi(1, t_int(state, eid, "oeuvre_x"))
		if k == "forum_interstellaire":
			x += t_int(state, eid, "forum_pct")
		var pk: Dictionary = per_kind.get(k, {})
		for key in fx:
			pk[key] = int(pk.get(key, 0)) + int(fx[key]) * x / 100
		per_kind[k] = pk
	for k in per_kind:
		var cap: Dictionary = kind_def(String(k)).get("fx_cap", {})
		var pk: Dictionary = per_kind[k]
		for key in pk:
			var v := int(pk[key])
			if cap.has(key):
				var c := int(cap[key])
				v = maxi(v, c) if c < 0 else mini(v, c)
			out[key] = int(out.get(key, 0)) + v
	var kt := kardashev_tier(state, eid)
	var cp: Array = cfg("kardashev").get("culture_pct", [])
	if kt > 0 and kt < cp.size() and int(cp[kt]) != 0:
		out["culture_pct"] = int(out.get("culture_pct", 0)) + int(cp[kt])
	return out


static func fx_text(fx: Dictionary) -> String:
	var parts := PackedStringArray()
	var names := {"ship_cost_pct": "coût des vaisseaux %+d %%", "building_cost_pct": "coût des bâtiments %+d %%", "trade_income_pct": "commerce %+d %%",
		"ship_days_pct": "durée des vaisseaux %+d %%", "titan_days_pct": "durée des titans %+d %%", "first_day_damage_pct": "dégâts du premier jour %+d %%",
		"detect": "détection %+d", "mega_voix_pct": "voix amphictyoniques %+d %%", "opinion_all": "opinion de tous %+d", "stability": "stabilité %+d",
		"culture_pct": "Rayonnement %+d %%", "supply_range": "ravitaillement %+d saut(s)", "fleet_speed_pct": "vitesse des flottes %+d %%",
		"defense_capacity": "places de défense %+d", "repair_pct": "réparations %+d %%", "damage_pct": "dégâts %+d %%", "home_damage_pct": "dégâts chez soi %+d %%"}
	for k in fx:
		parts.append(String(names.get(k, String(k) + " %+d")) % int(fx[k]))
	return ", ".join(parts)


# --- Branchements dans les autres systèmes -------------------------------------------------------

## Places de défense en plus dans un système (Anneau orbital, module Batteries), pour Defenses.capacity.
static func capacity_bonus(state: GameState, sid: int, owner: int) -> int:
	if state.megas.is_empty():
		return 0
	var n := 0
	for m in in_system(state, sid):
		if int(m["o"]) != owner:
			continue
		n += int(special(m, "capacity", 0))
		if String(m.get("mod", "")) != "" and complete(m):
			n += int(((kind_def(String(m["k"])).get("module_fx", {}) as Dictionary).get(String(m["mod"]), {}) as Dictionary).get("capacity", 0))
	return n


## Population maximale en plus sur une colonie (module Habitation de l'Anneau orbital).
static func pop_bonus(state: GameState, pid: int, owner: int) -> int:
	if state.megas.is_empty() or pid < 0:
		return 0
	var n := 0
	var sid := state.galaxy.get_planet(pid).system_id
	for m in in_system(state, sid):
		if int(m["p"]) == pid and int(m["o"]) == owner and complete(m) and String(m.get("mod", "")) != "":
			n += int(((kind_def(String(m["k"])).get("module_fx", {}) as Dictionary).get(String(m["mod"]), {}) as Dictionary).get("pop", 0))
	return n


## Jours de chantier spatial gagnés par jour sur cette colonie (module Chantier naval).
static func ship_bonus(state: GameState, c: Colony) -> int:
	if state.megas.is_empty():
		return 0
	var sid := state.galaxy.get_planet(c.planet_id).system_id
	for m in in_system(state, sid):
		if int(m["p"]) == c.planet_id and int(m["o"]) == c.owner and complete(m) and String(m.get("mod", "")) != "":
			return int(((kind_def(String(m["k"])).get("module_fx", {}) as Dictionary).get(String(m["mod"]), {}) as Dictionary).get("ship_speed", 0))
	return 0


## Siphon de géante achevé : dépôt de ravitaillement (Logistics.has_depot).
static func depot_at(state: GameState, sid: int, holder: int) -> bool:
	if state.megas.is_empty() or holder < 0:
		return false
	for m in in_system(state, sid):
		if int(m["o"]) == holder and bool(special(m, "depot", false)):
			return true
	return false


## Réseau de veille : sources de vision (Fleets.visible_systems) ; 99 = toute la galaxie.
static func vision(state: GameState, eid: int, sources: Dictionary) -> void:
	if state.megas.is_empty():
		return
	for m in owned_by(state, eid):
		var r := int(special(m, "vision", 0))
		if r <= 0 or r >= 99:
			continue
		var sid := int(m["s"])
		if int(sources.get(sid, -1)) < r:
			sources[sid] = r


static func see_all(state: GameState, eid: int, seen: Dictionary) -> void:
	if state.megas.is_empty():
		return
	for m in owned_by(state, eid):
		if int(special(m, "vision", 0)) >= 99:
			for s in state.galaxy.systems:
				seen[s.id] = true
			return


## Voix amphictyoniques en plus (Forum interstellaire), en pour cent.
static func voix_pct(state: GameState, eid: int) -> int:
	if state.megas.is_empty():
		return 0
	return Research.fx_int(state, eid, "mega_voix_pct")


## Durée des titans (Méga-chantier naval), en pour cent.
static func titan_days_pct(state: GameState, eid: int) -> int:
	if state.megas.is_empty():
		return 0
	return Research.fx_int(state, eid, "titan_days_pct")


# --- Chaque mois : prise, usure, sièges, événements, Kardashev -----------------------------------

static func monthly(state: GameState, added: Array[Dictionary]) -> void:
	if state.megas.is_empty():
		return
	for id in ids(state):
		var m := get_m(state, id)
		if m.is_empty():
			continue
		_sync_owner(state, m, added)
	MegasWorld.monthly(state, added)
	for e in state.empires:
		if not e.is_npc() and not e.eliminated:
			_kardashev(state, e.id, added)


## Prise (prop. 31) : une mégastructure suit le propriétaire de son système.
static func _sync_owner(state: GameState, m: Dictionary, added: Array[Dictionary]) -> void:
	if is_ruin(m) and not bool(m.get("rs", 0)):
		return
	var sid := int(m["s"])
	var o := state.system_owner(sid)
	var cur := int(m["o"])
	if o < 0 or o == cur or GameState.is_npc(o):
		return
	if cur >= 0 and _holds(state, cur, sid):
		return
	var before := state.get_empire(cur)
	m["o"] = o
	m["w"] = 0  # un chantier en cours s'arrête : le nouveau maître décidera
	m.erase("rp")
	m.erase("rs")
	m.erase("f")
	if int(m["st"]) == 0:
		entries(state).erase(str(int(m["id"])))  # un Chantier qui ne tenait pas : rien à prendre
		touch(state)
		return
	touch(state)
	_stat(state, o, "taken", 1)
	added.append(state.add_chronicle("%s passe aux mains de %s%s." % [name_of(state, m), state.get_empire(o).short_name(),
			(", arraché(e) à %s" % before.short_name()) if before != null else ""], Espionage.private_to(state, [o, cur], sid)))
	MegasBridges.on_taken(state, m, cur, o, added)


## Indice de Kardashev ×10 (prop. 9).
static func kardashev(state: GameState, eid: int) -> int:
	return int(sub(state, "kard").get(str(eid), 0))


@warning_ignore("integer_division")
static func kardashev_tier(state: GameState, eid: int) -> int:
	return kardashev(state, eid) / 10


static func kardashev_text(state: GameState, eid: int) -> String:
	var k := kardashev(state, eid)
	@warning_ignore("integer_division")
	var t := "%d,%d" % [k / 10, k % 10]
	var titles: Array = cfg("kardashev").get("titles", [])
	var tier := kardashev_tier(state, eid)
	if tier > 0 and tier < titles.size():
		t += " (%s)" % String(titles[tier])
	return t


@warning_ignore("integer_division")
static func compute_kardashev(state: GameState, eid: int) -> int:
	var kc := cfg("kardashev")
	var en: Array = kc.get("energy", [150, 400, 800])
	var gross := int((Economy.empire_income(state, eid)["gross"] as Dictionary).get("energy", 0))
	var tier := 0
	if gross >= int(en[0]):
		tier = 1
		var type2 := complete_count(state, eid, "sphere_dyson") > 0 or complete_count(state, eid, "essaim_dyson") >= 3
		if type2:
			tier = 2
			var great := 0
			var era5 := 0
			for m in owned_by(state, eid):
				if complete(m) and int(kind_def(String(m["k"])).get("era", 1)) >= 4:
					great += 1
					if int(kind_def(String(m["k"])).get("era", 1)) >= 5:
						era5 += 1
			if great >= int(kc.get("great", 6)) and era5 >= int(kc.get("era5", 3)) and gross >= int(en[2]):
				tier = 3
	if tier >= 3:
		return 30
	var lo := 0 if tier == 0 else int(en[tier - 1])
	var hi := int(en[tier])
	var frac := clampi((gross - lo) * 10 / maxi(1, hi - lo), 0, 9)
	return tier * 10 + frac


static func _kardashev(state: GameState, eid: int, added: Array[Dictionary]) -> void:
	var before := kardashev_tier(state, eid)
	var k := compute_kardashev(state, eid)
	sub(state, "kard")[str(eid)] = k
	@warning_ignore("integer_division")
	var tier := k / 10
	if tier > before:
		touch(state)
		var titles: Array = cfg("kardashev").get("titles", [])
		Announce.next(state, "kardashev", {"actor": eid})
		added.append(state.add_chronicle("%s franchit le type %s de l'échelle de Kardashev : %s. Les astronomes voisins notent une étoile un peu moins brillante que prévu." % [
				state.get_empire(eid).short_name(), ["0", "I", "II", "III"][tier], String(titles[tier]) if tier < titles.size() else ""]))
		MegasBridges.on_kardashev(state, eid, tier, added)
	elif tier < before:
		touch(state)


# --- Anciennes sauvegardes (prop. 1) ------------------------------------------------------------

## Convertit les trois mégastructures des merveilles d'une ancienne sauvegarde (avant la 88) : bâtiments
## achevés ou à une étape, chantiers en cours, ruines. Allume le pilier en « Classiques » s'il le faut.
@warning_ignore("integer_division")
static func migrate_wonders(state: GameState) -> void:
	var map := {}
	for k in kind_ids():
		var w := String(kind_def(k).get("from_wonder", ""))
		if w != "":
			map[w] = k
	var found := []
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		for b in c.buildings.duplicate():
			if map.has(b):
				var st := int(state.wonders.get("stage", {}).get("%s#%d" % [b, pid], 0))
				found.append([String(map[b]), pid, c.owner, st])
				c.buildings.erase(b)
	var builds: Dictionary = state.wonders.get("build", {})
	for w in map:
		if builds.has(w):
			var per: Dictionary = builds[w]
			for ek in per:
				var entry: Dictionary = per[ek]
				var pid := int(entry.get("p", -1))
				if pid >= 0 and not bool(entry.get("ruin", 0)):
					found.append([String(map[w]), pid, int(ek), -1 - Wonders.pct(entry)])
			builds.erase(w)
	var ruins: Dictionary = state.wonders.get("ruins", {})
	for w in map:
		if ruins.has(w):
			found.append([String(map[w]), int(ruins[w]), -1, -1000])
			ruins.erase(w)
	if found.is_empty() and state.wonders.is_empty():
		return
	if state.megas.is_empty():
		setup(state, "classiques", "aucune")
	for row in found:
		var k := String(row[0])
		var pid := int(row[1])
		var sid := state.galaxy.get_planet(pid).system_id
		var n := stage_count(k)
		var st := n
		var code := int(row[3])
		if code > 0:
			st = mini(n - 1, 1 + code)
		elif code == -1000:
			st = maxi(1, n - 2)
		elif code < 0:
			st = 1 + (-1 - code) * (n - 2) / 100
		var id := int(state.megas.get("next", 1))
		state.megas["next"] = id + 1
		var m := {"id": id, "k": k, "o": int(row[2]), "s": sid, "p": -1 if body(k) == "star" else pid, "st": st, "w": 0}
		if code == -1000:
			m["ruin"] = 1
			m["o"] = -1
		entries(state)[str(id)] = m
	touch(state)
