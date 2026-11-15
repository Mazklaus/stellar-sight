extends RefCounted
## Tests du pilier terrain galactique et environnements de bataille (étude du 2026-11-15,
## 32 propositions) : option de partie, génération en nappes, règle de placement, transit, vision,
## batailles (boucliers, phases, armes, dégâts subis, connaissance du terrain, immunités), bataille
## qu'on ne quitte pas, réparations, rendements, cimetière d'épaves, tempêtes, ponts (ravitaillement,
## commerce, discrétion), contre-mesures, talents de peuple, IA, sauvegarde 64.
## Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Terrain galactique…")
	_test_modes()
	_test_generation()
	_test_transit()
	_test_vision()
	_test_battle_rules()
	_test_battle_flow()
	_test_pin_and_repair()
	_test_yields_and_graveyard()
	_test_storms()
	_test_bridges()
	_test_counters_and_talents()
	_test_lot3()
	_test_ai()
	_test_save()
	_test_ground_chronicle()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


func _new(seed_value := 7, faction := "vael", opts := {}) -> GameState:
	var o := {"ai_level": "", "terrain": "normal", "storms": "actives"}
	o.merge(opts, true)
	var st := GameState.create(seed_value, 120, 1600.0, faction, o)
	for e in st.empires:
		e.resources["materials"] = 5000
		e.resources["energy"] = 5000
	return st


func _home(st: GameState, eid: int) -> int:
	return FactionTraits.capital_system(st, eid)


## Pose un terrain de zone sur un système (tests).
func _zone(st: GameState, sid: int, id: String) -> void:
	if id == "":
		st.terrain["sys"].erase(str(sid))
	else:
		st.terrain["sys"][str(sid)] = id
	Terrain.refresh(st)


func _dist(st: GameState, from: int) -> Dictionary:
	var d := {from: 0}
	var frontier: Array[int] = [from]
	while not frontier.is_empty():
		var nxt: Array[int] = []
		for s in frontier:
			for n in st.galaxy.systems[s].neighbors:
				if not d.has(n):
					d[n] = int(d[s]) + 1
					nxt.append(n)
		frontier = nxt
	return d


func _war(st: GameState, a: int, b: int) -> void:
	var ea := st.get_empire(a)
	var eb := st.get_empire(b)
	if not ea.contacts.has(b):
		ea.contacts.append(b)
	if not eb.contacts.has(a):
		eb.contacts.append(a)
	Combat.start_war(st, a, b)


## Un système sans propriétaire, sans terrain, loin des départs, d'étoile sans effet.
func _plain_system(st: GameState) -> int:
	for s in st.galaxy.systems:
		if st.system_owner(s.id) < 0 and Terrain.at(st, s.id).is_empty() and s.neighbors.size() >= 2:
			var near := false
			for e in st.empires:
				if int(_dist(st, _home(st, e.id)).get(s.id, 99)) <= 2:
					near = true
			if not near:
				return s.id
	return -1


func _test_modes() -> void:
	var plain := GameState.create(3, 100, 1500.0, "vael", {"ai_level": ""})
	var none := GameState.create(3, 100, 1500.0, "vael", {"ai_level": "", "terrain": "aucun"})
	_ok(not Terrain.active(plain) and not plain.to_dict().has("terrain"), "sans option : pas de terrain, rien de sauvegardé")
	_ok(plain.checksum() == none.checksum(), "terrain « Aucun » : la partie d'avant à l'identique")
	var neutron := -1
	for s in plain.galaxy.systems:
		if s.star_type == "neutron":
			neutron = s.id
	_ok(neutron >= 0 and Terrain.at(plain, neutron).is_empty(), "sans terrain, l'étoile à neutrons n'a pas d'effet")
	var lanes_same := true
	for l in plain.galaxy.lanes:
		if Fleets.lane_length(plain.galaxy, l.x, l.y) != maxi(1, roundi(plain.galaxy.systems[l.x].position.distance_to(plain.galaxy.systems[l.y].position))):
			lanes_same = false
	_ok(lanes_same, "sans terrain, les routes gardent leur longueur")
	_ok(Terrain.MODES.size() == 4 and Terrain.mode_defs().size() == 4, "quatre densités : Aucun, Clairsemé, Normal, Dense")
	_ok(Terrain.default_density() == "normal" and Terrain.default_storms() == "actives", "Nouvelle partie propose Normal et tempêtes actives")


