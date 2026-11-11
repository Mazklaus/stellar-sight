extends SceneTree
## Captures des peuples créés (éditeur d'espèces) avec le rendu réel :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_species.gd
## Écrit dans CAPTURE_DIR (par défaut user://captures) : Nouvelle partie avec deux peuples créés de la
## bibliothèque (une féodalité humanoïde, une ruche), l'éditeur de peuples (onglets, refus), le choix des
## rivaux (un peuple créé ajouté en rival), et la galerie des portraits provisoires.
## Les peuples d'exemple vivent dans un dossier de bibliothèque à part, effacé à la fin.

const DIR := "user://capture_species"


func _initialize() -> void:
	var out := OS.get_environment("CAPTURE_DIR")
	if out == "":
		out = ProjectSettings.globalize_path("user://captures")
	DirAccess.make_dir_recursive_absolute(out)
	SpeciesLibrary.dir = DIR
	var a := Species.from_preset("ossarane")
	a.merge({"id": "p_ordre_d_azur", "name": "Ordre d'Azur", "short": "Azur", "color": "#3fb6a8", "portrait": "humanoide_5",
		"registre": "Classique / hard SF", "credo": "raison", "origine": "gisement_filons", "biomes": ["continental", "arctic"],
		"traits": ["erudits", "forgerons", "canonniers", "tenaces", "voraces"],
		"lore": "L'Ordre d'Azur mesure tout, y compris la loyauté de ses vassaux, au millimètre près. Ses fiefs sont tenus par des ingénieurs-barons qui préfèrent les plans aux duels."}, true)
	var b := Species.from_preset("khthari")
	b.merge({"id": "p_nuee_de_vor", "name": "Nuée de Vor", "short": "Vor", "color": "#c46a2b", "portrait": "ruche_2",
		"traits": ["fecondite", "tenaces"], "lore": "La Nuée de Vor ne se souvient pas d'être née. Elle se souvient seulement d'avoir eu faim."}, true)
	for s in [a, b]:
		var err := SpeciesLibrary.save(s)
		if err != "":
			printerr("peuple d'exemple refusé : ", err)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.save_path = "user://saves/capture_quicksave.json"
	root.add_child(main)
	await _frames(30)
	main._main_menu.show_page("new")
	main._main_menu.select_faction("p_ordre_d_azur")
	await _frames(5)
	await _shot(out + "/nouvelle-partie-peuple-cree.png")
	main._main_menu.select_faction("p_nuee_de_vor")
	await _frames(5)
	await _shot(out + "/nouvelle-partie-ruche-creee.png")
	# L'éditeur de peuples, ouvert sur l'Ordre d'Azur, onglet par onglet.
	main._main_menu.select_faction("p_ordre_d_azur")
	main._main_menu.open_species("new")
	var ed: SpeciesEditor = main._main_menu._species
	for t in ["identity", "layers", "traits"]:
		ed.show_tab(t)
		await _frames(5)
		await _shot(out + "/editeur-%s.png" % t)
	# Un peuple refusé : la raison s'affiche, Enregistrer est grisé.
	ed.open_new("vael")
	ed.set_layer("archetype", "ruche")
	ed.show_tab("layers")
	await _frames(5)
	await _shot(out + "/editeur-refus.png")
	main._main_menu.show_page("new")
	main._main_menu.add_slot("p_nuee_de_vor")
	await _frames(5)
	await _shot(out + "/nouvelle-partie-rivaux.png")
	main.queue_free()
	await _frames(3)

	# Galerie des portraits provisoires.
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.05, 0.08)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var grid := GridContainer.new()
	grid.columns = 7
	grid.position = Vector2(60, 60)
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	bg.add_child(grid)
	for p: Dictionary in Species.portraits():
		var box := VBoxContainer.new()
		var arch := String((p["archetypes"] as Array)[0])
		var col := {"humanoide": Color("#3fb6a8"), "ruche": Color("#c46a2b"), "lithoide": Color("#9aa7b8")}.get(arch, Color("#9b7fd4")) as Color
		box.add_child(Widgets.ArtSlot.new("portrait_" + String(p["id"]), Vector2(200, 245), col, "faction"))
		var l := Label.new()
		l.text = String(p["label"])
		box.add_child(l)
		grid.add_child(box)
	await _frames(10)
	await _shot(out + "/galerie-portraits.png")
	for s in [a, b]:
		SpeciesLibrary.delete(String(s["id"]))
	quit(0)


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("capture : ", path)
