class_name FleetsScreen
extends RefCounted
## Onglet Flottes du domaine Forces (refonte, C12) : toutes les flottes de l'empire en tableau triable
## (composition, puissance, coque, position, ordre, amiral, autonomie). La flotte choisie se renomme,
## fusionne, se scinde et se met à niveau depuis l'écran. Construit dans les conteneurs d'EmpireScreens.
##
## Bêta-test (3.1) : « Nouvelle flotte » crée une flotte vide (une formation, voir Musters) ; on y
## commande des vaisseaux, répartis entre les chantiers libres, qui la rejoignent en sortant. Une flotte
## existante reçoit des renforts de la même façon. Les formations encore vides ont leur ligne au tableau.

const COLOR := Color(0.93, 0.5, 0.42)
## Sélection d'une formation encore vide : MUSTER_BASE - identifiant (les flottes gardent leur id >= 0).
const MUSTER_BASE := -1000
## Clé de tri, libellé, largeur.
const COLUMNS := [["name", "Flotte", 160.0], ["ships", "Composition", 180.0], ["power", "Puissance", 80.0], ["hull", "Coque", 56.0],
		["place", "Position", 140.0], ["order", "Ordre", 140.0], ["admiral", "Amiral", 130.0], ["supply", "Autonomie", 76.0]]


## Ce que fait la flotte, en clair.
static func order_text(state: GameState, f: Fleet) -> String:
	if f.refit_left > 0:
		return "Mise à niveau (%d j)" % f.refit_left
	if state.battles.has(f.system_id) and not f.is_moving() and Espionage.battle_sides(state.battles[f.system_id]).has(f.owner):
		return "Au combat"
	if f.is_exploring():
		return "Exploration auto"
	if f.is_patrolling():
		return "Patrouille"
	var j := Musters.joining(state, f.id)
	if j >= 0 and state.fleets.has(j):
		return "Rejoint %s" % (state.fleets[j] as Fleet).fleet_name
	if f.is_moving():
		return "En route, %d j" % Fleets.eta_days(state, f)
	if f.is_guarding():
		return "Garde"
	return "Attend des ordres" if f.is_idle() else "À l'arrêt"


## Une ligne par flotte de l'empire : {id, name, ships, count, power, hull, place, order, admiral, supply}.
static func rows(state: GameState, player: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for fid in state.sorted_fleet_ids():
		var f: Fleet = state.fleets[fid]
		if f.owner != player:
			continue
		var sys := state.galaxy.systems[f.system_id].system_name
		var place := sys
		if f.is_moving():
			place = "vers %s" % state.galaxy.systems[f.destination()].system_name
		var h := Heroes.at_post(state, "fleet", f.id, player)
		@warning_ignore("integer_division")
		var hull := f.total_hp() * 100 / maxi(1, f.total_max_hp())
		var comp := Fleets.composition(f)
		var mid := Musters.for_fleet(state, fid)
		if mid >= 0:
			var rec := Musters.get_rec(state, mid)
			var more := (rec["q"] as Array).size() + (rec["y"] as Dictionary).size()
			if more > 0:
				comp += ", +%d en commande" % more
		out.append({"id": fid, "name": f.fleet_name, "ships": comp, "count": f.ships.size(), "power": Capture.fleet_power(f),
				"hull": hull, "place": place, "order": order_text(state, f), "admiral": String(h.get("name", "")),
				"supply": Logistics.reserves(state, f) if Logistics.active(state) else -1})
	# Flottes créées dans l'onglet et encore vides (formations sans vaisseau).
	for m: Dictionary in Musters.of_empire(state, player):
		var rec: Dictionary = m["rec"]
		if Musters.has_fleet(state, rec):
			continue
		var n := (rec["q"] as Array).size() + (rec["y"] as Dictionary).size()
		out.append({"id": MUSTER_BASE - int(m["id"]), "name": String(rec["n"]), "ships": ("%d en commande" % n) if n > 0 else "Vide",
				"count": 0, "power": 0, "hull": 100, "place": state.galaxy.systems[int(rec["s"])].system_name,
				"order": "En formation", "admiral": "", "supply": -1})
	return out


## Identifiant de formation d'une ligne de formation vide (-1 pour une flotte).
static func muster_of_row(row_id: int) -> int:
	return MUSTER_BASE - row_id if row_id <= MUSTER_BASE else -1


## Valeur de tri d'une ligne pour une colonne.
static func sort_key(r: Dictionary, key: String) -> Variant:
	match key:
		"ships":
			return int(r["count"])
		"power", "hull", "supply":
			return int(r[key])
	return String(r[key]).to_lower()


static func sorted_rows(state: GameState, player: int, key: String, desc: bool) -> Array[Dictionary]:
	var list := rows(state, player)
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ka: Variant = sort_key(a, key)
		var kb: Variant = sort_key(b, key)
		if ka == kb:
			return int(a["id"]) < int(b["id"])
		return ka > kb if desc else ka < kb)
	return list


