class_name ResearchTree
extends Control
## Arbre des technologies d'un empire, dessiné d'un bloc : quatre couloirs (un par domaine) et cinq
## colonnes (une par ère). Chaque technologie est une carte ; un trait la relie à ses prérequis.
## Toutes les technologies du peuple sont visibles dès le début (choix de design).
## Clic : sélectionne la carte (tech_selected). Double-clic : la met en tête de file (tech_activated).
## Il ne modifie jamais l'état : l'écran Recherche transforme les demandes en ordres.

signal tech_selected(tech_id: String)
signal tech_activated(tech_id: String)

const LANE_LABEL := 30.0
const ERA_HEAD := 30.0
const CARD_H := 30.0
const GAP_X := 6.0
const GAP_Y := 5.0
const ERA_GAP := 16.0
const LANE_GAP := 12.0
const MIN_CARD_W := 112.0

var selected := ""
var _state: GameState
var _player := 0
var _cols := 1
var _card_w := 150.0
var _rects := {}
var _lanes: Array[Dictionary] = []
var _hover := ""
var _font: Font
var _bold: Font


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = UiTheme.body_font()
	_bold = UiTheme.numbers_font()


func setup(state: GameState, player: int, width: float) -> void:
	_state = state
	_player = player
	_layout(width)
	queue_redraw()


func refresh() -> void:
	queue_redraw()


## Rectangle d'une carte dans l'arbre (Rect2() si la technologie n'y figure pas), pour les tests.
func card_rect(tech_id: String) -> Rect2:
	return _rects.get(tech_id, Rect2())


func card_ids() -> Array:
	return _rects.keys()


func select(tech_id: String) -> void:
	selected = tech_id
	queue_redraw()
	tech_selected.emit(tech_id)


func _layout(width: float) -> void:
	_rects.clear()
	_lanes.clear()
	var me := _state.get_empire(_player) if _state else null
	if me == null:
		return
	var eras := Research.eras()
	var usable := width - LANE_LABEL - (eras - 1) * ERA_GAP
	_cols = 2 if usable / (eras * 2) - GAP_X >= MIN_CARD_W else 1
	_card_w = maxf(MIN_CARD_W, floorf((usable - eras * (_cols - 1) * GAP_X) / (eras * _cols)))
	var ids := Research.visible_ids(me.faction())
	var y := ERA_HEAD
	for d in Research.domain_ids():
		var cells := {}
		var rows := 1
		for tid in ids:
			var t := Research.tech(tid)
			if String(t["domain"]) != d:
				continue
			var era := int(t["era"])
			if not cells.has(era):
				cells[era] = []
			cells[era].append(tid)
		for era in cells:
			rows = maxi(rows, ceili(float(cells[era].size()) / _cols))
		for era in cells:
			var list: Array = cells[era]
			for i in list.size():
				@warning_ignore("integer_division")
				var r := i / _cols
				var c := i % _cols
				var x: float = LANE_LABEL + (era - 1) * (_cols * _card_w + (_cols - 1) * GAP_X + ERA_GAP) + c * (_card_w + GAP_X)
				_rects[list[i]] = Rect2(x, y + r * (CARD_H + GAP_Y), _card_w, CARD_H)
		var h := rows * (CARD_H + GAP_Y) - GAP_Y
		_lanes.append({"id": d, "y": y, "h": h})
		y += h + LANE_GAP
	custom_minimum_size = Vector2(LANE_LABEL + eras * (_cols * _card_w + (_cols - 1) * GAP_X) + (eras - 1) * ERA_GAP, y)


func _era_x(era: int) -> float:
	return LANE_LABEL + (era - 1) * (_cols * _card_w + (_cols - 1) * GAP_X + ERA_GAP)


func _tech_at(p: Vector2) -> String:
	for tid in _rects:
		if (_rects[tid] as Rect2).has_point(p):
			return tid
	return ""


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var h := _tech_at(event.position)
		if h != _hover:
			_hover = h
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var tid := _tech_at(event.position)
		if tid != "":
			select(tid)
			if event.double_click:
				tech_activated.emit(tid)
			accept_event()


