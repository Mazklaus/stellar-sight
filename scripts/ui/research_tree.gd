class_name ResearchTree
extends Control
## Arbre des technologies d'un empire, dessiné d'un bloc : un couloir par domaine, la bande Peuple
## dessous (technologies propres sans lien avec l'arbre commun, et la Destinée), une bande Trouvailles
## s'il y en a, et cinq colonnes (une par ère). Dans chaque case, les technologies sont rangées par champ.
## Chaque technologie est une carte avec son médaillon (TechArt) ; un trait la relie à ses prérequis,
## même d'un couloir à l'autre. Les technologies de peuple qui remplacent une technologie commune ou en
## préparent une restent à leur place, avec le liseré du peuple (prop. 6 revue de l'étude de l'arbre).
## L'arbre n'a pas de taille plafond : il défile, et se zoome (Ctrl + molette, ou set_zoom).
## Clic : sélectionne la carte (tech_selected). Double-clic : la met en tête de file (tech_activated).
## Clic droit : planifie le chemin jusqu'à elle (tech_planned).
## Il ne modifie jamais l'état : l'écran Recherche transforme les demandes en ordres.

signal tech_selected(tech_id: String)
signal tech_activated(tech_id: String)
signal tech_planned(tech_id: String)
signal zoom_changed(zoom: float)

const LANE_LABEL := 30.0
const ERA_HEAD := 30.0
const CARD_W := 200.0
const CARD_H := 42.0
const MASTERY_H := 30.0
const GAP_X := 8.0
const GAP_Y := 6.0
const ERA_GAP := 26.0
const LANE_GAP := 14.0
const COLS := 2
const MIN_ZOOM := 0.5
const MAX_ZOOM := 1.6

var selected := ""
## Filtres de l'écran : champ ("" = tous), sorte de déblocage, texte cherché, « Mon peuple ».
var filter := {"field": "", "kind": "", "text": "", "mine": false}
## Chemin planifié (clic droit) : ses liens s'allument.
var path: Array[String] = []
var zoom := 1.0
var _state: GameState
var _player := 0
var _rects := {}
var _lanes: Array[Dictionary] = []
var _hover := ""
var _font: Font
var _bold: Font
var _base_size := Vector2.ZERO
var _match_cache := {}
var _mine := {}


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = UiTheme.body_font()
	_bold = UiTheme.numbers_font()


## width, height : place disponible (gardés pour compatibilité ; l'arbre prend la taille qu'il lui faut).
func setup(state: GameState, player: int, _width := 0.0, _height := 0.0) -> void:
	_state = state
	_player = player
	_layout()
	queue_redraw()


func refresh() -> void:
	_match_cache.clear()
	queue_redraw()


## Rectangle d'une carte dans l'arbre, à l'échelle affichée (Rect2() si elle n'y figure pas).
func card_rect(tech_id: String) -> Rect2:
	var r: Rect2 = _rects.get(tech_id, Rect2())
	return Rect2(r.position * zoom, r.size * zoom)


func card_ids() -> Array:
	return _rects.keys()


func select(tech_id: String) -> void:
	selected = tech_id
	queue_redraw()
	tech_selected.emit(tech_id)


func set_filter(key: String, value: Variant) -> void:
	filter[key] = value
	_match_cache.clear()
	queue_redraw()


func set_path(ids: Array[String]) -> void:
	path = ids
	queue_redraw()


func set_zoom(z: float) -> void:
	zoom = clampf(z, MIN_ZOOM, MAX_ZOOM)
	custom_minimum_size = _base_size * zoom
	queue_redraw()
	zoom_changed.emit(zoom)


