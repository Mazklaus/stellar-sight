class_name ResourceIcon
extends Control
## Petite icône vectorielle d'une ressource, dessinée par le code (aucune image à fournir) :
## éclair pour l'énergie, cube pour les matériaux, feuille pour la nourriture,
## étoile pour l'influence, cristal pour les cristaux de saut, livre ouvert pour le Savoir.

const COLORS := {
	"energy": Color(1.0, 0.85, 0.3),
	"materials": Color(0.85, 0.62, 0.42),
	"food": Color(0.5, 0.88, 0.45),
	"influence": Color(0.78, 0.55, 1.0),
	"crystals": Color(0.4, 0.92, 1.0),
	"knowledge": Color(1.0, 0.58, 0.66),
}

var resource_id := ""


static func make(id: String, side := 18.0) -> ResourceIcon:
	var icon := ResourceIcon.new()
	icon.resource_id = id
	icon.custom_minimum_size = Vector2(side, side)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon


static func color_of(id: String) -> Color:
	return COLORS.get(id, Color.WHITE)


func _draw() -> void:
	var s := minf(size.x, size.y)
	var o := (size - Vector2(s, s)) * 0.5
	var col := color_of(resource_id)
	var pts := PackedVector2Array()
	match resource_id:
		"energy":
			for p in [Vector2(0.58, 0.02), Vector2(0.18, 0.56), Vector2(0.46, 0.56), Vector2(0.36, 0.98), Vector2(0.84, 0.4), Vector2(0.54, 0.4)]:
				pts.append(o + p * s)
		"materials":
			# Cube vu en perspective : trois faces de luminosités différentes.
			var top := PackedVector2Array([Vector2(0.5, 0.06), Vector2(0.92, 0.28), Vector2(0.5, 0.5), Vector2(0.08, 0.28)])
			var left := PackedVector2Array([Vector2(0.08, 0.28), Vector2(0.5, 0.5), Vector2(0.5, 0.96), Vector2(0.08, 0.74)])
			var right := PackedVector2Array([Vector2(0.5, 0.5), Vector2(0.92, 0.28), Vector2(0.92, 0.74), Vector2(0.5, 0.96)])
			draw_colored_polygon(_place(top, o, s), col.lightened(0.25))
			draw_colored_polygon(_place(left, o, s), col.darkened(0.15))
			draw_colored_polygon(_place(right, o, s), col.darkened(0.4))
			return
		"food":
			# Feuille : deux arcs qui se rejoignent en pointe.
			for i in 13:
				var t := i / 12.0
				pts.append(o + Vector2(0.15 + 0.7 * t, 0.85 - 0.7 * t + sin(t * PI) * -0.22) * s)
			for i in 13:
				var t := 1.0 - i / 12.0
				pts.append(o + Vector2(0.15 + 0.7 * t, 0.85 - 0.7 * t + sin(t * PI) * 0.22) * s)
			draw_colored_polygon(pts, col)
			draw_line(o + Vector2(0.08, 0.92) * s, o + Vector2(0.62, 0.38) * s, col.darkened(0.45), maxf(1.0, s * 0.07))
			return
		"influence":
			for i in 10:
				var r := 0.48 if i % 2 == 0 else 0.2
				var a := -PI * 0.5 + TAU * i / 10.0
				pts.append(o + (Vector2(0.5, 0.53) + Vector2(cos(a), sin(a)) * r) * s)
		"crystals":
			var facets := PackedVector2Array([Vector2(0.5, 0.02), Vector2(0.82, 0.36), Vector2(0.5, 0.98), Vector2(0.18, 0.36)])
			draw_colored_polygon(_place(facets, o, s), col)
			draw_colored_polygon(_place(PackedVector2Array([Vector2(0.5, 0.02), Vector2(0.82, 0.36), Vector2(0.5, 0.36)]), o, s), col.lightened(0.45))
			draw_colored_polygon(_place(PackedVector2Array([Vector2(0.18, 0.36), Vector2(0.5, 0.36), Vector2(0.5, 0.98)]), o, s), col.darkened(0.3))
			return
		"knowledge":
			# Livre ouvert : deux pages inclinées et une tranche.
			var lp := PackedVector2Array([Vector2(0.06, 0.24), Vector2(0.48, 0.32), Vector2(0.48, 0.9), Vector2(0.06, 0.8)])
			var rp := PackedVector2Array([Vector2(0.52, 0.32), Vector2(0.94, 0.24), Vector2(0.94, 0.8), Vector2(0.52, 0.9)])
			draw_colored_polygon(_place(lp, o, s), col)
			draw_colored_polygon(_place(rp, o, s), col.darkened(0.2))
			draw_line(o + Vector2(0.5, 0.3) * s, o + Vector2(0.5, 0.92) * s, col.lightened(0.5), maxf(1.0, s * 0.06))
			return
		_:
			draw_circle(o + Vector2(s, s) * 0.5, s * 0.4, col)
			return
	draw_colored_polygon(pts, col)


func _place(points: PackedVector2Array, o: Vector2, s: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in points:
		out.append(o + p * s)
	return out
