class_name AnnounceCenter
extends Node
## Chef d'orchestre des annonces (étude de la fenêtre d'événement, prop. 9 à 14, 19 à 26, 33 à 37) :
## lit les annonces typées du registre (Announce), décide pour ce lecteur de leur sort (chronique seule,
## avis cliquable, pastille de la colonne, fenêtre, Fanfare), tient la file d'ouverture (Fanfare d'abord,
## plafond de 2 fenêtres par 30 jours), la colonne à droite au-dessus du cadran, et la pause unifiée de
## toutes les fenêtres (annonces, événements, hauts faits, élection).
##
## Rien ici n'entre dans l'état de la partie : ce que le joueur a lu ou écarté est propre à son poste
## (sauvegardé à côté de l'état, clé « ui » de SaveGame), sinon la partie en réseau se désynchroniserait.

signal locate_requested(system_id: int)
signal screen_requested(screen: String)
signal relation_requested(empire_id: int, pane: String)
signal idle_fleets_requested
signal event_requested(event_id: int)
signal deed_requested(item_id: int)
## La fenêtre s'est ouverte ou fermée (main.gd met à jour la caméra et le survol).
signal panel_changed(open: bool)

## Les tests et les outils coupent l'ouverture automatique (une fenêtre capterait le clavier).
static var auto := true
## Ouverture automatique sur ce poste (main.gd la coupe quand le menu principal est désactivé :
## tests et outils de capture).
var opening := true

var state: GameState
var viewer := 0
var spectator := false
## Partie en réseau : jamais de pause (net_check, s'il est donné, le dit au moment de la pause).
var networked := false
var net_check: Callable
## Horloge (l'autoload GameClock ; un script compilé par les tests ne peut pas le nommer).
var clock: Node
## main.gd : un menu, un écran ou une autre fenêtre recouvre-t-il la carte ?
var blocked: Callable
var hud: Hud
var panel: AnnouncePanel
var column: AnnounceColumn

## Pastilles d'annonces de la colonne : {"aids": [ids], "k", "t", "g", "read"}.
var items: Array[Dictionary] = []
## Annonces en attente d'ouverture automatique (identifiants), Fanfares en tête.
var queue: Array[int] = []
## Dernière annonce du registre déjà examinée.
var seen := 0
## Jours des dernières ouvertures automatiques (plafond prop. 21).
var opened_days: Array[int] = []
## Pastille ouverte dans la fenêtre (indice dans items), -1 si aucune.
var current := -1
## Pauses en cours, par fenêtre (« announce », « event », « deed », « election ») ; vrai si c'est nous
## qui avons arrêté le temps.
var holds := {}
var _we_paused := false


func setup(p_hud: Hud, p_clock: Node, p_blocked: Callable) -> void:
	hud = p_hud
	clock = p_clock
	blocked = p_blocked
	AnnounceSettings.load_settings()
	panel = AnnouncePanel.new()
	add_child(panel)
	panel.closed.connect(close_panel)
	panel.acknowledged.connect(_acknowledge)
	panel.locate_requested.connect(func(sid: int) -> void:
		close_panel()
		locate_requested.emit(sid))
	panel.screen_requested.connect(func(id: String) -> void:
		close_panel()
		screen_requested.emit(id))
	panel.nav_requested.connect(func(delta: int) -> void: _navigate(delta))
	panel.relation_requested.connect(func(id: int, pane: String) -> void:
		close_panel()
		relation_requested.emit(id, pane))
	panel.idle_fleets_requested.connect(func() -> void:
		close_panel()
		idle_fleets_requested.emit())
	column = AnnounceColumn.new()
	column.center = self
	hud.add_child(column)
	column.open_requested.connect(open_item)
	column.dismiss_requested.connect(dismiss)
	column.decision_requested.connect(_on_decision)


func _on_decision(kind: String, id: int) -> void:
	if kind == "event":
		event_requested.emit(id)
	elif kind == "deed":
		deed_requested.emit(id)


