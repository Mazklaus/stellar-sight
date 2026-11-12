extends RefCounted
## Tests des fléaux errants (Plagues, lot 3 des créatures) : nombre et dates selon la densité, le
## réglage et la taille de la galaxie ; naissance (Spectre et sa couleur, Grande Migration) ; faiblesse
## du Spectre sous sa couleur ; festin (population, colonie rayée, jamais une capitale) ; maraude d'une
## colonie à l'autre ; départ au bout d'un an ; Triomphe partagé selon les dégâts ; Appât (fléau ou
## troupeau) ; IA ; sauvegarde 32 ; déterminisme. Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Fléaux errants…")
	_test_setup()
	_test_spawn()
	_test_eat()
	_test_roam()
	_test_leave()
	_test_reward()
	_test_bait()
	_test_ai()
	_test_save()
	_test_determinism()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


func _new(seed_value := 11, density := "normales", extra := {}) -> GameState:
	var o := {"ai_level": "", "creatures": density}
	o.merge(extra, true)
	return GameState.create(seed_value, 150, 1800.0, "vael", o)


## Une colonie (hors capitale) de l'empire dans un système libre, à `min_j` sauts au moins de sa capitale.
func _colony(st: GameState, owner: int, min_j := 2, pop := 6) -> int:
	var cap := FactionTraits.capital_system(st, owner)
	var jumps := FactionTraits.jumps_from(st.galaxy, cap)
	for s in st.galaxy.systems:
		if st.system_owner(s.id) < 0 and s.planet_ids.size() > 0 and int(jumps.get(s.id, 99)) >= min_j and int(jumps.get(s.id, 99)) <= 5 \
				and Fleets.fleets_at(st, s.id).is_empty() and not Fauna.nests(st).has(s.id) and Guardians.awake_at(st, s.id) == "":
			var c := Colony.new()
			c.planet_id = s.planet_ids[0]
			c.owner = owner
			c.kind = Colony.KIND_COLONY
			c.population = pop
			st.add_colony(c)
			return s.id
	return -1


func _test_setup() -> void:
	var st := _new()
	var pl := Plagues.plan(st)
	_ok(pl.size() == 1 and int(pl[0][0]) >= int(Plagues.data()["first_day"]), "Normales, 150 systèmes : un fléau prévu, pas avant l'an 15 (jour %s)" % (str(pl[0][0]) if not pl.is_empty() else "-"))
	_ok(Plagues.plan(_new(11, "aucune")).is_empty(), "sans créatures, pas de fléau")
	_ok(Plagues.plan(_new(11, "normales", {"plagues": false})).is_empty(), "réglage « Fléaux errants » décoché : aucun")
	var two := Plagues.plan(_new(11, "grouillantes"))
	_ok(two.size() == 2 and String(two[0][1]) != String(two[1][1]) and int(two[1][0]) - int(two[0][0]) >= int(Plagues.data()["gap_days"]), "Grouillantes : deux fléaux différents, à deux ans d'écart au moins")
	var big := GameState.create(11, 240, 2600.0, "vael", {"ai_level": "", "creatures": "normales"})
	_ok(Plagues.plan(big).size() == 2, "grande galaxie : un fléau de plus")


func _test_spawn() -> void:
	var st := _new()
	var added: Array[Dictionary] = []
	var pid := Plagues._spawn(st, "spectre", added)
	_ok(pid >= 0 and Plagues.alive(st).has(pid), "le Spectre des pulsars se lève")
	var f := Plagues.fleet_of(st, pid)
	var p: Dictionary = Plagues.list(st)[pid]
	_ok(f != null and f.owner == GameState.FAUNA_ID and st.system_owner(f.system_id) < 0, "une flotte de la Faune, née dans un système libre")
	_ok(String(p["star"]) != "", "il porte une couleur d'étoile (%s)" % p["star"])
	var pw := Combat.fleet_power(f)
	_ok(pw >= 600 and pw <= 1400, "un fléau demande une vraie flotte (puissance %d)" % pw)
	_ok(not added.is_empty() and String(added[0]["text"]).contains("fléau"), "toute la galaxie l'apprend")
	_ok(Fauna.hostile(st, f, 0) and Plagues.of_fleet(st, f) == pid, "hostile à tous")
	var same := -1
	var other := -1
	for s in st.galaxy.systems:
		if s.star_type == String(p["star"]) and same < 0:
			same = s.id
		elif s.star_type != String(p["star"]) and other < 0:
			other = s.id
	_ok(Plagues.damage_pct(st, f, same) == int(Plagues.kind_def("spectre")["weak_pct"]) and Plagues.damage_pct(st, f, other) == 0, "affaibli de moitié sous sa couleur, pas ailleurs")
	var mig := Plagues._spawn(st, "migration", added)
	var mf := Plagues.fleet_of(st, mig)
	_ok(mf != null and Fauna.species_of_unit(mf.ships[0]) == "beliers" and Combat.fleet_power(mf) >= 4 * Fauna.species_power("beliers"), "la Grande Migration : des Béliers fous, quatre fois plus robustes")


