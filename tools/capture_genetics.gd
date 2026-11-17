extends SceneTree
## Capture de l'écran Génome (ingénierie des espèces), avec le rendu réel :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_genetics.gd
## Écrit les images dans le dossier donné par CAPTURE_DIR (par défaut user://captures).
## Scénario : Vael, ingénierie complète, populations mêlées. Quatre technologies du pilier, l'espèce
## fondatrice déjà Doués et Adaptables, un programme Industrieux en cours, des Ossarane qui vivent
## à la capitale (greffe et lignée possibles).


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
	var st := GameState.create(2026, 150, 1800.0, "vael", {"ai_level": "", "genetics": "complete", "peoples": "actifs"})
	main._start(st)
	main.game_in_progress = true
	var me := 0
	var e := st.get_empire(me)
	for t in ["genetique", "reprogrammation", "resequencage", "acclimatation_glandulaire", "implants_neuraux", "evolution_dirigee"]:
		e.techs[t] = true
	e.resources["knowledge"] = 900
	Genetics._set_genome(st, e, "vael", {"add": ["g_doues", "g_adaptables"]})
	var c: Colony = st.colonies[e.capital_planet]
	c.population += 6
	c.species["ossarane"] = 6
	Peoples.refresh(st)
	SimCommands.apply(st, SimCommands.gen_act(me, "mod", {"fid": "vael", "add": ["g_frugaux"]}))
	main._refresh_all()
	main.set_process(false)
	main.toggle_empire_screen("genome")
	await _frames(30)
	await _shot(out + "/ecran-genome.png")
	quit()


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(path)
	print("capture : ", path)
