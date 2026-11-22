extends RefCounted
## Tests des peuples insolites, lot 2 (étude « Les 15 peuples insolites et le 9e peuple », prop. 35 à
## 58, 106 à 111 pour leur part) : les peuples qui vivent chez les autres. Implants de plusieurs sortes,
## Compagnie Ventrelune (parts, licence, nationalisation, défaut, OPA), Bureau des Affaires Courantes
## (normes, Non-conformité, Mise en demeure et Procédure, paperasse, Administration totale), Enfants du
## Signal (nœuds, bande passante, pare-feu, hébergement, corps empruntés, mutations, Saturation), Rêveurs
## d'Ysmer (rêveries, Éveillés, souffles, flotte de songe, Rêve commun), choc des tons Bureau /
## Brisecomète, partie de 10 ans jouée par l'IA, déterminisme, sauvegarde.

const ODD := ["ventrelune", "bureau", "signal", "ysmer"]

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Peuples insolites (lot 2)…")
	_test_data()
	_test_found()
	_test_implants()
	_test_ventrelune()
	_test_bureau()
	_test_signal()
	_test_ysmer()
	_test_tones()
	_test_ai_game()


func _ok(cond: bool, what: String) -> void:
	print("  ", "ok " if cond else "KO ", what)
	_check.call(cond, what)


func _game(seed_value := 11, player := "ossarane", rivals: Array = ODD + ["vael", "teyl"]) -> GameState:
	var r: Array = rivals.duplicate()
	return GameState.create(seed_value, 150, 1800.0, player, {"ai_level": "", "rivals": r})


func _eid(st: GameState, faction: String) -> int:
	for e in st.empires:
		if e.faction_id == faction:
			return e.id
	return -1


func _contact(st: GameState, a: int, b: int) -> void:
	for p in [[a, b], [b, a]]:
		if not st.get_empire(p[0]).contacts.has(p[1]):
			st.get_empire(p[0]).contacts.append(p[1])


func _trade(st: GameState, a: int, b: int, on := true) -> void:
	_contact(st, a, b)
	Diplomacy._rel_w(st, a, b)["trade"] = 1 if on else 0


func _home(st: GameState, eid: int) -> int:
	var e := st.get_empire(eid)
	return e.capital_planet if e.capital_planet >= 0 else e.home_planet


func _cols(st: GameState, eid: int) -> Array[int]:
	var out: Array[int] = []
	for pid in st.sorted_colony_ids():
		var c: Colony = st.colonies[pid]
		if c.owner == eid and c.is_colony():
			out.append(int(pid))
	return out


func _month(st: GameState) -> void:
	var added: Array[Dictionary] = []
	Insolites._implant_month(st, added)


func _test_data() -> void:
	var odd := GameData.insolite_faction_ids()
	var all_ok := true
	for fid in ODD:
		var f := GameData.faction(fid)
		all_ok = all_ok and odd.has(fid) and bool(f.get("insolite", false)) and String(f.get("broken_rule", "")) != "" \
				and Insolites.kind_of_faction(f) == fid and f.has("guest") and not FactionTraits.species(f).is_empty()
	_ok(all_ok, "quatre peuples qui vivent chez les autres : fiche insolite, règle cassée, champ « guest », espèce construite")
	_ok(Insolites.worldless(GameData.faction("signal")) and not Insolites.worldless(GameData.faction("ventrelune")) and Insolites.worldless(GameData.faction("exode")),
			"seul le Signal (et les nomades) part sans monde")
	var vic_ok := true
	for v in ["opa", "administration", "saturation", "reve_commun"]:
		vic_ok = vic_ok and Victory.is_people(v) and Research.tech(Victory.tech_for(v)).get("victory", "") == v
	_ok(vic_ok, "quatre victoires de peuple, chacune avec sa technologie")
	_ok(Victory.people_ids_for(GameData.faction("signal")).has("saturation") and Victory.people_ids_for(GameData.faction("ysmer")).has("reve_commun"), "la Saturation va au Signal, le Rêve commun aux Ysmer")
	_ok(InsBureau.norm_defs().size() >= 6, "catalogue ouvert des normes du Bureau (%d)" % InsBureau.norm_defs().size())
	_ok(Insolites.implant_def("noeud").get("hidden", false) and Insolites.implant_def("reverie").get("hidden", false) and not Insolites.implant_def("guichet").get("hidden", true),
			"nœuds et rêveries cachés, guichets visibles")
	_ok(int(GameData.faction("ventrelune").get("colony_influence_pct", 100)) == 400, "la Compagnie colonise à quatre fois le prix en influence")


