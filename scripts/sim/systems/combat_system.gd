class_name CombatSystem
extends RefCounted
## Combats, sièges et réparations, exécutés à chaque tick après les déplacements, dans un ordre fixe :
## 1. batailles : dans chaque système où se trouvent à l'arrêt des flottes d'empires en guerre
##    (dont au moins une armée), un jour de bataille. Une bataille dure 6 jours : 2 à longue portée,
##    2 à moyenne, 2 à courte, puis un rapport ; si les deux camps sont encore là, une autre commence ;
## 2. sièges : un système ennemi sans flotte armée pour le défendre est assiégé par les flottes armées
##    qui y stationnent ; sa garnison fond, ses bastions tirent, sa production est réduite ;
## 3. réparations et troupes : les flottes hors combat se réparent (vite chez elles, lentement ailleurs)
##    et refont leurs troupes dans leurs propres systèmes ;
## 4. empires disparus : un empire sans revendication disparaît, et ses flottes avec lui.
##
## Les tirs sont simultanés (les dégâts d'un jour s'appliquent ensemble). Les cibles sont tirées par
## state.rng, dans l'ordre des identifiants : la même partie sur toutes les machines.
## Une flotte peut quitter une bataille : l'ordre s'applique avant les déplacements du jour suivant,
## elle est partie avant que la bataille reprenne (pas de contrôle pendant la bataille elle-même,
## comme dans Endless Space 2).


## events reçoit les événements pour l'interface : {"type": "battle_started", "system", "empires", "renewed"},
## {"type": "battle_ended", "report"}, {"type": "siege_started", "system", "by", "owner"}.
static func process(state: GameState, events: Array = []) -> Array[Dictionary]:
	var added: Array[Dictionary] = []
	var by_sys := _stationary_by_system(state)
	var fought := {}
	var sids := by_sys.keys()
	sids.sort()
	for sid in sids:
		if _in_conflict(state, by_sys[sid]):
			fought[sid] = true
			_battle_day(state, int(sid), by_sys[sid], added, events)
	# Batailles terminées faute de combattants (fuite, destruction, flotte partie).
	var bids := state.battles.keys()
	bids.sort()
	for sid in bids:
		if not fought.has(sid):
			_end_battle(state, int(sid), added, events)
	_sieges(state, fought, added, events)
	_repairs(state, fought)
	_eliminations(state, added)
	return added


static func _stationary_by_system(state: GameState) -> Dictionary:
	var out := {}
	for fid in state.sorted_fleet_ids():
		var f: Fleet = state.fleets[fid]
		if f.is_moving():
			continue
		if not out.has(f.system_id):
			out[f.system_id] = []
		out[f.system_id].append(f)
	return out


## Deux flottes d'empires en guerre, dont au moins une armée.
static func _in_conflict(state: GameState, fleets: Array) -> bool:
	for a: Fleet in fleets:
		if not Combat.is_armed(a):
			continue
		for b: Fleet in fleets:
			if Combat.at_war(state, a.owner, b.owner):
				return true
	return false


# --- Batailles ---------------------------------------------------------------------------------

static func _new_battle(state: GameState, sid: int) -> Dictionary:
	var b := {"id": state.next_battle_id, "system": sid, "start": state.tick, "day": 0,
			"fleets": [], "sides": []}
	state.next_battle_id += 1
	state.battles[sid] = b
	return b


static func _side(b: Dictionary, empire_id: int) -> Dictionary:
	for s: Dictionary in b["sides"]:
		if int(s["empire"]) == empire_id:
			return s
	var s := {"empire": empire_id, "engaged": {}, "lost": {}, "dealt": 0}
	b["sides"].append(s)
	b["sides"].sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return int(x["empire"]) < int(y["empire"]))
	return s


## Jour d'arrivée d'une flotte dans la bataille (0 si elle n'y est pas encore).
static func _joined_day(b: Dictionary, fid: int) -> int:
	for e: Array in b["fleets"]:
		if int(e[0]) == fid:
			return int(e[1])
	return 0


