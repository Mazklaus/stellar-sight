class_name GroundSiege
extends RefCounted
## Combat au sol, lot 2 : siège en deux temps, bombardement orbital à postures, dévastation,
## Citadelle, reddition et sortie de la garnison (étude du 2026-11-15, prop. 19 à 23 ; data/ground.json,
## blocs "siege", "bombard", "devastation"). Seulement en combat au sol complet (Ground.full).
##
## - Fortifications : chaque colonie établie du défenseur et chaque bâtiment « fort » (Bastion,
##   Citadelle) en donnent ; le siège les use d'abord, la garnison (la milice) ensuite. Le génie de
##   siège à bord des assiégeants ajoute sa puissance. Hors siège, elles se relèvent chaque jour.
## - Posture de bombardement d'une flotte (ordre) : Sélectif (cibles militaires, siège plus fort),
##   Indiscriminé (tue de la population, dévaste), Rasant (crime de guerre, réservé aux peuples qui le
##   permettent). Une Citadelle debout protège population et bâtiments du bombardement.
## - Dévastation (0 à 100 par système) : réduit production, croissance et stabilité ; née du
##   bombardement et des batailles au sol, elle baisse chaque mois.
## - Reddition : un monde bombardé sans fortifications, sans milice ni régiment capitule après
##   quelques jours, sauf les peuples qui ne se rendent jamais (couche « no_surrender »).
## - Sortie : le défenseur lance ses régiments au sol contre les transports qui assiègent (une fois par
##   période de recharge).
##
## state.ground : "fort" {"<sid>": fortifications actuelles}, "bomb" {"<fid>": posture},
##   "dev" {"<sid>": dévastation}, "surr" {"<sid>": jours de bombardement sans défense}, "sortie" {"<sid>": tick de recharge}.

const POSTURES: Array[String] = ["", "selectif", "indiscrimine", "rasant"]


static func _cfg(k: String) -> Dictionary:
	return Ground.data().get(k, {})


static func _sub(state: GameState, k: String) -> Dictionary:
	if not state.ground.has(k):
		state.ground[k] = {}
	return state.ground[k]


# --- Fortifications -----------------------------------------------------------------------------

static func fort_max(state: GameState, sid: int) -> int:
	var owner := WarPeace.holder(state, sid)
	if owner < 0:
		return 0
	var sc := _cfg("siege")
	var n := 0
	for pid in state.galaxy.systems[sid].planet_ids:
		var c: Colony = state.colonies.get(pid)
		if c == null or c.owner != owner or not c.is_established():
			continue
		n += int(sc.get("fort_per_colony", 20)) if c.is_colony() else int(sc.get("fort_per_outpost", 5))
		for b in c.buildings:
			n += int(GameData.building(b).get("fort", 0))
	@warning_ignore("integer_division")
	return n * maxi(10, 100 + Research.fx_int(state, owner, "fort_pct")) / 100


static func fort(state: GameState, sid: int) -> int:
	var mx := fort_max(state, sid)
	return mini(mx, int(_sub(state, "fort").get(str(sid), mx)))


static func has_citadel(state: GameState, sid: int) -> bool:
	var owner := WarPeace.holder(state, sid)
	for pid in state.galaxy.systems[sid].planet_ids:
		var c: Colony = state.colonies.get(pid)
		if c == null or c.owner != owner or not c.is_established():
			continue
		for b in c.buildings:
			if bool(GameData.building(b).get("citadel", false)):
				return true
	return false


## La Citadelle protège population et bâtiments tant que les fortifications tiennent.
static func shielded(state: GameState, sid: int) -> bool:
	return has_citadel(state, sid) and fort(state, sid) > 0


# --- Postures de bombardement ----------------------------------------------------------------------

static func posture(state: GameState, fid: int) -> String:
	return String(_sub(state, "bomb").get(str(fid), ""))


static func posture_def(p: String) -> Dictionary:
	return _cfg("bombard").get("postures", {}).get(p, {})


