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
## OPÉRATIONS (lot 2, catalogue dans data/espionage.json) : un réseau assez haut lance une opération
## payée en influence ; ses chances de succès et de découverte sont fixées et affichées au lancement, puis
## tranchées à son terme par un hachage de la partie. Une opération découverte coûte de l'infiltration,
## laisse un souvenir et un grief d'un an (déclarer la guerre à l'espion n'est pas un parjure), rompt
## une alliance, et ouvre un « dossier » où la victime choisit : expulser ou exiger réparation.
## Le credo Profit (talent "spy" de sa fiche) : +1 cellule, larcins à moitié prix, réseaux deux fois
## plus rapides chez un partenaire commercial, dividende semestriel chez ces partenaires.
## Lot 3 : l'INTRIGUE (semer la discorde, corrompre un héritier), le RÉSEAU RETOURNÉ (la victime
## d'une découverte peut garder le réseau en vie et lui faire écrire de faux relevés et de faux dossiers,
## jusqu'à ce que l'espion s'en rende compte), et les TALENTS DE PEUPLE par couche d'espèce
## (data "talents" : féodalité, république, ruche, conscience distribuée, foi, synthétiques).
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
	return int(c["start"]) + int(per[clampi(era - 1, 0, per.size() - 1)]) + int(talent(state, empire_id).get("extra_cells", 0))


## Talents d'espionnage du peuple : celui de sa fiche (research.spy, credo Profit) plus ceux de ses
## couches d'espèce (data "talents"). Les valeurs s'additionnent, en entiers.
static func talent(state: GameState, empire_id: int) -> Dictionary:
	var e := state.get_empire(empire_id)
	if e == null:
		return {}
	var out := {}
	var own: Dictionary = e.faction().get("research", {}).get("spy", {})
	for k in own:
		out[k] = int(own[k])
	var sp: Dictionary = e.faction().get("species", {})
	var table: Dictionary = data().get("talents", {})
	for layer in LAYERS:
		var t: Dictionary = (table.get(layer, {}) as Dictionary).get(String(sp.get(layer, "")), {})
		for k in t:
			if k != "label" and k != "text":
				out[k] = int(out.get(k, 0)) + int(t[k])
	return out


const LAYERS := ["archetype", "gouvernement", "credo"]


## Talents à afficher : [[nom, texte], …] (fiche du peuple, puis couches d'espèce).
static func talent_labels(state: GameState, empire_id: int) -> Array:
	var e := state.get_empire(empire_id)
	var out := []
	if e == null:
		return out
	var research: Dictionary = e.faction().get("research", {})
	if research.has("spy"):
		out.append([String(research.get("name", "Talent")), String(research.get("text", ""))])
	var sp: Dictionary = e.faction().get("species", {})
	var table: Dictionary = data().get("talents", {})
	for layer in LAYERS:
		var t: Dictionary = (table.get(layer, {}) as Dictionary).get(String(sp.get(layer, "")), {})
		if not t.is_empty():
			out.append([String(t["label"]), String(t["text"])])
	return out


## Cellules de contre-espionnage de b, pondérées (l'Inquisition de la foi les compte double).
static func counter_weight(state: GameState, b: int) -> int:
	return home_cells(state, b) * maxi(1, int(talent(state, b).get("counter_x", 1)))


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
	return Research.current_era(state, empire_id) + int(talent(state, empire_id).get("decryption", 0))


