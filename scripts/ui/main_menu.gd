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
const TILE_SIZE := Vector2(150, 270)
## Case « Au hasard » du choix de faction : un peuple est tiré au lancement.
const RANDOM_FACTION := "random"
const TYPE_LABELS := {"continental": "continental", "ocean": "océanique", "desert": "désertique", "arctic": "glaciaire",
	"toxic": "toxique", "gas_giant": "géante gazeuse", "barren": "stérile", "asteroids": "astéroïdes"}

var page := "home"
var selected_faction := ""

var _home: VBoxContainer
var _resume: Button
var _continue: Button
var _new_page: Control
var _scene_art: Widgets.ArtSlot
var _scene_name: Label
var _faction_emblem: Widgets.Emblem
var _faction_registre: Label
var _faction_worlds: Label
var _faction_lore: Label
var _lore_header: Label
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

	# Illustration de fond si assets/art/main_menu existe ; sinon la galaxie qui dérive derrière.
	var backdrop := Widgets.ArtSlot.new("main_menu", Vector2.ZERO)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.visible = backdrop.has_art()
	root.add_child(backdrop)
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
	title.add_theme_font_override("font", UiTheme.font(200, 14))
	title.add_theme_font_size_override("font_size", 86)
	title.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	title.add_theme_constant_override("shadow_offset_y", 2)
	_title_block.add_child(title)
	var line := ColorRect.new()
	line.color = Color(1, 1, 1, 0.35)
	line.custom_minimum_size = Vector2(640, 1)
	line.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_title_block.add_child(line)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 10)
	_title_block.add_child(gap)
	var tag := UiTheme.dim(TAGLINE.to_upper(), 14)
	tag.add_theme_font_override("font", UiTheme.font(400, 4))
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
		var tile := _faction_cards[fid] as Button
		tile.set_pressed_no_signal(fid == id)
		_style_tile(tile, fid == id, false)
	if id == RANDOM_FACTION:
		_scene_art.set_art("faction_random", Color(0.56, 0.64, 0.72), "galaxy")
		_scene_name.text = "Peuple tiré au sort"
		_scene_name.add_theme_color_override("font_color", UiTheme.TEXT)
		_lore_header.text = "AU HASARD"
		_faction_emblem.color = Color(0.56, 0.64, 0.72)
		_faction_registre.text = "Surprise"
		_faction_trait.text = "Un peuple est tiré au sort au lancement. Le destin a un sens de l'humour, vous verrez."
		_faction_worlds.text = "—"
		_faction_lore.text = "Certains choisissent leur camp. D'autres préfèrent découvrir, au réveil, qu'ils sont un essaim affamé ou une théocratie chantante. C'est une façon de vivre."
		_faction_emblem.queue_redraw()
		return
	var f := GameData.faction(id)
	var col := Color.html(String(f.get("color", "#ffffff")))
	_scene_art.set_art("faction_%s_scene" % id, col, "faction")
	_scene_name.text = String(f.get("name", id))
	_scene_name.add_theme_color_override("font_color", col.lightened(0.45))
	_lore_header.text = String(f.get("short", id)).to_upper()
	_faction_emblem.color = col
	_faction_emblem.queue_redraw()
	_faction_registre.text = String(f.get("registre", ""))
	_faction_registre.add_theme_color_override("font_color", col.lightened(0.3))
	_faction_trait.text = String(f.get("trait", ""))
	var worlds := PackedStringArray()
	for t in f.get("preferred", []):
		worlds.append(String(TYPE_LABELS.get(t, t)))
	_faction_worlds.text = ", ".join(worlds) if not worlds.is_empty() else "—"
	_faction_lore.text = String(f.get("lore", ""))


## Lance la partie avec la faction choisie ; graine tapée (nombre ou texte) ou tirée au hasard.
func launch() -> void:
	var text := _seed_edit.text.strip_edges()
	var seed_value := randi()
	if text.is_valid_int():
		seed_value = text.to_int()
	elif text != "":
		seed_value = text.hash()
	var faction := selected_faction
	if faction == RANDOM_FACTION:
		var ids := GameData.faction_ids()
		faction = ids[randi() % ids.size()]
	new_game_requested.emit(faction, seed_value)


