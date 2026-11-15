class_name BattleScene
extends RefCounted
## Décor d'une bataille spatiale (étude visuel des combats, prop. 1, 6, 8, 9, 10) : ce que la vue de
## replay doit dessiner autour des vaisseaux. Relevé au début de la bataille dans b["scene"], recopié
## dans le rapport. Purement descriptif : aucune règle ne le lit.
##
## {"seed", "star", "planet": {"type", "size", "id"}, "moons": [{"type", "id"}], "belt": bool,
##  "station": "" | "bastion" | "outpost" | "colony", "owner": empire du système, "wrecks": épaves
##  déjà présentes (cimetière), "siege": bool, "lair": bool}
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
			"lair": state.lairs.has(sid), "planet": {}, "moons": []}
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


## Décor d'une bataille au sol (visuel des combats, lot 2, prop. 18 à 22) : relevé à l'ouverture de la
## bataille dans b["sc"], recopié dans le rapport (avec la dévastation finale "dev1").
## {"seed", "star", "ter", "pop", "fort", "fort_max", "citadel", "bastion", "dev0", "orbit", "bombard"}
static func ground_capture(state: GameState, sid: int, attacker: int, defender: int, battle_id: int, tactic: String) -> Dictionary:
	var s: StarSystem = state.galaxy.systems[sid]
	var pop := 0
	var bastion := false
	for pid in s.planet_ids:
		var c: Colony = state.colonies.get(pid)
		if c != null and c.owner == defender:
			pop += c.population if c.is_colony() else 0
			if c.buildings.has("bastion"):
				bastion = true
	var orbit := 0
	var bombard := tactic == "bombardement"
	for f in Fleets.fleets_at(state, sid, attacker):
		orbit += f.ships.size()
		if GroundSiege.posture(state, f.id) != "":
			bombard = true
	return {"seed": battle_id * 6151 + sid * 17, "star": s.star_type, "ter": Ground.terrain_of(state, sid, defender), "pop": pop,
			"fort": GroundSiege.fort(state, sid), "fort_max": GroundSiege.fort_max(state, sid),
			"citadel": GroundSiege.has_citadel(state, sid), "bastion": bastion, "dev0": GroundSiege.dev(state, sid),
			"orbit": mini(orbit, 40), "bombard": bombard}
