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
const NEWS := "Prototype : galaxie, économie et colonisation jouables. Recherche et diplomatie en préparation."
## Rayon de la planète de l'accueil, en part de la hauteur de l'écran.
const PLANET_RADIUS := 0.6
const TILE_SIZE := Vector2(150, 270)
## Case « Au hasard » du choix de faction : un peuple est tiré au lancement.
const RANDOM_FACTION := "random"
const TYPE_LABELS := {"continental": "continental", "ocean": "océanique", "desert": "désertique", "arctic": "glaciaire",
	"toxic": "toxique", "gas_giant": "géante gazeuse", "barren": "stérile", "asteroids": "astéroïdes"}

var page := "home"
var selected_faction := ""

var _home: Control
var _items: Array[Widgets.OrbitMenuItem] = []
var _planet: ColorRect
var _orbits: Control
var _logo: Widgets.TitleRing
var _halo: TextureRect
var _tagline: Label
var _hint: PanelContainer
var _hint_label: Label
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
var _options_page: Control
var _options: OptionsPanel
var _faction_cards := {}
var _faction_trait: RichTextLabel
var _seed_edit: LineEdit
## Façon de jouer choisie pour la nouvelle partie (GameClock.MODE_*), et longueur des tours.
var time_mode: int = 0
var turn_days: int = 10
var _time_select: OptionButton
## Niveau des empires IA (AiLevels) et mode spectateur (aucun joueur humain : on regarde les IA).
var ai_level: String = AiLevels.default_id()
## Tempérament des IA (AiLevels.temperament) : leur attitude envers les autres empires.
var temperament: String = AiLevels.default_temperament()
var _temper_select: OptionButton
var spectator := false
var _ai_select: OptionButton
var _mode_select: OptionButton
## Victoires de la nouvelle partie : date limite du score en jours (0 = aucune) et victoires de peuple.
var deadline_days: int = Victory.default_deadline()
var people_victories := true
var _deadline_select: OptionButton
var _people_check: CheckBox


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
	# Accueil, sur le modèle des 4X « épurés » : une grande planète à gauche, les entrées posées le
	# long de son orbite, l'emblème-titre à droite, sur la galaxie qui dérive.
	_home = Control.new()
	_home.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_home.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_home)
	var shade := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0.0, 0.005, 0.02, 0.8))
	grad.set_color(1, Color(0.0, 0.005, 0.02, 0.1))
	var gtex := GradientTexture2D.new()
	gtex.gradient = grad
	gtex.fill_to = Vector2(1, 0)
	shade.texture = gtex
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_home.add_child(shade)
	_planet = ColorRect.new()
	_planet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var world := Planet.new()
	world.type = "continental"
	world.id = 7
	world.system_id = 3
	var mat := SystemView.make_planet_material(world)
	mat.set_shader_parameter("light_dir", Vector3(0.92, -0.3, 0.35))
	mat.set_shader_parameter("spin", 0.006)
	mat.set_shader_parameter("relief_scale", 4.2)
	_planet.material = mat
	_home.add_child(_planet)
	_orbits = Control.new()
	_orbits.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_orbits.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_orbits.draw.connect(_draw_orbits)
	_home.add_child(_orbits)

	# Halo sombre derrière l'emblème, pour qu'il se lise par-dessus la galaxie.
	_halo = TextureRect.new()
	var hgrad := Gradient.new()
	hgrad.set_color(0, Color(0.0, 0.005, 0.02, 0.85))
	hgrad.set_color(1, Color(0.0, 0.005, 0.02, 0.0))
	var htex := GradientTexture2D.new()
	htex.gradient = hgrad
	htex.fill = GradientTexture2D.FILL_RADIAL
	htex.fill_from = Vector2(0.5, 0.5)
	htex.fill_to = Vector2(1.0, 0.5)
	_halo.texture = htex
	_halo.stretch_mode = TextureRect.STRETCH_SCALE
	_halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_home.add_child(_halo)
	_logo = Widgets.TitleRing.new(170)
	_home.add_child(_logo)
	_tagline = UiTheme.dim(TAGLINE.to_upper(), 13)
	_tagline.add_theme_font_override("font", UiTheme.font(400, 4))
	_tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_home.add_child(_tagline)

	_resume = _menu_button("resume", "Reprendre la partie", "Revenir à la partie en cours, là où le temps s'est arrêté.", func() -> void: resume_requested.emit())
	_continue = _menu_button("load", "Continuer", "", func() -> void: continue_requested.emit())
	_menu_button("new", "Nouvelle partie", "Choisir un peuple et lancer une nouvelle galaxie.", func() -> void: show_page("new"))
	_menu_button("options", "Options", "Affichage, partie et commandes.", func() -> void: show_page("options"))
	_menu_button("quit", "Quitter", "Retourner au bureau. La galaxie attendra.", func() -> void: quit_requested.emit())
	_hint = PanelContainer.new()
	_hint.add_theme_stylebox_override("panel", UiTheme.box(Color(0.02, 0.03, 0.05, 0.92), Color(1, 1, 1, 0.12), 8, 1))
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.visible = false
	_home.add_child(_hint)
	_hint_label = UiTheme.paragraph("", 260, 14)
	_hint.add_child(_hint_label)

	var news := HBoxContainer.new()
	news.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	news.grow_horizontal = Control.GROW_DIRECTION_BOTH
	news.offset_top = -36
	news.offset_bottom = -12
	news.add_theme_constant_override("separation", 10)
	news.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_home.add_child(news)
	var bullet := Widgets.Dot.new(UiTheme.ACCENT, 8)
	bullet.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	news.add_child(bullet)
	news.add_child(UiTheme.dim(NEWS, 14))
	var version := UiTheme.dim("Prototype  ·  Godot 4.7", 13)
	version.anchor_left = 1.0
	version.anchor_right = 1.0
	version.anchor_top = 1.0
	version.anchor_bottom = 1.0
	version.offset_left = -220
	version.offset_right = -20
	version.offset_top = -34
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_home.add_child(version)
	root.resized.connect(_layout_home)
	_layout_home.call_deferred()

	_build_new_page(root)
	# Options en plein écran : la galaxie floute sous un voile, la page est centrée.
	_options_page = Control.new()
	_options_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_options_page.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(_options_page)
	var veil := ColorRect.new()
	veil.color = Color(0.01, 0.02, 0.035, 0.88)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_options_page.add_child(veil)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_options_page.add_child(center)
	center.anchor_bottom = 0.9
	_options = OptionsPanel.new()
	_options.back_requested.connect(func() -> void: show_page("home"))
	center.add_child(_options)
	# Boutons ronds dans les coins bas de l'écran, comme sur les grandes pages de réglages.
	var foot := _options.footer
	foot.get_parent().remove_child(foot)
	foot.anchor_top = 1.0
	foot.anchor_bottom = 1.0
	foot.anchor_right = 1.0
	foot.offset_left = 28
	foot.offset_right = -32
	foot.offset_top = -80
	foot.offset_bottom = -24
	_options_page.add_child(foot)
	show_page("home")


