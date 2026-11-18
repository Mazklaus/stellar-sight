class_name LivingTests
extends RefCounted
## Tests des mondes vivants (étude du 2026-11-18, version complète : 33 propositions). Données et
## réglage, placement, humeur et paliers, découverte, effets sur la colonie, demandes, Rejet et départ,
## sauvegarde (lot 1) ; décharges, sol, refuge, anticorps, invitation, IA (lot 2) ; meurtre d'un monde,
## Forge, nef-graine, fusion, écoute, éveil, Monde-Ego, fiche et menu (lot 3). Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Mondes vivants…")
	print("  - data")
	_test_data()
	print("  - setup")
	_test_setup()
	print("  - mood")
	_test_mood()
	print("  - effects")
	_test_effects()
	print("  - requests")
	_test_requests()
	print("  - reject")
	_test_reject()
	print("  - save")
	_test_save()
	print("  - war")
	_test_war()
	print("  - invite")
	_test_invite()
	print("  - murder")
	_test_murder()
	print("  - seed / fuse")
	_test_seed_fuse()
	print("  - listen / wake")
	_test_listen_wake()
	print("  - ego")
	_test_ego()
	print("  - ui / ai")
	_test_ui_ai()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


static func new_game(mode := "rares", ego := "non", faction := "ossarane", extra := {}) -> GameState:
	var opts := {"ai_level": "", "living": mode, "living_ego": ego}
	opts.merge(extra, true)
	return GameState.create(4343, 150, 1800.0, faction, opts)


static func first(st: GameState) -> int:
	var ids := LivingWorlds.ids(st)
	return ids[0] if not ids.is_empty() else -1


static func colonize(st: GameState, pid: int, eid: int, pop := 6) -> Colony:
	var c := Colony.new()
	c.planet_id = pid
	c.owner = eid
	c.kind = Colony.KIND_COLONY
	c.days_left = 0
	c.population = pop
	st.colonies[pid] = c
	st.rebuild_ownership()
	return c


static func cmd(st: GameState, eid: int, act: String, pid: int) -> String:
	var c := SimCommands.living_act(eid, act, {"p": pid})
	var why := SimCommands.validate(st, c)
	if why == "":
		SimCommands.apply(st, c)
	return why


func _test_data() -> void:
	var d := GameData.livingworlds()
	_ok(not d.is_empty(), "données des mondes vivants chargées")
	_ok(LivingWorlds.mode_defs().size() == 3 and LivingWorlds.default_mode() == "rares", "trois réglages, Rares par défaut")
	_ok(LivingWorlds.default_ego() == "non", "Monde-Ego désactivé par défaut")
	var last := -1000
	var sorted := true
	for t: Dictionary in LivingWorlds.tiers():
		sorted = sorted and int(t["max"]) > last
		last = int(t["max"])
	_ok(sorted and LivingWorlds.tiers().size() == 5, "cinq paliers d'humeur, ordonnés")
	for o in LivingWorlds.origin_ids():
		_ok(LivingWorlds.origin_def(o).has("label") and Fauna.species(String(LivingWorlds.origin_def(o).get("antibody", ""))).size() > 0, "origine %s : nom et anticorps existants" % o)
	_ok(LivingWorlds.temper_ids().size() >= 5, "cinq tempéraments au moins (catalogue ouvert)")
	for k in ["lw_demande", "lw_eveil", "lw_visiteurs"]:
		_ok(not Events.card(k).is_empty(), "carte %s enregistrée" % k)
	_ok(not GameData.ship("vivant_nef_graine").is_empty(), "la nef-graine se lit comme une classe")
	_ok(not Faiths.precept_def("gardiens_monde").is_empty(), "précepte Gardiens du monde")
	for a in ["living_wake", "living_anger", "living_leave", "living_ego"]:
		_ok(not Announce.kind_def(a).is_empty(), "annonce %s" % a)


