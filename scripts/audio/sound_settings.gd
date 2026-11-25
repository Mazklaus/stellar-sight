class_name SoundSettings
extends RefCounted
## Réglages du son sur ce poste (étude du son, bloc K) : un volume par bus réglable, le profil d'écoute,
## le son quand la fenêtre n'a plus la main, les sons de survol. Fichier user://settings.cfg, section
## « sound », à côté de UiSettings et d'AnnounceSettings.

const PATH := "user://settings.cfg"

## Volume par bus, de 0 à 1. Un bus absent prend sa valeur par défaut (data/audio.json).
static var volumes := {}
static var profile := ""
## Le son continue quand la fenêtre du jeu n'est plus au premier plan.
static var background := false
## Un son au survol des boutons (K4 : coupé d'origine).
static var hover := false
## Les peuples parlent leur langue quand on s'adresse à eux (Q3 : réglable).
static var speech := true
## Densité de la musique (E1) : "" vaut le réglage d'origine, « continue ».
static var density := ""
## Les tests coupent l'écriture du fichier.
static var persist := true


static func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	var v: Variant = cfg.get_value("sound", "volumes", {})
	volumes = v if v is Dictionary else {}
	profile = String(cfg.get_value("sound", "profile", ""))
	background = bool(cfg.get_value("sound", "background", false))
	hover = bool(cfg.get_value("sound", "hover", false))
	speech = bool(cfg.get_value("sound", "speech", true))
	density = String(cfg.get_value("sound", "density", ""))


static func save_settings() -> void:
	if not persist:
		return
	var cfg := ConfigFile.new()
	cfg.load(PATH)  # garde les autres sections
	cfg.set_value("sound", "volumes", volumes)
	cfg.set_value("sound", "profile", profile)
	cfg.set_value("sound", "background", background)
	cfg.set_value("sound", "hover", hover)
	cfg.set_value("sound", "speech", speech)
	cfg.set_value("sound", "density", density)
	cfg.save(PATH)


static func reset() -> void:
	volumes = {}
	profile = ""
	background = false
	hover = false
	speech = true
	density = ""
	save_settings()
	Son.apply_settings()


static func volume_def(bus: String) -> Dictionary:
	for d in GameData.audio().get("volumes", []):
		if String(d["bus"]) == bus:
			return d
	return {}


static func volume(bus: String) -> float:
	if volumes.has(bus):
		return clampf(float(volumes[bus]), 0.0, 1.0)
	return float(volume_def(bus).get("default", 1.0))


static func set_volume(bus: String, value: float) -> void:
	volumes[bus] = clampf(value, 0.0, 1.0)
	save_settings()
	Son.apply_settings()


## Cran suivant (ou précédent) de la liste volume_steps ; après le dernier, on revient au premier.
static func cycle_volume(bus: String, dir := 1) -> void:
	var steps: Array = GameData.audio().get("volume_steps", [0.0, 0.5, 1.0])
	var cur := volume(bus)
	var at := 0
	for i in steps.size():
		if absf(float(steps[i]) - cur) < absf(float(steps[at]) - cur):
			at = i
	set_volume(bus, float(steps[posmod(at + dir, steps.size())]))


static func volume_label(bus: String) -> String:
	var v := volume(bus)
	return "Coupé" if v <= 0.001 else "%d %%" % roundi(v * 100.0)


static func profile_id() -> String:
	var all: Dictionary = GameData.audio().get("profiles", {})
	if all.has(profile):
		return profile
	return String(GameData.audio().get("default_profile", "enceintes"))


static func profile_label() -> String:
	return String(GameData.audio().get("profiles", {}).get(profile_id(), {}).get("label", profile_id()))


static func cycle_profile() -> void:
	var ids: Array = GameData.audio().get("profiles", {}).keys()
	if ids.is_empty():
		return
	profile = String(ids[(ids.find(profile_id()) + 1) % ids.size()])
	save_settings()
	Son.apply_settings()


static func density_id() -> String:
	var all: Dictionary = GameData.audio().get("music", {}).get("density", {})
	return density if all.has(density) else String(GameData.audio().get("music", {}).get("default_density", "continue"))


static func density_label() -> String:
	return String(GameData.audio().get("music", {}).get("density", {}).get(density_id(), {}).get("label", density_id()))


static func cycle_density(dir := 1) -> void:
	var ids: Array = GameData.audio().get("music", {}).get("density", {}).keys()
	if ids.is_empty():
		return
	density = String(ids[posmod(ids.find(density_id()) + dir, ids.size())])
	save_settings()
