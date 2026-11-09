class_name AiDiplomacy
extends RefCounted
## La diplomatie des empires IA : juger une proposition (evaluate), et agir (think) : proposer la paix,
## une alliance, un accord commercial ou un échange de cartes, quitter une alliance devenue gênante,
## et se servir des talents de son peuple (soudoyer un héritier, banquet des lignées, arbitrage).
##
## Le jugement additionne des raisons lisibles, affichées telles quelles au joueur avant qu'il propose
## (comme la barre d'Endless Space 2 qui montre ce que l'autre pense de l'offre) :
## l'opinion, le cours de la guerre, la lassitude, le rapport de forces (la « pression » d'ES2),
## l'ennemi commun et le tempérament (Pacifique à Belliqueux, décalé par le peuple).
## Les niveaux : la Recrue juge à l'humeur du jour (un écart déterministe, le même tout le mois) et
## ignore le rapport de forces ; Normal compte les bases ; Vétéran et au-delà pèsent tout et se servent
## des talents de leur peuple au bon moment. L'Essaim (no_treaties, never_peace) ne signe jamais rien.


static func cfg() -> Dictionary:
	return Diplomacy.data()["ai"]


static func _ctx(state: GameState, e: Empire) -> Dictionary:
	return {"state": state, "e": e, "lv": AiLevels.level(e.ai_level), "ai": AiLevels.personality(e), "salt": 0, "intent": ""}


static func _skill(e: Empire) -> int:
	return int(AiLevels.level(e.ai_level).get("military", {}).get("skill", 1))


## Puissance que l'IA s'attribue : ses flottes de guerre et ses systèmes (même barème que enemy_power).
static func own_power(state: GameState, e: Empire) -> int:
	var n := 0
	for f in Fleets.empire_fleets(state, e.id):
		if Combat.is_armed(f):
			n += Combat.fleet_power(f)
	return n + 6 * EmpireReport.owned_systems(state, e.id).size()


## Jugement de l'empire IA ai_id sur un traité proposé par from_id : {"score", "parts": [{label, value}]}.
## Accepté si score >= ai.accept_at. Pur (aucune écriture), donc utilisable par l'interface.
static func evaluate(state: GameState, ai_id: int, from_id: int, treaty: String) -> Dictionary:
	var parts: Array[Dictionary] = []
	var e := state.get_empire(ai_id)
	var c := cfg()
	if Diplomacy.no_treaties(state, ai_id) or (e.is_ai() and bool(AiLevels.personality(e).get("temperament", {}).get("never_peace", false))):
		parts.append({"label": "Ne signe jamais rien", "value": -999})
		return {"score": -999, "parts": parts}
	var aggr := AiLevels.aggression(e) if e.is_ai() else 0
	var skill := _skill(e) if e.is_ai() else 2
	var op := Diplomacy.opinion(state, ai_id, from_id)
	var at_war := Combat.at_war(state, ai_id, from_id)
	match treaty:
		Diplomacy.PEACE:
			if at_war:
				_p(parts, "Mettre fin à la guerre", int(c["peace_war_base"]))
				# En guerre, l'opinion compte moins : la haine est déjà dans la guerre elle-même.
				@warning_ignore("integer_division")
				_p(parts, "Opinion", op / 4)
				var war_days := Diplomacy.pact_days(state, ai_id, from_id)
				if war_days < Diplomacy.days("min_war_days", 60):
					_p(parts, "La guerre vient de commencer", int(c["too_early"]))
				_p(parts, "Lassitude de la guerre", mini(int(c["weariness_max"]), war_days / 30))
				var sc := Diplomacy.war_score(state, ai_id, from_id)
				# Celui qui gagne veut continuer, celui qui perd veut s'arrêter.
				_p(parts, "Cours de la guerre", clampi(-sc / 4, -int(c["score_max"]), int(c["score_max"])))
				if skill >= 1:
					_p(parts, "Rapport de forces", _pressure(state, e, from_id))
			else:
				_p(parts, "Pacte de paix", int(c["peace_cold_base"]))
				_p(parts, "Opinion", op / 2)
			_p(parts, "Tempérament", int(c["temperament_peace"]) * aggr)
			if Diplomacy.has_ability(state, ai_id, "crusade") and _credo(state, ai_id) != _credo(state, from_id):
				_p(parts, "Pas de paix avec les hérétiques", int(c["crusade_peace"]))
		Diplomacy.ALLIANCE:
			_p(parts, "S'engager dans une alliance", int(c["alliance_base"]))
			_p(parts, "Opinion", op)
			_p(parts, "Ennemi commun", int(c["common_enemy_bonus"]) * mini(2, Diplomacy.common_enemies(state, ai_id, from_id).size()))
			_p(parts, "Tempérament", int(c["temperament_other"]) * absi(aggr))
			if skill >= 1:
				# Une alliance entraîne dans les guerres de l'autre : gare à celles qu'on ne veut pas.
				var unwanted := 0
				for w in state.get_empire(from_id).wars:
					if not e.wars.has(w) and Diplomacy.opinion(state, ai_id, w) > 0:
						unwanted += 1
				_p(parts, "Ses guerres ne sont pas les nôtres", -20 * unwanted)
		Diplomacy.TRADE:
			_p(parts, "Commerce", int(c["trade_base"]))
			_p(parts, "Opinion", op / 2)
			_p(parts, "Tempérament", int(c["temperament_other"]) * maxi(0, aggr))
		Diplomacy.MAPS:
			_p(parts, "Révéler ses routes", int(c["maps_base"]))
			_p(parts, "Opinion", op / 2)
			if skill >= 2 and Diplomacy.border_systems(state, ai_id, from_id) > 0:
				_p(parts, "Un voisin n'a pas à tout savoir", -10)
	if skill == 0 and e.is_ai():
		_p(parts, "Humeur du jour", _mood(state, ai_id, from_id, treaty))
	var score := 0
	for p in parts:
		score += int(p["value"])
	return {"score": score, "parts": parts}


