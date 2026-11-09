class_name EmpireScreens
extends CanvasLayer
## Écrans d'empire, en plein écran comme dans les 4X « épurés » : la carte s'efface, le panneau
## d'empire et le cadran du temps restent en place, un onglet en haut au centre nomme l'écran (et le
## ferme), une colonne à gauche résume, et le contenu se range en blocs titrés.
## Économie, Colonies, Recherche (en attente de son système) et Diplomatie.
## Les chiffres viennent d'EmpireReport, qui applique les règles de la simulation sans rien modifier.
## Les emplacements d'illustration (Widgets.ArtSlot) prendront les images de assets/art/ quand elles existeront.

signal planet_requested(planet_id: int)
signal close_requested
signal screen_changed(screen_id: String)
## Le joueur déclare la guerre à un empire (écran Diplomatie, après confirmation).
signal war_requested(empire_id: int)
## Un ordre de l'écran Diplomatie (proposer, répondre, rompre, soudoyer, banquet, arbitrer).
signal command_requested(cmd: Dictionary)

const MARGIN := 10.0
const SIDE_WIDTH := EmpireBar.WIDTH
const SIDE_TOP := EmpireBar.MARGIN + EmpireBar.HEIGHT + 8.0
const CONTENT_LEFT := SIDE_WIDTH + 2.0 * MARGIN + 18.0
## Le contenu s'arrête avant le cadran du temps, en bas à droite.
const CONTENT_RIGHT := TimeDial.SIDE + 30.0
const COLUMN_WIDTHS := [200.0, 200.0, 120.0, 210.0, 230.0]
const COLONY_FILTERS := [["all", "Toutes"], ["colony", "Colonies"], ["outpost", "Avant-postes"], ["founding", "Fondations"]]
const TYPE_COLORS := {
	"continental": Color(0.35, 0.7, 0.4), "ocean": Color(0.25, 0.5, 0.9), "desert": Color(0.9, 0.65, 0.35),
	"arctic": Color(0.75, 0.88, 1.0), "toxic": Color(0.65, 0.78, 0.2), "gas_giant": Color(0.88, 0.7, 0.45),
	"barren": Color(0.6, 0.58, 0.55), "asteroids": Color(0.62, 0.56, 0.48),
}

var current := ""
## Planète choisie dans l'écran Colonies (-1 = aucune).
var selected_planet := -1
var colony_filter := "all"
var _state: GameState
var _player := 0
var _root: Control
var _tab: Button
var _side: PanelContainer
var _side_box: VBoxContainer
var _content: MarginContainer
# Économie
var _res_rows := {}
var _totals := {}
var _donut: Widgets.Donut
var _donut_legend: VBoxContainer
var _sys_list: VBoxContainer
var _sys_sig := ""
var _alerts: Label
var _faction_art: Widgets.ArtSlot
var _trait: Label
# Colonies
var _col_list: VBoxContainer
var _col_sig := ""
var _col_rows: Array[Dictionary] = []
var _col_empty: Label
var _col_donut: Widgets.Donut
var _col_counts := {}
var _filter_tabs := {}
var _pick_art: Widgets.ArtSlot
var _pick_title: Label
var _pick_lines: Label
var _pick_net: HBoxContainer
var _pick_open: Widgets.RoundButton
# Diplomatie
var _diplo_sig := ""
## Boutons « Déclarer la guerre » par empire (pour les tests).
var war_buttons := {}
## Empire choisi dans l'écran Diplomatie, et les boutons de sa relation (pour les tests).
var diplo_selected := -1
var diplo_table: DiplomacyTable
var treaty_buttons := {}
var cancel_buttons := {}
var proposal_buttons := {}
var ability_buttons := {}


func _ready() -> void:
	layer = 2  # sous l'interface (panneau d'empire, cadran), au-dessus de la carte et de la vue système
	visible = false
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP  # la carte derrière ne réagit plus
	add_child(_root)
	var bg := ColorRect.new()
	bg.color = Color(0.008, 0.014, 0.028, 0.9)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bg)
	# Léger halo bleuté au centre, pour que le fond ne soit pas un aplat mort.
	var glow := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0.16, 0.3, 0.42, 0.28))
	grad.set_color(1, Color(0.16, 0.3, 0.42, 0.0))
	var gtex := GradientTexture2D.new()
	gtex.gradient = grad
	gtex.fill = GradientTexture2D.FILL_RADIAL
	gtex.fill_from = Vector2(0.5, 0.45)
	gtex.fill_to = Vector2(1.05, 0.45)
	glow.texture = gtex
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(glow)

	_tab = Button.new()
	_tab.theme_type_variation = &"TabButton"
	_tab.toggle_mode = true
	_tab.button_pressed = true
	_tab.focus_mode = Control.FOCUS_NONE
	_tab.tooltip_text = "Fermer  (Échap)"
	_tab.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_tab.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_tab.pressed.connect(func() -> void: close_requested.emit())
	_root.add_child(_tab)

	_side = PanelContainer.new()
	_side.theme_type_variation = &"SidePanel"
	_side.position = Vector2(MARGIN, SIDE_TOP)
	_side.custom_minimum_size = Vector2(SIDE_WIDTH, 0)
	_root.add_child(_side)
	_side_box = VBoxContainer.new()
	_side_box.add_theme_constant_override("separation", 10)
	_side.add_child(_side_box)

	_content = MarginContainer.new()
	_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_content.offset_left = CONTENT_LEFT
	_content.offset_top = 64.0
	_content.offset_right = -CONTENT_RIGHT
	_content.offset_bottom = -24.0
	_root.add_child(_content)


func open(screen_id: String, state: GameState, player: int) -> void:
	_state = state
	_player = player
	var was_open := visible
	visible = true
	show_screen(screen_id)
	if not was_open:
		_root.modulate.a = 0.0
		_root.create_tween().tween_property(_root, "modulate:a", 1.0, 0.18)


func close() -> void:
	visible = false
	current = ""


func is_open() -> bool:
	return visible and current != ""


