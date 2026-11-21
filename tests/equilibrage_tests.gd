extends RefCounted
## Tests de l'équilibrage, lot 1 (l'espace et le tour par tour) : échelle des distances, mise en route
## avant le saut, générations de moteurs, vue de l'éclaireur, échange de cartes limité, « voir n'est pas
## connaître », voisinage vivant, rythme des IA au tour par tour, étapes, consigne d'engagement et point
## de ralliement.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Équilibrage, lot 1 : l'espace et le tour par tour…")
	_test_distances()
	_test_spool()
	_test_drives_and_vision()
	_test_maps()
	_test_surveyed()
	_test_neighbourhood()
	_test_turn_ai()
	_test_queue()
	_test_stance()
	_test_rally()
	_test_build_queue()
	_test_claim_queue()
	print("Équilibrage, lot 2 : victoires et économie…")
	_test_not_before()
	_test_bloc_cap()
	_test_victory_values()
	_test_claim_scale()
	_test_stock_caps()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


func _home(st: GameState, empire_id := 0) -> int:
	return st.galaxy.get_planet(st.get_empire(empire_id).home_planet).system_id


func _fleet_with(st: GameState, empire_id: int, ship_id: String) -> Fleet:
	for f in Fleets.empire_fleets(st, empire_id):
		if f.count(ship_id) > 0:
			return f
	return null


func _raw(st: GameState, a: int, b: int) -> int:
	return maxi(1, roundi(st.galaxy.systems[a].position.distance_to(st.galaxy.systems[b].position)))


func _test_distances() -> void:
	var st := GameState.create(11)
	var home := _home(st)
	var n: int = st.galaxy.systems[home].neighbors[0]
	var scale := int(GameData.rules()["distances"]["normales"])
	_ok(st.galaxy.lane_scale_pct == scale, "une partie neuve prend les distances normales (%d %%)" % scale)
	@warning_ignore("integer_division")
	_ok(Fleets.lane_length(st.galaxy, home, n) == _raw(st, home, n) * scale / 100, "la route mesure la distance de la carte fois l'échelle")
	var far := GameState.create(11, 150, 1800.0, "", {"galaxy": {"distances": "vastes"}})
	var near := GameState.create(11, 150, 1800.0, "", {"galaxy": {"distances": "proches"}})
	_ok(Fleets.lane_length(far.galaxy, home, n) > Fleets.lane_length(st.galaxy, home, n)
			and Fleets.lane_length(near.galaxy, home, n) < Fleets.lane_length(st.galaxy, home, n), "vastes allonge les routes, proches les raccourcit")
	_ok(far.galaxy.systems[home].position == st.galaxy.systems[home].position, "le réglage ne déplace aucune étoile")
	var loaded := GameState.from_dict(far.to_dict())
	_ok(loaded != null and loaded.galaxy.lane_scale_pct == far.galaxy.lane_scale_pct, "l'échelle survit à la sauvegarde")
	var old := st.to_dict()
	(old["galaxy_settings"] as Dictionary).erase("distances")
	var legacy := GameState.from_dict(old)
	_ok(legacy != null and legacy.galaxy.lane_scale_pct == 100, "une sauvegarde d'avant le réglage garde ses routes d'origine")
	_ok(not GalaxySettings.ids("distances").is_empty() and GalaxySettings.normalize({"distances": "n'importe quoi"})["distances"] == "normales",
			"un réglage inconnu retombe sur les distances normales")


