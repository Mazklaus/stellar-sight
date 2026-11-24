extends SceneTree
## Captures du pilier combat au sol et armées, avec le rendu réel, et la vidéo de la vue de bataille au sol :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_ground.gd
## Écrit les images dans CAPTURE_DIR (par défaut user://captures) ; les images de la vidéo vont dans
## CAPTURE_DIR/replay-sol/ (img_0000.png…), à assembler avec ffmpeg :
##   ffmpeg -framerate 30 -i replay-sol/img_%04d.png -pix_fmt yuv420p -vf scale=1280:-2 replay-sol.mp4
## Scénario : Ossarane (joueur), combat au sol complet. Une flotte de transports débarque infanterie,
## blindés, aérien et forces spéciales sur la capitale d'un voisin en guerre, défendue par sa milice et
## ses régiments ; la bataille se joue jusqu'au bout, puis on la revoit.

const FPS := 30.0
const SPEED := 2.0


func _initialize() -> void:
	var out := OS.get_environment("CAPTURE_DIR")
	if out == "":
		out = ProjectSettings.globalize_path("user://captures")
	DirAccess.make_dir_recursive_absolute(out + "/replay-sol")
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
	for t in ["blindes_assaut", "assaut_aeroporte", "genie_siege", "debarquement"]:
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
	for t in ["infanterie", "infanterie", "infanterie", "infanterie", "blindes", "blindes", "aerien", "commandos", "genie"]:
		Ground._new_regiment(st, me, t, sp, home)
	var f := st.spawn_ship(me, "transport", home)
	for i in 3:
		f.add_ship("transport")
	f.add_ship("croiseur")
	f.fleet_name = "Ost de Thessa"
	Ground.embark(st, me, f.id)
	# Le défenseur a quelques régiments.
	for t in ["infanterie", "infanterie", "blindes"]:
		Ground._new_regiment(st, foe, t, Peoples.founder_of(st, foe), target)
	sim.step()
	st.proposals = []
	main.set_process(false)
	for t in main._hud._toasts.get_children():
		t.queue_free()
	# 1. Fiche de flotte avec ses régiments, à quai.
	main.select_fleet(f.id)
	main._go_to_system(home)
	main._refresh_all()
	await _frames(20)
	await _shot(out + "/fiche-flotte-regiments.png")
	# 2. Écran du système : lever un régiment.
	main.open_system_view(home, st.get_empire(me).capital_planet)
	await _frames(12)
	await _scroll_to(main, "Lever un régiment")
	await _shot(out + "/systeme-recrutement.png")
	main.close_system_view()
	await _frames(4)
	# 3. Siège puis débarquement.
	f.system_id = target
	GroundSiege.set_posture(st, f.id, "selectif")
	for i in 4:
		sim.step()
	main.select_fleet(f.id)
	main._go_to_system(target)
	main._refresh_all()
	await _frames(12)
	await _shot(out + "/siege-fortifications.png")
	GroundSiege._sub(st, "fort")[str(target)] = 0
	sim.submit(SimCommands.invade(me, f.id))
	sim.flush_commands()
	sim.step()
	main._refresh_all()
	await _frames(10)
	main.toggle_empire_screen("armies")
	await _frames(12)
	await _shot(out + "/ecran-armees-debarquement.png")
	main.toggle_empire_screen("armies")
	await _frames(4)
	var guard := 0
	while not Ground.battle(st, target).is_empty() and guard < 200:
		sim.step()
		guard += 1
	main._refresh_all()
	main._view.queue_redraw()
	await _frames(6)
	main.toggle_empire_screen("armies")
	await _frames(12)
	await _shot(out + "/ecran-armees-rapport.png")
	main.toggle_empire_screen("armies")
	await _frames(4)
	# 4. La vue de bataille au sol, image par image.
	var reps := Ground.reports_for(st, me)
	if reps.is_empty():
		print("pas de rapport")
		quit()
		return
	var rep: Dictionary = reps[0]
	var panel: GroundReplayPanel = main._hud.ground_replay
	panel.show_replay(st, me, rep)
	panel.playing = false
	await _frames(10)
	panel.modulate.a = 1.0
	var total := panel.day_count() * GroundReplayPanel.DAY_SECONDS
	var n := 0
	var t := 0.0
	while t <= total + 0.6:
		panel.t = minf(t, total)
		panel.queue_redraw()
		await _frames(1)
		await _shot_quiet(out + "/replay-sol/img_%04d.png" % n)
		n += 1
		t += SPEED / FPS
	panel.t = total * 0.45
	panel.queue_redraw()
	await _frames(2)
	await _shot(out + "/vue-bataille-sol.png")
	print("images de la vidéo : %d (%d jours)" % [n, panel.day_count()])
	quit()


func _scroll_to(main: Node, text: String) -> void:
	var l := _find_label(main, text)
	if l == null:
		# Refonte : la section peut être dans un autre volet de la fiche d'empire, ou dans un autre onglet.
		var es: EmpireScreens = main._empire_screens
		if es.current == "diplomacy" and es.diplo_tab == "empires":
			for pane: String in ["deal", "war", "relation"]:
				es.set_diplo_pane(pane)
				await _frames(4)
				l = _find_label(main, text)
				if l != null:
					break
		if l == null:
			for addr: String in ["diplomacy:league", "diplomacy:neighbors", "diplomacy:assembly", "diplomacy:empires"]:
				es.show_address(addr)
				await _frames(8)
				l = _find_label(main, text)
				if l != null:
					break
	if l == null:
		return
	var sc: Node = l.get_parent()
	while sc != null and not sc is ScrollContainer:
		sc = sc.get_parent()
	if sc == null:
		return
	var s := sc as ScrollContainer
	s.scroll_vertical = int(l.global_position.y - s.global_position.y) + s.scroll_vertical - 200
	await _frames(6)


func _find_label(n: Node, text: String) -> Control:
	for c in n.find_children("*", "", true, false):
		if c is Label and (c as Label).is_visible_in_tree() and (c as Label).text.to_upper().contains(text.to_upper()):
			return c
		if c is Button and (c as Button).is_visible_in_tree() and (c as Button).text.to_upper().contains(text.to_upper()):
			return c
	return null


func _frames(k: int) -> void:
	for _i in k:
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(path)
	print("capture : ", path)


func _shot_quiet(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(path)
