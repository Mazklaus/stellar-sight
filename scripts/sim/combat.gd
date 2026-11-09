class_name Combat
extends RefCounted
## Règles du combat, de la guerre, du siège et de l'invasion : fonctions pures qui LISENT l'état
## (sauf start_war et capture_system, appelées par les ordres et par CombatSystem).
## L'interface et l'IA s'en servent pour afficher et décider avec exactement les mêmes calculs.
##
## Inspiration (voir data/combat.json, "_sources") : Endless Space 2 comme référence principale
## (bataille automatique, plan de bataille choisi avant, blocus puis siège qui use la garnison,
## invasion par les troupes embarquées), et les trois phases de portée du premier Endless Space.
## Tout en entiers, aucun aléatoire hors de state.rng.


static func data() -> Dictionary:
	return GameData.combat()


# --- Vaisseaux et flottes ----------------------------------------------------------------------

static func is_military(ship_id: String) -> bool:
	return bool(GameData.ship(ship_id).get("military", false))


static func weapons(ship_id: String) -> Dictionary:
	return GameData.ship(ship_id).get("weapons", {})


static func is_armed_ship(ship_id: String) -> bool:
	return not weapons(ship_id).is_empty()


## Une flotte armée peut combattre, bloquer et assiéger.
static func is_armed(f: Fleet) -> bool:
	for s in f.ships:
		if is_armed_ship(s):
			return true
	return false


## Flotte entièrement militaire (l'IA la mène à la guerre plutôt qu'en exploration).
static func is_warfleet(f: Fleet) -> bool:
	if f.ships.is_empty():
		return false
	for s in f.ships:
		if not is_military(s):
			return false
	return true


## Dégâts qu'un vaisseau inflige sur toute une bataille en Équilibre, sans défense en face.
static func ship_damage_profile(ship_id: String) -> int:
	var total := 0
	var phases: Array = data()["phases"]
	var w := weapons(ship_id)
	for k in w:
		var eff: Array = data()["weapons"][k]["eff"]
		for i in phases.size():
			@warning_ignore("integer_division")
			total += int(w[k]) * int(eff[i]) * int(phases[i]["days"]) / 100
	return total


## Puissance d'un vaisseau intact : ce qu'il inflige et ce qu'il encaisse, en une seule note.
static func ship_strength(ship_id: String) -> int:
	@warning_ignore("integer_division")
	return (ship_damage_profile(ship_id) + Fleet.max_hp_of(ship_id)) / 10


## Puissance d'une flotte, réduite par les dégâts subis.
static func fleet_power(f: Fleet) -> int:
	var p := 0
	for i in f.ships.size():
		var s := f.ships[i]
		@warning_ignore("integer_division")
		p += ship_strength(s) * f.hp[i] / Fleet.max_hp_of(s)
	return p


static func max_troops(f: Fleet) -> int:
	var n := 0
	for s in f.ships:
		n += int(GameData.ship(s).get("troops", 0))
	return n


static func siege_power(f: Fleet) -> int:
	var n := 0
	for s in f.ships:
		n += int(GameData.ship(s).get("siege", 0))
	return n


# --- Tactiques et phases -----------------------------------------------------------------------

static func tactic_ids() -> Array[String]:
	var out: Array[String] = []
	for t: Dictionary in data()["tactics"]:
		out.append(String(t["id"]))
	return out


static func default_tactic() -> String:
	return String(data().get("default_tactic", "equilibre"))


static func tactic(id: String) -> Dictionary:
	for t: Dictionary in data()["tactics"]:
		if t["id"] == id:
			return t
	return tactic(default_tactic()) if id != default_tactic() else {}


static func fleet_tactic(f: Fleet) -> String:
	return f.tactic if tactic_ids().has(f.tactic) else default_tactic()


static func tactic_label(id: String) -> String:
	return String(tactic(id).get("label", id))


## Durée d'une bataille, en jours (la somme des phases).
static func battle_days() -> int:
	var n := 0
	for p: Dictionary in data()["phases"]:
		n += int(p["days"])
	return n


## Phase (0 longue, 1 moyenne, 2 courte portée) du jour « day » d'une bataille (1 = premier jour).
static func phase_index(day: int) -> int:
	var phases: Array = data()["phases"]
	var acc := 0
	for i in phases.size():
		acc += int(phases[i]["days"])
		if day <= acc:
			return i
	return phases.size() - 1


