class_name Insolites
extends RefCounted
## Les peuples insolites (étude « Les 15 peuples insolites et le 9e peuple », validée le 2026-11-19 ;
## data/insolites.json). Lot 1 : les peuples sans monde, qui vivent en mouvement.
##   - Flotte-Exode des Derniers (InsExode) : quatre Nefs-cités en fuite, les Traqueurs, l'Espoir.
##   - Cirque Stellaire Zambalù (InsZambalu) : Troupes, représentations, Fan-clubs, Grand Numéro.
##   - Orbe-Monde Halcyre (InsHalcyre) : une planète qui marche, mange des lunes et s'allume en étoile.
##   - Hardes de Kraal (InsKraal) : des vaisseaux vivants qui naissent, vieillissent et broutent.
## Lot 2 : les peuples qui vivent chez les autres (InsVentrelune, InsBureau, InsSignal, InsYsmer).
## Lot 3 : les populations étranges, qui viennent des morts (InsAsphodele), tiennent en un seul homme
## (InsCassivel), ne pensent pas (InsSilencieux) ou refusent d'être vues (InsQuietude).
## Lot 4 : le temps, la lenteur et la vie végétale : défaire le passé (InsSablier), agir en décennies
## (InsGravea), coloniser sans vaisseau (InsMyrr) et changer les mondes en jardins (InsVergemonde).
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


## Lot 5 de l'arbre : un réglage d'un peuple insolite modifié par ses technologies (effet "ins_pct",
## {"peuple.réglage": %}). Le réglage de base reste dans data/insolites.json.
@warning_ignore("integer_division")
static func tuned(state: GameState, eid: int, section: String, key: String, base: int) -> int:
	var p := Research.fx_sub(state, eid, "ins_pct", section + "." + key)
	return base if p == 0 else base * maxi(0, 100 + p) / 100


## Lot 5 de l'arbre : talent de recherche d'un peuple insolite, du Savoir à chaque événement de sa
## mécanique (clé "learn_<événement>" du talent, en Savoir par unité). Renvoie le Savoir gagné.
static func learn(state: GameState, eid: int, key: String, units: int) -> int:
	var e := state.get_empire(eid)
	if e == null or units <= 0:
		return 0
	var k := int(e.faction().get("research", {}).get(key, 0)) * units
	if k > 0:
		e.resources["knowledge"] = int(e.resources.get("knowledge", 0)) + k
	return k


static func c_int(section: String, key: String, def := 0) -> int:
	return int(cfg(section).get(key, def))


# --- Qui est insolite ? --------------------------------------------------------------------------

## Sorte de peuple insolite d'une fiche ("" pour un peuple classique) : champ "nomad" des peuples
## sans monde (lot 1), "guest" des peuples qui vivent chez les autres (lot 2).
static func kind_of_faction(f: Dictionary) -> String:
	var k := String(f.get("nomad", {}).get("kind", ""))
	return k if k != "" else String(f.get("guest", {}).get("kind", ""))


## Le peuple démarre-t-il sans monde natal ? (les nomades, et le Signal qui n'existe que comme donnée)
static func worldless(f: Dictionary) -> bool:
	return f.has("nomad") or bool(f.get("guest", {}).get("worldless", false))


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
	match k:
		"ventrelune":
			InsVentrelune.found(state, e, sid, ed)
			return
		"bureau":
			InsBureau.found(state, e, sid, ed)
			return
		"signal":
			InsSignal.found(state, e, sid, ed)
			return
		"ysmer":
			InsYsmer.found(state, e, sid, ed)
			return
		"asphodele":
			InsAsphodele.found(state, e, sid, ed)
			return
		"cassivel":
			InsCassivel.found(state, e, sid, ed)
			return
		"silencieux":
			InsSilencieux.found(state, e, sid, ed)
			return
		"quietude":
			InsQuietude.found(state, e, sid, ed)
			return
		"sablier":
			InsSablier.found(state, e, sid, ed)
			return
		"gravea":
			InsGravea.found(state, e, sid, ed)
			return
		"myrr":
			InsMyrr.found(state, e, sid, ed)
			return
		"vergemonde":
			InsVergemonde.found(state, e, sid, ed)
			return
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


