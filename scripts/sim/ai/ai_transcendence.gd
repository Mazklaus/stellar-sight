class_name AiTranscendence
extends RefCounted
## IA et Transcendance (prop. 40 ; voir Transcendence, data/transcendence.json « ai »).
## Une fois par mois, si le pilier est en jeu : cherche L'Orée à l'ère V, choisit la voie qui lui va
## (préférences par credo, puis la première ouverte), bâtit l'Exodium étape par étape en gardant une
## réserve, des Relais sur ses colonies les plus peuplées, mène l'Arche jusqu'à la Bordure, et rejoint
## le Passage d'un allié. Un peuple qui ne transcende jamais (Kh'thari) ne cherche pas L'Orée.
## Ses rivaux visent l'Exodium aux alertes (AiPlayer._war_target, Transcendence.strike_target).
## La Recrue oublie souvent.

static func cfg() -> Dictionary:
	return Transcendence.cfg("ai")


static func think(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if not Transcendence.applies(state, e.id) or Transcendence.t_int(state, e.id, "never") > 0:
		return
	@warning_ignore("integer_division")
	var month := state.tick / Transcendence.month_days() + 1
	if Transcendence.stat(state, e.id, "ai_month") >= month:
		return
	Transcendence._stat(state, e.id, "ai_month", month - Transcendence.stat(state, e.id, "ai_month"))
	_ark(ctx)  # l'Arche se mène même les mois où l'on oublie le reste
	if AiPlayer._forgets(ctx) or Transcendence.renounced(state, e.id):
		return
	_research(ctx)
	if not Transcendence.knows_oree(state, e.id):
		return
	if Transcendence.path_of(state, e.id) == "" and Transcendence.host_of(state, e.id) < 0:
		if _join(ctx):
			return
		_choose(ctx)
		return
	_oeuvre(ctx)
	_relays(ctx)


static func _research(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var t := String(Transcendence.data().get("tech", "oree"))
	if e.techs.has(t) or int(Research.tech(t).get("era", 9)) > Research.current_era(state, e.id):
		return
	var step := AiGenetics.reachable(state, e, t, 3)
	if step != "" and not e.research_queue.has(step):
		AiPlayer._issue(ctx, SimCommands.research(e.id, step))


static func _choose(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var open := Transcendence.available_paths(state, e.id)
	if open.is_empty():
		return
	var pick := ""
	for p in (cfg().get("prefs", {}) as Dictionary).get(Transcendence.credo(state, e.id), []):
		if open.has(String(p)):
			pick = String(p)
			break
	if pick == "":
		pick = open[0]
	if AiPlayer._issue(ctx, SimCommands.tr_act(e.id, "path", {"path": pick})):
		AiPlayer._intent(ctx, "se vouer à %s" % Transcendence.path_label(pick).to_lower())


## Rejoindre le Passage d'un allié : bâtir un Relais, puis se joindre.
static func _join(ctx: Dictionary) -> bool:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	for other in state.empires:
		if other.id == e.id or not Transcendence.in_passage(state, other.id):
			continue
		if Transcendence.check_join(state, e.id, other.id) == "":
			if AiPlayer._issue(ctx, SimCommands.tr_act(e.id, "join", {"host": other.id})):
				AiPlayer._intent(ctx, "partir avec %s" % other.short_name())
			return true
		if (Diplomacy.allied(state, e.id, other.id) or Koinon.same_league(state, e.id, other.id)) and e.capital_planet >= 0:
			var b := Transcendence.relay_building()
			if Economy.check_build(state, e.id, e.capital_planet, b) == "":
				AiPlayer._issue(ctx, SimCommands.build(e.id, e.capital_planet, b))
				return true
	return false


static func _oeuvre(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if Transcendence.check_oeuvre(state, e.id) != "":
		return
	# Réserve : on garde de quoi tenir (reserve_pct % du coût en plus), sauf la Recrue.
	var cost := Transcendence.stage_cost(state, e.id)
	if AiPlayer._skill(ctx) >= 1:
		var pct := int(cfg().get("reserve_pct", 50))
		for r in cost:
			@warning_ignore("integer_division")
			if int(e.resources.get(r, 0)) < int(cost[r]) * (100 + pct) / 100:
				return
	if AiPlayer._issue(ctx, SimCommands.tr_act(e.id, "oeuvre", {})):
		AiPlayer._intent(ctx, "bâtir %s" % Transcendence.oeuvre_label(Transcendence.path_of(state, e.id)))


## Des Relais sur les colonies les plus peuplées, une fois la jauge à moitié pleine.
static func _relays(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if Transcendence.gauge_pct(state, e.id) < 50 or Transcendence.relays(state, e.id) >= int(cfg().get("relays", 3)):
		return
	var b := Transcendence.relay_building()
	var best: Colony = null
	for c in AiPlayer._own_colonies(state, e.id):
		if c.is_colony() and not c.buildings.has(b) and Economy.check_build(state, e.id, c.planet_id, b) == "" \
				and (best == null or c.population > best.population or (c.population == best.population and c.planet_id < best.planet_id)):
			best = c
	if best != null:
		AiPlayer._issue(ctx, SimCommands.build(e.id, best.planet_id, b))


## L'Arche : cap sur le système de bordure, et on s'y arrête.
static func _ark(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var f := Transcendence.ark_fleet(state, e.id)
	if f == null or f.is_moving():
		return
	var target := int(Transcendence.ark(state, e.id).get("target", -1))
	if target >= 0 and f.system_id != target:
		if AiPlayer._issue(ctx, SimCommands.move_fleet(e.id, f.id, target)):
			AiPlayer._intent(ctx, "mener l'Arche jusqu'à la Bordure")
