class_name AncientsBridges
extends RefCounted
## Puissances anciennes : ponts avec les autres piliers (lot 3 de l'étude du 2026-11-15).
##
## - Guerre sainte (19) : coloniser, bombarder ou prendre un Monde saint réveille aussitôt les
##   Hiérophantes, à tout moment de la partie.
## - Religion (21) : pèlerinage des foies Précurseurs vers les Mondes saints, consécration (+30).
## - Reliques (22) : une relique-clé par ancienne, cachée dans une fouille près de sa poche.
## - Héritage (23) : une ancienne abattue laisse 2 à 3 coffres (fouilles) ; le dernier attend une crise.
## - Héros (25) : trait « Ami des anciens » gagné avec un poste honorifique.
## - Talents par couche (26), en données (data/ancients.json, « talents »).
## - Origine « Rejeton » (27) : une petite ancienne protectrice, même sans l'option.


static func cfg() -> Dictionary:
	return Ancients.data().get("bridges", {})


# --- Talents par couche (prop. 26) ------------------------------------------------------------------

static func talents_of(state: GameState, eid: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var e := state.get_empire(eid)
	if e == null or e.is_npc():
		return out
	for t: Dictionary in Ancients.data().get("talents", []):
		if Events.layer_value(state, eid, String(t["layer"])) == String(t["value"]):
			out.append(t)
	return out


## Opinion de départ ajoutée : talents, relique-clé tenue, héros Ami des anciens, Rejeton, consécrations.
static func talent_op(state: GameState, id: int, eid: int) -> int:
	var kind := Ancients.kind_of(state, id)
	var v := 0
	for t in talents_of(state, eid):
		v += int((t.get("op", {}) as Dictionary).get(kind, 0))
	if holds_key(state, id, eid):
		v += int(cfg()["relic_op"])
	if has_friend(state, eid):
		v += int(cfg()["friend_op"])
	var a := Ancients.get_a(state, id)
	if int(a.get("scion", -1)) == eid:
		v += int(cfg()["scion_op"])
	# La rivale de votre protectrice vous déteste d'office.
	var rival := Ancients.id_of_kind(state, String(Ancients.kind_def(kind).get("rival", "")))
	if rival >= 0 and int(Ancients.get_a(state, rival).get("scion", -1)) == eid:
		v += int(cfg()["rival_op"])
	if kind == "hierophantes":
		var sf := Faiths.state_faith(state, eid) if state.faith_on else ""
		for pid in state.ancients.get("consecrated", {}):
			if sf != "" and String(state.ancients["consecrated"][pid]) == sf:
				v += int(cfg()["consecrate_op"])
	return v


## Les nuées n'entendent pas les anciennes : pas de requête.
static func hears(state: GameState, _id: int, eid: int) -> bool:
	for t in talents_of(state, eid):
		if bool(t.get("deaf", false)):
			return false
	return true


static func mission_mult(state: GameState, eid: int) -> int:
	var m := 100
	for t in talents_of(state, eid):
		m = maxi(m, int(t.get("mission_mult", 100)))
	return m


static func contrib_pct(state: GameState, eid: int) -> int:
	var p := 0
	for t in talents_of(state, eid):
		p += int(t.get("contrib_pct", 0))
	return p


## Les Bergers parient toujours en faveur des synthétiques.
static func wins_bets(state: GameState, eid: int, card_id: String) -> bool:
	if not card_id.begins_with("anc_bergers"):
		return false
	for t in talents_of(state, eid):
		if bool(t.get("bets", false)):
			return true
	return false


# --- Héros (prop. 25) -------------------------------------------------------------------------------

static func has_friend(state: GameState, eid: int) -> bool:
	for hid in state.heroes:
		var h: Dictionary = state.heroes[hid]
		if int(h.get("owner", -1)) == eid and (h.get("traits", []) as Array).has("ami_anciens"):
			return true
	return false


## Un poste honorifique : le héros le plus expérimenté de l'empire devient Ami des anciens.
static func on_post(state: GameState, _id: int, eid: int, _post: String) -> void:
	if state.heroes.is_empty() or has_friend(state, eid):
		return
	var best: Dictionary = {}
	var keys := state.heroes.keys()
	keys.sort()
	for hid in keys:
		var h: Dictionary = state.heroes[hid]
		if int(h.get("owner", -1)) != eid or String(h.get("status", "")) == "dead":
			continue
		if best.is_empty() or int(h.get("xp", 0)) > int(best.get("xp", 0)):
			best = h
	if best.is_empty():
		return
	var added: Array[Dictionary] = []
	CrisisAllies._give(state, best, "ami_anciens", added)


# --- Guerre sainte (prop. 19) -----------------------------------------------------------------------

static func holy_world_in(state: GameState, sid: int) -> int:
	if not Ancients.enabled(state):
		return -1
	for pid in state.galaxy.systems[sid].planet_ids:
		if Ancients.holy_owner(state, pid) >= 0:
			return pid
	return -1


## Colonisation d'une planète (SimCommands « colonize ») : un Monde saint, c'est la guerre sainte.
static func on_colonize(state: GameState, eid: int, pid: int) -> void:
	if not Ancients.enabled(state) or Ancients.holy_owner(state, pid) < 0:
		return
	var added: Array[Dictionary] = []
	holy_war(state, Ancients.holy_owner(state, pid), eid, "colonise un Monde saint", added)


## Bombardement d'un système (GroundSiege) qui abrite un Monde saint.
static func on_bombard(state: GameState, sid: int, by: int) -> void:
	var pid := holy_world_in(state, sid)
	if pid < 0 or GameState.is_npc(by):
		return
	var added: Array[Dictionary] = []
	holy_war(state, Ancients.holy_owner(state, pid), by, "bombarde un Monde saint", added)


## Prise d'un système qui abrite un Monde saint colonisé.
static func on_capture(state: GameState, sid: int, taker: int, added: Array[Dictionary]) -> void:
	var pid := holy_world_in(state, sid)
	if pid < 0 or GameState.is_npc(taker) or not state.colonies.has(pid):
		return
	holy_war(state, Ancients.holy_owner(state, pid), taker, "prend un Monde saint", added)


static func holy_war(state: GameState, id: int, eid: int, why: String, added: Array[Dictionary]) -> void:
	if id < 0 or Ancients.get_a(state, id).is_empty() or Ancients.at_war_with(state, id, eid):
		return
	var e := state.get_empire(eid)
	if e == null or e.eliminated:
		return
	var a := Ancients.get_a(state, id)
	Ancients.meet(state, id, eid, added)
	added.append(state.add_chronicle("Guerre sainte : %s %s, et %s se lève d'un bond." % [e.display_name(), why, Ancients.name_of(state, id)]))
	if AncientsWake.wake_on(state) and Ancients.asleep(state, id):
		a["why"] = "%s %s." % [e.display_name(), why]
		if AncientsWake.parvenue(state) < 0:
			AncientsWake.notice(state, id, added)
		AncientsWake.awaken(state, id, added)
	Ancients.declare_war(state, id, eid, "sainte" if not Ancients.asleep(state, id) else "punition", added)
	Events.push(state, eid, "anc_guerre_sainte", {"anc": id, "system": int(a["home"])}, added)


# --- Religion (prop. 21) ----------------------------------------------------------------------------

## Pèlerinage : chaque mois, une foi d'État Précurseurs gagne du zèle par empire qui a une flotte sur un Monde saint.
static func monthly(state: GameState, added: Array[Dictionary]) -> void:
	if not Ancients.enabled(state):
		return
	if state.faith_on:
		var done := {}
		for pid in state.ancients.get("holy", {}):
			var sid := state.galaxy.get_planet(int(pid)).system_id
			for f in Fleets.fleets_at(state, sid):
				if GameState.is_npc(f.owner) or done.has(f.owner):
					continue
				var sf := Faiths.state_faith(state, f.owner)
				if FaithWars.nature(state, sf) == "precurseurs":
					done[f.owner] = true
					FaithWars.add_zeal(state, sf, int(cfg()["pilgrim_zeal"]))
	_scions(state, added)


static func check_consecrate(state: GameState, eid: int, id: int, pid: int) -> String:
	if not state.faith_on:
		return "pas de foi dans cette partie"
	if Ancients.holy_owner(state, pid) != id:
		return "ce n'est pas un de ses Mondes saints"
	var sf := Faiths.state_faith(state, eid)
	if sf == Faiths.LAICITE or sf == "":
		return "il faut une foi d'État"
	if String(state.ancients.get("consecrated", {}).get(pid, "")) == sf:
		return "déjà consacré par votre foi"
	if state.colonies.has(pid):
		return "on ne consacre pas un monde colonisé"
	var sid := state.galaxy.get_planet(pid).system_id
	if Fleets.fleets_at(state, sid, eid).is_empty():
		return "il faut un vaisseau sur place"
	if not Economy.can_afford(state.get_empire(eid), cfg()["consecrate_cost"]):
		return "il faut %s" % GameData.format_amounts(cfg()["consecrate_cost"])
	return ""


static func consecrate(state: GameState, eid: int, id: int, pid: int, added: Array[Dictionary]) -> void:
	Economy.pay(state.get_empire(eid), cfg()["consecrate_cost"])
	if not state.ancients.has("consecrated"):
		state.ancients["consecrated"] = {}
	var sf := Faiths.state_faith(state, eid)
	state.ancients["consecrated"][pid] = sf
	# Toute la foi en profite : opinion de départ et opinion du moment des fidèles en contact.
	var a := Ancients.get_a(state, id)
	for e in state.empires:
		if Faiths.state_faith(state, e.id) == sf and Ancients.in_contact(state, id, e.id):
			(a["base"] as Dictionary)[e.id] = int((a["base"] as Dictionary).get(e.id, 0)) + int(cfg()["consecrate_op"])
			Ancients.add_op(state, id, e.id, int(cfg()["consecrate_op"]))
	added.append(state.add_chronicle("%s consacre %s sans y poser le pied. Les Hiérophantes apprécient le geste, et surtout la retenue." % [
			state.get_empire(eid).display_name(), state.galaxy.get_planet(pid).display_name(state.galaxy)]))


# --- Reliques-clés (prop. 22) -----------------------------------------------------------------------

static func key_relic(kind: String) -> String:
	for rid in Relics.ids():
		if String(Relics.def(rid).get("ancient", "")) == kind:
			return rid
	return ""


static func holds_key(state: GameState, id: int, eid: int) -> bool:
	if state.relics.is_empty():
		return false
	var rid := key_relic(Ancients.kind_of(state, id))
	return rid != "" and state.relics.has(rid) and int(state.relics[rid]["owner"]) == eid


## Cache la relique-clé de chaque ancienne dans une fouille, à 2 à 4 sauts de sa poche.
static func place_relics(state: GameState) -> void:
	if state.relics.is_empty() or not Ancients.enabled(state):
		return
	var span: Array = cfg()["relic_jumps"]
	for id in Ancients.ids(state):
		var rid := key_relic(Ancients.kind_of(state, id))
		if rid == "" or not state.relics.has(rid) or int(state.relics[rid]["owner"]) != -1:
			continue
		var jumps := FactionTraits.jumps_from(state.galaxy, int(Ancients.get_a(state, id)["home"]))
		var cands: Array = []
		for s in state.galaxy.systems:
			var j := int(jumps.get(s.id, 999))
			if j < int(span[0]) or j > int(span[1]) or s.planet_ids.is_empty() or state.system_owner(s.id) >= 0 or state.digs.has(s.id) or Pirates.is_lair(state, s.id):
				continue
			cands.append([j * 1000 + Ancients._h(state, ["cle", id, s.id]) % 1000, s.id])
		cands.sort()
		if not cands.is_empty():
			Relics.create_site(state, int(cands[0][1]), rid)


## Refuser un ultimatum ou la soumission sans guerre, la relique-clé en main.
static func shield(state: GameState, id: int, eid: int) -> bool:
	return holds_key(state, id, eid)


# --- Héritage (prop. 23) ----------------------------------------------------------------------------

## Une ancienne qui n'a plus aucun monde : elle tombe, et laisse ses coffres.
static func on_destroyed(state: GameState, id: int, added: Array[Dictionary]) -> void:
	var a := Ancients.get_a(state, id)
	if String(a.get("stage", "")) == "fallen":
		return
	a["stage"] = "fallen"
	(a.get("dom", {}) as Dictionary).clear()
	(a["war"] as Dictionary).clear()
	for e in state.empires:
		e.path_cache.clear()
	added.append(state.add_chronicle("%s n'est plus. Ses mondes sont à d'autres ; ses coffres, eux, sont encore fermés." % Ancients.name_of(state, id)))
	if state.relics.is_empty():
		return
	var span: Array = cfg()["vaults"]
	var want := int(span[0]) + Ancients._h(state, ["coffres", id]) % (int(span[1]) - int(span[0]) + 1)
	var jumps := FactionTraits.jumps_from(state.galaxy, int(a["home"]))
	var cands: Array = []
	for s in state.galaxy.systems:
		var j := int(jumps.get(s.id, 999))
		if j > 3 or s.planet_ids.is_empty() or state.digs.has(s.id):
			continue
		cands.append([j * 1000 + Ancients._h(state, ["coffre", id, s.id]) % 1000, s.id])
	cands.sort()
	var made: Array[int] = []
	for c in cands:
		if made.size() >= want:
			break
		if Relics.create_site(state, int(c[1])):
			state.digs[int(c[1])]["vault"] = id
			made.append(int(c[1]))
	if not made.is_empty():
		state.digs[made[-1]]["vault_crisis"] = true
		added.append(state.add_chronicle("Les coffres %s : %d fouilles autour de son ancienne capitale. Le dernier, dit-on, ne s'ouvre que quand le ciel brûle." % [
				Crisis.de_name(Ancients.name_of(state, id)), made.size()]))


## Coffre ouvert : une technologie ancienne en plus de la relique.
static func on_dig_finished(state: GameState, sid: int, eid: int, added: Array[Dictionary]) -> void:
	var d: Dictionary = state.digs.get(sid, {})
	if not d.has("vault") or GameState.is_npc(eid):
		return
	var tid := Ancients.gift_tech(state, eid)
	if tid != "":
		added.append(state.add_chronicle("Dans le coffre, sous la relique, des plans : %s y gagne %s." % [state.get_empire(eid).display_name(),
				String(Research.tech(tid).get("label", tid))], Espionage.private_to(state, [eid], sid)))


# --- Rejeton (prop. 27) -----------------------------------------------------------------------------

## Les empires d'origine « Rejeton » reçoivent une petite ancienne protectrice (après Ancients.setup).
static func setup_scions(state: GameState) -> void:
	for e in state.empires:
		if bool(e.faction().get("ancient_scion", false)):
			make_scion(state, e.id)


static func make_scion(state: GameState, eid: int) -> int:
	if state.ancients.is_empty() or not state.ancients.has("list"):
		state.ancients = {"mode": "aucune", "wake": true, "list": {}, "holy": {}, "worlds": {}, "boons": {}}
	var used := {}
	for id in Ancients.ids(state):
		used[Ancients.kind_of(state, id)] = true
	var free: Array[String] = []
	for k in Ancients.kind_ids():
		if not used.has(k) and not bool(Ancients.kind_def(k).get("no_opinion", false)):
			free.append(k)
	if free.is_empty() or Ancients.ids(state).size() >= GameState.ANCIENT_MAX:
		return -1
	var k := free[Ancients._h(state, ["rejeton", eid]) % free.size()]
	var span: Array = cfg()["scion_jumps"]
	var jumps := FactionTraits.jumps_from(state.galaxy, FactionTraits.capital_system(state, eid))
	var cands: Array = []
	for s in state.galaxy.systems:
		var j := int(jumps.get(s.id, 999))
		if j < int(span[0]) or j > int(span[1]) or s.planet_ids.is_empty() or not Ancients._free(state, s.id):
			continue
		cands.append([-s.planet_ids.size() * 1000 + Ancients._h(state, ["nid", eid, s.id]) % 1000, s.id])
	if cands.is_empty():
		return -1
	cands.sort()
	var pocket: Array[int] = [int(cands[0][1])]
	var id := Ancients.create(state, k, pocket)
	if id < 0:
		return -1
	var a := Ancients.get_a(state, id)
	a["scion"] = eid
	a["small"] = true
	# Petite ancienne : sa garde seulement, au tiers de la force.
	var fl := Ancients.fleets_of(state, id)
	for i in range(fl.size() - 1, 0, -1):
		state.fleets.erase(fl[i].id)
		(a["fleets"] as Array).erase(fl[i].id)
	@warning_ignore("integer_division")
	a["power"] = int(a["power"]) * int(cfg()["scion_power_pct"]) / 100
	a["scion_gift"] = int(cfg()["scion_gift_days"])
	var added: Array[Dictionary] = []
	Ancients.meet(state, id, eid, added)
	for e in state.empires:
		e.path_cache.clear()
	return id


## Chaque mois : tribut léger du rejeton, cadeau tous les deux ans.
static func _scions(state: GameState, added: Array[Dictionary]) -> void:
	for id in Ancients.ids(state):
		var a := Ancients.get_a(state, id)
		var eid := int(a.get("scion", -1))
		if eid < 0:
			continue
		var e := state.get_empire(eid)
		if e == null or e.eliminated or String(a.get("stage", "")) == "fallen":
			continue
		@warning_ignore("integer_division")
		e.resources["energy"] = maxi(0, int(e.resources.get("energy", 0)) - int(e.resources.get("energy", 0)) * int(cfg()["scion_tribute_pct"]) / 100)
		if state.tick >= int(a.get("scion_gift", 0)):
			a["scion_gift"] = state.tick + int(cfg()["scion_gift_days"])
			var table: Array = Ancients.data()["gift_table"]
			Events.push(state, eid, "anc_cadeau", {"anc": id, "system": int(a["home"]), "n": Ancients._h(state, ["don-rejeton", id, state.tick]) % mini(3, table.size())}, added)


# --- Commandes et interface -------------------------------------------------------------------------

static func check_act(state: GameState, eid: int, act: String, x: int, _s: String, n: int) -> String:
	if act == "consecrate":
		return check_consecrate(state, eid, x, n)
	return "action inconnue"


static func act(state: GameState, eid: int, act_id: String, x: int, _s: String, n: int, added: Array[Dictionary]) -> void:
	if act_id == "consecrate":
		consecrate(state, eid, x, n, added)


## Lignes des ponts pour la fiche de l'écran Diplomatie.
static func ui_lines(state: GameState, player: int, id: int) -> PackedStringArray:
	var out := PackedStringArray()
	var tl := PackedStringArray()
	for t in talents_of(state, player):
		var kinds: Dictionary = t.get("op", {})
		if kinds.is_empty() or kinds.has(Ancients.kind_of(state, id)):
			tl.append("%s (%s)" % [String(t["label"]), String(t["text"])])
	if not tl.is_empty():
		out.append("Talents de votre peuple : " + " ; ".join(tl))
	var holy := PackedStringArray()
	for pid in state.ancients.get("holy", {}):
		if int(state.ancients["holy"][pid]) == id:
			holy.append(state.galaxy.get_planet(int(pid)).display_name(state.galaxy))
	if not holy.is_empty():
		out.append("Mondes saints : %s. Les coloniser, les bombarder ou les prendre, c'est la guerre sainte ; les consacrer sans y poser le pied lui plaît." % ", ".join(holy))
	var rid := key_relic(Ancients.kind_of(state, id))
	if holds_key(state, id, player):
		out.append("Vous tenez sa relique-clé, %s : elle vous pardonne une colère majeure, et vous pouvez refuser ses ultimatums sans guerre." % String(Relics.def(rid).get("name", rid)))
	if int(Ancients.get_a(state, id).get("scion", -1)) == player:
		out.append("Votre protectrice : cadeau tous les deux ans, tribut de %d %% de votre énergie chaque mois." % int(cfg()["scion_tribute_pct"]))
	return out


static func ui_buttons(state: GameState, player: int, id: int, emit: Callable) -> Array[Control]:
	var out: Array[Control] = []
	for pid in state.ancients.get("holy", {}):
		if int(state.ancients["holy"][pid]) != id:
			continue
		var sid := state.galaxy.get_planet(int(pid)).system_id
		if Fleets.fleets_at(state, sid, player).is_empty():
			continue
		var p2 := int(pid)
		out.append(VassalUi._btn("Consacrer %s" % state.galaxy.get_planet(p2).display_name(state.galaxy), check_consecrate(state, player, id, p2),
				"Consacrer un Monde saint sans le coloniser : +30 d'opinion des Hiérophantes pour toute votre foi (50 influence, un vaisseau sur place).",
				func() -> void: emit.call(SimCommands.anc_act(player, "consecrate", id, "", p2))))
	return out