static func phase_label(i: int) -> String:
	return String(data()["phases"][clampi(i, 0, data()["phases"].size() - 1)]["label"])


## Efficacité (en %) d'une famille d'armes à une phase.
static func weapon_eff(weapon: String, phase: int) -> int:
	return int(data()["weapons"].get(weapon, {}).get("eff", [100, 100, 100])[phase])


## Dégâts d'un tir : arme de puissance `power`, à la phase donnée, modifiée par la tactique du tireur,
## un bonus en % (traits de peuple), la défense de la cible et sa tactique.
static func shot_damage(weapon: String, power: int, phase: int, shooter_tactic: String, bonus_pct: int,
		target_ship: String, target_tactic: String) -> int:
	var wd: Dictionary = data()["weapons"].get(weapon, {})
	var defense := int(GameData.ship(target_ship).get(String(wd.get("defense", "armor")), 0)) if target_ship != "" else 0
	var mult := int(tactic(shooter_tactic)["dmg"][phase])
	var taken := int(tactic(target_tactic).get("taken", 100))
	@warning_ignore("integer_division")
	var d := power * weapon_eff(weapon, phase) * mult * bonus_pct * (100 - defense) * taken / 10000000000
	return maxi(1, d)


# --- Guerre ------------------------------------------------------------------------------------

static func at_war(state: GameState, a: int, b: int) -> bool:
	if a == b or a < 0 or b < 0:
		return false
	var e := state.get_empire(a)
	return e != null and e.wars.has(b)


## Trait de combat d'un peuple (bloc "combat" de data/factions.json).
static func trait_value(state: GameState, empire_id: int, key: String, default: Variant = 0) -> Variant:
	var e := state.get_empire(empire_id)
	if e == null:
		return default
	return e.faction().get("combat", {}).get(key, default)


## L'Essaim Kh'thari est en guerre avec tout empire rencontré.
static func always_war(state: GameState, empire_id: int) -> bool:
	return bool(trait_value(state, empire_id, "always_war", false))


static func check_declare_war(state: GameState, empire_id: int, target: int) -> String:
	var e := state.get_empire(empire_id)
	var t := state.get_empire(target)
	if e == null or t == null:
		return "empire inconnu"
	if empire_id == target:
		return "un empire ne peut pas se déclarer la guerre (pas officiellement)"
	if e.eliminated or t.eliminated:
		return "cet empire a disparu"
	if not e.contacts.has(target):
		return "vous n'avez jamais rencontré cet empire"
	if e.wars.has(target):
		return "vous êtes déjà en guerre"
	return ""


## Déclare la guerre, dans les deux sens. Renvoie l'entrée de chronique.
static func start_war(state: GameState, a: int, b: int, by_nature := false) -> Dictionary:
	var ea := state.get_empire(a)
	var eb := state.get_empire(b)
	if not ea.wars.has(b):
		ea.wars.append(b)
		ea.wars.sort()
	if not eb.wars.has(a):
		eb.wars.append(a)
		eb.wars.sort()
	if by_nature:
		return state.add_chronicle("%s rencontre %s et ne voit pas l'intérêt de discuter. C'est la guerre : l'Essaim ne signe rien, il digère." % [
				ea.display_name(), eb.display_name()])
	return state.add_chronicle("%s déclare la guerre à %s. Les amirautés ressortent les cartes, les poètes les hymnes." % [
			ea.display_name(), eb.display_name()])


# --- Systèmes : garnison, siège, invasion ------------------------------------------------------

## Garnison maximale d'un système revendiqué : population, avant-postes, capitale et bastions,
## modulée par le peuple (fiefs d'Ossarane). 0 pour un système libre.
static func garrison_max(state: GameState, system_id: int) -> int:
	var owner := state.system_owner(system_id)
	if owner < 0:
		return 0
	var g: Dictionary = data()["garrison"]
	var e := state.get_empire(owner)
	var n := 0
	for pid in state.galaxy.systems[system_id].planet_ids:
		var c: Colony = state.colonies.get(pid)
		if c == null or c.owner != owner or not c.is_established():
			continue
		n += c.population * int(g["per_pop"]) if c.is_colony() else int(g["per_outpost"])
		if pid == e.capital_planet:
			n += int(g["capital"])
		for b in c.buildings:
			n += int(GameData.building(b).get("garrison", 0))
	@warning_ignore("integer_division")
	return n * int(trait_value(state, owner, "garrison_pct", 100)) / 100


