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
##
## Habillage (étude visuel des combats, lot 1) : le décor du vrai système (BattleBackdrop) passe
## derrière, les sprites de vaisseaux sont éclairés par son étoile (shaders/ship_lit.gdshader), et les
## effets suivent la famille d'arme : bulles de bouclier, étincelles, fumée et feux sous la moitié de
## la coque, explosions (en plusieurs temps pour les méga-vaisseaux), débris qui dérivent jusqu'à la
## fin. Tout est fonction du temps du replay `t`, jamais du temps réel : une même image se rejoue
## à l'identique. La touche T bascule sur la vue tactique d'origine (fond uni, sans décor).

signal closed

const DAY_SECONDS := 2.2
const SPEEDS := [1.0, 2.0, 4.0]
const SIZE_PX := {"small": 11.0, "medium": 15.0, "large": 21.0, "titan": 32.0}
const SPRITE_SCALE := 5.0  # longueur d'un sprite de vaisseau, en multiples de SIZE_PX
const STEP := 54.0        # écart entre deux vaisseaux d'une colonne
const COL_GAP := 190.0    # écart entre écran, ligne et arrière
const WEAPON_COLORS := {
	"kinetic": Color(1.0, 0.86, 0.45), "beam": Color(0.45, 0.92, 1.0), "missile": Color(1.0, 0.6, 0.3),
	"torpedo": Color(0.95, 0.45, 0.85), "artillery": Color(1.0, 0.95, 0.8), "fighters": Color(0.6, 1.0, 0.6),
	"bombers": Color(0.85, 1.0, 0.4), "stellar_lance": Color(1.0, 0.98, 0.7), "singularity": Color(0.75, 0.4, 1.0),
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
var cinematic: BattleCinematic  # la même bataille en 3D, par-dessus cette vue
## Vue tactique : fond uni et pions, sans décor ni effets (T).
var tactical := false
var backdrop: BattleBackdrop
var _ships: Node2D             # sprites éclairés, derrière le dessin de la vue
var _sprites := {}             # unité -> Sprite2D
var _lit: ShaderMaterial
var _detail := 1
var _tactical_btn: Button
const LIT_SHADER := preload("res://shaders/ship_lit.gdshader")
## Lot 3 : positions de repos (le rangement), les manœuvres les déplacent selon la phase et la tactique.
var _base_pos: Array = []
var _carriers := {}            # unité -> nombre d'appareils de son essaim
var _no_fighters := false      # terrain qui cloue les chasseurs au hangar
var sounds: BattleSounds


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS  # sprites de vaisseaux réduits
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
	_tactical_btn = _button(bar, "VUE TACTIQUE", "Basculer entre le décor et la vue tactique, sans fioritures  (T)", toggle_tactical)
	_button(bar, "CINÉMATIQUE 3D", "Regarder la bataille en 3D, sous plusieurs plans de caméra (prototype)", open_cinematic)
	_button(bar, "PASSER", "Fermer la vue et revenir au rapport  (Échap)", hide_replay)
	# Décor et vaisseaux passent sous le dessin de la vue (show_behind_parent) ; le premier plan
	# (rochers, poussière) passe au-dessus des vaisseaux mais sous les boutons.
	backdrop = BattleBackdrop.new()
	backdrop.show_behind_parent = true
	add_child(backdrop)
	move_child(backdrop, 0)
	_ships = Node2D.new()
	_ships.show_behind_parent = true
	add_child(_ships)
	move_child(_ships, 1)
	add_child(backdrop.foreground)
	move_child(backdrop.foreground, 2)
	_lit = ShaderMaterial.new()
	_lit.shader = LIT_SHADER
	sounds = BattleSounds.new()
	add_child(sounds)
	cinematic = BattleCinematic.new()
	add_child(cinematic)
	cinematic.closed.connect(func() -> void: queue_redraw())


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
	_detail = UiSettings.replay_detail_level()
	backdrop.size = size
	backdrop.setup(r.get("scene", {}), _detail)
	var light := BattleBackdrop.star_light(String(backdrop.scene.get("star", "yellow")))
	_lit.set_shader_parameter("light_color", backdrop.light_color())
	_lit.set_shader_parameter("power", light["power"])
	_lit.set_shader_parameter("ambient", light["ambient"])
	_prepare()
	_build_sprites()
	_apply_tactical()
	_refresh_buttons()
	visible = true
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.2)
	queue_redraw()


