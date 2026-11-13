class_name Fauna
extends RefCounted
## La Faune (étude « Créatures spatiales et gardiens », 2026-11-12, lot 1 : propositions 1 à 5, 13 en
## partie, 14 à 16) : une puissance neutre (GameState.FAUNA_ID, hors de state.empires) faite de
## troupeaux de créatures qui vivent autour de leur nid. Les troupeaux migrent à quelques sauts du nid,
## n'entrent jamais dans un système revendiqué, ne colonisent ni n'assiègent rien, et ne barrent pas le
## passage. Chaque espèce a un tempérament (passive, territoriale, prédatrice) et une faiblesse lisible
## dans le modèle de combat. Après le premier contact, chaque empire peut l'étudier (bonus permanent),
## la chasser (+33 % de dégâts, butin, elle le combat même passive) ou, pour deux espèces, l'apprivoiser.
## Tant que le nid vit, les troupeaux tués renaissent. Règles dans data/creatures.json. Entiers, sans
## aléatoire (les choix suivent des hachages de la graine) : même partie sur toutes les machines.
##
## state.fauna = {"density": réglage, "per_nest": troupeaux par nid,
##   "nests": {sid: {"sp": espèce, "born": jour, "lost": dernier troupeau perdu ou né}},
##   "herds": {flotte: {"sp", "nest": système du nid (-1 : troupeau dérangé par une curiosité),
##     "next": prochain déplacement, "until": dispersion du troupeau dérangé (0 sinon)}},
##   "meta": {empire: {"seen": {sp: jour}, "study": {sp: fin (> 0 en cours, -1 terminée)},
##     "stance": {sp: "chasse" | "apprivoise"}, "kills": {sp: créatures abattues}}}}

const ATTITUDES := ["etude", "chasse", "apprivoise", "renoncer"]
const LAYERS := ["archetype", "gouvernement", "credo", "registre"]

static var _talent_cache := {}


static func data() -> Dictionary:
	return GameData.creatures()


## Talents du peuple face aux créatures (data/creatures.json, "talents"), couches d'espèce
## additionnées (les booléens restent vrais), comme Pirates.talent.
static func talent(state: GameState, empire_id: int) -> Dictionary:
	var e := state.get_empire(empire_id)
	if e == null or e.is_npc():
		return {}
	var ck := "%s:%d" % [e.faction_id, GameData.factions_gen]
	if _talent_cache.has(ck):
		return _talent_cache[ck]
	var out := {}
	var sp: Dictionary = e.faction().get("species", {})
	var table: Dictionary = data().get("talents", {})
	for layer in LAYERS:
		var t: Dictionary = (table.get(layer, {}) as Dictionary).get(String(sp.get(layer, "")), {})
		for k in t:
			if k == "label" or k == "text":
				continue
			var v: Variant = t[k]
			out[k] = v if v is bool else int(out.get(k, 0)) + int(v)
	_talent_cache[ck] = out
	return out


## Talents à afficher : [[nom, texte], …].
static func talent_labels(state: GameState, empire_id: int) -> Array:
	var e := state.get_empire(empire_id)
	var out := []
	if e == null or e.is_npc():
		return out
	var sp: Dictionary = e.faction().get("species", {})
	var table: Dictionary = data().get("talents", {})
	for layer in LAYERS:
		var t: Dictionary = (table.get(layer, {}) as Dictionary).get(String(sp.get(layer, "")), {})
		if not t.is_empty():
			out.append([String(t["label"]), String(t["text"])])
	return out


## Revenu des safaris (credo du profit) : énergie par mois pour chaque colonie à 2 sauts d'un nid vivant.
static func safari_income(state: GameState, empire_id: int) -> int:
	var per := int(talent(state, empire_id).get("safari", 0))
	if per <= 0 or nests(state).is_empty():
		return 0
	var near := {}
	for sid in nest_ids(state):
		near[sid] = true
		for n in state.galaxy.systems[sid].neighbors:
			near[int(n)] = true
			for n2 in state.galaxy.systems[int(n)].neighbors:
				near[int(n2)] = true
	var count := 0
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner == empire_id and near.has(state.galaxy.get_planet(pid).system_id):
			count += 1
	return count * per


