class_name TimeDial
extends Control
## Cadran du temps, en bas à droite : l'équivalent temps réel du gros bouton rond de fin de tour
## des 4X au tour par tour. Le centre met en pause ou relance, la date s'affiche dessous, et les
## cinq vitesses sont des crans sur l'arc du haut. Il lit l'horloge et n'émet que des demandes.
## Au tour par tour, le cadran redevient un vrai bouton de fin de tour : le centre termine le
## tour, l'anneau se remplit pendant que les jours du tour défilent, et le numéro du tour s'affiche.

signal pause_toggled
signal speed_requested(index: int)

const SIDE := 150.0
const RING := 62.0
const CORE := 44.0
## Arc des crans de vitesse (radians, 0 = droite, sens horaire à l'écran).
const ARC_FROM := PI * 1.18
const ARC_TO := PI * 1.82

var _clock: Node
var _hover_speed := -1
var _hover_core := false


func _ready() -> void:
	_clock = get_node("/root/GameClock")
	custom_minimum_size = Vector2(SIDE, SIDE)
	size = Vector2(SIDE, SIDE)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_clock.day_passed.connect(func(_d: int) -> void: queue_redraw())
	_clock.speed_changed.connect(func(_s: int) -> void: queue_redraw())
	_clock.pause_changed.connect(func(_p: bool) -> void:
		queue_redraw()
		tooltip_text = _tip())
	_clock.mode_changed.connect(func(_m: int) -> void:
		queue_redraw()
		tooltip_text = _tip())
	tooltip_text = _tip()


## Position d'un cran de vitesse (0 à 4), en coordonnées locales.
func speed_position(i: int) -> Vector2:
	var n: int = _clock.SECONDS_PER_DAY.size()
	var a := lerpf(ARC_FROM, ARC_TO, float(i) / float(n - 1))
	return size * 0.5 + Vector2(cos(a), sin(a)) * RING


