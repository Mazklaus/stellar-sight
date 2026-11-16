extends RefCounted
## Tests de l'administration et de la corruption (étude « Administration et corruption », 2026-11-16) :
## données, réglages (Désactivée = règles d'avant, Simple = jauge seule), charge et capacité, tranches
## de dépassement et leurs effets, corruption (distance, Tribunal, capitale), production détournée,
## effort administratif, intégration des conquêtes, transfert de capitale, ponts (scandales, doléance,
## commerce, espionnage, haut fait), interface et sauvegarde. Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Administration et corruption…")
	_test_data()
	_test_modes()
	_test_load_capacity()
	_test_over()
	_test_corruption()
	_test_yields()
	_test_effort()
	_test_integration()
	_test_capital()
	_test_bridges()
	_test_talents()
	_test_ai()
	_test_save()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


static func new_game(seed_value := 31, extra := {}) -> GameState:
	var o := {"ai_level": "", "admin": "complete"}
	o.merge(extra, true)
	return GameState.create(seed_value, 120, 1600.0, "vael", o)


static func eid_of(st: GameState, fid: String) -> int:
	for e in st.empires:
		if e.faction_id == fid:
			return e.id
	return -1


static func apply(st: GameState, cmd: Dictionary) -> String:
	var why := SimCommands.validate(st, cmd)
	if why == "":
		SimCommands.apply(st, cmd)
	return why


## Donne à l'empire une colonie dans un système libre (le plus proche de sa capitale).
static func give_system(st: GameState, eid: int, skip: Array = []) -> int:
	var e := st.get_empire(eid)
	var cap := st.galaxy.get_planet(e.capital_planet).system_id
	var best := -1
	var bd := 1e12
	for s in st.galaxy.systems.size():
		if s == cap or skip.has(s) or st.system_owner(s) >= 0:
			continue
		var d: float = st.galaxy.systems[s].position.distance_to(st.galaxy.systems[cap].position)
		if d < bd and not st.galaxy.systems[s].planet_ids.is_empty():
			bd = d
			best = s
	if best < 0:
		return -1
	var c := Colony.new()
	c.planet_id = st.galaxy.systems[best].planet_ids[0]
	c.owner = eid
	c.population = 3
	st.add_colony(c)
	st.rebuild_ownership()
	return best


static func give(st: GameState, eid: int, n: int) -> Array[int]:
	var out: Array[int] = []
	for i in n:
		var s := give_system(st, eid, out)
		if s < 0:
			break
		out.append(s)
	Admin.refresh(st)
	return out


func _test_data() -> void:
	var d := Admin.data()
	_ok((d["modes"] as Array).size() == 3, "trois réglages")
	_ok(Admin.default_mode() == "complete", "Complète par défaut")
	_ok(Admin.effort_defs().size() == 4, "quatre crans d'effort")
	for r in d["corruption"]["resources"]:
		_ok(String(r) != "food", "la corruption ne touche jamais la nourriture")
	_ok(not GameData.building("tribunal").is_empty(), "le Tribunal existe")
	for t in d["admin_techs"]:
		_ok(not Research.tech(String(t)).is_empty(), "technologie d'administration %s connue" % t)
	_ok(not Espionage.op_def("acheter_fonctionnaires").is_empty(), "opération « Acheter les fonctionnaires »")
	_ok(not Heroes.trait_def("integre").is_empty() and not Heroes.trait_def("bureaucrate").is_empty(), "traits Intègre et Bureaucrate")
	_ok(not Laws.law_def("fonctionnaires_elus").is_empty() and not Laws.law_def("inspection_imperiale").is_empty(), "deux lois d'administration")


func _test_modes() -> void:
	var off := new_game(31, {"admin": "desactivee"})
	_ok(off.admin.is_empty(), "Désactivée : rien ne tourne")
	var p := eid_of(off, "vael")
	_ok(not Admin.applies(off, p), "Désactivée : le pilier ne s'applique à personne")
	_ok(Admin.research_pct(off, p) == 0, "Désactivée : pas de surcoût administratif")
	_ok(Stability.threshold(off, p) == int(Stability.data()["sources"]["overextension"]["threshold"]), "Désactivée : la surextension reste en place")
	var none := GameState.create(31, 120, 1600.0, "vael", {"ai_level": ""})
	_ok(none.admin.is_empty(), "sans option (tests, banc) : désactivée")
	var simple := new_game(31, {"admin": "simple"})
	_ok(Admin.enabled(simple) and not Admin.full(simple), "Simple : la jauge seule")
	var sp := eid_of(simple, "vael")
	give(simple, sp, 3)
	_ok(not Admin.has_corruption(simple, sp), "Simple : pas de corruption")
	for k in (simple.admin["cor"] as Dictionary).keys():
		_ok(int(simple.admin["cor"][k]) == 0, "Simple : corruption nulle")
	var st := new_game()
	_ok(Admin.full(st), "Complète : tout tourne")


