class_name PortProbe
extends Node
## Vérifie qu'une partie répond à une adresse, sans la rejoindre : connexion ENet, attente du défi
## (« challenge ») que l'hôte envoie à chaque nouveau venu, puis on raccroche. Sert au joueur qui
## veut savoir si l'hôte est joignable, et à l'hôte pour tester son port depuis son adresse Internet.
## Le résultat arrive par finished (ok, mot de passe demandé, message).

signal finished(ok: bool, password_required: bool, message: String)

const TIMEOUT_MS := 8000

var address := ""
var port := 0
var _peer: ENetMultiplayerPeer
var _deadline := 0


func start(address_: String, port_: int) -> Error:
	stop()
	address = address_.strip_edges()
	port = port_
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_client(address, port)
	if err != OK:
		_peer = null
		return err
	_deadline = Time.get_ticks_msec() + TIMEOUT_MS
	return OK


func busy() -> bool:
	return _peer != null


func stop() -> void:
	if _peer:
		_peer.close()
	_peer = null


func _process(_delta: float) -> void:
	if _peer == null:
		return
	_peer.poll()
	while _peer and _peer.get_available_packet_count() > 0:
		var data := _peer.get_packet()
		if data.size() > 4096:
			continue
		var msg: Variant = bytes_to_var(data)
		if msg is Dictionary and String(msg.get("k", "")) == "challenge":
			var pw := bool(msg.get("pw", false))
			stop()
			finished.emit(true, pw, "La partie répond à %s, port %d%s." % [address, port, " (mot de passe demandé)" if pw else ""])
			return
	if _peer and Time.get_ticks_msec() > _deadline:
		stop()
		finished.emit(false, false, "Aucune réponse de %s, port %d (UDP)." % [address, port])
