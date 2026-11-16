class_name FinanceUi
extends RefCounted
## Onglet « Trésor » de l'écran Ordre intérieur (F12 ; voir Finance, étude « Fiscalité et dette
## publique », prop. 8 et 33). Colonne de gauche : trésor, solde du mois, dette et plafond, cote,
## inflation, crise de la dette, doléances, talents du peuple. Contenu : cran d'impôt, budget poste par
## poste avec projection, emprunts en cours (rembourser, répudier), lever un emprunt, prêter, solde des
## équipages et impôt de guerre, traitements des fonctionnaires (effort administratif), planche à
## billets, franchises fiscales, cotes des empires connus. Lit l'état, n'émet que des ordres finance_*
## (et admin_effort).

const W := 760.0
const INK := Color(0.86, 0.74, 0.36)


static func build(es: EmpireScreens) -> void:
	var state := es._state
	var player := es._player
	var e := state.get_empire(player)
	var inc := Economy.empire_income(state, player)
	var net := int(inc["net"].get("energy", 0))
	var debt := Finance.debt(state, player)
	var cap := Finance.cap(state, player)
	var g := es._grid()
	es._side_box.add_child(g)
	es._key_value(g, "Trésor", "%d énergie" % int(e.resources.get("energy", 0)))
	var nl := es._key_value(g, "Solde du mois", "%+d" % net)
	nl.add_theme_color_override("font_color", UiTheme.delta_color(net))
	var dl := es._key_value(g, "Dette / plafond", "%d / %d" % [debt, cap])
	dl.add_theme_color_override("font_color", debt_color(debt, cap))
	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = maxi(1, cap)
	bar.value = mini(debt, maxi(1, cap))
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(EmpireScreens.SIDE_WIDTH - 40.0, 12)
	var fill := StyleBoxFlat.new()
	fill.bg_color = debt_color(debt, cap)
	bar.add_theme_stylebox_override("fill", fill)
	bar.tooltip_text = cap_tip(state, player)
	es._side_box.add_child(bar)
	var g2 := es._grid()
	es._side_box.add_child(g2)
	var gr := Finance.grade(state, player)
	var gl := es._key_value(g2, "Cote de crédit", gr)
	gl.add_theme_color_override("font_color", Color(String(Finance.grade_def(gr).get("color", "#cccccc"))))
	gl.tooltip_text = "Selon la dette rapportée au plafond (%d %%). Elle fixe le taux et module le plafond." % Finance.ratio_pct(state, player)
	gl.mouse_filter = Control.MOUSE_FILTER_STOP
	var rl := es._key_value(g2, "Taux proposé", Finance.rate_label(Finance.rate_for(state, player, "bank")) + " / mois")
	rl.tooltip_text = rate_tip(state, player)
	rl.mouse_filter = Control.MOUSE_FILTER_STOP
	if Finance.full(state):
		es._key_value(g2, "Inflation", Finance.inflation_label(Finance.inflation(state, player)))
		es._key_value(g2, "Réserve", "%d énergie" % Finance.reserve(state, player))
	var st := Finance.crisis_stage(state, player)
	var cl := es._key_value(g2, "Crise de la dette", ("%s (%d / 100)" % [String(Finance.stage_def(st)["label"]), Finance.crisis_progress(state, player)]) if st > 0 else ("%d / 100" % Finance.crisis_progress(state, player)))
	cl.add_theme_color_override("font_color", Color(0.85, 0.33, 0.31) if st > 0 else UiTheme.TEXT_DIM)
	if Finance.in_bankruptcy(state, player):
		var bl := es._key_value(g2, "Faillite", "malus jusqu'au %s" % GameCalendar.date_string(Finance.bankrupt_until(state, player)))
		bl.add_theme_color_override("font_color", Color(0.85, 0.33, 0.31))
	for k in ["t", "d"]:
		var gend := FinanceBridges.grievance_end(state, player, k)
		if gend > state.tick:
			var what := "Baisser les impôts : revenir au cran Normal ou moins" if k == "t" else "Rembourser la dette : redescendre sous %d %% du plafond" % Finance.d_int("politics", "debt_ok_pct")
			es._side_box.add_child(UiTheme.paragraph("Doléance « %s » avant le %s." % [what, GameCalendar.date_string(gend)], EmpireScreens.SIDE_WIDTH - 24.0, 12))
	var by := FinanceBridges.balanced_years(state, player)
	if by > 0:
		es._key_value(g2, "Budget à l'équilibre", "%d an%s" % [by, "s" if by > 1 else ""])
	var talents := Finance.talent_labels(state, player)
	if not talents.is_empty():
		es._side_box.add_child(HSeparator.new())
		es._side_box.add_child(UiTheme.dim("Talents de votre peuple", 13))
		for tl in talents:
			es._side_box.add_child(UiTheme.paragraph("%s : %s" % [tl[0], tl[1]], EmpireScreens.SIDE_WIDTH - 24.0, 12))
	es._side_box.add_child(HSeparator.new())
	es._side_box.add_child(UiTheme.paragraph("L'énergie est le trésor de l'empire. Sous zéro, la Banque intérieure avance d'office ce qui manque, jusqu'au plafond de crédit ; au plafond, la crise de la dette monte jusqu'à la faillite.", EmpireScreens.SIDE_WIDTH - 24.0, 12))

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	es._content.add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 18)
	scroll.add_child(col)
	col.add_child(_tax_block(es))
	col.add_child(_budget_block(es, inc))
	if st > 0:
		col.add_child(_crisis_block(es))
	col.add_child(_loans_block(es))
	if Finance.full(state):
		if not OrderScreen._ro(es):
			col.add_child(_borrow_block(es))
			var lb := _lend_block(es)
			if lb != null:
				col.add_child(lb)
		col.add_child(_spending_block(es))
		col.add_child(_franchise_block(es))
		var rb := _ratings_block(es)
		if rb != null:
			col.add_child(rb)


