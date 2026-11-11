class_name GameVersion
extends RefCounted
## Empreinte de la version du jeu, comparée dans le salon multijoueur : deux machines dont les règles
## (data/), la simulation (scripts/sim/) ou le réseau (scripts/net/) diffèrent ne resteraient pas synchronisées, même d'un
## chiffre dans un fichier de données. On refuse donc tout joueur dont l'empreinte diffère.
##
## L'empreinte couvre les fichiers tels qu'ils sont dans le jeu lancé : tout le monde doit jouer avec
## la même version (le même export, ou le même dossier de projet).

## Dossiers qui décident du déroulement d'une partie.
const ROOTS := ["res://data", "res://scripts/sim", "res://scripts/net"]
## Fichiers sans effet sur la partie (métadonnées de l'éditeur).
const IGNORED_EXTENSIONS := ["uid", "import"]

static var _cached := ""


## Empreinte courte (16 caractères hexadécimaux), calculée une fois par lancement.
static func fingerprint() -> String:
	if _cached == "":
		_cached = compute(ROOTS).substr(0, 16)
	return _cached


## Version lisible : nom et version du projet, version de Godot, empreinte.
static func label() -> String:
	var v := str(ProjectSettings.get_setting("application/config/version", ""))
	return "%s%s · Godot %s · %s" % [
		ProjectSettings.get_setting("application/config/name", "Stellar Sigth"),
		(" " + v) if v != "" else "",
		Engine.get_version_info().get("string", "?"),
		fingerprint(),
	]


## SHA-256 des fichiers des dossiers donnés (chemins triés, chemin + contenu), et de la version de
## Godot (le moteur fait les calculs : deux versions peuvent arrondir différemment).
static func compute(roots: Array) -> String:
	var files: Array[String] = []
	for root: String in roots:
		_collect(root, files)
	files.sort()
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(str(Engine.get_version_info().get("hex", 0)).to_utf8_buffer())
	for path in files:
		ctx.update(path.to_utf8_buffer())
		ctx.update(FileAccess.get_file_as_bytes(path))
	return ctx.finish().hex_encode()


static func _collect(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_collect(dir_path.path_join(sub), out)
	for f in dir.get_files():
		if not IGNORED_EXTENSIONS.has(f.get_extension()):
			out.append(dir_path.path_join(f))