## Gardiens vénérés (credo de la foi) : gardiens éveillés à 3 sauts au plus d'une colonie de l'empire.
static func venerated(state: GameState, empire_id: int) -> int:
	var tal := talent(state, empire_id)
	if int(tal.get("venerate_stab", 0)) == 0 and int(tal.get("venerate_influence", 0)) == 0:
		return 0
	var mine := {}
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner == empire_id:
			mine[state.galaxy.get_planet(pid).system_id] = true
	if mine.is_empty():
		return 0
	var n := 0
	for gid in Guardians.ids(state):
		var gsid := Guardians.fleet_system(state, gid)
		if gsid < 0 or String(Guardians.list(state)[gid]["status"]) != "awake":
			continue
		var j := FactionTraits.jumps_from(state.galaxy, gsid)
		for sid in mine:
			if int(j.get(sid, 99)) <= 3:
				n += 1
				break
	return mini(n, int(tal.get("venerate_max", 3)))


## Parts de stabilité de la Faune (credo de la foi : gardiens vénérés).
static func stability_parts(state: GameState, empire_id: int) -> Array:
	var v := int(talent(state, empire_id).get("venerate_stab", 0))
	if v == 0 or state.fauna.is_empty():
		return []
	var n := venerated(state, empire_id)
	return [["Gardiens vénérés (%d)" % n, v * n]] if n > 0 else []


static func species(sp: String) -> Dictionary:
	return (data()["species"] as Dictionary).get(sp, {})


static func species_ids() -> Array[String]:
	var out: Array[String] = []
	for k in data()["species"]:
		out.append(String(k))
	out.sort()
	return out


static func temper(sp: String) -> String:
	return String(species(sp).get("temper", "territorial"))


static func temper_label(sp: String) -> String:
	return String((data()["tempers"] as Dictionary).get(temper(sp), {}).get("label", temper(sp)))


static func attitude_def(att: String) -> Dictionary:
	return (data()["attitudes"] as Dictionary).get(att, {})


## Espèce d'une créature (identifiant de classe « bete_… »), "" si ce n'en est pas une.
static func species_of_unit(unit: String) -> String:
	return String(GameData.ship(unit).get("creature", ""))


# --- Densité et placement ----------------------------------------------------------------------

static func densities() -> Array:
	return data()["densities"]


static func density_def(id: String) -> Dictionary:
	for d: Dictionary in densities():
		if String(d["id"]) == id:
			return d
	return {}


static func default_density() -> String:
	return String(data().get("default", "normales"))


static func density_label(id: String) -> String:
	return String(density_def(id).get("label", id))


static func nests(state: GameState) -> Dictionary:
	return state.fauna.get("nests", {})


static func herds(state: GameState) -> Dictionary:
	return state.fauna.get("herds", {})


static func active(state: GameState) -> bool:
	return not nests(state).is_empty() or not herds(state).is_empty()


static func nest_ids(state: GameState) -> Array[int]:
	var out: Array[int] = []
	for k in nests(state):
		out.append(int(k))
	out.sort()
	return out


static func herd_ids(state: GameState) -> Array[int]:
	var out: Array[int] = []
	for k in herds(state):
		out.append(int(k))
	out.sort()
	return out


## Avant toute écriture : une partie sans faune (ancienne sauvegarde, tests) reçoit une structure vide.
static func _ensure(state: GameState) -> void:
	if state.fauna.is_empty():
		state.fauna = _empty("aucune")


static func _empty(density_id: String) -> Dictionary:
	return {"density": density_id, "per_nest": int(density_def(density_id).get("herds", 0)), "nests": {}, "herds": {}, "meta": {},
			"guardians": {}, "choke": {}}