## Après la mise en place de tous les empires : le Signal pose ses premiers nœuds.
static func after_setup(state: GameState) -> void:
	for eid in nomad_ids(state):
		match kind(state, eid):
			"signal":
				InsSignal.seed_nodes(state, eid)
			"ysmer":
				InsYsmer.seed_reverie(state, eid)  # le Dormeur a déjà un rêveur chez le plus proche voisin
			"cassivel":
				InsCassivel.after_setup(state, eid)  # Sire Cassivel, héros et souverain
			"sablier":
				InsSablier.after_setup(state, eid)  # le Gardien chronal


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
	match k:
		"kraal":
			return InsKraal.herd_pop(state, eid) > 0
		"signal":
			return InsSignal.alive(state, eid)
		"ventrelune", "bureau", "ysmer", "asphodele", "cassivel", "silencieux", "quietude", "sablier", "gravea", "myrr", "vergemonde":
			return false
	return FactionTraits.city_fleet(state, eid) != null


# --- Revenus ------------------------------------------------------------------------------------

## Revenu mensuel brut propre aux peuples sans monde (Economy.empire_income, avant bonus de production).
static func income(state: GameState, eid: int) -> Dictionary:
	if state.insolites.is_empty():
		return {}
	var nf := InsBureau.norm_fx(state, eid, "influence")  # norme « archivage en sept exemplaires »
	if nf != 0:
		var out := _kind_income(state, eid).duplicate()
		out["influence"] = int(out.get("influence", 0)) + nf
		return out
	return _kind_income(state, eid)


static func _kind_income(state: GameState, eid: int) -> Dictionary:
	match kind(state, eid):
		"ysmer":
			return InsYsmer.income(state, eid)
		"exode":
			return InsExode.income(state, eid)
		"zambalu":
			return InsZambalu.income(state, eid)
		"halcyre":
			return InsHalcyre.income(state, eid)
		"kraal":
			return InsKraal.income(state, eid)
		"cassivel":
			return InsCassivel.income(state, eid)
	return {}


static func add_to(into: Dictionary, amounts: Dictionary, times := 1) -> void:
	for r in amounts:
		into[r] = int(into.get(r, 0)) + int(amounts[r]) * times


# --- Implants (prop. 9) -------------------------------------------------------------------------

static func implant_def(k: String) -> Dictionary:
	return (cfg("implants").get("kinds", {}) as Dictionary).get(k, {})


static func _ikey(pid: int, k: String) -> String:
	return str(pid) if k == "fan_club" else "%d|%s" % [pid, k]  # Fan-clubs : clé de la sauvegarde 101


static func _ipid(key: Variant) -> int:
	var s := String(key)
	var i := s.find("|")
	return int(s) if i < 0 else int(s.substr(0, i))


## Implant d'une sorte sur une planète ({} sans implant de cette sorte).
static func implant(state: GameState, pid: int, k := "fan_club") -> Dictionary:
	if state.insolites.is_empty():
		return {}
	return (state.insolites.get("implants", {}) as Dictionary).get(_ikey(pid, k), {})


