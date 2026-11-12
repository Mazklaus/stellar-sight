class_name Victory
extends RefCounted
## Les conditions de victoire : fonctions pures qui LISENT l'état (data/victories.json).
## VictorySystem fait avancer les comptes à rebours et proclame le vainqueur ; l'interface affiche
## les mêmes avancées avec les mêmes règles.
##
## - Trois victoires classiques, ouvertes à tous : conquête (capitales d'origine), domination (part
##   des systèmes tenue un temps), score (le meilleur à la date limite).
## - Des victoires de peuple, qui demandent des couches d'espèce (requires, comme les talents
##   diplomatiques : FactionTraits.species_matches) et une technologie de Société de l'ère IV.
##   Un peuple personnalisé qui a la bonne couche y a droit.
## - Avancée en pourcentage : sous met_at (75), on approche ; à met_at la condition est remplie et le
##   compte à rebours tourne (victoires « à tenir ») ; 100 = victoire. Une victoire de peuple se voit
##   des autres dès visible_at (50), et toutes donnent une alerte à 50 et 75 (Endless Space 2).

const SCORE := "score"


static func data() -> Dictionary:
	return GameData.victories()


static func info(id: String) -> Dictionary:
	return data().get("victories", {}).get(id, {})


static func label(id: String) -> String:
	return String(info(id).get("label", id))


## Toutes les victoires, dans l'ordre des données (classiques d'abord).
static func ids() -> Array[String]:
	var out: Array[String] = []
	for k in data().get("victories", {}):
		out.append(String(k))
	return out


static func is_people(id: String) -> bool:
	return String(info(id).get("kind", "")) == "people"


static func met_at() -> int:
	return int(data().get("met_at", 75))


static func visible_at() -> int:
	return int(data().get("visible_at", 50))


## Texte de la règle, avec ses chiffres.
static func rule_text(id: String) -> String:
	var v := info(id)
	var t := String(v.get("text", ""))
	@warning_ignore("integer_division")
	var years := int(v.get("hold_days", 0)) / GameCalendar.DAYS_PER_YEAR
	match id:
		"domination":
			return t % [int(v["systems_pct"]), int(v["ally_pct"]), years]
		"elu":
			return t % [years, int(v["heir_min"])]
		"couplet":
			return t % [int(v["sites"]), int(v["sites"]), years]
		"charte":
			return t % [int(v["min_signatories"]), years]
		"moisson":
			return t % [int(v["pop_share_pct"]), int(v["digested"]), years]
		"noosphere":
			return t % [int(v["nodes"]), years]
		"terre_promise":
			return t % [int(v["min_jumps"]), int(v["reveal_jumps"]), maxi(1, years)]
		"legende":
			return t % [int(v["exploits"]), int(v["min_reputation"]), maxi(1, years)]
		"silence":
			return t % [int(v["colonies"]), years]
	return t


# --- Règles de la partie -----------------------------------------------------------------------

static func deadline_options() -> Array:
	return data().get("deadlines", [])


static func deadline_days_for(option_id: String) -> int:
	for d: Dictionary in deadline_options():
		if String(d["id"]) == option_id:
			return int(d["days"])
	return -1


static func default_deadline() -> int:
	return maxi(0, deadline_days_for(String(data().get("default_deadline", ""))))


## Date limite de la partie en jours (0 = sans date limite).
static func deadline(state: GameState) -> int:
	return int(state.victory_rules.get("deadline", 0))


static func people_enabled(state: GameState) -> bool:
	return bool(state.victory_rules.get("people", true))


## La victoire est-elle en jeu dans cette partie (réglages de la nouvelle partie) ?
static func enabled(state: GameState, id: String) -> bool:
	if info(id).is_empty():
		return false
	if id == SCORE:
		return deadline(state) > 0
	if is_people(id):
		return people_enabled(state)
	return bool(state.victory_rules.get(id, true))


## Les alliés avancent-ils ensemble vers la conquête et la domination (réglage de la partie) ?
static func allies_count(state: GameState) -> bool:
	return bool(state.victory_rules.get("allies", true))


