extends RefCounted
## Tests des flottes, des déplacements, du brouillard de guerre et de la colonisation par vaisseau colon,
## appelés par smoke_test.gd.

const TEST_SAVE := "user://saves/test_fleets.json"

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Flottes et exploration…")
	_test_start()
	_test_move()
	_test_move_refusals()
	_test_turn_around_and_stop()
	_test_build_ship()
	_test_colony_ship()
	_test_merge_split()
	_test_upkeep()
	_test_contact()
	_test_save_and_replay()
	_test_scouting_run()
	_test_auto_explore()
	_test_auto_explore_two_scouts()
	_test_auto_explore_end()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


func _home(st: GameState, empire_id := 0) -> int:
	return st.galaxy.get_planet(st.get_empire(empire_id).capital_planet).system_id


func _fleet_with(st: GameState, empire_id: int, ship_id: String) -> Fleet:
	for f in Fleets.empire_fleets(st, empire_id):
		if f.count(ship_id) > 0:
			return f
	return null


## Avance jusqu'à ce que la flotte s'arrête (au plus max_days). Renvoie les jours écoulés.
func _run_until_stopped(sim: Simulation, fleet_id: int, max_days := 400) -> int:
	sim.flush_commands()
	var days := 0
	while days < max_days and sim.state.fleets.has(fleet_id) and sim.state.fleets[fleet_id].is_moving():
		sim.step()
		days += 1
	return days


## Un système connu mais pas encore exploré, à deux sauts du système d'origine.
func _frontier_system(st: GameState, empire_id: int) -> int:
	for s in st.galaxy.systems:
		if not Fleets.is_explored(st, empire_id, s.id) and Fleets.is_known(st, empire_id, s.id):
			return s.id
	return -1


func _test_start() -> void:
	var st := GameState.create(11)
	for e in st.empires:
		var fleets := Fleets.empire_fleets(st, e.id)
		var home := _home(st, e.id)
		_ok(fleets.size() == 2, "%s : deux flottes au départ (obtenu %d)" % [e.faction_id, fleets.size()])
		var settler := "spore_ship" if e.faction_id == "khthari" else "colony_ship"
		_ok(_fleet_with(st, e.id, "scout") != null and _fleet_with(st, e.id, settler) != null,
				"%s : un éclaireur et un vaisseau colon (%s)" % [e.faction_id, settler])
		var all_home := true
		for f in fleets:
			all_home = all_home and f.system_id == home and not f.is_moving()
		_ok(all_home, "%s : flottes à l'arrêt au système d'origine" % e.faction_id)
		# Vision de départ : l'éclaireur voit à 2 sauts.
		var ok := e.explored.has(home)
		for n in st.galaxy.systems[home].neighbors:
			ok = ok and e.explored.has(n)
			for n2 in st.galaxy.systems[n].neighbors:
				ok = ok and e.explored.has(n2)
		_ok(ok, "%s : origine et systèmes à 2 sauts explorés" % e.faction_id)
		_ok(e.explored.size() < st.galaxy.systems.size() / 4, "%s : la majeure partie de la galaxie est dans le brouillard (%d explorés)" % [e.faction_id, e.explored.size()])
	_ok(_fleet_with(st, 0, "scout").fleet_name == "Éclaireur 1", "les flottes sont nommées d'après leur vaisseau")


func _test_move() -> void:
	var st := GameState.create(12)
	var sim := Simulation.new(st)
	var scout := _fleet_with(st, 0, "scout")
	var target := _frontier_system(st, 0)
	_ok(target != -1, "un système connu mais inexploré existe")
	var path := Fleets.find_path(st, 0, scout.system_id, target)
	_ok(path.size() >= 3 and path[-1] == target, "chemin de %d sauts vers la frontière" % path.size())
	var linked := true
	var prev := scout.system_id
	for s in path:
		linked = linked and st.galaxy.systems[prev].neighbors.has(s)
		prev = s
	_ok(linked, "le chemin suit les routes de saut")
	var plan := Fleets.plan_route(st, scout, target)
	var expected := Fleets.route_days(st, scout, plan)
	_ok(sim.submit(SimCommands.move_fleet(0, scout.id, target)), "ordre de déplacement accepté")
	sim.flush_commands()
	_ok(scout.is_moving() and scout.destination() == target, "la flotte part vers sa destination")
	_ok(Fleets.eta_days(st, scout) == expected, "délai annoncé = délai de l'itinéraire (%d j)" % expected)
	var mid := Fleets.position(st, scout)
	sim.step()
	_ok(scout.progress == Fleets.speed(scout, st) or scout.system_id != st.galaxy.get_planet(st.get_empire(0).capital_planet).system_id,
			"la flotte avance de sa vitesse chaque jour")
	_ok(Fleets.position(st, scout) != mid, "sa position sur la carte change")
	var days := 1 + _run_until_stopped(sim, scout.id)
	_ok(scout.system_id == target and not scout.is_moving() and scout.progress == 0, "arrivée à destination")
	_ok(days == expected, "arrivée au jour prévu (%d j, prévu %d)" % [days, expected])
	_ok(Fleets.is_explored(st, 0, target), "le système d'arrivée est exploré")
	var beyond := 0
	for n in st.galaxy.systems[target].neighbors:
		if Fleets.is_explored(st, 0, n):
			beyond += 1
	_ok(beyond == st.galaxy.systems[target].neighbors.size(), "l'éclaireur voit les systèmes voisins de son arrivée")


