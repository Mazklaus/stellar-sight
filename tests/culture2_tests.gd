extends RefCounted
## Tests du rayonnement culturel, lot 2 (étude du 2026-11-15) : effets des paliers (Savoir par route,
## routes plus riches, espionnage plus rapide, opinion, lassitude de guerre, migrants, faveur des
## mineurs), osmose des lois (offre, adoption gratuite, refus et stabilité), osmose des savoirs,
## pression sur les courants, « Vivre comme eux », défection culturelle (compte à rebours, annulation,
## passage), victoire du Grand Rayonnement et alertes, score, pillage du Musée. Appelés par smoke_test.gd.

const C1 := preload("res://tests/culture_tests.gd")

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Rayonnement culturel (effets, défection, victoire)…")
	_test_effects()
	_test_law_osmosis()
	_test_tech_osmosis()
	_test_currents()
	_test_defection()
	_test_victory()
	_test_capture()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


func _test_effects() -> void:
	var st := C1.new_game()
	C1.meet(st, 0, 1)
	st.trade["routes"] = [{"kind": "ext", "from": 0, "to": 1, "blocked": false, "net": 5, "value": 5}]
	_ok(CultureLife.income_of(st, 0).get("knowledge", 0) == 0, "Exotique : pas encore de Savoir par route")
	st.culture["tier"]["0>1"] = 2
	_ok(int(CultureLife.income_of(st, 0).get("knowledge", 0)) == 1, "Familier : +1 Savoir par route")
	st.culture["tier"]["0>1"] = 4
	_ok(int(CultureLife.income_of(st, 0).get("knowledge", 0)) == 3, "Influent : +3 Savoir par route")
	_ok(CultureLife.route_pct(st, 0, 1) == 25 and CultureLife.route_pct(st, 1, 0) == 0, "Influent : routes vers lui +25 %")
	_ok(CultureLife.spy_days_pct(st, 0, 1) < 0 and CultureLife.spy_days_pct(st, 1, 0) == 0, "Influent : opérations plus rapides chez lui")
	var op := Culture.opinion_parts(st, 1, 0)
	_ok(not op.is_empty() and int(op[0][1]) == 9, "Influent : +9 d'opinion chez lui (3 par palier dès Familier)")
	var found := false
	for p in Diplomacy.opinion_parts(st, 1, 0):
		found = found or String(p["label"]).begins_with("Culture")
	_ok(found, "la ligne apparaît dans l'opinion")
	_ok(CultureLife.war_ex_pct(st, {"a": 1, "d": 0}, 1) == 50 and CultureLife.war_ex_pct(st, {"a": 0, "d": 1}, 0) == 0, "attaquer une culture Influente chez soi : lassitude +50 %")
	_ok(CultureLife.migrant_pull(st, 1, 0) > 0 and CultureLife.migrant_pull(st, 0, 1) == 0, "les migrants préfèrent l'empire qui les fascine")
	var sm := C1.new_game(11, {"minors": "normal"})
	var mid := Minors.ids(sm)[0]
	Minors.get_m(sm, mid)["contact"][0] = 0
	Minors.get_m(sm, mid)["fav"][0] = 10
	sm.culture["tier"]["0>%d" % mid] = 4
	CultureLife._minors(sm, [0] as Array[int])
	_ok(Minors.fav(sm, mid, 0) == 11, "Influent chez un peuple mineur : +1 faveur par mois")


func _pol_game() -> GameState:
	return C1.new_game(11, {"politics": Politics.default_mode()})


func _test_law_osmosis() -> void:
	var st := _pol_game()
	if not Laws.applies(st, 0) or not Laws.applies(st, 1):
		_ok(true, "politique absente pour ces peuples (osmose sautée)")
		return
	C1.meet(st, 0, 1)
	Laws._w(st, 0)["laws"].append("pain_jeux")
	st.culture["tier"]["0>1"] = 3
	st.culture["cum"]["0>1"] = Culture.heritage(st, 1)
	var added: Array[Dictionary] = []
	st.get_empire(1).ai_level = ""
	CultureLife._offer_law(st, 1, added)
	var off := CultureLife.pending_offer(st, 1)
	_ok(String(off.get("law", "")) == "pain_jeux" and int(off.get("from", -1)) == 0, "En vogue : une loi est proposée par osmose")
	_ok(SimCommands.validate(st, SimCommands.cul_act(1, "osmose", -1, "", 1)) == "", "réponse possible")
	SimCommands.apply(st, SimCommands.cul_act(1, "osmose", -1, "", 1))
	_ok(Laws.is_enacted(st, 1, "pain_jeux") and CultureLife.pending_offer(st, 1).is_empty(), "acceptée : la loi passe, gratuitement")
	var close := false
	for m in st.memories:
		close = close or (int(m["who"]) == 1 and String(m["kind"]) == "culture_osmose")
	_ok(close, "acceptée : les deux peuples se rapprochent")
	# Refus : stabilité.
	var st2 := _pol_game()
	C1.meet(st2, 0, 1)
	Laws._w(st2, 0)["laws"].append("pain_jeux")
	st2.culture["tier"]["0>1"] = 3
	st2.culture["cum"]["0>1"] = Culture.heritage(st2, 1)
	st2.get_empire(1).ai_level = ""
	CultureLife._offer_law(st2, 1, added)
	SimCommands.apply(st2, SimCommands.cul_act(1, "osmose", -1, "", 0))
	var sid := FactionTraits.capital_system(st2, 1)
	var hit := false
	for p in Stability.parts(st2, sid):
		hit = hit or (String(p[0]).begins_with("Modèle étranger refusé") and int(p[1]) == -10)
	_ok(hit and not Laws.is_enacted(st2, 1, "pain_jeux"), "refusée : -10 stabilité pendant un an")
	_ok(int(st2.culture["osm_cd"]["1"]) > st2.tick, "au plus une osmose par an")
	CultureLife._offer_law(st2, 1, added)
	_ok(CultureLife.pending_offer(st2, 1).is_empty(), "pas de nouvelle offre avant un an")


