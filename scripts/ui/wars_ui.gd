class_name WarsUi
extends RefCounted
## Écran Diplomatie : buts de guerre (voir Wars). En paix : motifs disponibles, choix du motif et du but
## pour la déclaration, revendications à acheter. En guerre : nom, motif, buts des deux camps, score en %
## détaillé, but du défenseur à choisir, exiger la reddition (avec l'avis de l'adversaire), se rendre.
## Construit par EmpireScreens ; chaque ordre passe par emit (SimCommands.war_act). buttons reçoit les
## boutons (pour les tests), draft le choix du motif par empire.


static func _btn(text: String, why: String, tip: String, on_press: Callable, primary := false) -> Button:
	return VassalUi._btn(text, why, tip, on_press, primary)


static func _key(id: int) -> String:
	return "war_%d" % id


## Motif et but choisis pour déclarer la guerre à id : [motif, but] (["", ""] : au mieux).
static func choice(state: GameState, player: int, id: int, draft: Dictionary) -> Array:
	var ch := Wars.choices(state, player, id)
	if ch.is_empty():
		return ["", ""]
	var i := int(draft.get(_key(id), -1))
	if i < 0 or i >= ch.size():
		return Wars.auto_choice(state, player, id)
	return ch[i]


## Texte d'aide du bouton de déclaration.
static func declare_tip(state: GameState, player: int, id: int, draft: Dictionary) -> String:
	var c := choice(state, player, id, draft)
	var cid := String(c[0])
	var gid := String(c[1])
	var lines := PackedStringArray()
	lines.append("Motif : %s. %s" % [Wars.casus_label(cid), String(Wars.casus_def(cid).get("text", ""))])
	lines.append("But : %s. %s" % [Wars.goal_label(gid), String(Wars.goal_def(gid).get("text", ""))])
	if Diplomacy.in_truce(state, player, id):
		var t: Dictionary = Wars.data()["truce"]
		lines.append("Rompre la trêve : stabilité %d pendant un an, toute la galaxie s'en souviendra, la lassitude part de %d %%." % [int(t["break_stability"]), int(t["break_exhaustion"])])
	return "\n".join(lines)


static func _parts_tip(parts: Array) -> String:
	var out := PackedStringArray()
	for p in parts:
		out.append("%s : %+d %%" % [String(p[0]), int(p[1])])
	return "\n".join(out) if not out.is_empty() else "Rien encore."


