class_name Borders
extends RefCounted
## Frontières et droit de passage (étude du 2026-11-15, 32 propositions validées).
##
## Frontière souple : hors guerre, une flotte ARMÉE a besoin d'un droit de passage pour entrer dans
## un système d'un empire rencontré. Rien ne la bloque (sauf option Strictes), mais entrer sans droit
## est une intrusion : souvenir chez le propriétaire s'il voit la flotte, -1 par mois si elle stationne.
## Les vaisseaux sans armes ont le passage inoffensif (droit de la mer), sauf frontières closes.
##
## Droit de passage des flottes de guerre de v chez o :
## - guerre entre eux (on se bat), pas encore de contact, Sans-Bannière et faune : toujours ;
## - liens forts : alliés, équipe, suzerain et sujets (et sujets d'un même suzerain), même Koinon,
##   même coalition de l'Amphictyonie ;
## - traité de libre-passage (réciproque, dénoncé avec préavis) ou politique Ouverte de o envers v ;
## - clause « Passage imposé » d'un traité de paix, libre-passage imposé par l'Arbitre (lot 2) ;
## - laissez-passer d'une flotte (lot 2), corridor discret (lot 3).
## Politique de chaque empire envers chaque autre : Ouverte, Gardée (défaut) ou Close.
## Quand un droit prend fin, une flotte a grace_days jours pour sortir sans intrusion.
##
## state.borders = {"mode": "libres" | "souples" | "strictes", "pol": {"o>v": politique},
##   "legal": {"<flotte>": dernier jour où elle était en règle en territoire étranger},
##   "intr": {"<flotte>": {"o", "s" (système), "since" (arrivée), "t" (intrusion)}},
##   "first": {"o>v": 1} (première intrusion pardonnée, talent), "half": {"o>v": 0|1},
##   "summ": {"o>v": échéance de la sommation}, "ign": {"o>v": fin du motif et de la riposte},
##   "cool": {"o>v": prochaine sommation possible}, "fp": {"<flotte>": {"o", "end"}} (laissez-passer),
##   "toll": {"<o>": palier de péage}, "gates": {"o>v": 1} (flottes à nos portes, recalculé chaque mois),
##   "imp": {"a-b": fin du libre-passage imposé par l'Arbitre}, "corr": {"o>v": fin du corridor discret}}
## Les clés de paires sont "o>v" (politique de o envers v, ou intrusion de v chez o).
## Tout est déterministe : parcours dans l'ordre des identifiants, aucun aléatoire.

const OPEN := "open"
const GUARDED := "guarded"
const CLOSED := "closed"
const POLICIES: Array[String] = ["open", "guarded", "closed"]
const MODES: Array[String] = ["libres", "souples", "strictes"]
## Drapeaux des variantes d'itinéraire (voir Fleets._dijkstra).
const PATH_LAIRS := 1
const PATH_ARMED := 2
const PATH_CIVIL := 4
## Éclaireurs et civils d'un peuple contrebandier : passent les portails d'autrui (voir Portals).
const PATH_SMUGGLE := 8

static var _talent_cache := {}


static func data() -> Dictionary:
	return GameData.borders()


static func _cfg(k: String) -> Dictionary:
	return data().get(k, {})


static func _blank() -> Dictionary:
	return {"mode": "libres", "pol": {}, "legal": {}, "intr": {}, "first": {}, "half": {},
			"summ": {}, "ign": {}, "cool": {}, "fp": {}, "toll": {}, "gates": {}, "imp": {}, "corr": {}}


static func setup(state: GameState, mode: String) -> void:
	state.borders = _blank()
	state.borders["mode"] = mode if MODES.has(mode) else "libres"


static func to_dict(state: GameState) -> Dictionary:
	return state.borders.duplicate(true)


static func from_dict(state: GameState, d: Dictionary) -> void:
	state.borders = _blank()
	for k in d:
		state.borders[k] = Vassals._ints(d[k])
	# Les clés de flottes et de paires restent des chaînes (Vassals._ints ne touche qu'aux valeurs).
	if not MODES.has(String(state.borders.get("mode", ""))):
		state.borders["mode"] = "libres"


static func worth_saving(state: GameState) -> bool:
	return active(state)


static func mode(state: GameState) -> String:
	return String(state.borders.get("mode", "libres"))


static func active(state: GameState) -> bool:
	return mode(state) != "libres"


static func strict(state: GameState) -> bool:
	return mode(state) == "strictes"


static func _b(state: GameState) -> Dictionary:
	if not state.borders.has("pol"):
		var m := mode(state)
		state.borders = _blank()
		state.borders["mode"] = m
	elif not state.borders.has("corr"):
		var blank := _blank()
		for k in blank:
			if not state.borders.has(k):
				state.borders[k] = blank[k]
	return state.borders


static func _pk(o: int, v: int) -> String:
	return "%d>%d" % [o, v]


static func _name(state: GameState, eid: int) -> String:
	var e := state.get_empire(eid)
	return e.display_name() if e != null else "?"


static func _sys(state: GameState, sid: int) -> String:
	return state.galaxy.systems[sid].system_name


static func mode_defs() -> Array:
	return data()["modes"]


static func policy_label(p: String) -> String:
	for d: Dictionary in data()["policies"]:
		if String(d["id"]) == p:
			return String(d["label"])
	return p


static func policy_text(p: String) -> String:
	for d: Dictionary in data()["policies"]:
		if String(d["id"]) == p:
			return String(d["text"])
	return ""


# --- Talents de peuple (prop. 26) ------------------------------------------------------------------

## Talent de frontière d'un empire par ses couches d'espèce ({} sinon), fusion des couches.
static func talent(state: GameState, eid: int) -> Dictionary:
	var e := state.get_empire(eid)
	if e == null or e.is_npc():
		return {}
	var ck := "%s:%s" % [e.faction_id, str(e.faction().get("species", {}))]
	if _talent_cache.has(ck):
		return _talent_cache[ck]
	var out := {}
	var sp := FactionTraits.species(e.faction())
	var table: Dictionary = _cfg("talents")
	for layer in ["traits", "archetype", "gouvernement", "credo"]:
		var t: Dictionary = table.get(layer, {})
		var values: Array = []
		if layer == "traits":
			values = sp.get("traits", [])
		else:
			values = [String(sp.get(layer, ""))]
		for v in values:
			if t.has(String(v)):
				var d: Dictionary = t[String(v)]
				if not FactionTraits.species_matches(e.faction(), d.get("requires", {})):
					continue
				out["labels"] = (out.get("labels", []) as Array) + [[String(d["label"]), String(d["text"])]]
				for k in d:
					if k != "label" and k != "text" and k != "requires":
						out[k] = d[k]
	_talent_cache[ck] = out
	return out


