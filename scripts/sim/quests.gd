class_name Quests
extends RefCounted
## Quêtes (étude « Événements, quêtes et reliques », 2026-11-12, propositions 8 à 10 et 16, lot 3).
##
## Une quête a des chapitres ; chaque chapitre a deux branches, chacune avec un objectif que la
## simulation vérifie (aller à, tenir, atteindre un seuil, envoyer un héros, démanteler un repaire,
## payer) et une récompense. Les deux objectifs avancent ensemble : le premier rempli choisit la
## branche, comme dans Endless Space 2, et pose une marque que les événements peuvent lire
## (« quete:<modèle>:<chapitre>:<branche> »). Trois familles :
## - quête de peuple, une par credo (5 fils de 4 chapitres), reçue au jour credo_day, avec un héros
##   unique au 3e chapitre et une relique majeure (tag « quete ») au dernier ;
## - quêtes secondaires, nées d'une curiosité sondée, d'un choix d'événement (effet « quest ») ou de
##   l'état de l'empire (repaire connu, système instable, héros…), avec un délai ;
## - quêtes galactiques (réglage « Avec retournements ») : une à la fois pour toute la galaxie.
##   Le passage (compétitive : un artéfact traverse la galaxie, on marque des points près de lui),
##   La Rouille grise (coopérative : un fléau que tous financent, le plus généreux est honoré),
##   le Conclave des Phares (deux camps, des Phares tenus par des héros, d'après l'Académie d'ES2),
##   Le réveil des tombeaux (des gardiens se lèvent après les fouilles ; un peuple synthétique peut
##   parlementer avec eux, talent de la proposition 15 reporté du lot 2).
##
## state.quests[id] = {"id", "tpl", "owner", "ch", "start", "until" (0 = sans délai), "subj":
##   {"system", "rival", "hero", "lair"}, "base": [b0, b1] (valeur de départ des seuils relatifs),
##   "cnt": [c0, c1] (jours tenus, repaire démantelé), "path": [branches prises], "status":
##   "active" | "done" | "failed", "end", "wait" (jour où s'ouvre le chapitre suivant, 0 = ouvert)}.
## state.quest_meta[empire] = {"credo": 0/1 (quête de peuple reçue), "credo_done", "done", "failed",
##   "boons": [{"label", "fx", "until" (0 = permanent)}], "no_offer": jour (Conclave perdu),
##   "seen": {modèle: jour}}.
## state.galactic = {"next": jour du prochain tirage, "seen": [ids], "cur": {} | quête en cours,
##   "log": [{"id", "title", "winner", "tick"}]}.
## Tout est déterministe : entiers, parcours triés, tirages par hachage de la graine.

const CREDO_PREFIX := "credo_"


static func data() -> Dictionary:
	return GameData.quests()


static func rules() -> Dictionary:
	return data()["rules"]


static func modes() -> Array:
	return data()["modes"]


static func mode_def(id: String) -> Dictionary:
	for d: Dictionary in modes():
		if String(d["id"]) == id:
			return d
	return {}


static func default_mode() -> String:
	return String(data().get("default_mode", "toutes"))


static func enabled(state: GameState) -> bool:
	return state.quest_mode != "aucunes" and state.quest_mode != ""


static func galactic_on(state: GameState) -> bool:
	return state.quest_mode == "toutes"


static func tpl(id: String) -> Dictionary:
	return (data()["templates"] as Dictionary).get(id, {})


static func gdef(id: String) -> Dictionary:
	return (data()["galactic"] as Dictionary).get(id, {})


static func _h(state: GameState, parts: Array) -> int:
	return absi(hash([state.seed_value, "quete"] + parts))


static func meta(state: GameState, empire_id: int) -> Dictionary:
	if not state.quest_meta.has(empire_id):
		state.quest_meta[empire_id] = {"credo": 0, "credo_done": 0, "done": 0, "failed": 0, "boons": [], "no_offer": 0, "seen": {}}
	return state.quest_meta[empire_id]


static func setup(state: GameState, mode: String) -> void:
	state.quest_mode = mode if not mode_def(mode).is_empty() else "aucunes"
	state.quests.clear()
	state.quest_meta.clear()
	state.galactic = {"next": int(rules()["galactic_first_day"]), "seen": [], "cur": {}, "log": []}


static func _major(state: GameState, empire_id: int) -> bool:
	var e := state.get_empire(empire_id)
	return e != null and not e.is_npc() and not e.eliminated


## Quêtes d'un empire (en cours d'abord, puis terminées), triées par identifiant.
static func of(state: GameState, empire_id: int, active_only := false) -> Array[int]:
	var ids := state.quests.keys()
	ids.sort()
	var act: Array[int] = []
	var old: Array[int] = []
	for id in ids:
		var q: Dictionary = state.quests[id]
		if int(q["owner"]) != empire_id:
			continue
		if String(q["status"]) == "active":
			act.append(int(id))
		elif not active_only:
			old.append(int(id))
	act.append_array(old)
	return act


static func is_credo(q: Dictionary) -> bool:
	return String(tpl(String(q["tpl"])).get("kind", "")) == "credo"


static func chapters(q: Dictionary) -> Array:
	return tpl(String(q["tpl"]))["chapters"]


static func chapter(q: Dictionary) -> Dictionary:
	var chs := chapters(q)
	return chs[clampi(int(q["ch"]), 0, chs.size() - 1)]


# --- Départ d'une quête -------------------------------------------------------------------------

## Lance une quête pour cet empire (sujets donnés puis tirés). Renvoie son identifiant, -1 sinon.
static func start(state: GameState, empire_id: int, tpl_id: String, given: Dictionary, added: Array[Dictionary]) -> int:
	var t := tpl(tpl_id)
	if t.is_empty() or not enabled(state) or not _major(state, empire_id):
		return -1
	var subj := _subjects(state, empire_id, tpl_id, given)
	if subj.is_empty():
		return -1
	var id := state.next_quest_id
	state.next_quest_id += 1
	var q := {"id": id, "tpl": tpl_id, "owner": empire_id, "ch": 0, "start": state.tick,
			"until": state.tick + int(t["days"]) if int(t.get("days", 0)) > 0 else 0,
			"subj": subj, "base": [0, 0], "cnt": [0, 0], "path": [], "status": "active", "end": 0, "wait": 0}
	state.quests[id] = q
	(meta(state, empire_id)["seen"] as Dictionary)[tpl_id] = state.tick
	_begin_chapter(state, q)
	added.append(state.add_chronicle("Nouvelle quête pour %s : « %s ». %s" % [state.get_empire(empire_id).short_name(), title(state, q),
			"Le récit commence (Chroniques, onglet Quêtes)."], Espionage.private_to(state, [empire_id])))
	return id


