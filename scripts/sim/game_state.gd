class_name GameState
extends RefCounted
## Tout l'état d'une partie, et rien d'autre : c'est ce qu'on sauvegarde,
## ce qu'on compare entre machines en multijoueur, et la seule chose que la simulation modifie.
##
## La partie statique de la galaxie (positions, routes, types d'étoiles) n'entre pas dans to_dict()
## ni dans l'empreinte : elle ne change pas en cours de partie. to_snapshot() l'ajoute, pour les
## sauvegardes et le multijoueur : la régénérer depuis la graine sur une autre machine pourrait
## donner une autre galaxie (sinus et cosinus calculés différemment selon le système).

const FORMAT_VERSION := 15
## Versions plus anciennes encore lues (la 9 n'a pas encore de modèles de vaisseaux, la 10 pas de
## victoires : une ancienne partie se charge sans date limite, victoires de peuple en jeu ; la 11 pas
## de peuples créés ; avant la 14, conquête et domination toujours en jeu, alliés qui gagnent ensemble,
## bonus d'IA fixes ; avant la 15, galaxie toujours régénérée depuis la graine).
const READABLE_VERSIONS := [9, 10, 11, 12, 13, 14, 15]
## Compléments de nom des empires qui partagent un peuple.
const ROMAN := ["", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII"]
const CHRONICLE_MAX := 50

## Message de la dernière erreur de from_dict(), pour l'affichage.
static var last_error := ""

var seed_value: int = 0
var system_count: int = 150
var galaxy_radius: float = 1800.0
## Réglages de génération de la galaxie (GalaxySettings) : forme, routes, placement des départs…
var galaxy_settings: Dictionary = GalaxySettings.defaults()
## Planètes déjà changées pour un empire voisin par les mondes garantis (création seulement).
var _guaranteed := {}
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
## Modèles de vaisseaux conçus en partie (voir Designs), par identifiant ("m<empire>_<n>").
var designs: Dictionary = {}
var next_design_id: int = 0
## Victoires (voir Victory) : règles choisies au lancement {"deadline": jours (0 = sans date limite),
## "people": victoires de peuple en jeu, "conquete" / "domination": ces victoires en jeu, "allies": les
## alliés avancent et gagnent ensemble}, et vainqueur proclamé {"empire", "victory", "tick", "allies":
## alliés qui partagent la victoire} ({} = aucun).
var victory_rules: Dictionary = default_victory_rules()
## Difficulté progressive : les bonus des IA Expert et Légende montent avec le temps (AiLevels).
var ai_scaling := false
var winner: Dictionary = {}
## Peuples créés dans l'éditeur qui jouent dans cette partie : identifiant -> fiche complète
## (Species.build), recopiée au lancement et sauvegardée, pour que la partie ne dépende pas des
## fichiers de la bibliothèque (modifiés ou supprimés depuis).
var custom_factions: Dictionary = {}

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
## - "spectator" : aucun joueur humain, l'empire 0 est lui aussi une IA (mode spectateur) ;
## - "deadline" : date limite en jours pour la victoire au score (0 = aucune, défaut data/victories.json) ;
## - "people_victories" : victoires de peuple en jeu (défaut oui) ;
## - "victories" : {"conquete", "domination", "allies"} à false pour retirer ces victoires ou faire
##   jouer chaque allié pour lui-même (défaut : tout en jeu, comme Endless Space 2) ;
## - "ai_scaling" : difficulté progressive (défaut non) ;
## - "starts" : départ par indice d'empire ("" = normal, "avance" = une avance de colonies et de
##   vaisseaux, voir rules.json "advanced_start") ;
## - "distances" : distance de chaque empire à l'empire 0 ("" = selon le placement, "proche" ou
##   "lointain" : il reçoit l'un des départs tirés les plus proches ou les plus lointains du vôtre ;
##   "hasard" : l'un des trois, tiré avec la graine) ;
## - "rivals" : peuples des autres empires (officiels ou créés), dans l'ordre ; défaut : les peuples
##   officiels autres que celui du joueur ;
## - "duplicates" : plusieurs empires peuvent partager un peuple (défaut non : les doublons sont ignorés) ;
## - "colors" : couleur de chaque empire (codes html, par indice d'empire ; "" = automatique). En
##   automatique, un empire prend la couleur de son peuple, ou la première couleur libre de
##   Empire.PALETTE si elle est déjà prise ;
## - "galaxy" : réglages de la galaxie (GalaxySettings) ; ils fixent alors aussi le nombre de systèmes
##   et le rayon, à la place de system_count_ et galaxy_radius_.
static func create(seed_value_: int, system_count_: int = 150, galaxy_radius_: float = 1800.0, player_faction := "", options := {}) -> GameState:
	var settings := GalaxySettings.normalize(options.get("galaxy", {}))
	if options.has("galaxy"):
		system_count_ = GalaxySettings.system_count(settings)
		galaxy_radius_ = GalaxySettings.radius(settings)
	var s := _base(seed_value_, system_count_, galaxy_radius_, settings)
	s.victory_rules = default_victory_rules()
	s.victory_rules["deadline"] = maxi(0, int(options.get("deadline", Victory.default_deadline())))
	s.victory_rules["people"] = bool(options.get("people_victories", true))
	var vic: Dictionary = options.get("victories", {})
	for k in ["conquete", "domination", "allies"]:
		s.victory_rules[k] = bool(vic.get(k, true))
	s.ai_scaling = bool(options.get("ai_scaling", false))
	s._setup_empires(player_faction, options.get("rivals", null), bool(options.get("duplicates", false)), options.get("distances", []))
	s._setup_colors(options.get("colors", []))
	s._setup_ai(options)
	s._setup_advanced_starts(options.get("starts", []))
	FleetSystem.update_exploration(s)
	return s


static func default_victory_rules() -> Dictionary:
	return {"deadline": 0, "people": true, "conquete": true, "domination": true, "allies": true}


## Galaxie et générateur seulement, sans empires (base commune à create() et from_dict()).
## galaxy_data : galaxie écrite par Galaxy.to_dict() ; vide = régénérée depuis la graine.
static func _base(seed_value_: int, system_count_: int, galaxy_radius_: float, settings := {}, galaxy_data := {}) -> GameState:
	var s := GameState.new()
	s.seed_value = seed_value_
	s.system_count = system_count_
	s.galaxy_radius = galaxy_radius_
	s.galaxy_settings = GalaxySettings.normalize(settings)
	if galaxy_data.is_empty():
		s.galaxy = GalaxyGenerator.generate(seed_value_, system_count_, galaxy_radius_, GalaxySettings.generator_shape(s.galaxy_settings))
	else:
		s.galaxy = Galaxy.from_dict(galaxy_data)
	# Flux aléatoire distinct de celui de la génération, dérivé de la même graine.
	s.rng.seed = hash([seed_value_, "simulation"])
	# Une nouvelle partie (ou un chargement) repart sans les modèles de la précédente.
	GameData.clear_custom_ships()
	GameData.clear_game_factions()
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
		"galaxy_settings": galaxy_settings.duplicate(),
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
		"designs": _sorted_designs(),
		"next_design_id": next_design_id,
		"victory_rules": victory_rules.duplicate(),
		"ai_scaling": ai_scaling,
		"winner": winner.duplicate(),
		"custom_factions": _sorted_values(custom_factions),
	}


