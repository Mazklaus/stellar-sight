class_name OrderScreen
extends RefCounted
## Écran Ordre intérieur (F12) : la stabilité de l'empire (voir Stability).
## Colonne de gauche : stabilité d'empire et son effet, systèmes par palier, talents du peuple.
## Contenu : vos systèmes du moins stable au plus stable (valeur, palier, cible, décret en cours,
## décrets possibles), puis les mondes libres qui touchent votre territoire (réintégrer).
## Construit dans les conteneurs d'EmpireScreens, dont il reprend les aides (_grid, _key_value…).


static func build(es: EmpireScreens) -> void:
	var state := es._state
	var player := es._player
	es._order_sig = signature(es)
	es.order_buttons.clear()
	es._side_header("screen_order", "Ordre intérieur", Color(0.42, 0.75, 0.55), "faction")
	var applies := Stability.applies(state, player)
	var g := es._grid()
	es._side_box.add_child(g)
	if applies:
		var ev := Stability.empire_value(state, player)
		var vl := es._key_value(g, "Stabilité d'empire", str(ev))
		vl.add_theme_color_override("font_color", Color(String(Stability.tier_for(ev)["color"])))
		var pct := Stability.empire_pct(state, player)
		var pl := es._key_value(g, "Savoir, influence", "%+d %%" % pct)
		pl.add_theme_color_override("font_color", UiTheme.delta_color(pct))
		pl.tooltip_text = String(Stability.data()["empire"].get("_doc", ""))
		pl.mouse_filter = Control.MOUSE_FILTER_STOP
		var inf := Stability.extra_influence(state, player)
		if inf > 0:
			es._key_value(g, "Ferveur", "+%d influence" % inf)
		es._side_box.add_child(HSeparator.new())
		var counts := {}
		for sid in Stability.systems_of(state, player):
			var t := Stability.tier_id(state, sid)
			counts[t] = int(counts.get(t, 0)) + 1
		var tg := es._grid()
		es._side_box.add_child(tg)
		var rev := Stability.tiers().duplicate()
		rev.reverse()
		for t: Dictionary in rev:
			var l := es._key_value(tg, String(t["label"]), str(int(counts.get(String(t["id"]), 0))))
			l.add_theme_color_override("font_color", Color(String(t["color"])))
			l.tooltip_text = String(t["text"])
			l.mouse_filter = Control.MOUSE_FILTER_STOP
	else:
		es._side_box.add_child(UiTheme.paragraph("Votre peuple ne connaît pas la stabilité : une seule volonté le tient.", EmpireScreens.SIDE_WIDTH - 24.0, 13))
	var talents := Stability.talent_labels(state, player)
	if not talents.is_empty():
		es._side_box.add_child(HSeparator.new())
		es._side_box.add_child(UiTheme.dim("Talents de votre peuple", 13))
		for tl in talents:
			es._side_box.add_child(UiTheme.paragraph("%s : %s" % [tl[0], tl[1]], EmpireScreens.SIDE_WIDTH - 24.0, 12))
	es._side_box.add_child(HSeparator.new())
	es._side_box.add_child(UiTheme.paragraph(String(EmpireBar.screen_info("order").get("why", "")), EmpireScreens.SIDE_WIDTH - 24.0, 13))

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	es._content.add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 18)
	scroll.add_child(col)
	if applies:
		var mine := Widgets.Block.new("Vos systèmes, du moins stable au plus stable")
		col.add_child(mine)
		var list := []
		var cx := Stability.context(state, player)
		for sid in Stability.systems_of(state, player):
			list.append([Stability.value(state, sid), sid])
		list.sort()
		for it in list:
			mine.body.add_child(_system_row(es, int(it[1]), cx))
		if list.is_empty():
			mine.body.add_child(UiTheme.dim("Aucun système revendiqué.", 14))
	var free := free_worlds(state, player)
	if not free.is_empty():
		var fb := Widgets.Block.new("Mondes libres à vos frontières")
		col.add_child(fb)
		fb.body.add_child(UiTheme.paragraph("Des systèmes qui ont fait sécession et rejoint %s. Ils se reprennent par la force, ou se réintègrent contre de l'influence quand l'empire est assez stable." % String(Stability.data()["npc"]["name"]), 760.0, 13))
		for sid in free:
			fb.body.add_child(_free_row(es, sid))


## Ce qui change l'écran : mois, systèmes et leurs entrées de stabilité, ressources.
static func signature(es: EmpireScreens) -> String:
	var state := es._state
	var e := state.get_empire(es._player)
	@warning_ignore("integer_division")
	return "%d|%s|%s|%s|%d" % [state.tick / 30, str(Stability.systems_of(state, es._player)), str(state.stability),
			str(free_worlds(state, es._player)), e.resources.get("influence", 0) if e else 0]