func show_screen(screen_id: String) -> void:
	current = screen_id
	for c in _content.get_children() + _side_box.get_children():
		c.get_parent().remove_child(c)
		c.queue_free()
	_res_rows.clear()
	_totals.clear()
	_col_rows.clear()
	_col_counts.clear()
	_filter_tabs.clear()
	_col_sig = ""
	_sys_sig = ""
	var sc := EmpireBar.screen_info(screen_id)
	_tab.text = ("%s     ×" % sc.get("label", screen_id)).to_upper()
	match screen_id:
		"economy":
			_build_economy()
		"colonies":
			_build_colonies()
		"research":
			_build_research()
		"diplomacy":
			_build_diplomacy()
	refresh()
	screen_changed.emit(screen_id)


## Met à jour les chiffres (à chaque tick et après chaque ordre).
func refresh() -> void:
	if not is_open() or _state == null:
		return
	match current:
		"economy":
			_refresh_economy()
		"colonies":
			_refresh_colonies()
		"diplomacy":
			if _diplomacy_sig() != _diplo_sig:
				show_screen("diplomacy")


## Lignes de la liste des colonies (boutons), pour les tests.
func colony_buttons() -> Array[Button]:
	var out: Array[Button] = []
	for r in _col_rows:
		out.append(r["button"])
	return out


## Texte d'une ligne de ressource de l'économie (pour les tests) : "Matériaux|200|+20|-3|+17|…".
func economy_row_text(resource_id: String) -> String:
	if not _res_rows.has(resource_id):
		return ""
	var parts := PackedStringArray()
	for l: Label in _res_rows[resource_id]:
		parts.append(l.text)
	return "|".join(parts)


## Choisit une colonie dans l'écran Colonies (sa fiche s'affiche en bas).
func select_colony(pid: int) -> void:
	selected_planet = pid
	refresh()


## Ouvre la vue système de la colonie choisie.
func open_selected_colony() -> void:
	if selected_planet >= 0:
		planet_requested.emit(selected_planet)


func set_colony_filter(f: String) -> void:
	colony_filter = f
	for id in _filter_tabs:
		(_filter_tabs[id] as Button).set_pressed_no_signal(id == f)
	_col_sig = ""
	refresh()


# --- Pièces communes ------------------------------------------------------------------------

func _side_header(art_id: String, caption: String, tint: Color, motif: String) -> Widgets.ArtSlot:
	var art := Widgets.ArtSlot.new(art_id, Vector2(SIDE_WIDTH - 20.0, 150), tint, motif)
	art.set_caption(caption, 30)
	_side_box.add_child(art)
	return art


func _key_value(grid: GridContainer, key: String, value := "") -> Label:
	var k := Label.new()
	k.text = key
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(k)
	var v := Label.new()
	v.theme_type_variation = &"Numbers"
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.text = value
	grid.add_child(v)
	return v


func _grid(columns := 2) -> GridContainer:
	var g := GridContainer.new()
	g.columns = columns
	g.add_theme_constant_override("h_separation", 20)
	g.add_theme_constant_override("v_separation", 4)
	return g


## Icône et nombre pour chaque ressource non nulle d'un bilan.
func _fill_net(box: HBoxContainer, net: Dictionary, font_size := 16) -> void:
	for ch in box.get_children():
		box.remove_child(ch)
		ch.queue_free()
	for r in GameData.resource_ids():
		var v := int(net.get(r, 0))
		if v == 0:
			continue
		var pair := HBoxContainer.new()
		pair.add_theme_constant_override("separation", 3)
		pair.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pair.add_child(ResourceIcon.make(r, font_size - 2))
		var l := Label.new()
		l.text = "%+d" % v
		l.theme_type_variation = &"Numbers"
		l.add_theme_font_size_override("font_size", font_size)
		l.add_theme_color_override("font_color", UiTheme.delta_color(v))
		pair.add_child(l)
		box.add_child(pair)


func _row_button(height: float) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(0, height)
	b.add_theme_stylebox_override("normal", UiTheme.box(Color(1, 1, 1, 0.035), Color(0, 0, 0, 0), 8, 0))
	b.add_theme_stylebox_override("hover", UiTheme.box(Color(1, 1, 1, 0.08), Color(0, 0, 0, 0), 8, 0))
	var on := UiTheme.box(Color(UiTheme.ACCENT, 0.16), UiTheme.ACCENT, 8, 0)
	on.border_width_left = 3
	b.add_theme_stylebox_override("pressed", on)
	b.add_theme_stylebox_override("hover_pressed", on)
	return b


## Rangée de cases verrouillées (systèmes à venir).
func _locked_row(count: int, slot: Vector2, tip: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for i in count:
		var l := Widgets.ArtSlot.new("", slot, Color(0.5, 0.6, 0.7), "lock")
		l.mouse_filter = Control.MOUSE_FILTER_STOP
		l.tooltip_text = tip
		row.add_child(l)
	return row


# --- Économie -------------------------------------------------------------------------------

func _build_economy() -> void:
	var me := _state.get_empire(_player) if _state else null
	var col := me.color() if me else UiTheme.ACCENT
	var fid := me.faction_id if me else ""
	_faction_art = _side_header("faction_" + fid, me.short_name() if me else "", col, "faction")
	_side_box.add_child(UiTheme.section("Effets"))
	_trait = UiTheme.paragraph("", SIDE_WIDTH - 24.0, 14)
	_side_box.add_child(_trait)
	_side_box.add_child(HSeparator.new())
	_side_box.add_child(UiTheme.section("Empire"))
	var tgrid := _grid()
	_side_box.add_child(tgrid)
	for key in ["population", "colonies", "outposts", "systems", "founding"]:
		var label: String = {"population": "Population", "colonies": "Colonies", "outposts": "Avant-postes",
				"systems": "Systèmes", "founding": "Fondations en cours"}[key]
		_totals[key] = _key_value(tgrid, label)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 22)
	_content.add_child(rows)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 22)
	rows.add_child(top)
	var table := Widgets.Block.new("Bilan des ressources")
	table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(table)
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 10)
	table.body.add_child(grid)
	for h in ["", "Stock", "Production", "Entretien", "Bilan / mois", "Tendance"]:
		var l := UiTheme.section(h)
		if h != "":
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(l)
	for r in GameData.resource_ids():
		var name_box := HBoxContainer.new()
		name_box.add_theme_constant_override("separation", 8)
		name_box.custom_minimum_size = Vector2(170, 0)
		name_box.add_child(ResourceIcon.make(r, 20))
		var name_l := Label.new()
		name_l.text = GameData.resource_label(r)
		name_l.add_theme_font_size_override("font_size", 16)
		name_box.add_child(name_l)
		grid.add_child(name_box)
		var labels: Array[Label] = [name_l]
		for i in 5:
			var l := Label.new()
			l.theme_type_variation = &"Numbers"
			l.add_theme_font_size_override("font_size", 20 if i < 4 else 14)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			l.custom_minimum_size = Vector2(76 if i < 4 else 150, 0)
			grid.add_child(l)
			labels.append(l)
		_res_rows[r] = labels

	var share := Widgets.Block.new("Répartition de la production")
	share.custom_minimum_size = Vector2(380, 0)
	top.add_child(share)
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 16)
	share.body.add_child(srow)
	_donut = Widgets.Donut.new(176)
	_donut.center_title = "PAR MOIS"
	srow.add_child(_donut)
	_donut_legend = VBoxContainer.new()
	_donut_legend.alignment = BoxContainer.ALIGNMENT_CENTER
	_donut_legend.add_theme_constant_override("separation", 4)
	srow.add_child(_donut_legend)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 22)
	bottom.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(bottom)
	var systems := Widgets.Block.new("Production par système")
	systems.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(systems)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	systems.body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	systems.body.add_child(scroll)
	_sys_list = VBoxContainer.new()
	_sys_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sys_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_sys_list)
	var alerts := Widgets.Block.new("Alertes")
	alerts.custom_minimum_size = Vector2(380, 0)
	bottom.add_child(alerts)
	_alerts = UiTheme.paragraph("", 340, 15)
	alerts.body.add_child(_alerts)


