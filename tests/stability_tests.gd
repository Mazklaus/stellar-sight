extends RefCounted
## Tests de la stabilité (Stability, StabilitySystem) : glissement vers la cible, sources (capitale,
## distance, surextension, garnison, conquête), paliers et production, décrets, offrande, révolte,
## rebelles et sécession vers les Sans-Bannière, réintégration, talents des couches d'espèce, colonies
## sauvages de la ruche, stabilité d'empire, sauvegarde 22 et déterminisme. Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Stabilité…")
	_test_drift()
	_test_sources()
	_test_tiers()
	_test_decrees()
	_test_offering()
	_test_secession()
	_test_reintegrate()
	_test_talents()
	_test_wild()
	_test_empire_pct()
	_test_save()
	_test_determinism()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


func _new(seed_value := 7, faction := "vael") -> GameState:
	return GameState.create(seed_value, 150, 1800.0, faction, {"ai_level": ""})


func _emp(st: GameState, faction_id: String) -> int:
	for e in st.empires:
		if e.faction_id == faction_id:
			return e.id
	return -1


func _home(st: GameState, empire_id := 0) -> int:
	return FactionTraits.capital_system(st, empire_id)


## Fonde directement une colonie établie dans un système libre à au moins `min_jumps` sauts de la
## capitale de l'empire. Renvoie l'identifiant du système (-1 si aucun).
func _plant(st: GameState, empire_id: int, min_jumps: int, pop := 3, max_jumps := 99) -> int:
	var jumps := FactionTraits.jumps_from(st.galaxy, _home(st, empire_id))
	for s in st.galaxy.systems:
		var j := int(jumps.get(s.id, 999))
		if j < min_jumps or j > max_jumps or st.system_owner(s.id) >= 0 or s.planet_ids.is_empty():
			continue
		var c := Colony.new()
		c.planet_id = s.planet_ids[0]
		c.owner = empire_id
		c.kind = Colony.KIND_COLONY
		c.population = pop
		st.add_colony(c)
		return s.id
	return -1


func _month(sim: Simulation, n := 1) -> void:
	sim.advance(30 * n)


func _part(st: GameState, sid: int, prefix: String) -> int:
	for p in Stability.parts(st, sid):
		if String(p[0]).begins_with(prefix):
			return int(p[1])
	return 0


func _test_drift() -> void:
	var sim := Simulation.new(_new())
	var st := sim.state
	_ok(st.stability.is_empty(), "nouvelle partie : aucune stabilité calculée")
	_month(sim)
	var home := _home(st)
	_ok(st.stability.has(home), "après un mois, le système capital a une stabilité")
	_ok(Stability.target(st, home) >= 60, "capitale : cible au-dessus de la base (+10)")
	_ok(Stability.value(st, home) == 52, "la stabilité glisse de 2 points par mois vers sa cible (%d)" % Stability.value(st, home))
	_month(sim, 6)
	_ok(Stability.value(st, home) == 50 + 2 * 7 or Stability.value(st, home) == Stability.target(st, home), "glissement régulier jusqu'à la cible")
	var kh := _emp(st, "khthari")
	_ok(not Stability.applies(st, kh) and not st.stability.has(_home(st, kh)), "esprit de ruche : pas de stabilité")


func _test_sources() -> void:
	var st := _new(11)
	var far := _plant(st, 0, 6)
	_ok(far >= 0 and _part(st, far, "Distance") < 0, "colonie lointaine : malus de distance à la capitale")
	_ok(_part(st, far, "Distance") >= -10, "malus de distance plafonné à -10")
	_ok(_part(st, _home(st), "Capitale") == 10, "capitale : +10")
	# Surextension : au-delà de 10 systèmes peuplés.
	var n := 0
	while Stability.colony_systems(st, 0) < 14 and n < 40:
		_plant(st, 0, 1)
		n += 1
	st.tick += 1
	_ok(_part(st, _home(st), "Surextension") == -2, "deux systèmes de trop : -2 partout (%d)" % _part(st, _home(st), "Surextension"))
	st.get_empire(0).techs["administration"] = 0
	st.tick += 1
	_ok(_part(st, _home(st), "Surextension") == 0, "Administration coloniale : seuil relevé de 2")
	# Garnison : flotte armée à l'arrêt.
	st.spawn_ship(0, "corvette", far)
	_ok(_part(st, far, "Flotte armée") == 5, "flotte armée en orbite : +5")
	# Conquête qui s'efface.
	Stability.on_capture(st, far)
	_ok(_part(st, far, "Monde conquis") == -15, "monde tout juste conquis : -15")
	st.tick += 900
	_ok(_part(st, far, "Monde conquis") > -15 and _part(st, far, "Monde conquis") < 0, "le malus de conquête s'efface avec le temps")
	# Forum : +10.
	st.colonies[st.galaxy.systems[far].planet_ids[0]].buildings.append("forum")
	_ok(_part(st, far, "Bâtiments") == 10, "Forum impérial : +10")