## État complet avec la galaxie elle-même (positions, routes, planètes) : ce qu'on sauvegarde et ce
## que l'hôte envoie aux joueurs. Se relit avec from_dict(), sans rien régénérer.
func to_snapshot() -> Dictionary:
	var d := to_dict()
	d["galaxy"] = galaxy.to_dict()
	return d


func _sorted_designs() -> Array:
	var ids := designs.keys()
	ids.sort()
	var out := []
	for k in ids:
		out.append(designs[k].duplicate(true))
	return out


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
	if not READABLE_VERSIONS.has(int(d["version"])):
		last_error = "version de format %s non prise en charge (attendu %d)" % [d["version"], FORMAT_VERSION]
		return null
	var galaxy_data: Variant = d.get("galaxy", {})
	if not galaxy_data is Dictionary:
		last_error = "galaxie illisible"
		return null
	var s := GameState._base(int(d["seed"]), int(d["system_count"]), float(d["galaxy_radius"]), d.get("galaxy_settings", {}), galaxy_data)
	if s.galaxy == null:
		last_error = "galaxie incohérente"
		return null
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
	# Peuples créés avant les empires : leur fiche vient de la sauvegarde, pas de la bibliothèque.
	for cf: Dictionary in d.get("custom_factions", []):
		var fd: Dictionary = GameData._to_ints(cf)
		if not Species.is_valid_id(String(fd.get("id", ""))) or not fd.has("species"):
			last_error = "peuple créé invalide : %s" % fd.get("id", "?")
			return null
		s.custom_factions[String(fd["id"])] = fd
	GameData.set_game_factions(s.custom_factions)
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
	# Les modèles avant les flottes : leurs vaisseaux doivent être reconnus.
	for rd: Dictionary in d.get("designs", []):
		var rec: Dictionary = GameData._to_ints(rd)
		if Designs.hull(String(rec.get("hull", ""))).is_empty() or s.get_empire(int(rec.get("owner", -1))) == null:
			last_error = "modèle de vaisseau invalide : %s" % rec.get("id", "?")
			return null
		s.designs[String(rec["id"])] = rec
	s.next_design_id = int(d.get("next_design_id", 0))
	Designs.register_all(s)
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
	var vr: Dictionary = d.get("victory_rules", {})
	s.victory_rules = default_victory_rules()
	s.victory_rules["deadline"] = int(vr.get("deadline", 0))
	for k in ["people", "conquete", "domination", "allies"]:
		s.victory_rules[k] = bool(vr.get(k, true))
	s.ai_scaling = bool(d.get("ai_scaling", false))
	var w: Dictionary = d.get("winner", {})
	if not w.is_empty():
		var allies := []
		for a in w.get("allies", []):
			allies.append(int(a))
		s.winner = {"empire": int(w["empire"]), "victory": String(w["victory"]), "tick": int(w["tick"]), "allies": allies}
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
	f.add_ship(ship_id, -1, Research.mark_gen(self, owner_id))
	f.troops = Combat.max_troops(f, self)
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
		# Avance de départ des niveaux hauts (affichée dans la description du niveau). En difficulté
		# progressive, les bonus partent de zéro : pas d'avance au départ.
		var bonus: Dictionary = {} if ai_scaling else AiLevels.level(lv).get("start_bonus", {})
		for r in bonus:
			e.resources[r] = int(e.resources.get(r, 0)) + int(bonus[r])


