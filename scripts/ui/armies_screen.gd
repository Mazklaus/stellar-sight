class_name ArmiesScreen
extends RefCounted
## Écran Armées (combat au sol complet, voir Ground) : réserve de recrues, entretien, recrutements en
## cours, régiments (où ils sont, santé, moral, démobiliser), batailles au sol en cours (RETRAITE pour
## l'assaillant) et derniers rapports. Le recrutement se fait dans l'écran d'un système peuplé.
## Construit dans les conteneurs d'EmpireScreens, dont il reprend les aides (_grid, _key_value…).


static func build(es: EmpireScreens) -> void:
	var state := es._state
	var player := es._player
	es._armies_sig = signature(es)
	es._side_header("screen_armies", "Armées", Color(0.78, 0.52, 0.36), "faction")
	var full := Ground.full(state)
	if not full:
		es._side_box.add_child(UiTheme.paragraph("Dans cette partie, le combat au sol est simplifié : les troupes sont un nombre porté par les vaisseaux, et une invasion réussit dès qu'elles dépassent la garnison. Les régiments se choisissent dans la Nouvelle partie (Combat au sol : Complet).", EmpireScreens.SIDE_WIDTH - 24.0, 13))
		return
	var regs := Ground.regiments_of(state, player)
	var g := es._grid()
	es._side_box.add_child(g)
	var rl := es._key_value(g, "Réserve de recrues", "%d / %d" % [Ground.recruits(state, player), Ground.recruits_cap(state, player)])
	rl.tooltip_text = "+%d par mois, selon la population de vos colonies. Chaque régiment en coûte quelques-unes." % Ground.recruits_gain(state, player)
	rl.mouse_filter = Control.MOUSE_FILTER_STOP
	es._key_value(g, "Régiments", str(regs.size()))
	var fl := es._key_value(g, "Sans entretien", str(Ground.free_regiments(state, player)))
	fl.tooltip_text = "Les premiers régiments ne coûtent rien (2, plus 1 par 6 de population ; davantage pour les peuples guerriers). Les suivants coûtent leur entretien."
	fl.mouse_filter = Control.MOUSE_FILTER_STOP
	var up := GameData.format_amounts(Ground.upkeep(state, player))
	es._key_value(g, "Entretien", up if up != "" else "aucun")
	es._key_value(g, "En formation", str(Ground.queue_of(state, player).size()))
	es._side_box.add_child(HSeparator.new())
	es._side_box.add_child(UiTheme.dim("Tactiques par défaut", 13))
	for side in ["attack", "defense"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var l := UiTheme.dim("À l'assaut" if side == "attack" else "En défense", 13)
		l.custom_minimum_size = Vector2(90, 0)
		row.add_child(l)
		row.add_child(_tactic_pick(es, side, Ground.default_tactic(state, player, side),
				func(t: String) -> Dictionary: return SimCommands.ground_act(player, "default_tactic", -1, side, t)))
		es._side_box.add_child(row)
	es._side_box.add_child(HSeparator.new())
	es._side_box.add_child(UiTheme.paragraph("Un régiment se lève dans l'écran d'un système peuplé, prend l'espèce de la colonie et ses traits, puis attend au sol. Une flotte avec des places de troupes (transports, croiseurs, Soute à troupes) l'embarque ; ENVAHIR le débarque chez l'ennemi : quelques jours de débarquement, puis bataille au sol contre la milice et les régiments du défenseur. Infanterie, blindés et aérien se battent en triangle : les blindés écrasent l'infanterie, l'aérien détruit les blindés.", EmpireScreens.SIDE_WIDTH - 24.0, 12))

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	es._content.add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 18)
	scroll.add_child(col)

	var mine_battles: Array[Dictionary] = []
	for b in Ground.battles(state):
		if int(b["a"]) == player or int(b["d"]) == player:
			mine_battles.append(b)
	if not mine_battles.is_empty():
		var bb := Widgets.Block.new("Batailles au sol")
		col.add_child(bb)
		for b in mine_battles:
			bb.body.add_child(_battle_row(es, b))

	var besieged: Array[int] = []
	for k in state.sieges.keys():
		if WarPeace.holder(state, int(k)) == player:
			besieged.append(int(k))
	besieged.sort()
	if not besieged.is_empty():
		var sb := Widgets.Block.new("Vos systèmes assiégés")
		col.add_child(sb)
		for sid in besieged:
			sb.body.add_child(_siege_row(es, sid))
	var rb := Widgets.Block.new("Vos régiments")
	col.add_child(rb)
	if regs.is_empty():
		rb.body.add_child(UiTheme.dim("Aucun régiment. Levez-en un dans l'écran d'un de vos systèmes peuplés.", 14))
	for r in regs:
		rb.body.add_child(_regiment_row(es, r))

	var q := Ground.queue_of(state, player)
	if not q.is_empty():
		var qb := Widgets.Block.new("En formation")
		col.add_child(qb)
		for it: Dictionary in q:
			var left := int(it["d"]) - state.tick
			qb.body.add_child(UiTheme.paragraph("%s (%s) à %s : prêt dans %d jour%s." % [Ground.type_label(String(it["t"])), Peoples.label(String(it["sp"])),
					state.galaxy.systems[int(it["s"])].system_name, left, "s" if left > 1 else ""], 760.0, 14))

	var reps := Ground.reports_for(state, player)
	if not reps.is_empty():
		var pb := Widgets.Block.new("Derniers rapports")
		col.add_child(pb)
		for rep: Dictionary in reps:
			var rr := HBoxContainer.new()
			rr.add_theme_constant_override("separation", 10)
			var rpl := UiTheme.paragraph(report_line(state, rep, player), 640.0, 13)
			rpl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			rr.add_child(rpl)
			if GroundReplayPanel.has_log(rep):
				var vb := Button.new()
				vb.text = "REVOIR"
				vb.focus_mode = Control.FOCUS_NONE
				vb.tooltip_text = "Rejouer la bataille au sol, jour par jour."
				var rid := int(rep["id"])
				vb.pressed.connect(func() -> void: es.ground_replay_requested.emit(rid))
				rr.add_child(vb)
			pb.body.add_child(rr)
	var dev := []
	for k in (state.ground.get("dev", {}) as Dictionary).keys():
		if WarPeace.holder(state, int(k)) == player:
			dev.append([GroundSiege.dev(state, int(k)), int(k)])
	if not dev.is_empty():
		dev.sort()
		dev.reverse()
		var db := Widgets.Block.new("Systèmes dévastés")
		col.add_child(db)
		db.body.add_child(UiTheme.paragraph("La dévastation réduit la production (-1 % pour 2 points), la croissance et la stabilité ; elle baisse de quelques points chaque mois, hors siège et hors bataille.", 760.0, 13))
		for it: Array in dev:
			db.body.add_child(UiTheme.paragraph("%s : dévastation %d %%." % [state.galaxy.systems[int(it[1])].system_name, int(it[0])], 760.0, 14))