static func _subjects(state: GameState, empire_id: int, tpl_id: String, given: Dictionary) -> Dictionary:
	var t := tpl(tpl_id)
	var wanted: Dictionary = t.get("subjects", {})
	var subj := {"system": int(given.get("system", -1)), "rival": int(given.get("rival", -1)),
			"hero": int(given.get("hero", -1)), "lair": int(given.get("lair", -1))}
	if wanted.has("system") and subj["system"] < 0:
		var mode := String(wanted["system"])
		var sid := -1
		if mode == "far":
			sid = far_system(state, empire_id, [tpl_id, state.tick])
		else:
			var cands := Events._systems(state, empire_id, mode)
			if not cands.is_empty():
				sid = cands[_h(state, ["sys", tpl_id, empire_id, state.tick]) % cands.size()]
		if sid < 0:
			return {}
		subj["system"] = sid
	if wanted.has("lair") and subj["lair"] < 0:
		var lairs := Pirates.known_lairs(state, empire_id)
		if lairs.is_empty():
			return {}
		var cap := FactionTraits.capital_system(state, empire_id)
		var jumps := FactionTraits.jumps_from(state.galaxy, cap) if cap >= 0 else {}
		var best := -1
		var bj := 99999
		for sid in lairs:
			var j := int(jumps.get(sid, 9999))
			if j < bj:
				bj = j
				best = sid
		subj["lair"] = best
		subj["system"] = best
	if wanted.has("hero") and subj["hero"] < 0:
		var hs := Events._heroes(state, empire_id, String(wanted["hero"]))
		if hs.is_empty():
			return {}
		subj["hero"] = hs[_h(state, ["hero", tpl_id, empire_id, state.tick]) % hs.size()]
	if wanted.has("rival") and subj["rival"] < 0:
		var rs := Events._rivals(state, empire_id, String(wanted["rival"]))
		if rs.is_empty():
			return {}
		subj["rival"] = rs[_h(state, ["rival", tpl_id, empire_id, state.tick]) % rs.size()]
	return subj


## Un système lointain (au moins far_min_jumps sauts de la capitale), connu, pas à soi, avec des
## planètes. Moins exigeant s'il n'y en a pas. -1 si rien.
static func far_system(state: GameState, empire_id: int, salt: Array) -> int:
	var cap := FactionTraits.capital_system(state, empire_id)
	if cap < 0:
		return -1
	var jumps := FactionTraits.jumps_from(state.galaxy, cap)
	for need in [int(rules()["far_min_jumps"]), 2, 1]:
		var cands: Array[int] = []
		for sys in state.galaxy.systems:
			if sys.planet_ids.is_empty() or int(jumps.get(sys.id, -1)) < need or state.system_owner(sys.id) == empire_id:
				continue
			if Pirates.is_lair(state, sys.id) or not Fleets.is_known(state, empire_id, sys.id):
				continue
			cands.append(sys.id)
		if not cands.is_empty():
			return cands[_h(state, ["far", empire_id] + salt) % cands.size()]
	return -1


static func _begin_chapter(state: GameState, q: Dictionary) -> void:
	var brs: Array = chapter(q)["branches"]
	var base: Array = [0, 0]
	for i in brs.size():
		var g: Dictionary = brs[i]["goal"]
		if String(g["k"]) == "stat" and not bool(g.get("abs", false)):
			base[i] = stat_now(state, int(q["owner"]), String(g["stat"]))
	q["base"] = base
	q["cnt"] = [0, 0]


# --- Objectifs ----------------------------------------------------------------------------------

## Valeur actuelle d'une statistique d'empire pour les seuils des quêtes.
static func stat_now(state: GameState, empire_id: int, stat: String) -> int:
	var e := state.get_empire(empire_id)
	if e == null:
		return 0
	match stat:
		"techs":
			return e.techs.size()
		"systems":
			return Events.own_systems(state, empire_id).size()
		"pop":
			var n := 0
			for pid in state.colonies:
				var c: Colony = state.colonies[pid]
				if c.owner == empire_id and c.is_colony():
					n += c.population
			return n
		"energy", "influence":
			return int(e.resources.get(stat, 0))
		"fragments":
			return Relics.fragments(state, empire_id)
		"relics":
			return Relics.owned(state, empire_id).size() if not state.relics.is_empty() else 0
	return int(e.stats.get(stat, 0))


## [avancement, objectif] d'une branche ([] pour un paiement).
static func progress(state: GameState, q: Dictionary, b: int) -> Array:
	var g: Dictionary = chapter(q)["branches"][b]["goal"]
	var eid := int(q["owner"])
	var sid := int(q["subj"]["system"])
	match String(g["k"]):
		"stat":
			var cur := stat_now(state, eid, String(g["stat"]))
			if not bool(g.get("abs", false)):
				cur -= int(q["base"][b])
			return [clampi(cur, 0, int(g["n"])), int(g["n"])]
		"visit":
			return [1 if _fleet_in(state, eid, sid) else 0, 1]
		"own":
			return [1 if sid >= 0 and state.system_owner(sid) == eid else 0, 1]
		"stab":
			if sid < 0 or not Stability.applies(state, eid) or state.system_owner(sid) != eid:
				return [0, int(g["v"])]
			return [mini(Stability.value(state, sid), int(g["v"])), int(g["v"])]
		"hero":
			return [mini(int(q["cnt"][b]), int(g.get("days", 1))), int(g.get("days", 1))]
		"lair":
			return [int(q["cnt"][b]), 1]
	return []


static func _fleet_in(state: GameState, empire_id: int, sid: int) -> bool:
	if sid < 0:
		return false
	for f: Fleet in state.fleets.values():
		if f.owner == empire_id and f.system_id == sid and f.path.is_empty() and not f.ships.is_empty():
			return true
	return false


## Un héros de l'empire tient le poste voulu aujourd'hui.
static func _hero_holds(state: GameState, q: Dictionary, where: String) -> bool:
	var eid := int(q["owner"])
	var sid := int(q["subj"]["system"])
	for hid in Heroes.ids_of(state, eid):
		var h: Dictionary = state.heroes[hid]
		if not Heroes.active(state, h) or Heroes.is_prisoner(h):
			continue
		var post := String(h["post"])
		match where:
			"council":
				if post == "council":
					return true
			"governor":
				if post == "system":
					return true
			"system":
				if post == "system" and int(h["target"]) == sid:
					return true
				if post == "fleet":
					var f: Fleet = state.fleets.get(int(h["target"]))
					if f != null and f.system_id == sid:
						return true
	return false