## Ouvre la cinématique 3D de la bataille affichée (la vue 2D se met en pause dessous).
func open_cinematic() -> void:
	if report.is_empty():
		return
	playing = false
	_refresh_buttons()
	cinematic.show_cinematic(_state, report, _left)


func hide_replay() -> void:
	if cinematic and cinematic.visible:
		cinematic.hide_cinematic()  # Échap dans la cinématique : retour à la vue 2D
		return
	if visible:
		visible = false
		closed.emit()


## Ferme sans revenir au rapport (nouvelle partie, chargement).
func close_silently() -> void:
	if cinematic:
		cinematic.close_silently()
	visible = false
	_state = null
	report = {}
	_clear_sprites()


func toggle_play() -> void:
	if day_count() > 0 and t >= day_count() * DAY_SECONDS:
		t = 0.0
	playing = not playing
	_refresh_buttons()


func toggle_tactical() -> void:
	tactical = not tactical
	_apply_tactical()
	_refresh_buttons()
	queue_redraw()


func _apply_tactical() -> void:
	backdrop.visible = not tactical
	backdrop.foreground.visible = not tactical
	_ships.visible = not tactical


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
		_tactical_btn.text = "VUE DÉCOR" if tactical else "VUE TACTIQUE"


func _process(delta: float) -> void:
	if not visible:
		return
	if playing:
		var t0 := t
		t += delta * float(SPEEDS[_speed_i])
		var end := day_count() * DAY_SECONDS
		if t >= end:
			t = end
			playing = false
			_refresh_buttons()
		emit_cues(t0, t)
	_update_scene()
	queue_redraw()


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
	_carriers.clear()
	var sw: Dictionary = GameData.battle_visuals().get("swarms", {})
	for i in n:
		var wp := Combat.weapons(String(units[i][1]))
		var pts := int(wp.get("fighters", 0)) + int(wp.get("bombers", 0))
		if pts > 0:
			_carriers[i] = clampi(int(ceil(float(pts) / float(sw.get("per_wing", 2)))), 1, int(sw.get("max", 8)))
	_no_fighters = false
	for tid in report.get("scene", {}).get("terrain", []):
		var wpct: Dictionary = Terrain.def(String(tid)).get("fx", {}).get("weapon_pct", {})
		if wpct.has("fighters") and int(wpct["fighters"]) == 0:
			_no_fighters = true
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
	_base_pos = _pos.duplicate()
	_maneuver()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and visible and not report.is_empty():
		_layout()
		_update_scene()


# --- Dessin ------------------------------------------------------------------------------------

