class_name TranscendenceScreen
extends RefCounted
## Écran Transcendance (voir Transcendence, prop. 39) : un onglet de l'écran Victoire. La voie, la jauge
## d'Élévation et son détail, les trois étapes de l'Exodium, le Passage (Relais, Lieux minces, empires
## joints), et les Passages en cours dans la galaxie. Construit dans les conteneurs d'EmpireScreens.

const COLOR := Color(0.85, 0.8, 1.0)


## Onglets « Victoires | Transcendance | Contact » en tête de ces écrans (selon les piliers en jeu).
static func tabs(es: EmpireScreens, active: String) -> void:
	var list := [["victory", "Victoires"]]
	if Transcendence.enabled(es._state):
		list.append(["transcendence", "Transcendance"])
	if Contact.enabled(es._state):
		list.append(["contact", "Contact"])
	if list.size() < 2:
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for t in list:
		var b := Button.new()
		b.text = String(t[1])
		b.toggle_mode = true
		b.button_pressed = String(t[0]) == active
		b.focus_mode = Control.FOCUS_NONE
		var sid := String(t[0])
		b.pressed.connect(func() -> void: es.show_screen(sid))
		es.transcendence_buttons["tab:" + sid] = b
		es.contact_buttons["tab:" + sid] = b
		row.add_child(b)
	es._side_box.add_child(row)