func _test_move_refusals() -> void:
	var st := GameState.create(13)
	var sim := Simulation.new(st)
	var scout := _fleet_with(st, 0, "scout")
	var unknown := -1
	for s in st.galaxy.systems:
		if unknown == -1 and not Fleets.is_known(st, 0, s.id):
			unknown = s.id
	_ok(not sim.submit(SimCommands.move_fleet(0, scout.id, unknown)), "refus : système hors des cartes")
	_ok(not sim.submit(SimCommands.move_fleet(0, scout.id, scout.system_id)), "refus : la flotte y est déjà")
	_ok(not sim.submit(SimCommands.move_fleet(1, scout.id, st.galaxy.systems[scout.system_id].neighbors[0])), "refus : flotte d'un autre empire")
	_ok(not sim.submit(SimCommands.move_fleet(0, 9999, 0)), "refus : flotte inconnue")
	_ok(not sim.submit(SimCommands.move_fleet(0, scout.id, 99999)), "refus : système inconnu")
	_ok(not sim.submit(SimCommands.stop_fleet(0, scout.id)), "refus : arrêter une flotte déjà à l'arrêt")


func _test_turn_around_and_stop() -> void:
	var st := GameState.create(14)
	var sim := Simulation.new(st)
	var scout := _fleet_with(st, 0, "scout")
	var home := scout.system_id
	var n: int = st.galaxy.systems[home].neighbors[0]
	sim.submit(SimCommands.move_fleet(0, scout.id, n))
	sim.flush_commands()
	sim.step()
	var lane := Fleets.lane_length(st.galaxy, home, n)
	var done := scout.progress
	_ok(scout.is_moving() and done > 0 and done < lane, "en route sur la première route")
	_ok(sim.submit(SimCommands.move_fleet(0, scout.id, home)), "nouvel ordre en plein trajet accepté")
	sim.flush_commands()
	_ok(scout.system_id == n and scout.path == [home] and scout.progress == lane - done,
			"demi-tour : la flotte repart vers son point de départ sans téléporter")
	var days := _run_until_stopped(sim, scout.id)
	@warning_ignore("integer_division")
	var expected_days := (done + Fleets.speed(scout, st) - 1) / Fleets.speed(scout, st)
	_ok(scout.system_id == home and days == expected_days, "retour au départ en %d j (prévu %d)" % [days, expected_days])
	# Arrêt en route : on rebrousse chemin si on est à moins de la moitié.
	sim.submit(SimCommands.move_fleet(0, scout.id, n))
	sim.flush_commands()
	sim.step()
	_ok(sim.submit(SimCommands.stop_fleet(0, scout.id)), "ordre d'arrêt accepté")
	sim.flush_commands()
	_run_until_stopped(sim, scout.id)
	_ok(scout.system_id == (home if done * 2 < lane else n), "arrêt au système le plus proche")


