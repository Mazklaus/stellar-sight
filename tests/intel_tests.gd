extends RefCounted
## Tests de la dernière information connue (Intel) : mémoire figée hors de vue, rafraîchie au retour,
## sauvegarde, reprise des anciennes sauvegardes, partage entre alliés, déterminisme et affichage.
## Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Dernière information connue…")
	var old_lens := Intel.lens
	_test_start()
	_test_frozen_then_refreshed()
	_test_save_round_trip()
	_test_old_save()
	_test_share()
	_test_determinism()
	_test_display()
	Intel.lens = old_lens


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


func _home(st: GameState, empire_id := 0) -> int:
	return st.galaxy.get_planet(st.get_empire(empire_id).capital_planet).system_id


## Un système libre, avec des planètes, que l'empire ne voit pas en ce moment.
func _far_free_system(st: GameState, empire_id: int) -> int:
	var seen := Fleets.visible_systems(st, empire_id)
	for s in st.galaxy.systems:
		if s.planet_count > 0 and st.system_owner(s.id) == -1 and not seen.has(s.id):
			var near := false
			for n in s.neighbors:
				if seen.has(n) or st.system_owner(n) != -1:
					near = true
			if not near:
				return s.id
	return -1


## Pose un éclaireur de l'empire dans le système, laisse passer un jour, puis le retire.
func _glimpse(sim: Simulation, empire_id: int, system_id: int) -> void:
	var f := sim.state.spawn_ship(empire_id, "scout", system_id)
	sim.step()
	sim.state.fleets.erase(f.id)
	sim.step()


func _claim(st: GameState, owner: int, planet_id: int) -> void:
	var c := Colony.new()
	c.planet_id = planet_id
	c.owner = owner
	c.kind = Colony.KIND_OUTPOST
	st.add_colony(c)


func _test_start() -> void:
	var st := GameState.create(7)
	var e := st.get_empire(0)
	var home := _home(st)
	_ok(e.intel.has(home), "mémoire du système d'origine dès le départ")
	_ok(int(e.intel[home]["info"]["owner"]) == 0 and int(e.intel[home]["day"]) == 0, "relevé du système d'origine daté du jour 0")
	var all_known := true
	for sid in e.explored:
		if not e.intel.has(sid):
			all_known = false
	_ok(all_known, "chaque système exploré a un relevé")
	_ok(Intel.owner_of(st, 0, home) == 0 and Intel.is_live(st, 0, home), "le système d'origine se lit en direct")


func _test_frozen_then_refreshed() -> void:
	var sim := Simulation.new(GameState.create(11))
	var st := sim.state
	var y := _far_free_system(st, 0)
	_ok(y >= 0, "un système libre hors de vue pour le test")
	if y < 0:
		return
	_ok(Intel.known(st, 0, y).is_empty() and Intel.last_seen(st, 0, y) == -1, "système jamais vu : rien en mémoire")
	_glimpse(sim, 0, y)
	var seen_day := st.tick - 1
	_ok(Fleets.is_explored(st, 0, y) and not Intel.is_live(st, 0, y), "système aperçu puis perdu de vue")
	_ok(Intel.last_seen(st, 0, y) == seen_day, "date de la dernière observation retenue")
	var pid: int = st.galaxy.get_system(y).planet_ids[0]
	_claim(st, 1, pid)
	sim.advance(40)
	_ok(st.system_owner(y) == 1, "le rival a bien pris le système (état réel)")
	_ok(Intel.owner_of(st, 0, y) == -1, "hors de vue, le système reste libre dans la mémoire")
	_ok(Intel.colony_of(st, 0, pid) == null, "hors de vue, la revendication du rival n'apparaît pas")
	_ok(Intel.owner_of(st, -1, y) == 1 and Intel.colony_of(st, -1, pid) != null, "le lecteur -1 (spectateur) voit l'état réel")
	_ok(Intel.last_seen(st, 0, y) == seen_day, "la date ne bouge pas hors de vue")
	_ok(Intel.age_label(st, 0, y) == "vu il y a 1 mois", "âge du relevé en mots (%s)" % Intel.age_label(st, 0, y))
	_ok(Intel.age_label(st, 0, _home(st)) == "", "aucun âge pour un système vu")
	var f := st.spawn_ship(0, "scout", y)
	sim.step()
	_ok(Intel.is_live(st, 0, y) and Intel.owner_of(st, 0, y) == 1, "de retour sur place, la mémoire se met à jour")
	st.fleets.erase(f.id)
	sim.step()
	_ok(Intel.owner_of(st, 0, y) == 1 and Intel.last_seen(st, 0, y) == st.tick - 1, "nouveau relevé figé avec la nouvelle date")
	var ghost := Intel.colony_of(st, 0, pid)
	_ok(ghost != null and ghost.owner == 1 and not ghost.is_colony(), "revendication reconstituée depuis le relevé")
	# Un empire qui disparaît reste au nom de son ancien propriétaire jusqu'à la prochaine observation.
	st.colonies.erase(pid)
	st.rebuild_ownership()
	sim.step()
	_ok(Intel.owner_of(st, 0, y) == 1, "un abandon hors de vue n'est pas connu")


