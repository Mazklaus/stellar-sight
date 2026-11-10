extends RefCounted
## Tests du lot 2 de la recherche : marques d'armes et de défenses (I à V, gardées par chaque vaisseau
## jusqu'à sa remise à niveau au chantier), doctrines exclusives, épaves, eurêkas, sauvegarde.
## Appelés par smoke_test.gd.

var _check: Callable
var _combat := preload("res://tests/combat_tests.gd").new()


func run(check: Callable) -> void:
	_check = check
	print("Arsenal : marques, doctrines, épaves, eurêkas…")
	_test_data()
	_test_marks()
	_test_ship_marks_and_refit()
	_test_doctrines()
	_test_doctrine_combat()
	_test_wrecks()
	_test_eurekas()
	_test_ai_refit()
	_test_save()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


func _state(faction := "ossarane", seed_value := 4242) -> GameState:
	return GameState.create(seed_value, 150, 1800.0, faction, {"ai_level": ""})


func _apply(st: GameState, cmd: Dictionary) -> String:
	var why := SimCommands.validate(st, cmd)
	if why == "":
		SimCommands.apply(st, cmd)
	return why


func _home(st: GameState, eid: int) -> int:
	return st.galaxy.get_planet(st.get_empire(eid).capital_planet).system_id


func _test_data() -> void:
	var techs: Dictionary = Research.data()["technologies"]
	# Chaque famille monte de la marque I à la V dans l'arbre commun.
	var reach := {}
	for tid in techs:
		if techs[tid].has("requires"):
			continue
		for fam in techs[tid].get("effects", {}).get("marks", {}):
			reach[fam] = int(reach.get(fam, 1)) + int(techs[tid]["effects"]["marks"][fam])
	var short := PackedStringArray()
	for fam in Research.mark_families():
		if int(reach.get(fam, 1)) != 5:
			short.append("%s %d" % [fam, int(reach.get(fam, 1))])
	_ok(short.is_empty(), "les 9 familles montent jusqu'à la marque V, pas plus (%s)" % ", ".join(short))
	# Doctrines : paires réciproques de la même ère, en Armement.
	var bad := PackedStringArray()
	var n := 0
	for tid in techs:
		var t: Dictionary = techs[tid]
		if not t.get("doctrine", false):
			continue
		n += 1
		var o: Dictionary = techs.get(String(t.get("exclusive", "")), {})
		if o.is_empty() or String(o.get("exclusive", "")) != tid or int(o["era"]) != int(t["era"]) or t["domain"] != "armement":
			bad.append(tid)
	_ok(n == 6 and bad.is_empty(), "3 paires de doctrines exclusives et réciproques (%d, %s)" % [n, ", ".join(bad)])
	var eu := 0
	var no_text := PackedStringArray()
	for tid in techs:
		if techs[tid].has("eureka"):
			eu += 1
			if Research.eureka_text(tid) == "":
				no_text.append(tid)
	_ok(eu >= 30 and no_text.is_empty(), "une trentaine d'eurêkas, tous lisibles (%d, %s)" % [eu, ", ".join(no_text)])


func _test_marks() -> void:
	var st := _state()
	var m := Research.marks(st, 0)
	_ok(m.size() == 9 and int(m["kinetic"]) == 1 and int(m["shield"]) == 1, "marque I partout au départ")
	Research.grant(st, 0, ["canons_masse", "accelerateurs"])
	_ok(int(Research.marks(st, 0)["kinetic"]) == 3, "deux technologies de canons : marque III")
	_ok(Combat.weapon_bonus(st, 0, "kinetic") == 40, "marque III : +40 % de dégâts")
	Research.grant(st, 0, ["blindage_composite"])
	_ok(int(Combat.defense_bonus(st, 0)["armor"]) == 20, "blindage marque II : +20 % de protection")
	_ok(Research.next_mark_tech(st, 0, "kinetic") == "canons_rail", "la marque suivante des canons : Canons à rail")
	# Les armes de peuple gardent leur bonus à part (griffes de l'Essaim).
	var sk := _state("khthari")
	var kid := -1
	for e in sk.empires:
		if e.faction_id == "khthari":
			kid = e.id
	Research.grant(sk, kid, ["griffes"])
	_ok(Combat.weapon_bonus(sk, kid, "kinetic") == 25 and int(Research.marks(sk, kid)["kinetic"]) == 1,
			"les Griffes de l'Essaim : +25 % sans changer de marque")


