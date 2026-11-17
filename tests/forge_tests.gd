class_name ForgeTests
extends RefCounted
## Tests de la Forge des mondes (étude du 2026-11-17, 42 propositions) : données et réglage, technologies,
## chantier planétaire et Vaisseau-architecte, agglomération, compression, habitat-monde et modules,
## entretien et intégrité, Masse, sauvegarde (lot 1). Coquilles, démantèlement, évacuation et ponts (lot
## 2) : ForgeTests2 ; moteurs, rosettes, bélier, reliquaires, talents, Braderie (lot 3) : ForgeTests3.
## Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Forge des mondes…")
	print("  - data")
	_test_data()
	print("  - setup")
	_test_setup()
	print("  - agglomerate")
	_test_agglomerate()
	print("  - compress")
	_test_compress()
	print("  - habitat")
	_test_habitat()
	print("  - upkeep")
	_test_upkeep()
	print("  - save")
	_test_save()
	ForgeTests2.run(check)
	ForgeTests3.run(check)


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


static func new_game(mode := "complete", anc := "aucun", faction := "ossarane", extra := {}) -> GameState:
	var opts := {"ai_level": "", "worldforge": mode, "forge_ancients": anc}
	opts.merge(extra, true)
	return GameState.create(4242, 150, 1800.0, faction, opts)


static func cmd(st: GameState, eid: int, act: String, d := {}) -> String:
	var c := SimCommands.forge_act(eid, act, d)
	var why := SimCommands.validate(st, c)
	if why == "":
		SimCommands.apply(st, c)
	return why


static func all_techs(st: GameState, eid: int) -> void:
	Research.grant(st, eid, ["architectes_stellaires", "agglomeration", "compression_gravitationnelle", "demantelement", "mondes_coquilles", "mondes_sur_mesure", "moteurs_planetaires"])


static func home_sys(st: GameState, eid: int) -> int:
	return MegasTests.home_sys(st, eid)


## Un corps du système natal mis au type voulu (sans colonie) ; -1 s'il n'y en a pas.
static func body(st: GameState, sid: int, t: String, size := 3) -> int:
	for pid in st.galaxy.systems[sid].planet_ids:
		if not st.colonies.has(pid):
			st.override_planet(pid, {"type": t, "size": size})
			return pid
	return -1


## Fait avancer les chantiers de n jours.
static func run_days(st: GameState, n: int) -> void:
	for i in n:
		st.tick += 1
		WorldForge.daily(st)


static func finish(st: GameState, id: int) -> void:
	var j := WorldForge.get_job(st, id)
	if j.is_empty():
		return
	j["w"] = 1
	WorldForge.daily(st)


static func last_job(st: GameState) -> int:
	var ids := WorldForge.job_ids(st)
	return ids[ids.size() - 1] if not ids.is_empty() else -1


func _test_data() -> void:
	var d := GameData.worldforge()
	_ok(d.get("ops", {}).size() == 11, "11 chantiers planétaires au catalogue")
	var bad := PackedStringArray()
	for op in WorldForge.op_ids():
		for t in WorldForge.op_def(op).get("tech", []):
			if Research.tech(String(t)).is_empty():
				bad.append("%s:%s" % [op, t])
	_ok(bad.is_empty(), "technologies du catalogue valides (%s)" % ", ".join(bad))
	for t in ["noyau", "habitat", "coquille", "creux", "reliquaire", "abri"]:
		_ok(not GameData.planet_type(t).is_empty() and bool(GameData.planet_type(t).get("artificial", false)), "type de monde %s" % t)
	_ok(WorldForge.mode_defs().size() == 3 and WorldForge.ancient_defs().size() == 3, "trois réglages, trois quantités de mondes anciens")
	var talents := 0
	for f in ["ossarane", "choeur", "vael", "khthari", "teyl", "ferrocornes", "brisecomete", "murmurants"]:
		if WorldForge.cfg("talents").has(f):
			talents += 1
	_ok(talents == 8, "un talent de la Forge par peuple (8)")
	for m in ["world_unmade", "world_dismantled_near", "world_digested", "world_rammed", "world_ordered"]:
		_ok((GameData.diplomacy().get("memories", {}) as Dictionary).has(m), "souvenir diplomatique %s" % m)