func _test_build_ship() -> void:
	var st := GameState.create(15)
	var sim := Simulation.new(st)
	var e := st.get_empire(0)
	var cap := e.capital_planet
	var before := e.resources.duplicate()
	var cost: Dictionary = GameData.ship("scout")["cost"]
	_ok(sim.submit(SimCommands.build_ship(0, cap, "scout")), "construction d'un éclaireur acceptée")
	sim.flush_commands()
	_ok(st.colonies[cap].ship_build == "scout", "le chantier spatial est occupé")
	_ok(e.resources["materials"] == before["materials"] - int(cost["materials"]), "le coût est payé à la commande")
	_ok(not sim.submit(SimCommands.build_ship(0, cap, "colony_ship")), "refus : chantier spatial occupé")
	_ok(not sim.submit(SimCommands.build_ship(0, cap, "dreadnought")), "refus : classe inconnue")
	_ok(not sim.submit(SimCommands.build_ship(1, cap, "scout")), "refus : planète d'un autre empire")
	# Le chantier spatial n'empêche pas les bâtiments.
	var b_ok := false
	for bid in GameData.buildings():
		if Economy.check_build(st, 0, cap, bid) == "":
			b_ok = true
	_ok(b_ok, "un bâtiment reste possible pendant la construction d'un vaisseau")
	var n_before := Fleets.empire_fleets(st, 0).size()
	sim.advance(int(GameData.ship("scout")["days"]) - 1)
	_ok(Fleets.empire_fleets(st, 0).size() == n_before, "pas de vaisseau avant la fin du chantier")
	sim.step()
	var fleets := Fleets.empire_fleets(st, 0)
	_ok(fleets.size() == n_before + 1, "le vaisseau sort du chantier au jour prévu")
	var newest := fleets[-1]
	_ok(newest.ships == ["scout"] and newest.system_id == _home(st) and newest.fleet_name == "Éclaireur 2", "nouvelle flotte en orbite : %s" % newest.fleet_name)
	_ok(st.colonies[cap].ship_build == "", "le chantier spatial est libéré")
	_ok(st.chronicle.back()["text"].contains("Éclaireur 2"), "la chronique annonce le nouveau vaisseau")
	# Un avant-poste ne construit pas de vaisseaux.
	var outpost := -1
	for pid in st.galaxy.systems[_home(st)].planet_ids:
		if outpost == -1 and Economy.check_colonize(st, 0, pid, Colony.KIND_OUTPOST) == "":
			outpost = pid
	if outpost != -1:
		sim.submit(SimCommands.colonize(0, outpost, Colony.KIND_OUTPOST))
		sim.advance(Economy.claim_days(Colony.KIND_OUTPOST) + 1)
		_ok(not sim.submit(SimCommands.build_ship(0, outpost, "scout")), "refus : pas de chantier spatial sur un avant-poste")
	e.resources["materials"] = 0
	_ok(not sim.submit(SimCommands.build_ship(0, cap, "scout")), "refus : ressources insuffisantes")


func _test_colony_ship() -> void:
	var st := GameState.create(16)
	var sim := Simulation.new(st)
	var e := st.get_empire(0)
	var home := _home(st)
	var colonist := _fleet_with(st, 0, "colony_ship")
	# Une planète libre dans un système voisin.
	var target := -1
	for n in st.galaxy.systems[home].neighbors:
		if st.system_owner(n) == -1:
			for pid in st.galaxy.systems[n].planet_ids:
				if target == -1:
					target = pid
	_ok(target != -1, "une planète libre dans un système voisin")
	var dest := st.galaxy.get_planet(target).system_id
	_ok(not Economy.in_range(st, 0, dest), "sans vaisseau, un système voisin est hors de portée")
	_ok(Economy.check_colonize(st, 0, target, Colony.KIND_OUTPOST).contains("vaisseau colon"), "le refus parle du vaisseau colon")
	sim.submit(SimCommands.move_fleet(0, colonist.id, dest))
	sim.flush_commands()
	_ok(not Economy.in_range(st, 0, dest), "un vaisseau en route ne compte pas encore")
	_run_until_stopped(sim, colonist.id)
	_ok(colonist.system_id == dest and Economy.in_range(st, 0, dest), "arrivé : le système est à portée")
	var cost := Economy.claim_cost_for(st, 0, target, Colony.KIND_OUTPOST)
	_ok(not cost.has("materials"), "avec un vaisseau colon, les matériaux sont déjà payés (%s)" % GameData.format_amounts(cost))
	var inf_before := int(e.resources["influence"])
	_ok(sim.submit(SimCommands.colonize(0, target, Colony.KIND_OUTPOST)), "colonisation par vaisseau colon acceptée")
	sim.flush_commands()
	_ok(st.colonies.has(target) and st.colonies[target].owner == 0, "la revendication est lancée")
	_ok(not st.fleets.has(colonist.id), "le vaisseau colon s'est démonté (flotte dissoute)")
	_ok(int(e.resources["influence"]) == inf_before - int(cost.get("influence", 0)), "seule l'influence est payée")
	_ok(st.system_owner(dest) == 0, "le système est revendiqué")
	# Plus de vaisseau colon : une autre planète du système attend que l'avant-poste soit établi.
	var other := -1
	for pid in st.galaxy.systems[dest].planet_ids:
		if pid != target and other == -1:
			other = pid
	if other != -1:
		_ok(Economy.check_colonize(st, 0, other, Colony.KIND_OUTPOST) != "", "pas de seconde revendication avant l'établissement")
		sim.advance(Economy.claim_days(Colony.KIND_OUTPOST) + 1)
		_ok(Economy.has_foothold(st, 0, dest) and not Economy.needs_ship(st, 0, other), "une fois établi, le système sert de base")


