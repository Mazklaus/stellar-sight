class_name InsAsphodele
extends RefCounted
## Asphodèle, Cité des Trépassés (props 59 à 64 ; voir Insolites, data/insolites.json "asphodele").
## Sa population ne naît pas (croissance nulle) : elle accueille les morts des autres empires.
##   - Les Âmes : chaque mois, toute baisse de population d'une colonie compte des morts (recensement ;
##     un départ en vaisseau colon n'en est pas un). Les morts à reach_jumps sauts d'une colonie
##     d'Asphodèle, sur une planète à Ossuaire, ou dans une colonie fidèle de la Traversée (nature de foi),
##     versent leurs Âmes ; souls_per_pop Âmes deviennent un habitant numérisé qui garde son espèce.
##   - Ossuaires : implants posés chez un signataire du Pacte funéraire (stabilité et piété pour l'hôte).
##     La loi « Rites funéraires protégés » de l'Amphictyonie interdit les pactes.
##   - Revenants : un héros mort n'importe où peut être réveillé au service d'Asphodèle.
##   - Nécro-conseil : trois Anciens accumulent de l'Usure ; on les laisse partir (Savoir et piété).
##   - Victoire : le Grand Rassemblement (accueillir les morts de la moitié de la galaxie, en cumul).
##
## État (Insolites.emp) : "souls", "gathered" (cumul), "ssp": {espèce: Âmes en attente}, "council":
## [{"n": nom, "t": jour d'entrée}], "pacts": {empire: jour} ; état commun state.insolites["census"] =
## {"pid": population du mois dernier}, "dep": {"pid": départs du mois}, "fallen": [héros morts].


static func _c(key: String, def := 0) -> int:
	return Insolites.c_int("asphodele", key, def)


static func found(state: GameState, e: Empire, _sid: int, ed: Dictionary) -> void:
	ed["souls"] = 0
	ed["gathered"] = 0
	ed["ssp"] = {}
	ed["pacts"] = {}
	var names: Array = Insolites.cfg("asphodele").get("council_names", ["un Ancien"])
	var council := []
	for i in _c("council_seats", 3):
		council.append({"n": String(names[posmod(hash([state.seed_value, e.id, "conseil", i]), names.size())]) if i == 0 else String(names[i % names.size()]),
				"t": state.tick - i * 360})
	ed["council"] = council


static func asphodeles(state: GameState) -> Array[int]:
	var out: Array[int] = []
	for eid in Insolites.nomad_ids(state):
		if Insolites.kind(state, eid) == "asphodele":
			out.append(eid)
	return out


# --- Recensement des morts (prop. 60) ----------------------------------------------------------------

## Un départ volontaire (vaisseau colon) n'est pas une mort : à décompter du recensement.
static func note_departure(state: GameState, pid: int, n: int) -> void:
	if state.insolites.is_empty() or n <= 0 or asphodeles(state).is_empty():
		return
	var dep := Insolites.sub(state, "dep")
	dep[str(pid)] = int(dep.get(str(pid), 0)) + n


## Bilan du mois, une fois pour toute la galaxie : qui est mort, où, et à qui vont les Âmes.
static func census(state: GameState, added: Array[Dictionary]) -> void:
	var asph := asphodeles(state)
	if asph.is_empty():
		return
	var old := Insolites.sub(state, "census")
	var dep := Insolites.sub(state, "dep")
	var now := {}
	var reach := {}
	for a in asph:
		reach[a] = _reach(state, a)
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if not c.is_colony():
			continue
		now[str(pid)] = c.population
		var dead := int(old.get(str(pid), c.population)) - c.population - int(dep.get(str(pid), 0))
		if dead <= 0:
			continue
		var p := state.galaxy.get_planet(int(pid))
		var to := -1
		for a in asph:
			if a == c.owner:
				to = a
				break
			var oss := Insolites.implant(state, int(pid), "ossuaire")
			if (not oss.is_empty() and int(oss["o"]) == a) or (reach[a] as Dictionary).has(p.system_id) or _traversee(state, c):
				to = a
				break
		if to >= 0:
			_receive(state, to, c, dead)
	# Planètes disparues (mangées, détruites) : tous leurs habitants sont morts.
	for key in old:
		if not now.has(key) and int(old[key]) > 0:
			var p2 := state.galaxy.get_planet(int(key))
			if p2 == null:
				continue
			for a in asph:
				if (reach[a] as Dictionary).has(p2.system_id):
					_receive(state, a, null, int(old[key]))
					break
	state.insolites["census"] = now
	state.insolites["dep"] = {}
	for a in asph:
		_awaken(state, a, added)


