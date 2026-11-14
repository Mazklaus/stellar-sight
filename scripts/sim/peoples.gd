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
## Lot 2 (propositions 8 à 15) : un statut par espèce et par empire (citoyens, résidents, assujettis,
## à assimiler, expulsés, exterminés), une intégration par colonie et par espèce (Colony.integ), les
## affinités et frictions entre espèces (calculées depuis les couches), l'opinion des systèmes mêlée
## par les credos des citoyens, deux lois (Hospitalité, Préférence native), la doléance « Des droits
## pour mon peuple » et des héros d'autres espèces. Règles : data/rules.json "peoples".
##
## Sans l'option de partie « peoples » (tests, bancs, vieilles sauvegardes), la conquête convertit les
## habitants comme avant et aucune colonie n'a de mosaïque.

## Habitabilité sous laquelle une espèce ne naît plus là où une autre espèce y est à l'aise.
const BIRTH_HAB := 40
## Statuts, dans l'ordre d'affichage.
const STATUSES := ["citoyens", "residents", "assujettis", "assimiler", "expulses", "extermines"]


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
	_clean_integ(c)


static func _clean_integ(c: Colony) -> void:
	for fid in c.integ.keys():
		if not c.species.has(fid):
			c.integ.erase(fid)


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
	# Monde conquis (ou repris) : tout le monde repart de zéro avec le nouveau maître.
	c.integ.clear()
	var start := int(data().get("integration", {}).get("conquered", 0))
	for fid in c.species:
		c.integ[fid] = start


## Fondation d'une colonie peuplée par une autre espèce de l'empire (voir Colony.founder).
static func on_founded(state: GameState, c: Colony) -> void:
	var fid := c.founder
	c.founder = ""
	if fid == "" or not enabled(state) or fid == founder_of(state, c.owner):
		return
	c.species.clear()
	c.species[fid] = c.population
	c.integ.clear()
	c.integ[fid] = int(data().get("integration", {}).get("founded", 75))


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
		# Luxe aimé servi (proposition 23) : les naissances doublent.
		if fid != founder_of(state, c.owner) and Movements.loved_served(state, c.owner, fid):
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
	# Une fois par espèce (et non par ressource) : nombre, pourcentages de son peuple, modificateur.
	var info := []
	for fid in cnt:
		info.append([int(cnt[fid]), GameData.faction(fid).get("production_pct", {}), species_prod_mod(state, c, fid)])
	for r in gross:
		var base := int(own_pct.get(r, 100))
		var acc := 0
		for x: Array in info:
			var p := int((x[1] as Dictionary).get(r, 100)) * int(x[2]) / 100
			acc += int(x[0]) * p * 100 / maxi(1, base)
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
	var pops := {}
	var need := int(data().get("colonize_min", 2))
	for e in state.empires:
		if e.eliminated:
			continue
		var cnt := empire_counts(state, e.id)
		var foreign := {}
		for fid in _sorted_keys(cnt):
			if fid != e.faction_id and fid != "" and int(cnt[fid]) > 0:
				foreign[fid] = int(cnt[fid])
		if not foreign.is_empty():
			pops[str(e.id)] = foreign
		var cs := []
		for fid in _sorted_keys(cnt):
			if fid != e.faction_id and fid != "" and int(cnt[fid]) >= need:
				cs.append(fid)
		# Traité de migration : on colonise aussi avec l'espèce du partenaire.
		for o in Movements.partners(state, e.id):
			var of := state.get_empire(o).faction_id
			if o != e.id and of != e.faction_id and not cs.has(of):
				cs.append(of)
		cs.sort()
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
	state.peoples["pop"] = pops


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


# --- Statuts (lot 2, propositions 8, 10 et 12) --------------------------------------------------

static func status_def(id: String) -> Dictionary:
	return (data().get("statuses", {}) as Dictionary).get(id, {})


static func status_label(id: String) -> String:
	return String(status_def(id).get("label", id))


static func _layer(fid: String, layer: String) -> String:
	return String(GameData.faction(fid).get("species", {}).get(layer, ""))


