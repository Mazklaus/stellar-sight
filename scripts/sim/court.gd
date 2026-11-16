class_name Court
extends RefCounted
## La cour et les Grandes Maisons (étude « La cour et les familles nobles », 2026-11-16 ; data/court.json).
## Chaque empire (sauf les ruches) a trois à cinq Maisons : une vocation (Armateurs, Champions…), des
## fiefs (les systèmes hors capitale, partagés entre elles), un siège, des membres (courtisans légers à
## quatre aptitudes, comme le souverain), une faveur de -100 à +100 en cinq paliers, des désirs et deux
## biens de luxe préférés, un penchant vers un courant politique. Le trône nomme ses grands offices
## (Grand Intendant, Connétable, Grand Héraut, Maître des Murmures, Grand Aumônier en théocratie) et
## trois postes mineurs parmi les membres des Maisons ou ses héros. Missions, mariages, Fronde,
## ultimatum, guerre civile, vaincus : CourtIntrigue. Faste, styles, ponts, événements : CourtBridges.
##
## Réglage « Grandes Maisons » : Actives (défaut d'une nouvelle partie), Apaisées (ni Fronde, ni
## ultimatum, ni guerre civile) ou Aucune (rien ne tourne, state.court reste vide). Sans l'option
## (tests), pas de cour.
##
## État : state.court = {"mode", "next": prochain id de membre, "hid": prochain id de maison,
##  "e": {"empire": E}, "sys": {"système": empire au dernier bilan}}.
## E = {"houses": [H], "fiefs": {"système": id de maison}, "offices": {office: {"k": m | h, "id"}},
##  "minor": {poste: id de membre}, "faste", "train": {train: 0-3}, "cd": {clé: jour}, "notes",
##  "levers": {"maison": jour de fin}, "fronde": {"maison": jour de fin}, "pacified": {"système": jour},
##  "ult": {"h", "until"}, "ult_cd", "next_ev", "fete_until", "sel" (0 : choix des maisons à faire),
##  "offer": [ids de maisons proposées], "star": id de membre (-1)}.
## H = {"id", "name", "voc", "color", "members": [M], "head", "rivals": [ids], "friends": [ids], "fav",
##  "adj", "scorn", "tier", "seat", "kin", "parts": [[libellé, valeur]], "from": empire d'origine (-1)}.
## M = {"id", "name", "g", "born", "life", "apt": {aptitude: 0-6}, "traits": [ids]}.

const APTS := ["gestion", "guerre", "eloquence", "intrigue"]
const DAYS_PER_YEAR := 360


static func data() -> Dictionary:
	return GameData.court()


static func rules() -> Dictionary:
	return data()["rules"]


static func r_int(key: String) -> int:
	return int(rules().get(key, 0))


static func mode_defs() -> Array:
	return data().get("modes", [])


static func default_mode() -> String:
	return String(data().get("default_mode", "actives"))


static func _h(state: GameState, parts: Array) -> int:
	return absi(hash([state.seed_value, "cour"] + parts))


# --- Réglage, sauvegarde -----------------------------------------------------------------------

static func mode(state: GameState) -> String:
	return String(state.court.get("mode", "aucune"))


static func enabled(state: GameState) -> bool:
	return not state.court.is_empty()


## Apaisées : ni Fronde, ni ultimatum, ni guerre civile.
static func peaceful(state: GameState) -> bool:
	return mode(state) == "apaisees"


static func worth_saving(state: GameState) -> bool:
	return not state.court.is_empty()


static func setup(state: GameState, mode_id: String) -> void:
	state.court = {}
	var ok := false
	for m: Dictionary in mode_defs():
		if String(m["id"]) == mode_id:
			ok = true
	if not ok or mode_id == "aucune":
		return
	state.court = {"mode": mode_id, "next": 1, "hid": 1, "e": {}, "sys": {}}
	for e in state.empires:
		if e.eliminated or e.is_npc():
			continue
		found(state, e.id)


static func to_dict(state: GameState) -> Dictionary:
	return Ancients._sorted(state.court)


static func from_dict(state: GameState, d: Dictionary) -> void:
	state.court = {}
	if d.is_empty():
		return
	state.court = GameData._to_ints(d.duplicate(true))


# --- Lecture -----------------------------------------------------------------------------------

static func entry(state: GameState, eid: int) -> Dictionary:
	if state.court.is_empty():
		return {}
	return (state.court["e"] as Dictionary).get(str(eid), {})


## L'empire a-t-il des Maisons ?
static func applies(state: GameState, eid: int) -> bool:
	return not entry(state, eid).is_empty()


static func government(state: GameState, eid: int) -> String:
	var e := state.get_empire(eid)
	if e == null or e.is_npc():
		return ""
	return String(e.faction().get("species", {}).get("gouvernement", "feodalite"))


## Mots du gouvernement : plural, one, the, head, fronde.
## Majuscule initiale seule (String.capitalize met une majuscule à chaque mot).
static func ucfirst(t: String) -> String:
	return t.left(1).to_upper() + t.substr(1) if t != "" else t


static func words(state: GameState, eid: int) -> Dictionary:
	var g: Dictionary = data()["governments"]
	return g.get(government(state, eid), g["feodalite"])


static func houses(state: GameState, eid: int) -> Array:
	return entry(state, eid).get("houses", [])


static func house(state: GameState, eid: int, hid: int) -> Dictionary:
	for h: Dictionary in houses(state, eid):
		if int(h["id"]) == hid:
			return h
	return {}


static var _voc_index: Dictionary = {}


static func voc_def(id: String) -> Dictionary:
	if _voc_index.is_empty():
		for v: Dictionary in data()["vocations"]:
			_voc_index[String(v["id"])] = v
	return _voc_index.get(id, {})


static func trait_def(id: String) -> Dictionary:
	return (data()["traits"] as Dictionary).get(id, {})


static func office_def(id: String) -> Dictionary:
	for o: Dictionary in data()["offices"]:
		if String(o["id"]) == id:
			return o
	return {}


static func minor_def(id: String) -> Dictionary:
	for o: Dictionary in data()["minor_posts"]:
		if String(o["id"]) == id:
			return o
	return {}


## Offices de l'empire (le Grand Aumônier n'existe qu'en théocratie).
static func office_ids(state: GameState, eid: int) -> Array[String]:
	var out: Array[String] = []
	var g := government(state, eid)
	for o: Dictionary in data()["offices"]:
		var gs: Array = o.get("governments", [])
		if gs.is_empty() or gs.has(g):
			out.append(String(o["id"]))
	return out


static func office_label(state: GameState, eid: int, id: String) -> String:
	var o := office_def(id)
	return String((o.get("labels", {}) as Dictionary).get(government(state, eid), o.get("label", id)))


## Talents de cour du peuple (les quatre couches additionnées).
static func talent(state: GameState, eid: int) -> Dictionary:
	var out := {}
	var t: Dictionary = data()["talents"]
	for layer in ["archetype", "credo", "registre", "gouvernement"]:
		var d: Dictionary = (t.get(layer, {}) as Dictionary).get(Events.layer_value(state, eid, layer), {})
		for k in d:
			if k != "label":
				out[k] = int(out.get(k, 0)) + int(d[k])
	return out


