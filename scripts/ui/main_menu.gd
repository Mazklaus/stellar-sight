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
const TILE_SIZE := Vector2(150, 240)
## Largeur de la rangée de portraits (cinq visibles).
const TILE_STRIP_WIDTH := 5 * 150 + 4 * 4
## Largeur des colonnes de la liste des rivaux.
const SLOT_COL_FACTION := 202.0
const SLOT_COL_COLOR := 96.0
const SLOT_COL_LEVEL := 160.0
const SLOT_COL_TEMPER := 158.0
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
var _tile_strip: ScrollContainer
var _tile_grid: HBoxContainer
## Page « Peuples » : bibliothèque et éditeur d'espèces.
var _species: SpeciesEditor
## Page à rouvrir en quittant l'éditeur (accueil, ou Nouvelle partie si l'on venait de là).
var _species_return := "home"
## Empires rivaux, un emplacement chacun (dans l'ordre) : {"faction": peuple ou RANDOM_FACTION,
## "color": code html ou "" (automatique), "level": niveau d'IA ou "" (le niveau par défaut),
## "temper": tempérament ou "" (le tempérament par défaut)}. Résolus au lancement par empire_setup().
var slots: Array[Dictionary] = []
## Plusieurs empires peuvent-ils partager un peuple (y compris le vôtre) ?
var allow_duplicates := false
var _slot_list: VBoxContainer
var _slot_count: Label
var _slot_note: Label
var _dup_check: CheckBox
var _add_slot: Button
var _slots_dirty := false
var _slot_adv: PopupPanel
var _slot_adv_index := -1
var _slot_adv_title: Label
var _slot_start_select: OptionButton
var _slot_dist_select: OptionButton
## Réglages de la galaxie (GalaxySettings) : taille, forme, routes, départs, mondes garantis.
var galaxy_settings: Dictionary = GalaxySettings.defaults()
var _galaxy_banner: Widgets.ArtSlot
var _size_select: OptionButton
var _shape_select: OptionButton
var _lanes_select: OptionButton
var _placement_select: OptionButton
var _guaranteed_select: OptionButton
var _placement_desc: Label
var _galaxy_adv: PopupPanel
## Nombre d'empires au plus dans une galaxie (joueur compris).
const MAX_EMPIRES := 12
## Départ et distance au joueur d'un rival (réglages derrière le « + » de sa ligne).
const START_LABELS := {"": "Normal", "avance": "Avancé"}
const DISTANCE_LABELS := {"": "Sans préférence", "proche": "Proche de vous", "lointain": "Loin de vous", "hasard": "Au hasard"}
## Noms des couleurs de Empire.PALETTE, dans le même ordre.
const COLOR_NAMES := ["Or", "Pourpre", "Azur", "Vert", "Violet", "Orange", "Turquoise", "Rose", "Blanc",
	"Brun", "Gris", "Lime"]
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
## Victoires classiques en jeu et alliés qui gagnent ensemble (GameState.victory_rules).
var victories := {"conquete": true, "domination": true, "allies": true}
var _victory_checks := {}
## Difficulté progressive : les bonus des IA Expert et Légende montent avec le temps.
var ai_scaling := false
var _scaling_check: CheckBox

## Réglages enregistrés (dernière partie et préréglages du joueur), dans un fichier JSON de user://.
const PRESETS_PATH := "user://new_game_presets.json"
## Préfixe des codes de partie (graine et réglages, à partager).
const CODE_PREFIX := "SS1-"
var presets_path := PRESETS_PATH
var _quick: Widgets.OrbitMenuItem
var _preset_select: OptionButton
var _preset_popup: PopupPanel
var _preset_name: LineEdit
var _preset_delete: Button
var _code_popup: PopupPanel
var _code_out: LineEdit
var _code_in: LineEdit
var _code_note: Label
var _applying := false


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
	_quick = _menu_button("quick", "Partie rapide", "Relancer aussitôt avec les réglages de votre dernière partie, sur une nouvelle galaxie.", quick_game)
	_menu_button("new", "Nouvelle partie", "Choisir un peuple et lancer une nouvelle galaxie.", func() -> void: show_page("new"))
	_menu_button("species", "Peuples", "Créer, modifier et ranger vos propres peuples : couches d'espèce, traits, portrait.", func() -> void: open_species("home"))
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
	_species = SpeciesEditor.new()
	root.add_child(_species)
	_species.back_requested.connect(func() -> void: show_page(_species_return))
	_species.library_changed.connect(_on_library_changed)
	show_page("home")


## Affiche le menu. can_resume : une partie est en cours derrière ; has_save : une sauvegarde existe.
func open(can_resume: bool, has_save: bool, save_label := "") -> void:
	_quick.visible = not last_settings().is_empty()
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
	if _species:
		_species.visible = name == "species"
	if name == "options":
		_options.sync()
	if name == "new" and selected_faction == "":
		select_faction(GameData.faction_ids()[0])


## Échap : revient à l'accueil depuis une sous-page. Renvoie false si l'on était déjà à l'accueil.
func back() -> bool:
	if page == "species":
		show_page(_species_return)
		return true
	if page != "home":
		show_page("home")
		return true
	return false


## Ouvre l'éditeur de peuples ; Retour (ou Échap) ramène à la page d'où l'on vient.
func open_species(from: String) -> void:
	_species_return = from
	show_page("species")
	if from == "new" and not GameData.is_official(selected_faction) and selected_faction != RANDOM_FACTION:
		_species.open_saved(selected_faction)


## Un peuple a été enregistré ou supprimé : la rangée de portraits et la liste des rivaux se refont.
func _on_library_changed() -> void:
	var known := GameData.all_faction_ids()
	# Un rival dont le peuple a été supprimé est tiré au hasard.
	for s in slots:
		if s["faction"] != RANDOM_FACTION and not known.has(s["faction"]):
			s["faction"] = RANDOM_FACTION
	_rebuild_tiles()
	_refresh_slots()
	if selected_faction != RANDOM_FACTION and not known.has(selected_faction):
		selected_faction = ""
	if selected_faction != "":
		select_faction(selected_faction)
	elif page == "new":
		select_faction(GameData.faction_ids()[0])


## Emplacements par défaut : un rival par peuple officiel (le vôtre sera retiré au lancement).
static func default_slots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for fid in GameData.faction_ids():
		out.append(new_slot(fid))
	return out


static func new_slot(fid: String) -> Dictionary:
	return {"faction": fid, "color": "", "level": "", "temper": "", "start": "", "distance": ""}


## Ajoute un rival (au hasard par défaut). Refuse au-delà de MAX_EMPIRES - 1 rivaux.
func add_slot(fid := RANDOM_FACTION) -> bool:
	if slots.size() >= MAX_EMPIRES - 1:
		return false
	slots.append(new_slot(fid))
	_refresh_slots()
	return true


## Retire un rival. Refuse de retirer le dernier.
func remove_slot(index: int) -> bool:
	if slots.size() <= 1 or index < 0 or index >= slots.size():
		return false
	slots.remove_at(index)
	_refresh_slots()
	return true


## Change un réglage d'un rival : "faction", "color", "level", "temper", "start" (départ : "" ou
## "avance") ou "distance" ("", "proche", "lointain", "hasard") ; "" = par défaut.
func set_slot(index: int, key: String, value: String) -> bool:
	if index < 0 or index >= slots.size() or not slots[index].has(key):
		return false
	match key:
		"faction":
			if value != RANDOM_FACTION and GameData.faction(value).is_empty():
				return false
		"level":
			if value != "" and not AiLevels.is_valid(value):
				return false
		"temper":
			if value != "" and not AiLevels.is_valid_temperament(value):
				return false
		"color":
			if value != "" and not Empire.PALETTE.has(value):
				return false
		"start":
			if not START_LABELS.has(value):
				return false
		"distance":
			if not DISTANCE_LABELS.has(value):
				return false
	slots[index][key] = value
	_refresh_slots()
	return true


