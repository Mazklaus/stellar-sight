class_name IntelScreen
extends RefCounted
## Écran Renseignement (F8) : les réseaux de l'ombre (voir Espionage).
## Colonne de gauche : cellules, chiffrement, sondes, réseaux soupçonnés chez nous.
## Contenu : une ligne par empire rencontré (infiltration, palier, évolution, cellules affectées) et le
## contre-espionnage ; à droite, le dossier de l'empire choisi, ou ce que ses paliers dévoileraient.
## Construit dans les conteneurs d'EmpireScreens, dont il reprend les aides (_grid, _key_value…).

const BAR_WIDTH := 130.0


static func build(es: EmpireScreens) -> void:
	var state := es._state
	var player := es._player
	var me := state.get_empire(player)
	es._intel_sig = signature(es)
	es.intel_buttons.clear()
	es.intel_op_buttons.clear()
	es.intel_case_buttons.clear()
	if es.intel_selected < 0 or not me.contacts.has(es.intel_selected) or state.get_empire(es.intel_selected).eliminated:
		es.intel_selected = -1
		for o in me.contacts:
			if not state.get_empire(o).eliminated:
				es.intel_selected = o
				break

	# Colonne de gauche.
	es._side_header("screen_intel", "Renseignement", Color(0.55, 0.85, 0.75), "faction")
	var g := es._grid()
	es._side_box.add_child(g)
	es._key_value(g, "Cellules", "%d / %d" % [Espionage.cells_used(state, player), Espionage.cells_total(state, player)])
	var free := es._key_value(g, "Libres", str(Espionage.cells_free(state, player)))
	free.add_theme_color_override("font_color", UiTheme.GOLD if Espionage.cells_free(state, player) > 0 else UiTheme.TEXT)
	var dec := es._key_value(g, "Déchiffrement", str(Espionage.decryption(state, player)))
	dec.tooltip_text = "Votre ère (et vos talents) : plus elle est avancée, plus vos réseaux percent les codes des autres."
	dec.mouse_filter = Control.MOUSE_FILTER_STOP
	var enc := es._key_value(g, "Chiffrement", str(Espionage.encryption(state, player)))
	enc.tooltip_text = "Votre ère, +%d si au moins une cellule fait du contre-espionnage chez vous, plus vos talents." % int(Espionage.data()["network"]["home_cell_encryption"])
	enc.mouse_filter = Control.MOUSE_FILTER_STOP
	var wait := Espionage.probe_wait(state, me)
	var pv := es._key_value(g, "Sondes", "%d / %d" % [me.probes, Espionage.probes_max()])
	pv.tooltip_text = ("Prochaine sonde dans %d jours." % wait if me.probes < Espionage.probes_max() else "Stock plein.") + \
			"\nUne sonde (%s) rapporte un relevé d'un système connu hors de vue : bouton SONDE dans la vue du système." % GameData.format_amounts(Espionage.probe_cost())
	pv.mouse_filter = Control.MOUSE_FILTER_STOP
	es._side_box.add_child(HSeparator.new())
	var sus := Espionage.suspected(state, player)
	if Espionage.home_cells(state, player) <= 0:
		es._side_box.add_child(UiTheme.paragraph("Sans cellule chez vous, vous ne saurez pas qui vous espionne.", EmpireScreens.SIDE_WIDTH - 24.0, 13))
	elif sus.is_empty():
		es._side_box.add_child(UiTheme.paragraph("Le contre-espionnage ne signale aucun réseau étranger notable.", EmpireScreens.SIDE_WIDTH - 24.0, 13))
	else:
		var names := PackedStringArray()
		for s in sus:
			names.append(state.get_empire(s).short_name())
		var t := UiTheme.paragraph("Réseaux soupçonnés chez nous : %s." % ", ".join(names), EmpireScreens.SIDE_WIDTH - 24.0, 13)
		t.add_theme_color_override("font_color", UiTheme.WARN)
		es._side_box.add_child(t)
	var doubles := Espionage.turned_by(state, player)
	if not doubles.is_empty():
		var dn := PackedStringArray()
		for s in doubles:
			dn.append(state.get_empire(s).short_name())
		var td := UiTheme.paragraph("Agents doubles : nous tenons le réseau de %s, qui ne lit que ce que nous voulons." % ", ".join(dn), EmpireScreens.SIDE_WIDTH - 24.0, 13)
		td.add_theme_color_override("font_color", UiTheme.GOLD)
		es._side_box.add_child(td)
	var talents := Espionage.talent_labels(state, player)
	if not talents.is_empty():
		es._side_box.add_child(HSeparator.new())
		es._side_box.add_child(UiTheme.dim("Talents de votre peuple", 13))
		for tl in talents:
			var tlab := UiTheme.paragraph("%s : %s" % [tl[0], tl[1]], EmpireScreens.SIDE_WIDTH - 24.0, 12)
			es._side_box.add_child(tlab)
	es._side_box.add_child(UiTheme.paragraph(String(EmpireBar.screen_info("intel").get("why", "")), EmpireScreens.SIDE_WIDTH - 24.0, 13))

	# Contenu : réseaux à gauche, dossier à droite.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	es._content.add_child(row)
	var left := Widgets.Block.new("Réseaux de l'ombre")
	left.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(left)
	left.body.add_child(_home_line(es))
	left.body.add_child(HSeparator.new())
	var any := false
	for o in me.contacts:
		var oe := state.get_empire(o)
		if oe == null or oe.eliminated:
			continue
		left.body.add_child(_network_line(es, o))
		any = true
	if not any:
		left.body.add_child(UiTheme.dim("Aucun empire rencontré : personne à espionner.", 14))
	var tiers := HBoxContainer.new()
	tiers.add_theme_constant_override("separation", 14)
	for i in Espionage.data()["tiers"].size():
		var info := Espionage.tier_info(i + 1)
		var l := UiTheme.dim("%d  %s" % [int(info["at"]), info["label"]], 12)
		l.tooltip_text = String(info["text"])
		l.mouse_filter = Control.MOUSE_FILTER_STOP
		tiers.add_child(l)
	left.body.add_child(tiers)

	# Colonne de droite défilante : dossiers de découverte, opérations, dossier de renseignement.
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(scroll)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 18)
	scroll.add_child(right)
	var cases := Espionage.cases_for(state, player)
	if not cases.is_empty():
		right.add_child(_cases_block(es, cases))
	if es.intel_selected >= 0:
		right.add_child(_operations_block(es, es.intel_selected))
		right.add_child(_dossier_block(es, es.intel_selected))