static func signature(es: EmpireScreens) -> String:
	@warning_ignore("integer_division")
	return "%s|%s|%s|%d|%d|%s|%s" % [str(rows(es._state, es._player)), es.fleets_sort, str(es.fleets_sort_desc), es.fleets_selected, es._state.tick / 30,
			str(Musters.of_empire(es._state, es._player)), str(Musters.auto_join(es._state, es._player))]


static func build(es: EmpireScreens) -> void:
	var state := es._state
	var player := es._player
	es._fleets_sig = signature(es)
	es.fleets_buttons.clear()
	var list := sorted_rows(state, player, es.fleets_sort, es.fleets_sort_desc)
	var ids: Array[int] = []
	var ships := 0
	var power := 0
	var idle := 0
	for r: Dictionary in list:
		ids.append(int(r["id"]))
		ships += int(r["count"])
		power += int(r["power"])
		if String(r["order"]) == "Attend des ordres":
			idle += 1
	if not ids.has(es.fleets_selected):
		es.fleets_selected = ids[0] if not ids.is_empty() else -1

	# Colonne de gauche.
	es._side_header("screen_fleets", "Flottes", COLOR, "faction")
	var g := es._grid()
	es._side_box.add_child(g)
	es._key_value(g, "Flottes", str(list.size()))
	es._key_value(g, "Vaisseaux", str(ships))
	es._key_value(g, "Puissance totale", str(power))
	var iv := es._key_value(g, "Sans ordres", str(idle))
	if idle > 0:
		iv.add_theme_color_override("font_color", UiTheme.WARN)
	var up := Fleets.upkeep(state, player)
	if not up.is_empty():
		es._key_value(g, "Entretien", GameData.format_amounts(up) + " / mois")
	es._side_box.add_child(HSeparator.new())
	_side_new_fleet(es)
	es._side_box.add_child(HSeparator.new())
	es._side_box.add_child(UiTheme.paragraph("Un clic sur un en-tête trie le tableau, un second inverse l'ordre. Un clic sur une flotte ouvre ses réglages en bas ; « Voir sur la carte » y mène.", EmpireScreens.SIDE_WIDTH - 24.0, 12))

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 18)
	es._content.add_child(col)
	var tb := Widgets.Block.new("Vos flottes")
	tb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tb.body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(tb)
	var heads := HBoxContainer.new()
	heads.add_theme_constant_override("separation", 8)
	tb.body.add_child(heads)
	for c: Array in COLUMNS:
		var key := String(c[0])
		var hb := Button.new()
		hb.flat = true
		hb.focus_mode = Control.FOCUS_NONE
		hb.alignment = HORIZONTAL_ALIGNMENT_LEFT
		hb.custom_minimum_size = Vector2(float(c[2]), 0)
		hb.add_theme_font_override("font", UiTheme.caps_font())
		hb.add_theme_font_size_override("font_size", 12)
		hb.text = String(c[1]).to_upper() + ((" ▼" if es.fleets_sort_desc else " ▲") if es.fleets_sort == key else "")
		hb.add_theme_color_override("font_color", UiTheme.ACCENT if es.fleets_sort == key else UiTheme.TEXT_DIM)
		hb.pressed.connect(func() -> void:
			if es.fleets_sort == key:
				es.fleets_sort_desc = not es.fleets_sort_desc
			else:
				es.fleets_sort = key
				es.fleets_sort_desc = key in ["power", "ships", "hull"]
			es.show_screen("fleets"))
		heads.add_child(hb)
		es.fleets_buttons["sort:" + key] = hb
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tb.body.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 3)
	scroll.add_child(box)
	if list.is_empty():
		box.add_child(UiTheme.dim("Aucune flotte. « Nouvelle flotte », à gauche, en crée une à remplir.", 14))
	for r: Dictionary in list:
		var fid := int(r["id"])
		var b := es._row_button(34)
		b.set_pressed_no_signal(fid == es.fleets_selected)
		b.pressed.connect(func() -> void:
			es.fleets_selected = fid
			es.show_screen("fleets"))
		var row := HBoxContainer.new()
		row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		row.offset_left = 8
		row.add_theme_constant_override("separation", 8)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(row)
		for c: Array in COLUMNS:
			var key := String(c[0])
			var l := Label.new()
			l.custom_minimum_size = Vector2(float(c[2]), 0)
			l.clip_text = true
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE
			l.add_theme_font_size_override("font_size", 14)
			if key == "ships":
				b.tooltip_text = String(r["ships"])
			match key:
				"hull":
					l.text = "%d %%" % int(r["hull"])
					l.add_theme_color_override("font_color", UiTheme.BAD if int(r["hull"]) < 50 else (UiTheme.WARN if int(r["hull"]) < 90 else UiTheme.TEXT))
				"supply":
					l.text = ("%d j" % int(r["supply"])) if int(r["supply"]) >= 0 else "—"
				"admiral":
					l.text = String(r["admiral"]) if String(r["admiral"]) != "" else "—"
				"order":
					l.text = String(r["order"])
					if l.text == "Attend des ordres":
						l.add_theme_color_override("font_color", UiTheme.WARN)
					elif l.text == "En formation" or l.text.begins_with("Rejoint"):
						l.add_theme_color_override("font_color", UiTheme.ACCENT)
					elif l.text == "Au combat":
						l.add_theme_color_override("font_color", UiTheme.BAD)
				"power":
					l.text = str(r[key]) if fid > MUSTER_BASE else "—"
				_:
					l.text = str(r[key])
			if key == "name":
				l.add_theme_font_size_override("font_size", 15)
			elif key == "power":
				l.theme_type_variation = &"Numbers"
			row.add_child(l)
		box.add_child(b)
		es.fleets_buttons["row:%d" % fid] = b
	if es.fleets_selected >= 0:
		col.add_child(_detail(es, state.fleets[es.fleets_selected]))
	elif es.fleets_selected <= MUSTER_BASE:
		col.add_child(_muster_detail(es, muster_of_row(es.fleets_selected)))


