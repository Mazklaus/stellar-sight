class_name DeedsBridges
extends RefCounted
## Ponts des hauts faits galactiques (voir Deeds) vers le reste du jeu :
## - affinité de famille (credo, registre : Gloire ×2, prop. 18) et rattrapage (moitié basse, prop. 15) ;
## - grands moments déjà en jeu qui donnent de la Gloire (merveille, crise, gardien, quête, ancienne,
##   paix imposée : prop. 14) et premiers moments des Annales (prop. 22) ;
## - héros, Légende, Rayonnement, Amphictyonie, score (props 25 à 28) ;
## - titres et Infamie dans l'opinion (props 12 et 16) ;
## - Âges d'or (prop. 13, option) ;
## - opération « Falsifier les annales » (prop. 29) ;
## - victoire « Les Annales » (prop. 32, option).

## Actes dont le premier exemplaire s'inscrit dans les Annales (frise des grands moments).
const FIRSTS := {"colony": "Première colonie", "wars": "Première guerre", "battles_won": "Première bataille gagnée",
		"treaty": "Premier traité", "conquests": "Première conquête", "curios": "Première curiosité fouillée",
		"quests": "Première quête galactique", "guardians": "Premier gardien abattu", "digs": "Premières fouilles"}


# --- Affinité et rattrapage --------------------------------------------------------------------

## La famille fait-elle partie des affinités de l'empire (credo ou registre) ?
static func affinity(state: GameState, eid: int, fam: String) -> bool:
	var aff: Dictionary = (Deeds.data()["families"] as Dictionary).get(fam, {}).get("affinity", {})
	if state.get_empire(eid) == null:
		return false
	for layer in aff:
		if (aff[layer] as Array).has(Events.layer_value(state, eid, String(layer))):
			return true
	return false


## Empires classés par Gloire (vivants, hors PNJ), du premier au dernier ; égalité : plus petit id.
static func ranking(state: GameState) -> Array[int]:
	var out: Array[int] = []
	for e in state.empires:
		if not e.eliminated and not e.is_npc():
			out.append(e.id)
	out.sort_custom(func(a: int, b: int) -> bool:
		var ga := Deeds.glory(state, a)
		var gb := Deeds.glory(state, b)
		return ga > gb or (ga == gb and a < b))
	return out


## Dans la moitié basse du classement de Gloire ? (il faut que d'autres aient plus de Gloire)
static func lower_half(state: GameState, eid: int) -> bool:
	var r := ranking(state)
	if r.size() < 2 or not r.has(eid):
		return false
	var above := 0
	var mine := Deeds.glory(state, eid)
	for o in r:
		if Deeds.glory(state, o) > mine:
			above += 1
	return above * 2 >= r.size()


static func catchup_pct(state: GameState, eid: int) -> int:
	return Deeds.r_int("catchup_pct") if lower_half(state, eid) else 0


## L'empire en tête de Gloire (-1 si personne n'en a).
static func leader(state: GameState) -> int:
	var r := ranking(state)
	if r.is_empty() or Deeds.glory(state, r[0]) <= 0:
		return -1
	return r[0]


## Gloire d'un grand moment (prop. 14) : ajoutée et inscrite dans les Annales.
static func moment(state: GameState, eid: int, what: String, pct := 100) -> int:
	if not Deeds.enabled(state):
		return 0
	var e := state.get_empire(eid)
	if e == null or e.is_npc():
		return 0
	@warning_ignore("integer_division")
	var g := int((Deeds.rules()["moments"] as Dictionary).get(what, 0)) * pct / 100
	if g <= 0:
		return 0
	Deeds.add_glory(state, eid, g)
	Deeds.annal(state, eid, "moment", what, g)
	return g


# --- Actes ---------------------------------------------------------------------------------------

static func on_note(state: GameState, eid: int, key: String, n: int, first: bool) -> void:
	if first and FIRSTS.has(key):
		Deeds.annal(state, eid, "first", key)
	match key:
		"quests":
			for i in n:
				moment(state, eid, "quests")
		"guardians":
			for i in n:
				moment(state, eid, "guardians")


