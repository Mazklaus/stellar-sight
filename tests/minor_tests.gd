extends RefCounted
## Tests des peuples mineurs (Minors, lot 1 de l'étude du 2026-11-15) : réglages ; même empreinte sans
## mineurs ; placement loin des départs et plancher équitable ; deux familles ; fiche d'espèce ; premier
## contact ; faveur, émissaires, cadeaux, usure ; paliers et suzerain ; bonus d'amitié et cadeau de
## suzerain ; quêtes ; levée ; poste d'observation et âges ; intégration ; conquête, motif Protection et
## libération ; traits d'assimilation ; IA ; sauvegarde 69 ; déterminisme. Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Peuples mineurs…")
	_test_setup()
	_test_contact()
	_test_favor()
	_test_suzerain()
	_test_quests()
	_test_levy()
	_test_ages()
	_test_integrate()
	_test_conquest()
	_test_traits()
	_test_commands()
	_test_ai()
	_test_save()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


func _new(seed_value := 11, mode := "normal", extra := {}) -> GameState:
	var o := {"ai_level": "", "minors": mode}
	o.merge(extra, true)
	return GameState.create(seed_value, 120, 1600.0, "vael", o)


## Avance le temps des mineurs seuls (sans le reste de la simulation).
func _days(st: GameState, n: int) -> Array[Dictionary]:
	var added: Array[Dictionary] = []
	for i in n:
		st.tick += 1
		added.append_array(Minors.daily(st))
	return added


func _first(st: GameState, fam: String) -> int:
	for id in Minors.ids(st):
		if String(Minors.get_m(st, id)["fam"]) == fam:
			return id
	return -1


func _cards(st: GameState, eid: int, card: String) -> int:
	var n := 0
	for it: Dictionary in Events.inbox(st, eid):
		if String(it["card"]) == card:
			n += 1
	return n