func _test_found() -> void:
	var st := _game()
	var v := _eid(st, "ventrelune")
	var s := _eid(st, "signal")
	_ok(_cols(st, v).size() == 1 and _cols(st, _eid(st, "bureau")).size() == 1 and _cols(st, _eid(st, "ysmer")).size() == 1, "Compagnie, Bureau et Ysmer ont un monde natal")
	_ok(_cols(st, s).is_empty() and Fleets.empire_fleets(st, s).is_empty(), "le Signal n'a ni planète ni vaisseau")
	_ok(InsSignal.nodes(st, s).size() == 3 and Insolites.keeps_alive(st, s), "trois nœuds au départ, qui le gardent en vie")
	var host := (st.colonies[InsSignal.nodes(st, s)[0]] as Colony).owner
	_ok(st.get_empire(host).contacts.has(s) and st.get_empire(s).contacts.has(host), "le Signal a rencontré ses hôtes")
	_ok(not Insolites.keeps_alive(st, v), "la Compagnie vit de son Siège, comme un empire classique")
	_ok(Insolites.claim_block(st, _eid(st, "ysmer"), Colony.KIND_COLONY) != "" and Insolites.claim_block(st, _eid(st, "ysmer"), Colony.KIND_OUTPOST) == "", "les Ysmer n'ont qu'un monde (avant-postes permis)")


func _test_implants() -> void:
	var st := _game(13)
	var pid := _home(st, _eid(st, "ossarane"))
	var n0 := Insolites.implants_on(st, pid).size()  # un nœud du Signal y est peut-être déjà
	Insolites.add_implant(st, pid, "fan_club", _eid(st, "vael"))
	Insolites.add_implant(st, pid, "guichet", _eid(st, "bureau"))
	_ok(Insolites.implants_on(st, pid).size() == n0 + 2 and not Insolites.implant(st, pid).is_empty() and not Insolites.implant(st, pid, "guichet").is_empty(), "une planète porte un implant de chaque sorte")
	_ok((st.insolites["implants"] as Dictionary).has(str(pid)), "le Fan-club garde sa clé (sauvegarde 101)")
	Insolites.remove_implant(st, pid, "guichet")
	_ok(Insolites.implants_on(st, pid).size() == n0 + 1 and Insolites.implants_of(st, _eid(st, "bureau"), "guichet").is_empty(), "retirer une sorte laisse les autres")


func _test_ventrelune() -> void:
	var st := _game(21)
	var v := _eid(st, "ventrelune")
	var o := _eid(st, "ossarane")
	var ev := st.get_empire(v)
	var eo := st.get_empire(o)
	ev.resources["energy"] = 5000
	var pid := _home(st, o)
	_contact(st, v, o)
	var cmd := SimCommands.ins_act(v, "buy", {"pid": pid})
	_ok(SimCommands.validate(st, cmd) != "", "pas de parts sans accord commercial (la licence)")
	_trade(st, v, o)
	_ok(SimCommands.validate(st, cmd) == "", "avec la licence, la Compagnie achète")
	var before := int(eo.resources.get("energy", 0))
	SimCommands.apply(st, cmd)
	_ok(InsVentrelune.share(st, v, pid) == 10 and int(eo.resources.get("energy", 0)) > before, "10 % achetés, le propriétaire touche le prix")
	for _i in 5:
		SimCommands.apply(st, cmd)
	_ok(InsVentrelune.share(st, v, pid) == 60, "majorité : 60 %")
	var vs := Fleets.visible_systems(st, v)
	_ok(vs.has(st.galaxy.get_planet(pid).system_id), "à 25 %, la Compagnie voit la colonie")
	eo.resources["energy"] = 1000
	var ve := int(ev.resources["energy"])
	var added: Array[Dictionary] = []
	InsVentrelune.daily(st, v, Insolites.emp(st, v), true, added)
	_ok(int(ev.resources["energy"]) > ve and int(eo.resources["energy"]) < 1000, "dividendes et impôt versés chaque mois")
	_trade(st, v, o, false)
	InsVentrelune.daily(st, v, Insolites.emp(st, v), true, added)
	_ok(not InsVentrelune.licensed(st, v, pid) and Insolites.expropriation_casus(st, v, o) and Wars.casus_list(st, v, o).has("expropriation"), "licence perdue : parts sans licence, motif Expropriation")
	_ok(SimCommands.validate(st, SimCommands.ins_act(o, "nationalize", {"pid": pid})) == "", "le propriétaire peut nationaliser")
	SimCommands.apply(st, SimCommands.ins_act(o, "nationalize", {"pid": pid}))
	_ok(InsVentrelune.share(st, v, pid) == 0 and Diplomacy.opinion(st, v, o) < 0, "nationalisation : parts saisies, opinion en chute")
	_ok(Insolites.contract_fee_pct(st, v) == -30 and Insolites.contract_fee_pct(st, o) == 0, "armée privée : mercenaires 30 % moins chers")
	added.clear()
	InsVentrelune.on_default(st, o, v, 300, added)
	_ok(InsVentrelune.share(st, v, pid) == 30, "un défaut de paiement envers la Compagnie se rembourse en parts")
	# Victoire fabriquée : la majorité de trois rivaux.
	var n := 0
	for e in st.empires:
		if e.id == v or e.is_npc() or _cols(st, e.id).is_empty():
			continue
		_trade(st, v, e.id)
		for cp in _cols(st, e.id):
			(Insolites.emp(st, v)["shares"] as Dictionary)[str(cp)] = 100
		n += 1
		if n >= 3:
			break
	ev.techs["opa_galactique"] = true
	var pr := Victory.progress(st, v, "opa")
	_ok(pr["cond"], "victoire : l'OPA galactique (%s)" % ", ".join(PackedStringArray(pr["lines"])))
	_ok(Insolites.growth_pct(st, v) == int(InsVentrelune.directive_def(st, v).get("growth_pct", 0)), "la directive du Conseil règle la croissance du Siège")


