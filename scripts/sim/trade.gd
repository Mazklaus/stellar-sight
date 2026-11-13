class_name Trade
extends RefCounted
## Commerce, lot 1 (étude « Le commerce galactique », data/trade.json) : routes commerciales,
## comptoirs, routes intérieures, blocus, paliers de traité, embargo, piraterie des routes.
##
## Paliers de traité (relation "trade") : 0 aucun, 1 Comptoirs ouverts, 2 Accord commercial,
## 3 Libre-échange. Le traité « trade » de Diplomacy fait monter d'un palier (Humankind, Distant Worlds 2).
##
## Chaque mois (compute), chaque empire envoie ses routes dans la limite de sa capacité (base +
## comptoirs + technologies, Civilization VI) : d'abord les routes intérieures qu'il réserve, vers ses
## jeunes colonies ; puis une route vers chaque partenaire, les plus rentables d'abord ; les places qui
## restent vont aux jeunes colonies. Une route suit le plus court chemin de couloirs (en évitant les
## systèmes des ennemis quand c'est possible) ; elle rapporte la même valeur aux deux bouts
## (Galactic Civilizations), plus si elle est longue et relie des systèmes peuplés (Endless Space 2),
## moins le tarif du palier et ce que volent les pirates des systèmes non protégés (Stellaris).
## Une flotte armée hostile sur le chemin la bloque.
##
## Le résultat est rangé dans state.trade (routes, revenus par empire, colonies desservies) : le
## bilan, l'interface et l'IA le lisent sans rien recalculer. Tout est entier et parcouru dans l'ordre.

const NONE := 0
const OPEN := 1
const AGREEMENT := 2
const FREE := 3


static func data() -> Dictionary:
	return GameData.trade()


static func tiers() -> Array:
	return data()["tiers"]


static func tier_info(n: int) -> Dictionary:
	for t: Dictionary in tiers():
		if int(t["id"]) == n:
			return t
	return {}


static func tier_label(n: int) -> String:
	return "Aucun commerce" if n <= 0 else String(tier_info(n).get("label", "?"))


## Palier de traité commercial entre a et b (0 = aucun).
static func tier(state: GameState, a: int, b: int) -> int:
	return int(Diplomacy.rel(state, a, b).get("trade", 0))


## Libellé du prochain palier à proposer ("" si le libre-échange est déjà signé).
static func next_label(state: GameState, a: int, b: int) -> String:
	var t := tier(state, a, b)
	return "" if t >= FREE else tier_label(t + 1)


# --- Paliers et embargo ------------------------------------------------------------------------

## Conditions du palier suivant (appelé par Diplomacy.check_terms pour le traité « trade »).
static func check_next_tier(state: GameState, a: int, b: int) -> String:
	if embargoed(state, a, b):
		return "un embargo interdit tout commerce"
	var t := tier(state, a, b)
	if t >= FREE:
		return "le libre-échange est déjà en vigueur"
	if not Diplomacy.has_pact(state, a, b):
		return "le commerce exige la paix"
	if t == AGREEMENT:
		var fi := tier_info(FREE)
		var since := int(Diplomacy.rel(state, a, b).get("tier_since", state.tick))
		var left := int(fi.get("after_days", 720)) - (state.tick - since)
		if left > 0:
			return "le libre-échange exige deux ans d'accord commercial (encore %d jours)" % left
		var need := int(fi.get("min_opinion", 20))
		if Diplomacy.opinion(state, a, b) < need or Diplomacy.opinion(state, b, a) < need:
			return "le libre-échange exige une opinion d'au moins %d de part et d'autre" % need
	return ""


## Monte d'un palier (conditions déjà vérifiées). Appelé par Diplomacy.sign_treaty.
static func raise_tier(state: GameState, a: int, b: int) -> int:
	var r := Diplomacy._rel_w(state, a, b)
	var t := int(r.get("trade", 0)) + 1
	if int(r.get("trade", 0)) == 0:
		r["trade_since"] = state.tick
	r["trade"] = t
	r["tier_since"] = state.tick
	return t


static func embargoed(state: GameState, a: int, b: int) -> bool:
	return not (Diplomacy.rel(state, a, b).get("emb", []) as Array).is_empty()


