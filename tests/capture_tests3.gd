extends RefCounted
## Tests des prises de guerre, lot 3 (étude « Prises de guerre », propositions 36 à 50) : règles des
## peuples restantes, rapport, annonces, Butin et Chantier, lentille Terrain, clause de paix, hauts faits,
## Vaisseau-tombe et IA.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Prises de guerre (lot 3)…")
	_test_peoples()
	_test_report_and_announces()
	_test_ui_blocks()
	_test_peace_clause()
	_test_deeds()
	_test_menu_option()


func _ok(cond: bool, what: String) -> void:
	print("  ", "ok " if cond else "KO ", what)
	_check.call(cond, what)


func _state(seed_value := 4242, faction := "ossarane", mode := "complete") -> GameState:
	return GameState.create(seed_value, 150, 1800.0, faction, {"ai_level": "", "capture": mode})


func _me(st: GameState) -> int:
	return st.empires[0].id


func _foe(st: GameState) -> int:
	return st.empires[1].id


func _empty_system(st: GameState) -> int:
	for s in st.galaxy.systems:
		if st.system_owner(s.id) == -1 and s.neighbors.size() >= 2:
			return s.id
	return -1


func _test_peoples() -> void:
	# Profit : l'Épave remontée se bâtit sur un champ de 5 épaves, même sans cimetière (prop. 37).
	var st := _state(301, "brisecomete")
	var me := _me(st)
	var e := st.get_empire(me)
	var pid := e.capital_planet
	var sid := int(st.galaxy.get_planet(pid).system_id)
	_ok(not PeopleHulls.wrecks_ok(st, pid), "pas d'épaves au départ")
	for _i in 5:
		CaptureLore._add_wreck(st, sid, _foe(st), "fregate")
	_ok(PeopleHulls.wrecks_ok(st, pid), "Épave remontée : un champ de 5 épaves suffit")
	# Murmurants : étude à distance (prop. 41).
	var ms := _state(302, "murmurants")
	_ok(CaptureLore.study_pct(ms, _me(ms), false) > CaptureLore.study_pct(st, me, false), "Murmurants : rétro-ingénierie +50 %")
	_ok(Capture.data().get("no_wreck_hulls", []).has("onde_nef"), "l'Onde-nef ne laisse pas d'épave")
	var rep := {}
	var added: Array[Dictionary] = []
	CaptureLore.after_battle(ms, _empty_system(ms), {"sides": [{"empire": _me(ms), "lost": {}}, {"empire": _foe(ms), "lost": {"onde_nef": 2}}]}, _me(ms), rep, added)
	_ok(CaptureLore.field(ms, _empty_system(ms)).is_empty(), "une Onde-nef détruite ne remplit pas le champ")


func _test_report_and_announces() -> void:
	var r := {"log": [{"boards": [[0, 1, 1], [0, 2, 0]]}], "capture_lore": {"recovered": ["fregate~3"], "learned": ["Coques lourdes"], "mats": 12}}
	var t := CaptureUi.report_text(r, 0, 0)
	_ok(t.contains("2 tentative") and t.contains("1 prise"), "rapport : section des abordages")
	_ok(t.contains("Butin") and t.contains("Rétro-ingénierie") and t.contains("12 matériaux"), "rapport : section Prises et épaves")
	_ok(not CaptureUi.report_text(r, 0, 1).contains("Butin"), "le butin ne se montre qu'au vainqueur")
	for k in ["battle_loot", "mega_prize", "tomb_seen"]:
		_ok(not Announce.kind_def(k).is_empty(), "annonce « %s »" % k)
	var st := _state(311)
	var sid := _empty_system(st)
	CaptureTomb.force_spawn(st, -1)
	CaptureTomb.tomb(st).clear()
	st.tick = 360 * 5
	var found := false
	for _y in 30:
		CaptureTomb.daily(st)
		if CaptureTomb.active(st):
			found = true
			break
		st.tick += 360
	_ok(found, "le Vaisseau-tombe finit par apparaître (25 % par an dès l'an 5)")
	_ok(sid >= 0, "système libre trouvé")


