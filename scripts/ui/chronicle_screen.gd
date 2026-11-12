class_name ChronicleScreen
extends RefCounted
## Écran Chroniques (J) : les événements qui attendent une décision (boîte), le journal des décisions
## prises, et les curiosités repérées dans la galaxie (voir Events et Curios).
## Construit dans les conteneurs d'EmpireScreens, dont il reprend les aides (_grid, _key_value…).


static func build(es: EmpireScreens) -> void:
	var state := es._state
	var player := es._player
	es._chron_sig = signature(es)
	es.chronicle_buttons.clear()
	var box := Events.inbox(state, player)
	var log: Array = Events.meta(state, player)["log"] if state.ev_meta.has(player) else []
	var known := Curios.known(state, player)

	# Colonne de gauche.
	es._side_header("screen_chronicles", "Chroniques", Color(0.95, 0.78, 0.45), "star")
	var g := es._grid()
	es._side_box.add_child(g)
	es._key_value(g, "En attente", "%d" % box.size())
	es._key_value(g, "Décisions prises", "%d" % log.size())
	es._key_value(g, "Curiosités repérées", "%d" % known.size())
	if state.curio_density != "aucune":
		var det := es._key_value(g, "Détection", "niveau %d" % Curios.detect(state, player))
		det.tooltip_text = "Les curiosités de niveau supérieur restent invisibles. Les capteurs et certaines technologies l'améliorent."
		det.mouse_filter = Control.MOUSE_FILTER_STOP
		var pw := es._key_value(g, "Puissance d'expédition", "%d" % Curios.power(state, player))
		pw.tooltip_text = "Plus elle dépasse le niveau d'une curiosité, plus la sonde est rapide (de 180 jours à 15)."
		pw.mouse_filter = Control.MOUSE_FILTER_STOP
	es._side_box.add_child(HSeparator.new())
	es._side_box.add_child(UiTheme.paragraph(String(EmpireBar.screen_info("chronicles").get("why", "")), EmpireScreens.SIDE_WIDTH - 24.0, 13))

	# Contenu défilant.
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	es._content.add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 18)
	scroll.add_child(col)

	if not Events.enabled(state) and state.curio_density == "aucune":
		col.add_child(UiTheme.dim("Ni événements ni curiosités dans cette partie (réglage de la Nouvelle partie).", 15))
		return

	var wait := Widgets.Block.new("En attente de décision")
	col.add_child(wait)
	if box.is_empty():
		wait.body.add_child(UiTheme.dim("Rien pour l'instant. Les nouvelles arrivent d'elles-mêmes." if Events.enabled(state)
				else "Les événements sont désactivés pour cette partie.", 14))
	for item: Dictionary in box:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var b := Button.new()
		b.theme_type_variation = &"PrimaryButton"
		b.focus_mode = Control.FOCUS_NONE
		b.text = "Décider"
		var id := int(item["id"])
		b.pressed.connect(func() -> void: es.event_requested.emit(id))
		es.chronicle_buttons["event:%d" % id] = b
		row.add_child(b)
		var t := UiTheme.title(Events.fill(state, player, item, String(Events.card(String(item["card"])).get("title", ""))), 18)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(t)
		var left := maxi(0, int(item["until"]) - state.tick)
		row.add_child(UiTheme.dim("encore %d jour%s" % [left, "s" if left > 1 else ""], 13))
		wait.body.add_child(row)

	var cur := Widgets.Block.new("Curiosités repérées")
	col.add_child(cur)
	if known.is_empty():
		cur.body.add_child(UiTheme.dim("Aucune curiosité en vue. Explorez, et améliorez votre détection." if state.curio_density != "aucune"
				else "Pas de curiosités dans cette partie.", 14))
	var cg := GridContainer.new()
	cg.columns = 4
	cg.add_theme_constant_override("h_separation", 18)
	cg.add_theme_constant_override("v_separation", 6)
	if not known.is_empty():
		cur.body.add_child(cg)
	for pid in known:
		var p := state.galaxy.get_planet(pid)
		var vb := Button.new()
		vb.flat = true
		vb.focus_mode = Control.FOCUS_NONE
		vb.alignment = HORIZONTAL_ALIGNMENT_LEFT
		vb.text = Curios.describe(state, pid)
		vb.tooltip_text = "Ouvrir le système"
		var ppid := pid
		vb.pressed.connect(func() -> void: es.planet_requested.emit(ppid))
		es.chronicle_buttons["curio:%d" % pid] = vb
		cg.add_child(vb)
		cg.add_child(UiTheme.dim(p.display_name(state.galaxy), 13))
		cg.add_child(UiTheme.dim("sonde : %d jours" % Curios.duration(state, player, pid), 13))
		var prog := Curios.progress(state, player, pid)
		cg.add_child(UiTheme.dim("en cours : %d / %d" % [prog, Curios.duration(state, player, pid)] if prog > 0 else "", 13))

	var jr := Widgets.Block.new("Journal")
	col.add_child(jr)
	if log.is_empty():
		jr.body.add_child(UiTheme.dim("Aucune décision prise pour l'instant.", 14))
	for i in range(log.size() - 1, -1, -1):
		var x: Dictionary = log[i]
		var l := UiTheme.paragraph("%s  ·  %s : %s" % [GameCalendar.date_string(int(x["tick"])), x["title"], x["label"]], 900.0, 14)
		jr.body.add_child(l)


## Ce qui change l'écran : boîte, journal, curiosités visibles et avancement des sondes.
static func signature(es: EmpireScreens) -> String:
	var state := es._state
	var player := es._player
	var s := "%s|%d" % [str(Events.inbox(state, player).map(func(it: Dictionary) -> int: return int(it["id"]))),
			(Events.meta(state, player)["log"] as Array).size() if state.ev_meta.has(player) else 0]
	for pid in Curios.known(state, player):
		s += "|%d:%d" % [pid, Curios.progress(state, player, pid)]
	@warning_ignore("integer_division")
	return s + "|%d" % (state.tick / 30)