func _test_bureau() -> void:
	var st := _game(31)
	var b := _eid(st, "bureau")
	var o := _eid(st, "ossarane")
	var t := _eid(st, "teyl")
	var vl := _eid(st, "vael")
	_contact(st, b, o)
	_contact(st, b, t)
	_contact(st, b, vl)
	_ok(InsBureau.published(st, b).size() == 2, "deux normes publiées au départ")
	var nc0 := InsBureau.nonconf_pct(st, o)
	_ok(nc0 < 0 and Insolites.trade_pct(st, o) < 100 and Insolites.ship_days_pct(st, o) > 0, "Non-conformité : commerce et chantiers ralentis (%d %%)" % nc0)
	var norm := String(InsBureau.published(st, b)[0])
	SimCommands.apply(st, SimCommands.ins_act(t, "sign", {"b": b, "norm": norm}))
	_ok(InsBureau.nonconf_pct(st, o) < nc0, "plus il y a de signataires, plus refuser coûte")
	for n in InsBureau.published(st, b):
		var cmd := SimCommands.ins_act(t, "sign", {"b": b, "norm": String(n)})
		if SimCommands.validate(st, cmd) == "":
			SimCommands.apply(st, cmd)
	_ok(InsBureau.conforms(st, b, t) and InsBureau.nonconf_pct(st, t) == 0, "Teyl a tout signé : en règle")
	_ok(Combat.check_declare_war(st, b, o) != "", "le Bureau ne déclare pas de guerre")
	for e in st.empires:  # les autres se mettent en règle : la Procédure aura ses voix
		if e.id == b or e.id == o or e.is_npc() or not e.contacts.has(b):
			continue
		for n in InsBureau.published(st, b):
			var cmd := SimCommands.ins_act(e.id, "sign", {"b": b, "norm": String(n)})
			if SimCommands.validate(st, cmd) == "":
				SimCommands.apply(st, cmd)
	SimCommands.apply(st, SimCommands.ins_act(b, "summon", {"target": o}))
	var ed := Insolites.emp(st, b)
	ed["summon"][str(o)] = st.tick
	var added: Array[Dictionary] = []
	InsBureau.daily(st, b, ed, false, added)
	_ok(InsBureau.sanctioned(st, o) and Insolites.production_bonus(st, o, "energy") <= -10, "Procédure votée : %s sanctionné" % st.get_empire(o).short_name())
	_ok(Insolites.claim_extra_days(st, b, Colony.KIND_COLONY) == 360 and Insolites.claim_extra_days(st, o, Colony.KIND_COLONY) == 0, "paperasse : un an de dossier par colonie du Bureau")
	_ok(bool(Admin.talent(st, b).get("no_corruption", false)) and int(Admin.talent(st, b).get("cap_pct", 0)) == 50, "aucune corruption, capacité +50 %")
	var total := func() -> int:
		var n := 0
		for k in (ed["sign"] as Dictionary):
			n += (ed["sign"][k] as Array).size()
		return n
	var before: int = total.call()
	InsBureau._lose_file(st, b, ed, added)
	_ok(total.call() == before - 1, "le Bureau perd une signature (dossier égaré)")
	# Victoire fabriquée : tout le monde signe tout. Deux normes ne suffisent plus (équilibrage, lot 6).
	var bed := Insolites.emp(st, b)
	var need_norms := int(Insolites.cfg("bureau")["total_min_norms"])
	for e in st.empires:
		if e.id != b and not e.is_npc():
			_contact(st, b, e.id)
			for n in InsBureau.published(st, b):
				var c0 := SimCommands.ins_act(e.id, "sign", {"b": b, "norm": String(n)})
				if SimCommands.validate(st, c0) == "":
					SimCommands.apply(st, c0)
	st.get_empire(b).techs["administration_totale"] = true
	_ok(need_norms == 5 and InsBureau.published(st, b).size() < need_norms and not Victory.progress(st, b, "administration")["cond"], "Administration totale : pas avant cinq normes en vigueur")
	st.get_empire(b).techs.erase("administration_totale")
	for nd: Dictionary in Insolites.cfg("bureau")["norms"]:
		if (bed["norms"] as Array).size() < need_norms and not (bed["norms"] as Array).has(String(nd["id"])):
			(bed["norms"] as Array).append(String(nd["id"]))
	_ok(int(GameData.victories()["victories"]["administration"]["hold_days"]) == 1080, "Administration totale : tenue trois ans")
	for e in st.empires:
		if e.id == b or e.is_npc():
			continue
		_contact(st, b, e.id)
		for n in InsBureau.published(st, b):
			var cmd := SimCommands.ins_act(e.id, "sign", {"b": b, "norm": String(n)})
			if SimCommands.validate(st, cmd) == "":
				SimCommands.apply(st, cmd)
	st.get_empire(b).techs["administration_totale"] = true
	_ok(Victory.progress(st, b, "administration")["cond"], "victoire : l'Administration totale")
	_ok(InsBureau.norm_fx(st, o, "trade_pct") > 0 and Insolites.trade_pct(st, o) > 100, "une norme signée donne son avantage")
	# Guichets : chez les signataires avec qui le Bureau commerce.
	_trade(st, b, o)
	InsBureau._month(st, b, ed, added)
	_ok(Insolites.implants_of(st, b, "guichet").size() >= 1, "un Guichet ouvre chez un signataire commerçant")


