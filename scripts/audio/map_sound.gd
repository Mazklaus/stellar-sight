class_name MapSound
extends Node
## Les sons localisés de la carte (étude du son, bloc B ; réglages : bloc "map" de data/audio.json).
## Sur la carte, une étoile explorée, une flotte visible ou un siège s'entend seulement de très près
## et près du centre de l'écran. Dans la vue système, l'étoile et ses planètes forment un fond léger,
## la planète choisie passe devant. Tout reste sous la musique, qui joue seule aux paliers Galaxie et
## Région. Douze voix au plus : les sons les plus présents gagnent, deux sources du même son n'en
## occupent qu'une.
## mix() est une fonction pure (tests) ; le nœud relève les sources cinq fois par seconde et fait
## glisser le volume et le panoramique de chaque voix vers sa cible.

const VOICE_BUS := "CarteV%d"

var view: GalaxyView
var camera: Camera2D
var system_screen: SystemScreen
## Un écran plein recouvre-t-il la carte ? (main.is_modal_open)
var modal := Callable()

var _voices: Array = []  # {player, bus, sound, gain, pan, target, target_pan}
var _clock := 0.0
var _filter: AudioEffectLowPassFilter
var _cut := 20500.0
var _cut_target := 20500.0


static func cfg() -> Dictionary:
	return Son.data().get("map", {})


## Mélange des sources : [{sound, gain 0 à 1, pan -1 à 1}], du plus présent au moins présent.
## Une source de la carte : {sound, kind, pos, weight} ; opts : {center, zoom, half, half_w, factor}.
## Une source déjà placée (vue système) : {sound, gain, pan}.
static func mix(emitters: Array, opts: Dictionary) -> Array:
	var c := cfg()
	var zoom := float(opts.get("zoom", 1.0))
	var center: Vector2 = opts.get("center", Vector2.ZERO)
	var half := maxf(1.0, float(opts.get("half", 540.0)))
	var half_w := maxf(1.0, float(opts.get("half_w", half * 16.0 / 9.0)))
	var factor := float(opts.get("factor", 1.0))
	var best := {}
	for e: Dictionary in emitters:
		var gain := 0.0
		var pan := 0.0
		if e.has("gain"):
			gain = float(e["gain"])
			pan = float(e.get("pan", 0.0))
		else:
			var kind := String(e.get("kind", "star"))
			var gate: Array = c.get("gate", {}).get(kind, [1.7, 2.6])
			var near := smoothstep(float(gate[0]), float(gate[1]), zoom)
			if near <= 0.0:
				continue
			var off: Vector2 = ((e["pos"] as Vector2) - center) * zoom
			var reach := float(c.get("reach", {}).get(kind, 0.8))
			var close := clampf(1.0 - off.length() / (half * reach), 0.0, 1.0)
			gain = near * close * close * float(e.get("weight", 1.0))
			pan = clampf(off.x / half_w, -1.0, 1.0) * 0.8
		gain = clampf(gain * factor, 0.0, 1.0)
		if gain < 0.01:
			continue
		var sound := String(e["sound"])
		if not best.has(sound) or gain > float(best[sound]["gain"]):
			best[sound] = {"sound": sound, "gain": gain, "pan": pan}
	var out: Array = best.values()
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["gain"] > b["gain"] if not is_equal_approx(a["gain"], b["gain"]) else String(a["sound"]) < String(b["sound"]))
	return out.slice(0, int(c.get("voices", 12)))


## Sources de la carte : étoiles explorées, flottes visibles, systèmes assiégés.
static func map_emitters(v: GalaxyView) -> Array:
	var out: Array = []
	if v == null or v.state == null or v.galaxy == null:
		return out
	var w: Dictionary = cfg().get("weight", {})
	for s: StarSystem in v.galaxy.systems:
		var sid := s.id
		if not v.is_explored(sid):
			continue
		out.append({"sound": "etoile_" + s.star_type, "kind": "star", "pos": s.position, "weight": float(w.get("star", 1.0))})
		if v.state.sieges.has(sid) and v.is_seen(sid):
			out.append({"sound": "etat_siege", "kind": "siege", "pos": s.position, "weight": float(w.get("siege", 0.9))})
	var at: Dictionary = v.fleet_positions()
	for fid: int in at:
		var f: Fleet = v.state.fleets[fid]
		var e: Empire = v.state.get_empire(f.owner)
		var style := SpeciesLook.hull_style(e.faction_id) if e != null else "fuseau"
		out.append({"sound": "flotte_" + style, "kind": "fleet", "pos": at[fid],
			"weight": float(w.get("fleet" if f.is_moving() else "fleet_idle", 0.5))})
	return out


