class_name GroundReplayPanel
extends Control
## Vue de la bataille au sol (combat au sol, prop. 18) : rejoue le journal d'un rapport de bataille au
## sol (Ground.reports_for), comme la vue de replay spatiale. Elle ne fait que relire : rien ici ne
## touche la simulation, et elle ne met pas la partie en pause.
##
## L'assaillant débarque à gauche, le défenseur tient la droite (milice et régiments). Chaque régiment
## est un pion à symbole militaire (infanterie : croix, blindés : chenille, aérien : ailes, milice :
## carré plein), avec sa barre de santé. Un jour dure DAY_SECONDS à vitesse 1 : les coups partent en
## décalé (traçantes), puis les unités détruites s'éteignent.
##
## Visuel des combats (lot 2) : par défaut, la vue montre le champ de bataille (GroundBackdrop) et les
## régiments en figurines (ArmyLayer) ; la touche T revient aux pions (vue tactique).

signal closed

const DAY_SECONDS := 1.6
const SPEEDS := [1.0, 2.0, 4.0]
const TOKEN := Vector2(46, 30)
const STEP := Vector2(60, 50)
const TERRAIN_COLORS := {
	"continental": Color(0.16, 0.26, 0.14), "ocean": Color(0.08, 0.18, 0.3), "desert": Color(0.38, 0.3, 0.16),
	"arctic": Color(0.5, 0.56, 0.62), "toxic": Color(0.26, 0.3, 0.1), "gas_giant": Color(0.3, 0.2, 0.32),
	"barren": Color(0.26, 0.22, 0.2), "asteroids": Color(0.18, 0.18, 0.2), "gaia": Color(0.12, 0.32, 0.18),
	"ecumenopole": Color(0.22, 0.22, 0.26),
}

var report: Dictionary = {}
var playing := true
var t := 0.0
var _speed_i := 0
var _state: GameState
var _viewer := 0
var _days := 1
var _pos: Array = []
var _dmg_until: Array = []  # [jour][unité] : dégâts cumulés avant ce jour (indice 0 : avant le premier)
var _dead_day: Array = []
var _by_day: Array = []     # coups de chaque jour (indice 0 = jour 1)
var _play_btn: Button
var _speed_btn: Button
var _tactical_btn: Button
var tactical := false
var backdrop: GroundBackdrop
var army: ArmyLayer
var sounds: BattleSounds       # points d'accroche du son (lot 3, prop. 37)
var _scale := 0
var _slow_time := 0.0
var _shot_cols: Array = [Color(1.0, 0.86, 0.45), Color(0.55, 0.85, 1.0)]  # couleur des tirs de chaque camp (registre, peuple)          # secondes passées sous le plancher d'images par seconde


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
	# Décor et figurines passent sous le dessin de la vue (show_behind_parent).
	backdrop = GroundBackdrop.new()
	backdrop.show_behind_parent = true
	add_child(backdrop)
	army = ArmyLayer.new()
	army.show_behind_parent = true
	add_child(army)
	sounds = BattleSounds.new()
	add_child(sounds)
	add_child(bar)
	_button(bar, "◀ JOUR", "Revenir au début du jour précédent", func() -> void: _seek_day(-1))
	_play_btn = _button(bar, "PAUSE", "Lecture ou pause  (Espace)", toggle_play)
	_speed_btn = _button(bar, "VITESSE ×1", "Changer la vitesse de lecture", _cycle_speed)
	_button(bar, "JOUR ▶", "Passer au jour suivant", func() -> void: _seek_day(1))
	_tactical_btn = _button(bar, "VUE TACTIQUE", "Basculer entre le champ de bataille et les pions  (T)", toggle_tactical)
	_button(bar, "FERMER", "Fermer la vue  (Échap)", hide_replay)


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
	return not r.get("shots", []).is_empty() and not r.get("units", []).is_empty()


