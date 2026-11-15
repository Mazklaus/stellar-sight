class_name CultureLife
extends RefCounted
## Rayonnement culturel, lot 2 (étude du 2026-11-15) : ce que font les paliers. Savoir par route et
## routes plus riches (prop. 21), opinion et lassitude de guerre (22), osmose des lois (23) et des
## savoirs (24), pression sur les courants et « Vivre comme eux » (25), défection culturelle à compte à
## rebours (26 ; Galactic Civilizations : défection à 4×), migrants et peuples mineurs (27), victoire
## « Le Grand Rayonnement » (32), score et conquête (33). Les merveilles culturelles (9) sont des
## bâtiments (data/buildings.json, champ culture_wonder) lus par Culture.source_parts.
##
## État ajouté à state.culture : "offer": {cible: {"law", "from", "until"}}, "refus": {empire: jour de fin},
## "osm_cd": {empire: jour}, "def": {système: {"to", "from", "end"}}, "def_last": {empire: jour},
## "alert": {empire: palier d'alerte}, "vic": {empire: 1}.


static func data() -> Dictionary:
	return Culture.data()


static func ef() -> Dictionary:
	return data()["effects"]


static func daily(state: GameState, added: Array[Dictionary]) -> void:
	CultureBridges.daily(state, added)


# --- Revenu et effets lus ailleurs (props 21, 22, 27) -------------------------------------------

## Revenu culturel du mois : Savoir des routes vers les empires où l'on est Familier ou mieux, énergie
## des stations de villégiature (population à trois sauts ou moins).
static func income_of(state: GameState, eid: int) -> Dictionary:
	var out := {}
	var kn := 0
	var from := int(ef()["knowledge_route_from"])
	for b in Culture.living(state):
		if b == eid:
			continue
		var t := Culture.tier(state, eid, b)
		if t >= from:
			kn += Culture._routes_between(state, eid, b) * (1 + (t - from) * int(ef()["knowledge_per_tier"]))
	if kn > 0:
		out["knowledge"] = kn
	var st: Dictionary = data()["station"]
	var en := 0
	for pid in Culture._with_building(state, eid, "villegiature"):
		var sid := state.galaxy.get_planet(pid).system_id
		var jumps := FactionTraits.jumps_from(state.galaxy, sid)
		var pop := 0
		for s in jumps:
			if int(jumps[s]) > int(st["jumps"]):
				continue
			for p2 in state.galaxy.systems[int(s)].planet_ids:
				var c: Colony = state.colonies.get(p2)
				if c != null and c.is_colony() and c.is_established() and not GameState.is_npc(c.owner):
					pop += c.population
		@warning_ignore("integer_division")
		en += mini(int(st["energy_max"]), pop / maxi(1, int(st["pop_div"])))
	if en > 0:
		out["energy"] = en
	return out


## Routes commerciales de who vers other : +25 % de revenu quand who est Influent ou mieux chez other.
static func route_pct(state: GameState, who: int, other: int) -> int:
	if state.culture.is_empty():
		return 0
	return int(ef()["route_energy_pct"]) if Culture.tier(state, who, other) >= int(ef()["route_energy_from"]) else 0


## Opérations d'espionnage de a chez b : 50 % plus rapides quand a y est Influent ou mieux (durée -33 %).
static func spy_days_pct(state: GameState, a: int, b: int) -> int:
	if state.culture.is_empty() or Culture.tier(state, a, b) < int(ef()["spy_fast_from"]):
		return 0
	@warning_ignore("integer_division")
	return -100 * int(ef()["spy_fast_pct"]) / (100 + int(ef()["spy_fast_pct"]))


## Lassitude de guerre : attaquer un empire dont la culture est Influente chez soi lasse 50 % plus vite.
static func war_ex_pct(state: GameState, rec: Dictionary, eid: int) -> int:
	if state.culture.is_empty() or int(rec.get("a", -1)) != eid:
		return 0
	var d := int(rec.get("d", -1))
	return int(ef()["war_lassitude_pct"]) if d >= 0 and Culture.tier(state, d, eid) >= int(ef()["war_lassitude_from"]) else 0


## Migrants (prop. 27) : partir vers un empire dont la culture est En vogue chez soi tente davantage.
static func migrant_pull(state: GameState, home: int, dest: int) -> int:
	if state.culture.is_empty() or home == dest:
		return 0
	var t := Culture.tier(state, dest, home)
	return maxi(0, t - int(ef()["migrant_pull_from"]) + 1) * 60


