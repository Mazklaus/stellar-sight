class_name ArchaeoUi
extends RefCounted
## Onglet « Archéologie » des Chroniques (prop. 42) : sites et méthode de fouille, pistes des Disparus,
## musée et antiquités, actions de fragments, Bibliothèque d'Aster et Collectionneur. Remplace la liste des
## fouilles du Reliquaire quand les Strates sont en jeu (réglage Complète).


static func build(es: EmpireScreens, col: VBoxContainer) -> void:
	col.add_child(_sites_block(es))
	col.add_child(_trails_block(es))
	col.add_child(_museum_block(es))
	col.add_child(_actions_block(es))


static func signature(es: EmpireScreens) -> String:
	if not Archaeology.enabled(es._state):
		return ""
	return "%d" % hash([es._state.archaeo, es._state.digs, Relics.fragments(es._state, es._player)])


static func _button(es: EmpireScreens, text: String, why: String, tip: String, key: String, cmd: Dictionary, primary := false) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	if primary:
		b.theme_type_variation = &"PrimaryButton"
	b.text = text
	b.disabled = why != ""
	b.tooltip_text = why if why != "" else tip
	b.pressed.connect(func() -> void: es.command_requested.emit(cmd))
	es.chronicle_buttons[key] = b
	return b


static func _sites_block(es: EmpireScreens) -> Control:
	var state := es._state
	var player := es._player
	var blk := Widgets.Block.new("Sites de fouille")
	var intro := UiTheme.paragraph("Méthode : Prudente (lente, sans incident grave, une antiquité de plus), Méthodique, ou Pillage (rapide, butin réduit, site détruit). Hors de chez vous : une flotte à l'arrêt sur un système libre, ou un permis de fouille.", 900.0, 13)
	intro.modulate = Color(1, 1, 1, 0.7)
	blk.body.add_child(intro)
	var sites := Relics.known_sites(state, player)
	if sites.is_empty():
		blk.body.add_child(UiTheme.dim("Aucun site connu. Les plus anciens (strate Première) demandent une détection de niveau 3.", 14))
	for sid in sites:
		var d: Dictionary = state.digs[sid]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var nm := Button.new()
		nm.flat = true
		nm.focus_mode = Control.FOCUS_NONE
		nm.alignment = HORIZONTAL_ALIGNMENT_LEFT
		nm.text = "%s (%s)" % [Relics.site_name(state, sid), state.galaxy.systems[sid].system_name]
		nm.tooltip_text = Archaeology.site_desc(state, player, sid)
		nm.custom_minimum_size = Vector2(300, 0)
		nm.clip_text = true
		var first := int(state.galaxy.systems[sid].planet_ids[0])
		nm.pressed.connect(func() -> void: es.planet_requested.emit(first))
		row.add_child(nm)
		var by := int(d["by"])
		var status := Archaeology.site_desc(state, player, sid)
		if int(d["done"]) >= 0:
			status += " · terminé par %s" % state.get_empire(int(d["done"])).short_name()
			if Archaeology.sub(state, "hl").has(str(sid)):
				status += " · Haut lieu"
		elif Relics.hidden_from(state, player, sid):
			status += " · un voile cache ce qui s'y passe"
		elif by == player and int(d["next"]) >= 0:
			status += " · %s · chapitre %d / %d · %d %% · jet dans %d jours" % [Archaeology.method_label(String(d.get("me", ""))), int(d["ch"]) + 1, int(d["chapters"]),
					Relics.success_pct(state, player, sid), int(d["next"]) - state.tick]
		elif by >= 0 and int(d["next"]) >= 0:
			status += " · fouillé par %s" % state.get_empire(by).short_name()
		var st_l := UiTheme.paragraph(status, 420.0, 13)
		st_l.modulate = Color(1, 1, 1, 0.7)
		st_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(st_l)
		if Relics.is_open(state, sid) and (by != player or int(d["next"]) < 0):
			for m in ["prudente", "methodique", "pillage"]:
				var why := Relics.check_start(state, player, sid, m)
				row.add_child(_button(es, Archaeology.method_label(m), why, String((Archaeology.methods().get(m, {}) as Dictionary).get("text", "")),
						"dig:%d:%s" % [sid, m], SimCommands.dig_start(player, sid, m), m == "methodique"))
		elif Relics.is_open(state, sid) and by == player:
			row.add_child(_button(es, "Indice (%d fragments)" % int(Relics.data()["digs"]["clue_fragments"]), Relics.check_clue(state, player, sid),
					"+1 au prochain jet.", "clue:%d" % sid, SimCommands.dig_clue(player, sid)))
		blk.body.add_child(row)
	return blk


