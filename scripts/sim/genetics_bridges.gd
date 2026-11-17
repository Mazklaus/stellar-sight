class_name GeneticsBridges
extends RefCounted
## Ingénierie des espèces : lots 2 et 3 et ponts vers les autres piliers (voir Genetics).
##
## Lot 2 : lignées façonnées (prop. 15), abrutissement (20), greffe par sacrifice (21), Nomos
## « Génome » (Libre ingénierie, Convention de l'intégrité, Moratoire génétique ; prop. 28),
## « Profanation de notre sang » (29), Grande Maison à souche génétique (32), cliniques du Syndicat (37).
## Lot 3 : hybrides (22), don génétique aux peuples mineurs (23), mutations et lignée qui dérive (30),
## héritiers façonnés (31), « Voler un génome » et « Contaminer les cuves » (35), échantillons de
## créatures (36), statistiques des hauts faits (38).


static func cfg(section: String) -> Dictionary:
	return Genetics.cfg(section)


static func c_int(section: String, key: String, def := 0) -> int:
	return Genetics.c_int(section, key, def)


static func _h(state: GameState, parts: Array) -> int:
	return absi(hash([state.seed_value] + parts))


# --- Nomos, cour, contamination -----------------------------------------------------------------

## Le Moratoire génétique de l'Amphictyonie gèle-t-il les programmes de cet empire (s'il en est membre) ?
static func moratorium(state: GameState, eid: int) -> bool:
	return _amph_ban(state, eid, "gen_moratorium")


static func _amph_ban(state: GameState, eid: int, kind: String) -> bool:
	if state.amph.is_empty() or not Amphictyony.founded(state) or not Amphictyony.is_member(state, eid):
		return false
	return Amphictyony.banned(state, kind)


## Remise (négative) des ponts : Libre ingénierie du Nomos, Grande Maison à souche génétique en faveur.
static func cost_pct(state: GameState, eid: int) -> int:
	var pct := 0
	if not state.amph.is_empty() and Amphictyony.founded(state) and Amphictyony.is_member(state, eid):
		pct += Amphictyony.level_sum(state, "gen_cost_pct")
	if state.faith_on and _faith_precept(state, eid, "chair_argile"):
		pct += int(Faiths.precept_def("chair_argile").get("gen_cost_pct", -20))
	if state.politics_on and Laws.is_enacted(state, eid, "eugenisme_etat"):
		pct += -25
	if not state.court.is_empty():
		var voc := String(cfg("court").get("house_trait", "lignee_souche"))
		for h: Dictionary in Court.houses(state, eid):
			if String(h.get("voc", "")) == voc and Court.favor(h) >= c_int("court", "favor", 60):
				pct += c_int("court", "cost_pct", -20)
				break
	return pct


## La foi d'État de l'empire suit-elle ce précepte ?
static func _faith_precept(state: GameState, eid: int, pid: String) -> bool:
	if not state.faith_on or not Faiths.has_state_faith(state, eid):
		return false
	return Faiths.has_precept(state, Faiths.state_faith(state, eid), pid)


## « Sainteté de la chair » : l'espèce fondatrice ne se façonne pas.
static func flesh_sacred(state: GameState, eid: int, fid: String) -> bool:
	var e := state.get_empire(eid)
	return e != null and fid == e.faction_id and _faith_precept(state, eid, "saintete_chair")


static func contaminated(state: GameState, eid: int) -> bool:
	return state.tick < int(Genetics.sub(state, "contam").get(str(eid), 0))


## Nomos « Intégrité des peuples » : pas de programme sur une espèce fondatrice d'un autre empire.
static func foreign_banned(state: GameState, eid: int, fid: String) -> bool:
	if not _amph_ban(state, eid, "gen_foreign"):
		return false
	for o in state.empires:
		if o.id != eid and not o.eliminated and o.faction_id == Genetics.root(fid):
			return true
	return false


# --- Après un programme --------------------------------------------------------------------------

## Programme achevé : grief des empires dont on a façonné l'espèce, mutation possible, hauts faits.
static func on_program(state: GameState, eid: int, fid: String, p: Dictionary, added: Array[Dictionary]) -> void:
	var base := Genetics.root(fid)
	for o in state.empires:
		if o.id != eid and not o.eliminated and o.faction_id == base:
			Diplomacy.remember(state, o.id, eid, "gen_profanation")
	_mutation(state, eid, fid, p, added)
	_deed_stats(state, eid)