func _draw() -> void:
	if report.is_empty():
		return
	_maneuver()
	if tactical:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.01, 0.015, 0.03, 0.985))
	else:
		# Bandeau sombre en haut : le titre reste lisible sur le décor.
		var band := PackedColorArray([Color(0, 0, 0, 0.72), Color(0, 0, 0, 0.72), Color(0, 0, 0, 0), Color(0, 0, 0, 0)])
		draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(size.x, 0), Vector2(size.x, 210), Vector2(0, 210)]), band)
		draw_polygon(PackedVector2Array([Vector2(0, size.y - 130), Vector2(size.x, size.y - 130), Vector2(size.x, size.y), Vector2(0, size.y)]),
				PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 0.6), Color(0, 0, 0, 0.6)]))
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
	if not tactical:
		_draw_swarms(d, frac)
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
		var w := String(sh[2])
		var stopped := int(sh[3]) <= 0 and (w == "missile" or w == "torpedo")
		if stopped and not tactical:
			# Défense ponctuelle : le missile éclate en route.
			if p < 0.7:
				_draw_shot(w, _pos[a], _pos[b], p, false, k)
			elif p < 0.95:
				var q := (p - 0.7) / 0.25
				var c: Vector2 = _bezier(_pos[a], _pos[b], Vector2(0, -60.0 if k % 2 == 0 else 60.0), 0.7) if w == "missile" else _pos[a].lerp(_pos[b], 0.7)
				draw_circle(c, 3.0 + q * 9.0, Color(1.0, 0.85, 0.5, 1.0 - q))
			continue
		_draw_shot(w, _pos[a], _pos[b], clampf(p, 0.0, 1.0), p > 1.0, k)
		if p > 1.0 and not tactical:
			_draw_impact(b, _pos[b], (p - 1.0) / 0.15, k)
	_draw_boards(day.get("boards", []), frac)


## Prises de guerre : grappins et capsules (pointillés), puis la prise qui change de couleur (anneau).
func _draw_boards(boards: Array, frac: float) -> void:
	for bd: Array in boards:
		var a := int(bd[0])
		var b := int(bd[1])
		if a < 0 or b < 0 or a >= _pos.size() or b >= _pos.size() or frac < 0.45:
			continue
		var p := clampf((frac - 0.45) / 0.35, 0.0, 1.0)
		var end: Vector2 = _pos[a].lerp(_pos[b], p)
		draw_dashed_line(_pos[a], end, Color(0.95, 0.85, 0.45, 0.85), 1.5, 5.0)
		if p >= 1.0:
			var ok := int(bd[2]) == 1
			draw_arc(_pos[b], 14.0, 0.0, TAU, 24, Color(0.45, 1.0, 0.55, 0.9) if ok else Color(1.0, 0.45, 0.35, 0.7), 2.0)


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
	var dying := dd == d and frac > 0.6 and frac <= 0.85
	var dir := 1.0 if left else -1.0
	var pts := PackedVector2Array([pos + Vector2(r * 1.2 * dir, 0), pos + Vector2(-r * 0.8 * dir, -r * 0.75),
			pos + Vector2(-r * 0.45 * dir, 0), pos + Vector2(-r * 0.8 * dir, r * 0.75)])
	var has_sprite := not tactical and _sprites.has(i)
	var art: Texture2D = null
	if not has_sprite and e:
		art = ShipArt.texture(e.faction_id, String(u[1]), col)
	if art:
		# Sprite tiré du modèle 3D : nez vers la droite, retourné pour le camp de droite.
		var long := r * SPRITE_SCALE
		var ext := Vector2(long, long * art.get_height() / art.get_width())
		draw_set_transform(pos, 0.0, Vector2(dir, 1.0))
		draw_texture_rect(art, Rect2(-ext * 0.5, ext), false, Color(0.4, 0.4, 0.42, 0.4) if dead else Color.WHITE)
		draw_set_transform(Vector2.ZERO)
	if dead:
		if tactical:
			if not art:
				draw_colored_polygon(pts, Color(0.35, 0.35, 0.38, 0.35))
			draw_line(pos + Vector2(-r, -r), pos + Vector2(r, r), Color(1, 0.4, 0.35, 0.5), 1.5)
			draw_line(pos + Vector2(-r, r), pos + Vector2(r, -r), Color(1, 0.4, 0.35, 0.5), 1.5)
		else:
			if not has_sprite:
				draw_colored_polygon(pts, Color(0.18, 0.18, 0.2, 0.6))
			_draw_debris(i, pos, r, dd)
		return
	if dying and not tactical:
		_draw_explosion(i, pos, r, (frac - 0.6) / 0.25)
	elif dying:
		draw_circle(pos, r * 2.2 * (frac - 0.7) / 0.15 + r, Color(1, 0.7, 0.3, 0.55))
	if not art and not has_sprite:
		draw_colored_polygon(pts, col)
		draw_polyline(pts + PackedVector2Array([pts[0]]), col.lightened(0.4), 1.0)
	# Coque : dégâts appliqués à la fin de chaque jour.
	var hp_frac := _hp_frac(i, d, frac)
	if not tactical and hp_frac < float(_fx().get("burn_below", 0.5)):
		_draw_smoke(i, pos, r, hp_frac)
	var bw := r * 2.2
	draw_rect(Rect2(pos + Vector2(-bw * 0.5, r + 4), Vector2(bw, 4)), Color(1, 1, 1, 0.12))
	draw_rect(Rect2(pos + Vector2(-bw * 0.5, r + 4), Vector2(bw * hp_frac, 4)), UiTheme.GOOD if hp_frac > 0.5 else (UiTheme.WARN if hp_frac > 0.25 else UiTheme.BAD))
	_centered(UiTheme.body_font(), pos + Vector2(0, r + 20), String(GameData.ship(String(u[1])).get("label", u[1])), 11, UiTheme.TEXT_DIM)


