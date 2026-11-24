class_name SpeciesEditor
extends Control
## Écran « Peuples » du menu principal : la bibliothèque des peuples créés et l'éditeur d'espèces.
## Inspiré des éditeurs consultés (docs : README, section Éditeur d'espèces) : onglets comme la
## création de civilisation de Galactic Civilizations IV (Biologie, Capacités, Flottes), liste des
## qualités et des défauts avec leur coût et compteur de points comme Stellaris, aperçu permanent à
## droite. Les règles sont celles de Species (rien n'est vérifié ici qui ne le soit aussi au chargement).
##
## Le peuple en cours d'édition est un spec (voir Species) ; chaque changement rafraîchit l'aperçu.

signal back_requested
## La bibliothèque a changé (peuple enregistré ou supprimé) : la liste de Nouvelle partie se refait.
signal library_changed

const TABS := [["identity", "Identité"], ["layers", "Couches"], ["traits", "Traits"]]
## Vue guidée (refonte D2) : six étapes, dans l'ordre des questions que se pose le joueur plutôt que
## dans celui des données. [id, libellé du fil, question en titre, aide, sections montrées].
## Les mêmes sections se rangent dans les trois onglets d'origine quand on passe en vue complète.
const STEPS := [
	["start", "Départ", "D'où partir", "Un peuple officiel prête ses couches et ses traits, que vous changez ensuite. La page blanche part d'un peuple neutre.", ["start"]],
	["who", "Nature", "Qui sont-ils", "Le registre règle le ton et l'opinion que les autres peuples ont d'eux. L'archétype dit de quoi ils sont faits.", ["layer_registre", "layer_archetype", "temper"]],
	["life", "Mœurs", "Comment vivent-ils", "Les couches sont gratuites : chacune apporte sa règle, avec sa force et son prix.", ["layer_gouvernement", "layer_credo", "layer_origine", "biomes"]],
	["traits", "Traits", "Ce qui les distingue", "", ["traits", "talent"]],
	["look", "Apparence", "À quoi ressemblent-ils", "Rien sur cette page ne change les règles.", ["portraits", "look"]],
	["name", "Histoire", "Leur nom et leur histoire", "Le nom complet sert dans les chroniques, le nom court sur la carte et dans les listes.", ["names", "lore"]],
]
const PROPOSE_TEXT := "Proposer une chronique"
const COLORS := ["#e8b44a", "#c0392b", "#4a90e2", "#6fcf3a", "#3fb6a8", "#9b7fd4", "#d96fb0", "#c46a2b", "#e0d6b8", "#7f8fa6"]
const LAYER_LABELS := {"registre": "Registre", "archetype": "Archétype", "gouvernement": "Gouvernement", "credo": "Credo", "origine": "Origine"}
const BIOME_LABELS := {"continental": "Continental", "ocean": "Océanique", "desert": "Désertique", "arctic": "Glaciaire", "toxic": "Toxique"}
const STYLE_LABELS := {"ossarane": "Navires d'Ossarane", "choeur": "Cathédrales du Chœur", "vael": "Frégates de Vael", "khthari": "Coques vivantes kh'thari", "teyl": "Nœuds de Teyl", "ferrocornes": "Coques-clans ferrocornes", "brisecomete": "Cargos armés du Syndicat", "murmurants": "Voiles des Murmurants"}

## Peuple en cours d'édition, et identifiant enregistré qu'il remplace ("" = nouveau peuple).
var spec: Dictionary = {}
var editing_id := ""
var tab := "identity"
## Vue guidée (les six étapes) ou vue complète (les trois onglets), et étape montrée.
var guided := true
var step := 0
## Dernier message affiché sous les boutons (enregistrement, erreur…).
var status := ""

var _tabs := {}
var _pages := {}
var _list: VBoxContainer
var _name_edit: LineEdit
var _short_edit: LineEdit
var _lore_edit: TextEdit
var _color_row: HBoxContainer
var _style_select: OptionButton
var _temper_select: OptionButton
var _talent_select: OptionButton
var _talent_ids: Array[String] = []
var _portrait_grid: GridContainer
var _layer_selects := {}
var _layer_texts := {}
var _biome_selects: Array[OptionButton] = []
var _budget_label: Label
var _chosen_row: HFlowContainer
var _good_list: VBoxContainer
var _bad_list: VBoxContainer
var _preview_art: Widgets.ArtSlot
var _preview_name: Label
var _preview_budget: Label
var _preview_errors: Label
var _preview_rules: RichTextLabel
var _status_label: Label
var _delete_b: Button
var _delete_armed := false
var _syncing := false
var _sections := {}
var _slots := {}
var _step_pages: Array[ScrollContainer] = []
var _step_buttons: Array[Button] = []
var _step_errors: Array[Label] = []
var _thread: HBoxContainer
var _tab_row: HBoxContainer
var _mode_b: Button
var _nav: HBoxContainer
var _prev_b: Button
var _next_b: Button
var _propose_b: Button
var _propose_armed := false
var _last_proposal := ""
## Le portrait a été choisi (à la main, ou hérité d'un modèle ou d'un peuple enregistré) : il ne suit
## plus l'archétype. Sur une page blanche, il le suit tant qu'on n'y a pas touché.
var _portrait_picked := false
static var _chronicle_parts := {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0.012, 0.016, 0.026, 0.98)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var title := UiTheme.title("Peuples", 32)
	title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	title.grow_horizontal = Control.GROW_DIRECTION_BOTH
	title.offset_top = 18
	add_child(title)
	_build_library()
	_build_center()
	_build_preview()
	_build_footer()
	open_new("")


# --- API (aussi utilisée par les tests) ---------------------------------------------------------

## Nouveau peuple, à partir du modèle d'un officiel (« Partir de… ») ou neutre (preset == "").
func open_new(preset: String) -> void:
	spec = Species.from_preset(preset)
	editing_id = ""
	_portrait_picked = preset != ""
	if preset != "":
		spec["name"] = "Héritiers de %s" % GameData.faction(preset).get("short", preset)
		spec["short"] = "Héritiers"
	else:
		spec["name"] = "Nouveau peuple"
		spec["short"] = "Nouveaux"
	_set_status("Nouveau peuple%s : donnez-lui un nom, puis enregistrez." % (" (modèle %s)" % GameData.faction(preset).get("short", preset) if preset != "" else ""))
	_sync_all()


