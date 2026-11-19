class_name InsKraal
extends RefCounted
## Hardes de Kraal (props 29 à 34 ; voir Insolites, data/insolites.json "kraal").
## Chaque vaisseau est un habitant : il naît Petit, devient Jeune, Adulte puis Ancien (passage d'âge tiré
## chaque mois par hachage, en moyenne après age_months mois). Deux Adultes (ou Anciens) au repos dans un
## pâturage (géante gazeuse ou nébuleuse) donnent naissance à un Petit. Les pâturages s'épuisent sous la
## harde et repoussent sans elle ; brouté un mois, un pâturage libre devient un avant-poste de la Harde.
## Routes de migration : plus vite vers un pâturage connu. Pilotes arrachés aux colonies ennemies. La
## Faune les épargne ; un Kraal mort ne se capture pas, il se dépèce (Insolites.on_ship_lost).
##
## État (Insolites.emp) : "graze": {"sid": herbe restante}, "known": {"sid": 1} (pâturages connus, routes),
## "breed": {"fid": mois de gestation}, "claim": {"sid": jours de pâture}, "pilots": {"fid": n}.


static func _c(key: String, def := 0) -> int:
	return Insolites.c_int("kraal", key, def)


static func ages() -> Array:
	return Insolites.cfg("kraal").get("ages", [])


static func is_kraal(ship_id: String) -> bool:
	return ages().has(ship_id)


static func found(state: GameState, e: Empire, sid: int, ed: Dictionary) -> void:
	var herd: Array = Insolites.cfg("kraal").get("start_herd", ["kraal_ancien"])
	var f := state.spawn_ship(e.id, String(herd[0]), sid)
	for i in range(1, herd.size()):
		f.add_ship(String(herd[i]), -1, Research.mark_gen(state, e.id))
	f.troops = Combat.max_troops(f, state)
	f.fleet_name = "Grande Harde des %s" % e.short_name()
	ed["graze"] = {}
	ed["known"] = {}
	ed["breed"] = {}
	ed["claim"] = {}
	ed["pilots"] = {}
	# Les Anciens se souviennent des routes de migration : la carte à quelques sauts est connue d'emblée.
	var d: Dictionary = FactionTraits.jumps_from(state.galaxy, sid)
	for s in d:
		if int(d[s]) <= _c("memory_jumps", 4):
			e.explored[int(s)] = true
			if is_pasture(state, int(s)):
				(ed["known"] as Dictionary)[str(s)] = 1


static func herd_pop(state: GameState, eid: int) -> int:
	var w: Dictionary = Insolites.cfg("kraal").get("age_pop", {})
	var n := 0
	for f in Fleets.empire_fleets(state, eid):
		for s in f.ships:
			n += int(w.get(s, 0))
	return n


static func kraal_count(f: Fleet) -> int:
	var n := 0
	for s in f.ships:
		if is_kraal(s):
			n += 1
	return n


static func breeders(f: Fleet) -> int:
	var a: Array = ages()
	return f.count(String(a[2])) + f.count(String(a[3]))


## Pâturage : une géante gazeuse dans le système, ou une nébuleuse (terrain).
static func is_pasture(state: GameState, sid: int) -> bool:
	if (Insolites.cfg("kraal").get("pasture_zones", []) as Array).has(Terrain.zone(state, sid)):
		return true
	var types: Array = Insolites.cfg("kraal").get("pasture_types", [])
	for pid in state.galaxy.systems[sid].planet_ids:
		if types.has(state.galaxy.get_planet(pid).type) and not Insolites.is_eaten(state, pid):
			return true
	return false


static func graze(state: GameState, eid: int, sid: int) -> int:
	return int((Insolites.emp(state, eid).get("graze", {}) as Dictionary).get(str(sid), _c("pasture_max", 100)))


## Hardes à l'arrêt dans un pâturage : {sid: [flottes]}.
static func _grazing(state: GameState, eid: int) -> Dictionary:
	var out := {}
	for f in Fleets.empire_fleets(state, eid):
		if f.is_moving() or kraal_count(f) == 0 or not is_pasture(state, f.system_id):
			continue
		if not out.has(f.system_id):
			out[f.system_id] = []
		(out[f.system_id] as Array).append(f)
	return out


static func income(state: GameState, eid: int) -> Dictionary:
	var out := {}
	var gz := _grazing(state, eid)
	var y: Dictionary = Insolites.cfg("kraal").get("graze_yields", {})
	for sid in gz:
		if graze(state, eid, int(sid)) <= 0:
			continue
		for f: Fleet in gz[sid]:
			Insolites.add_to(out, y, breeders(f))
	return out


