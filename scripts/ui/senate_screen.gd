class_name SenateScreen
extends RefCounted
## Écran Sénat (P) : la politique intérieure de l'empire (voir Politics).
## Colonne de gauche : le régime (selon le gouvernement), les courants au pouvoir, la prochaine
## élection et le soutien choisi. Contenu : l'hémicycle de la dernière élection, les six courants
## (opinion de l'empire, représentants, au pouvoir, bouton Soutenir ou Nommer), puis le dépouillement
## par système (représentants, courant majoritaire, effet sur la stabilité).
## Construit dans les conteneurs d'EmpireScreens, dont il reprend les aides (_grid, _key_value…).


## Hémicycle : les représentants en arcs, colorés par courant (ordre de la roue, gauche à droite).
class Hemicycle:
	extends Control
	var counts: Array = []
	var colors: Array = []
	var ruling: Array = []

	func _init() -> void:
		custom_minimum_size = Vector2(420, 220)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var total := 0
		for c in counts:
			total += int(c)
		var center := Vector2(size.x * 0.5, size.y - 14.0)
		var r_out := minf(size.x * 0.5, size.y) - 14.0
		if total <= 0:
			draw_arc(center, r_out * 0.7, PI, TAU, 48, Color(UiTheme.TEXT_DIM, 0.5), 2.0, true)
			return
		# Rangées : autant que nécessaire pour loger les sièges (au plus 8).
		var rows := clampi(int(ceil(sqrt(float(total) / 6.0))), 1, 8)
		var radii: Array[float] = []
		var caps: Array[int] = []
		var cap_sum := 0
		for k in rows:
			var r := r_out * (0.45 + 0.55 * float(k + 1) / float(rows))
			radii.append(r)
			caps.append(int(r))
			cap_sum += int(r)
		var seats: Array[Vector2] = []
		var angles: Array[float] = []
		for k in rows:
			var n := maxi(1, int(round(float(total) * caps[k] / cap_sum)))
			for j in n:
				var a := PI + PI * (float(j) + 0.5) / float(n)
				seats.append(center + Vector2(cos(a), sin(a)) * radii[k])
				angles.append(a)
		# Sièges triés par angle : les courants s'étalent de gauche à droite.
		var order: Array = []
		for i in seats.size():
			order.append([angles[i], i])
		order.sort()
		var dot := clampf(r_out / float(rows) * 0.32, 2.5, 9.0)
		var s := 0
		for ci in counts.size():
			for _j in int(counts[ci]):
				if s >= order.size():
					break
				var p: Vector2 = seats[int(order[s][1])]
				var col: Color = colors[ci]
				draw_circle(p, dot, col if ruling.has(ci) else Color(col, 0.45))
				s += 1


