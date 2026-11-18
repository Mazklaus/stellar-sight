class_name LivingWorldsWar
extends RefCounted
## Les mondes vivants qui se défendent et qui voyagent (prop. 12-19 ; voir LivingWorlds).
## Défenses vivantes (prop. 12) : à chaque jour de bataille dans son système, le monde frappe de ses
## décharges les flottes des empires qu'il trouve Méfiants ou Hostiles, s'ils combattent l'empire qu'il
## préfère (ou s'il n'en préfère aucun). Anticorps (prop. 13) : un empire Hostile qui entre dans son
## système ou l'assiège voit naître un troupeau de faune qui ne chasse que lui. Sol hostile (prop. 14),
## refuge (prop. 15), fuite (prop. 18), invitation (prop. 19).


static func _w() -> Dictionary:
	return LivingWorlds.cfg("war")


static func w_int(key: String, def := 0) -> int:
	return int(_w().get(key, def))


# --- Défenses vivantes (prop. 12) --------------------------------------------------------------

## L'empire que le monde préfère parmi ceux qui combattent (humeur >= 0), -1 sinon.
static func favored(state: GameState, pid: int, owners: Array) -> int:
	var best := -1
	var best_m := -1
	for o in owners:
		var m := LivingWorlds.mood(state, pid, int(o))
		if m > best_m or (m == best_m and int(o) < best):
			best_m = m
			best = int(o)
	return best


## Appelé par CombatSystem après chaque jour de bataille.
static func battle_day(state: GameState, sid: int, fighters: Array, added: Array[Dictionary]) -> void:
	if state.living.is_empty():
		return
	for pid in LivingWorlds.in_system(state, sid):
		_strike(state, pid, sid, fighters, added)


static func _strike(state: GameState, pid: int, sid: int, fighters: Array, added: Array[Dictionary]) -> void:
	var owners := []
	for f: Fleet in fighters:
		if not GameState.is_npc(f.owner) and not owners.has(f.owner):
			owners.append(f.owner)
	var ego := int(LivingWorlds.world(state, pid).get("ego", 0)) == 1
	var fav := -1 if ego else favored(state, pid, owners)
	var targets: Array = []
	for f: Fleet in fighters:
		if GameState.is_npc(f.owner) or f.owner == fav:
			continue
		if not ego and not LivingWorlds.dislikes(state, pid, f.owner):
			continue
		if fav >= 0 and not Combat.hostile_fleets(state, f, _any_of(fighters, fav)):
			continue
		for i in f.ships.size():
			targets.append([f, i])
	if targets.is_empty():
		return
	var od := LivingWorlds.origin_def(String(LivingWorlds.world(state, pid)["o"]))
	var power := int(LivingWorlds.cfg("ego").get("strike", 90)) if ego else int(od.get("strike", 40))
	var weapon := String(_w().get("strike_weapon", "decharge"))
	for n in w_int("strike_shots", 3):
		var pick: Array = targets[state.rng.randi_range(0, targets.size() - 1)]
		var tg: Fleet = pick[0]
		var ti := int(pick[1])
		if ti >= tg.ships.size():
			continue
		var dmg := Combat.shot_damage(weapon, power, 1, Combat.default_tactic(), 100, tg.ships[ti], Combat.fleet_tactic(tg), 0,
				Combat.defense_bonus(state, tg.owner, Combat.ship_marks(state, tg, ti)))
		var tp := LivingWorlds.t_int(state, tg.owner, "strike_taken_pct")
		if tp != 0:
			@warning_ignore("integer_division")
			dmg = maxi(1, dmg * (100 + tp) / 100)
		tg.hp[ti] -= dmg
	for pair in targets:
		var f: Fleet = pair[0]
		for i in range(f.ships.size() - 1, -1, -1):
			if f.hp[i] <= 0:
				f.remove_at(i)
		if f.ships.is_empty() and state.fleets.has(f.id):
			state.fleets.erase(f.id)
	LivingWorlds._stat(state, fav, "strikes_for", 1)


static func _any_of(fighters: Array, owner: int) -> Fleet:
	for f: Fleet in fighters:
		if f.owner == owner:
			return f
	return null


# --- Chaque mois : anticorps, fuite (prop. 13, 18) ---------------------------------------------

static func monthly(state: GameState, pid: int, added: Array[Dictionary]) -> void:
	var w := LivingWorlds.world(state, pid)
	var sid := LivingWorlds.sys_of(state, pid)
	_antibodies(state, pid, w, sid, added)
	_flee(state, pid, w, sid, added)


