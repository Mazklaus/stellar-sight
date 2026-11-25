class_name CultureScreen
extends RefCounted
## Écran Rayonnement (voir Culture) : votre Rayonnement mensuel et son détail, votre Patrimoine, vos
## talents ; pour chaque empire rencontré, votre palier chez lui (cumul ÷ son Patrimoine, tendance,
## mois avant le palier suivant), le sien chez vous et ce qui module la diffusion ; l'osmose proposée,
## les savoirs ouverts par osmose, les défections en cours, ambassades et Troupe de spectacle.
## Construit dans les conteneurs d'EmpireScreens, dont il reprend les aides (_grid, _key_value…).


static func build(es: EmpireScreens) -> void:
	var state := es._state
	var player := es._player
	es._culture_sig = signature(es)
	es._side_header("screen_culture", "Rayonnement", Color(0.86, 0.62, 0.86), "faction")
	if not Culture.enabled(state):
		es._side_box.add_child(UiTheme.paragraph("Dans cette partie, le rayonnement culturel n'est pas en jeu (Nouvelle partie : Rayonnement culturel).", EmpireScreens.SIDE_WIDTH - 24.0, 13))
		return
	var g := es._grid()
	es._side_box.add_child(g)
	var rl := es._key_value(g, "Rayonnement", "%d / mois" % Culture.radiance(state, player))
	rl.tooltip_text = radiance_tip(state, player)
	rl.mouse_filter = Control.MOUSE_FILTER_STOP
	var pl := es._key_value(g, "Patrimoine", str(Culture.heritage(state, player)))
	pl.tooltip_text = "Votre influence cumulée, vos lois, vos reliques, vos merveilles et l'âge de vos colonies : la culture des autres se mesure à lui.\nCe mois-ci : +%d." % Culture._heritage_rate(state, player)
	pl.mouse_filter = Control.MOUSE_FILTER_STOP
	var top := Culture.top_influencer(state, player)
	if int(top[1]) >= 0:
		var dl := es._key_value(g, "Culture dominante", state.get_empire(int(top[1])).short_name())
		dl.tooltip_text = "La culture étrangère la plus avancée chez vous : %s, %s." % [state.get_empire(int(top[1])).display_name(), Culture.tier_label(int(top[0])).to_lower()]
		dl.mouse_filter = Control.MOUSE_FILTER_STOP
	var inc := Culture.income(state, player)
	if not inc.is_empty():
		es._key_value(g, "Revenu culturel", GameData.format_amounts(inc))
	var ex := Culture.exposed(state, player)
	var tl := Culture.talent_labels(state, player)
	if not tl.is_empty():
		es._side_box.add_child(HSeparator.new())
		es._side_box.add_child(UiTheme.dim("Talents de votre peuple", 13))
		for t in tl:
			es._side_box.add_child(UiTheme.paragraph("%s : %s" % [t[0], t[1]], EmpireScreens.SIDE_WIDTH - 24.0, 12))
	es._side_box.add_child(HSeparator.new())
	es._side_box.add_child(UiTheme.paragraph("Le Rayonnement part chaque mois vers chaque empire rencontré et s'y cumule. Rapporté au Patrimoine de la cible, il donne un palier : Exotique (10 %), Familier (30 %), En vogue (60 %), Influent (100 %), Dominant (200 %). Routes commerciales, droit de passage, même foi et luxes exportés l'accélèrent ; gouvernements et credos opposés, frontières fermées et l'absence de tout lien le freinent ; la guerre et l'embargo le coupent.", EmpireScreens.SIDE_WIDTH - 24.0, 12))

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	es._content.add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 18)
	scroll.add_child(col)

	var offer := CultureLife.pending_offer(state, player)
	if not offer.is_empty():
		var ob := Widgets.Block.new("Osmose des lois")
		col.add_child(ob)
		var lid := String(offer["law"])
		ob.body.add_child(UiTheme.paragraph("Chez vous, on réclame « %s », une loi de %s : %s Adoptée, elle est gratuite et rapproche vos deux peuples ; refusée, la rue gronde (stabilité %d pendant un an). Réponse avant le %s, sinon c'est un refus." % [
				String(Laws.law_def(lid).get("label", lid)), state.get_empire(int(offer["from"])).display_name(), String(Laws.law_def(lid).get("text", "")),
				int(CultureLife.ef()["law_refuse_stability"]), GameCalendar.date_string(int(offer["until"]))], 760.0, 14))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		ob.body.add_child(row)
		for pair in [["Adopter", 1], ["Refuser", 0]]:
			var b := Button.new()
			b.text = String(pair[0])
			b.focus_mode = Control.FOCUS_NONE
			var nn := int(pair[1])
			b.pressed.connect(func() -> void: es.command_requested.emit(SimCommands.cul_act(player, "osmose", -1, "", nn)))
			row.add_child(b)
			es.culture_buttons["osmose:%d" % nn] = b

	var tb := Widgets.Block.new("Votre culture dans la galaxie")
	col.add_child(tb)
	tb.body.add_child(_tier_scale())
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 6)
	tb.body.add_child(grid)
	for h in ["Empire", "Votre culture chez lui", "Diffusion", "La sienne chez vous", ""]:
		grid.add_child(UiTheme.dim(h, 13))
	var tg := Culture.targets(state, player)
	if tg.is_empty():
		tb.body.add_child(UiTheme.dim("Aucun empire rencontré : votre culture n'a encore personne à séduire.", 14))
	for b in tg:
		_row(es, grid, b)

	if Culture.has_museum(state, player):
		col.add_child(_museum_block(state, ex))

	var defs := CultureLife.defections_of(state, player)
	if not defs.is_empty():
		var db := Widgets.Block.new("Défections culturelles en cours")
		col.add_child(db)
		for d in defs:
			var gain := int(d[1]) == player
			db.body.add_child(UiTheme.paragraph("%s %s %s dans %s%s" % [state.galaxy.systems[int(d[0])].system_name, "pourrait vous rejoindre, quittant" if gain else "pourrait partir chez",
					state.get_empire(int(d[3])).short_name() if gain else state.get_empire(int(d[1])).short_name(), Victory._days_text(int(d[2])),
					"." if gain else " : rétablissez la stabilité, fermez vos frontières ou votez l'Exception culturelle."], 760.0, 14))

	var offers := CultureLife.tech_offers(state, player)
	if not offers.is_empty():
		var kb := Widgets.Block.new("Osmose des savoirs")
		col.add_child(kb)
		kb.body.add_child(UiTheme.paragraph("Les cultures En vogue chez vous vous ouvrent leurs savoirs : on les apprend contre de l'énergie, sans les rechercher.", 760.0, 13))
		for tid: String in offers.slice(0, 8):
			var r := HBoxContainer.new()
			r.add_theme_constant_override("separation", 10)
			var l := Label.new()
			l.text = "%s (%s)" % [String(Research.tech(tid).get("label", tid)), GameData.format_amounts(CultureLife.tech_cost(state, player, tid))]
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			r.add_child(l)
			var bb := Button.new()
			bb.text = "Apprendre"
			bb.focus_mode = Control.FOCUS_NONE
			var why := CultureLife.check_tech(state, player, tid)
			bb.disabled = why != ""
			bb.tooltip_text = why
			var t2: String = tid
			bb.pressed.connect(func() -> void: es.command_requested.emit(SimCommands.cul_act(player, "savoir", -1, t2)))
			r.add_child(bb)
			es.culture_buttons["savoir:" + tid] = bb
			kb.body.add_child(r)

	if Victory.enabled(state, "rayonnement"):
		var vb := Widgets.Block.new("Le Grand Rayonnement")
		col.add_child(vb)
		var pr := Victory.progress(state, player, "rayonnement")
		vb.body.add_child(UiTheme.paragraph("%s\n%s" % [Victory.rule_text("rayonnement"), "\n".join(pr["lines"])], 760.0, 13))


