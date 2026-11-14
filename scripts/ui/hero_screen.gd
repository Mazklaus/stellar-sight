class_name HeroScreen
extends RefCounted
## Écran Panthéon (F10) : les héros de l'empire (voir Heroes).
## Colonne de gauche : places, renom vers la prochaine offre, sièges du conseil.
## Contenu : l'offre en attente (1 parmi 3), puis une carte par héros avec son poste, son effet,
## ses traits et les ordres (affecter, rappeler, renvoyer).
## Construit dans les conteneurs d'EmpireScreens, dont il reprend les aides (_grid, _key_value…).

const CARD_WIDTH := 300.0
const PORTRAIT := Vector2(96, 112)


static func build(es: EmpireScreens) -> void:
	var state := es._state
	var player := es._player
	es._hero_sig = signature(es)
	es.hero_buttons.clear()
	var m := Heroes.meta(state, player)
	var noun := Heroes.noun(state, player, true)

	# Colonne de gauche.
	es._side_header("screen_heroes", "Panthéon", Color(0.86, 0.72, 0.36), "faction")
	var g := es._grid()
	es._side_box.add_child(g)
	es._key_value(g, noun, "%d / %d" % [Heroes.ids_of(state, player).size(), Heroes.cap(state, player)])
	var ren := es._key_value(g, "Renom", "%d / %d" % [int(m["renown"]), Heroes.renown_needed(state, player)])
	ren.tooltip_text = "Vos actes (colonies, victoires, traités, opérations…) font monter le renom. Au seuil, trois candidats se présentent ; la classe penche vers vos actes récents."
	ren.mouse_filter = Control.MOUSE_FILTER_STOP
	es._key_value(g, "Conseil", "%d / %d" % [Heroes.council(state, player).size(), Heroes.seats(state, player)])
	es._side_box.add_child(HSeparator.new())
	for cls in Heroes.data()["classes"]:
		var c: Dictionary = Heroes.class_def(cls)
		var l := UiTheme.paragraph("%s (%s) : %s" % [c["label"], Heroes.post_label(String(c["post"])), c["text"]], EmpireScreens.SIDE_WIDTH - 24.0, 12)
		l.add_theme_color_override("font_color", Color(String(c["color"])).lerp(Color.WHITE, 0.45))
		es._side_box.add_child(l)
	var talents := Heroes.talent_labels(state, player)
	if not talents.is_empty():
		es._side_box.add_child(HSeparator.new())
		es._side_box.add_child(UiTheme.dim("Talents de votre peuple", 13))
		for tl in talents:
			es._side_box.add_child(UiTheme.paragraph("%s : %s" % [tl[0], tl[1]], EmpireScreens.SIDE_WIDTH - 24.0, 12))
	var mems: Array = []
	for x: Dictionary in m.get("memorials", []):
		if int(x["until"]) > state.tick:
			mems.append(x)
	if not mems.is_empty():
		es._side_box.add_child(HSeparator.new())
		es._side_box.add_child(UiTheme.dim("Souvenirs", 13))
		for x: Dictionary in mems:
			var cd: Dictionary = Heroes.data()["memorial"]["credo"].get(String(x["credo"]), {})
			@warning_ignore("integer_division")
			var ml := UiTheme.paragraph("%s : %s (encore %d ans)." % [x["name"], cd.get("text", ""), (int(x["until"]) - state.tick) / Heroes.DAYS_PER_YEAR + 1],
					EmpireScreens.SIDE_WIDTH - 24.0, 12)
			ml.add_theme_color_override("font_color", UiTheme.GOLD)
			es._side_box.add_child(ml)
	es._side_box.add_child(UiTheme.paragraph(String(EmpireBar.screen_info("heroes").get("why", "")), EmpireScreens.SIDE_WIDTH - 24.0, 13))

	# Contenu défilant.
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	es._content.add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 18)
	scroll.add_child(col)
	var offer: Array = m["offer"]
	if not offer.is_empty():
		col.add_child(_offer_block(es, offer))
	var mine := Widgets.Block.new("Vos %s" % noun.to_lower())
	col.add_child(mine)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 16)
	flow.add_theme_constant_override("v_separation", 16)
	mine.body.add_child(flow)
	var ids := Heroes.ids_of(state, player)
	for id in ids:
		flow.add_child(_hero_card(es, state.heroes[id]))
	if ids.is_empty():
		mine.body.add_child(UiTheme.dim("Aucun héros pour l'instant : le renom en fera venir.", 14))
	var market := Heroes.for_hire(state, player)
	if not market.is_empty():
		col.add_child(_market_block(es, market))
	var held := Heroes.prisoners_of(state, player)
	if not held.is_empty():
		col.add_child(_prison_block(es, held))


