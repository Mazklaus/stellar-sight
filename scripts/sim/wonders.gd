class_name Wonders
extends RefCounted
## Merveilles galactiques (étude « Merveilles galactiques », 2026-11-15 ; data/wonders.json).
## Une merveille est un grand chantier à part : il ne prend ni emplacement ni la file de la colonie,
## un empire en mène un à la fois (Stellaris), il se paie au fil des mois après une avance de 20 %
## (Humankind : projet partagé) et les autres colonies proches peuvent y verser. Plusieurs empires
## peuvent courir après la même merveille : le premier qui l'achève la gagne, les autres récupèrent la
## moitié de leur mise, ou toute leur mise s'ils la reportent dans les 90 jours sur une autre merveille
## de même ère ou plus haute (Civilization VI et VII). Chaque merveille demande un site (étoile, terrain,
## type de planète, bâtiment, capitale, monde frontalier, carrefour…). On voit les chantiers rivaux là
## où l'on voit, ou par un réseau d'espionnage, par quarts d'avancement. Une merveille achevée entre
## dans les bâtiments de sa colonie : score, opinion, Rayonnement et changement de mains suivent.
## Les mégastructures se bâtissent par étapes, chacune donnant déjà une part de l'effet.
## Le catalogue (familles, effets « fx » et « special ») est dans WondersCatalog (lot 2), les ponts
## (guerre, espionnage, Amphictyonie, œuvres collectives, victoire) dans WondersBridges (lot 3).
##
## État : state.wonders = {"mode", "pool": [ids tirés] ([] = tout), "build": {merveille: {empire:
##  chantier}}, "carry": {empire: {"amt", "until", "era"}}, "warn": {"m>e>r": quart}, "stage":
##  {"m#planète": étape}, "builder": {"m#planète": empire}, "sig": empreinte des propriétaires, ...}.
## Un chantier : {"p": planète, "pts": avancement, "need": points à atteindre, "paid": {ressource: n},
##  "total": {ressource: n}, "ok": 1 si le mois est payé, "since": jour, "st": étape atteinte,
##  "c": {empire: part versée} (œuvres collectives)}. Les points avancent de 100 par jour à vitesse normale.

const MONTH := 30
const OFFSET := 23  ## jour du mois où se paient les chantiers


static func data() -> Dictionary:
	return GameData.wonders()


static func rules() -> Dictionary:
	return data()["rules"]


static func r_int(key: String) -> int:
	return int(rules().get(key, 0))


static func def(wid: String) -> Dictionary:
	return GameData.wonders_list().get(wid, {})


static func is_wonder(id: String) -> bool:
	return GameData.wonders_list().has(id)


static func label(wid: String) -> String:
	return String(def(wid).get("label", wid))


static func family(wid: String) -> String:
	return String(def(wid).get("family", "galactique"))


static func family_label(fam: String) -> String:
	return String(data()["families"].get(fam, fam))


static var _ids: Array[String] = []


## Toutes les merveilles du catalogue, triées par ère puis par nom (identifiants).
static func all_ids() -> Array[String]:
	if _ids.is_empty():
		var keys: Array = GameData.wonders_list().keys()
		keys.sort_custom(func(a: Variant, b: Variant) -> bool:
			var ea := int(def(String(a)).get("era", 1))
			var eb := int(def(String(b)).get("era", 1))
			return ea < eb if ea != eb else String(a) < String(b))
		for k in keys:
			_ids.append(String(k))
	return _ids


static func mode_defs() -> Array:
	return data().get("modes", [])


static func default_mode() -> String:
	return String(data().get("default_mode", "toutes"))


## Une merveille unique dans la galaxie (course) ? Les mégastructures et les Grands Œuvres non.
static func galaxy_unique(wid: String) -> bool:
	return not ["mega", "oeuvre"].has(family(wid))


static func repeatable(wid: String) -> bool:
	return bool(def(wid).get("repeat", false))


static func stages(wid: String) -> Array:
	return def(wid).get("stages", [])


# --- Réglage, sauvegarde -----------------------------------------------------------------------

static func mode(state: GameState) -> String:
	return String(state.wonders.get("mode", default_mode()))


static func enabled(state: GameState) -> bool:
	return mode(state) != "aucune"


static func worth_saving(state: GameState) -> bool:
	return not state.wonders.is_empty()


static func setup(state: GameState, mode_id: String) -> void:
	var ok := false
	for m: Dictionary in mode_defs():
		if String(m["id"]) == mode_id:
			ok = true
	state.wonders = {"mode": mode_id if ok else default_mode(), "pool": [], "build": {}, "carry": {}, "warn": {}, "stage": {},
			"builder": {}, "sig": ""}
	if mode(state) == "tirage":
		_draw(state)
	WondersCatalog.setup(state)


## Tirage (Old World) : environ 60 % du catalogue, au hasard de la graine. Les merveilles déjà
## nécessaires au jeu (Bourse galactique, mégastructures) restent.
static func _draw(state: GameState) -> void:
	var pool: Array = []
	for wid in all_ids():
		if family(wid) == "mega" or wid == "bourse_galactique" or family(wid) == "oeuvre":
			pool.append(wid)
		elif absi(hash([state.seed_value, "merveille", wid])) % 100 < int(data().get("draw_pct", 60)):
			pool.append(wid)
	state.wonders["pool"] = pool


static func to_dict(state: GameState) -> Dictionary:
	return Ancients._sorted(state.wonders)


static func from_dict(state: GameState, d: Dictionary) -> void:
	state.wonders = {}
	if d.is_empty():
		return
	state.wonders = GameData._to_ints(d.duplicate(true))