## Tous les rivaux tirés au hasard.
func randomize_slots() -> void:
	for s in slots:
		s["faction"] = RANDOM_FACTION
	_refresh_slots()


## Tous les rivaux reprennent le niveau et le tempérament par défaut.
func apply_defaults_to_all() -> void:
	for s in slots:
		s["level"] = ""
		s["temper"] = ""
	_refresh_slots()


func set_duplicates(on: bool) -> void:
	allow_duplicates = on
	if _dup_check:
		_dup_check.set_pressed_no_signal(on)
	_refresh_slots()


## Ajoute un rival de ce peuple, ou retire le premier qui l'a déjà (raccourci des tests et outils).
func toggle_rival(fid: String) -> bool:
	for i in slots.size():
		if slots[i]["faction"] == fid:
			return remove_slot(i)
	return add_slot(fid)


## Les empires de la nouvelle partie, prêts pour GameState.create : peuples des rivaux (les « au hasard »
## tirés avec la graine, pour qu'une graine redonne la même galaxie), et par indice d'empire (0 = vous)
## niveau d'IA, tempérament et couleur. Sans doublons permis, un rival qui reprend votre peuple ou
## celui d'un rival précédent est retiré, et les tirages évitent les peuples déjà pris.
func empire_setup(player: String, seed_value := 0) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var used: Array[String] = []
	if player != "":
		used.append(player)
	var picked: Array[String] = []
	picked.resize(slots.size())
	for i in slots.size():
		var fid := String(slots[i]["faction"])
		if fid == RANDOM_FACTION or GameData.faction(fid).is_empty():
			continue
		if allow_duplicates or not used.has(fid):
			picked[i] = fid
			used.append(fid)
	for i in slots.size():
		var fid := String(slots[i]["faction"])
		if fid != RANDOM_FACTION and not GameData.faction(fid).is_empty():
			continue
		var pool: Array[String] = []
		for f in GameData.all_faction_ids():
			if allow_duplicates or not used.has(f):
				pool.append(f)
		if pool.is_empty():
			continue
		picked[i] = pool[rng.randi_range(0, pool.size() - 1)]
		used.append(picked[i])
	var out := {"rivals": [] as Array[String], "ai_levels": [ai_level], "temperaments": [temperament],
			"colors": [""], "starts": [""], "distances": [""], "duplicates": allow_duplicates}
	for i in slots.size():
		if picked[i] == "" or (out["rivals"] as Array).size() >= MAX_EMPIRES - 1:
			continue
		var s := slots[i]
		(out["rivals"] as Array).append(picked[i])
		(out["ai_levels"] as Array).append(s["level"] if s["level"] != "" else ai_level)
		(out["temperaments"] as Array).append(s["temper"] if s["temper"] != "" else temperament)
		(out["colors"] as Array).append(s["color"])
		(out["starts"] as Array).append(String(s.get("start", "")))
		(out["distances"] as Array).append(String(s.get("distance", "")))
	# Tous les rivaux retirés : on reprend les officiels plutôt qu'une galaxie vide.
	if (out["rivals"] as Array).is_empty():
		for fid in GameData.faction_ids():
			if fid != player:
				(out["rivals"] as Array).append(fid)
				(out["ai_levels"] as Array).append(ai_level)
				(out["temperaments"] as Array).append(temperament)
				(out["colors"] as Array).append("")
				(out["starts"] as Array).append("")
				(out["distances"] as Array).append("")
	return out


## Peuples des rivaux engagés pour ce peuple joué (tirages au hasard faits avec la graine 0).
func rival_ids(player := "") -> Array[String]:
	var out: Array[String] = []
	out.assign(empire_setup(player)["rivals"])
	return out


## Ce que deviendront les rivaux au lancement, en clair (doublons retirés), sous la liste.
func slots_note() -> String:
	var notes := PackedStringArray()
	var dup := _duplicates_note()
	if dup != "":
		notes.append(dup)
	var rec := GalaxySettings.recommended_empires(galaxy_settings)
	if slots.size() + 1 > rec:
		notes.append("Galaxie %s : %d empires conseillés, vous en prévoyez %d. Ça va être serré." % [
			String(GalaxySettings.entry("size", galaxy_settings["size"])["label"]).to_lower(), rec, slots.size() + 1])
	return "\n".join(notes)


func _duplicates_note() -> String:
	if allow_duplicates:
		return ""
	var seen: Array[String] = []
	if selected_faction != "" and selected_faction != RANDOM_FACTION:
		seen.append(selected_faction)
	var dropped := PackedStringArray()
	for s in slots:
		var fid := String(s["faction"])
		if fid == RANDOM_FACTION:
			continue
		if seen.has(fid):
			dropped.append(String(GameData.faction(fid).get("short", fid)))
		else:
			seen.append(fid)
	if dropped.is_empty():
		return ""
	return "Déjà pris, retiré au lancement : %s (cochez « Peuples en double » pour les garder)." % ", ".join(dropped)


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
		_refresh_slots()
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
	_refresh_slots()


## Choix de la ligne « Temps » : 0 = temps réel, puis une entrée par longueur de tour.
func set_time_choice(index: int) -> void:
	_time_select.select(index)
	if index <= 0:
		time_mode = GameClock.MODE_REALTIME
	else:
		time_mode = GameClock.MODE_TURNS
		turn_days = GameClock.TURN_LENGTHS[mini(index - 1, GameClock.TURN_LENGTHS.size() - 1)]
	_refresh_preset()


## Niveau d'IA par défaut des rivaux (ceux restés sur « Par défaut », et tous en spectateur).
func set_ai_level(id: String) -> void:
	if not AiLevels.is_valid(id):
		return
	ai_level = id
	_ai_select.select(AiLevels.ids().find(id))
	_refresh_slots()


## Tempérament par défaut des rivaux.
func set_temperament(id: String) -> void:
	if not AiLevels.is_valid_temperament(id):
		return
	temperament = id
	_temper_select.select(AiLevels.temperament_ids().find(id))
	_refresh_slots()


func set_deadline(days: int) -> void:
	deadline_days = maxi(0, days)
	_refresh_preset()
	var opts := Victory.deadline_options()
	for i in opts.size():
		if int(opts[i]["days"]) == deadline_days:
			_deadline_select.select(i)


func set_people_victories(on: bool) -> void:
	people_victories = on
	_people_check.set_pressed_no_signal(on)
	_refresh_preset()


func _victory_check(key: String, tip: Array) -> CheckBox:
	var c := CheckBox.new()
	c.text = String(tip[0])
	c.tooltip_text = String(tip[1])
	c.focus_mode = Control.FOCUS_NONE
	c.button_pressed = bool(victories[key])
	c.toggled.connect(func(on: bool) -> void: set_victory(key, on))
	c.custom_minimum_size = Vector2(140, 0)
	_victory_checks[key] = c
	return c


## Met en jeu ou retire une victoire ("conquete", "domination"), ou fait gagner les alliés ensemble ("allies").
func set_victory(key: String, on: bool) -> bool:
	if not victories.has(key):
		return false
	victories[key] = on
	if _victory_checks.has(key):
		(_victory_checks[key] as CheckBox).set_pressed_no_signal(on)
	_refresh_preset()
	return true


func set_ai_scaling(on: bool) -> void:
	ai_scaling = on
	if _scaling_check:
		_scaling_check.set_pressed_no_signal(on)
	_refresh_preset()


## Règles de la partie pour GameState.create (en plus des empires et de la galaxie).
func game_options() -> Dictionary:
	return {"victories": victories.duplicate(), "ai_scaling": ai_scaling}