## a impose-t-il un embargo à b ?
static func embargo_by(state: GameState, a: int, b: int) -> bool:
	return (Diplomacy.rel(state, a, b).get("emb", []) as Array).has(a)


## Empires visés par un embargo de a.
static func embargoes_of(state: GameState, a: int) -> Array[int]:
	var out: Array[int] = []
	for o in state.empires:
		if o.id != a and embargo_by(state, a, o.id):
			out.append(o.id)
	return out


static func check_embargo(state: GameState, player: int, target: int) -> String:
	var e := state.get_empire(player)
	var t := state.get_empire(target)
	if e == null or t == null or player == target or GameState.is_npc(target):
		return "empire inconnu"
	if t.eliminated:
		return "cet empire a disparu"
	if not e.contacts.has(target):
		return "vous n'avez jamais rencontré cet empire"
	if embargo_by(state, player, target):
		return "votre embargo est déjà en vigueur"
	if Diplomacy.team_of(state, player, target) > 0:
		return "même équipe : pas d'embargo entre alliés de toujours"
	return ""


static func embargo(state: GameState, player: int, target: int, joined := false) -> void:
	var r := Diplomacy._rel_w(state, player, target)
	var had := int(r.get("trade", 0)) > 0
	var emb: Array = r.get("emb", [])
	emb.append(player)
	emb.sort()
	r["emb"] = emb
	r["trade"] = 0
	Diplomacy.remember(state, target, player, "embargo")
	var ep := state.get_empire(player)
	var et := state.get_empire(target)
	if joined:
		state.add_chronicle("%s se joint à l'embargo contre %s. Les quais se vident un peu plus." % [ep.display_name(), et.display_name()], Espionage.public_to(state, [player, target]))
	else:
		state.add_chronicle("%s décrète un embargo contre %s%s. Les douaniers ont reçu des ordres, et une liste." % [
				ep.display_name(), et.display_name(), " : les accords commerciaux sont rompus" if had else ""], Espionage.public_to(state, [player, target]))
	if joined:
		return
	# Les alliés IA qui n'aiment pas la cible suivent (sanctions de Stellaris).
	var need := int(data()["embargo"].get("ally_join_opinion", 0))
	for ally in Diplomacy.allies(state, player):
		var ae := state.get_empire(ally)
		if ally == target or not ae.is_ai() or not ae.contacts.has(target) or embargo_by(state, ally, target):
			continue
		if Diplomacy.opinion(state, ally, target) <= need:
			embargo(state, ally, target, true)


static func check_lift(state: GameState, player: int, target: int) -> String:
	if state.get_empire(player) == null or state.get_empire(target) == null:
		return "empire inconnu"
	if not embargo_by(state, player, target):
		return "aucun embargo de votre part contre cet empire"
	return ""


static func lift(state: GameState, player: int, target: int) -> void:
	var r := Diplomacy._rel_w(state, player, target)
	var emb: Array = r.get("emb", [])
	emb.erase(player)
	r["emb"] = emb
	state.add_chronicle("%s lève son embargo contre %s. Les premiers cargos repartent, prudemment." % [
			state.get_empire(player).display_name(), state.get_empire(target).display_name()], Espionage.public_to(state, [player, target]))


## Le commerce a été rompu (annulation) : souvenir, double si les routes étaient riches.
static func on_cut(state: GameState, player: int, target: int) -> void:
	var v := value_between(state, player, target)
	Diplomacy.remember(state, target, player, "trade_cut")
	if v >= int(data().get("cut_rich_value", 10)):
		Diplomacy.remember(state, target, player, "trade_cut")


# --- Opinion -----------------------------------------------------------------------------------

## Lignes d'opinion du commerce de a envers b : [[libellé, valeur], …].
@warning_ignore("integer_division")
static func opinion_parts(state: GameState, a: int, b: int) -> Array:
	var out := []
	var t := tier(state, a, b)
	if t <= 0:
		return out
	out.append(["Commerce : %s" % tier_label(t), int(tier_info(t).get("opinion", 0))])
	var op: Dictionary = data()["opinion"]
	var years := mini(int(op["years_max"]), (state.tick - int(Diplomacy.rel(state, a, b).get("trade_since", state.tick))) / 360)
	if years > 0:
		out.append(["%d an%s de commerce" % [years, "s" if years > 1 else ""], years * int(op["per_year"])])
	return out