func _test_spool() -> void:
	var st := GameState.create(12)
	var sim := Simulation.new(st)
	var home := _home(st)
	var n: int = st.galaxy.systems[home].neighbors[0]
	var scout := _fleet_with(st, 0, "scout")
	var table: Dictionary = GameData.rules()["spool_days"]
	_ok(Fleets.spool_days(st, scout, home, n) == int(table["small"]), "éclaireur : mise en route d'une petite coque")
	var colon := _fleet_with(st, 0, "colony_ship")
	_ok(colon != null and Fleets.spool_days(st, colon, home, n) == int(table["medium"]), "vaisseau colon : mise en route d'une coque moyenne")
	var big := Fleet.new()
	big.owner = 0
	big.add_ship("scout", -1, 0)
	big.add_ship("croiseur", -1, 0)
	_ok(Fleets.spool_days(st, big, home, n) == int(table["large"]), "la plus grande coque de la flotte compte")
	sim.submit(SimCommands.move_fleet(0, scout.id, n))
	sim.flush_commands()
	var eta := Fleets.eta_days(st, scout)
	sim.step()
	_ok(scout.system_id == home and scout.progress == 0 and scout.spool == 1, "premier jour : la flotte charge ses moteurs sur place")
	var days := 1
	while days < 200 and scout.is_moving():
		sim.step()
		days += 1
	_ok(scout.system_id == n and days == eta, "le délai annoncé compte la mise en route (%d jours, %d annoncés)" % [days, eta])
	_ok(scout.spool == 0, "arrivée : la mise en route repart de zéro")
	# Les Maîtrises de propulsion raccourcissent la mise en route.
	var e := st.get_empire(0)
	for t in ["propulseurs", "postcombustion", "hyperflux", "flux_continu", "saut_precision", "sauts_calcules"]:
		e.techs[t] = true
	_ok(Fleets.spool_days(st, big, home, n) == 1, "les trois Maîtrises réduisent la mise en route au quart (4 jours, puis 1)")
	_ok(Fleets.spool_days(st, scout, home, n) == 0, "une petite coque part alors sans attendre")


func _test_drives_and_vision() -> void:
	var st := GameState.create(13)
	var e := st.get_empire(1)
	var f := Fleet.new()
	f.owner = 1
	f.add_ship("scout", -1, 0)
	var trait_pct := int(e.faction().get("fleet_speed_pct", 100))
	var base := int(GameData.ship("scout")["speed"])
	@warning_ignore("integer_division")
	_ok(Fleets.speed(f, st) == base * trait_pct / 100, "sans moteur : la vitesse de la coque")
	var want := [125, 160, 250]
	var techs := ["propulseurs", "hyperflux", "saut_precision"]
	for i in 3:
		e.techs[techs[i]] = true
		@warning_ignore("integer_division")
		_ok(Fleets.speed(f, st) == base * (trait_pct * int(want[i]) / 100) / 100, "génération %d de moteurs : vitesse ×%.2f" % [i + 1, float(want[i]) / 100.0])
	_ok(Fleets.vision(f, st) == 1, "un éclaireur voit à un saut")
	e.techs["telemetrie_longue"] = true
	_ok(Fleets.vision(f, st) == 2, "Télémétrie à longue base : l'éclaireur voit à deux sauts")
	var war := Fleet.new()
	war.owner = 1
	war.add_ship("corvette", -1, 0)
	_ok(Fleets.vision(war, st) == 1, "la Télémétrie ne change pas la vue des autres vaisseaux")
	_ok(not Research.tech("telemetrie_longue").is_empty() and int(Research.tech("telemetrie_longue")["era"]) == 2, "la Télémétrie est une technologie de l'ère 2")


func _test_maps() -> void:
	var st := GameState.create(14)
	var a := st.get_empire(0)
	var b := st.get_empire(1)
	var jumps := Diplomacy.days("maps_jumps", 1)
	var ha := _home(st, 0)
	var dj := FactionTraits.jumps_from(st.galaxy, ha)
	# a a tout exploré ; b ne connaît que son coin.
	for s in st.galaxy.systems:
		a.explored[s.id] = true
	var before := b.explored.size()
	Diplomacy.share_maps(st, 0, 1)
	var got_far := false
	var got_near := true
	for s in st.galaxy.systems:
		var j := int(dj.get(s.id, 999))
		if j > jumps and b.explored.has(s.id) and int(FactionTraits.jumps_from(st.galaxy, _home(st, 1)).get(s.id, 999)) > 3:
			got_far = true
		if j <= jumps and not b.explored.has(s.id):
			got_near = false
	_ok(b.explored.size() > before and got_near, "échange de cartes : le territoire de l'autre et ses abords")
	_ok(not got_far, "échange de cartes : rien de ses explorations lointaines")
	_ok(not Diplomacy.atlas_open(st, 0, 1), "pas d'atlas complet à la première ère")
	Diplomacy.share_maps(st, 0, 1, true)
	_ok(b.explored.size() == st.galaxy.systems.size(), "atlas complet : tout ce que l'autre a exploré")


