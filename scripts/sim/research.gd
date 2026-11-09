class_name Research
extends RefCounted
## La recherche : fonctions pures qui LISENT l'état (data/technologies.json).
## EconomySystem fait avancer la file au bilan mensuel, SimCommands valide les ordres, et l'interface
## affiche les mêmes coûts et les mêmes refus.
##
## - Quatre domaines (armement, génie, économie, société) sur cinq ères. Une ère s'ouvre dans un
##   domaine quand on y connaît assez de technologies de l'ère précédente (era_thresholds).
## - Une seule ressource, le Savoir, produite par la population et les bâtiments de recherche.
##   Il s'accumule dans le stock ; chaque mois, la technologie en tête de file en consomme
##   jusqu'à deux fois le revenu (spend_rate_pct).
## - Le coût monte avec chaque technologie connue et avec la taille de l'empire.
## - Une technologie peut demander des couches d'espèce (requires.species), être interdite à
##   certaines (forbidden), en remplacer une commune (replaces) ou être hérétique (heretic : plus
##   chère et coûteuse en ferveur). Tout passe par FactionTraits.species_matches, pour que les
##   peuples personnalisés de l'éditeur y aient droit aussi.
##
## Effets des technologies (champ effects, effects_exalted pendant l'Exaltation) : voir aggregate().

const MAX_QUEUE := 12


static func data() -> Dictionary:
	return GameData.technologies()


static func tech(id: String) -> Dictionary:
	return data().get("technologies", {}).get(id, {})


static func exists(id: String) -> bool:
	return data().get("technologies", {}).has(id)


static func domain_ids() -> Array[String]:
	var out: Array[String] = []
	for d: Dictionary in data().get("domains", []):
		out.append(String(d["id"]))
	return out


static func domain(id: String) -> Dictionary:
	for d: Dictionary in data().get("domains", []):
		if d["id"] == id:
			return d
	return {}


static func eras() -> int:
	return int(data().get("eras", 5))


# --- Technologies d'un peuple -------------------------------------------------------------------

static var _visible_cache := {}


## Technologies de l'arbre d'une faction (toutes visibles dès le début), dans l'ordre des données.
static func visible_ids(faction: Dictionary) -> Array[String]:
	var key := String(faction.get("id", ""))
	if _visible_cache.has(key):
		return _visible_cache[key]
	var techs: Dictionary = data().get("technologies", {})
	var out: Array[String] = []
	var replaced := {}
	for tid in techs:
		var t: Dictionary = techs[tid]
		if not FactionTraits.species_matches(faction, t.get("requires", {}).get("species", {})):
			continue
		var forbid: Dictionary = t.get("forbidden", {}).get("species", {})
		if not forbid.is_empty() and FactionTraits.species_matches(faction, forbid):
			continue
		if t.has("replaces"):
			replaced[String(t["replaces"])] = String(tid)
		out.append(String(tid))
	var kept: Array[String] = []
	for tid in out:
		if not replaced.has(tid):
			kept.append(tid)
	_visible_cache[key] = kept
	return kept


static func is_visible(faction: Dictionary, tid: String) -> bool:
	return visible_ids(faction).has(tid)


## La technologie commune que celle-ci remplace pour ce peuple ("" si aucune).
static func replaced_by(faction: Dictionary, tid: String) -> String:
	for v in visible_ids(faction):
		if String(tech(v).get("replaces", "")) == tid:
			return v
	return ""


## Une technologie qui en remplace une autre compte comme elle pour les prérequis.
static func _satisfies(faction: Dictionary, have: Dictionary, pre: String) -> bool:
	if have.has(pre):
		return true
	var alt := replaced_by(faction, pre)
	return alt != "" and have.has(alt)


static func is_heretic(faction: Dictionary, tid: String) -> bool:
	var h: Dictionary = tech(tid).get("heretic", {})
	return not h.is_empty() and FactionTraits.species_matches(faction, h.get("species", {}))


## Propre à un peuple (demande des couches d'espèce).
static func is_specific(tid: String) -> bool:
	return tech(tid).has("requires")