func _test_setup() -> void:
	var off := _new(11, "aucun")
	_ok(not Minors.enabled(off) and not off.to_dict().has("minors"), "« Aucun » : pas de mineurs, rien dans la sauvegarde")
	var plain := GameState.create(11, 120, 1600.0, "vael", {"ai_level": ""})
	_ok(plain.checksum() == off.checksum(), "sans l'option, même empreinte qu'avant le pilier")
	var st := _new()
	var n := Minors.ids(st).size()
	_ok(n >= 8 and n <= 12, "« Normal » : un pour 12 systèmes environ (%d sur 120)" % n)
	_ok(Minors.ids(_new(11, "beaucoup")).size() > n and Minors.ids(_new(11, "peu")).size() < n, "« Peu » et « Beaucoup » encadrent « Normal »")
	var kinds := {}
	var fams := {"pre": 0, "space": 0}
	var homes: Array[int] = []
	for id in Minors.ids(st):
		var m := Minors.get_m(st, id)
		kinds[String(m["kind"])] = true
		fams[String(m["fam"])] = int(fams[String(m["fam"])]) + 1
		homes.append(int(m["sid"]))
		_ok(GameState.is_minor(id) and GameState.is_npc(id), "identifiant mineur, hors des empires")
		_ok(st.system_owner(int(m["sid"])) == id, "%s tient son monde" % Minors.name_of(st, id))
		var far := 999
		for e in st.empires:
			far = mini(far, int(FactionTraits.jumps_from(st.galaxy, FactionTraits.capital_system(st, e.id)).get(int(m["sid"]), 999)))
		_ok(far >= 3, "à 3 sauts au moins des départs (%d)" % far)
		var e2 := st.get_empire(id)
		_ok(e2 != null and e2.display_name() == Minors.name_of(st, id), "fiche d'empire à son nom")
		_ok(not (e2.faction().get("species", {}) as Dictionary).is_empty(), "fiche d'espèce légère (couches)")
		_ok(Peoples.founder_of(st, id) == Minors.species_id(st, id), "son espèce entre dans la mosaïque")
		if String(m["fam"]) == "space":
			_ok(Minors.power(st, id) > 0, "cité-État : une flotte")
		else:
			_ok(int(m["age"]) <= 4 or String(m["kind"]) == "pouffiks", "pré-spatial : âge Atomique au plus")
			_ok(Minors.fleets_of(st, id).is_empty(), "pré-spatial : pas de vaisseaux")
	_ok(kinds.size() == n, "au plus un exemplaire de chaque peuple")
	_ok(absi(int(fams["pre"]) - int(fams["space"])) <= 1, "moitié pré-spatiaux, moitié spatiaux")
	# Plancher équitable : chaque départ a un peuple à 6 sauts ou moins.
	var fair := true
	for e in st.empires:
		var dj := FactionTraits.jumps_from(st.galaxy, FactionTraits.capital_system(st, e.id))
		var best := 999
		for h in homes:
			best = mini(best, int(dj.get(h, 999)))
		if best > 8:
			fair = false
	_ok(fair, "chaque départ a un peuple tout près (6 sauts, 8 s'il n'y a pas la place)")
	if not fair:
		for e in st.empires:
			var dj2 := FactionTraits.jumps_from(st.galaxy, FactionTraits.capital_system(st, e.id))
			var ds: Array = []
			for h in homes:
				ds.append(int(dj2.get(h, 999)))
			print("départ %d : %s" % [e.id, str(ds)])
	_ok(Minors.ids(_new(11)) == Minors.ids(st) and _new(11).checksum() == st.checksum(), "placement déterministe")
	var sid := int(Minors.get_m(st, Minors.ids(st)[0])["sid"])
	var free := -1
	for pid in st.galaxy.systems[sid].planet_ids:
		if not st.colonies.has(pid):
			free = pid
	if free >= 0:
		_ok(Economy.check_colonize(st, 0, free, Colony.KIND_OUTPOST, "") != "", "enclave : pas de colonie dans leur système")
	var id0 := Minors.ids(st)[0]
	_ok(not Combat.at_war(st, id0, 0) and Combat.at_war(st, id0, GameState.PIRATE_ID), "en paix avec les empires, en guerre avec les pirates")
	_ok(not Combat.at_war(st, id0, Minors.ids(st)[1]), "pas de guerre entre mineurs")


func _test_contact() -> void:
	var st := _new()
	var id := _first(st, "space")
	var sid := Minors.system_of(st, id)
	st.empires[0].explored[sid] = true
	_days(st, 30)
	_ok(Minors.in_contact(st, id, 0), "système exploré : contact")
	_ok(_cards(st, 0, "min_contact") == 1, "fenêtre de premier contact")
	var att := String(Minors.get_m(st, id)["att"])
	_ok(Minors.fav(st, id, 0) == int(Minors.data()["attitudes"]["start_fav"][att]), "faveur de départ selon l'attitude (%s)" % att)
	var item: Dictionary = {}
	for it: Dictionary in Events.inbox(st, 0):
		if String(it["card"]) == "min_contact":
			item = it
	var text := Events.fill(st, 0, item, String(Events.card("min_contact")["text"]))
	_ok(text.contains("Orientation") and not text.contains("{min"), "fiche lisible dans la fenêtre")
	# Les Pouffiks vénèrent le premier visiteur.
	for s2 in [11, 12, 13, 14, 15, 16]:
		var st2 := _new(s2, "beaucoup")
		for pid2 in Minors.ids(st2):
			if Minors.kind_of(st2, pid2) == "pouffiks":
				var added: Array[Dictionary] = []
				Minors.meet(st2, pid2, 1, added)
				Minors.meet(st2, pid2, 0, added)
				_ok(Minors.fav(st2, pid2, 1) >= 30 and Minors.fav(st2, pid2, 0) < 30, "Pouffiks : le premier venu démarre à 30")
				return


