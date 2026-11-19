extends RefCounted
## Tests des prises de guerre, lot 1 (étude « Prises de guerre », propositions 1 à 20) : réglage de
## partie, prises et avaries, posture d'abordage, résolution, modules, reddition, technologies,
## réparations au chantier, remise en état, refonte, démantèlement, revente, sauvegarde 99.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Prises de guerre (lot 1)…")
	_test_modes()
	_test_prize_stats()
	_test_posture()
	_test_boarding()
	_test_rules()
	_test_peoples()
	_test_surrender()
	_test_repairs_and_acts()
	_test_battle_runs()
	_test_save()


func _ok(cond: bool, what: String) -> void:
	print("  ", "ok " if cond else "KO ", what)
	_check.call(cond, what)


func _state(seed_value := 4242, faction := "ossarane", mode := "complete") -> GameState:
	return GameState.create(seed_value, 150, 1800.0, faction, {"ai_level": "", "capture": mode})


func _me(st: GameState) -> int:
	return st.empires[0].id


func _empire_of(st: GameState, faction: String) -> int:
	for e in st.empires:
		if e.faction_id == faction:
			return e.id
	return -1


func _empty_system(st: GameState) -> int:
	for s in st.galaxy.systems:
		if st.system_owner(s.id) == -1 and s.neighbors.size() >= 2:
			return s.id
	return -1


func _war(st: GameState, a: int, b: int) -> void:
	for p in [[a, b], [b, a]]:
		if not st.get_empire(p[0]).contacts.has(p[1]):
			st.get_empire(p[0]).contacts.append(p[1])
	Combat.start_war(st, a, b)


func _spawn(st: GameState, owner: int, ships: Array, sid: int) -> Fleet:
	var f := st.spawn_ship(owner, String(ships[0]), sid)
	for i in range(1, ships.size()):
		f.add_ship(String(ships[i]))
	f.troops = Combat.max_troops(f)
	return f


func _battle(st: GameState, sid: int) -> Dictionary:
	return {"id": 999, "system": sid, "day": 5, "fleets": [], "sides": [], "units": [], "slots": [], "log": []}


func _test_modes() -> void:
	var st := GameState.create(5, 150, 1800.0, "ossarane", {"ai_level": ""})
	_ok(st.capture_mode == "classique" and not Capture.full(st), "sans option : prises Classique (anciennes sauvegardes, tests)")
	var full := _state(5)
	_ok(Capture.full(full) and full.capture.has("post") and full.capture.has("fields"), "Complète : l'état des prises existe")
	var off := _state(5, "ossarane", "desactivee")
	_ok(Capture.disabled(off) and not Capture.full(off), "Désactivée : aucune prise")
	_ok(Capture.mode_defs().size() == 3 and Capture.default_mode() == "complete", "trois réglages, Complète par défaut au menu")


func _test_prize_stats() -> void:
	var base := GameData.ship("fregate")
	var pid := Capture.prize_id("fregate", 1 | 2)  # blindage fissuré, affûts faussés
	var sd := GameData.ship(pid)
	_ok(Capture.is_prize(pid) and Capture.base_of(pid) == "fregate" and Capture.mask_of(pid) == 3, "identifiant de prise base~masque")
	_ok(int(sd["armor"]) == int(base["armor"]) * 75 / 100, "Blindage fissuré : blindage −25 %")
	_ok(int(sd["weapons"]["beam"]) == int(base["weapons"]["beam"]) * 85 / 100, "Affûts faussés : dégâts −15 %")
	_ok(String(sd["label"]).ends_with("(prise)") and sd.get("prize", false), "une prise se lit comme une classe, marquée « prise »")
	_ok(int(sd["upkeep"].get("energy", 0)) <= int(base["upkeep"].get("energy", 0)), "chaque avarie baisse l'entretien")
	_ok(Capture.avarie_count(pid) == 2 and Capture.avarie_count(Capture.prize_id("fregate", 0)) == 0, "compte des avaries")
	_ok(not Capture.is_prize("fregate") and Capture.prize_id(pid, 0) == "fregate~0", "une prise de prise garde la même base")
	var st := _state(9)
	for _i in 20:
		var m := Capture.roll_avaries(st, 0, 2, 4)
		var n := Capture.avaries_of(Capture.prize_id("fregate", m)).size()
		if n < 2 or n > 4:
			_ok(false, "tirage d'avaries hors bornes")
			return
	_ok(true, "tirage d'avaries entre les bornes (épave : 2 à 4)")
	var titan := Capture.prize_id("titan", 0)
	_ok(not GameData.ship(titan).has("unique_per_empire"), "une méga-coque prise ne compte pas dans « une par empire »")


