class_name PeopleSound
extends RefCounted
## La signature sonore des peuples (étude du son, bloc D ; réglages : bloc "peoples" de data/audio.json).
## Chaque peuple a un indicatif de quelques notes et une façon de parler. L'humeur transforme
## l'indicatif selon le statut diplomatique : doublé à l'octave pour un allié, assombri en guerre
## froide, grave et frappé en guerre. La parole est fabriquée d'après le texte affiché : sa longueur
## donne le nombre de syllabes, sa ponctuation les silences. Un peuple créé dans l'éditeur prend la
## palette de son registre, décalée d'après son nom. Les Silencieux n'ont ni indicatif ni parole.


static func cfg() -> Dictionary:
	return Son.data().get("peoples", {})


## Fiche sonore d'un peuple : la sienne, sinon celle de son registre (D3), sinon celle par défaut.
static func signature(faction_id: String) -> Dictionary:
	var c := cfg()
	var all: Dictionary = c.get("signatures", {})
	if all.has(faction_id):
		return all[faction_id]
	var reg := String(GameData.faction(faction_id).get("registre", ""))
	var base := String(c.get("registers", {}).get(reg, c.get("default", "")))
	var out: Dictionary = (all.get(base, {}) as Dictionary).duplicate(true)
	if out.has("synth"):
		# Même palette que le peuple modèle, hauteur et voix décalées d'après le nom : deux peuples
		# créés dans le même registre ne se confondent pas.
		var shift := float(posmod(faction_id.hash(), 7) - 3)
		out["synth"]["f"] = float(out["synth"]["f"]) * pow(2.0, shift / 12.0)
		out["voice_f"] = float(out.get("voice_f", 150.0)) * pow(2.0, shift / 12.0)
	return out


static func is_mute(faction_id: String) -> bool:
	return bool(signature(faction_id).get("mute", false)) or not signature(faction_id).has("synth")


## Recette de l'indicatif d'un peuple selon l'humeur ("alliance", "peace", "cold", "war", "none").
static func jingle(faction_id: String, mood := "peace") -> Dictionary:
	if is_mute(faction_id):
		return {}
	var out: Dictionary = (signature(faction_id)["synth"] as Dictionary).duplicate(true)
	var m: Dictionary = cfg().get("moods", {}).get(mood, {})
	out["f"] = float(out["f"]) * pow(2.0, float(m.get("semis", 0)) / 12.0)
	out["len"] = float(out["len"]) * float(m.get("len", 1.0))
	out["step"] = float(out["step"]) * float(m.get("len", 1.0))
	out["lp"] = clampf(float(out.get("lp", 1.0)) * float(m.get("lp", 1.0)), 0.03, 1.0)
	var notes: Array = (out["notes"] as Array).duplicate()
	if bool(m.get("octave", false)) and not notes.is_empty():
		notes.append(float(notes[notes.size() - 1]) + 12.0)
	if bool(m.get("hit", false)):
		notes.push_front(-12.0)
	out["notes"] = notes
	return out


## Recette de la parole d'un peuple pour un texte : une syllabe par paquet de caractères, un silence
## à chaque ponctuation, la mélodie tirée du texte lui-même (le même texte se dit toujours pareil).
static func speech(faction_id: String, text: String) -> Dictionary:
	if is_mute(faction_id) or text.strip_edges() == "":
		return {}
	var c := cfg()
	var sig := signature(faction_id)
	var voice: Dictionary = c.get("voices", {}).get(String(sig.get("voice", "formant")), {})
	var sp: Dictionary = c.get("speech", {})
	var slow := float(voice.get("slow", 1.0))
	var syl := float(sp.get("syllable", 0.11)) * slow
	var count := clampi(int(ceil(float(text.length()) / float(sp.get("chars", 9)) / slow)), 1, maxi(1, int(float(sp.get("max", 1.8)) / syl)))
	var spread := int(voice.get("spread", 5))
	var rng := RandomNumberGenerator.new()
	rng.seed = text.hash()
	var notes: Array = []
	var marks := 0
	for ch in text:
		marks += 1 if ch in [",", ".", ";", ":", "!", "?"] else 0
	var pause_every := maxi(2, count / maxi(1, marks + 1))
	for i in count:
		if i > 0 and i % pause_every == 0 and i < count - 1:
			notes.append(-60.0)  # trop grave pour s'entendre : le silence d'une virgule
			continue
		notes.append(float(rng.randi_range(-spread, spread)) if spread > 0 else 0.0)
		if bool(voice.get("double", false)):
			notes[notes.size() - 1] = float(notes[notes.size() - 1]) + (7.0 if i % 2 == 1 else 0.0)
	return {"w": String(voice.get("w", "saw")), "f": float(sig.get("voice_f", 150.0)), "notes": notes, "step": syl,
		"len": syl * 1.3, "a": minf(0.02, syl * 0.2), "lp": float(voice.get("lp", 0.4)), "gain": 0.4}


## Son de l'indicatif : le fichier du peuple s'il existe (assets/sounds/peuples/indicatif_<id>),
## sinon l'esquisse.
static func jingle_stream(faction_id: String, mood := "peace") -> AudioStream:
	var recipe := jingle(faction_id, mood)
	if recipe.is_empty():
		return null
	var base := "%speuples/indicatif_%s" % [String(Son.data().get("dir", "res://assets/sounds/")), faction_id]
	for ext in Son.data().get("ext", ["ogg", "wav"]):
		if ResourceLoader.exists("%s.%s" % [base, String(ext)]):
			return load("%s.%s" % [base, String(ext)])
	return SoundSynth.stream(recipe)


## Joue l'indicatif d'un peuple, puis sa parole si le réglage le permet (Q3).
static func hail(faction_id: String, mood := "peace", text := "") -> void:
	Son.heard.append("peuple:%s:%s" % [faction_id, mood])
	if Son.heard.size() > 64:
		Son.heard.remove_at(0)
	var c := cfg()
	var s := jingle_stream(faction_id, mood)
	if s == null:
		return
	var semis := float(c.get("moods", {}).get(mood, {}).get("semis", 0))
	Son.play_stream(s, String(c.get("bus", "Signaux")), float(c.get("vol", -14.0)), 1.0 if s is AudioStreamWAV else pow(2.0, semis / 12.0))
	if SoundSettings.speech and text != "":
		var words := speech(faction_id, text)
		if not words.is_empty():
			Son.play_stream(SoundSynth.stream(words), String(c.get("speech_bus", "Voix")), float(c.get("speech_vol", -18.0)))
