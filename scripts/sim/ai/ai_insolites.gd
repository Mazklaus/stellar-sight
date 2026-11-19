class_name AiInsolites
extends RefCounted
## IA des peuples insolites (prop. 5 ; voir Insolites). Chaque peuple joue sa règle cassée :
##   - l'Exode lève l'ancre avant les Traqueurs, suit les Chants de la route et se pose sur la Terre
##     promise, garde ses nefs ensemble et arme une escorte dans son chantier embarqué ;
##   - le Cirque envoie ses Troupes jouer chez les empires en paix et en construit d'autres ;
##   - l'Orbe-Monde va manger là où il y a à manger, laisse des Lunes-sentinelles, dévore en guerre ;
##   - les Kraal vont de pâturage en pâturage et arrachent des Pilotes chez l'ennemi.
## Et la réaction des autres : envoyer un délégué au Grand Numéro, purger un Fan-club.


static func _ai() -> Dictionary:
	return Insolites.cfg("ai")


## Flottes menées ici (AiPlayer._fleets les laisse) : Troupes du Cirque, hardes de Kraal au repos.
static func managed(state: GameState, f: Fleet) -> bool:
	if state.insolites.is_empty():
		return false
	match Insolites.kind(state, f.owner):
		"zambalu":
			return InsZambalu.is_troupe(f) or FactionTraits.is_city_fleet(f)
		"kraal":
			return InsKraal.kraal_count(f) > 0
		"exode", "halcyre":
			return FactionTraits.is_city_fleet(f) and not InsExode.arrived(state, f.owner)
	return false


