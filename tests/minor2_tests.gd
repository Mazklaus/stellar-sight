extends RefCounted
## Tests des peuples mineurs, lot 2 (MinorsLife) : conscience et « se révéler » ; accords avec les
## pré-spatiaux ; programmes des spatiaux ; sujet ; disperser ; hostiles (guerre, raids, repaire) ;
## drames (astéroïde, guerre nucléaire, déclin) ; Avènement ; sécession en peuple libre ; pré-conscients
## et élévation ; sauvegarde 70. Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Peuples mineurs, vie…")
	_test_awareness()
	_test_accords()
	_test_programs()
	_test_subject()
	_test_disperse()
	_test_hostile()
	_test_dramas()
	_test_rise()
	_test_secession()
	_test_presapients()
	_test_save()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


func _new(seed_value := 11, mode := "normal", extra := {}) -> GameState:
	var o := {"ai_level": "", "minors": mode}
	o.merge(extra, true)
	return GameState.create(seed_value, 120, 1600.0, "vael", o)


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


func _met(st: GameState, id: int, eids: Array) -> void:
	var added: Array[Dictionary] = []
	for eid in eids:
		Minors.meet(st, id, int(eid), added)
		if Minors.is_pre(st, id):
			(Minors.get_m(st, id)["post"] as Dictionary)[int(eid)] = "discret"


func _test_awareness() -> void:
	var st := _new()
	var id := _first(st, "pre")
	var m := Minors.get_m(st, id)
	_ok(MinorsLife.aware_level(st, id) == 0 and MinorsLife.aware_label(st, id) == "Ignorants", "au départ : ignorants")
	_met(st, id, [0])
	(m["post"] as Dictionary)[0] = "ouvert"
	st.spawn_ship(0, "corvette", int(m["sid"]))
	_days(st, 30)
	_ok(int(m["aware"]) == 3, "flotte visible et poste ouvert : la conscience monte (+3)")
	m["aware"] = 30
	_ok(MinorsLife.aware_level(st, id) == 1, "25 : rumeurs")
	var slow := Minors.age_need(st, id)
	m["aware"] = 85
	_ok(Minors.age_need(st, id) < slow, "plus ils savent, plus leurs âges passent vite")
	m["aware"] = 0
	_ok(Minors.check_act(st, 0, "reveal", id, "", -1) == "", "se révéler possible avec un poste")
	Minors.act(st, 0, "reveal", id, "", -1, [])
	_ok(MinorsLife.revealed(st, id), "ils savent")


func _test_accords() -> void:
	var st := _new()
	var id := _first(st, "pre")
	var m := Minors.get_m(st, id)
	m["age"] = 2
	_met(st, id, [0])
	st.empires[0].resources["influence"] = 500
	_ok(Minors.check_act(st, 0, "accord", id, "trade", -1).contains("révéler"), "accords : il faut d'abord se révéler")
	Minors.act(st, 0, "reveal", id, "", -1, [])
	for k in ["trade", "tech", "guide"]:
		_ok(Minors.check_act(st, 0, "accord", id, k, -1) == "", "accord %s possible" % k)
		Minors.act(st, 0, "accord", id, k, -1, [])
	var e0 := int(st.empires[0].resources.get("energy", 0))
	var i0 := int(st.empires[0].resources["influence"])
	_days(st, 30)
	_ok(int(st.empires[0].resources.get("energy", 0)) == e0 + 3, "accord commercial : énergie 1 + âge par mois")
	_ok(int(st.empires[0].resources["influence"]) == i0 - 3, "chaque accord coûte 1 influence par mois")
	# Transfert ×3, doublé par le talent Raison du credo des Vael (lot 3, prop. 32).
	_ok(MinorsBridges.tech_x(st, 0) == 2, "les Vael (credo Raison) doublent le transfert de technologie")
	_ok(MinorsLife.age_mult(st, id) == 3 * MinorsBridges.tech_x(st, 0), "transfert de technologie : âges trois fois plus vite (×2 Raison) (obtenu ×%d)" % MinorsLife.age_mult(st, id))
	(m["acc"][0] as Dictionary)["guide"] = st.tick - 5 * 360
	_days(st, 30)
	_ok(String(m.get("credo", "")) == String(st.empires[0].faction()["species"]["credo"]), "Guidance : leur credo glisse vers le vôtre")
	_ok(String(st.get_empire(id).faction()["species"]["credo"]) == String(m["credo"]), "leur fiche d'espèce suit")
	Minors.act(st, 0, "accord", id, "trade", -1, [])
	_ok(not MinorsLife.has_accord(st, id, 0, "trade"), "on peut mettre fin à un accord")