static func _m(state: GameState, key: String) -> Dictionary:
	if not state.wonders.has(key):
		state.wonders[key] = {}
	return state.wonders[key]


static func in_pool(state: GameState, wid: String) -> bool:
	var pool: Array = state.wonders.get("pool", [])
	return pool.is_empty() or pool.has(wid)


# --- Lecture ------------------------------------------------------------------------------------

## Chantiers en cours d'une merveille : {empire (chaîne): chantier}.
static func builds_of(state: GameState, wid: String) -> Dictionary:
	return _m(state, "build").get(wid, {})


static func build_of(state: GameState, eid: int, wid: String) -> Dictionary:
	return builds_of(state, wid).get(str(eid), {})


## Chantiers menés par un empire : [[merveille, chantier], …], triés.
static func builds_by(state: GameState, eid: int) -> Array:
	var out: Array = []
	var b: Dictionary = state.wonders.get("build", {})
	var keys := b.keys()
	keys.sort()
	for wid in keys:
		var e: Dictionary = b[wid]
		if e.has(str(eid)):
			out.append([String(wid), e[str(eid)]])
	return out


## Grands chantiers qui comptent dans la limite (pas les restaurations ni les œuvres collectives).
static func active_count(state: GameState, eid: int) -> int:
	var n := 0
	for pair in builds_by(state, eid):
		var e: Dictionary = pair[1]
		if not bool(e.get("ruin", 0)) and not def(String(pair[0])).has("collective"):
			n += 1
	return n


static func max_builds(state: GameState, eid: int) -> int:
	return r_int("max_builds") + Research.fx_int(state, eid, "wonder_builds")


## Merveilles tenues : [[merveille, planète, propriétaire], …] (bâtiments achevés ou à une étape).
static func held(state: GameState) -> Array:
	var out: Array = []
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		for b in c.buildings:
			if is_wonder(b):
				out.append([b, pid, c.owner])
	return out


## Où est bâtie cette merveille (planète, -1 si nulle part). Une étape suffit.
static func built_at(state: GameState, wid: String) -> int:
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.buildings.has(wid):
			return pid
	return -1


## Merveilles tenues par un empire (identifiants, avec répétition pour les Grands Œuvres).
static func owned(state: GameState, eid: int) -> Array[String]:
	var out: Array[String] = []
	for row in held(state):
		if int(row[2]) == eid and not is_staging(state, String(row[0]), int(row[1])):
			out.append(String(row[0]))
	return out


## Étape atteinte d'une mégastructure encore en chantier (0 si achevée ou sans étapes).
static func stage_at(state: GameState, wid: String, pid: int) -> int:
	return int(state.wonders.get("stage", {}).get("%s#%d" % [wid, pid], 0))


static func is_staging(state: GameState, wid: String, pid: int) -> bool:
	return stage_at(state, wid, pid) > 0


## Rendement d'une merveille dans sa colonie : celui de l'étape atteinte pour une mégastructure.
static func yields_of(state: GameState, pid: int, wid: String) -> Dictionary:
	if WondersBridges.shared_yields(wid):
		return {}  # œuvre du Koinon : partagée chaque mois entre ceux qui ont versé
	var st := stage_at(state, wid, pid)
	var sts := stages(wid)
	if st > 0 and st <= sts.size():
		return (sts[st - 1] as Dictionary).get("yields", {})
	return def(wid).get("yields", {})


## Avancement en pour cent d'un chantier.
static func pct(entry: Dictionary) -> int:
	if entry.is_empty():
		return 0
	@warning_ignore("integer_division")
	return clampi(int(entry["pts"]) * 100 / maxi(1, int(entry["need"])), 0, 100)


## Quart d'avancement (0 à 3 ; 4 = achevé), ce qu'un rival voit du chantier.
static func quarter(entry: Dictionary) -> int:
	@warning_ignore("integer_division")
	return clampi(pct(entry) / maxi(1, r_int("quarter")), 0, 4)


## L'empire viewer connaît-il le chantier de eid sur cette merveille ? Le sien, la Toile du Silence,
## un système visible ou un réseau d'espionnage chez lui.
static func knows(state: GameState, viewer: int, eid: int, wid: String, seen := {}) -> bool:
	if viewer == eid:
		return true
	var e := build_of(state, eid, wid)
	if e.is_empty():
		return false
	if WondersCatalog.sees_all(state, viewer):
		return true
	if Espionage.tier(state, viewer, eid) >= 1:
		return true
	var sid := state.galaxy.get_planet(int(e["p"])).system_id
	var vis: Dictionary = seen if not seen.is_empty() else Fleets.visible_systems(state, viewer)
	return vis.has(sid)


## Les chantiers rivaux connus d'un empire sur une merveille : [[empire, quart], …].
static func rivals_known(state: GameState, viewer: int, wid: String, seen := {}) -> Array:
	var out: Array = []
	var b := builds_of(state, wid)
	var keys := b.keys()
	keys.sort()
	for k in keys:
		var eid := int(k)
		if eid != viewer and knows(state, viewer, eid, wid, seen):
			out.append([eid, quarter(b[k])])
	return out


# --- Déblocage, site, coût -----------------------------------------------------------------------

## La merveille est-elle à la portée de cet empire (technologie, ère, registre, credo) ?
static func unlocked(state: GameState, eid: int, wid: String) -> bool:
	var d := def(wid)
	var e := state.get_empire(eid)
	if d.is_empty() or e == null or e.is_npc():
		return false
	if bool(d.get("culture", false)) and not Culture.enabled(state):
		return false
	var cr := String(d.get("credo", ""))
	if cr != "" and String(e.faction().get("credo", "")) != cr:
		return false
	var era := Research.current_era(state, eid)
	if d.has("unlock_era") and era < int(d["unlock_era"]):
		return false
	var reg := String(d.get("registre", ""))
	if reg != "" and String(e.faction().get("registre", "")) == reg and era >= int(d.get("era", 1)) - 1:
		return true  # son registre : une ère plus tôt, sans la technologie (Civ VII)
	return Research.knows_all(state, eid, d.get("requires_tech", []))