## Prop. 30 : un programme sur quinze environ mute (trait génétique de plus, au hasard, sans coût).
static func _mutation(state: GameState, eid: int, fid: String, p: Dictionary, added: Array[Dictionary]) -> void:
	if _h(state, ["mut", eid, int(p.get("id", 0))]) % 100 >= c_int("events", "mutation_pct", 8):
		return
	var e := state.get_empire(eid)
	var f := Genetics.fiche(state, eid, fid)
	if not Genetics.voies_of(f).has("genetique"):
		return
	var cur := Genetics.traits_of(f)
	var pool: Array[String] = []
	for t: Dictionary in Genetics.catalogue():
		if String(t["voie"]) == "genetique" and int(t.get("cost", 0)) <= 1 and not cur.has(String(t["id"])):
			var clash := false
			for o in t.get("opposes", []):
				clash = clash or cur.has(String(o))
			if not clash:
				pool.append(String(t["id"]))
	if pool.is_empty():
		return
	var tid := pool[_h(state, ["mutw", eid, int(p.get("id", 0))]) % pool.size()]
	var g := Genetics.preview_genome(e.genome.get(fid, {}), [tid], [], "")
	Genetics._set_genome(state, e, fid, g)
	Genetics._stat(state, eid, "mutations", 1)
	added.append(state.add_chronicle("Mutation dans les cuves de %s : les %s naissent %s. Personne ne l'a demandé ; personne ne se plaint, pour l'instant." % [
			e.display_name(), Genetics.label(state, eid, fid), Genetics.trait_label(tid).to_lower()], Espionage.private_to(state, [eid])))


## Statistiques lues par les hauts faits (traits d'une espèce, espèces façonnées).
static func _deed_stats(state: GameState, eid: int) -> void:
	var e := state.get_empire(eid)
	var key := str(eid)
	var st: Dictionary = Genetics.sub(state, "st").get(key, {})
	st["founder_traits"] = Genetics.counted_traits(Genetics.traits_of(e.faction()))
	var n := 0
	for k in e.genome:
		if not (e.genome[k] as Dictionary).is_empty():
			n += 1
	n += lineages_of(state, eid).size()
	st["shaped"] = n
	Genetics.sub(state, "st")[key] = st


## Programmes d'un autre type que mod / cyber / transfer.
static func complete_other(state: GameState, eid: int, p: Dictionary, added: Array[Dictionary]) -> void:
	var e := state.get_empire(eid)
	match String(p.get("kind", "")):
		"lineage":
			_make_lineage(state, eid, p, added)
		"staple":
			var fid := String(p["fid"])
			var g := Genetics.preview_genome(e.genome.get(fid, {}), ["g_abrutis"], [], "")
			Genetics._set_genome(state, e, fid, g)
			Genetics._stat(state, eid, "stapled", 1)
			for o in state.empires:
				if o.id != eid and not o.eliminated and o.faction_id == fid:
					Diplomacy.remember(state, o.id, eid, "gen_profanation")
			added.append(state.add_chronicle("Les %s de %s sont abrutis : ils travaillent mieux et ne demandent plus rien. On n'entend plus que les machines." % [
					Genetics.label(state, eid, fid), e.display_name()], Espionage.private_to(state, [eid])))
		"heir":
			_heirs(state, eid, added)
		"gift":
			var mid := int(p.get("minor", -1))
			if Minors.enabled(state) and not Minors.get_m(state, mid).is_empty():
				Minors.add_fav(state, mid, eid, c_int("gift", "relation", 40))
				Genetics._stat(state, eid, "gifts", 1)
				added.append(state.add_chronicle("%s offre aux %s un programme génétique : récoltes plus riches, enfants plus sains. La reconnaissance est sincère, la dépendance aussi." % [
						e.display_name(), Minors.name_of(state, mid)], Espionage.private_to(state, [eid])))
	_deed_stats(state, eid)


# --- Lignées (prop. 15) -------------------------------------------------------------------------

static func lineages_of(state: GameState, eid: int, base := "") -> Array[String]:
	var out: Array[String] = []
	var lin := Genetics.sub(state, "lin")
	var ks := lin.keys()
	ks.sort()
	for lid in ks:
		var l: Dictionary = lin[lid]
		if int(l.get("owner", -1)) == eid and (base == "" or String(l.get("base", "")) == base):
			out.append(String(lid))
	return out