func _test_setup() -> void:
	var off := GameState.create(4242, 150, 1800.0, "ossarane", {"ai_level": ""})
	_ok(off.forge.is_empty() and not WorldForge.enabled(off), "sans l'option : désactivée")
	var st0 := new_game("desactivee")
	_ok(st0.forge.is_empty(), "Désactivée : rien")
	Research.grant(st0, 0, ["architectes_stellaires"])
	MegasTests.rich(st0, 0)
	_ok(Fleets.check_build_ship(st0, 0, st0.get_empire(0).capital_planet, "architecte").contains("pas en jeu"), "ni Forge ni mégastructures : pas de Vaisseau-architecte")
	var st := new_game()
	Research.grant(st, 0, ["architectes_stellaires"])
	MegasTests.rich(st, 0)
	_ok(WorldForge.enabled(st) and WorldForge.dismantle_on(st), "Complète : création et démantèlement")
	_ok(not Fleets.check_build_ship(st, 0, st.get_empire(0).capital_planet, "architecte").contains("pas en jeu"), "la Forge seule permet le Vaisseau-architecte")
	var sd := new_game("sans_demantelement")
	_ok(WorldForge.enabled(sd) and not WorldForge.dismantle_on(sd), "Sans démantèlement")
	_ok(Research.unlocks(st.get_empire(0).faction(), "agglomeration").has("Agglomération (Forge des mondes)"), "la technologie annonce le chantier")


func _test_agglomerate() -> void:
	var st := new_game()
	var sid := home_sys(st, 0)
	var pid := body(st, sid, "asteroids", 1)
	_ok(WorldForge.site_reason(st, 0, "agglomerer", sid, pid).contains("technologie"), "il faut la technologie")
	all_techs(st, 0)
	MegasTests.rich(st, 0)
	_ok(WorldForge.site_reason(st, 0, "agglomerer", sid, pid) == "", "agglomération possible sur la ceinture")
	_ok(cmd(st, 0, "start", {"op": "agglomerer", "s": sid, "p": pid}).contains("architecte"), "sans Vaisseau-architecte : refusé")
	var f := MegasTests.architect(st, 0, sid)
	var mat := int(st.get_empire(0).resources["materials"])
	var why := cmd(st, 0, "start", {"op": "agglomerer", "s": sid, "p": pid})
	_ok(why == "", "chantier lancé (%s)" % why)
	_ok(int(st.get_empire(0).resources["materials"]) == mat - 300, "payé au lancement (300 matériaux)")
	var id := last_job(st)
	_ok(id >= 0 and int(WorldForge.get_job(st, id)["w"]) == 900, "900 jours")
	_ok(not WorldForge.architect_busy(st, f), "l'architecte reste libre (il lance, il ne reste pas)")
	_ok(WorldForge.site_reason(st, 0, "agglomerer", sid, pid).contains("déjà en cours"), "un chantier par système")
	run_days(st, 10)
	_ok(int(WorldForge.get_job(st, id)["w"]) == 890, "le chantier avance")
	finish(st, id)
	var p := st.galaxy.get_planet(pid)
	_ok(p.type == "barren" and p.size == 2 and p.deposits.is_empty(), "la ceinture devient une stérile de taille 2, sans gisements")
	_ok(WorldForge.is_made(st, pid) and WorldForge.stat(st, 0, "made") == 1, "monde façonné compté")
	_ok(WorldForge.kardashev_count(st, 0) == 1, "liaison Kardashev : un monde")
	_ok(int(Research.effects(st, 0).get("culture_pct", 0)) >= 2, "Rayonnement des mondes créés (+2 %)")
	# Plan : l'architecte le plus proche se met en route.
	var st2 := new_game()
	all_techs(st2, 0)
	MegasTests.rich(st2, 0)
	var s2 := home_sys(st2, 0)
	var p2 := body(st2, s2, "asteroids", 1)
	var nb := int(st2.galaxy.systems[s2].neighbors[0])
	var f2 := MegasTests.architect(st2, 0, nb)
	_ok(cmd(st2, 0, "plan", {"op": "agglomerer", "s": s2, "p": p2}) == "" and f2.is_moving(), "architecte lointain : il se met en route")
	_ok(WorldForge.architect_busy(st2, f2) and Megastructures.architect_busy(st2, f2), "l'ordre retient l'architecte (aussi pour les mégastructures)")
	f2.path.clear()
	f2.progress = 0
	f2.system_id = s2
	run_days(st2, 1)
	_ok(WorldForge.job_ids(st2).size() == 1 and not WorldForge.architect_busy(st2, f2), "arrivé : le chantier est lancé")