static func build(es: EmpireScreens) -> void:
	var state := es._state
	var player := es._player
	es._senate_sig = signature(es)
	es.senate_buttons.clear()
	es._side_header("screen_senate", "Sénat", Color(0.66, 0.55, 0.88), "faction")
	var applies := Politics.applies(state, player)
	var reg := Politics.regime(state, player) if state.get_empire(player) != null else {}
	var g := es._grid()
	es._side_box.add_child(g)
	if not state.politics_on:
		es._side_box.add_child(UiTheme.paragraph("Cette partie se joue sans politique intérieure (réglage de Nouvelle partie).", EmpireScreens.SIDE_WIDTH - 24.0, 13))
	elif not reg.is_empty():
		es._key_value(g, "Régime", String(reg["label"]))
		if applies:
			var names := PackedStringArray()
			for i in Politics.ruling(state, player):
				names.append(Politics.short(state, player, int(i)))
			var rl := es._key_value(g, "Au pouvoir", ", ".join(names))
			rl.add_theme_color_override("font_color", Politics.color(Politics.lead(state, player)).lightened(0.2))
			if Politics.mode(state, player) != "continuous":
				var left := maxi(0, Politics.next_election(state, player) - state.tick)
				@warning_ignore("integer_division")
				es._key_value(g, "Prochaine élection", "dans %d mois" % maxi(1, (left + 29) / 30) if left > 0 else "ce mois-ci")
				var pk := Politics.pick(state, player)
				var appoint := Politics.mode(state, player) == "appoint"
				var pl := es._key_value(g, "Courant nommé" if appoint else "Votre soutien", Politics.short(state, player, pk) if pk >= 0 else ("le choix du peuple" if appoint else "aucun"))
				if pk >= 0:
					pl.add_theme_color_override("font_color", Politics.color(pk).lightened(0.2))
			var n := int(Politics.emp(state, player).get("n", 0))
			es._key_value(g, "Élections tenues", str(n))
		es._side_box.add_child(HSeparator.new())
		es._side_box.add_child(UiTheme.paragraph(String(reg.get("text", "")), EmpireScreens.SIDE_WIDTH - 24.0, 13))
	es._side_box.add_child(HSeparator.new())
	es._side_box.add_child(UiTheme.paragraph(String(EmpireBar.screen_info("senate").get("why", "")), EmpireScreens.SIDE_WIDTH - 24.0, 13))

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	es._content.add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 18)
	scroll.add_child(col)
	if not applies:
		var b := Widgets.Block.new(String(reg.get("label", "Sénat")) if not reg.is_empty() else "Sénat")
		col.add_child(b)
		var why := "Pas de vie politique dans cette partie." if not state.politics_on else String(reg.get("text", "Une seule volonté : pas de courants, pas de vote."))
		b.body.add_child(UiTheme.paragraph(why, 760.0, 15))
		return
	col.add_child(_assembly_block(es))
	col.add_child(_currents_block(es))
	col.add_child(_count_block(es))


## Ce qui change l'écran : mois, entrée d'empire, entrées des systèmes de l'empire.
static func signature(es: EmpireScreens) -> String:
	var state := es._state
	var syss := []
	for sid in Stability.systems_of(state, es._player):
		syss.append(Politics.sys_entry(state, sid).get("rep", -1))
	@warning_ignore("integer_division")
	return "%d|%s|%s|%s" % [state.tick / 30, str(Politics.emp(state, es._player)), str(syss), str(state.politics_on)]


## L'hémicycle de la dernière élection (ou du consensus du mois), et son résultat.
static func _assembly_block(es: EmpireScreens) -> Control:
	var state := es._state
	var player := es._player
	var en := Politics.emp(state, player)
	var reg := Politics.regime(state, player)
	var b := Widgets.Block.new(String(reg["label"]))
	var votes: Array = en.get("votes", [])
	var continuous := Politics.mode(state, player) == "continuous"
	if votes.is_empty() or (not continuous and int(en.get("n", 0)) == 0):
		b.body.add_child(UiTheme.paragraph("Pas encore d'élection : le premier vote aura lieu au jour %d. D'ici là, gouvernent les courants du penchant de votre peuple." % Politics.next_election(state, player), 760.0, 14))
		return b
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	b.body.add_child(row)
	var h := Hemicycle.new()
	var colors := []
	var shown := []
	var tot := 0
	for i in Politics.N:
		colors.append(Politics.color(i))
		tot += int(votes[i])
	if continuous:
		# Consensus : l'opinion des nœuds, ramenée à 100 sièges.
		for i in Politics.N:
			@warning_ignore("integer_division")
			shown.append(int(votes[i]) * 100 / maxi(1, tot))
	else:
		shown = votes.duplicate()
	h.counts = shown
	h.colors = colors
	h.ruling = Politics.ruling(state, player)
	row.add_child(h)
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 4)
	row.add_child(side)
	if continuous:
		side.add_child(UiTheme.dim("Consensus du mois (nœuds reliés)", 13))
	else:
		side.add_child(UiTheme.dim("Élection du %s" % GameCalendar.date_string(int(en.get("last", 0))), 13))
	var final: Array = en.get("final", [])
	for i in Politics.ruling(state, player):
		var l := Label.new()
		var v := int(final[int(i)]) if not final.is_empty() else int(votes[int(i)])
		var raw := int(votes[int(i)])
		@warning_ignore("integer_division")
		var pct := raw * 100 / maxi(1, tot)
		if continuous:
			l.text = "%s  %d %%" % [Politics.short(state, player, int(i)), pct]
		elif v > raw:
			l.text = "%s  %d  (%d élu%s + %d voix reçue%s)" % [Politics.short(state, player, int(i)), v, raw, "s" if raw > 1 else "", v - raw, "s" if v - raw > 1 else ""]
		else:
			l.text = "%s  %d représentants" % [Politics.short(state, player, int(i)), v]
		l.add_theme_color_override("font_color", Politics.color(int(i)).lightened(0.2))
		l.add_theme_font_size_override("font_size", 16)
		side.add_child(l)
	var top := int(en.get("top", -1))
	if Politics.mode(state, player) == "appoint" and top >= 0 and not Politics.in_power(state, player, top):
		side.add_child(UiTheme.paragraph("Le peuple avait voté %s%s." % [Politics.label(state, player, top),
				(" : la nomination a coûté %d de ferveur" % int(en.get("fervor", 0))) if int(en.get("fervor", 0)) > 0 else ""], 300.0, 13))
	elif not continuous:
		side.add_child(UiTheme.paragraph("Les courants battus ont donné leurs voix au vainqueur le plus proche sur la roue, jamais à l'opposé.", 300.0, 12))
	return b


