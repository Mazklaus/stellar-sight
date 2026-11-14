extends SceneTree
## Captures du lot 2 de la religion (zèle, hérésies, missions, croisade, Culte du Je), avec le rendu réel :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_faith_wars.gd
## Écrit les images dans le dossier donné par CAPTURE_DIR (par défaut user://captures).
## Scénario 1 : le Chœur (joueur, foi Code saint) après un an ; une hérésie de sa Liturgie (concile
## possible), un schisme que Vael a adopté (croisade possible), des missionnaires étrangers chez lui.
## Scénario 2 : l'Essaim Kh'thari et ses drones qui pensent « je ».


func _initialize() -> void:
	var out := OS.get_environment("CAPTURE_DIR")
	if out == "":
		out = ProjectSettings.globalize_path("user://captures")
	DirAccess.make_dir_recursive_absolute(out)
	await _choeur(out)
	await _khthari(out)
	quit()


func _start(faction: String) -> Node:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.save_path = "user://saves/capture_quicksave.json"
	main.start_with_menu = false
	root.add_child(main)
	await _frames(10)
	main.player_faction = faction
	main.game_options = {"faiths": "actives", "peoples": "actifs"}
	main.new_game(4242)
	await _frames(5)
	return main


func _id_of(st: GameState, faction: String) -> int:
	for e in st.empires:
		if e.faction_id == faction:
			return e.id
	return -1


func _choeur(out: String) -> void:
	var main: Node = await _start("choeur")
	var sim: Simulation = main.simulation
	var st: GameState = sim.state
	var me: int = main.view_empire
	var fc := Faiths.founded_by(st, me)
	var dch := Faiths.default_choice(st, me, fc)
	if int(Faiths.faith(st, fc)["pending"]) > 0:
		Faiths.choose(st, fc, String(dch["nature"]), dch["doctrines"], String(dch["precept"]))
	sim.advance(360)
	var v := _id_of(st, "vael")
	var t := _id_of(st, "teyl")
	var none: Array[Dictionary] = []
	# Une hérésie chez les Teyl, un schisme adopté par Vael.
	var tc: Colony = st.colonies[st.get_empire(t).capital_planet]
	tc.faith = {fc: tc.population}
	FaithWars.spawn_heresy(st, fc, tc.planet_id, none)
	var vc: Colony = st.colonies[st.get_empire(v).capital_planet]
	vc.faith = {fc: vc.population}
	var sch := FaithWars.spawn_heresy(st, fc, vc.planet_id, none)
	vc.faith = {sch: vc.population}
	FaithWars._schism_month(st, sch, none)
	st.faiths["state"][str(v)] = sch
	for e in st.empires:
		if e.id != me and not st.get_empire(me).contacts.has(e.id):
			st.get_empire(me).contacts.append(e.id)
		if e.id != me and not e.contacts.has(me):
			e.contacts.append(me)
	for s in st.galaxy.systems:
		st.get_empire(me).explored[s.id] = true
	# Une mission en cours, et des missionnaires de Vael chez nous.
	var targets := FaithWars.mission_targets(st, me, fc, 3)
	if not targets.is_empty():
		FaithWars.mission(st, me, int(targets[0]))
	var cap := FactionTraits.capital_system(st, me)
	st.faiths["missions"]["list"].append({"by": v, "sid": cap, "fid": sch, "end": st.tick + 300})
	FaithWars.add_zeal(st, fc, 12)
	st.get_empire(me).resources["knowledge"] = 900
	st.get_empire(me).resources["influence"] = 400
	Relics.touch(st)
	main.set_process(false)
	for x in main._hud._toasts.get_children():
		x.queue_free()
	main._refresh_all()
	await _frames(6)
	main.toggle_empire_screen("faith")
	await _frames(10)
	await _shot(out + "/ecran-foi-lot2.png")
	# Défilement vers les grandes fois (concile, réécriture, croisade).
	var sc := _find_scroll(main._empire_screens._content)
	if sc != null:
		sc.scroll_vertical = 520
		await _frames(6)
		await _shot(out + "/ecran-foi-chef.png")
	main.queue_free()
	await _frames(4)


func _khthari(out: String) -> void:
	var main: Node = await _start("khthari")
	var sim: Simulation = main.simulation
	var st: GameState = sim.state
	var me: int = main.view_empire
	sim.advance(360)
	var n := 0
	for pid in st.sorted_colony_ids():
		var c: Colony = st.colonies[pid]
		if c.owner == me and c.is_colony() and c.is_established():
			st.faiths["je"][str(pid)] = {"n": [5, 2, 7][n % 3], "tol": n == 1}
			n += 1
			if n >= 3:
				break
	main.set_process(false)
	for x in main._hud._toasts.get_children():
		x.queue_free()
	main._refresh_all()
	await _frames(6)
	main.toggle_empire_screen("faith")
	await _frames(10)
	await _shot(out + "/ecran-foi-ruche.png")
	main.queue_free()
	await _frames(4)


func _find_scroll(n: Node) -> ScrollContainer:
	if n is ScrollContainer:
		return n
	for c in n.get_children():
		var r := _find_scroll(c)
		if r != null:
			return r
	return null


func _frames(k: int) -> void:
	for _i in k:
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(path)
	print("capture : ", path)