## Garnison actuelle (le siège l'use, elle remonte ensuite d'un point par jour).
static func garrison(state: GameState, system_id: int) -> int:
	var mx := garrison_max(state, system_id)
	return mini(mx, int(state.garrisons.get(system_id, mx)))


## Batteries des bastions du système : {arme: puissance}.
static func battery(state: GameState, system_id: int) -> Dictionary:
	var owner := state.system_owner(system_id)
	var out := {}
	if owner < 0:
		return out
	for pid in state.galaxy.systems[system_id].planet_ids:
		var c: Colony = state.colonies.get(pid)
		if c == null or c.owner != owner or not c.is_established():
			continue
		for b in c.buildings:
			var bat: Dictionary = GameData.building(b).get("battery", {})
			for k in bat:
				out[k] = int(out.get(k, 0)) + int(bat[k])
	return out


## Flottes ennemies armées, à l'arrêt, qui assiègent le système : leur empire est en guerre avec
## le propriétaire, et aucune flotte armée du propriétaire n'est là pour les en empêcher.
static func besiegers(state: GameState, system_id: int) -> Array[Fleet]:
	var out: Array[Fleet] = []
	var owner := state.system_owner(system_id)
	if owner < 0:
		return out
	var here := Fleets.fleets_at(state, system_id)
	for f in here:
		if f.owner == owner and is_armed(f):
			return []
	for f in here:
		if at_war(state, f.owner, owner) and is_armed(f):
			out.append(f)
	return out


## Le système est-il assiégé (constaté au dernier jour de simulation) ?
static func is_besieged(state: GameState, system_id: int) -> bool:
	return state.sieges.has(system_id)


## Un ennemi armé à l'arrêt dans ce système arrête les flottes de cet empire qui le traversent (blocus).
static func blocks(state: GameState, empire_id: int, system_id: int) -> bool:
	for f in Fleets.fleets_at(state, system_id):
		if at_war(state, f.owner, empire_id) and is_armed(f):
			return true
	return false


## Bataille en cours dans un système ({} s'il n'y en a pas).
static func battle_at(state: GameState, system_id: int) -> Dictionary:
	return state.battles.get(system_id, {})


static func check_invade(state: GameState, empire_id: int, fleet_id: int) -> String:
	var f: Fleet = state.fleets.get(fleet_id)
	if f == null or f.owner != empire_id:
		return "cette flotte ne vous appartient pas"
	if f.is_moving():
		return "la flotte doit être à l'arrêt dans le système visé"
	var owner := state.system_owner(f.system_id)
	if owner < 0 or owner == empire_id:
		return "aucun système ennemi à envahir ici"
	if not at_war(state, empire_id, owner):
		return "vous n'êtes pas en guerre avec %s" % state.get_empire(owner).short_name()
	for other in Fleets.fleets_at(state, f.system_id, owner):
		if is_armed(other):
			return "une flotte de défense tient encore l'orbite"
	if f.troops <= 0:
		return "aucune troupe à bord (les croiseurs en emportent le plus)"
	var g := garrison(state, f.system_id)
	if f.troops <= g:
		return "%d troupes contre une garnison de %d : assiégez pour l'user, ou amenez du renfort" % [f.troops, g]
	return ""


