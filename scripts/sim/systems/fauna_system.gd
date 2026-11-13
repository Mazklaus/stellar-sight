class_name FaunaSystem
extends RefCounted
## Faune (voir Fauna), exécutée à chaque tick après les pirates, dans l'ordre des identifiants :
## 1. troupeaux : un troupeau disparu (abattu) est rayé et son nid note la perte ; un troupeau dérangé
##    se disperse à la fin de son délai ; à l'arrêt et hors bataille, un prédateur fond sur un vaisseau
##    sans armes arrêté dans un système libre voisin, et chacun migre à son heure autour de son nid ;
## 2. premier contact : un empire qui voit un troupeau rencontre son espèce ;
## 3. nids : un nid sans troupeau tenu par une flotte armée hostile est détruit ; sinon, il fait renaître
##    un troupeau quand le délai de repeuplement est passé, que personne ne l'en empêche et que le
##    système n'a pas été revendiqué (un nid colonisé dort) ;
## 4. gardiens (Guardians.daily) : riposte, étoile rongée, réveils, visites de l'Horloger ;
##    fléaux errants (Plagues.daily) : naissance à leur date, d'une colonie à l'autre, départ au bout d'un an ;
##    filets gravitationnels (WarBeasts.daily) : captures pour le Vivarium ;
## 5. études : celles qui arrivent à terme donnent leur bonus.
## Aucun aléatoire : les choix de destination suivent un hachage de la graine, du troupeau et du jour.


static func process(state: GameState) -> Array[Dictionary]:
	var added: Array[Dictionary] = []
	if state.fauna.is_empty():
		return added
	if not Fauna.active(state) and (state.fauna.get("meta", {}) as Dictionary).is_empty():
		return added
	for fid in Fauna.herd_ids(state):
		_herd(state, fid, added)
	_contacts(state, added)
	for sid in Fauna.nest_ids(state):
		_nest(state, sid, added)
	Guardians.daily(state, added)
	Plagues.daily(state, added)
	WarBeasts.daily(state, added)
	_studies(state, added)
	return added


static func _herd(state: GameState, fid: int, added: Array[Dictionary]) -> void:
	var h: Dictionary = Fauna.herds(state)[fid]
	var f: Fleet = state.fleets.get(fid)
	var nest := int(h["nest"])
	if f == null:
		Fauna.herds(state).erase(fid)
		if Fauna.nests(state).has(nest):
			Fauna.nests(state)[nest]["lost"] = state.tick
		return
	if f.is_moving() or state.battles.has(f.system_id):
		return
	# Troupeau attiré par un Appât (Plagues.bait) : il se sert à destination, puis rentre.
	if int(h.get("bait", -1)) >= 0:
		if f.system_id == int(h["bait"]):
			Plagues.herd_bait_arrived(state, fid, added)
		elif not _go(state, f, int(h["bait"])):
			h["bait"] = -1
		return
	if int(h["until"]) > 0:
		if state.tick >= int(h["until"]):
			state.fleets.erase(fid)
			Fauna.herds(state).erase(fid)
		return
	var sp := String(h["sp"])
	var d := Fauna.data()
	if Fauna.temper(sp) == "predator" and posmod(state.tick + fid * 3, int(d["prey_every_days"])) == 0:
		var prey := _prey(state, f)
		if prey >= 0 and _go(state, f, prey):
			return
	if state.tick < int(h["next"]) or nest < 0:
		return
	h["next"] = state.tick + int(d["migrate_days"]) + posmod(fid * 53 + state.tick, 60)
	var target := _roam_target(state, f, sp, nest)
	if target >= 0:
		_go(state, f, target)


static func _go(state: GameState, f: Fleet, to: int) -> bool:
	var plan := Fleets.plan_route(state, f, to)
	if plan.is_empty():
		return false
	f.system_id = int(plan["system"])
	f.path.assign(plan["path"])
	f.progress = int(plan["progress"])
	return true


## Système libre voisin où un vaisseau sans armes d'un empire hostile attend à l'arrêt (-1 sinon).
static func _prey(state: GameState, f: Fleet) -> int:
	var ns: Array[int] = state.galaxy.systems[f.system_id].neighbors.duplicate()
	ns.sort()
	for n in ns:
		if state.system_owner(n) >= 0 or _other_species_at(state, n, String(Fauna.herd_of(state, f)["sp"])):
			continue
		for g in Fleets.fleets_at(state, n):
			if not GameState.is_npc(g.owner) and not Combat.is_armed(g) and Fauna.hostile(state, f, g.owner):
				return n
	return -1