func _test_save_round_trip() -> void:
	var sim := Simulation.new(GameState.create(12))
	var y := _far_free_system(sim.state, 0)
	if y >= 0:
		_glimpse(sim, 0, y)
		_claim(sim.state, 1, sim.state.galaxy.get_system(y).planet_ids[0])
	sim.advance(5)
	var d := sim.state.to_dict()
	_ok(int(d["version"]) == GameState.FORMAT_VERSION, "format de sauvegarde à jour")
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(d)))
	_ok(back != null, "sauvegarde avec mémoire relue (%s)" % GameState.last_error)
	if back == null:
		return
	_ok(back.checksum() == sim.state.checksum(), "même empreinte après aller-retour JSON")
	var same := true
	for i in back.empires.size():
		if Intel.to_list(back.empires[i]) != Intel.to_list(sim.state.empires[i]):
			same = false
	_ok(same, "mémoires identiques après rechargement")
	if y >= 0:
		_ok(Intel.owner_of(back, 0, y) == -1 and back.system_owner(y) == 1, "le système perdu de vue reste libre dans la mémoire relue")
	var b := Simulation.new(back)
	sim.advance(60)
	b.advance(60)
	_ok(sim.state.checksum() == b.state.checksum(), "la partie rechargée continue à l'identique")


func _test_old_save() -> void:
	var st := GameState.create(13)
	Simulation.new(st).advance(10)
	var d := st.to_dict()
	d["version"] = 15
	for e: Dictionary in d["empires"]:
		e.erase("intel")
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(d)))
	_ok(back != null, "sauvegarde 15 toujours lisible (%s)" % GameState.last_error)
	if back == null:
		return
	var ok := true
	for e in back.empires:
		for sid in e.explored:
			if not e.intel.has(sid) or e.intel[sid]["info"] != Intel.survey(back, sid):
				ok = false
	_ok(ok, "sauvegarde 15 : mémoire tirée de l'état réel pour les systèmes explorés")


func _test_share() -> void:
	var a := Empire.new()
	var b := Empire.new()
	a.intel[5] = {"day": 10, "info": {"owner": 1, "claims": [], "siege": -1, "battle": 0}}
	b.intel[5] = {"day": 30, "info": {"owner": 2, "claims": [], "siege": -1, "battle": 0}}
	b.intel[6] = {"day": 3, "info": {"owner": -1, "claims": [], "siege": -1, "battle": 0}}
	Intel.share(a, b)
	_ok(int(a.intel[5]["info"]["owner"]) == 2 and int(a.intel[5]["day"]) == 30, "partage : le relevé le plus récent l'emporte")
	_ok(int(b.intel[5]["day"]) == 30 and a.intel.has(6), "partage : chacun reçoit ce que l'autre sait")


func _test_determinism() -> void:
	var a := Simulation.new(GameState.create(14))
	var b := Simulation.new(GameState.create(14))
	a.advance(150)
	b.advance(150)
	var same := a.state.checksum() == b.state.checksum()
	for i in a.state.empires.size():
		if Intel.to_list(a.state.empires[i]) != Intel.to_list(b.state.empires[i]):
			same = false
	_ok(same, "mémoires identiques entre deux parties de même graine")
	var rival := a.state.get_empire(1)
	_ok(rival.intel.size() >= rival.explored.size() - 2, "l'IA tient sa mémoire à jour en explorant")


func _test_display() -> void:
	var sim := Simulation.new(GameState.create(15))
	var st := sim.state
	var y := _far_free_system(st, 0)
	if y < 0:
		return
	_glimpse(sim, 0, y)
	var pid: int = st.galaxy.get_system(y).planet_ids[0]
	_claim(st, 1, pid)
	var p := st.galaxy.get_planet(pid)
	Intel.lens = 0
	_ok(PlanetInfo.status_line(st, p) == "Libre", "fiche de planète : dernière information connue pour le joueur")
	_ok(Intel.shown_owner(st, y) == -1, "interface : propriétaire mémorisé")
	Intel.lens = -1
	_ok(PlanetInfo.status_line(st, p) != "Libre", "fiche de planète : état réel pour le spectateur")
	var view := GalaxyView.new()
	view.set_state(st)
	view.viewer = 0
	view.fog = true
	view._seen = Fleets.visible_systems(st, 0)
	_ok(view.owner_of(y) == -1 and view.colony_of(pid) == null, "carte : système hors de vue montré tel qu'on l'a vu")
	view.fog = false
	_ok(view.owner_of(y) == 1, "carte sans brouillard : état réel")
	view.free()