## Ce qui change l'écran : héros, renom et offre, mois, flottes et réseaux (cibles possibles).
static func signature(es: EmpireScreens) -> String:
	var state := es._state
	@warning_ignore("integer_division")
	return "%s|%s|%d|%d|%s|%d" % [str(Heroes.ids_of(state, es._player).map(func(i: int) -> Dictionary: return state.heroes[i])),
			str(Heroes.meta(state, es._player)) + str(Heroes.prisoners_of(state, es._player).map(func(i: int) -> Dictionary: return state.heroes[i]))
			+ str(Heroes.for_hire(state, es._player)) + str(state.get_empire(es._player).heir_loyalty),
			state.tick / 30, state.fleets.size(), str(state.networks),
			Heroes.cap(state, es._player) * 10 + Heroes.seats(state, es._player)]


static func _class_color(cls: String) -> Color:
	return Color(String(Heroes.class_def(cls).get("color", "#cccccc")))


static func _portrait(h: Dictionary, state: GameState = null) -> Widgets.ArtSlot:
	var art := Widgets.ArtSlot.new(String(h["portrait"]), PORTRAIT, _class_color(String(h["cls"])), "faction")
	if state != null:
		art.set_hero(portrait_info(state, h))
	return art


## Ce que le portrait montre du héros lui-même (voir Widgets.ArtSlot.set_hero).
static func portrait_info(state: GameState, h: Dictionary) -> Dictionary:
	var owner := state.get_empire(int(h.get("owner", -1)))
	return {"seed": int(h.get("id", 0)), "cls": String(h["cls"]), "lvl": int(h.get("lvl", 1)), "age": Heroes.age(state, h),
			"wound": Heroes.is_wounded(state, h), "prisoner": Heroes.is_prisoner(h), "heir": int(h.get("heir", 0)) > 0,
			"faction": owner.color() if owner else Color(0.5, 0.5, 0.5)}


static func _traits_line(h: Dictionary) -> Control:
	var box := HFlowContainer.new()
	box.add_theme_constant_override("h_separation", 8)
	for t in h["traits"]:
		var d := Heroes.trait_def(String(t))
		var l := Label.new()
		l.text = "◆ " + String(d.get("label", t))
		l.add_theme_font_size_override("font_size", 13)
		l.add_theme_color_override("font_color", UiTheme.GOLD)
		l.tooltip_text = String(d.get("text", ""))
		l.mouse_filter = Control.MOUSE_FILTER_STOP
		box.add_child(l)
	return box


