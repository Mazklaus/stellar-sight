class_name Musters
extends RefCounted
## Flottes en formation (bêta-test, tâche 3.1) : on crée une flotte dans l'onglet Flottes, même vide,
## puis on y commande des vaisseaux. Chaque commande part au chantier libre le plus proche du point de
## rassemblement ; le vaisseau terminé rejoint sa flotte de lui-même. Une flotte existante se renforce
## de la même façon.
##
## Aussi : un vaisseau armé neuf hors commande rejoint la flotte armée à l'arrêt là où il sort (ou au
## point de ralliement), sauf si l'empire a coupé ce réglage. Empires humains seulement : l'IA range
## ses vaisseaux elle-même.
##
## État (state.musters, {} tant que rien ne sert) :
##   "next" : prochain identifiant ;
##   "m" : formation -> {"o" empire, "n" nom, "s" système de rassemblement, "f" flotte (-1 avant le
##         premier vaisseau), "q" vaisseaux encore à lancer, "y" colonie -> vaisseau en chantier} ;
##   "j" : flotte en route pour rejoindre -> flotte visée (JOIN_ANY : la flotte armée à l'arrêt sur place) ;
##   "off" : empires qui ont coupé le ralliement automatique des vaisseaux neufs.
## Aucun aléatoire, tout est parcouru dans l'ordre des identifiants.

const JOIN_ANY := -2
const QUEUE_MAX := 24
const NAME_MAX := 40


# --- État --------------------------------------------------------------------------------------

static func _root(state: GameState) -> Dictionary:
	if state.musters.is_empty():
		state.musters = {"next": 1, "m": {}, "j": {}, "off": []}
	return state.musters


static func _sub(state: GameState, k: String) -> Dictionary:
	if state.musters.is_empty():
		return {}
	return state.musters.get(k, {})


static func worth_saving(state: GameState) -> bool:
	if state.musters.is_empty():
		return false
	return not (_sub(state, "m").is_empty() and _sub(state, "j").is_empty() and (state.musters.get("off", []) as Array).is_empty())


static func to_dict(state: GameState) -> Dictionary:
	return Ancients._sorted(state.musters)


static func from_dict(state: GameState, d: Dictionary) -> void:
	state.musters = {}
	if d.is_empty():
		return
	state.musters = GameData._to_ints(d.duplicate(true))
	for k in ["m", "j"]:
		if not state.musters.has(k):
			state.musters[k] = {}
	if not state.musters.has("off"):
		state.musters["off"] = []
	if not state.musters.has("next"):
		state.musters["next"] = 1


## Identifiant que recevra la prochaine formation (lecture seule).
static func next_id(state: GameState) -> int:
	return int(state.musters.get("next", 1))


## Formation d'identifiant id ({} si elle n'existe pas).
static func get_rec(state: GameState, id: int) -> Dictionary:
	return _sub(state, "m").get(str(id), {})