func set_spectator(on: bool) -> void:
	spectator = on
	_mode_select.select(1 if on else 0)
	_refresh_slots()


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
		var ids := GameData.all_faction_ids()
		faction = ids[randi() % ids.size()]
	var store := _load_presets()
	store["last"] = _without_seed(settings())
	_save_presets(store)
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
	_build_presets_bar(page_root)

	# Écran unique en blocs, à la Endless Space 2 : Empire (peuple joué) en haut à gauche, Rivaux en
	# haut à droite, puis en bas les traits du peuple, la Galaxie, la Partie et la Victoire.
	_scene_art.modulate = Color(1, 1, 1, 0.5)  # l'illustration passe en fond, sous le bloc Rivaux
	_scene_name.visible = false
	var left := VBoxContainer.new()
	left.position = Vector2(32, 74)
	left.add_theme_constant_override("separation", 10)
	page_root.add_child(left)
	left.add_child(_header("Empire"))
	# Rangée défilante : les peuples créés s'ajoutent à droite des officiels.
	_tile_strip = ScrollContainer.new()
	_tile_strip.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(_tile_strip)
	_tile_grid = HBoxContainer.new()
	_tile_grid.add_theme_constant_override("separation", 4)
	_tile_strip.add_child(_tile_grid)
	_rebuild_tiles()
	# Sous les portraits : le nom du peuple choisi et l'éditeur de peuples.
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 12)
	tools.custom_minimum_size = Vector2(TILE_STRIP_WIDTH, 0)
	left.add_child(tools)
	var name_holder := _scene_name.get_parent()
	if name_holder:
		name_holder.remove_child(_scene_name)
	_scene_name.visible = true
	_scene_name.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_scene_name.add_theme_font_size_override("font_size", 26)
	_scene_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_scene_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scene_name.clip_text = true
	tools.add_child(_scene_name)
	var create_b := Button.new()
	create_b.text = "Créer ou modifier un peuple…"
	create_b.focus_mode = Control.FOCUS_NONE
	create_b.tooltip_text = "Ouvre l'éditeur de peuples (le peuple créé sélectionné s'y ouvre)."
	create_b.pressed.connect(func() -> void: open_species("new"))
	tools.add_child(create_b)
	# Histoire du peuple (et sa victoire de peuple), dans une petite zone qui défile.
	var lore_scroll := ScrollContainer.new()
	lore_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lore_scroll.custom_minimum_size = Vector2(TILE_STRIP_WIDTH, 92)
	left.add_child(lore_scroll)
	var lore_box := VBoxContainer.new()
	lore_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lore_scroll.add_child(lore_box)
	_lore_header = UiTheme.section("")
	lore_box.add_child(_lore_header)
	_faction_lore = UiTheme.paragraph("", TILE_STRIP_WIDTH - 16, 14)
	_faction_lore.add_theme_font_override("font", UiTheme.font(300))
	_faction_lore.add_theme_color_override("font_color", Color(UiTheme.TEXT, 0.85))
	lore_box.add_child(_faction_lore)

	_build_rivals_block(page_root)

	var bottom := HBoxContainer.new()
	bottom.anchor_top = 1.0
	bottom.anchor_bottom = 1.0
	bottom.anchor_right = 1.0
	bottom.offset_left = 32
	bottom.offset_right = -32
	bottom.offset_top = -330
	bottom.offset_bottom = -96
	bottom.add_theme_constant_override("separation", 20)
	page_root.add_child(bottom)
	var traits := _bottom_block(bottom, "Affinité et traits", 0)
	traits.get_parent().get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	# Hauteur fixe qui défile : un peuple créé peut aligner plus de traits qu'un officiel.
	_faction_trait.fit_content = false
	_faction_trait.scroll_active = true
	_faction_trait.custom_minimum_size = Vector2(380, 104)
	_faction_trait.add_theme_font_size_override("normal_font_size", 13)
	_faction_trait.add_theme_font_size_override("bold_font_size", 13)
	_faction_trait.add_theme_color_override("default_color", UiTheme.TEXT)
	traits.add_child(_faction_trait)
	var wrow := HBoxContainer.new()
	wrow.add_theme_constant_override("separation", 8)
	traits.add_child(wrow)
	var wl := UiTheme.section("Mondes préférés")
	wrow.add_child(wl)
	_faction_worlds = Label.new()
	wrow.add_child(_faction_worlds)

	# Galaxie : taille, forme, graine ; routes, départs et mondes garantis derrière « Avancé ».
	var galaxy := _bottom_block(bottom, "Galaxie", 330, 0)
	_galaxy_banner = Widgets.ArtSlot.new("new_game_galaxy", Vector2(330, 38), Color(0.45, 0.6, 0.95), "galaxy")
	galaxy.add_child(_galaxy_banner)
	var gbox := _block_rows(galaxy)
	_size_select = _settings_select("size")
	_labeled_row(gbox, "Taille", _size_select)
	_shape_select = _settings_select("shape")
	_labeled_row(gbox, "Forme", _shape_select)
	_seed_edit = LineEdit.new()
	_seed_edit.placeholder_text = "graine au hasard"
	_seed_edit.tooltip_text = "Un nombre ou un mot. La même graine redonne la même galaxie, et les mêmes rivaux tirés au hasard."
	_seed_edit.text_submitted.connect(func(_t: String) -> void: launch())
	_labeled_row(gbox, "Graine", _seed_edit)
	var adv := Button.new()
	adv.text = "+ Avancé"
	adv.focus_mode = Control.FOCUS_NONE
	adv.tooltip_text = "Routes, placement des départs, mondes habitables garantis."
	adv.pressed.connect(open_galaxy_advanced)
	_seed_edit.get_parent().add_child(adv)
	_build_galaxy_advanced(page_root)
	_refresh_galaxy()

	# Partie : jouer ou regarder, temps réel ou tour par tour.
	var game := _block_rows(_bottom_block(bottom, "Partie", 330, 0))
	_mode_select = OptionButton.new()
	_mode_select.clip_text = true
	_mode_select.add_item("Jouer le peuple choisi")
	_mode_select.add_item("Spectateur : les empires s'affrontent sans vous")
	_mode_select.tooltip_text = "Spectateur : tous les peuples sont menés par l'ordinateur, la carte est entièrement visible\net le tableau des empires permet de suivre chacun d'eux (ou de voir à travers ses yeux).\nVotre peuple est alors mené par une IA du niveau par défaut."
	_mode_select.item_selected.connect(func(i: int) -> void: set_spectator(i == 1))
	_labeled_row(game, "Mode", _mode_select)
	_time_select = OptionButton.new()
	_time_select.clip_text = true
	_time_select.tooltip_text = "Temps réel : le temps file, Espace met en pause.\nTour par tour : le temps est arrêté pendant vos ordres ; Fin de tour (Espace) fait passer les jours du tour."
	_time_select.add_item("Temps réel pausable")
	for d in GameClock.TURN_LENGTHS:
		_time_select.add_item("Tour par tour, %d jours" % d)
	_time_select.item_selected.connect(set_time_choice)
	_labeled_row(game, "Temps", _time_select)
	_scaling_check = CheckBox.new()
	_scaling_check.text = "Difficulté progressive"
	_scaling_check.focus_mode = Control.FOCUS_NONE
	_scaling_check.tooltip_text = "Les bonus des IA Expert et Légende partent de zéro et atteignent leur pleine valeur\naprès %d ans de partie (comme la difficulté progressive de Stellaris).\nPas d'avance de départ : elles vous laissent le temps de vous installer." % (AiLevels.scaling_days() / GameCalendar.DAYS_PER_YEAR)
	_scaling_check.toggled.connect(set_ai_scaling)
	game.add_child(_scaling_check)

	# Victoire : date limite du score, victoires de peuple.
	var vic := _block_rows(_bottom_block(bottom, "Victoire", 330, 0))
	_deadline_select = OptionButton.new()
	_deadline_select.clip_text = true
	_deadline_select.tooltip_text = "Date limite : à cette date, le meilleur score l'emporte si personne n'a gagné avant.\nLes autres victoires se cochent en dessous (F7 pour suivre la course)."
	for d: Dictionary in Victory.deadline_options():
		_deadline_select.add_item("Score : %s" % String(d["label"]).to_lower())
	_deadline_select.item_selected.connect(func(i: int) -> void: set_deadline(int(Victory.deadline_options()[i]["days"])))
	_labeled_row(vic, "Limite", _deadline_select)
	_people_check = CheckBox.new()
	_people_check.text = "Victoires de peuple"
	_people_check.focus_mode = Control.FOCUS_NONE
	_people_check.button_pressed = people_victories
	_people_check.tooltip_text = "Chaque peuple a une victoire qui lui est propre, tirée de ses couches d'espèce\n(l'Élu des routes, le Dernier Couplet, la Charte des Quarante et Un, la Moisson)."
	_people_check.toggled.connect(set_people_victories)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 2)
	vic.add_child(grid)
	var vtips := {
		"conquete": ["Conquête", "Prendre et tenir toutes les capitales d'origine rivales (ou rester seul en vie)."],
		"domination": ["Domination", "Tenir une grande part des systèmes de la galaxie pendant un temps."],
		"allies": ["Alliés ensemble", "Les alliés additionnent leurs conquêtes et leurs systèmes, et gagnent ensemble\n(Endless Space 2). Décoché : chacun pour soi, même allié."],
	}
	for key in ["conquete", "domination"]:
		grid.add_child(_victory_check(key, vtips[key]))
	grid.add_child(_people_check)
	_people_check.text = "De peuple"
	grid.add_child(_victory_check("allies", vtips["allies"]))
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