## Affiche le menu. can_resume : une partie est en cours derrière ; has_save : une sauvegarde existe.
func open(can_resume: bool, has_save: bool, save_label := "") -> void:
	_resume.visible = can_resume
	_continue.visible = not can_resume
	_continue.disabled = not has_save
	_continue.description = "Charger la sauvegarde rapide (%s)." % save_label if has_save else "Aucune sauvegarde pour l'instant."
	visible = true
	show_page("home")
	_layout_home()


func close() -> void:
	visible = false


func is_open() -> bool:
	return visible


func show_page(name: String) -> void:
	page = name
	_home.visible = name == "home"
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
	_faction_trait.text = trait_bbcode(f, col)
	var worlds := PackedStringArray()
	for t in f.get("preferred", []):
		worlds.append(String(TYPE_LABELS.get(t, t)))
	_faction_worlds.text = ", ".join(worlds) if not worlds.is_empty() else "—"
	var lore := String(f.get("lore", ""))
	# Victoire de peuple, ouverte par ses couches d'espèce.
	for vid in Victory.people_ids_for(f):
		lore += "\n\nVictoire de peuple, %s : %s" % [Victory.label(vid), Victory.rule_text(vid)]
	_faction_lore.text = lore


## Choix de la ligne « Temps » : 0 = temps réel, puis une entrée par longueur de tour.
func set_time_choice(index: int) -> void:
	_time_select.select(index)
	if index <= 0:
		time_mode = GameClock.MODE_REALTIME
	else:
		time_mode = GameClock.MODE_TURNS
		turn_days = GameClock.TURN_LENGTHS[mini(index - 1, GameClock.TURN_LENGTHS.size() - 1)]


func set_ai_level(id: String) -> void:
	if not AiLevels.is_valid(id):
		return
	ai_level = id
	_ai_select.select(AiLevels.ids().find(id))


func set_temperament(id: String) -> void:
	if not AiLevels.is_valid_temperament(id):
		return
	temperament = id
	_temper_select.select(AiLevels.temperament_ids().find(id))


func set_deadline(days: int) -> void:
	deadline_days = maxi(0, days)
	var opts := Victory.deadline_options()
	for i in opts.size():
		if int(opts[i]["days"]) == deadline_days:
			_deadline_select.select(i)


func set_people_victories(on: bool) -> void:
	people_victories = on
	_people_check.set_pressed_no_signal(on)


func set_spectator(on: bool) -> void:
	spectator = on
	_mode_select.select(1 if on else 0)