static func check_lineage(state: GameState, eid: int, fid: String, add: Array, rem: Array) -> String:
	if not Genetics.full(state) or not state.peoples_on:
		return "les lignées demandent l'ingénierie complète et les populations mêlées"
	var e := state.get_empire(eid)
	if e.gene_path == "purete":
		return "votre serment de Pureté interdit tout programme"
	if moratorium(state, eid):
		return "le Moratoire génétique de l'Amphictyonie interdit tout programme"
	if Genetics.is_lineage(fid) or not Genetics.species_of(state, eid).has(fid):
		return "cette espèce ne vit pas chez vous"
	if lineages_of(state, eid, fid).size() >= c_int("lineage", "max", 2):
		return "%d lignées au plus par espèce" % c_int("lineage", "max", 2)
	if Genetics.programs(state, eid).size() >= Genetics.max_programs(state, eid):
		return "déjà %d programme(s) en cours" % Genetics.max_programs(state, eid)
	if add.is_empty() and rem.is_empty():
		return "une lignée doit différer de son espèce"
	if _biggest_colony(state, eid, fid) == null:
		return "il faut au moins 2 habitants de cette espèce sur un monde"
	var base := Genetics.fiche(state, eid, fid)
	var voies := Genetics.voies_of(base, e.gene_path)
	var synth := String(FactionTraits.species(base).get("archetype", "")) == "synthetique"
	var cur := Genetics.traits_of(base)
	var pts := 0
	for tid in add:
		var t := Genetics.trait_def(String(tid))
		if t.is_empty() or cur.has(String(tid)):
			return "trait impossible : %s" % Genetics.trait_label(String(tid))
		var v := String(t.get("voie", "creation"))
		if v == "special" or (v != "creation" and not voies.has(v)):
			return "%s : voie fermée à cette espèce" % Genetics.trait_label(String(tid))
		var need := Genetics._power_for_add(String(tid), synth)
		if not Genetics.has_power(state, eid, need):
			return "%s demande la technologie %s" % [Genetics.trait_label(String(tid)), Research.tech(Genetics.tech_for(need)).get("label", need)]
		for o in t.get("opposes", []):
			if cur.has(String(o)) and not rem.has(String(o)):
				return "%s et %s s'excluent" % [Genetics.trait_label(String(tid)), Genetics.trait_label(String(o))]
		pts += int(t.get("cost", 0))
	for tid in rem:
		if not cur.has(String(tid)):
			return "%s : l'espèce ne l'a pas" % Genetics.trait_label(String(tid))
		pts -= Genetics.trait_cost(String(tid))
	var after := Genetics.apply_genome(base, Genetics.preview_genome({}, add, rem, ""), "", false)
	if Genetics.counted_traits(Genetics.traits_of(after)) > Genetics.trait_cap(state, eid, fid):
		return "%d traits au plus pour cette espèce" % Genetics.trait_cap(state, eid, fid)
	if pts > Genetics.margin_left(state, eid, fid):
		return "marge dépassée de %d point(s)" % (pts - Genetics.margin_left(state, eid, fid))
	return ""


@warning_ignore("integer_division")
static func lineage_cost(state: GameState, eid: int, fid: String, add: Array, rem: Array) -> int:
	var pop := maxi(1, Genetics.pop_of(state, eid, fid))
	var v := c_int("cost", "lineage_base", 80) + c_int("cost", "per_pop", 2) * pop + c_int("cost", "per_point", 10) * maxi(1, pop / 2) * Genetics.points_changed(add, rem)
	return maxi(1, v * (100 + Genetics.cost_pct(state, eid, Genetics.voie_of_change(state, eid, fid, add))) / 100)


static func start_lineage(state: GameState, eid: int, fid: String, add: Array, rem: Array) -> void:
	var p := Genetics._new_prog(state, eid, "lineage", fid, lineage_cost(state, eid, fid, add, rem), Genetics.resource_for(state, eid, fid))
	p["add"] = add.duplicate()
	p["rem"] = rem.duplicate()


## Monde où vit le plus d'habitants de cette espèce (au moins 2) chez cet empire.
static func _biggest_colony(state: GameState, eid: int, fid: String) -> Colony:
	var best: Colony = null
	var best_n := 1
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner != eid or not c.is_colony() or not c.is_established():
			continue
		var n := int(Peoples.counts(state, c).get(fid, 0)) if not c.species.is_empty() else (c.population if fid == state.get_empire(eid).faction_id else 0)
		if n > best_n:
			best = c
			best_n = n
	return best


