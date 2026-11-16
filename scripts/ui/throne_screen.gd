class_name ThroneScreen
extends RefCounted
## Écran Trône (Maj+F10, ou clic sur le nom de l'empire ; voir Rulers) : le souverain (portrait tiré de
## la galerie des souverains, titre, surnoms, âge, aptitudes, légitimité et son détail), son ambition,
## le pouvoir de son archétype, son poste ; la loi de succession, les héritiers et leur éducation, les
## héritages de la maison, le mariage, l'abdication ; les annales des règnes passés. Lit l'état, n'émet
## que des ordres « ruler_act ».

const W := 760.0
const GOLD := Color(0.95, 0.78, 0.36)


static func build(es: EmpireScreens) -> void:
	var state := es._state
	var player := es._player
	es._throne_sig = signature(es)
	var sm := Rulers.summary(state, player)
	var court_tab := tab == "cour" and Court.applies(state, player)
	es._side_header(String(sm.get("portrait", "screen_throne")) if not court_tab else "screen_throne", "La Cour" if court_tab else "Trône", GOLD, "faction")
	_tabs(es)
	if court_tab:
		CourtScreen.build(es)
		return
	if not Rulers.enabled(state) or sm.is_empty():
		es._side_box.add_child(UiTheme.paragraph("Dans cette partie, les souverains ne sont pas en jeu (Nouvelle partie : Souverains).", EmpireScreens.SIDE_WIDTH - 24.0, 13))
		return
	var en := Rulers.entry(state, player)
	var r := Rulers.ruler(state, player)
	var g := es._grid()
	es._side_box.add_child(g)
	es._key_value(g, "Régime", String(sm["kind_label"]))
	if r.is_empty():
		es._key_value(g, "Trône", "vacant")
		if int(sm.get("until", 0)) > 0:
			es._key_value(g, "Interrègne", "jusqu'au %s" % GameCalendar.date_string(int(sm["until"])))
	else:
		var ll := es._key_value(g, "Légitimité", "%d / 100" % int(sm["legit"]))
		ll.tooltip_text = legit_tip(state, player)
		ll.mouse_filter = Control.MOUSE_FILTER_STOP
		es._key_value(g, "Âge", "%d ans" % int(sm["age"]) if int(r.get("life", 0)) > 0 else "sans âge")
		es._key_value(g, "Règne", "%d an%s" % [int(sm["reign"]), "s" if int(sm["reign"]) > 1 else ""])
		es._key_value(g, "Archétype", String(Rulers.arch_def(String(r["arch"])).get("label", r["arch"])))
		if int(en.get("wobbly", 0)) > state.tick:
			es._key_value(g, "Couronne vacillante", "jusqu'au %s" % GameCalendar.date_string(int(en["wobbly"])))
		if RulersDynasty.in_regency(state, player):
			es._key_value(g, "Régence", String((en["regent"] as Dictionary).get("name", "un conseil")))
	if Rulers.hereditary(state, player):
		es._key_value(g, "Maison", String(en.get("house", "")))
		es._key_value(g, "Renom", str(int(en.get("renown", 0))))
	es._side_box.add_child(HSeparator.new())
	es._side_box.add_child(UiTheme.paragraph(String(sm["kind_text"]), EmpireScreens.SIDE_WIDTH - 24.0, 12))

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	es._content.add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 18)
	scroll.add_child(col)

	if not r.is_empty():
		_ruler_block(es, col, state, player, en, r)
		_ambition_block(es, col, state, player, en, r)
	_line_block(es, col, state, player, en)
	_legacy_block(es, col, state, player, en)
	_annals_block(col, state, player, en)


## Onglet de l'écran : « Trône » ou « La Cour » (voir CourtScreen).
static var tab := "trone"


## Boutons d'onglet (seulement si l'empire a une cour).
static func _tabs(es: EmpireScreens) -> void:
	if not Court.applies(es._state, es._player):
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	es._side_box.add_child(row)
	for t in [["trone", "Trône"], ["cour", "La Cour"]]:
		var b := Button.new()
		b.text = String(t[1])
		b.toggle_mode = true
		b.button_pressed = tab == String(t[0])
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var id := String(t[0])
		b.pressed.connect(func() -> void:
			tab = id
			es.show_screen("throne"))
		row.add_child(b)
		es.throne_buttons["tab:" + id] = b


