extends SceneTree
## Captures de la recherche avec le rendu réel :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_research.gd
## Écrit les images dans CAPTURE_DIR (par défaut user://captures) : l'arbre du Chœur Éternel en début
## de partie (une hérésie choisie), puis en milieu de partie avec une file, et l'arbre de Vael.


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

	var st := GameState.create(2026, 150, 1800.0, "choeur", {"ai_level": "normal"})
	main._start(st)
	main.game_in_progress = true
	Research.grant(st, 0, ["canons_masse", "litanies"])
	Research.apply_queue(st, 0, "hydroponie", false)
	Research.apply_queue(st, 0, "scriptorium", false)
	st.get_empire(0).research_progress = 70
	main._refresh_all()
	main.toggle_empire_screen("research")
	main._empire_screens.research_selected = "genetique"
	main._empire_screens.show_screen("research")
	await _frames(30)
	await _shot(out + "/recherche-choeur-debut.png")
	main.close_empire_screen()

	var sim: Simulation = main.simulation
	sim.advance(30 * 120)
	var me := st.get_empire(0)
	Research.grant(st, 0, ["extraction", "fusion_compacte", "logistique", "blindage_composite", "tetes_chercheuses",
			"lentilles", "debarquement", "propulseurs", "cales_rapides", "adaptation", "administration", "rhetorique"])
	me.research_queue.clear()
	for t in ["boucliers_phase", "coques_lourdes", "serviteurs", "mondes_toxiques"]:
		if Research.check_queue(st, 0, t) == "":
			Research.apply_queue(st, 0, t, false)
	me.research_progress = Research.cost(st, 0, me.research_queue[0]) / 3 if not me.research_queue.is_empty() else 0
	main._refresh_all()
	main.toggle_empire_screen("research")
	main._empire_screens.research_selected = "esprits_lies"
	main._empire_screens.show_screen("research")
	await _frames(30)
	await _shot(out + "/recherche-choeur-milieu.png")
	main.close_empire_screen()

	var sv := GameState.create(2026, 150, 1800.0, "vael", {"ai_level": "normal"})
	main._start(sv)
	main.game_in_progress = true
	Research.grant(sv, 0, ["rhetorique", "assemblees", "universites", "medecine"])
	Research.apply_queue(sv, 0, "chancelleries", false)
	Research.apply_queue(sv, 0, "xenodiplomatie", false)
	main._refresh_all()
	main.toggle_empire_screen("research")
	main._empire_screens.research_selected = "xenodiplomatie"
	main._empire_screens.show_screen("research")
	await _frames(30)
	await _shot(out + "/recherche-vael.png")

	# Une partie de spectateur avancée : où en sont les IA ?
	var sp := Simulation.new(GameState.create(7, 150, 1800.0, "", {"spectator": true, "ai_level": "normal"}))
	for m in range(1, 241):
		sp.advance(30)
		if m % 60 == 0:
			var parts := PackedStringArray()
			for e in sp.state.empires:
				parts.append("%s %d tech. (ère %d, %+d Savoir/mois)" % [e.short_name(), e.techs.size(), Research.current_era(sp.state, e.id),
						int(Economy.empire_income(sp.state, e.id)["net"]["knowledge"])])
			print("mois %d (%.2f h) : %s" % [m, m * 15.0 / 3600.0, ", ".join(parts)])
	quit()


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(path)
	print("capture : ", path)
