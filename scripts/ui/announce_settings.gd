class_name AnnounceSettings
extends RefCounted
## Réglages des annonces sur ce poste (étude de la fenêtre d'événement, prop. 13, 27, 29 à 32, 38) :
## apparence et pause par type, préréglage, vitesse des animations, son. Ce ne sont pas des données de
## partie : fichier user://settings.cfg, section « announce », comme UiSettings.

const PATH := "user://settings.cfg"
const AUTO := -1
const PRESETS := ["chroniqueur", "stratege", "silence"]
const ANIMS := ["normale", "rapide", "instant"]

## Apparence imposée par type (AUTO = selon la distance, sinon 0 Chronique … 3 Fanfare).
static var looks := {}
## Pause imposée par type (absent = selon la gravité : la Fanfare met en pause).
static var pauses := {}
## Types qui ne s'ouvrent plus d'eux-mêmes (interrupteur de la fenêtre, prop. 13).
static var no_auto := {}
static var preset := "stratege"
static var anim := "normale"
static var sound := true
## Les tests coupent l'écriture du fichier (ils ne doivent pas toucher aux réglages du joueur).
static var persist := true


static func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	looks = cfg.get_value("announce", "looks", {})
	pauses = cfg.get_value("announce", "pauses", {})
	no_auto = cfg.get_value("announce", "no_auto", {})
	preset = String(cfg.get_value("announce", "preset", "stratege"))
	if not PRESETS.has(preset):
		preset = "stratege"
	anim = String(cfg.get_value("announce", "anim", "normale"))
	if not ANIMS.has(anim):
		anim = "normale"
	sound = bool(cfg.get_value("announce", "sound", true))


static func save_settings() -> void:
	if not persist:
		return
	var cfg := ConfigFile.new()
	cfg.load(PATH)  # garde les autres sections (UiSettings)
	cfg.set_value("announce", "looks", looks)
	cfg.set_value("announce", "pauses", pauses)
	cfg.set_value("announce", "no_auto", no_auto)
	cfg.set_value("announce", "preset", preset)
	cfg.set_value("announce", "anim", anim)
	cfg.set_value("announce", "sound", sound)
	cfg.save(PATH)


static func reset() -> void:
	looks = {}
	pauses = {}
	no_auto = {}
	preset = "stratege"
	anim = "normale"
	sound = true
	save_settings()


## Gravité finale d'une annonce pour ce lecteur : défaut du type (Announce.gravity), puis l'apparence
## imposée par le joueur ; un type toujours visible qui le concerne ne descend jamais sous l'Avis.
static func final_gravity(state: GameState, rec: Dictionary, viewer: int) -> int:
	var kind := String(rec["k"])
	var g := Announce.gravity(state, rec, viewer)
	var forced := int(looks.get(kind, AUTO))
	if forced != AUTO:
		g = forced
	if Announce.always(kind) and Announce.distance(state, rec, viewer) == Announce.SELF:
		g = maxi(g, Announce.AVIS)
	return clampi(g, Announce.MURMUR, Announce.FANFARE)


static func look_of(kind: String) -> int:
	return int(looks.get(kind, AUTO))


## Apparence suivante dans le cycle Auto, Chronique, Avis, Fenêtre, Fanfare (écran Options).
static func cycle_look(kind: String) -> void:
	var v := look_of(kind) + 1
	if v > Announce.FANFARE:
		v = AUTO
	if v == AUTO:
		looks.erase(kind)
	else:
		looks[kind] = v
	save_settings()


static func look_label(kind: String) -> String:
	var v := look_of(kind)
	return "Auto" if v == AUTO else Announce.gravity_label(v)


## La fenêtre de cette annonce met-elle la partie en pause ? (prop. 26)
static func pauses_for(kind: String, gravity: int) -> bool:
	if pauses.has(kind):
		return bool(pauses[kind])
	return gravity >= Announce.FANFARE


static func toggle_pause(kind: String, gravity_default: int) -> void:
	pauses[kind] = not pauses_for(kind, gravity_default)
	save_settings()


static func auto_open(kind: String) -> bool:
	return not no_auto.has(kind)


static func set_auto_open(kind: String, on: bool) -> void:
	if on:
		no_auto.erase(kind)
	else:
		no_auto[kind] = true
	save_settings()


static func cycle_preset() -> void:
	preset = PRESETS[(PRESETS.find(preset) + 1) % PRESETS.size()]
	save_settings()


static func preset_label() -> String:
	return String(Announce.data()["presets"].get(preset, {}).get("label", preset))


static func cycle_anim() -> void:
	anim = ANIMS[(ANIMS.find(anim) + 1) % ANIMS.size()]
	save_settings()


static func anim_label() -> String:
	return String(Announce.data()["anim"].get(anim, {}).get("label", anim))


## Durée des fondus d'ouverture (prop. 27).
static func anim_seconds() -> float:
	return float(Announce.data()["anim"].get(anim, {}).get("seconds", 0.25))
