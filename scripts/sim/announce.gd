class_name Announce
extends RefCounted
## Annonces typées (étude de la fenêtre d'événement généralisée, prop. 1 à 8). Une ligne de chronique
## peut porter un type d'annonce (data/announcements.json, catalogue ouvert) et des références
## (empires, système, héros…). Le type dit la famille, la gravité selon la distance au lecteur, le ton,
## l'écran lié et l'illustration ; l'interface (AnnounceCenter) en tire avis, pastilles, fenêtres et
## Fanfares. Le registre state.announces garde les annonces typées (la chronique, elle, défile).
##
## Pour typer une ligne existante, une seule ligne avant l'appel :
##     Announce.next(state, "war_declared", {"actor": a, "target": b})
##     state.add_chronicle(...)
## add_chronicle consomme l'étiquette posée par next() (voir GameState.add_chronicle).
##
## Tout ce qui est ici est déterministe : le registre fait partie de l'état synchronisé en réseau.

const MURMUR := 0
const AVIS := 1
const WINDOW := 2
const FANFARE := 3
## Distance du lecteur à l'annonce (indice dans "g" : [soi, proche, lointain]).
const SELF := 0
const NEAR := 1
const FAR := 2


static func data() -> Dictionary:
	return GameData.announcements()


static func kind_def(kind: String) -> Dictionary:
	return data()["kinds"].get(kind, {})


static func kind_ids() -> Array[String]:
	var out: Array[String] = []
	for k in data()["kinds"]:
		out.append(String(k))
	return out


static func family_def(fam: String) -> Dictionary:
	return data()["families"].get(fam, {})


static func family_ids() -> Array[String]:
	var out: Array[String] = []
	for f in data()["families"]:
		out.append(String(f))
	return out


static func family_of(kind: String) -> String:
	return String(kind_def(kind).get("family", "colonies"))


static func family_color(fam: String) -> Color:
	var c: Array = family_def(fam).get("color", [0.38, 0.86, 0.92])
	return Color(float(c[0]), float(c[1]), float(c[2]))


static func need_color(need: String) -> Color:
	var c: Array = data()["needs"].get(need, data()["needs"]["info"])["color"]
	return Color(float(c[0]), float(c[1]), float(c[2]))


static func need_label(need: String) -> String:
	return String(data()["needs"].get(need, {}).get("label", need))


static func gravity_label(g: int) -> String:
	for d: Dictionary in data()["gravities"]:
		if int(d["id"]) == g:
			return String(d["label"])
	return "?"


static func rhythm(key: String, fallback: Variant = 0) -> Variant:
	return data()["rhythm"].get(key, fallback)


## Le type ne peut jamais descendre sous l'Avis pour l'empire concerné (prop. 30, CK3 « always_show »).
static func always(kind: String) -> bool:
	return bool(kind_def(kind).get("always", false))


# --- Étiquetage et registre ---------------------------------------------------------------------

## Pose le type de la prochaine ligne de chronique (consommé par GameState.add_chronicle).
## refs : "actor", "target" (empires), "inv" (autres empires concernés), "system", "planet", "hero",
## et pour les fenêtres spéciales des instantanés ("name", "portrait", "born", "lvl"…).
static func next(state: GameState, kind: String, refs := {}) -> void:
	if kind_def(kind).is_empty():
		push_error("Type d'annonce inconnu : %s" % kind)
		return
	state.announce_next = {"k": kind, "r": refs.duplicate(true)}


## Enregistre l'annonce qui accompagne entry (appelé par add_chronicle). Renvoie l'enregistrement.
static func record(state: GameState, entry: Dictionary, tag: Dictionary) -> Dictionary:
	var kind := String(tag["k"])
	var m := meta(state)
	var id := int(m.get("next", 1))
	m["next"] = id + 1
	var rec := {"id": id, "t": state.tick, "k": kind, "x": String(entry["text"]), "r": GameData._to_ints(tag.get("r", {}))}
	if entry.has("who"):
		rec["w"] = (entry["who"] as Array).duplicate()
	# Première de la galaxie (prop. 5) : la nouvelle passe à tout le monde, renseignement ou pas.
	if bool(kind_def(kind).get("first", false)):
		var firsts: Dictionary = m.get("firsts", {})
		if not firsts.has(kind):
			firsts[kind] = id
			m["firsts"] = firsts
			rec["f"] = 1
			rec.erase("w")
	entry["kind"] = kind
	entry["aid"] = id
	state.announces.append(rec)
	_trim(state)
	return rec


static func meta(state: GameState) -> Dictionary:
	return state.announce_meta


## Plafond du registre : on retire d'abord les plus anciennes qui ne sont pas des Fanfares.
static func _trim(state: GameState) -> void:
	var cap := int(rhythm("registry_max", 1200))
	while state.announces.size() > cap:
		var drop := 0
		for i in state.announces.size():
			if int((kind_def(String(state.announces[i]["k"])).get("g", [0]) as Array).max()) < FANFARE:
				drop = i
				break
		state.announces.remove_at(drop)


static func find(state: GameState, aid: int) -> Dictionary:
	# Les identifiants croissent : recherche dichotomique.
	var lo := 0
	var hi := state.announces.size() - 1
	while lo <= hi:
		@warning_ignore("integer_division")
		var mid := (lo + hi) / 2
		var v := int(state.announces[mid]["id"])
		if v == aid:
			return state.announces[mid]
		if v < aid:
			lo = mid + 1
		else:
			hi = mid - 1
	return {}


static func last_id(state: GameState) -> int:
	return int(state.announces.back()["id"]) if not state.announces.is_empty() else 0


# --- Lecture par un empire ----------------------------------------------------------------------