static func debt_color(debt: int, cap: int) -> Color:
	if debt * 100 <= cap * 50:
		return Color(0.42, 0.75, 0.55)
	if debt * 100 <= cap * 75:
		return Color(0.86, 0.76, 0.36)
	return Color(0.85, 0.33, 0.31)


static func cap_tip(state: GameState, player: int) -> String:
	var cc: Dictionary = Finance.data()["credit"]
	var lines := PackedStringArray(["Plafond de crédit : %d mois de production brute d'énergie (%d), au moins %d." % [int(cc["months"]), Finance.gross_energy(state, player), int(cc["min"])]])
	var t := Finance._fx(state, player, "debt_cap_pct") + int(Finance.talent(state, player).get("cap_pct", 0))
	if t != 0:
		lines.append("  %+d %%  technologies, lois, talents" % t)
	for l in FinanceBridges.cap_lines(state, player):
		lines.append("  %+d %%  %s" % [int(l[1]), String(l[0])])
	lines.append("  ×%d %%  cote %s" % [int(Finance.grade_def(Finance.grade(state, player)).get("cap_pct", 100)), Finance.grade(state, player)])
	return "\n".join(lines)


static func rate_tip(state: GameState, player: int) -> String:
	var lines := PackedStringArray(["Intérêt mensuel fixé à la signature (jamais de spirale)."])
	var g := Finance.grade(state, player)
	lines.append("  ×%d %%  cote %s" % [int(Finance.grade_def(g).get("rate_pct", 100)), g])
	var t := Finance._fx(state, player, "debt_rate_pct") + int(Finance.talent(state, player).get("rate_pct", 0))
	if t != 0:
		lines.append("  %+d %%  technologies, lois, talents" % t)
	for l in FinanceBridges.rate_lines(state, player):
		lines.append("  %+d %%  %s" % [int(l[1]), String(l[0])])
	if Finance.in_bankruptcy(state, player):
		lines.append("  %+d %%  faillite récente" % Finance.d_int("bankruptcy", "rate_pct"))
	return "\n".join(lines)


static func _tax_block(es: EmpireScreens) -> Control:
	var state := es._state
	var player := es._player
	var b := Widgets.Block.new("Niveau d'imposition")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	b.body.add_child(row)
	var cur := Finance.tax(state, player)
	for d: Dictionary in Finance.tax_defs():
		var id := String(d["id"])
		var bt := Button.new()
		bt.text = String(d["label"])
		bt.toggle_mode = true
		bt.button_pressed = id == cur
		bt.focus_mode = Control.FOCUS_NONE
		bt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var why := Finance.check_tax(state, player, id) if id != cur else ""
		bt.disabled = OrderScreen._ro(es) or (why != "" and id != cur)
		bt.tooltip_text = String(d["text"]) + (("\n" + why) if why != "" else "")
		bt.pressed.connect(func() -> void: es.command_requested.emit(SimCommands.finance_tax(player, id)))
		row.add_child(bt)
		es.order_buttons["tax:" + id] = bt
	b.body.add_child(UiTheme.paragraph(String(Finance.tax_def(cur).get("text", "")) + " Changer de cran coûte %d influence, une fois par an au plus." % int(Finance.data()["taxes"]["change_cost"].get("influence", 0)), W, 13))
	var leak := 0
	var n := 0
	for sid in Stability.systems_of(state, player):
		leak += Finance.leak_pct(state, player, sid)
		n += 1
	@warning_ignore("integer_division")
	if n > 0 and leak / n > 0:
		@warning_ignore("integer_division")
		b.body.add_child(UiTheme.paragraph("Fuite fiscale : la corruption retient en moyenne %d %% de l'énergie des colonies sur l'impôt supplémentaire." % (leak / n), W, 13))
	return b