## Prise d'un système : les revendications du propriétaire changent de mains. L'Essaim digère les
## colonies conquises (il n'y reste qu'une population, le reste devient biomasse).
## Renvoie les entrées de chronique.
static func capture_system(state: GameState, system_id: int, new_owner: int) -> Array[Dictionary]:
	var added: Array[Dictionary] = []
	var old := state.system_owner(system_id)
	var eo := state.get_empire(old)
	var en := state.get_empire(new_owner)
	var digest := bool(trait_value(state, new_owner, "digest", false))
	var bio := int(en.faction().get("biomass", {}).get("materials", 0))
	var digested := 0
	var lost_capital := false
	for pid in state.galaxy.systems[system_id].planet_ids:
		var c: Colony = state.colonies.get(pid)
		if c == null or c.owner != old:
			continue
		if digest and c.is_colony() and c.population > 1:
			digested += c.population - 1
			c.population = 1
		c.owner = new_owner
		c.construction = ""
		c.construction_days = 0
		c.ship_build = ""
		c.ship_days = 0
		c.growth = 0
		if eo.capital_planet == pid:
			lost_capital = true
	if digested > 0:
		en.resources["materials"] = int(en.resources.get("materials", 0)) + digested * bio
		en.biomass += digested * bio
	state.rebuild_ownership()
	state.garrisons[system_id] = 0
	state.sieges.erase(system_id)
	var sname := state.galaxy.systems[system_id].system_name
	var fervor := int(trait_value(state, new_owner, "fervor_per_conquest", 0))
	if fervor > 0 and FactionTraits.has_fervor(en.faction()):
		en.fervor = mini(int(en.faction()["fervor"]["max"]), en.fervor + fervor)
	if digested > 0:
		added.append(state.add_chronicle("%s envahit %s. %d population%s digérée%s en biomasse ; les survivants sont priés de se sentir chez eux." % [
				en.display_name(), sname, digested, "s" if digested > 1 else "", "s" if digested > 1 else ""]))
	else:
		added.append(state.add_chronicle("%s envahit %s et en chasse %s. On repeint les drapeaux ; les habitants, eux, restent." % [
				en.display_name(), sname, eo.display_name()]))
	if lost_capital:
		eo.capital_planet = _new_capital(state, old)
		if eo.capital_planet >= 0:
			added.append(state.add_chronicle("%s perd sa capitale et se replie sur %s. La cour emporte les archives, et surtout l'argenterie." % [
					eo.display_name(), state.galaxy.get_planet(eo.capital_planet).display_name(state.galaxy)]))
	return added


## Nouvelle capitale après une perte : la colonie fondée la plus peuplée (-1 s'il n'y en a plus).
static func _new_capital(state: GameState, empire_id: int) -> int:
	var best: Colony = null
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner == empire_id and c.is_colony() and c.is_established() and (best == null or c.population > best.population):
			best = c
	return best.planet_id if best else -1


static func check_tactic(state: GameState, empire_id: int, fleet_id: int, tactic_id: String) -> String:
	var f: Fleet = state.fleets.get(fleet_id)
	if f == null or f.owner != empire_id:
		return "cette flotte ne vous appartient pas"
	if not tactic_ids().has(tactic_id):
		return "tactique inconnue : %s" % tactic_id
	if fleet_tactic(f) == tactic_id:
		return "la flotte suit déjà cette tactique"
	return ""


# --- Affichage ---------------------------------------------------------------------------------

## « Rayons 30 · blindage 10 % · boucliers 30 % · 4 troupes »
static func ship_summary(ship_id: String) -> String:
	var sd := GameData.ship(ship_id)
	var parts := PackedStringArray()
	var w := weapons(ship_id)
	for k in w:
		parts.append("%s %d" % [String(data()["weapons"][k]["short"]), int(w[k])])
	parts.append("structure %d" % Fleet.max_hp_of(ship_id))
	if int(sd.get("armor", 0)) > 0:
		parts.append("blindage %d %%" % int(sd["armor"]))
	if int(sd.get("shield", 0)) > 0:
		parts.append("boucliers %d %%" % int(sd["shield"]))
	if int(sd.get("troops", 0)) > 0:
		parts.append("%d troupes" % int(sd["troops"]))
	return "  ·  ".join(parts)


## Total d'un dictionnaire {classe: nombre}.
static func count_ships(d: Dictionary) -> int:
	var n := 0
	for k in d:
		n += int(d[k])
	return n


## « 3 Corvettes, Frégate » à partir d'un dictionnaire {classe: nombre}.
static func ships_text(d: Dictionary) -> String:
	var parts := PackedStringArray()
	for sid in GameData.ship_ids():
		var n := int(d.get(sid, 0))
		if n == 1:
			parts.append(String(GameData.ship(sid)["label"]))
		elif n > 1:
			parts.append("%d %s" % [n, GameData.ship(sid)["plural"]])
	return ", ".join(parts) if not parts.is_empty() else "aucun"