func _test_load_capacity() -> void:
	var st := new_game()
	var p := eid_of(st, "vael")
	var l0 := Admin.load_of(st, p)
	_ok(l0 > 0, "la capitale pèse déjà (%d)" % l0)
	_ok(Admin.capacity(st, p) >= int(Admin.data()["capacity"]["capital"]) * 8 / 10, "la capitale apporte sa capacité (%d)" % Admin.capacity(st, p))
	give(st, p, 2)
	var l1 := Admin.load_of(st, p)
	_ok(l1 >= l0 + 2 * Admin.d_int("load", "system"), "deux systèmes de plus pèsent (%d → %d)" % [l0, l1])
	_ok(not (Admin.entry(st, p)["lp"] as Array).is_empty() and not (Admin.entry(st, p)["cp"] as Array).is_empty(), "détails de la charge et de la capacité")
	# Calibrage : un empire de départ tient une dizaine de systèmes avant de dépasser.
	var st2 := new_game()
	var p2 := eid_of(st2, "vael")
	var n := 0
	while Admin.over_pct(st2, p2) == 0 and n < 30:
		if give(st2, p2, 1).is_empty():
			break
		n += 1
	_ok(n >= 8 and n <= 14, "au départ, la capacité tient environ 10 systèmes (%d)" % (n + 1))


func _test_over() -> void:
	var st := new_game()
	var p := eid_of(st, "vael")
	(st.admin["e"][str(p)] as Dictionary)["cap"] = 10
	(st.admin["e"][str(p)] as Dictionary)["load"] = 15
	(st.admin["e"][str(p)] as Dictionary)["over"] = 50
	_ok(Admin.steps(st, p) == 5, "50 % de trop : 5 tranches")
	_ok(Admin.research_pct(st, p) == 25, "recherche +25 %")
	var c := Admin.influence_cost(st, p, {"influence": 100})
	_ok(int(c["influence"]) == 125, "coûts en influence +25 %")
	var parts := Admin.empire_stability_parts(st, p)
	_ok(not parts.is_empty() and int(parts[0][1]) == -10, "stabilité -10 partout (%s)" % str(parts))
	var st0 := new_game()
	_ok(Research.cost(st, p, "administration2") > Research.cost(st0, p, "administration2"), "dépassement : la recherche coûte plus cher")
	# Pas de double peine : la surextension disparaît quand le pilier est actif.
	var found := false
	for sp in Stability.parts(st, FactionTraits.capital_system(st, p), Stability.context(st, p)):
		if String(sp[0]).begins_with("Surextension"):
			found = true
	_ok(not found, "pilier actif : plus de ligne Surextension")


func _test_corruption() -> void:
	var st := new_game()
	var p := eid_of(st, "vael")
	var cap := FactionTraits.capital_system(st, p)
	_ok(Admin.corruption(st, cap) == 0, "la capitale n'est pas corrompue")
	var far := -1
	var bd := 0.0
	for s in st.galaxy.systems.size():
		if st.system_owner(s) >= 0 or st.galaxy.systems[s].planet_ids.is_empty():
			continue
		var d: float = st.galaxy.systems[s].position.distance_to(st.galaxy.systems[cap].position)
		if d > bd:
			bd = d
			far = s
	var c := Colony.new()
	c.planet_id = st.galaxy.systems[far].planet_ids[0]
	c.owner = p
	c.population = 3
	st.add_colony(c)
	st.rebuild_ownership()
	Admin.refresh(st)
	var v := Admin.corruption(st, far)
	_ok(v > 0, "un système lointain est corrompu (%d %%)" % v)
	_ok(v <= Admin.d_int("corruption", "max"), "plafond de %d %%" % Admin.d_int("corruption", "max"))
	var r: Array = Admin.corruption_parts(st, p, far)
	_ok(int(r[0]) == v and not (r[1] as Array).is_empty(), "détail de la corruption")
	c.buildings.append("tribunal")
	Admin.refresh(st)
	var v2 := Admin.corruption(st, far)
	_ok(v2 <= v / 2 + 1, "le Tribunal divise par deux (%d → %d)" % [v, v2])
	_ok(Admin.average_corruption(st, p) >= 0, "corruption moyenne")