## Systèmes à portée des nécropoles : reach_jumps sauts autour de chaque colonie d'Asphodèle.
static func _reach(state: GameState, eid: int) -> Dictionary:
	var out := {}
	var r := _c("reach_jumps", 5)
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner != eid or not c.is_colony():
			continue
		var d: Dictionary = FactionTraits.jumps_from(state.galaxy, state.galaxy.get_planet(int(pid)).system_id)
		for sid in d:
			if int(d[sid]) <= r:
				out[int(sid)] = true
	return out


## Colonie fidèle de la Traversée (nature de foi) : ses morts trouvent Asphodèle à toute distance.
static func _traversee(state: GameState, c: Colony) -> bool:
	if not state.faith_on:
		return false
	var fid := Faiths.majority(c)
	return fid != "" and FaithWars.nature(state, fid) == "traversee"


static func _receive(state: GameState, eid: int, c: Colony, dead: int) -> void:
	var ed := Insolites.emp(state, eid)
	ed["souls"] = int(ed.get("souls", 0)) + dead
	ed["gathered"] = int(ed.get("gathered", 0)) + dead
	var ssp: Dictionary = ed.get("ssp", {})
	var fid := ""
	if c != null:
		var counts := Peoples.counts(state, c) if Peoples.enabled(state) else {}
		var best := -1
		var ks := counts.keys()
		ks.sort()
		for k in ks:
			if int(counts[k]) > best:
				best = int(counts[k])
				fid = String(k)
		if fid == "":
			var oe := state.get_empire(c.owner)
			fid = oe.faction_id if oe != null and not oe.is_npc() else (Minors.species_id(state, c.owner) if not state.minors.is_empty() and GameState.is_npc(c.owner) else "")
	if fid != "":
		ssp[fid] = int(ssp.get(fid, 0)) + dead
	ed["ssp"] = ssp


## Les Âmes deviennent des habitants numérisés, qui gardent leur espèce (prop. 62).
static func _awaken(state: GameState, eid: int, added: Array[Dictionary]) -> void:
	var ed := Insolites.emp(state, eid)
	var e := state.get_empire(eid)
	var per := maxi(1, _c("souls_per_pop", 2))
	var n := 0
	while int(ed["souls"]) >= per and n < _c("souls_cap_per_month", 4):
		var c := _roomiest(state, eid)
		if c == null:
			break
		ed["souls"] = int(ed["souls"]) - per
		n += 1
		c.population += 1
		var fid := _take_species(ed, per)
		if fid != "" and fid != e.faction_id and Peoples.enabled(state):
			c.species[fid] = int(c.species.get(fid, 0)) + 1
	if n > 0 and state.tick % 360 < 30:
		added.append(state.add_chronicle("Dans les nécropoles d'Asphodèle, %d mort%s ouvre%s les yeux. On leur explique ; ils posent toujours les mêmes questions." % [
				n, "s" if n > 1 else "", "nt" if n > 1 else ""], Espionage.private_to(state, [eid])))


static func _take_species(ed: Dictionary, per: int) -> String:
	var ssp: Dictionary = ed.get("ssp", {})
	var best := ""
	var bn := 0
	var ks := ssp.keys()
	ks.sort()
	for k in ks:
		if int(ssp[k]) > bn:
			bn = int(ssp[k])
			best = String(k)
	if best != "":
		ssp[best] = int(ssp[best]) - per
		if int(ssp[best]) <= 0:
			ssp.erase(best)
	return best