# --- Capacité et routes ------------------------------------------------------------------------

## Comptoirs bâtis par l'empire (bâtiments qui donnent trade_routes).
static func comptoirs(state: GameState, empire_id: int) -> Array[int]:
	var out: Array[int] = []
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner != empire_id:
			continue
		for b in c.buildings:
			if int(GameData.building(b).get("trade_routes", 0)) > 0:
				out.append(pid)
				break
	return out


static func capacity(state: GameState, empire_id: int) -> int:
	var n := int(data()["capacity_base"])
	for pid in comptoirs(state, empire_id):
		for b in (state.colonies[pid] as Colony).buildings:
			n += int(GameData.building(b).get("trade_routes", 0))
	return n + Research.fx_int(state, empire_id, "trade_routes")


## Places de capacité réservées aux routes intérieures.
static func reserved(state: GameState, empire_id: int) -> int:
	return int(state.trade.get("reserve", {}).get(empire_id, 0))


static func check_reserve(state: GameState, empire_id: int, n: int) -> String:
	if state.get_empire(empire_id) == null:
		return "empire inconnu"
	if n < 0 or n > capacity(state, empire_id):
		return "réserve impossible (0 à %d)" % capacity(state, empire_id)
	return ""


static func set_reserve(state: GameState, empire_id: int, n: int) -> void:
	if not state.trade.has("reserve"):
		state.trade["reserve"] = {}
	if n == 0:
		state.trade["reserve"].erase(empire_id)
	else:
		state.trade["reserve"][empire_id] = n


## Systèmes d'où partent les routes d'un empire : sa capitale et ses comptoirs.
static func hubs(state: GameState, empire_id: int) -> Array[int]:
	var out: Array[int] = []
	var cap := FactionTraits.capital_system(state, empire_id)
	if cap >= 0:
		out.append(cap)
	for pid in comptoirs(state, empire_id):
		var sid := state.galaxy.get_planet(pid).system_id
		if not out.has(sid):
			out.append(sid)
	return out


static func system_pop(state: GameState, sid: int) -> int:
	var n := 0
	for pid in state.galaxy.systems[sid].planet_ids:
		var c: Colony = state.colonies.get(pid)
		if c != null and c.is_colony():
			n += c.population
	return n


## Plus court chemin de couloirs de from à to, en évitant si possible les systèmes tenus par un ennemi
## de a ou de b. [] si aucun chemin.
static func path(state: GameState, from: int, to: int, a: int, b: int) -> Array[int]:
	var p := _bfs(state, from, to, a, b, true)
	if p.is_empty():
		p = _bfs(state, from, to, a, b, false)
	return p


static func _bfs(state: GameState, from: int, to: int, a: int, b: int, avoid: bool) -> Array[int]:
	var prev := {from: -1}
	var queue: Array[int] = [from]
	var i := 0
	while i < queue.size():
		var cur := queue[i]
		i += 1
		if cur == to:
			break
		for n in state.galaxy.systems[cur].neighbors:
			if prev.has(n):
				continue
			if avoid and n != to:
				var o := state.system_owner(n)
				if o >= 0 and o != a and o != b and (Combat.at_war(state, o, a) or Combat.at_war(state, o, b)):
					continue
			prev[n] = cur
			queue.append(n)
	var out: Array[int] = []
	if not prev.has(to):
		return out
	var c := to
	while c != -1:
		out.push_front(c)
		c = int(prev[c])
	return out


## Valeur brute d'une route (avant tarif, pirates et blocus).
@warning_ignore("integer_division")
static func raw_value(state: GameState, p: Array[int]) -> int:
	var rd: Dictionary = data()["route"]
	var jumps := clampi(p.size() - 1, 1, int(rd["max_jumps"]))
	var pop := system_pop(state, p[0]) + system_pop(state, p[p.size() - 1])
	return mini(int(rd["cap"]), int(rd["base"]) + jumps * pop / maxi(1, int(rd["pop_div"])))


