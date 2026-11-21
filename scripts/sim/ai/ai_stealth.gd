class_name AiStealth
extends RefCounted
## IA et furtivité (prop. 36 ; voir Stealth, data/stealth.json « ai »).
## - Réagir (niveau Normal et plus, react_skill) : après une embuscade subie, ou en guerre, l'IA
##   cherche le Réseau de détecteurs et bâtit un Réseau d'écoute à sa capitale et sur ses colonies
##   proches d'un rival.
## - Raids (niveau Vétéran et plus, raid_skill) : en guerre, ses flottes de guerre voilées passent en
##   Embuscade (elles frappent ce qu'elles trouvent) ; en paix, elles reviennent à la posture normale.
## La Recrue ignore la furtivité (elle subit, sans réagir).

static func cfg() -> Dictionary:
	return Stealth.cfg("ai")


static func _alarmed(ctx: Dictionary) -> bool:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if not e.wars.is_empty():
		return true
	var last := int(Stealth._sub(state, "amb").get(str(e.id), -99999))
	return state.tick - last <= int(cfg().get("listen_after_ambush_days", 720))


## L'empire a-t-il rencontré un peuple voilé (qui n'est pas son allié) ? Ses frontières s'équipent alors
## de Réseaux d'écoute : le Voile se perce de près (équilibrage B7).
static func _knows_veiled(ctx: Dictionary) -> bool:
	if ctx.has("knows_veiled"):
		return ctx["knows_veiled"]
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var out := false
	if not e.veiled():
		for o in e.contacts:
			if Veil.is_veiled(state, int(o)) and not state.get_empire(int(o)).eliminated and not Diplomacy.allied(state, e.id, int(o)):
				out = true
				break
	ctx["knows_veiled"] = out
	return out


## Bâtiments souhaités pour cette colonie (ajoutés aux vœux des défenses).
static func wishes(ctx: Dictionary, c: Colony) -> Array[String]:
	var out: Array[String] = []
	var state: GameState = ctx["state"]
	if not Stealth.enabled(state) or not c.is_established() or c.buildings.has("reseau_ecoute"):
		return out
	if AiPlayer._skill(ctx) < int(cfg().get("react_skill", 1)) or not (_alarmed(ctx) or _knows_veiled(ctx)):
		return out
	var e: Empire = ctx["e"]
	var sid := state.galaxy.get_planet(c.planet_id).system_id
	var capital := FactionTraits.capital_system(state, e.id) == sid
	if capital or int(AiPlayer.rival_distance(ctx).get(sid, 99)) <= 1:
		out.append("reseau_ecoute")
	return out


## Technologie à chercher en priorité (« » si rien).
static func research_wish(ctx: Dictionary) -> String:
	var state: GameState = ctx["state"]
	if not Stealth.enabled(state) or AiPlayer._skill(ctx) < int(cfg().get("react_skill", 1)) or not (_alarmed(ctx) or _knows_veiled(ctx)):
		return ""
	var e: Empire = ctx["e"]
	for t in ["capteurs", "detecteurs_1"]:
		if not e.techs.has(t):
			return t
	return ""


static func think(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	if not Stealth.enabled(state):
		return
	var e: Empire = ctx["e"]
	var t := research_wish(ctx)
	if t != "" and not e.research_queue.has(t):
		AiPlayer._issue(ctx, SimCommands.research(e.id, t))
	if AiPlayer._skill(ctx) < int(cfg().get("raid_skill", 2)):
		return
	var at_war := not e.wars.is_empty()
	for f in AiPlayer._warfleets(ctx):
		if Stealth.base_cloak(state, f) <= 0 or Veil.is_veiled(state, e.id):
			continue
		var want := "ambush" if at_war else ""
		if Stealth.posture(state, f) != want:
			AiPlayer._issue(ctx, SimCommands.stealth_act(e.id, "pose", f.id, -1, want))