static func talent_labels(state: GameState, eid: int) -> Array[String]:
	var out: Array[String] = []
	var t: Dictionary = data()["talents"]
	for layer in ["archetype", "credo", "registre", "gouvernement"]:
		var d: Dictionary = (t.get(layer, {}) as Dictionary).get(Events.layer_value(state, eid, layer), {})
		if d.has("label"):
			out.append(String(d["label"]))
	return out


static func member(state: GameState, eid: int, mid: int) -> Dictionary:
	for h: Dictionary in houses(state, eid):
		for m: Dictionary in h["members"]:
			if int(m["id"]) == mid:
				return m
	return {}


static func house_of_member(state: GameState, eid: int, mid: int) -> Dictionary:
	for h: Dictionary in houses(state, eid):
		for m: Dictionary in h["members"]:
			if int(m["id"]) == mid:
				return h
	return {}


static func head(h: Dictionary) -> Dictionary:
	for m: Dictionary in h.get("members", []):
		if int(m["id"]) == int(h.get("head", -1)):
			return m
	return {}


static func age(state: GameState, m: Dictionary) -> int:
	@warning_ignore("integer_division")
	return (state.tick - int(m.get("born", state.tick))) / DAYS_PER_YEAR


## Aptitudes d'un membre, traits compris (plafond 6).
static func apts(m: Dictionary) -> Dictionary:
	var out := {}
	for a in APTS:
		out[a] = int((m.get("apt", {}) as Dictionary).get(a, 0))
	for t in m.get("traits", []):
		var ta: Dictionary = trait_def(String(t)).get("apt", {})
		for a in ta:
			out[a] = mini(6, int(out.get(a, 0)) + int(ta[a]))
	return out


static func trait_sum(m: Dictionary, key: String) -> int:
	var n := 0
	for t in m.get("traits", []):
		n += int(trait_def(String(t)).get(key, 0))
	return n


static func trait_max(m: Dictionary, key: String) -> int:
	var n := 1
	for t in m.get("traits", []):
		n = maxi(n, int(trait_def(String(t)).get(key, 1)))
	return n


## Fiefs (systèmes) d'une maison, triés.
static func fiefs_of(state: GameState, eid: int, hid: int) -> Array[int]:
	var out: Array[int] = []
	var f: Dictionary = entry(state, eid).get("fiefs", {})
	for k in f:
		if int(f[k]) == hid:
			out.append(int(k))
	out.sort()
	return out


## Maison qui tient ce système en fief ({} sinon).
static func fief_house(state: GameState, sid: int, owner := -2) -> Dictionary:
	if state.court.is_empty():
		return {}
	if owner == -2:
		owner = state.system_owner(sid)
	var en := entry(state, owner)
	if en.is_empty():
		return {}
	var hid := int((en["fiefs"] as Dictionary).get(str(sid), -1))
	return house(state, owner, hid) if hid >= 0 else {}


static func favor(h: Dictionary) -> int:
	return int(h.get("fav", 0))


static func tiers() -> Array:
	return rules()["tiers"]


static func tier_for(v: int) -> Dictionary:
	var best: Dictionary = tiers()[0]
	for t: Dictionary in tiers():
		if v >= int(t["min"]):
			best = t
	return best


static func tier(h: Dictionary) -> Dictionary:
	return tier_for(favor(h))


static func tier_id(h: Dictionary) -> String:
	return String(tier(h)["id"])


## Faveur assez bonne pour que la maison serve (siège et effets) : Neutre ou mieux.
static func serves(h: Dictionary) -> bool:
	return favor(h) >= int(tiers()[2]["min"])


# --- Fondation ---------------------------------------------------------------------------------

## Les Maisons d'un empire (début de partie, ou empire né en cours de partie). La ruche n'en a pas.
static func found(state: GameState, eid: int, choose := true) -> Dictionary:
	if government(state, eid) == "ruche" or government(state, eid) == "":
		return {}
	var en := {"houses": [], "fiefs": {}, "offices": {}, "minor": {}, "faste": r_int("faste_base"),
			"train": {"table": 0, "fetes": 0, "garde": 0}, "cd": {}, "notes": {}, "levers": {}, "fronde": {}, "pacified": {},
			"ult": {}, "ult_cd": 0, "next_ev": state.tick + _ev_gap(state, eid), "fete_until": 0, "sel": 0 if choose else 1,
			"offer": [], "star": -1}
	(state.court["e"] as Dictionary)[str(eid)] = en
	var n := start_count(state, eid) + (1 if choose else 0)
	for v in _draw_vocations(state, eid, n):
		var h := add_house(state, eid, v)
		if choose and (en["offer"] as Array).size() < 4:
			(en["offer"] as Array).append(int(h["id"]))
	if not choose:
		en["offer"] = []
	reconcile(state, eid)
	refresh(state, eid)
	return en


static func start_count(state: GameState, eid: int) -> int:
	return r_int("start_houses") + int(talent(state, eid).get("extra_houses", 0))


static func max_count(state: GameState, eid: int) -> int:
	return r_int("max_houses") + int(talent(state, eid).get("extra_houses", 0))


## Vocations tirées : celles du registre de l'empire d'abord (une au plus), puis les communes.
static func _draw_vocations(state: GameState, eid: int, n: int) -> Array[String]:
	var reg := Events.layer_value(state, eid, "registre")
	var used: Array[String] = []
	for h: Dictionary in houses(state, eid):
		used.append(String(h["voc"]))
	var mine: Array[String] = []
	var common: Array[String] = []
	for v: Dictionary in data()["vocations"]:
		var id := String(v["id"])
		if used.has(id):
			continue
		var regs: Array = v.get("registres", [])
		if regs.is_empty():
			common.append(id)
		elif regs.has(reg):
			mine.append(id)
	var salt := ["voc", eid, state.tick, used.size()]
	var sorter := func(a: String, b: String) -> bool: return _h(state, salt + [a]) < _h(state, salt + [b])
	mine.sort_custom(sorter)
	common.sort_custom(sorter)
	var out: Array[String] = []
	if not mine.is_empty() and used.is_empty():
		out.append(mine[0])
	for id in common:
		if out.size() < n:
			out.append(id)
	for id in mine:
		if out.size() < n and not out.has(id):
			out.append(id)
	return out


static func add_house(state: GameState, eid: int, voc: String, from := -1) -> Dictionary:
	var en := entry(state, eid)
	var hid := int(state.court.get("hid", 1))
	state.court["hid"] = hid + 1
	var reg := Events.layer_value(state, eid, "registre")
	var names: Dictionary = data()["names"]
	var pool: Array = names.get(reg, names.values()[0])
	var taken: Array[String] = []
	for h: Dictionary in houses(state, eid):
		taken.append(String(h["name"]))
	var name := String(pool[_h(state, ["nom", eid, hid]) % pool.size()])
	var tries := 0
	while taken.has(name) and tries < pool.size():
		tries += 1
		name = String(pool[(_h(state, ["nom", eid, hid]) + tries) % pool.size()])
	var cols: Array = data()["colors"]
	var h := {"id": hid, "name": name, "voc": voc, "color": String(cols[hid % cols.size()]), "members": [], "head": -1,
			"rivals": [], "friends": [], "fav": 0, "adj": 0, "scorn": 0, "tier": "neutre", "seat": -1, "kin": 0, "parts": [], "from": from}
	(en["houses"] as Array).append(h)
	var nm := r_int("members_min") + _h(state, ["nb", eid, hid]) % (r_int("members_max") - r_int("members_min") + 1)
	for i in nm:
		add_member(state, eid, h, i == 0)
	_pick_head(state, eid, h)
	_pick_rivals(state, eid)
	return h