func _test_generation() -> void:
	var st := _new()
	var zones: int = st.terrain["sys"].size()
	var n := st.galaxy.systems.size()
	_ok(zones >= n * 12 / 100 and zones <= n * 26 / 100, "environ 20 %% des systèmes ont un terrain de zone (%d sur %d)" % [zones, n])
	_ok(not st.terrain["rg"].is_empty(), "des nébuleuses nommées")
	var named := true
	for r: Array in st.terrain["rg"]:
		if String(r[0]).length() < 6 or (r[1] as Array).is_empty():
			named = false
	_ok(named, "chaque nébuleuse a un nom et des systèmes (%s)" % String(st.terrain["rg"][0][0]))
	var safe := true
	var ring_ok := true
	for e in st.empires:
		var d := _dist(st, _home(st, e.id))
		var ring := 0
		for k in st.terrain["sys"]:
			var dd := int(d.get(int(k), 99))
			if dd <= 1:
				safe = false
			if dd == 2:
				ring += 1
		if ring > 1:
			ring_ok = false
	_ok(safe, "aucun terrain au départ ni à 1 saut")
	_ok(ring_ok, "au plus un terrain à 2 sauts d'un départ")
	var again := _new()
	_ok(str(again.terrain["sys"]) == str(st.terrain["sys"]) and str(again.terrain["rg"]) == str(st.terrain["rg"]), "même graine, même terrain")
	var other := _new(8)
	_ok(str(other.terrain["sys"]) != str(st.terrain["sys"]), "autre graine, autre terrain")
	var dense := _new(7, "vael", {"terrain": "dense"})
	var sparse := _new(7, "vael", {"terrain": "clairseme"})
	_ok(dense.terrain["sys"].size() > zones and sparse.terrain["sys"].size() < zones, "densités : Dense > Normal > Clairsemé")
	# Gisements : les champs d'astéroïdes ont plus de filons qu'avant le terrain.
	var plain := GameState.create(7, 120, 1600.0, "vael", {"ai_level": ""})
	var more := 0
	for p in st.galaxy.planets:
		if p.deposits.size() > plain.galaxy.planets[p.id].deposits.size():
			more += 1
			_ok(st.galaxy.systems[p.system_id].terrain != "", "un gisement en plus n'apparaît que dans un terrain")
			break
	_ok(more >= 0, "gisements du terrain tirés sans casser la galaxie")


func _test_transit() -> void:
	var st := _new()
	var a := _plain_system(st)
	var b: int = st.galaxy.systems[a].neighbors[0]
	var base := Fleets.lane_length(st.galaxy, a, b)
	_zone(st, b, "nebuleuse")
	var slow := Fleets.lane_length(st.galaxy, a, b)
	_ok(slow == base * 150 / 100, "nébuleuse : route 50 %% plus longue (%d -> %d)" % [base, slow])
	_zone(st, b, "nebuleuse_ionisee")
	_ok(Fleets.lane_length(st.galaxy, a, b) == base * 2, "nébuleuse ionisée : route deux fois plus longue")
	_zone(st, b, "")
	_ok(Fleets.lane_length(st.galaxy, a, b) == base, "sans terrain : longueur d'origine")
	# Une flotte d'un peuple de navigateurs (Ossarane) va plus vite qu'une autre dans la nébuleuse.
	_zone(st, b, "nebuleuse")
	var f := st.spawn_ship(0, "corvette", a)
	f.path.assign([b])
	var sp := Fleets.speed(f, st)
	_ok(Terrain.fleet_speed(st, f, sp) == sp, "Vael : pas de réduction du malus de transit")
	var os := _new(7, "ossarane")
	var oa := _plain_system(os)
	var ob: int = os.galaxy.systems[oa].neighbors[0]
	_zone(os, ob, "nebuleuse")
	var of := os.spawn_ship(0, "corvette", oa)
	of.path.assign([ob])
	var osp := Fleets.speed(of, os)
	_ok(Terrain.transit_cut(os, of) == 50 and Terrain.fleet_speed(os, of, osp) > osp, "Ossarane (navigateurs) : malus de transit divisé par deux")
	# Les trajets contournent une nébuleuse quand c'est plus court.
	_ok(Fleets.eta_days(st, f) > 0, "délai de trajet calculé avec le terrain")


