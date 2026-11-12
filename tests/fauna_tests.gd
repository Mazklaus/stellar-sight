extends RefCounted
## Tests de la faune (Fauna, FaunaSystem, AiFauna, BestiaryPanel) : densités et placement des nids,
## hostilité selon le tempérament et l'attitude, bataille contre un troupeau, ni siège ni blocus,
## migrations autour du nid, repeuplement, destruction d'un nid, attitudes (coûts, étude et bonus,
## apprivoisement, chasse et butin), piège de curiosité vivante, contournement des sans-armes, IA,
## Bestiaire ; sauvegarde 29 et déterminisme. Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Faune…")
	_test_setup()
	_test_hostility()
	_test_battle()
	_test_migration()
	_test_respawn()
	_test_nest_destroyed()
	_test_attitudes()
	_test_loot()
	_test_trap()
	_test_ai()
	_test_save()
	_test_determinism()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


func _new(seed_value := 11, density := "normales") -> GameState:
	return GameState.create(seed_value, 150, 1800.0, "vael", {"ai_level": "", "creatures": density})


## Nid d'une espèce de ce tempérament (en crée un dans un système libre s'il n'y en a pas).
func _nest_of(st: GameState, temper: String) -> int:
	for sid in Fauna.nest_ids(st):
		if Fauna.temper(String(Fauna.nests(st)[sid]["sp"])) == temper and Guardians.awake_at(st, sid) == "":
			return sid  # (pas le nid que garde la Matriarche)
	for sp in Fauna.species_ids():
		if Fauna.temper(sp) != temper:
			continue
		for s in st.galaxy.systems:
			if st.system_owner(s.id) < 0 and not Fauna.nests(st).has(s.id) and not s.planet_ids.is_empty() and Fleets.fleets_at(st, s.id).is_empty() and Guardians.awake_at(st, s.id) == "":
				Fauna.create_nest(st, s.id, sp)
				return s.id
	return -1


func _meet(st: GameState, empire_id: int, sp: String) -> void:
	var added: Array[Dictionary] = []
	Fauna.see(st, empire_id, sp, 0, added)


func _test_setup() -> void:
	var none := _new(11, "aucune")
	_ok(not Fauna.active(none) and Fauna.nest_ids(none).is_empty() and Fauna.herd_ids(none).is_empty(), "créatures « Aucune » : ni nid ni troupeau")
	var st := _new()
	var nests := Fauna.nest_ids(st)
	_ok(Fauna.active(st) and nests.size() >= 3, "créatures normales : des nids (%d)" % nests.size())
	var far := true
	var herds_ok := true
	var deposit := true
	for sid in nests:
		for e in st.empires:
			var cap := FactionTraits.capital_system(st, e.id)
			if cap >= 0 and int(FactionTraits.jumps_from(st.galaxy, cap).get(sid, 999)) < int(Fauna.data()["min_jumps_from_start"]):
				far = false
		if Fauna.nest_herds(st, sid).size() != 3:
			herds_ok = false
		var sp := String(Fauna.nests(st)[sid]["sp"])
		var dep := String(Fauna.species(sp)["deposit"])
		var found := false
		for pid in st.galaxy.systems[sid].planet_ids:
			if st.galaxy.get_planet(pid).deposits.has(dep):
				found = true
		deposit = deposit and found
	_ok(far, "nids à 4 sauts au moins de chaque capitale")
	_ok(herds_ok, "trois troupeaux par nid en densité normale")
	_ok(deposit, "chaque nid porte le gisement de son espèce")
	var rare := _new(11, "grouillantes")
	_ok(Fauna.nest_ids(rare).size() > nests.size(), "créatures grouillantes : plus de nids")
	var f: Fleet = st.fleets[Fauna.herd_ids(st)[0]]
	_ok(f.owner == GameState.FAUNA_ID and GameState.is_npc(f.owner) and st.get_empire(GameState.FAUNA_ID) != null, "les troupeaux appartiennent à la Faune, puissance neutre")
	_ok(Combat.ship_strength("bete_rongeroc") > 0 and GameData.ship("bete_nuee").get("creature", "") == "nuees", "unités de créatures lues par le catalogue")


