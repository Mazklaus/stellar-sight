extends SceneTree
## Joueur automatique pour tester le multijoueur en vrai réseau (ENet sur cette machine ou entre deux) :
## l'hôte crée une partie, les clients la rejoignent, chacun donne des ordres au hasard à son empire,
## à la vitesse maximale, jusqu'au jour DAYS. Chacun affiche alors « FINAL <jour> <empreinte> » :
## les empreintes doivent être identiques. tools/net_selftest.sh lance un hôte et deux clients.
##   ROLE=host CLIENTS=2 DAYS=1800 godot --headless --path . -s res://tools/net_bot.gd
##   ROLE=client ADDR=127.0.0.1 godot --headless --path . -s res://tools/net_bot.gd
## Variables : PORT (24570), SEED (7), NAME, ORDERS (ordres par seconde, défaut 6), TIMEOUT (secondes),
## QUIT_AT (client : quitte brutalement à ce jour, pour tester le départ d'un joueur), TURNS (hôte :
## tours simultanés de TURNS jours ; chacun donne quelques ordres puis termine son tour, et met parfois
## la partie en pause pendant que les jours défilent), PICK (client : rang de l'empire libre choisi).
## RESUME=1 (hôte) : reprend la dernière sauvegarde automatique en réseau (les joueurs y retrouvent leur
## empire) ; HOST_QUITS_AT (hôte) : quitte brutalement à ce jour.
## Le nom sert d'identifiant : un client relancé avec le même nom retrouve son empire.

var session: NetSession
var role := ""
var days := 1800
var clients := 1
var rng := RandomNumberGenerator.new()
var orders_per_sec := 6.0
var started := false
var done := false
var sent := 0
var _quit_in := -1.0


var _ready_done := false
## Tour par tour : temps avant de terminer son tour, et ordres encore à donner pendant ce tour.
var _turn_wait := -1.0


func _initialize() -> void:
	pass


## Mise en place à la première image : les nœuds ne sont dans l'arbre qu'une fois la boucle lancée.
func _setup() -> void:
	role = OS.get_environment("ROLE")
	days = int(_env("DAYS", "1800"))
	clients = int(_env("CLIENTS", "1"))
	orders_per_sec = float(_env("ORDERS", "6"))
	var port := int(_env("PORT", str(NetSession.DEFAULT_PORT)))
	rng.seed = hash(_env("NAME", role) + str(Time.get_ticks_usec()))
	session = NetSession.new()
	session.player_name = _env("NAME", role)
	session.token = "bot-" + _env("NAME", role)
	root.add_child(session)
	session.notice.connect(func(t: String, _o: String) -> void: print("[%s] %s" % [role, t]))
	session.ended.connect(func(r: String) -> void:
		print("[%s] fin : %s" % [role, r])
		_finish())
	session.join_failed.connect(func(r: String) -> void:
		print("[%s] refusé : %s" % [role, r])
		quit(2))
	var clock: Node = root.get_node("GameClock")
	if role == "host":
		var seats := {}
		var st: GameState
		if _env("RESUME", "") != "":
			st = SaveGame.load_state(NetSession.AUTOSAVE_PATH)
			seats = SaveGame.last_clock.get("net", {})
			print("[host] reprise au jour %d, places : %s" % [st.tick, seats])
		else:
			st = GameState.create(int(_env("SEED", "7")), 150, 1800.0, "ossarane", {"ai_level": "normal"})
		var sim := Simulation.new(st)
		clock.attach(sim)
		if _env("RESUME", "") != "":
			clock.apply_settings(SaveGame.last_clock)
		elif _env("TURNS", "") != "":
			clock.set_mode(clock.MODE_TURNS, int(_env("TURNS", "10")))
		var err := session.host(sim, 0, port, seats)
		if err != OK:
			print("[host] ouverture impossible : %s" % error_string(err))
			quit(2)
			return
		session.request_speed(4)
		print("[host] partie ouverte, port %d, en attente de %d client(s)" % [port, clients])
	else:
		session.joined.connect(func(state: GameState, e: int) -> void:
			var sim := Simulation.new(state)
			clock.attach(sim)
			session.bind(sim)
			print("[%s] entré, empire %d, jour %d" % [session.player_name, e, state.tick]))
		session.choose_empire.connect(func(list: Array) -> void:
			var free := list.filter(func(d: Dictionary) -> bool: return d["free"])
			if free.is_empty():
				print("[%s] aucun empire libre" % session.player_name)
				quit(2)
				return
			var d: Dictionary = free[mini(int(_env("PICK", "0")), free.size() - 1)]
			print("[%s] choisit %s" % [session.player_name, d["name"]])
			session.pick(int(d["id"])))
		session.join(_env("ADDR", "127.0.0.1"), port)


