class_name AnnouncePanel
extends CanvasLayer
## Fenêtre commune des annonces (étude de la fenêtre d'événement, prop. 13 à 18, 22, 24, 27) : bandeau
## de famille, illustration, titre, date, phrase du chroniqueur, texte, conséquences, puis « Montrer
## l'emplacement », « Ouvrir l'écran lié », « Réduire » (Échap) et « Compris ». Flèches pour passer
## d'une pastille de la colonne à l'autre (« 2 sur 5 »), interrupteur « Ouvrir d'elle-même ».
## En Fanfare (prop. 15 à 17), la même fenêtre passe en plein cadre, avec deux vues spéciales :
## mémorial (portrait en médaillon, dates, épitaphe) et guerre (deux blasons, motif, but, forces).
## AnnounceCenter l'ouvre ; elle ne décide de rien.

signal closed
signal acknowledged
signal locate_requested(system_id: int)
signal screen_requested(screen: String)
signal nav_requested(delta: int)

const WIDTH := 620.0
const FANFARE_WIDTH := 900.0

## Ce qui est affiché (tests) : type, annonce, Fanfare ou non, vue spéciale ("", "war", "memorial").
var kind := ""
var aid := -1
var fanfare := false
var view := ""
var locate_button: Widgets.RoundButton
var screen_button: Widgets.RoundButton
var later_button: Widgets.RoundButton
var ok_button: Widgets.RoundButton
var auto_check: CheckBox
var prev_button: Widgets.IconButton
var next_button: Widgets.IconButton
var nav_label: Label

var _dim: ColorRect
var _root: Control
var _window: PanelContainer
var _box: VBoxContainer
var _band: FamilyBand
var _art: Widgets.ArtSlot
var _special: VBoxContainer
var _title: Label
var _sub: Label
var _lead: Label
var _text: Label
var _conseq: VBoxContainer
var _system := -1
var _screen := ""
var _tween: Tween


func _ready() -> void:
	layer = 7
	visible = false
	_dim = ColorRect.new()
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_dim)
	_root = CenterContainer.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	_window = PanelContainer.new()
	_window.theme_type_variation = &"WindowPanel"
	_root.add_child(_window)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 8)
	_window.add_child(_box)
	_band = FamilyBand.new()
	_box.add_child(_band)
	_art = Widgets.ArtSlot.new("", Vector2(WIDTH, 150), UiTheme.ACCENT, "star")
	_box.add_child(_art)
	_special = VBoxContainer.new()
	_special.alignment = BoxContainer.ALIGNMENT_CENTER
	_special.add_theme_constant_override("separation", 6)
	_box.add_child(_special)
	_title = UiTheme.title("", 28)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box.add_child(_title)
	_sub = UiTheme.dim("", 13)
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(_sub)
	_lead = UiTheme.paragraph("", WIDTH - 20.0, 14)
	_lead.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lead.add_theme_color_override("font_color", Color(UiTheme.TEXT_DIM, 0.95))
	_box.add_child(_lead)
	_text = UiTheme.paragraph("", WIDTH - 20.0, 16)
	_box.add_child(_text)
	_conseq = VBoxContainer.new()
	_conseq.add_theme_constant_override("separation", 3)
	_box.add_child(_conseq)

	var nav := HBoxContainer.new()
	nav.alignment = BoxContainer.ALIGNMENT_CENTER
	nav.add_theme_constant_override("separation", 12)
	_box.add_child(nav)
	auto_check = CheckBox.new()
	auto_check.text = "Ouvrir d'elle-même"
	auto_check.focus_mode = Control.FOCUS_NONE
	auto_check.tooltip_text = "Décoché, ce type d'annonce reste dans la colonne de droite sans s'ouvrir (réglable dans Options, onglet Annonces)."
	auto_check.toggled.connect(func(on: bool) -> void:
		if kind != "":
			AnnounceSettings.set_auto_open(kind, on))
	nav.add_child(auto_check)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(40, 0)
	nav.add_child(spacer)
	prev_button = Widgets.IconButton.new("prev", 26)
	prev_button.tooltip_text = "Annonce plus récente"
	prev_button.pressed.connect(func() -> void: nav_requested.emit(-1))
	nav.add_child(prev_button)
	nav_label = UiTheme.dim("", 13)
	nav.add_child(nav_label)
	next_button = Widgets.IconButton.new("next", 26)
	next_button.tooltip_text = "Annonce plus ancienne"
	next_button.pressed.connect(func() -> void: nav_requested.emit(1))
	nav.add_child(next_button)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 22)
	_box.add_child(buttons)
	locate_button = Widgets.RoundButton.new("next", "Emplacement", 13)
	locate_button.tooltip_text = "Montrer l'emplacement sur la carte"
	locate_button.pressed.connect(func() -> void:
		if _system >= 0:
			locate_requested.emit(_system))
	buttons.add_child(locate_button)
	screen_button = Widgets.RoundButton.new("plus", "Écran lié", 13)
	screen_button.pressed.connect(func() -> void:
		if _screen != "":
			screen_requested.emit(_screen))
	buttons.add_child(screen_button)
	later_button = Widgets.RoundButton.new("back", "Réduire", 13)
	later_button.tooltip_text = "L'annonce reste dans la colonne de droite (Échap)."
	later_button.pressed.connect(func() -> void: closed.emit())
	buttons.add_child(later_button)
	ok_button = Widgets.RoundButton.new("check", "Compris", 13)
	ok_button.tooltip_text = "L'annonce quitte la colonne (elle reste dans les Chroniques, touche J)."
	ok_button.pressed.connect(func() -> void: acknowledged.emit())
	buttons.add_child(ok_button)