## Traits d'un peuple en texte enrichi : le nom de chaque trait en gras, à sa couleur.
static func trait_bbcode(f: Dictionary, col: Color) -> String:
	var lines := PackedStringArray()
	for t: Dictionary in f.get("traits", []):
		lines.append("[b][color=#%s]%s[/color][/b]  %s" % [col.lightened(0.35).to_html(false), t["name"], t["text"]])
	return "\n".join(lines) if not lines.is_empty() else String(f.get("trait", ""))


## Texte brut des traits affichés (pour les tests).
func trait_text() -> String:
	return _faction_trait.get_parsed_text()


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
	bottom.offset_top = -390
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
	traits.add_child(UiTheme.section("Traits du peuple"))
	_faction_trait = RichTextLabel.new()
	_faction_trait.bbcode_enabled = true
	_faction_trait.fit_content = true
	_faction_trait.scroll_active = false
	_faction_trait.custom_minimum_size = Vector2(440, 0)
	_faction_trait.add_theme_font_size_override("normal_font_size", 13)
	_faction_trait.add_theme_font_size_override("bold_font_size", 13)
	_faction_trait.add_theme_color_override("default_color", UiTheme.TEXT)
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
	var banner := Widgets.ArtSlot.new("new_game_galaxy", Vector2(400, 50), Color(0.45, 0.6, 0.95), "galaxy")
	banner.set_caption("150 systèmes, spirale", 15)
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
	_ai_select = OptionButton.new()
	_ai_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var tip := PackedStringArray(["Niveau des empires menés par l'ordinateur :"])
	for id in AiLevels.ids():
		_ai_select.add_item("IA %s" % AiLevels.label(id))
		tip.append("%s : %s" % [AiLevels.label(id), AiLevels.level(id).get("desc", "")])
	_ai_select.tooltip_text = "\n".join(tip)
	_ai_select.select(AiLevels.ids().find(ai_level))
	_ai_select.item_selected.connect(func(i: int) -> void: set_ai_level(AiLevels.ids()[i]))
	rivals.add_child(_ai_select)
	_temper_select = OptionButton.new()
	_temper_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var ttip := PackedStringArray(["Tempérament des IA envers les autres empires (ne change pas leurs ressources) :"])
	for id in AiLevels.temperament_ids():
		_temper_select.add_item(String(AiLevels.temperament(id)["label"]))
		ttip.append("%s : %s" % [AiLevels.temperament(id)["label"], AiLevels.temperament(id).get("desc", "")])
	ttip.append("Chaque peuple le décale d'un cran : le Chœur (zélé) et l'Essaim (vorace) vers l'agressif, Vael (conciliante) vers le pacifique.")
	_temper_select.tooltip_text = "\n".join(ttip)
	_temper_select.select(AiLevels.temperament_ids().find(temperament))
	_temper_select.item_selected.connect(func(i: int) -> void: set_temperament(AiLevels.temperament_ids()[i]))
	rivals.add_child(_temper_select)
	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 10)
	gbox.add_child(mode_row)
	var ml := Label.new()
	ml.text = "Partie"
	ml.custom_minimum_size = Vector2(90, 0)
	mode_row.add_child(ml)
	_mode_select = OptionButton.new()
	_mode_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mode_select.add_item("Jouer le peuple choisi")
	_mode_select.add_item("Spectateur : regarder les %d peuples s'affronter" % GameData.faction_ids().size())
	_mode_select.tooltip_text = "Spectateur : tous les peuples sont menés par l'ordinateur, la carte est entièrement visible\net le tableau des empires permet de suivre chacun d'eux (ou de voir à travers ses yeux)."
	_mode_select.item_selected.connect(func(i: int) -> void: set_spectator(i == 1))
	mode_row.add_child(_mode_select)
	var time_row := HBoxContainer.new()
	time_row.add_theme_constant_override("separation", 10)
	gbox.add_child(time_row)
	var tl := Label.new()
	tl.text = "Temps"
	tl.custom_minimum_size = Vector2(90, 0)
	time_row.add_child(tl)
	_time_select = OptionButton.new()
	_time_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_time_select.tooltip_text = "Temps réel : le temps file, Espace met en pause.\nTour par tour : le temps est arrêté pendant vos ordres ; Fin de tour (Espace) fait passer les jours du tour."
	_time_select.add_item("Temps réel pausable")
	for d in GameClock.TURN_LENGTHS:
		_time_select.add_item("Tour par tour, %d jours par tour" % d)
	_time_select.item_selected.connect(set_time_choice)
	time_row.add_child(_time_select)
	var vic_row := HBoxContainer.new()
	vic_row.add_theme_constant_override("separation", 10)
	gbox.add_child(vic_row)
	var vl := Label.new()
	vl.text = "Victoire"
	vl.custom_minimum_size = Vector2(90, 0)
	vic_row.add_child(vl)
	_deadline_select = OptionButton.new()
	_deadline_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_deadline_select.tooltip_text = "Date limite : à cette date, le meilleur score l'emporte si personne n'a gagné avant.\nConquête et domination sont toujours en jeu (F7 pour suivre la course)."
	for d: Dictionary in Victory.deadline_options():
		_deadline_select.add_item("Score : %s" % String(d["label"]).to_lower())
	_deadline_select.item_selected.connect(func(i: int) -> void: set_deadline(int(Victory.deadline_options()[i]["days"])))
	vic_row.add_child(_deadline_select)
	_people_check = CheckBox.new()
	_people_check.text = "De peuple"
	_people_check.focus_mode = Control.FOCUS_NONE
	_people_check.button_pressed = people_victories
	_people_check.tooltip_text = "Chaque peuple a une victoire qui lui est propre, tirée de ses couches d'espèce\n(l'Élu des routes, le Dernier Couplet, la Charte des Quarante et Un, la Moisson)."
	_people_check.toggled.connect(func(on: bool) -> void: people_victories = on)
	vic_row.add_child(_people_check)
	set_deadline(deadline_days)

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