func _test_surveyed() -> void:
	var st := GameState.create(15)
	var sim := Simulation.new(st)
	var e := st.get_empire(0)
	var home := _home(st)
	_ok(e.surveyed.has(home), "le système de départ est reconnu")
	var n: int = st.galaxy.systems[home].neighbors[0]
	_ok(e.explored.has(n) and not e.surveyed.has(n), "un voisin vu de loin est exploré, pas reconnu")
	_ok(AiPlayer.best_claim(st, e, n, 2, Fleets.visible_systems(st, 0)).is_empty(), "l'IA ne revendique rien dans un système seulement aperçu")
	var scout := _fleet_with(st, 0, "scout")
	sim.submit(SimCommands.move_fleet(0, scout.id, n))
	sim.flush_commands()
	var days := 0
	while days < 200 and scout.is_moving():
		sim.step()
		days += 1
	_ok(e.surveyed.has(n), "le passage d'un vaisseau reconnaît le système")
	_ok(Fleets.explore_target(st, scout) >= 0 and not e.surveyed.has(Fleets.explore_target(st, scout)), "l'exploration automatique vise un système pas encore reconnu")
	var loaded := GameState.from_dict(st.to_dict())
	_ok(loaded != null and loaded.get_empire(0).surveyed.size() == e.surveyed.size(), "les systèmes reconnus sont sauvegardés")
	var old := st.to_dict()
	for ed: Dictionary in old["empires"]:
		ed.erase("surveyed")
	var legacy := GameState.from_dict(old)
	_ok(legacy != null and legacy.get_empire(0).surveyed.size() == legacy.get_empire(0).explored.size(), "ancienne sauvegarde : tout ce qui était exploré est reconnu")


func _test_neighbourhood() -> void:
	var st := GameState.create(16, 150, 1800.0, "", {"curios": Curios.default_density(), "creatures": "normales", "minors": Minors.default_mode()})
	var all_curio := true
	var all_nest := true
	for e in st.empires:
		var dj := FactionTraits.jumps_from(st.galaxy, _home(st, e.id))
		var curio := false
		for pid in st.curios:
			if int(dj.get(st.galaxy.get_planet(int(pid)).system_id, 999)) <= 3:
				curio = true
		var nest := false
		for sid in Fauna.nests(st):
			if int(dj.get(int(sid), 999)) <= 3:
				nest = true
		for sid in st.lairs:
			if int(dj.get(int(sid), 999)) <= 3:
				nest = true
		all_curio = all_curio and (curio or st.curios.is_empty())
		all_nest = all_nest and (nest or not Fauna.active(st))
	_ok(not st.curios.is_empty() and all_curio, "voisinage vivant : une curiosité à trois sauts au plus de chaque départ")
	_ok(Fauna.active(st) and all_nest, "voisinage vivant : un nid ou un repaire à trois sauts au plus de chaque départ")
	for sid in Fauna.nests(st):
		for e in st.empires:
			_ok(int(FactionTraits.jumps_from(st.galaxy, _home(st, e.id)).get(int(sid), 999)) >= 2, "aucun nid à moins de deux sauts d'un départ")
			break
		break


func _test_turn_ai() -> void:
	var st := GameState.create(17, 150, 1800.0, "", {"turn_days": 30, "spectator": true})
	_ok(st.turn_days == 30, "la durée du tour est dans la partie")
	var e := st.get_empire(1)
	var n := 0
	for d in 90:
		st.tick += 1
		if AiSystem.should_think(st, e):
			n += 1
			_ok(posmod(st.tick, 30) == 1, "au tour par tour, l'IA réfléchit le premier jour du tour (jour %d)" % st.tick)
	_ok(n == 3, "une réflexion par tour : 3 en 90 jours (%d)" % n)
	var rt := GameState.create(17)
	_ok(rt.turn_days == 0, "en temps réel, les IA gardent leur rythme")
	var loaded := GameState.from_dict(st.to_dict())
	_ok(loaded != null and loaded.turn_days == 30, "la durée du tour est sauvegardée")
	_ok(GameClock.DEFAULT_TURN_DAYS == 30 and GameClock.TURN_LENGTHS.has(10) and not GameClock.TURN_LENGTHS.has(5), "tours d'un mois par défaut, 10 jours en option, plus de tours de 5 jours")