## Budget : recettes et dépenses d'énergie du mois, solde, projection.
static func _budget_block(es: EmpireScreens, inc: Dictionary) -> Control:
	var state := es._state
	var player := es._player
	var e := state.get_empire(player)
	var b := Widgets.Block.new("Budget du mois (énergie)")
	var gross := int(inc["gross"].get("energy", 0))
	var upkeep := int(inc["upkeep"].get("energy", 0))
	var rent := Finance.lender_income(state, player)
	var fleets := int(Fleets.upkeep(state, player).get("energy", 0))
	var armies := int(Ground.upkeep(state, player).get("energy", 0))
	var admin := int(Admin.upkeep(state, player).get("energy", 0)) if not state.admin.is_empty() else 0
	var interest := 0
	var principal := 0
	for l: Dictionary in Finance.loans(state, player):
		interest += Finance.interest_of(state, player, l)
		principal += Finance.principal_part(l)
	var raw := {"energy": upkeep - interest - principal}
	var before_infl := int(raw["energy"])
	var infl := Finance.inflation(state, player)
	if infl > 0 and before_infl > 0:
		@warning_ignore("integer_division")
		before_infl = before_infl * 10000 / (10000 + infl)
	var inflation := upkeep - interest - principal - before_infl
	var rest := before_infl - fleets - armies - admin
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 40)
	b.body.add_child(row)
	var income := [["Production et impôt des colonies", gross - rent]]
	if rent > 0:
		income.append(["Mensualités reçues (prêts consentis)", rent])
	var spend := [["Flottes", fleets], ["Armées", armies], ["Bâtiments et colonies", rest]]
	if admin > 0:
		spend.append(["Fonctionnaires", admin])
	if interest > 0:
		spend.append(["Intérêts", interest])
	if principal > 0:
		spend.append(["Remboursement du capital", principal])
	if inflation > 0:
		spend.append(["Inflation", inflation])
	for side in [["Recettes", income], ["Dépenses", spend]]:
		var c := VBoxContainer.new()
		c.custom_minimum_size = Vector2(340, 0)
		row.add_child(c)
		c.add_child(UiTheme.dim(String(side[0]), 14))
		for p in (side[1] as Array):
			if int(p[1]) == 0:
				continue
			var l := Label.new()
			l.text = "%d   %s" % [int(p[1]), String(p[0])]
			l.add_theme_font_size_override("font_size", 13)
			c.add_child(l)
	var net := int(inc["net"].get("energy", 0))
	var energy := int(e.resources.get("energy", 0))
	var proj := energy + 12 * net
	var line := "Solde : %+d par mois. Dans 12 mois : %d énergie" % [net, proj]
	if net < 0:
		var room := energy + maxi(0, Finance.cap(state, player) - Finance.debt(state, player))
		@warning_ignore("integer_division")
		line += " ; plafond de crédit atteint dans %d mois environ." % maxi(0, room / -net)
	else:
		line += "."
	b.body.add_child(UiTheme.paragraph(line, W, 13))
	return b


static func _crisis_block(es: EmpireScreens) -> Control:
	var state := es._state
	var player := es._player
	var st := Finance.crisis_stage(state, player)
	var b := Widgets.Block.new("Crise de la dette : %s" % String(Finance.stage_def(st)["label"]))
	b.body.add_child(UiTheme.paragraph(String(Finance.stage_def(st)["text"]) + " La jauge monte chaque mois au plafond avec un solde négatif, et recule sinon ; à 100, la faillite.", W, 13))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	b.body.add_child(row)
	var cur := Finance.approach(state, player)
	for d: Dictionary in Finance.approach_defs():
		var id := String(d["id"])
		var bt := Button.new()
		bt.text = String(d["label"])
		bt.toggle_mode = true
		bt.button_pressed = id == cur
		bt.focus_mode = Control.FOCUS_NONE
		bt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bt.disabled = OrderScreen._ro(es) or id == cur
		bt.tooltip_text = String(d["text"])
		bt.pressed.connect(func() -> void: es.command_requested.emit(SimCommands.finance_approach(player, id)))
		row.add_child(bt)
		es.order_buttons["approach:" + id] = bt
	return b


