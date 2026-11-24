class_name DiplomacyTable
extends Control
## L'anneau des relations de l'onglet Empires (refonte, C16 ; forme validée par l'utilisateur sur un banc
## d'essai le 24/11/2026). L'empire du joueur est au centre, les autres sur un anneau. Un rayon coloré va
## du joueur à chaque empire rencontré : rouge la guerre, ambre la guerre froide, bleu la paix, cyan
## l'alliance. Le nom, le statut et l'opinion de l'empire sont écrits vers l'extérieur, dans le cadre.
## Les guerres et alliances entre les autres empires longent le bord ; seules celles de l'empire choisi
## sont marquées. Une ligue (Koinon) est une bande de couleur qui enveloppe ses membres : son Stratège
## porte un cercle plein, un associé un cercle en pointillés. Un sujet est plus petit, à côté de son
## suzerain, relié à lui par un trait doré.

signal empire_selected(empire_id: int)

const STATUS_COLORS := {
	"war": Color(1.0, 0.36, 0.3),
	"cold": Color(1.0, 0.7, 0.3),
	"peace": Color(0.4, 0.62, 1.0),
	"alliance": Color(0.38, 0.86, 0.92),
	"none": Color(0.5, 0.52, 0.56),
}
## Couleurs des ligues, dans l'ordre de leurs identifiants.
const LEAGUE_COLORS := [Color(0.78, 0.61, 1.0), Color(1.0, 0.56, 0.75), Color(0.48, 0.88, 0.63), Color(0.93, 0.85, 0.45)]
const GOLD := Color(0.85, 0.64, 0.25)
## Marge laissée aux étiquettes entre l'anneau et le bord du bloc.
const LABEL_ROOM := 105.0
const NAME_MAX := 13

var selected := -1
## Boutons des empires autour de l'anneau, par identifiant (pour les tests).
var buttons := {}
var _state: GameState
var _player := 0
var _ids: Array[int] = []


func _init(side := 440.0) -> void:
	custom_minimum_size = Vector2(side, side)
	mouse_filter = Control.MOUSE_FILTER_PASS


## Ordre des empires sur l'anneau : la ligue du joueur d'abord, puis les autres ligues, puis les empires
## sans ligue ; un sujet vient juste après son suzerain (les sujets du joueur en tête).
static func ring_order(state: GameState, player: int) -> Array[int]:
	var mine := Koinon.league_of(state, player)
	var base: Array[int] = []
	var subs := {}
	for e in state.empires:
		if e.id == player:
			continue
		var lord := Vassals.lord_of(state, e.id)
		if lord >= 0 and lord != player and state.get_empire(lord) != null:
			if not subs.has(lord):
				subs[lord] = []
			(subs[lord] as Array).append(e.id)
		else:
			base.append(e.id)
	var key := func(id: int) -> Array:
		var l := Koinon.league_of(state, id)
		var group := 100000 if l < 0 else (0 if l == mine else l + 1)
		return [0 if Vassals.lord_of(state, id) == player else 1, group, id]
	base.sort_custom(func(a: int, b: int) -> bool: return key.call(a) < key.call(b))
	var out: Array[int] = []
	for id in base:
		out.append(id)
		for s: int in subs.get(id, []):
			out.append(s)
	return out


## Ligues à nommer sous l'anneau : [[nom, couleur], ...] pour celles qui ont un membre connu.
func league_legend() -> Array:
	var out := []
	if _state == null:
		return out
	for lid in Koinon.league_ids(_state):
		out.append([String(Koinon.league(_state, lid).get("name", "Ligue")), league_color(lid)])
	return out


func league_color(lid: int) -> Color:
	var ids := Koinon.league_ids(_state)
	return LEAGUE_COLORS[maxi(0, ids.find(lid)) % LEAGUE_COLORS.size()]


func setup(state: GameState, player: int, selected_id: int) -> void:
	_state = state
	_player = player
	selected = selected_id
	for c in get_children():
		remove_child(c)
		c.queue_free()
	buttons.clear()
	_ids = ring_order(state, player)
	var empty := StyleBoxEmpty.new()
	for id in _ids:
		var e := state.get_empire(id)
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.toggle_mode = true
		b.button_pressed = id == selected
		b.flat = true
		for st in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
			b.add_theme_stylebox_override(st, empty)
		b.tooltip_text = "%s : %s" % [e.display_name(), status_line(id)]
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var target := id
		b.pressed.connect(func() -> void: empire_selected.emit(target))
		add_child(b)
		buttons[id] = b
	_layout()
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout()
		queue_redraw()


