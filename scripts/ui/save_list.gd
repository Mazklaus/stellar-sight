class_name SaveList
extends VBoxContainer
## Liste des sauvegardes (refonte D3b), partagée par le menu principal et le menu du jeu : une ligne
## par fichier, la plus récente en tête, avec la vignette, le peuple joué, la date de jeu et le moment
## de l'enregistrement. Charger d'un clic, supprimer en deux.

signal load_requested(path: String)
signal changed

const ROW_WIDTH := 700.0
const THUMB := Vector2(144, 81)
const KIND_LABELS := {"quick": "Rapide", "auto": "Automatique", "manual": ""}

## Dossier lu (les tests en donnent un autre).
var dir := SaveGame.SAVE_DIR
## Chemins montrés, dans l'ordre des lignes.
var paths: Array[String] = []
var _rows: VBoxContainer
var _empty: Label
var _armed := ""


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	custom_minimum_size = Vector2(ROW_WIDTH, 0)
	_empty = UiTheme.dim("Aucune sauvegarde pour l'instant. Ctrl+S en fait une en cours de partie.", 15)
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_empty)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(ROW_WIDTH, 470)
	add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 6)
	scroll.add_child(_rows)
	set_meta("scroll", scroll)
	refresh()


## Relit le dossier et refait les lignes.
func refresh() -> void:
	if _rows == null:
		return
	_armed = ""
	for c in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()
	paths.clear()
	for s: Dictionary in SaveGame.list(dir):
		paths.append(String(s["path"]))
		_rows.add_child(_row(s))
	_empty.visible = paths.is_empty()
	(get_meta("scroll") as Control).visible = not paths.is_empty()


func remove(path: String) -> void:
	SaveGame.remove(path)
	refresh()
	changed.emit()


func _row(s: Dictionary) -> Control:
	var col := Color.html(String(s["color"])) if Color.html_is_valid(String(s.get("color", ""))) else UiTheme.ACCENT
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UiTheme.box(Color(0.03, 0.04, 0.06, 0.8), Color(1, 1, 1, 0.1), 8, 1))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	frame.add_child(row)
	# Vignette : la carte au moment de l'enregistrement, sinon un aplat à la couleur du peuple.
	var holder := Control.new()
	holder.custom_minimum_size = THUMB
	row.add_child(holder)
	var back := ColorRect.new()
	back.color = Color(col.darkened(0.7), 1.0)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_child(back)
	var img := SaveGame.thumbnail(String(s["path"]))
	if img != null:
		var tex := TextureRect.new()
		tex.texture = ImageTexture.create_from_image(img)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		holder.add_child(tex)
	else:
		var dot := Widgets.Dot.new(col, 18)
		dot.position = THUMB * 0.5 - Vector2(9, 9)
		holder.add_child(dot)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.add_theme_constant_override("separation", 2)
	row.add_child(text)
	var who := Label.new()
	who.text = String(s.get("empire", "")) if String(s.get("empire", "")) != "" else "Partie sans nom"
	who.add_theme_font_size_override("font_size", 19)
	who.add_theme_color_override("font_color", col.lightened(0.4))
	who.clip_text = true
	text.add_child(who)
	var when := Label.new()
	when.text = String(s.get("date", ""))
	text.add_child(when)
	var kind := String(KIND_LABELS.get(String(s.get("kind", "")), ""))
	text.add_child(UiTheme.dim("%s%s" % [(kind + " · ") if kind != "" else "", when_text(String(s.get("saved_at", "")))], 13))
	var load_b := Button.new()
	load_b.text = "Charger"
	load_b.focus_mode = Control.FOCUS_NONE
	load_b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var path := String(s["path"])
	load_b.pressed.connect(func() -> void: load_requested.emit(path))
	row.add_child(load_b)
	var del := Button.new()
	del.text = "Supprimer"
	del.focus_mode = Control.FOCUS_NONE
	del.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	del.tooltip_text = "Efface ce fichier du disque (deux clics)."
	del.pressed.connect(func() -> void:
		if _armed != path:
			_armed = path
			for other in get_tree().get_nodes_in_group("save_list_delete"):
				(other as Button).text = "Supprimer"
			del.text = "Confirmer"
			return
		remove(path))
	del.add_to_group("save_list_delete")
	row.add_child(del)
	return frame


## « 2026-11-24T19:23:40 » devient « 24/11/2026, 19 h 23 ».
static func when_text(iso: String) -> String:
	var parts := iso.split("T")
	var d := parts[0].split("-")
	if parts.size() != 2 or d.size() != 3:
		return iso
	var t := parts[1].split(":")
	return "%s/%s/%s, %s h %s" % [d[2], d[1], d[0], t[0], t[1] if t.size() > 1 else "00"]
