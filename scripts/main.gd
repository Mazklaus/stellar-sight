extends Node2D
## Point d'entrée : crée la simulation, la vue, la caméra et l'interface (barre d'empire, vue système,
## menus d'empire, menu principal, menu pause), et traduit les entrées du joueur en réglages
## d'horloge, en navigation ou en ordres.
## Rien ici ne modifie l'état de partie directement : tout passe par Simulation.submit().

const SYSTEM_COUNT := 150
const GALAXY_RADIUS := 1800.0
const PICK_RADIUS_PX := 14.0
const FLEET_PICK_RADIUS_PX := 11.0
## Au-delà de ce déplacement (pixels), un clic droit est un glissé de caméra, pas un ordre.
const RIGHT_CLICK_SLOP_PX := 6.0
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
## Flotte sélectionnée (-1 = aucune).
var selected_fleet := -1
var _right_press := Vector2(-1, -1)
## Flottes du joueur en route au tick précédent : pour annoncer leur arrivée.
var _fleets_moving := {}


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
	_hud.layer = 3  # au-dessus de la vue système et des écrans d'empire
	add_child(_hud)
	_hud.open_system_requested.connect(open_system_view)
	_hud.screen_requested.connect(toggle_empire_screen)
	_hud.menu_requested.connect(open_pause_menu)
	_hud.pause_toggled.connect(GameClock.toggle_pause)
	_hud.speed_requested.connect(GameClock.set_speed)
	_hud.close_system_requested.connect(close_system_view)
	_hud.fleet_action_requested.connect(_on_fleet_action)
	_hud.fleet_requested.connect(focus_fleet)
	_hud.fleet_system_requested.connect(func(fid: int) -> void:
		var f: Fleet = simulation.state.fleets.get(fid)
		if f:
			open_system_view(f.system_id if not f.is_moving() else f.next_system()))
	_hud.idle_fleet_requested.connect(func() -> void: cycle_idle_fleet(1))
	_hud.lens_changed.connect(func(l: String) -> void:
		_view.lens = l
		_view.queue_redraw())

	_system_screen = SystemScreen.new()
	add_child(_system_screen)
	_system_screen.close_requested.connect(close_system_view)
	_system_screen.cycle_requested.connect(cycle_system)
	_hud.system_mode_requested.connect(func(m: bool) -> void: _system_screen.set_manage_mode(m))
	_system_screen.mode_changed.connect(_hud.set_manage_tab)
	_system_screen.rename_requested.connect(_on_rename_requested)
	_system_screen.colonize_requested.connect(func(planet_id: int, kind: String) -> void:
		simulation.submit(SimCommands.colonize(LOCAL_PLAYER, planet_id, kind)))
	_system_screen.build_requested.connect(func(planet_id: int, building_id: String) -> void:
		simulation.submit(SimCommands.build(LOCAL_PLAYER, planet_id, building_id)))
	_system_screen.build_ship_requested.connect(func(planet_id: int, ship_id: String) -> void:
		simulation.submit(SimCommands.build_ship(LOCAL_PLAYER, planet_id, ship_id)))
	_system_screen.command_requested.connect(func(cmd: Dictionary) -> void: simulation.submit(cmd))

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
		GameClock.set_mode(_main_menu.time_mode, _main_menu.turn_days)
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
	if SaveGame.save_state(simulation.state, save_path, GameClock.settings()) == OK:
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
	GameClock.apply_settings(SaveGame.last_clock)
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
	if not Fleets.is_explored(simulation.state, LOCAL_PLAYER, id):
		_hud.notify("Système inexploré : envoyez d'abord un vaisseau y jeter un œil.")
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
	var sc := EmpireBar.screen_info(screen_id)
	if not sc.get("ready", false):
		_hud.notify(String(sc.get("why", "Bientôt.")))
		_hud.bar.set_open_screen(_empire_screens.current)
		return
	if not _empire_screens.is_open() and UiSettings.auto_pause_menus and not GameClock.paused:
		_auto_paused = true
		GameClock.set_paused(true)
	_hud.show_hover(null, Vector2.ZERO)
	_empire_screens.open(screen_id, simulation.state, LOCAL_PLAYER)
	_hud.set_empire_screen_open(true)
	_update_map_input()


func close_empire_screen() -> void:
	if not _empire_screens.is_open():
		return
	_empire_screens.close()
	_hud.bar.set_open_screen("")
	_hud.set_empire_screen_open(false)
	if _auto_paused:
		_auto_paused = false
		GameClock.set_paused(false)
	_update_map_input()


func is_empire_screen_open() -> bool:
	return _empire_screens != null and _empire_screens.is_open()




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
	simulation.ticked.connect(func(_tick: int) -> void:
		_announce_arrivals()
		_refresh_all())
	_view.set_state(state)
	_hud.set_state(state, LOCAL_PLAYER)
	select_fleet(-1)
	_fleets_moving = _moving_fleet_ids()
	_hud.show_chronicle(state.chronicle.back() if not state.chronicle.is_empty() else {})
	GameClock.attach(simulation)