func show_replay(state: GameState, viewer: int, r: Dictionary) -> void:
	if not has_log(r):
		return
	_state = state
	_viewer = viewer
	report = r
	t = 0.0
	playing = true
	_speed_i = 0
	_prepare()
	_setup_scene()
	_refresh_buttons()
	visible = true
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.2)
	queue_redraw()


func hide_replay() -> void:
	if visible:
		visible = false
		closed.emit()


func close_silently() -> void:
	visible = false
	_state = null
	report = {}


func toggle_tactical() -> void:
	tactical = not tactical
	_apply_tactical()
	_refresh_buttons()
	queue_redraw()


func _apply_tactical() -> void:
	backdrop.visible = not tactical
	army.visible = not tactical


## Peuple d'un camp : celui de l'empire (les habitants d'un système sans maître n'en ont pas).
func _side_fid(side: int) -> String:
	var e := _state.get_empire(int(report["a"]) if side == 0 else int(report["d"])) if _state else null
	return e.faction_id if e else ""


func _side_color(side: int) -> Color:
	var e := _state.get_empire(int(report["a"]) if side == 0 else int(report["d"])) if _state else null
	if e:
		return e.color()
	return Color(0.82, 0.62, 0.32) if side == 0 else Color(0.62, 0.66, 0.6)


## Monte le décor et les armées (échelle choisie dans les options) pour le rapport affiché.
func _setup_scene() -> void:
	_scale = UiSettings.battle_scale_level()
	_slow_time = 0.0
	army.reduced = false
	backdrop.size = size if size.x > 0 else Vector2(1600, 900)
	var sc: Dictionary = report.get("sc", {}).duplicate()
	if not sc.is_empty() and not sc.has("csp"):
		sc["csp"] = _side_fid(1)  # rapport d'avant le lot 3 : la ville du défenseur prend son peuple
	backdrop.setup(sc, UiSettings.replay_detail_level())
	army.setup(report, backdrop, _scale, _dmg_until, _dead_day, [_side_color(0), _side_color(1)], [_side_fid(0), _side_fid(1)])
	_shot_cols = [SpeciesLook.shot_color(_side_fid(0)), SpeciesLook.shot_color(_side_fid(1))]
	if (_shot_cols[0] as Color).is_equal_approx(_shot_cols[1]):
		_shot_cols[1] = (_shot_cols[1] as Color).lerp(Color(0.55, 0.85, 1.0), 0.6)  # même peuple des deux côtés : tirs distincts
	army.update(t, backdrop.tint)
	_apply_tactical()


func toggle_play() -> void:
	if t >= _days * DAY_SECONDS:
		t = 0.0
	playing = not playing
	_refresh_buttons()


func day_count() -> int:
	return _days


func current_day() -> int:
	return clampi(int(t / DAY_SECONDS), 0, maxi(0, _days - 1))


func _cycle_speed() -> void:
	_speed_i = (_speed_i + 1) % SPEEDS.size()
	_refresh_buttons()


func _seek_day(delta: int) -> void:
	t = clampi(current_day() + delta, 0, maxi(0, _days - 1)) * DAY_SECONDS + 0.001
	queue_redraw()


func _refresh_buttons() -> void:
	if _play_btn:
		_play_btn.text = "PAUSE" if playing else "LECTURE"
		_speed_btn.text = "VITESSE ×%d" % int(SPEEDS[_speed_i])
		_tactical_btn.text = "CHAMP DE BATAILLE" if tactical else "VUE TACTIQUE"


func _process(delta: float) -> void:
	if not visible:
		return
	if playing:
		var t0 := t
		t += delta * float(SPEEDS[_speed_i])
		if t >= _days * DAY_SECONDS:
			t = _days * DAY_SECONDS
			playing = false
			_refresh_buttons()
		emit_cues(t0, t)
	if not tactical:
		army.update(t, backdrop.tint)
		if playing:
			_watch_fps(delta)
	queue_redraw()


