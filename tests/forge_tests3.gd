class_name ForgeTests3
extends RefCounted
## Forge des mondes, lot 3 : moteurs planétaires et marche des mondes, rosettes, bélier, mondes-reliquaires
## (défenses, trésor, monde-abri, mondes vivants), carcasses de titans, talents, Grande Braderie.

static var _check: Callable


static func run(check: Callable) -> void:
	_check = check
	print("  - engines / march")
	_test_engines()
	print("  - rosette")
	_test_rosette()
	print("  - ram")
	_test_ram()
	print("  - relics")
	_test_relics()
	print("  - carcass")
	_test_carcass()
	print("  - talents")
	_test_talents()


static func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


static func _setup(faction := "ossarane", anc := "aucun") -> GameState:
	var st := ForgeTests.new_game("complete", anc, faction)
	ForgeTests.all_techs(st, 0)
	MegasTests.rich(st, 0)
	MegasTests.architect(st, 0, ForgeTests.home_sys(st, 0))
	return st


static func _colony(st: GameState, pid: int, owner: int, pop: int) -> Colony:
	var c := Colony.new()
	c.planet_id = pid
	c.owner = owner
	c.population = pop
	st.colonies[pid] = c
	st.rebuild_ownership()
	return c


static func _test_engines() -> void:
	var st := _setup()
	var sid := ForgeTests.home_sys(st, 0)
	var pid := ForgeTests.body(st, sid, "barren", 2)
	_ok(WorldForge.site_reason(st, 0, "moteurs", sid, st.get_empire(0).capital_planet) != "", "pas de moteurs sur la capitale")
	WorldForge.add_mass(st, 0, 40)
	var why := ForgeTests.cmd(st, 0, "start", {"op": "moteurs", "s": sid, "p": pid})
	_ok(why == "", "moteurs lancés (%s)" % why)
	ForgeTests.finish(st, ForgeTests.last_job(st))
	_ok(int(WorldForge.world(st, pid).get("eng", 0)) == 1, "le monde a ses moteurs")
	var tg := WorldForgeWorld.move_targets(st, 0, pid)
	_ok(not tg.is_empty(), "un voisin où aller")
	if tg.is_empty():
		return
	var to := tg[0]
	why = ForgeTests.cmd(st, 0, "move", {"p": pid, "t": to})
	_ok(why == "", "mise en marche (%s)" % why)
	_ok(WorldForge.production_pct(st, pid) == 50, "production de moitié en route")
	_ok(WorldForge.colony_block(st, pid) != "", "on ne colonise pas un monde en marche")
	ForgeTests.run_days(st, 719)
	_ok(st.galaxy.get_planet(pid).system_id == sid, "pas encore arrivé")
	ForgeTests.run_days(st, 1)
	_ok(st.galaxy.get_planet(pid).system_id == to and st.galaxy.systems[to].planet_ids.has(pid) and not st.galaxy.systems[sid].planet_ids.has(pid), "arrivé dans le système voisin (2 ans)")
	var back := GameState.from_dict(st.to_dict())
	_ok(back != null and back.galaxy.get_planet(pid).system_id == to and back.galaxy.systems[to].planet_ids.has(pid), "relu : le monde est à sa nouvelle place")
	_ok(back != null and back.checksum() == st.checksum(), "même empreinte")


static func _test_rosette() -> void:
	var st := _setup()
	var sid := ForgeTests.home_sys(st, 0)
	var n := 1
	for pid in st.galaxy.systems[sid].planet_ids:
		if not st.colonies.has(pid) and n < 3:
			st.override_planet(pid, {"type": "continental"})
			_colony(st, pid, 0, 3)
			n += 1
	if n < 3:
		_ok(true, "système natal trop petit pour une rosette (non testée)")
		return
	var why := ForgeTests.cmd(st, 0, "rosette", {"s": sid})
	_ok(why == "", "rosette formée (%s)" % why)
	var inc := WorldForge.income(st, 0)
	_ok(int(inc["gross"].get("food", 0)) == 6 and int(inc["upkeep"].get("energy", 0)) >= 9, "+2 nourriture et 3 énergie par monde")
	var cap := st.get_empire(0).capital_planet
	_ok(WorldForgeWorld.pop_bonus(st, cap, 0) == 1, "+1 habitant par monde")
	st.get_empire(0).resources["energy"] = 0
	var added: Array[Dictionary] = []
	for i in 6:
		WorldForgeWorld._rosettes_month(st, added)
	var crash := false
	for e in added:
		if String(e["text"]).contains("percuté"):
			crash = true
	_ok(crash and not WorldForge.sub(st, "rosettes").has(str(sid)), "six mois impayés : deux mondes se percutent")