static func _p(parts: Array[Dictionary], label: String, value: int) -> void:
	if value != 0:
		parts.append({"label": label, "value": value})


static func _credo(state: GameState, id: int) -> String:
	return String(FactionTraits.species(state.get_empire(id).faction()).get("credo", ""))


## Rapport de forces : plus l'autre est fort (selon ce que l'on sait de lui), plus la paix est tentante.
static func _pressure(state: GameState, e: Empire, other: int) -> int:
	var mine := maxi(10, own_power(state, e))
	var theirs := maxi(10, AiPlayer.enemy_power(_ctx(state, e), other))
	var m := int(cfg()["pressure_max"])
	@warning_ignore("integer_division")
	return clampi((theirs * 100 / mine - 100) / 5, -m, m)


## L'humeur de la Recrue : un écart de -noise à +noise, fixe pendant un mois (hachage de l'état).
static func _mood(state: GameState, a: int, b: int, treaty: String) -> int:
	var n := int(cfg()["recrue_noise"])
	@warning_ignore("integer_division")
	var month := state.tick / maxi(1, int(GameData.rules()["month_days"]))
	return posmod(hash([state.seed_value, month, a, b, treaty]), 2 * n + 1) - n


# --- Agir --------------------------------------------------------------------------------------

## Module diplomatie d'AiPlayer. Au plus une proposition par réflexion (pas de harcèlement).
static func think(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if Diplomacy.no_treaties(state, e.id):
		return
	_heir(ctx)
	_leave_alliances(ctx)
	if _propose(ctx):
		return
	_mediate(ctx)
	_bribe(ctx)


static func _issue(ctx: Dictionary, cmd: Dictionary) -> bool:
	return AiPlayer._issue(ctx, cmd)


static func _propose(ctx: Dictionary) -> bool:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var want := int(cfg()["propose_at"])
	for other in e.contacts:
		var o := state.get_empire(other)
		if o == null or o.eliminated or Diplomacy.no_treaties(state, other):
			continue
		var wishes: Array[String] = []
		if Combat.at_war(state, e.id, other) or not Diplomacy.has_pact(state, e.id, other):
			wishes.append(Diplomacy.PEACE)
		elif Diplomacy.pact(state, e.id, other) == Diplomacy.PEACE:
			wishes.append(Diplomacy.ALLIANCE)
		if Diplomacy.has_pact(state, e.id, other) and not Diplomacy.has_trade(state, e.id, other):
			wishes.append(Diplomacy.TRADE)
		if not Combat.at_war(state, e.id, other) and AiPlayer._skill(ctx) >= 1:
			wishes.append(Diplomacy.MAPS)
		for t in wishes:
			if SimCommands.validate(state, SimCommands.propose_treaty(e.id, other, t)) != "":
				continue
			# L'IA ne propose que ce qu'elle accepterait elle-même, avec une marge.
			if int(evaluate(state, e.id, other, t)["score"]) < want or AiPlayer._forgets(ctx):
				continue
			if _issue(ctx, SimCommands.propose_treaty(e.id, other, t)):
				var signed := Diplomacy.has_pact(state, e.id, other) if t != Diplomacy.TRADE else Diplomacy.has_trade(state, e.id, other)
				if t == Diplomacy.ALLIANCE:
					signed = Diplomacy.allied(state, e.id, other)
				AiPlayer._intent(ctx, "%s %s avec %s" % ["Signe" if signed else "Propose", Diplomacy.treaty_label(t).to_lower(), o.short_name()])
				return true
	return false


## Une alliance qui ne plaît plus (opinion négative) se quitte.
static func _leave_alliances(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	for other in Diplomacy.allies(state, e.id):
		if Diplomacy.opinion(state, e.id, other) < -10 and not AiPlayer._forgets(ctx):
			if _issue(ctx, SimCommands.cancel_treaty(e.id, other, Diplomacy.ALLIANCE)):
				AiPlayer._intent(ctx, "Quitte son alliance avec %s" % state.get_empire(other).short_name())


## Dynastie féodale : banquet quand l'héritier vacille. La Recrue s'y prend trop tard.
static func _heir(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if not Diplomacy.has_heir(state, e.id):
		return
	var use := AiPlayer._use(ctx)
	var at: int = [12, 35, 45][clampi(use, 0, 2)]
	if e.heir_loyalty > at or AiPlayer._forgets(ctx):
		return
	if _issue(ctx, SimCommands.banquet(e.id)):
		AiPlayer._intent(ctx, "Banquet pour retenir son héritier")


## Soudoyer l'héritier d'un rival : Normal seulement contre un ennemi, Vétéran+ aussi contre un voisin
## détesté, et seulement avec de l'influence en trop ; la Recrue achète n'importe qui quand elle peut.
static func _bribe(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var use := AiPlayer._use(ctx)
	var cost := int(Diplomacy.ability("heir")["bribe_cost"].get("influence", 30))
	var reserve := int(ctx["lv"].get("reserve_influence", 0))
	if AiPlayer._res(ctx, "influence") < cost + reserve + (0 if use == 0 else 20):
		return
	for other in e.contacts:
		if SimCommands.validate(state, SimCommands.bribe_heir(e.id, other)) != "":
			continue
		var o := state.get_empire(other)
		var good := false
		match use:
			0:
				good = true
			1:
				good = e.wars.has(other)
			_:
				good = e.wars.has(other) or (Diplomacy.opinion(state, e.id, other) < -20 and o.heir_loyalty < 50)
		if not good or AiPlayer._forgets(ctx):
			continue
		if _issue(ctx, SimCommands.bribe_heir(e.id, other)):
			AiPlayer._intent(ctx, "Soudoie l'héritier de %s" % o.short_name())
			return


## République : arbitrer une guerre. Vétéran+ choisit celle où un ami souffre ; Normal arbitre quand
## l'influence déborde ; la Recrue arbitre la première guerre venue, quitte à sauver un rival.
static func _mediate(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if not Diplomacy.has_ability(state, e.id, "mediation"):
		return
	var use := AiPlayer._use(ctx)
	var cost := int(Diplomacy.ability("mediation")["cost"].get("influence", 40))
	var spare: int = [0, 40, 20][clampi(use, 0, 2)]
	if AiPlayer._res(ctx, "influence") < cost + int(ctx["lv"].get("reserve_influence", 0)) + spare:
		return
	for a in e.contacts:
		for b in state.get_empire(a).wars:
			if b <= a:
				continue
			if SimCommands.validate(state, SimCommands.mediate(e.id, a, b)) != "":
				continue
			if use >= 2:
				# Utile seulement si un ami (opinion > 20) est dans le camp qui perd.
				var loser := a if Diplomacy.war_score(state, a, b) < 0 else b
				if Diplomacy.opinion(state, e.id, loser) <= 20:
					continue
			if AiPlayer._forgets(ctx):
				continue
			if _issue(ctx, SimCommands.mediate(e.id, a, b)):
				AiPlayer._intent(ctx, "Arbitre la guerre entre %s et %s" % [state.get_empire(a).short_name(), state.get_empire(b).short_name()])
				return
