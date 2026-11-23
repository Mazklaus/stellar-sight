extends SceneTree
## Démonstration de l'essai « portraits animés » (PortraitMotion), avec le rendu réel :
##   xvfb-run -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 --resolution 1280x720 -s res://tools/portrait_motion_demo.gd
## Sans CAPTURE_DIR : la fenêtre reste ouverte (Échap pour quitter).
## Avec CAPTURE_DIR : enregistre SECONDS secondes (défaut 12) en images PNG à 30 i/s dans ce dossier,
## à assembler ensuite avec ffmpeg (voir tools/portrait_motion_video.sh).
## À gauche l'image d'origine, figée ; au centre et à droite les deux portraits animés ; en bas, les
## mêmes à la taille des cartes du Panthéon.

const IDS := ["essais/essai_mystique", "essais/essai_noble"]
var _out := ""
var _frames := 0
var _total := 0


func _initialize() -> void:
	_out = OS.get_environment("CAPTURE_DIR")
	_total = int(float(OS.get_environment("SECONDS") if OS.get_environment("SECONDS") != "" else "12") * 30.0)
	root.theme = UiTheme.theme()
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.04, 0.06)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var col := VBoxContainer.new()
	col.position = Vector2(24, 14)
	col.add_theme_constant_override("separation", 8)
	root.add_child(col)
	col.add_child(UiTheme.title("Portraits animés : essai", 24))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	col.add_child(row)
	row.add_child(_card(IDS[0], Vector2(300, 398), "Image d'origine (figée)", false))
	row.add_child(_card(IDS[0], Vector2(300, 398), "Respiration, regard, clignement, lueur", true))
	row.add_child(_card(IDS[1], Vector2(300, 398), "Idem, avec poussières", true))
	var small := VBoxContainer.new()
	small.add_theme_constant_override("separation", 8)
	row.add_child(small)
	var lbl := Label.new()
	lbl.text = "Taille Panthéon\n(96 × 112)"
	small.add_child(lbl)
	for id in IDS:
		small.add_child(_card(id, Vector2(96, 112), "", true))
	var lbl2 := Label.new()
	lbl2.text = "Taille Trône\n(170 × 210)"
	small.add_child(lbl2)
	small.add_child(_card(IDS[1], Vector2(170, 210), "", true))
	if _out != "":
		DirAccess.make_dir_recursive_absolute(_out)
		Engine.max_fps = 30
	Engine.physics_ticks_per_second = 30


func _card(id: String, sz: Vector2, caption: String, alive: bool) -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var slot := Widgets.ArtSlot.new(id, sz, Color(0.8, 0.6, 0.3), "faction")
	if not alive:
		(slot.get_child(0) as TextureRect).material = null
	box.add_child(slot)
	if caption != "":
		var l := Label.new()
		l.text = caption
		l.add_theme_font_size_override("font_size", 13)
		box.add_child(l)
	return box


func _process(_delta: float) -> bool:
	if Input.is_key_pressed(KEY_ESCAPE):
		return true
	if _out == "":
		return false
	_frames += 1
	if _frames > 3:
		var img := root.get_texture().get_image()
		img.save_png("%s/f_%04d.png" % [_out, _frames - 3])
	return _frames >= _total + 3
