class_name BetaLot2Tests
extends RefCounted
## Lot 2 du bêta-test (ne plus perdre sans comprendre) : flotte abattue par les bastions d'un siège (2.1),
## fenêtre du sujet malgré lui (2.3), chemins vers les conditions de paix (2.4), reddition sur occupation
## totale (2.2 : dernier rempart, reddition sans conditions, délai de grâce). Les pauses automatiques en
## temps réel (3.3) se vérifient dans smoke_test, avec la scène principale.
##   tools/run_tests.sh beta_lot2_tests

var _check: Callable
const MAIN := preload("res://scripts/main.gd")


func run(check: Callable) -> void:
	_check = check
	print("Bêta-test, lot 2…")
	_test_bastion_losses()
	_test_subject_window()
	_test_war_paths()
	_test_surrender_human_winner()
	_test_surrender_human_loser()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


## Un monde de l'IA 1 avec un bastion, et une flotte du joueur devant lui.
static func _siege_setup(st: GameState) -> Array:
	var c: Colony = null
	for pid in st.sorted_colony_ids():
		var x: Colony = st.colonies[pid]
		if x.owner == 1 and x.is_colony() and x.is_established():
			c = x
			break
	if not c.buildings.has("bastion"):
		c.buildings.append("bastion")
	var sid := st.galaxy.get_planet(c.planet_id).system_id
	var f := st.spawn_ship(0, "fregate", sid)
	st.sieges[sid] = {"system": sid, "by": 0, "start": st.tick}
	return [sid, f]


## 2.1 : le premier vaisseau abattu du siège et la flotte détruite font une ligne de chronique, que la
## touche B retrouve (main.last_loss) faute de rapport de bataille.
func _test_bastion_losses() -> void:
	var st := GameState.create(41, 40, 900.0, "vael")
	var setup := _siege_setup(st)
	var sid := int(setup[0])
	var f: Fleet = setup[1]
	_ok(not Combat.battery(st, sid).is_empty(), "le bastion arme les batteries du système")
	f.add_ship("fregate", -1, -1)
	f.hp[0] = 1
	f.hp[1] = 100000
	var added: Array[Dictionary] = []
	for _i in 30:
		if f.ships.size() == 2:
			CombatSystem._battery_fire(st, sid, [f] as Array[Fleet], added)
	_ok(f.ships.size() == 1 and st.fleets.has(f.id), "un vaisseau abattu, la flotte tient")
	var downed := added.filter(func(e: Dictionary) -> bool: return String(e.get("kind", "")) == "ship_downed")
	_ok(downed.size() == 1 and String(downed[0]["text"]).contains(f.fleet_name), "premier vaisseau abattu : une ligne pour l'assiégeant (%s)" % str(downed))
	added.clear()
	f.add_ship("fregate", -1, -1)
	f.hp[0] = 100000
	f.hp[1] = 1
	for _i in 30:
		if f.ships.size() == 2:
			CombatSystem._battery_fire(st, sid, [f] as Array[Fleet], added)
	_ok(f.ships.size() == 1 and added.is_empty(), "le vaisseau suivant tombe sans nouvelle ligne : une seule par siège")
	_ok(MAIN.last_loss(st, 0).is_empty(), "pas encore de flotte perdue")
	f.hp[0] = 1
	for _i in 30:
		if st.fleets.has(f.id):
			CombatSystem._battery_fire(st, sid, [f] as Array[Fleet], added)
	_ok(not st.fleets.has(f.id), "la flotte finit détruite par les bastions")
	var lost := added.filter(func(e: Dictionary) -> bool: return String(e.get("kind", "")) == "fleet_lost")
	_ok(lost.size() == 1 and String(lost[0]["text"]).contains("Il n'y a pas eu de bataille"), "flotte détruite : la chronique dit pourquoi (%s)" % str(lost))
	var rec := MAIN.last_loss(st, 0)
	_ok(not rec.is_empty() and Announce.involved(rec).has(0) and Announce.gravity(st, rec, 0) >= Announce.AVIS, "la perte est une annonce au moins Avis pour le joueur")
	_ok(Announce.can_see(rec, 1), "l'assiégé l'apprend aussi")
	_ok(Hud.last_report(st, 0).is_empty(), "aucun rapport de bataille : B rouvrira cette annonce")


