extends RefCounted
## Tests de la cour, lot 1 (étude « La cour et les familles nobles », 2026-11-16) : catalogue en données,
## réglage (Aucune = rien ne tourne), fondation et choix des maisons, fiefs et sièges, faveur et paliers,
## grands offices et postes mineurs, effets, sauvegarde. Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Cour et Grandes Maisons (le socle)…")
	_test_data()
	_test_modes()
	_test_found_and_choice()
	_test_fiefs()
	_test_favor()
	_test_offices()
	_test_effects()
	_test_save()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


static func new_game(seed_value := 31, extra := {}) -> GameState:
	var o := {"ai_level": "", "court": "actives"}
	o.merge(extra, true)
	return GameState.create(seed_value, 120, 1600.0, "vael", o)


static func eid_of(st: GameState, fid: String) -> int:
	for e in st.empires:
		if e.faction_id == fid:
			return e.id
	return -1


## Avance jusqu'au prochain bilan mensuel de la cour (compris), cour seulement.
static func to_month(st: GameState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in 31:
		st.tick += 1
		out.append_array(Court.daily(st))
		if posmod(st.tick, Court.r_int("check_days")) == Court.r_int("offset"):
			return out
	return out


static func apply(st: GameState, cmd: Dictionary) -> String:
	var why := SimCommands.validate(st, cmd)
	if why == "":
		SimCommands.apply(st, cmd)
	return why


## Réponse à la dernière carte de cour de l'inbox (index du choix).
static func answer(st: GameState, eid: int, card: String, index: int) -> bool:
	for item: Dictionary in (Events.meta(st, eid)["inbox"] as Array).duplicate():
		if String(item["card"]) == card:
			var added: Array[Dictionary] = []
			Events.choose(st, eid, int(item["id"]), index, added)
			return true
	return false


static func has_card(st: GameState, eid: int, card: String) -> bool:
	for item: Dictionary in Events.meta(st, eid)["inbox"]:
		if String(item["card"]) == card:
			return true
	return false


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


func _test_data() -> void:
	var d := Court.data()
	var vocs: Array = d["vocations"]
	_ok(vocs.size() >= 19, "19 vocations au moins (%d)" % vocs.size())
	var common := 0
	for v: Dictionary in vocs:
		if (v.get("registres", []) as Array).is_empty():
			common += 1
		_ok(Politics.index_of(String(v["current"])) >= 0, "vocation %s : courant connu" % v["id"])
		_ok(Court.APTS.has(String(v["apt"])), "vocation %s : aptitude connue" % v["id"])
		_ok((v["goods"] as Array).size() == 2, "vocation %s : deux biens de luxe préférés" % v["id"])
		for g in v["goods"]:
			_ok(Goods.label(String(g)) != String(g) or Goods.label(String(g)) != "", "bien %s connu" % g)
		for t in v["traits"]:
			_ok(not Court.trait_def(String(t)).is_empty(), "trait %s connu" % t)
		for c: Dictionary in (v["likes"] as Array) + (v["dislikes"] as Array):
			if String(c["k"]) == "law":
				_ok(not Laws.law_def(String(c["id"])).is_empty(), "loi %s connue (%s)" % [c["id"], v["id"]])
			if String(c["k"]) == "building":
				_ok(not GameData.building(String(c["id"])).is_empty(), "bâtiment %s connu (%s)" % [c["id"], v["id"]])
	_ok(common == 12, "douze vocations communes (%d)" % common)
	_ok((d["offices"] as Array).size() == 5, "cinq grands offices (quatre, plus l'Aumônier des théocraties)")
	_ok((d["minor_posts"] as Array).size() == 3, "trois postes mineurs")
	for g in ["feodalite", "republique", "theocratie", "syndicat", "horde", "conscience"]:
		_ok((d["governments"] as Dictionary).has(g), "mots de la cour pour %s" % g)
	_ok(not (d["governments"] as Dictionary).has("ruche"), "la ruche n'a pas de maisons")
	var cards := 0
	for c: Dictionary in d["cards"]:
		_ok(not Events.card(String(c["id"])).is_empty(), "carte %s chargée par Events" % c["id"])
		if String(c["id"]).begins_with("court_ev_"):
			cards += 1
	_ok(cards >= 30, "au moins trente événements de cour (%d)" % cards)
	for reg in Species.options("registre"):
		_ok((d["names"] as Dictionary).has(String(reg.get("id", reg.get("name", "")))), "noms de maisons pour le registre %s" % reg.get("id", reg.get("name", "")))


func _test_modes() -> void:
	var st := GameState.create(31, 120, 1600.0, "vael", {"ai_level": ""})
	_ok(st.court.is_empty(), "sans l'option : pas de cour")
	var st2 := new_game(31, {"court": "aucune"})
	_ok(st2.court.is_empty(), "Aucune : state.court reste vide")
	for i in 400:
		st2.tick += 1
		Court.daily(st2)
	_ok(st2.court.is_empty(), "Aucune : rien ne tourne en 400 jours")
	var e := st2.get_empire(eid_of(st2, "vael"))
	_ok(Court.effects(st2, e.id).is_empty() and Court.income(st2, e.id).is_empty(), "Aucune : ni effets ni revenus")
	_ok(Court.check_act(st2, e.id, "fete", -1, -1, "") != "", "Aucune : pas d'ordre de cour")
	_ok(not Court.worth_saving(st2), "Aucune : rien à sauvegarder")
	var st3 := new_game(31, {"court": "apaisees"})
	_ok(Court.peaceful(st3) and not st3.court.is_empty(), "Apaisées : la cour existe, sans Fronde")
	var st4 := new_game()
	for o in st4.empires:
		if o.is_npc() or o.eliminated:
			continue
		if Court.government(st4, o.id) == "ruche":
			_ok(not Court.applies(st4, o.id), "%s (ruche) : pas de maisons" % o.display_name())
		else:
			_ok(Court.houses(st4, o.id).size() == Court.start_count(st4, o.id) + 1, "%s : %d familles se présentent" % [o.display_name(), Court.houses(st4, o.id).size()])


func _test_found_and_choice() -> void:
	var st := new_game()
	var v := eid_of(st, "vael")
	var en := Court.entry(st, v)
	_ok((en["offer"] as Array).size() == 4, "quatre familles proposées au choix")
	var names := {}
	for h: Dictionary in Court.houses(st, v):
		_ok(not names.has(h["name"]), "nom de maison unique %s" % h["name"])
		names[h["name"]] = true
		_ok((h["members"] as Array).size() >= 2 and (h["members"] as Array).size() <= 4, "%s : 2 à 4 membres" % h["name"])
		_ok(not Court.head(h).is_empty(), "%s : un chef" % h["name"])
		_ok(not (h["rivals"] as Array).is_empty(), "%s : une rivale" % h["name"])
	to_month(st)
	_ok(has_card(st, v, "court_houses"), "premier bilan : la carte du choix des maisons")
	var dropped := int(en["offer"][1])
	_ok(answer(st, v, "court_houses", 1), "on renvoie la deuxième")
	_ok(Court.house(st, v, dropped).is_empty(), "la maison renvoyée a disparu")
	_ok(Court.houses(st, v).size() == Court.start_count(st, v), "il reste %d maisons" % Court.start_count(st, v))
	_ok(int(en["sel"]) == 1, "le choix est fait")
	to_month(st)
	_ok(not has_card(st, v, "court_houses"), "la carte ne revient pas")


func _test_fiefs() -> void:
	var st := new_game()
	var v := eid_of(st, "vael")
	to_month(st)
	answer(st, v, "court_houses", 0)
	var sids: Array = []
	for i in 6:
		var s := give_system(st, v, sids)
		if s >= 0:
			sids.append(s)
	Court.reconcile(st, v)
	var cap := FactionTraits.capital_system(st, v)
	_ok(Court.fief_house(st, cap, v).is_empty(), "la capitale reste à la couronne")
	var counts: Array[int] = []
	for h: Dictionary in Court.houses(st, v):
		counts.append(Court.fiefs_of(st, v, int(h["id"])).size())
	_ok(counts.max() - counts.min() <= 1, "fiefs partagés équitablement (%s)" % str(counts))
	for s in sids:
		_ok(not Court.fief_house(st, int(s), v).is_empty(), "système %d donné en fief" % s)
	var h0: Dictionary = Court.houses(st, v)[0]
	_ok(int(h0["seat"]) >= 0, "un siège pour %s" % h0["name"])
	# Donner un fief : révocation pour l'ancienne maison.
	var h1: Dictionary = Court.houses(st, v)[1]
	var target := Court.fiefs_of(st, v, int(h0["id"]))[0]
	st.get_empire(v).resources["influence"] = 500
	var adj_before := int(h0["adj"])
	_ok(apply(st, SimCommands.court_act(v, "grant", target, int(h1["id"]))) == "", "donner un fief")
	_ok(int(Court.fief_house(st, target, v)["id"]) == int(h1["id"]), "le fief change de maison")
	_ok(int(h0["adj"]) < adj_before, "l'ancienne maison s'offense de la révocation")
	_ok(apply(st, SimCommands.court_act(v, "grant", cap, int(h1["id"]))) != "", "pas la capitale")
	# Système perdu : le fief disparaît.
	var lost := int(sids[0])
	for pid in st.galaxy.systems[lost].planet_ids:
		if st.colonies.has(pid):
			st.colonies.erase(pid)
	st.rebuild_ownership()
	Court.reconcile(st, v)
	_ok(Court.fief_house(st, lost, v).is_empty(), "système perdu : le fief est rendu")


func _test_favor() -> void:
	var st := new_game()
	var v := eid_of(st, "vael")
	var h: Dictionary = Court.houses(st, v)[0]
	Court.adjust(st, v, int(h["id"]), 60)
	_ok(Court.favor(h) >= 40, "un présent royal : faveur %d" % Court.favor(h))
	_ok(int(h["adj"]) <= Court.r_int("adj_max"), "humeur plafonnée")
	Court.adjust(st, v, int(h["id"]), -200)
	_ok(int(h["adj"]) == Court.r_int("adj_min"), "humeur plancher")
	_ok(Court.tier_id(h) == "furieuse" or Court.tier_id(h) == "mecontente", "humeur exécrable : %s" % Court.tier_id(h))
	_ok(Court.tier_for(100)["id"] == "devouee" and Court.tier_for(-100)["id"] == "furieuse" and Court.tier_for(0)["id"] == "neutre", "cinq paliers")
	var parts: Array = h["parts"]
	_ok(parts.size() >= 1, "la faveur se détaille (%d lignes)" % parts.size())
	# Délaissée : sans office, elle s'aigrit.
	var h2: Dictionary = Court.houses(st, v)[1]
	for i in 6:
		to_month(st)
	_ok(int(h2["scorn"]) < 0, "une maison sans office s'aigrit (%d)" % int(h2["scorn"]))


func _test_offices() -> void:
	var st := new_game()
	var v := eid_of(st, "vael")
	_ok(Court.office_ids(st, v).size() == 4, "quatre grands offices hors théocratie")
	var h: Dictionary = Court.houses(st, v)[0]
	var m: Dictionary = h["members"][0]
	var fav := Court.favor(h)
	_ok(apply(st, SimCommands.court_act(v, "appoint", int(m["id"]), 0, "intendant")) == "", "nommer un Grand Intendant")
	_ok(Court.office_apt(st, v, "intendant") == int(Court.apts(m)["gestion"]), "l'office suit sa Gestion")
	_ok(Court.favor(h) > fav, "sa maison est flattée (%d → %d)" % [fav, Court.favor(h)])
	_ok(apply(st, SimCommands.court_act(v, "appoint", int(m["id"]), 0, "heraut")) != "", "un seul office par courtisan")
	var h2: Dictionary = Court.houses(st, v)[1]
	var m2: Dictionary = h2["members"][0]
	apply(st, SimCommands.court_act(v, "appoint", int(m2["id"]), 0, "intendant"))
	_ok(Court.offices_of(st, v, int(h["id"])).is_empty() and int(h["adj"]) < 15, "révoqué : la première maison perd l'office et s'en offense")
	# Héros à un office.
	var hid: int = Heroes.ids_of(st, v)[0]
	_ok(apply(st, SimCommands.court_act(v, "appoint", hid, 1, "connetable")) == "", "un héros peut tenir un office")
	_ok(Court.office_apt(st, v, "connetable") >= 1, "aptitude du héros comptée")
	_ok(apply(st, SimCommands.court_act(v, "vacate", -1, -1, "connetable")) == "", "libérer un office")
	_ok(Court.holder(st, v, "connetable").is_empty(), "office vacant")
	# Postes mineurs.
	_ok(apply(st, SimCommands.court_act(v, "minor", int(m["id"]), -1, "medecin")) == "", "nommer un Médecin de la cour")
	_ok(Court.medic_pct(st, v) == int(Court.apts(m)["gestion"]) * Court.r_int("medecin_pct"), "le Médecin réduit le risque de mort")
	# Théocratie : l'Aumônier.
	for o in st.empires:
		if Court.government(st, o.id) == "theocratie":
			_ok(Court.office_ids(st, o.id).has("aumonier"), "%s (théocratie) : un Grand Aumônier" % o.display_name())
			_ok(Court.office_label(st, o.id, "intendant") == "Économe sacré", "libellés de théocratie")


func _test_effects() -> void:
	var st := new_game()
	var v := eid_of(st, "vael")
	var h: Dictionary = Court.houses(st, v)[0]
	var m: Dictionary = h["members"][0]
	apply(st, SimCommands.court_act(v, "appoint", int(m["id"]), 0, "heraut"))
	var el := int(Court.apts(m)["eloquence"])
	_ok(int(Court.income(st, v).get("influence", 0)) >= el, "le Grand Héraut rapporte de l'influence (%d)" % el)
	_ok(int(Heroes.income(st, v).get("influence", 0)) >= el, "revenu passé dans le bilan des héros")
	var fx := Court.effects(st, v)
	_ok(fx is Dictionary, "effets au format des technologies")
	Relics.touch(st)
	var rfx := Research.effects(st, v)
	_ok(rfx is Dictionary, "fusionnés dans Research.effects")
	# Fief d'une maison dévouée : production en plus.
	to_month(st)
	answer(st, v, "court_houses", 0)
	var s := give_system(st, v)
	Court.reconcile(st, v)
	var fh := Court.fief_house(st, s, v)
	if not fh.is_empty():
		var col: Colony = null
		for pid in st.galaxy.systems[s].planet_ids:
			if st.colonies.has(pid):
				col = st.colonies[pid]
		fh["adj"] = 60
		Court.refresh(st, v)
		var hi: Dictionary = Economy.colony_yields(st, col)["gross"]
		fh["adj"] = -60
		fh["scorn"] = -30
		Court.refresh(st, v)
		var lo: Dictionary = Economy.colony_yields(st, col)["gross"]
		var shi := 0
		var slo := 0
		for r in hi:
			shi += int(hi[r])
			slo += int(lo[r])
		_ok(shi >= slo, "un fief dévoué produit plus qu'un fief furieux (%d / %d)" % [shi, slo])
		var sp := Court.stability_parts(st, s, v)
		_ok(not sp.is_empty(), "le fief pèse sur la stabilité du système")


func _test_save() -> void:
	var st := new_game()
	var v := eid_of(st, "vael")
	to_month(st)
	var d := st.to_dict()
	_ok(d.has("court"), "la cour est sauvegardée")
	_ok(int(d["version"]) >= 76, "format 76 ou plus")
	var st2 := GameState.from_dict(d)
	_ok(st2 != null and Court.houses(st2, v).size() == Court.houses(st, v).size(), "relue : les mêmes maisons")
	_ok(JSON.stringify(Court.to_dict(st2)) == JSON.stringify(Court.to_dict(st)), "relue à l'identique")
	var st3 := new_game(31, {"court": "aucune"})
	_ok(not st3.to_dict().has("court"), "Aucune : pas de clé court dans la sauvegarde")