## Visible dans les listes de ce peuple (technologies qu'il aura un jour, credo, catalogue tiré).
static func visible_for(state: GameState, eid: int, wid: String) -> bool:
	var d := def(wid)
	var e := state.get_empire(eid)
	if d.is_empty() or e == null or not in_pool(state, wid) or not enabled(state):
		return false
	if bool(d.get("culture", false)) and not Culture.enabled(state):
		return false
	if family(wid) == "oeuvre" and not WondersBridges.oeuvres_on(state):
		return false
	var cr := String(d.get("credo", ""))
	if cr != "" and String(e.faction().get("credo", "")) != cr:
		return false
	for t in d.get("requires_tech", []):
		if not Research.is_visible(e.faction(), String(t)):
			return false
	return true


## Coût total d'une merveille pour un empire (technologies, plans volés, Grands Œuvres plus chers).
static func total_cost(state: GameState, eid: int, wid: String) -> Dictionary:
	var pct_ := Research.fx_int(state, eid, "building_cost_pct") + Research.fx_int(state, eid, "wonder_cost_pct")
	pct_ += int(_m(state, "plans").get("%s>%d" % [wid, eid], 0))
	var c := Research.scaled_amounts(def(wid).get("cost", {}), pct_)
	if family(wid) == "oeuvre":
		var n := owned(state, eid).count(wid)
		if n > 0:
			c = Research.scaled_amounts(c, n * r_int("oeuvre_step_pct"))
	return Goods.with_strategic(state, c, Goods.building_strategic(wid))


## Avance due au lancement (20 % du coût), moins ce qu'un report de course apporte.
static func advance_cost(state: GameState, eid: int, wid: String) -> Dictionary:
	var tot := total_cost(state, eid, wid)
	var out := {}
	var carry := carry_for(state, eid, wid)
	for r in tot:
		@warning_ignore("integer_division")
		var v := int(tot[r]) * r_int("advance_pct") / 100 - int(carry.get(r, 0))
		if v > 0:
			out[r] = v
	return out


## Report de course utilisable sur cette merveille (même ère ou plus haute, avant l'échéance).
static func carry_for(state: GameState, eid: int, wid: String) -> Dictionary:
	var c: Dictionary = _m(state, "carry").get(str(eid), {})
	if c.is_empty() or state.tick > int(c["until"]) or int(def(wid).get("era", 1)) < int(c["era"]):
		return {}
	return c["amt"]


## Points à atteindre : la durée en jours × 100.
static func need_pts(wid: String) -> int:
	return int(def(wid).get("days", 360)) * 100


## Vitesse du chantier en points par jour : 100, plus le gouverneur (et son trait de maître d'œuvre),
## plus son registre (Civ VII : +30 %), plus les effets d'empire.
static func speed(state: GameState, eid: int, wid: String, pid: int) -> int:
	var v := 100 + Research.fx_int(state, eid, "wonder_speed_pct")
	var e := state.get_empire(eid)
	var reg := String(def(wid).get("registre", ""))
	if reg != "" and e and String(e.faction().get("registre", "")) == reg:
		v = v * r_int("own_registre_speed") / 100
	var sid := state.galaxy.get_planet(pid).system_id
	var h := Heroes.at_post(state, "system", sid, eid)
	if not h.is_empty():
		v += r_int("governor_pct")
		var tp: Dictionary = rules().get("trait_pct", {})
		for t in h.get("traits", []):
			v += int(tp.get(String(t), 0))
	return maxi(10, v)


