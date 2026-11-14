extends RefCounted
## Tests du pilier buts de guerre et traités de paix, lot 1 : motifs, revendications, buts annoncés,
## but du défenseur, score en %, reddition sur but, trêve proportionnelle et rompue, noms de guerre,
## guerre d'indépendance, sauvegarde 53. Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Buts de guerre, lot 1…")
	_test_catalogue()
	_test_claims()
	_test_declare()
	_test_defense_goal()
	_test_score()
	_test_surrender()
	_test_human_surrender()
	_test_goals_effects()
	_test_truce()
	_test_independence()
	_test_ai()
	_test_save()
	Wars.data()["claims"]["max_jumps"] = 4


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


func _new(seed_value := 7, opts := {}) -> GameState:
	# Galaxie de test : les empires naissent loin les uns des autres ; on lève la portée des revendications.
	Wars.data()["claims"]["max_jumps"] = 99
	var o := {"ai_level": "", "wargoals": "actifs", "vassals": "actifs"}
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
		# Un avant-poste près de la capitale : un système à revendiquer qui n'est pas la capitale.
		var cap := FactionTraits.capital_system(st, e.id)
		var dist := FactionTraits.jumps_from(st.galaxy, cap)
		var best := -1
		for sys in st.galaxy.systems:
			if sys.planet_ids.size() > 0 and st.system_owner(sys.id) == -1 and dist.has(sys.id) \
					and (best < 0 or int(dist[sys.id]) < int(dist[best])):
				best = sys.id
		if best >= 0:
			var c := Colony.new()
			c.planet_id = st.galaxy.get_system(best).planet_ids[0]
			c.owner = e.id
			c.kind = Colony.KIND_OUTPOST
			st.add_colony(c)
	return st


## Systèmes de b que a peut revendiquer, sans sa capitale (cédée seulement par la soumission).
func _cand(st: GameState, a: int, b: int) -> Array:
	var cap := FactionTraits.capital_system(st, b)
	return Wars.claim_candidates(st, a, b).filter(func(x: Array) -> bool: return int(x[0]) != cap)


func _majors(st: GameState) -> Array[int]:
	var out: Array[int] = []
	for e in st.empires:
		if not e.is_npc() and not Diplomacy.no_treaties(st, e.id):
			out.append(e.id)
	return out


## Un couple [a, b] où a peut revendiquer des systèmes de b (a différent de skip).
func _pair(st: GameState, human_ok := true) -> Array:
	var ms := _majors(st)
	for a in ms:
		if not human_ok and a == 0:
			continue
		for b in ms:
			if a != b and (human_ok or b != 0) and not _cand(st, a, b).is_empty():
				return [a, b]
	return []


## Fait commencer la guerre il y a days jours.
func _age(st: GameState, a: int, b: int, days := 200) -> void:
	Wars.war(st, a, b)["t"] = st.tick - days


func _test_catalogue() -> void:
	_ok(Wars.casus_defs().size() >= 11 and Wars.goal_defs().size() >= 9, "Catalogues : %d motifs, %d buts" % [Wars.casus_defs().size(), Wars.goal_defs().size()])
	for c in Wars.casus_defs():
		for g in c["goals"]:
			_ok(not Wars.goal_def(String(g)).is_empty(), "Motif %s : but %s connu" % [c["id"], g])
	var off := _new(7, {"wargoals": "aucuns"})
	var p := _pair(off)
	_ok(not off.wars_on and Wars.check_claim(off, int(p[0]), int(_cand(off, int(p[0]), int(p[1]))[0][0])) != "", "Option désactivée : pas de revendication")
	_ok(not off.to_dict().has("wars"), "Option désactivée : même empreinte (pas de bloc wars)")