static func encryption(state: GameState, empire_id: int) -> int:
	var bonus := int(data()["network"]["home_cell_encryption"]) if home_cells(state, empire_id) > 0 else 0
	return Research.current_era(state, empire_id) + bonus + int(talent(state, empire_id).get("encryption", 0))


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
	var trade_pct := int(talent(state, a).get("trade_growth_pct", 100))
	if trade_pct != 100 and Diplomacy.has_trade(state, a, b):
		@warning_ignore("integer_division")
		base = base * trade_pct / 100
	out.append(["%d cellule%s (déchiffrement %d contre chiffrement %d : %d %%)" % [
			cells, "s" if cells > 1 else "", decryption(state, a), encryption(state, b), pct], base])
	if Diplomacy.has_trade(state, a, b):
		out.append(["Accord commercial : les cargos cachent bien", int(cfg["trade_bonus"])])
	if Diplomacy.border_systems(state, a, b) > 0 or Diplomacy.border_systems(state, b, a) > 0:
		out.append(["Frontière commune", int(cfg["border_bonus"])])
	if Combat.at_war(state, a, b):
		out.append(["En guerre : tout le monde se méfie", -int(cfg["war_malus"])])
	var open := int(talent(state, b).get("open_nodes", 0))
	if open != 0:
		out.append(["Conscience partagée : ses nœuds sont ouverts", open])
	var counter := home_cells(state, b)
	if counter > 0:
		var w := counter_weight(state, b)
		out.append(["Contre-espionnage (%d cellule%s%s)" % [counter, "s" if counter > 1 else "", ", Inquisition" if w > counter else ""],
				-w * int(cfg["counter_per_cell"])])
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
			_record(state, a, b)
		# Sous le palier Comptables, le dernier dossier reste, daté (dernière information connue).
		if t >= 2:
			spy.dossiers[b] = _report(state, a, b, t)
	# 4) Réseaux retournés : l'espion finit-il par s'en rendre compte ?
	for k in ks:
		var net: Dictionary = state.networks.get(k, {})
		if not net.is_empty() and int(net.get("turned", 0)) == 1:
			_spot_turned(state, int(net["a"]), int(net["b"]))
	# 5) Dividendes du credo Profit.
	for e in state.empires:
		if not e.eliminated:
			_dividends(state, e.id)


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
				if Diplomacy.allied(state, e.id, xi) or (infiltration(state, e.id, xi) >= need and not is_turned(state, e.id, xi)):
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


# --- Opérations (lot 2) ------------------------------------------------------------------------

static func op_ids() -> Array[String]:
	var out: Array[String] = []
	for o: Dictionary in data()["operations"]:
		out.append(String(o["id"]))
	return out


static func op_def(op_id: String) -> Dictionary:
	for o: Dictionary in data()["operations"]:
		if String(o["id"]) == op_id:
			return o
	return {}


const FAMILY_LABELS := {"renseignement": "Renseignement", "larcin": "Larcin", "sabotage": "Sabotage", "intrigue": "Intrigue"}


## Coût d'une opération pour l'espion (les larcins du credo Profit sont moins chers).
static func op_cost(state: GameState, a: int, op_id: String) -> Dictionary:
	var o := op_def(op_id)
	var cost: Dictionary = (o.get("cost", {}) as Dictionary).duplicate()
	var pct := int(talent(state, a).get("%s_cost_pct" % String(o.get("family", "")), 100))
	if pct != 100:
		for r in cost:
			@warning_ignore("integer_division")
			cost[r] = int(cost[r]) * pct / 100
	return cost


## Chances {"success", "discovery"} en %, et leurs raisons {"success_parts", "discovery_parts"}.
static func chances(state: GameState, a: int, b: int, op_id: String) -> Dictionary:
	var o := op_def(op_id)
	var c: Dictionary = data()["chances"]
	var above := maxi(0, tier(state, a, b) - int(o["tier"]))
	var crypto := decryption(state, a) - encryption(state, b)
	var era_gap := maxi(0, Research.current_era(state, b) - Research.current_era(state, a))
	var counter := home_cells(state, b)
	var sp := [["Base", int(o["success"])]]
	if above > 0:
		sp.append(["Réseau au-dessus du palier requis", above * int(c["per_tier"])])
	if crypto != 0:
		sp.append(["Déchiffrement contre chiffrement", crypto * int(c["per_crypto"])])
	var dp := [["Base", int(o["discovery"])]]
	if counter > 0:
		dp.append(["Contre-espionnage (%d cellule%s)" % [counter, "s" if counter > 1 else ""], counter_weight(state, b) * int(c["counter_per_cell"])])
	if era_gap > 0:
		dp.append(["Cible plus avancée", era_gap * int(c["era_gap_discovery"])])
	if above > 0:
		dp.append(["Réseau bien implanté", -above * int(c["per_tier"])])
	var succ := 0
	for p in sp:
		succ += int(p[1])
	var disc := 0
	for p in dp:
		disc += int(p[1])
	return {"success": clampi(succ, int(c["min"]), int(c["max"])), "discovery": clampi(disc, int(c["min"]), int(c["max"])),
			"success_parts": sp, "discovery_parts": dp}