## Meilleure route de a vers b : du hub de a le plus proche de la capitale de b, au hub de b le plus
## proche de ce départ. [] si aucune.
static func best_path(state: GameState, a: int, b: int) -> Array[int]:
	var hb := hubs(state, b)
	var ha := hubs(state, a)
	if ha.is_empty() or hb.is_empty():
		return []
	var target := hb[0]
	var from := ha[0]
	var jt := FactionTraits.jumps_from(state.galaxy, target)
	for h in ha:
		if int(jt.get(h, 999)) < int(jt.get(from, 999)):
			from = h
	var jf := FactionTraits.jumps_from(state.galaxy, from)
	var to := hb[0]
	for h in hb:
		if int(jf.get(h, 999)) < int(jf.get(to, 999)):
			to = h
	if not jf.has(to):
		return []
	return path(state, from, to, a, b)


## Jeunes colonies de l'empire (moins de young_pop habitants, hors capitale), les moins peuplées d'abord.
static func young_colonies(state: GameState, empire_id: int) -> Array[int]:
	var young := int(data()["internal"]["young_pop"])
	var cap := FactionTraits.capital_system(state, empire_id)
	var list := []
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner != empire_id or not c.is_colony() or not c.is_established() or c.population >= young:
			continue
		if state.galaxy.get_planet(pid).system_id == cap:
			continue
		list.append([c.population, pid])
	list.sort()
	var out: Array[int] = []
	for it in list:
		out.append(int(it[1]))
	return out


## Partenaires commerciaux d'un empire (palier > 0, encore en jeu), par identifiant.
static func partners(state: GameState, empire_id: int) -> Array[int]:
	var out: Array[int] = []
	var e := state.get_empire(empire_id)
	if e == null:
		return out
	for o in state.empires:
		if o.id != empire_id and not o.eliminated and e.contacts.has(o.id) and tier(state, empire_id, o.id) > 0:
			out.append(o.id)
	return out


# --- Calcul mensuel ------------------------------------------------------------------------------

## Routes du mois, risques des pirates et revenus. Appelé par TradeSystem le jour du bilan, avant
## l'économie du mois suivant ; aussi par les tests et après un chargement de vieille sauvegarde.
static func compute(state: GameState) -> Array[Dictionary]:
	var added: Array[Dictionary] = []
	var routes: Array = []
	var ints := {}
	for e in state.empires:
		if e.eliminated or e.is_npc():
			continue
		_routes_of_empire(state, e.id, routes, ints)
	var armed := _hostile_presence(state)
	_update_risk(state, routes)
	var income := {}
	for r: Dictionary in routes:
		_finish_route(state, r, armed)
		if String(r["kind"]) == "ext":
			for who in [int(r["from"]), int(r["to"])]:
				var inc: Dictionary = income.get(who, {})
				@warning_ignore("integer_division")
				inc["energy"] = int(inc.get("energy", 0)) + int(r["net"]) * maxi(0, 100 + Research.fx_int(state, who, "trade_income_pct")) / 100
				income[who] = inc
		else:
			var inc: Dictionary = income.get(int(r["from"]), {})
			if not bool(r["blocked"]):
				for res in data()["internal"]["yields"]:
					inc[res] = int(inc.get(res, 0)) + int(data()["internal"]["yields"][res])
			income[int(r["from"])] = inc
	# Influence des traités : par partenaire, selon le palier.
	for e in state.empires:
		if e.eliminated or e.is_npc():
			continue
		for o in partners(state, e.id):
			var infl := int(tier_info(tier(state, e.id, o)).get("influence", 0))
			if infl != 0:
				var inc: Dictionary = income.get(e.id, {})
				inc["influence"] = int(inc.get("influence", 0)) + infl
				income[e.id] = inc
	state.trade["routes"] = routes
	state.trade["ints"] = ints
	state.trade["income"] = income
	_spawn_lairs(state, added)
	return added