## recs : annonces de la pastille, la plus récente d'abord. g : gravité finale. nav : position, total.
func open(state: GameState, viewer: int, recs: Array[Dictionary], g: int, nav_at: int, nav_total: int) -> void:
	var rec := recs[0]
	kind = String(rec["k"])
	aid = int(rec["id"])
	var kd := Announce.kind_def(kind)
	fanfare = g >= Announce.FANFARE
	view = String(kd.get("view", "")) if fanfare or String(kd.get("view", "")) == "memorial" else ""
	var fam := Announce.family_of(kind)
	var fcol := Announce.family_color(fam)
	var need := Announce.need(rec, viewer)
	var w := FANFARE_WIDTH if fanfare else WIDTH
	_box.custom_minimum_size = Vector2(w, 0)
	_dim.color = Color(0.0, 0.01, 0.03, 0.88 if fanfare else 0.5)
	_band.setup(fam, Announce.need_color(need), Announce.gravity_label(g).to_upper() if fanfare else Announce.need_label(need))
	_art.custom_minimum_size = Vector2(w, 280 if fanfare else 150)
	var motif: String = {"guerre": "faction", "diplomatie": "faction", "colonies": "planet", "au_dela": "star"}.get(fam, "star")
	_art.set_art("annonces/%s" % kind, fcol, motif)
	_title.text = Announce.title(state, rec).to_upper() if fanfare else Announce.title(state, rec)
	_title.add_theme_font_size_override("font_size", 40 if fanfare else 28)
	_sub.text = Announce.subtitle(rec)
	_lead.text = "« %s »" % Announce.lead(rec) if Announce.lead(rec) != "" else ""
	_lead.visible = _lead.text != ""
	_lead.custom_minimum_size.x = w - 20.0
	_text.text = String(rec["x"])
	_text.custom_minimum_size.x = w - 20.0
	_text.add_theme_font_size_override("font_size", 18 if fanfare else 16)
	_build_special(state, viewer, rec, w)
	_build_consequences(state, viewer, recs, w)
	_system = Announce.system_of(state, rec)
	locate_button.visible = _system >= 0
	_screen = String(kd.get("screen", ""))
	screen_button.visible = _screen != "" and viewer >= 0
	if _screen != "":
		var info := EmpireBar.screen_info({"transcendence": "victory", "contact": "victory", "megas": "wonders", "forge": "wonders"}.get(_screen, _screen))
		screen_button.tooltip_text = "Ouvrir l'écran %s" % String(info.get("label", _screen))
	auto_check.set_pressed_no_signal(AnnounceSettings.auto_open(kind))
	nav_label.text = "%d sur %d" % [nav_at, nav_total]
	prev_button.disabled = nav_at <= 1
	next_button.disabled = nav_at >= nav_total
	prev_button.visible = nav_total > 1
	next_button.visible = nav_total > 1
	nav_label.visible = nav_total > 1
	visible = true
	_fade_in()


