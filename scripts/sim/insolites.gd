class_name Insolites
extends RefCounted
## Les peuples insolites (étude « Les 15 peuples insolites et le 9e peuple », validée le 2026-11-19 ;
## data/insolites.json). Lot 1 : les peuples sans monde, qui vivent en mouvement.
##   - Flotte-Exode des Derniers (InsExode) : quatre Nefs-cités en fuite, les Traqueurs, l'Espoir.
##   - Cirque Stellaire Zambalù (InsZambalu) : Troupes, représentations, Fan-clubs, Grand Numéro.
##   - Orbe-Monde Halcyre (InsHalcyre) : une planète qui marche, mange des lunes et s'allume en étoile.
##   - Hardes de Kraal (InsKraal) : des vaisseaux vivants qui naissent, vieillissent et broutent.
## Chaque peuple porte un champ de faction "nomad" {kind, ship, count}, posé par une brique d'espèce
## (data/species_parts.json) : un peuple créé dans l'éditeur avec la même brique suit les mêmes règles.
##
## Socle commun (props 8 et 9) : la population portée (sur une flotte, une planète-être, une harde),
## qui compte pour la part de population galactique, le score et les victoires ; les implants (un peuple
## présent sur la planète d'un autre empire, que l'hôte peut purger) ; le chantier embarqué des peuples
## sans planète.
##
## État : state.insolites = {} sans peuple insolite dans la partie, sinon
##   {"emp": {"eid": {"k": sorte, "pop", "sp": {peuple: n}, "yard": {"ship", "left"}, … (selon la sorte)}},
##    "implants": {"pid": {"k", "o": propriétaire, "t": jour}}, "eaten": {"pid": 1},
##    "stage": {"sid": jour de fin du bonus de spectacle}, "truce": {"a:b": jour de fin}, "numero": {…}}.

const MONTH := 30
const OFFSET := 11  # bilan mensuel des peuples insolites (décalé des autres piliers)


static func data() -> Dictionary:
	return GameData.insolites()


static func cfg(section: String) -> Dictionary:
	return data().get(section, {})


static func c_int(section: String, key: String, def := 0) -> int:
	return int(cfg(section).get(key, def))


# --- Qui est insolite ? --------------------------------------------------------------------------

## Sorte de peuple sans monde d'une fiche ("" pour un peuple classique).
static func kind_of_faction(f: Dictionary) -> String:
	return String(f.get("nomad", {}).get("kind", ""))


static func kind(state: GameState, eid: int) -> String:
	var e := state.get_empire(eid)
	if e == null or e.is_npc():
		return ""
	return kind_of_faction(e.faction())


static func is_nomad(state: GameState, eid: int) -> bool:
	return kind(state, eid) != ""


static func active(state: GameState) -> bool:
	return not state.insolites.is_empty()


static func emp(state: GameState, eid: int) -> Dictionary:
	if state.insolites.is_empty():
		return {}
	return (state.insolites.get("emp", {}) as Dictionary).get(str(eid), {})


static func sub(state: GameState, key: String) -> Dictionary:
	if not state.insolites.has(key):
		state.insolites[key] = {}
	return state.insolites[key]


## Empires insolites vivants de la partie, par identifiant croissant.
static func nomad_ids(state: GameState) -> Array[int]:
	var out: Array[int] = []
	if state.insolites.is_empty():
		return out
	for e in state.empires:
		if not e.eliminated and kind_of_faction(e.faction()) != "":
			out.append(e.id)
	return out


# --- Mise en place --------------------------------------------------------------------------------