func _test_signal() -> void:
	var st := _game(41)
	var s := _eid(st, "signal")
	var pid := InsSignal.nodes(st, s)[0]
	var host := (st.colonies[pid] as Colony).owner
	var eh := st.get_empire(host)
	_ok(not Insolites.implant_visible(st, pid, host, "noeud"), "le nœud est invisible pour l'hôte")
	eh.techs["propagande"] = true
	_ok(Insolites.implant_visible(st, pid, host, "noeud"), "le pare-feu culturel (Propagande) le révèle")
	eh.resources["knowledge"] = 200
	var k0 := int(st.get_empire(s).resources.get("knowledge", 0))
	_month(st)
	_ok(int(st.get_empire(s).resources.get("knowledge", 0)) > k0 and int(eh.resources["knowledge"]) < 200, "bande passante : le Savoir de l'hôte passe au Signal")
	var sid := st.galaxy.get_planet(pid).system_id
	_ok(InsSignal.symptoms(st, sid, host), "symptômes chez l'hôte")
	_ok(Diplomacy.check_terms(st, host, s, Diplomacy.PEACE) != "" and Combat.check_declare_war(st, s, host) != "", "le Signal ne signe aucun traité, ne déclare aucune guerre")
	SimCommands.apply(st, SimCommands.ins_act(host, "host", {"s": s}))
	_ok(InsSignal.hosted(st, s, host) and not InsSignal.symptoms(st, sid, host), "Accord d'hébergement : plus de symptômes")
	_ok(Insolites.check_purge(st, host, pid, "noeud") != "", "un nœud toléré ne se purge pas")
	SimCommands.apply(st, SimCommands.ins_act(host, "unhost", {"s": s}))
	eh.resources["knowledge"] = 500
	_ok(SimCommands.validate(st, SimCommands.ins_act(host, "purge", {"pid": pid, "k": "noeud"})) == "", "l'hôte purge le nœud")
	SimCommands.apply(st, SimCommands.ins_act(host, "purge", {"pid": pid, "k": "noeud"}))
	_ok(Insolites.implant(st, pid, "noeud").is_empty(), "nœud purgé")
	_ok(InsSignal.vulnerable(st, _eid(st, "teyl")) and not InsSignal.vulnerable(st, _eid(st, "vael")), "Teyl (synthétique, Noosphère) est plus vulnérable")
	# Corps empruntés : douze nœuds.
	var ed := Insolites.emp(st, s)
	for e in st.empires:
		for cp in _cols(st, e.id):
			if e.id != s and not e.is_npc():
				Insolites.add_implant(st, cp, "noeud", s)
	var added: Array[Dictionary] = []
	var have := InsSignal.nodes(st, s).size()
	if have >= Insolites.c_int("signal", "borrow_nodes", 12):
		InsSignal.daily(st, s, ed, true, added)
		_ok(Fleets.empire_fleets(st, s).size() == 1, "corps empruntés : une flotte détournée")
	else:
		ed["borrow_cd"] = 0
		InsSignal._borrow(st, s, ed, InsSignal.nodes(st, s), added)
		_ok(Fleets.empire_fleets(st, s).size() == 1, "corps empruntés : une flotte détournée (cas forcé, %d nœuds)" % have)
	st.tick += Insolites.c_int("signal", "borrow_days", 120)
	InsSignal.daily(st, s, ed, false, added)
	_ok(Fleets.empire_fleets(st, s).is_empty(), "les corps empruntés s'éteignent au bout de 120 jours")
	ed["mut_next"] = st.tick
	InsSignal.daily(st, s, ed, false, added)
	_ok((ed["mut"] as Array).size() == 1, "mutation : une variante gagne un trait")
	st.get_empire(s).techs["saturation"] = true
	_ok(Victory.progress(st, s, "saturation")["cond"], "victoire : la Saturation (nœuds partout)")