static func posture_label(p: String) -> String:
	return String(posture_def(p).get("label", "Aucun")) if p != "" else "Aucun"


## Le Rasant n'est permis qu'aux peuples dont une couche le prévoit (combat.orbital_raze).
static func posture_allowed(state: GameState, eid: int, p: String) -> bool:
	if not POSTURES.has(p):
		return false
	if p != "rasant":
		return true
	var e := state.get_empire(eid)
	return e != null and int(e.faction().get("combat", {}).get("orbital_raze", 0)) > 0


static func check_posture(state: GameState, eid: int, fid: int, p: String) -> String:
	if not Ground.full(state):
		return "les armées ne sont pas en jeu"
	var f: Fleet = state.fleets.get(fid)
	if f == null or f.owner != eid:
		return "cette flotte ne vous appartient pas"
	if not Combat.is_armed(f):
		return "une flotte sans armes ne bombarde pas"
	if not POSTURES.has(p):
		return "posture inconnue"
	if not posture_allowed(state, eid, p):
		return "votre peuple ne rase pas les mondes"
	return ""


static func set_posture(state: GameState, fid: int, p: String) -> void:
	if p == "":
		_sub(state, "bomb").erase(str(fid))
	else:
		_sub(state, "bomb")[str(fid)] = p


## Posture suivante permise (pour le bouton de la fiche de flotte).
static func next_posture(state: GameState, eid: int, p: String) -> String:
	var i := POSTURES.find(p)
	for k in range(1, POSTURES.size() + 1):
		var q := POSTURES[(i + k) % POSTURES.size()]
		if posture_allowed(state, eid, q):
			return q
	return ""


# --- Dévastation ------------------------------------------------------------------------------------

static func dev(state: GameState, sid: int) -> int:
	return int(_sub(state, "dev").get(str(sid), 0))


static func add_dev(state: GameState, sid: int, n: int) -> void:
	if n == 0:
		return
	var v := clampi(dev(state, sid) + n, 0, 100)
	if v <= 0:
		_sub(state, "dev").erase(str(sid))
	else:
		_sub(state, "dev")[str(sid)] = v


## Production d'une colonie (en %) selon la dévastation de son système.
static func production_pct(state: GameState, sid: int) -> int:
	if state.ground.is_empty() or not state.ground.has("dev"):
		return 100
	@warning_ignore("integer_division")
	return 100 - dev(state, sid) * int(_cfg("devastation").get("production_pct_per_point", 50)) / 100


static func growth_pct(state: GameState, sid: int) -> int:
	if state.ground.is_empty() or not state.ground.has("dev"):
		return 0
	@warning_ignore("integer_division")
	return -dev(state, sid) * int(_cfg("devastation").get("growth_pct_per_point", 100)) / 100


static func stability_malus(state: GameState, sid: int) -> int:
	if state.ground.is_empty() or not state.ground.has("dev"):
		return 0
	@warning_ignore("integer_division")
	return -dev(state, sid) / maxi(1, int(_cfg("devastation").get("points_per_stability", 5)))


# --- Siège ----------------------------------------------------------------------------------------

## Puissance de siège du génie à bord d'une flotte.
static func engineer_power(state: GameState, f: Fleet) -> int:
	var n := 0
	for r in Ground.aboard(state, f.id):
		n += int(Ground.type_def(String(r["t"])).get("abilities", {}).get("siege", 0))
	return n


## Un jour de siège (appelé par CombatSystem._sieges en mode complet, à la place de l'usure directe
## de la garnison). power : puissance de siège des flottes.
static func on_siege(state: GameState, sid: int, by: Array[Fleet], power: int) -> void:
	var owner := state.system_owner(sid)
	var worst := ""
	for f in by:
		if not state.fleets.has(f.id):
			continue
		power += engineer_power(state, f)
		var p := posture(state, f.id)
		if p != "":
			var sp := int(posture_def(p).get("siege_pct", 100))
			if p == "selectif":
				sp += Research.fx_int(state, f.owner, "precision_siege_pct")
			@warning_ignore("integer_division")
			power += Combat.siege_power(f, state) * (sp - 100) / 100
			if POSTURES.find(p) > POSTURES.find(worst):
				worst = p
	power = maxi(0, power)
	var fk := str(sid)
	var fo := fort(state, sid)
	if fo > 0:
		var left := maxi(0, fo - power)
		power -= fo - left
		_sub(state, "fort")[fk] = left
	if power > 0:
		state.garrisons[sid] = maxi(0, Combat.garrison(state, sid) - power)
	if worst != "":
		_bombard(state, sid, by[0].owner, owner, worst)
	_surrender(state, sid, by[0].owner, owner, worst)