static func _make_lineage(state: GameState, eid: int, p: Dictionary, added: Array[Dictionary]) -> void:
	var e := state.get_empire(eid)
	var base := String(p["fid"])
	var c := _biggest_colony(state, eid, base)
	if c == null:
		return
	var n := int(state.genetics.get("seq", 1))
	state.genetics["seq"] = n + 1
	var lid := "%s~L~%d~%d" % [base, eid, n]
	var names: Array = ["Façonnés", "Nouvelle souche", "Cuvée", "Second jet", "Lignée claire", "Lignée sombre"]
	var nm := String(names[_h(state, ["lin", eid, n]) % names.size()])
	Genetics.sub(state, "lin")[lid] = {"base": base, "owner": eid, "name": nm, "add": (p.get("add", []) as Array).duplicate(), "rem": (p.get("rem", []) as Array).duplicate()}
	_write_lineage(state, lid)
	GameData.set_game_factions(state.custom_factions)
	# La moitié des habitants de l'espèce sur ce monde devient la lignée.
	var have := int(Peoples.counts(state, c).get(base, 0)) if not c.species.is_empty() else c.population
	@warning_ignore("integer_division")
	var moved := maxi(1, have / 2)
	if c.species.has(base):
		c.species[base] = int(c.species[base]) - moved
		if int(c.species[base]) <= 0:
			c.species.erase(base)
	c.species[lid] = int(c.species.get(lid, 0)) + moved
	Genetics._stat(state, eid, "lineages", 1)
	added.append(state.add_chronicle("Une lignée naît chez %s : les %s « %s » (%d habitants sur %s). Ils ressemblent à leurs parents, en mieux, disent-ils." % [
			e.display_name(), Peoples.label(base), nm, moved, state.galaxy.get_planet(c.planet_id).display_name(state.galaxy)], Espionage.private_to(state, [eid])))


## Fiche d'une lignée : celle de son espèce chez son empire, génome de la lignée posé dessus.
static func _write_lineage(state: GameState, lid: String) -> void:
	var l: Dictionary = Genetics.sub(state, "lin").get(lid, {})
	if l.is_empty():
		return
	var e := state.get_empire(int(l["owner"]))
	var base_f := Genetics.fiche(state, int(l["owner"]), String(l["base"])) if e != null else GameData.faction(String(l["base"]))
	var f := Genetics.apply_genome(base_f, {"add": l.get("add", []), "rem": l.get("rem", [])}, "", false).duplicate(true)
	f["id"] = lid
	f["name"] = "%s (%s)" % [String(base_f.get("name", l["base"])), String(l["name"])]
	f["short"] = "%s %s" % [String(base_f.get("short", l["base"])), String(l["name"]).to_lower()]
	f["lineage_of"] = String(l["base"])
	state.custom_factions[lid] = f


## Le génome d'une espèce a changé : ses lignées suivent (fid "" : toutes celles de l'empire).
static func refresh_lineages(state: GameState, eid: int, fid: String) -> void:
	if not Genetics.enabled(state):
		return
	var l := lineages_of(state, eid, fid)
	if l.is_empty():
		return
	for lid in l:
		_write_lineage(state, lid)
	GameData.set_game_factions(state.custom_factions)


# --- Abrutissement (prop. 20), greffe (prop. 21) ------------------------------------------------

static func check_staple(state: GameState, eid: int, fid: String) -> String:
	if not Genetics.full(state) or not state.peoples_on:
		return "l'abrutissement demande l'ingénierie complète et les populations mêlées"
	var e := state.get_empire(eid)
	if e.gene_path == "purete":
		return "votre serment de Pureté interdit tout programme"
	if moratorium(state, eid):
		return "le Moratoire génétique de l'Amphictyonie interdit tout programme"
	if _amph_ban(state, eid, "gen_staple"):
		return "la Convention de l'intégrité interdit l'abrutissement"
	if fid == e.faction_id or not Genetics.species_of(state, eid).has(fid):
		return "on n'abrutit que les autres espèces qui vivent chez vous"
	if Peoples.status(state, eid, fid) != String(cfg("stapling").get("status", "assujettis")):
		return "seuls les assujettis peuvent être abrutis"
	if not Genetics.has_power(state, eid, "reseq"):
		return "il faut la technologie %s" % Research.tech(Genetics.tech_for("reseq")).get("label", "")
	if not Genetics.is_organic(Genetics.fiche(state, eid, fid)):
		return "seuls les corps organiques s'abrutissent"
	if Genetics.traits_of(Genetics.fiche(state, eid, fid)).has("g_abrutis"):
		return "ils le sont déjà"
	if Genetics.programs(state, eid).size() >= Genetics.max_programs(state, eid):
		return "déjà %d programme(s) en cours" % Genetics.max_programs(state, eid)
	return ""