func _hp_frac(i: int, d: int, frac: float) -> float:
	var dmg := int(_dmg_until[d][i]) if frac < 0.8 else int(_dmg_until[mini(d + 1, _dmg_until.size() - 1)][i])
	return clampf(1.0 - float(dmg) / float(_max_hp[i]), 0.0, 1.0)


func _fx() -> Dictionary:
	return GameData.battle_visuals().get("effects", {})


## Nombre aléatoire fixe pour (unité, k) : les effets se rejouent à l'identique.
static func _h(i: int, k: int) -> float:
	return fposmod(sin(float(i) * 12.9898 + float(k) * 78.233) * 43758.5453, 1.0)


## Instant (en secondes de replay) de la destruction d'une unité.
func _death_time(dd: int) -> float:
	return (float(dd) + 0.78) * DAY_SECONDS


## Explosion : éclair, boule de feu et onde de choc ; les méga-vaisseaux sautent en trois temps.
func _draw_explosion(i: int, pos: Vector2, r: float, q: float) -> void:
	var u: Array = report["units"][i]
	var mega := (_fx().get("mega_sizes", ["titan"]) as Array).has(Combat.ship_size(String(u[1])))
	var bursts := 3 if mega else 1
	for k in bursts:
		var qk := clampf(q * float(bursts) - float(k) * 0.6, 0.0, 1.0) if mega else q
		if qk <= 0.0 or qk >= 1.0:
			continue
		var c := pos + (Vector2(_h(i, k) - 0.5, _h(i, k + 7) - 0.5) * r * 2.0 if mega else Vector2.ZERO)
		var rr := r * (1.0 + 2.4 * qk) * (1.4 if k == bursts - 1 else 1.0)
		draw_circle(c, rr * 0.55, Color(1.0, 0.95, 0.8, (1.0 - qk) * 0.9))
		draw_circle(c, rr, Color(1.0, 0.55, 0.2, (1.0 - qk) * 0.55))
		draw_arc(c, rr * 1.5, 0.0, TAU, 32, Color(1.0, 0.8, 0.5, (1.0 - qk) * 0.6), 2.0, true)


