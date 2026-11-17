class_name ArchaeoBridges
extends RefCounted
## Archéologie, lot 3 : ponts avec les autres piliers (prop. 33-39), permis de fouille (prop. 11),
## fouilles concurrentes (prop. 12) et le Collectionneur (prop. 25).
## État : state.archaeo (voir Archaeology) : "permits" {"hôte:invité": {"until", "share"}}, "aster" {eid: fin},
## "plans" {"eid:système": 1}, "fakes" {eid: fin}, "rivals" {système: {eid: {"next", "clues"}}},
## "col" le Collectionneur {"s": système, "until", "next", "stock": [ids d'antiquités]}.

const COLLECTOR := -3  # propriétaire des antiquités en vitrine chez le Collectionneur


static func _h(state: GameState, parts: Array) -> int:
	return absi(hash([state.seed_value, "archeo_b"] + parts))


static func _near(state: GameState, sid: int, targets: Array[int], jumps: int) -> bool:
	if targets.is_empty():
		return false
	var dist := FactionTraits.jumps_from(state.galaxy, sid)
	for t in targets:
		if int(dist.get(t, 999)) <= jumps:
			return true
	return false


static func _ancient_near(state: GameState, kind: String, sid: int, jumps: int) -> int:
	if not Ancients.enabled(state):
		return -1
	var id := Ancients.id_of_kind(state, kind)
	if id < 0:
		return -1
	return id if _near(state, sid, Ancients.systems_of(state, id), jumps) else -1


# --- Début, fin, pillage (prop. 33-36) --------------------------------------------------------------

static func on_start(state: GameState, eid: int, sid: int, _m: String, added: Array[Dictionary]) -> void:
	# Kheb : fouiller près de ses tombeaux rapproche leur réveil, et il n'aime pas ça.
	var kheb := _ancient_near(state, "kheb", sid, Archaeology.r_int("kheb_jumps", 4))
	if kheb >= 0:
		Ancients.add_op(state, kheb, eid, Archaeology.r_int("kheb_op", -5))
		var a: Dictionary = Ancients.get_a(state, kheb)
		if a.has("tomb_next"):
			a["tomb_next"] = maxi(state.tick + 1, int(a["tomb_next"]) - Archaeology.r_int("kheb_hasten_days", 180))
		added.append(state.add_chronicle("Les pelles de %s résonnent jusqu'aux tombeaux de Kheb. Quelque chose, en dessous, se retourne dans son sommeil." % [
				state.get_empire(eid).short_name()], Espionage.private_to(state, [eid], sid)))


static func on_finish(state: GameState, sid: int, eid: int, added: Array[Dictionary]) -> void:
	var d: Dictionary = state.digs[sid]
	var e := state.get_empire(eid)
	var t := String(d.get("at", ""))
	var m := String(d.get("me", ""))
	# Mégastructures (prop. 34) : un site sur une ruine donne ses Plans (-30 % pour la relever).
	if not state.megas.is_empty():
		for mg in Megastructures.in_system(state, sid):
			if Megastructures.is_ruin(mg):
				Archaeology.sub(state, "plans")["%d:%d" % [eid, sid]] = 1
				added.append(state.add_chronicle("Sous la ruine de %s, %s retrouve les Plans des bâtisseurs : la relever coûtera bien moins cher." % [
						Megastructures.name_of(state, mg), e.short_name()], Espionage.private_to(state, [eid], sid)))
				break
	# Contact (prop. 35) : un Observatoire fait avancer la jauge du Signal.
	if t == "observatoire" and Contact.full(state):
		Contact.add_gauge(state, eid, Archaeology.r_int("echo_gauge", 5), added)
	# Foi (prop. 36) : Nécropoles et Sanctuaires sont des lieux saints.
	if t in ["necropole", "sanctuaire"] and FactionTraits.has_fervor(e.faction()):
		var n := 0
		if Archaeology.t_bool(state, eid, "faith_always"):
			n = Archaeology.r_int("faith_prudente", 5)
		elif m == "pillage":
			n = Archaeology.r_int("faith_pillage", -10)
		elif m == "prudente" or Events.layer_value(state, eid, "credo") == "foi":
			n = Archaeology.r_int("faith_prudente", 5)
		if n != 0:
			e.fervor = clampi(e.fervor + n, 0, int(e.faction()["fervor"].get("max", 100)))
			added.append(state.add_chronicle("%s : %s (ferveur %+d)." % [Relics.site_name(state, sid),
					"les fidèles crient à la profanation" if n < 0 else "les fidèles en font un pèlerinage", n], Espionage.private_to(state, [eid])))


