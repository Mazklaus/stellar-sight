class_name AnnounceUi
extends RefCounted
## Onglets « Annonces » et « Heures » de l'écran Chroniques (étude de la fenêtre d'événement, prop. 39
## et 40) : le registre des annonces typées, filtrable par famille, gravité et « me concerne », avec
## « Rouvrir » (la fenêtre commune) et « Lieu » ; puis la frise des grandes heures de l'empire (ses
## Fanfares et ses premières de la galaxie), du premier jour à aujourd'hui.

const LIST_MAX := 120


static func viewer_of(es: EmpireScreens) -> int:
	return -1 if es.see_all else es._player


static func build(es: EmpireScreens, col: VBoxContainer) -> void:
	var state := es._state
	var viewer := viewer_of(es)
	var f: Dictionary = es.announce_filter
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 14)
	col.add_child(bar)
	var fam := OptionButton.new()
	fam.focus_mode = Control.FOCUS_NONE
	fam.add_item("Toutes les familles")
	var fams := Announce.family_ids()
	for id in fams:
		fam.add_item(String(Announce.family_def(id).get("label", id)))
	fam.select(fams.find(String(f.get("family", ""))) + 1)
	fam.item_selected.connect(func(i: int) -> void:
		f["family"] = "" if i == 0 else fams[i - 1]
		es.show_screen("chronicles"))
	bar.add_child(fam)
	es.chronicle_buttons["ann:family"] = fam
	var grav := OptionButton.new()
	grav.focus_mode = Control.FOCUS_NONE
	for t in ["Toutes", "Avis et plus", "Fenêtres et plus", "Fanfares"]:
		grav.add_item(t)
	grav.select(int(f.get("gravity", 0)))
	grav.item_selected.connect(func(i: int) -> void:
		f["gravity"] = i
		es.show_screen("chronicles"))
	bar.add_child(grav)
	es.chronicle_buttons["ann:gravity"] = grav
	var mine := CheckBox.new()
	mine.text = "Me concerne"
	mine.focus_mode = Control.FOCUS_NONE
	mine.disabled = viewer < 0
	mine.set_pressed_no_signal(bool(f.get("mine", false)))
	mine.toggled.connect(func(on: bool) -> void:
		f["mine"] = on
		es.show_screen("chronicles"))
	bar.add_child(mine)
	es.chronicle_buttons["ann:mine"] = mine

	var block := Widgets.Block.new("Annonces")
	col.add_child(block)
	var shown := 0
	for rec in Announce.readable(state, viewer):
		if not _passes(state, rec, viewer, f):
			continue
		block.body.add_child(_row(es, rec, viewer))
		shown += 1
		if shown >= LIST_MAX:
			block.body.add_child(UiTheme.dim("Les plus anciennes sont plus bas dans le registre : affinez les filtres.", 13))
			break
	if shown == 0:
		block.body.add_child(UiTheme.dim("Aucune annonce ne répond à ces filtres." if not state.announces.is_empty()
				else "Le chroniqueur n'a encore rien annoncé.", 14))


static func _passes(state: GameState, rec: Dictionary, viewer: int, f: Dictionary) -> bool:
	if String(f.get("family", "")) != "" and Announce.family_of(String(rec["k"])) != String(f["family"]):
		return false
	var need_g := int(f.get("gravity", 0))
	if need_g > 0:
		var g := AnnounceSettings.final_gravity(state, rec, viewer)
		if g < need_g:
			return false
	if bool(f.get("mine", false)) and viewer >= 0 and not Announce.involved(rec).has(viewer):
		return false
	return true


static func _row(es: EmpireScreens, rec: Dictionary, viewer: int) -> Control:
	var state := es._state
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var glyph := Glyph.new()
	glyph.family = Announce.family_of(String(rec["k"]))
	glyph.fill = Announce.need_color(Announce.need(rec, viewer))
	row.add_child(glyph)
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 0)
	row.add_child(mid)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	mid.add_child(head)
	head.add_child(UiTheme.dim(GameCalendar.date_string(int(rec["t"])), 13))
	var t := UiTheme.title(Announce.title(state, rec), 17)
	head.add_child(t)
	if int(rec.get("f", 0)) > 0:
		var fl := UiTheme.dim("PREMIÈRE DE LA GALAXIE", 11)
		fl.add_theme_color_override("font_color", UiTheme.WARN)
		head.add_child(fl)
	var txt := UiTheme.paragraph(String(rec["x"]), 640.0, 14)
	txt.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	mid.add_child(txt)
	var aid := int(rec["id"])
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.text = "Rouvrir"
	b.pressed.connect(func() -> void: es.announce_requested.emit(aid))
	es.chronicle_buttons["ann:%d" % aid] = b
	row.add_child(b)
	var sid := Announce.system_of(state, rec)
	if sid >= 0:
		var lb := Button.new()
		lb.focus_mode = Control.FOCUS_NONE
		lb.text = "Lieu"
		lb.pressed.connect(func() -> void: es.announce_locate_requested.emit(sid))
		row.add_child(lb)
	return row