## Débris d'un vaisseau détruit : éclats qui dérivent et tournent jusqu'à la fin du replay.
func _draw_debris(i: int, pos: Vector2, r: float, dd: int) -> void:
	var counts: Array = GameData.battle_visuals().get("detail", {}).get("debris", [4, 9, 16])
	var n := int(counts[clampi(_detail, 0, counts.size() - 1)])
	var age := maxf(0.0, t - _death_time(dd))
	for k in n:
		var a := _h(i, k) * TAU
		var v := 6.0 + _h(i, k + 31) * 16.0
		var p := pos + Vector2(cos(a), sin(a)) * (r * 0.4 + v * sqrt(age + 0.2))
		var s := r * (0.15 + 0.3 * _h(i, k + 53))
		var rot := age * (_h(i, k + 71) - 0.5) * 3.0 + a
		var shard := PackedVector2Array([p + Vector2(cos(rot), sin(rot)) * s, p + Vector2(cos(rot + 2.3), sin(rot + 2.3)) * s * 0.6,
				p + Vector2(cos(rot + 4.0), sin(rot + 4.0)) * s * 0.8])
		var glow := clampf(1.0 - age / 3.0, 0.0, 1.0)
		draw_colored_polygon(shard, Color(0.3 + 0.6 * glow, 0.28 + 0.25 * glow, 0.26, 0.85))


## Coque endommagée : panaches de fumée qui montent et feux qui vacillent.
func _draw_smoke(i: int, pos: Vector2, r: float, hp_frac: float) -> void:
	var counts: Array = GameData.battle_visuals().get("detail", {}).get("smoke", [0, 4, 8])
	var n := int(counts[clampi(_detail, 0, counts.size() - 1)])
	var heavy := hp_frac < 0.25
	for k in n:
		var phase := fposmod(t * 0.6 + _h(i, k), 1.0)
		var origin := pos + Vector2((_h(i, k + 3) - 0.5) * r * 1.6, (_h(i, k + 5) - 0.5) * r * 0.8)
		var p := origin + Vector2(-8.0, -22.0) * phase
		draw_circle(p, r * (0.2 + 0.5 * phase), Color(0.22, 0.22, 0.24, (1.0 - phase) * (0.55 if heavy else 0.35)))
	var fires := 2 if heavy else 1
	for k in fires:
		var fp := pos + Vector2((_h(i, k + 11) - 0.5) * r * 1.4, (_h(i, k + 13) - 0.5) * r * 0.6)
		var fl := 0.6 + 0.4 * sin(t * 17.0 + float(k) * 2.1 + float(i))
		draw_circle(fp, r * 0.16 * fl + 1.0, Color(1.0, 0.6, 0.2, 0.9))
		draw_circle(fp, r * 0.3 * fl + 1.5, Color(1.0, 0.35, 0.1, 0.35))


# --- Sprites éclairés --------------------------------------------------------------------------

func _clear_sprites() -> void:
	for s in _sprites.values():
		(s as Node).queue_free()
	_sprites.clear()


func _build_sprites() -> void:
	_clear_sprites()
	var units: Array = report["units"]
	for i in units.size():
		var u: Array = units[i]
		var e := _state.get_empire(int(u[0])) if _state else null
		if e == null:
			continue
		var tex := ShipArt.lit_texture(e.faction_id, String(u[1]), e.color())
		if tex == null:
			# Pas de sprite pré-rendu : silhouette dessinée selon la coque et le style du peuple (prop. 14).
			tex = HullArt.lit_texture(SpeciesLook.hull_style(e.faction_id), String(u[1]), e.color())
		var sp := Sprite2D.new()
		sp.texture = tex
		sp.material = _lit
		sp.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_ships.add_child(sp)
		_sprites[i] = sp
	_update_scene()


