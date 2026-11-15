class_name BordersUi
extends RefCounted
## Écran Diplomatie : frontières et droit de passage (voir Borders). Dans la relation avec un empire :
## ce que ses flottes peuvent faire chez vous et les vôtres chez lui, votre politique (Ouverte, Gardée,
## Close), ses flottes en intrusion chez vous. Colonne de gauche : talents de frontière, intrusions.
## Construit par EmpireScreens ; chaque ordre passe par emit (SimCommands.border_act). buttons reçoit
## les boutons (pour les tests).


static func _btn(text: String, why: String, tip: String, on_press: Callable, primary := false) -> Button:
	return VassalUi._btn(text, why, tip, on_press, primary)


## Bloc ajouté à la relation avec l'empire id.
static func relation(state: GameState, player: int, id: int, emit: Callable, buttons: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var e := state.get_empire(id)
	if not Borders.active(state) or e == null or e.eliminated or e.is_npc() or player == id:
		return box
	var me := state.get_empire(player)
	if me == null or not me.contacts.has(id):
		return box
	box.add_child(UiTheme.section("Frontières"))
	var l1 := UiTheme.dim("Chez vous, ses flottes : %s" % Borders.access_text(state, player, id), 13)
	l1.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l1.custom_minimum_size = Vector2(480, 0)
	box.add_child(l1)
	var l2 := UiTheme.dim("Chez lui, vos flottes : %s" % Borders.access_text(state, id, player), 13)
	l2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l2.custom_minimum_size = Vector2(480, 0)
	box.add_child(l2)
	buttons["access"] = l2
	var row := VassalUi._flow()
	box.add_child(row)
	var cur := Borders.policy(state, player, id)
	for p in Borders.POLICIES:
		var pol: String = p
		var lab := Borders.policy_label(pol).to_upper()
		var b := _btn(("● " if pol == cur else "") + lab, Borders.check_policy(state, player, id, pol) if pol != cur else "",
				Borders.policy_text(pol), func() -> void: emit.call(SimCommands.border_act(player, "policy", id, -1, pol)), pol == cur)
		if pol == cur:
			b.disabled = true
			b.tooltip_text = "Votre politique actuelle. " + Borders.policy_text(pol)
		row.add_child(b)
		buttons["policy_" + pol] = b
	var intr := Borders.intruders(state, player, id)
	if not intr.is_empty():
		var names := PackedStringArray()
		for fid in intr:
			var f: Fleet = state.fleets.get(fid)
			if f != null and Borders._sees(state, player, f):
				names.append("%s (%s)" % [f.fleet_name, state.galaxy.systems[f.system_id].system_name])
		if not names.is_empty():
			var w := UiTheme.dim("En intrusion chez vous : %s" % ", ".join(names), 13)
			w.add_theme_color_override("font_color", UiTheme.BAD)
			w.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			w.custom_minimum_size = Vector2(480, 0)
			box.add_child(w)
			buttons["intruders"] = w
	_relation_lot2(state, player, id, emit, buttons, box)
	return box


static func _line(box: Control, text: String, color: Color, buttons: Dictionary, key: String) -> void:
	var w := UiTheme.dim(text, 13)
	w.add_theme_color_override("font_color", color)
	w.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	w.custom_minimum_size = Vector2(480, 0)
	box.add_child(w)
	buttons[key] = w


## Sommations, motif « Violation de frontière », péage, laissez-passer, Arbitre (lot 2).
static func _relation_lot2(state: GameState, player: int, id: int, emit: Callable, buttons: Dictionary, box: Control) -> void:
	var e := state.get_empire(id)
	var end_me := Borders.summons_end(state, player, id)
	if end_me > 0:
		_line(box, "Vous l'avez sommé de partir : encore %d j avant le motif de guerre." % (end_me - state.tick), UiTheme.WARN, buttons, "summons_sent")
	var end_him := Borders.summons_end(state, id, player)
	if end_him > 0:
		_line(box, "Il vous somme de retirer vos flottes de son espace : encore %d j. Passé ce délai, il tiendra un motif de guerre et ses patrouilles tireront." % (end_him - state.tick),
				UiTheme.BAD, buttons, "summons_received")
	var ign: Dictionary = state.borders.get("ign", {})
	if Borders.has_cb(state, player, id):
		_line(box, "Sommation ignorée : motif de guerre « Violation de frontière » encore %d j ; vos flottes ripostent contre ses intrus tant que vous êtes en guerre froide." % (int(ign["%d>%d" % [player, id]]) - state.tick),
				UiTheme.GOOD, buttons, "cb")
	if Borders.has_cb(state, id, player):
		_line(box, "Vous avez ignoré sa sommation : il tient contre vous un motif « Violation de frontière » (encore %d j), et ses flottes attaquent les vôtres chez lui." % (int(ign["%d>%d" % [id, player]]) - state.tick),
				UiTheme.BAD, buttons, "cb_against")
	if Borders.toll_of(state, id) > 0:
		box.add_child(UiTheme.dim("Péage chez lui : %d énergie par saut pour vos flottes de guerre de passage." % Borders.toll_of(state, id), 13))
	var row := VassalUi._flow()
	box.add_child(row)
	if not Borders.seen_intruders(state, player, id).is_empty() or end_me > 0:
		var why := Borders.check_summons(state, player, id)
		var b := _btn("SOMMER DE PARTIR", why, "Ses flottes en intrusion ont %d jours pour quitter votre espace. Ignorée, la sommation lui coûte votre opinion et vous donne un motif de guerre, « Violation de frontière », pendant cinq ans ; en guerre froide, vos flottes pourront attaquer ses intrus chez vous." % Borders.summons_days(state, player, id),
				func() -> void: emit.call(SimCommands.border_act(player, "summons", id)))
		row.add_child(b)
		buttons["summons"] = b
	# Laissez-passer pour une de vos flottes.
	var cands: Array[Fleet] = []
	for f in Fleets.empire_fleets(state, player):
		if Borders.check_pass(state, player, f.id, id) == "":
			cands.append(f)
	if not cands.is_empty():
		var pick := OptionButton.new()
		pick.clip_text = true
		pick.custom_minimum_size = Vector2(180, 0)
		for f in cands:
			pick.add_item(f.fleet_name)
			pick.set_item_metadata(pick.item_count - 1, f.id)
		row.add_child(pick)
		var cost := int(Borders.pass_cost(state, player).get("influence", 0))
		var pb := _btn("LAISSEZ-PASSER" + (" (%d Inf)" % cost if cost > 0 else ""), "",
				"Demander le passage de cette flotte chez %s pendant %d jours. %s" % [e.short_name(), int(Borders.data()["pass"]["days"]),
				"Une IA répond aussitôt, selon son opinion et la taille de la flotte." if e.is_ai() else "Il a %d jours pour répondre." % Borders.answer_days()],
				func() -> void: emit.call(SimCommands.border_act(player, "pass", int(pick.get_item_metadata(pick.selected)), id)))
		row.add_child(pb)
		buttons["pass"] = pb
	# L'Arbitre des étoiles impose le libre-passage entre cet empire et un autre amphictyon.
	if state.amph_on and AmphInst.arbiter(state) == player and Amphictyony.is_member(state, id):
		var others: Array[int] = []
		for m in Amphictyony.members(state):
			if m != id and Borders.check_arbiter(state, player, id, m) == "":
				others.append(m)
		if not others.is_empty():
			var ap := OptionButton.new()
			ap.clip_text = true
			ap.custom_minimum_size = Vector2(160, 0)
			for m in others:
				ap.add_item(state.get_empire(m).short_name())
				ap.set_item_metadata(ap.item_count - 1, m)
			row.add_child(ap)
			var ab := _btn("IMPOSER LE LIBRE-PASSAGE (%d Inf)" % int(Borders.data()["arbiter"]["cost"]["influence"]), "",
					"En Arbitre des étoiles : libre-passage forcé entre ces deux amphictyons pendant cinq ans.",
					func() -> void: emit.call(SimCommands.border_act(player, "arbiter", id, int(ap.get_item_metadata(ap.selected)))))
			row.add_child(ab)
			buttons["arbiter"] = ab


## Colonne de gauche : mode des frontières, talents, intrusions chez le joueur.
static func side(state: GameState, player: int, width: float, emit := Callable(), buttons := {}) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	if not Borders.active(state):
		return box
	box.add_child(HSeparator.new())
	box.add_child(UiTheme.section("Frontières %s" % ("strictes" if Borders.strict(state) else "souples")))
	for x in Borders.talent_labels(state, player):
		box.add_child(UiTheme.paragraph("%s : %s" % [String(x[0]), String(x[1])], width, 12))
	# Péage : énergie par saut des flottes de guerre étrangères qui traversent vos systèmes avec un droit de passage.
	if emit.is_valid():
		box.add_child(UiTheme.paragraph("Péage par saut (flottes de guerre étrangères de passage) :", width, 12))
		var row := VassalUi._flow()
		box.add_child(row)
		var cur := Borders.toll_level(state, player)
		var steps := Borders.toll_steps()
		for i in steps.size():
			var lvl := i
			var b := _btn(("● " if lvl == cur else "") + str(int(steps[lvl])), "", "Péage de %d énergie par saut. Les alliés, sujets et membres de votre Koinon ne paient pas." % int(steps[lvl]),
					func() -> void: emit.call(SimCommands.border_act(player, "toll", lvl)), lvl == cur)
			b.disabled = lvl == cur
			row.add_child(b)
			buttons["toll_%d" % lvl] = b
	var list := Borders.intrusions_in(state, player)
	if list.is_empty():
		box.add_child(UiTheme.paragraph("Aucune flotte étrangère en intrusion chez vous.", width, 12))
		return box
	for it in list:
		var f: Fleet = state.fleets.get(int(it[0]))
		if f == null:
			continue
		box.add_child(UiTheme.paragraph("Intrusion : %s de %s à %s." % [f.fleet_name, state.get_empire(int(it[1])).short_name(),
				state.galaxy.systems[f.system_id].system_name], width, 12))
	return box
