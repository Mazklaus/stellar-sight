class_name PeoplesScreen
extends RefCounted
## Onglet Peuples du domaine Empire (refonte, C3) : les espèces de l'empire en cartes, avec portrait,
## effectifs, rôle, intégration et statut. Colonne de gauche : totaux, accueil des réfugiés, diasporas.
## Construit dans les conteneurs d'EmpireScreens, dont il reprend les aides.

const CARD_WIDTH := 300.0


## Une entrée par espèce de l'empire, la plus nombreuse d'abord :
## [{fid, label, count, pct, founder, colonist, collection, integration, status}].
static func cards(state: GameState, player: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var cnt := Peoples.empire_counts(state, player)
	var total := 0
	for k in cnt:
		total += int(cnt[k])
	var keys := cnt.keys()
	keys.sort_custom(func(a: String, b: String) -> bool:
		return int(cnt[a]) > int(cnt[b]) or (int(cnt[a]) == int(cnt[b]) and a < b))
	var own := Peoples.founder_of(state, player)
	var colonists := Peoples.colonist_species(state, player)
	var coll := {}
	for entry: Dictionary in Peoples.collections(state, player):
		coll[entry["species"]] = entry
	for fid: String in keys:
		@warning_ignore("integer_division")
		out.append({"fid": fid, "label": Peoples.label(fid), "count": int(cnt[fid]),
				"pct": int(cnt[fid]) * 100 / maxi(1, total), "founder": fid == own, "colonist": colonists.has(fid),
				"collection": coll.get(fid, {}), "integration": Peoples.empire_integration(state, player, fid),
				"status": Peoples.status(state, player, fid)})
	return out


static func signature(es: EmpireScreens) -> String:
	var st := es._state
	@warning_ignore("integer_division")
	return "%s|%d|%s|%s|%s" % [str(cards(st, es._player)), st.tick / 30, Movements.policy(st, es._player),
			str(Movements.claim(st, es._player)), str(Peoples.rights_demand(st, es._player))]


static func build(es: EmpireScreens) -> void:
	var state := es._state
	var player := es._player
	es._peoples_sig = signature(es)
	es.peoples_buttons.clear()
	var me := state.get_empire(player)
	var list := cards(state, player)
	var total := 0
	for c: Dictionary in list:
		total += int(c["count"])

	# Colonne de gauche.
	es._side_header(GameData.portrait_art(me.faction_id), "Peuples", me.color(), "faction")
	var g := es._grid()
	es._side_box.add_child(g)
	es._key_value(g, "Espèces", str(list.size()))
	es._key_value(g, "Habitants", str(total))
	var citizens := 0
	for c: Dictionary in list:
		if String(c["status"]) == "citoyens":
			citizens += int(c["count"])
	@warning_ignore("integer_division")
	es._key_value(g, "Citoyens", "%d %%" % (citizens * 100 / maxi(1, total)))
	es._side_box.add_child(UiTheme.paragraph("Chaque espèce garde son corps, ses biomes et ses talents. Avec %d habitants, elle peut fonder des colonies ; à %s, elle donne un bonus de collection." % [
			int(Peoples.data().get("colonize_min", 2)), "/".join(PackedStringArray(Array(Peoples.data().get("collection_tiers", [10, 25, 50])).map(func(x: Variant) -> String: return str(int(x)))))],
			EmpireScreens.SIDE_WIDTH - 24.0, 12))
	es._build_moves_side()

	# Contenu : les cartes.
	var block := Widgets.Block.new("Peuples de l'empire")
	block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	block.size_flags_vertical = Control.SIZE_EXPAND_FILL
	es._content.add_child(block)
	var d := Peoples.rights_demand(state, player)
	if not d.is_empty():
		var dl := UiTheme.paragraph("Doléance : les %s réclament la citoyenneté avant le %s." % [Peoples.label(String(d["fid"])), GameCalendar.date_string(int(d["end"]))], 900.0, 14)
		dl.add_theme_color_override("font_color", UiTheme.WARN)
		block.body.add_child(dl)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	block.body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	block.body.add_child(scroll)
	var flow := HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.add_theme_constant_override("h_separation", 18)
	flow.add_theme_constant_override("v_separation", 18)
	scroll.add_child(flow)
	for c: Dictionary in list:
		flow.add_child(_card(es, c))


static func _card(es: EmpireScreens, c: Dictionary) -> Control:
	var state := es._state
	var player := es._player
	var fid := String(c["fid"])
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.box(Color(1, 1, 1, 0.035), UiTheme.LINE, 0, 1))
	panel.custom_minimum_size = Vector2(CARD_WIDTH, 0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)
	var tint := Color.html(String(GameData.faction(fid).get("color", "#66ccdd")))
	var art := Widgets.ArtSlot.new(GameData.portrait_art(fid), Vector2(CARD_WIDTH, 130), tint, "faction")
	art.set_caption(String(c["label"]), 24)
	col.add_child(art)
	var pad := MarginContainer.new()
	for side in ["left", "right", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 12)
	col.add_child(pad)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	pad.add_child(body)

	var head := HBoxContainer.new()
	var n := Label.new()
	n.theme_type_variation = &"Numbers"
	n.add_theme_font_size_override("font_size", 22)
	n.text = str(c["count"])
	head.add_child(n)
	var share := UiTheme.dim("  habitants, %d %% de l'empire" % int(c["pct"]), 13)
	share.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(share)
	body.add_child(head)

	var role := "Trop peu nombreux pour fonder une colonie"
	var role_col := UiTheme.TEXT_DIM
	if bool(c["founder"]):
		role = "Peuple fondateur"
		role_col = UiTheme.GOLD
	elif bool(c["colonist"]):
		role = "Peut fonder des colonies"
		role_col = UiTheme.TEXT
	var rl := Label.new()
	rl.text = role
	rl.add_theme_font_size_override("font_size", 14)
	rl.add_theme_color_override("font_color", role_col)
	body.add_child(rl)
	var en: Dictionary = c["collection"]
	var cl := Label.new()
	cl.add_theme_font_size_override("font_size", 14)
	if en.is_empty():
		cl.text = "Pas de bonus de collection"
		cl.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	else:
		cl.text = "Collection %s : +%d %% %s" % [["I", "II", "III"][clampi(int(en["tier"]) - 1, 0, 2)], int(en["pct"]),
				GameData.resource_label(String(en["resource"])).to_lower()]
		cl.add_theme_color_override("font_color", UiTheme.GOOD)
	body.add_child(cl)

	if bool(c["founder"]):
		body.add_child(UiTheme.dim("Citoyens de droit.", 13))
		return panel
	var integ := int(c["integration"])
	if integ >= 0:
		var irow := HBoxContainer.new()
		irow.add_theme_constant_override("separation", 8)
		irow.tooltip_text = "Intégration moyenne des %s dans l'empire : elle monte chaque année, sauf pour les assujettis et les expulsés. Sous 50 %%, ils produisent moins et pèsent sur la stabilité." % c["label"]
		var il := UiTheme.dim("Intégration", 13)
		irow.add_child(il)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.max_value = 100
		bar.value = integ
		bar.custom_minimum_size = Vector2(0, 6)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		irow.add_child(bar)
		var iv := Label.new()
		iv.theme_type_variation = &"Numbers"
		iv.text = "%d %%" % integ
		iv.add_theme_color_override("font_color", UiTheme.WARN if integ < 50 else UiTheme.TEXT)
		irow.add_child(iv)
		body.add_child(irow)

	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 8)
	var sl := UiTheme.dim("Statut", 13)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	srow.add_child(sl)
	var ob := OptionButton.new()
	ob.custom_minimum_size = Vector2(160, 0)
	var cur := String(c["status"])
	var ids: Array[String] = []
	for st in Peoples.allowed_statuses(state, player, fid):
		ob.add_item(Peoples.status_label(st))
		ob.set_item_tooltip(ids.size(), String(Peoples.status_def(st).get("text", "")))
		ids.append(st)
	ob.selected = ids.find(cur)
	var nx := Peoples.next_change(state, player, fid)
	if state.tick < nx:
		ob.disabled = true
		ob.tooltip_text = "Statut changé récemment : prochain changement le %s." % GameCalendar.date_string(nx)
	else:
		@warning_ignore("integer_division")
		ob.tooltip_text = "Statut des %s (modifiable tous les %d ans)." % [c["label"], int(Peoples.data().get("status_days", 1800)) / 360]
	ob.item_selected.connect(func(i: int) -> void:
		if ids[i] != cur:
			es.command_requested.emit(SimCommands.peoples_status(player, fid, ids[i]))
			ob.disabled = true)
	srow.add_child(ob)
	body.add_child(srow)
	es.peoples_buttons[fid] = ob
	var rights := String(Peoples.status_def(cur).get("text", ""))
	if rights != "":
		var rp := UiTheme.paragraph(rights, CARD_WIDTH - 24.0, 12)
		rp.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
		body.add_child(rp)
	return panel
