extends SceneTree
## Vérifie que ce système d'exploitation calcule les parties exactement comme les autres.
## À lancer une fois sur chaque système (Windows, Linux) avec la même version du jeu :
##   godot --headless --path . -s res://tools/determinism_check.gd
## (sous Windows : Godot_v4.7-stable_win64_console.exe --headless --path <dossier du jeu> -s res://tools/determinism_check.gd)
##
## Deux mesures pour plusieurs galaxies (formes, placements des départs) :
## - la création : on crée la partie ici et on relève l'empreinte de son instantané de départ ;
## - la simulation : on part de l'instantané de départ fait sous Linux (tools/determinism_starts/),
##   comme un client qui reçoit la partie de l'hôte, on fait jouer les IA quelques années et on relève
##   l'empreinte de l'état chaque année.
## Le résultat est comparé ligne à ligne à tools/determinism_reference.txt (fait sous Linux) et écrit
## dans user://determinism.txt pour pouvoir l'envoyer.
##
## Si seule la création diffère, ce n'est pas grave en multijoueur : l'hôte crée la partie et envoie
## son instantané. Si la simulation diffère, elle n'est pas portable : à signaler.
## Variables : YEARS (défaut 3), WRITE_REFERENCE=1 (réécrit la référence au lieu de comparer).

const REFERENCE := "res://tools/determinism_reference.txt"
const OUTPUT := "user://determinism.txt"
const STARTS := "res://tools/determinism_starts"
const CASES := [
	{"name": "spirale-standard", "seed": 1, "galaxy": {"size": "moyenne", "shape": "spirale_3", "placement": "standard"}},
	{"name": "amas-equilibre", "seed": 42, "galaxy": {"size": "moyenne", "shape": "amas", "placement": "equilibre", "guaranteed": 2}},
	{"name": "anneau-chaotique", "seed": 1337, "galaxy": {"size": "petite", "shape": "anneau", "lanes": "denses", "placement": "chaotique"}},
	{"name": "elliptique-grande", "seed": 987654321, "galaxy": {"size": "grande", "shape": "elliptique", "placement": "equilibre"}},
]


func _initialize() -> void:
	var years := int(OS.get_environment("YEARS")) if OS.get_environment("YEARS") != "" else 3
	var write_ref := OS.get_environment("WRITE_REFERENCE") == "1"
	var lines: Array[String] = []
	for c: Dictionary in CASES:
		print("… %s" % c["name"])
		var opts := {"spectator": true, "ai_level": "normal", "galaxy": c["galaxy"]}
		var created := GameState.create(int(c["seed"]), 150, 1800.0, "", opts).to_snapshot()
		lines.append("%s création %s" % [c["name"], _hash(created)])
		var start_path := "%s/%s.json" % [STARTS, c["name"]]
		if write_ref:
			DirAccess.make_dir_recursive_absolute(STARTS)
			var w := FileAccess.open(start_path, FileAccess.WRITE)
			w.store_string(JSON.stringify(created, "", true, true))
			w.close()
		var start: Variant = JSON.parse_string(FileAccess.get_file_as_string(start_path)) if FileAccess.file_exists(start_path) else created
		var state := GameState.from_dict(start)
		if state == null:
			printerr("Instantané illisible : %s (%s)" % [start_path, GameState.last_error])
			quit(2)
			return
		var sim := Simulation.new(state)
		lines.append("%s an 0 %s" % [c["name"], sim.state.checksum().substr(0, 16)])
		for y in range(1, years + 1):
			sim.advance(360)
			lines.append("%s an %d %s" % [c["name"], y, sim.state.checksum().substr(0, 16)])
	var text := "\n".join(lines) + "\n"
	var f := FileAccess.open(OUTPUT, FileAccess.WRITE)
	if f != null:
		f.store_string("# %s · %s\n%s" % [OS.get_name(), GameVersion.label(), text])
		f.close()
	if write_ref:
		var r := FileAccess.open(REFERENCE, FileAccess.WRITE)
		r.store_string(text)
		r.close()
		print("Référence écrite (%d lignes)." % lines.size())
		quit(0)
		return
	print("Système : %s · %s" % [OS.get_name(), GameVersion.label()])
	print("Résultat écrit dans %s" % ProjectSettings.globalize_path(OUTPUT))
	if not FileAccess.file_exists(REFERENCE):
		print(text)
		print("Pas de référence à comparer.")
		quit(0)
		return
	var ref := FileAccess.get_file_as_string(REFERENCE).strip_edges().split("\n")
	var galaxy_diff := 0
	var game_diff := 0
	for i in lines.size():
		var expected := ref[i] if i < ref.size() else "(absent)"
		if lines[i] != expected:
			if lines[i].contains(" création "):
				galaxy_diff += 1
			else:
				game_diff += 1
			print("ÉCART  ici : %s\n       réf : %s" % [lines[i], expected])
	if galaxy_diff == 0 and game_diff == 0:
		print("IDENTIQUE à la référence : ce système calcule les parties comme les autres.")
	elif game_diff == 0:
		print("Créations différentes (%d), simulation identique : le multijoueur fonctionne, l'hôte crée la partie et l'envoie." % galaxy_diff)
	else:
		print("PARTIES DIFFÉRENTES (%d écarts) : envoie le fichier %s." % [game_diff, ProjectSettings.globalize_path(OUTPUT)])
	quit(0 if game_diff == 0 else 1)


func _hash(d: Dictionary) -> String:
	return JSON.stringify(d, "", true, true).sha256_text().substr(0, 16)
