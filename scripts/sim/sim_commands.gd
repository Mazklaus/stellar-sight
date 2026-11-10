class_name SimCommands
extends RefCounted
## Les ordres des joueurs. C'est le SEUL moyen pour un joueur de modifier la partie.
##
## Un ordre est un simple dictionnaire (facile à envoyer sur le réseau ou à rejouer) :
##   {"type": "rename_system", "player": 0, "system": 12, "name": "Nouvelle-Aube"}
## Il est d'abord validé, puis appliqué par la Simulation à une frontière de tick.
## En multijoueur, les clients enverront leurs ordres à l'hôte, qui les validera,
## fixera leur ordre d'application et les rediffusera.

const NAME_MAX_LENGTH := 32


static func rename_system(player: int, system_id: int, new_name: String) -> Dictionary:
	return {"type": "rename_system", "player": player, "system": system_id, "name": new_name}


## Lance une colonie ("colony") ou un avant-poste ("outpost") sur une planète.
## Une colonie sur un de ses propres avant-postes le transforme en colonie.
static func colonize(player: int, planet_id: int, kind: String = Colony.KIND_COLONY) -> Dictionary:
	return {"type": "colonize", "player": player, "planet": planet_id, "kind": kind}


## Lance la construction d'un bâtiment sur une colonie ou un avant-poste.
static func build(player: int, planet_id: int, building_id: String) -> Dictionary:
	return {"type": "build", "player": player, "planet": planet_id, "building": building_id}


## Construit un vaisseau au chantier spatial d'une colonie.
static func build_ship(player: int, planet_id: int, ship_id: String) -> Dictionary:
	return {"type": "build_ship", "player": player, "planet": planet_id, "ship": ship_id}


## Envoie une flotte vers un système, par le plus court chemin connu.
static func move_fleet(player: int, fleet_id: int, system_id: int) -> Dictionary:
	return {"type": "move_fleet", "player": player, "fleet": fleet_id, "system": system_id}


## Arrête une flotte au prochain système (ou fait demi-tour si c'est plus près).
static func stop_fleet(player: int, fleet_id: int) -> Dictionary:
	return {"type": "stop_fleet", "player": player, "fleet": fleet_id}


## Donne (ou retire, avec "") un ordre permanent à une flotte : Fleet.ORDER_EXPLORE.
static func set_fleet_order(player: int, fleet_id: int, order: String) -> Dictionary:
	return {"type": "set_fleet_order", "player": player, "fleet": fleet_id, "order": order}


## Verse tous les vaisseaux d'une flotte dans une autre (même système, à l'arrêt).
static func merge_fleets(player: int, fleet_id: int, into_id: int) -> Dictionary:
	return {"type": "merge_fleets", "player": player, "fleet": fleet_id, "into": into_id}


## Détache un vaisseau d'une classe donnée dans une nouvelle flotte.
static func split_fleet(player: int, fleet_id: int, ship_id: String) -> Dictionary:
	return {"type": "split_fleet", "player": player, "fleet": fleet_id, "ship": ship_id}


## Chœur Éternel : sacrifie un fidèle d'une colonie (-1 population) pour nourrir la ferveur.
static func sacrifice(player: int, planet_id: int) -> Dictionary:
	return {"type": "sacrifice", "player": player, "planet": planet_id}


## Concorde de Vael : vote d'urgence, achève tout de suite le chantier ("building" ou "ship")
## d'une planète contre de l'influence.
static func rush(player: int, planet_id: int, what: String) -> Dictionary:
	return {"type": "rush", "player": player, "planet": planet_id, "what": what}


## Déclare la guerre à un empire rencontré (la guerre vaut dans les deux sens).
static func declare_war(player: int, target: int) -> Dictionary:
	return {"type": "declare_war", "player": player, "target": target}


## Propose un traité (Diplomacy.TREATY_IDS) à un empire rencontré. Une IA répond tout de suite,
## un joueur humain reçoit la proposition.
static func propose_treaty(player: int, target: int, treaty: String) -> Dictionary:
	return {"type": "propose_treaty", "player": player, "target": target, "treaty": treaty}


## Répond à une proposition reçue.
static func answer_proposal(player: int, proposal_id: int, accept: bool) -> Dictionary:
	return {"type": "answer_proposal", "player": player, "proposal": proposal_id, "accept": accept}


## Rompt un traité : "alliance", "peace" (après la trêve) ou "trade".
static func cancel_treaty(player: int, target: int, treaty: String) -> Dictionary:
	return {"type": "cancel_treaty", "player": player, "target": target, "treaty": treaty}