static func damage_pct(state: GameState, f: Fleet) -> int:
	return int((Insolites.emp(state, f.owner).get("pilots", {}) as Dictionary).get(str(f.id), 0)) * _c("pilot_damage_pct", 10)


static func speed_pct(state: GameState, f: Fleet) -> int:
	if not f.is_moving() or kraal_count(f) == 0:
		return 100
	var known: Dictionary = Insolites.emp(state, f.owner).get("known", {})
	return _c("route_pct", 130) if known.has(str(f.destination())) else _c("off_route_pct", 85)


static func daily(state: GameState, eid: int, ed: Dictionary, month: bool, added: Array[Dictionary]) -> void:
	var gz := _grazing(state, eid)
	var sids := gz.keys()
	sids.sort()
	var claim: Dictionary = ed.get("claim", {})
	for sid in sids:
		(ed["known"] as Dictionary)[str(sid)] = 1
		if state.system_owner(int(sid)) >= 0:
			continue
		claim[str(sid)] = int(claim.get(str(sid), 0)) + 1
		if int(claim[str(sid)]) >= _c("claim_days", 30):
			_claim(state, eid, int(sid), added)
			claim.erase(str(sid))
	ed["claim"] = claim
	if month:
		_graze_month(state, eid, ed, gz)
		_births(state, eid, ed, gz, added)
		_aging(state, eid)
		var pl: Dictionary = ed.get("pilots", {})
		for k in pl.keys():
			if not state.fleets.has(int(k)):
				pl.erase(k)


## Un pâturage brouté un mois devient le territoire de la Harde : un avant-poste sur son meilleur corps libre.
static func _claim(state: GameState, eid: int, sid: int, added: Array[Dictionary]) -> void:
	var best := -1
	var types: Array = Insolites.cfg("kraal").get("pasture_types", [])
	for pid in state.galaxy.systems[sid].planet_ids:
		if state.colonies.has(pid) or Insolites.is_eaten(state, pid):
			continue
		var p := state.galaxy.get_planet(pid)
		var score := p.size + (100 if types.has(p.type) else 0)
		if best < 0 or score > state.galaxy.get_planet(best).size + (100 if types.has(state.galaxy.get_planet(best).type) else 0):
			best = pid
	if best < 0 or Pirates.guard_fleet(state, sid) != null or Pirates.is_port(state, sid):
		return
	var c := Colony.new()
	c.planet_id = best
	c.owner = eid
	c.kind = Colony.KIND_OUTPOST
	state.colonies[best] = c
	state.rebuild_ownership()
	Research.count_stat(state, eid, "pastures")
	added.append(state.add_chronicle("Les Kraal font de %s un pâturage : la Harde y revient chaque saison, et n'aime pas qu'on y touche." % state.galaxy.systems[sid].system_name,
			Espionage.private_to(state, [eid], sid)))


static func _graze_month(state: GameState, eid: int, ed: Dictionary, gz: Dictionary) -> void:
	var g: Dictionary = ed.get("graze", {})
	var mx := _c("pasture_max", 100)
	for k in (ed.get("known", {}) as Dictionary):
		var sid := int(k)
		var v := int(g.get(k, mx))
		if gz.has(sid):
			v -= _c("graze_month", 12) * (gz[sid] as Array).size()
		else:
			v += _c("regrow_month", 5)
		g[k] = clampi(v, 0, mx)
	ed["graze"] = g


## Naissances (prop. 29) : deux Adultes au repos dans un pâturage bien vert, quelques mois de gestation.
static func _births(state: GameState, eid: int, ed: Dictionary, gz: Dictionary, added: Array[Dictionary]) -> void:
	var br: Dictionary = ed.get("breed", {})
	var seen := {}
	var sids := gz.keys()
	sids.sort()
	for sid in sids:
		if graze(state, eid, int(sid)) < _c("birth_min_graze", 25):
			continue
		for f: Fleet in gz[sid]:
			if breeders(f) < 2:
				continue
			var k := str(f.id)
			seen[k] = true
			br[k] = int(br.get(k, 0)) + 1
			if int(br[k]) >= _c("birth_months", 3):
				br[k] = 0
				f.add_ship(String(ages()[0]), -1, Research.mark_gen(state, eid))
				Research.count_stat(state, eid, "births")
				added.append(state.add_chronicle("Un Petit Kraal est né à %s. Il a déjà mordu un astéroïde." % state.galaxy.systems[int(sid)].system_name,
						Espionage.private_to(state, [eid], int(sid))))
	for k in br.keys():
		if not seen.has(k):
			br.erase(k)
	ed["breed"] = br