func _refresh_economy() -> void:
	var me := _state.get_empire(_player)
	if me == null:
		return
	var parts: Array = []
	var gross_total := 0
	for c in _donut_legend.get_children():
		_donut_legend.remove_child(c)
		c.queue_free()
	for r: Dictionary in EmpireReport.resources(_state, _player):
		var labels: Array[Label] = []
		labels.assign(_res_rows[r["id"]])
		labels[1].text = str(r["stock"])
		labels[2].text = "+%d" % r["gross"] if int(r["gross"]) > 0 else "0"
		labels[2].add_theme_color_override("font_color", UiTheme.GOOD if int(r["gross"]) > 0 else UiTheme.TEXT_DIM)
		labels[3].text = "-%d" % r["upkeep"] if int(r["upkeep"]) > 0 else "0"
		labels[3].add_theme_color_override("font_color", UiTheme.BAD if int(r["upkeep"]) > 0 else UiTheme.TEXT_DIM)
		labels[4].text = "%+d" % r["net"]
		labels[4].add_theme_color_override("font_color", UiTheme.delta_color(int(r["net"])))
		var trend := ""
		var col := UiTheme.TEXT_DIM
		if int(r["months_left"]) >= 0:
			trend = "épuisé dans %d mois" % r["months_left"]
			col = UiTheme.WARN if int(r["months_left"]) > 2 else UiTheme.BAD
		elif int(r["net"]) > 0:
			trend = "en hausse"
			col = UiTheme.GOOD
		else:
			trend = "stable"
		if int(r["bonus_pct"]) != 0:
			labels[2].tooltip_text = "Bonus de faction : %+d %%" % r["bonus_pct"]
			labels[2].mouse_filter = Control.MOUSE_FILTER_STOP
		labels[5].text = trend
		labels[5].add_theme_color_override("font_color", col)
		# Anneau : part de chaque ressource dans la production brute.
		var rc := ResourceIcon.color_of(r["id"])
		parts.append({"value": float(r["gross"]), "color": rc})
		gross_total += int(r["gross"])
		var leg := HBoxContainer.new()
		leg.add_theme_constant_override("separation", 6)
		var v := Label.new()
		v.theme_type_variation = &"Numbers"
		v.custom_minimum_size = Vector2(44, 0)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		v.text = str(r["gross"])
		leg.add_child(v)
		leg.add_child(ResourceIcon.make(r["id"], 14))
		var n := Label.new()
		n.text = String(r["label"])
		n.add_theme_color_override("font_color", rc.lightened(0.2))
		leg.add_child(n)
		_donut_legend.add_child(leg)
	_donut.set_parts(parts, str(gross_total))

	var alerts := PackedStringArray()
	if me.starving:
		alerts.append("Famine : les réserves de nourriture sont vides et la population décline. Construisez des fermes ou colonisez un monde fertile.")
	if me.blackout:
		alerts.append("Pénurie d'énergie : tous les chantiers sont à l'arrêt tant que le stock reste vide.")
	for r: Dictionary in EmpireReport.resources(_state, _player):
		if int(r["months_left"]) >= 0 and int(r["months_left"]) <= 6 and int(r["stock"]) > 0:
			alerts.append("%s : épuisé dans %d mois à ce rythme." % [r["label"], r["months_left"]])
	if alerts.is_empty():
		alerts.append("Aucune crise en vue. Les comptables de l'empire s'ennuient, ce qui est bon signe.")
	_alerts.text = "\n\n".join(alerts)
	_alerts.add_theme_color_override("font_color", UiTheme.BAD if me.starving or me.blackout else UiTheme.TEXT_DIM)

	_faction_art.set_caption(me.short_name(), 30)
	_trait.text = EmpireBar.trait_summary(me.faction())
	var t := EmpireReport.totals(_state, _player)
	(_totals["population"] as Label).text = str(t["population"])
	(_totals["colonies"] as Label).text = str(t["colonies"])
	(_totals["outposts"] as Label).text = str(t["outposts"])
	(_totals["systems"] as Label).text = str(t["systems"])
	(_totals["founding"] as Label).text = "%d / %d" % [t["founding"], t["max_projects"]]
	_refresh_system_rows()


