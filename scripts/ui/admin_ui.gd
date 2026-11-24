class_name AdminUi
extends RefCounted
## Onglet « Administration » de l'écran Ordre intérieur (F12 ; voir Admin, étude « Administration et
## corruption », prop. 31). Colonne de gauche : jauge charge contre capacité, effets du dépassement,
## corruption moyenne, talents du peuple. Contenu : effort administratif, détail de la charge et de la
## capacité, provinces, systèmes du plus corrompu au moins corrompu (détail en infobulle, bouton
## Intégrer pour les conquêtes), transfert de capitale. Lit l'état, n'émet que des ordres admin_*.

const W := 760.0
const INK := Color(0.78, 0.66, 0.42)


## Jauge charge contre capacité, en tête de l'écran (refonte, C5).
class Gauge:
	extends Control
	var charge := 0
	var cap := 1
	var step_pct := 25

	func _init() -> void:
		custom_minimum_size = Vector2(AdminUi.W, 46)

	## Part de la barre remplie (la capacité est au milieu ; le double de la capacité remplit tout).
	func fill_ratio() -> float:
		return clampf(float(charge) / float(maxi(1, cap) * 2), 0.0, 1.0)

	func _draw() -> void:
		var w := size.x
		var bar := Rect2(0, 18, w, 12)
		draw_rect(bar, Color(1, 1, 1, 0.07))
		draw_rect(Rect2(bar.position, Vector2(w * fill_ratio(), bar.size.y)), AdminUi.gauge_color(charge, cap))
		var f := UiTheme.caps_font()
		# Tranches de dépassement, à droite de la capacité.
		var k := 1
		while k * step_pct < 100:
			var x := w * (0.5 + 0.5 * float(k * step_pct) / 100.0)
			draw_line(Vector2(x, 18), Vector2(x, 30), Color(0, 0, 0, 0.45), 1.0)
			draw_string(f, Vector2(x - 14, 44), "+%d %%" % (k * step_pct), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UiTheme.TEXT_DIM)
			k += 1
		draw_line(Vector2(w * 0.5, 12), Vector2(w * 0.5, 34), UiTheme.TEXT, 2.0)
		draw_string(f, Vector2(w * 0.5 - 60, 10), "CAPACITÉ %d" % cap, HORIZONTAL_ALIGNMENT_CENTER, 120, 11, UiTheme.TEXT)
		draw_string(f, Vector2(0, 10), "CHARGE %d" % charge, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, AdminUi.gauge_color(charge, cap))


static func _gauge_block(state: GameState, player: int) -> Control:
	var b := Widgets.Block.new("Charge et capacité")
	var gz := Gauge.new()
	gz.charge = Admin.load_of(state, player)
	gz.cap = Admin.capacity(state, player)
	gz.step_pct = maxi(5, Admin.d_int("over", "step_pct"))
	gz.tooltip_text = "Le trait du milieu est la capacité : au-delà, chaque tranche de %d %% coûte de la stabilité, du Savoir et de l'influence." % Admin.d_int("over", "step_pct")
	b.body.add_child(gz)
	var over := Admin.over_pct(state, player)
	var line := "Les bureaux tiennent la charge : il reste %d de marge." % (gz.cap - gz.charge) if over <= 0 else \
			("La charge dépasse la capacité de %d %%, soit %d tranche%s de pénalité." % [over, Admin.steps(state, player), "s" if Admin.steps(state, player) > 1 else ""] if Admin.steps(state, player) > 0 \
			else "La charge dépasse la capacité de %d %% : pas encore de pénalité, la première tranche tombe à +%d %%." % [over, Admin.d_int("over", "step_pct")])
	var lp := UiTheme.paragraph(line, W, 13)
	lp.add_theme_color_override("font_color", gauge_color(gz.charge, gz.cap) if over > 0 else UiTheme.TEXT_DIM)
	b.body.add_child(lp)
	return b


