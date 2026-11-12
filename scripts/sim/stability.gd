class_name Stability
extends RefCounted
## Stabilité des systèmes (étude « Pirates et stabilité des colonies », 2026-11-12) : chaque système
## revendiqué a une stabilité de 0 à 100 (state.stability[sid]["v"]) qui glisse chaque mois vers sa
## cible, somme de sources affichées. Cinq paliers modulent la production ; un an de Révolte et le
## système fait sécession : il passe aux Sans-Bannière (GameState.NPC_ID), qui y lèvent des rebelles.
## Talents par couche d'espèce dans data/stability.json "talents". Tout en entiers, sans aléatoire.
##
## state.stability[sid] = {"v": stabilité, "revolt": jours de révolte, "hit": dernier jour attaqué,
##   "conq": jour de conquête, "decree": décret en vigueur, "decree_end": fin du décret,
##   "offer": dernière offrande, "wild": jours loin du nid (esprit de ruche)} ; clés absentes = défaut.
## state.stab_meta = {"loot": {empire: dernier pillage}}.

const LAYERS := ["archetype", "gouvernement", "credo"]

## Talents par fiche de peuple (pur : ne dépend que des données). Aucun autre cache : la simulation
## doit donner le même résultat qu'on reprenne une sauvegarde ou non.
static var _talent_cache := {}


static func data() -> Dictionary:
	return GameData.stability()


static func entry(state: GameState, sid: int) -> Dictionary:
	return state.stability.get(sid, {})


static func _entry_w(state: GameState, sid: int) -> Dictionary:
	if not state.stability.has(sid):
		state.stability[sid] = {"v": int(data()["base"])}
	return state.stability[sid]


# --- Talents -----------------------------------------------------------------------------------

## Talents de stabilité du peuple, couches d'espèce additionnées (les booléens restent vrais).
static func talent(state: GameState, empire_id: int) -> Dictionary:
	var e := state.get_empire(empire_id)
	if e == null or e.is_npc():
		return {}
	# Les talents ne dépendent que de la fiche du peuple : gardés tant qu'elle ne change pas.
	var ck := "%s:%d" % [e.faction_id, GameData.factions_gen]
	if _talent_cache.has(ck):
		return _talent_cache[ck]
	var out := {}
	var sp: Dictionary = e.faction().get("species", {})
	var table: Dictionary = data().get("talents", {})
	for layer in LAYERS:
		var t: Dictionary = (table.get(layer, {}) as Dictionary).get(String(sp.get(layer, "")), {})
		for k in t:
			if k == "label" or k == "text":
				continue
			var v: Variant = t[k]
			out[k] = v if v is bool else int(out.get(k, 0)) + int(v)
	_talent_cache[ck] = out
	return out


## Talents à afficher : [[nom, texte], …].
static func talent_labels(state: GameState, empire_id: int) -> Array:
	var e := state.get_empire(empire_id)
	var out := []
	if e == null or e.is_npc():
		return out
	var sp: Dictionary = e.faction().get("species", {})
	var table: Dictionary = data().get("talents", {})
	for layer in LAYERS:
		var t: Dictionary = (table.get(layer, {}) as Dictionary).get(String(sp.get(layer, "")), {})
		if not t.is_empty():
			out.append([String(t["label"]), String(t["text"])])
	return out


## Le peuple a-t-il une stabilité ? (l'esprit de ruche n'en a pas, ni les Sans-Bannière.)
static func applies(state: GameState, empire_id: int) -> bool:
	var e := state.get_empire(empire_id)
	return e != null and not e.is_npc() and not bool(talent(state, empire_id).get("no_stability", false))


# --- Paliers -----------------------------------------------------------------------------------

static func tiers() -> Array:
	return data()["tiers"]


static func tier_for(v: int) -> Dictionary:
	var best: Dictionary = tiers()[0]
	for t: Dictionary in tiers():
		if v >= int(t["min"]):
			best = t
	return best


## Stabilité actuelle d'un système (base si jamais calculée, 50 si le peuple n'en a pas).
static func value(state: GameState, sid: int) -> int:
	var owner := state.system_owner(sid)
	if owner < 0 or not applies(state, owner):
		return int(data()["base"])
	return int(entry(state, sid).get("v", int(data()["base"])))


static func tier(state: GameState, sid: int) -> Dictionary:
	return tier_for(value(state, sid))


static func tier_id(state: GameState, sid: int) -> String:
	return String(tier(state, sid)["id"])


