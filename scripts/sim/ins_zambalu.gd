class_name InsZambalu
extends RefCounted
## Cirque Stellaire Zambalù (props 17 à 22 ; voir Insolites, data/insolites.json "zambalu").
## Une seule cité mobile, la Cité-chapiteau, et des Troupes sans armes. Une Troupe à l'arrêt chez un
## empire en paix joue 60 jours : billetterie, stabilité, Rayonnement massif. En guerre, une Troupe
## escortée qui tient 90 jours un système ennemi fait d'une colonie un Fan-club (implant qui verse une
## dîme) : le Cirque ne garde aucune planète. Sa population vient des Recrues (culture Influente chez un
## empire), jamais des naissances. Tous les dix ans, le Grand Numéro : trêve entre les délégués.
##
## État (Insolites.emp) : "pop", "sp", "shows": {"fid": {"s", "b", "left"}}, "tours": {"fid": {"s", "p",
## "left"}}, "rec": {"eid": palier déjà payé en recrues}, "num": {"next", "call", "del": [empires]}.

const TROUPE := "troupe_cirque"


static func _c(key: String, def := 0) -> int:
	return Insolites.c_int("zambalu", key, def)


static func found(state: GameState, e: Empire, _sid: int, ed: Dictionary) -> void:
	ed["pop"] = _c("start_pop", 10)
	ed["sp"] = {e.faction_id: int(ed["pop"])}
	ed["shows"] = {}
	ed["tours"] = {}
	ed["rec"] = {}
	ed["num"] = {"next": state.tick + _c("numero_first_days", 1800), "call": 0, "del": []}


static func income(state: GameState, eid: int) -> Dictionary:
	var out := {}
	@warning_ignore("integer_division")
	var units := int(Insolites.emp(state, eid).get("pop", 0)) / maxi(1, _c("pop_per_yield", 2))
	Insolites.add_to(out, Insolites.cfg("zambalu").get("pop_yields", {}), units)
	return out


static func is_troupe(f: Fleet) -> bool:
	return f.count(TROUPE) > 0


## L'hôte interdit-il les spectacles ? (loi Exception culturelle, prop. 18)
static func banned(state: GameState, host: int) -> bool:
	return state.politics_on and Laws.is_enacted(state, host, "exception_culturelle")


## Empire chez qui une Troupe à l'arrêt dans ce système jouerait : le propriétaire du système, s'il est
## un vrai empire rencontré (-1 sinon).
static func host_of(state: GameState, eid: int, sid: int) -> int:
	var b := state.system_owner(sid)
	if b < 0 or b == eid or b >= state.empires.size():
		return -1
	var e := state.get_empire(eid)
	if not e.contacts.has(b) or state.get_empire(b).eliminated:
		return -1
	return b


static func daily(state: GameState, eid: int, ed: Dictionary, month: bool, added: Array[Dictionary]) -> void:
	var shows: Dictionary = ed.get("shows", {})
	var tours: Dictionary = ed.get("tours", {})
	var seen := {}
	for f in Fleets.empire_fleets(state, eid):
		if not is_troupe(f):
			continue
		var key := str(f.id)
		seen[key] = true
		if f.is_moving():
			shows.erase(key)
			tours.erase(key)
			continue
		var sid := f.system_id
		var b := host_of(state, eid, sid)
		if b < 0:
			shows.erase(key)
			tours.erase(key)
			continue
		if Combat.at_war(state, eid, b):
			shows.erase(key)
			_tour_day(state, eid, ed, f, b, added)
		else:
			tours.erase(key)
			_show_day(state, eid, ed, f, b, added)
	for k in shows.keys():
		if not seen.has(k):
			shows.erase(k)
	for k in tours.keys():
		if not seen.has(k):
			tours.erase(k)
	if month:
		_recruits(state, eid, ed, added)


## Représentation (prop. 18) : 60 jours à l'arrêt chez un hôte en paix, une scène à la fois par système.
static func _show_day(state: GameState, eid: int, ed: Dictionary, f: Fleet, b: int, added: Array[Dictionary]) -> void:
	var shows: Dictionary = ed["shows"]
	var key := str(f.id)
	var sid := f.system_id
	if banned(state, b) or int((state.insolites.get("stage", {}) as Dictionary).get(str(sid), 0)) > state.tick:
		shows.erase(key)
		return
	if not shows.has(key) or int(shows[key]["s"]) != sid:
		for k in shows:
			if k != key and int(shows[k]["s"]) == sid:
				return  # une autre Troupe joue déjà ici
		shows[key] = {"s": sid, "b": b, "left": _c("show_days", 60)}
	var sh: Dictionary = shows[key]
	sh["left"] = int(sh["left"]) - 1
	if int(sh["left"]) > 0:
		return
	shows.erase(key)
	var e := state.get_empire(eid)
	var host := state.get_empire(b)
	var ticket := mini(Insolites.tuned(state, eid, "zambalu", "show_ticket", _c("show_ticket", 20)), maxi(0, int(host.resources.get("energy", 0))))
	host.resources["energy"] = int(host.resources.get("energy", 0)) - ticket
	e.resources["energy"] = int(e.resources.get("energy", 0)) + ticket
	Insolites.sub(state, "stage")[str(sid)] = state.tick + _c("show_stability_days", 180)
	_spectacle_mass(state, e, host, sid)
	if not state.culture.is_empty():
		var cum := Culture._m(state, "cum")
		var ck := Culture._k(eid, b)
		cum[ck] = int(cum.get(ck, 0)) + Insolites.tuned(state, eid, "zambalu", "show_radiance", _c("show_radiance", 40))
	else:
		# Sans rayonnement culturel, les Recrues viennent des tournées : un artiste par représentation.
		ed["pop"] = int(ed["pop"]) + 1
		Insolites.add_species(ed, host.faction_id, 1)
	Research.count_stat(state, eid, "shows")
	added.append(state.add_chronicle("Le Cirque Zambalù triomphe à %s ! %s paie %d énergie de billetterie et ne parle que de ça pendant six mois." % [
			state.galaxy.systems[sid].system_name, host.short_name(), ticket], Espionage.private_to(state, [eid, b], sid)))


