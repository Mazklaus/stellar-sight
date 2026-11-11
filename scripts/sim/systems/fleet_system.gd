class_name FleetSystem
extends RefCounted
## Flottes, exécutées à chaque tick, dans un ordre fixe :
## 1. chantiers spatiaux : les vaisseaux terminés sortent en orbite, chacun dans sa propre flotte ;
## 2. déplacements : chaque flotte avance de sa vitesse le long de son trajet ; une flotte qui entre
##    dans un système tenu par une flotte armée d'un empire en guerre avec elle s'y arrête (blocus) ;
## 3. exploration : chaque empire découvre ce que voient ses revendications et ses flottes,
##    et rencontre les empires qu'il aperçoit (premier contact) ;
## 4. exploration automatique : les flottes qui en ont l'ordre repartent vers la frontière.
## Aucun aléatoire, uniquement des entiers, tout est parcouru dans l'ordre des identifiants.


static func process(state: GameState) -> Array[Dictionary]:
	var added: Array[Dictionary] = []
	for pid in state.sorted_colony_ids():
		_process_shipyard(state, state.colonies[pid], added)
	for fid in state.sorted_fleet_ids():
		_move(state, state.fleets[fid])
	for fid in state.sorted_fleet_ids():
		var entry := _refit_step(state, state.fleets[fid])
		if not entry.is_empty():
			added.append(entry)
	added.append_array(update_exploration(state))
	for fid in state.sorted_fleet_ids():
		var f: Fleet = state.fleets[fid]
		if f.is_exploring():
			var entry := explore_step(state, f)
			if not entry.is_empty():
				added.append(entry)
	return added


## Remise à niveau au chantier : un jour de plus à quai. Partir ou se battre l'interrompt (le prix
## payé est perdu) ; au bout du compte, tous les vaisseaux prennent les marques actuelles de l'empire.
static func _refit_step(state: GameState, f: Fleet) -> Dictionary:
	if f.refit_left <= 0:
		return {}
	if f.is_moving() or state.battles.has(f.system_id) or not Fleets.has_own_yard(state, f.owner, f.system_id):
		f.refit_left = 0
		return {}
	f.refit_left -= 1
	if f.refit_left > 0:
		return {}
	var g := Research.mark_gen(state, f.owner)
	for i in f.gen.size():
		f.gen[i] = g
	if state.get_empire(f.owner).is_ai():
		return {}
	return state.add_chronicle("%s sort du chantier de %s avec les dernières marques d'armes. L'équipage trouve que ça sent le neuf, et la facture." % [
			f.fleet_name, state.galaxy.systems[f.system_id].system_name], Espionage.private_to(state, [f.owner], f.system_id))


## Une flotte en exploration automatique choisit sa prochaine cible : à l'arrêt, ou dès que sa
## destination a été explorée en chemin (un éclaireur voit à deux sauts, il n'a pas besoin d'y aller).
## Quand il ne reste rien à explorer, l'ordre s'arrête et la chronique le signale.
static func explore_step(state: GameState, f: Fleet) -> Dictionary:
	if f.is_moving() and not Fleets.is_explored(state, f.owner, f.destination()):
		return {}
	var target := Fleets.explore_target(state, f)
	var plan := Fleets.plan_route(state, f, target) if target >= 0 else {}
	if plan.is_empty():
		f.standing_order = ""
		var e := state.get_empire(f.owner)
		return state.add_chronicle("%s : le %s a cartographié tout ce que ses routes connues permettaient d'atteindre. L'équipage attend de nouveaux ordres, et des vacances." % [
				e.short_name(), f.fleet_name], Espionage.private_to(state, [f.owner], f.system_id))
	f.system_id = int(plan["system"])
	f.path.assign(plan["path"])
	f.progress = int(plan["progress"])
	return {}