func _test_programs() -> void:
	var st := _new()
	var id := -1
	for i in Minors.ids(st):
		if not Minors.is_pre(st, i) and Minors.gift_def(st, i).has("fx"):
			id = i
	_met(st, id, [0])
	var m := Minors.get_m(st, id)
	(m["fav"] as Dictionary)[0] = 30
	_ok(Minors.check_act(st, 0, "prog", id, "fonds", -1).contains("amitié"), "programmes : amitié requise")
	(m["fav"] as Dictionary)[0] = 80
	_days(st, 30)
	var e := st.empires[0]
	e.resources["energy"] = 1000
	var gfx: Dictionary = Minors.gift_def(st, id)["fx"]
	var key := String(gfx.keys()[0])
	var before := Research.fx_int(st, 0, key) if not gfx[key] is Dictionary else 0
	Minors.act(st, 0, "prog", id, "fonds", -1, [])
	_ok(int(e.resources["energy"]) == 850, "Fonds de développement : 150 énergie")
	if not gfx[key] is Dictionary:
		_ok(Research.fx_int(st, 0, key) == before + int(gfx[key]), "cadeau doublé pendant le Fonds")
	var nf := Fleets.empire_fleets(st, 0).size()
	Minors.act(st, 0, "prog", id, "escadre", -1, [])
	_ok(Fleets.empire_fleets(st, 0).size() == nf + 1, "Escadre étrangère : une flotte offerte")
	_ok(Minors.check_act(st, 0, "prog", id, "escadre", -1) != "", "pas d'escadre chaque mois")
	var c: Colony = st.colonies[int(m["planet"])]
	var p0 := c.population
	Minors.act(st, 0, "prog", id, "migration", -1, [])
	_ok(c.population < p0, "Migration choisie : des habitants partent")
	if Peoples.enabled(st):
		var found := false
		for pid in st.sorted_colony_ids():
			var x: Colony = st.colonies[pid]
			if x.owner == 0 and int(x.species.get(Minors.species_id(st, id), 0)) > 0:
				found = true
		_ok(found, "une nouvelle espèce dans votre mosaïque")


func _test_subject() -> void:
	var st := _new()
	var id := _first(st, "space")
	_met(st, id, [0, 1])
	var m := Minors.get_m(st, id)
	(m["fav"] as Dictionary)[0] = 90
	_days(st, 30)
	_ok(Minors.check_act(st, 0, "subject", id, "", -1) == "", "le suzerain peut en faire un sujet")
	Minors.act(st, 0, "subject", id, "", -1, [])
	(m["fav"] as Dictionary)[1] = 100
	(m["fav"] as Dictionary)[0] = 20
	var en := int(st.empires[0].resources.get("energy", 0))
	_days(st, 30)
	_ok(Minors.suzerain(st, id) == 0, "un sujet ne change pas de suzerain")
	_ok(int(st.empires[0].resources.get("energy", 0)) >= en + 3, "tribut du sujet")


func _test_disperse() -> void:
	var st := _new()
	var id := _first(st, "space")
	_met(st, id, [0])
	Minors.act(st, 0, "war", id, "", -1, [])
	var sid := Minors.system_of(st, id)
	var kind := Minors.kind_of(st, id)
	Combat.capture_system(st, sid, 0)
	var item: Dictionary = {}
	for it: Dictionary in Events.inbox(st, 0):
		if String(it["card"]) == "min_conquered_space":
			item = it
	_ok(not item.is_empty(), "conquête d'un spatial : garder ou raser")
	if item.is_empty():
		return
	var text := Events.fill(st, 0, item, String(Events.card("min_conquered_space")["text"]))
	_ok(not text.contains("{min"), "fenêtre remplie (%s)" % text.substr(0, 40))
	var r0 := st.empires[0].resources.duplicate()
	Events.choose(st, 0, int(item["id"]), 1, [])
	var gained := false
	for r in st.empires[0].resources:
		if int(st.empires[0].resources[r]) > int(r0.get(r, 0)):
			gained = true
	_ok(gained, "raser : butin selon l'orientation")
	_ok(not Minors.absorbed(st, 0).has(kind), "le peuple dispersé n'apporte pas son trait")


