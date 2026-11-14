extends SceneTree
## Captures de l'Amphictyonie, lot 3 (pouvoir et légitimité), avec le rendu réel :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_amph_power.gd
## Écrit les images dans le dossier donné par CAPTURE_DIR (par défaut user://captures).
## Scénario : Vael (joueur) siège ; l'Arbitre des étoiles a reçu les pleins pouvoirs, la Cour attend
## les réponses (vassaux et rebelles) ; c'est l'an 30, l'élection du Chancelier des étoiles est ouverte ;
## Vael a une loi qui se heurte au Nomos et la loi Souveraineté. Écran Amphictyonie (bloc « Pouvoir et
## légitimité ») et écran des victoires.


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
	main.game_options = {"amphictyony": "active", "politics": "active"}
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
	for i in range(2, others.size()):
		Amphictyony.join(st, others[i])
	st.tick = int(st.amph["founded"]) + int(AmphInst.idata()["council"]["after_days"])
	Amphictyony.recompute_voix(st)
	_pass(st, me, "council", "", 0, -1)
	var cs := AmphInst.councillors(st)
	var arb: int = cs[0] if cs[0] != me else cs[1]
	_pass(st, cs[0], "arbiter", "", 0, arb)
	_pass(st, others[2], "step", "commerce", -1, -1)
	_pass(st, others[3], "step", "savoir", 1, -1)
	# L'Arbitre obtient un mandat à vie, puis les pleins pouvoirs : la Cour attend les réponses.
	st.tick = int(AmphPower.cdata()["from_day"]) - 200
	_pass(st, others[1], "term_lift", "", 0, -1)
	_pass(st, arb, "full_powers", "", 0, -1)
	for i in range(0, others.size()):
		var o: int = others[i]
		if o == arb:
			continue
		if i % 3 == 2:
			AmphPower.rise(st, o)
		elif i % 3 == 0:
			AmphPower.submit(st, o)
	# Vael a des lois qui se heurtent au Nomos, et la loi Souveraineté.
	var en := Politics._emp_w(st, me)
	en["laws"] = ["libre_echange", "souverainete"]
	st.relic_rev += 1
	# L'an 30 : élection du Chancelier des étoiles.
	st.tick = int(AmphPower.cdata()["from_day"])
	Amphictyony.recompute_voix(st)
	AmphPower._open_chan(st, added)
	st.amph["imp"]["until"] = st.tick + 60
	if AmphPower.chan_on(st):
		var cands: Array = AmphPower.chan(st)["cands"]
		for m in Amphictyony.members(st):
			if not cands.has(m) and m != me:
				AmphPower.cvote(st, m, int(cands[posmod(m, 2)]))
	st.amph["share"][str(arb)] = 48
	VictorySystem._monthly(st, 30, added)
	st.amph["queue"] = []
	Amphictyony.propose(st, me, "step", "peuples", 1, -1, "")
	Amphictyony.propose(st, me, "step", "ombres", 1, -1, "")
	main.set_process(false)
	for t in main._hud._toasts.get_children():
		t.queue_free()
	main._refresh_all()
	await _frames(6)
	main.toggle_empire_screen("amphictyony")
	await _frames(10)
	var sc := _find_scroll(main)
	if sc != null:
		var blk := _find_label(main, "Pouvoir et légitimité")
		if blk != null:
			sc.scroll_vertical = int(blk.global_position.y - sc.global_position.y) + sc.scroll_vertical - 20
		await _frames(6)
	await _shot(out + "/ecran-amphictyonie-lot3.png")
	main.toggle_empire_screen("victory")
	await _frames(10)
	await _shot(out + "/ecran-victoires-diplomatique.png")
	quit()


func _find_label(n: Node, text: String) -> Control:
	for c in n.find_children("*", "Label", true, false):
		var l := c as Label
		if l.is_visible_in_tree() and l.text.contains(text):
			return l
	return null


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