## Rouvre un peuple de la bibliothèque.
func open_saved(id: String) -> void:
	var s: Dictionary = GameData.faction(id).get("spec", {})
	if s.is_empty():
		return
	spec = s.duplicate(true)
	editing_id = id
	_portrait_picked = true
	_set_status("")
	_sync_all()
	if guided and step == 0 and _nav != null:
		set_step(1)


## Copie d'un peuple enregistré, sous un nouveau nom.
func duplicate_current() -> void:
	spec = spec.duplicate(true)
	spec["name"] = ("Copie de %s" % String(spec.get("name", ""))).substr(0, Species.NAME_MAX)
	spec["id"] = ""
	editing_id = ""
	_set_status("Copie créée : elle sera enregistrée comme un nouveau peuple.")
	_sync_all()


func set_layer(layer: String, id: String) -> void:
	var changed := String(spec.get(layer, "")) != id
	spec[layer] = id
	# Le portrait choisi reste : la galerie se réordonne seulement (ceux de l'archétype d'abord).
	# Sur une page blanche, tant qu'aucun n'a été choisi, il suit l'archétype.
	if layer == "archetype" and changed and not _portrait_picked:
		var ps := Species.portraits(id)
		if not ps.is_empty():
			spec["portrait"] = String(ps[0]["id"])
	_sync_all()


func set_portrait(id: String) -> void:
	spec["portrait"] = id
	_portrait_picked = true
	_refresh()


## Ajoute ou retire un trait. Renvoie "" ou la raison du refus (ajout impossible).
func toggle_trait(id: String) -> String:
	var ts: Array = spec.get("traits", [])
	if ts.has(id):
		ts.erase(id)
	else:
		var why := add_refusal(id)
		if why != "":
			_set_status(why)
			return why
		ts.append(id)
	spec["traits"] = ts
	_refresh()
	return ""


## "" si le trait peut être ajouté au peuple, sinon pourquoi pas.
func add_refusal(id: String) -> String:
	var ts: Array = spec.get("traits", [])
	if ts.has(id):
		return ""
	var trial := spec.duplicate(true)
	(trial["traits"] as Array).append(id)
	var errs := Species.trait_errors(trial)
	return "" if errs.is_empty() else errs[0]


## Enregistre le peuple dans la bibliothèque. Renvoie "" ou la raison de l'échec.
func save() -> String:
	if editing_id == "":
		spec["id"] = Species.make_id(String(spec.get("name", "")), GameData.library_faction_ids())
	else:
		spec["id"] = editing_id
	var err := SpeciesLibrary.save(spec)
	if err != "":
		_set_status("Impossible d'enregistrer : " + err)
		return err
	editing_id = String(spec["id"])
	_set_status("« %s » enregistré : il vous attend dans Nouvelle partie." % spec["name"])
	_rebuild_list()
	library_changed.emit()
	return ""


## Supprime le peuple ouvert (s'il est enregistré). Les parties qui le jouent le gardent.
func delete_current() -> bool:
	if editing_id == "":
		return false
	var nm := String(spec.get("name", editing_id))
	if not SpeciesLibrary.delete(editing_id):
		return false
	open_new("")
	_set_status("« %s » supprimé de la bibliothèque. Les parties sauvegardées le gardent." % nm)
	_rebuild_list()
	library_changed.emit()
	return true


func show_tab(id: String) -> void:
	tab = id
	if guided:
		guided = false
		_place()
		_rebuild_list()
	_show_pages()


## Vue guidée (six étapes) ou vue complète (les trois onglets) : les mêmes contrôles, rangés autrement.
func set_guided(on: bool) -> void:
	guided = on
	_place()
	_rebuild_list()
	_show_pages()


func set_step(i: int) -> void:
	step = clampi(i, 0, STEPS.size() - 1)
	if guided:
		_show_pages()
	else:
		set_guided(true)


## Les refus de Species.errors rangés par étape : [PackedStringArray] × STEPS.size(). Une exigence
## entre deux couches se montre aux deux étapes, puisqu'on peut la lever de l'un ou l'autre côté.
func step_errors() -> Array:
	var out := []
	for i in STEPS.size():
		out.append(PackedStringArray())
	var probe := spec.duplicate(true)
	probe["id"] = editing_id if editing_id != "" else Species.make_id(String(spec.get("name", "")), GameData.library_faction_ids())
	var errs := Species.errors(probe)
	if errs.is_empty():
		return out
	var trait_errs := Species.trait_errors(probe)
	var pairs := {}
	for layer in Species.layers():
		var b := Species.brick(String(layer), String(spec.get(layer, "")))
		if b.is_empty():
			continue
		for l2 in b.get("requires", {}):
			pairs["%s demande : %s" % [b["label"], Species._labels(String(l2), b["requires"][l2])]] = [String(layer), String(l2)]
		for l2 in b.get("excludes", {}):
			pairs["%s est incompatible avec %s" % [b["label"], Species.brick(String(l2), String(spec.get(l2, ""))).get("label", spec.get(l2, ""))]] = [String(layer), String(l2)]
	for e in errs:
		var where := {}
		if trait_errs.has(e) or e.begins_with("le talent"):
			where[_step_index("traits")] = true
		elif pairs.has(e):
			for l in pairs[e]:
				where[_layer_step(String(l))] = true
		elif e.begins_with("couleur") or e.begins_with("portrait") or e.begins_with("style"):
			where[_step_index("look")] = true
		elif e.begins_with("tempérament"):
			where[_step_index("who")] = true
		elif e.contains("biome"):
			where[_step_index("life")] = true
		else:
			for layer in Species.layers():
				if e.contains("« %s »" % layer):
					where[_layer_step(String(layer))] = true
			if where.is_empty():
				where[_step_index("name")] = true
		for i in where:
			# Un tableau compacté rangé dans un Array est une copie : on le reprend, on le repose.
			var mine: PackedStringArray = out[i]
			mine.append(e)
			out[i] = mine
	return out


func _step_index(id: String) -> int:
	for i in STEPS.size():
		if String(STEPS[i][0]) == id:
			return i
	return 0


## Étape qui porte une section ; une couche ajoutée aux données sans place prévue va dans « Mœurs ».
func _layer_step(layer: String) -> int:
	for i in STEPS.size():
		if (STEPS[i][4] as Array).has("layer_" + layer) or (layer == "biomes" and (STEPS[i][4] as Array).has("biomes")):
			return i
	return _step_index("life")