static func add_member(state: GameState, eid: int, h: Dictionary, elder := false) -> Dictionary:
	var mid := int(state.court.get("next", 1))
	state.court["next"] = mid + 1
	var salt := ["membre", eid, mid]
	var nm := Rulers._name_pick(state, eid, salt)
	var ages: Array = rules()["member_age"]
	var a := int(ages[0]) + _h(state, salt + ["age"]) % (int(ages[1]) - int(ages[0]) + 1)
	if elder:
		a = maxi(a, 40)
	var v := voc_def(String(h["voc"]))
	var apt := {"gestion": 0, "guerre": 0, "eloquence": 0, "intrigue": 0}
	var main := String(v.get("apt", "gestion"))
	apt[main] = 1 + _h(state, salt + ["main"]) % 3
	for i in 2 + _h(state, salt + ["pts"]) % 3:
		var k: String = APTS[_h(state, salt + ["apt", i]) % APTS.size()]
		apt[k] = mini(6, int(apt[k]) + 1)
	var traits: Array = []
	var vt: Array = v.get("traits", [])
	if not vt.is_empty():
		traits.append(String(vt[_h(state, salt + ["tr"]) % vt.size()]))
	if _h(state, salt + ["tr2"]) % 100 < 40:
		var all := (data()["traits"] as Dictionary).keys()
		all.sort()
		var t2 := String(all[_h(state, salt + ["tr3"]) % all.size()])
		if not traits.has(t2):
			traits.append(t2)
	var life := r_int("member_life") + _h(state, salt + ["vie"]) % 15
	@warning_ignore("integer_division")
	life = life * (100 + int(talent(state, eid).get("member_life_pct", 0))) / 100
	if Rulers._sp_arch(state, eid) == "synthetique" or Rulers._sp_arch(state, eid) == "energetique":
		life = 0
	var m := {"id": mid, "name": String(nm[0]), "g": String(nm[1]), "born": state.tick - a * DAYS_PER_YEAR, "life": life, "apt": apt, "traits": traits}
	(h["members"] as Array).append(m)
	return m


## Chef de maison : l'aîné, ou l'intrigant qui l'a poussé (head_pct).
static func _pick_head(state: GameState, eid: int, h: Dictionary) -> void:
	var best := -1
	var bv := -100000
	for m: Dictionary in h["members"]:
		var v := age(state, m) + trait_sum(m, "head_pct") + _h(state, ["chef", eid, int(m["id"])]) % 5
		if v > bv:
			bv = v
			best = int(m["id"])
	h["head"] = best


## Rivalités : chaque maison a une rivale (vocations au courant opposé, sinon tirage) et une amie.
static func _pick_rivals(state: GameState, eid: int) -> void:
	var hs := houses(state, eid)
	for h: Dictionary in hs:
		var rv: Array = (h["rivals"] as Array).filter(func(x: Variant) -> bool: return not house(state, eid, int(x)).is_empty())
		h["rivals"] = rv
		var fr: Array = (h["friends"] as Array).filter(func(x: Variant) -> bool: return not house(state, eid, int(x)).is_empty())
		h["friends"] = fr
	for h: Dictionary in hs:
		if not (h["rivals"] as Array).is_empty() or hs.size() < 2:
			continue
		var my := Politics.index_of(String(voc_def(String(h["voc"])).get("current", "")))
		var pick := -1
		for o: Dictionary in hs:
			if int(o["id"]) == int(h["id"]) or (h["friends"] as Array).has(int(o["id"])):
				continue
			var oc := Politics.index_of(String(voc_def(String(o["voc"])).get("current", "")))
			if my >= 0 and oc >= 0 and Politics.opposite(my) == oc:
				pick = int(o["id"])
				break
		if pick < 0:
			var cands: Array[int] = []
			for o: Dictionary in hs:
				if int(o["id"]) != int(h["id"]) and not (h["friends"] as Array).has(int(o["id"])):
					cands.append(int(o["id"]))
			if cands.is_empty():
				continue
			pick = cands[_h(state, ["rivale", eid, int(h["id"])]) % cands.size()]
		(h["rivals"] as Array).append(pick)
		var o2 := house(state, eid, pick)
		if not (o2["rivals"] as Array).has(int(h["id"])):
			(o2["rivals"] as Array).append(int(h["id"]))
	for h: Dictionary in hs:
		if not (h["friends"] as Array).is_empty() or hs.size() < 3:
			continue
		for o: Dictionary in hs:
			if int(o["id"]) != int(h["id"]) and not (h["rivals"] as Array).has(int(o["id"])) and (o["friends"] as Array).is_empty():
				(h["friends"] as Array).append(int(o["id"]))
				(o["friends"] as Array).append(int(h["id"]))
				break


## Une maison disparaît (renvoyée, brisée, partie en sécession) : offices et fiefs libérés.
static func remove_house(state: GameState, eid: int, hid: int) -> void:
	var en := entry(state, eid)
	var h := house(state, eid, hid)
	if h.is_empty():
		return
	for m: Dictionary in h["members"]:
		_vacate_member(state, eid, int(m["id"]))
	(en["houses"] as Array).erase(h)
	var f: Dictionary = en["fiefs"]
	for k in f.keys():
		if int(f[k]) == hid:
			f.erase(k)
	for d in ["levers", "fronde"]:
		(en[d] as Dictionary).erase(str(hid))
	for id in Heroes.ids_of(state, eid):
		if int(state.heroes[id].get("house", -1)) == hid:
			state.heroes[id].erase("house")
	_pick_rivals(state, eid)
	Relics.touch(state)


static func _vacate_member(state: GameState, eid: int, mid: int) -> void:
	var en := entry(state, eid)
	var offs: Dictionary = en["offices"]
	for k in offs.keys():
		var o: Dictionary = offs[k]
		if String(o["k"]) == "m" and int(o["id"]) == mid:
			offs.erase(k)
	var mi: Dictionary = en["minor"]
	for k in mi.keys():
		if int(mi[k]) == mid:
			mi.erase(k)
	if int(en.get("star", -1)) == mid:
		en["star"] = -1


## Un membre quitte la cour (mort, exil, prison, élevé au rang de héros).
static func remove_member(state: GameState, eid: int, mid: int) -> void:
	var h := house_of_member(state, eid, mid)
	if h.is_empty():
		return
	_vacate_member(state, eid, mid)
	var ms: Array = h["members"]
	for m: Dictionary in ms:
		if int(m["id"]) == mid:
			ms.erase(m)
			break
	if ms.is_empty():
		add_member(state, eid, h, true)
	if int(h["head"]) == mid or head(h).is_empty():
		_pick_head(state, eid, h)
	Relics.touch(state)


# --- Fiefs -------------------------------------------------------------------------------------