func _test_claims() -> void:
	var st := _new()
	var p := _pair(st)
	var a := int(p[0])
	var b := int(p[1])
	_ok(not Wars.casus_list(st, a, b).has("revendication"), "Sans revendication, pas de motif Revendication")
	var cand: Array = _cand(st, a, b)
	var sid := int(cand[0][0])
	var cost := int(cand[0][1])
	var j := Wars.jumps_to(st, a, sid)
	var expect := 50 + 25 * maxi(0, j - 1) + (25 if Vassals.system_pop(st, sid, b) > 0 else 0)
	_ok(cost == expect, "Coût d'une revendication : 50 + 25/saut + 25 si peuplé (%d, attendu %d)" % [cost, expect])
	var inf := int(st.get_empire(a).resources["influence"])
	_ok(SimCommands.validate(st, SimCommands.war_act(a, "claim", sid)) == "", "Revendiquer : possible")
	SimCommands.apply(st, SimCommands.war_act(a, "claim", sid))
	_ok(int(st.get_empire(a).resources["influence"]) == inf - cost and Wars.has_claim(st, a, sid), "Revendiquer : influence payée, revendication posée")
	_ok(SimCommands.validate(st, SimCommands.war_act(a, "claim", sid)) != "", "Revendiquer deux fois : refusé")
	_ok(Wars.casus_list(st, a, b).has("revendication"), "Revendication : le motif s'ouvre")
	var goals := []
	for c in Wars.choices(st, a, b):
		if String(c[0]) == "revendication":
			goals.append(String(c[1]))
	_ok(goals.has("conquete") and goals.has("humiliation"), "Revendication : Conquête et Humiliation possibles (%s)" % [goals])
	# Rivalité : -20 %.
	Diplomacy.remember(st, a, b, "declared_war")
	Diplomacy.remember(st, a, b, "broke_treaty")
	Diplomacy.remember(st, a, b, "conquest")
	if Diplomacy.opinion(st, a, b) <= -50 and cand.size() > 1:
		var c2 := int(cand[1][1])
		var raw := 50 + 25 * maxi(0, Wars.jumps_to(st, a, int(cand[1][0])) - 1) + (25 if Vassals.system_pop(st, int(cand[1][0]), b) > 0 else 0)
		_ok(Wars.claim_cost(st, a, int(cand[1][0])) == raw - raw * 20 / 100, "Rival (opinion %d) : revendication -20 %% (%d)" % [Diplomacy.opinion(st, a, b), c2])
	# Allié : pas de revendication.
	var st2 := _new()
	Diplomacy.sign_treaty(st2, a, b, Diplomacy.PEACE)
	Diplomacy.sign_treaty(st2, a, b, Diplomacy.ALLIANCE)
	_ok(Wars.check_claim(st2, a, sid) != "", "On ne revendique pas chez un allié")


func _test_declare() -> void:
	var st := _new()
	var p := _pair(st, false)
	var a := int(p[0])
	var b := int(p[1])
	var sid := int(_cand(st, a, b)[0][0])
	Wars.claim(st, a, sid)
	_ok(SimCommands.validate(st, SimCommands.declare_war(a, b, "independance", "independance")) != "", "Motif non détenu : refusé")
	_ok(SimCommands.validate(st, SimCommands.declare_war(a, b, "revendication", "soumission")) != "", "But non ouvert par le motif : refusé")
	SimCommands.apply(st, SimCommands.declare_war(a, b, "revendication", "conquete"))
	var rec := Wars.war(st, a, b)
	_ok(not rec.is_empty() and String(rec["cb"]) == "revendication" and String(rec["ga"]) == "conquete", "Déclaration : motif et but annoncés")
	_ok(String(rec["name"]) != "" and not String(rec["name"]).contains("{"), "Nom de guerre : %s" % rec["name"])
	_ok((rec["tgt"][0] as Array).has(sid), "Les revendications deviennent les cibles du but")
	_ok(String(rec["gd"]) != "", "Défenseur IA : but choisi tout de suite (%s)" % rec["gd"])
	_ok(not Wars.stability_parts(st, a).any(func(x: Array) -> bool: return String(x[0]) == "Guerre d'agression"), "Guerre motivée : pas de malus d'agression")
	# Agression sans motif : stabilité, lassitude, souvenir chez les tiers.
	var st2 := _new()
	var ms := _majors(st2)
	var x := -1
	var y := -1
	for i in ms:
		for k in ms:
			if i != k and i != 0 and k != 0 and Wars.choices(st2, i, k).all(func(c: Array) -> bool: return String(c[0]) == "agression"):
				x = i
				y = k
				break
		if x >= 0:
			break
	_ok(x >= 0, "Il existe un couple sans motif")
	if x < 0:
		return
	SimCommands.apply(st2, SimCommands.declare_war(x, y))
	var r2 := Wars.war(st2, x, y)
	_ok(String(r2["cb"]) == "agression" and bool(r2["agg"]) and int(r2["ex"][0]) == 10, "Sans motif : agression, lassitude de départ 10 %")
	_ok(Wars.stability_parts(st2, x).any(func(q: Array) -> bool: return int(q[1]) == -2), "Agression : stabilité -2")
	var third := -1
	for e in ms:
		if e != x and e != y:
			third = e
			break
	var found := false
	for m in st2.memories:
		if int(m["who"]) == third and int(m["about"]) == x and String(m["kind"]) == "aggressor":
			found = true
	_ok(found, "Agression : les tiers s'en souviennent")
	_ok(Diplomacy.war_score(st2, x, y) == 0 and Wars.score(st2, x, y) == 0, "Score en % au départ : 0")