static func tier_label(state: GameState, sid: int) -> String:
	return String(tier(state, sid)["label"])


static func tier_color(state: GameState, sid: int) -> Color:
	return Color.html(String(tier(state, sid).get("color", "#a9b4c2")))


## Bonus ou malus de production du système, en points de % (palier et loi martiale).
static func prod_pct(state: GameState, sid: int) -> int:
	var owner := state.system_owner(sid)
	if owner < 0 or not applies(state, owner):
		return 0
	var pct := int(tier(state, sid).get("prod_pct", 0))
	var d := active_decree(state, sid)
	if d != "":
		pct += int(decree_def(d).get("prod_pct", 0))
	return pct


## La population grandit-elle ? (pas en Agitation ni en Révolte.)
static func growth_ok(state: GameState, sid: int) -> bool:
	var owner := state.system_owner(sid)
	if owner < 0 or not applies(state, owner):
		return true
	return bool(tier(state, sid).get("growth", true))


## Chantiers gelés (Révolte).
static func frozen(state: GameState, sid: int) -> bool:
	var owner := state.system_owner(sid)
	if owner < 0 or not applies(state, owner):
		return false
	return bool(tier(state, sid).get("frozen", false))


## Le système ne produit plus d'influence (Concessions locales).
static func no_influence(state: GameState, sid: int) -> bool:
	var d := active_decree(state, sid)
	return d != "" and bool(decree_def(d).get("no_influence", false))


## Applique la stabilité au rendement d'une revendication (Economy.colony_yields).
static func adjust_yields(state: GameState, sid: int, gross: Dictionary) -> void:
	if state.stability.is_empty():
		return
	var pct := prod_pct(state, sid)
	if pct != 0:
		for r in gross:
			if int(gross[r]) > 0:
				@warning_ignore("integer_division")
				gross[r] = int(gross[r]) * maxi(0, 100 + pct) / 100
	if no_influence(state, sid):
		gross["influence"] = mini(0, int(gross.get("influence", 0)))


## Influence en plus des systèmes en Ferveur (Economy.empire_income) : comptée au bilan mensuel.
static func extra_influence(state: GameState, empire_id: int) -> int:
	return int((state.stab_meta.get("inf", {}) as Dictionary).get(empire_id, 0))


static func compute_extra_influence(state: GameState, empire_id: int) -> int:
	if not applies(state, empire_id):
		return 0
	var n := 0
	for sid in systems_of(state, empire_id):
		n += int(tier(state, sid).get("influence", 0))
	return n


## Bilan mensuel d'empire (StabilitySystem) : bonus de stabilité d'empire et influence de Ferveur.
static func refresh_empire(state: GameState, empire_id: int) -> void:
	for key in ["pct", "inf"]:
		if not state.stab_meta.has(key):
			state.stab_meta[key] = {}
	var p := compute_empire_pct(state, empire_id)
	var i := compute_extra_influence(state, empire_id)
	if p != 0:
		state.stab_meta["pct"][empire_id] = p
	else:
		state.stab_meta["pct"].erase(empire_id)
	if i != 0:
		state.stab_meta["inf"][empire_id] = i
	else:
		state.stab_meta["inf"].erase(empire_id)


# --- Systèmes d'un empire ----------------------------------------------------------------------

## Systèmes où l'empire a au moins une revendication établie, triés.
static func systems_of(state: GameState, empire_id: int) -> Array[int]:
	var seen := {}
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner == empire_id and c.is_established():
			seen[state.galaxy.get_planet(pid).system_id] = true
	var out: Array[int] = []
	for k in seen:
		out.append(int(k))
	out.sort()
	return out


## Systèmes avec au moins une colonie peuplée (surextension) : les avant-postes ne comptent pas.
static func colony_systems(state: GameState, empire_id: int) -> int:
	var seen := {}
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner == empire_id and c.is_colony() and c.is_established():
			seen[state.galaxy.get_planet(pid).system_id] = true
	return seen.size()


## Colonies peuplées de l'empire dans un système.
static func colony_systems_in(state: GameState, empire_id: int, sid: int) -> int:
	var n := 0
	for pid in state.galaxy.systems[sid].planet_ids:
		var c: Colony = state.colonies.get(pid)
		if c != null and c.owner == empire_id and c.is_colony() and c.is_established():
			n += 1
	return n


