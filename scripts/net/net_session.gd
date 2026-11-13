class_name NetSession
extends Node
## Session multijoueur : le transport (ENet, UDP) autour du cœur Lockstep, et l'horloge partagée.
##
## L'hôte ouvre sa partie en cours ; un client s'y connecte par adresse. L'hôte lui présente les empires
## libres (tenus par l'IA) et le joueur choisit le sien ; un joueur qui revient (même identifiant, ou à
## défaut même nom) retrouve directement son empire. La partie se met alors en pause, l'hôte confie
## l'empire (ordre « seat ») et envoie l'instantané complet (GameState.to_snapshot, compressé).
## Au départ d'un joueur, voulu ou non, son empire repasse à l'IA (intérim) et lui reste réservé ;
## l'hôte sauvegarde automatiquement, avec la liste des places, pour reprendre la partie au besoin.
##
## Une fois branchée (GameClock.driver), la session remplace l'horloge locale : elle fait avancer la
## simulation au rythme de l'hôte.
## - Temps réel : pause et vitesse partagées (tout le monde peut mettre en pause ; reprend celui qui
##   a mis en pause ou l'hôte ; seul l'hôte règle la vitesse).
## - Tour par tour (tours simultanés) : chacun donne ses ordres pendant que le temps est arrêté, puis
##   termine son tour ; quand tous ont terminé (ou que l'hôte force la fin du tour), les jours du tour
##   défilent chez tous et tout le monde s'arrête au même jour, au début du tour suivant.
##
## Les messages sont des dictionnaires encodés par var_to_bytes (sans objets : rien d'exécutable).

signal notice(text: String, tone: String)
## Client : l'hôte a accepté ; state est la partie à rejoindre, empire_id l'empire confié.
signal joined(state: GameState, empire_id: int)
## Client : l'hôte a renvoyé son état après une désynchronisation ; le jeu remplace sa partie par
## celle-ci (et rappelle bind()), sans changer d'empire.
signal resynced(state: GameState)
## Client : connexion refusée ou perdue avant d'entrer.
signal join_failed(reason: String)
## Client : l'hôte propose les empires à prendre (voir _empire_list) ; répondre par pick().
signal choose_empire(empires: Array)
## Salon d'avant-partie, client : nouvel état du salon (voir lobby_state()).
signal lobby_changed(state: Dictionary)
## Salon, hôte : un joueur demande quelque chose (« take » une place, « set » peuple et couleur de sa
## place, « ready »). Le jeu applique ce qui est permis puis appelle lobby_update().
signal lobby_request(peer: int, kind: String, data: Dictionary)
## La session s'est terminée (hôte parti, réseau fermé).
signal ended(reason: String)
## Les joueurs connectés ont changé (noms, empires).
signal players_changed
## Pause ou vitesse partagées ont changé.
signal clock_changed
## Hôte : la box a répondu (ou non) à la demande d'ouverture du port (UPnP). Voir upnp_text().
signal upnp_changed
## Discussion : un message reçu (ou envoyé). team : réservé à l'équipe de l'auteur.
signal chat_received(entry: Dictionary)

enum { NONE, HOST, CLIENT }

const DEFAULT_PORT := 24570
## Joueurs humains au plus (l'hôte compris) : autant que d'empires (GameState.MAX_EMPIRES).
const MAX_PLAYERS := 12
const MAX_DAYS_PER_FRAME := 8
## Marge ajoutée à la demi-latence pour fixer le délai des ordres.
const DELAY_MARGIN_MS := 60.0
## Niveau de l'IA qui tient l'empire d'un joueur parti.
const INTERIM_AI := "normal"
const AUTOSAVE_PATH := "user://saves/multi_auto.json"
## Le script de l'horloge, pour ses constantes (l'autoload GameClock n'est pas nommable ici : la
## session doit aussi se compiler dans les outils lancés avec -s, où il n'existe pas encore).
const Clock := preload("res://scripts/sim/game_clock.gd")
const DESYNC_DIR := "user://desync"
## Réglages réseau du joueur (nom, dernière adresse, identifiant).
const NET_SETTINGS := "user://net.cfg"
## Garde-fous de l'hôte face à Internet : taille maximale d'un message d'un joueur (un peuple créé
## pèse quelques Ko), délai pour se présenter (mot de passe compris), connexions par adresse, et
## débit de messages par joueur (au-delà, il est déconnecté).
const MAX_CLIENT_PACKET := 256 * 1024
const MAX_HOST_PACKET := 64 * 1024 * 1024
const HELLO_TIMEOUT_MS := 8000
const MAX_PER_ADDRESS := 4
const MAX_PACKETS_PER_SECOND := 400
const CHAT_BURST := 5
const CHAT_WINDOW_MS := 5000
## Mauvais mots de passe : après PASSWORD_TRIES essais ratés, l'adresse attend PASSWORD_LOCK_MS.
const PASSWORD_TRIES := 5
## Client : sans le défi de l'hôte dans ce délai, on abandonne (au lieu d'attendre sans fin).
const CONNECT_TIMEOUT_MS := 10000
const PASSWORD_LOCK_MS := 60000
## Délais de déconnexion ENet (ms) : un joueur coupé est repéré en quelques secondes.
const TIMEOUT_MIN_MS := 3000
const TIMEOUT_MAX_MS := 10000

var role := NONE
var core: Lockstep
var player_name := "Joueur"
## Pair -> nom (l'hôte compris, sous Lockstep.HOST).
var names := {}
var my_empire := -1
## Horloge partagée.
var paused := true
var speed := 1
## Nom de celui qui a mis en pause ("" : personne, ou pause d'arrivée).
var paused_by := ""
var delay := 1
## Tour par tour (copie de l'hôte) : longueur d'un tour, jour où le tour en cours s'arrête (-1 : on
## donne ses ordres), et pairs qui n'ont pas encore terminé leur tour.
var turn_mode := false
var turn_days := 10
var turn_target := -1
var waiting: Array = []
## Client : qui dirige quel empire (pair -> empire), reçu de l'hôte avec l'horloge.
var seat_map := {}
## Minuteur de tour (GameClock.TURN_TIMERS) et instant local où il force la fin du tour (-1 : arrêté).
var timer_id := ""
var timer_end_ms := -1
## Discussion : derniers messages ({"n": auteur, "t": texte, "e": équipe seulement}), du plus ancien.
var chat_log: Array[Dictionary] = []
## Hôte : ouvrir le port sur la box par UPnP (désactivé par les bots de test). État : "" (rien),
## "busy" (recherche en cours), "ok" (port ouvert, upnp_address = adresse Internet), "fail" (upnp_reason).
var use_upnp := true
## Mot de passe de la partie (hôte ; "" : aucun) et celui que le joueur tape pour rejoindre. Il ne
## circule jamais en clair : l'hôte envoie un défi, le joueur répond par une empreinte SHA-256.
var password := ""
var join_password := ""
## Hôte : pairs connectés pas encore présentés (pair -> instant de connexion), défis envoyés,
## compte des messages de la seconde en cours et des derniers messages de discussion.
var _unhelloed := {}
var _nonces := {}
var _rate := {}
var _chat_times := {}
## Hôte : adresse -> instants des derniers mauvais mots de passe.
var _fails := {}
## Client : l'hôte a-t-il répondu (défi reçu) ? Sinon, abandon à _connect_deadline.
var _greeted := false
var _connect_deadline := 0
var _connect_target := ""
var upnp_state := ""
## Hôte : adresse Internet de la box (service api.ipify.org), celle à donner aux amis.
var public_address := ""
var _ip_request: HTTPRequest
var upnp_address := ""
var upnp_reason := ""
var _mapper: PortMapper
const CHAT_MAX := 200
const CHAT_KEEP := 60
## Identifiant durable du joueur (user://net.cfg) : c'est lui qui retrouve l'empire au retour.
var token := ""
## Hôte : places réservées aux joueurs partis, identifiant -> {"e": empire, "n": nom}.
var absent := {}
## Chemin de la sauvegarde automatique (les tests en prennent un autre).
var autosave_path := AUTOSAVE_PATH