static func _ruler_block(es: EmpireScreens, col: VBoxContainer, state: GameState, player: int, en: Dictionary, r: Dictionary) -> void:
	var b := Widgets.Block.new(Rulers.full_name(state, player))
	col.add_child(b)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	b.body.add_child(row)
	var art := Widgets.ArtSlot.new(String(r["portrait"]), Vector2(170, 210), GOLD, "faction")
	row.add_child(art)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var cogs := PackedStringArray()
	for cid in r.get("cogs", []):
		cogs.append(Rulers.cog_text(state, player, r, String(cid)))
	info.add_child(UiTheme.paragraph("Surnoms : %s" % (", ".join(cogs) if not cogs.is_empty() else "aucun encore, le règne les donnera"), 540.0, 14))
	var ag := GridContainer.new()
	ag.columns = 3
	ag.add_theme_constant_override("h_separation", 14)
	info.add_child(ag)
	var apts := Rulers.apts(state, player)
	for k: String in Rulers.APTS:
		var d: Dictionary = Rulers.data()["aptitudes"][k]
		var v := int(apts.get(k, 0))
		ag.add_child(UiTheme.dim(String(d["label"]), 13))
		var bar := Label.new()
		bar.text = "◆".repeat(v) + "◇".repeat(maxi(0, int(Rulers.data()["apt_max"]) - v))
		bar.add_theme_color_override("font_color", GOLD)
		ag.add_child(bar)
		ag.add_child(UiTheme.dim(String(d["text"]) % (v * int(d["per"])), 12))
	var ad := Rulers.arch_def(String(r["arch"]))
	info.add_child(UiTheme.paragraph("%s : %s" % [String(ad.get("label", "")), String(ad.get("text", ""))], 540.0, 13))
	# Pouvoir de l'archétype.
	var p: Dictionary = ad.get("power", {})
	if not p.is_empty():
		var pr := HBoxContainer.new()
		pr.add_theme_constant_override("separation", 10)
		info.add_child(pr)
		var pl := UiTheme.paragraph("Pouvoir « %s » : %s" % [String(p.get("label", "")), String(p.get("text", ""))], 400.0, 13)
		pl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pr.add_child(pl)
		_button(es, pr, "Invoquer", SimCommands.ruler_act(player, "power"), "power")
	# Poste.
	var post := String(r.get("post", ""))
	var where := "au palais" if post != "fleet" else "à la tête d'une flotte"
	if post == "fleet" and state.fleets.has(int(r.get("target", -1))):
		where = "à la tête de %s" % (state.fleets[int(r["target"])] as Fleet).fleet_name
	var po := HBoxContainer.new()
	po.add_theme_constant_override("separation", 10)
	info.add_child(po)
	var ql := UiTheme.paragraph("Poste : %s. Au front, il double son bonus de Guerre pour sa flotte, mais peut y être blessé ou tué." % where, 400.0, 13)
	ql.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	po.add_child(ql)
	if post == "fleet":
		_button(es, po, "Rappeler au palais", SimCommands.ruler_act(player, "post", -1, "capital"), "post_capital")
	else:
		var best := _best_fleet(state, player)
		if best >= 0:
			_button(es, po, "Prendre le commandement", SimCommands.ruler_act(player, "post", best, "fleet"), "post_fleet")
	if Rulers.is_wounded(state, player):
		info.add_child(UiTheme.dim("Blessé : se remet jusqu'au %s." % GameCalendar.date_string(int(en["wound"])), 13))


static func _ambition_block(_es: EmpireScreens, col: VBoxContainer, state: GameState, player: int, en: Dictionary, _r: Dictionary) -> void:
	var am: Dictionary = en.get("amb", {})
	var done: Array = en.get("amb_done", [])
	if am.is_empty() and done.is_empty():
		return
	var b := Widgets.Block.new("Ambition")
	col.add_child(b)
	if not am.is_empty():
		var a := Rulers.amb_def(String(am["id"]))
		var pg := Rulers.amb_progress(state, player)
		b.body.add_child(UiTheme.paragraph("%s : %s (%d / %d). Réussie, elle donne +%d de légitimité et un surnom." % [String(a.get("label", "")), String(a.get("text", "")),
				mini(int(pg[0]), int(pg[1])), int(pg[1]), Rulers.r_int("ambition_legit")], W, 14))
	else:
		b.body.add_child(UiTheme.dim("Aucune ambition en cours : une nouvelle se présentera bientôt.", 13))
	if not done.is_empty():
		var names := PackedStringArray()
		for id in done:
			names.append(String(Rulers.amb_def(String(id)).get("label", id)))
		b.body.add_child(UiTheme.dim("Accomplies : " + ", ".join(names), 13))