static func _is_hive(fid: String) -> bool:
	return _layer(fid, "gouvernement") == "ruche" or _layer(fid, "archetype") == "ruche"


## Statuts possibles pour une espèce dans un empire. Une ruche n'a que des assujettis ; une conscience
## synthétique, des résidents ou des assujettis ; les habitants d'une ruche chez un empire ordinaire ne
## peuvent être que résidents ou assujettis ; la république n'assujettit pas. L'expulsion et
## l'extermination restent des choix ouverts à tous (l'Essaim, lui, digère : voir FactionTraits).
static func allowed_statuses(state: GameState, empire_id: int, fid: String) -> Array[String]:
	var out: Array[String] = []
	var own := founder_of(state, empire_id)
	if own == "" or fid == own:
		out.append("citoyens")
		return out
	var og := _layer(own, "gouvernement")
	var base: Array
	if og == "ruche":
		base = ["assujettis", "expulses", "extermines"]
	elif og == "conscience" or _is_hive(fid):
		base = ["residents", "assujettis", "expulses", "extermines"]
	else:
		base = STATUSES.duplicate()
	for st in base:
		if st == "assujettis" and og == "republique":
			continue
		out.append(String(st))
	return out


static func default_status(state: GameState, empire_id: int, fid: String) -> String:
	var ok := allowed_statuses(state, empire_id, fid)
	for st in ["citoyens", "residents", "assujettis"]:
		if ok.has(st):
			return st
	return ok[0]


## Statut d'une espèce dans un empire (l'espèce fondatrice est toujours citoyenne).
static func status(state: GameState, empire_id: int, fid: String) -> String:
	if fid == founder_of(state, empire_id) or GameState.is_npc(empire_id):
		return "citoyens"
	var st := String((state.peoples.get("status", {}) as Dictionary).get(str(empire_id), {}).get(fid, ""))
	if st != "" and allowed_statuses(state, empire_id, fid).has(st):
		return st
	return default_status(state, empire_id, fid)


## Citoyens au sens du vote, des héros et de l'opinion (« à assimiler » en sont).
static func is_citizen(state: GameState, empire_id: int, fid: String) -> bool:
	var st := status(state, empire_id, fid)
	return st == "citoyens" or st == "assimiler"


## Jour à partir duquel le statut de cette espèce peut de nouveau changer.
static func next_change(state: GameState, empire_id: int, fid: String) -> int:
	var m: Dictionary = (state.peoples.get("changed", {}) as Dictionary).get(str(empire_id), {})
	if not m.has(fid):
		return 0
	return int(m[fid]) + int(data().get("status_days", 1800))


## Habitants des autres espèces dans un empire (relevé au bilan mensuel).
static func foreign_pop(state: GameState, empire_id: int) -> Dictionary:
	return (state.peoples.get("pop", {}) as Dictionary).get(str(empire_id), {})


static func check_status(state: GameState, empire_id: int, fid: String, st: String) -> String:
	if not enabled(state):
		return "les peuples mêlés ne sont pas actifs dans cette partie"
	var e := state.get_empire(empire_id)
	if e == null or e.eliminated:
		return "empire inconnu"
	if fid == e.faction_id:
		return "votre propre peuple est toujours citoyen"
	if GameData.faction(fid).is_empty():
		return "peuple inconnu : %s" % fid
	if not STATUSES.has(st):
		return "statut inconnu : %s" % st
	if not allowed_statuses(state, empire_id, fid).has(st):
		if st == "assujettis" and _layer(e.faction_id, "gouvernement") == "republique":
			return "la république n'assujettit personne"
		return "%s impossible pour les %s chez vous" % [status_label(st), label(fid)]
	if status(state, empire_id, fid) == st:
		return "c'est déjà leur statut"
	var nx := next_change(state, empire_id, fid)
	if state.tick < nx:
		return "leur statut a changé récemment : prochain changement le %s" % GameCalendar.date_string(nx)
	return ""


