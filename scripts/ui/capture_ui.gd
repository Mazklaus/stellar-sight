class_name CaptureUi
extends RefCounted
## Prises de guerre côté interface : infobulle de la posture d'abordage et menu des prises d'une flotte
## (remise en état, refonte, démantèlement, revente). Les ordres passent par main._submit.

## Infobulle du bouton « Abordage » : état de la posture et chance estimée contre un croiseur moyen.
static func posture_tip(state: GameState, f: Fleet) -> String:
	if state == null or f == null:
		return ""
	var why := Capture.check_posture(state, f.owner, f.id)
	if why != "":
		return "Abordage indisponible : %s." % why
	var lines: Array[String] = []
	lines.append("Posture d'abordage : %s." % ("ACTIVE" if Capture.posture(state, f) else "inactive"))
	lines.append("Les vaisseaux ennemis tombés sous leur seuil de coque (30 % pour les petits et moyens, 20 % pour les grands, 10 % pour un titan) sont abordés au lieu d'être achevés.")
	lines.append("Troupes à bord : %d (petit 4, moyen 8, grand 16, titan 40 par tentative ; la moitié revient si l'abordage réussit)." % f.troops)
	lines.append("La prise rejoint votre flotte avec 1 à 2 avaries. Le reste est expliqué dans le Codex (« Prises de guerre »).")
	return "\n".join(lines)


## Ouvre le menu des prises de la flotte (ou de tous ses vaisseaux pour le démantèlement).
static func open_prize_menu(main: Node, state: GameState, player: int, f: Fleet) -> void:
	if state == null or f == null or f.owner != player:
		return
	var menu := PopupMenu.new()
	menu.name = "PrizeMenu"
	var cmds: Array[Dictionary] = []
	var any := false
	var seen := {}
	for ship in f.ships:
		if not Capture.is_prize(ship) or seen.has(ship):
			continue
		seen[ship] = true
		any = true
		var avs := Capture.avaries_of(ship)
		menu.add_separator("%s · %d avarie(s)" % [Designs.label(Capture.base_of(ship)), avs.size()])
		if not avs.is_empty():
			_item(menu, cmds, state, player, "repair", f, ship, {}, "Remettre en état (%s)" % GameData.format_amounts(Capture.repair_cost(ship)))
		for to in _refit_targets(state, player, ship):
			_item(menu, cmds, state, player, "refit", f, ship, {"x": to}, "Refondre en %s (%s)" % [Designs.label(to), GameData.format_amounts(Capture.refit_cost(to))])
		_item(menu, cmds, state, player, "scrap", f, ship, {}, "Démanteler (+%s)" % GameData.format_amounts(Capture.scrap_gain(state, player, ship)))
		_item(menu, cmds, state, player, "sell", f, ship, {"x": "market"}, "Vendre au marché (%d énergie)" % Capture.sell_price(state, player, ship, "market"))
		_item(menu, cmds, state, player, "sell", f, ship, {"x": "pirates"}, "Vendre aux pirates (%d énergie)" % Capture.sell_price(state, player, ship, "pirates"))
	if CaptureTomb.system(state) == f.system_id:
		any = true
		menu.add_separator(CaptureTomb.label())
		var why := Capture.check_act(state, player, "tomb", {"fleet": f.id})
		var id := cmds.size()
		cmds.append(SimCommands.cap_act(player, "tomb", {"fleet": f.id}))
		menu.add_item("Aborder (%d troupes)" % Capture.rule("tomb_troops", 60), id)
		if why != "":
			menu.set_item_disabled(menu.get_item_index(id), true)
			menu.set_item_tooltip(menu.get_item_index(id), why)
	if not any:
		menu.add_separator("Aucune prise dans cette flotte")
	menu.id_pressed.connect(func(id: int) -> void:
		if id >= 0 and id < cmds.size() and main.has_method("_submit"):
			main.call("_submit", cmds[id])
		menu.queue_free())
	menu.popup_hide.connect(func() -> void:
		if is_instance_valid(menu):
			menu.queue_free.call_deferred())
	main.add_child(menu)
	menu.popup_centered()


