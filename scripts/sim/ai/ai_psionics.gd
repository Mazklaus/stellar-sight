class_name AiPsionics
extends RefCounted
## IA et pouvoirs psioniques (prop. 41 ; voir Psionics, data/psionics.json « ai »).
## Une fois par mois, si le pilier est en jeu : recherche la chaîne du pilier (Théorie psionique,
## Télépathie, puis Écrans psychiques et Précognition), choisit L'Éveil si son credo le veut, bâtit un
## Collège des sensitifs sur sa capitale, puis use de ses pouvoirs en gardant une réserve : Apaisement
## sur le système le plus agité, Préscience en guerre, Lecture des esprits sur un ennemi.
## Un peuple sourd (synthétique) cherche seulement les Écrans psychiques. La Recrue oublie souvent.
## Lot 2 : en réglage Complet, ouvre le Songe dès qu'il en a le Savoir, plonge (posture selon son
## tempérament : Audacieuse s'il est agressif, Prudente s'il est pacifique), accepte les pactes sauf
## celui de la Dernière Puissance, accepte la réforme de l'Élu si son credo est la foi ; en guerre,
## tente la Domination mentale ; en paix, use de la Voix sur le voisin qui l'aime le moins.

static func cfg() -> Dictionary:
	return Psionics.cfg("ai")


static func think(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if not Psionics.applies(state, e.id):
		return
	@warning_ignore("integer_division")
	var month := state.tick / int(GameData.rules()["month_days"]) + 1
	if Psionics.stat(state, e.id, "ai_month") >= month:
		return
	Psionics._stat(state, e.id, "ai_month", month - Psionics.stat(state, e.id, "ai_month"))
	if AiPlayer._skill(ctx) < int(cfg().get("min_skill", 0)) or AiPlayer._forgets(ctx):
		return
	_research(ctx)
	if Psionics.best_level(state, e.id) <= 0:
		return
	var credo := String(FactionTraits.species(e.faction()).get("credo", ""))
	if (cfg().get("eveil_credo", []) as Array).has(credo) and Psionics.check(state, e.id, "path", {}) == "":
		AiPlayer._issue(ctx, SimCommands.psi_act(e.id, "path"))
		AiPlayer._intent(ctx, "éveiller son peuple au Songe")
		return
	_college(ctx)
	_dream(ctx)
	_powers(ctx)


static func _research(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var chain: Array = ["ecrans_psychiques"] if int(Psionics.arch_def(e.faction()).get("max", 3)) <= 0 \
			else ["theorie_psionique", "telepathie", "ecrans_psychiques", "precognition"]
	for t in chain:
		if e.techs.has(t):
			continue
		if int(Research.tech(t).get("era", 9)) <= Research.current_era(state, e.id):
			var step := AiGenetics.reachable(state, e, t, 3)
			if step != "" and not e.research_queue.has(step):
				AiPlayer._issue(ctx, SimCommands.research(e.id, step))
		break


static func _college(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var b := String(Psionics.cfg("college").get("building", "college_sensitifs"))
	if Psionics.colleges(state, e.id) > 0 or e.capital_planet < 0:
		return
	if Economy.check_build(state, e.id, e.capital_planet, b) == "":
		AiPlayer._issue(ctx, SimCommands.build(e.id, e.capital_planet, b))


static func _dream(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if not Psionics.full(state):
		return
	var off := PsionicsDream.offer(state, e.id)
	if not off.is_empty():
		var yes := not PsionicsDream.is_last(String(off["p"])) and PsionicsDream.pact(state, e.id).is_empty()
		AiPlayer._issue(ctx, SimCommands.psi_act(e.id, "pact", {"accept": yes}))
		return
	if PsionicsDream.check_reform(state, e.id) == "":
		var credo := String(FactionTraits.species(e.faction()).get("credo", ""))
		AiPlayer._issue(ctx, SimCommands.psi_act(e.id, "reform", {"accept": credo == "foi"}))
		return
	if PsionicsDream.check_open(state, e.id) == "":
		AiPlayer._issue(ctx, SimCommands.psi_act(e.id, "open"))
		AiPlayer._intent(ctx, "ouvrir le Songe")
		return
	var aggr := AiLevels.aggression(e)
	var posture := "audacieuse" if aggr >= 1 else ("prudente" if aggr <= -1 else "mesuree")
	if Psionics.resonance(state, e.id) - PsionicsDream.dive_cost(state, e.id) >= int(cfg().get("reserve", 20)) and PsionicsDream.check_dive(state, e.id, posture) == "":
		AiPlayer._issue(ctx, SimCommands.psi_act(e.id, "dive", {"posture": posture}))
		AiPlayer._intent(ctx, "plonger dans le Songe")


static func _powers(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var reserve := int(cfg().get("reserve", 20))
	# Apaisement : le système le plus agité sous le seuil.
	var worst := -1
	var worst_v := int(cfg().get("calm_below", 35))
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner != e.id or not c.is_colony():
			continue
		var sid := state.galaxy.get_planet(pid).system_id
		var v := Stability.value(state, sid)
		if v < worst_v:
			worst_v = v
			worst = sid
	if worst >= 0 and _try(ctx, "apaisement", worst, reserve):
		return
	if not e.wars.is_empty():
		if _try(ctx, "prescience", -1, reserve):
			return
		var foe := -1
		for w in e.wars:
			if e.contacts.has(w):
				foe = w
				break
		if foe >= 0 and _try(ctx, "lecture", foe, reserve):
			return
		for fid in PsionicsDream.fleet_ids(state):
			var f: Fleet = state.fleets[fid]
			if f.owner == e.id and not f.is_moving() and _try(ctx, "domination", f.system_id, reserve):
				return
	else:
		# La Voix : sur le voisin qui nous aime le moins (opinion négative).
		var worst_e := -1
		var worst_o := 0
		for c in e.contacts:
			var b := state.get_empire(c)
			if b == null or b.eliminated or b.is_npc():
				continue
			var o := Diplomacy.opinion(state, c, e.id)
			if o < worst_o:
				worst_o = o
				worst_e = c
		if worst_e >= 0:
			_try(ctx, "voix", worst_e, reserve)


static func _try(ctx: Dictionary, power: String, target: int, reserve: int) -> bool:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if Psionics.resonance(state, e.id) - Psionics.power_cost(state, e.id, power) < reserve and power != "apaisement":
		return false
	if Psionics.check_power(state, e.id, power, target) != "":
		return false
	AiPlayer._issue(ctx, SimCommands.psi_act(e.id, "power", {"power": power, "target": target}))
	AiPlayer._intent(ctx, "user de son pouvoir : %s" % String(Psionics.power_def(power).get("label", power)))
	return true
