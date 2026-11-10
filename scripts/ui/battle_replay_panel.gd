class_name BattleReplayPanel
extends Control
## Vue de bataille facultative : rejoue le journal d'un rapport de bataille (state.battle_reports[i]["log"]),
## dans l'esprit des batailles regardées d'Endless Space 2, en 2D stylisée.
## Elle ne fait que relire : la bataille est déjà jouée par la simulation, rien ici ne la touche,
## et elle ne met jamais la partie en pause (en multijoueur, chacun regarde quand il veut).
##
## Chaque camp est rangé en trois colonnes : écran devant, ligne, arrière derrière. Un jour de bataille
## dure DAY_SECONDS à vitesse 1 : les tirs du jour partent en décalé (missiles en courbe, rayons,
## traçantes des canons, torpilles, obus d'artillerie, essaims de chasseurs), puis les vaisseaux
## détruits s'éteignent.

signal closed

const DAY_SECONDS := 2.2
const SPEEDS := [1.0, 2.0, 4.0]
const SIZE_PX := {"small": 11.0, "medium": 15.0, "large": 21.0, "titan": 32.0}
const STEP := 54.0        # écart entre deux vaisseaux d'une colonne
const COL_GAP := 190.0    # écart entre écran, ligne et arrière
const WEAPON_COLORS := {
	"kinetic": Color(1.0, 0.86, 0.45), "beam": Color(0.45, 0.92, 1.0), "missile": Color(1.0, 0.6, 0.3),
	"torpedo": Color(0.95, 0.45, 0.85), "artillery": Color(1.0, 0.95, 0.8), "fighters": Color(0.6, 1.0, 0.6),
	"bombers": Color(0.85, 1.0, 0.4), "stellar_lance": Color(1.0, 0.98, 0.7),
	"martyr": Color(1.0, 0.35, 0.25),
}

var report: Dictionary = {}
var playing := true
var t := 0.0
var _speed_i := 0
var _state: GameState
var _viewer := 0
var _left := {}          # empires du camp de gauche
var _pos: Array = []      # position de chaque unité
var _col_labels: Array = []  # [position, libellé du rang] sous chaque colonne
var _max_hp: Array = []
var _dmg_until: Array = []  # _dmg_until[d][u] : dégâts cumulés avant le jour d (indice 0 = avant le premier)
var _dead_day: Array = []   # jour (indice du journal) où l'unité est détruite, -1 sinon
var _play_btn: Button
var _speed_btn: Button


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bar := HBoxContainer.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	bar.offset_top = -72.0
	bar.offset_bottom = -28.0
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar.add_theme_constant_override("separation", 8)
	add_child(bar)
	_button(bar, "◀ JOUR", "Revenir au début du jour précédent", func() -> void: _seek_day(-1))
	_play_btn = _button(bar, "PAUSE", "Lecture ou pause  (Espace)", toggle_play)
	_speed_btn = _button(bar, "VITESSE ×1", "Changer la vitesse de lecture", _cycle_speed)
	_button(bar, "JOUR ▶", "Passer au jour suivant", func() -> void: _seek_day(1))
	_button(bar, "PASSER", "Fermer la vue et revenir au rapport  (Échap)", hide_replay)


func _button(parent: Control, text: String, tip: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(120, 38)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


static func has_log(r: Dictionary) -> bool:
	return not r.get("log", []).is_empty() and not r.get("units", []).is_empty()


func show_replay(state: GameState, viewer: int, r: Dictionary) -> void:
	if not has_log(r):
		return
	_state = state
	_viewer = viewer
	report = r
	t = 0.0
	playing = true
	_speed_i = 0
	_left.clear()
	var first := int(r["sides"][0]["empire"])
	var anchor := viewer if BattleReportPanel._fought(r, viewer) else first
	_left[anchor] = true
	_prepare()
	_refresh_buttons()
	visible = true
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.2)
	queue_redraw()


func hide_replay() -> void:
	if visible:
		visible = false
		closed.emit()


## Ferme sans revenir au rapport (nouvelle partie, chargement).
func close_silently() -> void:
	visible = false
	_state = null
	report = {}


func toggle_play() -> void:
	if day_count() > 0 and t >= day_count() * DAY_SECONDS:
		t = 0.0
	playing = not playing
	_refresh_buttons()


func day_count() -> int:
	return report.get("log", []).size()


## Jour affiché (indice dans le journal) et avancement dans ce jour (0 à 1).
func current_day() -> int:
	return clampi(int(t / DAY_SECONDS), 0, maxi(0, day_count() - 1))


