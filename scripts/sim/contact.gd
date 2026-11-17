class_name Contact
extends RefCounted
## La victoire de Contact (étude du 2026-11-17, 45 propositions validées ; données : data/contact.json).
##
## Un seul Signal par partie, venu d'au-delà de la galaxie (prop. 4). Quatre étapes :
## 1. Écouter : la technologie Écoute profonde ; on capte par deux voies sur trois (prop. 8) : une
##    Oreille de la Bordure qui a fini d'écouter (prop. 9), un Écho fossile relevé (prop. 10), la
##    technologie Grammaire des étoiles (prop. 3). Une voie seule = Signal partiel.
## 2. Déchiffrer : jauge 0-1000 (prop. 12), quatre couches à 250/500/750/1000 (prop. 13-17), chacune
##    une carte d'événement, un don, un indice sur la nature des Lointains (prop. 19).
## 3. Décider : les Taiseux, la loi du Silence et les objecteurs (lots 2-3).
## 4. Répondre : le Héraut (après les Plans), puis la Transmission (prop. 29-31) ; à son terme, l'issue
##    dépend de la nature des Lointains, tirée en secret à la création (prop. 34).
##
## Réglages : « Contact » Complet / Victoire seule / Désactivé (prop. 5), « Lointains » (prop. 6),
## « Issue » Victoire / Ouverture (prop. 7). Sans l'option (tests, bancs) : désactivé.
##
## État : state.contact = {"mode", "nmode", "outcome", "nature", "routes": {"eid": {route: jour}},
##  "ears": {"planète": jours écoutés}, "echoes": {"sid": 1}, "survey": {"eid:sid": jours},
##  "net": {"eid": années}, "alerts": {"eid": restantes}, "alert": {"eid": {alerte en attente}},
##  "gauge": {"eid": 0-1000}, "layers": {"eid": couches atteintes 0-4}, "share": {"eid": %},
##  "cadj": {"eid": ajustement de certitude}, "elim": {"eid": [natures écartées]},
##  "read": {"eid": {"menace": n, "outil": n}}, "plans": {"eid": "raw" | "audit" | jour de fin d'audit},
##  "gifts": {"eid": [dons]}, "abc": {"eid": jour de fin de l'intuition}, "tx": {"eid": {"prog",
##  "rate", "start", "lost"}}, "done": {"eid": jour}, "failed": {"eid": jour}, "first": {"porteuse":
##  eid}, "st": {"eid": {statistiques}}, "fxsig", et les sous-états des lots 2 et 3.
## Tout est déterministe : entiers, tirages par hachage de la graine, ordres par SimCommands.

const SUBS := ["routes", "ears", "echoes", "survey", "net", "alerts", "alert", "gauge", "layers", "share", "cadj", "elim", "read", "plans",
		"gifts", "abc", "tx", "done", "failed", "first", "st", "fxsig", "frag", "offers", "cons", "echo_hit", "taiseux", "voyage",
		"incoming", "porteuse_until", "scars", "threats", "faith_seen", "city_heraut", "interp", "ear_own"]

static var _edge_key := ""
static var _edge: Dictionary = {}


static func data() -> Dictionary:
	return GameData.contact()


static func cfg(section: String) -> Dictionary:
	var v: Variant = data().get(section, {})
	return v if v is Dictionary else {}


static func c_int(section: String, key: String, def := 0) -> int:
	return int(cfg(section).get(key, def))


static func mode_defs() -> Array:
	return data().get("modes", [])


static func default_mode() -> String:
	return String(data().get("default_mode", "complete"))


static func nature_mode_defs() -> Array:
	return data().get("nature_modes", [])


static func default_nature_mode() -> String:
	return String(data().get("default_nature_mode", "hasard"))


static func outcome_defs() -> Array:
	return data().get("outcomes", [])


static func default_outcome() -> String:
	return String(data().get("default_outcome", "victoire"))


static func mode(state: GameState) -> String:
	return String(state.contact.get("mode", "desactive"))


static func nature_mode(state: GameState) -> String:
	return String(state.contact.get("nmode", "hasard"))


static func outcome(state: GameState) -> String:
	return String(state.contact.get("outcome", "victoire"))


static func enabled(state: GameState) -> bool:
	return state != null and not state.contact.is_empty()


## Mode Complet : fragments, Consortium, espionnage, Amphictyonie, objecteurs, Taiseux, saboteurs, crises.
static func full(state: GameState) -> bool:
	return enabled(state) and mode(state) == "complete"


static func opens(state: GameState) -> bool:
	return enabled(state) and outcome(state) == "ouverture"


static func applies(state: GameState, eid: int) -> bool:
	var e := state.get_empire(eid) if enabled(state) and eid >= 0 else null
	return e != null and not e.is_npc() and not e.eliminated


static func _label_of(defs: Array, id: String, def: String) -> String:
	for m: Dictionary in defs:
		if String(m["id"]) == id:
			return String(m["label"])
	return def


static func mode_label(state: GameState) -> String:
	return _label_of(mode_defs(), mode(state), "Désactivé")


static func nature_mode_label(state: GameState) -> String:
	return _label_of(nature_mode_defs(), nature_mode(state), "Au hasard")


static func outcome_label(state: GameState) -> String:
	return _label_of(outcome_defs(), outcome(state), "Victoire")


# --- Réglage, sauvegarde -----------------------------------------------------------------------

static func _valid(defs: Array, id: String) -> bool:
	for m: Dictionary in defs:
		if String(m["id"]) == id:
			return true
	return false


static func setup(state: GameState, mode_id: String, nature_id := "", outcome_id := "") -> void:
	state.contact = {}
	if not _valid(mode_defs(), mode_id) or mode_id == "desactive":
		return
	var nm := nature_id if _valid(nature_mode_defs(), nature_id) else default_nature_mode()
	var oc := outcome_id if _valid(outcome_defs(), outcome_id) else default_outcome()
	state.contact = {"mode": mode_id, "nmode": nm, "outcome": oc}
	for k in SUBS:
		state.contact[k] = {}
	state.contact["nature"] = _draw_nature(state)
	place_echoes(state)


static func worth_saving(state: GameState) -> bool:
	return enabled(state)


static func to_dict(state: GameState) -> Dictionary:
	return state.contact.duplicate(true)


static func from_dict(state: GameState, d: Dictionary) -> void:
	if d.is_empty():
		state.contact = {}
		return
	state.contact = GameData._to_ints(d.duplicate(true))
	for k in SUBS:
		if not state.contact.has(k):
			state.contact[k] = {}


static func sub(state: GameState, k: String) -> Dictionary:
	if state.contact.is_empty():
		return {}  # pilier désactivé : ne jamais le rallumer en écrivant
	if not state.contact.has(k) or not (state.contact[k] is Dictionary):
		state.contact[k] = {}
	return state.contact[k]


static func _h(state: GameState, parts: Array) -> int:
	return absi(hash([state.seed_value, "ct"] + parts))