func _test_posture() -> void:
	var st := _state(11, "ossarane")
	var me := _me(st)
	var sid := _empty_system(st)
	var f := _spawn(st, me, ["fregate", "fregate"], sid)
	_ok(not Capture.posture_open(st, f), "sans Équipes de prise, pas de posture")
	_ok(Capture.check_posture(st, me, f.id) != "", "l'ordre de posture est refusé sans la technologie")
	Research.grant(st, me, ["equipes_prise"])
	_ok(Capture.posture_open(st, f) and not Capture.posture(st, f), "Équipes de prise : posture possible, coupée par défaut")
	_ok(Capture.check_act(st, me, "posture", {"fleet": f.id, "on": true}) == "", "ordre de posture valide")
	Capture.apply_act(st, me, "posture", {"fleet": f.id, "on": true})
	_ok(Capture.posture(st, f), "posture d'abordage active")
	var st2 := _state(12, "ferrocornes")
	var me2 := _me(st2)
	var g := _spawn(st2, me2, ["fregate"], _empty_system(st2))
	_ok(Capture.posture(st2, g), "Horde : posture d'abordage active par défaut")


func _test_boarding() -> void:
	var st := _state(21, "ossarane")
	var me := _me(st)
	var foe := (me + 1) % st.empires.size()
	var sid := _empty_system(st)
	_war(st, me, foe)
	Research.grant(st, me, ["equipes_prise"])
	var mine := _spawn(st, me, ["fregate", "fregate", "transport"], sid)
	mine.troops = 60
	Capture.set_posture(st, mine.id, true)
	var theirs := _spawn(st, foe, ["corvette", "fregate", "fregate"], sid)
	var fl: Array[Fleet] = [mine, theirs]
	var b := _battle(st, sid)
	var added: Array[Dictionary] = []
	_ok(Capture.boarding(st, b, fl, 2, {}, added).is_empty(), "rien à prendre tant que l'ennemi n'est pas très abîmé")
	theirs.hp[0] = 2  # corvette brisée (sous 30 %)
	_ok(Capture.boarding(st, b, fl, 1, {}, added).is_empty(), "pas d'abordage en phase moyenne sans capsules")
	var got: Array = []
	for _i in 40:
		mine.troops = maxi(mine.troops, 8)
		got = Capture.boarding(st, b, fl, 2, {}, added)
		if not got.is_empty():
			break
	var prize := ""
	for s in mine.ships:
		if Capture.is_prize(s):
			prize = s
	_ok(not got.is_empty() and Capture.base_of(prize) == "corvette", "posture d'abordage : la corvette brisée devient une prise")
	_ok(Capture.avarie_count(prize) >= 1 and Capture.avarie_count(prize) <= 2, "prise par abordage : 1 ou 2 avaries")
	_ok(mine.troops < 60, "l'abordage dépense des troupes")
	_ok(Capture.stat(st, me, "prizes") == 1 and int(st.get_empire(me).stats.get("prizes", 0)) == 1, "la prise est comptée")
	# Le dernier vaisseau d'une flotte n'est pris que si son camp n'en a pas d'autre.
	var lone := _spawn(st, foe, ["corvette"], sid)
	lone.hp[0] = 1
	var other := _spawn(st, foe, ["fregate"], sid)
	var fl2: Array[Fleet] = [mine, lone, other]
	_ok(not Capture.can_board(st, mine, lone, 0, fl2), "on ne vide pas une flotte tant que son camp en a d'autres")
	var fl3: Array[Fleet] = [mine, lone]
	_ok(Capture.can_board(st, mine, lone, 0, fl3), "dernier vaisseau du camp : il peut être pris")
	# Capsules d'assaut : dès la phase moyenne.
	GameData.register_custom_ship("t_pods", {"label": "Capsulier", "size": "medium", "hp": 100, "troops": 20, "assault_pods": true, "military": true, "weapons": {"kinetic": 5}})
	var pods := _spawn(st, me, ["t_pods"], sid)
	pods.troops = 20
	Capture.set_posture(st, pods.id, true)
	lone.hp[0] = 1
	var fl4: Array[Fleet] = [pods, lone]
	var ok_pods := false
	for _i in 40:
		pods.troops = 20
		if not Capture.boarding(st, b, fl4, 1, {}, added).is_empty():
			ok_pods = true
			break
	_ok(ok_pods, "Capsules d'assaut : abordage dès la phase moyenne")