## Onglet « Heures » : frise des grandes heures de l'empire.
static func build_hours(es: EmpireScreens, col: VBoxContainer) -> void:
	var state := es._state
	var viewer := viewer_of(es)
	var hours := Announce.hours(state, viewer)
	var frise := Frise.new()
	frise.state = state
	frise.hours = hours
	frise.viewer = viewer
	col.add_child(frise)
	es.chronicle_buttons["hours:frise"] = frise
	var block := Widgets.Block.new("Les Heures de l'empire" if viewer >= 0 else "Les Heures de la galaxie")
	col.add_child(block)
	if hours.is_empty():
		block.body.add_child(UiTheme.dim("Pas encore de grande heure. Les Fanfares et les premières de la galaxie s'inscriront ici.", 14))
	for i in range(hours.size() - 1, -1, -1):
		block.body.add_child(_row(es, hours[i], viewer))


static func signature(es: EmpireScreens) -> String:
	return "%d|%s" % [Announce.last_id(es._state), str(es.announce_filter)]


## Petit glyphe de famille dans un rond de la couleur du besoin.
class Glyph:
	extends Control
	var family := ""
	var fill := UiTheme.ACCENT

	func _init() -> void:
		custom_minimum_size = Vector2(30, 30)
		size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		draw_circle(c, 13.0, Color(fill, 0.18))
		draw_arc(c, 13.0, 0.0, TAU, 32, fill, 1.5, true)
		AnnounceColumn.draw_glyph(self, String(Announce.family_def(family).get("glyph", "")), c, 7.0, Color(UiTheme.TEXT, 0.9))


## Frise : une ligne du premier jour à aujourd'hui, un jalon par grande heure (couleur de sa famille),
## les années repères en dessous.
class Frise:
	extends Control
	var state: GameState
	var hours: Array[Dictionary] = []
	var viewer := -1

	func _init() -> void:
		custom_minimum_size = Vector2(0, 124)
		mouse_filter = Control.MOUSE_FILTER_PASS

	func _x_of(t: int) -> float:
		var span := maxf(1.0, float(state.tick))
		return 20.0 + (size.x - 40.0) * clampf(float(t) / span, 0.0, 1.0)

	func _draw() -> void:
		if state == null:
			return
		var y := 62.0
		draw_line(Vector2(20, y), Vector2(size.x - 20, y), Color(1, 1, 1, 0.25), 2.0, true)
		var f := UiTheme.font(400)
		var years := maxi(1, int(state.tick / 360.0))
		var step := maxi(1, int(ceil(years / 8.0)))
		for yr in range(0, years + 1, step):
			var x := _x_of(yr * 360)
			draw_line(Vector2(x, y - 4), Vector2(x, y + 4), Color(1, 1, 1, 0.35), 1.0)
			var lab := GameCalendar.date_string(yr * 360).get_slice(" ", GameCalendar.date_string(yr * 360).get_slice_count(" ") - 1)
			draw_string(f, Vector2(x - 14, y + 22), lab, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UiTheme.TEXT_DIM)
		# Une étiquette ne se pose que là où elle ne recouvre pas la précédente du même côté ; sinon le jalon
		# reste seul sur la ligne (son titre se lit dans la liste dessous).
		var up := true
		var free_up := -1.0e9
		var free_down := -1.0e9
		for rec in hours:
			var x := _x_of(int(rec["t"]))
			var col := Announce.family_color(Announce.family_of(String(rec["k"])))
			var title := String(Announce.kind_def(String(rec["k"])).get("title", ""))
			var tw := minf(150.0, f.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x)
			var tx := x + 3.0 if x + 3.0 + tw < size.x - 4.0 else x - 3.0 - tw
			var side := 0
			if tx >= (free_up if up else free_down):
				side = 1 if up else -1
			elif tx >= (free_down if up else free_up):
				side = -1 if up else 1
			if side != 0:
				var tip_y := y - 30.0 * side
				draw_line(Vector2(x, y), Vector2(x, tip_y), Color(col, 0.6), 1.0, true)
				draw_string(f, Vector2(tx, tip_y - 2 if side > 0 else tip_y + 10), title, HORIZONTAL_ALIGNMENT_LEFT, 150, 11, Color(col, 0.95))
				if side > 0:
					free_up = tx + tw + 8.0
				else:
					free_down = tx + tw + 8.0
			draw_circle(Vector2(x, y), 5.0, col)
			draw_circle(Vector2(x, y), 2.0, Color(0.02, 0.02, 0.03))
			up = not up
		if hours.is_empty():
			draw_string(f, Vector2(24, y - 12), "Premier jour", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UiTheme.TEXT_DIM)