## Texte d'un objectif : « Envoyer une flotte à Kesh », « Gagner 2 batailles »…
static func goal_text(state: GameState, q: Dictionary, b: int) -> String:
	var g: Dictionary = chapter(q)["branches"][b]["goal"]
	var eid := int(q["owner"])
	var sname := _sys_name(state, int(q["subj"]["system"]))
	match String(g["k"]):
		"visit":
			return "Avoir une flotte à l'arrêt à %s" % sname
		"own":
			return "Posséder le système %s" % sname
		"stab":
			return "Porter la stabilité de %s à %d" % [sname, int(g["v"])]
		"hero":
			var days := int(g.get("days", 1))
			match String(g.get("where", "")):
				"council":
					return "Garder un héros au conseil pendant %d jours" % days
				"governor":
					return "Garder un héros gouverneur pendant %d jours" % days
			return "Garder un héros à %s pendant %d jours (gouverneur, ou amiral d'une flotte sur place)" % [sname, days]
		"lair":
			return "Démanteler %s" % Pirates.lair_ref(state, int(q["subj"]["lair"]))
		"pay":
			return "Payer %s" % GameData.format_amounts(pay_cost(state, eid, g))
		"stat":
			var n := int(g["n"])
			var lbl := String((data()["goal_labels"] as Dictionary).get(String(g["stat"]), String(g["stat"]) + " %d"))
			var pl := "s" if n > 1 else ""
			var k := lbl.count("%s")
			var args: Array = [n]
			for _i in k:
				args.append(pl)
			return lbl % args
	return "?"


static func pay_cost(state: GameState, empire_id: int, g: Dictionary) -> Dictionary:
	var out := {}
	for r in g.get("cost", {}):
		out[r] = Events.era_scaled(state, empire_id, int(g["cost"][r]))
	return out


## Lignes de la récompense d'une branche.
static func reward_lines(state: GameState, q: Dictionary, b: int) -> Array[String]:
	return Events.fx_lines(state, int(q["owner"]), _item(q), chapter(q)["branches"][b].get("fx", []))


static func _item(q: Dictionary) -> Dictionary:
	var s: Dictionary = q["subj"]
	return {"id": -1, "card": "", "system": int(s["system"]), "planet": -1, "rival": int(s["rival"]), "hero": int(s["hero"])}


static func _sys_name(state: GameState, sid: int) -> String:
	return state.galaxy.systems[sid].system_name if sid >= 0 and sid < state.galaxy.systems.size() else "?"


## Titre et textes avec leurs sujets : {system}, {hero}, {rival}.
static func fill(state: GameState, q: Dictionary, s: String) -> String:
	var subj: Dictionary = q["subj"]
	var out := s.replace("{system}", _sys_name(state, int(subj["system"])))
	var h: Dictionary = state.heroes.get(int(subj["hero"]), {})
	out = out.replace("{hero}", String(h.get("name", "un héros disparu")))
	var r := state.get_empire(int(subj["rival"]))
	out = out.replace("{rival}", r.display_name() if r != null else "un rival")
	return out


static func title(state: GameState, q: Dictionary) -> String:
	return fill(state, q, String(tpl(String(q["tpl"]))["title"]))


static func chapter_text(state: GameState, q: Dictionary) -> String:
	return fill(state, q, String(chapter(q)["text"]))


## Signature de ton de la quête de peuple, selon le registre (« textes teintés par le registre »).
static func voice(state: GameState, empire_id: int) -> String:
	return String((data()["voices"] as Dictionary).get(Events.layer_value(state, empire_id, "registre"), ""))


# --- Chaque jour --------------------------------------------------------------------------------

static func daily(state: GameState, added: Array[Dictionary]) -> void:
	if not enabled(state):
		return
	var r := rules()
	for e in state.empires:
		if e.is_npc() or e.eliminated:
			continue
		var m := meta(state, e.id)
		if int(m["credo"]) == 0 and state.tick >= int(r["credo_day"]):
			m["credo"] = 1
			start(state, e.id, CREDO_PREFIX + Events.layer_value(state, e.id, "credo"), {}, added)
		if state.tick >= int(r["side_first_day"]) and posmod(state.tick + e.id * 37, int(r["side_every"])) == 0:
			_offer_side(state, e.id, added)
	var ids := state.quests.keys()
	ids.sort()
	for id in ids:
		var q: Dictionary = state.quests[id]
		if String(q["status"]) == "active":
			_advance(state, q, added)
	_boons(state)
	if galactic_on(state):
		_galactic_daily(state, added)


static func _offer_side(state: GameState, empire_id: int, added: Array[Dictionary]) -> void:
	var r := rules()
	var n := 0
	for id in of(state, empire_id, true):
		if not is_credo(state.quests[id]):
			n += 1
	if n >= int(r["side_max"]) or _h(state, ["side", empire_id, state.tick]) % 100 >= int(r["side_pct"]):
		return
	var seen: Dictionary = meta(state, empire_id)["seen"]
	var pool: Array[String] = []
	for tid in data()["origins"]["monthly"]:
		var t := tpl(String(tid))
		if seen.has(String(tid)):
			continue
		var subj := _subjects(state, empire_id, String(tid), {})
		if subj.is_empty() or not Events.conditions_ok(state, empire_id, t.get("if", {}), subj):
			continue
		pool.append(String(tid))
	if pool.is_empty():
		return
	start(state, empire_id, pool[_h(state, ["sidepick", empire_id, state.tick]) % pool.size()], {}, added)


static func _advance(state: GameState, q: Dictionary, added: Array[Dictionary]) -> void:
	var eid := int(q["owner"])
	if not _major(state, eid):
		q["status"] = "failed"
		q["end"] = state.tick
		return
	if int(q["wait"]) > 0:
		if state.tick < int(q["wait"]):
			return
		q["wait"] = 0
		_begin_chapter(state, q)
		added.append(state.add_chronicle("%s, « %s » : un nouveau chapitre s'ouvre, « %s »." % [state.get_empire(eid).short_name(), title(state, q),
				String(chapter(q)["title"])], Espionage.private_to(state, [eid])))
	if int(q["until"]) > 0 and state.tick > int(q["until"]):
		_fail(state, q, "le temps est écoulé", added)
		return
	var brs: Array = chapter(q)["branches"]
	for b in brs.size():
		var g: Dictionary = brs[b]["goal"]
		var k := String(g["k"])
		if k == "pay":
			continue
		if k == "hero" and _hero_holds(state, q, String(g.get("where", "system"))):
			q["cnt"][b] = int(q["cnt"][b]) + 1
		if k == "lair" and int(q["cnt"][b]) == 0 and not Pirates.is_lair(state, int(q["subj"]["lair"])):
			_fail(state, q, "un autre a touché la prime", added)
			return
		var p := progress(state, q, b)
		if not p.is_empty() and int(p[0]) >= int(p[1]):
			complete_branch(state, q, b, added)
			return