## Une ligne par système de l'empire : nom, revendications, bilan. Un clic ouvre sa vue système.
func _refresh_system_rows() -> void:
	var systems := EmpireReport.owned_systems(_state, _player)
	var sig := str(systems)
	if sig != _sys_sig:
		_sys_sig = sig
		for c in _sys_list.get_children():
			_sys_list.remove_child(c)
			c.queue_free()
		for sid in systems:
			var b := _row_button(40)
			b.toggle_mode = false
			b.tooltip_text = "Ouvrir la vue système"
			var first := _first_claim(sid)
			b.pressed.connect(func() -> void: planet_requested.emit(first))
			var row := HBoxContainer.new()
			row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			row.offset_left = 10
			row.add_theme_constant_override("separation", 10)
			row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.add_child(row)
			var name_l := UiTheme.title(_state.galaxy.systems[sid].system_name, 19)
			name_l.custom_minimum_size = Vector2(200, 0)
			name_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(name_l)
			var claims := UiTheme.dim("", 13)
			claims.custom_minimum_size = Vector2(150, 0)
			claims.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(claims)
			var net := HBoxContainer.new()
			net.add_theme_constant_override("separation", 12)
			net.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			net.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(net)
			b.set_meta("sid", sid)
			b.set_meta("claims", claims)
			b.set_meta("net", net)
			_sys_list.add_child(b)
	for b: Button in _sys_list.get_children():
		var sid: int = b.get_meta("sid")
		var n := 0
		for pid in _state.galaxy.systems[sid].planet_ids:
			var c: Colony = _state.colonies.get(pid)
			if c and c.owner == _player:
				n += 1
		(b.get_meta("claims") as Label).text = "%d revendication%s" % [n, "s" if n > 1 else ""]
		_fill_net(b.get_meta("net"), EmpireReport.system_net(_state, _player, sid), 15)


func _first_claim(sid: int) -> int:
	for pid in _state.galaxy.systems[sid].planet_ids:
		var c: Colony = _state.colonies.get(pid)
		if c and c.owner == _player:
			return pid
	return -1


# --- Colonies -------------------------------------------------------------------------------

func _build_colonies() -> void:
	_side_header("screen_colonies", "Colonies", UiTheme.ACCENT, "galaxy")
	var ring := HBoxContainer.new()
	ring.add_theme_constant_override("separation", 14)
	_side_box.add_child(ring)
	_col_donut = Widgets.Donut.new(130)
	_col_donut.center_title = "TOTAL"
	ring.add_child(_col_donut)
	var counts := _grid()
	counts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	counts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ring.add_child(counts)
	for key in ["colonies", "outposts", "founding"]:
		var label: String = {"colonies": "Colonies", "outposts": "Avant-postes", "founding": "Fondations"}[key]
		_col_counts[key] = _key_value(counts, label)
	_side_box.add_child(HSeparator.new())
	var g := _grid()
	_side_box.add_child(g)
	_col_counts["population"] = _key_value(g, "Population")
	_col_counts["systems"] = _key_value(g, "Systèmes")
	_col_counts["max_projects"] = _key_value(g, "Fondations simultanées")

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 22)
	_content.add_child(rows)
	var list_block := Widgets.Block.new("Liste des colonies")
	list_block.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_block.body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(list_block)
	var filters := HBoxContainer.new()
	filters.alignment = BoxContainer.ALIGNMENT_CENTER
	filters.add_theme_constant_override("separation", 30)
	list_block.body.add_child(filters)
	for f in COLONY_FILTERS:
		var b := Button.new()
		b.theme_type_variation = &"TabButton"
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.text = String(f[1]).to_upper()
		var fid: String = f[0]
		b.pressed.connect(func() -> void: set_colony_filter(fid))
		b.set_pressed_no_signal(fid == colony_filter)
		filters.add_child(b)
		_filter_tabs[fid] = b
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 0)
	list_block.body.add_child(header)
	var indent := Control.new()
	indent.custom_minimum_size = Vector2(12, 0)  # même retrait que le texte des lignes
	header.add_child(indent)
	var titles := ["Planète", "Type", "Population", "Chantier", "Bilan par mois"]
	for i in titles.size():
		var l := UiTheme.section(titles[i])
		l.custom_minimum_size = Vector2(COLUMN_WIDTHS[i], 0)
		header.add_child(l)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_block.body.add_child(scroll)
	_col_list = VBoxContainer.new()
	_col_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_col_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_col_list)
	_col_empty = UiTheme.paragraph("Rien dans cette catégorie. L'empire tient tout entier dans un carnet d'adresses très mince.", 600)
	_col_empty.visible = false
	list_block.body.add_child(_col_empty)

	var pick := Widgets.Block.new("Colonie choisie", 0)
	pick.custom_minimum_size = Vector2(0, 236)
	rows.add_child(pick)
	var prow := HBoxContainer.new()
	prow.add_theme_constant_override("separation", 0)
	pick.body.add_child(prow)
	_pick_art = Widgets.ArtSlot.new("", Vector2(380, 220), UiTheme.ACCENT, "planet")
	prow.add_child(_pick_art)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 0)
	prow.add_child(info)
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", UiTheme.box(Color(1, 1, 1, 0.05), Color(0, 0, 0, 0), 10, 0))
	info.add_child(bar)
	_pick_title = UiTheme.title("", 26)
	_pick_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bar.add_child(_pick_title)
	var details := MarginContainer.new()
	details.add_theme_constant_override("margin_left", 20)
	details.add_theme_constant_override("margin_top", 10)
	details.add_theme_constant_override("margin_right", 20)
	details.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info.add_child(details)
	var dbox := VBoxContainer.new()
	dbox.add_theme_constant_override("separation", 8)
	details.add_child(dbox)
	_pick_lines = UiTheme.paragraph("", 400, 15)
	dbox.add_child(_pick_lines)
	_pick_net = HBoxContainer.new()
	_pick_net.add_theme_constant_override("separation", 14)
	dbox.add_child(_pick_net)
	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_END
	info.add_child(foot)
	_pick_open = Widgets.RoundButton.new("next", "Ouvrir la vue système", 16)
	_pick_open.pressed.connect(open_selected_colony)
	foot.add_child(_pick_open)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(14, 0)
	foot.add_child(pad)