static func _routes_of_empire(state: GameState, eid: int, routes: Array, ints: Dictionary) -> void:
	var cap := capacity(state, eid)
	var young := young_colonies(state, eid)
	var reserve := mini(reserved(state, eid), cap)
	var used := 0
	var capital := FactionTraits.capital_system(state, eid)
	var yi := 0
	while used < reserve and yi < young.size() and capital >= 0:
		if _add_internal(state, eid, capital, young[yi], routes, ints):
			used += 1
		yi += 1
	var cands := []
	for o in partners(state, eid):
		if embargoed(state, eid, o):
			continue
		var p := best_path(state, eid, o)
		if p.is_empty():
			continue
		cands.append([-raw_value(state, p), o, p])
	cands.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0] or (x[0] == y[0] and x[1] < y[1]))
	for c in cands:
		if used >= cap:
			break
		var p: Array[int] = c[2]
		routes.append({"from": eid, "to": int(c[1]), "kind": "ext", "path": p, "value": -int(c[0]),
				"tier": tier(state, eid, int(c[1]))})
		used += 1
	while used < cap and yi < young.size() and capital >= 0:
		if _add_internal(state, eid, capital, young[yi], routes, ints):
			used += 1
		yi += 1


static func _add_internal(state: GameState, eid: int, capital: int, pid: int, routes: Array, ints: Dictionary) -> bool:
	var sid := state.galaxy.get_planet(pid).system_id
	var p := path(state, capital, sid, eid, eid)
	if p.is_empty():
		return false
	routes.append({"from": eid, "to": eid, "kind": "int", "path": p, "value": 0, "tier": 0, "colony": pid})
	ints[pid] = 1
	return true


## Systèmes où se tient une flotte armée, avec ses propriétaires : {sid: [owners]}.
static func _hostile_presence(state: GameState) -> Dictionary:
	var out := {}
	for fid in state.sorted_fleet_ids():
		var f: Fleet = state.fleets[fid]
		if not Combat.is_armed(f):
			continue
		var l: Array = out.get(f.system_id, [])
		if not l.has(f.owner):
			l.append(f.owner)
		out[f.system_id] = l
	return out


static func _blocker(state: GameState, sid: int, a: int, b: int, armed: Dictionary) -> int:
	for o in armed.get(sid, []):
		var owner := int(o)
		if owner == a or owner == b:
			continue
		if owner == GameState.FAUNA_ID:
			for f in Fleets.fleets_at(state, sid, owner):
				if Combat.is_armed(f) and (Fauna.hostile(state, f, a) or Fauna.hostile(state, f, b)):
					return owner
			continue
		if Combat.at_war(state, owner, a) or Combat.at_war(state, owner, b):
			return owner
	return -1


static func _finish_route(state: GameState, r: Dictionary, armed: Dictionary) -> void:
	var a := int(r["from"])
	var b := int(r["to"])
	var p: Array = r["path"]
	r["blocked"] = false
	r["by"] = -1
	for sid in p:
		var bl := _blocker(state, int(sid), a, b, armed)
		if bl >= 0:
			r["blocked"] = true
			r["by"] = bl
			r["at"] = int(sid)
			break
	var loss := route_loss(state, r)
	r["loss"] = loss
	if String(r["kind"]) != "ext":
		r["net"] = 0
		return
	if bool(r["blocked"]):
		r["net"] = 0
		return
	var ti := tier_info(int(r["tier"]))
	var pct := 100 - int(ti.get("tariff_pct", 0)) + int(ti.get("bonus_pct", 0))
	@warning_ignore("integer_division")
	r["net"] = int(r["value"]) * (1000 - loss) / 1000 * pct / 100


## Part de la valeur volée par les pirates, en pour mille : le risque du système le plus exposé du
## chemin (hors bouts de la route), doublé près d'un repaire sous contrat contre un des deux bouts.
## Au plus 25 % (risque maximal), 50 % sous contrat : le plafond de la piraterie de Stellaris.
static func route_loss(state: GameState, r: Dictionary) -> int:
	var pd: Dictionary = data()["piracy"]
	var risk: Dictionary = state.trade.get("risk", {})
	if risk.is_empty():
		return 0
	var p: Array = r["path"]
	var a := int(r["from"])
	var b := int(r["to"])
	var worst := 0
	for i in range(1, p.size() - 1):
		var v := int(risk.get(int(p[i]), 0))
		if v > 0 and _incited_near(state, int(p[i]), a, b):
			v *= int(pd["incite_mult"])
		worst = maxi(worst, v)
	return mini(int(pd["loss_max"]), worst)