static func staple_cost(state: GameState, eid: int, fid: String) -> int:
	return Genetics.mod_cost(state, eid, fid, ["g_abrutis"], [], "")


## Habitants à sacrifier pour la prochaine greffe (2, puis 4, 6…).
static func graft_price(state: GameState, eid: int) -> int:
	return c_int("graft", "first", 2) + c_int("graft", "step", 2) * Genetics.stat(state, eid, "grafts")


## Bonus que la greffe d'une espèce donnerait : {ressource: points de pourcentage}.
@warning_ignore("integer_division")
static func graft_gain(state: GameState, eid: int, donor: String) -> Dictionary:
	var f := Genetics.fiche(state, eid, donor)
	var r := Genetics.strong_of(f)
	var over := int((f.get("production_pct", {}) as Dictionary).get(r, 100)) - 100
	if over < c_int("graft", "min_strong", 10):
		return {}
	return {r: over * c_int("graft", "share_pct", 50) / 100}


static func check_graft(state: GameState, eid: int, donor: String, free := false) -> String:
	if not Genetics.full(state) or not state.peoples_on:
		return "la greffe demande l'ingénierie complète et les populations mêlées"
	var e := state.get_empire(eid)
	if e.gene_path == "purete":
		return "votre serment de Pureté interdit tout programme"
	if moratorium(state, eid):
		return "le Moratoire génétique de l'Amphictyonie interdit tout programme"
	if donor == e.faction_id or Genetics.is_lineage(donor) or not Genetics.species_of(state, eid).has(donor):
		return "il faut une autre espèce qui vit chez vous"
	if not Genetics.is_organic(e.faction()) or not Genetics.is_organic(Genetics.fiche(state, eid, donor)):
		return "la greffe se fait entre corps organiques"
	if ((e.genome.get(e.faction_id, {}) as Dictionary).get("gdon", []) as Array).has(donor):
		return "vous avez déjà greffé cette espèce"
	if graft_gain(state, eid, donor).is_empty():
		return "cette espèce n'a pas de point fort à prendre"
	if not free and Genetics.pop_of(state, eid, donor) < graft_price(state, eid):
		return "il faut sacrifier %d habitants de cette espèce" % graft_price(state, eid)
	return ""


static func graft(state: GameState, eid: int, donor: String, added: Array[Dictionary], free := false) -> void:
	var e := state.get_empire(eid)
	var gain := graft_gain(state, eid, donor)
	if not free:
		var left := graft_price(state, eid)
		for pid in state.sorted_colony_ids():
			var c: Colony = state.colonies[pid]
			if left <= 0:
				break
			if c.owner != eid or not c.species.has(donor):
				continue
			var cut := mini(left, int(c.species[donor]))
			c.species[donor] = int(c.species[donor]) - cut
			if int(c.species[donor]) <= 0:
				c.species.erase(donor)
			c.population = maxi(1, c.population - cut)
			left -= cut
			Peoples.normalize(c)
	var g := (e.genome.get(e.faction_id, {}) as Dictionary).duplicate(true)
	var gr: Dictionary = g.get("graft", {})
	for r in gain:
		gr[r] = int(gr.get(r, 0)) + int(gain[r])
	g["graft"] = gr
	g["gfood"] = int(g.get("gfood", 0)) + c_int("graft", "food_pct", 5)
	g["gdon"] = (g.get("gdon", []) as Array) + [donor]
	Genetics._set_genome(state, e, e.faction_id, g)
	Genetics._stat(state, eid, "grafts", 1)
	added.append(state.add_chronicle("Greffe chez %s : les %s donnent ce qu'ils avaient de meilleur (%s). Ils n'avaient pas vraiment le choix." % [
			e.display_name(), Peoples.label(donor), GameData.format_amounts(gain, true)], Espionage.private_to(state, [eid])))
	_deed_stats(state, eid)


## L'Essaim digère un peuple (prop. 37, « Tout est biomasse ») : une greffe gratuite tous les n.
static func on_digest(state: GameState, eid: int, fid: String, added: Array[Dictionary]) -> void:
	if not Genetics.full(state) or not Genetics.applies(state, eid):
		return
	var n := int(Genetics.talent(state, eid).get("graft_digest", 0))
	if n <= 0:
		return
	var key := str(eid)
	var d := int(Genetics.sub(state, "digest").get(key, 0)) + 1
	Genetics.sub(state, "digest")[key] = d
	if d >= n and check_graft(state, eid, fid, true) == "":
		Genetics.sub(state, "digest")[key] = 0
		graft(state, eid, fid, added, true)