static func _offer_block(es: EmpireScreens, offer: Array) -> Control:
	var state := es._state
	var player := es._player
	var b := Widgets.Block.new("Candidats : choisissez-en un")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	b.body.add_child(row)
	var full := Heroes.ids_of(state, player).size() >= Heroes.cap(state, player)
	var picks: Array[Button] = []
	for i in offer.size():
		var cand: Dictionary = offer[i]
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(CARD_WIDTH, 0)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 6)
		card.add_child(v)
		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", 10)
		v.add_child(top)
		var cart := _portrait(cand)
		cart.set_hero({"seed": absi(hash(String(cand["name"]))), "cls": String(cand["cls"]), "lvl": 1, "age": int(cand.get("age", 30)),
				"faction": state.get_empire(es._player).color()})
		top.add_child(cart)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(info)
		var name := UiTheme.paragraph(String(cand["name"]), CARD_WIDTH - PORTRAIT.x - 30.0, 15)
		info.add_child(name)
		var cl := Label.new()
		cl.text = "%s · %d ans" % [Heroes.class_def(String(cand["cls"]))["label"], int(cand.get("age", 30))]
		if String(cand.get("sp", "")) != "":
			cl.text += " · %s" % Peoples.label(String(cand["sp"]))
		cl.add_theme_color_override("font_color", _class_color(String(cand["cls"])).lerp(Color.WHITE, 0.3))
		info.add_child(cl)
		info.add_child(_traits_line(cand))
		var cad := Heroes.ambition_def(String(cand.get("amb", "")))
		if not cad.is_empty():
			var al := UiTheme.dim("Ambition : %s" % cad["label"], 12)
			al.tooltip_text = String(cad["text"])
			al.mouse_filter = Control.MOUSE_FILTER_STOP
			info.add_child(al)
		v.add_child(UiTheme.paragraph(String(Heroes.class_def(String(cand["cls"]))["text"]), CARD_WIDTH - 20.0, 12))
		var pick := Button.new()
		pick.text = "CHOISIR"
		pick.focus_mode = Control.FOCUS_NONE
		var why := Heroes.check_pick(state, player, i)
		pick.disabled = why != ""
		pick.tooltip_text = why
		var idx := i
		pick.pressed.connect(func() -> void: es.command_requested.emit(SimCommands.hero_pick(player, idx)))
		v.add_child(pick)
		picks.append(pick)
		row.add_child(card)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 12)
	b.body.add_child(foot)
	if full:
		var warn := UiTheme.dim("Toutes les places sont prises : renvoyez un héros pour en accueillir un nouveau, ou déclinez.", 13)
		warn.add_theme_color_override("font_color", UiTheme.WARN)
		foot.add_child(warn)
	var decline := Button.new()
	decline.text = "DÉCLINER"
	decline.focus_mode = Control.FOCUS_NONE
	decline.tooltip_text = "Renvoyer les trois candidats. Le renom repart vers l'offre suivante."
	decline.pressed.connect(func() -> void: es.command_requested.emit(SimCommands.hero_pick(player, -1)))
	foot.add_child(decline)
	es.hero_buttons["pick"] = picks
	es.hero_buttons["decline"] = decline
	return b


## Ce que fait le héros en ce moment, en une ligne.
static func status_text(state: GameState, h: Dictionary) -> String:
	if Heroes.is_prisoner(h):
		var je := state.get_empire(int(h["jailer"]))
		var conv := int(h.get("convert", 0))
		if GameState.is_npc(int(h["jailer"])) and h.has("ransom"):
			return "Prisonnier de %s : rançon à payer avant le %s, sinon il sera exécuté." % [je.short_name() if je else "?", GameCalendar.date_string(int(h["ransom"]))]
		return "Prisonnier de %s%s." % [je.short_name() if je else "?", (" : on le travaille au corps, ralliement dans %d jours" % maxi(0, conv - state.tick)) if conv > 0 else ""]
	if Heroes.is_wounded(state, h):
		return "Blessé : de retour dans %d jours." % (int(h["wound"]) - state.tick)
	var lent := ""
	if int(h.get("lender", -1)) >= 0:
		var le := state.get_empire(int(h["lender"]))
		lent = "Loué à %s, encore %d jours (%d énergie par mois). " % [le.short_name() if le else "?", maxi(0, int(h.get("lend_until", 0)) - state.tick), Heroes.hire_fee(h)]
	elif int(h.get("for_hire", 0)) > 0:
		lent = "À louer (%d énergie par mois). " % Heroes.hire_fee(h)
	return lent + _post_text(state, h)


static func _post_text(state: GameState, h: Dictionary) -> String:
	var post := String(h["post"])
	if post == "":
		return "Sans affectation."
	var where := "%s : %s" % [Heroes.post_label(post), target_name(state, post, int(h["target"]))]
	if int(h["arrive"]) > state.tick:
		return "%s (en route, %d jours)." % [where, int(h["arrive"]) - state.tick]
	return where + "."


static func target_name(state: GameState, post: String, target: int) -> String:
	match post:
		"fleet":
			var f: Fleet = state.fleets.get(target)
			return f.fleet_name if f else "?"
		"system":
			var s := state.galaxy.get_system(target)
			return s.system_name if s else "?"
		"council":
			return "siège %d" % (target + 1)
		"agent":
			var e := state.get_empire(target)
			return "réseau chez %s" % e.short_name() if e else "?"
		"amph":
			return Amphictyony.name_short()
	return ""