## Sources de la vue système : l'étoile, chaque planète, l'état des colonies.
static func system_emitters(screen: SystemScreen) -> Array:
	var out: Array = []
	var sv := screen.view
	if sv == null or sv.system == null or sv.state == null:
		return out
	var c := cfg()
	var w: Dictionary = c.get("weight", {})
	var rect := sv.scene_rect()
	var half_w := maxf(1.0, rect.size.x * 0.5)
	var mid := rect.get_center().x
	out.append({"sound": "etoile_" + sv.system.star_type, "gain": float(w.get("system_star", 0.5)),
		"pan": clampf((sv.star_center().x - mid) / half_w, -1.0, 1.0) * 0.8})
	for pid: int in sv.system.planet_ids:
		var p: Planet = sv.state.galaxy.get_planet(pid)
		if p == null:
			continue
		var chosen := pid == sv.selected_planet
		var pan := clampf((sv.planet_position(pid).x - mid) / half_w, -1.0, 1.0) * 0.8
		out.append({"sound": "monde_" + p.type, "pan": pan, "gain": float(w.get("planet_selected" if chosen else "planet", 0.4))})
		var col: Colony = sv.state.colonies.get(pid)
		if col == null:
			continue
		var g := float(w.get("state", 0.5)) * (1.0 if chosen else 0.5)
		if sv.state.sieges.has(sv.system.id):
			out.append({"sound": "etat_siege", "pan": pan, "gain": g})
		elif col.buildings.size() >= int(c.get("industry_buildings", 6)):
			out.append({"sound": "etat_industrie", "pan": pan, "gain": g})
		elif col.population >= int(c.get("city_pop", 12)):
			out.append({"sound": "etat_ville", "pan": pan, "gain": g})
	return out


