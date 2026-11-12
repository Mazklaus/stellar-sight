class_name Curios
extends RefCounted
## Curiosités (étude « Événements, quêtes et reliques », 2026-11-12, propositions 1 et 2) : des
## planètes portent une curiosité de niveau 1 à 4 et d'un type (atmosphérique, souterraine, vivante,
## ruines, épave). Le niveau de détection d'un empire dit ce qu'il voit, sa puissance d'expédition
## combien de temps il met à la sonder : un vaisseau sans armes à l'arrêt dans le système, ou une
## station d'étude dans le système, la sonde chaque jour. Premier arrivé, premier servi : la
## curiosité sondée disparaît pour les autres. La récompense est tirée dans la table de son type.
## Sources : Endless Space 2 (niveaux, détection, puissance d'expédition, types, pièges), Stellaris
## (durée selon l'écart de niveau), Civilization VI (premier arrivé, récompenses qui grandissent).
## Règles dans data/events.json "curios". Entiers, tirages par hachage de la graine.
##
## state.curios[pid] = {"lvl": 1-4, "type": id, "name": indice du nom, "done": empire qui l'a sondée
##   (-1 sinon), "day": jour où elle l'a été, "prog": {empire: jours de sonde accumulés}}.
## state.curio_traps = [{"fleet": id, "until": jour}] : flottes pirates sorties d'un piège, retirées
##   au bout de trap_days si elles sont encore là.

const STATION := "station_etude"


static func data() -> Dictionary:
	return GameData.events()["curios"]


static func densities() -> Array:
	return data()["densities"]


static func density_def(id: String) -> Dictionary:
	for d: Dictionary in densities():
		if String(d["id"]) == id:
			return d
	return {}


static func default_density() -> String:
	return String(data().get("default", "normales"))


static func type_def(t: String) -> Dictionary:
	return (data()["types"] as Dictionary).get(t, {})


static func type_ids() -> Array:
	var ids: Array = (data()["types"] as Dictionary).keys()
	ids.sort()
	return ids


static func _h(state: GameState, parts: Array) -> int:
	return absi(hash([state.seed_value, "curio"] + parts))


# --- Placement ---------------------------------------------------------------------------------

## Place les curiosités d'une nouvelle partie : une planète sur `per` environ, jamais sur un monde
## d'origine ni dans un système revendiqué au départ. Le niveau monte avec la distance au départ le
## plus proche. Tout passe par un hachage de la graine : même partie, mêmes curiosités.
static func setup(state: GameState, density_id: String) -> void:
	state.curio_density = density_id if not density_def(density_id).is_empty() else "aucune"
	state.curios.clear()
	var per := int(density_def(state.curio_density).get("per", 0))
	if per <= 0:
		return
	var starts: Array = []
	for e in state.empires:
		var cap := FactionTraits.capital_system(state, e.id)
		if cap < 0 and e.home_planet >= 0:
			cap = state.galaxy.get_planet(e.home_planet).system_id
		if cap >= 0:
			starts.append(FactionTraits.jumps_from(state.galaxy, cap))
	var tw: Dictionary = data()["type_weights"]
	var types := type_ids()
	var total_tw := 0
	for t in types:
		total_tw += int(tw.get(t, 0))
	var lw: Array = data()["level_weights"]
	for sys in state.galaxy.systems:
		if state.system_owner(sys.id) >= 0:
			continue
		var near := 999
		for d: Dictionary in starts:
			near = mini(near, int(d.get(sys.id, 999)))
		var max_lvl := 4
		for pair in data()["level_max_by_jumps"]:
			if near < int(pair[0]):
				max_lvl = int(pair[1])
				break
		for pid in sys.planet_ids:
			if _h(state, ["place", pid]) % per != 0:
				continue
			var tot := 0
			for i in max_lvl:
				tot += int(lw[i])
			var roll := _h(state, ["lvl", pid]) % maxi(1, tot)
			var lvl := 1
			for i in max_lvl:
				roll -= int(lw[i])
				if roll < 0:
					lvl = i + 1
					break
			var troll := _h(state, ["type", pid]) % maxi(1, total_tw)
			var typ := String(types[0])
			for t in types:
				troll -= int(tw.get(t, 0))
				if troll < 0:
					typ = String(t)
					break
			var names: Array = (data()["names"] as Dictionary).get(typ, [""])
			state.curios[pid] = {"lvl": lvl, "type": typ, "name": _h(state, ["name", pid]) % names.size(), "done": -1, "day": 0, "prog": {}}


