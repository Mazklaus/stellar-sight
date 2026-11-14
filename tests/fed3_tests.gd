extends RefCounted
## Tests du pilier fédérations et vassaux, lot 3 : sujets spécialisés, possessions, culte imposé,
## flotte fédérale, opérations communes, Communion et Tolérance, loi Hégémonie, stabilité, espionnage,
## héros (Délégué, Résident), talents de peuple par couches d'espèce, sauvegarde 52.
## Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Fédérations et vassaux, lot 3…")
	_test_specs()
	_test_possessions()
	_test_talents()
	_test_cult()
	_test_federal_fleet()
	_test_joint()
	_test_stability()
	_test_spy()
	_test_heroes()
	_test_save()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


func _new(seed_value := 7, opts := {}) -> GameState:
	var o := {"ai_level": "", "koinon": "actif", "vassals": "actifs"}
	o.merge(opts, true)
	var st := GameState.create(seed_value, 150, 1800.0, "vael", o)
	for e in st.empires:
		if e.is_npc():
			continue
		for x in st.empires:
			if x.id != e.id and not x.is_npc() and not e.contacts.has(x.id):
				e.contacts.append(x.id)
		e.resources["influence"] = 3000
		e.resources["energy"] = 5000
		e.resources["materials"] = 5000
		if e.id != 0:
			e.ai_level = "veteran"
	return st


func _majors(st: GameState) -> Array[int]:
	var out: Array[int] = []
	for e in st.empires:
		if not e.is_npc() and not Diplomacy.no_treaties(st, e.id):
			out.append(e.id)
	return out


func _of(st: GameState, faction: String) -> int:
	for e in st.empires:
		if e.faction_id == faction:
			return e.id
	return -1


func _league(st: GameState, a: int, b: int, fid := "marchande") -> int:
	if Combat.at_war(st, a, b):
		Diplomacy.sign_treaty(st, a, b, Diplomacy.PEACE)
	Diplomacy.sign_treaty(st, a, b, Diplomacy.ALLIANCE)
	Diplomacy._rel_w(st, a, b)["since"] = st.tick - 720
	return Koinon.found(st, a, b, fid)


func _test_specs() -> void:
	var st := _new()
	var ms := _majors(st)
	var lord := ms[1]
	var sub := ms[2]
	var cl := Vassals.preset_clauses("vassal")
	cl["spec"] = "prospecteur"
	Vassals.bind(st, lord, sub, "vassal", cl, 700)
	Vassals.link(st, sub)["loy"] = 700
	_ok(Vassals.spec_of(st, sub) == "prospecteur" and Vassals.spec_rank(st, sub) == 3, "Spécialité : rang III à forte loyauté (%d)" % Vassals.loyalty(st, sub))
	_ok(Vassals.production_pct(st, sub, "materials") == 20 and Vassals.production_pct(st, lord, "materials") == 7, "Prospecteur : +20 % de matériaux chez le sujet, +7 % chez le suzerain")
	_ok(int(Vassals.tribute_of(st, sub).get("materials", 0)) == 25, "Prospecteur : tribut en matériaux plus lourd (10 + 15)")
	Vassals.link(st, sub)["loy"] = -10
	_ok(Vassals.spec_rank(st, sub) == 0 and Vassals.production_pct(st, lord, "materials") == 0, "Spécialité : sans effet quand le sujet est déloyal")
	Vassals.link(st, sub)["loy"] = 100
	Vassals.link(st, sub)["cl"]["spec"] = "rempart"
	_ok(Vassals.defense_pct(st, sub) == 10 and Vassals.defense_pct(st, lord) == 3, "Rempart : vaisseaux mieux protégés")
	_ok(int(Combat.defense_bonus(st, sub)["armor"]) - int(Combat.defense_bonus(st, ms[3])["armor"]) != 0 or Research.marks(st, sub) != Research.marks(st, ms[3]), "Rempart : compté dans la protection au combat")
	var bad := Vassals.preset_clauses("vassal")
	bad["spec"] = "satrapie"
	_ok(Vassals.check_clauses_for(st, lord, bad) != "" or bool(Vassals.talent(st, lord).get("satrapy", false)), "Satrapie : réservée aux hordes")