func _test_setup() -> void:
	var off := GameState.create(4343, 150, 1800.0, "ossarane", {"ai_level": ""})
	_ok(off.living.is_empty(), "sans option : pas de monde vivant")
	_ok(new_game("aucun").living.is_empty(), "réglage Aucun : rien")
	var st := new_game()
	_ok(LivingWorlds.enabled(st) and LivingWorlds.ids(st).size() >= 1, "réglage Rares : au moins un monde vivant")
	var pid := first(st)
	var p := st.galaxy.get_planet(pid)
	_ok(not st.colonies.has(pid) and p.size >= 5, "monde vivant de départ : libre et assez grand")
	var cap := st.galaxy.get_planet(st.get_empire(0).capital_planet).system_id
	_ok(int(FactionTraits.jumps_from(st.galaxy, cap).get(p.system_id, 99)) >= 4, "loin de la capitale du joueur")
	var fr := new_game("frequents")
	_ok(LivingWorlds.ids(fr).size() >= LivingWorlds.ids(st).size(), "Fréquents : au moins autant")
	_ok(not LivingWorlds.knows(st, pid, 0), "le monde n'est pas encore connu")
	st.spawn_ship(0, GameData.class_ids()[0], p.system_id)
	LivingWorlds._discover(st, pid, LivingWorlds.world(st, pid))
	_ok(LivingWorlds.knows(st, pid, 0), "une flotte en orbite : le monde est reconnu vivant")


func _test_mood() -> void:
	var st := new_game()
	var pid := first(st)
	var w := LivingWorlds.world(st, pid)
	w["t"] = "curieux"
	LivingWorlds.set_mood(st, pid, 0, -60)
	_ok(LivingWorlds.tier_id(st, pid, 0) == "hostile" and LivingWorlds.hates(st, pid, 0), "-60 : Hostile")
	LivingWorlds.set_mood(st, pid, 0, -20)
	_ok(LivingWorlds.tier_id(st, pid, 0) == "mefiant" and LivingWorlds.dislikes(st, pid, 0), "-20 : Méfiant")
	LivingWorlds.set_mood(st, pid, 0, 0)
	_ok(LivingWorlds.tier_id(st, pid, 0) == "neutre", "0 : Neutre")
	LivingWorlds.add_mood(st, pid, 0, 30)
	_ok(LivingWorlds.tier_id(st, pid, 0) == "bienveillant" and LivingWorlds.loves(st, pid, 0), "+30 : Bienveillant")
	LivingWorlds.set_mood(st, pid, 0, 90)
	_ok(LivingWorlds.tier_index(st, pid, 0) == 4, "+90 : Lié")
	# Tolérance : après une colère, les pertes sont amorties.
	LivingWorlds.set_mood(st, pid, 0, 0)
	LivingWorlds.harden(st, pid, 0)
	LivingWorlds.add_mood(st, pid, 0, -20)
	_ok(LivingWorlds.mood(st, pid, 0) == -18, "tolérance : -20 devient -18 (%d)" % LivingWorlds.mood(st, pid, 0))
	# Énigme : humeur cachée tant qu'on ne l'a pas écoutée.
	w["t"] = "enigme"
	(w["known"] as Dictionary)["0"] = 1
	_ok(not LivingWorlds.mood_known(st, pid, 0), "Énigme : humeur cachée")
	(w["deep"] as Dictionary)["0"] = 1
	_ok(LivingWorlds.mood_known(st, pid, 0), "Énigme écoutée : humeur visible")
	# Hanté : plafonné pour qui n'a pas fait l'Éveil.
	w["o"] = "hante"
	LivingWorlds.set_mood(st, pid, 0, 80)
	_ok(LivingWorlds.mood(st, pid, 0) <= -30, "Hanté : humeur plafonnée")
	# Guerre près du monde : il n'aime pas.
	w["o"] = "eveille"
	w["t"] = "curieux"
	LivingWorlds.set_mood(st, pid, 0, 0)
	st.battles[LivingWorlds.sys_of(st, pid)] = {"sides": [{"empire": 0}]}
	LivingWorlds._moods(st, pid, w)
	st.battles.erase(LivingWorlds.sys_of(st, pid))
	_ok(LivingWorlds.mood(st, pid, 0) < 0, "une bataille dans son ciel : humeur en baisse")


