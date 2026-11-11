class_name Intel
extends RefCounted
## Dernière information connue : ce que chaque empire sait des systèmes qu'il ne voit plus.
##
## Chaque empire garde, pour chaque système qu'il a vu, un relevé daté de la dernière observation
## (Empire.intel) : propriétaire, revendications (planète, propriétaire, colonie ou avant-poste,
## population), siège et bataille en cours. Le relevé est pris pendant l'exploration de chaque tick
## (FleetSystem.update_exploration), seulement pour les systèmes vus. Hors de vue, il reste figé.
##
## Lire un système passe par ici : vu maintenant = l'état réel ; connu mais pas vu = le relevé ;
## inconnu = rien. Un lecteur -1 (spectateur sans brouillard, outils) voit l'état réel partout.
## Données de simulation : entiers seulement, sauvegardées, identiques chez tous les joueurs.

## Durée (jours) au bout de laquelle une silhouette de flotte s'efface.
const SIGHTING_DAYS := 90

## Lecteur de l'interface : l'empire dont l'écran montre les yeux, ou -1 pour tout voir. Simple
## affichage, réglé par la scène principale : la simulation ne le lit JAMAIS.
static var lens := -1
## Relevé d'un système sans colonie, siège ni bataille : partagé, jamais modifié.
const EMPTY_SURVEY := {"owner": -1, "claims": [], "siege": -1, "battle": 0}


# --- Relevés ------------------------------------------------------------------------------------

## Relevé d'un système tel qu'il est maintenant (sans la date).
static func survey(state: GameState, system_id: int) -> Dictionary:
	var claims := []
	var s := state.galaxy.get_system(system_id)
	for pid in s.planet_ids:
		var c: Colony = state.colonies.get(pid)
		if c != null:
			claims.append([pid, c.owner, 1 if c.is_colony() else 0, c.population, 1 if c.is_established() else 0])
	var siege: Dictionary = state.sieges.get(system_id, {})
	return {
		"owner": state.system_owner(system_id),
		"claims": claims,
		"siege": int(siege.get("by", -1)),
		"battle": 1 if state.battles.has(system_id) else 0,
	}


## Met à jour la mémoire de chaque empire avec ce qu'il voit ce tick (seen_by : Fleets.visible_all).
## Le relevé d'un système n'est calculé qu'une fois par tick, même vu par plusieurs empires, et n'est
## remplacé que s'il a changé ; la date, elle, avance tant que le système reste en vue.
static func record(state: GameState, seen_by: Array[Dictionary]) -> void:
	# Les systèmes sans colonie, siège ni bataille (la plupart) partagent un même relevé vide.
	var busy := {}
	for pid in state.colonies:
		busy[state.galaxy.get_planet(pid).system_id] = true
	for sid in state.sieges:
		busy[sid] = true
	for sid in state.battles:
		busy[sid] = true
	var cache := {}
	for e in state.empires:
		if e.eliminated or e.id >= seen_by.size():
			continue
		for sid in seen_by[e.id]:
			var now: Dictionary = cache.get(sid, {})
			if now.is_empty():
				now = survey(state, sid) if busy.has(sid) else EMPTY_SURVEY
				cache[sid] = now
			var known: Dictionary = e.intel.get(sid, {})
			if known.is_empty():
				e.intel[sid] = {"day": state.tick, "info": now}
			elif is_same(known["info"], now):
				known["day"] = state.tick
			elif known["info"] != now:
				e.intel[sid] = {"day": state.tick, "info": now}
			else:
				known["day"] = state.tick
				known["info"] = now
	_record_fleets(state, seen_by)


## Silhouettes : chaque flotte étrangère vue est notée (système, jour, taille, armée ou non) ; une
## silhouette s'efface quand son système est vu sans elle, ou au bout de SIGHTING_DAYS jours.
static func _record_fleets(state: GameState, seen_by: Array[Dictionary]) -> void:
	# Position, taille et armement de chaque flotte, calculés une fois pour tous les empires.
	var spots: Array = []
	for fid in state.sorted_fleet_ids():
		var f: Fleet = state.fleets[fid]
		spots.append([fid, f.owner, Fleets.vision_center(state, f), f.ships.size(), -1, f])
	for e in state.empires:
		if e.eliminated or e.id >= seen_by.size():
			continue
		var seen: Dictionary = seen_by[e.id]
		var here := {}
		for spot in spots:
			if int(spot[1]) == e.id or not seen.has(spot[2]):
				continue
			if int(spot[4]) == -1:
				spot[4] = 1 if Combat.is_armed(spot[5]) else 0
			var fid: int = spot[0]
			here[fid] = true
			var old: Dictionary = e.sightings.get(fid, {})
			if old.is_empty():
				e.sightings[fid] = {"sys": spot[2], "day": state.tick, "owner": spot[1], "ships": spot[3],
						"armed": spot[4]}
			else:
				old["sys"] = spot[2]
				old["day"] = state.tick
				old["owner"] = spot[1]
				old["ships"] = spot[3]
				old["armed"] = spot[4]
		if e.sightings.size() == here.size():
			continue
		var ids := e.sightings.keys()
		ids.sort()
		for fid in ids:
			if here.has(fid):
				continue
			var s: Dictionary = e.sightings[fid]
			if seen.has(int(s["sys"])) or state.tick - int(s["day"]) > SIGHTING_DAYS:
				e.sightings.erase(fid)