static func threshold(state: GameState, empire_id: int) -> int:
	return int(data()["sources"]["overextension"]["threshold"]) + Research.fx_int(state, empire_id, "stability_threshold")


static func system_pop(state: GameState, sid: int, owner: int) -> int:
	var n := 0
	for pid in state.galaxy.systems[sid].planet_ids:
		var c: Colony = state.colonies.get(pid)
		if c != null and c.owner == owner and c.is_colony() and c.is_established():
			n += c.population
	return n


# --- Sources -----------------------------------------------------------------------------------

## Contexte d'empire partagé par tous ses systèmes (sources globales, capitale, flottes armées).
## Calculé à la demande ; le bilan mensuel le calcule une fois par empire et le passe à parts().
static func context(state: GameState, empire_id: int) -> Dictionary:
	var e := state.get_empire(empire_id)
	var tal := talent(state, empire_id)
	var src: Dictionary = data()["sources"]
	var cap := FactionTraits.capital_system(state, empire_id)
	var c := {"talent": tal, "capital": cap, "jumps": FactionTraits.jumps_from(state.galaxy, cap) if cap >= 0 else {}}
	var global: Array = []
	# Surextension.
	var over := colony_systems(state, empire_id) - threshold(state, empire_id)
	if over > 0:
		var ov: Dictionary = src["overextension"]
		global.append(["Surextension (%d systèmes de trop)" % over, maxi(int(ov["max"]), over * int(ov["per_system"]))])
	# Pénuries.
	if (e.starving or e.blackout) and not bool(tal.get("no_shortage", false)):
		global.append(["Famine" if e.starving else "Pénurie d'énergie", int(src["shortage"])])
	# Lassitude de guerre : la plus longue guerre en cours.
	var longest := 0
	for w in e.wars:
		longest = maxi(longest, Diplomacy.pact_days(state, empire_id, int(w)))
	if longest > 0 and Laws.no_war_weariness(state, empire_id):
		pass
	elif longest > 0:
		var wd: Dictionary = src["war"]
		@warning_ignore("integer_division")
		var v := maxi(int(wd["max"]), longest / 90 * int(wd["per_quarter"])) * maxi(1, int(tal.get("war_x", 1)))
		if v != 0:
			global.append(["Lassitude de guerre", v])
	elif int(tal.get("peace", 0)) != 0 and state.tick >= int(tal.get("peace_days", 720)) \
			and _days_since_war(state, empire_id) >= int(tal.get("peace_days", 720)):
		global.append(["Paix durable", int(tal["peace"])])
	# Technologies.
	var tv := Research.fx_int(state, empire_id, "stability")
	if tv != 0:
		global.append(["Technologies", tv])
	# Ferveur (théocratie).
	if FactionTraits.has_fervor(e.faction()):
		if int(tal.get("exalted", 0)) != 0 and FactionTraits.is_exalted(state, empire_id):
			global.append(["Exaltation", int(tal["exalted"])])
		elif int(tal.get("silent", 0)) != 0 and e.fervor <= 0:
			global.append(["Le dieu se tait (ferveur à 0)", int(tal["silent"])])
	# Héritier déloyal (féodalité).
	if int(tal.get("heir_disloyal", 0)) != 0 and e.heir_loyalty >= 0 and e.heir_loyalty < int(tal.get("heir_below", 30)):
		global.append(["Héritier déloyal", int(tal["heir_disloyal"])])
	# Parjure (honneur).
	if int(tal.get("perjury", 0)) != 0:
		for m in state.memories:
			if int(m["about"]) == empire_id and String(m["kind"]) == "broke_treaty" \
					and state.tick - int(m["tick"]) < int(tal.get("perjury_days", 360)):
				global.append(["Parjure", int(tal["perjury"])])
				break
	# Accord commercial (profit).
	if int(tal.get("trade", 0)) != 0:
		for o in state.empires:
			if o.id != empire_id and not o.eliminated and Diplomacy.has_trade(state, empire_id, o.id):
				global.append(["Accord commercial", int(tal["trade"])])
				break
	# Butin (horde).
	if int(tal.get("loot_recent", 0)) != 0:
		var last := int((state.stab_meta.get("loot", {}) as Dictionary).get(empire_id, -100000))
		if state.tick - last <= int(tal.get("loot_days", 180)):
			global.append(["Butin récent", int(tal["loot_recent"])])
		elif state.tick >= int(tal.get("loot_none_days", 360)) and state.tick - last > int(tal.get("loot_none_days", 360)):
			global.append(["Les clans s'ennuient (pas de pillage)", int(tal.get("loot_none", 0))])
	# Pirates : scandale ou honte d'un tribut payé.
	global.append_array(Pirates.stability_parts(state, empire_id))
	# Contre-espionnage : un réseau chez soi tient les meneurs à l'œil.
	if not state.networks.is_empty() and Espionage.home_cells(state, empire_id) > 0:
		global.append(["Réseau intérieur (contre-espionnage)", int(src["counter_network"])])
	c["global"] = global
	# Flottes armées à l'arrêt, par système.
	var armed := {}
	for fid in state.sorted_fleet_ids():
		var f: Fleet = state.fleets[fid]
		if f.owner == empire_id and not f.is_moving() and Combat.is_armed(f):
			armed[f.system_id] = true
	c["armed"] = armed
	return c


