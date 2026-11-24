class_name ForgeUi
extends RefCounted
## Écran Forge des mondes (prop. 5) : un onglet de l'écran Merveilles, sans nouvelle lentille. Masse
## planétaire, chantiers planétaires, mondes façonnés et leur intégrité, ce qu'on peut lancer et où ; au
## centre, les chantiers connus, les mondes façonnés, les mondes-reliquaires et le catalogue. Actions
## sur l'écran Système (prop. 2).

const COLOR := Color(0.95, 0.78, 0.55)


static func signature(es: EmpireScreens) -> String:
	var state := es._state
	if not WorldForge.enabled(state):
		return "off"
	var e := state.get_empire(es._player)
	@warning_ignore("integer_division")
	return "%d|%d|%s|%s|%d|%d" % [e.techs.size(), state.tick / 30, str(WorldForge.jobs(state)), str(WorldForge.sub(state, "worlds").size()), WorldForge.mass(state, es._player),
			Megastructures.architects_of(state, es._player).size()]


static func _btn(es: EmpireScreens, text: String, command: Dictionary, tip: String, key: String) -> Button:
	var why := SimCommands.validate(es._state, command)
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.disabled = why != ""
	b.clip_text = true
	b.custom_minimum_size = Vector2(EmpireScreens.SIDE_WIDTH - 24.0, 0)
	b.tooltip_text = tip + ("\n\nImpossible : %s." % why if why != "" else "")
	b.pressed.connect(func() -> void: es.command_requested.emit(command))
	es.forge_buttons[key] = b
	return b


static func job_text(state: GameState, j: Dictionary) -> String:
	var where := WorldForge.world_name(state, int(j["p"])) if int(j["p"]) >= 0 else "orbite de %s" % state.galaxy.systems[int(j["s"])].system_name
	var s := "%s : %s, %d / %d jours" % [WorldForge.op_label(String(j["op"])), where, int(j["tot"]) - int(j["w"]), int(j["tot"])]
	if int(j.get("for", -1)) >= 0 and state.get_empire(int(j["for"])) != null:
		s += " (commande de %s)" % state.get_empire(int(j["for"])).short_name()
	return s


static func world_text(state: GameState, pid: int) -> String:
	var w := WorldForge.world(state, pid)
	var p := state.galaxy.get_planet(pid)
	var s := "%s (%s, taille %d)" % [WorldForge.world_name(state, pid), Megastructures.planet_label(p.type), p.size]
	var up := int((WorldForge.cfg("worlds").get(String(w.get("k", "")), {}) as Dictionary).get("upkeep", 0))
	if up > 0:
		s += ", intégrité %d %%" % int(w.get("integ", 100))
	if int(w.get("eng", 0)) > 0:
		s += ", moteurs"
	var mv: Variant = WorldForge.sub(state, "moving").get(str(pid), null)
	if mv is Dictionary:
		s += ", en marche vers %s (%d jours)" % [state.galaxy.systems[int(mv["to"])].system_name, int(mv["w"])]
	if WorldForgeWorld.is_living(state, pid):
		s += ", vivant"
	return s


