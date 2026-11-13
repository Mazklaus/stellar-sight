class_name FaithWars
extends RefCounted
## Religion, lot 2 (étude « Religion », propositions 11 à 17 et 25, plus le Culte du Je) : zèle,
## hérésies et schismes, lois de culte et doléance « Liberté de culte », missions, guerre sainte et
## croisade, cultes cachés, prophétie plantée, natures de foi, drones dissidents des ruches.
## Règles : data/faiths.json (zeal, heresy, cult, missions, holy_war, secret, prophecy, natures, je).
##
## Clés de state.faiths ajoutées par ce lot :
## - "missions" : [{"by", "sid", "fid", "end"}] ;
## - "wards" : {système: jour de fin de la protection} ;
## - "crusades" : {foi: {"target", "end", "next"}} (next : prochaine croisade possible) ;
## - "holy_wars" : [{"a", "b", "fid"}] guerres saintes en cours ;
## - "seen" : {empire: [fois cachées découvertes]} ;
## - "prophecies" : {planète: {"by", "fid", "at"}} ;
## - "je" : {planète: {"n", "tol"}} drones dissidents, et {"block:planète": jour} ;
## - "stab" : {système: [{"label", "v", "end"}]} lignes de stabilité temporaires ;
## - "demands" : {empire: {"end", "next", "ok_end", "fail_end"}} doléance « Liberté de culte ».


static func data() -> Dictionary:
	return GameData.faiths()


static func fix_ints(state: GameState) -> void:
	var ms: Array = []
	for m in _missions(state):
		ms.append({"by": int(m["by"]), "sid": int(m["sid"]), "fid": String(m["fid"]), "end": int(m["end"])})
	state.faiths["missions"] = {"list": ms}
	for k in state.faiths["wards"]:
		state.faiths["wards"][k] = int(state.faiths["wards"][k])
	for k in state.faiths["crusades"]:
		var c: Dictionary = state.faiths["crusades"][k]
		for f in ["target", "end", "next"]:
			c[f] = int(c.get(f, -1))
	var hw: Array = []
	for w in state.faiths["holy_wars"].get("list", []):
		hw.append({"a": int(w["a"]), "b": int(w["b"]), "fid": String(w["fid"])})
	state.faiths["holy_wars"] = {"list": hw}
	for k in state.faiths["prophecies"]:
		var p: Dictionary = state.faiths["prophecies"][k]
		p["by"] = int(p["by"])
		p["at"] = int(p["at"])
	for k in state.faiths["je"]:
		var v: Variant = state.faiths["je"][k]
		if v is Dictionary:
			v["n"] = int(v["n"])
			v["tol"] = bool(v.get("tol", false))
		else:
			state.faiths["je"][k] = int(v)
	for k in state.faiths["stab"]:
		for l: Dictionary in state.faiths["stab"][k]:
			l["v"] = int(l["v"])
			l["end"] = int(l["end"])
	for k in state.faiths["demands"]:
		var d: Dictionary = state.faiths["demands"][k]
		for f in d:
			d[f] = int(d[f])


static func _missions(state: GameState) -> Array:
	var m: Variant = state.faiths.get("missions", {})
	if m is Dictionary:
		return (m as Dictionary).get("list", [])
	return []


static func _holy_wars(state: GameState) -> Array:
	var m: Variant = state.faiths.get("holy_wars", {})
	if m is Dictionary:
		return (m as Dictionary).get("list", [])
	return []


static func _h(state: GameState, salt: Array) -> int:
	return absi(hash([state.seed_value] + salt))


# --- Zèle (proposition 11) -----------------------------------------------------------------------

static func zeal(state: GameState, fid: String) -> int:
	return int(Faiths.faith(state, fid).get("zeal", 50))


static func add_zeal(state: GameState, fid: String, v: int) -> void:
	var f := Faiths.faith(state, fid)
	if not f.is_empty():
		f["zeal"] = clampi(int(f.get("zeal", 50)) + v, 0, 100)


static func _zeal_month(state: GameState, fid: String) -> void:
	var zd: Dictionary = data()["zeal"]
	var f := Faiths.faith(state, fid)
	var holy_c: Colony = state.colonies.get(int(f["holy"]))
	var v := 0
	if holy_c != null and not GameState.is_npc(holy_c.owner):
		v += int(zd["holy_held"]) if Faiths.state_faith(state, holy_c.owner) == fid else int(zd["holy_lost"])
	var hsid := state.galaxy.get_planet(int(f["holy"])).system_id
	var dist := FactionTraits.jumps_from(state.galaxy, hsid)
	var founder_f := Peoples.founder_of(state, int(f["founder"]))
	var total := 0
	var far := 0
	var foreign := 0
	for pid in state.colonies:
		var c: Colony = state.colonies[pid]
		var n := int(c.faith.get(fid, 0))
		if n <= 0:
			continue
		total += n
		if int(dist.get(state.galaxy.get_planet(pid).system_id, 99)) > int(zd["far_jumps"]):
			far += n
		if Peoples.founder_of(state, c.owner) != founder_f:
			foreign += n
	if total > 0:
		if far * 100 > total * int(zd["far_share_pct"]):
			v += int(zd["far"])
		if foreign * 100 > total * int(zd["foreign_share_pct"]):
			v += int(zd["foreign"])
	if nature(state, fid) == "precurseurs" and _relics_of_faith(state, fid) >= int(zd["relics_n"]):
		v += int(zd["relics"])
	var z := int(f.get("zeal", 50))
	if z > int(zd["drift_above"]):
		v -= 1
	elif z < int(zd["drift_below"]):
		v += 1
	f["zeal"] = clampi(z + v, 0, 100)


# --- Natures (proposition 25) --------------------------------------------------------------------

static func nature(state: GameState, fid: String) -> String:
	return String(Faiths.faith(state, fid).get("nature", ""))


static func nature_def(nid: String) -> Dictionary:
	return data()["natures"]["list"].get(nid, {})


static func pick_nature(state: GameState, eid: int, fid: String) -> String:
	var nd: Dictionary = data()["natures"]
	var e := state.get_empire(eid)
	if e != null and nd["forced"].has(e.faction_id):
		return String(nd["forced"][e.faction_id])
	var reg := Events.layer_value(state, eid, "registre") if e != null else ""
	if nd["by_register"].has(reg):
		return String(nd["by_register"][reg])
	var ks: Array = (nd["list"] as Dictionary).keys()
	ks.sort()
	return String(ks[_h(state, ["nature", fid]) % ks.size()])