static func _stat(state: GameState, eid: int, k: String, n: int) -> void:
	if state.contact.is_empty():
		return
	var st := sub(state, "st")
	var d: Dictionary = st.get(str(eid), {})
	d[k] = int(d.get(k, 0)) + n
	st[str(eid)] = d


static func stat(state: GameState, eid: int, k: String) -> int:
	return int((sub(state, "st").get(str(eid), {}) as Dictionary).get(k, 0))


static func month_days() -> int:
	return int(GameData.rules()["month_days"])


# --- Talents, peuples --------------------------------------------------------------------------

## Talent de Contact du peuple (prop. 36).
static func talent(state: GameState, eid: int) -> Dictionary:
	var e := state.get_empire(eid)
	if e == null:
		return {}
	var v: Variant = cfg("talents").get(Genetics.root(e.faction_id), null)
	return v if v is Dictionary else {}


static func t_int(state: GameState, eid: int, key: String) -> int:
	var v: Variant = talent(state, eid).get(key, 0)
	return int(v) if (v is int or v is float) else 0


static func credo(state: GameState, eid: int) -> String:
	var e := state.get_empire(eid)
	return "" if e == null else String(FactionTraits.species(e.faction()).get("credo", ""))


## Nom du Signal et voix des couches selon le peuple (prop. 35).
static func voice(state: GameState, eid: int, key: String) -> String:
	var names := cfg("names")
	var e := state.get_empire(eid)
	var d: Dictionary = names.get(Genetics.root(e.faction_id), {}) if e != null else {}
	if d.has(key):
		return String(d[key])
	return String((names.get("default", {}) as Dictionary).get(key, ""))


static func signal_name(state: GameState, eid: int) -> String:
	var n := voice(state, eid, "name")
	return n if n != "" else "le Signal"


# --- Les Lointains -----------------------------------------------------------------------------

static func nature_defs() -> Array:
	return cfg("natures").get("list", [])


static func nature_def(id: String) -> Dictionary:
	for n: Dictionary in nature_defs():
		if String(n["id"]) == id:
			return n
	return {}


static func nature(state: GameState) -> String:
	return String(state.contact.get("nature", "batisseurs"))


static func nature_label(id: String) -> String:
	return String(nature_def(id).get("label", id))


static func _draw_nature(state: GameState) -> String:
	if nature_mode(state) == "bienveillants":
		return "batisseurs"
	var total := 0
	for n: Dictionary in nature_defs():
		total += maxi(0, int(n.get("weight", 0)))
	if total <= 0:
		return "batisseurs"
	var roll := _h(state, ["nature"]) % total
	for n: Dictionary in nature_defs():
		roll -= maxi(0, int(n.get("weight", 0)))
		if roll < 0:
			return String(n["id"])
	return "batisseurs"


## Natures encore possibles aux yeux de l'empire (dossier, prop. 19).
static func possible_natures(state: GameState, eid: int) -> Array[String]:
	var out: Array[String] = []
	var el: Array = sub(state, "elim").get(str(eid), [])
	for n: Dictionary in nature_defs():
		if not el.has(String(n["id"])):
			out.append(String(n["id"]))
	return out


## Écarte n natures fausses de plus du dossier (ordre fixé par hachage) ; all = toutes sauf la vraie.
static func eliminate(state: GameState, eid: int, n: int, all := false) -> void:
	if nature_mode(state) == "sans_indices":
		return
	var el: Array = sub(state, "elim").get(str(eid), []).duplicate()
	var wrong: Array = []
	for nd: Dictionary in nature_defs():
		var id := String(nd["id"])
		if id != nature(state) and not el.has(id):
			wrong.append(id)
	wrong.sort_custom(func(a: String, b: String) -> bool: return _h(state, ["elim", a]) < _h(state, ["elim", b]))
	var k := wrong.size() if all else mini(n, wrong.size())
	for i in k:
		el.append(wrong[i])
	sub(state, "elim")[str(eid)] = el


## L'empire sait-il (dossier réduit à une nature) ?
static func knows_nature(state: GameState, eid: int) -> bool:
	return possible_natures(state, eid).size() == 1


## L'empire juge-t-il possible une nature dangereuse (Affamés, ou Semeurs sans audit) ?
static func fears(state: GameState, eid: int) -> bool:
	var pn := possible_natures(state, eid)
	if pn.has("affames"):
		return true
	return pn.has("semeurs") and plans_state(state, eid) != "audit"


# --- La Bordure --------------------------------------------------------------------------------

## Systèmes de la Bordure : la part edge_pct % la plus loin du centre de la galaxie.
static func edge_systems(state: GameState) -> Dictionary:
	var key := "%d|%d" % [state.seed_value, state.galaxy.systems.size()]
	if key == _edge_key:
		return _edge
	var center := Vector2.ZERO
	for s in state.galaxy.systems:
		center += s.position
	center /= maxf(1.0, float(state.galaxy.systems.size()))
	var ids: Array = []
	for s in state.galaxy.systems:
		ids.append([s.position.distance_to(center), s.id])
	ids.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0] or (a[0] == b[0] and int(a[1]) < int(b[1])))
	@warning_ignore("integer_division")
	var n := maxi(1, ids.size() * c_int("ear", "edge_pct", 25) / 100)
	_edge = {}
	for i in mini(n, ids.size()):
		_edge[int(ids[i][1])] = true
	_edge_key = key
	return _edge


static func is_edge(state: GameState, sid: int) -> bool:
	return edge_systems(state).has(sid)


# --- Voies de capture --------------------------------------------------------------------------

static func listen_tech() -> String:
	return String(cfg("techs").get("listen", "ecoute_profonde"))


static func grammar_tech() -> String:
	return String(cfg("techs").get("grammar", "grammaire_etoiles"))


static func listens(state: GameState, eid: int) -> bool:
	var e := state.get_empire(eid)
	return e != null and e.techs.has(listen_tech())


static func routes(state: GameState, eid: int) -> Dictionary:
	return sub(state, "routes").get(str(eid), {})


static func route_count(state: GameState, eid: int) -> int:
	return routes(state, eid).size()


static func captured(state: GameState, eid: int) -> bool:
	return route_count(state, eid) >= c_int("capture", "need", 2)


static func partial(state: GameState, eid: int) -> bool:
	return route_count(state, eid) > 0 and not captured(state, eid)


static func route_label(r: String) -> String:
	return String((cfg("capture").get("routes", {}) as Dictionary).get(r, r))