static func build(es: EmpireScreens) -> void:
	var state := es._state
	var player := es._player
	es._forge_sig = signature(es)
	es._side_header("screen_forge", "Forge des mondes", COLOR, "faction")
	MegasUi.tabs(es, "forge")
	var w := EmpireScreens.SIDE_WIDTH - 24.0
	if not WorldForge.applies(state, player):
		es._side_box.add_child(UiTheme.paragraph("Dans cette partie, la Forge des mondes n'est pas en jeu (Nouvelle partie : Forge des mondes).", w, 13))
		return
	var g := es._grid()
	es._side_box.add_child(g)
	es._key_value(g, "Réglage", WorldForge.mode_label(state))
	es._key_value(g, "Masse planétaire", str(WorldForge.mass(state, player)))
	es._key_value(g, "Chantiers planétaires", "%d / %d" % [WorldForge.busy(state, player), WorldForge.slots(state, player)])
	es._key_value(g, "Vaisseaux-architectes", str(Megastructures.architects_of(state, player).size()))
	es._key_value(g, "Mondes créés / défaits", "%d / %d" % [WorldForge.stat(state, player, "made"), WorldForge.stat(state, player, "dism")])
	var t := WorldForge.talent(state, player)
	if t.has("label"):
		es._side_box.add_child(HSeparator.new())
		es._side_box.add_child(UiTheme.dim("Talent de votre peuple", 13))
		es._side_box.add_child(UiTheme.paragraph("%s : %s" % [String(t["label"]), String(t.get("text", ""))], w, 12))
	if WorldForge.mass(state, player) >= 10:
		es._side_box.add_child(_btn(es, "Fondre 10 Masse (+%d matériaux)" % (10 * WorldForge.r_int("mass_materials", 10)), SimCommands.forge_act(player, "melt", {"n": 10}),
				String((WorldForge.cfg("instant").get("fondre", {}) as Dictionary).get("text", "")), "melt"))
	es._side_box.add_child(HSeparator.new())
	var mine := WorldForge.jobs_of(state, player)
	if not mine.is_empty():
		es._side_box.add_child(UiTheme.dim("Vos chantiers", 13))
	for j in mine:
		es._side_box.add_child(UiTheme.paragraph(job_text(state, j), w, 12))
		es._side_box.add_child(_btn(es, "Abandonner", SimCommands.forge_act(player, "cancel", {"id": int(j["id"])}), "Rien n'est remboursé.", "cancel:%d" % int(j["id"])))
	# Mondes à moteurs : mettre en marche.
	var wk := WorldForge.sub(state, "worlds").keys()
	wk.sort_custom(func(a: Variant, b: Variant) -> bool: return int(a) < int(b))
	for k in wk:
		var pid := int(k)
		if WorldForge.holder(state, pid) != player or int(WorldForge.world(state, pid).get("eng", 0)) <= 0:
			continue
		var tg := WorldForgeWorld.move_targets(state, player, pid)
		if not tg.is_empty():
			es._side_box.add_child(_btn(es, "Mettre en marche : %s vers %s" % [WorldForge.world_name(state, pid), state.galaxy.systems[tg[0]].system_name],
					SimCommands.forge_act(player, "move", {"p": pid, "t": tg[0]}), String((WorldForge.cfg("instant").get("deplacer", {}) as Dictionary).get("text", "")), "move:%d" % pid))
	es._side_box.add_child(UiTheme.dim("Lancer", 13))
	var any := false
	for op in WorldForge.op_ids():
		if not WorldForge.unlocked(state, player, op):
			continue
		var arg := "prefere" if op == "sur_mesure" else ""
		var s := WorldForge.sites(state, player, op, 1, arg)
		if s.is_empty():
			continue
		any = true
		var site: Array = s[0]
		var where := WorldForge.world_name(state, int(site[1])) if int(site[1]) >= 0 else "orbite de %s" % state.galaxy.systems[int(site[0])].system_name
		var cost := WorldForge.op_cost(state, player, op, int(site[0]))
		var m := WorldForge.op_mass(op)
		es._side_box.add_child(_btn(es, "%s : %s (%s%s)" % [WorldForge.op_label(op), where, GameData.format_amounts(cost), (", %d Masse" % m) if m > 0 else ""],
				SimCommands.forge_act(player, "plan", {"op": op, "s": int(site[0]), "p": int(site[1]), "a": arg}),
				("Le Vaisseau-architecte libre le plus proche part lancer le chantier.\n\n" if WorldForge.needs_architect(op) else "") + String(WorldForge.op_def(op).get("text", "")),
				"plan:" + op))
	if not any:
		es._side_box.add_child(UiTheme.paragraph("Aucun site disponible : il faut la technologie et un système tenu qui convient (voir l'écran Système pour chaque corps).", w, 12))
	es._side_box.add_child(HSeparator.new())
	es._side_box.add_child(UiTheme.paragraph("Un chantier planétaire se lance sur un corps d'un système que vous tenez, par un Vaisseau-architecte présent : un chantier par système, %d à la fois au départ, payé au lancement. Une flotte ennemie dans le système le suspend ; la prise du système le donne au vainqueur. Les mondes façonnés coûtent de l'énergie chaque mois : sans elle, leur intégrité baisse jusqu'à l'effondrement." % WorldForge.r_int("slots", 2), w, 12))

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	es._content.add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 18)
	scroll.add_child(col)
	var seen := Fleets.visible_systems(state, player)
	var known := func(sid: int) -> bool: return es.see_all or seen.has(sid) or Fleets.is_explored(state, player, sid)

	var jb := Widgets.Block.new("Chantiers planétaires")
	col.add_child(jb)
	var nj := 0
	for id in WorldForge.job_ids(state):
		var j := WorldForge.get_job(state, id)
		if int(j["o"]) != player and int(j.get("b", -1)) != player and not known.call(int(j["s"])):
			continue
		nj += 1
		var o := state.get_empire(int(j["o"]))
		jb.body.add_child(UiTheme.paragraph("%s%s" % [job_text(state, j), (", à %s" % o.short_name()) if o != null else ""], 760.0, 13))
	if nj == 0:
		jb.body.add_child(UiTheme.dim("Aucun pour l'instant.", 13))

	var wb := Widgets.Block.new("Mondes façonnés")
	col.add_child(wb)
	var nw := 0
	for k in wk:
		var pid := int(k)
		var p := state.galaxy.get_planet(pid)
		if WorldForge.holder(state, pid) != player and not known.call(p.system_id):
			continue
		nw += 1
		var o := state.get_empire(WorldForge.holder(state, pid))
		wb.body.add_child(UiTheme.paragraph("%s%s" % [world_text(state, pid), (", à %s" % o.short_name()) if o != null and not o.is_npc() else ""], 760.0, 13))
	if nw == 0:
		wb.body.add_child(UiTheme.dim("Aucun pour l'instant.", 13))

	var rel := WorldForge.sub(state, "relics")
	if not rel.is_empty():
		var rb := Widgets.Block.new("Mondes-reliquaires des Façonneurs")
		col.add_child(rb)
		var nr := 0
		var rk := rel.keys()
		rk.sort_custom(func(a: Variant, b: Variant) -> bool: return int(a) < int(b))
		for k in rk:
			var pid := int(k)
			var p := state.galaxy.get_planet(pid)
			if WorldForge.is_gone(state, pid) or not known.call(p.system_id):
				continue
			nr += 1
			var st := "scellé" if WorldForgeWorld.is_relic(state, pid) else ("vivant" if WorldForgeWorld.is_living(state, pid) or LivingWorlds.is_living(state, pid) else "ouvert")
			rb.body.add_child(UiTheme.paragraph("%s, autour de %s : %s" % [WorldForgeWorld.relic_name(state, pid), state.galaxy.systems[p.system_id].system_name, st], 760.0, 13))
		if nr == 0:
			rb.body.add_child(UiTheme.dim("Aucun repéré pour l'instant : explorez.", 13))

	var cb := Widgets.Block.new("Catalogue")
	col.add_child(cb)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 14)
	flow.add_theme_constant_override("v_separation", 14)
	cb.body.add_child(flow)
	var tint := Color(0.6, 0.85, 0.7)
	for op in WorldForge.op_ids():
		var d := WorldForge.op_def(op)
		if bool(d.get("dismantle", false)) and not WorldForge.dismantle_on(state):
			continue
		var open := WorldForge.unlocked(state, player, op)
		var days := "%d à %d j" % [int(d.get("days_base", 0)) + int(d.get("days_per_size", 0)), int(d.get("days_base", 0)) + 5 * int(d.get("days_per_size", 0))] if d.has("days_base") else "%d j" % int(d.get("days", 0))
		var made := WondersUi.catalog_card("forge_" + String(op), tint, WorldForge.op_label(op), "DISPONIBLE" if open else "TECHNOLOGIE MANQUANTE",
				UiTheme.GOOD if open else UiTheme.TEXT_DIM, "%s · %s%s" % [GameData.format_amounts(d.get("cost", {})), days, (" · %d Masse" % int(d["mass"])) if d.has("mass") else ""],
				String(d.get("text", "")), "" if open else "Il manque : %s." % Research.missing_text(state, player, d.get("tech", [])), not open)
		flow.add_child(made[0])
		es.wonder_cards["forge:" + String(op)] = made[0]
	for k in WorldForge.cfg("instant"):
		var d: Dictionary = WorldForge.cfg("instant")[k]
		if k == "belier" and not WorldForge.dismantle_on(state):
			continue
		var made := WondersUi.catalog_card("forge_" + String(k), tint, String(d.get("label", k)), "TIR IMMÉDIAT", Color(0.95, 0.62, 0.3), "", String(d.get("text", "")), "", false)
		flow.add_child(made[0])
		es.wonder_cards["forge:" + String(k)] = made[0]


