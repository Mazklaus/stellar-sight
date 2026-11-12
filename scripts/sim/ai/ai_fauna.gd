class_name AiFauna
extends RefCounted
## Faune pour les empires IA (voir Fauna, proposition 15).
## Normale et au-dessus : étudie, une à la fois, les espèces rencontrées dont un nid est proche ; une IA
## pacifique apprivoise ensuite une espèce apprivoisable, une IA agressive chasse une espèce hostile
## dont un nid est proche (une seule à la fois). Toujours en gardant de quoi payer deux colonies.
## Chasse (voir AiPlayer._command_fleet) : en paix, la flotte de guerre attaque le nid ou le troupeau
## hostile connu le plus proche de la capitale, à 6 sauts au plus, si elle fait 1,5 fois ce qui s'y
## trouve (la Recrue ne compte pas et part dès qu'elle fait jeu égal). Gardiens (lot 2) : jusqu'à 8
## sauts ; même en guerre s'il est à 4 sauts au plus et que la flotte fait 2 fois sa force.
## Colonisation : un système où se tient un troupeau hostile est laissé de côté.


const INFLUENCE_RESERVE := 80


static func think(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if not Fauna.active(state):
		return
	if posmod(state.tick + e.id * 13, 30) != 0:
		return
	if int(ctx["lv"].get("faction_use", 1)) <= 0:
		return
	var known := Fauna.known_species(state, e.id)
	if known.is_empty():
		return
	for sp in known:
		if Fauna.study_end(state, e.id, sp) > 0:
			return  # une étude à la fois
	var aggr := AiLevels.aggression(e)
	for sp in known:
		if Fauna.study_end(state, e.id, sp) == 0 and _nest_near(ctx, sp) and _rich(e, Fauna.attitude_cost("etude"), 1):
			if AiPlayer._issue(ctx, SimCommands.fauna_attitude(e.id, sp, "etude")):
				AiPlayer._intent(ctx, "Étudie les %s" % String(Fauna.species(sp)["label"]))
				return
	var hunts := 0
	for sp in known:
		if Fauna.stance(state, e.id, sp) == "chasse":
			hunts += 1
	for sp in known:
		if Fauna.stance(state, e.id, sp) != "":
			continue
		var att := ""
		if aggr <= 0 and bool(Fauna.species(sp).get("tamable", false)) and Fauna.studied(state, e.id, sp):
			att = "apprivoise"
		elif aggr > 0 and hunts == 0 and Fauna.temper(sp) != "passive" and _nest_near(ctx, sp):
			att = "chasse"
		if att != "" and _rich(e, Fauna.attitude_cost(att), 1):
			if AiPlayer._issue(ctx, SimCommands.fauna_attitude(e.id, sp, att)):
				AiPlayer._intent(ctx, ("Apprivoise les %s" if att == "apprivoise" else "Chasse les %s") % String(Fauna.species(sp)["label"]))
				return


## Assez riche, en gardant de quoi payer deux colonies (l'influence sert d'abord à s'étendre).
static func _rich(e: Empire, cost: Dictionary, times: int) -> bool:
	for r in cost:
		var keep := INFLUENCE_RESERVE if r == "influence" else 0
		if int(e.resources.get(r, 0)) < times * int(cost[r]) + keep:
			return false
	return true


## Un nid de l'espèce à 6 sauts au plus de la capitale ?
static func _nest_near(ctx: Dictionary, sp: String) -> bool:
	var state: GameState = ctx["state"]
	var home := AiPlayer._capital_system(ctx)
	if home < 0:
		return false
	if not ctx.has("home_jumps"):
		ctx["home_jumps"] = FactionTraits.jumps_from(state.galaxy, home)
	var jumps: Dictionary = ctx["home_jumps"]
	for sid in Fauna.nest_ids(state):
		if String(Fauna.nests(state)[sid]["sp"]) == sp and int(jumps.get(sid, 99)) <= 6:
			return true
	return false


## Nid ou troupeau à attaquer pour cette flotte de guerre (en paix), -1 sinon : espèce rencontrée et
## hostile, système libre exploré à 6 sauts au plus de la capitale, le plus proche d'abord.
static func nest_target(ctx: Dictionary, f: Fleet, home: int) -> int:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if not Fauna.active(state) or home < 0:
		return -1
	var war := not e.wars.is_empty()
	if not ctx.has("home_jumps"):
		ctx["home_jumps"] = FactionTraits.jumps_from(state.galaxy, home)
	var jumps: Dictionary = ctx["home_jumps"]
	var need := 150 if int(ctx["lv"].get("faction_use", 1)) > 0 else 100
	var power := Combat.fleet_power(f)
	var best := -1
	var best_j := 7
	var cands := {}
	if not war:
		for sid in Fauna.nest_ids(state):
			cands[sid] = String(Fauna.nests(state)[sid]["sp"])
	for fid in Fauna.herd_ids(state):
		var g: Fleet = state.fleets.get(fid)
		if war:
			break  # en guerre, on ne chasse pas la faune
		if g != null and not g.is_moving() and Fauna.hostile(state, g, e.id):
			cands[g.system_id] = String(Fauna.herds(state)[fid]["sp"])
	# Gardiens (lot 2) : vus, éveillés, hostiles ; plus loin (8 sauts), ils gardent les meilleurs systèmes.
	var guards := {}
	for gid in Guardians.known(state, e.id):
		var gsid := Guardians.fleet_system(state, gid)
		if gsid >= 0 and Guardians.awake_at(state, gsid) == gid and Guardians.hostile(state, gid, e.id):
			guards[gsid] = gid
			cands[gsid] = ""
	var ids := cands.keys()
	ids.sort()
	for sid in ids:
		var sp := String(cands[sid])
		if guards.has(sid):
			pass
		elif not Fauna.knows(state, e.id, sp) or not Fauna.species_hostile(state, e.id, sp):
			continue
		if not Fleets.is_explored(state, e.id, sid) or state.system_owner(sid) >= 0:
			continue
		var j := int(jumps.get(sid, 99))
		var want := need
		if guards.has(sid):
			j -= 2  # 8 sauts au plus, comptés comme 6
			if war:
				# En guerre : seulement un gardien proche (4 sauts) et avec une large marge.
				if j > 2:
					continue
				want = need + 50
		if j < best_j and power * 100 >= want * maxi(1, Fauna.herd_power(state, sid)):
			best = sid
			best_j = j
	return best


## Le système abrite-t-il en ce moment des créatures qui attaqueraient un colon de cet empire (ou un
## prédateur dans un système voisin) ?
static func dangerous(state: GameState, empire_id: int, sid: int) -> bool:
	if not Fauna.active(state):
		return false
	for g in Fleets.fleets_at(state, sid, GameState.FAUNA_ID):
		if Fauna.hostile(state, g, empire_id):
			return true
	# Un prédateur voisin viendrait chercher le colon pendant qu'il s'installe.
	for n in state.galaxy.systems[sid].neighbors:
		for g in Fleets.fleets_at(state, n, GameState.FAUNA_ID):
			var h := Fauna.herd_of(state, g)
			if not h.is_empty() and Fauna.temper(String(h["sp"])) == "predator" and Fauna.hostile(state, g, empire_id):
				return true
	return false