## Grand Spectacle (prop. 107) : chez un hôte dont la foi d'État est de cette nature, la représentation
## est une messe : elle convertit un habitant de la plus grande colonie du système et les fidèles paient
## une seconde billetterie.
static func _spectacle_mass(state: GameState, e: Empire, host: Empire, sid: int) -> void:
	var fid := Faiths.state_faith(state, host.id)
	if not state.faith_on or FaithWars.nature(state, fid) != "grand_spectacle":
		return
	e.resources["energy"] = int(e.resources.get("energy", 0)) + Insolites.tuned(state, e.id, "zambalu", "show_ticket", _c("show_ticket", 20))
	var best: Colony = null
	for pid in state.galaxy.systems[sid].planet_ids:
		var c: Colony = state.colonies.get(pid)
		if c != null and c.owner == host.id and c.is_colony() and c.population > 0 and (best == null or c.population > best.population):
			best = c
	if best != null:
		Faiths._convert_one(best, fid)


## Tournée triomphale (prop. 19) : en guerre, une Troupe escortée tient 90 jours le système d'une colonie
## ennemie sans bataille ; la colonie devient un Fan-club et reste à son propriétaire.
static func _tour_day(state: GameState, eid: int, ed: Dictionary, f: Fleet, b: int, added: Array[Dictionary]) -> void:
	var tours: Dictionary = ed["tours"]
	var key := str(f.id)
	var sid := f.system_id
	if not Combat.is_armed(f) or state.battles.has(sid):
		tours.erase(key)
		return
	var target := -1
	for pid in state.galaxy.systems[sid].planet_ids:
		var c: Colony = state.colonies.get(pid)
		if c == null or c.owner != b or not c.is_colony() or not c.is_established() or not Insolites.implant(state, pid).is_empty():
			continue
		if target < 0 or c.population > (state.colonies[target] as Colony).population:
			target = pid
	if target < 0:
		tours.erase(key)
		return
	if not tours.has(key) or int(tours[key]["p"]) != target:
		tours[key] = {"s": sid, "p": target, "left": Insolites.tuned(state, eid, "zambalu", "tour_days", _c("tour_days", 90))}
	var t: Dictionary = tours[key]
	t["left"] = int(t["left"]) - 1
	if int(t["left"]) > 0:
		return
	tours.erase(key)
	Insolites.add_implant(state, target, "fan_club", eid)
	Research.count_stat(state, eid, "fan_clubs")
	added.append(state.add_chronicle("Tournée triomphale : %s devient un Fan-club du Cirque Zambalù. Les drapeaux de %s flottent encore, mais tout le monde porte le maillot." % [
			state.galaxy.get_planet(target).display_name(state.galaxy), state.get_empire(b).short_name()], Espionage.public_to(state, [eid, b])))


## Recrues (prop. 20) : la culture du Cirque devient Influente chez un empire, ses artistes le rejoignent ;
## chaque palier de plus en amène d'autres.
static func _recruits(state: GameState, eid: int, ed: Dictionary, added: Array[Dictionary]) -> void:
	if state.culture.is_empty():
		return
	var rec: Dictionary = ed.get("rec", {})
	var need := _c("recruit_tier", 3)
	for b in Culture.living(state):
		if b == eid or b >= state.empires.size():
			continue
		var t := Culture.tier(state, eid, b)
		var last := int(rec.get(str(b), 0))
		if t < need or t <= last:
			continue
		var gain := _c("recruit_pop", 3) if last < need else _c("recruit_next_tier", 2) * (t - last)
		rec[str(b)] = t
		ed["pop"] = int(ed["pop"]) + gain
		Insolites.add_species(ed, state.get_empire(b).faction_id, gain)
		added.append(state.add_chronicle("Des artistes de %s rejoignent le Chapiteau (%d population) : le Cirque y est désormais %s." % [
				state.get_empire(b).short_name(), gain, Culture.tier_label(t)], Espionage.private_to(state, [eid, b])))
	ed["rec"] = rec