# --- Héritiers façonnés (prop. 31), don aux mineurs (prop. 23), cliniques (prop. 37) ------------

static func check_heir(state: GameState, eid: int) -> String:
	if state.rulers.is_empty() or not Rulers.hereditary(state, eid):
		return "il faut une dynastie héréditaire"
	if RulersDynasty.heirs(state, eid).is_empty():
		return "pas d'héritier à façonner"
	if not Genetics.has_power(state, eid, "add"):
		return "il faut la technologie %s" % Research.tech(Genetics.tech_for("add")).get("label", "")
	if state.get_empire(eid).gene_path == "purete":
		return "votre serment de Pureté interdit tout programme"
	if Genetics.programs(state, eid).size() >= Genetics.max_programs(state, eid):
		return "déjà %d programme(s) en cours" % Genetics.max_programs(state, eid)
	return ""


static func _heirs(state: GameState, eid: int, added: Array[Dictionary]) -> void:
	var mx := int(Rulers.data().get("apt_max", 6))
	var b := c_int("heir", "bonus", 1)
	for h: Dictionary in RulersDynasty.heirs(state, eid):
		var apt: Dictionary = h.get("apt", {})
		for k in apt:
			apt[k] = mini(mx, int(apt[k]) + b)
	Genetics._stat(state, eid, "heirs", 1)
	added.append(state.add_chronicle("Les héritiers de %s sortent des cuves de la cour : plus vifs, plus forts, plus beaux. Les précepteurs se sentent soudain inutiles." % [
			state.get_empire(eid).display_name()], Espionage.private_to(state, [eid])))


static func check_gift(state: GameState, eid: int, mid: int) -> String:
	if not Minors.enabled(state) or Minors.get_m(state, mid).is_empty():
		return "peuple mineur inconnu"
	if not Minors.can_talk(state, mid, eid):
		return "vous ne parlez pas avec ce peuple"
	if not Genetics.has_power(state, eid, "add"):
		return "il faut la technologie %s" % Research.tech(Genetics.tech_for("add")).get("label", "")
	if state.get_empire(eid).gene_path == "purete":
		return "votre serment de Pureté interdit tout programme"
	if Genetics.programs(state, eid).size() >= Genetics.max_programs(state, eid):
		return "déjà %d programme(s) en cours" % Genetics.max_programs(state, eid)
	return ""


## Traits façonnés que le Syndicat peut acheter : ceux des génomes des empires rencontrés.
static func clinic_offers(state: GameState, eid: int) -> Array[String]:
	var out: Array[String] = []
	if int(Genetics.talent(state, eid).get("clinics", 0)) <= 0:
		return out
	var have: Array = Genetics.sub(state, "stolen").get(str(eid), [])
	for o in state.empires:
		if o.id == eid or o.eliminated or not e_contacts(state, eid).has(o.id):
			continue
		for k in o.genome:
			for tid in (o.genome[k] as Dictionary).get("add", []):
				var t := Genetics.trait_def(String(tid))
				if String(t.get("voie", "")) in ["special", "creation"] or have.has(String(tid)) or out.has(String(tid)):
					continue
				out.append(String(tid))
	out.sort()
	return out


static func clinic_price(tid: String) -> int:
	return c_int("clinics", "energy_per_point", 120) * maxi(1, Genetics.trait_cost(tid))


static func check_clinic(state: GameState, eid: int, tid: String) -> String:
	if not clinic_offers(state, eid).has(tid):
		return "ce génome n'est pas à vendre"
	if int(state.get_empire(eid).resources.get("energy", 0)) < clinic_price(tid):
		return "il faut %d énergie" % clinic_price(tid)
	return ""


static func learn_trait(state: GameState, eid: int, tid: String) -> void:
	var key := str(eid)
	var l: Array = Genetics.sub(state, "stolen").get(key, [])
	if not l.has(tid):
		l.append(tid)
	Genetics.sub(state, "stolen")[key] = l


# --- Espionnage (prop. 35), créatures (prop. 36) ------------------------------------------------

## « Voler un génome » : un trait façonné de la cible, au hasard, devient possible chez le voleur.
static func steal_genome(state: GameState, thief: int, target: int, salt: Array) -> String:
	var t := state.get_empire(target)
	if t == null or not Genetics.enabled(state):
		return ""
	var have: Array = Genetics.sub(state, "stolen").get(str(thief), [])
	var pool: Array[String] = []
	var ks := t.genome.keys()
	ks.sort()
	for k in ks:
		for tid in (t.genome[k] as Dictionary).get("add", []):
			if not have.has(String(tid)) and not pool.has(String(tid)) and String(Genetics.trait_def(String(tid)).get("voie", "")) != "creation":
				pool.append(String(tid))
	if pool.is_empty():
		return ""
	var tid := pool[_h(state, salt + ["steal"]) % pool.size()]
	learn_trait(state, thief, tid)
	return tid