static func _line_block(es: EmpireScreens, col: VBoxContainer, state: GameState, player: int, en: Dictionary) -> void:
	var dyn := Rulers.kind(state, player) == "dynastie"
	var b := Widgets.Block.new("Lignée et succession" if dyn else "Succession")
	col.add_child(b)
	if dyn:
		var law := String(en.get("law", Rulers.data().get("default_law", "primogeniture")))
		b.body.add_child(UiTheme.paragraph("Loi : %s. %s" % [String(Rulers.data()["laws"][law]["label"]), String(Rulers.data()["laws"][law]["text"])], W, 14))
		var lr := HBoxContainer.new()
		lr.add_theme_constant_override("separation", 8)
		b.body.add_child(lr)
		for lid in (Rulers.data()["laws"] as Dictionary).keys():
			if String(lid) != law:
				_button(es, lr, "Adopter : %s (%s)" % [String(Rulers.data()["laws"][lid]["label"]), GameData.format_amounts(RulersDynasty.rules()["law_change"])],
						SimCommands.ruler_act(player, "law", -1, String(lid)), "law:" + String(lid))
		if String(en.get("consort", "")) != "":
			var sp := int(en.get("spouse", -1))
			b.body.add_child(UiTheme.dim("Consort : %s%s" % [String(en["consort"]), (", alliance de sang avec %s" % state.get_empire(sp).display_name()) if sp >= 0 and state.get_empire(sp) != null else ""], 13))
	var hs := RulersDynasty.heirs(state, player)
	var hh := Heroes.heir_of(state, player)
	if not hh.is_empty():
		b.body.add_child(UiTheme.dim("Héritier désigné : %s" % String(hh.get("name", "")), 13))
	if hs.is_empty() and dyn:
		b.body.add_child(UiTheme.dim("Aucun enfant pour l'instant. Sans héritier, la lignée s'éteint à la mort du souverain.", 13))
	for c: Dictionary in hs:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		b.body.add_child(row)
		var apt := PackedStringArray()
		for k: String in Rulers.APTS:
			apt.append("%s %d" % [String(Rulers.data()["aptitudes"][k]["label"]).left(3), int((c["apt"] as Dictionary).get(k, 0))])
		var l := Label.new()
		l.text = "%s, %d ans%s  ·  %s%s" % [String(c["name"]), RulersDynasty.child_age(state, c), " (bâtard)" if int(c.get("bastard", 0)) == 1 else "", "  ".join(apt),
				("  ·  éduqué : " + String(Heroes.class_def(String(c["edu"]))["label"]).to_lower()) if String(c["edu"]) != "" else ""]
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		if String(c["edu"]) == "":
			var cls := RulersDynasty._best_cls(c)
			_button(es, row, "Éduquer : %s" % String(Heroes.class_def(cls)["label"]).to_lower(), SimCommands.ruler_act(player, "educate", int(c["id"]), cls), "educate:%d" % int(c["id"]))
	var ar := HBoxContainer.new()
	ar.add_theme_constant_override("separation", 8)
	b.body.add_child(ar)
	if Rulers.hereditary(state, player) and int(en.get("spouse", -1)) < 0:
		for o in state.get_empire(player).contacts:
			var cmd := SimCommands.ruler_act(player, "marry", int(o), "")
			if SimCommands.validate(state, cmd) == "":
				_button(es, ar, "Mariage avec %s" % state.get_empire(int(o)).short_name(), cmd, "marry:%d" % int(o))
	if Rulers.mortal(state) and not Rulers.immortal_kind(state, player):
		_button(es, ar, "Abdiquer (légitimité %d)" % Rulers.r_int("abdicate_adj"), SimCommands.ruler_act(player, "abdicate"), "abdicate")


static func _legacy_block(es: EmpireScreens, col: VBoxContainer, state: GameState, player: int, en: Dictionary) -> void:
	var b := Widgets.Block.new(RulersDynasty.legacy_label(state, player))
	col.add_child(b)
	b.body.add_child(UiTheme.paragraph("Chaque règne achevé laisse du renom (%d aujourd'hui) : il achète des héritages permanents, voie par voie." % int(en.get("renown", 0)), W, 13))
	var bought: Dictionary = en.get("legacies", {})
	for t in RulersDynasty.legacy_defs():
		var d: Dictionary = RulersDynasty.legacy_defs()[t]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		b.body.add_child(row)
		var lv := int(bought.get(t, 0))
		var l := Label.new()
		var nx := RulersDynasty.legacy_next(state, player, String(t))
		l.text = "%s : %d / %d%s" % [String(d["label"]), lv, (d["levels"] as Array).size(), ("  ·  suivant : %s (%s)" % [String(nx["label"]), String(nx.get("text", ""))]) if not nx.is_empty() else "  ·  voie achevée"]
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(l)
		if not nx.is_empty():
			_button(es, row, "%d renom" % int(nx["cost"]), SimCommands.ruler_act(player, "legacy", -1, String(t)), "legacy:" + String(t))