static func _detail(es: EmpireScreens, f: Fleet) -> Control:
	var state := es._state
	var player := es._player
	var blk := Widgets.Block.new(f.fleet_name)
	var line := HFlowContainer.new()
	line.add_theme_constant_override("h_separation", 10)
	line.add_theme_constant_override("v_separation", 8)
	blk.body.add_child(line)
	var see := Button.new()
	see.theme_type_variation = &"PrimaryButton"
	see.focus_mode = Control.FOCUS_NONE
	see.text = "VOIR SUR LA CARTE"
	var fid := f.id
	see.pressed.connect(func() -> void: es.fleet_requested.emit(fid))
	line.add_child(see)
	es.fleets_buttons["see"] = see
	# Renommer.
	var name_edit := LineEdit.new()
	name_edit.text = f.fleet_name
	name_edit.max_length = SimCommands.NAME_MAX_LENGTH
	name_edit.custom_minimum_size = Vector2(220, 0)
	name_edit.tooltip_text = "Nouveau nom de la flotte, puis Entrée."
	var rename := func(t: String) -> void:
		var cmd := SimCommands.rename_fleet(player, fid, t)
		if SimCommands.validate(state, cmd) == "":
			es.command_requested.emit(cmd)
	name_edit.text_submitted.connect(rename)
	line.add_child(name_edit)
	es.fleets_buttons["name"] = name_edit
	var rb := Button.new()
	rb.focus_mode = Control.FOCUS_NONE
	rb.text = "RENOMMER"
	rb.pressed.connect(func() -> void: rename.call(name_edit.text))
	line.add_child(rb)
	# Mettre à niveau.
	var refit := Button.new()
	refit.focus_mode = Control.FOCUS_NONE
	refit.text = "METTRE À NIVEAU"
	var why := Fleets.check_refit(state, player, fid)
	refit.disabled = why != ""
	refit.tooltip_text = why if why != "" else "Remet les vaisseaux au dernier modèle de leur classe, au chantier du système."
	refit.pressed.connect(func() -> void: es.command_requested.emit(SimCommands.refit(player, fid)))
	line.add_child(refit)
	es.fleets_buttons["refit"] = refit
	# Fusionner.
	var merge := OptionButton.new()
	merge.focus_mode = Control.FOCUS_NONE
	merge.add_item("Fusionner avec…")
	var others: Array[int] = []
	for oid in state.sorted_fleet_ids():
		if Fleets.check_merge(state, player, fid, oid) == "":
			others.append(oid)
			merge.add_item((state.fleets[oid] as Fleet).fleet_name)
	merge.disabled = others.is_empty()
	merge.tooltip_text = "Aucune autre flotte à l'arrêt dans le même système." if others.is_empty() else "Verse tous ses vaisseaux dans l'autre flotte."
	merge.item_selected.connect(func(i: int) -> void:
		if i > 0:
			es.command_requested.emit(SimCommands.merge_fleets(player, fid, others[i - 1])))
	line.add_child(merge)
	es.fleets_buttons["merge"] = merge
	# Scinder.
	var split := OptionButton.new()
	split.focus_mode = Control.FOCUS_NONE
	split.add_item("Détacher un vaisseau…")
	var classes: Array[String] = []
	for sid in f.ships:
		if not classes.has(sid) and Fleets.check_split(state, player, fid, sid) == "":
			classes.append(sid)
			split.add_item("%s (%d)" % [String(GameData.ship(sid).get("label", sid)), f.count(sid)])
	split.disabled = classes.is_empty()
	split.tooltip_text = Fleets.check_split(state, player, fid, f.ships[0]) if classes.is_empty() and not f.ships.is_empty() else "Le vaisseau détaché forme une nouvelle flotte dans le même système."
	split.item_selected.connect(func(i: int) -> void:
		if i > 0:
			es.command_requested.emit(SimCommands.split_fleet(player, fid, classes[i - 1])))
	line.add_child(split)
	es.fleets_buttons["split"] = split
	# Renforts (bêta-test, 3.1) : vaisseaux commandés pour cette flotte.
	blk.body.add_child(_order_block(es, Musters.for_fleet(state, fid), fid))
	# Composition détaillée.
	var comp := HFlowContainer.new()
	comp.add_theme_constant_override("h_separation", 18)
	blk.body.add_child(comp)
	for r: Dictionary in Hud.fleet_rows(f):
		@warning_ignore("integer_division")
		var l := UiTheme.dim("%d × %s, coque %d %%" % [int(r["n"]), String(r["label"]), int(r["hp"]) * 100 / maxi(1, int(r["max"]))], 13)
		comp.add_child(l)
	return blk


