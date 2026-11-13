class_name TradeScreen
extends RefCounted
## Écran Commerce (C) : les routes de l'empire (voir Trade).
## Colonne de gauche : capacité (base, comptoirs, technologies), revenu du mois, routes intérieures
## réservées (- / +), embargos en cours.
## Contenu : routes envoyées (partenaire ou colonie, sauts, valeur, tarif, pertes, blocus, net),
## routes reçues des partenaires, partenaires sans route, puis les systèmes de route menacés par
## les pirates. Construit dans les conteneurs d'EmpireScreens, dont il reprend les aides.


static func build(es: EmpireScreens) -> void:
	var state := es._state
	var player := es._player
	es._trade_sig = signature(es)
	es.trade_buttons.clear()
	es._side_header("screen_trade", "Commerce", Color(0.85, 0.7, 0.35), "faction")
	var me := state.get_empire(player)
	var g := es._grid()
	es._side_box.add_child(g)
	var cap := Trade.capacity(state, player)
	var cl := es._key_value(g, "Capacité de routes", str(cap))
	cl.tooltip_text = "Base %d, comptoirs %d, technologies %d" % [int(Trade.data()["capacity_base"]), Trade.comptoirs(state, player).size(),
			cap - int(Trade.data()["capacity_base"]) - Trade.comptoirs(state, player).size()]
	cl.mouse_filter = Control.MOUSE_FILTER_STOP
	es._key_value(g, "Routes envoyées", str(Trade.sent_by(state, player).size()))
	es._key_value(g, "Partenaires", str(Trade.partners(state, player).size()))
	var inc := Trade.income(state, player).duplicate()
	if not state.goods.is_empty():
		for r in Goods.income(state, player):
			inc[r] = int(inc.get(r, 0)) + int(Goods.income(state, player)[r])
	var parts := PackedStringArray()
	for r in GameData.resource_ids():
		if int(inc.get(r, 0)) != 0:
			parts.append("%+d %s" % [int(inc[r]), GameData.resource_label(r).to_lower()])
	es._key_value(g, "Revenu du mois", ", ".join(parts) if not parts.is_empty() else "aucun")
	es._side_box.add_child(HSeparator.new())
	es._side_box.add_child(UiTheme.dim("Routes intérieures réservées", 13))
	var rrow := HBoxContainer.new()
	rrow.add_theme_constant_override("separation", 8)
	es._side_box.add_child(rrow)
	var res := Trade.reserved(state, player)
	for d in [-1, 1]:
		var b := Button.new()
		b.text = "−" if d < 0 else "+"
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(30, 0)
		var n: int = res + d
		var why := Trade.check_reserve(state, player, n) if me else "Spectateur"
		b.disabled = why != ""
		b.tooltip_text = why
		b.pressed.connect(func() -> void: es.command_requested.emit(SimCommands.trade_reserve(player, n)))
		rrow.add_child(b)
		es.trade_buttons["reserve%+d" % d] = b
		if d < 0:
			var l := Label.new()
			l.text = "%d / %d" % [res, cap]
			l.theme_type_variation = &"Numbers"
			rrow.add_child(l)
	var young := Trade.young_colonies(state, player)
	es._side_box.add_child(UiTheme.paragraph("Une route intérieure part de la capitale vers une colonie de moins de %d habitants : +%d nourriture, +%d matériaux par mois et une croissance plus rapide. Les réserver les fait passer avant les partenaires. Jeunes colonies : %d." % [
			int(Trade.data()["internal"]["young_pop"]), int(Trade.data()["internal"]["yields"]["food"]), int(Trade.data()["internal"]["yields"]["materials"]), young.size()],
			EmpireScreens.SIDE_WIDTH - 24.0, 12))
	var emb := Trade.embargoes_of(state, player)
	var against := []
	for e in state.empires:
		if e.id != player and Trade.embargo_by(state, e.id, player):
			against.append(e.display_name())
	if not emb.is_empty() or not against.is_empty():
		es._side_box.add_child(HSeparator.new())
		es._side_box.add_child(UiTheme.dim("Embargos", 13))
		for o in emb:
			es._side_box.add_child(UiTheme.paragraph("Vous frappez %s d'embargo (à lever dans la diplomatie)." % _name(state, o), EmpireScreens.SIDE_WIDTH - 24.0, 12))
		for n in against:
			es._side_box.add_child(UiTheme.paragraph("%s vous frappe d'embargo." % n, EmpireScreens.SIDE_WIDTH - 24.0, 12))
	es._side_box.add_child(HSeparator.new())
	es._side_box.add_child(UiTheme.paragraph(String(EmpireBar.screen_info("trade").get("why", "")), EmpireScreens.SIDE_WIDTH - 24.0, 13))

	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 10)
	es._content.add_child(root)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 2)
	root.add_child(tabs)
	for t in [["routes", "Routes"], ["resources", "Ressources"], ["market", "Marché"], ["knowledge", "Savoir"]]:
		var tb := Button.new()
		tb.theme_type_variation = &"TabButton"
		tb.text = String(t[1]).to_upper()
		tb.toggle_mode = true
		tb.focus_mode = Control.FOCUS_NONE
		tb.button_pressed = es.trade_tab == String(t[0])
		var tid: String = t[0]
		tb.pressed.connect(func() -> void:
			es.trade_tab = tid
			es.show_screen("trade"))
		tabs.add_child(tb)
		es.trade_buttons["tab_" + tid] = tb
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 18)
	scroll.add_child(col)
	if es.trade_tab == "resources":
		GoodsScreen.build_resources(es, col)
		return
	if es.trade_tab == "market":
		GoodsScreen.build_market(es, col)
		return
	if es.trade_tab == "knowledge":
		GoodsScreen.build_knowledge(es, col)
		return

	var sent := Widgets.Block.new("Vos routes (%d / %d)" % [Trade.sent_by(state, player).size(), cap])
	col.add_child(sent)
	for r in Trade.sent_by(state, player):
		sent.body.add_child(_route_row(es, r, true))
	if Trade.sent_by(state, player).is_empty():
		sent.body.add_child(UiTheme.dim("Aucune route : signez l'ouverture de comptoirs dans la diplomatie, ou réservez une route intérieure.", 14))
	var recv: Array[Dictionary] = []
	for r in Trade.routes_of(state, player):
		if int(r["to"]) == player and int(r["from"]) != player:
			recv.append(r)
	if not recv.is_empty():
		var rb := Widgets.Block.new("Routes de vos partenaires")
		col.add_child(rb)
		rb.body.add_child(UiTheme.paragraph("Elles rapportent autant aux deux bouts : vos partenaires les envoient avec leur propre capacité.", 760.0, 13))
		for r in recv:
			rb.body.add_child(_route_row(es, r, false))
	var idle: Array[int] = []
	for o in Trade.partners(state, player):
		var has := false
		for r in Trade.sent_by(state, player):
			if int(r["to"]) == o:
				has = true
		if not has:
			idle.append(o)
	if not idle.is_empty():
		var ib := Widgets.Block.new("Partenaires sans route de votre part")
		col.add_child(ib)
		for o in idle:
			var why := "embargo" if Trade.embargoed(state, player, o) else ("pas de chemin" if Trade.best_path(state, player, o).is_empty() else "capacité pleine")
			ib.body.add_child(UiTheme.paragraph("%s · %s · valeur possible %d" % [_name(state, o), why, Trade.estimate(state, player, o)], 760.0, 14))
	var risky := risky_systems(state, player)
	if not risky.is_empty():
		var kb := Widgets.Block.new("Systèmes de route exposés aux pirates")
		col.add_child(kb)
		var pd: Dictionary = Trade.data()["piracy"]
		@warning_ignore("integer_division")
		kb.body.add_child(UiTheme.paragraph("Hors de tout territoire et sans flotte pour les garder, les systèmes traversés attirent les pirates : le risque monte chaque mois (plus vite près d'un repaire) et une flotte ou une patrouille le fait retomber. Une route perd le risque de son système le plus exposé, %d %% au plus. Au maximum (%d ‰), un nouveau repaire s'installe." % [
				int(pd["risk_max"]) / 10, int(pd["spawn_at"])], 760.0, 13))
		var shown := 0
		for it in risky:
			shown += 1
			if shown > 8:
				kb.body.add_child(UiTheme.dim("… et %d autres systèmes moins exposés." % (risky.size() - 8), 13))
				break
			var sid := int(it[1])
			var l := Label.new()
			l.text = "%s · risque %d ‰%s" % [state.galaxy.systems[sid].system_name, -int(it[0]),
					"  · un repaire peut s'y installer" if -int(it[0]) >= int(Trade.data()["piracy"]["spawn_at"]) else ""]
			l.add_theme_font_size_override("font_size", 14)
			l.add_theme_color_override("font_color", Color(0.95, 0.55, 0.4) if -int(it[0]) >= 150 else UiTheme.TEXT)
			kb.body.add_child(l)