static func set_status(state: GameState, empire_id: int, fid: String, st: String) -> void:
	var key := str(empire_id)
	FaithNatures.on_status(state, empire_id, status(state, empire_id, fid), st)
	for k in ["status", "changed"]:
		if not state.peoples.has(k):
			state.peoples[k] = {}
		if not (state.peoples[k] as Dictionary).has(key):
			state.peoples[k][key] = {}
	state.peoples["status"][key][fid] = st
	state.peoples["changed"][key][fid] = state.tick


# --- Intégration (proposition 9) ----------------------------------------------------------------

static func integration(c: Colony, fid: String) -> int:
	return int(c.integ.get(fid, 100))


## Intégration moyenne d'une espèce dans un empire (pondérée par les habitants ; -1 si absente).
@warning_ignore("integer_division")
static func empire_integration(state: GameState, empire_id: int, fid: String) -> int:
	var n := 0
	var acc := 0
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner != empire_id or not c.is_established():
			continue
		var k := int(c.species.get(fid, 0))
		if k > 0:
			n += k
			acc += k * integration(c, fid)
	return acc / n if n > 0 else -1


## Points d'intégration gagnés en un an par une espèce sur une colonie.
@warning_ignore("integer_division")
static func integration_rate(state: GameState, c: Colony, fid: String) -> int:
	var st := status(state, c.owner, fid)
	if bool(status_def(st).get("no_integration", false)):
		return 0
	var ig: Dictionary = data().get("integration", {})
	var v := int(ig.get("yearly", 5))
	if st == "citoyens" or st == "assimiler":
		v += int(ig.get("citizen", 2))
	var own := founder_of(state, c.owner)
	if _layer(fid, "credo") != "" and _layer(fid, "credo") == _layer(own, "credo"):
		v += int(ig.get("same_credo", 2))
	if c.buildings.has("forum"):
		v += int(ig.get("forum", 2))
	if not state.heroes.is_empty():
		var sid := state.galaxy.get_planet(c.planet_id).system_id
		if not Heroes.at_post(state, "system", sid, c.owner).is_empty():
			v += int(ig.get("intendant", 2))
	var tl := Movements.talent(state, c.owner)
	v += int(tl.get("integ_yearly", 0))
	var pct := int(Laws.effects(state, c.owner).get("integration_pct", 0)) + int(tl.get("integ_pct", 0))
	v = v * (100 + pct) / 100
	# Propagande xénophobe d'un rival : moitié moins vite.
	if Movements.xeno_left(state, c.owner) > 0:
		v /= 2
	return v


## Modificateur de production (en %) d'une espèce sur une colonie : statut et intégration.
@warning_ignore("integer_division")
static func species_prod_mod(state: GameState, c: Colony, fid: String) -> int:
	if fid == founder_of(state, c.owner):
		return 100
	var st := status(state, c.owner, fid)
	var mod := 100 + int(status_def(st).get("prod_pct", 0))
	# Conscience : les esprits organiques invités travaillent mieux (talent guest_prod_pct).
	if (st == "residents" or st == "assujettis") and _layer(fid, "archetype") != "synthetique":
		mod += int(Movements.talent(state, c.owner).get("guest_prod_pct", 0))
	var ig: Dictionary = data().get("integration", {})
	var below := int(ig.get("low_below", 50))
	var i := integration(c, fid)
	if i < below:
		mod += int(ig.get("low_prod_max", -25)) * (below - i) / maxi(1, below)
	return maxi(0, mod)


# --- Affinités, frictions et stabilité (propositions 9, 10, 11, 14) -----------------------------

## Affinité (positive) ou friction (négative) entre deux espèces, depuis leurs couches.
static func affinity(a: String, b: String) -> int:
	var fr: Dictionary = data().get("frictions", {})
	var v := 0
	var ca := _layer(a, "credo")
	var cb := _layer(b, "credo")
	if ca != "" and ca == cb:
		v += int(fr.get("same_credo", 2))
	elif ca != "" and cb != "":
		var lean: Dictionary = Politics.data()["lean"]["credo"]
		var ia := Politics.index_of(String(lean.get(ca, "")))
		var ib := Politics.index_of(String(lean.get(cb, "")))
		if ia >= 0 and ib >= 0 and ib == Politics.opposite(ia):
			v += int(fr.get("opposed_credo", -2))
	var xa := _layer(a, "archetype")
	var xb := _layer(b, "archetype")
	if xa != "" and xa == xb:
		v += int(fr.get("same_archetype", 1))
	if _is_hive(a) != _is_hive(b):
		v += int(fr.get("ruche", -4))
	if (xa == "synthetique") != (xb == "synthetique") and not _is_hive(a) and not _is_hive(b) \
			and xa != "energetique" and xb != "energetique":
		v += int(fr.get("synthetique", -2))
	return v


