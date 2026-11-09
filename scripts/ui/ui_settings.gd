class_name UiSettings
extends RefCounted
## Réglages du joueur sur ce poste (plein écran, pause automatique). Ce ne sont pas des données
## de partie : ils ne vont ni dans la sauvegarde ni sur le réseau. Fichier user://settings.cfg.

const PATH := "user://settings.cfg"

static var fullscreen := false
## Mettre le jeu en pause à l'ouverture d'un menu d'empire (et reprendre à la fermeture).
static var auto_pause_menus := false
static var _loaded := false


static func load_settings() -> void:
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	fullscreen = bool(cfg.get_value("display", "fullscreen", false))
	auto_pause_menus = bool(cfg.get_value("game", "auto_pause_menus", false))


static func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.set_value("game", "auto_pause_menus", auto_pause_menus)
	cfg.save(PATH)


static func apply() -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)


static func toggle_fullscreen() -> void:
	fullscreen = not fullscreen
	apply()
	save_settings()
