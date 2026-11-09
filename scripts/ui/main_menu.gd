class_name MainMenu
extends CanvasLayer
## Menu principal, par-dessus une galaxie qui dérive lentement : reprendre ou continuer une partie,
## en lancer une nouvelle (choix de la faction et de la graine), options, quitter.
## Il n'émet que des demandes ; main.gd crée la partie.

signal new_game_requested(faction_id: String, seed_value: int)
signal resume_requested
signal continue_requested
signal quit_requested

const TAGLINE := "Chronique d'une galaxie qui n'avait rien demandé"
const FACTION_CARD := Vector2(324, 96)

var page := "home"
var selected_faction := ""

var _home: VBoxContainer
var _resume: Button
var _continue: Button
var _new_page: PanelContainer
var _options_page: PanelContainer
var _options: OptionsPanel
var _faction_cards := {}
var _faction_trait: Label
var _seed_edit: LineEdit
var _title_block: VBoxContainer


func _ready() -> void:
	layer = 10
	visible = false
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP  # la carte derrière ne réagit pas
	add_child(root)

	# Voile sombre à gauche pour la lisibilité, la galaxie reste visible à droite.
	var shade := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0.0, 0.005, 0.02, 0.95))
	grad.set_color(1, Color(0.0, 0.005, 0.02, 0.15))
	grad.add_point(0.45, Color(0.0, 0.005, 0.02, 0.75))
	var gtex := GradientTexture2D.new()
	gtex.gradient = grad
	gtex.fill_to = Vector2(1, 0)
	shade.texture = gtex
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(shade)

	_title_block = VBoxContainer.new()
	_title_block.position = Vector2(96, 120)
	_title_block.add_theme_constant_override("separation", 0)
	_title_block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_title_block)
	var title := Label.new()
	title.text = "STELLAR SIGTH"
	var wide := FontVariation.new()
	wide.base_font = UiTheme.FONT_TITLE
	wide.spacing_glyph = 8
	title.add_theme_font_override("font", wide)
	title.add_theme_font_size_override("font_size", 88)
	title.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
	title.add_theme_color_override("font_shadow_color", Color(UiTheme.ACCENT, 0.35))
	title.add_theme_constant_override("shadow_offset_y", 0)
	title.add_theme_constant_override("shadow_outline_size", 18)
	_title_block.add_child(title)
	var line := ColorRect.new()
	line.color = UiTheme.GOLD
	line.custom_minimum_size = Vector2(120, 2)
	line.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_title_block.add_child(line)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 10)
	_title_block.add_child(gap)
	var tag := UiTheme.dim(TAGLINE, 18)
	_title_block.add_child(tag)

	_home = VBoxContainer.new()
	_home.position = Vector2(96, 340)
	_home.custom_minimum_size = Vector2(360, 0)
	_home.add_theme_constant_override("separation", 10)
	root.add_child(_home)
	_resume = _menu_button("Reprendre la partie", func() -> void: resume_requested.emit())
	_continue = _menu_button("Continuer", func() -> void: continue_requested.emit())
	_menu_button("Nouvelle partie", func() -> void: show_page("new"))
	_menu_button("Options", func() -> void: show_page("options"))
	_menu_button("Quitter", func() -> void: quit_requested.emit())

	var version := UiTheme.dim("Prototype  ·  Godot 4.7", 13)
	version.anchor_left = 1.0
	version.anchor_right = 1.0
	version.anchor_top = 1.0
	version.anchor_bottom = 1.0
	version.offset_left = -220
	version.offset_right = -20
	version.offset_top = -34
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(version)

	_build_new_page(root)
	_options_page = _window(root, Vector2(520, 340))
	_options = OptionsPanel.new()
	_options.back_requested.connect(func() -> void: show_page("home"))
	_options_page.add_child(_options)
	show_page("home")


## Affiche le menu. can_resume : une partie est en cours derrière ; has_save : une sauvegarde existe.
func open(can_resume: bool, has_save: bool, save_label := "") -> void:
	_resume.visible = can_resume
	_continue.visible = not can_resume
	_continue.disabled = not has_save
	_continue.tooltip_text = "Charger la sauvegarde rapide (%s)" % save_label if has_save else "Aucune sauvegarde pour l'instant."
	visible = true
	show_page("home")


func close() -> void:
	visible = false


func is_open() -> bool:
	return visible


func show_page(name: String) -> void:
	page = name
	_home.visible = name == "home"
	_title_block.visible = name == "home"
	_new_page.visible = name == "new"
	_options_page.visible = name == "options"
	if name == "options":
		_options.sync()
	if name == "new" and selected_faction == "":
		select_faction(GameData.faction_ids()[0])


