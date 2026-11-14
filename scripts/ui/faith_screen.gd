class_name FaithScreen
extends RefCounted
## Écran Foi (Y) : la religion de l'empire (voir Faiths).
## Colonne de gauche : foi d'État, culte natal, grandes fois en jeu, délai avant un changement.
## Contenu : le choix de la foi d'État (laïcité, incroyance, grandes fois), les grandes fois de la
## galaxie (fondateur, monde saint, fidèles, chef de foi, nature, doctrines et préceptes ; le fondateur
## fixe la foi à la Révélation, le chef choisit un précepte à chaque palier), puis les croyances de
## chaque colonie de l'empire.
## Construit dans les conteneurs d'EmpireScreens, dont il reprend les aides (_grid, _key_value…).


static func build(es: EmpireScreens) -> void:
	var state := es._state
	var player := es._player
	es._faith_sig = signature(es)
	es.faith_buttons.clear()
	es._side_header("screen_faith", "Foi", Color(0.86, 0.74, 0.42), "faction")
	var g := es._grid()
	es._side_box.add_child(g)
	if not state.faith_on:
		es._side_box.add_child(UiTheme.paragraph("Cette partie se joue sans religions (réglage de Nouvelle partie).", EmpireScreens.SIDE_WIDTH - 24.0, 13))
		return
	var sf := Faiths.state_faith(state, player)
	var sl := es._key_value(g, "Foi d'État", Faiths.name_of(state, sf))
	if sf != Faiths.LAICITE:
		sl.add_theme_color_override("font_color", Faiths.color_of(state, sf).lightened(0.2))
	var nat := Faiths.native_def(state, player)
	es._key_value(g, "Culte natal", String(nat.get("label", "aucun")))
	es._key_value(g, "Grandes fois", "%d / %d" % [Faiths.ids(state).size(), Faiths.limit(state)])
	var last := int(state.faiths["changed"].get(str(player), -100000))
	var left := int(Faiths.data()["state"]["cooldown_days"]) - (state.tick - last)
	@warning_ignore("integer_division")
	es._key_value(g, "Prochain changement", "dans %d mois" % maxi(1, (left + 29) / 30) if left > 0 else "possible")
	var own := Faiths.founded_by(state, player)
	es._key_value(g, "Foi fondée", Faiths.name_of(state, own) if own != "" else "aucune")
	if not Faiths.faith(state, sf).is_empty():
		es._key_value(g, "Zèle", "%d / 100" % FaithWars.zeal(state, sf))
		es._key_value(g, "Nature", String(FaithWars.nature_def(FaithWars.nature(state, sf)).get("label", "aucune")))
	if FaithWars.demand(state, player) > state.tick:
		var dl := es._key_value(g, "Doléance", "Liberté de culte (%s)" % GameCalendar.date_string(FaithWars.demand(state, player)))
		dl.add_theme_color_override("font_color", UiTheme.WARN)
	if not nat.is_empty():
		es._side_box.add_child(UiTheme.paragraph("%s : %s" % [String(nat["label"]), String(nat["text"])], EmpireScreens.SIDE_WIDTH - 24.0, 12))
	es._side_box.add_child(HSeparator.new())
	es._side_box.add_child(UiTheme.paragraph(String(EmpireBar.screen_info("faith").get("why", "")), EmpireScreens.SIDE_WIDTH - 24.0, 13))

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	es._content.add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 18)
	scroll.add_child(col)
	if Faiths.is_hive(state, player):
		var b := Widgets.Block.new("Conscience collective")
		b.body.add_child(UiTheme.paragraph("Une seule pensée ne prie pas : vos colonies n'ont pas de foi, ne prêchent pas et ne se convertissent pas.", 760.0, 15))
		col.add_child(b)
		col.add_child(_je_block(es))
	else:
		col.add_child(_state_block(es))
		var nb := FaithNaturePanel.build(es)
		if nb != null:
			col.add_child(nb)
		col.add_child(_missions_block(es))
	col.add_child(_faiths_block(es))
	col.add_child(_colonies_block(es))


## Ce qui change l'écran : mois, fois (doctrines, préceptes), foi d'État, fidèles de l'empire.
static func signature(es: EmpireScreens) -> String:
	var state := es._state
	if not state.faith_on:
		return "off"
	var mine := []
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner == es._player:
			mine.append(c.faith)
	var lot2 := []
	for k in ["missions", "wards", "crusades", "seen", "je", "demands", "blessed", "quarantine", "nat"]:
		lot2.append(state.faiths.get(k, {}))
	@warning_ignore("integer_division")
	return "%d|%s|%s|%s|%s" % [state.tick / 30, str(state.faiths["list"]), str(state.faiths["state"]), str(mine), str(lot2)]