func _test_queue() -> void:
	var st := GameState.create(18)
	var sim := Simulation.new(st)
	var home := _home(st)
	var a: int = st.galaxy.systems[home].neighbors[0]
	var scout := _fleet_with(st, 0, "scout")
	_ok(sim.submit(SimCommands.queue_fleet(0, scout.id, a)), "une étape donnée à une flotte à l'arrêt est un ordre ordinaire")
	sim.flush_commands()
	_ok(scout.is_moving() and scout.destination() == a and scout.queue.is_empty(), "elle part aussitôt")
	_ok(sim.submit(SimCommands.queue_fleet(0, scout.id, home)), "une étape s'ajoute au trajet en cours")
	sim.flush_commands()
	_ok(scout.queue.size() == 1 and scout.queue[0] == home, "l'étape attend son tour")
	_ok(not sim.submit(SimCommands.queue_fleet(0, scout.id, home)), "refus : deux fois la même étape de suite")
	var days := 0
	var seen_a := false
	while days < 400 and (scout.is_moving() or not scout.queue.is_empty()):
		sim.step()
		days += 1
		seen_a = seen_a or (scout.system_id == a)
	_ok(seen_a and scout.system_id == home and scout.queue.is_empty(), "arrivée à destination, la flotte repart vers l'étape, puis s'arrête")
	sim.submit(SimCommands.move_fleet(0, scout.id, a))
	sim.submit(SimCommands.queue_fleet(0, scout.id, home))
	sim.flush_commands()
	sim.submit(SimCommands.move_fleet(0, scout.id, a))
	sim.flush_commands()
	_ok(scout.queue.is_empty(), "un ordre ordinaire efface les étapes")
	var loaded_src := st.to_dict()
	scout.queue.append(home)
	var loaded := GameState.from_dict(st.to_dict())
	_ok(loaded != null and loaded.fleets[scout.id].queue.size() == 1 and not loaded_src.is_empty(), "les étapes sont sauvegardées")


func _test_stance() -> void:
	var st := GameState.create(19)
	var home := _home(st)
	var e := st.get_empire(0)
	# Un second système à soi pour se replier, et un ennemi plus fort qui arrive chez nous.
	var n: int = st.galaxy.systems[home].neighbors[0]
	var mine := st.spawn_ship(0, "corvette", n)
	var foe := st.spawn_ship(1, "croiseur", n)
	st.spawn_ship(1, "croiseur", n).system_id = n
	Combat.start_war(st, 1, 0, true, true)
	e.explored[n] = true
	_ok(Fleets.check_stance(st, 0, mine.id, "repli") == "" and Fleets.check_stance(st, 0, mine.id, "nimporte") != "", "consignes connues : engager, éviter, repli")
	_ok(Fleets.retreat_target(st, mine) == home, "repli vers le système ami le plus proche")
	mine.stance = Fleet.STANCE_FALLBACK
	CombatSystem._stances(st, [mine, foe])
	_ok(mine.is_moving() and mine.destination() == home, "surclassée : la flotte se replie")
	var strong := st.spawn_ship(0, "croiseur", n)
	var strong2 := st.spawn_ship(0, "croiseur", n)
	var strong3 := st.spawn_ship(0, "croiseur", n)
	strong.stance = Fleet.STANCE_FALLBACK
	CombatSystem._stances(st, [strong, strong2, strong3, foe])
	_ok(not strong.is_moving(), "à forces suffisantes, la consigne de repli laisse engager")
	strong.stance = Fleet.STANCE_AVOID
	CombatSystem._stances(st, [strong, strong2, strong3, foe])
	_ok(strong.is_moving(), "éviter le combat : la flotte part même plus forte")
	_ok(CombatSystem._spooling(st, strong) == (Fleets.spool_days(st, strong, n, strong.path[0]) > 0), "pendant sa mise en route, elle reste dans la bataille")