## "" si le site convient, sinon la raison. Les conditions de terrain, de faune, d'anciennes ou de
## peuples ne s'appliquent pas quand ces réglages ne sont pas en jeu.
static func site_reason(state: GameState, eid: int, pid: int, wid: String) -> String:
	var site: Dictionary = def(wid).get("site", {})
	var p := state.galaxy.get_planet(pid)
	var c: Colony = state.colonies.get(pid)
	var e := state.get_empire(eid)
	if p == null or c == null or e == null:
		return "planète inconnue"
	var sys := state.galaxy.systems[p.system_id]
	if bool(site.get("capital", false)) and e.capital_planet != pid:
		return "seulement sur votre capitale"
	if site.has("star") or site.has("terrain"):
		var ok := false
		if site.has("star") and (site["star"] as Array).has(sys.star_type):
			ok = true
		if site.has("or_star") and (site["or_star"] as Array).has(sys.star_type):
			ok = true
		if site.has("terrain"):
			if not Terrain.active(state):
				ok = true
			else:
				var here := Terrain.at(state, p.system_id)
				for t in site["terrain"]:
					if here.has(String(t)):
						ok = true
		if not ok:
			var names := PackedStringArray()
			for s in site.get("star", []) + site.get("or_star", []):
				names.append(GalaxyGenerator.star_label(String(s)).to_lower())
			for t in site.get("terrain", []):
				names.append(Terrain.label(String(t)).to_lower())
			return "il faut un système : %s" % " ou ".join(names)
	if bool(site.get("storm_or_terrain", false)) and Terrain.active(state) and Terrain.at(state, p.system_id).filter(func(t: String) -> bool: return t != sys.star_type).is_empty():
		return "il faut un système de terrain difficile (nébuleuse, astéroïdes, tempête…)"
	if site.has("planet"):
		var alt := String(site.get("or_building", ""))
		if not (site["planet"] as Array).has(p.type) and not (alt != "" and c.buildings.has(alt)):
			var names := PackedStringArray()
			for t in site["planet"]:
				names.append(String(GameData.planet_type(String(t)).get("label", t)).to_lower())
			if alt != "":
				names.append("une colonie avec %s" % String(GameData.building(alt).get("label", alt)).to_lower())
			return "il faut : %s" % " ou ".join(names)
	if site.has("building"):
		var need := String(site["building"])
		var alt2 := String(site.get("or_building", ""))
		if not _system_has(state, eid, p.system_id, need) and not (alt2 != "" and not site.has("planet") and _system_has(state, eid, p.system_id, alt2)):
			var t := String(GameData.building(need).get("label", need)).to_lower()
			if alt2 != "" and not site.has("planet"):
				t += " ou " + String(GameData.building(alt2).get("label", alt2)).to_lower()
			return "il faut dans le système : %s" % t
	if int(site.get("min_size", 0)) > p.size:
		return "il faut une planète de taille %d ou plus" % int(site["min_size"])
	if int(site.get("min_pop", 0)) > c.population:
		return "il faut %d population (%d)" % [int(site["min_pop"]), c.population]
	if int(site.get("crossroads", 0)) > sys.neighbors.size():
		return "il faut un carrefour de %d routes hyperspatiales (%d ici)" % [int(site["crossroads"]), sys.neighbors.size()]
	if bool(site.get("border", false)):
		var front := false
		for n in sys.neighbors:
			if state.system_owner(n) != eid:
				front = true
		if not front:
			return "il faut un monde frontalier (un système voisin qui n'est pas à vous)"
	if bool(site.get("no_habitable", false)):
		for opid in sys.planet_ids:
			var o: Colony = state.colonies.get(opid)
			if o and o.is_colony():
				return "il faut un système sans monde habité"
			if int(GameData.planet_type(state.galaxy.get_planet(opid).type).get("base_hab", 0)) > 0:
				return "il faut une étoile sans monde habitable"
	if bool(site.get("amph", false)) and not (Amphictyony.founded(state) and Amphictyony.is_member(state, eid)):
		return "il faut être membre de l'Amphictyonie"
	if bool(site.get("amph_seat", false)) and not (Amphictyony.founded(state) and Amphictyony.is_member(state, eid) and e.capital_planet == pid):
		return "seulement sur la capitale d'un membre de l'Amphictyonie"
	if bool(site.get("nest", false)) and Fauna.active(state) and not Fauna.nests(state).has(p.system_id):
		var near := false
		for n in sys.neighbors:
			if Fauna.nests(state).has(n):
				near = true
		if not near:
			return "il faut un nid de créatures dans le système ou à côté"
	if int(site.get("ancient_near", 0)) > 0 and Ancients.enabled(state):
		var d := FactionTraits.jumps_from(state.galaxy, p.system_id)
		var near2 := false
		for aid in Ancients.ids(state):
			var home := int(Ancients.get_a(state, aid).get("home", -1))
			if home >= 0 and int(d.get(home, 999)) <= int(site["ancient_near"]):
				near2 = true
		if not near2:
			return "il faut une puissance ancienne à %d sauts ou moins" % int(site["ancient_near"])
	if int(site.get("min_species", 0)) > 1 and Peoples.enabled(state) and Peoples.counts(state, c).size() < int(site["min_species"]):
		return "il faut un monde où vivent %d peuples ou plus" % int(site["min_species"])
	if bool(site.get("holy", false)):
		if state.faith_on:
			var fid := Faiths.state_faith(state, eid)
			if fid == "" or int(Faiths.faith(state, fid).get("holy", -1)) != pid:
				return "seulement sur le monde saint de votre foi d'État"
		elif e.capital_planet != pid:
			return "seulement sur votre capitale (sans religions)"
	if bool(site.get("trade_route", false)):
		var on := false
		for r: Dictionary in state.trade.get("routes", []):
			if (int(r["from"]) == eid or int(r["to"]) == eid) and (r["path"] as Array).has(p.system_id):
				on = true
		if not on:
			return "il faut un système traversé par une de vos routes commerciales"
	if bool(site.get("distinct_system", false)):
		for opid in sys.planet_ids:
			var o2: Colony = state.colonies.get(opid)
			if o2 and o2.buildings.has(wid):
				return "déjà un %s dans ce système" % label(wid)
	return ""


static func _system_has(state: GameState, eid: int, sid: int, bid: String) -> bool:
	for opid in state.galaxy.systems[sid].planet_ids:
		var o: Colony = state.colonies.get(opid)
		if o and o.owner == eid and o.has_kind(bid):
			return true
	return false