static func build(es: EmpireScreens) -> void:
	var state := es._state
	var player := es._player
	var g := es._grid()
	es._side_box.add_child(g)
	var load := Admin.load_of(state, player)
	var cap := Admin.capacity(state, player)
	var over := Admin.over_pct(state, player)
	var gl := es._key_value(g, "Charge / capacité", "%d / %d" % [load, cap])
	gl.add_theme_color_override("font_color", gauge_color(load, cap))
	var g2 := es._grid()
	es._side_box.add_child(g2)
	var n := Admin.steps(state, player)
	if over > 0:
		es._key_value(g2, "Dépassement", "+%d %% (%d tranche%s)" % [over, n, "s" if n > 1 else ""])
		es._key_value(g2, "Stabilité", "%d partout" % maxi(Admin.d_int("over", "stability_max"), n * Admin.d_int("over", "stability")))
		es._key_value(g2, "Recherche", "+%d %% de coût" % Admin.research_pct(state, player))
		es._key_value(g2, "Influence", "+%d %% de coût" % Admin.influence_pct(state, player))
		if Admin.has_corruption(state, player):
			es._key_value(g2, "Corruption", "+%d partout" % (n * Admin.d_int("over", "corruption")))
	else:
		es._key_value(g2, "Dépassement", "aucun")
	if Admin.has_corruption(state, player):
		var al := es._key_value(g2, "Corruption moyenne", "%d %%" % Admin.average_corruption(state, player))
		al.add_theme_color_override("font_color", corruption_color(Admin.average_corruption(state, player)))
	var upk := Admin.upkeep(state, player)
	es._key_value(g2, "Fonctionnaires", ("%d énergie / mois" % int(upk.get("energy", 0))) if not upk.is_empty() else "gratuits")
	if Admin.in_transition(state, player):
		es._key_value(g2, "Capitale", "en transfert jusqu'au %s" % GameCalendar.date_string(int(Admin.entry(state, player).get("trans", 0))))
	var gend := AdminBridges.grievance_end(state, player)
	if gend > state.tick:
		es._side_box.add_child(UiTheme.paragraph("Doléance « Assainir l'administration » : ramenez la corruption moyenne sous %d %% avant le %s." % [
				Admin.d_int("politics", "grievance_from") - 5, GameCalendar.date_string(gend)], EmpireScreens.SIDE_WIDTH - 24.0, 12))
	var cy := AdminBridges.clean_years(state, player)
	if cy > 0:
		es._key_value(g2, "Mains propres", "%d an%s" % [cy, "s" if cy > 1 else ""])
	var talents := Admin.talent_labels(state, player)
	if not talents.is_empty():
		es._side_box.add_child(HSeparator.new())
		es._side_box.add_child(UiTheme.dim("Talents de votre peuple", 13))
		for tl in talents:
			es._side_box.add_child(UiTheme.paragraph("%s : %s" % [tl[0], tl[1]], EmpireScreens.SIDE_WIDTH - 24.0, 12))
	es._side_box.add_child(HSeparator.new())
	es._side_box.add_child(UiTheme.paragraph("Tout ce que l'empire possède pèse sur ses bureaux. La corruption de chaque système détourne une part de son énergie, de ses matériaux, de son influence et de son Savoir (jamais la nourriture).", EmpireScreens.SIDE_WIDTH - 24.0, 12))

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	es._content.add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 18)
	scroll.add_child(col)
	col.add_child(_gauge_block(state, player))
	col.add_child(_effort_block(es))
	col.add_child(_breakdown_block(state, player))
	if Admin.full(state):
		col.add_child(_systems_block(es))
		var cb := _capital_block(es)
		if cb != null:
			col.add_child(cb)


static func gauge_color(load: int, cap: int) -> Color:
	if load <= cap:
		return Color(0.42, 0.75, 0.55)
	if load * 100 <= cap * 130:
		return Color(0.88, 0.57, 0.23)
	return Color(0.85, 0.33, 0.31)


static func corruption_color(v: int) -> Color:
	if v < 10:
		return Color(0.66, 0.71, 0.76)
	if v < 20:
		return Color(0.86, 0.76, 0.36)
	if v < 30:
		return Color(0.88, 0.57, 0.23)
	return Color(0.85, 0.33, 0.31)