static func talent_labels(state: GameState, eid: int) -> Array:
	var seen := {}
	var out: Array = []
	for x in talent(state, eid).get("labels", []):
		if not seen.has(String(x[0])):
			seen[String(x[0])] = true
			out.append(x)
	return out


# --- Politiques ------------------------------------------------------------------------------------

## Politique par défaut d'un empire envers ses contacts (talent, puis loi Doctrine des frontières).
static func default_policy(state: GameState, o: int) -> String:
	if state.politics_on:
		var doc: Dictionary = data().get("doctrine", {})
		for law in doc:
			if Laws.is_enacted(state, o, String(law)):
				return String(doc[law])
	var t := String(talent(state, o).get("default", ""))
	return t if POLICIES.has(t) else GUARDED


## Loi Doctrine des frontières (prop. 28) : la politique par défaut a changé ; ceux qui la subissent
## (sans politique propre) réagissent comme à un changement de politique.
static func on_default_change(state: GameState, o: int, before: String) -> void:
	var after := default_policy(state, o)
	if after == before:
		return
	dirty(state)
	var eo := state.get_empire(o)
	var pol: Dictionary = _b(state)["pol"]
	for v in eo.contacts:
		if pol.has(_pk(o, v)) or GameState.is_npc(v):
			continue
		if after == CLOSED and not bool(talent(state, o).get("close_free", false)) and not sanctuary_free(state, o, v):
			Diplomacy.remember(state, v, o, "borders_closed")
		elif after == OPEN:
			Diplomacy.remember(state, v, o, "borders_opened")
	state.add_chronicle("%s change de doctrine : ses frontières sont désormais %s par défaut." % [_name(state, o), {"open": "ouvertes", "guarded": "gardées", "closed": "closes"}.get(after, after)],
			Espionage.public_to(state, [o]))


## Politique de o envers v.
static func policy(state: GameState, o: int, v: int) -> String:
	if GameState.is_minor(o):
		return CLOSED if MinorsLife.hostile_to(state, o, v) else OPEN  # enclave d'un peuple mineur
	var p := String((state.borders.get("pol", {}) as Dictionary).get(_pk(o, v), ""))
	return p if p != "" else default_policy(state, o)


static func check_policy(state: GameState, o: int, v: int, p: String) -> String:
	if not active(state):
		return "les frontières sont libres dans cette partie"
	var eo := state.get_empire(o)
	var ev := state.get_empire(v)
	if eo == null or ev == null or o == v or ev.is_npc():
		return "empire inconnu"
	if not eo.contacts.has(v):
		return "vous n'avez jamais rencontré cet empire"
	if not POLICIES.has(p):
		return "politique inconnue"
	if policy(state, o, v) == p:
		return "c'est déjà votre politique envers lui"
	if p == CLOSED and amph_free_navigation(state, o, v):
		return "le Nomos impose la libre navigation entre amphictyons"
	return ""


## Les droits ont changé : les itinéraires qui contournent l'espace interdit sont à recalculer.
static func dirty(state: GameState) -> void:
	for e in state.empires:
		e.border_cache.clear()


static func set_policy(state: GameState, o: int, v: int, p: String) -> void:
	dirty(state)
	var b := _b(state)
	var before := policy(state, o, v)
	b["pol"][_pk(o, v)] = p
	if p == CLOSED and before != CLOSED:
		if not bool(talent(state, o).get("close_free", false)) and not sanctuary_free(state, o, v) and not _amph_flag(state, o, v, "sov_close_free"):
			Diplomacy.remember(state, v, o, "borders_closed")
		state.add_chronicle("%s ferme ses frontières à %s. Même les éclaireurs devront rester dehors." % [_name(state, o), _name(state, v)],
				Espionage.public_to(state, [o, v]))
	elif p == OPEN and before != OPEN:
		Diplomacy.remember(state, v, o, "borders_opened")
		state.add_chronicle("%s ouvre ses frontières aux flottes de %s : libre-passage accordé." % [_name(state, o), _name(state, v)],
				Espionage.public_to(state, [o, v]))
	elif before == OPEN:
		state.add_chronicle("%s retire le libre-passage accordé à %s. Ses flottes ont %d jours pour sortir." % [_name(state, o), _name(state, v), int(data()["grace_days"])],
				Espionage.private_to(state, [o, v]))


# --- Droit de passage ------------------------------------------------------------------------------

## Liens forts : alliés, équipe, suzerain et sujets (et sujets d'un même suzerain), même Koinon,
## même coalition de l'Amphictyonie.
static func strong_link(state: GameState, a: int, b: int) -> bool:
	if Diplomacy.allied(state, a, b) or Diplomacy.team_of(state, a, b) > 0:
		return true
	var la := Vassals.lord_of(state, a)
	var lb := Vassals.lord_of(state, b)
	if la == b or lb == a or (la >= 0 and la == lb):
		return true
	if state.koinon_on and Koinon.same_league(state, a, b):
		return true
	if state.amph_on and AmphInst.in_coalition(state, a) and AmphInst.in_coalition(state, b):
		return true
	return false


## Les deux sont-ils amphictyons sous une loi de navigation (flag d'un niveau de la famille Navigation) ?
static func _amph_flag(state: GameState, a: int, b: int, flag: String) -> bool:
	return state.amph_on and Amphictyony.is_member(state, a) and Amphictyony.is_member(state, b) \
			and Amphictyony._level_flag(state, flag)


static func has_treaty(state: GameState, a: int, b: int) -> bool:
	return int(Diplomacy.rel(state, a, b).get("pass", 0)) != 0


## Préavis de dénonciation du libre-passage en cours (jour de fin, 0 sinon).
static func treaty_end(state: GameState, a: int, b: int) -> int:
	return int(Diplomacy.rel(state, a, b).get("pass_end", 0))