## Stabilité (props 23 et 25) : refus d'une osmose, « Vivre comme eux ».
static func stability_parts(state: GameState, sid: int, owner: int) -> Array:
	var out := []
	if state.culture.is_empty() or GameState.is_npc(owner):
		return out
	var until := int(state.culture.get("refus", {}).get(str(owner), 0))
	if until > state.tick:
		out.append(["Modèle étranger refusé (osmose)", int(ef()["law_refuse_stability"])])
	var top := Culture.top_influencer(state, owner)
	if int(top[0]) >= int(ef()["live_like_them_from"]) and sid != FactionTraits.capital_system(state, owner):
		var v := int(Stability.entry(state, sid).get("v", 50))
		if v < int(ef()["live_like_them_stab"]):
			out.append(["« Vivre comme eux » (%s)" % state.get_empire(int(top[1])).display_name(), int(ef()["live_like_them"])])
	return out


# --- Bilan mensuel ------------------------------------------------------------------------------

static func monthly(state: GameState, ids: Array[int], added: Array[Dictionary]) -> void:
	for b in ids:
		_offer_law(state, b, added)
		_push_currents(state, b)
	_minors(state, ids)
	_defection(state, ids, added)
	_alerts(state, ids, added)


## Osmose des lois (prop. 23) : l'empire le plus influent (En vogue ou mieux) propose une de ses lois.
static func _offer_law(state: GameState, b: int, added: Array[Dictionary]) -> void:
	if not state.politics_on or not Laws.applies(state, b):
		return
	var offers := Culture._m(state, "offer")
	var cur: Dictionary = offers.get(str(b), {})
	if not cur.is_empty():
		if state.tick >= int(cur["until"]):
			answer_law(state, b, false, added)
		return
	if state.tick < int(state.culture.get("osm_cd", {}).get(str(b), 0)):
		return
	var top := Culture.top_influencer(state, b)
	if int(top[0]) < int(ef()["law_osmosis_from"]):
		return
	var a := int(top[1])
	if not Laws.applies(state, a):
		return
	for lid in Laws.enacted(state, a):
		if law_ok(state, b, String(lid)):
			offers[str(b)] = {"law": String(lid), "from": a, "until": state.tick + 60}
			Culture._m(state, "osm_cd")[str(b)] = state.tick + int(ef()["law_osmosis_cd"])
			added.append(state.add_chronicle("Osmose culturelle : chez %s, on réclame « %s », une loi de %s dont tout le monde parle. Deux mois pour l'adopter (gratuitement) ou la refuser." % [
					state.get_empire(b).display_name(), String(Laws.law_def(String(lid)).get("label", lid)), state.get_empire(a).display_name()], [a, b]))
			if state.get_empire(b).is_ai():
				answer_law(state, b, _ai_accepts(state, b, a), added)
			return


## La loi peut-elle passer chez b par osmose (tout sauf le coût, qui est offert) ?
static func law_ok(state: GameState, b: int, lid: String) -> bool:
	var why := Laws.check_adopt(state, b, lid)
	return why == "" or why.begins_with("pas assez d'influence")


static func _ai_accepts(state: GameState, b: int, a: int) -> bool:
	var tmp := String(state.get_empire(b).ai_temperament)
	if tmp == "belliqueux" or Diplomacy.opinion(state, b, a) < -20:
		return false
	return true


static func check_answer(state: GameState, b: int) -> String:
	if state.culture.is_empty():
		return "pas de rayonnement dans cette partie"
	if (state.culture.get("offer", {}) as Dictionary).get(str(b), {}).is_empty():
		return "aucune loi proposée par osmose"
	return ""


static func answer_law(state: GameState, b: int, accept: bool, added: Array[Dictionary]) -> void:
	var offers := Culture._m(state, "offer")
	var cur: Dictionary = offers.get(str(b), {})
	offers.erase(str(b))
	if cur.is_empty():
		return
	var a := int(cur["from"])
	var lid := String(cur["law"])
	var lname := String(Laws.law_def(lid).get("label", lid))
	if accept and law_ok(state, b, lid):
		var en := Laws._w(state, b)
		(en["laws"] as Array).append(lid)
		state.relic_rev += 1
		Diplomacy.remember(state, b, a, "culture_osmose")
		Diplomacy.remember(state, a, b, "culture_osmose")
		added.append(state.add_chronicle("%s adopte « %s », à la manière de %s. Les puristes grincent ; la jeunesse applaudit." % [
				state.get_empire(b).display_name(), lname, state.get_empire(a).display_name()], [a, b]))
	else:
		Culture._m(state, "refus")[str(b)] = state.tick + int(ef()["law_refuse_days"])
		Diplomacy.remember(state, a, b, "culture_refus")
		added.append(state.add_chronicle("%s refuse « %s » : on ne vivra pas comme chez %s. La rue gronde un an." % [
				state.get_empire(b).display_name(), lname, state.get_empire(a).display_name()], [a, b]))