func _refresh_all() -> void:
	if selected_fleet >= 0 and not simulation.state.fleets.has(selected_fleet):
		select_fleet(-1)  # flotte dissoute (vaisseau colon démonté, fusion)
	_view.queue_redraw()
	_hud.refresh()
	_system_screen.refresh()
	_empire_screens.refresh()


func _on_rename_requested(system_id: int, new_name: String) -> void:
	simulation.submit(SimCommands.rename_system(LOCAL_PLAYER, system_id, new_name))


func _on_command_applied(_cmd: Dictionary) -> void:
	_fleets_moving = _moving_fleet_ids()
	_refresh_all()
	if not simulation.state.chronicle.is_empty():
		_hud.show_chronicle(simulation.state.chronicle.back())


func _process(delta: float) -> void:
	if galaxy == null:
		return
	_view.day_fraction = GameClock.day_fraction()
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
		var fleet := _pick_fleet_at(mb.position)
		if fleet >= 0 and not mb.double_click:
			select_fleet(fleet)
			return
		var picked := _pick_system_at(mb.position)
		if mb.double_click and picked >= 0:
			open_system_view(picked)
		else:
			select_fleet(-1)
			_select(picked)
		return
	# Clic droit (sans glisser) avec une flotte sélectionnée : l'envoyer vers le système visé.
	if mb and mb.button_index == MOUSE_BUTTON_RIGHT and not is_system_view_open() and not is_modal_open():
		if mb.pressed:
			_right_press = mb.position
		elif _right_press.x >= 0.0 and mb.position.distance_to(_right_press) <= RIGHT_CLICK_SLOP_PX:
			_right_press = Vector2(-1, -1)
			order_fleet_to(_pick_system_at(mb.position))
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
			elif selected_fleet >= 0:
				select_fleet(-1)
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
			# Dans la vue système, Tab bascule vue orbitale / gestion ; sur la carte, il passe d'un système à l'autre.
			if is_system_view_open():
				_system_screen.toggle_mode()
			else:
				cycle_system(-1 if key.shift_pressed else 1)
		KEY_PAGEUP, KEY_PAGEDOWN:
			cycle_system(-1 if key.keycode == KEY_PAGEUP else 1)
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
			if key.physical_keycode == KEY_F and not is_system_view_open() and not is_empire_screen_open():
				cycle_fleet(-1 if key.shift_pressed else 1)
				return
			if key.physical_keycode == KEY_I and not is_system_view_open() and not is_empire_screen_open():
				cycle_idle_fleet(-1 if key.shift_pressed else 1)
				return
			if key.physical_keycode == KEY_E and selected_fleet >= 0 and not is_system_view_open() and not is_empire_screen_open():
				toggle_auto_explore(selected_fleet)
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
	return _view.pick_system(get_global_mouse_position(), PICK_RADIUS_PX / _camera.zoom.x)


## Système connu sous une position écran (celle d'un événement de clic, par exemple).
func _pick_system_at(screen_pos: Vector2) -> int:
	var world_pos := get_viewport().get_canvas_transform().affine_inverse() * screen_pos
	return _view.pick_system(world_pos, PICK_RADIUS_PX / _camera.zoom.x)


func _pick_fleet_at(screen_pos: Vector2) -> int:
	var world_pos := get_viewport().get_canvas_transform().affine_inverse() * screen_pos
	return _view.pick_fleet(world_pos, FLEET_PICK_RADIUS_PX / _camera.zoom.x)


# --- Flottes ----------------------------------------------------------------------------------

## Sélectionne une flotte (-1 : aucune). Sa fiche s'affiche et son trajet se dessine.
func select_fleet(fleet_id: int) -> void:
	selected_fleet = fleet_id
	_view.selected_fleet = fleet_id
	_view.queue_redraw()
	_hud.show_fleet(fleet_id)


## Envoie la flotte sélectionnée vers un système (si c'est la nôtre).
func order_fleet_to(system_id: int) -> void:
	var f: Fleet = simulation.state.fleets.get(selected_fleet)
	if f == null or f.owner != LOCAL_PLAYER or system_id < 0:
		return
	if simulation.submit(SimCommands.move_fleet(LOCAL_PLAYER, f.id, system_id)):
		var plan := Fleets.plan_route(simulation.state, f, system_id)
		var days := Fleets.route_days(simulation.state, f, plan)
		var where := galaxy.get_system(system_id).system_name if Fleets.is_explored(simulation.state, LOCAL_PLAYER, system_id) else "un système inexploré"
		if days == 0:
			_hud.notify("%s : reste à %s." % [f.fleet_name, where])
		else:
			_hud.notify("%s : cap sur %s (%d jour%s)." % [f.fleet_name, where, days, "s" if days > 1 else ""])