func _test_hostile() -> void:
	var st := _new()
	var id := _first(st, "space")
	var m := Minors.get_m(st, id)
	m["att"] = "hostile"
	_ok(Combat.at_war(st, id, 0), "un spatial hostile est en guerre avec qui n'a pas 20 de faveur")
	_met(st, id, [0])
	(m["fav"] as Dictionary)[0] = 25
	_ok(not Combat.at_war(st, id, 0), "à 20 de faveur, il cesse")
	(m["fav"] as Dictionary)[0] = 0
	# Raid : une colonie à 3 sauts au plus.
	var near := -1
	var jumps := FactionTraits.jumps_from(st.galaxy, int(m["sid"]))
	for s in st.galaxy.systems:
		if st.system_owner(s.id) < 0 and int(jumps.get(s.id, 999)) <= 2 and int(jumps.get(s.id, 999)) >= 1:
			for pid in s.planet_ids:
				if not st.colonies.has(pid):
					near = pid
					break
		if near >= 0:
			break
	if near >= 0:
		var c := Colony.new()
		c.planet_id = near
		c.owner = 0
		c.kind = Colony.KIND_COLONY
		c.population = 3
		st.add_colony(c)
		st.rebuild_ownership()
		var raided := false
		for i in 40:
			_days(st, 30)
			if not (m.get("raid", {}) as Dictionary).is_empty():
				raided = true
				break
		_ok(raided, "il lance un raid sur la colonie voisine")
	# Repaire : sans ami depuis cinq ans.
	var st2 := _new()
	var lairs0 := st2.lairs.size()
	for i in 12 * 25:
		_days(st2, 30)
		if st2.lairs.size() > lairs0:
			break
	_ok(st2.lairs.size() > lairs0, "peuples sans ami : un repaire pirate finit par naître")


func _test_dramas() -> void:
	var st := _new()
	var id := _first(st, "pre")
	var m := Minors.get_m(st, id)
	m["age"] = 3
	_met(st, id, [0])
	m["asteroid"] = {"until": st.tick + 45, "saved": false}
	Events.push(st, 0, "min_asteroid", {"min": id, "system": int(m["sid"])}, [])
	var item: Dictionary = {}
	for it: Dictionary in Events.inbox(st, 0):
		if String(it["card"]) == "min_asteroid":
			item = it
	st.empires[0].resources["energy"] = 500
	Events.choose(st, 0, int(item["id"]), 0, [])
	_ok(bool(m["asteroid"]["saved"]) and int(m["aware"]) >= 20, "astéroïde détruit : peuple sauvé, la conscience monte")
	_days(st, 60)
	_ok(int(m["age"]) == 3, "sauvés : ils gardent leur âge")
	m["asteroid"] = {"until": st.tick + 10, "saved": false}
	_days(st, 30)
	_ok(int(m["age"]) == 1, "laissé faire : deux âges perdus")
	# Déclin sous le siège.
	var sp := _first(st, "space")
	var sm := Minors.get_m(st, sp)
	st.sieges[int(sm["sid"])] = {"by": 0}
	_days(st, 31)
	_ok(MinorsLife.declining(st, sp), "un spatial assiégé entre en déclin")
	_met(st, sp, [1])
	st.empires[1].resources["influence"] = 500
	_ok(Minors.check_act(st, 1, "integrate", sp, "", -1) == "" and Minors.integration_cost(st, sp, 1) == 75, "en déclin : tout empire peut l'intégrer à moitié prix")
	st.sieges.erase(int(sm["sid"]))


func _test_rise() -> void:
	var st := _new()
	var id := _first(st, "pre")
	var m := Minors.get_m(st, id)
	_met(st, id, [0])
	Minors.act(st, 0, "reveal", id, "", -1, [])
	st.empires[0].resources["influence"] = 500
	Minors.act(st, 0, "accord", id, "tech", -1, [])
	m["age"] = 5
	m["age_days"] = 99999
	_days(st, 30)
	_ok(not Minors.is_pre(st, id) and Minors.power(st, id) > 0, "Avènement : il devient un spatial, avec une flotte")
	_ok(Minors.suzerain(st, id) == 0 and Minors.fav(st, id, 0) >= 99, "sous transfert de technologie : né protégé du donneur")
	(m["fav"] as Dictionary)[0] = 10
	_met(st, id, [1])
	(m["fav"] as Dictionary)[1] = 100
	_days(st, 30)
	_ok(Minors.suzerain(st, id) == 0, "suzerain verrouillé")