static func _state_block(es: EmpireScreens) -> Control:
	var state := es._state
	var player := es._player
	var b := Widgets.Block.new("Foi d'État")
	var sd: Dictionary = Faiths.data()["state"]
	b.body.add_child(UiTheme.paragraph("Là où la foi d'État domine, stabilité +%d ; là où une autre foi domine, %d. Changer de foi d'État coûte %d de stabilité pendant un an, et le clergé ne l'accepte qu'une fois tous les trois ans. Adopter une foi étrangère demande une colonie où elle dépasse %d %%." % [
			int(sd["stab_major"]), int(sd["stab_minor"]), int(sd["change_stab"]), int(sd["adopt_share_pct"])], 760.0, 13))
	var choices: Array = [Faiths.LAICITE, Faiths.INCROYANCE]
	choices.append_array(Faiths.ids(state))
	var sf := Faiths.state_faith(state, player)
	for fid: String in choices:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		b.body.add_child(row)
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(12, 12)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		dot.color = Faiths.color_of(state, fid) if fid != Faiths.LAICITE else Color(0.4, 0.4, 0.4)
		row.add_child(dot)
		var nl := Label.new()
		nl.text = Faiths.name_of(state, fid)
		nl.custom_minimum_size = Vector2(260, 0)
		if fid == sf:
			nl.add_theme_color_override("font_color", UiTheme.GOLD)
		row.add_child(nl)
		var info := Label.new()
		info.custom_minimum_size = Vector2(340, 0)
		info.add_theme_font_size_override("font_size", 12)
		info.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
		if Faiths.data()["pseudo"].has(fid):
			info.text = String(Faiths.data()["pseudo"][fid]["text"])
			info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		else:
			info.text = "%d fidèles chez vous, meilleure colonie %d %%" % [int(Faiths.followers_by_owner(state, fid).get(player, 0)), Faiths.best_share(state, player, fid)]
		row.add_child(info)
		if fid == sf:
			row.add_child(UiTheme.dim("foi d'État", 13))
			continue
		var btn := Button.new()
		btn.focus_mode = Control.FOCUS_NONE
		btn.text = "Adopter"
		var why := Faiths.check_state(state, player, fid)
		btn.disabled = why != ""
		btn.tooltip_text = why
		btn.pressed.connect(func() -> void: es.command_requested.emit(SimCommands.faith_state(player, fid)))
		row.add_child(btn)
		es.faith_buttons["state:" + fid] = btn
	var para := false
	for fid in Faiths.ids(state):
		if FaithWars.nature(state, fid) == "parasite":
			para = true
	if para or FaithWars.quarantined(state, player):
		var on := FaithWars.quarantined(state, player)
		var qb := _btn("Lever la quarantaine" if on else "Mettre en quarantaine", FaithWars.check_quarantine(state, player),
				"Contre le Parasite saint : flottes et migrants ne le portent plus chez vous, mais chaque système perd %d de stabilité." % absi(int(FaithWars.data()["natures"]["parasite_quarantine_stab"])))
		qb.pressed.connect(func() -> void: es.command_requested.emit(SimCommands.faith_quarantine(player)))
		b.body.add_child(qb)
		es.faith_buttons["quarantine"] = qb
	return b


