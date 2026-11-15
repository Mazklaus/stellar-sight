class_name AncientsUi
extends RefCounted
## Section « Anciennes » de l'écran Diplomatie (prop. 29) : une fiche par puissance ancienne
## rencontrée (humeur, rapport de force, colères, attentes, faveur et postes), avec les actes possibles
## (contribuer, interroger un poste, guerre, paix). Les éléments de l'Éveil viennent d'AncientsWake.

const WAR_LABELS := {"punition": "Punition", "empire": "vous l'avez déclarée", "endiguement": "Endiguement", "dominion": "Dominion refusé", "sainte": "guerre sainte"}
const STAGE_LABELS := {"sleep": "Endormie", "notice": "S'éveille", "awake": "Éveillée", "decadent": "Décadente", "guardian": "Gardienne en armes", "fallen": "Abattue"}


## Ligne grisée qui passe à la ligne (la colonne de droite ne doit pas s'élargir).
static func _dim(text: String, size := 13) -> Label:
	var l := UiTheme.dim(text, size)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size = Vector2(320, 0)
	return l


static func _btn(text: String, why: String, tip: String, on_press: Callable, primary := false) -> Button:
	return VassalUi._btn(text, why, tip, on_press, primary)


## null si aucune ancienne n'est connue du joueur.
static func block(state: GameState, player: int, emit: Callable, buttons: Dictionary, draft: Dictionary) -> Control:
	if not Ancients.enabled(state) or player < 0:
		return null
	var met := Ancients.met(state, player)
	if met.is_empty():
		return null
	var blk := Widgets.Block.new("Anciennes")
	blk.body.add_child(_dim("Des civilisations d'avant, repliées dans leur poche d'étoiles. Elles ne votent pas, ne commercent pas et ne se laissent pas espionner ; elles demandent, offrent et s'offusquent.", 13))
	for id in met:
		blk.body.add_child(_card(state, player, id, emit, buttons, draft))
	return blk


