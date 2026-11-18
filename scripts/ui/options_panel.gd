class_name OptionsPanel
extends VBoxContainer
## Page Options, partagée par le menu principal et le menu du jeu, sur le modèle des 4X « épurés » :
## un titre fin centré, une rangée d'onglets, puis une ligne par réglage (libellé à gauche,
## valeur dans une case sombre à droite), et des boutons ronds en bas.
## Les réglages s'appliquent tout de suite et sont propres au poste (UiSettings, user://settings.cfg).

signal back_requested

const ROW_WIDTH := 760.0
const VALUE_WIDTH := 300.0
const TABS := [["display", "Affichage"], ["game", "Partie"], ["announce", "Annonces"], ["controls", "Commandes"]]

var tab := "display"
## Rangée des boutons du bas (Retour, Valeurs par défaut), que le menu principal place dans les coins.
var footer: HBoxContainer
var _tabs := {}
var _pages := {}
var _fullscreen: Button
var _auto_pause: Button
var _silhouettes: Button
var _detail: Button
var _scale_b: Button
var _scale: Button
var _preset: Button
var _anim: Button
var _sound: Button
var _search: LineEdit
## Lignes des types d'annonce (tests) : type -> {"row", "look", "pause", "auto"}.
var announce_rows := {}


func _ready() -> void:
	add_theme_constant_override("separation", 14)
	custom_minimum_size = Vector2(ROW_WIDTH, 0)
	var title := UiTheme.title("Options", 34)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)
	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 40)
	add_child(tabs)
	for t in TABS:
		var b := Button.new()
		b.theme_type_variation = &"TabButton"
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.text = String(t[1]).to_upper()
		var id: String = t[0]
		b.pressed.connect(func() -> void: show_tab(id))
		tabs.add_child(b)
		_tabs[id] = b
	var rule := ColorRect.new()
	rule.color = Color(1, 1, 1, 0.14)
	rule.custom_minimum_size = Vector2(0, 1)
	add_child(rule)

	var display := _page("display")
	_fullscreen = _toggle_row(display, "Plein écran", "Touche F11, à tout moment.", func() -> void:
		UiSettings.toggle_fullscreen()
		sync())
	var srow := _row(display, "Échelle de l'interface", "Agrandit textes et panneaux, pour les grands écrans.")
	_scale = _value_box("", false) as Button
	_scale.tooltip_text = "Clic : 100 %, 125 %, 150 %"
	_scale.pressed.connect(func() -> void:
		UiSettings.cycle_ui_scale()
		sync())
	srow.add_child(_scale)
	var drow := _row(display, "Détail des vues de bataille", "Décors, débris et fumées des replays. Sobre pour les petites machines.")
	_detail = _value_box("", false) as Button
	_detail.tooltip_text = "Clic : Sobre, Normal, Riche"
	_detail.pressed.connect(func() -> void:
		UiSettings.cycle_replay_detail()
		sync())
	drow.add_child(_detail)
	var brow := _row(display, "Échelle des batailles au sol", "Nombre de figurines par régiment : de l'escarmouche à la grande bataille.")
	_scale_b = _value_box("", false) as Button
	_scale_b.tooltip_text = "Clic : Escarmouche, Bataille, Grande bataille"
	_scale_b.pressed.connect(func() -> void:
		UiSettings.cycle_battle_scale()
		sync())
	brow.add_child(_scale_b)
	_silhouettes = _toggle_row(display, "Silhouettes des flottes sur la carte",
			"Remplace le chevron par la silhouette du plus gros vaisseau, au style de son peuple.", func() -> void:
		UiSettings.fleet_silhouettes = not UiSettings.fleet_silhouettes
		UiSettings.save_settings()
		sync())
	var game := _page("game")
	_auto_pause = _toggle_row(game, "Pause automatique dans les écrans d'empire",
			"Le temps s'arrête quand vous consultez l'économie ou vos colonies, et repart à la fermeture.", func() -> void:
		UiSettings.auto_pause_menus = not UiSettings.auto_pause_menus
		UiSettings.save_settings()
		sync())
	_build_announce(_page("announce"))
	var controls := _page("controls")
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(ROW_WIDTH, 360)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	controls.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	for g in PauseMenu.SHORTCUT_GROUPS:
		list.add_child(UiTheme.section(String(g[0])))
		for sc in g[1]:
			var row := _row(list, String(sc[1]), "")
			row.add_child(_value_box(String(sc[0]), true))

	var foot := HBoxContainer.new()
	footer = foot
	add_child(foot)
	var back := Widgets.RoundButton.new("back", "Retour", 18)
	back.tooltip_text = "Échap"
	back.pressed.connect(func() -> void: back_requested.emit())
	foot.add_child(back)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(spacer)
	var reset := Widgets.RoundButton.new("back", "Valeurs par défaut", 18)
	reset.glyph = "reset"
	reset.tooltip_text = "Fenêtré, interface à 100 %, sans pause automatique, annonces au préréglage Stratège."
	reset.pressed.connect(reset_defaults)
	foot.add_child(reset)
	show_tab("display")
	sync()


