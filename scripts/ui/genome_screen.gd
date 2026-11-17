class_name GenomeScreen
extends RefCounted
## Écran Génome (voir Genetics, prop. 39) : programmes en cours, voie d'élévation, et pour chaque
## espèce qui vit chez vous sa fiche façonnée (traits, marge, plafond) et les changements possibles :
## ajouter ou retirer un trait, acclimater, « Chair et acier », Grand Transfert, lignée, abrutir,
## greffer ; héritiers façonnés, dons aux peuples mineurs, cliniques du Syndicat.
## Construit dans les conteneurs d'EmpireScreens, dont il reprend les aides (_grid, _key_value…).

const COLOR := Color(0.55, 0.85, 0.7)


static func build(es: EmpireScreens) -> void:
	var state := es._state
	var player := es._player
	es._genome_sig = signature(es)
	es._side_header("screen_genome", "Génome", COLOR, "faction")
	if not Genetics.applies(state, player):
		es._side_box.add_child(UiTheme.paragraph("Dans cette partie, l'ingénierie des espèces n'est pas en jeu (Nouvelle partie : Ingénierie des espèces).", EmpireScreens.SIDE_WIDTH - 24.0, 13))
		return
	var e := state.get_empire(player)
	var g := es._grid()
	es._side_box.add_child(g)
	es._key_value(g, "Réglage", Genetics.mode_label(state))
	var pd := Genetics.path_def(e.gene_path)
	es._key_value(g, "Voie d'élévation", String(pd.get("label", "aucune")))
	es._key_value(g, "Programmes achevés", str(Genetics.programs_done(state, player)))
	es._key_value(g, "Programmes à la fois", str(Genetics.max_programs(state, player)))
	es._key_value(g, "Technologies du pilier", "%d / %d" % [Genetics.tech_count(state, player), Genetics.c_int("margin", "tech_max", 4)])
	if GeneticsBridges.contaminated(state, player):
		es._key_value(g, "Cuves contaminées", "jusqu'au %s" % GameCalendar.date_string(int(Genetics.sub(state, "contam")[str(player)])))
	var tl := Genetics.talent_labels(state, player)
	if not tl.is_empty():
		es._side_box.add_child(HSeparator.new())
		es._side_box.add_child(UiTheme.dim("Talents de votre peuple", 13))
		for t in tl:
			es._side_box.add_child(UiTheme.paragraph("%s : %s" % [t[0], t[1]], EmpireScreens.SIDE_WIDTH - 24.0, 12))
	es._side_box.add_child(HSeparator.new())
	es._side_box.add_child(UiTheme.dim("Voie d'élévation", 13))
	if e.gene_path == "":
		for p: Dictionary in Genetics.path_defs():
			var pid := String(p["id"])
			var b := _btn(es, String(p["label"]), Genetics.check_path(state, player, pid), "%s\n%s" % [String(p["label"]), String(p["text"])],
					SimCommands.gen_act(player, "path", {"path": pid}), "path:" + pid)
			es._side_box.add_child(b)
	else:
		es._side_box.add_child(UiTheme.paragraph(String(pd.get("text", "")), EmpireScreens.SIDE_WIDTH - 24.0, 12))
		if e.gene_path == "purete":
			es._side_box.add_child(_btn(es, "Renier la Pureté", Genetics.check_renounce(state, player), "Le serment s'efface : crise de stabilité (%d) pendant deux ans, et plus jamais de serment." % int(Genetics.cfg("paths").get("renounce", {}).get("stability", -20)),
					SimCommands.gen_act(player, "renounce"), "renounce"))
	es._side_box.add_child(HSeparator.new())
	es._side_box.add_child(UiTheme.paragraph("Un programme change une espèce chez vous seulement. Il se paie en Savoir (matériaux pour un corps synthétique), en mensualités prises sur le stock avant la recherche ; l'effet tombe à la fin. La marge d'une espèce monte avec les technologies du pilier (4 au plus), le Codex des origines et la voie génétique ; un défaut rend ses points.", EmpireScreens.SIDE_WIDTH - 24.0, 12))

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	es._content.add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 18)
	scroll.add_child(col)

	var progs := Genetics.programs(state, player)
	var pb := Widgets.Block.new("Programmes en cours (%d / %d)" % [progs.size(), Genetics.max_programs(state, player)])
	col.add_child(pb)
	if progs.is_empty():
		pb.body.add_child(UiTheme.dim("Aucun programme : les cuves attendent.", 14))
	for p: Dictionary in progs:
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 10)
		var l := Label.new()
		l.text = "%s : %d / %d %s, encore %d mois environ" % [prog_label(state, player, p), int(p.get("paid", 0)), int(p["cost"]),
				"matériaux" if String(p.get("res", "")) == "materials" else "Savoir", Genetics.months_left(p)]
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(l)
		r.add_child(_btn(es, "Annuler", "", "La moitié de ce qui a été versé revient.", SimCommands.gen_act(player, "cancel", {"id": int(p["id"])}), "cancel:%d" % int(p["id"])))
		pb.body.add_child(r)

	for fid in Genetics.species_of(state, player):
		_species_block(es, col, fid)
	for lid in GeneticsBridges.lineages_of(state, player):
		var lb := Widgets.Block.new("Lignée : %s" % String(GameData.faction(lid).get("name", lid)))
		col.add_child(lb)
		lb.body.add_child(UiTheme.paragraph("Traits : %s. %d habitants." % [_traits_text(GameData.faction(lid)), Genetics.pop_of(state, player, lid)], 760.0, 13))

	var ob := Widgets.Block.new("Cour, alliés et marché noir")
	col.add_child(ob)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	ob.body.add_child(row)
	row.add_child(_btn(es, "Héritiers façonnés (%d Savoir)" % Genetics.c_int("cost", "heir", 200), GeneticsBridges.check_heir(state, player),
			"Vos héritiers gagnent +1 dans chaque aptitude.", SimCommands.gen_act(player, "heir"), "heir"))
	if Minors.enabled(state):
		for mid in Minors.met(state, player):
			row.add_child(_btn(es, "Don génétique : %s" % Minors.short_of(state, mid), GeneticsBridges.check_gift(state, player, mid),
					"Un programme offert (%d Savoir) : +%d de faveur." % [Genetics.c_int("cost", "gift", 150), Genetics.c_int("gift", "relation", 40)],
					SimCommands.gen_act(player, "gift", {"minor": mid}), "gift:%d" % mid))
	for tid in GeneticsBridges.clinic_offers(state, player):
		row.add_child(_btn(es, "Clinique : %s (%d énergie)" % [Genetics.trait_label(tid), GeneticsBridges.clinic_price(tid)], GeneticsBridges.check_clinic(state, player, tid),
				String(Genetics.trait_def(tid).get("text", "")), SimCommands.gen_act(player, "clinic", {"trait": tid}), "clinic:" + tid))
	var known: Array = Genetics.sub(state, "stolen").get(str(player), []) + Genetics.sub(state, "samples").get(str(player), [])
	if not known.is_empty():
		var names := PackedStringArray()
		for tid in known:
			names.append(Genetics.trait_label(String(tid)))
		ob.body.add_child(UiTheme.paragraph("Génomes acquis (volés, achetés, échantillons) : %s." % ", ".join(names), 760.0, 13))


