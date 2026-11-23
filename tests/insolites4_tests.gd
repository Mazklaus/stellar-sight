extends RefCounted
## Tests des peuples insolites, lot 4 (étude « Les 15 peuples insolites et le 9e peuple », prop. 83 à
## 105, 106 à 111 pour leur part) : le temps et la vie autre. Gardiens du Sablier Fêlé (Registre,
## annulations, déchirures et effondrement, bulles, Chronopathie, la Boucle), Lithes de Gravéa (Œuvres
## lentes, Consensus séculaire, Patience, Hibernation, Remodelage), Sporemère de Myrr (comètes, mycélium,
## feu, réseau, spores, symbiose, Biosphère unique), Hallier de Vergemonde (trois âges, mondes-jardins,
## Cœur, Feu-qui-renouvelle, Grand Jardin), chocs des tons, partie de 10 ans jouée par l'IA,
## déterminisme, sauvegarde.

const ODD := ["sablier", "gravea", "myrr", "vergemonde"]

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Peuples insolites (lot 4)…")
	_test_data()
	_test_found()
	_test_sablier()
	_test_gravea()
	_test_myrr()
	_test_vergemonde()
	_test_tones()
	_test_ai_game()
	_test_born()


func _ok(cond: bool, what: String) -> void:
	print("  ", "ok " if cond else "KO ", what)
	_check.call(cond, what)


func _game(seed_value := 11, player := "ossarane", rivals: Array = ODD + ["choeur", "teyl"], extra := {}) -> GameState:
	var opts := {"ai_level": "", "rivals": rivals.duplicate()}
	opts.merge(extra)
	return GameState.create(seed_value, 150, 1800.0, player, opts)


func _eid(st: GameState, faction: String) -> int:
	for e in st.empires:
		if e.faction_id == faction:
			return e.id
	return -1


func _contact(st: GameState, a: int, b: int) -> void:
	for p in [[a, b], [b, a]]:
		if not st.get_empire(p[0]).contacts.has(p[1]):
			st.get_empire(p[0]).contacts.append(p[1])


func _cols(st: GameState, eid: int) -> Array[int]:
	var out: Array[int] = []
	for pid in st.sorted_colony_ids():
		var c: Colony = st.colonies[pid]
		if c.owner == eid and c.is_colony():
			out.append(int(pid))
	return out


func _labels(parts: Array) -> Array:
	var out := []
	for p in parts:
		out.append(String(p[0]) if p is Array else String(p.get("label", "")))
	return out


func _rich(st: GameState, eid: int) -> void:
	for r in ["energy", "materials", "knowledge", "influence", "food"]:
		st.get_empire(eid).resources[r] = 5000


func _colony(st: GameState, pid: int, eid: int, pop := 6) -> Colony:
	var c := Colony.new()
	c.planet_id = pid
	c.owner = eid
	c.kind = Colony.KIND_COLONY
	c.population = pop
	c.days_left = 0
	st.colonies[pid] = c
	st.rebuild_ownership()
	return c


## Une planète libre dans un système libre (ni colonie, ni propriétaire), la plus proche de from.
func _free_far(st: GameState, from: int, min_jumps := 1) -> int:
	var d: Dictionary = FactionTraits.jumps_from(st.galaxy, from)
	var best := -1
	var best_d := 999
	for sid in d:
		if int(d[sid]) < min_jumps or int(d[sid]) >= best_d or st.system_owner(int(sid)) >= 0:
			continue
		for pid in st.galaxy.systems[int(sid)].planet_ids:
			if not st.colonies.has(pid):
				best = int(pid)
				best_d = int(d[sid])
				break
	return best


