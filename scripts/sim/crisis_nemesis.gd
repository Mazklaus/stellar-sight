class_name CrisisNemesis
extends RefCounted
## Crises de fin de partie, lot 3, prop. 23 : « Devenir la crise » (voie de l'Ambition démesurée).
## Option de nouvelle partie « crisis_nemesis » (avec les crises). Un seul empire à la fois prend la voie
## (commande crisis_ambition). Sa Menace monte par ses conquêtes, ses guerres, ses victoires, ses
## atrocités et ses technologies interdites ; trois paliers donnent des effets cumulés (effects). Le
## dernier est un point de non-retour : tous les empires lui déclarent la guerre et ne peuvent plus faire
## la paix avec lui, leurs flottes le frappent plus fort, et il doit achever son grand œuvre (commande
## crisis_oeuvre) pour gagner (victoire « fleau »). Perdre sa capitale brise la voie, pour toujours.
## État : state.crisis["nem"] = {"who", "menace", "tier", "fund", "need", "since", "broken": [empires]}.


static func data() -> Dictionary:
	return Crisis.data().get("nemesis", {})


static func enabled(state: GameState) -> bool:
	return Crisis.enabled(state) and state.crisis.has("nem")


static func nem(state: GameState) -> Dictionary:
	return state.crisis.get("nem", {})


static func who(state: GameState) -> int:
	return int(nem(state).get("who", -1)) if enabled(state) else -1


static func tier(state: GameState) -> int:
	return int(nem(state).get("tier", 0)) if enabled(state) else 0


static func tiers() -> Array:
	return data().get("tiers", [])


static func tier_def(n: int) -> Dictionary:
	var t := tiers()
	return t[n - 1] if n >= 1 and n <= t.size() else {}


## Le Fléau des étoiles (dernier palier atteint) ?
static func is_scourge(state: GameState, eid: int) -> bool:
	return eid >= 0 and who(state) == eid and tier(state) >= tiers().size()


static func setup(state: GameState, on: bool) -> void:
	if on and Crisis.enabled(state):
		state.crisis["nem"] = {"who": -1, "menace": 0, "tier": 0, "fund": 0, "need": 0, "since": 0, "broken": []}


# --- Prendre la voie --------------------------------------------------------------------------------

static func check_ambition(state: GameState, eid: int) -> String:
	if not enabled(state):
		return "l'option « Devenir la crise » n'est pas en jeu"
	var e := state.get_empire(eid)
	if e == null or e.eliminated or GameState.is_npc(eid):
		return "empire inconnu"
	if state.tick < int(data().get("from_day", 3600)):
		return "pas avant %s" % GameCalendar.date_string(int(data().get("from_day", 3600)))
	if who(state) >= 0:
		return "%s a déjà pris cette voie" % state.get_empire(who(state)).short_name() if who(state) != eid else "vous avez déjà pris cette voie"
	if (nem(state)["broken"] as Array).has(eid):
		return "votre ambition a été brisée"
	if Crisis.pacted(state, eid):
		return "vous avez pactisé avec la crise"
	return ""


static func take(state: GameState, eid: int, added: Array[Dictionary]) -> void:
	var n := nem(state)
	n["who"] = eid
	n["menace"] = 0
	n["tier"] = 0
	n["fund"] = 0
	n["since"] = state.tick
	added.append(state.add_chronicle("%s prend la voie de l'Ambition démesurée. Les autres empires ne le savent pas encore ; ils l'apprendront à ses actes." % state.get_empire(eid).display_name(),
			Espionage.private_to(state, [eid])))


# --- La Menace --------------------------------------------------------------------------------------

## Research.count_stat : conquêtes, guerres, victoires.
static func on_stat(state: GameState, eid: int, key: String, n: int) -> void:
	if who(state) == eid and data().get("gain", {}).has(key):
		gain(state, eid, int(data()["gain"][key]) * n)


static func gain(state: GameState, eid: int, pts: int) -> void:
	if who(state) != eid or pts <= 0:
		return
	var nm := nem(state)
	nm["menace"] = int(nm["menace"]) + pts
	var t := tiers()
	while int(nm["tier"]) < t.size() and int(nm["menace"]) >= int(t[int(nm["tier"])]["at"]):
		nm["tier"] = int(nm["tier"]) + 1
		_tier_up(state, eid, int(nm["tier"]))