static func _first_colony(state: GameState, player: int, sid: int) -> int:
	for pid in state.galaxy.systems[sid].planet_ids:
		var c: Colony = state.colonies.get(pid)
		if c != null and c.owner == player and c.is_established():
			return pid
	return -1


## Actions de l'écran Système pour le corps p (une colonie ou non) : chantiers sur ce corps ; sur la
## première colonie du système, les corps nouveaux, la rosette et les commandes.
static func system_actions(state: GameState, player: int, p: Planet, emit: Callable) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not WorldForge.applies(state, player):
		return out
	var sid := p.system_id
	for op in WorldForge.op_ids():
		var d := WorldForge.op_def(op)
		if bool(d.get("new_body", false)) or not WorldForge.unlocked(state, player, op):
			continue
		if WorldForge.site_reason(state, player, op, sid, p.id) != "":
			continue
		var cost := WorldForge.op_cost(state, player, op, sid)
		var act := "start" if not WorldForge.needs_architect(op) else "plan"
		out.append(WondersUi._act(state, SimCommands.forge_act(player, act, {"op": op, "s": sid, "p": p.id}), "Forge des mondes : %s" % WorldForge.op_label(op),
				"%s  »  %d jours" % [GameData.format_amounts(cost), WorldForge.op_days(state, player, op, p.id)],
				("Un Vaisseau-architecte part lancer le chantier.\n\n" if WorldForge.needs_architect(op) else "") + String(d.get("text", "")), emit))
	if int(WorldForge.world(state, p.id).get("eng", 0)) > 0 and WorldForge.holder(state, p.id) == player:
		for to in WorldForgeWorld.move_targets(state, player, p.id):
			out.append(WondersUi._act(state, SimCommands.forge_act(player, "move", {"p": p.id, "t": to}), "Mettre en marche vers %s" % state.galaxy.systems[to].system_name,
					"%d jours" % WorldForge.r_int("move_days", 720), String((WorldForge.cfg("instant").get("deplacer", {}) as Dictionary).get("text", "")), emit))
		for tp in WorldForgeWorld.ram_targets(state, player, p.id):
			out.append(WondersUi._act(state, SimCommands.forge_act(player, "ram", {"p": p.id, "t": tp}), "Bélier planétaire sur %s" % WorldForge.world_name(state, tp),
					"les deux mondes deviennent des cailloux", String((WorldForge.cfg("instant").get("belier", {}) as Dictionary).get("text", "")), emit))
	if p.id != _first_colony(state, player, sid):
		return out
	for op in ["habitat", "sur_mesure"]:
		if not WorldForge.unlocked(state, player, op):
			continue
		var choices: Array = WorldForge.op_def(op).get("choices", [""]) if op == "sur_mesure" else [""]
		for a in choices:
			if WorldForge.site_reason(state, player, op, sid, -1, String(a)) != "":
				continue
			var label := WorldForge.op_label(op) + ((" : %s" % ("type préféré" if String(a) == "prefere" else Megastructures.planet_label(String(a)))) if String(a) != "" else "")
			out.append(WondersUi._act(state, SimCommands.forge_act(player, "plan", {"op": op, "s": sid, "p": -1, "a": String(a)}), "Forge des mondes : %s" % label,
					"%s  »  %d jours" % [GameData.format_amounts(WorldForge.op_cost(state, player, op, sid)), WorldForge.op_days(state, player, op)],
					String(WorldForge.op_def(op).get("text", "")), emit))
	if WorldForge.unlocked(state, player, "rosette") and WorldForgeWorld.rosette_worlds(state, player, sid).size() >= WorldForge.r_int("rosette_min", 3) and not WorldForge.sub(state, "rosettes").has(str(sid)):
		out.append(WondersUi._act(state, SimCommands.forge_act(player, "rosette", {"s": sid}), "Former une rosette",
				GameData.format_amounts((WorldForge.cfg("instant").get("rosette", {}) as Dictionary).get("cost", {})), String((WorldForge.cfg("instant").get("rosette", {}) as Dictionary).get("text", "")), emit))
	for seller in WorldForgeWorld.sellers(state, player):
		out.append(WondersUi._act(state, SimCommands.forge_act(player, "order", {"seller": seller, "s": sid, "a": "prefere"}), "Commander un monde à %s" % state.get_empire(seller).short_name(),
				"%s et %d Masse" % [GameData.format_amounts(WorldForgeWorld.order_price(state, seller)), WorldForge.op_mass("sur_mesure")],
				String((WorldForge.cfg("instant").get("commande", {}) as Dictionary).get("text", "")), emit))
	return out
