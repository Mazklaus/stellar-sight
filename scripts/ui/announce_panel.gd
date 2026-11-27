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
## Ouvrir la diplomatie sur un empire et un volet ("relation", "deal", "war"). Bêta-test, 2.3 et 2.4.
signal relation_requested(empire_id: int, pane: String)
## Passer en revue les flottes sans ordres (Fanfare de guerre, bêta-test 3.3).
signal idle_fleets_requested
## Un ordre de guerre à envoyer pour le lecteur (bêta-test 2.2 : appliquer son but après une reddition sans conditions).
signal command_requested(cmd: Dictionary)

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
## Boutons de la vue spéciale (tests) : "peace", "idle" pour la guerre, "wait", "revolt", "protector" pour un sujet.
var special_buttons := {}

var _dim: ColorRect
var _root: Control
var _window: PanelContainer
var _box: VBoxContainer
var _band: FamilyBand
var _art: Widgets.ArtSlot
var _side_art: Widgets.ArtSlot
var _special: VBoxContainer
var _title: Label
var _sub: Label
var _lead: Label
var _text: RichTextLabel
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
	# Hors Fanfare, le gabarit commun : l'illustration à gauche sur toute la hauteur, le texte à droite.
	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 16)
	_window.add_child(split)
	_side_art = AnnounceFrame.side_art(AnnounceFrame.ART_WIDTH)
	split.add_child(_side_art)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 8)
	split.add_child(_box)
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
	_text = TipManager.paragraph(WIDTH - 20.0, 16)
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
	view = String(kd.get("view", "")) if fanfare or ["memorial", "subject", "endgame"].has(String(kd.get("view", ""))) else ""
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
	_art.visible = fanfare
	_side_art.set_art("annonces/%s" % kind, fcol, motif)
	_side_art.visible = not fanfare
	for l: Label in [_title, _sub, _lead]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if fanfare else HORIZONTAL_ALIGNMENT_LEFT
	_title.text = Announce.title(state, rec).to_upper() if fanfare else Announce.title(state, rec)
	_title.add_theme_font_size_override("font_size", 40 if fanfare else 28)
	_sub.text = Announce.subtitle(rec)
	_lead.text = "« %s »" % Announce.lead(rec) if Announce.lead(rec) != "" else ""
	_lead.visible = _lead.text != ""
	_lead.custom_minimum_size.x = w - 20.0
	TipManager.set_linked(_text, String(rec["x"]))
	_text.custom_minimum_size.x = w - 20.0
	_text.add_theme_font_size_override("normal_font_size", 18 if fanfare else 16)
	_build_special(state, viewer, rec, w)
	_build_consequences(state, viewer, recs, w)
	_system = Announce.system_of(state, rec)
	locate_button.visible = _system >= 0
	_screen = String(kd.get("screen", ""))
	screen_button.visible = _screen != "" and viewer >= 0
	if _screen != "":
		var info := EmpireBar.screen_info({"transcendence": "victory", "contact": "victory", "kardashev": "victory", "megas": "wonders", "forge": "wonders"}.get(_screen, _screen))
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
	special_buttons.clear()
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
			_war_actions(state, viewer, a, b)
		"subject":
			_subject_view(state, viewer, int(r.get("actor", -1)), w)
		"endgame":
			_endgame_view(state, viewer, int(r.get("actor", -1)), int(r.get("target", -1)))
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


## Fanfare de guerre qui concerne le lecteur : mener aux conditions de paix (bêta-test 2.4) et aux flottes
## sans ordres (3.3).
func _war_actions(state: GameState, viewer: int, a: int, b: int) -> void:
	if viewer < 0 or (viewer != a and viewer != b):
		return
	var enemy := b if viewer == a else a
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 22)
	_special.add_child(row)
	if Combat.at_war(state, viewer, enemy):
		var peace := Widgets.RoundButton.new("plus", "Conditions de paix", 13)
		peace.tooltip_text = "Diplomatie, volet Traiter : ce que vous pouvez exiger ou céder, au prix du score de guerre (%+d aujourd'hui)." % Diplomacy.war_score(state, viewer, enemy)
		peace.pressed.connect(func() -> void: relation_requested.emit(enemy, "deal"))
		row.add_child(peace)
		special_buttons["peace"] = peace
	var idle := Fleets.idle_fleets(state, viewer).filter(func(f: Fleet) -> bool: return Combat.is_armed(f))
	if not idle.is_empty():
		var go := Widgets.RoundButton.new("next", "Flottes sans ordres (%d)" % idle.size(), 13)
		go.tooltip_text = main_idle_text(state, viewer).strip_edges()
		go.pressed.connect(func() -> void: idle_fleets_requested.emit())
		row.add_child(go)
		special_buttons["idle"] = go
	# Bêta-test (3.4) : l'ordre de défense et le rapport de force, là où le joueur en a besoin.
	if Combat.at_war(state, viewer, enemy):
		var how := UiTheme.paragraph("Pour tenir un système : choisissez une flotte armée, puis « Garder ce système ». Flotte choisie, le survol d'un système donne le rapport de force.", 560, 13)
		how.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		how.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
		_special.add_child(how)
		special_buttons["how"] = how