## Ajoute une voie ; la première ouvre l'alerte (vraie), la deuxième la capture complète.
static func add_route(state: GameState, eid: int, r: String, added: Array[Dictionary]) -> void:
	if not applies(state, eid) or routes(state, eid).has(r):
		return
	var was := route_count(state, eid)
	var rs := routes(state, eid).duplicate()
	rs[r] = state.tick
	sub(state, "routes")[str(eid)] = rs
	_stat(state, eid, "routes", 1)
	state.relic_rev += 1
	var e := state.get_empire(eid)
	if was == 0:
		sub(state, "alerts")[str(eid)] = 0  # plus de fausses alertes après la vraie
		_push_alert(state, eid, true, "", added)
		Announce.next(state, "signal_heard", {"actor": eid})
		added.append(state.add_chronicle("%s capte quelque chose (%s) : %s, peut-être. Il faut une deuxième voie pour l'entendre en entier." % [e.display_name(), route_label(r), signal_name(state, eid)],
				Espionage.private_to(state, [eid])))
	elif was + 1 == c_int("capture", "need", 2):
		added.append(state.add_chronicle("%s capte %s en entier (%s). Le déchiffrement peut commencer pour de bon." % [e.display_name(), signal_name(state, eid), route_label(r)],
				Espionage.private_to(state, [eid])))


# --- Oreilles de la Bordure --------------------------------------------------------------------

static func ear_building() -> String:
	return String(cfg("ear").get("building", "oreille_bordure"))


## Une nébuleuse rend l'Oreille sourde (prop. 9, 41).
static func deaf(state: GameState, sid: int) -> bool:
	var deafs: Array = cfg("ear").get("deaf_terrains", [])
	for t in Terrain.at(state, sid):
		if deafs.has(t) or String(t).begins_with("nebul"):
			return true
	return false


## Un trou noir ou une géante bleue dans le système ou à un saut (prop. 9, 29).
static func amplified(state: GameState, sid: int) -> bool:
	var stars: Array = cfg("ear").get("amp_stars", [])
	if sid < 0 or sid >= state.galaxy.systems.size():
		return false
	if stars.has(state.galaxy.systems[sid].star_type):
		return true
	for l in state.galaxy.lanes:
		var o := l.y if l.x == sid else (l.x if l.y == sid else -1)
		if o >= 0 and stars.has(state.galaxy.systems[o].star_type):
			return true
	return false


## Jours d'écoute nécessaires pour une Oreille dans ce système.
static func ear_need(state: GameState, sid: int) -> int:
	var d := c_int("ear", "listen_days", 720) if is_edge(state, sid) else c_int("ear", "inner_days", 1440)
	if amplified(state, sid):
		d -= c_int("ear", "amp_days", 180)
	return maxi(month_days(), d)


## Oreilles de l'empire : [[planète, système, jours écoutés, besoin]].
static func ears_of(state: GameState, eid: int) -> Array:
	var out := []
	var b := ear_building()
	var es := sub(state, "ears")
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner == eid and c.buildings.has(b):
			var sid := state.galaxy.get_planet(int(pid)).system_id
			out.append([int(pid), sid, int(es.get(str(pid), 0)), ear_need(state, sid)])
	return out


## Oreilles qui ont fini d'écouter (elles nourrissent le déchiffrement et raccourcissent la Transmission).
static func ears_done(state: GameState, eid: int) -> int:
	var n := 0
	for x in ears_of(state, eid):
		if int(x[2]) >= int(x[3]):
			n += 1
	n += ContactVoices.extra_ears(state, eid)
	return mini(n, c_int("ear", "ear_cap", 5))


static func _tick_ears(state: GameState, added: Array[Dictionary]) -> void:
	var b := ear_building()
	var es := sub(state, "ears")
	for k in es.keys():
		var c: Colony = state.colonies.get(int(k))
		if c == null or not c.buildings.has(b):
			es.erase(k)
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if not c.buildings.has(b) or not applies(state, c.owner):
			continue
		var sid := state.galaxy.get_planet(int(pid)).system_id
		if deaf(state, sid):
			continue
		var need := ear_need(state, sid)
		var was := int(es.get(str(pid), 0))
		es[str(pid)] = mini(need, was + month_days())
		if was < need and int(es[str(pid)]) >= need:
			add_route(state, c.owner, "ear", added)


# --- Échos fossiles ----------------------------------------------------------------------------

static func echo_sites(state: GameState) -> Array[int]:
	var out: Array[int] = []
	for k in sub(state, "echoes"):
		out.append(int(k))
	out.sort()
	return out


static func is_echo(state: GameState, sid: int) -> bool:
	return sub(state, "echoes").has(str(sid))


## Place 4 à 8 Échos à la création : étoiles mortes et ruines d'abord, loin des capitales (prop. 10).
static func place_echoes(state: GameState) -> void:
	var ec := cfg("echoes")
	@warning_ignore("integer_division")
	var n := clampi(state.galaxy.systems.size() / maxi(1, int(ec.get("per_systems", 25))), int(ec.get("min", 4)), int(ec.get("max", 8)))
	var caps := {}
	for e in state.empires:
		var cs := FactionTraits.capital_system(state, e.id)
		if cs >= 0:
			caps[cs] = true
	var prefer: Array = ec.get("prefer_stars", [])
	var cand: Array = []
	for s in state.galaxy.systems:
		if caps.has(s.id) or state.system_owner(s.id) >= 0:
			continue
		var w := 0 if prefer.has(s.star_type) else 1
		cand.append([w, _h(state, ["echo", s.id]), s.id])
	for sid in ContactVoices.kheb_sites(state):
		cand.append([-1, 0, sid])
	cand.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	var es := sub(state, "echoes")
	for x in cand:
		if es.size() >= n:
			break
		es[str(int(x[2]))] = 1


## Relevés : une flotte à l'arrêt dans le système, ou le système tenu (technologie Écoute profonde).
static func _tick_echoes(state: GameState, added: Array[Dictionary]) -> void:
	var sites := echo_sites(state)
	if sites.is_empty():
		return
	var here := {}
	for fid in state.fleets:
		var f: Fleet = state.fleets[fid]
		if f.is_moving() or not is_echo(state, f.system_id):
			continue
		here["%d:%d" % [f.owner, f.system_id]] = true
	for sid in sites:
		var ow := state.system_owner(sid)
		if ow >= 0:
			here["%d:%d" % [ow, sid]] = true
	var sv := sub(state, "survey")
	var keys := here.keys()
	keys.sort()
	for k in keys:
		var eid := int(String(k).get_slice(":", 0))
		if not applies(state, eid) or not listens(state, eid) or routes(state, eid).has("echo"):
			continue
		var need := c_int("echoes", "survey_days", 90)
		var v := int(sv.get(k, 0)) + month_days()
		sv[k] = v
		if v >= need:
			add_route(state, eid, "echo", added)


