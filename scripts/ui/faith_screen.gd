class_name FaithScreen
extends RefCounted
## Écran Foi (Y) : la religion de l'empire (voir Faiths).
## Colonne de gauche : foi d'État, culte natal, grandes fois en jeu, délai avant un changement.
## Contenu : le choix de la foi d'État (laïcité, incroyance, grandes fois), les grandes fois de la
## galaxie (fondateur, monde saint, fidèles, chef de foi, dogmes ; le chef choisit les dogmes à chaque
## palier), puis les croyances de chaque colonie de l'empire.
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
	else:
		col.add_child(_state_block(es))
	col.add_child(_faiths_block(es))
	col.add_child(_colonies_block(es))


## Ce qui change l'écran : mois, fois et dogmes, foi d'État, fidèles de l'empire.
static func signature(es: EmpireScreens) -> String:
	var state := es._state
	if not state.faith_on:
		return "off"
	var mine := []
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner == es._player:
			mine.append(c.faith)
	@warning_ignore("integer_division")
	return "%d|%s|%s|%s" % [state.tick / 30, str(state.faiths["list"]), str(state.faiths["state"]), str(mine)]


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
		box.add_child(UiTheme.dim("%s, %s. Monde saint : %s. %d fidèles. Chef de foi : %s." % [
				founder.display_name() if known else "Un empire inconnu", String(Faiths.data()["vias"].get(String(f["via"]), "")),
				holy.display_name(state.galaxy), Faiths.followers(state, fid),
				"vous" if h == player else (state.get_empire(h).short_name() if h >= 0 else "personne")], 13))
		var names := PackedStringArray()
		for d in f["dogmas"]:
			names.append(String(Faiths.dogma_def(String(d))["label"]))
		var dl := UiTheme.paragraph("Dogmes : %s" % (", ".join(names) if not names.is_empty() else "aucun encore"), 760.0, 13)
		box.add_child(dl)
		var free := Faiths.free_slots(state, fid)
		if free > 0:
			box.add_child(UiTheme.dim("%d dogme%s à choisir par le chef de foi." % [free, "s" if free > 1 else ""], 13))
			if h == player:
				box.add_child(_dogma_picker(es, fid))
		box.add_child(HSeparator.new())
	return b


## Choix d'un dogme, par famille (le chef de foi seulement).
static func _dogma_picker(es: EmpireScreens, fid: String) -> Control:
	var state := es._state
	var player := es._player
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 6)
	var by := {}
	for did in Faiths.dogma_ids():
		var fam := String(Faiths.dogma_def(did)["family"])
		if not by.has(fam):
			by[fam] = []
		by[fam].append(did)
	var cols := []
	for fam: Dictionary in Faiths.data()["families"]:
		var l := Label.new()
		l.text = String(fam["label"])
		l.add_theme_color_override("font_color", UiTheme.GOLD)
		l.tooltip_text = String(fam["text"])
		l.mouse_filter = Control.MOUSE_FILTER_PASS
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
			var did := String(c[r])
			var d := Faiths.dogma_def(did)
			var btn := Button.new()
			btn.focus_mode = Control.FOCUS_NONE
			btn.text = String(d["label"])
			btn.custom_minimum_size = Vector2(200, 0)
			var why := Faiths.check_dogma(state, player, fid, did)
			btn.disabled = why != ""
			var tip := String(d["text"])
			if d.has("ck3"):
				tip += "\n(Inspiré de Crusader Kings III : %s.)" % String(d["ck3"])
			if why != "":
				tip += "\n" + why
			btn.tooltip_text = tip
			btn.pressed.connect(func() -> void: es.command_requested.emit(SimCommands.faith_dogma(player, fid, did)))
			grid.add_child(btn)
			es.faith_buttons["dogma:%s:%s" % [fid, did]] = btn
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
		row.add_child(_bar(state, c))
		var t := UiTheme.dim(Faiths.colony_text(state, c), 12)
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
	if not any:
		b.body.add_child(UiTheme.dim("Aucune colonie.", 14))
	return b


## Barre des croyances d'une colonie (une couleur par foi, gris pour les cultes natals).
static func _bar(state: GameState, c: Colony) -> Control:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 0)
	bar.custom_minimum_size = Vector2(160, 12)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var cnt := Faiths.counts(c)
	var keys := cnt.keys()
	keys.sort()
	for fid in keys:
		var r := ColorRect.new()
		r.custom_minimum_size = Vector2(160.0 * float(cnt[fid]) / float(maxi(1, c.population)), 12)
		r.color = Color(0.35, 0.35, 0.33) if String(fid) == Faiths.NATIVE else Faiths.color_of(state, String(fid))
		bar.add_child(r)
	return bar