static func _roomiest(state: GameState, eid: int) -> Colony:
	var best: Colony = null
	var room := 0
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner != eid or not c.is_colony():
			continue
		var r := Economy.max_pop(state, state.galaxy.get_planet(int(pid)), eid, c.buildings) - c.population
		if r > room:
			room = r
			best = c
	return best


# --- Pacte funéraire et Ossuaires (prop. 61) --------------------------------------------------------

static func pacted(state: GameState, a: int, host: int) -> bool:
	return (Insolites.emp(state, a).get("pacts", {}) as Dictionary).has(str(host))


static func check_pact(state: GameState, host: int, a: int, on: bool) -> String:
	if Insolites.kind(state, a) != "asphodele":
		return "le Pacte funéraire se signe avec Asphodèle"
	if host == a:
		return "Asphodèle garde déjà ses morts"
	var e := state.get_empire(host)
	if not e.contacts.has(a):
		return "vous n'avez jamais rencontré Asphodèle"
	if not on:
		return "" if pacted(state, a, host) else "aucun pacte à rompre"
	if pacted(state, a, host):
		return "le pacte est déjà signé"
	if Combat.at_war(state, host, a):
		return "pas de pacte en guerre"
	if Insolites.funeral_banned(state):
		return "la loi « Rites funéraires protégés » de l'Amphictyonie interdit les pactes"
	return ""


static func set_pact(state: GameState, host: int, a: int, on: bool, added: Array[Dictionary]) -> void:
	var pacts: Dictionary = Insolites.emp(state, a).get("pacts", {})
	if on:
		pacts[str(host)] = state.tick
		_ossuaries(state, a, host)
		added.append(state.add_chronicle("%s signe le Pacte funéraire avec Asphodèle. Les premiers Ossuaires ouvrent : on y dépose les morts, on en repart plus léger." % state.get_empire(host).display_name(),
				Espionage.public_to(state, [host, a])))
	else:
		pacts.erase(str(host))
		for pid in Insolites.implants_of(state, a, "ossuaire"):
			if (state.colonies[pid] as Colony).owner == host:
				Insolites.remove_implant(state, pid, "ossuaire")
		Diplomacy.remember(state, a, host, "ins_pact_broken")
		added.append(state.add_chronicle("%s rompt le Pacte funéraire. Les Ossuaires ferment ; personne n'ose demander où vont les morts maintenant." % state.get_empire(host).display_name(),
				Espionage.public_to(state, [host, a])))
	Insolites.emp(state, a)["pacts"] = pacts


## Un Ossuaire sur chaque colonie établie du signataire (nouvelles colonies comprises, chaque mois).
static func _ossuaries(state: GameState, a: int, host: int) -> void:
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner == host and c.is_colony() and c.is_established() and Insolites.implant(state, int(pid), "ossuaire").is_empty():
			Insolites.add_implant(state, int(pid), "ossuaire", a)


# --- Revenants (prop. 62) ---------------------------------------------------------------------------

## Un héros meurt (Heroes.die) : il rejoint la liste des morts qu'Asphodèle peut réveiller.
static func on_hero_death(state: GameState, h: Dictionary) -> void:
	if asphodeles(state).is_empty() or bool(h.get("revenant", false)):
		return
	var fallen: Array = state.insolites.get("fallen", [])
	fallen.append({"name": String(h["name"]), "portrait": String(h.get("portrait", "")), "cls": String(h.get("cls", "stratege")),
			"lvl": int(h.get("lvl", 1)), "sp": String(h.get("sp", "")), "o": int(h.get("owner", -1)), "t": state.tick})
	while fallen.size() > _c("fallen_max", 8):
		fallen.pop_front()
	state.insolites["fallen"] = fallen


static func fallen(state: GameState) -> Array:
	return state.insolites.get("fallen", [])