func _test_data() -> void:
	var odd := GameData.insolite_faction_ids()
	var all_ok := true
	for fid in ODD:
		var f := GameData.faction(fid)
		all_ok = all_ok and odd.has(fid) and bool(f.get("insolite", false)) and String(f.get("broken_rule", "")) != "" \
				and Insolites.kind_of_faction(f) == fid and f.has("guest") and not Insolites.worldless(f)
	_ok(all_ok, "quatre peuples du temps et de la vie autre : fiche insolite, règle cassée, champ « guest »")
	var vic_ok := true
	for v in ["paradoxe", "remodelage", "biosphere", "grand_jardin"]:
		vic_ok = vic_ok and Victory.is_people(v) and Research.tech(Victory.tech_for(v)).get("victory", "") == v
	_ok(vic_ok, "quatre victoires de peuple, chacune avec sa technologie")
	_ok(Victory.people_ids_for(GameData.faction("sablier")).has("paradoxe") and Victory.people_ids_for(GameData.faction("gravea")).has("remodelage")
			and Victory.people_ids_for(GameData.faction("myrr")).has("biosphere") and Victory.people_ids_for(GameData.faction("vergemonde")).has("grand_jardin"),
			"chaque victoire va à son peuple")
	_ok(not Victory.people_ids_for(GameData.faction("vergemonde")).has("biosphere"), "la Biosphère unique reste au Myrr (le Hallier a son Grand Jardin : refonte de l'arbre, prop. 18)")
	_ok(String(GameData.faction("myrr").get("species", {}).get("archetype", "")) == "fongoide" and String(GameData.faction("vergemonde").get("species", {}).get("archetype", "")) == "vegetal",
			"deux archétypes nouveaux : fongoïde et végétal")
	_ok(not Psionics.form_def("chronopathie").is_empty(), "catalogue ouvert : la forme psionique Chronopathie")
	_ok(not Insolites.implant_def("mycelium").get("hidden", true), "le mycélium est un implant visible")


func _test_found() -> void:
	var st := _game()
	var ok := true
	for fid in ODD:
		ok = ok and _cols(st, _eid(st, fid)).size() >= 1
	_ok(ok, "les quatre peuples ont un monde natal")
	var s := _eid(st, "sablier")
	var h := InsSablier.hero(st, s)
	_ok(not h.is_empty() and bool(h.get("chronal", false)), "le Gardien chronal veille sur le Sablier")
	_ok(int(Insolites.emp(st, s)["sand"]) == Insolites.c_int("sablier", "sand_start", 40), "les Gardiens commencent avec un peu de Sable")
	_ok(Psionics.form(st, s) == "chronopathie", "la Chronarchie donne la Chronopathie")
	_ok(InsSablier.life_pct(st, s) > 100 and Heroes.life_years(st, s) > Heroes.life_years(st, _eid(st, "ossarane")), "les héros des Gardiens vivent plus longtemps")