func _test_ysmer() -> void:
	var st := _game(51)
	var y := _eid(st, "ysmer")
	var o := _eid(st, "ossarane")
	var pid := _home(st, o)
	_ok(not InsYsmer.organic(st, _eid(st, "teyl")) and InsYsmer.organic(st, o), "les synthétiques ne rêvent pas")
	Insolites.add_implant(st, pid, "reverie", y)
	_contact(st, y, o)
	_ok(not Insolites.implant_visible(st, pid, o, "reverie"), "la rêverie est invisible sans Éveillés")
	var ey := st.get_empire(y)
	ey.resources["influence"] = 500
	var k0 := int(st.get_empire(o).resources.get("knowledge", 0))
	SimCommands.apply(st, SimCommands.ins_act(y, "inspire", {"pid": pid}))
	_ok(int(st.get_empire(o).resources.get("knowledge", 0)) == k0 + 30, "souffler une inspiration : +30 Savoir pour l'hôte")
	SimCommands.apply(st, SimCommands.ins_act(y, "nightmare", {"pid": pid}))
	var labels := []
	for p in Insolites.stability_parts(st, st.galaxy.get_planet(pid).system_id, o):
		labels.append(String(p[0]))
	_ok(labels.has("Cauchemars des Ysmer"), "cauchemars : stabilité en baisse")
	_ok(SimCommands.validate(st, SimCommands.ins_act(y, "dream_fleet")) == "", "les Ysmer peuvent rêver une flotte")
	var added: Array[Dictionary] = []
	SimCommands.apply(st, SimCommands.ins_act(y, "dream_fleet"))
	var dream := 0
	for f in Fleets.empire_fleets(st, y):
		if f.fleet_name == "Flotte de songe":
			dream += 1
	_ok(dream == 1, "une flotte de songe apparaît au-dessus du Dormeur")
	st.tick += 90
	InsYsmer.daily(st, y, Insolites.emp(st, y), false, added)
	dream = 0
	for f in Fleets.empire_fleets(st, y):
		if f.fleet_name == "Flotte de songe":
			dream += 1
	_ok(dream == 0, "elle se dissipe au bout de 90 jours")
	_ok(Insolites.income(st, y).get("influence", 0) >= 1, "chaque rêverie rapporte de l'influence")
	_ok(Insolites.check_purge(st, o, pid, "reverie") != "", "sans Éveillés, pas de chasse aux rêveries")
	# Propagation : quelques années de nuits.
	var n0 := InsYsmer.reveries(st, y).size()
	for m in 60:
		st.tick += 30
		InsYsmer._spread(st, y)
	_ok(InsYsmer.reveries(st, y).size() >= n0, "les rêveries restent en place (%d → %d)" % [n0, InsYsmer.reveries(st, y).size()])
	var teyl_hit := false
	for p2 in InsYsmer.reveries(st, y):
		teyl_hit = teyl_hit or (st.colonies[p2] as Colony).owner == _eid(st, "teyl")
	_ok(not teyl_hit, "aucune rêverie chez Teyl")
	for e in st.empires:
		for cp in _cols(st, e.id):
			if e.id != y and InsYsmer.organic(st, e.id):
				Insolites.add_implant(st, cp, "reverie", y)
	ey.techs["reve_commun"] = true
	_ok(Victory.progress(st, y, "reve_commun")["cond"], "victoire : le Rêve commun")