## Pillage (prop. 14) : le peuple d'origine s'en souvient, l'héritier aussi, et le Conservatoire d'Ylm.
static func on_pillage(state: GameState, eid: int, sid: int, added: Array[Dictionary]) -> void:
	Research.count_stat(state, eid, "archaeo_pillage")
	if Archaeology.t_bool(state, eid, "pillage_free"):
		return
	var o := Archaeology.site_origin(state, sid)
	var victim := Archaeology.origin_empire(o)
	if victim >= 0 and victim != eid:
		var ve := state.get_empire(victim)
		if ve != null and not ve.eliminated:
			Diplomacy.remember(state, victim, eid, "pillage_sites")
	var dn := Archaeology.disparu_of(o)
	if dn != "":
		var heir := ArchaeoWorld.heir_of(state, dn)
		if heir >= 0 and Minors.enabled(state):
			Minors.add_fav(state, heir, eid, Archaeology.r_int("pillage_fav", -20))
	if o.begins_with("a:") and Ancients.enabled(state):
		var aid := Ancients.id_of_kind(state, o.substr(2))
		if aid >= 0:
			Ancients.add_op(state, aid, eid, Archaeology.r_int("pillage_fav", -20))
	var ylm := _ancient_near(state, "conservatoire", sid, Archaeology.r_int("ylm_jumps", 4))
	if ylm >= 0:
		Ancients.add_op(state, ylm, eid, Archaeology.r_int("ylm_op", -15))
		added.append(state.add_chronicle("Le Conservatoire d'Ylm a vu le pillage de %s. Il note. Il note toujours." % Relics.site_name(state, sid),
				Espionage.private_to(state, [eid])))


static func plans_pct(state: GameState, eid: int, sid: int) -> int:
	if not Archaeology.enabled(state) or sid < 0:
		return 0
	return Archaeology.r_int("plans_pct", -30) if Archaeology.sub(state, "plans").has("%d:%d" % [eid, sid]) else 0


# --- Permis de fouille (prop. 11) ---------------------------------------------------------------------

static func grant_permit(state: GameState, host: int, guest: int, share: int, added: Array[Dictionary]) -> void:
	var h := state.get_empire(host)
	var g := state.get_empire(guest)
	if h == null or g == null:
		return
	Archaeology.sub(state, "permits")[Archaeology.permit_key(host, guest)] = {"until": state.tick + Archaeology.r_int("permit_days", 3600), "share": share}
	added.append(state.add_chronicle("%s accorde à %s un permis de fouille pour dix ans%s." % [h.short_name(), g.short_name(),
			", trouvailles partagées" if share == 1 else ""], Espionage.private_to(state, [host, guest])))


# --- Fouilles concurrentes (prop. 12) -------------------------------------------------------------------

## Un second empire peut-il creuser en même temps sur ce site libre ?
static func can_rival(state: GameState, eid: int, sid: int) -> bool:
	if not Archaeology.full(state) or not bool(Archaeology.rule("concurrence")) or not state.digs.has(sid):
		return false
	var d: Dictionary = state.digs[sid]
	var by := int(d["by"])
	return by >= 0 and by != eid and int(d["next"]) >= 0 and state.system_owner(sid) < 0 \
			and not (Archaeology.sub(state, "rivals").get(str(sid), {}) as Dictionary).has(str(eid))


static func join_rival(state: GameState, eid: int, sid: int) -> bool:
	if not can_rival(state, eid, sid):
		return false
	var r := Archaeology.sub(state, "rivals")
	if not r.has(str(sid)):
		r[str(sid)] = {}
	(r[str(sid)] as Dictionary)[str(eid)] = {"next": state.tick + Archaeology.phase_days(state, eid, sid), "clues": Archaeology.t_int(state, eid, "start_clue")}
	return true