## Place les nids d'une nouvelle partie : un pour `per` systèmes environ, loin des départs et les uns
## des autres, jamais sur un repaire pirate ; les espèces tournent à partir d'un décalage tiré de la
## graine, pour que chacune ait sa chance. Chaque nid reçoit son gisement et ses premiers troupeaux.
static func setup(state: GameState, density_id: String) -> void:
	if density_def(density_id).is_empty():
		density_id = "aucune"
	state.fauna = _empty(density_id)
	var per := int(density_def(density_id).get("per", 0))
	if per <= 0:
		return
	@warning_ignore("integer_division")
	var want := maxi(1, (state.galaxy.systems.size() + per / 2) / per)
	var starts: Array = []
	for e in state.empires:
		var cap := FactionTraits.capital_system(state, e.id)
		if cap < 0 and e.home_planet >= 0:
			cap = state.galaxy.get_planet(e.home_planet).system_id
		if cap >= 0:
			starts.append(FactionTraits.jumps_from(state.galaxy, cap))
	var cands: Array = []
	for s in state.galaxy.systems:
		if state.system_owner(s.id) >= 0 or s.planet_ids.is_empty() or state.lairs.has(s.id):
			continue
		var near := 999
		for d: Dictionary in starts:
			near = mini(near, int(d.get(s.id, 999)))
		if near < int(data()["min_jumps_from_start"]):
			continue
		cands.append([hash([state.seed_value, "nid", s.id]), s.id])
	cands.sort()
	var picked: Array[int] = []
	for c in cands:
		if picked.size() >= want:
			break
		var sid := int(c[1])
		var ok := true
		for p in picked:
			if int(FactionTraits.jumps_from(state.galaxy, p).get(sid, 999)) < int(data()["min_jumps_between"]):
				ok = false
				break
		if ok:
			picked.append(sid)
	var ids := species_ids()
	var off := posmod(hash([state.seed_value, "faune"]), ids.size())
	for i in picked.size():
		create_nest(state, picked[i], ids[(off + i) % ids.size()])


static func create_nest(state: GameState, sid: int, sp: String) -> void:
	_ensure(state)
	nests(state)[sid] = {"sp": sp, "born": state.tick, "lost": -100000}
	# Le gisement qui fait la richesse du nid (et donne envie de le prendre).
	var dep := String(species(sp).get("deposit", ""))
	var ddef: Dictionary = GameData.deposit(dep) if dep != "" else {}
	var added := 0
	if not ddef.is_empty():
		for pid in state.galaxy.systems[sid].planet_ids:
			if added >= 2:
				break
			var p := state.galaxy.get_planet(pid)
			if p.deposits.has(dep) or (bool(ddef.get("habitable_only", false)) and not p.is_habitable_type()):
				continue
			var deps: Array = Array(p.deposits).duplicate()
			deps.append(dep)
			state.override_planet(pid, {"deposits": deps})
			added += 1
	for i in int(state.fauna.get("per_nest", 0)):
		var f := spawn_herd(state, sp, sid, sid)
		herds(state)[f.id]["next"] = state.tick + 30 + 50 * i + posmod(sid * 13, 30)
	for o in state.empires:
		o.path_cache.clear()


## Fait naître un troupeau de l'espèce dans le système. nest = -1 : troupeau dérangé (piège d'une
## curiosité), hostile à tous et dispersé au bout de `until`.
static func spawn_herd(state: GameState, sp: String, sid: int, nest: int, until := 0) -> Fleet:
	_ensure(state)
	var sd := species(sp)
	var unit := String(sd["unit"])
	var f := state.spawn_ship(GameState.FAUNA_ID, unit, sid)
	for i in range(1, int(sd.get("herd", 1))):
		f.add_ship(unit, -1, -1)
	f.troops = 0
	f.fleet_name = ("%s dérangées" if nest < 0 else "Troupeau de %s") % String(sd["label"])
	herds(state)[f.id] = {"sp": sp, "nest": nest, "next": state.tick + int(data()["migrate_days"]) + posmod(f.id * 53, 60), "until": until, "bait": -1}
	return f


static func herd_of(state: GameState, f: Fleet) -> Dictionary:
	if f == null or f.owner != GameState.FAUNA_ID:
		return {}
	return herds(state).get(f.id, {})


## Troupeaux vivants d'un nid.
static func nest_herds(state: GameState, sid: int) -> Array[int]:
	var out: Array[int] = []
	for fid in herd_ids(state):
		if int(herds(state)[fid]["nest"]) == sid and state.fleets.has(fid):
			out.append(fid)
	return out


static func herd_power(state: GameState, sid: int) -> int:
	var p := 0
	for f in Fleets.fleets_at(state, sid, GameState.FAUNA_ID):
		p += Combat.fleet_power(f)
	return p


## Puissance d'un troupeau type de l'espèce (intact).
static func species_power(sp: String) -> int:
	var sd := species(sp)
	return Combat.ship_strength(String(sd["unit"])) * int(sd.get("herd", 1))


