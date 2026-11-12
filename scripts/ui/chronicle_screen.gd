class_name ChronicleScreen
extends RefCounted
## Écran Chroniques (J), à la manière de l'écran « Quêtes et événements » d'Endless Space 2, en trois
## onglets : Quêtes (quêtes de l'empire et retournement galactique, voir Quests et QuestPanel),
## Événements (boîte, curiosités repérées, journal ; voir Events et Curios), Reliquaire (reliques et
## fouilles, voir Relics) et Bestiaire (créatures rencontrées, voir BestiaryPanel).
## Construit dans les conteneurs d'EmpireScreens (_grid, _key_value…).

const TABS := [["quests", "Quêtes"], ["events", "Événements"], ["relics", "Reliquaire"], ["bestiary", "Bestiaire"]]


## Onglets offerts dans cette partie (selon les réglages de la Nouvelle partie).
static func tabs(state: GameState) -> Array[String]:
	var out: Array[String] = []
	if Quests.enabled(state):
		out.append("quests")
	out.append("events")
	if not state.relics.is_empty():
		out.append("relics")
	if Fauna.active(state):
		out.append("bestiary")
	return out


static func build(es: EmpireScreens) -> void:
	var state := es._state
	var player := es._player
	es._chron_sig = signature(es)
	es.chronicle_buttons.clear()
	var box := Events.inbox(state, player)
	var log: Array = Events.meta(state, player)["log"] if state.ev_meta.has(player) else []
	var known := Curios.known(state, player)

	# Colonne de gauche.
	es._side_header("screen_chronicles", "Chroniques", Color(0.95, 0.78, 0.45), "star")
	var g := es._grid()
	es._side_box.add_child(g)
	es._key_value(g, "En attente", "%d" % box.size())
	es._key_value(g, "Décisions prises", "%d" % log.size())
	es._key_value(g, "Curiosités repérées", "%d" % known.size())
	if Quests.enabled(state):
		es._key_value(g, "Quêtes en cours", "%d" % Quests.of(state, player, true).size())
	if not state.relics.is_empty():
		var fr := es._key_value(g, "Fragments", "%d" % Relics.fragments(state, player))
		fr.tooltip_text = "Petite monnaie des reliques : indices de fouille, part du Triomphe, dons. On en trouve dans les curiosités, les fouilles et les épaves."
		fr.mouse_filter = Control.MOUSE_FILTER_STOP
		es._key_value(g, "Reliques", "%d" % Relics.owned(state, player).size())
	if Fauna.active(state):
		es._key_value(g, "Espèces rencontrées", "%d / %d" % [Fauna.known_species(state, player).size(), Fauna.species_ids().size()])
	if state.curio_density != "aucune":
		var det := es._key_value(g, "Détection", "niveau %d" % Curios.detect(state, player))
		det.tooltip_text = "Les curiosités de niveau supérieur restent invisibles. Les capteurs et certaines technologies l'améliorent."
		det.mouse_filter = Control.MOUSE_FILTER_STOP
		var pw := es._key_value(g, "Puissance d'expédition", "%d" % Curios.power(state, player))
		pw.tooltip_text = "Plus elle dépasse le niveau d'une curiosité, plus la sonde est rapide (de 180 jours à 15)."
		pw.mouse_filter = Control.MOUSE_FILTER_STOP
	es._side_box.add_child(HSeparator.new())
	es._side_box.add_child(UiTheme.paragraph(String(EmpireBar.screen_info("chronicles").get("why", "")), EmpireScreens.SIDE_WIDTH - 24.0, 13))

	# Onglets, puis contenu défilant.
	var offered := tabs(state)
	if not offered.has(es.chron_tab):
		es.chron_tab = offered[0]
	var top := VBoxContainer.new()
	top.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.size_flags_vertical = Control.SIZE_EXPAND_FILL
	top.add_theme_constant_override("separation", 12)
	es._content.add_child(top)
	var bar := HBoxContainer.new()
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", 30)
	top.add_child(bar)
	for t in TABS:
		if not offered.has(String(t[0])):
			continue
		var tb := Button.new()
		tb.theme_type_variation = &"TabButton"
		tb.toggle_mode = true
		tb.focus_mode = Control.FOCUS_NONE
		var tid := String(t[0])
		var label := String(t[1])
		if tid == "events" and not box.is_empty():
			label += " (%d)" % box.size()
		tb.text = label.to_upper()
		tb.set_pressed_no_signal(tid == es.chron_tab)
		tb.pressed.connect(func() -> void:
			es.chron_tab = tid
			es.show_screen("chronicles"))
		es.chronicle_buttons["tab:%s" % tid] = tb
		bar.add_child(tb)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	top.add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 18)
	scroll.add_child(col)

	if es.chron_tab == "quests":
		QuestPanel.build(es, col)
		return
	if es.chron_tab == "bestiary":
		BestiaryPanel.build(es, col)
		return
	if es.chron_tab == "relics":
		col.add_child(_reliquary_block(es))
		col.add_child(_digs_block(es))
		return
	if not Events.enabled(state) and state.curio_density == "aucune" and box.is_empty() and Guardians.ids(state).is_empty():
		col.add_child(UiTheme.dim("Ni événements ni curiosités dans cette partie (réglage de la Nouvelle partie).", 15))
		return

	var wait := Widgets.Block.new("En attente de décision")
	col.add_child(wait)
	if box.is_empty():
		wait.body.add_child(UiTheme.dim("Rien pour l'instant. Les nouvelles arrivent d'elles-mêmes." if Events.enabled(state)
				else "Les événements sont désactivés pour cette partie.", 14))
	for item: Dictionary in box:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var b := Button.new()
		b.theme_type_variation = &"PrimaryButton"
		b.focus_mode = Control.FOCUS_NONE
		b.text = "Décider"
		var id := int(item["id"])
		b.pressed.connect(func() -> void: es.event_requested.emit(id))
		es.chronicle_buttons["event:%d" % id] = b
		row.add_child(b)
		var t := UiTheme.title(Events.fill(state, player, item, String(Events.card(String(item["card"])).get("title", ""))), 18)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(t)
		var left := maxi(0, int(item["until"]) - state.tick)
		row.add_child(UiTheme.dim("encore %d jour%s" % [left, "s" if left > 1 else ""], 13))
		wait.body.add_child(row)

	var cur := Widgets.Block.new("Curiosités repérées")
	col.add_child(cur)
	if known.is_empty():
		cur.body.add_child(UiTheme.dim("Aucune curiosité en vue. Explorez, et améliorez votre détection." if state.curio_density != "aucune"
				else "Pas de curiosités dans cette partie.", 14))
	var cg := GridContainer.new()
	cg.columns = 4
	cg.add_theme_constant_override("h_separation", 18)
	cg.add_theme_constant_override("v_separation", 6)
	if not known.is_empty():
		cur.body.add_child(cg)
	for pid in known:
		var p := state.galaxy.get_planet(pid)
		var vb := Button.new()
		vb.flat = true
		vb.focus_mode = Control.FOCUS_NONE
		vb.alignment = HORIZONTAL_ALIGNMENT_LEFT
		vb.text = Curios.describe(state, pid)
		vb.tooltip_text = "Ouvrir le système"
		var ppid := pid
		vb.pressed.connect(func() -> void: es.planet_requested.emit(ppid))
		es.chronicle_buttons["curio:%d" % pid] = vb
		cg.add_child(vb)
		cg.add_child(UiTheme.dim(p.display_name(state.galaxy), 13))
		cg.add_child(UiTheme.dim("sonde : %d jours" % Curios.duration(state, player, pid), 13))
		var prog := Curios.progress(state, player, pid)
		cg.add_child(UiTheme.dim("en cours : %d / %d" % [prog, Curios.duration(state, player, pid)] if prog > 0 else "", 13))

	var jr := Widgets.Block.new("Journal")
	col.add_child(jr)
	if log.is_empty():
		jr.body.add_child(UiTheme.dim("Aucune décision prise pour l'instant.", 14))
	for i in range(log.size() - 1, -1, -1):
		var x: Dictionary = log[i]
		var l := UiTheme.paragraph("%s  ·  %s : %s" % [GameCalendar.date_string(int(x["tick"])), x["title"], x["label"]], 900.0, 14)
		jr.body.add_child(l)