## Sous le plancher d'images par seconde pendant 2 s, la vue divise les figurines par deux (une fois).
func _watch_fps(delta: float) -> void:
	if army.reduced:
		return
	var floor_fps := float(GroundBackdrop.cfg().get("fps_floor", 30))
	if delta > 1.0 / floor_fps:
		_slow_time += delta
		if _slow_time > 2.0:
			army.set_reduced(true)
	else:
		_slow_time = maxf(0.0, _slow_time - delta * 0.5)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		toggle_play()
		accept_event()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_T:
		toggle_tactical()
		accept_event()


# --- Préparation -------------------------------------------------------------------------------

func _prepare() -> void:
	var units: Array = report["units"]
	var n := units.size()
	var shots: Array = report["shots"]
	_days = 1
	for sh: Array in shots:
		_days = maxi(_days, int(sh[0]))
	_by_day.clear()
	for d in _days:
		_by_day.append([])
	for sh: Array in shots:
		(_by_day[int(sh[0]) - 1] as Array).append(sh)
	_dead_day.clear()
	_dead_day.resize(n)
	_dead_day.fill(-1)
	_dmg_until.clear()
	var acc: Array = []
	acc.resize(n)
	acc.fill(0)
	_dmg_until.append(acc.duplicate())
	for d in _days:
		for sh: Array in _by_day[d]:
			var tg := int(sh[2])
			if tg >= 0 and tg < n:
				acc[tg] = int(acc[tg]) + int(sh[3])
				if int(sh[4]) == 1 and int(_dead_day[tg]) < 0:
					_dead_day[tg] = d
		_dmg_until.append(acc.duplicate())
	_layout()


## Pions rangés en colonnes depuis la ligne de front (au centre) vers l'arrière ; régiments devant,
## milice derrière (côté défenseur).
func _layout() -> void:
	var units: Array = report["units"]
	_pos.clear()
	_pos.resize(units.size())
	var w := size.x if size.x > 0 else 1600.0
	var h := size.y if size.y > 0 else 900.0
	var top := 230.0
	var bottom := h - 150.0
	var per_col := maxi(1, int((bottom - top) / STEP.y))
	for side in 2:
		var members: Array[int] = []
		for i in units.size():
			if int((units[i] as Dictionary)["side"]) == side and String(units[i]["t"]) != "milice":
				members.append(i)
		for i in units.size():
			if int((units[i] as Dictionary)["side"]) == side and String(units[i]["t"]) == "milice":
				members.append(i)
		for k in members.size():
			@warning_ignore("integer_division")
			var c := k / per_col
			var row := k % per_col
			var in_col := mini(per_col, members.size() - c * per_col)
			var x_off := 110.0 + c * STEP.x
			var y := (top + bottom) * 0.5 + (row - (in_col - 1) * 0.5) * STEP.y
			_pos[members[k]] = Vector2(w * 0.5 - x_off if side == 0 else w * 0.5 + x_off, y)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and visible and not report.is_empty():
		_layout()
		if backdrop and army:
			_setup_scene()


# --- Dessin ------------------------------------------------------------------------------------