static func _battle_day(state: GameState, sid: int, fleets: Array, added: Array[Dictionary], events: Array) -> void:
	var b: Dictionary = state.battles.get(sid, {})
	var fresh := b.is_empty()
	if fresh:
		b = _new_battle(state, sid)
	b["day"] = int(b["day"]) + 1
	var day := int(b["day"])
	var phase := Combat.phase_index(day)
	# Combattants : les flottes dont l'empire est en guerre avec un autre présent.
	var fighters: Array[Fleet] = []
	for f: Fleet in fleets:
		for g: Fleet in fleets:
			if Combat.at_war(state, f.owner, g.owner):
				fighters.append(f)
				break
	for f in fighters:
		if _joined_day(b, f.id) == 0:
			b["fleets"].append([f.id, day])
			var side := _side(b, f.owner)
			for s in f.ships:
				side["engaged"][s] = int(side["engaged"].get(s, 0)) + 1
	if fresh:
		var names := PackedStringArray()
		var ids: Array[int] = []
		for s: Dictionary in b["sides"]:
			ids.append(int(s["empire"]))
			names.append(state.get_empire(int(s["empire"])).display_name())
		# Une bataille qui reprend aussitôt après la précédente (les deux camps sont restés) n'est pas annoncée.
		var renewed := false
		for r: Dictionary in state.battle_reports:
			if int(r["system"]) == sid and int(r["end"]) >= state.tick - 1:
				renewed = true
		if not renewed:
			added.append(state.add_chronicle("Bataille à %s : %s ouvrent le feu. Les chroniqueurs taillent leurs crayons." % [
					state.galaxy.systems[sid].system_name, " et ".join(names)]))
		events.append({"type": "battle_started", "system": sid, "empires": ids, "renewed": renewed})
	# Cibles possibles de chaque empire : tous les vaisseaux ennemis présents, dans l'ordre.
	var targets := {}
	for f in fighters:
		if targets.has(f.owner):
			continue
		var list: Array = []
		for g in fighters:
			if Combat.at_war(state, f.owner, g.owner):
				for i in g.ships.size():
					list.append([g, i])
		targets[f.owner] = list
	# Tirs simultanés : on cumule, puis on applique.
	var pending := {}
	for f in fighters:
		var list: Array = targets[f.owner]
		if list.is_empty():
			continue
		var tac := Combat.fleet_tactic(f)
		var bonus := _damage_bonus(state, b, f, sid)
		var side := _side(b, f.owner)
		for i in f.ships.size():
			var w := Combat.weapons(f.ships[i])
			var keys := w.keys()
			keys.sort()
			for k in keys:
				var pick: Array = list[state.rng.randi_range(0, list.size() - 1)]
				var tg: Fleet = pick[0]
				var ti: int = pick[1]
				var dmg := Combat.shot_damage(String(k), int(w[k]), phase, tac, bonus, tg.ships[ti], Combat.fleet_tactic(tg))
				var key := Vector2i(tg.id, ti)
				pending[key] = int(pending.get(key, 0)) + dmg
				side["dealt"] = int(side["dealt"]) + dmg
	_apply_damage(state, b, fighters, pending)
	if day >= Combat.battle_days():
		_end_battle(state, sid, added, events)


## Bonus de dégâts des traits de peuple (en %) : Ossarane chez elle, Vael arrivée en renfort.
static func _damage_bonus(state: GameState, b: Dictionary, f: Fleet, sid: int) -> int:
	var pct := 100
	if state.system_owner(sid) == f.owner:
		@warning_ignore("integer_division")
		pct = pct * int(Combat.trait_value(state, f.owner, "home_damage_pct", 100)) / 100
	if _joined_day(b, f.id) > 1:
		@warning_ignore("integer_division")
		pct = pct * int(Combat.trait_value(state, f.owner, "reinforcement_pct", 100)) / 100
	return pct


static func _apply_damage(state: GameState, b: Dictionary, fighters: Array[Fleet], pending: Dictionary) -> void:
	for f in fighters:
		var lost_any := false
		for i in range(f.ships.size() - 1, -1, -1):
			var dmg := int(pending.get(Vector2i(f.id, i), 0))
			if dmg <= 0:
				continue
			f.hp[i] -= dmg
			if f.hp[i] <= 0:
				var side := _side(b, f.owner)
				side["lost"][f.ships[i]] = int(side["lost"].get(f.ships[i], 0)) + 1
				_credit_kill(state, b, f.owner)
				f.remove_at(i)
				lost_any = true
		if lost_any:
			f.troops = mini(f.troops, Combat.max_troops(f))
		if f.ships.is_empty():
			state.fleets.erase(f.id)


