class_name PeopleHulls
extends RefCounted
## Coques de peuple (étude « Les chantiers des peuples », 2026-11-18) : les règles des modules intégrés
## qui font une chose qu'aucun module commun ne fait. Chaque règle est un drapeau de module
## (data/designs.json) recopié sur la classe ou le modèle (Designs.FLAGS) ; ce fichier les applique.
##
## Les coques elles-mêmes sont des données : une coque de peuple demande une couche d'espèce
## ("requires"."species" : archétype, gouvernement, credo, trait, registre, origine), jamais un peuple,
## donc un peuple créé dans l'éditeur ou un futur peuple les obtient par ses choix (catalogue ouvert).
##
## Drapeaux :
## - concord : une flotte qui n'en compte que de tels entre chez un empire en paix sans droit de passage ;
## - larvae : après une bataille gagnée, un vaisseau perdu sur deux repousse dans la flotte ;
## - linked : les dégâts reçus par les vaisseaux reliés d'une flotte se partagent entre eux ;
## - predictive : la flotte tire avant l'ennemi (les tireurs qu'elle abat ce jour-là ne tirent pas) ;
## - broadside : l'artillerie tire aussi au contact (phase courte) ;
## - boarding : en phase courte, abordage d'un petit vaisseau ennemi très abîmé, qui change de camp ;
## - wreck_discount : 60 % de matériaux en moins dans un système qui a un cimetière d'épaves ;
## - privateer : la flotte qui bloque une route commerciale ennemie rançonne les convois ;
## - phased : la phase longue ne touche pas le vaisseau ;
## - echo_song : un survivant de bataille rapporte des Échos ;
## - cold_blood : autonomie doublée loin du ravitaillement ;
## - embassy : stationnée chez un empire en paix, influence chaque mois et meilleure opinion ;
## - pulpit : les Martyrs de la flotte frappent une fois et demie plus fort ;
## - brood : un Sporange de guerre gratuit par mois dans la flotte (plafond) ;
## - backup : détruit, le vaisseau se reconstruit à moitié prix et moitié temps ;
## - market : énergie chaque mois selon le commerce du système ;
## - first_salvo : intouchable le premier jour de bataille, salve +50 % ce jour-là ;
## - penitent : détruit, il rend un dixième de leur coque aux autres vaisseaux de sa flotte.

const WRECKS_USED := 5
const WRECK_DISCOUNT_PCT := 60
const LARVAE_PCT := 50
const BOARD_HP_PCT := 30
const BOARD_CHANCE := 50
const EMBASSY_INFLUENCE := 2
const EMBASSY_OPINION := 10
const BROOD_SHIP := "sporange"
const BROOD_MAX := 6
const MARKET_BASE := 3
const MARKET_PER_ROUTE := 2
const ECHOES_PER_SONG := 4
const FIRST_SALVO_PCT := 150
const PULPIT_PCT := 150
const PENITENT_PCT := 10


static func flag(ship_id: String, f: String) -> bool:
	return bool(GameData.ship(ship_id).get(f, false))


static func fleet_flag(fleet: Fleet, f: String) -> bool:
	return Combat._fleet_has_flag(fleet, f)


## Lot 2 de l'arbre (prop. 47) : une coque de peuple gagne une capacité ("upgrade" : tech, flag, text)
## quand l'empire connaît la technologie de sa bande Peuple. Le drapeau gagné vaut celui d'un module.
static func has_flag(state: GameState, f: Fleet, fl: String) -> bool:
	if Combat._fleet_has_flag(f, fl):
		return true
	if state == null or f == null:
		return false
	for s in f.ships:
		var up: Dictionary = Designs.hull(String(GameData.ship(s).get("hull", ""))).get("upgrade", {})
		if String(up.get("flag", "")) == fl and Research.knows(state, f.owner, String(up["tech"])):
			return true
	return false