func _test_hostility() -> void:
	var st := _new()
	var pas := _nest_of(st, "passive")
	var ter := _nest_of(st, "territorial")
	var hp: Fleet = st.fleets[Fauna.nest_herds(st, pas)[0]]
	var ht: Fleet = st.fleets[Fauna.nest_herds(st, ter)[0]]
	_ok(not Fauna.hostile(st, hp, 0), "une espèce passive laisse passer")
	_ok(Fauna.hostile(st, ht, 0), "une espèce territoriale attaque")
	_ok(not Fauna.hostile(st, ht, GameState.PIRATE_ID), "la Faune ne se bat pas contre les pirates")
	var sp_p := String(Fauna.herd_of(st, hp)["sp"])
	var sp_t := String(Fauna.herd_of(st, ht)["sp"])
	_meet(st, 0, sp_p)
	_meet(st, 0, sp_t)
	st.get_empire(0).resources["influence"] = 500
	st.get_empire(0).resources["energy"] = 500
	Fauna.set_attitude(st, 0, sp_p, "chasse")
	_ok(Fauna.hostile(st, hp, 0) and not Fauna.hostile(st, hp, 1), "chasser une espèce passive : elle combat le chasseur, pas les autres")
	_ok(Fauna.avoided(st, 0, pas), "les sans-armes du chasseur contournent son nid")
	st.fauna["meta"][0]["stance"][sp_t] = "apprivoise"
	_ok(not Fauna.hostile(st, ht, 0) and not Fauna.avoided(st, 0, ter), "une espèce apprivoisée n'attaque plus")


func _test_battle() -> void:
	var sim := Simulation.new(_new())
	var st := sim.state
	var ter := _nest_of(st, "territorial")
	var pas := _nest_of(st, "passive")
	_ok(not Combat.blocks(st, 0, ter), "la Faune ne fait pas de blocus")
	st.spawn_ship(0, "fregate", ter)
	st.spawn_ship(0, "fregate", pas)
	sim.advance(1)
	_ok(st.battles.has(ter), "une flotte qui s'arrête chez une espèce territoriale est attaquée")
	_ok(not st.battles.has(pas), "chez une espèce passive, pas de bataille")
	var cap := FactionTraits.capital_system(st, 0)
	var trap := Fauna.spawn_trap(st, cap, 5)
	_ok(not Combat.besiegers(st, cap).has(trap), "la Faune n'assiège rien")


func _test_migration() -> void:
	var sim := Simulation.new(_new(13))
	var st := sim.state
	var roam := int(Fauna.data()["roam_jumps"])
	var moved := false
	var start := {}
	for fid in Fauna.herd_ids(st):
		start[fid] = (st.fleets[fid] as Fleet).system_id
	var ok := true
	for i in 8:
		sim.advance(90)
		for fid in Fauna.herd_ids(st):
			var f: Fleet = st.fleets.get(fid)
			if f == null:
				continue
			var nest := int(Fauna.herds(st)[fid]["nest"])
			if nest < 0:
				continue
			var j := int(FactionTraits.jumps_from(st.galaxy, nest).get(f.system_id, 999))
			if j > roam + 1:
				ok = false
			if start.has(fid) and f.system_id != int(start[fid]):
				moved = true
	_ok(moved, "les troupeaux migrent")
	_ok(ok, "ils restent à %d sauts de leur nid" % roam)


func _test_respawn() -> void:
	var sim := Simulation.new(_new())
	var st := sim.state
	var sid := Fauna.nest_ids(st)[0]
	var before := Fauna.nest_herds(st, sid).size()
	st.fleets.erase(Fauna.nest_herds(st, sid)[0])
	sim.advance(1)
	_ok(Fauna.nest_herds(st, sid).size() == before - 1 and int(Fauna.nests(st)[sid]["lost"]) >= 0, "troupeau abattu : le nid note la perte")
	sim.advance(int(Fauna.data()["respawn_days"]) + 1)
	_ok(Fauna.nest_herds(st, sid).size() == before, "le troupeau renaît au bout de trois ans")