static func _tier_up(state: GameState, eid: int, n: int) -> void:
	var td := tier_def(n)
	var e := state.get_empire(eid)
	var od: Dictionary = data().get("oeuvre", {})
	var text := String(td.get("text", "")).replace("{empire}", e.display_name()).replace("{oeuvre}", String(od.get("name", "son grand œuvre")))
	state.add_chronicle("%s : %s" % [String(td.get("label", "Menace")), text])
	Relics.touch(state)
	if n >= 2:
		for o in state.empires:
			if not o.eliminated and o.id != eid:
				Diplomacy.remember(state, o.id, eid, "nemesis")
	if bool(td.get("final", false)):
		var nm := nem(state)
		var others := 0
		for o in state.empires:
			if o.eliminated or o.id == eid:
				continue
			others += 1
			if not Combat.at_war(state, o.id, eid):
				Combat.start_war(state, o.id, eid)
		nm["need"] = maxi(int(od.get("min", 2400)), others * int(od.get("need_per_empire", 1200)))
		for o in state.empires:
			o.path_cache.clear()


# --- Le grand œuvre ---------------------------------------------------------------------------------

static func check_oeuvre(state: GameState, eid: int, res: String) -> String:
	if not is_scourge(state, eid):
		return "il faut être le Fléau des étoiles"
	if res != "energy" and res != "materials":
		return "ressource inconnue"
	var e := state.get_empire(eid)
	if int(e.resources.get(res, 0)) < int(data()["oeuvre"].get("pack", 200)):
		return "pas assez de %s" % GameData.resource_label(res).to_lower()
	return ""


static func fund(state: GameState, eid: int, res: String, added: Array[Dictionary]) -> void:
	var pack := int(data()["oeuvre"].get("pack", 200))
	var e := state.get_empire(eid)
	e.resources[res] = int(e.resources.get(res, 0)) - pack
	var nm := nem(state)
	nm["fund"] = int(nm["fund"]) + pack
	if int(nm["fund"]) >= int(nm["need"]) and state.winner.is_empty() and state.tick >= Victory.not_before(state):
		state.winner = {"empire": eid, "victory": "fleau", "tick": state.tick, "allies": []}
		added.append(state.add_chronicle(Victory.chronicle_text("fleau", e, [], state)))


static func pct(state: GameState) -> int:
	var nm := nem(state)
	@warning_ignore("integer_division")
	return mini(100, int(nm.get("fund", 0)) * 100 / maxi(1, int(nm.get("need", 1))))


# --- Chaque jour ------------------------------------------------------------------------------------

## La voie se brise si l'ambitieux perd sa capitale (ou disparaît).
static func daily(state: GameState, added: Array[Dictionary]) -> void:
	var eid := who(state)
	if eid < 0:
		return
	var e := state.get_empire(eid)
	var col: Colony = state.colonies.get(e.capital_planet) if e != null else null
	if e != null and not e.eliminated and col != null and col.owner == eid:
		return
	var nm := nem(state)
	(nm["broken"] as Array).append(eid)
	var was := int(nm["tier"])
	nm["who"] = -1
	nm["menace"] = 0
	nm["tier"] = 0
	nm["fund"] = 0
	nm["need"] = 0
	Relics.touch(state)
	if was >= 1 and e != null:
		added.append(state.add_chronicle(String(data().get("broken_text", "{empire} : l'ambition est brisée.")).replace("{empire}", e.display_name())))


# --- Effets -----------------------------------------------------------------------------------------

## Effets cumulés des paliers atteints (Research.effects via Crisis.effects).
static func effects(state: GameState, eid: int) -> Dictionary:
	var out := {}
	if who(state) != eid:
		return out
	for n in range(1, tier(state) + 1):
		Research._merge(out, tier_def(n).get("fx", {}))
	return out


## Bonus des autres empires contre les flottes du Fléau dans ce système.
static func damage_pct(state: GameState, f: Fleet, sid: int) -> int:
	var w := who(state)
	if w < 0 or f.owner == w or GameState.is_npc(f.owner) or not is_scourge(state, w):
		return 0
	for g in Fleets.fleets_at(state, sid, w):
		if not g.ships.is_empty():
			return int(data().get("foes_damage_pct", 10))
	return 0
