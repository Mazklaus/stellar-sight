class_name Son
extends RefCounted
## Le son du jeu (étude du son, blocs A et J). Tout passe par ici : les bus sont construits en code
## d'après data/audio.json, et un repère sonore se joue par Son.cue("ui_valider"). Un repère cherche un
## fichier (assets/sounds/<dossier>/<id>.ogg ou .wav, variantes <id>_1 à <id>_5 tirées au hasard), sinon
## il joue son esquisse de synthèse (SoundSynth), sinon il se tait. Déposer un fichier suffit donc à
## remplacer une esquisse, sans toucher au code.
## Son.setup() est appelé une fois au lancement (main.gd). Sans lui (tests de règles, outils), cue() ne
## fait que tenir le journal `heard`.

const VARIANTS := 5

## Derniers repères demandés (tests, outil de contrôle).
static var heard: Array[String] = []
static var _director: SoundDirector
static var _files := {}
static var _focused := true


static func data() -> Dictionary:
	return GameData.audio()


static func cue_def(id: String) -> Dictionary:
	return data().get("cues", {}).get(id, {})


## Construit les bus, applique les réglages et pose le chef d'orchestre sous la racine.
static func setup() -> void:
	build_buses()
	SoundSettings.load_settings()
	apply_settings()
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or (_director != null and is_instance_valid(_director)):
		return
	_director = SoundDirector.new()
	_director.name = "SoundDirector"
	tree.root.add_child.call_deferred(_director)


## Bus de data/audio.json, créés s'ils manquent. Un bus se déverse dans son « send » ; la musique et
## l'ambiance reçoivent le compresseur qui les baisse quand une annonce sonne (A3) ; le bus Master
## porte les deux effets des profils d'écoute (K2), allumés par apply_settings().
static func build_buses() -> void:
	for b in data().get("buses", []):
		var id := String(b["id"])
		if AudioServer.get_bus_index(id) >= 0:
			continue
		AudioServer.add_bus()
		var at := AudioServer.bus_count - 1
		AudioServer.set_bus_name(at, id)
		AudioServer.set_bus_send(at, String(b.get("send", "Master")))
	var duck: Dictionary = data().get("duck", {})
	for target in duck.get("targets", []):
		var at := AudioServer.get_bus_index(String(target))
		if at < 0 or _effect_at(at, "AudioEffectCompressor") >= 0:
			continue
		var c := AudioEffectCompressor.new()
		c.threshold = float(duck.get("threshold_db", -30.0))
		c.ratio = float(duck.get("ratio", 6.0))
		c.attack_us = float(duck.get("attack_us", 40.0))
		c.release_ms = float(duck.get("release_ms", 600.0))
		c.sidechain = StringName(String(duck.get("trigger", "Annonces")))
		AudioServer.add_bus_effect(at, c)
	if _effect_at(0, "AudioEffectCompressor") < 0:
		AudioServer.add_bus_effect(0, AudioEffectCompressor.new())
	if _effect_at(0, "AudioEffectStereoEnhance") < 0:
		AudioServer.add_bus_effect(0, AudioEffectStereoEnhance.new())


static func _effect_at(bus: int, type: String) -> int:
	for i in AudioServer.get_bus_effect_count(bus):
		if AudioServer.get_bus_effect(bus, i).is_class(type):
			return i
	return -1


## Recopie les réglages (volumes, profil d'écoute, fenêtre au second plan) sur les bus.
static func apply_settings() -> void:
	for d in data().get("volumes", []):
		var bus := String(d["bus"])
		var at := AudioServer.get_bus_index(bus)
		if at < 0:
			continue
		var v := SoundSettings.volume(bus)
		var off := v <= 0.001
		if at == 0:
			off = off or not (_focused or SoundSettings.background)
		AudioServer.set_bus_mute(at, off)
		AudioServer.set_bus_volume_db(at, linear_to_db(maxf(v, 0.001)))
	var prof: Dictionary = data().get("profiles", {}).get(SoundSettings.profile_id(), {})
	var comp := _effect_at(0, "AudioEffectCompressor")
	if comp >= 0:
		var on := prof.has("ratio")
		AudioServer.set_bus_effect_enabled(0, comp, on)
		if on:
			var c := AudioServer.get_bus_effect(0, comp) as AudioEffectCompressor
			c.threshold = float(prof.get("threshold_db", -26.0))
			c.ratio = float(prof["ratio"])
			c.gain = float(prof.get("gain_db", 0.0))
	var wide := _effect_at(0, "AudioEffectStereoEnhance")
	if wide >= 0:
		var on := prof.has("pan_pullout")
		AudioServer.set_bus_effect_enabled(0, wide, on)
		if on:
			(AudioServer.get_bus_effect(0, wide) as AudioEffectStereoEnhance).pan_pullout = float(prof["pan_pullout"])