# --- Flottes en formation (bêta-test, 3.1) ------------------------------------------------------

## Colonne de gauche : créer une flotte vide, et le réglage des vaisseaux neufs qui rejoignent.
static func _side_new_fleet(es: EmpireScreens) -> void:
	var state := es._state
	var player := es._player
	es._side_box.add_child(UiTheme.section("Former une flotte"))
	es._side_box.add_child(UiTheme.paragraph("Créez la flotte, même vide, puis commandez-lui des vaisseaux. Chaque commande part au chantier libre le plus proche ; le vaisseau terminé rejoint la flotte de lui-même.", EmpireScreens.SIDE_WIDTH - 24.0, 12))
	var nb := Button.new()
	nb.theme_type_variation = &"PrimaryButton"
	nb.focus_mode = Control.FOCUS_NONE
	nb.text = "NOUVELLE FLOTTE"
	nb.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var home := default_place(state, player)
	var cmd := SimCommands.muster_act(player, "new", home, -1, next_name(state, player))
	var why := SimCommands.validate(state, cmd)
	nb.disabled = why != ""
	nb.tooltip_text = why if why != "" else "Une flotte vide, rassemblée à %s. Nom et point de rassemblement se changent ensuite." % state.galaxy.systems[home].system_name
	nb.pressed.connect(func() -> void:
		es.fleets_selected = MUSTER_BASE - Musters.next_id(state)
		es.command_requested.emit(cmd))
	es._side_box.add_child(nb)
	es.fleets_buttons["new"] = nb
	var auto := CheckBox.new()
	auto.text = "Les vaisseaux armés neufs rejoignent la flotte à quai"
	auto.focus_mode = Control.FOCUS_NONE
	auto.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	auto.custom_minimum_size = Vector2(EmpireScreens.SIDE_WIDTH - 24.0, 0)
	auto.button_pressed = Musters.auto_join(state, player)
	auto.tooltip_text = "Hors commande, un vaisseau armé qui sort d'un chantier (ou arrive au point de ralliement) se fond dans la flotte armée à l'arrêt sur place. Décoché : il forme sa propre flotte, comme avant."
	auto.toggled.connect(func(on: bool) -> void: es.command_requested.emit(SimCommands.muster_act(player, "auto", 1 if on else 0)))
	es._side_box.add_child(auto)
	es.fleets_buttons["auto"] = auto