## Échap : revient à l'accueil depuis une sous-page. Renvoie false si l'on était déjà à l'accueil.
func back() -> bool:
	if page != "home":
		show_page("home")
		return true
	return false


func select_faction(id: String) -> void:
	selected_faction = id
	for fid in _faction_cards:
		(_faction_cards[fid] as Button).set_pressed_no_signal(fid == id)
	_faction_trait.text = String(GameData.faction(id).get("trait", ""))


## Lance la partie avec la faction choisie ; graine tapée (nombre ou texte) ou tirée au hasard.
func launch() -> void:
	var text := _seed_edit.text.strip_edges()
	var seed_value := randi()
	if text.is_valid_int():
		seed_value = text.to_int()
	elif text != "":
		seed_value = text.hash()
	new_game_requested.emit(selected_faction, seed_value)


func _build_new_page(root: Control) -> void:
	_new_page = _window(root, Vector2(700, 640))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	_new_page.add_child(box)
	box.add_child(UiTheme.title("Nouvelle partie", 34))
	box.add_child(UiTheme.dim("Choisissez votre peuple. Les trois autres se disputeront la galaxie avec vous.", 14))
	box.add_child(HSeparator.new())
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	box.add_child(grid)
	for fid in GameData.faction_ids():
		var f := GameData.faction(fid)
		var col := Color.html(String(f.get("color", "#ffffff")))
		var card := Button.new()
		card.toggle_mode = true
		card.focus_mode = Control.FOCUS_NONE
		card.custom_minimum_size = FACTION_CARD
		card.add_theme_stylebox_override("pressed", UiTheme.box(Color(col.darkened(0.75), 0.95), col, 8))
		card.add_theme_stylebox_override("hover_pressed", UiTheme.box(Color(col.darkened(0.7), 1.0), col.lightened(0.2), 8))
		card.pressed.connect(select_faction.bind(fid))
		card.gui_input.connect(func(ev: InputEvent) -> void:
			var mb := ev as InputEventMouseButton
			if mb and mb.double_click and mb.button_index == MOUSE_BUTTON_LEFT:
				select_faction(fid)
				launch())
		var row := HBoxContainer.new()
		row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		row.offset_left = 14
		row.add_theme_constant_override("separation", 12)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(row)
		var emblem := Widgets.Emblem.new(40)
		emblem.color = col
		emblem.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(emblem)
		var texts := VBoxContainer.new()
		texts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		texts.add_theme_constant_override("separation", -2)
		texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(texts)
		var name_l := UiTheme.title(String(f.get("short", fid)), 24, col.lightened(0.3))
		name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		texts.add_child(name_l)
		var reg := UiTheme.dim(String(f.get("registre", "")), 13)
		reg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		texts.add_child(reg)
		grid.add_child(card)
		_faction_cards[fid] = card
	box.add_child(UiTheme.section("Particularité"))
	_faction_trait = UiTheme.paragraph("", 640, 15)
	_faction_trait.custom_minimum_size.y = 48
	box.add_child(_faction_trait)
	box.add_child(UiTheme.section("Galaxie"))
	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", 10)
	box.add_child(seed_row)
	var seed_label := Label.new()
	seed_label.text = "Graine"
	seed_row.add_child(seed_label)
	_seed_edit = LineEdit.new()
	_seed_edit.placeholder_text = "vide = au hasard (un nombre ou un mot)"
	_seed_edit.custom_minimum_size = Vector2(340, 0)
	_seed_edit.text_submitted.connect(func(_t: String) -> void: launch())
	seed_row.add_child(_seed_edit)
	var gap := Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(gap)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	box.add_child(buttons)
	var back_b := Button.new()
	back_b.text = "Retour  (Échap)"
	back_b.focus_mode = Control.FOCUS_NONE
	back_b.pressed.connect(func() -> void: show_page("home"))
	buttons.add_child(back_b)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(spacer)
	var go := Button.new()
	go.theme_type_variation = &"PrimaryButton"
	go.text = "Lancer la partie"
	go.custom_minimum_size = Vector2(240, 46)
	go.focus_mode = Control.FOCUS_NONE
	go.pressed.connect(launch)
	buttons.add_child(go)


func _menu_button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.theme_type_variation = &"MenuItem"
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(360, 54)
	b.pressed.connect(action)
	_home.add_child(b)
	return b


func _window(root: Control, win_size: Vector2) -> PanelContainer:
	var w := PanelContainer.new()
	w.theme_type_variation = &"WindowPanel"
	w.position = Vector2(96, 110)
	w.custom_minimum_size = win_size
	w.visible = false
	root.add_child(w)
	return w