static func _bombard(state: GameState, sid: int, by: int, owner: int, p: String) -> void:
	var d := posture_def(p)
	if shielded(state, sid):
		return
	AncientsBridges.on_bombard(state, sid, by)  # Monde saint bombardé : guerre sainte
	add_dev(state, sid, int(d.get("dev_per_day", 0)))
	var every := int(d.get("pop_every_days", 0))
	if every > 0 and state.rng.randi_range(1, every) == 1:
		var best: Colony = null
		for pid in state.galaxy.systems[sid].planet_ids:
			var c: Colony = state.colonies.get(pid)
			if c != null and c.owner == owner and c.is_colony() and c.population > 1 and (best == null or c.population > best.population):
				best = c
		if best != null:
			best.population -= 1
			best.growth = 0
			Peoples.normalize(best)
			Faiths.normalize(best)
	# Nomos (Mondes protégés) : bombarder sans discernement un monde peuplé est un crime de guerre.
	if p != "selectif" and Vassals.system_pop(state, sid, owner) > 0:
		var mk := "nomos_%d_%d" % [by, sid]
		if not _sub(state, "marks").has(mk):
			_sub(state, "marks")[mk] = state.tick
			WarLaws.war_crime(state, by, owner, "orbital_bombing")
	if bool(d.get("crime", false)):
		var key := "crime_%d_%d" % [by, sid]
		var marks := _sub(state, "marks")
		if not marks.has(key):
			marks[key] = state.tick
			Diplomacy.remember(state, owner, by, "war_crime")
			state.add_chronicle("%s rase %s depuis l'orbite. Les cendres retombent pendant des semaines ; la galaxie, elle, s'en souviendra." % [
					state.get_empire(by).display_name(), state.galaxy.systems[sid].system_name])


## Reddition : bombardé, sans fortifications ni milice ni régiment, le monde capitule au bout de
## quelques jours (jamais pour un peuple « no_surrender »).
static func _surrender(state: GameState, sid: int, by: int, owner: int, p: String) -> void:
	var sk := str(sid)
	var e := state.get_empire(owner)
	var never := e != null and int(e.faction().get("combat", {}).get("no_surrender", 0)) > 0
	if p == "" or never or fort(state, sid) > 0 or Combat.garrison(state, sid) > 0 \
			or not Ground.on_ground(state, sid, owner).is_empty() or not Ground.battle(state, sid).is_empty():
		_sub(state, "surr").erase(sk)
		return
	var n := int(_sub(state, "surr").get(sk, 0)) + 1
	_sub(state, "surr")[sk] = n
	if n < int(_cfg("siege").get("surrender_days", 10)):
		return
	_sub(state, "surr").erase(sk)
	state.add_chronicle("%s capitule sous les bombes de %s : sans soldats ni remparts, le gouverneur hisse le drapeau blanc." % [
			state.galaxy.systems[sid].system_name, state.get_empire(by).display_name()])
	if not WarPeace.invade(state, sid, by):
		Combat.capture_system(state, sid, by)
	state.garrisons.erase(sid)


static func surrender_left(state: GameState, sid: int) -> int:
	var n := int(_sub(state, "surr").get(str(sid), 0))
	return int(_cfg("siege").get("surrender_days", 10)) - n if n > 0 else -1