## Jours depuis la fin de la dernière guerre de l'empire (depuis le début de la partie s'il n'en a pas eu).
static func _days_since_war(state: GameState, empire_id: int) -> int:
	var last := int((state.stab_meta.get("peace", {}) as Dictionary).get(empire_id, 0))
	return state.tick - last


## Sources de stabilité d'un système : [[libellé, valeur], …] (l'infobulle les liste toutes).
static func parts(state: GameState, sid: int, cx := {}) -> Array:
	var owner := state.system_owner(sid)
	var out := []
	if owner < 0 or not applies(state, owner):
		return out
	var src: Dictionary = data()["sources"]
	if cx.is_empty():
		cx = context(state, owner)
	var tal: Dictionary = cx["talent"]
	out.append(["Base", int(data()["base"])])
	var cap := int(cx["capital"])
	if sid == cap:
		out.append(["Capitale", int(src["capital"])])
	elif not bool(tal.get("no_distance", false)) and cap >= 0:
		var dd: Dictionary = src["distance"]
		var j := int((cx["jumps"] as Dictionary).get(sid, 99))
		if j > int(dd["free_jumps"]):
			out.append(["Distance à la capitale (%d sauts)" % j, maxi(int(dd["max"]), (j - int(dd["free_jumps"])) * int(dd["per_jump"]))])
	out.append_array(cx["global"])
	# Surpopulation, bâtiments.
	var op: Dictionary = src["overpop"]
	var crowd := 0
	var bld := 0
	var bsrc: Dictionary = src["buildings"]
	for pid in state.galaxy.systems[sid].planet_ids:
		var c: Colony = state.colonies.get(pid)
		if c == null or c.owner != owner or not c.is_established():
			continue
		for b in c.buildings:
			bld += int(bsrc.get(b, 0))
		if c.is_colony() and not bool(tal.get("no_overpop", false)):
			var mx := Economy.max_pop(state, state.galaxy.get_planet(pid), owner, c.buildings)
			@warning_ignore("integer_division")
			var limit := mx * int(op["from_pct"]) / 100
			if mx > 0 and c.population > limit:
				crowd += c.population - limit
	if crowd > 0:
		out.append(["Surpopulation", maxi(int(op["max"]), crowd * int(op["per_pop"]))])
	if bld != 0:
		out.append(["Bâtiments (forum, préfecture…)", bld])
	# Garnison.
	if (cx["armed"] as Dictionary).has(sid):
		out.append(["Flotte armée en orbite", int(src["garrison"])])
	# Intendant.
	if not state.heroes.is_empty():
		var h := Heroes.at_post(state, "system", sid, owner)
		if not h.is_empty():
			var it: Dictionary = src["intendant"]
			@warning_ignore("integer_division")
			out.append(["Gouverneur : %s" % String(h["name"]), int(it["base"]) + int(it["per_level"]) * Heroes.half_levels(h, "system") / 2])
	var en := entry(state, sid)
	# Attaque récente.
	var at: Dictionary = src["attacked"]
	if en.has("hit") and state.tick - int(en["hit"]) < int(at["days"]):
		out.append(["Attaqué récemment", int(at["value"])])
	# Monde conquis, qui s'efface.
	var cq: Dictionary = src["conquered"]
	if en.has("conq"):
		var age := state.tick - int(en["conq"])
		if age < int(cq["days"]):
			@warning_ignore("integer_division")
			var v := int(cq["value"]) * (int(cq["days"]) - age) / int(cq["days"]) * maxi(1, int(tal.get("conquered_x", 1)))
			if v != 0:
				out.append(["Monde conquis", v])
	# Agitation semée par des espions étrangers.
	if en.has("agit") and state.tick < int(en["agit"]):
		out.append(["Agitateurs étrangers", int(src["agitation"]["value"])])
	# Dissidence des fiefs lointains (féodalité).
	if int(tal.get("dissent", 0)) != 0 and state.get_empire(owner).dissent and _far_fief_system(state, owner, sid):
		out.append(["Dissidence des fiefs", int(tal["dissent"])])
	# Nœud voisin en révolte (conscience distribuée).
	if int(tal.get("revolt_neighbors", 0)) != 0:
		for n in state.galaxy.systems[sid].neighbors:
			if state.system_owner(n) == owner and int(entry(state, n).get("v", 50)) < int(tiers()[1]["min"]):
				out.append(["Nœud voisin en révolte", int(tal["revolt_neighbors"])])
				break
	# Suite d'un événement (voir Events).
	if en.has("ev_end") and state.tick < int(en["ev_end"]):
		out.append([String(Events.card(String(en.get("ev_card", ""))).get("title", "Événement")), int(en.get("ev", 0))])
	# Représentation au pouvoir (voir Politics).
	if state.politics_on:
		var rp := Politics.stability_part(state, sid, owner)
		if not rp.is_empty() and int(rp[1]) != 0:
			out.append(rp)
		out.append_array(Laws.stability_parts(state, sid, owner))
	# Décret.
	var d := active_decree(state, sid)
	if d != "":
		out.append([String(decree_def(d)["label"]), int(decree_def(d).get("stability", 0))])
	return out