static func _antibodies(state: GameState, pid: int, w: Dictionary, sid: int, added: Array[Dictionary]) -> void:
	if state.tick < int(w.get("ab", 0)):
		return
	var ego := int(w.get("ego", 0)) == 1
	var target := -1
	var besieger := int((state.sieges.get(sid, {}) as Dictionary).get("by", -1)) if state.sieges.has(sid) else -1
	if besieger >= 0 and (ego or LivingWorlds.hates(state, pid, besieger)):
		target = besieger
	if target < 0:
		for f in Fleets.fleets_at(state, sid):
			if GameState.is_npc(f.owner) or f.is_moving() or not Combat.is_armed(f):
				continue
			if ego or LivingWorlds.hates(state, pid, f.owner):
				target = f.owner
				break
	if target < 0 or LivingWorlds.t_bool(state, target, "no_antibody"):
		return
	var sp := String(LivingWorlds.cfg("ego").get("antibody", "betes_songe")) if ego else String(LivingWorlds.origin_def(String(w["o"])).get("antibody", "rongeroc"))
	if Fauna.species(sp).is_empty():
		return
	w["ab"] = state.tick + w_int("antibody_cd", 180)
	for i in w_int("antibody_herds", 1):
		var f := Fauna.spawn_herd(state, sp, sid, -1, state.tick + w_int("antibody_days", 120))
		Fauna.herds(state)[f.id]["lw"] = -1 if ego else target
		f.fleet_name = "Anticorps de %s" % LivingWorlds.name_of(state, pid)
	LivingWorlds.harden(state, pid, target)
	LivingWorlds._stat(state, target, "antibodies", 1)
	var who := [target]
	var h := LivingWorlds.host(state, pid)
	if h >= 0 and h != target:
		who.append(h)
	added.append(state.add_chronicle("%s se défend : des %s jaillissent du sol de %s et ne chassent que les vaisseaux de %s." % [
			LivingWorlds.name_of(state, pid), String(Fauna.species(sp).get("label", sp)).to_lower(), state.galaxy.systems[sid].system_name,
			state.get_empire(target).short_name() if not ego else "tout le monde"], Espionage.private_to(state, who, sid)))


## Fauna.hostile : un troupeau d'anticorps ne chasse que l'empire visé (-1 : tous, Monde-Ego).
static func antibody_hostile(h: Dictionary, empire_id: int) -> Variant:
	if not h.has("lw"):
		return null
	var t := int(h["lw"])
	return t < 0 or t == empire_id


## Prop. 18 : assiégé par un Hostile, le monde saute ailleurs avec la colonie d'un hôte qu'il aime.
static func _flee(state: GameState, pid: int, w: Dictionary, sid: int, added: Array[Dictionary]) -> void:
	if not state.sieges.has(sid) or state.tick < int(w.get("jump", 0)) or int(w.get("ego", 0)) == 1:
		return
	var besieger := int((state.sieges[sid] as Dictionary).get("by", -1))
	var h := LivingWorlds.host(state, pid)
	if besieger < 0 or h < 0 or not LivingWorlds.hates(state, pid, besieger) or not LivingWorlds.loves(state, pid, h):
		return
	var to := _refuge_system(state, h, sid)
	if to < 0:
		return
	w["jump"] = state.tick + int(LivingWorlds.origin_def(String(w["o"])).get("leave_cd", 3600))
	var nm := LivingWorlds.name_of(state, pid)
	LivingWorlds.move_planet(state, pid, to)
	LivingWorlds._stat(state, h, "flights", 1)
	Announce.next(state, "living_leave", {"actor": h, "target": besieger, "system": sid})
	added.append(state.add_chronicle("%s n'attend pas la fin du siège : il bondit hors de son orbite avec la colonie de %s et reparaît à %s. Les assiégeants de %s restent bouche bée devant le vide." % [
			nm, state.get_empire(h).short_name(), state.galaxy.systems[to].system_name, state.get_empire(besieger).short_name()]))


## Un système de l'hôte (ou libre) à flee_range sauts au plus, sans siège, le plus proche.
static func _refuge_system(state: GameState, h: int, from: int) -> int:
	var dist := FactionTraits.jumps_from(state.galaxy, from)
	var best := -1
	var best_s := 999999
	var keys := dist.keys()
	keys.sort()
	for k in keys:
		var sid := int(k)
		var dj := int(dist[k])
		if sid == from or dj > w_int("flee_range", 5) or state.sieges.has(sid) or state.lairs.has(sid):
			continue
		var so := state.system_owner(sid)
		if so != h and so >= 0:
			continue
		if state.galaxy.systems[sid].planet_ids.size() >= 8:
			continue
		var score := dj * 10 + (0 if so == h else 5)
		if score < best_s:
			best_s = score
			best = sid
	return best