## Aucun empire n'est joué par un humain : la partie se regarde (mode spectateur).
func is_spectator_game() -> bool:
	for e in empires:
		if not e.is_ai():
			return false
	return not empires.is_empty()


func _setup_empires(player_faction: String, rivals: Variant = null, duplicates := false, distances: Array = []) -> void:
	var order: Array[String] = []
	if player_faction != "" and not GameData.faction(player_faction).is_empty():
		order.append(player_faction)
	var others: Array = rivals if rivals is Array else GameData.faction_ids()
	for fid in others:
		if (duplicates or not order.has(String(fid))) and not GameData.faction(String(fid)).is_empty():
			order.append(String(fid))
	# Les peuples créés sont recopiés dans la partie (et dans sa sauvegarde).
	for fid in order:
		if not GameData.is_official(fid):
			custom_factions[fid] = GameData.faction(fid).duplicate(true)
	GameData.set_game_factions(custom_factions)
	var homes := _assign_distances(_pick_home_systems(order.size()), distances)
	var rules := GameData.rules()
	var hw: Dictionary = rules["homeworld"]
	for i in mini(order.size(), homes.size()):
		var e := Empire.new()
		e.id = i
		e.faction_id = order[i]
		# Deuxième, troisième… empire du même peuple : « Lignées d'Ossarane II ».
		var rank := order.slice(0, i).count(order[i])
		if rank > 0:
			e.name_suffix = ROMAN[mini(rank, ROMAN.size() - 1)]
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
		_guarantee_worlds(e, sys.id, homes)
		var c := Colony.new()
		c.planet_id = home_id
		c.owner = e.id
		c.kind = Colony.KIND_COLONY
		c.population = int(hw["pop"])
		for b in hw["buildings"]:
			c.buildings.append(String(b))
		colonies[home_id] = c
		e.capital_planet = home_id
		e.home_planet = home_id
		# Flotte de départ : de quoi explorer et fonder une première colonie.
		for ship_id in FactionTraits.start_ships(e.faction_id):
			spawn_ship(e.id, String(ship_id), sys.id)
	rebuild_ownership()