func _test_sablier() -> void:
	var st := _game(13)
	var s := _eid(st, "sablier")
	var o := _eid(st, "ossarane")
	var added: Array[Dictionary] = []
	var ed := Insolites.emp(st, s)
	var cap := FactionTraits.capital_system(st, s)
	# Le Registre : un vaisseau perdu se note, s'annule, revient à la capitale.
	var f := st.spawn_ship(s, "corvette", cap)
	InsSablier.on_ship_lost(st, f, 0)
	_ok(InsSablier.ledger(st, s).size() == 1, "un vaisseau perdu entre au Registre")
	ed["sand"] = 10
	_ok(SimCommands.validate(st, SimCommands.ins_act(s, "undo", {"i": 0})) != "", "annuler coûte du Sable")
	ed["sand"] = 200
	var n0 := Fleets.fleets_at(st, cap, s).size()
	SimCommands.apply(st, SimCommands.ins_act(s, "undo", {"i": 0}))
	_ok(Fleets.fleets_at(st, cap, s).size() > n0 and InsSablier.ledger(st, s).is_empty(), "annulé : le vaisseau est à la capitale, le Registre se vide")
	_ok(InsSablier.tear_active(st, cap) and InsSablier.system_pct(st, cap) < 0, "chaque annulation déchire le système (production en baisse)")
	_ok(_labels(Insolites.stability_parts(st, cap, s)).has("Déchirure du temps"), "la déchirure pèse sur la stabilité")
	# Trop ancien : le sable fige.
	InsSablier.on_ship_lost(st, f, 0)
	st.tick += Insolites.c_int("sablier", "reg_days", 180) + 1
	_ok(InsSablier.check_undo(st, s, 0) != "", "un événement trop ancien ne s'annule plus")
	ed["reg"] = []
	# Effondrement : trois annulations au même endroit.
	var home: Colony = st.colonies[_cols(st, s)[0]]
	home.population = 10
	for _i in 2:
		InsSablier.on_ship_lost(st, f, 0)
		InsSablier.undo(st, s, 0, added)
	var collapsed := false
	for c in st.chronicle:
		collapsed = collapsed or String(c.get("text", "")).begins_with("Effondrement local")
	_ok(collapsed and home.population == 5, "trois passés défaits au même endroit : effondrement, moitié de la population (%d)" % home.population)
	# Système conquis : annulé, il revient.
	_contact(st, s, o)
	var csid := st.galaxy.get_planet(home.planet_id).system_id
	InsSablier.on_capture(st, csid, o, s)
	home.owner = o
	st.rebuild_ownership()
	ed["sand"] = 200
	st.insolites["tears"] = {}
	_ok(InsSablier.check_undo(st, s, InsSablier.ledger(st, s).size() - 1) == "", "un système conquis s'annule")
	InsSablier.undo(st, s, InsSablier.ledger(st, s).size() - 1, added)
	_ok(home.owner == s and st.system_owner(csid) == s, "la conquête n'a jamais eu lieu")
	# Technologie volée.
	var oe := st.get_empire(o)
	oe.research_shelf["x_test"] = 100
	InsSablier.on_tech_stolen(st, o, s, "x_test", 60)
	InsSablier.undo(st, s, InsSablier.ledger(st, s).size() - 1, added)
	_ok(int(oe.research_shelf.get("x_test", 0)) == 40, "une technologie volée ne l'a jamais été (le voleur perd l'avance)")
	# Point fixe : le Gardien chronal.
	var hid := int(ed["hero"])
	ed["loop"] = 2
	Heroes.die(st, st.heroes[hid], "tombe au combat", added)
	_ok(int(ed["hero"]) == -1 and int(ed["loop"]) == 0, "la mort du Gardien chronal est un point fixe : la Boucle se défait")
	var noted := false
	for en: Dictionary in InsSablier.ledger(st, s):
		noted = noted or String(en["k"]) == "hero"
	_ok(not noted, "cette mort-là n'entre pas au Registre")
	st.tick = int(ed["back"])
	InsSablier.daily(st, s, ed, false, added)
	_ok(not InsSablier.hero(st, s).is_empty(), "un nouveau Gardien chronal vient, des années plus tard")
	# Bulles.
	ed["sand"] = 200
	ed["bub"] = 0
	_ok(SimCommands.validate(st, SimCommands.ins_act(s, "bubble", {"s": cap, "mode": "dilatation"})) != "", "la Dilatation ne se pose pas chez soi")
	st.insolites["tears"] = {}
	SimCommands.apply(st, SimCommands.ins_act(s, "bubble", {"s": cap, "mode": "compression"}))
	_ok(InsSablier.system_pct(st, cap) == Insolites.c_int("sablier", "bubble_pct", 25), "Compression : la production du système monte")
	_ok(SimCommands.validate(st, SimCommands.ins_act(s, "bubble", {"s": cap, "mode": "compression"})) != "", "une bulle par an")
	# Chronopathie.
	ed["sand"] = 0
	InsSablier.psi_effect(st, s, "sable_rendu", -1, added)
	_ok(int(ed["sand"]) > 0, "Chronopathie : le Sable rendu")
	# La Boucle et la victoire.
	_rich(st, s)
	_ok(InsSablier.check_loop(st, s) != "", "la Boucle demande sa technologie")
	st.get_empire(s).techs["paradoxe_stable"] = true
	SimCommands.apply(st, SimCommands.ins_act(s, "loop"))
	_ok(not (ed["lp"] as Dictionary).is_empty(), "une étape de la Boucle est en chantier")
	ed["lp"] = {"left": 1}
	InsSablier.daily(st, s, ed, false, added)
	_ok(int(ed["loop"]) == 1, "l'étape se ferme")
	ed["loop"] = 3
	_ok(Victory.progress(st, s, "paradoxe")["cond"], "victoire : le Paradoxe stable")