func _process(delta: float) -> bool:
	if not _ready_done:
		_ready_done = true
		_setup()
		return false
	if Time.get_ticks_msec() > int(_env("TIMEOUT", "300")) * 1000:
		print("[%s] délai dépassé" % role)
		quit(3)
		return false
	if _quit_in >= 0.0:
		_quit_in -= delta
		if _quit_in < 0.0:
			quit(0)
		return false
	if session == null or session.core == null:
		return false
	var st := session.core.sim.state
	if role == "host" and not started and session.core.seats.size() - 1 >= clients and session.paused:
		started = true
		if not session.turn_mode:
			session.request_pause(false)
		print("[host] tout le monde est là : c'est parti")
	if role == "host" and _env("HOST_QUITS_AT", "") != "" and st.tick >= int(_env("HOST_QUITS_AT", "0")) and session.paused:
		print("[host] je quitte au jour %d" % st.tick)
		quit(0)
		return false
	if session.turn_mode:
		_turn_bot(delta, st)
		if st.tick >= days and session.paused and session.turn_target < 0 and not session.core.can_step() and not done:
			_finish()
		return false
	# Après un départ (pause automatique), l'hôte relance la partie.
	if role == "host" and started and session.paused and st.tick < days and not session.core.can_step():
		session.request_pause(false)
	# QUIT_AT : ce client quitte brutalement à ce jour (test du départ d'un joueur).
	if role != "host" and _env("QUIT_AT", "") != "" and st.tick >= int(_env("QUIT_AT", "0")):
		print("[%s] je quitte au jour %d" % [session.player_name, st.tick])
		quit(0)
		return false
	if rng.randf() < orders_per_sec * delta and st.tick < days:
		var cmd := _random_order(st, session.my_empire)
		if SimCommands.validate(st, cmd) == "" and session.submit(cmd) == "":
			sent += 1
	if role == "host" and st.tick >= days and not session.paused:
		session.request_pause(true)
	if st.tick >= days and session.paused and not session.core.can_step() and not done:
		_finish()
	return false


## Tours simultanés : quelques ordres, puis fin de tour ; parfois une pause pendant la résolution.
func _turn_bot(delta: float, st: GameState) -> void:
	if role != "host" and _env("QUIT_AT", "") != "" and st.tick >= int(_env("QUIT_AT", "0")):
		print("[%s] je quitte au jour %d" % [session.player_name, st.tick])
		quit(0)
		return
	var ordering := session.paused and not session.core.can_step()
	if not session.paused and rng.randf() < 0.004 and role != "host":
		session.request_toggle()  # pause commune au milieu du tour (comme une bataille)
		return
	if not ordering or st.tick >= days or (role == "host" and not started):
		_turn_wait = -1.0
		return
	var me := Lockstep.HOST if role == "host" else session._peer.get_unique_id()
	if not session.waiting.has(me):
		return  # déjà prêt
	if _turn_wait < 0.0:
		_turn_wait = rng.randf_range(0.05, 0.4)
	if rng.randf() < 0.3:
		var cmd := _random_order(st, session.my_empire)
		if SimCommands.validate(st, cmd) == "" and session.submit(cmd) == "":
			sent += 1
	_turn_wait -= delta
	if _turn_wait < 0.0:
		session.request_toggle()


func _finish() -> void:
	if done or session.core == null:
		return
	done = true
	var st := session.core.sim.state
	print("FINAL %s %d %s ordres=%d" % [session.player_name, st.tick, st.checksum(), sent])
	_quit_in = 3.0  # le temps que les derniers messages partent


func _random_order(state: GameState, empire: int) -> Dictionary:
	var fleets := Fleets.empire_fleets(state, empire)
	if not fleets.is_empty() and rng.randf() < 0.6:
		var f: Fleet = fleets[rng.randi_range(0, fleets.size() - 1)]
		var sys := state.galaxy.get_system(f.system_id)
		if not sys.neighbors.is_empty():
			return SimCommands.move_fleet(empire, f.id, sys.neighbors[rng.randi_range(0, sys.neighbors.size() - 1)])
	var techs := Research.visible_ids(GameData.faction(state.get_empire(empire).faction_id))
	if rng.randf() < 0.5 and not techs.is_empty():
		return SimCommands.research(empire, String(techs[rng.randi_range(0, techs.size() - 1)]))
	var mine := []
	for pid in state.sorted_colony_ids():
		if state.colonies[pid].owner == empire:
			mine.append(pid)
	if not mine.is_empty():
		var pid: int = mine[rng.randi_range(0, mine.size() - 1)]
		var b := ["mine", "farm", "lab", "forum", "shipyard"]
		return SimCommands.build(empire, pid, b[rng.randi_range(0, b.size() - 1)])
	return SimCommands.rename_system(empire, rng.randi_range(0, state.galaxy.systems.size() - 1), "Relais %d" % rng.randi_range(1, 999))


func _env(k: String, d: String) -> String:
	var v := OS.get_environment(k)
	return v if v != "" else d