## Opération en cours de a chez b, {} sinon (une seule à la fois par réseau).
static func running(state: GameState, a: int, b: int) -> Dictionary:
	for op in state.operations:
		if int(op["a"]) == a and int(op["b"]) == b:
			return op
	return {}


static func check_op(state: GameState, a: int, b: int, op_id: String) -> String:
	var e := state.get_empire(a)
	var t := state.get_empire(b)
	if e == null or e.eliminated:
		return "empire inconnu"
	if t == null or t.eliminated or a == b:
		return "cible inconnue"
	var o := op_def(op_id)
	if o.is_empty():
		return "opération inconnue"
	if not e.contacts.has(b):
		return "empire jamais rencontré"
	var need := int(o["tier"])
	if tier(state, a, b) < need:
		return "il faut un réseau à %d (%s)" % [tier_at(need), tier_info(need)["label"]]
	if not running(state, a, b).is_empty():
		return "une opération est déjà en cours chez lui"
	if String(o.get("family", "")) == "intrigue":
		if int(talent(state, a).get("no_intrigue", 0)) > 0:
			return "une ruche ne complote pas : elle dévore"
		if int(talent(state, b).get("intrigue_immune", 0)) > 0:
			return "aucune intrigue ne prend sur une ruche : ni cour, ni rumeurs"
	match op_id:
		"discorde":
			if _framed(state, a, b) < 0:
				return "il n'a aucun ami à brouiller"
		"heritier":
			if not Diplomacy.has_heir(state, b):
				return "cet empire n'a pas d'héritier"
		"vol_techno":
			if Research.steal_target(state, a, b) == "":
				return "il ne connaît rien que vous puissiez lui voler"
		"siphon":
			if int(t.resources.get("energy", 0)) <= 0:
				return "ses réserves d'énergie sont vides"
		"sabotage_chantier":
			if _sabotage_site(state, b) < 0:
				return "aucun chantier en cours chez lui"
		"archives":
			if t.research_progress <= 0:
				return "aucune recherche à brûler"
	var cost := op_cost(state, a, op_id)
	if not Economy.can_afford(e, cost):
		return "pas assez de ressources (%s)" % GameData.format_amounts(cost)
	return ""


static func launch(state: GameState, a: int, b: int, op_id: String) -> void:
	var o := op_def(op_id)
	Economy.pay(state.get_empire(a), op_cost(state, a, op_id))
	var ch := chances(state, a, b, op_id)
	state.operations.append({"id": state.next_spy_id, "a": a, "b": b, "op": op_id, "start": state.tick,
			"end": state.tick + int(o["days"]), "success": int(ch["success"]), "discovery": int(ch["discovery"])})
	state.next_spy_id += 1


## Annuler une opération en cours : l'influence est perdue, mais rien ne peut plus être découvert.
static func check_cancel(state: GameState, a: int, b: int) -> String:
	return "aucune opération en cours chez lui" if running(state, a, b).is_empty() else ""


static func cancel(state: GameState, a: int, b: int) -> void:
	state.operations.erase(running(state, a, b))