static func _trails_block(es: EmpireScreens) -> Control:
	var state := es._state
	var player := es._player
	var blk := Widgets.Block.new("Les Disparus")
	for d in Archaeology.in_game_disparus(state):
		var dd := Archaeology.disparu_def(d)
		var v := ArchaeoWorld.vestiges(state, player, d)
		var known := ArchaeoWorld.cradle_known(state, player, d)
		var title := String(dd.get("label", d)).capitalize() if v > 0 else "Un peuple dont on ne sait rien"
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var l := UiTheme.paragraph("%s · %d / %d vestiges%s%s" % [title, v, Archaeology.r_int("vestiges_for_cradle", 6),
				(" · Monde-berceau à %s" % state.galaxy.systems[int(ArchaeoWorld.cradle_of(state, d)["s"])].system_name) if known else "",
				(" · %d antiquité(s)" % ArchaeoWorld.antiqs_of_disparu(state, player, d).size()) if v > 0 else ""], 560.0, 13)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		if v > 0:
			row.add_child(_button(es, "Reconstitution", ArchaeoWorld.check_reco(state, player, d), String((dd.get("reco", {}) as Dictionary).get("text", "")),
					"reco:%s" % d, SimCommands.ar_act(player, "reco", {"d": d})))
		if known:
			row.add_child(_button(es, "Secrets (%d fragments)" % Archaeology.r_int("secrets_fragments", 300), ArchaeoWorld.check_secrets(state, player, d),
					String((dd.get("secrets", {}) as Dictionary).get("text", "")), "secrets:%s" % d, SimCommands.ar_act(player, "secrets", {"d": d})))
		blk.body.add_child(row)
		if known:
			var lore := UiTheme.paragraph(String(dd.get("lore", "")), 900.0, 12)
			lore.modulate = Color(1, 1, 1, 0.65)
			blk.body.add_child(lore)
	return blk


