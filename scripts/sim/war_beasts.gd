class_name WarBeasts
extends RefCounted
## Bêtes de guerre (étude « Créatures spatiales et gardiens », lot 3, proposition 11 ; règles dans
## data/creatures.json, "war_beasts"). Un vaisseau à filet gravitationnel (le Chalutier du vide, ou un
## modèle avec le module) à l'arrêt, hors bataille, dans un système où vit un troupeau d'une espèce que
## l'empire a apprivoisée, en capture une bête tous les net_days, si ses Vivariums ont de la place.
## La bête grandit au Vivarium : jeune, puis adulte, puis ancienne. On la lâche adulte ou ancienne :
## elle devient un vaisseau (bete_<espèce>_adulte / _ancien) au système du premier Vivarium et coûte
## des vivres au lieu de matériaux. Socle des futures Hardes de Kraal.
## État : state.fauna["beasts"] = {empire: [{"sp", "born"}]}, state.fauna["nets"] = {flotte: [système, début]}.


static func data() -> Dictionary:
	return GameData.creatures().get("war_beasts", {})


static func beasts(state: GameState, empire_id: int) -> Array:
	return (state.fauna.get("beasts", {}) as Dictionary).get(empire_id, [])


## Stade d'une bête : "jeune", "adulte" ou "ancien".
static func stage(state: GameState, b: Dictionary) -> String:
	var age := state.tick - int(b["born"])
	var d := data()
	if age >= int(d["elder_days"]):
		return "ancien"
	if age >= int(d["adult_days"]):
		return "adulte"
	return "jeune"


static func stage_label(st: String) -> String:
	return String((data().get("stages", {}) as Dictionary).get(st, st))


## Vaisseau que devient la bête lâchée à ce stade.
static func unit_for(sp: String, st: String) -> String:
	var base := String(Fauna.species(sp).get("unit", ""))
	return "%s_%s" % [base, st]


## Places au Vivarium (somme des Vivariums de l'empire).
static func capacity(state: GameState, empire_id: int) -> int:
	var per := 0
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner == empire_id:
			for bid in c.buildings:
				per += int(GameData.building(String(bid)).get("vivarium", 0))
	return per


## Système du premier Vivarium de l'empire (-1 s'il n'en a pas).
static func vivarium_system(state: GameState, empire_id: int) -> int:
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner == empire_id and c.buildings.has("vivarium"):
			return state.galaxy.get_planet(pid).system_id
	return -1


## Le Vivarium se bâtit-il ? Il faut avoir étudié une espèce (ruche et reptiliens : dès le départ).
static func check_vivarium(state: GameState, empire_id: int) -> String:
	if bool(Fauna.talent(state, empire_id).get("vivarium_free", false)):
		return ""
	for sp in Fauna.species_ids():
		if Fauna.studied(state, empire_id, sp):
			return ""
	return "il faut d'abord avoir étudié une espèce de créatures"


static func has_net(f: Fleet) -> bool:
	for s in f.ships:
		if bool(GameData.ship(s).get("net", false)):
			return true
	return false


# --- Chaque jour ------------------------------------------------------------------------------------

static func daily(state: GameState, added: Array[Dictionary]) -> void:
	if state.fauna.is_empty() or Fauna.herds(state).is_empty():
		return
	if not state.fauna.has("nets"):
		state.fauna["nets"] = {}
	var nets: Dictionary = state.fauna["nets"]
	var seen := {}
	for fid in state.sorted_fleet_ids():
		var f: Fleet = state.fleets[fid]
		if GameState.is_npc(f.owner) or f.is_moving() or state.battles.has(f.system_id) or Combat.is_armed(f) or not has_net(f):
			continue
		var sp := _catchable(state, f)
		if sp == "":
			continue
		seen[fid] = true
		var cur: Array = nets.get(fid, [])
		if cur.is_empty() or int(cur[0]) != f.system_id:
			nets[fid] = [f.system_id, state.tick]
			continue
		if state.tick - int(cur[1]) < int(data()["net_days"]):
			continue
		nets[fid] = [f.system_id, state.tick]
		_capture(state, f, sp, added)
	for k in nets.keys():
		if not seen.has(k):
			nets.erase(k)
	if nets.is_empty():
		state.fauna.erase("nets")


## Espèce qu'on peut capturer ici : un troupeau d'une espèce apprivoisée par l'empire ("" sinon).
static func _catchable(state: GameState, f: Fleet) -> String:
	for g in Fleets.fleets_at(state, f.system_id, GameState.FAUNA_ID):
		var h := Fauna.herd_of(state, g)
		if h.is_empty() or g.is_moving() or g.ships.is_empty():
			continue
		var sp := String(h["sp"])
		if Fauna.stance(state, f.owner, sp) == "apprivoise":
			return sp
	return ""