static func check_raise(state: GameState, eid: int, i: int) -> String:
	if Insolites.kind(state, eid) != "asphodele":
		return "seule Asphodèle réveille les morts"
	if i < 0 or i >= fallen(state).size():
		return "aucun mort de ce nom"
	if Heroes.ids_of(state, eid).size() >= Heroes.cap(state, eid):
		return "le conseil n'a plus de place pour un héros"
	var cost: Dictionary = Insolites.cfg("asphodele").get("raise_cost", {})
	if not Economy.can_afford(state.get_empire(eid), cost):
		return "ressources insuffisantes (il faut %s)" % GameData.format_amounts(cost)
	return ""


static func raise(state: GameState, eid: int, i: int, added: Array[Dictionary]) -> void:
	var f: Dictionary = fallen(state)[i]
	Economy.pay(state.get_empire(eid), Insolites.cfg("asphodele").get("raise_cost", {}))
	(state.insolites["fallen"] as Array).remove_at(i)
	var cand := Heroes.make_candidate(state, eid, String(f["cls"]), ["revenant", eid, state.tick])
	cand["name"] = String(f["name"])
	if String(f["portrait"]) != "":
		cand["portrait"] = String(f["portrait"])
	var id := Heroes.recruit(state, eid, cand)
	var h: Dictionary = state.heroes[id]
	h["lvl"] = maxi(int(h["lvl"]), int(f["lvl"]))
	h["revenant"] = true
	if String(f["sp"]) != "":
		h["sp"] = String(f["sp"])
	var was := state.get_empire(int(f["o"]))
	if was != null and int(f["o"]) != eid:
		Diplomacy.remember(state, int(f["o"]), eid, "ins_revenant")
	added.append(state.add_chronicle("%s se réveille dans une nécropole d'Asphodèle. Il demande l'année, puis s'il peut garder son ancien grade. On lui dit oui." % String(f["name"]),
			Espionage.public_to(state, [eid, int(f["o"])])))


# --- Nécro-conseil (prop. 63) -----------------------------------------------------------------------

static func lassitude(state: GameState, seat: Dictionary) -> int:
	@warning_ignore("integer_division")
	return (state.tick - int(seat["t"])) / 30


static func tired(state: GameState, eid: int) -> int:
	var n := 0
	for s: Dictionary in Insolites.emp(state, eid).get("council", []):
		if lassitude(state, s) >= _c("lassitude_max", 60):
			n += 1
	return n


static func check_release(state: GameState, eid: int, i: int) -> String:
	if Insolites.kind(state, eid) != "asphodele":
		return "seul le Nécro-conseil laisse partir ses Anciens"
	var council: Array = Insolites.emp(state, eid).get("council", [])
	if i < 0 or i >= council.size():
		return "aucun Ancien à ce siège"
	if lassitude(state, council[i]) < _c("lassitude_max", 60) / 2:
		return "cet Ancien n'est pas encore las (%d mois d'Usure sur %d)" % [lassitude(state, council[i]), _c("lassitude_max", 60)]
	return ""


static func release(state: GameState, eid: int, i: int, added: Array[Dictionary]) -> void:
	var e := state.get_empire(eid)
	var council: Array = Insolites.emp(state, eid)["council"]
	var old: Dictionary = council[i]
	e.resources["knowledge"] = int(e.resources.get("knowledge", 0)) + _c("release_knowledge", 120)
	e.resources["influence"] = int(e.resources.get("influence", 0)) + _c("release_influence", 20)
	if FactionTraits.has_fervor(e.faction()):
		e.fervor = mini(int(e.faction()["fervor"]["max"]), e.fervor + 10)
	var name := ""
	var fl := fallen(state)
	if not fl.is_empty():
		name = String((fl[fl.size() - 1] as Dictionary)["name"])
	else:
		var names: Array = Insolites.cfg("asphodele").get("council_names", ["un Ancien"])
		name = String(names[posmod(hash([state.seed_value, state.tick, eid, "siege"]), names.size())])
	council[i] = {"n": name, "t": state.tick}
	added.append(state.add_chronicle("Le Nécro-conseil laisse partir %s, qui siégeait depuis %d ans. Une dernière phrase, que personne ne note, puis le silence ; %s prend la place encore tiède." % [
			String(old["n"]), lassitude(state, old) / 12, name], Espionage.private_to(state, [eid])))


