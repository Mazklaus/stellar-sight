class_name AnnounceFrame
extends RefCounted
## Cadre commun des fenêtres (étude de la fenêtre d'événement, prop. 25) : voile, fenêtre centrée,
## filet d'or « Décision » pour les fenêtres qui attendent un choix (événements, hauts faits, élection),
## fondu d'ouverture réglable (AnnounceSettings.anim). Les annonces (AnnouncePanel) ont le même cadre,
## avec le bandeau de leur famille.

const ART_WIDTH := 300.0
const ART_MIN_HEIGHT := 380.0


## Pose le voile et la fenêtre sur layer (calque 7) ; renvoie la boîte où mettre le contenu.
## tag : libellé du filet de tête ("" : pas de filet).
## art_width > 0 : gabarit à deux colonnes, l'illustration à gauche sur toute la hauteur (voir art_of).
static func build(layer: CanvasLayer, width: float, tag := "", separation := 10, art_width := 0.0) -> VBoxContainer:
	layer.layer = 7
	layer.visible = false
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.0, 0.01, 0.03, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)
	var window := PanelContainer.new()
	window.name = "Window"
	window.theme_type_variation = &"WindowPanel"
	center.add_child(window)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(width, 0)
	box.add_theme_constant_override("separation", separation)
	if art_width > 0.0:
		var split := HBoxContainer.new()
		split.name = "Split"
		split.add_theme_constant_override("separation", 16)
		window.add_child(split)
		split.add_child(side_art(art_width))
		split.add_child(box)
	else:
		window.add_child(box)
	if tag != "":
		box.add_child(DecisionBand.new(tag))
	return box


## L'illustration de la colonne de gauche : elle prend toute la hauteur de la fenêtre.
static func side_art(art_width: float) -> Widgets.ArtSlot:
	var art := Widgets.ArtSlot.new("", Vector2(art_width, ART_MIN_HEIGHT), UiTheme.ACCENT, "star")
	art.name = "Art"
	art.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return art


## L'illustration d'une fenêtre bâtie à deux colonnes (null sinon).
static func art_of(layer: CanvasLayer) -> Widgets.ArtSlot:
	return layer.get_node_or_null("Center/Window/Split/Art") as Widgets.ArtSlot


## Fondu d'ouverture du voile et de la fenêtre (à appeler après visible = true).
static func fade_in(layer: CanvasLayer) -> void:
	var secs := AnnounceSettings.anim_seconds()
	var parts: Array[CanvasItem] = []
	for n in ["Dim", "Center"]:
		var c := layer.get_node_or_null(n) as CanvasItem
		if c:
			parts.append(c)
	for c in parts:
		c.modulate.a = 1.0 if secs <= 0.0 else 0.0
	if secs <= 0.0 or parts.is_empty():
		return
	var tw := layer.create_tween().set_parallel(true)
	for c in parts:
		tw.tween_property(c, "modulate:a", 1.0, secs)


## Filet d'or en tête des fenêtres de décision.
class DecisionBand:
	extends Control
	var tag := ""

	func _init(t: String) -> void:
		tag = t.to_upper()
		custom_minimum_size = Vector2(0, 24)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var col := Announce.need_color("decision")
		draw_rect(Rect2(0, size.y - 3, size.x, 3), col)
		AnnounceColumn.draw_glyph(self, "decision", Vector2(10, 10), 8.0, col)
		draw_string(UiTheme.font(500, 2), Vector2(26, 15), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)