func _test_tech_osmosis() -> void:
	var st := C1.new_game()
	C1.meet(st, 0, 1)
	_ok(CultureLife.tech_offers(st, 1).is_empty() or Culture.tier(st, 0, 1) >= 3, "pas d'osmose des savoirs sans culture En vogue")
	Research.grant(st, 0, ["rhetorique", "chancelleries"])
	st.culture["tier"]["0>1"] = 3
	var offers := CultureLife.tech_offers(st, 1)
	var tid := ""
	for t in offers:
		if not st.get_empire(1).techs.has(t):
			tid = t
			break
	_ok(tid != "", "En vogue : ses savoirs s'ouvrent (%d)" % offers.size())
	if tid == "":
		return
	st.get_empire(1).resources["energy"] = 100000
	_ok(SimCommands.validate(st, SimCommands.cul_act(1, "savoir", -1, tid)) == "", "achat possible")
	var before := int(st.get_empire(1).resources["energy"])
	SimCommands.apply(st, SimCommands.cul_act(1, "savoir", -1, tid))
	_ok(Research.knows(st, 1, tid) and int(st.get_empire(1).resources["energy"]) < before, "technologie apprise contre de l'énergie")


func _test_currents() -> void:
	var st := _pol_game()
	if not st.politics_on or not Politics.applies(st, 1) or not Politics.applies(st, 0):
		_ok(true, "pas de courants pour ces peuples (sauté)")
		return
	C1.meet(st, 0, 1)
	st.culture["tier"]["0>1"] = 5
	var i := Politics.principal(st, 0)
	var sid := FactionTraits.capital_system(st, 1)
	var before := int(Politics.opinion(st, sid)[i])
	CultureLife._push_currents(st, 1)
	_ok(int(Politics.opinion(st, sid)[i]) > before or before >= 1000, "Dominant : son courant principal gagne chez la cible")
	# « Vivre comme eux » : un système peu stable, hors capitale.
	var s2 := -1
	var jumps := FactionTraits.jumps_from(st.galaxy, sid)
	for s in st.galaxy.systems:
		if st.system_owner(s.id) < 0 and not s.planet_ids.is_empty() and int(jumps.get(s.id, 99)) <= 3:
			var c := Colony.new()
			c.planet_id = s.planet_ids[0]
			c.owner = 1
			c.kind = Colony.KIND_COLONY
			c.population = 3
			st.add_colony(c)
			s2 = s.id
			break
	Stability._entry_w(st, s2)["v"] = 20
	var live := false
	for p in CultureLife.stability_parts(st, s2, 1):
		live = live or String(p[0]).begins_with("« Vivre comme eux »")
	_ok(live, "Dominant et stabilité basse : « Vivre comme eux »")


## Deux colonies voisines : une de b (hors capitale), une de a à deux sauts au plus. [sid de b, sid de a].
func _border(st: GameState, a: int, b: int) -> Array:
	var cap := FactionTraits.capital_system(st, b)
	var jumps := FactionTraits.jumps_from(st.galaxy, cap)
	for s in st.galaxy.systems:
		if st.system_owner(s.id) >= 0 or s.planet_ids.is_empty() or int(jumps.get(s.id, 99)) > 4 or s.id == cap:
			continue
		var nj := FactionTraits.jumps_from(st.galaxy, s.id)
		for n in st.galaxy.systems:
			if n.id == s.id or st.system_owner(n.id) >= 0 or n.planet_ids.is_empty() or int(nj.get(n.id, 99)) > 2:
				continue
			for pair in [[s, b], [n, a]]:
				var c := Colony.new()
				c.planet_id = (pair[0] as StarSystem).planet_ids[0]
				c.owner = int(pair[1])
				c.kind = Colony.KIND_COLONY
				c.population = 3
				st.add_colony(c)
			return [s.id, n.id]
	return []


