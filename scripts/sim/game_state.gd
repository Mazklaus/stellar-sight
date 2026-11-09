class_name GameState
extends RefCounted
## Tout l'état d'une partie, et rien d'autre : c'est ce qu'on sauvegarde,
## ce qu'on compare entre machines en multijoueur, et la seule chose que la simulation modifie.
##
## La partie statique de la galaxie (positions, routes, types d'étoiles) n'est pas
## stockée : elle se régénère à l'identique depuis la graine. Seules les données
## qui changent en cours de partie sont sérialisées.

const FORMAT_VERSION := 7
const CHRONICLE_MAX := 50

## Message de la dernière erreur de from_dict(), pour l'affichage.
static var last_error := ""

var seed_value: int = 0
var system_count: int = 150
var galaxy_radius: float = 1800.0
## Jour de jeu courant (un tick = un jour).
var tick: int = 0
## Générateur aléatoire de la simulation. Toute décision aléatoire en cours de partie
## doit passer par lui (jamais randi() ou randf() globaux), sinon le déterminisme casse.
var rng := RandomNumberGenerator.new()
var galaxy: Galaxy
## Chronique galactique : derniers événements, du plus ancien au plus récent.
## Chaque entrée : {"tick": int, "text": String}.
var chronicle: Array[Dictionary] = []
## Empires en jeu ; l'identifiant d'un empire est aussi celui de son joueur dans les ordres.
var empires: Array[Empire] = []
## Revendications (colonies et avant-postes), par identifiant de planète.
var colonies: Dictionary = {}
## Modifications des planètes générées (monde d'origine…) : identifiant -> {"type", "size", "deposits"}.
var planet_overrides: Dictionary = {}
## Flottes en jeu, par identifiant.
var fleets: Dictionary = {}
## Identifiant de la prochaine flotte créée (jamais réutilisé).
var next_fleet_id: int = 0
## Garnisons entamées par un siège : identifiant de système -> garnison actuelle
## (absent = garnison pleine, voir Combat.garrison).
var garrisons: Dictionary = {}
## Sièges en cours : identifiant de système -> {"by": empire assiégeant, "start": tick}.
var sieges: Dictionary = {}
## Batailles en cours : identifiant de système -> bataille (voir CombatSystem).
var battles: Dictionary = {}
## Derniers rapports de bataille, du plus ancien au plus récent.
var battle_reports: Array[Dictionary] = []
var next_battle_id: int = 0
## Diplomatie (voir Diplomacy) : relations par paire d'empires ("a-b", a < b) -> {"pact", "since",
## "truce", "trade", "trust", "score", "cool"} ; souvenirs (griefs et gestes) qui s'effacent avec le
## temps ; propositions de traité en attente d'une réponse humaine.
var relations: Dictionary = {}
var memories: Array[Dictionary] = []
var proposals: Array[Dictionary] = []
var next_proposal_id: int = 0

## Systèmes vus par chaque empire au dernier passage de l'exploration (FleetSystem), et le tick
## correspondant : donnée dérivée, non sauvegardée, qui évite à l'IA de refaire le calcul.
var seen_cache: Array[Dictionary] = []
var seen_tick: int = -1
## Propriétaire de chaque système revendiqué (donnée dérivée des colonies, non sauvegardée).
var _system_owner: Dictionary = {}


## Nouvelle partie : galaxie, puis les empires de la première version placés dans leurs systèmes d'origine.
## player_faction devient l'empire 0 (le joueur local) ; les autres suivent dans l'ordre des données.
## options :
## - "ai_level" : niveau des empires IA (AiLevels, défaut celui de data/ai.json ; "" = aucune IA,
##   les autres empires restent inertes, ce dont se servent les tests de règles) ;
## - "ai_levels" : niveaux empire par empire (tableau, prioritaire sur "ai_level") ;
## - "temperament" / "temperaments" : tempérament des IA (AiLevels.temperament), global ou empire par empire ;
## - "spectator" : aucun joueur humain, l'empire 0 est lui aussi une IA (mode spectateur).
static func create(seed_value_: int, system_count_: int = 150, galaxy_radius_: float = 1800.0, player_faction := "", options := {}) -> GameState:
	var s := _base(seed_value_, system_count_, galaxy_radius_)
	s._setup_empires(player_faction)
	s._setup_ai(options)
	FleetSystem.update_exploration(s)
	return s