func _refresh_colonies() -> void:
	var all := EmpireReport.colonies(_state, _player)
	var list: Array[Dictionary] = []
	for c in all:
		if _matches_filter(c):
			list.append(c)
	var ids := PackedStringArray()
	for c in list:
		ids.append(str(c["planet_id"]))
	var sig := colony_filter + ":" + ",".join(ids)
	if sig != _col_sig:
		_col_sig = sig
		_rebuild_colony_rows(list)
	_col_empty.visible = list.is_empty()
	var t := EmpireReport.totals(_state, _player)
	(_col_counts["colonies"] as Label).text = str(t["colonies"])
	(_col_counts["outposts"] as Label).text = str(t["outposts"])
	(_col_counts["founding"] as Label).text = str(t["founding"])
	(_col_counts["population"] as Label).text = str(t["population"])
	(_col_counts["systems"] as Label).text = str(t["systems"])
	(_col_counts["max_projects"] as Label).text = str(t["max_projects"])
	_col_donut.set_parts([
		{"value": float(t["colonies"]), "color": UiTheme.ACCENT},
		{"value": float(t["outposts"]), "color": Color(0.55, 0.62, 0.72)},
		{"value": float(t["founding"]), "color": UiTheme.WARN}], str(all.size()))
	if selected_planet < 0 or not _state.colonies.has(selected_planet) or (_state.colonies[selected_planet] as Colony).owner != _player:
		selected_planet = int(all[0]["planet_id"]) if not all.is_empty() else -1
	for i in list.size():
		_fill_colony_row(_col_rows[i], list[i])
	_refresh_pick(all)


func _matches_filter(c: Dictionary) -> bool:
	match colony_filter:
		"colony":
			return c["established"] and c["kind"] == Colony.KIND_COLONY
		"outpost":
			return c["established"] and c["kind"] != Colony.KIND_COLONY
		"founding":
			return not c["established"]
	return true


func _rebuild_colony_rows(list: Array[Dictionary]) -> void:
	for c in _col_list.get_children():
		_col_list.remove_child(c)
		c.queue_free()
	_col_rows.clear()
	for c in list:
		var b := _row_button(42)
		var pid: int = c["planet_id"]
		b.pressed.connect(func() -> void: select_colony(pid))
		b.gui_input.connect(func(ev: InputEvent) -> void:
			var mb := ev as InputEventMouseButton
			if mb and mb.double_click and mb.button_index == MOUSE_BUTTON_LEFT:
				planet_requested.emit(pid))
		b.tooltip_text = "Clic : choisir    Double-clic : ouvrir la vue système"
		var row := HBoxContainer.new()
		row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		row.offset_left = 12
		row.add_theme_constant_override("separation", 0)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(row)
		var cells: Array[Control] = []
		for i in COLUMN_WIDTHS.size():
			var cell: Control
			if i == 4:
				cell = HBoxContainer.new()
				(cell as HBoxContainer).add_theme_constant_override("separation", 10)
			else:
				cell = Label.new()
			cell.custom_minimum_size = Vector2(COLUMN_WIDTHS[i], 0)
			cell.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(cell)
			cells.append(cell)
		(cells[0] as Label).theme_type_variation = &"Title"
		(cells[0] as Label).add_theme_font_size_override("font_size", 20)
		_col_list.add_child(b)
		_col_rows.append({"button": b, "cells": cells, "net_sig": "", "pid": pid})


func _pop_text(c: Dictionary) -> String:
	if not c["established"]:
		return "fondation : %d j" % c["days_left"]
	if c["kind"] == Colony.KIND_COLONY:
		return "%d / %d" % [c["population"], c["max_pop"]]
	return "avant-poste"


func _fill_colony_row(row: Dictionary, c: Dictionary) -> void:
	var cells: Array = row["cells"]
	(row["button"] as Button).set_pressed_no_signal(int(row["pid"]) == selected_planet)
	(cells[0] as Label).text = String(c["name"])
	(cells[0] as Label).add_theme_color_override("font_color", UiTheme.TEXT)
	(cells[1] as Label).text = String(c["type_label"]) + ("  (capitale)" if c["capital"] else "")
	(cells[2] as Label).text = _pop_text(c)
	(cells[2] as Label).add_theme_color_override("font_color", UiTheme.WARN if not c["established"] else UiTheme.TEXT)
	(cells[3] as Label).text = "%s (%d j)" % [c["construction"], c["construction_days"]] if c["construction"] != "" else "—"
	(cells[3] as Label).add_theme_color_override("font_color", UiTheme.TEXT if c["construction"] != "" else UiTheme.TEXT_DIM)
	var sig := str(c["net"])
	if sig != row["net_sig"]:
		row["net_sig"] = sig
		_fill_net(cells[4], c["net"])


func _refresh_pick(all: Array[Dictionary]) -> void:
	var c: Dictionary = {}
	for x in all:
		if int(x["planet_id"]) == selected_planet:
			c = x
	_pick_open.disabled = c.is_empty()
	if c.is_empty():
		_pick_title.text = "Aucune colonie"
		_pick_lines.text = "Fondez une colonie ou un avant-poste depuis la vue d'un système."
		_fill_net(_pick_net, {})
		return
	var p := _state.galaxy.get_planet(selected_planet)
	var type_id := String(p.type)
	_pick_art.set_art("planet_" + type_id, TYPE_COLORS.get(type_id, UiTheme.ACCENT), "planet")
	_pick_title.text = String(c["name"]).to_upper()
	var lines := PackedStringArray()
	lines.append("%s, taille %d  ·  système %s%s" % [c["type_label"], p.size, c["system_name"], "  ·  capitale" if c["capital"] else ""])
	if not c["established"]:
		lines.append("Fondation en cours : encore %d jours." % c["days_left"])
	elif c["kind"] == Colony.KIND_COLONY:
		lines.append("Colonie : %d / %d population." % [c["population"], c["max_pop"]])
	else:
		lines.append("Avant-poste : pas de population, mais la planète est à nous.")
	lines.append("Chantier : %s (%d j)" % [c["construction"], c["construction_days"]] if c["construction"] != "" else "Aucun chantier en cours.")
	lines.append("Bilan par mois :")
	_pick_lines.text = "\n".join(lines)
	_fill_net(_pick_net, c["net"], 18)


# --- Recherche et diplomatie (en attente) ---------------------------------------------------