## Coques de peuple qu'améliore une technologie (pour l'arbre et le Codex).
static func upgrades_of(tid: String) -> Array[String]:
	var out: Array[String] = []
	for hid in Designs.hull_ids():
		if String(Designs.hull(hid).get("upgrade", {}).get("tech", "")) == tid:
			out.append(hid)
	return out


## Coque de peuple ? (rubrique à part dans le Chantier)
static func is_people_hull(hull_id: String) -> bool:
	return bool(Designs.hull(hull_id).get("people", false)) or Designs.hull(hull_id).get("requires", {}).has("species")


## La couche qui ouvre une coque à un peuple, lisible (« trait Navigateurs »).
static func opened_by(hull_id: String) -> String:
	var req: Dictionary = Designs.hull(hull_id).get("requires", {}).get("species", {})
	var parts := PackedStringArray()
	var names := {"archetype": "archétype", "gouvernement": "gouvernement", "credo": "credo", "traits": "trait", "registre": "registre", "origine": "origine"}
	for layer in req:
		var vals := PackedStringArray()
		for v in req[layer]:
			vals.append(_layer_label(String(layer), String(v)))
		parts.append("%s %s" % [String(names.get(layer, layer)), " ou ".join(vals)])
	return ", ".join(parts)


static func _layer_label(layer: String, v: String) -> String:
	if layer == "registre":
		return v
	var key := "traits" if layer == "traits" else layer
	var table: Variant = GameData.species_parts().get(key, {})
	if table is Dictionary and (table as Dictionary).has(v):
		return String(table[v].get("label", v)) if table[v] is Dictionary else v
	if table is Array:
		for it in table:
			if it is Dictionary and String(it.get("id", "")) == v:
				return String(it.get("label", v))
	return v


# --- Frontières -----------------------------------------------------------------------------------

## Pavillon de concorde : une flotte faite seulement de tels vaisseaux entre chez un empire en paix.
static func concord_right(state: GameState, f: Fleet, o: int) -> bool:
	if f.ships.is_empty() or Combat.at_war(state, f.owner, o):
		return false
	for s in f.ships:
		if not flag(s, "concord"):
			return false
	return true


# --- Chantier : coût -------------------------------------------------------------------------------

## Coût ajusté au lieu de construction : Bricolage (épaves) et Noyau de sauvegarde (moitié prix).
@warning_ignore("integer_division")
## Flotte-ville II (arbre, restes des lots 4-5) : les batteries de la capitale mobile (100 + city_battery_pct).
static func city_battery_pct(state: GameState, empire_id: int, ship_id: String) -> int:
	if not FactionTraits.is_capital_ship(ship_id):
		return 100
	return 100 + Research.fx_int(state, empire_id, "city_battery_pct")


## Flotte-ville III : le chantier embarqué. Vrai si la flotte-ville campe dans ce système et que l'empire
## connaît le chantier (city_yard) : le campement vaut un chantier ami.
static func city_yard(state: GameState, empire_id: int, system_id: int) -> bool:
	if Research.fx_int(state, empire_id, "city_yard") <= 0:
		return false
	return FactionTraits.camp_system(state, empire_id) == system_id


static func adjust_cost(state: GameState, empire_id: int, ship_id: String, planet_id: int, cost: Dictionary) -> Dictionary:
	var out := cost
	if planet_id >= 0 and city_yard(state, empire_id, state.galaxy.get_planet(planet_id).system_id):
		out = Research.scaled_amounts(out, -Research.fx_int(state, empire_id, "city_yard"))
	if planet_id >= 0 and flag(ship_id, "wreck_discount") and wrecks_ok(state, planet_id):
		out = out.duplicate()
		out["materials"] = int(out.get("materials", 0)) * (100 - WRECK_DISCOUNT_PCT) / 100
	if has_backup(state, empire_id, ship_id):
		out = out.duplicate()
		for r in out:
			out[r] = int(out[r]) / 2
	return out


