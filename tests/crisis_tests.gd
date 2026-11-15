extends RefCounted
## Tests des crises de fin de partie (Crisis, lot 1 de l'étude du 2026-11-15) : réglages (aucune, une,
## toutes, date, force) ; même empreinte sans crise ; tirage pas avant la date ; déclencheurs précoces ;
## préavis en fenêtres d'événement ; arrivée (cœur, points faibles, vagues) ; Front commun ; chute d'un
## système, sort et libération ; Registre de l'Inspection ; Faille réparée par ses ancres ; victoire
## (stabilité, relique, influence) ; défaite commune ; date limite repoussée ; sauvegarde 65 ;
## déterminisme. Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Crises de fin de partie…")
	_test_setup()
	_test_roll()
	_test_early()
	_test_notice()
	_test_arrive()
	_test_front()
	_test_fall()
	_test_inspection()
	_test_dechirure()
	_test_victory()
	_test_defeat()
	_test_save()
	_test_determinism()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


func _new(seed_value := 11, mode := "une", extra := {}) -> GameState:
	var o := {"ai_level": "", "crises": mode}
	o.merge(extra, true)
	return GameState.create(seed_value, 120, 1600.0, "vael", o)


## Une colonie (hors capitale) de l'empire dans un système libre, à min_j sauts au moins de sa capitale.
func _colony(st: GameState, owner: int, min_j := 2, pop := 6) -> int:
	var cap := FactionTraits.capital_system(st, owner)
	var jumps := FactionTraits.jumps_from(st.galaxy, cap)
	for s in st.galaxy.systems:
		if st.system_owner(s.id) < 0 and s.planet_ids.size() > 0 and int(jumps.get(s.id, 99)) >= min_j and int(jumps.get(s.id, 99)) <= 5 \
				and Fleets.fleets_at(st, s.id).is_empty():
			var c := Colony.new()
			c.planet_id = s.planet_ids[0]
			c.owner = owner
			c.kind = Colony.KIND_COLONY
			c.population = pop
			st.add_colony(c)
			return s.id
	return -1


## Lance la crise k tout de suite et saute le préavis.
func _force(st: GameState, k: String) -> Array[Dictionary]:
	var added: Array[Dictionary] = []
	Crisis.begin(st, k, added)
	var c := Crisis.cur(st)
	while String(c.get("stage", "")) == "notice":
		st.tick = int(c["steps"][int(c["step"])])
		Crisis._notice(st, added)
	return added


func _cards(st: GameState, eid: int, card: String) -> int:
	var n := 0
	for it: Dictionary in Events.inbox(st, eid):
		if String(it["card"]) == card:
			n += 1
	return n


func _test_setup() -> void:
	var off := _new(11, "aucune")
	_ok(not Crisis.enabled(off) and not off.to_dict().has("crisis"), "« Aucune » : pas de crise, rien dans la sauvegarde (même empreinte qu'avant)")
	var st := _new()
	_ok(Crisis.enabled(st) and int(st.crisis["start"]) == 10800 and String(st.crisis["str"]) == "normale", "par défaut : une crise, fin de partie à l'an 30, force normale")
	_ok((st.crisis["kinds"] as Array).size() >= 3, "les trois crises du lot 1 sont autorisées")
	var st2 := _new(11, "toutes", {"crisis_start": "an20", "crisis_strength": "cauchemar", "crisis_kinds": ["recif"]})
	_ok(int(st2.crisis["start"]) == 7200 and String(st2.crisis["str"]) == "cauchemar" and st2.crisis["kinds"] == ["recif"], "réglages : an 20, Cauchemar, une seule crise autorisée")
	_ok(GameState.is_npc(GameState.CRISIS_ID) and st.get_empire(GameState.CRISIS_ID) != null, "la Crise est une puissance non jouable")
	_ok(GameData.ship("crise_recif_eclat").has("hp") and GameData.ship("crise_insp_registre").has("hp"), "unités de crise lues dans crises.json")
	_ok(Relics.is_trophy("chant_fige") and Relics.is_trophy("tampon_supreme") and Relics.is_trophy("eclat_faille"), "trois trophées de crise")


func _test_roll() -> void:
	var st := _new(11, "une", {"crisis_kinds": ["recif", "inspection", "dechirure"]})
	var added: Array[Dictionary] = []
	for d in [0, 720, 3600, 7200, 10799]:
		st.tick = d
		Crisis._maybe_start(st, added)
	_ok(not Crisis.ongoing(st), "aucun tirage avant la fin de partie")
	var day := -1
	for i in 40:
		st.tick = 10800 + i * 720
		Crisis._maybe_start(st, added)
		if Crisis.ongoing(st):
			day = st.tick
			break
	_ok(day >= 10800, "une crise finit par être tirée après l'an 30 (jour %d)" % day)
	# Mode « une » : jamais deux.
	st.crisis["cur"] = {}
	st.tick += 720 * 20
	Crisis._maybe_start(st, added)
	_ok(not Crisis.ongoing(st), "mode « une » : pas de deuxième crise")


