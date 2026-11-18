extends SceneTree
## Captures du glossaire en jeu (infobulles imbriquées et Codex de l'Archonte), avec le rendu réel :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_codex.gd
## Écrit les images dans le dossier donné par CAPTURE_DIR (par défaut user://captures).
## Scénario : Vaël ; une infobulle de terme et sa voisine imbriquée (figée), puis le Codex sur un
## article du lexique, sur une fiche de peuple, sur une recherche et sur une section du manuel.


func _initialize() -> void:
	var out := OS.get_environment("CAPTURE_DIR")
	if out == "":
		out = ProjectSettings.globalize_path("user://captures")
	DirAccess.make_dir_recursive_absolute(out)
	CodexPrefs.persist = false
	CodexPrefs.reset()
	UiSettings.glossary_intro_done = true
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.save_path = "user://saves/capture_quicksave.json"
	main.start_with_menu = false
	root.add_child(main)
	await _frames(10)
	var st := GameState.create(2027, 150, 1800.0, "vael", {"ai_level": ""})
	main._start(st)
	main.game_in_progress = true
	main.set_process(false)
	main._sync_codex()
	main._refresh_all()
	await _frames(10)
	# 1. Infobulles imbriquées : un terme, puis un terme de sa définition, figés.
	var tips: TipManager = main.tips
	tips.set_process(false)
	var first := _term_with_link()
	var t1 := tips._open(Glossary.tip_text(first), first, main._hud.bar, Vector2(520, 250))
	await _frames(4)
	t1.set_locked(true)
	var second := _first_link(Glossary.tip_text(first), first)
	if second != "":
		var t2 := tips._open(Glossary.tip_text(second), second, t1, t1.position + Vector2(t1.size.x - 30.0, 60.0), t1)
		await _frames(4)
		t2.set_locked(true)
	await _frames(6)
	await _shot(out + "/infobulles-imbriquees.png")
	tips.close_all()
	# 2. Le Codex sur l'article du terme.
	main.open_codex(first)
	await _frames(10)
	await _shot(out + "/codex-terme.png")
	# 3. Une fiche de peuple.
	main.codex.navigate("cat:peuples:vael")
	await _frames(10)
	await _shot(out + "/codex-fiche-peuple.png")
	# 4. Une recherche.
	main.codex._search.text = "stabilite"
	main.codex._search.text_changed.emit("stabilite")
	main.codex._search_timer = 0.0
	await _frames(10)
	await _shot(out + "/codex-recherche.png")
	main.codex._search.text = ""
	main.codex._search.text_changed.emit("")
	# 5. Une section du manuel.
	main.codex.navigate("man:03-interface#les-infobulles-et-le-codex")
	await _frames(10)
	await _shot(out + "/codex-manuel.png")
	quit()


## Un terme dont la définition contient au moins un autre terme.
func _term_with_link() -> String:
	for tid in ["stabilite", "influence", "biosphere"]:
		if Glossary.has(tid) and _first_link(Glossary.tip_text(tid), tid) != "":
			return tid
	for tid in Glossary.order:
		if _first_link(Glossary.tip_text(tid), tid) != "":
			return tid
	return Glossary.order[0]


func _first_link(bb: String, skip: String) -> String:
	var at := bb.find("[url=glo:")
	while at >= 0:
		var end := bb.find("]", at)
		var id := bb.substr(at + 9, end - at - 9)
		if id != skip:
			return id
		at = bb.find("[url=glo:", end)
	return ""


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(path)
	print("capture : ", path)
