class_name InsSignal
extends RefCounted
## Enfants du Signal (props 48 à 53 ; voir Insolites, data/insolites.json "signal").
## Aucune planète, aucun vaisseau : le Signal vit dans des Nœuds (implants cachés) hébergés par les
## colonies des autres. Trois nœuds au départ, dans les premières colonies des empires les plus proches ;
## chaque mois, chaque nœud peut se copier sur une colonie voisine (un saut) ou chez un partenaire
## commercial de son hôte. Bande passante : un nœud prend chaque mois une part du Savoir de son hôte ;
## l'hôte souffre de symptômes (stabilité) et ne voit les nœuds qu'avec le pare-feu culturel (Propagande).
## Synthétiques et Noosphère (gouvernement Conscience) attrapent le Signal deux fois plus vite.
## Corps empruntés : à partir de 12 nœuds, le Signal détourne un chantier hôte pour une flotte de
## 120 jours. Mutations : tous les 5 ans une variante gagne un trait, et parfois une variante hostile
## emporte un quart des nœuds (schisme). Seule diplomatie : l'Accord d'hébergement (l'hôte tolère, ne
## souffre plus et reçoit du Savoir). Victoire : la Saturation.
##
## État (Insolites.emp) : "mut": [traits], "mut_next": jour, "borrow": {"fid": fin}, "borrow_cd": jour,
## "hosts": {"eid": jour de l'accord}, "pop" (nombre de nœuds, mis à jour chaque mois).


static func _c(key: String, def := 0) -> int:
	return Insolites.c_int("signal", key, def)


static func found(state: GameState, _e: Empire, _sid: int, ed: Dictionary) -> void:
	ed["mut"] = []
	ed["mut_next"] = state.tick + _c("mutate_every_days", 1800)
	ed["borrow"] = {}
	ed["borrow_cd"] = 0
	ed["hosts"] = {}


static func nodes(state: GameState, eid: int) -> Array[int]:
	return Insolites.implants_of(state, eid, "noeud")


static func mut_fx(state: GameState, eid: int, key: String) -> int:
	var n := 0
	for id in Insolites.emp(state, eid).get("mut", []):
		for m: Dictionary in Insolites.cfg("signal").get("mutations", []):
			if String(m["id"]) == String(id):
				n += int(m.get("fx", {}).get(key, 0))
	return n


static func alive(state: GameState, eid: int) -> bool:
	return not nodes(state, eid).is_empty() or not (Insolites.emp(state, eid).get("borrow", {}) as Dictionary).is_empty()


## Synthétiques et Noosphère : deux fois plus vulnérables (l'inverse du Songe).
static func vulnerable(state: GameState, eid: int) -> bool:
	var e := state.get_empire(eid)
	if e == null or e.is_npc():
		return false
	var sp: Dictionary = e.faction().get("species", {})
	return String(sp.get("archetype", "")) == "synthetique" or String(sp.get("gouvernement", "")) == "conscience"


## L'hôte voit-il ce nœud ? Pare-feu culturel (Propagande) ; la variante furtive se cache encore un an.
static func detects(state: GameState, eid: int, im: Dictionary) -> bool:
	if Research.fx_int(state, eid, "meme_firewall") <= 0:
		return false
	return mut_fx(state, int(im.get("o", -1)), "stealth") <= 0 or state.tick - int(im.get("t", 0)) >= 360


static func hosted(state: GameState, sig: int, host: int) -> bool:
	return (Insolites.emp(state, sig).get("hosts", {}) as Dictionary).has(str(host))


## Bande passante prise chaque mois sur une colonie (Savoir).
static func bandwidth(state: GameState, sig: int, c: Colony) -> Dictionary:
	@warning_ignore("integer_division")
	var n := maxi(_c("bandwidth_min", 1), c.population * (_c("bandwidth_pct", 10) + mut_fx(state, sig, "bandwidth")) / 50)
	return {"knowledge": n}


