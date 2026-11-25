extends RefCounted
## Le son, lot 1 (étude du son, blocs A, J, K) : bus, réglages, esquisses, repères des boutons.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	SoundSettings.persist = false
	AnnounceSettings.persist = false
	_test_buses()
	_test_settings()
	_test_synth()
	_test_cues()
	_test_buttons()
	_test_announces()
	_test_options()
	SoundSettings.reset()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, "son : " + what)


func _test_buses() -> void:
	Son.build_buses()
	var n := AudioServer.bus_count
	Son.build_buses()
	_ok(AudioServer.bus_count == n, "reconstruire les bus n'en ajoute pas")
	for b in Son.data()["buses"]:
		var at := AudioServer.get_bus_index(String(b["id"]))
		_ok(at > 0, "bus %s présent" % b["id"])
		_ok(String(AudioServer.get_bus_send(at)) == String(b["send"]), "bus %s vers %s" % [b["id"], b["send"]])
	var music := AudioServer.get_bus_index("Musique")
	var comp := AudioServer.get_bus_effect(music, 0) as AudioEffectCompressor
	_ok(comp != null and String(comp.sidechain) == "Annonces", "la musique baisse quand une annonce sonne")
	for d in Son.data()["volumes"]:
		_ok(AudioServer.get_bus_index(String(d["bus"])) >= 0, "volume réglable sur un bus connu (%s)" % d["bus"])


func _test_settings() -> void:
	SoundSettings.reset()
	var music := AudioServer.get_bus_index("Musique")
	_ok(is_equal_approx(SoundSettings.volume("Musique"), 0.7), "volume d'origine lu dans les données")
	_ok(absf(AudioServer.get_bus_volume_db(music) - linear_to_db(0.7)) < 0.01, "volume d'origine posé sur le bus")
	SoundSettings.set_volume("Musique", 0.0)
	_ok(AudioServer.is_bus_mute(music) and SoundSettings.volume_label("Musique") == "Coupé", "volume à zéro : bus coupé")
	SoundSettings.cycle_volume("Musique")
	_ok(is_equal_approx(SoundSettings.volume("Musique"), 0.2) and not AudioServer.is_bus_mute(music), "cran suivant")
	SoundSettings.cycle_volume("Musique", -1)
	SoundSettings.cycle_volume("Musique", -1)
	_ok(is_equal_approx(SoundSettings.volume("Musique"), 1.0), "cran précédent, en boucle")
	_ok(SoundSettings.profile_id() == "enceintes", "profil d'origine")
	_ok(not AudioServer.is_bus_effect_enabled(0, 0) and not AudioServer.is_bus_effect_enabled(0, 1), "enceintes : aucun effet")
	SoundSettings.cycle_profile()
	_ok(SoundSettings.profile_id() == "casque" and AudioServer.is_bus_effect_enabled(0, 1), "casque : stéréo resserrée")
	SoundSettings.cycle_profile()
	_ok(SoundSettings.profile_id() == "nuit" and AudioServer.is_bus_effect_enabled(0, 0) and not AudioServer.is_bus_effect_enabled(0, 1), "nuit : compresseur")
	SoundSettings.cycle_profile()
	_ok(SoundSettings.profile_id() == "enceintes", "le profil revient au premier")
	Son.set_focused(false)
	_ok(AudioServer.is_bus_mute(0), "fenêtre au second plan : son coupé")
	SoundSettings.background = true
	Son.apply_settings()
	_ok(not AudioServer.is_bus_mute(0), "son hors de la fenêtre activé : le son continue")
	Son.set_focused(true)
	SoundSettings.reset()


func _test_synth() -> void:
	var recipe: Dictionary = Son.cue_def("ui_valider")["synth"]
	var buf := SoundSynth.samples(recipe)
	var want := (float(recipe["step"]) * 2.0 + float(recipe["len"])) * SoundSynth.rate()
	_ok(absf(buf.size() - want) < 4.0, "durée de l'esquisse")
	var peak := 0.0
	for v in buf:
		peak = maxf(peak, absf(v))
	_ok(peak > 0.05 and peak <= 1.0, "esquisse audible et sans saturation (%.2f)" % peak)
	_ok(absf(buf[buf.size() - 1]) < 0.01, "l'esquisse finit en silence")
	_ok(SoundSynth.stream(recipe) == SoundSynth.stream(recipe), "esquisse gardée en cache")
	_ok(SoundSynth.stream(recipe, 12.0) != SoundSynth.stream(recipe), "une transposition donne un autre son")
	for id in Son.data()["cues"]:
		var def: Dictionary = Son.cue_def(id)
		var b := SoundSynth.samples(def["synth"])
		var p := 0.0
		for v in b:
			p = maxf(p, absf(v))
		_ok(p > 0.02 and p <= 1.0, "esquisse de %s audible (%.2f)" % [id, p])