func _test_compress() -> void:
	var st := new_game()
	all_techs(st, 0)
	MegasTests.rich(st, 0)
	var sid := home_sys(st, 0)
	var pid := body(st, sid, "gas_giant", 5)
	MegasTests.architect(st, 0, sid)
	_ok(cmd(st, 0, "start", {"op": "comprimer", "s": sid, "p": pid}) == "", "compression lancée")
	finish(st, last_job(st))
	var p := st.galaxy.get_planet(pid)
	_ok(p.type == "noyau" and p.size == 3, "la géante devient un monde-noyau de taille 3")
	_ok(int(GameData.planet_type("noyau").get("city_pop_yields", {}).get("materials", 0)) > 0, "monde-noyau riche en matériaux")
	# Ferrocornes : 30 % plus rapide.
	var fe := new_game("complete", "aucun", "ferrocornes")
	_ok(WorldForge.op_days(fe, 0, "comprimer") < WorldForge.op_days(st, 0, "comprimer"), "Fondeurs de lunes : compression plus rapide")


func _test_habitat() -> void:
	var st := new_game()
	all_techs(st, 0)
	MegasTests.rich(st, 0)
	var sid := home_sys(st, 0)
	_ok(WorldForge.site_reason(st, 0, "habitat", sid, -1).contains("sans planète habitable"), "habitat : pas dans un système habitable")
	# Un système sans habitable, tenu par un avant-poste établi.
	var hs := -1
	for s in st.galaxy.systems:
		if s.planet_ids.size() >= 2 and s.planet_ids.size() < 8 and not WorldForge.has_habitable(st, s.id) and st.system_owner(s.id) < 0:
			hs = s.id
			break
	_ok(hs >= 0, "un système sans habitable existe")
	var anchor: int = st.galaxy.systems[hs].planet_ids[0]
	var c := Colony.new()
	c.planet_id = anchor
	c.owner = 0
	c.kind = Colony.KIND_OUTPOST
	c.days_left = 0
	st.colonies[anchor] = c
	st.rebuild_ownership()
	_ok(WorldForge._holds(st, 0, hs), "système tenu par l'avant-poste")
	MegasTests.architect(st, 0, hs)
	var n0 := st.galaxy.planets.size()
	var why := cmd(st, 0, "start", {"op": "habitat", "s": hs, "p": -1})
	_ok(why == "", "habitat-monde lancé (%s)" % why)
	finish(st, last_job(st))
	_ok(st.galaxy.planets.size() == n0 + 1, "un corps nouveau")
	var hp := st.galaxy.planets[n0]
	_ok(hp.type == "habitat" and hp.size == 3 and st.galaxy.systems[hs].planet_ids.has(hp.id), "habitat-monde dans le système (Ossarane : taille 3)")
	_ok(int(GameData.planet_type("habitat").get("base_hab", 0)) == 70, "habitable à 70 %")
	_ok(WorldForge.growth_pct(st, hp.id) == 100, "colonie deux fois plus rapide")
	_ok(WorldForge.site_reason(st, 0, "habitat", hs, -1) != "", "un habitat par système")
	# Module : +1 taille.
	_ok(WorldForge.site_reason(st, 0, "module", hs, hp.id) == "", "extension possible (%s)" % WorldForge.site_reason(st, 0, "module", hs, hp.id))
	cmd(st, 0, "start", {"op": "module", "s": hs, "p": hp.id})
	finish(st, last_job(st))
	_ok(hp.size == 4 and int(WorldForge.world(st, hp.id)["mods"]) == 1, "l'habitat gagne une taille")