static func _far_fief_system(state: GameState, owner: int, sid: int) -> bool:
	for pid in state.galaxy.systems[sid].planet_ids:
		var c: Colony = state.colonies.get(pid)
		if c != null and c.owner == owner and FactionTraits.is_far_fief(state, c):
			return true
	return false


## Système le moins stable de l'empire (le plus petit identifiant à égalité), -1 si aucun.
## skip_capital : hors capitale ; below : seulement sous cette valeur (0 = sans limite).
static func least_stable(state: GameState, empire_id: int, skip_capital: bool, below := 0) -> int:
	if not applies(state, empire_id):
		return -1
	var cap := FactionTraits.capital_system(state, empire_id)
	var best := -1
	var best_v := 1000
	for sid in systems_of(state, empire_id):
		if skip_capital and sid == cap:
			continue
		var v := value(state, sid)
		if (below <= 0 or v < below) and v < best_v:
			best = sid
			best_v = v
	return best


## Agitateurs étrangers (opération Attiser la dissidence) : malus de stabilité pendant un an.
static func agitate(state: GameState, sid: int) -> void:
	_entry_w(state, sid)["agit"] = state.tick + int(data()["sources"]["agitation"]["days"])


## Cible vers laquelle glisse la stabilité du système.
static func target(state: GameState, sid: int, cx := {}) -> int:
	var t := 0
	for p in parts(state, sid, cx):
		t += int(p[1])
	return clampi(t, 0, 100)


## Stabilité d'empire : moyenne des systèmes pondérée par la population (50 sans colonie).
static func empire_value(state: GameState, empire_id: int) -> int:
	if not applies(state, empire_id):
		return int(data()["base"])
	var tot := 0
	var w := 0
	for sid in systems_of(state, empire_id):
		var p := maxi(1, system_pop(state, sid, empire_id))
		tot += value(state, sid) * p
		w += p
	if w == 0:
		return int(data()["base"])
	@warning_ignore("integer_division")
	return tot / w


## Bonus de Savoir et d'influence de la stabilité d'empire, en points de % : fixé au bilan mensuel
## (StabilitySystem, gardé dans state.stab_meta["pct"]), pour que l'économie reste légère.
static func empire_pct(state: GameState, empire_id: int) -> int:
	return int((state.stab_meta.get("pct", {}) as Dictionary).get(empire_id, 0))


static func compute_empire_pct(state: GameState, empire_id: int) -> int:
	if not applies(state, empire_id):
		return 0
	var ed: Dictionary = data()["empire"]
	@warning_ignore("integer_division")
	return clampi((empire_value(state, empire_id) - int(data()["base"])) * int(ed["pct_per_point"]) / 100, -int(ed["max_pct"]), int(ed["max_pct"]))


# --- Décrets -----------------------------------------------------------------------------------