## Une flotte d'empire s'y tient (une colonie en chantier, une escadre) : un troupeau qui migre ne
## s'y installe pas ; seuls les prédateurs vont chercher les vaisseaux.
static func _occupied(state: GameState, sid: int) -> bool:
	for g in Fleets.fleets_at(state, sid):
		if not GameState.is_npc(g.owner):
			return true
	return false


static func _other_species_at(state: GameState, sid: int, sp: String) -> bool:
	for g in Fleets.fleets_at(state, sid, GameState.FAUNA_ID):
		var h := Fauna.herd_of(state, g)
		if h.is_empty() or String(h["sp"]) != sp:
			return true
	return false


## Prochaine étape d'une migration : un système à roam_jumps sauts au plus du nid, jamais revendiqué,
## sans repaire, ni troupeau d'une autre espèce, ni flotte d'empire, différent de l'actuel ; choix par
## hachage. -1 si aucun.
static func _roam_target(state: GameState, f: Fleet, sp: String, nest: int) -> int:
	var jumps := FactionTraits.jumps_from(state.galaxy, nest)
	var roam := int(Fauna.data()["roam_jumps"])
	var cands: Array[int] = []
	for k in jumps:
		var sid := int(k)
		if int(jumps[k]) > roam or sid == f.system_id or state.system_owner(sid) >= 0 or state.lairs.has(sid):
			continue
		if _other_species_at(state, sid, sp) or _occupied(state, sid):
			continue
		cands.append(sid)
	if cands.is_empty():
		return -1
	cands.sort()
	return cands[posmod(hash([state.seed_value, "migre", f.id, state.tick]), cands.size())]


static func _contacts(state: GameState, added: Array[Dictionary]) -> void:
	if state.seen_tick != state.tick or state.seen_cache.size() < state.empires.size():
		return
	for fid in Fauna.herd_ids(state):
		var f: Fleet = state.fleets.get(fid)
		if f == null:
			continue
		var sp := String(Fauna.herds(state)[fid]["sp"])
		var at := Fleets.vision_center(state, f)
		for e in state.empires:
			if e.eliminated or Fauna.knows(state, e.id, sp):
				continue
			if (state.seen_cache[e.id] as Dictionary).has(at):
				Fauna.see(state, e.id, sp, at, added)


static func _nest(state: GameState, sid: int, added: Array[Dictionary]) -> void:
	var n: Dictionary = Fauna.nests(state)[sid]
	var sp := String(n["sp"])
	if state.battles.has(sid):
		return
	var alive := Fauna.nest_herds(state, sid).size()
	var holder := _hostile_holder(state, sid, sp)
	if alive == 0 and holder >= 0:
		Fauna.destroy_nest(state, sid, holder, added)
		return
	if alive < int(state.fauna.get("per_nest", 0)) and holder < 0 and state.system_owner(sid) < 0 \
			and state.tick - int(n["lost"]) >= int(Fauna.data()["respawn_days"]):
		Fauna.spawn_herd(state, sp, sid, sid)
		n["lost"] = state.tick


## Empire (le plus petit identifiant) dont une flotte armée tient le nid et à qui l'espèce est hostile.
static func _hostile_holder(state: GameState, sid: int, sp: String) -> int:
	var best := -1
	for f in Fleets.fleets_at(state, sid):
		if GameState.is_npc(f.owner) or not Combat.is_armed(f) or not Fauna.species_hostile(state, f.owner, sp):
			continue
		if best < 0 or f.owner < best:
			best = f.owner
	return best


static func _studies(state: GameState, added: Array[Dictionary]) -> void:
	var meta: Dictionary = state.fauna.get("meta", {})
	if meta.is_empty():
		return
	var eids := meta.keys()
	eids.sort()
	for eid in eids:
		var study: Dictionary = meta[eid]["study"]
		for sp in Fauna.species_ids():
			var end := int(study.get(sp, 0))
			if end <= 0 or state.tick < end:
				continue
			study[sp] = -1
			state.relic_rev += 1
			var e := state.get_empire(int(eid))
			if e != null and not e.is_ai():
				var sd := Fauna.species(sp)
				added.append(state.add_chronicle("L'étude des %s est terminée. %s Leur faiblesse : %s" % [
						String(sd["label"]), String(sd.get("study_text", "")), String(sd["weakness"]).to_lower()], Espionage.private_to(state, [int(eid)])))
