extends SceneTree
## Démonstration de la méthode 3 des portraits animés (PortraitRig : portrait découpé et rigué) :
##   xvfb-run -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 --resolution 1280x720 --fixed-fps 30 -s res://tools/portrait_rig_demo.gd
## Avec CAPTURE_DIR : enregistre SECONDS secondes (défaut 18) en images PNG à 30 i/s.

const RIGS := [["essai_mystique", "Mystique"], ["essai_noble", "Noble"], ["essai_cornu", "Cornu"]]
var _out := ""
var _frames := 0
var _total := 0


func _initialize() -> void:
	_out = OS.get_environment("CAPTURE_DIR")
	_total = int(float(OS.get_environment("SECONDS") if OS.get_environment("SECONDS") != "" else "18") * 30.0)
	root.theme = UiTheme.theme()
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.04, 0.06)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var col := VBoxContainer.new()
	col.position = Vector2(24, 14)
	col.add_theme_constant_override("separation", 8)
	root.add_child(col)
	col.add_child(UiTheme.title("Portraits découpés et rigués (méthode 3) : respiration, tête, regard, clignement, parole", 20))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	col.add_child(row)
	var i := 0
	for r in RIGS:
		var box := VBoxContainer.new()
		box.add_child(PortraitRig.new(r[0], Vector2(390, 518), float(i) * 1.7))
		var l := Label.new()
		l.text = r[1]
		box.add_child(l)
		row.add_child(box)
		i += 1
	if _out != "":
		DirAccess.make_dir_recursive_absolute(_out)


func _process(_delta: float) -> bool:
	if Input.is_key_pressed(KEY_ESCAPE):
		return true
	if _out == "":
		return false
	_frames += 1
	if _frames > 3:
		root.get_texture().get_image().save_png("%s/f_%04d.png" % [_out, _frames - 3])
	return _frames >= _total + 3