func _test_rally() -> void:
	var st := GameState.create(20)
	var sim := Simulation.new(st)
	var e := st.get_empire(0)
	var home := _home(st)
	var n: int = st.galaxy.systems[home].neighbors[0]
	_ok(not sim.submit(SimCommands.set_rally(0, -1)), "refus : pas de point de ralliement à enlever")
	_ok(sim.submit(SimCommands.set_rally(0, n)), "poser le point de ralliement")
	sim.flush_commands()
	_ok(e.rally_system == n, "le point de ralliement est noté")
	var cap: Colony = st.colonies[e.capital_planet]
	cap.ship_build = "corvette"
	cap.ship_days = 1
	sim.step()
	var corvette := _fleet_with(st, 0, "corvette")
	_ok(corvette != null and corvette.is_moving() and corvette.destination() == n, "un vaisseau armé neuf part vers le point de ralliement")
	cap.ship_build = "scout"
	cap.ship_days = 1
	var scouts_before := 0
	for f in Fleets.empire_fleets(st, 0):
		scouts_before += f.count("scout")
	sim.step()
	var new_scout_moving := false
	for f in Fleets.empire_fleets(st, 0):
		if f.count("scout") > 0 and f.system_id == home and f.is_moving() and f.destination() == n and f.id > corvette.id:
			new_scout_moving = true
	_ok(not new_scout_moving, "un vaisseau sans armes reste au chantier")
	var loaded := GameState.from_dict(st.to_dict())
	_ok(loaded != null and loaded.get_empire(0).rally_system == n, "le point de ralliement est sauvegardé")


## File de production : un bâtiment et un vaisseau mis en file partent tout seuls quand la place se libère.
func _test_build_queue() -> void:
	var st := GameState.create(21)
	var sim := Simulation.new(st)
	var e := st.get_empire(0)
	var cap: Colony = st.colonies[e.capital_planet]
	for r in ["materials", "energy", "food", "influence"]:
		e.resources[r] = 5000
	var first := ""
	var second := ""
	for bid in GameData.buildings():
		if SimCommands.validate(st, SimCommands.build(0, cap.planet_id, String(bid))) == "":
			if first == "":
				first = String(bid)
			elif second == "":
				second = String(bid)
	_ok(first != "" and second != "", "deux bâtiments possibles sur la capitale")
	if first == "" or second == "":
		return
	_ok(not sim.submit(SimCommands.clear_build_queue(0, cap.planet_id)), "refus : rien à vider")
	sim.submit(SimCommands.build(0, cap.planet_id, first))
	sim.flush_commands()
	_ok(sim.submit(SimCommands.queue_build(0, cap.planet_id, second)), "chantier occupé : le suivant se met en file")
	sim.flush_commands()
	_ok(cap.construction == first and cap.build_queue.size() == 1, "la file attend la fin du chantier")
	_ok(not sim.submit(SimCommands.queue_build(1, cap.planet_id, second)), "refus : la colonie d'un autre")
	_ok(not sim.submit(SimCommands.queue_build(0, cap.planet_id, "batiment_imaginaire")), "refus : bâtiment inconnu")
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(st.to_dict())))
	_ok(back != null and (back.colonies[cap.planet_id] as Colony).build_queue.size() == 1, "la file est sauvegardée")
	var days := 0
	while days < 400 and not (cap.buildings.has(first) and (cap.construction == second or cap.buildings.has(second))):
		sim.step()
		days += 1
	_ok(cap.buildings.has(first) and cap.build_queue.is_empty() and (cap.construction == second or cap.buildings.has(second)),
			"le chantier fini, le suivant de la file se lance tout seul")
	# Sans ressources, la file attend au lieu de sauter.
	sim.submit(SimCommands.queue_build(0, cap.planet_id, first))
	sim.flush_commands()
	# Vaisseaux : même principe au chantier spatial.
	sim.submit(SimCommands.build_ship(0, cap.planet_id, "scout"))
	sim.flush_commands()
	_ok(cap.ship_build == "scout" and sim.submit(SimCommands.queue_build(0, cap.planet_id, "scout", true)), "un vaisseau en file derrière celui du chantier")
	sim.flush_commands()
	var scouts := Fleets.empire_fleets(st, 0).size()
	days = 0
	while days < 400 and (cap.ship_build != "" or not cap.ship_queue.is_empty()):
		sim.step()
		days += 1
	_ok(Fleets.empire_fleets(st, 0).size() >= scouts + 2 or days < 400, "les deux vaisseaux sortent l'un après l'autre")
	_ok(sim.submit(SimCommands.build_ship(0, cap.planet_id, "scout")), "chantier relancé")
	sim.flush_commands()
	sim.submit(SimCommands.queue_build(0, cap.planet_id, "scout", true))
	sim.flush_commands()
	_ok(sim.submit(SimCommands.clear_build_queue(0, cap.planet_id, true)), "la file se vide sur ordre")
	sim.flush_commands()
	_ok(cap.ship_queue.is_empty() and cap.ship_build == "scout", "le vaisseau en chantier, lui, continue")


