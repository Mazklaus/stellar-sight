extends RefCounted
## Tests du visuel des combats, lot 2 (batailles au sol) : décor relevé dans le rapport, déroutes notées,
## figurines par régiment selon l'échelle et le plafond, corps qui restent, déterminisme de la vue,
## vue tactique. Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Visuel des combats, lot 2…")
	_test_data()
	var rep := _battle()
	if rep.is_empty():
		_ok(false, "Visuel sol : une bataille au sol a lieu")
		return
	_test_report(rep)
	_test_army(rep)


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


func _test_data() -> void:
	var g := GroundBackdrop.cfg()
	_ok((g["scales"] as Array).size() == 3, "Visuel sol : trois échelles de bataille")
	for fam in ["infanterie", "blindes", "aerien", "milice"]:
		var f: Array = g["figures"][fam]
		_ok(f.size() == 3 and int(f[0]) < int(f[1]) and int(f[1]) < int(f[2]), "Visuel sol : figurines croissantes par échelle (%s)" % fam)
	for ter in ["continental", "ocean", "desert", "arctic", "toxic", "gas_giant", "barren", "asteroids", "gaia", "ecumenopole"]:
		_ok(g["biomes"].has(ter), "Visuel sol : biome %s" % ter)
	_ok(ArmyLayer.figures_for("marcheur", 2) == 1, "Visuel sol : un marcheur reste une seule figurine")
	_ok(ArmyLayer.figures_for("infanterie", 2) > ArmyLayer.figures_for("infanterie", 0), "Visuel sol : la grande bataille a plus de figurines")
	var old := UiSettings.battle_scale
	UiSettings.battle_scale = "bataille"
	_ok(UiSettings.battle_scale_level() == 1 and UiSettings.BATTLE_SCALES.size() == 3, "Visuel sol : réglage d'échelle")
	UiSettings.battle_scale = old


func _battle() -> Dictionary:
	var st := GameState.create(12, 120, 1600.0, "ossarane", {"ai_level": "", "ground": "complet"})
	var sim := Simulation.new(st)
	for e in [st.get_empire(0), st.get_empire(1)]:
		e.contacts.append(1 - e.id)
	Combat.start_war(st, 0, 1)
	var target := FactionTraits.capital_system(st, 1)
	for g in Fleets.fleets_at(st, target, 1):
		st.fleets.erase(g.id)
	var f := st.spawn_ship(0, "transport", target)
	for i in 3:
		f.add_ship("transport")
	for t in ["infanterie", "infanterie", "infanterie", "infanterie", "infanterie", "infanterie", "infanterie", "infanterie"]:
		var r := Ground._new_regiment(st, 0, t, Peoples.founder_of(st, 0), target)
		r["f"] = f.id
	Ground.sync_fleet(st, f)
	sim.submit(SimCommands.invade(0, f.id))
	sim.flush_commands()
	var guard := 0
	while not Ground.battle(st, target).is_empty() and guard < 200:
		sim.step()
		guard += 1
	var reps := Ground.reports_for(st, 0)
	if reps.is_empty():
		return {}
	_state = st
	return reps[0]


var _state: GameState


func _test_report(rep: Dictionary) -> void:
	var sc: Dictionary = rep.get("sc", {})
	_ok(not sc.is_empty() and sc.has("ter") and sc.has("seed"), "Visuel sol : décor relevé dans le rapport")
	_ok(int(sc.get("pop", 0)) > 0, "Visuel sol : population de la ville relevée (%d)" % int(sc.get("pop", 0)))
	_ok(sc.has("dev1") and int(sc["dev1"]) >= int(sc.get("dev0", 0)), "Visuel sol : dévastation finale notée")
	_ok(rep.has("routs") and rep["routs"] is Array, "Visuel sol : déroutes notées")
	var ok_vet := true
	for u: Dictionary in rep["units"]:
		if String(u["t"]) != "milice" and not u.has("vet"):
			ok_vet = false
	_ok(ok_vet, "Visuel sol : vétérance de chaque régiment notée")