## "" si l'empire peut lancer cette merveille sur cette planète, sinon la raison.
static func check_start(state: GameState, eid: int, pid: int, wid: String) -> String:
	var d := def(wid)
	if d.is_empty():
		return "merveille inconnue : %s" % wid
	if not enabled(state):
		return "pas de merveilles dans cette partie"
	if not in_pool(state, wid):
		return "cette merveille n'est pas dans le tirage de la partie"
	var e := state.get_empire(eid)
	var c: Colony = state.colonies.get(pid)
	if e == null or c == null or c.owner != eid:
		return "cette planète ne vous appartient pas"
	if not c.is_established():
		return "la colonie n'est pas encore fondée"
	if not c.is_colony() and not bool(d.get("site", {}).get("outpost_ok", false)):
		return "impossible sur un avant-poste"
	if family(wid) == "oeuvre" and not WondersBridges.oeuvres_on(state):
		return "la victoire des Grands Œuvres n'est pas en jeu"
	if d.has("collective") and String(d["collective"]) != "crisis":
		var cw := WondersBridges.check_collective(state, eid, wid)
		if cw != "":
			return cw
	var nb := WondersBridges.check_nomos(state, eid, wid)
	if nb != "":
		return nb
	if not unlocked(state, eid, wid):
		if d.has("credo") and String(e.faction().get("credo", "")) != String(d["credo"]):
			return "réservée au credo : %s" % String(d["credo"])
		if d.has("unlock_era"):
			return "il faut atteindre l'ère %d" % int(d["unlock_era"])
		return "technologie requise : %s" % Research.missing_text(state, eid, d.get("requires_tech", []))
	var ruin := WondersCatalog.ruin_of(state, wid)
	if ruin >= 0:
		return "elle gît en ruine sur %s : il faut la restaurer" % state.galaxy.get_planet(ruin).display_name(state.galaxy)
	if galaxy_unique(wid):
		var at := built_at(state, wid)
		if at >= 0:
			var o: Colony = state.colonies[at]
			return "merveille déjà bâtie chez %s" % (state.get_empire(o.owner).display_name() if o.owner != eid else "vous")
	elif not repeatable(wid):
		for row in held(state):
			if String(row[0]) == wid and int(row[2]) == eid and not is_staging(state, wid, int(row[1])):
				return "une seule par empire : déjà bâtie"
	var mine := build_of(state, eid, wid)
	if not mine.is_empty():
		return "déjà en chantier sur %s" % state.galaxy.get_planet(int(mine["p"])).display_name(state.galaxy)
	if repeatable(wid) or family(wid) == "mega":
		var p0 := state.galaxy.get_planet(pid)
		for opid in state.galaxy.systems[p0.system_id].planet_ids:
			var oc: Colony = state.colonies.get(opid)
			if oc and oc.buildings.has(wid) and (repeatable(wid) or oc.owner == eid):
				return "déjà un %s dans ce système" % label(wid).to_lower()
	if not d.has("collective") and active_count(state, eid) >= max_builds(state, eid):
		return "un grand chantier à la fois (%d en cours)" % active_count(state, eid)
	var site := site_reason(state, eid, pid, wid)
	if site != "":
		return site
	var adv := advance_cost(state, eid, wid)
	if not Economy.can_afford(e, adv):
		return "ressources insuffisantes pour l'avance (il faut %s)" % GameData.format_amounts(adv)
	return ""


# --- Ordres -------------------------------------------------------------------------------------

static func start(state: GameState, eid: int, pid: int, wid: String, added: Array[Dictionary]) -> void:
	var e := state.get_empire(eid)
	var adv := advance_cost(state, eid, wid)
	Economy.pay(e, adv)
	var tot := total_cost(state, eid, wid)
	var paid := adv.duplicate()
	var carry := carry_for(state, eid, wid)
	for r in carry:
		paid[r] = mini(int(tot.get(r, 0)), int(paid.get(r, 0)) + int(carry[r]))
	if not carry.is_empty():
		_m(state, "carry").erase(str(eid))
	var b: Dictionary = _m(state, "build")
	if not b.has(wid):
		b[wid] = {}
	b[wid][str(eid)] = {"p": pid, "pts": 0, "need": need_pts(wid), "paid": paid, "total": tot, "ok": 1, "since": state.tick, "st": 0}
	var p := state.galaxy.get_planet(pid)
	added.append(state.add_chronicle("%s pose la première pierre de %s sur %s. Les architectes promettent que ce sera fini à temps ; ils le promettent toujours." % [
			e.short_name(), label(wid), p.display_name(state.galaxy)], Espionage.private_to(state, [eid], p.system_id)))


## "" si l'empire peut abandonner ce chantier.
static func check_cancel(state: GameState, eid: int, wid: String) -> String:
	return "" if not build_of(state, eid, wid).is_empty() else "aucun chantier de cette merveille"


## Abandon volontaire : comme une course perdue (moitié rendue, ou report de toute la mise).
static func cancel(state: GameState, eid: int, wid: String, added: Array[Dictionary]) -> void:
	var entry := build_of(state, eid, wid)
	if entry.is_empty():
		return
	_lose(state, eid, wid, entry, -1, added)


## Verser depuis une colonie à 3 sauts ou moins : 5 % du coût en matériaux, 5 % d'avancement ; une
## fois par mois et par colonie.
static func check_contribute(state: GameState, eid: int, wid: String, from_pid: int) -> String:
	var entry := build_of(state, eid, wid)
	if entry.is_empty():
		return "aucun chantier de cette merveille"
	var c: Colony = state.colonies.get(from_pid)
	if c == null or c.owner != eid or not c.is_colony() or not c.is_established():
		return "il faut une de vos colonies"
	if from_pid == int(entry["p"]):
		return "la colonie du chantier y travaille déjà"
	var d := FactionTraits.jumps_from(state.galaxy, state.galaxy.get_planet(int(entry["p"])).system_id)
	if int(d.get(state.galaxy.get_planet(from_pid).system_id, 999)) > r_int("contrib_jumps"):
		return "trop loin du chantier (%d sauts au plus)" % r_int("contrib_jumps")
	@warning_ignore("integer_division")
	var month := state.tick / MONTH
	if int(_m(state, "cm").get(str(from_pid), -1)) == month:
		return "cette colonie a déjà versé ce mois-ci"
	if pct(entry) >= 100:
		return "le chantier s'achève"
	var amt := contribute_cost(state, eid, wid)
	if not Economy.can_afford(state.get_empire(eid), amt):
		return "il faut %s" % GameData.format_amounts(amt)
	return ""