func _test_effects() -> void:
	var st := new_game()
	var pid := first(st)
	var p := st.galaxy.get_planet(pid)
	LivingWorlds.set_mood(st, pid, 0, -70)
	_ok(LivingWorlds.colony_block(st, pid, 0) != "", "Hostile : il refuse les colons")
	_ok(Economy.check_colonize(st, 0, pid, Colony.KIND_COLONY).contains("rejette") or Economy.check_colonize(st, 0, pid, Colony.KIND_COLONY) != "", "Economy.check_colonize refuse")
	LivingWorlds.set_mood(st, pid, 0, -20)
	_ok(LivingWorlds.claim_days(st, 0, pid, 30) == 60, "Méfiant : installation deux fois plus longue")
	LivingWorlds.set_mood(st, pid, 0, 60)
	colonize(st, pid, 0)
	var base := LivingWorlds.pop_bonus(st, pid, 0)
	_ok(base > 0, "Bienveillant : population en plus (%d)" % base)
	_ok(int(LivingWorlds.income(st, 0)["gross"].get("food", 0)) > 0, "Bienveillant : il nourrit ses hôtes")
	var parts := LivingWorlds.stability_parts(st, p.system_id, 0)
	_ok(not parts.is_empty() and int(parts[0][1]) > 0, "Bienveillant : stabilité en plus")
	LivingWorlds.set_mood(st, pid, 0, -70)
	_ok(LivingWorlds.pop_bonus(st, pid, 0) < 0, "Hostile : population en moins")
	var w := LivingWorlds.world(st, pid)
	w["fav"] = Peoples.founder_of(st, 0)
	_ok(LivingWorlds.growth_pct(st, pid) == 20, "espèce préférée : croissance +20 %")
	w["repos"] = {"e": 0, "until": st.tick + 100}
	_ok(LivingWorlds.production_pct(st, pid) == 70, "sol en repos : production -30 %")


func _test_requests() -> void:
	var st := new_game()
	var pid := first(st)
	colonize(st, pid, 0)
	var w := LivingWorlds.world(st, pid)
	w["t"] = "curieux"
	w["next_req"] = st.tick
	st.get_empire(0).resources["influence"] = 500
	st.get_empire(0).resources["knowledge"] = 500
	st.get_empire(0).resources["food"] = 500
	st.get_empire(0).resources["energy"] = 500
	var added: Array[Dictionary] = []
	LivingWorlds._requests(st, pid, w, added)
	var req: Dictionary = w.get("req", {})
	_ok(not req.is_empty() and int(req["e"]) == 0, "une demande à son hôte (%s)" % str(req))
	var box := Events.inbox(st, 0)
	var item := {}
	for it: Dictionary in box:
		if String(it["card"]) == "lw_demande":
			item = it
	_ok(not item.is_empty(), "la carte Le monde demande arrive")
	_ok(not Events.fill(st, 0, item, String(Events.card("lw_demande")["text"])).contains("{lw_"), "jetons de la carte remplacés")
	var m0 := LivingWorlds.mood(st, pid, 0)
	LivingWorlds.set_mood(st, pid, 0, 0)
	m0 = 0
	Events.choose(st, 0, int(item["id"]), 0, added)
	_ok(LivingWorlds.mood(st, pid, 0) > m0, "demande acceptée : humeur en hausse")
	_ok((w.get("req", {}) as Dictionary).is_empty(), "demande soldée")
	w["req"] = {"k": "chant", "e": 0}
	LivingWorlds.answer(st, 0, pid, false, added)
	_ok(LivingWorlds.mood(st, pid, 0) < 20, "demande refusée : humeur en baisse")
	# Obligation : chasser les flottes, trahie.
	LivingWorlds.set_mood(st, pid, 0, 0)
	w["watch"] = {"k": "nofleet", "e": 0, "until": st.tick + 100}
	var war_ship := ""
	for sid in GameData.class_ids():
		if int(GameData.ship(sid).get("attack", 0)) > 0:
			war_ship = sid
			break
	if war_ship != "":
		st.spawn_ship(0, war_ship, LivingWorlds.sys_of(st, pid))
		LivingWorlds._watch(st, pid, w, added)
		_ok(LivingWorlds.mood(st, pid, 0) < 0, "promesse trahie : humeur en baisse")