func _get_tooltip(at_position: Vector2) -> String:
	var tid := _tech_at(at_position)
	if tid == "" or _state == null:
		return ""
	var t := Research.tech(tid)
	return "%s\n%s\n%d Savoir" % [String(t.get("label", tid)), String(t.get("text", "")), Research.cost(_state, _player, tid)]


## État d'une carte : "known", "current", "queued", "available", "locked".
func state_of(tid: String) -> String:
	var e := _state.get_empire(_player)
	if e.techs.has(tid):
		return "known"
	if not e.research_queue.is_empty() and e.research_queue[0] == tid:
		return "current"
	if e.research_queue.has(tid):
		return "queued"
	if Research.is_available(_state, _player, tid):
		return "available"
	return "locked"


func _draw() -> void:
	if _state == null or _rects.is_empty():
		return
	var e := _state.get_empire(_player)
	var f := e.faction()
	var eras := Research.eras()
	# Bandeaux des ères, avec l'ère ouverte la plus avancée de chaque domaine.
	for era in range(1, eras + 1):
		var x: float = _era_x(era)
		var w: float = _cols * _card_w + (_cols - 1) * GAP_X
		var label := "ÈRE %s" % ["I", "II", "III", "IV", "V"][era - 1]
		var sw := _bold.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		draw_string(_bold, Vector2(x + (w - sw) * 0.5, 16), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(UiTheme.TEXT, 0.75))
		draw_line(Vector2(x, 23), Vector2(x + w, 23), Color(1, 1, 1, 0.16), 1.0)
	for lane in _lanes:
		var dom := Research.domain(String(lane["id"]))
		var col := Color.html(String(dom.get("color", "#ffffff")))
		var y0 := float(lane["y"])
		var h := float(lane["h"])
		draw_rect(Rect2(0, y0 - 4, size.x, h + 8), Color(col, 0.045))
		draw_rect(Rect2(0, y0 - 4, 3, h + 8), Color(col, 0.8))
		# Libellé vertical du domaine.
		var txt := String(dom.get("label", lane["id"])).to_upper()
		var tw := _bold.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		draw_set_transform(Vector2(20, y0 + h * 0.5 + tw * 0.5), -PI * 0.5)
		draw_string(_bold, Vector2.ZERO, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(col, 0.95))
		draw_set_transform(Vector2.ZERO)
		# Ères fermées dans ce domaine : voile sombre.
		for era in range(2, eras + 1):
			if not Research.era_open(e.techs, String(lane["id"]), era):
				var x: float = _era_x(era) - 3
				draw_rect(Rect2(x, y0 - 3, size.x - x, h + 6), Color(0, 0, 0, 0.22))
				break
	# Traits des prérequis, sous les cartes.
	for tid in _rects:
		var r: Rect2 = _rects[tid]
		for p in Research.tech(tid).get("pre", []):
			var pid := String(p)
			if not _rects.has(pid):
				pid = Research.replaced_by(f, pid)
			if not _rects.has(pid):
				continue
			var pr: Rect2 = _rects[pid]
			var hot: bool = selected == tid or selected == pid or _hover == tid
			var lc := Color(UiTheme.ACCENT, 0.85) if hot else Color(1, 1, 1, 0.13 if not e.techs.has(pid) else 0.24)
			var a := Vector2(pr.end.x, pr.get_center().y)
			var b := Vector2(r.position.x, r.get_center().y)
			if b.x <= a.x + 2:
				a = Vector2(pr.get_center().x, pr.end.y if pr.position.y < r.position.y else pr.position.y)
				b = Vector2(r.get_center().x, r.position.y if pr.position.y < r.position.y else r.end.y)
				draw_line(a, b, lc, 1.5 if hot else 1.0, true)
			else:
				var mx := (a.x + b.x) * 0.5
				draw_polyline(PackedVector2Array([a, Vector2(mx, a.y), Vector2(mx, b.y), b]), lc, 1.5 if hot else 1.0, true)
	# Cartes.
	for tid in _rects:
		_draw_card(tid, _rects[tid], e, f)