## Croisade du Chœur : chaque vaisseau détruit nourrit le dieu-machine des empires qui le combattaient.
static func _credit_kill(state: GameState, b: Dictionary, victim: int) -> void:
	for s: Dictionary in b["sides"]:
		var eid := int(s["empire"])
		var gain := int(Combat.trait_value(state, eid, "fervor_per_kill", 0))
		if gain > 0 and Combat.at_war(state, eid, victim):
			var e := state.get_empire(eid)
			e.fervor = mini(int(e.faction()["fervor"]["max"]), e.fervor + gain)


## Fin d'une bataille : rapport, chronicle, événement. Le vainqueur est le seul camp encore présent.
static func _end_battle(state: GameState, sid: int, added: Array[Dictionary], events: Array) -> void:
	var b: Dictionary = state.battles.get(sid, {})
	if b.is_empty():
		return
	state.battles.erase(sid)
	var present := {}
	for f in Fleets.fleets_at(state, sid):
		present[f.owner] = true
	var standing: Array[int] = []
	for s: Dictionary in b["sides"]:
		if present.has(int(s["empire"])):
			standing.append(int(s["empire"]))
	var winner := standing[0] if standing.size() == 1 else -1
	var report := b.duplicate(true)
	report["end"] = state.tick
	report["winner"] = winner
	report["system_name"] = state.galaxy.systems[sid].system_name
	state.battle_reports.append(report)
	var keep := int(Combat.data().get("reports_max", 12))
	while state.battle_reports.size() > keep:
		state.battle_reports.pop_front()
	var losses := PackedStringArray()
	for s: Dictionary in b["sides"]:
		losses.append("%s %d" % [state.get_empire(int(s["empire"])).short_name(), Combat.count_ships(s["lost"])])
	var sname := state.galaxy.systems[sid].system_name
	if winner >= 0:
		added.append(state.add_chronicle("Bataille de %s : victoire de %s. Pertes : %s. Les vainqueurs comptent leurs morts, les vaincus leurs excuses." % [
				sname, state.get_empire(winner).display_name(), ", ".join(losses)]))
	else:
		added.append(state.add_chronicle("Bataille de %s : rien n'est décidé après %d jours de feu. Pertes : %s." % [
				sname, int(b["day"]), ", ".join(losses)]))
	events.append({"type": "battle_ended", "report": report})


# --- Sièges ------------------------------------------------------------------------------------

static func _sieges(state: GameState, fought: Dictionary, added: Array[Dictionary], events: Array) -> void:
	var gcfg: Dictionary = Combat.data()["garrison"]
	# Systèmes à examiner : ceux qui ont une garnison entamée, un siège en cours, ou des flottes.
	var check := {}
	for k in state.garrisons:
		check[k] = true
	for k in state.sieges:
		check[k] = true
	for fid in state.sorted_fleet_ids():
		var f: Fleet = state.fleets[fid]
		if not f.is_moving():
			check[f.system_id] = true
	var ids := check.keys()
	ids.sort()
	for k in ids:
		var sid := int(k)
		var owner := state.system_owner(sid)
		if owner < 0:
			state.garrisons.erase(sid)
			state.sieges.erase(sid)
			continue
		var by: Array[Fleet] = []
		if not fought.has(sid):
			by = Combat.besiegers(state, sid)
		if by.is_empty():
			if state.sieges.has(sid):
				state.sieges.erase(sid)
				if not fought.has(sid):
					added.append(state.add_chronicle("Le siège de %s est levé. On rouvre les volets, on recompte les provisions." % state.galaxy.systems[sid].system_name))
			if state.garrisons.has(sid):
				var g := int(state.garrisons[sid]) + int(gcfg["regen_per_day"])
				if g >= Combat.garrison_max(state, sid):
					state.garrisons.erase(sid)
				else:
					state.garrisons[sid] = g
			continue
		var lead: Fleet = by[0]
		if not state.sieges.has(sid):
			state.sieges[sid] = {"system": sid, "by": lead.owner, "start": state.tick}
			added.append(state.add_chronicle("%s met le siège devant %s. La garnison serre les dents, la population les rations." % [
					state.get_empire(lead.owner).display_name(), state.galaxy.systems[sid].system_name]))
			events.append({"type": "siege_started", "system": sid, "by": lead.owner, "owner": owner})
		var before := Combat.garrison(state, sid)
		# Les bastions tirent tant que la garnison tient.
		if before > 0:
			_battery_fire(state, sid, by)
		var power := 0
		for f: Fleet in by:
			if state.fleets.has(f.id):
				power += Combat.siege_power(f)
		state.garrisons[sid] = maxi(0, before - power)


