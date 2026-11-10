class_name ShipyardScreen
extends VBoxContainer
## Écran Chantier (éditeur de vaisseaux), inspiré de l'écran de conception d'Endless Space 2 :
## à gauche la liste des modèles rangés par coque, au centre la coque et ses emplacements colorés par
## type, à droite les modules qui vont dans l'emplacement choisi, en bas les caractéristiques
## comparées à la version d'avant. Rien n'est modifié dans la partie avant « Enregistrer » : l'écran
## envoie des ordres (SimCommands.save_design, retire_design) comme le reste de l'interface.

signal command_requested(cmd: Dictionary)

const LINE_LABELS := {"screen": "Écran", "line": "Ligne", "rear": "Arrière"}
const TARGET_LABELS := {"nearest": "Au plus proche", "largest": "Les plus gros", "smallest": "Les plus petits", "rear": "Porteurs et arrière"}
const PHASES := ["longue", "moyenne", "courte"]

## Modèle affiché : un identifiant de classe (modèle d'origine), de modèle enregistré, ou "" (brouillon neuf).
var selected := ""
## Brouillon en cours : coque, un module (ou "") par emplacement, nom, rang, priorité de cible.
var draft := {}
## Emplacement choisi (indice dans slots()), -1 = aucun.
var slot_index := -1
## Boutons utiles aux tests : "save", "retire", "auto", "clear" ; modules par identifiant ; modèles par identifiant.
var buttons := {}
var module_buttons := {}
var design_buttons := {}
var hull_buttons := {}

var _state: GameState
var _player := 0
var _side: VBoxContainer
var _name: LineEdit
var _line: OptionButton
var _target: OptionButton
var _hull_view: HullView
var _modules_box: VBoxContainer
var _stats_grid: GridContainer
var _reason: Label
var _title: Label


func setup(state: GameState, player: int, side_box: VBoxContainer, side_width: float, side_height: float) -> void:
	_state = state
	_player = player
	add_theme_constant_override("separation", 10)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Colonne de gauche : modèles par coque, dans une zone qui défile.
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(side_width, side_height)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side_box.add_child(scroll)
	_side = VBoxContainer.new()
	_side.add_theme_constant_override("separation", 3)
	_side.custom_minimum_size = Vector2(side_width - 14.0, 0)
	scroll.add_child(_side)
	_build_main()
	if selected == "" or GameData.ship(selected).is_empty():
		var first := _first_design()
		select_design(first)
	else:
		select_design(selected)


# --- Construction -------------------------------------------------------------------------------