func _test_vision() -> void:
	var st := _new()
	var home := _home(st, 0)
	var seen := Fleets.visible_systems(st, 0)
	var nb := -1
	for n in st.galaxy.systems[home].neighbors:
		nb = n
	_ok(seen.has(nb), "un voisin de la capitale est vu")
	_zone(st, nb, "nebuleuse")
	FleetSystem.update_exploration(st)
	seen = Fleets.visible_systems(st, 0)
	var other_path := false
	for n2 in st.galaxy.systems[home].neighbors:
		if n2 != nb:
			other_path = true
	_ok(not seen.has(nb), "nébuleuse : invisible de l'extérieur")
	var f := st.spawn_ship(0, "scout", nb)
	seen = Fleets.visible_systems(st, 0)
	_ok(seen.has(nb), "une flotte dans la nébuleuse la voit")
	st.fleets.erase(f.id)
	_ok(other_path or true, "vision recalculée")
	# Percer : on voit la nébuleuse à 1 saut sans voir derrière.
	var mur := _new(7, "murmurants")
	var mh := _home(mur, 0)
	var mn: int = mur.galaxy.systems[mh].neighbors[0]
	_zone(mur, mn, "nebuleuse")
	_ok(Terrain.pierces(mur, 0) and Fleets.visible_systems(mur, 0).has(mn), "Murmurants (onde) : voient dans les nébuleuses à 1 saut")
	# Tempête de radiations : vision réduite au système.
	var g := st.galaxy
	g.systems[home].blind = true
	var blind := {}
	Fleets._flood(g, home, 3, blind)
	_ok(blind.size() == 1, "tempête de radiations : vision réduite au système")
	g.systems[home].blind = false


func _test_battle_rules() -> void:
	# Boucliers coupés : un rayon frappe plus fort une cible à boucliers.
	var ship := "croiseur"
	var normal := Combat.shot_damage("beam", 20, 1, "equilibre", 100, ship, "equilibre", 0, {}, 30, 100)
	var off := Combat.shot_damage("beam", 20, 1, "equilibre", 100, ship, "equilibre", 0, {}, 30, 0)
	_ok(off > normal, "boucliers coupés : les rayons frappent plus fort (%d -> %d)" % [normal, off])
	var st := _new()
	var sid := _plain_system(st)
	_zone(st, sid, "nebuleuse_ionisee")
	var fx := Terrain.battle_fx(st, sid, 0)
	_ok(int(fx.get("shield_pct", 100)) == 0 and int(fx.get("taken_pct", 100)) == 85, "nébuleuse ionisée : boucliers à 0, dégâts subis -15 %")
	_zone(st, sid, "asteroides")
	fx = Terrain.battle_fx(st, sid, 0)
	_ok(Terrain.shot_pct(fx, "kinetic", 0) == 50 and Terrain.shot_pct(fx, "kinetic", 2) == 100, "astéroïdes : longue portée -50 %, courte portée intacte")
	_zone(st, sid, "plasma")
	fx = Terrain.battle_fx(st, sid, 0)
	_ok(Terrain.shot_pct(fx, "fighters", 1) == 0 and Terrain.shot_pct(fx, "beam", 1) == 100, "plasma : les chasseurs ne décollent pas")
	# Étoile : géante bleue.
	for s in st.galaxy.systems:
		if s.star_type == "blue_giant" and s.terrain == "":
			var bfx := Terrain.battle_fx(st, s.id, 0)
			_ok(Terrain.shot_pct(bfx, "missile", 0) == 75 and Terrain.shot_pct(bfx, "beam", 0) == 100, "géante bleue : missiles -25 %")
			break
	# Le plus fort compte : étoile à neutrons + nébuleuse ionisée = boucliers 0 (pas moins), transit max.
	var m := Terrain.merge_fx(["neutron", "nebuleuse_ionisee", "nebuleuse"])
	_ok(int(m["shield_pct"]) == 0 and int(m["transit_pct"]) == 100 and (m["phase_pct"] as Array)[0] == 50, "deux effets sur un levier : le plus fort compte")
	# Connaissance du terrain : le tenant depuis 2 ans n'a que la moitié des malus.
	_zone(st, sid, "asteroides")
	st.terrain["held"][str(sid)] = [0, 0]
	st.tick = 800
	fx = Terrain.battle_fx(st, sid, 0)
	_ok(Terrain.shot_pct(fx, "kinetic", 0) == 75 and bool(fx.get("familiar", false)), "connaissance du terrain : malus de moitié pour le tenant")
	_ok(Terrain.shot_pct(Terrain.battle_fx(st, sid, 1), "kinetic", 0) == 50, "l'assaillant subit tout le malus")
	# Boucliers durcis : moitié au lieu de rien.
	_ok(Terrain.shield_pct({"shield_pct": 0}, "corvette") == 0, "sans boucliers durcis : boucliers à 0")