## Chaque jour, hors siège : les fortifications se relèvent ; postures des flottes disparues oubliées.
## Chaque mois : la dévastation baisse.
static func daily(state: GameState) -> void:
	var fo := _sub(state, "fort")
	var keys := fo.keys()
	keys.sort()
	for k in keys:
		var sid := int(k)
		if Combat.is_besieged(state, sid) or Logistics.encircled(state, sid):
			continue
		var v := int(fo[k]) + int(_cfg("siege").get("fort_regen", 2))
		if v >= fort_max(state, sid):
			fo.erase(k)
		else:
			fo[k] = v
	var bomb := _sub(state, "bomb")
	for k in bomb.keys():
		if not state.fleets.has(int(k)):
			bomb.erase(k)
	if state.tick % int(GameData.rules()["month_days"]) == 0:
		var dv := _sub(state, "dev")
		var dk := dv.keys()
		dk.sort()
		for k in dk:
			if Combat.is_besieged(state, int(k)) or not Ground.battle(state, int(k)).is_empty():
				continue
			add_dev(state, int(k), -int(_cfg("devastation").get("decay_per_month", 3)))


# --- Sortie ---------------------------------------------------------------------------------------

static func check_sortie(state: GameState, eid: int, sid: int) -> String:
	if not Ground.full(state):
		return "les armées ne sont pas en jeu"
	if sid < 0 or sid >= state.galaxy.systems.size() or WarPeace.holder(state, sid) != eid:
		return "ce système n'est pas à vous"
	if not Combat.is_besieged(state, sid):
		return "personne n'assiège ce système"
	if not Ground.battle(state, sid).is_empty():
		return "on se bat déjà au sol"
	if Ground.on_ground(state, sid, eid).is_empty():
		return "aucun régiment pour sortir"
	var targets := 0
	for f in Combat.besiegers(state, sid):
		targets += Ground.aboard(state, f.id).size()
	if targets == 0:
		return "les assiégeants n'ont pas de troupes à bord"
	var ready := int(_sub(state, "sortie").get(str(sid), 0))
	if ready > state.tick:
		return "la garnison se remet de sa dernière sortie (%d j)" % (ready - state.tick)
	return ""


## Une passe d'armes : chaque régiment du défenseur frappe un régiment à bord des assiégeants, qui
## répond ; les morts restent sur place.
static func sortie(state: GameState, eid: int, sid: int) -> void:
	_sub(state, "sortie")[str(sid)] = state.tick + int(_cfg("siege").get("sortie_cooldown", 30))
	var mine := Ground.on_ground(state, sid, eid)
	var theirs: Array[Dictionary] = []
	for f in Combat.besiegers(state, sid):
		theirs.append_array(Ground.aboard(state, f.id))
	var pct := int(_cfg("siege").get("sortie_pct", 150))
	var killed := 0
	var lost := 0
	for r in mine:
		if theirs.is_empty():
			break
		var t: Dictionary = theirs[state.rng.randi_range(0, theirs.size() - 1)]
		var dm: Array = Ground.type_def(String(r["t"])).get("dmg", [5, 10])
		@warning_ignore("integer_division")
		t["hp"] = int(t["hp"]) - state.rng.randi_range(int(dm[0]), int(dm[1])) * pct / 100
		var dt: Array = Ground.type_def(String(t["t"])).get("dmg", [5, 10])
		r["hp"] = int(r["hp"]) - state.rng.randi_range(int(dt[0]), int(dt[1]))
		if int(t["hp"]) <= 0:
			state.ground["r"].erase(str(int(t["id"])))
			theirs.erase(t)
			killed += 1
		if int(r["hp"]) <= 0:
			state.ground["r"].erase(str(int(r["id"])))
			lost += 1
	Ground.sync_all(state)
	state.add_chronicle("Sortie de la garnison de %s : %d régiment%s ennemi%s détruit%s dans les soutes, %d perdu%s." % [
			state.galaxy.systems[sid].system_name, killed, "s" if killed > 1 else "", "s" if killed > 1 else "", "s" if killed > 1 else "", lost, "s" if lost > 1 else ""])