## Fiefs à jour : systèmes perdus rendus, nouveaux systèmes donnés à la maison qui en a le moins,
## nouvelle maison quand l'empire grandit (un par per_systems systèmes, plafond max_houses), sièges.
static func reconcile(state: GameState, eid: int) -> void:
	var en := entry(state, eid)
	if en.is_empty():
		return
	var cap := FactionTraits.capital_system(state, eid)
	var owned := Stability.systems_of(state, eid)
	var f: Dictionary = en["fiefs"]
	for k in f.keys():
		var sid := int(k)
		if sid == cap or not owned.has(sid) or house(state, eid, int(f[k])).is_empty():
			f.erase(k)
	if int(en.get("sel", 1)) == 1 and houses(state, eid).size() < max_count(state, eid):
		@warning_ignore("integer_division")
		var want := start_count(state, eid) + owned.size() / maxi(1, r_int("per_systems"))
		if houses(state, eid).size() < mini(want, max_count(state, eid)):
			var vs := _draw_vocations(state, eid, 1)
			if not vs.is_empty():
				var h := add_house(state, eid, vs[0])
				h["adj"] = 10
				state.add_chronicle("Une nouvelle famille monte à la cour de %s : %s %s, des %s." % [state.get_empire(eid).display_name(),
						String(words(state, eid)["the"]), String(h["name"]), String(voc_def(vs[0]).get("label", "")).to_lower()],
						Espionage.private_to(state, [eid]))
	var hs := houses(state, eid)
	if hs.is_empty():
		return
	for sid in owned:
		if sid == cap or f.has(str(sid)):
			continue
		var best: Dictionary = {}
		var bn := 1000000
		for h: Dictionary in hs:
			if (en["fronde"] as Dictionary).has(str(int(h["id"]))):
				continue
			var n := fiefs_of(state, eid, int(h["id"])).size()
			if n < bn:
				bn = n
				best = h
		if best.is_empty():
			best = hs[0]
		f[str(sid)] = int(best["id"])
	for h: Dictionary in hs:
		var seat := -1
		var sp := -1
		for sid in fiefs_of(state, eid, int(h["id"])):
			var p := Stability.system_pop(state, sid, eid)
			if p > sp:
				sp = p
				seat = sid
		h["seat"] = seat
	var sys: Dictionary = state.court["sys"]
	for k in sys.keys():
		if int(sys[k]) == eid and not owned.has(int(k)):
			sys.erase(k)
	for sid in owned:
		if sid != cap:
			sys[str(sid)] = eid


## Donne un fief à une maison (révocation pour l'ancienne).
static func set_fief(state: GameState, eid: int, sid: int, hid: int) -> void:
	(entry(state, eid)["fiefs"] as Dictionary)[str(sid)] = hid
	reconcile(state, eid)
	Relics.touch(state)


# --- Offices et postes -------------------------------------------------------------------------

## Offices tenus par une maison (ses membres, ou ses héros qui en sont issus).
static func offices_of(state: GameState, eid: int, hid: int) -> Array[String]:
	var out: Array[String] = []
	var offs: Dictionary = entry(state, eid).get("offices", {})
	for k in offs:
		if holder_house(state, eid, offs[k]) == hid:
			out.append(String(k))
	out.sort()
	return out


static func holder_house(state: GameState, eid: int, o: Dictionary) -> int:
	if String(o.get("k", "")) == "m":
		return int(house_of_member(state, eid, int(o["id"])).get("id", -1))
	var hh: Dictionary = state.heroes.get(int(o.get("id", -1)), {})
	return int(hh.get("house", -1))


## Aptitudes d'un titulaire : membre (traits compris) ou héros (sa classe vaut 1 + niveau / 2).
static func holder_apts(state: GameState, eid: int, o: Dictionary) -> Dictionary:
	if String(o.get("k", "")) == "m":
		return apts(member(state, eid, int(o["id"])))
	var out := {"gestion": 1, "guerre": 1, "eloquence": 1, "intrigue": 1}
	var hh: Dictionary = state.heroes.get(int(o.get("id", -1)), {})
	if not hh.is_empty():
		@warning_ignore("integer_division")
		out[Rulers.apt_of_cls(String(hh["cls"]))] = mini(6, 1 + int(hh.get("lvl", 1)) / 2 + 1)
	return out


static func holder_name(state: GameState, eid: int, o: Dictionary) -> String:
	if String(o.get("k", "")) == "m":
		var m := member(state, eid, int(o["id"]))
		var h := house_of_member(state, eid, int(o["id"]))
		return "%s %s" % [String(m.get("name", "?")), String(h.get("name", ""))]
	return String((state.heroes.get(int(o.get("id", -1)), {}) as Dictionary).get("name", "?"))


## Titulaire valide d'un office ({} si vacant, ou si le titulaire a disparu).
static func holder(state: GameState, eid: int, office: String) -> Dictionary:
	var o: Dictionary = (entry(state, eid).get("offices", {}) as Dictionary).get(office, {})
	if o.is_empty():
		return {}
	if String(o["k"]) == "m":
		return o if not member(state, eid, int(o["id"])).is_empty() else {}
	var hh: Dictionary = state.heroes.get(int(o["id"]), {})
	return o if not hh.is_empty() and int(hh["owner"]) == eid and not Heroes.is_prisoner(hh) else {}


## Aptitude d'un office (0 si vacant).
static func office_apt(state: GameState, eid: int, office: String) -> int:
	var o := holder(state, eid, office)
	if o.is_empty():
		return 0
	return int(holder_apts(state, eid, o).get(String(office_def(office).get("apt", "gestion")), 0))


static func minor_apt(state: GameState, eid: int, post: String) -> int:
	var mid := int((entry(state, eid).get("minor", {}) as Dictionary).get(post, -1))
	if mid < 0:
		return 0
	var m := member(state, eid, mid)
	return int(apts(m).get(String(minor_def(post).get("apt", "gestion")), 0)) if not m.is_empty() else 0


# --- Faveur ------------------------------------------------------------------------------------