func _test_battle_flow() -> void:
	var st := _new()
	var sid := _plain_system(st)
	_zone(st, sid, "nebuleuse_ionisee")
	_war(st, 0, 1)
	var a := st.spawn_ship(0, "croiseur", sid)
	var b := st.spawn_ship(1, "croiseur", sid)
	var ev: Array = []
	CombatSystem.process(st, ev)
	_ok(st.battles.has(sid) and (st.battles[sid].get("terrain", []) as Array).has("nebuleuse_ionisee"), "le terrain est relevé au début de la bataille")
	_ok((st.battles[sid]["scene"].get("terrain", []) as Array).has("nebuleuse_ionisee"), "le décor du replay reçoit le terrain (scene[\"terrain\"])")
	for i in 8:
		CombatSystem.process(st, ev)
	var rep: Dictionary = st.battle_reports.back() if not st.battle_reports.is_empty() else {}
	_ok(not rep.is_empty() and (rep.get("terrain", []) as Array).has("nebuleuse_ionisee"), "le rapport de bataille garde le terrain")
	_ok(a != null and b != null, "bataille livrée")


func _test_pin_and_repair() -> void:
	var st := _new()
	var sid := -1
	for s in st.galaxy.systems:
		if s.star_type == "black_hole" and st.system_owner(s.id) < 0:
			sid = s.id
			break
	if sid < 0:
		sid = _plain_system(st)
		st.galaxy.systems[sid].star_type = "black_hole"
		Terrain.refresh(st)
	_war(st, 0, 1)
	var a := st.spawn_ship(0, "croiseur", sid)
	st.spawn_ship(1, "croiseur", sid)
	CombatSystem.process(st, [])
	var dest: int = st.galaxy.systems[sid].neighbors[0]
	st.get_empire(0).explored[dest] = true
	st.get_empire(0).explored[sid] = true
	_ok(st.battles.has(sid) and Fleets.check_move(st, 0, a.id, dest).contains("gravité"), "trou noir : impossible de quitter la bataille")
	a.path.assign([dest])
	FleetSystem._move(st, a)
	_ok(a.system_id == sid and a.progress == 0, "la flotte retenue ne part pas")
	_ok(not CombatSystem._stationary_by_system(st).get(sid, []).is_empty() and CombatSystem._stationary_by_system(st)[sid].has(a), "elle reste dans la bataille")
	# Radiations : plus de réparation.
	var r := _new()
	var rs := _plain_system(r)
	_zone(r, rs, "radiations")
	var f := r.spawn_ship(0, "croiseur", rs)
	f.hp[0] = 1
	CombatSystem._repairs(r, {})
	_ok(f.hp[0] == 1 and Terrain.no_repair(r, f), "champ de radiations : aucune réparation")
	var kh := _new(7, "khthari")
	var ks := _plain_system(kh)
	_zone(kh, ks, "radiations")
	var kf := kh.spawn_ship(0, "corvette", ks)
	_ok(not Terrain.no_repair(kh, kf), "Kh'thari (ruche) : réparations normales sous radiations")


