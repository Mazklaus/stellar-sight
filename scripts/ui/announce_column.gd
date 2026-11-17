class_name AnnounceColumn
extends VBoxContainer
## Colonne des annonces, à droite au-dessus du cadran (étude de la fenêtre d'événement, prop. 19 et 20) :
## une pastille ronde par annonce en attente, la plus récente en bas, près du cadran. Couleur du besoin
## (or : décision, rouge : menace, vert : bonne nouvelle, bleu : information), glyphe de la famille,
## pastille de nombre pour une nouvelle regroupée. Clic : ouvrir ; clic droit : écarter.
## Les décisions des boîtes du joueur (événements, hauts faits) s'y rangent aussi, en or, tout en bas.

signal open_requested(index: int)
signal dismiss_requested(index: int)
signal decision_requested(kind: String, id: int)

const SIDE := 38.0
const GAP := 6.0

var center: AnnounceCenter
## Pastilles affichées (tests) : {"index"} pour une annonce, {"kind", "id"} pour une décision.
var shown: Array[Dictionary] = []


func _init() -> void:
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	# Au-dessus du bouton de menu, lui-même au-dessus du cadran (Hud.MARGIN = 10, TimeDial.SIDE = 150).
	offset_right = -10.0 + 1.0
	offset_left = offset_right - SIDE
	offset_bottom = -TimeDial.SIDE - 10.0 - 46.0
	offset_top = offset_bottom
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	alignment = BoxContainer.ALIGNMENT_END
	add_theme_constant_override("separation", int(GAP))
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func rebuild() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	shown.clear()
	if center == null or center.state == null:
		return
	var room := 9
	if is_inside_tree():
		room = maxi(2, int((get_viewport().get_visible_rect().size.y - TimeDial.SIDE - 330.0) / (SIDE + GAP)))
	var decisions: Array[Dictionary] = center.decisions()
	var n_items := mini(center.items.size(), maxi(0, room - decisions.size()))
	for i in range(center.items.size() - n_items, center.items.size()):
		var it: Dictionary = center.items[i]
		var rec := Announce.find(center.state, int(it["aids"].back()))
		if rec.is_empty():
			continue
		var p := Pip.new()
		p.glyph = String(Announce.family_def(Announce.family_of(String(it["k"]))).get("glyph", ""))
		p.fill = Announce.need_color(Announce.need(rec, center.viewer))
		p.family = Announce.family_color(Announce.family_of(String(it["k"])))
		p.count = (it["aids"] as Array).size()
		p.read = bool(it["read"])
		p.fanfare = int(it["g"]) >= Announce.FANFARE
		p.tooltip_text = "%s\n%s  %s\nClic : ouvrir    Clic droit : écarter" % [Announce.title(center.state, rec), GameCalendar.date_string(int(rec["t"])), String(rec["x"])]
		var idx := i
		p.clicked.connect(func(right: bool) -> void:
			if right:
				dismiss_requested.emit(idx)
			else:
				open_requested.emit(idx))
		add_child(p)
		shown.append({"index": i})
	for d in decisions.slice(0, mini(decisions.size(), room)):
		var p := Pip.new()
		p.glyph = "decision"
		p.fill = Announce.need_color("decision")
		p.family = p.fill
		p.tooltip_text = "Décision en attente\n%s\nClic : ouvrir" % String(d["title"])
		var kind := String(d["kind"])
		var id := int(d["id"])
		p.clicked.connect(func(right: bool) -> void:
			if not right:
				decision_requested.emit(kind, id))
		add_child(p)
		shown.append({"kind": kind, "id": id})


