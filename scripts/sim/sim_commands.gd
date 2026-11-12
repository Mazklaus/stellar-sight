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


## Registre Cosmique : replier le temps sur un chantier ("building" ou "ship"), contre des échos.
static func fold(player: int, planet_id: int, what: String) -> Dictionary:
	return {"type": "fold", "player": player, "planet": planet_id, "what": what}


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


## Une dynastie féodale unit ses lignées à celles d'un allié (victoire de l'Élu des routes).
static func unite_lineages(player: int, target: int) -> Dictionary:
	return {"type": "unite_lineages", "player": player, "target": target}


## Une république fait arbitrer la guerre entre deux autres empires (paix imposée).
static func mediate(player: int, a: int, b: int) -> Dictionary:
	return {"type": "mediate", "player": player, "a": a, "b": b}


## Contrat de flotte entre un syndicat (merc) et un client en guerre contre target ; player est l'un des deux.
static func contract(player: int, merc: int, client: int, target: int) -> Dictionary:
	return {"type": "contract", "player": player, "merc": merc, "client": client, "target": target}


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


## Affecte n cellules d'espionnage chez target (target == player : contre-espionnage chez soi).
static func spy_cells(player: int, target: int, n: int) -> Dictionary:
	return {"type": "spy_cells", "player": player, "target": target, "n": n}


## Lance une sonde vers un système connu hors de vue : relevé ponctuel.
static func probe(player: int, system_id: int) -> Dictionary:
	return {"type": "probe", "player": player, "system": system_id}


## Lance une opération d'espionnage (data/espionage.json "operations") chez target.
static func spy_op(player: int, target: int, op_id: String) -> Dictionary:
	return {"type": "spy_op", "player": player, "target": target, "op": op_id}


## Annule l'opération en cours chez target.
static func spy_cancel(player: int, target: int) -> Dictionary:
	return {"type": "spy_cancel", "player": player, "target": target}


## Répond à des espions démasqués chez soi : "expel" ou "reparation".
## Choisit un héros de l'offre en attente (index ; -1 = décline l'offre).
static func hero_pick(player: int, index: int) -> Dictionary:
	return {"type": "hero_pick", "player": player, "index": index}


## Affecte un héros : post = "fleet" (flotte), "system" (système), "council" (siège), "agent" (empire
## où l'on a un réseau) ; "" = le rappeler.
static func hero_assign(player: int, hero_id: int, post: String, target: int) -> Dictionary:
	return {"type": "hero_assign", "player": player, "hero": hero_id, "post": post, "target": target}


## Renvoie un héros (il quitte l'empire).
static func hero_dismiss(player: int, hero_id: int) -> Dictionary:
	return {"type": "hero_dismiss", "player": player, "hero": hero_id}


## Un syndicat met un héros en location (on) ou l'en retire.
static func hero_for_hire(player: int, hero_id: int, on: bool) -> Dictionary:
	return {"type": "hero_for_hire", "player": player, "hero": hero_id, "on": on}


## Un empire engage un héros à louer.
static func hero_hire(player: int, hero_id: int) -> Dictionary:
	return {"type": "hero_hire", "player": player, "hero": hero_id}


## Le geôlier décide du sort d'un prisonnier : "free", "convert" ou "execute".
static func hero_prisoner(player: int, hero_id: int, action: String) -> Dictionary:
	return {"type": "hero_prisoner", "player": player, "hero": hero_id, "action": action}


static func spy_answer(player: int, case_id: int, choice: String) -> Dictionary:
	return {"type": "spy_answer", "player": player, "case": case_id, "choice": choice}