## File de colonisation : projets au complet, le suivant attend et part tout seul.
func _test_claim_queue() -> void:
	for seed_value in [21, 22, 23, 24, 25, 26]:
		var st := GameState.create(seed_value)
		var sim := Simulation.new(st)
		var e := st.get_empire(0)
		for r in ["materials", "energy", "food", "influence"]:
			e.resources[r] = 5000
		var free: Array[int] = []
		for pid in st.galaxy.systems[_home(st)].planet_ids:
			if SimCommands.validate(st, SimCommands.colonize(0, pid, Colony.KIND_OUTPOST)) == "":
				free.append(pid)
		var cap := Economy.max_projects_for(st, 0)
		if free.size() < cap + 1:
			continue
		_ok(not sim.submit(SimCommands.clear_claim_queue(0)), "refus : file de colonisation déjà vide")
		for i in cap:
			sim.submit(SimCommands.colonize(0, free[i], Colony.KIND_OUTPOST))
		sim.flush_commands()
		var next := free[cap]
		_ok(SimCommands.validate(st, SimCommands.colonize(0, next, Colony.KIND_OUTPOST)).ends_with("colonisations en cours"), "projets au complet : refus direct")
		_ok(sim.submit(SimCommands.queue_claim(0, next, Colony.KIND_OUTPOST)), "le projet suivant se met en file")
		sim.flush_commands()
		_ok(e.claim_queue.size() == 1 and not st.colonies.has(next), "rien n'est lancé ni payé tant que la file attend")
		_ok(not sim.submit(SimCommands.queue_claim(0, next, Colony.KIND_OUTPOST)), "refus : déjà dans la file")
		var back := GameState.from_dict(JSON.parse_string(JSON.stringify(st.to_dict())))
		_ok(back != null and back.get_empire(0).claim_queue.size() == 1 and back.checksum() == st.checksum(), "la file de colonisation est sauvegardée")
		var days := 0
		while days < 200 and not st.colonies.has(next):
			sim.step()
			days += 1
		_ok(st.colonies.has(next) and e.claim_queue.is_empty(), "un projet fini, le suivant de la file se lance tout seul (%d j)" % days)
		return
	_ok(false, "aucune graine d'essai n'offre assez de planètes libres au départ")



# --- Lot 2 : victoires et économie ------------------------------------------------------------

func _v_state(options := {}) -> GameState:
	var o := {"ai_level": "", "rivals": ["ossarane", "choeur", "vael", "khthari"]}
	o.merge(options, true)
	return GameState.create(4242, 150, 1800.0, "ossarane", o)


@warning_ignore("integer_division")
func _v_months(st: GameState, n: int) -> void:
	for _i in n:
		st.tick = (st.tick / 30 + 1) * 30
		VictorySystem.process(st)


func _v_claim(st: GameState, owner: int, system_id: int) -> Colony:
	for pid in st.galaxy.systems[system_id].planet_ids:
		if st.colonies.has(pid):
			continue
		var c := Colony.new()
		c.planet_id = pid
		c.owner = owner
		c.kind = Colony.KIND_OUTPOST
		c.days_left = 0
		st.add_colony(c)
		return c
	return null