static func _capture(state: GameState, f: Fleet, sp: String, added: Array[Dictionary]) -> void:
	var e := state.get_empire(f.owner)
	var room := capacity(state, f.owner) - beasts(state, f.owner).size()
	if room <= 0:
		if not e.is_ai() and posmod(state.tick, 90) < int(data()["net_days"]):
			added.append(state.add_chronicle("Le filet de %s est plein, mais aucun Vivarium n'a de place : on relâche la bête, à regret." % f.fleet_name,
					Espionage.private_to(state, [f.owner])))
		return
	var herd: Fleet = null
	for g in Fleets.fleets_at(state, f.system_id, GameState.FAUNA_ID):
		var h := Fauna.herd_of(state, g)
		if not h.is_empty() and String(h["sp"]) == sp and not g.ships.is_empty():
			herd = g
			break
	if herd == null:
		return
	herd.ships.remove_at(herd.ships.size() - 1)
	herd.hp.remove_at(herd.hp.size() - 1)
	if herd.ships.is_empty():
		state.fleets.erase(herd.id)  # FaunaSystem raye le troupeau et son nid note la perte
	if not state.fauna.has("beasts"):
		state.fauna["beasts"] = {}
	if not state.fauna["beasts"].has(f.owner):
		state.fauna["beasts"][f.owner] = []
	(state.fauna["beasts"][f.owner] as Array).append({"sp": sp, "born": state.tick})
	if not e.is_ai():
		added.append(state.add_chronicle("%s ramène une jeune bête des %s au Vivarium. Elle mord, mais gentiment." % [
				f.fleet_name, String(Fauna.species(sp)["label"])], Espionage.private_to(state, [f.owner])))


# --- Lâcher une bête --------------------------------------------------------------------------------

static func check_release(state: GameState, empire_id: int, index: int) -> String:
	var e := state.get_empire(empire_id)
	if e == null or e.is_npc() or e.eliminated:
		return "empire inconnu"
	var l := beasts(state, empire_id)
	if index < 0 or index >= l.size():
		return "bête inconnue"
	if stage(state, l[index]) == "jeune":
		return "elle est encore trop jeune"
	if vivarium_system(state, empire_id) < 0:
		return "il faut un Vivarium"
	return ""


static func release(state: GameState, empire_id: int, index: int) -> Fleet:
	var l := beasts(state, empire_id)
	var b: Dictionary = l[index]
	l.remove_at(index)
	var sid := vivarium_system(state, empire_id)
	var unit := unit_for(String(b["sp"]), stage(state, b))
	var f := state.spawn_ship(empire_id, unit, sid)
	f.fleet_name = "Bêtes de guerre"
	var e := state.get_empire(empire_id)
	if not e.is_ai():
		state.add_chronicle("Une %s quitte le Vivarium de %s pour rejoindre la flotte. Les mécaniciens ne savent pas trop où mettre le fourrage." % [
				String(GameData.ship(unit).get("label", unit)).to_lower(), state.galaxy.systems[sid].system_name], Espionage.private_to(state, [empire_id]))
	return f


# --- Sauvegarde -------------------------------------------------------------------------------------

static func to_dict(state: GameState) -> Dictionary:
	var out := {}
	var bs: Dictionary = state.fauna.get("beasts", {})
	if not bs.is_empty():
		var l := []
		var keys := bs.keys()
		keys.sort()
		for k in keys:
			var arr := []
			for b: Dictionary in bs[k]:
				arr.append([String(b["sp"]), int(b["born"])])
			l.append([int(k), arr])
		out["beasts"] = l
	var nets: Dictionary = state.fauna.get("nets", {})
	if not nets.is_empty():
		var n := []
		var keys := nets.keys()
		keys.sort()
		for k in keys:
			n.append([int(k), int(nets[k][0]), int(nets[k][1])])
		out["nets"] = n
	return out


static func from_dict(state: GameState, d: Dictionary) -> void:
	state.fauna.erase("beasts")
	state.fauna.erase("nets")
	if d.has("beasts"):
		var bs := {}
		for p: Array in d["beasts"]:
			var arr := []
			for b: Array in p[1]:
				arr.append({"sp": String(b[0]), "born": int(b[1])})
			bs[int(p[0])] = arr
		state.fauna["beasts"] = bs
	if d.has("nets"):
		var nets := {}
		for p: Array in d["nets"]:
			nets[int(p[0])] = [int(p[1]), int(p[2])]
		state.fauna["nets"] = nets