func _test_reject() -> void:
	var st := new_game()
	var pid := first(st)
	var sid := LivingWorlds.sys_of(st, pid)
	colonize(st, pid, 0)
	LivingWorlds.set_mood(st, pid, 0, -80)
	var w := LivingWorlds.world(st, pid)
	w["hate"] = LivingWorlds.r_int("reject_days", 1080) - 30
	var added: Array[Dictionary] = []
	LivingWorlds._reject_and_leave(st, pid, w, added)
	_ok(not st.colonies.has(pid), "le Rejet chasse la colonie Hostile")
	_ok((w["rej"] as Dictionary).has("0"), "le Rejet est noté")
	_ok(int((w["thr"] as Dictionary).get("0", 0)) > 0, "tolérance accrue après la colère")
	# Un an plus tard, le système toujours tenu par l'empire Hostile : il part.
	var other: int = -1
	for q in st.galaxy.systems[sid].planet_ids:
		if q != pid and not st.colonies.has(q):
			other = q
			break
	if other >= 0:
		var oc := colonize(st, other, 0)
		oc.kind = Colony.KIND_OUTPOST
		st.rebuild_ownership()
	(w["rej"] as Dictionary)["0"] = st.tick - LivingWorlds.r_int("leave_days", 360)
	LivingWorlds.set_mood(st, pid, 1, 60)  # un rival qu'il aime : il part chez lui s'il y a de la place
	LivingWorlds._reject_and_leave(st, pid, w, added)
	var p := st.galaxy.get_planet(pid)
	_ok(p.system_id != sid or not LivingWorlds.is_living(st, pid), "un an plus tard, le monde s'en va")
	if LivingWorlds.is_living(st, pid):
		var back := GameState.from_dict(st.to_dict())
		_ok(back.galaxy.get_planet(pid).system_id == p.system_id and back.galaxy.systems[p.system_id].planet_ids.has(pid), "sauvegarde : le monde reste où il est parti")
		_ok(not back.galaxy.systems[sid].planet_ids.has(pid), "sauvegarde : il a quitté son ancien système")


func _test_save() -> void:
	_ok(GameState.FORMAT_VERSION >= 95 and GameState.READABLE_VERSIONS.has(94), "format 95 ou plus, 94 toujours lisible")
	var st := new_game("frequents", "oui")
	var pid := first(st)
	LivingWorlds.set_mood(st, pid, 0, 42)
	var d := st.to_dict()
	_ok(d.has("living"), "les mondes vivants sont sauvegardés")
	var back := GameState.from_dict(d)
	_ok(LivingWorlds.mood(back, pid, 0) == 42 and LivingWorlds.ego_on(back), "rechargés : humeur et Monde-Ego")
	_ok(LivingWorlds.ids(back) == LivingWorlds.ids(st), "rechargés : mêmes mondes")
	var snap := GameState.from_dict(st.to_snapshot())
	_ok(LivingWorlds.ids(snap) == LivingWorlds.ids(st), "instantané réseau : mêmes mondes")
	var old := new_game("aucun").to_dict()
	old.erase("living")
	old["version"] = 94
	var ob := GameState.from_dict(old)
	_ok(ob != null and ob.living.is_empty(), "sauvegarde 94 : rien à faire")