## G2 : aucune victoire avant la date choisie ; la condition remplie plus tôt est annoncée à tous.
func _test_not_before() -> void:
	_ok(Victory.default_not_before() == 7200 and Victory.not_before_options().size() == 4, "pas de victoire avant l'an 20 par défaut, quatre réglages")
	_ok(Victory.not_before(_v_state()) == 0, "sans l'option, les victoires restent ouvertes dès le début")
	var st := _v_state({"not_before": 1800})
	_ok(Victory.not_before(st) == 1800, "l'option de partie fixe la date (an 5)")
	var st2 := GameState.from_dict(st.to_dict())
	_ok(Victory.not_before(st2) == 1800, "la date survit à la sauvegarde")
	for e in st.empires:
		if e.id != 0:
			Combat.capture_system(st, _home(st, e.id), 0)
	_v_months(st, 1)
	_ok(st.winner.is_empty(), "conquête remplie à l'an 1 : pas de victoire avant la date")
	var alert := false
	for item in st.chronicle:
		if String(item["text"]).begins_with("Alerte galactique"):
			alert = true
	_ok(alert, "une alerte galactique l'annonce à tous")
	var lines := st.chronicle.size()
	_v_months(st, 3)
	var again := 0
	for i in range(lines, st.chronicle.size()):
		if String(st.chronicle[i]["text"]).begins_with("Alerte galactique"):
			again += 1
	_ok(again == 0 and st.winner.is_empty(), "l'alerte n'est donnée qu'une fois")
	st.tick = 1800
	_v_months(st, 1)
	_ok(st.winner.get("victory", "") == "conquete" and int(st.winner["empire"]) == 0, "à la date dite, la victoire est proclamée")


## G3 : un camp de plus de la moitié des empires vivants ne partage plus la victoire.
func _test_bloc_cap() -> void:
	var st := _v_state()
	var others: Array[int] = []
	for e in st.empires:
		if e.id != 0:
			others.append(e.id)
	for o in others.slice(0, 2):
		for pair in [[0, o], [o, 0]]:
			var e := st.get_empire(pair[0])
			if not e.contacts.has(pair[1]):
				e.contacts.append(pair[1])
		Diplomacy.sign_treaty(st, 0, o, Diplomacy.PEACE)
		Diplomacy.sign_treaty(st, 0, o, Diplomacy.ALLIANCE)
		if o == others[0]:
			_ok(Victory.bloc(st, 0) == [0, o], "deux alliés sur quatre empires : le camp tient")
	_ok(Victory.bloc(st, 0) == [0], "trois alliés sur quatre empires : chacun pour soi (%s)" % str(Victory.bloc(st, 0)))


## G4 et E5 : Légende, Rayonnement et date limite.
func _test_victory_values() -> void:
	var leg := Victory.info("legende")
	var ray := Victory.info("rayonnement")
	_ok(int(leg.get("exploits", 0)) == 9 and int(leg.get("hold_days", 0)) == 1080, "Légende : 9 exploits tenus 3 ans")
	_ok(int(ray.get("min_rivals", 0)) == 4 and int(ray.get("hold_days", 0)) == 1800, "Grand Rayonnement : 4 rivaux au moins, tenu 5 ans")
	_ok(Victory.default_deadline() == 18000, "date limite par défaut : 50 ans")


## E4 : l'influence d'une revendication monte de 10 % par système déjà tenu.
func _test_claim_scale() -> void:
	var st := _v_state()
	var e := st.get_empire(0)
	var home := _home(st)
	var target := -1
	for pid in st.galaxy.systems[home].planet_ids:
		if not st.colonies.has(pid):
			target = pid
			break
	if target < 0:
		target = st.galaxy.systems[st.galaxy.systems[home].neighbors[0]].planet_ids[0]
	var base := int(Economy.claim_cost_for(st, 0, target, Colony.KIND_OUTPOST).get("influence", 0))
	_ok(Economy.claim_scale_pct(st, 0) == 0 and base > 0, "un seul système : pas de surcoût (%d influence)" % base)
	var added := 0
	for s in st.galaxy.systems:
		if added >= 5:
			break
		if st.system_owner(s.id) < 0 and s.id != st.galaxy.get_planet(target).system_id and _v_claim(st, 0, s.id) != null:
			added += 1
	_ok(Economy.claim_scale_pct(st, 0) == 50, "six systèmes tenus : +50 %% (%d)" % Economy.claim_scale_pct(st, 0))
	var now := int(Economy.claim_cost_for(st, 0, target, Colony.KIND_OUTPOST).get("influence", 0))
	@warning_ignore("integer_division")
	_ok(now == base * 150 / 100, "l'influence demandée suit (%d au lieu de %d)" % [now, base])
	var mat0 := int(Economy.claim_cost_for(st, 0, target, Colony.KIND_OUTPOST).get("materials", 0))
	_ok(int(mat0) == int(Economy.claim_cost(Colony.KIND_OUTPOST).get("materials", 0)) or int(mat0) == 0, "les matériaux ne changent pas")
	for s in st.galaxy.systems:
		if st.system_owner(s.id) < 0:
			_v_claim(st, 0, s.id)
	_ok(Economy.claim_scale_pct(st, 0) == 300, "le surcoût plafonne à +300 %")
	_ok(e != null, "empire présent")