static func _test_ram() -> void:
	var st := _setup()
	var sid := ForgeTests.home_sys(st, 0)
	var pid := ForgeTests.body(st, sid, "barren", 2)
	WorldForge.mark_world(st, pid, "barren", 0)
	WorldForge.world(st, pid)["eng"] = 1
	var nb := int(st.galaxy.systems[sid].neighbors[0])
	var tp: int = st.galaxy.systems[nb].planet_ids[0] if not st.galaxy.systems[nb].planet_ids.is_empty() else -1
	if tp < 0:
		_ok(true, "voisin sans planète (bélier non testé)")
		return
	_colony(st, tp, 1, 4)
	_ok(WorldForgeWorld.check_ram(st, 0, pid, tp).contains("guerre"), "seulement en guerre")
	Combat.start_war(st, 0, 1)
	var why := ForgeTests.cmd(st, 0, "ram", {"p": pid, "t": tp})
	_ok(why == "", "bélier lancé (%s)" % why)
	_ok(st.galaxy.get_planet(pid).type == "asteroids" and st.galaxy.get_planet(tp).type == "asteroids" and not st.colonies.has(tp), "les deux deviennent des cailloux")
	_ok(WorldForge.stat(st, 0, "rams") == 1, "la galaxie s'en souviendra")


static func _test_relics() -> void:
	var none := ForgeTests.new_game("complete", "aucun")
	_ok(WorldForge.sub(none, "relics").is_empty(), "Aucun : pas de monde-reliquaire")
	var st := ForgeTests.new_game("complete", "beaucoup")
	var rel := WorldForge.sub(st, "relics")
	_ok(rel.size() >= 2, "Beaucoup : des mondes-reliquaires (%d)" % rel.size())
	var pid := int(rel.keys()[0])
	_ok(WorldForgeWorld.is_relic(st, pid) and st.galaxy.get_planet(pid).type == "reliquaire", "un monde-reliquaire scellé")
	_ok(WorldForgeWorld.relic_name(st, pid) != "" and WorldForge.world_name(st, pid) == WorldForgeWorld.relic_name(st, pid), "il porte un nom des Façonneurs")
	_ok(WorldForge.colony_block(st, pid) != "", "on ne le colonise pas scellé")
	var back := GameState.from_dict(st.to_dict())
	_ok(back != null and back.galaxy.get_planet(pid) != null and back.galaxy.get_planet(pid).type == "reliquaire", "relu : les reliquaires sont reconstruits")
	# Ouverture : défenses une fois, puis trésor et monde-abri.
	ForgeTests.all_techs(st, 0)
	MegasTests.rich(st, 0)
	var sid := st.galaxy.get_planet(pid).system_id
	MegasTests.architect(st, 0, sid)
	_ok(WorldForge.site_reason(st, 0, "ouvrir", sid, pid).contains("inexploré") or st.get_empire(0).explored.has(sid), "un reliquaire inexploré ne se propose pas")
	st.get_empire(0).explored[sid] = true
	var why := WorldForge.site_reason(st, 0, "ouvrir", sid, pid)
	_ok(why == "" or why.contains("tenu"), "ouverture possible (%s)" % why)
	var r := WorldForgeWorld.relic(st, pid)
	r["woke"] = 1  # défenses déjà éveillées : on teste le trésor
	var k0 := int(st.get_empire(0).resources["knowledge"])
	var added: Array[Dictionary] = []
	WorldForgeWorld.opened(st, {"id": 1, "op": "ouvrir", "o": 0, "b": 0, "s": sid, "p": pid}, added)
	_ok(not WorldForgeWorld.is_relic(st, pid), "le monde est ouvert")
	_ok(int(st.get_empire(0).resources["knowledge"]) == k0 + 250 and WorldForge.mass(st, 0) == 80, "trésor : 250 Savoir et 80 Masse")
	var t := st.galaxy.get_planet(pid).type
	_ok(t == "abri" or t == "barren", "monde-abri (ou effondré)")
	if t == "abri":
		_colony(st, pid, 0, 3)
		_ok(WorldForgeWorld.shelter(st, pid), "monde-abri : à l'abri des crises")
	# Défenses dormantes : l'architecte est perdu, le monde reste scellé.
	var p2 := int(rel.keys()[1])
	var s2 := st.galaxy.get_planet(p2).system_id
	var f := MegasTests.architect(st, 0, s2)
	var woke := false
	if WorldForge._h(st, ["wake", p2]) % 100 < WorldForge.r_int("relic_wake_pct", 34):
		WorldForgeWorld.opened(st, {"id": 2, "op": "ouvrir", "o": 0, "b": 0, "s": s2, "p": p2}, added)
		woke = true
		_ok(WorldForgeWorld.is_relic(st, p2) and not st.fleets.has(f.id), "défenses éveillées : architecte perdu, monde encore scellé")
	_ok(true, "défenses %s" % ("testées" if woke else "endormies pour ce tirage"))
	# Monde vivant : il aime qui ne défait pas de monde.
	var lp := int(rel.keys()[rel.size() - 1])
	WorldForgeWorld.relic(st, lp)["open"] = 1
	WorldForgeWorld.relic(st, lp)["living"] = {"o": -1, "hate": 0}
	st.override_planet(lp, {"type": "abri"})
	_colony(st, lp, 0, 3)
	_ok(WorldForgeWorld.pop_bonus(st, lp, 0) == 2, "monde vivant : +2 habitants s'il vous aime")
	WorldForge._stat(st, 0, "dism", 1)
	_ok(WorldForgeWorld.pop_bonus(st, lp, 0) == -2, "il hait les briseurs de mondes")
	for i in 60:
		WorldForgeWorld._living_month(st, added)
	_ok(WorldForge.is_gone(st, lp), "haï trop longtemps, il s'en va")


