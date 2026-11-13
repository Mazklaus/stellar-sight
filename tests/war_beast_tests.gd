extends RefCounted
## Tests du lot 3 B des créatures : bêtes de guerre (filet gravitationnel, Vivarium, stades, lâcher,
## entretien en vivres), talents par couche (honneur, foi, raison, profit, survie, ruche et reptilien,
## synthétique, énergétique), trait de héros « Tueur de monstres », repaires dresseurs, sauvegarde.
## Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Bêtes de guerre et talents…")
	_test_vivarium()
	_test_capture()
	_test_release()
	_test_talents()
	_test_slayer()
	_test_pirates()
	_test_save()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


func _new(seed_value := 11) -> GameState:
	return GameState.create(seed_value, 150, 1800.0, "", {"ai_level": "", "creatures": "normales"})


func _eid(st: GameState, faction: String) -> int:
	for e in st.empires:
		if e.faction_id == faction:
			return e.id
	return -1


func _cap_colony(st: GameState, eid: int) -> Colony:
	return st.colonies[st.get_empire(eid).capital_planet]


## Nid de Nacrelles libre de gardien (en crée un au besoin).
func _nacre_nest(st: GameState) -> int:
	for sid in Fauna.nest_ids(st):
		if String(Fauna.nests(st)[sid]["sp"]) == "nacrelles" and Guardians.awake_at(st, sid) == "" and not Fauna.nest_herds(st, sid).is_empty():
			return sid
	for s in st.galaxy.systems:
		if st.system_owner(s.id) < 0 and not Fauna.nests(st).has(s.id) and not s.planet_ids.is_empty() and Fleets.fleets_at(st, s.id).is_empty() and Guardians.awake_at(st, s.id) == "":
			Fauna.create_nest(st, s.id, "nacrelles")
			return s.id
	return -1


func _tame(st: GameState, eid: int, sp: String) -> void:
	var added: Array[Dictionary] = []
	Fauna.see(st, eid, sp, 0, added)
	Fauna._meta(st, eid)["study"][sp] = -1
	Fauna._meta(st, eid)["stance"][sp] = "apprivoise"


func _test_vivarium() -> void:
	var st := _new()
	var vael := _eid(st, "vael")
	var pid := st.get_empire(vael).capital_planet
	_ok(Economy.check_build(st, vael, pid, "vivarium").contains("étudié"), "Vivarium : il faut avoir étudié une espèce")
	Fauna._meta(st, vael)["study"]["nacrelles"] = -1
	_ok(not Economy.check_build(st, vael, pid, "vivarium").contains("étudié"), "une espèce étudiée ouvre le Vivarium")
	var kh := _eid(st, "khthari")
	_ok(WarBeasts.check_vivarium(st, kh) == "" and WarBeasts.check_vivarium(st, _eid(st, "ferrocornes")) == "", "ruche et reptiliens : Vivarium dès le départ")
	_ok(not GameData.ship("chalutier").is_empty() and bool(GameData.ship("chalutier").get("net", false)), "le Chalutier du vide porte un filet gravitationnel")
	var sd := Designs.compute("corvette", ["filet_gravitationnel"])
	_ok(bool(sd.get("net", false)), "le module « Filet gravitationnel » se pose sur un modèle")


func _test_capture() -> void:
	var sim := Simulation.new(_new(13))
	var st := sim.state
	var vael := _eid(st, "vael")
	var nest := _nacre_nest(st)
	_tame(st, vael, "nacrelles")
	_cap_colony(st, vael).buildings.append("vivarium")
	_ok(WarBeasts.capacity(st, vael) == int(GameData.building("vivarium")["vivarium"]), "un Vivarium : trois places")
	var herd: Fleet = st.fleets[Fauna.nest_herds(st, nest)[0]]
	var n0 := 0
	for fid in Fauna.nest_herds(st, nest):
		n0 += (st.fleets[fid] as Fleet).ships.size()
	st.spawn_ship(vael, "chalutier", nest)
	sim.advance(int(WarBeasts.data()["net_days"]) + 2)
	var n1 := 0
	for fid in Fauna.nest_herds(st, nest):
		n1 += (st.fleets[fid] as Fleet).ships.size()
	_ok(WarBeasts.beasts(st, vael).size() == 1 and String(WarBeasts.beasts(st, vael)[0]["sp"]) == "nacrelles", "le filet ramène une jeune Nacrelle au Vivarium")
	_ok(n1 < n0 or herd.ships.size() < 3, "le troupeau perd une bête")
	_ok(WarBeasts.stage(st, WarBeasts.beasts(st, vael)[0]) == "jeune", "elle est jeune")
	# Plus de place : rien ne se capture.
	st.fauna["beasts"][vael] = [{"sp": "nacrelles", "born": st.tick}, {"sp": "nacrelles", "born": st.tick}, {"sp": "nacrelles", "born": st.tick}]
	sim.advance(int(WarBeasts.data()["net_days"]) + 2)
	_ok(WarBeasts.beasts(st, vael).size() == 3, "Vivarium plein : la bête est relâchée")
	# Une espèce non apprivoisée ne se capture pas.
	var st2 := _new(13)
	var v2 := _eid(st2, "vael")
	var nest2 := _nacre_nest(st2)
	_cap_colony(st2, v2).buildings.append("vivarium")
	st2.spawn_ship(v2, "chalutier", nest2)
	var s2 := Simulation.new(st2)
	s2.advance(int(WarBeasts.data()["net_days"]) + 2)
	_ok(WarBeasts.beasts(st2, v2).is_empty(), "sans apprivoisement, pas de capture")