func _draw() -> void:
	if report.is_empty():
		return
	var ter := String(report.get("ter", ""))
	if not tactical:
		_draw_field()
		return
	var gcol: Color = TERRAIN_COLORS.get(ter, Color(0.15, 0.17, 0.15))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.01, 0.015, 0.03, 0.985))
	# Le sol : une bande de terrain, plus sombre côté plages (gauche).
	var ground := Rect2(Vector2(30, 200), Vector2(size.x - 60, size.y - 330))
	draw_rect(ground, Color(gcol, 0.55))
	draw_rect(Rect2(ground.position, Vector2(ground.size.x * 0.18, ground.size.y)), Color(gcol.darkened(0.45), 0.6))
	draw_line(Vector2(size.x * 0.5, ground.position.y), Vector2(size.x * 0.5, ground.end.y), Color(1, 1, 1, 0.08), 2.0)
	var font := UiTheme.body_font()
	var d := current_day()
	var frac := clampf((t - d * DAY_SECONDS) / DAY_SECONDS, 0.0, 1.0)
	_draw_header(font, d)
	_draw_names(font)
	_draw_track()
	var units: Array = report["units"]
	for i in units.size():
		_draw_unit(i, d, frac)
	var shots: Array = _by_day[d] if d < _by_day.size() else []
	var n := shots.size()
	for k in n:
		var start := 0.04 + 0.62 * float(k) / float(maxi(1, n))
		var p := (frac - start) / 0.28
		if p < 0.0 or p > 1.15:
			continue
		var sh: Array = shots[k]
		var a := int(sh[1])
		var b := int(sh[2])
		if a < 0 or b < 0 or a >= _pos.size() or b >= _pos.size():
			continue
		_draw_shot(_pos[a], _pos[b], clampf(p, 0.0, 1.0), p > 1.0, int((units[a] as Dictionary)["side"]))


func _draw_header(font: Font, d: int) -> void:
	var ter := String(report.get("ter", ""))
	var sname := _state.galaxy.systems[int(report["s"])].system_name if _state else "?"
	draw_string(UiTheme.caps_font(), Vector2(40, 52), "BATAILLE AU SOL", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiTheme.TEXT_DIM)
	draw_string(UiTheme.title_font(), Vector2(40, 92), "Bataille de %s" % sname, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, UiTheme.TEXT)
	var tline := "Jour %d sur %d" % [d + 1, _days]
	if ter != "":
		tline += "  ·  terrain : %s" % String(Ground.terrain_def(ter).get("label", ter)).to_lower()
	draw_string(font, Vector2(40, 122), tline, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UiTheme.WARN)


func _draw_names(font: Font) -> void:
	var ea := _state.get_empire(int(report["a"])) if _state else null
	var ed := _state.get_empire(int(report["d"])) if _state else null
	var y := 175.0
	_centered(UiTheme.title_font(), Vector2(size.x * 0.25, y), ea.short_name() if ea else "?", 24, UiTheme.TEXT)
	_centered(UiTheme.title_font(), Vector2(size.x * 0.75, y), ed.short_name() if ed else "Habitants", 24, UiTheme.TEXT)
	var ta := String(report.get("ta", ""))
	var td := String(report.get("td", ""))
	if ta != "":
		_centered(font, Vector2(size.x * 0.25, y + 20), Ground.tactic_label("attack", ta), 13, UiTheme.TEXT_DIM)
	if td != "":
		_centered(font, Vector2(size.x * 0.75, y + 20), Ground.tactic_label("defense", td), 13, UiTheme.TEXT_DIM)


func _draw_track() -> void:
	var w := 420.0
	var x0 := size.x * 0.5 - w * 0.5
	var y := 108.0
	draw_rect(Rect2(x0, y, w, 6), Color(1, 1, 1, 0.12))
	var cx := x0 + w * clampf(t / (float(maxi(1, _days)) * DAY_SECONDS), 0.0, 1.0)
	draw_rect(Rect2(x0, y, cx - x0, 6), UiTheme.ACCENT)
	draw_circle(Vector2(cx, y + 3), 5.0, UiTheme.TEXT)