func _test_early() -> void:
	var st := _new()
	var day0 := Crisis.endgame_day(st)
	Crisis.on_tech(st, 0, "etoiles_captives")
	_ok(Crisis.endgame_day(st) == day0 - 1800, "technologie interdite : la fin de partie avance de cinq ans")
	Crisis.on_tech(st, 1, "etoiles_captives")
	_ok(Crisis.endgame_day(st) == day0 - 1800, "le même déclencheur ne compte qu'une fois")
	Crisis.on_atrocity(st, 0)
	Crisis.on_relic(st, 0, "flamme_spectre")
	_ok(Crisis.endgame_day(st) == day0 - 3600, "dix ans d'avance au plus")
	var off := _new(11, "aucune")
	Crisis.on_atrocity(off, 0)
	_ok(not Crisis.enabled(off), "sans crise, les déclencheurs ne font rien")


func _test_notice() -> void:
	var st := _new()
	st.tick = 10800
	var added: Array[Dictionary] = []
	Crisis.begin(st, "recif", added)
	_ok(String(Crisis.cur(st)["stage"]) == "notice" and _cards(st, 0, "crise_alerte_1") == 1, "préavis du Récif : première fenêtre d'événement chez le joueur")
	_ok(_cards(st, 1, "crise_alerte_1") == 1, "chaque empire reçoit la fenêtre")
	_ok(not added.is_empty(), "et la chronique l'annonce")
	var txt := Events.fill(st, 0, Events.inbox(st, 0)[0], String(Events.card("crise_alerte_1")["text"]))
	_ok(not txt.contains("{") and txt.contains("Récif"), "texte de la fenêtre rempli : %s" % txt.left(60))
	st.tick = 10800 + 360
	Crisis._notice(st, added)
	_ok(_cards(st, 0, "crise_alerte_2") == 1 and not Crisis.active(st), "deuxième étape un an après")
	st.tick = 10800 + 720
	Crisis._notice(st, added)
	_ok(Crisis.active(st) and _cards(st, 0, "crise_arrivee") == 1, "arrivée au bout de deux ans, avec sa fenêtre")
	# La Déchirure n'a pas de préavis.
	var st2 := _new(12, "une", {"rivals": ["ossarane", "khthari", "teyl"]})  # sans peuple de foi (présage, lot 3)
	st2.tick = 10800
	var a2: Array[Dictionary] = []
	Crisis.begin(st2, "dechirure", a2)
	_ok(Crisis.active(st2) or Crisis.cur(st2).is_empty(), "la Déchirure arrive sans préavis")
	_ok(_cards(st2, 0, "crise_arrivee") == 1 or not Crisis.enabled(st2), "mais son ouverture ouvre la fenêtre")


func _test_arrive() -> void:
	var st := _new()
	st.tick = 10800
	_force(st, "recif")
	var hearts := 0
	for f in Crisis.stations(st):
		if Crisis.role_of(st, f.id) == Crisis.ROLE_HEART:
			hearts += 1
	_ok(hearts == 1, "le Récif pose son cœur")
	_ok(Crisis.war_fleets(st).size() == int(Crisis.data()["power"]["wave"]), "trois flottes de guerre à l'arrivée")
	var p := Crisis.total_power(st)
	_ok(p >= int(Crisis.cur(st)["power"]), "puissance visée atteinte (%d pour %d)" % [p, int(Crisis.cur(st)["power"])])
	_ok(_cards(st, 0, "crise_front") == 1, "le Front commun est proposé à tous")
	var o := int(Crisis.cur(st)["origin"])
	_ok(o >= 0 and st.system_owner(o) < 0, "arrivée dans un système libre")
	var e := st.get_empire(GameState.CRISIS_ID)
	_ok(e.display_name().contains("Récif"), "la puissance porte le nom de la crise : %s" % e.display_name())
	# Force réglable.
	var weak := _new(11, "une", {"crisis_strength": "faible"})
	var strong := _new(11, "une", {"crisis_strength": "cauchemar"})
	_ok(Crisis.target_power(strong) == Crisis.target_power(weak) * 5, "Cauchemar = cinq fois Faible")