## Passage d'âge (prop. 29) : chaque mois, un Kraal passe à l'âge suivant une fois sur age_months[âge].
static func _aging(state: GameState, eid: int) -> void:
	var a: Array = ages()
	var months: Array = Insolites.cfg("kraal").get("age_months", [18, 30, 60])
	for f in Fleets.empire_fleets(state, eid):
		var ups: Array[int] = []
		for i in f.ships.size():
			var s := a.find(f.ships[i])
			if s < 0 or s >= a.size() - 1:
				continue
			if posmod(hash([state.seed_value, state.tick, f.id, i, "kraal"]), maxi(1, int(months[s]))) == 0:
				ups.append(i)
		for j in range(ups.size() - 1, -1, -1):
			var i := ups[j]
			var old := f.ships[i]
			var nxt := String(a[a.find(old) + 1])
			@warning_ignore("integer_division")
			var hp := maxi(1, f.hp[i] * Fleet.max_hp_of(nxt) / Fleet.max_hp_of(old))
			var g := f.gen[i]
			f.remove_at(i)
			f.add_ship(nxt, hp, g)


# --- Pilotes (prop. 32) -------------------------------------------------------------------------------

## Colonie ennemie où arracher un Pilote dans le système de la harde (-1 sinon).
static func pilot_source(state: GameState, eid: int, f: Fleet) -> int:
	var best := -1
	for pid in state.galaxy.systems[f.system_id].planet_ids:
		var c: Colony = state.colonies.get(pid)
		if c == null or not c.is_colony() or c.population < _c("pilot_min_pop", 2) or not Combat.at_war(state, eid, c.owner):
			continue
		if best < 0 or c.population > (state.colonies[best] as Colony).population:
			best = pid
	return best


static func check_pilot(state: GameState, eid: int, fid: int) -> String:
	if Insolites.kind(state, eid) != "kraal":
		return "seuls les Kraal lient des Pilotes"
	var f: Fleet = state.fleets.get(fid)
	if f == null or f.owner != eid or kraal_count(f) == 0:
		return "il faut une harde de Kraal"
	if f.is_moving():
		return "la harde doit être à l'arrêt"
	if state.battles.has(f.system_id):
		return "pas pendant une bataille"
	if int((Insolites.emp(state, eid).get("pilots", {}) as Dictionary).get(str(fid), 0)) >= _c("pilot_max", 3):
		return "%d Pilotes au plus par harde" % _c("pilot_max", 3)
	if pilot_source(state, eid, f) < 0:
		return "aucune colonie ennemie assez peuplée dans ce système"
	return ""


static func pilot(state: GameState, eid: int, fid: int, added: Array[Dictionary]) -> void:
	var f: Fleet = state.fleets[fid]
	var pid := pilot_source(state, eid, f)
	var c: Colony = state.colonies[pid]
	c.population -= 1
	var pl: Dictionary = Insolites.emp(state, eid)["pilots"]
	pl[str(fid)] = int(pl.get(str(fid), 0)) + 1
	Research.count_stat(state, eid, "digested")  # la Moisson compte les populations prises
	added.append(state.add_chronicle("Les Kraal arrachent un habitant à %s et le lient à leur harde comme Pilote. Il ne reviendra pas." % state.galaxy.get_planet(pid).display_name(state.galaxy),
			Espionage.public_to(state, [eid, c.owner])))


static func status_lines(state: GameState, eid: int, ed: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var counts := {}
	for f in Fleets.empire_fleets(state, eid):
		for s in f.ships:
			if is_kraal(s):
				counts[s] = int(counts.get(s, 0)) + 1
	var parts := PackedStringArray()
	for s in ages():
		parts.append("%s %d" % [String(GameData.ship(String(s)).get("plural", s)), int(counts.get(s, 0))])
	out.append("La Harde : %s (population %d)" % [", ".join(parts), herd_pop(state, eid)])
	out.append("Pâturages connus : %d" % (ed.get("known", {}) as Dictionary).size())
	var pl := 0
	for k in (ed.get("pilots", {}) as Dictionary):
		pl += int(ed["pilots"][k])
	if pl > 0:
		out.append("Pilotes liés : %d" % pl)
	return out
