class_name SpeciesLibrary
extends RefCounted
## Bibliothèque des peuples créés par le joueur : un fichier JSON par peuple dans user://species/,
## gardé d'une partie à l'autre et partageable (il suffit d'envoyer le fichier). Au démarrage,
## load_all() vérifie chaque fichier avec les règles de l'éditeur (Species.errors) et enregistre les
## peuples valides auprès de GameData : ils apparaissent alors dans les listes de Nouvelle partie,
## pour le joueur comme pour les rivaux. Un fichier hors règles est écarté, avec sa raison.

const DEFAULT_DIR := "user://species"

## Dossier des fichiers (les tests en prennent un autre pour ne pas toucher aux vrais peuples).
static var dir := DEFAULT_DIR
## Fichiers écartés au dernier chargement : [{"path", "error"}].
static var rejected: Array[Dictionary] = []


static func path_for(id: String) -> String:
	return "%s/%s.json" % [dir, id]


## Lit le dossier et enregistre les peuples valides (remplace la bibliothèque précédente).
## Renvoie le nombre de peuples chargés.
static func load_all() -> int:
	GameData.clear_library_factions()
	rejected.clear()
	var n := 0
	for path in _files():
		var spec := read_file(path)
		var err := "fichier illisible" if spec.is_empty() else Species.check(spec)
		if err == "" and path.get_file().get_basename() != String(spec["id"]):
			err = "le nom du fichier doit être l'identifiant du peuple (%s.json)" % spec["id"]
		if err != "":
			rejected.append({"path": path, "error": err})
			continue
		GameData.register_library_faction(Species.build(spec))
		n += 1
	return n


## Peuples enregistrés, par identifiant trié : leurs specs (pour rouvrir l'éditeur).
static func specs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in GameData.library_faction_ids():
		out.append((GameData.faction(id).get("spec", {}) as Dictionary).duplicate(true))
	return out


## Enregistre (ou remplace) un peuple : vérifie, écrit le fichier, met la bibliothèque à jour.
## Renvoie "" ou la raison de l'échec.
static func save(spec: Dictionary) -> String:
	var err := Species.check(spec)
	if err != "":
		return err
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(path_for(String(spec["id"])), FileAccess.WRITE)
	if f == null:
		return "écriture impossible : %s" % error_string(FileAccess.get_open_error())
	var clean := spec.duplicate(true)
	clean["format"] = Species.FORMAT
	f.store_string(JSON.stringify(clean, "\t", false))
	f.close()
	GameData.register_library_faction(Species.build(clean))
	return ""


## Supprime un peuple de la bibliothèque (son fichier aussi). Les parties sauvegardées qui le jouent
## gardent leur copie et se rechargent toujours.
static func delete(id: String) -> bool:
	if not Species.is_valid_id(id):
		return false
	GameData.unregister_library_faction(id)
	var p := path_for(id)
	if FileAccess.file_exists(p):
		return DirAccess.remove_absolute(p) == OK
	return true


## Spec lu dans un fichier ({} si illisible). Les entiers du JSON redeviennent des int.
static func read_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return {}
	return GameData._to_ints(parsed)


static func _files() -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for name in d.get_files():
		if name.get_extension() == "json":
			out.append("%s/%s" % [dir, name])
	out.sort()
	return out