func _test_war() -> void:
	var st := new_game()
	var pid := first(st)
	var sid := LivingWorlds.sys_of(st, pid)
	LivingWorlds.set_mood(st, pid, 0, 60)
	LivingWorlds.set_mood(st, pid, 1, -70)
	_ok(LivingWorldsWar.ground_pct(st, sid, 0) > 0 and LivingWorldsWar.ground_pct(st, sid, 1) < 0, "le sol choisit son camp")
	var war_ship := ""
	for k in GameData.class_ids():
		if int(GameData.ship(k).get("attack", 0)) > 0:
			war_ship = k
			break
	var mine := st.spawn_ship(0, war_ship if war_ship != "" else GameData.class_ids()[0], sid)
	_ok(LivingWorldsWar.refuge(st, mine), "flotte d'un ami : refuge en orbite")
	var theirs := st.spawn_ship(1, war_ship if war_ship != "" else GameData.class_ids()[0], sid)
	_ok(not LivingWorldsWar.refuge(st, theirs), "pas de refuge pour l'ennemi")
	Combat.start_war(st, 0, 1)
	var hp0 := 0
	for v in theirs.hp:
		hp0 += int(v)
	var added: Array[Dictionary] = []
	LivingWorldsWar.battle_day(st, sid, [mine, theirs], added)
	var hp1 := 0
	if st.fleets.has(theirs.id):
		for v in theirs.hp:
			hp1 += int(v)
	_ok(hp1 < hp0, "décharge : le monde frappe la flotte qu'il hait (%d -> %d)" % [hp0, hp1])
	# Anticorps : seul l'empire visé est chassé.
	_ok(LivingWorldsWar.antibody_hostile({"lw": 1}, 1) == true and LivingWorldsWar.antibody_hostile({"lw": 1}, 0) == false, "anticorps : seul l'empire visé")
	_ok(LivingWorldsWar.antibody_hostile({}, 0) == null, "troupeau ordinaire : règle habituelle")
	_ok(LivingWorldsWar.ai_avoid(st, sid, 1, 0), "IA : éviter le système d'un monde qui aime le défenseur")


func _test_invite() -> void:
	var st := new_game()
	var pid := first(st)
	var w := LivingWorlds.world(st, pid)
	(w["known"] as Dictionary)["0"] = 1
	LivingWorlds.set_mood(st, pid, 0, 10)
	_ok(cmd(st, 0, "invite", pid) != "", "invitation refusée sous Bienveillant")
	LivingWorlds.set_mood(st, pid, 0, 40)
	var e := st.get_empire(0)
	for r in LivingWorldsWar.invite_cost(st, 0):
		e.resources[r] = 5000
	var why := cmd(st, 0, "invite", pid)
	_ok(why == "", "invitation acceptée (%s)" % why)
	_ok(st.system_owner(st.galaxy.get_planet(pid).system_id) == 0, "le monde vient se poser chez vous")
	_ok(cmd(st, 0, "invite", pid) != "", "pas deux invitations de suite")


func _test_murder() -> void:
	var st := new_game("frequents", "non", "ossarane", {"worldforge": "complete"})
	var ids := LivingWorlds.ids(st)
	var pid: int = ids[0]
	_ok(WorldForgeBridges.untouchable(st, 0, pid).has("un monde vivant"), "Forge : un monde vivant est intouchable")
	LivingWorlds.set_mood(st, pid, 0, 0)
	LivingWorlds.on_dismantle_start(st, pid, 0)
	_ok(LivingWorlds.mood(st, pid, 0) < 0, "un chantier de démantèlement l'inquiète")
	var added: Array[Dictionary] = []
	LivingWorlds.on_murder(st, pid, 0, added)
	_ok(not LivingWorlds.is_living(st, pid), "un monde vivant tué")
	if ids.size() > 1:
		_ok(LivingWorlds.mood(st, int(ids[1]), 0) <= -60, "les autres mondes vivants l'ont entendu")
	_ok(LivingWorlds.stat(st, 0, "murder") == 1, "le meurtre est compté")
	# Reliquaire qui s'éveille vivant.
	var rp := -1
	for p in st.galaxy.planets:
		if not LivingWorlds.is_living(st, p.id) and not st.colonies.has(p.id):
			rp = p.id
			break
	_ok(LivingWorldsBridges.relic_wakes(st, rp, 0) and String(LivingWorlds.world(st, rp)["o"]) == "reliquaire", "un reliquaire s'éveille en monde vivant")