# --- Ce qu'un empire voit et peut faire ---------------------------------------------------------

## Niveau de détection : les curiosités de ce niveau ou moins sont visibles dans les systèmes explorés.
static func detect(state: GameState, empire_id: int) -> int:
	return int(data()["base_detect"]) + Research.fx_int(state, empire_id, "curio_detect")


## Puissance d'expédition : plus elle dépasse le niveau, plus la sonde est rapide.
static func power(state: GameState, empire_id: int) -> int:
	var p := int(data()["base_power"]) + Research.fx_int(state, empire_id, "curio_power")
	var e := state.get_empire(empire_id)
	if e != null and not e.is_npc():
		p += int((data().get("talents", {}) as Dictionary).get(String(e.faction().get("species", {}).get("credo", "")), 0))
	return p


static func is_open(state: GameState, pid: int) -> bool:
	return state.curios.has(pid) and int(state.curios[pid]["done"]) < 0


## L'empire voit-il la curiosité de cette planète (non sondée, système exploré, niveau détecté) ?
static func sees(state: GameState, empire_id: int, pid: int) -> bool:
	if not is_open(state, pid):
		return false
	var e := state.get_empire(empire_id)
	if e == null or e.is_npc():
		return false
	var sid := state.galaxy.get_planet(pid).system_id
	return e.explored.has(sid) and int(state.curios[pid]["lvl"]) <= detect(state, empire_id)


## Curiosités ouvertes visibles par l'empire dans un système, par identifiant de planète.
static func visible_in(state: GameState, empire_id: int, sid: int) -> Array[int]:
	var out: Array[int] = []
	if state.curios.is_empty():
		return out
	for pid in state.galaxy.systems[sid].planet_ids:
		if sees(state, empire_id, pid):
			out.append(pid)
	return out


## Toutes les curiosités ouvertes que l'empire voit, triées.
static func known(state: GameState, empire_id: int) -> Array[int]:
	var out: Array[int] = []
	var ids := state.curios.keys()
	ids.sort()
	for pid in ids:
		if sees(state, empire_id, int(pid)):
			out.append(int(pid))
	return out


## Jours de sonde nécessaires pour cet empire.
static func duration(state: GameState, empire_id: int, pid: int) -> int:
	var gap := clampi(power(state, empire_id) - int(state.curios[pid]["lvl"]), -3, 1)
	return int((data()["days_by_gap"] as Dictionary).get(str(gap), 60))


static func progress(state: GameState, empire_id: int, pid: int) -> int:
	if not state.curios.has(pid):
		return 0
	return int((state.curios[pid]["prog"] as Dictionary).get(empire_id, 0))


static func curio_name(state: GameState, pid: int) -> String:
	var c: Dictionary = state.curios.get(pid, {})
	if c.is_empty():
		return ""
	var names: Array = (data()["names"] as Dictionary).get(String(c["type"]), [""])
	return String(names[int(c["name"]) % names.size()])


## « Temple scellé (ruines, niveau 3) ».
static func describe(state: GameState, pid: int) -> String:
	var c: Dictionary = state.curios[pid]
	return "%s (%s, niveau %d)" % [curio_name(state, pid), String(type_def(String(c["type"]))["label"]).to_lower(), int(c["lvl"])]


## La curiosité que l'empire sonde dans ce système : la première ouverte et visible.
static func target_in(state: GameState, empire_id: int, sid: int) -> int:
	var v := visible_in(state, empire_id, sid)
	return v[0] if not v.is_empty() else -1


## Une flotte de cet empire peut-elle sonder ici (sans armes, à l'arrêt, pas de bataille) ?
static func can_probe(state: GameState, f: Fleet) -> bool:
	if f.is_moving() or GameState.is_npc(f.owner) or Combat.is_armed(f) or state.battles.has(f.system_id):
		return false
	return target_in(state, f.owner, f.system_id) >= 0