## « Contaminer les cuves » : les programmes de la cible s'arrêtent quelques mois.
static func contaminate(state: GameState, target: int) -> void:
	if Genetics.enabled(state):
		Genetics.sub(state, "contam")[str(target)] = state.tick + c_int("espionage", "contaminate_days", 60)


## Une flotte de l'empire abat une créature spatiale : échantillon (trait unique) si l'option est là.
static func on_creature_killed(state: GameState, eid: int, size: int) -> String:
	if not Genetics.applies(state, eid):
		return ""
	var ct := cfg("creature_traits")
	var tid := String(ct.get("big", "")) if size >= int(ct.get("big_from", 3)) else String(ct.get("small", ""))
	if tid == "":
		return ""
	var key := str(eid)
	var l: Array = Genetics.sub(state, "samples").get(key, [])
	if l.has(tid):
		return ""
	l.append(tid)
	Genetics.sub(state, "samples")[key] = l
	return tid


# --- Commandes du lot 2 et 3 ---------------------------------------------------------------------

static func check(state: GameState, eid: int, act: String, d: Dictionary) -> String:
	match act:
		"lineage":
			return check_lineage(state, eid, String(d.get("fid", "")), d.get("add", []), d.get("rem", []))
		"staple":
			return check_staple(state, eid, String(d.get("fid", "")))
		"graft":
			return check_graft(state, eid, String(d.get("fid", "")))
		"heir":
			return check_heir(state, eid)
		"gift":
			return check_gift(state, eid, int(d.get("minor", -1)))
		"clinic":
			return check_clinic(state, eid, String(d.get("trait", "")))
	return "ordre inconnu : %s" % act


static func apply(state: GameState, eid: int, act: String, d: Dictionary, added: Array[Dictionary]) -> void:
	var e := state.get_empire(eid)
	match act:
		"lineage":
			start_lineage(state, eid, String(d["fid"]), d.get("add", []), d.get("rem", []))
		"staple":
			Genetics._new_prog(state, eid, "staple", String(d["fid"]), staple_cost(state, eid, String(d["fid"])), "knowledge")
		"graft":
			graft(state, eid, String(d["fid"]), added)
		"heir":
			Genetics._new_prog(state, eid, "heir", e.faction_id, c_int("cost", "heir", 200), "knowledge")
		"gift":
			var p := Genetics._new_prog(state, eid, "gift", e.faction_id, c_int("cost", "gift", 150), "knowledge")
			p["minor"] = int(d["minor"])
		"clinic":
			var tid := String(d["trait"])
			e.resources["energy"] = int(e.resources.get("energy", 0)) - clinic_price(tid)
			learn_trait(state, eid, tid)


# --- Bilan mensuel : hybrides (prop. 22), lignée qui dérive (prop. 30) ---------------------------

static func monthly(state: GameState, added: Array[Dictionary]) -> void:
	if not Genetics.full(state) or not state.peoples_on:
		return
	@warning_ignore("integer_division")
	var month := state.tick / int(GameData.rules()["month_days"])
	# Une fois par an, à tour de rôle : la simulation reste légère.
	for e in state.empires:
		if e.eliminated or e.is_npc() or posmod(month + e.id, 12) != 0:
			continue
		_hybrids(state, e, added)
		_drift(state, e, added)


## Colonies où vivent deux espèces organiques d'affinité positive : chance d'une espèce hybride.
static func _hybrids(state: GameState, e: Empire, added: Array[Dictionary]) -> void:
	var hy := Genetics.sub(state, "hyb")
	var key := str(e.id)
	var born := int(hy.get(key, 0))
	if born >= c_int("hybrid", "max_per_empire", 3):
		return
	var chance := c_int("hybrid", "chance", 150) * maxi(1, int(Genetics.talent(state, e.id).get("hybrid_x", 1)))
	var min_each := c_int("hybrid", "min_each", 3)
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner != e.id or c.species.is_empty() or not c.is_colony():
			continue
		var cnt := Peoples.counts(state, c)
		var ids := cnt.keys()
		ids.sort()
		for i in ids.size():
			for j in range(i + 1, ids.size()):
				var a := String(ids[i])
				var b := String(ids[j])
				if int(cnt[a]) < min_each or int(cnt[b]) < min_each or Genetics.root(a) == Genetics.root(b):
					continue
				if a.find("~H~") > 0 or b.find("~H~") > 0:
					continue
				if not Genetics.is_organic(GameData.faction(a)) or not Genetics.is_organic(GameData.faction(b)) or Peoples.affinity(a, b) <= 0:
					continue
				if _h(state, ["hyb", e.id, pid, a, b, state.tick]) % 10000 >= chance:
					continue
				_make_hybrid(state, e, c, a, b, added)
				return


