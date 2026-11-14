extends SceneTree
## Captures de l'Amphictyonie, lot 2 (institutions et crises), avec le rendu réel :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_amph_inst.gd
## Écrit les images dans le dossier donné par CAPTURE_DIR (par défaut user://captures).
## Scénario : Vael (joueur) siège depuis dix ans ; la Haute Voûte est bâtie, Vael y siège et un Arbitre
## est élu ; un grand chantier est ouvert, un membre appelle à l'aide, une capitale vient de tomber et
## une session extraordinaire siège. Écran Amphictyonie, en haut puis plus bas.


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
	main.player_faction = "vael"
	main.game_options = {"amphictyony": "active"}
	main.new_game(4242)
	await _frames(5)
	var sim: Simulation = main.simulation
	var st: GameState = sim.state
	var me: int = main.view_empire
	sim.advance(360)
	for e in st.empires:
		if e.is_npc():
			continue
		for o in st.empires:
			if o.id != e.id and not o.is_npc() and not e.contacts.has(o.id):
				e.contacts.append(o.id)
		e.resources["influence"] = maxi(int(e.resources.get("influence", 0)), 900)
		e.resources["energy"] = maxi(int(e.resources.get("energy", 0)), 3000)
		e.resources["materials"] = maxi(int(e.resources.get("materials", 0)), 3000)
	var added: Array[Dictionary] = []
	st.tick = int(Amphictyony.data()["found"]["min_day"])
	Amphictyony.monthly(st, added)
	Amphictyony.found_sign(st, me)
	var others: Array[int] = []
	for e in st.empires:
		if e.id != me and Amphictyony.eligible(st, e.id):
			others.append(e.id)
	Amphictyony.found_sign(st, others[0])
	Amphictyony.found_sign(st, others[1])
	for i in range(2, others.size() - 1):
		Amphictyony.join(st, others[i])
	var outsider: int = others[others.size() - 1]
	AmphInst.observe(st, outsider)
	st.tick = int(st.amph["founded"]) + int(AmphInst.idata()["council"]["after_days"])
	# Vael pèse lourd : elle siégera à la Haute Voûte.
	Amphictyony.recompute_voix(st)
	st.amph["voix"][str(me)] = int(st.amph["voix"][str(me)]) + 400
	_pass(st, me, "council", "", 0, -1)
	var cs := AmphInst.councillors(st)
	var arb: int = cs[0] if cs[0] != me else cs[1]
	_pass(st, me, "arbiter", "", 0, arb)
	_pass(st, others[0], "work", "voile", 0, -1)
	_pass(st, others[2], "step", "commerce", 1, -1)
	AmphInst.work_give(st, others[0], 400)
	AmphInst.work_give(st, me, 250)
	AmphInst.work_give(st, others[1], 150)
	AmphInst.denounce(st, me, others[4] if others.size() > 5 else outsider)
	st.amph["queue"] = []
	Amphictyony.propose(st, others[1], "step", "savoir", 1, -1, "")
	Amphictyony.propose(st, others[3], "step", "guerre", 1, -1, "")
	st.tick = int(st.amph["next"])
	Amphictyony.daily(st, added)
	for m in Amphictyony.members(st):
		if posmod(m, 2) == 0:
			Amphictyony.vote(st, m, 1)
	Amphictyony.vote(st, me, 1)
	st.tick += 20
	st.get_empire(others[3]).resources["materials"] = 40
	AmphInst.aid_ask(st, others[3], "materials")
	AmphInst.aid_give(st, others[1], others[3], 100)
	AmphInst.on_capital(st, others[2], others[1])
	AmphInst.convene(st, others[1], int(AmphInst.open_trigs(st)[0]["id"]))
	AmphInst.svote(st, me, 1)
	AmphInst.svote(st, others[0], 1)
	AmphInst.svote(st, others[3], -1)
	Amphictyony.on_atrocity(st, others[4] if others.size() > 5 else others[3])
	main.set_process(false)
	for t in main._hud._toasts.get_children():
		t.queue_free()
	main._refresh_all()
	await _frames(6)
	main.toggle_empire_screen("amphictyony")
	await _frames(10)
	await _shot(out + "/ecran-amphictyonie-lot2.png")
	var sc := _find_scroll(main)
	if sc != null:
		sc.scroll_vertical = 900
		await _frames(6)
		await _shot(out + "/ecran-amphictyonie-lot2-suite.png")
		sc.scroll_vertical = 1900
		await _frames(6)
		await _shot(out + "/ecran-amphictyonie-lot2-fin.png")
	quit()


func _pass(st: GameState, by: int, kind: String, fam: String, dir: int, target: int) -> void:
	st.amph["queue"] = []
	var why := Amphictyony.check_propose(st, by, kind, fam, dir, target, "")
	if why != "":
		print("refus ", kind, " : ", why)
		return
	Amphictyony.propose(st, by, kind, fam, dir, target, "")
	var added: Array[Dictionary] = []
	st.tick = maxi(st.tick + 1, int(st.amph["next"]))
	Amphictyony.daily(st, added)
	for m in Amphictyony.members(st):
		Amphictyony.vote(st, m, 1)
	st.tick = int(Amphictyony.session(st)["end"])
	Amphictyony.daily(st, added)


func _find_scroll(n: Node) -> ScrollContainer:
	var best: ScrollContainer = null
	for c in n.find_children("*", "ScrollContainer", true, false):
		var s := c as ScrollContainer
		if s.is_visible_in_tree() and (best == null or s.size.x > best.size.x):
			best = s
	return best


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(path)
	print("capture : ", path)