func _build_main() -> void:
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	add_child(top)
	_title = UiTheme.title("", 24)
	_title.custom_minimum_size = Vector2(260, 0)
	top.add_child(_title)
	_name = LineEdit.new()
	_name.placeholder_text = "Nom du modèle"
	_name.max_length = Designs.NAME_MAX
	_name.custom_minimum_size = Vector2(220, 0)
	_name.text_changed.connect(func(t: String) -> void:
		draft["name"] = t
		_refresh_status())
	top.add_child(_name)
	top.add_child(UiTheme.dim("Rang", 13))
	_line = OptionButton.new()
	for k in Designs.LINES:
		_line.add_item(LINE_LABELS[k])
	_line.tooltip_text = "Où le vaisseau se tient en bataille : l'écran encaisse en premier, l'arrière est protégé."
	_line.item_selected.connect(func(i: int) -> void:
		draft["line"] = Designs.LINES[i]
		_refresh_status())
	top.add_child(_line)
	top.add_child(UiTheme.dim("Cible", 13))
	_target = OptionButton.new()
	for k in Designs.TARGETS:
		_target.add_item(TARGET_LABELS[k])
	_target.tooltip_text = "Ce que ses armes visent en priorité. (Appliqué en bataille au prochain lot.)"
	_target.item_selected.connect(func(i: int) -> void:
		draft["target"] = Designs.TARGETS[i]
		_refresh_status())
	top.add_child(_target)

	var mid := HBoxContainer.new()
	mid.add_theme_constant_override("separation", 12)
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(mid)
	_hull_view = HullView.new()
	_hull_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hull_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_hull_view.custom_minimum_size = Vector2(420, 260)
	_hull_view.slot_clicked.connect(_on_slot_clicked)
	mid.add_child(_hull_view)
	var right := PanelContainer.new()
	right.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.PANEL, UiTheme.LINE, 8))
	right.custom_minimum_size = Vector2(300, 0)
	mid.add_child(right)
	var mscroll := ScrollContainer.new()
	mscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(mscroll)
	_modules_box = VBoxContainer.new()
	_modules_box.add_theme_constant_override("separation", 4)
	_modules_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mscroll.add_child(_modules_box)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 16)
	add_child(bottom)
	_stats_grid = GridContainer.new()
	_stats_grid.columns = 8
	_stats_grid.add_theme_constant_override("h_separation", 14)
	_stats_grid.add_theme_constant_override("v_separation", 2)
	_stats_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(_stats_grid)
	var actions := VBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	actions.custom_minimum_size = Vector2(230, 0)
	bottom.add_child(actions)
	for spec: Array in [["save", "Enregistrer le modèle"], ["retire", "Retirer"]]:
		var b := Button.new()
		b.text = spec[1]
		b.focus_mode = Control.FOCUS_NONE
		actions.add_child(b)
		buttons[spec[0]] = b
	(buttons["save"] as Button).pressed.connect(save_draft)
	(buttons["retire"] as Button).pressed.connect(_toggle_retire)
	# « Concevoir pour moi » : le même outil que les IA, au mieux de ce qu'on sait de l'adversaire.
	var auto := MenuButton.new()
	auto.text = "Concevoir pour moi  ▾"
	auto.flat = false
	auto.focus_mode = Control.FOCUS_NONE
	auto.tooltip_text = "Remplit la coque pour un rôle, avec les modules que vous connaissez, en tenant compte des armes et des défenses vues dans vos batailles."
	var roles := Designs.ROLES.keys()
	for i in roles.size():
		auto.get_popup().add_item(String(Designs.ROLES[roles[i]]["label"]), i)
	auto.get_popup().id_pressed.connect(func(i: int) -> void: auto_design_draft(String(roles[i])))
	actions.add_child(auto)
	buttons["auto"] = auto
	_reason = UiTheme.dim("", 13)
	_reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reason.custom_minimum_size = Vector2(230, 0)
	actions.add_child(_reason)


func _fill_side() -> void:
	for c in _side.get_children():
		_side.remove_child(c)
		c.queue_free()
	design_buttons.clear()
	hull_buttons.clear()
	var me := _state.get_empire(_player)
	_side.add_child(UiTheme.section("Modèles"))
	var origins := FactionTraits.ship_ids_for(me.faction_id)
	var retired: Array[Dictionary] = []
	for hid in Designs.hull_ids_for(me.faction_id):
		var h := Designs.hull(hid)
		var head := Button.new()
		head.text = "+  %s" % String(h["label"]).to_upper()
		head.alignment = HORIZONTAL_ALIGNMENT_LEFT
		head.flat = true
		head.focus_mode = Control.FOCUS_NONE
		head.add_theme_font_override("font", UiTheme.caps_font())
		head.add_theme_font_size_override("font_size", 13)
		var techs: Array = h.get("requires_tech", [])
		var known := Research.knows_all(_state, _player, techs)
		head.add_theme_color_override("font_color", UiTheme.ACCENT if known else UiTheme.TEXT_DIM)
		head.tooltip_text = "Nouveau modèle sur une coque de %s (%s)" % [String(h["label"]).to_lower(), _slots_text(hid)]
		if not known:
			head.tooltip_text += "\nTechnologie requise : %s" % Research.missing_text(_state, _player, techs)
		head.pressed.connect(func() -> void: new_draft(hid))
		_side.add_child(head)
		hull_buttons[hid] = head
		for sid in origins:
			if String(GameData.ship(sid).get("hull", "")) == hid:
				_add_design_row(sid, "%s  ·  origine" % String(GameData.ship(sid)["label"]))
		for rec in Designs.designs_of(_state, _player):
			if String(rec["hull"]) != hid:
				continue
			if rec.get("retired", false):
				retired.append(rec)
			else:
				_add_design_row(String(rec["id"]), "%s  ·  v%d" % [rec["name"], int(rec.get("version", 1))])
	if not retired.is_empty():
		_side.add_child(UiTheme.section("Retirés"))
		for rec in retired:
			_add_design_row(String(rec["id"]), "%s  ·  v%d" % [rec["name"], int(rec.get("version", 1))], true)