## Filet (prop. 10) : chaque année sans capter, une chance croissante qu'un Écho se révèle près de chez soi.
static func _yearly_net(state: GameState, eid: int, added: Array[Dictionary]) -> void:
	if captured(state, eid) or routes(state, eid).has("echo") or not listens(state, eid):
		return
	var net := sub(state, "net")
	var years := int(net.get(str(eid), 0)) + 1
	net[str(eid)] = years
	if _h(state, ["net", eid, state.tick]) % 100 >= years * c_int("echoes", "net_pct", 10):
		return
	var cap := FactionTraits.capital_system(state, eid)
	if cap < 0:
		return
	var jumps := FactionTraits.jumps_from(state.galaxy, cap)
	var best := -1
	var best_j := 999
	for sid in jumps:
		var j := int(jumps[sid])
		if j >= 1 and not is_echo(state, int(sid)) and (j < best_j or (j == best_j and int(sid) < best)):
			best_j = j
			best = int(sid)
	if best < 0:
		return
	sub(state, "echoes")[str(best)] = 1
	net[str(eid)] = 0
	added.append(state.add_chronicle("Un Écho fossile se révèle près de chez %s, à %s : une vieille trace du Signal, prise dans la poussière. Il suffit d'y stationner une flotte." % [
			state.get_empire(eid).short_name(), state.galaxy.systems[best].system_name], Espionage.private_to(state, [eid])))


# --- Fausses alertes (prop. 11) ----------------------------------------------------------------

static func alert_kinds() -> Array:
	return cfg("alerts").get("kinds", [])


static func pending_alert(state: GameState, eid: int) -> Dictionary:
	return sub(state, "alert").get(str(eid), {})


static func _push_alert(state: GameState, eid: int, real: bool, kind: String, added: Array[Dictionary]) -> void:
	sub(state, "alert")[str(eid)] = {"true": 1 if real else 0, "kind": kind, "tick": state.tick}
	Events.push(state, eid, "ct_alerte", {}, added)


## Avant la vraie capture : 1 à 3 fausses alertes, une tous les 8 à 14 mois.
static func _maybe_false_alert(state: GameState, eid: int, added: Array[Dictionary]) -> void:
	if route_count(state, eid) > 0 or not listens(state, eid) or not pending_alert(state, eid).is_empty():
		return
	var al := sub(state, "alerts")
	if not al.has(str(eid)):
		var lo := c_int("alerts", "min", 1)
		var hi := c_int("alerts", "max", 3)
		al[str(eid)] = lo + _h(state, ["alerts", eid]) % maxi(1, hi - lo + 1) + ContactVoices.extra_alerts(state, eid)
	if int(al[str(eid)]) <= 0:
		return
	@warning_ignore("integer_division")
	var month := state.tick / month_days()
	if posmod(month + eid * 5, 8 + _h(state, ["alertgap", eid]) % 7) != 0:
		return
	var kinds := alert_kinds()
	if kinds.is_empty():
		return
	al[str(eid)] = int(al[str(eid)]) - 1
	var kd: Dictionary = kinds[_h(state, ["alertkind", eid, state.tick]) % kinds.size()]
	_push_alert(state, eid, false, String(kd["id"]), added)
	added.append(state.add_chronicle("%s : %s. %s" % [state.get_empire(eid).short_name(), String(kd["label"]), String(kd.get("text", ""))], Espionage.private_to(state, [eid])))


static func announce_alert(state: GameState, eid: int, added: Array[Dictionary]) -> void:
	var a := pending_alert(state, eid)
	if a.is_empty():
		return
	sub(state, "alert").erase(str(eid))
	var e := state.get_empire(eid)
	if int(a.get("true", 0)) > 0:
		e.resources["influence"] = int(e.resources.get("influence", 0)) + c_int("alerts", "announce_influence", 20)
		_stat(state, eid, "announced", 1)
		added.append(state.add_chronicle("%s annonce à toute la galaxie avoir capté un signal venu d'au-delà de la Bordure. Pour une fois, c'est vrai." % e.display_name(), Espionage.public_to(state, [eid])))
	else:
		e.resources["influence"] = maxi(0, int(e.resources.get("influence", 0)) + c_int("alerts", "false_influence", -30))
		_adj_cert(state, eid, c_int("alerts", "false_certainty", -2))
		_stat(state, eid, "false_alarm", 1)
		added.append(state.add_chronicle("%s annonce avoir capté le Signal. Trois semaines plus tard, démenti gêné : c'était %s." % [e.display_name(), _alert_label(String(a.get("kind", ""))).to_lower()], Espionage.public_to(state, [eid])))


static func verify_alert(state: GameState, eid: int) -> void:
	var a := pending_alert(state, eid)
	if a.is_empty():
		return
	a["verify"] = state.tick + c_int("alerts", "verify_days", 180)
	sub(state, "alert")[str(eid)] = a


static func _alert_label(kind: String) -> String:
	for k: Dictionary in alert_kinds():
		if String(k["id"]) == kind:
			return String(k["label"])
	return "une fausse alerte"


static func _tick_alert(state: GameState, eid: int, added: Array[Dictionary]) -> void:
	var a := pending_alert(state, eid)
	if a.is_empty() or int(a.get("verify", 0)) <= 0 or state.tick < int(a["verify"]):
		return
	sub(state, "alert").erase(str(eid))
	if int(a.get("true", 0)) > 0:
		_adj_cert(state, eid, c_int("certainty", "verified_alert", 1))
		added.append(state.add_chronicle("Vérification faite : le signal capté par %s est bien artificiel, et il vient de très loin." % state.get_empire(eid).short_name(), Espionage.private_to(state, [eid])))
	else:
		added.append(state.add_chronicle("Vérification faite : ce n'était que %s. Les prudents de %s ont bien fait de se taire." % [_alert_label(String(a.get("kind", ""))).to_lower(), state.get_empire(eid).short_name()], Espionage.private_to(state, [eid])))


# --- Jauge de déchiffrement (prop. 12) ---------------------------------------------------------

static func gauge(state: GameState, eid: int) -> int:
	return int(sub(state, "gauge").get(str(eid), 0))


static func gauge_max() -> int:
	return c_int("gauge", "max", 1000)


static func gauge_pct(state: GameState, eid: int) -> int:
	@warning_ignore("integer_division")
	return 100 * gauge(state, eid) / maxi(1, gauge_max())


static func share(state: GameState, eid: int) -> int:
	return int(sub(state, "share").get(str(eid), c_int("gauge", "share_default", 10)))


## Plafond de la jauge : Signal partiel (prop. 8), Abécédaire sans clé (prop. 17).
static func gauge_cap(state: GameState, eid: int) -> int:
	if not captured(state, eid):
		return c_int("capture", "partial_cap", 250) if partial(state, eid) else 0
	if not abc_key(state, eid):
		return gauge_max() - 1
	return gauge_max()


static func add_gauge(state: GameState, eid: int, n: int, added: Array[Dictionary] = []) -> void:
	if route_count(state, eid) <= 0:
		return
	var before := gauge(state, eid)
	sub(state, "gauge")[str(eid)] = clampi(before + n, 0, maxi(before, gauge_cap(state, eid)))
	_check_layers(state, eid, added)


## Savoir consacré ce mois-ci au Signal.
static func knowledge_spent(state: GameState, eid: int) -> int:
	if route_count(state, eid) <= 0 or gauge(state, eid) >= gauge_max():
		return 0
	var gross := int((Economy.empire_income(state, eid)["gross"] as Dictionary).get("knowledge", 0))
	@warning_ignore("integer_division")
	return maxi(0, gross * share(state, eid) / 100)


