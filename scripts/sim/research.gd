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
## Par peuple : technologie commune remplacée -> technologie du peuple qui la remplace.
static var _replaced_cache := {}


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
	var repl := {}
	for tid in kept:
		if techs[tid].has("replaces"):
			repl[String(techs[tid]["replaces"])] = tid
	_replaced_cache[key] = repl
	_visible_cache[key] = kept
	return kept


static func is_visible(faction: Dictionary, tid: String) -> bool:
	return visible_ids(faction).has(tid)


## La technologie commune que celle-ci remplace pour ce peuple ("" si aucune).
static func replaced_by(faction: Dictionary, tid: String) -> String:
	visible_ids(faction)
	return String(_replaced_cache[String(faction.get("id", ""))].get(tid, ""))


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


## Ce que la technologie débloque pour ce peuple : bâtiments, classes de vaisseaux, coques et modules
## du Chantier (libellés).
static func unlocks(faction: Dictionary, tid: String) -> PackedStringArray:
	var out := PackedStringArray()
	for bid in GameData.buildings():
		if GameData.building(bid).get("requires_tech", []).has(tid):
			out.append(String(GameData.building(bid).get("label", bid)))
	for sid in FactionTraits.ship_ids_for(String(faction.get("id", ""))):
		if GameData.ship(sid).get("requires_tech", []).has(tid):
			out.append(String(GameData.ship(sid).get("label", sid)))
	for hid in Designs.hull_ids_for(String(faction.get("id", ""))):
		var h := Designs.hull(hid)
		if h.get("requires_tech", []).has(tid) and not out.has(String(h.get("label", hid))):
			out.append("coque %s" % String(h.get("label", hid)))
	for mid in Designs.module_ids():
		var m := Designs.module(mid)
		if m.get("requires_tech", []).has(tid) and Designs.module_allowed_for(mid, faction):
			out.append("module %s" % String(m.get("label", mid)))
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
## colonies : nombre de colonies fondées s'il est déjà connu (l'IA qui compare toutes les technologies).
static func cost(state: GameState, empire_id: int, tid: String, colonies := -1) -> int:
	var d := data()
	var t := tech(tid)
	var e := state.get_empire(empire_id)
	var era := clampi(int(t.get("era", 1)), 1, eras())
	var c := int(d["base_cost"][era - 1]) * int(d.get("cost_scale_pct", 100)) / 100
	var known := e.techs.size() if e else 0
	c = c * (1000 + int(d.get("per_known_permille", 0)) * known) / 1000
	if colonies < 0:
		colonies = colony_count(state, empire_id)
	var extra := maxi(0, colonies - int(d.get("free_colonies", 0))) * int(d.get("per_colony_pct", 0))
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
	var other := String(t.get("exclusive", ""))
	if other != "" and planned.has(other):
		return "doctrine fermée : vous avez choisi « %s » (définitif ; celle-ci ne s'obtient plus que par les épaves)" % \
				String(tech(other).get("label", other))
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


# --- Marques d'armes et de défenses -------------------------------------------------------------

## Familles à marques (6 armes, 3 défenses), dans l'ordre d'affichage.
static func mark_families() -> Array:
	return data().get("marks", {}).get("families", [])


static func mark_label(fam: String) -> String:
	return String(data().get("marks", {}).get("labels", {}).get(fam, fam))


## Bonus d'une marque, en points de % (+20 par marque au-delà de la première).
static func mark_bonus(mark: int) -> int:
	return int(data().get("marks", {}).get("step_pct", 20)) * maxi(0, mark - 1)


## Marques actuelles de l'empire {famille: 1..5} : ce que reçoit un vaisseau neuf ou remis à niveau.
static func marks(state: GameState, empire_id: int) -> Dictionary:
	var e := state.get_empire(empire_id)
	if e == null:
		return {}
	effects(state, empire_id)
	return e.tech_marks


## Indice de l'état actuel des marques dans Empire.marks_log (ajouté s'il a changé) : le vaisseau
## qui sort du chantier le garde jusqu'à sa prochaine remise à niveau.
static func mark_gen(state: GameState, empire_id: int) -> int:
	var e := state.get_empire(empire_id)
	if e == null:
		return -1
	var now := marks(state, empire_id)
	if e.marks_log.is_empty() or e.marks_log[e.marks_log.size() - 1] != now:
		e.marks_log.append(now.duplicate())
	return e.marks_log.size() - 1