static func chronicle_parts() -> Dictionary:
	if _chronicle_parts.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/species_chronicle.json"))
		_chronicle_parts = parsed if parsed is Dictionary else {"_": {}}
	return _chronicle_parts


## Trois lignes de chronique tirées des choix : le corps et le monde natal, le gouvernement et le
## credo, l'origine. Chaque brique apporte sa phrase (data/species_chronicle.json).
static func chronicle(s: Dictionary) -> String:
	var c := chronicle_parts()
	var biomes: Array = s.get("biomes", [])
	var keys := [
		[["archetype", String(s.get("archetype", ""))], ["biome", String(biomes[0]) if not biomes.is_empty() else ""]],
		[["gouvernement", String(s.get("gouvernement", ""))], ["credo", String(s.get("credo", ""))]],
		[["origine", String(s.get("origine", ""))]],
	]
	var lines := PackedStringArray()
	for group: Array in keys:
		var bits := PackedStringArray()
		for k: Array in group:
			var t := String((c.get(k[0], {}) as Dictionary).get(k[1], ""))
			if t != "":
				bits.append(t)
		if not bits.is_empty():
			lines.append(" ".join(bits))
	return "\n".join(lines).substr(0, Species.LORE_MAX)


## Écrit la chronique proposée dans l'histoire. Un texte que le joueur a écrit n'est remplacé qu'au
## second clic (ou avec force). Renvoie vrai si l'histoire a été écrite.
func propose_chronicle(force := false) -> bool:
	var cur := String(spec.get("lore", "")).strip_edges()
	if cur != "" and cur != _last_proposal and not force and not _propose_armed:
		_propose_armed = true
		_propose_b.text = "Remplacer votre texte ?"
		return false
	_disarm_propose()
	_last_proposal = chronicle(spec)
	spec["lore"] = _last_proposal
	_syncing = true
	_lore_edit.text = _last_proposal
	_syncing = false
	_refresh()
	return true


func _disarm_propose() -> void:
	_propose_armed = false
	if _propose_b:
		_propose_b.text = PROPOSE_TEXT


# --- Construction -------------------------------------------------------------------------------

func _build_library() -> void:
	var col := VBoxContainer.new()
	col.position = Vector2(32, 74)
	col.custom_minimum_size = Vector2(270, 0)
	col.add_theme_constant_override("separation", 8)
	add_child(col)
	col.add_child(_header("Bibliothèque"))
	var frame := _frame(col)
	frame.custom_minimum_size = Vector2(270, 560)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_list)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	col.add_child(row)
	var nb := _small_button("Nouveau", "Un peuple neutre, à composer de zéro.")
	nb.pressed.connect(func() -> void: open_new(""))
	row.add_child(nb)
	var db := _small_button("Dupliquer", "Une copie du peuple ouvert, enregistrée à part.")
	db.pressed.connect(duplicate_current)
	row.add_child(db)
	_delete_b = _small_button("Supprimer", "Retire le peuple de la bibliothèque (deux clics).")
	_delete_b.pressed.connect(func() -> void:
		if not _delete_armed:
			_delete_armed = true
			_delete_b.text = "Confirmer"
			return
		_disarm_delete()
		delete_current())
	row.add_child(_delete_b)
	_rebuild_list()


func _rebuild_list() -> void:
	for c in _list.get_children():
		c.queue_free()
	# En vue guidée, les modèles officiels sont à l'étape « Départ » : la bibliothèque ne garde que vos peuples.
	if not guided:
		_list.add_child(UiTheme.section("Partir d'un peuple officiel"))
		for fid in GameData.faction_ids():
			_list.add_child(_model_button(fid))
	_list.add_child(UiTheme.section("Vos peuples"))
	var ids := GameData.library_faction_ids()
	if ids.is_empty():
		_list.add_child(UiTheme.dim("Aucun pour l'instant.", 13))
	for id in ids:
		var f := GameData.faction(id)
		var b := _list_button(String(f["name"]), Color.html(String(f["color"])), String(f.get("trait", "")))
		b.toggle_mode = true
		b.set_pressed_no_signal(id == editing_id)
		b.pressed.connect(open_saved.bind(id))
		_list.add_child(b)
	if not SpeciesLibrary.rejected.is_empty():
		_list.add_child(UiTheme.section("Fichiers écartés"))
		for r: Dictionary in SpeciesLibrary.rejected:
			var l := UiTheme.paragraph("%s : %s" % [String(r["path"]).get_file(), r["error"]], 230, 12)
			l.add_theme_color_override("font_color", UiTheme.WARN)
			_list.add_child(l)


func _model_button(fid: String) -> Button:
	var f := GameData.faction(fid)
	var b := _list_button(String(f["short"]), Color.html(String(f["color"])), "Nouveau peuple sur le modèle de %s (mêmes couches et traits, chiffres des briques)." % f["name"])
	b.pressed.connect(func() -> void:
		open_new(fid)
		if guided:
			set_step(1))
	return b