## Sources de faveur d'une maison : [[libellé, valeur], …].
static func parts(state: GameState, eid: int, h: Dictionary) -> Array:
	var out := []
	var v := voc_def(String(h["voc"]))
	var hid := int(h["id"])
	if int(h.get("adj", 0)) != 0:
		out.append(["Humeur (présents, offenses, souvenirs)", int(h["adj"])])
	if int(h.get("scorn", 0)) != 0:
		out.append(["Délaissée (aucun office)", int(h["scorn"])])
	# Équité des fiefs.
	var hs := houses(state, eid)
	var total := 0
	for o: Dictionary in hs:
		total += fiefs_of(state, eid, int(o["id"])).size()
	if hs.size() >= 2 and total >= hs.size():
		var mine := fiefs_of(state, eid, hid).size()
		var avg := float(total) / hs.size()
		if mine < avg - 1.0:
			out.append(["Moins de fiefs que les autres", -r_int("equity")])
		elif mine > avg + 1.0:
			@warning_ignore("integer_division")
			out.append(["Plus de fiefs que les autres", r_int("equity") / 2])
	# Offices.
	var offs := offices_of(state, eid, hid)
	if not offs.is_empty():
		out.append(["Grands offices (%d)" % offs.size(), mini(r_int("office_fav_max"), offs.size() * r_int("office_fav"))])
	# Légitimité du souverain.
	if Rulers.has_ruler(state, eid):
		var l := Rulers.legitimacy(state, eid)
		if l >= Rulers.r_int("legit_high"):
			out.append(["Souverain légitime", r_int("legit_high")])
		elif l <= Rulers.r_int("legit_low"):
			out.append(["Souverain contesté", r_int("legit_low")])
	# Stabilité de ses fiefs.
	var fs := fiefs_of(state, eid, hid)
	if not fs.is_empty() and Stability.applies(state, eid):
		var sum := 0
		for sid in fs:
			sum += Stability.value(state, sid)
		@warning_ignore("integer_division")
		var avg_s := sum / fs.size()
		if avg_s < r_int("stab_low"):
			out.append(["Fiefs agités", r_int("stab_low_fav")])
		elif avg_s >= r_int("stab_high"):
			out.append(["Fiefs prospères", r_int("stab_high_fav")])
	# Désirs.
	for c: Dictionary in v.get("likes", []) + v.get("dislikes", []):
		var n := _cond(state, eid, h, c)
		if n != 0:
			out.append([String(c.get("label", "?")), n])
	# Biens de luxe préférés.
	if Goods.active(state):
		var have := false
		var gl := PackedStringArray()
		for g in v.get("goods", []):
			gl.append(Goods.label(String(g)))
			if Goods.has_luxury(state, eid, String(g)):
				have = true
		out.append([("Ses luxes (%s)" if have else "Privée de ses luxes (%s)") % ", ".join(gl), r_int("goods_have") if have else r_int("goods_miss")])
	# Courant politique.
	if Politics.applies(state, eid):
		var ci := Politics.index_of(String(v.get("current", "")))
		if ci >= 0 and Politics.in_power(state, eid, ci):
			out.append(["%s au pouvoir" % Politics.short(state, eid, ci), r_int("current_power")])
		elif ci >= 0 and Politics.lead(state, eid) == Politics.opposite(ci):
			out.append(["%s au pouvoir" % Politics.short(state, eid, Politics.opposite(ci)), r_int("current_opposite")])
	if int(h.get("kin", 0)) == 1:
		out.append(["Liée au trône par un mariage", 10])
	# Humeur du chef.
	@warning_ignore("integer_division")
	var op := trait_sum(head(h), "op") / 3
	if op != 0:
		out.append(["Caractère de son chef", op])
	# Rivales et amies en charge.
	for rid in h.get("rivals", []):
		if not offices_of(state, eid, int(rid)).is_empty():
			out.append(["Sa rivale %s en charge" % String(house(state, eid, int(rid)).get("name", "")), r_int("rival_both_office")])
			break
	for fid in h.get("friends", []):
		if not offices_of(state, eid, int(fid)).is_empty():
			out.append(["Son amie %s en charge" % String(house(state, eid, int(fid)).get("name", "")), r_int("friend_office")])
			break
	out.append_array(CourtBridges.favor_parts(state, eid, h))
	return out


## Valeur d'un désir (likes/dislikes) pour une maison.
static func _cond(state: GameState, eid: int, h: Dictionary, c: Dictionary) -> int:
	var v := int(c.get("v", 0))
	var hid := int(h["id"])
	match String(c.get("k", "")):
		"law":
			return v if Laws.applies(state, eid) and Laws.is_enacted(state, eid, String(c["id"])) else 0
		"building":
			var n := 0
			for sid in fiefs_of(state, eid, hid):
				for pid in state.galaxy.systems[sid].planet_ids:
					var col: Colony = state.colonies.get(pid)
					if col != null and col.owner == eid:
						n += col.buildings.count(String(c["id"]))
			return mini(int(c.get("max", 99)), n * int(c.get("per", 0)))
		"fiefs_most", "fiefs_least":
			var mine := fiefs_of(state, eid, hid).size()
			var top := true
			var low := true
			for o: Dictionary in houses(state, eid):
				if int(o["id"]) == hid:
					continue
				var n2 := fiefs_of(state, eid, int(o["id"])).size()
				if n2 >= mine:
					top = false
				if n2 <= mine:
					low = false
			return v if (top if String(c["k"]) == "fiefs_most" else low) else 0
		"office":
			return v if not offices_of(state, eid, hid).is_empty() else 0
		"no_office":
			return v if offices_of(state, eid, hid).is_empty() else 0
		"office_id":
			var o := holder(state, eid, String(c["id"]))
			if o.is_empty():
				return 0
			var oh := holder_house(state, eid, o)
			return v if oh == hid or (h.get("friends", []) as Array).has(oh) else 0
		"war":
			var e := state.get_empire(eid)
			return v if e != null and not e.wars.is_empty() else 0
		"long_peace":
			var e2 := state.get_empire(eid)
			return v if e2 != null and e2.wars.is_empty() and Stability._days_since_war(state, eid) >= int(c.get("years", 10)) * DAYS_PER_YEAR else 0
		"faith":
			return v if state.faith_on and Faiths.state_faith(state, eid) != "" else 0
		"kin":
			return v if int(h.get("kin", 0)) == 1 else 0
		"minor_ruler":
			return v if not state.rulers.is_empty() and RulersDynasty.in_regency(state, eid) else 0
		"fleets":
			var n3 := 0
			for fid in state.sorted_fleet_ids():
				var f: Fleet = state.fleets[fid]
				if f.owner == eid and Combat.is_armed(f):
					n3 += 1
			return v if n3 >= int(c.get("n", 1)) else 0
		"stat":
			return v if DeedsEval.value(state, eid, String(c["id"])) >= int(c.get("n", 1)) else 0
	return 0


## Recalcule la faveur et le palier de chaque maison (le cache des effets saute si un palier change).
static func refresh(state: GameState, eid: int) -> void:
	var changed := false
	for h: Dictionary in houses(state, eid):
		var p := parts(state, eid, h)
		var sum := 0
		for x in p:
			sum += int(x[1])
		h["parts"] = p
		h["fav"] = clampi(sum, r_int("fav_min"), r_int("fav_max"))
		var t := tier_id(h)
		if t != String(h.get("tier", "")):
			h["tier"] = t
			changed = true
	if changed:
		Relics.touch(state)


## Humeur d'une maison (présents, offenses) ; le palier suit tout de suite (now) ou au prochain bilan.
static func adjust(state: GameState, eid: int, hid: int, n: int, now := true) -> void:
	var h := house(state, eid, hid)
	if h.is_empty() or n == 0:
		return
	h["adj"] = clampi(int(h.get("adj", 0)) + n, r_int("adj_min"), r_int("adj_max"))
	if now:
		refresh(state, eid)


static func adjust_all(state: GameState, eid: int, n: int, except := -1) -> void:
	for h: Dictionary in houses(state, eid):
		if int(h["id"]) != except:
			adjust(state, eid, int(h["id"]), n, false)
	refresh(state, eid)


# --- Effets ------------------------------------------------------------------------------------

## Production d'une colonie : palier de la maison qui tient le fief, et ressources de sa vocation.
static func adjust_yields(state: GameState, colony: Colony, sid: int, gross: Dictionary) -> void:
	if state.court.is_empty():
		return
	var h := fief_house(state, sid, colony.owner)
	if h.is_empty():
		return
	var pct := int(tier(h).get("prod", 0))
	var sys: Dictionary = voc_def(String(h["voc"])).get("sys", {})
	for r in gross:
		var p := pct + (int(sys.get(r, 0)) if serves(h) else 0)
		if p != 0 and int(gross[r]) > 0:
			@warning_ignore("integer_division")
			gross[r] = int(gross[r]) * (100 + p) / 100