## 2.3 : devenir sujet sans l'avoir demandé ouvre une fenêtre avec trois voies ; pas pour un protectorat.
func _test_subject_window() -> void:
	var st := GameState.create(43, 40, 900.0, "vael")
	st.vassals_on = true
	for o in [1, 2]:
		for pair in [[0, o], [o, 0]]:
			if not st.get_empire(pair[0]).contacts.has(pair[1]):
				st.get_empire(pair[0]).contacts.append(pair[1])
	var before := st.announces.size()
	Vassals.bind(st, 1, 0, "vassal", Vassals.preset_clauses("vassal"), 0, true)
	var recs := st.announces.slice(before).filter(func(r: Dictionary) -> bool: return String(r["k"]) == "became_subject")
	_ok(recs.size() == 1, "reddition silencieuse : la fenêtre du sujet arrive quand même")
	var rec: Dictionary = recs[0] if not recs.is_empty() else {}
	_ok(not rec.is_empty() and Announce.can_see(rec, 0) and not Announce.can_see(rec, 1), "elle ne parle qu'au sujet")
	_ok(not rec.is_empty() and Announce.gravity(st, rec, 0) >= Announce.WINDOW, "elle s'ouvre en fenêtre")
	_ok(String(rec.get("x", "")).contains("Clauses"), "elle rappelle les clauses (%s)" % String(rec.get("x", "")))
	var panel := AnnouncePanel.new()
	Engine.get_main_loop().root.add_child(panel)
	if not rec.is_empty():
		panel.open(st, 0, [rec] as Array[Dictionary], Announce.WINDOW, 1, 1)
	_ok(panel.view == "subject" and panel.special_buttons.has("wait") and panel.special_buttons.has("revolt") and panel.special_buttons.has("protector"),
			"trois voies : payer, préparer la révolte, chercher un protecteur")
	var asked := []
	panel.relation_requested.connect(func(id: int, pane: String) -> void: asked.append([id, pane]))
	if panel.special_buttons.has("revolt"):
		(panel.special_buttons["revolt"] as Button).pressed.emit()
	_ok(asked == [[1, "deal"]], "préparer la révolte mène au volet Traiter du suzerain (%s)" % str(asked))
	var prot: Button = panel.special_buttons.get("protector")
	_ok(prot != null and not prot.disabled, "un rival connu est proposé comme protecteur")
	panel.free()
	# Protectorat demandé : pas de fenêtre. Un sujet de l'IA non plus.
	Vassals.unbind(st, 0)
	before = st.announces.size()
	Vassals.bind(st, 1, 0, "protectorat", Vassals.preset_clauses("protectorat"), 0, true)
	Vassals.bind(st, 0, 2, "vassal", Vassals.preset_clauses("vassal"), 0, true)
	_ok(not st.announces.slice(before).any(func(r: Dictionary) -> bool: return String(r["k"]) == "became_subject"), "ni pour un protectorat ni pour une IA")