func _build_research() -> void:
	_side_header("screen_research", "Recherche", Color(0.55, 0.7, 1.0), "star")
	_side_box.add_child(UiTheme.paragraph(String(EmpireBar.screen_info("research").get("why", "")), SIDE_WIDTH - 24.0, 14))
	_side_box.add_child(HSeparator.new())
	var g := _grid()
	_side_box.add_child(g)
	_key_value(g, "Recherche en cours", "aucune")
	_key_value(g, "Technologies connues", "0")

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 22)
	_content.add_child(rows)
	var tree := Widgets.Block.new("Arbre des technologies")
	rows.add_child(tree)
	var eras := HBoxContainer.new()
	eras.add_theme_constant_override("separation", 26)
	eras.alignment = BoxContainer.ALIGNMENT_CENTER
	tree.body.add_child(eras)
	for era in ["Ère I", "Ère II", "Ère III", "Ère IV"]:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 8)
		eras.add_child(col)
		var h := Widgets.NotchHeader.new(era, 16)
		h.custom_minimum_size.x = 2 * 112 + 6
		col.add_child(h)
		for i in 3:
			col.add_child(_locked_row(2, Vector2(112, 96), "Technologie à découvrir"))
	var now := Widgets.Block.new("Recherche en cours")
	rows.add_child(now)
	var nrow := HBoxContainer.new()
	nrow.add_theme_constant_override("separation", 20)
	now.body.add_child(nrow)
	var p := UiTheme.paragraph("Aucune. Les laboratoires sont prêts, il ne manque que des savants et un arbre à explorer.", 560, 15)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nrow.add_child(p)
	var pick := Widgets.RoundButton.new("plus", "Choisir une technologie", 16)
	pick.disabled = true
	pick.tooltip_text = "Arrive avec le système de recherche."
	nrow.add_child(pick)
	_spacer(rows)


func _build_diplomacy() -> void:
	_side_header("screen_diplomacy", "Diplomatie", Color(0.8, 0.6, 1.0), "faction")
	_diplo_sig = _diplomacy_sig()
	war_buttons.clear()
	treaty_buttons.clear()
	cancel_buttons.clear()
	proposal_buttons.clear()
	ability_buttons.clear()
	var me := _state.get_empire(_player)
	if diplo_selected < 0 or _state.get_empire(diplo_selected) == null or diplo_selected == _player:
		diplo_selected = -1
		for e in _state.empires:
			if e.id != _player and me.contacts.has(e.id) and not e.eliminated:
				diplo_selected = e.id
				break
		if diplo_selected < 0:
			diplo_selected = 1 if _player == 0 else 0

	# Colonne de gauche : bilan, talents du peuple, héritier.
	var g := _grid()
	_side_box.add_child(g)
	var wars := 0
	var pacts := 0
	for o in me.contacts:
		if Combat.at_war(_state, _player, o):
			wars += 1
		elif Diplomacy.has_pact(_state, _player, o):
			pacts += 1
	_key_value(g, "Empires rencontrés", str(me.contacts.size()))
	_key_value(g, "Guerres", str(wars))
	_key_value(g, "Traités", str(pacts))
	var income := Diplomacy.treaty_income(_state, _player)
	if not income.is_empty():
		_key_value(g, "Revenus des traités", GameData.format_amounts(income, true))
	_side_box.add_child(HSeparator.new())
	for ab in Diplomacy.faction_abilities(me.faction()):
		var t := UiTheme.paragraph("%s. %s" % [ab["label"], ab["text"]], SIDE_WIDTH - 24.0, 13)
		_side_box.add_child(t)
	if Diplomacy.has_heir(_state, _player):
		_side_box.add_child(_heir_box(me))
	if Diplomacy.faction_abilities(me.faction()).is_empty():
		_side_box.add_child(UiTheme.paragraph(String(EmpireBar.screen_info("diplomacy").get("why", "")), SIDE_WIDTH - 24.0, 14))

	# Contenu : la table à gauche, la relation choisie et les propositions à droite.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	_content.add_child(row)
	var left := Widgets.Block.new("Galaxie diplomatique")
	left.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(left)
	diplo_table = DiplomacyTable.new(430.0)
	left.body.add_child(diplo_table)
	diplo_table.setup(_state, _player, diplo_selected)
	diplo_table.empire_selected.connect(func(id: int) -> void:
		diplo_selected = id
		show_screen("diplomacy"))
	var legend := HBoxContainer.new()
	legend.add_theme_constant_override("separation", 12)
	for st in ["war", "cold", "peace", "alliance"]:
		var pair := HBoxContainer.new()
		pair.add_theme_constant_override("separation", 4)
		pair.add_child(Widgets.Dot.new(DiplomacyTable.STATUS_COLORS[st], 10))
		pair.add_child(UiTheme.dim(Diplomacy.status_label(st), 13))
		legend.add_child(pair)
	left.body.add_child(legend)

	var right := VBoxContainer.new()
	right.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	right.add_theme_constant_override("separation", 18)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)
	var props := Diplomacy.proposals_for(_state, _player)
	if not props.is_empty():
		right.add_child(_proposals_block(props))
	right.add_child(_relation_block(diplo_selected))


func _heir_box(me: Empire) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var trend := Diplomacy.heir_trend(_state, _player)
	var delta := 0
	var lines := PackedStringArray()
	for p in trend:
		delta += int(p["value"])
		lines.append("%+d  %s" % [int(p["value"]), p["label"]])
	var g := _grid()
	box.add_child(g)
	var v := _key_value(g, "Loyauté de l'héritier", "%d / 100" % me.heir_loyalty)
	v.add_theme_color_override("font_color", UiTheme.GOOD if me.heir_loyalty >= 50 else (UiTheme.WARN if me.heir_loyalty >= 25 else UiTheme.BAD))
	v.tooltip_text = "Chaque mois : %+d\n%s" % [delta, "\n".join(lines)]
	v.mouse_filter = Control.MOUSE_FILTER_STOP
	var t := _key_value(g, "Tendance", "%+d / mois" % delta)
	t.add_theme_color_override("font_color", UiTheme.delta_color(delta))
	if me.heir_suitor >= 0 and _state.get_empire(me.heir_suitor) != null:
		box.add_child(UiTheme.dim("Courtisé par %s" % _state.get_empire(me.heir_suitor).short_name(), 13))
	var cost: Dictionary = Diplomacy.ability("heir")["banquet_cost"]
	var b := Button.new()
	b.text = "BANQUET DES LIGNÉES (%s)" % GameData.format_amounts(cost)
	b.focus_mode = Control.FOCUS_NONE
	var why := Diplomacy.check_banquet(_state, _player)
	b.disabled = why != ""
	b.tooltip_text = why if why != "" else "+%d loyauté." % int(Diplomacy.ability("heir")["banquet_gain"])
	b.pressed.connect(func() -> void: command_requested.emit(SimCommands.banquet(_player)))
	box.add_child(b)
	ability_buttons["banquet"] = b
	return box