func _test_possessions() -> void:
	var st := _new()
	var ms := _majors(st)
	var lord := ms[1]
	var sub := ms[2]
	Vassals.bind(st, lord, sub, "vassal", Vassals.preset_clauses("vassal"), 300)
	_ok(Vassals.check_build_pos(st, ms[3], sub, "comptoir") != "", "Possessions : seulement chez son sujet")
	var mat := int(st.get_empire(lord).resources["materials"])
	SimCommands.apply(st, SimCommands.vas_act(lord, "build", sub, "comptoir"))
	_ok(Vassals.has_pos(st, sub, "comptoir") and int(st.get_empire(lord).resources["materials"]) == mat - 150, "Comptoir : bâti contre son coût")
	_ok(int(Vassals.tribute_of(st, sub)["materials"]) == 11, "Comptoir : le tribut augmente d'un dixième")
	_ok(Vassals.check_build_pos(st, lord, sub, "comptoir") != "", "Possessions : une seule de chaque")
	SimCommands.apply(st, SimCommands.vas_act(lord, "build", sub, "mission"))
	_ok(Vassals.opinion_bonus(st, sub, lord) == 10, "Mission : +10 d'opinion du sujet envers son suzerain")
	SimCommands.apply(st, SimCommands.vas_act(lord, "build", sub, "garnison"))
	var found := false
	for p in Vassals.loyalty_parts(st, sub):
		if String(p["label"]).begins_with("Garnison"):
			found = true
	_ok(found and Vassals.defense_pct(st, sub) >= 10, "Garnison : protège le sujet et touche sa loyauté selon le credo")


func _test_talents() -> void:
	var st := _new(7, {"rivals": 7})
	var oss := _of(st, "ossarane")
	var vael := _of(st, "vael")
	var kh := _of(st, "khthari")
	if oss >= 0:
		_ok(int(Vassals.talent(st, oss).get("patronage_free", 0)) == 3 and bool(Vassals.talent(st, oss).get("heir_vassal", false)), "Talent Féodalité : pas de patronage divisé jusqu'à 3 sujets")
		var ms := _majors(st)
		var subs: Array[int] = []
		for m in ms:
			if m != oss and subs.size() < 2:
				subs.append(m)
		for s in subs:
			Vassals.bind(st, oss, s, "vassal", Vassals.preset_clauses("vassal"), 300)
		var div := false
		for p in Vassals.loyalty_parts(st, subs[0]):
			if String(p["label"]).begins_with("Patronage"):
				div = true
		_ok(not div, "Féodalité : deux sujets, pas de patronage divisé")
		_ok(Diplomacy.heir_recipient(st, oss) == subs[0] or Diplomacy.heir_recipient(st, oss) == subs[1], "Féodalité : l'héritier livre son fief à un sujet")
	if vael >= 0:
		_ok(bool(Koinon.talent(st, vael).get("quick_found", false)), "Talent République : Koinon sans deux ans d'alliance")
		var other := _majors(st)[0] if _majors(st)[0] != vael else _majors(st)[1]
		if Combat.at_war(st, vael, other):
			Diplomacy.sign_treaty(st, vael, other, Diplomacy.PEACE)
		Diplomacy.sign_treaty(st, vael, other, Diplomacy.ALLIANCE)
		Diplomacy._rel_w(st, vael, other)["trust"] = 100
		var why := Koinon.check_found(st, vael, other, "marchande")
		_ok(not why.contains("ans d'alliance"), "République : fonde aussitôt allié (%s)" % why)
	if kh >= 0:
		_ok(bool(Vassals.talent(st, kh).get("no_koinon", false)) and bool(Vassals.talent(st, kh).get("no_surrender_to", false)), "Talent Ruche + Survie : ni Koinon ni sujets, nul ne se rend devant elle")
	var teyl := _of(st, "teyl")
	if teyl >= 0:
		var o2 := _majors(st)[0] if _majors(st)[0] != teyl else _majors(st)[1]
		Koinon.setup(st, "actif")
		var lid := _league(st, teyl, o2, "savante")
		_ok(Koinon.knowledge_pct(st, teyl) == 10 and Koinon.knowledge_pct(st, o2) == 5, "Talent Conscience : un rang de plus en Ligue savante")
		_ok(lid >= 0, "Conscience : ligue fondée")
	var labels := Vassals.talent_labels(st, oss) if oss >= 0 else []
	_ok(oss < 0 or not labels.is_empty(), "Talents : libellés affichables")