## Détail du gain mensuel de jauge (dixièmes de %) : [[libellé, valeur]].
@warning_ignore("integer_division")
static func gain_parts(state: GameState, eid: int) -> Array:
	var out := []
	if route_count(state, eid) <= 0 or not applies(state, eid):
		return out
	out.append(["Écoute", c_int("gauge", "base", 3)])
	var k := knowledge_spent(state, eid) / maxi(1, c_int("gauge", "knowledge_div", 2))
	if k > 0:
		out.append(["Savoir consacré (%d %%)" % share(state, eid), k])
	var ears := ears_done(state, eid)
	if ears > 0:
		out.append(["Oreilles (%d)" % ears, ears * c_int("ear", "gauge_per_ear", 2)])
	var raw := 0
	for x in out:
		raw += int(x[1])
	var pct := 0
	var why: PackedStringArray = []
	var e := state.get_empire(eid)
	if e.techs.has(grammar_tech()):
		pct += c_int("gauge", "grammar_pct", 25)
		why.append("Grammaire des étoiles")
	for x in ContactRace.gauge_pct_parts(state, eid):
		pct += int(x[1])
		why.append(String(x[0]))
	for x in ContactVoices.gauge_pct_parts(state, eid):
		pct += int(x[1])
		why.append(String(x[0]))
	if pct != 0 and raw > 0:
		out.append(["%s (%+d %%)" % [", ".join(why), pct], raw * pct / 100])
	var total := 0
	for x in out:
		total += int(x[1])
	if partial(state, eid):
		out.append(["Signal partiel (moitié de vitesse)", -total * (100 - c_int("capture", "partial_pct", 50)) / 100])
	return out


static func monthly_gain(state: GameState, eid: int) -> int:
	var n := 0
	for p in gain_parts(state, eid):
		n += int(p[1])
	return clampi(n, 0, c_int("gauge", "max_month", 60))


# --- Couches (prop. 13-18) ---------------------------------------------------------------------

static func layer_defs() -> Array:
	return data().get("layers", [])


static func layers(state: GameState, eid: int) -> int:
	return int(sub(state, "layers").get(str(eid), 0))


static func layer_label(i: int) -> String:
	var ld := layer_defs()
	return String((ld[i] as Dictionary).get("label", "")) if i >= 0 and i < ld.size() else ""


static func has_layer(state: GameState, eid: int, id: String) -> bool:
	var ld := layer_defs()
	for i in ld.size():
		if String(ld[i]["id"]) == id:
			return layers(state, eid) > i
	return false


static func _check_layers(state: GameState, eid: int, added: Array[Dictionary]) -> void:
	var ld := layer_defs()
	while layers(state, eid) < ld.size() and gauge(state, eid) >= int(ld[layers(state, eid)]["at"]):
		var i := layers(state, eid)
		sub(state, "layers")[str(eid)] = i + 1
		_on_layer(state, eid, String(ld[i]["id"]), added)


static func _on_layer(state: GameState, eid: int, id: String, added: Array[Dictionary]) -> void:
	var e := state.get_empire(eid)
	_stat(state, eid, "layer_" + id, 1)
	state.relic_rev += 1
	var ld: Dictionary = {}
	for x: Dictionary in layer_defs():
		if String(x["id"]) == id:
			ld = x
	added.append(state.add_chronicle("%s déchiffre %s de %s. « %s »" % [e.display_name(), String(ld.get("label", id)).to_lower(), signal_name(state, eid), voice(state, eid, id)],
			Espionage.private_to(state, [eid])))
	match id:
		"porteuse":
			_on_porteuse(state, eid, added)
		"echo":
			eliminate(state, eid, 1)
			ContactRace.on_echo(state, eid, added)
		"plans":
			eliminate(state, eid, 2)
		"abecedaire":
			eliminate(state, eid, 0, true)
			_stat(state, eid, "abc", 1)
	ContactVoices.on_layer(state, eid, id, added)
	var card := String(ld.get("card", ""))
	if card != "":
		Events.push(state, eid, card, {}, added)


## Première Porteuse de la galaxie : annonce, et stabilité par credo pour tous (prop. 14).
static func _on_porteuse(state: GameState, eid: int, added: Array[Dictionary]) -> void:
	var first := sub(state, "first")
	if first.has("porteuse"):
		return
	first["porteuse"] = eid
	sub(state, "porteuse_until")["t"] = state.tick + c_int("porteuse", "days", 360)
	_stat(state, eid, "first_porteuse", 1)
	Announce.next(state, "contact_porteuse", {"actor": eid})
	added.append(state.add_chronicle("Nous ne sommes pas seuls : %s déchiffre la Porteuse d'un signal venu d'au-delà de la galaxie. Des nombres premiers, sans fin. Dans tous les empires, on lève les yeux." % state.get_empire(eid).display_name()))
	ContactVoices.on_porteuse(state, eid, added)


## Lecture ambiguë d'une couche (prop. 18).
static func read_layer(state: GameState, eid: int, how: String) -> void:
	var r: Dictionary = sub(state, "read").get(str(eid), {}).duplicate()
	r[how] = int(r.get(how, 0)) + 1
	sub(state, "read")[str(eid)] = r
	state.relic_rev += 1


static func readings(state: GameState, eid: int, how: String) -> int:
	return int((sub(state, "read").get(str(eid), {}) as Dictionary).get(how, 0))


# --- Les Plans (prop. 16) ----------------------------------------------------------------------

## "" (pas encore décidé), "raw", "audit" (achevé), "auditing" (en cours).
static func plans_state(state: GameState, eid: int) -> String:
	var v: Variant = sub(state, "plans").get(str(eid), "")
	if v is int:
		return "audit" if state.tick >= int(v) else "auditing"
	return String(v)


static func plans_raw(state: GameState, eid: int, added: Array[Dictionary]) -> void:
	if plans_state(state, eid) != "":
		return
	sub(state, "plans")[str(eid)] = "raw"
	var gifts: Array = cfg("plans").get("gifts", [])
	if not gifts.is_empty():
		var g: Dictionary = gifts[_h(state, ["gift", eid]) % gifts.size()]
		var have: Array = sub(state, "gifts").get(str(eid), []).duplicate()
		have.append(String(g["id"]))
		sub(state, "gifts")[str(eid)] = have
		added.append(state.add_chronicle("%s bâtit les Plans tels quels : %s (%s)." % [state.get_empire(eid).short_name(), String(g["label"]), String(g.get("text", ""))], Espionage.private_to(state, [eid])))
	state.relic_rev += 1


static func plans_audit(state: GameState, eid: int) -> void:
	if plans_state(state, eid) != "":
		return
	sub(state, "plans")[str(eid)] = state.tick + c_int("plans", "audit_days", 360)


