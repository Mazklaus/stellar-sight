class_name BetaLot3Tests
extends RefCounted
## Lot 3 du bêta-test (faire une armée) : flotte créée vide puis commandée, répartition entre les
## chantiers, renforts d'une flotte existante, vaisseau neuf qui rejoint la flotte à quai (3.1) ;
## rapport de force (3.2). L'interface (onglet Flottes, fiche de flotte) se vérifie dans smoke_test.
##   tools/run_tests.sh beta_lot3_tests

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Bêta-test, lot 3…")
	_test_empty_fleet_ordered()
	_test_two_yards()
	_test_reinforce_existing()
	_test_auto_join()
	_test_orders_and_save()
	_test_odds()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


static func _rich(st: GameState, eid := 0) -> void:
	var e := st.get_empire(eid)
	for r in ["materials", "energy", "influence", "food", "science"]:
		e.resources[r] = 100000


static func _home_sys(st: GameState, eid := 0) -> int:
	return st.galaxy.get_planet(st.get_empire(eid).capital_planet).system_id


static func _cmd(st: GameState, act: String, a := -1, b := -1, s := "") -> String:
	var cmd := SimCommands.muster_act(0, act, a, b, s)
	var why := SimCommands.validate(st, cmd)
	if why == "":
		SimCommands.apply(st, cmd)
	return why


static func _fleets_of(st: GameState, eid := 0) -> Array[Fleet]:
	var out: Array[Fleet] = []
	for fid in st.sorted_fleet_ids():
		if (st.fleets[fid] as Fleet).owner == eid:
			out.append(st.fleets[fid])
	return out


static func _named(st: GameState, n: String) -> Fleet:
	for f: Fleet in st.fleets.values():
		if f.fleet_name == n:
			return f
	return null


## 3.1 : une flotte vide se crée, se commande ; les vaisseaux sortent un à un et s'y fondent.
func _test_empty_fleet_ordered() -> void:
	var st := GameState.create(51)
	_rich(st)
	var home := _home_sys(st)
	_ok(_cmd(st, "new", home, -1, "") != "", "refus : une flotte sans nom")
	_ok(_cmd(st, "new", 9999, -1, "Garde noire") != "", "refus : rassemblement hors de vos systèmes")
	_ok(_cmd(st, "new", home, -1, "Garde noire") == "", "nouvelle flotte, encore vide")
	var list := Musters.of_empire(st, 0)
	_ok(list.size() == 1 and int(list[0]["rec"]["f"]) == -1, "la formation existe sans vaisseau")
	var id := int(list[0]["id"])
	_ok(_cmd(st, "add", id, -1, "titan") != "", "refus : vaisseau unique ou hors de portée (%s)" % Musters.order_block(st, 0, "titan"))
	_ok(_cmd(st, "add", id, -1, "fregate") == "" and _cmd(st, "add", id, -1, "fregate") == "", "deux frégates commandées")
	_ok(_cmd(st, "sub", id, -1, "escorteur") != "", "refus : retirer une classe absente")
	var before := _fleets_of(st).size()
	var sim := Simulation.new(st)
	for _i in 200:
		sim.step()
		_rich(st)
		if Musters.get_rec(st, id).is_empty():
			break
	var g := _named(st, "Garde noire")
	_ok(g != null and g.count("fregate") == 2, "les deux frégates forment « Garde noire » (%s)" % (Fleets.composition(g) if g else "absente"))
	_ok(_fleets_of(st).size() == before + 1, "une seule flotte de plus, pas deux")
	_ok(Musters.get_rec(st, id).is_empty(), "commande terminée : la formation s'efface")


