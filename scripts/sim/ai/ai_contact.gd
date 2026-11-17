class_name AiContact
extends RefCounted
## IA et Contact (prop. 43 ; voir Contact, data/contact.json « ai »).
## Une fois par mois, si le pilier est en jeu : cherche Écoute profonde à l'ère IV, bâtit des Oreilles
## à la Bordure (de préférence près d'un trou noir ou d'une géante bleue, jamais dans une nébuleuse),
## envoie une flotte au repos relever l'Écho le plus proche, règle la part du Savoir selon son niveau,
## vérifie les alertes au lieu de les annoncer, audite les Plans, cherche la clé par intuition, bâtit
## le Héraut et répond, sauf si le dossier penche vers les Affamés ou les Semeurs non audités.
## Les lots 2 et 3 ajoutent l'échange de fragments, les Consortiums et les objecteurs (ContactRace.ai).
## La Recrue oublie souvent.

static func cfg() -> Dictionary:
	return Contact.cfg("ai")


static func think(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if not Contact.applies(state, e.id) or Contact.done(state, e.id) or Contact.failed(state, e.id):
		return
	@warning_ignore("integer_division")
	var month := state.tick / Contact.month_days() + 1
	if Contact.stat(state, e.id, "ai_month") >= month:
		return
	Contact._stat(state, e.id, "ai_month", month - Contact.stat(state, e.id, "ai_month"))
	if AiPlayer._forgets(ctx):
		return
	_research(ctx)
	if not Contact.listens(state, e.id):
		return
	_share(ctx)
	_alert(ctx)
	_ears(ctx)
	_echo(ctx)
	_plans(ctx)
	_heraut(ctx)
	ContactRace.ai(ctx)


static func _research(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	for t in [Contact.listen_tech(), Contact.grammar_tech()]:
		if e.techs.has(t):
			continue
		if int(Research.tech(t).get("era", 9)) > Research.current_era(state, e.id):
			return
		var step := AiGenetics.reachable(state, e, t, 3)
		if step != "" and not e.research_queue.has(step):
			AiPlayer._issue(ctx, SimCommands.research(e.id, step))
		return


static func _share(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if Contact.route_count(state, e.id) <= 0:
		return
	var table: Array = cfg().get("share", [10])
	var i := maxi(0, AiLevels.ids().find(e.ai_level))
	var v := int(table[mini(i, table.size() - 1)])
	@warning_ignore("integer_division")
	v = v / 10 * 10 if v % 10 < 5 else (v / 10 + 1) * 10
	v = clampi(v, 0, Contact.c_int("gauge", "share_max", 30))
	if Contact.share(state, e.id) != v:
		AiPlayer._issue(ctx, SimCommands.ct_act(e.id, "share", {"v": v}))


static func _alert(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if Contact.check(state, e.id, "verify", {}) == "":
		AiPlayer._issue(ctx, SimCommands.ct_act(e.id, "verify"))


## Oreilles : sur les colonies et avant-postes de la Bordure, les systèmes amplifiés d'abord.
static func _ears(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if Contact.ears_of(state, e.id).size() >= int(cfg().get("ears", 2)):
		return
	var b := Contact.ear_building()
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner == e.id and c.construction == b:
			return  # une à la fois
	var best := -1
	var best_score := -1
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner != e.id or c.construction != "":
			continue
		var sid := state.galaxy.get_planet(int(pid)).system_id
		if Economy.check_build(state, e.id, int(pid), b) != "":
			continue
		var score := (2 if Contact.is_edge(state, sid) else 0) + (1 if Contact.amplified(state, sid) else 0)
		if score > best_score:
			best_score = score
			best = int(pid)
	if best >= 0 and best_score >= 2:
		AiPlayer._issue(ctx, SimCommands.build(e.id, best, b))


## Échos : une flotte au repos, sans ennemi, part relever l'Écho exploré le plus proche.
static func _echo(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if Contact.routes(state, e.id).has("echo") or Contact.captured(state, e.id):
		return
	for fid in state.fleets:
		var f: Fleet = state.fleets[fid]
		if f.owner == e.id and Contact.is_echo(state, f.system_id):
			return  # déjà en relevé
	var cap := FactionTraits.capital_system(state, e.id)
	if cap < 0:
		return
	var jumps := FactionTraits.jumps_from(state.galaxy, cap)
	var target := -1
	var tj := 999
	for sid in Contact.echo_sites(state):
		if not e.explored.has(sid) or not jumps.has(sid):
			continue
		var ow := state.system_owner(sid)
		if ow >= 0 and ow != e.id:
			continue
		if int(jumps[sid]) < tj:
			tj = int(jumps[sid])
			target = sid
	if target < 0:
		return
	var ids := state.fleets.keys()
	ids.sort()
	for fid in ids:
		var f: Fleet = state.fleets[fid]
		if f.owner != e.id or f.is_moving() or f.ships.is_empty():
			continue
		if AiPlayer._issue(ctx, SimCommands.move_fleet(e.id, f.id, target)):
			return


static func _plans(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if Contact.check(state, e.id, "plans_audit", {}) == "":
		AiPlayer._issue(ctx, SimCommands.ct_act(e.id, "plans_audit" if bool(cfg().get("audit", true)) else "plans_raw"))
	if Contact.check(state, e.id, "intuition", {}) == "":
		AiPlayer._issue(ctx, SimCommands.ct_act(e.id, "intuition"))


## Le Héraut sur la capitale, puis la Transmission, si l'on ne craint pas les Lointains.
static func _heraut(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if not Contact.has_layer(state, e.id, "plans") or Contact.transmitting(state, e.id):
		return
	if Contact.fears(state, e.id) and Contact.nature_mode(state) != "sans_indices":
		return
	if not Contact.has_heraut(state, e.id):
		var b := Contact.heraut_building()
		if Economy.check_build(state, e.id, e.capital_planet, b) == "":
			AiPlayer._issue(ctx, SimCommands.build(e.id, e.capital_planet, b))
		return
	if Contact.check_transmit(state, e.id) == "":
		AiPlayer._issue(ctx, SimCommands.ct_act(e.id, "transmit"))