func _test_gravea() -> void:
	var st := _game(17)
	var g := _eid(st, "gravea")
	var o := _eid(st, "ossarane")
	var added: Array[Dictionary] = []
	var ed := Insolites.emp(st, g)
	_rich(st, g)
	var cap := FactionTraits.capital_system(st, g)
	var target := -1
	for pid in st.galaxy.systems[cap].planet_ids:
		if not st.colonies.has(pid):
			target = int(pid)
			break
	if target < 0:
		target = int(st.galaxy.systems[cap].planet_ids[0])
		st.colonies.erase(target)
		st.rebuild_ownership()
	st.override_planet(target, {"type": "barren"})
	_ok(SimCommands.validate(st, SimCommands.ins_act(g, "work", {"w": "habitable", "pid": target})).contains("technologie"), "Œuvres par ère : rendre un monde habitable attend l'Œuvre du souffle")
	Research.grant(st, g, ["oeuvre_souffle"])
	_ok(SimCommands.validate(st, SimCommands.ins_act(g, "work", {"w": "habitable", "pid": target})) == "", "une Œuvre lente peut commencer")
	SimCommands.apply(st, SimCommands.ins_act(g, "work", {"w": "habitable", "pid": target}))
	var works: Array = ed["works"]
	_ok(works.size() == 1 and int(works[0]["left"]) >= 3600, "elle prendra plus de dix ans")
	_ok(SimCommands.validate(st, SimCommands.ins_act(g, "work", {"w": "fondre", "pid": target})) != "", "une seule Œuvre par système")
	# Patience.
	ed["time"] = 300
	var left0 := int(works[0]["left"])
	SimCommands.apply(st, SimCommands.ins_act(g, "hasten", {"i": 0}))
	_ok(int(works[0]["left"]) == left0 - 300 and int(ed["time"]) == 0, "la Patience dépense son Temps d'un coup")
	ed["acted"] = 0
	st.tick += 360
	InsGravea.daily(st, g, ed, true, added)
	_ok(int(ed["time"]) > 0, "sans rien entreprendre, le Temps s'accumule")
	works[0]["left"] = 1
	InsGravea.daily(st, g, ed, false, added)
	_ok(st.galaxy.get_planet(target).type == "continental" and (ed["done"] as Dictionary).has(str(cap)), "l'Œuvre achevée change la forme du monde")
	# Consensus séculaire.
	_contact(st, g, o)
	_ok(Insolites.war_block(st, g, o) != "", "pas de guerre sans délibération")
	SimCommands.apply(st, SimCommands.ins_act(g, "deliberate", {"t": o}))
	_ok(Insolites.war_block(st, g, o) != "", "le consensus se forme deux ans")
	st.tick += Insolites.c_int("gravea", "cons_days", 720) + 1
	_ok(Insolites.war_block(st, g, o) == "", "consensus mûr : la guerre est possible")
	# Hibernation.
	var home := _cols(st, g)[0]
	_ok(SimCommands.validate(st, SimCommands.ins_act(g, "sleep", {"pid": home})) != "", "on n'hiberne que sous la menace")
	Combat.start_war(st, o, g)
	st.spawn_ship(o, "corvette", cap)
	_ok(SimCommands.validate(st, SimCommands.ins_act(g, "sleep", {"pid": home})) == "", "un monde attaqué peut s'endormir")
	SimCommands.apply(st, SimCommands.ins_act(g, "sleep", {"pid": home}))
	_ok(Insolites.target_block(st, cap) != "", "un monde endormi ne s'envahit pas")
	_ok(Insolites.colony_pct(st, home) == 0, "il ne produit plus rien")
	st.tick += Insolites.c_int("gravea", "sleep_days", 1080) + 1
	InsGravea.daily(st, g, ed, true, added)
	_ok(Insolites.target_block(st, cap) == "" and Insolites.colony_pct(st, home) == 100, "il se réveille")
	# Victoire.
	for i in 5:
		(ed["done"] as Dictionary)[str(1000 + i)] = "fondre"
	st.get_empire(g).techs["remodelage"] = true
	_ok(Victory.progress(st, g, "remodelage")["cond"], "victoire : le Remodelage")