## Victoires de peuple auxquelles une faction (ou un peuple personnalisé) a droit, par ses couches.
static func people_ids_for(faction: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for id in ids():
		if is_people(id) and FactionTraits.species_matches(faction, info(id).get("requires", {})):
			out.append(id)
	return out


## L'empire peut-il gagner ainsi ?
static func applies(state: GameState, empire_id: int, id: String) -> bool:
	var e := state.get_empire(empire_id)
	if e == null or not enabled(state, id):
		return false
	if is_people(id):
		return FactionTraits.species_matches(e.faction(), info(id).get("requires", {}))
	return true


## Victoires que l'empire peut viser dans cette partie.
static func ids_for(state: GameState, empire_id: int) -> Array[String]:
	var out: Array[String] = []
	for id in ids():
		if applies(state, empire_id, id):
			out.append(id)
	return out


## Technologie qui ouvre une victoire de peuple ("" pour une classique).
static func tech_for(id: String) -> String:
	return String(info(id).get("tech", ""))


## Technologies de victoire de ce peuple (l'IA les met en tête de recherche).
static func people_techs(faction: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for id in people_ids_for(faction):
		if tech_for(id) != "":
			out.append(tech_for(id))
	return out


static func has_tech(state: GameState, empire_id: int, id: String) -> bool:
	var t := tech_for(id)
	return t == "" or Research.knows(state, empire_id, t)


# --- Avancée -----------------------------------------------------------------------------------

## Compte à rebours déjà tenu (jours) pour une victoire à tenir.
static func held(state: GameState, empire_id: int, id: String) -> int:
	var e := state.get_empire(empire_id)
	return int(e.victory.get(id, {}).get("held", 0)) if e else 0


## Dernière avancée calculée par VictorySystem (au bilan mensuel), en pourcentage.
static func cached_pct(state: GameState, empire_id: int, id: String) -> int:
	var e := state.get_empire(empire_id)
	return int(e.victory.get(id, {}).get("pct", 0)) if e else 0


## Plus forte avancée connue d'un empire, toutes victoires confondues sauf le score.
static func best_cached(state: GameState, empire_id: int) -> Dictionary:
	var best := {"id": "", "pct": 0}
	var e := state.get_empire(empire_id)
	if e == null or e.eliminated:
		return best
	for id in ids():
		if id == SCORE or not e.victory.has(id):
			continue
		var p := int(e.victory[id].get("pct", 0))
		if p > int(best["pct"]):
			best = {"id": id, "pct": p}
	return best


## Avancée de l'empire vers une victoire :
## {"pct": 0-100, "cond": condition remplie (le compte à rebours avance), "keep": la condition manque
##  mais le compte à rebours est gardé (pause), "won": victoire acquise, "lines": [texte],
##  "hold": durée à tenir (0 = immédiate), "held": déjà tenu}.
static func progress(state: GameState, empire_id: int, id: String) -> Dictionary:
	var out := {"pct": 0, "cond": false, "keep": false, "won": false, "lines": [], "hold": int(info(id).get("hold_days", 0)), "held": held(state, empire_id, id)}
	var e := state.get_empire(empire_id)
	if e == null or e.eliminated:
		return out
	match id:
		"conquete":
			_conquest(state, e, out)
		"domination":
			_domination(state, e, out)
		"score":
			_score_progress(state, e, out)
		"elu":
			_elu(state, e, out)
		"couplet":
			_couplet(state, e, out)
		"charte":
			_charte(state, e, out)
		"moisson":
			_moisson(state, e, out)
		"noosphere":
			_noosphere(state, e, out)
		"terre_promise":
			_terre_promise(state, e, out)
		"legende":
			_legende(state, e, out)
		"silence":
			_silence(state, e, out)
	if is_people(id) and not has_tech(state, empire_id, id):
		out["lines"].append("Technologie requise : %s" % String(Research.tech(tech_for(id)).get("label", tech_for(id))))
		out["cond"] = false
		out["won"] = false
		out["pct"] = mini(int(out["pct"]), met_at() - 1)
	return out


## Avancée d'une victoire à tenir : approche (0 à met_at - 1), puis met_at à 100 avec le temps tenu.
static func _timed(out: Dictionary, done: int, needed: int) -> void:
	var hold := maxi(1, int(out["hold"]))
	if out["cond"] or (out["keep"] and int(out["held"]) > 0):
		@warning_ignore("integer_division")
		out["pct"] = mini(100, met_at() + (100 - met_at()) * int(out["held"]) / hold)
		var left := maxi(0, hold - int(out["held"]))
		out["lines"].append(("Compte à rebours : %s" if out["cond"] else "Compte à rebours en pause : %s") % _days_text(left))
	else:
		@warning_ignore("integer_division")
		out["pct"] = (met_at() - 1) * mini(done, needed) / maxi(1, needed)


## Avancée d'une victoire immédiate : la part atteinte, 100 seulement une fois acquise.
static func _instant(out: Dictionary, done: int, needed: int) -> void:
	@warning_ignore("integer_division")
	out["pct"] = 100 if out["won"] else mini(99, 100 * mini(done, needed) / maxi(1, needed))


static func _days_text(days: int) -> String:
	if days >= GameCalendar.DAYS_PER_YEAR:
		@warning_ignore("integer_division")
		var y := days / GameCalendar.DAYS_PER_YEAR
		@warning_ignore("integer_division")
		var m := (days % GameCalendar.DAYS_PER_YEAR) / GameCalendar.DAYS_PER_MONTH
		return "%d an%s%s" % [y, "s" if y > 1 else "", (" %d mois" % m) if m > 0 else ""]
	@warning_ignore("integer_division")
	var mo := days / GameCalendar.DAYS_PER_MONTH
	return "%d mois" % mo if mo > 0 else "%d jours" % days


static func _owner_of(state: GameState, planet_id: int) -> int:
	var c: Colony = state.colonies.get(planet_id)
	return c.owner if c != null else -1


## Bloc d'un empire pour la conquête et la domination : lui et ses alliés encore en vie (Endless
## Space 2 : les alliés avancent ensemble vers ces victoires, et les gagnent ensemble). Lui seul si la
## partie fait jouer chaque allié pour lui-même.
static func bloc(state: GameState, empire_id: int) -> Array[int]:
	var out: Array[int] = [empire_id]
	for a in Diplomacy.allies(state, empire_id):
		# Les coéquipiers gagnent toujours ensemble ; les autres alliés si la partie le permet.
		if not allies_count(state) and Diplomacy.team_of(state, empire_id, a) <= 0:
			continue
		if not state.get_empire(a).eliminated and not out.has(a):
			out.append(a)
	out.sort()
	return out


static func _conquest(state: GameState, e: Empire, out: Dictionary) -> void:
	var b := bloc(state, e.id)
	var targets := 0
	var held_caps := 0
	var alive := 0
	for o in state.empires:
		if b.has(o.id):
			continue
		targets += 1
		if not o.eliminated:
			alive += 1
		if FactionTraits.has_horde(o.faction()):
			# Horde : sa capitale est la flotte-ville ; elle compte comme prise une fois abattue.
			if FactionTraits.city_fleet(state, o.id) == null:
				held_caps += 1
		elif o.home_planet >= 0 and b.has(_owner_of(state, o.home_planet)):
			held_caps += 1
	var own_ok := e.home_planet < 0 or b.has(_owner_of(state, e.home_planet))
	if FactionTraits.has_horde(e.faction()):
		own_ok = FactionTraits.city_fleet(state, e.id) != null
	if b.size() > 1:
		out["lines"].append("Alliés : %d (leurs conquêtes comptent)" % (b.size() - 1))
	out["lines"].append("Capitales rivales tenues : %d / %d" % [held_caps, targets])
	out["lines"].append("Capitale d'origine : %s" % ("tenue" if own_ok else "PERDUE, à reprendre"))
	if targets > 0 and alive == 0:
		out["lines"].append("Seuls encore en vie" if b.size() > 1 else "Seul empire encore en vie")
		out["won"] = true
	elif targets > 0 and held_caps == targets and own_ok:
		out["won"] = true
	_instant(out, held_caps if own_ok else mini(held_caps, targets - 1), targets)


## Systèmes où l'empire (ou, avec with_allies, son bloc) a une revendication fondée.
static func systems_held(state: GameState, empire_id: int, with_allies := false) -> int:
	var b: Array[int] = bloc(state, empire_id) if with_allies else ([empire_id] as Array[int])
	var seen := {}
	for pid in state.colonies:
		var c: Colony = state.colonies[pid]
		if b.has(c.owner) and c.is_established():
			seen[state.galaxy.get_planet(pid).system_id] = true
	return seen.size()


## Systèmes à tenir pour la domination : la part de base, plus ally_pct par allié (au plus max_pct).
static func domination_needed(state: GameState, empire_id := -1) -> int:
	var v := info("domination")
	var allies := bloc(state, empire_id).size() - 1 if empire_id >= 0 else 0
	var pct := mini(int(v.get("max_pct", 100)), int(v["systems_pct"]) + allies * int(v.get("ally_pct", 0)))
	return ceili(state.galaxy.systems.size() * pct / 100.0)


static func _domination(state: GameState, e: Empire, out: Dictionary) -> void:
	var have := systems_held(state, e.id, true)
	var need := domination_needed(state, e.id)
	if bloc(state, e.id).size() > 1:
		out["lines"].append("Avec %d allié%s : il en faut davantage" % [bloc(state, e.id).size() - 1, "s" if bloc(state, e.id).size() > 2 else ""])
	out["lines"].append("Systèmes tenus : %d / %d" % [have, need])
	out["cond"] = have >= need
	_timed(out, have, need)


## Score d'un empire (barème de data/victories.json) : population, revendications, technologies,
## faits d'armes, exploration, et un peu de l'avancée de sa victoire de peuple.
static func score(state: GameState, empire_id: int) -> int:
	var e := state.get_empire(empire_id)
	if e == null:
		return 0
	var s: Dictionary = data().get("score", {})
	var pts := 0
	for pid in state.colonies:
		var c: Colony = state.colonies[pid]
		if c.owner != empire_id or not c.is_established():
			continue
		pts += c.population * int(s.get("pop", 2)) + int(s.get("colony", 10) if c.is_colony() else s.get("outpost", 4))
	pts += e.techs.size() * int(s.get("tech", 5))
	# Merveilles et mégastructures (data/buildings.json, champ score).
	var w := Economy.wonders(state)
	for key in w:
		if int(w[key]) == empire_id:
			pts += int(GameData.building(String(key).get_slice("#", 0)).get("score", 0))
	pts += int(e.stats.get("kills", 0)) * int(s.get("kill", 2))
	pts += int(e.stats.get("conquests", 0)) * int(s.get("conquest", 10))
	if not state.relics.is_empty():
		pts += Relics.owned(state, empire_id).size() * int(Relics.rules()["score"])
	pts += Quests.score(state, empire_id)
	@warning_ignore("integer_division")
	pts += e.explored.size() / maxi(1, int(s.get("explored_div", 3)))
	var best := 0
	for id in ids():
		if is_people(id) and e.victory.has(id):
			best = maxi(best, int(e.victory[id].get("pct", 0)))
	@warning_ignore("integer_division")
	pts += mini(int(s.get("people_max", 50)), best / maxi(1, int(s.get("people_pct_div", 2))))
	return pts


## Classement par score des empires encore en vie : [{"id", "score"}], du meilleur au moins bon
## (à égalité, le plus petit identifiant d'abord).
static func ranking(state: GameState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in state.empires:
		if not e.eliminated:
			out.append({"id": e.id, "score": score(state, e.id)})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["score"] != b["score"]:
			return a["score"] > b["score"]
		return a["id"] < b["id"])
	return out


static func _score_progress(state: GameState, e: Empire, out: Dictionary) -> void:
	var rank := ranking(state)
	var pos := 1
	for i in rank.size():
		if int(rank[i]["id"]) == e.id:
			pos = i + 1
	out["lines"].append("Score : %d (rang %d sur %d)" % [score(state, e.id), pos, rank.size()])
	var dl := deadline(state)
	if dl > 0:
		out["lines"].append("Date limite : %s (dans %s)" % [GameCalendar.date_string(dl), _days_text(maxi(0, dl - state.tick))])
		@warning_ignore("integer_division")
		out["pct"] = mini(99, 100 * state.tick / dl) if pos == 1 else 0


# --- Victoires de peuple -----------------------------------------------------------------------

## Rivaux encore en vie qui signent des traités (les ruches qui ne vivent que pour survivre, non).
static func signing_rivals(state: GameState, empire_id: int) -> Array[int]:
	var out: Array[int] = []
	for o in state.empires:
		if o.id != empire_id and not o.eliminated and not Diplomacy.no_treaties(state, o.id):
			out.append(o.id)
	return out


## Les lignées de a et b sont-elles unies (union faite, alliance toujours en place) ?
static func united(state: GameState, a: int, b: int) -> bool:
	return int(Diplomacy.rel(state, a, b).get("union", 0)) > 0 and Diplomacy.allied(state, a, b)


static func unions_needed(state: GameState, empire_id: int) -> int:
	return maxi(int(info("elu")["min_unions"]), signing_rivals(state, empire_id).size())


static func union_count(state: GameState, empire_id: int) -> int:
	var n := 0
	for o in signing_rivals(state, empire_id):
		if united(state, empire_id, o):
			n += 1
	return n


static func _elu(state: GameState, e: Empire, out: Dictionary) -> void:
	var v := info("elu")
	var need := unions_needed(state, e.id)
	var have := union_count(state, e.id)
	out["lines"].append("Lignées unies : %d / %d" % [have, need])
	var loyal := e.heir_loyalty >= int(v["heir_min"])
	out["lines"].append("Héritier : %s" % ("aucun" if e.heir_loyalty < 0 else "loyauté %d (%d requis)" % [e.heir_loyalty, int(v["heir_min"])]))
	out["cond"] = have >= need and loyal
	_timed(out, have, need)


## Peut-on unir ses lignées à celles de target ? "" si oui, sinon la raison.
static func check_union(state: GameState, player: int, target: int) -> String:
	var v := info("elu")
	var e := state.get_empire(player)
	var t := state.get_empire(target)
	if e == null or t == null or player == target:
		return "empire inconnu"
	if not applies(state, player, "elu"):
		return "seule une dynastie féodale peut unir ses lignées"
	if not has_tech(state, player, "elu"):
		return "il faut la technologie %s" % String(Research.tech(tech_for("elu")).get("label", ""))
	if e.eliminated or t.eliminated:
		return "cet empire a disparu"
	if e.heir_loyalty < 0:
		return "pas d'héritier à marier"
	if Diplomacy.no_treaties(state, target):
		return "%s ne signe rien, pas même un contrat de mariage" % t.short_name()
	if united(state, player, target):
		return "lignées déjà unies"
	if not Diplomacy.allied(state, player, target):
		return "il faut d'abord une alliance"
	var need := int(v["alliance_days"])
	if Diplomacy.pact_days(state, player, target) < need:
		return "l'alliance doit durer %d jours (encore %d)" % [need, need - Diplomacy.pact_days(state, player, target)]
	if not Economy.can_afford(e, v["union_cost"]):
		return "pas assez de ressources (%s)" % GameData.format_amounts(v["union_cost"])
	return ""


static func union(state: GameState, player: int, target: int) -> void:
	var e := state.get_empire(player)
	Economy.pay(e, info("elu")["union_cost"])
	Diplomacy._rel_w(state, player, target)["union"] = maxi(1, state.tick)
	Diplomacy.remember(state, target, player, "union")
	state.add_chronicle("Noces de lignées : %s unit sa maison à celle de %s. Les généalogistes réclament une prime." % [
			e.display_name(), state.get_empire(target).display_name()], Espionage.public_to(state, [player, target]))


## Cathédrales achevées de l'empire, un système compté une fois : identifiants de systèmes.
static func cathedral_systems(state: GameState, empire_id: int) -> Array[int]:
	var b := String(info("couplet")["building"])
	var seen := {}
	for pid in state.colonies:
		var c: Colony = state.colonies[pid]
		if c.owner == empire_id and c.buildings.has(b):
			seen[state.galaxy.get_planet(pid).system_id] = true
	var out: Array[int] = []
	for s in seen:
		out.append(int(s))
	out.sort()
	return out


static func _couplet(state: GameState, e: Empire, out: Dictionary) -> void:
	var v := info("couplet")
	var sites := int(v["sites"])
	var have := cathedral_systems(state, e.id).size()
	out["lines"].append("Cathédrales-chœurs : %d / %d" % [have, sites])
	var exalted := FactionTraits.has_fervor(e.faction()) and FactionTraits.is_exalted(state, e.id)
	out["lines"].append("Exaltation : %s" % ("oui, le chœur chante" if exalted else "non, le chant se tait"))
	out["cond"] = have >= sites and exalted
	out["keep"] = have >= sites
	_timed(out, have, sites)


## Empires qui ont signé la Charte avec l'empire : paix ou alliance, et commerce.
static func signatories(state: GameState, empire_id: int) -> Array[int]:
	var out: Array[int] = []
	for o in state.empires:
		if o.id != empire_id and not o.eliminated and Diplomacy.has_pact(state, empire_id, o.id) and Diplomacy.has_trade(state, empire_id, o.id):
			out.append(o.id)
	return out


static func _charte(state: GameState, e: Empire, out: Dictionary) -> void:
	var v := info("charte")
	var alive := 0
	var blockers: Array[String] = []
	for o in state.empires:
		if o.id != e.id and not o.eliminated:
			alive += 1
			if Diplomacy.no_treaties(state, o.id):
				blockers.append(o.short_name())
	var signed := signatories(state, e.id).size()
	var need := maxi(int(v["min_signatories"]), alive)
	out["lines"].append("Signataires : %d / %d" % [signed, need])
	if not blockers.is_empty():
		out["lines"].append("Ne signera jamais : %s" % ", ".join(blockers))
	out["cond"] = signed >= need
	_timed(out, signed, need)


## Population totale des revendications fondées de la galaxie, et celle de l'empire : [total, sienne].
static func population_share(state: GameState, empire_id: int) -> Array[int]:
	var total := 0
	var mine := 0
	for pid in state.colonies:
		var c: Colony = state.colonies[pid]
		if not c.is_established():
			continue
		total += c.population
		if c.owner == empire_id:
			mine += c.population
	return [total, mine]


static func _moisson(state: GameState, e: Empire, out: Dictionary) -> void:
	var v := info("moisson")
	var ps := population_share(state, e.id)
	@warning_ignore("integer_division")
	var share := 100 * ps[1] / maxi(1, ps[0])
	var want_share := int(v["pop_share_pct"])
	var dig := int(e.stats.get("digested", 0))
	var want_dig := int(v["digested"])
	out["lines"].append("Part de la population galactique : %d %% / %d %%" % [share, want_share])
	out["lines"].append("Population digérée : %d / %d" % [dig, want_dig])
	# La Moisson se tient : le compte à rebours repart de zéro si l'Essaim retombe sous le seuil.
	out["cond"] = share >= want_share and dig >= want_dig
	# L'avancée suit la plus en retard des deux mesures.
	var r1 := 1000 * mini(share, want_share) / maxi(1, want_share)
	var r2 := 1000 * mini(dig, want_dig) / maxi(1, want_dig)
	_timed(out, mini(r1, r2), 1000)


## L'Éveil de la Noosphère : assez de nœuds reliés, et pas une seule revendication coupée.
static func _noosphere(state: GameState, e: Empire, out: Dictionary) -> void:
	var want := int(info("noosphere")["nodes"])
	var nodes := FactionTraits.network_nodes(state, e.id)
	var cut := FactionTraits.network_cut(state, e.id)
	out["lines"].append("Nœuds reliés : %d / %d" % [nodes, want])
	if cut > 0:
		out["lines"].append("Revendications coupées : %d (aucune permise)" % cut)
	out["cond"] = nodes >= want and cut == 0
	_timed(out, nodes if cut == 0 else mini(nodes, want - 1), want)


## Terre promise d'une horde : un monde habitable pour elle, à au moins min_jumps sauts de son
## berceau et hors des systèmes d'origine, tiré par hachage de la graine (le même à chaque calcul,
## sans rien sauvegarder). À défaut, parmi les plus lointains. -1 s'il n'y en a aucun.
static var _promised := {}

static func promised_planet(state: GameState, empire_id: int) -> int:
	var e := state.get_empire(empire_id)
	if e == null or not FactionTraits.has_horde(e.faction()) or e.home_planet < 0:
		return -1
	var key := "%d:%d:%d:%s" % [state.galaxy.get_instance_id(), state.seed_value, empire_id, e.faction_id]
	if _promised.has(key):
		return int(_promised[key])
	var homes := {}
	for o in state.empires:
		if o.home_planet >= 0:
			homes[state.galaxy.get_planet(o.home_planet).system_id] = true
	var d: Dictionary = FactionTraits.jumps_from(state.galaxy, state.galaxy.get_planet(e.home_planet).system_id)
	var want := int(info("terre_promise").get("min_jumps", 6))
	var far: Array[int] = []
	var farthest: Array[int] = []
	var best_d := -1
	for p: Planet in state.galaxy.planets:
		if homes.has(p.system_id) or Economy.habitability(p.type, e.faction()) <= 0 or not d.has(p.system_id):
			continue
		var j := int(d[p.system_id])
		if j >= want:
			far.append(p.id)
		if j > best_d:
			best_d = j
			farthest.clear()
		if j == best_d:
			farthest.append(p.id)
	var pool := far if not far.is_empty() else farthest
	var pid := -1
	if not pool.is_empty():
		pool.sort()
		pid = pool[posmod(hash([state.seed_value, empire_id, "terre_promise"]), pool.size())]
	_promised[key] = pid
	return pid


static func _terre_promise(state: GameState, e: Empire, out: Dictionary) -> void:
	var pid := promised_planet(state, e.id)
	if pid < 0:
		out["lines"].append("Aucune Terre promise dans cette galaxie")
		return
	var p := state.galaxy.get_planet(pid)
	var cf := FactionTraits.city_fleet(state, e.id)
	var v := info("terre_promise")
	var known := has_tech(state, e.id, "terre_promise")
	var found := false
	if cf == null:
		out["lines"].append("Sans flotte-ville, les Chants de la route se taisent")
	elif known:
		var dist := int(FactionTraits.jumps_from(state.galaxy, cf.system_id).get(p.system_id, 999))
		found = dist <= int(v["reveal_jumps"])
		if found:
			out["lines"].append("Terre promise : %s" % p.display_name(state.galaxy))
		else:
			out["lines"].append("Les Chants de la route : la Terre promise est à %d sauts de la flotte-ville" % dist)
	var c: Colony = state.colonies.get(pid)
	var owned := c != null and c.owner == e.id and c.is_established()
	var camped := cf != null and not cf.is_moving() and cf.system_id == p.system_id
	if owned or camped:
		found = true
	out["lines"].append("Colonie sur la Terre promise : %s" % ("fondée" if owned else "non"))
	out["lines"].append("Flotte-ville au camp : %s" % ("oui" if camped else "non"))
	out["cond"] = owned and camped
	_timed(out, int(found) + int(owned) + int(camped), 3)


## La Légende (registre Picaresque) : des exploits différents, puis une réputation tenue.
static func _legende(state: GameState, e: Empire, out: Dictionary) -> void:
	var v := info("legende")
	var need := int(v["exploits"])
	var min_rep := int(v["min_reputation"])
	var n := mini(e.exploits.size(), need)
	out["lines"].append("Exploits : %d / %d" % [e.exploits.size(), need])
	for x in Reputation.EXPLOITS:
		if e.exploits.has(String(x[0])):
			out["lines"].append("  ✓ %s" % String(x[1]))
	out["lines"].append("Réputation : %d (%d au moins)" % [e.reputation, min_rep])
	# Une légende a besoin d'un héros vivant et libre pour la porter (document de game design).
	var hero := Heroes.has_free_hero(state, e.id)
	out["lines"].append("Héros vivant pour la porter : %s" % ("oui" if hero else "aucun"))
	out["cond"] = e.exploits.size() >= need and e.reputation >= min_rep and hero
	_timed(out, n + int(e.reputation >= min_rep) + int(hero), need + 2)


## Le Silence parfait (archétype Énergétique) : assez de colonies peuplées, et pas un repérage depuis
## le dernier bilan (VictorySystem vérifie tous les check_days) ; un repérage remet tout à zéro.
static func _silence(state: GameState, e: Empire, out: Dictionary) -> void:
	var want := int(info("silence")["colonies"])
	var n := 0
	for pid in state.colonies:
		var c: Colony = state.colonies[pid]
		if c.owner == e.id and c.is_established():
			n += 1
	var since := -1 if e.spotted_tick < 0 else state.tick - e.spotted_tick
	var quiet := since < 0 or since > int(data().get("check_days", 30))
	out["lines"].append("Colonies peuplées : %d / %d" % [n, want])
	if since < 0:
		out["lines"].append("Jamais repéré")
	else:
		out["lines"].append("Dernier repérage : il y a %s, par %s" % [_days_text(since), state.get_empire(e.spotted_by).display_name() if e.spotted_by >= 0 else "?"])
	out["cond"] = n >= want and quiet
	_timed(out, mini(n, want) if quiet else mini(n, want - 1), want)


# --- Ce que l'on voit des autres ---------------------------------------------------------------

## Avancée que viewer voit de l'empire empire_id (-1 = cachée : victoire de peuple d'un autre
## sous le seuil de visibilité, ou empire jamais rencontré). viewer = -1 : tout voir (spectateur).
static func visible_pct(state: GameState, viewer: int, empire_id: int, id: String) -> int:
	var pct := cached_pct(state, empire_id, id)
	if viewer < 0 or viewer == empire_id:
		return pct
	var v := state.get_empire(viewer)
	if v == null or not v.contacts.has(empire_id):
		return -1
	if is_people(id) and pct < visible_at():
		return -1
	return pct


## Vainqueur proclamé : {"empire", "victory", "tick"} ou {} si la partie continue.
static func winner(state: GameState) -> Dictionary:
	return state.winner


## Texte du chroniqueur pour la victoire de e (et de ses alliés, pour une victoire partagée).
static func chronicle_text(id: String, e: Empire, allies: Array = [], state: GameState = null) -> String:
	var who := e.display_name()
	if not allies.is_empty() and state != null:
		var names := PackedStringArray()
		for a in allies:
			names.append(state.get_empire(int(a)).short_name())
		who += " (avec %s)" % ", ".join(names)
	var t := String(info(id).get("chronicle", "%s l'emporte."))
	return t % who if t.contains("%s") else t


## L'empire fait-il partie des vainqueurs (lui-même ou un allié qui partage la victoire) ?
static func is_winner(state: GameState, empire_id: int) -> bool:
	var w := state.winner
	return not w.is_empty() and (int(w["empire"]) == empire_id or Array(w.get("allies", [])).has(empire_id))