# --- Branchements -----------------------------------------------------------------------------------

## Lignes de stabilité : Usure des Anciens chez Asphodèle, Ossuaire chez l'hôte.
static func stability_parts(state: GameState, sid: int, owner: int, out: Array) -> void:
	if Insolites.kind(state, owner) == "asphodele":
		var t := tired(state, owner)
		if t > 0:
			out.append(["Usure des Anciens (%d)" % t, t * _c("lassitude_stab", -4)])
	for pid in state.galaxy.systems[sid].planet_ids:
		var c: Colony = state.colonies.get(pid)
		if c != null and c.owner == owner and not Insolites.implant(state, int(pid), "ossuaire").is_empty():
			out.append(["Ossuaire d'Asphodèle", int(Insolites.implant_def("ossuaire").get("stability", 3))])
			return


## Les fois réagissent (prop. 64) : le Culte des ancêtres et la Traversée l'aiment, d'autres l'exècrent.
static func opinion_parts(state: GameState, a: int, b: int, out: Array) -> void:
	if Insolites.kind(state, b) != "asphodele" or not state.faith_on:
		return
	var sf := Faiths.state_faith(state, a)
	if sf == "":
		return
	var nat := FaithWars.nature(state, sf)
	if (Insolites.cfg("asphodele").get("faith_like", []) as Array).has(nat):
		out.append(["Leur foi honore les morts", _c("faith_like_op", 15)])
	elif (Insolites.cfg("asphodele").get("faith_hate", []) as Array).has(nat):
		out.append(["Leur foi exècre la Cité des Trépassés", _c("faith_hate_op", -15)])


static func daily(state: GameState, eid: int, ed: Dictionary, month: bool, _added: Array[Dictionary]) -> void:
	if not month:
		return
	var pacts: Dictionary = ed.get("pacts", {})
	for k in pacts.keys():
		var host := state.get_empire(int(k))
		if host == null or host.eliminated or Combat.at_war(state, int(k), eid) or Insolites.funeral_banned(state):
			pacts.erase(k)
			for pid in Insolites.implants_of(state, eid, "ossuaire"):
				if (state.colonies[pid] as Colony).owner == int(k):
					Insolites.remove_implant(state, pid, "ossuaire")
			continue
		_ossuaries(state, eid, int(k))
	ed["pop"] = 0


# --- Victoire : le Grand Rassemblement (prop. 64) ----------------------------------------------------

static func galaxy_pop(state: GameState) -> int:
	var n := 0
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.is_colony() and not GameState.is_npc(c.owner):
			n += c.population
	return n


static func victory(state: GameState, e: Empire, out: Dictionary) -> void:
	var want := int(Insolites.cfg("victories").get("grand_rassemblement", {}).get("pct", 50))
	var g := int(Insolites.emp(state, e.id).get("gathered", 0))
	var tot := galaxy_pop(state)
	@warning_ignore("integer_division")
	var pct := g * 100 / tot if tot > 0 else 0
	out["lines"].append("Morts accueillis : %d, soit %d %% de la population de la galaxie (%d %% voulus)" % [g, pct, want])
	out["cond"] = tot > 0 and pct >= want
	Victory._timed(out, mini(pct, want), want)


static func status_lines(state: GameState, eid: int, ed: Dictionary) -> Array[String]:
	var out: Array[String] = []
	out.append("Âmes en attente : %d ; morts accueillis : %d" % [int(ed.get("souls", 0)), int(ed.get("gathered", 0))])
	out.append("Pactes funéraires : %d ; Ossuaires : %d" % [(ed.get("pacts", {}) as Dictionary).size(), Insolites.implants_of(state, eid, "ossuaire").size()])
	var seats := PackedStringArray()
	for s: Dictionary in ed.get("council", []):
		seats.append("%s (%d mois)" % [String(s["n"]), lassitude(state, s)])
	out.append("Nécro-conseil : %s" % ", ".join(seats))
	if not fallen(state).is_empty():
		out.append("Morts illustres à réveiller : %d" % fallen(state).size())
	return out