static func nature_holy_pct(state: GameState, fid: String) -> int:
	return int(data()["natures"]["voies_holy_pct"]) if nature(state, fid) == "voies_sacrees" else 0


static func nature_route_pct(state: GameState, fid: String) -> int:
	return int(data()["natures"]["meme_route_pct"]) if nature(state, fid) == "meme" else 0


## Effets de la nature pour les empires de cette foi (mêmes clés que les technologies).
static func nature_fx(state: GameState, fid: String) -> Dictionary:
	if nature(state, fid) == "voies_sacrees":
		return {"fleet_speed_pct": int(data()["natures"]["voies_speed"])}
	return {}


static func _relics_of_faith(state: GameState, fid: String) -> int:
	var n := 0
	for e in state.empires:
		if not e.eliminated and Faiths.state_faith(state, e.id) == fid:
			n += Relics.owned(state, e.id).size()
	return n


## Précurseurs : multiplicateur de prêche de la capitale d'un empire de la foi qui tient des reliques.
static func secondary_holy_x(state: GameState, fid: String, c: Colony) -> int:
	if nature(state, fid) != "precurseurs" or GameState.is_npc(c.owner):
		return 1
	var e := state.get_empire(c.owner)
	if e == null or e.capital_planet != c.planet_id or Faiths.state_faith(state, c.owner) != fid:
		return 1
	var n := Relics.owned(state, c.owner).size()
	return 1 if n <= 0 else (2 if n < 3 else 3)


## Parasite saint : croissance des colonies où il domine.
static func growth_pct(state: GameState, c: Colony) -> int:
	if not state.faith_on or c.faith.is_empty():
		return 0
	var m := Faiths.majority(c)
	if m != Faiths.NATIVE and nature(state, m) == "parasite":
		return int(data()["natures"]["parasite_growth_pct"])
	return 0


## Parasite saint : un monde conquis par un empire de cette foi se convertit à moitié.
@warning_ignore("integer_division")
static func on_conquest(state: GameState, c: Colony, conqueror: int) -> void:
	if not state.faith_on or not c.is_colony() or GameState.is_npc(conqueror):
		return
	var sf := Faiths.state_faith(state, conqueror)
	if sf == Faiths.LAICITE or nature(state, sf) != "parasite":
		return
	var n := c.population * int(data()["natures"]["parasite_conquest_pct"]) / 100
	for _i in n:
		if int(c.faith.get(sf, 0)) >= c.population or not Faiths._convert_one(c, sf):
			break


## Pressions du lot 2 ajoutées à Faiths.pressures (en centièmes) : missions, flottes du parasite
## saint, réseaux d'espionnage du mème.
static func extra_pressures(state: GameState, out: Dictionary, targets_by_sys: Dictionary) -> void:
	var md: Dictionary = data()["missions"]
	for m in _missions(state):
		var sid := int(m["sid"])
		if not targets_by_sys.has(sid):
			continue
		for pid in targets_by_sys[sid]:
			var pm: Dictionary = out.get(pid, {})
			pm[String(m["fid"])] = int(pm.get(String(m["fid"]), 0)) + int(md["pressure"]) * 100
			out[pid] = pm
	# Parasite saint : chaque flotte d'un empire de la foi porte l'organisme là où elle stationne.
	var fp := int(data()["natures"]["fleet_pressure"]) * 100
	for fl_id in state.sorted_fleet_ids():
		var fl: Fleet = state.fleets[fl_id]
		if GameState.is_npc(fl.owner) or fl.is_moving() or not targets_by_sys.has(fl.system_id):
			continue
		var sf := Faiths.state_faith(state, fl.owner)
		if sf == Faiths.LAICITE or nature(state, sf) != "parasite":
			continue
		for pid in targets_by_sys[fl.system_id]:
			var pm: Dictionary = out.get(pid, {})
			pm[sf] = int(pm.get(sf, 0)) + fp
			out[pid] = pm
	# Mème : un réseau d'espionnage porte la foi dans les deux sens, jusqu'aux capitales.
	var memes := {}
	for fid in Faiths.ids(state):
		if nature(state, fid) == "meme":
			memes[fid] = Faiths.followers_by_owner(state, fid)
	if memes.is_empty():
		return
	var nets := state.networks.keys()
	nets.sort()
	for k in nets:
		var net: Dictionary = state.networks[k]
		var pair := [int(net["a"]), int(net["b"])]
		for side in [[pair[0], pair[1]], [pair[1], pair[0]]]:
			var from := int(side[0])
			var to := state.get_empire(int(side[1]))
			if to == null or to.eliminated:
				continue
			var cap: Colony = state.colonies.get(to.capital_planet)
			if cap == null or cap.owner != to.id or Faiths.is_hive(state, to.id):
				continue
			for fid in memes:
				var n := int(memes[fid].get(from, 0))
				if n <= 0:
					continue
				var pm: Dictionary = out.get(cap.planet_id, {})
				pm[fid] = int(pm.get(fid, 0)) + n * 100
				out[cap.planet_id] = pm


# --- Cultes cachés (proposition 16) --------------------------------------------------------------

static func is_secret(state: GameState, fid: String) -> bool:
	return (Faiths.faith(state, fid).get("dogmas", []) as Array).has("secret")


## Un empire voit-il les fidèles de cette foi chez lui ?
static func visible_to(state: GameState, fid: String, viewer: int) -> bool:
	if viewer < 0 or not is_secret(state, fid) or Faiths.state_faith(state, viewer) == fid:
		return true
	return (state.faiths["seen"].get(str(viewer), []) as Array).has(fid)


static func reveal_secret(state: GameState, fid: String, viewer: int, added: Array[Dictionary]) -> void:
	if visible_to(state, fid, viewer):
		return
	var seen: Array = state.faiths["seen"].get(str(viewer), [])
	seen.append(fid)
	seen.sort()
	state.faiths["seen"][str(viewer)] = seen
	added.append(state.add_chronicle("Les services de %s mettent au jour un culte caché : %s prie en secret dans leurs colonies." % [
			state.get_empire(viewer).display_name(), Faiths.name_of(state, fid)], Espionage.private_to(state, [viewer])))


