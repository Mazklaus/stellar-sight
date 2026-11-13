class_name Peoples
extends RefCounted
## Populations mixtes (étude « Populations mixtes et migrations », 2026-11-13, lot 1 : propositions 1
## à 7). Une colonie peut abriter plusieurs espèces : chaque espèce est une fiche de peuple (officiel
## ou créé), désignée par son identifiant de faction.
##
## Modèle : Colony.population reste le total, utilisé partout ailleurs. Colony.species ne compte que
## les habitants qui ne sont PAS de l'espèce du propriétaire ; le reste (population moins la somme)
## est l'espèce du propriétaire. Une colonie d'une seule espèce a donc un dictionnaire vide, et rien
## ne change pour elle.
##
## Sans l'option de partie « peoples » (tests, bancs, vieilles sauvegardes), la conquête convertit les
## habitants comme avant et aucune colonie n'a de mosaïque.

## Habitabilité sous laquelle une espèce ne naît plus là où une autre espèce y est à l'aise.
const BIRTH_HAB := 40


static func data() -> Dictionary:
	return GameData.rules().get("peoples", {})


static func enabled(state: GameState) -> bool:
	return state.peoples_on


## Espèce d'un propriétaire ("" pour les puissances neutres, qui n'ont pas d'espèce propre).
static func founder_of(state: GameState, owner: int) -> String:
	if GameState.is_npc(owner):
		return ""
	var e := state.get_empire(owner)
	return e.faction_id if e != null else ""


static func label(fid: String) -> String:
	var f := GameData.faction(fid)
	return String(f.get("short", f.get("name", fid)))


## Habitants par espèce, espèce du propriétaire comprise ({} pour un avant-poste ou une colonie vide).
static func counts(state: GameState, c: Colony) -> Dictionary:
	var out := {}
	if not c.is_colony() or c.population <= 0:
		return out
	var rest := c.population
	for fid in c.species:
		var n := int(c.species[fid])
		if n > 0:
			out[fid] = n
			rest -= n
	var own := founder_of(state, c.owner)
	if rest > 0:
		out[own] = int(out.get(own, 0)) + rest
	return out


## Habitants de l'espèce du propriétaire.
static func own_count(c: Colony) -> int:
	var rest := c.population
	for fid in c.species:
		rest -= int(c.species[fid])
	return maxi(0, rest)


## Remet la mosaïque d'accord avec le total, après une perte d'habitants (famine, sacrifice, fléau,
## digestion…) : une fois l'espèce du propriétaire épuisée, la plus nombreuse des autres perd les
## siens d'abord (à égalité, l'identifiant le plus petit).
static func normalize(c: Colony) -> void:
	if c.species.is_empty():
		return
	var total := 0
	for fid in c.species.keys():
		if int(c.species[fid]) <= 0:
			c.species.erase(fid)
		else:
			total += int(c.species[fid])
	while total > c.population and not c.species.is_empty():
		var best := ""
		for fid in _sorted_keys(c.species):
			if best == "" or int(c.species[fid]) > int(c.species[best]):
				best = fid
		var cut := mini(int(c.species[best]), total - c.population)
		c.species[best] = int(c.species[best]) - cut
		total -= cut
		if int(c.species[best]) <= 0:
			c.species.erase(best)


## Changement de propriétaire (conquête, sécession, réintégration) : les habitants gardent leur
## espèce. L'espèce de l'ancien propriétaire passe dans la mosaïque, celle du nouveau en sort (elle
## devient le reste implicite).
static func on_owner_change(state: GameState, c: Colony, old_owner: int, new_owner: int) -> void:
	if not enabled(state) or not c.is_colony():
		c.species.clear()
		return
	normalize(c)
	var old_f := founder_of(state, old_owner)
	var rest := own_count(c)
	if rest > 0 and old_f != "":
		c.species[old_f] = int(c.species.get(old_f, 0)) + rest
	var new_f := founder_of(state, new_owner)
	if new_f != "":
		c.species.erase(new_f)


## Fondation d'une colonie peuplée par une autre espèce de l'empire (voir Colony.founder).
static func on_founded(state: GameState, c: Colony) -> void:
	var fid := c.founder
	c.founder = ""
	if fid == "" or not enabled(state) or fid == founder_of(state, c.owner):
		return
	c.species.clear()
	c.species[fid] = c.population


# --- Habitabilité par espèce --------------------------------------------------------------------

## Habitabilité d'un type de planète pour une espèce vivant dans un empire : les technologies de
## l'empire profitent à tous ses habitants. Gardée dans le cache de l'empire.
static func hab(state: GameState, empire_id: int, fid: String, planet_type: String) -> int:
	if fid == "" or fid == founder_of(state, empire_id):
		return Economy._pop_hab(state, empire_id, planet_type)
	var e := state.get_empire(empire_id)
	if e == null:
		return 0
	if e.hab_cache_n != e.techs.size():
		e.hab_cache.clear()
		e.hab_cache_n = e.techs.size()
	var key := fid + "|" + planet_type
	if not e.hab_cache.has(key):
		var f := GameData.faction(fid)
		e.hab_cache[key] = Economy.habitability_for(state, empire_id, planet_type, f) \
				if Economy.houses_pop(state, empire_id, planet_type, f) else 0
	return e.hab_cache[key]


