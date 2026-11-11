extends SceneTree
## Diagnostic de l'expansion des IA, sans rien changer aux règles : chaque mois des premières années,
## ce qui pourrait bloquer chaque empire (influence, matériaux, chantiers de colonisation pleins,
## vaisseau colon qui attend, guerre). Une ligne JSON par graine (« EXP {...} »), agrégée par
## tools/expansion_report.py.
##   SEEDS=1,2,3 YEARS=5 godot --headless --path . -s res://tools/expansion_bench.gd


func _initialize() -> void:
	var years := int(OS.get_environment("YEARS")) if OS.get_environment("YEARS") != "" else 5
	var level := OS.get_environment("LEVEL") if OS.get_environment("LEVEL") != "" else "normal"
	var seeds := [3, 17, 99]
	if OS.get_environment("SEEDS") != "":
		seeds = Array(OS.get_environment("SEEDS").split(",")).map(func(s: String) -> int: return int(s))
	for sd in seeds:
		var st := GameState.create(sd, 150, 1800.0, "", {"spectator": true, "ai_level": level})
		var sim := Simulation.new(st)
		var rows := {}
		for e in st.empires:
			rows[e.id] = {"faction": e.faction_id, "months": []}
		for m in years * 12:
			sim.advance(30)
			for e in st.empires:
				if e.eliminated:
					continue
				rows[e.id]["months"].append(_sample(st, e))
		print("EXP " + JSON.stringify({"seed": sd, "empires": rows.values()}))
	quit()


static func _sample(st: GameState, e: Empire) -> Dictionary:
	var net: Dictionary = Economy.empire_income(st, e.id)["net"]
	var colonies := 0
	var outposts := 0
	for pid in st.colonies:
		var c: Colony = st.colonies[pid]
		if c.owner != e.id or not c.is_established():
			continue
		if c.is_colony():
			colonies += 1
		else:
			outposts += 1
	var colonizers := 0
	var waiting := 0  # vaisseaux colons à l'arrêt hors de nos systèmes (arrivés, faute de pouvoir fonder)
	var warships := 0
	for f in Fleets.empire_fleets(st, e.id):
		if Fleets.colonizer_ship(f) != "":
			colonizers += 1
			if not f.is_moving() and st.system_owner(f.system_id) != e.id:
				waiting += 1
		if Combat.is_warfleet(f):
			warships += f.ships.size()
	var building_colonizer := 0
	for pid in st.colonies:
		var c: Colony = st.colonies[pid]
		if c.owner == e.id and c.ship_build != "" and GameData.ship(c.ship_build).get("colonizer", false):
			building_colonizer += 1
	var use := int(AiLevels.level(e.ai_level).get("faction_use", 1))
	return {
		"sys": Victory.systems_held(st, e.id), "col": colonies, "out": outposts,
		"inf": int(e.resources.get("influence", 0)), "mat": int(e.resources.get("materials", 0)),
		"food": int(e.resources.get("food", 0)),
		"ninf": int(net.get("influence", 0)), "nmat": int(net.get("materials", 0)), "nfood": int(net.get("food", 0)),
		"proj": Economy.active_projects(st, e.id), "maxproj": Economy.max_projects_for(st, e.id),
		"colonizers": colonizers, "building": building_colonizer, "waiting": waiting,
		"warships": warships, "war": not e.wars.is_empty(),
		"targets": AiPlayer._has_open_targets(st, e, int(use), 1, Intel.seen(st, e.id)),
	}