var _peer: ENetMultiplayerPeer
var _accum := 0.0
## Hôte : pause demandée, on joue jusqu'au premier jour sans trame scellée.
var _pausing := false
var _pauser := -1
## Hôte : arrivées et départs à traiter dès que tout le monde est arrêté.
var _joins: Array[int] = []
var _leaves: Array[int] = []
var _stall_told := false
var _delay_timer := 0.0
## Hôte : pair -> identifiant, pair -> empire choisi (arrivée en attente), pairs ayant fini leur tour.
var _tokens := {}
## Hôte : pairs désynchronisés à qui renvoyer l'état dès que tout le monde est arrêté, et faut-il
## repartir ensuite (la partie tournait quand l'écart a été vu).
var _resyncs: Array[int] = []
var _resume_after_resync := false
var _picks := {}
var _ready := {}
## Hôte : annonce de la partie sur le réseau local (voir LanDiscovery).
var _beacon: LanDiscovery
var _beacon_timer := 0.0
var _port := DEFAULT_PORT
## Salon d'avant-partie (hôte, avant la création de la partie) : ouvert, places tenues par chaque pair
## (pair -> indice de place), pairs prêts, et dernier état envoyé (places, résumé des réglages).
var lobby_open := false
var lobby_seats := {}
var lobby_ready := {}
var _lobby_view := {}
## Client : mon identifiant de pair dans le salon.
var _lobby_me := 0


func is_active() -> bool:
	return role != NONE


func is_host() -> bool:
	return role == HOST


# --- Ouverture ---------------------------------------------------------------------------------

## Ouvre la partie en cours au réseau. Le joueur local garde son empire.
## seats : places d'une partie en réseau sauvegardée (SaveGame.last_clock["net"]), pour réserver leurs
## empires aux joueurs qui reviendront. Tout autre empire humain passe à l'IA en attendant son joueur.
func host(sim: Simulation, empire_id: int, port := DEFAULT_PORT, seats := {}) -> Error:
	close()
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_server(port, MAX_PLAYERS - 1)
	if err != OK:
		_peer = null
		return err
	_peer.peer_connected.connect(_on_peer_connected)
	_peer.peer_disconnected.connect(_on_peer_disconnected)
	role = HOST
	_port = port
	_beacon = LanDiscovery.new()
	_beacon_timer = 0.0
	_open_upnp(port)
	core = Lockstep.new(sim, true)
	core.seats[Lockstep.HOST] = empire_id
	core.desync_detected.connect(_on_desync)
	names = {Lockstep.HOST: player_name}
	if token == "":
		token = local_token()
	_tokens = {Lockstep.HOST: token}
	my_empire = empire_id
	speed = _clock().speed_index
	turn_mode = _clock().is_turn_based()
	turn_days = _clock().turn_days
	timer_id = _clock().turn_timer
	timer_end_ms = -1
	turn_target = -1
	paused = true
	for t in seats:
		var e := int((seats[t] as Dictionary).get("e", -1)) if seats[t] is Dictionary else -1
		if String(t) != token and e >= 0 and e != empire_id:
			absent[String(t)] = {"e": e, "n": String(seats[t].get("n", "Joueur"))}
	for e in sim.state.empires:
		if e.id != empire_id and not e.is_ai() and not e.eliminated:
			core.request(Lockstep.HOST, SimCommands.seat(e.id, INTERIM_AI))
	core.flush_paused()
	_update_waiting()
	_attach_clock()
	players_changed.emit()
	return OK


## Identifiant durable de ce joueur, créé au premier besoin et rangé dans user://net.cfg.
static func local_token() -> String:
	var cfg := ConfigFile.new()
	cfg.load(NET_SETTINGS)
	var t := String(cfg.get_value("net", "token", ""))
	if t == "":
		t = Crypto.new().generate_random_bytes(8).hex_encode()
		cfg.set_value("net", "token", t)
		cfg.save(NET_SETTINGS)
	return t


## Ouvre le salon d'avant-partie : les joueurs se connectent pendant que l'hôte règle la partie, prennent
## une place « joueur humain » et y choisissent peuple et couleur. start_from_lobby() lance la partie.
func open_lobby(port := DEFAULT_PORT) -> Error:
	close()
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_server(port, MAX_PLAYERS - 1)
	if err != OK:
		_peer = null
		return err
	_peer.peer_connected.connect(_on_peer_connected)
	_peer.peer_disconnected.connect(_on_peer_disconnected)
	role = HOST
	_port = port
	_beacon = LanDiscovery.new()
	_beacon_timer = 0.0
	_open_upnp(port)
	lobby_open = true
	if token == "":
		token = local_token()
	names = {Lockstep.HOST: player_name}
	_tokens = {Lockstep.HOST: token}
	return OK


## Hôte : état du salon à montrer à tous. view : {"slots": [{"i", "name", "faction", "color",
## "human", "level"}], "summary": texte des réglages}. Les joueurs et leur place s'y ajoutent ici.
func lobby_update(view: Dictionary) -> void:
	if not lobby_open:
		return
	_lobby_view = view.duplicate(true)
	_send(0, {"k": "lobby", "l": lobby_state()})


## Salon : places (avec qui les tient), résumé, noms et joueurs prêts.
func lobby_state() -> Dictionary:
	var st := _lobby_view.duplicate(true)
	var held := {}
	for p in lobby_seats:
		held[int(lobby_seats[p])] = p
	for sl in st.get("slots", []):
		var p := int(held.get(int(sl["i"]), 0))
		sl["peer"] = p
		sl["player"] = String(names.get(p, "")) if p != 0 else ""
		sl["ready"] = lobby_ready.has(p)
	st["host"] = player_name
	st["names"] = names.duplicate()
	return st


## Hôte : la place i n'est plus pour un humain (passée à l'IA ou retirée) : son joueur la perd.
func lobby_release_slot(i: int) -> void:
	for p in lobby_seats.keys():
		if int(lobby_seats[p]) == i:
			lobby_seats.erase(p)
			lobby_ready.erase(p)


## Hôte : la place est-elle tenue par un joueur ?
func lobby_slot_holder(i: int) -> int:
	for p in lobby_seats:
		if int(lobby_seats[p]) == i:
			return p
	return 0