static func wrecks_ok(state: GameState, planet_id: int) -> bool:
	var p = state.galaxy.get_planet(planet_id)
	if p == null:
		return false
	if int(state.battle_wrecks.get(int(p.system_id), 0)) >= WRECKS_USED:
		return true
	return CaptureLore.field(state, int(p.system_id)).size() >= WRECKS_USED  # champ d'épaves (prises de guerre, prop. 37)


static func has_backup(state: GameState, empire_id: int, ship_id: String) -> bool:
	var hid := String(GameData.ship(ship_id).get("hull", ""))
	return hid != "" and String(_backups(state).get(str(empire_id), "")) == hid


static func _backups(state: GameState) -> Dictionary:
	if not state.people_hulls.has("backup"):
		state.people_hulls["backup"] = {}
	return state.people_hulls["backup"]


## Mise en chantier : les épaves servent, la sauvegarde est consommée, la durée est divisée par deux.
@warning_ignore("integer_division")
static func on_build(state: GameState, empire_id: int, planet_id: int, ship_id: String, c: Colony) -> void:
	if flag(ship_id, "wreck_discount") and wrecks_ok(state, planet_id):
		var sid := int(state.galaxy.get_planet(planet_id).system_id)
		if int(state.battle_wrecks.get(sid, 0)) >= WRECKS_USED:
			state.battle_wrecks[sid] = int(state.battle_wrecks[sid]) - WRECKS_USED
			if int(state.battle_wrecks[sid]) <= 0:
				state.battle_wrecks.erase(sid)
		else:
			var fl := CaptureLore.field(state, sid)
			for _k in WRECKS_USED:
				fl.pop_front()
	if has_backup(state, empire_id, ship_id):
		_backups(state).erase(str(empire_id))
		c.ship_days = maxi(1, c.ship_days / 2)
		if _backups(state).is_empty():
			state.people_hulls.erase("backup")


# --- Bataille ---------------------------------------------------------------------------------------

## Le tir sur ce vaisseau ne porte pas (Déphasage en phase longue, Voile abyssal le premier jour).
static func untouchable(ship_id: String, phase: int, day: int) -> bool:
	if phase == 0 and flag(ship_id, "phased"):
		return true
	return day == 1 and flag(ship_id, "first_salvo")


## Phase dont l'arme lit l'efficacité : la Bordée prête la phase moyenne à l'artillerie au contact.
static func shot_phase(ship_id: String, family: String, phase: int) -> int:
	if phase >= 2 and Combat.weapon_eff(family, phase) <= 0 and family == "artillery" and flag(ship_id, "broadside"):
		return 1
	return phase


## Bonus du tir (en %) : Voile abyssal le premier jour, Chaire de proue pour les Martyrs.
static func shot_pct(f: Fleet, ship_id: String, family: String, day: int) -> int:
	var pct := 100
	if day == 1 and flag(ship_id, "first_salvo"):
		pct = pct * FIRST_SALVO_PCT / 100
	if family == "martyr" and fleet_flag(f, "pulpit"):
		pct = pct * PULPIT_PCT / 100
	return pct


## Calcul prédictif : retire les tirs des vaisseaux que les flottes prédictives abattent ce jour-là.
## shots : [[clé tireur Vector2i, clé cible Vector2i, dégâts]...] ; renvoie le nouveau cumul par cible.
static func predictive(fighters: Array[Fleet], shots: Array, pending: Dictionary) -> Dictionary:
	var pred := {}
	for f in fighters:
		if fleet_flag(f, "predictive"):
			pred[f.id] = true
	if pred.is_empty():
		return pending
	var first := {}
	for s in shots:
		if pred.has(int((s[0] as Vector2i).x)):
			first[s[1]] = int(first.get(s[1], 0)) + int(s[2])
	var dead := {}
	var by_id := {}
	for f in fighters:
		by_id[f.id] = f
	for key in first:
		var k: Vector2i = key
		var f: Fleet = by_id.get(k.x)
		if f != null and k.y < f.hp.size() and int(f.hp[k.y]) - int(first[key]) <= 0:
			dead[key] = true
	if dead.is_empty():
		return pending
	var out := {}
	for s in shots:
		var shooter: Vector2i = s[0]
		if dead.has(shooter) and not pred.has(shooter.x):
			continue
		out[s[1]] = int(out.get(s[1], 0)) + int(s[2])
	# Les dégâts hors tirs (charges des martyrs ajoutées ensuite) ne passent pas par ici.
	return out