## Fourchette affichée (proposition 14) : on ne voit jamais la force exacte d'une créature, seulement
## un ordre de grandeur, plus précis une fois l'espèce étudiée.
static func power_range(state: GameState, empire_id: int, f: Fleet) -> Array[int]:
	var p := Combat.fleet_power(f)
	var h := herd_of(state, f)
	var spread := 15 if not h.is_empty() and studied(state, empire_id, String(h["sp"])) else 40
	@warning_ignore("integer_division")
	var out: Array[int] = [maxi(1, p * (100 - spread) / 100 / 5 * 5), maxi(5, (p * (100 + spread) / 100 + 4) / 5 * 5)]
	return out


# --- Attitudes ----------------------------------------------------------------------------------

static func _meta(state: GameState, empire_id: int) -> Dictionary:
	_ensure(state)
	var m: Dictionary = state.fauna["meta"]
	if not m.has(empire_id):
		m[empire_id] = {"seen": {}, "study": {}, "stance": {}, "kills": {}, "techs": {}, "unlock": {}}
	return m[empire_id]


static func _meta_r(state: GameState, empire_id: int) -> Dictionary:
	return (state.fauna.get("meta", {}) as Dictionary).get(empire_id, {})


static func knows(state: GameState, empire_id: int, sp: String) -> bool:
	return (_meta_r(state, empire_id).get("seen", {}) as Dictionary).has(sp)


## Espèces rencontrées par l'empire, triées.
static func known_species(state: GameState, empire_id: int) -> Array[String]:
	var out: Array[String] = []
	for sp in species_ids():
		if knows(state, empire_id, sp):
			out.append(sp)
	return out


static func stance(state: GameState, empire_id: int, sp: String) -> String:
	return String((_meta_r(state, empire_id).get("stance", {}) as Dictionary).get(sp, ""))


## Fin de l'étude : > 0 en cours (jour de fin), -1 terminée, 0 jamais commencée.
static func study_end(state: GameState, empire_id: int, sp: String) -> int:
	return int((_meta_r(state, empire_id).get("study", {}) as Dictionary).get(sp, 0))


static func studied(state: GameState, empire_id: int, sp: String) -> bool:
	return study_end(state, empire_id, sp) < 0


static func kills(state: GameState, empire_id: int, sp: String) -> int:
	return int((_meta_r(state, empire_id).get("kills", {}) as Dictionary).get(sp, 0))


## Le troupeau combat-il cet empire ? Jamais les autres puissances neutres ; jamais un empire qui a
## apprivoisé l'espèce ; toujours un chasseur de l'espèce et un troupeau dérangé ; sinon selon le
## tempérament (une espèce passive laisse passer).
static func hostile(state: GameState, beast: Fleet, empire_id: int) -> bool:
	if empire_id < 0 or GameState.is_npc(empire_id):
		return false
	var h := herd_of(state, beast)
	if h.is_empty():
		var gid := Guardians.of_fleet(state, beast)
		if gid != "":
			return Guardians.hostile(state, gid, empire_id)
		# Machines des tombeaux : elles parlementent avec un peuple synthétique.
		if not beast.ships.is_empty() and String(beast.ships[0]) == "bete_machine_tombeau" and bool(talent(state, empire_id).get("parley", false)):
			return false
		return true
	var sp := String(h["sp"])
	if sp == "nuees" and bool(talent(state, empire_id).get("storm_veil", false)):
		return false
	match stance(state, empire_id, sp):
		"apprivoise":
			return false
		"chasse":
			return true
	if int(h["nest"]) < 0:
		return true
	return temper(sp) != "passive"


## L'espèce est-elle hostile à cet empire par nature (sans regarder un troupeau précis) ?
static func species_hostile(state: GameState, empire_id: int, sp: String) -> bool:
	if sp == "nuees" and bool(talent(state, empire_id).get("storm_veil", false)):
		return false
	match stance(state, empire_id, sp):
		"apprivoise":
			return false
		"chasse":
			return true
	return temper(sp) != "passive"


## Les vaisseaux sans armes de cet empire contournent-ils ce système ? (nid connu d'une espèce qui
## les attaquerait)
static func avoided(state: GameState, empire_id: int, sid: int) -> bool:
	var n: Dictionary = nests(state).get(sid, {})
	if not n.is_empty() and species_hostile(state, empire_id, String(n["sp"])):
		return true
	var gid := Guardians.awake_at(state, sid)
	return gid != "" and Guardians.hostile(state, gid, empire_id)