## Refait la rangée de portraits : officiels, peuples créés de la bibliothèque (user://species/), « Au hasard ».
func _rebuild_tiles() -> void:
	for c in _tile_grid.get_children():
		_tile_grid.remove_child(c)
		c.queue_free()
	_faction_cards.clear()
	_tile_strip.custom_minimum_size = Vector2(TILE_STRIP_WIDTH, TILE_SIZE.y + (14 if GameData.library_faction_ids().size() > 0 else 0))
	for fid in GameData.all_faction_ids() + [RANDOM_FACTION]:
		var f := GameData.faction(fid) if fid != RANDOM_FACTION else {"short": "Au hasard", "color": "#8fa3b8"}
		var col := Color.html(String(f.get("color", "#ffffff")))
		var tile := _faction_tile(fid, String(f.get("short", fid)), col)
		_tile_grid.add_child(tile)
		_faction_cards[fid] = tile


## Change un réglage de la galaxie ("size", "shape", "lanes", "placement", "guaranteed").
func set_galaxy(key: String, value: Variant) -> bool:
	var next := galaxy_settings.duplicate()
	next[key] = value
	next = GalaxySettings.normalize(next)
	if next[key] != value and str(next[key]) != str(value):
		return false
	galaxy_settings = next
	_refresh_galaxy()
	_refresh_slots()
	return true


func open_galaxy_advanced() -> void:
	_galaxy_adv.reset_size()
	_galaxy_adv.popup_centered()


## Liste d'un réglage de la galaxie, dont chaque entrée porte son identifiant.
func _settings_select(key: String) -> OptionButton:
	var b := OptionButton.new()
	b.clip_text = true
	var tip := PackedStringArray()
	for e: Dictionary in GalaxySettings._table(key):
		var label := String(e["label"])
		if key == "size":
			label = "%s : %d systèmes" % [label, int(e["systems"])]
			tip.append("%s : %d systèmes, %d empires conseillés" % [e["label"], e["systems"], e["empires"]])
		elif e.has("desc"):
			tip.append("%s : %s" % [e["label"], String(e["desc"]).replace("\n", " ")])
		b.add_item(label)
		b.set_item_metadata(b.item_count - 1, e["id"])
	b.tooltip_text = "\n".join(tip)
	b.item_selected.connect(func(i: int) -> void: set_galaxy(key, String(b.get_item_metadata(i))))
	return b


## Fenêtre « Galaxie : réglages avancés », le « + » du bloc à la Endless Space 2.
func _build_galaxy_advanced(page_root: Control) -> void:
	_galaxy_adv = PopupPanel.new()
	_galaxy_adv.add_theme_stylebox_override("panel", UiTheme.box(Color(0.03, 0.04, 0.06, 1.0), Color(1, 1, 1, 0.16), 18, 1))
	page_root.add_child(_galaxy_adv)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(520, 0)
	box.add_theme_constant_override("separation", 10)
	_galaxy_adv.add_child(box)
	box.add_child(_header("Galaxie : réglages avancés"))
	_lanes_select = _settings_select("lanes")
	_labeled_row(box, "Routes", _lanes_select)
	_placement_select = _settings_select("placement")
	_labeled_row(box, "Départs", _placement_select)
	_placement_desc = UiTheme.paragraph("", 500, 13)
	_placement_desc.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	box.add_child(_placement_desc)
	_guaranteed_select = OptionButton.new()
	for k in GalaxySettings.MAX_GUARANTEED + 1:
		_guaranteed_select.add_item("Aucun" if k == 0 else "%d monde%s de votre type à 2 sauts au plus" % [k, "s" if k > 1 else ""])
	_guaranteed_select.tooltip_text = "Des planètes d'un type préféré de chaque peuple, près de son départ (Stellaris en met 2).\nAucun : la galaxie telle qu'elle est tirée."
	_guaranteed_select.item_selected.connect(func(i: int) -> void: set_galaxy("guaranteed", i))
	_labeled_row(box, "Garantis", _guaranteed_select)
	var close := Button.new()
	close.text = "Fermer"
	close.focus_mode = Control.FOCUS_NONE
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	close.pressed.connect(func() -> void: _galaxy_adv.hide())
	box.add_child(close)


## Remet les listes du bloc Galaxie et de la fenêtre avancée sur les réglages, et la légende.
func _refresh_galaxy() -> void:
	_refresh_preset()
	if _size_select == null:
		return
	for pair in [[_size_select, "size"], [_shape_select, "shape"], [_lanes_select, "lanes"], [_placement_select, "placement"]]:
		var b: OptionButton = pair[0]
		for i in b.item_count:
			if String(b.get_item_metadata(i)) == String(galaxy_settings[pair[1]]):
				b.select(i)
	_guaranteed_select.select(int(galaxy_settings["guaranteed"]))
	_placement_desc.text = String(GalaxySettings.entry("placement", galaxy_settings["placement"])["desc"])
	_galaxy_banner.set_caption("%s · %d empires conseillés" % [GalaxySettings.summary(galaxy_settings),
			GalaxySettings.recommended_empires(galaxy_settings)], 13)


