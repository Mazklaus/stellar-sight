extends Node2D
## Point d'entrée : crée la simulation, la vue, la caméra et l'interface (barre d'empire, vue système,
## menus d'empire, menu principal, menu pause), et traduit les entrées du joueur en réglages
## d'horloge, en navigation ou en ordres.
## Rien ici ne modifie l'état de partie directement : tout passe par Simulation.submit().

const SYSTEM_COUNT := 150
const GALAXY_RADIUS := 1800.0
const PICK_RADIUS_PX := 14.0
const START_ZOOM := 0.22
## Zoom de départ, centré sur le système d'origine du joueur.
const HOME_ZOOM := 0.45
## Zoom derrière le menu principal, et vitesse de dérive de la caméra.
const MENU_ZOOM := 0.3
const MENU_DRIFT := Vector2(14.0, 5.0)
## Identifiant du joueur local. En multijoueur, chaque machine aura le sien.
const LOCAL_PLAYER := 0

var simulation: Simulation
## Fichier de sauvegarde rapide (F5 / F9). Les tests le redirigent ailleurs.
var save_path := SaveGame.QUICKSAVE_PATH
## Faction du joueur local pour les nouvelles parties (choisie dans le menu principal).
var player_faction := "ossarane"
## Ouvrir le menu principal au lancement (les tests et les captures le désactivent).
var start_with_menu := true
## Vrai dès que le joueur a lancé ou chargé une partie (la galaxie derrière le menu n'en est pas une).
var game_in_progress := false
## Raccourci vers la galaxie de la partie en cours.
var galaxy: Galaxy:
	get:
		return simulation.state.galaxy if simulation else null

var _view: GalaxyView
var _camera: GalaxyCamera
var _hud: Hud
var _system_screen: SystemScreen
var _empire_screens: EmpireScreens
var _main_menu: MainMenu
var _pause_menu: PauseMenu
## État de la pause avant l'ouverture du menu pause (ou d'un menu d'empire en pause automatique).
var _paused_before := false
var _auto_paused := false


func _ready() -> void:
	randomize()
	UiSettings.load_settings()
	UiSettings.apply()
	get_tree().root.theme = UiTheme.theme()
	_view = GalaxyView.new()
	_view.viewer = LOCAL_PLAYER
	add_child(_view)
	_camera = GalaxyCamera.new()
	add_child(_camera)
	_camera.make_current()

	_hud = Hud.new()
	_hud.layer = 2  # au-dessus de la vue système
	add_child(_hud)
	_hud.open_system_requested.connect(open_system_view)
	_hud.screen_requested.connect(toggle_empire_screen)
	_hud.menu_requested.connect(open_pause_menu)
	_hud.pause_toggled.connect(GameClock.toggle_pause)
	_hud.speed_requested.connect(GameClock.set_speed)
	_hud.close_system_requested.connect(close_system_view)
	_hud.lens_changed.connect(func(l: String) -> void:
		_view.lens = l
		_view.queue_redraw())

	_system_screen = SystemScreen.new()
	add_child(_system_screen)
	_system_screen.close_requested.connect(close_system_view)
	_system_screen.cycle_requested.connect(cycle_system)
	_system_screen.rename_requested.connect(_on_rename_requested)
	_system_screen.colonize_requested.connect(func(planet_id: int, kind: String) -> void:
		simulation.submit(SimCommands.colonize(LOCAL_PLAYER, planet_id, kind)))
	_system_screen.build_requested.connect(func(planet_id: int, building_id: String) -> void:
		simulation.submit(SimCommands.build(LOCAL_PLAYER, planet_id, building_id)))

	_empire_screens = EmpireScreens.new()
	add_child(_empire_screens)
	_empire_screens.close_requested.connect(close_empire_screen)
	_empire_screens.screen_changed.connect(func(id: String) -> void: _hud.bar.set_open_screen(id))
	_empire_screens.planet_requested.connect(func(pid: int) -> void:
		close_empire_screen()
		open_system_view(galaxy.get_planet(pid).system_id, pid))

	_pause_menu = PauseMenu.new()
	add_child(_pause_menu)
	_pause_menu.resume_requested.connect(close_pause_menu)
	_pause_menu.save_requested.connect(save_game)
	_pause_menu.load_requested.connect(func() -> void:
		close_pause_menu()
		load_game())
	_pause_menu.main_menu_requested.connect(func() -> void:
		close_pause_menu()
		open_main_menu())
	_pause_menu.quit_requested.connect(func() -> void: get_tree().quit())

	_main_menu = MainMenu.new()
	add_child(_main_menu)
	_main_menu.new_game_requested.connect(func(faction_id: String, seed_value: int) -> void:
		player_faction = faction_id
		new_game(seed_value)
		game_in_progress = true
		close_main_menu()
		var me := simulation.state.get_empire(LOCAL_PLAYER)
		_hud.notify("%s : que la chronique commence." % me.display_name(), "good"))
	_main_menu.resume_requested.connect(close_main_menu)
	_main_menu.continue_requested.connect(func() -> void:
		if load_game():
			close_main_menu())
	_main_menu.quit_requested.connect(func() -> void: get_tree().quit())

	UiTheme.apply_to(self)
	new_game(randi())
	if start_with_menu:
		open_main_menu()
	else:
		game_in_progress = true