func _test_defense_goal() -> void:
	var st := _new()
	var ms := _majors(st)
	var a := ms[1]
	SimCommands.apply(st, SimCommands.declare_war(a, 0))
	var rec := Wars.war(st, a, 0)
	var defs := Wars.defense_goals(st, rec)
	_ok(String(rec["gd"]) == "" and defs.has("humiliation"), "Défenseur humain : il choisit son but (%s)" % [defs])
	_ok(SimCommands.validate(st, SimCommands.war_act(a, "goal", 0, "humiliation")) != "", "Seul le défenseur choisit")
	_ok(SimCommands.validate(st, SimCommands.war_act(0, "goal", a, "soumission")) != "", "But hors liste : refusé")
	_ok(Wars.check_demand(st, 0, a) != "", "But pas encore fixé : pas de reddition exigée")
	SimCommands.apply(st, SimCommands.war_act(0, "goal", a, "rancon"))
	_ok(String(Wars.war(st, a, 0)["gd"]) == "rancon", "Défenseur : but fixé (Rançon)")
	# Échéance : le but se fixe tout seul.
	var st2 := _new()
	SimCommands.apply(st2, SimCommands.declare_war(a, 0))
	st2.tick += 100
	Wars.monthly(st2)
	_ok(String(Wars.war(st2, a, 0)["gd"]) != "", "Après 90 jours sans choix, le but se fixe seul")


func _test_score() -> void:
	var st := _new()
	var p := _pair(st, false)
	var a := int(p[0])
	var b := int(p[1])
	var cand: Array = _cand(st, a, b)
	var sid := int(cand[0][0])
	Wars.claim(st, a, sid)
	SimCommands.apply(st, SimCommands.declare_war(a, b, "revendication", "conquete"))
	Wars.on_battle(st, a, b, 60)
	_ok(Wars.score(st, a, b) == 20 and Wars.score(st, b, a) == -20, "Batailles : 40 x 60 / (60 + 60) = 20 %% (%d)" % Wars.score(st, a, b))
	Wars.on_battle(st, a, b, 100000)
	_ok(Wars.score(st, a, b) <= 40 and Wars.score(st, a, b) >= 39, "Batailles : plafond 40 %% (%d)" % Wars.score(st, a, b))
	Combat.capture_system(st, sid, a)
	var parts: Array = Wars.score_parts(st, a, b)["parts"]
	_ok(parts.any(func(x: Array) -> bool: return String(x[0]) == "Systèmes pris" and int(x[1]) > 0), "Système pris : le score monte (%s)" % [parts])
	_ok(not Wars.has_claim(st, a, sid), "Système pris : la revendication est remplie")
	_ok(Wars.lost_claims(st, b).has(sid) and Wars.casus_list(st, b, a).has("reconquete"), "Système perdu : revendication de reconquête")
	var rec := Wars.war(st, a, b)
	_ok(Wars.objective_held(st, rec, a), "Conquête : l'objectif (revendications) est tenu")
	for i in 30:
		Wars.monthly(st)
	_ok(int(rec["hold"][0]) == 30 and Wars.score_parts(st, a, b)["parts"].any(func(x: Array) -> bool: return String(x[0]).begins_with("But tenu") and int(x[1]) == 25), "But tenu : +1 %/mois, plafond 25 %")
	_ok(Wars.score(st, a, b) <= 100, "Score borné à 100 %%")
	_ok(Diplomacy.war_score(st, a, b) == Wars.score(st, a, b), "Le score de guerre de la diplomatie est en %")
	_ok(Vassals.check_surrender(st, b, a) != "", "Reddition de la Cour des sujets : remplacée par le but")