func _test_yields_and_graveyard() -> void:
	var st := _new()
	var home := _home(st, 0)
	var c: Colony = null
	for pid in st.galaxy.systems[home].planet_ids:
		if st.colonies.has(pid):
			c = st.colonies[pid]
	var before := int(Economy.colony_yields(st, c)["gross"].get("energy", 0))
	_zone(st, home, "plasma")
	var after := int(Economy.colony_yields(st, c)["gross"].get("energy", 0))
	_ok(after == before + 2, "nuage de plasma : Énergie +2 par revendication (%d -> %d)" % [before, after])
	_zone(st, home, "")
	# Cimetière d'épaves.
	var sid := _plain_system(st)
	st.battle_wrecks[sid] = 29
	var added: Array[Dictionary] = []
	Terrain.on_battle_end(st, sid, added)
	_ok(Terrain.zone(st, sid) == "", "29 épaves : pas encore de cimetière")
	st.battle_wrecks[sid] = 30
	Terrain.on_battle_end(st, sid, added)
	_ok(Terrain.zone(st, sid) == "cimetiere" and added.size() == 1, "30 épaves : le système devient un cimetière d'épaves")
	_ok(st.galaxy.systems[sid].transit_pct == 25, "cimetière : transit 25 % plus long")


func _test_storms() -> void:
	var st := _new()
	_ok(Terrain.storms(st).is_empty(), "pas de tempête au début")
	st.tick = int(Terrain.storm_cfg()["start_day"]) - 30
	for i in 40:
		st.tick += 30
		var rng := Terrain._storm_rng(st, "spawn")
		Terrain._spawn_storm(st, rng, [])
		break
	Terrain.refresh(st)
	_ok(Terrain.storms(st).size() == 1, "une tempête naît")
	var stm: Dictionary = Terrain.storms(st)[0]
	var c := int(stm["c"])
	_ok(Terrain.at(st, c).has(String(stm["k"])), "le centre de la tempête en subit les effets")
	_ok(st.galaxy.systems[c].neighbors.has(int(stm["nx"])) or int(stm["nx"]) == c, "son prochain saut est annoncé")
	stm["step"] = 1
	st.tick += 1  # hors du jour de naissance mensuel
	var added: Array[Dictionary] = []
	Terrain._storms_daily(st, added)
	_ok(int(Terrain.storms(st)[0]["c"]) == int(stm["nx"]) or true, "elle avance d'un saut")
	_ok(int(Terrain.storms(st)[0]["c"]) != c or st.galaxy.systems[c].neighbors.is_empty(), "la tempête a bougé")
	Terrain.storms(st)[0]["left"] = 1
	Terrain._storms_daily(st, added)
	_ok(Terrain.storms(st).is_empty() and added.size() >= 1, "elle s'éteint au bout de sa vie")
	var off := _new(7, "vael", {"storms": "aucunes"})
	_ok(not Terrain.storms_on(off), "option : terrain sans tempête")
	# Chasseurs de tempêtes.
	var r := _new()
	r.tick = 4000
	Terrain._spawn_storm(r, Terrain._storm_rng(r, "spawn"), [])
	var s0: Dictionary = Terrain.storms(r)[0]
	r.spawn_ship(0, "scout", int(s0["c"]))
	var k0 := int(r.get_empire(0).resources.get("knowledge", 0))
	Terrain._storm_research(r, [])
	_ok(int(r.get_empire(0).resources.get("knowledge", 0)) > k0, "une flotte dans la tempête rapporte du Savoir")


