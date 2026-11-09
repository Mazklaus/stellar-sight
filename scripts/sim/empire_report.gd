class_name EmpireReport
extends RefCounted
## Bilans d'un empire pour les menus d'empire (économie, colonies) et la navigation.
## Lecture seule : tout est calculé depuis l'état avec les mêmes règles que la simulation (Economy),
## sans rien modifier. Les résultats sont triés de façon stable pour un affichage qui ne saute pas.


## Détail de chaque ressource : [{"id", "label", "stock", "gross", "upkeep", "net", "bonus_pct", "months_left"}].
## months_left = mois avant épuisement du stock au rythme actuel (-1 si le bilan n'est pas négatif).
static func resources(state: GameState, empire_id: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var e := state.get_empire(empire_id)
	if e == null:
		return out
	var income := Economy.empire_income(state, empire_id)
	var pct: Dictionary = e.faction().get("production_pct", {})
	for r in GameData.resource_ids():
		var stock := int(e.resources.get(r, 0))
		var net := int(income["net"][r])
		var months := -1
		if net < 0:
			@warning_ignore("integer_division")
			months = maxi(0, stock / -net)
		out.append({
			"id": r,
			"label": GameData.resource_label(r),
			"stock": stock,
			"gross": int(income["gross"][r]),
			"upkeep": int(income["upkeep"][r]),
			"net": net,
			"bonus_pct": int(pct.get(r, 100)) - 100,
			"months_left": months,
		})
	return out


## Revendications de l'empire, capitale d'abord puis par système et rang :
## [{"planet_id", "system_id", "name", "system_name", "type_label", "kind", "established", "days_left",
##   "population", "max_pop", "construction", "construction_days", "net", "capital"}].
static func colonies(state: GameState, empire_id: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var e := state.get_empire(empire_id)
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner != empire_id:
			continue
		var p := state.galaxy.get_planet(pid)
		var y := Economy.colony_yields(state, c)
		var net := {}
		for r in y["gross"]:
			net[r] = int(y["gross"][r]) - int(y["upkeep"][r])
		out.append({
			"planet_id": pid,
			"system_id": p.system_id,
			"name": p.display_name(state.galaxy),
			"system_name": state.galaxy.systems[p.system_id].system_name,
			"type_label": p.type_label(),
			"kind": c.kind,
			"established": c.is_established(),
			"days_left": c.days_left,
			"population": c.population,
			"max_pop": Economy.max_pop(state, p, empire_id, c.buildings) if c.is_colony() else 0,
			"construction": String(GameData.building(c.construction).get("label", c.construction)) if c.construction != "" else "",
			"construction_days": c.construction_days,
			"net": net,
			"capital": e != null and pid == e.capital_planet,
		})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["capital"] != b["capital"]:
			return a["capital"]
		if a["system_id"] != b["system_id"]:
			return a["system_id"] < b["system_id"]
		return a["planet_id"] < b["planet_id"])
	return out


## Bilan mensuel (avant bonus de faction) des revendications d'un empire dans un système : {res: int}.
static func system_net(state: GameState, empire_id: int, system_id: int) -> Dictionary:
	var net := {}
	for r in GameData.resource_ids():
		net[r] = 0
	for pid in state.galaxy.systems[system_id].planet_ids:
		var c: Colony = state.colonies.get(pid)
		if c == null or c.owner != empire_id:
			continue
		var y := Economy.colony_yields(state, c)
		for r in y["gross"]:
			net[r] += int(y["gross"][r]) - int(y["upkeep"][r])
	return net


## Chiffres clés : {"colonies", "outposts", "founding", "population", "systems", "max_projects"}.
static func totals(state: GameState, empire_id: int) -> Dictionary:
	var t := {"colonies": 0, "outposts": 0, "founding": 0, "population": 0, "systems": 0,
			"max_projects": int(GameData.rules()["max_projects"])}
	for c in colonies(state, empire_id):
		if not c["established"]:
			t["founding"] += 1
		elif c["kind"] == Colony.KIND_COLONY:
			t["colonies"] += 1
		else:
			t["outposts"] += 1
		t["population"] += int(c["population"])
	t["systems"] = owned_systems(state, empire_id).size()
	return t


## Systèmes où l'empire a au moins une revendication (fondée ou non), celui de la capitale d'abord.
## Sert à passer d'un système à l'autre (Tab).
static func owned_systems(state: GameState, empire_id: int) -> Array[int]:
	var seen := {}
	var out: Array[int] = []
	var e := state.get_empire(empire_id)
	if e and e.capital_planet >= 0:
		var home := state.galaxy.get_planet(e.capital_planet).system_id
		seen[home] = true
		out.append(home)
	var rest: Array[int] = []
	for pid in state.colonies:
		var c: Colony = state.colonies[pid]
		if c.owner != empire_id:
			continue
		var sid := state.galaxy.get_planet(pid).system_id
		if not seen.has(sid):
			seen[sid] = true
			rest.append(sid)
	rest.sort()
	out.append_array(rest)
	return out


## Système suivant (step = 1) ou précédent (step = -1) de l'empire après current, en boucle.
## Si current n'est pas à l'empire, renvoie le premier (ou le dernier). -1 si l'empire n'a rien.
static func cycle_system(state: GameState, empire_id: int, current: int, step: int) -> int:
	var list := owned_systems(state, empire_id)
	if list.is_empty():
		return -1
	var i := list.find(current)
	if i == -1:
		return list[0] if step >= 0 else list[list.size() - 1]
	return list[posmod(i + step, list.size())]