## Hôte : tous les joueurs connectés ont une place et sont prêts.
func lobby_all_ready() -> bool:
	for p in names:
		if p == Lockstep.HOST:
			continue
		if not lobby_seats.has(p) or not lobby_ready.has(p):
			return false
	return true


## Hôte : la partie est créée ; chaque joueur du salon prend l'empire de sa place (seats : pair ->
## empire). Les empires des places humaines ont été créés tenus par l'IA : l'accueil les leur confie.
func start_from_lobby(sim: Simulation, empire_id: int, seats: Dictionary) -> void:
	lobby_open = false
	core = Lockstep.new(sim, true)
	core.seats[Lockstep.HOST] = empire_id
	core.desync_detected.connect(_on_desync)
	my_empire = empire_id
	speed = _clock().speed_index
	turn_mode = _clock().is_turn_based()
	turn_days = _clock().turn_days
	timer_id = _clock().turn_timer
	timer_end_ms = -1
	turn_target = -1
	paused = true
	_update_waiting()
	_attach_clock()
	for p in seats:
		if names.has(p):
			_picks[p] = int(seats[p])
			_joins.append(p)
	# Les joueurs sans place entrent comme à l'ordinaire : ils choisiront un empire libre.
	for p in names.keys():
		if p != Lockstep.HOST and not seats.has(p):
			_send(p, {"k": "choose", "l": _empire_list()})
	lobby_seats.clear()
	lobby_ready.clear()
	_after_stop()
	players_changed.emit()


## Client : demandes au salon.
func lobby_take(i: int) -> void:
	_send(Lockstep.HOST, {"k": "lobby_take", "i": i})


func lobby_set(faction: String, color: String) -> void:
	var msg := {"k": "lobby_set", "f": faction, "c": color}
	if not GameData.is_official(faction) and not GameData.faction(faction).is_empty():
		msg["def"] = GameData.faction(faction)  # peuple créé : l'hôte en a besoin pour créer la partie
	_send(Lockstep.HOST, msg)


func lobby_set_ready(value: bool) -> void:
	_send(Lockstep.HOST, {"k": "lobby_ready", "r": value})


## Se connecte à une partie. La réponse arrive par joined ou join_failed.
func join(address: String, port := DEFAULT_PORT) -> Error:
	close()
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_client(address, port)
	if err != OK:
		_peer = null
		return err
	if token == "":
		token = local_token()
	_greeted = false
	_connect_deadline = Time.get_ticks_msec() + CONNECT_TIMEOUT_MS
	_connect_target = "%s, port %d" % [address, port]
	_peer.peer_connected.connect(func(id: int) -> void:
		if id == Lockstep.HOST:
			_set_timeout(id))  # puis l'hôte envoie son défi (« challenge »), et l'on se présente
	_peer.peer_disconnected.connect(func(id: int) -> void:
		if id == Lockstep.HOST:
			# Pas pendant poll() : fermer le pair au milieu de sa propre boucle le ferait planter.
			_end.call_deferred("l'hôte a quitté la partie" if core else "connexion perdue"))
	role = CLIENT
	return OK


## Ferme la session (sans prévenir les autres : ENet le leur signale).
func close() -> void:
	if _peer:
		_peer.close()
	_peer = null
	_beacon = null
	lobby_open = false
	lobby_seats = {}
	lobby_ready = {}
	_lobby_view = {}
	role = NONE
	core = null
	names = {}
	_unhelloed = {}
	_nonces = {}
	_rate = {}
	_chat_times = {}
	my_empire = -1
	_joins.clear()
	_leaves.clear()
	_resyncs.clear()
	_resume_after_resync = false
	if _mapper:
		_mapper.close()
	upnp_state = ""
	upnp_address = ""
	upnp_reason = ""
	_pausing = false
	absent = {}
	chat_log.clear()
	_tokens = {}
	_picks = {}
	_ready = {}
	waiting = []
	seat_map = {}
	turn_target = -1
	timer_end_ms = -1
	if _clock().driver == self:
		_clock().driver = null
		_clock().net_ready = false
		_clock().net_waiting.clear()
		_clock().net_players.clear()
		_clock().net_timer_end_ms = -1


func _end(reason: String) -> void:
	if role == NONE:
		return
	var was_in := core != null
	close()
	if was_in:
		ended.emit(reason)
	else:
		join_failed.emit(reason)


## Adresses locales de cette machine (IPv4), à donner aux autres joueurs.
# --- Ouverture du port sur la box (UPnP) ---------------------------------------------------------

func _open_upnp(port: int) -> void:
	if not use_upnp:
		return
	_lookup_public_address()
	if _mapper == null:
		_mapper = PortMapper.new()
		_mapper.finished.connect(_on_upnp)
	upnp_state = "busy"
	_mapper.open(port)
	upnp_changed.emit()


func _on_upnp(ok: bool, address: String, reason: String) -> void:
	if role != HOST:
		return
	upnp_state = "ok" if ok else "fail"
	upnp_address = address
	upnp_reason = reason
	upnp_changed.emit()


## Ce qu'il faut dire aux joueurs qui viennent par Internet.
## Cherche l'adresse Internet (celle à donner aux amis : l'adresse locale ne sert que chez soi).
func _lookup_public_address() -> void:
	if public_address != "":
		return
	if _ip_request == null:
		_ip_request = HTTPRequest.new()
		_ip_request.timeout = 8.0
		add_child(_ip_request)
		_ip_request.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
			var ip := body.get_string_from_utf8().strip_edges()
			if result == HTTPRequest.RESULT_SUCCESS and code == 200 and ip.is_valid_ip_address():
				public_address = ip
				upnp_changed.emit())
	if _ip_request.get_http_client_status() == HTTPClient.STATUS_DISCONNECTED:
		_ip_request.request("https://api.ipify.org")


func upnp_text() -> String:
	match upnp_state:
		"busy":
			return "Par Internet : ouverture du port sur votre box (UPnP)…"
		"ok":
			if upnp_address != "":
				return "Par Internet : %s (port %d ouvert sur votre box par UPnP)." % [upnp_address, _port]
			return "Par Internet : port %d ouvert sur votre box par UPnP ; donnez votre adresse publique." % _port
		"fail":
			if public_address != "":
				return "Par Internet : donnez %s (votre adresse Internet), port %d, une fois ce port UDP redirigé sur votre box vers ce PC (UPnP : %s), ou utilisez Tailscale." % [public_address, _port, upnp_reason]
			return "Par Internet : %s ; redirigez le port %d (UDP) sur votre box, ou utilisez Tailscale." % [upnp_reason, _port]
	if public_address != "":
		return "Par Internet : donnez %s (votre adresse Internet), port %d redirigé (UDP), ou Tailscale." % [public_address, _port]
	return "Par Internet : votre adresse publique, port %d redirigé (UDP), ou Tailscale." % _port


func _exit_tree() -> void:
	if _mapper:
		_mapper.shutdown()


static func local_addresses() -> Array[String]:
	var out: Array[String] = []
	for a in IP.get_local_addresses():
		if a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254."):
			out.append(a)
	return out


# --- Ordres et horloge (appelés par le jeu) ----------------------------------------------------