func _centered(f: Font, at: Vector2, text: String, fsize: int, col: Color) -> void:
	var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	draw_string(f, Vector2(at.x - tw * 0.5, at.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)


func _draw_unit(i: int, d: int, frac: float) -> void:
	var u: Dictionary = report["units"][i]
	var pos: Vector2 = _pos[i]
	var side := int(u["side"])
	var e := _state.get_empire(int(report["a"]) if side == 0 else int(report["d"])) if _state else null
	var col := e.color() if e else Color(0.7, 0.7, 0.7)
	var dd := int(_dead_day[i])
	var dead := dd >= 0 and (dd < d or (dd == d and frac > 0.85))
	var dying := dd == d and frac > 0.7 and frac <= 0.85
	var r := Rect2(pos - TOKEN * 0.5, TOKEN)
	var ty := String(u["t"])
	var fam := String(Ground.type_def(ty).get("family", ty))
	if dead:
		draw_rect(r, Color(0.3, 0.3, 0.32, 0.3))
		draw_line(r.position, r.end, Color(1, 0.4, 0.35, 0.5), 1.5)
		draw_line(Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.position.y), Color(1, 0.4, 0.35, 0.5), 1.5)
		return
	if dying:
		draw_circle(pos, 30.0 * (frac - 0.7) / 0.15 + 14.0, Color(1, 0.7, 0.3, 0.5))
	var fill := Color(col, 0.35 if ty != "milice" else 0.6)
	draw_rect(r, fill)
	draw_rect(r, col.lightened(0.35), false, 1.5)
	var inner := r.grow(-5)
	var lc := Color(1, 1, 1, 0.9)
	match fam:
		"infanterie":
			if ty == "milice":
				draw_rect(Rect2(pos - Vector2(5, 5), Vector2(10, 10)), lc)
			else:
				draw_line(inner.position, inner.end, lc, 1.6)
				draw_line(Vector2(inner.position.x, inner.end.y), Vector2(inner.end.x, inner.position.y), lc, 1.6)
		"blindes":
			var ov := Rect2(pos - Vector2(13, 6), Vector2(26, 12))
			draw_arc(ov.position + Vector2(6, 6), 6, PI * 0.5, PI * 1.5, 10, lc, 1.6)
			draw_arc(ov.end - Vector2(6, 6), 6, -PI * 0.5, PI * 0.5, 10, lc, 1.6)
			draw_line(ov.position + Vector2(6, 0), Vector2(ov.end.x - 6, ov.position.y), lc, 1.6)
			draw_line(Vector2(ov.position.x + 6, ov.end.y), ov.end - Vector2(6, 0), lc, 1.6)
		"aerien":
			draw_arc(pos + Vector2(-6, 4), 7, PI, TAU, 10, lc, 1.6)
			draw_arc(pos + Vector2(6, 4), 7, PI, TAU, 10, lc, 1.6)
	var ab: Dictionary = Ground.type_def(ty).get("abilities", {})
	if ab.has("sabotage"):
		draw_string(UiTheme.caps_font(), r.position + Vector2(2, 10), "FS", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, lc)
	elif ab.has("siege"):
		draw_string(UiTheme.caps_font(), r.position + Vector2(2, 10), "G", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, lc)
	var mh := maxi(1, int(u.get("hp", 100)))
	var dmg := int(_dmg_until[d][i]) if frac < 0.8 else int(_dmg_until[mini(d + 1, _dmg_until.size() - 1)][i])
	var hp_frac := clampf(1.0 - float(dmg) / float(mh), 0.0, 1.0)
	draw_rect(Rect2(r.position + Vector2(0, r.size.y + 3), Vector2(r.size.x, 4)), Color(1, 1, 1, 0.12))
	draw_rect(Rect2(r.position + Vector2(0, r.size.y + 3), Vector2(r.size.x * hp_frac, 4)),
			UiTheme.GOOD if hp_frac > 0.5 else (UiTheme.WARN if hp_frac > 0.25 else UiTheme.BAD))


func _draw_shot(a: Vector2, b: Vector2, p: float, hit: bool, side: int) -> void:
	var col := Color(1.0, 0.86, 0.45) if side == 0 else Color(0.55, 0.85, 1.0)
	if hit:
		draw_circle(b, 8.0, Color(col, 0.5))
		return
	for j in 3:
		var q := clampf(p - j * 0.07, 0.0, 1.0)
		if q > 0.0:
			draw_circle(a.lerp(b, q) + Vector2(0, -sin(q * PI) * 18.0), 2.4, Color(col, 1.0 - j * 0.25))