func _test_tones() -> void:
	var st := _game(61, "brisecomete", ["bureau", "vael"])
	var b := _eid(st, "bureau")
	var c := _eid(st, "brisecomete")
	var labels := []
	for p in Diplomacy.opinion_parts(st, b, c):
		labels.append(String(p["label"]))
	_ok(labels.has("Le Syndicat a fait passer en contrebande l'original du Formulaire B-7"), "choc des tons Bureau / Brisecomète dans l'opinion")
	var added: Array[Dictionary] = []
	Events.on_contact(st, st.get_empire(c), st.get_empire(b), added)
	var got := false
	for it in Events.meta(st, c).get("inbox", []):
		if String(it.get("card", "")) == "t_formulaire_contrebande":
			got = true
	_ok(not Events.enabled(st) or got, "premier contact : la carte « le Formulaire et la Contrebande »")


func _test_ai_game() -> void:
	var opts := {"spectator": true, "ai_level": "normal", "rivals": ["ventrelune", "bureau", "signal", "ysmer", "ossarane", "vael", "brisecomete"]}
	var st := GameState.create(7, 150, 1800.0, "", opts.duplicate(true))
	var sim := Simulation.new(st)
	var alive5 := true
	var early_win := false
	var bought := false
	var signed := false
	var spread := false
	var dreamt := false
	var s := _eid(st, "signal")
	var b := _eid(st, "bureau")
	for d in 3600:
		sim.step()
		if not bought:
			bought = not InsVentrelune.shares(st, _eid(st, "ventrelune")).is_empty()
		if not signed:
			signed = not (Insolites.emp(st, b).get("sign", {}) as Dictionary).is_empty()
		if not spread:
			spread = InsSignal.nodes(st, s).size() > Insolites.c_int("signal", "start_nodes", 3)
		if not dreamt:
			dreamt = InsYsmer.reveries(st, _eid(st, "ysmer")).size() > 1
		if d == 1799:
			for fid in ODD:
				alive5 = alive5 and not st.get_empire(_eid(st, fid)).eliminated
		if not st.winner.is_empty():
			early_win = true
	_ok(alive5, "les quatre peuples survivent jusqu'à l'an 5")
	_ok(not early_win, "aucune victoire en 10 ans")
	_ok(bought, "IA : la Compagnie achète des parts")
	_ok(signed, "IA : des empires signent les normes du Bureau")
	_ok(spread, "IA : le Signal se propage")
	_ok(dreamt, "IA : les rêveries gagnent du terrain")
	var d1 := st.to_dict()
	var st2 := GameState.from_dict(JSON.parse_string(JSON.stringify(d1)))
	_ok(st2 != null and JSON.stringify(st2.to_dict()) == JSON.stringify(d1), "sauvegarde relue à l'identique")
	var a := GameState.create(9, 120, 1600.0, "", opts.duplicate(true))
	var bb := GameState.create(9, 120, 1600.0, "", opts.duplicate(true))
	var sa := Simulation.new(a)
	var sb := Simulation.new(bb)
	for _d in 720:
		sa.step()
		sb.step()
	_ok(JSON.stringify(a.to_dict()) == JSON.stringify(bb.to_dict()), "déterminisme : deux parties identiques restent identiques")
