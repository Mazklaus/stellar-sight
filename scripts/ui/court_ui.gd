class_name CourtScreen
extends RefCounted
## Onglet « La Cour » de l'écran Trône (voir Court) : grands offices et postes mineurs, Grandes Maisons
## (vocation, siège, fiefs, faveur et son détail, désirs, membres, rivales), missions, faste et train de
## la cour, grande fête, Frondes et leviers. Lit l'état, n'émet que des ordres « court_act ».

const W := ThroneScreen.W
const GOLD := ThroneScreen.GOLD


static func build(es: EmpireScreens) -> void:
	var state := es._state
	var player := es._player
	var en := Court.entry(state, player)
	var wd := Court.words(state, player)
	var g := es._grid()
	es._side_box.add_child(g)
	var ft := CourtBridges.faste_tier(state, player)
	es._key_value(g, String(wd["plural"]), str(Court.houses(state, player).size()))
	es._key_value(g, "Faste", "%d (%s)" % [int(en["faste"]), String(ft.get("label", "cour modeste"))])
	if CourtBridges.style_on(state, player):
		es._key_value(g, "Style", "%s : %s" % [String(CourtBridges.style_def(state, player)["label"]), String(CourtBridges.style_def(state, player)["text"])])
	var up := CourtBridges.train_upkeep(state, player)
	if up > 0:
		es._key_value(g, "Train de la cour", "%d énergie / mois" % up)
	if Court.peaceful(state):
		es._key_value(g, "Réglage", "Apaisées (pas de Fronde)")
	var tl := Court.talent_labels(state, player)
	if not tl.is_empty():
		es._side_box.add_child(HSeparator.new())
		es._side_box.add_child(UiTheme.paragraph("\n".join(tl), EmpireScreens.SIDE_WIDTH - 24.0, 12))

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	es._content.add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 18)
	scroll.add_child(col)
	_offices_block(es, col, state, player, en)
	for h: Dictionary in Court.houses(state, player):
		_house_block(es, col, state, player, en, h)
	_faste_block(es, col, state, player, en)


## Largeur d'un emplacement d'office.
const SLOT_CARD := 236.0


static func _offices_block(es: EmpireScreens, col: VBoxContainer, state: GameState, player: int, en: Dictionary) -> void:
	var b := Widgets.Block.new("Grands offices")
	col.add_child(b)
	b.body.add_child(UiTheme.paragraph("Les titulaires viennent des %s ou de vos héros. Nommer flatte une maison ; révoquer l'offense. Une maison sans office s'aigrit." % String(Court.words(state, player)["plural"]).to_lower(), W, 13))
	# Un emplacement par office : le titulaire dedans, ou « vacant » bien visible.
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 12)
	flow.add_theme_constant_override("v_separation", 12)
	b.body.add_child(flow)
	for oid in Court.office_ids(state, player):
		var od := Court.office_def(oid)
		var o := Court.holder(state, player, oid)
		var apt_label := String(Rulers.data()["aptitudes"][String(od["apt"])]["label"])
		var acts := _slot(flow, Court.office_label(state, player, oid), "" if o.is_empty() else Court.holder_name(state, player, o),
				"" if o.is_empty() else "%s %d" % [apt_label, Court.office_apt(state, player, oid)], String(od.get("text", "")), true)
		var items: Array = []
		for h: Dictionary in Court.houses(state, player):
			for m: Dictionary in h["members"]:
				items.append(["%s %s (%s %d)" % [String(m["name"]), String(h["name"]), apt_label.left(3), int(Court.apts(m)[String(od["apt"])])],
						SimCommands.court_act(player, "appoint", int(m["id"]), 0, oid)])
		for hid in Heroes.ids_of(state, player):
			var hh: Dictionary = state.heroes[hid]
			items.append(["Héros : %s" % String(hh["name"]), SimCommands.court_act(player, "appoint", hid, 1, oid)])
		_menu(es, acts, "Nommer…", items)
		if not o.is_empty():
			ThroneScreen._button(es, acts, "Libérer", SimCommands.court_act(player, "vacate", -1, -1, oid), "court:vacate:" + oid)
	for p: Dictionary in Court.data()["minor_posts"]:
		if bool(p.get("megas", false)) and not Megastructures.enabled(state):
			continue  # Grand Architecte : seulement avec les mégastructures
		var mid := int((en["minor"] as Dictionary).get(String(p["id"]), -1))
		var m2 := Court.member(state, player, mid)
		var acts2 := _slot(flow, String(p["label"]), "" if m2.is_empty() else "%s %s" % [String(m2["name"]), String(Court.house_of_member(state, player, mid)["name"])],
				"", String(p["text"]), false)
		var items2: Array = []
		for h: Dictionary in Court.houses(state, player):
			for m: Dictionary in h["members"]:
				items2.append(["%s %s (%d)" % [String(m["name"]), String(h["name"]), int(Court.apts(m)[String(p["apt"])])], SimCommands.court_act(player, "minor", int(m["id"]), -1, String(p["id"]))])
		_menu(es, acts2, "Nommer…", items2)