static func _incited_near(state: GameState, sid: int, a: int, b: int) -> bool:
	if state.lairs.is_empty():
		return false
	var j := FactionTraits.jumps_from(state.galaxy, sid)
	var rng := int(data()["piracy"]["lair_range"])
	for lid in Pirates.lair_ids(state):
		if int(j.get(lid, 999)) > rng:
			continue
		var lair: Dictionary = state.lairs[lid]
		var victim := int((lair["contract"] as Dictionary).get("victim", (lair["raid"] as Dictionary).get("victim", -1)))
		if victim >= 0 and (victim == a or victim == b):
			return true
	return false


## Un système est-il tenu (territoire d'un empire, ou une de ses flottes s'y trouve ou y patrouille) ?
static func policed(state: GameState, sid: int, fleet_at: Dictionary) -> bool:
	var o := state.system_owner(sid)
	if o >= 0 and not GameState.is_npc(o):
		return true
	return fleet_at.has(sid)


static func _update_risk(state: GameState, routes: Array) -> void:
	var pd: Dictionary = data()["piracy"]
	# Sans pirates en jeu, personne ne guette les cargos.
	if state.pirate_density == "aucun" or Pirates.density_def(state.pirate_density).is_empty():
		state.trade["risk"] = {}
		return
	var fleet_at := {}
	for fid in state.sorted_fleet_ids():
		var f: Fleet = state.fleets[fid]
		if GameState.is_npc(f.owner) or f.owner == GameState.FAUNA_ID:
			continue
		fleet_at[f.system_id] = true
		for s in f.patrol:
			fleet_at[int(s)] = true
	var on_route := {}
	for r: Dictionary in routes:
		var p: Array = r["path"]
		for i in range(1, p.size() - 1):
			on_route[int(p[i])] = true
	var risk: Dictionary = state.trade.get("risk", {})
	var lair_near := {}
	if not state.lairs.is_empty():
		for lid in Pirates.lair_ids(state):
			var j := FactionTraits.jumps_from(state.galaxy, lid)
			for sid in on_route:
				if int(j.get(sid, 999)) <= int(pd["lair_range"]):
					lair_near[sid] = true
	var ids := on_route.keys()
	for sid in risk:
		if not on_route.has(sid):
			ids.append(sid)
	ids.sort()
	var out := {}
	for sid in ids:
		var v := int(risk.get(sid, 0))
		if on_route.has(sid) and not policed(state, int(sid), fleet_at):
			v += int(pd["risk_per_month"]) + (int(pd["lair_bonus"]) if lair_near.has(sid) else 0)
		else:
			v -= int(pd["risk_decay"])
		v = clampi(v, 0, int(pd["risk_max"]))
		if v > 0:
			out[int(sid)] = v
	state.trade["risk"] = out


## Un risque au maximum fait naître un repaire dans le système (si les pirates sont en jeu).
static func _spawn_lairs(state: GameState, added: Array[Dictionary]) -> void:
	if state.pirate_density == "aucun" or Pirates.density_def(state.pirate_density).is_empty():
		return
	var pd: Dictionary = data()["piracy"]
	var risk: Dictionary = state.trade.get("risk", {})
	var ids := risk.keys()
	ids.sort()
	for sid in ids:
		if int(risk[sid]) < int(pd["spawn_at"]) or state.system_owner(int(sid)) >= 0 or state.lairs.has(int(sid)):
			continue
		var j := FactionTraits.jumps_from(state.galaxy, int(sid))
		var near := false
		for lid in state.lairs:
			if int(j.get(int(lid), 999)) < int(pd["spawn_min_jumps"]):
				near = true
				break
		if near:
			continue
		Pirates.create_lair(state, int(sid))
		risk.erase(sid)
		added.append(state.add_chronicle("Des forbans s'installent à %s, sur une route marchande que personne ne gardait. Ils appellent ça un péage." % [
				state.galaxy.systems[int(sid)].system_name], Espionage.public_to(state, [])))
		return