# --- Sol hostile, refuge (prop. 14, 15) --------------------------------------------------------

## Bonus de dégâts au sol (Ground._damage) dans le système d'un monde vivant.
static func ground_pct(state: GameState, sid: int, eid: int) -> int:
	if state.living.is_empty():
		return 0
	var n := 0
	for pid in LivingWorlds.in_system(state, sid):
		if LivingWorlds.dislikes(state, pid, eid):
			n -= w_int("ground_pct", 25)
		elif LivingWorlds.loves(state, pid, eid):
			n += w_int("ground_pct", 25)
	return n


## Prop. 15 : une flotte d'un empire Bienveillant ou Lié se répare entièrement en orbite (Mogo).
static func refuge(state: GameState, f: Fleet) -> bool:
	if state.living.is_empty() or f == null or f.is_moving() or GameState.is_npc(f.owner):
		return false
	for pid in LivingWorlds.in_system(state, f.system_id):
		if LivingWorlds.mood(state, pid, f.owner) >= w_int("refuge_min", 25):
			return true
	return false


# --- Invitation (prop. 19) ---------------------------------------------------------------------

static func invite_cost(state: GameState, eid: int) -> Dictionary:
	return Research.scaled_amounts(LivingWorlds.r_dict("invite_cost"), LivingWorlds.t_int(state, eid, "invite_pct"))


static func check_invite(state: GameState, eid: int, pid: int) -> String:
	var w := LivingWorlds.world(state, pid)
	if int(w.get("ego", 0)) == 1:
		return "Ego ne se laisse inviter nulle part"
	if state.colonies.has(pid):
		return "ce monde a déjà des hôtes"
	if LivingWorlds.mood(state, pid, eid) < LivingWorlds.r_int("invite_min", 25):
		return "il faut que ce monde vous soit au moins Bienveillant"
	if state.system_owner(LivingWorlds.sys_of(state, pid)) == eid:
		return "il est déjà chez vous"
	if state.tick < int((w["inv"] as Dictionary).get(str(eid), 0)):
		return "il a déjà décliné une invitation récemment"
	if _invite_target(state, eid, pid) < 0:
		return "aucun de vos systèmes n'a de place pour lui"
	var e := state.get_empire(eid)
	var cost := invite_cost(state, eid)
	if not Economy.can_afford(e, cost):
		return "ressources insuffisantes (il faut %s)" % GameData.format_amounts(cost)
	return ""


static func _invite_target(state: GameState, eid: int, pid: int) -> int:
	var dist := FactionTraits.jumps_from(state.galaxy, LivingWorlds.sys_of(state, pid))
	var best := -1
	var best_d := 999999
	var keys := dist.keys()
	keys.sort()
	for k in keys:
		var sid := int(k)
		if state.system_owner(sid) != eid or state.sieges.has(sid):
			continue
		if state.galaxy.systems[sid].planet_ids.size() >= LivingWorlds.r_int("invite_max_planets", 8):
			continue
		if int(dist[k]) < best_d:
			best_d = int(dist[k])
			best = sid
	return best


static func invite(state: GameState, eid: int, pid: int, added: Array[Dictionary]) -> void:
	var w := LivingWorlds.world(state, pid)
	var to := _invite_target(state, eid, pid)
	if to < 0:
		return
	var e := state.get_empire(eid)
	Economy.pay(e, invite_cost(state, eid))
	(w["inv"] as Dictionary)[str(eid)] = state.tick + LivingWorlds.r_int("invite_cd_days", 1800)
	var from := LivingWorlds.sys_of(state, pid)
	LivingWorlds.move_planet(state, pid, to)
	LivingWorlds.add_mood(state, pid, eid, 5)
	LivingWorlds._stat(state, eid, "invited", 1)
	Announce.next(state, "living_leave", {"actor": eid, "system": to})
	added.append(state.add_chronicle("Invité par %s, %s quitte %s et vient se poser à %s, comme un chat qui choisit son coussin." % [
			e.short_name(), LivingWorlds.name_of(state, pid), state.galaxy.systems[from].system_name, state.galaxy.systems[to].system_name]))


# --- IA (prop. 32) -----------------------------------------------------------------------------

## Le système d'un monde vivant qui aime le défenseur est à éviter, sauf nette supériorité.
static func ai_avoid(state: GameState, sid: int, attacker: int, owner: int) -> bool:
	if state.living.is_empty():
		return false
	for pid in LivingWorlds.in_system(state, sid):
		if LivingWorlds.loves(state, pid, owner) or LivingWorlds.dislikes(state, pid, attacker):
			return true
	return false