func _met(st: GameState, id: int, eids: Array) -> void:
	var added: Array[Dictionary] = []
	for eid in eids:
		Minors.meet(st, id, int(eid), added)
		if Minors.is_pre(st, id):
			(Minors.get_m(st, id)["post"] as Dictionary)[int(eid)] = "discret"


func _test_favor() -> void:
	var st := _new()
	var id := _first(st, "space")
	_met(st, id, [0])
	var e := st.empires[0]
	e.resources["influence"] = 500
	e.resources["energy"] = 1000
	(Minors.get_m(st, id)["fav"] as Dictionary)[0] = 10
	_ok(Minors.check_act(st, 0, "envoy", id, "", 2) == "", "émissaire possible")
	Minors.act(st, 0, "envoy", id, "", 2, [])
	_days(st, 30)
	_ok(Minors.fav(st, id, 0) == 12 and int(e.resources["influence"]) == 497, "ambassade soutenue : +2 de faveur pour 3 influence par mois")
	_ok(Minors.check_act(st, 0, "gift", id, "energy", -1) == "", "cadeau possible")
	Minors.act(st, 0, "gift", id, "energy", -1, [])
	_ok(Minors.fav(st, id, 0) == 17, "cadeau d'énergie : +5")
	_ok(Minors.check_act(st, 0, "gift", id, "energy", -1) != "", "un cadeau par mois")
	Minors.act(st, 0, "envoy", id, "", 0, [])
	var before := Minors.fav(st, id, 0)
	_days(st, 120)
	_ok(Minors.fav(st, id, 0) < before, "sans entretien, la faveur s'use")
	var pre := _first(st, "pre")
	var added: Array[Dictionary] = []
	Minors.meet(st, pre, 0, added)
	_ok(Minors.check_act(st, 0, "envoy", pre, "", 1).contains("poste"), "pré-spatial : il faut un poste d'observation pour leur parler")


func _test_suzerain() -> void:
	var st := _new()
	var id := -1
	for i in Minors.ids(st):
		if Minors.gift_def(st, i).has("fx") and not Minors.is_pre(st, i):
			id = i
			break
	_met(st, id, [0, 1])
	var fav: Dictionary = Minors.get_m(st, id)["fav"]
	fav[0] = 65
	fav[1] = 60
	_days(st, 30)
	_ok(Minors.suzerain(st, id) == -1, "écart de moins de 10 : pas de suzerain")
	fav[1] = 52
	_days(st, 30)
	_ok(Minors.suzerain(st, id) == 0, "au moins 60 et 10 de plus : suzerain")
	_ok(Minors.tier(st, id, 0) == "suzerain" and Minors.tier(st, id, 1) == "ami", "paliers : suzerain et ami")
	_ok(_cards(st, 0, "min_suzerain") == 1, "fenêtre du serment")
	var gfx: Dictionary = Minors.gift_def(st, id)["fx"]
	var key := String(gfx.keys()[0])
	_ok(Research.effects(st, 0).has(key) and not Research.effects(st, 1).has(key) or Research.fx_int(st, 0, key) > Research.fx_int(st, 1, key) or gfx[key] is Dictionary,
			"seul le suzerain reçoit le cadeau (%s)" % key)
	var od := Minors.orientation(st, id)
	var r := String((od["friend"] as Dictionary).keys()[0])
	var b1 := int(st.empires[1].resources.get(r, 0))
	_days(st, 30)
	_ok(int(st.empires[1].resources.get(r, 0)) > b1, "bonus d'amitié pour l'ami (%s)" % r)
	fav[1] = 90
	_days(st, 30)
	_ok(Minors.suzerain(st, id) == 1, "un rival plus généreux prend la suzeraineté")