func _test_nest_destroyed() -> void:
	var sim := Simulation.new(_new())
	var st := sim.state
	var ter := _nest_of(st, "territorial")
	for fid in Fauna.nest_herds(st, ter):
		st.fleets.erase(fid)
	var mat := int(st.get_empire(0).resources.get("materials", 0))
	st.spawn_ship(0, "fregate", ter)
	sim.advance(1)
	_ok(not Fauna.nests(st).has(ter), "nid sans troupeau tenu par une flotte armée hostile : détruit")
	_ok(int(st.get_empire(0).resources.get("materials", 0)) >= mat + int(Fauna.data()["nest_loot"]["materials"]), "butin du nid")
	var pas := _nest_of(st, "passive")
	for fid in Fauna.nest_herds(st, pas):
		st.fleets.erase(fid)
	st.spawn_ship(0, "fregate", pas)
	sim.advance(1)
	_ok(Fauna.nests(st).has(pas), "le nid d'une espèce passive non chassée n'est pas détruit")


func _test_attitudes() -> void:
	var sim := Simulation.new(_new())
	var st := sim.state
	var e := st.get_empire(0)
	e.resources["influence"] = 300
	e.resources["energy"] = 300
	_ok(Fauna.check_attitude(st, 0, "nacrelles", "etude") != "", "on n'étudie pas une espèce jamais rencontrée")
	_meet(st, 0, "nacrelles")
	_meet(st, 0, "cristalloides")
	_ok(Fauna.check_attitude(st, 0, "nacrelles", "apprivoise") != "", "apprivoiser demande l'étude")
	_ok(Fauna.check_attitude(st, 0, "cristalloides", "apprivoise") != "", "les Cristalloïdes ne s'apprivoisent pas")
	var energy := int(e.resources["energy"])
	_ok(sim.submit(SimCommands.fauna_attitude(0, "nacrelles", "etude")), "commande d'étude acceptée")
	sim.advance(1)
	_ok(Fauna.study_end(st, 0, "nacrelles") > 0 and int(e.resources["energy"]) < energy, "étude lancée et payée")
	_ok(Fauna.check_attitude(st, 0, "nacrelles", "etude") != "", "une seule étude à la fois par espèce")
	var before := int(Research.effects(st, 0).get("production_pct", {}).get("knowledge", 0))
	sim.advance(int(Fauna.attitude_def("etude")["days"]) + 1)
	_ok(Fauna.studied(st, 0, "nacrelles"), "étude terminée au bout d'un an")
	_ok(int(Research.effects(st, 0).get("production_pct", {}).get("knowledge", 0)) == before + 5, "bonus de l'étude : +5 % de Savoir")
	e.resources["influence"] = 300
	_ok(Fauna.check_attitude(st, 0, "nacrelles", "apprivoise") == "", "espèce étudiée : on peut l'apprivoiser")
	Fauna.set_attitude(st, 0, "nacrelles", "apprivoise")
	_ok(Fauna.stance(st, 0, "nacrelles") == "apprivoise", "apprivoisée")
	Fauna.set_attitude(st, 0, "nacrelles", "renoncer")
	_ok(Fauna.stance(st, 0, "nacrelles") == "", "renoncer rend l'espèce à son humeur")
	Fauna.set_attitude(st, 0, "cristalloides", "chasse")
	var ter := _nest_of(st, "territorial")
	var herd: Fleet = null
	for fid in Fauna.herd_ids(st):
		if String(Fauna.herds(st)[fid]["sp"]) == "cristalloides":
			herd = st.fleets[fid]
	if herd != null:
		var f := st.spawn_ship(0, "fregate", ter)
		_ok(Fauna.hunt_pct(st, f, [herd]) == 33 and Fauna.hunt_pct(st, st.spawn_ship(1, "fregate", ter), [herd]) == 0, "chasse : +33 % de dégâts pour le seul chasseur")
	var pr := Fauna.power_range(st, 0, st.fleets[Fauna.herd_ids(st)[0]])
	_ok(pr[0] < pr[1], "force des créatures affichée en fourchette")


func _test_loot() -> void:
	var st := _new()
	_meet(st, 0, "rongeroc")
	var e := st.get_empire(0)
	var mat := int(e.resources.get("materials", 0))
	var added: Array[Dictionary] = []
	var b := {"system": 0, "sides": [{"empire": GameState.FAUNA_ID, "lost": {"bete_rongeroc": 2}}, {"empire": 0, "lost": {}}]}
	Fauna.on_battle(st, b, 0, added)
	_ok(int(e.resources.get("materials", 0)) == mat + 15, "butin à moitié sans chasse (2 × 15 × 50 %)")
	_ok(Fauna.kills(st, 0, "rongeroc") == 2, "prises comptées")
	st.fauna["meta"][0]["stance"]["rongeroc"] = "chasse"
	Fauna.on_battle(st, b, 0, added)
	_ok(int(e.resources.get("materials", 0)) == mat + 45, "butin entier pour le chasseur")