## Une station d'étude de l'empire dans ce système ?
static func has_station(state: GameState, empire_id: int, sid: int) -> bool:
	for pid in state.galaxy.systems[sid].planet_ids:
		var c: Colony = state.colonies.get(pid)
		if c != null and c.owner == empire_id and c.buildings.has(STATION):
			return true
	return false


## Un éclaireur en exploration automatique attend ici s'il sonde une curiosité assez rapide.
static func wants_to_stay(state: GameState, f: Fleet) -> bool:
	if state.curios.is_empty() or not can_probe(state, f):
		return false
	var pid := target_in(state, f.owner, f.system_id)
	return duration(state, f.owner, pid) <= int(data()["explore_wait_days"])


# --- Chaque jour ---------------------------------------------------------------------------------

static func daily(state: GameState, added: Array[Dictionary]) -> void:
	if not state.curio_traps.is_empty():
		_traps(state)
	if state.curios.is_empty():
		return
	# Qui sonde quoi aujourd'hui : une seule avance par empire et par curiosité, quel que soit le
	# nombre de vaisseaux. Parcours dans l'ordre des flottes puis des colonies (déterministe).
	var probing := {}
	for fid in state.sorted_fleet_ids():
		var f: Fleet = state.fleets[fid]
		if can_probe(state, f):
			probing["%d:%d" % [f.owner, target_in(state, f.owner, f.system_id)]] = [f.owner, target_in(state, f.owner, f.system_id)]
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner < 0 or GameState.is_npc(c.owner) or not c.buildings.has(STATION) or not c.is_established():
			continue
		var sid := state.galaxy.get_planet(pid).system_id
		if state.battles.has(sid):
			continue
		var t := target_in(state, c.owner, sid)
		if t >= 0:
			probing["%d:%d" % [c.owner, t]] = [c.owner, t]
	var keys := probing.keys()
	keys.sort_custom(func(a: String, b: String) -> bool:
		var pa: Array = probing[a]
		var pb: Array = probing[b]
		return int(pa[1]) < int(pb[1]) or (int(pa[1]) == int(pb[1]) and int(pa[0]) < int(pb[0])))
	for k in keys:
		var eid := int(probing[k][0])
		var pid := int(probing[k][1])
		if not is_open(state, pid):
			continue  # un autre empire l'a terminée plus tôt dans la journée
		var prog: Dictionary = state.curios[pid]["prog"]
		prog[eid] = int(prog.get(eid, 0)) + 1
		if int(prog[eid]) >= duration(state, eid, pid):
			resolve(state, eid, pid, added)


## La sonde aboutit : la curiosité est à cet empire, la récompense tombe.
static func resolve(state: GameState, empire_id: int, pid: int, added: Array[Dictionary]) -> void:
	var c: Dictionary = state.curios[pid]
	c["done"] = empire_id
	c["day"] = state.tick
	c["prog"] = {}
	Research.count_stat(state, empire_id, "curios")
	Research.count_stat(state, empire_id, "collection")
	var kind := _pick_reward(state, empire_id, pid)
	var got := _give(state, empire_id, pid, kind, added) + _layer_bonus(state, empire_id, pid)
	var e := state.get_empire(empire_id)
	added.append(state.add_chronicle("%s sonde %s sur %s : %s" % [e.short_name(), describe(state, pid),
			state.galaxy.get_planet(pid).display_name(state.galaxy), got], Espionage.private_to(state, [empire_id], state.galaxy.get_planet(pid).system_id)))