## Systèmes des routes de l'empire avec un risque pirate, du plus menacé au moins menacé : [[-risque, sid]].
static func risky_systems(state: GameState, player: int) -> Array:
	var seen := {}
	var out := []
	for r in Trade.routes_of(state, player):
		for sid in r["path"]:
			var s := int(sid)
			if seen.has(s):
				continue
			seen[s] = true
			var v := Trade.risk_at(state, s)
			if v > 0:
				out.append([-v, s])
	out.sort()
	return out


static func _name(state: GameState, eid: int) -> String:
	var e := state.get_empire(eid)
	return e.display_name() if e else "?"


static func _route_row(es: EmpireScreens, r: Dictionary, mine: bool) -> Control:
	var state := es._state
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var nl := Label.new()
	var ext := String(r["kind"]) == "ext"
	if ext:
		var other := int(r["to"]) if mine else int(r["from"])
		nl.text = _name(state, other)
		var e := state.get_empire(other)
		if e:
			nl.add_theme_color_override("font_color", e.color().lightened(0.3))
	else:
		var pl := state.galaxy.get_planet(int(r["colony"]))
		nl.text = "Intérieure → %s" % (pl.display_name(state.galaxy) if pl else "?")
		nl.add_theme_color_override("font_color", Color(0.55, 0.85, 0.6))
	nl.custom_minimum_size = Vector2(220, 0)
	nl.clip_text = true
	nl.add_theme_font_size_override("font_size", 16)
	row.add_child(nl)
	var p: Array = r["path"]
	var info := Label.new()
	info.add_theme_font_size_override("font_size", 14)
	info.custom_minimum_size = Vector2(420, 0)
	var bits := PackedStringArray(["%d sauts" % maxi(0, p.size() - 1)])
	if ext:
		var ti := Trade.tier_info(int(r["tier"]))
		bits.append("valeur %d" % int(r["value"]))
		bits.append(String(ti.get("label", "")))
		if int(ti.get("tariff_pct", 0)) > 0:
			bits.append("tarif %d %%" % int(ti["tariff_pct"]))
		if int(ti.get("bonus_pct", 0)) > 0:
			bits.append("+%d %%" % int(ti["bonus_pct"]))
	else:
		bits.append("+%d nourriture, +%d matériaux" % [int(Trade.data()["internal"]["yields"]["food"]), int(Trade.data()["internal"]["yields"]["materials"])])
	if int(r.get("loss", 0)) > 0:
		bits.append("pirates −%s %%" % String.num(int(r["loss"]) / 10.0, 1))
	info.text = " · ".join(bits)
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(info)
	var nv := Label.new()
	nv.add_theme_font_size_override("font_size", 16)
	nv.theme_type_variation = &"Numbers"
	if bool(r.get("blocked", false)):
		var by := int(r.get("by", -1))
		var who := "faune" if by == GameState.FAUNA_ID else ("pirates" if GameState.is_npc(by) else _name(state, by))
		nv.text = "BLOQUÉE (%s à %s)" % [who, state.galaxy.systems[int(r.get("at", p[0]))].system_name]
		nv.add_theme_color_override("font_color", Color(0.95, 0.4, 0.35))
	elif ext:
		nv.text = "%+d énergie" % int(r["net"])
		nv.add_theme_color_override("font_color", UiTheme.GOLD)
	else:
		nv.text = "active"
	nv.tooltip_text = "Chemin : " + " → ".join(p.map(func(s: Variant) -> String: return state.galaxy.systems[int(s)].system_name))
	nv.mouse_filter = Control.MOUSE_FILTER_STOP
	row.add_child(nv)
	return row


## Ce qui change l'écran : mois, routes, réserve, embargos.
static func signature(es: EmpireScreens) -> String:
	var state := es._state
	@warning_ignore("integer_division")
	return "%d|%d|%s|%s|%d|%s" % [state.tick / 30, Trade.reserved(state, es._player), str(Trade.embargoes_of(state, es._player)),
			str(Trade.sent_by(state, es._player).size()), Trade.capacity(state, es._player), GoodsScreen.signature(es)]