static func _loans_block(es: EmpireScreens) -> Control:
	var state := es._state
	var player := es._player
	var b := Widgets.Block.new("Emprunts en cours")
	var ls := Finance.loans(state, player)
	if ls.is_empty():
		b.body.add_child(UiTheme.dim("Aucune dette : l'empire ne doit rien à personne.", 14))
	for l: Dictionary in ls:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var nl := Label.new()
		nl.text = Finance.lender_label(state, player, l)
		nl.custom_minimum_size = Vector2(230, 0)
		nl.clip_text = true
		row.add_child(nl)
		var vl := Label.new()
		var m := int(l["m"])
		vl.text = "%d énergie à %s / mois" % [int(l["p"]), Finance.rate_label(int(l["r"]))] + ((", %d mensualités de %d" % [m, Finance.installment(state, player, l)]) if m > 0 else ", intérêts seuls")
		vl.custom_minimum_size = Vector2(330, 0)
		vl.add_theme_font_size_override("font_size", 13)
		row.add_child(vl)
		if not OrderScreen._ro(es):
			var lid := int(l["id"])
			var amount := int(l["p"])
			var bt := Button.new()
			bt.focus_mode = Control.FOCUS_NONE
			bt.add_theme_font_size_override("font_size", 12)
			bt.text = "Rembourser"
			var why := Finance.check_repay(state, player, lid, amount)
			bt.disabled = why != ""
			bt.tooltip_text = why if why != "" else "Rembourser tout le capital restant (%d)." % amount
			bt.pressed.connect(func() -> void: es.command_requested.emit(SimCommands.finance_repay(player, lid, amount)))
			row.add_child(bt)
			es.order_buttons["repay:%d" % lid] = bt
			if String(l["l"]) != "bank" and Finance.full(state):
				var rb := Button.new()
				rb.focus_mode = Control.FOCUS_NONE
				rb.add_theme_font_size_override("font_size", 12)
				rb.text = "Répudier"
				var why_r := Finance.check_repudiate(state, player, lid)
				rb.disabled = why_r != ""
				rb.tooltip_text = why_r if why_r != "" else "Ne plus payer : pas de malus de faillite, mais cote D pendant 10 ans, prêteurs fâchés, et un motif de guerre « Recouvrement » pour le créancier."
				rb.pressed.connect(func() -> void: es.command_requested.emit(SimCommands.finance_repudiate(player, lid)))
				row.add_child(rb)
				es.order_buttons["repudiate:%d" % lid] = rb
		b.body.add_child(row)
	return b


static func _borrow_block(es: EmpireScreens) -> Control:
	var state := es._state
	var player := es._player
	var lc: Dictionary = Finance.data()["loan"]
	var b := Widgets.Block.new("Lever un emprunt")
	b.body.add_child(UiTheme.paragraph("De %d à %d énergie tout de suite, remboursés en %d mensualités. Le taux se fixe à la signature, selon votre cote et le prêteur." % [int(lc["min"]), int(lc["max"]), int(lc["months"])], W, 13))
	for lk in Finance.lenders(state, player).slice(0, 8):
		var key := String(lk[0])
		var kw := Finance._split(key)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var nl := Label.new()
		nl.text = "%s (%s / mois)" % [String(lk[1]), Finance.rate_label(Finance.rate_for(state, player, String(kw[0]), int(kw[1])))]
		nl.custom_minimum_size = Vector2(300, 0)
		nl.clip_text = true
		row.add_child(nl)
		for amount in [100, 300, 500, 1000]:
			var bt := Button.new()
			bt.focus_mode = Control.FOCUS_NONE
			bt.add_theme_font_size_override("font_size", 12)
			bt.text = "+%d" % amount
			var why := Finance.check_borrow(state, player, key, amount)
			bt.disabled = why != ""
			bt.tooltip_text = why if why != "" else "Emprunter %d énergie à %s." % [amount, String(lk[1])]
			var a := int(amount)
			bt.pressed.connect(func() -> void: es.command_requested.emit(SimCommands.finance_borrow(player, key, a)))
			row.add_child(bt)
			es.order_buttons["borrow:%s:%d" % [key, amount]] = bt
		b.body.add_child(row)
	return b


