class_name SoundSynth
extends RefCounted
## Esquisses de synthèse (étude du son, J2) : tant qu'aucun fichier n'est déposé pour un repère, le jeu
## fabrique un son court à partir de sa recette (bloc "synth" de data/audio.json). Une recette est une
## suite de notes : w onde, f fréquence de base, notes en demi-tons, step écart entre deux notes,
## len durée d'une note, a attaque, slide glissement sur la note, lp passe-bas, gain.
## Le résultat est un AudioStreamWAV mono 16 bits, gardé en cache.

static var _cache := {}


static func rate() -> int:
	return int(GameData.audio().get("rate", 32000))


## Son de la recette, transposé de `semis` demi-tons.
static func stream(recipe: Dictionary, semis := 0.0) -> AudioStreamWAV:
	var key := "%d/%.2f" % [recipe.hash(), semis]
	if _cache.has(key):
		return _cache[key]
	var out := AudioStreamWAV.new()
	out.format = AudioStreamWAV.FORMAT_16_BITS
	out.mix_rate = rate()
	out.stereo = false
	out.data = _bytes(samples(recipe, semis))
	_cache[key] = out
	return out


## Échantillons de la recette, entre -1 et 1.
static func samples(recipe: Dictionary, semis := 0.0) -> PackedFloat32Array:
	var sr := float(rate())
	var notes: Array = recipe.get("notes", [0])
	var step := float(recipe.get("step", 0.0))
	var note_len := maxf(0.005, float(recipe.get("len", 0.1)))
	var attack := clampf(float(recipe.get("a", 0.003)), 0.0005, note_len * 0.9)
	var slide := float(recipe.get("slide", 0.0))
	var gain := float(recipe.get("gain", 0.5))
	var wave := String(recipe.get("w", "sine"))
	var base := float(recipe.get("f", 440.0)) * pow(2.0, semis / 12.0)
	var total := int(ceil((step * maxi(0, notes.size() - 1) + note_len) * sr)) + 1
	var buf := PackedFloat32Array()
	buf.resize(total)
	var n_len := int(note_len * sr)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261125
	for i in notes.size():
		var f0 := base * pow(2.0, float(notes[i]) / 12.0)
		var start := int(float(i) * step * sr)
		var phase := 0.0
		var held := 0.0
		for k in n_len:
			var t := float(k) / float(n_len)
			var f := f0 * pow(2.0, slide * t / 12.0)
			phase = fmod(phase + f / sr, 1.0)
			var v := 0.0
			match wave:
				"triangle":
					v = 4.0 * absf(phase - 0.5) - 1.0
				"saw":
					v = 2.0 * phase - 1.0
				"square":
					v = 1.0 if phase < 0.5 else -1.0
				"noise":
					# Bruit tenu : une valeur tirée à chaque période, la fréquence donne la couleur.
					if phase < f / sr:
						held = rng.randf_range(-1.0, 1.0)
					v = held
				_:
					v = sin(TAU * phase)
			var sec := float(k) / sr
			var env := minf(1.0, sec / attack) * pow(1.0 - t, 2.0)
			buf[start + k] += v * env * gain
	var lp := float(recipe.get("lp", 1.0))
	if lp < 1.0:
		# Passe-bas à un pôle : 0 fermé, 1 ouvert.
		var a := clampf(lp * lp, 0.002, 1.0)
		var y := 0.0
		for i in total:
			y += a * (buf[i] - y)
			buf[i] = y
	return buf


static func _bytes(buf: PackedFloat32Array) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(buf.size() * 2)
	for i in buf.size():
		out.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 32767.0))
	return out
