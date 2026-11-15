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
	return box


## Colonne de gauche : mode des frontières, talents, intrusions chez le joueur.
static func side(state: GameState, player: int, width: float) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	if not Borders.active(state):
		return box
	box.add_child(HSeparator.new())
	box.add_child(UiTheme.section("Frontières %s" % ("strictes" if Borders.strict(state) else "souples")))
	for x in Borders.talent_labels(state, player):
		box.add_child(UiTheme.paragraph("%s : %s" % [String(x[0]), String(x[1])], width, 12))
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
