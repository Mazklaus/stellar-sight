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
	_test_files()
	_test_map()
	_test_screens()
	_test_ceiling()
	_test_peoples()
	_test_music()
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


## Fichiers son posés dans assets/sounds (outils du son, P5 et P6) : chacun a sa fiche d'origine dans
## origines.json (outil, licence) et ne dépasse pas le niveau de référence de son dossier. Les niveaux
## sont mesurés par tools/audio/son.py au moment où il pose le fichier.
func _test_files() -> void:
	var levels: Dictionary = Son.data()["levels"]
	_ok(float(levels["carte"]) <= float(levels["musique"]) - 10.0, "les sons de la carte sont réglés nettement sous la musique")
	_ok(float(levels["ecran"]) <= float(levels["musique"]) - 10.0, "les lieux des écrans aussi")
	var good := {"outil": "essai", "licence": "CC0", "lufs": -32.0}
	_ok(_file_fault("carte/x", good, levels) == "", "fiche complète et niveau tenu : rien à redire")
	_ok(_file_fault("carte/x", {}, levels) != "", "un fichier sans fiche est refusé")
	_ok(_file_fault("carte/x", {"outil": "essai", "licence": "", "lufs": -32.0}, levels) != "", "un fichier sans licence est refusé")
	_ok(_file_fault("carte/x", {"outil": "essai", "licence": "CC0", "lufs": -25.0}, levels) != "", "un son de carte trop fort est refusé")
	_ok(_file_fault("carte/x", {"outil": "essai", "licence": "CC0", "lufs": -32.0, "crete": -8.0}, levels) != "", "un fond dont un claquement ressort est refusé")
	_ok(_file_fault("ui/x", {"outil": "essai", "licence": "CC0", "lufs": -20.0, "crete": -1.0}, levels) != "", "une crête au ras du plafond est refusée")
	_ok(_file_fault("carte/x", {"outil": "essai", "licence": "CC0", "lufs": -32.0, "crete": -20.0, "grave": 0.9}, levels) != "", "un fond fait surtout de grondement est refusé")
	_ok(_file_fault("dossier_neuf/x", {"outil": "essai", "licence": "CC0", "lufs": -20.0}, levels) == "", "dossier inconnu : niveau par défaut")
	var root := String(Son.data()["dir"])
	var origins := {}
	if FileAccess.file_exists(root + "origines.json"):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(root + "origines.json"))
		origins = parsed if parsed is Dictionary else {}
	for id in _sound_files(root, ""):
		var fault := _file_fault(id, origins.get(id, {}), levels)
		_ok(fault == "", "fichier %s : %s" % [id, fault if fault != "" else "bon"])


func _file_fault(id: String, card: Dictionary, levels: Dictionary) -> String:
	if card.is_empty():
		return "pas de fiche d'origine"
	if String(card.get("outil", "")) == "" or String(card.get("licence", "")) == "":
		return "fiche sans outil ou sans licence"
	var top := float(levels.get(id.get_slice("/", 0), levels["default"]))
	if float(card.get("lufs", 0.0)) > top + 1.5:
		return "trop fort (%.1f LUFS pour %.1f)" % [float(card.get("lufs", 0.0)), top]
	var cap: Dictionary = Son.data()["ceiling"]
	var peak := float(cap["peak_db"])
	var crest: Dictionary = cap["crest_db"]
	if crest.has(id.get_slice("/", 0)):
		peak = minf(peak, top + float(crest[id.get_slice("/", 0)]))
	if float(card.get("grave", 0.0)) > float(cap.get("sub_share_by_dir", {}).get(id.get_slice("/", 0), cap["sub_share"])):
		return "trop de grondement sous 60 Hz"
	if float(card.get("crete", -100.0)) > peak + 0.5:
		return "crête trop haute (%.1f dB pour %.1f)" % [float(card.get("crete", 0.0)), peak]
	return ""


