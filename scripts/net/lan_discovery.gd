class_name LanDiscovery
extends RefCounted
## Parties en réseau local trouvées sans taper d'adresse : l'hôte annonce sa partie chaque seconde
## par diffusion UDP (broadcast) sur PORT, et la page Multijoueur écoute ce port pour les lister.
## Ne traverse pas Internet : seulement les machines du même réseau (maison, LAN).

const PORT := 24569
## Une partie disparaît de la liste si on ne l'entend plus pendant ce temps (ms).
const EXPIRE_MS := 4000
const MAGIC := "stellar-sigth"
## Une annonce pèse quelques centaines d'octets ; au-delà, elle est ignorée. Pas plus de MAX_GAMES
## parties listées (un voisin bruyant ne remplit pas la page).
const MAX_PACKET := 2048
const MAX_GAMES := 32

var _udp: PacketPeerUDP
var _listening := false
## Adresse -> {"name", "port", "players", "turns", "date", "version", "seen"}.
var games := {}


## Hôte : prépare l'émetteur.
func open_beacon() -> void:
	_udp = PacketPeerUDP.new()
	_udp.set_broadcast_enabled(true)
	_udp.set_dest_address("255.255.255.255", PORT)


## Hôte : annonce (une fois par seconde environ).
func announce(info: Dictionary) -> void:
	if _udp == null:
		open_beacon()
	var msg := info.duplicate()
	msg["k"] = MAGIC
	_udp.put_packet(var_to_bytes(msg))


## Page Multijoueur : écoute les annonces. Renvoie false si le port est déjà pris sur cette machine.
func listen(port := PORT) -> bool:
	close()
	_udp = PacketPeerUDP.new()
	if _udp.bind(port) != OK:
		_udp = null
		return false
	_listening = true
	return true


func is_listening() -> bool:
	return _listening


## Lit les annonces reçues et oublie les parties muettes. Renvoie true si la liste a changé.
func poll() -> bool:
	if _udp == null or not _listening:
		return false
	var changed := false
	var now := Time.get_ticks_msec()
	while _udp.get_available_packet_count() > 0:
		var data := _udp.get_packet()
		var addr := _udp.get_packet_ip()
		if data.size() > MAX_PACKET:
			continue
		var msg: Variant = bytes_to_var(data)
		if not msg is Dictionary or not NetSafe.is_plain(msg, 1, 128, [32]) or String(msg.get("k", "")) != MAGIC:
			continue
		var known := games.has(addr)
		if not known and games.size() >= MAX_GAMES:
			continue
		var port := NetSession._num(msg.get("port"), NetSession.DEFAULT_PORT)
		var g := {"name": String(msg.get("name", "?")).substr(0, 40), "port": port if port > 0 and port < 65536 else NetSession.DEFAULT_PORT,
				"players": clampi(NetSession._num(msg.get("players"), 1), 0, 99), "turns": bool(msg.get("turns", false)),
				"locked": bool(msg.get("pw", false)),
				"date": String(msg.get("date", "")).substr(0, 40), "version": String(msg.get("version", "")).substr(0, 64), "seen": now}
		if not known or games[addr]["players"] != g["players"] or games[addr]["date"] != g["date"]:
			changed = true
		games[addr] = g
	for a in games.keys():
		if now - int(games[a]["seen"]) > EXPIRE_MS:
			games.erase(a)
			changed = true
	return changed


func close() -> void:
	if _udp:
		_udp.close()
	_udp = null
	_listening = false
	games.clear()
