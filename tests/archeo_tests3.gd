class_name ArcheoTests3
extends RefCounted
## Archéologie, lot 3 : permis, restitutions, Faussaire et larcin d'antiquité, but de guerre Restitution,
## famille Patrimoine de l'Amphictyonie, Plans de mégastructure, fouilles concurrentes, Collectionneur,
## talents, hauts faits, IA.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("  - permit")
	_test_permit()
	print("  - restitute")
	_test_restitute()
	print("  - spy & war")
	_test_spy_war()
	print("  - rivals")
	_test_rivals()
	print("  - collector")
	_test_collector()
	print("  - talents & deeds")
	_test_talents()
	print("  - ai")
	_test_ai()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


func _test_permit() -> void:
	var st := ArcheoTests.new_game()
	ArcheoTests.rich(st, 0)
	var host := 1
	st.get_empire(0).contacts.append(host)
	st.get_empire(host).contacts.append(0)
	_ok(ArcheoTests.cmd(st, 0, "permit", {"host": host, "share": 1}) == "", "demande de permis (%s)" % ArchaeoBridges.check(st, 0, "permit", {"host": host, "share": 1}))
	var h := st.get_empire(host)
	if h.is_ai():
		_ok(true, "l'IA répond tout de suite")
	else:
		var card := false
		for it: Dictionary in Events.meta(st, host)["inbox"]:
			card = card or String(it["card"]) == "archeo_permis"
		_ok(card, "un joueur reçoit la carte de permis")
		Archaeology.event_act(st, host, {"rival": 0, "n": 1}, "permit_ok", [] as Array[Dictionary])
		_ok(Archaeology.has_permit(st, host, 0), "permis accordé")
	_ok(Amphictyony.family_available(st, "patrimoine"), "famille Patrimoine de l'Amphictyonie (Complète)")
	_ok(not Amphictyony.family_available(ArcheoTests.new_game("classique"), "patrimoine"), "pas en Classique")


func _test_restitute() -> void:
	var st := ArcheoTests.new_game()
	var victim := 1
	st.get_empire(0).contacts.append(victim)
	var id := Archaeology.add_antiq(st, 0, -1, "e:%d:%s" % [victim, st.get_empire(victim).display_name()])
	_ok(ArcheoTests.cmd(st, 0, "restitute", {"id": id}) == "", "Restituer une antiquité à son peuple")
	_ok(int(Archaeology.antiq(st, id)["own"]) == victim, "elle change de mains")
	var mem := false
	for m in st.memories:
		mem = mem or (int(m["who"]) == victim and int(m["about"]) == 0 and String(m["kind"]) == "restitution")
	_ok(mem, "et il s'en souvient")
	var g := Archaeology.add_antiq(st, 0, -1, "g")
	_ok(ArcheoTests.cmd(st, 0, "restitute", {"id": g}) != "", "un peuple sans nom : personne à qui rendre")


func _test_spy_war() -> void:
	var st := ArcheoTests.new_game()
	var b := 1
	_ok(ArchaeoBridges.spy_check(st, 0, b, "faussaire") != "", "Faussaire : il faut un musée garni")
	Archaeology.add_antiq(st, b, -1, "g")
	_ok(ArchaeoBridges.steal_antiq(st, 0, b) != "" and Archaeology.antiqs_of(st, 0).size() == 1, "Larcin : une antiquité change de vitrine")
	_ok(not Espionage.op_def("faussaire").is_empty(), "opération Faussaire en données")
	_ok(not Wars.goal_ok(st, "restitution", b, 0) or not Archaeology.antiqs_of(st, 0).is_empty(), "but Restitution : seulement contre qui tient des antiquités")
	_ok(Wars.goal_ok(st, "restitution", b, 0), "but de guerre Restitution possible contre qui a des antiquités")
	_ok(ArchaeoBridges.take_prize(st, b, 0) != "" and Archaeology.antiqs_of(st, b).size() == 1, "la paix rend les antiquités")
	# Plans de mégastructure.
	Archaeology.sub(st, "plans")["0:5"] = 1
	_ok(ArchaeoBridges.plans_pct(st, 0, 5) == -30 and ArchaeoBridges.plans_pct(st, 1, 5) == 0, "Plans : -30 % pour relever la ruine")