static func _faiths_block(es: EmpireScreens) -> Control:
	var state := es._state
	var player := es._player
	var b := Widgets.Block.new("Grandes fois de la galaxie")
	if Faiths.ids(state).is_empty():
		b.body.add_child(UiTheme.paragraph("Aucune grande foi n'est encore née. Une Révélation peut venir d'une relique sainte, d'un gardien vaincu, d'un héros à l'ambition Foi (niveau 3), de trois technologies de Société de l'ère II, ou d'un prophète qu'on écoute.", 760.0, 14))
		return b
	for fid: String in Faiths.ids(state):
		var f := Faiths.faith(state, fid)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 4)
		b.body.add_child(box)
		var title := Label.new()
		title.text = Faiths.name_of(state, fid)
		title.add_theme_font_size_override("font_size", 18)
		title.add_theme_color_override("font_color", Faiths.color_of(state, fid).lightened(0.25))
		box.add_child(title)
		var founder := state.get_empire(int(f["founder"]))
		var holy := state.galaxy.get_planet(int(f["holy"]))
		var h := Faiths.head(state, fid)
		var known := founder != null and (int(f["founder"]) == player or state.get_empire(player).contacts.has(int(f["founder"])))
		box.add_child(_faith_tags(es, fid))
		box.add_child(UiTheme.dim("%s, %s. Monde saint : %s. %d fidèles. Chef de foi : %s." % [
				founder.display_name() if known else "Un empire inconnu", String(Faiths.data()["vias"].get(String(f["via"]), "")),
				holy.display_name(state.galaxy), Faiths.followers(state, fid),
				"vous" if h == player else (state.get_empire(h).short_name() if h >= 0 else "personne")], 13))
		if int(f.get("pending", 0)) > 0:
			if int(f["founder"]) == player:
				box.add_child(_choice_block(es, fid))
			else:
				box.add_child(UiTheme.dim("Le fondateur fixe encore la nature, les doctrines et le premier précepte (avant le %s)." % GameCalendar.date_string(int(f["pending"])), 13))
			box.add_child(HSeparator.new())
			continue
		box.add_child(_doctrines_line(state, fid))
		var names := PackedStringArray()
		for d in f["precepts"]:
			names.append(String(Faiths.precept_def(String(d)).get("label", d)))
		var dl := UiTheme.paragraph("Préceptes : %s" % (", ".join(names) if not names.is_empty() else "aucun encore"), 760.0, 13)
		var tips := PackedStringArray()
		for d in f["precepts"]:
			var pd := Faiths.precept_def(String(d))
			tips.append("%s : %s" % [String(pd.get("label", d)), String(pd.get("text", ""))])
		dl.tooltip_text = "\n".join(tips)
		dl.mouse_filter = Control.MOUSE_FILTER_PASS
		box.add_child(dl)
		var free := Faiths.free_slots(state, fid)
		if free > 0:
			box.add_child(UiTheme.dim("%d précepte%s à choisir par %s." % [free, "s" if free > 1 else "", "le chef de foi" if Faiths.doctrine(state, fid, "chef") != "aucun" else "l'empire qui compte le plus de fidèles"], 13))
			if h == player:
				box.add_child(_precept_picker(es, fid))
		if h == player:
			var acts := _head_actions(es, fid)
			if acts != null:
				box.add_child(acts)
		box.add_child(HSeparator.new())
	return b


## Doctrines d'une foi, sur une ligne (le détail en infobulle).
static func _doctrines_line(state: GameState, fid: String) -> Control:
	var parts := PackedStringArray()
	var tips := PackedStringArray()
	for a in Faiths.AXES:
		var d := Faiths.doctrine_def(a, Faiths.doctrine(state, fid, a))
		var al := String(Faiths.data()["doctrines"][a]["label"])
		parts.append("%s %s" % [al, String(d.get("label", "?")).to_lower()])
		tips.append("%s : %s. %s" % [al, String(d.get("label", "?")), String(d.get("text", ""))])
	var l := UiTheme.paragraph("Doctrines : %s" % ", ".join(parts), 760.0, 13)
	l.tooltip_text = "\n".join(tips)
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	return l


