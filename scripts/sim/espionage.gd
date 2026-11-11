class_name Espionage
extends RefCounted
## Espionnage, lot 1 : les réseaux de l'ombre et le renseignement (voir data/espionage.json).
##
## Chaque empire a des CELLULES (2 au départ, plus avec les ères). Il les affecte chez un empire
## rencontré, où elles font monter un RÉSEAU (infiltration de 0 à 100), ou chez lui, où elles font
## du contre-espionnage (elles freinent tous les réseaux étrangers et renforcent le chiffrement).
## Chaque mois, l'infiltration bouge selon les cellules, l'écart entre le déchiffrement de l'espion et
## le chiffrement de la cible (leurs ères), le commerce, la frontière et la guerre.
##
## Le réseau montre sans rien faire, par paliers :
## - 20, Cartographes : les relevés de ses systèmes (Intel) se mettent à jour chaque mois ;
## - 40, Comptables : un dossier (ressources, recherche, technologies) et sa chronique intérieure ;
## - 60, Amirauté : ses flottes ; - 80, Conseil : ses guerres et ce qu'il pense de chacun.
## Les opérations (voler, saboter, intriguer) viendront au lot 2, les talents de peuple au lot 3.
##
## Les SONDES donnent un relevé ponctuel d'un système connu, sans réseau.
## La CHRONIQUE ne dit à chacun que ce qu'il peut savoir : voir public_to, private_to et can_read.
##
## Tout est déterministe : entiers, parcours dans l'ordre des identifiants, aucun aléatoire.
## Inspiration et sources : data/espionage.json ("_sources").


static func data() -> Dictionary:
	return GameData.espionage()


static func key(a: int, b: int) -> String:
	return "%d>%d" % [a, b]


# --- Cellules ----------------------------------------------------------------------------------

## Cellules dont dispose l'empire : celles du départ, plus celles de son ère.
static func cells_total(state: GameState, empire_id: int) -> int:
	var c: Dictionary = data()["cells"]
	var per: Array = c["per_era"]
	var era := Research.current_era(state, empire_id)
	return int(c["start"]) + int(per[clampi(era - 1, 0, per.size() - 1)])


## Cellules affectées par a chez b (chez lui-même quand a == b : contre-espionnage).
static func cells_on(state: GameState, a: int, b: int) -> int:
	return int((state.networks.get(key(a, b), {}) as Dictionary).get("cells", 0))


static func home_cells(state: GameState, empire_id: int) -> int:
	return cells_on(state, empire_id, empire_id)


static func cells_used(state: GameState, empire_id: int) -> int:
	var n := 0
	for k in state.networks:
		var net: Dictionary = state.networks[k]
		if int(net["a"]) == empire_id:
			n += int(net["cells"])
	return n


static func cells_free(state: GameState, empire_id: int) -> int:
	return cells_total(state, empire_id) - cells_used(state, empire_id)


## Peut-on mettre n cellules de player chez target (target == player : contre-espionnage) ?
static func check_cells(state: GameState, player: int, target: int, n: int) -> String:
	var e := state.get_empire(player)
	var t := state.get_empire(target)
	if e == null or e.eliminated:
		return "empire inconnu"
	if t == null or t.eliminated:
		return "cible inconnue"
	if target != player and not e.contacts.has(target):
		return "empire jamais rencontré"
	if n < 0:
		return "nombre de cellules invalide"
	if cells_used(state, player) - cells_on(state, player, target) + n > cells_total(state, player):
		return "pas assez de cellules (%d en tout)" % cells_total(state, player)
	return ""


static func set_cells(state: GameState, a: int, b: int, n: int) -> void:
	var k := key(a, b)
	var net: Dictionary = state.networks.get(k, {})
	if net.is_empty():
		if n <= 0:
			return
		net = {"a": a, "b": b, "cells": 0, "inf": 0}
		state.networks[k] = net
	net["cells"] = n
	if n <= 0 and int(net["inf"]) <= 0:
		state.networks.erase(k)


# --- Réseaux -----------------------------------------------------------------------------------