## Formations d'un empire, par identifiant : [{id, rec}].
static func of_empire(state: GameState, eid: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var m := _sub(state, "m")
	var ids: Array[int] = []
	for k in m:
		if int(m[k]["o"]) == eid:
			ids.append(int(k))
	ids.sort()
	for id in ids:
		out.append({"id": id, "rec": m[str(id)]})
	return out


## Formation attachée à une flotte existante (renforts), -1 s'il n'y en a pas.
static func for_fleet(state: GameState, fid: int) -> int:
	var m := _sub(state, "m")
	for k in m:
		if int(m[k]["f"]) == fid:
			return int(k)
	return -1


## Flotte que celle-ci part rejoindre (-1 aucune, JOIN_ANY la flotte armée trouvée sur place).
static func joining(state: GameState, fid: int) -> int:
	return int(_sub(state, "j").get(str(fid), -1))


## Un ordre donné à la main reprend la flotte : elle ne rejoint plus personne.
static func forget(state: GameState, fid: int) -> void:
	if not state.musters.is_empty():
		_sub(state, "j").erase(str(fid))


static func auto_join(state: GameState, eid: int) -> bool:
	return state.musters.is_empty() or not (state.musters.get("off", []) as Array).has(eid)


## Vaisseaux en chantier pour une formation.
static func building(rec: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var y: Dictionary = rec.get("y", {})
	var keys := y.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return int(a) < int(b))
	for k in keys:
		out.append(String(y[k]))
	return out


## Où les vaisseaux de la formation se rendent : la flotte (sa destination) une fois née, sinon le
## point de rassemblement.
static func target_system(state: GameState, rec: Dictionary) -> int:
	var f: Fleet = state.fleets.get(int(rec["f"]))
	if f != null and f.owner == int(rec["o"]):
		return f.destination()
	return int(rec["s"])


## La flotte de la formation existe-t-elle encore ?
static func has_fleet(state: GameState, rec: Dictionary) -> bool:
	var f: Fleet = state.fleets.get(int(rec["f"]))
	return f != null and f.owner == int(rec["o"])


# --- Ce qu'on peut commander -------------------------------------------------------------------

## Classes que l'empire peut commander pour une formation : celles qu'il sait construire, hors vaisseaux
## uniques (titans) et vaisseaux qui naissent.
static func orderable(state: GameState, eid: int) -> Array[String]:
	var out: Array[String] = []
	for sid in Designs.buildable_ids(state, eid):
		if order_block(state, eid, sid) == "":
			out.append(sid)
	return out


## Pourquoi une classe ne se commande pas ("" si elle se commande).
static func order_block(state: GameState, eid: int, ship_id: String) -> String:
	var sd := GameData.ship(ship_id)
	if sd.is_empty():
		return "classe de vaisseau inconnue"
	if bool(sd.get("spawn_only", false)):
		return "ce vaisseau ne se construit pas"
	if bool((sd.get("requires", {}) as Dictionary).get("unique_per_empire", false)):
		return "un vaisseau unique se commande au chantier d'une colonie"
	if not Designs.can_build_id(state, eid, ship_id):
		return "votre peuple ne construit pas ce vaisseau"
	if not Fleets.ship_unlocked(state, eid, ship_id):
		return "technologie requise : %s" % Research.missing_text(state, eid, sd.get("requires_tech", []))
	var nb := Insolites.ship_block(state, eid)
	if nb != "":
		return nb
	return ""


## Chantiers capables de lancer ce vaisseau aujourd'hui, à ressources égales (on ignore seulement le
## prix et l'occupation) : sert à dire pourquoi une commande attend.
static func wait_reason(state: GameState, id: int) -> String:
	var rec := get_rec(state, id)
	if rec.is_empty() or (rec["q"] as Array).is_empty():
		return ""
	var eid := int(rec["o"])
	var ship_id := String(rec["q"][0])
	var any_yard := false
	var busy := true
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner != eid:
			continue
		var why := Fleets.check_build_ship(state, eid, pid, ship_id)
		if why == "":
			return ""
		if why == "le chantier spatial est occupé":
			any_yard = true
			continue
		if why.begins_with("ressources insuffisantes"):
			any_yard = true
			busy = false
			continue
	if not any_yard:
		return "aucun de vos chantiers ne peut construire ce vaisseau"
	if busy:
		return "tous vos chantiers sont occupés"
	var cost := Fleets.ship_cost(state, eid, ship_id)
	return "ressources insuffisantes (il faut %s)" % GameData.format_amounts(cost)


# --- Ordres ------------------------------------------------------------------------------------

## Ordres : "new" (s nom, a système de rassemblement ; ou b flotte à renforcer et s premier vaisseau
## commandé, "" pour aucun), "add" / "sub"
## (a formation, s classe), "drop" (a), "rename" (a, s), "place" (a, b système), "auto" (a 1/0).
static func check(state: GameState, player: int, act: String, a: int, b: int, s: String) -> String:
	var e := state.get_empire(player)
	if e == null:
		return "empire inconnu"
	match act:
		"new":
			if b >= 0:
				var f: Fleet = state.fleets.get(b)
				if f == null or f.owner != player:
					return "cette flotte ne vous appartient pas"
				if for_fleet(state, b) >= 0:
					return "cette flotte a déjà des renforts en commande"
				return order_block(state, player, s) if s != "" else ""
			var n := s.strip_edges()
			if n.is_empty():
				return "nom vide"
			if n.length() > NAME_MAX:
				return "nom trop long (%d caractères au plus)" % NAME_MAX
			return _check_place(state, player, a)
		"add", "sub", "drop", "rename", "place":
			var rec := get_rec(state, a)
			if rec.is_empty() or int(rec["o"]) != player:
				return "cette formation ne vous appartient pas"
			match act:
				"add":
					if (rec["q"] as Array).size() >= QUEUE_MAX:
						return "commande pleine (%d vaisseaux en attente au plus)" % QUEUE_MAX
					return order_block(state, player, s)
				"sub":
					if not (rec["q"] as Array).has(s):
						return "aucun vaisseau de cette classe n'attend son chantier"
				"rename":
					var n := s.strip_edges()
					if n.is_empty():
						return "nom vide"
					if n.length() > NAME_MAX:
						return "nom trop long (%d caractères au plus)" % NAME_MAX
					if has_fleet(state, rec):
						return "la flotte existe : renommez-la comme les autres"
				"place":
					if has_fleet(state, rec):
						return "la flotte existe : c'est elle que les renforts rejoignent"
					return _check_place(state, player, b)
			return ""
		"auto":
			if (a == 1) == auto_join(state, player):
				return "c'est déjà le réglage"
			return ""
	return "ordre inconnu : %s" % act


static func _check_place(state: GameState, player: int, sid: int) -> String:
	if state.galaxy.get_system(sid) == null or state.system_owner(sid) != player:
		return "le point de rassemblement doit être un de vos systèmes"
	return ""


static func apply(state: GameState, player: int, act: String, a: int, b: int, s: String) -> void:
	if check(state, player, act, a, b, s) != "":
		return
	var root := _root(state)
	match act:
		"new":
			var id := int(root["next"])
			root["next"] = id + 1
			var rec := {"o": player, "n": s.strip_edges(), "s": a, "f": -1, "q": [], "y": {}}
			if b >= 0:
				var f: Fleet = state.fleets[b]
				rec["n"] = f.fleet_name
				rec["s"] = f.system_id
				rec["f"] = b
				if s != "":
					(rec["q"] as Array).append(s)  # renforts : le premier vaisseau commandé d'un coup
			(root["m"] as Dictionary)[str(id)] = rec
		"add":
			(get_rec(state, a)["q"] as Array).append(s)
		"sub":
			var q: Array = get_rec(state, a)["q"]
			q.remove_at(q.rfind(s))
			_close_if_done(state, a)
		"drop":
			# Les vaisseaux déjà en chantier sortent quand même, chacun dans sa propre flotte.
			(root["m"] as Dictionary).erase(str(a))
		"rename":
			get_rec(state, a)["n"] = s.strip_edges()
		"place":
			get_rec(state, a)["s"] = b
		"auto":
			var off: Array = root["off"]
			if a == 1:
				off.erase(player)
			else:
				off.append(player)
				off.sort()


## Une formation qui a sa flotte et plus rien en commande ni en chantier a fini son travail. Une
## formation encore vide (pas de flotte) reste : c'est la flotte qu'on vient de créer.
static func _close_if_done(state: GameState, id: int) -> void:
	var rec := get_rec(state, id)
	if rec.is_empty():
		return
	if (rec["q"] as Array).is_empty() and (rec["y"] as Dictionary).is_empty() and int(rec["f"]) >= 0:
		_sub(state, "m").erase(str(id))


# --- Chantiers ---------------------------------------------------------------------------------

## Un vaisseau sort du chantier de la colonie planet_id. Renvoie true s'il appartient à une formation
## (il prend alors son nom ou part la rejoindre ; le point de ralliement ne s'applique pas).
static func on_built(state: GameState, planet_id: int, f: Fleet) -> bool:
	var m := _sub(state, "m")
	if m.is_empty():
		return false
	var key := str(planet_id)
	for k in _sorted_keys(m):
		var rec: Dictionary = m[k]
		var y: Dictionary = rec["y"]
		if int(rec["o"]) != f.owner or not y.has(key) or String(y[key]) != f.ships[0]:
			continue
		y.erase(key)
		if has_fleet(state, rec):
			_sub(state, "j")[str(f.id)] = int(rec["f"])
		else:
			# Premier vaisseau (ou flotte perdue entre-temps) : c'est lui, la flotte.
			f.fleet_name = String(rec["n"])
			rec["f"] = f.id
			var to := int(rec["s"])
			if to != f.system_id:
				var plan := Fleets.plan_route(state, f, to)
				if not plan.is_empty():
					f.path.assign(plan["path"])
		_close_if_done(state, int(k))
		return true
	return false


## Un vaisseau armé neuf hors commande : il rejoindra la flotte armée qu'il trouvera à l'arrêt là où
## il s'arrête (son chantier, ou le point de ralliement).
static func on_new_ship(state: GameState, f: Fleet) -> void:
	var e := state.get_empire(f.owner)
	if e == null or e.is_ai() or not Combat.is_armed(f) or not auto_join(state, f.owner):
		return
	(_root(state)["j"] as Dictionary)[str(f.id)] = JOIN_ANY


static func _sorted_keys(d: Dictionary) -> Array:
	var keys := d.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return int(a) < int(b))
	return keys