## Habitants par espèce d'un système (colonies établies du propriétaire) et leur intégration cumulée.
static func system_counts(state: GameState, sid: int, owner: int) -> Dictionary:
	var cnt := {}
	var integ := {}
	for pid in state.galaxy.systems[sid].planet_ids:
		var c: Colony = state.colonies.get(pid)
		if c == null or c.owner != owner or not c.is_established() or not c.is_colony():
			continue
		var cc := counts(state, c)
		for fid in cc:
			cnt[fid] = int(cnt.get(fid, 0)) + int(cc[fid])
			integ[fid] = int(integ.get(fid, 0)) + int(cc[fid]) * (100 if fid == founder_of(state, owner) else integration(c, fid))
	return {"cnt": cnt, "integ": integ}


## Lignes de stabilité des peuples pour un système (voir Stability.parts).
@warning_ignore("integer_division")
static func stability_parts(state: GameState, sid: int, owner: int) -> Array:
	var out := []
	if not enabled(state) or GameState.is_npc(owner):
		return out
	var sc := system_counts(state, sid, owner)
	var cnt: Dictionary = sc["cnt"]
	var total := 0
	for fid in cnt:
		total += int(cnt[fid])
	if total <= 0:
		return out
	var own := founder_of(state, owner)
	var own_n := int(cnt.get(own, 0))
	var foreign := total - own_n
	if foreign > 0:
		# Statuts : une ligne par statut, avec les espèces concernées.
		var by := {}
		for fid in _sorted_keys(cnt):
			if fid == own:
				continue
			var st := status(state, owner, fid)
			var sd := status_def(st)
			var v := int(sd.get("stability", 0))
			if st == "residents" and int(cnt[fid]) * 2 > total:
				v = int(sd.get("stability_major", 0))
			if st == "assimiler" and int(Movements.talent(state, owner).get("assim_free", 0)) > 0:
				v = 0
			if v == 0:
				continue
			if not by.has(st):
				by[st] = {"v": v, "who": []}
			(by[st]["who"] as Array).append(label(fid))
		for st in STATUSES:
			if by.has(st):
				out.append(["%s (%s)" % [status_label(st), ", ".join(by[st]["who"])], int(by[st]["v"])])
		# Intégration.
		var ig: Dictionary = data().get("integration", {})
		var below := int(ig.get("low_below", 50))
		var acc := 0
		for fid in cnt:
			if fid != own:
				acc += int(sc["integ"][fid])
		var avg := acc / foreign
		if avg < below:
			var v := int(ig.get("low_max", -10)) * (below - avg) * foreign / (maxi(1, below) * total)
			if v != 0:
				out.append(["Peuples mal intégrés (%d %%)" % avg, v])
		# Affinités et frictions.
		var fr: Dictionary = data().get("frictions", {})
		var big: Array = []
		for fid in _sorted_keys(cnt):
			if int(cnt[fid]) * 100 >= int(fr.get("share_pct", 15)) * total:
				big.append(fid)
		var af := 0
		for i in big.size():
			for j in range(i + 1, big.size()):
				af += affinity(String(big[i]), String(big[j]))
		af = clampi(af, -int(fr.get("max", 5)), int(fr.get("max", 5)))
		if af != 0:
			out.append(["Affinités entre peuples" if af > 0 else "Frictions entre peuples", af])
		# Luxe aimé servi (proposition 23) : une ligne, quel que soit le nombre d'espèces comblées.
		var fed: Array = []
		for fid in big:
			if fid != own and Movements.loved_served(state, owner, String(fid)):
				fed.append(label(String(fid)))
		if not fed.is_empty():
			out.append(["Luxe aimé servi (%s)" % ", ".join(fed), int(Movements.data().get("loved_stability", 5))])
	# Lois.
	var fx := Laws.effects(state, owner)
	var native := own_n * 2 > total
	var np := int(fx.get("native_pref", 0))
	if np != 0:
		out.append(["Préférence native" + ("" if native else " (votre peuple y est minoritaire)"), np if native else -np])
	var sn := int(fx.get("stability_native", 0))
	if sn != 0 and native and foreign > 0:
		out.append(["Hospitalité (les vôtres grognent)", sn])
	# Doléance « Des droits pour mon peuple ».
	var r: Dictionary = (state.peoples.get("rights", {}) as Dictionary).get(str(owner), {})
	for f: Dictionary in r.get("fx", []):
		if int(f["end"]) > state.tick and int(cnt.get(String(f["fid"]), 0)) > 0:
			out.append(["Droits des %s %s" % [label(String(f["fid"])), "accordés" if int(f["v"]) > 0 else "refusés"], int(f["v"])])
	return out