static func prog_label(state: GameState, player: int, p: Dictionary) -> String:
	var who := Genetics.label(state, player, String(p.get("fid", "")))
	match String(p.get("kind", "")):
		"mod":
			var parts := PackedStringArray()
			for t in p.get("add", []):
				parts.append("+" + Genetics.trait_label(String(t)))
			for t in p.get("rem", []):
				parts.append("-" + Genetics.trait_label(String(t)))
			if String(p.get("bio", "")) != "":
				parts.append("acclimatation")
			return "%s (%s)" % [who, ", ".join(parts)]
		"cyber":
			return "%s : Chair et acier" % who
		"transfer":
			return "%s : Grand Transfert" % who
		"lineage":
			return "%s : nouvelle lignée" % who
		"staple":
			return "%s : abrutissement" % who
		"heir":
			return "Héritiers façonnés"
		"gift":
			return "Don génétique"
	return who


static func _traits_text(f: Dictionary) -> String:
	var names := PackedStringArray()
	for t in Genetics.traits_of(f):
		names.append(Genetics.trait_label(String(t)))
	return ", ".join(names) if not names.is_empty() else "aucun"


static func _species_block(es: EmpireScreens, col: VBoxContainer, fid: String) -> void:
	var state := es._state
	var player := es._player
	var e := state.get_empire(player)
	var f := Genetics.fiche(state, player, fid)
	var b := Widgets.Block.new("%s%s" % [String(f.get("name", fid)), " (votre peuple)" if fid == e.faction_id else ""])
	col.add_child(b)
	var arch := String(FactionTraits.species(f).get("archetype", ""))
	b.body.add_child(UiTheme.paragraph("%d habitants · %s · traits : %s · marge %d / %d · plafond %d traits%s" % [
			Genetics.pop_of(state, player, fid), arch, _traits_text(f), Genetics.margin_left(state, player, fid), Genetics.margin_total(state, player, fid),
			Genetics.trait_cap(state, player, fid), " · cybernétique" if bool(f.get("cyber", false)) else ""], 760.0, 13))
	var voies := Genetics.voies_of(f, e.gene_path)
	var extra: Array = Genetics.sub(state, "stolen").get(str(player), []) + Genetics.sub(state, "samples").get(str(player), [])
	var cur := Genetics.traits_of(f)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 4)
	b.body.add_child(flow)
	for t: Dictionary in Genetics.catalogue():
		var tid := String(t["id"])
		if cur.has(tid):
			continue
		var v := String(t["voie"])
		if not voies.has(v) and not extra.has(tid):
			continue
		var cost := Genetics.mod_cost(state, player, fid, [tid], [], "")
		flow.add_child(_btn(es, "+%s (%d)" % [String(t["label"]), int(t.get("cost", 0))], Genetics.check_mod(state, player, fid, [tid], [], ""),
				"%s (%s, %d point(s)) : %s\nProgramme : %d %s." % [String(t["label"]), Genetics.voie_label(v), int(t.get("cost", 0)), String(t.get("text", "")), cost,
				"matériaux" if Genetics.resource_for(state, player, fid) == "materials" else "Savoir"],
				SimCommands.gen_act(player, "mod", {"fid": fid, "add": [tid]}), "add:%s:%s" % [fid, tid]))
	for tid in cur:
		if Genetics.trait_def(String(tid)).is_empty():
			continue
		flow.add_child(_btn(es, "-%s" % Genetics.trait_label(String(tid)), Genetics.check_mod(state, player, fid, [], [tid], ""),
				"Retirer %s : %d point(s) rendus." % [Genetics.trait_label(String(tid)), Genetics.trait_cost(String(tid))],
				SimCommands.gen_act(player, "mod", {"fid": fid, "rem": [tid]}), "rem:%s:%s" % [fid, String(tid)]))
	var acts := HFlowContainer.new()
	acts.add_theme_constant_override("h_separation", 6)
	b.body.add_child(acts)
	if Genetics.has_power(state, player, "biome") or Genetics.free_biome_ready(state, player):
		var pref: Array = f.get("preferred", [])
		for bio in Species.parts()["biomes"]:
			if not pref.is_empty() and String(pref[0]) == String(bio):
				continue
			if pref.size() >= 2 and String(pref[1]) == String(bio):
				continue
			acts.add_child(_btn(es, "Acclimater : %s" % String(GameData.planet_type(String(bio)).get("label", bio)), Genetics.check_mod(state, player, fid, [], [], String(bio)),
					"Second biome changé (le monde natal ne change jamais).", SimCommands.gen_act(player, "mod", {"fid": fid, "bio": String(bio)}), "bio:%s:%s" % [fid, String(bio)]))
	if Genetics.is_organic(f) and not bool(f.get("cyber", false)) and Genetics.has_power(state, player, "cyber"):
		acts.add_child(_btn(es, "Chair et acier (%d)" % Genetics.cyber_cost(state, player, fid), Genetics.check_cyber(state, player, fid),
				String(Genetics.cfg("cyber").get("text", "")), SimCommands.gen_act(player, "cyber", {"fid": fid}), "cyber:" + fid))
	if e.gene_path == "synthetique" and Genetics.is_organic(f):
		acts.add_child(_btn(es, "Grand Transfert (%d)" % Genetics.transfer_cost(state, player, fid), Genetics.check_transfer(state, player, fid),
				"L'espèce devient synthétique, pour de bon.", SimCommands.gen_act(player, "transfer", {"fid": fid}), "transfer:" + fid))
	if Genetics.full(state) and state.peoples_on:
		# Lignées : les traits forts seulement (2 points, ou croissance), pour garder l'écran lisible.
		var lin := HFlowContainer.new()
		lin.add_theme_constant_override("h_separation", 6)
		var lin_label := UiTheme.dim("Fonder une lignée :", 13)
		lin.add_child(lin_label)
		for t: Dictionary in Genetics.catalogue():
			var tid := String(t["id"])
			if cur.has(tid) or not voies.has(String(t["voie"])) or (int(t.get("cost", 0)) < 2 and not bool(t.get("growth", false))):
				continue
			if GeneticsBridges.check_lineage(state, player, fid, [tid], []) == "":
				lin.add_child(_btn(es, String(t["label"]), "",
						"Une lignée façonnée : la moitié des habitants d'un monde la rejoint ; elle compte comme la même espèce.",
						SimCommands.gen_act(player, "lineage", {"fid": fid, "add": [tid]}), "lineage:%s:%s" % [fid, tid]))
		if lin.get_child_count() > 1:
			b.body.add_child(lin)
		else:
			lin.free()
		if fid != e.faction_id:
			acts.add_child(_btn(es, "Abrutir", GeneticsBridges.check_staple(state, player, fid),
					"Assujettis seulement : +10 % de production, plus de volonté.", SimCommands.gen_act(player, "staple", {"fid": fid}), "staple:" + fid))
			acts.add_child(_btn(es, "Greffer (%d habitants)" % GeneticsBridges.graft_price(state, player), GeneticsBridges.check_graft(state, player, fid),
					"Prendre leur point fort pour votre peuple : %s." % GameData.format_amounts(GeneticsBridges.graft_gain(state, player, fid), true),
					SimCommands.gen_act(player, "graft", {"fid": fid}), "graft:" + fid))


static func _btn(es: EmpireScreens, text: String, why: String, tip: String, command: Dictionary, key: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.disabled = why != ""
	b.tooltip_text = tip + ("\n\nImpossible : %s." % why if why != "" else "")
	b.pressed.connect(func() -> void: es.command_requested.emit(command))
	es.genome_buttons[key] = b
	return b


static func signature(es: EmpireScreens) -> String:
	var state := es._state
	if not Genetics.applies(state, es._player):
		return "off"
	var e := state.get_empire(es._player)
	return "%d|%d|%s|%s|%d|%d|%d" % [e.genome_rev, e.techs.size(), e.gene_path, str(Genetics.programs(state, es._player)),
			int(e.resources.get("knowledge", 0)) / 100, Genetics.programs_done(state, es._player), state.custom_factions.size()]