## Marques d'un vaisseau d'après son indice (-1 : celles de l'empire, toujours à jour).
static func marks_of_gen(state: GameState, empire_id: int, g: int) -> Dictionary:
	var e := state.get_empire(empire_id)
	if e == null:
		return {}
	if g < 0 or g >= e.marks_log.size():
		return marks(state, empire_id)
	return e.marks_log[g]


## Le vaisseau a-t-il des marques en retard sur celles de l'empire ?
static func gen_outdated(state: GameState, empire_id: int, g: int) -> bool:
	return g >= 0 and marks_of_gen(state, empire_id, g) != marks(state, empire_id)


## Technologie qui donne la marque suivante d'une famille à cet empire ("" s'il n'y en a plus) :
## la moins avancée de son arbre parmi celles qu'il ne connaît pas.
static func next_mark_tech(state: GameState, empire_id: int, fam: String) -> String:
	var e := state.get_empire(empire_id)
	if e == null:
		return ""
	var best := ""
	var best_era := 99
	for tid in visible_ids(e.faction()):
		if e.techs.has(tid) or not tech(tid).get("effects", {}).get("marks", {}).has(fam):
			continue
		var era := int(tech(tid).get("era", 1))
		if era < best_era:
			best_era = era
			best = tid
	return best


# --- Épaves et eurêkas ---------------------------------------------------------------------------

## Ajoute du Savoir déjà acquis à une technologie (épave, eurêka) : à la recherche en cours s'il
## s'agit d'elle, sinon mis de côté. Une technologie entièrement payée ainsi est découverte aussitôt
## (c'est la seule façon d'obtenir l'autre branche d'une doctrine). Renvoie true si elle l'est.
static func add_progress(state: GameState, empire_id: int, tid: String, amount: int) -> bool:
	var e := state.get_empire(empire_id)
	if e == null or amount <= 0 or e.techs.has(tid):
		return false
	if not e.research_queue.is_empty() and e.research_queue[0] == tid:
		e.research_progress += amount
		return false  # achevée au prochain bilan, avec le reste de la recherche
	var have := int(e.research_shelf.get(tid, 0)) + amount
	if have >= cost(state, empire_id, tid) and not e.research_queue.has(tid):
		complete(state, empire_id, tid)
		return true
	e.research_shelf[tid] = have
	return false


## Savoir déjà acquis pour une technologie (en cours ou mis de côté).
static func progress_of(state: GameState, empire_id: int, tid: String) -> int:
	var e := state.get_empire(empire_id)
	if e == null:
		return 0
	if not e.research_queue.is_empty() and e.research_queue[0] == tid:
		return e.research_progress
	return int(e.research_shelf.get(tid, 0))


## Pourcentage de bonus des épaves pour un peuple (Reliques saintes ×2, Mémoire génétique ×3).
static func wreck_mult(faction: Dictionary) -> int:
	return int(faction.get("research", {}).get("wreck_pct", 100))


## Épaves (Stellaris) : le vainqueur d'une bataille étudie ce que le vaincu avait de plus avancé.
## Chaque famille où le vaincu a une meilleure marque donne wreck_pct % (10 %) de la technologie de la
## marque suivante ; chaque doctrine du vaincu que le vainqueur n'a pas, autant. Renvoie les
## technologies touchées [[id, Savoir, découverte ?]...].
@warning_ignore("integer_division")
static func study_wrecks(state: GameState, winner: int, loser: int) -> Array:
	var out: Array = []
	var w := state.get_empire(winner)
	var l := state.get_empire(loser)
	if w == null or l == null:
		return out
	var pct := int(data().get("wreck_pct", 10)) * wreck_mult(w.faction()) / 100
	var mine := marks(state, winner)
	var theirs := marks(state, loser)
	var targets: Array[String] = []
	for fam in mark_families():
		if int(theirs.get(fam, 1)) > int(mine.get(fam, 1)):
			var tid := next_mark_tech(state, winner, String(fam))
			if tid != "" and not targets.has(tid):
				targets.append(tid)
	for tid in l.sorted_techs():
		if tech(String(tid)).get("doctrine", false) and not w.techs.has(tid) and is_visible(w.faction(), String(tid)):
			targets.append(String(tid))
	for tid in targets:
		var amount := maxi(1, cost(state, winner, tid) * pct / 100)
		out.append([tid, amount, add_progress(state, winner, tid, amount)])
	return out