## Fondation d'un peuple sans monde (GameState._setup_empires) : pas de colonie natale ; sa cité mobile
## (ou sa harde) apparaît dans le système de départ, avec ses vaisseaux de départ.
static func found(state: GameState, e: Empire, sid: int) -> void:
	var f := e.faction()
	var k := kind_of_faction(f)
	var ed := {"k": k, "pop": 0, "sp": {}}
	sub(state, "emp")[str(e.id)] = ed
	var nm: Dictionary = f["nomad"]
	var ship := String(nm.get("ship", ""))
	match k:
		"kraal":
			InsKraal.found(state, e, sid, ed)
		_:
			var n := maxi(1, int(nm.get("count", 1)))
			var city := state.spawn_ship(e.id, ship, sid)
			for _i in range(1, n):
				city.add_ship(ship, -1, Research.mark_gen(state, e.id))
			city.troops = Combat.max_troops(city, state)
			city.fleet_name = "%s des %s" % [String(GameData.ship(ship).get("plural" if n > 1 else "label", ship)), e.short_name()]
			match k:
				"exode":
					InsExode.found(state, e, sid, ed)
				"zambalu":
					InsZambalu.found(state, e, sid, ed)
				"halcyre":
					InsHalcyre.found(state, e, sid, ed)
	for ship_id in FactionTraits.start_ships(e.faction_id):
		state.spawn_ship(e.id, String(ship_id), sid)


static func worth_saving(state: GameState) -> bool:
	return not state.insolites.is_empty()


static func to_dict(state: GameState) -> Dictionary:
	return state.insolites.duplicate(true)


static func from_dict(state: GameState, d: Dictionary) -> void:
	state.insolites = GameData._to_ints(d.duplicate(true)) if not d.is_empty() else {}


# --- Population portée (prop. 8) -------------------------------------------------------------------

## Population portée par l'empire (hors colonies) : celle des nefs, du Chapiteau, la Masse de l'Orbe,
## les Kraal comptés par âge. 0 pour un peuple classique.
static func carried_pop(state: GameState, eid: int) -> int:
	var ed := emp(state, eid)
	if ed.is_empty():
		return 0
	var e := state.get_empire(eid)
	if e == null or e.eliminated:
		return 0
	if String(ed["k"]) == "kraal":
		return InsKraal.herd_pop(state, eid)
	return int(ed.get("pop", 0))


## Population portée de tous les empires : [total galactique, celle de l'empire].
static func carried_share(state: GameState, eid: int) -> Array[int]:
	var total := 0
	var mine := 0
	for id in nomad_ids(state):
		var n := carried_pop(state, id)
		total += n
		if id == eid:
			mine += n
	return [total, mine]


## Points de score de la population portée (data/victories.json, score.pop).
static func score(state: GameState, eid: int, per_pop: int) -> int:
	@warning_ignore("integer_division")
	return carried_pop(state, eid) * per_pop * c_int("carried", "score_pct", 100) / 100


static func add_species(ed: Dictionary, fid: String, n: int) -> void:
	if n == 0 or fid == "":
		return
	var sp: Dictionary = ed.get("sp", {})
	sp[fid] = maxi(0, int(sp.get(fid, 0)) + n)
	if int(sp[fid]) == 0:
		sp.erase(fid)
	ed["sp"] = sp


## Le peuple garde-t-il la vie sans une seule revendication ? (CombatSystem._eliminations)
static func keeps_alive(state: GameState, eid: int) -> bool:
	var k := kind(state, eid)
	if k == "":
		return false
	if k == "kraal":
		return InsKraal.herd_pop(state, eid) > 0
	return FactionTraits.city_fleet(state, eid) != null


# --- Revenus ------------------------------------------------------------------------------------

## Revenu mensuel brut propre aux peuples sans monde (Economy.empire_income, avant bonus de production).
static func income(state: GameState, eid: int) -> Dictionary:
	if state.insolites.is_empty():
		return {}
	match kind(state, eid):
		"exode":
			return InsExode.income(state, eid)
		"zambalu":
			return InsZambalu.income(state, eid)
		"halcyre":
			return InsHalcyre.income(state, eid)
		"kraal":
			return InsKraal.income(state, eid)
	return {}


static func add_to(into: Dictionary, amounts: Dictionary, times := 1) -> void:
	for r in amounts:
		into[r] = int(into.get(r, 0)) + int(amounts[r]) * times


# --- Implants (prop. 9) -------------------------------------------------------------------------

static func implant_def(k: String) -> Dictionary:
	return (cfg("implants").get("kinds", {}) as Dictionary).get(k, {})