## Un ordre du joueur local. Renvoie la raison d'un refus immédiat, "" sinon (il s'appliquera au
## jour que l'hôte lui donnera).
func submit(cmd: Dictionary) -> String:
	if core == null:
		return "pas de partie en réseau"
	var why := SimCommands.validate(core.sim.state, cmd)
	if why != "":
		return why
	if role == HOST:
		why = core.request(Lockstep.HOST, cmd)
		_flush()
		return why
	_send(Lockstep.HOST, {"k": "order", "c": cmd})
	return ""


## Espace, cadran : demande de pause ou de reprise, pour tout le monde.
func request_pause(value: bool) -> void:
	if role == HOST:
		_host_pause(Lockstep.HOST, value)
	elif core:
		_send(Lockstep.HOST, {"k": "pause", "p": value})


## Espace, cadran : au tour par tour, terminer son tour (ou l'annuler tant que les autres jouent ; l'hôte
## qui a déjà terminé force la fin du tour) ; pendant que les jours défilent, pause commune.
## En temps réel : pause ou reprise.
func request_toggle() -> void:
	if core == null:
		return
	if not turn_mode:
		request_pause(not paused)
		return
	if not paused and not _pausing:
		request_pause(true)
		return
	var me := _my_id()
	var now_ready := not waiting.has(me)
	if role == HOST:
		_host_ready(Lockstep.HOST, true, now_ready)
	else:
		_send(Lockstep.HOST, {"k": "ready", "r": not now_ready})


## Client : l'empire choisi dans la liste de choose_empire.
func pick(empire_id: int) -> void:
	if role == CLIENT and core == null:
		_send(Lockstep.HOST, {"k": "pick", "e": empire_id})


func request_speed(index: int) -> void:
	if role == HOST:
		speed = clampi(index, 0, Clock.SECONDS_PER_DAY.size() - 1)
		_update_delay()
		_broadcast_clock()
	elif core:
		notice.emit("Seul l'hôte règle la vitesse.", "")


## Fraction du jour en cours, pour animer les flottes.
func day_fraction() -> float:
	if paused or core == null or not core.can_step():
		return 0.0
	return clampf(_accum / _seconds_per_day(), 0.0, 1.0)


## Appelé à chaque image par GameClock (driver) : réseau, puis avance de la simulation.
func clock_process(delta: float) -> void:
	_poll()
	if core == null:
		return
	if role == HOST:
		_host_clock(delta)
	else:
		_client_clock(delta)
	_flush()


func _process(delta: float) -> void:
	# Hors partie (connexion en cours, salon), on écoute quand même le réseau.
	if _peer and _clock().driver != self:
		_poll()
		if lobby_open and _beacon:
			_beacon_timer -= delta
			if _beacon_timer <= 0.0:
				_beacon_timer = 1.0
				_beacon.announce({"name": player_name, "port": _port, "players": names.size(), "turns": _clock().is_turn_based(),
						"date": "salon", "version": GameVersion.fingerprint(), "pw": password != ""})


## L'horloge du jeu (autoload).
func _clock() -> Node:
	return get_node("/root/GameClock")


func _seconds_per_day() -> float:
	return Clock.TURN_SECONDS_PER_DAY if turn_mode else Clock.SECONDS_PER_DAY[speed]


func _my_id() -> int:
	return Lockstep.HOST if role == HOST else (_peer.get_unique_id() if _peer else 0)


func _attach_clock() -> void:
	_clock().driver = self
	_sync_clock()


## Recopie l'horloge partagée dans GameClock (cadran, Espace).
func _sync_clock() -> void:
	var c := _clock()
	var stopped := paused or _pausing
	c.net_sync(stopped, speed, Clock.MODE_TURNS if turn_mode else Clock.MODE_REALTIME, turn_days,
			turn_target if not stopped else -1)
	c.net_ready = turn_mode and stopped and not waiting.has(_my_id())
	var who: Array[String] = []
	for p in waiting:
		who.append(String(names.get(p, "?")))
	c.net_waiting = who
	var players: Array[Dictionary] = []
	if turn_mode and core:
		var seat_of: Dictionary = core.seats if role == HOST else seat_map
		var ids := seat_of.keys()
		ids.sort()
		for p in ids:
			var e := core.sim.state.get_empire(int(seat_of[p]))
			players.append({"name": String(names.get(p, "?")), "color": e.color() if e else Color.GRAY,
					"ready": not waiting.has(p), "me": int(p) == _my_id()})
	c.net_players = players
	c.net_timer_end_ms = timer_end_ms if turn_mode and stopped else -1


func _set_timeout(id: int) -> void:
	var p := _peer.get_peer(id) if _peer else null
	if p:
		p.set_timeout(0, TIMEOUT_MIN_MS, TIMEOUT_MAX_MS)


func _host_clock(delta: float) -> void:
	_beacon_timer -= delta
	if _beacon and _beacon_timer <= 0.0:
		_beacon_timer = 1.0
		_beacon.announce({"name": player_name, "port": _port, "players": core.seats.size(),
				"turns": turn_mode, "date": GameCalendar.date_string(core.tick()), "version": GameVersion.fingerprint(), "pw": password != ""})
	_delay_timer += delta
	if _delay_timer > 1.0:
		_delay_timer = 0.0
		_update_delay()
	if _pausing:
		# Tout le monde s'arrête au premier jour sans trame scellée : on y va.
		var n := 0
		while core.can_step() and n < MAX_DAYS_PER_FRAME:
			core.step()
			n += 1
		if not core.can_step():
			# Arrêt tombé sur la fin du tour : c'est une fin de tour ordinaire (on donne ses ordres).
			if turn_mode and turn_target >= 0 and core.tick() >= turn_target:
				_finish_turn()
				return
			_pausing = false
			paused = true
			_broadcast_clock()
			_after_stop()
		return
	if paused:
		_tick_timer()
		core.flush_paused()
		return
	_accum += delta
	var step := _seconds_per_day()
	var n := 0
	while _accum >= step and n < MAX_DAYS_PER_FRAME:
		if not core.host_may_step():
			_accum = minf(_accum, step)
			if not _stall_told:
				_stall_told = true
				notice.emit("%s ralentit la partie (machine ou connexion lente)." % names.get(core.slowest(), "Un joueur"), "")
			return
		_stall_told = false
		_accum -= step
		n += 1
		core.seal_until(_seal_limit())
		core.step()
		if turn_mode and core.tick() >= turn_target:
			_finish_turn()
			return
		if not turn_mode and core.tick() % Lockstep.CHECK_DAYS == 0:
			_autosave()
	if n >= MAX_DAYS_PER_FRAME:
		_accum = 0.0


## Dernier jour à sceller : jour courant + délai, sans dépasser la fin du tour en cours.
func _seal_limit() -> int:
	var until := core.tick() + delay
	return mini(until, turn_target - 1) if turn_mode else until


func _client_clock(delta: float) -> void:
	if not paused:
		_accum += delta
	var step := _seconds_per_day()
	var n := 0
	while core.can_step() and n < MAX_DAYS_PER_FRAME:
		# On suit le rythme de l'hôte ; on rattrape si l'on est en retard ou s'il s'est arrêté.
		if _accum >= step:
			_accum -= step
		elif not (paused or core.lead() > delay + 1):
			break
		core.step()
		n += 1
	if not core.can_step():
		_accum = minf(_accum, step)