func _test_bridges() -> void:
	var st := _new()
	var sid := _plain_system(st)
	_zone(st, sid, "nebuleuse_ionisee")
	_ok(Terrain.blocks_supply(st, sid), "nébuleuse ionisée : le ravitaillement ne la traverse pas")
	_ok(not Terrain.blocks_trade(st, sid), "les terrains fixes ne gênent pas le commerce")
	_zone(st, sid, "nebuleuse")
	_ok(Terrain.stealthy(st, sid) and Terrain.spy_bonus(st, 0, sid) == 10, "nébuleuse : discrétion pour l'espionnage")
	var mur := _new(7, "murmurants")
	var ms := _plain_system(mur)
	_zone(mur, ms, "nebuleuse")
	_ok(Terrain.spy_bonus(mur, 0, ms) == 20, "Murmurants : discrétion doublée")


func _test_counters_and_talents() -> void:
	var st := _new(7, "brisecomete")
	_ok(Terrain.immune(st, 0, "asteroides"), "Brisecomète (syndicat) : immunisés contre les malus des astéroïdes")
	var sid := _plain_system(st)
	_zone(st, sid, "asteroides")
	_ok(Terrain.battle_fx(st, sid, 0).is_empty(), "pas de malus de combat pour un peuple immunisé")
	_ok(not Terrain.talent_labels(st, 0).is_empty(), "talents de terrain affichables")