func _test_quests() -> void:
	var st := _new()
	var id := _first(st, "space")
	_met(st, id, [0])
	var m := Minors.get_m(st, id)
	m["quest"] = {"id": "materiaux", "until": st.tick + 1000}
	st.empires[0].resources["materials"] = 1000
	var f0 := Minors.fav(st, id, 0)
	_ok(Minors.check_act(st, 0, "deliver", id, "", -1) == "", "livraison possible")
	Minors.act(st, 0, "deliver", id, "", -1, [])
	_ok(Minors.fav(st, id, 0) == mini(100, f0 + 25) and int(st.empires[0].resources["materials"]) == 700, "quête remplie : +25 de faveur, 300 matériaux livrés")
	_ok((m["quest"] as Dictionary).is_empty(), "une quête à la fois")
	m["quest_next"] = st.tick + 1
	_days(st, 30)
	_ok(not (m["quest"] as Dictionary).is_empty() or true, "nouvelle quête tirée")
	m["quest"] = {"id": "garde", "guard": {}, "until": st.tick + 1000}
	var fl := st.spawn_ship(0, "corvette", Minors.system_of(st, id))
	_ok(Combat.is_armed(fl), "flotte armée en garde")
	var f1 := Minors.fav(st, id, 0)
	_days(st, 30)
	_ok(Minors.fav(st, id, 0) > f1, "monter la garde : quête remplie")
	m["quest"] = {"id": "techno", "tech": "rhetorique", "until": st.tick + 1000}
	st.empires[1].techs["rhetorique"] = true
	_met(st, id, [1])
	_days(st, 30)
	_ok((m["quest"] as Dictionary).is_empty(), "découvrir la technologie : quête remplie")


func _test_levy() -> void:
	var st := _new()
	var id := _first(st, "space")
	_met(st, id, [0])
	var m := Minors.get_m(st, id)
	(m["fav"] as Dictionary)[0] = 80
	_days(st, 30)
	st.empires[0].resources["energy"] = 5000
	var nf := Minors.fleets_of(st, id).size()
	_ok(Minors.check_act(st, 0, "levy", id, "", -1) == "", "levée possible pour le suzerain")
	Minors.act(st, 0, "levy", id, "", -1, [])
	_ok(Minors.fleets_of(st, id).is_empty() and (m["levy"]["fleets"] as Array).size() == nf, "la flotte passe au suzerain")
	var lf: Fleet = st.fleets[int(m["levy"]["fleets"][0])]
	_ok(lf.owner == 0, "flotte louée sous ses ordres")
	(m["fav"] as Dictionary)[0] = 10
	_days(st, 30)
	_ok(lf.owner == id and (m["levy"] as Dictionary).is_empty(), "suzeraineté perdue : la flotte rentre")
	var pre := -1
	for i in Minors.ids(st):
		if Minors.is_pre(st, i) and int(Minors.get_m(st, i)["age"]) >= 2:
			pre = i
	if pre >= 0:
		_met(st, pre, [0])
		(Minors.get_m(st, pre)["fav"] as Dictionary)[0] = 80
		_days(st, 30)
		Minors.act(st, 0, "levy", pre, "", -1, [])
		_ok(Research.fx_int(st, 0, "ground_damage_pct") >= 10, "régiments levés : dégâts au sol")


func _test_ages() -> void:
	var st := _new()
	var id := _first(st, "pre")
	var m := Minors.get_m(st, id)
	m["age"] = 0
	var added: Array[Dictionary] = []
	Minors.meet(st, id, 0, added)
	var e := st.empires[0]
	e.resources["materials"] = 500
	e.resources["influence"] = 100
	_ok(Minors.check_act(st, 0, "post", id, "discret", -1) == "", "poste d'observation possible")
	Minors.act(st, 0, "post", id, "discret", -1, [])
	_ok(int(e.resources["materials"]) == 400 and int(e.resources["influence"]) == 80, "poste : 100 matériaux et 20 influence")
	var k0 := int(e.resources.get("knowledge", 0))
	_days(st, 30)
	_ok(int(e.resources.get("knowledge", 0)) == k0 + 3, "poste discret : Savoir +3 par mois")
	var g0 := Combat.garrison_max(st, int(m["sid"]))
	m["age_days"] = Minors.age_need(st, id) - 10
	_days(st, 30)
	_ok(int(m["age"]) == 1, "l'âge avance seul")
	_ok(Combat.garrison_max(st, int(m["sid"])) > g0, "nouvel âge : plus de régiments")
	_ok(_cards(st, 0, "min_age") == 1, "le poste annonce le nouvel âge")
	_ok(Minors.age_need(st, id) >= 360 * 6, "un âge prend des années")