## Galaxie et générateur seulement, sans empires (base commune à create() et from_dict()).
static func _base(seed_value_: int, system_count_: int, galaxy_radius_: float) -> GameState:
	var s := GameState.new()
	s.seed_value = seed_value_
	s.system_count = system_count_
	s.galaxy_radius = galaxy_radius_
	s.galaxy = GalaxyGenerator.generate(seed_value_, system_count_, galaxy_radius_)
	# Flux aléatoire distinct de celui de la génération, dérivé de la même graine.
	s.rng.seed = hash([seed_value_, "simulation"])
	return s


func to_dict() -> Dictionary:
	var systems := []
	for sys in galaxy.systems:
		systems.append({"name": sys.system_name})
	var empire_list := []
	for e in empires:
		empire_list.append(e.to_dict())
	var colony_list := []
	for pid in sorted_colony_ids():
		colony_list.append(colonies[pid].to_dict())
	var override_list := []
	var override_ids := planet_overrides.keys()
	override_ids.sort()
	for pid in override_ids:
		var o: Dictionary = planet_overrides[pid].duplicate(true)
		o["planet"] = pid
		override_list.append(o)
	var fleet_list := []
	for fid in sorted_fleet_ids():
		fleet_list.append(fleets[fid].to_dict())
	return {
		"version": FORMAT_VERSION,
		"seed": seed_value,
		"system_count": system_count,
		"galaxy_radius": galaxy_radius,
		"tick": tick,
		# L'état du générateur tient sur 64 bits : en texte pour survivre au JSON
		# (dont les nombres sont des flottants, précis seulement jusqu'à 2^53).
		"rng_state": str(rng.state),
		"systems": systems,
		"chronicle": chronicle.duplicate(true),
		"empires": empire_list,
		"colonies": colony_list,
		"planet_overrides": override_list,
		"fleets": fleet_list,
		"next_fleet_id": next_fleet_id,
		"garrisons": _int_map_to_list(garrisons, "garrison"),
		"sieges": _sorted_values(sieges),
		"battles": _sorted_values(battles),
		"battle_reports": battle_reports.duplicate(true),
		"next_battle_id": next_battle_id,
		"relations": _sorted_values(relations),
		"memories": memories.duplicate(true),
		"proposals": proposals.duplicate(true),
		"next_proposal_id": next_proposal_id,
	}


## Dictionnaire id -> entier, en liste triée [{"system": id, key: valeur}] (le JSON n'a pas de clés entières).
static func _int_map_to_list(d: Dictionary, key: String) -> Array:
	var ids := d.keys()
	ids.sort()
	var out := []
	for k in ids:
		out.append({"system": k, key: d[k]})
	return out


## Valeurs d'un dictionnaire id -> dictionnaire, triées par identifiant (elles portent leur "system").
static func _sorted_values(d: Dictionary) -> Array:
	var ids := d.keys()
	ids.sort()
	var out := []
	for k in ids:
		out.append(d[k].duplicate(true))
	return out