func _build_center() -> void:
	var col := VBoxContainer.new()
	col.position = Vector2(326, 74)
	col.custom_minimum_size = Vector2(830, 0)
	col.add_theme_constant_override("separation", 8)
	add_child(col)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	col.add_child(top)
	_thread = HBoxContainer.new()
	_thread.add_theme_constant_override("separation", 4)
	top.add_child(_thread)
	for i in STEPS.size():
		var b := Button.new()
		b.theme_type_variation = &"TabButton"
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		var k := i
		b.pressed.connect(func() -> void: set_step(k))
		_thread.add_child(b)
		_step_buttons.append(b)
	_tab_row = HBoxContainer.new()
	_tab_row.add_theme_constant_override("separation", 36)
	top.add_child(_tab_row)
	for t in TABS:
		var b := Button.new()
		b.theme_type_variation = &"TabButton"
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.text = String(t[1]).to_upper()
		b.pressed.connect(show_tab.bind(String(t[0])))
		_tab_row.add_child(b)
		_tabs[t[0]] = b
	var frame := _frame(col)
	frame.custom_minimum_size = Vector2(830, 600)
	var stack := Control.new()
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.add_child(stack)
	for t in TABS:
		_pages[t[0]] = _scroll_page(stack)
	for i in STEPS.size():
		var scroll := _scroll_page(stack)
		var page: VBoxContainer = scroll.get_child(0)
		page.add_child(UiTheme.title(String(STEPS[i][2]), 24))
		if String(STEPS[i][3]) != "":
			page.add_child(UiTheme.dim(String(STEPS[i][3]), 14))
		var err := UiTheme.paragraph("", 790, 13)
		err.add_theme_color_override("font_color", UiTheme.BAD)
		err.visible = false
		page.add_child(err)
		_step_errors.append(err)
		_step_pages.append(scroll)
		_slots["step%d" % i] = page
	_nav = HBoxContainer.new()
	col.add_child(_nav)
	_prev_b = Button.new()
	_prev_b.focus_mode = Control.FOCUS_NONE
	_prev_b.pressed.connect(func() -> void: set_step(step - 1))
	_nav.add_child(_prev_b)
	# La bascule de vue reste au milieu de la rangée, dans les deux vues.
	for i in 2:
		var nav_gap := Control.new()
		nav_gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_nav.add_child(nav_gap)
		if i == 0:
			_mode_b = Button.new()
			_mode_b.focus_mode = Control.FOCUS_NONE
			_mode_b.tooltip_text = "Vue guidée : six étapes, une question à la fois. Vue complète : tout sur trois onglets, pour qui sait ce qu'il cherche."
			_mode_b.pressed.connect(func() -> void: set_guided(not guided))
			_nav.add_child(_mode_b)
	_next_b = Button.new()
	_next_b.focus_mode = Control.FOCUS_NONE
	_next_b.pressed.connect(func() -> void: set_step(step + 1))
	_nav.add_child(_next_b)
	# Emplacements de la vue complète : l'onglet Identité garde ses deux colonnes.
	var identity: VBoxContainer = _pages["identity"].get_child(0)
	var id_top := HBoxContainer.new()
	id_top.add_theme_constant_override("separation", 20)
	identity.add_child(id_top)
	var form := VBoxContainer.new()
	form.add_theme_constant_override("separation", 8)
	form.custom_minimum_size = Vector2(380, 0)
	id_top.add_child(form)
	var lore_col := VBoxContainer.new()
	lore_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	id_top.add_child(lore_col)
	_slots["identity_form"] = form
	_slots["identity_lore"] = lore_col
	_slots["identity_bottom"] = identity
	var layers_page: VBoxContainer = _pages["layers"].get_child(0)
	layers_page.add_child(UiTheme.dim("Les couches sont gratuites : chacune apporte sa règle, avec sa force et son prix.", 14))
	_slots["layers"] = layers_page
	_slots["traits"] = _pages["traits"].get_child(0)
	_build_start()
	_build_identity()
	_build_layers()
	_build_traits()
	_place()
	_show_pages()


func _scroll_page(stack: Control) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	stack.add_child(scroll)
	var page := VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 10)
	scroll.add_child(page)
	return scroll


## Une section : un groupe de contrôles construit une fois, que _place range selon la vue.
func _section(id: String) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_sections[id] = v
	return v


## Range les sections dans les étapes (vue guidée) ou dans les trois onglets (vue complète).
func _place() -> void:
	var plan := []
	if guided:
		for i in STEPS.size():
			plan.append(["step%d" % i, STEPS[i][4]])
	else:
		plan = [["identity_form", ["names", "look", "temper", "talent"]], ["identity_lore", ["lore"]], ["identity_bottom", ["portraits"]], ["traits", ["traits"]]]
	var placed := {}
	for entry: Array in plan:
		for id in entry[1]:
			_move(String(id), String(entry[0]))
			placed[id] = true
	# Les couches (et toute couche ajoutée aux données sans place prévue), puis les biomes.
	var rest := "step%d" % _step_index("life") if guided else "layers"
	for layer in Species.layers():
		if not placed.has("layer_" + String(layer)):
			_move("layer_" + String(layer), rest)
	if not placed.has("biomes"):
		_move("biomes", rest)


func _move(id: String, slot: String) -> void:
	var n: Control = _sections.get(id)
	var to: Control = _slots.get(slot)
	if n == null or to == null:
		return
	if n.get_parent() != null:
		n.get_parent().remove_child(n)
	to.add_child(n)


func _show_pages() -> void:
	_thread.visible = guided
	_tab_row.visible = not guided
	_mode_b.text = "Vue complète" if guided else "Vue guidée"
	for t in _tabs:
		(_tabs[t] as Button).set_pressed_no_signal(t == tab)
		(_pages[t] as Control).visible = not guided and t == tab
	for i in STEPS.size():
		_step_buttons[i].set_pressed_no_signal(i == step)
		_step_pages[i].visible = guided and i == step
	_prev_b.visible = guided and step > 0
	if step > 0:
		_prev_b.text = "Précédent : %s" % STEPS[step - 1][2]
	_next_b.visible = guided and step < STEPS.size() - 1
	if step < STEPS.size() - 1:
		_next_b.text = "Suivant : %s" % STEPS[step + 1][2]


func _build_start() -> void:
	var sec := _section("start")
	var blank := _list_button("Page blanche", Color(0.75, 0.78, 0.84), "Un peuple neutre, à composer de zéro.")
	blank.pressed.connect(func() -> void:
		open_new("")
		set_step(1))
	sec.add_child(blank)
	sec.add_child(UiTheme.section("Sur le modèle d'un peuple officiel"))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 6)
	sec.add_child(flow)
	for fid in GameData.faction_ids():
		flow.add_child(_model_button(fid))
	sec.add_child(UiTheme.dim("Vos peuples enregistrés se rouvrent depuis la bibliothèque, à gauche.", 13))