## Les six courants : opinion de l'empire, représentants, au pouvoir, soutien.
static func _currents_block(es: EmpireScreens) -> Control:
	var state := es._state
	var player := es._player
	var b := Widgets.Block.new("Les six courants")
	var op := Politics.empire_opinion(state, player)
	var votes: Array = Politics.emp(state, player).get("votes", [])
	var mode := Politics.mode(state, player)
	var ro := state.get_empire(player) == null
	var pk := Politics.pick(state, player)
	for i in Politics.N:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		b.body.add_child(row)
		var sw := ColorRect.new()
		sw.color = Politics.color(i)
		sw.custom_minimum_size = Vector2(10, 22)
		row.add_child(sw)
		var nl := Label.new()
		nl.text = Politics.short(state, player, i)
		nl.custom_minimum_size = Vector2(150, 0)
		nl.add_theme_font_size_override("font_size", 16)
		nl.add_theme_color_override("font_color", Politics.color(i).lightened(0.25))
		nl.mouse_filter = Control.MOUSE_FILTER_STOP
		var d := Politics.current_def(i)
		nl.tooltip_text = "%s\nCe qui le nourrit : %s\nOpposé : %s" % [String(d["text"]), String(d["acts"]), Politics.short(state, player, Politics.opposite(i))]
		row.add_child(nl)
		var bar := ProgressBar.new()
		bar.min_value = 0
		bar.max_value = 1000
		bar.value = int(op[i])
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(160, 10)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var fill := StyleBoxFlat.new()
		fill.bg_color = Politics.color(i)
		bar.add_theme_stylebox_override("fill", fill)
		row.add_child(bar)
		var pl := Label.new()
		@warning_ignore("integer_division")
		pl.text = "%d %%" % ((int(op[i]) + 5) / 10)
		pl.custom_minimum_size = Vector2(50, 0)
		pl.add_theme_font_size_override("font_size", 14)
		row.add_child(pl)
		var vl := Label.new()
		vl.text = ("%d élu%s" % [int(votes[i]), "s" if int(votes[i]) > 1 else ""]) if not votes.is_empty() and mode != "continuous" else ""
		vl.custom_minimum_size = Vector2(70, 0)
		vl.add_theme_font_size_override("font_size", 13)
		vl.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
		row.add_child(vl)
		if Politics.in_power(state, player, i):
			var tl := Label.new()
			tl.text = "EN TÊTE" if Politics.lead(state, player) == i and Politics.seats(state, player) > 1 else "AU POUVOIR"
			tl.custom_minimum_size = Vector2(96, 0)
			tl.add_theme_color_override("font_color", UiTheme.GOLD)
			tl.add_theme_font_size_override("font_size", 13)
			row.add_child(tl)
		else:
			var sp := Control.new()
			sp.custom_minimum_size = Vector2(96, 0)
			row.add_child(sp)
		if not ro and mode != "continuous":
			var btn := Button.new()
			btn.focus_mode = Control.FOCUS_NONE
			btn.toggle_mode = true
			btn.button_pressed = pk == i
			var appoint := mode == "appoint"
			btn.text = ("Nommé" if pk == i else "Nommer") if appoint else ("Soutenu" if pk == i else "Soutenir")
			var cost := int(Politics.regime(state, player).get("fervor_cost", 0))
			btn.tooltip_text = ("À la prochaine élection, ce courant gouvernera, quel que soit le vote." + ("\nS'il n'est pas celui que le peuple choisit : -%d ferveur." % cost if cost > 0 else "")) if appoint \
					else "Soutien officiel : +%d pour mille de poids à ce courant dans chaque tirage de représentant, à la prochaine élection." % int(Politics.data()["support_bonus"])
			var target := -1 if pk == i else i
			btn.pressed.connect(func() -> void: es.command_requested.emit(SimCommands.politics_support(player, target)))
			row.add_child(btn)
			es.senate_buttons[i] = btn
	return b