func new_game(seed_value: int) -> void:
	_start(GameState.create(seed_value, SYSTEM_COUNT, GALAXY_RADIUS, player_faction))
	# On commence chez soi : caméra sur le système d'origine, fiche ouverte.
	var me := simulation.state.get_empire(LOCAL_PLAYER)
	if me:
		var home := galaxy.get_planet(me.capital_planet).system_id
		_camera.stop_glide()
		_camera.position = galaxy.get_system(home).position
		_camera.zoom = Vector2(HOME_ZOOM, HOME_ZOOM)
		_select(home)
	else:
		_camera.position = Vector2.ZERO
		_camera.zoom = Vector2(START_ZOOM, START_ZOOM)


func save_game() -> void:
	if SaveGame.save_state(simulation.state, save_path) == OK:
		_hud.notify("Partie sauvegardée (%s)" % GameCalendar.date_string(simulation.state.tick), "good")
	else:
		_hud.notify("Échec de la sauvegarde : %s" % SaveGame.last_error, "bad")


## Recharge la sauvegarde rapide. Renvoie false (avec un message) si c'est impossible.
func load_game() -> bool:
	var state := SaveGame.load_state(save_path)
	if state == null:
		_hud.notify("Chargement impossible : %s" % SaveGame.last_error, "bad")
		return false
	_start(state)
	game_in_progress = true
	var me := state.get_empire(LOCAL_PLAYER)
	if me:
		_select(galaxy.get_planet(me.capital_planet).system_id)
		_camera.position = galaxy.get_system(_view.selected_id).position
	_hud.notify("Partie chargée (%s)" % GameCalendar.date_string(state.tick), "good")
	return true


# --- Vue système ------------------------------------------------------------------------------

## Ouvre l'écran dédié d'un système, sur une planète donnée si planet_id >= 0.
func open_system_view(id: int, planet_id := -1) -> void:
	var s := galaxy.get_system(id) if galaxy else null
	if s == null:
		return
	if is_empire_screen_open():
		close_empire_screen()
	_select(id)
	_system_screen.open(simulation.state, s, LOCAL_PLAYER)
	if planet_id >= 0 and s.planet_ids.has(planet_id):
		_system_screen.select_planet(planet_id)
	_hud.set_system_mode(true)
	# La carte est cachée et ne réagit plus (caméra, survol) tant que la vue système est ouverte.
	_view.visible = false
	_update_map_input()


func close_system_view() -> void:
	if not _system_screen.is_open():
		return
	_system_screen.close()
	_hud.set_system_mode(false)
	_view.visible = true
	_update_map_input()
	_select(_view.selected_id)


func is_system_view_open() -> bool:
	return _system_screen != null and _system_screen.is_open()


## Passe au système suivant (1) ou précédent (-1) de l'empire : dans la vue système si elle est
## ouverte, sinon sur la carte (sélection et glissement de la caméra).
func cycle_system(step: int) -> void:
	var current := _system_screen.system_id if is_system_view_open() else _view.selected_id
	_go_to_system(EmpireReport.cycle_system(simulation.state, LOCAL_PLAYER, current, step))


## Revient au système de la capitale.
func go_to_capital() -> void:
	var me := simulation.state.get_empire(LOCAL_PLAYER)
	if me:
		_go_to_system(galaxy.get_planet(me.capital_planet).system_id)