## Ce qui change l'écran : réseaux, mois, sondes, contacts, empire choisi.
static func signature(es: EmpireScreens) -> String:
	var me := es._state.get_empire(es._player)
	@warning_ignore("integer_division")
	return "%s|%d|%d|%s|%d|%d|%s|%s|%d|%s" % [str(es._state.networks), es._state.tick / 30, me.probes, str(me.contacts), es.intel_selected,
			Research.current_era(es._state, es._player), str(es._state.operations), str(es._state.spy_cases),
			int(me.resources.get("influence", 0)), str(Heroes.meta(es._state, es._player).get("files", []))]


static func _cells_box(es: EmpireScreens, target: int) -> HBoxContainer:
	var state := es._state
	var player := es._player
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var n := Espionage.cells_on(state, player, target)
	var minus := Button.new()
	minus.text = "−"
	minus.focus_mode = Control.FOCUS_NONE
	minus.custom_minimum_size = Vector2(28, 0)
	minus.disabled = n <= 0
	minus.tooltip_text = "Rappeler une cellule"
	minus.pressed.connect(func() -> void: es.command_requested.emit(SimCommands.spy_cells(player, target, n - 1)))
	box.add_child(minus)
	var l := Label.new()
	l.text = str(n)
	l.theme_type_variation = &"Numbers"
	l.custom_minimum_size = Vector2(22, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(l)
	var plus := Button.new()
	plus.text = "+"
	plus.focus_mode = Control.FOCUS_NONE
	plus.custom_minimum_size = Vector2(28, 0)
	var why := Espionage.check_cells(state, player, target, n + 1)
	plus.disabled = why != ""
	plus.tooltip_text = why if why != "" else "Affecter une cellule"
	plus.pressed.connect(func() -> void: es.command_requested.emit(SimCommands.spy_cells(player, target, n + 1)))
	box.add_child(plus)
	es.intel_buttons[target] = [minus, plus]
	return box


static func _home_line(es: EmpireScreens) -> Control:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	var name := Label.new()
	name.text = "Contre-espionnage"
	name.custom_minimum_size = Vector2(150, 0)
	line.add_child(name)
	var cfg: Dictionary = Espionage.data()["network"]
	var info := UiTheme.dim("Chaque cellule freine tous les réseaux étrangers de %d par mois et ajoute %d au chiffrement." % [
			int(cfg["counter_per_cell"]), int(cfg["home_cell_encryption"])], 13)
	info.custom_minimum_size = Vector2(BAR_WIDTH + 170, 0)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.add_child(info)
	line.add_child(_cells_box(es, es._player))
	return line


static func _network_line(es: EmpireScreens, target: int) -> Control:
	var state := es._state
	var player := es._player
	var oe := state.get_empire(target)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	var name := Button.new()
	name.text = oe.short_name()
	name.flat = true
	name.focus_mode = Control.FOCUS_NONE
	name.alignment = HORIZONTAL_ALIGNMENT_LEFT
	name.custom_minimum_size = Vector2(150, 0)
	name.add_theme_color_override("font_color", oe.color().lerp(Color.WHITE, 0.35 if target != es.intel_selected else 0.7))
	name.tooltip_text = "Voir le dossier"
	name.pressed.connect(func() -> void:
		es.intel_selected = target
		es.show_screen("intel"))
	line.add_child(name)
	var inf := Espionage.infiltration(state, player, target)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(BAR_WIDTH, 8)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.max_value = int(Espionage.data()["network"]["max"])
	bar.value = inf
	bar.add_theme_stylebox_override("fill", UiTheme.box(oe.color(), Color(0, 0, 0, 0), 0, 0))
	var t := Espionage.tier(state, player, target)
	var tips := PackedStringArray()
	for i in Espionage.data()["tiers"].size():
		var info := Espionage.tier_info(i + 1)
		tips.append("%s %d  %s : %s" % ["✓" if t > i else "·", int(info["at"]), info["label"], info["text"]])
	bar.tooltip_text = "\n".join(tips)
	line.add_child(bar)
	var tl := Label.new()
	tl.text = "%d  %s" % [inf, String(Espionage.tier_info(t).get("label", "—"))]
	tl.custom_minimum_size = Vector2(120, 0)
	tl.add_theme_color_override("font_color", UiTheme.GOLD if t > 0 else UiTheme.TEXT_DIM)
	line.add_child(tl)
	var gr := Espionage.growth(state, player, target)
	var gl := Label.new()
	gl.text = "%+d / mois" % gr
	gl.custom_minimum_size = Vector2(80, 0)
	gl.add_theme_color_override("font_color", UiTheme.delta_color(gr))
	var parts := PackedStringArray()
	for p in Espionage.growth_parts(state, player, target):
		parts.append("%+d  %s" % [int(p[1]), p[0]])
	gl.tooltip_text = "\n".join(parts) if not parts.is_empty() else "Aucune cellule : pas de réseau."
	gl.mouse_filter = Control.MOUSE_FILTER_STOP
	line.add_child(gl)
	line.add_child(_cells_box(es, target))
	return line


static func _dossier_block(es: EmpireScreens, target: int) -> Control:
	var blk := _dossier_core(es, target)
	_hero_file(es, target, blk)
	return blk


## Le dossier de ses héros, rapporté par l'opération du même nom (peut-être un faux).
static func _hero_file(es: EmpireScreens, target: int, blk: Widgets.Block) -> void:
	var f := Heroes.hero_file(es._state, es._player, target)
	if f.is_empty():
		return
	blk.body.add_child(HSeparator.new())
	blk.body.add_child(UiTheme.dim("Ses héros, au %s" % GameCalendar.date_string(int(f["day"])), 13))
	var lines := PackedStringArray()
	for r: Dictionary in f["heroes"]:
		var post := String(r["post"])
		lines.append("%s, %s niv. %d%s, loyauté %d" % [r["name"], String(Heroes.class_def(String(r["cls"])).get("label", r["cls"])).to_lower(),
				int(r["lvl"]), (" (%s)" % Heroes.post_label(post)) if post != "" else "", int(r["loy"])])
	blk.body.add_child(UiTheme.paragraph("\n".join(lines) if not lines.is_empty() else "Aucun héros libre.", 420, 13))


static func _dossier_core(es: EmpireScreens, target: int) -> Widgets.Block:
	var state := es._state
	var oe := state.get_empire(target)
	var me := state.get_empire(es._player)
	var blk := Widgets.Block.new("Dossier : %s" % oe.short_name())
	blk.heading.add_theme_font_size_override("font_size", 22)
	var d: Dictionary = me.dossiers.get(target, {})
	if d.is_empty():
		var t := Espionage.tier(state, es._player, target)
		var msg := "Le réseau doit atteindre %d (Comptables) pour ouvrir un dossier." % Espionage.tier_at(2)
		if t >= 1:
			msg = "Les Cartographes tiennent à jour les relevés de ses systèmes. " + msg
		blk.body.add_child(UiTheme.paragraph(msg, 420, 14))
		return blk
	blk.body.add_child(UiTheme.dim("Rapport du %s" % GameCalendar.date_string(int(d["day"])), 13))
	var g := es._grid()
	blk.body.add_child(g)
	es._key_value(g, "Ère", EmpireScreens.ROMAN[clampi(int(d["era"]) - 1, 0, 4)])
	es._key_value(g, "Technologies", str(int(d["techs"])))
	var rs := String(d.get("research", ""))
	es._key_value(g, "Recherche en cours", String(Research.tech(rs).get("label", rs)) if rs != "" else "aucune")
	es._key_value(g, "Systèmes", str(int(d["colonies"])))
	var net := HBoxContainer.new()
	net.add_theme_constant_override("separation", 10)
	es._fill_net(net, d["res"], 14)
	for ch in net.get_children():
		for l in ch.get_children():
			if l is Label:
				l.text = l.text.trim_prefix("+")
				l.add_theme_color_override("font_color", UiTheme.TEXT)
	blk.body.add_child(UiTheme.dim("Réserves", 13))
	blk.body.add_child(net)
	if int(d["tier"]) >= 3:
		blk.body.add_child(HSeparator.new())
		var g2 := es._grid()
		blk.body.add_child(g2)
		es._key_value(g2, "Flottes", str((d["fleets"] as Array).size()))
		es._key_value(g2, "Vaisseaux", str(int(d["ships"])))
		es._key_value(g2, "dont de guerre", str(int(d["warships"])))
		var biggest := (d["fleets"] as Array).duplicate()
		biggest.sort_custom(func(x: Array, y: Array) -> bool: return int(x[1]) > int(y[1]) or (int(x[1]) == int(y[1]) and int(x[0]) < int(y[0])))
		var lines := PackedStringArray()
		for f in biggest.slice(0, 4):
			lines.append("%s : %d vaisseau%s (%d armé%s)" % [state.galaxy.systems[int(f[0])].system_name, int(f[1]), "x" if int(f[1]) > 1 else "",
					int(f[2]), "s" if int(f[2]) > 1 else ""])
		if not lines.is_empty():
			blk.body.add_child(UiTheme.paragraph("\n".join(lines), 420, 13))
	else:
		blk.body.add_child(UiTheme.dim("Flottes : à %d (Amirauté)." % Espionage.tier_at(3), 13))
	if int(d["tier"]) >= 4:
		blk.body.add_child(HSeparator.new())
		var wars := PackedStringArray()
		for w in d["wars"]:
			wars.append(state.get_empire(int(w)).short_name())
		blk.body.add_child(UiTheme.paragraph("En guerre contre : %s" % (", ".join(wars) if not wars.is_empty() else "personne"), 420, 14))
		var g3 := es._grid()
		blk.body.add_child(g3)
		for pair in d["opinions"]:
			var v := int(pair[1])
			var val := es._key_value(g3, "Pense de %s" % state.get_empire(int(pair[0])).short_name(), "%+d  %s" % [v, Diplomacy.opinion_label(v)])
			val.add_theme_color_override("font_color", UiTheme.delta_color(v) if absi(v) >= 20 else UiTheme.TEXT)
	else:
		blk.body.add_child(UiTheme.dim("Guerres et opinions : à %d (Conseil)." % Espionage.tier_at(4), 13))
	return blk


## Espions démasqués chez nous : expulser ou exiger réparation (sans réponse : expulsion).
static func _cases_block(es: EmpireScreens, cases: Array[Dictionary]) -> Control:
	var state := es._state
	var blk := Widgets.Block.new("Espions démasqués")
	blk.heading.add_theme_font_size_override("font_size", 22)
	var due: Dictionary = Espionage.data()["discovery"]["reparation"]
	for c in cases:
		var spy := state.get_empire(int(c["spy"]))
		var left := int(Espionage.data()["discovery"]["answer_days"]) - (state.tick - int(c["tick"]))
		var l := UiTheme.paragraph("Des agents de %s, pris pendant : %s. Sans réponse dans %d jours, on les expulse." % [
				spy.short_name(), String(Espionage.op_def(String(c["op"])).get("label", c["op"])).to_lower(), left], 420, 14)
		blk.body.add_child(l)
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		blk.body.add_child(line)
		var cid := int(c["id"])
		var buttons := []
		var turn_why := Espionage.check_turn(state, es._player, int(c["spy"]))
		for pair in [["expel", "EXPULSER", "Leur réseau tombe à 0 et leurs cellules rentrent."],
				["reparation", "EXIGER RÉPARATION", "Ils paient %s s'ils le peuvent ; sinon, toute la galaxie apprend qu'ils ont refusé. Leur réseau reste en place." % GameData.format_amounts(due)],
				["turn", "RETOURNER", "On les relâche sans un mot, et ils travaillent pour nous : leurs relevés de nos systèmes et leurs dossiers mentiront, leurs opérations échoueront, jusqu'à ce qu'ils comprennent (environ %d %% de chances par mois)." % Espionage.spot_chance(state, int(c["spy"]), es._player)]]:
			var b := Button.new()
			b.text = pair[1]
			b.focus_mode = Control.FOCUS_NONE
			b.tooltip_text = pair[2]
			if pair[0] == "turn" and turn_why != "":
				b.disabled = true
				b.tooltip_text += "\nImpossible : %s." % turn_why
			var choice := String(pair[0])
			b.pressed.connect(func() -> void: es.command_requested.emit(SimCommands.spy_answer(es._player, cid, choice)))
			line.add_child(b)
			buttons.append(b)
		es.intel_case_buttons[cid] = buttons
		var grief := UiTheme.dim("Grief : pendant un an, leur déclarer la guerre ne sera pas un parjure.", 12)
		blk.body.add_child(grief)
	return blk


## Opérations possibles chez l'empire choisi, avec leur briefing chiffré ; l'opération en cours.
static func _operations_block(es: EmpireScreens, target: int) -> Control:
	var state := es._state
	var player := es._player
	var oe := state.get_empire(target)
	var blk := Widgets.Block.new("Opérations chez %s" % oe.short_name())
	blk.heading.add_theme_font_size_override("font_size", 22)
	var run := Espionage.running(state, player, target)
	if not run.is_empty():
		var o := Espionage.op_def(String(run["op"]))
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		var l := UiTheme.paragraph("En cours : %s, encore %d jours (succès %d %%, découverte %d %%)." % [
				o["label"], maxi(0, int(run["end"]) - state.tick), int(run["success"]), int(run["discovery"])], 330, 14)
		l.add_theme_color_override("font_color", UiTheme.GOLD)
		line.add_child(l)
		var cancel := Button.new()
		cancel.text = "ANNULER"
		cancel.focus_mode = Control.FOCUS_NONE
		cancel.tooltip_text = "L'influence est perdue, mais plus rien ne peut être découvert."
		cancel.pressed.connect(func() -> void: es.command_requested.emit(SimCommands.spy_cancel(player, target)))
		line.add_child(cancel)
		blk.body.add_child(line)
	var g := GridContainer.new()
	g.columns = 5
	g.add_theme_constant_override("h_separation", 14)
	g.add_theme_constant_override("v_separation", 4)
	blk.body.add_child(g)
	for h in ["Opération", "Coût", "Succès", "Découverte", ""]:
		g.add_child(UiTheme.dim(h, 12))
	for op_id in Espionage.op_ids():
		var o := Espionage.op_def(op_id)
		var name := Label.new()
		name.text = String(o["label"])
		name.tooltip_text = "%s. %s\nPalier requis : %d (%s). Durée : %d jours. Une réussite consomme %d d'infiltration." % [
				Espionage.FAMILY_LABELS.get(String(o["family"]), o["family"]), o["text"], Espionage.tier_at(int(o["tier"])), Espionage.tier_info(int(o["tier"]))["label"], int(o["days"]), int(o.get("spend", 0))]
		name.mouse_filter = Control.MOUSE_FILTER_STOP
		g.add_child(name)
		var cost := Label.new()
		cost.text = GameData.format_amounts(Espionage.op_cost(state, player, op_id))
		g.add_child(cost)
		var ch := Espionage.chances(state, player, target, op_id)
		g.add_child(_pct_label(int(ch["success"]), ch["success_parts"], true))
		g.add_child(_pct_label(int(ch["discovery"]), ch["discovery_parts"], false))
		var b := Button.new()
		b.text = "LANCER"
		b.focus_mode = Control.FOCUS_NONE
		var why := Espionage.check_op(state, player, target, op_id)
		b.disabled = why != ""
		b.tooltip_text = why if why != "" else "Lancer : %s" % o["label"]
		b.pressed.connect(func() -> void: es.command_requested.emit(SimCommands.spy_op(player, target, op_id)))
		g.add_child(b)
		es.intel_op_buttons[op_id] = b
	if Diplomacy.allied(state, player, target):
		var warn := UiTheme.paragraph("C'est un allié : des agents pris chez lui rompraient l'alliance.", 420, 13)
		warn.add_theme_color_override("font_color", UiTheme.WARN)
		blk.body.add_child(warn)
	return blk


static func _pct_label(v: int, parts: Array, good_high: bool) -> Label:
	var l := Label.new()
	l.text = "%d %%" % v
	l.theme_type_variation = &"Numbers"
	var good := v >= 60 if good_high else v <= 25
	var bad := v < 40 if good_high else v >= 50
	l.add_theme_color_override("font_color", UiTheme.GOOD if good else (UiTheme.BAD if bad else UiTheme.TEXT))
	var lines := PackedStringArray()
	for p in parts:
		lines.append("%+d  %s" % [int(p[1]), p[0]])
	l.tooltip_text = "\n".join(lines)
	l.mouse_filter = Control.MOUSE_FILTER_STOP
	return l