## Pastille ronde de la colonne.
class Pip:
	extends Control
	signal clicked(right: bool)
	var glyph := ""
	var fill := UiTheme.ACCENT
	var family := UiTheme.ACCENT
	var count := 1
	var read := false
	var fanfare := false

	func _init() -> void:
		custom_minimum_size = Vector2(AnnounceColumn.SIDE, AnnounceColumn.SIDE)
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(queue_redraw)
		mouse_exited.connect(queue_redraw)

	func _gui_input(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb and mb.pressed and (mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT):
			accept_event()
			clicked.emit(mb.button_index == MOUSE_BUTTON_RIGHT)

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 2.0
		var hot := get_global_rect().has_point(get_global_mouse_position())
		draw_circle(c, r, Color(0.03, 0.04, 0.06, 0.92))
		draw_circle(c, r, Color(fill, 0.22 if not read else 0.1))
		draw_arc(c, r, 0.0, TAU, 40, Color(fill, 1.0 if hot else (0.55 if read else 0.9)), 2.0 if not fanfare else 3.0, true)
		if fanfare:
			draw_arc(c, r + 1.5, 0.0, TAU, 40, Color(UiTheme.WARN, 0.6), 1.0, true)
		AnnounceColumn.draw_glyph(self, glyph, c, r * 0.52, Color(UiTheme.TEXT, 0.6 if read else 0.95))
		if count > 1:
			var bc := c + Vector2(r * 0.72, -r * 0.72)
			draw_circle(bc, 8.0, fill.darkened(0.2))
			var f := UiTheme.font(600)
			var t := str(count) if count < 10 else "9+"
			var tw := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
			draw_string(f, bc + Vector2(-tw * 0.5, 4.0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.02, 0.02, 0.03))


## Glyphes des familles (data/announcements.json « glyph »), tracés au trait.
static func draw_glyph(ci: CanvasItem, glyph: String, c: Vector2, s: float, col: Color) -> void:
	var w := 1.6
	match glyph:
		"swords":
			ci.draw_line(c + Vector2(-s, s), c + Vector2(s, -s), col, w, true)
			ci.draw_line(c + Vector2(s, s), c + Vector2(-s, -s), col, w, true)
			ci.draw_line(c + Vector2(-s, s * 0.4), c + Vector2(-s * 0.4, s), col, w, true)
			ci.draw_line(c + Vector2(s, s * 0.4), c + Vector2(s * 0.4, s), col, w, true)
		"rings":
			ci.draw_arc(c + Vector2(-s * 0.4, 0), s * 0.6, 0.0, TAU, 20, col, w, true)
			ci.draw_arc(c + Vector2(s * 0.4, 0), s * 0.6, 0.0, TAU, 20, col, w, true)
		"warning":
			ci.draw_polyline(PackedVector2Array([c + Vector2(0, -s), c + Vector2(s, s * 0.8), c + Vector2(-s, s * 0.8), c + Vector2(0, -s)]), col, w, true)
			ci.draw_line(c + Vector2(0, -s * 0.35), c + Vector2(0, s * 0.2), col, w, true)
			ci.draw_circle(c + Vector2(0, s * 0.5), 1.4, col)
		"crown":
			ci.draw_polyline(PackedVector2Array([c + Vector2(-s, s * 0.6), c + Vector2(-s, -s * 0.5), c + Vector2(-s * 0.5, s * 0.05), c + Vector2(0, -s * 0.8), c + Vector2(s * 0.5, s * 0.05), c + Vector2(s, -s * 0.5), c + Vector2(s, s * 0.6), c + Vector2(-s, s * 0.6)]), col, w, true)
		"flame":
			ci.draw_polyline(PackedVector2Array([c + Vector2(0, s), c + Vector2(-s * 0.7, s * 0.2), c + Vector2(-s * 0.2, -s * 0.3), c + Vector2(0, -s), c + Vector2(s * 0.3, -s * 0.2), c + Vector2(s * 0.7, s * 0.2), c + Vector2(0, s)]), col, w, true)
		"gear":
			ci.draw_arc(c, s * 0.55, 0.0, TAU, 20, col, w, true)
			for i in 6:
				var a := TAU * i / 6.0
				ci.draw_line(c + Vector2(cos(a), sin(a)) * s * 0.55, c + Vector2(cos(a), sin(a)) * s, col, w, true)
		"spiral":
			var pts := PackedVector2Array()
			for i in 24:
				var t := float(i) / 23.0
				var a := t * TAU * 1.6
				pts.append(c + Vector2(cos(a), sin(a)) * s * (0.15 + 0.85 * t))
			ci.draw_polyline(pts, col, w, true)
		"coin":
			ci.draw_arc(c, s * 0.85, 0.0, TAU, 24, col, w, true)
			ci.draw_line(c + Vector2(0, -s * 0.5), c + Vector2(0, s * 0.5), col, w, true)
		"eye":
			ci.draw_arc(c + Vector2(0, s * 0.7), s * 1.2, -PI * 0.78, -PI * 0.22, 16, col, w, true)
			ci.draw_arc(c + Vector2(0, -s * 0.7), s * 1.2, PI * 0.22, PI * 0.78, 16, col, w, true)
			ci.draw_circle(c, s * 0.3, col)
		"planet":
			ci.draw_arc(c, s * 0.6, 0.0, TAU, 24, col, w, true)
			ci.draw_line(c + Vector2(-s, s * 0.3), c + Vector2(s, -s * 0.3), col, w, true)
		"decision":
			ci.draw_line(c + Vector2(0, -s), c + Vector2(0, s * 0.35), col, w + 0.6, true)
			ci.draw_circle(c + Vector2(0, s * 0.8), 1.8, col)
		_:
			ci.draw_circle(c, s * 0.35, col)