## Délai des ordres : la demi-latence du joueur le plus lointain, plus une marge, en jours.
func _update_delay() -> void:
	var rtt := 0.0
	for id in core.acks:
		var p := _peer.get_peer(id)
		if p:
			rtt = maxf(rtt, p.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))
	var d := clampi(ceili((rtt * 0.5 + DELAY_MARGIN_MS) / (_seconds_per_day() * 1000.0)) + 1, 1, 8)
	if d != delay:
		delay = d
		_broadcast_clock()
	core.delay = delay
	core.max_lead = delay + 4


# --- Hôte : pause, arrivées, départs -----------------------------------------------------------

func _host_pause(by: int, value: bool) -> void:
	if value:
		if paused or _pausing:
			return
		_pausing = true
		_pauser = by
		paused_by = String(names.get(by, ""))
		_broadcast_clock()
		return
	if not (paused or _pausing):
		return
	if turn_mode:
		return  # au tour par tour, on repart quand tout le monde a terminé son tour (_start_turn)
	if by != Lockstep.HOST and _pauser >= 0 and by != _pauser and names.has(_pauser):
		_send(by, {"k": "notice", "t": "Seul %s ou l'hôte peut reprendre." % names[_pauser], "o": ""})
		return
	if not _joins.is_empty() or not _leaves.is_empty():
		return  # une arrivée ou un départ est en cours de traitement
	_pausing = false
	paused = false
	_pauser = -1
	paused_by = ""
	_accum = 0.0
	core.seal_until(core.tick() + delay)
	_broadcast_clock()


# --- Hôte : tours simultanés -------------------------------------------------------------------

## Un joueur termine son tour (value) ou l'annule. force : l'hôte, qui a déjà terminé, n'attend plus.
func _host_ready(by: int, value: bool, force := false) -> void:
	if not turn_mode or not paused or _pausing:
		return
	if force and by == Lockstep.HOST:
		if not waiting.is_empty():
			_announce("L'hôte force la fin du tour (sans attendre %s)." % _names_of(waiting), "")
		_start_turn()
		return
	if value:
		_ready[by] = true
	else:
		_ready.erase(by)
	_update_waiting()
	_broadcast_clock()
	_try_start_turn()


## Joueurs qui n'ont pas encore terminé leur tour.
func _update_waiting() -> void:
	waiting = []
	if not turn_mode:
		return
	var ids := core.seats.keys()
	ids.sort()
	for p in ids:
		if not _ready.has(p):
			waiting.append(p)


func _try_start_turn() -> void:
	if turn_mode and paused and not _pausing and waiting.is_empty() and _joins.is_empty() and _leaves.is_empty():
		_start_turn()


## Minuteur de tour : lancé quand on donne ses ordres (« fixe ») ou quand il ne reste qu'un joueur à
## attendre (« dernier ») ; à zéro, l'hôte termine le tour pour tout le monde, comme s'il le forçait.
func _tick_timer() -> void:
	var info := Clock.timer_info(timer_id)
	var mode := String(info["mode"])
	var runs := turn_mode and paused and not _pausing and _joins.is_empty() and _leaves.is_empty() \
			and (mode == "fixe" or (mode == "dernier" and waiting.size() == 1 and core.seats.size() > 1))
	if not runs:
		if timer_end_ms >= 0:
			timer_end_ms = -1
			_broadcast_clock()
		return
	var now := Time.get_ticks_msec()
	if timer_end_ms < 0:
		timer_end_ms = now + int(info["s"]) * 1000
		_broadcast_clock()
	elif now >= timer_end_ms:
		_announce("Temps écoulé : fin du tour%s." % ("" if waiting.is_empty() else " sans attendre %s" % _names_of(waiting)), "")
		_start_turn()


## Les jours du tour défilent chez tous, jusqu'au début du tour suivant (calé sur turn_days, comme
## en solo : un tour interrompu par une bataille repart vers la même fin).
func _start_turn() -> void:
	turn_target = (core.tick() / turn_days + 1) * turn_days
	timer_end_ms = -1
	_ready.clear()
	_pausing = false
	paused = false
	_pauser = -1
	paused_by = ""
	_accum = 0.0
	core.seal_until(_seal_limit())
	_update_waiting()
	_broadcast_clock()


## Tout le monde est arrivé au début du tour suivant : on donne ses ordres.
func _finish_turn() -> void:
	paused = true
	_pausing = false  # une pause demandée au dernier jour du tour (écart, joueur) est déjà là
	turn_target = -1
	_ready.clear()
	_update_waiting()
	_broadcast_clock()
	_autosave()
	_after_stop()


func _names_of(peers: Array) -> String:
	var out := PackedStringArray()
	for p in peers:
		out.append(String(names.get(p, "?")))
	return ", ".join(out)


## Tout le monde est arrêté au même jour : on traite arrivées et départs.
func _after_stop() -> void:
	for id in _leaves:
		_process_leave(id)
	_leaves.clear()
	var joins := _joins.duplicate()
	_joins.clear()
	for id in joins:
		_welcome(id)
	_send_resyncs()
	_update_waiting()
	_broadcast_clock()
	# La partie tournait avant l'écart : elle repart d'elle-même (au tour par tour, vers la même fin).
	if _resume_after_resync:
		_resume_after_resync = false
		if turn_mode and turn_target >= 0:
			_start_turn()
		elif not turn_mode:
			_host_pause(Lockstep.HOST, false)
	players_changed.emit()
	_flush()


## Départ d'un joueur : l'IA reprend son empire (ordre daté comme les autres, donc au même jour chez
## tous), la place lui reste réservée, et l'hôte sauvegarde pour pouvoir reprendre à ce point.
func _process_leave(id: int) -> void:
	var e: int = core.seats.get(id, -1)
	core.remove_peer(id)
	_ready.erase(id)
	var who := String(names.get(id, "Un joueur"))
	if e >= 0:
		core.request(Lockstep.HOST, SimCommands.seat(e, INTERIM_AI))
		if _tokens.has(id):
			absent[String(_tokens[id])] = {"e": e, "n": who}
	names.erase(id)
	_tokens.erase(id)
	if paused and not _pausing:
		core.flush_paused()
	var saved := _autosave()
	_announce("%s a quitté la partie : l'IA tient son empire en attendant son retour.%s" % [who, " Sauvegarde automatique faite." if saved else ""], "bad")


## Sauvegarde automatique de l'hôte, avec les places (qui dirige quel empire) pour les retours.
func _autosave() -> bool:
	if role != HOST or core == null:
		return false
	var clock: Dictionary = _clock().settings()
	clock["net"] = seats_record()
	return SaveGame.save_state(core.sim.state, autosave_path, clock) == OK


## Places de la partie : identifiant -> {"e": empire, "n": nom}, joueurs présents et partis.
func seats_record() -> Dictionary:
	var out := absent.duplicate(true)
	for p in core.seats:
		if _tokens.has(p):
			out[String(_tokens[p])] = {"e": int(core.seats[p]), "n": String(names.get(p, "Joueur"))}
	return out