static func pending_offer(state: GameState, b: int) -> Dictionary:
	if state.culture.is_empty():
		return {}
	return (state.culture.get("offer", {}) as Dictionary).get(str(b), {})


## Pression sur les courants (prop. 25) : la culture En vogue pousse son courant principal chez la cible.
static func _push_currents(state: GameState, b: int) -> void:
	if not state.politics_on or not Politics.applies(state, b):
		return
	var top := Culture.top_influencer(state, b)
	if int(top[0]) < int(ef()["current_push_from"]) or not Politics.applies(state, int(top[1])):
		return
	var i := Politics.principal(state, int(top[1]))
	var pts := int(ef()["current_push"]) * (int(top[0]) - int(ef()["current_push_from"]) + 1)
	for sid in Stability.systems_of(state, b):
		Politics.push(state, sid, i, pts)


## Peuples mineurs (prop. 27) : Influent ou mieux, +1 faveur par mois.
static func _minors(state: GameState, ids: Array[int]) -> void:
	if state.minors.is_empty():
		return
	for a in ids:
		for mid in Minors.met(state, a):
			if Culture.tier(state, a, mid) >= int(ef()["minor_favor_from"]):
				Minors.add_fav(state, mid, a, int(ef()["minor_favor"]))


# --- Osmose des savoirs (prop. 24) --------------------------------------------------------------

## Technologies que b peut acquérir par osmose : connues d'un empire En vogue ou mieux chez b.
static func tech_offers(state: GameState, b: int) -> Array[String]:
	var out: Array[String] = []
	if state.culture.is_empty():
		return out
	var eb := state.get_empire(b)
	for a in Culture.living(state):
		if a == b or Culture.tier(state, a, b) < int(ef()["tech_osmosis_from"]):
			continue
		var ea := state.get_empire(a)
		var ks := ea.techs.keys()
		ks.sort()
		for tid in ks:
			var t := String(tid)
			if not eb.techs.has(t) and not out.has(t) and Research.is_available(state, b, t) and not Victory.is_people(String(Research.tech(t).get("victory", ""))):
				out.append(t)
	return out


static func tech_cost(state: GameState, b: int, tid: String) -> Dictionary:
	var pct := int(ef()["tech_osmosis_pct"]) * maxi(10, 100 + Culture.tal(state, b, "tech_osmosis_cost_pct")) / 100
	@warning_ignore("integer_division")
	return {"energy": maxi(1, Research.cost(state, b, tid) * pct / 100)}


static func check_tech(state: GameState, b: int, tid: String) -> String:
	if not tech_offers(state, b).has(tid):
		return "aucune culture influente ne vous ouvre cette technologie"
	var cost := tech_cost(state, b, tid)
	if not Economy.can_afford(state.get_empire(b), cost):
		return "pas assez d'énergie (%s)" % GameData.format_amounts(cost)
	return ""


static func buy_tech(state: GameState, b: int, tid: String, added: Array[Dictionary]) -> void:
	Economy.pay(state.get_empire(b), tech_cost(state, b, tid))
	Research.grant(state, b, [tid])
	added.append(state.add_chronicle("%s apprend « %s » par osmose : les manuels étrangers se traduisent tout seuls quand on aime leurs auteurs." % [
			state.get_empire(b).display_name(), String(Research.tech(tid).get("label", tid))], [b]))


# --- Défection culturelle (prop. 26) ------------------------------------------------------------