## La branche b du chapitre en cours est remplie : récompense, marque, chapitre suivant ou fin.
static func complete_branch(state: GameState, q: Dictionary, b: int, added: Array[Dictionary]) -> void:
	var eid := int(q["owner"])
	var e := state.get_empire(eid)
	var ch := chapter(q)
	var br: Dictionary = ch["branches"][b]
	var lines := reward_lines(state, q, b)
	Events.apply_fx(state, eid, _item(q), br.get("fx", []), added)
	(Events.meta(state, eid)["marks"] as Dictionary)["quete:%s:%d:%d" % [String(q["tpl"]), int(q["ch"]), b]] = state.tick
	(q["path"] as Array).append(b)
	Heroes.act(state, eid, "quest_chapter")
	var last := int(q["ch"]) + 1 >= chapters(q).size()
	added.append(state.add_chronicle("%s, « %s » : %s (%s). %s" % [e.short_name(), title(state, q), String(ch["title"]),
			String(br["label"]).to_lower(), (", ".join(lines) + ".") if not lines.is_empty() else ""],
			Espionage.private_to(state, [eid])))
	if not last:
		q["ch"] = int(q["ch"]) + 1
		var gap := int((rules()["chapter_gap"] as Dictionary).get("credo" if is_credo(q) else "side", 0))
		if gap > 0:
			q["wait"] = state.tick + gap
			if int(q["until"]) > 0:
				q["until"] = int(q["until"]) + gap
		else:
			_begin_chapter(state, q)
		return
	q["status"] = "done"
	q["end"] = state.tick
	var m := meta(state, eid)
	m["done"] = int(m["done"]) + 1
	Research.count_stat(state, eid, "quests")
	if is_credo(q):
		m["credo_done"] = 1
		Reputation.exploit(state, eid, "quete_peuple")
		added.append(state.add_chronicle("%s achève la quête de son peuple, « %s ». On en fera des chansons, des statues et sans doute des produits dérivés." % [
				e.display_name(), title(state, q)], Espionage.public_to(state, [eid])))


static func _fail(state: GameState, q: Dictionary, why: String, added: Array[Dictionary]) -> void:
	q["status"] = "failed"
	q["end"] = state.tick
	var eid := int(q["owner"])
	var m := meta(state, eid)
	m["failed"] = int(m["failed"]) + 1
	added.append(state.add_chronicle("%s abandonne la quête « %s » : %s." % [state.get_empire(eid).short_name(), title(state, q), why],
			Espionage.private_to(state, [eid])))


## Démantèlement d'un repaire (Pirates.dismantle) : les quêtes de prime de cet empire avancent.
static func on_lair(state: GameState, sid: int, empire_id: int) -> void:
	for id in state.quests:
		var q: Dictionary = state.quests[id]
		if String(q["status"]) != "active" or int(q["owner"]) != empire_id or int(q["subj"]["lair"]) != sid:
			continue
		var brs: Array = chapter(q)["branches"]
		for b in brs.size():
			if String(brs[b]["goal"]["k"]) == "lair":
				q["cnt"][b] = 1


# --- Paiement d'une branche (ordre) -------------------------------------------------------------

static func check_pay(state: GameState, empire_id: int, quest_id: int, b: int) -> String:
	var q: Dictionary = state.quests.get(quest_id, {})
	if q.is_empty() or int(q["owner"]) != empire_id or String(q["status"]) != "active":
		return "quête inconnue"
	if int(q["wait"]) > 0:
		return "le chapitre suivant n'est pas encore ouvert"
	var brs: Array = chapter(q)["branches"]
	if b < 0 or b >= brs.size() or String(brs[b]["goal"]["k"]) != "pay":
		return "cette branche ne se paie pas"
	var e := state.get_empire(empire_id)
	var cost := pay_cost(state, empire_id, brs[b]["goal"])
	for r in cost:
		if int(e.resources.get(r, 0)) < int(cost[r]):
			return "pas assez de %s" % GameData.resource_label(String(r)).to_lower()
	return ""


static func pay(state: GameState, empire_id: int, quest_id: int, b: int, added: Array[Dictionary]) -> void:
	var q: Dictionary = state.quests[quest_id]
	var e := state.get_empire(empire_id)
	var cost := pay_cost(state, empire_id, chapter(q)["branches"][b]["goal"])
	for r in cost:
		e.resources[r] = int(e.resources.get(r, 0)) - int(cost[r])
	complete_branch(state, q, b, added)


# --- Récompenses propres aux quêtes (appelées par Events.apply_fx) ------------------------------

## Donne une relique de quête ; si les reliques sont absentes de la partie (pas de curiosités), son
## effet devient une faveur permanente ; si un autre empire la tient, des fragments.
static func give_relic(state: GameState, empire_id: int, rid: String) -> String:
	var d := Relics.def(rid)
	if state.relics.is_empty():
		add_boon(state, empire_id, String(d.get("name", rid)), d.get("fx", {}), 0)
		return "%s (son effet s'attache à l'empire)" % String(d.get("name", rid))
	var r: Dictionary = state.relics.get(rid, {})
	if r.is_empty() or (int(r["owner"]) != -1 and int(r["owner"]) != Relics.MARKET):
		Relics.add_fragments(state, empire_id, 30)
		return "30 fragments (la relique est ailleurs)"
	Relics.gain(state, empire_id, rid)
	return String(d.get("name", rid))


## Fait entrer un héros unique (nommé) dans l'empire. Renvoie son identifiant.
static func give_hero(state: GameState, empire_id: int, hero_name: String, cls: String) -> int:
	var cand := Heroes.make_candidate(state, empire_id, cls, ["quete", empire_id, hero_name])
	cand["name"] = hero_name
	var id := Heroes.recruit(state, empire_id, cand)
	var h: Dictionary = state.heroes[id]
	h["lvl"] = 2
	h["unique"] = 1
	return id


## Faveur au format des technologies (fusionnée dans Research.effects), days = 0 : permanente.
static func add_boon(state: GameState, empire_id: int, label: String, fx: Dictionary, days: int) -> void:
	(meta(state, empire_id)["boons"] as Array).append({"label": label, "fx": fx.duplicate(true), "until": state.tick + days if days > 0 else 0})
	Relics.touch(state)


static func _boons(state: GameState) -> void:
	var changed := false
	var keys := state.quest_meta.keys()
	keys.sort()
	for k in keys:
		var boons: Array = state.quest_meta[k]["boons"]
		var i := 0
		while i < boons.size():
			var u := int(boons[i]["until"])
			if u > 0 and u <= state.tick:
				boons.remove_at(i)
				changed = true
				continue
			i += 1
	if changed:
		Relics.touch(state)


## Un héros vaincu au Conclave : plus d'offre de héros (Heroes._maybe_offer).
static func blocks_offers(state: GameState, empire_id: int) -> bool:
	return int(state.quest_meta.get(empire_id, {}).get("no_offer", 0)) > state.tick