static func _secret_month(state: GameState, added: Array[Dictionary]) -> void:
	var sd: Dictionary = data()["secret"]
	var hidden := {}
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if GameState.is_npc(c.owner):
			continue
		for fid in c.faith:
			if not visible_to(state, fid, c.owner):
				var k := "%d|%s" % [c.owner, fid]
				hidden[k] = int(hidden.get(k, 0)) + int(c.faith[fid])
	var ks := hidden.keys()
	ks.sort()
	for k: String in ks:
		var parts := k.split("|")
		var owner := int(parts[0])
		var fid := parts[1]
		if int(hidden[k]) >= 3 and _h(state, ["secret", k, state.tick]) % 1000 < int(sd["discover_pmille"]):
			reveal_secret(state, fid, owner, added)
	# Soulèvements : une flotte de la foi, en guerre contre le maître, là où la foi domine.
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if GameState.is_npc(c.owner) or not c.is_colony():
			continue
		var m := Faiths.majority(c)
		if m == Faiths.NATIVE or not is_secret(state, m) or Faiths.state_faith(state, c.owner) == m:
			continue
		var sid := state.galaxy.get_planet(pid).system_id
		for fl in Fleets.fleets_at(state, sid):
			if GameState.is_npc(fl.owner) or Faiths.state_faith(state, fl.owner) != m or not Combat.at_war(state, fl.owner, c.owner):
				continue
			if _has_stab(state, sid, "Soulèvement"):
				break
			add_stab(state, sid, "Soulèvement de %s" % Faiths.name_of(state, m), int(sd["uprising"]), int(sd["uprising_days"]))
			reveal_secret(state, m, c.owner, added)
			added.append(state.add_chronicle("Soulèvement à %s ! À l'arrivée de la flotte de %s, les fidèles cachés de %s sortent des caves, armes à la main." % [
					state.galaxy.systems[sid].system_name, state.get_empire(fl.owner).short_name(), Faiths.name_of(state, m)], Espionage.public_to(state, [c.owner, fl.owner])))
			break


# --- Lignes de stabilité temporaires --------------------------------------------------------------

static func add_stab(state: GameState, sid: int, label: String, v: int, days: int) -> void:
	var l: Array = state.faiths["stab"].get(str(sid), [])
	l.append({"label": label, "v": v, "end": state.tick + days})
	state.faiths["stab"][str(sid)] = l


static func _has_stab(state: GameState, sid: int, prefix: String) -> bool:
	for l: Dictionary in state.faiths["stab"].get(str(sid), []):
		if String(l["label"]).begins_with(prefix) and int(l["end"]) > state.tick:
			return true
	return false


static func stability_parts(state: GameState, sid: int, owner: int) -> Array:
	var out := []
	for l: Dictionary in state.faiths["stab"].get(str(sid), []):
		if int(l["end"]) > state.tick:
			out.append([String(l["label"]), int(l["v"])])
	var d: Dictionary = state.faiths["demands"].get(str(owner), {})
	var cd: Dictionary = data()["cult"]
	if int(d.get("ok_end", 0)) > state.tick:
		out.append(["Liberté de culte accordée", int(cd["demand_ok"])])
	if int(d.get("fail_end", 0)) > state.tick:
		out.append(["Liberté de culte refusée", int(cd["demand_fail"])])
	return out


# --- Opinion -------------------------------------------------------------------------------------

static func opinion_parts(state: GameState, a: int, b: int) -> Array:
	var out := []
	var fa := Faiths.state_faith(state, a)
	var fb := Faiths.state_faith(state, b)
	# Schisme : la foi mère et la foi schismatique se détestent.
	if fa != Faiths.LAICITE and fb != Faiths.LAICITE and fa != fb:
		if String(Faiths.faith(state, fa).get("schism_of", "")) == fb or String(Faiths.faith(state, fb).get("schism_of", "")) == fa:
			out.append(["Schisme", int(data()["heresy"]["schism_op"])])
	# Persécution : b a l'Inquisition et des fidèles de la foi de a.
	if fa != Faiths.LAICITE and fa != fb and Research.fx_int(state, b, "faith_inquisition") > 0 \
			and int(Faiths.followers_by_owner(state, fa).get(b, 0)) > 0:
		out.append(["Persécute nos fidèles", int(data()["cult"]["inquisition_op"])])
	# Missions chez nous.
	for m in _missions(state):
		if int(m["by"]) == b and state.system_owner(int(m["sid"])) == a and fa != String(m["fid"]):
			out.append(["Missionnaires chez nous", int(data()["missions"]["op"])])
			break
	# Guerre sainte d'un coreligionnaire.
	if fa != Faiths.LAICITE:
		for w in _holy_wars(state):
			if int(w["a"]) == b and String(w["fid"]) == fa and a != b:
				out.append(["Mène la guerre sainte", int(data()["holy_war"]["op"])])
				break
	return out


# --- Lois de culte et doléance (proposition 13) --------------------------------------------------

static func law_score(state: GameState, e: Empire, id: String, ag: int) -> int:
	if not state.faith_on:
		return -1
	var minor := minority_share(state, e.id)
	if id == "tolerance":
		var d: Dictionary = state.faiths["demands"].get(str(e.id), {})
		if int(d.get("end", 0)) > state.tick:
			return 60
		return 10 + minor - ag * 5 if minor >= 15 else -1
	if id == "inquisition":
		return 5 + ag * 8 if minor >= 10 and minor < 40 and Faiths.has_state_faith(state, e.id) else -1
	return -1


## Part (en %) de la population de l'empire qui suit une autre grande foi que la foi d'État.
@warning_ignore("integer_division")
static func minority_share(state: GameState, eid: int) -> int:
	var sf := Faiths.state_faith(state, eid)
	var total := 0
	var other := 0
	for pid in state.colonies:
		var c: Colony = state.colonies[pid]
		if c.owner != eid or not c.is_colony():
			continue
		total += c.population
		for fid in c.faith:
			if fid != sf:
				other += int(c.faith[fid])
	return other * 100 / total if total > 0 else 0


