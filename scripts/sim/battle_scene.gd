class_name BattleScene
extends RefCounted
## Décor d'une bataille spatiale (étude visuel des combats, prop. 1, 6, 8, 9, 10) : ce que la vue de
## replay doit dessiner autour des vaisseaux. Relevé au début de la bataille dans b["scene"], recopié
## dans le rapport. Purement descriptif : aucune règle ne le lit.
##
## {"seed", "star", "planet": {"type", "size", "id"}, "moons": [{"type", "id"}], "belt": bool,
##  "station": "" | "bastion" | "outpost" | "colony", "owner": empire du système, "wrecks": épaves
##  déjà présentes (cimetière), "siege": bool, "lair": bool, "terrain": terrains actifs triés (Terrain.at,
##  vide sans terrain ; chaque terrain a un bloc "visual" dans data/terrain.json)}
## Les rapports plus anciens n'ont pas de "scene" : la vue prend alors un décor par défaut.


static func capture(state: GameState, sid: int, battle_id: int) -> Dictionary:
	var s: StarSystem = state.galaxy.systems[sid]
	var owner := state.system_owner(sid)
	var best := -1
	var best_score := -1
	var belt := false
	var station := ""
	var others: Array = []
	for pid in s.planet_ids:
		var p := state.galaxy.get_planet(pid)
		if p.type == "asteroids":
			belt = true
		var c: Colony = state.colonies.get(pid)
		# Planète montrée : la plus peuplée du propriétaire du système, sinon la plus grande.
		var score := p.size * 10
		if c != null and c.owner == owner:
			score += 1000 + c.population * 20
			if c.buildings.has("bastion"):
				station = "bastion"
			elif station == "":
				station = "colony" if c.is_colony() else "outpost"
		if p.type != "asteroids" and score > best_score:
			best_score = score
			best = pid
		if p.type != "asteroids":
			others.append(pid)
	var scene := {"seed": battle_id * 7919 + sid * 31, "star": s.star_type, "owner": owner, "belt": belt,
			"station": station, "wrecks": int(state.battle_wrecks.get(sid, 0)), "siege": state.sieges.has(sid),
			"lair": state.lairs.has(sid), "planet": {}, "moons": [], "terrain": Terrain.at(state, sid)}
	if best >= 0:
		var bp := state.galaxy.get_planet(best)
		scene["planet"] = {"type": bp.type, "size": bp.size, "id": bp.id}
		# Deux autres corps du système en lunes lointaines, de la plus proche à la plus lointaine.
		var cap := int(GameData.battle_visuals().get("planet", {}).get("moons_max", 2))
		for pid in others:
			if pid != best and scene["moons"].size() < cap:
				scene["moons"].append({"type": state.galaxy.get_planet(pid).type, "id": pid})
	return scene


## Fin de bataille : siège en place (planète au premier plan) et épaves laissées au cimetière.
static func finish(state: GameState, sid: int, report: Dictionary) -> void:
	var scene: Dictionary = report.get("scene", {})
	if scene.is_empty():
		return
	scene["siege"] = bool(scene.get("siege", false)) or state.sieges.has(sid)
	var lost := 0
	for side: Dictionary in report.get("sides", []):
		lost += Combat.count_ships(side.get("lost", {}))
	if lost > 0:
		var cap := int(GameData.battle_visuals().get("objects", {}).get("wrecks_cap", 60))
		state.battle_wrecks[sid] = mini(cap, int(state.battle_wrecks.get(sid, 0)) + lost)