## Bonus de dégâts d'une flotte contre les créatures qu'elle chasse, en points de %.
static func hunt_pct(state: GameState, f: Fleet, fighters: Array) -> int:
	if GameState.is_npc(f.owner) or not active(state):
		return 0
	var vs_fauna := false
	var hunted := false
	for g in fighters:
		if (g as Fleet).owner != GameState.FAUNA_ID:
			continue
		vs_fauna = true
		var h := herd_of(state, g as Fleet)
		if not h.is_empty() and stance(state, f.owner, String(h["sp"])) == "chasse":
			hunted = true
	if not vs_fauna:
		return 0
	var pct := 0
	# Honneur : le bonus de chasse vaut contre toutes les créatures (gardiens et fléaux compris).
	if hunted or bool(talent(state, f.owner).get("hunt_all", false)):
		pct += int(attitude_def("chasse").get("damage_pct", 0))
	# Amiral « Tueur de monstres ».
	if not state.heroes.is_empty():
		var adm := Heroes.at_post(state, "fleet", f.id, f.owner)
		if not adm.is_empty():
			pct += Heroes.trait_fx(adm, "fauna_damage_pct")
	return pct


## Coût d'une attitude pour cet empire (credo de la raison : étude moins chère).
static func attitude_cost_for(state: GameState, empire_id: int, att: String) -> Dictionary:
	var cost := attitude_cost(att)
	if att == "etude":
		var pct := int(talent(state, empire_id).get("study_pct", 0))
		if pct != 0:
			return Research.scaled_amounts(cost, pct)
	return cost


static func attitude_cost(att: String) -> Dictionary:
	return (attitude_def(att).get("cost", {}) as Dictionary).duplicate()


static func check_attitude(state: GameState, empire_id: int, sp: String, att: String) -> String:
	var e := state.get_empire(empire_id)
	if e == null or e.is_npc() or e.eliminated:
		return "empire inconnu"
	if species(sp).is_empty():
		return "espèce inconnue"
	if not ATTITUDES.has(att):
		return "attitude inconnue"
	if not knows(state, empire_id, sp):
		return "vous n'avez pas encore rencontré cette espèce"
	match att:
		"etude":
			if study_end(state, empire_id, sp) > 0:
				return "l'étude est déjà en cours"
			if studied(state, empire_id, sp):
				return "l'espèce est déjà étudiée"
		"chasse":
			if stance(state, empire_id, sp) == "chasse":
				return "vous chassez déjà cette espèce"
		"apprivoise":
			if not tamable(state, empire_id, sp):
				return "cette espèce ne s'apprivoise pas"
			if stance(state, empire_id, sp) == "apprivoise":
				return "l'espèce est déjà apprivoisée"
			if bool(attitude_def("apprivoise").get("needs_study", true)) and not studied(state, empire_id, sp) and not Guardians.tame_freed(state, sp):
				return "il faut d'abord étudier l'espèce"
		"renoncer":
			if stance(state, empire_id, sp) == "":
				return "ni chasse ni apprivoisement en cours"
			return ""
	if not Economy.can_afford(e, attitude_cost_for(state, empire_id, att)):
		return "pas assez de ressources (%s)" % GameData.format_amounts(attitude_cost_for(state, empire_id, att))
	return ""


## L'espèce s'apprivoise-t-elle pour cet empire ? (credo de la survie : toutes)
static func tamable(state: GameState, empire_id: int, sp: String) -> bool:
	return bool(species(sp).get("tamable", false)) or bool(talent(state, empire_id).get("tame_all", false))


static func set_attitude(state: GameState, empire_id: int, sp: String, att: String) -> void:
	var e := state.get_empire(empire_id)
	var m := _meta(state, empire_id)
	var sd := species(sp)
	var text := ""
	match att:
		"etude":
			Economy.pay(e, attitude_cost_for(state, empire_id, att))
			m["study"][sp] = state.tick + int(attitude_def("etude").get("days", 360))
			text = "%s lance l'étude des %s. Les xénobiologistes promettent des résultats dans l'année, et des croquis dès demain." % [e.display_name(), String(sd["label"])]
		"chasse":
			Economy.pay(e, attitude_cost(att))
			m["stance"][sp] = "chasse"
			text = "%s ouvre la chasse aux %s. Les amiraux affûtent leurs canons et leurs anecdotes." % [e.display_name(), String(sd["label"])]
		"apprivoise":
			Economy.pay(e, attitude_cost(att))
			m["stance"][sp] = "apprivoise"
			text = "%s apprivoise les %s : ses vaisseaux et les troupeaux se croisent désormais sans se tirer dessus, parfois même en chantant." % [e.display_name(), String(sd["label"])]
		"renoncer":
			(m["stance"] as Dictionary).erase(sp)
			text = "%s ne chasse ni n'apprivoise plus les %s. Les troupeaux retrouvent leur humeur naturelle." % [e.display_name(), String(sd["label"])]
	for o in state.empires:
		o.path_cache.clear()
	if not e.is_ai():
		state.add_chronicle(text, Espionage.private_to(state, [empire_id]))