## Le fondateur fixe sa foi : une nature parmi trois, une position par axe de doctrine, un premier
## précepte (un schisme garde doctrines et préceptes et ne choisit que sa nature).
static func _choice_block(es: EmpireScreens, fid: String) -> Control:
	var state := es._state
	var player := es._player
	var f := Faiths.faith(state, fid)
	var fresh := (f["precepts"] as Array).is_empty()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.add_child(UiTheme.paragraph("Fixez votre foi avant le %s (sinon le clergé choisit à votre place)." % GameCalendar.date_string(int(f["pending"])), 760.0, 13))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 6)
	box.add_child(grid)
	var picks := {}
	var nat_opt := OptionButton.new()
	nat_opt.focus_mode = Control.FOCUS_NONE
	var nats: Array = f.get("offer", [])
	for i in nats.size():
		var nd := FaithWars.nature_def(String(nats[i]))
		nat_opt.add_item(String(nd.get("label", nats[i])))
		nat_opt.set_item_tooltip(i, String(nd.get("text", "")))
	grid.add_child(UiTheme.dim("Nature", 13))
	grid.add_child(nat_opt)
	es.faith_buttons["choose_nature:" + fid] = nat_opt
	var axis_opts := {}
	var prec_ids: Array = []
	var prec_opt := OptionButton.new()
	if fresh:
		for a in Faiths.AXES:
			var o := OptionButton.new()
			o.focus_mode = Control.FOCUS_NONE
			var keys: Array = []
			var opts: Dictionary = Faiths.data()["doctrines"][a]["options"]
			for k in opts:
				o.add_item(String(opts[k]["label"]))
				o.set_item_tooltip(keys.size(), String(opts[k]["text"]))
				keys.append(String(k))
			o.select(maxi(0, keys.find(String(Faiths.DEFAULT_DOCTRINES[a]))))
			axis_opts[a] = [o, keys]
			grid.add_child(UiTheme.dim(String(Faiths.data()["doctrines"][a]["label"]), 13))
			grid.add_child(o)
			es.faith_buttons["choose_%s:%s" % [a, fid]] = o
		prec_opt.focus_mode = Control.FOCUS_NONE
		for pid in Faiths.precept_ids():
			if Faiths._precept_free(state, fid, String(pid)) != "":
				continue
			prec_opt.add_item(String(Faiths.precept_def(pid)["label"]))
			prec_opt.set_item_tooltip(prec_ids.size(), String(Faiths.precept_def(pid)["text"]))
			prec_ids.append(String(pid))
		grid.add_child(UiTheme.dim("Premier précepte", 13))
		grid.add_child(prec_opt)
		es.faith_buttons["choose_precept:" + fid] = prec_opt
	var desc := UiTheme.paragraph("", 760.0, 12)
	box.add_child(desc)
	var ok := _btn("Fixer la foi", "", "La nature, les doctrines et le premier précepte sont définitifs (un concile pourra changer une doctrine).")
	box.add_child(ok)
	es.faith_buttons["choose:" + fid] = ok
	var gather := func() -> Array:
		var nat := String(nats[nat_opt.selected]) if nat_opt.selected >= 0 and nat_opt.selected < nats.size() else ""
		var dc := {}
		for a in axis_opts:
			var o: OptionButton = axis_opts[a][0]
			dc[a] = String(axis_opts[a][1][o.selected]) if o.selected >= 0 else ""
		var pid := String(prec_ids[prec_opt.selected]) if fresh and prec_opt.selected >= 0 and prec_opt.selected < prec_ids.size() else ""
		return [nat, dc, pid]
	var upd := func(_i := 0) -> void:
		var g: Array = gather.call()
		var why := Faiths.check_choose(state, player, fid, g[0], g[1], g[2])
		ok.disabled = why != ""
		ok.tooltip_text = "La nature, les doctrines et le premier précepte sont définitifs (un concile pourra changer une doctrine)." + (("\n" + why) if why != "" else "")
		var lines := PackedStringArray()
		lines.append(String(FaithWars.nature_def(String(g[0])).get("text", "")))
		if String(g[2]) != "":
			lines.append("%s : %s" % [String(Faiths.precept_def(String(g[2]))["label"]), String(Faiths.precept_def(String(g[2]))["text"])])
		desc.text = "\n".join(lines)
	nat_opt.item_selected.connect(upd)
	prec_opt.item_selected.connect(upd)
	for a in axis_opts:
		(axis_opts[a][0] as OptionButton).item_selected.connect(upd)
	upd.call()
	ok.pressed.connect(func() -> void:
		var g: Array = gather.call()
		es.command_requested.emit(SimCommands.faith_choose(player, fid, g[0], g[1], g[2])))
	return box


## Choix d'un précepte, par famille (le chef de foi seulement).
static func _precept_picker(es: EmpireScreens, fid: String) -> Control:
	var state := es._state
	var player := es._player
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 6)
	var by := {}
	for pid in Faiths.precept_ids():
		var fam := String(Faiths.precept_def(pid)["family"])
		if not by.has(fam):
			by[fam] = []
		by[fam].append(pid)
	var cols := []
	for fam: Dictionary in Faiths.data()["precept_families"]:
		var l := Label.new()
		l.text = String(fam["label"])
		l.add_theme_color_override("font_color", UiTheme.GOLD)
		grid.add_child(l)
		cols.append(by.get(String(fam["id"]), []))
	var rows := 0
	for c: Array in cols:
		rows = maxi(rows, c.size())
	for r in rows:
		for c: Array in cols:
			if r >= c.size():
				grid.add_child(Control.new())
				continue
			var pid := String(c[r])
			var d := Faiths.precept_def(pid)
			var why := Faiths.check_precept(state, player, fid, pid)
			var tip := String(d["text"])
			if d.has("src"):
				tip += "\n(Inspiré de %s.)" % String(d["src"])
			var btn := _btn(String(d["label"]), why, tip)
			btn.custom_minimum_size = Vector2(200, 0)
			btn.pressed.connect(func() -> void: es.command_requested.emit(SimCommands.faith_precept(player, fid, pid)))
			grid.add_child(btn)
			es.faith_buttons["precept:%s:%s" % [fid, pid]] = btn
	return grid