## Ce que la technologie débloque pour ce peuple : bâtiments et classes de vaisseaux (libellés).
static func unlocks(faction: Dictionary, tid: String) -> PackedStringArray:
	var out := PackedStringArray()
	for bid in GameData.buildings():
		if GameData.building(bid).get("requires_tech", []).has(tid):
			out.append(String(GameData.building(bid).get("label", bid)))
	for sid in FactionTraits.ship_ids_for(String(faction.get("id", ""))):
		if GameData.ship(sid).get("requires_tech", []).has(tid):
			out.append(String(GameData.ship(sid).get("label", sid)))
	return out


static func knows(state: GameState, empire_id: int, tid: String) -> bool:
	var e := state.get_empire(empire_id)
	return e != null and e.techs.has(tid)


## L'empire connaît-il toutes ces technologies ? Pour débloquer un bâtiment ou un vaisseau, il faut
## la technologie exacte : une variante de peuple débloque son propre bâtiment (Scriptorium à la place
## de l'Académie), pas celui de la technologie qu'elle remplace.
static func knows_all(state: GameState, empire_id: int, tids: Array) -> bool:
	var e := state.get_empire(empire_id)
	if e == null:
		return tids.is_empty()
	for t in tids:
		if not e.techs.has(String(t)):
			return false
	return true


## Libellés des technologies manquantes d'une liste ("" si rien ne manque).
static func missing_text(state: GameState, empire_id: int, tids: Array) -> String:
	var e := state.get_empire(empire_id)
	var parts := PackedStringArray()
	for t in tids:
		if e == null or not e.techs.has(String(t)):
			parts.append(String(tech(String(t)).get("label", t)))
	return ", ".join(parts)


# --- Ères ---------------------------------------------------------------------------------------

## Nombre de technologies d'une ère, dans un domaine, parmi celles de `have`.
static func count_in(have: Dictionary, domain_id: String, era: int) -> int:
	var n := 0
	for tid in have:
		var t := tech(String(tid))
		if String(t.get("domain", "")) == domain_id and int(t.get("era", 0)) == era:
			n += 1
	return n


static func era_threshold(era: int) -> int:
	var th: Array = data().get("era_thresholds", [])
	return int(th[era - 1]) if era >= 1 and era <= th.size() else 0


## Une ère est ouverte dans un domaine si l'on y connaît assez de technologies de l'ère précédente.
static func era_open(have: Dictionary, domain_id: String, era: int) -> bool:
	if era <= 1:
		return true
	return count_in(have, domain_id, era - 1) >= era_threshold(era)


## Ère la plus avancée ouverte dans au moins un domaine.
static func current_era(state: GameState, empire_id: int) -> int:
	var e := state.get_empire(empire_id)
	if e == null:
		return 1
	var best := 1
	for d in domain_ids():
		for era in range(2, eras() + 1):
			if era_open(e.techs, d, era):
				best = maxi(best, era)
	return best


# --- Coûts --------------------------------------------------------------------------------------

## Coût en Savoir d'une technologie pour un empire, à cet instant.
@warning_ignore("integer_division")
static func cost(state: GameState, empire_id: int, tid: String) -> int:
	var d := data()
	var t := tech(tid)
	var e := state.get_empire(empire_id)
	var era := clampi(int(t.get("era", 1)), 1, eras())
	var c := int(d["base_cost"][era - 1]) * int(d.get("cost_scale_pct", 100)) / 100
	var known := e.techs.size() if e else 0
	c = c * (1000 + int(d.get("per_known_permille", 0)) * known) / 1000
	var extra := maxi(0, colony_count(state, empire_id) - int(d.get("free_colonies", 0))) * int(d.get("per_colony_pct", 0))
	c = c * (100 + extra) / 100
	if e:
		var f := e.faction()
		var rs: Dictionary = f.get("research", {})
		c = c * int(rs.get("domain_cost_pct", {}).get(String(t.get("domain", "")), 100)) / 100
		for tag in t.get("tags", []):
			c = c * int(rs.get("tag_cost_pct", {}).get(String(tag), 100)) / 100
		if is_heretic(f, tid):
			c = c * int(t["heretic"].get("cost_pct", 100)) / 100
	return maxi(1, c)


static func colony_count(state: GameState, empire_id: int) -> int:
	var n := 0
	for pid in state.colonies:
		var c: Colony = state.colonies[pid]
		if c.owner == empire_id and c.is_colony() and c.is_established():
			n += 1
	return n