func _menu_button(glyph: String, text: String, desc: String, action: Callable) -> Widgets.OrbitMenuItem:
	var b := Widgets.OrbitMenuItem.new(glyph, text, desc)
	b.pressed.connect(action)
	b.mouse_entered.connect(func() -> void: _show_hint(b))
	b.mouse_exited.connect(func() -> void: _hint.visible = false)
	_home.add_child(b)
	_items.append(b)
	return b


## Petite bulle d'aide à droite de l'entrée survolée.
func _show_hint(b: Widgets.OrbitMenuItem) -> void:
	if b.description == "":
		return
	_hint_label.text = b.description
	_hint.reset_size()
	_hint.position = b.position + Vector2(b.DIAMETER + 40.0, b.size.y - 4.0)
	_hint.visible = true


## Centre et rayon de la grande planète, selon la taille de l'écran.
func _planet_geometry() -> Array:
	var vs := _home.size if _home.size.y > 0 else Vector2(1600, 900)
	var r := vs.y * PLANET_RADIUS
	var c := Vector2(-r * 0.42, vs.y * 0.5)
	return [c, r, vs]


## Place la planète, les entrées sur leur orbite et l'emblème (à chaque redimensionnement).
func _layout_home() -> void:
	if _home == null:
		return
	var g := _planet_geometry()
	var c: Vector2 = g[0]
	var r: float = g[1]
	var vs: Vector2 = g[2]
	var body := float((_planet.material as ShaderMaterial).get_shader_parameter("body"))
	var side := r / body * 2.0
	_planet.size = Vector2(side, side)
	_planet.position = c - _planet.size * 0.5
	var orbit := r + vs.y * 0.09
	var shown: Array[Widgets.OrbitMenuItem] = []
	for b in _items:
		if b.visible:
			shown.append(b)
	var step := vs.y * 0.115
	for i in shown.size():
		var y := c.y + (float(i) - float(shown.size() - 1) * 0.5) * step
		var dy := y - c.y
		var x := c.x + sqrt(maxf(0.0, orbit * orbit - dy * dy))
		var b := shown[i]
		b.size = b.custom_minimum_size
		b.position = Vector2(x - b.DIAMETER * 0.5 - 2.0, y - b.size.y * 0.5)
	_logo.size = _logo.custom_minimum_size
	_halo.size = Vector2(760, 760)
	_halo.position = Vector2(vs.x * 0.66, vs.y * 0.47) - _halo.size * 0.5
	_logo.position = Vector2(vs.x * 0.66, vs.y * 0.45) - _logo.size * 0.5
	_tagline.size = Vector2(600, 20)
	_tagline.position = Vector2(vs.x * 0.66 - 300.0, vs.y * 0.45 + _logo.radius + 48.0)
	_orbits.queue_redraw()


## Fines orbites autour de la planète, dont celle qui porte les entrées.
func _draw_orbits() -> void:
	var g := _planet_geometry()
	var c: Vector2 = g[0]
	var r: float = g[1]
	var vs: Vector2 = g[2]
	_orbits.draw_arc(c, r + vs.y * 0.09, -PI * 0.5, PI * 0.5, 160, Color(1, 1, 1, 0.22), 1.2, true)
	_orbits.draw_arc(c, r + vs.y * 0.2, -PI * 0.5, PI * 0.5, 160, Color(1, 1, 1, 0.08), 1.0, true)
	_orbits.draw_arc(c, r * 1.01, -PI * 0.5, PI * 0.5, 160, Color(0.55, 0.8, 1.0, 0.18), 2.0, true)