func _test_defection() -> void:
	var st := C1.new_game()
	C1.meet(st, 0, 1)
	var pair := _border(st, 0, 1)
	_ok(not pair.is_empty(), "deux colonies voisines pour le test")
	if pair.is_empty():
		return
	var sid := int(pair[0])
	var ids := Culture.living(st)
	var added: Array[Dictionary] = []
	st.culture["tier"]["0>1"] = 4
	st.culture["last"]["0>1"] = 500
	st.culture["rad"]["1"] = 1
	Stability._entry_w(st, sid)["v"] = 5
	CultureLife._defection(st, ids, added)
	_ok(CultureLife.defections_of(st, 1).is_empty(), "sans Conversion culturelle, pas de défection")
	Research.grant(st, 0, ["conversion_culturelle"])
	Stability._entry_w(st, sid)["v"] = 25
	CultureLife._defection(st, ids, added)
	_ok(CultureLife.defections_of(st, 1).is_empty(), "réglage « rare » : il faut une révolte (stabilité 25 : non)")
	Stability._entry_w(st, sid)["v"] = 5
	CultureLife._defection(st, ids, added)
	var d := CultureLife.defections_of(st, 1)
	_ok(d.size() == 1 and int(d[0][0]) == sid and int(d[0][1]) == 0 and int(d[0][2]) == 720, "compte à rebours de deux ans, affiché")
	_ok(not CultureLife.defections_of(st, 1).any(func(x: Array) -> bool: return int(x[0]) == FactionTraits.capital_system(st, 1)), "jamais la capitale")
	# La guerre l'annule.
	st.get_empire(1).wars.append(2)
	CultureLife._defection(st, ids, added)
	_ok(CultureLife.defections_of(st, 1).is_empty(), "une guerre annule la défection")
	st.get_empire(1).wars.erase(2)
	st.culture["def_last"].erase("1")
	CultureLife._defection(st, ids, added)
	st.culture["def"][str(sid)]["end"] = st.tick
	CultureLife._defection(st, ids, added)
	_ok(st.system_owner(sid) == 0, "au bout du compte à rebours, le système change de drapeau")
	var off := C1.new_game(11, {"culture_defect": "aucune"})
	C1.meet(off, 0, 1)
	var p2 := _border(off, 0, 1)
	Research.grant(off, 0, ["conversion_culturelle"])
	off.culture["tier"]["0>1"] = 5
	off.culture["last"]["0>1"] = 900
	Stability._entry_w(off, int(p2[0]))["v"] = 0
	CultureLife._defection(off, Culture.living(off), added)
	_ok(CultureLife.defections_of(off, 1).is_empty(), "réglage « aucune » : jamais de défection")


func _test_victory() -> void:
	var off := C1.new_game(11, {"culture": "aucun"})
	_ok(not Victory.enabled(off, "rayonnement"), "sans rayonnement, pas de Grand Rayonnement")
	var st := C1.new_game()
	_ok(Victory.enabled(st, "rayonnement"), "Grand Rayonnement en jeu par défaut")
	var nov := C1.new_game(11, {"victories": {"rayonnement": false}})
	_ok(not Victory.enabled(nov, "rayonnement"), "décochable dans la Nouvelle partie")
	for e in st.empires:
		if e.id != 0:
			C1.meet(st, 0, e.id)
			st.culture["tier"]["0>%d" % e.id] = 4
	var pr := Victory.progress(st, 0, "rayonnement")
	_ok(bool(pr["cond"]), "Influent chez chaque empire survivant : le compte à rebours démarre")
	_ok(int(pr["hold"]) == 720, "à tenir deux ans")
	st.culture["tier"]["0>1"] = 3
	_ok(not bool(Victory.progress(st, 0, "rayonnement")["cond"]), "un seul empire manquant suffit à arrêter")
	var added: Array[Dictionary] = []
	CultureLife._alerts(st, Culture.living(st), added)
	var alert := false
	for a in added:
		alert = alert or String(a.get("text", "")).begins_with("Alerte culturelle")
	_ok(alert, "alerte à toute la galaxie aux trois quarts")
	_ok(Culture.score(st, 0) > 0 and Victory.score(st, 0) >= Culture.score(st, 0), "le rayonnement compte dans le score")
	_ok(Victory.info("idole").get("requires", {}).get("credo", []).has("plaisir"), "L'Idole des étoiles : victoire du credo Plaisir")
	_ok(not Victory.applies(st, 0, "idole"), "un peuple sans Plaisir n'y a pas droit")


func _test_capture() -> void:
	var st := C1.new_game()
	if st.relics.is_empty():
		_ok(true, "pas de reliques (pillage sauté)")
		return
	var c := C1.colony_of(st, 1)
	c.buildings.append("musee_galactique")
	var rid := Relics.ids()[0]
	Relics.gain(st, 1, rid)
	var added: Array[Dictionary] = []
	Culture.monthly(st, added)
	_ok((st.culture["exp"]["1"] as Array).has(rid), "relique exposée")
	var sid := FactionTraits.capital_system(st, 1)
	Culture.on_capture(st, sid, 0, 1, added)
	_ok(int(st.relics[rid]["owner"]) == 0, "le conquérant emporte les reliques exposées")