static func _item(menu: PopupMenu, cmds: Array[Dictionary], state: GameState, player: int, act: String, f: Fleet, ship: String, extra: Dictionary, text: String) -> void:
	var d := {"fleet": f.id, "ship": ship}
	d.merge(extra)
	var why := Capture.check_act(state, player, act, d)
	var id := cmds.size()
	cmds.append(SimCommands.cap_act(player, act, d))
	menu.add_item(text, id)
	var idx := menu.get_item_index(id)
	if why != "":
		menu.set_item_disabled(idx, true)
		menu.set_item_tooltip(idx, why)


## Jusqu'à trois de vos modèles de même taille, les plus récents d'abord.
static func _refit_targets(state: GameState, player: int, ship: String) -> Array[String]:
	var out: Array[String] = []
	var size := Combat.ship_size(ship)
	var ids := Designs.buildable_ids(state, player)
	for k in range(ids.size() - 1, -1, -1):
		if Combat.ship_size(ids[k]) == size:
			out.append(ids[k])
			if out.size() >= 3:
				break
	return out


# --- Chantier : prises, butin et rétro-ingénierie (prop. 44, 45) ------------------------------------

static func signature(state: GameState, player: int) -> String:
	if not Capture.full(state):
		return ""
	return "%d|%d|%d|%d" % [prizes_of(state, player).size(), CaptureLore.pending_loot(state, player).size(),
			CaptureLore.analyses_of(state, player).size(), CaptureLore.copies_of(state, player).size()]


## Prises en service : [[flotte, vaisseau]...].
static func prizes_of(state: GameState, player: int) -> Array:
	var out: Array = []
	for f in Fleets.empire_fleets(state, player):
		for s in f.ships:
			if Capture.is_prize(s):
				out.append([f, s])
	return out