## Bloc ajouté à la relation avec l'empire id.
static func relation(state: GameState, player: int, id: int, emit: Callable, buttons: Dictionary, draft: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var e := state.get_empire(id)
	if not state.wars_on or e == null or e.eliminated or e.is_npc() or player == id:
		return box
	if Combat.at_war(state, player, id) and not Wars.war(state, player, id).is_empty():
		_war_panel(state, player, id, emit, buttons, box)
	else:
		_peace_panel(state, player, id, emit, buttons, draft, box)
	return box


static func _peace_panel(state: GameState, player: int, id: int, emit: Callable, buttons: Dictionary, draft: Dictionary, box: VBoxContainer) -> void:
	box.add_child(UiTheme.section("Motifs de guerre"))
	if Diplomacy.no_treaties(state, player):
		box.add_child(UiTheme.dim("Guerre totale : votre peuple ne connaît pas d'autre motif.", 13))
		return
	var ch := Wars.choices(state, player, id)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	var ob := OptionButton.new()
	ob.focus_mode = Control.FOCUS_NONE
	var cur := choice(state, player, id, draft)
	for i in ch.size():
		var cid := String(ch[i][0])
		var gid := String(ch[i][1])
		ob.add_item("%s : %s" % [Wars.casus_label(cid), Wars.goal_label(gid)], i)
		ob.set_item_tooltip(i, "%s\n%s" % [String(Wars.casus_def(cid).get("text", "")), String(Wars.goal_def(gid).get("text", ""))])
		if cid == String(cur[0]) and gid == String(cur[1]):
			ob.selected = i
	ob.item_selected.connect(func(i: int) -> void:
		draft[_key(id)] = i
		emit.call({}))
	row.add_child(ob)
	buttons["casus"] = ob
	var cl := Wars.claims_on(state, player, id)
	if not cl.is_empty():
		var names := PackedStringArray()
		for sid in cl:
			names.append(state.galaxy.systems[sid].system_name)
		box.add_child(UiTheme.dim("Vos revendications : %s" % ", ".join(names), 13))
	_claim_buttons(state, player, id, emit, buttons, box)


static func _claim_buttons(state: GameState, player: int, id: int, emit: Callable, buttons: Dictionary, box: VBoxContainer) -> void:
	var cand := Wars.claim_candidates(state, player, id, 3)
	if cand.is_empty():
		return
	var flow := VassalUi._flow()
	for c in cand:
		var sid := int(c[0])
		var cost := int(c[1])
		var why := Wars.check_claim(state, player, sid)
		var b := _btn("REVENDIQUER %s (%s)" % [state.galaxy.systems[sid].system_name.to_upper(), ("%d influence" % cost) if cost > 0 else "gratuit"], why,
				"Ouvre le motif Revendication : une conquête la lui prendra, sa reddition vous la cédera. Il le saura.",
				func() -> void: emit.call(SimCommands.war_act(player, "claim", sid)))
		flow.add_child(b)
		buttons["claim_%d" % sid] = b
	box.add_child(flow)


static func _war_panel(state: GameState, player: int, id: int, emit: Callable, buttons: Dictionary, box: VBoxContainer) -> void:
	var rec := Wars.war(state, player, id)
	var me_att := int(rec["a"]) == player
	box.add_child(UiTheme.section(String(rec["name"])))
	box.add_child(UiTheme.dim("Motif : %s (%s)" % [Wars.casus_label(String(rec["cb"])) if String(rec["cb"]) != "allie" else "aux côtés d'un allié",
			"vous attaquez" if me_att else "il vous attaque"], 13))
	var mine := Wars.goal_of(rec, player)
	var his := Wars.goal_of(rec, id)
	var gl := UiTheme.dim("Votre but : %s%s   •   Le sien : %s" % [Wars.goal_label(mine) if mine != "" else "à choisir",
			"  (tenu)" if mine != "" and Wars.objective_held(state, rec, player) else "", Wars.goal_label(his) if his != "" else "à choisir"], 13)
	gl.tooltip_text = "%s\n\n%s" % [String(Wars.goal_def(mine).get("text", "")), String(Wars.goal_def(his).get("text", ""))]
	gl.mouse_filter = Control.MOUSE_FILTER_STOP
	box.add_child(gl)
	var sp := Wars.score_parts(state, player, id)
	var sc := UiTheme.dim("Score de guerre : %+d %%" % int(sp["total"]), 15)
	sc.add_theme_color_override("font_color", UiTheme.delta_color(int(sp["total"])))
	sc.tooltip_text = _parts_tip(sp["parts"])
	sc.mouse_filter = Control.MOUSE_FILTER_STOP
	box.add_child(sc)
	buttons["score"] = sc
	var flow := VassalUi._flow()
	# Défenseur : choisir son but.
	if mine == "":
		for gid in Wars.defense_goals(state, rec):
			var g := String(gid)
			var b := _btn("BUT : %s" % Wars.goal_label(g).to_upper(), Wars.check_defense_goal(state, player, id, g), String(Wars.goal_def(g).get("text", "")),
					func() -> void: emit.call(SimCommands.war_act(player, "goal", id, g)))
			flow.add_child(b)
			buttons["goal_" + g] = b
		box.add_child(UiTheme.dim("Choisissez votre but avant %d jours, sinon il se fixera seul." % maxi(0, int(rec["gdl"]) - state.tick), 13))
	# Exiger la reddition : l'avis de l'adversaire.
	var ap := Wars.accept_parts(state, player, id)
	var verdict := "il accepterait" if int(ap["total"]) >= 0 else "il refuserait"
	var dw := Wars.check_demand(state, player, id)
	var bd := _btn("EXIGER SA REDDITION (%s)" % verdict, dw, "Il se rendrait à votre but et vous céderait vos revendications.\nMarge d'acceptation %+d :\n%s" % [int(ap["total"]), _parts_tip(ap["parts"])],
			func() -> void: emit.call(SimCommands.war_act(player, "demand", id)), int(ap["total"]) >= 0)
	flow.add_child(bd)
	buttons["demand"] = bd
	var yw := Wars.check_yield(state, player, id)
	var by := _btn("SE RENDRE À SON BUT", yw, "La guerre finit tout de suite. %s Il obtient aussi ses revendications sur vous." % String(Wars.goal_def(his).get("text", "")),
			func() -> void: emit.call(SimCommands.war_act(player, "yield", id)))
	flow.add_child(by)
	buttons["yield"] = by
	box.add_child(flow)
	_claim_buttons(state, player, id, emit, buttons, box)