## Chaque jour : opérations arrivées à terme, dossiers de découverte restés sans réponse.
static func daily(state: GameState) -> void:
	if not state.operations.is_empty():
		var done: Array[Dictionary] = []
		for op in state.operations:
			if int(op["end"]) <= state.tick:
				done.append(op)
		for op in done:
			state.operations.erase(op)
			_resolve(state, op)
	if not state.spy_cases.is_empty():
		var limit := int(data()["discovery"]["answer_days"])
		var late: Array[Dictionary] = []
		for c in state.spy_cases:
			if state.tick - int(c["tick"]) >= limit:
				late.append(c)
		for c in late:
			answer(state, int(c["victim"]), int(c["id"]), "expel")


## Jet déterministe (0 à 99) : même partie, même opération, même réponse sur toutes les machines.
static func _roll(state: GameState, op: Dictionary, what: String) -> int:
	return posmod(hash([state.seed_value, int(op["id"]), int(op["a"]), int(op["b"]), String(op["op"]), what]), 100)


static func _resolve(state: GameState, op: Dictionary) -> void:
	var a := int(op["a"])
	var b := int(op["b"])
	var ea := state.get_empire(a)
	var eb := state.get_empire(b)
	if ea == null or eb == null or ea.eliminated or eb.eliminated:
		return
	var o := op_def(String(op["op"]))
	if is_turned(state, a, b):
		_resolve_turned(state, a, b, o)
		return
	var ok := _roll(state, op, "succès") < int(op["success"])
	var seen := _roll(state, op, "découverte") < int(op["discovery"])
	var what := ""
	if ok:
		what = _apply(state, a, b, o)
		var net: Dictionary = state.networks.get(key(a, b), {})
		if not net.is_empty():
			net["inf"] = maxi(0, int(net["inf"]) - int(o.get("spend", 0)))
		Research.count_stat(state, a, "operations")
	if not seen:
		if ok:
			state.add_chronicle("%s, chez %s : %s" % [o["label"], eb.short_name(), what], private_to(state, [a]))
		else:
			state.add_chronicle("%s, chez %s : l'opération échoue sans bruit. Les agents rentrent les mains vides et les pieds secs." % [
					o["label"], eb.short_name()], private_to(state, [a]))
		return
	_discovered(state, a, b, o, ok, what)


## Effet d'une opération réussie ; renvoie la phrase de la chronique.
static func _apply(state: GameState, a: int, b: int, o: Dictionary) -> String:
	var ea := state.get_empire(a)
	var eb := state.get_empire(b)
	match String(o["id"]):
		"rapport":
			ea.dossiers[b] = dossier(state, b, data()["tiers"].size())
			Intel.record_systems(state, ea, EmpireReport.owned_systems(state, b))
			return "le dossier complet est sur la table, cartes à jour comprises."
		"vol_techno":
			var tid := Research.steal_target(state, a, b)
			if tid == "":
				return "les archives ne contenaient rien de neuf. Dommage, la serrure était belle."
			@warning_ignore("integer_division")
			var amount := maxi(1, Research.cost(state, a, tid) * int(o["steal_pct"]) / 100)
			Research.add_progress(state, a, tid, amount)
			Research.count_stat(state, a, "stolen")
			return "les plans de « %s » changent de mains (%d Savoir)." % [String(Research.tech(tid).get("label", tid)), amount]
		"siphon":
			@warning_ignore("integer_division")
			var take := mini(int(o["take_max"]), maxi(0, int(eb.resources.get("energy", 0))) * int(o["take_pct"]) / 100)
			eb.resources["energy"] = int(eb.resources.get("energy", 0)) - take
			ea.resources["energy"] = int(ea.resources.get("energy", 0)) + take
			return "%d énergie détournée. Les compteurs de la cible tournent, les nôtres aussi." % take
		"sabotage_chantier":
			var pid := _sabotage_site(state, b)
			if pid < 0:
				return "le chantier visé était déjà terminé. Les explosifs serviront une autre fois."
			var c: Colony = state.colonies[pid]
			if c.ship_build != "":
				c.ship_days += int(o["delay_days"])
			else:
				c.construction_days += int(o["delay_days"])
			return "le chantier de %s prend %d jours de retard. Un boulon mal serré, puis mille." % [
					state.galaxy.get_planet(pid).display_name(state.galaxy), int(o["delay_days"])]
		"archives":
			@warning_ignore("integer_division")
			var burnt := eb.research_progress * int(o["burn_pct"]) / 100
			eb.research_progress -= burnt
			return "%d Savoir partent en fumée. Les bibliothécaires accusent la foudre, puis les rats." % burnt
		"discorde":
			var c := _framed(state, a, b)
			if c < 0:
				return "il n'avait plus d'ami à brouiller. Les fausses preuves finissent au broyeur."
			Diplomacy.remember(state, b, c, "framed")
			return "de fausses preuves accusent %s de l'espionner. L'amitié refroidit d'un coup." % state.get_empire(c).short_name()
		"heritier":
			if not Diplomacy.has_heir(state, b):
				return "l'héritier n'est plus là. La bourse reste dans la poche."
			eb.heir_loyalty = maxi(0, eb.heir_loyalty - int(o["loyalty_loss"]))
			eb.heir_suitor = a
			return "l'héritier accepte nos conseils, et notre or (loyauté %d). C'est à nous qu'il pense, désormais." % eb.heir_loyalty
	return ""