## Reconstruit un état à partir de to_dict(). Renvoie null si les données sont invalides
## (le détail est dans GameState.last_error).
static func from_dict(d: Dictionary) -> GameState:
	last_error = ""
	for key in ["version", "seed", "system_count", "galaxy_radius", "tick", "rng_state", "systems", "chronicle", "empires", "colonies", "planet_overrides", "fleets", "next_fleet_id"]:
		if not d.has(key):
			last_error = "champ manquant : %s" % key
			return null
	if int(d["version"]) != FORMAT_VERSION:
		last_error = "version de format %s non prise en charge (attendu %d)" % [d["version"], FORMAT_VERSION]
		return null
	var s := GameState._base(int(d["seed"]), int(d["system_count"]), float(d["galaxy_radius"]))
	var systems: Array = d["systems"]
	if systems.size() != s.galaxy.systems.size():
		last_error = "nombre de systèmes incohérent (%d au lieu de %d)" % [systems.size(), s.galaxy.systems.size()]
		return null
	for i in systems.size():
		var entry: Dictionary = systems[i]
		s.galaxy.systems[i].system_name = String(entry.get("name", s.galaxy.systems[i].system_name))
	s.tick = int(d["tick"])
	s.rng.state = String(d["rng_state"]).to_int()
	for e: Dictionary in d["chronicle"]:
		s.chronicle.append({"tick": int(e["tick"]), "text": String(e["text"])})
	for o: Dictionary in d["planet_overrides"]:
		var fields := o.duplicate(true)
		fields.erase("planet")
		if s.galaxy.get_planet(int(o["planet"])) == null:
			last_error = "planète inconnue dans les modifications : %s" % o["planet"]
			return null
		s.override_planet(int(o["planet"]), fields)
	for e: Dictionary in d["empires"]:
		if GameData.faction(String(e["faction"])).is_empty():
			last_error = "faction inconnue : %s" % e["faction"]
			return null
		if String(e.get("ai", "")) != "" and not AiLevels.is_valid(String(e["ai"])):
			last_error = "niveau d'IA inconnu : %s" % e["ai"]
			return null
		if String(e.get("temper", "")) != "" and not AiLevels.is_valid_temperament(String(e["temper"])):
			last_error = "tempérament d'IA inconnu : %s" % e["temper"]
			return null
		s.empires.append(Empire.from_dict(e))
	for c: Dictionary in d["colonies"]:
		var colony := Colony.from_dict(c)
		if s.galaxy.get_planet(colony.planet_id) == null or s.get_empire(colony.owner) == null:
			last_error = "colonie invalide sur la planète %d" % colony.planet_id
			return null
		s.colonies[colony.planet_id] = colony
	for fd: Dictionary in d["fleets"]:
		var f := Fleet.from_dict(fd)
		var bad := s.get_empire(f.owner) == null or s.galaxy.get_system(f.system_id) == null or f.ships.is_empty()
		for sid in f.path:
			if s.galaxy.get_system(sid) == null:
				bad = true
		for ship in f.ships:
			if GameData.ship(ship).is_empty():
				bad = true
		if bad:
			last_error = "flotte invalide : %d" % f.id
			return null
		s.fleets[f.id] = f
	s.next_fleet_id = int(d["next_fleet_id"])
	for g: Dictionary in d.get("garrisons", []):
		s.garrisons[int(g["system"])] = int(g["garrison"])
	for sg: Dictionary in d.get("sieges", []):
		var v: Dictionary = GameData._to_ints(sg)
		s.sieges[int(v["system"])] = v
	for b: Dictionary in d.get("battles", []):
		var v: Dictionary = GameData._to_ints(b)
		s.battles[int(v["system"])] = v
	for r: Dictionary in d.get("battle_reports", []):
		s.battle_reports.append(GameData._to_ints(r))
	s.next_battle_id = int(d.get("next_battle_id", 0))
	for r: Dictionary in d.get("relations", []):
		var v: Dictionary = GameData._to_ints(r)
		s.relations[String(v["key"])] = v
	for m: Dictionary in d.get("memories", []):
		s.memories.append(GameData._to_ints(m))
	for p: Dictionary in d.get("proposals", []):
		s.proposals.append(GameData._to_ints(p))
	s.next_proposal_id = int(d.get("next_proposal_id", 0))
	s.rebuild_ownership()
	return s