static func implant(state: GameState, pid: int) -> Dictionary:
	if state.insolites.is_empty():
		return {}
	return (state.insolites.get("implants", {}) as Dictionary).get(str(pid), {})


static func implants_of(state: GameState, owner: int) -> Array[int]:
	var out: Array[int] = []
	if state.insolites.is_empty():
		return out
	var im: Dictionary = state.insolites.get("implants", {})
	for k in im:
		if int(im[k]["o"]) == owner:
			out.append(int(k))
	out.sort()
	return out


static func add_implant(state: GameState, pid: int, k: String, owner: int) -> void:
	sub(state, "implants")[str(pid)] = {"k": k, "o": owner, "t": state.tick}


## L'implant est-il visible de cet empire ? (Les implants cachés : lots suivants.)
static func implant_visible(state: GameState, pid: int, eid: int) -> bool:
	var im := implant(state, pid)
	if im.is_empty():
		return false
	if int(im["o"]) == eid or not bool(implant_def(String(im["k"])).get("hidden", false)):
		return true
	var c: Colony = state.colonies.get(pid)
	return c != null and c.owner == eid and int(im.get("seen", 0)) > 0


## Dîmes du mois : chaque implant prend sa part chez l'hôte (dans la limite de ses réserves).
static func _implant_month(state: GameState, added: Array[Dictionary]) -> void:
	var im: Dictionary = state.insolites.get("implants", {})
	var keys := im.keys()
	keys.sort_custom(func(a, b): return int(a) < int(b))
	for key in keys:
		var d: Dictionary = im[key]
		var pid := int(key)
		var c: Colony = state.colonies.get(pid)
		var owner := state.get_empire(int(d["o"]))
		if c == null or not c.is_colony() or owner == null or owner.eliminated or c.owner == owner.id:
			im.erase(key)
			continue
		var host := state.get_empire(c.owner)
		var df := implant_def(String(d["k"]))
		if host == null or host.is_npc():
			continue
		var tithe: Dictionary = (df.get("tithe", {}) as Dictionary).duplicate()
		tithe["energy"] = int(tithe.get("energy", 0)) + c.population * int(df.get("tithe_per_pop", 0))
		for r in tithe:
			var n := mini(int(tithe[r]), maxi(0, int(host.resources.get(r, 0))))
			if n > 0:
				host.resources[r] = int(host.resources.get(r, 0)) - n
				owner.resources[r] = int(owner.resources.get(r, 0)) + n
		var rad := int(df.get("radiance", 0))
		if rad > 0 and not state.culture.is_empty():
			var cum := Culture._m(state, "cum")
			var ck := Culture._k(owner.id, host.id)
			cum[ck] = int(cum.get(ck, 0)) + rad
	if not added.is_empty():
		pass


static func check_purge(state: GameState, eid: int, pid: int) -> String:
	var im := implant(state, pid)
	if im.is_empty():
		return "aucun implant sur cette planète"
	var c: Colony = state.colonies.get(pid)
	if c == null or c.owner != eid:
		return "seul le propriétaire de la planète peut purger un implant"
	if not implant_visible(state, pid, eid):
		return "aucun implant connu sur cette planète"
	var cost: Dictionary = implant_def(String(im["k"])).get("purge_cost", {})
	if not Economy.can_afford(state.get_empire(eid), cost):
		return "ressources insuffisantes (il faut %s)" % GameData.format_amounts(cost)
	return ""


static func purge(state: GameState, eid: int, pid: int, added: Array[Dictionary]) -> void:
	var im := implant(state, pid)
	var df := implant_def(String(im["k"]))
	Economy.pay(state.get_empire(eid), df.get("purge_cost", {}))
	var owner := state.get_empire(int(im["o"]))
	(state.insolites["implants"] as Dictionary).erase(str(pid))
	var sid := state.galaxy.get_planet(pid).system_id
	sub(state, "purged")[str(sid)] = state.tick + int(df.get("purge_stability_days", 0))
	added.append(state.add_chronicle("%s purge le %s de %s sur %s. Les fans pleurent ; certains gardent leurs affiches sous le lit." % [
			state.get_empire(eid).display_name(), String(df.get("label", im["k"])), owner.short_name() if owner else "?",
			state.galaxy.get_planet(pid).display_name(state.galaxy)], Espionage.private_to(state, [eid, int(im["o"])], sid)))