func _test_release() -> void:
	var st := _new()
	var vael := _eid(st, "vael")
	_cap_colony(st, vael).buildings.append("vivarium")
	st.fauna["beasts"] = {vael: [{"sp": "rongeroc", "born": st.tick}, {"sp": "nacrelles", "born": st.tick - int(WarBeasts.data()["elder_days"])}]}
	_ok(WarBeasts.check_release(st, vael, 0).contains("jeune"), "une jeune bête ne se lâche pas")
	_ok(WarBeasts.check_release(st, vael, 1) == "", "une ancienne se lâche")
	var up0 := int(Fleets.upkeep(st, vael).get("food", 0))
	var f := WarBeasts.release(st, vael, 1)
	_ok(f != null and f.ships[0] == "bete_nacrelle_ancien" and f.system_id == WarBeasts.vivarium_system(st, vael), "elle devient une Nacrelle ancienne au système du Vivarium")
	_ok(int(Fleets.upkeep(st, vael).get("food", 0)) > up0 and Combat.is_armed(f), "une bête de guerre armée, entretenue en vivres")
	_ok(Combat.ship_strength("bete_nacrelle_ancien") > Combat.ship_strength("bete_nacrelle_adulte") and Combat.ship_strength("bete_nacrelle_adulte") > Combat.ship_strength("bete_nacrelle"), "ancienne > adulte > sauvage")
	_ok(WarBeasts.beasts(st, vael).size() == 1, "elle quitte le Vivarium")
	_ok(SimCommands.validate(st, SimCommands.beast_release(vael, 0)) != "", "la commande refuse une bête trop jeune")