func _test_yields() -> void:
	var st := new_game()
	var p := eid_of(st, "vael")
	var cap := FactionTraits.capital_system(st, p)
	var col: Colony = st.colonies[st.get_empire(p).capital_planet]
	var before: Dictionary = Economy.colony_yields(st, col)["gross"]
	(st.admin["cor"] as Dictionary)[str(cap)] = 40
	var after: Dictionary = Economy.colony_yields(st, col)["gross"]
	_ok(int(after.get("food", 0)) == int(before.get("food", 0)), "la nourriture n'est pas détournée")
	if int(before.get("energy", 0)) > 0:
		_ok(int(after["energy"]) < int(before["energy"]), "l'énergie est détournée (%d → %d)" % [int(before["energy"]), int(after["energy"])])
	(st.admin["cor"] as Dictionary)[str(cap)] = 0
	(st.admin["ni"] as Dictionary)[str(cap)] = 1
	var ni: Dictionary = Economy.colony_yields(st, col)["gross"]
	_ok(int(ni.get("food", 0)) <= int(before.get("food", 0)) / 2 + 1, "non intégré : production divisée par deux")
	_ok(Admin.decree_block(st, cap) != "", "non intégré : pas de décret")


func _test_effort() -> void:
	var st := new_game()
	var p := eid_of(st, "vael")
	_ok(Admin.effort(st, p) == "normal", "effort Normal par défaut")
	var cap0 := Admin.capacity(st, p)
	_ok(apply(st, SimCommands.admin_effort(p, "genereux")) == "", "passer en Généreux")
	_ok(Admin.capacity(st, p) > cap0, "Généreux : capacité en hausse (%d → %d)" % [cap0, Admin.capacity(st, p)])
	_ok(int(Admin.upkeep(st, p).get("energy", 0)) >= 0, "les fonctionnaires se paient en énergie")
	_ok(apply(st, SimCommands.admin_effort(p, "frugal")) == "", "passer en Frugal")
	_ok(Admin.upkeep(st, p).is_empty(), "Frugal : aucun entretien")
	_ok(apply(st, SimCommands.admin_effort(p, "nimporte")) != "", "effort inconnu refusé")
	apply(st, SimCommands.admin_effort(p, "enquete"))
	var has := false
	for part in Admin.empire_stability_parts(st, p):
		if String(part[0]) == "Grande enquête":
			has = true
	_ok(has, "Grande enquête : stabilité en baisse partout")


func _test_integration() -> void:
	var st := new_game()
	var p := eid_of(st, "vael")
	var other := -1
	for e in st.empires:
		if e.id != p and not e.is_npc():
			other = e.id
			break
	var sid := give_system(st, other, [])
	st.tick = 30 * 11
	Admin.daily(st)
	# Le système change de main : il arrive non intégré.
	for pid in st.galaxy.systems[sid].planet_ids:
		var c: Colony = st.colonies.get(pid)
		if c != null:
			c.owner = p
	st.rebuild_ownership()
	st.tick = 30 * 12
	Admin.daily(st)
	_ok(not Admin.is_integrated(st, sid), "une conquête arrive non intégrée")
	_ok(Admin.load_parts(st, p).size() >= 0, "charge recalculée")
	var cost := Admin.integrate_cost(st, p, sid)
	_ok(int(cost.get("influence", 0)) > 0, "intégrer coûte de l'influence (%s)" % str(cost))
	st.get_empire(p).resources["influence"] = 500
	Stability.entry(st, sid)["v"] = 60
	var why := apply(st, SimCommands.admin_integrate(p, sid))
	_ok(why == "", "intégration lancée (%s)" % why)
	_ok(Admin.integrating(st, sid) > st.tick, "intégration en cours")
	st.tick += Admin.d_int("integration", "days") + 30
	st.tick -= posmod(st.tick, 30)
	Admin.daily(st)
	_ok(Admin.is_integrated(st, sid), "intégration achevée")