func _test_cult() -> void:
	var st := _new(7, {"faiths": "actives"})
	var ms := _majors(st)
	var lord := ms[1]
	var sub := ms[2]
	Vassals.bind(st, lord, sub, "vassal", Vassals.preset_clauses("vassal"), 300)
	var cl: Dictionary = (Vassals.link(st, sub)["cl"] as Dictionary).duplicate(true)
	cl["cult"] = "impose"
	st.faiths["state"][str(lord)] = Faiths.LAICITE
	_ok(Vassals.check_clauses_for(st, lord, cl) != "", "Culte imposé : il faut une foi d'État")
	st.faiths["state"][str(lord)] = "foi_test"
	_ok(Vassals.check_clauses_for(st, lord, cl) == "", "Culte imposé : possible avec une foi d'État")
	var loy := Vassals.loyalty(st, sub)
	st.tick = int(Vassals.link(st, sub)["next"])
	Vassals.set_terms(st, lord, sub, cl)
	_ok(Faiths.state_faith(st, sub) == "foi_test", "Culte imposé : la foi du suzerain devient celle du sujet")
	var free := bool(Vassals.talent(st, lord).get("cult_free", false))
	_ok((Vassals.loyalty(st, sub) < loy) != free, "Culte imposé : la loyauté baisse (sauf théocratie)")
	# Communion : la Tolérance des deux côtés suffit.
	var st2 := _new(7, {"politics": "active"})
	var m2 := _majors(st2)
	_ok(Koinon._faith_ok(st2, m2[1], m2[1]), "Communion : même foi")
	_ok(not Koinon._faith_ok(st2, m2[1], m2[2]) or Koinon._faith_key(st2, m2[1]) == Koinon._faith_key(st2, m2[2]) or Laws.is_enacted(st2, m2[1], "tolerance"), "Communion : fois différentes sans Tolérance, refusée")


func _test_federal_fleet() -> void:
	var st := _new()
	var ms := _majors(st)
	var lid := _league(st, ms[1], ms[2])
	var l := Koinon.league(st, lid)
	_ok(not Koinon.law_def("fleet").is_empty(), "Flotte fédérale : loi en données")
	l["laws"]["fleet"] = 2
	l["xp"] = 400
	l["ffund"] = 100000
	var model := Koinon.federal_model(st, lid)
	Koinon._federal_month(st, lid)
	var ff := Koinon.federal_fleets(st, lid)
	_ok(model == "" or (ff.size() == 1 and (st.fleets[ff[0]] as Fleet).owner == Koinon.strategos(st, lid)), "Flotte fédérale : l'arsenal livre un vaisseau au Stratège (%s)" % model)
	if not ff.is_empty():
		var up := Fleets.upkeep(st, Koinon.strategos(st, lid))
		var f: Fleet = st.fleets[ff[0]]
		_ok(Koinon.is_federal(st, f.id), "Flotte fédérale : reconnue")
		var ships_up := 0
		for r in up:
			ships_up += int(up[r])
		var without := 0
		for fl in Fleets.empire_fleets(st, Koinon.strategos(st, lid)):
			if fl.id == f.id:
				continue
			for s in fl.ships:
				for r in GameData.ship(s).get("upkeep", {}):
					without += int(GameData.ship(s)["upkeep"][r])
		_ok(ships_up <= without + 1, "Flotte fédérale : sans entretien")
		Koinon.league(st, lid)["strat"] = ms[2] if Koinon.strategos(st, lid) == ms[1] else ms[1]
		Koinon._federal_month(st, lid)
		_ok((st.fleets[f.id] as Fleet).owner == Koinon.strategos(st, lid), "Flotte fédérale : elle suit le nouveau Stratège")
		Koinon._dissolve(st, lid)
		_ok(not st.fleets.has(f.id), "Flotte fédérale : dissoute avec le Koinon")