## Caméra qui dérive doucement (parallaxe), lumière de l'étoile et sprites à leur place.
func _update_scene() -> void:
	if report.is_empty() or backdrop == null:
		return
	_maneuver()
	backdrop.cam = Vector2(sin(t * 0.21) * 36.0, cos(t * 0.15) * 16.0)
	backdrop.time = t
	var to_star := backdrop.star_pos - size * 0.5
	var ld := Vector3(to_star.x, to_star.y, 0.0).normalized()
	ld.z = 0.65
	_lit.set_shader_parameter("light_dir", ld)
	var d := current_day()
	var frac := clampf((t - d * DAY_SECONDS) / DAY_SECONDS, 0.0, 1.0)
	var log: Array = report["log"]
	var today := int(log[d]["day"]) if d < log.size() else 0
	for i in _sprites:
		var sp: Sprite2D = _sprites[i]
		var u: Array = report["units"][i]
		var r := float(SIZE_PX.get(Combat.ship_size(String(u[1])), 10.0))
		var dir := 1.0 if _on_left(int(u[0])) else -1.0
		var long := r * SPRITE_SCALE
		var k := long / float(sp.texture.get_width())
		var dd := int(_dead_day[i])
		var dead := dd >= 0 and (dd < d or (dd == d and frac > 0.85))
		sp.visible = int(u[3]) <= today
		sp.position = _pos[i] if i < _pos.size() and _pos[i] != null else Vector2.ZERO
		if dead:
			# Carcasse : assombrie, elle dérive et tourne lentement.
			var age := maxf(0.0, t - _death_time(dd))
			sp.position += Vector2(_h(i, 1) - 0.5, _h(i, 2) - 0.5) * age * 8.0
			sp.rotation = (_h(i, 3) - 0.5) * age * 0.25
			sp.modulate = Color(0.3, 0.28, 0.28, 0.55)
		else:
			sp.rotation = 0.0
			sp.modulate = Color.WHITE
		sp.scale = Vector2(k * dir, k)


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
		"singularity":
			var sc := a.lerp(b, p)
			draw_circle(sc, 5.0, Color(0.02, 0.0, 0.05))
			draw_arc(sc, 7.0 + sin(p * 20.0) * 1.5, 0.0, TAU, 20, col, 2.0, true)
		"martyr":
			draw_circle(a.lerp(b, p), 6.0, col)
		_:
			draw_circle(a.lerp(b, p), 2.0, col)


## Impact : bulle de bouclier si la cible en a un, sinon gerbe d'étincelles sur le blindage.
func _draw_impact(target: int, at: Vector2, q: float, k: int) -> void:
	var u: Array = report["units"][target]
	var r := float(SIZE_PX.get(Combat.ship_size(String(u[1])), 10.0))
	var q2 := clampf(q, 0.0, 1.0)
	if int(GameData.ship(String(u[1])).get("shield", 0)) >= int(_fx().get("shield_min", 1)):
		var c := Color(0.45, 0.8, 1.0, 0.55 * (1.0 - q2))
		draw_arc(at, r * 2.0, 0.0, TAU, 40, c, 2.5, true)
		draw_circle(at, r * 2.0, Color(0.45, 0.8, 1.0, 0.12 * (1.0 - q2)))
		return
	for j in 5:
		var a := _h(target * 31 + k, j) * TAU
		var p0 := at + Vector2(cos(a), sin(a)) * r * 0.3
		draw_line(p0, p0 + Vector2(cos(a), sin(a)) * (4.0 + 10.0 * q2), Color(1.0, 0.85, 0.5, 1.0 - q2), 1.3)


static func _bezier(a: Vector2, b: Vector2, bend: Vector2, q: float) -> Vector2:
	var c := (a + b) * 0.5 + bend
	return a.lerp(c, q).lerp(c.lerp(b, q), q)


# --- Lot 3 : manœuvres, essaims, son ------------------------------------------------------------

## Tactique d'un camp (gauche ou droite) relevée par la bataille ; "equilibre" pour un ancien rapport.
func side_tactic(left: bool) -> String:
	for sd: Dictionary in report.get("sides", []):
		if _on_left(int(sd["empire"])) == left and sd.has("tac"):
			return String(sd["tac"])
	return "equilibre"


