class_name PsionicsScreen
extends RefCounted
## Écran Songe (voir Psionics, prop. 40) : Résonance (réserve, gain, plafond), voie L'Éveil, niveau de
## chaque espèce, sensitifs (héros et Collèges), pouvoirs de la forme de l'empire avec leur coût, leur
## recharge et leur risque de fêlure, effets en cours. Le lot 2 y ajoute la plongée et le pacte.
## Construit dans les conteneurs d'EmpireScreens, dont il reprend les aides (_grid, _key_value…).

const COLOR := Color(0.72, 0.6, 0.95)


static func build(es: EmpireScreens) -> void:
	var state := es._state
	var player := es._player
	es._psionics_sig = signature(es)
	es._side_header("screen_psionics", "Songe", COLOR, "faction")
	if not Psionics.applies(state, player):
		es._side_box.add_child(UiTheme.paragraph("Dans cette partie, les pouvoirs psioniques ne sont pas en jeu (Nouvelle partie : Pouvoirs psioniques).", EmpireScreens.SIDE_WIDTH - 24.0, 13))
		return
	var e := state.get_empire(player)
	var g := es._grid()
	es._side_box.add_child(g)
	es._key_value(g, "Réglage", Psionics.mode_label(state))
	es._key_value(g, "Forme", Psionics.form_label(state, player))
	es._key_value(g, "Résonance", "%d / %d (+%d par mois)" % [Psionics.resonance(state, player), Psionics.cap(state, player), Psionics.monthly_gain(state, player)])
	es._key_value(g, "Votre peuple", Psionics.level_label(Psionics.founder_level(state, player)))
	es._key_value(g, "Collèges des sensitifs", str(Psionics.colleges(state, player)))
	es._key_value(g, "Écrans psychiques", "%d %% d'échec contre vous" % Psionics.screen_pct(state, player))
	var tl := Psionics.talent_labels(state, player)
	if not tl.is_empty():
		es._side_box.add_child(HSeparator.new())
		es._side_box.add_child(UiTheme.dim("Talents de votre peuple", 13))
		for t in tl:
			es._side_box.add_child(UiTheme.paragraph("%s : %s" % [t[0], t[1]], EmpireScreens.SIDE_WIDTH - 24.0, 12))
	es._side_box.add_child(HSeparator.new())
	es._side_box.add_child(UiTheme.dim("Voie d'élévation", 13))
	var pd := Psionics.path_def()
	if Psionics.awake(state, player):
		es._side_box.add_child(UiTheme.paragraph("%s : %s%s" % [String(pd.get("label", "")), "Transcendance atteinte. " if Psionics.crowned(state, player) else "",
				String(pd.get("text", ""))], EmpireScreens.SIDE_WIDTH - 24.0, 12))
	else:
		es._side_box.add_child(_btn(es, String(pd.get("label", "L'Éveil")), Psionics.check(state, player, "path", {}), String(pd.get("text", "")),
				SimCommands.psi_act(player, "path"), "path"))
	es._side_box.add_child(HSeparator.new())
	es._side_box.add_child(UiTheme.paragraph("Les espèces qui entendent %s donnent de la Résonance chaque mois, plus encore si elles sont éveillées ; les Collèges la multiplient. Chaque pouvoir la dépense et risque une fêlure : la loi sur les sensitifs, L'Éveil, les Collèges et un héros sensitif de la bonne classe la rendent plus rare." % Psionics.form_label(state, player).to_lower(), EmpireScreens.SIDE_WIDTH - 24.0, 12))

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	es._content.add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 18)
	scroll.add_child(col)

	# Pouvoirs.
	var pb := Widgets.Block.new("Pouvoirs : %s" % Psionics.form_label(state, player))
	col.add_child(pb)
	for p: Dictionary in Psionics.powers_of(state, player):
		var pid := String(p["id"])
		var fc: Array = Psionics.felure_chance(state, player, pid)
		var parts := PackedStringArray()
		for x in fc[1]:
			parts.append("%s %+d %%" % [x[0], int(x[1])])
		var tip := "%s\n%s\nCoût : %d Résonance ; recharge : %d jours ; fêlure : %d %%%s" % [String(p["label"]), String(p["text"]), Psionics.power_cost(state, player, pid),
				int(p.get("cooldown", 0)), int(fc[0]), (" (%s)" % ", ".join(parts)) if not parts.is_empty() else ""]
		var h := Psionics.power_hero(state, player, pid)
		if not h.is_empty():
			tip += "\nSensitif : %s (puissance %d)" % [h["name"], Psionics.hero_power(state, h)]
		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", 8)
		pb.body.add_child(row)
		var lab := Label.new()
		lab.text = "%s (%d, fêlure %d %%)" % [String(p["label"]), Psionics.power_cost(state, player, pid), int(fc[0])]
		lab.custom_minimum_size = Vector2(300, 0)
		row.add_child(lab)
		for t in _targets(state, player, p):
			var why := Psionics.check_power(state, player, pid, int(t[0]))
			row.add_child(_btn(es, String(t[1]), why, tip, SimCommands.psi_act(player, "power", {"power": pid, "target": int(t[0])}), "power:%s:%d" % [pid, int(t[0])]))

	# Espèces.
	var sb := Widgets.Block.new("Vos espèces et le Songe")
	col.add_child(sb)
	for fid in Genetics.species_of(state, player):
		var lv := Psionics.level(state, player, fid)
		sb.body.add_child(UiTheme.paragraph("%s : %s (%d habitants)" % [Genetics.label(state, player, fid), Psionics.level_label(lv), Genetics.pop_of(state, player, fid)], 760.0, 13))

	# Sensitifs.
	var hb := Widgets.Block.new("Sensitifs")
	col.add_child(hb)
	var any := false
	for id in Heroes.ids_of(state, player):
		var h: Dictionary = state.heroes[id]
		var p := Psionics.hero_power(state, h)
		if p > 0:
			any = true
			hb.body.add_child(UiTheme.paragraph("%s (%s, niveau %d) : puissance %d" % [h["name"], String(Heroes.class_def(String(h["cls"])).get("label", h["cls"])), int(h["lvl"]), p], 760.0, 13))
	if not any:
		hb.body.add_child(UiTheme.dim("Aucun héros sensitif pour l'instant.", 13))

	# Effets en cours.
	var fb := Widgets.Block.new("En cours")
	col.add_child(fb)
	var shown := false
	for fx: Dictionary in Psionics.fx_list(state, player):
		if int(fx["until"]) <= state.tick:
			continue
		shown = true
		fb.body.add_child(UiTheme.paragraph("%s, jusqu'au %s" % [fx_label(state, fx), GameCalendar.date_string(int(fx["until"]))], 760.0, 13))
	if not shown:
		fb.body.add_child(UiTheme.dim("Rien : le Songe est calme.", 13))
	PsionicsDreamUi.build(es, col)