func _test_joint() -> void:
	var st := _new()
	var ms := _majors(st)
	var lid := _league(st, ms[1], ms[2], "savante")
	var strat := Koinon.strategos(st, lid)
	_ok(Koinon.check_joint(st, strat) != "", "Opération commune : il faut le rang II")
	var l := Koinon.league(st, lid)
	l["xp"] = 150
	l["treasury"] = 500
	for w in st.get_empire(strat).wars.duplicate():
		Diplomacy.sign_treaty(st, strat, int(w), Diplomacy.PEACE)
	var other := ms[2] if strat == ms[1] else ms[1]
	_ok(Koinon.check_joint(st, other) != "", "Opération commune : seul le Stratège la lance")
	_ok(Koinon.check_joint(st, strat) == "", "Opération commune : possible au rang II, en paix (%s)" % Koinon.check_joint(st, strat))
	SimCommands.apply(st, SimCommands.koi_act(strat, "joint"))
	_ok(int(l["treasury"]) == 350 and not (l["joint"] as Dictionary).is_empty(), "Opération commune : payée par le trésor, en cours")
	_ok(Koinon.check_joint(st, strat) != "", "Opération commune : une par décennie")
	var coh := Koinon.cohesion(st, lid)
	st.tick = int(l["joint"]["until"])
	Koinon._joint_month(st, lid)
	_ok((l["joint"] as Dictionary).is_empty() and Koinon.cohesion(st, lid) != coh, "Opération commune : tranchée au terme (cohésion %d -> %d)" % [coh, Koinon.cohesion(st, lid)])


func _test_stability() -> void:
	var st := _new()
	var ms := _majors(st)
	Vassals.bind(st, ms[1], ms[2], "vassal", Vassals.preset_clauses("vassal"), 900)
	var parts := Vassals.stability_parts(st, ms[1])
	_ok(not parts.is_empty() and int(parts[0][1]) > 0, "Stabilité : un sujet loyal apaise le suzerain")
	Vassals.link(st, ms[2])["loy"] = -300
	Vassals.link(st, ms[2])["cl"]["dip"] = "aucune"
	var sp := Vassals.stability_parts(st, ms[2])
	_ok(not sp.is_empty() and int(sp[0][1]) < 0, "Stabilité : un sujet humilié s'agite")


