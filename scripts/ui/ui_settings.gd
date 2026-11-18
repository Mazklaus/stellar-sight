class_name UiSettings
extends RefCounted
## Réglages du joueur sur ce poste (plein écran, pause automatique). Ce ne sont pas des données
## de partie : ils ne vont ni dans la sauvegarde ni sur le réseau. Fichier user://settings.cfg.

const PATH := "user://settings.cfg"

static var fullscreen := false
## Mettre le jeu en pause à l'ouverture d'un menu d'empire (et reprendre à la fermeture).
static var auto_pause_menus := false
## Échelle de toute l'interface (lisibilité sur grands écrans).
static var ui_scale := 1.0
const UI_SCALES := [1.0, 1.25, 1.5]
## Détail des vues de bataille (visuel des combats, prop. 5) : "sobre", "normal" ou "riche".
static var replay_detail := "normal"
const REPLAY_DETAILS := ["sobre", "normal", "riche"]
## Échelle des batailles au sol (visuel des combats, prop. 23 amendée) : figurines par régiment.
static var battle_scale := "escarmouche"
const BATTLE_SCALES := ["escarmouche", "bataille", "grande"]
## Coques de peuple (prop. 38) : silhouette de la coque de tête sur l'icône de flotte de la carte.
static var fleet_silhouettes := false
static var _loaded := false


static func load_settings() -> void:
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	fullscreen = bool(cfg.get_value("display", "fullscreen", false))
	auto_pause_menus = bool(cfg.get_value("game", "auto_pause_menus", false))
	ui_scale = float(cfg.get_value("display", "ui_scale", 1.0))
	replay_detail = String(cfg.get_value("display", "replay_detail", "normal"))
	if not REPLAY_DETAILS.has(replay_detail):
		replay_detail = "normal"
	fleet_silhouettes = bool(cfg.get_value("display", "fleet_silhouettes", false))
	battle_scale = String(cfg.get_value("display", "battle_scale", "escarmouche"))
	if not BATTLE_SCALES.has(battle_scale):
		battle_scale = "escarmouche"


static func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(PATH)  # garde les autres sections (annonces : AnnounceSettings)
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.set_value("game", "auto_pause_menus", auto_pause_menus)
	cfg.set_value("display", "ui_scale", ui_scale)
	cfg.set_value("display", "replay_detail", replay_detail)
	cfg.set_value("display", "battle_scale", battle_scale)
	cfg.set_value("display", "fleet_silhouettes", fleet_silhouettes)
	cfg.save(PATH)


static func apply() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		tree.root.content_scale_factor = ui_scale
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)


static func toggle_fullscreen() -> void:
	fullscreen = not fullscreen
	apply()
	save_settings()


## Passe à l'échelle d'interface suivante (100 %, 125 %, 150 %).
static func cycle_ui_scale() -> void:
	var i := UI_SCALES.find(ui_scale)
	ui_scale = UI_SCALES[(i + 1) % UI_SCALES.size()]
	apply()
	save_settings()


## Indice du détail des replays (0 sobre, 1 normal, 2 riche).
static func replay_detail_level() -> int:
	return maxi(0, REPLAY_DETAILS.find(replay_detail))


static func cycle_replay_detail() -> void:
	replay_detail = REPLAY_DETAILS[(replay_detail_level() + 1) % REPLAY_DETAILS.size()]
	save_settings()


static func battle_scale_level() -> int:
	return maxi(0, BATTLE_SCALES.find(battle_scale))


static func cycle_battle_scale() -> void:
	battle_scale = BATTLE_SCALES[(battle_scale_level() + 1) % BATTLE_SCALES.size()]
	save_settings()