# --- Chantier embarqué ---------------------------------------------------------------------------

static func yard_allowed(state: GameState, eid: int) -> bool:
	var k := kind(state, eid)
	if not (cfg("yard").get("kinds", []) as Array).has(k):
		return false
	return not (k == "exode" and int(emp(state, eid).get("arrived", 0)) > 0)


static func check_build(state: GameState, eid: int, ship_id: String) -> String:
	if not yard_allowed(state, eid):
		return "votre peuple n'a pas de chantier embarqué"
	var e := state.get_empire(eid)
	var cf := FactionTraits.city_fleet(state, eid)
	if cf == null:
		return "il faut la cité mobile pour construire"
	var sd := GameData.ship(ship_id)
	if sd.is_empty():
		return "classe de vaisseau inconnue : %s" % ship_id
	if bool(sd.get("spawn_only", false)) or bool(sd.get("colonizer", false)):
		return "ce vaisseau ne se construit pas dans la cité mobile"
	if not Designs.can_build_id(state, eid, ship_id):
		return "votre peuple ne construit pas de %s" % String(sd.get("plural", ship_id)).to_lower()
	if not Fleets.ship_unlocked(state, eid, ship_id):
		return "technologie requise : %s" % Research.missing_text(state, eid, sd.get("requires_tech", []))
	if String(sd.get("requires", {}).get("building", "")) != "":
		return "ce vaisseau demande un chantier planétaire"
	if not (emp(state, eid).get("yard", {}) as Dictionary).is_empty():
		return "le chantier embarqué est occupé"
	var cost := Fleets.ship_cost(state, eid, ship_id)
	if not Economy.can_afford(e, cost):
		return "ressources insuffisantes (il faut %s)" % GameData.format_amounts(cost)
	return ""


static func build(state: GameState, eid: int, ship_id: String) -> void:
	var e := state.get_empire(eid)
	Economy.pay(e, Fleets.ship_cost(state, eid, ship_id))
	emp(state, eid)["yard"] = {"ship": ship_id, "left": Fleets.ship_days(state, eid, ship_id)}


static func _yard_day(state: GameState, eid: int, ed: Dictionary, added: Array[Dictionary]) -> void:
	var y: Dictionary = ed.get("yard", {})
	if y.is_empty():
		return
	y["left"] = int(y["left"]) - 1
	if int(y["left"]) > 0:
		return
	var cf := FactionTraits.city_fleet(state, eid)
	if cf == null:
		return  # chantier en attente : la cité mobile a disparu
	ed["yard"] = {}
	var f := state.spawn_ship(eid, String(y["ship"]), cf.system_id)
	added.append(state.add_chronicle("%s : un %s sort des soutes de %s." % [state.get_empire(eid).short_name(),
			String(GameData.ship(String(y["ship"])).get("label", y["ship"])), cf.fleet_name], Espionage.private_to(state, [eid], f.system_id)))


# --- Branchements dans les autres règles ------------------------------------------------------------

## Raison qui empêche un traité entre a et b ("" sinon) : l'Avatar d'Halcyre n'a pas visité l'autre.
static func treaty_block(state: GameState, a: int, b: int) -> String:
	if state.insolites.is_empty():
		return ""
	for pair in [[a, b], [b, a]]:
		if kind(state, int(pair[0])) == "halcyre" and not InsHalcyre.visited(state, int(pair[0]), int(pair[1])):
			return "l'Avatar d'Halcyre n'a jamais traversé un système de %s" % state.get_empire(int(pair[1])).short_name()
	return ""


