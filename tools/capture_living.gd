extends SceneTree
## Capture d'un monde vivant dans la vue système (fiche et actions) et des feuilles sur la carte, avec le
## rendu réel :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_living.gd
## Écrit les images dans le dossier donné par CAPTURE_DIR (par défaut user://captures).
## Scénario : Lignées d'Ossarane, mondes vivants fréquents. Le premier monde vivant est colonisé par le
## joueur et lui est Bienveillant, avec une demande en cours ; les autres sont connus, l'un d'eux Méfiant.


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
	var st := GameState.create(2026, 150, 1800.0, "ossarane", {"ai_level": "", "living": "frequents"})
	main._start(st)
	main.game_in_progress = true
	var me := 0
	var e := st.get_empire(me)
	for r in ["materials", "energy", "influence", "crystals", "food"]:
		e.resources[r] = 6000
	var ids := LivingWorlds.ids(st)
	var pid: int = ids[0]
	var w := LivingWorlds.world(st, pid)
	w["t"] = "maternel"
	var c := Colony.new()
	c.planet_id = pid
	c.owner = me
	c.kind = Colony.KIND_COLONY
	c.days_left = 0
	c.population = 7
	st.colonies[pid] = c
	st.rebuild_ownership()
	for i in ids.size():
		(LivingWorlds.world(st, int(ids[i]))["known"] as Dictionary)[str(me)] = 1
		LivingWorlds.set_mood(st, int(ids[i]), me, [58, -22, 12, 80][i % 4])
	(w["deep"] as Dictionary)[str(me)] = 1
	w["req"] = {"k": "repos", "e": me}
	LivingWorlds.touch(st)
	for x in ids:
		e.explored[LivingWorlds.sys_of(st, int(x))] = true
	main._refresh_all()
	main.set_process(false)
	main.open_system_view(LivingWorlds.sys_of(st, pid), pid)
	await _frames(30)
	await _shot(out + "/systeme-monde-vivant.png")
	main.close_system_view()
	await _frames(5)
	main._camera.position = st.galaxy.systems[LivingWorlds.sys_of(st, pid)].position
	main._camera.zoom = Vector2(1.8, 1.8)
	main._view.queue_redraw()
	await _frames(20)
	await _shot(out + "/carte-mondes-vivants.png")
	quit()


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(path)
	print("capture : ", path)
