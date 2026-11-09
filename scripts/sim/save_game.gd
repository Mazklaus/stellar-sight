class_name SaveGame
extends RefCounted
## Sauvegarde et chargement d'une partie, au format JSON lisible.
## Le fichier contient l'état complet et son empreinte, vérifiée au chargement.

const FORMAT_ID := "stellar-sigth-save"
const SAVE_DIR := "user://saves"
const QUICKSAVE_PATH := "user://saves/quicksave.json"

static var last_error := ""


static func save_state(state: GameState, path: String = QUICKSAVE_PATH) -> Error:
	last_error = ""
	var dir_err := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if dir_err != OK:
		last_error = "impossible de créer le dossier %s" % path.get_base_dir()
		return dir_err
	var data := {
		"format": FORMAT_ID,
		"saved_at": Time.get_datetime_string_from_system(),
		"date": GameCalendar.date_string(state.tick),
		"checksum": state.checksum(),
		"state": state.to_dict(),
	}
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
	if not FileAccess.file_exists(path):
		last_error = "aucune sauvegarde"
		return null
	var text := FileAccess.get_file_as_string(path)
	var json := JSON.new()
	var parsed: Variant = json.data if json.parse(text) == OK else null
	if not parsed is Dictionary or parsed.get("format", "") != FORMAT_ID or not parsed.get("state") is Dictionary:
		last_error = "fichier de sauvegarde illisible"
		return null
	var state := GameState.from_dict(parsed["state"])
	if state == null:
		last_error = GameState.last_error
		return null
	if state.checksum() != String(parsed.get("checksum", "")):
		last_error = "sauvegarde abîmée (empreinte différente)"
		return null
	return state


static func exists(path: String = QUICKSAVE_PATH) -> bool:
	return FileAccess.file_exists(path)