func _build_new_page(root: Control) -> void:
	# Page plein écran, sur le modèle des écrans de choix de faction des 4X : une grille de portraits
	# à gauche, la grande illustration du peuple choisi à droite, ses traits et son histoire en bas.
	var page_root := Control.new()
	page_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page_root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(page_root)
	_new_page = page_root
	var bg := ColorRect.new()
	bg.color = Color(0.012, 0.016, 0.026, 0.97)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page_root.add_child(bg)
	_scene_art = Widgets.ArtSlot.new("", Vector2.ZERO, UiTheme.ACCENT, "faction")
	_scene_art.anchor_left = 0.5
	_scene_art.anchor_right = 1.0
	_scene_art.anchor_bottom = 1.0
	page_root.add_child(_scene_art)
	# Fondu de l'illustration vers la gauche.
	var fade := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0.012, 0.016, 0.026, 1.0))
	grad.set_color(1, Color(0.012, 0.016, 0.026, 0.0))
	var gtex := GradientTexture2D.new()
	gtex.gradient = grad
	gtex.fill_to = Vector2(1, 0)
	fade.texture = gtex
	fade.stretch_mode = TextureRect.STRETCH_SCALE
	fade.anchor_left = 0.5
	fade.anchor_right = 0.5
	fade.anchor_bottom = 1.0
	fade.offset_right = 220
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page_root.add_child(fade)

	# Nom complet du peuple choisi, posé sur son illustration.
	_scene_name = UiTheme.title("", 40)
	_scene_name.anchor_left = 0.55
	_scene_name.anchor_right = 1.0
	_scene_name.offset_top = 80
	_scene_name.offset_right = -32
	_scene_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_scene_name.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_scene_name.add_theme_constant_override("shadow_outline_size", 6)
	page_root.add_child(_scene_name)

	var title := UiTheme.title("Nouvelle partie", 32)
	title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	title.grow_horizontal = Control.GROW_DIRECTION_BOTH
	title.offset_top = 18
	page_root.add_child(title)

	var left := VBoxContainer.new()
	left.position = Vector2(32, 74)
	left.add_theme_constant_override("separation", 10)
	page_root.add_child(left)
	left.add_child(_header("Peuples disponibles"))
	var grid := HBoxContainer.new()
	grid.add_theme_constant_override("separation", 4)
	left.add_child(grid)
	for fid in GameData.faction_ids() + [RANDOM_FACTION]:
		var f := GameData.faction(fid) if fid != RANDOM_FACTION else {"short": "Au hasard", "color": "#8fa3b8"}
		var col := Color.html(String(f.get("color", "#ffffff")))
		var tile := _faction_tile(fid, String(f.get("short", fid)), col)
		grid.add_child(tile)
		_faction_cards[fid] = tile

	var bottom := HBoxContainer.new()
	bottom.anchor_top = 1.0
	bottom.anchor_bottom = 1.0
	bottom.anchor_right = 1.0
	bottom.offset_left = 32
	bottom.offset_right = -32
	bottom.offset_top = -330
	bottom.offset_bottom = -96
	bottom.add_theme_constant_override("separation", 24)
	page_root.add_child(bottom)
	var traits := _bottom_block(bottom, "Affinité et traits", 470)
	var trow := HBoxContainer.new()
	trow.add_theme_constant_override("separation", 10)
	traits.add_child(trow)
	_faction_emblem = Widgets.Emblem.new(22)
	trow.add_child(_faction_emblem)
	_faction_registre = Label.new()
	trow.add_child(_faction_registre)
	traits.add_child(UiTheme.section("Trait du peuple"))
	_faction_trait = UiTheme.paragraph("", 440, 15)
	traits.add_child(_faction_trait)
	traits.add_child(UiTheme.section("Mondes préférés"))
	_faction_worlds = Label.new()
	traits.add_child(_faction_worlds)
	var lore_box := _bottom_block(bottom, "", 0)
	lore_box.get_parent().get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lore_header = lore_box.get_parent().get_parent().get_child(0) as Label
	_faction_lore = UiTheme.paragraph("", 420, 15)
	_faction_lore.add_theme_font_override("font", UiTheme.font(300))
	_faction_lore.add_theme_color_override("font_color", Color(UiTheme.TEXT, 0.85))
	lore_box.add_child(_faction_lore)
	var galaxy := _bottom_block(bottom, "Galaxie", 400, 0)
	var banner := Widgets.ArtSlot.new("new_game_galaxy", Vector2(400, 86), Color(0.45, 0.6, 0.95), "galaxy")
	galaxy.add_child(banner)
	var gbox := VBoxContainer.new()
	gbox.add_theme_constant_override("separation", 8)
	var gpad := MarginContainer.new()
	for side in ["left", "right", "top"]:
		gpad.add_theme_constant_override("margin_" + side, 14)
	gpad.add_child(gbox)
	galaxy.add_child(gpad)
	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", 10)
	gbox.add_child(seed_row)
	var seed_label := Label.new()
	seed_label.text = "Graine"
	seed_label.custom_minimum_size = Vector2(90, 0)
	seed_row.add_child(seed_label)
	_seed_edit = LineEdit.new()
	_seed_edit.placeholder_text = "au hasard (un nombre ou un mot)"
	_seed_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seed_edit.text_submitted.connect(func(_t: String) -> void: launch())
	seed_row.add_child(_seed_edit)
	var rivals := HBoxContainer.new()
	rivals.add_theme_constant_override("separation", 10)
	gbox.add_child(rivals)
	var rl := Label.new()
	rl.text = "Rivaux"
	rl.custom_minimum_size = Vector2(90, 0)
	rivals.add_child(rl)
	rivals.add_child(UiTheme.dim("les %d autres peuples, menés par l'ordinateur" % (GameData.faction_ids().size() - 1), 14))
	var size_row := HBoxContainer.new()
	size_row.add_theme_constant_override("separation", 10)
	gbox.add_child(size_row)
	var sl := Label.new()
	sl.text = "Taille"
	sl.custom_minimum_size = Vector2(90, 0)
	size_row.add_child(sl)
	size_row.add_child(UiTheme.dim("150 systèmes, spirale", 14))

	var back_b := Widgets.RoundButton.new("back", "Retour")
	back_b.tooltip_text = "Échap"
	back_b.anchor_top = 1.0
	back_b.anchor_bottom = 1.0
	back_b.offset_left = 28
	back_b.offset_top = -76
	back_b.offset_bottom = -76 + back_b.custom_minimum_size.y
	back_b.pressed.connect(func() -> void: show_page("home"))
	page_root.add_child(back_b)
	var go := Widgets.RoundButton.new("check", "Commencer")
	go.tooltip_text = "Entrée dans la graine, ou double-clic sur un portrait"
	go.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	go.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	go.offset_right = -32
	go.offset_left = -32 - go.custom_minimum_size.x
	go.offset_top = -76
	go.offset_bottom = -76 + go.custom_minimum_size.y
	go.pressed.connect(launch)
	page_root.add_child(go)