## Dépouillement par système : représentants, courant majoritaire, effet sur la stabilité.
static func _count_block(es: EmpireScreens) -> Control:
	var state := es._state
	var player := es._player
	var b := Widgets.Block.new("Dépouillement par système")
	var syss := Stability.systems_of(state, player)
	if syss.is_empty():
		b.body.add_child(UiTheme.dim("Aucun système.", 14))
		return b
	for sid in syss:
		var en := Politics.sys_entry(state, sid)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		b.body.add_child(row)
		var name_b := Button.new()
		name_b.flat = true
		name_b.text = state.galaxy.systems[sid].system_name
		name_b.custom_minimum_size = Vector2(170, 0)
		name_b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		name_b.clip_text = true
		name_b.add_theme_font_size_override("font_size", 15)
		var first := es._first_claim(sid)
		name_b.pressed.connect(func() -> void: es.planet_requested.emit(first))
		row.add_child(name_b)
		var reps: Array = en.get("reps", []) if int(en.get("o", -1)) == player else []
		var counts := HBoxContainer.new()
		counts.add_theme_constant_override("separation", 6)
		counts.custom_minimum_size = Vector2(240, 0)
		row.add_child(counts)
		if reps.is_empty():
			counts.add_child(UiTheme.dim("pas encore de représentants", 13))
		else:
			for i in Politics.N:
				if int(reps[i]) <= 0:
					continue
				var l := Label.new()
				l.text = "%s %d" % [Politics.short(state, player, i).substr(0, 3), int(reps[i])]
				l.add_theme_color_override("font_color", Politics.color(i).lightened(0.2))
				l.add_theme_font_size_override("font_size", 13)
				counts.add_child(l)
		var op := Politics.opinion(state, sid)
		if not op.is_empty():
			var top := Politics._argmax(op)
			var ol := Label.new()
			@warning_ignore("integer_division")
			ol.text = "penche %s (%d %%)" % [Politics.short(state, player, top), (int(op[top]) + 5) / 10]
			ol.custom_minimum_size = Vector2(170, 0)
			ol.add_theme_font_size_override("font_size", 13)
			ol.add_theme_color_override("font_color", Politics.color(top).lightened(0.2))
			row.add_child(ol)
		var part := Politics.stability_part(state, sid, player)
		if not part.is_empty():
			var sl := Label.new()
			sl.text = "%+d stabilité" % int(part[1])
			sl.add_theme_color_override("font_color", UiTheme.delta_color(int(part[1])))
			sl.add_theme_font_size_override("font_size", 13)
			sl.tooltip_text = String(part[0])
			sl.mouse_filter = Control.MOUSE_FILTER_STOP
			row.add_child(sl)
	return b