static func rivals_of(state: GameState, sid: int) -> Array[int]:
	var out: Array[int] = []
	for k in (Archaeology.sub(state, "rivals").get(str(sid), {}) as Dictionary):
		out.append(int(k))
	out.sort()
	return out


static func _rivals_daily(state: GameState, added: Array[Dictionary]) -> void:
	var rv := Archaeology.sub(state, "rivals")
	var keys := rv.keys()
	keys.sort()
	for k in keys:
		var sid := int(k)
		var team: Dictionary = rv[k]
		if not Relics.is_open(state, sid) or state.system_owner(sid) >= 0:
			rv.erase(k)
			continue
		var d: Dictionary = state.digs[sid]
		var ids := team.keys()
		ids.sort()
		for rk in ids:
			var eid := int(rk)
			var me: Dictionary = team[rk]
			if not Archaeology.has_camp(state, eid, sid):
				team.erase(rk)
				continue
			if state.tick < int(me["next"]):
				continue
			me["next"] = state.tick + Archaeology.phase_days(state, eid, sid)
			var dg: Dictionary = Relics.data()["digs"]
			var dice := 1 + _h(state, ["rival", sid, eid, state.tick]) % 10
			if dice + int(me["clues"]) + Relics.skill(state, eid, sid) - Relics.difficulty(state, sid) < int(dg["success_at"]):
				me["clues"] = mini(int(dg["clue_max"]), int(me["clues"]) + 1)
				continue
			# Le premier qui finit un chapitre prend le site ; l'autre garde ses indices.
			var old := int(d["by"])
			team.erase(rk)
			if old >= 0 and old != eid:
				team[str(old)] = {"next": int(d["next"]), "clues": int(d["clues"])}
			d["by"] = eid
			d["clues"] = int(me["clues"])
			added.append(state.add_chronicle("Course aux fouilles à %s : %s finit le chapitre le premier et prend le chantier." % [
					Relics.site_name(state, sid), state.get_empire(eid).short_name()], Espionage.private_to(state, [eid, old], sid)))
			Relics._roll(state, sid, added, true)
			break
		if team.is_empty():
			rv.erase(k)


# --- Ordres (via Archaeology.check / apply) ---------------------------------------------------------

static func check(state: GameState, eid: int, act: String, d: Dictionary) -> String:
	var e := state.get_empire(eid)
	match act:
		"permit":
			var host := int(d.get("host", -1))
			var h := state.get_empire(host)
			if h == null or h.eliminated or host == eid or h.is_npc():
				return "hôte inconnu"
			if not e.contacts.has(host):
				return "empire jamais rencontré"
			if Combat.at_war(state, eid, host):
				return "on ne fouille pas chez un ennemi"
			if Archaeology.has_permit(state, host, eid):
				return "vous avez déjà un permis chez lui"
			if _pending(state, host, "archeo_permis"):
				return "il étudie déjà une demande"
			return _cost_problem(e, Archaeology.rule("permit_fee"))
		"restitute":
			var a := Archaeology.antiq(state, int(d.get("id", -1)))
			if a.is_empty() or int(a.get("own", -1)) != eid:
				return "cette antiquité n'est pas à vous"
			if restitute_target(state, eid, int(d.get("id", -1))).is_empty():
				return "personne à qui la rendre : son peuple n'est plus là, ou vous ne le connaissez pas"
			return ""
		"sell_antiq":
			var a2 := Archaeology.antiq(state, int(d.get("id", -1)))
			if a2.is_empty() or int(a2.get("own", -1)) != eid:
				return "cette antiquité n'est pas à vous"
			if Events.layer_value(state, eid, "credo") != "profit" and not Archaeology.t_bool(state, eid, "pillage_free"):
				return "le marché noir des antiquités est réservé au credo Profit"
			return ""
		"aster":
			var lib := Ancients.id_of_kind(state, "bibliotheque") if Ancients.enabled(state) else -1
			if lib < 0 or not Ancients.in_contact(state, lib, eid):
				return "il faut connaître la Bibliothèque d'Aster"
			if Ancients.opinion(state, lib, eid) < Archaeology.r_int("aster_min_op", 10):
				return "la Bibliothèque ne prête qu'à ses amis"
			if int(Archaeology.sub(state, "aster").get(str(eid), 0)) > state.tick:
				return "son archéologue est déjà chez vous"
			return _cost_problem(e, Archaeology.rule("aster_cost"))
		"collector_buy", "collector_sell":
			var col := Archaeology.sub(state, "col")
			if int(col.get("until", 0)) <= state.tick:
				return "le Collectionneur n'est pas en ville"
			if not e.explored.has(int(col.get("s", -1))):
				return "vous ne savez pas où il a posé sa boutique"
			if act == "collector_buy":
				var stock: Array = col.get("stock", [])
				var i := int(d.get("i", -1))
				if i < 0 or i >= stock.size():
					return "pièce inconnue"
				return _cost_problem(e, Archaeology.rule("collector_buy"))
			var a3 := Archaeology.antiq(state, int(d.get("id", -1)))
			if a3.is_empty() or int(a3.get("own", -1)) != eid:
				return "cette antiquité n'est pas à vous"
			return ""
	return "ordre inconnu"