static func gift_def(id: String) -> Dictionary:
	for g: Dictionary in cfg("plans").get("gifts", []):
		if String(g["id"]) == id:
			return g
	return {}


# --- L'Abécédaire (prop. 17) -------------------------------------------------------------------

## La clé de lecture : un fragment étranger, la clé d'Aster, ou l'intuition achevée.
static func abc_key(state: GameState, eid: int) -> bool:
	if ContactRace.foreign_count(state, eid) > 0 or ContactVoices.aster_key(state, eid):
		return true
	var t := int(sub(state, "abc").get(str(eid), 0))
	return t > 0 and state.tick >= t


static func intuition_running(state: GameState, eid: int) -> bool:
	var t := int(sub(state, "abc").get(str(eid), 0))
	return t > 0 and state.tick < t


static func check_intuition(state: GameState, eid: int) -> String:
	if not captured(state, eid):
		return "il faut avoir capté le Signal"
	if abc_key(state, eid):
		return "vous avez déjà la clé de lecture"
	if intuition_running(state, eid):
		return "l'intuition mûrit déjà"
	if not has_layer(state, eid, "plans"):
		return "il faut d'abord les Plans"
	return ""


# --- Certitude (prop. 19) ----------------------------------------------------------------------

static func _adj_cert(state: GameState, eid: int, n: int) -> void:
	sub(state, "cadj")[str(eid)] = int(sub(state, "cadj").get(str(eid), 0)) + n


static func certainty(state: GameState, eid: int) -> int:
	if route_count(state, eid) <= 0:
		return 0
	var c := c_int("certainty", "captured", 2) if captured(state, eid) else 1
	c += layers(state, eid) * c_int("certainty", "per_layer", 2)
	c += ContactRace.foreign_count(state, eid) * c_int("certainty", "per_fragment", 1)
	c += int(sub(state, "cadj").get(str(eid), 0))
	return clampi(c, 0, c_int("certainty", "max", 10))


# --- Le Héraut et la Transmission (prop. 29-31) ------------------------------------------------

static func heraut_building() -> String:
	return String(cfg("heraut").get("building", "heraut"))


## Planète du Héraut de l'empire (-1 sinon).
static func heraut_planet(state: GameState, eid: int) -> int:
	var b := heraut_building()
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner == eid and c.buildings.has(b):
			return int(pid)
	return -1


static func heraut_system(state: GameState, eid: int) -> int:
	var p := heraut_planet(state, eid)
	if p >= 0:
		return state.galaxy.get_planet(p).system_id
	return ContactVoices.city_heraut_system(state, eid)


static func has_heraut(state: GameState, eid: int) -> bool:
	return heraut_system(state, eid) >= 0


static func tx(state: GameState, eid: int) -> Dictionary:
	return sub(state, "tx").get(str(eid), {})


static func transmitting(state: GameState, eid: int) -> bool:
	return sub(state, "tx").has(str(eid))


static func done(state: GameState, eid: int) -> bool:
	return sub(state, "done").has(str(eid))


static func failed(state: GameState, eid: int) -> bool:
	return sub(state, "failed").has(str(eid))


static func finished(state: GameState) -> bool:
	return not sub(state, "done").is_empty() or not sub(state, "failed").is_empty()


## Durée de la Transmission (jours) : base, moins Oreilles et amplification, jamais sous le plancher.
static func tx_need(state: GameState, eid: int) -> int:
	var h := cfg("heraut")
	var cut := ears_done(state, eid) * int(h.get("ear_days", 60))
	var sid := heraut_system(state, eid)
	if sid >= 0 and amplified(state, sid):
		cut += int(h.get("amp_days", 360))
	return maxi(int(h.get("min_days", 720)), int(h.get("days", 1440)) - cut)


static func tx_rate(state: GameState, eid: int) -> int:
	return int(tx(state, eid).get("rate", 0))


static func tx_cost(state: GameState, eid: int) -> int:
	return c_int("heraut", "energy_month", 8) * (1 + tx_rate(state, eid))


static func tx_pct(state: GameState, eid: int) -> int:
	@warning_ignore("integer_division")
	return mini(100, 100 * int(tx(state, eid).get("prog", 0)) / maxi(1, tx_need(state, eid)))


## Jours restants estimés au débit actuel.
@warning_ignore("integer_division")
static func tx_left(state: GameState, eid: int) -> int:
	var left := maxi(0, tx_need(state, eid) - int(tx(state, eid).get("prog", 0)))
	var speed := 100 + c_int("heraut", "rate_pct", 33) * tx_rate(state, eid)
	var by_speed := left * 100 / maxi(1, speed)
	var by_floor := maxi(0, int(tx(state, eid).get("start", state.tick)) + c_int("heraut", "min_days", 720) - state.tick)
	return maxi(by_speed, by_floor)


static func check_transmit(state: GameState, eid: int) -> String:
	if not applies(state, eid):
		return "le Contact n'est pas en jeu"
	if done(state, eid) or failed(state, eid):
		return "votre empire a déjà répondu"
	if transmitting(state, eid):
		return "la Transmission est déjà lancée"
	if not has_layer(state, eid, "plans"):
		return "il faut avoir déchiffré les Plans"
	if not has_heraut(state, eid):
		return "il faut bâtir le Héraut"
	var why := ContactVoices.transmit_block(state, eid)
	if why != "":
		return why
	return ""


static func start_tx(state: GameState, eid: int, added: Array[Dictionary]) -> void:
	sub(state, "tx")[str(eid)] = {"prog": 0, "rate": 0, "start": state.tick, "lost": 0}
	_stat(state, eid, "tx", 1)
	state.relic_rev += 1
	var e := state.get_empire(eid)
	Announce.next(state, "contact_reply", {"actor": eid, "system": heraut_system(state, eid)})
	added.append(state.add_chronicle("Alerte galactique : %s répond au Signal. Son Héraut, à %s, émet vers l'au-delà ; dans %s au plus tôt, la réponse arrivera. D'ici là, tout le monde sait où il est." % [
			e.display_name(), state.galaxy.systems[heraut_system(state, eid)].system_name, Victory._days_text(tx_left(state, eid))]))
	ContactRace.on_transmit(state, eid, added)


static func check_rate(state: GameState, eid: int, r: int) -> String:
	if not transmitting(state, eid):
		return "aucune Transmission en cours"
	if r < 0 or r > c_int("heraut", "rate_max", 3):
		return "débit inconnu"
	return ""