func _test_ship_marks_and_refit() -> void:
	var st := _state()
	st.fleets.clear()
	var home := _home(st, 0)
	var f := st.spawn_ship(0, "corvette", home)
	var old: Dictionary = Combat.ship_marks(st, f, 0).duplicate()
	Research.grant(st, 0, ["canons_masse"])
	_ok(int(Combat.ship_marks(st, f, 0)["kinetic"]) == int(old["kinetic"]), "un vaisseau garde les marques de sa construction")
	_ok(Fleets.outdated_count(st, f) == 1, "il est en retard d'une marque")
	var g := st.spawn_ship(0, "corvette", home)
	_ok(int(Combat.ship_marks(st, g, 0)["kinetic"]) == 2, "un vaisseau neuf sort avec la dernière marque")
	_ok(Fleets.outdated_count(st, g) == 0, "le neuf est à jour")
	# Fusion et séparation gardent les marques de chaque vaisseau.
	_ok(_apply(st, SimCommands.merge_fleets(0, g.id, f.id)) == "", "fusion de deux flottes")
	var outdated := Fleets.outdated_count(st, f)
	_ok(outdated == 1, "après fusion, un seul vaisseau en retard (%d)" % outdated)
	# Remise à niveau : 10 % du prix, 5 jours à quai dans un chantier ami.
	var e := st.get_empire(0)
	var cost := Fleets.refit_cost(st, f)
	var price := Fleets.ship_cost(st, 0, "corvette")
	_ok(int(cost.get("materials", 0)) == maxi(1, int(price.get("materials", 0)) / 10), "remise à niveau : 10 pour cent du prix (%s)" % GameData.format_amounts(cost))
	var mat := int(e.resources["materials"])
	_ok(_apply(st, SimCommands.refit(0, f.id)) == "", "ordre de remise à niveau au chantier")
	_ok(int(e.resources["materials"]) == mat - int(cost.get("materials", 0)), "le prix est payé")
	_ok(SimCommands.validate(st, SimCommands.refit(0, f.id)) != "", "pas deux remises à niveau à la fois")
	_ok(SimCommands.validate(st, SimCommands.split_fleet(0, f.id, "corvette")) != "", "pas de séparation pendant la remise à niveau")
	var sim := Simulation.new(st)
	for i in Fleets.refit_days():
		sim.step()
	_ok(f.refit_left == 0 and Fleets.outdated_count(st, f) == 0, "après 5 jours, toute la flotte a les dernières marques")
	# Loin de chez soi, pas de chantier.
	var far := -1
	for s in st.galaxy.systems:
		if st.system_owner(s.id) == -1:
			far = s.id
			break
	var h := st.spawn_ship(0, "corvette", far)
	Research.grant(st, 0, ["accelerateurs"])
	_ok(Fleets.outdated_count(st, h) == 1 and SimCommands.validate(st, SimCommands.refit(0, h.id)).contains("colonie"),
			"pas de remise à niveau hors d'un système à soi")
	# Partir interrompt la remise à niveau.
	_ok(_apply(st, SimCommands.refit(0, f.id)) == "", "nouvelle remise à niveau après une nouvelle marque")
	var dest := st.galaxy.systems[home].neighbors[0]
	Fleets.plan_route(st, f, dest)
	_ok(_apply(st, SimCommands.move_fleet(0, f.id, dest)) == "", "la flotte repart")
	sim.step()
	_ok(f.refit_left == 0 and Fleets.outdated_count(st, f) > 0, "partir interrompt la remise à niveau")


func _test_doctrines() -> void:
	var st := _state()
	var e := st.get_empire(0)
	Research.grant(st, 0, ["canons_masse", "lentilles", "blindage_composite"])
	_ok(Research.check_queue(st, 0, "rideau_acier") == "", "la doctrine du rideau d'acier se recherche dès l'ère II")
	_ok(_apply(st, SimCommands.research(0, "rideau_acier")) == "", "elle entre dans la file")
	var why := Research.check_queue(st, 0, "frappe_profondeur")
	_ok(why.contains("fermée"), "l'autre branche est fermée dès que la première est en file (%s)" % why)
	Research.complete(st, 0, "rideau_acier")
	_ok(Research.check_queue(st, 0, "frappe_profondeur").contains("définitif"), "choix définitif une fois découverte")
	# Seules les épaves ouvrent l'autre branche.
	var c := Research.cost(st, 0, "frappe_profondeur")
	_ok(not Research.add_progress(st, 0, "frappe_profondeur", c / 2), "la moitié par les épaves : pas encore")
	_ok(Research.add_progress(st, 0, "frappe_profondeur", c) and e.techs.has("frappe_profondeur"),
			"payée entièrement par les épaves, l'autre doctrine est découverte")