static func _effort_block(es: EmpireScreens) -> Control:
	var state := es._state
	var player := es._player
	var b := Widgets.Block.new("Effort administratif")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	b.body.add_child(row)
	var cur := Admin.effort(state, player)
	for d: Dictionary in Admin.effort_defs():
		var id := String(d["id"])
		var bt := Button.new()
		bt.text = String(d["label"])
		bt.toggle_mode = true
		bt.button_pressed = id == cur
		bt.focus_mode = Control.FOCUS_NONE
		bt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var why := Admin.check_effort(state, player, id) if id != cur else ""
		bt.disabled = OrderScreen._ro(es) or (why != "" and id != cur)
		bt.tooltip_text = String(d["text"]) + (("\n" + why) if why != "" else "")
		bt.pressed.connect(func() -> void: es.command_requested.emit(SimCommands.admin_effort(player, id)))
		row.add_child(bt)
		es.order_buttons["effort:" + id] = bt
	b.body.add_child(UiTheme.paragraph(String(Admin.effort_def(cur).get("text", "")), W, 13))
	return b


static func _breakdown_block(state: GameState, player: int) -> Control:
	var b := Widgets.Block.new("Détail de la charge et de la capacité")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 40)
	b.body.add_child(row)
	for side in [["Charge", Admin.entry(state, player).get("lp", [])], ["Capacité", Admin.entry(state, player).get("cp", [])]]:
		var c := VBoxContainer.new()
		c.custom_minimum_size = Vector2(340, 0)
		row.add_child(c)
		c.add_child(UiTheme.dim(String(side[0]), 14))
		for p in (side[1] as Array):
			var l := Label.new()
			var v := int(p[1])
			l.text = "%+d   %s" % [v, String(p[0])] if String(side[0]) == "Capacité" and v < 0 else "%d   %s" % [v, String(p[0])]
			l.add_theme_font_size_override("font_size", 13)
			c.add_child(l)
		if (side[1] as Array).is_empty():
			c.add_child(UiTheme.dim("rien", 13))
	return b


## Systèmes de l'empire, du plus corrompu au moins corrompu, avec leur siège.
static func _systems_block(es: EmpireScreens) -> Control:
	var state := es._state
	var player := es._player
	var b := Widgets.Block.new("Vos systèmes, du plus corrompu au moins corrompu" if Admin.has_corruption(state, player) else "Vos systèmes")
	var list := []
	for k in (state.admin["sys"] as Dictionary).keys():
		if int(state.admin["sys"][k]) == player:
			list.append([-Admin.corruption(state, int(k)), int(k)])
	list.sort()
	if list.is_empty():
		b.body.add_child(UiTheme.dim("Aucun système.", 14))
	for it in list:
		b.body.add_child(_system_row(es, int(it[1])))
	return b


static func _system_row(es: EmpireScreens, sid: int) -> Control:
	var state := es._state
	var player := es._player
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var name_b := Button.new()
	name_b.flat = true
	name_b.text = state.galaxy.systems[sid].system_name
	name_b.custom_minimum_size = Vector2(170, 0)
	name_b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_b.clip_text = true
	name_b.add_theme_font_size_override("font_size", 15)
	name_b.tooltip_text = "Ouvrir le système"
	var first := es._first_claim(sid)
	name_b.pressed.connect(func() -> void: es.planet_requested.emit(first))
	row.add_child(name_b)
	if Admin.has_corruption(state, player):
		var cor := Admin.corruption(state, sid)
		var cl := Label.new()
		cl.text = "%d %%" % cor
		cl.custom_minimum_size = Vector2(60, 0)
		cl.add_theme_color_override("font_color", corruption_color(cor))
		cl.add_theme_font_size_override("font_size", 14)
		cl.mouse_filter = Control.MOUSE_FILTER_STOP
		cl.tooltip_text = corruption_tip(state, player, sid)
		row.add_child(cl)
	var seat := Admin.seat_of(state, sid)
	var sl := Label.new()
	sl.custom_minimum_size = Vector2(200, 0)
	sl.add_theme_font_size_override("font_size", 13)
	sl.add_theme_color_override("font_color", UiTheme.TEXT_DIM if seat >= 0 else Color(0.85, 0.33, 0.31))
	sl.text = ("siège : " + state.galaxy.systems[seat].system_name) if seat >= 0 and seat != sid else ("siège" if seat == sid else "enclave")
	row.add_child(sl)
	if not Admin.is_integrated(state, sid):
		var end := Admin.integrating(state, sid)
		if end > state.tick:
			var il := Label.new()
			il.text = "intégration : %d j" % (end - state.tick)
			il.add_theme_color_override("font_color", UiTheme.GOLD)
			il.add_theme_font_size_override("font_size", 13)
			row.add_child(il)
		elif not OrderScreen._ro(es):
			var why := Admin.check_integrate(state, player, sid)
			var bt := Button.new()
			bt.focus_mode = Control.FOCUS_NONE
			bt.add_theme_font_size_override("font_size", 12)
			bt.text = "Intégrer (%s)" % GameData.format_amounts(Admin.integrate_cost(state, player, sid))
			bt.disabled = why != ""
			bt.tooltip_text = why if why != "" else "Non intégré : production -%d %%, aucun décret, aucune charge. L'intégration prend %d jours." % [
					Admin.d_int("integration", "prod_pct"), Admin.d_int("integration", "days")]
			bt.pressed.connect(func() -> void: es.command_requested.emit(SimCommands.admin_integrate(player, sid)))
			row.add_child(bt)
			es.order_buttons["integrate:%d" % sid] = bt
	return row


