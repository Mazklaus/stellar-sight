class_name AnnounceSounds
extends RefCounted
## Points d'accroche du son des annonces (étude de la fenêtre d'événement, prop. 32). À chaque ouverture,
## on cherche <dir><type>.<ext>, puis <dir><famille>.<ext>, puis <dir>gravite_<n>.<ext> (bloc "sounds" de
## data/announcements.json) ; s'il n'y a aucun fichier, l'esquisse de synthèse de la famille joue à la
## place (Son.announce, étude du son F4). Tout sort sur le bus Annonces, qui fait baisser la musique.
## Réglage « Son des annonces » : AnnounceSettings.sound.

static var _paths := {}
static var _player: AudioStreamPlayer
## Derniers repères demandés (tests) : "type/gravité".
static var heard: Array[String] = []


static func path_of(id: String) -> String:
	if _paths.has(id):
		return _paths[id]
	var cfg: Dictionary = Announce.data().get("sounds", {})
	var out := ""
	for ext in cfg.get("ext", ["ogg", "wav"]):
		var p := "%s%s.%s" % [String(cfg.get("dir", "res://assets/sounds/announce/")), id, String(ext)]
		if ResourceLoader.exists(p):
			out = p
			break
	_paths[id] = out
	return out


static func play(kind: String, gravity: int) -> void:
	heard.append("%s/%d" % [kind, gravity])
	if heard.size() > 20:
		heard.remove_at(0)
	if not AnnounceSettings.sound:
		return
	var p := ""
	for id in [kind, Announce.family_of(kind), "gravite_%d" % gravity]:
		p = path_of(id)
		if p != "":
			break
	if p == "":
		Son.announce(Announce.family_of(kind), gravity)
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	if _player == null or not is_instance_valid(_player):
		_player = AudioStreamPlayer.new()
		tree.root.add_child(_player)
	if AudioServer.get_bus_index("Annonces") >= 0:
		_player.bus = &"Annonces"
	_player.stream = load(p)
	_player.play()