func _test_talents() -> void:
	var st := _new()
	var oss := _eid(st, "ossarane")
	var vael := _eid(st, "vael")
	var mur := _eid(st, "murmurants")
	var teyl := _eid(st, "teyl")
	var kh := _eid(st, "khthari")
	var bris := _eid(st, "brisecomete")
	var ch := _eid(st, "choeur")
	_ok(bool(Fauna.talent(st, oss).get("hunt_all", false)) and int(Fauna.talent(st, oss).get("triumph_pct", 0)) == 100, "honneur : Triomphe doublé, chasse de toutes les créatures")
	var tri := Guardians.triumph_scale(st, oss, 10, 40)
	_ok(int(tri[0]) == 20 and int(tri[1]) == 80, "honneur : Triomphe doublé (20 de stabilité, 80 d'influence)")
	var g := Fauna.spawn_herd(st, "rongeroc", FactionTraits.capital_system(st, oss), -1)
	var f := st.spawn_ship(oss, "fregate", g.system_id)
	_ok(Fauna.hunt_pct(st, f, [f, g]) > 0, "honneur : bonus de chasse sans la déclarer")
	var fv := st.spawn_ship(vael, "fregate", g.system_id)
	_ok(Fauna.hunt_pct(st, fv, [fv, g]) == 0, "les autres doivent déclarer la chasse")
	var full := int(Fauna.attitude_cost("etude").get("energy", 0))
	_ok(int(Fauna.attitude_cost_for(st, vael, "etude").get("energy", 0)) == full / 2, "raison : l'étude à moitié prix")
	_ok(Fauna.tamable(st, kh, "cristalloides") and not Fauna.tamable(st, vael, "cristalloides"), "survie : toutes les espèces s'apprivoisent")
	var nuee := Fauna.spawn_herd(st, "nuees", g.system_id, 0)
	_ok(not Fauna.hostile(st, nuee, mur) and Fauna.hostile(st, nuee, vael), "énergétique : les Nuées d'orage ne les voient pas")
	var stw := _new()
	var veil := stw.get_empire(_eid(stw, "teyl"))
	var vg: Dictionary = {}
	for s in stw.galaxy.systems:
		if stw.system_owner(s.id) < 0 and s.planet_ids.size() >= 2 and Fleets.fleets_at(stw, s.id).is_empty() and Guardians.awake_at(stw, s.id) == "" and not Fauna.nests(stw).has(s.id):
			if not Guardians.list(stw).has("veilleur"):
				Guardians._create(stw, "veilleur", s.id)
			vg = Guardians.list(stw)["veilleur"]
			break
	var vsid := Guardians.fleet_system(stw, "veilleur")
	_ok(not Guardians.hostile(stw, "veilleur", veil.id) and Guardians.hostile(stw, "veilleur", _eid(stw, "vael")), "synthétique : le Veilleur parlemente")
	_ok(Guardians.colony_block(stw, vsid, veil.id) == "" and Guardians.colony_block(stw, vsid, _eid(stw, "vael")) != "", "synthétique : on peut coloniser chez un gardien machine")
	# Profit : safaris près d'un nid.
	var nest := Fauna.nest_ids(st)[0]
	var c := Colony.new()
	var pid := -1
	for s in st.galaxy.systems:
		if pid < 0 and st.system_owner(s.id) < 0 and s.planet_ids.size() > 0 and s.neighbors.has(nest):
			pid = s.planet_ids[0]
	if pid < 0:
		pid = st.galaxy.systems[nest].planet_ids[0]
	c.planet_id = pid
	c.owner = bris
	c.kind = Colony.KIND_COLONY
	c.population = 3
	st.add_colony(c)
	_ok(Fauna.safari_income(st, bris) >= int(Fauna.talent(st, bris)["safari"]) and Fauna.safari_income(st, vael) == 0, "profit : les safaris rapportent près des nids (%d)" % Fauna.safari_income(st, bris))
	# Foi : un gardien vivant près de ses colonies est vénéré.
	var gid := ""
	for x in Guardians.ids(st):
		if String(Guardians.list(st)[x]["status"]) == "awake":
			gid = x
	var gsid := Guardians.fleet_system(st, gid)
	var c2 := Colony.new()
	var pid2 := -1
	for s in st.galaxy.systems:
		if pid2 < 0 and st.system_owner(s.id) < 0 and s.planet_ids.size() > 0 and s.neighbors.has(gsid):
			pid2 = s.planet_ids[0]
	c2.planet_id = pid2
	c2.owner = ch
	c2.kind = Colony.KIND_COLONY
	c2.population = 3
	st.add_colony(c2)
	_ok(Fauna.venerated(st, ch) >= 1 and not Fauna.stability_parts(st, ch).is_empty(), "foi : le gardien voisin est vénéré (stabilité)")
	_ok(Fauna.venerated(st, vael) == 0, "les autres ne vénèrent rien")
	_ok(Fauna.talent_labels(st, oss).size() >= 1, "les talents s'affichent")


func _test_slayer() -> void:
	var h := {"name": "Amirale Test", "owner": 0, "traits": []}
	var st := _new()
	var added: Array[Dictionary] = []
	Guardians.monster_slayer(st, h, added)
	_ok((h["traits"] as Array).has("tueur_monstres"), "l'amiral gagne « Tueur de monstres »")
	_ok(not Heroes.class_traits("stratege").has("tueur_monstres"), "ce trait ne se tire jamais au sort")
	_ok(Heroes.trait_fx(h, "fauna_damage_pct") == 25, "+25 % de dégâts contre les créatures")


func _test_pirates() -> void:
	var st := GameState.create(11, 150, 1800.0, "", {"ai_level": "", "creatures": "grouillantes", "pirates": "infestes"})
	var tamed := 0
	for sid in Pirates.lair_ids(st):
		var g := Pirates.guard_fleet(st, sid)
		if g == null:
			continue
		for s in g.ships:
			if String(GameData.ship(s).get("tamed", "")) != "":
				tamed += 1
	var expect := 0
	for sid in Pirates.lair_ids(st):
		if Pirates.tamed_beast(st, sid) != "":
			expect += 1
	_ok(tamed == expect, "les repaires proches d'un nid ont dressé une bête (%d sur %d repaires)" % [tamed, Pirates.lair_ids(st).size()])


func _test_save() -> void:
	var sim := Simulation.new(_new(17))
	var st := sim.state
	var vael := _eid(st, "vael")
	var nest := _nacre_nest(st)
	_tame(st, vael, "nacrelles")
	_cap_colony(st, vael).buildings.append("vivarium")
	st.spawn_ship(vael, "chalutier", nest)
	st.fauna["beasts"] = {vael: [{"sp": "nacrelles", "born": 0}]}
	sim.advance(10)
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(st.to_snapshot())))
	_ok(back != null and back.checksum() == st.checksum(), "bêtes et filets sauvegardés (même empreinte)")
	if back == null:
		return
	var a := Simulation.new(st)
	var b := Simulation.new(back)
	a.advance(60)
	b.advance(60)
	_ok(a.state.checksum() == b.state.checksum() and WarBeasts.beasts(b.state, vael).size() == WarBeasts.beasts(a.state, vael).size(), "la partie reprise capture à l'identique")
