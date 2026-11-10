extends SceneTree
## Captures des ères IV et V d'Économie et de Société avec le rendu réel :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_late_eras.gd
## Écrit les images dans CAPTURE_DIR (par défaut user://captures) : l'arbre de recherche en fin de
## partie (Économie d'abondance, technologie ultime), puis un système transformé (capitale en
## écuménopole, monde-jardin voisin) avec les ordres de terraformation et de 2e rang.


func _initialize() -> void:
	var out := OS.get_environment("CAPTURE_DIR")
	if out == "":
		out = ProjectSettings.globalize_path("user://captures")
	DirAccess.make_dir_recursive_absolute(out)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.save_path = "user://saves/capture_quicksave.json"
	main.start_with_menu = false
	root.add_child(main)
	await _frames(30)

	var st := GameState.create(2026, 150, 1800.0, "vael", {"ai_level": "normal"})
	main._start(st)
	main.game_in_progress = true
	st.tick = 18000
	var me := st.get_empire(0)
	for r in ["materials", "energy", "influence", "crystals", "food"]:
		me.resources[r] = 6000
	# Tout l'arbre jusqu'à l'ère IV, et une partie de l'ère V.
	var keep := ["abondance", "symbiose", "nexus_savoir", "replicateurs", "spatioports", "adaptation_totale"]
	for tid in Research.visible_ids(me.faction()):
		var t := Research.tech(tid)
		if keep.has(tid) or (int(t["era"]) == 5 and String(t["domain"]) in ["armement", "genie"]):
			continue
		Research.complete(st, 0, tid)
	Research.apply_queue(st, 0, "nexus_savoir", false)
	main._refresh_all()
	main.toggle_empire_screen("research")
	main._empire_screens.research_selected = "abondance"
	main._empire_screens.show_screen("research")
	await _frames(40)
	await _shot(out + "/recherche-ere-v.png")
	main._empire_screens.research_selected = "arcologie_planetaire"
	main._empire_screens.show_screen("research")
	await _frames(20)
	await _shot(out + "/recherche-arcologie.png")
	main.close_empire_screen()

	# La capitale devient une écuménopole, une voisine un monde-jardin.
	var home := me.capital_planet
	var sys := st.galaxy.get_planet(home).system_id
	var c: Colony = st.colonies[home]
	c.population = 30
	c.buildings = ["capitale", "ferme_verticale", "mine_profonde", "academie", "prefecture"] as Array[String]
	st.override_planet(home, {"type": "ecumenopole"})
	var garden := -1
	for pid in st.galaxy.systems[sys].planet_ids:
		var p := st.galaxy.get_planet(pid)
		if pid != home and p.type in ["desert", "arctic", "toxic", "barren", "continental"] and not st.colonies.has(pid):
			var g := Colony.new()
			g.planet_id = pid
			g.owner = 0
			g.population = 6
			g.buildings = ["complexe_minier", "centrale_fusion"] as Array[String]
			st.add_colony(g)
			if garden < 0:
				garden = pid
				st.override_planet(pid, {"type": "gaia"})
			else:
				g.construction = "terraformeur"
				g.construction_days = 200
	main._refresh_all()
	main.open_system_view(sys)
	await _frames(120)
	main._system_screen.select_planet(home)
	await _frames(30)
	await _shot(out + "/systeme-ecumenopole.png")
	if garden >= 0:
		main._system_screen.select_planet(garden)
		await _frames(30)
		await _shot(out + "/systeme-monde-jardin.png")
	quit(0)


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(path)
	print("capture : ", path)