## Reliquaire : chaque relique avec son effet, son Triomphe et ses ordres (porteur, don, vente).
static func _reliquary_block(es: EmpireScreens) -> Control:
	var state := es._state
	var player := es._player
	var blk := Widgets.Block.new("Reliquaire")
	var mine := Relics.owned(state, player)
	var m: Dictionary = state.relic_meta.get(player, {})
	if not m.is_empty() and String(m["tri"]) != "" and int(m["until"]) > state.tick:
		var tl := UiTheme.paragraph("Triomphe en cours : %s (%s), encore %d jours." % [String(Relics.def(String(m["tri"]))["triumph"]["label"]),
				String(Relics.def(String(m["tri"]))["name"]), int(m["until"]) - state.tick], 900.0, 14)
		tl.add_theme_color_override("font_color", UiTheme.GOLD)
		blk.body.add_child(tl)
	if mine.is_empty() and (m.is_empty() or (m["fakes"] as Array).is_empty()):
		blk.body.add_child(UiTheme.dim("Aucune relique. Les fouilles en sortent une à la fin de leur dernier chapitre ; les espions et les conquérants en prennent aussi.", 14))
	for rid in mine:
		blk.body.add_child(_relic_row(es, rid))
	if not m.is_empty():
		for f: Dictionary in m["fakes"]:
			var d := Relics.def(String(f["relic"]))
			var row := VBoxContainer.new()
			row.add_child(UiTheme.title(String(d["name"]), 18))
			row.add_child(UiTheme.dim("Rapportée par nos agents. Son effet tarde à se manifester ; les experts sont formels, il faut lui laisser le temps.", 13))
			blk.body.add_child(row)
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 10)
	var gift := OptionButton.new()
	gift.focus_mode = Control.FOCUS_NONE
	gift.add_item("Offrir %d fragments à…" % int(Relics.data()["fragments"]["gift_lot"]))
	var targets: Array[int] = []
	for e in state.empires:
		if Relics.check_gift_fragments(state, player, e.id) == "":
			targets.append(e.id)
			gift.add_item(e.short_name())
	gift.disabled = targets.is_empty()
	gift.item_selected.connect(func(i: int) -> void:
		if i > 0:
			es.command_requested.emit(SimCommands.fragments_gift(player, targets[i - 1])))
	tools.add_child(gift)
	if Relics.can_trade(state, player):
		var sell := Button.new()
		sell.focus_mode = Control.FOCUS_NONE
		sell.text = "Vendre %d fragments (%d énergie)" % [int(Relics.data()["fragments"]["sell_lot"]), Events.era_scaled(state, player, int(Relics.data()["fragments"]["sell_energy"]))]
		var why := Relics.check_sell_fragments(state, player)
		sell.disabled = why != ""
		sell.tooltip_text = why
		sell.pressed.connect(func() -> void: es.command_requested.emit(SimCommands.fragments_sell(player)))
		es.chronicle_buttons["sell_fragments"] = sell
		tools.add_child(sell)
	blk.body.add_child(tools)
	return blk


