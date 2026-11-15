extends SceneTree
## Banc d'essai des décors (étude visuel des combats, prop. 36) : planches de vignettes sans bataille,
## pour vérifier d'un coup d'œil chaque étoile, chaque terrain, chaque style de ville et chaque biome
## (et voir aussitôt un asset final posé à son emplacement) :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/banc_decors.gd
## Écrit dans CAPTURE_DIR (par défaut user://captures) : banc-espace-N.png (étoiles × terrains) et
## banc-villes-N.png (styles de ville × biomes), 9 vignettes par planche, chacune légendée.

const CELL := Vector2(1600, 900)
const K := 1.0 / 3.0


func _initialize() -> void:
	var out := OS.get_environment("CAPTURE_DIR")
	if out == "":
		out = ProjectSettings.globalize_path("user://captures")
	DirAccess.make_dir_recursive_absolute(out)
	await process_frame
	# Espace : chaque terrain sous son étoile (ou une étoile jaune), puis chaque étoile sans terrain.
	var space: Array = []
	for star in ["yellow", "red", "white", "blue_giant", "neutron", "black_hole"]:
		space.append([{"star": star, "terrain": []}, star])
	for tid in Terrain.data().get("terrains", {}):
		var td: Dictionary = Terrain.def(String(tid))
		var star := String(tid) if String(td.get("family", "")) == "star" else "yellow"
		space.append([{"star": star, "terrain": [String(tid)]}, "%s · %s" % [star, Terrain.label(String(tid))]])
	var page := 0
	for i in range(0, space.size(), 9):
		await _sheet(space.slice(i, i + 9), true, out + "/banc-espace-%d.png" % page)
		page += 1
	# Sol : chaque style de ville sur son biome type, puis un même style sur chaque biome.
	var cities: Array = []
	var biomes := ["continental", "ocean", "desert", "arctic", "toxic", "gaia", "barren", "asteroids", "ecumenopole"]
	var styles: Dictionary = GameData.battle_visuals().get("cities", {}).get("styles", {})
	var peoples: Dictionary = GameData.battle_visuals().get("cities", {}).get("peoples", {})
	var by_style := {}
	for fid in peoples:
		by_style[String(peoples[fid])] = String(fid)
	var bi := 0
	for st in styles:
		if String(st).begins_with("_"):
			continue
		cities.append([{"ter": biomes[bi % biomes.size()], "pop": 16, "csp": String(by_style.get(st, ""))}, "%s · %s" % [st, biomes[bi % biomes.size()]]])
		bi += 1
	for b in biomes:
		cities.append([{"ter": b, "pop": 12, "csp": "vael"}, "héroïque · %s" % b])
	for pop in [0, 3, 8, 14, 22]:
		cities.append([{"ter": "continental", "pop": pop, "csp": "ossarane"}, "citadelle · %d pop" % pop])
	page = 0
	for i in range(0, cities.size(), 9):
		await _sheet(cities.slice(i, i + 9), false, out + "/banc-villes-%d.png" % page)
		page += 1
	quit()


func _sheet(items: Array, space: bool, path: String) -> void:
	var holder := Control.new()
	holder.size = CELL
	root.add_child(holder)
	for i in items.size():
		var wrap := Control.new()
		wrap.size = CELL
		wrap.clip_contents = true
		wrap.scale = Vector2(K, K)
		@warning_ignore("integer_division")
		wrap.position = Vector2((i % 3) * CELL.x * K, (i / 3) * CELL.y * K)
		holder.add_child(wrap)
		var sc: Dictionary = (items[i][0] as Dictionary).duplicate(true)
		sc["seed"] = 101 + i * 7
		if space:
			sc.merge({"planet": {"type": "continental", "size": 3, "id": i}, "moons": [{"type": "barren", "id": 50 + i}],
					"belt": false, "station": "colony", "wrecks": 4}, false)
			var bd := BattleBackdrop.new()
			wrap.add_child(bd)
			bd.size = CELL
			bd.setup(sc, 1)
			bd.time = 1.3
			wrap.add_child(bd.foreground)
		else:
			sc.merge({"star": "yellow", "fort": 0, "fort_max": 0}, false)
			var gb := GroundBackdrop.new()
			wrap.add_child(gb)
			gb.size = CELL
			gb.setup(sc, 1)
		var lbl := Label.new()
		lbl.text = String(items[i][1])
		lbl.add_theme_font_size_override("font_size", 40)
		lbl.add_theme_color_override("font_outline_color", Color.BLACK)
		lbl.add_theme_constant_override("outline_size", 10)
		lbl.position = Vector2(24, 16)
		wrap.add_child(lbl)
	for _i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("planche : ", path)
	holder.queue_free()
	await process_frame