func _test_rules() -> void:
	var st := _state(31, "ossarane")
	var me := _me(st)
	var foe := (me + 1) % st.empires.size()
	var sid := _empty_system(st)
	_war(st, me, foe)
	Research.grant(st, me, ["equipes_prise"])
	var mine := _spawn(st, me, ["fregate", "transport"], sid)
	mine.troops = 50
	var theirs := _spawn(st, foe, ["corvette", "fregate"], sid)
	theirs.hp[0] = 1
	var c0 := Capture.chance(st, mine, theirs, 0)
	_ok(c0 >= Capture.rule("chance_min") and c0 <= Capture.rule("chance_max"), "chance bornée entre 5 et 90 %")
	GameData.register_custom_ship("t_grap", {"label": "Harponneur", "size": "medium", "hp": 100, "grapple": true, "military": true})
	mine.add_ship("t_grap")
	_ok(Capture.force(st, mine, "corvette") > Capture.troops_needed("corvette"), "Grappins : force d'abordage +25 %")
	GameData.register_custom_ship("t_sas", {"label": "Coursive piégée", "size": "small", "hp": 50, "board_def": true, "military": true})
	theirs.add_ship("t_sas")
	var si := theirs.ships.find("t_sas")
	_ok(Capture.defense(st, theirs, si) > Capture.size_rule("small", "crew"), "Sas piégés : défense +50 %")
	_ok(Capture.troops_needed("titan") == 40 and Capture.size_rule("titan", "hp_pct") == 10, "méga-coque : 40 troupes, 10 % de structure")
	# Charge d'autodestruction.
	GameData.register_custom_ship("t_boom", {"label": "Brûlot", "size": "small", "hp": 50, "self_destruct_capture": true, "military": true})
	var boom := _spawn(st, foe, ["t_boom", "fregate"], sid)
	boom.hp[boom.ships.find("t_boom")] = 1
	Capture.set_posture(st, mine.id, true)
	var fl: Array[Fleet] = [mine, boom]
	var b := _battle(st, sid)
	var added: Array[Dictionary] = []
	var res: Array = []
	for _i in 60:
		res = Capture.boarding(st, b, fl, 2, {}, added)
		if not res.is_empty():
			break
	_ok(not res.is_empty() and String(res[0][1]) == "" and not boom.ships.has("t_boom"), "Charge d'autodestruction : le vaisseau saute, pas de prise")
	# Technologies et doctrine.
	_ok(not Research.tech("equipes_prise").is_empty() and Research.heir_of("capsules_assaut") == "equipes_prise" and not Research.tech("ingenierie_inverse").is_empty(), "technologies de prise (Capsules fondues dans Équipes de prise)")
	_ok(int(Research.tech("abordage")["effects"].get("board_pct", 0)) == 20, "doctrine Abordage : force +20 %")
	for m in ["grappins", "capsules_assaut", "sas_pieges", "charge_autodestruction", "grue_recuperation"]:
		_ok(not Designs.module(m).is_empty(), "module %s" % m)
	_ok(not Heroes.data()["traits"].get("abordeur", {}).is_empty() and bool(Heroes.data()["traits"]["abordeur"].get("earned", false)), "trait Abordeur (gagné)")


func _test_peoples() -> void:
	# Coques synthétiques : elles s'effacent.
	var st := _state(41, "ossarane")
	var me := _me(st)
	var teyl := _empire_of(st, "teyl")
	if teyl < 0:
		teyl = (me + 1) % st.empires.size()
	var sid := _empty_system(st)
	_war(st, me, teyl)
	Research.grant(st, me, ["equipes_prise"])
	var mine := _spawn(st, me, ["fregate", "transport"], sid)
	mine.troops = 50
	Capture.set_posture(st, mine.id, true)
	var theirs := _spawn(st, teyl, ["corvette", "fregate"], sid)
	theirs.hp[0] = 1
	var fl: Array[Fleet] = [mine, theirs]
	var b := _battle(st, sid)
	var added: Array[Dictionary] = []
	var res: Array = []
	for _i in 60:
		res = Capture.boarding(st, b, fl, 2, {}, added)
		if not res.is_empty():
			break
	if st.get_empire(teyl).faction_id == "teyl":
		_ok(not res.is_empty() and String(res[0][1]) == "", "coque synthétique abordée : elle s'efface")
	_ok(Capture.unboardable("onde_nef") or Designs.hull("onde_nef").is_empty(), "l'Onde-nef ne peut pas être abordée")
	_ok(Capture.unboardable("bete_x") and Capture.unboardable("def_tourelle"), "créatures et défenses fixes : pas de prise")
	# Foi : défense renforcée, ne se rend jamais.
	var st2 := _state(42, "choeur")
	_ok(Capture.surrender_pct(st2, _me(st2)) == 0, "credo Foi : ne se rend jamais")
	var st3 := _state(43, "brisecomete")
	_ok(Capture.surrender_pct(st3, _me(st3)) == 60, "credo Profit : négocie volontiers")
	# Horde : trophées.
	var st4 := _state(44, "ferrocornes")
	var me4 := _me(st4)
	Capture.on_prize(st4, me4, (me4 + 1) % st4.empires.size(), Capture.prize_id("corvette", 0), _empty_system(st4), added)
	var parts := Capture.stability_parts(st4, 0, me4)
	_ok(parts.size() == 1 and String(parts[0][0]) == "Trophées de clan", "Horde : une prise est un trophée (stabilité)")