func show_tab(id: String) -> void:
	tab = id
	for t in _tabs:
		(_tabs[t] as Button).set_pressed_no_signal(t == id)
		(_pages[t] as Control).visible = t == id


## Remet les réglages par défaut (fenêtré, pas de pause automatique).
func reset_defaults() -> void:
	if UiSettings.fullscreen:
		UiSettings.toggle_fullscreen()
	UiSettings.ui_scale = 1.0
	UiSettings.apply()
	UiSettings.auto_pause_menus = false
	UiSettings.replay_detail = "normal"
	UiSettings.battle_scale = "escarmouche"
	UiSettings.save_settings()
	AnnounceSettings.reset()
	sync()


## Recopie les réglages actuels dans les cases.
func sync() -> void:
	if _fullscreen == null:
		return
	_set_toggle(_fullscreen, UiSettings.fullscreen)
	_set_toggle(_auto_pause, UiSettings.auto_pause_menus)
	_set_toggle(_silhouettes, UiSettings.fleet_silhouettes)
	_scale.text = "%d %%" % roundi(UiSettings.ui_scale * 100.0)
	_detail.text = String(GameData.battle_visuals().get("detail", {}).get("labels", {}).get(UiSettings.replay_detail, UiSettings.replay_detail))
	_scale_b.text = String(GameData.battle_visuals().get("ground", {}).get("scale_labels", {}).get(UiSettings.battle_scale, UiSettings.battle_scale))
	_preset.text = AnnounceSettings.preset_label()
	_anim.text = AnnounceSettings.anim_label()
	_set_toggle(_sound, AnnounceSettings.sound)
	for kind in announce_rows:
		_sync_announce_row(String(kind))


## Onglet Annonces (étude de la fenêtre d'événement, prop. 29 à 32) : préréglage, animations, son, puis
## pour chaque type, rangé par famille : apparence (Auto, Chronique, Avis, Fenêtre, Fanfare), pause,
## ouverture automatique. Une recherche filtre la liste.
func _build_announce(page: VBoxContainer) -> void:
	var prow := _row(page, "Préréglage", "Chroniqueur : tout s'ouvre. Stratège : l'essentiel. Silence : rien ne s'ouvre, sauf les Fanfares.")
	_preset = _value_box("", false) as Button
	_preset.tooltip_text = "Clic : Chroniqueur, Stratège, Silence"
	_preset.pressed.connect(func() -> void:
		AnnounceSettings.cycle_preset()
		sync())
	prow.add_child(_preset)
	var arow := _row(page, "Animations des fenêtres", "Durée des fondus d'ouverture.")
	_anim = _value_box("", false) as Button
	_anim.tooltip_text = "Clic : Normales, Rapides, Instantanées"
	_anim.pressed.connect(func() -> void:
		AnnounceSettings.cycle_anim()
		sync())
	arow.add_child(_anim)
	_sound = _toggle_row(page, "Son des annonces", "Un son par famille d'annonce, quand l'habillage sonore sera là.", func() -> void:
		AnnounceSettings.sound = not AnnounceSettings.sound
		AnnounceSettings.save_settings()
		sync())
	_search = LineEdit.new()
	_search.placeholder_text = "Chercher un type d'annonce…"
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_t: String) -> void: _filter_announce())
	page.add_child(_search)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	var hl := UiTheme.dim("TYPE", 12)
	hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(hl)
	for t in ["APPARENCE", "PAUSE", "S'OUVRE"]:
		var l := UiTheme.dim(t, 12)
		l.custom_minimum_size = Vector2(118, 0)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		head.add_child(l)
	page.add_child(head)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(ROW_WIDTH, 190)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 3)
	scroll.add_child(list)
	for fam in Announce.family_ids():
		var sec := UiTheme.section(String(Announce.family_def(fam).get("label", fam)))
		sec.add_theme_color_override("font_color", Announce.family_color(fam))
		sec.set_meta("family", fam)
		list.add_child(sec)
		for kind in Announce.kind_ids():
			if Announce.family_of(kind) != fam:
				continue
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			var l := Label.new()
			l.text = String(Announce.kind_def(kind).get("title", kind))
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			l.add_theme_font_size_override("font_size", 14)
			row.add_child(l)
			var look := _small_box()
			look.tooltip_text = "Clic : Auto, Chronique, Avis, Fenêtre, Fanfare"
			look.pressed.connect(func() -> void:
				AnnounceSettings.cycle_look(kind)
				_sync_announce_row(kind))
			row.add_child(look)
			var pause := _small_box()
			pause.tooltip_text = "La fenêtre de ce type met-elle la partie en pause (en solo) ?"
			pause.pressed.connect(func() -> void:
				AnnounceSettings.toggle_pause(kind, _default_gravity(kind))
				_sync_announce_row(kind))
			row.add_child(pause)
			var auto := _small_box()
			auto.tooltip_text = "Non : l'annonce reste dans la colonne de droite sans s'ouvrir."
			auto.pressed.connect(func() -> void:
				AnnounceSettings.set_auto_open(kind, not AnnounceSettings.auto_open(kind))
				_sync_announce_row(kind))
			row.add_child(auto)
			row.set_meta("family", fam)
			list.add_child(row)
			announce_rows[kind] = {"row": row, "look": look, "pause": pause, "auto": auto, "label": l.text}