func _sound_files(root: String, sub: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(root + sub)
	if dir == null:
		return out
	for d in dir.get_directories():
		out.append_array(_sound_files(root, sub + d + "/"))
	for f in dir.get_files():
		if f.get_extension() in ["ogg", "wav"]:
			out.append(sub + f.get_basename())
	return out


## Lot 2 : les sons localisés de la carte.
func _test_map() -> void:
	var c: Dictionary = MapSound.cfg()
	var gate: Array = c["gate"]["star"]
	_ok(float(gate[0]) >= GalaxyView.TIER_SYSTEM_ZOOM, "une étoile ne s'entend qu'au palier Système")
	_ok(float(c["vol"]) <= -6.0, "une voix de la carte reste basse")
	var star := {"sound": "etoile_yellow", "kind": "star", "pos": Vector2.ZERO, "weight": 1.0}
	var o := {"center": Vector2.ZERO, "half": 540.0, "half_w": 960.0}
	o["zoom"] = GalaxyView.TIER_REGION_ZOOM
	_ok(MapSound.mix([star], o).is_empty(), "palier Région : la musique seule")
	o["zoom"] = float(gate[0])
	_ok(MapSound.mix([star], o).is_empty(), "au seuil de zoom, encore rien")
	o["zoom"] = float(gate[1])
	var m := MapSound.mix([star], o)
	_ok(m.size() == 1 and is_equal_approx(float(m[0]["gain"]), 1.0) and is_zero_approx(float(m[0]["pan"])), "de très près et au centre : son plein, au milieu")
	o["zoom"] = (float(gate[0]) + float(gate[1])) * 0.5
	var half := MapSound.mix([star], o)
	_ok(half.size() == 1 and float(half[0]["gain"]) > 0.2 and float(half[0]["gain"]) < 0.8, "entre les deux zooms, le son monte")
	o["zoom"] = float(gate[1])
	var right := star.duplicate()
	right["pos"] = Vector2(100.0, 0.0)
	m = MapSound.mix([right], o)
	_ok(m.size() == 1 and float(m[0]["pan"]) > 0.1 and float(m[0]["gain"]) < 1.0, "source à droite : plus faible, vers la droite")
	right["pos"] = Vector2(-100.0, 0.0)
	_ok(float(MapSound.mix([right], o)[0]["pan"]) < -0.1, "source à gauche")
	right["pos"] = Vector2(2000.0, 0.0)
	_ok(MapSound.mix([right], o).is_empty(), "hors de portée : rien")
	var two := MapSound.mix([star, right, star.duplicate()], o)
	_ok(two.size() == 1, "deux étoiles du même type : une seule voix")
	var many: Array = []
	for i in 30:
		many.append({"sound": "s%d" % i, "kind": "star", "pos": Vector2(float(i), 0.0), "weight": 1.0})
	var cut := MapSound.mix(many, o)
	_ok(cut.size() == int(c["voices"]) and String(cut[0]["sound"]) == "s0", "douze voix au plus, les plus proches d'abord")
	o["factor"] = float(c["lens"])
	_ok(is_equal_approx(float(MapSound.mix([star], o)[0]["gain"]), float(c["lens"])), "lentille : sources en retrait")
	o["factor"] = 0.0
	_ok(MapSound.mix([star], o).is_empty(), "écran ouvert : la carte se tait")
	_ok(MapSound.mix([{"sound": "monde_ocean", "gain": 0.4, "pan": -0.3}], {}).size() == 1, "vue système : source déjà placée")
	# Chaque étoile, monde, coque et état a son fond, fichier ou esquisse, et il boucle.
	var ids: Array = ["etat_ville", "etat_industrie", "etat_siege"]
	for t in ["yellow", "red", "white", "blue_giant", "neutron", "black_hole"]:
		ids.append("etoile_" + t)
	for t: String in GameData.planet_types():
		if not t.begins_with("_"):
			ids.append("monde_" + t)
	for t in ["fuseau", "nef", "brique", "treillis", "bricole", "organique", "cristal", "roc"]:
		ids.append("flotte_" + t)
	var mute: Array = []
	for id: String in ids:
		var s := MapSound.stream_for(id)
		var loops := s is AudioStreamWAV and (s as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_FORWARD
		loops = loops or (s is AudioStreamOggVorbis and (s as AudioStreamOggVorbis).loop)
		if not loops:
			mute.append(id)
	_ok(mute.is_empty(), "chaque source de la carte a un son en boucle (%s)" % ", ".join(mute))
	var bed := SoundSynth.bed_samples(c["beds"]["etoile"])
	var peak := 0.0
	var step := 0.0
	for i in bed.size():
		peak = maxf(peak, absf(bed[i]))
		if i > 0:
			step = maxf(step, absf(bed[i] - bed[i - 1]))
	_ok(peak > 0.05 and peak <= 1.0, "esquisse de fond audible, sans saturer")
	_ok(absf(bed[0] - bed[bed.size() - 1]) <= step * 1.5, "esquisse de fond : la reprise ne claque pas")
	# Le nœud : une voix par son, relâchée quand la source s'éloigne.
	MapSound.build_buses()
	var n := AudioServer.bus_count
	MapSound.build_buses()
	_ok(AudioServer.bus_count == n and AudioServer.get_bus_send(AudioServer.get_bus_index("CarteV0")) == &"Carte", "voix de la carte versées dans le bus Carte")
	var node := MapSound.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(node)
	node.set_process(false)
	node.retarget([{"sound": "etoile_red", "gain": 0.5, "pan": 0.2}, {"sound": "flotte_nef", "gain": 0.3, "pan": 0.0}])
	_ok(node.playing().size() == 2 and is_equal_approx(float(node.playing()["etoile_red"]), 0.5), "deux sources, deux voix")
	node.retarget([{"sound": "etoile_red", "gain": 0.8, "pan": 0.0}])
	_ok(is_equal_approx(float(node.playing()["etoile_red"]), 0.8) and is_zero_approx(float(node.playing()["flotte_nef"])), "la voix suit sa source, l'autre s'éteint")
	node._clock = 100.0
	node._process(10.0)
	_ok(node.playing().size() == 1, "une voix éteinte est rendue")
	_ok(node.sources().is_empty(), "sans carte, aucune source")
	node.free()
	# Une vraie partie : étoiles explorées seulement, flottes, vue système.
	var st := GameState.create(11)
	var gv := GalaxyView.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(gv)
	gv.set_state(st)
	gv.fog = false
	var all := MapSound.map_emitters(gv)
	var stars := all.filter(func(e: Dictionary) -> bool: return e["kind"] == "star")
	var fleets := all.filter(func(e: Dictionary) -> bool: return e["kind"] == "fleet")
	_ok(stars.size() == st.galaxy.systems.size(), "sans brouillard, chaque étoile est une source")
	_ok(not fleets.is_empty() and String(fleets[0]["sound"]).begins_with("flotte_"), "les flottes sont des sources")
	gv.fog = true
	gv._seen = Fleets.visible_systems(st, 0)
	var known := MapSound.map_emitters(gv).filter(func(e: Dictionary) -> bool: return e["kind"] == "star")
	_ok(known.size() > 0 and known.size() < stars.size(), "sous le brouillard, seules les étoiles explorées s'entendent")
	var home := st.galaxy.get_system(st.galaxy.get_planet(st.get_empire(0).capital_planet).system_id)
	var close := MapSound.mix(MapSound.map_emitters(gv), {"center": home.position, "zoom": float(gate[1]), "half": 540.0, "half_w": 960.0})
	_ok(not close.is_empty() and String(close[0]["sound"]) == "etoile_" + home.star_type, "au-dessus de la capitale, son étoile domine")
	gv.free()
	var screen := SystemScreen.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(screen)
	screen.open(st, home, 0)
	screen.select_planet(st.get_empire(0).capital_planet)
	var inside := MapSound.mix(MapSound.system_emitters(screen), {})
	var cap := "monde_" + st.galaxy.get_planet(st.get_empire(0).capital_planet).type
	_ok(not inside.is_empty() and String(inside[0]["sound"]) == cap, "vue système : la planète choisie passe devant")
	_ok(inside.any(func(e: Dictionary) -> bool: return String(e["sound"]).begins_with("etoile_")), "vue système : l'étoile en fond")
	screen.free()


## Lot 3 : les lieux des écrans.
func _test_screens() -> void:
	var c: Dictionary = ScreenSound.cfg()
	var places: Dictionary = c["places"]
	var missing: Array = []
	var mute: Array = []
	for dom: Dictionary in UiDomains.DOMAINS:
		for tab: Array in dom["tabs"]:
			for addr: String in tab[1]:
				if not places.has(addr):
					missing.append(addr)
					continue
				var s := MapSound.stream_for("lieu_" + String(places[addr][0]), String(c["dir"]))
				var loops := s is AudioStreamWAV and (s as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_FORWARD
				if not (loops or (s is AudioStreamOggVorbis and (s as AudioStreamOggVorbis).loop)):
					mute.append(addr)
	_ok(missing.is_empty(), "chaque onglet d'un domaine a son lieu (%s)" % ", ".join(missing))
	_ok(mute.is_empty(), "chaque lieu a un son en boucle (%s)" % ", ".join(mute))
	_ok(String(ScreenSound.place_of("order")[0]) == "rue" and String(ScreenSound.place_of("trade")[0]) == "quai", "un écran à onglets s'ouvre sur son lieu d'origine")
	_ok(String(ScreenSound.place_of("inconnu")[0]) == "", "pas de lieu pour un écran inconnu")
	var st := GameState.create(11)
	var rest := float(c["rest"])
	_ok(is_equal_approx(ScreenSound.agitation(st, 0, ""), rest) and is_equal_approx(ScreenSound.agitation(null, 0, "stability"), rest), "sans donnée, le lieu est au repos")
	for vary in ["stability", "corruption", "debt", "deficit", "fleets", "routes", "colonies", "senate", "throne", "court", "contact"]:
		var a := ScreenSound.agitation(st, 0, vary)
		_ok(a >= 0.0 and a <= 1.0, "agitation « %s » entre 0 et 1" % vary)
	_ok(String(ScreenSound.place_of("senate", st, 0)[0]) in ["senat", "ruche"], "le Sénat a son lieu selon le régime")
	var swap: Dictionary = c["regime_places"]["ruche"]
	_ok(MapSound.stream_for("lieu_" + String(swap["senate"]), String(c["dir"])) != null, "la ruche bourdonne à la place de l'hémicycle")
	var calm := ScreenSound.agitation(st, 0, "deficit")
	st.get_empire(0).starving = true
	_ok(ScreenSound.agitation(st, 0, "deficit") > calm, "une famine agite la salle des comptes")
	var before := ScreenSound.agitation(st, 0, "fleets")
	var mine: Fleet = null
	for fid: int in st.fleets:
		if (st.fleets[fid] as Fleet).owner == 0:
			mine = st.fleets[fid]
			break
	_ok(mine != null and before < 1.0, "des flottes à quai, un pont calme")
	var node := ScreenSound.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(node)
	node.set_process(false)
	node.enter("rue")
	_ok(node.place() == "rue", "ouvrir un écran installe son lieu")
	node.enter("tresor")
	_ok(node.place() == "tresor" and node._sounds.has("rue"), "changer d'onglet : le lieu d'avant s'efface en fondu")
	node._clock = 100.0
	node._process(10.0)
	_ok(not node._sounds.has("rue"), "le lieu quitté se tait")
	node.enter("")
	_ok(node.place() == "", "fermer l'écran rend la carte")
	node.free()
	var es := EmpireScreens.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(es)
	es.open("economy", st, 0)
	_ok(String(ScreenSound.place_of(UiDomains.address(es))[0]) == "comptes", "le Bilan ouvre la salle des comptes")
	es.open("order", st, 0)
	_ok(String(ScreenSound.place_of(UiDomains.address(es))[0]) in ["rue", "bureaux", "tresor"], "l'écran de l'Ordre ouvre un de ses lieux")
	es.free()


## Garde-fous de niveau : rien ne sort trop fort.
func _test_ceiling() -> void:
	var cap: Dictionary = Son.data()["ceiling"]
	Son.build_buses()
	var last := AudioServer.get_bus_effect_count(0) - 1
	var lim := AudioServer.get_bus_effect(0, last) as AudioEffectHardLimiter
	_ok(lim != null and AudioServer.is_bus_effect_enabled(0, last), "un limiteur ferme la sortie générale")
	_ok(lim != null and is_equal_approx(lim.ceiling_db, float(cap["master_db"])) and lim.ceiling_db <= -1.0, "plafond de sortie sous 0 dB")
	for d in Son.data()["volumes"]:
		_ok(float(d["default"]) <= 0.8, "volume d'origine de %s sans surplus" % d["bus"])
	var loud: Array = []
	for id: String in Son.data()["cues"]:
		var def: Dictionary = Son.cue_def(id)
		if not def.has("synth"):
			continue
		var m := Son.measure(SoundSynth.samples(def["synth"]))
		var vol := float(def.get("vol", 0.0))
		if float(m["peak_db"]) + vol > float(cap["cue_peak_db"]) or float(m["rms_db"]) + vol > float(cap["cue_rms_db"]):
			loud.append("%s %.1f/%.1f" % [id, float(m["peak_db"]) + vol, float(m["rms_db"]) + vol])
	_ok(loud.is_empty(), "aucun repère au-dessus du plafond (%s)" % ", ".join(loud))
	var ann: Dictionary = Son.data()["announce"]
	var worst := -100.0
	for fam: String in ann.get("families", {}):
		var m := Son.measure(SoundSynth.samples(Son.announce_recipe(fam, 3)))
		worst = maxf(worst, float(m["peak_db"]) + float(ann.get("vol", -9.0)))
	_ok(worst <= float(cap["cue_peak_db"]) + 3.0, "une fanfare reste sous le plafond (%.1f dB)" % worst)
	for spec: Array in [[MapSound.cfg(), "carte"], [ScreenSound.cfg(), "écrans"]]:
		var c: Dictionary = spec[0]
		var beds: Dictionary = MapSound.cfg()["beds"]
		var top := -100.0
		for k: String in beds:
			top = maxf(top, float(Son.measure(SoundSynth.bed_samples(beds[k]))["rms_db"]) + float(c["vol"]))
		_ok(top <= float(cap["bed_rms_db"]), "fonds (%s) sous le plafond (%.1f dB)" % [spec[1], top])
	_ok(float(Son.data()["levels"]["carte"]) + float(MapSound.cfg()["vol"]) <= float(Son.data()["levels"]["musique"]) - 20.0, "une voix de la carte joue au moins 20 dB sous la musique")
	_ok(float(Son.data()["levels"]["ecran"]) + float(ScreenSound.cfg()["vol"]) <= float(Son.data()["levels"]["musique"]) - 18.0, "un lieu joue au moins 18 dB sous la musique")


## Lot 4 : la signature sonore des peuples.
func _test_peoples() -> void:
	var c: Dictionary = PeopleSound.cfg()
	var cap: Dictionary = Son.data()["ceiling"]
	var seen := {}
	var loud: Array = []
	for f: Dictionary in GameData.factions():
		var id := String(f["id"])
		_ok(c["signatures"].has(id), "le peuple %s a sa signature" % id)
		if PeopleSound.is_mute(id):
			continue
		var j := PeopleSound.jingle(id)
		var key := "%s/%s/%s" % [j["w"], j["f"], j["notes"]]
		_ok(not seen.has(key), "l'indicatif de %s ne ressemble à aucun autre" % id)
		seen[key] = true
		for mood: String in c["moods"]:
			var m := Son.measure(SoundSynth.samples(PeopleSound.jingle(id, mood)))
			if float(m["peak_db"]) + float(c["vol"]) > float(cap["cue_peak_db"]) or float(m["rms_db"]) + float(c["vol"]) > float(cap["cue_rms_db"]):
				loud.append("%s/%s %.1f/%.1f" % [id, mood, float(m["peak_db"]) + float(c["vol"]), float(m["rms_db"]) + float(c["vol"])])
		var sp := Son.measure(SoundSynth.samples(PeopleSound.speech(id, "Nous saluons votre maison, et nous attendons.")))
		if float(sp["peak_db"]) + float(c["speech_vol"]) > float(cap["cue_peak_db"]):
			loud.append("parole de %s" % id)
	_ok(loud.is_empty(), "indicatifs et paroles sous le plafond (%s)" % ", ".join(loud))
	_ok(PeopleSound.is_mute("silencieux") and PeopleSound.jingle("silencieux").is_empty() and PeopleSound.speech("silencieux", "Rien.").is_empty(), "les Silencieux se taisent")
	var peace := PeopleSound.jingle("ossarane", "peace")
	var war := PeopleSound.jingle("ossarane", "war")
	var ally := PeopleSound.jingle("ossarane", "alliance")
	_ok(float(war["f"]) < float(peace["f"]) and (war["notes"] as Array).size() == (peace["notes"] as Array).size() + 1, "en guerre : plus grave, avec un coup d'ouverture")
	_ok((ally["notes"] as Array).size() == (peace["notes"] as Array).size() + 1 and float(ally["f"]) == float(peace["f"]), "allié : le même motif, doublé à l'octave")
	_ok(float(PeopleSound.jingle("ossarane", "cold")["lp"]) < float(peace["lp"]), "guerre froide : assombri")
	var short := PeopleSound.speech("vael", "Soit.")
	var long := PeopleSound.speech("vael", "La Concorde a reçu votre proposition, elle en débat, et sa réponse viendra quand chacun aura parlé.")
	_ok((long["notes"] as Array).size() > (short["notes"] as Array).size(), "un texte long se dit en plus de syllabes")
	_ok(float(long["step"]) * float((long["notes"] as Array).size()) <= float(c["speech"]["max"]) + 0.3, "la parole reste brève")
	_ok(str(PeopleSound.speech("vael", "Soit.")) == str(short), "le même texte se dit toujours de la même façon")
	_ok((long["notes"] as Array).has(-60.0), "la ponctuation fait des silences")
	_ok(not PeopleSound.jingle("peuple_inconnu_42").is_empty(), "un peuple créé reçoit une signature")
	Son.heard.clear()
	SoundSettings.speech = true
	PeopleSound.hail("teyl", "war", "En guerre.")
	_ok(Son.heard.has("peuple:teyl:war"), "saluer un peuple joue son indicatif")
	var st := GameState.create(11)
	var es := EmpireScreens.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(es)
	es.open("diplomacy", st, 0)
	Son.heard.clear()
	var other := 1
	es.diplo_table.empire_selected.emit(other)
	_ok(Son.heard.any(func(h: String) -> bool: return h.begins_with("peuple:" + st.get_empire(other).faction_id)), "choisir un empire sur l'anneau fait entendre son peuple")
	es.free()
	var op := OptionsPanel.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(op)
	op.show_tab("sound")
	_ok(op._speech != null, "réglage « Parole des peuples » dans les Options")
	op.free()


## Lot 5 : la musique.
func _test_music() -> void:
	var c: Dictionary = MusicPlayer.cfg()
	var ids := {}
	for s: Dictionary in c["states"]:
		ids[String(s["id"])] = String(s["fallback"])
	for id: String in ids:
		_ok(ids[id] == "" or ids.has(ids[id]), "le repli de l'état %s existe" % id)
	var st := GameState.create(11)
	_ok(MusicPlayer.state_of(null, 0, true) == "menu" and MusicPlayer.state_of(st, 0, true) == "menu", "au menu, la musique du menu")
	var base := MusicPlayer.state_of(st, 0, false)
	_ok(base in ["paix", "tension", "crise"], "une partie qui commence n'est pas en guerre")
	st.get_empire(0).wars.append(1)
	_ok(MusicPlayer.state_of(st, 0, false) == "guerre", "en guerre, la musique de guerre")
	st.winner = {"empire": 0}
	_ok(MusicPlayer.state_of(st, 0, false) == "victoire", "victoire du joueur")
	st.winner = {"empire": 1}
	_ok(MusicPlayer.state_of(st, 0, false) == "defaite", "victoire d'un autre : défaite")
	for id: String in ids:
		_ok(ids.has(MusicPlayer.playable(id)) or MusicPlayer.playable(id) == "", "l'état %s retombe sur un état connu" % id)
	MusicPlayer._lists = {"paix": ["paix_1", "paix_2", "paix_3"], "guerre": [], "tension": [], "crise": []}
	_ok(MusicPlayer.playable("crise") == "paix", "un état sans morceau prend ceux de son repli")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var last := ""
	var twice := false
	for i in 40:
		var n := MusicPlayer.next_piece("paix", last, rng)
		twice = twice or n == last
		last = n
	_ok(not twice, "jamais deux fois de suite le même morceau")
	MusicPlayer._lists = {"paix": ["paix_1"]}
	_ok(MusicPlayer.next_piece("paix", "paix_1") == "paix_1", "un seul morceau : il revient")
	MusicPlayer._lists = {}
	SoundSettings.density = ""
	_ok(SoundSettings.density_id() == "continue" and is_zero_approx(MusicPlayer.gap(rng)), "d'origine, la musique ne s'arrête jamais")
	SoundSettings.cycle_density()
	_ok(SoundSettings.density_id() == "normale" and MusicPlayer.gap(rng) >= 15.0, "densité normale : un silence entre deux morceaux")
	SoundSettings.cycle_density()
	SoundSettings.cycle_density()
	_ok(SoundSettings.density_id() == "continue", "le réglage fait le tour")
	var levels: Dictionary = Son.data()["levels"]
	_ok(float(levels["musique"]) + float(c["vol"]) <= -16.0, "la musique elle-même reste à un niveau de fond")
	var node := MusicPlayer.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(node)
	node.set_process(false)
	node._process(0.6)
	_ok(String(node.now()["state"]) in ["", "menu", "paix"], "sans partie, la musique se place sur le menu ou son repli")
	node.free()