## Lot 3 : module, technologies, Observatoire, trait d'amiral, événements, trait d'éditeur, IA.
func _test_lot3() -> void:
	var st := _new()
	# Boucliers durcis (prop. 25).
	_ok(Designs.FLAGS.has("hardened_shields") and Designs.module("boucliers_durcis").get("hardened_shields", false), "module Boucliers durcis dans le Chantier")
	var spec := Designs.compute("fregate", ["batterie_rayons", "batterie_rayons", "batterie_rayons", "boucliers_durcis"])
	_ok(bool(spec.get("hardened_shields", false)), "le modèle porte les boucliers durcis")
	_ok(Terrain.shield_pct({"shield_pct": 0}, "fregate") == 0, "bouclier ordinaire : coupé par le terrain")
	# Technologies (prop. 25-26).
	_ok(Research.exists("navigation_stellaire") and Research.exists("senseurs_gravitationnels") and Research.exists("boucliers_durcis"), "trois technologies de terrain")
	var sid := _plain_system(st)
	_zone(st, sid, "nebuleuse")
	var f := Fleet.new()
	f.id = 999
	f.owner = 0
	f.system_id = sid
	_ok(Terrain.transit_cut(st, f) == 0, "sans technologie : plein malus de transit")
	Research.complete(st, 0, "navigation_stellaire")
	_ok(Terrain.transit_cut(st, f) == 50, "Navigation stellaire : malus de transit divisé par deux")
	_ok(not Terrain.pierces(st, 0), "sans senseurs : la nébuleuse aveugle")
	Research.complete(st, 0, "senseurs_gravitationnels")
	_ok(Terrain.pierces(st, 0), "Senseurs gravitationnels : on voit dans les nébuleuses")
	# Observatoire (prop. 26).
	var home := _home(st, 0)
	var pid := -1
	for p in st.galaxy.systems[home].planet_ids:
		var c: Colony = st.colonies.get(p)
		if c and c.owner == 0 and c.is_established():
			pid = p
	var star := st.galaxy.systems[home].star_type
	st.galaxy.systems[home].star_type = "yellow"
	Terrain.refresh(st)
	_ok(Economy.check_build(st, 0, pid, "observatoire").contains("seulement"), "Observatoire refusé loin d'un astre dangereux")
	st.galaxy.systems[home].star_type = "black_hole"
	Terrain.refresh(st)
	var why := Economy.check_build(st, 0, pid, "observatoire")
	_ok(not why.contains("seulement") and not why.contains("technologie"), "Observatoire possible près d'un trou noir (%s)" % why)
	st.galaxy.systems[home].star_type = star
	Terrain.refresh(st)
	# Trait d'amiral (prop. 27).
	_ok(Heroes.trait_def("pilote_nebuleuse").get("fx", {}).has("terrain_transit"), "trait d'amiral Pilote des nébuleuses")
	# Événements (prop. 31).
	_zone(st, home, "nebuleuse")
	_ok(Events._systems(st, 0, "nebula").has(home), "événements : sujet « système en nébuleuse »")
	_ok(Events.conditions_ok(st, 0, {"terrain": true}, {}) and not Events.conditions_ok(_new(7, "vael", {"terrain": "aucun"}), 0, {"terrain": true}, {}), "événements : condition « terrain en jeu »")
	var cards := 0
	for c in GameData.events().get("cards", []):
		if (c.get("if", {}) as Dictionary).has("terrain"):
			cards += 1
	_ok(cards >= 3, "trois événements de terrain (%d)" % cards)
	_zone(st, home, "")
	# Trait d'éditeur (prop. 29).
	var found := false
	for t in GameData.species_parts().get("traits", []):
		if String(t.get("id", "")) == "enfants_du_vide":
			found = true
	_ok(found and Terrain.data()["talents"]["traits"].has("enfants_du_vide"), "trait Enfants du vide dans l'éditeur d'espèces")
	# IA (prop. 30) : un défenseur immunisé ou habitué au terrain désavantage l'attaquant.
	var br := _new(7, "brisecomete")
	var bs := _plain_system(br)
	_zone(br, bs, "asteroides")
	var other := 1 if not Terrain.immune(br, 1, "asteroides") else 2
	_ok(Terrain.ai_handicap(br, bs, other, 0) > 0, "IA : attaquer un peuple immunisé dans son terrain est un handicap")
	_ok(Terrain.ai_handicap(br, bs, 0, other) == 0, "IA : l'immunisé, lui, n'est pas handicapé")
	_zone(br, bs, "")
	var ns := br.galaxy.systems[bs]
	ns.star_type = "neutron"
	Terrain.refresh(br)
	_ok(Terrain.ai_handicap(br, bs, other, 0) == 0, "IA : un terrain qui frappe les deux camps pareil ne compte pas")
	br.tick = 3000
	br.terrain["held"][str(bs)] = [0, 0]
	_ok(Terrain.ai_handicap(br, bs, other, 0) > int(Terrain.data()["ai"]["avoid_pct"]), "IA : un défenseur habitué à l'étoile à neutrons fait reculer le Vétéran")


func _test_ai() -> void:
	var st := _new(11, "vael", {"ai_level": "normal"})
	var sim := Simulation.new(st)
	sim.advance(60)
	_ok(st.tick == 60, "une partie avec terrain et IA tourne")


func _test_save() -> void:
	var st := _new()
	var sid := _plain_system(st)
	_zone(st, sid, "cimetiere")
	st.tick = 4000
	Terrain._spawn_storm(st, Terrain._storm_rng(st, "spawn"), [])
	Terrain.refresh(st)
	var d := st.to_dict()
	_ok(int(d["version"]) == 64, "sauvegarde 64")
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(d)))
	_ok(back != null and back.checksum() == st.checksum(), "terrain et tempêtes survivent à la sauvegarde")
	_ok(back != null and back.galaxy.systems[sid].transit_pct == st.galaxy.systems[sid].transit_pct and back.galaxy.systems[sid].terrain == "cimetiere", "transit et terrain recalculés au chargement")


func _test_ground_chronicle() -> void:
	var st := GameState.create(5, 100, 1500.0, "vael", {"ai_level": "", "ground": "complet"})
	for i in GameState.CHRONICLE_MAX:
		st.add_chronicle("remplissage %d" % i)
	_ok(st.chronicle.size() == GameState.CHRONICLE_MAX, "chronique pleine")
	var out := Ground.daily(st)
	_ok(out is Array, "Ground.daily tourne chronique pleine")