# --- Champ de bataille (visuel des combats, lot 2) ---------------------------------------------

static func _hash(n: float) -> float:
	return fposmod(sin(n * 12.9898) * 43758.5453, 1.0)


func _draw_field() -> void:
	var font := UiTheme.body_font()
	var d := current_day()
	var frac := clampf((t - d * DAY_SECONDS) / DAY_SECONDS, 0.0, 1.0)
	_draw_bombard()
	_draw_banners(font)
	_draw_field_shots(d, frac)
	_draw_weather()
	# Bandeau sombre en haut pour garder les titres lisibles sur le ciel.
	var top := 215.0
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(size.x, 0), Vector2(size.x, top), Vector2(0, top)]),
			PackedColorArray([Color(0, 0, 0, 0.72), Color(0, 0, 0, 0.72), Color(0, 0, 0, 0), Color(0, 0, 0, 0)]))
	draw_polygon(PackedVector2Array([Vector2(0, size.y - 110), Vector2(size.x, size.y - 110), Vector2(size.x, size.y), Vector2(0, size.y)]),
			PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 0.6), Color(0, 0, 0, 0.6)]))
	_draw_header(font, d)
	_draw_names(font)
	_draw_track()
	var labels: Dictionary = GroundBackdrop.cfg().get("scale_labels", {})
	var scales: Array = GroundBackdrop.cfg().get("scales", [])
	var sl := String(labels.get(String(scales[_scale]) if _scale < scales.size() else "", ""))
	var legend := "%s  ·  %d figurines" % [sl, army.living_total(t)]
	if army.reduced:
		legend += "  ·  allégé (images par seconde)"
	draw_string(font, Vector2(40, size.y - 40), legend, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiTheme.TEXT_DIM)


## Bombardement orbital (siège ou tactique « bombardement ») : rayons qui tombent du ciel côté défenseur.
func _draw_bombard() -> void:
	if not bool(report.get("sc", {}).get("bombard", false)):
		return
	var period := 0.45
	var m := int(t / period)
	for back in 2:
		var idx := m - back
		if idx < 0:
			continue
		var age := (t - idx * period) / 0.4
		if age < 0.0 or age > 1.0:
			continue
		var gx := size.x * (0.55 + 0.45 * _hash(idx * 1.7 + 3.0))
		var gz := _hash(idx * 2.3 + 1.0)
		var p := backdrop.project(gx, gz)
		var s := backdrop.scale_at(gz)
		var a := 1.0 - age
		draw_line(Vector2(p.x - 40.0, 0), p, Color(1.0, 0.85, 0.6, 0.55 * a), 3.0 * s)
		draw_line(Vector2(p.x - 40.0, 0), p, Color(1, 1, 1, 0.8 * a), 1.2)
		draw_circle(p, (10.0 + 34.0 * age) * s, Color(1.0, 0.6, 0.25, 0.45 * a))
		draw_circle(p, 8.0 * s * a, Color(1, 0.95, 0.8, a))