## Bloc « Empires rivaux », en haut à droite : réglages par défaut, puis une ligne par rival
## (peuple ou au hasard, couleur, niveau d'IA, tempérament), à la Galactic Civilizations IV.
func _build_rivals_block(page_root: Control) -> void:
	var outer := VBoxContainer.new()
	outer.anchor_left = 0.5
	outer.anchor_right = 1.0
	outer.offset_left = 26
	outer.offset_right = -32
	outer.offset_top = 74
	outer.add_theme_constant_override("separation", 8)
	page_root.add_child(outer)
	var head := HBoxContainer.new()
	outer.add_child(head)
	var hl := _header("Empires rivaux")
	hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(hl)
	_slot_count = Label.new()
	_slot_count.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	head.add_child(_slot_count)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UiTheme.box(Color(0.03, 0.04, 0.06, 0.82), Color(1, 1, 1, 0.1), 12, 1))
	outer.add_child(frame)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	frame.add_child(body)

	# Réglages par défaut : ils valent pour chaque rival resté sur « Par défaut ».
	var defaults := HBoxContainer.new()
	defaults.add_theme_constant_override("separation", 8)
	body.add_child(defaults)
	var dl := Label.new()
	dl.text = "Par défaut"
	dl.custom_minimum_size = Vector2(96, 0)
	defaults.add_child(dl)
	_ai_select = OptionButton.new()
	_ai_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var tip := PackedStringArray(["Niveau par défaut des empires menés par l'ordinateur :"])
	for id in AiLevels.ids():
		_ai_select.add_item("IA %s" % AiLevels.label(id))
		tip.append("%s : %s" % [AiLevels.label(id), AiLevels.level(id).get("desc", "")])
	_ai_select.tooltip_text = "\n".join(tip)
	_ai_select.select(AiLevels.ids().find(ai_level))
	_ai_select.item_selected.connect(func(i: int) -> void: set_ai_level(AiLevels.ids()[i]))
	defaults.add_child(_ai_select)
	_temper_select = OptionButton.new()
	_temper_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_temper_select.tooltip_text = _temper_tip("Tempérament par défaut des IA envers les autres empires (ne change pas leurs ressources) :")
	for id in AiLevels.temperament_ids():
		_temper_select.add_item(String(AiLevels.temperament(id)["label"]))
	_temper_select.select(AiLevels.temperament_ids().find(temperament))
	_temper_select.item_selected.connect(func(i: int) -> void: set_temperament(AiLevels.temperament_ids()[i]))
	defaults.add_child(_temper_select)
	var apply_b := Button.new()
	apply_b.text = "Appliquer à tous"
	apply_b.focus_mode = Control.FOCUS_NONE
	apply_b.tooltip_text = "Remet chaque rival sur le niveau et le tempérament par défaut."
	apply_b.pressed.connect(apply_defaults_to_all)
	defaults.add_child(apply_b)

	# En-têtes des colonnes, alignés sur les lignes.
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 8)
	body.add_child(cols)
	for c in [["Peuple", SLOT_COL_FACTION], ["Couleur", SLOT_COL_COLOR], ["Niveau d'IA", SLOT_COL_LEVEL], ["Tempérament", SLOT_COL_TEMPER]]:
		var l := UiTheme.section(String(c[0]))
		l.custom_minimum_size = Vector2(float(c[1]), 0)
		cols.add_child(l)
	var list_scroll := ScrollContainer.new()
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_scroll.custom_minimum_size = Vector2(0, 6 * 38)
	body.add_child(list_scroll)
	_slot_list = VBoxContainer.new()
	_slot_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slot_list.add_theme_constant_override("separation", 4)
	list_scroll.add_child(_slot_list)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	body.add_child(actions)
	_add_slot = Button.new()
	_add_slot.text = "+ Ajouter un rival"
	_add_slot.focus_mode = Control.FOCUS_NONE
	_add_slot.pressed.connect(func() -> void: add_slot())
	actions.add_child(_add_slot)
	var rand_b := Button.new()
	rand_b.text = "Tout au hasard"
	rand_b.focus_mode = Control.FOCUS_NONE
	rand_b.tooltip_text = "Chaque rival devient « Au hasard » : vous découvrirez vos voisins en les rencontrant."
	rand_b.pressed.connect(randomize_slots)
	actions.add_child(rand_b)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(spacer)
	_dup_check = CheckBox.new()
	_dup_check.text = "Peuples en double"
	_dup_check.focus_mode = Control.FOCUS_NONE
	_dup_check.button_pressed = allow_duplicates
	_dup_check.tooltip_text = "Permet à plusieurs empires d'être du même peuple, y compris le vôtre.\nIls se distinguent par leur couleur et un numéro (« Lignées d'Ossarane II »)."
	_dup_check.toggled.connect(set_duplicates)
	actions.add_child(_dup_check)
	_slot_note = Label.new()
	_slot_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_slot_note.add_theme_color_override("font_color", UiTheme.WARN)
	_slot_note.add_theme_font_size_override("font_size", 13)
	body.add_child(_slot_note)
	_build_slot_advanced(page_root)
	if slots.is_empty():
		slots = default_slots()
	_refresh_slots()


func _temper_tip(first: String) -> String:
	var ttip := PackedStringArray([first])
	for id in AiLevels.temperament_ids():
		ttip.append("%s : %s" % [AiLevels.temperament(id)["label"], AiLevels.temperament(id).get("desc", "")])
	ttip.append("Chaque peuple le décale d'un cran : le Chœur (zélé) et l'Essaim (vorace) vers l'agressif, Vael (conciliante) vers le pacifique.")
	return "\n".join(ttip)


## Refait les lignes des rivaux, le compte et la note des doublons. Différé : un menu déroulant
## d'une ligne peut être celui qui vient de changer.
func _refresh_slots() -> void:
	if _slot_list == null:
		return
	_slot_count.text = "%d / %d" % [slots.size(), MAX_EMPIRES - 1]
	_add_slot.disabled = slots.size() >= MAX_EMPIRES - 1
	_slot_note.text = slots_note()
	_slot_note.visible = _slot_note.text != ""
	_refresh_preset()
	if not _slots_dirty:
		_slots_dirty = true
		_rebuild_slot_rows.call_deferred()


func _rebuild_slot_rows() -> void:
	_slots_dirty = false
	if _slot_list == null:
		return
	for c in _slot_list.get_children():
		_slot_list.remove_child(c)
		c.queue_free()
	for i in slots.size():
		_slot_list.add_child(_slot_row(i))


## Peuples pris par les autres emplacements (et le vôtre) : grisés dans la liste quand les doublons
## ne sont pas permis.
func _taken_factions(except: int) -> Array[String]:
	var out: Array[String] = []
	if allow_duplicates:
		return out
	if not spectator and selected_faction != "" and selected_faction != RANDOM_FACTION:
		out.append(selected_faction)
	for j in slots.size():
		if j != except and slots[j]["faction"] != RANDOM_FACTION:
			out.append(String(slots[j]["faction"]))
	return out