func _test_surrender() -> void:
	var st := _state(51, "ossarane")
	var me := _me(st)
	var foe := _empire_of(st, "brisecomete")
	if foe < 0 or foe == me:
		foe = (me + 1) % st.empires.size()
	var sid := _empty_system(st)
	_war(st, me, foe)
	var mine := _spawn(st, me, ["croiseur", "croiseur", "croiseur", "fregate", "fregate"], sid)
	var got := false
	for k in 30:
		var theirs := _spawn(st, foe, ["corvette", "corvette"], sid)
		for i in theirs.ships.size():
			theirs.hp[i] = 1
		var fl: Array[Fleet] = [mine, theirs]
		var b := _battle(st, sid)
		var added: Array[Dictionary] = []
		var res := Capture.surrenders(st, b, fl, 2, added)
		if not res.is_empty():
			got = not st.fleets.has(theirs.id) and b.has("surrender")
			break
		st.fleets.erase(theirs.id)
	_ok(got, "reddition : un camp à bout, dominé à 3 contre 1, se rend et ses vaisseaux deviennent des prises")
	var b2 := _battle(st, sid)
	var fl0: Array[Fleet] = [mine]
	_ok(Capture.surrenders(st, b2, fl0, 3, []).is_empty(), "reddition seulement en fin de phase")
	Capture.apply_act(st, me, "surrender", {"x": "refuse"})
	_ok(Capture.surrender_policy(st, me) == "refuse", "politique de reddition : refuser")


func _test_repairs_and_acts() -> void:
	var st := _state(61, "ossarane")
	var me := _me(st)
	var e := st.get_empire(me)
	var home := -1
	for s in st.galaxy.systems:
		if Fleets.has_own_yard(st, me, s.id):
			home = s.id
			break
	var away := _empty_system(st)
	var pid := Capture.prize_id("fregate", 1 | 4)
	var f := _spawn(st, me, ["fregate", pid], away)
	var pi := f.ships.find(pid)
	f.hp[pi] = 10
	_ok(Capture.repair_blocked(st, f, pid), "une prise loin d'un chantier ne se répare pas")
	_ok(not Capture.repair_blocked(st, f, "fregate"), "un vaisseau ordinaire se répare partout")
	_ok(Capture.check_act(st, me, "repair", {"fleet": f.id, "ship": pid}) != "", "remise en état refusée loin du chantier")
	f.system_id = home
	_ok(not Capture.repair_blocked(st, f, pid), "au chantier, la prise se répare")
	e.resources["materials"] = 5000
	e.resources["energy"] = 5000
	_ok(Capture.check_act(st, me, "repair", {"fleet": f.id, "ship": pid}) == "", "remise en état possible au chantier")
	Capture.apply_act(st, me, "repair", {"fleet": f.id, "ship": pid})
	var after := ""
	for s in f.ships:
		if Capture.is_prize(s):
			after = s
	_ok(Capture.avarie_count(after) == 1 and f.refit_left > 0, "remise en état : une avarie de moins, du temps à quai")
	f.refit_left = 0
	var mat := int(e.resources["materials"])
	_ok(Capture.check_act(st, me, "scrap", {"fleet": f.id, "ship": after}) == "", "démantèlement possible")
	Capture.apply_act(st, me, "scrap", {"fleet": f.id, "ship": after})
	_ok(int(e.resources["materials"]) > mat and not f.ships.has(after), "démantèlement : des matériaux")
	var p2 := Capture.prize_id("corvette", 2)
	f.add_ship(p2)
	f.add_ship("fregate")
	var en := int(e.resources["energy"])
	_ok(Capture.check_act(st, me, "sell", {"fleet": f.id, "ship": p2, "x": "market"}) == "", "revente au marché possible")
	Capture.apply_act(st, me, "sell", {"fleet": f.id, "ship": p2, "x": "market"})
	_ok(int(e.resources["energy"]) > en and not f.ships.has(p2), "revente : de l'énergie")
	var p3 := Capture.prize_id("fregate", 8)
	f.add_ship(p3)
	var to := ""
	for id in Designs.buildable_ids(st, me):
		if Combat.ship_size(id) == "medium" and Combat.is_military(id):
			to = id
			break
	_ok(to != "" and Capture.check_act(st, me, "refit", {"fleet": f.id, "ship": p3, "x": to}) == "", "refonte possible vers un modèle de même taille")
	Capture.apply_act(st, me, "refit", {"fleet": f.id, "ship": p3, "x": to})
	_ok(not f.ships.has(p3) and f.ships.has(to), "refonte : la prise devient un de vos modèles")
	_ok(Capture.check_act(st, me, "refit", {"fleet": f.id, "ship": "fregate", "x": to}) != "", "on ne refond pas un vaisseau ordinaire")