func _test_secession() -> void:
	var st := _new()
	var e := st.empires[0]
	var sid := -1
	for pid in st.sorted_colony_ids():
		var c: Colony = st.colonies[pid]
		if c.owner == 0 and pid != e.capital_planet:
			sid = st.galaxy.get_planet(pid).system_id
	if sid < 0:
		var cap_sys := FactionTraits.capital_system(st, 0)
		for nb in st.galaxy.systems[cap_sys].neighbors:
			if st.system_owner(int(nb)) < 0:
				for pid in st.galaxy.systems[int(nb)].planet_ids:
					if not st.colonies.has(pid) and not (GameData.planet_type(st.galaxy.get_planet(pid).type).get("pop_yields", {}) as Dictionary).is_empty():
						var c2 := Colony.new()
						c2.planet_id = pid
						c2.owner = 0
						c2.kind = Colony.KIND_COLONY
						c2.population = 4
						st.add_colony(c2)
						sid = int(nb)
						break
			if sid >= 0:
				break
	st.rebuild_ownership()
	_ok(sid >= 0, "une colonie à faire sécession")
	if sid < 0:
		return
	var added: Array[Dictionary] = []
	StabilitySystem.secede(st, sid, 0, added)
	var id := Minors.at_system(st, sid)
	_ok(id >= 0, "sécession : un peuple mineur à la place des Sans-Bannière")
	if id < 0:
		return
	_ok(Minors.name_of(st, id).begins_with("Libres de"), "nommé d'après son système (%s)" % Minors.name_of(st, id))
	_ok(Minors.species_id(st, id) == e.faction_id, "de l'espèce qui y vivait")
	_ok(not Combat.at_war(st, id, 1), "neutre et courtisable")
	_ok(Minors.fav(st, id, 0) == 0 and Minors.grudge(st, id, 0), "l'ancien maître démarre à 0 avec une rancune")


func _test_presapients() -> void:
	var st := _new()
	var pres: Dictionary = st.minors.get("pres", {})
	_ok(not pres.is_empty(), "quelques pré-conscients dans la galaxie (%d)" % pres.size())
	if pres.is_empty():
		return
	var pid := int(pres.keys()[0])
	var c := Colony.new()
	c.planet_id = pid
	c.owner = 0
	c.kind = Colony.KIND_COLONY
	c.population = 3
	st.add_colony(c)
	st.rebuild_ownership()
	_ok(MinorsLife.pres_of(st, 0) == [pid], "pré-conscients sur votre monde")
	st.empires[0].resources["knowledge"] = 1000
	_ok(Minors.check_act(st, 0, "elevate", -1, "", pid).contains("Élévation"), "élévation : il faut la technologie Élévation")
	st.empires[0].techs["genetique"] = true
	_ok(Minors.check_act(st, 0, "elevate", -1, "", pid) != "", "élévation : la Génétique appliquée ne suffit plus")
	Research.grant(st, 0, ["elevation"])
	_ok(Minors.check_act(st, 0, "elevate", -1, "", pid) == "", "élévation possible")
	Minors.act(st, 0, "elevate", -1, "", pid, [])
	_ok(int(st.empires[0].resources["knowledge"]) == 700, "élévation : 300 savoir")
	var p0 := c.population
	st.tick += 1800
	_days(st, 30)
	_ok(c.population == p0 + 2 and MinorsLife.pres_kind(st, pid) == "", "élévation achevée : une espèce de plus dans la mosaïque")
	if Peoples.enabled(st):
		_ok(c.species.size() >= 1, "leur espèce est comptée")


func _test_save() -> void:
	var sim := Simulation.new(_new(17, "beaucoup", {"ai_level": "normal"}))
	var st := sim.state
	sim.advance(1080)
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(st.to_snapshot())))
	_ok(back != null and back.checksum() == st.checksum(), "sauvegarde 70 relue, même empreinte")
	if back == null:
		return
	var a := Simulation.new(st)
	var b := Simulation.new(back)
	a.advance(360)
	b.advance(360)
	_ok(a.state.checksum() == b.state.checksum(), "la partie reprise continue à l'identique")
