extends SceneTree
## Captures de l'écran Chantier (éditeur de vaisseaux) avec le rendu réel :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_shipyard.gd
## Écrit dans CAPTURE_DIR (par défaut user://captures) : un modèle d'origine, un modèle conçu sur une
## coque de croiseur (comparé à sa version précédente), et une coque de peuple (martyr du Chœur).


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
	Research.grant(st, 0, ["coques_lourdes", "torpilles", "debarquement", "charge_sacree", "bombardes"])
	main._refresh_all()
	main.toggle_empire_screen("shipyard")
	var screens: EmpireScreens = main._empire_screens
	screens.shipyard.select_design("croiseur")
	await _frames(20)
	await _shot(out + "/chantier-origine.png")

	var spec := {"name": "Lance d'aurore", "hull": "croiseur", "modules": ["lanceur_missiles", "lanceur_missiles", "plaques_blindage"], "line": "line", "target": "largest"}
	SimCommands.apply(st, SimCommands.save_design(0, spec))
	spec["modules"] = ["lanceur_missiles", "lanceur_missiles", "batterie_rayons", "plaques_blindage", "bouclier"]
	spec["previous"] = "m0_0"
	SimCommands.apply(st, SimCommands.save_design(0, spec))
	screens.shipyard.select_design("m0_1")
	screens.shipyard.draft["slots"] = screens.shipyard._assign_slots("croiseur", ["lanceur_missiles", "lanceur_missiles", "tube_torpilles", "batterie_rayons", "plaques_blindage", "plaques_blindage", "bouclier", "propulseurs"])
	screens.shipyard.slot_index = 2
	screens.shipyard._refresh_all()
	await _frames(20)
	await _shot(out + "/chantier-modele.png")

	Research.grant(st, 0, ["artillerie", "lances_stellaires", "boucliers_phase", "chasse", "canons_rail", "obusiers"])
	screens.shipyard.new_draft("titan")
	screens.shipyard.auto_design_draft("ligne")
	screens.shipyard.draft["name"] = "Soleil de l'Hymne"
	screens.shipyard._refresh_all()
	await _frames(20)
	await _shot(out + "/chantier-titan.png")

	Research.grant(st, 0, ["leviathans", "nefs_mondes", "canons_singularite", "matiere_programmable"])
	screens.shipyard.new_draft("nef_monde")
	screens.shipyard.auto_design_draft("ligne")
	screens.shipyard.draft["name"] = "Patrie errante"
	screens.shipyard._refresh_all()
	await _frames(20)
	await _shot(out + "/chantier-nef-monde.png")

	screens.shipyard.new_draft("martyr")
	screens.shipyard.place_module("plaques_blindage")
	await _frames(20)
	await _shot(out + "/chantier-coque-peuple.png")
	quit()


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(path)
	print("capture : ", path)
