class_name ShipArt
extends RefCounted
## Sprites des vaisseaux tirés de leur modèle 3D (docs/vaisseaux-3d.md, tools/vaisseaux/).
## Par peuple et par coque, dans res://assets/ships/ : <peuple>_<coque>_sprite.png (vue de dessus, nez
## vers la droite) et <peuple>_<coque>_portrait.png (vue 3/4 avant), chacun avec son masque
## <..>_masque.png (blanc = teint aux couleurs de l'empire).
## Sans sprite pour ce peuple et cette coque (ni pour la coque dont elle est la variante), texture()
## renvoie null et l'interface garde son dessin stylisé.

const DIR := "res://assets/ships/"
const TEINTE_FORCE := 0.55  # part de la couleur d'empire dans la zone du masque

static var _cache := {}     # "<base>|<couleur>" -> Texture2D
static var _images := {}    # chemin -> Image (ou null si absent)


## Coque d'un vaisseau : celle d'un modèle conçu, celle d'origine d'une classe, sinon l'identifiant.
static func hull_of(ship_id: String) -> String:
	var s := GameData.ship(ship_id)
	if s.has("hull"):
		return String(s["hull"])
	return String(Designs.origin(ship_id).get("hull", ship_id))


## Nom de fichier (sans suffixe) du sprite d'un vaisseau pour un peuple, ou "" s'il n'en a pas.
## Une variante de coque (titan_bastion…) reprend le sprite de sa coque de base.
static func base_name(faction_id: String, ship_id: String, kind := "sprite") -> String:
	var style := GameData.ship_style(faction_id)  # un peuple créé emprunte le style d'un officiel
	var h := hull_of(ship_id)
	while h != "":
		var base := "%s_%s" % [style, h]
		if ResourceLoader.exists("%s%s_%s.png" % [DIR, base, kind]):
			return base
		h = String(Designs.hull(h).get("variant_of", ""))
	return ""


static func has_art(faction_id: String, ship_id: String) -> bool:
	return base_name(faction_id, ship_id) != ""


## Sprite vu de dessus teint aux couleurs de l'empire (gardé en cache), ou null.
static func texture(faction_id: String, ship_id: String, tint: Color) -> Texture2D:
	return _teinte(faction_id, ship_id, tint, "sprite")


## Portrait 3/4 teint aux couleurs de l'empire (gardé en cache), ou null.
static func portrait(faction_id: String, ship_id: String, tint: Color) -> Texture2D:
	return _teinte(faction_id, ship_id, tint, "portrait")


static func _teinte(faction_id: String, ship_id: String, tint: Color, kind: String) -> Texture2D:
	var base := base_name(faction_id, ship_id, kind)
	if base == "":
		return null
	var key := "%s_%s|%s" % [base, kind, tint.to_html(false)]
	if _cache.has(key):
		return _cache[key]
	var img := _image("%s%s_%s.png" % [DIR, base, kind])
	var tex: Texture2D = null
	if img:
		var masque := _image("%s%s_%s_masque.png" % [DIR, base, kind])
		var finale := teinter(img, masque, tint) if masque else img.duplicate() as Image
		# Mipmaps : les images (512 à 900 px) sont affichées bien plus petites ; dessiner avec
		# CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS pour éviter le grain.
		if finale.is_compressed():
			finale.decompress()
		finale.generate_mipmaps()
		tex = ImageTexture.create_from_image(finale)
	_cache[key] = tex
	return tex


## Teint la zone blanche du masque : la luminosité du sprite est gardée, la couleur tire vers la teinte.
static func teinter(img: Image, masque: Image, tint: Color) -> Image:
	var out := img.duplicate() as Image
	if out.is_compressed():
		out.decompress()
	out.convert(Image.FORMAT_RGBA8)
	var m := masque.duplicate() as Image
	if m.is_compressed():
		m.decompress()
	if m.get_size() != out.get_size():
		m.resize(out.get_width(), out.get_height())
	m.convert(Image.FORMAT_L8)
	var px := out.get_data()
	var mk := m.get_data()
	var tr := tint.r * 1.25
	var tg := tint.g * 1.25
	var tb := tint.b * 1.25
	for i in mk.size():
		var k := mk[i]
		if k < 8:
			continue
		var j := i * 4
		var r := px[j]
		var g := px[j + 1]
		var b := px[j + 2]
		var l := 0.299 * r + 0.587 * g + 0.114 * b
		var f := k / 255.0 * TEINTE_FORCE
		px[j] = clampi(int(r + (l * tr - r) * f), 0, 255)
		px[j + 1] = clampi(int(g + (l * tg - g) * f), 0, 255)
		px[j + 2] = clampi(int(b + (l * tb - b) * f), 0, 255)
	return Image.create_from_data(out.get_width(), out.get_height(), false, Image.FORMAT_RGBA8, px)


static func _image(path: String) -> Image:
	if _images.has(path):
		return _images[path]
	var img: Image = null
	if ResourceLoader.exists(path):
		var tex := load(path) as Texture2D
		if tex:
			img = tex.get_image()
	if img == null and FileAccess.file_exists(path):
		img = Image.load_from_file(ProjectSettings.globalize_path(path))
	_images[path] = img
	return img