## Meilleure habitabilité parmi les espèces présentes sur une colonie (ou -1 sans mosaïque).
static func best_hab(state: GameState, c: Colony, planet_type: String) -> int:
	if c.species.is_empty():
		return -1
	var best := 0
	if own_count(c) > 0:
		best = Economy._pop_hab(state, c.owner, planet_type)
	for fid in c.species:
		if int(c.species[fid]) > 0:
			best = maxi(best, hab(state, c.owner, String(fid), planet_type))
	return best


# --- Naissances ---------------------------------------------------------------------------------

## Un habitant de plus : l'espèce est tirée parmi celles présentes, au prorata de leur nombre, de leur
## habitabilité et du monde natal (×2). Tirage haché sur le jour et la planète : déterministe.
static func on_birth(state: GameState, c: Colony) -> void:
	c.population += 1
	if c.species.is_empty():
		return
	var fid := birth_species(state, c)
	if fid != founder_of(state, c.owner):
		c.species[fid] = int(c.species.get(fid, 0)) + 1


static func birth_weights(state: GameState, c: Colony) -> Dictionary:
	var planet := state.galaxy.get_planet(c.planet_id)
	var cnt := counts(state, c)
	var habs := {}
	var any_ok := false
	for fid in cnt:
		habs[fid] = hab(state, c.owner, fid, planet.type)
		if int(habs[fid]) >= BIRTH_HAB:
			any_ok = true
	var w := {}
	for fid in _sorted_keys(cnt):
		var h := int(habs[fid])
		if h <= 0 or (any_ok and h < BIRTH_HAB):
			continue
		var v := int(cnt[fid]) * h
		if _is_homeworld(state, fid, c.planet_id):
			v *= 2
		w[fid] = v
	return w


static func birth_species(state: GameState, c: Colony) -> String:
	var w := birth_weights(state, c)
	var own := founder_of(state, c.owner)
	if w.is_empty():
		return own if own_count(c) > 0 else String(_sorted_keys(c.species)[0])
	var total := 0
	for fid in w:
		total += int(w[fid])
	var roll := absi(hash([state.seed_value, state.tick, c.planet_id, "naissance"])) % maxi(1, total)
	for fid in _sorted_keys(w):
		roll -= int(w[fid])
		if roll < 0:
			return fid
	return own


static func _is_homeworld(state: GameState, fid: String, planet_id: int) -> bool:
	for e in state.empires:
		if e.faction_id == fid and e.home_planet == planet_id:
			return true
	return false


# --- Espèces d'un empire, colonisation ----------------------------------------------------------

## Habitants de chaque espèce dans tout l'empire (colonies établies), espèce fondatrice comprise.
static func empire_counts(state: GameState, empire_id: int) -> Dictionary:
	var out := {}
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner != empire_id or not c.is_established():
			continue
		var cnt := counts(state, c)
		for fid in cnt:
			out[fid] = int(out.get(fid, 0)) + int(cnt[fid])
	return out


## Espèces avec lesquelles l'empire peut fonder une colonie : la sienne, et toute autre qui compte au
## moins colonize_min habitants chez lui (relevé au bilan mensuel, voir refresh).
static func colonist_species(state: GameState, empire_id: int) -> Array[String]:
	var out: Array[String] = []
	var own := founder_of(state, empire_id)
	if own != "":
		out.append(own)
	if not enabled(state):
		return out
	for fid in state.peoples.get("colonists", {}).get(str(empire_id), []):
		if String(fid) != own:
			out.append(String(fid))
	return out


## "" si l'empire peut coloniser cette planète avec cette espèce, sinon la raison.
static func check_colonist(state: GameState, empire_id: int, planet: Planet, fid: String) -> String:
	if fid == "" or fid == founder_of(state, empire_id):
		return ""
	if not enabled(state):
		return "les peuples mêlés ne sont pas actifs dans cette partie"
	if not colonist_species(state, empire_id).has(fid):
		return "il faut au moins %d %s dans l'empire pour fonder une colonie" % [int(data().get("colonize_min", 2)), label(fid)]
	if hab(state, empire_id, fid, planet.type) <= 0:
		return "planète inhabitable pour les %s" % label(fid)
	return ""


## L'espèce de l'empire la mieux adaptée à un type de planète (la sienne à égalité).
static func best_colonist(state: GameState, empire_id: int, planet_type: String) -> String:
	var best := founder_of(state, empire_id)
	var best_h := hab(state, empire_id, best, planet_type)
	for fid in colonist_species(state, empire_id):
		var h := hab(state, empire_id, fid, planet_type)
		if h > best_h:
			best = fid
			best_h = h
	return best


# --- Production par espèce ----------------------------------------------------------------------

