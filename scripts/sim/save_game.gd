class_name SaveGame
extends RefCounted
## Sauvegarde et chargement d'une partie, au format JSON lisible.
## Le fichier contient l'état complet et son empreinte, vérifiée au chargement.

const FORMAT_ID := "stellar-sight-save"
## Identifiant des sauvegardes écrites avant la correction du nom du jeu (« Sigth »), toujours lues.
const LEGACY_FORMAT_IDS := ["stellar-sigth-save"]
const SAVE_DIR := "user://saves"
const QUICKSAVE_PATH := "user://saves/quicksave.json"

static var last_error := ""
## Réglages de l'horloge lus par le dernier load_state() réussi ({"mode": "realtime"|"turns",
## "turn_days": int}), vide si la sauvegarde n'en contient pas (anciennes sauvegardes).
static var last_clock := {}
## État du poste rangé avec la dernière sauvegarde chargée (colonne des annonces) : hors empreinte.
static var last_ui := {}


## clock : façon de jouer (temps réel ou tour par tour), rangée à côté de l'état car ce n'est
## pas une donnée de simulation (elle n'entre pas dans l'empreinte).
## ui : état propre au poste (colonne des annonces), lui aussi hors empreinte.
## meta : ce que la liste des sauvegardes montre sans relire toute la partie ({"empire", "color",
## "kind" : "quick" | "auto" | "manual"}). Hors empreinte ; écrit avant l'état, pour être lu en tête.
static func save_state(state: GameState, path: String = QUICKSAVE_PATH, clock := {}, ui := {}, meta := {}) -> Error:
	last_error = ""
	var dir_err := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if dir_err != OK:
		last_error = "impossible de créer le dossier %s" % path.get_base_dir()
		return dir_err
	var data := {
		"format": FORMAT_ID,
		"saved_at": Time.get_datetime_string_from_system(),
		"date": GameCalendar.date_string(state.tick),
	}
	for k in ["empire", "color", "kind"]:
		if meta.has(k):
			data[k] = String(meta[k])
	data["checksum"] = state.checksum()
	# La galaxie entière : la sauvegarde se recharge à l'identique sur un autre système.
	# head() lit ce qui précède sans toucher à l'état ; l'horloge et l'état du poste viennent après.
	data["state"] = state.to_snapshot()
	if not clock.is_empty():
		data["clock"] = clock
	if not ui.is_empty():
		data["ui"] = ui
	# Écriture dans un fichier temporaire puis renommage : une coupure pendant
	# l'écriture n'abîme pas la sauvegarde précédente.
	var tmp_path := path + ".tmp"
	var f := FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		last_error = "écriture impossible : %s" % error_string(FileAccess.get_open_error())
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(data, "\t", false, true))
	f.close()
	var err := DirAccess.rename_absolute(tmp_path, path)
	if err != OK:
		last_error = "renommage impossible : %s" % error_string(err)
	return err


## Charge une sauvegarde. Renvoie null en cas d'échec (détail dans SaveGame.last_error).
static func load_state(path: String = QUICKSAVE_PATH) -> GameState:
	last_error = ""
	last_clock = {}
	last_ui = {}
	if not FileAccess.file_exists(path):
		last_error = "aucune sauvegarde"
		return null
	var text := FileAccess.get_file_as_string(path)
	var json := JSON.new()
	var parsed: Variant = json.data if json.parse(text) == OK else null
	if not parsed is Dictionary or not _known_format(parsed.get("format", "")) or not parsed.get("state") is Dictionary:
		last_error = "fichier de sauvegarde illisible"
		return null
	var state := GameState.from_dict(parsed["state"])
	if state == null:
		last_error = GameState.last_error
		return null
	if state.checksum() != String(parsed.get("checksum", "")):
		last_error = "sauvegarde abîmée (empreinte différente)"
		return null
	if parsed.get("clock") is Dictionary:
		last_clock = parsed["clock"]
	if parsed.get("ui") is Dictionary:
		last_ui = parsed["ui"]
	return state