static func _relic_row(es: EmpireScreens, rid: String) -> Control:
	var state := es._state
	var player := es._player
	var d := Relics.def(rid)
	var r: Dictionary = state.relics[rid]
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	var name_l := UiTheme.title(String(d["name"]), 18)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_l)
	var bearer := int(r["hero"])
	head.add_child(UiTheme.dim("portée par %s" % String(state.heroes[bearer]["name"]) if state.heroes.has(bearer) else "au Reliquaire", 13))
	row.add_child(head)
	row.add_child(UiTheme.dim(String(d["text"]), 13))
	var mult := Relics.holy_mult(state, player, rid)
	var passive := UiTheme.paragraph("Effet : %s%s" % [Relics.fx_text(d.get("fx", {}), mult), "  (relique sainte : ×1,5 pour la Foi)" if mult > 100 else ""], 900.0, 14)
	row.add_child(passive)
	var split := Relics.triumph_split(state, player, rid)
	var cost_txt := "%d influence" % split[0] + ((" + %d fragments" % split[1]) if split[1] > 0 else "")
	row.add_child(UiTheme.paragraph("Triomphe « %s » : %s. Coût %s, recharge 10 ans." % [String(d["triumph"]["label"]), Relics.triumph_text(state, player, rid), cost_txt], 900.0, 13))
	var orders := HBoxContainer.new()
	orders.add_theme_constant_override("separation", 10)
	var tri := Button.new()
	tri.theme_type_variation = &"PrimaryButton"
	tri.focus_mode = Control.FOCUS_NONE
	tri.text = "Triomphe"
	var why := Relics.check_triumph(state, player, rid)
	tri.disabled = why != ""
	tri.tooltip_text = why
	tri.pressed.connect(func() -> void: es.command_requested.emit(SimCommands.relic_triumph(player, rid)))
	es.chronicle_buttons["triumph:%s" % rid] = tri
	orders.add_child(tri)
	var bear := OptionButton.new()
	bear.focus_mode = Control.FOCUS_NONE
	bear.add_item("Confier à un héros…")
	var heroes: Array[int] = []
	if bearer >= 0:
		bear.add_item("Rendre au Reliquaire")
		heroes.append(-1)
	for hid in Heroes.ids_of(state, player):
		if Relics.check_assign(state, player, rid, hid) == "":
			heroes.append(hid)
			bear.add_item(String(state.heroes[hid]["name"]))
	bear.disabled = heroes.is_empty()
	bear.tooltip_text = "Un héros porteur gagne de l'expérience et du renom chaque mois. S'il est capturé, la relique part avec son geôlier."
	bear.item_selected.connect(func(i: int) -> void:
		if i > 0:
			es.command_requested.emit(SimCommands.relic_assign(player, rid, heroes[i - 1])))
	orders.add_child(bear)
	var gift := OptionButton.new()
	gift.focus_mode = Control.FOCUS_NONE
	gift.add_item("Offrir à…")
	var targets: Array[int] = []
	for e in state.empires:
		if Relics.check_gift(state, player, rid, e.id) == "":
			targets.append(e.id)
			gift.add_item(e.short_name())
	gift.disabled = targets.is_empty()
	gift.tooltip_text = "Un cadeau qui se souvient : +25 d'opinion pendant cinq ans."
	gift.item_selected.connect(func(i: int) -> void:
		if i > 0:
			es.command_requested.emit(SimCommands.relic_gift(player, rid, targets[i - 1])))
	orders.add_child(gift)
	if Relics.can_trade(state, player):
		var sell := Button.new()
		sell.focus_mode = Control.FOCUS_NONE
		sell.text = "Vendre au marché noir"
		sell.tooltip_text = "%d énergie et %d influence ; la relique repartira dans une ruine." % [Events.era_scaled(state, player, int(Relics.rules()["sell_energy"])), int(Relics.rules()["sell_influence"])]
		sell.pressed.connect(func() -> void: es.command_requested.emit(SimCommands.relic_sell(player, rid)))
		orders.add_child(sell)
	row.add_child(orders)
	return row