func _test_myrr() -> void:
	var st := _game(19)
	var m := _eid(st, "myrr")
	var o := _eid(st, "ossarane")
	var added: Array[Dictionary] = []
	var ed := Insolites.emp(st, m)
	var me := st.get_empire(m)
	_rich(st, m)
	var cap := FactionTraits.capital_system(st, m)
	# Comètes.
	var target := _free_far(st, cap, 1)
	var tsid := st.galaxy.get_planet(target).system_id
	if not me.explored.has(tsid):
		me.explored[tsid] = true
	var ok_c := InsMyrr.check_comet(st, m, tsid)
	_ok(ok_c == "", "une comète-semence vers un système libre proche (%s)" % ok_c)
	SimCommands.apply(st, SimCommands.ins_act(m, "comet", {"s": tsid}))
	var comets: Array = ed["comets"]
	var l0 := int(comets[0]["left"]) if not comets.is_empty() else 0
	SimCommands.apply(st, SimCommands.ins_act(m, "comet", {"s": tsid}))
	_ok(comets.size() == 1 and int(comets[0]["left"]) == maxi(1, l0 / 2), "une seconde comète vers le même système arrive deux fois plus vite")
	comets[0]["left"] = 1
	InsMyrr.daily(st, m, ed, false, added)
	_ok(InsMyrr.seeded(st, m).has(tsid) or _owned_in(st, m, tsid), "la comète tombe : une colonie pousse")
	# Réseau : un système isolé produit moitié moins.
	for c in st.colonies.values():
		if c.owner == m:
			c.days_left = 0
	InsMyrr._network(st, m, ed)
	var tpid := -1
	for pid in st.galaxy.systems[tsid].planet_ids:
		if st.colonies.has(pid) and (st.colonies[pid] as Colony).owner == m:
			tpid = int(pid)
	var adjacent := st.galaxy.systems[cap].neighbors.has(tsid)
	_ok(tpid >= 0 and InsMyrr.colony_pct(st, tpid) == (100 if adjacent else Insolites.c_int("myrr", "iso_pct", 50)), "réseau mycorhizien : un système coupé de la capitale produit moitié moins")
	# Mycélium : une colonie étrangère du système est rongée, puis absorbée.
	var spid := -1
	for pid in st.galaxy.systems[cap].planet_ids:
		if not st.colonies.has(pid):
			spid = int(pid)
			break
	if spid < 0:
		spid = int(st.galaxy.systems[tsid].planet_ids[-1]) if st.galaxy.systems[tsid].planet_ids.size() > 1 else -1
	if spid >= 0:
		var oc := _colony(st, spid, o, 3)
		Insolites.add_implant(st, spid, "mycelium", m)
		var fed := false
		for t in 60:
			st.tick += 30
			InsMyrr._feed(st, m, added)
			if oc.population < 3:
				fed = true
				break
		_ok(fed, "le mycélium prend des habitants")
		oc.population = 1
		for t in 60:
			st.tick += 30
			InsMyrr._feed(st, m, added)
			if oc.owner == m:
				break
		_ok(oc.owner == m and int(ed["absorbed"]) == 1, "à un habitant, la colonie est absorbée")
		_ok((ed["sym"] as Array).has(st.get_empire(o).faction_id) and Insolites.production_bonus(st, m, "materials") + Insolites.production_bonus(st, m, "knowledge") + Insolites.production_bonus(st, m, "energy") + Insolites.production_bonus(st, m, "food") > 0,
				"Myrr y gagne une symbiose")
		var memo := false
		for p in Diplomacy.opinion_parts(st, o, m):
			memo = memo or String(p.get("memory", "")) == "ins_absorbed" or String(p["label"]).contains("absorb")
		_ok(memo, "l'absorbé s'en souvient")
	# Spores et feu.
	_contact(st, m, o)
	Combat.start_war(st, o, m)
	var f := st.spawn_ship(o, "corvette", cap)
	var hp0 := f.hp[0]
	InsMyrr._spores(st, m)
	_ok(f.hp[0] < hp0, "les spores rongent les flottes ennemies dans ses systèmes")
	var home := -1
	for pid in st.galaxy.systems[cap].planet_ids:
		if st.colonies.has(pid) and (st.colonies[pid] as Colony).owner == m and (st.colonies[pid] as Colony).is_colony():
			home = int(pid)
			break
	var pop0 := (st.colonies[home] as Colony).population
	_ok(SimCommands.validate(st, SimCommands.ins_act(o, "burn", {"pid": home})) == "", "en guerre, une flotte sur place peut brûler le mycélium")
	SimCommands.apply(st, SimCommands.ins_act(o, "burn", {"pid": home}))
	_ok(InsMyrr.burned(st, cap) and (not st.colonies.has(home) or (st.colonies[home] as Colony).population < pop0), "le feu : la colonie perd des habitants, le système ne pousse plus")
	# Purge : chasser le mycélium coûte de l'influence (le feu reste le remède sûr).
	_ok(Insolites.implant_def("mycelium").has("purge_cost"), "on peut purger le mycélium")
	# Victoire : 40 % des mondes habitables.
	var hs := InsMyrr.habitable_share(st, m)
	var need := int(hs[0]) * 40 / 100 + 1
	for sys in st.galaxy.systems:
		for pid in sys.planet_ids:
			if need <= 0:
				break
			if int(GameData.planet_type(st.galaxy.get_planet(pid).type).get("base_hab", 0)) > 0 and not st.colonies.has(pid):
				_colony(st, int(pid), m, 1)
				need -= 1
	me.techs["biosphere_unique"] = true
	_ok(Victory.progress(st, m, "biosphere")["cond"], "victoire : la Biosphère unique")