## Une ligne de rival : peuple, couleur, niveau, tempérament, et × pour le retirer. Un réglage qui
## s'écarte du défaut est écrit dans la couleur d'accent, comme un repère.
func _slot_row(i: int) -> HBoxContainer:
	var s := slots[i]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var fsel := OptionButton.new()
	fsel.clip_text = true
	fsel.custom_minimum_size = Vector2(SLOT_COL_FACTION, 0)
	fsel.add_item("Au hasard")
	fsel.set_item_metadata(0, RANDOM_FACTION)
	var taken := _taken_factions(i)
	var ids := GameData.all_faction_ids()
	for k in ids.size():
		if k == GameData.faction_ids().size():
			fsel.add_separator("Vos peuples")
		var f := GameData.faction(ids[k])
		fsel.add_item(String(f.get("name", ids[k])))
		var idx := fsel.item_count - 1
		fsel.set_item_metadata(idx, ids[k])
		fsel.set_item_icon(idx, _swatch(Color.html(String(f.get("color", "#ffffff")))))
		fsel.set_item_disabled(idx, taken.has(ids[k]) and ids[k] != s["faction"])
		if ids[k] == s["faction"]:
			fsel.select(idx)
	if s["faction"] == RANDOM_FACTION:
		fsel.select(0)
	fsel.item_selected.connect(func(idx: int) -> void: set_slot(i, "faction", String(fsel.get_item_metadata(idx))))
	row.add_child(fsel)

	var csel := OptionButton.new()
	csel.clip_text = true
	csel.custom_minimum_size = Vector2(SLOT_COL_COLOR, 0)
	csel.tooltip_text = "Auto : la couleur du peuple, ou une couleur libre si elle est déjà prise."
	csel.add_item("Auto")
	csel.set_item_metadata(0, "")
	for k in Empire.PALETTE.size():
		csel.add_item(String(COLOR_NAMES[k]))
		csel.set_item_metadata(k + 1, Empire.PALETTE[k])
		csel.set_item_icon(k + 1, _swatch(Color.html(Empire.PALETTE[k])))
		if Empire.PALETTE[k] == s["color"]:
			csel.select(k + 1)
	csel.item_selected.connect(func(idx: int) -> void: set_slot(i, "color", String(csel.get_item_metadata(idx))))
	_mark_override(csel, s["color"] != "")
	row.add_child(csel)

	var lsel := OptionButton.new()
	lsel.clip_text = true
	lsel.custom_minimum_size = Vector2(SLOT_COL_LEVEL, 0)
	lsel.add_item("Défaut (%s)" % AiLevels.label(ai_level))
	lsel.set_item_metadata(0, "")
	for id in AiLevels.ids():
		lsel.add_item(AiLevels.label(id))
		lsel.set_item_metadata(lsel.item_count - 1, id)
		if id == s["level"]:
			lsel.select(lsel.item_count - 1)
	lsel.tooltip_text = _ai_select.tooltip_text
	lsel.item_selected.connect(func(idx: int) -> void: set_slot(i, "level", String(lsel.get_item_metadata(idx))))
	_mark_override(lsel, s["level"] != "")
	row.add_child(lsel)

	var tsel := OptionButton.new()
	tsel.clip_text = true
	tsel.custom_minimum_size = Vector2(SLOT_COL_TEMPER, 0)
	tsel.add_item("Défaut (%s)" % String(AiLevels.temperament(temperament)["label"]))
	tsel.set_item_metadata(0, "")
	for id in AiLevels.temperament_ids():
		tsel.add_item(String(AiLevels.temperament(id)["label"]))
		tsel.set_item_metadata(tsel.item_count - 1, id)
		if id == s["temper"]:
			tsel.select(tsel.item_count - 1)
	tsel.tooltip_text = _temper_tip("Tempérament de cet empire envers les autres :")
	tsel.item_selected.connect(func(idx: int) -> void: set_slot(i, "temper", String(tsel.get_item_metadata(idx))))
	_mark_override(tsel, s["temper"] != "")
	row.add_child(tsel)

	var more := Button.new()
	var custom := String(s.get("start", "")) != "" or String(s.get("distance", "")) != ""
	more.text = "+"
	more.focus_mode = Control.FOCUS_NONE
	more.custom_minimum_size = Vector2(26, 0)
	more.tooltip_text = "Départ : %s\nDistance : %s" % [START_LABELS[String(s.get("start", ""))], DISTANCE_LABELS[String(s.get("distance", ""))]]
	_mark_button(more, custom)
	more.pressed.connect(func() -> void: open_slot_advanced(i))
	row.add_child(more)

	var rm := Button.new()
	rm.text = "×"
	rm.focus_mode = Control.FOCUS_NONE
	rm.tooltip_text = "Retirer ce rival"
	rm.disabled = slots.size() <= 1
	rm.pressed.connect(func() -> void: remove_slot(i))
	row.add_child(rm)
	return row


func _mark_button(b: Button, on: bool) -> void:
	if on:
		b.add_theme_color_override("font_color", UiTheme.ACCENT)
		b.add_theme_color_override("font_hover_color", UiTheme.ACCENT)


## Fenêtre « + » d'un rival : départ avancé et distance à votre capitale.
func open_slot_advanced(index: int) -> void:
	if index < 0 or index >= slots.size():
		return
	_slot_adv_index = index
	var s := slots[index]
	var fid := String(s["faction"])
	_slot_adv_title.text = ("Rival %d : %s" % [index + 1, "au hasard" if fid == RANDOM_FACTION else String(GameData.faction(fid).get("short", fid))]).to_upper()
	_slot_start_select.select(START_LABELS.keys().find(String(s.get("start", ""))))
	_slot_dist_select.select(DISTANCE_LABELS.keys().find(String(s.get("distance", ""))))
	_slot_adv.reset_size()
	_slot_adv.popup_centered()


func _build_slot_advanced(page_root: Control) -> void:
	_slot_adv = PopupPanel.new()
	_slot_adv.add_theme_stylebox_override("panel", UiTheme.box(Color(0.03, 0.04, 0.06, 1.0), Color(1, 1, 1, 0.16), 18, 1))
	page_root.add_child(_slot_adv)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(480, 0)
	box.add_theme_constant_override("separation", 10)
	_slot_adv.add_child(box)
	_slot_adv_title = _header("")
	box.add_child(_slot_adv_title)
	_slot_start_select = OptionButton.new()
	for k in START_LABELS:
		_slot_start_select.add_item(String(START_LABELS[k]))
	_slot_start_select.tooltip_text = "Avancé : l'empire part avec deux colonies de plus autour de son monde d'origine,\nsa flotte de départ en double et des réserves (matériaux, énergie, influence)."
	_slot_start_select.item_selected.connect(func(i: int) -> void: set_slot(_slot_adv_index, "start", String(START_LABELS.keys()[i])))
	_labeled_row(box, "Départ", _slot_start_select)
	_slot_dist_select = OptionButton.new()
	for k in DISTANCE_LABELS:
		_slot_dist_select.add_item(String(DISTANCE_LABELS[k]))
	_slot_dist_select.item_selected.connect(func(i: int) -> void: set_slot(_slot_adv_index, "distance", String(DISTANCE_LABELS.keys()[i])))
	_labeled_row(box, "Distance", _slot_dist_select)
	var note := UiTheme.paragraph("Les départs sont tirés selon le placement de la galaxie. « Sans préférence » : ce rival prend celui qui lui revient ; « Proche de vous » donne à ce rival l'un des départs les plus proches du vôtre, « Loin de vous » l'un des plus éloignés ; « Au hasard » tire l'une de ces trois distances, et vous la découvrirez en jeu.", 460, 13)
	note.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	box.add_child(note)
	var close := Button.new()
	close.text = "Fermer"
	close.focus_mode = Control.FOCUS_NONE
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	close.pressed.connect(func() -> void: _slot_adv.hide())
	box.add_child(close)


func _mark_override(b: OptionButton, on: bool) -> void:
	if on:
		b.add_theme_color_override("font_color", UiTheme.ACCENT)
		b.add_theme_color_override("font_hover_color", UiTheme.ACCENT)


## Petit carré de couleur pour les listes (peuples, couleurs).
func _swatch(c: Color) -> Texture2D:
	var img := Image.create(12, 12, false, Image.FORMAT_RGBA8)
	img.fill(c)
	return ImageTexture.create_from_image(img)


## Contenu d'un bloc du bas : des lignes avec une marge.
func _block_rows(block: VBoxContainer) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	var pad := MarginContainer.new()
	for side in ["left", "right", "top"]:
		pad.add_theme_constant_override("margin_" + side, 14)
	pad.add_child(box)
	block.add_child(pad)
	return box


## Une ligne « libellé : réglage ».
func _labeled_row(parent: Control, text: String, control: Control) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(70, 0)
	row.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)


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
	var art := Widgets.ArtSlot.new(GameData.portrait_art(fid) if fid != RANDOM_FACTION else "faction_" + fid, Vector2(TILE_SIZE.x, TILE_SIZE.y - 34), col, "faction")
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



# --- Réglages enregistrés : dernière partie, préréglages, code de partie ---------------------------

## Tous les réglages de l'écran, en données (préréglages, Partie rapide, code de partie).
func settings() -> Dictionary:
	return {"faction": selected_faction, "slots": slots.duplicate(true), "duplicates": allow_duplicates,
		"ai_level": ai_level, "temperament": temperament, "spectator": spectator,
		"time_mode": time_mode, "turn_days": turn_days, "deadline": deadline_days, "people": people_victories,
		"victories": victories.duplicate(), "ai_scaling": ai_scaling, "galaxy": galaxy_settings.duplicate(),
		"seed": _seed_edit.text.strip_edges() if _seed_edit else ""}