static func contribute_cost(state: GameState, eid: int, wid: String) -> Dictionary:
	var entry := build_of(state, eid, wid)
	var tot: Dictionary = entry.get("total", total_cost(state, eid, wid))
	@warning_ignore("integer_division")
	return {"materials": maxi(10, int(tot.get("materials", 0)) * r_int("contrib_pct") / 100)}


static func contribute(state: GameState, eid: int, wid: String, from_pid: int) -> void:
	var entry := build_of(state, eid, wid)
	var amt := contribute_cost(state, eid, wid)
	Economy.pay(state.get_empire(eid), amt)
	var paid: Dictionary = entry["paid"]
	paid["materials"] = int(paid.get("materials", 0)) + int(amt["materials"])
	@warning_ignore("integer_division")
	entry["pts"] = mini(int(entry["need"]), int(entry["pts"]) + int(entry["need"]) * r_int("contrib_pct") / 100)
	@warning_ignore("integer_division")
	_m(state, "cm")[str(from_pid)] = state.tick / MONTH


## Presser le dernier quart : achever contre de l'influence (3 par point de pour cent et par ère).
static func rush_cost(state: GameState, eid: int, wid: String) -> int:
	var entry := build_of(state, eid, wid)
	var left := 100 - pct(entry)
	return left * r_int("rush_influence_per_pct") * maxi(1, int(def(wid).get("era", 1)))


static func check_rush(state: GameState, eid: int, wid: String) -> String:
	var entry := build_of(state, eid, wid)
	if entry.is_empty():
		return "aucun chantier de cette merveille"
	if pct(entry) < r_int("rush_from_pct"):
		return "seulement dans le dernier quart (%d %%)" % pct(entry)
	var cost := rush_cost(state, eid, wid)
	if int(state.get_empire(eid).resources.get("influence", 0)) < cost:
		return "il faut %d influence" % cost
	return ""


static func rush(state: GameState, eid: int, wid: String) -> void:
	var entry := build_of(state, eid, wid)
	var e := state.get_empire(eid)
	e.resources["influence"] = int(e.resources.get("influence", 0)) - rush_cost(state, eid, wid)
	# Le reste du coût est réputé payé (l'influence couvre les heures supplémentaires).
	entry["paid"] = (entry["total"] as Dictionary).duplicate()
	entry["pts"] = int(entry["need"])


# --- Chaque jour ---------------------------------------------------------------------------------

static func daily(state: GameState) -> Array[Dictionary]:
	var added: Array[Dictionary] = []
	if state.wonders.is_empty() or not enabled(state):
		return added
	var monthly := posmod(state.tick, MONTH) == OFFSET
	if monthly:
		_check_owners_sig(state)
		_expire_carry(state, added)
	var b: Dictionary = state.wonders.get("build", {})
	var wids := b.keys()
	wids.sort()
	for wid in wids:
		if not b.has(wid):
			continue
		var per: Dictionary = b[wid]
		var eids := per.keys()
		eids.sort()
		for k in eids:
			if not per.has(k):
				continue
			var eid := int(k)
			var entry: Dictionary = per[k]
			eid = _sync_owner(state, String(wid), eid, entry, added)
			if eid < 0:
				continue
			if monthly:
				_pay_month(state, String(wid), eid, entry, added)
			if int(entry.get("ok", 1)) == 0 or WondersBridges.blocked(state, eid, entry):
				continue
			entry["pts"] = mini(int(entry["need"]), int(entry["pts"]) + speed(state, eid, String(wid), int(entry["p"])))
			_check_stage(state, String(wid), eid, entry, added)
			if int(entry["pts"]) >= int(entry["need"]):
				complete(state, String(wid), eid, added)
	if monthly:
		_warn(state, added)
	WondersCatalog.daily(state, added)
	WondersBridges.daily(state, added)
	return added


## Le chantier suit sa planète : conquise, elle passe au conquérant avec ce qui y est versé (prop. 18),
## sauf s'il court déjà après la même merveille ; une colonie perdue l'arrête. Renvoie le maître du
## chantier, -1 s'il a disparu.
static func _sync_owner(state: GameState, wid: String, eid: int, entry: Dictionary, added: Array[Dictionary]) -> int:
	var c: Colony = state.colonies.get(int(entry["p"]))
	var per: Dictionary = builds_of(state, wid)
	if c == null or not c.is_established() or GameState.is_npc(c.owner) or state.get_empire(c.owner) == null:
		per.erase(str(eid))
		_drop_if_empty(state, wid)
		return -1
	if c.owner == eid:
		return eid
	var now := c.owner
	per.erase(str(eid))
	if per.has(str(now)):
		_drop_if_empty(state, wid)
		return -1
	per[str(now)] = entry
	entry["ok"] = 1
	var p := state.galaxy.get_planet(int(entry["p"]))
	added.append(state.add_chronicle("%s s'empare du chantier de %s sur %s, échafaudages et dettes compris." % [
			state.get_empire(now).short_name(), label(wid), p.display_name(state.galaxy)], Espionage.private_to(state, [now, eid], p.system_id)))
	return now


static func _drop_if_empty(state: GameState, wid: String) -> void:
	var b: Dictionary = _m(state, "build")
	if b.has(wid) and (b[wid] as Dictionary).is_empty():
		b.erase(wid)