## Savoir dépensable ce mois-ci : jusqu'à spend_rate_pct du revenu, dans la limite du stock. Une
## réserve accumulée (épaves, biomasse, file restée vide) s'écoule aussi, un douzième par mois au moins.
@warning_ignore("integer_division")
static func monthly_budget(stock: int, income: int) -> int:
	var cap := maxi(maxi(income, 5), stock / 12) * int(data().get("spend_rate_pct", 200)) / 100
	return clampi(stock, 0, cap)


## Mois restants estimés avant la fin de la technologie en tête de file (-1 si le Savoir ne vient pas).
static func months_left(state: GameState, empire_id: int, tid: String, income: int) -> int:
	var e := state.get_empire(empire_id)
	if e == null:
		return -1
	var left := cost(state, empire_id, tid) - (e.research_progress if not e.research_queue.is_empty() and e.research_queue[0] == tid else 0)
	if left <= 0:
		return 0
	if income <= 0:
		return -1
	@warning_ignore("integer_division")
	return (left + income - 1) / income


# --- Ordres -------------------------------------------------------------------------------------

## "" si l'empire peut mettre cette technologie en file, sinon la raison du refus.
## Les prérequis et les seuils d'ère comptent ce qui est déjà en file (on peut planifier une chaîne).
static func check_queue(state: GameState, empire_id: int, tid: String, front := false) -> String:
	var e := state.get_empire(empire_id)
	if e == null:
		return "empire inconnu : %d" % empire_id
	if not exists(tid):
		return "technologie inconnue : %s" % tid
	var f := e.faction()
	if not is_visible(f, tid):
		return "cette technologie n'est pas pour votre peuple"
	if e.techs.has(tid):
		return "déjà découverte"
	if e.research_queue.has(tid):
		if not front:
			return "déjà dans la file"
		if e.research_queue[0] == tid:
			return "déjà la recherche en cours"
		return ""  # passer devant : déjà validée quand elle est entrée dans la file
	if e.research_queue.size() >= MAX_QUEUE:
		return "la file est pleine (%d technologies)" % MAX_QUEUE
	var planned := e.techs.duplicate()
	for q in e.research_queue:
		planned[q] = true
	var t := tech(tid)
	var missing := PackedStringArray()
	for p in t.get("pre", []):
		if not _satisfies(f, planned, String(p)):
			var shown := replaced_by(f, String(p))
			missing.append(String(tech(shown if shown != "" else String(p)).get("label", p)))
	if not missing.is_empty():
		return "il faut d'abord : %s" % ", ".join(missing)
	var era := int(t.get("era", 1))
	if not era_open(planned, String(t["domain"]), era):
		return "ère %d fermée en %s : il faut %d technologies de l'ère %d (%d)" % [
				era, String(domain(String(t["domain"])).get("label", t["domain"])), era_threshold(era), era - 1,
				count_in(planned, String(t["domain"]), era - 1)]
	return ""


## Une technologie peut-elle être recherchée tout de suite (prérequis et ère, sans compter la file) ?
static func is_available(state: GameState, empire_id: int, tid: String) -> bool:
	var e := state.get_empire(empire_id)
	if e == null or e.techs.has(tid) or not is_visible(e.faction(), tid):
		return false
	var t := tech(tid)
	for p in t.get("pre", []):
		if not _satisfies(e.faction(), e.techs, String(p)):
			return false
	return era_open(e.techs, String(t["domain"]), int(t.get("era", 1)))


static func check_remove(state: GameState, empire_id: int, tid: String) -> String:
	var e := state.get_empire(empire_id)
	if e == null:
		return "empire inconnu : %d" % empire_id
	if not e.research_queue.has(tid):
		return "pas dans la file"
	return ""