## Bataille d'un jour entre deux flottes identiques ; renvoie les dégâts infligés par chaque camp.
func _duel(setup: Callable, ship := "corvette", seed_value := 9) -> Array:
	var st := _state("ossarane", seed_value)
	st.fleets.clear()
	var sid := _combat._empty_system(st)
	_combat._meet_and_war(st, 0, 1)
	var a := _combat._spawn(st, 0, ship, sid, 4)
	var b := _combat._spawn(st, 1, ship, sid, 4)
	setup.call(st, a, b)
	var sim := Simulation.new(st)
	sim.step()
	var b0: Dictionary = st.battles[sid]
	var dealt := [0, 0]
	for s: Dictionary in b0["sides"]:
		dealt[int(s["empire"])] = int(s["dealt"])
	return dealt


func _test_doctrine_combat() -> void:
	# (frégates : leurs rayons portent loin, les écarts de dégâts se voient dès le premier jour)
	var fbase := _duel(func(_st: GameState, _a: Fleet, _b: Fleet) -> void: pass, "fregate")
	var eclair := _duel(func(st: GameState, _a: Fleet, _b: Fleet) -> void: Research.grant(st, 0, ["guerre_eclair"]), "fregate")
	_ok(eclair[0] > fbase[0], "guerre éclair : plus de dégâts le premier jour (%d contre %d)" % [eclair[0], fbase[0]])
	var lointain := _duel(func(st: GameState, _a: Fleet, _b: Fleet) -> void: Research.grant(st, 0, ["feu_lointain"]), "fregate")
	_ok(lointain[0] > fbase[0], "feu lointain : plus de dégâts à longue portée (%d contre %d)" % [lointain[0], fbase[0]])
	var abordage := _duel(func(st: GameState, _a: Fleet, _b: Fleet) -> void: Research.grant(st, 0, ["abordage"]), "fregate")
	_ok(abordage[0] == fbase[0], "abordage : rien de plus à longue portée")
	var base := _duel(func(_st: GameState, _a: Fleet, _b: Fleet) -> void: pass)
	var marked := _duel(func(st: GameState, _a: Fleet, _b: Fleet) -> void: Research.grant(st, 0, ["canons_masse", "accelerateurs"]))
	_ok(marked[0] > base[0], "des canons marque III frappent plus fort (%d contre %d)" % [marked[0], base[0]])
	var stale := _duel(func(st: GameState, a: Fleet, _b: Fleet) -> void:
		for i in a.gen.size():
			a.gen[i] = Research.mark_gen(st, 0)
		Research.grant(st, 0, ["canons_masse", "accelerateurs"]))
	_ok(stale[0] == base[0], "sans remise à niveau, la flotte tire encore en marque I (%d contre %d)" % [stale[0], base[0]])
	# Rideau d'acier : les corvettes (écran) encaissent moins.
	var rideau := _duel(func(st: GameState, _a: Fleet, _b: Fleet) -> void: Research.grant(st, 1, ["rideau_acier"]))
	_ok(rideau[0] < base[0],
			"rideau d'acier : l'écran encaisse moins (%d contre %d)" % [rideau[0], base[0]])
	# Guerre d'usure : réparations doublées.
	var st := _state()
	st.fleets.clear()
	var f := st.spawn_ship(0, "fregate", _home(st, 0))
	f.hp[0] = 10
	CombatSystem._repairs(st, {})
	var normal := f.hp[0] - 10
	f.hp[0] = 10
	Research.grant(st, 0, ["guerre_usure"])
	CombatSystem._repairs(st, {})
	_ok(f.hp[0] - 10 >= normal * 2, "guerre d'usure : réparations deux fois plus rapides (%d contre %d)" % [f.hp[0] - 10, normal])