func _proposals_block(props: Array[Dictionary]) -> Control:
	var blk := Widgets.Block.new("Propositions reçues")
	for p in props:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		blk.body.add_child(line)
		var from := _state.get_empire(int(p["from"]))
		var left := Diplomacy.days("proposal_days", 30) - (_state.tick - int(p["tick"]))
		var l := Label.new()
		l.text = "%s propose : %s  (encore %d j)" % [from.short_name(), Diplomacy.treaty_label(String(p["treaty"])), left]
		l.add_theme_color_override("font_color", from.color().lerp(Color.WHITE, 0.4))
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.tooltip_text = String(Diplomacy.treaty_info(String(p["treaty"])).get("desc", ""))
		l.mouse_filter = Control.MOUSE_FILTER_STOP
		line.add_child(l)
		var pid := int(p["id"])
		var ok := Button.new()
		ok.text = "ACCEPTER"
		ok.theme_type_variation = &"PrimaryButton"
		ok.focus_mode = Control.FOCUS_NONE
		var why := Diplomacy.check_answer(_state, _player, pid, true)
		ok.disabled = why != ""
		ok.tooltip_text = why
		ok.pressed.connect(func() -> void: command_requested.emit(SimCommands.answer_proposal(_player, pid, true)))
		line.add_child(ok)
		var no := Button.new()
		no.text = "REFUSER"
		no.focus_mode = Control.FOCUS_NONE
		no.pressed.connect(func() -> void: command_requested.emit(SimCommands.answer_proposal(_player, pid, false)))
		line.add_child(no)
		proposal_buttons[pid] = [ok, no]
	return blk


