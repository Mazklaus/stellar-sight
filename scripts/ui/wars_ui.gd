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
	var pr := WarLaws.seen_prep(state, player, id)
	if not pr.is_empty():
		var wl := UiTheme.dim("Préavis : vos espions le voient masser ses flottes face à %s." % ("vous" if int(pr["b"]) == player else state.get_empire(int(pr["b"])).short_name()), 13)
		wl.add_theme_color_override("font_color", UiTheme.delta_color(-1))
		box.add_child(wl)
		buttons["prep"] = wl
	if Combat.at_war(state, player, id) and not Wars.war(state, player, id).is_empty():
		_war_panel(state, player, id, emit, buttons, box)
	else:
		_peace_panel(state, player, id, emit, buttons, draft, box)
	_third_party(state, player, id, emit, buttons, box)
	return box


static func _peace_panel(state: GameState, player: int, id: int, emit: Callable, buttons: Dictionary, draft: Dictionary, box: VBoxContainer) -> void:
	_treaties_between(state, player, id, box)
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
	_crisis_block(state, player, id, emit, buttons, draft, box)
	_ultimatum_buttons(state, player, id, emit, buttons, box)


## Traités du registre entre player et id (lot 2), avec leurs clauses en vigueur.
static func _treaties_between(state: GameState, player: int, id: int, box: VBoxContainer) -> void:
	var list: Array = []
	for t in WarPeace.treaties_of(state, player):
		if int(t["a"]) == id or int(t["b"]) == id:
			list.append(t)
	if list.is_empty():
		return
	box.add_child(UiTheme.section("Traités signés"))
	for i in mini(3, list.size()):
		var l := UiTheme.dim(treaty_line(state, list[i], player), 13)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(480, 0)
		box.add_child(l)


## Une ligne du registre : nom, date, vainqueur, clauses en vigueur.
static func treaty_line(state: GameState, t: Dictionary, player: int) -> String:
	var w := int(t["w"])
	var who := "statu quo" if w < 0 else ("en votre faveur" if w == player else "en faveur de %s" % state.get_empire(w).short_name())
	var cls := PackedStringArray()
	for k in t["cl"]:
		var u := int(t["cl"][k])
		var lab := String(WarPeace.clause_def(String(k)).get("label", k))
		if u == -2:
			cls.append(lab + " (violée)")
		elif u == -1:
			cls.append(lab)
		elif u > state.tick:
			cls.append("%s (encore %d j)" % [lab, u - state.tick])
	if int(t.get("g", -1)) >= 0:
		cls.append("garanti par l'Arbitre")
	return "%s, %s (%s, %s)%s" % [String(t["name"]), GameCalendar.date_string(int(t["t"])), String(t["kind"]), who,
			(" : " + ", ".join(cls)) if not cls.is_empty() else ""]