func _add_design_row(id: String, text: String, dim := false) -> void:
	var b := Button.new()
	b.text = "    " + text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.clip_text = true
	b.set_pressed_no_signal(id == selected)
	b.add_theme_font_size_override("font_size", 14)
	if dim:
		b.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	b.pressed.connect(func() -> void: select_design(id))
	_side.add_child(b)
	design_buttons[id] = b


# --- Actions ------------------------------------------------------------------------------------

## Montre un modèle (classe d'origine ou modèle enregistré) et en fait le brouillon.
func select_design(id: String) -> void:
	selected = id
	var sd := GameData.ship(id)
	var hid := String(sd.get("hull", ""))
	if hid == "":
		new_draft(Designs.hull_ids_for(_state.get_empire(_player).faction_id)[0])
		return
	var custom: bool = sd.get("custom", false)
	draft = {
		"hull": hid,
		"slots": _assign_slots(hid, sd.get("modules", [])),
		"name": String(sd["label"]) if custom else "",
		"line": String(sd.get("line", "line")),
		"target": String(sd.get("target", "nearest")),
	}
	slot_index = -1
	_refresh_all()


## Brouillon vierge sur une coque.
func new_draft(hull_id: String) -> void:
	selected = ""
	draft = {
		"hull": hull_id,
		"slots": _assign_slots(hull_id, []),
		"name": "",
		"line": String(Designs.hull(hull_id).get("line", "line")),
		"target": "nearest",
	}
	slot_index = 0 if not slots().is_empty() else -1
	_refresh_all()


## Emplacements de la coque du brouillon : [{"type", "label"}], dans l'ordre des types de données.
func slots() -> Array[Dictionary]:
	return _slots_of(String(draft.get("hull", "")))


