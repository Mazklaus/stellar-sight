extends SceneTree
## Contrôle du son (étude du son, J8) : liste les bus et, pour chaque repère de data/audio.json, d'où
## vient son son (fichier déposé, esquisse de synthèse, rien). Signale un repère sur un bus inconnu,
## un bouton qui pointe vers un repère absent, une famille d'annonces sans esquisse.
##   godot --headless --path . -s tools/audio_check.gd
##   godot --headless --path . -s tools/audio_check.gd -- --wav /chemin/dossier   écrit aussi les esquisses en .wav


func _init() -> void:
	var out_dir := ""
	var args := OS.get_cmdline_user_args()
	var at := args.find("--wav")
	if at >= 0 and at + 1 < args.size():
		out_dir = args[at + 1]
		DirAccess.make_dir_recursive_absolute(out_dir)
	Son.build_buses()
	var errors := 0
	var d := Son.data()
	print("Bus :")
	for b in d.get("buses", []):
		print("  %-10s vers %s" % [b["id"], b.get("send", "Master")])
	print("Repères :")
	var count := {"fichier": 0, "esquisse": 0, "": 0}
	for id in d.get("cues", {}):
		var def: Dictionary = d["cues"][id]
		var src := Son.source_of(id)
		count[src] += 1
		print("  %-16s %-10s %-9s %s" % [id, def.get("bus", "?"), src if src != "" else "muet", def.get("label", "")])
		if AudioServer.get_bus_index(String(def.get("bus", ""))) < 0:
			printerr("    bus inconnu : %s" % def.get("bus", ""))
			errors += 1
		if out_dir != "" and def.has("synth"):
			SoundSynth.stream(def["synth"]).save_to_wav("%s/%s.wav" % [out_dir, id])
	var buttons: Dictionary = d.get("buttons", {})
	for k in buttons:
		if k != "_doc" and not d["cues"].has(String(buttons[k])):
			printerr("  bouton « %s » : repère absent (%s)" % [k, buttons[k]])
			errors += 1
	print("Annonces :")
	for fam in Announce.data().get("families", {}):
		var own: bool = d.get("announce", {}).get("families", {}).has(fam)
		print("  %-12s %s" % [fam, "esquisse" if own else "esquisse commune"])
		if not own:
			errors += 1
		if out_dir != "":
			for g in [1, 2, 3]:
				SoundSynth.stream(Son.announce_recipe(fam, g)).save_to_wav("%s/annonce_%s_%d.wav" % [out_dir, fam, g])
	print("%d fichiers, %d esquisses, %d muets, %d anomalies." % [count["fichier"], count["esquisse"], count[""], errors])
	quit(1 if errors > 0 else 0)