func _test_cues() -> void:
	for id in Son.data()["cues"]:
		var def: Dictionary = Son.cue_def(id)
		_ok(AudioServer.get_bus_index(String(def["bus"])) > 0, "repère %s sur un bus connu" % id)
		_ok(String(def.get("label", "")) != "", "repère %s nommé" % id)
		_ok(Son.source_of(id) != "", "repère %s : un fichier ou une esquisse" % id)
		_ok(Son.stream_of(id) != null, "repère %s : un son" % id)
	_ok(Son.source_of("inconnu") == "" and Son.stream_of("inconnu") == null, "repère inconnu : rien")
	Son.heard.clear()
	Son.cue("ui_valider")
	Son.cue("")
	_ok(",".join(Son.heard) == "ui_valider", "journal des repères")
	_ok(Son.data()["speed_semitones"].size() == GameClock.SECONDS_PER_DAY.size(), "une hauteur par cran de vitesse")


func _test_buttons() -> void:
	var cfg: Dictionary = Son.data()["buttons"]
	for k in ["default", "tab", "toggle", "hover"]:
		_ok(Son.data()["cues"].has(String(cfg[k])), "bouton « %s » : repère connu" % k)
	var b := Button.new()
	_ok(Son.button_cue(b) == "ui_clic", "bouton simple")
	b.toggle_mode = true
	_ok(Son.button_cue(b) == "ui_bascule", "bouton à bascule")
	b.theme_type_variation = &"TabButton"
	_ok(Son.button_cue(b) == "ui_onglet", "onglet")
	b.set_meta("son", "ui_valider")
	_ok(Son.button_cue(b) == "ui_valider", "repère choisi par le bouton")
	b.set_meta("son", "")
	_ok(Son.button_cue(b) == "", "bouton muet")
	b.free()
	# Le chef d'orchestre donne leur son aux boutons qui entrent dans l'arbre.
	var tree := Engine.get_main_loop() as SceneTree
	var dir := SoundDirector.new()
	tree.root.add_child(dir)
	Son._director = dir
	var b2 := Button.new()
	tree.root.add_child(b2)
	_ok(b2.has_meta(&"son_pose"), "bouton pris en charge à son entrée dans l'arbre")
	Son.heard.clear()
	b2.pressed.emit()
	dir._flush()
	_ok(",".join(Son.heard) == "ui_clic", "un clic joue le repère du bouton")
	Son.heard.clear()
	b2.pressed.emit()
	Son.cue("ui_ouvrir")
	dir._flush()
	_ok(",".join(Son.heard) == "ui_ouvrir", "le clic cède la place à l'ouverture d'un écran")
	Son.heard.clear()
	b2.mouse_entered.emit()
	_ok(Son.heard.is_empty(), "survol muet d'origine")
	SoundSettings.hover = true
	b2.mouse_entered.emit()
	_ok(",".join(Son.heard) == "ui_survol", "survol sonore une fois le réglage activé")
	SoundSettings.hover = false
	Son.heard.clear()
	dir._on_speed(4)
	dir._on_pause(true, GameClock)
	_ok(",".join(Son.heard) == "temps_vitesse,temps_pause", "le cadran du temps a ses repères")
	b2.free()
	dir.free()
	Son._director = null


func _test_announces() -> void:
	for fam in Announce.data()["families"]:
		_ok(Son.data()["announce"]["families"].has(fam), "famille %s : une esquisse à elle" % fam)
	_ok(Son.announce_recipe("guerre", 0).is_empty(), "une Chronique ne sonne pas")
	var last := 0
	for g in [1, 2, 3]:
		var n := SoundSynth.samples(Son.announce_recipe("guerre", g)).size()
		_ok(n > last, "gravité %d : son plus ample" % g)
		last = n
	_ok(Son.announce_recipe("guerre", 3)["w"] != Son.announce_recipe("diplomatie", 3)["w"], "le timbre suit la famille")
	_ok(Son.announce_recipe("famille_inconnue", 2)["notes"].size() == 3, "famille inconnue : esquisse commune")
	_ok(String(Son.data()["duck"]["trigger"]) == String(Son.data()["announce"]["bus"]), "les annonces sonnent sur le bus qui fait baisser la musique")


func _test_options() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var panel := OptionsPanel.new()
	tree.root.add_child(panel)
	_ok(panel.volume_boxes.size() == Son.data()["volumes"].size(), "onglet Son : une ligne par volume")
	panel.show_tab("sound")
	_ok(panel.tab == "sound", "onglet Son ouvert")
	var box := panel.volume_boxes["Musique"] as Button
	_ok(box.text == "70 %", "volume affiché (%s)" % box.text)
	box.pressed.emit()
	_ok(box.text == "80 %" and is_equal_approx(SoundSettings.volume("Musique"), 0.8), "un clic passe au cran suivant")
	panel._profile.pressed.emit()
	_ok(panel._profile.text == "Casque", "profil d'écoute changé depuis les Options")
	panel._hover.pressed.emit()
	_ok(SoundSettings.hover, "sons de survol activés depuis les Options")
	panel.reset_defaults()
	_ok(box.text == "70 %" and not SoundSettings.hover and SoundSettings.profile_id() == "enceintes", "valeurs par défaut")
	panel.free()