static func _lend_block(es: EmpireScreens) -> Control:
	var state := es._state
	var player := es._player
	var e := state.get_empire(player)
	var rows := []
	for o in state.empires:
		if o.id != player and not o.eliminated and not o.is_npc() and e.contacts.has(o.id) and Finance.applies(state, o.id):
			rows.append(o)
	if rows.is_empty():
		return null
	var b := Widgets.Block.new("Prêter à un autre empire")
	b.body.add_child(UiTheme.paragraph("Traité de prêt : vous avancez l'énergie, il vous rembourse en %d mensualités avec intérêts. Une IA n'accepte que si elle en a besoin. S'il fait défaut, vous gagnez un motif de guerre « Recouvrement »." % Finance.d_int("loan", "months"), W, 13))
	for o: Empire in rows:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var nl := Label.new()
		var g := Finance.grade_seen(state, o.id, player)
		nl.text = "%s (cote %s)" % [o.short_name(), g]
		nl.custom_minimum_size = Vector2(300, 0)
		nl.add_theme_color_override("font_color", Color(String(Finance.grade_def(g).get("color", "#cccccc"))))
		row.add_child(nl)
		for amount in [100, 300, 500]:
			var bt := Button.new()
			bt.focus_mode = Control.FOCUS_NONE
			bt.add_theme_font_size_override("font_size", 12)
			bt.text = "%d" % amount
			var why := Finance.check_lend(state, player, o.id, amount)
			bt.disabled = why != ""
			bt.tooltip_text = why if why != "" else "Lui prêter %d énergie." % amount
			var oid := o.id
			var a := int(amount)
			bt.pressed.connect(func() -> void: es.command_requested.emit(SimCommands.finance_lend(player, oid, a)))
			row.add_child(bt)
			es.order_buttons["lend:%d:%d" % [o.id, amount]] = bt
		b.body.add_child(row)
	return b


## Solde des équipages, impôt de guerre, traitements des fonctionnaires, planche à billets.
static func _spending_block(es: EmpireScreens) -> Control:
	var state := es._state
	var player := es._player
	var b := Widgets.Block.new("Dépenses de l'État")
	b.body.add_child(UiTheme.dim("Solde des équipages", 14))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	b.body.add_child(row)
	var cur := Finance.pay(state, player)
	for d: Dictionary in Finance.pay_defs():
		var id := String(d["id"])
		var bt := Button.new()
		bt.text = String(d["label"])
		bt.toggle_mode = true
		bt.button_pressed = id == cur
		bt.focus_mode = Control.FOCUS_NONE
		bt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bt.disabled = OrderScreen._ro(es) or id == cur
		bt.tooltip_text = String(d["text"])
		bt.pressed.connect(func() -> void: es.command_requested.emit(SimCommands.finance_pay(player, id)))
		row.add_child(bt)
		es.order_buttons["pay:" + id] = bt
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 10)
	b.body.add_child(row2)
	var on := Finance.war_tax_on(state, player)
	var wt := Button.new()
	wt.focus_mode = Control.FOCUS_NONE
	wt.text = "Lever l'impôt de guerre" if not on else "Lever : impôt de guerre en vigueur"
	var why := Finance.check_war_tax(state, player, not on)
	wt.disabled = OrderScreen._ro(es) or why != ""
	wt.tooltip_text = String(Finance.data()["war_tax"]["_doc"]) + (("\n" + why) if why != "" else "")
	wt.pressed.connect(func() -> void: es.command_requested.emit(SimCommands.finance_war_tax(player, not on)))
	row2.add_child(wt)
	es.order_buttons["war_tax"] = wt
	var mt := Button.new()
	mt.focus_mode = Control.FOCUS_NONE
	mt.text = "Battre monnaie (+%d énergie)" % Finance.mint_amount(state, player)
	var why_m := Finance.check_mint(state, player)
	mt.disabled = OrderScreen._ro(es) or why_m != ""
	mt.tooltip_text = why_m if why_m != "" else "Planche à billets : %d mois de production tout de suite, contre +3 %% d'inflation." % Finance.d_int("mint", "months")
	mt.pressed.connect(func() -> void: es.command_requested.emit(SimCommands.finance_mint(player)))
	row2.add_child(mt)
	es.order_buttons["mint"] = mt
	if not state.admin.is_empty() and Admin.applies(state, player):
		b.body.add_child(UiTheme.dim("Traitements des fonctionnaires (effort administratif)", 14))
		var row3 := HBoxContainer.new()
		row3.add_theme_constant_override("separation", 6)
		b.body.add_child(row3)
		var ce := Admin.effort(state, player)
		for d: Dictionary in Admin.effort_defs():
			var id := String(d["id"])
			var bt := Button.new()
			bt.text = String(d["label"])
			bt.toggle_mode = true
			bt.button_pressed = id == ce
			bt.focus_mode = Control.FOCUS_NONE
			bt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var why_e := Admin.check_effort(state, player, id) if id != ce else ""
			bt.disabled = OrderScreen._ro(es) or (why_e != "" and id != ce)
			bt.tooltip_text = String(d["text"])
			bt.pressed.connect(func() -> void: es.command_requested.emit(SimCommands.admin_effort(player, id)))
			row3.add_child(bt)
			es.order_buttons["salary:" + id] = bt
	return b