static func think(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if state.insolites.is_empty() or e.is_npc() or e.eliminated:
		return
	_react(ctx)
	if AiPlayer._use(ctx) <= 0:
		return
	match Insolites.kind(state, e.id):
		"exode":
			_exode(ctx)
		"zambalu":
			_zambalu(ctx)
		"halcyre":
			_halcyre(ctx)
		"kraal":
			_kraal(ctx)


static func _go(ctx: Dictionary, f: Fleet, sid: int, why := "") -> bool:
	if sid < 0 or sid == f.system_id:
		return false
	var e: Empire = ctx["e"]
	if AiPlayer._issue(ctx, SimCommands.move_fleet(e.id, f.id, sid)):
		if why != "":
			AiPlayer._intent(ctx, why)
		return true
	return false


## Puissance armée ennemie (en guerre) dans un système.
static func _foe_power(state: GameState, eid: int, sid: int) -> int:
	var n := 0
	for fid in state.sorted_fleet_ids():
		var f: Fleet = state.fleets[fid]
		if f.system_id == sid and f.owner != eid and Combat.is_armed(f) and Combat.at_war(state, f.owner, eid):
			n += Combat.fleet_power(f)
	return n


## Systèmes joignables triés par distance (sauts), à max_jumps au plus : [[sauts, sid], …].
static func _near(state: GameState, from: int, max_jumps: int) -> Array:
	var d: Dictionary = FactionTraits.jumps_from(state.galaxy, from)
	var out := []
	for sid in d:
		if int(d[sid]) > 0 and int(d[sid]) <= max_jumps:
			out.append([int(d[sid]), int(sid)])
	out.sort()
	return out


## Meilleur vaisseau de guerre que le chantier embarqué peut construire ("" sinon).
static func _yard_warship(state: GameState, eid: int) -> String:
	var best := ""
	var best_s := -1
	var ids: Array = FactionTraits.ship_ids_for(state.get_empire(eid).faction_id)
	ids.append_array(Designs.buildable_ids(state, eid))
	for sid in ids:
		var sd := GameData.ship(String(sid))
		if not bool(sd.get("military", false)) and sd.get("weapons", {}).is_empty():
			continue
		if Insolites.check_build(state, eid, String(sid)) != "":
			continue
		var s := Combat.ship_strength(String(sid))
		if s > best_s:
			best_s = s
			best = String(sid)
	return best


# --- Réactions de tous les empires ---------------------------------------------------------------

static func _react(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	# Grand Numéro : un délégué si l'on est pacifique, ou si l'on a une guerre à suspendre.
	if InsZambalu.open_call(state) >= 0 and InsZambalu.check_delegate(state, e.id) == "":
		if AiLevels.aggression(e) <= 0 or not e.wars.is_empty():
			AiPlayer._issue(ctx, SimCommands.ins_act(e.id, "delegate"))
	# Fan-clubs : on purge l'implant d'un ennemi, ou quand on a de l'influence à revendre.
	var im: Dictionary = state.insolites.get("implants", {})
	for key in im.keys():
		var pid := int(key)
		var c: Colony = state.colonies.get(pid)
		if c == null or c.owner != e.id:
			continue
		var owner := int(im[key]["o"])
		if (Combat.at_war(state, e.id, owner) or int(e.resources.get("influence", 0)) >= 150) and Insolites.check_purge(state, e.id, pid) == "":
			AiPlayer._issue(ctx, SimCommands.ins_act(e.id, "purge", {"pid": pid}))
			break


# --- Flotte-Exode --------------------------------------------------------------------------------

static func _exode(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if InsExode.arrived(state, e.id):
		return
	if InsExode.check_settle(state, e.id) == "":
		if AiPlayer._issue(ctx, SimCommands.ins_act(e.id, "settle")):
			AiPlayer._intent(ctx, "Se pose sur la Terre promise")
			return
	var nefs := InsExode.nef_fleets(state, e.id)
	if nefs.is_empty():
		return
	var cf: Fleet = nefs[0]
	# Les nefs restent ensemble.
	for i in range(1, nefs.size()):
		var f: Fleet = nefs[i]
		if f.is_moving():
			continue
		if f.system_id == cf.system_id and not cf.is_moving():
			AiPlayer._issue(ctx, SimCommands.merge_fleets(e.id, f.id, cf.id))
		elif not cf.is_moving():
			_go(ctx, f, cf.system_id)
	# Escorte : le chantier embarqué arme l'Exode (six vaisseaux de guerre au plus).
	var armed := 0
	for f in Fleets.empire_fleets(state, e.id):
		if not FactionTraits.is_city_fleet(f):
			for s in f.ships:
				if Combat.is_armed_ship(s):
					armed += 1
	if armed < 6 and int(e.resources.get("materials", 0)) >= 150 and not AiPlayer._forgets(ctx):
		var ship := _yard_warship(state, e.id)
		if ship != "":
			AiPlayer._issue(ctx, SimCommands.ins_act(e.id, "build", {"ship": ship}))
	# L'escorte suit les nefs en temps de paix.
	if e.wars.is_empty() and not cf.is_moving():
		for f in Fleets.empire_fleets(state, e.id):
			if f.is_idle() and Combat.is_armed(f) and not FactionTraits.is_city_fleet(f) and f.system_id != cf.system_id:
				_go(ctx, f, cf.system_id)
	if cf.is_moving():
		return
	var ed := Insolites.emp(state, e.id)
	var anc: Dictionary = ed.get("anc", {})
	var stay := state.tick - int(anc.get("t", state.tick))
	var promised := Victory.promised_planet(state, e.id) if Victory.has_tech(state, e.id, "terre_promise") else -1
	if promised >= 0:
		var psid := state.galaxy.get_planet(promised).system_id
		var dist := int(FactionTraits.jumps_from(state.galaxy, cf.system_id).get(psid, 999))
		if dist <= int(Victory.info("terre_promise")["reveal_jumps"]) and psid != cf.system_id:
			if _go(ctx, cf, psid, "Fait route vers la Terre promise"):
				return
	var here := _anchor_value(state, e.id, cf.system_id)
	var threatened := _foe_power(state, e.id, cf.system_id) > 0
	if stay < int(_ai().get("exode_flee_days", 600)) and here > 0 and not threatened:
		return
	var best := -1
	var best_v := -999999
	var pd := FactionTraits.jumps_from(state.galaxy, state.galaxy.get_planet(promised).system_id) if promised >= 0 else {}
	for pair in _near(state, cf.system_id, 4):
		var sid := int(pair[1])
		if _foe_power(state, e.id, sid) > 0 or not e.explored.has(sid):
			continue
		var v := _anchor_value(state, e.id, sid) * 10 - int(pair[0]) * 3
		if state.system_owner(sid) >= 0:
			v -= 5
		if not pd.is_empty():
			v -= int(pd.get(sid, 30)) * 4
		if v > best_v:
			best_v = v
			best = sid
	_go(ctx, cf, best, "Lève l'ancre avant les Traqueurs")


static func _anchor_value(state: GameState, eid: int, sid: int) -> int:
	var v := 0
	for pid in state.galaxy.systems[sid].planet_ids:
		var w := InsExode.planet_work(state, eid, pid)
		for r in w:
			v += int(w[r])
	return v


# --- Cirque Zambalù ------------------------------------------------------------------------------

static func _zambalu(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var ed := Insolites.emp(state, e.id)
	var troupes: Array[Fleet] = []
	for f in Fleets.empire_fleets(state, e.id):
		if InsZambalu.is_troupe(f):
			troupes.append(f)
	if troupes.size() < 4 and int(e.resources.get("materials", 0)) >= 80 and not AiPlayer._forgets(ctx):
		AiPlayer._issue(ctx, SimCommands.ins_act(e.id, "build", {"ship": InsZambalu.TROUPE}))
	var taken := {}
	var shows: Dictionary = ed.get("shows", {})
	for k in shows:
		taken[int(shows[k]["s"])] = true
	for f in troupes:
		if f.is_moving():
			taken[f.destination()] = true
	for f in troupes:
		if f.is_moving() or shows.has(str(f.id)):
			continue
		var best := -1
		for pair in _near(state, f.system_id, 8):
			var sid := int(pair[1])
			if taken.has(sid) or not e.explored.has(sid):
				continue
			var b := InsZambalu.host_of(state, e.id, sid)
			if b < 0 or Combat.at_war(state, e.id, b) or InsZambalu.banned(state, b):
				continue
			if int((state.insolites.get("stage", {}) as Dictionary).get(str(sid), 0)) > state.tick:
				continue
			best = sid
			break
		if best >= 0 and _go(ctx, f, best, "Part en tournée"):
			taken[best] = true
	# Le Chapiteau fuit les flottes ennemies.
	var cf := FactionTraits.city_fleet(state, e.id)
	if cf != null and not cf.is_moving() and _foe_power(state, e.id, cf.system_id) > 0:
		for pair in _near(state, cf.system_id, 2):
			if _foe_power(state, e.id, int(pair[1])) == 0 and e.explored.has(int(pair[1])):
				_go(ctx, cf, int(pair[1]), "Le Chapiteau plie bagage")
				break


# --- Orbe-Monde Halcyre --------------------------------------------------------------------------

static func _halcyre(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var o := InsHalcyre.orbe(state, e.id)
	if o == null or o.is_moving():
		return
	var ed := Insolites.emp(state, e.id)
	if not (ed.get("eat", {}) as Dictionary).is_empty():
		return
	var sid := o.system_id
	# En guerre, l'Orbe dévore une colonie ennemie de son système.
	if InsHalcyre.mass(state, e.id) >= 40:
		for pid in state.galaxy.systems[sid].planet_ids:
			if InsHalcyre.check_devour(state, e.id, pid) == "":
				if AiPlayer._issue(ctx, SimCommands.ins_act(e.id, "devour", {"pid": pid})):
					AiPlayer._intent(ctx, "Dévore un monde ennemi")
					return
	var edible := InsHalcyre.edible(state, sid)
	# Lune-sentinelle : un éclat laissé dans un système libre quand la Masse le permet.
	if InsHalcyre.mass(state, e.id) >= int(_ai().get("halcyre_sentinel_mass", 50)) and state.system_owner(sid) < 0:
		for pid in state.galaxy.systems[sid].planet_ids:
			if edible.has(pid) and edible.size() > 1 and pid == edible[0]:
				continue
			if InsHalcyre.check_sentinel(state, e.id, pid) == "":
				if AiPlayer._issue(ctx, SimCommands.ins_act(e.id, "sentinel", {"pid": pid})):
					return
	if not edible.is_empty():
		return  # il reste à manger ici : l'Orbe mangera demain
	for pair in _near(state, sid, 6):
		var to := int(pair[1])
		var owner := state.system_owner(to)
		if owner >= 0 and owner != e.id and Combat.at_war(state, owner, e.id):
			continue
		if InsHalcyre.edible(state, to).is_empty() or _foe_power(state, e.id, to) > 0:
			continue
		if _go(ctx, o, to, "L'Orbe-Monde part manger ailleurs"):
			return
	if o.is_idle():
		AiPlayer._issue(ctx, SimCommands.set_fleet_order(e.id, o.id, Fleet.ORDER_EXPLORE))  # rien à manger en vue : l'Orbe erre


# --- Hardes de Kraal -----------------------------------------------------------------------------

static func _kraal(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var want := int(_ai().get("kraal_min_graze", 30))
	var taken := {}
	var known: Dictionary = Insolites.emp(state, e.id).get("known", {})
	for f in Fleets.empire_fleets(state, e.id):
		if InsKraal.kraal_count(f) == 0 or f.is_moving() or state.battles.has(f.system_id):
			continue
		if InsKraal.check_pilot(state, e.id, f.id) == "":
			AiPlayer._issue(ctx, SimCommands.ins_act(e.id, "pilot", {"fleet": f.id}))
			continue
		if not e.wars.is_empty() and Combat.is_warfleet(f) and state.system_owner(f.system_id) >= 0 and Combat.at_war(state, e.id, state.system_owner(f.system_id)):
			continue  # en chasse chez l'ennemi
		if InsKraal.is_pasture(state, f.system_id) and InsKraal.graze(state, e.id, f.system_id) >= want and not taken.has(f.system_id):
			taken[f.system_id] = true
			continue
		var moved := false
		for pair in _near(state, f.system_id, 8):
			var to := int(pair[1])
			if taken.has(to) or not InsKraal.is_pasture(state, to) or InsKraal.graze(state, e.id, to) < want:
				continue
			var owner := state.system_owner(to)
			if (owner >= 0 and owner != e.id) or _foe_power(state, e.id, to) > 0:
				continue
			if _go(ctx, f, to, "La Harde migre vers un pâturage"):
				taken[to] = true
				moved = true
				break
		if not moved and not known.has(str(f.system_id)) and f.is_idle():
			AiPlayer._issue(ctx, SimCommands.set_fleet_order(e.id, f.id, Fleet.ORDER_EXPLORE))  # chercher de nouveaux pâturages