func _test_eat() -> void:
	var st := _new()
	var sid := _colony(st, 0, 2, 6)
	var pid: int = st.galaxy.systems[sid].planet_ids[0]
	var added: Array[Dictionary] = []
	_ok(Plagues.eat(st, sid, 3, -20, 360, "Le Spectre", added), "le fléau se sert dans une colonie")
	_ok((st.colonies[pid] as Colony).population == 3, "elle perd de la population")
	Plagues.eat(st, sid, 3, -20, 360, "Le Spectre", added)
	_ok(not st.colonies.has(pid) and st.system_owner(sid) < 0, "une colonie vidée est rayée de la carte")
	var cap := FactionTraits.capital_system(st, 0)
	var cpop := (st.colonies[st.get_empire(0).capital_planet] as Colony).population
	Plagues.eat(st, cap, 3, -20, 360, "Le Spectre", added)
	_ok((st.colonies[st.get_empire(0).capital_planet] as Colony).population == cpop, "jamais une capitale")
	_ok(not Plagues._prey_systems(st).has(cap), "les capitales ne sont pas des proies")


func _test_roam() -> void:
	var sim := Simulation.new(_new(19))
	var st := sim.state
	_colony(st, 0, 2, 8)
	_colony(st, 1, 2, 8)
	var added: Array[Dictionary] = []
	var pid := Plagues._spawn(st, "migration", added)
	for i in 300:
		sim.advance(1)
		if int(Plagues.list(st)[pid]["eaten"]) > 0 or String(Plagues.list(st)[pid]["status"]) != "alive":
			break
	_ok(int(Plagues.list(st)[pid]["eaten"]) > 0, "le fléau va de colonie en colonie et dévore (%d)" % int(Plagues.list(st)[pid]["eaten"]))


func _test_leave() -> void:
	var st := _new()
	var added: Array[Dictionary] = []
	var pid := Plagues._spawn(st, "spectre", added)
	Plagues.list(st)[pid]["born"] = st.tick - int(Plagues.data()["life_days"])
	Plagues.daily(st, added)
	_ok(String(Plagues.list(st)[pid]["status"]) == "gone" and Plagues.fleet_of(st, pid) == null, "au bout d'un an, il quitte la galaxie")


func _test_reward() -> void:
	var st := _new()
	var added: Array[Dictionary] = []
	var pid := Plagues._spawn(st, "spectre", added)
	var p: Dictionary = Plagues.list(st)[pid]
	p["dmg"] = {0: 700, 1: 300}
	p["hp"] = 0
	var i0 := int(st.get_empire(0).resources.get("influence", 0))
	var i1 := int(st.get_empire(1).resources.get("influence", 0))
	var f := Plagues.fleet_of(st, pid)
	f.ships.clear()
	f.hp.clear()
	var add2: Array[Dictionary] = []
	Plagues.on_battle(st, {"system": f.system_id}, 0, add2)
	_ok(String(p["status"]) == "dead" and int(p["by"]) == 0, "abattu : la plus belle part au premier")
	var t: Dictionary = Plagues.data()["triumph"]
	_ok(int(st.get_empire(0).resources.get("influence", 0)) - i0 >= int(t["influence"]) * 70 / 100 and int(st.get_empire(1).resources.get("influence", 0)) - i1 >= int(t["influence"]) * 30 / 100, "Triomphe partagé selon les dégâts (70 / 30)")
	var tri := false
	for a in add2:
		if String(a["text"]).begins_with("Triomphe") and String(a["text"]).contains("70 %"):
			tri = true
	_ok(tri, "la chronique annonce le partage")
	_ok(st.relics.is_empty() or int(st.relics.get("flamme_spectre", {}).get("owner", -1)) == 0, "trophée pour le premier")