func _test_merge_split() -> void:
	var st := GameState.create(17)
	var sim := Simulation.new(st)
	var scout := _fleet_with(st, 0, "scout")
	var colonist := _fleet_with(st, 0, "colony_ship")
	_ok(not sim.submit(SimCommands.merge_fleets(0, scout.id, scout.id)), "refus : fusion avec soi-même")
	_ok(sim.submit(SimCommands.merge_fleets(0, scout.id, colonist.id)), "fusion acceptée")
	sim.flush_commands()
	_ok(not st.fleets.has(scout.id) and colonist.ships == ["colony_ship", "scout"], "les vaisseaux passent dans la flotte d'accueil")
	_ok(Fleets.speed(colonist) == int(GameData.ship("colony_ship")["speed"]), "la flotte va à la vitesse du plus lent")
	_ok(Fleets.vision(colonist) == int(GameData.ship("scout")["vision"]), "et voit aussi loin que le meilleur")
	_ok(Fleets.composition(colonist) == "Vaisseau colon, Éclaireur", "composition lisible : %s" % Fleets.composition(colonist))
	_ok(sim.submit(SimCommands.split_fleet(0, colonist.id, "scout")), "détachement accepté")
	sim.flush_commands()
	_ok(colonist.ships == ["colony_ship"] and Fleets.empire_fleets(st, 0).size() == 2, "le vaisseau détaché forme une nouvelle flotte")
	_ok(not sim.submit(SimCommands.split_fleet(0, colonist.id, "colony_ship")), "refus : détacher le dernier vaisseau")
	var n: int = st.galaxy.systems[colonist.system_id].neighbors[0]
	var other := Fleets.empire_fleets(st, 0)[-1]
	sim.submit(SimCommands.move_fleet(0, other.id, n))
	sim.flush_commands()
	_ok(not sim.submit(SimCommands.merge_fleets(0, other.id, colonist.id)), "refus : fusion avec une flotte en route")


func _test_upkeep() -> void:
	var st := GameState.create(18)
	var up := Fleets.upkeep(st, 0)
	_ok(int(up.get("energy", 0)) == 2, "deux vaisseaux : 2 Én d'entretien par mois")
	var income := Economy.empire_income(st, 0)
	var colony_upkeep := 0
	for pid in st.sorted_colony_ids():
		if st.colonies[pid].owner == 0:
			colony_upkeep += int(Economy.colony_yields(st, st.colonies[pid])["upkeep"]["energy"])
	_ok(int(income["upkeep"]["energy"]) == colony_upkeep + 2, "l'entretien des flottes compte dans le bilan")


func _test_contact() -> void:
	var st := GameState.create(19)
	_ok(st.get_empire(0).contacts.is_empty(), "aucun contact au départ")
	var scout := _fleet_with(st, 0, "scout")
	scout.system_id = _home(st, 2)  # on dépose l'éclaireur chez un voisin
	var added := FleetSystem.update_exploration(st)
	_ok(st.get_empire(0).contacts.has(2) and st.get_empire(2).contacts.has(0), "premier contact, retenu des deux côtés")
	_ok(added.size() >= 1 and String(added[0]["text"]).contains("Premier contact"), "la chronique raconte la rencontre")
	_ok(FleetSystem.update_exploration(st).is_empty(), "une seule fois")
	var seen := Fleets.visible_systems(st, 2)
	_ok(Fleets.fleet_visible(st, 2, scout, seen), "l'empire visité voit l'éclaireur chez lui")
	var far_seen := Fleets.visible_systems(st, 1)
	_ok(not Fleets.fleet_visible(st, 1, scout, far_seen) or st.get_empire(1).contacts.has(0), "un empire lointain ne le voit pas")