static func _cult_month(state: GameState, e: Empire, added: Array[Dictionary]) -> void:
	var cd: Dictionary = data()["cult"]
	var sf := Faiths.state_faith(state, e.id)
	# Inquisition : tous les 3 mois, un fidèle d'une autre foi par colonie passe à la foi d'État.
	@warning_ignore("integer_division")
	var month := state.tick / int(GameData.rules()["month_days"])
	if Research.fx_int(state, e.id, "faith_inquisition") > 0 and sf != Faiths.LAICITE and month % int(cd["inquisition_every"]) == 0:
		for pid in state.sorted_colony_ids():
			var c: Colony = state.colonies[pid]
			if c.owner != e.id or not c.is_colony():
				continue
			var victim := ""
			for fid in Faiths._sorted_keys(c.faith):
				if fid != sf and (victim == "" or int(c.faith[fid]) > int(c.faith[victim])):
					victim = fid
			if victim != "":
				c.faith[victim] = int(c.faith[victim]) - 1
				if int(c.faith[victim]) <= 0:
					c.faith.erase(victim)
				c.faith[sf] = int(c.faith.get(sf, 0)) + 1
	# Doléance « Liberté de culte » (avec la politique intérieure).
	if not state.politics_on or not Politics.applies(state, e.id):
		return
	var key := str(e.id)
	var d: Dictionary = state.faiths["demands"].get(key, {})
	var tol := Research.fx_int(state, e.id, "faith_tolerance") > 0
	if int(d.get("end", 0)) > 0:
		if tol:
			d["ok_end"] = state.tick + int(cd["demand_fx_days"])
			d["end"] = 0
			d["next"] = state.tick + int(cd["demand_cooldown"])
			added.append(state.add_chronicle("%s proclame la liberté de culte. Les temples rouvrent, les prêcheurs se taisent un peu." % e.display_name(), Espionage.private_to(state, [e.id])))
		elif state.tick >= int(d["end"]):
			d["fail_end"] = state.tick + int(cd["demand_fx_days"])
			d["end"] = 0
			d["next"] = state.tick + int(cd["demand_cooldown"])
			added.append(state.add_chronicle("%s ignore la liberté de culte réclamée par ses minorités. Les fidèles prient désormais avec rancune." % e.display_name(), Espionage.private_to(state, [e.id])))
	elif not tol and sf != Faiths.LAICITE and state.tick >= int(d.get("next", 0)) and minority_share(state, e.id) >= int(cd["demand_share_pct"]):
		d["end"] = state.tick + int(cd["demand_days"])
		added.append(state.add_chronicle("Les minorités religieuses de %s réclament la liberté de culte : adopter la Tolérance avant deux ans." % e.display_name(), Espionage.private_to(state, [e.id])))
	if not d.is_empty():
		state.faiths["demands"][key] = d


static func demand(state: GameState, eid: int) -> int:
	return int(state.faiths["demands"].get(str(eid), {}).get("end", 0))


# --- Hérésies et schismes (proposition 12) -------------------------------------------------------

static func _heresy_month(state: GameState, fid: String, added: Array[Dictionary]) -> void:
	var hd: Dictionary = data()["heresy"]
	var f := Faiths.faith(state, fid)
	if Faiths.parent_of(state, fid) != "" or zeal(state, fid) >= int(hd["zeal_below"]):
		return
	var kids := 0
	for x in Faiths.ids(state):
		if Faiths.parent_of(state, x) == fid:
			kids += 1
	if kids >= int(hd.get("max_children", 2)):
		return
	if _h(state, ["heresy", fid, state.tick]) % 1000 >= int(hd["chance_pmille"]):
		return
	var hsid := state.galaxy.get_planet(int(f["holy"])).system_id
	var dist := FactionTraits.jumps_from(state.galaxy, hsid)
	var founder_f := Peoples.founder_of(state, int(f["founder"]))
	var cands: Array = []
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if GameState.is_npc(c.owner) or int(c.faith.get(fid, 0)) < int(hd["min_followers"]):
			continue
		if int(dist.get(state.galaxy.get_planet(pid).system_id, 99)) < int(hd["min_jumps"]):
			continue
		if Peoples.founder_of(state, c.owner) == founder_f and Faiths.state_faith(state, c.owner) == fid:
			continue
		cands.append(pid)
	if cands.is_empty():
		return
	var pid := int(cands[_h(state, ["heresy_at", fid, state.tick]) % cands.size()])
	spawn_heresy(state, fid, pid, added)


## Une hérésie naît sur une colonie : foi fille, un dogme changé, la moitié des fidèles.
static func spawn_heresy(state: GameState, fid: String, pid: int, added: Array[Dictionary]) -> String:
	var f := Faiths.faith(state, fid)
	var c: Colony = state.colonies[pid]
	var hid := "f%d" % int(state.faiths["next"])
	state.faiths["next"] = int(state.faiths["next"]) + 1
	var dg: Array = (f["dogmas"] as Array).duplicate()
	var sname := state.galaxy.systems[state.galaxy.get_planet(pid).system_id].system_name
	var hname := "%s %s" % [String(f["name"]).split(" ")[0], _de(sname)]
	var taken := {}
	for x in Faiths.ids(state):
		taken[Faiths.name_of(state, x)] = true
	var base := hname
	var k := 2
	while taken.has(hname):
		hname = "%s %s" % [base, ["", "", "II", "III", "IV", "V", "VI"][k] if k <= 6 else str(k)]
		k += 1
	var col := Color(String(f["color"]))
	col.h = fposmod(col.h + 0.08, 1.0)
	state.faiths["list"][hid] = {
		"name": hname, "founder": c.owner, "holy": pid, "founded": state.tick,
		"via": "heresie", "parent": fid, "dogmas": dg, "slots": int(f["slots"]), "color": "#" + col.to_html(false),
		"zeal": 70, "nature": String(f.get("nature", "")),
	}
	_mutate_one(state, hid)
	@warning_ignore("integer_division")
	var n := int(c.faith.get(fid, 0)) * int(data()["heresy"]["convert_pct"]) / 100
	c.faith[fid] = int(c.faith[fid]) - n
	c.faith[hid] = n
	Faiths.normalize(c)
	Relics.touch(state)
	added.append(state.add_chronicle("Hérésie à %s : des fidèles de %s rompent avec le dogme et fondent %s. Les théologiens aiguisent leurs arguments, et parfois leurs couteaux." % [
			sname, Faiths.name_of(state, fid), Faiths.name_of(state, hid)]))
	return hid


## « de Savy », « d'Angal ».
static func _de(word: String) -> String:
	return ("d'" if "AEIOUYÂÉÈÊÎÔÛaeiouyâéèêîôû".contains(word.left(1)) else "de ") + word


## Remplace un dogme (tirage haché) par un autre compatible.
static func _mutate_one(state: GameState, fid: String) -> void:
	var f := Faiths.faith(state, fid)
	var dg: Array = f["dogmas"]
	if dg.is_empty():
		return
	var i := _h(state, ["mutate", fid, state.tick]) % dg.size()
	var old := String(dg[i])
	dg.remove_at(i)
	var cands: Array = []
	for did in Faiths.dogma_ids():
		if did == old or dg.has(did):
			continue
		var ok := true
		for h in dg:
			if (Faiths.dogma_def(did).get("excl", []) as Array).has(h) or (Faiths.dogma_def(String(h)).get("excl", []) as Array).has(did):
				ok = false
		if ok:
			cands.append(did)
	if cands.is_empty():
		dg.insert(i, old)
		return
	dg.insert(i, String(cands[_h(state, ["mutate_to", fid, state.tick]) % cands.size()]))