## Soudoie l'héritier d'une dynastie féodale rivale (sa loyauté baisse).
static func bribe_heir(player: int, target: int) -> Dictionary:
	return {"type": "bribe_heir", "player": player, "target": target}


## Banquet des lignées : la dynastie regagne la loyauté de son héritier.
static func banquet(player: int) -> Dictionary:
	return {"type": "banquet", "player": player}


## Une république fait arbitrer la guerre entre deux autres empires (paix imposée).
static func mediate(player: int, a: int, b: int) -> Dictionary:
	return {"type": "mediate", "player": player, "a": a, "b": b}


## Choisit la tactique de combat d'une flotte (Combat.tactic_ids()).
static func set_tactic(player: int, fleet_id: int, tactic: String) -> Dictionary:
	return {"type": "set_tactic", "player": player, "fleet": fleet_id, "tactic": tactic}


## Remet une flotte à niveau dans un chantier ami : ses vaisseaux prennent les marques actuelles.
static func refit(player: int, fleet_id: int) -> Dictionary:
	return {"type": "refit", "player": player, "fleet": fleet_id}


## Enregistre un modèle de vaisseau (voir Designs.check_save pour spec).
static func save_design(player: int, spec: Dictionary) -> Dictionary:
	return {"type": "save_design", "player": player, "spec": spec.duplicate(true)}


## Retire un modèle de la liste de construction (retired false : l'y remet). Ses vaisseaux restent.
static func retire_design(player: int, design_id: String, retired := true) -> Dictionary:
	return {"type": "retire_design", "player": player, "design": design_id, "retired": retired}


## Débarque les troupes d'une flotte sur le système ennemi où elle stationne : il change de mains.
static func invade(player: int, fleet_id: int) -> Dictionary:
	return {"type": "invade", "player": player, "fleet": fleet_id}


## Met une technologie dans la file de recherche (en tête avec front : elle devient la recherche en cours).
static func research(player: int, tech_id: String, front := false) -> Dictionary:
	return {"type": "research_queue", "player": player, "tech": tech_id, "front": front}


## Retire une technologie de la file de recherche (et celles qui en dépendaient).
static func research_remove(player: int, tech_id: String) -> Dictionary:
	return {"type": "research_remove", "player": player, "tech": tech_id}


## Renvoie "" si l'ordre est applicable à cet état, sinon la raison du refus.
static func validate(state: GameState, cmd: Dictionary) -> String:
	if not cmd.has("type") or not cmd.has("player"):
		return "ordre incomplet"
	match String(cmd["type"]):
		"rename_system":
			var id := int(cmd.get("system", -1))
			if state.galaxy.get_system(id) == null:
				return "système inconnu : %d" % id
			var n := String(cmd.get("name", "")).strip_edges()
			if n.is_empty():
				return "nom vide"
			if n.length() > NAME_MAX_LENGTH:
				return "nom trop long (%d caractères max)" % NAME_MAX_LENGTH
			return ""
		"colonize":
			return Economy.check_colonize(state, int(cmd["player"]), int(cmd.get("planet", -1)), String(cmd.get("kind", "")))
		"build":
			return Economy.check_build(state, int(cmd["player"]), int(cmd.get("planet", -1)), String(cmd.get("building", "")))
		"build_ship":
			return Fleets.check_build_ship(state, int(cmd["player"]), int(cmd.get("planet", -1)), String(cmd.get("ship", "")))
		"move_fleet":
			return Fleets.check_move(state, int(cmd["player"]), int(cmd.get("fleet", -1)), int(cmd.get("system", -1)))
		"stop_fleet":
			return Fleets.check_stop(state, int(cmd["player"]), int(cmd.get("fleet", -1)))
		"set_fleet_order":
			return Fleets.check_order(state, int(cmd["player"]), int(cmd.get("fleet", -1)), String(cmd.get("order", "")))
		"merge_fleets":
			return Fleets.check_merge(state, int(cmd["player"]), int(cmd.get("fleet", -1)), int(cmd.get("into", -1)))
		"split_fleet":
			return Fleets.check_split(state, int(cmd["player"]), int(cmd.get("fleet", -1)), String(cmd.get("ship", "")))
		"sacrifice":
			return FactionTraits.check_sacrifice(state, int(cmd["player"]), int(cmd.get("planet", -1)))
		"rush":
			return FactionTraits.check_rush(state, int(cmd["player"]), int(cmd.get("planet", -1)), String(cmd.get("what", "")))
		"declare_war":
			return Combat.check_declare_war(state, int(cmd["player"]), int(cmd.get("target", -1)))
		"propose_treaty":
			return Diplomacy.check_propose(state, int(cmd["player"]), int(cmd.get("target", -1)), String(cmd.get("treaty", "")))
		"answer_proposal":
			return Diplomacy.check_answer(state, int(cmd["player"]), int(cmd.get("proposal", -1)), bool(cmd.get("accept", false)))
		"cancel_treaty":
			return Diplomacy.check_cancel(state, int(cmd["player"]), int(cmd.get("target", -1)), String(cmd.get("treaty", "")))
		"bribe_heir":
			return Diplomacy.check_bribe(state, int(cmd["player"]), int(cmd.get("target", -1)))
		"banquet":
			return Diplomacy.check_banquet(state, int(cmd["player"]))
		"mediate":
			return Diplomacy.check_mediate(state, int(cmd["player"]), int(cmd.get("a", -1)), int(cmd.get("b", -1)))
		"set_tactic":
			return Combat.check_tactic(state, int(cmd["player"]), int(cmd.get("fleet", -1)), String(cmd.get("tactic", "")))
		"save_design":
			return Designs.check_save(state, int(cmd["player"]), cmd.get("spec", {}))
		"retire_design":
			return Designs.check_retire(state, int(cmd["player"]), String(cmd.get("design", "")))
		"refit":
			return Fleets.check_refit(state, int(cmd["player"]), int(cmd.get("fleet", -1)))
		"invade":
			return Combat.check_invade(state, int(cmd["player"]), int(cmd.get("fleet", -1)))
		"research_queue":
			return Research.check_queue(state, int(cmd["player"]), String(cmd.get("tech", "")), bool(cmd.get("front", false)))
		"research_remove":
			return Research.check_remove(state, int(cmd["player"]), String(cmd.get("tech", "")))
		_:
			return "type d'ordre inconnu : %s" % cmd["type"]