func _test_bait() -> void:
	var st := _new()
	var vsid := _colony(st, 1, 2, 6)
	var added: Array[Dictionary] = []
	var has_op := false
	for op in GameData.espionage()["operations"]:
		if String(op["id"]) == "appat":
			has_op = true
	_ok(has_op, "opération d'espionnage « Appât »")
	var pid := Plagues._spawn(st, "spectre", added)
	var txt := Plagues.bait(st, 1)
	var p: Dictionary = Plagues.list(st)[pid]
	_ok(txt != "" and int(p["target"]) == vsid, "l'Appât détourne le fléau vers les colonies du rival")
	# Sans fléau : un troupeau hostile proche vient se servir.
	var sim := Simulation.new(_new(23))
	var s2 := sim.state
	var nest := -1
	for sid in Fauna.nest_ids(s2):
		if Fauna.temper(String(Fauna.nests(s2)[sid]["sp"])) != "passive" and Guardians.awake_at(s2, sid) == "" and not Fauna.nest_herds(s2, sid).is_empty():
			nest = sid
			break
	var col := -1
	if nest >= 0:
		var jn := FactionTraits.jumps_from(s2.galaxy, nest)
		for s in s2.galaxy.systems:
			if col < 0 and s2.system_owner(s.id) < 0 and s.planet_ids.size() > 0 and int(jn.get(s.id, 99)) >= 1 and int(jn.get(s.id, 99)) <= 3 and Fleets.fleets_at(s2, s.id).is_empty() and not Fauna.nests(s2).has(s.id):
				var c := Colony.new()
				c.planet_id = s.planet_ids[0]
				c.owner = 1
				c.kind = Colony.KIND_COLONY
				c.population = 6
				s2.add_colony(c)
				col = s.id
	_ok(col >= 0, "colonie de test près d'un nid hostile")
	if col < 0:
		return
	var pick := Plagues.bait_pick(s2, 1)
	_ok(not pick.is_empty() and String(pick[0]) == "herd", "sans fléau, l'Appât vise un troupeau hostile proche")
	Plagues.bait(s2, 1)
	var fid := int(pick[1])
	var pop := (s2.colonies[s2.galaxy.systems[col].planet_ids[0]] as Colony).population
	for i in 120:
		sim.advance(1)
		if not Fauna.herds(s2).has(fid) or int(Fauna.herds(s2)[fid].get("bait", -1)) < 0:
			break
	var c2: Colony = s2.colonies.get(s2.galaxy.systems[col].planet_ids[0])
	_ok(c2 == null or c2.population < pop, "le troupeau appâté se sert chez le rival")


func _test_ai() -> void:
	var st := GameState.create(11, 150, 1800.0, "", {"creatures": "normales"})
	var e := st.get_empire(0)
	var home := FactionTraits.capital_system(st, 0)
	var sid := _colony(st, 0, 2, 6)
	var added: Array[Dictionary] = []
	var pid := Plagues._spawn(st, "migration", added)
	var pf := Plagues.fleet_of(st, pid)
	pf.system_id = sid
	Plagues.list(st)[pid]["seen"][0] = 0
	e.explored[sid] = true
	var ctx := {"state": st, "e": e, "lv": AiLevels.level("normale")}
	var f := st.spawn_ship(0, "fregate", home)
	_ok(AiFauna.nest_target(ctx, f, home) != sid, "IA : trop faible, elle laisse le fléau")
	while Combat.fleet_power(f) * 100 < 155 * Fauna.herd_power(st, sid):
		f.add_ship("croiseur", -1, -1)
	_ok(AiFauna.nest_target(ctx, f, home) == sid, "IA : assez forte, elle défend sa colonie contre le fléau")


func _test_save() -> void:
	var sim := Simulation.new(_new(13, "grouillantes"))
	var st := sim.state
	_colony(st, 0, 2, 8)
	var added: Array[Dictionary] = []
	var pid := Plagues._spawn(st, "spectre", added)
	Plagues.list(st)[pid]["dmg"] = {1: 120}
	sim.advance(30)
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(st.to_snapshot())))
	_ok(back != null, "sauvegarde 32 relue")
	if back == null:
		return
	_ok(back.checksum() == st.checksum(), "même empreinte après sauvegarde (fléaux)")
	_ok(Plagues.ids(back) == Plagues.ids(st) and Plagues.plan(back).size() == Plagues.plan(st).size() and int(Plagues.list(back)[pid]["dmg"].get(1, 0)) == 120, "fléaux, plan et dégâts relus")
	var a := Simulation.new(st)
	var b := Simulation.new(back)
	a.advance(200)
	b.advance(200)
	_ok(a.state.checksum() == b.state.checksum(), "la partie reprise continue à l'identique")


func _test_determinism() -> void:
	var a := GameState.create(31, 150, 1800.0, "", {"creatures": "grouillantes"})
	var b := GameState.create(31, 150, 1800.0, "", {"creatures": "grouillantes"})
	var sa := Simulation.new(a)
	var sb := Simulation.new(b)
	var add: Array[Dictionary] = []
	Plagues._spawn(a, "migration", add)
	Plagues._spawn(b, "migration", add)
	sa.advance(400)
	sb.advance(400)
	_ok(a.checksum() == b.checksum(), "même graine, mêmes fléaux après 400 jours")