## Ce qui change l'écran : régiments du joueur, file, batailles, rapports, réserve.
static func signature(es: EmpireScreens) -> String:
	var state := es._state
	if not Ground.full(state):
		return "simple"
	var regs := Ground.regiments_of(state, es._player)
	var parts := PackedStringArray()
	for r in regs:
		@warning_ignore("integer_division")
		parts.append("%d:%d:%d:%d:%d" % [int(r["id"]), int(r["hp"]) / 5, int(r["mo"]) / 5, int(r["s"]), int(r["f"])])
	var bs := PackedStringArray()
	for b in Ground.battles(state):
		bs.append("%d:%d" % [int(b["id"]), maxi(0, state.tick - int(b["st"]))])
	for b in Ground.battles(state):
		bs.append("%s:%s" % [String(b.get("ta", "")), String(b.get("td", ""))])
	bs.append(str(state.ground.get("tac", {})))
	bs.append(str(state.sieges.keys()))
	bs.append(str(state.ground.get("sortie", {})))
	@warning_ignore("integer_division")
	bs.append(str(state.tick / 30) + str(state.ground.get("dev", {})))
	return "%s|%d|%d|%s|%d|%d" % [",".join(parts), Ground.queue_of(state, es._player).size(), Ground.recruits(state, es._player),
			",".join(bs), Ground.reports_for(state, es._player).size(), Ground.reports_for(state, es._player).front().get("id", 0) if not Ground.reports_for(state, es._player).is_empty() else 0]


static func _regiment_row(es: EmpireScreens, r: Dictionary) -> Control:
	var state := es._state
	var player := es._player
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var name_l := Label.new()
	name_l.text = Ground.label(state, r)
	name_l.custom_minimum_size = Vector2(240, 0)
	name_l.clip_text = true
	name_l.add_theme_font_size_override("font_size", 15)
	row.add_child(name_l)
	var where := ""
	if int(r["f"]) >= 0 and state.fleets.has(int(r["f"])):
		var f: Fleet = state.fleets[int(r["f"])]
		where = "à bord de %s" % f.fleet_name
	elif int(r["s"]) >= 0:
		where = "au sol, %s" % state.galaxy.systems[int(r["s"])].system_name
	var wl := UiTheme.dim(where, 14)
	wl.custom_minimum_size = Vector2(230, 0)
	wl.clip_text = true
	row.add_child(wl)
	@warning_ignore("integer_division")
	var hp := int(r["hp"]) * 100 / maxi(1, Ground.max_hp(r))
	@warning_ignore("integer_division")
	var mo := int(r["mo"]) * 100 / maxi(1, Ground.max_morale(r))
	var stats := UiTheme.dim("santé %d %%  ·  moral %d %%" % [hp, mo], 14)
	stats.custom_minimum_size = Vector2(190, 0)
	if hp < 50 or mo < 50:
		stats.add_theme_color_override("font_color", UiTheme.delta_color(-1))
	row.add_child(stats)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var rid := int(r["id"])
	var b := Button.new()
	b.text = "DÉMOBILISER"
	b.focus_mode = Control.FOCUS_NONE
	var why := Ground.check_demobilize(state, player, rid)
	b.disabled = why != ""
	b.tooltip_text = why if why != "" else "Rendre ces soldats à la vie civile : la moitié des recrues revient à la réserve."
	b.pressed.connect(func() -> void: es.command_requested.emit(SimCommands.ground_act(player, "demob", rid)))
	row.add_child(b)
	return row