## Applique un ordre déjà validé.
static func apply(state: GameState, cmd: Dictionary) -> void:
	match String(cmd["type"]):
		"rename_system":
			var sys := state.galaxy.get_system(int(cmd["system"]))
			var old_name := sys.system_name
			sys.system_name = String(cmd["name"]).strip_edges()
			if old_name != sys.system_name:
				state.add_chronicle("Les cartographes rebaptisent %s : on dira désormais %s." % [old_name, sys.system_name])
		"colonize":
			var e := state.get_empire(int(cmd["player"]))
			var pid := int(cmd["planet"])
			var kind := String(cmd["kind"])
			Economy.pay(e, Economy.claim_cost_for(state, e.id, pid, kind))
			var p := state.galaxy.get_planet(pid)
			if Economy.needs_ship(state, e.id, pid):
				# Le vaisseau colon se démonte : ses modules deviennent les premiers bâtiments.
				var f := Fleets.colonizer_fleet(state, e.id, p.system_id)
				f.remove_ship(Fleets.colonizer_ship(f))
				if f.ships.is_empty():
					state.fleets.erase(f.id)
			var c: Colony = state.colonies.get(pid)
			if c == null:
				c = Colony.new()
				c.planet_id = pid
				c.owner = e.id
			c.kind = kind
			c.days_left = Economy.claim_days(kind)
			state.add_colony(c)
		"build":
			var e := state.get_empire(int(cmd["player"]))
			var c: Colony = state.colonies[int(cmd["planet"])]
			var b := GameData.building(String(cmd["building"]))
			Economy.pay(e, Economy.building_cost(state, e.id, String(cmd["building"])))
			c.construction = String(cmd["building"])
			c.construction_days = int(b["days"])
		"build_ship":
			var e := state.get_empire(int(cmd["player"]))
			var c: Colony = state.colonies[int(cmd["planet"])]
			var sd := GameData.ship(String(cmd["ship"]))
			Economy.pay(e, Fleets.ship_cost(state, e.id, String(cmd["ship"])))
			c.population -= int(sd.get("pop_cost", 0))
			c.ship_build = String(cmd["ship"])
			c.ship_days = Fleets.ship_days(state, e.id, String(cmd["ship"]))
		"move_fleet":
			var f: Fleet = state.fleets[int(cmd["fleet"])]
			var plan := Fleets.plan_route(state, f, int(cmd["system"]))
			f.standing_order = ""  # un ordre donné à la main reprend la main sur l'exploration
			f.system_id = int(plan["system"])
			f.path.assign(plan["path"])
			f.progress = int(plan["progress"])
		"stop_fleet":
			var f: Fleet = state.fleets[int(cmd["fleet"])]
			f.standing_order = ""
			var lane := Fleets.lane_length(state.galaxy, f.system_id, f.path[0])
			if f.progress * 2 >= lane:
				f.path.resize(1)  # finir la route en cours
			else:
				var back := f.system_id
				f.system_id = f.path[0]
				f.path.assign([back])
				f.progress = lane - f.progress
		"set_fleet_order":
			var f: Fleet = state.fleets[int(cmd["fleet"])]
			f.standing_order = String(cmd["order"])
			if f.is_exploring():
				FleetSystem.explore_step(state, f)  # cap immédiat sur la frontière, sans attendre le tick
		"merge_fleets":
			var f: Fleet = state.fleets[int(cmd["fleet"])]
			var into: Fleet = state.fleets[int(cmd["into"])]
			for i in f.ships.size():
				into.add_ship(f.ships[i], f.hp[i], f.gen[i])
			into.troops += f.troops
			state.fleets.erase(f.id)
		"split_fleet":
			var f: Fleet = state.fleets[int(cmd["fleet"])]
			var ship_id := String(cmd["ship"])
			var before := Combat.max_troops(f, state)
			var ship_hp := f.remove_ship_hp(ship_id)
			var nf := state.spawn_ship(f.owner, ship_id, f.system_id)
			nf.hp[0] = ship_hp
			nf.gen[0] = f.last_gen
			nf.tactic = f.tactic
			# Les troupes se répartissent selon la capacité de chaque flotte.
			@warning_ignore("integer_division")
			nf.troops = f.troops * Combat.max_troops(nf, state) / maxi(1, before)
			f.troops -= nf.troops
		"sacrifice":
			var e := state.get_empire(int(cmd["player"]))
			var c: Colony = state.colonies[int(cmd["planet"])]
			var fv: Dictionary = e.faction()["fervor"]
			c.population -= 1
			c.growth = 0
			e.fervor = mini(int(fv["max"]), e.fervor + FactionTraits.sacrifice_gain(state, e.id))
			Research.count_stat(state, e.id, "sacrifices")
			state.add_chronicle("Offrande sur %s : un fidèle rejoint le dieu-machine. Il paraît que c'est un honneur ; il paraît surtout que c'est obligatoire." % [
					state.galaxy.get_planet(c.planet_id).display_name(state.galaxy)])
		"rush":
			var e := state.get_empire(int(cmd["player"]))
			var pid := int(cmd["planet"])
			var what := String(cmd["what"])
			e.resources["influence"] = int(e.resources["influence"]) - FactionTraits.rush_cost(state, e.id, pid, what)
			var c: Colony = state.colonies[pid]
			# Le chantier s'achève au prochain jour de simulation, comme s'il était arrivé à terme.
			if what == FactionTraits.RUSH_BUILDING:
				c.construction_days = 1
			else:
				c.ship_days = 1
		"declare_war":
			Combat.start_war(state, int(cmd["player"]), int(cmd["target"]))
		"propose_treaty":
			Diplomacy.propose(state, int(cmd["player"]), int(cmd["target"]), String(cmd["treaty"]))
		"answer_proposal":
			Diplomacy.answer(state, int(cmd["proposal"]), bool(cmd["accept"]))
		"cancel_treaty":
			Diplomacy.cancel(state, int(cmd["player"]), int(cmd["target"]), String(cmd["treaty"]))
		"bribe_heir":
			Diplomacy.bribe(state, int(cmd["player"]), int(cmd["target"]))
		"banquet":
			Diplomacy.banquet(state, int(cmd["player"]))
		"mediate":
			Diplomacy.mediate(state, int(cmd["player"]), int(cmd["a"]), int(cmd["b"]))
		"set_tactic":
			state.fleets[int(cmd["fleet"])].tactic = String(cmd["tactic"])
		"save_design":
			Designs.save(state, int(cmd["player"]), cmd["spec"])
		"retire_design":
			state.designs[String(cmd["design"])]["retired"] = bool(cmd.get("retired", true))
		"refit":
			var f: Fleet = state.fleets[int(cmd["fleet"])]
			Economy.pay(state.get_empire(f.owner), Fleets.refit_cost(state, f))
			f.refit_left = Fleets.refit_days()
		"invade":
			var f: Fleet = state.fleets[int(cmd["fleet"])]
			var sid := f.system_id
			f.troops -= Combat.garrison(state, sid)  # les défenseurs se battent jusqu'au dernier
			Combat.capture_system(state, sid, f.owner)
		"research_queue":
			Research.apply_queue(state, int(cmd["player"]), String(cmd["tech"]), bool(cmd.get("front", false)))
		"research_remove":
			Research.apply_remove(state, int(cmd["player"]), String(cmd["tech"]))