## Ajoute une technologie à la file (en tête si front : elle devient la recherche en cours).
## Le Savoir déjà investi dans une recherche interrompue est mis de côté (research_shelf) et
## retrouvé quand on y revient.
static func apply_queue(state: GameState, empire_id: int, tid: String, front: bool) -> void:
	var e := state.get_empire(empire_id)
	if front and e.research_queue.has(tid):
		e.research_queue.erase(tid)
	if front and not e.research_queue.is_empty():
		# Changer de recherche en cours : le travail entamé est mis de côté, pas perdu.
		if e.research_progress > 0:
			e.research_shelf[e.research_queue[0]] = e.research_progress
		e.research_queue.insert(0, tid)
		_fix_order(e)  # ses prérequis encore en file passent devant elle
		e.research_progress = int(e.research_shelf.get(e.research_queue[0], 0))
		e.research_shelf.erase(e.research_queue[0])
	else:
		e.research_queue.append(tid)
		if e.research_queue.size() == 1:
			e.research_progress = int(e.research_shelf.get(tid, 0))
			e.research_shelf.erase(tid)


## Retire une technologie de la file, et celles qui en dépendaient.
static func apply_remove(state: GameState, empire_id: int, tid: String) -> void:
	var e := state.get_empire(empire_id)
	var was_first := not e.research_queue.is_empty() and e.research_queue[0] == tid
	if was_first and e.research_progress > 0:
		e.research_shelf[tid] = e.research_progress
	e.research_queue.erase(tid)
	# Ce qui dépendait d'elle (prérequis ou seuil d'ère) quitte la file aussi.
	var changed := true
	while changed:
		changed = false
		var planned := e.techs.duplicate()
		var keep: Array[String] = []
		for q in e.research_queue:
			if _plannable(e, planned, q):
				planned[q] = true
				keep.append(q)
			else:
				changed = true
		e.research_queue = keep
	if was_first:
		e.research_progress = 0
		if not e.research_queue.is_empty():
			e.research_progress = int(e.research_shelf.get(e.research_queue[0], 0))
			e.research_shelf.erase(e.research_queue[0])


static func _plannable(e: Empire, planned: Dictionary, tid: String) -> bool:
	var t := tech(tid)
	for p in t.get("pre", []):
		if not _satisfies(e.faction(), planned, String(p)):
			return false
	return era_open(planned, String(t["domain"]), int(t.get("era", 1)))


## Après une insertion en tête, remet en ordre la file pour que chaque technologie suive ses prérequis.
static func _fix_order(e: Empire) -> void:
	var planned := e.techs.duplicate()
	var rest: Array[String] = e.research_queue.duplicate()
	var out: Array[String] = []
	var guard := 0
	while not rest.is_empty() and guard < 64:
		guard += 1
		var placed := false
		for q in rest:
			if _plannable(e, planned, q):
				out.append(q)
				planned[q] = true
				rest.erase(q)
				placed = true
				break
		if not placed:
			break
	e.research_queue = out


# --- Avancée mensuelle --------------------------------------------------------------------------

## Fait avancer la recherche d'un empire au bilan mensuel. `income` = Savoir net du mois.
## Renvoie les technologies achevées.
static func advance(state: GameState, empire_id: int, income: int) -> Array[String]:
	var done: Array[String] = []
	var e := state.get_empire(empire_id)
	if e == null or e.research_queue.is_empty():
		return done
	var budget := monthly_budget(int(e.resources.get("knowledge", 0)), income)
	while budget > 0 and not e.research_queue.is_empty():
		var tid := e.research_queue[0]
		var need := cost(state, empire_id, tid) - e.research_progress
		var spend := mini(budget, maxi(0, need))
		e.research_progress += spend
		e.resources["knowledge"] = int(e.resources.get("knowledge", 0)) - spend
		budget -= spend
		if e.research_progress < cost(state, empire_id, tid):
			break
		complete(state, empire_id, tid)
		done.append(tid)
	return done


## Découvre une technologie (fin de recherche, épave, ou test) : effets ponctuels compris.
static func complete(state: GameState, empire_id: int, tid: String) -> void:
	var e := state.get_empire(empire_id)
	if e == null or e.techs.has(tid):
		return
	e.techs[tid] = true
	if not e.research_queue.is_empty() and e.research_queue[0] == tid:
		e.research_queue.remove_at(0)
		e.research_progress = 0
		if not e.research_queue.is_empty():
			e.research_progress = int(e.research_shelf.get(e.research_queue[0], 0))
			e.research_shelf.erase(e.research_queue[0])
	else:
		e.research_queue.erase(tid)
	e.research_shelf.erase(tid)
	var f := e.faction()
	if FactionTraits.has_fervor(f):
		var t := tech(tid)
		var gain := int(t.get("fervor", 0))
		gain += int(f.get("research", {}).get("fervor_per_domain", {}).get(String(t.get("domain", "")), 0))
		if is_heretic(f, tid):
			gain += int(t["heretic"].get("fervor", 0))
		e.fervor = clampi(e.fervor + gain, 0, int(f["fervor"]["max"]))
	e.tech_fx_n = -1