## Les batteries des bastions tirent à moyenne portée sur les assiégeants.
static func _battery_fire(state: GameState, sid: int, by: Array[Fleet]) -> void:
	var bat := Combat.battery(state, sid)
	if bat.is_empty():
		return
	var owner := state.system_owner(sid)
	var list: Array = []
	for f: Fleet in by:
		for i in f.ships.size():
			list.append([f, i])
	var pending := {}
	var keys := bat.keys()
	keys.sort()
	for k in keys:
		var pick: Array = list[state.rng.randi_range(0, list.size() - 1)]
		var tg: Fleet = pick[0]
		var dmg := Combat.shot_damage(String(k), int(bat[k]), 1, Combat.default_tactic(),
				int(Combat.trait_value(state, owner, "home_damage_pct", 100)), tg.ships[pick[1]], Combat.fleet_tactic(tg))
		var key := Vector2i(tg.id, int(pick[1]))
		pending[key] = int(pending.get(key, 0)) + dmg
	for f: Fleet in by:
		for i in range(f.ships.size() - 1, -1, -1):
			var dmg := int(pending.get(Vector2i(f.id, i), 0))
			if dmg > 0:
				f.hp[i] -= dmg
				if f.hp[i] <= 0:
					f.remove_at(i)
		f.troops = mini(f.troops, Combat.max_troops(f))
		if f.ships.is_empty():
			state.fleets.erase(f.id)


# --- Réparations et troupes --------------------------------------------------------------------

static func _repairs(state: GameState, fought: Dictionary) -> void:
	var home := int(Combat.data()["repair_pct_home"])
	var away := int(Combat.data()["repair_pct_away"])
	var regen := int(Combat.data()["troops_regen_pct"])
	for fid in state.sorted_fleet_ids():
		var f: Fleet = state.fleets[fid]
		var sid := f.system_id
		if not f.is_moving() and (fought.has(sid) or state.sieges.has(sid) and state.system_owner(sid) != f.owner):
			continue  # en pleine bataille ou en plein siège
		var at_home := not f.is_moving() and state.system_owner(sid) == f.owner
		var pct := home if at_home or bool(Combat.trait_value(state, f.owner, "repair_anywhere", false)) else away
		for i in f.ships.size():
			var mx := Fleet.max_hp_of(f.ships[i])
			if f.hp[i] < mx:
				@warning_ignore("integer_division")
				f.hp[i] = mini(mx, f.hp[i] + maxi(1, mx * pct / 100))
		var tmax := Combat.max_troops(f)
		if at_home and f.troops < tmax:
			@warning_ignore("integer_division")
			f.troops = mini(tmax, f.troops + maxi(1, tmax * regen / 100))


# --- Empires disparus --------------------------------------------------------------------------

static func _eliminations(state: GameState, added: Array[Dictionary]) -> void:
	var alive := {}
	for pid in state.sorted_colony_ids():
		alive[state.colonies[pid].owner] = true
	for e in state.empires:
		if e.eliminated or alive.has(e.id):
			continue
		eliminate(state, e)
		added.append(state.add_chronicle("%s disparaît de la galaxie. Il en reste des épaves, des chansons, et quelques dettes impayées." % e.display_name()))


static func eliminate(state: GameState, e: Empire) -> void:
	e.eliminated = true
	e.capital_planet = -1
	for f in Fleets.empire_fleets(state, e.id):
		state.fleets.erase(f.id)
	for other in state.empires:
		other.wars.erase(e.id)
	e.wars.clear()