static func _tick_tx(state: GameState, eid: int, added: Array[Dictionary]) -> void:
	var t := tx(state, eid)
	if t.is_empty():
		return
	var e := state.get_empire(eid)
	if not has_heraut(state, eid):
		if int(t.get("lost", 0)) == 0:
			# Retour au dernier quart atteint (prop. 30).
			@warning_ignore("integer_division")
			var q := maxi(1, tx_need(state, eid) / 4)
			@warning_ignore("integer_division")
			t["prog"] = int(t["prog"]) / q * q
			t["lost"] = 1
			_stat(state, eid, "tx_lost", 1)
			added.append(state.add_chronicle("Le Héraut de %s est tombé : la Transmission s'interrompt et retombe à %d %%. Il faudra un nouveau Héraut pour reprendre." % [e.display_name(), tx_pct(state, eid)],
					Espionage.public_to(state, [eid])))
		return
	t["lost"] = 0
	if ContactVoices.tx_paused(state, eid):
		return
	var cost := tx_cost(state, eid)
	if int(e.resources.get("energy", 0)) < cost:
		return  # faute d'énergie, la Transmission marque le pas
	e.resources["energy"] = int(e.resources.get("energy", 0)) - cost
	@warning_ignore("integer_division")
	t["prog"] = int(t["prog"]) + month_days() * (100 + c_int("heraut", "rate_pct", 33) * tx_rate(state, eid)) / 100
	_expose(state, eid)
	if int(t["prog"]) >= tx_need(state, eid) and state.tick - int(t.get("start", 0)) >= c_int("heraut", "min_days", 720):
		complete(state, eid, added)


## Exposition (prop. 31) : le Héraut et la capitale révélés à tous.
static func _expose(state: GameState, eid: int) -> void:
	if not full(state):
		return
	var sids: Array = []
	var hs := heraut_system(state, eid)
	if hs >= 0:
		sids.append(hs)
	var cs := FactionTraits.capital_system(state, eid)
	if cs >= 0 and not sids.has(cs):
		sids.append(cs)
	for o in state.empires:
		if o.id != eid and not o.is_npc() and not o.eliminated:
			Intel.record_systems(state, o, sids)


## Systèmes révélés par une Transmission (la carte les marque).
static func exposed_systems(state: GameState) -> Array[int]:
	var out: Array[int] = []
	if not full(state):
		return out
	for k in sub(state, "tx"):
		var hs := heraut_system(state, int(k))
		if hs >= 0:
			out.append(hs)
	return out


# --- Issues (prop. 34) -------------------------------------------------------------------------

static func complete(state: GameState, eid: int, added: Array[Dictionary]) -> void:
	sub(state, "tx").erase(str(eid))
	var e := state.get_empire(eid)
	var nd := nature_def(nature(state))
	var oc := String(nd.get("outcome", "victory"))
	var win := oc == "victory" or oc == "archive" or oc == "loop" or (oc == "trap" and plans_state(state, eid) == "audit")
	state.relic_rev += 1
	if not win:
		sub(state, "failed")[str(eid)] = state.tick
		_stat(state, eid, "failed", 1)
		Announce.next(state, "contact_fail", {"actor": eid})
		added.append(state.add_chronicle(String(nd.get("fail", "La réponse arrive, et elle n'est pas bonne pour %s.")) % e.display_name()))
		ContactVoices.on_fail(state, eid, String(nd.get("crisis", "")), added)
		return
	sub(state, "done")[str(eid)] = state.tick
	for m in ContactRace.partners(state, eid):
		sub(state, "done")[str(m)] = state.tick
	_stat(state, eid, "won", 1)
	if opens(state):
		added.append(state.add_chronicle(String(nd.get("win", "La réponse arrive pour %s.")) % e.display_name() + " La partie continue : les Lointains font désormais partie du paysage."))
		return
	# La victoire est proclamée par VictorySystem (Victory.progress « contact »).


## Avancée vers la victoire « contact » (Victory.progress) : capture 0-9 %, jauge 10-59 %,
## Héraut 60 %, Transmission 75-99 %, 100 à la réponse.
@warning_ignore("integer_division")
static func victory(state: GameState, e: Empire, out: Dictionary) -> void:
	var eid := e.id
	var host := ContactRace.winner_host(state, eid)
	if done(state, eid):
		out["pct"] = 100
		out["won"] = not opens(state) and (host < 0 or host == eid)
		out["lines"].append("La réponse est arrivée")
		return
	if failed(state, eid):
		out["lines"].append("A répondu à %s" % nature_label(nature(state)).to_lower())
		return
	if not listens(state, eid):
		out["lines"].append("Technologie %s requise" % String(Research.tech(listen_tech()).get("label", listen_tech())))
		return
	if route_count(state, eid) <= 0:
		out["lines"].append("À l'écoute : aucune voie")
		return
	if not captured(state, eid):
		out["pct"] = 5
		out["lines"].append("Signal partiel (%d voie sur %d)" % [route_count(state, eid), c_int("capture", "need", 2)])
	if transmitting(state, eid):
		var t := tx(state, eid)
		out["pct"] = 75 + 24 * int(t.get("prog", 0)) / maxi(1, tx_need(state, eid))
		out["lines"].append("Transmission : %d %%, %s restants%s" % [tx_pct(state, eid), Victory._days_text(tx_left(state, eid)), " (Héraut perdu)" if int(t.get("lost", 0)) > 0 else ""])
		out["cond"] = true
		return
	if captured(state, eid):
		out["pct"] = 10 + 50 * gauge(state, eid) / maxi(1, gauge_max())
	out["lines"].append("Déchiffrement : %d %% (%d couche%s sur 4)" % [gauge_pct(state, eid), layers(state, eid), "s" if layers(state, eid) > 1 else ""])
	if has_heraut(state, eid):
		out["pct"] = maxi(int(out["pct"]), 60)
		out["lines"].append("Héraut bâti")


# --- Bâtiments, effets -------------------------------------------------------------------------

## Bâtiments du Contact (economy.check_special) : l'Oreille de la Bordure et le Héraut.
static func check_build(state: GameState, eid: int, c: Colony, building_id: String) -> String:
	if not applies(state, eid):
		return "le Contact n'est pas en jeu dans cette partie"
	var sid := state.galaxy.get_planet(c.planet_id).system_id
	if building_id == ear_building():
		for x in ears_of(state, eid):
			if int(x[1]) == sid:
				return "une Oreille écoute déjà dans ce système"
		if deaf(state, sid):
			return "une nébuleuse rend ce système sourd"
	elif building_id == heraut_building():
		if not c.is_colony():
			return "seulement sur une colonie"
		if not has_layer(state, eid, "plans"):
			return "il faut avoir déchiffré les Plans"
		if heraut_planet(state, eid) >= 0:
			return "votre empire a déjà un Héraut"
		for pid in state.sorted_colony_ids():
			var o: Colony = state.colonies[pid]
			if o.owner == eid and o.construction == building_id:
				return "un Héraut est déjà en chantier"
	return ""


## Effets lus par Research.effects : dons des Plans, lectures, brouillage, ouverture.
static func effects(state: GameState, eid: int) -> Dictionary:
	var out := {}
	if not applies(state, eid):
		return out
	for gid in sub(state, "gifts").get(str(eid), []):
		Research._merge(out, gift_def(String(gid)).get("fx", {}))
	var rd := cfg("readings")
	for how in ["menace", "outil"]:
		var n := readings(state, eid, how)
		for i in n:
			Research._merge(out, (rd.get(how, {}) as Dictionary).get("fx", {}))
	if opens(state) and done(state, eid):
		Research._merge(out, {"production_pct": {"knowledge": 25, "energy": 10}})
	Research._merge(out, ContactRace.effects(state, eid))
	return out