static func _colonies_block(es: EmpireScreens) -> Control:
	var state := es._state
	var player := es._player
	var b := Widgets.Block.new("Croyances de vos colonies")
	var any := false
	var sf := Faiths.state_faith(state, player)
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner != player or not c.is_colony() or not c.is_established():
			continue
		any = true
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		b.body.add_child(row)
		var nb := Button.new()
		nb.flat = true
		nb.text = state.galaxy.get_planet(pid).display_name(state.galaxy)
		nb.custom_minimum_size = Vector2(200, 0)
		nb.alignment = HORIZONTAL_ALIGNMENT_LEFT
		nb.pressed.connect(func() -> void: es.planet_requested.emit(pid))
		row.add_child(nb)
		row.add_child(_bar(state, c, player))
		var t := UiTheme.dim(Faiths.colony_text(state, c, player), 12)
		t.custom_minimum_size = Vector2(360, 0)
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(t)
		var m := Faiths.majority(c)
		if sf != Faiths.LAICITE:
			var ml := UiTheme.dim("fidèle" if m == sf else "à convertir", 12)
			ml.add_theme_color_override("font_color", UiTheme.GOLD if m == sf else UiTheme.TEXT_DIM)
			row.add_child(ml)
		var hf := ""
		for fid in Faiths.ids(state):
			if int(Faiths.faith(state, fid)["holy"]) == pid:
				hf = fid
		if hf != "":
			var hl := UiTheme.dim("monde saint", 12)
			hl.add_theme_color_override("font_color", Faiths.color_of(state, hf).lightened(0.3))
			row.add_child(hl)
		if Research.fx_int(state, player, "faith_sacrifice") > 0:
			var sb := _btn("Sacrifice", FaithWars.check_sacrifice(state, player, pid), "Un fidèle monte à l'autel : zèle +%d, un habitant de moins." % Research.fx_int(state, player, "faith_sacrifice"))
			sb.pressed.connect(func() -> void: es.command_requested.emit(SimCommands.faith_sacrifice(player, pid)))
			row.add_child(sb)
			es.faith_buttons["sacrifice:%d" % pid] = sb
	if not any:
		b.body.add_child(UiTheme.dim("Aucune colonie.", 14))
	return b


## Barre des croyances d'une colonie (une couleur par foi, gris pour les cultes natals).
static func _bar(state: GameState, c: Colony, viewer := -1) -> Control:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 0)
	bar.custom_minimum_size = Vector2(160, 12)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var cnt := Faiths.visible_counts(state, c, viewer)
	var keys := cnt.keys()
	keys.sort()
	for fid in keys:
		var r := ColorRect.new()
		r.custom_minimum_size = Vector2(160.0 * float(cnt[fid]) / float(maxi(1, c.population)), 12)
		r.color = Color(0.35, 0.35, 0.33) if String(fid) == Faiths.NATIVE else Faiths.color_of(state, String(fid))
		bar.add_child(r)
	return bar


## Étiquettes d'une foi : nature, zèle, hérésie ou schisme, culte caché, croisade en cours.
static func _faith_tags(es: EmpireScreens, fid: String) -> Control:
	var state := es._state
	var f := Faiths.faith(state, fid)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var nd := FaithWars.nature_def(FaithWars.nature(state, fid))
	if not nd.is_empty():
		var nl := UiTheme.dim("Nature : %s" % String(nd["label"]), 13)
		nl.add_theme_color_override("font_color", UiTheme.GOLD)
		nl.tooltip_text = String(nd["text"])
		nl.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(nl)
	row.add_child(UiTheme.dim("Zèle %d" % FaithWars.zeal(state, fid), 13))
	var pf := Faiths.parent_of(state, fid)
	if pf != "":
		row.add_child(UiTheme.dim("hérésie de %s" % Faiths.name_of(state, pf), 13))
	elif String(f.get("schism_of", "")) != "":
		row.add_child(UiTheme.dim("schisme de %s" % Faiths.name_of(state, String(f["schism_of"])), 13))
	if FaithWars.is_secret(state, fid):
		row.add_child(UiTheme.dim("culte caché" + ("" if FaithWars.visible_to(state, fid, es._player) else " (fidèles invisibles chez vous)"), 13))
	var cr := FaithWars.crusade_of(state, fid)
	if not cr.is_empty():
		var te := state.get_empire(int(cr["target"]))
		var cl := UiTheme.dim("croisade contre %s" % (te.short_name() if te != null else "?"), 13)
		cl.add_theme_color_override("font_color", Color(0.95, 0.55, 0.4))
		row.add_child(cl)
	return row