## Deux chantiers libres : la commande se répartit, chaque vaisseau rejoint la flotte.
func _test_two_yards() -> void:
	var st := GameState.create(52)
	_rich(st)
	var home := _home_sys(st)
	var cap: Colony = st.colonies[st.get_empire(0).capital_planet]
	var other := -1
	for pid in st.galaxy.systems[home].planet_ids:
		if not st.colonies.has(pid):
			other = pid
			break
	_ok(other >= 0, "une planète libre dans le système d'origine")
	var c := Colony.new()
	c.planet_id = other
	c.owner = 0
	c.population = 6
	st.colonies[other] = c
	st.rebuild_ownership()
	_ok(Fleets.check_build_ship(st, 0, other, "fregate") == "", "le second chantier peut lancer une frégate (%s)" % Fleets.check_build_ship(st, 0, other, "fregate"))
	_cmd(st, "new", home, -1, "Doublé")
	var id := int(Musters.of_empire(st, 0)[0]["id"])
	_cmd(st, "add", id, -1, "fregate")
	_cmd(st, "add", id, -1, "fregate")
	Musters.daily(st)
	_ok(cap.ship_build == "fregate" and c.ship_build == "fregate", "les deux chantiers travaillent en même temps")
	_ok((Musters.get_rec(st, id)["q"] as Array).is_empty() and Musters.building(Musters.get_rec(st, id)).size() == 2, "plus rien en attente, deux en chantier")
	_ok(Musters.wait_reason(st, id) == "", "rien n'attend")
	_cmd(st, "add", id, -1, "fregate")
	_ok(Musters.wait_reason(st, id) == "tous vos chantiers sont occupés", "la troisième attend un chantier (%s)" % Musters.wait_reason(st, id))
	var sim := Simulation.new(st)
	for _i in 300:
		sim.step()
		_rich(st)
		if Musters.get_rec(st, id).is_empty():
			break
	var g := _named(st, "Doublé")
	_ok(g != null and g.count("fregate") == 3, "trois frégates dans la flotte (%s)" % (Fleets.composition(g) if g else "absente"))


## Renforts : une flotte qui existe déjà reçoit ce qu'on lui commande, même loin du chantier.
func _test_reinforce_existing() -> void:
	var st := GameState.create(53)
	_rich(st)
	var home := _home_sys(st)
	var near: int = st.galaxy.systems[home].neighbors[0]
	var f := st.spawn_ship(0, "fregate", near)
	f.fleet_name = "Avant-garde"
	for s in st.galaxy.systems:
		st.get_empire(0).explored[s.id] = true
		st.get_empire(0).surveyed[s.id] = true
	_ok(_cmd(st, "new", -1, f.id) == "", "renforts commandés pour une flotte existante")
	_ok(_cmd(st, "new", -1, f.id) != "", "refus : une seconde commande pour la même flotte")
	var id := Musters.for_fleet(st, f.id)
	_ok(id >= 0 and _cmd(st, "rename", id, -1, "Autre") != "", "refus : une flotte qui existe se renomme comme les autres")
	_cmd(st, "add", id, -1, "fregate")
	var sim := Simulation.new(st)
	var joined := false
	for _i in 300:
		sim.step()
		_rich(st)
		if f.count("fregate") == 2:
			joined = true
			break
	_ok(joined and st.fleets.has(f.id) and f.system_id == near, "le renfort a rejoint la flotte dans son système")
	_ok(_named(st, "Avant-garde") == f and _fleets_of(st).filter(func(x: Fleet) -> bool: return x.count("fregate") > 0).size() == 1, "aucune frégate isolée")