func _test_tiers() -> void:
	var st := _new(13)
	var home := _home(st)
	var c: Colony = st.colonies[st.get_empire(0).capital_planet]
	var base := int(Economy.colony_yields(st, c)["gross"]["materials"])
	st.stability[home] = {"v": 5}
	_ok(Stability.tier_id(st, home) == "revolte" and Stability.prod_pct(st, home) == -50, "stabilité 5 : Révolte, -50 %")
	_ok(not Stability.growth_ok(st, home) and Stability.frozen(st, home), "Révolte : pas de croissance, chantiers gelés")
	var low := int(Economy.colony_yields(st, c)["gross"]["materials"])
	_ok(low == base / 2, "Révolte : la production de matériaux est divisée par deux (%d -> %d)" % [base, low])
	st.stability[home] = {"v": 20}
	_ok(Stability.tier_id(st, home) == "agitation" and not Stability.growth_ok(st, home) and not Stability.frozen(st, home), "stabilité 20 : Agitation")
	st.stability[home] = {"v": 90}
	Stability.refresh_empire(st, 0)
	_ok(Stability.tier_id(st, home) == "ferveur" and Stability.extra_influence(st, 0) == 1, "stabilité 90 : Ferveur, +1 influence")
	_ok(int(Economy.colony_yields(st, c)["gross"]["materials"]) == base * 120 / 100, "Ferveur : +20 % de production")


func _test_decrees() -> void:
	var sim := Simulation.new(_new(17))
	var st := sim.state
	var home := _home(st)
	var e := st.get_empire(0)
	e.resources["influence"] = 500
	e.resources["energy"] = 500
	_ok(Stability.check_decree(st, 0, home, "loi_martiale") != "", "loi martiale : il faut une flotte armée")
	_ok(sim.submit(SimCommands.decree(0, home, "fetes")), "Fêtes publiques acceptées")
	sim.flush_commands()
	_ok(Stability.active_decree(st, home) == "fetes" and _part(st, home, "Fêtes") == 15, "décret en vigueur : +15")
	_ok(int(e.resources["influence"]) == 485 and int(e.resources["energy"]) == 440, "les Fêtes se paient en influence et en énergie")
	_ok(Stability.check_decree(st, 0, home, "concessions") != "", "un seul décret à la fois")
	_month(sim, 7)
	_ok(Stability.active_decree(st, home) == "", "le décret expire au bout de 6 mois")
	var bri := Simulation.new(_new(17, "brisecomete")).state
	_ok(int(Stability.decree_cost(bri, 0, "fetes")["energy"]) == 30, "Syndicat : Fêtes à moitié prix")
	var other := _emp(st, "brisecomete")
	_ok(Stability.check_decree(st, 0, _home(st, other), "fetes") != "", "pas de décret chez les autres")


func _test_offering() -> void:
	var st := _new(19, "choeur")
	var home := _home(st)
	st.stability[home] = {"v": 60}
	var e := st.get_empire(0)
	var f0 := e.fervor
	_ok(Stability.check_offering(st, 0, home) == "", "théocratie : offrande possible")
	Stability.offering(st, 0, home)
	_ok(Stability.value(st, home) == 40 and e.fervor == mini(f0 + 15, int(e.faction()["fervor"]["max"])), "offrande : -20 stabilité, +15 ferveur")
	_ok(Stability.check_offering(st, 0, home) != "", "une offrande par système tous les 6 mois")
	var v := _new(19, "vael")
	_ok(Stability.check_offering(v, 0, _home(v)) != "", "pas d'offrande hors théocratie")