static func empire_stability_parts(state: GameState, eid: int) -> Array:
	var out := []
	if not applies(state, eid):
		return out
	if state.tick < int(sub(state, "porteuse_until").get("t", 0)):
		var v := int((cfg("porteuse").get("stab", {}) as Dictionary).get(credo(state, eid), 0))
		if v != 0:
			out.append(["Nous ne sommes pas seuls", v])
	if plans_state(state, eid) == "raw" and nature(state) == "semeurs":
		var s := c_int("plans", "raw_stab", -5) + t_int(state, eid, "semeurs_stab")
		if t_int(state, eid, "semeurs_double") > 0:
			s *= 2
		out.append(["Plans bruts : des machines qui ne dorment pas", s])
	out.append_array(ContactVoices.stability_parts(state, eid))
	return out


# --- Commandes ---------------------------------------------------------------------------------

static func check(state: GameState, eid: int, act: String, d: Dictionary) -> String:
	if not applies(state, eid):
		return "le Contact n'est pas en jeu"
	match act:
		"share":
			var v := int(d.get("v", -1))
			if v < 0 or v > c_int("gauge", "share_max", 30):
				return "part du Savoir hors bornes"
			return ""
		"intuition":
			return check_intuition(state, eid)
		"transmit":
			return check_transmit(state, eid)
		"rate":
			return check_rate(state, eid, int(d.get("v", -1)))
		"announce", "verify":
			if pending_alert(state, eid).is_empty() or int(pending_alert(state, eid).get("verify", 0)) > 0:
				return "aucune alerte en attente"
			return ""
		"plans_raw", "plans_audit":
			if not has_layer(state, eid, "plans") or plans_state(state, eid) != "":
				return "rien à décider sur les Plans"
			return ""
	var w := ContactRace.check(state, eid, act, d)
	if w != "?":
		return w
	return ContactVoices.check(state, eid, act, d)


static func apply(state: GameState, eid: int, act: String, d: Dictionary) -> Array[Dictionary]:
	var added: Array[Dictionary] = []
	match act:
		"share":
			sub(state, "share")[str(eid)] = int(d["v"])
		"intuition":
			sub(state, "abc")[str(eid)] = state.tick + c_int("abecedaire", "intuition_days", 720)
			added.append(state.add_chronicle("Les linguistes de %s s'enferment avec %s : il leur manque la clé de lecture, ils la chercheront dans la phase du Signal." % [state.get_empire(eid).short_name(), signal_name(state, eid)],
					Espionage.private_to(state, [eid])))
		"transmit":
			start_tx(state, eid, added)
		"rate":
			tx(state, eid)["rate"] = int(d["v"])
		"announce":
			announce_alert(state, eid, added)
		"verify":
			verify_alert(state, eid)
		"plans_raw":
			plans_raw(state, eid, added)
		"plans_audit":
			plans_audit(state, eid)
		_:
			if not ContactRace.apply(state, eid, act, d, added):
				ContactVoices.apply(state, eid, act, d, added)
	return added


## Choix d'une carte d'événement du Contact (Events.apply_fx, effet « ct »).
static func event_act(state: GameState, eid: int, act: String, added: Array[Dictionary]) -> void:
	if not applies(state, eid):
		return
	match act:
		"read_outil":
			read_layer(state, eid, "outil")
		"read_menace":
			read_layer(state, eid, "menace")
			ContactRace.on_menace(state, eid)
		"plans_raw":
			plans_raw(state, eid, added)
			read_layer(state, eid, "outil")
		"plans_audit":
			plans_audit(state, eid)
		"alert_announce":
			announce_alert(state, eid, added)
		"alert_verify":
			verify_alert(state, eid)


## Texte d'un effet « ct » (fenêtre d'événement).
static func event_line(act: String) -> String:
	var rd := cfg("readings")
	match act:
		"read_outil":
			return "Lecture outil : %s" % _fx_text((rd.get("outil", {}) as Dictionary).get("fx", {}))
		"read_menace":
			return "Lecture arme : %s, opinion %d chez ceux qui l'apprennent" % [_fx_text((rd.get("menace", {}) as Dictionary).get("fx", {})), int((rd.get("menace", {}) as Dictionary).get("opinion", -10))]
		"plans_raw":
			return "Un don des Lointains tout de suite (risqué face aux Semeurs)"
		"plans_audit":
			return "Audit d'un an : aucun risque"
		"alert_announce":
			return "+%d influence si c'est vrai ; %d et de la certitude perdue sinon" % [c_int("alerts", "announce_influence", 20), c_int("alerts", "false_influence", -30)]
		"alert_verify":
			return "Six mois de vérification, sans risque"
	return ""


static func _fx_text(fx: Dictionary) -> String:
	var parts: PackedStringArray = []
	for k in fx:
		if fx[k] is Dictionary:
			for r in fx[k]:
				parts.append("%+d %% %s" % [int(fx[k][r]), GameData.resource_label(String(r)) if String(r) != "all" else "de production"])
		else:
			parts.append("%+d %% %s" % [int(fx[k]), {"damage_pct": "de dégâts", "fleet_speed_pct": "de vitesse"}.get(k, k)])
	return ", ".join(parts)


## Bilan mensuel.
static func monthly(state: GameState, added: Array[Dictionary]) -> void:
	if not enabled(state):
		return
	_tick_ears(state, added)
	_tick_echoes(state, added)
	@warning_ignore("integer_division")
	var yearly := posmod(state.tick / month_days(), 12) == 0
	for e in state.empires:
		if not applies(state, e.id):
			continue
		if e.techs.has(grammar_tech()):
			add_route(state, e.id, "grammar", added)
		_maybe_false_alert(state, e.id, added)
		_tick_alert(state, e.id, added)
		if yearly:
			_yearly_net(state, e.id, added)
		if route_count(state, e.id) > 0 and not done(state, e.id) and not failed(state, e.id):
			var spent := knowledge_spent(state, e.id)
			var gain := monthly_gain(state, e.id)
			if spent > 0:
				e.resources["knowledge"] = maxi(0, int(e.resources.get("knowledge", 0)) - spent)
			add_gauge(state, e.id, gain, added)
		_tick_tx(state, e.id, added)
	ContactRace.monthly(state, added)
	ContactVoices.monthly(state, added)
	_refresh_fx(state)


static func _refresh_fx(state: GameState) -> void:
	var sig := sub(state, "fxsig")
	for e in state.empires:
		if not applies(state, e.id):
			continue
		var s := str(effects(state, e.id).hash())
		if String(sig.get(str(e.id), "")) != s:
			sig[str(e.id)] = s
			state.relic_rev += 1