func _test_spy() -> void:
	var st := _new()
	var ms := _majors(st)
	var spy := ms[3]
	Vassals.bind(st, ms[1], ms[2], "vassal", Vassals.preset_clauses("vassal"), 300)
	_ok(Vassals.spy_check(st, ms[1], ms[2], "attiser_independance") != "", "Espionnage : pas contre son propre sujet")
	_ok(Vassals.spy_check(st, spy, ms[2], "attiser_independance") == "", "Espionnage : attiser l'indépendance chez le sujet d'un rival")
	var loy := Vassals.loyalty(st, ms[2])
	Vassals.spy_apply(st, spy, ms[2], Espionage.op_def("attiser_independance"))
	_ok(Vassals.loyalty(st, ms[2]) == loy - 150, "Espionnage : la loyauté du sujet perd 15 points")
	Vassals.spy_apply(st, spy, ms[2], Espionage.op_def("acheter_allegeance"))
	_ok(int(Vassals.link(st, ms[2])["fealty"]) == spy, "Espionnage : allégeance secrète achetée")
	var lid := _league(st, ms[4] if ms.size() > 4 else 0, ms[5] if ms.size() > 5 else ms[0])
	if lid >= 0:
		var coh := Koinon.cohesion(st, lid)
		var target := Koinon.members_of(st, lid)[0]
		_ok(Vassals.spy_check(st, spy, target, "discorde_synode") == "", "Espionnage : semer la discorde dans un Koinon étranger")
		Vassals.spy_apply(st, spy, target, Espionage.op_def("discorde_synode"))
		_ok(Koinon.cohesion(st, lid) == coh - 15, "Espionnage : la cohésion perd 15 points")
	_ok(Espionage.op_def("discorde_synode").get("fed", false) == true, "Espionnage : opérations en données")


func _test_heroes() -> void:
	var st := _new()
	var ms := _majors(st)
	var lord := ms[1]
	var sub := ms[2]
	Vassals.bind(st, lord, sub, "vassal", Vassals.preset_clauses("vassal"), 0)
	var hid := Heroes.recruit(st, lord, Heroes.make_candidate(st, lord, "orateur", ["fed3"]))
	_ok(Heroes.check_assign(st, lord, hid, "resident", ms[3]) != "", "Résident : seulement auprès d'un sujet")
	_ok(Heroes.check_assign(st, lord, hid, "resident", sub) == "", "Résident : poste possible")
	var tr := Vassals.loyalty_trend(st, sub)
	Heroes.assign(st, lord, hid, "resident", sub)
	st.tick = int(st.heroes[hid]["arrive"])
	_ok(Vassals.loyalty_trend(st, sub) > tr, "Résident : la loyauté du sujet monte plus vite")
	var lid := _league(st, ms[3], ms[4] if ms.size() > 4 else 0)
	var m := Koinon.members_of(st, lid)[0]
	var h2 := Heroes.recruit(st, m, Heroes.make_candidate(st, m, "orateur", ["fed3b"]))
	_ok(Heroes.check_assign(st, lord, hid, "koinon", 0) != "", "Délégué : il faut être membre d'un Koinon")
	var t0 := Koinon.cohesion_trend(st, lid)
	Heroes.assign(st, m, h2, "koinon", 0)
	st.tick = maxi(st.tick, int(st.heroes[h2]["arrive"]))
	_ok(Koinon.cohesion_trend(st, lid) > t0, "Délégué au Koinon : la cohésion monte")


func _test_save() -> void:
	var st := _new()
	var ms := _majors(st)
	var cl := Vassals.preset_clauses("vassal")
	cl["spec"] = "erudit"
	Vassals.bind(st, ms[1], ms[2], "vassal", cl, 300)
	Vassals.build_pos(st, ms[1], ms[2], "mission")
	var lid := _league(st, ms[3], ms[4] if ms.size() > 4 else 0)
	Koinon.league(st, lid)["ffund"] = 42
	var d: Dictionary = JSON.parse_string(JSON.stringify(st.to_snapshot()))
	_ok(int(d["version"]) == 52, "Sauvegarde : version 52")
	var back := GameState.from_dict(d)
	_ok(Vassals.spec_of(back, ms[2]) == "erudit" and Vassals.has_pos(back, ms[2], "mission"), "Sauvegarde : spécialité et possessions gardées")
	_ok(int(Koinon.league(back, lid)["ffund"]) == 42, "Sauvegarde : arsenal fédéral gardé")
	_ok(back.checksum() == st.checksum(), "Sauvegarde : même empreinte après relecture")
