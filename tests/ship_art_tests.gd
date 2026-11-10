extends RefCounted
## Tests des sprites tirés des modèles 3D (ShipArt, docs/vaisseaux-3d.md) : coque de chaque vaisseau,
## sprite trouvé par peuple et par coque (repli sur la coque de base d'une variante), teinte d'empire
## limitée au masque. Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Sprites des vaisseaux 3D…")
	_test_hulls()
	_test_lookup()
	_test_tint()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


func _test_hulls() -> void:
	_ok(ShipArt.hull_of("fregate") == "fregate", "ShipArt : la frégate a sa propre coque")
	_ok(ShipArt.hull_of("transport") == "fregate", "ShipArt : le transport de troupes est une coque de frégate")
	_ok(ShipArt.hull_of("escorteur") == "corvette", "ShipArt : l'escorteur est une coque de corvette")
	var st := GameState.create(4242, 150, 1800.0, "ossarane", {"ai_level": ""})
	var spec := {"name": "Lance d'essai", "hull": "croiseur", "modules": [], "line": "line", "target": "nearest"}
	Research.grant(st, 0, ["coques_lourdes"])
	var why := SimCommands.validate(st, SimCommands.save_design(0, spec))
	if why == "":
		SimCommands.apply(st, SimCommands.save_design(0, spec))
		_ok(ShipArt.hull_of("m0_0") == "croiseur", "ShipArt : un modèle conçu garde la coque choisie")
	else:
		_ok(false, "ShipArt : enregistrement du modèle d'essai refusé (%s)" % why)


func _test_lookup() -> void:
	# Les frégates Ossarane et Kh'thari du test Tripo sont dans assets/ships.
	if not ResourceLoader.exists(ShipArt.DIR + "ossarane_fregate_sprite.png"):
		print("  (sprites non importés : lancer godot --headless --import une fois, recherche non vérifiée)")
		return
	_ok(ShipArt.base_name("ossarane", "fregate") == "ossarane_fregate", "ShipArt : sprite de la frégate Ossarane trouvé")
	_ok(ShipArt.base_name("ossarane", "bombarde") == "ossarane_fregate", "ShipArt : la bombarde reprend le sprite de sa coque")
	_ok(ShipArt.base_name("khthari", "fregate") == "khthari_fregate", "ShipArt : sprite de la frégate Kh'thari trouvé")
	_ok(ShipArt.base_name("vael", "fregate") == "", "ShipArt : pas de sprite Vael, l'interface garde son dessin")
	_ok(ShipArt.base_name("ossarane", "titan_bastion") == "", "ShipArt : variante sans sprite ni coque de base dessinée")
	_ok(not ShipArt.has_art("ossarane", "croiseur"), "ShipArt : pas encore de croiseur Ossarane")


func _test_tint() -> void:
	var img := Image.create(2, 1, false, Image.FORMAT_RGBA8)
	img.set_pixel(0, 0, Color(0.8, 0.8, 0.8, 1.0))
	img.set_pixel(1, 0, Color(0.8, 0.8, 0.8, 0.5))
	var masque := Image.create(2, 1, false, Image.FORMAT_L8)
	masque.set_pixel(0, 0, Color.WHITE)
	masque.set_pixel(1, 0, Color.BLACK)
	var out := ShipArt.teinter(img, masque, Color(1.0, 0.0, 0.0))
	var a := out.get_pixel(0, 0)
	var b := out.get_pixel(1, 0)
	_ok(a.r > 0.8 and a.g < 0.5 and a.b < 0.5, "ShipArt : la zone du masque tire vers la couleur de l'empire")
	_ok(absf(b.r - 0.8) < 0.01 and absf(b.g - 0.8) < 0.01 and absf(b.a - 0.5) < 0.01, "ShipArt : hors du masque, le sprite est intact (transparence comprise)")
	_ok(absf(a.a - 1.0) < 0.01, "ShipArt : la teinte garde l'opacité")