func _small_box() -> Button:
	var b := _value_box("", false) as Button
	b.custom_minimum_size = Vector2(118, 28)
	b.add_theme_font_size_override("font_size", 13)
	return b


## Gravité d'un type pour l'empire concerné (sert au défaut de la pause).
func _default_gravity(kind: String) -> int:
	var look := AnnounceSettings.look_of(kind)
	if look != AnnounceSettings.AUTO:
		return look
	return int((Announce.kind_def(kind).get("g", [1]) as Array)[0])


func _sync_announce_row(kind: String) -> void:
	var r: Dictionary = announce_rows[kind]
	(r["look"] as Button).text = AnnounceSettings.look_label(kind)
	var p := AnnounceSettings.pauses_for(kind, _default_gravity(kind))
	(r["pause"] as Button).text = "Pause" if p else "Non"
	(r["pause"] as Button).add_theme_color_override("font_color", UiTheme.ACCENT if p else UiTheme.TEXT_DIM)
	var a := AnnounceSettings.auto_open(kind)
	(r["auto"] as Button).text = "Oui" if a else "Colonne"
	(r["auto"] as Button).add_theme_color_override("font_color", UiTheme.ACCENT if a else UiTheme.TEXT_DIM)


func _filter_announce() -> void:
	var q := _search.text.strip_edges().to_lower()
	var fams := {}
	for kind in announce_rows:
		var r: Dictionary = announce_rows[kind]
		var show := q == "" or String(r["label"]).to_lower().contains(q) or String(kind).contains(q)
		(r["row"] as Control).visible = show
		if show:
			fams[Announce.family_of(String(kind))] = true
	var list := (announce_rows.values()[0]["row"] as Control).get_parent() if not announce_rows.is_empty() else null
	if list:
		for c in list.get_children():
			if c is Label and c.has_meta("family"):
				c.visible = fams.has(String(c.get_meta("family")))


func _page(id: String) -> VBoxContainer:
	var p := VBoxContainer.new()
	p.add_theme_constant_override("separation", 6)
	p.custom_minimum_size = Vector2(ROW_WIDTH, 360)
	add_child(p)
	_pages[id] = p
	return p


func _row(parent: Control, label: String, tip: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.tooltip_text = tip
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	parent.add_child(row)
	var l := Label.new()
	l.text = label
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", 16)
	row.add_child(l)
	return row


func _value_box(text: String, read_only: bool) -> Control:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.text = text
	b.custom_minimum_size = Vector2(VALUE_WIDTH, 36)
	b.add_theme_stylebox_override("normal", UiTheme.box(Color(0.0, 0.0, 0.0, 0.55), Color(0, 0, 0, 0), 6, 0))
	b.add_theme_stylebox_override("hover", UiTheme.box(Color(0.1, 0.13, 0.16, 0.9), Color(0, 0, 0, 0), 6, 0))
	b.add_theme_stylebox_override("disabled", UiTheme.box(Color(0.0, 0.0, 0.0, 0.4), Color(0, 0, 0, 0), 6, 0))
	b.add_theme_color_override("font_disabled_color", Color(UiTheme.TEXT, 0.8))
	b.disabled = read_only
	return b


func _toggle_row(parent: Control, label: String, tip: String, action: Callable) -> Button:
	var row := _row(parent, label, tip)
	var b := _value_box("", false) as Button
	b.tooltip_text = tip
	b.pressed.connect(action)
	row.add_child(b)
	return b


func _set_toggle(b: Button, on: bool) -> void:
	b.text = "Activé" if on else "Désactivé"
	b.add_theme_color_override("font_color", UiTheme.ACCENT if on else UiTheme.TEXT_DIM)
	b.add_theme_color_override("font_hover_color", UiTheme.ACCENT.lightened(0.3) if on else UiTheme.TEXT)