func _test_surrender() -> void:
	var st := _new()
	var p := _pair(st, false)
	var a := int(p[0])
	var b := int(p[1])
	var sid := int(_cand(st, a, b)[0][0])
	Wars.claim(st, a, sid)
	SimCommands.apply(st, SimCommands.declare_war(a, b, "revendication", "conquete"))
	_ok(Wars.check_demand(st, a, b).contains("trop tôt"), "Reddition : pas avant 60 jours")
	_age(st, a, b)
	# Score faible contre une IA qui n'est pas écrasée : refus, puis délai.
	if Wars.acceptance(st, a, b) < 0:
		SimCommands.apply(st, SimCommands.war_act(a, "demand", b))
		_ok(Combat.at_war(st, a, b) and Wars.check_demand(st, a, b).contains("trop tôt pour reproposer"), "Refus de l'IA : la guerre continue, délai avant de redemander")
	var st2 := _new()
	Wars.claim(st2, a, sid)
	SimCommands.apply(st2, SimCommands.declare_war(a, b, "revendication", "conquete"))
	_age(st2, a, b)
	Wars.on_battle(st2, a, b, 100000)
	_ok(Wars.acceptance(st2, a, b) >= 0, "Victoire nette : l'IA accepterait (%d)" % Wars.acceptance(st2, a, b))
	var t0 := st2.tick
	var sc := Wars.score(st2, a, b)
	SimCommands.apply(st2, SimCommands.war_act(a, "demand", b))
	_ok(not Combat.at_war(st2, a, b) and st2.system_owner(sid) == a, "Reddition acceptée : paix, revendication cédée")
	var expect := mini(1080, 360 + maxi(sc, 50) * 7)
	_ok(Diplomacy.truce_left(st2, a, b) == expect, "Trêve proportionnelle : 360 + 7 j par point (%d, attendu %d)" % [Diplomacy.truce_left(st2, a, b), expect])
	_ok(t0 == st2.tick and Wars.war(st2, a, b).is_empty(), "La guerre est close")
	# Le vaincu se rend de lui-même.
	var st3 := _new()
	Wars.claim(st3, a, sid)
	SimCommands.apply(st3, SimCommands.declare_war(a, b, "revendication", "conquete"))
	_age(st3, a, b)
	_ok(SimCommands.validate(st3, SimCommands.war_act(b, "yield", a)) == "", "Se rendre : toujours possible au perdant")
	SimCommands.apply(st3, SimCommands.war_act(b, "yield", a))
	_ok(not Combat.at_war(st3, a, b) and st3.system_owner(sid) == a and Diplomacy.truce_left(st3, a, b) == 360 + 50 * 7, "Se rendre : le but adverse s'applique, trêve d'au moins 50 %")


func _test_human_surrender() -> void:
	var st := _new()
	var ms := _majors(st)
	var a := ms[1]
	SimCommands.apply(st, SimCommands.declare_war(a, 0))
	_age(st, a, 0)
	SimCommands.apply(st, SimCommands.war_act(0, "goal", a, "humiliation"))
	Wars.propose(st, "wdemand", a, 0)
	var props := Diplomacy.proposals_for(st, 0)
	_ok(props.size() == 1 and String(props[0]["treaty"]) == "wdemand", "L'humain reçoit l'exigence de reddition")
	_ok(Diplomacy.proposal_label(props[0]) == "Exige votre reddition" and Wars.kind_text(st, props[0]) != "", "Proposition lisible")
	SimCommands.apply(st, SimCommands.answer_proposal(0, int(props[0]["id"]), false))
	_ok(Combat.at_war(st, a, 0), "Refus : la guerre continue")
	var inf := int(st.get_empire(0).resources["influence"])
	Wars.propose(st, "wdemand", a, 0)
	Diplomacy._set_cooldown(st, a, 0, "wdemand", 0)
	props = Diplomacy.proposals_for(st, 0)
	if props.size() == 1:
		SimCommands.apply(st, SimCommands.answer_proposal(0, int(props[0]["id"]), true))
	_ok(not Combat.at_war(st, a, 0), "Acceptation : la paix est signée")
	_ok(int(st.get_empire(0).resources["influence"]) <= inf, "Humiliation ou autre but appliqué au vaincu")