func _test_seed_fuse() -> void:
	var st := new_game()
	var pid := first(st)
	var w := LivingWorlds.world(st, pid)
	(w["known"] as Dictionary)["0"] = 1
	var c := colonize(st, pid, 0)
	LivingWorlds.set_mood(st, pid, 0, 40)
	_ok(cmd(st, 0, "seed", pid) != "", "pas de nef-graine sans lien")
	LivingWorlds.set_mood(st, pid, 0, 90)
	var n0 := LivingWorldsBridges.seed_count(st, 0)
	var why := cmd(st, 0, "seed", pid)
	_ok(why == "" and LivingWorldsBridges.seed_count(st, 0) == n0 + 1, "Lié : une nef-graine (%s)" % why)
	_ok(cmd(st, 0, "seed", pid) != "", "la graine suivante doit mûrir")
	(w["lie"] as Dictionary)["0"] = st.tick
	_ok(cmd(st, 0, "fuse", pid).contains("ans"), "fusion : il faut un long lien")
	st.tick += LivingWorlds.r_int("fuse_days", 3600)
	why = cmd(st, 0, "fuse", pid)
	_ok(why == "" and int(w["fused"]) == 0, "fusion faite (%s)" % why)
	_ok(LivingWorlds.fused_colony(st, c) and Movements.push_reason(st, c) == "", "monde fusionné : personne ne part")
	LivingWorlds.set_mood(st, pid, 1, 60)
	_ok(LivingWorlds.check_war(st, 0, 1) != "", "monde fusionné : il refuse la guerre contre un ami")
	_ok(LivingWorlds.production_pct(st, pid) > 100, "fusion : production en hausse")


func _test_listen_wake() -> void:
	var st := new_game()
	var pid := first(st)
	var w := LivingWorlds.world(st, pid)
	(w["known"] as Dictionary)["0"] = 1
	_ok(LivingWorldsBridges.check_listen(st, 0, pid) != "", "écouter : il faut des pouvoirs psioniques")
	var mm := new_game("rares", "non", "murmurants")
	var mp := first(mm)
	(LivingWorlds.world(mm, mp)["known"] as Dictionary)["0"] = 1
	if LivingWorlds.t_bool(mm, 0, "free_listen"):
		var why := cmd(mm, 0, "listen", mp)
		_ok(why == "" and (LivingWorlds.world(mm, mp)["deep"] as Dictionary).has("0"), "Murmurants : écoute sans Résonance (%s)" % why)
	# Éveil en cours de partie : carte Le monde s'éveille, réponse « laisser s'éveiller ».
	var cand := -1
	for p in st.galaxy.planets:
		if not LivingWorlds.is_living(st, p.id) and p.type == "continental":
			cand = p.id
			break
	var added: Array[Dictionary] = []
	LivingWorldsBridges.event_act(st, 0, cand, "wake", added)
	_ok(LivingWorlds.is_living(st, cand) and LivingWorlds.knows(st, cand, 0), "éveil accepté : un nouveau monde vivant")
	var cand2 := -1
	for p in st.galaxy.planets:
		if not LivingWorlds.is_living(st, p.id) and p.id != cand:
			cand2 = p.id
			break
	LivingWorldsBridges.event_act(st, 0, cand2, "sleep", added)
	_ok(LivingWorlds.sub(st, "slept").has(str(cand2)), "monde endormi pour toujours")


