extends RefCounted
## Tests des fondations du multijoueur : instantané de partie avec la galaxie complète (relu sans rien
## régénérer), sauvegarde portable, comparaison d'états (StateDiff), empreinte de version (GameVersion).
## Appelés par smoke_test.gd.

const TEST_SAVE := "user://saves/test_net.json"

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Fondations du multijoueur…")
	_test_snapshot_roundtrip()
	_test_snapshot_not_regenerated()
	_test_snapshot_invalid()
	_test_save_portable()
	_test_old_format()
	_test_state_diff()
	_test_version()
	_test_seat_command()
	_test_lockstep()
	_test_lockstep_pause()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


func _game(seed_value := 77, years := 1) -> Simulation:
	var st := GameState.create(seed_value, 150, 1800.0, "", {"spectator": true, "ai_level": "normal",
			"galaxy": {"shape": "amas", "placement": "equilibre", "guaranteed": 1}})
	var sim := Simulation.new(st)
	sim.advance(360 * years)
	return sim


func _galaxy_equal(a: Galaxy, b: Galaxy) -> bool:
	if a.systems.size() != b.systems.size() or a.planets.size() != b.planets.size() or a.lanes != b.lanes:
		return false
	for i in a.systems.size():
		var x := a.systems[i]
		var y := b.systems[i]
		if x.position != y.position or x.star_type != y.star_type or x.neighbors != y.neighbors or x.planet_ids != y.planet_ids:
			return false
	for i in a.planets.size():
		var p := a.planets[i]
		var q := b.planets[i]
		if p.system_id != q.system_id or p.index != q.index or p.type != q.type or p.size != q.size or p.deposits != q.deposits:
			return false
	return true


func _test_snapshot_roundtrip() -> void:
	var sim := _game()
	var snap := sim.state.to_snapshot()
	_ok(snap.has("galaxy") and not sim.state.to_dict().has("galaxy"), "l'instantané contient la galaxie, pas l'empreinte")
	var copy := GameState.from_dict(JSON.parse_string(JSON.stringify(snap)))
	_ok(copy != null, "instantané relu après passage en JSON (%s)" % GameState.last_error)
	if copy == null:
		return
	_ok(copy.checksum() == sim.state.checksum(), "instantané relu = même empreinte")
	_ok(_galaxy_equal(copy.galaxy, sim.state.galaxy), "instantané relu = même galaxie au bit près (positions, routes, voisins, planètes)")
	# La partie continue à l'identique depuis l'instantané, comme chez un client en multijoueur.
	var follow := Simulation.new(copy)
	sim.advance(90)
	follow.advance(90)
	_ok(follow.state.checksum() == sim.state.checksum(), "la partie continue à l'identique depuis l'instantané")


func _test_snapshot_not_regenerated() -> void:
	var st := GameState.create(5, 150, 1800.0, "ossarane", {"ai_level": ""})
	var snap := st.to_snapshot()
	# On déplace une étoile dans l'instantané : si la galaxie était régénérée, le changement serait perdu.
	var g: Dictionary = snap["galaxy"]
	var coords := Marshalls.base64_to_raw(String(g["positions"])).to_float32_array()
	coords[0] += 123.25
	g["positions"] = Marshalls.raw_to_base64(coords.to_byte_array())
	var copy := GameState.from_dict(snap)
	_ok(copy != null and copy.galaxy.systems[0].position.x == coords[0] and coords[0] != st.galaxy.systems[0].position.x,
			"la galaxie de l'instantané est reprise telle quelle, pas régénérée depuis la graine")


func _test_snapshot_invalid() -> void:
	var st := GameState.create(5, 150, 1800.0, "ossarane", {"ai_level": ""})
	var snap := st.to_snapshot()
	(snap["galaxy"] as Dictionary)["lanes"] = [[0, 99999]]
	_ok(GameState.from_dict(snap) == null and GameState.last_error == "galaxie incohérente", "galaxie incohérente refusée")
	var snap2 := st.to_snapshot()
	(snap2["galaxy"]["systems"] as Array).pop_back()
	_ok(GameState.from_dict(snap2) == null, "galaxie tronquée refusée")