const CLAIM_KINDS := ["colonies", "pop", "building", "deposit", "planet", "claim"]


## Ce que tiennent les revendications fondées d'un empire, pour les eurêkas en attente `tids` (tous
## ceux de son arbre si vide) : {"kind:what": total}. Un seul passage sur les revendications.
static func claims_summary(state: GameState, empire_id: int, tids: Array = []) -> Dictionary:
	var e := state.get_empire(empire_id)
	var want: Array = []
	for tid in (tids if not tids.is_empty() else visible_ids(e.faction())):
		var eu: Dictionary = tech(String(tid)).get("eureka", {})
		if CLAIM_KINDS.has(String(eu.get("kind", ""))):
			var pair := [String(eu["kind"]), String(eu.get("what", ""))]
			if not want.has(pair):
				want.append(pair)
	var out := {}
	for pair in want:
		out[pair[0] + ":" + pair[1]] = 0
	if want.is_empty():
		return out
	for pid in state.colonies:
		var c: Colony = state.colonies[pid]
		if c.owner != empire_id or not c.is_established():
			continue
		var p := state.galaxy.get_planet(pid)
		for pair in want:
			var what: String = pair[1]
			var n := 0
			match String(pair[0]):
				"colonies": n = 1 if c.is_colony() else 0
				"pop": n = c.population if c.is_colony() else 0
				"building": n = 1 if c.buildings.has(what) else 0
				"deposit": n = 1 if p.deposits.has(what) else 0
				"planet": n = 1 if c.is_colony() and p.type == what else 0
				"claim": n = 1 if p.type == what else 0
			if n != 0:
				var k: String = pair[0] + ":" + what
				out[k] = int(out[k]) + n
	return out


## Avancement d'un eurêka : [valeur actuelle, objectif]. Les conditions lisent l'état sans le changer.
## summary : claims_summary déjà calculé (plusieurs eurêkas d'affilée), sinon calculé ici.
static func eureka_status(state: GameState, empire_id: int, tid: String, summary := {}) -> Array:
	var eu: Dictionary = tech(tid).get("eureka", {})
	var e := state.get_empire(empire_id)
	if eu.is_empty() or e == null:
		return [0, 0]
	var n := int(eu.get("n", 1))
	var what := String(eu.get("what", ""))
	var have := 0
	match String(eu.get("kind", "")):
		"kills", "ships_lost", "battles_won", "conquests", "besieged", "wars", "built", "sacrifices":
			have = int(e.stats.get(String(eu["kind"]), 0))
		"contacts":
			have = e.contacts.size()
		"explored":
			have = e.explored.size()
		"techs":
			have = e.techs.size()
		"exalted":
			have = 1 if FactionTraits.is_exalted(state, empire_id) else 0
		"trade", "peace":
			for c in e.contacts:
				var r: Dictionary = state.relations.get(Diplomacy.key(empire_id, c), {})
				if String(eu["kind"]) == "trade" and int(r.get("trade", 0)) != 0:
					have += 1
				elif String(eu["kind"]) == "peace" and String(r.get("pact", "")) != "":
					have += 1
		_:
			var k := String(eu["kind"]) + ":" + what
			if not summary.has(k):
				summary = claims_summary(state, empire_id, [tid])
			have = int(summary.get(k, 0))
	return [have, n]


## Objectif d'un eurêka, en clair ("" s'il n'y en a pas).
static func eureka_text(tid: String) -> String:
	var eu: Dictionary = tech(tid).get("eureka", {})
	if eu.is_empty():
		return ""
	var n := int(eu.get("n", 1))
	var what := String(eu.get("what", ""))
	var plural := "s" if n > 1 else ""
	match String(eu.get("kind", "")):
		"kills": return "détruire %d vaisseau%s ennemi%s" % [n, "x" if n > 1 else "", plural]
		"ships_lost": return "perdre %d vaisseau%s au combat" % [n, "x" if n > 1 else ""]
		"battles_won": return "gagner %d bataille%s" % [n, plural]
		"conquests": return "conquérir %d système%s" % [n, plural]
		"besieged": return "subir un siège"
		"wars": return "entrer en guerre"
		"built": return "construire %d vaisseau%s" % [n, "x" if n > 1 else ""]
		"sacrifices": return "faire %d offrande%s" % [n, plural]
		"contacts": return "rencontrer %d empire%s" % [n, plural]
		"explored": return "explorer %d systèmes" % n
		"techs": return "connaître %d technologies" % n
		"exalted": return "atteindre l'Exaltation"
		"trade": return "signer un accord commercial"
		"peace": return "signer une paix"
		"colonies": return "fonder %d colonies" % n
		"pop": return "atteindre %d de population" % n
		"building": return "avoir %d %s" % [n, String(GameData.building(what).get("label", what)).to_lower()]
		"deposit": return "tenir %d gisement%s de %s" % [n, plural, String(GameData.deposit(what).get("label", what)).to_lower()]
		"planet": return "coloniser un monde %s" % String(GameData.planet_type(what).get("label", what)).to_lower()
		"claim": return "revendiquer une planète %s" % String(GameData.planet_type(what).get("label", what)).to_lower()
	return ""