func _test_upkeep() -> void:
	var st := new_game()
	all_techs(st, 0)
	var sid := home_sys(st, 0)
	var pid := body(st, sid, "barren", 3)
	WorldForge.reshape(st, pid, "coquille")
	WorldForge.mark_world(st, pid, "coquille", 0)
	var inc := WorldForge.income(st, 0)
	_ok(int(inc["upkeep"].get("energy", 0)) == 2, "entretien : 2 énergie pour une coquille")
	st.get_empire(0).resources["energy"] = 0
	var added: Array[Dictionary] = []
	for i in 5:
		WorldForgeBridges._integrity(st, added)
	_ok(int(WorldForge.world(st, pid)["integ"]) == 50, "sans énergie : l'intégrité baisse (50)")
	WorldForgeBridges._integrity(st, added)
	var breach := false
	for e in added:
		if String(e["text"]).contains("Brèche"):
			breach = true
	_ok(breach, "brèche annoncée sous 50 %")
	for i in 6:
		WorldForgeBridges._integrity(st, added)
	_ok(st.galaxy.get_planet(pid).type == "barren" and not WorldForge.is_made(st, pid), "à zéro : la coquille retombe en stérile")
	# Masse : fondre.
	WorldForge.add_mass(st, 0, 12)
	var m0 := int(st.get_empire(0).resources["materials"])
	_ok(cmd(st, 0, "melt", {"n": 5}) == "" and WorldForge.mass(st, 0) == 7 and int(st.get_empire(0).resources["materials"]) == m0 + 50, "fondre 5 Masse : 50 matériaux")
	_ok(cmd(st, 0, "melt", {"n": 50}) != "", "pas plus que la Masse détenue")


func _test_save() -> void:
	var st := new_game()
	all_techs(st, 0)
	MegasTests.rich(st, 0)
	var sid := home_sys(st, 0)
	var hs := -1
	for s in st.galaxy.systems:
		if s.planet_ids.size() >= 2 and s.planet_ids.size() < 8 and not WorldForge.has_habitable(st, s.id) and st.system_owner(s.id) < 0:
			hs = s.id
			break
	var anchor: int = st.galaxy.systems[hs].planet_ids[0]
	var c := Colony.new()
	c.planet_id = anchor
	c.owner = 0
	c.kind = Colony.KIND_OUTPOST
	c.days_left = 0
	st.colonies[anchor] = c
	st.rebuild_ownership()
	MegasTests.architect(st, 0, hs)
	cmd(st, 0, "start", {"op": "habitat", "s": hs, "p": -1})
	finish(st, last_job(st))
	var pid := body(st, sid, "asteroids", 1)
	MegasTests.architect(st, 0, sid)
	cmd(st, 0, "start", {"op": "agglomerer", "s": sid, "p": pid})
	WorldForge.add_mass(st, 0, 33)
	var n := st.galaxy.planets.size()
	var d := st.to_dict()
	_ok(d.has("forge") and int(d["version"]) == 91, "sauvegarde 91 avec la Forge")
	var back := GameState.from_dict(d)
	_ok(back != null, "relecture (%s)" % GameState.last_error)
	if back == null:
		return
	_ok(back.galaxy.planets.size() == n and back.galaxy.planets[n - 1].type == "habitat", "l'habitat-monde est reconstruit")
	_ok(back.galaxy.systems[hs].planet_ids.has(n - 1), "dans son système")
	_ok(WorldForge.mass(back, 0) == 33 and WorldForge.job_ids(back).size() == 1, "Masse et chantier relus")
	_ok(back.checksum() == st.checksum(), "même empreinte après relecture")
	var snap := GameState.from_dict(st.to_snapshot())
	_ok(snap != null and snap.galaxy.planets.size() == n, "instantané : pas de corps en double")
	var old := new_game("desactivee").to_dict()
	old["version"] = 90
	old.erase("forge")
	var ob := GameState.from_dict(old)
	_ok(ob != null and ob.forge.is_empty(), "ancienne sauvegarde (90) : sans Forge")