## Bonus des études terminées (fusionnés dans Research.effects, voir state.relic_rev).
static func effects(state: GameState, empire_id: int) -> Dictionary:
	var out := Guardians.effects(state, empire_id)
	var study: Dictionary = _meta_r(state, empire_id).get("study", {})
	if study.is_empty():
		return out
	for sp in species_ids():
		if int(study.get(sp, 0)) < 0:
			Research._merge(out, (species(sp).get("study_fx", {}) as Dictionary).duplicate(true))
	return out


# --- Événements de partie -----------------------------------------------------------------------

## Premier contact : un empire voit un troupeau (système visible ce jour-là).
static func see(state: GameState, empire_id: int, sp: String, sid: int, added: Array[Dictionary]) -> void:
	var m := _meta(state, empire_id)
	if (m["seen"] as Dictionary).has(sp):
		return
	m["seen"][sp] = state.tick
	var e := state.get_empire(empire_id)
	if e.is_ai():
		return
	var sd := species(sp)
	added.append(state.add_chronicle("Premier contact avec les %s, près de %s. %s Elles sont %s. (Chroniques, onglet Bestiaire : les étudier, les chasser%s.)" % [
			String(sd["label"]), state.galaxy.systems[sid].system_name, String(sd["text"]), temper_label(sp).to_lower(),
			" ou les apprivoiser" if bool(sd.get("tamable", false)) else ""], Espionage.private_to(state, [empire_id], sid)))


## Fin d'une bataille contre la Faune : le vainqueur ramasse le butin des créatures abattues (entier
## pour qui les chasse, moitié sinon) et compte ses prises.
static func on_battle(state: GameState, b: Dictionary, winner: int, added: Array[Dictionary]) -> void:
	if winner < 0 or GameState.is_npc(winner) or not active(state):
		return
	var we := state.get_empire(winner)
	for s: Dictionary in b["sides"]:
		if int(s["empire"]) != GameState.FAUNA_ID:
			continue
		var loot := {}
		var count := 0
		for unit in s["lost"]:
			var sp := species_of_unit(String(unit))
			if sp == "":
				continue
			var n := int(s["lost"][unit])
			count += n
			var m := _meta(state, winner)
			m["kills"][sp] = int(m["kills"].get(sp, 0)) + n
			var pct := int(attitude_def("chasse").get("loot_pct", 100)) if stance(state, winner, sp) == "chasse" else 50
			var per: Dictionary = species(sp).get("loot", {})
			for r in per:
				@warning_ignore("integer_division")
				loot[r] = int(loot.get(r, 0)) + int(per[r]) * n * pct / 100
		if loot.is_empty():
			continue
		for r in loot:
			we.resources[r] = int(we.resources.get(r, 0)) + int(loot[r])
		if not we.is_ai():
			added.append(state.add_chronicle("Les équipages de %s dépècent %d créature%s à %s : %s. Les cuisiniers de bord ont des idées ; personne ne veut les entendre." % [
					we.short_name(), count, "s" if count > 1 else "", state.galaxy.systems[int(b["system"])].system_name,
					GameData.format_amounts(loot)], Espionage.private_to(state, [winner], int(b["system"]))))