static func decree_ids() -> Array:
	var ids: Array = data()["decrees"].keys()
	ids.sort()
	return ids


static func decree_def(id: String) -> Dictionary:
	return data()["decrees"].get(id, {})


static func active_decree(state: GameState, sid: int) -> String:
	var en := entry(state, sid)
	if String(en.get("decree", "")) != "" and int(en.get("decree_end", 0)) > state.tick:
		return String(en["decree"])
	return ""


static func decree_cost(state: GameState, empire_id: int, id: String) -> Dictionary:
	var cost: Dictionary = (decree_def(id).get("cost", {}) as Dictionary).duplicate()
	if id == "fetes":
		var pct := int(talent(state, empire_id).get("fetes_pct", 100))
		if pct != 100:
			for r in cost:
				@warning_ignore("integer_division")
				cost[r] = int(cost[r]) * pct / 100
	return cost


static func check_decree(state: GameState, empire_id: int, sid: int, id: String) -> String:
	if decree_def(id).is_empty():
		return "décret inconnu"
	if sid < 0 or sid >= state.galaxy.systems.size() or state.system_owner(sid) != empire_id:
		return "ce système ne vous appartient pas"
	if not applies(state, empire_id):
		return "votre peuple ne connaît pas la dissidence"
	if active_decree(state, sid) != "":
		return "un décret est déjà en vigueur ici"
	if bool(decree_def(id).get("needs_fleet", false)) and not _armed_at(state, empire_id, sid):
		return "il faut une flotte armée à l'arrêt dans le système"
	if not Economy.can_afford(state.get_empire(empire_id), decree_cost(state, empire_id, id)):
		return "pas assez de ressources (%s)" % GameData.format_amounts(decree_cost(state, empire_id, id))
	return ""


static func _armed_at(state: GameState, empire_id: int, sid: int) -> bool:
	for f in Fleets.fleets_at(state, sid, empire_id):
		if Combat.is_armed(f):
			return true
	return false


static func decree(state: GameState, empire_id: int, sid: int, id: String) -> void:
	Economy.pay(state.get_empire(empire_id), decree_cost(state, empire_id, id))
	var en := _entry_w(state, sid)
	en["decree"] = id
	en["decree_end"] = state.tick + int(decree_def(id).get("days", 180))


# --- Offrande (théocratie) ---------------------------------------------------------------------

static func check_offering(state: GameState, empire_id: int, sid: int) -> String:
	if not bool(talent(state, empire_id).get("offering", false)) or not FactionTraits.has_fervor(state.get_empire(empire_id).faction()):
		return "seule une théocratie fait cette offrande"
	if sid < 0 or sid >= state.galaxy.systems.size() or state.system_owner(sid) != empire_id:
		return "ce système ne vous appartient pas"
	var od: Dictionary = data()["offering"]
	var en := entry(state, sid)
	if en.has("offer") and state.tick - int(en["offer"]) < int(od["cooldown_days"]):
		return "une offrande a déjà été faite ici il y a moins de 6 mois"
	if value(state, sid) + int(od["stability"]) < 0:
		return "il ne reste plus rien à offrir ici"
	return ""


static func offering(state: GameState, empire_id: int, sid: int) -> void:
	var od: Dictionary = data()["offering"]
	var e := state.get_empire(empire_id)
	var en := _entry_w(state, sid)
	en["v"] = clampi(int(en.get("v", data()["base"])) + int(od["stability"]), 0, 100)
	en["offer"] = state.tick
	e.fervor = mini(int(e.faction()["fervor"]["max"]), e.fervor + int(od["fervor"]))


# --- Réintégration des mondes libres ------------------------------------------------------------

static func reintegrate_cost(state: GameState, sid: int) -> Dictionary:
	var rd: Dictionary = data()["reintegrate"]
	var n := 0
	for pid in state.galaxy.systems[sid].planet_ids:
		var c: Colony = state.colonies.get(pid)
		if c != null and c.owner == GameState.NPC_ID:
			n += 1
	return {"influence": int(rd["cost_base"]) + int(rd["cost_per_planet"]) * n}