## Empreinte de l'état complet. Deux machines qui ont la même empreinte au même tick
## sont synchronisées ; une différence signale une désynchronisation (ou une sauvegarde abîmée).
func checksum() -> String:
	return JSON.stringify(to_dict(), "", true, true).sha256_text()


func add_chronicle(text: String) -> Dictionary:
	var entry := {"tick": tick, "text": text}
	chronicle.append(entry)
	while chronicle.size() > CHRONICLE_MAX:
		chronicle.pop_front()
	return entry


## Identifiants des flottes, triés (même raison que sorted_colony_ids).
func sorted_fleet_ids() -> Array:
	var ids := fleets.keys()
	ids.sort()
	return ids


## Crée une flotte d'un vaisseau dans un système. Son nom suit la classe : « Éclaireur 3 ».
func spawn_ship(owner_id: int, ship_id: String, system_id: int) -> Fleet:
	var e := get_empire(owner_id)
	var n := int(e.ships_built.get(ship_id, 0)) + 1
	e.ships_built[ship_id] = n
	var f := Fleet.new()
	f.id = next_fleet_id
	next_fleet_id += 1
	f.owner = owner_id
	f.fleet_name = "%s %d" % [GameData.ship(ship_id).get("label", ship_id), n]
	f.add_ship(ship_id)
	f.troops = Combat.max_troops(f)
	f.system_id = system_id
	fleets[f.id] = f
	return f


func get_empire(id: int) -> Empire:
	if id < 0 or id >= empires.size():
		return null
	return empires[id]


## Identifiants des planètes revendiquées, triés : tout parcours qui modifie l'état passe par là,
## pour que l'ordre de traitement soit le même sur toutes les machines.
func sorted_colony_ids() -> Array:
	var ids := colonies.keys()
	ids.sort()
	return ids


## Propriétaire d'un système (-1 si personne). Une colonisation en cours compte déjà.
func system_owner(system_id: int) -> int:
	return int(_system_owner.get(system_id, -1))


func rebuild_ownership() -> void:
	_system_owner.clear()
	for pid in sorted_colony_ids():
		var sys_id := galaxy.get_planet(pid).system_id
		if not _system_owner.has(sys_id):
			_system_owner[sys_id] = colonies[pid].owner


func add_colony(colony: Colony) -> void:
	colonies[colony.planet_id] = colony
	rebuild_ownership()


## Modifie une planète générée et retient la modification (elle sera sauvegardée).
func override_planet(planet_id: int, fields: Dictionary) -> void:
	var p := galaxy.get_planet(planet_id)
	var o: Dictionary = planet_overrides.get(planet_id, {})
	if fields.has("type"):
		p.type = String(fields["type"])
		o["type"] = p.type
	if fields.has("size"):
		p.size = int(fields["size"])
		o["size"] = p.size
	if fields.has("deposits"):
		p.deposits.clear()
		for dep in fields["deposits"]:
			p.deposits.append(String(dep))
		o["deposits"] = Array(p.deposits)
	planet_overrides[planet_id] = o


func _setup_ai(options: Dictionary) -> void:
	var level := String(options.get("ai_level", AiLevels.default_id()))
	var per: Array = options.get("ai_levels", [])
	var temper := String(options.get("temperament", AiLevels.default_temperament()))
	var tempers: Array = options.get("temperaments", [])
	var spectator := bool(options.get("spectator", false))
	for e in empires:
		if e.id == 0 and not spectator:
			continue  # le joueur humain
		var lv := String(per[e.id]) if e.id < per.size() else level
		if lv == "":
			continue
		if not AiLevels.is_valid(lv):
			lv = AiLevels.default_id()
		e.ai_level = lv
		var tp := String(tempers[e.id]) if e.id < tempers.size() else temper
		e.ai_temperament = tp if AiLevels.is_valid_temperament(tp) else AiLevels.default_temperament()
		# Avance de départ des niveaux hauts (affichée dans la description du niveau).
		var bonus: Dictionary = AiLevels.level(lv).get("start_bonus", {})
		for r in bonus:
			e.resources[r] = int(e.resources.get(r, 0)) + int(bonus[r])