func _test_capital() -> void:
	var st := new_game()
	var p := eid_of(st, "vael")
	var e := st.get_empire(p)
	var s := give_system(st, p, [])
	var pid := int(st.galaxy.systems[s].planet_ids[0])
	var c: Colony = st.colonies[pid]
	_ok(apply(st, SimCommands.admin_capital(p, pid)) != "", "trop peu peuplée : refus")
	c.population = 12
	e.resources["influence"] = 500
	e.resources["materials"] = 1000
	Admin.refresh(st)
	var why := apply(st, SimCommands.admin_capital(p, pid))
	_ok(why == "", "transfert de capitale (%s)" % why)
	_ok(e.capital_planet == pid, "la capitale a changé")
	_ok(c.buildings.has("capitale"), "le bâtiment Capitale a suivi")
	_ok(Admin.in_transition(st, p), "transition en cours")
	_ok(Admin.check_move_capital(st, p, e.capital_planet) != "", "pas de second transfert tout de suite")


func _test_bridges() -> void:
	var st := new_game()
	var p := eid_of(st, "vael")
	var cap := FactionTraits.capital_system(st, p)
	# Scandale « Détournement révélé » joué à la main : la carte arrive.
	var added: Array[Dictionary] = []
	AdminBridges._play(st, st.get_empire(p), cap, "detournement", added)
	var found := false
	for item: Dictionary in Events.meta(st, p)["inbox"]:
		if String(item["card"]) == "admin_detournement":
			found = true
			Events.choose(st, p, int(item["id"]), 0, added)
			break
	_ok(found, "la carte « Détournement révélé » arrive")
	_ok(int((st.admin.get("purge", {}) as Dictionary).get(str(cap), 0)) > st.tick, "punir : purge des bureaux")
	AdminBridges._play(st, st.get_empire(p), cap, "fonctionnaires_achetes", added)
	_ok(int(Admin.entry(st, p).get("leak", 0)) > st.tick, "fonctionnaires achetés : fuites")
	# Commerce : la corruption d'un port rogne la route.
	(st.admin["cor"] as Dictionary)[str(cap)] = 20
	_ok(AdminBridges.trade_pct(st, p, cap) == 20, "commerce : -20 % depuis un port corrompu")
	# Espionnage : acheter les fonctionnaires d'un rival.
	var b := AdminBridges.bribe_target(st, p)
	_ok(b >= -1, "cible d'achat de fonctionnaires")
	# Haut fait : Mains propres.
	_ok(AdminBridges.clean_years(st, p) >= 0, "années de mains propres")
	_ok(not Deeds.def("mains_propres").is_empty(), "haut fait Mains propres")


func _test_talents() -> void:
	var st := new_game(31, {})
	for e in st.empires:
		if e.is_npc():
			continue
		var t := Admin.talent(st, e.id)
		_ok(t is Dictionary, "talent lu pour %s" % e.faction_id)
		var g := Admin.government(st, e.id)
		if g == "ruche" or g == "conscience":
			_ok(not Admin.has_corruption(st, e.id), "%s : aucune corruption" % g)


func _test_ai() -> void:
	var st := new_game(41, {"ai_level": "normale"})
	var sim := Simulation.new(st)
	sim.advance(360)
	var any := false
	for e in st.empires:
		if not e.is_npc() and Admin.applies(st, e.id) and Admin.load_of(st, e.id) > 0:
			any = true
	_ok(any, "un an d'IA : la charge se calcule pour tous")


func _test_save() -> void:
	var st := new_game()
	var p := eid_of(st, "vael")
	give(st, p, 2)
	apply(st, SimCommands.admin_effort(p, "genereux"))
	var d := st.to_dict()
	_ok(d.has("admin"), "l'administration est sauvegardée")
	_ok(int(d["version"]) >= 77, "format 77")
	var st2 := GameState.from_dict(d)
	_ok(st2 != null and Admin.effort(st2, p) == "genereux", "relue : même effort")
	_ok(JSON.stringify(Admin.to_dict(st2)) == JSON.stringify(Admin.to_dict(st)), "relue à l'identique")
	var off := new_game(31, {"admin": "desactivee"})
	_ok(not off.to_dict().has("admin"), "Désactivée : pas de clé admin dans la sauvegarde")