func _cycle_speed() -> void:
	_speed_i = (_speed_i + 1) % SPEEDS.size()
	_refresh_buttons()


func _seek_day(delta: int) -> void:
	var d := clampi(current_day() + delta, 0, maxi(0, day_count() - 1))
	t = d * DAY_SECONDS + 0.001
	queue_redraw()


func _refresh_buttons() -> void:
	if _play_btn:
		_play_btn.text = "PAUSE" if playing else "LECTURE"
		_speed_btn.text = "VITESSE ×%d" % int(SPEEDS[_speed_i])


func _process(delta: float) -> void:
	if not visible:
		return
	if playing:
		t += delta * float(SPEEDS[_speed_i])
		var end := day_count() * DAY_SECONDS
		if t >= end:
			t = end
			playing = false
			_refresh_buttons()
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		toggle_play()
		accept_event()


# --- Préparation -------------------------------------------------------------------------------

func _prepare() -> void:
	var units: Array = report["units"]
	var n := units.size()
	_max_hp.clear()
	_dead_day.clear()
	for u: Array in units:
		_max_hp.append(maxi(1, Fleet.max_hp_of(String(u[1]))))
		_dead_day.append(-1)
	_dmg_until.clear()
	var acc: Array = []
	acc.resize(n)
	acc.fill(0)
	_dmg_until.append(acc.duplicate())
	var log: Array = report["log"]
	for d in log.size():
		var day: Dictionary = log[d]
		for sh: Array in day["shots"]:
			var tg := int(sh[1])
			if tg >= 0 and tg < n:
				acc[tg] = int(acc[tg]) + int(sh[3])
		for k in day["kills"]:
			if int(k) >= 0 and int(k) < n:
				_dead_day[int(k)] = d
		_dmg_until.append(acc.duplicate())
	_layout()


func _on_left(empire_id: int) -> bool:
	return _left.has(empire_id)


## Positions : écran près du centre, ligne puis arrière vers les bords ; plusieurs sous-colonnes
## quand une colonne déborde.
func _layout() -> void:
	var units: Array = report["units"]
	_pos.clear()
	_pos.resize(units.size())
	var w := size.x if size.x > 0 else 1600.0
	var h := size.y if size.y > 0 else 900.0
	var top := 200.0
	var bottom := h - 150.0
	var lines := ["screen", "line", "rear"]
	_col_labels.clear()
	for side in [true, false]:
		var col_x := w * 0.5
		for li in lines.size():
			var members: Array[int] = []
			for i in units.size():
				if _on_left(int(units[i][0])) == side and String(units[i][2]) == lines[li]:
					members.append(i)
			if members.is_empty():
				continue
			# Les grosses coques prennent plus de place : l'écart suit la plus grosse de la colonne.
			var step := STEP
			for m in members:
				step = maxf(step, float(SIZE_PX.get(Combat.ship_size(String(units[m][1])), 10.0)) * 2.0 + 34.0)
			var per_col := maxi(1, int((bottom - top) / step))
			@warning_ignore("integer_division")
			var cols := (members.size() + per_col - 1) / per_col
			for k in members.size():
				@warning_ignore("integer_division")
				var c := k / per_col
				var row := k % per_col
				var in_col := mini(per_col, members.size() - c * per_col)
				var x_off := 120.0 + li * COL_GAP + c * step
				var y := (top + bottom) * 0.5 + (row - (in_col - 1) * 0.5) * step
				_pos[members[k]] = Vector2(col_x - x_off if side else col_x + x_off, y)
			var lx := 120.0 + li * COL_GAP + (cols - 1) * step * 0.5
			_col_labels.append([Vector2(col_x - lx if side else col_x + lx, bottom + 30.0), Combat.line_label(String(lines[li]))])
			col_x += (-1.0 if side else 1.0) * (cols - 1) * step


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and visible and not report.is_empty():
		_layout()


# --- Dessin ------------------------------------------------------------------------------------

