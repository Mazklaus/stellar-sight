extends SceneTree
## Captures de l'Amphictyonie (lot 1 de « Conseil galactique »), avec le rendu réel :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_amphictyony.gd
## Écrit les images dans le dossier donné par CAPTURE_DIR (par défaut user://captures).
## Scénario : Vael (joueur) en l'an 8, tout le monde se connaît ; l'acte de fondation circule (capture),
## puis l'Amphictyonie est fondée, une séance a eu lieu (Routes franches adoptées), une autre est en
## cours, un membre est hors-la-loi. Écran Amphictyonie, lentille.


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
		for s in st.galaxy.systems:
			if e.id == me:
				e.explored[s.id] = true
		e.resources["influence"] = maxi(int(e.resources.get("influence", 0)), 300)
	st.tick = int(Amphictyony.data()["found"]["min_day"]) - 1
	var added: Array[Dictionary] = []
	st.tick += 1
	Amphictyony.monthly(st, added)
	main.set_process(false)
	for t in main._hud._toasts.get_children():
		t.queue_free()
	main._refresh_all()
	await _frames(6)
	main.toggle_empire_screen("amphictyony")
	await _frames(10)
	await _shot(out + "/ecran-amphictyonie-fondation.png")
	main.toggle_empire_screen("amphictyony")
	await _frames(4)
	# Fondation par le joueur et deux autres ; tout le monde adhère sauf un.
	Amphictyony.found_sign(st, me)
	var others: Array[int] = []
	for e in st.empires:
		if e.id != me and Amphictyony.eligible(st, e.id):
			others.append(e.id)
	Amphictyony.found_sign(st, others[0])
	Amphictyony.found_sign(st, others[1])
	for i in range(2, others.size() - 1):
		Amphictyony.join(st, others[i])
	# Première séance : Routes franches, adoptées.
	Amphictyony.propose(st, me, "step", "commerce", 1, -1, "")
	st.tick = int(st.amph["next"])
	Amphictyony.daily(st, added)
	for m in Amphictyony.members(st):
		Amphictyony.vote(st, m, 1 if posmod(m, 3) != 0 else -1)
	st.tick = int(Amphictyony.session(st)["end"])
	Amphictyony.daily(st, added)
	# Un membre enfreint le Nomos ; des propositions attendent ; une séance est en cours.
	Amphictyony.on_atrocity(st, others[1])
	Amphictyony.propose(st, others[0], "step", "savoir", 1, -1, "")
	Amphictyony.propose(st, others[2], "sanction", "", 0, others[1], "mil")
	Amphictyony.support(st, me, int(Amphictyony.proposal_of(st, others[2])["id"]))
	if others.size() > 3:
		Amphictyony.propose(st, others[3], "step", "guerre", -1, -1, "")
	st.tick = int(st.amph["next"])
	Amphictyony.daily(st, added)
	st.tick += 40
	for m in Amphictyony.members(st):
		if posmod(m, 2) == 0:
			Amphictyony.vote(st, m, 1)
	Amphictyony.recompute_voix(st)
	main._refresh_all()
	await _frames(6)
	main.toggle_empire_screen("amphictyony")
	await _frames(10)
	await _shot(out + "/ecran-amphictyonie.png")
	main.toggle_empire_screen("amphictyony")
	await _frames(4)
	main._view.fog = false
	main._hud.set_lens("amph")
	await _frames(8)
	await _shot(out + "/lentille-amphictyonie.png")
	quit()


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(path)
	print("capture : ", path)