## Lignes de stabilité d'un système tenu en fief.
static func stability_parts(state: GameState, sid: int, owner: int) -> Array:
	var out := []
	if state.court.is_empty():
		return out
	var h := fief_house(state, sid, owner)
	if not h.is_empty():
		var t := tier(h)
		if int(t.get("stab", 0)) != 0:
			out.append(["Fief de %s (%s)" % [String(h["name"]), String(t["label"]).to_lower()], int(t["stab"])])
		var vs := int(voc_def(String(h["voc"])).get("sys_stab", 0))
		if vs != 0 and serves(h):
			out.append(["Fief des %s" % String(voc_def(String(h["voc"]))["label"]), vs])
		var en := entry(state, owner)
		if int((en["fronde"] as Dictionary).get(str(int(h["id"])), 0)) > state.tick:
			out.append(["%s de %s" % [String(words(state, owner)["fronde"]), String(h["name"])], r_int("fronde_stab")])
	var pac := int((entry(state, owner).get("pacified", {}) as Dictionary).get(str(sid), 0))
	if pac > state.tick:
		out.append(["Pacifié par l'Intendant", r_int("pacify_stab")])
	return out


## Lignes de stabilité de tout l'empire : Grand Aumônier, cour austère.
static func empire_stability_parts(state: GameState, eid: int) -> Array:
	var out := []
	if not applies(state, eid):
		return out
	if office_ids(state, eid).has("aumonier"):
		@warning_ignore("integer_division")
		var n := office_apt(state, eid, "aumonier") / 2 * int(office_def("aumonier").get("stab_per2", 1))
		if n != 0:
			out.append([office_label(state, eid, "aumonier"), n])
	out.append_array(CourtBridges.stability_parts(state, eid))
	return out


## Effets au format des technologies (fusionnés dans Research.effects).
static func effects(state: GameState, eid: int) -> Dictionary:
	var out := {}
	if not applies(state, eid):
		return out
	var hs := houses(state, eid)
	var ground := 0
	for h: Dictionary in hs:
		ground += int(tier(h).get("ground", 0))
		if serves(h):
			Rulers._add_fx(out, voc_def(String(h["voc"])).get("seat", {}))
	if not hs.is_empty() and ground != 0:
		@warning_ignore("integer_division")
		Research._merge(out, {"ground_damage_pct": ground / hs.size()})
	for oid in office_ids(state, eid):
		var a := office_apt(state, eid, oid)
		if a <= 0:
			continue
		Research._merge(out, _scale(office_def(oid).get("fx_per", {}), a))
	Rulers._add_fx(out, CourtBridges.effects(state, eid))
	return out


static func _scale(fx: Dictionary, n: int) -> Dictionary:
	var out := {}
	for k in fx:
		if fx[k] is Dictionary:
			out[k] = _scale(fx[k], n)
		else:
			out[k] = int(fx[k]) * n
	return out


## Influence mensuelle : Grand Héraut, faste.
static func income(state: GameState, eid: int) -> Dictionary:
	if not applies(state, eid):
		return {}
	var n := office_apt(state, eid, "heraut") * int(office_def("heraut").get("influence_per", 1))
	n += int(CourtBridges.faste_tier(state, eid).get("influence", 0))
	return {"influence": n} if n > 0 else {}


## Chiffrement : Maître des Murmures (un point par tranche de deux).
static func encryption(state: GameState, eid: int) -> int:
	if not applies(state, eid):
		return 0
	@warning_ignore("integer_division")
	return office_apt(state, eid, "murmures") / 2


## Loyauté en plus d'un héros issu d'une maison (selon sa faveur).
static func hero_loyalty(state: GameState, h: Dictionary) -> int:
	if state.court.is_empty() or int(h.get("house", -1)) < 0:
		return 0
	var hh := house(state, int(h["owner"]), int(h["house"]))
	if hh.is_empty():
		return 0
	return int((rules()["hero_loyalty"] as Dictionary).get(tier_id(hh), 0))


## Un héros recruté peut venir d'une maison (un sur trois) : sa loyauté suivra la faveur.
static func on_hero_recruit(state: GameState, eid: int, hid: int) -> void:
	if not applies(state, eid) or not state.heroes.has(hid):
		return
	var hs := houses(state, eid)
	if hs.is_empty() or _h(state, ["recrue", eid, hid]) % 3 != 0:
		return
	state.heroes[hid]["house"] = int((hs[_h(state, ["recrue_m", eid, hid]) % hs.size()] as Dictionary)["id"])


## Garde du corps : points retirés aux chances d'assassinat.
static func guard_pts(state: GameState, eid: int) -> int:
	return minor_apt(state, eid, "garde") * r_int("garde_pts") if applies(state, eid) else 0


## Médecin de la cour : % retiré au risque de mort de vieillesse.
static func medic_pct(state: GameState, eid: int) -> int:
	return mini(90, minor_apt(state, eid, "medecin") * r_int("medecin_pct")) if applies(state, eid) else 0


## Précepteur : % de chances d'un point de plus à l'éducation d'un héritier.
static func tutor_pct(state: GameState, eid: int) -> int:
	return minor_apt(state, eid, "precepteur") * r_int("precepteur_pct") if applies(state, eid) else 0


## Nouveau souverain : sa maison (s'il en sort une) s'en réjouit, les autres s'inquiètent un peu ; les
## mariages du règne passé ne lient plus personne.
static func on_new_ruler(state: GameState, eid: int, r: Dictionary) -> void:
	if not applies(state, eid):
		return
	var hn := String(r.get("house", ""))
	for h: Dictionary in houses(state, eid):
		h["kin"] = 0
		adjust(state, eid, int(h["id"]), r_int("new_ruler_adj") if String(h["name"]) == hn else r_int("new_ruler_others"), false)
	refresh(state, eid)


## La maison la plus favorable ({} sans maisons).
static func strongest_house(state: GameState, eid: int) -> Dictionary:
	var best: Dictionary = {}
	for h: Dictionary in houses(state, eid):
		if best.is_empty() or favor(h) > favor(best):
			best = h
	return best


## Régent possible : le chef de la maison la plus dévouée (Dévouée seulement), {} sinon.
static func devoted_head(state: GameState, eid: int) -> Dictionary:
	var h := strongest_house(state, eid)
	if h.is_empty() or tier_id(h) != "devouee":
		return {}
	var m := head(h)
	return {"name": "%s %s" % [String(m.get("name", "?")), String(h["name"])], "apt": apts(m)} if not m.is_empty() else {}


# --- Jour par jour -----------------------------------------------------------------------------