static func build(es: EmpireScreens) -> void:
	var state := es._state
	var player := es._player
	es._transcendence_sig = signature(es)
	es._side_header("screen_transcendence", "Transcendance", COLOR, "faction")
	tabs(es, "transcendence")
	var w := EmpireScreens.SIDE_WIDTH - 24.0
	if not Transcendence.applies(state, player):
		es._side_box.add_child(UiTheme.paragraph("Dans cette partie, la Transcendance n'est pas en jeu (Nouvelle partie : Transcendance).", w, 13))
		return
	var g := es._grid()
	es._side_box.add_child(g)
	es._key_value(g, "Réglage", "%s, issue %s" % [Transcendence.mode_label(state), Transcendence.outcome_label(state).to_lower()])
	var pid := Transcendence.path_of(state, player)
	var host := Transcendence.host_of(state, player)
	es._key_value(g, "Voie", Transcendence.path_label(pid) if pid != "" else ("jointe à %s" % state.get_empire(host).short_name() if host >= 0 else "aucune"))
	if pid != "":
		es._key_value(g, "Jauge d'Élévation", "%d %% (+%s par mois)" % [Transcendence.gauge_pct(state, player), _tenths(Transcendence.monthly_gain(state, player))])
	var t := Transcendence.talent(state, player)
	if t.has("label"):
		es._side_box.add_child(HSeparator.new())
		es._side_box.add_child(UiTheme.dim("Talent de votre peuple", 13))
		es._side_box.add_child(UiTheme.paragraph("%s : %s" % [String(t["label"]), String(t.get("text", ""))], w, 12))
	es._side_box.add_child(HSeparator.new())
	if Transcendence.renounced(state, player):
		es._side_box.add_child(UiTheme.paragraph("Votre peuple a renoncé à l'Orée. Il ne la franchira plus.", w, 13))
	elif pid == "" and host < 0:
		es._side_box.add_child(UiTheme.dim("Se vouer à une voie", 13))
		for p: Dictionary in Transcendence.path_defs():
			var id := String(p["id"])
			es._side_box.add_child(_btn(es, String(p["label"]), Transcendence.check(state, player, "path", {"path": id}), String(p.get("text", "")),
					SimCommands.tr_act(player, "path", {"path": id}), "path:" + id))
		for other in state.empires:
			if other.id != player and Transcendence.in_passage(state, other.id) and (Diplomacy.allied(state, player, other.id) or Koinon.same_league(state, player, other.id)):
				es._side_box.add_child(_btn(es, "Rejoindre le Passage de %s" % other.short_name(), Transcendence.check(state, player, "join", {"host": other.id}),
						"Partir (ou gagner) avec lui : il vous faut un Relais du Passage chez vous ; son Passage dure un an de plus.",
						SimCommands.tr_act(player, "join", {"host": other.id}), "join:%d" % other.id))
	elif pid != "":
		var od := Transcendence.oeuvre_def(pid)
		var why := Transcendence.check(state, player, "oeuvre", {})
		if Transcendence.stage(state, player) < Transcendence.stage_count(pid) and not Transcendence.stage_running(state, player) and not Transcendence.in_passage(state, player):
			var cost := Transcendence.stage_cost(state, player)
			es._side_box.add_child(_btn(es, "Bâtir %s, étape %d (%s)" % [String(od.get("label", "l'Exodium")), Transcendence.stage(state, player) + 1, GameData.format_amounts(cost)], why,
					String(od.get("text", "")), SimCommands.tr_act(player, "oeuvre", {}), "oeuvre"))
		es._side_box.add_child(_btn(es, "Renoncer à l'Orée", Transcendence.check(state, player, "renounce", {}),
				"La jauge est perdue, cinq ans de crise de stabilité, les Restants au pouvoir ; plus jamais l'Orée.",
				SimCommands.tr_act(player, "renounce", {}), "renounce"))
	for x in TranscendenceUiExtra.side(es):
		es._side_box.add_child(x)
	es._side_box.add_child(HSeparator.new())
	es._side_box.add_child(UiTheme.paragraph("Trois étapes : franchir l'Orée et remplir la jauge, bâtir l'Exodium de sa voie, puis tenir le Passage. Le Passage recule d'un an par mois d'occupation du système de l'Exodium ; six mois, et l'Exodium est détruit. Des Relais (2 mois chacun) et des Lieux minces (3 mois) le raccourcissent, jamais sous deux ans.", w, 12))

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	es._content.add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 18)
	scroll.add_child(col)

	if pid != "":
		var gb := Widgets.Block.new("Jauge d'Élévation : %d %%" % Transcendence.gauge_pct(state, player))
		col.add_child(gb)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(500, 10)
		bar.max_value = Transcendence.gauge_max()
		bar.value = Transcendence.gauge(state, player)
		gb.body.add_child(bar)
		for x in Transcendence.gain_parts(state, player):
			gb.body.add_child(UiTheme.paragraph("%s : %+s par mois" % [x[0], _tenths(int(x[1]))], 760.0, 13))
		if TranscendenceWorld.frozen(state, player):
			gb.body.add_child(UiTheme.paragraph("Gelée : les Restants bloquent la jauge.", 760.0, 13))
		var ob := Widgets.Block.new(String(Transcendence.oeuvre_label(pid)).capitalize())
		col.add_child(ob)
		var n := Transcendence.stage_count(pid)
		for i in n:
			var sd := Transcendence.stage_def(pid, i)
			var st := "achevée" if i < Transcendence.stage(state, player) else ("en chantier jusqu'au %s" % GameCalendar.date_string(int(Transcendence.oeuvre(state, player)["until"])) if i == Transcendence.stage(state, player) and Transcendence.stage_running(state, player) else "à bâtir")
			ob.body.add_child(UiTheme.paragraph("Étape %d (%s, %d jours) : %s" % [i + 1, GameData.format_amounts(sd.get("cost", {})), int(sd.get("days", 0)), st], 760.0, 13))
		var sys := Transcendence.oeuvre_sys(state, player)
		if sys >= 0:
			ob.body.add_child(UiTheme.dim("Site : %s" % state.galaxy.systems[sys].system_name, 13))
		var pb := Widgets.Block.new("Le Passage")
		col.add_child(pb)
		var p := cfg_passage()
		pb.body.add_child(UiTheme.paragraph("Durée : %s (Relais : %d, Lieux minces tenus : %d, empires joints : %d)" % [Victory._days_text(Transcendence.passage_need(state, player)),
				Transcendence.relays(state, player), TranscendenceWorld.minces_held(state, player), Transcendence.joined_to(state, player).size()], 760.0, 13))
		if Transcendence.in_passage(state, player):
			var a := Transcendence.ark(state, player)
			if not a.is_empty():
				pb.body.add_child(UiTheme.paragraph("L'Arche fait route vers la Bordure : %s. Amenez-la jusque-là et arrêtez-la." % state.galaxy.systems[int(a["target"])].system_name, 760.0, 13))
			else:
				pb.body.add_child(UiTheme.paragraph("En cours : %d %% (%s restants)%s" % [Transcendence.passage_pct(state, player), Victory._days_text(maxi(0, Transcendence.passage_need(state, player) - Transcendence.passage_prog(state, player))),
						", Exodium occupé depuis %d mois" % int(Transcendence.passage(state, player).get("occ", 0)) if int(Transcendence.passage(state, player).get("occ", 0)) > 0 else ""], 760.0, 13))
		else:
			pb.body.add_child(UiTheme.dim("Il commence quand l'Exodium est achevé. Plancher : %s." % Victory._days_text(int(p.get("min_days", 720))), 13))

	# Les voies.
	var vb := Widgets.Block.new("Les cinq voies")
	col.add_child(vb)
	for p: Dictionary in Transcendence.path_defs():
		var why := Transcendence.path_why(state, player, String(p["id"]))
		vb.body.add_child(UiTheme.paragraph("%s : %s%s" % [String(p["label"]), String(p.get("text", "")), "" if why == "" else " (fermée : %s)" % why], 760.0, 12))

	# Passages dans la galaxie.
	var lb := Widgets.Block.new("Dans la galaxie")
	col.add_child(lb)
	var me := state.get_empire(player)
	var any := false
	for e in state.empires:
		if e.id == player or e.eliminated or not (es.see_all or me.contacts.has(e.id)):
			continue
		var opid := Transcendence.path_of(state, e.id)
		if opid == "":
			continue
		var pct := Victory.visible_pct(state, -1 if es.see_all else player, e.id, "transcendance")
		any = true
		var line := "%s : %s" % [e.short_name(), Transcendence.path_label(opid)]
		if pct < 0:
			line += ", jauge cachée"
		else:
			line += ", %s" % " ; ".join(PackedStringArray(Victory.progress(state, e.id, "transcendance")["lines"]).slice(1))
		lb.body.add_child(UiTheme.paragraph(line, 760.0, 13))
	for e in state.empires:
		if Transcendence.done(state, e.id):
			any = true
			lb.body.add_child(UiTheme.paragraph("%s : transcendé le %s" % [e.short_name(), GameCalendar.date_string(int(Transcendence.sub(state, "done")[str(e.id)]))], 760.0, 13))
	if not any:
		lb.body.add_child(UiTheme.dim("Aucun empire connu ne s'est voué à une voie.", 13))
	TranscendenceUiExtra.content(es, col)


