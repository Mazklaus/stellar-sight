class_name UserDataMigration
extends RefCounted
## Le dossier user:// suit le nom du projet (application/config/name). Corriger « Stellar Sigth » en
## « Stellar Sight » l'a déplacé : au premier lancement, on recopie l'ancien dossier (sauvegardes,
## peuples créés, réglages, préréglages) dans le nouveau s'il est encore vide. L'ancien dossier est
## laissé tel quel (rien n'est supprimé).

const OLD_DIR_NAME := "Stellar Sigth"


static func run() -> void:
	var new_dir := OS.get_user_data_dir()
	if new_dir.get_file() == OLD_DIR_NAME:
		return
	var old_dir := new_dir.get_base_dir().path_join(OLD_DIR_NAME)
	if not DirAccess.dir_exists_absolute(old_dir) or _has_content(new_dir):
		return
	var copied := _copy_dir(old_dir, new_dir)
	print("Données de « %s » recopiées dans « %s » (%d fichiers)." % [old_dir, new_dir, copied])


## Vrai si le dossier contient déjà des données du joueur (on ne mélange jamais deux dossiers).
static func _has_content(path: String) -> bool:
	var d := DirAccess.open(path)
	if d == null:
		return false
	for f in d.get_files():
		if f.get_extension() in ["cfg", "json"]:
			return true
	for sub in d.get_directories():
		if sub in ["saves", "species"]:
			return true
	return false


static func _copy_dir(from: String, to: String) -> int:
	var d := DirAccess.open(from)
	if d == null or DirAccess.make_dir_recursive_absolute(to) != OK:
		return 0
	var n := 0
	for f in d.get_files():
		if DirAccess.copy_absolute(from.path_join(f), to.path_join(f)) == OK:
			n += 1
	for sub in d.get_directories():
		# Caches et journaux du moteur : Godot les recrée.
		if sub in ["logs", "shader_cache", "vulkan"]:
			continue
		n += _copy_dir(from.path_join(sub), to.path_join(sub))
	return n