func _go_to_system(id: int) -> void:
	if id < 0:
		return
	if is_system_view_open():
		open_system_view(id)
	else:
		_select(id)
		_camera.glide_to(galaxy.get_system(id).position, maxf(_camera.zoom.x, HOME_ZOOM))


# --- Menus d'empire ---------------------------------------------------------------------------

## Ouvre un menu d'empire ("economy", "colonies"), ou le ferme s'il est déjà affiché.
func toggle_empire_screen(screen_id: String) -> void:
	if _empire_screens.is_open() and _empire_screens.current == screen_id:
		close_empire_screen()
		return
	var sc := _screen_info(screen_id)
	if not sc.get("ready", false):
		_hud.notify(String(sc.get("why", "Bientôt.")))
		_hud.bar.set_open_screen(_empire_screens.current)
		return
	if not _empire_screens.is_open() and UiSettings.auto_pause_menus and not GameClock.paused:
		_auto_paused = true
		GameClock.set_paused(true)
	_hud.show_hover(null, Vector2.ZERO)
	_empire_screens.open(screen_id, simulation.state, LOCAL_PLAYER)
	_update_map_input()


func close_empire_screen() -> void:
	if not _empire_screens.is_open():
		return
	_empire_screens.close()
	_hud.bar.set_open_screen("")
	if _auto_paused:
		_auto_paused = false
		GameClock.set_paused(false)
	_update_map_input()


func is_empire_screen_open() -> bool:
	return _empire_screens != null and _empire_screens.is_open()


func _screen_info(screen_id: String) -> Dictionary:
	for sc: Dictionary in EmpireBar.SCREENS:
		if sc["id"] == screen_id:
			return sc
	return {}


# --- Menu principal et menu pause -------------------------------------------------------------

func open_main_menu() -> void:
	close_system_view()
	close_empire_screen()
	GameClock.set_paused(true)
	_hud.visible = false
	_camera.stop_glide()
	_camera.zoom = Vector2(MENU_ZOOM, MENU_ZOOM)
	var label := ""
	if SaveGame.exists(save_path):
		label = Time.get_datetime_string_from_unix_time(int(FileAccess.get_modified_time(save_path)), true)
	_main_menu.open(game_in_progress, SaveGame.exists(save_path), label)
	_update_map_input()


func close_main_menu() -> void:
	_main_menu.close()
	_hud.visible = true
	_update_map_input()


func open_pause_menu() -> void:
	if _pause_menu.is_open() or _main_menu.is_open():
		return
	_paused_before = GameClock.paused
	GameClock.set_paused(true)
	_hud.show_hover(null, Vector2.ZERO)
	_pause_menu.open(GameClock.date_string())
	_update_map_input()


func close_pause_menu() -> void:
	if not _pause_menu.is_open():
		return
	_pause_menu.close()
	GameClock.set_paused(_paused_before)
	_update_map_input()


## Un menu plein écran (principal, pause ou d'empire) recouvre la carte.
func is_modal_open() -> bool:
	return _main_menu.is_open() or _pause_menu.is_open() or is_empire_screen_open()


## La caméra de la carte ne réagit que si la carte est visible et rien ne la recouvre.
func _update_map_input() -> void:
	var active := not is_system_view_open() and not is_modal_open()
	_camera.set_process(active)
	_camera.set_process_unhandled_input(active)
	if not active:
		_hud.show_hover(null, Vector2.ZERO)


# --- Partie -----------------------------------------------------------------------------------

func _start(state: GameState) -> void:
	if is_system_view_open():
		close_system_view()
	close_empire_screen()
	simulation = Simulation.new(state)
	simulation.command_applied.connect(_on_command_applied)
	simulation.command_rejected.connect(func(_cmd: Dictionary, reason: String) -> void:
		_hud.notify("Ordre refusé : %s" % reason, "bad"))
	simulation.chronicle_added.connect(_hud.show_chronicle)
	simulation.ticked.connect(func(_tick: int) -> void: _refresh_all())
	_view.set_state(state)
	_hud.set_state(state, LOCAL_PLAYER)
	_hud.show_chronicle(state.chronicle.back() if not state.chronicle.is_empty() else {})
	GameClock.attach(simulation)