## Lignes de rangement : couloirs (domaine, bande Peuple, Trouvailles) et cases par ère.
func _layout() -> void:
	_rects.clear()
	_lanes.clear()
	_match_cache.clear()
	var me := _state.get_empire(_player) if _state else null
	if me == null:
		return
	var f := me.faction()
	var eras := Research.eras()
	var ids := Research.visible_for(_state, _player)
	_mine = _people_web(f, ids)
	var lanes := []
	for d in Research.domain_ids():
		lanes.append({"id": d, "label": String(Research.domain(d).get("label", d)), "color": Color.html(String(Research.domain(d).get("color", "#ffffff"))), "cells": {}})
	var band := {"id": "peuple", "label": String(Research.data().get("band", {}).get("label", "Peuple")), "color": me.color(), "cells": {}}
	var finds := {"id": "trouvailles", "label": "Trouvailles", "color": Color("d9b85c"), "cells": {}}
	for tid in ids:
		var t := Research.tech(tid)
		var lane: Dictionary
		if Research.is_find(tid):
			lane = finds
		elif Research.in_band(f, tid):
			lane = band
		else:
			lane = lanes[maxi(0, Research.domain_ids().find(String(t["domain"])))]
		var era := clampi(int(t.get("era", 1)), 1, eras)
		if not lane["cells"].has(era):
			lane["cells"][era] = []
		lane["cells"][era].append(tid)
	if not band["cells"].is_empty():
		lanes.append(band)
	if not finds["cells"].is_empty():
		lanes.append(finds)
	var y := ERA_HEAD
	for lane: Dictionary in lanes:
		var rows := 1
		var cells: Dictionary = lane["cells"]
		for era in cells:
			cells[era] = _sorted_cell(cells[era])
			@warning_ignore("integer_division")
			rows = maxi(rows, (cells[era].size() + COLS - 1) / COLS)
		for era in cells:
			var list: Array = cells[era]
			for i in list.size():
				@warning_ignore("integer_division")
				var r := i / COLS
				var c := i % COLS
				var x: float = _era_x(era) + c * (CARD_W + GAP_X)
				var h := MASTERY_H if Research.is_mastery(list[i]) else CARD_H
				var dy := (CARD_H - h) * 0.5
				_rects[list[i]] = Rect2(x + (12.0 if h < CARD_H else 0.0), y + r * (CARD_H + GAP_Y) + dy, CARD_W - (12.0 if h < CARD_H else 0.0), h)
		var hh := rows * (CARD_H + GAP_Y) - GAP_Y
		_lanes.append({"id": lane["id"], "label": lane["label"], "color": lane["color"], "y": y, "h": hh})
		y += hh + LANE_GAP
	_base_size = Vector2(LANE_LABEL + eras * (COLS * CARD_W + (COLS - 1) * GAP_X) + (eras - 1) * ERA_GAP + 8.0, y)
	custom_minimum_size = _base_size * zoom


## Une case : par champ (ordre du domaine), puis dans l'ordre des données ; chaque Maîtrise suit sa parente.
func _sorted_cell(list: Array) -> Array:
	var order := {}
	for d in Research.domain_ids():
		var i := 0
		for fd: Dictionary in Research.domain(d).get("fields", []):
			order[String(fd["id"])] = i
			i += 1
	var main_ids: Array = []
	var mast := {}
	for tid in list:
		var m := String(Research.tech(tid).get("mastery", ""))
		if m != "" and list.has(m):
			if not mast.has(m):
				mast[m] = []
			mast[m].append(tid)
		else:
			main_ids.append(tid)
	var keyed: Array = []
	for i in main_ids.size():
		keyed.append([int(order.get(Research.field_of(main_ids[i]), 9)), i, main_ids[i]])
	keyed.sort()
	var out: Array = []
	for k in keyed:
		out.append(k[2])
		for m in mast.get(k[2], []):
			out.append(m)
	return out


## « Mon peuple » : ses technologies propres, leurs prérequis et ce qu'elles ouvrent.
func _people_web(_f: Dictionary, ids: Array[String]) -> Dictionary:
	var web := {}
	for tid in ids:
		if Research.is_specific(tid) or Research.tech(tid).has("victory"):
			web[tid] = true
	var todo: Array = web.keys()
	while not todo.is_empty():
		var t := String(todo.pop_back())
		for p in Research.tech(t).get("pre", []):
			if not web.has(String(p)) and ids.has(String(p)):
				web[String(p)] = true
				todo.append(String(p))
	for tid in ids:
		for p in Research.tech(tid).get("pre", []):
			if Research.is_specific(String(p)):
				web[tid] = true
	return web


func _era_x(era: int) -> float:
	return LANE_LABEL + (era - 1) * (COLS * CARD_W + (COLS - 1) * GAP_X + ERA_GAP)