## Implants d'une planète, toutes sortes, par sorte croissante.
static func implants_on(state: GameState, pid: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if state.insolites.is_empty():
		return out
	var ks: Array = (cfg("implants").get("kinds", {}) as Dictionary).keys()
	ks.sort()
	for k in ks:
		var im := implant(state, pid, String(k))
		if not im.is_empty():
			out.append(im)
	return out


## Planètes portant un implant de ce propriétaire (d'une sorte, ou de toutes avec k = ""), triées.
static func implants_of(state: GameState, owner: int, k := "") -> Array[int]:
	var out: Array[int] = []
	if state.insolites.is_empty():
		return out
	var im: Dictionary = state.insolites.get("implants", {})
	for key in im:
		var d: Dictionary = im[key]
		if int(d["o"]) == owner and (k == "" or String(d["k"]) == k):
			var pid := _ipid(key)
			if not out.has(pid):
				out.append(pid)
	out.sort()
	return out


static func add_implant(state: GameState, pid: int, k: String, owner: int) -> void:
	sub(state, "implants")[_ikey(pid, k)] = {"k": k, "o": owner, "t": state.tick}


static func remove_implant(state: GameState, pid: int, k: String) -> void:
	if not state.insolites.is_empty():
		(state.insolites.get("implants", {}) as Dictionary).erase(_ikey(pid, k))


## L'implant est-il visible de cet empire ? Un implant caché ne se voit que de son propriétaire, et de
## l'hôte qui sait le chercher : pare-feu (Propagande) pour un Nœud du Signal, Éveil psionique pour une
## Rêverie d'Ysmer.
static func implant_visible(state: GameState, pid: int, eid: int, k := "fan_club") -> bool:
	var im := implant(state, pid, k)
	if im.is_empty():
		return false
	if int(im["o"]) == eid or not bool(implant_def(k).get("hidden", false)):
		return true
	var c: Colony = state.colonies.get(pid)
	if c == null or c.owner != eid:
		return false
	match k:
		"noeud":
			return InsSignal.detects(state, eid, im)
		"reverie":
			return InsYsmer.detects(state, eid)
		"poste":
			return false  # le poste voilé ne se voit qu'une fois découvert : il tombe aussitôt
	return int(im.get("seen", 0)) > 0


## Dîmes du mois : chaque implant prend sa part chez l'hôte (dans la limite de ses réserves).
static func _implant_month(state: GameState, _added: Array[Dictionary]) -> void:
	var im: Dictionary = state.insolites.get("implants", {})
	var keys := im.keys()
	keys.sort()
	for key in keys:
		var d: Dictionary = im[key]
		var pid := _ipid(key)
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
		match String(d["k"]):
			"noeud":
				tithe = InsSignal.bandwidth(state, owner.id, c)
		for r in tithe:
			var n := mini(int(tithe[r]), maxi(0, int(host.resources.get(r, 0))))
			if n > 0:
				host.resources[r] = int(host.resources.get(r, 0)) - n
				owner.resources[r] = int(owner.resources.get(r, 0)) + n
		Insolites.add_to(host.resources, df.get("host_gain", {}))  # piété des Ossuaires
		var rad := int(df.get("radiance", 0))
		if rad > 0 and not state.culture.is_empty():
			var cum := Culture._m(state, "cum")
			var ck := Culture._k(owner.id, host.id)
			cum[ck] = int(cum.get(ck, 0)) + rad


static func check_purge(state: GameState, eid: int, pid: int, k := "fan_club") -> String:
	var im := implant(state, pid, k)
	if im.is_empty():
		return "aucun implant de cette sorte sur cette planète"
	var c: Colony = state.colonies.get(pid)
	if c == null or c.owner != eid:
		return "seul le propriétaire de la planète peut purger un implant"
	if not implant_visible(state, pid, eid, k):
		return "aucun implant connu sur cette planète"
	if k == "reverie" and not Psionics.awake(state, eid):
		return "seuls des Éveillés peuvent plonger dans le Songe pour chasser une rêverie"
	if k == "noeud" and InsSignal.hosted(state, int(im["o"]), eid):
		return "un accord d'hébergement protège ce nœud : rompez-le d'abord"
	if k == "ossuaire":
		return "un Ossuaire tient au Pacte funéraire : rompez le pacte pour le fermer"
	var cost: Dictionary = implant_def(k).get("purge_cost", {})
	if not Economy.can_afford(state.get_empire(eid), cost):
		return "ressources insuffisantes (il faut %s)" % GameData.format_amounts(cost)
	return ""


const PURGE_TEXT := {
	"fan_club": "Les fans pleurent ; certains gardent leurs affiches sous le lit.",
	"guichet": "Le guichet ferme. Une affichette indique de s'adresser au guichet d'à côté, qui n'existe pas.",
	"noeud": "Les calculateurs redémarrent. Pendant une seconde, tous les écrans ont affiché le même mot.",
	"reverie": "Les Éveillés sont revenus du Songe ; les dormeurs ne se souviennent plus de ce qu'ils rêvaient.",
	"ossuaire": "On rend les morts aux familles, qui ne savent pas trop quoi en faire.",
	"poste": "Le poste voilé est démonté. Les jeunes peuples ne sauront jamais qu'on les aimait.",
	"mycelium": "On brûle les caves, les égouts, les champs. Ça sent le pain grillé pendant une semaine, et la terre ne donne plus rien de l'année.",
}


static func purge(state: GameState, eid: int, pid: int, added: Array[Dictionary], k := "fan_club") -> void:
	var im := implant(state, pid, k)
	var df := implant_def(k)
	Economy.pay(state.get_empire(eid), df.get("purge_cost", {}))
	var owner := state.get_empire(int(im["o"]))
	remove_implant(state, pid, k)
	var sid := state.galaxy.get_planet(pid).system_id
	if k == "mycelium" and Ecology.has_biosphere(state, pid):
		Ecology._set_health(state, pid, maxi(0, Ecology.health(state, pid) - c_int("myrr", "burn_eco", 30)))  # seul le feu l'arrête
	sub(state, "purged")[str(sid)] = state.tick + int(df.get("purge_stability_days", 0))
	added.append(state.add_chronicle("%s purge le %s de %s sur %s. %s" % [
			state.get_empire(eid).display_name(), String(df.get("label", k)).to_lower(), owner.short_name() if owner else "?",
			state.galaxy.get_planet(pid).display_name(state.galaxy), String(PURGE_TEXT.get(k, ""))], Espionage.private_to(state, [eid, int(im["o"])], sid)))


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
		if kind(state, int(pair[0])) == "signal":
			return "le Signal ne signe rien, sauf un Accord d'hébergement"
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
		"myrr":
			return "la Sporemère n'envahit pas : le mycélium gagne les mondes de proche en proche"
	return ""


## Raison qui empêche d'envahir ce système ("" sinon) : un monde des Lithes y hiberne.
static func target_block(state: GameState, sid: int) -> String:
	if state.insolites.is_empty():
		return ""
	var g := InsGravea.invade_block(state, sid)
	return g if g != "" else InsMyrr.invade_block(state, sid)


## Raison qui empêche de construire un vaisseau ("" sinon) : la Sporemère n'en a aucun, jamais.
static func ship_block(state: GameState, eid: int) -> String:
	if state.insolites.is_empty() or kind(state, eid) != "myrr":
		return ""
	return "la Sporemère ne construit aucun vaisseau : elle lance des comètes-semences"


## Production d'une colonie en % (Economy.colony_yields) : déchirures et bulles du Sablier, monde des
## Lithes qui hiberne, système de Myrr isolé du réseau.
static func colony_pct(state: GameState, pid: int) -> int:
	if state.insolites.is_empty():
		return 100
	var pct := maxi(0, 100 + InsSablier.system_pct(state, state.galaxy.get_planet(pid).system_id))
	@warning_ignore("integer_division")
	pct = pct * InsGravea.colony_pct(state, pid) / 100 * InsMyrr.colony_pct(state, pid) / 100
	pct = pct * (100 + InsSilencieux.colony_pct(state, pid)) / 100  # Optimiser les chaînes
	return pct


## Un système va changer de main (Combat.capture_system) : le Registre des Gardiens.
static func on_capture(state: GameState, sid: int, new_owner: int, old: int) -> void:
	if not state.insolites.is_empty():
		InsSablier.on_capture(state, sid, new_owner, old)


## Une technologie est volée (Espionage, « Voler une technologie ») : le Registre des Gardiens.
static func on_tech_stolen(state: GameState, thief: int, victim: int, tid: String, amount: int) -> void:
	if not state.insolites.is_empty():
		InsSablier.on_tech_stolen(state, thief, victim, tid, amount)


## Espérance de vie des héros en % (Heroes.life_years) : la longévité des Gardiens.
static func life_pct(state: GameState, eid: int) -> int:
	return 100 if state.insolites.is_empty() else InsSablier.life_pct(state, eid)


## Bombardement orbital (GroundSiege) : le feu sur un système de Myrr.
static func on_bombard(state: GameState, sid: int, owner: int) -> void:
	if not state.insolites.is_empty():
		InsMyrr.on_bombard(state, sid, owner)


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
	if InsYsmer.nightmare(state, sid):
		out.append(["Cauchemars des Ysmer", c_int("ysmer", "nightmare_stab", -10)])
	InsSablier.stability_parts(state, sid, out)
	if owner < 0:
		return out
	if InsSignal.symptoms(state, sid, owner):
		out.append(["Symptômes étranges", c_int("signal", "symptom_stab", -2)])
	var ns := InsBureau.norm_fx(state, owner, "stab")
	if ns != 0:
		out.append(["Registre d'état civil", ns])
	if InsBureau.bailiffs(state, sid, owner):
		out.append(["Huissiers du Bureau", -3])
	InsAsphodele.stability_parts(state, sid, owner, out)
	InsCassivel.stability_parts(state, owner, out)
	InsVergemonde.stability_parts(state, owner, out)
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
	if state.insolites.is_empty():
		return 100
	var pct := InsKraal.speed_pct(state, f) if kind(state, f.owner) == "kraal" else 100
	var e := state.get_empire(f.owner)
	if e != null and e.wars.is_empty():
		pct += InsBureau.norm_fx(state, f.owner, "speed_pct")  # formulaire de transit B-7
	return pct


## Un vaisseau tombe au combat (CombatSystem._apply_damage) : carcasse d'un Kraal dépecée.
static func on_ship_lost(state: GameState, f: Fleet, i: int, b: Dictionary) -> void:
	if state.insolites.is_empty():
		return
	InsSablier.on_ship_lost(state, f, i)  # le Registre des Gardiens
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


## Bonus de production (%, Economy.production_pct) : normes signées (recherche), sanctions du Bureau.
static func production_bonus(state: GameState, eid: int, resource: String) -> int:
	if state.insolites.is_empty():
		return 0
	var n := InsBureau.norm_fx(state, eid, "knowledge_pct") if resource == "knowledge" else 0
	if InsBureau.sanctioned(state, eid):
		n += c_int("bureau", "sanction_income_pct", -10)
	match kind(state, eid):
		"cassivel":
			n += InsCassivel.production_bonus(state, eid)  # Muséum Orphelin
		"silencieux":
			if resource == "knowledge":
				n -= 100  # ils ne cherchent pas : ils démontent
		"myrr":
			n += InsMyrr.production_bonus(state, eid, resource)  # symbioses
		"vergemonde":
			n += InsVergemonde.production_bonus(state, eid, resource)  # les trois âges
	return n


## Revenu des traités commerciaux en % (Economy.empire_income) : normes, Non-conformité.
static func trade_pct(state: GameState, eid: int) -> int:
	if state.insolites.is_empty():
		return 100
	return maxi(0, 100 + InsBureau.norm_fx(state, eid, "trade_pct") + InsBureau.nonconf_pct(state, eid))


## Durée de construction des vaisseaux en % de plus (Fleets.ship_days) : homologation, Non-conformité.
static func ship_days_pct(state: GameState, eid: int) -> int:
	if state.insolites.is_empty():
		return 0
	return -InsBureau.norm_fx(state, eid, "build_pct") - InsBureau.nonconf_pct(state, eid)


## Croissance en % (Economy.growth_per_day) : directive Croissance de la Compagnie.
static func growth_pct(state: GameState, eid: int) -> int:
	if state.insolites.is_empty() or kind(state, eid) != "ventrelune":
		return 0
	return int(InsVentrelune.directive_def(state, eid).get("growth_pct", 0))


## Raison qui empêche une déclaration de guerre ("" sinon) : le Bureau envoie des Mises en demeure.
static func war_block(state: GameState, eid: int, target := -1) -> String:
	if state.insolites.is_empty():
		return ""
	match kind(state, eid):
		"gravea":
			return InsGravea.war_block(state, eid, target)  # Consensus séculaire
		"bureau":
			return "le Bureau ne déclare jamais de guerre : il adresse une Mise en demeure"
		"signal":
			return "le Signal ne déclare pas de guerre : il se copie"
	return ""


## Raison qui empêche une revendication de ce type ("" sinon) : le Dormeur n'a qu'un monde.
static func claim_block(state: GameState, eid: int, claim_kind: String) -> String:
	if state.insolites.is_empty():
		return ""
	if claim_kind == Colony.KIND_COLONY and kind(state, eid) == "ysmer":
		return "les Ysmer n'ont qu'un monde, celui du Dormeur : leur territoire est dans les rêves des autres"
	if kind(state, eid) == "myrr":
		return "la Sporemère ne revendique rien : elle lance des comètes-semences (menu des peuples)"
	return ""


## Jours de plus pour fonder une revendication (SimCommands) : le dossier d'un an du Bureau.
static func claim_extra_days(state: GameState, eid: int, claim_kind: String) -> int:
	if state.insolites.is_empty() or claim_kind != Colony.KIND_COLONY or kind(state, eid) != "bureau":
		return 0
	return tuned(state, eid, "bureau", "file_days", c_int("bureau", "file_days", 360))


## Coût des contrats de mercenaires en % de plus (Diplomacy.sign_contract) : l'armée privée.
static func contract_fee_pct(state: GameState, client: int) -> int:
	if state.insolites.is_empty() or kind(state, client) != "ventrelune":
		return 0
	return c_int("ventrelune", "merc_fee_pct", -30)


## Planètes que le peuple voit chez les autres : parts de la Compagnie à 25 %, nœuds, rêveries.
static func seen_planets(state: GameState, eid: int) -> Array[int]:
	var pids: Array[int] = []
	match kind(state, eid):
		"ventrelune":
			var sh := InsVentrelune.shares(state, eid)
			for key in sh:
				if int(sh[key]) >= c_int("ventrelune", "view_pct", 25):
					pids.append(int(key))
			pids.sort()
		"signal", "ysmer":
			pids = implants_of(state, eid)
	return pids


## Vision (Fleets) : les systèmes de ces planètes, sans portée au-delà.
static func vision(state: GameState, eid: int, sources: Dictionary) -> void:
	if state.insolites.is_empty():
		return
	for pid in seen_planets(state, eid):
		var p := state.galaxy.get_planet(pid)
		if p != null:
			sources[p.system_id] = maxi(int(sources.get(p.system_id, -1)), 0)


## Ces systèmes sont aussi explorés (chaque mois) : on peut ouvrir leur vue système.
static func _explore(state: GameState, eid: int) -> void:
	var e := state.get_empire(eid)
	for pid in seen_planets(state, eid):
		var p := state.galaxy.get_planet(pid)
		if p != null:
			e.explored[p.system_id] = true


## Motif de guerre Expropriation (Wars) : la Compagnie contre qui a saisi ou privé de licence ses parts.
static func expropriation_casus(state: GameState, a: int, b: int) -> bool:
	return not state.insolites.is_empty() and InsVentrelune.expropriation_casus(state, a, b)


## Opinion de a envers b (Diplomacy.opinion_parts) : les fois face à Asphodèle.
static func opinion_parts(state: GameState, a: int, b: int) -> Array:
	var out := []
	if not state.insolites.is_empty():
		InsAsphodele.opinion_parts(state, a, b, out)
	return out


## Sources de Rayonnement (Culture.source_parts) : la Collection du Muséum.
static func culture_parts(state: GameState, eid: int) -> Array:
	var out := []
	if not state.insolites.is_empty():
		InsCassivel.culture_parts(state, eid, out)
	return out


## Immunités des Silencieux (culture, foi, diplomatie ; psionique et intrigues par leurs talents).
static func silent(state: GameState, eid: int) -> bool:
	return not state.insolites.is_empty() and InsSilencieux.is_silent(state, eid)


## Ni file de recherche ni Savoir (Research.advance) : les Silencieux n'inventent pas.
static func no_research(state: GameState, eid: int) -> bool:
	return silent(state, eid)


## Victoire permise à cet empire (Victory.progress) : la force seulement pour les Silencieux.
static func victory_allowed(state: GameState, eid: int, id: String) -> bool:
	return state.insolites.is_empty() or InsSilencieux.victory_allowed(state, eid, id)


## Loi « Rites funéraires protégés » (Amphictyonie) : pas de Pacte funéraire.
static func funeral_banned(state: GameState) -> bool:
	return not state.amph.is_empty() and Amphictyony.founded(state) and Amphictyony.banned(state, "funeral_pact")


## Un héros meurt (Heroes.die) : liste des morts d'Asphodèle, chute de Sire Cassivel.
static func on_hero_death(state: GameState, h: Dictionary, out: Array[Dictionary]) -> void:
	if state.insolites.is_empty():
		return
	InsCassivel.on_hero_death(state, h, out)
	InsAsphodele.on_hero_death(state, h)
	InsSablier.on_hero_death(state, h, out)


## Un départ volontaire n'est pas une mort (recensement d'Asphodèle).
static func note_departure(state: GameState, pid: int, n: int) -> void:
	if not state.insolites.is_empty():
		InsAsphodele.note_departure(state, pid, n)


## Avènement d'un pré-spatial (MinorsLife.rise) : un Protégé des Observateurs.
static func on_minor_rise(state: GameState, mid: int, added: Array[Dictionary]) -> void:
	if not state.insolites.is_empty():
		InsQuietude.on_rise(state, mid, added)


## Opérations d'espionnage des peuples insolites (drapeau "insolites" dans data/espionage.json).
static func spy_check(state: GameState, a: int, b: int, op_id: String) -> String:
	match op_id:
		"acquisition_discrete":
			if kind(state, a) != "cassivel":
				return "seul le Muséum vole des spécimens"
			if InsCassivel.species_of(state, b) == "" or InsCassivel.species_held(state, a).has(InsCassivel.species_of(state, b)):
				return "la vitrine a déjà son spécimen de ce peuple"
	return ""


static func spy_apply(state: GameState, a: int, b: int, o: Dictionary) -> String:
	match String(o["id"]):
		"acquisition_discrete":
			return InsCassivel.spy_steal(state, a, b)
	return ""


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
		if month:
			_explore(state, eid)
		match String(ed["k"]):
			"exode":
				InsExode.daily(state, eid, ed, month, added)
			"zambalu":
				InsZambalu.daily(state, eid, ed, month, added)
			"halcyre":
				InsHalcyre.daily(state, eid, ed, month, added)
			"kraal":
				InsKraal.daily(state, eid, ed, month, added)
			"ventrelune":
				InsVentrelune.daily(state, eid, ed, month, added)
			"bureau":
				InsBureau.daily(state, eid, ed, month, added)
			"signal":
				InsSignal.daily(state, eid, ed, month, added)
			"ysmer":
				InsYsmer.daily(state, eid, ed, month, added)
			"asphodele":
				InsAsphodele.daily(state, eid, ed, month, added)
			"cassivel":
				InsCassivel.daily(state, eid, ed, month, added)
			"silencieux":
				InsSilencieux.daily(state, eid, ed, month, added)
			"quietude":
				InsQuietude.daily(state, eid, ed, month, added)
			"sablier":
				InsSablier.daily(state, eid, ed, month, added)
			"gravea":
				InsGravea.daily(state, eid, ed, month, added)
			"myrr":
				InsMyrr.daily(state, eid, ed, month, added)
			"vergemonde":
				InsVergemonde.daily(state, eid, ed, month, added)
	InsZambalu.numero_day(state, added)
	if month:
		InsAsphodele.census(state, added)  # les morts du mois, une fois pour toute la galaxie
		_implant_month(state, added)
	return added


# --- Ordres des joueurs ---------------------------------------------------------------------------
## Actions (SimCommands.ins_act) : "build" (ship), "settle", "purge" (pid, k), "delegate", "sentinel" (pid),
## "devour" (pid), "pilot" (fleet) ; lot 2 : "buy" et "nationalize" (pid), "sign" (b, norm), "summon"
## (target), "host" et "unhost" (s), "inspire" et "nightmare" (pid), "dream_fleet" ; lot 3 : "pact" et
## "unpact" (a), "raise" et "release" (i), "backup", "acquire" (w : empire ou mineur), "awaken" (pid),
## "post" et "uplift" (m : mineur) ; lot 4 : "undo" (i), "bubble" (s, mode), "repli" (fleet), "pli" (pid), "loop", "work" (w, pid),
## "hasten" (i), "deliberate" (t), "sleep" (pid), "comet" (s), "burn" (pid), "season" (s), "heart" (pid).

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
			return check_purge(state, eid, int(d.get("pid", -1)), String(d.get("k", "fan_club")))
		"delegate":
			return InsZambalu.check_delegate(state, eid)
		"sentinel":
			return InsHalcyre.check_sentinel(state, eid, int(d.get("pid", -1)))
		"devour":
			return InsHalcyre.check_devour(state, eid, int(d.get("pid", -1)))
		"pilot":
			return InsKraal.check_pilot(state, eid, int(d.get("fleet", -1)))
		"buy":
			return InsVentrelune.check_buy(state, eid, int(d.get("pid", -1)))
		"nationalize":
			return InsVentrelune.check_nationalize(state, eid, int(d.get("pid", -1)))
		"sign":
			return InsBureau.check_sign(state, eid, int(d.get("b", -1)), String(d.get("norm", "")))
		"summon":
			return InsBureau.check_summon(state, eid, int(d.get("target", -1)))
		"host", "unhost":
			return InsSignal.check_host(state, eid, int(d.get("s", -1)), act == "host")
		"inspire", "nightmare":
			return InsYsmer.check_breath(state, eid, act, int(d.get("pid", -1)))
		"dream_fleet":
			return InsYsmer.check_dream_fleet(state, eid)
		"pact", "unpact":
			return InsAsphodele.check_pact(state, eid, int(d.get("a", -1)), act == "pact")
		"raise":
			return InsAsphodele.check_raise(state, eid, int(d.get("i", -1)))
		"release":
			return InsAsphodele.check_release(state, eid, int(d.get("i", -1)))
		"backup":
			return InsCassivel.check_backup(state, eid)
		"acquire":
			return InsCassivel.check_acquire(state, eid, int(d.get("w", -1)))
		"awaken":
			return InsSilencieux.check_awaken(state, eid, int(d.get("pid", -1)))
		"post":
			return InsQuietude.check_post(state, eid, int(d.get("m", -1)))
		"uplift":
			return InsQuietude.check_uplift(state, eid, int(d.get("m", -1)))
		"undo":
			return InsSablier.check_undo(state, eid, int(d.get("i", -1)))
		"bubble":
			return InsSablier.check_bubble(state, eid, int(d.get("s", -1)), String(d.get("mode", "")))
		"repli":
			return InsSablier.check_fold(state, eid, "repli", int(d.get("fleet", -1)))
		"pli":
			return InsSablier.check_fold(state, eid, "pli", int(d.get("pid", -1)))
		"loop":
			return InsSablier.check_loop(state, eid)
		"work":
			return InsGravea.check_work(state, eid, String(d.get("w", "")), int(d.get("pid", -1)))
		"hasten":
			return InsGravea.check_hasten(state, eid, int(d.get("i", -1)))
		"deliberate":
			return InsGravea.check_deliberate(state, eid, int(d.get("t", -1)))
		"sleep":
			return InsGravea.check_sleep(state, eid, int(d.get("pid", -1)))
		"comet":
			return InsMyrr.check_comet(state, eid, int(d.get("s", -1)))
		"burn":
			return InsMyrr.check_burn(state, eid, int(d.get("pid", -1)))
		"season":
			return InsVergemonde.check_season(state, eid, String(d.get("s", "")))
		"heart":
			return InsVergemonde.check_heart(state, eid, int(d.get("pid", -1)))
	return "action inconnue : %s" % act


static func apply(state: GameState, eid: int, act: String, d: Dictionary) -> Array[Dictionary]:
	var added: Array[Dictionary] = []
	match act:
		"build":
			build(state, eid, String(d["ship"]))
		"settle":
			InsExode.settle(state, eid, added)
		"purge":
			purge(state, eid, int(d["pid"]), added, String(d.get("k", "fan_club")))
		"delegate":
			InsZambalu.delegate(state, eid)
		"sentinel":
			InsHalcyre.sentinel(state, eid, int(d["pid"]), added)
		"devour":
			InsHalcyre.devour(state, eid, int(d["pid"]))
		"pilot":
			InsKraal.pilot(state, eid, int(d["fleet"]), added)
		"buy":
			InsVentrelune.buy(state, eid, int(d["pid"]), added)
		"nationalize":
			InsVentrelune.nationalize(state, eid, int(d["pid"]), added)
		"sign":
			InsBureau.sign(state, eid, int(d["b"]), String(d["norm"]), added)
		"summon":
			InsBureau.summon(state, eid, int(d["target"]), added)
		"host", "unhost":
			InsSignal.set_host(state, eid, int(d["s"]), act == "host", added)
		"inspire", "nightmare":
			InsYsmer.breath(state, eid, act, int(d["pid"]), added)
		"dream_fleet":
			InsYsmer.dream_fleet(state, eid, added)
		"pact", "unpact":
			InsAsphodele.set_pact(state, eid, int(d["a"]), act == "pact", added)
		"raise":
			InsAsphodele.raise(state, eid, int(d["i"]), added)
		"release":
			InsAsphodele.release(state, eid, int(d["i"]), added)
		"backup":
			InsCassivel.backup(state, eid, added)
		"acquire":
			InsCassivel.acquire(state, eid, int(d["w"]), added)
		"awaken":
			InsSilencieux.awaken(state, eid, int(d["pid"]), added)
		"post":
			InsQuietude.post(state, eid, int(d["m"]), added)
		"uplift":
			InsQuietude.uplift(state, eid, int(d["m"]), added)
		"undo":
			InsSablier.undo(state, eid, int(d["i"]), added)
		"bubble":
			InsSablier.bubble(state, eid, int(d["s"]), String(d["mode"]), added)
		"repli":
			InsSablier.fold(state, eid, "repli", int(d["fleet"]), added)
		"pli":
			InsSablier.fold(state, eid, "pli", int(d["pid"]), added)
		"loop":
			InsSablier.loop(state, eid, added)
		"work":
			InsGravea.start_work(state, eid, String(d["w"]), int(d["pid"]), added)
		"hasten":
			InsGravea.hasten(state, eid, int(d["i"]), added)
		"deliberate":
			InsGravea.deliberate(state, eid, int(d["t"]), added)
		"sleep":
			InsGravea.sleep(state, eid, int(d["pid"]), added)
		"comet":
			InsMyrr.comet(state, eid, int(d["s"]), added)
		"burn":
			InsMyrr.burn(state, eid, int(d["pid"]), added)
		"season":
			InsVergemonde.set_season(state, eid, String(d["s"]), added)
		"heart":
			InsVergemonde.heart(state, eid, int(d["pid"]), added)
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
		"ventrelune":
			out = InsVentrelune.status_lines(state, eid, ed)
		"bureau":
			out = InsBureau.status_lines(state, eid, ed)
		"signal":
			out = InsSignal.status_lines(state, eid, ed)
		"ysmer":
			out = InsYsmer.status_lines(state, eid, ed)
		"asphodele":
			out = InsAsphodele.status_lines(state, eid, ed)
		"cassivel":
			out = InsCassivel.status_lines(state, eid, ed)
		"silencieux":
			out = InsSilencieux.status_lines(state, eid, ed)
		"quietude":
			out = InsQuietude.status_lines(state, eid, ed)
		"sablier":
			out = InsSablier.status_lines(state, eid, ed)
		"gravea":
			out = InsGravea.status_lines(state, eid, ed)
		"myrr":
			out = InsMyrr.status_lines(state, eid, ed)
		"vergemonde":
			out = InsVergemonde.status_lines(state, eid, ed)
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