static func _test_carcass() -> void:
	var st := _setup()
	var sid := ForgeTests.home_sys(st, 0)
	var added: Array[Dictionary] = []
	WorldForgeWorld.on_titan_slain(st, "x", 0, sid, added)
	_ok(WorldForge.sub(st, "carcass").has(str(sid)), "carcasse de titan en orbite")
	_ok(int(WorldForge.income(st, 0)["gross"].get("materials", 0)) == 20, "matériaux de la carcasse")
	_ok(WorldForge.cost_pct(st, 0, "habitat", sid) == -50, "habitat-monde à moitié prix")
	st.tick += 3601
	WorldForgeWorld.monthly(st, added)
	_ok(not WorldForge.sub(st, "carcass").has(str(sid)), "la carcasse finit dépecée")


static func _test_talents() -> void:
	var ch := _setup("choeur")
	var sid := ForgeTests.home_sys(ch, 0)
	var pid := ForgeTests.body(ch, sid, "asteroids", 1)
	ForgeTests.cmd(ch, 0, "start", {"op": "agglomerer", "s": sid, "p": pid})
	ForgeTests.finish(ch, ForgeTests.last_job(ch))
	_ok(WorldForge.t_int(ch, 0, "made_stab") == 1, "Chœur : Chant des sphères (+1 stabilité)")
	var mu := _setup("murmurants")
	var ms := ForgeTests.home_sys(mu, 0)
	var mp := ForgeTests.body(mu, ms, "creux", 5)
	_colony(mu, mp, 0, 2)
	_ok(WorldForgeWorld.hides_fleets(mu, 0, ms), "Murmurants : l'intérieur de leurs mondes creux cache leurs flottes")
	var va := ForgeTests.new_game("complete", "aucun", "vael")
	_ok(WorldForge.t_int(va, 0, "convention_x") == 2, "Vael : double voix à la Convention")