static func daily(state: GameState) -> Array[Dictionary]:
	var added: Array[Dictionary] = []
	if state.court.is_empty():
		return added
	if posmod(state.tick, r_int("check_days")) != r_int("offset"):
		return added
	# Empires nés en cours de partie (sécession, partage, guerre civile) : leurs maisons, sans choix.
	for e in state.empires:
		if e.eliminated or e.is_npc() or (state.court["e"] as Dictionary).has(str(e.id)) or government(state, e.id) == "ruche":
			continue
		found(state, e.id, false)
	CourtIntrigue.conquests(state, added)
	var keys := (state.court["e"] as Dictionary).keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return int(a) < int(b))
	for k in keys:
		var eid := int(k)
		var e := state.get_empire(eid)
		if e == null or e.eliminated:
			continue
		month(state, eid, added)
	CourtIntrigue.monthly_all(state, added)
	return added


static func month(state: GameState, eid: int, added: Array[Dictionary]) -> void:
	var en := entry(state, eid)
	if int(en.get("sel", 1)) == 0:
		CourtIntrigue.offer_houses(state, eid, added)
	reconcile(state, eid)
	_members_month(state, eid, added)
	_scorn_month(state, eid)
	for h: Dictionary in houses(state, eid):
		var a := int(h.get("adj", 0))
		if a != 0:
			h["adj"] = a - signi(a) * mini(absi(a), r_int("adj_decay"))
	refresh(state, eid)
	CourtBridges.monthly(state, eid, added)
	CourtIntrigue.monthly(state, eid, added)
	refresh(state, eid)


## Les membres vieillissent et meurent ; les chefs se succèdent ; des cousins arrivent.
static func _members_month(state: GameState, eid: int, added: Array[Dictionary]) -> void:
	var warn := int(Heroes.data()["life"]["warn"])
	var per_year := int(Heroes.data()["life"]["per_year_pct"])
	var medic := medic_pct(state, eid)
	for h: Dictionary in houses(state, eid).duplicate():
		for m: Dictionary in (h["members"] as Array).duplicate():
			var life := int(m.get("life", 0))
			if life <= 0:
				continue
			var a := age(state, m)
			var from := life - warn
			if a < from:
				continue
			@warning_ignore("integer_division")
			var per_mille := (a - from + 1) * per_year * 10 / 12 * (100 - medic) / 100
			if _h(state, ["mort_m", eid, int(m["id"]), state.tick]) % 1000 >= per_mille:
				continue
			var was_head := int(h["head"]) == int(m["id"])
			remove_member(state, eid, int(m["id"]))
			if was_head:
				var nh := head(h)
				added.append(state.add_chronicle("%s %s, %s, s'éteint à %d ans. %s lui succède à la tête de %s %s." % [String(m["name"]), String(h["name"]),
						String(words(state, eid)["head"]), a, String(nh.get("name", "?")), String(words(state, eid)["the"]), String(h["name"])],
						Espionage.private_to(state, [eid])))
		if (h["members"] as Array).size() < r_int("members_max") and _h(state, ["cousin", eid, int(h["id"]), state.tick]) % 24 == 0:
			add_member(state, eid, h)


## Une maison sans office s'aigrit doucement (deux fois plus vite si son chef est fier).
static func _scorn_month(state: GameState, eid: int) -> void:
	for h: Dictionary in houses(state, eid):
		if offices_of(state, eid, int(h["id"])).is_empty():
			var step := r_int("scorn_month") * trait_max(head(h), "scorn_x")
			h["scorn"] = maxi(r_int("scorn_min"), int(h.get("scorn", 0)) + step)
		else:
			h["scorn"] = mini(0, int(h.get("scorn", 0)) + r_int("scorn_others"))


static func _ev_gap(state: GameState, eid: int) -> int:
	var ev: Array = rules()["event_every"]
	return int(ev[0]) + _h(state, ["ev_gap", eid, state.tick]) % maxi(1, int(ev[1]) - int(ev[0]) + 1)


# --- Ordres ------------------------------------------------------------------------------------

## act : appoint (s = office, x = id, y = 1 pour un héros) | vacate (s) | minor (s = poste, x = membre,
## -1 pour libérer) | grant (x = système, y = maison) | missions et intrigues (voir CourtIntrigue).
static func check_act(state: GameState, eid: int, act_: String, x: int, y: int, s: String) -> String:
	if not applies(state, eid):
		return "pas de cour dans cette partie"
	var en := entry(state, eid)
	match act_:
		"appoint":
			if not office_ids(state, eid).has(s):
				return "office inconnu"
			if y == 1:
				var hh: Dictionary = state.heroes.get(x, {})
				if hh.is_empty() or int(hh["owner"]) != eid or Heroes.is_prisoner(hh):
					return "héros indisponible"
			elif member(state, eid, x).is_empty():
				return "courtisan introuvable"
			var kk := "h" if y == 1 else "m"
			for k in (en["offices"] as Dictionary):
				var o: Dictionary = en["offices"][k]
				if String(k) != s and String(o["k"]) == kk and int(o["id"]) == x:
					return "il tient déjà un autre office"
			var cur := holder(state, eid, s)
			if not cur.is_empty() and String(cur["k"]) == kk and int(cur["id"]) == x:
				return "il tient déjà cet office"
			return ""
		"vacate":
			return "" if not holder(state, eid, s).is_empty() else "office déjà vacant"
		"minor":
			if minor_def(s).is_empty():
				return "poste inconnu"
			if x >= 0 and member(state, eid, x).is_empty():
				return "courtisan introuvable"
			return ""
		"grant":
			if state.system_owner(x) != eid or x == FactionTraits.capital_system(state, eid):
				return "ce système ne peut pas être donné en fief"
			if house(state, eid, y).is_empty():
				return "maison introuvable"
			if int((en["fiefs"] as Dictionary).get(str(x), -1)) == y:
				return "elle tient déjà ce fief"
			if not Economy.can_afford(state.get_empire(eid), rules()["grant_cost"]):
				return "pas assez d'influence"
			return ""
	return CourtIntrigue.check_act(state, eid, act_, x, y, s)


static func act(state: GameState, eid: int, act_: String, x: int, y: int, s: String, added: Array[Dictionary]) -> void:
	var en := entry(state, eid)
	var e := state.get_empire(eid)
	match act_:
		"appoint":
			var old := holder(state, eid, s)
			if not old.is_empty():
				var oh := holder_house(state, eid, old)
				if oh >= 0:
					adjust(state, eid, oh, r_int("revoke_adj") * _revoke_x(state, eid, house(state, eid, oh)), false)
			(en["offices"] as Dictionary)[s] = {"k": "h" if y == 1 else "m", "id": x}
			var nh := holder_house(state, eid, en["offices"][s])
			if nh >= 0:
				adjust(state, eid, nh, r_int("appoint_adj"), false)
			var sell := int(talent(state, eid).get("sell_office", 0))
			if sell > 0:
				e.resources["energy"] = int(e.resources.get("energy", 0)) + sell
			refresh(state, eid)
			Relics.touch(state)
		"vacate":
			var oh2 := holder_house(state, eid, holder(state, eid, s))
			(en["offices"] as Dictionary).erase(s)
			if oh2 >= 0:
				adjust(state, eid, oh2, r_int("revoke_adj") * _revoke_x(state, eid, house(state, eid, oh2)), false)
			refresh(state, eid)
			Relics.touch(state)
		"minor":
			var mi: Dictionary = en["minor"]
			if x < 0:
				mi.erase(s)
			else:
				for k in mi.keys():
					if int(mi[k]) == x:
						mi.erase(k)
				mi[s] = x
				var mh := house_of_member(state, eid, x)
				if not mh.is_empty():
					@warning_ignore("integer_division")
					adjust(state, eid, int(mh["id"]), r_int("appoint_adj") / 3)
		"grant":
			Economy.pay(e, rules()["grant_cost"])
			var prev := int((en["fiefs"] as Dictionary).get(str(x), -1))
			if prev >= 0 and not house(state, eid, prev).is_empty():
				adjust(state, eid, prev, r_int("revoke_fief_adj") * _revoke_x(state, eid, house(state, eid, prev)), false)
				adjust_all(state, eid, r_int("revoke_others"), prev)
				Rulers.adjust(state, eid, r_int("revoke_legit"))
			adjust(state, eid, y, r_int("grant_adj"), false)
			set_fief(state, eid, x, y)
			refresh(state, eid)
		_:
			CourtIntrigue.act(state, eid, act_, x, y, s, added)