## La fenêtre du jeu a pris ou perdu la main (réglage « Son hors de la fenêtre »).
static func set_focused(on: bool) -> void:
	_focused = on
	apply_settings()


## Fichiers déposés pour un repère (aucun tant que l'habillage sonore n'est pas livré).
static func files_of(id: String) -> Array:
	if _files.has(id):
		return _files[id]
	var out: Array = []
	var dir := "%s%s/" % [String(data().get("dir", "res://assets/sounds/")), String(cue_def(id).get("dir", "ui"))]
	var names := [id]
	for i in VARIANTS:
		names.append("%s_%d" % [id, i + 1])
	for n in names:
		for ext in data().get("ext", ["ogg", "wav"]):
			var p := "%s%s.%s" % [dir, n, String(ext)]
			if ResourceLoader.exists(p):
				out.append(p)
				break
	_files[id] = out
	return out


## D'où vient le son d'un repère : "fichier", "esquisse" ou "" (muet ou inconnu).
static func source_of(id: String) -> String:
	if not files_of(id).is_empty():
		return "fichier"
	return "esquisse" if cue_def(id).has("synth") else ""


## Joue un repère. `semis` le transpose (crans de vitesse du cadran, par exemple).
static func cue(id: String, semis := 0.0) -> void:
	if id == "":
		return
	heard.append(id)
	if heard.size() > 64:
		heard.remove_at(0)
	if _director != null and is_instance_valid(_director):
		_director.play_cue(id, semis)


## Son d'un repère (fichier tiré parmi les variantes, sinon esquisse), ou null.
static func stream_of(id: String, semis := 0.0) -> AudioStream:
	var files := files_of(id)
	if not files.is_empty():
		return load(String(files[randi() % files.size()]))
	var def := cue_def(id)
	if def.has("synth"):
		return SoundSynth.stream(def["synth"], semis)
	return null


## Joue un son déjà chargé sur un bus (annonces, plus tard les voix et la carte).
static func play_stream(stream: AudioStream, bus: String, vol_db := 0.0, pitch := 1.0) -> void:
	if stream != null and _director != null and is_instance_valid(_director):
		_director.play(stream, bus, vol_db, pitch)


## Repère d'un bouton de l'interface (bloc "buttons") : son propre choix par set_meta("son", id), sinon
## onglet, bascule ou clic simple.
static func button_cue(b: BaseButton) -> String:
	if b.has_meta("son"):
		return String(b.get_meta("son"))
	var cfg: Dictionary = data().get("buttons", {})
	if b.theme_type_variation == &"TabButton":
		return String(cfg.get("tab", ""))
	if b.toggle_mode:
		return String(cfg.get("toggle", ""))
	return String(cfg.get("default", ""))


## Esquisse d'une annonce (F4) : la famille donne le timbre et le motif, la gravité le nombre de notes
## et leur durée. Rien pour une Chronique.
static func announce_recipe(family: String, gravity: int) -> Dictionary:
	var cfg: Dictionary = data().get("announce", {})
	var counts: Array = cfg.get("counts", [0, 1, 3, 5])
	var g := clampi(gravity, 0, counts.size() - 1)
	var n := int(counts[g])
	if n <= 0:
		return {}
	var out: Dictionary = (cfg.get("families", {}).get(family, cfg.get("default", {})) as Dictionary).duplicate()
	out["notes"] = (out.get("notes", [0]) as Array).slice(0, n)
	out["len"] = float((cfg.get("len", []) as Array)[g])
	out["step"] = float((cfg.get("step", []) as Array)[g])
	out["a"] = 0.008
	out["gain"] = 0.45
	return out


static func announce(family: String, gravity: int) -> void:
	var cfg: Dictionary = data().get("announce", {})
	var recipe := announce_recipe(family, gravity)
	if recipe.is_empty():
		return
	play_stream(SoundSynth.stream(recipe), String(cfg.get("bus", "Annonces")), float(cfg.get("vol", -9.0)))