## Empire que la discorde accuserait : celui que b aime le plus (hors espion), -1 si aucun.
static func _framed(state: GameState, a: int, b: int) -> int:
	var eb := state.get_empire(b)
	var best := -1
	var best_op := 0
	for c in eb.contacts:
		var ec := state.get_empire(c)
		if c == a or ec == null or ec.eliminated:
			continue
		var op := Diplomacy.opinion(state, b, c)
		if best < 0 or op > best_op:
			best = c
			best_op = op
	return best


## Colonie dont le chantier serait saboté : la capitale si elle construit, sinon la plus peuplée qui
## construit (vaisseau ou bâtiment). -1 si aucune.
static func _sabotage_site(state: GameState, b: int) -> int:
	var eb := state.get_empire(b)
	var best := -1
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner != b or (c.ship_build == "" and c.construction == ""):
			continue
		if pid == eb.capital_planet:
			return pid
		if best < 0 or c.population > (state.colonies[best] as Colony).population:
			best = pid
	return best


static func _discovered(state: GameState, a: int, b: int, o: Dictionary, ok: bool, what: String) -> void:
	var ea := state.get_empire(a)
	var eb := state.get_empire(b)
	var net: Dictionary = state.networks.get(key(a, b), {})
	if not net.is_empty():
		net["inf"] = maxi(0, int(net["inf"]) - int(data()["discovery"]["infiltration_loss"]))
	var tb := talent(state, b)
	for i in maxi(1, int(tb.get("caught_memory", 1))):
		Diplomacy.remember(state, b, a, "spy_caught")
	Diplomacy.remember(state, b, a, "spy_grief")
	var verdict := "Ils ont réussi quand même : %s" % what if ok else "Ils repartent bredouilles, et repérés."
	state.add_chronicle("Des agents de %s sont démasqués chez %s (%s). %s" % [ea.display_name(), eb.display_name(), String(o["label"]).to_lower(), verdict],
			public_to(state, [a, b]))
	var zeal := int(tb.get("fervor_on_catch", 0))
	if zeal > 0 and FactionTraits.has_fervor(eb.faction()) and _credo(state, a) != _credo(state, b):
		eb.fervor = mini(int(eb.faction()["fervor"]["max"]), eb.fervor + zeal)
		state.add_chronicle("Des espions infidèles ! Les prêcheurs de %s tiennent leur sermon de la semaine (ferveur +%d)." % [eb.short_name(), zeal],
				private_to(state, [b]))
	if Diplomacy.allied(state, a, b):
		Diplomacy.break_alliance_for_spying(state, b, a)
	if int(tb.get("devour", 0)) > 0:
		if not net.is_empty():
			net["inf"] = 0
		set_cells(state, a, b, 0)
		Diplomacy.remember(state, a, b, "spy_expelled")
		state.add_chronicle("La ruche de %s ne pose pas de questions aux agents de %s. Elle les digère. Le réseau s'éteint avec eux." % [
				eb.display_name(), ea.display_name()], public_to(state, [a, b]))
		return
	var case := {"id": state.next_spy_id, "victim": b, "spy": a, "op": String(o["id"]), "tick": state.tick}
	state.next_spy_id += 1
	state.spy_cases.append(case)
	if eb.is_ai():
		answer(state, b, int(case["id"]), AiEspionage.response(state, b, a))