## Infiltration de a chez b (0 à 100). Un empire se connaît lui-même entièrement.
static func infiltration(state: GameState, a: int, b: int) -> int:
	if a == b:
		return int(data()["network"]["max"])
	return int((state.networks.get(key(a, b), {}) as Dictionary).get("inf", 0))


static func decryption(state: GameState, empire_id: int) -> int:
	return Research.current_era(state, empire_id)


static func encryption(state: GameState, empire_id: int) -> int:
	var bonus := int(data()["network"]["home_cell_encryption"]) if home_cells(state, empire_id) > 0 else 0
	return Research.current_era(state, empire_id) + bonus


## Pourcentage de croissance selon déchiffrement de a moins chiffrement de b.
static func crypto_pct(state: GameState, a: int, b: int) -> int:
	var table: Array = data()["network"]["crypto_pct"]
	var diff := clampi(decryption(state, a) - encryption(state, b), -2, 2)
	return int(table[diff + 2])


## Raisons de l'évolution mensuelle du réseau de a chez b : [[libellé, valeur], …].
static func growth_parts(state: GameState, a: int, b: int) -> Array:
	var cfg: Dictionary = data()["network"]
	var out := []
	var cells := cells_on(state, a, b)
	if cells <= 0:
		if infiltration(state, a, b) > 0:
			out.append(["Aucune cellule : le réseau s'étiole", -int(cfg["decay_without_cells"])])
		return out
	var pct := crypto_pct(state, a, b)
	@warning_ignore("integer_division")
	var base := cells * int(cfg["growth_per_cell"]) * pct / 100
	out.append(["%d cellule%s (déchiffrement %d contre chiffrement %d : %d %%)" % [
			cells, "s" if cells > 1 else "", decryption(state, a), encryption(state, b), pct], base])
	if Diplomacy.has_trade(state, a, b):
		out.append(["Accord commercial : les cargos cachent bien", int(cfg["trade_bonus"])])
	if Diplomacy.border_systems(state, a, b) > 0 or Diplomacy.border_systems(state, b, a) > 0:
		out.append(["Frontière commune", int(cfg["border_bonus"])])
	if Combat.at_war(state, a, b):
		out.append(["En guerre : tout le monde se méfie", -int(cfg["war_malus"])])
	var counter := home_cells(state, b)
	if counter > 0:
		out.append(["Contre-espionnage (%d cellule%s)" % [counter, "s" if counter > 1 else ""], -counter * int(cfg["counter_per_cell"])])
	return out


static func growth(state: GameState, a: int, b: int) -> int:
	var n := 0
	for p in growth_parts(state, a, b):
		n += int(p[1])
	return n


## Palier atteint par a chez b : 0 (rien) à 4 (Conseil).
static func tier(state: GameState, a: int, b: int) -> int:
	var inf := infiltration(state, a, b)
	var t := 0
	for i in data()["tiers"].size():
		if inf >= int(data()["tiers"][i]["at"]):
			t = i + 1
	return t


static func tier_info(t: int) -> Dictionary:
	var tiers: Array = data()["tiers"]
	return tiers[t - 1] if t >= 1 and t <= tiers.size() else {}


static func tier_at(t: int) -> int:
	return int(tier_info(t).get("at", 0))


## Réseaux étrangers que b soupçonne : il faut au moins une cellule chez soi, et le réseau doit avoir
## atteint le premier palier (on ne remarque pas trois curieux). Identifiants des espions, triés.
static func suspected(state: GameState, b: int) -> Array[int]:
	var out: Array[int] = []
	if home_cells(state, b) <= 0:
		return out
	for e in state.empires:
		if e.id != b and infiltration(state, e.id, b) >= tier_at(1):
			out.append(e.id)
	return out


# --- Mois --------------------------------------------------------------------------------------