func _test_secession() -> void:
	var sim := Simulation.new(_new(23))
	var st := sim.state
	var far := _plant(st, 0, 3, 3, 4)
	_ok(far >= 0, "colonie de test fondée")
	var rebels := 0
	var log := []
	sim.chronicle_added.connect(func(en: Dictionary) -> void: log.append(String(en["text"])))
	for m in 12:
		st.stability[far] = {"v": 0, "revolt": int(st.stability.get(far, {}).get("revolt", 0))}
		_month(sim)
		if m == 3:
			for fid in st.sorted_fleet_ids():
				if GameState.is_npc(st.fleets[fid].owner):
					rebels += 1
	_ok(rebels >= 1, "4 mois de révolte : des rebelles se lèvent (%d flotte)" % rebels)
	_ok(log.any(func(t: String) -> bool: return t.contains("sécession à voix haute")), "avertissement de sécession dans la chronique")
	_ok(st.system_owner(far) == GameState.NPC_ID, "un an de révolte : le système fait sécession")
	_ok(log.any(func(t: String) -> bool: return t.begins_with("Sécession !")), "la chronique annonce la sécession")
	_ok(Combat.at_war(st, 0, GameState.NPC_ID) and Combat.at_war(st, GameState.NPC_ID, 3), "les Sans-Bannière sont hostiles à tous")
	_ok(st.get_empire(GameState.NPC_ID).short_name() == "Sans-Bannière" and not st.empires.has(st.get_empire(GameState.NPC_ID)), "Sans-Bannière : hors de la liste des empires")
	# La capitale ne fait jamais sécession.
	var home := _home(st)
	for m in 13:
		st.stability[home] = {"v": 0, "revolt": int(st.stability.get(home, {}).get("revolt", 0))}
		_month(sim)
	_ok(st.system_owner(home) == 0, "la capitale ne fait jamais sécession")
	# Invasion d'un monde libre possible (guerre permanente).
	_ok(Combat.check_invade(st, 0, st.spawn_ship(0, "croiseur", far).id) != "aucun système ennemi à envahir ici", "un monde libre peut être envahi")


func _test_reintegrate() -> void:
	var sim := Simulation.new(_new(29))
	var st := sim.state
	var far := _plant(st, 0, 1, 2, 1)
	var log: Array[Dictionary] = []
	StabilitySystem.secede(st, far, 0, log)
	_ok(st.system_owner(far) == GameState.NPC_ID, "sécession forcée")
	st.stability[_home(st)] = {"v": 80}
	st.get_empire(0).resources["influence"] = 200
	_ok(Stability.check_reintegrate(st, 0, far).contains("rebelles"), "rebelles armés sur place : pas de réintégration")
	for fid in st.sorted_fleet_ids():
		if GameState.is_npc(st.fleets[fid].owner):
			st.fleets.erase(fid)
	st.stability[_home(st)] = {"v": 40}
	_ok(Stability.check_reintegrate(st, 0, far).contains("au moins 60"), "stabilité d'empire trop basse")
	st.stability[_home(st)] = {"v": 80}
	st.get_empire(0).resources["influence"] = 0
	_ok(Stability.check_reintegrate(st, 0, far).contains("influence"), "réintégration payée en influence")
	st.get_empire(0).resources["influence"] = 200
	_ok(Stability.check_reintegrate(st, 1, far) != "", "seul un voisin peut réintégrer")
	_ok(sim.submit(SimCommands.reintegrate(0, far)), "réintégration acceptée")
	sim.flush_commands()
	_ok(st.system_owner(far) == 0 and Stability.value(st, far) == 40, "le monde libre rentre dans l'empire, à 40 de stabilité")