static func _contact(state: GameState, a: int, b: int) -> void:
	if a == b or GameState.is_npc(b):
		return
	var ea := state.get_empire(a)
	var eb := state.get_empire(b)
	if not ea.contacts.has(b):
		ea.contacts.append(b)
	if not eb.contacts.has(a):
		eb.contacts.append(a)


## Premiers nœuds (Insolites.after_setup) : les colonies natales des empires les plus proches.
static func seed_nodes(state: GameState, eid: int) -> void:
	var e := state.get_empire(eid)
	var from := state.galaxy.get_planet(e.home_planet).system_id if e.home_planet >= 0 else 0
	var dist: Dictionary = FactionTraits.jumps_from(state.galaxy, from)
	var rows := []
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner == eid or GameState.is_npc(c.owner) or not c.is_colony():
			continue
		var sid := state.galaxy.get_planet(int(pid)).system_id
		rows.append([int(dist.get(sid, 999)), int(pid)])
	rows.sort()
	var placed := 0
	for row in rows:
		if placed >= _c("start_nodes", 3):
			break
		var c: Colony = state.colonies[int(row[1])]
		Insolites.add_implant(state, int(row[1]), "noeud", eid)
		_contact(state, eid, c.owner)
		placed += 1
	Insolites.emp(state, eid)["pop"] = placed


# --- Chaque jour ----------------------------------------------------------------------------------

static func daily(state: GameState, eid: int, ed: Dictionary, month: bool, added: Array[Dictionary]) -> void:
	_borrow_day(state, eid, ed, added)
	if state.tick >= int(ed.get("mut_next", 0)):
		_mutate(state, eid, ed, added)
	if not month:
		return
	_spread(state, eid)
	var mine := nodes(state, eid)
	ed["pop"] = mine.size()
	# Accord d'hébergement : l'hôte reçoit des technologies (du Savoir) pour la bande passante tolérée.
	var hosts: Dictionary = ed["hosts"]
	for k in hosts.keys():
		var h := state.get_empire(int(k))
		if h == null or h.eliminated:
			hosts.erase(k)
			continue
		var n := 0
		for pid in mine:
			if (state.colonies[pid] as Colony).owner == int(k):
				n += 1
		h.resources["knowledge"] = int(h.resources.get("knowledge", 0)) + n * _c("host_gift_knowledge", 4)
	# Corps empruntés (prop. 50).
	if mine.size() >= _c("borrow_nodes", 12) and state.tick >= int(ed.get("borrow_cd", 0)) and (ed["borrow"] as Dictionary).is_empty():
		_borrow(state, eid, ed, mine, added)


static func _spread(state: GameState, eid: int) -> void:
	var chance := _c("spread_pmille", 60) * (100 + mut_fx(state, eid, "spread_pct")) / 100
	for pid in nodes(state, eid):
		var c: Colony = state.colonies.get(pid)
		if c == null:
			continue
		var sid := state.galaxy.get_planet(pid).system_id
		var cands: Array[int] = []
		for nb in [sid] + Array(state.galaxy.systems[sid].neighbors):
			for qid in state.galaxy.systems[int(nb)].planet_ids:
				_cand(state, eid, int(qid), cands)
		for o in state.empires:
			if o.id != c.owner and not o.is_npc() and not o.eliminated and Diplomacy.has_trade(state, c.owner, o.id):
				var cap := o.capital_planet if o.capital_planet >= 0 else o.home_planet
				_cand(state, eid, cap, cands)
		if cands.is_empty():
			continue
		var h := hash([state.seed_value, state.tick, pid, "signal"])
		var target := cands[posmod(h, cands.size())]
		var tc: Colony = state.colonies[target]
		var ch := chance * (_c("spread_vulnerable_x", 2) if vulnerable(state, tc.owner) else 1)
		if posmod(h / 7, 1000) < ch:
			Insolites.add_implant(state, target, "noeud", eid)
			_contact(state, eid, tc.owner)