static func _without_seed(d: Dictionary) -> Dictionary:
	var out := d.duplicate(true)
	out.erase("seed")
	return out


## Réglages par défaut de l'écran (votre peuple choisi gardé).
func default_settings() -> Dictionary:
	return {"faction": selected_faction, "slots": default_slots(), "duplicates": false,
		"ai_level": AiLevels.default_id(), "temperament": AiLevels.default_temperament(), "spectator": false,
		"time_mode": GameClock.MODE_REALTIME, "turn_days": 10, "deadline": Victory.default_deadline(), "people": true,
		"victories": {"conquete": true, "domination": true, "allies": true}, "ai_scaling": false,
		"galaxy": GalaxySettings.defaults()}


## Remplit l'écran avec des réglages (préréglage, dernière partie, code). Une valeur inconnue garde la
## valeur par défaut ; un peuple absent de cette installation (peuple créé ailleurs) passe « Au hasard ».
## Renvoie les avertissements à afficher.
func apply_settings(d: Dictionary) -> PackedStringArray:
	var warn := PackedStringArray()
	var base := default_settings()
	_applying = true
	var fid := String(d.get("faction", selected_faction))
	if fid != RANDOM_FACTION and GameData.faction(fid).is_empty():
		warn.append("Votre peuple « %s » n'existe pas ici : tiré au hasard." % fid)
		fid = RANDOM_FACTION
	if fid != "":
		select_faction(fid)
	allow_duplicates = bool(d.get("duplicates", false))
	if _dup_check:
		_dup_check.set_pressed_no_signal(allow_duplicates)
	var new_slots: Array[Dictionary] = []
	var raw: Variant = d.get("slots", base["slots"])
	for item: Variant in (raw if raw is Array else []):
		if not item is Dictionary or new_slots.size() >= MAX_EMPIRES - 1:
			continue
		var src: Dictionary = item
		var sf := String(src.get("faction", RANDOM_FACTION))
		if sf != RANDOM_FACTION and GameData.faction(sf).is_empty():
			warn.append("Peuple rival « %s » inconnu ici : remplacé par Au hasard." % sf)
			sf = RANDOM_FACTION
		var slot := new_slot(sf)
		for k in ["color", "level", "temper", "start", "distance"]:
			slot[k] = String(src.get(k, ""))
		if slot["color"] != "" and not Empire.PALETTE.has(slot["color"]):
			slot["color"] = ""
		if slot["level"] != "" and not AiLevels.is_valid(slot["level"]):
			slot["level"] = ""
		if slot["temper"] != "" and not AiLevels.is_valid_temperament(slot["temper"]):
			slot["temper"] = ""
		if not START_LABELS.has(slot["start"]):
			slot["start"] = ""
		if not DISTANCE_LABELS.has(slot["distance"]):
			slot["distance"] = ""
		new_slots.append(slot)
	slots = new_slots if not new_slots.is_empty() else default_slots()
	set_ai_level(String(d.get("ai_level", base["ai_level"])))
	set_temperament(String(d.get("temperament", base["temperament"])))
	set_spectator(bool(d.get("spectator", false)))
	var turns := int(d.get("time_mode", GameClock.MODE_REALTIME)) == GameClock.MODE_TURNS
	var ti := GameClock.TURN_LENGTHS.find(int(d.get("turn_days", 10)))
	set_time_choice(1 + maxi(0, ti) if turns else 0)
	set_deadline(int(d.get("deadline", base["deadline"])))
	set_people_victories(bool(d.get("people", true)))
	var vic: Dictionary = d.get("victories", {}) if d.get("victories", {}) is Dictionary else {}
	for k in victories:
		set_victory(k, bool(vic.get(k, true)))
	set_ai_scaling(bool(d.get("ai_scaling", false)))
	galaxy_settings = GalaxySettings.normalize(d.get("galaxy", {}))
	if _seed_edit and d.has("seed"):
		_seed_edit.text = String(d["seed"])
	_applying = false
	_refresh_galaxy()
	_refresh_slots()
	return warn


func _load_presets() -> Dictionary:
	var f := FileAccess.open(presets_path, FileAccess.READ)
	if f == null:
		return {"last": {}, "presets": []}
	var text := f.get_as_text()
	var d: Variant = JSON.parse_string(text) if text.strip_edges() != "" else null
	if not d is Dictionary:
		return {"last": {}, "presets": []}
	var out: Dictionary = d
	if not out.get("last", {}) is Dictionary:
		out["last"] = {}
	if not out.get("presets", []) is Array:
		out["presets"] = []
	return out