func _center() -> Vector2:
	return size * 0.5


func _radius() -> float:
	return maxf(60.0, minf(size.x, size.y) * 0.5 - LABEL_ROOM)


## Angle de la place k sur l'anneau (la première en haut, puis dans le sens des aiguilles).
func _angle(k: int) -> float:
	return -PI * 0.5 + TAU * float(k) / float(maxi(1, _ids.size()))


func _pos(id: int) -> Vector2:
	return _center() + Vector2.from_angle(_angle(_ids.find(id))) * _radius()


func _status(id: int) -> String:
	var e := _state.get_empire(id)
	return "none" if e.eliminated else Diplomacy.status(_state, _player, id)


func _is_sub(id: int) -> bool:
	return Vassals.lord_of(_state, id) >= 0


## Seconde ligne de l'étiquette : statut (ou sujétion) puis opinion de l'empire envers le joueur.
func status_line(id: int) -> String:
	var e := _state.get_empire(id)
	if e.eliminated:
		return "Disparu"
	var st := _status(id)
	if st == "none":
		return Diplomacy.status_label(st)
	var text := Diplomacy.status_text(_state, _player, id)
	var lord := Vassals.lord_of(_state, id)
	if lord == _player:
		text = "Votre sujet"
	elif lord >= 0:
		text = "Sujet, %s" % text.to_lower()
	return "%s  %+d" % [text, Diplomacy.opinion(_state, id, _player)]


func _short(id: int) -> String:
	var n := _state.get_empire(id).short_name()
	return n if n.length() <= NAME_MAX else n.left(NAME_MAX - 1) + "."


