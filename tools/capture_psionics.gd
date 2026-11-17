extends SceneTree
## Capture de l'écran Songe (pouvoirs psioniques) et de la lentille psionique, avec le rendu réel :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_psionics.gd
## Écrit les images dans le dossier donné par CAPTURE_DIR (par défaut user://captures).
## Scénario : Vael, pouvoirs psioniques complets. Les technologies du pilier, L'Éveil, un Collège à la
## capitale, de la Résonance, le Songe ouvert, un pacte avec le Miroir tendre, et un Apaisement en cours.


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
	var st := GameState.create(2026, 150, 1800.0, "vael", {"ai_level": "", "psionics": "complet"})
	main._start(st)
	main.game_in_progress = true
	var me := 0
	var e := st.get_empire(me)
	for t in ["theorie_psionique", "telepathie", "ecrans_psychiques", "precognition", "ouverture_songe", "navigation_songe"]:
		e.techs[t] = true
	SimCommands.apply(st, SimCommands.psi_act(me, "path"))
	var c: Colony = st.colonies[e.capital_planet]
	c.buildings.append("college_sensitifs")
	Psionics.add_resonance(st, me, 400)
	e.resources["knowledge"] = 5000
	SimCommands.apply(st, SimCommands.psi_act(me, "open"))
	Psionics.sub(st, "offer")[str(me)] = {"p": "miroir", "until": st.tick + 100}
	SimCommands.apply(st, SimCommands.psi_act(me, "pact", {"accept": true}))
	PsionicsDream.pact(st, me)["favor"] = 42
	var sid := st.galaxy.get_planet(e.capital_planet).system_id
	SimCommands.apply(st, SimCommands.psi_act(me, "power", {"power": "apaisement", "target": sid}))
	main._refresh_all()
	main.set_process(false)
	main.toggle_empire_screen("psionics")
	await _frames(30)
	await _shot(out + "/ecran-songe.png")
	main.toggle_empire_screen("psionics")
	await _frames(5)
	main._hud.set_lens("psionics")
	main._view.lens = "psionics"
	main._camera.position = st.galaxy.systems[sid].position
	main._camera.zoom = Vector2(0.7, 0.7)
	main._view.queue_redraw()
	await _frames(20)
	await _shot(out + "/lentille-psionique.png")
	quit()


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(path)
	print("capture : ", path)