func _test_save_and_replay() -> void:
	var a := Simulation.new(GameState.create(2026))
	var scout := _fleet_with(a.state, 0, "scout")
	var colonist := _fleet_with(a.state, 0, "colony_ship")
	a.submit(SimCommands.move_fleet(0, scout.id, _frontier_system(a.state, 0)))
	a.submit(SimCommands.move_fleet(0, colonist.id, a.state.galaxy.systems[colonist.system_id].neighbors[0]))
	a.submit(SimCommands.build_ship(0, a.state.get_empire(0).capital_planet, "scout"))
	a.advance(3)
	_ok(scout.is_moving() and scout.progress > 0, "sauvegarde en plein trajet")
	var d := a.state.to_dict()
	var b_state := GameState.from_dict(JSON.parse_string(JSON.stringify(d)))
	_ok(b_state != null, "état avec flottes relu (%s)" % GameState.last_error)
	if b_state == null:
		return
	_ok(b_state.checksum() == a.state.checksum(), "même empreinte après aller-retour JSON")
	SaveGame.save_state(a.state, TEST_SAVE)
	var loaded := SaveGame.load_state(TEST_SAVE)
	_ok(loaded != null and loaded.checksum() == a.state.checksum(), "sauvegarde sur disque relue à l'identique")
	DirAccess.remove_absolute(TEST_SAVE)
	var b := Simulation.new(b_state)
	a.advance(200)
	b.advance(200)
	_ok(a.state.checksum() == b.state.checksum(), "la partie rechargée continue à l'identique")
	var replayed := Simulation.replay(GameState.create(2026), a.command_log, a.state.tick)
	_ok(replayed.state.checksum() == a.state.checksum(), "rediffusion d'une partie avec flottes")
	var bad := d.duplicate(true)
	bad["fleets"][0]["ships"] = ["vaisseau_imaginaire"]
	_ok(GameState.from_dict(bad) == null, "flotte invalide refusée au chargement")


## Un éclaireur qui part au bout de la galaxie : il finit par tout explorer sur son passage.
func _test_scouting_run() -> void:
	var sim := Simulation.new(GameState.create(31))
	var st := sim.state
	var scout := _fleet_with(st, 0, "scout")
	var start := st.get_empire(0).explored.size()
	var trips := 0
	for _i in 12:
		var target := _frontier_system(st, 0)
		if target == -1 or Fleets.check_move(st, 0, scout.id, target) != "":
			break
		sim.submit(SimCommands.move_fleet(0, scout.id, target))
		_run_until_stopped(sim, scout.id)
		trips += 1
	_ok(trips == 12, "12 expéditions successives possibles (obtenu %d)" % trips)
	_ok(st.get_empire(0).explored.size() > start + 10, "l'exploration progresse (%d -> %d systèmes)" % [start, st.get_empire(0).explored.size()])
	print("  éclaireur : %d systèmes explorés en %d jours" % [st.get_empire(0).explored.size(), st.tick])