## Effets des faveurs et des quêtes galactiques en cours, au format des technologies.
static func effects(state: GameState, empire_id: int) -> Dictionary:
	var out := {}
	if state.quest_meta.has(empire_id):
		for bn: Dictionary in state.quest_meta[empire_id]["boons"]:
			if int(bn["until"]) == 0 or int(bn["until"]) > state.tick:
				Relics._merge_scaled(out, bn["fx"], 100)
	var cur: Dictionary = state.galactic.get("cur", {})
	if not cur.is_empty() and _major(state, empire_id):
		match String(cur["id"]):
			"fleau":
				Relics._merge_scaled(out, gdef("fleau")["fx"], 100)
			"tombeaux":
				if (cur.get("near", []) as Array).has(empire_id):
					Relics._merge_scaled(out, gdef("tombeaux")["fx"], 100)
	return out


## Points de score des quêtes (Victory.score).
static func score(state: GameState, empire_id: int) -> int:
	var m: Dictionary = state.quest_meta.get(empire_id, {})
	if m.is_empty():
		return 0
	var r := rules()
	return (int(m["done"]) - int(m["credo_done"])) * int(r["score_quest"]) + int(m["credo_done"]) * int(r["score_credo"])


# --- Quêtes galactiques -------------------------------------------------------------------------

static func current(state: GameState) -> Dictionary:
	return state.galactic.get("cur", {}) if not state.galactic.is_empty() else {}


static func _majors(state: GameState) -> Array[int]:
	var out: Array[int] = []
	for e in state.empires:
		if not e.is_npc() and not e.eliminated:
			out.append(e.id)
	return out


static func _galactic_daily(state: GameState, added: Array[Dictionary]) -> void:
	var g := state.galactic
	var cur: Dictionary = g["cur"]
	if cur.is_empty():
		if state.tick >= int(g["next"]):
			_galactic_start(state, added)
		return
	match String(cur["id"]):
		"passage":
			_passage_day(state, cur, added)
		"fleau":
			if state.tick >= int(cur["end"]):
				_galactic_end(state, -1, "le fléau s'épuise de lui-même, sans remède ni héros", added)
		"conclave":
			_conclave_day(state, cur, added)
		"tombeaux":
			_tombs_day(state, cur, added)


static func eligible(state: GameState, id: String) -> bool:
	var d := gdef(id)
	match id:
		"tombeaux":
			var n := 0
			for sid in state.digs:
				if int(state.digs[sid]["done"]) >= 0:
					n += 1
			return n >= int(d["min_digs"])
		"conclave":
			return _majors(state).size() >= 2
	return _majors(state).size() >= 1


static func _galactic_start(state: GameState, added: Array[Dictionary]) -> void:
	var g := state.galactic
	var pool: Array[String] = []
	for id in data()["galactic"]["order"]:
		if not (g["seen"] as Array).has(String(id)) and eligible(state, String(id)):
			pool.append(String(id))
	if pool.is_empty():
		g["next"] = state.tick + 360
		return
	var id := pool[_h(state, ["galactic", state.tick]) % pool.size()]
	var d := gdef(id)
	var cur := {"id": id, "start": state.tick}
	match id:
		"passage":
			cur["path"] = _passage_path(state, int(d["steps"]))
			cur["step"] = 0
			cur["next_step"] = state.tick + int(d["step_days"])
			cur["pts"] = {}
			if (cur["path"] as Array).is_empty():
				g["next"] = state.tick + 360
				return
		"fleau":
			cur["target"] = int(d["per_empire"]) * _majors(state).size()
			cur["pool"] = 0
			cur["gifts"] = {}
			cur["end"] = state.tick + int(d["days"])
		"conclave":
			cur["phase"] = "choose"
			cur["camps"] = {}
			cur["phares"] = []
			cur["score"] = [0, 0]
			cur["until"] = state.tick + int(d["choose_days"])
		"tombeaux":
			cur["tombs"] = _place_tombs(state, d)
			cur["pts"] = {}
			cur["end"] = state.tick + int(d["days"])
			cur["near"] = []
			if (cur["tombs"] as Array).is_empty():
				g["next"] = state.tick + 360
				return
	(g["seen"] as Array).append(id)
	g["cur"] = cur
	if id == "tombeaux":
		_tombs_near(state, cur)
	Relics.touch(state)
	added.append(state.add_chronicle("Retournement galactique : %s. %s" % [String(d["title"]), String(d["text"])], null))


static func _galactic_end(state: GameState, winner: int, how: String, added: Array[Dictionary]) -> void:
	var g := state.galactic
	var cur: Dictionary = g["cur"]
	var d := gdef(String(cur["id"]))
	(g["log"] as Array).append({"id": String(cur["id"]), "title": String(d["title"]), "winner": winner, "tick": state.tick})
	var gap: Array = rules()["galactic_gap"]
	g["next"] = state.tick + int(gap[0]) + _h(state, ["gap", state.tick]) % maxi(1, int(gap[1]) - int(gap[0]))
	g["cur"] = {}
	Relics.touch(state)
	var who := state.get_empire(winner)
	var text := "Fin de « %s » : %s." % [String(d["title"]), how]
	if who != null:
		text += " %s en sort grandi." % who.display_name()
		Reputation.exploit(state, winner, "quete_galactique")
		Research.count_stat(state, winner, "quests")
	added.append(state.add_chronicle(text, null))


static func _reward(state: GameState, empire_id: int, fx: Array, added: Array[Dictionary]) -> String:
	var item := {"id": -1, "card": "", "system": -1, "planet": -1, "rival": -1, "hero": -1}
	var lines := Events.fx_lines(state, empire_id, item, fx)
	Events.apply_fx(state, empire_id, item, fx, added)
	return ", ".join(lines)


## Classement d'une table de points {empire: n} : [[n, empire]...], du meilleur au moins bon.
static func ranking(pts: Dictionary) -> Array:
	var out := []
	var keys := pts.keys()
	keys.sort()
	for k in keys:
		out.append([-int(pts[k]), int(k)])
	out.sort()
	var res := []
	for x in out:
		res.append([-int(x[0]), int(x[1])])
	return res


static func _share(state: GameState, cur: Dictionary, pts: Dictionary, min_pts: int, how_won: String, added: Array[Dictionary]) -> void:
	var d := gdef(String(cur["id"]))
	var rk := ranking(pts)
	var winner := -1
	if not rk.is_empty() and int(rk[0][0]) >= min_pts and _major(state, int(rk[0][1])):
		winner = int(rk[0][1])
		var got := _reward(state, winner, d["win"], added)
		added.append(state.add_chronicle("%s remporte « %s » (%d points) : %s." % [state.get_empire(winner).display_name(), String(d["title"]),
				int(rk[0][0]), got], null))
	for x in rk:
		var eid := int(x[1])
		if eid != winner and int(x[0]) >= min_pts and _major(state, eid) and d.has("part"):
			_reward(state, eid, d["part"], added)
	_galactic_end(state, winner, how_won, added)


# Le passage --------------------------------------------------------------------------------------