## Fondu d'ouverture (réglage « Animations », prop. 27).
func _fade_in() -> void:
	if _tween:
		_tween.kill()
	var secs := AnnounceSettings.anim_seconds()
	if secs <= 0.0:
		_root.modulate.a = 1.0
		_dim.modulate.a = 1.0
		return
	_root.modulate.a = 0.0
	_dim.modulate.a = 0.0
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(_root, "modulate:a", 1.0, secs)
	_tween.tween_property(_dim, "modulate:a", 1.0, secs * (2.0 if fanfare else 1.0))


func _build_special(state: GameState, viewer: int, rec: Dictionary, w: float) -> void:
	for c in _special.get_children():
		c.queue_free()
	_special.visible = view != ""
	var r: Dictionary = rec.get("r", {})
	match view:
		"war":
			var row := HBoxContainer.new()
			row.alignment = BoxContainer.ALIGNMENT_CENTER
			row.add_theme_constant_override("separation", 26)
			_special.add_child(row)
			var a := int(r.get("actor", -1))
			var b := int(r.get("target", -1))
			row.add_child(_side(state, a))
			row.add_child(UiTheme.title("CONTRE", 22, UiTheme.TEXT_DIM))
			row.add_child(_side(state, b))
		"memorial":
			var row := HBoxContainer.new()
			row.alignment = BoxContainer.ALIGNMENT_CENTER
			row.add_theme_constant_override("separation", 18)
			_special.add_child(row)
			var owner := state.get_empire(int(r.get("target", -1)))
			var col := owner.color() if owner else Color(0.6, 0.6, 0.6)
			var pid := String(r.get("portrait", ""))
			var medal := Widgets.ArtSlot.new(pid, Vector2(120, 140) if fanfare else Vector2(90, 105), col, "faction")
			if r.has("hero"):
				medal.set_hero({"seed": int(r.get("seed", 0)), "cls": String(r.get("cls", "")), "lvl": int(r.get("lvl", 1)), "age": 0, "faction": col})
			row.add_child(medal)
			var col_box := VBoxContainer.new()
			col_box.alignment = BoxContainer.ALIGNMENT_CENTER
			row.add_child(col_box)
			col_box.add_child(UiTheme.title(String(r.get("name", "")), 26))
			var born := int(r.get("born", rec["t"]))
			col_box.add_child(UiTheme.dim("%s  -  %s" % [GameCalendar.date_string(born), GameCalendar.date_string(int(rec["t"]))], 14))
			if r.has("lvl"):
				col_box.add_child(UiTheme.dim("Niveau %d" % int(r["lvl"]), 13))
			var why := String(r.get("why", ""))
			if why != "":
				var ep := UiTheme.paragraph("Ici repose qui %s." % why.trim_suffix("."), w * 0.55, 14)
				ep.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
				col_box.add_child(ep)