func _build_identity() -> void:
	var form := _section("names")
	form.custom_minimum_size = Vector2(380, 0)
	form.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_name_edit = _line(form, "Nom", "Le nom complet : « Lignées d'Ossarane ».", Species.NAME_MAX)
	_name_edit.text_changed.connect(func(t: String) -> void:
		if not _syncing:
			spec["name"] = t
			_refresh())
	_short_edit = _line(form, "Nom court", "Pour les cartes et les listes : « Ossarane ».", Species.SHORT_MAX)
	_short_edit.text_changed.connect(func(t: String) -> void:
		if not _syncing:
			spec["short"] = t
			_refresh())
	form = _section("look")
	form.custom_minimum_size = Vector2(380, 0)
	form.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	form.add_child(UiTheme.section("Couleur"))
	_color_row = HBoxContainer.new()
	_color_row.add_theme_constant_override("separation", 6)
	form.add_child(_color_row)
	for c in COLORS:
		var sw := Button.new()
		sw.custom_minimum_size = Vector2(30, 30)
		sw.focus_mode = Control.FOCUS_NONE
		sw.toggle_mode = true
		sw.tooltip_text = c
		sw.set_meta("color", c)
		sw.add_theme_stylebox_override("normal", UiTheme.box(Color.html(c), Color(0, 0, 0, 0), 0, 0))
		sw.add_theme_stylebox_override("hover", UiTheme.box(Color.html(c).lightened(0.15), Color(1, 1, 1, 0.5), 0, 1))
		sw.add_theme_stylebox_override("pressed", UiTheme.box(Color.html(c), Color(1, 1, 1, 0.95), 0, 2))
		sw.add_theme_stylebox_override("hover_pressed", UiTheme.box(Color.html(c), Color(1, 1, 1, 0.95), 0, 2))
		sw.pressed.connect(func() -> void:
			spec["color"] = c
			_refresh())
		_color_row.add_child(sw)
	form.add_child(UiTheme.section("Style de vaisseaux"))
	_style_select = OptionButton.new()
	for s in Species.parts()["ship_styles"]:
		_style_select.add_item(String(STYLE_LABELS.get(s, s)))
	_style_select.tooltip_text = "Les sprites et modèles 3D d'un peuple officiel, teints à vos couleurs. Les formes propres viendront avec les illustrations."
	_style_select.item_selected.connect(func(i: int) -> void:
		spec["ship_style"] = String(Species.parts()["ship_styles"][i])
		_refresh())
	form.add_child(_style_select)
	form = _section("temper")
	form.custom_minimum_size = Vector2(380, 0)
	form.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	form.add_child(UiTheme.section("Tempérament quand l'IA le joue"))
	_temper_select = OptionButton.new()
	for t: Dictionary in Species.parts()["temperaments"]:
		_temper_select.add_item("%s : %s" % [t["label"], t["text"]])
	_temper_select.item_selected.connect(func(i: int) -> void:
		spec["temperament"] = int(Species.parts()["temperaments"][i]["id"])
		_refresh())
	form.add_child(_temper_select)
	# Talent de recherche (props 21 et 71 de l'arbre) : une brique choisie comme un trait, selon les couches.
	form = _section("talent")
	form.custom_minimum_size = Vector2(380, 0)
	form.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	form.add_child(UiTheme.section("Talent de recherche"))
	_talent_select = OptionButton.new()
	_talent_select.tooltip_text = "Par défaut, le talent vient des couches (souvent du credo). Les talents proposés dépendent du gouvernement et de l'archétype."
	_talent_select.item_selected.connect(func(i: int) -> void:
		if _syncing:
			return
		spec["research_talent"] = "" if i <= 0 else _talent_ids[i - 1]
		_refresh())
	form.add_child(_talent_select)
	var lore_col := _section("lore")
	lore_col.add_theme_constant_override("separation", 6)
	lore_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lore_col.add_child(UiTheme.section("Histoire"))
	_lore_edit = TextEdit.new()
	_lore_edit.custom_minimum_size = Vector2(380, 250)
	_lore_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_lore_edit.placeholder_text = "Quelques lignes de chronique : d'où vient ce peuple, ce qu'il veut, ce qu'on dit de lui."
	_lore_edit.text_changed.connect(func() -> void:
		if not _syncing:
			_disarm_propose()
			spec["lore"] = _lore_edit.text.substr(0, Species.LORE_MAX)
			_refresh())
	lore_col.add_child(_lore_edit)
	_propose_b = Button.new()
	_propose_b.text = PROPOSE_TEXT
	_propose_b.focus_mode = Control.FOCUS_NONE
	_propose_b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_propose_b.tooltip_text = "Écrit trois lignes tirées de vos choix : le corps et le monde natal, le gouvernement et le credo, l'origine. À reprendre à votre main."
	_propose_b.pressed.connect(func() -> void: propose_chronicle())
	lore_col.add_child(_propose_b)
	var gallery := _section("portraits")
	gallery.add_child(UiTheme.section("Portrait (libre ; ceux de l'archétype en premier)"))
	_portrait_grid = GridContainer.new()
	_portrait_grid.columns = 8
	_portrait_grid.add_theme_constant_override("h_separation", 8)
	_portrait_grid.add_theme_constant_override("v_separation", 8)
	gallery.add_child(_portrait_grid)


func _build_layers() -> void:
	for layer in Species.layers():
		var page := _section("layer_" + String(layer))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		page.add_child(row)
		var l := Label.new()
		l.text = String(LAYER_LABELS.get(layer, layer))
		l.custom_minimum_size = Vector2(130, 0)
		row.add_child(l)
		var sel := OptionButton.new()
		sel.custom_minimum_size = Vector2(260, 0)
		for b: Dictionary in Species.options(String(layer)):
			sel.add_item(String(b["label"]))
		var lay := String(layer)
		sel.item_selected.connect(func(i: int) -> void:
			if not _syncing:
				set_layer(lay, String(Species.options(lay)[i]["id"])))
		row.add_child(sel)
		_layer_selects[layer] = sel
		var txt := RichTextLabel.new()
		txt.bbcode_enabled = true
		txt.fit_content = true
		txt.scroll_active = false
		txt.custom_minimum_size = Vector2(780, 0)
		txt.add_theme_font_size_override("normal_font_size", 13)
		txt.add_theme_font_size_override("bold_font_size", 13)
		page.add_child(txt)
		_layer_texts[layer] = txt
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 14)
	_section("biomes").add_child(brow)
	var bl := Label.new()
	bl.text = "Biomes"
	bl.custom_minimum_size = Vector2(130, 0)
	brow.add_child(bl)
	for i in 2:
		var sel := OptionButton.new()
		sel.custom_minimum_size = Vector2(200, 0)
		for b in Species.parts()["biomes"]:
			sel.add_item("%s %s" % [BIOME_LABELS.get(b, b), "(monde natal, 100 %)" if i == 0 else "(80 %)"])
		var idx := i
		sel.item_selected.connect(func(k: int) -> void:
			if _syncing:
				return
			var bs: Array = spec.get("biomes", ["continental", "ocean"]).duplicate()
			bs[idx] = String(Species.parts()["biomes"][k])
			spec["biomes"] = bs
			_refresh())
		brow.add_child(sel)
		_biome_selects.append(sel)