static func _make_hybrid(state: GameState, e: Empire, c: Colony, a: String, b: String, added: Array[Dictionary]) -> void:
	var n := int(state.genetics.get("seq", 1))
	state.genetics["seq"] = n + 1
	var hid := "%s~H~%s~%d~%d" % [Genetics.root(a), Genetics.root(b), e.id, n]
	var fa := GameData.faction(a)
	var fb := GameData.faction(b)
	var f := fa.duplicate(true)
	var pa: Dictionary = fa.get("production_pct", {})
	var pb: Dictionary = fb.get("production_pct", {})
	var pp := {}
	for r in pa.keys() + pb.keys():
		pp[r] = maxi(int(pa.get(r, 100)), int(pb.get(r, 100)))
	f["production_pct"] = pp
	f["id"] = hid
	var sa := String(fa.get("short", a))
	var sb := String(fb.get("short", b))
	f["name"] = "Hybrides %s-%s" % [sa, sb]
	f["short"] = "%s-%s" % [sa.substr(0, maxi(3, sa.length() / 2)), sb.to_lower()]
	f["hybrid_margin"] = c_int("hybrid", "margin", 1)
	f["hybrid_cap"] = c_int("hybrid", "cap", 1)
	f["hybrid_of"] = [a, b]
	var shown: Array = (f.get("traits", []) as Array).duplicate(true)
	shown.append({"name": "Hybride", "text": "Le meilleur des deux parents (production), un point de marge et un trait de plus."})
	f["traits"] = shown
	state.custom_factions[hid] = f
	GameData.set_game_factions(state.custom_factions)
	var moved := 0
	for x in [a, b]:
		var take := 1
		if c.species.has(x):
			c.species[x] = int(c.species[x]) - take
			if int(c.species[x]) <= 0:
				c.species.erase(x)
		moved += take
	c.species[hid] = int(c.species.get(hid, 0)) + moved
	Genetics.sub(state, "hyb")[str(e.id)] = int(Genetics.sub(state, "hyb").get(str(e.id), 0)) + 1
	Genetics._stat(state, e.id, "hybrids", 1)
	added.append(state.add_chronicle("Sur %s (%s), des enfants naissent qui ne sont ni %s ni %s : on les appelle les %s. Ils ont les yeux de l'un et l'appétit de l'autre." % [
			state.galaxy.get_planet(c.planet_id).display_name(state.galaxy), e.display_name(), sa, sb, String(f["name"])], Espionage.private_to(state, [e.id])))


## Une lignée de plus de drift_points points changés dérive : elle gagne un trait au hasard.
static func _drift(state: GameState, e: Empire, added: Array[Dictionary]) -> void:
	for lid in lineages_of(state, e.id):
		var l: Dictionary = Genetics.sub(state, "lin")[lid]
		if Genetics.points_changed(l.get("add", []), l.get("rem", [])) < c_int("events", "drift_points", 4):
			continue
		if _h(state, ["drift", lid, state.tick]) % 100 >= 25:
			continue
		var cur := Genetics.traits_of(GameData.faction(lid))
		var pool: Array[String] = []
		for t: Dictionary in Genetics.catalogue():
			if String(t["voie"]) in ["genetique", "pousses"] and not cur.has(String(t["id"])):
				pool.append(String(t["id"]))
		if pool.is_empty():
			continue
		var tid := pool[_h(state, ["driftw", lid, state.tick]) % pool.size()]
		(l["add"] as Array).append(tid)
		_write_lineage(state, lid)
		GameData.set_game_factions(state.custom_factions)
		added.append(state.add_chronicle("La lignée qui dérive : les %s de %s changent encore, d'eux-mêmes (%s). Les généticiens prennent des notes et des calmants." % [
				String(GameData.faction(lid).get("short", lid)), e.display_name(), Genetics.trait_label(tid).to_lower()], Espionage.private_to(state, [e.id])))


static func e_contacts(state: GameState, eid: int) -> Array:
	var e := state.get_empire(eid)
	return e.contacts if e != null else []