func _side(state: GameState, eid: int) -> Control:
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.custom_minimum_size = Vector2(220, 0)
	var e := state.get_empire(eid)
	var em := Widgets.Emblem.new(64)
	em.color = e.color() if e else Color(0.5, 0.5, 0.5)
	var holder := CenterContainer.new()
	holder.add_child(em)
	box.add_child(holder)
	var n := UiTheme.title(e.display_name() if e else "?", 20)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(n)
	var fleets := 0
	var ships := 0
	for f: Fleet in state.fleets.values():
		if f.owner == eid:
			fleets += 1
			ships += f.ships.size()
	var l := UiTheme.dim("%d flotte%s, %d vaisseau%s" % [fleets, "s" if fleets > 1 else "", ships, "x" if ships > 1 else ""], 13)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(l)
	return box


## Conséquences et contexte : empires concernés, motif et but de la guerre, autres nouvelles du même mois.
func _build_consequences(state: GameState, viewer: int, recs: Array[Dictionary], w: float) -> void:
	for c in _conseq.get_children():
		c.queue_free()
	var rec := recs[0]
	var lines := PackedStringArray()
	var names := PackedStringArray()
	for x in Announce.involved(rec):
		var e := state.get_empire(x)
		if e:
			names.append("vous" if x == viewer else e.display_name())
	if not names.is_empty():
		lines.append("Concerne : %s" % ", ".join(names))
	var r: Dictionary = rec.get("r", {})
	if view == "war" or String(Announce.kind_def(kind).get("view", "")) == "war":
		var war := Wars.war(state, int(r.get("actor", -1)), int(r.get("target", -1)))
		if not war.is_empty():
			var cb := String(Wars.casus_def(String(war.get("cb", ""))).get("label", ""))
			if cb != "":
				lines.append("Motif : %s" % cb)
			var goal := String(Wars.goal_def(String(war.get("ga", ""))).get("label", ""))
			if goal != "":
				lines.append("But de l'agresseur : %s" % goal)
	if Announce.always(kind) and Announce.involved(rec).has(viewer):
		lines.append("Ce type d'annonce vous concerne toujours : il ne descend jamais sous l'avis.")
	for line in lines:
		var l := UiTheme.paragraph(line, w - 20.0, 13)
		l.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
		_conseq.add_child(l)
	if recs.size() > 1:
		_conseq.add_child(Widgets.NotchHeader.new("Du même genre ce mois-ci (%d)" % (recs.size() - 1), 12))
		for i in range(1, mini(recs.size(), 5)):
			var o := recs[i]
			var l := UiTheme.paragraph("%s  %s" % [GameCalendar.date_string(int(o["t"])), String(o["x"])], w - 20.0, 13)
			l.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
			_conseq.add_child(l)
		if recs.size() > 5:
			_conseq.add_child(UiTheme.dim("… et %d autres (Chroniques, touche J)." % (recs.size() - 5), 12))
	_conseq.visible = _conseq.get_child_count() > 0


func close() -> void:
	visible = false
	kind = ""
	aid = -1
	view = ""


func is_open() -> bool:
	return visible


## Bandeau de famille : filet de la couleur de la famille, glyphe, nom de la famille et besoin.
class FamilyBand:
	extends Control
	var family := ""
	var accent := UiTheme.ACCENT
	var tag := ""

	func _init() -> void:
		custom_minimum_size = Vector2(0, 26)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func setup(fam: String, need_col: Color, t: String) -> void:
		family = fam
		accent = need_col
		tag = t
		queue_redraw()

	func _draw() -> void:
		var col := Announce.family_color(family)
		draw_rect(Rect2(0, size.y - 3, size.x, 3), col)
		AnnounceColumn.draw_glyph(self, String(Announce.family_def(family).get("glyph", "")), Vector2(11, 11), 9.0, col)
		var f := UiTheme.font(500, 2)
		draw_string(f, Vector2(28, 16), String(Announce.family_def(family).get("label", "")).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)
		var tw := f.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		draw_string(f, Vector2(size.x - tw - 4, 16), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, accent)