## Nouvelle partie ou partie chargée : les annonces passées ne s'ouvrent pas (ui : état sauvegardé du poste).
func start(p_state: GameState, p_viewer: int, p_spectator: bool, ui := {}) -> void:
	close_panel()
	release_all()
	state = p_state
	viewer = -1 if p_spectator else p_viewer
	spectator = p_spectator
	items.clear()
	queue.clear()
	opened_days.clear()
	seen = Announce.last_id(state)
	var col: Dictionary = ui.get("announce", {}) if ui is Dictionary else {}
	if not col.is_empty():
		seen = mini(seen, int(col.get("seen", seen)))
		for it: Dictionary in col.get("items", []):
			var aids: Array[int] = []
			for x in it.get("aids", []):
				if not Announce.find(state, int(x)).is_empty():
					aids.append(int(x))
			if not aids.is_empty():
				items.append({"aids": aids, "k": String(it["k"]), "t": int(it["t"]), "g": int(it["g"]), "read": bool(it.get("read", false))})
		# Ce qui est arrivé après la sauvegarde du poste mais avant celle de la partie n'a pas été vu.
		ingest(false)
	seen = Announce.last_id(state)
	refresh()


## État du poste à ranger dans la sauvegarde (clé « ui »).
func to_ui() -> Dictionary:
	var out: Array = []
	for it in items:
		out.append({"aids": it["aids"].duplicate(), "k": it["k"], "t": it["t"], "g": it["g"], "read": it["read"]})
	return {"seen": seen, "items": out}


# --- Chaque jour --------------------------------------------------------------------------------

## Examine les annonces arrivées depuis la veille. allow_open : elles peuvent rejoindre la file.
func ingest(allow_open := true) -> void:
	if state == null:
		return
	var last := Announce.last_id(state)
	if last <= seen:
		_expire()
		return
	# Les nouvelles sont en fin de registre : on remonte jusqu'à la dernière vue.
	var fresh: Array[Dictionary] = []
	for i in range(state.announces.size() - 1, -1, -1):
		var rec: Dictionary = state.announces[i]
		if int(rec["id"]) <= seen:
			break
		fresh.push_front(rec)
	seen = last
	for rec in fresh:
		if Announce.can_see(rec, viewer):
			_route(rec, allow_open)
	_expire()
	refresh()


## Ce que devient une annonce pour ce lecteur (prop. 9 à 12, 29, 31, 36).
func _route(rec: Dictionary, allow_open: bool) -> void:
	var kind := String(rec["k"])
	var g := effective_gravity(rec)
	if g <= Announce.MURMUR:
		return
	var preset := AnnounceSettings.preset
	if g == Announce.AVIS:
		if preset == "silence":
			_add_item(rec, g)
		else:
			_toast(rec)
		return
	var item := _add_item(rec, g)
	if bool(Announce.kind_def(kind).get("no_window", false)):
		return
	var wants := allow_open and auto and opening and AnnounceSettings.auto_open(kind)
	if spectator:
		wants = wants and (g >= Announce.FANFARE or int(rec.get("f", 0)) > 0)
	elif preset == "silence" and g < Announce.FANFARE:
		wants = false
	if not wants:
		if g >= Announce.WINDOW and allow_open:
			_toast(rec)
		return
	# Une pastille regroupée déjà en file n'y entre pas deux fois.
	for aid in queue:
		if (item["aids"] as Array).has(aid):
			return
	if g >= Announce.FANFARE:
		var at := 0
		while at < queue.size() and _gravity_of(queue[at]) >= Announce.FANFARE:
			at += 1
		queue.insert(at, int(rec["id"]))
	else:
		queue.append(int(rec["id"]))


## Gravité pour ce lecteur, réglages compris (préréglage Chroniqueur : les avis deviennent des fenêtres).
func effective_gravity(rec: Dictionary) -> int:
	var g := AnnounceSettings.final_gravity(state, rec, viewer)
	if AnnounceSettings.preset == "chroniqueur" and g == Announce.AVIS and AnnounceSettings.look_of(String(rec["k"])) == AnnounceSettings.AUTO:
		g = Announce.WINDOW
	return g


func _gravity_of(aid: int) -> int:
	var rec := Announce.find(state, aid)
	return effective_gravity(rec) if not rec.is_empty() else 0