static func _pending(state: GameState, eid: int, card: String) -> bool:
	for it: Dictionary in Events.meta(state, eid).get("inbox", []):
		if String(it.get("card", "")) == card:
			return true
	return false


static func _cost_problem(e: Empire, cost: Variant) -> String:
	if not (cost is Dictionary):
		return ""
	for r in cost:
		if int(e.resources.get(r, 0)) < int(cost[r]):
			return "pas assez de %s" % GameData.resource_label(String(r)).to_lower()
	return ""


static func _pay(e: Empire, cost: Variant) -> void:
	if cost is Dictionary:
		for r in cost:
			e.resources[r] = int(e.resources.get(r, 0)) - int(cost[r])


static func apply(state: GameState, eid: int, act: String, d: Dictionary, added: Array[Dictionary]) -> void:
	var e := state.get_empire(eid)
	match act:
		"permit":
			var host := int(d["host"])
			var share := int(d.get("share", 0))
			_pay(e, Archaeology.rule("permit_fee"))
			var h := state.get_empire(host)
			h.resources["energy"] = int(h.resources.get("energy", 0)) + int((Archaeology.rule("permit_fee") as Dictionary).get("energy", 0))
			if h.is_ai():
				if Diplomacy.opinion(state, host, eid) >= Archaeology.r_int("permit_min_opinion", 0) + (0 if share == 1 else 10):
					grant_permit(state, host, eid, share, added)
				else:
					added.append(state.add_chronicle("%s refuse le permis de fouille de %s (et garde la caution)." % [h.short_name(), e.short_name()],
							Espionage.private_to(state, [host, eid])))
			else:
				Events.push(state, host, "archeo_permis", {"system": FactionTraits.capital_system(state, host), "rival": eid, "n": share}, added)
		"restitute":
			restitute(state, eid, int(d["id"]), added)
		"sell_antiq":
			var id := int(d["id"])
			var n := Events.era_scaled(state, eid, Archaeology.r_int("sell_antiq_energy", 120)) * maxi(1, Archaeology.t_int(state, eid, "sell_x"))
			e.resources["energy"] = int(e.resources.get("energy", 0)) + n
			var name := Archaeology.antiq_name(state, id)
			Archaeology.remove_antiq(state, id)
			added.append(state.add_chronicle("%s passe par le marché noir : %s contre %d énergie, sans facture." % [e.short_name(), name, n], Espionage.private_to(state, [eid])))
		"aster":
			_pay(e, Archaeology.rule("aster_cost"))
			Archaeology.sub(state, "aster")[str(eid)] = state.tick + Archaeology.r_int("aster_days", 3600)
			Archaeology.touch(state)
			added.append(state.add_chronicle("La Bibliothèque d'Aster prête un archéologue à %s : +%d aux jets de fouille pendant dix ans." % [
					e.short_name(), Archaeology.r_int("aster_skill", 2)], Espionage.private_to(state, [eid])))
		"collector_buy":
			var col := Archaeology.sub(state, "col")
			var stock: Array = col["stock"]
			var aid := int(stock[int(d["i"])])
			stock.remove_at(int(d["i"]))
			_pay(e, Archaeology.rule("collector_buy"))
			Archaeology.give_antiq(state, aid, eid)
			added.append(state.add_chronicle("Le Collectionneur cède %s à %s, avec un soupir de déchirement très bien joué." % [Archaeology.antiq_name(state, aid), e.short_name()],
					Espionage.private_to(state, [eid])))
		"collector_sell":
			var id2 := int(d["id"])
			var a := Archaeology.antiq(state, id2)
			var n2 := Events.era_scaled(state, eid, Archaeology.r_int("collector_sell_energy", 180)) * (2 if int(a.get("sr", 1)) == 0 else 1)
			e.resources["energy"] = int(e.resources.get("energy", 0)) + n2
			Archaeology.give_antiq(state, id2, COLLECTOR)
			(Archaeology.sub(state, "col")["stock"] as Array).append(id2)
			added.append(state.add_chronicle("Le Collectionneur achète %s à %s pour %d énergie. Il ne résiste jamais à une pièce rare." % [
					Archaeology.antiq_name(state, id2), e.short_name(), n2], Espionage.private_to(state, [eid])))


