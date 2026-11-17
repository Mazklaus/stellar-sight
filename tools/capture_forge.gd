extends SceneTree
## Capture de l'onglet Forge des mondes de l'écran des Merveilles, d'un monde façonné dans la vue système
## et des repères sur la carte, avec le rendu réel :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_forge.gd
## Écrit les images dans le dossier donné par CAPTURE_DIR (par défaut user://captures).
## Scénario : Lignées d'Ossarane, Forge complète, mondes-reliquaires nombreux, mégastructures complètes.
## Une coquille et un monde-noyau dans le système natal, une ceinture en agglomération, un Vaisseau-
## architecte libre, de la Masse, toutes les technologies de la Forge.


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
	var st := GameState.create(2026, 150, 1800.0, "ossarane", {"ai_level": "", "megastructures": "completes", "worldforge": "complete", "forge_ancients": "beaucoup"})
	main._start(st)
	main.game_in_progress = true
	var me := 0
	var e := st.get_empire(me)
	for r in ["materials", "energy", "influence", "crystals", "food"]:
		e.resources[r] = 6000
	Research.grant(st, me, ["architectes_stellaires", "agglomeration", "compression_gravitationnelle", "demantelement", "mondes_coquilles", "mondes_sur_mesure", "moteurs_planetaires"])
	var sid := st.galaxy.get_planet(e.capital_planet).system_id
	var free: Array[int] = []
	for pid in st.galaxy.systems[sid].planet_ids:
		if not st.colonies.has(pid):
			free.append(pid)
	var shell := -1
	if free.size() >= 1:
		shell = free[0]
		WorldForge.reshape(st, shell, "coquille", 4)
		WorldForge.mark_world(st, shell, "coquille", me)
		WorldForge.world(st, shell)["integ"] = 85
		WorldForge._stat(st, me, "made", 1)
	if free.size() >= 2:
		WorldForge.reshape(st, free[1], "noyau", 3)
		WorldForge.mark_world(st, free[1], "noyau", me)
		WorldForge.world(st, free[1])["eng"] = 1
		WorldForge._stat(st, me, "made", 1)
	if free.size() >= 3:
		st.override_planet(free[2], {"type": "asteroids", "size": 1})
		var id := int(st.forge["next"])
		st.forge["next"] = id + 1
		WorldForge.jobs(st)[str(id)] = {"id": id, "op": "agglomerer", "o": me, "s": sid, "p": free[2], "w": 610, "tot": 900, "a": "", "for": -1, "b": me}
	WorldForge.add_mass(st, me, 74)
	st.spawn_ship(me, "architecte", sid)
	WorldForge.touch(st)
	main._refresh_all()
	main.set_process(false)
	main.toggle_empire_screen("wonders")
	await _frames(5)
	main._empire_screens.show_screen("forge")
	await _frames(30)
	await _shot(out + "/ecran-forge.png")
	main.close_empire_screen()
	await _frames(5)
	if free.size() >= 2:
		main.open_system_view(sid, free[1])
		await _frames(30)
		await _shot(out + "/systeme-forge.png")
		main.close_system_view()
		await _frames(5)
	main._camera.position = st.galaxy.systems[sid].position
	main._camera.zoom = Vector2(0.9, 0.9)
	main._view.queue_redraw()
	await _frames(20)
	await _shot(out + "/carte-forge.png")
	quit()


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(path)
	print("capture : ", path)