## Pastille de la colonne : une nouvelle du même type dans le mois rejoint la précédente (prop. 23).
func _add_item(rec: Dictionary, g: int) -> Dictionary:
	var kind := String(rec["k"])
	var window := int(Announce.rhythm("group_days", 30))
	for it in items:
		if String(it["k"]) == kind and not bool(it["read"]) and int(rec["t"]) - int(it["t"]) <= window:
			(it["aids"] as Array).append(int(rec["id"]))
			it["t"] = int(rec["t"])
			it["g"] = maxi(int(it["g"]), g)
			return it
	var aids: Array[int] = [int(rec["id"])]
	var it := {"aids": aids, "k": kind, "t": int(rec["t"]), "g": g, "read": false}
	items.append(it)
	var cap := int(Announce.rhythm("column_max", 9))
	while items.size() > cap:
		# On écarte d'abord la plus ancienne déjà lue, sinon la plus ancienne.
		var drop := 0
		for i in items.size():
			if bool(items[i]["read"]):
				drop = i
				break
		_remove_at(drop)
	return it


## Une pastille vit 60 jours (les Fanfares restent jusqu'à lecture).
func _expire() -> void:
	if state == null:
		return
	var days := int(Announce.rhythm("column_days", 60))
	for i in range(items.size() - 1, -1, -1):
		var it := items[i]
		if state.tick - int(it["t"]) > days and (int(it["g"]) < Announce.FANFARE or bool(it["read"])):
			_remove_at(i)


func _remove_at(i: int) -> void:
	for aid in items[i]["aids"]:
		queue.erase(int(aid))
	if current == i:
		current = -1
	elif current > i:
		current -= 1
	items.remove_at(i)


## Ouvre la prochaine annonce de la file si rien ne recouvre la carte. fanfares_only : passe avant
## les décisions (événements, hauts faits, élection), les fenêtres ordinaires passent après.
func try_open(fanfares_only := false) -> void:
	if state == null or queue.is_empty() or panel.is_open():
		return
	if blocked.is_valid() and bool(blocked.call()):
		return
	var aid := queue[0]
	var g := _gravity_of(aid)
	if fanfares_only and g < Announce.FANFARE:
		return
	if g < Announce.FANFARE:
		# Plafond : 2 fenêtres ordinaires par 30 jours, le reste attend dans la colonne (prop. 21).
		var span := int(Announce.rhythm("cap_days", 30))
		while not opened_days.is_empty() and state.tick - opened_days[0] > span:
			opened_days.remove_at(0)
		if opened_days.size() >= int(Announce.rhythm("cap", 2)):
			queue.remove_at(0)
			var rec := Announce.find(state, aid)
			if not rec.is_empty():
				_toast(rec)
			return
		opened_days.append(state.tick)
	queue.remove_at(0)
	var idx := index_of(aid)
	if idx >= 0:
		open_item(idx)


func index_of(aid: int) -> int:
	for i in items.size():
		if (items[i]["aids"] as Array).has(aid):
			return i
	return -1


# --- Fenêtre ------------------------------------------------------------------------------------

## Ouvre la pastille i de la colonne dans la fenêtre commune (ou en Fanfare).
func open_item(i: int) -> void:
	if i < 0 or i >= items.size() or state == null:
		return
	var it := items[i]
	var recs: Array[Dictionary] = []
	for aid in it["aids"]:
		var rec := Announce.find(state, int(aid))
		if not rec.is_empty():
			recs.append(rec)
	if recs.is_empty():
		_remove_at(i)
		refresh()
		return
	recs.reverse()  # la plus récente d'abord
	var g := int(it["g"])
	current = i
	it["read"] = true
	var nav := _nav_index(i)
	panel.open(state, viewer, recs, g, nav.x, nav.y)
	AnnounceSounds.play(String(it["k"]), g)
	if AnnounceSettings.pauses_for(String(it["k"]), g):
		hold("announce")
	refresh()
	panel_changed.emit(true)