## Mensualité : le reste du coût étalé sur les mois restants ; sans les moyens, le chantier s'arrête ce
## mois-ci (rien n'est perdu).
static func _pay_month(state: GameState, wid: String, eid: int, entry: Dictionary, added: Array[Dictionary]) -> void:
	var e := state.get_empire(eid)
	var inst := installment(state, eid, wid, entry)
	if inst.is_empty():
		entry["ok"] = 1
		return
	var was := int(entry.get("ok", 1))
	if Economy.can_afford(e, inst):
		Economy.pay(e, inst)
		var paid: Dictionary = entry["paid"]
		for r in inst:
			paid[r] = int(paid.get(r, 0)) + int(inst[r])
		entry["ok"] = 1
	else:
		entry["ok"] = 0
		if was == 1:
			added.append(state.add_chronicle("%s : le chantier de %s s'arrête, faute de %s. Les ouvriers jouent aux cartes sur les échafaudages." % [
					e.short_name(), label(wid), GameData.format_amounts(inst)], Espionage.private_to(state, [eid])))


## Mensualité d'un chantier : (coût total - déjà versé) / mois restants.
static func installment(state: GameState, eid: int, wid: String, entry: Dictionary) -> Dictionary:
	var sp := speed(state, eid, wid, int(entry["p"]))
	var left_pts := maxi(0, int(entry["need"]) - int(entry["pts"]))
	@warning_ignore("integer_division")
	var months := maxi(1, int(ceil(float(left_pts) / float(sp * MONTH))))
	var out := {}
	var tot: Dictionary = entry["total"]
	var paid: Dictionary = entry["paid"]
	for r in tot:
		var rest := int(tot[r]) - int(paid.get(r, 0))
		if rest > 0:
			@warning_ignore("integer_division")
			out[r] = maxi(1, int(ceil(float(rest) / float(months))))
	return out


## Étapes d'une mégastructure : chaque seuil franchi met la merveille en place à cette étape.
static func _check_stage(state: GameState, wid: String, eid: int, entry: Dictionary, added: Array[Dictionary]) -> void:
	var sts := stages(wid)
	if sts.size() < 2:
		return
	var p := pct(entry)
	var cum := 0
	var reached := 0
	for i in sts.size() - 1:
		cum += int((sts[i] as Dictionary).get("pct", 0))
		if p >= cum:
			reached = i + 1
	if reached <= int(entry.get("st", 0)):
		return
	entry["st"] = reached
	var pid := int(entry["p"])
	var c: Colony = state.colonies[pid]
	if not c.buildings.has(wid):
		c.buildings.append(wid)
	_m(state, "stage")["%s#%d" % [wid, pid]] = reached
	Economy.clear_wonders()
	WondersCatalog.on_stage(state, wid, eid, pid, reached, added)
	added.append(state.add_chronicle("%s : %s, étape « %s » achevée." % [state.get_empire(eid).short_name(), label(wid),
			String((sts[reached - 1] as Dictionary).get("label", reached))], Espionage.private_to(state, [eid], state.galaxy.get_planet(pid).system_id)))


## Achèvement : la merveille entre dans la colonie ; les rivaux de la course perdent (prop. 2 et 3).
static func complete(state: GameState, wid: String, eid: int, added: Array[Dictionary]) -> void:
	var entry := build_of(state, eid, wid)
	if entry.is_empty():
		return
	var pid := int(entry["p"])
	var c: Colony = state.colonies[pid]
	var e := state.get_empire(eid)
	var per := builds_of(state, wid)
	per.erase(str(eid))
	if not c.buildings.has(wid):
		c.buildings.append(wid)
	_m(state, "stage").erase("%s#%d" % [wid, pid])
	_m(state, "builder")["%s#%d" % [wid, pid]] = eid
	WondersBridges.on_complete_collective(state, wid, eid, pid, entry)
	if galaxy_unique(wid):
		var keys := per.keys()
		keys.sort()
		for k in keys:
			_lose(state, int(k), wid, per[k], eid, added)
	_drop_if_empty(state, wid)
	Economy.clear_wonders()
	state.relic_rev += 1
	var p := state.galaxy.get_planet(pid)
	Politics.on_building(state, p.system_id, wid)
	Events.push(state, eid, "wonder_done", {"planet": pid, "system": p.system_id, "n": all_ids().find(wid)}, added)
	Announce.next(state, "wonder_done", {"actor": eid, "planet": pid, "name": label(wid)})
	added.append(state.add_chronicle("Merveille : %s achève %s sur %s. Toute la galaxie en parle, certains avec envie." % [
			e.display_name(), label(wid), p.display_name(state.galaxy)], Espionage.public_to(state, [eid])))
	WondersCatalog.on_complete(state, wid, eid, pid, added)
	WondersBridges.on_complete(state, wid, eid, pid, added)
	DeedsBridges.on_wonder(state, eid, wid)


## Course perdue (ou abandon) : la mise est gardée 90 jours pour une autre merveille, sinon la moitié
## revient à l'échéance. winner < 0 : abandon volontaire.
static func _lose(state: GameState, eid: int, wid: String, entry: Dictionary, winner: int, added: Array[Dictionary]) -> void:
	builds_of(state, wid).erase(str(eid))
	_drop_if_empty(state, wid)
	var amt: Dictionary = (entry["paid"] as Dictionary).duplicate()
	if amt.is_empty():
		return
	var carry: Dictionary = _m(state, "carry")
	var old: Dictionary = carry.get(str(eid), {})
	if not old.is_empty():
		_refund_half(state, eid, old["amt"])  # un report déjà en attente : on rend sa moitié tout de suite
	carry[str(eid)] = {"amt": amt, "until": state.tick + r_int("carry_days"), "era": int(def(wid).get("era", 1))}
	var e := state.get_empire(eid)
	if winner >= 0:
		Events.push(state, eid, "wonder_lost", {"rival": winner, "planet": int(entry["p"]), "n": all_ids().find(wid)}, added)
		added.append(state.add_chronicle("%s perd la course de %s. La mise (%s) attend %d jours une autre merveille ; sinon, la moitié en reviendra." % [
				e.short_name(), label(wid), GameData.format_amounts(amt), r_int("carry_days")], Espionage.private_to(state, [eid])))
	else:
		added.append(state.add_chronicle("%s abandonne le chantier de %s. La mise (%s) attend %d jours une autre merveille ; sinon, la moitié en reviendra." % [
				e.short_name(), label(wid), GameData.format_amounts(amt), r_int("carry_days")], Espionage.private_to(state, [eid])))