## Son d'une source : son fichier (assets/sounds/carte/<id>.ogg ou .wav, mis en boucle), sinon le
## fond de synthèse de son préfixe.
static func stream_for(sound: String, dir := "", loop := true) -> AudioStream:
	var c := cfg()
	var base := "%s%s/%s" % [String(Son.data().get("dir", "res://assets/sounds/")), dir if dir != "" else String(c.get("dir", "carte")), sound]
	for ext in Son.data().get("ext", ["ogg", "wav"]):
		var p := "%s.%s" % [base, String(ext)]
		var s: AudioStream = null
		if ResourceLoader.exists(p):
			s = load(p)
		elif FileAccess.file_exists(p):
			s = AudioStreamOggVorbis.load_from_file(p) if String(ext) == "ogg" else AudioStreamWAV.load_from_file(p)
		if s is AudioStreamOggVorbis:
			(s as AudioStreamOggVorbis).loop = loop
		elif s is AudioStreamWAV and loop:
			(s as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
			(s as AudioStreamWAV).loop_end = int((s as AudioStreamWAV).get_length() * (s as AudioStreamWAV).mix_rate)
		if s != null:
			return s
	var bed: Dictionary = c.get("beds", {}).get(sound.get_slice("_", 0), {}) if loop else {}
	if bed.is_empty():
		return null
	return SoundSynth.bed(bed, float(posmod(sound.hash(), 9) - 4))


## Une voix = un lecteur sur son bus à panoramique, tous versés dans le bus de la carte, qui porte le
## passe-bas de la pause et du trou noir.
static func build_buses() -> void:
	var c := cfg()
	var main := String(c.get("bus", "Carte"))
	var at := AudioServer.get_bus_index(main)
	if at < 0:
		return
	if Son._effect_at(at, "AudioEffectLowPassFilter") < 0:
		var lp := AudioEffectLowPassFilter.new()
		lp.cutoff_hz = float(c.get("open_hz", 20500.0))
		AudioServer.add_bus_effect(at, lp)
	for i in int(c.get("voices", 12)):
		var id := VOICE_BUS % i
		if AudioServer.get_bus_index(id) >= 0:
			continue
		AudioServer.add_bus()
		var b := AudioServer.bus_count - 1
		AudioServer.set_bus_name(b, id)
		AudioServer.set_bus_send(b, main)
		AudioServer.add_bus_effect(b, AudioEffectPanner.new())


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	build_buses()
	var c := cfg()
	var main := AudioServer.get_bus_index(String(c.get("bus", "Carte")))
	if main >= 0:
		_filter = AudioServer.get_bus_effect(main, Son._effect_at(main, "AudioEffectLowPassFilter")) as AudioEffectLowPassFilter
	_cut = float(c.get("open_hz", 20500.0))
	_cut_target = _cut
	for i in int(c.get("voices", 12)):
		var p := AudioStreamPlayer.new()
		p.bus = StringName(VOICE_BUS % i)
		add_child(p)
		_voices.append({"player": p, "bus": AudioServer.get_bus_index(VOICE_BUS % i), "sound": "", "gain": 0.0, "pan": 0.0, "target": 0.0, "target_pan": 0.0})


func _process(delta: float) -> void:
	var c := cfg()
	_clock -= delta
	if _clock <= 0.0:
		_clock = float(c.get("tick", 0.2))
		retarget(sources())
	var rate := delta / maxf(0.05, float(c.get("fade", 1.2)))
	var top := db_to_linear(float(c.get("vol", -9.0)))
	for v: Dictionary in _voices:
		if v["sound"] == "":
			continue
		v["gain"] = move_toward(float(v["gain"]), float(v["target"]), rate)
		v["pan"] = move_toward(float(v["pan"]), float(v["target_pan"]), rate * 2.0)
		var p: AudioStreamPlayer = v["player"]
		if v["gain"] <= 0.0 and v["target"] <= 0.0:
			p.stop()
			v["sound"] = ""
			continue
		p.volume_db = linear_to_db(maxf(0.0001, float(v["gain"]) * top))
		if int(v["bus"]) >= 0:
			(AudioServer.get_bus_effect(int(v["bus"]), 0) as AudioEffectPanner).pan = float(v["pan"])
	if _filter != null:
		_cut = move_toward(_cut, _cut_target, delta * 30000.0)
		_filter.cutoff_hz = _cut


## Le mélange voulu à cet instant (carte ou vue système), écrans, lentille et pause compris.
func sources() -> Array:
	var c := cfg()
	_cut_target = float(c.get("open_hz", 20500.0))
	var clock := get_node_or_null("/root/GameClock")
	if clock != null and clock.paused and not clock.is_turn_based():
		_cut_target = float(c.get("pause_hz", 1400.0))
	var factor := 1.0
	if modal.is_valid() and modal.call():
		# Un écran plein éloigne la carte : plus bas, derrière un filtre (C1).
		factor = float(c.get("modal", 0.25))
		_cut_target = minf(_cut_target, float(c.get("modal_hz", 900.0)))
	var out: Array = []
	if system_screen != null and system_screen.is_open():
		out = mix(system_emitters(system_screen), {"factor": factor})
	elif view != null and camera != null and view.visible:
		if view.lens != "":
			factor *= float(c.get("lens", 0.5))
		var size := get_viewport().get_visible_rect().size
		out = mix(map_emitters(view), {"center": camera.get_screen_center_position(), "zoom": camera.zoom.x,
			"half": size.y * 0.5, "half_w": size.x * 0.5, "factor": factor})
	if not out.is_empty() and String(out[0]["sound"]) == "etoile_black_hole":
		_cut_target = minf(_cut_target, float(c.get("hole_hz", 2600.0)))
	return out


## Donne à chaque voix sa cible : une voix garde son son, un son nouveau prend une voix libre.
func retarget(mixed: Array) -> void:
	var want := {}
	for m: Dictionary in mixed:
		want[String(m["sound"])] = m
	for v: Dictionary in _voices:
		if v["sound"] != "" and want.has(v["sound"]):
			var m: Dictionary = want[v["sound"]]
			v["target"] = m["gain"]
			v["target_pan"] = m["pan"]
			want.erase(v["sound"])
		else:
			v["target"] = 0.0
	for sound: String in want:
		for v: Dictionary in _voices:
			if v["sound"] != "":
				continue
			var stream := stream_for(sound)
			if stream == null:
				break
			var m: Dictionary = want[sound]
			v["sound"] = sound
			v["gain"] = 0.0
			v["pan"] = m["pan"]
			v["target"] = m["gain"]
			v["target_pan"] = m["pan"]
			var p: AudioStreamPlayer = v["player"]
			p.stream = stream
			p.volume_db = -80.0
			p.play(randf() * stream.get_length())
			break


## Sons en cours et leur cible (tests, outil de contrôle).
func playing() -> Dictionary:
	var out := {}
	for v: Dictionary in _voices:
		if v["sound"] != "":
			out[v["sound"]] = v["target"]
	return out