## Lien de noosphère : dans chaque flotte, les dégâts des vaisseaux reliés sont mis en commun.
@warning_ignore("integer_division")
static func share_linked(fighters: Array[Fleet], pending: Dictionary) -> void:
	for f in fighters:
		var linked: Array[int] = []
		var total := 0
		for i in f.ships.size():
			if flag(f.ships[i], "linked"):
				linked.append(i)
				total += int(pending.get(Vector2i(f.id, i), 0))
		if linked.size() < 2 or total <= 0:
			continue
		var each := total / linked.size()
		var rest := total - each * linked.size()
		for i in linked:
			var d := each + (1 if rest > 0 else 0)
			rest -= 1
			if d > 0:
				pending[Vector2i(f.id, i)] = d
			else:
				pending.erase(Vector2i(f.id, i))


## Éperon d'abordage, en phase courte : chaque flotte qui aborde prend au plus un petit vaisseau ennemi
## très abîmé par jour. Renvoie les prises [[flotte preneuse, classe]...].
@warning_ignore("integer_division")
static func boarding(state: GameState, fighters: Array[Fleet], phase: int) -> Array:
	var out: Array = []
	if phase < 2:
		return out
	for f in fighters:
		if f.ships.is_empty() or not fleet_flag(f, "boarding") or f.troops <= 0:
			continue
		if state.rng.randi_range(0, 99) >= BOARD_CHANCE:
			continue
		for g in fighters:
			if g == f or g.ships.is_empty() or not Combat.hostile_fleets(state, f, g):
				continue
			var got := -1
			for i in g.ships.size():
				var sid := g.ships[i]
				if Combat.ship_size(sid) != "small" or Combat.ship_size(sid) == "" or not Combat.is_military(sid):
					continue
				if int(g.hp[i]) * 100 <= Fleet.max_hp_of(sid) * BOARD_HP_PCT and int(g.hp[i]) > 0:
					got = i
					break
			if got < 0 or g.ships.size() < 2:
				continue  # on ne vide pas une flotte par abordage
			var cls := g.ships[got]
			var hp := int(g.hp[got])
			g.remove_at(got)
			f.add_ship(cls, hp)
			f.troops = maxi(0, f.troops - 2)
			out.append([f, cls, g.owner])
			break
	return out


## Fin de bataille : larves (vainqueur seulement), chants d'écho (survivants).
@warning_ignore("integer_division")
static func after_battle(state: GameState, sid: int, sides: Array, winner: int) -> void:
	var survivors := Fleets.fleets_at(state, sid)
	for s: Dictionary in sides:
		var eid := int(s["empire"])
		var mine: Fleet = null
		for f: Fleet in survivors:
			if f.owner == eid and not f.ships.is_empty():
				mine = f
				break
		if mine == null:
			continue
		if eid == winner:
			var lost: Dictionary = s.get("lost", {})
			var keys := lost.keys()
			keys.sort()
			for cls in keys:
				if flag(String(cls), "larvae"):
					for _i in int(lost[cls]) * LARVAE_PCT / 100:
						mine.add_ship(String(cls))
		var e := state.get_empire(eid)
		if e != null and Echoes.has(e.faction()):
			var songs := 0
			for f: Fleet in survivors:
				if f.owner == eid:
					for sh in f.ships:
						if flag(sh, "echo_song"):
							songs += 1
			if songs > 0:
				e.echoes = mini(int(e.faction()["echoes"].get("max", 100)), e.echoes + songs * ECHOES_PER_SONG)