func _save_presets(store: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(presets_path.get_base_dir())
	var f := FileAccess.open(presets_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(store, "\t"))
		f.close()
	_rebuild_presets()


## Réglages de la dernière partie lancée ({} = aucune).
func last_settings() -> Dictionary:
	return _load_presets()["last"]


## Noms des préréglages enregistrés, dans l'ordre.
func preset_names() -> Array[String]:
	var out: Array[String] = []
	for p: Variant in _load_presets()["presets"]:
		if p is Dictionary:
			out.append(String(p.get("name", "")))
	return out


## Enregistre les réglages de l'écran sous ce nom (remplace un préréglage du même nom).
func save_preset(name: String) -> bool:
	name = name.strip_edges()
	if name == "":
		return false
	var store := _load_presets()
	var list: Array = store["presets"].filter(func(p: Variant) -> bool: return p is Dictionary and String(p.get("name", "")) != name)
	list.append({"name": name, "settings": _without_seed(settings())})
	store["presets"] = list
	_save_presets(store)
	return true


func delete_preset(name: String) -> bool:
	var store := _load_presets()
	var before: int = store["presets"].size()
	store["presets"] = store["presets"].filter(func(p: Variant) -> bool: return p is Dictionary and String(p.get("name", "")) != name)
	if store["presets"].size() == before:
		return false
	_save_presets(store)
	return true


## Applique un préréglage : "default", "last" ou le nom d'un préréglage enregistré.
func apply_preset(key: String) -> bool:
	var d := {}
	if key == "default":
		d = default_settings()
	elif key == "last":
		d = last_settings()
	else:
		for p: Variant in _load_presets()["presets"]:
			if p is Dictionary and String(p.get("name", "")) == key:
				d = p.get("settings", {})
	if d.is_empty():
		return false
	var seed_text := _seed_edit.text
	apply_settings(d)
	_seed_edit.text = seed_text
	return true


## Nom du préréglage qui correspond à l'écran ("" = Personnalisé).
func current_preset() -> String:
	var cur := _without_seed(settings())
	if _same(cur, default_settings()):
		return "default"
	for p: Variant in _load_presets()["presets"]:
		if p is Dictionary and _same(cur, p.get("settings", {})):
			return String(p.get("name", ""))
	if _same(cur, last_settings()):
		return "last"
	return ""


## Comparaison de réglages, après un aller-retour JSON (les nombres d'un fichier sont des flottants).
static func _same(a: Dictionary, b: Variant) -> bool:
	if not b is Dictionary or (b as Dictionary).is_empty():
		return false
	return JSON.stringify(JSON.parse_string(JSON.stringify(a)), "", true) == JSON.stringify(JSON.parse_string(JSON.stringify(b)), "", true)


## Partie rapide : les réglages de la dernière partie, sur une nouvelle galaxie (graine au hasard).
func quick_game() -> bool:
	var last := last_settings()
	if last.is_empty():
		return false
	apply_settings(last)
	_seed_edit.text = ""
	launch()
	return true


## Code de partie : graine et réglages en une ligne à partager (une graine est tirée s'il n'y en a pas).
func game_code() -> String:
	if _seed_edit.text.strip_edges() == "":
		_seed_edit.text = str(randi() % 1000000000)
	var raw := JSON.stringify(settings()).to_utf8_buffer()
	var z := raw.compress(FileAccess.COMPRESSION_DEFLATE)
	return CODE_PREFIX + Marshalls.raw_to_base64(z).replace("+", "-").replace("/", "_").replace("=", "")


## Réglages contenus dans un code de partie ({} = code illisible).
static func decode_game_code(code: String) -> Dictionary:
	code = code.strip_edges()
	if not code.begins_with(CODE_PREFIX):
		return {}
	var b64 := code.substr(CODE_PREFIX.length()).replace("-", "+").replace("_", "/")
	var ok_chars := RegEx.create_from_string("^[A-Za-z0-9+/]+$")
	if ok_chars.search(b64) == null:
		return {}
	while b64.length() % 4 != 0:
		b64 += "="
	var z := Marshalls.base64_to_raw(b64)
	if z.is_empty():
		return {}
	var raw := z.decompress_dynamic(1 << 20, FileAccess.COMPRESSION_DEFLATE)
	if raw.is_empty():
		return {}
	var d: Variant = JSON.parse_string(raw.get_string_from_utf8())
	return d if d is Dictionary else {}


## Applique un code de partie ; renvoie le message à afficher.
func apply_game_code(code: String) -> String:
	var d := decode_game_code(code)
	if d.is_empty():
		return "Code illisible : vérifiez qu'il commence par %s et qu'il est complet." % CODE_PREFIX
	var warn := apply_settings(d)
	if _code_out:
		_code_out.text = game_code()
	return "Réglages appliqués." if warn.is_empty() else "Réglages appliqués. " + " ".join(warn)


func _build_presets_bar(page_root: Control) -> void:
	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	bar.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	bar.offset_right = -32
	bar.offset_top = 22
	bar.add_theme_constant_override("separation", 8)
	page_root.add_child(bar)
	_preset_select = OptionButton.new()
	_preset_select.custom_minimum_size = Vector2(200, 0)
	_preset_select.clip_text = true
	_preset_select.tooltip_text = "Préréglages : les réglages par défaut, ceux de votre dernière partie, ou les vôtres.\nToucher à un réglage repasse en « Personnalisé »."
	_preset_select.item_selected.connect(func(i: int) -> void:
		var key := String(_preset_select.get_item_metadata(i))
		if key != "":
			apply_preset(key))
	bar.add_child(_preset_select)
	var save_b := Button.new()
	save_b.text = "Enregistrer…"
	save_b.focus_mode = Control.FOCUS_NONE
	save_b.tooltip_text = "Enregistrer ces réglages comme préréglage (sans la graine)."
	save_b.pressed.connect(open_preset_popup)
	bar.add_child(save_b)
	var code_b := Button.new()
	code_b.text = "Code de partie…"
	code_b.focus_mode = Control.FOCUS_NONE
	code_b.tooltip_text = "Une ligne qui contient la graine et tous les réglages : à partager, ou à coller pour rejouer la même galaxie."
	code_b.pressed.connect(open_code_popup)
	bar.add_child(code_b)

	_preset_popup = _small_popup(page_root, "Enregistrer les réglages")
	var pbox := _preset_popup.get_child(0) as VBoxContainer
	_preset_name = LineEdit.new()
	_preset_name.placeholder_text = "Nom du préréglage"
	_preset_name.text_submitted.connect(func(t: String) -> void:
		if save_preset(t):
			_preset_popup.hide())
	_labeled_row(pbox, "Nom", _preset_name)
	var prow := HBoxContainer.new()
	prow.add_theme_constant_override("separation", 8)
	pbox.add_child(prow)
	_preset_delete = Button.new()
	_preset_delete.focus_mode = Control.FOCUS_NONE
	_preset_delete.pressed.connect(func() -> void:
		delete_preset(_preset_name.text.strip_edges())
		_preset_popup.hide())
	prow.add_child(_preset_delete)
	var pspace := Control.new()
	pspace.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prow.add_child(pspace)
	var ok := Button.new()
	ok.text = "Enregistrer"
	ok.focus_mode = Control.FOCUS_NONE
	ok.pressed.connect(func() -> void:
		if save_preset(_preset_name.text):
			_preset_popup.hide())
	prow.add_child(ok)
	_preset_name.text_changed.connect(func(_t: String) -> void: _refresh_delete_button())

	_code_popup = _small_popup(page_root, "Code de partie")
	var cbox := _code_popup.get_child(0) as VBoxContainer
	_code_out = LineEdit.new()
	_code_out.editable = false
	_code_out.select_all_on_focus = true
	_labeled_row(cbox, "Ce code", _code_out)
	var copy := Button.new()
	copy.text = "Copier"
	copy.focus_mode = Control.FOCUS_NONE
	copy.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(_code_out.text)
		_code_note.text = "Copié. Le même code redonne la même galaxie, les mêmes rivaux et les mêmes règles.")
	_code_out.get_parent().add_child(copy)
	_code_in = LineEdit.new()
	_code_in.placeholder_text = "Collez ici le code d'un ami"
	_code_in.text_submitted.connect(func(t: String) -> void: _code_note.text = apply_game_code(t))
	_labeled_row(cbox, "Rejouer", _code_in)
	var use := Button.new()
	use.text = "Appliquer"
	use.focus_mode = Control.FOCUS_NONE
	use.pressed.connect(func() -> void: _code_note.text = apply_game_code(_code_in.text))
	_code_in.get_parent().add_child(use)
	_code_note = UiTheme.paragraph("", 560, 13)
	_code_note.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	cbox.add_child(_code_note)
	_rebuild_presets()


func _small_popup(page_root: Control, heading: String) -> PopupPanel:
	var pop := PopupPanel.new()
	pop.add_theme_stylebox_override("panel", UiTheme.box(Color(0.03, 0.04, 0.06, 1.0), Color(1, 1, 1, 0.16), 18, 1))
	page_root.add_child(pop)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(600, 0)
	box.add_theme_constant_override("separation", 10)
	pop.add_child(box)
	box.add_child(_header(heading))
	return pop


func open_preset_popup() -> void:
	var cur := current_preset()
	_preset_name.text = cur if cur != "default" and cur != "last" else ""
	_refresh_delete_button()
	_preset_popup.reset_size()
	_preset_popup.popup_centered()


func _refresh_delete_button() -> void:
	var name := _preset_name.text.strip_edges()
	_preset_delete.text = "Supprimer « %s »" % name if preset_names().has(name) else "Supprimer"
	_preset_delete.disabled = not preset_names().has(name)


func open_code_popup() -> void:
	_code_out.text = game_code()
	_code_in.text = ""
	_code_note.text = "Le code contient la graine : partagez-le pour jouer la même galaxie. Les peuples créés dans l'éditeur ne voyagent pas avec lui."
	_code_popup.reset_size()
	_code_popup.popup_centered()


func _rebuild_presets() -> void:
	if _preset_select == null:
		return
	_preset_select.clear()
	_preset_select.add_item("Personnalisé")
	_preset_select.set_item_metadata(0, "")
	_preset_select.add_item("Par défaut")
	_preset_select.set_item_metadata(1, "default")
	if not last_settings().is_empty():
		_preset_select.add_item("Dernière partie")
		_preset_select.set_item_metadata(_preset_select.item_count - 1, "last")
	var names := preset_names()
	if not names.is_empty():
		_preset_select.add_separator("Mes réglages")
		for n in names:
			_preset_select.add_item(n)
			_preset_select.set_item_metadata(_preset_select.item_count - 1, n)
	_refresh_preset()


## Le menu des préréglages montre celui qui correspond à l'écran, ou « Personnalisé ».
func _refresh_preset() -> void:
	if _preset_select == null or _applying or _seed_edit == null:
		return
	var cur := current_preset()
	for i in _preset_select.item_count:
		if not _preset_select.is_item_separator(i) and String(_preset_select.get_item_metadata(i)) == cur:
			_preset_select.select(i)
			return
	_preset_select.select(0)