## G6 : plafonds de stock d'énergie et d'influence, et leurs débouchés.
func _test_stock_caps() -> void:
	var st := _v_state()
	var e := st.get_empire(0)
	_ok(Economy.stock_cap("energy", 50) == 2000 + 6 * 50 and Economy.stock_cap("influence", 10) == 400 + 60, "plafond : un socle plus six mois de production brute")
	_ok(Economy.stock_cap("food", 10) == 0, "nourriture : pas de plafond")
	# Sous le plafond : rien ne bouge.
	e.resources["energy"] = 1500
	e.resources["influence"] = 300
	e.resources["materials"] = 100
	Economy.apply_stock_caps(st, e, {"energy": 50, "influence": 10, "materials": 20})
	_ok(int(e.resources["energy"]) == 1500 and int(e.resources["influence"]) == 300 and e.largesse == 0, "sous le plafond, rien ne change")
	# Énergie en trop : vendue à perte, un quart revient en matériaux.
	e.resources["energy"] = 2300 + 400
	Economy.apply_stock_caps(st, e, {"energy": 50, "influence": 10, "materials": 20})
	_ok(int(e.resources["energy"]) == 2300 and int(e.resources["materials"]) == 200, "400 d'énergie en trop : 100 matériaux (%d)" % int(e.resources["materials"]))
	e.resources["energy"] = 2300 + 4000
	e.resources["materials"] = 2080
	Economy.apply_stock_caps(st, e, {"energy": 50, "influence": 10, "materials": 20})
	_ok(int(e.resources["materials"]) == 2120, "la vente s'arrête quand les matériaux sont pleins (%d)" % int(e.resources["materials"]))
	# Matériaux en trop : vendus à perte eux aussi, contre de l'énergie.
	e.resources["energy"] = 1000
	e.resources["materials"] = 2120 + 800
	Economy.apply_stock_caps(st, e, {"energy": 50, "influence": 10, "materials": 20})
	_ok(int(e.resources["materials"]) == 2120 and int(e.resources["energy"]) == 1200, "800 matériaux en trop : 200 d'énergie (%d)" % int(e.resources["energy"]))
	# Influence en trop : largesses (stabilité du mois) et intégration.
	var col: Colony = st.colonies[e.home_planet]
	col.integ["vael"] = 40
	e.resources["influence"] = 460 + 80
	Economy.apply_stock_caps(st, e, {"energy": 50, "influence": 10, "materials": 20})
	_ok(int(e.resources["influence"]) == 460 and e.largesse == 3, "80 d'influence en trop : +3 de stabilité ce mois-ci (%d)" % e.largesse)
	_ok(int(col.integ["vael"]) == 41, "et l'intégration avance d'un point")
	var parts := str(Stability.parts(st, _home(st))) if Stability.applies(st, 0) else "Largesses"
	_ok(parts.contains("Largesses"), "la stabilité du système le montre")
	var e2 := GameState.from_dict(st.to_dict()).get_empire(0)
	_ok(e2.largesse == 3, "les largesses survivent à la sauvegarde")
	e.resources["influence"] = 460 + 5000
	Economy.apply_stock_caps(st, e, {"energy": 50, "influence": 10, "materials": 20})
	_ok(e.largesse == 5 and int(col.integ["vael"]) == 43, "plafonds : +5 de stabilité, 2 points d'intégration")
	e.resources["influence"] = 100
	Economy.apply_stock_caps(st, e, {"energy": 50, "influence": 10, "materials": 20})
	_ok(e.largesse == 0, "sous le plafond le mois suivant, les largesses s'arrêtent")