func _owned_in(st: GameState, eid: int, sid: int) -> bool:
	for pid in st.galaxy.systems[sid].planet_ids:
		if st.colonies.has(pid) and (st.colonies[pid] as Colony).owner == eid:
			return true
	return false


func _test_vergemonde() -> void:
	var st := _game(23, "ossarane", ODD + ["choeur", "teyl"], {"living": "rares"})
	var v := _eid(st, "vergemonde")
	var added: Array[Dictionary] = []
	var ed := Insolites.emp(st, v)
	_ok(SimCommands.validate(st, SimCommands.ins_act(v, "season", {"s": "pousses"})) == "", "le Hallier choisit sa saison")
	SimCommands.apply(st, SimCommands.ins_act(v, "season", {"s": "pousses"}))
	_ok(SimCommands.validate(st, SimCommands.ins_act(v, "season", {"s": "enracines"})) != "", "la saison ne tourne pas si vite")
	var k0 := Insolites.production_bonus(st, v, "knowledge")
	for _i in 12:
		InsVergemonde._drift(ed)
	var a := InsVergemonde.ages(st, v)
	_ok(int(a["p"]) > 40 and int(a["p"]) + int(a["m"]) + int(a["e"]) == 100, "les âges glissent vers les Pousses (la somme reste 100)")
	_ok(Insolites.production_bonus(st, v, "knowledge") > k0, "plus de Pousses, plus de Savoir")
	# Monde-jardin.
	var home := _cols(st, v)[0]
	var p := st.galaxy.get_planet(home)
	if p.type == "gaia" or not InsVergemonde.gardenable(st, home):
		st.override_planet(home, {"type": "continental"})
	InsVergemonde._grow(st, v, ed, added)
	(ed["since"] as Dictionary)[str(home)] = st.tick - Insolites.c_int("vergemonde", "garden_days", 2880)
	InsVergemonde._grow(st, v, ed, added)
	_ok(st.galaxy.get_planet(home).type == "gaia" and InsVergemonde.gardens(st, v) == 1, "au bout de huit ans, la colonie devient un monde-jardin")
	var other := -1
	for q in st.galaxy.systems[p.system_id].planet_ids:
		if int(q) != home and not st.colonies.has(q) and InsVergemonde.gardenable(st, int(q)):
			other = int(q)
			break
	if other >= 0:
		st.tick += Insolites.c_int("vergemonde", "spread_days", 1440)
		InsVergemonde._grow(st, v, ed, added)
		_ok(st.galaxy.get_planet(other).type == "gaia", "le jardin gagne une autre planète du système")
	# Cœur.
	_rich(st, v)
	_ok(SimCommands.validate(st, SimCommands.ins_act(v, "heart", {"pid": home})) == "", "planter un Cœur dans un monde-jardin")
	SimCommands.apply(st, SimCommands.ins_act(v, "heart", {"pid": home}))
	_ok(LivingWorlds.is_living(st, home) and LivingWorlds.tier_index(st, home, v) >= 3, "le monde vit, bienveillant d'emblée")
	# Feu-qui-renouvelle.
	var c: Colony = st.colonies[home]
	c.population = 8
	var burnt := false
	for t in 400:
		st.tick += 30
		InsVergemonde._fire(st, v, ed, added)
		if (ed["fire"] as Dictionary).has(str(home)):
			burnt = true
			break
	_ok(burnt and c.population == 6, "le Feu-qui-renouvelle emporte des habitants")
	st.tick += Insolites.c_int("vergemonde", "fire_regrow_days", 360)
	InsVergemonde._fire(st, v, ed, added)
	_ok(c.population > 6, "un an plus tard, la forêt repousse plus dense")
	# Victoire.
	var want := 8
	for sys in st.galaxy.systems:
		for pid in sys.planet_ids:
			if want <= InsVergemonde.gardens(st, v):
				break
			if not st.colonies.has(pid):
				_colony(st, int(pid), v, 1)
				st.override_planet(int(pid), {"type": "gaia"})
	var bound := 0
	for pid in _cols(st, v):
		if bound >= 3:
			break
		if not LivingWorlds.is_living(st, pid):
			LivingWorlds.add_world(st, pid, "graine", pid)
		LivingWorlds.set_mood(st, pid, v, 100)
		if LivingWorlds.tier_id(st, pid, v) == "lie":
			bound += 1
	st.get_empire(v).techs["grand_jardin"] = true
	_ok(Victory.progress(st, v, "grand_jardin")["cond"], "victoire : le Grand Jardin (%d jardins, %d Liés)" % [InsVergemonde.gardens(st, v), InsVergemonde.living_bound(st, v)])


