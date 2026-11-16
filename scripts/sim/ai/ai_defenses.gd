class_name AiDefenses
extends RefCounted
## IA et défenses spatiales (prop. 36 ; voir Defenses, data/defenses.json « ai »).
## - Où : la capitale, et les systèmes à front_jumps sauts ou moins d'un rival (en guerre, ou dès le
##   niveau Vétéran en paix). La Recrue bâtit au hasard de ses colonies (elle place mal), les autres sur
##   la colonie la plus peuplée du système.
## - Quoi, dans l'ordre : la station, son palier suivant, des modules (armes d'abord, puis blindage et
##   bouclier ; l'inhibiteur et le mouilleur pour le Vétéran aux goulots), des plates-formes tant qu'il
##   reste de la place, et un bouclier planétaire à la capitale.
## - Combien : jamais sous un plancher de matériaux qui dépend du niveau (min_materials).
## L'estimation des cibles ajoute la puissance des défenses fixes (AiPlayer._enemy_power_map).

const MODULES_BASE := ["module_batterie", "module_missiles", "module_blindage", "module_rayons", "module_bouclier", "module_antimissile", "module_hangar"]
const PLATFORMS := ["plateforme_missiles", "plateforme_canon", "plateforme_rayons", "plateforme_antimissile"]


static func cfg() -> Dictionary:
	return Defenses.cfg("ai")


## Chantiers de défense souhaités pour cette colonie, du plus urgent au moins urgent.
static func wishes(ctx: Dictionary, c: Colony) -> Array[String]:
	var out: Array[String] = []
	var state: GameState = ctx["state"]
	if not Defenses.enabled(state) or not c.is_established():
		return out
	var e: Empire = ctx["e"]
	var skill := AiPlayer._skill(ctx)
	var floor_m: Array = cfg().get("min_materials", [400, 250, 200])
	if AiPlayer._res(ctx, "materials") < int(floor_m[clampi(skill, 0, floor_m.size() - 1)]):
		return out
	var sid := state.galaxy.get_planet(c.planet_id).system_id
	var capital := FactionTraits.capital_system(state, e.id) == sid
	var front := int(AiPlayer.rival_distance(ctx).get(sid, 99)) <= int(cfg().get("front_jumps", 2))
	if front and e.wars.is_empty() and skill < 2:
		front = false
	if not capital and not front:
		return out
	var st := Defenses.station(state, sid)
	if st.is_empty():
		if _site(state, sid, e.id, skill) == c.planet_id:
			out.append("bastion")
		return out
	if int(st["pid"]) != c.planet_id:
		return out
	var t := int(st["t"])
	var next := String(Defenses.tier_def(t + 1).get("building", ""))
	if next != "":
		out.append(next)
	var mods: Array = MODULES_BASE.duplicate()
	if skill >= 2 and front and Defenses.full(state):
		mods.push_front("module_inhibiteur")
		mods.append("module_mouilleur")
	if skill >= 1:
		mods.append("module_reparation")
		mods.append("module_commandement")
	for m in mods:
		if not c.buildings.has(m) or Defenses.module_def(m).get("fx", "") in ["armor", "shield"]:
			out.append(String(m))
	if Defenses.full(state):
		# Une plate-forme par réflexion, en tournant sur les types : le canon ionique d'abord au palier III.
		if t >= 3:
			out.append("canon_ionique")
		@warning_ignore("integer_division")
		out.append(String(PLATFORMS[(state.tick / 30 + sid) % PLATFORMS.size()]))
	if capital:
		out.append("bouclier_planetaire_2" if c.buildings.has("bouclier_planetaire") else "bouclier_planetaire")
	return out


## Les défenses passent-elles avant le reste ? En guerre, ou quand les matériaux s'entassent (trois fois
## le plancher du niveau).
static func first(ctx: Dictionary) -> bool:
	var e: Empire = ctx["e"]
	if not e.wars.is_empty():
		return true
	var floor_m: Array = cfg().get("min_materials", [400, 250, 200])
	return AiPlayer._res(ctx, "materials") >= 3 * int(floor_m[clampi(AiPlayer._skill(ctx), 0, floor_m.size() - 1)])


## Colonie qui portera la station : la plus peuplée du système (la Recrue prend la première venue).
static func _site(state: GameState, sid: int, eid: int, skill: int) -> int:
	var best: Colony = null
	for pid in state.galaxy.systems[sid].planet_ids:
		var o: Colony = state.colonies.get(pid)
		if o == null or o.owner != eid or not o.is_established():
			continue
		if skill <= 0:
			return pid
		if best == null or o.population > best.population:
			best = o
	return best.planet_id if best != null else -1


## Poids (en %) des défenses fixes dans l'estimation d'une cible, selon le niveau.
static func power_weight(ctx: Dictionary) -> int:
	var arr: Array = cfg().get("power_weight_pct", [0, 60, 100])
	return int(arr[clampi(AiPlayer._skill(ctx), 0, arr.size() - 1)])