# --- Jour par jour -----------------------------------------------------------------------------

## Chaque jour, après les files des colonies : les chantiers libres prennent les commandes des
## formations, puis les vaisseaux en route rejoignent leur flotte.
static func daily(state: GameState) -> Array[Dictionary]:
	var added: Array[Dictionary] = []
	if state.musters.is_empty():
		return added
	_cleanup(state)
	_assign(state)
	_joins(state)
	return added


## Chantiers perdus (colonie prise, chantier vidé) : la commande revient en tête de file.
static func _cleanup(state: GameState) -> void:
	var m := _sub(state, "m")
	for k in _sorted_keys(m):
		var rec: Dictionary = m[k]
		var y: Dictionary = rec["y"]
		for pk in _sorted_keys(y):
			var c: Colony = state.colonies.get(int(pk))
			if c == null or c.owner != int(rec["o"]) or c.ship_build != String(y[pk]):
				(rec["q"] as Array).push_front(String(y[pk]))
				y.erase(pk)
		var f: Fleet = state.fleets.get(int(rec["f"]))
		if int(rec["f"]) >= 0 and (f == null or f.owner != int(rec["o"])):
			# Flotte détruite ou passée à l'ennemi : le prochain vaisseau refera la flotte.
			if (rec["q"] as Array).is_empty() and y.is_empty():
				m.erase(k)
			else:
				rec["f"] = -1