## Point de rassemblement par défaut : le point de ralliement s'il est à vous, sinon la capitale.
static func default_place(state: GameState, player: int) -> int:
	var e := state.get_empire(player)
	if e == null:
		return -1
	if e.rally_system >= 0 and state.system_owner(e.rally_system) == player:
		return e.rally_system
	var cap := state.galaxy.get_planet(e.capital_planet)
	return cap.system_id if cap != null else -1


## Nom proposé : « Flotte de réserve », puis la première « Ne flotte » libre.
static func next_name(state: GameState, player: int) -> String:
	var used := {}
	for f: Fleet in state.fleets.values():
		if f.owner == player:
			used[f.fleet_name] = true
	for m: Dictionary in Musters.of_empire(state, player):
		used[String(m["rec"]["n"])] = true
	for i in range(1, 100):
		var n := "%s flotte" % _ordinal(i)
		if not used.has(n):
			return n
	return "Nouvelle flotte"


static func _ordinal(i: int) -> String:
	return "1re" if i == 1 else "%de" % i


## Fiche d'une flotte encore vide : nom, point de rassemblement, commande, dissolution.
static func _muster_detail(es: EmpireScreens, mid: int) -> Control:
	var state := es._state
	var player := es._player
	var rec := Musters.get_rec(state, mid)
	var blk := Widgets.Block.new(String(rec.get("n", "")))
	if rec.is_empty():
		return blk
	var line := HFlowContainer.new()
	line.add_theme_constant_override("h_separation", 10)
	line.add_theme_constant_override("v_separation", 8)
	blk.body.add_child(line)
	var name_edit := LineEdit.new()
	name_edit.text = String(rec["n"])
	name_edit.max_length = Musters.NAME_MAX
	name_edit.custom_minimum_size = Vector2(220, 0)
	name_edit.tooltip_text = "Nom de la flotte, puis Entrée."
	var rename := func(t: String) -> void:
		var cmd := SimCommands.muster_act(player, "rename", mid, -1, t)
		if SimCommands.validate(state, cmd) == "":
			es.command_requested.emit(cmd)
	name_edit.text_submitted.connect(rename)
	line.add_child(name_edit)
	es.fleets_buttons["muster_name"] = name_edit
	var rb := Button.new()
	rb.focus_mode = Control.FOCUS_NONE
	rb.text = "RENOMMER"
	rb.pressed.connect(func() -> void: rename.call(name_edit.text))
	line.add_child(rb)
	var place := OptionButton.new()
	place.focus_mode = Control.FOCUS_NONE
	place.tooltip_text = "Point de rassemblement : le premier vaisseau terminé s'y rend, les suivants le rejoignent."
	var sids: Array[int] = []
	for s in state.galaxy.systems:
		if state.system_owner(s.id) == player:
			sids.append(s.id)
			place.add_item("Rassemblement : %s" % s.system_name)
			if s.id == int(rec["s"]):
				place.selected = sids.size() - 1
	place.item_selected.connect(func(i: int) -> void:
		var cmd := SimCommands.muster_act(player, "place", mid, sids[i])
		if SimCommands.validate(state, cmd) == "":
			es.command_requested.emit(cmd))
	line.add_child(place)
	es.fleets_buttons["muster_place"] = place
	var drop := Button.new()
	drop.focus_mode = Control.FOCUS_NONE
	drop.text = "DISSOUDRE"
	drop.tooltip_text = "Annule la commande. Un vaisseau déjà au chantier sort quand même, seul."
	drop.pressed.connect(func() -> void:
		es.fleets_selected = -1
		es.command_requested.emit(SimCommands.muster_act(player, "drop", mid)))
	line.add_child(drop)
	es.fleets_buttons["muster_drop"] = drop
	blk.body.add_child(_order_block(es, mid, -1))
	return blk