# --- Opinion politique mêlée (proposition 13) ---------------------------------------------------

## Penchant naturel d'un système : celui du peuple fondateur, mêlé au prorata de ses citoyens
## d'autres espèces (chacune vote selon son credo).
@warning_ignore("integer_division")
static func system_nature(state: GameState, sid: int, owner: int, nat: Array) -> Array:
	if not enabled(state):
		return nat
	var cnt: Dictionary = system_counts(state, sid, owner)["cnt"]
	var own := founder_of(state, owner)
	var total := int(cnt.get(own, 0))
	var mixed := false
	for fid in cnt:
		if fid != own and is_citizen(state, owner, fid):
			total += int(cnt[fid])
			mixed = true
	if not mixed or total <= 0:
		return nat
	var out := []
	for i in Politics.N:
		out.append(int(nat[i]) * int(cnt.get(own, 0)))
	for fid in _sorted_keys(cnt):
		if fid == own or not is_citizen(state, owner, fid):
			continue
		var n := Politics.nature_of(GameData.faction(fid))
		for i in Politics.N:
			out[i] = int(out[i]) + int(n[i]) * int(cnt[fid])
	for i in Politics.N:
		out[i] = int(out[i]) / total
	Politics._normalize(out, Politics._argmax(out))
	return out


# --- Bilan mensuel ------------------------------------------------------------------------------

## Départs (expulsion, extermination), assimilation, intégration annuelle, doléance des droits et
## pression des lois sur l'opinion. Appelé au bilan mensuel, après refresh.
@warning_ignore("integer_division")
static func monthly(state: GameState, added: Array[Dictionary]) -> void:
	if not enabled(state):
		return
	var month := int(GameData.rules()["month_days"])
	var m := state.tick / month
	var quarter := m % 3 == 0
	var year := m % 12 == 0
	var killers := {}
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.species.is_empty() or GameState.is_npc(c.owner) or not c.is_established():
			continue
		for fid in _sorted_keys(c.species):
			var st := status(state, c.owner, fid)
			var n := int(c.species.get(fid, 0))
			if n <= 0:
				continue
			if st == "extermines" or (st == "expulses" and quarter):
				if c.population <= 1:
					continue
				c.species[fid] = n - 1
				c.population -= 1
				# Les expulsés deviennent des réfugiés ; un exterminé sur deux parvient à fuir.
				if st == "expulses" or posmod(m + pid, 2) == 0:
					Movements.flee_from(state, state.galaxy.get_planet(pid).system_id, fid, 1, c.owner, added)
				if st == "extermines":
					if not killers.has(c.owner):
						killers[c.owner] = {}
					killers[c.owner][fid] = true
			elif st == "assimiler" and year:
				c.species[fid] = n - 1
			elif year:
				var rate := integration_rate(state, c, fid)
				if rate > 0:
					c.integ[fid] = mini(100, integration(c, fid) + rate)
			if int(c.species.get(fid, 0)) <= 0:
				c.species.erase(fid)
		_clean_integ(c)
	for k in _sorted_keys(killers):
		var killer := int(k)
		for o in state.empires:
			if o.id == killer or o.eliminated:
				continue
			Diplomacy.remember(state, o.id, killer, "exterminator")
			if (killers[k] as Dictionary).has(o.faction_id):
				Diplomacy.remember(state, o.id, killer, "kin_exterminated")
	for e in state.empires:
		if e.eliminated or e.is_npc():
			continue
		_rights(state, e, added)
		if state.politics_on:
			var lean: Dictionary = Laws.effects(state, e.id).get("lean", {})
			for cur in _sorted_keys(lean):
				var i := Politics.index_of(String(cur))
				if i < 0:
					continue
				for sid in Stability.systems_of(state, e.id):
					Politics.push(state, sid, i, int(lean[cur]))