static func _refund_half(state: GameState, eid: int, amt: Dictionary) -> void:
	var e := state.get_empire(eid)
	if e == null:
		return
	for r in amt:
		@warning_ignore("integer_division")
		e.resources[r] = int(e.resources.get(r, 0)) + int(amt[r]) * r_int("refund_pct") / 100


static func _expire_carry(state: GameState, added: Array[Dictionary]) -> void:
	var carry: Dictionary = _m(state, "carry")
	var keys := carry.keys()
	keys.sort()
	for k in keys:
		var c: Dictionary = carry[k]
		if state.tick > int(c["until"]):
			_refund_half(state, int(k), c["amt"])
			carry.erase(k)
			var e := state.get_empire(int(k))
			if e:
				added.append(state.add_chronicle("%s récupère la moitié de sa mise perdue dans la course aux merveilles." % e.short_name(), Espionage.private_to(state, [int(k)])))


## Propriétaires des merveilles : à chaque changement (conquête), les effets « fx » sont recalculés.
static func _check_owners_sig(state: GameState) -> void:
	var parts := PackedStringArray()
	for row in held(state):
		parts.append("%s#%d>%d" % [row[0], row[1], row[2]])
	var sig := ",".join(parts)
	if sig != String(state.wonders.get("sig", "")):
		state.wonders["sig"] = sig
		state.relic_rev += 1


## Alerte « un rival vous devance » : un rival connu a au moins un quart d'avance (une fois par quart).
static func _warn(state: GameState, added: Array[Dictionary]) -> void:
	var b: Dictionary = state.wonders.get("build", {})
	var wids := b.keys()
	wids.sort()
	var warn: Dictionary = _m(state, "warn")
	for wid in wids:
		var per: Dictionary = b[wid]
		if per.size() < 2 or not galaxy_unique(String(wid)):
			continue
		var eids := per.keys()
		eids.sort()
		for k in eids:
			var me := int(k)
			var mq := quarter(per[k])
			for k2 in eids:
				var other := int(k2)
				if other == me:
					continue
				var oq := quarter(per[k2])
				if oq * r_int("quarter") - mq * r_int("quarter") < r_int("warn_gap") or not knows(state, me, other, String(wid)):
					continue
				var key := "%s>%d>%d" % [wid, me, other]
				if int(warn.get(key, -1)) >= oq:
					continue
				warn[key] = oq
				added.append(state.add_chronicle("%s : %s vous devance sur %s (plus de %d %% contre %d %%). Accélérez, ou reportez la mise ailleurs." % [
						state.get_empire(me).short_name(), state.get_empire(other).short_name(), label(String(wid)), oq * r_int("quarter"), pct(per[k])],
						Espionage.private_to(state, [me])))


# --- Effets ------------------------------------------------------------------------------------

## Effets « fx » des merveilles tenues par un empire (fusionnés dans Research.effects).
static func effects(state: GameState, eid: int) -> Dictionary:
	var out := {}
	if state.wonders.is_empty():
		return out
	for wid in owned(state, eid):
		var fx: Dictionary = def(wid).get("fx", {})
		for k in fx:
			out[k] = int(out.get(k, 0)) + int(fx[k])
	return out


## Bâtisseur d'une merveille tenue (pour le Patrimoine, prop. 17) ; -1 inconnu.
static func builder_of(state: GameState, wid: String, pid: int) -> int:
	return int(state.wonders.get("builder", {}).get("%s#%d" % [wid, pid], -1))


## Texte des effets d'une merveille, pour les fiches.
static func effect_text(wid: String) -> String:
	return String(def(wid).get("text", ""))


## Jetons des cartes de merveille : {wonder}, {wonder_text}, {wonder_quote}, {wonder_effect}, {wonder_refund}.
static func fill(state: GameState, eid: int, item: Dictionary, s: String) -> String:
	if not s.contains("{wonder"):
		return s
	var ids := all_ids()
	var n := int(item.get("n", -1))
	var wid := ids[n] if n >= 0 and n < ids.size() else ""
	var p := int(item.get("planet", -1))
	var where := state.galaxy.get_planet(p).display_name(state.galaxy) if p >= 0 else "?"
	var out := s.replace("{wonder_text}", "%s achève %s sur %s, le %s. Les architectes saluent ; les rivaux comptent leurs pertes." % [
			state.get_empire(eid).display_name(), label(wid), where, GameCalendar.date_string(int(item.get("tick", state.tick)))])
	out = out.replace("{wonder_quote}", String(def(wid).get("quote", "Il y a des choses qu'on bâtit pour soi, et d'autres pour que les autres les voient.")))
	out = out.replace("{wonder_effect}", effect_text(wid))
	var carry: Dictionary = _m(state, "carry").get(str(eid), {})
	out = out.replace("{wonder_refund}", "Mise gardée : %s, jusqu'au %s ; reportée sur une merveille d'ère %d ou plus, elle compte entière. Sinon, la moitié revient." % [
			GameData.format_amounts(carry.get("amt", {})), GameCalendar.date_string(int(carry.get("until", state.tick))), int(carry.get("era", 1))] if not carry.is_empty() else "")
	out = out.replace("{wonder}", label(wid))
	return out