func _tech_at(p: Vector2) -> String:
	var q := p / zoom
	for tid in _rects:
		if (_rects[tid] as Rect2).has_point(q):
			return tid
	return ""


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var h := _tech_at(event.position)
		if h != _hover:
			_hover = h
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed:
		if event.ctrl_pressed and (event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			set_zoom(zoom * (1.1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.1))
			accept_event()
			return
		var tid := _tech_at(event.position)
		if tid == "":
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			select(tid)
			if event.double_click:
				tech_activated.emit(tid)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			select(tid)
			tech_planned.emit(tid)
			accept_event()


## Centre du losange de palier d'une ère dans un couloir de domaine (coin haut gauche de la colonne).
func _tier_center(lane: Dictionary, era: int) -> Vector2:
	return Vector2(_era_x(era) - ERA_GAP * 0.5, float(lane["y"]) + 4.0)


## Infobulle d'un palier d'ère sous le pointeur ("" sinon).
func _tier_tooltip(at_position: Vector2) -> String:
	var p := at_position / zoom
	for lane in _lanes:
		if not Research.domain_ids().has(String(lane["id"])):
			continue
		for era in range(2, Research.eras() + 1):
			var tr := Research.tier(String(lane["id"]), era)
			if tr.is_empty() or p.distance_to(_tier_center(lane, era)) > 9.0:
				continue
			var e := _state.get_empire(_player)
			var open := Research.era_open(e.techs, String(lane["id"]), era, e.faction(), _state, _player)
			return "Palier de l'ère %s (%s) : %s\n%s\n%s" % [["I", "II", "III", "IV", "V"][era - 1], String(lane["label"]),
					String(tr.get("label", "")), String(tr.get("text", "")),
					"Acquis : l'ère est ouverte." if open else "Gratuit dès que l'ère s'ouvre dans ce domaine."]
	return ""


func _get_tooltip(at_position: Vector2) -> String:
	var tid := _tech_at(at_position)
	if tid == "" and _state != null:
		return _tier_tooltip(at_position)
	if tid == "" or _state == null:
		return ""
	var t := Research.tech(tid)
	var f := _state.get_empire(_player).faction()
	var lines := PackedStringArray([String(t.get("label", tid)), String(t.get("text", ""))])
	var un := Research.unlocks(f, tid)
	if not un.is_empty():
		lines.append("Débloque : %s" % ", ".join(un))
	if Research.is_mastery(tid):
		lines.append("Maîtrise facultative : jamais prérequise, elle ne compte pas pour ouvrir l'ère suivante.")
	if Research.is_dangerous(tid):
		lines.append("Dangereuse : %s" % Research.danger_text(tid))
	lines.append("%d Savoir  ·  clic droit : planifier le chemin" % Research.cost(_state, _player, tid))
	return "\n".join(lines)


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


## La carte passe-t-elle les filtres de l'écran ?
func matches(tid: String) -> bool:
	if _match_cache.has(tid):
		return _match_cache[tid]
	var ok := true
	var fld := String(filter.get("field", ""))
	if fld != "" and Research.field_of(tid) != fld:
		ok = false
	var kind := String(filter.get("kind", ""))
	if ok and kind != "" and not Research.unlock_kinds(_state.get_empire(_player).faction(), tid).has(kind):
		ok = false
	var txt := String(filter.get("text", "")).strip_edges().to_lower()
	if ok and txt != "":
		var t := Research.tech(tid)
		ok = String(t.get("label", "")).to_lower().contains(txt) or String(t.get("text", "")).to_lower().contains(txt)
	if ok and bool(filter.get("mine", false)) and not _mine.has(tid):
		ok = false
	_match_cache[tid] = ok
	return ok


func _filtering() -> bool:
	return String(filter.get("field", "")) != "" or String(filter.get("kind", "")) != "" \
			or String(filter.get("text", "")).strip_edges() != "" or bool(filter.get("mine", false))


func _draw() -> void:
	if _state == null or _rects.is_empty():
		return
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(zoom, zoom))
	var e := _state.get_empire(_player)
	var f := e.faction()
	var eras := Research.eras()
	var width := _base_size.x
	# Bandeaux des ères.
	for era in range(1, eras + 1):
		var x: float = _era_x(era)
		var w: float = COLS * CARD_W + (COLS - 1) * GAP_X
		var label := "ÈRE %s" % ["I", "II", "III", "IV", "V"][era - 1]
		var sw := _bold.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		draw_string(_bold, Vector2(x + (w - sw) * 0.5, 16), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(UiTheme.TEXT, 0.75))
		draw_line(Vector2(x, 23), Vector2(x + w, 23), Color(1, 1, 1, 0.16), 1.0)
	for lane in _lanes:
		var col: Color = lane["color"]
		var y0 := float(lane["y"])
		var h := float(lane["h"])
		draw_rect(Rect2(0, y0 - 5, width, h + 10), Color(col, 0.045))
		draw_rect(Rect2(0, y0 - 5, 3, h + 10), Color(col, 0.8))
		var txt := String(lane["label"]).to_upper()
		var tw := _bold.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		draw_set_transform(Vector2(20, y0 + h * 0.5 + tw * 0.5) * zoom, -PI * 0.5, Vector2(zoom, zoom))
		draw_string(_bold, Vector2.ZERO, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(col, 0.95))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(zoom, zoom))
		# Paliers d'ère (prop. 4) : un losange en tête de chaque ère du domaine, doré une fois l'ère ouverte.
		if Research.domain_ids().has(String(lane["id"])):
			for era in range(2, eras + 1):
				if not Research.tier(String(lane["id"]), era).is_empty():
					var tc := _tier_center(lane, era)
					var open := Research.era_open(e.techs, String(lane["id"]), era, f, _state, _player)
					var pts := PackedVector2Array([tc + Vector2(0, -5), tc + Vector2(5, 0), tc + Vector2(0, 5), tc + Vector2(-5, 0)])
					draw_colored_polygon(pts, Color("d9b85c") if open else Color(1, 1, 1, 0.25))
		# Ères fermées dans ce domaine : voile sombre.
		if Research.domain_ids().has(String(lane["id"])):
			for era in range(2, eras + 1):
				if not Research.era_open(e.techs, String(lane["id"]), era, f, _state, _player):
					var x: float = _era_x(era) - 4
					draw_rect(Rect2(x, y0 - 4, width - x, h + 8), Color(0, 0, 0, 0.22))
					break
	var filtering := _filtering()
	var on_path := {}
	for p in path:
		on_path[p] = true
	# Traits des prérequis, sous les cartes (d'un couloir à l'autre aussi).
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
			var lit: bool = on_path.has(tid) and (on_path.has(pid) or e.techs.has(pid))
			var lc := Color(UiTheme.ACCENT, 0.85) if hot else Color(1, 1, 1, 0.13 if not e.techs.has(pid) else 0.24)
			if lit:
				lc = Color("d9b85c")
			elif filtering and not (matches(tid) and matches(pid)):
				lc.a *= 0.35
			var wid := 1.8 if hot or lit else 1.0
			var a := Vector2(pr.end.x, pr.get_center().y)
			var b := Vector2(r.position.x, r.get_center().y)
			if b.x <= a.x + 2:
				a = Vector2(pr.get_center().x, pr.end.y if pr.position.y < r.position.y else pr.position.y)
				b = Vector2(r.get_center().x, r.position.y if pr.position.y < r.position.y else r.end.y)
				draw_line(a, b, lc, wid, true)
			else:
				var mx := (a.x + b.x) * 0.5
				draw_polyline(PackedVector2Array([a, Vector2(mx, a.y), Vector2(mx, b.y), b]), lc, wid, true)
	for tid in _rects:
		_draw_card(tid, _rects[tid], e, f, filtering and not matches(tid), on_path.has(tid))


