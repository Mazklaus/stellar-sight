extends SceneTree
## Captures et vidéo de la vue de bataille spatiale habillée (visuel des combats, lot 1) :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_replay_espace.gd
## Écrit dans CAPTURE_DIR (par défaut user://captures) : decor-*.png et les images de la vidéo dans
## CAPTURE_DIR/replay-espace/ (img_0000.png…), à assembler avec ffmpeg :
##   ffmpeg -framerate 30 -i replay-espace/img_%04d.png -pix_fmt yuv420p -vf scale=1280:-2 replay-espace.mp4
## Scénario : Ossarane contre Kh'thari (les deux peuples qui ont des sprites 3D), bataille au-dessus de
## la capitale Kh'thari, avec un cimetière d'épaves de batailles passées ; puis un siège.

const FPS := 30.0
const SPEED := 1.5


func _initialize() -> void:
	var out := OS.get_environment("CAPTURE_DIR")
	if out == "":
		out = ProjectSettings.globalize_path("user://captures")
	DirAccess.make_dir_recursive_absolute(out + "/replay-espace")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.save_path = "user://saves/capture_quicksave.json"
	main.start_with_menu = false
	root.add_child(main)
	await _frames(20)
	var st := GameState.create(2611, 150, 1800.0, "ossarane", {"ai_level": "", "rivals": ["khthari"]})
	main._start(st)
	main.game_in_progress = true
	for s in st.galaxy.systems:
		st.get_empire(0).explored[s.id] = true
	for e in [st.get_empire(0), st.get_empire(1)]:
		e.contacts.append(1 - e.id)
	Combat.start_war(st, 0, 1)
	var target := st.galaxy.get_planet(st.get_empire(1).capital_planet).system_id
	st.battle_wrecks[target] = 18
	var mine := st.spawn_ship(0, "fregate", target)
	for s in ["fregate", "fregate", "fregate", "croiseur", "cuirasse", "corvette", "corvette", "porte_vaisseaux"]:
		mine.add_ship(s)
	mine.tactic = "assaut"
	var foe := st.spawn_ship(1, "fregate", target)
	for s in ["fregate", "fregate", "fregate", "fregate", "corvette", "corvette", "corvette", "croiseur"]:
		foe.add_ship(s)
	var sim: Simulation = main.simulation
	var guard := 0
	while guard < 40 and _report_at(st, target).is_empty():
		sim.step()
		guard += 1
	var rep := _report_at(st, target)
	if rep.is_empty():
		print("pas de rapport")
		quit(1)
		return
	print("décor : ", rep.get("scene", {}))
	var panel: BattleReplayPanel = main._hud.battle_replay
	if OS.get_environment("GALLERY") != "":
		await _gallery(panel, st, rep, out)
		quit()
		return
	panel.show_replay(st, 0, rep)
	panel.playing = false
	await _frames(10)
	panel.modulate.a = 1.0
	var total := panel.day_count() * BattleReplayPanel.DAY_SECONDS
	var n := 0
	var t := 0.0
	while t <= total + 0.8:
		panel.t = minf(t, total)
		panel._update_scene()
		panel.queue_redraw()
		await _frames(1)
		await _shot_quiet(out + "/replay-espace/img_%04d.png" % n)
		n += 1
		t += SPEED / FPS
	for k in [[0.18, "decor-portee-longue"], [0.55, "decor-portee-moyenne"], [0.93, "decor-fin"]]:
		panel.t = total * float(k[0])
		panel._update_scene()
		panel.queue_redraw()
		await _frames(2)
		await _shot(out + "/%s.png" % String(k[1]))
	panel.toggle_tactical()
	panel.t = total * 0.55
	panel._update_scene()
	await _frames(2)
	await _shot(out + "/decor-vue-tactique.png")
	panel.toggle_tactical()
	# Détail sobre.
	UiSettings.replay_detail = "sobre"
	panel.show_replay(st, 0, rep)
	panel.playing = false
	panel.modulate.a = 1.0
	panel.t = total * 0.55
	panel._update_scene()
	await _frames(4)
	await _shot(out + "/decor-detail-sobre.png")
	UiSettings.replay_detail = "normal"
	# Siège : une nouvelle flotte Kh'thari se jette sur les assiégeants.
	var days := 0
	while not st.sieges.has(target) and days < 60:
		sim.step()
		days += 1
	var foe2 := st.spawn_ship(1, "fregate", target)
	for s in ["fregate", "fregate", "corvette"]:
		foe2.add_ship(s)
	var before := st.battle_reports.size()
	guard = 0
	while guard < 40 and st.battle_reports.size() == before:
		sim.step()
		guard += 1
	if st.battle_reports.size() > before:
		var rep2: Dictionary = st.battle_reports[-1]
		print("décor du siège : ", rep2.get("scene", {}))
		panel.show_replay(st, 0, rep2)
		panel.playing = false
		panel.modulate.a = 1.0
		panel.t = panel.day_count() * BattleReplayPanel.DAY_SECONDS * 0.5
		panel._update_scene()
		await _frames(6)
		await _shot(out + "/decor-siege.png")
	print("images de la vidéo : %d" % n)
	quit()


## Galerie du lot 3 (GALLERY=1) : la même bataille avec d'autres peuples (coques par style) et dans
## chaque terrain (nébuleuse, tempêtes, trou noir, pulsar, géante bleue…) : CAPTURE_DIR/espace-*.png.
func _gallery(panel: BattleReplayPanel, st: GameState, rep: Dictionary, out: String) -> void:
	var combos := [["vael", "choeur", "nebuleuse", "yellow"], ["teyl", "ferrocornes", "asteroides", "red"],
			["murmurants", "brisecomete", "black_hole", "black_hole"], ["ossarane", "khthari", "neutron", "neutron"],
			["choeur", "vael", "blue_giant", "blue_giant"], ["ferrocornes", "teyl", "tempete_ionique", "red"],
			["brisecomete", "murmurants", "plasma", "yellow"], ["khthari", "ossarane", "cimetiere", "white"],
			["vael", "teyl", "tempete_gravitationnelle", "yellow"]]
	var f0 := st.get_empire(0).faction_id
	var f1 := st.get_empire(1).faction_id
	for c in combos:
		st.get_empire(0).faction_id = String(c[0])
		st.get_empire(1).faction_id = String(c[1])
		var r: Dictionary = rep.duplicate(true)
		r["scene"]["terrain"] = [String(c[2])]
		r["scene"]["star"] = String(c[3])
		panel.show_replay(st, 0, r)
		panel.playing = false
		panel.modulate.a = 1.0
		panel.t = panel.day_count() * BattleReplayPanel.DAY_SECONDS * 0.42
		panel._update_scene()
		panel.queue_redraw()
		await _frames(3)
		await _shot(out + "/espace-%s-%s-%s.png" % [String(c[0]), String(c[1]), String(c[2])])
	st.get_empire(0).faction_id = f0
	st.get_empire(1).faction_id = f1


func _report_at(st: GameState, sid: int) -> Dictionary:
	for r in st.battle_reports:
		if int(r.get("system", -1)) == sid:
			return r
	return {}


func _frames(k: int) -> void:
	for _i in k:
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("capture : ", path)


func _shot_quiet(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