func _welcome(id: int) -> void:
	if not names.has(id):
		return  # parti entre-temps
	var empire := int(_picks.get(id, -1))
	_picks.erase(id)
	if not _is_free(empire, String(_tokens.get(id, ""))):
		_send(id, {"k": "choose", "l": _empire_list(), "r": "cet empire vient d'être pris"})
		return
	core.request(Lockstep.HOST, SimCommands.seat(empire, ""))
	core.flush_paused()
	_flush()
	for t in absent.keys():
		if int(absent[t]["e"]) == empire:
			absent.erase(t)
	var snap := var_to_bytes(core.sim.state.to_snapshot()).compress(FileAccess.COMPRESSION_GZIP)
	core.add_peer(id, empire)
	_send(id, {"k": "welcome", "e": empire, "s": snap, "t": core.tick(), "names": names,
			"clock": _clock_msg()})
	var e := core.sim.state.get_empire(empire)
	_announce("%s rejoint la partie et prend la tête de %s." % [names[id], e.display_name()], "good")


## Empire qu'un joueur peut prendre : en vie, tenu par l'IA, sans joueur présent. Une place réservée
## à un joueur parti peut être prise par un autre (son titulaire choisira alors un autre empire).
func _is_free(empire_id: int, _tok := "") -> bool:
	var e := core.sim.state.get_empire(empire_id)
	return e != null and e.is_ai() and not e.eliminated and not core.seats.values().has(empire_id)


## Empire réservé à ce joueur (même identifiant, ou à défaut même nom), -1 s'il n'en a pas.
func _reserved_for(tok: String, pname: String) -> int:
	var key := ""
	if absent.has(tok):
		key = tok
	else:
		for t in absent:
			if String(absent[t]["n"]).to_lower() == pname.to_lower():
				key = t
				break
	if key == "":
		return -1
	var e := int(absent[key]["e"])
	return e if _is_free(e) else -1


## Empires de la partie, pour le choix du joueur qui arrive.
func _empire_list() -> Array:
	var out := []
	var held := {}
	for p in core.seats:
		held[int(core.seats[p])] = String(names.get(p, "?"))
	var reserved := {}
	for t in absent:
		reserved[int(absent[t]["e"])] = String(absent[t]["n"])
	var st := core.sim.state
	for e in st.empires:
		if e.eliminated:
			continue
		var colonies := 0
		for c in st.colonies.values():
			if c.owner == e.id:
				colonies += 1
		out.append({"id": e.id, "name": e.display_name(), "registre": String(e.faction().get("registre", "")),
				"color": e.color().to_html(false), "colonies": colonies, "player": String(held.get(e.id, "")),
				"reserved": String(reserved.get(e.id, "")), "free": _is_free(e.id)})
	return out


## Le joueur a son empire (choisi ou retrouvé) : on l'accueille dès que tout le monde est arrêté.
## Au tour par tour, pendant que les jours défilent, il entre au début du tour suivant.
func _queue_join(id: int) -> void:
	_joins.append(id)
	if turn_mode and not paused and not _pausing:
		_send(id, {"k": "notice", "t": "Vous entrerez dans la partie au début du tour suivant.", "o": ""})
		return
	_host_pause(Lockstep.HOST, true)
	paused_by = ""
	if paused and not _pausing:
		_after_stop()


func _on_peer_connected(id: int) -> void:
	_set_timeout(id)
	# Trop de connexions depuis la même adresse : refusée d'emblée.
	var addr := _address_of(id)
	var same := 0
	for p: int in _unhelloed.keys() + names.keys():
		if p != id and p != Lockstep.HOST and _address_of(p) == addr:
			same += 1
	if same >= MAX_PER_ADDRESS:
		_peer.disconnect_peer(id, true)
		return
	if _recent_fails(addr) >= PASSWORD_TRIES:
		_refuse(id, "trop de mauvais mots de passe : réessayez dans une minute")
		return
	# Défi : le joueur doit répondre par un « hello » (avec l'empreinte du mot de passe) à temps.
	var nonce := Crypto.new().generate_random_bytes(16).hex_encode()
	_nonces[id] = nonce
	_unhelloed[id] = Time.get_ticks_msec()
	_send(id, {"k": "challenge", "c": nonce, "pw": password != ""})


func _address_of(id: int) -> String:
	var p := _peer.get_peer(id) if _peer else null
	return p.get_remote_address() if p else ""


## Empreinte envoyée à la place du mot de passe : SHA-256(défi + mot de passe).
static func password_proof(nonce: String, pw: String) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update((nonce + "|" + pw).to_utf8_buffer())
	return h.finish().hex_encode()


## Hôte : coupe ceux qui ne se présentent pas à temps.
func _check_unhelloed() -> void:
	var now := Time.get_ticks_msec()
	for id: int in _unhelloed.keys():
		if now - int(_unhelloed[id]) > HELLO_TIMEOUT_MS:
			_unhelloed.erase(id)
			_nonces.erase(id)
			if _peer:
				_peer.disconnect_peer(id, true)


## Hôte : mauvais mots de passe venus de cette adresse dans la dernière minute.
func _recent_fails(addr: String) -> int:
	var now := Time.get_ticks_msec()
	var fails: Array = (_fails.get(addr, []) as Array).filter(func(t: int) -> bool: return now - t < PASSWORD_LOCK_MS)
	if fails.is_empty():
		_fails.erase(addr)
	else:
		_fails[addr] = fails
	return fails.size()


## Hôte : refuse un joueur avec une raison, puis le déconnecte (une fois la raison partie).
func _refuse(id: int, reason: String) -> void:
	_send(id, {"k": "refuse", "r": reason})
	_flush()
	# Déconnexion une fois la raison partie (disconnect_peer jetterait le message en attente). Il reste
	# dans _unhelloed : s'il ne part pas de lui-même, le délai de présentation le coupe.
	_nonces.erase(id)
	if not _unhelloed.has(id):
		_unhelloed[id] = Time.get_ticks_msec()
	var p := _peer.get_peer(id) if _peer else null
	if p:
		p.peer_disconnect_later()


func _on_peer_disconnected(id: int) -> void:
	if role != HOST:
		return
	_unhelloed.erase(id)
	_nonces.erase(id)
	_rate.erase(id)
	_chat_times.erase(id)
	if lobby_open:
		var who := String(names.get(id, ""))
		names.erase(id)
		_tokens.erase(id)
		lobby_seats.erase(id)
		lobby_ready.erase(id)
		if who != "":
			notice.emit("%s a quitté le salon." % who, "")
		players_changed.emit()
		lobby_update(_lobby_view)
		return
	_joins.erase(id)
	_picks.erase(id)
	if core.seats.has(id):
		_drop(id)
	else:
		names.erase(id)
		_tokens.erase(id)


## Un joueur est parti (ou revient sur une nouvelle connexion alors que l'ancienne n'est pas encore
## tombée). En temps réel la partie se met en pause ; au tour par tour, elle continue sans lui.
func _drop(id: int) -> void:
	if _leaves.has(id) or not core.seats.has(id):
		return
	if turn_mode:
		_process_leave(id)
		_update_waiting()
		_broadcast_clock()
		players_changed.emit()
		_flush()
		_try_start_turn()
		return
	_leaves.append(id)
	_host_pause(Lockstep.HOST, true)
	if paused and not _pausing:
		_after_stop()