## Mondes libres (Sans-Bannière) voisins d'un système de l'empire, par identifiant.
static func free_worlds(state: GameState, player: int) -> Array[int]:
	var out: Array[int] = []
	for sid in Stability.systems_of(state, player):
		for n in state.galaxy.systems[sid].neighbors:
			if GameState.is_npc(state.system_owner(n)) and not out.has(n):
				out.append(n)
	out.sort()
	return out


static func _system_row(es: EmpireScreens, sid: int, cx: Dictionary) -> Control:
	var state := es._state
	var player := es._player
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var v := Stability.value(state, sid)
	var tcol := Stability.tier_color(state, sid)
	var name_b := Button.new()
	name_b.flat = true
	name_b.text = state.galaxy.systems[sid].system_name
	name_b.custom_minimum_size = Vector2(170, 0)
	name_b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_b.clip_text = true
	name_b.add_theme_font_size_override("font_size", 16)
	name_b.tooltip_text = "Ouvrir le système"
	var first := es._first_claim(sid)
	name_b.pressed.connect(func() -> void: es.planet_requested.emit(first))
	row.add_child(name_b)
	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = 100
	bar.value = v
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(110, 10)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fill := StyleBoxFlat.new()
	fill.bg_color = tcol
	bar.add_theme_stylebox_override("fill", fill)
	row.add_child(bar)
	var target := Stability.target(state, sid, cx)
	var en := Stability.entry(state, sid)
	var revolt := int(en.get("revolt", 0))
	var vl := Label.new()
	@warning_ignore("integer_division")
	vl.text = "%d %s  %s%s" % [v, ("→ %d" % target) if target != v else "", Stability.tier_label(state, sid),
			("  · révolte %d mois" % (revolt / 30)) if revolt > 0 else ""]
	vl.custom_minimum_size = Vector2(230, 0)
	vl.add_theme_color_override("font_color", tcol)
	vl.add_theme_font_size_override("font_size", 14)
	vl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vl.mouse_filter = Control.MOUSE_FILTER_STOP
	var lines := PackedStringArray(["Cible %d :" % target])
	for p in Stability.parts(state, sid, cx):
		lines.append("  %+d  %s" % [int(p[1]), String(p[0])])
	lines.append("")
	lines.append(String(Stability.tier(state, sid).get("text", "")))
	vl.tooltip_text = "\n".join(lines)
	row.add_child(vl)
	var active := Stability.active_decree(state, sid)
	if active != "":
		var al := Label.new()
		al.text = "%s (%d j)" % [String(Stability.decree_def(active)["label"]), int(en.get("decree_end", 0)) - state.tick]
		al.add_theme_color_override("font_color", UiTheme.GOLD)
		al.add_theme_font_size_override("font_size", 13)
		al.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(al)
	elif not _ro(es):
		for id in Stability.decree_ids():
			var why := Stability.check_decree(state, player, sid, id)
			var b := Button.new()
			b.flat = true
			b.focus_mode = Control.FOCUS_NONE
			b.add_theme_font_size_override("font_size", 12)
			b.text = String(Stability.decree_def(id)["label"])
			b.disabled = why != ""
			b.tooltip_text = "%s\nCoût : %s%s" % [String(Stability.decree_def(id)["text"]), GameData.format_amounts(Stability.decree_cost(state, player, id)),
					("\n" + why) if why != "" else ""]
			var did: String = id
			b.pressed.connect(func() -> void: es.command_requested.emit(SimCommands.decree(player, sid, did)))
			row.add_child(b)
			es.order_buttons["%d:%s" % [sid, id]] = b
	return row


static func _free_row(es: EmpireScreens, sid: int) -> Control:
	var state := es._state
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var nl := Label.new()
	nl.text = state.galaxy.systems[sid].system_name
	nl.custom_minimum_size = Vector2(170, 0)
	nl.add_theme_font_size_override("font_size", 16)
	nl.add_theme_color_override("font_color", Color(String(Stability.data()["npc"]["color"])).lightened(0.3))
	row.add_child(nl)
	if not _ro(es):
		var why := Stability.check_reintegrate(state, es._player, sid)
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.text = "Réintégrer (%s)" % GameData.format_amounts(Stability.reintegrate_cost(state, sid))
		b.disabled = why != ""
		b.tooltip_text = why if why != "" else "Le monde libre rentre dans votre empire."
		var player := es._player
		b.pressed.connect(func() -> void: es.command_requested.emit(SimCommands.reintegrate(player, sid)))
		row.add_child(b)
		es.order_buttons["free:%d" % sid] = b
		if why != "":
			row.add_child(UiTheme.dim(why, 12))
	return row


## Observateur (aucun empire) : pas d'ordres.
static func _ro(es: EmpireScreens) -> bool:
	return es._state.get_empire(es._player) == null