## Aucun empire n'est joué par un humain : la partie se regarde (mode spectateur).
func is_spectator_game() -> bool:
	for e in empires:
		if not e.is_ai():
			return false
	return not empires.is_empty()


func _setup_empires(player_faction: String) -> void:
	var order := GameData.faction_ids()
	if order.has(player_faction):
		order.erase(player_faction)
		order.push_front(player_faction)
	var homes := _pick_home_systems(order.size())
	var rules := GameData.rules()
	var hw: Dictionary = rules["homeworld"]
	for i in mini(order.size(), homes.size()):
		var e := Empire.new()
		e.id = i
		e.faction_id = order[i]
		for r in GameData.resource_ids():
			e.resources[r] = int(rules["start_resources"].get(r, 0))
		empires.append(e)
		var faction := e.faction()
		if FactionTraits.has_fervor(faction):
			e.fervor = int(faction["fervor"]["start"])
		if Diplomacy.has_ability_faction(faction, "heir"):
			e.heir_loyalty = int(Diplomacy.ability("heir")["start"])
		var sys := galaxy.systems[homes[i]]
		# Monde d'origine : la plus grande planète du système, transformée au goût de l'espèce.
		var home_id: int = sys.planet_ids[0]
		for pid in sys.planet_ids:
			if galaxy.planets[pid].size > galaxy.planets[home_id].size:
				home_id = pid
		override_planet(home_id, {"type": faction["preferred"][0], "size": hw["size"]})
		var dep := String(faction.get("home_deposit", ""))
		if dep != "":
			var target := home_id
			for pid in sys.planet_ids:
				if pid != home_id:
					target = pid
					break
			if not galaxy.planets[target].deposits.has(dep):
				var deps := Array(galaxy.planets[target].deposits)
				deps.append(dep)
				override_planet(target, {"deposits": deps})
		var c := Colony.new()
		c.planet_id = home_id
		c.owner = e.id
		c.kind = Colony.KIND_COLONY
		c.population = int(hw["pop"])
		for b in hw["buildings"]:
			c.buildings.append(String(b))
		colonies[home_id] = c
		e.capital_planet = home_id
		# Flotte de départ : de quoi explorer et fonder une première colonie.
		for ship_id in FactionTraits.start_ships(e.faction_id):
			spawn_ship(e.id, String(ship_id), sys.id)
	rebuild_ownership()


## Systèmes d'origine : le premier au hasard (via state.rng), puis chaque suivant le plus loin
## possible des précédents. Seulement des étoiles calmes avec au moins deux planètes.
func _pick_home_systems(count: int) -> Array[int]:
	var candidates: Array[int] = []
	for s in galaxy.systems:
		if s.planet_count >= 2 and s.star_type != "neutron" and s.star_type != "black_hole":
			candidates.append(s.id)
	if candidates.size() < count:
		candidates.clear()
		for s in galaxy.systems:
			if s.planet_count >= 1:
				candidates.append(s.id)
	var chosen: Array[int] = []
	if candidates.is_empty():
		return chosen
	chosen.append(candidates[rng.randi_range(0, candidates.size() - 1)])
	while chosen.size() < count and chosen.size() < candidates.size():
		var best := -1
		var best_d := -1.0
		for c in candidates:
			if chosen.has(c):
				continue
			var d := INF
			for h in chosen:
				d = minf(d, galaxy.systems[c].position.distance_squared_to(galaxy.systems[h].position))
			if d > best_d:
				best_d = d
				best = c
		chosen.append(best)
	return chosen