## Actions du chef de foi : concile de doctrine, réunion et réécriture (Code saint), routes bénies
## (Voies sacrées), excommunication, croisade.
static func _head_actions(es: EmpireScreens, fid: String) -> Control:
	var state := es._state
	var player := es._player
	var box := HFlowContainer.new()
	box.add_theme_constant_override("h_separation", 10)
	box.add_theme_constant_override("v_separation", 6)
	if FaithWars.nature(state, fid) == "code_saint":
		for hid in Faiths.ids(state):
			if Faiths.parent_of(state, hid) != fid:
				continue
			var btn := _btn("Concile : réunir %s" % Faiths.name_of(state, hid), FaithWars.check_council(state, player, hid),
					"Ramène l'hérésie et ses fidèles dans la foi (%s)." % GameData.format_amounts(FaithWars.data()["heresy"]["council_cost"]))
			btn.pressed.connect(func() -> void: es.command_requested.emit(SimCommands.faith_council(player, hid)))
			box.add_child(btn)
			es.faith_buttons["council:" + hid] = btn
		var dg: Array = Faiths.faith(state, fid)["precepts"]
		if not dg.is_empty():
			var opt := OptionButton.new()
			opt.focus_mode = Control.FOCUS_NONE
			var ids: Array = []
			for did in Faiths.precept_ids():
				if Faiths._precept_free(state, fid, String(did)) == "":
					opt.add_item(String(Faiths.precept_def(did)["label"]))
					ids.append(did)
			box.add_child(opt)
			var old_label := String(Faiths.precept_def(String(dg[0])).get("label", dg[0]))
			var rb := _btn("Réécrire « %s »" % old_label, "",
					"Remplace le plus ancien précepte par celui choisi (%s)." % GameData.format_amounts(FaithWars.data()["heresy"]["rewrite_cost"]))
			var upd := func(i: int) -> void:
				var why := FaithWars.check_rewrite(state, player, fid, String(ids[i])) if i >= 0 and i < ids.size() else "aucun précepte choisi"
				rb.disabled = why != ""
				rb.tooltip_text = "Remplace le plus ancien précepte par celui choisi (%s).%s" % [GameData.format_amounts(FaithWars.data()["heresy"]["rewrite_cost"]), ("\n" + why) if why != "" else ""]
			opt.item_selected.connect(upd)
			upd.call(opt.selected)
			rb.pressed.connect(func() -> void:
				if opt.selected >= 0 and opt.selected < ids.size():
					es.command_requested.emit(SimCommands.faith_rewrite(player, fid, String(ids[opt.selected]))))
			box.add_child(rb)
			es.faith_buttons["rewrite:" + fid] = rb
	box.add_child(_concile_row(es, fid))
	if FaithWars.nature(state, fid) == "voies_sacrees":
		_lane_buttons(es, fid, box)
	if Faiths.state_faith(state, player) == fid and Faiths.has_head(state, fid):
		for e in state.empires:
			if e.eliminated or e.id == player or Faiths.state_faith(state, e.id) != fid:
				continue
			var target := e.id
			var xd: Dictionary = FaithWars.data()["excommunication"]
			var xb := _btn("Excommunier %s" % e.short_name(), FaithWars.check_excom(state, player, target),
					"Dix ans : opinion %d de tous les fidèles, stabilité %d chez lui, cible légitime de croisade (%s)." % [int(xd["op"]), int(xd["stab"]), GameData.format_amounts(xd["cost"])])
			xb.pressed.connect(func() -> void: es.command_requested.emit(SimCommands.faith_excom(player, target)))
			box.add_child(xb)
			es.faith_buttons["excom:%d" % target] = xb
	if Faiths.state_faith(state, player) == fid:
		for e in state.empires:
			if e.eliminated or e.id == player or not state.get_empire(player).contacts.has(e.id):
				continue
			var why := FaithWars.casus(state, player, e.id)
			if why == "":
				continue
			var btn := _btn("Croisade contre %s" % e.short_name(), FaithWars.check_crusade(state, player, e.id),
					"Motif : %s. Guerre déclarée, les empires de la foi sont appelés à vous suivre (%s)." % [why, GameData.format_amounts(FaithWars.crusade_cost(state, fid))])
			var target := e.id
			btn.pressed.connect(func() -> void: es.command_requested.emit(SimCommands.faith_crusade(player, target)))
			box.add_child(btn)
			es.faith_buttons["crusade:%d" % e.id] = btn
	return box if box.get_child_count() > 0 else null