func _test_save_portable() -> void:
	var sim := _game(31, 0)
	sim.advance(30)
	_ok(SaveGame.save_state(sim.state, TEST_SAVE) == OK, "sauvegarde écrite")
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TEST_SAVE))
	_ok(raw["state"].has("galaxy"), "la sauvegarde contient la galaxie complète")
	var loaded := SaveGame.load_state(TEST_SAVE)
	_ok(loaded != null and loaded.checksum() == sim.state.checksum(), "sauvegarde portable relue à l'identique (%s)" % SaveGame.last_error)
	DirAccess.remove_absolute(TEST_SAVE)


func _test_old_format() -> void:
	# Une sauvegarde d'avant la version 15 n'a pas de galaxie : on la régénère depuis la graine.
	var st := GameState.create(8, 150, 1800.0, "vael", {"ai_level": ""})
	var d := st.to_dict()
	d["version"] = 14
	var copy := GameState.from_dict(d)
	_ok(copy != null and _galaxy_equal(copy.galaxy, st.galaxy), "ancienne sauvegarde sans galaxie : régénérée depuis la graine")


func _test_state_diff() -> void:
	var sim := _game(12, 0)
	var a := sim.state.to_dict()
	var b: Dictionary = JSON.parse_string(JSON.stringify(a))
	_ok(StateDiff.differences(a, b).is_empty(), "états identiques (entiers relus en flottants par le JSON) : aucun écart")
	var res: Dictionary = b["empires"][1]["resources"]
	res["materials"] = float(res["materials"]) + 1.0
	b["tick"] = int(b["tick"]) + 1
	var diffs := StateDiff.differences(a, b)
	_ok(diffs.size() == 2, "deux écarts trouvés (%s)" % ", ".join(diffs))
	_ok(StateDiff.first_difference(a, b).begins_with("empires[1].resources.materials"), "premier écart = le plus haut dans l'état, avec son chemin")
	b.erase("winner")
	_ok(StateDiff.differences(a, b, 50).any(func(x: String) -> bool: return x.begins_with("winner : ")), "clé absente signalée")
	_ok(StateDiff.differences([1, 2], [1, 2, 3]) == [" : 2 éléments ≠ 3"], "listes de tailles différentes signalées")


func _test_version() -> void:
	var fp := GameVersion.fingerprint()
	_ok(fp.length() == 16 and fp.is_valid_hex_number(), "empreinte de version : 16 caractères hexadécimaux (%s)" % fp)
	_ok(GameVersion.compute(GameVersion.ROOTS).begins_with(fp), "empreinte stable d'un calcul à l'autre")
	_ok(GameVersion.compute(["res://data"]) != GameVersion.compute(["res://scripts/sim"]), "l'empreinte dépend des fichiers")
	_ok(GameVersion.label().contains(fp), "la version lisible montre l'empreinte")


func _test_seat_command() -> void:
	var st := GameState.create(3, 150, 1800.0, "ossarane", {"ai_level": "normal"})
	var sim := Simulation.new(st)
	_ok(sim.submit(SimCommands.seat(1, "")), "« seat » : un empire IA passe à un humain")
	sim.flush_commands()
	_ok(not st.get_empire(1).is_ai(), "l'empire 1 est maintenant tenu par un humain")
	sim.submit(SimCommands.seat(1, "normal"))
	sim.flush_commands()
	_ok(st.get_empire(1).ai_level == "normal" and st.get_empire(1).ai_temperament != "", "« seat » : retour à l'IA (intérim), avec un tempérament")
	_ok(SimCommands.validate(st, SimCommands.seat(1, "n'importe")) != "", "« seat » : niveau d'IA inconnu refusé")


## Trois machines reliées en mémoire, avec une latence aléatoire de 0 à 4 images par message :
## un hôte (empire 0) et deux clients (empires 1 et 2) qui donnent des ordres au hasard.
class Wire:
	var queue: Array = []  # [due, to_core_index, from_peer, msg]
	var rng := RandomNumberGenerator.new()
	var frame := 0

	func post(to: int, from: int, msg: Dictionary) -> void:
		# Chaque lien garde l'ordre (ENet fiable et ordonné) : l'échéance ne recule jamais.
		var due := frame + rng.randi_range(0, 4)
		for q in queue:
			if q[1] == to and q[2] == from:
				due = maxi(due, int(q[0]))
		queue.append([due, to, from, var_to_bytes(msg)])