static func has_prosp(state: GameState, a: int, b: int) -> bool:
	return int(Diplomacy.rel(state, a, b).get("prosp", 0)) != 0


## Pas de règle de frontière entre ces deux-là (option, PNJ, même empire, pas de contact, guerre).
static func _exempt(state: GameState, o: int, v: int) -> bool:
	if not active(state) or o < 0 or v < 0 or o == v or GameState.is_npc(o) or GameState.is_npc(v):
		return true
	var eo := state.get_empire(o)
	if eo == null or eo.eliminated or not eo.contacts.has(v):
		return true
	return Combat.at_war(state, o, v)


## Les flottes de guerre de v ont-elles le droit de traverser les systèmes de o (au niveau des empires) ?
static func grants(state: GameState, o: int, v: int) -> bool:
	if _exempt(state, o, v):
		return true
	if strong_link(state, o, v) or has_treaty(state, o, v) or policy(state, o, v) == OPEN:
		return true
	if Crisis.front_pair(state, o, v):
		return true  # Front commun contre la crise : passage libre
	return forced(state, o, v)


## Passage imposé : clause d'un traité de paix gagnée par v, ou libre-passage imposé par l'Arbitre.
static func forced(state: GameState, o: int, v: int) -> bool:
	if state.wars_on and not WarPeace.clause_active(state, v, o, "pass").is_empty():
		return true
	if int((_b(state)["imp"] as Dictionary).get(Diplomacy.key(o, v), 0)) > state.tick:
		return true
	return _amph_flag(state, o, v, "nav_open")


## Les vaisseaux sans armes de v passent-ils chez o (passage inoffensif) ?
static func civil_ok(state: GameState, o: int, v: int) -> bool:
	if grants(state, o, v):
		return true
	# Contrebandiers (talent) : leurs vaisseaux sans armes passent même les frontières closes.
	return policy(state, o, v) != CLOSED or bool(talent(state, v).get("civil_always", false))


## Une flotte est-elle traitée comme un passage inoffensif chez o (sans armes, ou de même foi d'État) ?
static func harmless(state: GameState, f: Fleet, o: int) -> bool:
	return not Combat.is_armed(f) or same_faith(state, o, f.owner)


## Religion (prop. 25) : même foi d'État.
static func same_faith(state: GameState, a: int, b: int) -> bool:
	if not state.faith_on:
		return false
	var fa := Faiths.state_faith(state, a)
	return fa != "" and fa == Faiths.state_faith(state, b)


## Cette flotte a-t-elle le droit d'être dans un système de o ?
static func fleet_right(state: GameState, f: Fleet, o: int) -> bool:
	if f.owner == o or _exempt(state, o, f.owner):
		return true
	if has_pass(state, f.id, o) or corridor(state, o, f.owner):
		return true
	if PeopleHulls.concord_right(state, f, o):
		return true  # Pavillon de concorde (coques de peuple)
	if Research.fx_int(state, f.owner, "forged_papers") > 0 and not Combat.at_war(state, f.owner, o):
		return true  # Faux papiers (Brisecomète, lot 4 de l'arbre) : hors guerre, pas besoin de droit
	if harmless(state, f, o):
		return civil_ok(state, o, f.owner)
	return grants(state, o, f.owner)


## Le système est-il interdit à cette flotte (propriétaire étranger, sans droit) ?
static func forbidden(state: GameState, f: Fleet, sid: int) -> bool:
	var o := state.system_owner(sid)
	return o >= 0 and not fleet_right(state, f, o)


## Drapeaux d'itinéraire d'une flotte (contournement des repaires, de l'espace interdit).
static func path_flags(state: GameState, f: Fleet) -> int:
	var flags := PATH_LAIRS if Fleets.avoids_lairs(state, f) else 0
	if active(state) and not GameState.is_npc(f.owner):
		flags |= PATH_CIVIL if not Combat.is_armed(f) else PATH_ARMED
	if not state.portals.is_empty() and not Combat.is_armed(f) and Portals.smuggler(state, f.owner):
		flags |= PATH_SMUGGLE
	return flags


## Pour l'itinéraire : les systèmes de o sont-ils interdits aux flottes (armées ou non) de v ?
static func blocks_path(state: GameState, v: int, o: int, armed: bool) -> bool:
	if o < 0:
		return false
	return not (grants(state, o, v) if armed else civil_ok(state, o, v))


## Itinéraire : avertissement si le trajet traverse l'espace d'un empire sans droit ("" sinon).
static func route_warning(state: GameState, f: Fleet, path: Array) -> String:
	if not active(state):
		return ""
	var names := PackedStringArray()
	var who := {}
	for sid in path:
		var o := state.system_owner(int(sid))
		if o >= 0 and not fleet_right(state, f, o) and not who.has(o):
			who[o] = true
			names.append(state.get_empire(o).short_name())
	if names.is_empty():
		return ""
	return "Traverse l'espace de %s sans droit de passage : intrusion." % ", ".join(names)


## Option Strictes : la flotte peut-elle entrer dans ce système ?
static func can_enter(state: GameState, f: Fleet, sid: int) -> bool:
	if not strict(state):
		return true
	return not forbidden(state, f, sid)


# --- Chaque jour : intrusions ------------------------------------------------------------------------

## Appelé chaque jour par FleetSystem, après les déplacements et l'exploration.
static func daily(state: GameState) -> void:
	if not active(state):
		return
	var b := _b(state)
	var legal: Dictionary = b["legal"]
	var intr: Dictionary = b["intr"]
	var grace := int(data()["grace_days"])
	var keep := {}
	for fid in state.sorted_fleet_ids():
		var f: Fleet = state.fleets[fid]
		if GameState.is_npc(f.owner):
			continue
		var k := str(fid)
		var o := state.system_owner(f.system_id)
		if o < 0 or o == f.owner:
			legal.erase(k)
			intr.erase(k)
			continue
		keep[k] = true
		if fleet_right(state, f, o):
			legal[k] = state.tick
			intr.erase(k)
			continue
		# Délai de sortie : la flotte était en règle il y a moins de grace_days jours.
		if legal.has(k) and state.tick - int(legal[k]) <= grace:
			continue
		if strict(state):
			_expel(state, f, o)
			continue
		var rec: Dictionary = intr.get(k, {})
		if rec.is_empty() or int(rec["o"]) != o:
			rec = {"o": o, "s": f.system_id, "since": state.tick, "t": state.tick, "seen": 0}
			intr[k] = rec
		elif int(rec["s"]) != f.system_id:
			rec["s"] = f.system_id
			rec["since"] = state.tick
		if int(rec["seen"]) == 0 and _sees(state, o, f):
			rec["seen"] = 1
			_record(state, f, o)
	_summons_daily(state)
	_passes_daily(state)
	# Les flottes disparues ne laissent rien.
	for k in legal.keys():
		if not keep.has(k):
			legal.erase(k)
	for k in intr.keys():
		if not keep.has(k):
			intr.erase(k)