# --- Lecture ------------------------------------------------------------------------------------

## Revenu mensuel du commerce d'un empire (calculé au dernier bilan).
static func income(state: GameState, empire_id: int) -> Dictionary:
	return state.trade.get("income", {}).get(empire_id, {})


## Routes qui touchent un empire (envoyées ou reçues).
static func routes_of(state: GameState, empire_id: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r: Dictionary in state.trade.get("routes", []):
		if int(r["from"]) == empire_id or int(r["to"]) == empire_id:
			out.append(r)
	return out


## Routes envoyées par un empire (celles qui occupent sa capacité).
static func sent_by(state: GameState, empire_id: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r: Dictionary in state.trade.get("routes", []):
		if int(r["from"]) == empire_id:
			out.append(r)
	return out


## Valeur nette des routes entre a et b ce mois-ci (dans les deux sens).
static func value_between(state: GameState, a: int, b: int) -> int:
	var n := 0
	for r: Dictionary in state.trade.get("routes", []):
		if String(r["kind"]) == "ext" and ((int(r["from"]) == a and int(r["to"]) == b) or (int(r["from"]) == b and int(r["to"]) == a)):
			n += int(r["net"])
	return n


## Estimation de la valeur d'une route entre a et b (pour l'IA et l'interface, avant signature).
static func estimate(state: GameState, a: int, b: int) -> int:
	var p := best_path(state, a, b)
	return 0 if p.is_empty() else raw_value(state, p)


## Colonie desservie par une route intérieure ce mois-ci ?
static func served(state: GameState, planet_id: int) -> bool:
	return state.trade.get("ints", {}).has(planet_id)


static func internal_growth(state: GameState, planet_id: int) -> int:
	if not served(state, planet_id):
		return 0
	return int(data()["internal"]["growth_per_day"])


static func risk_at(state: GameState, sid: int) -> int:
	return int(state.trade.get("risk", {}).get(sid, 0))


# --- Sauvegarde --------------------------------------------------------------------------------

static func to_dict(state: GameState) -> Dictionary:
	var t: Dictionary = state.trade
	var routes := []
	for r: Dictionary in t.get("routes", []):
		routes.append(r.duplicate(true))
	return {"routes": routes, "risk": _pairs(t.get("risk", {})), "reserve": _pairs(t.get("reserve", {})),
			"ints": _pairs(t.get("ints", {})), "income": _income_list(t.get("income", {}))}


static func from_dict(state: GameState, d: Dictionary) -> void:
	var t := {}
	var routes := []
	for r: Dictionary in d.get("routes", []):
		var v: Dictionary = GameData._to_ints(r)
		v["kind"] = String(v["kind"])
		var p: Array[int] = []
		for s in r.get("path", []):
			p.append(int(s))
		v["path"] = p
		v["blocked"] = bool(r.get("blocked", false))
		routes.append(v)
	t["routes"] = routes
	t["risk"] = _unpairs(d.get("risk", []))
	t["reserve"] = _unpairs(d.get("reserve", []))
	t["ints"] = _unpairs(d.get("ints", []))
	var inc := {}
	for it: Dictionary in d.get("income", []):
		var res := {}
		for k in it.get("res", {}):
			res[String(k)] = int(it["res"][k])
		inc[int(it["empire"])] = res
	t["income"] = inc
	state.trade = t


static func _pairs(d: Dictionary) -> Array:
	var ids := d.keys()
	ids.sort()
	var out := []
	for k in ids:
		out.append([int(k), int(d[k])])
	return out


static func _unpairs(a: Array) -> Dictionary:
	var out := {}
	for p in a:
		out[int(p[0])] = int(p[1])
	return out


static func _income_list(d: Dictionary) -> Array:
	var ids := d.keys()
	ids.sort()
	var out := []
	for k in ids:
		var res := {}
		var keys: Array = (d[k] as Dictionary).keys()
		keys.sort()
		for r in keys:
			res[r] = int(d[k][r])
		out.append({"empire": int(k), "res": res})
	return out