## Avance d'un camp vers le centre (pixels) à l'instant tt : la phase du jour, lissée au changement,
## multipliée par la tactique (prop. 13).
func advance_at(left: bool, tt: float) -> float:
	var mv: Dictionary = GameData.battle_visuals().get("maneuvers", {})
	var adv: Array = mv.get("advance", [0, 45, 90])
	var log: Array = report.get("log", [])
	if log.is_empty():
		return 0.0
	var d := clampi(int(tt / DAY_SECONDS), 0, log.size() - 1)
	var frac := clampf((tt - d * DAY_SECONDS) / DAY_SECONDS, 0.0, 1.0)
	var ph := clampi(int(log[d].get("phase", 0)), 0, adv.size() - 1)
	var prev := clampi(int(log[maxi(0, d - 1)].get("phase", 0)), 0, adv.size() - 1)
	var a := lerpf(float(adv[prev]), float(adv[ph]), smoothstep(0.0, 0.35, frac))
	var tac := side_tactic(left)
	var k := float(mv.get("tactics", {}).get(tac, 0.6))
	if tac == "adaptatif":
		k = [0.3, 0.75, 1.0][ph]
	return a * k


## Positions du moment : repos + avance selon la phase et la tactique, rangs serrés en Rempart,
## léger tangage. Un vaisseau détruit reste où il est mort ; la vue tactique garde le rangement.
func _maneuver() -> void:
	if _base_pos.size() != _pos.size():
		return
	var units: Array = report.get("units", [])
	if tactical:
		for i in _base_pos.size():
			_pos[i] = _base_pos[i]
		return
	var mv: Dictionary = GameData.battle_visuals().get("maneuvers", {})
	var sway := float(mv.get("sway", 5.0))
	var h := size.y if size.y > 0 else 900.0
	var cy := (200.0 + h - 150.0) * 0.5
	for i in _base_pos.size():
		if _base_pos[i] == null:
			continue
		var left := _on_left(int(units[i][0]))
		var tt := t
		var dd := int(_dead_day[i]) if i < _dead_day.size() else -1
		if dd >= 0:
			tt = minf(t, _death_time(dd))
		var k := 0.5 if String(units[i][2]) == "rear" else 1.0
		var base: Vector2 = _base_pos[i]
		var sq := float(mv.get("squeeze", {}).get(side_tactic(left), 1.0))
		var p := Vector2(base.x + (1.0 if left else -1.0) * advance_at(left, tt) * k, cy + (base.y - cy) * sq)
		p += Vector2(sin(tt * 0.9 + _h(i, 41) * TAU), cos(tt * 0.7 + _h(i, 43) * TAU)) * sway
		# Les deux flottes ne se traversent jamais : chacune garde sa moitié de l'arène.
		var mid := (size.x if size.x > 0 else 1600.0) * 0.5
		p.x = minf(p.x, maxf(base.x, mid - 40.0)) if left else maxf(p.x, minf(base.x, mid + 40.0))
		_pos[i] = p