## Hors commande : la frégate neuve rejoint la flotte armée à quai ; réglage coupé, elle reste seule.
func _test_auto_join() -> void:
	var st := GameState.create(54)
	_rich(st)
	var home := _home_sys(st)
	var cap := st.get_empire(0).capital_planet
	var guard := st.spawn_ship(0, "fregate", home)
	SimCommands.apply(st, SimCommands.build_ship(0, cap, "fregate"))
	var sim := Simulation.new(st)
	for _i in 200:
		sim.step()
		if (st.colonies[cap] as Colony).ship_build == "":
			break
	_ok(guard.count("fregate") == 2, "la frégate neuve a rejoint la flotte à quai")
	_ok(_cmd(st, "auto", 0) == "" and not Musters.auto_join(st, 0), "réglage coupé")
	SimCommands.apply(st, SimCommands.build_ship(0, cap, "fregate"))
	for _i in 200:
		sim.step()
		if (st.colonies[cap] as Colony).ship_build == "":
			break
	_ok(guard.count("fregate") == 2, "réglage coupé : la frégate neuve reste une flotte à part")
	# L'IA n'est pas concernée.
	var ai_home := _home_sys(st, 1)
	var ai_f := st.spawn_ship(1, "fregate", ai_home)
	var nf := st.spawn_ship(1, "fregate", ai_home)
	Musters.on_new_ship(st, nf)
	Musters.daily(st)
	_ok(st.fleets.has(nf.id) and ai_f.count("fregate") == 1, "l'IA range ses vaisseaux elle-même")


## Un ordre à la main reprend le vaisseau ; la sauvegarde garde tout.
func _test_orders_and_save() -> void:
	var st := GameState.create(55)
	var home := _home_sys(st)
	_cmd(st, "new", home, -1, "Réserve")
	var id := int(Musters.of_empire(st, 0)[0]["id"])
	_cmd(st, "add", id, -1, "fregate")
	var f := st.spawn_ship(0, "fregate", home)
	var g := st.spawn_ship(0, "fregate", st.galaxy.systems[home].neighbors[0])
	(st.musters["j"] as Dictionary)[str(f.id)] = g.id
	var d := st.to_dict()
	var back := GameState.from_dict(d)
	_ok(Musters.joining(back, f.id) == g.id and not Musters.get_rec(back, id).is_empty(), "sauvegarde : formation et renfort en route relus")
	_ok(StateDiff.first_difference(d, back.to_dict()) == "", "sauvegarde identique après relecture")
	SimCommands.apply(st, SimCommands.set_fleet_order(0, f.id, Fleet.ORDER_EXPLORE))
	_ok(Musters.joining(st, f.id) == -1, "un ordre à la main : le vaisseau ne rejoint plus")
	_ok(_cmd(st, "drop", id) == "" and Musters.of_empire(st, 0).is_empty(), "dissoudre la formation")
	var fresh := GameState.create(56)
	_ok(not fresh.to_dict().has("musters"), "rien d'écrit tant qu'aucune formation n'existe")


## 3.2 : rapport de force entre une flotte et ce qu'on voit d'un système.
func _test_odds() -> void:
	var st := GameState.create(57)
	var home := _home_sys(st)
	var mine := st.spawn_ship(0, "fregate", home)
	var there: int = st.galaxy.systems[home].neighbors[0]
	var o := ForceOdds.at(st, 0, mine, there)
	_ok(o.is_empty(), "rien en face : pas de rapport de force")
	for pair in [[0, 1], [1, 0]]:
		if not st.get_empire(pair[0]).contacts.has(pair[1]):
			st.get_empire(pair[0]).contacts.append(pair[1])
	Combat.start_war(st, 0, 1)
	var foe := st.spawn_ship(1, "fregate", there)
	for _i in 3:
		foe.add_ship("fregate", -1, -1)
	o = ForceOdds.at(st, 0, mine, there, true)
	_ok(not o.is_empty() and int(o["foe"]) > int(o["mine"]), "quatre frégates contre une : l'ennemi est plus fort (%s)" % str(o))
	_ok(String(o["verdict"]) == "défaite probable", "verdict : défaite probable (%s)" % str(o.get("verdict", "")))
	_ok(ForceOdds.line(o).contains("contre"), "la ligne compare les deux forces (%s)" % ForceOdds.line(o))
	for _i in 10:
		mine.add_ship("fregate", -1, -1)
	o = ForceOdds.at(st, 0, mine, there, true)
	_ok(String(o["verdict"]) == "victoire probable", "onze contre quatre : victoire probable (%s)" % str(o.get("verdict", "")))
	_ok(ForceOdds.verdict(100, 100) == "issue incertaine", "à égalité : issue incertaine")