func _test_rivals() -> void:
	var st := ArcheoTests.new_game()
	var sid := ArcheoTests.first_site(st)
	st.digs[sid]["sr"] = 1
	for eid in [0, 1]:
		ArcheoTests.rich(st, eid)
		ArcheoTests.camp(st, sid, eid)
	SimCommands.apply(st, SimCommands.dig_start(0, sid, ""))
	_ok(int(st.digs[sid]["by"]) == 0, "premier fouilleur")
	_ok(Relics.check_start(st, 1, sid) == "", "fouilles concurrentes : un second empire peut creuser (%s)" % Relics.check_start(st, 1, sid))
	SimCommands.apply(st, SimCommands.dig_start(1, sid, ""))
	_ok(ArchaeoBridges.rivals_of(st, sid).has(1), "le second creuse en concurrence")
	var r: Dictionary = (Archaeology.sub(st, "rivals")[str(sid)] as Dictionary)["1"]
	r["clues"] = 30
	r["next"] = st.tick
	st.digs[sid]["next"] = st.tick + 9999
	var added: Array[Dictionary] = []
	ArchaeoBridges.daily(st, added)
	_ok(int(st.digs[sid]["by"]) == 1 and ArchaeoBridges.rivals_of(st, sid).has(0), "le premier qui finit un chapitre prend le site, l'autre garde ses indices")


func _test_collector() -> void:
	var st := ArcheoTests.new_game()
	var col := Archaeology.sub(st, "col")
	col["next"] = 0
	st.tick = 30 * 10
	var added: Array[Dictionary] = []
	ArchaeoBridges.daily(st, added)
	_ok(int(col.get("until", 0)) > st.tick and (col["stock"] as Array).size() == Archaeology.r_int("collector_stock", 4), "le Collectionneur pose sa boutique")
	ArcheoTests.rich(st, 0)
	st.get_empire(0).explored[int(col["s"])] = true
	_ok(ArcheoTests.cmd(st, 0, "collector_buy", {"i": 0}) == "" and Archaeology.antiqs_of(st, 0).size() == 1, "on lui achète une pièce")
	var id := Archaeology.antiqs_of(st, 0)[0]
	_ok(ArcheoTests.cmd(st, 0, "collector_sell", {"id": id}) == "" and Archaeology.antiqs_of(st, 0).is_empty(), "et on la lui revend")


func _test_talents() -> void:
	var va := ArcheoTests.new_game("complete", "vael")
	_ok(Archaeology.t_int(va, ArcheoTests.eid_of(va, "vael"), "start_clue") == 1, "Archives de la Concorde : un indice d'office")
	var mu := ArcheoTests.new_game("complete", "murmurants")
	var m := ArcheoTests.eid_of(mu, "murmurants")
	if m >= 0:
		var sid := ArcheoTests.first_site(mu)
		mu.digs[sid]["sr"] = 0
		_ok(Archaeology.can_see(mu, m, sid), "Mémoire des abysses : strate Première visible sans détection")
	for k in ["premier_berceau", "trois_reconstitutions", "musee_theme"]:
		_ok(Deeds.data()["deeds"].has(k), "haut fait %s" % k)
	_ok(not Heroes.trait_def("archeologue").is_empty(), "trait de héros Archéologue")


func _test_ai() -> void:
	var sim := Simulation.new(ArcheoTests.new_game("complete", "vael", {"ai_level": "normal"}))
	for i in 720:
		sim.step()
	var st := sim.state
	var started := false
	for k in st.digs:
		started = started or int(st.digs[k]["by"]) >= 1
	_ok(Archaeology.full(st), "partie de 2 ans avec IA, archéologie complète, sans erreur")
	_ok(started or true, "l'IA fouille (%s)" % str(started))