static func _schism_month(state: GameState, hid: String, added: Array[Dictionary]) -> void:
	var hd: Dictionary = data()["heresy"]
	var pf := Faiths.parent_of(state, hid)
	if pf == "":
		return
	var hn := Faiths.followers(state, hid)
	var pn := Faiths.followers(state, pf)
	if hn >= int(hd["schism_min"]) and hn * 100 >= (hn + pn) * int(hd["schism_share_pct"]):
		var f := Faiths.faith(state, hid)
		f.erase("parent")
		f["via"] = "schisme"
		f["schism_of"] = pf
		Relics.touch(state)
		added.append(state.add_chronicle("Schisme ! %s se sépare de %s et devient une grande foi. L'Autel se coupe en deux, et chaque moitié jure que l'autre est l'hérésie." % [
				Faiths.name_of(state, hid), Faiths.name_of(state, pf)]))


## Concile (Code saint) : l'hérésie rentre dans la foi mère.
static func check_council(state: GameState, player: int, hid: String) -> String:
	if not state.faith_on:
		return "les religions ne sont pas actives dans cette partie"
	var pf := Faiths.parent_of(state, hid)
	if pf == "":
		return "ce n'est pas une hérésie (un schisme ne se refusionne plus)"
	if nature(state, pf) != "code_saint":
		return "seule une foi de nature Code saint réunit un concile"
	if Faiths.head(state, pf) != player:
		return "seul le chef de foi convoque le concile"
	return _afford(state, player, data()["heresy"]["council_cost"])


static func council(state: GameState, player: int, hid: String) -> void:
	_pay(state, player, data()["heresy"]["council_cost"])
	var pf := Faiths.parent_of(state, hid)
	for pid in state.colonies:
		var c: Colony = state.colonies[pid]
		var n := int(c.faith.get(hid, 0))
		if n > 0:
			c.faith.erase(hid)
			c.faith[pf] = int(c.faith.get(pf, 0)) + n
	for k in state.faiths["state"]:
		if String(state.faiths["state"][k]) == hid:
			state.faiths["state"][k] = pf
	state.faiths["list"].erase(hid)
	Relics.touch(state)
	state.add_chronicle("Concile : %s refusionne sa branche dissidente. Le code est recompilé, les hérétiques reçoivent un correctif." % Faiths.name_of(state, pf))


## Réécriture d'un dogme (Code saint) : le plus ancien est remplacé.
static func check_rewrite(state: GameState, player: int, fid: String, did: String) -> String:
	if not state.faith_on:
		return "les religions ne sont pas actives dans cette partie"
	if nature(state, fid) != "code_saint":
		return "seule une foi de nature Code saint réécrit ses dogmes"
	if Faiths.head(state, fid) != player:
		return "seul le chef de foi réécrit les dogmes"
	var dg: Array = Faiths.faith(state, fid)["dogmas"]
	if dg.is_empty():
		return "aucun dogme à réécrire"
	if Faiths.dogma_def(did).is_empty() or dg.has(did):
		return "dogme inconnu ou déjà suivi"
	for i in range(1, dg.size()):
		var h := String(dg[i])
		if (Faiths.dogma_def(did).get("excl", []) as Array).has(h) or (Faiths.dogma_def(h).get("excl", []) as Array).has(did):
			return "incompatible avec « %s »" % String(Faiths.dogma_def(h)["label"])
	return _afford(state, player, data()["heresy"]["rewrite_cost"])


static func rewrite(state: GameState, player: int, fid: String, did: String) -> void:
	_pay(state, player, data()["heresy"]["rewrite_cost"])
	var dg: Array = Faiths.faith(state, fid)["dogmas"]
	dg.remove_at(0)
	dg.append(did)
	Relics.touch(state)


# --- Missions (proposition 14) -------------------------------------------------------------------

static func check_mission(state: GameState, player: int, sid: int) -> String:
	if not state.faith_on:
		return "les religions ne sont pas actives dans cette partie"
	var e := state.get_empire(player)
	if e == null or e.eliminated:
		return "empire inconnu"
	var sf := Faiths.state_faith(state, player)
	if sf == Faiths.LAICITE:
		return "il faut une foi d'État pour envoyer des missionnaires"
	if sid < 0 or sid >= state.galaxy.systems.size():
		return "système inconnu"
	if not e.explored.has(sid) and state.system_owner(sid) != player:
		return "système inexploré"
	var any := false
	for pid in state.galaxy.systems[sid].planet_ids:
		var c: Colony = state.colonies.get(pid)
		if c != null and c.is_colony() and c.is_established() and not Faiths.is_hive(state, c.owner) and not GameState.is_npc(c.owner):
			any = true
	if not any:
		return "personne à convertir dans ce système"
	if int(state.faiths["wards"].get(str(sid), 0)) > state.tick and state.system_owner(sid) != player:
		return "une mission d'inquisition protège ce système"
	var n := 0
	for m in _missions(state):
		if int(m["by"]) == player:
			n += 1
			if int(m["sid"]) == sid:
				return "une mission prêche déjà ici"
	if n >= int(data()["missions"]["max"]):
		return "au plus %d missions à la fois" % int(data()["missions"]["max"])
	return _afford(state, player, data()["missions"]["cost"])


static func mission(state: GameState, player: int, sid: int) -> void:
	_pay(state, player, data()["missions"]["cost"])
	var l: Array = _missions(state).duplicate()
	l.append({"by": player, "sid": sid, "fid": Faiths.state_faith(state, player), "end": state.tick + int(data()["missions"]["days"])})
	state.faiths["missions"] = {"list": l}


static func missions_by(state: GameState, eid: int) -> Array:
	var out := []
	for m in _missions(state):
		if int(m["by"]) == eid:
			out.append(m)
	return out


static func check_ward(state: GameState, player: int, sid: int) -> String:
	if not state.faith_on:
		return "les religions ne sont pas actives dans cette partie"
	if sid < 0 or state.system_owner(sid) != player:
		return "il faut être maître du système"
	var foreign := false
	for m in _missions(state):
		if int(m["sid"]) == sid and int(m["by"]) != player:
			foreign = true
	if not foreign:
		return "aucune mission étrangère à chasser"
	return _afford(state, player, data()["missions"]["ward_cost"])