## Le premier à accomplir un haut fait : héros, renom, Légende, Rayonnement accru (props 25, 26, 28).
static func on_award(state: GameState, eid: int, id: String, _added: Array[Dictionary]) -> void:
	# Le héros le plus aguerri de l'empire porte le haut fait (expérience).
	var best: Dictionary = {}
	for hid in Heroes.ids_of(state, eid):
		var h: Dictionary = state.heroes[hid]
		if Heroes.is_prisoner(h):
			continue
		if best.is_empty() or int(h.get("xp", 0)) > int(best.get("xp", 0)):
			best = h
	if not best.is_empty():
		Heroes.gain_xp(state, best, Deeds.r_int("hero_xp"))
	Heroes.act(state, eid, "deed")
	if Deeds.family(id) == "guerre":
		Heroes.act(state, eid, "deed_war")
	Reputation.add(state, eid, Deeds.r_int("legend_rep"))
	Deeds._m(state, "rad")[str(eid)] = state.tick + Deeds.r_int("radiance_days")


static func daily(_state: GameState, _added: Array[Dictionary]) -> void:
	pass


static func monthly(state: GameState, added: Array[Dictionary]) -> void:
	# L'Infamie s'efface.
	var inf: Dictionary = state.deeds.get("infamy", {})
	for k in inf.keys():
		if int(inf[k]) <= state.tick:
			inf.erase(k)
	var rad: Dictionary = state.deeds.get("rad", {})
	for k in rad.keys():
		if int(rad[k]) <= state.tick:
			rad.erase(k)
	_golden(state, added)


## Fin d'une bataille : séries de victoires et « Tueur de géant ».
static func on_battle(state: GameState, b: Dictionary, winner: int) -> void:
	if not Deeds.enabled(state):
		return
	var streak := Deeds._m(state, "streak")
	var lead := leader(state)
	var giant := false
	for s: Dictionary in b["sides"]:
		var eid := int(s["empire"])
		var e := state.get_empire(eid)
		if e == null or e.is_npc():
			continue
		if eid == winner:
			streak[str(eid)] = int(streak.get(str(eid), 0)) + 1
		else:
			streak[str(eid)] = 0
			if eid == lead and winner >= 0 and Combat.at_war(state, winner, eid):
				giant = true
	if giant and winner != lead and lower_half(state, winner):
		Deeds.note(state, winner, "giant_slain")


## Prise d'un système (après le changement de mains) : Phénix et monde d'une puissance ancienne.
static func on_capture(state: GameState, system_id: int, new_owner: int, old: int) -> void:
	if not Deeds.enabled(state) or old == new_owner:
		return
	var en := state.get_empire(new_owner)
	if en == null or en.is_npc():
		return
	if en.home_planet >= 0 and state.galaxy.get_planet(en.home_planet).system_id == system_id:
		var c: Colony = state.colonies.get(en.home_planet)
		if c != null and c.owner == new_owner:
			Deeds.note(state, new_owner, "phoenix")
	if old >= 0 and Ancients.enabled(state) and Ancients.ids(state).has(old):
		Deeds.note(state, new_owner, "ancient_world")
		moment(state, new_owner, "ancient_world")


## Crise vaincue : Gloire selon la part de gloire, plus grande part, survivants (props 14, catalogue).
static func on_crisis_victory(state: GameState, sh: Array) -> void:
	if not Deeds.enabled(state):
		return
	for s: Array in sh:
		moment(state, int(s[0]), "crisis", int(s[1]))
	if not sh.is_empty():
		Deeds.note(state, int(sh[0][0]), "crisis_top")
	for e in state.empires:
		if not e.eliminated and not e.is_npc():
			Deeds.note(state, e.id, "crisis_survived")


static func on_wonder(state: GameState, eid: int, _wid: String) -> void:
	moment(state, eid, "wonder")


## Paix signée : paix imposée (Gloire) et « David » (vainqueur plus petit que le vaincu).
static func on_peace(state: GameState, a: int, b: int, winner: int) -> void:
	if not Deeds.enabled(state) or winner < 0:
		return
	var loser := b if winner == a else a
	moment(state, winner, "imposed_peace")
	if DeedsEval._systems_held(state, winner).size() < DeedsEval._systems_held(state, loser).size():
		Deeds.note(state, winner, "david")


# --- Opinion, effets, stabilité --------------------------------------------------------------------

