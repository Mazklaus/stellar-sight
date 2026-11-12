extends RefCounted
## Tests des gardiens (Guardians, lot 2 des créatures) : placement (nombre, distance aux capitales),
## colonisation interdite, hostilité (Horloger pacifique), mort et Triomphe (trophée, savoirs anciens,
## influence, carte de récit), vraie bataille, riposte de la Vouivre, gardiens endormis (Nid sous la
## ceinture, Œuf-monde, Portes au dernier chapitre de fouille), énigme de la Citadelle, étoile rongée et
## opération « Étouffer une étoile », machines des tombeaux, IA, Bestiaire, sauvegarde 30, déterminisme.
## Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Gardiens…")
	_test_setup()
	_test_block_and_hostility()
	_test_reward()
	_test_battle()
	_test_riposte()
	_test_dormant()
	_test_citadel()
	_test_star()
	_test_tombs()
	_test_ai()
	_test_save()
	_test_determinism()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


func _new(seed_value := 11, density := "normales") -> GameState:
	return GameState.create(seed_value, 150, 1800.0, "vael", {"ai_level": "", "creatures": density})


## Le gardien voulu, créé dans un système libre s'il n'est pas dans la partie.
func _ensure(st: GameState, gid: String) -> Dictionary:
	if Guardians.list(st).has(gid):
		return Guardians.list(st)[gid]
	var cap := FactionTraits.capital_system(st, 0)
	var jumps := FactionTraits.jumps_from(st.galaxy, cap)
	for s in st.galaxy.systems:
		if st.system_owner(s.id) < 0 and s.planet_ids.size() >= 2 and int(jumps.get(s.id, 0)) >= 3 and int(jumps.get(s.id, 99)) <= 6 \
				and Fleets.fleets_at(st, s.id).is_empty() and not Fauna.nests(st).has(s.id) and Guardians.awake_at(st, s.id) == "":
			var used := false
			for o in Guardians.ids(st):
				if int(Guardians.list(st)[o]["sid"]) == s.id:
					used = true
			if used:
				continue
			Guardians._create(st, gid, s.id)
			var g: Dictionary = Guardians.list(st)[gid]
			if int(g["planet"]) < 0:
				g["planet"] = s.planet_ids[0]
			return g
	return {}


func _fleet(st: GameState, gid: String) -> Fleet:
	return st.fleets.get(int(Guardians.list(st)[gid]["fleet"]))


func _inbox_has(st: GameState, eid: int, card: String) -> bool:
	for it in Events.meta(st, eid)["inbox"]:
		if String(it["card"]) == card:
			return true
	return false


func _kill(st: GameState, gid: String, eid: int) -> Array[Dictionary]:
	var added: Array[Dictionary] = []
	var f := _fleet(st, gid)
	f.ships.clear()
	f.hp.clear()
	Guardians.on_battle(st, {"system": f.system_id}, eid, added)
	return added


func _test_setup() -> void:
	var none := _new(11, "aucune")
	_ok(Guardians.ids(none).is_empty(), "sans créatures, pas de gardiens")
	var st := _new()
	var n := Guardians.ids(st).size()
	_ok(n >= 6 and n <= 10, "6 à 10 gardiens par partie (%d sur 150 systèmes)" % n)
	var far := true
	var free := true
	var spaced := true
	for gid in Guardians.ids(st):
		var sid := int(Guardians.list(st)[gid]["sid"])
		for e in st.empires:
			if int(FactionTraits.jumps_from(st.galaxy, FactionTraits.capital_system(st, e.id)).get(sid, 99)) < int(Guardians.data()["min_jumps"]):
				far = false
		if st.system_owner(sid) >= 0:
			free = false
		for o in Guardians.ids(st):
			if o != gid and int(FactionTraits.jumps_from(st.galaxy, sid).get(int(Guardians.list(st)[o]["sid"]), 99)) < 2:
				spaced = false
	_ok(far and free and spaced, "loin des capitales, sur des systèmes libres, à 2 sauts l'un de l'autre")
	var awake := 0
	for gid in Guardians.ids(st):
		if String(Guardians.list(st)[gid]["status"]) == "awake":
			awake += 1
			var p := Combat.fleet_power(_fleet(st, gid))
			_ok(p >= 200 and p <= 600, "%s : puissance de gardien (%d)" % [gid, p])
	_ok(awake > 0, "des gardiens éveillés gardent leur système")
	var big := GameState.create(11, 260, 2400.0, "vael", {"ai_level": "", "creatures": "normales"})
	_ok(Guardians.ids(big).size() > n or Guardians.ids(big).size() == 10, "plus de gardiens dans une grande galaxie (%d)" % Guardians.ids(big).size())