func _test_ui_blocks() -> void:
	var st := _state(321)
	var me := _me(st)
	var sid := _empty_system(st)
	var f := st.spawn_ship(me, "fregate", sid)
	f.add_ship(Capture.prize_id("croiseur", 3))
	CaptureLore.loot_of(st, me)["list"].append({"s": "corvette~1", "sid": sid, "until": st.tick + 30, "o": _foe(st)})
	CaptureLore.study_ship(st, me, "croiseur", false)
	var box := VBoxContainer.new()
	var sent: Array = []
	CaptureUi.shipyard_block(st, me, box, func(cmd: Dictionary) -> void: sent.append(cmd))
	_ok(box.get_child_count() > 8, "Chantier : prises, butin, politique, redditions et rétro-ingénierie")
	_ok(CaptureUi.signature(st, me) != "", "signature du Chantier pour le rafraîchir")
	_ok(CaptureUi.prizes_of(st, me).size() == 1, "une prise en service listée")
	_ok(CaptureUi.posture_tip(st, f).contains("Abordage") or CaptureUi.posture_tip(st, f).contains("abordage"), "infobulle de la posture d'abordage")
	CaptureLore._add_wreck(st, sid, _foe(st), "fregate")
	_ok(CaptureLore.field_text(st, sid).contains("Champ d'épaves"), "lentille Terrain : le champ d'épaves au survol")
	box.free()
	var cl := _state(322, "ossarane", "classique")
	var box2 := VBoxContainer.new()
	CaptureUi.shipyard_block(cl, _me(cl), box2, func(_c: Dictionary) -> void: pass)
	_ok(box2.get_child_count() == 0, "Classique : pas de section au Chantier")
	box2.free()


func _test_peace_clause() -> void:
	var st := _state(331)
	var me := _me(st)
	var foe := _foe(st)
	_ok(WarPeace.CLAUSES.has("prizes") and not WarPeace.clause_def("prizes").is_empty(), "clause de paix « Rendre les prises »")
	var fe := st.get_empire(foe)
	var my_class := ""
	for c in FactionTraits.ship_ids_for(st.get_empire(me).faction_id):
		if not FactionTraits.ship_ids_for(fe.faction_id).has(c) and bool(GameData.ship(c).get("military", false)):
			my_class = c
			break
	_ok(my_class != "", "une classe propre au peuple du joueur")
	if my_class == "":
		return
	var f := st.spawn_ship(foe, "corvette", _empty_system(st))
	var pid := Capture.prize_id(my_class, 1)
	f.add_ship(pid)
	_ok(CaptureLore.prizes_from(st, foe, me).size() == 1, "l'ennemi tient une de nos prises")
	var n := CaptureLore.return_prizes(st, foe, me)
	var back := false
	for fid in st.fleets:
		var g: Fleet = st.fleets[fid]
		if g.owner == me and g.ships.has(pid):
			back = true
	_ok(n == 1 and back and not f.ships.has(pid), "la paix rend la prise à son propriétaire")
	_ok(CaptureLore.prizes_from(st, foe, me).is_empty(), "plus rien à rendre ensuite")


func _test_deeds() -> void:
	var st := _state(341)
	var me := _me(st)
	_ok(DeedsEval.value(st, me, "cap_titan") == 0 and DeedsEval.value(st, me, "cap_fleet") == 0, "hauts faits : rien au départ")
	var f := st.spawn_ship(me, "fregate", _empty_system(st))
	for _i in 10:
		f.add_ship(Capture.prize_id("corvette", 1))
	_ok(DeedsEval.value(st, me, "cap_fleet") == 10, "Flotte de prises : 10 prises en service")
	Capture.note_stat(st, me, "mega_prizes")
	_ok(DeedsEval.value(st, me, "cap_titan") == 1, "Prise d'un titan comptée")
	Capture.note_stat(st, me, "wrecks", 50)
	_ok(DeedsEval.value(st, me, "cap_scrap") == 50, "Ferrailleur : 50 épaves récoltées")
	var dd: Dictionary = Deeds.data()["deeds"]
	_ok((dd.has("prise_titan") and dd.has("flotte_prises") and dd.has("ferrailleur")), "trois hauts faits déclarés")


func _test_menu_option() -> void:
	_ok(FileAccess.get_file_as_string("res://scripts/ui/main_menu.gd").contains("\"capture\": capture"), "option « Prises de guerre » au menu de nouvelle partie")
	var st := GameState.create(351, 150, 1800.0, "ossarane", {"ai_level": "normal", "capture": "complete"})
	var e := st.empires[1]
	var sid := _empty_system(st)
	var f := st.spawn_ship(e.id, "transport", sid)
	f.troops = 200
	CaptureTomb.force_spawn(st, sid)
	st.tick = 0
	var ctx := {"state": st, "e": e, "lv": AiLevels.level("expert"), "ai": AiLevels.personality(e), "salt": 0, "intent": ""}
	AiCapture.think(ctx)
	_ok(not CaptureTomb.active(st) or f.troops < 200 or AiPlayer._skill(ctx) < 2, "IA : une flotte garnie aborde le Vaisseau-tombe")