func _draw() -> void:
	if report.is_empty():
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.01, 0.015, 0.03, 0.985))
	for cl: Array in _col_labels:
		_centered(UiTheme.caps_font(), cl[0], String(cl[1]).to_upper(), 12, UiTheme.TEXT_DIM)
	var font := UiTheme.body_font()
	var log: Array = report["log"]
	var d := current_day()
	var frac := clampf((t - d * DAY_SECONDS) / DAY_SECONDS, 0.0, 1.0)
	var day: Dictionary = log[d] if d < log.size() else {}
	# Titre et phase.
	draw_string(UiTheme.caps_font(), Vector2(40, 52), "VUE DE BATAILLE", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiTheme.TEXT_DIM)
	draw_string(UiTheme.title_font(), Vector2(40, 92), "Bataille de %s" % String(report.get("system_name", "?")), HORIZONTAL_ALIGNMENT_LEFT, -1, 30, UiTheme.TEXT)
	var phase := int(day.get("phase", 0))
	draw_string(font, Vector2(40, 122), "Jour %d sur %d  ·  %s" % [int(day.get("day", d + 1)), day_count(), Combat.phase_label(phase)],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UiTheme.WARN)
	_draw_sides_names(font)
	_draw_phase_track(phase, frac)
	# Vaisseaux.
	var units: Array = report["units"]
	for i in units.size():
		_draw_unit(i, d, frac)
	# Tirs du jour, en décalé.
	var shots: Array = day.get("shots", [])
	var n := shots.size()
	for k in n:
		var start := 0.04 + 0.66 * float(k) / float(maxi(1, n))
		var p := (frac - start) / 0.3
		if p < 0.0 or p > 1.15:
			continue
		var sh: Array = shots[k]
		var a := int(sh[0])
		var b := int(sh[1])
		if a < 0 or b < 0 or a >= _pos.size() or b >= _pos.size():
			continue
		_draw_shot(String(sh[2]), _pos[a], _pos[b], clampf(p, 0.0, 1.0), p > 1.0, k)


func _draw_sides_names(font: Font) -> void:
	var left := PackedStringArray()
	var right := PackedStringArray()
	for s: Dictionary in report["sides"]:
		var e := _state.get_empire(int(s["empire"])) if _state else null
		var name := e.short_name() if e else "?"
		if _on_left(int(s["empire"])):
			left.append(name)
		else:
			right.append(name)
	var y := 175.0
	_centered(UiTheme.title_font(), Vector2(size.x * 0.25, y), " · ".join(left), 24, UiTheme.TEXT)
	_centered(UiTheme.title_font(), Vector2(size.x * 0.75, y), " · ".join(right), 24, UiTheme.TEXT)