## Concile : changer une position de doctrine (un axe, une option, un bouton).
static func _concile_row(es: EmpireScreens, fid: String) -> Control:
	var state := es._state
	var player := es._player
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var choices: Array = []
	var opt := OptionButton.new()
	opt.focus_mode = Control.FOCUS_NONE
	for a in Faiths.AXES:
		var opts: Dictionary = Faiths.data()["doctrines"][a]["options"]
		for k in opts:
			if Faiths.doctrine(state, fid, a) == String(k) or FaithNatures.doctrine_block(FaithWars.nature(state, fid), a, String(k)) != "":
				continue
			opt.add_item("%s : %s" % [String(Faiths.data()["doctrines"][a]["label"]), String(opts[k]["label"])])
			opt.set_item_tooltip(choices.size(), String(opts[k]["text"]))
			choices.append([a, String(k)])
	row.add_child(opt)
	var cost := GameData.format_amounts(FaithWars.concile_cost(state, fid))
	var cb := _btn("Réunir un concile", "", "Change une doctrine de la foi (%s, un concile tous les cinq ans)." % cost)
	var upd := func(i: int) -> void:
		var why := FaithWars.check_concile(state, player, fid, String(choices[i][0]), String(choices[i][1])) if i >= 0 and i < choices.size() else "aucune doctrine choisie"
		cb.disabled = why != ""
		cb.tooltip_text = "Change une doctrine de la foi (%s, un concile tous les cinq ans).%s" % [cost, ("\n" + why) if why != "" else ""]
	opt.item_selected.connect(upd)
	upd.call(opt.selected)
	cb.pressed.connect(func() -> void:
		if opt.selected >= 0 and opt.selected < choices.size():
			es.command_requested.emit(SimCommands.faith_concile(player, fid, String(choices[opt.selected][0]), String(choices[opt.selected][1]))))
	row.add_child(cb)
	es.faith_buttons["concile:" + fid] = cb
	return row


## Voies sacrées : bénir des routes au départ de vos systèmes, et régler celles déjà bénies.
static func _lane_buttons(es: EmpireScreens, fid: String, box: Control) -> void:
	var state := es._state
	var player := es._player
	var nd: Dictionary = FaithWars.data()["natures"]
	var modes := {"open": "ouverte", "closed": "fermée aux infidèles", "toll": "à péage"}
	for key in FaithWars.blessed_of(state, fid):
		var ends := String(key).split("-")
		var label := "%s ↔ %s" % [state.galaxy.systems[int(ends[0])].system_name, state.galaxy.systems[int(ends[1])].system_name]
		var cur := String(state.faiths["blessed"][key]["mode"])
		for m in ["open", "closed", "toll"]:
			if m == cur:
				continue
			var mode := String(m)
			var k := String(key)
			var mb := _btn("%s : %s" % [label, modes[mode]], FaithWars.check_lane_mode(state, player, k, mode), "Route bénie, aujourd'hui %s. Fermée : les infidèles y vont à %d %% de vitesse ; à péage : ils paient %d d'énergie au chef de foi." % [modes[cur], int(nd["voies_closed_pct"]), int(nd["voies_toll"])])
			mb.pressed.connect(func() -> void: es.command_requested.emit(SimCommands.faith_lane(player, k, mode)))
			box.add_child(mb)
			es.faith_buttons["lane:%s:%s" % [k, mode]] = mb
	if Faiths.head(state, fid) != player:
		return
	var shown := 0
	for sid in state.galaxy.systems.size():
		if shown >= 6 or state.system_owner(sid) != player:
			continue
		for nb in state.galaxy.systems[sid].neighbors:
			if shown >= 6:
				break
			var a := int(sid)
			var b := int(nb)
			if FaithWars.check_bless(state, player, a, b) != "" or (a > b and state.system_owner(b) == player):
				continue
			var bb := _btn("Bénir %s ↔ %s" % [state.galaxy.systems[a].system_name, state.galaxy.systems[b].system_name], "", "Les fidèles y vont %d %% plus vite et la foi y passe deux fois plus (%s, %d routes au plus)." % [int(nd["voies_speed_pct"]) - 100, GameData.format_amounts(nd["voies_bless_cost"]), int(nd["voies_max"])])
			bb.pressed.connect(func() -> void: es.command_requested.emit(SimCommands.faith_bless(player, a, b)))
			box.add_child(bb)
			es.faith_buttons["bless:%s" % FaithWars.lane_key(a, b)] = bb
			shown += 1


static func _btn(text: String, why: String, tip: String) -> Button:
	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	btn.text = text
	btn.disabled = why != ""
	btn.tooltip_text = tip + (("\n" + why) if why != "" else "")
	return btn