## Chaque mois : infiltration, sondes, puis ce que chaque réseau rapporte.
static func monthly(state: GameState) -> void:
	var cap := int(data()["network"]["max"])
	var ks := state.networks.keys()
	ks.sort()
	# 1) Les réseaux bougent tous sur l'état du début du mois (l'ordre n'a pas d'effet).
	var deltas := {}
	for k in ks:
		var net: Dictionary = state.networks[k]
		var a := int(net["a"])
		var b := int(net["b"])
		if a == b:
			continue
		deltas[k] = growth(state, a, b)
	for k in ks:
		var net: Dictionary = state.networks[k]
		var a := int(net["a"])
		var b := int(net["b"])
		if state.get_empire(a).eliminated or state.get_empire(b).eliminated:
			state.networks.erase(k)
			continue
		if a == b:
			continue
		net["inf"] = clampi(int(net["inf"]) + int(deltas[k]), 0, cap)
		if int(net["cells"]) <= 0 and int(net["inf"]) <= 0:
			state.networks.erase(k)
	# Cellules en trop (ne devrait pas arriver : les ères ne reculent pas) : on retire des réseaux.
	for e in state.empires:
		_trim_cells(state, e.id)
	# 2) Sondes.
	for e in state.empires:
		if not e.eliminated:
			_regen_probes(state, e)
	# 3) Ce que rapportent les réseaux.
	ks = state.networks.keys()
	ks.sort()
	for k in ks:
		var net: Dictionary = state.networks[k]
		var a := int(net["a"])
		var b := int(net["b"])
		if a == b:
			continue
		var t := tier(state, a, b)
		var spy := state.get_empire(a)
		if t >= 1:
			Intel.record_systems(state, spy, EmpireReport.owned_systems(state, b))
		if t >= 2:
			spy.dossiers[b] = dossier(state, b, t)
		else:
			spy.dossiers.erase(b)


static func _trim_cells(state: GameState, empire_id: int) -> void:
	var extra := cells_used(state, empire_id) - cells_total(state, empire_id)
	if extra <= 0:
		return
	var ks := state.networks.keys()
	ks.sort()
	ks.reverse()
	for k in ks:
		var net: Dictionary = state.networks[k]
		if int(net["a"]) != empire_id or extra <= 0:
			continue
		var take := mini(extra, int(net["cells"]))
		set_cells(state, empire_id, int(net["b"]), int(net["cells"]) - take)
		extra -= take


## Dossier de renseignement sur un empire, selon le palier atteint (2 à 4). Entiers et textes seulement.
static func dossier(state: GameState, b: int, t: int) -> Dictionary:
	var e := state.get_empire(b)
	var d := {"day": state.tick, "tier": t}
	var res := {}
	for r in GameData.resource_ids():
		res[r] = int(e.resources.get(r, 0))
	d["res"] = res
	d["research"] = String(e.research_queue[0]) if not e.research_queue.is_empty() else ""
	d["techs"] = e.techs.size()
	d["era"] = Research.current_era(state, b)
	d["colonies"] = EmpireReport.owned_systems(state, b).size()
	if t >= 3:
		var fleets := []
		var ships := 0
		var armed := 0
		for fid in state.sorted_fleet_ids():
			var f: Fleet = state.fleets[fid]
			if f.owner != b:
				continue
			var w := 0
			for s in f.ships:
				if Combat.is_armed_ship(String(s)):
					w += 1
			fleets.append([f.system_id, f.ships.size(), w])
			ships += f.ships.size()
			armed += w
		d["fleets"] = fleets
		d["ships"] = ships
		d["warships"] = armed
	if t >= 4:
		d["wars"] = Array(e.wars)
		var ops := []
		for o in e.contacts:
			var oe := state.get_empire(o)
			if oe != null and not oe.eliminated:
				ops.append([o, Diplomacy.opinion(state, b, o)])
		d["opinions"] = ops
	return d


# --- Sondes ------------------------------------------------------------------------------------

static func probe_cost() -> Dictionary:
	return data()["probes"]["cost"]


static func probes_max() -> int:
	return int(data()["probes"]["max"])


## Jours avant la prochaine sonde (0 si le stock est plein).
static func probe_wait(state: GameState, e: Empire) -> int:
	if e.probes >= probes_max():
		return 0
	return maxi(0, e.probe_day + int(data()["probes"]["regen_days"]) - state.tick)


static func _regen_probes(state: GameState, e: Empire) -> void:
	if e.probes >= probes_max():
		e.probe_day = state.tick
		return
	if state.tick - e.probe_day >= int(data()["probes"]["regen_days"]):
		e.probes += 1
		e.probe_day = state.tick