func _draw() -> void:
	var c := size * 0.5
	var paused: bool = _clock.paused
	# Anneau extérieur fin, et une portion plus marquée sous les crans.
	draw_circle(c, RING + 10.0, Color(0.03, 0.04, 0.06, 0.55))
	draw_arc(c, RING + 10.0, 0.0, TAU, 72, UiTheme.LINE_STRONG, 1.0, true)
	draw_arc(c, RING, 0.0, TAU, 72, UiTheme.LINE, 1.0, true)
	if _clock.is_turn_based():
		_draw_turn_dial(c)
		return
	for i in _clock.SECONDS_PER_DAY.size():
		var p := speed_position(i)
		var on: bool = i <= _clock.speed_index
		var col := UiTheme.ACCENT if on else Color(1, 1, 1, 0.25)
		if paused and on:
			col = Color(UiTheme.ACCENT, 0.45)
		var r := 5.0 if i == _hover_speed else 4.0
		draw_circle(p, r, col)
		if i == _clock.speed_index:
			draw_arc(p, 8.0, 0.0, TAU, 24, col, 1.0, true)
	# Disque central : pause / lecture.
	var core_col := Color(0.06, 0.08, 0.11, 0.92) if not _hover_core else Color(0.1, 0.13, 0.17, 0.95)
	draw_circle(c, CORE, core_col)
	draw_arc(c, CORE, 0.0, TAU, 64, UiTheme.WARN if paused else Color(UiTheme.ACCENT, 0.8), 1.5, true)
	var g := c + Vector2(0, -10)
	var s := 9.0
	var gcol := UiTheme.WARN if paused else UiTheme.TEXT
	if paused:
		draw_colored_polygon(PackedVector2Array([g + Vector2(-s * 0.7, -s), g + Vector2(s, 0), g + Vector2(-s * 0.7, s)]), gcol)
	else:
		draw_rect(Rect2(g + Vector2(-s * 0.8, -s), Vector2(s * 0.55, s * 2)), gcol)
		draw_rect(Rect2(g + Vector2(s * 0.25, -s), Vector2(s * 0.55, s * 2)), gcol)
	var f := UiTheme.numbers_font()
	var date: String = _clock.date_string()
	var w := f.get_string_size(date, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	draw_string(f, c + Vector2(-w * 0.5, 18), date, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UiTheme.TEXT)
	var label := "EN PAUSE" if paused else "VITESSE %d" % (_clock.speed_index + 1)
	var cf := UiTheme.caps_font()
	var lw := cf.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	draw_string(cf, c + Vector2(-lw * 0.5, 32), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, gcol if paused else UiTheme.TEXT_DIM)


## Variante tour par tour : progression du tour sur l'anneau, gros bouton « fin de tour » au centre.
func _draw_turn_dial(c: Vector2) -> void:
	var resolving: bool = _clock.is_resolving_turn()
	if resolving:
		var p: float = _clock.turn_progress()
		draw_arc(c, RING, -PI * 0.5, -PI * 0.5 + TAU * maxf(p, 0.02), 72, UiTheme.ACCENT, 3.0, true)
	var hot := _hover_core and not resolving
	draw_circle(c, CORE, Color(0.1, 0.13, 0.17, 0.95) if hot else Color(0.06, 0.08, 0.11, 0.92))
	var ring_col := Color(UiTheme.ACCENT, 0.8) if resolving else UiTheme.GOOD
	draw_arc(c, CORE, 0.0, TAU, 64, ring_col, 2.5 if hot else 1.5, true)
	var cf := UiTheme.caps_font()
	var head := "TOUR %d" % _clock.turn()
	var hw := cf.get_string_size(head, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	draw_string(cf, c + Vector2(-hw * 0.5, -18), head, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UiTheme.TEXT)
	# Glyphe : chevron double « suivant », ou sablier stylisé pendant la résolution.
	var g := c + Vector2(0, -2)
	var s := 6.0
	var gcol := UiTheme.TEXT_DIM if resolving else UiTheme.GOOD
	if resolving:
		draw_colored_polygon(PackedVector2Array([g + Vector2(-s, -s), g + Vector2(s, -s), g]), gcol)
		draw_colored_polygon(PackedVector2Array([g, g + Vector2(s, s), g + Vector2(-s, s)]), gcol)
	else:
		for off in [-s * 0.9, s * 0.4]:
			var o := g + Vector2(off, 0)
			draw_colored_polygon(PackedVector2Array([o + Vector2(-s * 0.5, -s), o + Vector2(s * 0.6, 0), o + Vector2(-s * 0.5, s)]), gcol)
	var f := UiTheme.numbers_font()
	var date: String = _clock.date_string()
	var w := f.get_string_size(date, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	draw_string(f, c + Vector2(-w * 0.5, 22), date, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiTheme.TEXT)
	# Légende dans la bande entre le disque et l'anneau, comme sous un bouton.
	var label := "EN COURS…" if resolving else "FIN DE TOUR"
	var lw := cf.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	draw_string(cf, c + Vector2(-lw * 0.5, CORE + 13), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, gcol)


func _process(_delta: float) -> void:
	# L'anneau de progression avance entre deux jours.
	if _clock and _clock.is_turn_based() and _clock.is_resolving_turn():
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion:
		var hs := _speed_at(motion.position)
		var hc := motion.position.distance_to(size * 0.5) <= CORE
		if hs != _hover_speed or hc != _hover_core:
			_hover_speed = hs
			_hover_core = hc
			queue_redraw()
		return
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		var i := -1 if _clock.is_turn_based() else _speed_at(mb.position)
		if i >= 0:
			speed_requested.emit(i)
			accept_event()
		elif mb.position.distance_to(size * 0.5) <= CORE:
			pause_toggled.emit()
			accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and (_hover_speed != -1 or _hover_core):
		_hover_speed = -1
		_hover_core = false
		queue_redraw()


func _speed_at(pos: Vector2) -> int:
	for i in _clock.SECONDS_PER_DAY.size():
		if pos.distance_to(speed_position(i)) <= 11.0:
			return i
	return -1


func _tip() -> String:
	if _clock.is_turn_based():
		return "Centre : fin de tour, %d jours passent  (Espace)" % _clock.turn_days
	return "Centre : %s  (Espace)\nCrans : vitesse 1 à 5  (touches 1 à 5)" % ("reprendre" if _clock.paused else "pause")
