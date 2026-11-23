extends SceneTree
## Démonstration des portraits dessinés animés (silhouettes provisoires : peuples, héros, souverains) :
##   xvfb-run -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 --resolution 1280x720 --fixed-fps 30 -s res://tools/portrait_drawn_demo.gd
## Avec CAPTURE_DIR : enregistre SECONDS secondes (défaut 12) en images PNG à 30 i/s.

const PEUPLES := ["portrait_humanoide_1", "portrait_humanoide_2", "portrait_ruche_1", "portrait_lithoide_3", "portrait_energetique_3", "portrait_synthetique_1", "portrait_reptilien_1"]
const HEROS := ["hero_humanoide_1", "hero_humanoide_4", "hero_ruche_1", "hero_lithoide_3", "hero_reptilien_3", "hero_synthetique_3", "hero_energetique_3"]
const SOUVERAINS := ["ruler_humanoide_1", "ruler_humanoide_7", "ruler_reptilien_2", "ruler_lithoide_5"]
const CLASSES := ["stratege", "intendant", "orateur", "ombre"]
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
	col.position = Vector2(20, 10)
	col.add_theme_constant_override("separation", 6)
	root.add_child(col)
	col.add_child(UiTheme.title("Portraits actuels animés : respiration, tête, clignement, lueur des yeux", 18))
	col.add_child(_row("Peuples (galerie de l'éditeur)", PEUPLES, Vector2(150, 176), 0))
	col.add_child(_row("Héros (Panthéon)", HEROS, Vector2(150, 176), 1))
	col.add_child(_row("Souverains (Trône)", SOUVERAINS, Vector2(150, 176), 2))
	if _out != "":
		DirAccess.make_dir_recursive_absolute(_out)


func _row(title: String, ids: Array, sz: Vector2, kind: int) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var l := Label.new()
	l.text = title
	l.add_theme_font_size_override("font_size", 13)
	box.add_child(l)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	var cols := [Color(0.38, 0.86, 0.92), Color(0.9, 0.6, 0.3), Color(0.6, 0.85, 0.4), Color(0.75, 0.55, 0.95), Color(0.95, 0.75, 0.35), Color(0.5, 0.7, 1.0), Color(0.9, 0.45, 0.45)]
	var i := 0
	for id in ids:
		var tint: Color = Color(0.95, 0.78, 0.36) if kind == 2 else cols[i % cols.size()]
		var a := Widgets.ArtSlot.new(id, sz, tint, "faction")
		a.variant = i
		if kind == 1:
			a.set_hero({"seed": 17 + i * 13, "cls": CLASSES[i % 4], "lvl": 1 + i % 5, "age": 30 + i * 7, "faction": cols[(i + 3) % cols.size()]})
		row.add_child(a)
		i += 1
	return box


func _process(_delta: float) -> bool:
	if Input.is_key_pressed(KEY_ESCAPE):
		return true
	if _out == "":
		return false
	_frames += 1
	if _frames > 3:
		root.get_texture().get_image().save_png("%s/f_%04d.png" % [_out, _frames - 3])
	return _frames >= _total + 3