static func _franchise_block(es: EmpireScreens) -> Control:
	var state := es._state
	var player := es._player
	var fc: Dictionary = Finance.data()["franchises"]
	var mine := Finance.franchises_of(state, player)
	var b := Widgets.Block.new("Franchises fiscales (%d / %d)" % [mine.size(), Finance.franchise_max(state, player)])
	b.body.add_child(UiTheme.paragraph("Un système exempté d'impôt : énergie de ses colonies %d %%, stabilité +%d, intégration administrative plus rapide. Accorder ou retirer coûte %d influence." % [
			int(fc["energy_pct"]), int(fc["stability"]), int(fc["cost"].get("influence", 0))], W, 13))
	var list := []
	for sid in Stability.systems_of(state, player):
		var v := Stability.value(state, sid) if Stability.applies(state, player) else 50
		list.append([0 if Finance.has_franchise(state, sid) else 1, v, sid])
	list.sort()
	for it in list.slice(0, 8):
		var sid := int(it[2])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var nl := Label.new()
		nl.text = "%s (stabilité %d)" % [state.galaxy.systems[sid].system_name, int(it[1])]
		nl.custom_minimum_size = Vector2(300, 0)
		row.add_child(nl)
		if Finance.on_strike(state, sid):
			var sl := Label.new()
			sl.text = "en grève"
			sl.add_theme_color_override("font_color", Color(0.85, 0.33, 0.31))
			row.add_child(sl)
		if not OrderScreen._ro(es):
			var has := Finance.has_franchise(state, sid)
			var bt := Button.new()
			bt.focus_mode = Control.FOCUS_NONE
			bt.add_theme_font_size_override("font_size", 12)
			bt.text = "Retirer la franchise" if has else "Accorder la franchise"
			var why := Finance.check_franchise(state, player, sid)
			bt.disabled = why != ""
			bt.tooltip_text = why
			bt.pressed.connect(func() -> void: es.command_requested.emit(SimCommands.finance_franchise(player, sid)))
			row.add_child(bt)
			es.order_buttons["franchise:%d" % sid] = bt
		b.body.add_child(row)
	return b


static func _ratings_block(es: EmpireScreens) -> Control:
	var state := es._state
	var player := es._player
	var e := state.get_empire(player)
	var rows := []
	for o in state.empires:
		if o.id != player and not o.eliminated and not o.is_npc() and e.contacts.has(o.id) and Finance.applies(state, o.id):
			rows.append(o)
	if rows.is_empty():
		return null
	var b := Widgets.Block.new("Cotes de crédit des empires connus")
	var gr := GridContainer.new()
	gr.columns = 4
	gr.add_theme_constant_override("h_separation", 24)
	b.body.add_child(gr)
	for o: Empire in rows:
		var g := Finance.grade_seen(state, o.id, player)
		var l := Label.new()
		l.text = "%s : %s" % [o.short_name(), g]
		l.add_theme_font_size_override("font_size", 13)
		l.add_theme_color_override("font_color", Color(String(Finance.grade_def(g).get("color", "#cccccc"))))
		gr.add_child(l)
	return b


static func signature(es: EmpireScreens) -> String:
	var state := es._state
	var e := state.get_empire(es._player)
	@warning_ignore("integer_division")
	return "%d|%s|%s|%s|%d|%d" % [state.tick / 30, str(Finance.entry(state, es._player)), str(state.finance.get("fr", {})), str(state.finance.get("strike", {})),
			e.resources.get("influence", 0) / 10 if e else 0, e.resources.get("energy", 0) / 20 if e else 0]