static func _row(es: EmpireScreens, grid: GridContainer, b: int) -> void:
	var state := es._state
	var player := es._player
	var minor := GameState.is_minor(b)
	var name := Label.new()
	name.text = Culture.target_name(state, b)
	grid.add_child(name)
	var t := Culture.tier(state, player, b)
	var mine := Label.new()
	var trend := Culture.last(state, player, b)
	var nx := Culture.months_to_next(state, player, b)
	mine.text = "%s  %d %%  +%d/mois%s" % [Culture.tier_label(t), Culture.ratio_pct(state, player, b), trend,
			("  (palier suivant : %d mois)" % nx) if nx > 0 else ""]
	mine.add_theme_color_override("font_color", Culture.tier_color(t).lightened(0.2))
	mine.tooltip_text = "%s\nCumul reçu : %d ; son Patrimoine : %d." % [String(Culture.tiers()[t]["text"]), Culture.cumul(state, player, b), Culture.heritage(state, b)]
	mine.mouse_filter = Control.MOUSE_FILTER_STOP
	grid.add_child(_with_dot(t, mine))
	var fp := Culture.flow_parts(state, player, b)
	var fl := Label.new()
	fl.text = ("coupée (%s)" % fp["cut"]) if String(fp["cut"]) != "" else "%d %%" % Culture.flow_pct(state, player, b, fp)
	var lines := PackedStringArray()
	for p in fp["parts"]:
		lines.append("%s : %+d %%" % [p[0], int(p[1])])
	fl.tooltip_text = "Diffusion de votre Rayonnement chez lui (100 % de base)\n" + ("\n".join(lines) if not lines.is_empty() else "aucun modificateur")
	fl.mouse_filter = Control.MOUSE_FILTER_STOP
	grid.add_child(fl)
	var theirs := Label.new()
	if minor:
		theirs.text = "-"
		grid.add_child(theirs)
	else:
		var t2 := Culture.tier(state, b, player)
		theirs.text = "%s  %d %%" % [Culture.tier_label(t2), Culture.ratio_pct(state, b, player)]
		theirs.add_theme_color_override("font_color", Culture.tier_color(t2).lightened(0.2))
		grid.add_child(_with_dot(t2, theirs))
	var acts := HBoxContainer.new()
	acts.add_theme_constant_override("separation", 6)
	grid.add_child(acts)
	if minor:
		return
	var has_emb := CultureBridges.embassies(state, player).has(b)
	var eb := Button.new()
	eb.focus_mode = Control.FOCUS_NONE
	eb.text = "Fermer l'ambassade" if has_emb else "Ambassade"
	var why := CultureBridges.check_act(state, player, "fermer" if has_emb else "ambassade", b, "", -1)
	eb.disabled = why != ""
	eb.tooltip_text = why if why != "" else ("Ambassade culturelle : diffusion +%d %% chez lui (seulement chez un autre credo), pour %s." % [int(Culture.data()["embassy"]["pct"]), GameData.format_amounts(Culture.data()["embassy"]["cost"])])
	eb.pressed.connect(func() -> void: es.command_requested.emit(SimCommands.cul_act(player, "fermer" if has_emb else "ambassade", b)))
	acts.add_child(eb)
	es.culture_buttons["ambassade:%d" % b] = eb
	var tr := Button.new()
	tr.focus_mode = Control.FOCUS_NONE
	tr.text = "Troupe"
	var why2 := CultureBridges.check_act(state, player, "troupe", b, "", -1)
	tr.disabled = why2 != ""
	tr.tooltip_text = why2 if why2 != "" else "Troupe de spectacle : trois mois de tournée, puis un spectacle au succès incertain (triomphe, succès, four ou scandale), pour %s." % GameData.format_amounts(CultureBridges.troupe_cost(state, player))
	tr.pressed.connect(func() -> void: es.command_requested.emit(SimCommands.cul_act(player, "troupe", b)))
	acts.add_child(tr)
	es.culture_buttons["troupe:%d" % b] = tr