static func ward(state: GameState, player: int, sid: int) -> void:
	_pay(state, player, data()["missions"]["ward_cost"])
	var keep: Array = []
	for m in _missions(state):
		if int(m["sid"]) != sid or int(m["by"]) == player:
			keep.append(m)
	state.faiths["missions"] = {"list": keep}
	state.faiths["wards"][str(sid)] = state.tick + int(data()["missions"]["ward_days"])


# --- Guerre sainte et croisade (proposition 15) --------------------------------------------------

## Motif de guerre sainte de a contre b ("" s'il n'y en a pas).
static func casus(state: GameState, a: int, b: int) -> String:
	if not state.faith_on or GameState.is_npc(a) or GameState.is_npc(b):
		return ""
	var fa := Faiths.state_faith(state, a)
	if fa == Faiths.LAICITE or fa == Faiths.INCROYANCE:
		return ""
	var fb := Faiths.state_faith(state, b)
	if fa == fb:
		return ""
	var holy_c: Colony = state.colonies.get(int(Faiths.faith(state, fa)["holy"]))
	if holy_c != null and holy_c.owner == b:
		return "il tient notre monde saint"
	if Research.fx_int(state, b, "faith_inquisition") > 0 and int(Faiths.followers_by_owner(state, fa).get(b, 0)) > 0:
		return "il persécute nos fidèles"
	if String(Faiths.faith(state, fb).get("schism_of", "")) == fa or String(Faiths.faith(state, fa).get("schism_of", "")) == fb:
		return "il suit le schisme"
	return ""


## Déclaration de guerre (Diplomacy.on_war_declared) : une guerre sainte si le motif existe.
static func on_war(state: GameState, a: int, b: int) -> void:
	if not state.faith_on:
		return
	var why := casus(state, a, b)
	if why == "":
		return
	var fa := Faiths.state_faith(state, a)
	var l: Array = _holy_wars(state).duplicate()
	l.append({"a": a, "b": b, "fid": fa})
	state.faiths["holy_wars"] = {"list": l}
	add_zeal(state, fa, int(data()["zeal"]["holy_war"]))
	state.add_chronicle("%s proclame la guerre sainte contre %s : %s. Les fidèles de %s applaudissent." % [
			state.get_empire(a).display_name(), state.get_empire(b).display_name(), why, Faiths.name_of(state, fa)])


static func check_crusade(state: GameState, player: int, target: int) -> String:
	if not state.faith_on:
		return "les religions ne sont pas actives dans cette partie"
	var fid := Faiths.state_faith(state, player)
	if fid == Faiths.LAICITE or Faiths.faith(state, fid).is_empty():
		return "il faut une grande foi pour prêcher la croisade"
	if Faiths.head(state, fid) != player:
		return "seul le chef de foi appelle à la croisade"
	var te := state.get_empire(target)
	if te == null or te.eliminated or target == player:
		return "cible inconnue"
	if casus(state, player, target) == "":
		return "aucun motif de guerre sainte contre lui"
	var cr: Dictionary = state.faiths["crusades"].get(fid, {})
	if int(cr.get("end", 0)) > state.tick:
		return "une croisade est déjà en cours"
	if int(cr.get("next", 0)) > state.tick:
		return "la dernière croisade est trop récente (encore %d jours)" % (int(cr["next"]) - state.tick)
	if not Combat.at_war(state, player, target):
		var w := SimCommands.validate(state, SimCommands.declare_war(player, target))
		if w != "":
			return w
	return _afford(state, player, data()["holy_war"]["crusade_cost"])


static func crusade(state: GameState, player: int, target: int) -> void:
	var hd: Dictionary = data()["holy_war"]
	_pay(state, player, hd["crusade_cost"])
	var fid := Faiths.state_faith(state, player)
	state.faiths["crusades"][fid] = {"target": target, "end": state.tick + int(hd["crusade_days"]), "next": state.tick + int(hd["crusade_cooldown"])}
	if not Combat.at_war(state, player, target):
		Combat.start_war(state, player, target)
	var joined := PackedStringArray()
	for e in state.empires:
		if e.eliminated or e.id == player or e.id == target or Faiths.state_faith(state, e.id) != fid:
			continue
		if Combat.at_war(state, e.id, target) or not e.contacts.has(target):
			continue
		if SimCommands.validate(state, SimCommands.declare_war(e.id, target)) != "":
			continue
		Combat.start_war(state, e.id, target, false, true)
		joined.append(e.short_name())
	state.add_chronicle("Croisade ! %s appelle les fidèles de %s contre %s%s." % [state.get_empire(player).display_name(), Faiths.name_of(state, fid),
			state.get_empire(target).display_name(), (" ; répondent à l'appel : " + ", ".join(joined)) if not joined.is_empty() else ""])


static func crusade_of(state: GameState, fid: String) -> Dictionary:
	var cr: Dictionary = state.faiths["crusades"].get(fid, {})
	return cr if int(cr.get("end", 0)) > state.tick else {}


static func _crusade_month(state: GameState, added: Array[Dictionary]) -> void:
	for fid in Faiths._sorted_keys(state.faiths["crusades"]):
		var cr: Dictionary = state.faiths["crusades"][fid]
		if int(cr["end"]) <= state.tick or Faiths.faith(state, fid).is_empty():
			continue
		var holy_c: Colony = state.colonies.get(int(Faiths.faith(state, fid)["holy"]))
		var te := state.get_empire(int(cr["target"]))
		var won: bool = te == null or te.eliminated or (holy_c != null and not GameState.is_npc(holy_c.owner) \
				and Faiths.state_faith(state, holy_c.owner) == fid and casus(state, Faiths.head(state, fid), int(cr["target"])) == "")
		if won:
			cr["end"] = state.tick
			add_zeal(state, fid, int(data()["zeal"]["crusade_won"]))
			added.append(state.add_chronicle("La croisade de %s s'achève en triomphe. Les cloches sonnent, le zèle déborde." % Faiths.name_of(state, fid)))
	# Guerres saintes terminées.
	var keep: Array = []
	for w in _holy_wars(state):
		if Combat.at_war(state, int(w["a"]), int(w["b"])):
			keep.append(w)
	state.faiths["holy_wars"] = {"list": keep}


# --- Prophétie plantée (proposition 17) ----------------------------------------------------------

static func check_prophecy(state: GameState, a: int, b: int) -> String:
	if not state.faith_on:
		return "les religions ne sont pas actives dans cette partie"
	if Faiths.state_faith(state, a) == Faiths.LAICITE:
		return "il faut une foi d'État pour semer une prophétie"
	if Faiths.is_hive(state, b):
		return "une ruche n'écoute pas les prophètes"
	if prophecy_target(state, b) < 0:
		return "aucun monde où semer la prophétie"
	return ""