## Opinion de a sur b : titres honorifiques de b (+10 chacun, hors Bâtisseur déjà compté par les
## merveilles) et Infamie de b (-15).
static func opinion_parts(state: GameState, a: int, b: int) -> Array:
	var out := []
	if not Deeds.enabled(state) or a == b:
		return out
	for t in Deeds.titles_of(state, b):
		if t == "batisseur":
			continue
		out.append(["Titre : %s" % Deeds.title_label(t), Deeds.r_int("title_opinion")])
	if int((state.deeds.get("infamy", {}) as Dictionary).get(str(b), 0)) > state.tick:
		out.append(["Infamie (haut fait infâme)", Deeds.r_int("infamy_opinion")])
	return out


static func infamous(state: GameState, eid: int) -> bool:
	return int((state.deeds.get("infamy", {}) as Dictionary).get(str(eid), 0)) > state.tick


static func effects(state: GameState, eid: int) -> Dictionary:
	if not in_golden(state, eid):
		return {}
	var p := int(Deeds.rules()["golden"]["pct"])
	return {"production_pct": {"knowledge": p, "materials": p}}


static func stability_parts(state: GameState, eid: int) -> Array:
	if not in_golden(state, eid):
		return []
	return [["Âge d'or", int(Deeds.rules()["golden"]["stability"])]]


## Patrimoine supplémentaire tiré de la Gloire (prop. 28).
static func heritage_bonus(state: GameState, eid: int) -> int:
	if not Deeds.enabled(state):
		return 0
	@warning_ignore("integer_division")
	return Deeds.glory(state, eid) / maxi(1, Deeds.r_int("heritage_div"))


## Rayonnement accru pendant un an après chaque haut fait (prop. 28).
static func radiance_pct(state: GameState, eid: int) -> int:
	if not Deeds.enabled(state):
		return 0
	return Deeds.r_int("radiance_pct") if int((state.deeds.get("rad", {}) as Dictionary).get(str(eid), 0)) > state.tick else 0


## Voix supplémentaires à l'Amphictyonie : une par tranche de 500 de Gloire (prop. 28).
static func votes(state: GameState, eid: int) -> int:
	if not Deeds.enabled(state):
		return 0
	@warning_ignore("integer_division")
	return Deeds.glory(state, eid) / maxi(1, Deeds.r_int("votes_per"))


## Points de score : un dixième de la Gloire (prop. 27).
static func score(state: GameState, eid: int) -> int:
	if not Deeds.enabled(state):
		return 0
	@warning_ignore("integer_division")
	return Deeds.glory(state, eid) / maxi(1, Deeds.r_int("score_div"))


# --- Âges d'or (prop. 13, option) ------------------------------------------------------------------

static func golden_on(state: GameState) -> bool:
	return Deeds.enabled(state) and bool((state.deeds.get("golden", {}) as Dictionary).get("on", false))


## État de l'âge d'or d'un empire : {"until": fin de l'âge en cours, "n": âges déjà vécus}.
static func golden_of(state: GameState, eid: int) -> Dictionary:
	return (state.deeds.get("golden", {}) as Dictionary).get("e", {}).get(str(eid), {})


static func in_golden(state: GameState, eid: int) -> bool:
	return golden_on(state) and int(golden_of(state, eid).get("until", 0)) > state.tick


## Seuil de Gloire à gagner sur la période pour le prochain âge d'or.
static func golden_threshold(state: GameState, eid: int) -> int:
	var g: Dictionary = Deeds.rules()["golden"]
	return int(g["base"]) + int(g["step"]) * int(golden_of(state, eid).get("n", 0))


## Gloire gagnée depuis le début de la période en cours.
static func golden_gained(state: GameState, eid: int) -> int:
	return Deeds.glory(state, eid) - int((state.deeds.get("golden", {}) as Dictionary).get("last", {}).get(str(eid), 0))