## Un palier se lit d'abord à sa pastille : la même couleur que sur l'échelle en tête du tableau.
static func _with_dot(tier: int, label: Control) -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var dot := Widgets.Dot.new(Culture.tier_color(tier), 12.0)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(dot)
	box.add_child(label)
	return box


## L'échelle des paliers, du plus faible au plus fort : [palier, libellé, seuil en %].
static func tier_scale() -> Array:
	var out := []
	for i in Culture.tiers().size():
		out.append([i, Culture.tier_label(i), int(Culture.tiers()[i].get("min", 0))])
	return out


static func _tier_scale() -> Control:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 18)
	for e in tier_scale():
		var l := UiTheme.dim("%s  %d %%" % [e[1], e[2]] if int(e[2]) > 0 else String(e[1]), 12)
		l.tooltip_text = String(Culture.tiers()[int(e[0])].get("text", ""))
		l.mouse_filter = Control.MOUSE_FILTER_STOP
		row.add_child(_with_dot(int(e[0]), l))
	return row


## Le Musée galactique en vitrine : une case par emplacement, vide tant qu'aucune relique ne l'occupe.
static func _museum_block(state: GameState, ex: Array[String]) -> Control:
	var b := Widgets.Block.new("Musée galactique")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	b.body.add_child(row)
	var slots := int(Culture.data()["sources"]["museum_slots"])
	for i in slots:
		var held := i < ex.size()
		var rid := ex[i] if held else ""
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 4)
		var slot := Widgets.ArtSlot.new(("relic_" + rid) if held else "", Vector2(150, 100), UiTheme.GOLD if held else Color(0.5, 0.6, 0.7), "star" if held else "lock")
		slot.mouse_filter = Control.MOUSE_FILTER_STOP
		if held:
			slot.variant = rid.hash() % 97
			slot.set_icon("relique", rid, 44.0)
			slot.tooltip_text = String(Relics.def(rid).get("text", ""))
		else:
			slot.tooltip_text = "Vitrine vide : il faut une relique au Reliquaire, que nul héros ne porte."
		cell.add_child(slot)
		var cap := UiTheme.paragraph(String(Relics.def(rid).get("name", rid)) if held else "Vitrine vide", 150.0, 12)
		if not held:
			cap.modulate = Color(1, 1, 1, 0.6)
		cell.add_child(cap)
		row.add_child(cell)
	var th := Culture.theme_of(ex)
	var note := "Thème complet (%s) : le Rayonnement du Musée est doublé." % th if th != "" else ("Aucune relique au Reliquaire à exposer." if ex.is_empty() else "Trois reliques d'un même thème doublent le Rayonnement du Musée.")
	b.body.add_child(UiTheme.dim(note, 13))
	return b