## Fin de guerre par occupation (bêta-test 2.2) : le vainqueur d'une reddition sans conditions applique son
## but ou compose ses termes ; les autres lecteurs retrouvent les conditions de paix et les flottes.
func _endgame_view(state: GameState, viewer: int, a: int, b: int) -> void:
	if viewer < 0 or (viewer != a and viewer != b):
		return
	if kind != "uncond_win" or viewer != a or WarPeace.uncond_of(state, a, b).is_empty():
		_war_actions(state, viewer, a, b)
		return
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 22)
	_special.add_child(row)
	var gid := Wars.goal_of(Wars.war(state, a, b), a)
	var apply := Widgets.RoundButton.new("plus", "Appliquer votre but", 13)
	apply.tooltip_text = "%s\nVos revendications vous reviennent aussi." % String(Wars.goal_def(gid).get("text", Wars.goal_label(gid)))
	apply.disabled = Wars.check_demand(state, a, b) != ""
	apply.pressed.connect(func() -> void: command_requested.emit(SimCommands.war_act(a, "demand", b)))
	row.add_child(apply)
	special_buttons["apply"] = apply
	var compose := Widgets.RoundButton.new("next", "Composer vos termes", 13)
	compose.tooltip_text = "Diplomatie, volet Traiter. Le score compte au maximum ; une clause que votre but ne justifie pas coûte le double."
	compose.pressed.connect(func() -> void: relation_requested.emit(b, "deal"))
	row.add_child(compose)
	special_buttons["compose"] = compose


static func main_idle_text(state: GameState, viewer: int) -> String:
	var parts := PackedStringArray()
	for f: Fleet in Fleets.idle_fleets(state, viewer):
		if Combat.is_armed(f):
			parts.append("%s, à %s" % [f.fleet_name, state.galaxy.get_system(f.system_id).system_name])
	return "\n".join(parts)


## Sujet malgré lui (bêta-test 2.3) : les trois voies qui restent, chacune avec son bouton vers la diplomatie.
func _subject_view(state: GameState, viewer: int, lord: int, w: float) -> void:
	if viewer < 0 or state.get_empire(lord) == null:
		return
	var rival := -1
	var best := -1
	var me := state.get_empire(viewer)
	for x in me.contacts:
		var o := state.get_empire(int(x))
		if o == null or o.eliminated or int(x) == lord or Vassals.check_fealty(state, viewer, int(x)) != "":
			continue
		var pw := Vassals.power(state, int(x))
		if pw > best:
			best = pw
			rival = int(x)
	var lname := state.get_empire(lord).short_name()
	var ways := [
		["wait", "Payer et attendre", "Vos mondes et vos flottes restent à vous. Le tribut part chaque mois et vous suivez %s dans ses guerres. Lui seul peut assouplir les clauses." % lname, "Voir le lien", lord],
		["revolt", "Préparer la révolte", "Des empires peuvent soutenir votre indépendance. Exigez-la quand votre camp pèse assez : s'il refuse, c'est la guerre de libération.", "Exiger l'indépendance", lord],
		["protector", "Chercher un protecteur", "Jurez en secret allégeance à un rival de %s. Le jour où il lui fait la guerre, vous changez de camp." % lname,
				"Voir %s" % state.get_empire(rival).short_name() if rival >= 0 else "Aucun rival connu", rival],
	]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_special.add_child(row)
	for wd in ways:
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", UiTheme.box(Color(0.04, 0.06, 0.09, 0.85), UiTheme.LINE, 4, 1))
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(card)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 6)
		card.add_child(col)
		col.add_child(UiTheme.title(String(wd[1]), 17))
		var txt := UiTheme.paragraph(String(wd[2]), (w - 60.0) / 3.0, 13)
		txt.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
		col.add_child(txt)
		var target := int(wd[4])
		var b := Widgets.RoundButton.new("plus", String(wd[3]), 12)
		b.disabled = target < 0
		b.pressed.connect(func() -> void: relation_requested.emit(target, "deal"))
		col.add_child(b)
		special_buttons[String(wd[0])] = b


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
