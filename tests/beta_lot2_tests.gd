class_name BetaLot2Tests
extends RefCounted
## Lot 2 du bêta-test (ne plus perdre sans comprendre) : flotte abattue par les bastions d'un siège (2.1),
## fenêtre du sujet malgré lui (2.3), chemins vers les conditions de paix (2.4). Les pauses automatiques en
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
