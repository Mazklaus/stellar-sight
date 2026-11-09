class_name DiplomacyTable
extends Control
## La « table » de l'écran Diplomatie, inspirée de l'écran des statuts diplomatiques d'Endless Space 2
## (capture étudiée : galerie hudsandguis.com, « Endless Space 2 - Diplomacy ») : l'empire du joueur au
## centre, les autres empires tout autour d'un grand anneau, et entre eux un secteur coloré par le statut
## (rouge la guerre, ambre la guerre froide, bleu la paix, cyan l'alliance, gris sans contact).
## Un clic sur un empire le sélectionne. Les liens entre les autres empires sont tracés en fins filets
## (guerre en rouge, alliance en cyan) pour lire la galaxie d'un coup d'œil.

signal empire_selected(empire_id: int)

const STATUS_COLORS := {
	"war": Color(1.0, 0.36, 0.3),
	"cold": Color(1.0, 0.7, 0.3),
	"peace": Color(0.4, 0.62, 1.0),
	"alliance": Color(0.38, 0.86, 0.92),
	"none": Color(0.5, 0.52, 0.56),
}

var selected := -1
## Boutons des empires autour de l'anneau, par identifiant (pour les tests).
var buttons := {}
var _state: GameState
var _player := 0
var _ids: Array[int] = []


func _init(side := 440.0) -> void:
	custom_minimum_size = Vector2(side, side)
	mouse_filter = Control.MOUSE_FILTER_PASS


func setup(state: GameState, player: int, selected_id: int) -> void:
	_state = state
	_player = player
	selected = selected_id
	for c in get_children():
		remove_child(c)
		c.queue_free()
	buttons.clear()
	_ids.clear()
	for e in state.empires:
		if e.id != player:
			_ids.append(e.id)
	for id in _ids:
		var e := state.get_empire(id)
		var st := Diplomacy.status(state, player, id)
		if e.eliminated:
			st = "none"
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.toggle_mode = true
		b.button_pressed = id == selected
		b.text = "%s\n%s" % [e.short_name().to_upper(), "Disparu" if e.eliminated else Diplomacy.status_label(st)]
		b.custom_minimum_size = Vector2(130, 46)
		b.add_theme_font_size_override("font_size", 13)
		b.add_theme_color_override("font_color", e.color().lerp(Color.WHITE, 0.25))
		var nb := UiTheme.box(Color(0.02, 0.03, 0.05, 0.85), Color(STATUS_COLORS[st], 0.55), 6, 1)
		b.add_theme_stylebox_override("normal", nb)
		b.add_theme_stylebox_override("hover", UiTheme.box(Color(0.06, 0.08, 0.11, 0.92), STATUS_COLORS[st], 6, 1))
		var on := UiTheme.box(Color(STATUS_COLORS[st], 0.2), STATUS_COLORS[st], 6, 2)
		b.add_theme_stylebox_override("pressed", on)
		b.add_theme_stylebox_override("hover_pressed", on)
		var target := id
		b.pressed.connect(func() -> void: empire_selected.emit(target))
		add_child(b)
		buttons[id] = b
	_layout()
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout()


func _center() -> Vector2:
	return size * 0.5


func _radius() -> float:
	return minf(size.x, size.y) * 0.5 - 30.0


## Angle d'un empire autour de l'anneau (le premier en haut, puis dans le sens des aiguilles).
func _angle(i: int) -> float:
	return -PI * 0.5 + TAU * float(i) / float(maxi(1, _ids.size()))


func _layout() -> void:
	for i in _ids.size():
		var b: Button = buttons.get(_ids[i])
		if b == null:
			continue
		var p := _center() + Vector2.from_angle(_angle(i)) * (_radius() - 6.0)
		b.position = p - b.custom_minimum_size * 0.5
		b.size = b.custom_minimum_size


func _draw() -> void:
	if _state == null:
		return
	var c := _center()
	var r := _radius()
	var n := maxi(1, _ids.size())
	var half := PI / float(n)
	# Secteurs : un par empire, de la couleur du statut.
	for i in _ids.size():
		var id := _ids[i]
		var e := _state.get_empire(id)
		var st := "none" if e.eliminated else Diplomacy.status(_state, _player, id)
		var col: Color = STATUS_COLORS[st]
		var a0 := _angle(i) - half + 0.03
		var a1 := _angle(i) + half - 0.03
		var pts := PackedVector2Array()
		var steps := 24
		for k in steps + 1:
			pts.append(c + Vector2.from_angle(lerpf(a0, a1, float(k) / steps)) * (r - 34.0))
		for k in range(steps, -1, -1):
			pts.append(c + Vector2.from_angle(lerpf(a0, a1, float(k) / steps)) * (r * 0.3))
		var alpha := 0.32 if id == selected else 0.16
		draw_colored_polygon(pts, Color(col, alpha))
		draw_line(c + Vector2.from_angle(a0) * r * 0.3, c + Vector2.from_angle(a0) * (r - 34.0), Color(1, 1, 1, 0.08), 1.0)
	# Anneaux.
	draw_arc(c, r - 34.0, 0, TAU, 96, Color(1, 1, 1, 0.16), 1.0, true)
	draw_arc(c, r * 0.3, 0, TAU, 64, Color(1, 1, 1, 0.22), 1.0, true)
	draw_arc(c, r + 8.0, 0, TAU, 96, Color(UiTheme.ACCENT, 0.12), 1.0, true)
	# Liens entre les autres empires (guerres, alliances), en cordes fines.
	for i in _ids.size():
		for j in range(i + 1, _ids.size()):
			var a := _ids[i]
			var b := _ids[j]
			if _state.get_empire(a).eliminated or _state.get_empire(b).eliminated:
				continue
			var st := Diplomacy.status(_state, a, b)
			if st != "war" and st != "alliance":
				continue
			var pa := c + Vector2.from_angle(_angle(i)) * (r - 40.0)
			var pb := c + Vector2.from_angle(_angle(j)) * (r - 40.0)
			if st == "war":
				draw_dashed_line(pa, pb, Color(STATUS_COLORS[st], 0.55), 1.5, 6.0)
			else:
				draw_line(pa, pb, Color(STATUS_COLORS[st], 0.6), 1.5, true)
	# Le joueur au centre.
	var me := _state.get_empire(_player)
	draw_circle(c, r * 0.3 - 6.0, Color(0.02, 0.03, 0.05, 0.9))
	draw_circle(c, r * 0.12, Color(me.color(), 0.85))
	draw_arc(c, r * 0.12 + 5.0, 0, TAU, 48, Color(me.color(), 0.5), 1.5, true)
	var f := UiTheme.caps_font()
	var label := me.short_name().to_upper()
	var w := f.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, 15).x
	draw_string(f, c + Vector2(-w * 0.5, r * 0.12 + 26.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UiTheme.TEXT)