## Emplacement d'un office : titre, titulaire (ou « Vacant »), aptitude. Rend la rangée des boutons.
static func _slot(flow: Control, title: String, holder: String, apt: String, tip: String, major: bool) -> HBoxContainer:
	var vacant := holder == ""
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiTheme.box(Color(1, 1, 1, 0.05 if major else 0.025), UiTheme.WARN if vacant else UiTheme.LINE, 0, 1))
	card.custom_minimum_size = Vector2(SLOT_CARD, 0)
	card.tooltip_text = tip
	flow.add_child(card)
	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 10)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(pad)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(box)
	box.add_child(UiTheme.dim(title.to_upper(), 12))
	var n := Label.new()
	n.text = "Vacant" if vacant else holder
	n.clip_text = true
	n.custom_minimum_size = Vector2(SLOT_CARD - 20.0, 0)
	n.add_theme_font_size_override("font_size", 16)
	n.add_theme_color_override("font_color", UiTheme.WARN if vacant else UiTheme.TEXT)
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(n)
	box.add_child(UiTheme.dim(apt if apt != "" else " ", 12))
	var acts := HBoxContainer.new()
	acts.add_theme_constant_override("separation", 8)
	box.add_child(acts)
	return acts


## Blason d'une maison : écu à sa couleur, partition tirée de son identifiant.
class Blazon:
	extends Control
	var color := Color.WHITE
	var pattern := 0

	func _init(col: Color, seed_id: int, side := 34.0) -> void:
		color = col
		pattern = absi(seed_id) % 4
		custom_minimum_size = Vector2(side, side * 1.15)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func outline() -> PackedVector2Array:
		var w := size.x
		var h := size.y
		return PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h * 0.55), Vector2(w * 0.5, h), Vector2(0, h * 0.55)])

	func _draw() -> void:
		var pts := outline()
		draw_colored_polygon(pts, color.darkened(0.45))
		var w := size.x
		var h := size.y
		var light := color.lightened(0.1)
		match pattern:
			0:
				draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w * 0.5, 0), Vector2(w * 0.5, h), Vector2(0, h * 0.55)]), light)
			1:
				draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h * 0.3), Vector2(0, h * 0.3)]), light)
			2:
				draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w * 0.3, 0), Vector2(w, h * 0.45), Vector2(w, h * 0.55), Vector2(w * 0.8, h * 0.72), Vector2(0, h * 0.2)]), light)
			_:
				draw_colored_polygon(PackedVector2Array([Vector2(w * 0.5, h * 0.15), Vector2(w * 0.8, h * 0.42), Vector2(w * 0.5, h * 0.72), Vector2(w * 0.2, h * 0.42)]), light)
		pts.append(pts[0])
		draw_polyline(pts, color.lightened(0.35), 1.2, true)