## 2.4 : en guerre, la barre d'alertes mène aux conditions de paix ; la Fanfare de guerre aussi, avec les
## flottes sans ordres (3.3).
func _test_war_paths() -> void:
	var st := GameState.create(47, 40, 900.0, "vael")
	for pair in [[0, 1], [1, 0]]:
		if not st.get_empire(pair[0]).contacts.has(pair[1]):
			st.get_empire(pair[0]).contacts.append(pair[1])
	Diplomacy._rel_w(st, 0, 1)["truce"] = 0
	Diplomacy._rel_w(st, 0, 1)["pact"] = Diplomacy.COLD
	Combat.start_war(st, 1, 0)
	var war := AlertBar.alerts(st, 0).filter(func(a: Dictionary) -> bool: return String(a["kind"]) == "war")
	_ok(war.size() == 1 and int(war[0]["arg"]) == 1 and String(war[0]["text"]).contains("score"), "alerte de guerre : l'ennemi et le score (%s)" % str(war))
	var idle := Fleets.idle_fleets(st, 0).filter(func(f: Fleet) -> bool: return Combat.is_armed(f))
	if idle.is_empty():
		st.spawn_ship(0, "fregate", st.galaxy.get_planet(st.get_empire(0).capital_planet).system_id)
	var txt := MAIN.idle_fleets_text(st, 0)
	_ok(txt.begins_with(" Flottes sans ordres : ") and txt.contains("("), "avis de guerre : flottes sans ordres et position (%s)" % txt)
	var recs := st.announces.filter(func(r: Dictionary) -> bool: return String(r["k"]) == "war_declared")
	if recs.is_empty():
		Announce.next(st, "war_declared", {"actor": 1, "target": 0})
		st.add_chronicle("Guerre de test.")
		recs = [st.announces.back()]
	var panel := AnnouncePanel.new()
	Engine.get_main_loop().root.add_child(panel)
	panel.open(st, 0, [recs.back()] as Array[Dictionary], Announce.FANFARE, 1, 1)
	_ok(panel.view == "war" and panel.special_buttons.has("peace") and panel.special_buttons.has("idle"), "Fanfare de guerre : conditions de paix et flottes sans ordres")
	var asked := []
	panel.relation_requested.connect(func(id: int, pane: String) -> void: asked.append([id, pane]))
	(panel.special_buttons["peace"] as Button).pressed.emit()
	_ok(asked == [[1, "deal"]], "conditions de paix : volet Traiter de l'ennemi")
	panel.free()


static func _kinds_since(st: GameState, before: int, k: String) -> Array:
	return st.announces.slice(before).filter(func(r: Dictionary) -> bool: return String(r["k"]) == k)


## 2.2 : vainqueur humain. Dernier rempart à un système libre, puis reddition sans conditions : il compose
## ses termes (score au maximum) ou applique son but ; sans traité, sa lassitude monte, puis le but s'applique.
func _test_surrender_human_winner() -> void:
	var wp: RefCounted = preload("res://tests/war_peace_tests.gd").new()
	var st: GameState = wp._new(61)
	var a := 0
	var b := -1
	for x in wp._majors(st):
		if x != a and EmpireReport.owned_systems(st, x).size() >= 2:
			b = x
			break
	_ok(b > 0, "un rival IA à deux systèmes au moins")
	if b < 0:
		return
	var rec: Dictionary = wp._war(st, a, b)
	var own := EmpireReport.owned_systems(st, b)
	var before := st.announces.size()
	for i in own.size() - 1:
		WarPeace.invade(st, own[i], a)
	var ls := _kinds_since(st, before, "last_stand")
	_ok(ls.size() == 1 and Announce.can_see(ls[0], a) and Announce.can_see(ls[0], b), "dernier rempart : les deux camps sont prévenus (%d)" % ls.size())
	_ok(not ls.is_empty() and String(ls[0].get("x", "")).contains(st.galaxy.get_system(own[own.size() - 1]).system_name), "il nomme le système encore libre")
	_ok(AlertBar.free_gauge(st, b) == "1 sur %d" % own.size(), "jauge : 1 système libre (%s)" % AlertBar.free_gauge(st, b))
	before = st.announces.size()
	WarPeace.invade(st, own[own.size() - 1], a)
	_ok(_kinds_since(st, before, "last_stand").is_empty(), "plus de dernier rempart une fois tout occupé")
	Wars.monthly(st)
	_ok(Combat.at_war(st, a, b), "vainqueur humain : pas de traité imposé d'office")
	_ok(String(WarPeace.uncond_of(st, a, b).get("k", "")) == "win", "reddition sans conditions en cours")
	var win := _kinds_since(st, before, "uncond_win")
	_ok(win.size() == 1 and Announce.gravity(st, win[0], a) >= Announce.WINDOW, "une fenêtre pour le vainqueur")
	_ok(WarPeace.terms_score(st, a, b) == 100, "ses termes se paient au score maximum")
	_ok(Wars.check_demand(st, a, b) == "" and Wars.ai_accepts(st, "wdemand", a, b), "exiger la reddition passe toujours")
	var terms := {"repar": true, "trib": true}
	_ok(Vassals.ai_accepts(st, "terms", a, b, terms) == (Vassals.price(st, b, terms, a) <= 100), "l'IA vaincue accepte tout ce qui tient sous 100")
	# La fenêtre : appliquer le but ou composer.
	var panel := AnnouncePanel.new()
	Engine.get_main_loop().root.add_child(panel)
	if not win.is_empty():
		panel.open(st, a, [win[0]] as Array[Dictionary], Announce.WINDOW, 1, 1)
	_ok(panel.view == "endgame" and panel.special_buttons.has("apply") and panel.special_buttons.has("compose"), "fenêtre : appliquer le but, composer les termes")
	var sent := []
	panel.command_requested.connect(func(cmd: Dictionary) -> void: sent.append(cmd))
	if panel.special_buttons.has("apply"):
		(panel.special_buttons["apply"] as Button).pressed.emit()
	_ok(sent.size() == 1 and String(sent[0]["act"]) == "demand" and int(sent[0]["x"]) == b, "appliquer le but : l'ordre d'exiger la reddition (%s)" % str(sent))
	panel.free()
	# Sans traité : lassitude du vainqueur après 90 jours, but appliqué au bout d'un an.
	var u: Dictionary = rec["unc"]
	u["t"] = st.tick - 100
	var ex0 := int(rec["ex"][0])
	Wars.monthly(st)
	_ok(int(rec["ex"][0]) >= ex0 + 6, "après 90 jours, la lassitude du vainqueur monte (%d -> %d)" % [ex0, int(rec["ex"][0])])
	u["t"] = st.tick - 400
	var start := st.chronicle.size()
	Wars.monthly(st)
	_ok(not Combat.at_war(st, a, b), "au bout d'un an, le but s'applique")
	var said := false
	for i in range(start, st.chronicle.size()):
		if String(st.chronicle[i]["text"]).contains("tous les systèmes de %s étaient occupés" % st.get_empire(b).display_name()):
			said = true
	_ok(said, "le traité dit pourquoi : tous les systèmes étaient occupés")