## Passe à la flotte suivante (1) ou précédente (-1) du joueur, et y glisse la caméra.
func cycle_fleet(step: int) -> void:
	var mine := Fleets.empire_fleets(simulation.state, LOCAL_PLAYER)
	if mine.is_empty():
		_hud.notify("Aucune flotte. Les chantiers spatiaux des colonies en construisent.")
		return
	var ids: Array[int] = []
	for f in mine:
		ids.append(f.id)
	focus_fleet(_cycle_id(ids, step))


## Passe à la prochaine flotte du joueur qui attend des ordres (à l'arrêt, sans exploration auto).
func cycle_idle_fleet(step: int) -> void:
	var ids: Array[int] = []
	for f in Fleets.idle_fleets(simulation.state, LOCAL_PLAYER):
		ids.append(f.id)
	if ids.is_empty():
		_hud.notify("Toutes vos flottes ont des ordres.")
		return
	focus_fleet(_cycle_id(ids, step))


## Identifiant suivant (ou précédent) de la flotte sélectionnée dans une liste triée.
## Si la flotte sélectionnée n'y est pas, on prend la première après elle.
func _cycle_id(ids: Array[int], step: int) -> int:
	var i := ids.find(selected_fleet)
	if i >= 0:
		return ids[posmod(i + step, ids.size())]
	if step > 0:
		for id in ids:
			if id > selected_fleet:
				return id
		return ids[0]
	for k in range(ids.size() - 1, -1, -1):
		if ids[k] < selected_fleet:
			return ids[k]
	return ids[-1]


## Sélectionne une flotte et glisse la caméra jusqu'à elle (liste des flottes, F, I).
func focus_fleet(fleet_id: int) -> void:
	if not simulation.state.fleets.has(fleet_id):
		return
	if is_system_view_open():
		close_system_view()
	select_fleet(fleet_id)
	_camera.glide_to(_view.fleet_world_position(fleet_id), maxf(_camera.zoom.x, HOME_ZOOM))


## Active ou coupe l'exploration automatique d'une flotte du joueur.
func toggle_auto_explore(fleet_id: int) -> void:
	var f: Fleet = simulation.state.fleets.get(fleet_id)
	if f == null or f.owner != LOCAL_PLAYER:
		return
	var order := "" if f.is_exploring() else Fleet.ORDER_EXPLORE
	if simulation.submit(SimCommands.set_fleet_order(LOCAL_PLAYER, fleet_id, order)):
		_hud.notify("%s : %s" % [f.fleet_name, "part explorer l'inconnu." if order != "" else "exploration automatique interrompue."])


func _moving_fleet_ids() -> Dictionary:
	var out := {}
	for f in Fleets.empire_fleets(simulation.state, LOCAL_PLAYER):
		if f.is_moving():
			out[f.id] = true
	return out


## Annonce les flottes du joueur arrivées à destination pendant le dernier tick
## (celles en exploration automatique repartent aussitôt : on ne les annonce pas).
func _announce_arrivals() -> void:
	var st := simulation.state
	for fid in _fleets_moving:
		var f: Fleet = st.fleets.get(fid)
		if f != null and not f.is_moving() and not f.is_exploring():
			_hud.notify("%s est arrivé à %s et attend vos ordres." % [f.fleet_name, galaxy.get_system(f.system_id).system_name])
	_fleets_moving = _moving_fleet_ids()


func _on_fleet_action(action: String, fleet_id: int) -> void:
	var st := simulation.state
	var f: Fleet = st.fleets.get(fleet_id)
	if f == null:
		return
	match action:
		"explore":
			toggle_auto_explore(fleet_id)
		"stop":
			simulation.submit(SimCommands.stop_fleet(LOCAL_PLAYER, fleet_id))
		"merge":
			for other in Fleets.fleets_at(st, f.system_id, LOCAL_PLAYER):
				if other.id != fleet_id:
					simulation.submit(SimCommands.merge_fleets(LOCAL_PLAYER, other.id, fleet_id))
		"split":
			# On détache un vaisseau de la classe la plus nombreuse (un éclaireur d'un groupe, par exemple).
			var best := ""
			for sid in GameData.ship_ids():
				if f.count(sid) > 0 and (best == "" or f.count(sid) > f.count(best)):
					best = sid
			simulation.submit(SimCommands.split_fleet(LOCAL_PLAYER, fleet_id, best))
		"colonize":
			# On ouvre le système sur la meilleure planète à revendiquer.
			var target := -1
			for pid in galaxy.get_system(f.system_id).planet_ids:
				if target == -1 and Economy.check_colonize(st, LOCAL_PLAYER, pid, Colony.KIND_COLONY) == "":
					target = pid
			for pid in galaxy.get_system(f.system_id).planet_ids:
				if target == -1 and Economy.check_colonize(st, LOCAL_PLAYER, pid, Colony.KIND_OUTPOST) == "":
					target = pid
			open_system_view(f.system_id, target)