## Ajuste la production d'une colonie mêlée : chaque espèce garde ses pourcentages de production.
## Economy.production_pct applique ensuite ceux de l'espèce du propriétaire à tout l'empire ; on
## multiplie donc ici par la moyenne (pondérée par les habitants) du rapport espèce / propriétaire.
@warning_ignore("integer_division")
static func adjust_yields(state: GameState, c: Colony, gross: Dictionary) -> void:
	if c.species.is_empty() or c.population <= 0:
		return
	var cnt := counts(state, c)
	var own_f := GameData.faction(founder_of(state, c.owner))
	var own_pct: Dictionary = own_f.get("production_pct", {})
	for r in gross:
		var base := int(own_pct.get(r, 100))
		var acc := 0
		for fid in cnt:
			var p := int(GameData.faction(fid).get("production_pct", {}).get(r, 100))
			acc += int(cnt[fid]) * p * 100 / maxi(1, base)
		var factor := acc / maxi(1, c.population)
		if factor != 100 and int(gross[r]) > 0:
			gross[r] = int(gross[r]) * factor / 100


# --- Bonus de collection ------------------------------------------------------------------------

## Ressource où une espèce excelle : son plus fort pourcentage de production (au-dessus de 100),
## sinon le Savoir (« chaque peuple apporte ses idées »).
static func strong_resource(fid: String) -> String:
	var pct: Dictionary = GameData.faction(fid).get("production_pct", {})
	var best := "knowledge"
	var best_v := 100
	for r in _sorted_keys(pct):
		if int(pct[r]) > best_v:
			best = r
			best_v = int(pct[r])
	return best


## Paliers de collection atteints par une espèce : 0 à 3.
static func collection_tier(n: int) -> int:
	var tiers: Array = data().get("collection_tiers", [10, 25, 50])
	var t := 0
	for i in tiers.size():
		if n >= int(tiers[i]):
			t = i + 1
	return t


## Bilan mensuel : recalcule les bonus de collection de chaque empire (gardés dans state.peoples,
## sauvegardés, pour que production_pct n'ait pas à compter les habitants).
static func refresh(state: GameState) -> void:
	if not enabled(state):
		return
	var coll := {}
	var colonists := {}
	var need := int(data().get("colonize_min", 2))
	for e in state.empires:
		if e.eliminated:
			continue
		var cnt := empire_counts(state, e.id)
		var cs := []
		for fid in _sorted_keys(cnt):
			if fid != e.faction_id and fid != "" and int(cnt[fid]) >= need:
				cs.append(fid)
		if not cs.is_empty():
			colonists[str(e.id)] = cs
		var entry := {}
		for fid in _sorted_keys(cnt):
			if fid == e.faction_id or fid == "":
				continue
			var t := collection_tier(int(cnt[fid]))
			if t > 0:
				entry[fid] = t
		if not entry.is_empty():
			coll[str(e.id)] = entry
	state.peoples["coll"] = coll
	state.peoples["colonists"] = colonists


## Bonus de production (en %) des collections d'un empire pour une ressource.
static func collection_pct(state: GameState, empire_id: int, resource: String) -> int:
	if not state.peoples_on:
		return 0
	var entry: Dictionary = state.peoples.get("coll", {}).get(str(empire_id), {})
	if entry.is_empty():
		return 0
	var pcts: Array = data().get("collection_pct", [5, 10, 15])
	var total := 0
	for fid in entry:
		if strong_resource(String(fid)) == resource:
			total += int(pcts[clampi(int(entry[fid]) - 1, 0, pcts.size() - 1)])
	return total


## Bonus de collection d'un empire, pour l'affichage : [{"species", "tier", "resource", "pct", "count"}].
static func collections(state: GameState, empire_id: int) -> Array:
	var out := []
	var entry: Dictionary = state.peoples.get("coll", {}).get(str(empire_id), {})
	var pcts: Array = data().get("collection_pct", [5, 10, 15])
	for fid in _sorted_keys(entry):
		var t := int(entry[fid])
		out.append({"species": fid, "tier": t, "resource": strong_resource(fid),
				"pct": int(pcts[clampi(t - 1, 0, pcts.size() - 1)])})
	return out


# --- Sauvegarde ---------------------------------------------------------------------------------

static func setup(state: GameState, mode: String) -> void:
	state.peoples_on = mode == "actifs"
	state.peoples = {"coll": {}, "colonists": {}}


static func to_dict(state: GameState) -> Dictionary:
	return {"on": state.peoples_on, "coll": state.peoples.get("coll", {}).duplicate(true),
			"colonists": state.peoples.get("colonists", {}).duplicate(true)}


static func from_dict(state: GameState, d: Dictionary) -> void:
	state.peoples_on = bool(d.get("on", false))
	state.peoples = {"coll": d.get("coll", {}).duplicate(true), "colonists": d.get("colonists", {}).duplicate(true)}


static func _sorted_keys(d: Dictionary) -> Array:
	var k := d.keys()
	k.sort()
	return k