func _build_traits() -> void:
	var page := _section("traits")
	page.add_theme_constant_override("separation", 10)
	_budget_label = Label.new()
	_budget_label.add_theme_font_size_override("font_size", 17)
	page.add_child(_budget_label)
	var b := Species.budget()
	var rules := UiTheme.paragraph("%d points de traits, %d traits au plus. Les défauts rendent des points (%d au plus). Un trait de croissance coûte %d point de plus, et un seul est permis. Un défaut qu'une couche annule est refusé." % [
			int(b["points"]), int(b["max_traits"]), int(b["max_flaws"]), int(b["growth_extra"])], 790, 13)
	rules.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	page.add_child(rules)
	page.add_child(UiTheme.section("Traits choisis"))
	_chosen_row = HFlowContainer.new()
	_chosen_row.add_theme_constant_override("h_separation", 6)
	_chosen_row.add_theme_constant_override("v_separation", 6)
	_chosen_row.custom_minimum_size = Vector2(0, 34)
	page.add_child(_chosen_row)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 16)
	page.add_child(cols)
	var good := VBoxContainer.new()
	good.custom_minimum_size = Vector2(395, 0)
	good.add_child(UiTheme.section("Qualités"))
	cols.add_child(good)
	_good_list = VBoxContainer.new()
	_good_list.add_theme_constant_override("separation", 4)
	good.add_child(_good_list)
	var bad := VBoxContainer.new()
	bad.custom_minimum_size = Vector2(395, 0)
	bad.add_child(UiTheme.section("Défauts"))
	cols.add_child(bad)
	_bad_list = VBoxContainer.new()
	_bad_list.add_theme_constant_override("separation", 4)
	bad.add_child(_bad_list)


func _build_preview() -> void:
	var col := VBoxContainer.new()
	col.position = Vector2(1180, 74)
	col.custom_minimum_size = Vector2(390, 0)
	col.add_theme_constant_override("separation", 8)
	add_child(col)
	col.add_child(_header("Aperçu"))
	var frame := _frame(col, 0)
	frame.custom_minimum_size = Vector2(390, 640)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 6)
	frame.add_child(inner)
	_preview_art = Widgets.ArtSlot.new("", Vector2(390, 230), UiTheme.ACCENT, "faction")
	inner.add_child(_preview_art)
	var pad := MarginContainer.new()
	for side in ["left", "right"]:
		pad.add_theme_constant_override("margin_" + side, 12)
	pad.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inner.add_child(pad)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	pad.add_child(box)
	_preview_name = UiTheme.title("", 22)
	box.add_child(_preview_name)
	_preview_budget = Label.new()
	box.add_child(_preview_budget)
	_preview_errors = UiTheme.paragraph("", 360, 13)
	_preview_errors.add_theme_color_override("font_color", UiTheme.BAD)
	box.add_child(_preview_errors)
	_preview_rules = RichTextLabel.new()
	_preview_rules.bbcode_enabled = true
	_preview_rules.scroll_active = true
	_preview_rules.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview_rules.custom_minimum_size = Vector2(360, 300)
	_preview_rules.add_theme_font_size_override("normal_font_size", 13)
	_preview_rules.add_theme_font_size_override("bold_font_size", 13)
	box.add_child(_preview_rules)


func _build_footer() -> void:
	var back_b := Widgets.RoundButton.new("back", "Retour")
	back_b.tooltip_text = "Échap"
	back_b.anchor_top = 1.0
	back_b.anchor_bottom = 1.0
	back_b.offset_left = 28
	back_b.offset_top = -76
	back_b.offset_bottom = -76 + back_b.custom_minimum_size.y
	back_b.pressed.connect(func() -> void: back_requested.emit())
	add_child(back_b)
	var go := Widgets.RoundButton.new("check", "Enregistrer")
	go.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	go.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	go.offset_right = -32
	go.offset_left = -32 - go.custom_minimum_size.x
	go.offset_top = -76
	go.offset_bottom = -76 + go.custom_minimum_size.y
	go.pressed.connect(func() -> void: save())
	add_child(go)
	set_meta("save_button", go)
	_status_label = UiTheme.dim("", 14)
	_status_label.anchor_top = 1.0
	_status_label.anchor_bottom = 1.0
	_status_label.anchor_left = 0.5
	_status_label.anchor_right = 0.5
	_status_label.offset_left = -420
	_status_label.offset_right = 340
	_status_label.offset_top = -66
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status_label)


# --- Rafraîchissement ---------------------------------------------------------------------------

## Remet tous les contrôles à l'image du spec (après ouverture ou changement de couche).
## Liste des talents qui conviennent aux couches choisies ; un talent devenu impossible est retiré.
func _sync_talents() -> void:
	if _talent_select == null:
		return
	_talent_ids = Species.talent_choices(spec)
	if String(spec.get("research_talent", "")) != "" and not _talent_ids.has(String(spec["research_talent"])):
		spec["research_talent"] = ""
	_talent_select.clear()
	_talent_select.add_item("Selon les couches")
	for t in _talent_ids:
		var td: Dictionary = Species.talents()[t]
		_talent_select.add_item(String(td["name"]))
		_talent_select.set_item_tooltip(_talent_select.item_count - 1, String(td["text"]))
	_talent_select.select(_talent_ids.find(String(spec.get("research_talent", ""))) + 1)


func _sync_all() -> void:
	if _name_edit == null:
		return
	_syncing = true
	_disarm_delete()
	_disarm_propose()
	_name_edit.text = String(spec.get("name", ""))
	_short_edit.text = String(spec.get("short", ""))
	_lore_edit.text = String(spec.get("lore", ""))
	_style_select.select(maxi(0, (Species.parts()["ship_styles"] as Array).find(String(spec.get("ship_style", "")))))
	var temps: Array = Species.parts()["temperaments"]
	for i in temps.size():
		if int(temps[i]["id"]) == int(spec.get("temperament", 0)):
			_temper_select.select(i)
	_sync_talents()
	for layer in _layer_selects:
		var opts := Species.options(String(layer))
		for i in opts.size():
			if String(opts[i]["id"]) == String(spec.get(layer, "")):
				(_layer_selects[layer] as OptionButton).select(i)
	var bs: Array = spec.get("biomes", [])
	for i in mini(2, bs.size()):
		_biome_selects[i].select(maxi(0, (Species.parts()["biomes"] as Array).find(String(bs[i]))))
	_syncing = false
	_rebuild_portraits()
	_rebuild_list()
	_refresh()