## Trajet de l'artéfact : il entre par un système du bord de la galaxie et la traverse par le plus
## court chemin vers le système le plus éloigné de son entrée (au plus steps étapes).
static func _passage_path(state: GameState, steps: int) -> Array:
	var systems := state.galaxy.systems
	if systems.is_empty():
		return []
	var center := Vector2.ZERO
	for s in systems:
		center += s.position
	center /= float(systems.size())
	var far: Array = []
	for s in systems:
		far.append([-int(s.position.distance_to(center)), s.id])
	far.sort()
	@warning_ignore("integer_division")
	var top := maxi(1, far.size() / 10)
	var start := int(far[_h(state, ["passage_in"]) % top][1])
	# Parcours en largeur depuis l'entrée : parents, puis le système atteignable le plus éloigné.
	var parent := {start: -1}
	var dist := {start: 0}
	var queue: Array[int] = [start]
	var qi := 0
	var exit := start
	while qi < queue.size():
		var cur := queue[qi]
		qi += 1
		var ns: Array = Array(systems[cur].neighbors)
		ns.sort()
		for n in ns:
			if not parent.has(int(n)):
				parent[int(n)] = cur
				dist[int(n)] = int(dist[cur]) + 1
				queue.append(int(n))
				if int(dist[int(n)]) > int(dist[exit]) or (int(dist[int(n)]) == int(dist[exit]) and int(n) < exit):
					exit = int(n)
	var path := []
	var at := exit
	while at >= 0:
		path.push_front(at)
		at = int(parent[at])
	if path.size() > steps:
		path = path.slice(0, steps)
	return path


static func passage_system(cur: Dictionary) -> int:
	var path: Array = cur.get("path", [])
	return int(path[clampi(int(cur.get("step", 0)), 0, path.size() - 1)]) if not path.is_empty() else -1


static func _passage_day(state: GameState, cur: Dictionary, added: Array[Dictionary]) -> void:
	var sid := passage_system(cur)
	var best := {}
	for f: Fleet in state.fleets.values():
		if f.system_id != sid or not f.path.is_empty() or f.ships.is_empty() or not _major(state, f.owner):
			continue
		var v := 2 if not Heroes.at_post(state, "fleet", f.id).is_empty() else 1
		best[f.owner] = maxi(int(best.get(f.owner, 0)), v)
	var pts: Dictionary = cur["pts"]
	for eid in best:
		pts[eid] = int(pts.get(eid, 0)) + int(best[eid])
	if state.tick >= int(cur["next_step"]):
		cur["step"] = int(cur["step"]) + 1
		cur["next_step"] = state.tick + int(gdef("passage")["step_days"])
		if int(cur["step"]) >= (cur["path"] as Array).size():
			_share(state, cur, pts, int(gdef("passage")["min_points"]), "l'artéfact quitte la galaxie aussi tranquillement qu'il y était entré", added)


# La Rouille grise ---------------------------------------------------------------------------------

static func contribute_cost(state: GameState, empire_id: int) -> Dictionary:
	var out := {}
	var lot: Dictionary = gdef("fleau")["lot"]
	for r in lot:
		out[r] = Events.era_scaled(state, empire_id, int(lot[r]))
	return out


static func check_contribute(state: GameState, empire_id: int) -> String:
	var cur := current(state)
	if cur.is_empty() or String(cur["id"]) != "fleau":
		return "aucun fléau à combattre"
	if not _major(state, empire_id):
		return "empire inconnu"
	var e := state.get_empire(empire_id)
	var cost := contribute_cost(state, empire_id)
	for r in cost:
		if int(e.resources.get(r, 0)) < int(cost[r]):
			return "pas assez de %s" % GameData.resource_label(String(r)).to_lower()
	return ""


static func contribute(state: GameState, empire_id: int, added: Array[Dictionary]) -> void:
	var cur := current(state)
	var e := state.get_empire(empire_id)
	var cost := contribute_cost(state, empire_id)
	for r in cost:
		e.resources[r] = int(e.resources.get(r, 0)) - int(cost[r])
	var gifts: Dictionary = cur["gifts"]
	gifts[empire_id] = int(gifts.get(empire_id, 0)) + 1
	cur["pool"] = int(cur["pool"]) + 1
	if int(cur["pool"]) >= int(cur["target"]):
		_share(state, cur, gifts, 1, "le remède est trouvé, la Rouille se dissout en une fine poussière inoffensive", added)


# Le Conclave des Phares ---------------------------------------------------------------------------

static func camp_of(state: GameState, empire_id: int) -> int:
	var cur := current(state)
	if cur.is_empty() or String(cur["id"]) != "conclave":
		return -1
	return int((cur["camps"] as Dictionary).get(empire_id, -1))


static func check_camp(state: GameState, empire_id: int, camp: int) -> String:
	var cur := current(state)
	if cur.is_empty() or String(cur["id"]) != "conclave" or String(cur["phase"]) != "choose":
		return "le Conclave ne recrute pas"
	if not _major(state, empire_id):
		return "empire inconnu"
	if camp < 0 or camp >= (gdef("conclave")["camps"] as Array).size():
		return "camp inconnu"
	if camp_of(state, empire_id) == camp:
		return "déjà dans ce camp"
	return ""


static func choose_camp(state: GameState, empire_id: int, camp: int) -> void:
	(current(state)["camps"] as Dictionary)[empire_id] = camp


static func camp_label(i: int) -> String:
	var camps: Array = gdef("conclave")["camps"]
	return String(camps[i]["label"]) if i >= 0 and i < camps.size() else "?"


static func _conclave_day(state: GameState, cur: Dictionary, added: Array[Dictionary]) -> void:
	var d := gdef("conclave")
	var camps: Dictionary = cur["camps"]
	if String(cur["phase"]) == "choose":
		if state.tick < int(cur["until"]):
			return
		for eid in _majors(state):
			if not camps.has(eid):
				camps[eid] = _h(state, ["camp", eid]) % 2
		cur["phares"] = _place_phares(state, int(d["phares"]))
		cur["phase"] = "hold"
		cur["until"] = state.tick + int(d["days"])
		var names := PackedStringArray()
		for sid in cur["phares"]:
			names.append(_sys_name(state, int(sid)))
		added.append(state.add_chronicle("Le Conclave des Phares commence : les Phares brûlent à %s. Les camps sont formés ; que les héros prennent position." % ", ".join(names), null))
		return
	var score: Array = cur["score"]
	for sid in cur["phares"]:
		var held := phare_holders(state, cur, int(sid))
		if held.size() == 1:
			score[int(held[0])] = int(score[int(held[0])]) + 1
	var target := int(d["target"])
	if int(score[0]) >= target or int(score[1]) >= target or state.tick >= int(cur["until"]):
		_conclave_end(state, cur, added)