func _test_wrecks() -> void:
	var st := _state("choeur")
	var me := st.get_empire(0)
	var foe := 1
	Research.grant(st, foe, ["canons_masse", "accelerateurs", "rideau_acier"])
	var out := Research.study_wrecks(st, 0, foe)
	var ids: Array = []
	for r in out:
		ids.append(r[0])
	_ok(ids.has("canons_masse") and ids.has("rideau_acier"), "les épaves font avancer la marque suivante et les doctrines du vaincu (%s)" % str(ids))
	var c := Research.cost(st, 0, "canons_masse")
	_ok(int(me.research_shelf.get("canons_masse", 0)) == c * 20 / 100, "Reliques saintes : épaves doublées (%d sur %d)" % [int(me.research_shelf.get("canons_masse", 0)), c])
	# Une vraie bataille gagnée : les épaves sont étudiées et comptées.
	var sw := _state("ossarane", 5)
	sw.fleets.clear()
	var sid := _combat._empty_system(sw)
	_combat._meet_and_war(sw, 0, 1)
	Research.grant(sw, 1, ["lentilles"])
	_combat._spawn(sw, 0, "croiseur", sid, 3)
	_combat._spawn(sw, 1, "corvette", sid, 1)
	var sim := Simulation.new(sw)
	for i in 6:
		sim.step()
	var rep: Dictionary = sw.battle_reports.back() if not sw.battle_reports.is_empty() else {}
	_ok(int(rep.get("winner", -1)) == 0, "trois croiseurs gagnent")
	_ok(int(sw.get_empire(0).stats.get("battles_won", 0)) == 1 and int(sw.get_empire(0).stats.get("kills", 0)) >= 1
			and int(sw.get_empire(1).stats.get("ships_lost", 0)) >= 1, "victoires, destructions et pertes sont comptées")
	_ok(int(sw.get_empire(0).research_shelf.get("lentilles", 0)) > 0 and rep.get("wrecks", []).size() > 0,
			"les épaves des rayons ennemis font avancer les Lentilles de focalisation")


func _test_eurekas() -> void:
	var st := _state()
	var e := st.get_empire(0)
	e.contacts.append(1)
	var got := Research.check_eurekas(st, 0)
	_ok(got.has("rhetorique") and e.eurekas.has("rhetorique"), "rencontrer un empire : eurêka de la Rhétorique impériale")
	var c := Research.cost(st, 0, "rhetorique")
	_ok(Research.progress_of(st, 0, "rhetorique") == c * 40 / 100, "l'eurêka paie 40 pour cent (%d sur %d)" % [Research.progress_of(st, 0, "rhetorique"), c])
	_ok(not Research.check_eurekas(st, 0).has("rhetorique"), "une seule fois")
	_ok(Research.eureka_status(st, 0, "chancelleries") == [1, 3], "avancement lisible : 1 empire sur 3")
	# En file, l'eurêka va droit à la recherche en cours.
	Research.grant(st, 0, ["rhetorique"])
	_apply(st, SimCommands.research(0, "medecine"))
	for pid in st.colonies:
		if st.colonies[pid].owner == 0:
			st.colonies[pid].population = 30
	var before := e.research_progress
	Research.check_eurekas(st, 0)
	_ok(e.research_progress > before, "la recherche en cours avance d'un coup (Médecine coloniale, 20 de population)")
	# Le bilan mensuel déclenche les eurêkas.
	var sim := Simulation.new(_state())
	var e2 := sim.state.get_empire(0)
	e2.contacts.append(1)
	sim.advance(95)
	_ok(e2.eurekas.has("rhetorique"), "les bilans vérifient les eurêkas chaque trimestre")


func _test_ai_refit() -> void:
	var st := GameState.create(8, 150, 1800.0, "", {"spectator": true, "ai_level": "veteran"})
	st.fleets.clear()
	var e := st.get_empire(0)
	var f := st.spawn_ship(0, "fregate", _home(st, 0))
	f.add_ship("fregate", -1, f.gen[0])
	Research.grant(st, 0, ["canons_masse"])
	e.resources["materials"] = 2000
	_ok(Fleets.outdated_count(st, f) == 2, "flotte IA en retard d'une marque")
	AiPlayer.think(st, e)
	_ok(f.refit_left > 0 or not st.fleets.has(f.id) or f.is_moving(), "en paix, l'IA remet à niveau ses flottes à quai")


func _test_save() -> void:
	var st := _state()
	st.fleets.clear()
	var f := st.spawn_ship(0, "corvette", _home(st, 0))
	Research.grant(st, 0, ["canons_masse"])
	st.spawn_ship(0, "corvette", _home(st, 0))
	f.refit_left = 3
	var e := st.get_empire(0)
	e.stats["kills"] = 4
	e.eurekas["rhetorique"] = true
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(st.to_dict())))
	var bf: Fleet = back.fleets[f.id]
	_ok(bf.refit_left == 3 and bf.gen == f.gen and Fleets.outdated_count(back, bf) == 1, "marques des vaisseaux et remise à niveau sauvegardées")
	var be := back.get_empire(0)
	_ok(be.marks_log.size() == e.marks_log.size() and int(be.stats.get("kills", 0)) == 4 and be.eurekas.has("rhetorique"),
			"journal des marques, faits d'armes et eurêkas sauvegardés")
	_ok(back.checksum() == st.checksum(), "même empreinte après rechargement")