func _test_block_and_hostility() -> void:
	var st := _new()
	var g := _ensure(st, "vouivre")
	var sid := int(g["sid"])
	_ok(Guardians.colony_block(st, sid) != "", "on ne colonise pas le système d'un gardien vivant")
	var pid: int = st.galaxy.systems[sid].planet_ids[0]
	_ok(Economy.check_colonize(st, 0, pid, Colony.KIND_OUTPOST).contains("veille"), "la colonisation est refusée avec la raison")
	_ok(Fauna.hostile(st, _fleet(st, "vouivre"), 0) and not Fauna.hostile(st, _fleet(st, "vouivre"), GameState.PIRATE_ID), "la Vouivre combat les empires, pas les PNJ")
	_ok(AiFauna.dangerous(st, 1, sid), "IA : le système d'un gardien est dangereux pour ses colons")
	var h := _ensure(st, "horloger")
	_ok(not h.is_empty() and not Fauna.hostile(st, _fleet(st, "horloger"), 0), "l'Horloger laisse passer")
	var added: Array[Dictionary] = []
	Guardians.card_fx(st, 0, {"system": int(h["sid"])}, {"k": "guardian", "do": "hostile"}, added)
	_ok(Fauna.hostile(st, _fleet(st, "horloger"), 0) and not Fauna.hostile(st, _fleet(st, "horloger"), 1), "provoqué, il ne combat que l'empire qui l'a provoqué")
	# Visite : une flotte qui s'arrête chez lui reçoit sa carte.
	var st2 := _new()
	var h2 := _ensure(st2, "horloger")
	st2.spawn_ship(0, "scout", int(h2["sid"]))
	var add2: Array[Dictionary] = []
	Guardians.daily(st2, add2)
	_ok(_inbox_has(st2, 0, "gardien_horloger"), "l'Horloger reçoit le visiteur (carte de dialogue)")


func _test_reward() -> void:
	var st := _new()
	var g := _ensure(st, "vouivre")
	var e := st.get_empire(0)
	var infl := int(e.resources.get("influence", 0))
	var added := _kill(st, "vouivre", 0)
	_ok(String(g["status"]) == "dead" and int(g["by"]) == 0, "abattue, la Vouivre est notée morte, par le vainqueur")
	_ok(Guardians.colony_block(st, int(g["sid"])) == "", "son système s'ouvre à la colonisation")
	_ok(Guardians.has_tech(st, 0, "ecailles_braise"), "savoir ancien hors de l'arbre : Écailles de braise")
	_ok(int(e.resources.get("influence", 0)) >= infl + int(Guardians.data()["triumph"]["influence"]), "Triomphe : influence")
	var tri := false
	for a in added:
		if String(a.get("text", "")).begins_with("Triomphe"):
			tri = true
	_ok(tri, "Triomphe annoncé dans la chronique")
	_ok(_inbox_has(st, 0, "gardien_oeuf_vouivre"), "récit : la carte de l'œuf de la Vouivre arrive")
	var trophy := String(Guardians.def("vouivre")["trophy"])
	_ok(st.relics.is_empty() or int(st.relics.get(trophy, {}).get("owner", -1)) == 0, "trophée au Reliquaire (%s)" % trophy)
	_ok(not Research.effects(st, 0).is_empty(), "les effets des savoirs anciens s'ajoutent à ceux de l'empire")
	# La Matriarche morte, les Nacrelles s'apprivoisent sans étude.
	var st2 := _new()
	_ensure(st2, "matriarche")
	_ok(not Guardians.tame_freed(st2, "nacrelles"), "Matriarche vivante : il faut étudier les Nacrelles")
	_kill(st2, "matriarche", 1)
	_ok(Guardians.tame_freed(st2, "nacrelles"), "Matriarche morte : Nacrelles apprivoisables sans étude, pour tous")


func _test_battle() -> void:
	var sim := Simulation.new(_new(17))
	var st := sim.state
	var g := _ensure(st, "ferrailleur")
	var f := st.spawn_ship(0, "croiseur", int(g["sid"]))
	for i in 14:
		f.add_ship("croiseur", -1, -1)
	sim.advance(25)
	_ok(String(g["status"]) == "dead" and int(g["by"]) == 0, "une vraie bataille abat le Ferrailleur (%s)" % g["status"])
	_ok(Guardians.has_tech(st, 0, "recyclage_ferrailleur"), "le vainqueur apprend le recyclage du Ferrailleur")


func _test_riposte() -> void:
	var st := _new()
	var g := _ensure(st, "vouivre")
	var f := _fleet(st, "vouivre")
	var cap: Colony = st.colonies[st.get_empire(0).capital_planet]
	cap.population = 8
	var pop := cap.population
	g["b_hp"] = f.total_hp()
	g["b_foes"] = [0]
	for i in f.hp.size():
		f.hp[i] = f.hp[i] * 6 / 10
	var added: Array[Dictionary] = []
	Guardians.daily(st, added)
	_ok(cap.population == pop - int(Guardians.data()["riposte_pop"]), "blessée, la Vouivre riposte sur les colonies les plus peuplées")
	_ok(f.total_hp() == f.total_max_hp(), "puis ses plaies se referment")