func _relation_block(id: int) -> Control:
	var e := _state.get_empire(id)
	var me := _state.get_empire(_player)
	var blk := Widgets.Block.new(e.display_name())
	var st := Diplomacy.status(_state, _player, id)
	if e.eliminated:
		st = "none"
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	blk.body.add_child(head)
	var art := Widgets.ArtSlot.new("faction_" + e.faction_id, Vector2(150, 110), e.color(), "faction")
	head.add_child(art)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(info)
	info.add_child(UiTheme.dim(String(e.faction().get("registre", "")), 13))
	var sl := Label.new()
	sl.text = ("Disparu" if e.eliminated else Diplomacy.status_label(st)).to_upper()
	sl.add_theme_font_size_override("font_size", 20)
	sl.add_theme_color_override("font_color", DiplomacyTable.STATUS_COLORS[st])
	info.add_child(sl)
	var extra := PackedStringArray()
	if Diplomacy.in_truce(_state, _player, id):
		extra.append("Trêve : encore %d jours" % Diplomacy.truce_left(_state, _player, id))
	if st == "peace" or st == "alliance":
		extra.append("Signé il y a %d jours" % Diplomacy.pact_days(_state, _player, id))
	if Diplomacy.has_trade(_state, _player, id):
		extra.append("Accord commercial")
	if st == "war":
		extra.append("Guerre depuis %d jours, score %+d" % [Diplomacy.pact_days(_state, _player, id), Diplomacy.war_score(_state, _player, id)])
	if e.is_ai():
		extra.append("Tempérament : %s" % AiLevels.temperament_label(e))
	for x in extra:
		info.add_child(UiTheme.dim(x, 13))
	if st == "none":
		blk.body.add_child(UiTheme.paragraph("Aucun contact : vos éclaireurs n'ont pas encore croisé cet empire." if not e.eliminated else "Cet empire a disparu de la galaxie.", 520, 14))
		return blk

	# Opinions, détaillées dans l'infobulle.
	var g := _grid(2)
	blk.body.add_child(g)
	_opinion_row(g, "Son opinion de vous", id, _player)
	_opinion_row(g, "Votre opinion de lui", _player, id)
	for ab in Diplomacy.faction_abilities(e.faction()):
		var t := UiTheme.paragraph("%s. %s" % [ab["label"], ab["text"]], 520, 13)
		t.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
		blk.body.add_child(t)
	if Diplomacy.has_heir(_state, id):
		blk.body.add_child(UiTheme.dim("Loyauté de son héritier : %d / 100" % e.heir_loyalty, 13))

	# Traités : un bouton par traité, avec ce que l'autre en pense (comme la barre d'Endless Space 2).
	blk.body.add_child(UiTheme.section("Proposer"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 6)
	blk.body.add_child(grid)
	for t in Diplomacy.TREATY_IDS:
		var b := Button.new()
		b.text = Diplomacy.treaty_label(t).to_upper()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(220, 0)
		var why := Diplomacy.check_propose(_state, _player, id, t)
		b.disabled = why != ""
		var desc := String(Diplomacy.treaty_info(t).get("desc", ""))
		b.tooltip_text = (why + "\n\n" + desc) if why != "" else desc
		var treaty := t
		b.pressed.connect(func() -> void: command_requested.emit(SimCommands.propose_treaty(_player, id, treaty)))
		grid.add_child(b)
		treaty_buttons[t] = b
		var verdict := Label.new()
		verdict.mouse_filter = Control.MOUSE_FILTER_STOP
		if why != "":
			verdict.text = why
			verdict.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
		elif e.is_ai():
			var ev := AiDiplomacy.evaluate(_state, id, _player, t)
			var yes := int(ev["score"]) >= int(Diplomacy.data()["ai"]["accept_at"])
			verdict.text = "%s  (%+d)" % ["Accepterait" if yes else "Refuserait", int(ev["score"])]
			verdict.add_theme_color_override("font_color", UiTheme.GOOD if yes else UiTheme.BAD)
			var lines := PackedStringArray()
			for p in ev["parts"]:
				lines.append("%+d  %s" % [int(p["value"]), p["label"]])
			verdict.tooltip_text = "Ce que %s pense de l'offre :\n%s" % [e.short_name(), "\n".join(lines)]
		else:
			verdict.text = "Il devra répondre"
			verdict.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
		verdict.add_theme_font_size_override("font_size", 13)
		verdict.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		verdict.custom_minimum_size = Vector2(240, 0)
		grid.add_child(verdict)

	# Rompre, déclarer, intriguer, arbitrer.
	var acts := HFlowContainer.new()
	acts.add_theme_constant_override("h_separation", 10)
	acts.add_theme_constant_override("v_separation", 6)
	blk.body.add_child(acts)
	for t in [Diplomacy.ALLIANCE, Diplomacy.PEACE, Diplomacy.TRADE]:
		var label: String = {"alliance": "QUITTER L'ALLIANCE", "peace": "DÉNONCER LA PAIX", "trade": "ROMPRE L'ACCORD"}[t]
		var shown: bool = (t == Diplomacy.ALLIANCE and Diplomacy.allied(_state, _player, id)) \
				or (t == Diplomacy.PEACE and Diplomacy.pact(_state, _player, id) == Diplomacy.PEACE) \
				or (t == Diplomacy.TRADE and Diplomacy.has_trade(_state, _player, id))
		if not shown:
			continue
		var b := Button.new()
		b.text = label
		b.focus_mode = Control.FOCUS_NONE
		var why := Diplomacy.check_cancel(_state, _player, id, t)
		b.disabled = why != ""
		b.tooltip_text = why
		var treaty: String = t
		b.pressed.connect(func() -> void: command_requested.emit(SimCommands.cancel_treaty(_player, id, treaty)))
		acts.add_child(b)
		cancel_buttons[t] = b
	if not e.eliminated and not Combat.at_war(_state, _player, id):
		var war := Button.new()
		var label := "ROMPRE ET DÉCLARER LA GUERRE" if Diplomacy.has_pact(_state, _player, id) else "DÉCLARER LA GUERRE"
		war.text = label
		war.focus_mode = Control.FOCUS_NONE
		var why := Combat.check_declare_war(_state, _player, id)
		war.disabled = why != ""
		war.tooltip_text = why if why != "" else ("Deux clics. Rompre un traité fait de vous un parjure aux yeux de toute la galaxie." \
				if Diplomacy.has_pact(_state, _player, id) else "Deux clics : la guerre vaut dans les deux sens.")
		var target := id
		war.pressed.connect(func() -> void:
			if war.text == label:
				war.text = "CONFIRMER ?"
				war.theme_type_variation = &"PrimaryButton"
			else:
				war_requested.emit(target))
		acts.add_child(war)
		war_buttons[id] = war
	if Diplomacy.has_heir(_state, id):
		var b := Button.new()
		b.text = "SOUDOYER L'HÉRITIER (%s)" % GameData.format_amounts(Diplomacy.ability("heir")["bribe_cost"])
		b.focus_mode = Control.FOCUS_NONE
		var why := Diplomacy.check_bribe(_state, _player, id)
		b.disabled = why != ""
		b.tooltip_text = why if why != "" else "Sa loyauté baisse de %d. À 0, il vous livre son fief le plus lointain. Ils le sauront." % int(Diplomacy.ability("heir")["bribe_loss"])
		b.pressed.connect(func() -> void: command_requested.emit(SimCommands.bribe_heir(_player, id)))
		acts.add_child(b)
		ability_buttons["bribe"] = b
	if Diplomacy.has_ability(_state, _player, "mediation"):
		for w in e.wars:
			if w == _player or not me.contacts.has(w) or Diplomacy.no_treaties(_state, w) or Diplomacy.no_treaties(_state, id):
				continue
			var b := Button.new()
			b.text = "ARBITRER : %s / %s" % [e.short_name().to_upper(), _state.get_empire(w).short_name().to_upper()]
			b.focus_mode = Control.FOCUS_NONE
			var why := Diplomacy.check_mediate(_state, _player, id, w)
			b.disabled = why != ""
			b.tooltip_text = why if why != "" else "Les Veilleurs du Seuil imposent la paix (%s)." % GameData.format_amounts(Diplomacy.ability("mediation")["cost"])
			var other := w
			b.pressed.connect(func() -> void: command_requested.emit(SimCommands.mediate(_player, id, other)))
			acts.add_child(b)
			ability_buttons["mediate_%d" % w] = b
	return blk


func _opinion_row(g: GridContainer, caption: String, who: int, about: int) -> void:
	var v := Diplomacy.opinion(_state, who, about)
	var val := _key_value(g, caption, "%+d  %s" % [v, Diplomacy.opinion_label(v)])
	val.add_theme_color_override("font_color", UiTheme.delta_color(v) if absi(v) >= 20 else UiTheme.TEXT)
	var lines := PackedStringArray()
	for p in Diplomacy.opinion_parts(_state, who, about):
		lines.append("%+d  %s" % [int(p["value"]), p["label"]])
	val.tooltip_text = "\n".join(lines) if not lines.is_empty() else "Aucune raison particulière."
	val.mouse_filter = Control.MOUSE_FILTER_STOP


## Ce qui change l'écran Diplomatie : contacts, guerres, traités, propositions, mois, influence.
func _diplomacy_sig() -> String:
	var parts := PackedStringArray()
	for e in _state.empires:
		parts.append("%d:%s:%s:%s:%d" % [e.id, str(e.contacts), str(e.wars), e.eliminated, e.heir_loyalty])
	@warning_ignore("integer_division")
	parts.append(str(_state.tick / 30))
	parts.append(str(_state.relations))
	parts.append(str(_state.proposals.size()) + ":" + str(_state.next_proposal_id))
	parts.append(str(_state.get_empire(_player).resources.get("influence", 0)))
	return "|".join(parts)


func _spacer(parent: Control) -> void:
	var gap := Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(gap)