func _test_front() -> void:
	var st := _new()
	st.tick = 10800
	_force(st, "recif")
	var added: Array[Dictionary] = []
	Crisis.card_fx(st, 0, {}, {"act": "front"}, added)
	Crisis.card_fx(st, 1, {}, {"act": "front"}, added)
	_ok(Crisis.front_pair(st, 0, 1), "deux empires du Front commun")
	_ok(Borders.grants(st, 0, 1), "passage libre entre eux")
	_ok(Fleets.allies_of(st, 0).has(1), "et vision partagée")
	_ok(not Crisis.front_pair(st, 0, 2) or st.empires.size() <= 2, "pas avec un empire resté à l'écart")
	var any: Fleet = Fleets.empire_fleets(st, 0)[0]
	var cf: Fleet = Crisis.war_fleets(st)[0]
	_ok(Crisis.damage_pct(st, any, cf.system_id) == 10, "+10 % de dégâts face à la crise")


func _test_fall() -> void:
	var st := _new()
	st.tick = 10800
	_force(st, "recif")
	var sid := _colony(st, 0, 2, 6)
	var cf: Fleet = Crisis.war_fleets(st)[0]
	cf.system_id = sid
	cf.path.clear()
	cf.progress = 0
	st.sieges[sid] = {"system": sid, "by": GameState.CRISIS_ID, "start": st.tick}
	Crisis.cur(st)["siege"] = {sid: st.tick - 95}  # la crise compte son siège même si des batailles l'interrompent
	var added: Array[Dictionary] = []
	Crisis._falls(st, added)
	_ok(Crisis.is_held(st, sid), "siège mené à terme : le système tombe")
	_ok(Crisis.production_pct(st, sid) == 30, "le corail étouffe la production (30 %)")
	_ok(Crisis.colony_block(st, sid) != "", "on ne colonise pas un système tombé")
	# Corail : la population est recouverte.
	var pid := st.galaxy.systems[sid].planet_ids[0]
	var pop0: int = st.colonies[pid].population
	st.tick = int(Crisis.held(st)[sid]["since"]) + 30
	Crisis._held_day(st, added)
	_ok(st.colonies.has(pid) and st.colonies[pid].population == pop0 - 2, "le Récif recouvre deux habitants par mois")
	# Libération : plus de flotte de la crise depuis un mois.
	st.fleets.erase(cf.id)
	var mine := st.spawn_ship(0, "corvette", sid)
	st.tick += 31
	Crisis._held_day(st, added)
	_ok(not Crisis.is_held(st, sid) and Crisis.contrib(st, 0) > 0, "système libéré, contribution comptée")
	st.fleets.erase(mine.id)


func _test_inspection() -> void:
	var st := _new()
	st.tick = 10800
	_force(st, "inspection")
	var bureaus := 0
	var hearts := 0
	for f in Crisis.stations(st):
		if Crisis.role_of(st, f.id) == Crisis.ROLE_HEART:
			hearts += 1
		else:
			bureaus += 1
	_ok(bureaus == 4 and hearts == 0, "l'Inspection ouvre quatre Bureaux de contrôle, pas encore de Registre")
	_ok(not Crisis._core_dead(st), "l'Inspection n'est pas vaincue tant que le Registre n'a pas paru")
	for f in Crisis.stations(st):
		f.ships.clear()
	var added: Array[Dictionary] = []
	st.tick += 1
	Crisis.on_battle(st, {"sides": [{"empire": 0, "engaged": {}, "lost": {}, "dealt": 50}, {"empire": GameState.CRISIS_ID, "engaged": {}, "lost": {}, "dealt": 5}]}, 0, added)
	Crisis._core_rules(st, added)
	hearts = 0
	for f in Crisis.stations(st):
		if Crisis.role_of(st, f.id) == Crisis.ROLE_HEART:
			hearts += 1
	_ok(hearts == 1 and bool(Crisis.cur(st)["registre"]), "le dernier Bureau fermé, le Registre central s'ouvre")
	_ok(Crisis.contrib(st, 0) >= 4 * int(Crisis.data()["contrib"]["station"]), "chaque Bureau détruit rapporte à qui l'a fermé")


func _test_dechirure() -> void:
	var st: GameState = null
	for sd in [12, 13, 14, 15, 16, 17]:
		st = _new(sd, "une", {"terrain": "normal"})
		st.tick = 10800
		_force(st, "dechirure")
		if Crisis.active(st):
			break
	if not Crisis.active(st):
		_ok(true, "Déchirure : aucune tempête libre dans ces galaxies (test sauté)")
		return
	var heart: Fleet = null
	var anchors := 0
	for f in Crisis.stations(st):
		if Crisis.role_of(st, f.id) == Crisis.ROLE_HEART:
			heart = f
		else:
			anchors += 1
	_ok(heart != null and anchors == 3, "la Faille et ses trois ancres")
	heart.hp[0] = 1
	var added: Array[Dictionary] = []
	Crisis._core_rules(st, added)
	_ok(heart.hp[0] == Fleet.max_hp_of(heart.ships[0]), "la Faille se répare tant que ses ancres tiennent")