## Camps qui tiennent ce Phare aujourd'hui (héros gouverneur du système ou amiral d'une flotte sur place).
static func phare_holders(state: GameState, cur: Dictionary, sid: int) -> Array:
	var camps: Dictionary = cur["camps"]
	var out := []
	var hids := state.heroes.keys()
	hids.sort()
	for hid in hids:
		var h: Dictionary = state.heroes[hid]
		var owner := int(h["owner"])
		if not camps.has(owner) or not Heroes.active(state, h) or Heroes.is_prisoner(h):
			continue
		var here := false
		if String(h["post"]) == "system" and int(h["target"]) == sid:
			here = true
		elif String(h["post"]) == "fleet":
			var f: Fleet = state.fleets.get(int(h["target"]))
			here = f != null and f.system_id == sid
		if here and not out.has(int(camps[owner])):
			out.append(int(camps[owner]))
	return out


## Phares : des systèmes tenus par des empires différents (hors capitales), sinon des systèmes libres
## au centre de la galaxie.
static func _place_phares(state: GameState, n: int) -> Array:
	var by_owner := {}
	var cands: Array = []
	for sys in state.galaxy.systems:
		var o := state.system_owner(sys.id)
		if o < 0 or not _major(state, o) or FactionTraits.capital_system(state, o) == sys.id:
			continue
		cands.append([_h(state, ["phare", sys.id]) % 100000, sys.id, o])
	cands.sort()
	var out := []
	for c in cands:
		if out.size() >= n:
			break
		if not by_owner.has(int(c[2])):
			by_owner[int(c[2])] = true
			out.append(int(c[1]))
	for c in cands:
		if out.size() >= n:
			break
		if not out.has(int(c[1])):
			out.append(int(c[1]))
	if out.size() < n:
		for sys in state.galaxy.systems:
			if out.size() >= n:
				break
			if state.system_owner(sys.id) < 0 and not sys.planet_ids.is_empty() and not Pirates.is_lair(state, sys.id) and not out.has(sys.id):
				out.append(sys.id)
	return out


static func _conclave_end(state: GameState, cur: Dictionary, added: Array[Dictionary]) -> void:
	var d := gdef("conclave")
	var score: Array = cur["score"]
	var win := -1
	if int(score[0]) != int(score[1]):
		win = 0 if int(score[0]) > int(score[1]) else 1
	var camps: Dictionary = cur["camps"]
	var lead := -1
	var lead_pts := -1
	var ks := camps.keys()
	ks.sort()
	for eid in ks:
		if not _major(state, int(eid)) or win < 0:
			continue
		if int(camps[eid]) == win:
			_reward(state, int(eid), d["win"], added)
			for hid in Heroes.ids_of(state, int(eid)):
				if not Heroes.is_prisoner(state.heroes[hid]):
					Heroes.gain_xp(state, state.heroes[hid], int(d["win_xp"]))
			var e := state.get_empire(int(eid))
			var sc := int(e.stats.get("battles_won", 0))
			if sc > lead_pts:
				lead_pts = sc
				lead = int(eid)
		else:
			meta(state, int(eid))["no_offer"] = state.tick + int(d["lose_days"])
	var how := "égalité parfaite, les Phares s'éteignent d'eux-mêmes, vexés" if win < 0 else "victoire des %s (%d contre %d)" % [camp_label(win), int(score[win]), int(score[1 - win])]
	_galactic_end(state, lead, how, added)


# Le réveil des tombeaux --------------------------------------------------------------------------

static func _place_tombs(state: GameState, d: Dictionary) -> Array:
	var sites: Array = []
	var keys := state.digs.keys()
	keys.sort()
	for sid in keys:
		if int(state.digs[sid]["done"]) >= 0:
			sites.append(int(sid))
	for sid in keys:
		if not sites.has(int(sid)):
			sites.append(int(sid))
	var cands: Array = []
	for sys in state.galaxy.systems:
		if state.system_owner(sys.id) < 0 and not sys.planet_ids.is_empty() and not Pirates.is_lair(state, sys.id) and not sites.has(sys.id):
			cands.append([_h(state, ["tomb", sys.id]) % 100000, sys.id])
	cands.sort()
	for c in cands:
		sites.append(int(c[1]))
	var out := []
	var ships: Array = d["ships"]
	for sid in sites:
		if out.size() >= int(d["tombs"]):
			break
		if state.battles.has(int(sid)):
			continue
		var f := state.spawn_ship(GameState.PIRATE_ID, String(ships[0]), int(sid))
		for i in range(1, ships.size()):
			f.add_ship(String(ships[i]), -1, 1)
		f.troops = 0
		f.fleet_name = "Gardiens du tombeau"
		out.append({"sid": int(sid), "fleet": f.id, "alive": 1, "by": -1})
	return out


static func tomb_at(cur: Dictionary, sid: int) -> Dictionary:
	for t: Dictionary in cur.get("tombs", []):
		if int(t["sid"]) == sid:
			return t
	return {}


## Empires qui tiennent un système à near_jumps ou moins d'un tombeau encore éveillé.
static func _tombs_near(state: GameState, cur: Dictionary) -> void:
	var near := {}
	var nj := int(gdef("tombeaux")["near_jumps"])
	for t: Dictionary in cur["tombs"]:
		if int(t["alive"]) == 0:
			continue
		var jumps := FactionTraits.jumps_from(state.galaxy, int(t["sid"]))
		for sid in jumps:
			if int(jumps[sid]) <= nj:
				var o := state.system_owner(int(sid))
				if o >= 0 and _major(state, o):
					near[o] = true
	var list := near.keys()
	list.sort()
	if str(list) != str(cur["near"]):
		cur["near"] = list
		Relics.touch(state)


static func _tombs_day(state: GameState, cur: Dictionary, added: Array[Dictionary]) -> void:
	var alive := 0
	for t: Dictionary in cur["tombs"]:
		if int(t["alive"]) == 1 and not state.fleets.has(int(t["fleet"])):
			t["alive"] = 0
		alive += int(t["alive"])
	if posmod(state.tick - int(cur["start"]), 30) == 0:
		_tombs_near(state, cur)
	if alive == 0:
		_share(state, cur, cur["pts"], 1, "les tombeaux se taisent, et cette fois pour de bon", added)
		return
	if state.tick >= int(cur["end"]):
		for t: Dictionary in cur["tombs"]:
			if int(t["alive"]) == 1 and state.fleets.has(int(t["fleet"])) and not state.battles.has(int(t["sid"])):
				state.fleets.erase(int(t["fleet"]))
				t["alive"] = 0
		_share(state, cur, cur["pts"], 1, "les gardiens se rendorment, lassés d'attendre", added)


## Fin d'une bataille (CombatSystem) : abattre les gardiens d'un tombeau rapporte un point au vainqueur.
static func on_battle(state: GameState, b: Dictionary, winner: int) -> void:
	var cur := current(state)
	if cur.is_empty() or String(cur["id"]) != "tombeaux" or winner < 0 or not _major(state, winner):
		return
	var t := tomb_at(cur, int(b.get("system", -1)))
	if t.is_empty() or int(t["alive"]) == 0:
		return
	var f: Fleet = state.fleets.get(int(t["fleet"]))
	if f == null or f.ships.is_empty():
		t["alive"] = 0
		t["by"] = winner
		var pts: Dictionary = cur["pts"]
		pts[winner] = int(pts.get(winner, 0)) + 1
		_tombs_near(state, cur)