## Trêve du Grand Numéro entre deux empires (Combat.at_war).
static func truce(state: GameState, a: int, b: int) -> bool:
	if state.insolites.is_empty() or not state.insolites.has("truce"):
		return false
	return int((state.insolites["truce"] as Dictionary).get(_pair(a, b), 0)) > state.tick


static func _pair(a: int, b: int) -> String:
	return "%d:%d" % [mini(a, b), maxi(a, b)]


## Raison qui empêche une invasion au sol ("" sinon) : les peuples sans monde ne prennent pas de planète.
static func invade_block(state: GameState, eid: int) -> String:
	if state.insolites.is_empty():
		return ""
	match kind(state, eid):
		"zambalu":
			return "le Cirque ne garde aucune planète : une Troupe escortée fait d'une colonie ennemie un Fan-club (Tournée triomphale)"
		"halcyre":
			return "l'Orbe-Monde ne conquiert pas un monde : il le mange"
		"kraal":
			return "les Kraal ne prennent pas de planète : ils y arrachent des Pilotes"
		"exode":
			if int(emp(state, eid).get("arrived", 0)) == 0:
				return "l'Exode ne prend pas la terre des autres : il cherche la sienne"
	return ""


## Raison qui empêche de revendiquer une planète ("" sinon) : elle a été mangée par l'Orbe-Monde.
static func colony_block(state: GameState, pid: int) -> String:
	if state.insolites.is_empty() or not (state.insolites.get("eaten", {}) as Dictionary).has(str(pid)):
		return ""
	return "l'Orbe-Monde a mangé cette planète : il n'en reste qu'un nuage de cailloux"


static func is_eaten(state: GameState, pid: int) -> bool:
	return not state.insolites.is_empty() and (state.insolites.get("eaten", {}) as Dictionary).has(str(pid))


## Lignes de stabilité d'un système (Stability.parts) : spectacle du Cirque, implant purgé.
static func stability_parts(state: GameState, sid: int, owner: int) -> Array:
	var out := []
	if state.insolites.is_empty():
		return out
	if int((state.insolites.get("stage", {}) as Dictionary).get(str(sid), 0)) > state.tick:
		out.append(["Spectacle du Cirque", c_int("zambalu", "show_stability", 10)])
	if int((state.insolites.get("purged", {}) as Dictionary).get(str(sid), 0)) > state.tick:
		out.append(["Implant purgé", -5])
	if owner < 0:
		return out
	return out


## Bonus de dégâts d'une flotte (CombatSystem) : Pilotes des Kraal, Masse de l'Orbe.
static func damage_pct(state: GameState, f: Fleet) -> int:
	if state.insolites.is_empty():
		return 0
	match kind(state, f.owner):
		"kraal":
			return InsKraal.damage_pct(state, f)
		"halcyre":
			return InsHalcyre.damage_pct(state, f)
	return 0


## Vitesse d'une flotte en % (Fleets.speed) : routes de migration des Kraal.
static func speed_pct(state: GameState, f: Fleet) -> int:
	if state.insolites.is_empty() or kind(state, f.owner) != "kraal":
		return 100
	return InsKraal.speed_pct(state, f)


## Un vaisseau tombe au combat (CombatSystem._apply_damage) : carcasse d'un Kraal dépecée.
static func on_ship_lost(state: GameState, f: Fleet, i: int, b: Dictionary) -> void:
	if state.insolites.is_empty():
		return
	var carcass: Dictionary = GameData.ship(f.ships[i]).get("carcass", {})
	if carcass.is_empty():
		return
	var takers: Array[int] = []
	for s: Dictionary in b.get("sides", []):
		var eid := int(s["empire"])
		if Combat.at_war(state, eid, f.owner) and not GameState.is_npc(eid):
			takers.append(eid)
	takers.sort()
	if takers.is_empty():
		return
	var e := state.get_empire(takers[0])
	if e == null:
		return
	for r in carcass:
		e.resources[r] = int(e.resources.get(r, 0)) + int(carcass[r])


## Les créatures sauvages épargnent-elles cet empire ? (Fauna.hostile : parenté des Kraal.)
static func fauna_kin(state: GameState, eid: int) -> bool:
	return not state.insolites.is_empty() and kind(state, eid) == "kraal"


