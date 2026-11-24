class_name UiSettings
extends RefCounted
## Réglages du joueur sur ce poste (plein écran, pause automatique). Ce ne sont pas des données
## de partie : ils ne vont ni dans la sauvegarde ni sur le réseau. Fichier user://settings.cfg.

const PATH := "user://settings.cfg"

static var fullscreen := false
## Mettre le jeu en pause à l'ouverture d'un menu d'empire (et reprendre à la fermeture).
static var auto_pause_menus := false
## Panneau de droite de la carte réduit à sa barre d'alertes (refonte, A4).
static var side_reduced := false
## Échelle de toute l'interface (lisibilité sur grands écrans).
static var ui_scale := 1.0
const UI_SCALES := [1.0, 1.25, 1.5]
## Détail des vues de bataille (visuel des combats, prop. 5) : "sobre", "normal" ou "riche".
static var replay_detail := "normal"
const REPLAY_DETAILS := ["sobre", "normal", "riche"]
## Échelle des batailles au sol (visuel des combats, prop. 23 amendée) : figurines par régiment.
static var battle_scale := "escarmouche"
const BATTLE_SCALES := ["escarmouche", "bataille", "grande"]
## Infobulles (glossaire en jeu, prop. 11, 12 et 16) : délai d'apparition, durée avant qu'elles se
## figent, mode de verrouillage ("minuterie" ou "action" : clic molette ou Maj), termes colorés.
static var tip_delay := 0.35
const TIP_DELAYS := [0.15, 0.35, 0.6, 1.0]
static var tip_lock := 0.8
const TIP_LOCKS := [0.4, 0.8, 1.5]
static var tip_lock_mode := "minuterie"
const TIP_LOCK_MODES := ["minuterie", "action"]
static var glossary_links := true
## L'annonce qui présente les mots colorés a déjà été montrée (prop. 22).
static var glossary_intro_done := false
## Coques de peuple (prop. 38) : silhouette de la coque de tête sur l'icône de flotte de la carte.
static var fleet_silhouettes := false
## Tour par tour (étude d'équilibrage, C5) : ce qui interrompt un tour en cours de résolution, en plus
## d'une bataille : une flotte étrangère armée qui entre chez vous, une déclaration de guerre, un
## événement à choix.
static var turn_stop_intrusion := true
static var turn_stop_war := true
static var turn_stop_events := true
## La fin de tour prévient de ce qui attend encore (refonte, A6 ; voir TurnChecks).
static var turn_warn_todo := true
static var _loaded := false


static func load_settings() -> void:
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	fullscreen = bool(cfg.get_value("display", "fullscreen", false))
	auto_pause_menus = bool(cfg.get_value("game", "auto_pause_menus", false))
	side_reduced = bool(cfg.get_value("display", "side_reduced", false))
	ui_scale = float(cfg.get_value("display", "ui_scale", 1.0))
	replay_detail = String(cfg.get_value("display", "replay_detail", "normal"))
	if not REPLAY_DETAILS.has(replay_detail):
		replay_detail = "normal"
	fleet_silhouettes = bool(cfg.get_value("display", "fleet_silhouettes", false))
	battle_scale = String(cfg.get_value("display", "battle_scale", "escarmouche"))
	if not BATTLE_SCALES.has(battle_scale):
		battle_scale = "escarmouche"
	tip_delay = float(cfg.get_value("tips", "delay", 0.35))
	tip_lock = float(cfg.get_value("tips", "lock", 0.8))
	tip_lock_mode = String(cfg.get_value("tips", "lock_mode", "minuterie"))
	if not TIP_LOCK_MODES.has(tip_lock_mode):
		tip_lock_mode = "minuterie"
	glossary_links = bool(cfg.get_value("tips", "glossary_links", true))
	glossary_intro_done = bool(cfg.get_value("tips", "intro_done", false))
	turn_stop_intrusion = bool(cfg.get_value("turns", "stop_intrusion", true))
	turn_stop_war = bool(cfg.get_value("turns", "stop_war", true))
	turn_stop_events = bool(cfg.get_value("turns", "stop_events", true))
	turn_warn_todo = bool(cfg.get_value("turns", "warn_todo", true))


static func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(PATH)  # garde les autres sections (annonces : AnnounceSettings)
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.set_value("game", "auto_pause_menus", auto_pause_menus)
	cfg.set_value("display", "side_reduced", side_reduced)
	cfg.set_value("display", "ui_scale", ui_scale)
	cfg.set_value("display", "replay_detail", replay_detail)
	cfg.set_value("display", "battle_scale", battle_scale)
	cfg.set_value("tips", "delay", tip_delay)
	cfg.set_value("tips", "lock", tip_lock)
	cfg.set_value("tips", "lock_mode", tip_lock_mode)
	cfg.set_value("tips", "glossary_links", glossary_links)
	cfg.set_value("tips", "intro_done", glossary_intro_done)
	cfg.set_value("display", "fleet_silhouettes", fleet_silhouettes)
	cfg.set_value("turns", "stop_intrusion", turn_stop_intrusion)
	cfg.set_value("turns", "stop_war", turn_stop_war)
	cfg.set_value("turns", "stop_events", turn_stop_events)
	cfg.set_value("turns", "warn_todo", turn_warn_todo)
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


## Infobulles : passe au réglage suivant, puis prévient le gestionnaire (TipManager).
static func cycle_tip_delay() -> void:
	tip_delay = TIP_DELAYS[(maxi(0, TIP_DELAYS.find(tip_delay)) + 1) % TIP_DELAYS.size()]
	_tips_changed()


static func cycle_tip_lock() -> void:
	tip_lock = TIP_LOCKS[(maxi(0, TIP_LOCKS.find(tip_lock)) + 1) % TIP_LOCKS.size()]
	_tips_changed()


static func cycle_tip_lock_mode() -> void:
	tip_lock_mode = TIP_LOCK_MODES[(maxi(0, TIP_LOCK_MODES.find(tip_lock_mode)) + 1) % TIP_LOCK_MODES.size()]
	_tips_changed()


static func toggle_glossary_links() -> void:
	glossary_links = not glossary_links
	_tips_changed()


static func _tips_changed() -> void:
	save_settings()
	if TipManager.instance != null:
		TipManager.instance.apply_settings()