static func _defection(state: GameState, ids: Array[int], added: Array[Dictionary]) -> void:
	var dm := Culture.defect_mode(state)
	var runs := Culture._m(state, "def")
	if dm == "aucune" or not data()["defect"].has(dm):
		runs.clear()
		return
	var cfg: Dictionary = data()["defect"][dm]
	# Comptes à rebours en cours : vérifiés, puis achevés.
	var keys := runs.keys()
	keys.sort()
	for k in keys:
		var r: Dictionary = runs[k]
		var sid := int(k)
		var from := int(r["from"])
		var to := int(r["to"])
		if not _defect_ok(state, sid, from, to, cfg):
			runs.erase(k)
			added.append(state.add_chronicle("%s renonce à rejoindre %s : le calme revient, ou la culture d'en face s'essouffle." % [
					state.galaxy.systems[sid].system_name, state.get_empire(to).display_name()], [from, to]))
			continue
		if state.tick >= int(r["end"]):
			runs.erase(k)
			_defect(state, sid, from, to, added)
	# Nouveaux comptes à rebours : au plus un par empire et par an.
	for b in ids:
		if state.tick - int(state.culture.get("def_last", {}).get(str(b), -100000)) < 360 * int(data()["defect"]["per_year"]):
			continue
		var cap := FactionTraits.capital_system(state, b)
		for sid in Stability.systems_of(state, b):
			if sid == cap or runs.has(str(sid)):
				continue
			var to := _defect_target(state, sid, b, cfg)
			if to < 0:
				continue
			runs[str(sid)] = {"from": b, "to": to, "end": state.tick + int(data()["defect"]["days"])}
			Culture._m(state, "def_last")[str(b)] = state.tick
			added.append(state.add_chronicle("Défection culturelle en vue : %s, instable et fasciné par %s, pourrait changer de drapeau dans %s." % [
					state.galaxy.systems[sid].system_name, state.get_empire(to).display_name(), Victory._days_text(int(data()["defect"]["days"]))], [b, to]))
			break


static func _defect_target(state: GameState, sid: int, b: int, cfg: Dictionary) -> int:
	if int(Stability.entry(state, sid).get("v", 50)) > int(cfg["max_stab"]):
		return -1
	var jumps := FactionTraits.jumps_from(state.galaxy, sid)
	var best := -1
	for a in Culture.living(state):
		if a == b or not _defect_ok(state, sid, b, a, cfg):
			continue
		if best < 0 or Culture.last(state, a, b) > Culture.last(state, best, b):
			best = a
	return best


static func _defect_ok(state: GameState, sid: int, b: int, a: int, cfg: Dictionary) -> bool:
	if state.system_owner(sid) != b or sid == FactionTraits.capital_system(state, b):
		return false
	var ea := state.get_empire(a)
	var eb := state.get_empire(b)
	if ea == null or eb == null or ea.eliminated or not eb.wars.is_empty() or Culture.at_war(state, a, b):
		return false
	if not Research.knows(state, a, String(data()["defect"]["tech"])):
		return false
	if int(Stability.entry(state, sid).get("v", 50)) > int(cfg["max_stab"]):
		return false
	if Culture.tier(state, a, b) < 4 or Culture.last(state, a, b) < int(cfg["ratio"]) * maxi(1, Culture.radiance(state, b)):
		return false
	var jumps := FactionTraits.jumps_from(state.galaxy, sid)
	for s in jumps:
		if int(jumps[s]) <= int(data()["defect"]["jumps"]) and state.system_owner(int(s)) == a:
			return true
	return false


static func _defect(state: GameState, sid: int, from: int, to: int, added: Array[Dictionary]) -> void:
	Stability._transfer(state, sid, from, to)
	state.stability.erase(sid)
	Economy.clear_wonders()
	Movements.on_secession(state, sid, from, to, added)
	added.append(state.add_chronicle("Défection culturelle ! %s quitte %s et rejoint %s, sans un coup de feu : on y parlait déjà leur langue, on y chantait déjà leurs chansons." % [
			state.galaxy.systems[sid].system_name, state.get_empire(from).display_name(), state.get_empire(to).display_name()], Espionage.public_to(state, [from, to])))


## Comptes à rebours de défection en cours qui touchent un empire : [[système, vers, jours restants], …].
static func defections_of(state: GameState, eid: int) -> Array:
	var out := []
	if state.culture.is_empty():
		return out
	var runs: Dictionary = state.culture.get("def", {})
	var keys := runs.keys()
	keys.sort()
	for k in keys:
		var r: Dictionary = runs[k]
		if int(r["from"]) == eid or int(r["to"]) == eid:
			out.append([int(k), int(r["to"]), maxi(0, int(r["end"]) - state.tick), int(r["from"])])
	return out


# --- Victoire (props 32 et 35) ------------------------------------------------------------------

## Empires survivants rencontrés où e est Influent ou mieux : [atteints, à atteindre].
static func influent_count(state: GameState, eid: int) -> Array:
	var n := 0
	var need := 0
	var e := state.get_empire(eid)
	for b in Culture.living(state):
		if b == eid or not e.contacts.has(b):
			continue
		need += 1
		if Culture.tier(state, eid, b) >= int(data()["victory"]["tier"]):
			n += 1
	return [n, need]