static func _golden(state: GameState, added: Array[Dictionary]) -> void:
	if not golden_on(state):
		return
	var gd: Dictionary = state.deeds["golden"]
	var g: Dictionary = Deeds.rules()["golden"]
	var per: Dictionary = gd.get("e", {})
	gd["e"] = per
	# Un âge qui finit : les effets changent.
	var ended := false
	for k in per.keys():
		var x: Dictionary = per[k]
		if int(x.get("until", 0)) > 0 and int(x["until"]) <= state.tick:
			x["until"] = 0
			ended = true
			added.append(state.add_chronicle("L'âge d'or de %s s'achève. On en parlera longtemps, souvent en exagérant." % state.get_empire(int(k)).short_name(),
					Espionage.private_to(state, [int(k)])))
	if ended:
		Relics.touch(state)
	var period := int(g["period"])
	if state.tick < period or posmod(state.tick, period) >= Deeds.r_int("check_days"):
		return
	var last: Dictionary = gd.get("last", {})
	gd["last"] = last
	var started := false
	for e in state.empires:
		if e.eliminated or e.is_npc():
			continue
		var gained := golden_gained(state, e.id)
		var need := golden_threshold(state, e.id)
		last[str(e.id)] = Deeds.glory(state, e.id)
		if gained < need:
			continue
		var x: Dictionary = per.get(str(e.id), {})
		x["n"] = int(x.get("n", 0)) + 1
		x["until"] = state.tick + int(g["days"])
		per[str(e.id)] = x
		started = true
		Deeds.annal(state, e.id, "golden", "age_or", gained)
		added.append(state.add_chronicle("Âge d'or pour %s ! %d de Gloire en dix ans : les poètes n'ont plus assez de rimes. Cinq ans de prospérité (+%d stabilité, +%d %% Savoir et matériaux)." % [
				e.display_name(), gained, int(g["stability"]), int(g["pct"])]))
	if started:
		Relics.touch(state)


# --- Ombres (prop. 29) -----------------------------------------------------------------------------

## Le haut fait encore à prendre où b est le plus avancé (records et Premières chiffrées).
static func _best_target(state: GameState, b: int) -> String:
	var best := ""
	var best_p := 0
	for id in Deeds.pool(state):
		var sid := String(id)
		if Deeds.is_won(state, sid) or Deeds.sort_of(sid) == "secret" or not Deeds.is_open(state, b, sid):
			continue
		if int(Deeds.def(sid)["n"]) < 2:
			continue
		var p := Deeds.pct(state, b, sid)
		if p > best_p:
			best = sid
			best_p = p
	return best


static func spy_check(state: GameState, _a: int, b: int, _op_id: String) -> String:
	if not Deeds.enabled(state):
		return "pas de hauts faits dans cette partie"
	if _best_target(state, b) == "":
		return "aucun haut fait en cours chez lui"
	return ""


static func spy_apply(state: GameState, a: int, b: int, _o: Dictionary) -> String:
	var id := _best_target(state, b)
	if id == "":
		return "ses annales sont vides : rien à falsifier."
	@warning_ignore("integer_division")
	var cut := maxi(1, int(Deeds.def(id)["n"]) * Deeds.r_int("falsify_pct") / 100)
	var key := "%s>%d" % [id, b]
	var f := Deeds._m(state, "falsified")
	f[key] = int(f.get(key, 0)) + cut
	Deeds._m(state, "fals_by")[key] = a
	return "ses annales sur « %s » ont été « corrigées » : %d de moins à son compteur." % [Deeds.label(id), cut]


## L'opération est découverte : la cible récupère sa progression.
static func spy_exposed(state: GameState, a: int, b: int) -> void:
	if not Deeds.enabled(state):
		return
	var by := Deeds._m(state, "fals_by")
	var f := Deeds._m(state, "falsified")
	for key in by.keys():
		if int(by[key]) == a and String(key).ends_with(">%d" % b):
			f.erase(key)
			by.erase(key)


# --- Victoire « Les Annales » (prop. 32, option) ----------------------------------------------------

static func annales_needed(state: GameState) -> int:
	var d := maxi(1, int(Deeds.rules()["annals"]["share_div"]))
	@warning_ignore("integer_division")
	return maxi(1, (Deeds.pool(state).size() + d - 1) / d)


static func victory(state: GameState, e: Empire, out: Dictionary) -> void:
	if not Deeds.enabled(state):
		out["lines"].append("Pas de hauts faits dans cette partie")
		return
	var have := Deeds.held_by(state, e.id).size()
	var need := annales_needed(state)
	var first := leader(state) == e.id
	out["lines"].append("Hauts faits détenus : %d sur %d" % [have, need])
	out["lines"].append("Premier en Gloire : %s" % ("oui" if first else "non"))
	out["cond"] = have >= need and first
	Victory._timed(out, have, need)