# --- Restitutions (prop. 32, 38) ------------------------------------------------------------------------

## À qui rendre cette antiquité : {"kind": "empire" | "minor" | "ancient", "id"} ou {}.
static func restitute_target(state: GameState, eid: int, id: int) -> Dictionary:
	var a := Archaeology.antiq(state, id)
	var o := String(a.get("o", ""))
	var ve := Archaeology.origin_empire(o)
	if ve >= 0 and ve != eid:
		var e := state.get_empire(ve)
		if e != null and not e.eliminated and state.get_empire(eid).contacts.has(ve):
			return {"kind": "empire", "id": ve}
	var dn := Archaeology.disparu_of(o)
	if dn != "" and Minors.enabled(state):
		var heir := ArchaeoWorld.heir_of(state, dn)
		if heir >= 0 and Minors.in_contact(state, heir, eid):
			return {"kind": "minor", "id": heir}
	if o.begins_with("a:") and Ancients.enabled(state):
		var aid := Ancients.id_of_kind(state, o.substr(2))
		if aid >= 0 and Ancients.in_contact(state, aid, eid):
			return {"kind": "ancient", "id": aid}
	return {}


static func restitute(state: GameState, eid: int, id: int, added: Array[Dictionary]) -> void:
	var t := restitute_target(state, eid, id)
	if t.is_empty():
		return
	var name := Archaeology.antiq_name(state, id)
	var e := state.get_empire(eid)
	var to := ""
	var bonus := Archaeology.r_int("restitute_fav", 25)
	if state.amph_on and Amphictyony.is_member(state, eid) and Amphictyony.level_sum(state, "archaeo_restit") > 0:
		@warning_ignore("integer_division")
		bonus += bonus / 2  # Convention du Patrimoine : les restitutions comptent davantage
	match String(t["kind"]):
		"empire":
			Archaeology.give_antiq(state, id, int(t["id"]))
			Diplomacy.remember(state, int(t["id"]), eid, "restitution")
			to = state.get_empire(int(t["id"])).short_name()
		"minor":
			Archaeology.remove_antiq(state, id)
			Minors.add_fav(state, int(t["id"]), eid, bonus)
			to = Minors.name_of(state, int(t["id"]))
		"ancient":
			Archaeology.remove_antiq(state, id)
			Ancients.add_op(state, int(t["id"]), eid, bonus)
			to = String(Ancients.kind_def(Ancients.kind_of(state, int(t["id"]))).get("name", "une puissance ancienne"))
	Archaeology._stat(state, eid, "restit")
	Research.count_stat(state, eid, "archaeo_restit")
	added.append(state.add_chronicle("%s rend %s à %s. On pleure un peu, des deux côtés, mais pas pour les mêmes raisons." % [e.short_name(), name, to],
			Espionage.public_to(state, [eid])))


# --- Espionnage (prop. 37) et guerre (prop. 38) ------------------------------------------------------------

static func spy_check(state: GameState, _a: int, b: int, op_id: String) -> String:
	if not Archaeology.full(state):
		return "l'archéologie n'est pas en jeu dans cette partie"
	match op_id:
		"faussaire":
			if ArchaeoWorld.displayed(state, b).is_empty():
				return "aucune antiquité dans son musée"
	return ""