## Portrait cliquable d'un peuple : illustration (ou motif) et nom dans un bandeau.
func _faction_tile(fid: String, label: String, col: Color) -> Button:
	var tile := Button.new()
	tile.toggle_mode = true
	tile.focus_mode = Control.FOCUS_NONE
	tile.custom_minimum_size = TILE_SIZE
	var clear := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "hover_pressed"]:
		tile.add_theme_stylebox_override(st, clear)
	tile.pressed.connect(select_faction.bind(fid))
	tile.gui_input.connect(func(ev: InputEvent) -> void:
		var mb := ev as InputEventMouseButton
		if mb and mb.double_click and mb.button_index == MOUSE_BUTTON_LEFT:
			select_faction(fid)
			launch())
	var art := Widgets.ArtSlot.new("faction_" + fid, Vector2(TILE_SIZE.x, TILE_SIZE.y - 34), col, "faction")
	art.variant = fid.hash()
	tile.add_child(art)
	var bar := PanelContainer.new()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.position = Vector2(0, TILE_SIZE.y - 34)
	bar.size = Vector2(TILE_SIZE.x, 34)
	tile.add_child(bar)
	var name_l := Label.new()
	name_l.text = label.to_upper()
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_l.add_theme_font_override("font", UiTheme.font(400, 1))
	name_l.add_theme_font_size_override("font_size", 14)
	bar.add_child(name_l)
	tile.set_meta("bar", bar)
	tile.set_meta("label", name_l)
	tile.mouse_entered.connect(func() -> void: _style_tile(tile, tile.button_pressed, true))
	tile.mouse_exited.connect(func() -> void: _style_tile(tile, tile.button_pressed, false))
	_style_tile(tile, false, false)
	return tile


func _style_tile(tile: Button, on: bool, hot: bool) -> void:
	var bg := Color(UiTheme.ACCENT, 0.85) if on else Color(0.06, 0.08, 0.11, 0.95 if not hot else 1.0)
	if hot and not on:
		bg = Color(0.12, 0.16, 0.2, 1.0)
	(tile.get_meta("bar") as PanelContainer).add_theme_stylebox_override("panel", UiTheme.box(bg, Color(0, 0, 0, 0), 0, 0))
	(tile.get_meta("label") as Label).add_theme_color_override("font_color", Color(0.02, 0.05, 0.07) if on else UiTheme.TEXT)
	tile.modulate = Color.WHITE if on or hot else Color(0.82, 0.84, 0.88)


## En-tête de bloc en capitales, sans cadre.
func _header(text: String) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_override("font", UiTheme.font(400, 1))
	l.add_theme_font_size_override("font_size", 19)
	return l


## Bloc du bas : en-tête puis cadre translucide. Renvoie le conteneur du contenu.
func _bottom_block(parent: Control, heading: String, width: float, padding := 14) -> VBoxContainer:
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	if width > 0:
		outer.custom_minimum_size = Vector2(width, 0)
	parent.add_child(outer)
	outer.add_child(_header(heading))
	var frame := PanelContainer.new()
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_theme_stylebox_override("panel", UiTheme.box(Color(0.03, 0.04, 0.06, 0.75), Color(1, 1, 1, 0.1), padding, 1))
	outer.add_child(frame)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 6 if padding > 0 else 0)
	frame.add_child(body)
	return body


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