## Ouvre une annonce du registre (écran Chroniques), même si elle a quitté la colonne.
func open_record(aid: int) -> void:
	var i := index_of(aid)
	if i < 0:
		var rec := Announce.find(state, aid)
		if rec.is_empty():
			return
		var aids: Array[int] = [aid]
		items.append({"aids": aids, "k": String(rec["k"]), "t": int(rec["t"]), "g": maxi(Announce.WINDOW, effective_gravity(rec)), "read": true})
		i = items.size() - 1
	open_item(i)


## Position de la pastille parmi celles de la colonne (« 2 sur 5 »).
func _nav_index(i: int) -> Vector2i:
	return Vector2i(items.size() - i, items.size())


func _navigate(delta: int) -> void:
	if current < 0:
		return
	# La plus récente est en bas de la liste : « suivante » remonte vers les plus anciennes.
	var to := current - delta
	if to < 0 or to >= items.size():
		return
	var was := current
	panel.close()
	current = -1
	if was >= 0:
		release("announce")
	open_item(to)


## « Réduire » (Échap) : la pastille reste dans la colonne.
func close_panel() -> void:
	if panel == null or not panel.is_open():
		return
	panel.close()
	current = -1
	release("announce")
	refresh()
	panel_changed.emit(false)


## « Compris » : la pastille quitte la colonne.
func _acknowledge() -> void:
	var i := current
	close_panel()
	if i >= 0 and i < items.size():
		_remove_at(i)
	refresh()


## Clic droit sur une pastille : écartée sans l'ouvrir.
func dismiss(i: int) -> void:
	if i < 0 or i >= items.size():
		return
	if current == i:
		close_panel()
	_remove_at(i)
	refresh()


func is_open() -> bool:
	return panel != null and panel.is_open()


## Décisions en attente dans les boîtes du joueur (pastilles d'or de la colonne, prop. 20 et 28).
func decisions() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if state == null or spectator:
		return out
	for item: Dictionary in Events.inbox(state, viewer):
		var c := Events.card(String(item["card"]))
		out.append({"kind": "event", "id": int(item["id"]), "t": int(item["tick"]), "title": Events.fill(state, viewer, item, String(c.get("title", "Événement")))})
	if Deeds.enabled(state):
		for item: Dictionary in Deeds.inbox(state, viewer):
			out.append({"kind": "deed", "id": int(item["id"]), "t": int(item.get("tick", state.tick)), "title": "Haut fait : choisir la récompense"})
	return out


func refresh() -> void:
	if column:
		column.rebuild()


# --- Avis ---------------------------------------------------------------------------------------

## Avis cliquable (prop. 10) : un clic ouvre l'annonce en fenêtre.
func _toast(rec: Dictionary) -> void:
	if hud == null:
		return
	var aid := int(rec["id"])
	var need := Announce.need(rec, viewer)
	var self_concerned := Announce.involved(rec).has(viewer)
	var secs := float(Announce.rhythm("toast_seconds_self" if self_concerned else "toast_seconds", 3.5))
	hud.notify(String(rec["x"]), "info", func() -> void: open_record(aid), secs, Announce.need_color(need))


# --- Pause unifiée ------------------------------------------------------------------------------

## Une fenêtre demande l'arrêt du temps (en solo seulement, jamais pour le spectateur ni en réseau).
## Si le joueur avait déjà mis en pause, on ne reprendra pas à sa place.
func hold(key: String) -> void:
	if net_check.is_valid():
		networked = bool(net_check.call())
	if networked or spectator or clock == null:
		return
	if holds.is_empty():
		if bool(clock.get("paused")):
			return
		clock.call("set_paused", true)
		_we_paused = true
	holds[key] = true


func release(key: String) -> void:
	if not holds.has(key):
		return
	holds.erase(key)
	if holds.is_empty() and _we_paused:
		_we_paused = false
		if clock != null:
			clock.call("set_paused", false)


## Le temps mis en pause par une fenêtre ne repartira pas à sa fermeture (arrêt automatique, voir
## main.halt_game) : le joueur reprend la main lui-même.
func keep_paused() -> void:
	_we_paused = false


func release_all() -> void:
	holds.clear()
	_we_paused = false