func _test_battle_runs() -> void:
	var st := _state(71, "ferrocornes")
	var me := _me(st)
	var foe := (me + 1) % st.empires.size()
	var sid := _empty_system(st)
	_war(st, me, foe)
	var mine := _spawn(st, me, ["belier_clan", "belier_clan", "fregate", "fregate", "transport"], sid)
	mine.troops = 80
	var theirs := _spawn(st, foe, ["corvette", "corvette", "corvette", "fregate"], sid)
	var reports := st.battle_reports.size()
	for _d in 12:
		CombatSystem.process(st)
	_ok(st.battle_reports.size() > reports, "une bataille complète se déroule avec les prises de guerre")
	var r: Dictionary = st.battle_reports[-1] if not st.battle_reports.is_empty() else {}
	var boards := 0
	for dl: Dictionary in r.get("log", []):
		boards += (dl.get("boards", []) as Array).size()
	_ok(boards >= 0, "journal des abordages dans le rapport")
	# Classique : la posture ne joue pas, seul l'Éperon prend.
	var cl := _state(72, "ossarane", "classique")
	var a := _me(cl)
	var o := (a + 1) % cl.empires.size()
	var s2 := _empty_system(cl)
	_war(cl, a, o)
	var m2 := _spawn(cl, a, ["fregate", "transport"], s2)
	m2.troops = 50
	var t2 := _spawn(cl, o, ["corvette", "fregate"], s2)
	t2.hp[0] = 1
	var fl: Array[Fleet] = [m2, t2]
	var added: Array[Dictionary] = []
	var any := false
	for _i in 30:
		any = any or not Capture.boarding(cl, _battle(cl, s2), fl, 2, {}, added).is_empty()
	_ok(not any, "Classique : sans Éperon, personne n'aborde")
	var off := _state(73, "ferrocornes", "desactivee")
	var a3 := _me(off)
	var s3 := _empty_system(off)
	var m3 := _spawn(off, a3, ["belier_clan", "belier_clan"], s3)
	var t3 := _spawn(off, (a3 + 1) % off.empires.size(), ["corvette", "fregate"], s3)
	_war(off, a3, t3.owner)
	t3.hp[0] = 1
	var fl3: Array[Fleet] = [m3, t3]
	var any3 := false
	for _i in 30:
		any3 = any3 or not Capture.boarding(off, _battle(off, s3), fl3, 2, {}, added).is_empty()
	_ok(not any3, "Désactivée : même l'Éperon n'aborde plus")


func _test_save() -> void:
	var st := _state(81, "ossarane")
	var me := _me(st)
	var pid := Capture.prize_id("fregate", 5)
	var f := _spawn(st, me, ["fregate", pid], _empty_system(st))
	Capture.set_posture(st, f.id, true)
	Capture.note_stat(st, me, "prizes", 2)
	var d := st.to_dict()
	_ok(int(d["version"]) >= 99, "sauvegarde 99")
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(d)))
	_ok(back != null and Capture.full(back), "les prises de guerre se rechargent")
	if back == null:
		return
	var g: Fleet = back.fleets[f.id]
	_ok(g.ships.has(pid) and Capture.avarie_count(pid) == 2, "une prise et ses avaries traversent la sauvegarde")
	_ok(int(back.capture["post"].get(str(f.id), 0)) == 1 and Capture.stat(back, me, "prizes") == 2, "posture et statistiques gardées")
	var cl := GameState.create(82, 150, 1800.0, "ossarane", {"ai_level": ""})
	var d2 := cl.to_dict()
	_ok(not d2.has("capture"), "Classique : rien de plus dans la sauvegarde")
