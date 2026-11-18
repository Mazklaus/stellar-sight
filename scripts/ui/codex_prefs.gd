class_name CodexPrefs
extends RefCounted
## Ce que le Codex retient sur ce poste (user://codex.cfg), hors de toute partie :
## - les Chroniques collectionnées (prop. 31), acquises pour de bon d'une partie à l'autre ;
## - les articles lus (pastille « nouveau », prop. 33) et les articles épinglés (prop. 29).
## Un fragment de lore appartient à un chapitre du manuel ; il se débloque quand la chronique de la
## partie (ce que le joueur a le droit d'y lire) nomme un terme de ce chapitre. Les fragments de
## l'ouverture du manuel (prélude, chapitres 1 et 2) sont acquis d'emblée.
## Le verrou des fiches (peuples, faune, gardiens, crises…) suit la partie en cours (CodexProgress) ;
## hors partie, seules les fiches secrètes (gardiens, crises, zone scellée) restent scellées.

const PATH := "user://codex.cfg"
const FREE_CHAPTERS := ["00-prelude", "02-premiere-partie", "03-interface"]

static var _loaded := false
static var chronicles: Dictionary = {}
static var read: Dictionary = {}
static var pins: Array[String] = []
## Partie en cours et lecteur (null hors partie) ; posés par main.
static var state: GameState
static var viewer := -1
static var _scan_idx := 0
static var _scan_state: GameState
static var _known_cache: Dictionary = {}
static var _known_tick := -1
static var _known_at := -1.0
## Fragments débloqués depuis la dernière lecture (pour la pastille et l'annonce).
static var fresh: Array[String] = []
## Faux pendant les tests : rien n'est écrit dans user://codex.cfg.
static var persist := true


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for id in cfg.get_value("codex", "chronicles", []):
		chronicles[String(id)] = true
	for id in cfg.get_value("codex", "read", []):
		read[String(id)] = true
	for id in cfg.get_value("codex", "pins", []):
		pins.append(String(id))


static func save() -> void:
	if not persist:
		return
	var cfg := ConfigFile.new()
	cfg.set_value("codex", "chronicles", chronicles.keys())
	cfg.set_value("codex", "read", read.keys())
	cfg.set_value("codex", "pins", pins)
	cfg.save(PATH)


## Pour les tests : oublie tout (sans toucher au fichier si save_after est faux).
static func reset(save_after := false) -> void:
	_loaded = true
	chronicles.clear()
	read.clear()
	pins.clear()
	fresh.clear()
	_scan_idx = 0
	_scan_state = null
	if save_after:
		save()


static func set_game(s: GameState, eid: int) -> void:
	ensure_loaded()
	state = s
	viewer = eid
	_known_tick = -1
	if s != _scan_state:
		_scan_state = s
		_scan_idx = 0


# --- Verrous ---------------------------------------------------------------------------------------

## L'article est-il ouvert au lecteur ? (fiches verrouillées, sections secrètes, fragments)
static func unlocked(aid: String) -> bool:
	ensure_loaded()
	if aid.begins_with("frag:"):
		return chronicle_unlocked(aid.substr(5))
	if aid.begins_with("man:"):
		var c := CodexData.section_chapter(aid.substr(4))
		if bool(c.get("secret", false)):
			return _secret_section_open(aid.substr(4))
		return true
	var t := Glossary.term(aid)
	if not bool(t.get("locked", false)):
		return true
	if state == null:
		return not bool(t.get("secret", false))
	return _known().has(aid)


static func _known() -> Dictionary:
	if state == null:
		return {}
	var now := Time.get_ticks_msec() / 1000.0
	if _known_tick != state.tick or now - _known_at > 2.0:
		_known_tick = state.tick
		_known_at = now
		_known_cache.clear()
		for id in (state.codex.get("seen", {}) as Dictionary).get(str(viewer), []):
			_known_cache[String(id)] = true
		for id in CodexProgress.known_now(state, viewer):
			_known_cache[id] = true
	return _known_cache


## Une section de la zone scellée s'ouvre quand le joueur a rencontré un secret qu'elle nomme.
static func _secret_section_open(sid: String) -> bool:
	if state == null:
		return false
	var low := String(CodexData.section(sid).get("text", "")).to_lower() + " " + String(CodexData.section(sid).get("title", "")).to_lower()
	for id: String in _known():
		var t := Glossary.term(id)
		if bool(t.get("secret", false)) and low.contains(String(t.get("name", "")).to_lower()):
			return true
	return false


# --- Chroniques --------------------------------------------------------------------------------

static func chronicle_unlocked(fid: String) -> bool:
	ensure_loaded()
	if chronicles.has(fid):
		return true
	var fr := CodexData.fragment(fid)
	return FREE_CHAPTERS.has(String(fr.get("chapter", "")))


## Lit les nouvelles entrées de la chronique de la partie : chaque terme nommé débloque le premier
## fragment encore scellé d'un de ses chapitres. Renvoie les fragments débloqués.
static func scan() -> Array[String]:
	ensure_loaded()
	var got: Array[String] = []
	if state == null:
		return got
	var n := state.chronicle.size()
	if _scan_idx > n:
		_scan_idx = 0
	var chapters_hit := {}
	for i in range(_scan_idx, n):
		var entry: Dictionary = state.chronicle[i]
		if not Espionage.can_read(entry, viewer):
			continue
		for tid in Glossary.find_terms(String(entry.get("text", ""))):
			for ch in Glossary.term(tid).get("chapters", []):
				chapters_hit[String(ch)] = true
	_scan_idx = n
	if chapters_hit.is_empty():
		return got
	for fr: Dictionary in CodexData.fragments:
		var ch := String(fr["chapter"])
		var fid := String(fr["id"])
		if chapters_hit.has(ch) and not chronicle_unlocked(fid):
			chronicles[fid] = true
			fresh.append(fid)
			got.append(fid)
			chapters_hit.erase(ch)  # un fragment par chapitre et par lecture
	if not got.is_empty():
		save()
	return got


static func chronicle_count() -> Vector2i:
	CodexData.ensure_loaded()
	var have := 0
	for fr: Dictionary in CodexData.fragments:
		if chronicle_unlocked(String(fr["id"])):
			have += 1
	return Vector2i(have, CodexData.fragments.size())


# --- Lu, épinglé -------------------------------------------------------------------------------

## « Nouveau » : un fragment fraîchement débloqué, ou une fiche verrouillée rencontrée, pas encore lus.
static func is_new(aid: String) -> bool:
	ensure_loaded()
	if read.has(aid):
		return false
	if aid.begins_with("frag:"):
		return fresh.has(aid.substr(5))
	return bool(Glossary.term(aid).get("locked", false)) and state != null and unlocked(aid)


static func mark_read(aid: String) -> void:
	ensure_loaded()
	if read.has(aid):
		return
	read[aid] = true
	if aid.begins_with("frag:"):
		fresh.erase(aid.substr(5))
	save()


static func has_new() -> bool:
	if not fresh.is_empty():
		return true
	if state == null:
		return false
	for id: String in _known():
		if not read.has(id):
			return true
	return false


static func toggle_pin(aid: String) -> void:
	ensure_loaded()
	if pins.has(aid):
		pins.erase(aid)
	else:
		pins.append(aid)
	save()