## Eurêkas (Civilization VI) atteints ce mois-ci : chacun paie eureka_pct % (40 %) de la technologie,
## une seule fois. Renvoie les technologies concernées.
@warning_ignore("integer_division")
static func check_eurekas(state: GameState, empire_id: int) -> Array[String]:
	var out: Array[String] = []
	var e := state.get_empire(empire_id)
	if e == null:
		return out
	var pct := int(data().get("eureka_pct", 40))
	var pending: Array = []
	for tid in visible_ids(e.faction()):
		if not e.techs.has(tid) and not e.eurekas.has(tid) and tech(tid).has("eureka"):
			pending.append(tid)
	var summary := claims_summary(state, empire_id, pending) if not pending.is_empty() else {}
	for tid in pending:
		var st := eureka_status(state, empire_id, tid, summary)
		if int(st[0]) < int(st[1]):
			continue
		e.eurekas[tid] = true
		add_progress(state, empire_id, tid, maxi(1, cost(state, empire_id, tid) * pct / 100))
		out.append(tid)
	return out


static func count_stat(state: GameState, empire_id: int, key: String, n := 1) -> void:
	var e := state.get_empire(empire_id)
	if e:
		e.stats[key] = int(e.stats.get(key, 0)) + n


# --- Effets -------------------------------------------------------------------------------------

## Effets cumulés des technologies connues : les nombres s'additionnent, les tables aussi, clé par clé.
## Pendant l'Exaltation (Chœur Éternel), les effects_exalted s'ajoutent.
## Clés : production_pct {res|"all"} (« all » hors Savoir), growth_pct, colony_start_pop, max_projects,
## building_slots, building_cost_pct, hab_bonus {type|"all"}, hab_set {type}, weapon_pct {famille},
## damage_pct, defense_pct {armor, shield, pd}, troops_pct, home_damage_pct, reinforcement_pct,
## garrison_pct, fleet_speed_pct, ship_days_pct, ship_cost_pct, upkeep_pct, claim_vision, alliances,
## fervor_big_colony, sacrifice_gain, fief_influence, biomass_bonus, marks {famille} (marques en plus),
## doctrines : screen_taken_pct, deep_strike_pct, phase_damage_pct {long|medium|short}, repair_pct,
## siege_pct, first_day_damage_pct.
static func effects(state: GameState, empire_id: int) -> Dictionary:
	var e := state.get_empire(empire_id)
	if e == null:
		return {}
	if e.tech_fx_n != e.techs.size():
		var base := {}
		var exalted := {}
		var has_exalted := false
		var ids: Array = e.techs.keys()
		ids.sort()
		for tid in ids:
			var t := tech(String(tid))
			_merge(base, t.get("effects", {}))
			_merge(exalted, t.get("effects", {}))
			if t.has("effects_exalted"):
				has_exalted = true
				_merge(exalted, t["effects_exalted"])
		e.tech_fx = base
		e.tech_fx_exalted = exalted
		e.tech_fx_has_exalted = has_exalted
		var md: Dictionary = data().get("marks", {})
		var bonus: Dictionary = base.get("marks", {})
		var marks := {}
		for fam in md.get("families", []):
			marks[String(fam)] = mini(int(md.get("max", 5)), 1 + int(bonus.get(fam, 0)))
		e.tech_marks = marks
		e.tech_fx_n = e.techs.size()
	# (appelé des centaines de milliers de fois par partie : l'exaltation n'est testée que si elle compte)
	if e.tech_fx_has_exalted and FactionTraits.is_exalted(state, empire_id):
		return e.tech_fx_exalted
	return e.tech_fx


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