# --- Le Grand Numéro (prop. 22) ----------------------------------------------------------------------

static func numero_day(state: GameState, added: Array[Dictionary]) -> void:
	for eid in Insolites.nomad_ids(state):
		var ed := Insolites.emp(state, eid)
		if String(ed["k"]) != "zambalu":
			continue
		var num: Dictionary = ed.get("num", {})
		if num.is_empty():
			continue
		var e := state.get_empire(eid)
		if int(num["call"]) == 0 and state.tick >= int(num["next"]):
			num["call"] = state.tick + _c("numero_call_days", 30)
			num["del"] = []
			added.append(state.add_chronicle("Le Cirque Zambalù annonce son Grand Numéro dans %d jours ! Tout empire qui y envoie un délégué suspendra ses guerres avec les autres délégués pendant six mois. Les places partent vite." % _c("numero_call_days", 30), []))
		elif int(num["call"]) > 0 and state.tick >= int(num["call"]):
			var dl: Array = num.get("del", [])
			dl.sort()
			var pairs := 0
			for i in dl.size():
				for j in range(i + 1, dl.size()):
					var a := int(dl[i])
					var b := int(dl[j])
					if (state.get_empire(a) as Empire).wars.has(b):
						Insolites.sub(state, "truce")[Insolites._pair(a, b)] = state.tick + _c("numero_truce_days", 180)
						pairs += 1
				if not state.culture.is_empty():
					var cum := Culture._m(state, "cum")
					var ck := Culture._k(eid, int(dl[i]))
					cum[ck] = int(cum.get(ck, 0)) + _c("numero_radiance", 30)
			e.resources["influence"] = int(e.resources.get("influence", 0)) + _c("numero_influence", 15) * dl.size()
			Research.count_stat(state, eid, "numeros")
			var names := PackedStringArray()
			for x in dl:
				names.append(state.get_empire(int(x)).short_name())
			added.append(state.add_chronicle("Le Grand Numéro du Cirque Zambalù ! %s. %s" % [
					("Délégués : %s" % ", ".join(names)) if not dl.is_empty() else "La salle est vide, le Cirque joue quand même",
					("Trêve du spectacle : %d guerre%s suspendue%s six mois." % [pairs, "s" if pairs > 1 else "", "s" if pairs > 1 else ""]) if pairs > 0 else "Personne n'avait de guerre à suspendre."], []))
			num["call"] = 0
			num["del"] = []
			num["next"] = state.tick + _c("numero_every_days", 3600)
		ed["num"] = num


## Cirque dont l'appel au Grand Numéro est ouvert (-1 sinon).
static func open_call(state: GameState) -> int:
	for eid in Insolites.nomad_ids(state):
		var ed := Insolites.emp(state, eid)
		if String(ed["k"]) == "zambalu" and int(ed.get("num", {}).get("call", 0)) > state.tick:
			return eid
	return -1


static func check_delegate(state: GameState, eid: int) -> String:
	var z := open_call(state)
	if z < 0:
		return "aucun Grand Numéro n'est annoncé"
	if z == eid:
		return "le Cirque joue son propre Grand Numéro"
	var e := state.get_empire(eid)
	if not e.contacts.has(z):
		return "vous n'avez jamais rencontré le Cirque"
	if Combat.at_war(state, eid, z):
		return "on n'envoie pas de délégué chez un ennemi"
	if (Insolites.emp(state, z)["num"]["del"] as Array).has(eid):
		return "votre délégué est déjà en route"
	return ""


static func delegate(state: GameState, eid: int) -> void:
	var z := open_call(state)
	(Insolites.emp(state, z)["num"]["del"] as Array).append(eid)


static func status_lines(state: GameState, eid: int, ed: Dictionary) -> Array[String]:
	var out: Array[String] = []
	out.append("Artistes au Chapiteau : %d" % int(ed["pop"]))
	var shows: Dictionary = ed.get("shows", {})
	for k in shows:
		out.append("Représentation à %s : %d jours" % [state.galaxy.systems[int(shows[k]["s"])].system_name, int(shows[k]["left"])])
	var tours: Dictionary = ed.get("tours", {})
	for k in tours:
		out.append("Tournée triomphale sur %s : %d jours" % [state.galaxy.get_planet(int(tours[k]["p"])).display_name(state.galaxy), int(tours[k]["left"])])
	var fc := Insolites.implants_of(state, eid).size()
	if fc > 0:
		out.append("Fan-clubs : %d" % fc)
	var num: Dictionary = ed.get("num", {})
	if int(num.get("call", 0)) > state.tick:
		out.append("Grand Numéro dans %d jours (%d délégués)" % [int(num["call"]) - state.tick, (num.get("del", []) as Array).size()])
	elif not num.is_empty():
		out.append("Prochain Grand Numéro dans %d jours" % maxi(0, int(num["next"]) - state.tick))
	return out
