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

	# Une espèce à la fois, choisie dans une rangée de portraits (refonte, C9).
	var species := Genetics.species_of(state, player)
	if not species.has(es.genome_species):
		es.genome_species = e.faction_id if species.has(e.faction_id) else (String(species[0]) if not species.is_empty() else "")
	if species.size() > 1:
		var pick := HFlowContainer.new()
		pick.add_theme_constant_override("h_separation", 10)
		pick.add_theme_constant_override("v_separation", 10)
		col.add_child(pick)
		for fid in species:
			var sf := String(fid)
			var pb2 := Button.new()
			pb2.toggle_mode = true
			pb2.focus_mode = Control.FOCUS_NONE
			pb2.custom_minimum_size = Vector2(150, 96)
			pb2.set_pressed_no_signal(sf == es.genome_species)
			pb2.tooltip_text = "%s : %d habitants" % [Genetics.label(state, player, sf), Genetics.pop_of(state, player, sf)]
			var tint := Color.html(String(GameData.faction(sf).get("color", "#66ccdd")))
			var art := Widgets.ArtSlot.new(GameData.portrait_art(sf), Vector2(146, 92), tint, "faction")
			art.position = Vector2(2, 2)
			art.mouse_filter = Control.MOUSE_FILTER_IGNORE
			art.set_caption(Genetics.label(state, player, sf), 14)
			art.modulate = Color.WHITE if sf == es.genome_species else Color(1, 1, 1, 0.55)
			pb2.add_child(art)
			pb2.pressed.connect(func() -> void:
				es.genome_species = sf
				es.show_screen("genome"))
			pick.add_child(pb2)
			es.genome_buttons["species:" + sf] = pb2
	if es.genome_species != "":
		_species_block(es, col, es.genome_species)
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
	# Traits en cartes à cocher : on coche ce qu'on ajoute et ce qu'on retire, puis on lance un seul programme.
	var picks: Dictionary = es.genome_picks.get(fid, {"add": [], "rem": []})
	var adds: Array = (picks["add"] as Array).filter(func(t: String) -> bool: return not cur.has(t))
	var rems: Array = (picks["rem"] as Array).filter(func(t: String) -> bool: return cur.has(t))
	es.genome_picks[fid] = {"add": adds, "rem": rems}
	var res_name := "matériaux" if Genetics.resource_for(state, player, fid) == "materials" else "Savoir"
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 8)
	b.body.add_child(flow)
	var hidden := 0
	for t: Dictionary in Genetics.catalogue():
		var tid := String(t["id"])
		if cur.has(tid):
			continue
		var v := String(t["voie"])
		if not voies.has(v) and not extra.has(tid):
			continue
		var why := Genetics.check_mod(state, player, fid, [tid], [], "")
		if why != "" and not adds.has(tid) and not es.genome_show_all:
			hidden += 1
			continue
		flow.add_child(_trait_card(es, fid, tid, "add", adds.has(tid), why,
				"%s · %d point%s" % [Genetics.voie_label(v), int(t.get("cost", 0)), "s" if int(t.get("cost", 0)) > 1 else ""], String(t.get("text", ""))))
	for tid in cur:
		if Genetics.trait_def(String(tid)).is_empty():
			continue
		flow.add_child(_trait_card(es, fid, String(tid), "rem", rems.has(String(tid)), Genetics.check_mod(state, player, fid, [], [String(tid)], ""),
				"Trait actuel · %d point%s rendu%s" % [Genetics.trait_cost(String(tid)), "s" if Genetics.trait_cost(String(tid)) > 1 else "", "s" if Genetics.trait_cost(String(tid)) > 1 else ""],
				String(Genetics.trait_def(String(tid)).get("text", ""))))
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 12)
	b.body.add_child(bar)
	if hidden > 0 or es.genome_show_all:
		var all_b := Button.new()
		all_b.focus_mode = Control.FOCUS_NONE
		all_b.text = "MASQUER LES IMPOSSIBLES" if es.genome_show_all else "VOIR TOUT (%d masqué%s)" % [hidden, "s" if hidden > 1 else ""]
		all_b.tooltip_text = "Les traits que cette espèce ne peut pas recevoir pour l'instant, avec la raison."
		all_b.pressed.connect(func() -> void:
			es.genome_show_all = not es.genome_show_all
			es.show_screen("genome"))
		bar.add_child(all_b)
		es.genome_buttons["show_all"] = all_b
	if not adds.is_empty() or not rems.is_empty():
		var parts := PackedStringArray()
		for t in adds:
			parts.append("+" + Genetics.trait_label(String(t)))
		for t in rems:
			parts.append("-" + Genetics.trait_label(String(t)))
		var why_all := Genetics.check_mod(state, player, fid, adds, rems, "")
		var sum := UiTheme.paragraph("Programme : %s. Coût : %d %s." % [", ".join(parts), Genetics.mod_cost(state, player, fid, adds, rems, ""), res_name], 420.0, 13)
		bar.add_child(sum)
		var go := _btn(es, "LANCER LE PROGRAMME", why_all, "Un seul programme pour tout ce qui est coché.",
				SimCommands.gen_act(player, "mod", {"fid": fid, "add": adds.duplicate(), "rem": rems.duplicate()}), "launch:" + fid)
		go.pressed.connect(func() -> void: es.genome_picks.erase(fid))
		bar.add_child(go)
	else:
		bar.add_child(UiTheme.dim("Cochez les traits à ajouter ou à retirer, puis lancez le programme.", 13))
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


## Carte à cocher d'un trait (kind : "add" pour l'ajouter, "rem" pour le retirer).
static func _trait_card(es: EmpireScreens, fid: String, tid: String, kind: String, on: bool, why: String, meta: String, text: String) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.set_pressed_no_signal(on)
	b.disabled = why != "" and not on
	b.custom_minimum_size = Vector2(236, 92)
	b.tooltip_text = text + ("\n\nImpossible : %s." % why if why != "" else "")
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 10
	col.offset_right = -10
	col.offset_top = 6
	col.offset_bottom = -6
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(col)
	var head := Label.new()
	head.text = "%s %s" % ["☑" if on else "☐", ("Retirer : " if kind == "rem" else "") + Genetics.trait_label(tid)]
	head.add_theme_font_size_override("font_size", 15)
	head.add_theme_color_override("font_color", UiTheme.ACCENT if on else (UiTheme.TEXT_DIM if why != "" else UiTheme.TEXT))
	head.clip_text = true
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(head)
	var ml := UiTheme.dim(meta, 11)
	ml.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(ml)
	var tl := UiTheme.paragraph(why if why != "" and not on else text, 216.0, 11)
	tl.add_theme_color_override("font_color", UiTheme.WARN if why != "" and not on else UiTheme.TEXT_DIM)
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tl.clip_text = true
	tl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(tl)
	b.pressed.connect(func() -> void:
		var picks: Dictionary = es.genome_picks.get(fid, {"add": [], "rem": []})
		var list: Array = picks[kind]
		if list.has(tid):
			list.erase(tid)
		else:
			list.append(tid)
		es.genome_picks[fid] = picks
		es.show_screen("genome"))
	es.genome_buttons["%s:%s:%s" % [kind, fid, tid]] = b
	return b


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
