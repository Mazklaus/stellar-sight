class_name InsGravea
extends RefCounted
## Lithes de Gravéa (props 89 à 93 ; voir Insolites, data/insolites.json "gravea").
## Ils vivent à l'échelle géologique : leurs actions prennent des décennies mais remodèlent des systèmes.
##   - Œuvres lentes : projets de dix à quinze ans dans un de leurs systèmes (fondre une ceinture
##     d'astéroïdes en monde, rendre un monde habitable, déplacer une planète vers la zone tempérée,
##     refroidir l'étoile). Elles changent le type des planètes (State.override_planet, comme la
##     terraformation et la Forge des mondes) ; works_max à la fois. Un système perdu emporte son chantier.
##   - Consensus séculaire : une guerre se délibère cons_days jours avant d'être possible (Combat.check_war
##     via Insolites.war_block). Leurs garnisons valent beaucoup plus (brique de gouvernement).
##   - Patience (credo) : une réserve de Temps monte chaque mois tant qu'ils n'ont rien entrepris depuis
##     idle_days ; elle se dépense d'un coup pour avancer une Œuvre d'autant de jours.
##   - Hibernation : un monde menacé (flotte ennemie armée dans le système) s'endort sleep_days jours : le
##     système ne peut plus être envahi, la colonie ne produit plus rien.
##   - Victoire : le Remodelage (works_win Œuvres achevées dans autant de systèmes différents).
##
## État (Insolites.emp) : "works": [{"w", "sid", "pid", "left", "total"}], "done": {sid: œuvre},
## "time" (réserve de Temps), "acted" (jour de la dernière entreprise), "cons": {cible: jour de maturité}.
## Galaxie : state.insolites "sleep": {pid: jour du réveil}.


static func _c(key: String, def := 0) -> int:
	return Insolites.c_int("gravea", key, def)


static func found(_state: GameState, _e: Empire, _sid: int, ed: Dictionary) -> void:
	ed["works"] = []
	ed["done"] = {}
	ed["time"] = 0
	ed["acted"] = 0
	ed["cons"] = {}


static func is_lithe(state: GameState, eid: int) -> bool:
	return not state.insolites.is_empty() and Insolites.kind(state, eid) == "gravea"


static func work_def(w: String) -> Dictionary:
	return (Insolites.cfg("gravea").get("works", {}) as Dictionary).get(w, {})


## Œuvres par ère (arbre, restes du lot 5) : une Œuvre qui porte "tech" attend cette technologie.
static func work_open(state: GameState, eid: int, w: String) -> bool:
	var t := String(work_def(w).get("tech", ""))
	return t == "" or Research.knows(state, eid, t)


static func work_ids() -> Array[String]:
	var out: Array[String] = []
	for k in (Insolites.cfg("gravea").get("works", {}) as Dictionary):
		if not String(k).begins_with("_"):
			out.append(String(k))
	out.sort()
	return out


# --- Œuvres lentes (prop. 89) ------------------------------------------------------------------------

## Planètes du système qu'une Œuvre changerait (celle visée, ou tout le système).
static func targets(state: GameState, w: String, pid: int) -> Array[int]:
	var out: Array[int] = []
	var wd := work_def(w)
	var mp: Dictionary = wd.get("map", {})
	var p := state.galaxy.get_planet(pid)
	if p == null:
		return out
	var pool: Array = state.galaxy.systems[p.system_id].planet_ids if String(wd.get("scope", "planet")) == "system" else [pid]
	for q in pool:
		var c: Colony = state.colonies.get(q)
		if c != null and c.owner != state.system_owner(p.system_id):
			continue
		if mp.has(state.galaxy.get_planet(int(q)).type):
			out.append(int(q))
	return out


static func check_work(state: GameState, eid: int, w: String, pid: int) -> String:
	if not is_lithe(state, eid):
		return "seuls les Lithes de Gravéa entreprennent des Œuvres lentes"
	var wd := work_def(w)
	if wd.is_empty():
		return "Œuvre inconnue"
	if not work_open(state, eid, w):
		return "technologie requise : %s" % Research.missing_text(state, eid, [String(wd["tech"])])
	var p := state.galaxy.get_planet(pid)
	if p == null:
		return "planète inconnue"
	if state.system_owner(p.system_id) != eid:
		return "il faut un de vos systèmes"
	var ed := Insolites.emp(state, eid)
	var works: Array = ed.get("works", [])
	for x: Dictionary in works:
		if int(x["sid"]) == p.system_id:
			return "une Œuvre est déjà en cours dans ce système"
	if works.size() >= _c("works_max", 3):
		return "trop d'Œuvres à la fois (%d au plus)" % _c("works_max", 3)
	if targets(state, w, pid).is_empty():
		return "rien à remodeler ici pour cette Œuvre"
	var cost: Dictionary = wd.get("cost", {})
	if not Economy.can_afford(state.get_empire(eid), cost):
		return "ressources insuffisantes (il faut %s)" % GameData.format_amounts(cost)
	return ""