func _test_tones() -> void:
	var st := _game(61, "ossarane", ODD)
	var labels := []
	for p in Diplomacy.opinion_parts(st, _eid(st, "vergemonde"), _eid(st, "myrr")):
		labels.append(String(p["label"]))
	_ok(labels.has("La forêt et la pourriture se disputent les mêmes mondes"), "choc des tons Myrr / Hallier dans l'opinion")
	var labels2 := []
	for p in Diplomacy.opinion_parts(st, _eid(st, "gravea"), _eid(st, "sablier")):
		labels2.append(String(p["label"]))
	_ok(labels2.has("Les Lithes trouvent indécent de défaire le temps"), "choc des tons Sablier / Gravéa")
	var added: Array[Dictionary] = []
	var g := st.get_empire(_eid(st, "gravea"))
	Events.on_contact(st, g, st.get_empire(_eid(st, "sablier")), added)
	var got := false
	for it in Events.meta(st, g.id).get("inbox", []):
		if String(it.get("card", "")) == "t_sable_pierre":
			got = true
	_ok(not Events.enabled(st) or got, "premier contact : la carte « le sable et la pierre »")


func _test_ai_game() -> void:
	var opts := {"spectator": true, "ai_level": "normal", "minors": "normal", "living": "rares", "rivals": ["sablier", "gravea", "myrr", "vergemonde", "ossarane", "teyl", "choeur"]}
	var st := GameState.create(7, 150, 1800.0, "", opts.duplicate(true))
	var sim := Simulation.new(st)
	var alive5 := true
	var early_win := false
	var worked := false
	var cometed := false
	var seasoned := false
	var s := _eid(st, "sablier")
	var g := _eid(st, "gravea")
	var m := _eid(st, "myrr")
	var v := _eid(st, "vergemonde")
	for d in 3600:
		sim.step()
		if not worked:
			worked = not (Insolites.emp(st, g).get("works", []) as Array).is_empty() or not (Insolites.emp(st, g).get("done", {}) as Dictionary).is_empty()
		if not cometed:
			cometed = not (Insolites.emp(st, m).get("comets", []) as Array).is_empty() or InsMyrr.seeded(st, m).size() > 1
		if not seasoned:
			seasoned = int(Insolites.emp(st, v).get("season_t", 0)) > 0
		if d == 1799:
			for fid in ODD:
				alive5 = alive5 and not st.get_empire(_eid(st, fid)).eliminated
		if not st.winner.is_empty() and not early_win:
			if ["paradoxe", "remodelage", "biosphere", "grand_jardin"].has(String(st.winner.get("victory", ""))):
				early_win = true
			print("  victoire au jour %d : %s" % [d, str(st.winner)])
			break
	_ok(alive5, "les quatre peuples survivent jusqu'à l'an 5")
	_ok(not early_win, "aucune victoire de peuple en 10 ans")
	_ok(worked, "IA : les Lithes entreprennent une Œuvre lente")
	_ok(cometed, "IA : la Sporemère lance des comètes")
	_ok(seasoned, "IA : le Hallier change de saison")
	# La partie peut s'arrêter avant l'an 10 (victoire) : le premier jardin demande huit ans (garden_days).
	print("    (arrêt au jour %d ; Sablier : %d annulations, Sable %d ; Lithes : %d Œuvres achevées ; Myrr : %d systèmes, %d absorbés ; Hallier : %d jardins)" % [
			st.tick, int(Insolites.emp(st, s).get("undone", 0)), int(Insolites.emp(st, s).get("sand", 0)), (Insolites.emp(st, g).get("done", {}) as Dictionary).size(),
			InsMyrr.seeded(st, m).size(), int(Insolites.emp(st, m).get("absorbed", 0)), InsVergemonde.gardens(st, v)])
	var d1 := st.to_dict()
	var st2 := GameState.from_dict(JSON.parse_string(JSON.stringify(d1)))
	_ok(st2 != null and JSON.stringify(st2.to_dict()) == JSON.stringify(d1), "sauvegarde relue à l'identique")
	var ga := GameState.create(9, 120, 1600.0, "", opts.duplicate(true))
	var gb := GameState.create(9, 120, 1600.0, "", opts.duplicate(true))
	var sa := Simulation.new(ga)
	var sb := Simulation.new(gb)
	for _d in 720:
		sa.step()
		sb.step()
	_ok(JSON.stringify(ga.to_dict()) == JSON.stringify(gb.to_dict()), "déterminisme : deux parties identiques restent identiques")


## Équilibrage, lot 6 : un empire né en cours de partie d'un peuple insolite reçoit l'état de sa règle.
func _test_born() -> void:
	var st := _game(23)
	var sab := _eid(st, "sablier")
	var cap := st.galaxy.get_planet(st.get_empire(sab).capital_planet).system_id
	var added: Array[Dictionary] = []
	var nid := RulersDynasty.spawn_empire(st, sab, [cap], {}, "test", added)
	_ok(nid >= 0 and Insolites.kind(st, nid) == "sablier" and String(Insolites.emp(st, nid).get("k", "")) == "sablier", "empire né du Sablier : il a l'état de sa règle")
	_ok(Insolites.nomad_ids(st).has(nid), "il compte parmi les peuples insolites en jeu")
	(st.insolites["emp"] as Dictionary).erase(str(nid))
	_ok(not Insolites.nomad_ids(st).has(nid), "un empire sans état de règle est laissé de côté au lieu de planter")
	InsZambalu.numero_day(st, added)
	_ok(InsZambalu.open_call(st) == -1, "le Grand Numéro ne plante plus sur lui")

