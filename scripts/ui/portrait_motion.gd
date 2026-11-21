class_name PortraitMotion
extends RefCounted
## Essai « portraits animés » : fait vivre une illustration fixe de portrait (héros, souverain,
## peuple) déposée dans assets/art/, sans la découper. Deux voies, de la plus légère à la plus riche :
##  1. assets/art/<id>.ogv existe (boucle vidéo, par ex. Midjourney « Loop » converti en Ogg Theora,
##     seul format vidéo de Godot 4) : la vidéo tourne en boucle à la place de l'image ;
##  2. sinon, shaders/portrait_alive.gdshader anime l'image (respiration, regard, et si
##     data/portrait_motion.json donne les yeux : clignement et lueur).
## Purement visuel : rien ne va dans la sauvegarde, la simulation ou le réseau.

const SHADER := preload("res://shaders/portrait_alive.gdshader")
const DATA_PATH := "res://data/portrait_motion.json"
const ART_DIR := "res://assets/art/"

## Interrupteur général (essai : allumé).
static var enabled := true
static var _data := {}


static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open(DATA_PATH, FileAccess.READ)
		if f:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				_data = parsed
		if _data.is_empty():
			_data = {"defaults": {}, "portraits": {}}
	return _data


## Réglages complets d'un portrait (valeurs par défaut complétées), {} s'il n'est pas décrit.
static func entry(art_id: String) -> Dictionary:
	var p: Dictionary = data().get("portraits", {})
	if not p.has(art_id):
		return {}
	var e: Dictionary = (data().get("defaults", {}) as Dictionary).duplicate(true)
	e.merge(p[art_id], true)
	return e


## Les illustrations de personnages qui s'animent même sans fiche (respiration et regard seuls).
static func is_character(art_id: String) -> bool:
	return art_id.begins_with("hero_") or art_id.begins_with("ruler_") or art_id.begins_with("portrait_") \
			or art_id.begins_with("faction_") and not art_id.ends_with("_scene")


static func video_path(art_id: String) -> String:
	var p := "%s%s.ogv" % [ART_DIR, art_id]
	return p if ResourceLoader.exists(p) or FileAccess.file_exists(p) else ""


## Matériau animé pour l'illustration art_id, null si elle ne doit pas bouger.
static func material_for(art_id: String, seed_value := 0.0) -> ShaderMaterial:
	if not enabled:
		return null
	var e := entry(art_id)
	if e.is_empty():
		if not is_character(art_id):
			return null
		e = (data().get("defaults", {}) as Dictionary).duplicate(true)
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("seed", seed_value if seed_value != 0.0 else float(hash(art_id) % 1000) * 0.01)
	m.set_shader_parameter("breath_amp", float(e.get("breath_amp", 0.006)))
	m.set_shader_parameter("breath_period", float(e.get("breath_period", 4.6)))
	m.set_shader_parameter("shoulders", float(e.get("shoulders", 0.45)))
	m.set_shader_parameter("head", _vec(e.get("head", [0.5, 0.33])))
	m.set_shader_parameter("head_radius", float(e.get("head_radius", 0.15)))
	m.set_shader_parameter("gaze_amp", float(e.get("gaze_amp", 0.0035)))
	m.set_shader_parameter("eye_size", _vec(e.get("eye_size", [0.024, 0.0095])))
	m.set_shader_parameter("blink_every", float(e.get("blink_every", 4.5)))
	var eyes: Array = e.get("eyes", [])
	if eyes.size() >= 2:
		m.set_shader_parameter("eyes_on", 1.0)
		m.set_shader_parameter("eye_l", _vec(eyes[0]))
		m.set_shader_parameter("eye_r", _vec(eyes[1]))
		m.set_shader_parameter("glow", float(e.get("glow", 0.0)))
	m.set_shader_parameter("glow_color", Color(String(e.get("glow_color", "#ffd9a0"))))
	m.set_shader_parameter("flicker", float(e.get("flicker", 0.0)))
	m.set_shader_parameter("motes", float(e.get("motes", 0.0)))
	m.set_shader_parameter("mote_color", Color(String(e.get("mote_color", "#ffbf73"))))
	return m


## Branche l'animation sur un TextureRect qui affiche l'illustration art_id (voir Widgets.ArtSlot).
## Une boucle vidéo, si elle existe, est ajoutée comme enfant de host et couvre le cadre.
static func attach(host: Control, tex: TextureRect, art_id: String) -> void:
	var old := host.get_node_or_null("PortraitVideo")
	if old:
		old.queue_free()
	tex.material = null
	if not enabled or tex.texture == null:
		return
	var vp := video_path(art_id)
	if vp != "":
		var v := VideoStreamPlayer.new()
		v.name = "PortraitVideo"
		v.stream = load(vp) as VideoStream
		v.loop = true
		v.autoplay = true
		v.expand = true
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		host.add_child(v)
		host.move_child(v, tex.get_index() + 1)
		return
	tex.material = material_for(art_id)


static func _vec(v: Variant) -> Vector2:
	if v is Array and (v as Array).size() >= 2:
		return Vector2(float(v[0]), float(v[1]))
	return Vector2.ZERO
