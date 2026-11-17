extends SceneTree
## Capture de l'onglet L'Échelle de l'écran des Victoires, avec le rendu réel :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_kardashev.gd
## Écrit les images dans le dossier donné par CAPTURE_DIR (par défaut user://captures).
## Scénario : Lignées d'Ossarane, échelle complète. Une Sphère de Dyson achevée autour de la capitale,
## le verrou du type I levé, une prérogative prise et la suivante à choisir ; les rivaux sont connus.


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
	var st := GameState.create(2026, 150, 1800.0, "ossarane", {"ai_level": "", "megastructures": "completes", "mega_ruins": "aucune", "kardashev": "complete"})
	main._start(st)
	main.game_in_progress = true
	var me := 0
	var e := st.get_empire(me)
	Research.grant(st, me, ["architectes_stellaires", "essaim_dyson", "fusion_compacte"])
	var cap: Colony = st.colonies[e.capital_planet]
	for bid in ["ferme_hydroponique", "centrale_fusion", "complexe_minier", "forum"]:
		if not cap.buildings.has(bid):
			cap.buildings.append(bid)
	var sid := st.galaxy.get_planet(e.capital_planet).system_id
	var id := int(st.megas["next"])
	st.megas["next"] = id + 1
	Megastructures.entries(st)[str(id)] = {"id": id, "k": "sphere_dyson", "o": me, "s": sid, "p": -1, "st": Megastructures.stage_count("sphere_dyson"), "w": 0}
	Megastructures.touch(st)
	for o in st.empires:
		if o.id != me and not o.is_npc():
			e.contacts.append(o.id)
			Kardashev.sub(st, "k")[str(o.id)] = 70 + 9 * o.id
	e.contacts.sort()
	Kardashev.monthly(st, [])
	var off := Kardashev.offer(st, me)
	if not off.is_empty():
		Kardashev.apply(st, me, "perk", {"id": "climat_maitrise"})
	main._refresh_all()
	main.set_process(false)
	main.toggle_empire_screen("victory")
	await _frames(5)
	main._empire_screens.show_screen("kardashev")
	await _frames(30)
	await _shot(out + "/ecran-kardashev.png")
	quit()


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(path)
	print("capture : ", path)
