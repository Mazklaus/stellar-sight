extends SceneTree
## Capture de l'onglet Mégastructures de l'écran des Merveilles, et des arcs sur la carte, avec le rendu réel :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_megastructures.gd
## Écrit les images dans le dossier donné par CAPTURE_DIR (par défaut user://captures).
## Scénario : Lignées d'Ossarane, mégastructures complètes, ruines nombreuses. Un Essaim de Dyson achevé
## autour de la capitale, un Ascenseur orbital en chantier, un Vaisseau-architecte libre, l'ère III connue.


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
	var st := GameState.create(2026, 150, 1800.0, "ossarane", {"ai_level": "", "megastructures": "completes", "mega_ruins": "beaucoup"})
	main._start(st)
	main.game_in_progress = true
	var me := 0
	var e := st.get_empire(me)
	for r in ["materials", "energy", "influence", "crystals", "food"]:
		e.resources[r] = 6000
	Research.grant(st, me, ["architectes_stellaires", "essaim_dyson", "anneau_orbital", "forge_noyau", "siphon_geante"])
	var sid := st.galaxy.get_planet(e.capital_planet).system_id
	var id := int(st.megas["next"])
	st.megas["next"] = id + 2
	Megastructures.entries(st)[str(id)] = {"id": id, "k": "essaim_dyson", "o": me, "s": sid, "p": -1, "st": 4, "w": 0}
	Megastructures.entries(st)[str(id + 1)] = {"id": id + 1, "k": "ascenseur_orbital", "o": me, "s": sid, "p": e.capital_planet, "st": 1, "w": 140}
	st.spawn_ship(me, "architecte", sid)
	Megastructures.touch(st)
	Megastructures._kardashev(st, me, [])
	main._refresh_all()
	main.set_process(false)
	main.toggle_empire_screen("wonders")
	await _frames(5)
	main._empire_screens.show_screen("megas")
	await _frames(30)
	await _shot(out + "/ecran-megastructures.png")
	main.close_empire_screen()
	await _frames(5)
	main._camera.position = st.galaxy.systems[sid].position
	main._camera.zoom = Vector2(0.9, 0.9)
	main._view.queue_redraw()
	await _frames(20)
	await _shot(out + "/carte-megastructures.png")
	quit()


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(path)
	print("capture : ", path)