func _test_goals_effects() -> void:
	var st := _new()
	var ms := _majors(st)
	var a := ms[1]
	var b := ms[2]
	SimCommands.apply(st, SimCommands.declare_war(a, b, "agression", "rancon"))
	_age(st, a, b)
	var mat := int(st.get_empire(b).resources["materials"])
	var wm := int(st.get_empire(a).resources["materials"])
	Wars.apply_victory(st, a, b)
	_ok(int(st.get_empire(b).resources["materials"]) == mat - mat * 33 / 100 and int(st.get_empire(a).resources["materials"]) == wm + mat * 33 / 100, "Rançon : un tiers des réserves")
	_ok((st.vassals["trib"] as Array).any(func(t: Dictionary) -> bool: return int(t["from"]) == b and int(t["to"]) == a and int(t["pct"]) == 15), "Rançon : tribut de 15 % pendant 5 ans")
	var st2 := _new()
	SimCommands.apply(st2, SimCommands.declare_war(a, b, "agression", "humiliation"))
	_age(st2, a, b)
	var ia := int(st2.get_empire(a).resources["influence"])
	Wars.apply_victory(st2, a, b)
	_ok(int(st2.get_empire(a).resources["influence"]) == ia + 100 and int(st2.get_empire(b).resources["influence"]) == 1500, "Humiliation : +100 influence, le vaincu perd la moitié de la sienne")
	_ok(Wars.stability_parts(st2, b).any(func(x: Array) -> bool: return int(x[1]) == -5), "Humiliation : stabilité -5 chez le vaincu")
	# Soumission : le vaincu devient vassal.
	var st3 := _new()
	SimCommands.apply(st3, SimCommands.declare_war(a, b))
	Wars.war(st3, a, b)["ga"] = "soumission"
	_age(st3, a, b)
	Wars.apply_victory(st3, a, b)
	_ok(Vassals.lord_of(st3, b) == a, "Soumission : le vaincu devient vassal")
	# Guerre totale : pas de reddition.
	var st4 := _new()
	SimCommands.apply(st4, SimCommands.declare_war(a, b))
	Wars.war(st4, a, b)["ga"] = "totale"
	_age(st4, a, b)
	_ok(Wars.check_demand(st4, a, b).contains("totale"), "Guerre totale : pas de reddition")


func _test_truce() -> void:
	var st := _new()
	var ms := _majors(st)
	var a := ms[1]
	var b := ms[2]
	Diplomacy.sign_treaty(st, a, b, Diplomacy.PEACE)
	_ok(SimCommands.validate(st, SimCommands.declare_war(a, b)) != "", "Trêve : déclaration simple refusée")
	_ok(SimCommands.validate(st, SimCommands.declare_war(a, b, "", "", true)) == "", "Trêve : on peut la rompre en le disant")
	var off := _new(7, {"wargoals": "aucuns"})
	Diplomacy.sign_treaty(off, a, b, Diplomacy.PEACE)
	_ok(SimCommands.validate(off, SimCommands.declare_war(a, b, "", "", true)) != "", "Sans buts de guerre : trêve infranchissable")
	SimCommands.apply(st, SimCommands.declare_war(a, b, "", "", true))
	var rec := Wars.war(st, a, b)
	_ok(bool(rec["brk"]) and int(rec["ex"][0]) >= 20, "Trêve rompue : lassitude de départ +20 %")
	_ok(Wars.stability_parts(st, a).any(func(x: Array) -> bool: return String(x[0]) == "Trêve rompue" and int(x[1]) == -5), "Trêve rompue : stabilité -5")
	_ok(Wars.casus_list(st, b, a).has("represailles"), "Trêve rompue : la victime gagne le motif Représailles")
	_ok(not Diplomacy.in_truce(st, a, b), "La trêve n'existe plus")