## Le lecteur (viewer < 0 : tout voir) peut-il lire cette annonce ? Même règle que la chronique.
static func can_see(rec: Dictionary, viewer: int) -> bool:
	if viewer < 0 or not rec.has("w"):
		return true
	return (rec["w"] as Array).has(viewer)


## Empires concernés : acteur, cible, autres.
static func involved(rec: Dictionary) -> Array[int]:
	var out: Array[int] = []
	var r: Dictionary = rec.get("r", {})
	for key in ["actor", "target"]:
		if r.has(key) and int(r[key]) >= 0:
			out.append(int(r[key]))
	for x in r.get("inv", []):
		if not out.has(int(x)):
			out.append(int(x))
	return out


## Distance du lecteur (prop. 4) : SELF s'il est concerné, NEAR s'il connaît un concerné (ou si
## l'annonce touche toute la galaxie), FAR sinon.
static func distance(state: GameState, rec: Dictionary, viewer: int) -> int:
	var inv := involved(rec)
	if inv.is_empty():
		return NEAR
	if inv.has(viewer):
		return SELF
	var e := state.get_empire(viewer) if viewer >= 0 else null
	if e == null:
		return NEAR
	for x in inv:
		if e.contacts.has(x):
			return NEAR
	return FAR


## Gravité par défaut pour ce lecteur, avant ses réglages : celle du type selon la distance, au moins
## Fenêtre pour une première de la galaxie, au moins Avis pour un type toujours visible qui le concerne.
static func gravity(state: GameState, rec: Dictionary, viewer: int) -> int:
	var kind := String(rec["k"])
	var g: Array = kind_def(kind).get("g", [1, 0, 0])
	var d := distance(state, rec, viewer)
	var out := int(g[mini(d, g.size() - 1)])
	if int(rec.get("f", 0)) > 0:
		out = maxi(out, WINDOW)
	if always(kind) and d == SELF:
		out = maxi(out, AVIS)
	return out


## Ton de l'annonce pour ce lecteur (or, rouge, vert, bleu de la colonne, prop. 20).
static func need(rec: Dictionary, viewer: int) -> String:
	var kd := kind_def(String(rec["k"]))
	var tone: Dictionary = kd.get("tone", {})
	var r: Dictionary = rec.get("r", {})
	if not tone.is_empty():
		if r.has("actor") and int(r["actor"]) == viewer and tone.has("actor"):
			return String(tone["actor"])
		if r.has("target") and int(r["target"]) == viewer and tone.has("target"):
			return String(tone["target"])
		if tone.has("other") and not involved(rec).has(viewer):
			return String(tone["other"])
	return String(kd.get("need", "info"))


## Titre de la fenêtre : celui du type, avec le nom du système s'il y en a un.
static func title(state: GameState, rec: Dictionary) -> String:
	var t := String(kind_def(String(rec["k"])).get("title", "Annonce"))
	return t


## Sous-titre : date, famille, et « Première de la galaxie » le cas échéant.
static func subtitle(rec: Dictionary) -> String:
	var parts := PackedStringArray([GameCalendar.date_string(int(rec["t"])), String(family_def(family_of(String(rec["k"]))).get("label", ""))])
	if int(rec.get("f", 0)) > 0:
		parts.append("Première de la galaxie")
	return "  ·  ".join(parts)


## Phrase du chroniqueur (prop. 16) : celle du type, sinon celle de sa famille.
static func lead(rec: Dictionary) -> String:
	var kd := kind_def(String(rec["k"]))
	if kd.has("lead"):
		return String(kd["lead"])
	return String(family_def(family_of(String(rec["k"]))).get("lead", ""))


static func system_of(state: GameState, rec: Dictionary) -> int:
	var r: Dictionary = rec.get("r", {})
	if r.has("system") and int(r["system"]) >= 0:
		return int(r["system"])
	if r.has("planet") and int(r["planet"]) >= 0:
		var p := state.galaxy.get_planet(int(r["planet"]))
		if p:
			return p.system_id
	return -1


## Annonces lisibles par le lecteur, de la plus récente à la plus ancienne (count <= 0 : toutes).
static func readable(state: GameState, viewer: int, count := 0) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in range(state.announces.size() - 1, -1, -1):
		var rec: Dictionary = state.announces[i]
		if can_see(rec, viewer):
			out.append(rec)
			if count > 0 and out.size() >= count:
				break
	return out


## Les « Heures » de l'empire (prop. 40) : ses Fanfares et les premières de la galaxie, dans l'ordre.
static func hours(state: GameState, viewer: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for rec: Dictionary in state.announces:
		if not can_see(rec, viewer):
			continue
		if gravity(state, rec, viewer) >= FANFARE or (int(rec.get("f", 0)) > 0 and involved(rec).has(viewer)):
			out.append(rec)
	return out


# --- Sauvegarde ---------------------------------------------------------------------------------

static func worth_saving(state: GameState) -> bool:
	return not state.announces.is_empty() or not state.announce_meta.is_empty()


static func to_dict(state: GameState) -> Dictionary:
	return {"list": state.announces.duplicate(true), "meta": state.announce_meta.duplicate(true)}


static func from_dict(state: GameState, d: Dictionary) -> void:
	state.announces.clear()
	for rec: Dictionary in d.get("list", []):
		var r := {"id": int(rec["id"]), "t": int(rec["t"]), "k": String(rec["k"]), "x": String(rec["x"]), "r": GameData._to_ints(rec.get("r", {}))}
		if rec.has("w"):
			var w := []
			for x in rec["w"]:
				w.append(int(x))
			r["w"] = w
		if rec.has("f"):
			r["f"] = int(rec["f"])
		state.announces.append(r)
	var m: Dictionary = GameData._to_ints(d.get("meta", {}))
	state.announce_meta = m