## 2.2 : vaincu humain face à l'IA. Délai de grâce ; reprendre un système annule la reddition.
func _test_surrender_human_loser() -> void:
	var wp: RefCounted = preload("res://tests/war_peace_tests.gd").new()
	var st: GameState = wp._new(67)
	var b := 0
	var a: int = wp._majors(st)[1]
	if a == b:
		a = wp._majors(st)[2]
	wp._war(st, a, b)
	var own := EmpireReport.owned_systems(st, b)
	for sid in own:
		WarPeace.invade(st, sid, a)
	var before := st.announces.size()
	Wars.monthly(st)
	_ok(Combat.at_war(st, a, b) and String(WarPeace.uncond_of(st, a, b).get("k", "")) == "grace", "vaincu humain : délai de grâce avant le traité")
	var gr := _kinds_since(st, before, "uncond_grace")
	_ok(gr.size() == 1 and Announce.can_see(gr[0], b), "le vaincu est prévenu")
	_ok(WarPeace.terms_score(st, a, b) == Diplomacy.war_score(st, a, b), "le score de l'IA reste le vrai")
	var alert := AlertBar.alerts(st, b).filter(func(x: Dictionary) -> bool: return String(x["kind"]) == "war")
	_ok(not alert.is_empty() and String(alert[0]["text"]).contains("tous vos systèmes sont occupés"), "la pastille de guerre le rappelle")
	# Reprendre un système : la reddition tombe.
	WarPeace.release(st, own[0])
	before = st.announces.size()
	Wars.monthly(st)
	_ok(Combat.at_war(st, a, b) and WarPeace.uncond_of(st, a, b).is_empty() and _kinds_since(st, before, "uncond_lifted").size() == 1, "un système repris annule la reddition")
	WarPeace.invade(st, own[0], a)
	Wars.monthly(st)
	_ok(not WarPeace.uncond_of(st, a, b).is_empty(), "tout occupé de nouveau : nouveau délai")
	(Wars.war(st, a, b)["unc"] as Dictionary)["t"] = st.tick - 31
	Wars.monthly(st)
	_ok(not Combat.at_war(st, a, b), "délai écoulé : le but de l'IA s'applique")
