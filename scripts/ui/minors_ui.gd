class_name MinorsUi
extends RefCounted
## Section « Peuples mineurs » de l'écran Diplomatie (prop. 34) : une liste façon Civilization VI (faveur,
## palier, suzerain, cadeau, quête) puis la fiche détaillée du peuple choisi, avec ses actes (émissaire,
## cadeaux, poste d'observation, livraison, levée, intégration, guerre, paix). En dessous, les traits
## d'assimilation des peuples absorbés. Les actes des lots 2 et 3 viennent de MinorsLife et MinorsBridges.

const TIER_COLORS := {"": Color(0.6, 0.6, 0.62), "contact": Color(0.75, 0.75, 0.6), "ami": Color(0.55, 0.8, 0.55), "suzerain": Color(0.95, 0.8, 0.35)}


static func _dim(text: String, size := 13) -> Label:
	return AncientsUi._dim(text, size)


static func _btn(text: String, why: String, tip: String, on_press: Callable, primary := false) -> Button:
	return VassalUi._btn(text, why, tip, on_press, primary)


## null si le joueur ne connaît aucun peuple et n'en a absorbé aucun.
static func block(state: GameState, player: int, emit: Callable, buttons: Dictionary, draft: Dictionary) -> Control:
	if not Minors.enabled(state) or player < 0:
		return null
	var met := Minors.met(state, player)
	if met.is_empty() and Minors.absorbed(state, player).is_empty() and MinorsLife.pres_of(state, player).is_empty():
		return null
	var blk := Widgets.Block.new("Peuples mineurs")
	blk.body.add_child(_dim("De petites civilisations qui ne sont pas des empires : on les protège, on les influence, on les absorbe. Faveur 20 : contact ; 50 : amitié ; au moins 60 et 10 de plus que tous les autres : suzerain.", 13))
	if not met.is_empty():
		blk.body.add_child(_list(state, player, met, emit, draft, buttons))
		var sel := int(draft.get("min_sel", met[0]))
		if not met.has(sel):
			sel = met[0]
		blk.body.add_child(_card(state, player, sel, emit, buttons))
	var tb := _traits(state, player, emit, buttons)
	if tb != null:
		blk.body.add_child(tb)
	var pb := MinorsLife.ui_pres(state, player, emit)
	if pb != null:
		blk.body.add_child(pb)
	return blk


static func _list(state: GameState, player: int, met: Array[int], emit: Callable, draft: Dictionary, buttons: Dictionary) -> Control:
	var g := GridContainer.new()
	g.columns = 6
	g.add_theme_constant_override("h_separation", 14)
	g.add_theme_constant_override("v_separation", 3)
	for h in ["Peuple", "Âge", "Faveur", "Palier", "Suzerain", "Quête"]:
		g.add_child(UiTheme.dim(h, 12))
	for id in met:
		var b := Button.new()
		b.text = Minors.short_of(state, id)
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_color_override("font_color", Color.html(String(Minors.kind_def(Minors.kind_of(state, id)).get("color", "#b0b0b0"))))
		b.tooltip_text = "%s : %s" % [Minors.name_of(state, id), String(Minors.gift_def(state, id).get("text", ""))]
		b.pressed.connect(func() -> void:
			draft["min_sel"] = id
			emit.call({}))
		buttons["min_sel_%d" % id] = b
		g.add_child(b)
		g.add_child(UiTheme.dim(Minors.age_label(state, id), 12))
		var fl := Label.new()
		fl.text = "%d" % Minors.fav(state, id, player) if Minors.can_talk(state, id, player) else "—"
		g.add_child(fl)
		var t := Minors.tier(state, id, player)
		var tl := Label.new()
		tl.text = String(Minors.TIER_LABELS.get(t, t))
		tl.add_theme_color_override("font_color", TIER_COLORS.get(t, Color.WHITE))
		g.add_child(tl)
		var s := Minors.suzerain(state, id)
		g.add_child(UiTheme.dim(state.get_empire(s).short_name() if s >= 0 and state.get_empire(s) != null else "personne", 12))
		var q: Dictionary = Minors.get_m(state, id).get("quest", {})
		g.add_child(UiTheme.dim(String(Minors.quest_def(String(q.get("id", ""))).get("label", "—")) if not q.is_empty() else "—", 12))
	return g