func _refresh_all() -> void:
	_view.queue_redraw()
	_hud.refresh()
	_system_screen.refresh()
	_empire_screens.refresh()


func _on_rename_requested(system_id: int, new_name: String) -> void:
	simulation.submit(SimCommands.rename_system(LOCAL_PLAYER, system_id, new_name))


func _on_command_applied(_cmd: Dictionary) -> void:
	_refresh_all()
	if not simulation.state.chronicle.is_empty():
		_hud.show_chronicle(simulation.state.chronicle.back())


func _process(delta: float) -> void:
	if galaxy == null:
		return
	if _main_menu.is_open():
		_camera.position += MENU_DRIFT * delta  # la galaxie dérive doucement derrière le menu
		return
	if is_system_view_open() or is_modal_open():
		return
	var id := _pick_system()
	if id != _view.hovered_id:
		_view.hovered_id = id
		_view.queue_redraw()
	_hud.show_hover(galaxy.get_system(id) if id >= 0 else null, get_viewport().get_mouse_position())


# --- Entrées ----------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and not is_system_view_open() and not is_modal_open():
		var picked := _pick_system_at(mb.position)
		if mb.double_click and picked >= 0:
			open_system_view(picked)
		else:
			_select(picked)
		return

	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_F11:
		UiSettings.toggle_fullscreen()
		return
	if _main_menu.is_open():
		if key.keycode == KEY_ESCAPE:
			if not _main_menu.back() and game_in_progress:
				close_main_menu()
		return
	if _pause_menu.is_open():
		if key.keycode == KEY_ESCAPE and not _pause_menu.back():
			close_pause_menu()
		elif key.keycode == KEY_F5:
			save_game()
		elif key.keycode == KEY_F9:
			close_pause_menu()
			load_game()
		return

	match key.keycode:
		KEY_ESCAPE:
			if is_empire_screen_open():
				close_empire_screen()
			elif is_system_view_open():
				close_system_view()
			elif _view.selected_id >= 0:
				_select(-1)
			else:
				open_pause_menu()
		KEY_F1:
			toggle_empire_screen("economy")
		KEY_F2:
			toggle_empire_screen("colonies")
		KEY_F3:
			toggle_empire_screen("research")
		KEY_F4:
			toggle_empire_screen("diplomacy")
		KEY_ENTER, KEY_KP_ENTER:
			if not is_system_view_open() and not is_empire_screen_open():
				open_system_view(_view.selected_id)
		KEY_L:
			if not is_system_view_open():
				_hud.set_lens("" if _hud.lens == "economy" else "economy")
		KEY_TAB:
			cycle_system(-1 if key.shift_pressed else 1)
		KEY_SPACE:
			GameClock.toggle_pause()
		KEY_F5:
			save_game()
		KEY_F9:
			load_game()
		KEY_LEFT, KEY_RIGHT:
			if is_system_view_open():
				_system_screen.select_adjacent_planet(-1 if key.keycode == KEY_LEFT else 1)
		_:
			if key.physical_keycode == KEY_H:
				go_to_capital()
				return
			# Touches physiques 1 à 5 (rangée du haut, même sur AZERTY) ou pavé numérique.
			var speed := _speed_from_key(key)
			if speed >= 0:
				GameClock.set_speed(speed)


func _select(id: int) -> void:
	_view.selected_id = id
	_view.queue_redraw()
	_hud.show_system(galaxy.get_system(id), simulation.state)


func _speed_from_key(key: InputEventKey) -> int:
	if key.physical_keycode >= KEY_1 and key.physical_keycode <= KEY_5:
		return key.physical_keycode - KEY_1
	if key.keycode >= KEY_KP_1 and key.keycode <= KEY_KP_5:
		return key.keycode - KEY_KP_1
	return -1


func _pick_system() -> int:
	return galaxy.find_nearest(get_global_mouse_position(), PICK_RADIUS_PX / _camera.zoom.x)


## Système sous une position écran (celle d'un événement de clic, par exemple).
func _pick_system_at(screen_pos: Vector2) -> int:
	var world_pos := get_viewport().get_canvas_transform().affine_inverse() * screen_pos
	return galaxy.find_nearest(world_pos, PICK_RADIUS_PX / _camera.zoom.x)
