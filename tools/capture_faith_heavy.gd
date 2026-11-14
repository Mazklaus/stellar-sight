extends SceneTree
## Captures du lot 4 de la religion (natures SF lourdes, héros de foi), avec le rendu réel :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_faith_heavy.gd
## Écrit les images dans le dossier donné par CAPTURE_DIR (par défaut user://captures).
## Le Chœur (joueur) après un an ; sa foi prend tour à tour les natures lourdes, et l'écran Foi
## montre le bloc de la nature et celui des héros de foi.

const NATURES := ["dieu_en_chantier", "entropisme", "astres_vivants", "chronolatrie"]


func _initialize() -> void:
	var out := OS.get_environment("CAPTURE_DIR")
	if out == "":
		out = ProjectSettings.globalize_path("user://captures")
	DirAccess.make_dir_recursive_absolute(out)
	for n in NATURES:
		await _shot_nature(out, n)
	quit()


func _shot_nature(out: String, nat: String) -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.save_path = "user://saves/capture_quicksave.json"
	main.start_with_menu = false
	root.add_child(main)
	await _frames(10)
	main.player_faction = "choeur"
	main.game_options = {"faiths": "actives", "peoples": "actifs"}
	main.new_game(4242)
	await _frames(5)
	var sim: Simulation = main.simulation
	var st: GameState = sim.state
	var me: int = main.view_empire
	var fc := Faiths.founded_by(st, me)
	var dch := Faiths.default_choice(st, me, fc)
	if int(Faiths.faith(st, fc)["pending"]) > 0:
		Faiths.choose(st, fc, nat, dch["doctrines"], String(dch["precept"]))
	else:
		Faiths.faith(st, fc)["nature"] = nat
		FaithNatures.on_chosen(st, fc)
	sim.advance(360)
	for s in st.galaxy.systems:
		st.get_empire(me).explored[s.id] = true
	st.get_empire(me).resources["influence"] = 400
	st.faiths["state"][str(me)] = fc
	if nat == "dieu_en_chantier":
		FaithNatures.fdat(st, fc)["stage"] = 2
	if nat == "entropisme":
		FaithNatures.fdat(st, fc)["clock"] = 37
	var cand := Heroes.make_candidate(st, me, "orateur", ["capture_voc"])
	cand["amb"] = "foi"
	var hid := Heroes.recruit(st, me, cand)
	st.heroes[hid]["post"] = "council"
	Relics.touch(st)
	main.set_process(false)
	for x in main._hud._toasts.get_children():
		x.queue_free()
	main._refresh_all()
	await _frames(6)
	main.toggle_empire_screen("faith")
	await _frames(10)
	var sc := _find_scroll(main._empire_screens._content)
	if sc != null:
		sc.scroll_vertical = 330
		await _frames(6)
	await _shot(out + "/ecran-foi-lourde-%s.png" % nat)
	main.queue_free()
	await _frames(4)


func _find_scroll(n: Node) -> ScrollContainer:
	if n is ScrollContainer:
		return n
	for c in n.get_children():
		var r := _find_scroll(c)
		if r != null:
			return r
	return null


func _frames(k: int) -> void:
	for _i in k:
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(path)
	print("capture : ", path)