static func cfg_passage() -> Dictionary:
	return Transcendence.cfg("passage")


static func _tenths(n: int) -> String:
	@warning_ignore("integer_division")
	return "%d,%d %%" % [n / 10, absi(n) % 10] if n % 10 != 0 else "%d %%" % (n / 10)


static func _btn(es: EmpireScreens, text: String, why: String, tip: String, command: Dictionary, key: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.disabled = why != ""
	b.clip_text = true
	b.custom_minimum_size = Vector2(EmpireScreens.SIDE_WIDTH - 24.0, 0)
	b.tooltip_text = tip + ("\n\nImpossible : %s." % why if why != "" else "")
	b.pressed.connect(func() -> void: es.command_requested.emit(command))
	es.transcendence_buttons[key] = b
	return b


static func signature(es: EmpireScreens) -> String:
	var state := es._state
	if not Transcendence.applies(state, es._player):
		return "off"
	var e := state.get_empire(es._player)
	@warning_ignore("integer_division")
	return "%d|%d|%s|%s|%s|%d|%d|%s" % [e.techs.size(), state.tick / 30, str(state.transcendence.get("path", {})), str(state.transcendence.get("oeuvre", {})),
			str(state.transcendence.get("joined", {})), Transcendence.gauge(state, es._player) / 10, e.contacts.size(), str(state.transcendence.get("done", {}))]
