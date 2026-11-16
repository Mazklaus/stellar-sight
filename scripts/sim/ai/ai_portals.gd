class_name AiPortals
extends RefCounted
## IA et portails de saut (prop. 36 ; voir Portals, data/portals.json « ai »), dès le niveau Normal :
## - relais hyperspatiaux : la capitale d'abord, puis un système voisin d'un de ses relais et plus proche
##   du front, jusqu'à relays_max ;
## - portails de saut : la capitale d'abord, puis les systèmes du front (rival à 3 sauts ou moins),
##   jusqu'à gates_max ; un Grand portail sur un portail dès que la technologie le permet ;
## - une Ancre sur un trou de ver qu'elle tient, et la restauration d'un portail ancien qu'elle tient ;
## - recherche : la Stabilisation des trous de ver pèse triple si elle connaît un trou de ver, les
##   relais et portails dès qu'elle a des rivaux.
## Jamais sous la réserve de matériaux (min_materials) ; les chemins de flotte empruntent déjà trous de
## ver et portails (Fleets._dijkstra), et l'inhibiteur ennemi ferme la sortie (Portals._inhibited).


static func cfg() -> Dictionary:
	return Portals.cfg("ai")


static func _count(ctx: Dictionary, kinds: Array) -> int:
	var n := 0
	for c in AiPlayer._my_colonies(ctx):
		for b in c.buildings:
			if kinds.has(b):
				n += 1
		if kinds.has(c.construction):
			n += 1
	return n


## Chantier de portail souhaité pour cette colonie ("" sinon).
static func wish(ctx: Dictionary, c: Colony) -> String:
	var state: GameState = ctx["state"]
	if not Portals.enabled(state) or not c.is_established() or AiPlayer._skill(ctx) < 1:
		return ""
	if AiPlayer._res(ctx, "materials") < int(cfg().get("min_materials", 600)):
		return ""
	var e: Empire = ctx["e"]
	var sid := state.galaxy.get_planet(c.planet_id).system_id
	# Une seule colonie par système porte les bâtiments : la première de l'empire dans le système.
	for pid in state.galaxy.systems[sid].planet_ids:
		var o: Colony = state.colonies.get(pid)
		if o != null and o.owner == e.id:
			if o != c:
				return ""
			break
	var cap := FactionTraits.capital_system(state, e.id)
	var front := int(AiPlayer.rival_distance(ctx).get(sid, 99)) <= 3
	if c.buildings.has("portail_saut") and Research.knows(state, e.id, "grands_portails"):
		return "grand_portail"
	if Portals.full(state) and int((state.portals.get("ruins", {}) as Dictionary).get(str(sid), -1)) == 0 and Research.knows(state, e.id, Portals.TECH_WORM):
		return "portail_ancien"
	if Portals.full(state) and Portals.wormhole_at(state, sid) >= 0 and not Portals.anchored(state, sid) and Research.knows(state, e.id, Portals.TECH_WORM):
		return "ancre_ver"
	if Research.knows(state, e.id, "portails_saut") and not Portals.has_gate(state, sid) and AiPlayer._res(ctx, "crystals") >= 60:
		var gates := _count(ctx, Portals.GATE_BUILDINGS)
		if gates < int(cfg().get("gates_max", 3)) and (sid == cap or (front and Portals.has_gate(state, cap))):
			return "portail_saut"
	if Research.knows(state, e.id, "relais_hyperspatiaux") and not Portals.has_relay(state, sid) and AiPlayer._res(ctx, "crystals") >= 20:
		var relays := _count(ctx, ["relais_hyper"])
		if relays < int(cfg().get("relays_max", 4)):
			if sid == cap:
				return "relais_hyper"
			var here := int(AiPlayer.rival_distance(ctx).get(sid, 99))
			for n in state.galaxy.systems[sid].neighbors:
				if Portals.has_relay(state, n) and state.system_owner(n) == e.id and int(AiPlayer.rival_distance(ctx).get(n, 99)) > here:
					return "relais_hyper"
	return ""


## Poids de recherche multiplié pour les technologies de portails (1 sinon).
static func tech_mult(ctx: Dictionary, tid: String) -> int:
	var state: GameState = ctx["state"]
	if not Portals.enabled(state):
		return 1
	var e: Empire = ctx["e"]
	if tid == Portals.TECH_WORM:
		for pr in state.portals.get("wh", []):
			if e.explored.has(int(pr[0])) or e.explored.has(int(pr[1])):
				return 3
		return 1
	if (tid == "relais_hyperspatiaux" or tid == "portails_saut") and not e.contacts.is_empty():
		return 2
	return 1