## Colonne de gauche : le registre des traités du joueur.
static func side(state: GameState, player: int, width: float) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	if not state.wars_on:
		return box
	var tl := WarLaws.talent_labels(state, player)
	if not tl.is_empty():
		box.add_child(HSeparator.new())
		box.add_child(UiTheme.section("Talents de guerre"))
		for x in tl:
			box.add_child(UiTheme.paragraph("%s : %s" % [String(x[0]), String(x[1])], width, 12))
	for wn in WarLaws.warnings(state, player):
		box.add_child(UiTheme.paragraph("Préavis : %s masse ses flottes face à %s." % [state.get_empire(int(wn[0])).short_name(),
				"vous" if int(wn[1]) == player else state.get_empire(int(wn[1])).short_name()], width, 12))
	var list := WarPeace.treaties_of(state, player)
	if list.is_empty():
		return box
	box.add_child(HSeparator.new())
	box.add_child(UiTheme.section("Registre des traités"))
	for i in mini(5, list.size()):
		box.add_child(UiTheme.paragraph(treaty_line(state, list[i], player), width, 12))
	return box


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
	if bool(rec.get("lim", false)):
		var ll := UiTheme.dim("Guerre limitée%s : flottes et avant-postes seulement, aucun monde peuplé envahi." % (" (kanly)" if String(rec["cb"]) == "kanly" else " (guerre réglée du Nomos)"), 13)
		box.add_child(ll)
		buttons["limited"] = ll
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
	# Lot 2 : lassitude des deux camps, occupation, camp et chef de guerre.
	var ex := UiTheme.dim("Lassitude : vous %d %%, lui %d %%" % [WarPeace.exhaustion(state, player, id), WarPeace.exhaustion(state, id, player)], 13)
	ex.tooltip_text = "De 0 à 100 % : le temps, les vaisseaux perdus, les systèmes occupés. Qui se bat pour conquérir se lasse plus vite que qui défend sa survie. Elle pèse sur la stabilité, et sur la reddition.\nÀ 100 % depuis un an, l'autre peut vous imposer le statu quo ; les deux camps à 100 % depuis un an : statu quo automatique."
	ex.mouse_filter = Control.MOUSE_FILTER_STOP
	box.add_child(ex)
	buttons["exhaustion"] = ex
	if WarPeace.occ_on(state):
		var mine_o := 0
		var his_o := 0
		for sid in WarPeace.occupied_by(state, player):
			if state.system_owner(sid) == id:
				mine_o += 1
		for sid in WarPeace.occupied_by(state, id):
			if state.system_owner(sid) == player:
				his_o += 1
		box.add_child(UiTheme.dim("Occupation : vous tenez %d de ses systèmes, il tient %d des vôtres" % [mine_o, his_o], 13))
		# Bêta-test 2.2 (R2) : combien de systèmes restent libres de chaque côté.
		var gauge := UiTheme.dim("Systèmes libres : vous %s, lui %s" % [AlertBar.free_gauge(state, player), AlertBar.free_gauge(state, id)], 13)
		gauge.tooltip_text = "Un empire dont tous les systèmes sont occupés se rend sans conditions. Quand il ne lui en reste qu'un, les deux camps sont prévenus."
		gauge.mouse_filter = Control.MOUSE_FILTER_STOP
		if WarPeace.free_systems(state, player).size() <= 1 or WarPeace.free_systems(state, id).size() <= 1:
			gauge.add_theme_color_override("font_color", UiTheme.delta_color(WarPeace.free_systems(state, player).size() - WarPeace.free_systems(state, id).size()))
		box.add_child(gauge)
		buttons["free"] = gauge
		var unc := WarPeace.uncond_of(state, player, id)
		var unc2 := WarPeace.uncond_of(state, id, player)
		if not unc.is_empty():
			var ul := UiTheme.dim("%s se rend sans conditions : composez vos termes (volet Traiter, le score compte au maximum) ou exigez sa reddition pour appliquer votre but." % e_short(state, id), 13)
			ul.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			ul.custom_minimum_size = Vector2(480, 0)
			ul.add_theme_color_override("font_color", UiTheme.GOOD)
			box.add_child(ul)
			buttons["uncond"] = ul
		elif not unc2.is_empty():
			var ul2 := UiTheme.dim("Tous vos systèmes sont occupés. Reprenez-en un pour annuler la reddition, ou traitez avant que son but ne s'applique.", 13)
			ul2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			ul2.custom_minimum_size = Vector2(480, 0)
			ul2.add_theme_color_override("font_color", UiTheme.BAD)
			box.add_child(ul2)
			buttons["uncond"] = ul2
	if rec.has("lead") and not Wars.war_by_key(state, String(rec["lead"])).is_empty() and int(rec.get("chief", -1)) >= 0:
		var lw := Wars.war_by_key(state, String(rec["lead"]))
		box.add_child(UiTheme.dim("Votre chef de guerre : %s (%s) ; il négocie pour vous." % [state.get_empire(int(rec["chief"])).short_name(), String(lw.get("name", ""))], 13) if int(rec["a"]) == player
				else UiTheme.dim("Il combat aux côtés de %s : son chef négocie pour lui." % state.get_empire(int(rec["chief"])).short_name(), 13))
	else:
		var con := WarPeace.contributions(state, rec, player)
		if con.size() > 1:
			var tot := 0
			for k in con:
				tot += maxi(0, int(con[k]))
			var names := PackedStringArray()
			var ids := con.keys()
			ids.sort()
			for k in ids:
				@warning_ignore("integer_division")
				names.append("%s %d %%" % [state.get_empire(int(k)).short_name(), 100 * maxi(0, int(con[k])) / maxi(1, tot)])
			var cl := UiTheme.dim("Votre camp (contribution) : %s" % ", ".join(names), 13)
			cl.tooltip_text = "Le butin suit la contribution : les revendications qu'un allié tient lui reviennent, l'influence et la rançon se partagent selon les batailles et les systèmes pris."
			cl.mouse_filter = Control.MOUSE_FILTER_STOP
			box.add_child(cl)
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
	var sq := _btn("IMPOSER LE STATU QUO", WarPeace.check_impose(state, player, id), "Chacun garde ce qu'il tient et revendique, le reste revient. Possible un an après que sa lassitude a atteint 100 %.",
			func() -> void: emit.call(SimCommands.war_act(player, "status", id)))
	flow.add_child(sq)
	buttons["status"] = sq
	if rec.has("lead") and int(rec["a"]) == player:
		var sp2 := _btn("PAIX SÉPARÉE (%d influence)" % int(Wars.data()["sides"]["separate_influence"]), WarPeace.check_separate(state, player, id),
				"Vous sortez de la guerre au statu quo ; votre chef de guerre continue seul, et s'en souviendra.",
				func() -> void: emit.call(SimCommands.war_act(player, "separate", id)))
		flow.add_child(sp2)
		buttons["separate"] = sp2
	box.add_child(flow)
	if not bool(rec.get("lim", false)):
		_claim_buttons(state, player, id, emit, buttons, box)