## Exploration automatique : l'éclaireur part seul, ne s'arrête pas tant qu'il reste de l'inconnu,
## rend la main à un ordre manuel, survit à la sauvegarde et se rediffuse à l'identique.
func _test_auto_explore() -> void:
	var sim := Simulation.new(GameState.create(31))
	var st := sim.state
	var scout := _fleet_with(st, 0, "scout")
	var colonist := _fleet_with(st, 0, "colony_ship")
	var start := st.get_empire(0).explored.size()
	_ok(scout.is_idle() and Fleets.idle_fleets(st, 0).size() == 2, "au départ, les deux flottes attendent des ordres")
	_ok(Fleets.check_order(st, 0, scout.id, "patrouille_imaginaire") != "", "ordre permanent inconnu refusé")
	_ok(Fleets.check_order(st, 1, scout.id, Fleet.ORDER_EXPLORE) != "", "on ne donne pas d'ordre à la flotte d'un autre")
	_ok(Fleets.check_order(st, 0, scout.id, "") != "", "rien à annuler sur une flotte sans ordre permanent")
	sim.submit(SimCommands.set_fleet_order(0, scout.id, Fleet.ORDER_EXPLORE))
	sim.flush_commands()
	_ok(scout.is_exploring() and scout.is_moving(), "exploration auto : l'éclaireur part aussitôt")
	_ok(not Fleets.is_explored(st, 0, scout.destination()), "il vise un système inexploré")
	_ok(Fleets.idle_fleets(st, 0).size() == 1 and Fleets.idle_fleets(st, 0)[0].id == colonist.id, "il ne compte plus parmi les flottes inactives")
	var stopped_days := 0
	for _d in 240:
		sim.step()
		if not scout.is_moving():
			stopped_days += 1
	_ok(scout.is_exploring(), "toujours en exploration après 240 jours")
	_ok(stopped_days == 0, "l'éclaireur ne reste jamais à l'arrêt (obtenu %d jours)" % stopped_days)
	var explored := st.get_empire(0).explored.size()
	_ok(explored > start + 30, "l'exploration auto découvre la galaxie (%d -> %d systèmes)" % [start, explored])
	print("  exploration auto : %d systèmes explorés en %d jours" % [explored, st.tick])
	# Sauvegarde et rediffusion.
	var loaded := GameState.from_dict(JSON.parse_string(JSON.stringify(st.to_dict())))
	_ok(loaded != null and loaded.fleets[scout.id].is_exploring(), "l'ordre d'exploration est sauvegardé")
	var b := Simulation.new(loaded)
	sim.advance(60)
	b.advance(60)
	_ok(sim.state.checksum() == b.state.checksum(), "exploration auto déterministe après rechargement")
	var replayed := Simulation.replay(GameState.create(31), sim.command_log, st.tick)
	_ok(replayed.state.checksum() == st.checksum(), "rediffusion d'une partie avec exploration auto")
	# Un ordre manuel reprend la main.
	sim.submit(SimCommands.move_fleet(0, scout.id, _home(st)))
	sim.flush_commands()
	_ok(not scout.is_exploring() and scout.destination() == _home(st), "un ordre de déplacement coupe l'exploration auto")
	sim.submit(SimCommands.set_fleet_order(0, scout.id, Fleet.ORDER_EXPLORE))
	sim.flush_commands()
	sim.submit(SimCommands.set_fleet_order(0, scout.id, ""))
	sim.flush_commands()
	_ok(not scout.is_exploring(), "l'exploration auto se coupe")
	# Une ancienne sauvegarde (sans le champ) se relit sans ordre.
	var d := st.to_dict()
	for fd in d["fleets"]:
		fd.erase("order")
	var old := GameState.from_dict(d)
	_ok(old != null and old.fleets[scout.id].standing_order == "", "sauvegarde sans ordre permanent relue")


## Deux éclaireurs en exploration ne visent pas le même système.
func _test_auto_explore_two_scouts() -> void:
	var sim := Simulation.new(GameState.create(47))
	var st := sim.state
	var a := _fleet_with(st, 0, "scout")
	var b := st.spawn_ship(0, "scout", a.system_id)
	sim.submit(SimCommands.set_fleet_order(0, a.id, Fleet.ORDER_EXPLORE))
	sim.submit(SimCommands.set_fleet_order(0, b.id, Fleet.ORDER_EXPLORE))
	sim.flush_commands()
	_ok(a.is_moving() and b.is_moving() and a.destination() != b.destination(), "deux éclaireurs, deux cibles différentes")
	var same := 0
	for _d in 120:
		sim.step()
		if a.is_moving() and b.is_moving() and a.destination() == b.destination():
			same += 1
	_ok(same <= 5, "ils se répartissent la frontière (même cible %d jours sur 120)" % same)


## Quand tout est exploré, l'ordre s'arrête, la chronique le dit, et la flotte redevient inactive.
func _test_auto_explore_end() -> void:
	var sim := Simulation.new(GameState.create(5))
	var st := sim.state
	var scout := _fleet_with(st, 0, "scout")
	sim.submit(SimCommands.set_fleet_order(0, scout.id, Fleet.ORDER_EXPLORE))
	sim.flush_commands()
	var e := st.get_empire(0)
	for sys in st.galaxy.systems:
		e.explored[sys.id] = true
	sim.step()
	sim.step()  # arrivée ou cible explorée : plus rien à viser
	var guard := 0
	while scout.is_moving() and guard < 400:
		sim.step()
		guard += 1
	_ok(not scout.is_exploring() and scout.is_idle(), "plus rien à explorer : l'ordre s'arrête")
	_ok(st.chronicle.any(func(c: Dictionary) -> bool: return String(c["text"]).contains(scout.fleet_name) and String(c["text"]).contains("cartographié")),
			"la chronique annonce la fin de l'exploration")
	_ok(Fleets.check_order(st, 0, scout.id, Fleet.ORDER_EXPLORE) != "", "exploration refusée quand il n'y a plus rien à voir")