static func exists(path: String = QUICKSAVE_PATH) -> bool:
	return FileAccess.file_exists(path)


static func _known_format(id: Variant) -> bool:
	return id == FORMAT_ID or LEGACY_FORMAT_IDS.has(id)


# --- Liste des sauvegardes (refonte D3b) ----------------------------------------------------------

const HEAD_BYTES := 4096
const AUTOSAVE_SLOTS := 3
## Sauvegarde automatique de la partie en réseau : elle se reprend depuis la page Multijoueur.
const HIDDEN_FILES := ["multi_auto.json"]


## L'en-tête d'une sauvegarde (date de jeu, moment, peuple, genre), lu sans charger la partie : les
## premiers octets du fichier, coupés avant l'état. Vide si le fichier n'est pas une sauvegarde.
static func head(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_buffer(mini(HEAD_BYTES, f.get_length())).get_string_from_utf8()
	f.close()
	var cut := text.find("\"state\"")
	if cut < 0:
		return {}
	var parsed: Variant = JSON.parse_string(text.substr(0, cut).strip_edges().trim_suffix(",") + "}")
	if not parsed is Dictionary or not _known_format(parsed.get("format", "")):
		return {}
	return parsed


## Les sauvegardes d'un dossier, la plus récente d'abord : l'en-tête de chacune, plus "path" et "mtime".
static func list(dir := SAVE_DIR) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for name in d.get_files():
		if not name.ends_with(".json") or HIDDEN_FILES.has(name):
			continue
		var h := head(dir.path_join(name))
		if h.is_empty():
			continue
		h["path"] = dir.path_join(name)
		h["mtime"] = int(FileAccess.get_modified_time(dir.path_join(name)))
		out.append(h)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["mtime"]) != int(b["mtime"]):
			return int(a["mtime"]) > int(b["mtime"])
		return String(a.get("saved_at", "")) > String(b.get("saved_at", "")) or (String(a.get("saved_at", "")) == String(b.get("saved_at", "")) and String(a["path"]) > String(b["path"])))
	return out


## Chemin d'une nouvelle sauvegarde à la main : partie_AAAAMMJJ_HHMMSS.json, sans écraser.
static func new_path(dir := SAVE_DIR) -> String:
	var t := Time.get_datetime_dict_from_system()
	var base := "partie_%04d%02d%02d_%02d%02d%02d" % [t["year"], t["month"], t["day"], t["hour"], t["minute"], t["second"]]
	var path := dir.path_join(base + ".json")
	var n := 2
	while FileAccess.file_exists(path):
		path = dir.path_join("%s_%d.json" % [base, n])
		n += 1
	return path


## Où écrire la prochaine sauvegarde automatique : trois fichiers qui tournent, le plus ancien d'abord.
static func autosave_path(dir := SAVE_DIR) -> String:
	var best := ""
	var best_time := -1
	for i in AUTOSAVE_SLOTS:
		var path := dir.path_join("auto_%d.json" % (i + 1))
		if not FileAccess.file_exists(path):
			return path
		var t := int(FileAccess.get_modified_time(path))
		if best_time < 0 or t < best_time:
			best_time = t
			best = path
	return best


static func thumb_path(path: String) -> String:
	return path.get_basename() + ".png"


## La vignette rangée à côté d'une sauvegarde (null s'il n'y en a pas).
static func thumbnail(path: String) -> Image:
	if not FileAccess.file_exists(thumb_path(path)):
		return null
	var img := Image.new()
	return img if img.load(thumb_path(path)) == OK else null


## Efface une sauvegarde et sa vignette.
static func remove(path: String) -> void:
	DirAccess.remove_absolute(path)
	if FileAccess.file_exists(thumb_path(path)):
		DirAccess.remove_absolute(thumb_path(path))