## Répartition entre les chantiers : formation par formation, chaque vaisseau en attente part au
## chantier libre (file de la colonie vide) le plus proche de sa flotte. Trop cher : on attend.
static func _assign(state: GameState) -> void:
	var m := _sub(state, "m")
	for k in _sorted_keys(m):
		var rec: Dictionary = m[k]
		var q: Array = rec["q"]
		if q.is_empty():
			continue
		var eid := int(rec["o"])
		var dist := _hops_from(state, target_system(state, rec))
		while not q.is_empty():
			var ship_id := String(q[0])
			var best := -1
			var best_d := 1 << 30
			for pid in state.sorted_colony_ids():
				var c: Colony = state.colonies[pid]
				if c.owner != eid or c.ship_build != "" or not c.ship_queue.is_empty():
					continue
				var sid := state.galaxy.get_planet(pid).system_id
				var d := int(dist.get(sid, 1 << 20))
				if d >= best_d:
					continue
				if SimCommands.validate(state, SimCommands.build_ship(eid, pid, ship_id)) != "":
					continue
				best = pid
				best_d = d
			if best < 0:
				break
			SimCommands.apply(state, SimCommands.build_ship(eid, best, ship_id))
			(rec["y"] as Dictionary)[str(best)] = ship_id
			q.pop_front()


## Sauts depuis un système, par toutes les routes (sert seulement à classer les chantiers).
static func _hops_from(state: GameState, from: int) -> Dictionary:
	var out := {from: 0}
	if state.galaxy.get_system(from) == null:
		return out
	var frontier: Array[int] = [from]
	while not frontier.is_empty():
		var nxt: Array[int] = []
		for s in frontier:
			for n in state.galaxy.systems[s].neighbors:
				if not out.has(n):
					out[n] = int(out[s]) + 1
					nxt.append(n)
		frontier = nxt
	return out


## Les vaisseaux qui rejoignent : arrivés près de leur flotte à l'arrêt, ils s'y fondent ; sinon ils
## se remettent en route vers elle (elle a pu bouger). Rien pendant une bataille.
static func _joins(state: GameState) -> void:
	var j := _sub(state, "j")
	for k in _sorted_keys(j):
		var f: Fleet = state.fleets.get(int(k))
		if f == null:
			j.erase(k)
			continue
		if f.is_moving() or state.battles.has(f.system_id):
			continue
		var t := int(j[k])
		if t == JOIN_ANY:
			j.erase(k)
			var into := _host_here(state, f)
			if into != null:
				Fleets.absorb(state, f, into)
			continue
		var into: Fleet = state.fleets.get(t)
		if into == null or into.owner != f.owner or into.id == f.id:
			j.erase(k)
			continue
		if into.system_id == f.system_id and not into.is_moving():
			if into.refit_left > 0:
				continue  # elle sort bientôt du chantier
			j.erase(k)
			Fleets.absorb(state, f, into)
			continue
		var plan := Fleets.plan_route(state, f, into.destination())
		if plan.is_empty() or (plan["path"] as Array).is_empty():
			if into.system_id != f.system_id:
				j.erase(k)  # injoignable : le vaisseau reste une flotte à part
			continue
		f.system_id = int(plan["system"])
		f.path.assign(plan["path"])
		f.progress = int(plan["progress"])


## Flotte armée de l'empire, à l'arrêt ici, sans mission qui l'emmène ailleurs : la plus nombreuse,
## à égalité la plus ancienne.
static func _host_here(state: GameState, f: Fleet) -> Fleet:
	var best: Fleet = null
	var j := _sub(state, "j")
	for fid in state.sorted_fleet_ids():
		var g: Fleet = state.fleets[fid]
		if g.id == f.id or g.owner != f.owner or g.system_id != f.system_id or g.is_moving() or g.refit_left > 0:
			continue
		if g.is_exploring() or g.is_patrolling() or j.has(str(g.id)) or not Combat.is_armed(g):
			continue
		if best == null or g.ships.size() > best.ships.size():
			best = g
	return best