static func _card(state: GameState, player: int, id: int, emit: Callable, buttons: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.add_child(HSeparator.new())
	var m := Minors.get_m(state, id)
	var kd := Minors.kind_def(String(m["kind"]))
	var title := Label.new()
	title.text = Minors.name_of(state, id)
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color.html(String(kd.get("color", "#b0b0b0"))))
	box.add_child(title)
	box.add_child(_dim("%s  ·  %s" % [String(kd.get("registre", "")), String(kd.get("blurb", ""))], 13))
	box.add_child(_dim(Minors.line(state, id), 13))
	var g := GridContainer.new()
	g.columns = 4
	g.add_theme_constant_override("h_separation", 18)
	g.add_theme_constant_override("v_separation", 4)
	box.add_child(g)
	var gd := Minors.gift_def(state, id)
	var gv := KoinonUi._kv(g, "Cadeau de suzerain", String(gd.get("label", "")))
	gv.tooltip_text = String(gd.get("text", ""))
	gv.mouse_filter = Control.MOUSE_FILTER_STOP
	var td: Dictionary = kd.get("trait", {})
	var tv := KoinonUi._kv(g, "Trait d'assimilation", String(td.get("label", "")))
	tv.tooltip_text = String(td.get("text", ""))
	tv.mouse_filter = Control.MOUSE_FILTER_STOP
	var od := Minors.orientation(state, id)
	KoinonUi._kv(g, "Bonus d'amitié", _res_text(od.get("friend", {})))
	if Minors.is_pre(state, id):
		KoinonUi._kv(g, "Âge", "%s (%d %%)" % [Minors.age_label(state, id), mini(99, int(m["age_days"]) * 100 / maxi(1, Minors.age_need(state, id)))])
	else:
		KoinonUi._kv(g, "Flotte", "puissance %d" % Minors.power(state, id))
	KoinonUi._kv(g, "Garnison", "%d" % Combat.garrison(state, int(m["sid"])))
	# Faveur de chaque empire (prop. 9).
	var favs: Array = []
	for eid in Minors._contact_ids(m):
		var e := state.get_empire(eid)
		if e != null:
			favs.append("%s %d" % [e.short_name(), Minors.fav(state, id, eid)])
	box.add_child(_dim("Faveur : %s" % (", ".join(favs) if not favs.is_empty() else "personne"), 13))
	var qt := Minors.quest_text(state, id)
	if qt != "":
		box.add_child(_dim("Quête : %s (+%d de faveur au premier qui réussit)" % [qt, int(Minors.data()["quests"]["reward"])], 13))
	if Minors.at_war_with(state, id, player):
		var wl := _dim("En guerre avec vous depuis %d mois." % (maxi(0, state.tick - int(m["war"][player])) / 30), 13)
		wl.add_theme_color_override("font_color", UiTheme.BAD)
		box.add_child(wl)
	if Minors.is_pre(state, id) and not Minors.can_talk(state, id, player):
		box.add_child(_dim("Ils ne savent pas encore parler aux étoiles : un poste d'observation ouvre la diplomatie avec eux.", 13))
	for l in MinorsLife.ui_lines(state, player, id) + MinorsBridges.ui_lines(state, player, id):
		box.add_child(_dim(String(l), 13))
	# Actes.
	var acts := HFlowContainer.new()
	acts.add_theme_constant_override("h_separation", 10)
	acts.add_theme_constant_override("v_separation", 6)
	box.add_child(acts)
	var envoys: Array = Minors.data()["favor"]["envoys"]
	var cur := Minors.envoy_level(state, id, player)
	for i in envoys.size():
		var lvl := i + 1
		var ed: Dictionary = envoys[i]
		var eb := _btn("%s%s (%d influence/mois, +%d)" % ["✓ " if cur == lvl else "", String(ed["label"]), int(ed["influence"]), int(ed["fav"])],
				"déjà en place" if cur == lvl else Minors.check_act(state, player, "envoy", id, "", lvl),
				"Un émissaire fait monter la faveur chaque mois. Sans entretien, elle s'use.",
				func() -> void: emit.call(SimCommands.min_act(player, "envoy", id, "", lvl)))
		acts.add_child(eb)
		buttons["min_envoy_%d_%d" % [id, lvl]] = eb
	if cur > 0:
		var rb := _btn("Rappeler l'émissaire", "", "", func() -> void: emit.call(SimCommands.min_act(player, "envoy", id, "", 0)))
		acts.add_child(rb)
	for res in Minors.data()["favor"]["gifts"]:
		var r := String(res)
		var gdd: Dictionary = Minors.data()["favor"]["gifts"][r]
		var b := _btn("Offrir %d %s (+%d)" % [int(gdd["cost"]), GameData.resource_label(r).to_lower(), int(gdd["fav"])], Minors.check_act(state, player, "gift", id, r, -1),
				"Un cadeau par mois.", func() -> void: emit.call(SimCommands.min_act(player, "gift", id, r)))
		acts.add_child(b)
		buttons["min_gift_%d_%s" % [id, r]] = b
	if Minors.is_pre(state, id):
		for mode in ["discret", "ouvert"]:
			var md := String(mode)
			var k := int(Minors.data()["observation"]["knowledge"][md])
			var pb := _btn("%sPoste %s (Savoir +%d/mois)" % ["✓ " if Minors.post_mode(state, id, player) == md else "", md, k],
					Minors.check_act(state, player, "post", id, md, -1),
					"Station en orbite (100 matériaux, 20 influence). Ouvert : plus de Savoir, mais ils prennent conscience de vous.",
					func() -> void: emit.call(SimCommands.min_act(player, "post", id, md)))
			acts.add_child(pb)
			buttons["min_post_%d_%s" % [id, md]] = pb
	var q: Dictionary = m.get("quest", {})
	if Minors.quest_def(String(q.get("id", ""))).has("deliver"):
		var db := _btn("Livrer (quête)", Minors.check_act(state, player, "deliver", id, "", -1), Minors.quest_text(state, id),
				func() -> void: emit.call(SimCommands.min_act(player, "deliver", id)))
		acts.add_child(db)
		buttons["min_deliver_%d" % id] = db
	if Minors.suzerain(state, id) == player or MinorsLife.declining(state, id):
		var lb := _btn("Lever leurs troupes (%d énergie, 2 ans)" % Minors.levy_cost(state, id, player), Minors.check_act(state, player, "levy", id, "", -1),
				"Le suzerain loue leur flotte (spatiaux) ou leurs régiments (âge féodal et au-delà).",
				func() -> void: emit.call(SimCommands.min_act(player, "levy", id)))
		acts.add_child(lb)
		buttons["min_levy_%d" % id] = lb
		var ib := _btn("Intégrer (%d influence)" % Minors.integration_cost(state, id, player), Minors.check_act(state, player, "integrate", id, "", -1),
				"Suzerain depuis deux ans et faveur 100 : leur monde devient votre colonie, leurs habitants vos citoyens, leur trait le vôtre.",
				func() -> void: emit.call(SimCommands.min_act(player, "integrate", id)), true)
		acts.add_child(ib)
		buttons["min_integrate_%d" % id] = ib
	if Minors.at_war_with(state, id, player):
		var pc := _btn("Faire la paix (%d influence)" % int(Minors.data()["war"]["peace_cost"]), Minors.check_act(state, player, "peace", id, "", -1),
				"Après six mois de guerre.", func() -> void: emit.call(SimCommands.min_act(player, "peace", id)))
		acts.add_child(pc)
		buttons["min_peace_%d" % id] = pc
	else:
		var wb := _btn("Déclarer la guerre", Minors.check_act(state, player, "war", id, "", -1),
				"Leur faveur tombe à 0 et ils ne l'oublieront pas. Leurs amis non plus.",
				func() -> void: emit.call(SimCommands.min_act(player, "war", id)))
		acts.add_child(wb)
		buttons["min_war_%d" % id] = wb
	for b2 in MinorsLife.ui_buttons(state, player, id, emit) + MinorsBridges.ui_buttons(state, player, id, emit):
		acts.add_child(b2)
	return box