func _test_talents() -> void:
	var os := _new(31, "ossarane")
	var far := _plant(os, 0, 6)
	os.get_empire(0).dissent = true
	_ok(_part(os, far, "Dissidence") == -20, "féodalité : la dissidence coûte 20 de stabilité aux fiefs lointains")
	var c: Colony = os.colonies[os.galaxy.systems[far].planet_ids[0]]
	var y := Economy.colony_yields(os, c)
	os.get_empire(0).dissent = false
	var y2 := Economy.colony_yields(os, c)
	_ok(int(y["gross"]["influence"]) == int(y2["gross"]["influence"]), "féodalité : la dissidence ne divise plus la production")
	var ch := _new(31, "choeur")
	ch.get_empire(0).fervor = 90
	ch.tick = 1
	_ok(_part(ch, _home(ch), "Exaltation") == 10, "théocratie : exaltation = +10")
	ch.get_empire(0).fervor = 0
	ch.tick = 2
	_ok(_part(ch, _home(ch), "Le dieu se tait") == -15, "théocratie : ferveur à 0 = -15")
	var ty := _new(31, "teyl")
	var tfar := _plant(ty, 0, 6)
	_ok(_part(ty, tfar, "Distance") == 0, "conscience distribuée : pas de malus de distance")
	_ok(Stability.talent(ty, 0).get("no_overpop", false), "synthétiques : pas de malus de surpopulation")
	var hon := _new(31, "ossarane")
	Diplomacy.remember(hon, 1, 0, "broke_treaty")
	hon.tick = 1
	_ok(_part(hon, _home(hon), "Parjure") == -10, "honneur : un parjure coûte 10 de stabilité")
	var kh := _new(31, "khthari")
	kh.get_empire(0).starving = true
	_ok(not Stability.applies(kh, 0), "ruche : pas de stabilité")
	var fe := _new(31, "ferrocornes")
	fe.tick = 400
	_ok(_part(fe, _home(fe), "Les clans s'ennuient") == -5, "horde : un an sans pillage = -5")
	Stability.on_loot(fe, 0)
	fe.tick = 401
	_ok(_part(fe, _home(fe), "Butin récent") == 10, "horde : pillage récent = +10")
	_ok(Stability.talent_labels(fe, 0).size() >= 1, "talents de stabilité affichables")


func _test_wild() -> void:
	var sim := Simulation.new(_new(37, "khthari"))
	var st := sim.state
	var far := _plant(st, 0, 7)
	var near := _plant(st, 0, 2, 3, 3)
	_ok(far >= 0 and near >= 0, "colonies de ruche fondées")
	var fc: Colony = st.colonies[st.galaxy.systems[far].planet_ids[0]]
	for m in 12:
		fc.population = 2  # (qu'elle ne devienne pas elle-même un monde-ruche)
		_month(sim)
	_ok(st.system_owner(far) == GameState.NPC_ID, "ruche : une colonie à plus de 6 sauts redevient sauvage en un an")
	_ok(st.system_owner(near) == 0, "ruche : une colonie proche reste au nid")


func _test_empire_pct() -> void:
	var st := _new(41)
	for sid in Stability.systems_of(st, 0):
		st.stability[sid] = {"v": 100}
	Stability.refresh_empire(st, 0)
	_ok(Stability.empire_value(st, 0) == 100 and Stability.empire_pct(st, 0) == 15, "stabilité d'empire 100 : +15 % de Savoir et d'influence")
	var inf := Economy.production_pct(st, 0, "influence")
	for sid in Stability.systems_of(st, 0):
		st.stability[sid] = {"v": 0}
	Stability.refresh_empire(st, 0)
	_ok(Stability.empire_pct(st, 0) == -15 and Economy.production_pct(st, 0, "influence") < inf, "stabilité d'empire 0 : -15 %")


func _test_save() -> void:
	var sim := Simulation.new(_new(43))
	var st := sim.state
	var far := _plant(st, 0, 1, 2, 1)
	_month(sim, 2)
	var log: Array[Dictionary] = []
	StabilitySystem.secede(st, far, 0, log)
	st.get_empire(0).resources["influence"] = 100
	Stability.decree(st, 0, _home(st), "concessions")
	Stability.on_loot(st, 2)
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(st.to_snapshot())))
	_ok(back != null, "sauvegarde 22 relue")
	if back == null:
		return
	_ok(back.checksum() == st.checksum(), "même empreinte après sauvegarde (stabilité, mondes libres, rebelles)")
	_ok(back.system_owner(far) == GameState.NPC_ID and Stability.active_decree(back, _home(back)) == "concessions", "mondes libres et décrets relus")
	var old := st.to_snapshot()
	old["version"] = 21
	old.erase("stability")
	old.erase("stab_meta")
	_ok(GameState.from_dict(JSON.parse_string(JSON.stringify(old))) != null, "une sauvegarde 21 se relit (sans stabilité)")


func _test_determinism() -> void:
	var a := Simulation.new(GameState.create(47))
	var b := Simulation.new(GameState.create(47))
	a.advance(400)
	b.advance(400)
	_ok(a.state.checksum() == b.state.checksum() and not a.state.stability.is_empty(), "même graine, même stabilité après 400 jours")