func _rebuild_portraits() -> void:
	for c in _portrait_grid.get_children():
		c.queue_free()
	var col := Color.html(String(spec.get("color", "#9b7fd4")))
	for p: Dictionary in Species.gallery(String(spec.get("archetype", ""))):
		var b := Button.new()
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(92, 114)
		b.tooltip_text = String(p["label"])
		var clear := StyleBoxEmpty.new()
		for st in ["normal", "hover", "pressed", "hover_pressed"]:
			b.add_theme_stylebox_override(st, clear)
		var art := Widgets.ArtSlot.new("portrait_" + String(p["id"]), Vector2(92, 114), col, "faction")
		b.add_child(art)
		var frame := Panel.new()
		frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(frame)
		b.set_meta("id", String(p["id"]))
		b.set_meta("frame", frame)
		b.set_meta("art", art)
		var pid := String(p["id"])
		b.pressed.connect(func() -> void: set_portrait(pid))
		_portrait_grid.add_child(b)


## Met à jour ce qui dépend du spec sans reconstruire les champs de saisie.
func _refresh() -> void:
	if _preview_name == null:
		return
	var col := Color.html(String(spec.get("color", "#9b7fd4"))) if Color.html_is_valid(String(spec.get("color", ""))) else UiTheme.ACCENT
	for sw in _color_row.get_children():
		(sw as Button).set_pressed_no_signal(String(sw.get_meta("color")) == String(spec.get("color", "")))
	for b in _portrait_grid.get_children():
		if b.is_queued_for_deletion():
			continue
		var on := String(b.get_meta("id")) == String(spec.get("portrait", ""))
		(b as Button).set_pressed_no_signal(on)
		(b.get_meta("frame") as Panel).add_theme_stylebox_override("panel", UiTheme.box(Color(0, 0, 0, 0), UiTheme.ACCENT if on else Color(1, 1, 1, 0.08), 0, 2 if on else 1))
		var art := b.get_meta("art") as Widgets.ArtSlot
		art.tint = col
		art.queue_redraw()
	for layer in _layer_texts:
		_layer_texts[layer].text = _brick_bbcode(String(layer), col)
	_refresh_traits(col)
	# Aperçu.
	_preview_art.set_art("portrait_" + String(spec.get("portrait", "")), col, "faction")
	_preview_name.text = String(spec.get("name", ""))
	_preview_name.add_theme_color_override("font_color", col.lightened(0.4))
	var c := Species.cost(spec)
	_preview_budget.text = "Traits : %d / %d points · %d / %d traits" % [int(c["used"]), int(c["budget"]), int(c["count"]), int(Species.budget()["max_traits"])]
	_preview_budget.add_theme_color_override("font_color", UiTheme.BAD if int(c["left"]) < 0 else UiTheme.TEXT_DIM)
	var probe := spec.duplicate(true)
	probe["id"] = editing_id if editing_id != "" else Species.make_id(String(spec.get("name", "")), GameData.library_faction_ids())
	var errs := Species.errors(probe)
	_preview_errors.text = "" if errs.is_empty() else "À corriger : " + " ; ".join(PackedStringArray(errs))
	(get_meta("save_button") as Button).disabled = not errs.is_empty()
	# Le refus se montre à l'étape en cause : sur le fil, et en tête de la page.
	var by_step := step_errors()
	for i in _step_buttons.size():
		var mine: PackedStringArray = by_step[i]
		var b := _step_buttons[i]
		b.text = "%d  %s%s" % [i + 1, String(STEPS[i][1]).to_upper(), "" if mine.is_empty() else "  !"]
		b.tooltip_text = String(STEPS[i][2]) + ("" if mine.is_empty() else "\nÀ corriger : " + " ; ".join(mine))
		for key in ["font_color", "font_pressed_color", "font_hover_color", "font_hover_pressed_color"]:
			if mine.is_empty():
				b.remove_theme_color_override(key)
			else:
				b.add_theme_color_override(key, UiTheme.BAD)
		_step_errors[i].text = "" if mine.is_empty() else "À corriger ici : " + " ; ".join(mine)
		_step_errors[i].visible = not mine.is_empty()
	var lines := PackedStringArray()
	# L'aperçu se montre même si le peuple n'est pas encore enregistrable (nom vide, trop de traits…),
	# tant que ses couches existent : on voit ce qu'on compose.
	if _layers_ok(probe):
		var built := Species.build(probe)
		lines.append(_registre_bbcode(String(built.get("registre", "")), col))
		lines.append(MainMenu.trait_bbcode(built, col))
		var rs: Dictionary = built.get("research", {})
		if rs.has("name"):
			lines.append("[b][color=#%s]%s[/color][/b]  %s" % [col.lightened(0.35).to_html(false), rs["name"], rs.get("text", "")])
	var u := Species.unlocks(spec)
	if not (u["victories"] as Array).is_empty():
		lines.append("[b]Victoire de peuple :[/b] " + ", ".join(PackedStringArray(u["victories"])))
	if not (u["abilities"] as Array).is_empty():
		lines.append("[b]Talents diplomatiques :[/b] " + ", ".join(PackedStringArray(u["abilities"])))
	if not (u["ships"] as Array).is_empty():
		lines.append("[b]Vaisseaux propres :[/b] " + ", ".join(PackedStringArray(u["ships"])))
	_preview_rules.text = "\n".join(lines)