## Multiplicateur d'une révocation : chef rancunier, credo de l'honneur.
static func _revoke_x(state: GameState, eid: int, h: Dictionary) -> int:
	return maxi(trait_max(head(h), "revoke_x"), maxi(1, int(talent(state, eid).get("revoke_x", 0))))


# --- Cartes (voir Events) ----------------------------------------------------------------------

static func _note(state: GameState, eid: int, ev_id: int, d: Dictionary) -> void:
	var notes: Dictionary = entry(state, eid)["notes"]
	notes[str(ev_id)] = d
	var keys := notes.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return int(a) < int(b))
	while keys.size() > 12:
		notes.erase(keys.pop_front())


static func note_of(state: GameState, eid: int, item: Dictionary) -> Dictionary:
	return (entry(state, eid).get("notes", {}) as Dictionary).get(str(int(item.get("id", -1))), {})


## Met une carte de cour dans la boîte, avec sa note (maison h, rivale r, textes).
static func push_card(state: GameState, eid: int, card_id: String, note: Dictionary, added: Array[Dictionary]) -> void:
	var ev := state.next_event_id
	Events.push(state, eid, card_id, {}, added)
	_note(state, eid, ev, note)


static func fill(state: GameState, eid: int, item: Dictionary, s: String) -> String:
	if state.court.is_empty() or not (s.contains("{court_") or s.contains("{house}") or s.contains("{head}") or s.contains("{rival_")):
		return s
	var n := note_of(state, eid, item)
	var out := s
	var h := house(state, eid, int(n.get("h", -1)))
	var r := house(state, eid, int(n.get("r", -1)))
	out = out.replace("{house}", String(h.get("name", n.get("hname", "?"))))
	out = out.replace("{head}", String(head(h).get("name", "?")))
	out = out.replace("{rival_house}", String(r.get("name", "?")))
	out = out.replace("{rival_head}", String(head(r).get("name", "?")))
	for k in n:
		if n[k] is String:
			out = out.replace("{court_%s}" % String(k), String(n[k]))
	if out.contains("{court_offer_"):
		var offer: Array = n.get("offer", [])
		for i in 4:
			var oh := house(state, eid, int(offer[i])) if i < offer.size() else {}
			var lbl := "?"
			if not oh.is_empty():
				var vd := voc_def(String(oh["voc"]))
				lbl = "Renvoyer %s, des %s (%s)" % [String(oh["name"]), String(vd.get("label", "")).to_lower(), String(vd.get("seat_text", ""))]
			out = out.replace("{court_offer_%d}" % i, lbl)
	return out


static func fx_lines(state: GameState, eid: int, item: Dictionary, fx: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var n := note_of(state, eid, item)
	match String(fx.get("act", "")):
		"fav":
			var nm := ""
			match String(fx.get("who", "house")):
				"house":
					nm = String(house(state, eid, int(n.get("h", -1))).get("name", "La maison"))
				"rival":
					nm = String(house(state, eid, int(n.get("r", -1))).get("name", "Sa rivale"))
				"all":
					nm = "Toutes les %s" % String(words(state, eid)["plural"]).to_lower()
				"others":
					nm = "Les autres %s" % String(words(state, eid)["plural"]).to_lower()
			out.append("%s : faveur %+d" % [nm, int(fx.get("n", 0))])
		"faste":
			out.append("Faste %+d" % int(fx.get("n", 0)))
		"pop_stab":
			out.append("Stabilité %+d partout pendant un an" % int(fx.get("v", 0)))
		_:
			out.append_array(CourtIntrigue.fx_lines(state, eid, item, fx, n))
	return out


static func fx_problem(state: GameState, eid: int, item: Dictionary, fx: Dictionary) -> String:
	if not applies(state, eid):
		return "pas de cour"
	return CourtIntrigue.fx_problem(state, eid, item, fx, note_of(state, eid, item))


static func apply_fx(state: GameState, eid: int, item: Dictionary, fx: Dictionary, added: Array[Dictionary]) -> void:
	var en := entry(state, eid)
	if en.is_empty():
		return
	var n := note_of(state, eid, item)
	match String(fx.get("act", "")):
		"fav":
			var v := int(fx.get("n", 0))
			match String(fx.get("who", "house")):
				"house":
					adjust(state, eid, int(n.get("h", -1)), v)
				"rival":
					adjust(state, eid, int(n.get("r", -1)), v)
				"all":
					adjust_all(state, eid, v)
				"others":
					adjust_all(state, eid, v, int(n.get("h", -1)))
		"faste":
			en["faste"] = clampi(int(en["faste"]) + int(fx.get("n", 0)), 0, r_int("faste_max"))
			Relics.touch(state)
		"pop_stab":
			if Stability.applies(state, eid):
				for sid in Stability.systems_of(state, eid):
					var se := Stability._entry_w(state, sid)
					se["ev"] = int(fx.get("v", 0))
					se["ev_end"] = state.tick + DAYS_PER_YEAR
					se["ev_card"] = String(item.get("card", ""))
		_:
			CourtIntrigue.apply_fx(state, eid, item, fx, n, added)


static func ai_value(state: GameState, eid: int, item: Dictionary, fx: Dictionary) -> int:
	var n := note_of(state, eid, item)
	match String(fx.get("act", "")):
		"fav":
			var who := String(fx.get("who", "house"))
			var hh := house(state, eid, int(n.get("r" if who == "rival" else "h", -1)))
			var w := 1
			if not hh.is_empty() and favor(hh) < -20:
				w = 2  # une maison fâchée compte double
			if who == "all" or who == "others":
				w = 3
			return int(fx.get("n", 0)) * w
		"faste":
			return int(fx.get("n", 0))
		"pop_stab":
			return int(fx.get("v", 0)) * 5
	return CourtIntrigue.ai_value(state, eid, item, fx, n)


# --- Résumés -----------------------------------------------------------------------------------

## « La maison Atrevane (Armateurs, satisfaite, 3 fiefs) ».
static func house_summary(state: GameState, eid: int, h: Dictionary) -> String:
	return "%s %s (%s, %s, %d fief(s))" % [ucfirst(String(words(state, eid)["the"])), String(h["name"]),
			String(voc_def(String(h["voc"])).get("label", "")), String(tier(h)["label"]).to_lower(), fiefs_of(state, eid, int(h["id"])).size()]