static func _sees(state: GameState, o: int, f: Fleet) -> bool:
	if o >= state.seen_cache.size():
		return false
	# Terrain : dans une nébuleuse, seule une présence sur place repère l'intruse.
	if Terrain.stealthy(state, f.system_id) and not Terrain.present(state, o, f.system_id):
		return false
	return Fleets.fleet_visible(state, o, f, state.seen_cache[o])


## Intrusion constatée : souvenir (double pendant une trêve), chronique.
static func _record(state: GameState, f: Fleet, o: int) -> void:
	var b := _b(state)
	var v := f.owner
	var pk := _pk(o, v)
	var t := talent(state, v)
	if bool(t.get("first_free", false)) and not (b["first"] as Dictionary).has(pk):
		b["first"][pk] = 1
		state.add_chronicle("Le %s de %s s'égare à %s, chez %s. On le prend pour un équipage perdu : pour cette fois." % [
				f.fleet_name, _name(state, v), _sys(state, f.system_id), _name(state, o)], Espionage.private_to(state, [o, v], f.system_id))
		return
	# Amiral discret (héros, prop. 27) : l'intrusion est notée, sans souvenir.
	if Heroes.trait_fx(Heroes.at_post(state, "fleet", f.id, v), "discreet") > 0:
		state.add_chronicle("Une flotte de %s croise à %s, chez %s ; son amiral sait se faire oublier, et les sentinelles hésitent à faire un rapport." % [
				_name(state, v), _sys(state, f.system_id), _name(state, o)], Espionage.private_to(state, [o, v], f.system_id))
		return
	var n := 1
	if Diplomacy.in_truce(state, o, v):
		n = int(data().get("truce_mult", 2))
	if _amph_flag(state, o, v, "sov_double"):
		n *= 2
	if int(t.get("intr_pct", 0)) <= -50:
		var h := int((b["half"] as Dictionary).get(pk, 0))
		b["half"][pk] = 1 - h
		if h == 1:
			n -= 1
	for i in n:
		Diplomacy.remember(state, o, v, "intrusion")
	state.add_chronicle("Intrusion : le %s de %s entre à %s, chez %s, sans droit de passage. Les sentinelles notent l'heure, et le nom du vaisseau." % [
			f.fleet_name, _name(state, v), _sys(state, f.system_id), _name(state, o)], Espionage.private_to(state, [o, v], f.system_id))


## Option Strictes : une flotte sans droit est repoussée vers le système permis le plus proche.
static func _expel(state: GameState, f: Fleet, o: int) -> void:
	var g := state.galaxy
	var seen := {f.system_id: true}
	var queue: Array[int] = [f.system_id]
	var i := 0
	var dest := -1
	while i < queue.size() and dest < 0:
		var cur := queue[i]
		i += 1
		var nbs: Array = g.systems[cur].neighbors.duplicate()
		nbs.sort()
		for n in nbs:
			if seen.has(n):
				continue
			seen[n] = true
			if not forbidden(state, f, n):
				dest = n
				break
			queue.append(n)
	if dest < 0:
		return
	var from := f.system_id
	f.system_id = dest
	f.path.clear()
	f.progress = 0
	f.standing_order = "" if f.standing_order == "patrol" else f.standing_order
	f.patrol.clear()
	state.add_chronicle("Le %s de %s est reconduit hors de %s par les patrouilles de %s, jusqu'à %s." % [
			f.fleet_name, _name(state, f.owner), _sys(state, from), _name(state, o), _sys(state, dest)], Espionage.private_to(state, [o, f.owner], dest))


## Chaque mois : les flottes qui stationnent sans droit depuis stay_days jours (et que le propriétaire
## voit) ajoutent leur souvenir.
static func monthly(state: GameState) -> void:
	if not active(state):
		return
	var b := _b(state)
	_gates(state)
	var stay := int(data()["stay_days"])
	var keys: Array = b["intr"].keys()
	keys.sort_custom(func(x: String, y: String) -> bool: return int(x) < int(y))
	for k in keys:
		var rec: Dictionary = b["intr"][k]
		var f: Fleet = state.fleets.get(int(k))
		if f == null or f.is_moving() or int(rec["seen"]) == 0:
			continue
		if state.tick - int(rec["since"]) >= stay:
			Diplomacy.remember(state, int(rec["o"]), f.owner, "intr_stay")


# --- Lectures pour l'interface et l'IA --------------------------------------------------------------

## Flottes de v en intrusion chez o (identifiants triés).
static func intruders(state: GameState, o: int, v: int) -> Array[int]:
	var out: Array[int] = []
	for k in (state.borders.get("intr", {}) as Dictionary):
		var rec: Dictionary = state.borders["intr"][k]
		var f: Fleet = state.fleets.get(int(k))
		if f != null and f.owner == v and int(rec["o"]) == o:
			out.append(int(k))
	out.sort()
	return out


## Toutes les intrusions chez o : [[flotte, intrus]] triées par flotte.
static func intrusions_in(state: GameState, o: int) -> Array:
	var out: Array = []
	var keys: Array = (state.borders.get("intr", {}) as Dictionary).keys()
	keys.sort_custom(func(x: String, y: String) -> bool: return int(x) < int(y))
	for k in keys:
		var rec: Dictionary = state.borders["intr"][k]
		var f: Fleet = state.fleets.get(int(k))
		if f != null and int(rec["o"]) == o and int(rec["seen"]) == 1:
			out.append([int(k), f.owner])
	return out