func _centered(f: Font, at: Vector2, text: String, fsize: int, col: Color) -> void:
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	draw_string(f, Vector2(at.x - w * 0.5, at.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)


## Trois segments (longue, moyenne, courte portée) avec le curseur du jour.
func _draw_phase_track(phase: int, frac: float) -> void:
	var w := 420.0
	var x0 := size.x * 0.5 - w * 0.5
	var y := 108.0
	for i in 3:
		var r := Rect2(x0 + i * (w / 3.0) + 2, y, w / 3.0 - 4, 6)
		draw_rect(r, UiTheme.ACCENT if i == phase else Color(1, 1, 1, 0.12))
		draw_string(UiTheme.body_font(), Vector2(r.position.x, y - 8), Combat.phase_label(i), HORIZONTAL_ALIGNMENT_LEFT, r.size.x, 12,
				UiTheme.TEXT if i == phase else UiTheme.TEXT_DIM)
	var total := float(maxi(1, day_count()))
	var cx := x0 + w * clampf(t / (total * DAY_SECONDS), 0.0, 1.0)
	draw_circle(Vector2(cx, y + 3), 5.0, UiTheme.TEXT)
	var _unused := frac


func _draw_unit(i: int, d: int, frac: float) -> void:
	var u: Array = report["units"][i]
	var joined := int(u[3])
	var log: Array = report["log"]
	var today := int(log[d]["day"]) if d < log.size() else 0
	if joined > today:
		return  # pas encore arrivé (renfort)
	var pos: Vector2 = _pos[i]
	var left := _on_left(int(u[0]))
	var e := _state.get_empire(int(u[0])) if _state else null
	var col := e.color() if e else Color.WHITE
	var r := float(SIZE_PX.get(Combat.ship_size(String(u[1])), 10.0))
	var dd := int(_dead_day[i])
	var dead := dd >= 0 and (dd < d or (dd == d and frac > 0.85))
	var dying := dd == d and frac > 0.7 and frac <= 0.85
	var dir := 1.0 if left else -1.0
	var pts := PackedVector2Array([pos + Vector2(r * 1.2 * dir, 0), pos + Vector2(-r * 0.8 * dir, -r * 0.75),
			pos + Vector2(-r * 0.45 * dir, 0), pos + Vector2(-r * 0.8 * dir, r * 0.75)])
	if dead:
		draw_colored_polygon(pts, Color(0.35, 0.35, 0.38, 0.35))
		draw_line(pos + Vector2(-r, -r), pos + Vector2(r, r), Color(1, 0.4, 0.35, 0.5), 1.5)
		draw_line(pos + Vector2(-r, r), pos + Vector2(r, -r), Color(1, 0.4, 0.35, 0.5), 1.5)
		return
	if dying:
		draw_circle(pos, r * 2.2 * (frac - 0.7) / 0.15 + r, Color(1, 0.7, 0.3, 0.55))
	draw_colored_polygon(pts, col)
	draw_polyline(pts + PackedVector2Array([pts[0]]), col.lightened(0.4), 1.0)
	# Coque : dégâts appliqués à la fin de chaque jour.
	var dmg := int(_dmg_until[d][i]) if frac < 0.8 else int(_dmg_until[mini(d + 1, _dmg_until.size() - 1)][i])
	var hp_frac := clampf(1.0 - float(dmg) / float(_max_hp[i]), 0.0, 1.0)
	var bw := r * 2.2
	draw_rect(Rect2(pos + Vector2(-bw * 0.5, r + 4), Vector2(bw, 4)), Color(1, 1, 1, 0.12))
	draw_rect(Rect2(pos + Vector2(-bw * 0.5, r + 4), Vector2(bw * hp_frac, 4)), UiTheme.GOOD if hp_frac > 0.5 else (UiTheme.WARN if hp_frac > 0.25 else UiTheme.BAD))
	_centered(UiTheme.body_font(), pos + Vector2(0, r + 20), String(GameData.ship(String(u[1])).get("label", u[1])), 11, UiTheme.TEXT_DIM)


## Un tir, de `a` vers `b`, avancé de p (0 à 1) ; `hit` : l'impact (court éclair après l'arrivée).
func _draw_shot(weapon: String, a: Vector2, b: Vector2, p: float, hit: bool, k: int) -> void:
	var col: Color = WEAPON_COLORS.get(weapon, Color.WHITE)
	if hit:
		draw_circle(b, 9.0, Color(col.r, col.g, col.b, 0.5))
		return
	var bend := Vector2(0, -60.0 if k % 2 == 0 else 60.0)
	match weapon:
		"beam":
			var alpha := sin(p * PI)
			draw_line(a, b, Color(col.r, col.g, col.b, 0.85 * alpha), 3.0)
			draw_line(a, b, Color(1, 1, 1, 0.5 * alpha), 0.8)
		"kinetic":
			for j in 3:
				var q := clampf(p - j * 0.08, 0.0, 1.0)
				if q > 0.0:
					draw_circle(a.lerp(b, q), 2.6, col)
		"missile":
			for j in 4:
				var q := clampf(p - j * 0.04, 0.0, 1.0)
				draw_circle(_bezier(a, b, bend, q), 3.4 - j * 0.6, Color(col.r, col.g, col.b, 1.0 - j * 0.22))
		"torpedo":
			draw_circle(a.lerp(b, p), 3.6, col)
			draw_line(a.lerp(b, maxf(0.0, p - 0.12)), a.lerp(b, p), Color(col.r, col.g, col.b, 0.5), 2.0)
		"artillery":
			draw_circle(_bezier(a, b, Vector2(0, -110.0), p), 4.5, col)
		"stellar_lance":
			var la := sin(p * PI)
			draw_line(a, b, Color(col.r, col.g, col.b, 0.9 * la), 7.0)
			draw_line(a, b, Color(1, 1, 1, 0.8 * la), 2.0)
		"fighters", "bombers":
			for j in 4:
				var q := clampf(p - j * 0.05, 0.0, 1.0)
				var c := a.lerp(b, q) + Vector2(0, sin(q * 12.0 + j) * 10.0)
				draw_colored_polygon(PackedVector2Array([c + Vector2(4, 0), c + Vector2(-3, -2.5), c + Vector2(-3, 2.5)]), col)
		"martyr":
			draw_circle(a.lerp(b, p), 6.0, col)
		_:
			draw_circle(a.lerp(b, p), 2.0, col)


static func _bezier(a: Vector2, b: Vector2, bend: Vector2, q: float) -> Vector2:
	var c := (a + b) * 0.5 + bend
	return a.lerp(c, q).lerp(c.lerp(b, q), q)
