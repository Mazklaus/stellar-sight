extends SceneTree
## Captures et vidéo de la vue de bataille au sol habillée (visuel des combats, lot 2) :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_replay_sol.gd
## Écrit dans CAPTURE_DIR (par défaut user://captures) : sol-*.png et les images de la vidéo dans
## CAPTURE_DIR/replay-sol-lot2/ (img_0000.png…), à assembler avec ffmpeg :
##   ffmpeg -framerate 30 -i replay-sol-lot2/img_%04d.png -pix_fmt yuv420p -vf scale=1280:-2 replay-sol-lot2.mp4
## Scénario repris de capture_ground.gd : débarquement complet sur la capitale d'un voisin, siège puis
## bataille ; la vidéo la montre à l'échelle « Bataille », puis les images fixes aux trois échelles.

const FPS := 30.0
const SPEED := 2.0


func _initialize() -> void:
	var out := OS.get_environment("CAPTURE_DIR")
	if out == "":
		out = ProjectSettings.globalize_path("user://captures")
	DirAccess.make_dir_recursive_absolute(out + "/replay-sol-lot2")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.save_path = "user://saves/capture_quicksave.json"
	main.start_with_menu = false
	root.add_child(main)
	await _frames(10)
	main.player_faction = "ossarane"
	main.game_options = {"ground": "complet", "wargoals": "actifs", "occupation": "occupation"}
	main.new_game(5151)
	await _frames(5)
	var sim: Simulation = main.simulation
	var st: GameState = sim.state
	var me: int = main.view_empire
	sim.advance(200)
	for e in st.empires:
		e.resources["materials"] = 9000
		e.resources["energy"] = 9000
		e.resources["food"] = 9000
		st.ground["rec"][str(e.id)] = 60
	for t in ["blindes_assaut", "assaut_aeroporte", "forces_speciales", "genie_siege", "debarquement"]:
		st.get_empire(me).techs[t] = true
	st.get_empire(me).tech_fx_n = -1
	for sys in st.galaxy.systems:
		st.get_empire(me).explored[sys.id] = true
	var foe := -1
	for e in st.empires:
		if e.id != me and not e.is_npc() and not e.eliminated:
			foe = e.id
			break
	for pair in [[me, foe], [foe, me]]:
		if not st.get_empire(pair[0]).contacts.has(pair[1]):
			st.get_empire(pair[0]).contacts.append(pair[1])
	if not Combat.at_war(st, me, foe):
		Combat.start_war(st, me, foe)
	var target := FactionTraits.capital_system(st, foe)
	var home := FactionTraits.capital_system(st, me)
	for g in Fleets.fleets_at(st, target, foe):
		st.fleets.erase(g.id)
	# Les régiments du joueur, à quai chez lui, puis une flotte de transports.
	var sp := Peoples.founder_of(st, me)
	for t in ["infanterie", "infanterie", "infanterie", "infanterie", "infanterie", "blindes", "blindes", "aerien", "aerien", "commandos", "genie"]:
		Ground._new_regiment(st, me, t, sp, home)
	var f := st.spawn_ship(me, "transport", home)
	for i in 3:
		f.add_ship("transport")
	f.add_ship("croiseur")
	f.fleet_name = "Ost de Thessa"
	Ground.embark(st, me, f.id)
	# Le défenseur a quelques régiments.
	for t in ["infanterie", "infanterie", "infanterie", "blindes", "blindes"]:
		Ground._new_regiment(st, foe, t, Peoples.founder_of(st, foe), target)
	sim.step()
	st.proposals = []
	main.set_process(false)
	for t in main._hud._toasts.get_children():
		t.queue_free()
	f.system_id = target
	GroundSiege.set_posture(st, f.id, "selectif")
	for i in 4:
		sim.step()
	GroundSiege._sub(st, "fort")[str(target)] = maxi(1, int(GroundSiege.fort_max(st, target) * 0.5))
	sim.submit(SimCommands.invade(me, f.id))
	sim.flush_commands()
	sim.step()
	var guard := 0
	while not Ground.battle(st, target).is_empty() and guard < 200:
		sim.step()
		guard += 1
	var reps := Ground.reports_for(st, me)
	if reps.is_empty():
		print("pas de rapport")
		quit()
		return
	var rep: Dictionary = reps[0]
	print("décor : ", rep.get("sc", {}), "  déroutes : ", rep.get("routs", []))
	var panel: GroundReplayPanel = main._hud.ground_replay
	if OS.get_environment("GALLERY") != "":
		await _gallery(panel, st, me, rep, out)
		quit()
		return
	var scale_env := OS.get_environment("SCALE")
	UiSettings.battle_scale = scale_env if scale_env != "" else "bataille"
	panel.show_replay(st, me, rep)
	panel.playing = false
	await _frames(10)
	panel.modulate.a = 1.0
	var total := panel.day_count() * GroundReplayPanel.DAY_SECONDS
	var n := 0
	var t := 0.0
	var t0 := Time.get_ticks_usec()
	if OS.get_environment("STILLS") != "":
		t = total + 1.0
	while t <= total + 0.6:
		panel.t = minf(t, total)
		panel.army.update(panel.t, panel.backdrop.tint)
		panel.queue_redraw()
		await _frames(1)
		await _shot_quiet(out + "/replay-sol-lot2/img_%04d.png" % n)
		n += 1
		t += SPEED / FPS
	print("images de la vidéo : %d (%d jours), %.1f ms par image (capture comprise)" % [n, panel.day_count(), (Time.get_ticks_usec() - t0) / 1000.0 / maxf(1, n)])
	for sc in ["escarmouche", "bataille", "grande"]:
		UiSettings.battle_scale = sc
		panel.show_replay(st, me, rep)
		panel.playing = false
		panel.modulate.a = 1.0
		for k in [[0.12, "debut"], [0.5, "milieu"], [0.97, "fin"]]:
			panel.t = total * float(k[0])
			var u0 := Time.get_ticks_usec()
			panel.army.update(panel.t, panel.backdrop.tint)
			var ms := (Time.get_ticks_usec() - u0) / 1000.0
			panel.queue_redraw()
			await _frames(3)
			await _shot(out + "/sol-%s-%s.png" % [sc, String(k[1])])
			print("  %s %s : %d figurines, mise à jour %.1f ms" % [sc, String(k[1]), panel.army.living_total(panel.t), ms])
	UiSettings.battle_scale = "bataille"
	panel.show_replay(st, me, rep)
	panel.playing = false
	panel.modulate.a = 1.0
	panel.t = total * 0.5
	panel.toggle_tactical()
	panel.queue_redraw()
	await _frames(3)
	await _shot(out + "/sol-vue-tactique.png")
	panel.toggle_tactical()
	quit()