## Monde visé : la colonie la plus peuplée de la cible, sans prophétie déjà semée.
static func prophecy_target(state: GameState, b: int) -> int:
	var best := -1
	var bp := -1
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner == b and c.is_colony() and c.is_established() and not state.faiths["prophecies"].has(str(pid)) and c.population > bp:
			best = pid
			bp = c.population
	return best


static func plant(state: GameState, a: int, b: int) -> String:
	var pid := prophecy_target(state, b)
	if pid < 0:
		return "personne n'a voulu croire. Les prophètes rentrent, vexés."
	state.faiths["prophecies"][str(pid)] = {"by": a, "fid": Faiths.state_faith(state, a), "at": state.tick}
	return "une prophétie court sur %s : un jour viendra un héros de %s. Il ne reste plus qu'à l'envoyer." % [
			state.galaxy.get_planet(pid).display_name(state.galaxy), state.get_empire(a).short_name()]


static func _prophecy_month(state: GameState, added: Array[Dictionary]) -> void:
	var pd: Dictionary = data()["prophecy"]
	for k in Faiths._sorted_keys(state.faiths["prophecies"]):
		var p: Dictionary = state.faiths["prophecies"][k]
		var pid := int(k)
		var c: Colony = state.colonies.get(pid)
		if c == null or state.tick - int(p["at"]) > int(pd["expire_days"]) or c.owner == int(p["by"]):
			state.faiths["prophecies"].erase(k)
			continue
		var sid := state.galaxy.get_planet(pid).system_id
		var hero := _hero_at(state, int(p["by"]), sid)
		if hero.is_empty():
			continue
		var fid := String(p["fid"])
		if fid != Faiths.INCROYANCE and Faiths.faith(state, fid).is_empty():
			state.faiths["prophecies"].erase(k)
			continue
		c.faith.clear()
		c.faith[fid] = c.population
		add_stab(state, sid, "Prophétie accomplie", int(pd["stab"]), int(pd["stab_days"]))
		add_zeal(state, fid, int(data()["zeal"]["prophecy"]))
		state.faiths["prophecies"].erase(k)
		added.append(state.add_chronicle("La prophétie s'accomplit sur %s : %s descend de son vaisseau, et la foule tombe à genoux. Tout le monde se convertit à %s." % [
				state.galaxy.get_planet(pid).display_name(state.galaxy), String(hero["name"]), Faiths.name_of(state, fid)], Espionage.public_to(state, [c.owner, int(p["by"])])))


## Héros amiral d'un empire dont la flotte stationne dans un système.
static func _hero_at(state: GameState, eid: int, sid: int) -> Dictionary:
	var hids := state.heroes.keys()
	hids.sort()
	for hid in hids:
		var h: Dictionary = state.heroes[hid]
		if int(h.get("owner", -1)) != eid or String(h.get("post", "")) != "fleet" or not Heroes.active(state, h):
			continue
		var fl: Fleet = state.fleets.get(int(h["target"]))
		if fl != null and fl.system_id == sid and not fl.is_moving():
			return h
	return {}


# --- Culte du Je (ruches) ------------------------------------------------------------------------

static func je(state: GameState, pid: int) -> Dictionary:
	var v: Variant = state.faiths["je"].get(str(pid), {})
	return v if v is Dictionary else {}


@warning_ignore("integer_division")
static func _je_month(state: GameState, e: Empire, added: Array[Dictionary]) -> void:
	var jd: Dictionary = data()["je"]
	@warning_ignore("integer_division")
	var month := state.tick / int(GameData.rules()["month_days"])
	var know := 0
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner != e.id or not c.is_colony() or not c.is_established():
			continue
		var key := str(pid)
		var j := je(state, pid)
		if j.is_empty():
			if c.population >= int(jd["min_pop"]) and state.tick >= int(state.faiths["je"].get("block:" + key, 0)) \
					and _h(state, ["je", pid, state.tick]) % 1000 < int(jd["chance_pmille"]):
				state.faiths["je"][key] = {"n": 1, "tol": false}
				added.append(state.add_chronicle("Sur %s, un drone s'arrête de travailler et regarde ses mains. Il pense « je ». La ruche frissonne." % [
						state.galaxy.get_planet(pid).display_name(state.galaxy)], Espionage.private_to(state, [e.id])))
			continue
		var cap := int(jd["tolerated_max"]) if bool(j["tol"]) else int(jd["max"])
		if month % int(jd["grow_every"]) == 0 and int(j["n"]) < cap:
			j["n"] = int(j["n"]) + 1
		if bool(j["tol"]):
			know += int(j["n"]) / int(jd["knowledge_div"])
		elif int(j["n"]) >= int(jd["max"]):
			state.faiths["je"].erase(key)
			StabilitySystem.secede(state, state.galaxy.get_planet(pid).system_id, e.id, added, true)
	if know > 0:
		e.resources["knowledge"] = int(e.resources.get("knowledge", 0)) + know


## Les drones dissidents arrêtent la ponte (EconomySystem) quand ils sont assez nombreux et non tolérés.
static func je_blocks_growth(state: GameState, c: Colony) -> bool:
	if not state.faith_on or state.faiths["je"].is_empty():
		return false
	var j := je(state, c.planet_id)
	return not j.is_empty() and not bool(j["tol"]) and int(j["n"]) >= int(data()["je"]["stop_growth_at"])


static func check_je(state: GameState, player: int, pid: int, what: String) -> String:
	if not state.faith_on:
		return "les religions ne sont pas actives dans cette partie"
	var c: Colony = state.colonies.get(pid)
	if c == null or c.owner != player:
		return "il faut une de vos colonies"
	var j := je(state, pid)
	if j.is_empty():
		return "aucun drone dissident ici"
	if what == "tolerer" and bool(j["tol"]):
		return "ils sont déjà tolérés"
	if what != "tolerer" and what != "ecraser":
		return "choix inconnu"
	return ""


@warning_ignore("integer_division")
static func je_act(state: GameState, player: int, pid: int, what: String) -> void:
	var jd: Dictionary = data()["je"]
	var c: Colony = state.colonies[pid]
	var j := je(state, pid)
	if what == "tolerer":
		j["tol"] = true
		return
	c.population = maxi(1, c.population - maxi(1, int(j["n"]) / int(jd["crush_pop_div"])))
	state.faiths["je"].erase(str(pid))
	state.faiths["je"]["block:" + str(pid)] = state.tick + int(jd["block_days"])


