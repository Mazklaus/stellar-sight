class_name OptionsPanel
extends VBoxContainer
## Page Options, partagée par le menu principal et le menu du jeu, sur le modèle des 4X « épurés » :
## un titre fin centré, une rangée d'onglets, puis une ligne par réglage (libellé à gauche,
## valeur dans une case sombre à droite), et des boutons ronds en bas.
## Les réglages s'appliquent tout de suite et sont propres au poste (UiSettings, user://settings.cfg).

signal back_requested

const ROW_WIDTH := 760.0
const VALUE_WIDTH := 300.0
const TABS := [["display", "Affichage"], ["map", "Carte"], ["game", "Partie"], ["sound", "Son"], ["announce", "Annonces"], ["controls", "Commandes"]]

var tab := "display"
## Rangée des boutons du bas (Retour, Valeurs par défaut), que le menu principal place dans les coins.
var footer: HBoxContainer
var _tabs := {}
var _pages := {}
var _fullscreen: Button
var _auto_pause: Button
var _autosave: Button
var _stop_intrusion: Button
var _stop_war: Button
var _stop_events: Button
var _warn_todo: Button
var _silhouettes: Button
var _emblems: Button
var _art_ids: Button
var _cargos: Button
var _labels: Button
var _glide: Button
var _detail: Button
var _scale_b: Button
var _scale: Button
var _preset: Button
var _anim: Button
var _sound: Button
var _search: LineEdit
## Infobulles (glossaire en jeu, prop. 16).
var _tip_links: Button
var _tip_delay: Button
var _tip_lock: Button
var _tip_mode: Button
## Cases de l'onglet Son (tests) : bus -> bouton du volume.
var volume_boxes := {}
var _profile: Button
var _background: Button
var _hover: Button
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
	tabs.add_theme_constant_override("separation", 26)
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
	_art_ids = _toggle_row(display, "Nom des images provisoires",
			"Tant qu'une illustration n'est pas déposée, son emplacement montre un tableau provisoire. Le nom du fichier attendu s'écrit dans le coin ; la liste complète est dans le Codex, à « Galerie des illustrations ».", func() -> void:
		UiSettings.art_ids = not UiSettings.art_ids
		UiSettings.save_settings()
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
	# Onglet Carte (refonte D3f) : ce que la carte montre, et comment elle passe d'un palier à l'autre.
	var map := _page("map")
	_emblems = _toggle_row(map, "Emblèmes des empires",
			"De loin, chaque empire porte son emblème au-dessus de son nom, sur son territoire.", func() -> void:
		UiSettings.map_emblems = not UiSettings.map_emblems
		UiSettings.save_settings()
		sync())
	_silhouettes = _toggle_row(map, "Silhouettes des flottes",
			"Remplace le chevron par la silhouette du plus gros vaisseau, au style de son peuple, à tous les paliers. De près, les silhouettes se montrent toujours.", func() -> void:
		UiSettings.fleet_silhouettes = not UiSettings.fleet_silhouettes
		UiSettings.save_settings()
		sync())
	_cargos = _toggle_row(map, "Cargos sur les routes commerciales",
			"De près, de petits cargos suivent vos routes. Sans eux, la carte ne se redessine que lorsqu'il s'y passe quelque chose.", func() -> void:
		UiSettings.map_cargos = not UiSettings.map_cargos
		UiSettings.save_settings()
		sync())
	var names_row := _row(map, "Noms des systèmes", "Quels systèmes portent leur nom sur la carte. Le système choisi ou survolé est toujours nommé.")
	_labels = _value_box("", false) as Button
	_labels.tooltip_text = "Clic : tous les systèmes explorés, ou les systèmes habités seulement"
	_labels.pressed.connect(func() -> void:
		UiSettings.cycle_map("labels")
		sync())
	names_row.add_child(_labels)
	var glide_row := _row(map, "Passage d'un palier à l'autre", "Le temps que met la carte à glisser quand on saute au palier Galaxie, Région ou Système par les trois boutons du cadran.")
	_glide = _value_box("", false) as Button
	_glide.tooltip_text = "Clic : Immédiat, Vif, Posé, Lent"
	_glide.pressed.connect(func() -> void:
		UiSettings.cycle_map("glide")
		sync())
	glide_row.add_child(_glide)
	map.add_child(UiTheme.dim("Les calques (routes, flottes, noms, curiosités, terrains) se cochent sur la carte, dans le sélecteur de lentilles.", 13))
	var game := _page("game")
	_auto_pause = _toggle_row(game, "Pause automatique dans les écrans d'empire",
			"Le temps s'arrête quand vous consultez l'économie ou vos colonies, et repart à la fermeture.", func() -> void:
		UiSettings.auto_pause_menus = not UiSettings.auto_pause_menus
		UiSettings.save_settings()
		sync())
	var arow := _row(game, "Sauvegarde automatique", "Le jeu enregistre la partie de lui-même, sur trois fichiers qui tournent. Le temps en pause ne compte pas.")
	_autosave = _value_box("", false) as Button
	_autosave.tooltip_text = "Clic : jamais, toutes les 5, 10 ou 20 minutes"
	_autosave.pressed.connect(func() -> void:
		var i := UiSettings.AUTOSAVE_CHOICES.find(UiSettings.autosave_minutes)
		UiSettings.autosave_minutes = UiSettings.AUTOSAVE_CHOICES[(i + 1) % UiSettings.AUTOSAVE_CHOICES.size()]
		UiSettings.save_settings()
		sync())
	arow.add_child(_autosave)
	game.add_child(UiTheme.section("Tour par tour : ce qui interrompt le tour"))
	_stop_intrusion = _toggle_row(game, "Une flotte étrangère armée entre chez vous",
			"Le tour s'arrête quand une flotte armée d'un autre empire, de pirates ou d'une crise arrive dans un de vos systèmes. Une bataille l'interrompt toujours.", func() -> void:
		UiSettings.turn_stop_intrusion = not UiSettings.turn_stop_intrusion
		UiSettings.save_settings()
		sync())
	_stop_war = _toggle_row(game, "On vous déclare la guerre",
			"Le tour s'arrête le jour où un empire vous déclare la guerre.", func() -> void:
		UiSettings.turn_stop_war = not UiSettings.turn_stop_war
		UiSettings.save_settings()
		sync())
	_stop_events = _toggle_row(game, "Un événement attend votre choix",
			"Le tour s'arrête quand un événement à choix arrive.", func() -> void:
		UiSettings.turn_stop_events = not UiSettings.turn_stop_events
		UiSettings.save_settings()
		sync())
	_warn_todo = _toggle_row(game, "Prévenir avant la fin du tour",
			"Avant de finir le tour, le jeu signale ce qui attend encore : décisions, propositions, recherche vide, chantiers libres, flottes sans ordres. Une seconde pression finit le tour quand même.", func() -> void:
		UiSettings.turn_warn_todo = not UiSettings.turn_warn_todo
		UiSettings.save_settings()
		sync())
	game.add_child(UiTheme.section("Infobulles et glossaire"))
	_tip_links = _toggle_row(game, "Termes du jeu colorés dans les infobulles",
			"Survolez un mot coloré pour son explication, puis un mot de cette explication, et ainsi de suite.", func() -> void:
		UiSettings.toggle_glossary_links()
		sync())
	var trow := _row(game, "Délai d'apparition", "Le temps que le curseur doit rester posé avant qu'une infobulle s'ouvre.")
	_tip_delay = _value_box("", false) as Button
	_tip_delay.tooltip_text = "Clic : 0,15 s, 0,35 s, 0,6 s, 1 s"
	_tip_delay.pressed.connect(func() -> void:
		UiSettings.cycle_tip_delay()
		sync())
	trow.add_child(_tip_delay)
	var mrow := _row(game, "Figer les infobulles", "Minuterie : elles se figent seules après un instant (la jauge du bas). Action : seulement au clic molette ou en tenant Maj.")
	_tip_mode = _value_box("", false) as Button
	_tip_mode.tooltip_text = "Clic : Minuterie, Action"
	_tip_mode.pressed.connect(func() -> void:
		UiSettings.cycle_tip_lock_mode()
		sync())
	mrow.add_child(_tip_mode)
	var lrow := _row(game, "Durée avant de figer", "En mode Minuterie, le temps avant qu'on puisse entrer dans l'infobulle.")
	_tip_lock = _value_box("", false) as Button
	_tip_lock.tooltip_text = "Clic : 0,4 s, 0,8 s, 1,5 s"
	_tip_lock.pressed.connect(func() -> void:
		UiSettings.cycle_tip_lock()
		sync())
	lrow.add_child(_tip_lock)
	_build_sound(_page("sound"))
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
	reset.tooltip_text = "Fenêtré, interface à 100 %, sans pause automatique, annonces au préréglage Stratège, volumes d'origine."
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
	UiSettings.autosave_minutes = 10
	UiSettings.fleet_silhouettes = false
	UiSettings.map_emblems = true
	UiSettings.art_ids = true
	UiSettings.map_cargos = true
	UiSettings.map_labels = "all"
	UiSettings.map_glide = "normal"
	UiSettings.replay_detail = "normal"
	UiSettings.battle_scale = "escarmouche"
	UiSettings.tip_delay = 0.35
	UiSettings.tip_lock = 0.8
	UiSettings.tip_lock_mode = "minuterie"
	UiSettings.glossary_links = true
	UiSettings._tips_changed()
	UiSettings.save_settings()
	AnnounceSettings.reset()
	SoundSettings.reset()
	sync()


## Recopie les réglages actuels dans les cases.
func sync() -> void:
	if _fullscreen == null:
		return
	_set_toggle(_fullscreen, UiSettings.fullscreen)
	_set_toggle(_auto_pause, UiSettings.auto_pause_menus)
	_autosave.text = "Jamais" if UiSettings.autosave_minutes <= 0 else "Toutes les %d minutes" % UiSettings.autosave_minutes
	_set_toggle(_stop_intrusion, UiSettings.turn_stop_intrusion)
	_set_toggle(_stop_war, UiSettings.turn_stop_war)
	_set_toggle(_stop_events, UiSettings.turn_stop_events)
	_set_toggle(_warn_todo, UiSettings.turn_warn_todo)
	_set_toggle(_silhouettes, UiSettings.fleet_silhouettes)
	_set_toggle(_emblems, UiSettings.map_emblems)
	_set_toggle(_art_ids, UiSettings.art_ids)
	_set_toggle(_cargos, UiSettings.map_cargos)
	_labels.text = String(UiSettings.MAP_LABEL_NAMES[UiSettings.map_labels])
	_glide.text = String(UiSettings.MAP_GLIDE_NAMES[UiSettings.map_glide])
	_scale.text = "%d %%" % roundi(UiSettings.ui_scale * 100.0)
	_detail.text = String(GameData.battle_visuals().get("detail", {}).get("labels", {}).get(UiSettings.replay_detail, UiSettings.replay_detail))
	_scale_b.text = String(GameData.battle_visuals().get("ground", {}).get("scale_labels", {}).get(UiSettings.battle_scale, UiSettings.battle_scale))
	_set_toggle(_tip_links, UiSettings.glossary_links)
	_tip_delay.text = ("%.2f s" % UiSettings.tip_delay).replace(".", ",").replace(",00 s", " s").replace("0 s", " s")
	_tip_lock.text = ("%.1f s" % UiSettings.tip_lock).replace(".", ",")
	_tip_mode.text = "Minuterie" if UiSettings.tip_lock_mode == "minuterie" else "Action (molette, Maj)"
	_preset.text = AnnounceSettings.preset_label()
	_anim.text = AnnounceSettings.anim_label()
	_set_toggle(_sound, AnnounceSettings.sound)
	for bus in volume_boxes:
		var vb := volume_boxes[bus] as Button
		vb.text = SoundSettings.volume_label(String(bus))
		vb.add_theme_color_override("font_color", UiTheme.TEXT_DIM if SoundSettings.volume(String(bus)) <= 0.001 else UiTheme.TEXT)
	_profile.text = SoundSettings.profile_label()
	_profile.tooltip_text = String(GameData.audio().get("profiles", {}).get(SoundSettings.profile_id(), {}).get("tip", ""))
	_set_toggle(_background, SoundSettings.background)
	_set_toggle(_hover, SoundSettings.hover)
	for kind in announce_rows:
		_sync_announce_row(String(kind))


## Onglet Son (étude du son, bloc K) : un volume par famille de sons, le profil d'écoute, le son quand
## le jeu passe au second plan, les sons de survol. Les lignes de volume viennent de data/audio.json.
func _build_sound(page: VBoxContainer) -> void:
	for d in GameData.audio().get("volumes", []):
		var bus := String(d["bus"])
		var row := _row(page, String(d["label"]), String(d.get("tip", "")))
		var box := _value_box("", false) as Button
		box.tooltip_text = "Clic : cran suivant. Clic droit : cran précédent."
		box.button_mask = MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_RIGHT
		box.gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_RIGHT:
				box.set_meta("recul", true))
		box.pressed.connect(func() -> void:
			SoundSettings.cycle_volume(bus, -1 if box.has_meta("recul") else 1)
			box.remove_meta("recul")
			sync())
		row.add_child(box)
		volume_boxes[bus] = box
	var prow := _row(page, "Profil d'écoute", "Adapte le mélange à ce qui diffuse le son.")
	_profile = _value_box("", false) as Button
	_profile.pressed.connect(func() -> void:
		SoundSettings.cycle_profile()
		sync())
	prow.add_child(_profile)
	_background = _toggle_row(page, "Son hors de la fenêtre", "Le son continue quand le jeu n'est plus au premier plan.", func() -> void:
		SoundSettings.background = not SoundSettings.background
		SoundSettings.save_settings()
		Son.apply_settings()
		sync())
	_hover = _toggle_row(page, "Sons de survol", "Un son discret quand le pointeur passe sur un bouton.", func() -> void:
		SoundSettings.hover = not SoundSettings.hover
		SoundSettings.save_settings()
		sync())


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
	_sound = _toggle_row(page, "Son des annonces", "Un son par famille d'annonce, plus ample quand l'annonce est grave.", func() -> void:
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