static func _museum_block(es: EmpireScreens) -> Control:
	var state := es._state
	var player := es._player
	var blk := Widgets.Block.new("Antiquités")
	var mine := Archaeology.antiqs_of(state, player)
	var slots := ArchaeoWorld.museum_slots(state, player)
	blk.body.add_child(UiTheme.dim("%d antiquité(s) · %s%s" % [mine.size(),
			("%d place(s) au Musée galactique" % slots) if slots > 0 else "pas de place au musée (il faut le Musée galactique)",
			" · salle à thème" if ArchaeoWorld.has_theme(state, player) else ""], 13))
	for id in mine:
		var a := Archaeology.antiq(state, id)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var l := UiTheme.paragraph("%s · %s · strate %s · %s" % [String(a.get("n", "")), Archaeology.type_label(String(a.get("t", ""))),
				Archaeology.strata_label(int(a.get("sr", 1))).to_lower(), Relics.fx_text(Archaeology.antiq_fx(state, id))], 600.0, 13)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		row.add_child(_button(es, "Restituer", ArchaeoBridges.check(state, player, "restitute", {"id": id}), "Rendre la pièce à son peuple : forte opinion.",
				"restitute:%d" % id, SimCommands.ar_act(player, "restitute", {"id": id})))
		var sell_why := ArchaeoBridges.check(state, player, "sell_antiq", {"id": id})
		if sell_why == "":
			row.add_child(_button(es, "Marché noir", "", "Vendre la pièce sans facture.", "sell:%d" % id, SimCommands.ar_act(player, "sell_antiq", {"id": id})))
		var col_why := ArchaeoBridges.check(state, player, "collector_sell", {"id": id})
		if col_why == "":
			row.add_child(_button(es, "Au Collectionneur", "", "Il paie double une pièce de strate Première.", "colsell:%d" % id, SimCommands.ar_act(player, "collector_sell", {"id": id})))
		blk.body.add_child(row)
	var col := Archaeology.sub(state, "col")
	if int(col.get("until", 0)) > state.tick:
		blk.body.add_child(UiTheme.dim("Le Collectionneur est à %s jusqu'au jour %d." % [state.galaxy.systems[int(col["s"])].system_name, int(col["until"])], 13))
		var stock: Array = col.get("stock", [])
		for i in stock.size():
			var row2 := HBoxContainer.new()
			var l2 := UiTheme.dim(Archaeology.antiq_name(state, int(stock[i])), 13)
			l2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row2.add_child(l2)
			row2.add_child(_button(es, "Acheter (%s)" % GameData.format_amounts(Archaeology.rule("collector_buy")), ArchaeoBridges.check(state, player, "collector_buy", {"i": i}),
					"", "colbuy:%d" % i, SimCommands.ar_act(player, "collector_buy", {"i": i})))
			blk.body.add_child(row2)
	return blk


static func _actions_block(es: EmpireScreens) -> Control:
	var state := es._state
	var player := es._player
	var blk := Widgets.Block.new("Actions de fragments (%d / %d)" % [Relics.fragments(state, player), Archaeology.frag_cap(state)])
	var acts := Archaeology.actions().keys()
	acts.sort()
	for act in acts:
		var ad := Archaeology.action_def(String(act))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var l := UiTheme.paragraph(String(ad.get("text", "")), 600.0, 13)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		row.add_child(_button(es, "%s (%d)" % [String(ad.get("label", act)), int(ad.get("cost", 0))], Archaeology.check(state, player, String(act), {}),
				String(ad.get("text", "")), "fa:%s" % act, SimCommands.ar_act(player, String(act))))
		blk.body.add_child(row)
	# Trois natures de fragments (prop. 5) : trois identiques se forgent en relique.
	for k in Archaeology.nature_ids():
		var nd := Archaeology.nature_def(k)
		var rown := HBoxContainer.new()
		rown.add_theme_constant_override("separation", 12)
		var ln := UiTheme.paragraph("Fragments %s : %d / %d · %s" % [String(nd.get("label", k)).to_lower(), Archaeology.nat(state, player, k), Archaeology.forge_need(),
				String(nd.get("text", ""))], 600.0, 13)
		ln.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rown.add_child(ln)
		rown.add_child(_button(es, "Forger", Archaeology.check(state, player, "forge", {"k": k}), "Trois fragments identiques donnent une relique encore libre, sinon un bienfait de leur nature.",
				"forge:%s" % k, SimCommands.ar_act(player, "forge", {"k": k})))
		blk.body.add_child(rown)
	var row2 := HBoxContainer.new()
	var l3 := UiTheme.paragraph("Bibliothèque d'Aster : un archéologue prêté pour dix ans (+%d aux jets)." % Archaeology.r_int("aster_skill", 2), 600.0, 13)
	l3.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.add_child(l3)
	row2.add_child(_button(es, "Demander (%s)" % GameData.format_amounts(Archaeology.rule("aster_cost")), ArchaeoBridges.check(state, player, "aster", {}), "",
			"aster", SimCommands.ar_act(player, "aster")))
	blk.body.add_child(row2)
	return blk