func _frames(k: int) -> void:
	for _i in k:
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(path)
	print("capture : ", path)


func _shot_quiet(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(path)


## Galerie du lot 3 : la même bataille rejouée avec d'autres peuples, biomes et tailles de ville
## (GALLERY=1) : écrit CAPTURE_DIR/galerie-<défenseur>-<biome>.png.
func _gallery(panel: GroundReplayPanel, st: GameState, me: int, rep: Dictionary, out: String) -> void:
	var combos := [["vael", "ossarane", "continental", 18], ["ossarane", "vael", "arctic", 9],
			["choeur", "khthari", "desert", 14], ["ferrocornes", "choeur", "toxic", 7],
			["khthari", "teyl", "gaia", 20], ["brisecomete", "ferrocornes", "barren", 4],
			["teyl", "murmurants", "ocean", 12], ["murmurants", "brisecomete", "ecumenopole", 22],
			["ossarane", "ossarane", "asteroids", 2]]
	UiSettings.battle_scale = "bataille"
	for c in combos:
		var r: Dictionary = rep.duplicate(true)
		for u in r.get("units", []):
			u["sp"] = String(c[0]) if int(u["side"]) == 0 else String(c[1])
		var sc: Dictionary = r.get("sc", {})
		sc["csp"] = String(c[1])
		sc["ter"] = String(c[2])
		sc["pop"] = int(c[3])
		r["ter"] = String(c[2])
		r["sc"] = sc
		panel.show_replay(st, me, r)
		panel.playing = false
		panel.modulate.a = 1.0
		panel.t = panel.day_count() * GroundReplayPanel.DAY_SECONDS * 0.3
		panel.army.update(panel.t, panel.backdrop.tint)
		panel.queue_redraw()
		await _frames(3)
		await _shot(out + "/galerie-%s-%s.png" % [String(c[1]), String(c[2])])
		print("  galerie %s contre %s, %s, pop %d" % [c[0], c[1], c[2], c[3]])