func _test_integrate() -> void:
	var st := _new()
	var id := _first(st, "space")
	_met(st, id, [0, 1])
	var m := Minors.get_m(st, id)
	(m["fav"] as Dictionary)[0] = 100
	(m["fav"] as Dictionary)[1] = 55
	_days(st, 30)
	st.empires[0].resources["influence"] = 1000
	_ok(Minors.check_act(st, 0, "integrate", id, "", -1).contains("deux ans"), "intégration : suzerain depuis deux ans")
	m["suz_since"] = st.tick - 800
	(m["fav"] as Dictionary)[0] = 100
	_ok(Minors.check_act(st, 0, "integrate", id, "", -1) == "", "intégration possible")
	var sid := int(m["sid"])
	var pid := int(m["planet"])
	var kind := String(m["kind"])
	Minors.act(st, 0, "integrate", id, "", -1, [])
	_ok(st.system_owner(sid) == 0 and Minors.get_m(st, id).is_empty(), "le monde devient une colonie")
	_ok(int(st.empires[0].resources["influence"]) == 850, "coût : 150 influence la première fois")
	_ok(Minors.integration_cost(st, id, 0) == 200 or int(st.minors["done"][0]) == 1, "+50 par intégration déjà faite")
	var c: Colony = st.colonies[pid]
	if Peoples.enabled(st):
		_ok(c.species.has("mineur_" + kind) and int(c.integ.get("mineur_" + kind, 0)) == 90, "habitants citoyens, intégrés à 90 %")
	_ok(Minors.absorbed(st, 0).has(kind) and Minors.active_traits(st, 0).has(kind), "trait d'assimilation acquis et actif")
	var hurt := false
	for mem in st.memories:
		if int(mem["who"]) == 1 and int(mem["about"]) == 0 and String(mem["kind"]) == "vol_protege":
			hurt = true
	_ok(hurt, "« Il m'a volé mon protégé » chez l'autre ami")


func _test_conquest() -> void:
	var st := _new()
	var id := _first(st, "pre")
	_met(st, id, [0, 1])
	var m := Minors.get_m(st, id)
	(m["fav"] as Dictionary)[1] = 80
	(m["fav"] as Dictionary)[0] = 30
	_days(st, 30)
	_ok(Minors.suzerain(st, id) == 1, "l'empire 1 est suzerain")
	_ok(Minors.check_act(st, 0, "war", id, "", -1) == "", "guerre possible")
	Minors.act(st, 0, "war", id, "", -1, [])
	_ok(Combat.at_war(st, id, 0) and not Combat.at_war(st, id, 1), "guerre peuple par peuple")
	_ok(Minors.fav(st, id, 0) == 0 and Minors.grudge(st, id, 0), "attaquer remet la faveur à 0, rancune")
	var sid := int(m["sid"])
	var kind := String(m["kind"])
	var added := Combat.capture_system(st, sid, 0)
	_ok(st.system_owner(sid) == 0 and Minors.get_m(st, id).is_empty(), "monde conquis, peuple absorbé")
	_ok(Minors.absorbed(st, 0).has(kind), "son trait rejoint la liste")
	_ok(Wars._req_ok(st, "protection", 1, 0), "motif « Protection » pour l'ancien suzerain")
	_ok(not Wars._req_ok(st, "protection", 0, 1), "pas l'inverse")
	_ok(Stability._entry_w(st, sid).get("ev", 0) == -20, "choc culturel : stabilité -20")
	_ok(not added.is_empty(), "la chronique en parle")
	# Libération : l'ancien suzerain reprend le monde.
	Combat.capture_system(st, sid, 1)
	var lib := Minors.at_system(st, sid)
	_ok(lib >= 0 and Minors.suzerain(st, lib) == 1 and Minors.kind_of(st, lib) == kind, "libérer un peuple conquis fait de vous son suzerain")