## Talents de couche (proposition 15) : une ruche dévore les curiosités vivantes (population), un peuple
## cosmique en tire des Échos.
static func _layer_bonus(state: GameState, empire_id: int, pid: int) -> String:
	var e := state.get_empire(empire_id)
	var c: Dictionary = state.curios[pid]
	var out := ""
	if String(c["type"]) == "vivante" and Events.layer_value(state, empire_id, "archetype") == "ruche":
		var col := _own_colony_in(state, empire_id, state.galaxy.get_planet(pid).system_id)
		if col == null:
			col = state.colonies.get(e.capital_planet)
		if col != null:
			col.population += int(Relics.rules()["hive_pop"])
			out += " L'Essaim dévore ce qui restait : +%d population." % int(Relics.rules()["hive_pop"])
	if Events.layer_value(state, empire_id, "registre") == "Cosmique / étrange" and Echoes.has(e.faction()):
		var n := int(Relics.rules()["cosmic_echoes"]) * int(c["lvl"])
		e.echoes += n
		out += " Elle résonne encore : +%d Échos." % n
	return out


static func _pick_reward(state: GameState, empire_id: int, pid: int) -> String:
	var table: Dictionary = type_def(String(state.curios[pid]["type"]))["rewards"]
	var keys := table.keys()
	keys.sort()
	var tot := 0
	for k in keys:
		tot += int(table[k])
	var roll := _h(state, ["reward", pid, empire_id]) % maxi(1, tot)
	for k in keys:
		roll -= int(table[k])
		if roll < 0:
			return String(k)
	return "nothing"


## Montant d'une récompense en ressource : selon le niveau, multiplié par l'ère de l'empire.
static func amount(state: GameState, empire_id: int, lvl: int, res: String) -> int:
	var base := int((data()["amount_by_level"] as Array)[clampi(lvl, 1, 4) - 1])
	base = Events.era_scaled(state, empire_id, base)
	match res:
		"crystals":
			@warning_ignore("integer_division")
			return maxi(3, base / 6)
		"influence":
			@warning_ignore("integer_division")
			return maxi(5, base / 3)
	return base


## Applique la récompense et renvoie la fin de la phrase de chronique.
static func _give(state: GameState, empire_id: int, pid: int, kind: String, added: Array[Dictionary]) -> String:
	var c: Dictionary = state.curios[pid]
	var lvl := int(c["lvl"])
	var e := state.get_empire(empire_id)
	var p := state.galaxy.get_planet(pid)
	if kind.begins_with("res_"):
		var res := kind.substr(4)
		var n := amount(state, empire_id, lvl, res)
		e.resources[res] = int(e.resources.get(res, 0)) + n
		return "%s. Les comptables n'en reviennent pas." % GameData.format_amounts({res: n}, true)
	if kind.begins_with("deposit_"):
		var dep := kind.substr(8)
		var ddef: Dictionary = GameData.deposit(dep)
		if ddef.is_empty() or p.deposits.has(dep) or (bool(ddef.get("habitable_only", false)) and not p.is_habitable_type()):
			return _give(state, empire_id, pid, "research", added)
		var deps: Array = Array(p.deposits)
		deps.append(dep)
		state.override_planet(pid, {"deposits": deps})
		return "un gisement de %s affleure. Les prospecteurs se battent déjà pour la première pioche." % String(ddef["label"]).to_lower()
	match kind:
		"research":
			var pct := int((data()["research_pct_by_level"] as Array)[lvl - 1])
			return Events.give_research(state, empire_id, pct) + ". Les savants réclament une plaque commémorative."
		"ship":
			var ship := String((data()["ship_by_level"] as Array)[lvl - 1])
			var f := state.spawn_ship(empire_id, ship, p.system_id)
			return "on remet en état un %s, rebaptisé %s. Il grince, mais il vole." % [String(GameData.ship(ship).get("label", ship)).to_lower(), f.fleet_name]
		"pop":
			var col := _own_colony_in(state, empire_id, p.system_id)
			if col == null:
				return _give(state, empire_id, pid, "res_food", added)
			var n := int((data()["pop_by_level"] as Array)[lvl - 1])
			col.population += n
			return "%d population d'une espèce locale demande l'asile à %s. Elle apporte ses recettes." % [n, state.galaxy.get_planet(col.planet_id).display_name(state.galaxy)]
		"card":
			var cards: Array = (data()["curio_cards"] as Dictionary).get(String(c["type"]), [])
			if cards.is_empty() or not Events.enabled(state):
				return _give(state, empire_id, pid, "research", added)
			var card := String(cards[_h(state, ["card", pid]) % cards.size()])
			Events.push(state, empire_id, card, {"system": p.system_id, "planet": pid}, added)
			return "l'expédition attend vos ordres (fenêtre d'événement)."
		"trap":
			spawn_trap(state, p.system_id, lvl)
			return "c'était un piège ! Une bande de pirates surgit de sa cachette."
		"fragments":
			if state.relics.is_empty():
				return _give(state, empire_id, pid, "research", added)
			var nf := 5 * lvl + 5
			Relics.add_fragments(state, empire_id, nf)
			return "%d fragments d'artéfacts, soigneusement étiquetés « sans doute important »." % nf
		"quest":
			# Départ d'une quête secondaire (proposition 2), selon le type de la curiosité.
			var qt := String((Quests.data()["origins"]["curio"] as Dictionary).get(String(c["type"]), ""))
			if qt == "" or not Quests.enabled(state) or (Quests.meta(state, empire_id)["seen"] as Dictionary).has(qt) \
					or Quests.start(state, empire_id, qt, {}, added) < 0:
				return _give(state, empire_id, pid, "research", added)
			return "une piste s'ouvre : la quête « %s » commence." % String(Quests.tpl(qt)["title"])
		"dig":
			# Ruines de niveau 3-4 : un chantier de fouilles s'ouvre dans le système.
			if lvl < 3 or state.relics.is_empty() or not Relics.create_site(state, p.system_id):
				return _give(state, empire_id, pid, "fragments", added)
			return "sous les ruines, un site entier : %s. Il faudra posséder le système pour le fouiller." % Relics.site_name(state, p.system_id)
	return "rien, sinon une belle photo et un équipage vexé."