func _draw_card(tid: String, r: Rect2, e: Empire, f: Dictionary, dim: bool, planned: bool) -> void:
	var t := Research.tech(tid)
	var col := TechArt.domain_color(tid)
	var st := state_of(tid)
	var mastery := Research.is_mastery(tid)
	var people := Research.is_specific(tid) or t.has("victory")
	var bg := Color(0.05, 0.06, 0.08, 0.92)
	var border := Color(1, 1, 1, 0.12)
	var text_col := Color(UiTheme.TEXT, 0.5)
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
	if people and st != "current" and st != "queued":
		border = Color(e.color(), 0.85)  # liseré du peuple
	if planned and st != "known":
		border = Color("d9b85c")
	if tid == _hover and st != "known":
		bg = bg.lightened(0.06)
	if dim:
		bg.a *= 0.45
		border.a *= 0.35
		text_col.a *= 0.4
	draw_rect(r, bg)
	if st == "current":
		var cost := maxi(1, Research.cost(_state, _player, tid))
		var frac := clampf(float(e.research_progress) / cost, 0.0, 1.0)
		draw_rect(Rect2(r.position, Vector2(r.size.x * frac, r.size.y)), Color(UiTheme.ACCENT, 0.18))
	elif st != "known" and e.research_shelf.has(tid):
		# Savoir déjà acquis (épaves, eurêka, recherche interrompue) : un trait sous la carte.
		var cost := maxi(1, Research.cost(_state, _player, tid))
		var frac := clampf(float(e.research_shelf[tid]) / cost, 0.0, 1.0)
		draw_rect(Rect2(r.position.x, r.end.y - 3, r.size.x * frac, 3), Color(0.85, 0.72, 0.36, 0.8))
	if Research.is_find(tid):
		_dashed_rect(r, border)
	else:
		draw_rect(r, border, false, 2.0 if tid == selected or people else 1.0)
	if tid == selected:
		draw_rect(r.grow(2), Color(UiTheme.ACCENT, 0.55), false, 1.0)
	# Médaillon (prop. 112) : miniature cerclée du domaine, crans d'ère, liseré du peuple.
	var mr := r.size.y * 0.5 - 4.0
	var mc := Vector2(r.position.x + 4.0 + mr, r.get_center().y)
	TechArt.draw_medallion(self, mc, mr, tid, f, e.color() if people else Color(0, 0, 0, 0), dim or st == "locked")
	var x: float = mc.x + mr + 7.0
	var right: float = r.end.x - 6
	if st == "queued" or st == "current":
		var n := str(e.research_queue.find(tid) + 1)
		var nw := _bold.get_string_size(n, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		draw_circle(Vector2(right - 6, r.position.y + 12), 8, Color(UiTheme.ACCENT, 0.85 if st == "current" else 0.35))
		draw_string(_bold, Vector2(right - 6 - nw * 0.5, r.position.y + 16), n, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.02, 0.03, 0.05) if st == "current" else UiTheme.TEXT)
		right -= 18
	elif st == "known":
		var c := Vector2(right - 5, r.position.y + 12)
		draw_polyline(PackedVector2Array([c + Vector2(-4, 0), c + Vector2(-1, 3), c + Vector2(4, -3)]), Color(col.lightened(0.3), 0.9), 1.6, true)
		right -= 14
	var fs := 12 if mastery else 13
	var label := _fit(String(t.get("label", tid)), right - x, fs)
	var ly := r.position.y + (r.size.y * 0.5 + 5.0 if mastery else 17.0)
	draw_string(_font, Vector2(x, ly), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, text_col)
	if mastery:
		return
	# Seconde ligne : pastilles (hérétique, spécialisation, dangereuse, eurêka) puis icônes de déblocage.
	var y2 := r.end.y - 11.0
	var mx := x + 3.0
	if Research.is_heretic(f, tid):
		draw_line(Vector2(mx - 3, y2 - 3), Vector2(mx + 3, y2 + 3), UiTheme.BAD, 1.6)
		draw_line(Vector2(mx - 3, y2 + 3), Vector2(mx + 3, y2 - 3), UiTheme.BAD, 1.6)
		mx += 11
	if Research.spec_group(tid) != "":
		# Spécialisation : un petit écu ; barré quand une autre branche a été choisie.
		var c := Vector2(mx, y2)
		var shield := PackedVector2Array([c + Vector2(-4, -4), c + Vector2(4, -4), c + Vector2(4, 0), c + Vector2(0, 5), c + Vector2(-4, 0), c + Vector2(-4, -4)])
		draw_polyline(shield, Color(UiTheme.ACCENT, 0.9), 1.3, true)
		if Research.spec_taken(e.techs, tid) != "" and st != "known":
			draw_line(c + Vector2(-5, 5), c + Vector2(5, -5), UiTheme.BAD, 1.4)
		mx += 12
	if Research.is_dangerous(tid):
		var c := Vector2(mx, y2)
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -5), c + Vector2(5, 4), c + Vector2(-5, 4)]), Color(UiTheme.BAD, 0.9))
		mx += 12
	if t.has("eureka") and st != "known":
		var c := Vector2(mx, y2)
		if e.eurekas.has(tid):
			draw_circle(c, 3.2, Color(0.85, 0.72, 0.36))
		else:
			draw_arc(c, 3.2, 0, TAU, 12, Color(0.85, 0.72, 0.36, 0.8), 1.2, true)
		mx += 10
	var ix := r.end.x - 10.0
	var kinds := Research.unlock_kinds(f, tid)
	kinds.reverse()
	for k in kinds:
		if ix < mx + 8:
			break
		_unlock_icon(Vector2(ix, y2), String(k), Color(col.lightened(0.35), text_col.a))
		ix -= 13.0
	var fl := Research.field_label(String(t.get("domain", "")), Research.field_of(tid))
	if fl != "" and ix - mx > 30:
		draw_string(_font, Vector2(mx, y2 + 4), _fit(fl, ix - mx - 4, 10), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(UiTheme.TEXT_DIM, 0.8 * text_col.a))