func _test_ego() -> void:
	var st := new_game("rares", "oui")
	_ok(LivingWorlds.ego_on(st), "Monde-Ego en jeu")
	var added: Array[Dictionary] = []
	LivingWorldsBridges.ego_monthly(st, added)
	_ok(LivingWorldsBridges.ego_pid(st) < 0, "Ego dort jusqu'à l'an 40")
	st.tick = 40 * 12 * int(GameData.rules()["month_days"])
	LivingWorldsBridges.ego_monthly(st, added)
	var ep := LivingWorldsBridges.ego_pid(st)
	_ok(ep >= 0 and LivingWorlds.mood(st, ep, 0) == -100, "Ego s'éveille, hostile à tous")
	_ok(LivingWorlds.colony_block(st, ep, 0) != "", "on ne s'installe pas sur Ego")
	LivingWorldsBridges.ego(st)["next"] = st.tick
	LivingWorldsBridges.ego_monthly(st, added)
	var seeds: Dictionary = LivingWorldsBridges.ego(st)["seeds"]
	if not seeds.is_empty():
		var tp := int(seeds.keys()[0])
		_ok(LivingWorldsBridges.ego_holds(st, tp), "une graine d'Ego interdit la planète visée")
		seeds[str(tp)] = st.tick
		LivingWorldsBridges.ego(st)["next"] = st.tick + 9999
		LivingWorldsBridges.ego_monthly(st, added)
		_ok((LivingWorldsBridges.ego(st)["ext"] as Dictionary).has(str(tp)), "la graine germe : extension d'Ego")
	# Le noyau : une coalition qui tient l'orbite l'abat.
	LivingWorldsBridges.ego(st)["siege"] = int(LivingWorlds.cfg("ego").get("kill_days", 30))
	LivingWorldsBridges._ego_fall(st, ep, [0], added)
	_ok(LivingWorldsBridges.ego_pid(st) < 0 and not LivingWorlds.is_living(st, ep), "Ego abattu")


func _test_ui_ai() -> void:
	var st := new_game()
	var pid := first(st)
	var p := st.galaxy.get_planet(pid)
	_ok(LivingUi.lines(st, 0, p).is_empty(), "fiche : rien tant qu'il n'est pas connu")
	(LivingWorlds.world(st, pid)["known"] as Dictionary)["0"] = 1
	var lines := LivingUi.lines(st, 0, p)
	_ok(not lines.is_empty() and lines[0].begins_with("Monde vivant"), "fiche : nom, origine, tempérament")
	_ok(LivingUi.lines(st, -1, p).size() > 1, "fiche spectateur : humeur envers chacun")
	LivingWorlds.set_mood(st, pid, 0, 40)
	var acts := LivingUi.system_actions(st, 0, p, func(_c: Dictionary) -> void: pass)
	var has_invite := false
	for a: Dictionary in acts:
		has_invite = has_invite or String(a["text"]).begins_with("Inviter")
	_ok(has_invite, "fiche : action Inviter")
	# IA : valeur des cartes.
	(LivingWorlds.world(st, pid))["req"] = {"k": "chant", "e": 1}
	st.get_empire(1).resources["influence"] = 999
	st.get_empire(1).resources["knowledge"] = 999
	var item := {"planet": pid}
	_ok(AiLiving.card_value(st, 1, item, "yes", 0) > AiLiving.card_value(st, 1, item, "no", 0), "IA : accepte une demande facile qu'elle peut payer")
	(LivingWorlds.world(st, pid))["req"] = {"k": "paix", "e": 1, "r": 0}
	_ok(AiLiving.card_value(st, 1, item, "yes", 2) < 0, "IA belliqueuse : refuse la paix")
	# Le mois de l'IA tourne sans erreur.
	for e in st.empires:
		if e.is_ai():
			(LivingWorlds.world(st, pid)["known"] as Dictionary)[str(e.id)] = 1
	for i in 3:
		st.tick += 30
		LivingWorlds.monthly(st, [] as Array[Dictionary])
	_ok(LivingWorlds.enabled(st), "trois mois de mondes vivants sans erreur")