## Relevés pris à distance (réseau d'espionnage, sonde) : même règle que record, pour ces systèmes.
static func record_systems(state: GameState, e: Empire, sids: Array) -> void:
	var ids := sids.duplicate()
	ids.sort()
	for sid in ids:
		var now := survey(state, int(sid))
		var known: Dictionary = e.intel.get(int(sid), {})
		if known.is_empty() or known["info"] != now:
			e.intel[int(sid)] = {"day": state.tick, "info": now}
		else:
			known["day"] = state.tick


## Mémoire tirée de l'état réel pour tous les systèmes explorés (sauvegardes d'avant la mémoire).
static func seed_from_truth(state: GameState, e: Empire) -> void:
	for sid in e.sorted_explored():
		if not e.intel.has(sid):
			e.intel[sid] = {"day": state.tick, "info": survey(state, sid)}


## Partage de cartes (alliance) : chacun reçoit les relevés plus récents de l'autre.
static func share(a: Empire, b: Empire) -> void:
	_merge_into(a, b)
	_merge_into(b, a)


static func _merge_into(from: Empire, to: Empire) -> void:
	var ids := from.intel.keys()
	ids.sort()
	for sid in ids:
		var theirs: Dictionary = from.intel[sid]
		var mine: Dictionary = to.intel.get(sid, {})
		if mine.is_empty() or int(theirs["day"]) > int(mine["day"]):
			to.intel[sid] = {"day": int(theirs["day"]), "info": theirs["info"]}


# --- Sauvegarde ---------------------------------------------------------------------------------

## Liste triée et compacte : [système, jour, propriétaire, assiégeant, bataille, revendications…],
## chaque revendication sur 5 entiers (planète, propriétaire, colonie, population, établie).
static func to_list(e: Empire) -> Array:
	var ids := e.intel.keys()
	ids.sort()
	var out := []
	for sid in ids:
		var m: Dictionary = e.intel[sid]
		var info: Dictionary = m["info"]
		var row := [sid, int(m["day"]), int(info["owner"]), int(info["siege"]), int(info["battle"])]
		for cl in info["claims"]:
			row.append_array(cl)
		out.append(row)
	return out


static func from_list(e: Empire, rows: Array) -> void:
	for row in rows:
		if not row is Array or row.size() < 5 or (row.size() - 5) % 5 != 0:
			continue
		var claims := []
		var i := 5
		while i < row.size():
			claims.append([int(row[i]), int(row[i + 1]), int(row[i + 2]), int(row[i + 3]), int(row[i + 4])])
			i += 5
		e.intel[int(row[0])] = {"day": int(row[1]), "info": {
			"owner": int(row[2]), "claims": claims, "siege": int(row[3]), "battle": int(row[4])}}


static func sightings_to_list(e: Empire) -> Array:
	var ids := e.sightings.keys()
	ids.sort()
	var out := []
	for fid in ids:
		var s: Dictionary = e.sightings[fid]
		out.append([fid, int(s["sys"]), int(s["day"]), int(s["owner"]), int(s["ships"]), int(s["armed"])])
	return out


static func sightings_from_list(e: Empire, rows: Array) -> void:
	for row in rows:
		if row is Array and row.size() == 6:
			e.sightings[int(row[0])] = {"sys": int(row[1]), "day": int(row[2]), "owner": int(row[3]),
					"ships": int(row[4]), "armed": int(row[5])}


# --- Lecture ------------------------------------------------------------------------------------

## Systèmes que l'empire voit en ce moment (calculés au tick, sinon recalculés).
static func seen(state: GameState, viewer: int) -> Dictionary:
	if viewer < 0:
		return {}
	if state.seen_tick == state.tick and viewer < state.seen_cache.size():
		return state.seen_cache[viewer]
	return Fleets.visible_systems(state, viewer)


## Le lecteur voit-il ce système en direct ? (-1 voit tout.)
static func is_live(state: GameState, viewer: int, system_id: int) -> bool:
	return viewer < 0 or seen(state, viewer).has(system_id)


## Relevé connu du lecteur pour un système : {} si jamais vu.
static func known(state: GameState, viewer: int, system_id: int) -> Dictionary:
	var e := state.get_empire(viewer)
	if e == null:
		return {}
	var m: Dictionary = e.intel.get(system_id, {})
	return m


## Jour de la dernière observation (le tick courant si vu en direct, -1 si jamais vu).
static func last_seen(state: GameState, viewer: int, system_id: int) -> int:
	if is_live(state, viewer, system_id):
		return state.tick
	var m := known(state, viewer, system_id)
	return int(m.get("day", -1))