static func start_work(state: GameState, eid: int, w: String, pid: int, added: Array[Dictionary]) -> void:
	var wd := work_def(w)
	Economy.pay(state.get_empire(eid), wd.get("cost", {}))
	var ed := Insolites.emp(state, eid)
	var days := int(wd.get("days", 3600))
	var sid := state.galaxy.get_planet(pid).system_id
	(ed["works"] as Array).append({"w": w, "sid": sid, "pid": pid, "left": days, "total": days})
	ed["acted"] = state.tick
	@warning_ignore("integer_division")
	added.append(state.add_chronicle("Les Lithes de Gravéa entreprennent une Œuvre à %s : %s. Les plans sont gravés pour %d ans ; les petits-enfants des témoins verront peut-être la fin." % [
			state.galaxy.systems[sid].system_name, String(wd.get("label", w)).to_lower(), days / 360], Espionage.public_to(state, [eid])))


static func _finish(state: GameState, eid: int, x: Dictionary, added: Array[Dictionary]) -> void:
	var wd := work_def(String(x["w"]))
	var mp: Dictionary = wd.get("map", {})
	var changed := 0
	for q in targets(state, String(x["w"]), int(x["pid"])):
		var p := state.galaxy.get_planet(q)
		state.override_planet(q, {"type": String(mp[p.type])})
		Ecology.on_terraform(state, q)
		changed += 1
	for e in state.empires:
		e.hab_cache.clear()
	var ed := Insolites.emp(state, eid)
	(ed["done"] as Dictionary)[str(int(x["sid"]))] = String(x["w"])
	added.append(state.add_chronicle("À %s, l'Œuvre des Lithes est achevée : %s. %d monde%s n'ont plus la même forme ; les cartes de cinq empires sont fausses." % [
			state.galaxy.systems[int(x["sid"])].system_name, String(wd.get("label", x["w"])).to_lower(), changed, "s" if changed > 1 else ""], Espionage.public_to(state, [eid])))


# --- Patience (prop. 91) -----------------------------------------------------------------------------

static func check_hasten(state: GameState, eid: int, i: int) -> String:
	if not is_lithe(state, eid):
		return "seuls les Lithes accumulent le Temps"
	var works: Array = Insolites.emp(state, eid).get("works", [])
	if i < 0 or i >= works.size():
		return "aucune Œuvre de ce rang"
	if int(Insolites.emp(state, eid).get("time", 0)) < _c("hasten_min", 60):
		return "pas assez de Temps en réserve (%d jours au moins)" % _c("hasten_min", 60)
	return ""


static func hasten(state: GameState, eid: int, i: int, added: Array[Dictionary]) -> void:
	var ed := Insolites.emp(state, eid)
	var x: Dictionary = (ed["works"] as Array)[i]
	var t := int(ed["time"])
	x["left"] = maxi(1, int(x["left"]) - t)
	ed["time"] = 0
	added.append(state.add_chronicle("Les Lithes dépensent d'un coup %d jours de patience : l'Œuvre de %s avance comme une montagne qui se décide." % [t, state.galaxy.systems[int(x["sid"])].system_name],
			Espionage.private_to(state, [eid])))


# --- Consensus séculaire (prop. 90) ------------------------------------------------------------------

static func check_deliberate(state: GameState, eid: int, target: int) -> String:
	if not is_lithe(state, eid):
		return "seuls les Lithes délibèrent un siècle"
	var t := state.get_empire(target)
	if t == null or t.eliminated or target == eid or t.is_npc():
		return "il faut un autre empire"
	if not state.get_empire(eid).contacts.has(target):
		return "vous n'avez jamais rencontré cet empire"
	if state.get_empire(eid).wars.has(target):
		return "vous êtes déjà en guerre"
	if (Insolites.emp(state, eid).get("cons", {}) as Dictionary).has(str(target)):
		return "le consensus est déjà en délibération"
	return ""


static func deliberate(state: GameState, eid: int, target: int, added: Array[Dictionary]) -> void:
	var ed := Insolites.emp(state, eid)
	(ed["cons"] as Dictionary)[str(target)] = state.tick + _c("cons_days", 720)
	ed["acted"] = state.tick
	added.append(state.add_chronicle("Les Lithes de Gravéa ouvrent une délibération sur %s. Elle durera deux ans. Les espions qui l'ont apprise en ont déjà prévenu leurs petits-enfants." % state.get_empire(target).display_name(),
			Espionage.public_to(state, [eid, target])))


## Raison qui empêche les Lithes de déclarer la guerre à target ("" si le consensus est mûr).
static func war_block(state: GameState, eid: int, target: int) -> String:
	if target < 0:
		return ""
	var cons: Dictionary = Insolites.emp(state, eid).get("cons", {})
	if not cons.has(str(target)):
		return "le Consensus séculaire doit d'abord délibérer deux ans (menu des peuples)"
	if int(cons[str(target)]) > state.tick:
		return "le consensus se forme encore (%d jours)" % (int(cons[str(target)]) - state.tick)
	return ""