## Missions : celles de l'empire, les systèmes où prêcher, et les missions étrangères à chasser.
static func _missions_block(es: EmpireScreens) -> Control:
	var state := es._state
	var player := es._player
	var md: Dictionary = FaithWars.data()["missions"]
	var b := Widgets.Block.new("Missions")
	b.body.add_child(UiTheme.paragraph("Une mission prêche votre foi d'État dans un système pendant un an (+%d de pression, %s, %d à la fois). Le maître du système peut la chasser par une mission d'inquisition (%s), qui le protège deux ans." % [
			int(md["pressure"]), GameData.format_amounts(md["cost"]), int(md["max"]), GameData.format_amounts(md["ward_cost"])], 760.0, 13))
	var sf := Faiths.state_faith(state, player)
	for m in FaithWars.missions_by(state, player):
		var sid := int(m["sid"])
		b.body.add_child(UiTheme.dim("En cours : %s, %s, jusqu'au %s." % [state.galaxy.systems[sid].system_name, Faiths.name_of(state, String(m["fid"])),
				GameCalendar.date_string(int(m["end"]))], 13))
	if sf == Faiths.LAICITE:
		b.body.add_child(UiTheme.dim("Il faut une foi d'État pour envoyer des missionnaires.", 13))
	else:
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 10)
		flow.add_theme_constant_override("v_separation", 6)
		for sid in FaithWars.mission_targets(state, player, sf, 6):
			var btn := _btn("Prêcher à %s" % state.galaxy.systems[sid].system_name, FaithWars.check_mission(state, player, sid), "Envoie une mission pour un an.")
			var target := int(sid)
			btn.pressed.connect(func() -> void: es.command_requested.emit(SimCommands.faith_mission(player, target)))
			flow.add_child(btn)
			es.faith_buttons["mission:%d" % sid] = btn
		if flow.get_child_count() > 0:
			b.body.add_child(flow)
		else:
			b.body.add_child(UiTheme.dim("Aucun système à convertir à portée (5 sauts).", 13))
	var seen := {}
	for m in FaithWars._missions(state):
		var sid := int(m["sid"])
		if int(m["by"]) == player or state.system_owner(sid) != player or seen.has(sid):
			continue
		seen[sid] = true
		var by := state.get_empire(int(m["by"]))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		row.add_child(UiTheme.dim("Missionnaires de %s à %s (%s)." % [by.short_name(), state.galaxy.systems[sid].system_name, Faiths.name_of(state, String(m["fid"]))], 13))
		var btn := _btn("Chasser", FaithWars.check_ward(state, player, sid), "Mission d'inquisition : chasse les missions étrangères et protège le système deux ans.")
		btn.pressed.connect(func() -> void: es.command_requested.emit(SimCommands.faith_ward(player, sid)))
		row.add_child(btn)
		es.faith_buttons["ward:%d" % sid] = btn
		b.body.add_child(row)
	return b


## Culte du Je : les drones qui pensent « je » sur les colonies de la ruche.
static func _je_block(es: EmpireScreens) -> Control:
	var state := es._state
	var player := es._player
	var jd: Dictionary = FaithWars.data()["je"]
	var b := Widgets.Block.new("Culte du Je")
	b.body.add_child(UiTheme.paragraph("Parfois, un drone pense « je ». Laissés à eux-mêmes, les dissidents arrêtent la ponte dès %d, et à %d la colonie se détache de la ruche. Les écraser coûte des drones et rien ne repousse pendant trois ans ; les tolérer plafonne le culte à %d et ces esprits libres rapportent du Savoir." % [
			int(jd["stop_growth_at"]), int(jd["max"]), int(jd["tolerated_max"])], 760.0, 13))
	var any := false
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		var j := FaithWars.je(state, pid)
		if c.owner != player or j.is_empty():
			continue
		any = true
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var nb := Button.new()
		nb.flat = true
		nb.text = state.galaxy.get_planet(pid).display_name(state.galaxy)
		nb.custom_minimum_size = Vector2(200, 0)
		nb.alignment = HORIZONTAL_ALIGNMENT_LEFT
		nb.pressed.connect(func() -> void: es.planet_requested.emit(pid))
		row.add_child(nb)
		row.add_child(UiTheme.dim("%d dissident%s%s" % [int(j["n"]), "s" if int(j["n"]) > 1 else "", ", tolérés" if bool(j["tol"]) else (", la ponte s'arrête" if FaithWars.je_blocks_growth(state, c) else "")], 13))
		for what in ["ecraser", "tolerer"]:
			var btn := _btn("Écraser" if what == "ecraser" else "Tolérer", FaithWars.check_je(state, player, pid, what),
					"Un drone sur trois dissidents disparaît, plus rien pendant trois ans." if what == "ecraser" else "Les dissidents restent, plafonnés, et pensent pour la ruche.")
			var w := String(what)
			btn.pressed.connect(func() -> void: es.command_requested.emit(SimCommands.faith_je(player, pid, w)))
			row.add_child(btn)
			es.faith_buttons["je:%d:%s" % [pid, what]] = btn
		b.body.add_child(row)
	if not any:
		b.body.add_child(UiTheme.dim("La ruche pense d'une seule voix. Pour l'instant.", 13))
	return b