## Le registre dans l'aperçu : son nom et l'opinion qu'il vaut auprès de chaque registre, pour qu'un
## changement de registre se voie (les registres sans mécanique propre ne jouent que sur le ton et
## l'opinion ; les règles qui suivent viennent des autres couches et des traits).
func _registre_bbcode(reg: String, col: Color) -> String:
	var good := PackedStringArray()
	var bad := PackedStringArray()
	for p: Array in Diplomacy.registre_opinions(reg):
		var label := "même registre" if String(p[0]) == reg else String(p[0])
		if int(p[1]) > 0:
			good.append("%s %+d" % [label, int(p[1])])
		elif int(p[1]) < 0:
			bad.append("%s %+d" % [label, int(p[1])])
	var out := "[b][color=#%s]Registre : %s[/color][/b]" % [col.lightened(0.35).to_html(false), reg]
	if not good.is_empty():
		out += "\n[color=#%s]Bien vu : %s[/color]" % [UiTheme.GOOD.to_html(false), ", ".join(good)]
	if not bad.is_empty():
		out += "\n[color=#%s]Mal vu : %s[/color]" % [UiTheme.BAD.to_html(false), ", ".join(bad)]
	return out


func _layers_ok(s: Dictionary) -> bool:
	for layer in Species.layers():
		if Species.brick(String(layer), String(s.get(layer, ""))).is_empty():
			return false
	return true


func _brick_bbcode(layer: String, col: Color) -> String:
	var b := Species.brick(layer, String(spec.get(layer, "")))
	if b.is_empty():
		return ""
	var out := PackedStringArray([String(b.get("text", ""))])
	for t: Dictionary in b.get("traits", []):
		out.append("[b][color=#%s]%s[/color][/b]  %s" % [col.lightened(0.35).to_html(false), t["name"], t["text"]])
	for l2 in b.get("requires", {}):
		out.append("[color=#%s]Demande : %s[/color]" % [UiTheme.WARN.to_html(false), Species._labels(String(l2), b["requires"][l2])])
	return "\n".join(out)


func _refresh_traits(col: Color) -> void:
	var c := Species.cost(spec)
	var b := Species.budget()
	_budget_label.text = "Points restants : %d    Traits : %d / %d    Défauts : %d / %d" % [int(c["left"]), int(c["count"]), int(b["max_traits"]), int(c["flaws"]), int(b["max_flaws"])]
	_budget_label.add_theme_color_override("font_color", UiTheme.BAD if int(c["left"]) < 0 else UiTheme.ACCENT)
	for n in _chosen_row.get_children():
		n.queue_free()
	for tid in spec.get("traits", []):
		var t := Species.trait_def(String(tid))
		var chip := Button.new()
		chip.focus_mode = Control.FOCUS_NONE
		chip.text = "%s  %+d  ✕" % [t.get("label", tid), Species.trait_cost(String(tid))]
		chip.tooltip_text = "Retirer : " + String(t.get("text", ""))
		chip.add_theme_stylebox_override("normal", UiTheme.box(Color(col, 0.25), Color(col, 0.7), 6, 1))
		chip.pressed.connect(func() -> void: toggle_trait(String(tid)))
		_chosen_row.add_child(chip)
	if (spec.get("traits", []) as Array).is_empty():
		_chosen_row.add_child(UiTheme.dim("Aucun : choisissez dans les listes ci-dessous.", 13))
	for list in [_good_list, _bad_list]:
		for n in list.get_children():
			n.queue_free()
	for tid in Species.trait_ids():
		var t := Species.trait_def(tid)
		var on := (spec.get("traits", []) as Array).has(tid)
		var why := add_refusal(tid)
		var row := Button.new()
		row.toggle_mode = true
		row.focus_mode = Control.FOCUS_NONE
		row.set_pressed_no_signal(on)
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.custom_minimum_size = Vector2(390, 30)
		var tags := PackedStringArray()
		if bool(t.get("growth", false)):
			tags.append("croissance")
		if int(t.get("cost", 0)) == 0:
			tags.append("mixte")
		row.text = "%s%s" % [t["label"], ("  (%s)" % ", ".join(tags)) if not tags.is_empty() else ""]
		row.tooltip_text = String(t["text"]) + ("" if why == "" or on else "\n\nImpossible : " + why)
		row.disabled = why != "" and not on
		row.add_theme_stylebox_override("normal", UiTheme.box(Color(0.05, 0.07, 0.1, 0.9), Color(1, 1, 1, 0.08), 6, 1))
		row.add_theme_stylebox_override("pressed", UiTheme.box(Color(col, 0.3), Color(col, 0.9), 6, 1))
		row.add_theme_stylebox_override("hover_pressed", UiTheme.box(Color(col, 0.38), Color(col, 1.0), 6, 1))
		var cost_l := Label.new()
		cost_l.text = "%+d" % Species.trait_cost(tid)
		cost_l.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
		cost_l.offset_left = -40
		cost_l.offset_right = -10
		cost_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		cost_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cost_l.add_theme_color_override("font_color", UiTheme.BAD if Species.trait_cost(tid) > 0 else UiTheme.GOOD)
		cost_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(cost_l)
		row.pressed.connect(func() -> void: toggle_trait(tid))
		var desc := UiTheme.paragraph(String(t["text"]), 380, 12)
		desc.add_theme_color_override("font_color", UiTheme.TEXT_DIM if why == "" or on else Color(UiTheme.TEXT_DIM, 0.5))
		var target := _bad_list if int(t.get("cost", 0)) < 0 else _good_list
		target.add_child(row)
		target.add_child(desc)


# --- Petits outils ------------------------------------------------------------------------------

func _set_status(text: String) -> void:
	status = text
	if _status_label:
		_status_label.text = text


func _disarm_delete() -> void:
	_delete_armed = false
	if _delete_b:
		_delete_b.text = "Supprimer"
		_delete_b.disabled = editing_id == ""


func _header(text: String) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_override("font", UiTheme.font(400, 1))
	l.add_theme_font_size_override("font_size", 19)
	return l


func _frame(parent: Control, padding := 12) -> PanelContainer:
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UiTheme.box(Color(0.03, 0.04, 0.06, 0.75), Color(1, 1, 1, 0.1), padding, 1))
	parent.add_child(frame)
	return frame


func _small_button(text: String, tip: String) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return b


func _list_button(text: String, col: Color, tip: String) -> Button:
	var b := Button.new()
	b.text = "      " + text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(240, 30)
	var dot := Widgets.Dot.new(col, 10)
	dot.position = Vector2(10, 10)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(dot)
	return b


func _line(parent: Control, label: String, tip: String, max_len: int) -> LineEdit:
	parent.add_child(UiTheme.section(label))
	var e := LineEdit.new()
	e.max_length = max_len
	e.tooltip_text = tip
	parent.add_child(e)
	return e