## Désynchronisation : les deux états sont gardés pour l'analyse (user://desync), puis, dès que tout
## le monde est arrêté au même jour, l'hôte renvoie son état au joueur concerné et la partie repart.
func _on_desync(peer: int, tick: int) -> void:
	DirAccess.make_dir_recursive_absolute(DESYNC_DIR)
	var path := "%s/hote_jour_%d.json" % [DESYNC_DIR, core.tick()]
	SaveGame.save_state(core.sim.state, path)
	_send(peer, {"k": "desync", "t": tick})
	_announce("Écart de calcul avec %s au %s : resynchronisation sur l'état de l'hôte (états gardés dans %s)." % [
			names.get(peer, "un joueur"), GameCalendar.date_string(tick), DESYNC_DIR], "bad")
	if not _resyncs.has(peer):
		_resyncs.append(peer)
	if paused and not _pausing:
		_after_stop()
		return
	if not _pausing:
		_resume_after_resync = true
	_host_pause(Lockstep.HOST, true)


## Renvoie l'état de l'hôte (instantané, comme à l'arrivée) aux pairs désynchronisés.
func _send_resyncs() -> void:
	if _resyncs.is_empty():
		return
	var snap := var_to_bytes(core.sim.state.to_snapshot()).compress(FileAccess.COMPRESSION_GZIP)
	for p in _resyncs:
		if core.seats.has(p):
			core.resync_peer(p)
			_send(p, {"k": "resync", "s": snap, "t": core.tick(), "clock": _clock_msg()})
	_resyncs.clear()


func _announce(text: String, tone: String) -> void:
	notice.emit(text, tone)
	_send(0, {"k": "notice", "t": text, "o": tone})


func _clock_msg() -> Dictionary:
	return {"k": "clock", "p": paused or _pausing, "s": speed, "b": paused_by, "d": delay,
			"tm": turn_mode, "td": turn_days, "tt": turn_target, "w": waiting, "names": names, "sp": core.seats if core else {}, "ti": timer_id,
			"tl": timer_end_ms - Time.get_ticks_msec() if timer_end_ms >= 0 else -1}


func _broadcast_clock() -> void:
	_sync_clock()
	clock_changed.emit()
	_send(0, _clock_msg())


# --- Réseau ------------------------------------------------------------------------------------

func _poll() -> void:
	if _peer == null:
		return
	_peer.poll()
	if role == HOST:
		_check_unhelloed()
	elif role == CLIENT and not _greeted and Time.get_ticks_msec() > _connect_deadline:
		_end("aucune réponse de %s. Vérifiez l'adresse (son adresse Internet, pas une 192.168 hors de chez lui), la redirection du port UDP sur sa box et le pare-feu Windows de l'hôte ; « Tester » le vérifie sans rejoindre" % _connect_target)
		return
	while _peer and _peer.get_available_packet_count() > 0:
		var from := _peer.get_packet_peer()
		var data := _peer.get_packet()
		# Garde-fous : taille, débit, puis décodage sans objets (bytes_to_var ne recrée jamais
		# d'objet ni de code). Un message mal formé est ignoré.
		if role == HOST:
			if data.size() > MAX_CLIENT_PACKET or not _within_rate(from):
				_peer.disconnect_peer(from, true)
				continue
		elif data.size() > MAX_HOST_PACKET:
			continue
		var msg: Variant = bytes_to_var(data)
		if msg is Dictionary:
			if role == HOST:
				_host_message(from, msg)
			else:
				_client_message(msg)


## Hôte : un joueur qui inonde la partie de messages est déconnecté.
func _within_rate(id: int) -> bool:
	var sec := Time.get_ticks_msec() / 1000
	var r: Array = _rate.get(id, [sec, 0])
	if int(r[0]) != sec:
		r = [sec, 0]
	r[1] = int(r[1]) + 1
	_rate[id] = r
	return int(r[1]) <= MAX_PACKETS_PER_SECOND


## Lecture prudente d'un nombre venu du réseau (un texte ou une liste donne la valeur par défaut).
static func _num(v: Variant, d := -1) -> int:
	return int(v) if v is int or v is float else d


func _host_message(from: int, msg: Dictionary) -> void:
	var kind := String(msg.get("k", ""))
	# Tant qu'il ne s'est pas présenté (défi réussi), un pair ne peut rien faire d'autre.
	if kind != "hello" and not names.has(from):
		return
	match kind:
		"hello":
			if names.has(from) or not _nonces.has(from):
				return  # déjà présenté, ou pas de défi en cours
			if String(msg.get("v", "")) != GameVersion.fingerprint():
				_refuse(from, "versions du jeu différentes (la vôtre : %s, l'hôte : %s)" % [String(msg.get("v", "?")).substr(0, 24), GameVersion.fingerprint()])
				return
			if password != "" and String(msg.get("pw", "")) != password_proof(String(_nonces[from]), password):
				var fails: Array = _fails.get(_address_of(from), [])
				fails.append(Time.get_ticks_msec())
				_fails[_address_of(from)] = fails
				_refuse(from, "mot de passe incorrect")
				notice.emit("Connexion refusée : mauvais mot de passe (%s)." % _address_of(from), "bad")
				return
			_unhelloed.erase(from)
			_nonces.erase(from)
			var pname := String(msg.get("n", "Joueur")).strip_edges().substr(0, 24)
			var tok := String(msg.get("id", "")).substr(0, 64)
			if tok == "":
				tok = "nom:" + pname.to_lower()
			names[from] = pname if pname != "" else "Joueur"
			_tokens[from] = tok
			if lobby_open:
				notice.emit("%s entre dans le salon." % names[from], "good")
				players_changed.emit()
				_send(from, {"k": "lobby", "l": lobby_state(), "you": from})
				_send(0, {"k": "lobby", "l": lobby_state()})
				return
			# Il revient alors que son ancienne connexion n'est pas encore tombée : on la ferme.
			for p in core.seats.keys():
				if p != Lockstep.HOST and _tokens.get(p, "") == tok:
					_drop(p)
					_peer.disconnect_peer(p, true)
			var back := _reserved_for(tok, names[from])
			if back >= 0:
				_picks[from] = back
				_queue_join(from)
			else:
				_send(from, {"k": "choose", "l": _empire_list()})
		"pick":
			if core == null or not names.has(from) or core.seats.has(from) or _joins.has(from):
				return
			var e := _num(msg.get("e"))
			if not _is_free(e):
				_send(from, {"k": "choose", "l": _empire_list(), "r": "cet empire n'est pas libre"})
				return
			_picks[from] = e
			_queue_join(from)
		"ready":
			if core and core.seats.has(from):
				_host_ready(from, bool(msg.get("r", true)))
		"lobby_take", "lobby_set", "lobby_ready":
			if lobby_open and names.has(from) and NetSafe.is_plain(msg, 4, 2048, [1024]):
				var data := msg.duplicate()
				data.erase("k")
				lobby_request.emit(from, String(msg["k"]).trim_prefix("lobby_"), data)
		"order":
			if core == null or not core.seats.has(from):
				return
			var why := NetSafe.check_order(msg.get("c"))
			if why == "":
				why = core.request(from, msg["c"])
			if why != "":
				_send(from, {"k": "notice", "t": "Ordre refusé : %s" % why, "o": "bad"})
		"ack":
			if core and core.seats.has(from):
				core.host_receive_ack(from, _num(msg.get("t"), 0), String(msg.get("h", "")).substr(0, 128))
		"pause":
			if core and core.seats.has(from):
				_host_pause(from, bool(msg.get("p", true)))
		"chat":
			if names.has(from) and _chat_allowed(from):
				_host_chat(from, String(msg.get("t", "")), bool(msg.get("e", false)))