static func shipyard_block(state: GameState, player: int, side: VBoxContainer, emit: Callable) -> void:
	if not Capture.full(state):
		return
	side.add_child(UiTheme.section("Prises de guerre"))
	var pr := prizes_of(state, player)
	if pr.is_empty():
		side.add_child(UiTheme.dim("Aucune prise en service. Posture d'abordage : bouton ABORDAGE de la flotte.", 13))
	for pair in pr:
		var f: Fleet = pair[0]
		var s := String(pair[1])
		var avs := Capture.avaries_of(s)
		var names := PackedStringArray()
		for a: Dictionary in avs:
			names.append(String(a["label"]))
		var l := UiTheme.dim("  %s · %s · %s" % [Designs.label(Capture.base_of(s)), f.fleet_name,
				("%d avarie(s)" % avs.size()) if not avs.is_empty() else "remise en état"], 13)
		l.tooltip_text = "\n".join(names) + ("\n" if not names.is_empty() else "") + "Remise en état, refonte, démantèlement, revente : bouton PRISES de la flotte, à l'arrêt dans un de vos systèmes."
		l.mouse_filter = Control.MOUSE_FILTER_PASS
		side.add_child(l)
	var loot := CaptureLore.pending_loot(state, player)
	side.add_child(UiTheme.section("Butin de bataille (%d)" % loot.size()))
	var auto := CheckBox.new()
	auto.text = "Politique d'épaves automatique"
	auto.button_pressed = bool(CaptureLore.loot_of(state, player).get("auto", false))
	auto.tooltip_text = "Coché : plus de butin à trier, la politique d'épaves décide (garder les coques presque intactes, sinon étudier ou démanteler)."
	auto.toggled.connect(func(on: bool) -> void: emit.call(SimCommands.cap_act(player, "loot", {"x": "auto", "on": on})))
	side.add_child(auto)
	for i in loot.size():
		var it: Dictionary = loot[i]
		var s := String(it["s"])
		var row := HBoxContainer.new()
		var l := UiTheme.dim("%s · %d av. · %s (j. %d)" % [Designs.label(Capture.base_of(s)), Capture.avarie_count(s),
				state.galaxy.systems[int(it["sid"])].system_name, int(it["until"]) - state.tick], 13)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.clip_text = true
		row.add_child(l)
		for pair in [["keep", "Garder", "Remettre en service (à moitié de structure, avec ses avaries)."],
				["scrap", "Démonter", "Démanteler : matériaux."], ["study", "Étudier", "Rétro-ingénierie renforcée (25 %, 3 technologies au plus)."]]:
			var b := Button.new()
			b.text = String(pair[1])
			b.focus_mode = Control.FOCUS_NONE
			var why := Capture.check_act(state, player, "loot", {"i": i, "x": pair[0]})
			b.disabled = why != ""
			b.tooltip_text = String(pair[2]) + (("\n" + why) if why != "" else "")
			var cmd := SimCommands.cap_act(player, "loot", {"i": i, "x": pair[0]})
			b.pressed.connect(func() -> void: emit.call(cmd))
			row.add_child(b)
		side.add_child(row)
	# Politique d'épaves (prop. 23).
	side.add_child(UiTheme.section("Politique d'épaves"))
	var pol := HBoxContainer.new()
	for p: Dictionary in Capture.data().get("policies", []):
		var b := Button.new()
		b.text = String(p["label"])
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.set_pressed_no_signal(CaptureLore.policy(state, player) == String(p["id"]))
		var why := CaptureLore.check_policy(state, player, String(p["id"]))
		b.disabled = why != ""
		b.tooltip_text = String(p["text"]) + (("\n" + why) if why != "" else "")
		var cmd := SimCommands.cap_act(player, "policy", {"x": String(p["id"])})
		b.pressed.connect(func() -> void: emit.call(cmd))
		pol.add_child(b)
	side.add_child(pol)
	# Redditions (prop. 11, 42, 47) : accepter ou refuser celles de l'ennemi.
	side.add_child(UiTheme.section("Redditions ennemies"))
	var sur := HBoxContainer.new()
	for pair in [["accept", "Accepter", "Les vaisseaux qui se rendent deviennent des prises."],
			["refuse", "Refuser", "On les achève. Crime de guerre si une Convention des prises est votée ; le credo Honneur le supporte mal."]]:
		var b := Button.new()
		b.text = String(pair[1])
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.set_pressed_no_signal(Capture.surrender_policy(state, player) == String(pair[0]))
		b.tooltip_text = String(pair[2])
		var cmd := SimCommands.cap_act(player, "surrender", {"x": String(pair[0])})
		b.pressed.connect(func() -> void: emit.call(cmd))
		sur.add_child(b)
	side.add_child(sur)
	# Rétro-ingénierie (prop. 29 à 32).
	side.add_child(UiTheme.section("Rétro-ingénierie"))
	var ana := CaptureLore.analyses_of(state, player)
	if ana.is_empty():
		side.add_child(UiTheme.dim("Aucun modèle ennemi analysé. Chaque épave étudiée d'un modèle donne +5 % de dégâts contre lui (jusqu'à +15 %).", 13))
	var keys := ana.keys()
	keys.sort()
	for k in keys:
		side.add_child(UiTheme.dim("  Analyse : %s  +%d %% de dégâts" % [Designs.label(String(k)), int(ana[k])], 13))
	var st: Dictionary = Capture.sub(state, "studies").get(str(player), {})
	var hk := st.keys()
	hk.sort()
	for h in hk:
		var done := CaptureLore.has_copy(state, player, String(h))
		side.add_child(UiTheme.dim("  Coque étrangère : %s  %s" % [String(Designs.hull(String(h)).get("label", h)),
				"copie débloquée" if done else "%d / %d études" % [int(st[h]), Capture.rule("copy_studies", 3)]], 13))
	side.add_child(UiTheme.dim("Épaves étudiées : %d · récoltées : %d matériaux" % [Capture.stat(state, player, "studied"), Capture.stat(state, player, "salvaged")], 12))


# --- Rapport de bataille : prises et épaves (prop. 43) ----------------------------------------------

static func report_text(r: Dictionary, winner: int, viewer: int) -> String:
	var out := ""
	var boards := 0
	var taken := 0
	for dl: Dictionary in r.get("log", []):
		for bd: Array in dl.get("boards", []):
			boards += 1
			taken += int(bd[2])
	if boards > 0:
		out += "\nAbordages : %d tentative(s), %d prise(s)." % [boards, taken]
	var cl: Dictionary = r.get("capture_lore", {})
	if cl.is_empty() or not (winner == viewer or viewer < 0):
		return out
	var rec: Array = cl.get("recovered", [])
	if not rec.is_empty():
		var names := PackedStringArray()
		for s in rec:
			names.append(Designs.label(Capture.base_of(String(s))))
		out += "\nÉpaves récupérables (Butin de bataille) : %s." % ", ".join(names)
	var learned: Array = cl.get("learned", [])
	if not learned.is_empty():
		out += "\nRétro-ingénierie : %s." % "; ".join(PackedStringArray(learned))
	if int(cl.get("mats", 0)) > 0:
		out += "\nFerraille récupérée : %d matériaux." % int(cl["mats"])
	return out
