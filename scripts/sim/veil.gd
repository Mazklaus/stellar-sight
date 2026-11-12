class_name Veil
extends RefCounted
## Archétype Énergétique : le Voile. Les flottes et les revendications d'un peuple voilé n'apparaissent
## pas aux autres empires, même à portée de vue, sauf :
## - à ceux qui ont la technologie qui perce le voile (champ "veil" "tech" de la fiche) ;
## - aux autres peuples voilés (ils se reconnaissent) et aux alliés (vision partagée) ;
## - dans un système où l'observateur a lui-même une flotte à l'arrêt ou une revendication : de si
##   près, la présence se sent.
## Le spectateur voit tout. La mémoire de carte (Intel) et l'IA n'enregistrent que ce qui se voit.
## Un peuple voilé vu par un empire non allié est « repéré » (Empire.spotted_tick), ce que compte la
## victoire du Silence parfait.
##
## Inspiration : le Chœur Ombral d'Endless Space 2 (flottes et sanctuaires voilés, détectés par un
## vaisseau dont la détection égale leur voile ; wiki ES2, « The Umbral Choir/Gameplay ») et le
## camouflage de Stellaris: First Contact (révélé seulement par une détection au moins égale, dans les
## frontières de l'observateur).


static func has(faction: Dictionary) -> bool:
	return faction.has("veil")


static func is_veiled(state: GameState, empire_id: int) -> bool:
	var e := state.get_empire(empire_id)
	return e != null and has(e.faction())


## Technologie qui perce le voile.
static func detection_tech() -> String:
	return String(GameData.rules().get("veil_tech", "detecteurs_abysse"))


## L'observateur perce-t-il le voile partout (technologie ou peuple voilé lui-même) ?
static func pierces(state: GameState, viewer: int) -> bool:
	if viewer < 0:
		return true
	var v := state.get_empire(viewer)
	if v == null:
		return false
	return has(v.faction()) or v.techs.has(detection_tech())


## Systèmes où l'observateur est assez près pour sentir une présence voilée : ses revendications et
## ses flottes à l'arrêt.
static func near(state: GameState, viewer: int) -> Dictionary:
	var out := {}
	for pid in state.colonies:
		var c: Colony = state.colonies[pid]
		if c.owner == viewer:
			out[state.galaxy.get_planet(pid).system_id] = true
	for fid in state.fleets:
		var f: Fleet = state.fleets[fid]
		if f.owner == viewer and not f.is_moving():
			out[f.system_id] = true
	return out


## Ce que owner possède dans le système sid est-il caché à viewer ? near : near(state, viewer), ou
## null pour le calculer.
static func hides(state: GameState, owner: int, viewer: int, sid: int, near_set: Variant = null) -> bool:
	if owner == viewer or owner < 0 or viewer < 0 or not is_veiled(state, owner):
		return false
	if pierces(state, viewer) or Diplomacy.allied(state, owner, viewer):
		return false
	var n: Dictionary = near(state, viewer) if near_set == null else near_set
	return not n.has(sid)


## Note qu'un peuple voilé a été vu par un empire non allié (Empire.spotted_tick = dernier jour où il
## l'a été). Le Silence parfait repart de zéro à chaque repérage. La chronique ne parle que du premier,
## et de celui qui rompt un an de silence.
static func spot(state: GameState, owner: int, viewer: int) -> void:
	if owner == viewer or viewer < 0 or not is_veiled(state, owner) or Diplomacy.allied(state, owner, viewer):
		return
	var e := state.get_empire(owner)
	var quiet := e.spotted_tick < 0 or state.tick - e.spotted_tick >= GameCalendar.DAYS_PER_YEAR
	e.spotted_tick = state.tick
	e.spotted_by = viewer
	if quiet:
		state.add_chronicle("%s a aperçu ce qui ne devait pas l'être : une présence de %s, là où il n'y avait rien. Le Silence est rompu." % [
				state.get_empire(viewer).display_name(), e.display_name()], Espionage.private_to(state, [owner, viewer]))


## Le relevé d'un système tel que viewer le voit : sans les revendications qui lui sont cachées.
static func filter_survey(state: GameState, survey: Dictionary, viewer: int, sid: int, near_set: Dictionary) -> Dictionary:
	var out := survey
	var hidden := {}
	for cl in survey["claims"]:
		var owner := int(cl[1])
		if owner != viewer and is_veiled(state, owner):
			if hides(state, owner, viewer, sid, near_set):
				hidden[owner] = true
			else:
				spot(state, owner, viewer)
	if hidden.is_empty():
		return out
	out = survey.duplicate(true)
	var kept := []
	for cl in survey["claims"]:
		if not hidden.has(int(cl[1])):
			kept.append(cl)
	out["claims"] = kept
	if hidden.has(int(out["owner"])):
		out["owner"] = -1
	if hidden.has(int(out["siege"])):
		out["siege"] = -1
	return out