## Talent synthétique (proposition 15) : parlementer avec un tombeau voisin le rendort.
static func check_parley(state: GameState, empire_id: int, sid: int) -> String:
	var cur := current(state)
	if cur.is_empty() or String(cur["id"]) != "tombeaux":
		return "aucun tombeau éveillé"
	if Events.layer_value(state, empire_id, "archetype") != "synthetique":
		return "seul un peuple synthétique sait leur parler"
	var t := tomb_at(cur, sid)
	if t.is_empty() or int(t["alive"]) == 0:
		return "ce tombeau dort déjà"
	if state.battles.has(sid):
		return "on se bat devant le tombeau"
	var jumps := FactionTraits.jumps_from(state.galaxy, sid)
	var near := false
	for s in Events.own_systems(state, empire_id):
		if int(jumps.get(s, 999)) <= int(gdef("tombeaux")["near_jumps"]):
			near = true
			break
	if not near:
		return "il faut tenir un système à %d sauts ou moins" % int(gdef("tombeaux")["near_jumps"])
	var e := state.get_empire(empire_id)
	var cost: Dictionary = gdef("tombeaux")["parley_cost"]
	for r in cost:
		if int(e.resources.get(r, 0)) < int(cost[r]):
			return "pas assez de %s" % GameData.resource_label(String(r)).to_lower()
	return ""


static func parley(state: GameState, empire_id: int, sid: int, added: Array[Dictionary]) -> void:
	var cur := current(state)
	var d := gdef("tombeaux")
	var e := state.get_empire(empire_id)
	var cost: Dictionary = d["parley_cost"]
	for r in cost:
		e.resources[r] = int(e.resources.get(r, 0)) - int(cost[r])
	var t := tomb_at(cur, sid)
	if state.fleets.has(int(t["fleet"])):
		state.fleets.erase(int(t["fleet"]))
	t["alive"] = 0
	t["by"] = empire_id
	var pts: Dictionary = cur["pts"]
	pts[empire_id] = int(pts.get(empire_id, 0)) + 1
	var got := Events.give_research(state, empire_id, int(d["parley_pct"]))
	_tombs_near(state, cur)
	added.append(state.add_chronicle("%s parlemente avec les gardiens de %s, de machine à machine. Ils se rendorment, après avoir partagé quelques secrets (%s)." % [
			e.display_name(), _sys_name(state, sid), got], Espionage.public_to(state, [empire_id])))


# --- Sauvegarde ---------------------------------------------------------------------------------

static func to_dict(state: GameState) -> Dictionary:
	var qs := []
	var ids := state.quests.keys()
	ids.sort()
	for id in ids:
		qs.append((state.quests[id] as Dictionary).duplicate(true))
	var metas := []
	var mk := state.quest_meta.keys()
	mk.sort()
	for k in mk:
		var m: Dictionary = (state.quest_meta[k] as Dictionary).duplicate(true)
		m["e"] = int(k)
		m["seen"] = Events._pairs(m["seen"])
		metas.append(m)
	var g: Dictionary = state.galactic.duplicate(true)
	if not (g.get("cur", {}) as Dictionary).is_empty():
		var cur: Dictionary = g["cur"]
		for key in ["pts", "gifts", "camps"]:
			if cur.has(key):
				cur[key] = _int_pairs(cur[key])
	return {"mode": state.quest_mode, "next_id": state.next_quest_id, "quests": qs, "meta": metas, "galactic": g}


static func from_dict(state: GameState, d: Dictionary) -> void:
	state.quests.clear()
	state.quest_meta.clear()
	state.quest_mode = String(d.get("mode", "aucunes"))
	state.next_quest_id = int(d.get("next_id", 0))
	for x: Dictionary in d.get("quests", []):
		var q: Dictionary = GameData._to_ints(x)
		q["tpl"] = String(x["tpl"])
		q["status"] = String(x["status"])
		q["subj"] = GameData._to_ints(x["subj"])
		q["base"] = _ints(x.get("base", [0, 0]))
		q["cnt"] = _ints(x.get("cnt", [0, 0]))
		q["path"] = _ints(x.get("path", []))
		q["wait"] = int(x.get("wait", 0))
		state.quests[int(q["id"])] = q
	for x: Dictionary in d.get("meta", []):
		var boons := []
		for bn: Dictionary in x.get("boons", []):
			boons.append({"label": String(bn["label"]), "fx": _fx(bn["fx"]), "until": int(bn["until"])})
		state.quest_meta[int(x["e"])] = {"credo": int(x.get("credo", 0)), "credo_done": int(x.get("credo_done", 0)),
				"done": int(x.get("done", 0)), "failed": int(x.get("failed", 0)), "boons": boons,
				"no_offer": int(x.get("no_offer", 0)), "seen": Events._unpairs(x.get("seen", []))}
	var g: Dictionary = d.get("galactic", {})
	state.galactic = {"next": int(g.get("next", int(rules()["galactic_first_day"]))), "seen": [], "cur": {}, "log": []}
	for s in g.get("seen", []):
		(state.galactic["seen"] as Array).append(String(s))
	for l: Dictionary in g.get("log", []):
		(state.galactic["log"] as Array).append({"id": String(l["id"]), "title": String(l["title"]), "winner": int(l["winner"]), "tick": int(l["tick"])})
	var c: Dictionary = g.get("cur", {})
	if not c.is_empty():
		var cur := {"id": String(c["id"])}
		for key in c:
			var v: Variant = c[key]
			match String(key):
				"id":
					pass
				"phase":
					cur["phase"] = String(v)
				"pts", "gifts", "camps":
					cur[key] = _int_unpairs(v)
				"path", "phares", "score", "near":
					cur[key] = _ints(v)
				"tombs":
					var ts := []
					for t: Dictionary in v:
						ts.append(GameData._to_ints(t))
					cur["tombs"] = ts
				_:
					cur[key] = int(v)
		state.galactic["cur"] = cur


static func _ints(a: Array) -> Array:
	var out := []
	for v in a:
		out.append(int(v))
	return out


static func _int_pairs(d: Dictionary) -> Array:
	var ks := d.keys()
	ks.sort()
	var out := []
	for k in ks:
		out.append([int(k), int(d[k])])
	return out


static func _int_unpairs(a: Array) -> Dictionary:
	var out := {}
	for p in a:
		out[int(p[0])] = int(p[1])
	return out


## Effets lus depuis le JSON : les nombres redeviennent des entiers, sous-dictionnaires compris.
static func _fx(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		var v: Variant = d[k]
		out[String(k)] = _fx(v) if v is Dictionary else int(v)
	return out