static func _res_text(res: Dictionary) -> String:
	var parts: Array = []
	for r in res:
		parts.append("%s +%d" % [GameData.resource_label(String(r)), int(res[r])])
	return ", ".join(parts) + " par mois"


## Traits d'assimilation (prop. 21) : actifs et en réserve.
static func _traits(state: GameState, player: int, emit: Callable, buttons: Dictionary) -> Control:
	var ab := Minors.absorbed(state, player)
	if ab.is_empty():
		return null
	var box := VBoxContainer.new()
	box.add_child(HSeparator.new())
	box.add_child(UiTheme.section("Traits d'assimilation (%d / %d actifs)" % [Minors.active_traits(state, player).size(), Minors.trait_slots(state, player)]))
	for k in ab:
		var kind := String(k)
		var td := Minors.trait_def(kind)
		var row := HBoxContainer.new()
		var on := Minors.active_traits(state, player).has(kind)
		var l := _dim("%s%s : %s" % ["✓ " if on else "", String(td.get("label", kind)), String(td.get("text", ""))], 13)
		if on:
			l.add_theme_color_override("font_color", UiTheme.GOOD)
		row.add_child(l)
		if not on:
			var b := _btn("Activer", Minors.check_act(state, player, "trait", -1, kind, -1), "Un emplacement libre, ou %d influence pour remplacer le plus ancien." % int(Minors.data()["traits"]["swap_cost"]),
					func() -> void: emit.call(SimCommands.min_act(player, "trait", -1, kind)))
			row.add_child(b)
			buttons["min_trait_%s" % kind] = b
		box.add_child(row)
	return box
