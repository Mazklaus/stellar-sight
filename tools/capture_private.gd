extends SceneTree
## Captures du pilier Économie privée, avec le rendu réel :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_private.gd
## Écrit les images dans le dossier donné par CAPTURE_DIR (par défaut user://captures).
## Scénario : Vael après deux ans, une douzaine de systèmes peuplés, deux compagnies (une sous
## charte), deux stations minières sous licence, une station touristique, un repaire du crime, une
## zone militaire. Onglet Privé de l'écran Commerce (haut et bas), puis le mode Économie privée de la
## lentille du commerce.


func _initialize() -> void:
	var out := OS.get_environment("CAPTURE_DIR")
	if out == "":
		out = ProjectSettings.globalize_path("user://captures")
	DirAccess.make_dir_recursive_absolute(out)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.save_path = "user://saves/capture_quicksave.json"
	main.start_with_menu = false
	root.add_child(main)
	await _frames(10)
	main.player_faction = "vael"
	main.game_options = {"private": "complete", "finance": "complete", "admin": "complete", "politics": "active", "culture": "actif"}
	main.new_game(4344)
	await _frames(5)
	var sim: Simulation = main.simulation
	var st: GameState = sim.state
	var me: int = main.view_empire
	var helper := preload("res://tests/admin_tests.gd")
	var got: Array[int] = []
	for _i in 12:
		var s: int = helper.give_system(st, me, got)
		if s >= 0:
			got.append(s)
	for c: Colony in st.colonies.values():
		if c.owner == me:
			c.population = maxi(c.population, 12)
	sim.advance(720)
	var e := st.get_empire(me)
	e.resources["energy"] = 900
	e.resources["influence"] = 300
	var en := Private._w(st, me)
	en["cap"] = 640
	en["conf"] = 68
	en["cargos"] = maxi(int(en["cargos"]), Private.cargo_need(st, me) - 1)
	en["liners"] = maxi(int(en["liners"]), Private.liner_need(st, me))
	# Deux stations minières sous licence, une station touristique.
	var sites := Private.mine_sites(st, me)
	for i in mini(2, sites.size()):
		(st.private["st"] as Dictionary)[str(sites[i])] = {"o": me, "k": "mine", "sid": st.galaxy.get_planet(sites[i]).system_id, "c": -1, "t": st.tick}
		(en["lic"] as Array).append(sites[i])
	var cap := FactionTraits.capital_system(st, me)
	for pid in st.galaxy.systems[cap].planet_ids:
		if Private.station(st, pid).is_empty():
			(st.private["st"] as Dictionary)[str(pid)] = {"o": me, "k": "resort", "sid": cap, "c": -1, "t": st.tick}
			break
	if Private.companies_of(st, me).is_empty():
		var c1 := Private.found_company(st, me, "fret", [])
		c1["pr"] = 72
		c1["ch"] = "commerce"
		var c2 := Private.found_company(st, me, "mines", [])
		c2["pr"] = 54
	if got.size() > 2:
		(st.private["crime"] as Dictionary)[str(got[2])] = {"o": me, "t": st.tick}
		(st.private["zone"] as Dictionary)[str(got[1])] = me
	var added: Array[Dictionary] = []
	Private._monthly(st, e, {}, added)
	st.relic_rev += 1
	main.set_process(false)
	for t in main._hud._toasts.get_children():
		t.queue_free()
	main._refresh_all()
	await _frames(6)
	main._empire_screens.trade_tab = "private"
	main.toggle_empire_screen("trade")
	await _frames(10)
	await _shot(out + "/ecran-prive.png")
	var sc := _find_scroll(main)
	if sc != null:
		sc.scroll_vertical = 100000
		await _frames(6)
		await _shot(out + "/ecran-prive-bas.png")
	main.toggle_empire_screen("trade")
	await _frames(4)
	main._hud.set_lens("private")
	main._view.lens = "private"
	main._view.queue_redraw()
	await _frames(8)
	await _shot(out + "/lentille-privee.png")
	quit()


func _find_scroll(n: Node) -> ScrollContainer:
	var best: ScrollContainer = null
	for c in n.find_children("*", "ScrollContainer", true, false):
		var s := c as ScrollContainer
		if s.is_visible_in_tree() and (best == null or s.size.x > best.size.x):
			best = s
	return best


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(path)
	print("capture : ", path)