## Systèmes d'origine : le premier au hasard (via state.rng), puis chaque suivant le plus loin
## possible des précédents. Seulement des étoiles calmes avec au moins deux planètes.
## Couleurs des empires : celle demandée, sinon celle du peuple, sinon la première libre de la palette.
func _setup_colors(wanted: Array) -> void:
	var used: Array[Color] = []
	# D'abord les couleurs demandées explicitement, pour que l'automatique les évite.
	for e in empires:
		var hex := String(wanted[e.id]) if e.id < wanted.size() else ""
		if hex != "" and Color.html_is_valid(hex):
			e.color_hex = hex
			used.append(Color.html(hex))
	for e in empires:
		if e.color_hex != "":
			continue
		var own := e.color()
		if not Empire.color_taken(own, used):
			used.append(own)
			continue
		for hex in Empire.PALETTE:
			if not Empire.color_taken(Color.html(hex), used):
				e.color_hex = hex
				break
		used.append(e.color())


## Mondes habitables garantis (réglage de la galaxie) : à deux sauts au plus du départ, au moins N
## planètes d'un type préféré du peuple ; il en manque, des planètes rocheuses proches sont changées.
func _guarantee_worlds(e: Empire, home_sys: int, homes: Array[int]) -> void:
	var want := int(galaxy_settings.get("guaranteed", 0))
	var preferred: Array = e.faction().get("preferred", [])
	if want <= 0 or preferred.is_empty():
		return
	var near: Array[int] = []
	var frontier: Array[int] = [home_sys]
	var seen := {home_sys: true}
	for _hop in 2:
		var next: Array[int] = []
		for sid in frontier:
			for nb in galaxy.systems[sid].neighbors:
				if not seen.has(nb):
					seen[nb] = true
					next.append(nb)
					if not homes.has(nb):
						near.append(nb)
		frontier = next
	var have := 0
	var spare: Array[int] = []
	for sid in near:
		for pid in galaxy.systems[sid].planet_ids:
			var p := galaxy.planets[pid]
			if preferred.has(p.type):
				have += 1
			elif p.type != "gas_giant" and p.type != "asteroids" and not _guaranteed.has(pid):
				spare.append(pid)
	var types := GameData.planet_types()
	for k in mini(want - have, spare.size()):
		var t := String(preferred[k % preferred.size()])
		var sizes: Array = types[t]["sizes"]
		override_planet(spare[k], {"type": t, "size": int(round((float(sizes[0]) + float(sizes[1])) * 0.5))})
		_guaranteed[spare[k]] = true


## Distance au joueur choisie par rival : les départs tirés ne changent pas, seule leur attribution.
## Les « proche » prennent, dans l'ordre, les départs les plus proches de celui de l'empire 0, les
## « lointain » les plus éloignés ; les autres gardent l'ordre du placement.
func _assign_distances(homes: Array[int], distances: Array) -> Array[int]:
	var wants := false
	distances = distances.duplicate()
	for i in range(1, mini(homes.size(), distances.size())):
		# « Au hasard » : proche, selon le placement ou lointain, tiré avec la graine.
		if String(distances[i]) == "hasard":
			distances[i] = ["proche", "", "lointain"][rng.randi_range(0, 2)]
		wants = wants or String(distances[i]) in ["proche", "lointain"]
	if not wants:
		return homes
	var origin := galaxy.systems[homes[0]].position
	var by_dist: Array[int] = homes.slice(1)
	by_dist.sort_custom(func(a: int, b: int) -> bool:
		var da := galaxy.systems[a].position.distance_squared_to(origin)
		var db := galaxy.systems[b].position.distance_squared_to(origin)
		return da < db or (da == db and a < b))
	var out: Array[int] = []
	out.resize(homes.size())
	out.fill(-1)
	out[0] = homes[0]
	var taken := {}
	for want in ["proche", "lointain"]:
		for i in range(1, homes.size()):
			if i < distances.size() and String(distances[i]) == want:
				var pick: int = by_dist.pop_front() if want == "proche" else by_dist.pop_back()
				out[i] = pick
				taken[pick] = true
	var rest: Array[int] = []
	for h in homes.slice(1):
		if not taken.has(h):
			rest.append(h)
	for i in range(1, homes.size()):
		if out[i] < 0:
			out[i] = rest.pop_front()
	return out