static func cases_for(state: GameState, victim: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c in state.spy_cases:
		if int(c["victim"]) == victim:
			out.append(c)
	return out


static func check_answer(state: GameState, victim: int, case_id: int, choice: String) -> String:
	if not ["expel", "reparation", "turn"].has(choice):
		return "réponse inconnue"
	for c in state.spy_cases:
		if int(c["id"]) == case_id:
			if int(c["victim"]) != victim:
				return "ce dossier ne vous concerne pas"
			if choice == "turn":
				return check_turn(state, victim, int(c["spy"]))
			return ""
	return "dossier inconnu"


## Peut-on retourner le réseau de spy ? Il faut des agents chez soi pour mener des agents doubles.
static func check_turn(state: GameState, victim: int, spy: int) -> String:
	if home_cells(state, victim) <= 0:
		return "il faut au moins une cellule de contre-espionnage pour mener des agents doubles"
	if infiltration(state, spy, victim) <= 0:
		return "leur réseau s'est effondré : plus rien à retourner"
	return ""


## Réponse de la victime à une découverte.
## - expel : le réseau de l'espion tombe à 0 et ses cellules rentrent ;
## - reparation : l'espion paie (data "reparation") s'il le peut ; sinon, tous ceux qui le
##   connaissent retiennent qu'il a refusé de réparer.
static func answer(state: GameState, victim: int, case_id: int, choice: String) -> void:
	var case := {}
	for c in state.spy_cases:
		if int(c["id"]) == case_id:
			case = c
	if case.is_empty():
		return
	state.spy_cases.erase(case)
	var a := int(case["spy"])
	var ea := state.get_empire(a)
	var eb := state.get_empire(victim)
	if ea == null or ea.eliminated:
		return
	if choice == "turn" and check_turn(state, victim, a) == "":
		var tn: Dictionary = state.networks[key(a, victim)]
		tn["turned"] = 1
		state.add_chronicle("%s relâche les agents de %s sans un mot. Clémence, ou calcul ?" % [eb.display_name(), ea.display_name()],
				public_to(state, [a, victim]))
		state.add_chronicle("Les agents de %s travaillent désormais pour nous : leurs relevés et leurs dossiers diront ce que nous voudrons." % ea.short_name(),
				private_to(state, [victim]))
		return
	if choice == "expel" or choice == "turn":
		var net: Dictionary = state.networks.get(key(a, victim), {})
		if not net.is_empty():
			net["inf"] = 0
		set_cells(state, a, victim, 0)
		Diplomacy.remember(state, a, victim, "spy_expelled")
		state.add_chronicle("%s expulse les agents de %s. On les raccompagne au spatioport, avec leurs valises et sans leurs carnets." % [
				eb.display_name(), ea.display_name()], public_to(state, [a, victim]))
		return
	var due: Dictionary = data()["discovery"]["reparation"]
	if Economy.can_afford(ea, due):
		Economy.pay(ea, due)
		for r in due:
			eb.resources[r] = int(eb.resources.get(r, 0)) + int(due[r])
		Diplomacy.remember(state, victim, a, "spy_reparation")
		state.add_chronicle("%s paie réparation à %s pour ses espions (%s). Les excuses sont sincères, le chèque aussi." % [
				ea.display_name(), eb.display_name(), GameData.format_amounts(due)], public_to(state, [a, victim]))
	else:
		for e in state.empires:
			if e.id != a and not e.eliminated and e.contacts.has(a):
				Diplomacy.remember(state, e.id, a, "spy_shamed")
		state.add_chronicle("%s exige réparation de %s, qui fait la sourde oreille. Toute la galaxie l'apprend." % [
				eb.display_name(), ea.display_name()], public_to(state, [a, victim]))


## La guerre contre un espion démasqué depuis moins d'un an n'est pas un parjure (grief).
static func has_grief(state: GameState, a: int, b: int) -> bool:
	var days := int(GameData.diplomacy()["memories"]["spy_grief"]["days"])
	for m in state.memories:
		if int(m["who"]) == a and int(m["about"]) == b and String(m["kind"]) == "spy_grief" and state.tick - int(m["tick"]) < days:
			return true
	return false


## Dividende du credo Profit : tous les dividend_days, chaque réseau assez haut chez un partenaire
## commercial rapporte une part d'une technologie qu'il connaît et pas l'espion. Sans découverte.
static func _dividends(state: GameState, a: int) -> void:
	var tl := talent(state, a)
	if not tl.has("dividend_days"):
		return
	@warning_ignore("integer_division")
	var every := maxi(1, int(tl["dividend_days"]) / 30)
	@warning_ignore("integer_division")
	if posmod(state.tick / 30 + a, every) != 0:
		return
	var e := state.get_empire(a)
	for b in e.contacts:
		if infiltration(state, a, b) < int(tl["dividend_min"]) or not Diplomacy.has_trade(state, a, b):
			continue
		var tid := Research.steal_target(state, a, b)
		if tid == "":
			continue
		@warning_ignore("integer_division")
		var amount := maxi(1, Research.cost(state, a, tid) * int(tl["dividend_pct"]) / 100)
		Research.add_progress(state, a, tid, amount)
		Research.count_stat(state, a, "stolen")
		state.add_chronicle("Dividende : les cargos de %s rapportent de chez %s les plans de « %s » (%d Savoir), glissés entre deux caisses." % [
				e.short_name(), state.get_empire(b).short_name(), String(Research.tech(tid).get("label", tid)), amount], private_to(state, [a]))


# --- Réseau retourné (lot 3) -------------------------------------------------------------------

## Le réseau de a chez b a-t-il été retourné par b ?
static func is_turned(state: GameState, a: int, b: int) -> bool:
	return int((state.networks.get(key(a, b), {}) as Dictionary).get("turned", 0)) == 1


## Réseaux d'autres empires que b a retournés : identifiants des espions, triés.
static func turned_by(state: GameState, b: int) -> Array[int]:
	var out: Array[int] = []
	for e in state.empires:
		if e.id != b and is_turned(state, e.id, b):
			out.append(e.id)
	return out


static func _credo(state: GameState, empire_id: int) -> String:
	return String(state.get_empire(empire_id).faction().get("species", {}).get("credo", ""))


## Le réseau rapporte les relevés des systèmes de b ; retourné, une part d'entre eux sont faux
## (système libre, sans colonie), tirée par hachage pour chaque système et chaque mois.
static func _record(state: GameState, a: int, b: int) -> void:
	var spy := state.get_empire(a)
	var sids := EmpireReport.owned_systems(state, b)
	if not is_turned(state, a, b):
		Intel.record_systems(state, spy, sids)
		return
	var real := []
	var fake := []
	var pct := int(data()["turned"]["false_pct"])
	@warning_ignore("integer_division")
	var month := state.tick / 30
	for sid in sids:
		if posmod(hash([state.seed_value, "faux", a, b, int(sid), month]), 100) < pct:
			fake.append(int(sid))
		else:
			real.append(int(sid))
	Intel.record_systems(state, spy, real)
	fake.sort()
	for sid in fake:
		spy.intel[sid] = {"day": state.tick, "info": Intel.EMPTY_SURVEY}


## Dossier venu du réseau : vrai, ou arrangé par b s'il est retourné (réserves divisées par deux,
## aucune flotte, aucune guerre).
static func _report(state: GameState, a: int, b: int, t: int) -> Dictionary:
	var d := dossier(state, b, t)
	if not is_turned(state, a, b):
		return d
	var res: Dictionary = d["res"]
	for r in res:
		@warning_ignore("integer_division")
		res[r] = int(res[r]) / 2
	if d.has("fleets"):
		d["fleets"] = []
		d["ships"] = 0
		d["warships"] = 0
	if d.has("wars"):
		d["wars"] = []
	return d


## Une opération lancée par un réseau retourné : b la laisse croire réussie (rapport, faux) ou la fait
## échouer sans bruit. Jamais de découverte : b a mieux à faire que de démasquer ses propres agents.
static func _resolve_turned(state: GameState, a: int, b: int, o: Dictionary) -> void:
	var ea := state.get_empire(a)
	var eb := state.get_empire(b)
	if String(o["id"]) == "rapport":
		ea.dossiers[b] = _report(state, a, b, data()["tiers"].size())
		_record(state, a, b)
		state.add_chronicle("%s, chez %s : le dossier complet est sur la table, cartes à jour comprises." % [o["label"], eb.short_name()],
				private_to(state, [a]))
	else:
		state.add_chronicle("%s, chez %s : l'opération échoue sans bruit. Les agents rentrent les mains vides et les pieds secs." % [
				o["label"], eb.short_name()], private_to(state, [a]))
	state.add_chronicle("Nos agents doubles ont « aidé » %s à mener son opération (%s). Elle n'a rien donné, sauf à nous." % [
			ea.short_name(), String(o["label"]).to_lower()], private_to(state, [b]))


## Chances (en %) que l'espion découvre ce mois-ci que son réseau est retourné.
static func spot_chance(state: GameState, a: int, b: int) -> int:
	var cfg: Dictionary = data()["turned"]
	var n := int(cfg["spot_pct"]) + int(cfg["spot_per_crypto"]) * (decryption(state, a) - encryption(state, b))
	return clampi(n, int(cfg["spot_min"]), int(cfg["spot_max"]))


static func _spot_turned(state: GameState, a: int, b: int) -> void:
	if posmod(hash([state.seed_value, "retourné", a, b, state.tick]), 100) >= spot_chance(state, a, b):
		return
	var net: Dictionary = state.networks[key(a, b)]
	net.erase("turned")
	net["inf"] = 0
	Diplomacy.remember(state, a, b, "turned_us")
	var eb := state.get_empire(b)
	state.add_chronicle("Les relevés venus de chez %s ne collaient plus : notre réseau était retourné depuis des mois. On repart de zéro, avec des agents neufs et des soupçons anciens." % eb.short_name(),
			private_to(state, [a]))
	state.add_chronicle("%s a compris que ses agents travaillaient pour nous. La comédie est finie ; elle aura bien duré." % state.get_empire(a).short_name(),
			private_to(state, [b]))
	if int(net["cells"]) <= 0:
		state.networks.erase(key(a, b))


# --- Sauvegarde --------------------------------------------------------------------------------

static func networks_to_list(state: GameState) -> Array:
	var ks := state.networks.keys()
	ks.sort()
	var out := []
	for k in ks:
		var net: Dictionary = state.networks[k]
		out.append([int(net["a"]), int(net["b"]), int(net["cells"]), int(net["inf"]), int(net.get("turned", 0))])
	return out


static func networks_from_list(state: GameState, rows: Array) -> void:
	for row in rows:
		if not row is Array or row.size() < 4:
			continue
		var a := int(row[0])
		var b := int(row[1])
		state.networks[key(a, b)] = {"a": a, "b": b, "cells": int(row[2]), "inf": int(row[3])}
		if row.size() >= 5 and int(row[4]) == 1:
			state.networks[key(a, b)]["turned"] = 1