func _test_dormant() -> void:
	var st := _new()
	var added: Array[Dictionary] = []
	# Nid sous la ceinture.
	var belt := _ensure(st, "nid_ceinture")
	_ok(String(belt["status"]) == "dormant" and Guardians.colony_block(st, int(belt["sid"])) == "", "le Nid sous la ceinture dort (on peut s'installer)")
	belt["wake"] = int(Guardians.data()["belt_wake"]) - 1
	Guardians.daily(st, added)
	_ok(String(belt["status"]) == "awake" and _fleet(st, "nid_ceinture") != null, "à force, la ceinture se réveille")
	# Œuf-monde : une colonie établie dessus reçoit la carte au bout d'un an.
	var egg := _ensure(st, "oeuf_monde")
	var c := Colony.new()
	c.planet_id = int(egg["planet"])
	c.owner = 0
	c.kind = Colony.KIND_COLONY
	c.population = 3
	st.add_colony(c)
	Guardians.daily(st, added)
	st.tick += int(Guardians.data()["egg_days"])
	Guardians.daily(st, added)
	_ok(_inbox_has(st, 0, "gardien_oeuf_monde"), "un an après la colonisation, l'Œuf-monde pulse (carte)")
	Guardians.card_fx(st, 0, {"system": int(egg["sid"])}, {"k": "guardian", "do": "egg_hatch"}, added)
	_ok(String(egg["status"]) == "awake" and not st.colonies.has(int(egg["planet"])), "s'il éclot, la colonie est détruite et un gardien se lève")
	var st3 := _new()
	var egg3 := _ensure(st3, "oeuf_monde")
	Guardians.card_fx(st3, 0, {"system": int(egg3["sid"])}, {"k": "guardian", "do": "egg_study"}, added)
	_ok(String(egg3["status"]) == "studied" and Array(st3.galaxy.get_planet(int(egg3["planet"])).deposits).has("crystals"), "étudié, il devient un gisement de cristaux")
	# Les Portes : au dernier chapitre de la fouille.
	var gates := _ensure(st, "portes")
	Guardians.on_dig_finished(st, int(gates["sid"]), 0, added)
	_ok(_inbox_has(st, 0, "gardien_portes"), "dernier chapitre de fouille : sceller ou libérer ce qui dort sous les Portes")
	Guardians.card_fx(st, 0, {"system": int(gates["sid"])}, {"k": "guardian", "do": "gates_open"}, added)
	_ok(String(gates["status"]) == "awake" and _inbox_has(st, 0, "gardien_pacte"), "libéré, il ravage le système puis propose un pacte")
	Guardians.card_fx(st, 0, {"system": int(gates["sid"])}, {"k": "guardian", "do": "pact"}, added)
	_ok(String(gates["status"]) == "pact" and Guardians.has_tech(st, 0, "pacte_portes") and Guardians.awake_at(st, int(gates["sid"])) == "", "le pacte le renvoie et donne un savoir ancien")


func _test_citadel() -> void:
	var st := _new()
	var g := _ensure(st, "citadelle")
	_kill(st, "citadelle", 0)
	_ok(_inbox_has(st, 0, "gardien_citadelle_1"), "la Citadelle éteinte pose sa première énigme")
	var added: Array[Dictionary] = []
	Guardians.card_fx(st, 0, {"system": int(g["sid"])}, {"k": "guardian", "do": "citadel_fail"}, added)
	_ok(String(g["status"]) == "awake" and _fleet(st, "citadelle") != null, "mauvaise réponse : elle se rallume")
	Guardians.card_fx(st, 0, {"system": int(g["sid"])}, {"k": "guardian", "do": "citadel_win"}, added)
	_ok(Guardians.has_tech(st, 0, "langue_muette") and Guardians.has_tech(st, 0, "reseau_citadelle"), "trois bonnes réponses : deux savoirs anciens")
	for c in ["gardien_citadelle_1", "gardien_citadelle_2", "gardien_citadelle_3", "gardien_horloger", "gardien_oeuf_monde", "gardien_portes", "gardien_pacte", "gardien_oeuf_vouivre", "gardien_epave_veilleur"]:
		_ok(not Events.card(c).is_empty(), "carte %s chargée" % c)