## Commande d'une formation : une ligne par classe que l'empire sait construire, avec le nombre en
## attente et en chantier, et les boutons + et −. mid = -1 et fid >= 0 : flotte sans commande encore
## (le premier + crée la commande de renforts).
static func _order_block(es: EmpireScreens, mid: int, fid: int) -> Control:
	var state := es._state
	var player := es._player
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var rec := Musters.get_rec(state, mid) if mid >= 0 else {}
	box.add_child(UiTheme.section("Renforts" if fid >= 0 else "Commande"))
	var q: Array = rec.get("q", [])
	var y: Array[String] = []
	if not rec.is_empty():
		y = Musters.building(rec)
	var status := ""
	if rec.is_empty() or (q.is_empty() and y.is_empty()):
		status = "Rien en commande. Chaque + envoie un vaisseau au chantier libre le plus proche ; il se paie au lancement."
	else:
		status = "%d en chantier, %d en attente." % [y.size(), q.size()]
		var why := Musters.wait_reason(state, mid)
		if why != "":
			status += " La suite attend : %s." % why
	var st := UiTheme.paragraph(status, 640, 13)
	st.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	box.add_child(st)
	es.fleets_buttons["order_status"] = st
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 3)
	box.add_child(grid)
	var ids := Musters.orderable(state, player)
	if ids.is_empty():
		box.add_child(UiTheme.dim("Aucun vaisseau à commander pour l'instant.", 13))
	for ship_id in ids:
		var sd := GameData.ship(ship_id)
		var l := Label.new()
		l.text = String(sd.get("label", ship_id))
		l.custom_minimum_size = Vector2(190, 0)
		l.clip_text = true
		l.mouse_filter = Control.MOUSE_FILTER_STOP
		l.tooltip_text = String(sd.get("description", ""))
		grid.add_child(l)
		var info := UiTheme.dim("%s, %d j%s" % [GameData.format_amounts(Fleets.ship_cost(state, player, ship_id)), Fleets.ship_days(state, player, ship_id),
				(", puissance %d" % Combat.ship_strength(ship_id)) if Combat.is_military(ship_id) else ""], 12)
		info.custom_minimum_size = Vector2(250, 0)
		grid.add_child(info)
		var n_q := q.count(ship_id)
		var n_y := y.count(ship_id)
		var cnt := Label.new()
		cnt.theme_type_variation = &"Numbers"
		cnt.custom_minimum_size = Vector2(70, 0)
		cnt.text = ("%d + %d" % [n_y, n_q]) if n_y > 0 and n_q > 0 else str(n_y + n_q)
		cnt.tooltip_text = "En chantier : %d. En attente d'un chantier : %d." % [n_y, n_q]
		cnt.mouse_filter = Control.MOUSE_FILTER_STOP
		grid.add_child(cnt)
		var plus := Button.new()
		plus.text = "+"
		plus.focus_mode = Control.FOCUS_NONE
		plus.custom_minimum_size = Vector2(34, 0)
		var sid := ship_id
		if mid >= 0:
			var why := SimCommands.validate(state, SimCommands.muster_act(player, "add", mid, -1, sid))
			plus.disabled = why != ""
			plus.tooltip_text = why if why != "" else "Commander un vaisseau de plus."
			plus.pressed.connect(func() -> void: es.command_requested.emit(SimCommands.muster_act(player, "add", mid, -1, sid)))
		else:
			plus.tooltip_text = "Commander un vaisseau de plus pour cette flotte."
			var why := SimCommands.validate(state, SimCommands.muster_act(player, "new", -1, fid, sid))
			plus.disabled = why != ""
			if why != "":
				plus.tooltip_text = why
			plus.pressed.connect(func() -> void: es.command_requested.emit(SimCommands.muster_act(player, "new", -1, fid, sid)))
		grid.add_child(plus)
		es.fleets_buttons["plus:" + sid] = plus
		var minus := Button.new()
		minus.text = "−"
		minus.focus_mode = Control.FOCUS_NONE
		minus.custom_minimum_size = Vector2(34, 0)
		minus.disabled = n_q == 0
		minus.tooltip_text = "Retirer un vaisseau qui attend encore son chantier." if n_q > 0 else "Rien en attente de cette classe (un vaisseau au chantier ne se décommande pas)."
		minus.pressed.connect(func() -> void: es.command_requested.emit(SimCommands.muster_act(player, "sub", mid, -1, sid)))
		grid.add_child(minus)
		es.fleets_buttons["minus:" + sid] = minus
	return box