## Un vaisseau va être retiré de la flotte (détruit) : la Noosphère-mère garde sa sauvegarde, la Nef de
## pénitence relève les autres vaisseaux de sa flotte.
@warning_ignore("integer_division")
static func on_ship_lost(state: GameState, f: Fleet, i: int) -> void:
	var ship_id := f.ships[i]
	if f.owner >= 0 and flag(ship_id, "backup"):
		var hid := String(GameData.ship(ship_id).get("hull", ""))
		if hid != "":
			_backups(state)[str(f.owner)] = hid
	if flag(ship_id, "penitent"):
		for k in f.ships.size():
			if k != i and int(f.hp[k]) > 0:
				var mx := Fleet.max_hp_of(f.ships[k])
				f.hp[k] = mini(mx, int(f.hp[k]) + mx * PENITENT_PCT / 100)


# --- Chaque mois --------------------------------------------------------------------------------------

static func monthly(state: GameState, added: Array[Dictionary]) -> void:
	for fid in state.sorted_fleet_ids():
		var f: Fleet = state.fleets[fid]
		if f.ships.is_empty() or GameState.is_npc(f.owner):
			continue
		var e := state.get_empire(f.owner)
		if e == null or e.eliminated:
			continue
		if fleet_flag(f, "brood") and not state.battles.has(f.system_id) and f.count(BROOD_SHIP) < BROOD_MAX:
			f.add_ship(BROOD_SHIP)
		if fleet_flag(f, "market"):
			e.resources["energy"] = int(e.resources.get("energy", 0)) + market_income(state, f.system_id)
		if fleet_flag(f, "embassy") and embassy_host(state, f) >= 0:
			e.resources["influence"] = int(e.resources.get("influence", 0)) + EMBASSY_INFLUENCE
	if added.is_empty():
		pass


## Marché flottant : énergie du mois dans ce système.
static func market_income(state: GameState, sid: int) -> int:
	var n := 0
	for r: Dictionary in state.trade.get("routes", []):
		if (r.get("path", []) as Array).has(sid):
			n += 1
	return MARKET_BASE + MARKET_PER_ROUTE * n


## Empire qui accueille l'Arche (système à lui, en paix), ou -1.
static func embassy_host(state: GameState, f: Fleet) -> int:
	if f.is_moving():
		return -1
	var o := state.system_owner(f.system_id)
	if o < 0 or o == f.owner or GameState.is_npc(o) or Combat.at_war(state, f.owner, o):
		return -1
	return o


## Opinion de a envers b : une Arche de b stationnée chez a. Les arches sont relevées une fois par jour.
static var _emb_key := ""
static var _emb := {}


static func embassy_opinion(state: GameState, a: int, b: int) -> int:
	var key := "%d|%d" % [state.get_instance_id(), state.tick]
	if key != _emb_key:
		_emb_key = key
		_emb = {}
		for fid in state.fleets:
			var f: Fleet = state.fleets[fid]
			if fleet_flag(f, "embassy"):
				var host := embassy_host(state, f)
				if host >= 0:
					_emb["%d>%d" % [f.owner, host]] = true
	return EMBASSY_OPINION if _emb.has("%d>%d" % [b, a]) else 0


# --- Commerce ------------------------------------------------------------------------------------------

## Soute franche : une flotte de corsaires de by stationnée sur ce système bloque et rançonne.
static func privateer_at(state: GameState, by: int, sid: int) -> bool:
	for f in Fleets.fleets_at(state, sid, by):
		if fleet_flag(f, "privateer"):
			return true
	return false


# --- Sauvegarde ----------------------------------------------------------------------------------------

static func to_dict(state: GameState) -> Dictionary:
	return state.people_hulls.duplicate(true)


static func from_dict(state: GameState, d: Variant) -> void:
	state.people_hulls = (d as Dictionary).duplicate(true) if d is Dictionary else {}
