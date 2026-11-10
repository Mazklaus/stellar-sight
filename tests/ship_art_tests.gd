extends RefCounted
## Tests des sprites tirés des modèles 3D (ShipArt, docs/vaisseaux-3d.md) : coque de chaque vaisseau,
## sprite trouvé par peuple et par coque (repli sur la coque de base d'une variante), teinte d'empire
## limitée au masque, cinématique 3D des batailles (BattleCinematic). Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Sprites des vaisseaux 3D…")
	_test_hulls()
	_test_lookup()
	_test_tint()
	_test_cinematic()


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
	_ok(ShipArt.base_name("khthari", "fregate", "portrait") == "khthari_fregate", "ShipArt : portrait 3/4 de la frégate Kh'thari trouvé")
	_ok(ShipArt.base_name("vael", "fregate", "portrait") == "", "ShipArt : pas de portrait Vael")


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


## Journal de bataille fictif : 6 jours (2 par phase), une frégate de chaque côté et une corvette
## de l'empire 1 détruite le 3e jour.
func _fake_report() -> Dictionary:
	var log: Array = []
	for d in 6:
		var shots: Array = [[0, 2 if d < 3 else 1, "beam", 10], [1, 0, "missile", 8], [2, 0, "kinetic", 4]]
		if d >= 3:
			shots = [[0, 1, "beam", 10], [1, 0, "missile", 8]]
		log.append({"day": d + 1, "phase": d / 2, "shots": shots, "kills": [2] if d == 2 else []})
	return {"id": 7, "system": 0, "system_name": "Essai", "sides": [{"empire": 0}, {"empire": 1}],
			"units": [[0, "fregate", "line", 1], [1, "fregate", "line", 1], [1, "corvette", "screen", 1]], "log": log}


func _test_cinematic() -> void:
	var st := GameState.create(4242, 150, 1800.0, "ossarane", {"ai_level": ""})
	var cin := BattleCinematic.new()
	cin._ready()
	cin.show_cinematic(st, _fake_report(), {0: true})
	_ok(cin._units.size() == 3, "Cinématique : un vaisseau 3D par unité du journal")
	var end := cin.day_count() * BattleCinematic.DAY_SECONDS
	_ok(cin.unit_pos(0, 0.0).x < cin.unit_pos(1, 0.0).x, "Cinématique : chaque camp arrive de son côté")
	_ok(cin.unit_pos(0, end).x > cin.unit_pos(1, end).x, "Cinématique : à courte portée, les flottes se sont croisées")
	_ok(cin.unit_pos(0, 4.2).is_equal_approx(cin.unit_pos(0, 4.2)), "Cinématique : positions calculées à partir du temps seul")
	_ok(String(cin.shot_at(0.0)["kind"]) == "ensemble", "Cinématique : le premier plan est un plan d'ensemble")
	var kinds := {}
	var tt := 0.0
	while tt < end:
		kinds[String(cin.shot_at(tt)["kind"])] = true
		tt += BattleCinematic.SHOT_SECONDS
	_ok(kinds.size() >= 2, "Cinématique : la caméra enchaîne plusieurs sortes de plans")
	_ok(cin.shot_at(5.0) == cin.shot_at(5.0), "Cinématique : un même instant redonne le même plan")
	cin.t = 3.5 * BattleCinematic.DAY_SECONDS
	cin._update(0.0)
	_ok(not (cin._units[2]["node"] as Node3D).visible and (cin._units[0]["node"] as Node3D).visible, "Cinématique : la corvette détruite a disparu, la frégate vole encore")
	if ResourceLoader.exists(ShipArt.DIR + "ossarane_fregate.glb"):
		var model := BattleCinematic.ship_model("ossarane", "bombarde")
		_ok(model != null, "Cinématique : la bombarde Ossarane prend le modèle 3D de la frégate")
		if model:
			model.free()
	_ok(BattleCinematic.ship_model("vael", "fregate") == null, "Cinématique : sans modèle 3D, une silhouette simple")
	cin.close_silently()
	cin.free()