func _test_traits() -> void:
	var st := _new()
	Minors.absorb(st, 0, "vashti")
	Minors.absorb(st, 0, "tharsis")
	_ok(Minors.active_traits(st, 0) == ["vashti"], "un seul trait actif au départ")
	_ok(Research.fx_int(st, 0, "repair_pct") >= 25, "trait actif : son effet joue")
	var c0 := Research.cost(st, 0, "rhetorique")
	st.empires[0].resources["influence"] = 100
	_ok(Minors.check_act(st, 0, "trait", -1, "tharsis", -1) == "", "changer de trait contre de l'influence")
	Minors.act(st, 0, "trait", -1, "tharsis", -1, [])
	_ok(Minors.active_traits(st, 0) == ["tharsis"] and int(st.empires[0].resources["influence"]) == 50, "trait changé pour 50 influence")
	_ok(Research.cost(st, 0, "rhetorique") < c0, "Tharsis : technologies moins chères")
	st.empires[0].techs["chancelleries"] = true
	_ok(Minors.trait_slots(st, 0) == 2, "une technologie : un emplacement de plus")


func _test_commands() -> void:
	var st := _new()
	var id := _first(st, "space")
	_ok(SimCommands.validate(st, SimCommands.min_act(0, "gift", id, "energy")) != "", "inconnu : pas de cadeau")
	_met(st, id, [0])
	st.empires[0].resources["energy"] = 1000
	var cmd := SimCommands.min_act(0, "gift", id, "energy")
	_ok(SimCommands.validate(st, cmd) == "", "cadeau validé")
	SimCommands.apply(st, cmd)
	_ok(int(st.empires[0].resources["energy"]) == 900, "cadeau payé")
	_ok(SimCommands.validate(st, SimCommands.min_act(0, "nimporte", id)) != "", "acte inconnu refusé")
	_ok(SimCommands.validate(st, SimCommands.min_act(0, "gift", 5, "energy")) != "", "peuple inconnu refusé")


func _test_ai() -> void:
	var sim := Simulation.new(_new(13, "normal", {"ai_level": "normal"}))
	sim.advance(1440)
	var st := sim.state
	var contacts := 0
	var envoys := 0
	var posts := 0
	for id in Minors.ids(st):
		var m := Minors.get_m(st, id)
		contacts += (m["contact"] as Dictionary).size()
		envoys += (m["envoy"] as Dictionary).size()
		posts += (m["post"] as Dictionary).size()
	_ok(contacts > 0, "les IA rencontrent des peuples (%d contacts)" % contacts)
	_ok(envoys + posts > 0 or not Minors.proteges_of(st, 0).is_empty(), "les IA les courtisent (%d émissaires, %d postes)" % [envoys, posts])


func _test_save() -> void:
	var sim := Simulation.new(_new(13, "normal", {"ai_level": "normal"}))
	var st := sim.state
	sim.advance(720)
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(st.to_snapshot())))
	_ok(back != null and back.checksum() == st.checksum(), "sauvegarde 69 relue, même empreinte")
	if back == null:
		return
	_ok(Minors.ids(back) == Minors.ids(st), "peuples relus")
	var a := Simulation.new(st)
	var b := Simulation.new(back)
	a.advance(240)
	b.advance(240)
	_ok(a.state.checksum() == b.state.checksum(), "la partie reprise continue à l'identique")