static func spy_apply(state: GameState, _a: int, b: int, o: Dictionary) -> String:
	match String(o.get("id", "")):
		"faussaire":
			Archaeology.sub(state, "fakes")[str(b)] = state.tick + 3600
			return "une fausse antiquité trône désormais dans son musée. Ses experts se disputent ; ses salles à thème n'en sont plus."
	return ""


## Larcin de relique étendu aux antiquités : renvoie le nom de la pièce volée, "" sinon.
static func steal_antiq(state: GameState, a: int, b: int) -> String:
	if not Archaeology.enabled(state):
		return ""
	var pool := Archaeology.antiqs_of(state, b)
	if pool.is_empty():
		return ""
	var id := pool[_h(state, ["vol", a, state.tick]) % pool.size()]
	Archaeology.give_antiq(state, id, a)
	return Archaeology.antiq_name(state, id)


## But de guerre « Restitution » : trois antiquités, d'abord celles du peuple du vainqueur.
static func take_prize(state: GameState, winner: int, loser: int) -> String:
	var mine: Array[int] = []
	var rest: Array[int] = []
	for id in Archaeology.antiqs_of(state, loser):
		if Archaeology.origin_empire(String(Archaeology.antiq(state, id).get("o", ""))) == winner:
			mine.append(id)
		else:
			rest.append(id)
	var pick := mine + rest
	var n := mini(3, pick.size())
	for i in n:
		Archaeology.give_antiq(state, pick[i], winner)
	return "%d antiquité%s" % [n, "s" if n > 1 else ""] if n > 0 else ""


# --- Le Collectionneur (prop. 25) -------------------------------------------------------------------------

static func _collector_daily(state: GameState, added: Array[Dictionary]) -> void:
	var col := Archaeology.sub(state, "col")
	if int(col.get("until", 0)) > 0 and int(col["until"]) <= state.tick:
		for id in col.get("stock", []):
			Archaeology.remove_antiq(state, int(id))
		col.clear()
		col["next"] = state.tick + Archaeology.r_int("collector_every_days", 1800)
		added.append(state.add_chronicle("Le Collectionneur replie sa boutique et repart vers d'autres étoiles, ses caisses pleines."))
		return
	if not col.has("next"):
		col["next"] = state.tick + Archaeology.r_int("collector_every_days", 1800)
	if int(col.get("until", 0)) > state.tick or state.tick < int(col["next"]):
		return
	var cands: Array = []
	for sys in state.galaxy.systems:
		if not sys.planet_ids.is_empty() and state.system_owner(sys.id) < 0 and not Pirates.is_lair(state, sys.id):
			cands.append(sys.id)
	if cands.is_empty():
		return
	var sid := int(cands[_h(state, ["col", state.tick]) % cands.size()])
	var stock: Array = []
	var disp := Archaeology.in_game_disparus(state)
	for i in Archaeology.r_int("collector_stock", 4):
		var o := "g"
		if not disp.is_empty() and _h(state, ["colo", state.tick, i]) % 3 > 0:
			o = "d:" + disp[_h(state, ["cold", state.tick, i]) % disp.size()]
		var id := Archaeology.add_antiq(state, COLLECTOR, -1, o)
		if id >= 0:
			Archaeology.antiq(state, id)["sr"] = _h(state, ["colsr", id]) % 3
			stock.append(id)
	col["s"] = sid
	col["until"] = state.tick + Archaeology.r_int("collector_stay_days", 360)
	col["stock"] = stock
	added.append(state.add_chronicle("Le Collectionneur pose sa boutique à %s : antiquités rares, prix déraisonnables, et un sourire qui ne dit rien de bon." % state.galaxy.systems[sid].system_name))


# --- Chaque jour ---------------------------------------------------------------------------------------

static func daily(state: GameState, added: Array[Dictionary]) -> void:
	_rivals_daily(state, added)
	if posmod(state.tick, 30) != 0:
		return
	var pm := Archaeology.sub(state, "permits")
	var keys := pm.keys()
	keys.sort()
	for k in keys:
		if int((pm[k] as Dictionary).get("until", 0)) <= state.tick:
			pm.erase(k)
	if Archaeology.cfg("rules").has("collector_every_days"):
		_collector_daily(state, added)