func _test_trap() -> void:
	var sim := Simulation.new(_new())
	var st := sim.state
	var sid := FactionTraits.capital_system(st, 0)
	var f := Fauna.spawn_trap(st, sid, 7)
	var h := Fauna.herd_of(st, f)
	_ok(int(h["nest"]) == -1 and int(h["until"]) > st.tick, "piège d'une curiosité vivante : un troupeau dérangé")
	_ok(Fauna.hostile(st, f, 0) and Fauna.hostile(st, f, 1), "un troupeau dérangé est hostile à tous")
	st.fleets.erase(f.id)
	Fauna.herds(st).erase(f.id)
	var free := -1
	for s in st.galaxy.systems:
		if st.system_owner(s.id) < 0 and Fleets.fleets_at(st, s.id).is_empty() and not Fauna.nests(st).has(s.id):
			free = s.id
			break
	var g := Fauna.spawn_trap(st, free, 3)
	sim.advance(int(Fauna.data()["trap_days"]) + 1)
	_ok(not st.fleets.has(g.id) and not Fauna.herds(st).has(g.id), "il se disperse au bout de 120 jours")


func _test_ai() -> void:
	var st := _new()
	var ter := _nest_of(st, "territorial")
	_ok(AiFauna.dangerous(st, 1, ter), "IA : un nid territorial est dangereux pour ses colons")
	var pas := _nest_of(st, "passive")
	_ok(not AiFauna.dangerous(st, 1, pas), "IA : une espèce passive ne gêne pas la colonisation")
	var sim := Simulation.new(GameState.create(11, 150, 1800.0, "", {"creatures": "normales"}))
	sim.advance(360 * 4)
	var acts := 0
	for e in sim.state.empires:
		for sp in Fauna.species_ids():
			if Fauna.study_end(sim.state, e.id, sp) != 0 or Fauna.stance(sim.state, e.id, sp) != "":
				acts += 1
	_ok(acts > 0, "les IA étudient, chassent ou apprivoisent (%d)" % acts)


func _test_save() -> void:
	var sim := Simulation.new(_new(13))
	var st := sim.state
	_meet(st, 0, "nuees")
	st.get_empire(0).resources["energy"] = 500
	st.get_empire(0).resources["influence"] = 500
	Fauna.set_attitude(st, 0, "nuees", "etude")
	Fauna.set_attitude(st, 0, "nuees", "chasse")
	Fauna.spawn_trap(st, FactionTraits.capital_system(st, 0), 1)
	sim.advance(40)
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(st.to_snapshot())))
	_ok(back != null, "sauvegarde 29 relue")
	if back == null:
		return
	_ok(back.checksum() == st.checksum(), "même empreinte après sauvegarde (nids, troupeaux, attitudes)")
	_ok(Fauna.nest_ids(back) == Fauna.nest_ids(st) and Fauna.herd_ids(back) == Fauna.herd_ids(st) and Fauna.stance(back, 0, "nuees") == "chasse", "nids, troupeaux et attitudes relus")
	var a := Simulation.new(st)
	var b := Simulation.new(back)
	a.advance(200)
	b.advance(200)
	_ok(a.state.checksum() == b.state.checksum(), "la partie reprise continue à l'identique")
	var old := st.to_snapshot()
	old.erase("fauna")
	var legacy := GameState.from_dict(JSON.parse_string(JSON.stringify(old)))
	_ok(legacy != null and not Fauna.active(legacy), "une sauvegarde sans faune se relit sans créatures")


func _test_determinism() -> void:
	var a := Simulation.new(GameState.create(53, 150, 1800.0, "", {"creatures": "grouillantes"}))
	var b := Simulation.new(GameState.create(53, 150, 1800.0, "", {"creatures": "grouillantes"}))
	a.advance(900)
	b.advance(900)
	_ok(a.state.checksum() == b.state.checksum() and Fauna.active(a.state), "même graine, même faune après 900 jours")