# --- Doléance « Des droits pour mon peuple » (proposition 14) ------------------------------------

static func _rights(state: GameState, e: Empire, added: Array[Dictionary]) -> void:
	var rc: Dictionary = data().get("rights", {})
	var all: Dictionary = state.peoples.get("rights", {})
	var key := str(e.id)
	var r: Dictionary = all.get(key, {})
	var changed := false
	if r.has("fid"):
		var fid := String(r["fid"])
		var done := status(state, e.id, fid) == "citoyens"
		if done or state.tick >= int(r["end"]):
			var v := int(rc.get("stability", 5)) if done else int(rc.get("stability_fail", -5))
			var fx: Array = r.get("fx", [])
			fx.append({"fid": fid, "v": v, "end": state.tick + int(rc.get("fx_days", 360))})
			r["fx"] = fx
			r.erase("fid")
			r.erase("end")
			r["next"] = state.tick + int(rc.get("cooldown", 360))
			changed = true
			if not e.is_ai():
				added.append(state.add_chronicle(("%s : les %s sont désormais citoyens. Ils le fêtent un an durant (+%d stabilité là où ils vivent)." if done else
						"%s : les %s n'ont pas obtenu leurs droits. Ils ne l'oublient pas de sitôt (%d stabilité là où ils vivent, un an).") % [
						e.short_name(), label(fid), absi(v) if done else v], Espionage.private_to(state, [e.id])))
	elif state.tick >= int(r.get("next", 0)):
		var pop := Laws.empire_pop(state, e.id)
		var best := ""
		var bn := 0
		var fp := foreign_pop(state, e.id)
		for fid in _sorted_keys(fp):
			var st := status(state, e.id, fid)
			if (st != "residents" and st != "assujettis") or not allowed_statuses(state, e.id, fid).has("citoyens"):
				continue
			if int(fp[fid]) * 100 >= int(rc.get("share_pct", 20)) * maxi(1, pop) and int(fp[fid]) > bn:
				best = fid
				bn = int(fp[fid])
		if best != "":
			r["fid"] = best
			r["end"] = state.tick + int(rc.get("days", 720))
			changed = true
			if not e.is_ai():
				added.append(state.add_chronicle("%s : doléance. Les %s (%d habitants) réclament la citoyenneté avant le %s (écran Colonies)." % [
						e.short_name(), label(best), bn, GameCalendar.date_string(int(r["end"]))], Espionage.private_to(state, [e.id])))
	var fx2: Array = r.get("fx", [])
	var keep := []
	for f: Dictionary in fx2:
		if int(f["end"]) > state.tick:
			keep.append(f)
	if keep.size() != fx2.size():
		r["fx"] = keep
		changed = true
	if r.has("fx") and (r["fx"] as Array).is_empty():
		r.erase("fx")
	if changed or not r.is_empty():
		if r.is_empty():
			all.erase(key)
		else:
			all[key] = r
		state.peoples["rights"] = all