func _random_order(state: GameState, empire: int, rng: RandomNumberGenerator) -> Dictionary:
	var fleets := Fleets.empire_fleets(state, empire)
	if not fleets.is_empty() and rng.randf() < 0.7:
		var f: Fleet = fleets[rng.randi_range(0, fleets.size() - 1)]
		var sys := state.galaxy.get_system(f.system_id)
		if not sys.neighbors.is_empty():
			return SimCommands.move_fleet(empire, f.id, sys.neighbors[rng.randi_range(0, sys.neighbors.size() - 1)])
	var techs := Research.visible_ids(GameData.faction(state.get_empire(empire).faction_id))
	if not techs.is_empty() and rng.randf() < 0.6:
		return SimCommands.research(empire, String(techs[rng.randi_range(0, techs.size() - 1)]))
	return SimCommands.rename_system(empire, rng.randi_range(0, state.galaxy.systems.size() - 1), "Relais %d" % rng.randi_range(1, 999))


func _lockstep_world(seed_value: int) -> Array:
	var st := GameState.create(seed_value, 150, 1800.0, "ossarane", {"ai_level": "normal", "ai_levels": ["", "", "", "normal", "normal"]})
	var host := Lockstep.new(Simulation.new(st), true)
	host.seats[Lockstep.HOST] = 0
	var cores: Array = [host]
	for i in 2:
		var c := Lockstep.new(Simulation.new(GameState.from_dict(st.to_snapshot())), false)
		cores.append(c)
		host.add_peer(i + 2, i + 1)
	return cores


## Fait tourner les trois machines `frames` images ; renvoie le nombre d'ordres demandés.
func _run_world(cores: Array, wire: Wire, frames: int, rng: RandomNumberGenerator, host_runs: Callable) -> int:
	var host: Lockstep = cores[0]
	var orders := 0
	for _f in frames:
		wire.frame += 1
		# Livraison des messages arrivés.
		var keep: Array = []
		for q in wire.queue:
			if int(q[0]) > wire.frame:
				keep.append(q)
				continue
			var msg: Dictionary = bytes_to_var(q[3])
			var to := int(q[1])
			if to == 0:
				match String(msg["k"]):
					"order":
						host.request(int(q[2]), msg["c"])
					"ack":
						host.host_receive_ack(int(q[2]), int(msg["t"]), String(msg.get("h", "")))
			elif String(msg["k"]) == "frame":
				(cores[to] as Lockstep).receive_frame(int(msg["t"]), msg["c"], bool(msg["s"]))
		wire.queue = keep
		# Ordres au hasard (un toutes les 3 images en moyenne par joueur).
		for i in 3:
			if rng.randf() < 0.33:
				var c: Lockstep = cores[i]
				var cmd := _random_order(c.sim.state, i, rng)
				if SimCommands.validate(c.sim.state, cmd) == "":
					orders += 1
					if i == 0:
						host.request(Lockstep.HOST, cmd)
					else:
						wire.post(0, i + 1, {"k": "order", "c": cmd})
		# L'hôte avance (ou se met en pause), les clients le suivent.
		host_runs.call(host)
		for i in [1, 2]:
			var c: Lockstep = cores[i]
			var n := 0
			while c.can_step() and n < 3:
				c.step()
				n += 1
			for out in c.outbox:
				wire.post(0, i + 1, out["msg"])
			c.outbox.clear()
		for out in host.outbox:
			for i in [1, 2]:
				if int(out["to"]) == 0 or int(out["to"]) == i + 1:
					wire.post(i, 1, out["msg"])
		host.outbox.clear()
	return orders


## Arrêt commun : l'hôte ne scelle plus rien et tout le monde joue jusqu'au premier jour sans trame.
func _settle(cores: Array, wire: Wire) -> void:
	_run_world(cores, wire, 40, RandomNumberGenerator.new(), func(h: Lockstep) -> void:
		while h.can_step():
			h.step())