static func _annals_block(col: VBoxContainer, state: GameState, player: int, en: Dictionary) -> void:
	var rg: Array = en.get("reigns", [])
	var b := Widgets.Block.new("Annales des règnes")
	col.add_child(b)
	if rg.is_empty():
		b.body.add_child(UiTheme.dim("Le premier règne s'écrit encore.", 13))
		return
	for i in range(rg.size() - 1, maxi(-1, rg.size() - 13), -1):
		var x: Dictionary = rg[i]
		b.body.add_child(UiTheme.paragraph("%s %s (%s – %s) : %s, légitimité %d." % [String(x.get("title", "")), String(x["name"]),
				GameCalendar.date_string(int(x["from"])), GameCalendar.date_string(int(x["to"])), end_text(String(x["end"])), int(x.get("legit", 0))], W, 13))
	if rg.size() > 12:
		b.body.add_child(UiTheme.dim("… et %d règnes plus anciens." % (rg.size() - 12), 12))


static func end_text(how: String) -> String:
	match how:
		"age": return "mort de vieillesse"
		"murdered": return "assassiné"
		"battle", "front": return "tombé au combat"
		"abdicate": return "a abdiqué"
		"deposed": return "renversé"
		"seized": return "écarté par son régent"
		"term": return "fin de mandat"
		"accident": return "mort accidentelle"
		"capital": return "mort avec la capitale"
	return how


static func legit_tip(state: GameState, player: int) -> String:
	var en := Rulers.entry(state, player)
	var lines := PackedStringArray(["Légitimité %d / 100." % Rulers.legitimacy(state, player)])
	lines.append("Ajustements du règne : %+d" % int(en.get("adj", 0)))
	var lg := RulersDynasty.legacy_sum(state, player, "legit")
	if lg != 0:
		lines.append("Héritages : %+d" % lg)
	var fb := RulersBridges.legit_bonus(state, player)
	if fb != 0:
		lines.append("Sacre par la foi d'État : %+d" % fb)
	if int(en.get("wobbly", 0)) > state.tick:
		lines.append("Couronne vacillante : -10")
	lines.append("Au-dessus de %d : stabilité +%d partout ; sous %d : stabilité %d, prétendants et coups d'État." % [Rulers.r_int("legit_high"), Rulers.r_int("legit_high_stab"),
			Rulers.r_int("legit_low"), Rulers.r_int("legit_low_stab")])
	return "\n".join(lines)


static func _best_fleet(state: GameState, player: int) -> int:
	var best: Fleet = null
	for fid in state.sorted_fleet_ids():
		var f: Fleet = state.fleets[fid]
		if f.owner == player and Combat.is_armed(f) and (best == null or Combat.fleet_power(f) > Combat.fleet_power(best)):
			best = f
	return best.id if best != null else -1


static func _button(es: EmpireScreens, parent: Control, text: String, cmd: Dictionary, key: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	var why := SimCommands.validate(es._state, cmd)
	b.disabled = why != ""
	b.tooltip_text = why
	b.pressed.connect(func() -> void: es.command_requested.emit(cmd))
	parent.add_child(b)
	es.throne_buttons[key] = b
	return b


static func signature(es: EmpireScreens) -> String:
	var state := es._state
	if tab == "cour" and Court.applies(state, es._player):
		return "cour|" + CourtScreen.signature(es)
	if not Rulers.enabled(state):
		return "off"
	var en := Rulers.entry(state, es._player)
	if en.is_empty():
		return "none"
	var e := state.get_empire(es._player)
	return "%d|%s|%d|%d|%s|%d|%d|%d" % [int(state.tick / 30.0), str(en.get("r", {}).get("name", "")), Rulers.legitimacy(state, es._player), int(en.get("renown", 0)),
			str(en.get("legacies", {})), (en.get("heirs", []) as Array).size(), int(e.resources.get("influence", 0)) / 40, int(en.get("power_cd", 0))]