## Ce que v peut faire chez o, en une ligne.
static func access_text(state: GameState, o: int, v: int) -> String:
	if not active(state):
		return "Frontières libres."
	if Combat.at_war(state, o, v):
		return "En guerre : aucune frontière ne tient."
	if strong_link(state, o, v):
		return "Lien fort (alliance, sujet, Koinon ou coalition) : libre-passage."
	if has_treaty(state, o, v):
		var end := treaty_end(state, o, v)
		return "Traité de libre-passage%s." % ((" (dénoncé : encore %d j)" % (end - state.tick)) if end > 0 else "")
	if forced(state, o, v):
		return "Passage imposé."
	match policy(state, o, v):
		OPEN:
			return "Ouverte : libre-passage accordé."
		CLOSED:
			return "Close : même les vaisseaux sans armes sont en intrusion."
	return "Gardée : vaisseaux sans armes seulement."


# --- Traités (libre-passage, prospection) -----------------------------------------------------------

static func check_treaty_terms(state: GameState, a: int, b: int, treaty: String) -> String:
	if not active(state):
		return "les frontières sont libres dans cette partie"
	if Combat.at_war(state, a, b):
		return "pas de traité de frontière avec un ennemi"
	match treaty:
		"passage":
			if has_treaty(state, a, b) and treaty_end(state, a, b) == 0:
				return "un traité de libre-passage est déjà en vigueur"
			if strong_link(state, a, b):
				return "vos liens ouvrent déjà vos frontières"
		"prosp":
			if state.curios.is_empty():
				return "aucune curiosité dans cette partie"
			if has_prosp(state, a, b):
				return "un traité de prospection est déjà en vigueur"
	return ""


static func sign(state: GameState, a: int, b: int, treaty: String) -> void:
	dirty(state)
	var r := Diplomacy._rel_w(state, a, b)
	match treaty:
		"passage":
			r["pass"] = 1
			r.erase("pass_end")
			state.add_chronicle("%s et %s signent un traité de libre-passage. Les douaniers lèvent la barrière, et les sourcils." % [_name(state, a), _name(state, b)],
					Espionage.public_to(state, [a, b]))
		"prosp":
			r["prosp"] = 1
			state.add_chronicle("%s et %s s'accordent un droit de prospection : leurs éclaireurs pourront fouiller les curiosités l'un de l'autre." % [_name(state, a), _name(state, b)],
					Espionage.public_to(state, [a, b]))


static func check_cancel(state: GameState, a: int, b: int, treaty: String) -> String:
	match treaty:
		"passage":
			if not has_treaty(state, a, b):
				return "aucun traité de libre-passage avec cet empire"
			if treaty_end(state, a, b) > 0:
				return "déjà dénoncé (encore %d j)" % (treaty_end(state, a, b) - state.tick)
		"prosp":
			if not has_prosp(state, a, b):
				return "aucun traité de prospection avec cet empire"
	return ""


static func cancel(state: GameState, a: int, b: int, treaty: String) -> void:
	var r := Diplomacy._rel_w(state, a, b)
	match treaty:
		"passage":
			r["pass_end"] = state.tick + int(_cfg("treaty").get("notice_days", 90))
			state.add_chronicle("%s dénonce son traité de libre-passage avec %s : il prendra fin dans %d jours." % [_name(state, a), _name(state, b), int(_cfg("treaty").get("notice_days", 90))],
					Espionage.public_to(state, [a, b]))
		"prosp":
			r.erase("prosp")
			state.add_chronicle("%s met fin au droit de prospection de %s." % [_name(state, a), _name(state, b)], Espionage.private_to(state, [a, b]))


## Chaque jour : préavis de dénonciation échus ; la guerre met fin aux traités de frontière.
static func treaties_daily(state: GameState) -> void:
	var keys := state.relations.keys()
	keys.sort()
	for k in keys:
		var r: Dictionary = state.relations[k]
		var end := int(r.get("pass_end", 0))
		if end > 0 and end <= state.tick:
			dirty(state)
			r.erase("pass")
			r.erase("pass_end")


## La guerre déchire les traités de frontière.
static func on_war(state: GameState, a: int, b: int) -> void:
	dirty(state)
	var r: Dictionary = state.relations.get(Diplomacy.key(a, b), {})
	r.erase("pass")
	r.erase("pass_end")
	r.erase("prosp")


## Un éclaireur de eid peut-il sonder une curiosité dans ce système ? (traité de prospection)
static func may_probe(state: GameState, eid: int, sid: int) -> bool:
	var o := state.system_owner(sid)
	if o < 0 or _exempt(state, o, eid):
		return true
	return strong_link(state, o, eid) or has_prosp(state, o, eid)


# --- Ordres ------------------------------------------------------------------------------------------

## Ordres de frontière : "policy" (x = empire, s = politique).
static func check_act(state: GameState, eid: int, act: String, x: int, y: int, s: String) -> String:
	if not active(state):
		return "les frontières sont libres dans cette partie"
	var e := state.get_empire(eid)
	if e == null or e.eliminated:
		return "empire inconnu"
	match act:
		"policy":
			return check_policy(state, eid, x, s)
		"summons":
			return check_summons(state, eid, x)
		"pass":
			return check_pass(state, eid, x, y)
		"toll":
			return check_toll(state, eid, x)
		"arbiter":
			return check_arbiter(state, eid, x, y)
	return "ordre de frontière inconnu"


static func act(state: GameState, eid: int, act_id: String, x: int, y: int, s: String) -> void:
	match act_id:
		"policy":
			set_policy(state, eid, x, s)
		"summons":
			summon(state, eid, x)
		"pass":
			request_pass(state, eid, x, y)
		"toll":
			set_toll(state, eid, x)
		"arbiter":
			arbiter_impose(state, eid, x, y)


# --- Sommation, motif, riposte (lot 2) ---------------------------------------------------------------

static func summons_days(state: GameState, o: int, v: int) -> int:
	if _amph_flag(state, o, v, "sov_fast"):
		return int(_cfg("summons").get("sov_days", 15))
	return int(_cfg("summons").get("days", 30))