static func _card(state: GameState, player: int, id: int, emit: Callable, buttons: Dictionary, draft: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var kd := Ancients.kind_def(Ancients.kind_of(state, id))
	var title := Label.new()
	title.text = Ancients.name_of(state, id)
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color.html(String(kd.get("color", "#d8c890"))))
	box.add_child(title)
	box.add_child(_dim(String(kd.get("blurb", "")), 13))
	var g := GridContainer.new()
	g.columns = 4
	g.add_theme_constant_override("h_separation", 18)
	g.add_theme_constant_override("v_separation", 4)
	box.add_child(g)
	KoinonUi._kv(g, "État", String(STAGE_LABELS.get(Ancients.stage(state, id), Ancients.stage(state, id))))
	if Ancients.no_opinion(state, id):
		KoinonUi._kv(g, "Humeur", "Sans opinion : elle parie, elle observe")
	else:
		var at := Ancients.attitude(state, id, player)
		var op := Ancients.opinion(state, id, player)
		var v := KoinonUi._kv(g, "Humeur", "%s (%+d)" % [String(at.get("label", "?")), op])
		v.add_theme_color_override("font_color", UiTheme.GOOD if op >= 100 else (UiTheme.WARN if op >= 0 else UiTheme.BAD))
		v.tooltip_text = String(at.get("text", ""))
		v.mouse_filter = Control.MOUSE_FILTER_STOP
	KoinonUi._kv(g, "Rapport de force", Ancients.force_text(state, id, player))
	KoinonUi._kv(g, "Mondes", "%d systèmes" % Ancients.systems_of(state, id).size())
	box.add_child(_dim("Ce qui la fâche : %s" % String(kd.get("angers_text", "")), 13))
	box.add_child(_dim("Ce qu'elle veut : %s" % String(kd.get("wants_text", "")), 13))
	if Ancients.at_war_with(state, id, player):
		var w: Dictionary = Ancients.get_a(state, id)["war"][player]
		var wl := _dim("En guerre avec vous (%s), depuis %d mois." % [String(WAR_LABELS.get(String(w["why"]), w["why"])),
				maxi(0, state.tick - int(w["since"])) / 30], 13)
		wl.add_theme_color_override("font_color", UiTheme.BAD)
		box.add_child(wl)
	for line in AncientsWake.ui_lines(state, player, id) + AncientsBridges.ui_lines(state, player, id):
		box.add_child(_dim(String(line), 13))
	# Faveur et postes (prop. 11).
	var posts: Array = kd.get("posts", [])
	if not posts.is_empty():
		box.add_child(UiTheme.section("Faveur et postes"))
		var rk := Ancients.ranking(state, id)
		var mine := 0
		var place := 0
		for i in rk.size():
			if int(rk[i][1]) == player:
				mine = -int(rk[i][0])
				place = i + 1
		var a := Ancients.get_a(state, id)
		box.add_child(_dim("Vos contributions de la période : %d points%s. Prochaine attribution dans %d mois." % [mine,
				(" (%de)" % place) if place > 0 else "", maxi(0, int(a["term"]) - state.tick) / 30], 13))
		for pd: Dictionary in posts:
			var holder := Ancients.post_holder(state, id, String(pd["id"]))
			var who := state.get_empire(holder).short_name() if holder >= 0 and state.get_empire(holder) != null else "personne"
			var pl := _dim("%s : %s. %s" % [String(pd["label"]), who, String(pd.get("text", ""))], 13)
			if holder == player:
				pl.add_theme_color_override("font_color", UiTheme.GOOD)
			box.add_child(pl)
	# Actes.
	var acts := HFlowContainer.new()
	acts.add_theme_constant_override("h_separation", 10)
	acts.add_theme_constant_override("v_separation", 6)
	box.add_child(acts)
	for res in Ancients.data()["contrib"]["options"]:
		var r := String(res)
		var cost := Ancients.give_cost(state, player, r)
		var b := _btn("Offrir %d %s" % [cost, GameData.resource_label(r).to_lower()], Ancients.check_act(state, player, "give", id, r, -1),
				"Contribution : améliore son humeur et compte pour l'attribution des postes.",
				func() -> void: emit.call(SimCommands.anc_act(player, "give", id, r)))
		acts.add_child(b)
		buttons["anc_give_%d_%s" % [id, r]] = b
	var ip := Ancients.intel_post(state, id, player)
	if not ip.is_empty():
		var target := -1
		if String(ip["intel"]) == "empire":
			var key := "anc_ask_%d" % id
			var ob := OptionButton.new()
			ob.focus_mode = Control.FOCUS_NONE
			var cands: Array[int] = []
			for e in state.empires:
				if e.id != player and not e.eliminated:
					cands.append(e.id)
					ob.add_item(e.short_name())
			if not draft.has(key) and not cands.is_empty():
				draft[key] = cands[0]
			target = int(draft.get(key, -1))
			ob.selected = cands.find(target)
			ob.item_selected.connect(func(i: int) -> void:
				draft[key] = cands[i]
				emit.call({}))
			acts.add_child(ob)
		var t2 := target
		var qb := _btn("Interroger (%s, 30 influence)" % String(ip["label"]), Ancients.check_act(state, player, "ask", id, "", t2),
				"Le titulaire du poste peut poser une question ; la réponse arrive dans la chronique.",
				func() -> void: emit.call(SimCommands.anc_act(player, "ask", id, "", t2)))
		acts.add_child(qb)
		buttons["anc_ask_%d" % id] = qb
	if Ancients.at_war_with(state, id, player):
		var pb := _btn("Proposer la paix (50 influence)", Ancients.check_act(state, player, "peace", id, "", -1),
				"Seulement après six mois de guerre, et tant qu'elle dort.",
				func() -> void: emit.call(SimCommands.anc_act(player, "peace", id)))
		acts.add_child(pb)
		buttons["anc_peace_%d" % id] = pb
	else:
		var wb := _btn("Déclarer la guerre", Ancients.check_act(state, player, "war", id, "", -1),
				"Ses mondes achevés valent une fortune. Ses flottes aussi, mais dans l'autre sens.",
				func() -> void: emit.call(SimCommands.anc_act(player, "war", id)))
		acts.add_child(wb)
		buttons["anc_war_%d" % id] = wb
	for b2 in AncientsWake.ui_buttons(state, player, id, emit) + AncientsBridges.ui_buttons(state, player, id, emit):
		acts.add_child(b2)
	box.add_child(HSeparator.new())
	return box