static func _process_shipyard(state: GameState, c: Colony, added: Array[Dictionary]) -> void:
	if c.ship_build == "":
		return
	var e := state.get_empire(c.owner)
	if e.blackout:
		return
	var p := state.galaxy.get_planet(c.planet_id)
	if Combat.is_besieged(state, p.system_id):
		return  # chantiers spatiaux bloqués pendant le siège
	c.ship_days -= 1
	if c.ship_days > 0:
		return
	var f := state.spawn_ship(c.owner, c.ship_build, p.system_id)
	Research.count_stat(state, c.owner, "built")
	c.ship_build = ""
	c.ship_days = 0
	var launch := String(GameData.ship(f.ships[0]).get("launch", ""))
	if launch != "":
		added.append(state.add_chronicle(launch % [e.display_name(), p.display_name(state.galaxy)], Espionage.private_to(state, [e.id], p.system_id)))
	else:
		added.append(state.add_chronicle("%s : le %s sort des chantiers de %s. On a cassé une bouteille sur la coque, et un peu la coque." % [
				e.short_name(), f.fleet_name, p.display_name(state.galaxy)], Espionage.private_to(state, [e.id], p.system_id)))


static func _move(state: GameState, f: Fleet) -> void:
	if not f.is_moving():
		return
	f.progress += Fleets.speed(f, state)
	while f.is_moving():
		var lane := Fleets.lane_length(state.galaxy, f.system_id, f.path[0])
		if f.progress < lane:
			return
		f.progress -= lane
		f.system_id = f.path.pop_front()
		if f.is_moving() and Combat.blocks(state, f.owner, f.system_id, f):
			f.path.clear()  # blocus : impossible de passer sans livrer bataille
	f.progress = 0  # arrivée : le reste du trajet du jour est perdu


## Met à jour les systèmes explorés et les contacts de chaque empire.
## Appelée à chaque tick, et à la création d'une partie. Renvoie les entrées de chronique.
static func update_exploration(state: GameState) -> Array[Dictionary]:
	var added: Array[Dictionary] = []
	var seen_by := Fleets.visible_all(state)
	state.seen_cache = seen_by.duplicate()
	state.seen_tick = state.tick
	for e in state.empires:
		var seen: Dictionary = seen_by[e.id]
		for sid in seen:
			e.explored[sid] = true
	Intel.record(state, seen_by)
	for e in state.empires:
		var seen: Dictionary = seen_by[e.id]
		for other in state.empires:
			if other.id == e.id or e.contacts.has(other.id):
				continue
			if _sees_empire(state, seen, other.id):
				_meet(state, e, other, added)
	return added


## L'empire voit-il un système revendiqué ou une flotte de l'empire other_id ?
static func _sees_empire(state: GameState, seen: Dictionary, other_id: int) -> bool:
	for sid in seen:
		if state.system_owner(sid) == other_id:
			return true
	# (on cherche s'il en existe une : l'ordre de parcours ne change pas la réponse)
	for f: Fleet in state.fleets.values():
		if f.owner == other_id and seen.has(Fleets.vision_center(state, f)):
			return true
	return false


## Premier contact, dans les deux sens (les deux empires se voient au même moment ou presque :
## on retient la rencontre pour les deux, une seule entrée de chronique).
static func _meet(state: GameState, a: Empire, b: Empire, added: Array[Dictionary]) -> void:
	a.contacts.append(b.id)
	a.contacts.sort()
	if not b.contacts.has(a.id):
		b.contacts.append(a.id)
		b.contacts.sort()
	added.append(state.add_chronicle("Premier contact entre %s et %s. Chacun trouve l'autre étrange, et se garde bien de le dire." % [
			a.display_name(), b.display_name()], Espionage.public_to(state, [a.id, b.id])))
	# L'Essaim Kh'thari ne négocie pas : s'il n'a pas de proie, la rencontre vaut déclaration de guerre.
	# Il ne chasse qu'une proie à la fois ; les autres attendront leur tour (voir CombatSystem._hunger).
	for pair in [[a, b], [b, a]]:
		var swarm: Empire = pair[0]
		var prey: Empire = pair[1]
		if Combat.hunts(state, swarm.id) and not swarm.wars.has(prey.id) and not Combat.has_live_war(state, swarm.id):
			added.append(Combat.start_war(state, swarm.id, prey.id, true))
			break