## Échéance de la sommation de o à v (0 sans sommation en cours).
static func summons_end(state: GameState, o: int, v: int) -> int:
	return int((state.borders.get("summ", {}) as Dictionary).get(_pk(o, v), 0))


## Flottes de v en intrusion chez o que o a vues.
static func seen_intruders(state: GameState, o: int, v: int) -> Array[int]:
	var out: Array[int] = []
	for it in intrusions_in(state, o):
		if int(it[1]) == v:
			out.append(int(it[0]))
	return out


static func check_summons(state: GameState, o: int, v: int) -> String:
	var ev := state.get_empire(v)
	if ev == null or ev.eliminated or o == v:
		return "empire inconnu"
	if _exempt(state, o, v):
		return "pas de frontière entre vous"
	if summons_end(state, o, v) > 0:
		return "sommation déjà en cours (encore %d j)" % (summons_end(state, o, v) - state.tick)
	var cool := int((_b(state)["cool"] as Dictionary).get(_pk(o, v), 0))
	if cool > state.tick:
		return "trop tôt pour une nouvelle sommation (%d j)" % (cool - state.tick)
	if seen_intruders(state, o, v).is_empty():
		return "aucune de ses flottes n'est en intrusion chez vous"
	return ""


static func summon(state: GameState, o: int, v: int) -> void:
	var d := summons_days(state, o, v)
	_b(state)["summ"][_pk(o, v)] = state.tick + d
	state.add_chronicle("%s somme %s de retirer ses flottes de son espace sous %d jours. Le ton est courtois ; le délai, non." % [_name(state, o), _name(state, v), d],
			Espionage.private_to(state, [o, v]))


## Chaque jour : sommations obéies (plus aucun intrus) ou ignorées (échéance passée).
static func _summons_daily(state: GameState) -> void:
	var b := _b(state)
	var summ: Dictionary = b["summ"]
	if summ.is_empty():
		return
	var keys: Array = summ.keys()
	keys.sort()
	var cd := int(_cfg("summons").get("cooldown_days", 60))
	for k in keys:
		var pair := String(k).split(">")
		var o := int(pair[0])
		var v := int(pair[1])
		if _exempt(state, o, v):
			summ.erase(k)
			continue
		if intruders(state, o, v).is_empty():
			summ.erase(k)
			b["cool"][k] = state.tick + cd
			state.add_chronicle("Les flottes de %s quittent l'espace de %s, comme sommé. L'incident est clos, à défaut d'être oublié." % [_name(state, v), _name(state, o)],
					Espionage.private_to(state, [o, v]))
		elif state.tick >= int(summ[k]):
			summ.erase(k)
			b["cool"][k] = state.tick + cd
			b["ign"][k] = state.tick + int(_cfg("summons").get("cb_days", 1800))
			Diplomacy.remember(state, o, v, "summons_ignored")
			state.add_chronicle("%s ignore la sommation de %s : ses flottes restent. %s tient désormais un motif de guerre, « Violation de frontière », et ses patrouilles ont ordre de tirer." % [
					_name(state, v), _name(state, o), _name(state, o)], Espionage.public_to(state, [o, v]))


## Motif de guerre « Violation de frontière » de a contre b (sommation ignorée, pour cinq ans).
static func has_cb(state: GameState, a: int, b: int) -> bool:
	return active(state) and int((state.borders.get("ign", {}) as Dictionary).get(_pk(a, b), 0)) > state.tick


## Riposte (prop. 7) : en guerre froide, après une sommation ignorée, les flottes armées de o
## attaquent celles de v en intrusion chez lui, sans déclaration de guerre. Jamais en paix.
static func riposte_on(state: GameState, o: int, f: Fleet) -> bool:
	if not has_cb(state, o, f.owner) or Diplomacy.pact(state, o, f.owner) != Diplomacy.COLD:
		return false
	var rec: Dictionary = (state.borders.get("intr", {}) as Dictionary).get(str(f.id), {})
	return not rec.is_empty() and int(rec["o"]) == o and state.system_owner(f.system_id) == o


## Combat.hostile_fleets : deux flottes hors guerre qui se battent par riposte.
static func riposte(state: GameState, a: Fleet, b: Fleet) -> bool:
	if not active(state) or (state.borders.get("ign", {}) as Dictionary).is_empty() or a.owner == b.owner:
		return false
	if GameState.is_npc(a.owner) or GameState.is_npc(b.owner):
		return false
	return riposte_on(state, a.owner, b) or riposte_on(state, b.owner, a)


## Système permis le plus proche pour cette flotte (son système s'il l'est, -1 si aucun).
static func nearest_permitted(state: GameState, f: Fleet) -> int:
	if not forbidden(state, f, f.system_id):
		return f.system_id
	var g := state.galaxy
	var seen := {f.system_id: true}
	var queue: Array[int] = [f.system_id]
	var i := 0
	while i < queue.size():
		var cur := queue[i]
		i += 1
		var nbs: Array = g.systems[cur].neighbors.duplicate()
		nbs.sort()
		for n in nbs:
			if seen.has(n):
				continue
			seen[n] = true
			if not forbidden(state, f, n):
				return n
			queue.append(n)
	return -1


# --- Laissez-passer (lot 2) ----------------------------------------------------------------------------

static func has_pass(state: GameState, fid: int, o: int) -> bool:
	var rec: Dictionary = (state.borders.get("fp", {}) as Dictionary).get(str(fid), {})
	return not rec.is_empty() and int(rec["o"]) == o and int(rec["end"]) > state.tick


static func pass_cost(state: GameState, v: int) -> Dictionary:
	if bool(talent(state, v).get("pass_free", false)):
		return {}
	return _cfg("pass").get("cost", {})


static func _pending_pass(state: GameState, fid: int) -> bool:
	for p in state.proposals:
		if String(p["treaty"]) == "bpass" and int(p.get("fleet", -1)) == fid:
			return true
	return false