static func check_probe(state: GameState, player: int, system_id: int) -> String:
	var e := state.get_empire(player)
	if e == null or e.eliminated:
		return "empire inconnu"
	if state.galaxy.get_system(system_id) == null:
		return "système inconnu"
	if not e.explored.has(system_id) and not e.intel.has(system_id):
		return "système jamais exploré"
	if Intel.is_live(state, player, system_id):
		return "ce système est déjà en vue"
	if e.probes <= 0:
		return "aucune sonde prête (prochaine dans %d jours)" % probe_wait(state, e)
	if not Economy.can_afford(e, probe_cost()):
		return "pas assez de ressources (%s)" % GameData.format_amounts(probe_cost())
	return ""


static func probe(state: GameState, player: int, system_id: int) -> void:
	var e := state.get_empire(player)
	if e.probes >= probes_max():
		e.probe_day = state.tick  # le compte à rebours de la suivante part maintenant
	e.probes -= 1
	Economy.pay(e, probe_cost())
	Intel.record_systems(state, e, [system_id])


# --- Chronique : qui sait quoi ? ---------------------------------------------------------------

## Événement public (guerre, traité, empire disparu…) : connu des empires concernés et de tous ceux
## qui ont rencontré l'un d'eux. Identifiants triés.
static func public_to(state: GameState, about: Array) -> Array:
	var out := []
	for e in state.empires:
		if about.has(e.id):
			out.append(e.id)
			continue
		for x in about:
			if e.contacts.has(int(x)):
				out.append(e.id)
				break
	return out


## Événement intérieur (colonie, chantier, découverte, bataille…) : connu des empires concernés, de
## leurs alliés, de ceux qui ont un réseau Comptables (40) chez l'un d'eux, et, s'il a lieu dans un
## système (system_id >= 0), de ceux qui le voient en ce moment. Identifiants triés.
static func private_to(state: GameState, about: Array, system_id := -1) -> Array:
	var out := []
	var need := tier_at(2)
	for e in state.empires:
		var knows := about.has(e.id)
		if not knows:
			for x in about:
				var xi := int(x)
				if Diplomacy.allied(state, e.id, xi) or infiltration(state, e.id, xi) >= need:
					knows = true
					break
		if not knows and system_id >= 0 and not e.eliminated:
			knows = _sees(state, e.id, system_id)
		if knows:
			out.append(e.id)
	return out


## Empires engagés dans une bataille (ses camps).
static func battle_sides(b: Dictionary) -> Array:
	var out := []
	for s: Dictionary in b["sides"]:
		out.append(int(s["empire"]))
	return out


## Vision du jour (ou de la veille, avant que les flottes n'aient bougé ce tick).
static func _sees(state: GameState, viewer: int, system_id: int) -> bool:
	if state.seen_tick >= state.tick - 1 and viewer < state.seen_cache.size():
		return state.seen_cache[viewer].has(system_id)
	return Fleets.visible_systems(state, viewer).has(system_id)


## Le lecteur (-1 : tout voir) peut-il lire cette entrée de chronique ?
static func can_read(entry: Dictionary, viewer: int) -> bool:
	if viewer < 0 or not entry.has("who"):
		return true
	return (entry["who"] as Array).has(viewer)


## Dernières entrées lisibles par le lecteur, de la plus récente à la plus ancienne.
static func readable(state: GameState, viewer: int, count: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in range(state.chronicle.size() - 1, -1, -1):
		if out.size() >= count:
			break
		var entry: Dictionary = state.chronicle[i]
		if can_read(entry, viewer):
			out.append(entry)
	return out


# --- Sauvegarde --------------------------------------------------------------------------------

static func networks_to_list(state: GameState) -> Array:
	var ks := state.networks.keys()
	ks.sort()
	var out := []
	for k in ks:
		var net: Dictionary = state.networks[k]
		out.append([int(net["a"]), int(net["b"]), int(net["cells"]), int(net["inf"])])
	return out


static func networks_from_list(state: GameState, rows: Array) -> void:
	for row in rows:
		if not row is Array or row.size() < 4:
			continue
		var a := int(row[0])
		var b := int(row[1])
		state.networks[key(a, b)] = {"a": a, "b": b, "cells": int(row[2]), "inf": int(row[3])}