# --- Lot 3 : crise, ultimatums, médiation, garantie ------------------------------------------------

## Crise diplomatique : l'ouvrir (motif et but choisis plus haut), ou la suivre (ralliés, reculer).
static func _crisis_block(state: GameState, player: int, id: int, emit: Callable, buttons: Dictionary, draft: Dictionary, box: VBoxContainer) -> void:
	var rec := WarLaws.crisis_between(state, player, id)
	var flow := VassalUi._flow()
	if rec.is_empty():
		var c := choice(state, player, id, draft)
		var s := "%s|%s" % [c[0], c[1]]
		var cost := GameData.format_amounts(Wars.data()["crisis"]["cost"])
		var b := _btn("OUVRIR UNE CRISE (%s)" % cost, WarLaws.check_crisis(state, player, id, s),
				"Annonce votre motif et votre but sans tirer : trente jours pour rallier des tiers. Avant l'échéance, l'un des deux peut reculer (le défenseur cède le but, l'agresseur ses revendications) ; sinon, c'est la guerre, ralliés compris.",
				func() -> void: emit.call(SimCommands.war_act(player, "crisis", id, s)))
		flow.add_child(b)
		buttons["crisis"] = b
		box.add_child(flow)
		return
	box.add_child(UiTheme.section("Crise diplomatique"))
	var mine: Array = rec["ra"] if int(rec["a"]) == player else rec["rd"]
	var his: Array = rec["rd"] if int(rec["a"]) == player else rec["ra"]
	var mine_n := PackedStringArray()
	var his_n := PackedStringArray()
	for x in mine:
		mine_n.append(state.get_empire(int(x)).short_name())
	for x in his:
		his_n.append(state.get_empire(int(x)).short_name())
	var l := UiTheme.dim("%s : %s, but %s ; guerre dans %d jours. Vos ralliés : %s ; les siens : %s." % [
			"Vous l'avez sommé" if int(rec["a"]) == player else "Il vous somme", Wars.casus_label(String(rec["cb"])).to_lower(), Wars.goal_label(String(rec["g"])).to_lower(),
			maxi(0, int(rec["end"]) - state.tick), ", ".join(mine_n) if not mine_n.is_empty() else "aucun", ", ".join(his_n) if not his_n.is_empty() else "aucun"], 13)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(480, 0)
	box.add_child(l)
	buttons["crisis_line"] = l
	var bd := _btn("RECULER", WarLaws.check_backdown(state, player, id),
			"Défenseur : vous cédez son but (revendications, rançon, humiliation…). Agresseur : vous abandonnez vos revendications et %d influence de prestige." % int(Wars.data()["crisis"]["backdown_influence"]),
			func() -> void: emit.call(SimCommands.war_act(player, "backdown", id)))
	flow.add_child(bd)
	buttons["backdown"] = bd
	var n := 0
	for t in WarLaws.rally_candidates(state, rec, player):
		if n >= 3:
			break
		var et := state.get_empire(t)
		var b2 := _btn("RALLIER %s" % et.short_name().to_upper(), WarLaws.check_rally(state, player, t, id),
				"Il entrera en guerre à vos côtés si la crise tourne à la guerre, et touchera sa part du butin selon sa contribution.",
				func() -> void: emit.call(SimCommands.war_act(player, "rally", t, str(id))))
		flow.add_child(b2)
		buttons["rally_%d" % t] = b2
		n += 1
	box.add_child(flow)