static func corruption_tip(state: GameState, player: int, sid: int) -> String:
	var r: Array = Admin.corruption_parts(state, player, sid)
	var lines := PackedStringArray(["Corruption %d %% (détourne cette part de l'énergie, des matériaux, de l'influence et du Savoir) :" % int(r[0])])
	for p in (r[1] as Array):
		lines.append("  %+d  %s" % [int(p[1]), String(p[0])])
	return "\n".join(lines)


## Transfert de capitale : les colonies assez peuplées, avec le coût et la raison d'un refus.
static func _capital_block(es: EmpireScreens) -> Control:
	var state := es._state
	var player := es._player
	var e := state.get_empire(player)
	if e == null or OrderScreen._ro(es):
		return null
	var cm: Dictionary = Admin.data()["capital_move"]
	var cands := []
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner == player and c.is_colony() and pid != e.capital_planet and c.population >= int(cm["min_pop"]):
			cands.append([-c.population, pid])
	cands.sort()
	var b := Widgets.Block.new("Déplacer la capitale")
	b.body.add_child(UiTheme.paragraph("Coût %s, %d mois de transition (stabilité %d partout), puis %d ans avant un nouveau transfert. Seulement vers une colonie d'au moins %d habitants." % [
			GameData.format_amounts(cm["cost"]), int(cm["transition_days"]) / 30, int(cm["stability"]), int(cm["cooldown_days"]) / 360, int(cm["min_pop"])], W, 13))
	if cands.is_empty():
		b.body.add_child(UiTheme.dim("Aucune colonie assez peuplée.", 13))
	for it in cands.slice(0, 5):
		var pid := int(it[1])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var l := Label.new()
		l.text = "%s (%d habitants)" % [state.galaxy.get_planet(pid).display_name(state.galaxy), -int(it[0])]
		l.custom_minimum_size = Vector2(300, 0)
		row.add_child(l)
		var why := Admin.check_move_capital(state, player, pid)
		var bt := Button.new()
		bt.focus_mode = Control.FOCUS_NONE
		bt.text = "Y installer la capitale"
		bt.disabled = why != ""
		bt.tooltip_text = why if why != "" else "Les archives partent en convoi."
		bt.pressed.connect(func() -> void: es.command_requested.emit(SimCommands.admin_capital(player, pid)))
		row.add_child(bt)
		es.order_buttons["capital:%d" % pid] = bt
		b.body.add_child(row)
	return b


static func signature(es: EmpireScreens) -> String:
	var state := es._state
	var e := state.get_empire(es._player)
	@warning_ignore("integer_division")
	return "%d|%s|%s|%s|%s|%d|%d" % [state.tick / 30, str(Admin.entry(state, es._player)), str(state.admin.get("ni", {})), str(state.admin.get("integ", {})),
			str(state.admin.get("cor", {})), e.resources.get("influence", 0) / 10 if e else 0, e.resources.get("materials", 0) / 50 if e else 0]