func _test_army(rep: Dictionary) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var panel := GroundReplayPanel.new()
	panel.size = Vector2(1600, 900)
	tree.root.add_child(panel)
	var old := UiSettings.battle_scale
	var totals: Array = []
	for sc in ["escarmouche", "bataille", "grande"]:
		UiSettings.battle_scale = sc
		panel.show_replay(_state, 0, rep)
		totals.append(panel.army.total)
	_ok(int(totals[0]) < int(totals[1]) and int(totals[1]) < int(totals[2]), "Visuel sol : plus de figurines à plus grande échelle (%s)" % str(totals))
	var caps: Array = GroundBackdrop.cfg()["cap"]
	_ok(int(totals[2]) <= int(caps[2]) + (rep["units"] as Array).size(), "Visuel sol : plafond de figurines respecté")
	UiSettings.battle_scale = "bataille"
	panel.show_replay(_state, 0, rep)
	var army := panel.army
	var end := panel.day_count() * GroundReplayPanel.DAY_SECONDS
	var start_n := army.living_total(0.0)
	var end_n := army.living_total(end)
	_ok(start_n == army.total, "Visuel sol : toutes les figurines debout au début")
	_ok(end_n < start_n, "Visuel sol : des figurines tombent (%d → %d)" % [start_n, end_n])
	# Une unité détruite n'a plus de figurine debout à la fin.
	var dead_ok := true
	for i in (rep["units"] as Array).size():
		if int(panel._dead_day[i]) >= 0 and army.alive_count(i, end) != 0:
			dead_ok = false
	_ok(dead_ok, "Visuel sol : une unité détruite n'a plus personne debout")
	# Les corps restent sur place : la position d'un corps ne dépend pas du moment où l'on regarde.
	var mm: MultiMesh = (army.get_child(0) as MultiMeshInstance2D).multimesh
	army.update(end, Color.WHITE)
	var n_corpses := mm.visible_instance_count
	var p1 := mm.get_instance_transform_2d(0).origin if n_corpses > 0 else Vector2.ZERO
	army.update(end + 0.5, Color.WHITE)
	var p2 := mm.get_instance_transform_2d(0).origin if mm.visible_instance_count > 0 else Vector2.ZERO
	_ok(n_corpses > 0 and p1 == p2, "Visuel sol : les corps restent là où ils sont tombés (%d)" % n_corpses)
	# Déterminisme : même temps, même image.
	army.update(end * 0.4, Color.WHITE)
	var inf: MultiMesh = (army.get_child(4) as MultiMeshInstance2D).multimesh
	var a := inf.get_instance_transform_2d(0).origin if inf.visible_instance_count > 0 else Vector2.ZERO
	army.update(end * 0.9, Color.WHITE)
	army.update(end * 0.4, Color.WHITE)
	var b := inf.get_instance_transform_2d(0).origin if inf.visible_instance_count > 0 else Vector2.ZERO
	_ok(inf.visible_instance_count > 0 and a == b, "Visuel sol : la vue est fonction du temps du replay")
	# L'assaillant avance depuis ses barges.
	var first := -1
	for i in (rep["units"] as Array).size():
		if int(rep["units"][i]["side"]) == 0:
			first = i
			break
	_ok(first >= 0 and army.anchor(first, end).x > army.anchor(first, 0.0).x, "Visuel sol : l'assaillant avance")
	_ok(panel.backdrop.visible and panel.backdrop.horizon_y > 0.0, "Visuel sol : champ de bataille monté")
	panel.toggle_tactical()
	_ok(not panel.backdrop.visible and not panel.army.visible, "Visuel sol : la vue tactique revient aux pions")
	panel.toggle_tactical()
	army.set_reduced(true)
	_ok(army.reduced and army.total <= int(caps[1]), "Visuel sol : mode allégé")
	# Un vieux rapport sans décor garde un décor par défaut.
	var legacy: Dictionary = rep.duplicate(true)
	legacy.erase("sc")
	legacy.erase("routs")
	panel.show_replay(_state, 0, legacy)
	_ok(not panel.backdrop.scene.is_empty() and panel.army.total > 0, "Visuel sol : décor par défaut pour un ancien rapport")
	UiSettings.battle_scale = old
	panel.close_silently()
	panel.queue_free()