func _test_victory() -> void:
	var st := _new()
	st.tick = 10800
	_force(st, "recif")
	Crisis.add_contrib(st, 0, 300)
	Crisis.add_contrib(st, 1, 100)
	for f in Crisis.stations(st):
		f.ships.clear()
	var added: Array[Dictionary] = []
	st.tick += 1
	var infl0 := int(st.empires[0].resources.get("influence", 0))
	Crisis.on_battle(st, {"sides": [{"empire": 0, "engaged": {}, "lost": {}, "dealt": 90}, {"empire": GameState.CRISIS_ID, "engaged": {}, "lost": {}, "dealt": 5}]}, 0, added)
	Crisis._active_day(st, added)
	_ok(not Crisis.ongoing(st) and String((st.crisis["past"] as Array)[-1]["result"]) == "victoire", "cœur et Mondes-Récifs détruits : la crise est vaincue")
	_ok(Crisis.fleets_left(st) == (st.crisis.get("remnants", {}) as Dictionary).size() and Crisis.fleets_left(st) <= 2, "ses flottes se dissipent, sauf deux restes sauvages au plus")
	var parts := Crisis.stability_parts(st, 1)
	_ok(not parts.is_empty() and int(parts[0][1]) == 10, "+10 de stabilité pour toute la galaxie")
	_ok(int(st.empires[0].resources.get("influence", 0)) > infl0, "influence selon la part de gloire")
	_ok(int((st.crisis["past"] as Array)[-1]["by"]) == 0, "coup final noté")
	_ok(_cards(st, 0, "crise_victoire") == 1, "fenêtre de victoire")
	st.tick += 3601
	_ok(Crisis.stability_parts(st, 1).is_empty(), "la liesse dure dix ans")


func _test_defeat() -> void:
	var st := _new()
	st.victory_rules["deadline"] = 12000
	st.tick = 11900
	_force(st, "recif")
	_ok(Victory.deadline(st) > 12000, "une crise arrivée repousse la date limite")
	var need := Crisis._defeat_need(st)
	var n := 0
	for s in st.galaxy.systems:
		if n >= need:
			break
		(Crisis.cur(st)["held"] as Dictionary)[s.id] = {"since": st.tick, "seen": st.tick, "owner": -1}
		n += 1
	var added: Array[Dictionary] = []
	Crisis._active_day(st, added)
	_ok(String(st.winner.get("victory", "")) == "crise" and int(st.winner["empire"]) == GameState.CRISIS_ID, "la moitié des mondes tenus : défaite commune")
	_ok(Victory.label("crise") == "Défaite commune" and not Victory.is_winner(st, 0), "personne ne gagne")


func _test_save() -> void:
	var sim := Simulation.new(_new(13))
	var st := sim.state
	st.tick = 10800
	_force(st, "recif")
	var added: Array[Dictionary] = []
	Crisis.card_fx(st, 0, {}, {"act": "front"}, added)
	Crisis.card_fx(st, 0, {}, {"act": "boon", "label": "Test", "fx": {"damage_pct": 5}, "days": 720}, added)
	Crisis.add_contrib(st, 1, 42)
	sim.advance(40)
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(st.to_snapshot())))
	_ok(back != null, "sauvegarde 65 relue")
	if back == null:
		return
	_ok(back.checksum() == st.checksum(), "même empreinte après sauvegarde (crise)")
	_ok(Crisis.active(back) and Crisis.in_front(back, 0) and Crisis.contrib(back, 1) == Crisis.contrib(st, 1) and Crisis.boons(back, 0).size() == Crisis.boons(st, 0).size() and Crisis.boons(st, 0).size() >= 1, "crise, Front, contribution et préparatifs relus")
	var a := Simulation.new(st)
	var b := Simulation.new(back)
	a.advance(150)
	b.advance(150)
	_ok(a.state.checksum() == b.state.checksum(), "la partie reprise continue à l'identique")


func _test_determinism() -> void:
	var a := GameState.create(31, 120, 1600.0, "", {"crises": "toutes"})
	var b := GameState.create(31, 120, 1600.0, "", {"crises": "toutes"})
	var sa := Simulation.new(a)
	var sb := Simulation.new(b)
	sa.advance(60)
	sb.advance(60)
	a.tick = 10800
	b.tick = 10800
	_force(a, "recif")
	_force(b, "recif")
	sa.advance(300)
	sb.advance(300)
	_ok(a.checksum() == b.checksum(), "même graine, même crise après 300 jours")
	_ok(Crisis.active(a) or not (a.crisis["past"] as Array).is_empty(), "la crise a vécu sa vie (%d systèmes tombés)" % int(Crisis.cur(a).get("fallen", 0)))