## Cadre de l'étiquette d'un empire : [coin, taille, alignement]. Elle part de l'anneau vers l'extérieur
## et reste dans le bloc.
func label_rect(id: int) -> Array:
	var a := _angle(_ids.find(id))
	var cs := cos(a)
	var sn := sin(a)
	var f := get_theme_default_font()
	var w := maxf(f.get_string_size(_short(id), HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x, f.get_string_size(status_line(id), HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x) + 4.0
	var t := _center() + Vector2.from_angle(a) * (_radius() + 26.0)
	var align := HORIZONTAL_ALIGNMENT_CENTER
	var x := t.x - w * 0.5
	if absf(cs) >= 0.3:
		align = HORIZONTAL_ALIGNMENT_LEFT if cs > 0.0 else HORIZONTAL_ALIGNMENT_RIGHT
		x = t.x if cs > 0.0 else t.x - w
	var y := t.y - 16.0 + (0.0 if absf(cs) >= 0.3 else (14.0 if sn > 0.0 else -14.0))
	x = clampf(x, 2.0, maxf(2.0, size.x - w - 2.0))
	y = clampf(y, 2.0, maxf(2.0, size.y - 34.0))
	return [Vector2(x, y), Vector2(w, 32.0), align]


func _layout() -> void:
	if _state == null:
		return
	for id in _ids:
		var b: Button = buttons.get(id)
		if b == null:
			continue
		var lr := label_rect(id)
		var r := Rect2(lr[0], lr[1]).merge(Rect2(_pos(id) - Vector2(16, 16), Vector2(32, 32)))
		b.position = r.position
		b.size = r.size


func _dashed_circle(c: Vector2, r: float, col: Color, w: float) -> void:
	var n := 12
	for k in n:
		draw_arc(c, r, TAU * float(k) / n, TAU * (float(k) + 0.55) / n, 4, col, w, true)


func _curve(a: Vector2, b: Vector2) -> PackedVector2Array:
	var c := _center()
	var r := _radius()
	var mid := (a + b) * 0.5
	var d := mid - c
	var q := mid
	if d.length() < 2.0:
		q = c + Vector2(a.y - c.y, c.x - a.x) * 0.62
	else:
		q = mid + d.normalized() * maxf(0.0, r * 0.62 - d.length())
	var pts := PackedVector2Array()
	for k in 25:
		var t := float(k) / 24.0
		pts.append(a.lerp(q, t).lerp(q.lerp(b, t), t))
	return pts


func _draw() -> void:
	if _state == null:
		return
	var c := _center()
	var r := _radius()
	var n := _ids.size()
	var bg := Color(0.035, 0.055, 0.09)
	draw_arc(c, r, 0, TAU, 96, Color(1, 1, 1, 0.2), 1.0, true)
	# Ligues : une bande qui enveloppe les membres voisins sur l'anneau.
	for lid in Koinon.league_ids(_state):
		var ks: Array[int] = []
		for k in n:
			if Koinon.league_of(_state, _ids[k]) == lid:
				ks.append(k)
		if ks.is_empty():
			continue
		var col := league_color(lid)
		var a0 := _angle(ks[0])
		var a1 := _angle(ks[ks.size() - 1])
		for pass_def: Array in [[44.0, Color(col, 0.3)], [40.0, bg], [40.0, Color(col, 0.1)]]:
			if a1 > a0:
				draw_arc(c, r, a0, a1, 48, pass_def[1], float(pass_def[0]), true)
			for a: float in [a0, a1]:
				draw_circle(c + Vector2.from_angle(a) * r, float(pass_def[0]) * 0.5, pass_def[1])
	# Liens entre les autres empires : marqués pour l'empire choisi, en filigrane sinon.
	for i in n:
		for j in range(i + 1, n):
			var ea := _ids[i]
			var eb := _ids[j]
			if _state.get_empire(ea).eliminated or _state.get_empire(eb).eliminated:
				continue
			var st := Diplomacy.status(_state, ea, eb)
			if st != "war" and st != "alliance":
				continue
			var strong := ea == selected or eb == selected
			var col2 := Color(STATUS_COLORS[st], 0.9 if strong else 0.16)
			var pts := _curve(_pos(ea), _pos(eb))
			if st == "war":
				for k in range(0, pts.size() - 1, 2):
					draw_line(pts[k], pts[k + 1], col2, 1.8 if strong else 1.0, true)
			else:
				draw_polyline(pts, col2, 1.8 if strong else 1.0, true)
	# Sujets d'un autre empire : trait doré jusqu'au suzerain.
	for id in _ids:
		var lord := Vassals.lord_of(_state, id)
		if lord >= 0 and lord != _player and _ids.has(lord):
			draw_line(_pos(id), _pos(lord), GOLD, 2.5, true)
	# Rayons : le statut envers le joueur.
	for id in _ids:
		var st := _status(id)
		if st == "none":
			continue
		var dir := (_pos(id) - c).normalized()
		var on := id == selected
		draw_line(c + dir * 34.0, c + dir * (r - 15.0), Color(STATUS_COLORS[st], 1.0 if on else 0.75), 5.0 if on else 3.0, true)
		if Vassals.lord_of(_state, id) == _player:
			draw_dashed_line(c + dir * 34.0, c + dir * (r - 15.0), GOLD, 1.2, 4.0)
	# Le joueur au centre.
	var me := _state.get_empire(_player)
	var my_league := Koinon.league_of(_state, _player)
	if my_league >= 0:
		draw_arc(c, 36.0, 0, TAU, 48, Color(league_color(my_league), 0.8), 3.0, true)
	draw_circle(c, 30.0, Color(0.04, 0.06, 0.1))
	draw_arc(c, 30.0, 0, TAU, 48, GOLD, 1.5, true)
	if me != null:
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -13), c + Vector2(13, 0), c + Vector2(0, 13), c + Vector2(-13, 0)]), Color(me.color(), 0.9))
	# Les empires et leurs étiquettes.
	var f := get_theme_default_font()
	for id in _ids:
		var e := _state.get_empire(id)
		var p := _pos(id)
		var st := _status(id)
		var grey := st == "none"
		var rad := 10.0 if _is_sub(id) else 14.0
		var lid := Koinon.league_of(_state, id)
		if lid >= 0 and not grey:
			if Koinon.strategos(_state, lid) == id:
				draw_arc(p, 19.0, 0, TAU, 32, league_color(lid), 2.5, true)
			elif Koinon.is_assoc(_state, id):
				_dashed_circle(p, 19.0, league_color(lid), 1.5)
		draw_circle(p, rad, Color(0.08, 0.1, 0.14) if grey else Color(e.color(), 0.9))
		if grey and not e.eliminated:
			_dashed_circle(p, rad, Color(0.4, 0.42, 0.46), 1.2)
		else:
			draw_arc(p, rad, 0, TAU, 32, Color.WHITE if id == selected else (Color(0.33, 0.36, 0.4) if grey else e.color().lightened(0.4)), 2.5 if id == selected else 1.2, true)
		var lr := label_rect(id)
		var at: Vector2 = lr[0]
		var w: float = (lr[1] as Vector2).x
		draw_string(f, at + Vector2(0, 13), _short(id), lr[2], w, 13, Color(0.48, 0.5, 0.55) if grey else (Color.WHITE if id == selected else UiTheme.TEXT))
		draw_string(f, at + Vector2(0, 28), status_line(id), lr[2], w, 12, Color(0.43, 0.45, 0.5) if grey else STATUS_COLORS[st])