static func check_pass(state: GameState, v: int, fid: int, o: int) -> String:
	var f: Fleet = state.fleets.get(fid)
	if f == null or f.owner != v:
		return "cette flotte ne vous appartient pas"
	var eo := state.get_empire(o)
	if eo == null or eo.eliminated or eo.is_npc() or o == v:
		return "empire inconnu"
	if _exempt(state, o, v):
		return "pas de frontière entre vous"
	if not Combat.is_armed(f) and civil_ok(state, o, v):
		return "une flotte sans armes passe déjà"
	if fleet_right(state, f, o):
		return "cette flotte a déjà le droit de passer"
	if _pending_pass(state, fid):
		return "demande déjà en cours"
	if not Economy.can_afford(state.get_empire(v), pass_cost(state, v)):
		return "il faut %d influence" % int(pass_cost(state, v).get("influence", 0))
	return ""


static func request_pass(state: GameState, v: int, fid: int, o: int) -> void:
	var f: Fleet = state.fleets[fid]
	Economy.pay(state.get_empire(v), pass_cost(state, v))
	var eo := state.get_empire(o)
	if eo.is_ai():
		if AiBorders.pass_score(state, o, v, f) >= 0:
			grant_pass(state, o, v, fid)
		else:
			state.add_chronicle("%s refuse un laissez-passer au %s de %s. La barrière reste baissée." % [_name(state, o), f.fleet_name, _name(state, v)],
					Espionage.private_to(state, [o, v]))
		return
	state.proposals.append({"id": state.next_proposal_id, "from": v, "to": o, "treaty": "bpass", "tick": state.tick, "fleet": fid})
	state.next_proposal_id += 1
	state.add_chronicle("%s demande à %s un laissez-passer pour son %s." % [_name(state, v), _name(state, o), f.fleet_name],
			Espionage.private_to(state, [o, v]))


static func grant_pass(state: GameState, o: int, v: int, fid: int) -> void:
	var f: Fleet = state.fleets.get(fid)
	if f == null:
		return
	dirty(state)
	var days := int(_cfg("pass").get("days", 90))
	_b(state)["fp"][str(fid)] = {"o": o, "end": state.tick + days}
	Diplomacy.remember(state, v, o, "pass_granted")
	state.add_chronicle("%s accorde un laissez-passer de %d jours au %s de %s." % [_name(state, o), days, f.fleet_name, _name(state, v)],
			Espionage.private_to(state, [o, v]))


static func _passes_daily(state: GameState) -> void:
	var fp: Dictionary = _b(state)["fp"]
	for k in fp.keys():
		if int(fp[k]["end"]) <= state.tick or not state.fleets.has(int(k)):
			fp.erase(k)
			dirty(state)


## Propositions de frontière entre humains (prop. 31) : la demande de laissez-passer.
static func is_kind(kind: String) -> bool:
	return kind == "bpass"


static func kind_label(p: Dictionary) -> String:
	return "Laissez-passer demandé" if String(p["treaty"]) == "bpass" else String(p["treaty"])


static func kind_text(state: GameState, p: Dictionary) -> String:
	var f: Fleet = state.fleets.get(int(p.get("fleet", -1)))
	if f == null:
		return ""
	return "Son %s (%d vaisseau%s) traverserait librement votre espace pendant %d jours." % [f.fleet_name, f.ships.size(), "x" if f.ships.size() > 1 else "", int(_cfg("pass").get("days", 90))]


static func answer_days() -> int:
	return int(_cfg("pass").get("answer_days", 15))


static func check_accept(state: GameState, p: Dictionary) -> String:
	if not state.fleets.has(int(p.get("fleet", -1))):
		return "cette flotte n'existe plus"
	return ""


static func answer(state: GameState, p: Dictionary, accept: bool) -> void:
	var from := int(p["from"])
	var to := int(p["to"])
	if accept and state.fleets.has(int(p["fleet"])):
		grant_pass(state, to, from, int(p["fleet"]))
	else:
		state.add_chronicle("%s refuse le laissez-passer demandé par %s." % [_name(state, to), _name(state, from)], Espionage.private_to(state, [from, to]))


# --- Péage (lot 2) ---------------------------------------------------------------------------------------

static func toll_steps() -> Array:
	return _cfg("toll").get("steps", [0])


static func toll_level(state: GameState, o: int) -> int:
	return int((state.borders.get("toll", {}) as Dictionary).get(str(o), 0))


## Énergie par saut que paie une flotte armée de passage chez o.
static func toll_of(state: GameState, o: int) -> int:
	var st := toll_steps()
	return int(st[clampi(toll_level(state, o), 0, st.size() - 1)])


static func check_toll(state: GameState, o: int, level: int) -> String:
	if level < 0 or level >= toll_steps().size():
		return "palier inconnu"
	if level == toll_level(state, o):
		return "c'est déjà votre péage"
	return ""


static func set_toll(state: GameState, o: int, level: int) -> void:
	_b(state)["toll"][str(o)] = level
	if level == 0:
		state.add_chronicle("%s lève son péage." % _name(state, o), Espionage.private_to(state, [o]))
	else:
		state.add_chronicle("%s établit un péage de %d énergie par saut pour les flottes de guerre de passage." % [_name(state, o), toll_of(state, o)],
				Espionage.public_to(state, [o]))


## FleetSystem : une flotte armée qui entre dans un système de o avec le droit de passage paie le péage.
static func charge_toll(state: GameState, f: Fleet, sid: int) -> void:
	if not active(state):
		return
	var o := state.system_owner(sid)
	# Douanes stellaires (lot 3 de l'arbre) : les vaisseaux sans armes paient aussi, à moitié prix.
	var civil := not Combat.is_armed(f)
	if civil and (o < 0 or GameState.is_npc(o) or Research.fx_int(state, o, "customs") <= 0):
		return
	if o < 0 or o == f.owner or _exempt(state, o, f.owner) or strong_link(state, o, f.owner):
		return
	if _amph_flag(state, o, f.owner, "toll_free") or corridor(state, o, f.owner):
		return
	var amount := toll_of(state, o)
	if civil:
		@warning_ignore("integer_division")
		amount /= 2
	if amount <= 0 or (not civil and not fleet_right(state, f, o)):
		return
	var ev := state.get_empire(f.owner)
	var paid := mini(amount, int(ev.resources.get("energy", 0)))
	if paid <= 0:
		return
	ev.resources["energy"] = int(ev.resources["energy"]) - paid
	var eo := state.get_empire(o)
	eo.resources["energy"] = int(eo.resources.get("energy", 0)) + paid * maxi(1, int(talent(state, o).get("toll_x", 1)) + Research.fx_int(state, o, "toll_x"))


