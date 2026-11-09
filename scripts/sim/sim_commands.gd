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
			Economy.pay(e, Economy.claim_cost(kind))
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
			Economy.pay(e, b.get("cost", {}))
			c.construction = String(cmd["building"])
			c.construction_days = int(b["days"])
