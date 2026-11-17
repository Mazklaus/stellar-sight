class_name AiMegas
extends RefCounted
## IA et mégastructures (prop. 44 ; voir Megastructures, data/megastructures.json).
## Une fois par mois, si le pilier est en jeu : cherche les Architectes stellaires dès l'ère II, garde un
## Vaisseau-architecte, avance ses mégastructures étape par étape en gardant une réserve, répare ce qui
## est ruiné, relève les ruines de ses systèmes et pose de nouveaux chantiers par ordre de préférence.
## Elle ne bâtit jamais de superarme (prop. 27 : choix laissé au joueur), mais allume l'Anneau
## d'extinction qu'elle aurait pris si la crise approche. La Recrue oublie souvent.

const PREFS := ["essaim_dyson", "forge_noyau", "decompresseur", "sphere_dyson", "matriochka", "nexus_savoir",
	"monde_anneau", "siphon_geante", "ascenseur_orbital", "anneau_orbital", "mega_chantier", "centre_coordination",
	"reseau_veille", "forum_interstellaire", "oeuvre_monumentale", "catapulte_quantique"]
const RESERVE := {"energy": 150, "materials": 250}


static func think(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if not Megastructures.applies(state, e.id):
		return
	@warning_ignore("integer_division")
	var month := state.tick / int(GameData.rules()["month_days"]) + 1
	if Megastructures.stat(state, e.id, "ai_month") >= month:
		return
	Megastructures._stat(state, e.id, "ai_month", month - Megastructures.stat(state, e.id, "ai_month"))
	if AiPlayer._forgets(ctx):
		return
	_research(ctx)
	_purge(ctx)
	_modules(ctx)
	if _advance(ctx):
		return
	if _restore(ctx):
		return
	if not _architect(ctx):
		return
	_plan(ctx)


static func _rich(e: Empire, cost: Dictionary) -> bool:
	for r in RESERVE:
		if int(e.resources.get(r, 0)) < int(RESERVE[r]) + int(cost.get(r, 0)):
			return false
	return Economy.can_afford(e, cost)


static func _research(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var t := "architectes_stellaires"
	if e.techs.has(t) or Research.current_era(state, e.id) < 2 or not e.research_queue.is_empty():
		return
	var step := AiGenetics.reachable(state, e, t, 2)
	if step != "":
		AiPlayer._issue(ctx, SimCommands.research(e.id, step))


static func _purge(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	for m in Megastructures.owned_by(state, e.id):
		if String(m["k"]) == "anneau_extinction" and MegasWorld.check_purge(state, e.id, int(m["id"])) == "":
			var near := false
			var j := FactionTraits.jumps_from(state.galaxy, int(m["s"]))
			for fid in state.sorted_fleet_ids():
				var f: Fleet = state.fleets[fid]
				if Crisis.is_crisis_fleet(f) and int(j.get(f.system_id, 99)) <= 3:
					near = true
			if near and AiPlayer._issue(ctx, SimCommands.mega_act(e.id, "purge", {"id": int(m["id"])})):
				AiPlayer._intent(ctx, "allumer l'Anneau d'extinction")


static func _modules(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	for m in Megastructures.owned_by(state, e.id):
		if String(m["k"]) == "anneau_orbital" and String(m.get("mod", "")) == "" and Megastructures.check_module(state, e.id, int(m["id"]), "habitation") == "":
			AiPlayer._issue(ctx, SimCommands.mega_act(e.id, "module", {"id": int(m["id"]), "m": "habitation"}))


## Avancer ou réparer ce qu'on a déjà (le moins cher d'abord : on finit ce qu'on commence).
static func _advance(ctx: Dictionary) -> bool:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	for m in Megastructures.owned_by(state, e.id):
		var id := int(m["id"])
		if bool(m.get("dmg", 0)):
			if Megastructures.check_repair(state, e.id, id) == "" and _rich(e, Megastructures.repair_cost(state, e.id, m)):
				return AiPlayer._issue(ctx, SimCommands.mega_act(e.id, "repair", {"id": id}))
			continue
		if Megastructures.check_advance(state, e.id, id) != "":
			continue
		var cost := Megastructures.stage_cost(state, e.id, String(m["k"]), int(m["st"]), int(m["s"]))
		if _rich(e, cost) and AiPlayer._issue(ctx, SimCommands.mega_act(e.id, "advance", {"id": id})):
			AiPlayer._intent(ctx, "étendre %s" % Megastructures.label(String(m["k"])))
			return true
	return false


static func _restore(ctx: Dictionary) -> bool:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	for m in MegasWorld.ruins(state):
		if bool(m.get("rs", 0)) or MegasWorld.check_restore(state, e.id, int(m["id"])) != "":
			continue
		if _rich(e, MegasWorld.restore_cost(state, e.id, m)) and AiPlayer._issue(ctx, SimCommands.mega_act(e.id, "restore", {"id": int(m["id"])})):
			AiPlayer._intent(ctx, "relever une ruine : %s" % Megastructures.label(String(m["k"])))
			return true
	return false


## Garder un Vaisseau-architecte (en construire un s'il n'y en a pas). Renvoie true s'il y en a un libre.
static func _architect(ctx: Dictionary) -> bool:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var ship := Megastructures.ship_id()
	if not Fleets.ship_unlocked(state, e.id, ship):
		return false
	var all := Megastructures.architects_of(state, e.id)
	for f in all:
		if not Megastructures.architect_busy(state, f):
			return true
	if not all.is_empty() and all.size() >= 2:
		return false
	for c in AiPlayer._my_colonies(ctx):
		if c.ship_build == Megastructures.ship_id():
			return false  # déjà en chantier
	if not _rich(e, GameData.ship(ship).get("cost", {})):
		return false
	var yard := AiPlayer._best_yard(ctx, ship)
	if yard != null:
		AiPlayer._issue(ctx, SimCommands.build_ship(e.id, yard.planet_id, ship))
	return false


static func _plan(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if Megastructures.busy(state, e.id) >= Megastructures.slots(state, e.id):
		return
	for k in PREFS:
		if not Megastructures.kind_allowed(state, k) or not Megastructures.unlocked(state, e.id, k):
			continue
		var s := Megastructures.sites(state, e.id, k, 4)
		if s.is_empty():
			continue
		# La meilleure étoile pour ce qui en dépend (bleue d'abord), sinon le premier site.
		var best: Array = s[0]
		var best_v := -1
		for site: Array in s:
			var v := int(Megastructures.cfg("stars").get(state.galaxy.systems[int(site[0])].star_type, 100))
			if v > best_v:
				best_v = v
				best = site
		if not _rich(e, Megastructures.stage_cost(state, e.id, k, 0, int(best[0]))):
			return
		var d := {"k": k, "s": int(best[0]), "p": int(best[1])}
		if Megastructures.check_plan(state, e.id, k, int(best[0]), int(best[1])) == "" and AiPlayer._issue(ctx, SimCommands.mega_act(e.id, "plan", d)):
			AiPlayer._intent(ctx, "bâtir %s" % Megastructures.label(k))
		return