func _client_message(msg: Dictionary) -> void:
	match String(msg.get("k", "")):
		"welcome":
			var raw: PackedByteArray = msg.get("s", PackedByteArray())
			var snap: Variant = bytes_to_var(raw.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP))
			var state := GameState.from_dict(snap) if snap is Dictionary else null
			if state == null:
				_end("partie reçue illisible (%s)" % GameState.last_error)
				return
			my_empire = int(msg["e"])
			names = msg.get("names", {})
			joined.emit(state, my_empire)  # le jeu crée sa Simulation et appelle bind()
			_client_message(msg.get("clock", {}))
			players_changed.emit()
		"lobby":
			if msg.has("you"):
				_lobby_me = int(msg["you"])
			var st: Dictionary = msg.get("l", {})
			st["you"] = _lobby_me
			lobby_changed.emit(st)
		"choose":
			choose_empire.emit(msg.get("l", []))
			if String(msg.get("r", "")) != "":
				notice.emit(String(msg["r"]), "bad")
		"refuse":
			_end(String(msg.get("r", "refusé par l'hôte")))
		"challenge":
			_greeted = true
			var nonce := String(msg.get("c", ""))
			var hello := {"k": "hello", "v": GameVersion.fingerprint(), "n": player_name, "id": token}
			if bool(msg.get("pw", false)):
				hello["pw"] = password_proof(nonce, join_password)
			_send(Lockstep.HOST, hello)
		"frame":
			if core:
				core.receive_frame(int(msg["t"]), msg.get("c", []), bool(msg.get("s", false)))
		"clock":
			paused = bool(msg.get("p", true))
			speed = clampi(int(msg.get("s", 1)), 0, Clock.SECONDS_PER_DAY.size() - 1)
			paused_by = String(msg.get("b", ""))
			delay = int(msg.get("d", 1))
			turn_mode = bool(msg.get("tm", false))
			turn_days = maxi(1, int(msg.get("td", 10)))
			turn_target = int(msg.get("tt", -1))
			waiting = msg.get("w", [])
			timer_id = String(msg.get("ti", ""))
			var left := int(msg.get("tl", -1))
			timer_end_ms = Time.get_ticks_msec() + left if left >= 0 else -1
			if msg.get("names") is Dictionary:
				names = msg["names"]
			if msg.get("sp") is Dictionary:
				seat_map = msg["sp"]
			if core:
				_sync_clock()
			clock_changed.emit()
		"notice":
			notice.emit(String(msg.get("t", "")), String(msg.get("o", "")))
		"chat":
			_add_chat({"n": String(msg.get("n", "?")), "t": String(msg.get("t", "")), "e": bool(msg.get("e", false))})
		"desync":
			if core:
				DirAccess.make_dir_recursive_absolute(DESYNC_DIR)
				SaveGame.save_state(core.sim.state, "%s/client_jour_%d.json" % [DESYNC_DIR, core.tick()])
		"resync":
			var raw2: PackedByteArray = msg.get("s", PackedByteArray())
			var snap2: Variant = bytes_to_var(raw2.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP))
			var fresh := GameState.from_dict(snap2) if snap2 is Dictionary else null
			if fresh == null:
				_end("état de l'hôte illisible (%s)" % GameState.last_error)
				return
			resynced.emit(fresh)  # le jeu remplace sa Simulation et rappelle bind()
			_client_message(msg.get("clock", {}))
			notice.emit("Partie resynchronisée sur l'état de l'hôte.", "good")


## Client : branche la simulation créée par le jeu à partir de la partie reçue.
func bind(sim: Simulation) -> void:
	core = Lockstep.new(sim, false)
	_attach_clock()


# --- Discussion ---------------------------------------------------------------------------------

## Envoie un message à tous (team : à son équipe seulement, en partie). L'hôte le relaie.
func send_chat(text: String, team := false) -> void:
	text = text.strip_edges().substr(0, CHAT_MAX)
	if text == "" or role == NONE:
		return
	if role == HOST:
		_host_chat(Lockstep.HOST, text, team)
	else:
		_send(Lockstep.HOST, {"k": "chat", "t": text, "e": team})


## Hôte : relaie un message à qui doit le lire (tout le monde, ou l'équipe de l'auteur).
func _host_chat(by: int, text: String, team: bool) -> void:
	text = text.strip_edges().substr(0, CHAT_MAX)
	if text == "":
		return
	var to := chat_recipients(by, team)
	if to.is_empty():
		return
	var msg := {"k": "chat", "n": String(names.get(by, "?")), "t": text, "e": team and core != null}
	for p in to:
		if p == Lockstep.HOST:
			_add_chat({"n": msg["n"], "t": text, "e": msg["e"]})
		else:
			_send(p, msg)


## Qui lit un message de by : tout le monde, ou en partie les joueurs de son équipe (et lui-même).
func chat_recipients(by: int, team: bool) -> Array[int]:
	var out: Array[int] = []
	var mine := int(core.seats.get(by, -1)) if core else -1
	for p: int in names:
		if team and core:
			var theirs := int(core.seats.get(p, -1))
			if p != by and (mine < 0 or theirs < 0 or Diplomacy.team_of(core.sim.state, mine, theirs) <= 0):
				continue
		out.append(p)
	out.sort()
	return out


## Hôte : pas plus de CHAT_BURST messages par joueur en CHAT_WINDOW_MS (le reste est ignoré).
func _chat_allowed(id: int) -> bool:
	var now := Time.get_ticks_msec()
	var times: Array = _chat_times.get(id, [])
	times = times.filter(func(t: int) -> bool: return now - t < CHAT_WINDOW_MS)
	if times.size() >= CHAT_BURST:
		_chat_times[id] = times
		return false
	times.append(now)
	_chat_times[id] = times
	return true


func _add_chat(entry: Dictionary) -> void:
	chat_log.append(entry)
	while chat_log.size() > CHAT_KEEP:
		chat_log.pop_front()
	chat_received.emit(entry)


func _send(to: int, msg: Dictionary) -> void:
	if _peer == null or (to != 0 and _peer.get_peer(to) == null and role == HOST):
		return
	_peer.set_transfer_mode(MultiplayerPeer.TRANSFER_MODE_RELIABLE)
	_peer.set_target_peer(to)
	_peer.put_packet(var_to_bytes(msg))


func _flush() -> void:
	if core == null:
		return
	for out in core.outbox:
		_send(int(out["to"]), out["msg"])
	core.outbox.clear()