func _test_lockstep() -> void:
	var cores := _lockstep_world(21)
	var host: Lockstep = cores[0]
	host.delay = 2
	host.max_lead = 6
	var desyncs := []
	host.desync_detected.connect(func(p: int, t: int) -> void: desyncs.append([p, t]))
	var wire := Wire.new()
	wire.rng.seed = 5
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var orders := _run_world(cores, wire, 1500, rng, func(h: Lockstep) -> void:
		if h.host_may_step():
			h.seal_until(h.tick() + h.delay)
			h.step())
	# Arrêt commun pour comparer les trois machines au même jour.
	_settle(cores, wire)
	var a: Lockstep = cores[0]
	_ok(a.tick() > 360, "lockstep : l'hôte a joué plus d'un an (%d jours, %d ordres)" % [a.tick(), orders])
	_ok(orders > 200, "lockstep : des centaines d'ordres échangés")
	var same := true
	for i in [1, 2]:
		var c: Lockstep = cores[i]
		same = same and c.tick() == a.tick() and c.sim.state.checksum() == a.sim.state.checksum()
	_ok(same, "lockstep : les trois machines finissent au même jour avec la même empreinte")
	_ok(desyncs.is_empty(), "lockstep : aucune désynchronisation signalée (%s)" % [desyncs])
	_ok(a.slowest() >= 0 and a.tick() - int(a.acks[a.slowest()]) <= a.max_lead, "lockstep : l'hôte n'a jamais distancé le plus lent de plus de max_lead jours")


func _test_lockstep_pause() -> void:
	var cores := _lockstep_world(4)
	var host: Lockstep = cores[0]
	var wire := Wire.new()
	wire.rng.seed = 2
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	_run_world(cores, wire, 120, rng, func(h: Lockstep) -> void:
		if h.host_may_step():
			h.seal_until(h.tick() + h.delay)
			h.step())
	# Pause : l'hôte ne scelle plus rien et joue jusqu'au premier jour sans trame ; ordres en pause.
	var stop_rng := RandomNumberGenerator.new()
	stop_rng.seed = 8
	_run_world(cores, wire, 60, stop_rng, func(h: Lockstep) -> void:
		while h.can_step():
			h.step()
		h.flush_paused())
	var q := host.tick()
	var same := true
	for i in [1, 2]:
		var c: Lockstep = cores[i]
		same = same and c.tick() == q and c.sim.state.checksum() == host.sim.state.checksum()
	_ok(same, "pause : tout le monde s'arrête au même jour (%d), ordres donnés en pause appliqués partout" % q)
	# Reprise : la trame Q est scellée, la partie continue à l'identique.
	_run_world(cores, wire, 200, rng, func(h: Lockstep) -> void:
		if h.host_may_step():
			h.seal_until(h.tick() + h.delay)
			h.step())
	_settle(cores, wire)
	var after := true
	for i in [1, 2]:
		var c: Lockstep = cores[i]
		after = after and c.tick() == host.tick() and c.sim.state.checksum() == host.sim.state.checksum()
	_ok(host.tick() > q and after, "reprise après la pause : mêmes empreintes (jour %d)" % host.tick())
	# Un client qui triche (ou diverge) est repéré à la somme de contrôle suivante.
	var desyncs := []
	host.desync_detected.connect(func(p: int, t: int) -> void: desyncs.append([p, t]))
	var cheater: Lockstep = cores[1]
	cheater.sim.state.get_empire(1).resources["materials"] = int(cheater.sim.state.get_empire(1).resources.get("materials", 0)) + 500
	_run_world(cores, wire, 120, rng, func(h: Lockstep) -> void:
		if h.host_may_step():
			h.seal_until(h.tick() + h.delay)
			h.step())
	_ok(not desyncs.is_empty() and int(desyncs[0][0]) == 2 and int(desyncs[0][1]) <= 330, "un client qui modifie sa partie est repéré dès le contrôle mensuel suivant (%s)" % [desyncs])