static func _ultimatum_buttons(state: GameState, player: int, id: int, emit: Callable, buttons: Dictionary, box: VBoxContainer) -> void:
	if not WarLaws.crisis_between(state, player, id).is_empty():
		return
	var flow := VassalUi._flow()
	var cost := GameData.format_amounts(Wars.data()["ultimatum"]["cost"])
	var n := 0
	for what in WarLaws.ult_whats(state, player, id):
		if n >= 3:
			break
		var w := String(what)
		var b := _btn("ULTIMATUM : %s" % WarLaws.what_label(state, w).to_upper(), WarLaws.check_ultimatum(state, player, id, w),
				"%s Accepter lui évite la guerre (il s'en souviendra) ; refuser vous donne le motif « Ultimatum refusé » pendant 5 ans, sans réprobation." % cost,
				func() -> void: emit.call(SimCommands.war_act(player, "ultimatum", id, w)))
		flow.add_child(b)
		buttons["ult_" + w] = b
		n += 1
	if n > 0:
		box.add_child(flow)


## Ce que le joueur peut faire en tiers : médiation (talent), garantie (Arbitre).
static func _third_party(state: GameState, player: int, id: int, emit: Callable, buttons: Dictionary, box: VBoxContainer) -> void:
	var flow := VassalUi._flow()
	for pair in WarLaws.mediable(state, player):
		var a := int(pair[0])
		var b := int(pair[1])
		if a != id and b != id:
			continue
		var cost := GameData.format_amounts(Wars.data()["mediation"]["cost"])
		var mb := _btn("MÉDIATION : %s / %s (%s)" % [state.get_empire(a).short_name().to_upper(), state.get_empire(b).short_name().to_upper(), cost], "",
				"Talent de votre peuple : vous ramenez la paix au statu quo ; les deux camps s'en souviendront avec gratitude.",
				func() -> void: emit.call(SimCommands.war_act(player, "mediate", a, str(b))))
		flow.add_child(mb)
		buttons["mediate"] = mb
	if AmphInst.arbiter(state) == player:
		for t in WarPeace.treaties_of(state, id):
			if int(t["w"]) < 0 or int(t.get("g", -1)) >= 0 or int(t["a"]) == player or int(t["b"]) == player:
				continue
			var tid := int(t["id"])
			var gb := _btn("GARANTIR LE %s" % String(t["name"]).to_upper(), WarLaws.check_guarantee(state, player, tid),
					"En tant qu'Arbitre des étoiles : qui violera ce traité donnera à chaque amphictyon le motif Défense commune.",
					func() -> void: emit.call(SimCommands.war_act(player, "guarantee", tid)))
			flow.add_child(gb)
			buttons["guarantee"] = gb
			break
	if flow.get_child_count() > 0:
		box.add_child(flow)


static func e_short(state: GameState, id: int) -> String:
	var e := state.get_empire(id)
	return e.short_name() if e != null else "?"
