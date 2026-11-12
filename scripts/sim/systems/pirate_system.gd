class_name PirateSystem
extends RefCounted
## Pirates (voir Pirates), exécutés à chaque tick, repaires dans l'ordre de leur système :
## - garde : tombée avec une flotte armée d'un empire sur place, le repaire est démantelé ; sinon elle
##   se reforme au bout de respawn_days ; elle grossit d'un navire tous les grow_every_days ;
## - raid en cours : à l'arrivée il pille puis rentre ; bloqué en chemin, il reprend sa route ;
## - nouveau raid : un contrat en attente part tout de suite, sinon au jour prévu (pas avant l'an 2).
## Aucun aléatoire.


static func process(state: GameState) -> Array[Dictionary]:
	var added: Array[Dictionary] = []
	if state.lairs.is_empty():
		return added
	for sid in Pirates.lair_ids(state):
		_lair(state, sid, added)
	if state.tick % int(GameData.rules()["month_days"]) == 0:
		Pirates.prune_meta(state)
	return added


static func _lair(state: GameState, sid: int, added: Array[Dictionary]) -> void:
	var lair: Dictionary = state.lairs[sid]
	var gd: Dictionary = Pirates.data()["guard"]
	var guard := Pirates.guard_fleet(state, sid)
	if guard == null:
		if int(lair["guard"]) >= 0:
			lair["guard"] = -1
			lair["lost"] = state.tick
		if not state.battles.has(sid):
			var winner := _holder(state, sid)
			if winner >= 0:
				Pirates.dismantle(state, sid, winner, added)
				return
			if state.tick - int(lair["lost"]) >= int(gd["respawn_days"]):
				Pirates.spawn_guard(state, sid)
	elif state.tick > int(lair["born"]) and (state.tick - int(lair["born"])) % int(gd["grow_every_days"]) == 0 \
			and guard.ships.size() < int(gd["max_ships"]) and not state.battles.has(sid):
		var grow: Array = gd["grow_ships"]
		guard.add_ship(String(grow[int(lair.get("grown", 0)) % grow.size()]), -1, 1)
		lair["grown"] = int(lair.get("grown", 0)) + 1
	var raid: Dictionary = lair["raid"]
	if not raid.is_empty():
		_raid_step(state, sid, raid, added)
		return
	if Pirates.guard_fleet(state, sid) == null:
		return
	var con: Dictionary = lair["contract"]
	if not con.is_empty():
		var t := Pirates.pick_target(state, sid, int(con["victim"]), int(Pirates.data()["hire"]["range_jumps"]))
		lair["contract"] = {}
		if t >= 0:
			Pirates.launch_raid(state, sid, t, added, int(con["by"]), int(con["victim"]))
		return
	if state.tick < int(lair["next"]):
		return
	var rd: Dictionary = Pirates.data()["raid"]
	var target := Pirates.pick_target(state, sid)
	if target < 0 or Pirates.launch_raid(state, sid, target, added) == null:
		lair["next"] = state.tick + int(GameData.rules()["month_days"])
	else:
		lair["next"] = state.tick + int(rd["every_days"])


## Empire (le plus petit identifiant) qui tient le système avec une flotte armée, -1 sinon.
static func _holder(state: GameState, sid: int) -> int:
	var best := -1
	for f in Fleets.fleets_at(state, sid):
		if f.is_moving() or GameState.is_npc(f.owner) or not Combat.is_armed(f):
			continue
		if best < 0 or f.owner < best:
			best = f.owner
	return best


static func _raid_step(state: GameState, sid: int, raid: Dictionary, added: Array[Dictionary]) -> void:
	var f: Fleet = state.fleets.get(int(raid["fleet"]))
	if f == null:
		state.lairs[sid]["raid"] = {}  # le raid a été détruit en route
		return
	if f.is_moving() or state.battles.has(f.system_id):
		return
	var back := bool(raid.get("back", false))
	var target := int(raid["target"])
	if not back and f.system_id == target:
		Pirates.plunder(state, sid, target, added)
		raid["back"] = true
		back = true
	if back and f.system_id == sid:
		# De retour au repaire : l'équipage rentre, la flotte se dissout dans la garde.
		state.fleets.erase(f.id)
		state.lairs[sid]["raid"] = {}
		return
	var plan := Fleets.plan_route(state, f, sid if back else target)
	if plan.is_empty():
		state.fleets.erase(f.id)
		state.lairs[sid]["raid"] = {}
		return
	f.system_id = int(plan["system"])
	f.path.assign(plan["path"])
	f.progress = int(plan["progress"])