## Fouilles connues : chapitre, indices, chances de la prochaine phase, ordres.
static func _digs_block(es: EmpireScreens) -> Control:
	var state := es._state
	var player := es._player
	var blk := Widgets.Block.new("Fouilles")
	var sites := Relics.known_sites(state, player)
	if sites.is_empty():
		blk.body.add_child(UiTheme.dim("Aucun site connu. Ils se cachent loin des capitales, et parfois sous des ruines de haut niveau.", 14))
	for sid in sites:
		var d: Dictionary = state.digs[sid]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		var nm := Button.new()
		nm.flat = true
		nm.focus_mode = Control.FOCUS_NONE
		nm.alignment = HORIZONTAL_ALIGNMENT_LEFT
		nm.text = "%s (%s)" % [Relics.site_name(state, sid), state.galaxy.systems[sid].system_name]
		nm.custom_minimum_size = Vector2(380, 0)
		var first := int(state.galaxy.systems[sid].planet_ids[0])
		nm.pressed.connect(func() -> void: es.planet_requested.emit(first))
		row.add_child(nm)
		var status := ""
		var by := int(d["by"])
		if int(d["done"]) >= 0:
			status = "terminée par %s" % state.get_empire(int(d["done"])).short_name()
		elif Relics.hidden_from(state, player, sid):
			status = "un voile cache ce qui s'y passe"
		elif by == player and int(d["next"]) >= 0:
			status = "chapitre %d / %d · %d indice%s · difficulté %d · %d %% de réussite · jet dans %d jours" % [int(d["ch"]) + 1, int(d["chapters"]),
					int(d["clues"]), "s" if int(d["clues"]) > 1 else "", Relics.difficulty(state, sid), Relics.success_pct(state, player, sid), int(d["next"]) - state.tick]
		elif by >= 0 and int(d["next"]) >= 0:
			status = "fouillée par %s (chapitre %d / %d)" % [state.get_empire(by).short_name(), int(d["ch"]) + 1, int(d["chapters"])]
		else:
			status = "%d chapitres · difficulté %d · %s" % [int(d["chapters"]), Relics.difficulty(state, sid),
					"à vous de jouer" if state.system_owner(sid) == player else "il faut posséder le système"]
		var st_l := UiTheme.dim(status, 13)
		st_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(st_l)
		var start_why := Relics.check_start(state, player, sid)
		if Relics.is_open(state, sid) and (by != player or int(d["next"]) < 0):
			var go := Button.new()
			go.theme_type_variation = &"PrimaryButton"
			go.focus_mode = Control.FOCUS_NONE
			go.text = "Fouiller (%s)" % GameData.format_amounts(Relics.data()["digs"]["start_cost"])
			go.disabled = start_why != ""
			go.tooltip_text = start_why
			go.pressed.connect(func() -> void: es.command_requested.emit(SimCommands.dig_start(player, sid)))
			es.chronicle_buttons["dig:%d" % sid] = go
			row.add_child(go)
		elif Relics.is_open(state, sid) and by == player:
			var clue := Button.new()
			clue.focus_mode = Control.FOCUS_NONE
			clue.text = "Indice (%d fragments)" % int(Relics.data()["digs"]["clue_fragments"])
			var why := Relics.check_clue(state, player, sid)
			clue.disabled = why != ""
			clue.tooltip_text = why if why != "" else "+1 au prochain jet. Un gouverneur Intendant ajoute son niveau."
			clue.pressed.connect(func() -> void: es.command_requested.emit(SimCommands.dig_clue(player, sid)))
			es.chronicle_buttons["clue:%d" % sid] = clue
			row.add_child(clue)
		blk.body.add_child(row)
	return blk


## Ce qui change l'écran : boîte, journal, curiosités visibles et avancement des sondes.
static func signature(es: EmpireScreens) -> String:
	var state := es._state
	var player := es._player
	var s := "%s|%d" % [str(Events.inbox(state, player).map(func(it: Dictionary) -> int: return int(it["id"]))),
			(Events.meta(state, player)["log"] as Array).size() if state.ev_meta.has(player) else 0]
	for pid in Curios.known(state, player):
		s += "|%d:%d" % [pid, Curios.progress(state, player, pid)]
	if not state.relics.is_empty():
		s += str(state.relics) + str(state.relic_meta.get(player, {})) + str(state.digs) + str(state.get_empire(player).resources.get("influence", 0))
	if Quests.enabled(state):
		s += QuestPanel.signature(es)
	s += BestiaryPanel.signature(es)
	@warning_ignore("integer_division")
	return s + "|%s|%d" % [es.chron_tab, state.tick / 30]