static func check_reintegrate(state: GameState, empire_id: int, sid: int) -> String:
	if sid < 0 or sid >= state.galaxy.systems.size() or state.system_owner(sid) != GameState.NPC_ID:
		return "ce n'est pas un monde libre"
	if not applies(state, empire_id):
		return "votre peuple ne sait pas convaincre, seulement prendre"
	var touches := false
	for n in state.galaxy.systems[sid].neighbors:
		if state.system_owner(n) == empire_id:
			touches = true
	if not touches:
		return "ce monde libre ne touche pas votre territoire"
	var need := int(data()["reintegrate"]["min_empire"])
	if empire_value(state, empire_id) < need:
		return "votre stabilité d'empire doit être d'au moins %d (elle est de %d)" % [need, empire_value(state, empire_id)]
	for f in Fleets.fleets_at(state, sid, GameState.NPC_ID):
		if Combat.is_armed(f):
			return "des rebelles armés tiennent encore l'orbite"
	if not Economy.can_afford(state.get_empire(empire_id), reintegrate_cost(state, sid)):
		return "pas assez d'influence (%s)" % GameData.format_amounts(reintegrate_cost(state, sid))
	return ""


static func reintegrate(state: GameState, empire_id: int, sid: int) -> Array[Dictionary]:
	Economy.pay(state.get_empire(empire_id), reintegrate_cost(state, sid))
	_transfer(state, sid, GameState.NPC_ID, empire_id)
	var en := _entry_w(state, sid)
	en["v"] = 40
	en["revolt"] = 0
	var e := state.get_empire(empire_id)
	return [state.add_chronicle("%s rentre dans le giron de %s. On rend les drapeaux, on garde les rancœurs pour plus tard." % [
			state.galaxy.systems[sid].system_name, e.display_name()], Espionage.private_to(state, [empire_id], sid))]


## Les revendications d'un propriétaire dans un système passent à un autre (sécession, retour).
static func _transfer(state: GameState, sid: int, from: int, to: int) -> void:
	for pid in state.galaxy.systems[sid].planet_ids:
		var c: Colony = state.colonies.get(pid)
		if c == null or c.owner != from:
			continue
		c.owner = to
		c.construction = ""
		c.construction_days = 0
		c.ship_build = ""
		c.ship_days = 0
		c.growth = 0
	state.rebuild_ownership()
	state.garrisons.erase(sid)
	state.sieges.erase(sid)


# --- Crochets ----------------------------------------------------------------------------------

## Système pris par la force (Combat.capture_system) : souvenir de conquête, plus de décret.
static func on_capture(state: GameState, sid: int) -> void:
	var en := _entry_w(state, sid)
	en["conq"] = state.tick
	en["revolt"] = 0
	en.erase("decree")
	en.erase("decree_end")
	en["v"] = mini(int(en.get("v", data()["base"])), int(data()["base"]))


## Pillage d'une horde (EconomySystem) : les clans s'en souviennent.
static func on_loot(state: GameState, empire_id: int) -> void:
	_meta_set(state, "loot", empire_id)


## Fin d'une guerre (Diplomacy.end_war) : la paix durable se compte à partir de là.
static func on_peace(state: GameState, a: int, b: int) -> void:
	_meta_set(state, "peace", a)
	_meta_set(state, "peace", b)


static func _meta_set(state: GameState, key: String, empire_id: int) -> void:
	if not state.stab_meta.has(key):
		state.stab_meta[key] = {}
	state.stab_meta[key][empire_id] = state.tick


# --- Sauvegarde --------------------------------------------------------------------------------

static func to_list(state: GameState) -> Array:
	var ids := state.stability.keys()
	ids.sort()
	var out := []
	for k in ids:
		var d: Dictionary = (state.stability[k] as Dictionary).duplicate()
		d["sid"] = int(k)
		out.append(d)
	return out


static func from_list(list: Array) -> Dictionary:
	var out := {}
	for d0 in list:
		var d: Dictionary = GameData._to_ints(d0)
		var sid := int(d["sid"])
		d.erase("sid")
		out[sid] = d
	return out


static func meta_to_dict(state: GameState) -> Dictionary:
	var out := {}
	for key in ["loot", "peace", "pct", "inf"]:
		var lst := []
		var lm: Dictionary = state.stab_meta.get(key, {})
		var ks := lm.keys()
		ks.sort()
		for k in ks:
			lst.append([int(k), int(lm[k])])
		out[key] = lst
	return out


static func meta_from_dict(d: Dictionary) -> Dictionary:
	var out := {}
	for key in ["loot", "peace", "pct", "inf"]:
		var lm := {}
		for p in d.get(key, []):
			lm[int(p[0])] = int(p[1])
		if not lm.is_empty():
			out[key] = lm
	return out