# --- Hibernation (prop. 92) --------------------------------------------------------------------------

static func asleep(state: GameState, pid: int) -> bool:
	return int((state.insolites.get("sleep", {}) as Dictionary).get(str(pid), 0)) > state.tick


static func check_sleep(state: GameState, eid: int, pid: int) -> String:
	if not is_lithe(state, eid):
		return "seuls les Lithes savent hiberner"
	var c: Colony = state.colonies.get(pid)
	if c == null or c.owner != eid or not c.is_colony():
		return "il faut une de vos colonies"
	if asleep(state, pid):
		return "ce monde dort déjà"
	var sid := state.galaxy.get_planet(pid).system_id
	var threat := false
	for f in Fleets.fleets_at(state, sid):
		if f.owner != eid and Combat.is_armed(f) and Combat.at_war(state, f.owner, eid):
			threat = true
	if not threat:
		return "seul un monde attaqué (flotte ennemie dans le système) s'endort"
	return ""


static func sleep(state: GameState, eid: int, pid: int, added: Array[Dictionary]) -> void:
	Insolites.sub(state, "sleep")[str(pid)] = state.tick + Insolites.tuned(state, eid, "gravea", "sleep_days", _c("sleep_days", 1080))
	Insolites.emp(state, eid)["acted"] = state.tick
	added.append(state.add_chronicle("%s s'endort. Les Lithes rentrent dans la roche, la surface se referme ; les envahisseurs ne trouvent qu'une montagne qui ne répond plus." % state.galaxy.get_planet(pid).display_name(state.galaxy),
			Espionage.public_to(state, [eid])))


## Raison qui empêche d'envahir ce système ("" sinon) : un monde des Lithes y hiberne.
static func invade_block(state: GameState, sid: int) -> String:
	if not state.insolites.has("sleep"):
		return ""
	for pid in state.galaxy.systems[sid].planet_ids:
		if asleep(state, int(pid)):
			return "un monde des Lithes hiberne ici : il n'y a rien à prendre qu'une montagne fermée"
	return ""


static func colony_pct(state: GameState, pid: int) -> int:
	return 0 if state.insolites.has("sleep") and asleep(state, pid) else 100


# --- Chaque jour -------------------------------------------------------------------------------------

static func daily(state: GameState, eid: int, ed: Dictionary, month: bool, added: Array[Dictionary]) -> void:
	var works: Array = ed.get("works", [])
	for i in range(works.size() - 1, -1, -1):
		var x: Dictionary = works[i]
		if state.system_owner(int(x["sid"])) != eid:
			works.remove_at(i)
			added.append(state.add_chronicle("Le chantier de l'Œuvre de %s est perdu avec le système. Les Lithes n'en parlent pas ; ils s'en souviendront longtemps." % state.galaxy.systems[int(x["sid"])].system_name,
					Espionage.public_to(state, [eid])))
			continue
		x["left"] = int(x["left"]) - 1
		if int(x["left"]) <= 0:
			works.remove_at(i)
			_finish(state, eid, x, added)
	if not month:
		return
	var e := state.get_empire(eid)
	if state.tick - int(ed.get("acted", 0)) >= _c("idle_days", 180) and e.wars.is_empty():
		ed["time"] = mini(_c("time_max", 720), int(ed.get("time", 0)) + Insolites.tuned(state, eid, "gravea", "time_month", _c("time_month", 20)))
	var cons: Dictionary = ed.get("cons", {})
	for k in cons.keys():
		if int(cons[k]) + _c("cons_keep_days", 360) < state.tick and not e.wars.has(int(k)):
			cons.erase(k)  # le consensus mûr s'évente s'il ne sert pas
	if state.insolites.has("sleep"):
		var sl: Dictionary = state.insolites["sleep"]
		for k in sl.keys():
			if int(sl[k]) <= state.tick:
				sl.erase(k)


# --- Victoire : le Remodelage (prop. 93) -------------------------------------------------------------

static func victory(state: GameState, e: Empire, out: Dictionary) -> void:
	var want := int(Insolites.cfg("victories").get("remodelage", {}).get("count", 5))
	var n := (Insolites.emp(state, e.id).get("done", {}) as Dictionary).size()
	out["lines"].append("Œuvres lentes achevées : %d / %d systèmes" % [n, want])
	out["cond"] = n >= want
	Victory._timed(out, mini(n, want), want)


static func status_lines(state: GameState, eid: int, ed: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var works: Array = ed.get("works", [])
	var parts := PackedStringArray()
	for x: Dictionary in works:
		@warning_ignore("integer_division")
		parts.append("%s (%s, %d ans)" % [String(work_def(String(x["w"])).get("label", x["w"])), state.galaxy.systems[int(x["sid"])].system_name, maxi(1, int(x["left"]) / 360)])
	out.append("Œuvres : %s" % (", ".join(parts) if not parts.is_empty() else "aucune"))
	out.append("Temps en réserve : %d jours ; Œuvres achevées : %d" % [int(ed.get("time", 0)), (ed.get("done", {}) as Dictionary).size()])
	return out