static func _house_block(es: EmpireScreens, col: VBoxContainer, state: GameState, player: int, en: Dictionary, h: Dictionary) -> void:
	var v := Court.voc_def(String(h["voc"]))
	var t := Court.tier(h)
	var hid := int(h["id"])
	var b := Widgets.Block.new("%s %s" % [String(Court.words(state, player)["one"]), String(h["name"])])
	b.heading.add_theme_color_override("font_color", Color(String(h["color"])))
	col.add_child(b)
	var fav := Label.new()
	fav.text = "%s  ·  faveur %d (%s)%s%s" % [String(v.get("label", "")), Court.favor(h), String(t["label"]).to_lower(),
			"  ·  liée au trône" if int(h.get("kin", 0)) == 1 else "",
			"  ·  EN %s" % String(Court.words(state, player)["fronde"]).to_upper() if int((en["fronde"] as Dictionary).get(str(hid), 0)) > state.tick else ""]
	fav.add_theme_color_override("font_color", Color(String(t.get("color", "#b0b0b0"))))
	var tip := PackedStringArray()
	for p in h.get("parts", []):
		tip.append("%s : %+d" % [String(p[0]), int(p[1])])
	fav.tooltip_text = "\n".join(tip) if not tip.is_empty() else "Rien ne pèse sur sa faveur."
	fav.mouse_filter = Control.MOUSE_FILTER_STOP
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	head.add_child(Blazon.new(Color(String(h["color"])), hid))
	fav.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(fav)
	b.body.add_child(head)
	b.body.add_child(UiTheme.paragraph("%s Siège : %s." % [String(v.get("text", "")), String(v.get("seat_text", ""))], W, 13))
	var fs := Court.fiefs_of(state, player, hid)
	var fn := PackedStringArray()
	for sid in fs:
		fn.append(String(state.galaxy.systems[sid].system_name) + (" (siège)" if sid == int(h["seat"]) else ""))
	b.body.add_child(UiTheme.paragraph("Fiefs : %s." % (", ".join(fn) if not fn.is_empty() else "aucun pour l'instant"), W, 13))
	var likes := PackedStringArray()
	for c: Dictionary in v.get("likes", []):
		likes.append(String(c.get("label", "")))
	var dis := PackedStringArray()
	for c: Dictionary in v.get("dislikes", []):
		dis.append(String(c.get("label", "")))
	var gl := PackedStringArray()
	for gd in v.get("goods", []):
		gl.append(Goods.label(String(gd)))
	b.body.add_child(UiTheme.dim("Aime : %s. Déteste : %s. Luxes : %s." % [", ".join(likes), ", ".join(dis), ", ".join(gl)], 12))
	var rel := PackedStringArray()
	for rid in h.get("rivals", []):
		rel.append("rivale de %s" % String(Court.house(state, player, int(rid)).get("name", "?")))
	for fid in h.get("friends", []):
		rel.append("amie de %s" % String(Court.house(state, player, int(fid)).get("name", "?")))
	if (en["levers"] as Dictionary).has(str(hid)):
		rel.append("nous tenons un secret sur elle")
	if not rel.is_empty():
		b.body.add_child(UiTheme.dim(Court.ucfirst(", ".join(rel)), 12))
	for m: Dictionary in h["members"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		b.body.add_child(row)
		var a := Court.apts(m)
		var apt := PackedStringArray()
		for k in Court.APTS:
			apt.append("%s %d" % [String(Rulers.data()["aptitudes"][k]["label"]).left(3), int(a[k])])
		var traits := PackedStringArray()
		for tr in m.get("traits", []):
			traits.append(String(Court.trait_def(String(tr)).get("label", tr)))
		var l := Label.new()
		l.text = "%s%s, %d ans  ·  %s%s" % ["♛ " if int(h["head"]) == int(m["id"]) else "", String(m["name"]), Court.age(state, m), "  ".join(apt),
				("  ·  " + ", ".join(traits)) if not traits.is_empty() else ""]
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(l)
		var mid := int(m["id"])
		_menu(es, row, "Ordres…", [
			["Élever au rang de héros (%s)" % GameData.format_amounts(Court.rules()["raise_cost"]), SimCommands.court_act(player, "raise", mid)],
			["Emprisonner (%s, %d %%)" % [GameData.format_amounts(Court.rules()["imprison_cost"]), CourtIntrigue.chance(state, player, "imprison")], SimCommands.court_act(player, "imprison", mid)],
			["Exiler (faveur %d)" % Court.r_int("exile_adj"), SimCommands.court_act(player, "exile", mid)]])
	var ar := HBoxContainer.new()
	ar.add_theme_constant_override("separation", 8)
	b.body.add_child(ar)
	ThroneScreen._button(es, ar, "Présent (%s)" % GameData.format_amounts(Court.rules()["gift_cost"]), SimCommands.court_act(player, "gift", hid), "court:gift:%d" % hid)
	var best := Court.strongest_house(state, player)
	if not best.is_empty() and int(best["id"]) != hid:
		ThroneScreen._button(es, ar, "Intercession de %s" % String(best["name"]), SimCommands.court_act(player, "intercede", hid, int(best["id"])), "court:intercede:%d" % hid)
	if (en["levers"] as Dictionary).has(str(hid)):
		ThroneScreen._button(es, ar, "Utiliser le secret (faveur %+d)" % Court.r_int("lever_adj"), SimCommands.court_act(player, "lever", hid), "court:lever:%d" % hid)
	else:
		ThroneScreen._button(es, ar, "Chercher un secret (%d %%)" % CourtIntrigue.chance(state, player, "secret"), SimCommands.court_act(player, "secret", hid), "court:secret:%d" % hid)
	ThroneScreen._button(es, ar, "Mariage", SimCommands.court_act(player, "wed", hid), "court:wed:%d" % hid)
	var fief_items: Array = []
	for sid in fs:
		fief_items.append(["Pacifier %s (%s)" % [String(state.galaxy.systems[sid].system_name), GameData.format_amounts(Court.rules()["pacify_cost"])], SimCommands.court_act(player, "pacify", sid)])
	for sid in Stability.systems_of(state, player):
		if not fs.has(sid) and sid != FactionTraits.capital_system(state, player):
			fief_items.append(["Lui donner %s (%s)" % [String(state.galaxy.systems[sid].system_name), GameData.format_amounts(Court.rules()["grant_cost"])], SimCommands.court_act(player, "grant", sid, hid)])
	_menu(es, ar, "Fiefs…", fief_items)


static func _faste_block(es: EmpireScreens, col: VBoxContainer, state: GameState, player: int, en: Dictionary) -> void:
	var b := Widgets.Block.new("Faste et train de la cour")
	col.add_child(b)
	var lines := PackedStringArray(["Faste %d, il tend vers %d." % [int(en["faste"]), CourtBridges.faste_target(state, player)]])
	for t: Dictionary in Court.rules()["faste_tiers"]:
		lines.append("%d : %s (faveur +%d, influence +%d, rayonnement +%d %%)" % [int(t["min"]), String(t["label"]), int(t["fav"]), int(t["influence"]), int(t["culture_pct"])])
	var st := CourtBridges.style_def(state, player)
	if not st.is_empty():
		lines.append("Style à partir de 50 : %s (%s)." % [String(st["label"]), String(st["text"])])
	b.body.add_child(UiTheme.paragraph("\n".join(lines), W, 13))
	for k in Court.rules()["train"]:
		var td: Dictionary = Court.rules()["train"][k]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		b.body.add_child(row)
		var lvl := int((en["train"] as Dictionary).get(k, 0))
		var l := Label.new()
		l.text = "%s : niveau %d / 3 (faste +%d, %d énergie / mois)" % [String(td["label"]), lvl, int(td["faste"][lvl]), int(td["upkeep"][lvl])]
		l.tooltip_text = String(td.get("text", ""))
		l.mouse_filter = Control.MOUSE_FILTER_STOP
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		if lvl > 0:
			ThroneScreen._button(es, row, "−", SimCommands.court_act(player, "train", lvl - 1, -1, String(k)), "court:train-:" + String(k))
		if lvl < 3:
			ThroneScreen._button(es, row, "+", SimCommands.court_act(player, "train", lvl + 1, -1, String(k)), "court:train+:" + String(k))
	var fr := HBoxContainer.new()
	b.body.add_child(fr)
	ThroneScreen._button(es, fr, "Grande fête (%s)" % GameData.format_amounts(CourtIntrigue.fete_cost(state, player)), SimCommands.court_act(player, "fete"), "court:fete")
	var others: Array = []
	for o in state.get_empire(player).contacts:
		var oe := state.get_empire(int(o))
		if oe != null and not oe.eliminated and not oe.is_npc():
			others.append(["Ambassade chez %s (%s)" % [oe.display_name(), GameData.format_amounts(Court.rules()["embassy_cost"])], SimCommands.court_act(player, "embassy", int(o))])
	_menu(es, fr, "Ambassade du %s…" % Court.office_label(state, player, "heraut"), others)


## Menu déroulant d'ordres : [[libellé, ordre], …] ; un ordre impossible est grisé, sa raison en infobulle.
static func _menu(es: EmpireScreens, parent: Control, text: String, items: Array) -> MenuButton:
	var mb := MenuButton.new()
	mb.text = text
	mb.flat = false
	mb.focus_mode = Control.FOCUS_NONE
	var pm := mb.get_popup()
	for i in items.size():
		pm.add_item(String(items[i][0]), i)
		var why := SimCommands.validate(es._state, items[i][1])
		pm.set_item_disabled(i, why != "")
		pm.set_item_tooltip(i, why)
	pm.id_pressed.connect(func(id: int) -> void: es.command_requested.emit(items[id][1]))
	mb.disabled = items.is_empty()
	parent.add_child(mb)
	return mb


static func signature(es: EmpireScreens) -> String:
	var state := es._state
	var en := Court.entry(state, es._player)
	if en.is_empty():
		return "none"
	var e := state.get_empire(es._player)
	var favs := PackedStringArray()
	for h: Dictionary in Court.houses(state, es._player):
		favs.append("%d:%d:%d" % [int(h["id"]), Court.favor(h), (h["members"] as Array).size()])
	return "%d|%s|%s|%s|%d|%s|%d|%d|%s" % [int(state.tick / 30.0), ",".join(favs), str(en["offices"]), str(en["minor"]), int(en["faste"]), str(en["train"]),
			int(e.resources.get("influence", 0)) / 20, int(e.resources.get("energy", 0)) / 50, str(en["fiefs"])]