# --- Flottes à nos portes (lot 2) ------------------------------------------------------------------------

## Chaque mois : une grosse flotte armée stationnée à un saut de chez o, sans droit d'y entrer, et que o voit.
static func _gates(state: GameState) -> void:
	var gates := {}
	var min_ships := int(_cfg("gates").get("min_ships", 4))
	for fid in state.sorted_fleet_ids():
		var f: Fleet = state.fleets[fid]
		if GameState.is_npc(f.owner) or f.is_moving() or f.ships.size() < min_ships or not Combat.is_armed(f):
			continue
		var here := state.system_owner(f.system_id)
		for n in state.galaxy.systems[f.system_id].neighbors:
			var o := state.system_owner(int(n))
			if o < 0 or o == f.owner or o == here or gates.has(_pk(o, f.owner)):
				continue
			if not grants(state, o, f.owner) and _sees(state, o, f):
				gates[_pk(o, f.owner)] = 1
	_b(state)["gates"] = gates


static func at_gates(state: GameState, o: int, v: int) -> bool:
	return active(state) and (state.borders.get("gates", {}) as Dictionary).has(_pk(o, v))


## Lignes d'opinion de a envers b dues aux frontières.
static func opinion_parts(state: GameState, a: int, b: int) -> Array:
	var out: Array = []
	if not active(state):
		return out
	if at_gates(state, a, b):
		out.append(["Ses flottes à nos portes", int(_cfg("gates").get("opinion", -5))])
	return out


## Frontières communes : un libre-passage réciproque divise la friction (friction_pct).
static func friction_pct(state: GameState, a: int, b: int) -> int:
	if active(state) and has_treaty(state, a, b):
		return int(data().get("friction_pct", 50))
	return 100


# --- Amphictyonie (lot 2) ---------------------------------------------------------------------------------

## Le Nomos impose-t-il la libre navigation entre ces deux amphictyons ? (pas de frontière close)
static func amph_free_navigation(state: GameState, o: int, v: int) -> bool:
	return _amph_flag(state, o, v, "free_nav")


static func check_arbiter(state: GameState, eid: int, a: int, b: int) -> String:
	if not state.amph_on or AmphInst.arbiter(state) != eid:
		return "seul l'Arbitre des étoiles peut imposer un libre-passage"
	if a == b or not Amphictyony.is_member(state, a) or not Amphictyony.is_member(state, b):
		return "il faut deux amphictyons"
	if Combat.at_war(state, a, b):
		return "ils sont en guerre"
	if strong_link(state, a, b) or has_treaty(state, a, b):
		return "leurs frontières sont déjà ouvertes"
	if int((_b(state)["imp"] as Dictionary).get(Diplomacy.key(a, b), 0)) > state.tick:
		return "libre-passage déjà imposé"
	var cost: Dictionary = _cfg("arbiter").get("cost", {})
	if not Economy.can_afford(state.get_empire(eid), cost):
		return "il faut %d influence" % int(cost.get("influence", 0))
	return ""


static func arbiter_impose(state: GameState, eid: int, a: int, b: int) -> void:
	Economy.pay(state.get_empire(eid), _cfg("arbiter").get("cost", {}))
	dirty(state)
	_b(state)["imp"][Diplomacy.key(a, b)] = state.tick + int(_cfg("arbiter").get("days", 1800))
	state.add_chronicle("L'Arbitre des étoiles, %s, impose le libre-passage entre %s et %s pour cinq ans. Les douaniers des deux bords déposent leurs tampons en soupirant." % [
			_name(state, eid), _name(state, a), _name(state, b)], Espionage.public_to(state, [eid, a, b]))


# --- Ponts (lot 3) -----------------------------------------------------------------------------------------

## Héros (prop. 27) : un ambassadeur auprès de l'Amphictyonie facilite les laissez-passer (orateur : davantage).
static func hero_pass_bonus(state: GameState, v: int) -> int:
	var h := Heroes.at_post(state, "amph", 0, v)
	if h.is_empty():
		return 0
	return int(_cfg("pass").get("ambassador_bonus", 15)) * (2 if String(h["cls"]) == "orateur" else 1)


## Espionnage (prop. 24) : corridor discret de v chez o (ses flottes passent sans intrusion constatée).
static func corridor(state: GameState, o: int, v: int) -> bool:
	return int((state.borders.get("corr", {}) as Dictionary).get(_pk(o, v), 0)) > state.tick


static func spy_check(state: GameState, a: int, b: int, _op_id: String) -> String:
	if not active(state):
		return "les frontières sont libres dans cette partie"
	if _exempt(state, b, a) or grants(state, b, a):
		return "vos flottes passent déjà chez lui"
	if corridor(state, b, a):
		return "un corridor est déjà ouvert"
	return ""


static func spy_apply(state: GameState, a: int, b: int, _o: Dictionary) -> String:
	dirty(state)
	var days := int(data().get("corridor_days", 90))
	_b(state)["corr"][_pk(b, a)] = state.tick + days
	return "un corridor discret est ouvert : %d jours sans qu'aucune patrouille ne remarque nos flottes." % days


## Commerce (prop. 23) : une route qui traverse les systèmes d'un empire Close envers l'un de ses bouts
## perd trade_closed_pct de sa valeur (les convois des contrebandiers passent quand même).
static func trade_pct(state: GameState, a: int, b: int, path: Array) -> int:
	if not active(state):
		return 0
	for i in range(1, path.size() - 1):
		var o := state.system_owner(int(path[i]))
		if o < 0 or o == a or o == b:
			continue
		for v in [a, b]:
			if not _exempt(state, o, v) and not civil_ok(state, o, v):
				return int(data().get("trade_closed_pct", -25))
	return 0

## Précepte Sanctuaire (catalogue ouvert des préceptes) : fermer ses frontières à un empire d'une
## autre foi ne lui laisse aucun grief.
static func sanctuary_free(state: GameState, o: int, v: int) -> bool:
	if not state.faith_on:
		return false
	var fo := Faiths.state_faith(state, o)
	return fo != "" and Faiths.has_precept(state, fo, "sanctuaire") and Faiths.state_faith(state, v) != fo