## Bannière au-dessus de chaque régiment (couleur de l'empire), chevrons de vétérance, étoile du général.
func _draw_banners(font: Font) -> void:
	var units: Array = report["units"]
	var vets := {"aguerri": 1, "veteran": 2, "elite": 3}
	for i in units.size():
		var u: Dictionary = units[i]
		if String(u["t"]) == "milice" or army.alive_count(i, t) == 0:
			continue
		var fade := 1.0
		if army.routed(i, t):
			fade = clampf(1.0 - (t - float(army.units[i]["rout_t"])) / (DAY_SECONDS * 1.6), 0.0, 1.0)
			if fade <= 0.0:
				continue
		var c := army.center(i, t)
		var a := army.anchor(i, t)
		var s := backdrop.scale_at(a.y)
		var col := _side_color(int(u["side"]))
		var base := c - Vector2(0, 26.0 * s)
		var top := base - Vector2(0, 34.0 * s)
		draw_line(base, top, Color(0.85, 0.85, 0.8, 0.9 * fade), 1.4)
		var flag := Rect2(top, Vector2(18.0 * s, 11.0 * s))
		if army.routed(i, t):
			flag.size.y *= 0.6
		draw_rect(flag, Color(col, 0.95 * fade))
		draw_rect(flag, Color(0, 0, 0, 0.5 * fade), false, 1.0)
		var nv := int(vets.get(String(u.get("vet", "")), 0))
		for k in nv:
			var y := flag.end.y + 3.0 + k * 3.5
			draw_polyline(PackedVector2Array([Vector2(top.x + 2, y), Vector2(top.x + 6, y + 2.5), Vector2(top.x + 10, y)]),
					Color(1.0, 0.85, 0.35, fade), 1.4)
		if String(u.get("gen", "")) != "":
			_star(top + Vector2(-8.0 * s, 4.0 * s), 6.0 * s, Color(1.0, 0.85, 0.35, fade))
			draw_string(font, top + Vector2(-8.0 * s, -6.0), String(u["gen"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 0.9, 0.6, fade))
		if army.routed(i, t):
			draw_string(UiTheme.caps_font(), flag.position + Vector2(22.0 * s, 9.0), "DÉROUTE", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(UiTheme.BAD, fade))
		# Santé du régiment sous la bannière.
		var hpf := float(army.alive_count(i, t)) / float(maxi(1, int(army.units[i]["n"])))
		var bar := Rect2(flag.position + Vector2(0, -6), Vector2(22.0 * s, 3))
		draw_rect(bar, Color(0, 0, 0, 0.5 * fade))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * hpf, 3)),
				Color(UiTheme.GOOD if hpf > 0.5 else (UiTheme.WARN if hpf > 0.25 else UiTheme.BAD), fade))