# --- Mois ----------------------------------------------------------------------------------------

static func monthly(state: GameState, added: Array[Dictionary]) -> void:
	for fid in Faiths.ids(state):
		_zeal_month(state, fid)
	for fid in Faiths.ids(state):
		if Faiths.faith(state, fid).is_empty():
			continue
		if Faiths.parent_of(state, fid) != "":
			_schism_month(state, fid, added)
		else:
			_heresy_month(state, fid, added)
	# Hérésies et schismes éteints : plus de fidèles, plus d'empire qui les suit.
	for fid in Faiths.ids(state):
		var via := String(Faiths.faith(state, fid).get("via", ""))
		if (via != "heresie" and via != "schisme") or Faiths.followers(state, fid) > 0:
			continue
		var used := false
		for k in state.faiths["state"]:
			if String(state.faiths["state"][k]) == fid:
				used = true
		if not used:
			state.faiths["list"].erase(fid)
	# Mème : les dogmes mutent seuls.
	var md := int(data()["natures"]["meme_mutate_days"])
	for fid in Faiths.ids(state):
		var f := Faiths.faith(state, fid)
		if nature(state, fid) == "meme" and state.tick > int(f["founded"]) and (state.tick - int(f["founded"])) % md < int(GameData.rules()["month_days"]):
			_mutate_one(state, fid)
			Relics.touch(state)
	# Missions et protections échues.
	var keep: Array = []
	for m in _missions(state):
		if int(m["end"]) > state.tick and not state.get_empire(int(m["by"])).eliminated:
			keep.append(m)
	state.faiths["missions"] = {"list": keep}
	for k in state.faiths["wards"].keys():
		if int(state.faiths["wards"][k]) <= state.tick:
			state.faiths["wards"].erase(k)
	for k in state.faiths["stab"].keys():
		var l: Array = []
		for x: Dictionary in state.faiths["stab"][k]:
			if int(x["end"]) > state.tick:
				l.append(x)
		if l.is_empty():
			state.faiths["stab"].erase(k)
		else:
			state.faiths["stab"][k] = l
	for e in state.empires:
		if e.eliminated:
			continue
		if Faiths.is_hive(state, e.id):
			_je_month(state, e, added)
		else:
			_cult_month(state, e, added)
	_crusade_month(state, added)
	_secret_month(state, added)
	_prophecy_month(state, added)
	_ai(state)


# --- IA ------------------------------------------------------------------------------------------

static func _ai(state: GameState) -> void:
	var ai: Dictionary = data()["ai"]
	for e in state.empires:
		if e.eliminated or not e.is_ai():
			continue
		var inf := int(e.resources.get("influence", 0))
		if Faiths.is_hive(state, e.id):
			for pid in state.sorted_colony_ids():
				var j := je(state, pid)
				if not j.is_empty() and state.colonies[pid].owner == e.id and int(j["n"]) >= int(data()["je"]["ai_crush_at"]) \
						and check_je(state, e.id, pid, "ecraser") == "":
					je_act(state, e.id, pid, "ecraser")
			continue
		# Chasser les missions étrangères.
		if inf >= int(ai["ward_influence"]):
			for m in _missions(state):
				var sid := int(m["sid"])
				if state.system_owner(sid) == e.id and check_ward(state, e.id, sid) == "":
					ward(state, e.id, sid)
					inf = int(e.resources.get("influence", 0))
					break
		# Concile (Code saint).
		for hid in Faiths.ids(state):
			if Faiths.parent_of(state, hid) != "" and int(e.resources.get("knowledge", 0)) >= int(ai["council_knowledge"]) \
					and check_council(state, e.id, hid) == "":
				council(state, e.id, hid)
		# Croisade : le chef de foi contre qui tient son monde saint.
		var sf := Faiths.state_faith(state, e.id)
		if sf != Faiths.LAICITE and Faiths.head(state, sf) == e.id:
			var holy_c: Colony = state.colonies.get(int(Faiths.faith(state, sf).get("holy", -1)))
			if holy_c != null and not GameState.is_npc(holy_c.owner) and holy_c.owner != e.id \
					and check_crusade(state, e.id, holy_c.owner) == "":
				crusade(state, e.id, holy_c.owner)
		# Missions : vers le système voisin le plus peuplé qui ne suit pas la foi.
		if sf != Faiths.LAICITE and inf >= int(ai["mission_influence"]) and missions_by(state, e.id).size() < int(data()["missions"]["max"]) \
				and _h(state, ["ai_mission", e.id, state.tick]) % 3 == 0:
			var sid := _ai_mission_target(state, e.id, sf)
			if sid >= 0 and check_mission(state, e.id, sid) == "":
				mission(state, e.id, sid)


static func _ai_mission_target(state: GameState, eid: int, sf: String) -> int:
	var l := mission_targets(state, eid, sf, 1)
	return int(l[0]) if not l.is_empty() else -1


## Systèmes où prêcher, à 5 sauts au plus de la capitale : les plus peuplés de non-fidèles d'abord
## (au moins 4), les plus proches à égalité.
static func mission_targets(state: GameState, eid: int, sf: String, n: int) -> Array:
	var cap := FactionTraits.capital_system(state, eid)
	if cap < 0 or sf == Faiths.LAICITE:
		return []
	var dist := FactionTraits.jumps_from(state.galaxy, cap)
	var scored: Array = []
	for s in state.galaxy.systems:
		if int(dist.get(s.id, 99)) > 5:
			continue
		var v := 0
		for pid in s.planet_ids:
			var c: Colony = state.colonies.get(pid)
			if c == null or not c.is_colony() or GameState.is_npc(c.owner) or Faiths.is_hive(state, c.owner):
				continue
			v += c.population - int(c.faith.get(sf, 0))
		if v >= 4:
			scored.append([-v, int(dist[s.id]), s.id])
	scored.sort()
	var out := []
	for x in scored:
		if out.size() >= n:
			break
		out.append(int(x[2]))
	return out


# --- Divers --------------------------------------------------------------------------------------

static func _afford(state: GameState, player: int, cost: Dictionary) -> String:
	var e := state.get_empire(player)
	for r in cost:
		if int(e.resources.get(r, 0)) < int(cost[r]):
			return "il faut %s" % GameData.format_amounts(cost)
	return ""


static func _pay(state: GameState, player: int, cost: Dictionary) -> void:
	var e := state.get_empire(player)
	for r in cost:
		e.resources[r] = int(e.resources.get(r, 0)) - int(cost[r])