## Renvoie "" si l'ordre est applicable à cet état, sinon la raison du refus.
## Multijoueur : confie un empire à un humain (ai_level "") ou à l'IA (un niveau d'AiLevels), quand un
## joueur rejoint ou quitte la partie. Seul l'hôte l'émet (la session refuse celui d'un client) ;
## comme tout ordre, il passe dans le flux commun pour s'appliquer au même jour sur chaque machine.
static func seat(empire_id: int, ai_level: String) -> Dictionary:
	return {"type": "seat", "player": empire_id, "ai": ai_level}


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
		"fold":
			return Echoes.check_fold(state, int(cmd["player"]), int(cmd.get("planet", -1)), String(cmd.get("what", "")))
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
		"unite_lineages":
			return Victory.check_union(state, int(cmd["player"]), int(cmd.get("target", -1)))
		"mediate":
			return Diplomacy.check_mediate(state, int(cmd["player"]), int(cmd.get("a", -1)), int(cmd.get("b", -1)))
		"contract":
			return Diplomacy.check_propose_contract(state, int(cmd["player"]), int(cmd.get("merc", -1)), int(cmd.get("client", -1)), int(cmd.get("target", -1)))
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
		"spy_cells":
			return Espionage.check_cells(state, int(cmd["player"]), int(cmd.get("target", -1)), int(cmd.get("n", -1)))
		"spy_op":
			return Espionage.check_op(state, int(cmd["player"]), int(cmd.get("target", -1)), String(cmd.get("op", "")))
		"spy_cancel":
			return Espionage.check_cancel(state, int(cmd["player"]), int(cmd.get("target", -1)))
		"hero_pick":
			return Heroes.check_pick(state, int(cmd["player"]), int(cmd.get("index", -2)))
		"hero_assign":
			return Heroes.check_assign(state, int(cmd["player"]), int(cmd.get("hero", -1)), String(cmd.get("post", "?")), int(cmd.get("target", -1)))
		"hero_dismiss":
			return Heroes.check_dismiss(state, int(cmd["player"]), int(cmd.get("hero", -1)))
		"hero_for_hire":
			return Heroes.check_for_hire(state, int(cmd["player"]), int(cmd.get("hero", -1)), bool(cmd.get("on", false)))
		"hero_hire":
			return Heroes.check_hire(state, int(cmd["player"]), int(cmd.get("hero", -1)))
		"hero_prisoner":
			return Heroes.check_prisoner(state, int(cmd["player"]), int(cmd.get("hero", -1)), String(cmd.get("action", "")))
		"spy_answer":
			return Espionage.check_answer(state, int(cmd["player"]), int(cmd.get("case", -1)), String(cmd.get("choice", "")))
		"probe":
			return Espionage.check_probe(state, int(cmd["player"]), int(cmd.get("system", -1)))
		"seat":
			if state.get_empire(int(cmd["player"])) == null:
				return "empire inconnu"
			var lv := String(cmd.get("ai", ""))
			if lv != "" and not AiLevels.is_valid(lv):
				return "niveau d'IA inconnu : %s" % lv
			return ""
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
				state.add_chronicle("Les cartographes rebaptisent %s : on dira désormais %s." % [old_name, sys.system_name], Espionage.private_to(state, [int(cmd["player"])]))
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
			Heroes.on_merge(state, f.id, into.id)
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
					state.galaxy.get_planet(c.planet_id).display_name(state.galaxy)], Espionage.private_to(state, [e.id], state.galaxy.get_planet(c.planet_id).system_id))
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
		"fold":
			Echoes.fold(state, int(cmd["player"]), int(cmd["planet"]), String(cmd["what"]))
		"spy_cells":
			Espionage.set_cells(state, int(cmd["player"]), int(cmd["target"]), int(cmd["n"]))
		"spy_op":
			Espionage.launch(state, int(cmd["player"]), int(cmd["target"]), String(cmd["op"]))
		"spy_cancel":
			Espionage.cancel(state, int(cmd["player"]), int(cmd["target"]))
		"hero_pick":
			Heroes.pick(state, int(cmd["player"]), int(cmd["index"]))
		"hero_assign":
			Heroes.assign(state, int(cmd["player"]), int(cmd["hero"]), String(cmd["post"]), int(cmd["target"]))
		"hero_dismiss":
			Heroes.dismiss(state, int(cmd["player"]), int(cmd["hero"]))
		"hero_for_hire":
			Heroes.set_for_hire(state, int(cmd["player"]), int(cmd["hero"]), bool(cmd["on"]))
		"hero_hire":
			Heroes.hire(state, int(cmd["player"]), int(cmd["hero"]))
		"hero_prisoner":
			Heroes.prisoner(state, int(cmd["player"]), int(cmd["hero"]), String(cmd["action"]))
		"spy_answer":
			Espionage.answer(state, int(cmd["player"]), int(cmd["case"]), String(cmd["choice"]))
		"probe":
			Espionage.probe(state, int(cmd["player"]), int(cmd["system"]))
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
		"unite_lineages":
			Victory.union(state, int(cmd["player"]), int(cmd["target"]))
		"mediate":
			Diplomacy.mediate(state, int(cmd["player"]), int(cmd["a"]), int(cmd["b"]))
		"contract":
			Diplomacy.propose_contract(state, int(cmd["player"]), int(cmd["merc"]), int(cmd["client"]), int(cmd["target"]))
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
		"seat":
			var e := state.get_empire(int(cmd["player"]))
			e.ai_level = String(cmd["ai"])
			if e.ai_level != "" and not AiLevels.is_valid_temperament(e.ai_temperament):
				e.ai_temperament = AiLevels.default_temperament()
