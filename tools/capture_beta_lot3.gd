extends SceneTree
## Captures du lot 3 du bêta-test (faire une armée), rendu réel :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_beta_lot3.gd
## Écrit dans CAPTURE_DIR (par défaut user://captures) : l'onglet Flottes avec une flotte en formation et
## sa commande, les renforts d'une flotte existante, la fiche de flotte (Rassembler ici, Renforts, effet
## de la conduite), le rapport de force au survol d'un système ennemi, les forces comparées en Diplomatie.


func _initialize() -> void:
	var out := OS.get_environment("CAPTURE_DIR")
	if out == "":
		out = ProjectSettings.globalize_path("user://captures")
	DirAccess.make_dir_recursive_absolute(out)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.save_path = "user://saves/capture_quicksave.json"
	main.save_dir = "user://capture_saves_beta3"
	main.start_with_menu = false
	root.add_child(main)
	await _frames(5)
	main.player_faction = "vael"
	main.new_game(4343)
	await _frames(20)
	var st: GameState = main.simulation.state
	var me := 0
	var foe := 1
	for pair in [[me, foe], [foe, me]]:
		if not st.get_empire(pair[0]).contacts.has(pair[1]):
			st.get_empire(pair[0]).contacts.append(pair[1])
	var e := st.get_empire(me)
	for r in ["materials", "energy", "influence"]:
		e.resources[r] = int(e.resources.get(r, 0)) + 3000
	var home: int = st.galaxy.get_planet(e.capital_planet).system_id
	var ship := ""
	for sid in Musters.orderable(st, me):
		if Combat.is_military(sid):
			ship = sid
			break
	var first := st.spawn_ship(me, ship, home)
	first.fleet_name = "Première escadre"
	first.add_ship(ship, -1, -1)
	var second := st.spawn_ship(me, ship, home)
	second.fleet_name = "Garde de Vaëlis"

	# Onglet Flottes : une flotte en formation, trois vaisseaux commandés.
	var cmds: Array[Dictionary] = [SimCommands.muster_act(me, "new", home, -1, "Flotte du Levant")]
	for c in cmds:
		SimCommands.apply(st, c)
	var mid := int(Musters.of_empire(st, me)[-1]["id"])
	for _i in 3:
		SimCommands.apply(st, SimCommands.muster_act(me, "add", mid, -1, ship))
	Musters.daily(st)
	var screens: EmpireScreens = main._empire_screens
	screens.fleets_selected = FleetsScreen.MUSTER_BASE - mid
	main.open_address("fleets")
	await _frames(30)
	await _shot(out + "/flottes-formation.png")
	# Renforts d'une flotte existante.
	SimCommands.apply(st, SimCommands.muster_act(me, "new", -1, first.id, ship))
	screens.fleets_selected = first.id
	screens.show_screen("fleets")
	await _frames(20)
	await _shot(out + "/flottes-renforts.png")
	main.close_empire_screen()
	await _frames(10)

	# Fiche de flotte : Rassembler ici, Renforts, ce que fait la conduite.
	main.select_fleet(first.id)
	main._camera.position = st.galaxy.systems[home].position
	await _frames(30)
	await _shot(out + "/fiche-flotte-conduite.png")

	# Rapport de force : une flotte ennemie dans un système voisin, survolé.
	var there: int = st.galaxy.systems[home].neighbors[0]
	var enemy := st.spawn_ship(foe, ship, there)
	for _i in 4:
		enemy.add_ship(ship, -1, -1)
	Diplomacy._rel_w(st, me, foe)["truce"] = 0
	Diplomacy._rel_w(st, me, foe)["pact"] = Diplomacy.COLD
	Combat.start_war(st, me, foe)
	FleetSystem.update_exploration(st)
	main._hud.refresh()
	var at: Vector2 = main.get_viewport().get_canvas_transform() * st.galaxy.systems[there].position
	await _hover(main, at)
	await _shot(out + "/rapport-de-force.png")
	await _hover(main, Vector2(800, 120))
	main.select_fleet(-1)
	await _frames(10)

	# Diplomatie : forces armées comparées.
	main.open_relation(foe, "relation")
	await _frames(30)
	await _shot(out + "/diplomatie-forces.png")
	main.close_empire_screen()
	await _frames(5)
	quit()


func _hover(main: Node, at: Vector2) -> void:
	Input.warp_mouse(at)
	var mm := InputEventMouseMotion.new()
	mm.position = at
	mm.global_position = at
	Input.parse_input_event(mm)
	await _frames(int(main.tips.delay * 60.0) + 30)


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(path)
	print("capture : ", path)