func _star(c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for k in 10:
		var rr := r if k % 2 == 0 else r * 0.45
		var ang := -PI * 0.5 + k * PI / 5.0
		pts.append(c + Vector2(cos(ang), sin(ang)) * rr)
	draw_colored_polygon(pts, col)


## Coups du jour entre figurines : traçantes pour l'infanterie, obus en cloche pour les blindés, salves
## de roquettes pour l'aérien ; éclair à la bouche du canon, explosion à l'impact.
func _draw_field_shots(d: int, frac: float) -> void:
	var units: Array = report["units"]
	var shots: Array = _by_day[d] if d < _by_day.size() else []
	var n := shots.size()
	for k in n:
		var start := 0.04 + 0.62 * float(k) / float(maxi(1, n))
		var p := (frac - start) / 0.28
		if p < 0.0 or p > 1.3:
			continue
		var sh: Array = shots[k]
		var a := int(sh[1])
		var b := int(sh[2])
		if a < 0 or b < 0 or a >= army.units.size() or b >= army.units.size():
			continue
		var side := int((units[a] as Dictionary)["side"])
		var col: Color = _shot_cols[side]
		var fam := String(army.units[a]["fam"])
		var seed_k := d * 131 + k * 17
		var vol := 3 if fam == "infanterie" or fam == "milice" else 1
		for v in vol:
			var pa := army.figure_pos(a, seed_k + v * 5, t)
			var pb := army.figure_pos(b, seed_k * 3 + v * 11, t)
			var q := clampf(p - v * 0.08, 0.0, 1.0)
			if p <= 1.0:
				if q < 0.25:
					draw_circle(pa, 3.0 * (1.0 - q * 4.0) + 1.0, Color(1, 0.95, 0.7, 0.9))
				match fam:
					"blindes":
						var arc := pa.lerp(pb, q) + Vector2(0, -sin(q * PI) * 60.0)
						draw_circle(arc, 3.4, col)
						draw_circle(arc, 1.6, Color(1, 1, 1))
					"aerien":
						var h0 := pa.lerp(pb, maxf(0.0, q - 0.12))
						draw_line(h0, pa.lerp(pb, q), Color(col, 0.85), 2.0)
					_:
						draw_line(pa.lerp(pb, maxf(0.0, q - 0.14)), pa.lerp(pb, q), Color(col, 1.0), 2.0)
			elif v == 0:
				var e := (p - 1.0) / 0.3
				var big := fam == "blindes" or fam == "aerien"
				var r := (6.0 if not big else 16.0) * (0.5 + e)
				draw_circle(pb, r, Color(1.0, 0.6, 0.25, 0.6 * (1.0 - e)))
				if big:
					draw_circle(pb - Vector2(0, 8.0 * e), r * 0.8, Color(0.25, 0.22, 0.2, 0.45 * (1.0 - e)))


## Météo du biome (pluie, neige, sable, pluie acide), fonction du temps du replay.
func _draw_weather() -> void:
	var w := String(backdrop.weather)
	if w == "none" or w == "":
		return
	var count: int = [60, 140, 240][clampi(UiSettings.replay_detail_level(), 0, 2)]
	var tt := t * 0.6
	for i in count:
		var hx := _hash(i * 1.31 + 0.5)
		var hy := _hash(i * 2.77 + 1.5)
		match w:
			"rain", "acid":
				var x := fposmod(hx * size.x - tt * 160.0, size.x)
				var y := fposmod(hy * size.y + tt * 900.0, size.y)
				var c := Color(0.75, 0.82, 0.95, 0.35) if w == "rain" else Color(0.7, 0.95, 0.35, 0.4)
				draw_line(Vector2(x, y), Vector2(x - 4, y + 16), c, 1.0)
			"snow":
				var x := fposmod(hx * size.x + sin(tt * 2.0 + i) * 20.0, size.x)
				var y := fposmod(hy * size.y + tt * 90.0, size.y)
				draw_circle(Vector2(x, y), 1.2 + hx * 1.4, Color(1, 1, 1, 0.7))
			"sand":
				var x := fposmod(hx * size.x + tt * 700.0, size.x)
				var y := fposmod(hy * size.y + sin(tt + i) * 8.0, size.y)
				draw_line(Vector2(x, y), Vector2(x + 22, y + 2), Color(0.9, 0.75, 0.5, 0.3), 1.2)
	if w == "sand":
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.85, 0.65, 0.4, 0.12))


## Repères sonores passés entre t0 et t1 (prop. 37) : salves, obus des blindés, bombardement, déroutes.
func emit_cues(t0: float, t1: float) -> void:
	if sounds == null or t1 <= t0 or army == null:
		return
	var d0 := clampi(int(t0 / DAY_SECONDS), 0, maxi(0, _by_day.size() - 1))
	var d1 := clampi(int(t1 / DAY_SECONDS), 0, maxi(0, _by_day.size() - 1))
	for d in range(d0, d1 + 1):
		if d >= _by_day.size():
			break
		var shots: Array = _by_day[d]
		var n := shots.size()
		for k in n:
			var at := (d + 0.04 + 0.62 * float(k) / float(maxi(1, n))) * DAY_SECONDS
			var a := int(shots[k][1])
			if at <= t0 or at > t1 or a < 0 or a >= army.units.size():
				continue
			var fam := String(army.units[a]["fam"])
			sounds.play("obus" if fam == "blindes" else ("roquette" if fam == "aerien" else "salve"))
		if bool(report.get("sc", {}).get("bombard", false)):
			var bt := (d + 0.5) * DAY_SECONDS
			if bt > t0 and bt <= t1:
				sounds.play("bombardement")
	for i in army.units.size():
		var rt := float(army.units[i].get("rout_t", -1.0))
		if rt > t0 and rt <= t1:
			sounds.play("deroute")
