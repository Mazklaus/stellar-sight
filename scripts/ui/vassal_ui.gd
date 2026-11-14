class_name VassalUi
extends RefCounted
## Écran Diplomatie : paix à conditions, reddition, protection, sujets (clauses, loyauté, intégration,
## libération), indépendance, soutiens et allégeance secrète (voir Vassals). Construit par EmpireScreens ;
## chaque ordre passe par emit (SimCommands.vas_act). buttons reçoit les boutons (pour les tests).


static func _btn(text: String, why: String, tip: String, on_press: Callable, primary := false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.disabled = why != ""
	b.tooltip_text = (why + ("\n\n" + tip if tip != "" else "")) if why != "" else tip
	if primary:
		b.theme_type_variation = &"PrimaryButton"
	b.pressed.connect(on_press)
	return b


static func _flow() -> HFlowContainer:
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", 10)
	f.add_theme_constant_override("v_separation", 6)
	return f


static func _loy_color(loy: int) -> Color:
	return UiTheme.GOOD if loy >= 200 else (UiTheme.WARN if loy >= 0 else UiTheme.BAD)


## Résumé pour la colonne de gauche : suzerain et sujets du joueur.
static func side(state: GameState, player: int, width: float) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var lord := Vassals.lord_of(state, player)
	var subs := Vassals.subjects_of(state, player)
	if lord < 0 and subs.is_empty():
		return box
	box.add_child(HSeparator.new())
	if lord >= 0:
		var l := UiTheme.dim("Suzerain : %s (%s)" % [state.get_empire(lord).short_name(), Vassals.preset_label(Vassals.preset_of(state, player))], 14)
		box.add_child(l)
		var loy := UiTheme.dim("Votre loyauté : %+d" % Vassals.loyalty_points(state, player), 13)
		loy.add_theme_color_override("font_color", _loy_color(Vassals.loyalty(state, player)))
		box.add_child(loy)
	if not subs.is_empty():
		box.add_child(UiTheme.section("Vos sujets"))
		for s in subs:
			var t := UiTheme.dim("%s : %s, loyauté %+d" % [state.get_empire(s).short_name(), Vassals.preset_label(Vassals.preset_of(state, s)), Vassals.loyalty_points(state, s)], 13)
			t.add_theme_color_override("font_color", _loy_color(Vassals.loyalty(state, s)))
			t.custom_minimum_size = Vector2(width, 0)
			t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			box.add_child(t)
	return box


## Bloc ajouté à la relation avec l'empire id.
static func relation(state: GameState, player: int, id: int, emit: Callable, buttons: Dictionary, draft: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var e := state.get_empire(id)
	if e == null or e.eliminated:
		return box
	# Liens de l'autre empire.
	var his_lord := Vassals.lord_of(state, id)
	var his_subs := Vassals.subjects_of(state, id)
	if his_lord >= 0 and his_lord != player:
		box.add_child(UiTheme.dim("Sujet de %s (%s)" % [state.get_empire(his_lord).short_name(), Vassals.preset_label(Vassals.preset_of(state, id))], 13))
	if not his_subs.is_empty():
		var names := PackedStringArray()
		for s in his_subs:
			names.append(state.get_empire(s).short_name())
		box.add_child(UiTheme.dim("Ses sujets : %s" % ", ".join(names), 13))
	if Vassals.lord_of(state, id) == player:
		box.add_child(_subject_panel(state, player, id, emit, buttons, draft))
	elif Vassals.lord_of(state, player) == id:
		box.add_child(_lord_panel(state, player, id, emit, buttons))
	if not state.vassals_on and Vassals.lord_of(state, id) != player and Vassals.lord_of(state, player) != id:
		return box
	if Combat.at_war(state, player, id):
		box.add_child(_terms_panel(state, player, id, emit, buttons, draft))
	var acts := _flow()
	if state.vassals_on and not Combat.at_war(state, player, id) and Vassals.lord_of(state, player) != id and Vassals.lord_of(state, id) != player:
		var why := Vassals.check_protect(state, player, id)
		if why == "" or Vassals.power_pct(state, player, id) < int(Vassals.data()["protect"]["power_pct"]):
			var b := _btn("DEMANDER SA PROTECTION", why, "Vous deviendrez son protégé (Protectorat) : il vous défend, vous rattrapez votre retard (+50 % de Savoir), vous lui versez 1 influence par mois.",
					func() -> void: emit.call(SimCommands.vas_act(player, "protect", id)))
			acts.add_child(b)
			buttons["protect"] = b
	if his_lord >= 0 and his_lord != player:
		var why := Vassals.check_support(state, player, id)
		var b := _btn("SOUTENIR SON INDÉPENDANCE (%s)" % GameData.format_amounts(Vassals.data()["independence"]["support_cost"]), why,
				"Le jour où %s exigera sa liberté, son suzerain comptera votre puissance ; s'il refuse, vous entrerez en guerre à ses côtés. %s le saura." % [e.short_name(), state.get_empire(his_lord).short_name()],
				func() -> void: emit.call(SimCommands.vas_act(player, "support", id)))
		acts.add_child(b)
		buttons["support"] = b
	var my_lord := Vassals.lord_of(state, player)
	if my_lord >= 0 and my_lord != id and not Vassals.locked(state, player):
		var sworn := int(Vassals.link(state, player)["fealty"]) == id
		var b := _btn("RETIRER L'ALLÉGEANCE SECRÈTE" if sworn else "JURER UNE ALLÉGEANCE SECRÈTE",
				Vassals.check_fealty(state, player, -1 if sworn else id),
				"Personne n'en saura rien. Si %s entre en guerre contre votre suzerain, vous romprez votre lien et passerez à ses côtés." % e.short_name(),
				func() -> void: emit.call(SimCommands.vas_act(player, "fealty", -1 if sworn else id)))
		acts.add_child(b)
		buttons["fealty"] = b
	if acts.get_child_count() > 0:
		box.add_child(acts)
	return box


## Conditions de paix : cases à cocher, prix en direct contre le score, et reddition.
static func _terms_panel(state: GameState, player: int, id: int, emit: Callable, buttons: Dictionary, draft: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.add_child(UiTheme.section("Conditions de paix"))
	var score := Diplomacy.war_score(state, player, id)
	var t: Dictionary = Vassals.data()["terms"]
	var key := str(id)
	if not draft.has(key):
		draft[key] = {}
	var d: Dictionary = draft[key]
	var price_label := Label.new()
	var send_holder := {}
	var refresh := func() -> void:
		var terms := _draft_terms(d)
		var p := Vassals.price(state, id, terms)
		var e := state.get_empire(id)
		var verdict := ""
		if e.is_ai():
			verdict = "  : accepterait" if p <= score else "  : refuserait"
		price_label.text = "Prix %d / score %+d%s" % [p, score, verdict]
		price_label.add_theme_color_override("font_color", UiTheme.GOOD if p <= score else UiTheme.BAD)
		if send_holder.has("b"):
			var why := Vassals.check_offer_terms(state, player, id, terms)
			var sb: Button = send_holder["b"]
			sb.disabled = why != ""
			sb.tooltip_text = why if why != "" else "Une IA accepte si le prix ne dépasse pas votre score ; un joueur répondra lui-même."
	var flow := _flow()
	box.add_child(flow)
	var cands := Vassals.cedable(state, id)
	cands.sort_custom(func(x: int, y: int) -> bool:
		var px := Vassals.system_pop(state, x, id)
		var py := Vassals.system_pop(state, y, id)
		return px > py or (px == py and x < y))
	for i in mini(6, cands.size()):
		var sid := cands[i]
		var cb := CheckBox.new()
		cb.text = "Céder %s (%d)" % [state.galaxy.systems[sid].system_name, Vassals.cede_price(state, id, sid)]
		cb.focus_mode = Control.FOCUS_NONE
		cb.button_pressed = (d.get("cede", []) as Array).has(sid)
		cb.toggled.connect(func(on: bool) -> void:
			var arr: Array = d.get("cede", [])
			if on and not arr.has(sid):
				arr.append(sid)
			elif not on:
				arr.erase(sid)
			d["cede"] = arr
			refresh.call())
		flow.add_child(cb)
		buttons["cede_%d" % sid] = cb
	var opts := [["trib", "Tribut %d %% pendant 5 ans (%d)" % [int(t["tribute_pct"]), int(t["tribute_price"])], true],
			["repar", "Réparations %d %% (%d)" % [int(t["repar_pct"]), int(t["repar_price"])], true],
			["break", "Rompre ses alliances (%d)" % int(t["break_price"]), not Diplomacy.allies(state, id).is_empty()],
			["free", "Libérer ses sujets", not Vassals.subjects_of(state, id).is_empty()]]
	for o in opts:
		if not bool(o[2]):
			continue
		var k := String(o[0])
		var cb := CheckBox.new()
		cb.text = String(o[1])
		cb.focus_mode = Control.FOCUS_NONE
		cb.button_pressed = bool(d.get(k, false))
		cb.toggled.connect(func(on: bool) -> void:
			d[k] = on
			refresh.call())
		flow.add_child(cb)
		buttons["term_" + k] = cb
	var vrow := HBoxContainer.new()
	vrow.add_theme_constant_override("separation", 8)
	box.add_child(vrow)
	vrow.add_child(UiTheme.dim("Devenir sujet (%d) :" % Vassals.vassal_price(state, id), 13))
	var ob := OptionButton.new()
	ob.focus_mode = Control.FOCUS_NONE
	ob.add_item("non", 0)
	var presets := Vassals.free_presets()
	for i in presets.size():
		ob.add_item(Vassals.preset_label(presets[i]), i + 1)
		ob.set_item_tooltip(i + 1, String(Vassals.preset(presets[i]).get("text", "")))
	ob.selected = presets.find(String(d.get("vassal", ""))) + 1
	ob.item_selected.connect(func(i: int) -> void:
		d["vassal"] = presets[i - 1] if i > 0 else ""
		refresh.call())
	vrow.add_child(ob)
	buttons["term_vassal"] = ob
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 10)
	box.add_child(srow)
	price_label.add_theme_font_size_override("font_size", 14)
	price_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	srow.add_child(price_label)
	var send := _btn("PROPOSER CES CONDITIONS", "-", "", func() -> void:
		emit.call(SimCommands.vas_act(player, "terms", id, "", _draft_terms(d)))
		draft.erase(key), true)
	send_holder["b"] = send
	srow.add_child(send)
	buttons["terms"] = send
	refresh.call()
	var sur := _btn("SE RENDRE", Vassals.check_surrender(state, player, id),
			"Vous devenez son vassal (préréglage Vassal) : la guerre cesse, votre empire survit. Possible à %d points de score contre vous, ou capitale perdue." % int(Vassals.data()["surrender"]["score"]),
			func() -> void: emit.call(SimCommands.vas_act(player, "surrender", id)))
	box.add_child(sur)
	buttons["surrender"] = sur
	return box


static func _draft_terms(d: Dictionary) -> Dictionary:
	var out := {}
	if not (d.get("cede", []) as Array).is_empty():
		out["cede"] = (d["cede"] as Array).duplicate()
	for k in ["trib", "repar", "break", "free"]:
		if bool(d.get(k, false)):
			out[k] = true
	if String(d.get("vassal", "")) != "":
		out["vassal"] = String(d["vassal"])
	return out


## Votre sujet : loyauté et causes, clauses modifiables, intégration, libération.
static func _subject_panel(state: GameState, player: int, id: int, emit: Callable, buttons: Dictionary, draft: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.add_child(UiTheme.section("Votre sujet : %s" % Vassals.preset_label(Vassals.preset_of(state, id))))
	var loy := Vassals.loyalty(state, id)
	var trend := Vassals.loyalty_trend(state, id)
	var lines := PackedStringArray()
	for p in Vassals.loyalty_parts(state, id):
		lines.append("%+.1f  %s" % [int(p["value"]) / 10.0, p["label"]])
	var ll := UiTheme.dim("Loyauté %+d / 100, tendance %+.1f par mois%s" % [Vassals.loyalty_points(state, id), trend / 10.0, "  (DÉLOYAL)" if Vassals.disloyal(state, id) else ""], 14)
	ll.add_theme_color_override("font_color", _loy_color(loy))
	ll.tooltip_text = "\n".join(lines) if not lines.is_empty() else "Rien ne bouge."
	ll.mouse_filter = Control.MOUSE_FILTER_STOP
	box.add_child(ll)
	var est := Vassals.tribute_estimate(state, id)
	box.add_child(UiTheme.dim("Lié depuis %d jours. Tribut ce mois : %s" % [Vassals.bond_days(state, id), GameData.format_amounts(est) if not est.is_empty() else "rien"], 13))
	if int(Vassals.link(state, id)["integ"]) >= 0:
		box.add_child(UiTheme.dim("Intégration en cours : %d / %d mois" % [int(Vassals.link(state, id)["imo"]), int(Vassals.data()["integration"]["months"])], 13))
	if Vassals.locked(state, id):
		box.add_child(UiTheme.paragraph(String(Vassals.preset("cour").get("text", "")), 520, 13))
		return box
	# Éditeur de clauses.
	var key := "cl_%d" % id
	if not draft.has(key):
		draft[key] = (Vassals.link(state, id)["cl"] as Dictionary).duplicate(true)
	var cl: Dictionary = draft[key]
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 12)
	g.add_theme_constant_override("v_separation", 4)
	box.add_child(g)
	var apply_holder := {}
	var refresh := func() -> void:
		var b: Button = apply_holder["b"]
		var why := Vassals.check_set_terms(state, player, id, cl)
		b.disabled = why != ""
		var cost := Vassals.renegotiate_cost(state, id, cl)
		var dnow := Vassals.clauses_now(Vassals.normalize(cl)) - Vassals.clauses_now(Vassals.link(state, id)["cl"])
		b.text = "APPLIQUER (%s, loyauté %+.0f)" % ["gratuit" if cost == 0 else "%d influence" % cost, dnow / 10.0]
		b.tooltip_text = why if why != "" else "Assouplir est gratuit à tout moment ; durcir coûte de l'influence, une fois tous les 5 ans."
	for c in Vassals.clause_defs():
		var cid := String(c["id"])
		g.add_child(UiTheme.dim(String(c["label"]), 13))
		var ob := OptionButton.new()
		ob.focus_mode = Control.FOCUS_NONE
		var opts: Array = c["opts"]
		for i in opts.size():
			ob.add_item("%s (%+.0f, %+.1f/mois)" % [String(opts[i]["label"]), int(opts[i]["now"]) / 10.0, int(opts[i]["m10"]) / 10.0], i)
			ob.set_item_tooltip(i, String(opts[i]["text"]))
			if String(opts[i]["id"]) == String(cl.get(cid, "")):
				ob.selected = i
		ob.item_selected.connect(func(i: int) -> void:
			cl[cid] = String(opts[i]["id"])
			refresh.call())
		g.add_child(ob)
		buttons["clause_" + cid] = ob
	for f in Vassals.families():
		var fam := String(f)
		g.add_child(UiTheme.dim("Tribut : %s" % GameData.resource_label(fam).to_lower(), 13))
		var ob := OptionButton.new()
		ob.focus_mode = Control.FOCUS_NONE
		var st: Array = Vassals.steps()
		for i in st.size():
			ob.add_item("%d %%" % int(st[i]), i)
			if int(st[i]) == int(cl.get("trib", {}).get(fam, 0)):
				ob.selected = i
		ob.item_selected.connect(func(i: int) -> void:
			var tr: Dictionary = cl.get("trib", {})
			if int(st[i]) > 0:
				tr[fam] = int(st[i])
			else:
				tr.erase(fam)
			cl["trib"] = tr
			refresh.call())
		g.add_child(ob)
		buttons["trib_" + fam] = ob
	var acts := _flow()
	box.add_child(acts)
	var ab := _btn("APPLIQUER", "-", "", func() -> void:
		emit.call(SimCommands.vas_act(player, "set_terms", id, "", cl.duplicate(true)))
		draft.erase(key), true)
	apply_holder["b"] = ab
	acts.add_child(ab)
	buttons["set_terms"] = ab
	refresh.call()
	for pid in Vassals.free_presets():
		var pr := pid
		var b := _btn(Vassals.preset_label(pid).to_upper(), "", String(Vassals.preset(pid).get("text", "")), func() -> void:
			draft[key] = Vassals.preset_clauses(pr)
			emit.call({}))
		acts.add_child(b)
	var ib := _btn("INTÉGRER", Vassals.check_integrate(state, player, id),
			"Un an et %s par mois : ses colonies et ses flottes deviennent les vôtres, l'empire disparaît." % GameData.format_amounts(Vassals.data()["integration"]["cost"]),
			func() -> void: emit.call(SimCommands.vas_act(player, "integrate", id)))
	acts.add_child(ib)
	buttons["integrate"] = ib
	var rb := _btn("LIBÉRER", Vassals.check_release(state, player, id), "Il redevient indépendant ; dix ans de trêve entre vous. Il s'en souviendra avec gratitude.",
			func() -> void: emit.call(SimCommands.vas_act(player, "release", id)))
	acts.add_child(rb)
	buttons["release"] = rb
	return box


## Votre suzerain : votre loyauté, et l'indépendance.
static func _lord_panel(state: GameState, player: int, id: int, emit: Callable, buttons: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.add_child(UiTheme.section("Votre suzerain : %s" % Vassals.preset_label(Vassals.preset_of(state, player))))
	box.add_child(UiTheme.paragraph(Vassals.clauses_text(Vassals.link(state, player)["cl"]), 520, 13))
	var ll := UiTheme.dim("Votre loyauté : %+d / 100" % Vassals.loyalty_points(state, player), 14)
	ll.add_theme_color_override("font_color", _loy_color(Vassals.loyalty(state, player)))
	box.add_child(ll)
	var sup: Array = Vassals.link(state, player).get("sup", [])
	if not sup.is_empty():
		var names := PackedStringArray()
		for s in sup:
			names.append(state.get_empire(int(s)).short_name())
		box.add_child(UiTheme.dim("Soutiens à votre indépendance : %s" % ", ".join(names), 13))
	if not Vassals.locked(state, player):
		var b := _btn("EXIGER L'INDÉPENDANCE", Vassals.check_freedom(state, player),
				"S'il refuse, c'est la guerre de libération (vos soutiens entrent en guerre avec vous). Votre camp : %d, lui : %d." % [Vassals.freedom_power(state, player), Vassals.power(state, id)],
				func() -> void: emit.call(SimCommands.vas_act(player, "freedom")))
		box.add_child(b)
		buttons["freedom"] = b
	return box