## Les postes qu'un héros peut prendre : [post, cible, libellé], celui de sa classe d'abord.
static func choices(state: GameState, player: int, h: Dictionary) -> Array:
	var own := String(Heroes.class_def(String(h["cls"])).get("post", ""))
	var order: Array[String] = [own]
	for p in ["fleet", "system", "council", "agent", "amph"]:
		if p != own:
			order.append(p)
	var out := []
	for post in order:
		var targets: Array[int] = []
		match post:
			"fleet":
				for fid in state.sorted_fleet_ids():
					var f: Fleet = state.fleets[fid]
					if f.owner == player:
						targets.append(f.id)
			"system":
				for s in state.galaxy.systems:
					if state.system_owner(s.id) == player:
						targets.append(s.id)
			"council":
				for seat in Heroes.seats(state, player):
					targets.append(seat)
			"agent":
				for o in state.get_empire(player).contacts:
					targets.append(int(o))
			"amph":
				targets.append(0)
		for t in targets:
			if int(h["target"]) == t and String(h["post"]) == post:
				continue
			if Heroes.check_assign(state, player, int(h["id"]), post, t) != "":
				continue
			var mark := " ★" if post == own else ""
			out.append([post, t, "%s : %s%s" % [Heroes.post_label(post), target_name(state, post, t), mark]])
	return out