## Un nid sans troupeau, tenu par une flotte armée d'un empire hostile à l'espèce, est détruit.
static func destroy_nest(state: GameState, sid: int, empire_id: int, added: Array[Dictionary]) -> void:
	var e := state.get_empire(empire_id)
	var sp := String(nests(state)[sid]["sp"])
	var loot: Dictionary = data()["nest_loot"]
	for r in loot:
		e.resources[r] = int(e.resources.get(r, 0)) + int(loot[r])
	nests(state).erase(sid)
	for o in state.empires:
		o.path_cache.clear()
	var who: Array[int] = [empire_id]
	for o in state.empires:
		if not o.eliminated and o.explored.has(sid) and not who.has(o.id):
			who.append(o.id)
	added.append(state.add_chronicle("%s détruit le nid des %s à %s (%s). Il n'en naîtra plus ; les naturalistes portent le deuil, les mineurs sortent les foreuses." % [
			e.display_name(), String(species(sp)["label"]), state.galaxy.systems[sid].system_name, GameData.format_amounts(loot)], Espionage.public_to(state, who)))


## Piège d'une curiosité vivante : un troupeau dérangé surgit (espèce tirée de la planète).
static func spawn_trap(state: GameState, sid: int, salt: int) -> Fleet:
	var ids := species_ids()
	var sp := ids[posmod(hash([state.seed_value, "piege", sid, salt]), ids.size())]
	return spawn_herd(state, sp, sid, -1, state.tick + int(data()["trap_days"]))


# --- Sauvegarde --------------------------------------------------------------------------------

static func _sorted_pairs(d: Dictionary) -> Array:
	var keys := d.keys()
	keys.sort()
	return keys.map(func(k: Variant) -> Array: return [String(k), d[k]])


static func to_dict(state: GameState) -> Dictionary:
	if state.fauna.is_empty():
		return {}
	var out := {"density": String(state.fauna.get("density", "aucune")), "per_nest": int(state.fauna.get("per_nest", 0)),
			"nests": [], "herds": [], "meta": []}
	for sid in nest_ids(state):
		var n: Dictionary = nests(state)[sid]
		out["nests"].append({"sid": sid, "sp": String(n["sp"]), "born": int(n["born"]), "lost": int(n["lost"])})
	for fid in herd_ids(state):
		var h: Dictionary = herds(state)[fid]
		out["herds"].append({"fleet": fid, "sp": String(h["sp"]), "nest": int(h["nest"]), "next": int(h["next"]), "until": int(h["until"]), "bait": int(h.get("bait", -1))})
	var meta: Dictionary = state.fauna.get("meta", {})
	var eids := meta.keys()
	eids.sort()
	for eid in eids:
		var m: Dictionary = meta[eid]
		out["meta"].append({"e": int(eid), "seen": _sorted_pairs(m["seen"]), "study": _sorted_pairs(m["study"]),
				"stance": _sorted_pairs(m["stance"]), "kills": _sorted_pairs(m["kills"]),
				"techs": _sorted_pairs(m.get("techs", {})), "unlock": _sorted_pairs(m.get("unlock", {}))})
	out["guardians"] = Guardians.to_list(state)
	out["choke"] = Guardians.choke_list(state)
	out["plagues"] = Plagues.to_dict(state)
	out["beasts"] = WarBeasts.to_dict(state)
	return out


static func from_dict(state: GameState, d: Dictionary) -> void:
	state.fauna = {}
	if d.is_empty():
		return
	state.fauna = _empty(String(d.get("density", "aucune")))
	state.fauna["per_nest"] = int(d.get("per_nest", 0))
	for n: Dictionary in d.get("nests", []):
		nests(state)[int(n["sid"])] = {"sp": String(n["sp"]), "born": int(n["born"]), "lost": int(n["lost"])}
	for h: Dictionary in d.get("herds", []):
		herds(state)[int(h["fleet"])] = {"sp": String(h["sp"]), "nest": int(h["nest"]), "next": int(h["next"]), "until": int(h["until"]), "bait": int(h.get("bait", -1))}
	for m: Dictionary in d.get("meta", []):
		var mm := {"seen": {}, "study": {}, "stance": {}, "kills": {}, "techs": {}, "unlock": {}}
		for k in ["seen", "study", "kills", "techs", "unlock"]:
			for p: Array in m.get(k, []):
				mm[k][String(p[0])] = int(p[1])
		for p: Array in m.get("stance", []):
			mm["stance"][String(p[0])] = String(p[1])
		state.fauna["meta"][int(m["e"])] = mm
	Guardians.from_list(state, d.get("guardians", []))
	Guardians.choke_from(state, d.get("choke", []))
	Plagues.from_dict(state, d.get("plagues", {}))
	WarBeasts.from_dict(state, d.get("beasts", {}))