## Accorde des technologies sans les rechercher (scénarios, tests, IA de démonstration).
static func grant(state: GameState, empire_id: int, tids: Array) -> void:
	for t in tids:
		complete(state, empire_id, String(t))


## Accorde à un empire toutes les technologies de son arbre (tests du contenu verrouillé).
static func grant_all(state: GameState, empire_id: int) -> void:
	var e := state.get_empire(empire_id)
	if e:
		grant(state, empire_id, visible_ids(e.faction()))


# --- Effets -------------------------------------------------------------------------------------

## Effets cumulés des technologies connues : les nombres s'additionnent, les tables aussi, clé par clé.
## Pendant l'Exaltation (Chœur Éternel), les effects_exalted s'ajoutent.
## Clés : production_pct {res|"all"} (« all » hors Savoir), growth_pct, colony_start_pop, max_projects,
## building_slots, building_cost_pct, hab_bonus {type|"all"}, hab_set {type}, weapon_pct {famille},
## damage_pct, defense_pct {armor, shield, pd}, troops_pct, home_damage_pct, reinforcement_pct,
## garrison_pct, fleet_speed_pct, ship_days_pct, ship_cost_pct, upkeep_pct, claim_vision, alliances,
## fervor_big_colony, sacrifice_gain, fief_influence, biomass_bonus.
static func effects(state: GameState, empire_id: int) -> Dictionary:
	var e := state.get_empire(empire_id)
	if e == null:
		return {}
	if e.tech_fx_n != e.techs.size():
		var base := {}
		var exalted := {}
		var ids: Array = e.techs.keys()
		ids.sort()
		for tid in ids:
			var t := tech(String(tid))
			_merge(base, t.get("effects", {}))
			_merge(exalted, t.get("effects", {}))
			_merge(exalted, t.get("effects_exalted", {}))
		e.tech_fx = base
		e.tech_fx_exalted = exalted
		e.tech_fx_n = e.techs.size()
	return e.tech_fx_exalted if FactionTraits.is_exalted(state, empire_id) else e.tech_fx


static func _merge(into: Dictionary, fx: Dictionary) -> void:
	for k in fx:
		var v: Variant = fx[k]
		if v is Dictionary:
			var sub: Dictionary = into.get(k, {})
			for kk in v:
				sub[kk] = int(sub.get(kk, 0)) + int(v[kk])
			into[k] = sub
		else:
			into[k] = int(into.get(k, 0)) + int(v)


static func fx_int(state: GameState, empire_id: int, key: String) -> int:
	return int(effects(state, empire_id).get(key, 0))


static func fx_sub(state: GameState, empire_id: int, key: String, sub: String) -> int:
	return int(effects(state, empire_id).get(key, {}).get(sub, 0))


## Bonus de production d'une ressource, en points de pourcentage (« all » ne compte pas le Savoir).
static func production_bonus(state: GameState, empire_id: int, resource: String) -> int:
	var fx := effects(state, empire_id)
	var t: Dictionary = fx.get("production_pct", {})
	var b := int(t.get(resource, 0))
	if resource != "knowledge":
		b += int(t.get("all", 0))
	return b


## Applique un pourcentage de technologie (ex. ship_cost_pct = -10) à une valeur entière.
@warning_ignore("integer_division")
static func scaled(v: int, pct_bonus: int) -> int:
	return v * maxi(0, 100 + pct_bonus) / 100


static func scaled_amounts(amounts: Dictionary, pct_bonus: int) -> Dictionary:
	if pct_bonus == 0:
		return amounts
	var out := {}
	for r in amounts:
		out[r] = scaled(int(amounts[r]), pct_bonus)
	return out
