class_name ForceOdds
extends RefCounted
## Rapport de force avant d'engager (bêta-test, tâche 3.2) : la flotte choisie, plus vos flottes déjà
## à l'arrêt sur place, contre ce que vous voyez d'hostile dans le système (flottes en guerre avec
## vous, bêtes et gardiens hostiles, défenses fixes d'un ennemi). Une estimation sur la puissance
## affichée partout : la tactique, les portées et le terrain peuvent la démentir.
## Lecture seule, sûre pour l'affichage.

## Seuils du verdict, rapport vos forces / les siennes en % (du plus favorable au moins favorable).
const VERDICTS := [[150, "victoire probable"], [110, "avantage"], [91, "issue incertaine"], [66, "désavantage"], [0, "défaite probable"]]


## Verdict en mots pour mine contre foe.
static func verdict(mine: int, foe: int) -> String:
	if foe <= 0:
		return "personne en face"
	@warning_ignore("integer_division")
	var pct := mine * 100 / foe
	for v: Array in VERDICTS:
		if pct >= int(v[0]):
			return String(v[1])
	return String(VERDICTS[-1][1])


## Ce que la flotte f trouverait en face dans le système sid, vu par viewer :
## {"mine", "foe", "lo", "hi", "verdict", "fleets", "defense"} ; {} si rien d'hostile n'y est visible.
## lo/hi : fourchette quand des bêtes ou des gardiens en sont (jamais leur force exacte) ; foe = milieu.
## live : tenir pour vu sans calculer la vision (tests).
static func at(state: GameState, viewer: int, f: Fleet, sid: int, live := false) -> Dictionary:
	if f == null or state.galaxy.get_system(sid) == null:
		return {}
	var seen := {} if live else Fleets.visible_systems(state, viewer)
	if not live and not seen.has(sid):
		return {}
	var lo := 0
	var hi := 0
	var n := 0
	for g in Fleets.fleets_at(state, sid):
		if g.owner == viewer or g.id == f.id:
			continue
		if not live and not Fleets.fleet_visible(state, viewer, g, seen):
			continue
		if not Combat.hostile_fleets(state, f, g):
			continue
		n += 1
		if g.owner == GameState.FAUNA_ID:
			var pr := Fauna.power_range(state, viewer, g)
			lo += int(pr[0])
			hi += int(pr[1])
		else:
			var p := Combat.fleet_power(g)
			lo += p
			hi += p
	var def := 0
	var owner := state.system_owner(sid)
	if owner >= 0 and owner != viewer and Combat.at_war(state, viewer, owner) and Defenses.enabled(state):
		def = Defenses.power(state, sid)
		lo += def
		hi += def
	if hi <= 0:
		return {}
	var mine := Combat.fleet_power(f)
	for g in Fleets.fleets_at(state, sid, viewer):
		if g.id != f.id:
			mine += Combat.fleet_power(g)
	@warning_ignore("integer_division")
	var foe := (lo + hi) / 2
	return {"mine": mine, "foe": foe, "lo": lo, "hi": hi, "verdict": verdict(mine, foe), "fleets": n, "defense": def}


## « Rapport de force : 27 contre 60, défaite probable. »
static func line(o: Dictionary) -> String:
	if o.is_empty():
		return ""
	var foe := str(int(o["foe"])) if int(o["lo"]) == int(o["hi"]) else "%d à %d" % [int(o["lo"]), int(o["hi"])]
	return "Rapport de force : %d contre %s, %s." % [int(o["mine"]), foe, String(o["verdict"])]


## Couleur du verdict pour l'interface : 1 favorable, 0 incertain, -1 défavorable.
static func tone(o: Dictionary) -> int:
	var v := String(o.get("verdict", ""))
	if v == "victoire probable" or v == "avantage":
		return 1
	if v == "issue incertaine" or v == "":
		return 0
	return -1


## Forces armées d'un empire (toutes ses flottes), pour la diplomatie.
static func empire_power(state: GameState, eid: int) -> int:
	var n := 0
	for f: Fleet in state.fleets.values():
		if f.owner == eid:
			n += Combat.fleet_power(f)
	return n


## Comparaison des forces armées en diplomatie : vos forces exactes, les siennes arrondies (vos
## états-majors estiment, ils ne comptent pas).
static func empire_line(state: GameState, viewer: int, other: int) -> String:
	var mine := empire_power(state, viewer)
	var his := empire_power(state, other)
	var shown := int(round(his / 50.0)) * 50 if his >= 50 else his
	var word := "comparables"
	if his * 100 > mine * 130:
		word = "supérieures aux vôtres"
	elif his * 130 < mine * 100:
		word = "inférieures aux vôtres"
	return "Forces armées : les vôtres %d, les siennes environ %d (%s)" % [mine, shown, word]