func _draw_card(tid: String, r: Rect2, e: Empire, f: Dictionary) -> void:
	var t := Research.tech(tid)
	var dom := Research.domain(String(t["domain"]))
	var col := Color.html(String(dom.get("color", "#ffffff")))
	var st := state_of(tid)
	var bg := Color(0.05, 0.06, 0.08, 0.92)
	var border := Color(1, 1, 1, 0.12)
	var text_col := Color(UiTheme.TEXT, 0.45)
	match st:
		"known":
			bg = Color(col.darkened(0.55), 0.95)
			border = Color(col, 0.55)
			text_col = UiTheme.TEXT
		"current":
			bg = Color(0.06, 0.1, 0.12, 0.95)
			border = UiTheme.ACCENT
			text_col = UiTheme.TEXT
		"queued":
			border = Color(UiTheme.ACCENT, 0.55)
			text_col = Color(UiTheme.TEXT, 0.9)
		"available":
			border = Color(col, 0.75)
			text_col = Color(UiTheme.TEXT, 0.92)
	if tid == _hover and st != "known":
		bg = bg.lightened(0.06)
	draw_rect(r, bg)
	if st == "current":
		var cost := maxi(1, Research.cost(_state, _player, tid))
		var frac := clampf(float(e.research_progress) / cost, 0.0, 1.0)
		draw_rect(Rect2(r.position, Vector2(r.size.x * frac, r.size.y)), Color(UiTheme.ACCENT, 0.18))
	draw_rect(r, border, false, 2.0 if tid == selected else 1.0)
	if tid == selected:
		draw_rect(r.grow(2), Color(UiTheme.ACCENT, 0.55), false, 1.0)
	# Pastilles : propre au peuple (losange aux couleurs du peuple), hérétique (croix rouge).
	var x: float = r.position.x + 7
	if Research.is_specific(tid):
		var c := Vector2(x + 3, r.get_center().y)
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -4), c + Vector2(4, 0), c + Vector2(0, 4), c + Vector2(-4, 0)]), e.color())
		x += 10
	if Research.is_heretic(f, tid):
		var c := Vector2(x + 3, r.get_center().y)
		draw_line(c + Vector2(-3, -3), c + Vector2(3, 3), UiTheme.BAD, 1.6)
		draw_line(c + Vector2(-3, 3), c + Vector2(3, -3), UiTheme.BAD, 1.6)
		x += 10
	var right: float = r.end.x - 6
	if st == "queued" or st == "current":
		var n := str(e.research_queue.find(tid) + 1)
		var nw := _bold.get_string_size(n, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		draw_circle(Vector2(right - 6, r.get_center().y), 8, Color(UiTheme.ACCENT, 0.85 if st == "current" else 0.35))
		draw_string(_bold, Vector2(right - 6 - nw * 0.5, r.get_center().y + 4), n, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.02, 0.03, 0.05) if st == "current" else UiTheme.TEXT)
		right -= 18
	elif st == "known":
		var c := Vector2(right - 5, r.get_center().y)
		draw_polyline(PackedVector2Array([c + Vector2(-4, 0), c + Vector2(-1, 3), c + Vector2(4, -3)]), Color(col.lightened(0.3), 0.9), 1.6, true)
		right -= 14
	var label := _fit(String(t.get("label", tid)), right - x, 13)
	draw_string(_font, Vector2(x, r.get_center().y + 5), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, text_col)


## Raccourcit un libellé avec « … » pour qu'il tienne dans la largeur.
func _fit(text: String, width: float, fs: int) -> String:
	if _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= width:
		return text
	var s := text
	while s.length() > 1 and _font.get_string_size(s + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > width:
		s = s.substr(0, s.length() - 1)
	return s.strip_edges() + "…"
