class_name KoinonUi
extends RefCounted
## Écran Diplomatie : le Koinon (voir Koinon). Dans la relation avec un empire : fonder une ligue avec
## un allié, demander à entrer dans la sienne, proposer au synode la guerre contre lui ou son exclusion.
## Un bloc « Votre Koinon » : forme, rang, cohésion, Stratège, lois, trésor, votes en cours, consigne,
## sortie. Chaque ordre passe par emit (SimCommands.koi_act) ; buttons reçoit les boutons (pour les tests).


static func _btn(text: String, why: String, tip: String, on_press: Callable, primary := false) -> Button:
	return VassalUi._btn(text, why, tip, on_press, primary)


static func _coh_color(c: int) -> Color:
	return UiTheme.GOOD if c >= 40 else (UiTheme.WARN if c >= 0 else UiTheme.BAD)


## Forme proposée par défaut pour fonder avec b (celle que choisirait une IA, sinon marchande).
static func default_form(state: GameState, a: int, b: int) -> String:
	return AiKoinon.pick_form(state, a, b)


## Bloc ajouté à la relation avec l'empire id.
static func relation(state: GameState, player: int, id: int, emit: Callable, buttons: Dictionary, draft: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var e := state.get_empire(id)
	if not state.koinon_on or e == null or e.eliminated:
		return box
	var mine := Koinon.league_of(state, player)
	var his := Koinon.league_of(state, id)
	if his >= 0:
		var l := Koinon.league(state, his)
		var role := "membre" if Koinon.is_member(state, id) else "associé"
		box.add_child(UiTheme.dim("Koinon : %s de %s (rang %s)" % [role, String(l["name"]), roman(Koinon.rank(state, his))], 13))
	if mine < 0 and his < 0 and Diplomacy.allied(state, player, id):
		box.add_child(UiTheme.section("Fonder un Koinon"))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		box.add_child(row)
		var key := "found_%d" % id
		if not draft.has(key):
			draft[key] = default_form(state, player, id)
		var ob := OptionButton.new()
		ob.focus_mode = Control.FOCUS_NONE
		var forms := Koinon.form_defs()
		for i in forms.size():
			ob.add_item(String(forms[i]["label"]), i)
			ob.set_item_tooltip(i, String(forms[i].get("text", "")))
			if String(forms[i]["id"]) == String(draft[key]):
				ob.selected = i
		ob.item_selected.connect(func(i: int) -> void:
			draft[key] = String(forms[i]["id"])
			emit.call({}))
		row.add_child(ob)
		buttons["found_form"] = ob
		var fid := String(draft[key])
		var why := Koinon.check_found(state, player, id, fid)
		var b := _btn("FONDER (%s chacun)" % GameData.format_amounts(Koinon.data()["found"]["cost"]), why,
				"%s\nUne ligue de 2 à 6 empires : synode, Stratège élu pour cinq ans, lois communes, trésor, défense mutuelle." % String(Koinon.form(fid).get("text", "")),
				func() -> void: emit.call(SimCommands.koi_act(player, "found", id, fid)), true)
		row.add_child(b)
		buttons["found"] = b
	elif mine < 0 and his >= 0:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		box.add_child(row)
		var bm := _btn("DEMANDER À ENTRER (%s)" % GameData.format_amounts(Koinon.data()["join_cost"]), Koinon.check_propose(state, player, "admit", id, "member"),
				"Le synode vote votre admission : membre de plein droit, avec voix, bonus de la forme et devoirs.",
				func() -> void: emit.call(SimCommands.koi_act(player, "join", id, "member")))
		row.add_child(bm)
		buttons["join_member"] = bm
		var ba := _btn("COMME ASSOCIÉ", Koinon.check_propose(state, player, "admit", id, "assoc"),
				"Associé : protégé par la ligue et soumis à ses lois (impôt réduit de moitié), mais sans voix ni bonus de la forme. Gratuit.",
				func() -> void: emit.call(SimCommands.koi_act(player, "join", id, "assoc")))
		row.add_child(ba)
		buttons["join_assoc"] = ba
	elif mine >= 0 and Koinon.is_member(state, player):
		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", 10)
		box.add_child(row)
		if his == mine:
			var bx := _btn("PROPOSER SON EXCLUSION", Koinon.check_propose(state, player, "exclude", id, ""),
					"Le synode tranche aux deux tiers des voix.",
					func() -> void: emit.call(SimCommands.koi_act(player, "propose", id, "exclude")))
			row.add_child(bx)
			buttons["exclude"] = bx
		else:
			var bw := _btn("PROPOSER LA GUERRE COMMUNE", Koinon.check_propose(state, player, "war", id, ""),
					"Le synode vote à la majorité ; ceux qui votent pour entrent en guerre ensemble.",
					func() -> void: emit.call(SimCommands.koi_act(player, "propose", id, "war")))
			row.add_child(bw)
			buttons["war"] = bw
	return box


## Bloc « Votre Koinon » ; null hors ligue.
static func league_block(state: GameState, player: int, emit: Callable, buttons: Dictionary, draft: Dictionary) -> Control:
	var lid := Koinon.league_of(state, player)
	if not state.koinon_on or lid < 0:
		return null
	var l := Koinon.league(state, lid)
	var blk := Widgets.Block.new(String(l["name"]))
	var member := Koinon.is_member(state, player)
	var strat := Koinon.strategos(state, lid)
	var form := Koinon.form(String(l["form"]))
	blk.body.add_child(UiTheme.paragraph(String(form.get("text", "")), 620.0, 13))
	var g := GridContainer.new()
	g.columns = 4
	g.add_theme_constant_override("h_separation", 18)
	g.add_theme_constant_override("v_separation", 4)
	blk.body.add_child(g)
	var rs: Array = Koinon.data()["ranks"]
	var r := Koinon.rank(state, lid)
	var next := "rang maximal" if r >= rs.size() else "rang suivant à %d" % int(rs[r])
	_kv(g, "Rang", "%s (%d xp, %s)" % [roman(r), int(l["xp"]), next])
	var parts := PackedStringArray()
	for p in Koinon.cohesion_parts(state, lid):
		parts.append("%+d  %s" % [int(p["value"]), p["label"]])
	var cv := _kv(g, "Cohésion", "%+d (%+d / mois)" % [Koinon.cohesion(state, lid), Koinon.cohesion_trend(state, lid)])
	cv.add_theme_color_override("font_color", _coh_color(Koinon.cohesion(state, lid)))
	cv.tooltip_text = "De -100 à 100. Positive, la ligue gagne de l'expérience ; négative, elle en perd.\n" + "\n".join(parts)
	cv.mouse_filter = Control.MOUSE_FILTER_STOP
	var sname := state.get_empire(strat).short_name() if state.get_empire(strat) != null else "?"
	if Koinon.hegemony(state, lid):
		_kv(g, "Stratège", "%s, à vie (Hégémonie)" % sname)
	else:
		@warning_ignore("integer_division")
		_kv(g, "Stratège", "%s, encore %d mois" % [sname, maxi(0, int(l["strat_until"]) - state.tick) / 30])
	_kv(g, "Trésor", "%d énergie" % int(l["treasury"]))
	var names := PackedStringArray()
	for m in Koinon.members_of(state, lid):
		names.append(state.get_empire(m).short_name())
	var assoc := PackedStringArray()
	for m in league_assoc(state, lid):
		assoc.append(state.get_empire(m).short_name())
	blk.body.add_child(UiTheme.dim("Membres : %s%s" % [", ".join(names), ("  ·  associés : " + ", ".join(assoc)) if not assoc.is_empty() else ""], 13))
	if not member:
		blk.body.add_child(UiTheme.dim("Associé : vous suivez les lois et payez l'impôt réduit, sans voter.", 13))
	# Lois.
	blk.body.add_child(UiTheme.section("Lois"))
	var lg := GridContainer.new()
	lg.columns = 4
	lg.add_theme_constant_override("h_separation", 12)
	lg.add_theme_constant_override("v_separation", 4)
	blk.body.add_child(lg)
	for law in Koinon.law_defs():
		var fam := String(law["id"])
		var stp := Koinon.law_step(state, lid, fam)
		var steps: Array = law["steps"]
		lg.add_child(UiTheme.dim(String(law["label"]), 13))
		var cur := UiTheme.dim(String(steps[stp]["label"]), 13)
		cur.tooltip_text = String(steps[stp].get("text", ""))
		cur.mouse_filter = Control.MOUSE_FILTER_STOP
		cur.custom_minimum_size = Vector2(170, 0)
		lg.add_child(cur)
		for d in [-1, 1]:
			var to: int = stp + int(d)
			var label := "−" if d < 0 else "+"
			var tip := String(steps[to]["label"]) + " : " + String(steps[to].get("text", "")) if to >= 0 and to < steps.size() else ""
			var why := Koinon.check_propose(state, player, "law", to, fam) if to >= 0 and to < steps.size() else "pas d'autre cran"
			var b := _btn(label, why, "Proposer au synode : " + tip, func() -> void: emit.call(SimCommands.koi_act(player, "propose", to, "law:" + fam)))
			b.custom_minimum_size = Vector2(34, 0)
			lg.add_child(b)
			buttons["law_%s_%s" % [fam, "up" if d > 0 else "down"]] = b
	# Votes en cours.
	var votes: Array = l.get("votes", [])
	if not votes.is_empty():
		blk.body.add_child(UiTheme.section("Synode"))
		for v in votes:
			blk.body.add_child(_vote_row(state, player, lid, v, emit, buttons))
	# Propositions : changer de forme.
	var acts := HFlowContainer.new()
	acts.add_theme_constant_override("h_separation", 10)
	acts.add_theme_constant_override("v_separation", 6)
	blk.body.add_child(acts)
	if member:
		var ob := OptionButton.new()
		ob.focus_mode = Control.FOCUS_NONE
		var forms := Koinon.form_defs()
		var key := "form_%d" % lid
		if not draft.has(key):
			draft[key] = String(l["form"])
		for i in forms.size():
			ob.add_item(String(forms[i]["label"]), i)
			ob.set_item_tooltip(i, String(forms[i].get("text", "")))
			if String(forms[i]["id"]) == String(draft[key]):
				ob.selected = i
		ob.item_selected.connect(func(i: int) -> void:
			draft[key] = String(forms[i]["id"])
			emit.call({}))
		acts.add_child(ob)
		buttons["form_pick"] = ob
		var nf := String(draft[key])
		var bf := _btn("PROPOSER CETTE FORME", Koinon.check_propose(state, player, "form", -1, nf),
				"Changer de forme remet l'expérience à zéro.", func() -> void: emit.call(SimCommands.koi_act(player, "propose", -1, "form:" + nf)))
		acts.add_child(bf)
		buttons["form"] = bf
	# Stratège : trésor et consigne.
	if strat == player:
		var n := mini(int(Koinon.data()["grant_max"]), int(l["treasury"]))
		for m in Koinon.all_of(state, lid):
			if m == player:
				continue
			var mm := m
			var bg := _btn("VERSER %d À %s" % [n, state.get_empire(m).short_name().to_upper()], Koinon.check_grant(state, player, m, n),
					"Le trésor commun secourt un membre (énergie : %d)." % int(state.get_empire(m).resources.get("energy", 0)),
					func() -> void: emit.call(SimCommands.koi_act(player, "grant", mm, "", n)))
			acts.add_child(bg)
			buttons["grant_%d" % m] = bg
		if state.amph_on and Amphictyony.in_session(state):
			var cur := Koinon.consigne(state, player)
			for c in [[1, "CONSIGNE : POUR"], [-1, "CONSIGNE : CONTRE"], [0, "PAS DE CONSIGNE"]]:
				var cval: int = c[0]
				var why := Koinon.check_consigne(state, player, cval)
				if why == "" and cur == cval:
					why = "consigne déjà donnée"
				var bc := _btn(String(c[1]), why, "À l'Amphictyonie, les membres qui suivent la consigne soudent la ligue (+2 de cohésion), ceux qui votent contre l'abîment (-2).",
						func() -> void: emit.call(SimCommands.koi_act(player, "consigne", cval)))
				acts.add_child(bc)
				buttons["consigne_%d" % cval] = bc
	elif Koinon.consigne(state, player) != 0:
		blk.body.add_child(UiTheme.dim("Consigne du Stratège à l'Amphictyonie : voter %s." % ("pour" if Koinon.consigne(state, player) > 0 else "contre"), 13))
	var tip := "Départ libre : trêve avec chaque membre et un mauvais souvenir."
	if Koinon.hegemony(state, lid) and member and strat != player:
		tip = "Hégémonie : il faut l'accord du Stratège ; s'il refuse, c'est la guerre de sécession."
	var bl := _btn("QUITTER LE KOINON", Koinon.check_leave(state, player), tip, func() -> void: emit.call(SimCommands.koi_act(player, "leave")))
	acts.add_child(bl)
	buttons["leave"] = bl
	return blk


static func roman(n: int) -> String:
	return ["0", "I", "II", "III", "IV", "V"][clampi(n, 0, 5)]


static func league_assoc(state: GameState, lid: int) -> Array[int]:
	var out: Array[int] = []
	for m in Koinon.league(state, lid).get("assoc", []):
		out.append(int(m))
	return out


static func _kv(g: GridContainer, k: String, v: String) -> Label:
	g.add_child(UiTheme.dim(k, 13))
	var l := Label.new()
	l.text = v
	l.add_theme_font_size_override("font_size", 14)
	g.add_child(l)
	return l


static func _vote_row(state: GameState, player: int, lid: int, v: Dictionary, emit: Callable, buttons: Dictionary) -> Control:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	var vid := int(v["id"])
	@warning_ignore("integer_division")
	var left := maxi(0, int(v["until"]) - state.tick)
	var lab := UiTheme.dim("%s (%d j) · pour %d, contre %d" % [Koinon.vote_text(state, lid, v), left, (v["yes"] as Array).size(), (v["no"] as Array).size()], 13)
	lab.custom_minimum_size = Vector2(320, 0)
	row.add_child(lab)
	if String(v["kind"]) == "elect":
		for c in Koinon.candidates(state, lid):
			var cid := c
			var be := _btn(state.get_empire(c).short_name().to_upper(), Koinon.check_vote(state, player, vid, str(c)), "Votre bulletin pour le Stratège.",
					func() -> void: emit.call(SimCommands.koi_act(player, "vote", vid, str(cid))))
			row.add_child(be)
			buttons["vote_%d_%d" % [vid, c]] = be
		return row
	var voted := ""
	if (v["yes"] as Array).has(player):
		voted = "vous avez voté pour"
	elif (v["no"] as Array).has(player):
		voted = "vous avez voté contre"
	for side in ["yes", "no"]:
		var s: String = side
		var why := Koinon.check_vote(state, player, vid, s)
		var by := _btn("POUR" if s == "yes" else "CONTRE", why, voted, func() -> void: emit.call(SimCommands.koi_act(player, "vote", vid, s)))
		row.add_child(by)
		buttons["vote_%d_%s" % [vid, s]] = by
	return row