static func _hero_card(es: EmpireScreens, h: Dictionary) -> Control:
	var state := es._state
	var player := es._player
	var id := int(h["id"])
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(CARD_WIDTH + 80.0, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	card.add_child(v)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	v.add_child(top)
	top.add_child(_portrait(h, state))
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(info)
	info.add_child(UiTheme.paragraph(String(h["name"]), CARD_WIDTH - 30.0, 15))
	var cl := Label.new()
	cl.text = "%s · niveau %d · %d ans" % [Heroes.class_def(String(h["cls"]))["label"], int(h["lvl"]), Heroes.age(state, h)]
	if String(h.get("sp", "")) != "":
		cl.text += " · %s" % Peoples.label(String(h["sp"]))
	cl.add_theme_color_override("font_color", _class_color(String(h["cls"])).lerp(Color.WHITE, 0.3))
	info.add_child(cl)
	var levels: Array = Heroes.data()["xp_levels"]
	var lvl := int(h["lvl"])
	var xp := ProgressBar.new()
	xp.show_percentage = false
	xp.custom_minimum_size = Vector2(160, 8)
	if lvl < levels.size():
		xp.min_value = float(levels[lvl - 1])
		xp.max_value = float(levels[lvl])
		xp.value = float(h["xp"])
		xp.tooltip_text = "Expérience : %d / %d" % [int(h["xp"]), int(levels[lvl])]
	else:
		xp.value = xp.max_value
		xp.tooltip_text = "Niveau maximal."
	info.add_child(xp)
	info.add_child(_traits_line(h))
	v.add_child(_loyalty_line(state, h))
	var st := UiTheme.paragraph(status_text(state, h), CARD_WIDTH + 60.0, 13)
	if Heroes.is_wounded(state, h) or Heroes.is_prisoner(h):
		st.add_theme_color_override("font_color", UiTheme.WARN)
	v.add_child(st)
	if Heroes.is_prisoner(h) and GameState.is_npc(int(h["jailer"])) and int(h["owner"]) == player:
		var why := Heroes.check_ransom(state, player, id)
		var rb := Button.new()
		rb.focus_mode = Control.FOCUS_NONE
		rb.text = "Payer la rançon (%s)" % GameData.format_amounts(Heroes.ransom_cost(h))
		rb.disabled = why != ""
		rb.tooltip_text = why if why != "" else "Il rentre aussitôt, libre de reprendre un poste."
		rb.pressed.connect(func() -> void: es.command_requested.emit(SimCommands.hero_ransom(player, id)))
		v.add_child(rb)
		es.hero_buttons["ransom_%d" % id] = rb
	if String(h["post"]) != "":
		var fx := UiTheme.dim(Heroes.post_effect_text(state, h), 13)
		v.add_child(fx)
	var orders := HBoxContainer.new()
	orders.add_theme_constant_override("separation", 8)
	v.add_child(orders)
	var opt := OptionButton.new()
	opt.focus_mode = Control.FOCUS_NONE
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opt.fit_to_longest_item = false
	opt.add_item("Affecter…")
	var ch := choices(state, player, h)
	for c in ch:
		opt.add_item(String(c[2]))
	opt.disabled = ch.is_empty() or Heroes.is_wounded(state, h) or Heroes.is_prisoner(h)
	opt.tooltip_text = "Le poste de sa classe (★) donne l'effet plein, les autres la moitié. Hors du système capital, %d jours de trajet." % int(Heroes.data()["travel_days"])
	opt.item_selected.connect(func(i: int) -> void:
		if i > 0:
			var c: Array = ch[i - 1]
			es.command_requested.emit(SimCommands.hero_assign(player, id, String(c[0]), int(c[1]))))
	orders.add_child(opt)
	var recall := Button.new()
	recall.text = "RAPPELER"
	recall.focus_mode = Control.FOCUS_NONE
	recall.disabled = String(h["post"]) == ""
	recall.pressed.connect(func() -> void: es.command_requested.emit(SimCommands.hero_assign(player, id, "", -1)))
	orders.add_child(recall)
	var dismiss := Button.new()
	dismiss.text = "RENVOYER"
	dismiss.focus_mode = Control.FOCUS_NONE
	dismiss.tooltip_text = "Le héros quitte votre service pour de bon."
	var dwhy := Heroes.check_dismiss(state, player, id)
	dismiss.disabled = dwhy != ""
	if dwhy != "":
		dismiss.tooltip_text = dwhy
	dismiss.pressed.connect(func() -> void: es.command_requested.emit(SimCommands.hero_dismiss(player, id)))
	orders.add_child(dismiss)
	var entry := {"assign": opt, "recall": recall, "dismiss": dismiss, "choices": ch}
	if int(Heroes.talent(state, player).get("hire", 0)) > 0 and int(h.get("lender", -1)) < 0:
		var on := int(h.get("for_hire", 0)) == 0
		var rent := Button.new()
		rent.text = "LOUER" if on else "RETIRER"
		rent.focus_mode = Control.FOCUS_NONE
		var rwhy := Heroes.check_for_hire(state, player, id, on)
		rent.disabled = rwhy != ""
		rent.tooltip_text = rwhy if rwhy != "" else ("Le mettre en location : un empire rencontré pourra l'engager pour un an, à %d énergie par mois." % Heroes.hire_fee(h) if on else "Le retirer de la location.")
		rent.pressed.connect(func() -> void: es.command_requested.emit(SimCommands.hero_for_hire(player, id, on)))
		orders.add_child(rent)
		entry["rent"] = rent
	es.hero_buttons[id] = entry
	return card


## Ambition et loyauté (rien pour un Avatar), espérance de vie.
static func _loyalty_line(state: GameState, h: Dictionary) -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	if int(h.get("heir", 0)) > 0:
		var loyh := Heroes.loyalty(state, h)
		var lh := Label.new()
		lh.add_theme_font_size_override("font_size", 13)
		lh.text = "Héritier de la lignée · loyauté %d" % loyh
		lh.tooltip_text = "Sa loyauté est celle de la lignée (écran Diplomatie : banquet, intrigues). Trop basse, il livre un fief à qui le courtise."
		lh.mouse_filter = Control.MOUSE_FILTER_STOP
		if loyh < 25:
			lh.add_theme_color_override("font_color", UiTheme.WARN)
		box.add_child(lh)
		return box
	var ad := Heroes.ambition_def(String(h.get("amb", "")))
	if ad.is_empty():
		var l := UiTheme.dim("Avatar : sans ambition propre, d'une loyauté sans faille.", 12)
		box.add_child(l)
		return box
	var amb := Label.new()
	amb.add_theme_font_size_override("font_size", 13)
	amb.text = "Ambition : %s%s" % [ad["label"], " ✓" if int(h.get("amb_done", 0)) > 0 else " (%d / %d)" % [int(h.get("amb_n", 0)), int(ad["grand"])]]
	amb.tooltip_text = "%s\nGrand objectif : %s." % [ad["text"], ad["grand_text"]]
	amb.mouse_filter = Control.MOUSE_FILTER_STOP
	box.add_child(amb)
	var loy := int(h.get("loy", 50))
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(90, 8)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.max_value = 100
	bar.value = loy
	var low := loy < int(Heroes.data()["loyalty"]["min_desert"])
	bar.modulate = UiTheme.WARN if low else Color(0.6, 0.9, 0.7)
	bar.tooltip_text = "Loyauté %d / 100. Servir son ambition l'entretient ; l'oublier, ou le laisser sans poste, l'use. Sous %d, il peut déserter." % [
			loy, int(Heroes.data()["loyalty"]["min_desert"])]
	box.add_child(bar)
	var ll := Label.new()
	ll.add_theme_font_size_override("font_size", 13)
	ll.text = "Loyauté %d" % loy
	if low:
		ll.add_theme_color_override("font_color", UiTheme.WARN)
	box.add_child(ll)
	return box


static func _prison_block(es: EmpireScreens, held: Array[int]) -> Control:
	var state := es._state
	var player := es._player
	var b := Widgets.Block.new("Prisonniers")
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 16)
	flow.add_theme_constant_override("v_separation", 16)
	b.body.add_child(flow)
	for id in held:
		var h: Dictionary = state.heroes[id]
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(CARD_WIDTH + 80.0, 0)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 6)
		card.add_child(v)
		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", 10)
		v.add_child(top)
		top.add_child(_portrait(h, state))
		var info := VBoxContainer.new()
		top.add_child(info)
		info.add_child(UiTheme.paragraph(String(h["name"]), CARD_WIDTH - 30.0, 15))
		var oe := state.get_empire(int(h["owner"]))
		var cl := Label.new()
		cl.text = "%s de %s · niveau %d" % [Heroes.class_def(String(h["cls"]))["label"], oe.short_name() if oe else "?", int(h["lvl"])]
		cl.add_theme_color_override("font_color", _class_color(String(h["cls"])).lerp(Color.WHITE, 0.3))
		info.add_child(cl)
		info.add_child(_traits_line(h))
		var conv := int(h.get("convert", 0))
		if conv > 0:
			v.add_child(UiTheme.dim("Conversion en cours : il nous rejoint dans %d jours (s'il reste une place)." % maxi(0, conv - state.tick), 13))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		v.add_child(row)
		var btns := {}
		for a in [["free", "LIBÉRER", "Il rentre chez lui ; son empire s'en souviendra avec gratitude."],
				["convert", "CONVERTIR", "Le rallier à notre cause : il nous rejoint après %d jours, s'il reste une place." % int(Heroes.data()["capture"]["convert_days"])],
				["execute", "EXÉCUTER", "Il meurt. Son empire ne l'oubliera pas (grief durable)."]]:
			var bt := Button.new()
			bt.text = String(a[1])
			bt.focus_mode = Control.FOCUS_NONE
			var why := Heroes.check_prisoner(state, player, id, String(a[0]))
			bt.disabled = why != ""
			bt.tooltip_text = why if why != "" else String(a[2])
			var act := String(a[0])
			var hid := id
			bt.pressed.connect(func() -> void: es.command_requested.emit(SimCommands.hero_prisoner(player, hid, act)))
			row.add_child(bt)
			btns[act] = bt
		es.hero_buttons["prisoner_%d" % id] = btns
		flow.add_child(card)
	return b