# --- Chaque jour ----------------------------------------------------------------------------------

static func daily(state: GameState) -> Array[Dictionary]:
	var added: Array[Dictionary] = []
	if state.insolites.is_empty():
		return added
	var month := state.tick % MONTH == OFFSET
	for eid in nomad_ids(state):
		var ed := emp(state, eid)
		if ed.is_empty():
			continue
		_yard_day(state, eid, ed, added)
		match String(ed["k"]):
			"exode":
				InsExode.daily(state, eid, ed, month, added)
			"zambalu":
				InsZambalu.daily(state, eid, ed, month, added)
			"halcyre":
				InsHalcyre.daily(state, eid, ed, month, added)
			"kraal":
				InsKraal.daily(state, eid, ed, month, added)
	InsZambalu.numero_day(state, added)
	if month:
		_implant_month(state, added)
	return added


# --- Ordres des joueurs ---------------------------------------------------------------------------
## Actions (SimCommands.ins_act) : "build" (ship), "settle", "purge" (pid), "delegate", "sentinel" (pid),
## "devour" (pid), "pilot" (fleet).

static func check(state: GameState, eid: int, act: String, d: Dictionary) -> String:
	if state.insolites.is_empty():
		return "aucun peuple insolite dans cette partie"
	var e := state.get_empire(eid)
	if e == null or e.eliminated:
		return "empire inconnu"
	match act:
		"build":
			return check_build(state, eid, String(d.get("ship", "")))
		"settle":
			return InsExode.check_settle(state, eid)
		"purge":
			return check_purge(state, eid, int(d.get("pid", -1)))
		"delegate":
			return InsZambalu.check_delegate(state, eid)
		"sentinel":
			return InsHalcyre.check_sentinel(state, eid, int(d.get("pid", -1)))
		"devour":
			return InsHalcyre.check_devour(state, eid, int(d.get("pid", -1)))
		"pilot":
			return InsKraal.check_pilot(state, eid, int(d.get("fleet", -1)))
	return "action inconnue : %s" % act


static func apply(state: GameState, eid: int, act: String, d: Dictionary) -> Array[Dictionary]:
	var added: Array[Dictionary] = []
	match act:
		"build":
			build(state, eid, String(d["ship"]))
		"settle":
			InsExode.settle(state, eid, added)
		"purge":
			purge(state, eid, int(d["pid"]), added)
		"delegate":
			InsZambalu.delegate(state, eid)
		"sentinel":
			InsHalcyre.sentinel(state, eid, int(d["pid"]), added)
		"devour":
			InsHalcyre.devour(state, eid, int(d["pid"]))
		"pilot":
			InsKraal.pilot(state, eid, int(d["fleet"]), added)
	return added


# --- Affichage ------------------------------------------------------------------------------------

## Lignes d'état du peuple pour sa fiche (écran Empire, manuel).
static func status_lines(state: GameState, eid: int) -> Array[String]:
	var out: Array[String] = []
	var ed := emp(state, eid)
	if ed.is_empty():
		return out
	match String(ed["k"]):
		"exode":
			out = InsExode.status_lines(state, eid, ed)
		"zambalu":
			out = InsZambalu.status_lines(state, eid, ed)
		"halcyre":
			out = InsHalcyre.status_lines(state, eid, ed)
		"kraal":
			out = InsKraal.status_lines(state, eid, ed)
	var y: Dictionary = ed.get("yard", {})
	if not y.is_empty():
		out.append("Chantier embarqué : %s (%d j)" % [String(GameData.ship(String(y["ship"])).get("label", y["ship"])), int(y["left"])])
	var sp: Dictionary = ed.get("sp", {})
	if sp.size() > 1:
		var names := PackedStringArray()
		var ks := sp.keys()
		ks.sort()
		for k in ks:
			names.append("%s %d" % [String(GameData.faction(String(k)).get("short", k)), int(sp[k])])
		out.append("Espèces à bord : %s" % ", ".join(names))
	return out