static func _own_colony_in(state: GameState, empire_id: int, sid: int) -> Colony:
	for pid in state.galaxy.systems[sid].planet_ids:
		var c: Colony = state.colonies.get(pid)
		if c != null and c.owner == empire_id and c.is_colony() and c.is_established():
			return c
	return null


## Une flotte pirate surgit dans le système (piège d'une curiosité ou d'un événement).
static func spawn_trap(state: GameState, sid: int, lvl: int) -> Fleet:
	var ships: Array = (data()["trap_ships_by_level"] as Array)[clampi(lvl, 1, 4) - 1]
	var f := state.spawn_ship(GameState.PIRATE_ID, String(ships[0]), sid)
	for i in range(1, ships.size()):
		f.add_ship(String(ships[i]), -1, 1)
	f.troops = 0
	f.fleet_name = "Pillards embusqués"
	state.curio_traps.append({"fleet": f.id, "until": state.tick + int(data()["trap_days"])})
	return f


static func _traps(state: GameState) -> void:
	var kept: Array[Dictionary] = []
	for t in state.curio_traps:
		var fid := int(t["fleet"])
		if not state.fleets.has(fid):
			continue
		if state.tick >= int(t["until"]) and not state.battles.has((state.fleets[fid] as Fleet).system_id):
			state.fleets.erase(fid)
			continue
		kept.append(t)
	state.curio_traps = kept


# --- Sauvegarde ----------------------------------------------------------------------------------

static func to_list(state: GameState) -> Array:
	var ids := state.curios.keys()
	ids.sort()
	var out := []
	for pid in ids:
		var c: Dictionary = state.curios[pid]
		var prog := []
		var pk: Array = (c["prog"] as Dictionary).keys()
		pk.sort()
		for k in pk:
			prog.append([int(k), int(c["prog"][k])])
		out.append({"pid": int(pid), "lvl": int(c["lvl"]), "type": String(c["type"]), "name": int(c["name"]),
				"done": int(c["done"]), "day": int(c["day"]), "prog": prog})
	return out


static func from_list(state: GameState, list: Array) -> void:
	state.curios.clear()
	for d: Dictionary in list:
		var prog := {}
		for pair in d.get("prog", []):
			prog[int(pair[0])] = int(pair[1])
		state.curios[int(d["pid"])] = {"lvl": int(d["lvl"]), "type": String(d["type"]), "name": int(d.get("name", 0)),
				"done": int(d.get("done", -1)), "day": int(d.get("day", 0)), "prog": prog}
