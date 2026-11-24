class_name BattlesScreen
extends RefCounted
## Onglet Batailles du domaine Forces (refonte, C15) : les rapports de bataille de l'empire, dans
## l'espace et au sol, en une liste datée, la plus récente d'abord, avec « Revoir ».
## Construit dans les conteneurs d'EmpireScreens.

const COLOR := Color(0.93, 0.42, 0.38)


## Une entrée par rapport qui concerne l'empire, la plus récente d'abord :
## {kind: "space"/"ground", tick, system, verdict ("won"/"lost"/"draw"), foes, text, index (espace) ou id (sol), replay}.
static func entries(state: GameState, player: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in state.battle_reports.size():
		var r: Dictionary = state.battle_reports[i]
		var mine := false
		var foes := PackedStringArray()
		for s: Dictionary in r["sides"]:
			if int(s["empire"]) == player:
				mine = true
			else:
				var e := state.get_empire(int(s["empire"]))
				foes.append(e.short_name() if e != null else "des inconnus")
		if not mine:
			continue
		var w := int(r.get("winner", -1))
		out.append({"kind": "space", "tick": int(r.get("end", 0)), "system": String(r.get("system_name", "?")),
				"verdict": "won" if w == player else ("draw" if w < 0 else "lost"), "foes": ", ".join(foes), "text": "", "index": i, "replay": true})
	for rep: Dictionary in Ground.reports_for(state, player):
		var how := String(rep["how"])
		var other := int(rep["d"]) if int(rep["a"]) == player else int(rep["a"])
		var oe := state.get_empire(other)
		out.append({"kind": "ground", "tick": int(rep["end"]), "system": state.galaxy.systems[int(rep["s"])].system_name,
				"verdict": "draw" if how == "peace" else ("won" if int(rep["w"]) == player else "lost"), "foes": oe.short_name() if oe != null else "les habitants",
				"text": ArmiesScreen.report_line(state, rep, player), "id": int(rep["id"]), "replay": GroundReplayPanel.has_log(rep)})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["tick"]) != int(b["tick"]):
			return int(a["tick"]) > int(b["tick"])
		return String(a["kind"]) > String(b["kind"]))
	return out


static func signature(es: EmpireScreens) -> String:
	return "%d|%d" % [es._state.battle_reports.size(), Ground.reports_for(es._state, es._player).size()]


static func build(es: EmpireScreens) -> void:
	var state := es._state
	var player := es._player
	es._battles_sig = signature(es)
	es.battles_buttons.clear()
	var list := entries(state, player)
	var won := 0
	var lost := 0
	for e: Dictionary in list:
		if String(e["verdict"]) == "won":
			won += 1
		elif String(e["verdict"]) == "lost":
			lost += 1
	es._side_header("screen_battles", "Batailles", COLOR, "faction")
	var g := es._grid()
	es._side_box.add_child(g)
	es._key_value(g, "Rapports gardés", str(list.size()))
	es._key_value(g, "Victoires", str(won)).add_theme_color_override("font_color", UiTheme.GOOD)
	es._key_value(g, "Défaites", str(lost)).add_theme_color_override("font_color", UiTheme.BAD if lost > 0 else UiTheme.TEXT)
	var now := 0
	for sid in state.battles:
		if Espionage.battle_sides(state.battles[sid]).has(player):
			now += 1
	es._key_value(g, "Batailles en cours", str(now))
	es._side_box.add_child(HSeparator.new())
	es._side_box.add_child(UiTheme.paragraph("« Revoir » rouvre le rapport d'une bataille spatiale, d'où elle se rejoue, ou rejoue une bataille au sol jour par jour. La touche B rouvre toujours le dernier rapport.", EmpireScreens.SIDE_WIDTH - 24.0, 12))

	var blk := Widgets.Block.new("Rapports de bataille")
	blk.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	blk.size_flags_vertical = Control.SIZE_EXPAND_FILL
	blk.body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	es._content.add_child(blk)
	if list.is_empty():
		blk.body.add_child(UiTheme.dim("Aucune bataille à raconter pour l'instant.", 14))
		return
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	blk.body.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	scroll.add_child(box)
	for e: Dictionary in list:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var date := UiTheme.dim(GameCalendar.date_string(int(e["tick"])), 13)
		date.custom_minimum_size = Vector2(96, 0)
		row.add_child(date)
		var kind := UiTheme.dim("ESPACE" if String(e["kind"]) == "space" else "SOL", 12)
		kind.custom_minimum_size = Vector2(60, 0)
		row.add_child(kind)
		var v := Label.new()
		v.custom_minimum_size = Vector2(90, 0)
		match String(e["verdict"]):
			"won":
				v.text = "Victoire"
				v.add_theme_color_override("font_color", UiTheme.GOOD)
			"lost":
				v.text = "Défaite"
				v.add_theme_color_override("font_color", UiTheme.BAD)
			_:
				v.text = "Sans vainqueur"
				v.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
		row.add_child(v)
		var what := UiTheme.paragraph("%s, contre %s" % [e["system"], e["foes"] if String(e["foes"]) != "" else "personne"], 560.0, 14)
		what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if String(e["text"]) != "":
			what.tooltip_text = String(e["text"])
			what.mouse_filter = Control.MOUSE_FILTER_STOP
		row.add_child(what)
		if bool(e["replay"]):
			var b := Button.new()
			b.text = "REVOIR"
			b.focus_mode = Control.FOCUS_NONE
			if String(e["kind"]) == "space":
				var idx := int(e["index"])
				b.pressed.connect(func() -> void: es.battle_report_requested.emit(idx))
				es.battles_buttons["space:%d" % idx] = b
			else:
				var rid := int(e["id"])
				b.pressed.connect(func() -> void: es.ground_replay_requested.emit(rid))
				es.battles_buttons["ground:%d" % rid] = b
			row.add_child(b)
		box.add_child(row)