func _test_independence() -> void:
	var st := _new()
	var ms := _majors(st)
	var lord := ms[1]
	var sub := ms[2]
	Vassals.bind(st, lord, sub, "vassal", Vassals.preset_clauses("vassal"), 0)
	Vassals.freedom_war(st, sub)
	var rec := Wars.war(st, sub, lord)
	_ok(not rec.is_empty() and String(rec["cb"]) == "independance" and String(rec["ga"]) == "independance", "Guerre d'indépendance : motif et but")
	_ok(String(rec["gd"]) == "affirmer", "Le suzerain se bat pour affirmer sa suzeraineté")
	_age(st, sub, lord)
	Wars.apply_victory(st, lord, sub)
	_ok(Vassals.lord_of(st, sub) == lord and Vassals.check_freedom(st, sub).contains("trop tôt"), "Suzeraineté affirmée : le sujet rentre dans le rang, pas de liberté avant 5 ans")


func _test_ai() -> void:
	var st := _new()
	var p := _pair(st, false)
	var a := int(p[0])
	var b := int(p[1])
	# Revendication : un voisin mal aimé, dans la fenêtre du niveau.
	Diplomacy.remember(st, a, b, "declared_war")
	var bought := false
	for i in 200:
		AiWars.think_state(st, a)
		if not Wars.bought_claims(st, a).is_empty():
			bought = true
			break
		st.tick += 1
	_ok(bought, "IA : achète une revendication sur un voisin détesté")
	# Vainqueur IA : exige la reddition quand l'autre l'accepterait.
	var st2 := _new()
	var sid := int(_cand(st2, a, b)[0][0])
	Wars.claim(st2, a, sid)
	SimCommands.apply(st2, SimCommands.declare_war(a, b, "revendication", "conquete"))
	_age(st2, a, b)
	Wars.on_battle(st2, a, b, 100000)
	AiWars.think_state(st2, a)
	_ok(not Combat.at_war(st2, a, b) and st2.system_owner(sid) == a, "IA vainqueur : exige et obtient la reddition")
	# Vaincu IA : se rend quand la défaite est nette.
	var st3 := _new()
	Wars.claim(st3, a, sid)
	SimCommands.apply(st3, SimCommands.declare_war(a, b, "revendication", "conquete"))
	_age(st3, a, b, 30)
	Wars.on_battle(st3, a, b, 100000)
	Combat.capture_system(st3, sid, a)
	st3.tick += 40
	AiWars.think_state(st3, b)
	_ok(not Combat.at_war(st3, a, b), "IA vaincue : se rend (marge %d)" % Wars.acceptance(st3, a, b))
	# Humain vainqueur : l'IA vaincue lui propose de se rendre.
	var st4 := _new()
	var ms := _majors(st4)
	var x := ms[1]
	var cx := int(_cand(st4, 0, x)[0][0])
	Wars.claim(st4, 0, cx)
	SimCommands.apply(st4, SimCommands.declare_war(0, x, "revendication", "conquete"))
	_age(st4, 0, x)
	Wars.on_battle(st4, 0, x, 100000)
	Combat.capture_system(st4, cx, 0)
	AiWars.think_state(st4, x)
	var props := Diplomacy.proposals_for(st4, 0)
	_ok(props.size() == 1 and String(props[0]["treaty"]) == "wyield", "IA vaincue face à un humain : elle propose de se rendre")


func _test_save() -> void:
	var st := _new()
	var p := _pair(st, false)
	var a := int(p[0])
	var b := int(p[1])
	Wars.claim(st, a, int(_cand(st, a, b)[0][0]))
	SimCommands.apply(st, SimCommands.declare_war(a, b, "revendication", "conquete"))
	Wars.on_battle(st, a, b, 50)
	var d: Dictionary = JSON.parse_string(JSON.stringify(st.to_snapshot()))
	_ok(int(d["version"]) == 53, "Sauvegarde : version 53")
	var back := GameState.from_dict(d)
	_ok(back.wars_on and String(Wars.war(back, a, b).get("name", "")) == String(Wars.war(st, a, b)["name"]), "Sauvegarde : guerre et nom gardés")
	_ok(Wars.score(back, a, b) == Wars.score(st, a, b) and Wars.bought_claims(back, a) == Wars.bought_claims(st, a), "Sauvegarde : score et revendications gardés")
	_ok(back.checksum() == st.checksum(), "Sauvegarde : même empreinte après relecture")
