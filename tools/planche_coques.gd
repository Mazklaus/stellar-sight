extends SceneTree
## Planche des silhouettes 2D (HullArt) : une ligne par style de peuple, une colonne par coque.
## godot --headless --path . -s res://tools/planche_coques.gd -- <sortie.png> [coque,coque,…]

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "/tmp/planche_coques.png"
	var hulls := ["corvette", "fregate", "croiseur", "cuirasse", "porte_vaisseaux", "titan", "nef_monde", "coursier", "martyr", "fregate_quarante", "ruche_mere"]
	if args.size() > 1:
		hulls = args[1].split(",")
	var styles: Array = HullArt.cfg()["styles"].keys()
	var cell := Vector2i(150, 90)
	var sheet := Image.create(cell.x * hulls.size(), cell.y * styles.size(), false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.04, 0.05, 0.08))
	for r in styles.size():
		for c in hulls.size():
			var ha := HullArt.new()
			ha.paint(String(styles[r]), String(hulls[c]), Color(0.8, 0.25, 0.2))
			var im: Image = ha.img
			var k := minf(float(cell.x - 10) / im.get_width(), float(cell.y - 10) / im.get_height())
			k = minf(k, 0.5)
			var w := maxi(1, int(im.get_width() * k))
			var h := maxi(1, int(im.get_height() * k))
			im.resize(w, h, Image.INTERPOLATE_BILINEAR)
			var pos := Vector2i(c * cell.x + (cell.x - w) / 2, r * cell.y + (cell.y - h) / 2)
			sheet.blend_rect(im, Rect2i(Vector2i.ZERO, Vector2i(w, h)), pos)
	sheet.save_png(out)
	print("styles: ", styles, " coques: ", hulls)
	quit()