static func _cand(state: GameState, eid: int, pid: int, out: Array[int]) -> void:
	var c: Colony = state.colonies.get(pid)
	if c == null or not c.is_colony() or not c.is_established() or c.owner == eid or GameState.is_npc(c.owner):
		return
	if not Insolites.implant(state, pid, "noeud").is_empty() or out.has(pid):
		return
	out.append(pid)


static func _mutate(state: GameState, eid: int, ed: Dictionary, added: Array[Dictionary]) -> void:
	ed["mut_next"] = state.tick + _c("mutate_every_days", 1800)
	var free := []
	for m: Dictionary in Insolites.cfg("signal").get("mutations", []):
		if not (ed["mut"] as Array).has(String(m["id"])):
			free.append(m)
	var h := hash([state.seed_value, state.tick, eid, "mutation"])
	if not free.is_empty():
		var m: Dictionary = free[posmod(h, free.size())]
		(ed["mut"] as Array).append(String(m["id"]))
		added.append(state.add_chronicle("Le Signal mute : %s. %s Personne ne sait qui a écrit la mise à jour." % [String(m["label"]), String(m.get("text", ""))], Espionage.private_to(state, [eid])))
	if posmod(h / 13, 1000) < _c("schism_pmille", 250):
		var mine := nodes(state, eid)
		@warning_ignore("integer_division")
		var lose := mine.size() * _c("schism_share_pct", 25) / 100
		for i in lose:
			var pid := mine[mine.size() - 1 - i]
			Insolites.remove_implant(state, pid, "noeud")
		if lose > 0:
			added.append(state.add_chronicle("Schisme du Signal : une variante se déclare hostile au Signal et emporte %d nœuds. Les deux versions s'accusent mutuellement d'être une copie." % lose, Espionage.private_to(state, [eid])))


static func _borrow(state: GameState, eid: int, ed: Dictionary, mine: Array[int], added: Array[Dictionary]) -> void:
	var best := -1
	for pid in mine:
		var c: Colony = state.colonies[pid]
		if not c.has_kind("arsenal") and not c.buildings.has("capitale"):
			continue
		if best < 0 or c.population > (state.colonies[best] as Colony).population:
			best = pid
	if best < 0:
		best = mine[0]
	var sid := state.galaxy.get_planet(best).system_id
	var ships: Array = Insolites.cfg("signal").get("borrow_ships", ["corvette"])
	var f := state.spawn_ship(eid, String(ships[0]), sid)
	for i in range(1, ships.size()):
		f.add_ship(String(ships[i]), -1, Research.mark_gen(state, eid))
	f.fleet_name = "Corps empruntés"
	(ed["borrow"] as Dictionary)[str(f.id)] = state.tick + _c("borrow_days", 120)
	ed["borrow_cd"] = state.tick + _c("borrow_cooldown_days", 720)
	var host := (state.colonies[best] as Colony).owner
	added.append(state.add_chronicle("Les chantiers de %s ont construit cette nuit %d vaisseaux que personne n'a commandés. Leurs équipages parlent d'une seule voix." % [
			state.galaxy.get_planet(best).display_name(state.galaxy), ships.size()], Espionage.private_to(state, [eid, host], sid)))


static func _borrow_day(state: GameState, eid: int, ed: Dictionary, added: Array[Dictionary]) -> void:
	var b: Dictionary = ed.get("borrow", {})
	for k in b.keys():
		if int(b[k]) > state.tick and state.fleets.has(int(k)):
			continue
		b.erase(k)
		if state.fleets.has(int(k)):
			var f: Fleet = state.fleets[int(k)]
			state.fleets.erase(int(k))
			added.append(state.add_chronicle("Les Corps empruntés du Signal s'éteignent : les équipages se réveillent à leur poste, sans souvenir des trois derniers mois.", Espionage.private_to(state, [eid], f.system_id)))


