class_name PortMapper
extends RefCounted
## Ouvre le port de la partie sur la box par UPnP, pour que des joueurs puissent rejoindre par
## Internet sans régler la box à la main. Tout se passe dans un fil (la recherche de la box prend
## une ou deux secondes) ; le résultat arrive par finished, sur le fil principal.
## Sans box UPnP (désactivé, réseau d'entreprise, double NAT…), finished donne la raison : il reste
## la redirection de port à la main ou Tailscale.

signal finished(ok: bool, external_address: String, reason: String)

const DESCRIPTION := "Stellar Sigth"
const DISCOVER_MS := 2000

var port := 0
## La box a accepté la redirection (à retirer en partant).
var mapped := false
var external_address := ""
var _upnp: UPNP
var _thread: Thread
## Numéro de la demande en cours : une réponse arrivée après close() (ou un nouvel open) est périmée.
var _gen := 0
## Recherches abandonnées encore en cours (la recherche de la box peut durer plusieurs secondes : on
## ne bloque pas le jeu pour l'attendre). Rejointes dès qu'elles répondent, ou par shutdown().
var _old_threads: Array[Thread] = []


## Lance la recherche de la box et la redirection du port UDP.
func open(port_: int) -> void:
	close()
	port = port_
	_thread = Thread.new()
	_thread.start(_work.bind(port_, _gen))


func busy() -> bool:
	return _thread != null and _thread.is_alive()


func _work(p: int, gen: int) -> void:
	var u := UPNP.new()
	var err := u.discover(DISCOVER_MS, 2, "InternetGatewayDevice")
	if err != UPNP.UPNP_RESULT_SUCCESS or u.get_gateway() == null or not u.get_gateway().is_valid_gateway():
		_done.call_deferred(false, "", "aucune box compatible UPnP trouvée" if err in [UPNP.UPNP_RESULT_SUCCESS, UPNP.UPNP_RESULT_NO_GATEWAY, UPNP.UPNP_RESULT_NO_DEVICES] else "recherche UPnP impossible (code %d)" % err, null, gen)
		return
	var res := u.add_port_mapping(p, p, DESCRIPTION, "UDP", 0)
	if res != UPNP.UPNP_RESULT_SUCCESS:
		_done.call_deferred(false, "", "la box refuse d'ouvrir le port %d (code %d)" % [p, res], null, gen)
		return
	_done.call_deferred(true, u.query_external_address(), "", u, gen)


func _done(ok: bool, address: String, reason: String, u: UPNP, gen: int) -> void:
	_join_old(false)
	if gen != _gen:
		# Partie refermée entre-temps : on ne laisse pas le port ouvert.
		if ok and u:
			u.delete_port_mapping(port, "UDP")
		return
	if _thread:
		_thread.wait_to_finish()
		_thread = null
	_upnp = u
	mapped = ok
	external_address = address
	finished.emit(ok, address, reason)


## Referme le port sur la box (en quittant la partie). Une recherche en cours est abandonnée sans
## l'attendre ; si elle ouvre quand même le port, sa réponse le referme.
func close() -> void:
	_gen += 1
	if _thread:
		_old_threads.append(_thread)
		_thread = null
	if mapped and _upnp:
		_upnp.delete_port_mapping(port, "UDP")
	mapped = false
	_upnp = null
	external_address = ""


## Avant de quitter le jeu : attend les recherches encore en cours.
func shutdown() -> void:
	close()
	_join_old(true)


func _join_old(all: bool) -> void:
	for t in _old_threads.duplicate():
		if all or not t.is_alive():
			t.wait_to_finish()
			_old_threads.erase(t)