## Héros à louer chez les syndicats rencontrés.
static func _market_block(es: EmpireScreens, ids: Array[int]) -> Control:
	var state := es._state
	var player := es._player
	var b := Widgets.Block.new("Héros à louer")
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 16)
	flow.add_theme_constant_override("v_separation", 16)
	b.body.add_child(flow)
	for id in ids:
		var h: Dictionary = state.heroes[id]
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(CARD_WIDTH, 0)
		var v := VBoxContainer.new()
		card.add_child(v)
		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", 10)
		v.add_child(top)
		top.add_child(_portrait(h, state))
		var info := VBoxContainer.new()
		top.add_child(info)
		info.add_child(UiTheme.paragraph(String(h["name"]), CARD_WIDTH - PORTRAIT.x - 30.0, 15))
		var oe := state.get_empire(int(h["owner"]))
		var cl := Label.new()
		cl.text = "%s de %s · niveau %d" % [Heroes.class_def(String(h["cls"]))["label"], oe.short_name(), int(h["lvl"])]
		cl.add_theme_color_override("font_color", _class_color(String(h["cls"])).lerp(Color.WHITE, 0.3))
		info.add_child(cl)
		info.add_child(_traits_line(h))
		var bt := Button.new()
		bt.text = "ENGAGER (%d énergie par mois)" % Heroes.hire_fee(h)
		bt.focus_mode = Control.FOCUS_NONE
		var why := Heroes.check_hire(state, player, id)
		bt.disabled = why != ""
		bt.tooltip_text = why if why != "" else "Il sert chez vous pendant %d jours, puis rentre chez son syndicat." % int(Heroes.data()["hire"]["days"])
		var hid := id
		bt.pressed.connect(func() -> void: es.command_requested.emit(SimCommands.hero_hire(player, hid)))
		v.add_child(bt)
		es.hero_buttons["hire_%d" % id] = bt
		flow.add_child(card)
	return b