static func fx_label(state: GameState, fx: Dictionary) -> String:
	match String(fx["id"]):
		"lecture":
			return "Lecture des esprits : %s" % state.get_empire(int(fx["target"])).display_name()
		"prescience":
			return "Préscience"
		"apaisement":
			return "Apaisement : %s" % state.galaxy.systems[int(fx["sys"])].system_name
		"f_empire", "f_system":
			return "Fêlure : %s" % String(fx.get("label", ""))
	return PsionicsDreamUi.fx_label(state, fx)


## Cibles proposées pour un pouvoir : [[cible, libellé]].
static func _targets(state: GameState, player: int, p: Dictionary) -> Array:
	var out := []
	var e := state.get_empire(player)
	match String(p.get("target", "self")):
		"empire":
			for c in e.contacts:
				var b := state.get_empire(c)
				if b != null and not b.eliminated and not b.is_npc():
					out.append([c, b.short_name()])
		"system":
			var seen := {}
			for pid in state.sorted_colony_ids():
				var c: Colony = state.colonies[pid]
				if c.owner == player and c.is_colony():
					var sid := state.galaxy.get_planet(pid).system_id
					if not seen.has(sid):
						seen[sid] = true
						out.append([sid, "%s (%d)" % [state.galaxy.systems[sid].system_name, Stability.value(state, sid)]])
		_:
			out.append([-1, "Invoquer"])
	return PsionicsDreamUi.targets(state, player, p, out)


static func _btn(es: EmpireScreens, text: String, why: String, tip: String, command: Dictionary, key: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.disabled = why != ""
	b.tooltip_text = tip + ("\n\nImpossible : %s." % why if why != "" else "")
	b.pressed.connect(func() -> void: es.command_requested.emit(command))
	es.psionics_buttons[key] = b
	return b


static func signature(es: EmpireScreens) -> String:
	var state := es._state
	if not Psionics.applies(state, es._player):
		return "off"
	var e := state.get_empire(es._player)
	@warning_ignore("integer_division")
	return "%d|%d|%s|%d|%s|%s|%d|%d" % [e.techs.size(), Psionics.resonance(state, es._player) / 5, str(Psionics.awake(state, es._player)),
			Psionics.colleges(state, es._player), str(Psionics.fx_list(state, es._player).size()), str(state.psionics.get("cd", {}).size()),
			state.tick / 30, e.contacts.size()] + "|%s|%s|%s|%s" % [str(PsionicsDream.pact(state, es._player)), str(PsionicsDream.offer(state, es._player)),
			str(PsionicsDream.opened(state, es._player)), str(PsionicsDream.check_reform(state, es._player) == "")] + "|%d|%s|%d" % [PsionicsBridges.lineage_until(state, es._player),
			str(PsionicsBridges.phare_lit(state, es._player)), PsionicsBridges.ambre_of(state, es._player)]