func _slots_of(hid: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var counts: Dictionary = Designs.hull(hid).get("slots", {})
	for t in Designs.slot_types():
		for i in int(counts.get(t, 0)):
			out.append({"type": String(t)})
	return out


## Range une liste de modules dans les emplacements (chacun d'abord dans son type, puis ailleurs).
func _assign_slots(hid: String, modules: Array) -> Array:
	var sl := _slots_of(hid)
	var out := []
	out.resize(sl.size())
	out.fill("")
	var rest: Array = []
	for mid in modules:
		var kind := String(Designs.module(String(mid)).get("slot", ""))
		var placed := false
		for i in sl.size():
			if out[i] == "" and sl[i]["type"] == kind:
				out[i] = String(mid)
				placed = true
				break
		if not placed:
			rest.append(mid)
	for mid in rest:
		var kind := String(Designs.module(String(mid)).get("slot", ""))
		for i in sl.size():
			if out[i] == "" and _accepts(String(sl[i]["type"]), kind, String(mid)):
				out[i] = String(mid)
				break
	return out


## Un emplacement de ce type reçoit-il ce module ? (type accepté et bonne taille de coque, ou
## miniaturisation débloquée par les marques de l'empire.)
func _accepts(slot_type: String, module_kind: String, mid := "") -> bool:
	if mid != "":
		var sizes: Array = Designs.module(mid).get("sizes", [])
		var size := String(Designs.hull(String(draft.get("hull", ""))).get("size", ""))
		if (Designs.extras(_state, _player, String(draft.get("hull", ""))).get(mid, []) as Array).has(slot_type):
			return true
		if not sizes.is_empty() and not sizes.has(size):
			return false
	return (Designs.slot_types().get(slot_type, {}).get("accepts", []) as Array).has(module_kind)


func draft_modules() -> Array:
	var out: Array = []
	for m in draft.get("slots", []):
		if String(m) != "":
			out.append(String(m))
	return out


## Pose un module dans l'emplacement choisi (ou le premier emplacement libre qui l'accepte).
func place_module(mid: String) -> void:
	var kind := String(Designs.module(mid).get("slot", ""))
	var sl := slots()
	var target := slot_index
	if target < 0 or target >= sl.size() or not _accepts(String(sl[target]["type"]), kind, mid):
		target = -1
		for i in sl.size():
			if String(draft["slots"][i]) == "" and _accepts(String(sl[i]["type"]), kind, mid):
				target = i
				break
	if target < 0:
		return
	draft["slots"][target] = mid
	# On avance vers l'emplacement libre suivant du même type, pour poser vite plusieurs modules.
	slot_index = target
	for i in range(target + 1, sl.size()):
		if String(draft["slots"][i]) == "" and sl[i]["type"] == sl[target]["type"]:
			slot_index = i
			break
	_refresh_all()


## Remplit le brouillon avec la conception automatique pour un rôle (qualité la plus haute).
func auto_design_draft(role_id: String) -> void:
	var hid := String(draft.get("hull", ""))
	var spec := Designs.auto_design(_state, _player, hid, role_id, 2)
	draft["slots"] = _assign_slots(hid, spec["modules"])
	draft["line"] = String(spec["line"])
	draft["target"] = String(spec["target"])
	if String(draft.get("name", "")).strip_edges() == "":
		draft["name"] = "%s %s" % [String(Designs.hull(hid).get("label", hid)), String(Designs.ROLES[role_id]["label"]).to_lower()]
	slot_index = -1
	_refresh_all()


func clear_slot(i: int) -> void:
	if i >= 0 and i < (draft.get("slots", []) as Array).size():
		draft["slots"][i] = ""
		slot_index = i
		_refresh_all()


func _on_slot_clicked(i: int, right: bool) -> void:
	if right:
		clear_slot(i)
	else:
		slot_index = i
		_refresh_all()


## Ordre d'enregistrement du brouillon : nouvelle version d'un modèle à soi, sinon nouveau modèle.
func save_spec() -> Dictionary:
	var spec := {
		"name": String(draft.get("name", "")).strip_edges(),
		"hull": String(draft["hull"]),
		"modules": draft_modules(),
		"line": String(draft.get("line", "line")),
		"target": String(draft.get("target", "nearest")),
	}
	if _state.designs.has(selected) and int(_state.designs[selected]["owner"]) == _player and not _state.designs[selected].get("retired", false):
		spec["previous"] = selected
	return spec


func save_draft() -> void:
	var spec := save_spec()
	if Designs.check_save(_state, _player, spec) != "":
		return
	var id := "m%d_%d" % [_player, _state.next_design_id]
	command_requested.emit(SimCommands.save_design(_player, spec))
	if _state.designs.has(id):
		select_design(id)
	else:
		_refresh_all()


func _toggle_retire() -> void:
	if not _state.designs.has(selected):
		return
	var retired: bool = _state.designs[selected].get("retired", false)
	command_requested.emit(SimCommands.retire_design(_player, selected, not retired))
	_refresh_all()


# --- Affichage ----------------------------------------------------------------------------------

func _refresh_all() -> void:
	_fill_side()
	var hid := String(draft.get("hull", ""))
	var h := Designs.hull(hid)
	_title.text = String(h.get("label", hid))
	_name.text = String(draft.get("name", ""))
	_line.select(maxi(0, Designs.LINES.find(String(draft.get("line", "line")))))
	_target.select(maxi(0, Designs.TARGETS.find(String(draft.get("target", "nearest")))))
	_hull_view.show_hull(hid, slots(), draft.get("slots", []), slot_index)
	_fill_modules()
	_fill_stats()
	_refresh_status()


func _fill_modules() -> void:
	for c in _modules_box.get_children():
		_modules_box.remove_child(c)
		c.queue_free()
	module_buttons.clear()
	var hid := String(draft.get("hull", ""))
	var size := String(Designs.hull(hid).get("size", "small"))
	var sl := slots()
	var stype := String(sl[slot_index]["type"]) if slot_index >= 0 and slot_index < sl.size() else ""
	var st_info: Dictionary = Designs.slot_types().get(stype, {})
	_modules_box.add_child(UiTheme.section("Modules  ·  %s" % String(st_info.get("label", "choisissez un emplacement")).to_lower() if stype != "" else "Modules"))
	if stype == "":
		_modules_box.add_child(UiTheme.paragraph("Cliquez un emplacement de la coque pour voir ce qui peut y aller. Clic droit : le vider.", 270, 13))
		return
	for mid in Designs.module_ids():
		var m := Designs.module(mid)
		var kind := String(m.get("slot", ""))
		var mini := Designs.miniaturisation_of(mid)
		var later := not mini.is_empty() and String(mini["slot"]) == stype and (mini.get("sizes", []) as Array).has(size)
		var ok := _accepts(stype, kind, mid)
		if not ok and not later:
			continue
		var b := Button.new()
		b.text = "%s\n%s" % [m.get("label", mid), module_value(mid, size)]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(270, 46)
		b.add_theme_font_size_override("font_size", 13)
		var techs: Array = m.get("requires_tech", [])
		b.tooltip_text = String(m.get("text", ""))
		if not Research.knows_all(_state, _player, techs):
			b.disabled = true
			b.tooltip_text += "\nTechnologie requise : %s" % Research.missing_text(_state, _player, techs)
		if not mini.is_empty() and later:
			b.tooltip_text += "\n%s" % String(mini.get("text", ""))
			if not ok:
				b.disabled = true
		b.pressed.connect(func() -> void: place_module(mid))
		_modules_box.add_child(b)
		module_buttons[mid] = b
	var clear := Button.new()
	clear.text = "Vider l'emplacement"
	clear.focus_mode = Control.FOCUS_NONE
	clear.disabled = String(draft["slots"][slot_index]) == ""
	clear.pressed.connect(func() -> void: clear_slot(slot_index))
	_modules_box.add_child(clear)
	buttons["clear"] = clear


## Effet d'un module sur une coque de cette taille, en une ligne : « Cinétique 12 · +4 j ».
static func module_value(mid: String, size: String) -> String:
	var m := Designs.module(mid)
	var parts := PackedStringArray()
	var weapons: Dictionary = GameData.combat().get("weapons", {})
	for fam in m.get("weapons", {}):
		var v := int(Designs._sized(m["weapons"][fam], size))
		parts.append("%s %d" % [weapons.get(fam, {}).get("short", fam), v])
	var names := {"hp": "coque", "armor": "blindage", "shield": "bouclier", "pd": "antimissile", "pd_fleet": "antimissile de flotte", "shield_fleet": "bouclier de flotte",
			"fleet_speed": "vitesse de la flotte", "speed": "vitesse", "vision": "vision", "troops": "troupes", "siege": "siège"}
	for k in Designs.STATS:
		if m.has(k):
			var v := int(Designs._sized(m[k], size))
			if v != 0:
				parts.append("%s %+d" % [names[k], v])
	var raw: Dictionary = m.get("cost", {})
	var cost: Dictionary = raw.get(size, {}) if raw.has(size) else raw
	if not cost.is_empty():
		parts.append(GameData.format_amounts(cost))
	return "  ·  ".join(parts)


## Dégâts par phase (longue, moyenne, courte) d'une liste d'armes {famille: puissance}.
static func phase_damage(weapons: Dictionary) -> Array[int]:
	var out: Array[int] = [0, 0, 0]
	var table: Dictionary = GameData.combat().get("weapons", {})
	for fam in weapons:
		var eff: Array = table.get(fam, {}).get("eff", [0, 0, 0])
		for i in 3:
			@warning_ignore("integer_division")
			out[i] += int(weapons[fam]) * int(eff[i]) / 100
	return out


## Caractéristiques du brouillon, et celles de la référence (le modèle affiché tel qu'enregistré).
func draft_stats() -> Dictionary:
	return Designs.compute(String(draft.get("hull", "")), draft_modules())


func _fill_stats() -> void:
	for c in _stats_grid.get_children():
		_stats_grid.remove_child(c)
		c.queue_free()
	var now := draft_stats()
	var ref: Dictionary = GameData.ship(selected) if selected != "" else {}
	var dmg := phase_damage(now.get("weapons", {}))
	var rdmg := phase_damage(ref.get("weapons", {})) if not ref.is_empty() else dmg
	var rows := [
		["Coque", int(now.get("hp", 0)), int(ref.get("hp", now.get("hp", 0)))],
		["Blindage", int(now.get("armor", 0)), int(ref.get("armor", now.get("armor", 0)))],
		["Bouclier", int(now.get("shield", 0)), int(ref.get("shield", now.get("shield", 0)))],
		["Antimissile", int(now.get("pd", 0)) + int(now.get("pd_fleet", 0)), int(ref.get("pd", now.get("pd", 0))) + int(ref.get("pd_fleet", now.get("pd_fleet", 0)))],
		["Dégâts longue", dmg[0], rdmg[0]],
		["Dégâts moyenne", dmg[1], rdmg[1]],
		["Dégâts courte", dmg[2], rdmg[2]],
		["Vitesse", int(now.get("speed", 0)), int(ref.get("speed", now.get("speed", 0)))],
		["Troupes", int(now.get("troops", 0)), int(ref.get("troops", now.get("troops", 0)))],
		["Siège", int(now.get("siege", 0)), int(ref.get("siege", now.get("siege", 0)))],
		["Durée (j)", int(now.get("days", 1)), int(ref.get("days", now.get("days", 1)))],
	]
	for r: Array in rows:
		var k := UiTheme.dim(String(r[0]), 13)
		_stats_grid.add_child(k)
		var v := Label.new()
		var diff := int(r[1]) - int(r[2])
		v.text = str(r[1]) + ("  (%+d)" % diff if diff != 0 else "")
		v.add_theme_font_override("font", UiTheme.numbers_font())
		v.add_theme_font_size_override("font_size", 14)
		var better := diff > 0 if String(r[0]) != "Durée (j)" else diff < 0
		if diff != 0:
			v.add_theme_color_override("font_color", UiTheme.GOOD if better else UiTheme.BAD)
		_stats_grid.add_child(v)
	_stats_grid.add_child(UiTheme.dim("Coût", 13))
	var cost := Label.new()
	cost.text = GameData.format_amounts(now.get("cost", {}))
	cost.add_theme_font_size_override("font_size", 14)
	_stats_grid.add_child(cost)


func _refresh_status() -> void:
	var spec := save_spec()
	var why := Designs.check_save(_state, _player, spec)
	var save_b: Button = buttons["save"]
	save_b.text = "Nouvelle version" if spec.has("previous") else "Enregistrer le modèle"
	save_b.disabled = why != ""
	_reason.text = why if why != "" else ("Les vaisseaux déjà construits gardent leur version." if spec.has("previous") else "Le modèle rejoindra la liste de construction de vos chantiers.")
	_reason.add_theme_color_override("font_color", UiTheme.WARN if why != "" else UiTheme.TEXT_DIM)
	var retire_b: Button = buttons["retire"]
	retire_b.visible = _state.designs.has(selected)
	if retire_b.visible:
		retire_b.text = "Remettre en service" if _state.designs[selected].get("retired", false) else "Retirer de la construction"


func _first_design() -> String:
	var mine := Designs.designs_of(_state, _player, true)
	if not mine.is_empty():
		return String(mine.back()["id"])
	for sid in FactionTraits.ship_ids_for(_state.get_empire(_player).faction_id):
		if GameData.ship(sid).has("hull"):
			return sid
	return ""


func _slots_text(hid: String) -> String:
	var parts := PackedStringArray()
	var counts: Dictionary = Designs.hull(hid).get("slots", {})
	for t in Designs.slot_types():
		if int(counts.get(t, 0)) > 0:
			parts.append("%d %s" % [int(counts[t]), String(Designs.slot_types()[t]["label"]).to_lower()])
	return ", ".join(parts)


## Vue de la coque : une silhouette schématique (en attendant les illustrations) et les emplacements,
## colorés par type, avec le module posé. Clic : choisir ; clic droit : vider.
class HullView:
	extends Control
	signal slot_clicked(index: int, right: bool)
	const BOX := Vector2(150, 50)
	var hull_id := ""
	var slot_list: Array[Dictionary] = []
	var filled: Array = []
	var chosen := -1
	var _rects: Array[Rect2] = []

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func show_hull(hid: String, sl: Array[Dictionary], f: Array, sel: int) -> void:
		hull_id = hid
		slot_list = sl
		filled = f
		chosen = sel
		queue_redraw()

	func _layout() -> void:
		_rects.clear()
		# Colonnes de la proue (à droite) vers la poupe : armes, lourds, titanesque, défense, soutien.
		var order := ["weapon", "heavy", "astral", "colossal", "titanic", "defense", "support"]
		for t in Designs.slot_types():
			if not order.has(t):
				order.insert(3, t)
		var cols: Array = []
		for t in order:
			var idx: Array = []
			for i in slot_list.size():
				if slot_list[i]["type"] == t:
					idx.append(i)
			if not idx.is_empty():
				cols.append(idx)
		_rects.resize(slot_list.size())
		var n := cols.size()
		var gap := 12.0
		# Les cases rétrécissent pour que toutes les colonnes tiennent (titan : cinq types d'emplacements).
		var box := Vector2(minf(BOX.x, (size.x - 20.0 - (n - 1) * gap) / maxf(1.0, n)), BOX.y)
		var total_w := n * box.x + (n - 1) * gap
		var x0 := (size.x + total_w) * 0.5 - box.x
		for ci in n:
			var idx: Array = cols[ci]
			var h := idx.size() * box.y + (idx.size() - 1) * 8.0
			var y0 := (size.y - h) * 0.5
			for k in idx.size():
				_rects[idx[k]] = Rect2(Vector2(x0 - ci * (box.x + gap), y0 + k * (box.y + 8.0)), box)

	func _draw() -> void:
		if hull_id == "":
			return
		_layout()
		var h := Designs.hull(hull_id)
		var scale := {"small": 0.55, "medium": 0.7, "large": 0.86, "titan": 1.0}.get(String(h.get("size", "small")), 0.7) as float
		var c := size * 0.5
		var w := size.x * 0.48 * scale
		var hh := size.y * 0.44 * scale
		var body := PackedVector2Array([c + Vector2(w, 0), c + Vector2(w * 0.55, -hh), c + Vector2(-w * 0.8, -hh * 0.85),
				c + Vector2(-w, -hh * 0.4), c + Vector2(-w, hh * 0.4), c + Vector2(-w * 0.8, hh * 0.85), c + Vector2(w * 0.55, hh)])
		draw_colored_polygon(body, Color(0.12, 0.2, 0.28, 0.55))
		var outline := body.duplicate()
		outline.append(body[0])
		draw_polyline(outline, Color(UiTheme.ACCENT, 0.5), 1.5, true)
		var font := UiTheme.body_font()
		for i in slot_list.size():
			var r := _rects[i]
			var t := String(slot_list[i]["type"])
			var col := Color.html(String(Designs.slot_types().get(t, {}).get("color", "#ffffff")))
			var mid := String(filled[i]) if i < filled.size() else ""
			draw_rect(r, Color(col.darkened(0.7), 0.85 if mid != "" else 0.45))
			draw_rect(r, Color(col, 1.0 if i == chosen else 0.7), false, 3.0 if i == chosen else 1.5)
			var text := String(Designs.module(mid).get("label", mid)) if mid != "" else "vide"
			var tcol := UiTheme.TEXT if mid != "" else UiTheme.TEXT_DIM
			draw_string(font, r.position + Vector2(6, 18), String(Designs.slot_types().get(t, {}).get("label", t)).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 10, 10, Color(col, 0.9))
			draw_string(font, r.position + Vector2(6, 38), text, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 10, 12, tcol)
		# Modules intégrés (coques de peuple, cœur des méga-coques) : sous la coque, jamais retirables.
		var integ: Array = h.get("integrated", [])
		var x := c.x - integ.size() * 0.5 * 170.0
		for mid in integ:
			var r := Rect2(Vector2(x, size.y - 34), Vector2(160, 26))
			draw_rect(r, Color(0.35, 0.28, 0.08, 0.8))
			draw_rect(r, Color(1.0, 0.8, 0.35, 0.9), false, 1.5)
			draw_string(font, r.position + Vector2(8, 18), "◆ " + String(Designs.module(String(mid)).get("label", mid)), HORIZONTAL_ALIGNMENT_LEFT, 150, 12, Color(1.0, 0.88, 0.6))
			x += 170.0

	func _slot_at(p: Vector2) -> int:
		for i in _rects.size():
			if _rects[i].has_point(p):
				return i
		return -1

	func _gui_input(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb and mb.pressed and (mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT):
			var i := _slot_at(mb.position)
			if i >= 0:
				slot_clicked.emit(i, mb.button_index == MOUSE_BUTTON_RIGHT)
				accept_event()

	func _get_tooltip(at_position: Vector2) -> String:
		var i := _slot_at(at_position)
		if i < 0:
			return ""
		var mid := String(filled[i]) if i < filled.size() else ""
		if mid == "":
			return "Emplacement libre. Clic : choisir un module à droite."
		return "%s\n%s\nClic droit : vider." % [Designs.module(mid).get("label", mid), Designs.module(mid).get("text", "")]