func _test_star() -> void:
	var st := _new()
	var g := _ensure(st, "mange_soleil")
	_ok(Guardians.production_pct(st, int(g["sid"])) == 100 - int(Guardians.data()["sun_eater_pct"]), "le Mange-soleil ronge la production de son système")
	var cap := FactionTraits.capital_system(st, 1)
	_ok(Guardians.production_pct(st, cap) == 100, "ailleurs, production normale")
	_ok(Espionage.check_op(st, 0, 1, "etouffer") != "", "« Étouffer une étoile » fermé tant que le Mange-soleil vit")
	_kill(st, "mange_soleil", 0)
	_ok(Guardians.unlocked(st, 0, "etouffer"), "son trophée ouvre l'opération « Étouffer une étoile »")
	Guardians.choke(st, cap)
	_ok(Guardians.production_pct(st, cap) == 100 - int(Guardians.data()["choke"]["pct"]), "étoile étouffée : production réduite")
	st.tick += int(Guardians.data()["choke"]["days"]) + 1
	_ok(Guardians.production_pct(st, cap) == 100, "puis elle se rallume")


func _test_tombs() -> void:
	var d := GameData.ship("bete_machine_tombeau")
	_ok(not d.is_empty() and int(d.get("hp", 0)) > 0, "machines des tombeaux au catalogue des gardiens")
	var ships: Array = GameData.quests()["galactic"]["tombeaux"]["ships"]
	_ok(ships.has("bete_machine_tombeau"), "les tombeaux réveillent des machines, plus des pirates")


func _test_ai() -> void:
	var st := GameState.create(11, 150, 1800.0, "", {"creatures": "normales"})
	var e := st.get_empire(0)
	var g := _ensure(st, "vouivre")
	var home := FactionTraits.capital_system(st, 0)
	var hj := FactionTraits.jumps_from(st.galaxy, home)
	var sid := -1
	for s in st.galaxy.systems:
		if sid < 0 and st.system_owner(s.id) < 0 and int(hj.get(s.id, 99)) >= 3 and int(hj.get(s.id, 99)) <= 6 and Fleets.fleets_at(st, s.id).is_empty():
			sid = s.id
	_fleet(st, "vouivre").system_id = sid
	var ctx := {"state": st, "e": e, "lv": AiLevels.level("normale")}
	var f := st.spawn_ship(0, "fregate", home)
	_ok(AiFauna.nest_target(ctx, f, home) != sid, "IA : un gardien inconnu n'est pas une cible")
	(g["seen"] as Dictionary)[0] = 0
	e.explored[sid] = true
	_ok(AiFauna.nest_target(ctx, f, home) != sid, "IA : trop faible, elle n'attaque pas le gardien")
	var gp := Fauna.herd_power(st, sid)
	while Combat.fleet_power(f) * 100 < 155 * gp:
		f.add_ship("croiseur", -1, -1)
	var j := int(FactionTraits.jumps_from(st.galaxy, home).get(sid, 99))
	_ok(j <= 8, "gardien de test à portée (%d sauts)" % j)
	_ok(AiFauna.nest_target(ctx, f, home) == sid, "IA : à 1,5 fois sa force estimée, elle part l'abattre")
	var sim := Simulation.new(GameState.create(11, 150, 1800.0, "", {"creatures": "normales"}))
	sim.advance(360 * 4)
	var seen := 0
	for gid in Guardians.ids(sim.state):
		seen += (Guardians.list(sim.state)[gid]["seen"] as Dictionary).size()
	_ok(seen > 0, "les IA repèrent les gardiens (%d)" % seen)


func _test_save() -> void:
	var sim := Simulation.new(_new(13))
	var st := sim.state
	_ensure(st, "horloger")
	_ensure(st, "nid_ceinture")
	var added: Array[Dictionary] = []
	Guardians.card_fx(st, 0, {"system": 0}, {"k": "guardian", "do": "hostile"}, added)
	_ensure(st, "vouivre")
	_kill(st, "vouivre", 0)
	Guardians.choke(st, FactionTraits.capital_system(st, 1))
	sim.advance(30)
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(st.to_snapshot())))
	_ok(back != null, "sauvegarde 30 relue")
	if back == null:
		return
	_ok(back.checksum() == st.checksum(), "même empreinte après sauvegarde (gardiens)")
	_ok(Guardians.ids(back) == Guardians.ids(st) and String(Guardians.list(back)["vouivre"]["status"]) == "dead" and Guardians.has_tech(back, 0, "ecailles_braise"), "gardiens, sorts et savoirs relus")
	var a := Simulation.new(st)
	var b := Simulation.new(back)
	a.advance(200)
	b.advance(200)
	_ok(a.state.checksum() == b.state.checksum(), "la partie reprise continue à l'identique")


func _test_determinism() -> void:
	var a := Simulation.new(GameState.create(29, 150, 1800.0, "", {"creatures": "normales"}))
	var b := Simulation.new(GameState.create(29, 150, 1800.0, "", {"creatures": "normales"}))
	a.advance(700)
	b.advance(700)
	_ok(a.state.checksum() == b.state.checksum() and not Guardians.ids(a.state).is_empty(), "même graine, mêmes gardiens après 700 jours")