static func radiance_tip(state: GameState, eid: int) -> String:
	var lines := PackedStringArray(["Rayonnement mensuel, avant diffusion :"])
	for p in Culture.source_parts(state, eid):
		lines.append("%s : +%d" % [p[0], int(p[1])])
	if Culture.source_parts(state, eid).is_empty():
		lines.append("aucune source (population en révolte, ou peuple qui ne rayonne pas)")
	lines.append("Bonus : %+d %%" % (Culture.radiance_pct(state, eid) - 100))
	var al := CultureBridges.ally_share(state, eid)
	if al > 0:
		lines.append("Part de vos alliés : +%d" % al)
	return "\n".join(lines)


## Ce qui change l'écran : mois écoulé, offres, ambassades, troupes, ressources pour les boutons.
static func signature(es: EmpireScreens) -> String:
	var state := es._state
	if not Culture.enabled(state):
		return "off"
	var e := state.get_empire(es._player)
	return "%d|%s|%s|%s|%s|%d|%d" % [int(state.tick / 30.0), str(CultureLife.pending_offer(state, es._player)), str(CultureBridges.embassies(state, es._player)),
			str(CultureBridges.troupes_of(state, es._player).size()), str(e.contacts), int(e.resources.get("energy", 0)) / 100, int(e.resources.get("influence", 0)) / 50]