## Départ avancé (par empire) : des colonies fondées autour du monde d'origine, la flotte de départ en
## double et des ressources (data/rules.json "advanced_start"), comme les départs « avancés » de
## Stellaris et Distant Worlds 2.
func _setup_advanced_starts(starts: Array) -> void:
	var adv: Dictionary = GameData.rules().get("advanced_start", {})
	var homes := {}
	for e in empires:
		homes[galaxy.get_planet(e.home_planet).system_id] = true
	for e in empires:
		if e.id >= starts.size() or String(starts[e.id]) != "avance":
			continue
		e.advanced_start = true
		var home_sys := galaxy.get_planet(e.home_planet).system_id
		var near: Array[int] = [home_sys]
		near.append_array(galaxy.systems[home_sys].neighbors)
		var spots: Array[int] = []
		for sid in near:
			if sid != home_sys and homes.has(sid):
				continue
			for pid in galaxy.systems[sid].planet_ids:
				if not colonies.has(pid) and Economy.habitability(galaxy.planets[pid].type, e.faction()) > 0:
					spots.append(pid)
		spots.sort_custom(func(a: int, b: int) -> bool:
			var ha := Economy.habitability(galaxy.planets[a].type, e.faction()) * 10 + galaxy.planets[a].size
			var hb := Economy.habitability(galaxy.planets[b].type, e.faction()) * 10 + galaxy.planets[b].size
			return ha > hb or (ha == hb and a < b))
		for k in mini(int(adv.get("colonies", 2)), spots.size()):
			var c := Colony.new()
			c.planet_id = spots[k]
			c.owner = e.id
			c.kind = Colony.KIND_COLONY
			c.population = int(adv.get("pop", 3))
			colonies[spots[k]] = c
		var res: Dictionary = adv.get("resources", {})
		for r in res:
			e.resources[r] = int(e.resources.get(r, 0)) + int(res[r])
		for ship_id in FactionTraits.start_ships(e.faction_id):
			spawn_ship(e.id, String(ship_id), home_sys)
	rebuild_ownership()


func _pick_home_systems(count: int) -> Array[int]:
	match String(galaxy_settings.get("placement", "standard")):
		"equilibre":
			return _pick_homes_balanced(count)
		"chaotique":
			return _pick_homes_chaotic(count)
	return _pick_homes_spread(count)


## Départs équilibrés : un secteur angulaire par empire ; dans chacun, le système d'au moins trois
## planètes le plus proche de l'anneau à mi-chemin du centre et du bord.
func _pick_homes_balanced(count: int) -> Array[int]:
	var candidates: Array[int] = []
	for s in galaxy.systems:
		var r := s.position.length() / galaxy_radius
		if s.planet_count >= 3 and s.star_type != "neutron" and s.star_type != "black_hole" and r > 0.3 and r < 0.92:
			candidates.append(s.id)
	if candidates.size() < count:
		return _pick_homes_spread(count)
	var chosen: Array[int] = []
	var offset := rng.randf() * TAU
	var width := TAU / float(count)
	for k in count:
		var best := -1
		var best_score := INF
		for c in candidates:
			if chosen.has(c):
				continue
			var pos := galaxy.systems[c].position
			var a := fposmod(pos.angle() - offset, TAU)
			if a < k * width or a >= (k + 1) * width:
				continue
			var score := absf(pos.length() / galaxy_radius - 0.62)
			if score < best_score:
				best_score = score
				best = c
		if best < 0:
			# Secteur vide (amas, anneau étroit) : le candidat le plus loin des départs déjà pris.
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
		if best >= 0:
			chosen.append(best)
	return chosen


## Départs chaotiques : tirés au hasard parmi les systèmes habitables.
func _pick_homes_chaotic(count: int) -> Array[int]:
	var candidates: Array[int] = []
	for s in galaxy.systems:
		if s.planet_count >= 2 and s.star_type != "neutron" and s.star_type != "black_hole":
			candidates.append(s.id)
	if candidates.size() < count:
		return _pick_homes_spread(count)
	var chosen: Array[int] = []
	while chosen.size() < count:
		var c := candidates[rng.randi_range(0, candidates.size() - 1)]
		if not chosen.has(c):
			chosen.append(c)
	return chosen


## Départs standard : le plus loin possible les uns des autres (le placement d'origine).
func _pick_homes_spread(count: int) -> Array[int]:
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