## Demande de droits en cours d'un empire ({} aucune) : {"fid", "end"}.
static func rights_demand(state: GameState, empire_id: int) -> Dictionary:
	var r: Dictionary = (state.peoples.get("rights", {}) as Dictionary).get(str(empire_id), {})
	return {"fid": String(r["fid"]), "end": int(r["end"])} if r.has("fid") else {}


# --- Diplomatie (propositions 8, 10 et 15) ------------------------------------------------------

## Ce que l'empire a pense de b à cause du sort de ses compatriotes chez b : [[libellé, points], …].
static func opinion_parts(state: GameState, a: int, b: int) -> Array:
	var out := []
	if not enabled(state):
		return out
	var ea := state.get_empire(a)
	if ea == null:
		return out
	var fa := ea.faction_id
	if int(foreign_pop(state, b).get(fa, 0)) > 0:
		var st := status(state, b, fa)
		var v := int(status_def(st).get("opinion", 0))
		if st == "citoyens":
			v = int(Movements.data().get("citizen_opinion", 3))
		if v != 0:
			out.append(["Les nôtres chez eux : %s" % status_label(st).to_lower(), v])
	if not state.heroes.is_empty():
		for id in Heroes.ids_of(state, b):
			var h: Dictionary = state.heroes[id]
			if String(h.get("sp", "")) == fa and not Heroes.is_prisoner(h):
				out.append(["Un des nôtres sert au Panthéon (%s)" % String(h["name"]), int(data().get("hero_opinion", 5))])
				break
	return out


## Les espèces citoyennes d'autres peuples qu'un empire peut proposer comme héros, avec leur poids.
static func hero_species(state: GameState, empire_id: int) -> Dictionary:
	var out := {}
	if not enabled(state):
		return out
	var fp := foreign_pop(state, empire_id)
	for fid in _sorted_keys(fp):
		if int(fp[fid]) > 0 and status(state, empire_id, fid) == "citoyens":
			out[fid] = int(fp[fid])
	return out


# --- Sauvegarde ---------------------------------------------------------------------------------

## Clés de state.peoples : "coll" (paliers de collection), "colonists" (espèces colonisatrices),
## "pop" (habitants des autres espèces par empire), "status" ({empire: {espèce: statut}}, seulement
## les statuts choisis), "changed" ({empire: {espèce: jour du dernier changement}}), "rights"
## ({empire: {"fid", "end"} demande en cours, "next", "fx": [{"fid", "v", "end"}]}).
const KEYS := ["coll", "colonists", "pop", "status", "changed", "rights"]


static func setup(state: GameState, mode: String) -> void:
	state.peoples_on = mode == "actifs"
	state.peoples = {}
	for k in KEYS:
		state.peoples[k] = {}


static func to_dict(state: GameState) -> Dictionary:
	var d := {"on": state.peoples_on}
	for k in KEYS:
		d[k] = (state.peoples.get(k, {}) as Dictionary).duplicate(true)
	return d


static func from_dict(state: GameState, d: Dictionary) -> void:
	state.peoples_on = bool(d.get("on", false))
	state.peoples = {}
	for k in KEYS:
		state.peoples[k] = (d.get(k, {}) as Dictionary).duplicate(true)
	# Les jours et les valeurs relus du JSON sont des flottants : on les remet en entiers.
	for eid in state.peoples["changed"]:
		var m: Dictionary = state.peoples["changed"][eid]
		for fid in m:
			m[fid] = int(m[fid])
	for eid in state.peoples["pop"]:
		var m: Dictionary = state.peoples["pop"][eid]
		for fid in m:
			m[fid] = int(m[fid])
	for eid in state.peoples["coll"]:
		var m: Dictionary = state.peoples["coll"][eid]
		for fid in m:
			m[fid] = int(m[fid])
	for eid in state.peoples["rights"]:
		var r: Dictionary = state.peoples["rights"][eid]
		for k in ["end", "next"]:
			if r.has(k):
				r[k] = int(r[k])
		var fx: Array = r.get("fx", [])
		for f: Dictionary in fx:
			f["v"] = int(f["v"])
			f["end"] = int(f["end"])


static func _sorted_keys(d: Dictionary) -> Array:
	var k := d.keys()
	k.sort()
	return k