## Propriétaire du système selon le lecteur (-1 : personne, ou rien de connu).
static func owner_of(state: GameState, viewer: int, system_id: int) -> int:
	if is_live(state, viewer, system_id):
		return state.system_owner(system_id)
	var m := known(state, viewer, system_id)
	if m.is_empty():
		return -1
	return int(m["info"]["owner"])


## Revendication d'une planète selon le lecteur : la vraie si son système est vu (ou si elle est au
## lecteur), sinon une copie reconstituée depuis le relevé (sans chantiers), ou null.
static func colony_of(state: GameState, viewer: int, planet_id: int) -> Colony:
	var real: Colony = state.colonies.get(planet_id)
	if real != null and real.owner == viewer:
		return real
	var p := state.galaxy.get_planet(planet_id)
	if p == null or is_live(state, viewer, p.system_id):
		return real
	var m := known(state, viewer, p.system_id)
	if m.is_empty():
		return null
	for cl in m["info"]["claims"]:
		if int(cl[0]) == planet_id:
			var c := Colony.new()
			c.planet_id = planet_id
			c.owner = int(cl[1])
			c.kind = Colony.KIND_COLONY if int(cl[2]) == 1 else Colony.KIND_OUTPOST
			c.population = int(cl[3])
			c.days_left = 0 if int(cl[4]) == 1 else 1
			return c
	return null


## Siège connu (-1 : aucun) et bataille connue, selon le lecteur.
static func siege_of(state: GameState, viewer: int, system_id: int) -> int:
	if is_live(state, viewer, system_id):
		return int((state.sieges.get(system_id, {}) as Dictionary).get("by", -1))
	var m := known(state, viewer, system_id)
	return -1 if m.is_empty() else int(m["info"]["siege"])


static func battle_known(state: GameState, viewer: int, system_id: int) -> bool:
	if is_live(state, viewer, system_id):
		return state.battles.has(system_id)
	var m := known(state, viewer, system_id)
	return not m.is_empty() and int(m["info"]["battle"]) == 1


## « vu il y a 3 mois » : âge d'un relevé, en mots. "" si le système est vu en ce moment.
static func age_label(state: GameState, viewer: int, system_id: int) -> String:
	if is_live(state, viewer, system_id):
		return ""
	var day := last_seen(state, viewer, system_id)
	if day < 0:
		return "jamais observé de près"
	var ago := state.tick - day
	if ago <= 1:
		return "vu hier"
	if ago < GameCalendar.DAYS_PER_MONTH:
		return "vu il y a %d jours" % ago
	if ago < GameCalendar.DAYS_PER_YEAR:
		@warning_ignore("integer_division")
		var months := ago / GameCalendar.DAYS_PER_MONTH
		return "vu il y a %d mois" % months
	@warning_ignore("integer_division")
	var years := ago / GameCalendar.DAYS_PER_YEAR
	return "vu il y a %d an%s" % [years, "s" if years > 1 else ""]


## Silhouettes de flottes que le lecteur ne voit plus, triées par flotte : [{"fleet", "sys", "day",
## "owner", "ships", "armed"}]. Seulement celles dont la flotte n'est pas visible en ce moment.
static func ghosts(state: GameState, viewer: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var e := state.get_empire(viewer)
	if e == null:
		return out
	var vis := seen(state, viewer)
	var ids := e.sightings.keys()
	ids.sort()
	for fid in ids:
		var f: Fleet = state.fleets.get(fid)
		if f != null and vis.has(Fleets.vision_center(state, f)):
			continue
		var g: Dictionary = e.sightings[fid].duplicate()
		g["fleet"] = fid
		out.append(g)
	return out


## Silhouettes dans un système, en une ligne : « Vael : 3 vaisseaux armés, il y a 12 jours ».
static func ghost_lines(state: GameState, viewer: int, system_id: int) -> PackedStringArray:
	var lines := PackedStringArray()
	for g in ghosts(state, viewer):
		if int(g["sys"]) != system_id:
			continue
		var owner := state.get_empire(int(g["owner"]))
		var n := int(g["ships"])
		var ago := state.tick - int(g["day"])
		lines.append("%s : %d vaisseau%s%s, aperçu%s" % [owner.short_name() if owner else "?", n, "x" if n > 1 else "",
				(" armé" + ("s" if n > 1 else "")) if int(g["armed"]) == 1 else "",
				" hier" if ago <= 1 else " il y a %d jours" % ago])
	return lines


# --- Raccourcis pour l'interface (lecteur = Intel.lens) ------------------------------------------

static func shown_owner(state: GameState, system_id: int) -> int:
	return owner_of(state, lens, system_id)


static func shown_colony(state: GameState, planet_id: int) -> Colony:
	return colony_of(state, lens, planet_id)


static func shown_live(state: GameState, system_id: int) -> bool:
	return is_live(state, lens, system_id)