static func _battle_row(es: EmpireScreens, b: Dictionary) -> Control:
	var state := es._state
	var player := es._player
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var l := UiTheme.paragraph(Ground.battle_text(state, b) + ".", 640.0, 14)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var sid := int(b["s"])
	var side := "attack" if int(b["a"]) == player else "defense"
	if state.tick < int(b["land"]):
		row.add_child(_tactic_pick(es, side, String(b.get("ta" if side == "attack" else "td", "")),
				func(t: String) -> Dictionary: return SimCommands.ground_act(player, "tactic", sid, t)))
	else:
		row.add_child(UiTheme.dim(Ground.tactic_label(side, String(b.get("ta" if side == "attack" else "td", ""))), 13))
	if int(b["a"]) == player:
		var rb := Button.new()
		rb.text = "RETRAITE"
		rb.focus_mode = Control.FOCUS_NONE
		var why := Ground.check_retreat(state, player, sid)
		rb.disabled = why != ""
		rb.tooltip_text = why if why != "" else "Rembarquer dans les flottes sur place. Chaque régiment risque de périr sur les plages, d'autant plus qu'il est blessé ; sans place à bord, il est perdu."
		rb.pressed.connect(func() -> void: es.command_requested.emit(SimCommands.ground_act(player, "retreat", sid)))
		row.add_child(rb)
	return row


## Choix d'une tactique (menu déroulant) ; make_cmd(tactique) donne l'ordre à envoyer.
static func _tactic_pick(es: EmpireScreens, side: String, current: String, make_cmd: Callable) -> OptionButton:
	var ob := OptionButton.new()
	ob.focus_mode = Control.FOCUS_NONE
	ob.clip_text = true
	ob.custom_minimum_size = Vector2(190, 0)
	var ids := Ground.tactic_ids(side)
	var tips := PackedStringArray()
	for i in ids.size():
		ob.add_item(Ground.tactic_label(side, String(ids[i])))
		tips.append("%s : %s" % [Ground.tactic_label(side, String(ids[i])), String(Ground.tactic_def(side, String(ids[i])).get("text", ""))])
		if String(ids[i]) == current:
			ob.select(i)
	ob.tooltip_text = "\n".join(tips)
	ob.item_selected.connect(func(i: int) -> void: es.command_requested.emit(make_cmd.call(String(ids[i]))))
	return ob


## Un système assiégé : fortifications, milice, reddition possible, bouton SORTIE.
static func _siege_row(es: EmpireScreens, sid: int) -> Control:
	var state := es._state
	var player := es._player
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var txt := "%s : fortifications %d / %d, milice %d / %d" % [state.galaxy.systems[sid].system_name, GroundSiege.fort(state, sid), GroundSiege.fort_max(state, sid),
			Combat.garrison(state, sid), Combat.garrison_max(state, sid)]
	if GroundSiege.shielded(state, sid):
		txt += ", la Citadelle protège la population"
	var left := GroundSiege.surrender_left(state, sid)
	if left > 0:
		txt += ", reddition dans %d j" % left
	var l := UiTheme.paragraph(txt + ".", 640.0, 14)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var b := Button.new()
	b.text = "SORTIE"
	b.focus_mode = Control.FOCUS_NONE
	var why := GroundSiege.check_sortie(state, player, sid)
	b.disabled = why != ""
	b.tooltip_text = why if why != "" else "Lancer vos régiments au sol contre les troupes à bord des assiégeants : une passe d'armes, puis la garnison se remet."
	b.pressed.connect(func() -> void: es.command_requested.emit(SimCommands.ground_act(player, "sortie", sid)))
	row.add_child(b)
	return row


## Une ligne de rapport : où, qui, comment ça a fini, combien de jours, quelles pertes.
static func report_line(state: GameState, rep: Dictionary, player: int) -> String:
	var sname := state.galaxy.systems[int(rep["s"])].system_name
	var att := state.get_empire(int(rep["a"]))
	var dfd := state.get_empire(int(rep["d"]))
	var won := int(rep["w"]) == player
	var how := String(rep["how"])
	var verdict := ""
	match how:
		"won":
			verdict = "le monde est pris"
		"held":
			verdict = "la défense a tenu"
		"retreat":
			verdict = "l'assaillant a sonné la retraite"
		"peace":
			verdict = "la paix a interrompu les combats"
	var lost: Array = rep.get("lost", [0, 0])
	return "%s %s : %s contre %s, %s (%d jours). Santé perdue : %d contre %d." % ["Victoire" if won else "Défaite" if how != "peace" else "Paix", sname,
			att.display_name() if att else "?", dfd.display_name() if dfd else "les habitants", verdict, maxi(1, int(rep["end"]) - int(rep["st"])),
			int(lost[0]), int(lost[1])]