## Essaims de chasseurs autour des porteurs (prop. 17) : ils orbitent, et plongent vers la cible les
## jours où le porteur lance ses chasseurs. Rien ne décolle si le terrain les cloue au hangar.
func _draw_swarms(d: int, frac: float) -> void:
	if _no_fighters or _carriers.is_empty():
		return
	var sw: Dictionary = GameData.battle_visuals().get("swarms", {})
	var orbit: Array = sw.get("orbit", [1.6, 2.6])
	var log: Array = report["log"]
	var day: Dictionary = log[d] if d < log.size() else {}
	var today := int(day.get("day", 0))
	var strikes := {}
	for sh: Array in day.get("shots", []):
		if String(sh[2]) in ["fighters", "bombers"] and not strikes.has(int(sh[0])):
			strikes[int(sh[0])] = int(sh[1])
	for i in _carriers:
		var u: Array = report["units"][i]
		if int(u[3]) > today:
			continue
		var dd := int(_dead_day[i])
		if dd >= 0 and (dd < d or (dd == d and frac > 0.85)):
			continue
		var e := _state.get_empire(int(u[0])) if _state else null
		var col := (e.color() if e else Color.WHITE).lightened(0.35)
		var r := float(SIZE_PX.get(Combat.ship_size(String(u[1])), 10.0))
		var c: Vector2 = _pos[i]
		var dir := 1.0 if _on_left(int(u[0])) else -1.0
		var tg := int(strikes.get(i, -1))
		for j in int(_carriers[i]):
			var spd := 1.4 + _h(i, j + 90) * 0.8
			var a := t * spd * dir + _h(i, j + 60) * TAU
			var rad := r * lerpf(float(orbit[0]), float(orbit[1]), _h(i, j + 70))
			var p := c + Vector2(cos(a) * rad * 1.3, sin(a) * rad * 0.6)
			var vel := Vector2(-sin(a) * 1.3, cos(a) * 0.6) * dir
			if tg >= 0 and tg < _pos.size():
				# Plongée : départ, passage sur la cible, retour au porteur.
				var q := clampf((frac - 0.08 - 0.05 * _h(i, j)) / 0.6, 0.0, 1.0)
				var arc := sin(q * PI)
				var dest: Vector2 = _pos[tg] + Vector2((_h(i, j + 5) - 0.5) * 30.0, (_h(i, j + 6) - 0.5) * 30.0)
				var np := p.lerp(dest, arc)
				vel = (np - p).normalized() if q < 0.5 else (p - np).normalized()
				if vel == Vector2.ZERO:
					vel = Vector2(dir, 0)
				p = np
			vel = vel.normalized()
			var nrm := vel.orthogonal()
			draw_colored_polygon(PackedVector2Array([p + vel * 4.0, p - vel * 3.0 + nrm * 2.5, p - vel * 3.0 - nrm * 2.5]), col)
			draw_circle(p - vel * 3.5, 1.2, Color(1.0, 0.8, 0.5, 0.8))


## Repères sonores des événements passés entre t0 et t1 (prop. 37) : tirs, impacts, explosions, phases.
func emit_cues(t0: float, t1: float) -> void:
	if sounds == null or t1 <= t0:
		return
	var log: Array = report.get("log", [])
	var d0 := clampi(int(t0 / DAY_SECONDS), 0, maxi(0, log.size() - 1))
	var d1 := clampi(int(t1 / DAY_SECONDS), 0, maxi(0, log.size() - 1))
	for d in range(d0, d1 + 1):
		var day: Dictionary = log[d]
		var ts := d * DAY_SECONDS
		if d > 0 and ts > t0 and ts <= t1 and int(day.get("phase", 0)) != int(log[d - 1].get("phase", 0)):
			sounds.play("phase", size * 0.5)
		var shots: Array = day.get("shots", [])
		var n := shots.size()
		for k in n:
			var sh: Array = shots[k]
			var start := ts + (0.04 + 0.66 * float(k) / float(maxi(1, n))) * DAY_SECONDS
			var a := int(sh[0])
			var b := int(sh[1])
			if a < 0 or b < 0 or a >= _pos.size() or b >= _pos.size():
				continue
			if start > t0 and start <= t1:
				sounds.play("tir_" + String(sh[2]), _pos[a])
			var hit := start + 0.3 * DAY_SECONDS
			if hit > t0 and hit <= t1 and int(sh[3]) > 0:
				var shielded := int(GameData.ship(String(report["units"][b][1])).get("shield", 0)) >= int(_fx().get("shield_min", 1))
				sounds.play("impact_bouclier" if shielded else "impact_coque", _pos[b])
		for kk in day.get("kills", []):
			var ki := int(kk)
			var bt := ts + 0.6 * DAY_SECONDS
			if ki >= 0 and ki < _pos.size() and bt > t0 and bt <= t1:
				var mega := (_fx().get("mega_sizes", ["titan"]) as Array).has(Combat.ship_size(String(report["units"][ki][1])))
				sounds.play("explosion_titan" if mega else "explosion", _pos[ki])
	var end := log.size() * DAY_SECONDS
	if end > t0 and end <= t1:
		sounds.play("fin", size * 0.5)