## Petite icône d'une sorte de déblocage (prop. 106).
func _unlock_icon(c: Vector2, kind: String, col: Color) -> void:
	match kind:
		"batiment":
			draw_colored_polygon(PackedVector2Array([c + Vector2(-4, 4), c + Vector2(-4, -1), c + Vector2(0, -5), c + Vector2(4, -1), c + Vector2(4, 4)]), col)
		"vaisseau", "coque":
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -5), c + Vector2(4, 4), c + Vector2(0, 2), c + Vector2(-4, 4)]), col)
		"module":
			draw_arc(c, 3.5, 0, TAU, 12, col, 1.6, true)
			draw_circle(c, 1.2, col)
		"regiment":
			draw_polyline(PackedVector2Array([c + Vector2(-4, 1), c + Vector2(0, -3), c + Vector2(4, 1)]), col, 1.8, true)
			draw_polyline(PackedVector2Array([c + Vector2(-4, 5), c + Vector2(0, 1), c + Vector2(4, 5)]), col, 1.8, true)
		"mega", "merveille", "forge":
			draw_arc(c, 4.5, 0, TAU, 14, col, 1.3, true)
			draw_circle(c, 1.6, col)
		"maitrise":
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -5), c + Vector2(1.5, -1.5), c + Vector2(5, 0), c + Vector2(1.5, 1.5),
					c + Vector2(0, 5), c + Vector2(-1.5, 1.5), c + Vector2(-5, 0), c + Vector2(-1.5, -1.5)]), col)
		"tactique":
			# deux flèches croisées
			draw_line(c + Vector2(-4, 4), c + Vector2(4, -4), col, 1.5, true)
			draw_line(c + Vector2(4, 4), c + Vector2(-4, -4), col, 1.5, true)
			draw_colored_polygon(PackedVector2Array([c + Vector2(4, -4), c + Vector2(1, -4), c + Vector2(4, -1)]), col)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-4, -4), c + Vector2(-1, -4), c + Vector2(-4, -1)]), col)
		"projet":
			draw_rect(Rect2(c - Vector2(4, 4), Vector2(8, 8)), col, false, 1.4)
			draw_line(c + Vector2(-2, 0), c + Vector2(2, 0), col, 1.4)
			draw_line(c + Vector2(0, -2), c + Vector2(0, 2), col, 1.4)
		"loi":
			draw_rect(Rect2(c + Vector2(-3.5, -4.5), Vector2(7, 9)), col, false, 1.3)
			draw_line(c + Vector2(-1.8, -1.5), c + Vector2(1.8, -1.5), col, 1.0)
			draw_line(c + Vector2(-1.8, 1), c + Vector2(1.8, 1), col, 1.0)
		_:
			draw_circle(c, 2.2, Color(col, col.a * 0.7))


func _dashed_rect(r: Rect2, col: Color) -> void:
	var pts := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), r.position]
	for i in 4:
		draw_dashed_line(pts[i], pts[i + 1], col, 1.2, 5.0)


## Raccourcit un libellé avec « … » pour qu'il tienne dans la largeur.
func _fit(text: String, width: float, fs: int) -> String:
	if _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= width:
		return text
	var s := text
	while s.length() > 1 and _font.get_string_size(s + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > width:
		s = s.substr(0, s.length() - 1)
	return s.strip_edges() + "…"