static func victory_rayonnement(state: GameState, e: Empire, out: Dictionary) -> void:
	if state.culture.is_empty():
		out["lines"].append("Pas de rayonnement dans cette partie.")
		return
	var c := influent_count(state, e.id)
	var others := Culture.living(state).size() - 1
	var need := maxi(int(Victory.info("rayonnement").get("min_rivals", 2)), others)
	out["lines"].append("Influent chez %d empire(s) sur %d survivant(s)" % [int(c[0]), others])
	if int(c[1]) < others:
		out["lines"].append("Il reste %d empire(s) à rencontrer" % (others - int(c[1])))
	out["cond"] = others >= int(Victory.info("rayonnement").get("min_rivals", 2)) and int(c[0]) >= others
	Victory._timed(out, int(c[0]), need)


static func foreign_pop_share(state: GameState, eid: int) -> Array:
	var tot := 0
	var mine := 0
	var e := state.get_empire(eid)
	for b in Culture.living(state):
		if b == eid or not e.contacts.has(b):
			continue
		var p := 0
		for sid in Stability.systems_of(state, b):
			p += Stability.system_pop(state, sid, b)
		tot += p
		if Culture.tier(state, eid, b) >= int(data()["victory"]["tier"]):
			mine += p
	return [mine, tot]


static func victory_idole(state: GameState, e: Empire, out: Dictionary) -> void:
	if state.culture.is_empty():
		out["lines"].append("Pas de rayonnement dans cette partie.")
		return
	var sh := foreign_pop_share(state, e.id)
	var want := int(Victory.info("idole").get("pct", 60))
	@warning_ignore("integer_division")
	var pct := int(sh[0]) * 100 / maxi(1, int(sh[1]))
	out["lines"].append("Population étrangère sous votre charme : %d %% (il en faut %d %%)" % [pct, want])
	out["cond"] = int(sh[1]) > 0 and pct >= want
	Victory._timed(out, pct, want)


## Alertes à la galaxie (prop. 32) : à la moitié puis aux trois quarts des empires survivants.
static func _alerts(state: GameState, ids: Array[int], added: Array[Dictionary]) -> void:
	if not Victory.enabled(state, "rayonnement"):
		return
	var al := Culture._m(state, "alert")
	var others := ids.size() - 1
	if others < 1:
		return
	for a in ids:
		var c := influent_count(state, a)
		@warning_ignore("integer_division")
		var pct := int(c[0]) * 100 / others
		var lvl := 0
		for step in data()["victory"]["alerts"]:
			if pct >= int(step):
				lvl = int(step)
		var old := int(al.get(str(a), 0))
		if lvl > old:
			added.append(state.add_chronicle("Alerte culturelle : la culture de %s est Influente chez %d %% des empires. Le Grand Rayonnement approche : fermez vos frontières, ou apprenez leurs chansons." % [
					state.get_empire(a).display_name(), pct], []))
		al[str(a)] = lvl


# --- Conquête (prop. 33) ------------------------------------------------------------------------

## Système pris : le conquérant emporte les reliques exposées si le Musée galactique y était ; les
## hordes et l'Essaim gagnent du Patrimoine.
static func on_capture(state: GameState, sid: int, new_owner: int, old_owner: int, added: Array[Dictionary]) -> void:
	if GameState.is_npc(new_owner) or GameState.is_npc(old_owner) or old_owner < 0:
		return
	var ch := Culture.tal(state, new_owner, "conquest_heritage")
	if ch > 0:
		var pat := Culture._m(state, "pat")
		pat[str(new_owner)] = Culture.heritage(state, new_owner) + ch
	var had := false
	for pid in state.galaxy.systems[sid].planet_ids:
		var c: Colony = state.colonies.get(pid)
		if c != null and c.buildings.has("musee_galactique"):
			had = true
	if not had or state.relics.is_empty():
		return
	var ex: Array = state.culture.get("exp", {}).get(str(old_owner), [])
	var took: Array[String] = []
	for rid in ex:
		if int(state.relics.get(String(rid), {}).get("owner", -1)) == old_owner:
			Relics.gain(state, new_owner, String(rid))
			took.append(String(Relics.def(String(rid)).get("name", rid)))
	if not took.is_empty():
		state.culture["exp"].erase(str(old_owner))
		added.append(state.add_chronicle("Pillage du Musée galactique : %s emporte %s. Les conservateurs de %s pleurent dans les vitrines vides." % [
				state.get_empire(new_owner).display_name(), ", ".join(took), state.get_empire(old_owner).display_name()], [new_owner, old_owner]))