# --- Accord d'hébergement (prop. 53) ---------------------------------------------------------------

static func check_host(state: GameState, host: int, sig: int, on: bool) -> String:
	if Insolites.kind(state, sig) != "signal":
		return "aucun Signal à héberger"
	var h := state.get_empire(host)
	if h == null or h.is_npc() or host == sig:
		return "empire inconnu"
	if not h.contacts.has(sig):
		return "vous n'avez jamais rencontré le Signal"
	if on and hosted(state, sig, host):
		return "l'accord est déjà en vigueur"
	if not on and not hosted(state, sig, host):
		return "aucun accord à rompre"
	return ""


static func set_host(state: GameState, host: int, sig: int, on: bool, added: Array[Dictionary]) -> void:
	var hosts: Dictionary = Insolites.emp(state, sig)["hosts"]
	if on:
		hosts[str(host)] = state.tick
		added.append(state.add_chronicle("%s signe un Accord d'hébergement avec le Signal. Les calculateurs ne grésillent plus ; parfois, une équation se résout toute seule pendant la nuit." % state.get_empire(host).short_name(), Espionage.private_to(state, [host, sig])))
	else:
		hosts.erase(str(host))
		added.append(state.add_chronicle("%s rompt son Accord d'hébergement avec le Signal." % state.get_empire(host).short_name(), Espionage.private_to(state, [host, sig])))


## Symptômes (stabilité) dans un système : un nœud non toléré chez son propriétaire.
static func symptoms(state: GameState, sid: int, owner: int) -> bool:
	for eid in Insolites.nomad_ids(state):
		if Insolites.kind(state, eid) != "signal" or hosted(state, eid, owner) or mut_fx(state, eid, "quiet") > 0:
			continue
		for pid in state.galaxy.systems[sid].planet_ids:
			var im := Insolites.implant(state, pid, "noeud")
			if not im.is_empty() and int(im["o"]) == eid:
				return true
	return false


# --- Victoire : la Saturation (prop. 52) ------------------------------------------------------------

static func victory(state: GameState, e: Empire, out: Dictionary) -> void:
	var want := int(Insolites.cfg("victories").get("saturation", {}).get("pct", _c("saturation_pct", 40)))
	var total := 0
	var ok := 0
	var mine := nodes(state, e.id)
	for o in state.empires:
		if o.id == e.id or o.is_npc() or o.eliminated:
			continue
		var cols := 0
		var hit := 0
		for pid in state.sorted_colony_ids():
			var c: Colony = state.colonies[pid]
			if c.owner == o.id and c.is_colony():
				cols += 1
				if mine.has(int(pid)):
					hit += 1
		if cols == 0:
			continue
		total += 1
		@warning_ignore("integer_division")
		var pct := hit * 100 / cols
		if pct >= want:
			ok += 1
		out["lines"].append("%s : %d %% des colonies" % [o.short_name(), pct])
	out["lines"].insert(0, "Empires saturés (%d %% de leurs colonies) : %d / %d" % [want, ok, total])
	out["cond"] = total > 0 and ok >= total
	Victory._timed(out, ok, maxi(1, total))


static func status_lines(state: GameState, eid: int, ed: Dictionary) -> Array[String]:
	var out: Array[String] = []
	out.append("Nœuds : %d ; hôtes sous accord : %d" % [nodes(state, eid).size(), (ed.get("hosts", {}) as Dictionary).size()])
	var names := PackedStringArray()
	for id in ed.get("mut", []):
		for m: Dictionary in Insolites.cfg("signal").get("mutations", []):
			if String(m["id"]) == String(id):
				names.append(String(m["label"]))
	if not names.is_empty():
		out.append("Variantes : %s" % ", ".join(names))
	if not (ed.get("borrow", {}) as Dictionary).is_empty():
		out.append("Corps empruntés en vol")
	return out
