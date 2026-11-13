class_name Movements
extends RefCounted
## Mouvements de population (étude « Populations mixtes et migrations », lot 3 : propositions 16 à 24).
## - Migration intérieure (option de partie « migrations ») : chaque trimestre, une colonie qui pousse
##   (pleine, en famine, instable, mal adaptée à une espèce) envoie un habitant vers la colonie qui
##   attire le plus cette espèce, à 6 sauts au plus ; aussi vers un empire lié par un traité de
##   migration (voir Diplomacy.MIGRATION).
## - Réfugiés : conquête, révolte, expulsion, extermination, famine, sécession. Ils partent vers la
##   colonie d'accueil la plus proche selon l'ordre de Stellaris (habitabilité >= 70 % avec de la
##   place, puis >= 70 %, >= 50 % avec de la place, >= 50 %), dans un empire dont la politique
##   d'accueil les accepte. Sans refuge : un convoi de réfugiés erre sur la carte, peut être pris par
##   les pirates, et fonde au bout de 3 ans une colonie Sans-Bannière.
## - Diaspora : le peuple d'un empire disparu (IA) peut renaître sur un monde où il est majoritaire et
##   en Révolte (ou déjà libre), ou réclamer un système à l'empire qui l'accueille (21 bis).
## - Sécession par affinité : un monde en sécession dont la majorité est d'une autre espèce rejoint
##   l'empire de cette espèce s'il touche sa frontière.
## Tout est déterministe (colonies triées, tirages hachés sur le jour).
## Règles : data/rules.json "movements". Données : state.moves (sauvegardées).
##
## state.moves : "policy" {empire: politique d'accueil}, "convoys" [{id, fid, n, sid, born, from}],
## "next_id", "refuge" {planète: [réfugiés, jusqu'au jour]}, "claims" {empire: {fid, end}},
## "claim_next" {empire: jour}, "refused" {fid: true}, "fx" {empire: [{fid, v, end}]},
## "frict" {système: jusqu'au jour}.

const POLICIES := ["fermee", "citoyens", "ouverte"]
const POLICY_LABELS := {"fermee": "Fermée", "citoyens": "Peuples citoyens seulement", "ouverte": "Ouverte"}


static func data() -> Dictionary:
	return GameData.rules().get("movements", {})


## Réfugiés, convois et diaspora suivent les peuples mêlés ; la migration intérieure a son option.
static func enabled(state: GameState) -> bool:
	return state.peoples_on


static func migrations_on(state: GameState) -> bool:
	return state.peoples_on and state.migrations_on


static func _m(state: GameState, key: String) -> Dictionary:
	if not state.moves.has(key):
		state.moves[key] = {}
	return state.moves[key]


# --- Talents de peuple (proposition 24) ----------------------------------------------------------

## Talents déjà calculés, par fiche d'espèce (lus dans des boucles chaudes : production, refuges).
static var _talents := {}


## Talents de peuples mêlés d'un empire, couches additionnées (data/rules.json movements.talents).
static func talent(state: GameState, empire_id: int) -> Dictionary:
	if GameState.is_npc(empire_id):
		return {}
	var e := state.get_empire(empire_id)
	if e == null:
		return {}
	var sp: Dictionary = e.faction().get("species", {})
	var ck := "%s:%d" % [e.faction_id, hash(sp)]
	if not _talents.has(ck):
		_talents[ck] = _talent_of(sp)
	return _talents[ck]


static func _talent_of(sp: Dictionary) -> Dictionary:
	var out := {}
	var table: Dictionary = data().get("talents", {})
	var keys: Array = []
	for layer in ["archetype", "gouvernement", "credo"]:
		keys.append([layer, String(sp.get(layer, ""))])
	for t in sp.get("traits", []):
		keys.append(["traits", String(t)])
	for k: Array in keys:
		var t: Dictionary = (table.get(k[0], {}) as Dictionary).get(k[1], {})
		for x in t:
			if x == "label" or x == "text":
				continue
			out[x] = int(out.get(x, 0)) + int(t[x])
	return out


## Talents à afficher : [[nom, texte], …].
static func talent_labels(state: GameState, empire_id: int) -> Array:
	var out := []
	var e := state.get_empire(empire_id)
	if e == null or GameState.is_npc(empire_id):
		return out
	var sp: Dictionary = e.faction().get("species", {})
	var table: Dictionary = data().get("talents", {})
	for layer in ["archetype", "gouvernement", "credo"]:
		var t: Dictionary = (table.get(layer, {}) as Dictionary).get(String(sp.get(layer, "")), {})
		if t.has("label"):
			out.append([String(t["label"]), String(t.get("text", ""))])
	for tr in sp.get("traits", []):
		var t: Dictionary = (table.get("traits", {}) as Dictionary).get(String(tr), {})
		if t.has("label"):
			out.append([String(t["label"]), String(t.get("text", ""))])
	return out


# --- Luxe aimé (proposition 23) -----------------------------------------------------------------

## Luxe préféré d'une espèce : celui des règles, sinon tiré de son identifiant (peuples créés).
static func loved(fid: String) -> String:
	var m: Dictionary = data().get("loved", {})
	if m.has(fid):
		return String(m[fid])
	var ids := Goods.luxury_ids()
	if ids.is_empty() or fid == "":
		return ""
	return ids[absi(hash(fid)) % ids.size()]


## L'empire sert-il le luxe aimé de cette espèce (gisement, licence ou contrebande) ?
static func loved_served(state: GameState, empire_id: int, fid: String) -> bool:
	if not enabled(state) or GameState.is_npc(empire_id) or not Goods.active(state):
		return false
	var g := loved(fid)
	return g != "" and Goods.has_luxury(state, empire_id, g)


# --- Déplacer un habitant ------------------------------------------------------------------------

## Habitants d'une espèce sur une colonie (espèce du propriétaire comprise).
static func count_of(state: GameState, c: Colony, fid: String) -> int:
	if fid == Peoples.founder_of(state, c.owner):
		return Peoples.own_count(c)
	return int(c.species.get(fid, 0))


## Retire un habitant d'une espèce (renvoie false s'il n'y en a pas).
static func remove_one(state: GameState, c: Colony, fid: String) -> bool:
	if count_of(state, c, fid) <= 0 or c.population <= 0:
		return false
	c.population -= 1
	if fid != Peoples.founder_of(state, c.owner):
		c.species[fid] = int(c.species[fid]) - 1
		if int(c.species[fid]) <= 0:
			c.species.erase(fid)
			c.integ.erase(fid)
	return true


## Ajoute un habitant d'une espèce, arrivé avec une intégration donnée (moyenne avec ceux déjà là).
@warning_ignore("integer_division")
static func add_one(state: GameState, c: Colony, fid: String, integ: int) -> void:
	c.population += 1
	if fid == Peoples.founder_of(state, c.owner) or fid == "":
		return
	var n := int(c.species.get(fid, 0))
	var old := Peoples.integration(c, fid) if n > 0 else integ
	c.species[fid] = n + 1
	c.integ[fid] = (old * n + integ) / (n + 1)


static func _sid(state: GameState, c: Colony) -> int:
	return state.galaxy.get_planet(c.planet_id).system_id


static func _room(state: GameState, c: Colony, fid: String) -> int:
	var p := state.galaxy.get_planet(c.planet_id)
	return Economy.max_pop(state, p, c.owner, c.buildings, fid) - c.population


# --- Migration intérieure et traité de migration (propositions 16 et 17) -------------------------

## Pourquoi une colonie pousse ses habitants dehors ("" : elle ne pousse pas).
static func push_reason(state: GameState, c: Colony) -> String:
	var e := state.get_empire(c.owner)
	if e == null or c.population < 2:
		return ""
	if e.starving:
		return "famine"
	if not Stability.growth_ok(state, _sid(state, c)):
		return "instable"
	var p := state.galaxy.get_planet(c.planet_id)
	var cap := Economy.max_pop(state, p, c.owner, c.buildings)
	if cap > 0 and c.population * 100 >= cap * int(data().get("crowded_pct", 90)):
		return "pleine"
	for fid in c.species:
		if Peoples.hab(state, c.owner, String(fid), p.type) < Peoples.BIRTH_HAB:
			return "inadaptee"
	return ""


## Espèce qui part : la moins bien adaptée (inadaptée), sinon la plus nombreuse.
static func _leaver(state: GameState, c: Colony, reason: String) -> String:
	var cnt := Peoples.counts(state, c)
	var p := state.galaxy.get_planet(c.planet_id)
	var best := ""
	var bk := 0
	for fid in Peoples._sorted_keys(cnt):
		var k: int
		if reason == "inadaptee":
			k = 1000 - Peoples.hab(state, c.owner, fid, p.type)
		else:
			k = int(cnt[fid])
		if best == "" or k > bk:
			best = fid
			bk = k
	return best


## Empires vers lesquels les habitants d'un empire migrent : lui-même et ses partenaires de traité.
static func partners(state: GameState, empire_id: int) -> Array[int]:
	var out: Array[int] = [empire_id]
	var e := state.get_empire(empire_id)
	if e == null:
		return out
	var cs: Array = e.contacts.duplicate()
	cs.sort()
	for o in cs:
		if Diplomacy.has_migration(state, empire_id, int(o)):
			out.append(int(o))
	return out


## Colonie d'arrivée d'un migrant : place libre, habitabilité, jeunesse, stabilité, distance.
static func migration_dest(state: GameState, src: Colony, fid: String, owners: Array[int]) -> Colony:
	var jumps := FactionTraits.jumps_from(state.galaxy, _sid(state, src))
	var src_hab := Peoples.hab(state, src.owner, fid, state.galaxy.get_planet(src.planet_id).type)
	var best: Colony = null
	var bs := -1000000
	var max_j := int(data().get("migration_jumps", 6))
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c == src or not c.is_colony() or not c.is_established() or not owners.has(c.owner):
			continue
		var j := int(jumps.get(_sid(state, c), 99))
		if j > max_j:
			continue
		var h := Peoples.hab(state, c.owner, fid, state.galaxy.get_planet(pid).type)
		if h < Peoples.BIRTH_HAB:
			continue
		var room := _room(state, c, fid)
		if room <= 0:
			continue
		var s := room * 10 + h - src_hab + Stability.value(state, _sid(state, c)) - j * 5
		if c.population < int(data().get("young_pop", 5)):
			s += int(data().get("young_bonus", 100))
		# Partir à l'étranger (traité de migration) : seulement pour bien mieux qu'à la maison.
		if c.owner != src.owner:
			s -= int(data().get("abroad_penalty", 150))
		if s > bs:
			bs = s
			best = c
	return best


## Bilan trimestriel (décalé selon l'empire) : quelques migrants par empire. Mensuel avec le trait de
## migration ou Spatioports de transit.
@warning_ignore("integer_division")
static func _migrate(state: GameState, e: Empire, month: int, added: Array[Dictionary]) -> void:
	var fast := FactionTraits.migrates(state, e.id)
	if not fast and posmod(month + e.id, 3) != 0:
		return
	var owners := partners(state, e.id)
	var cap := int(data().get("migrants_per_turn", 3))
	# Un accord commercial avec un partenaire de migration double le flux.
	for o in owners:
		if o != e.id and Diplomacy.has_trade(state, e.id, o):
			cap *= 2
			break
	var moved := 0
	var abroad := 0
	var abroad_cap := int(data().get("abroad_per_turn", 1))
	var home_only: Array[int] = [e.id]
	for pid in state.sorted_colony_ids():
		if moved >= cap:
			break
		var c: Colony = state.colonies[pid]
		if c.owner != e.id or not c.is_colony() or not c.is_established():
			continue
		var why := push_reason(state, c)
		if why == "":
			continue
		var fid := _leaver(state, c, why)
		if fid == "":
			continue
		var dest := migration_dest(state, c, fid, owners if abroad < abroad_cap else home_only)
		if dest == null:
			continue
		if dest.owner != e.id:
			abroad += 1
		var integ := 100 if fid == e.faction_id else Peoples.integration(c, fid)
		if dest.owner != e.id:
			integ = mini(integ, int(data().get("treaty_integration", 75)))
			if fid == Peoples.founder_of(state, dest.owner):
				integ = 100
		if remove_one(state, c, fid):
			add_one(state, dest, fid, integ)
			moved += 1


# --- Réfugiés et politique d'accueil (propositions 18 et 19) -------------------------------------

static func policy(state: GameState, empire_id: int) -> String:
	var p := String(_m(state, "policy").get(str(empire_id), ""))
	return p if POLICIES.has(p) else String(data().get("default_policy", "citoyens"))


static func check_policy(state: GameState, empire_id: int, p: String) -> String:
	if not enabled(state):
		return "les peuples mêlés ne sont pas actifs dans cette partie"
	var e := state.get_empire(empire_id)
	if e == null or e.eliminated:
		return "empire inconnu"
	if not POLICIES.has(p):
		return "politique inconnue : %s" % p
	if policy(state, empire_id) == p:
		return "c'est déjà votre politique d'accueil"
	return ""


static func set_policy(state: GameState, empire_id: int, p: String) -> void:
	_m(state, "policy")[str(empire_id)] = p


## L'empire accepte-t-il des réfugiés de cette espèce ?
static func accepts(state: GameState, empire_id: int, fid: String) -> bool:
	if GameState.is_npc(empire_id):
		return false
	var e := state.get_empire(empire_id)
	if e == null or e.eliminated:
		return false
	match policy(state, empire_id):
		"ouverte":
			return true
		"citoyens":
			return fid == e.faction_id or Peoples.status(state, empire_id, fid) == "citoyens"
	return false


## Colonie d'accueil la plus proche, dans l'ordre de Stellaris. exclude : empires qu'ils fuient.
static func refuge_for(state: GameState, from_sid: int, fid: String, exclude: Array) -> Colony:
	var jumps := FactionTraits.jumps_from(state.galaxy, from_sid)
	var best: Colony = null
	var bk := 1 << 40
	var ok_cache := {}
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if not c.is_colony() or not c.is_established() or exclude.has(c.owner):
			continue
		if not ok_cache.has(c.owner):
			ok_cache[c.owner] = accepts(state, c.owner, fid)
		if not ok_cache[c.owner]:
			continue
		var h := Peoples.hab(state, c.owner, fid, state.galaxy.get_planet(pid).type)
		if h < 50:
			continue
		var room := _room(state, c, fid) > 0
		var tier := 0 if (h >= 70 and room) else (1 if h >= 70 else (2 if room else 3))
		# Les Murmurants (et leurs semblables) attirent ceux « qui les ont entendus ».
		if int(talent(state, c.owner).get("refugee_pull", 0)) > 0:
			tier = maxi(0, tier - 1)
		var k := tier * 100000 + int(jumps.get(_sid(state, c), 999)) * 100 + 0
		if k < bk:
			bk = k
			best = c
	return best


## Accueille un réfugié sur une colonie : influence, nourriture, opinion de son empire d'origine,
## stabilité des réfugiés reconnaissants.
static func welcome(state: GameState, c: Colony, fid: String, n := 1) -> void:
	var tl := talent(state, c.owner)
	var integ := int(data().get("refugee_integration", 50))
	if int(tl.get("refugee_integration", 0)) > 0:
		integ = maxi(integ, int(tl["refugee_integration"]))
	if int(Laws.effects(state, c.owner).get("integration_pct", 0)) > 0:
		integ = mini(100, integ * (100 + int(Laws.effects(state, c.owner)["integration_pct"])) / 100)
	for i in n:
		add_one(state, c, fid, integ)
	var e := state.get_empire(c.owner)
	e.resources["influence"] = int(e.resources.get("influence", 0)) + n * int(data().get("refugee_influence", 2))
	e.resources["food"] = int(e.resources.get("food", 0)) - n * int(data().get("refugee_food", 5))
	var rf := _m(state, "refuge")
	var key := str(c.planet_id)
	var cur: Array = rf.get(key, [0, 0])
	rf[key] = [int(cur[0]) + n, state.tick + int(data().get("refugee_days", 3600))]
	for o in state.empires:
		if not o.eliminated and o.faction_id == fid and o.id != c.owner:
			Diplomacy.remember(state, o.id, c.owner, "refugees_welcomed")


## Des habitants fuient une colonie : vers un refuge, sinon en convoi. Renvoie le nombre parti.
static func flee(state: GameState, c: Colony, fid: String, n: int, exclude: Array, added: Array[Dictionary]) -> int:
	if not enabled(state) or n <= 0:
		return 0
	var gone := 0
	var stray := 0
	var sid := _sid(state, c)
	for i in n:
		if c.population <= 1 or not remove_one(state, c, fid):
			break
		gone += 1
		var dest := refuge_for(state, sid, fid, exclude)
		if dest != null:
			welcome(state, dest, fid)
		else:
			stray += 1
	if stray > 0:
		_new_convoy(state, sid, fid, stray, c.owner, added)
	return gone


## Réfugiés qui ont déjà quitté leur monde (extermination, expulsion déjà décomptées).
static func flee_from(state: GameState, sid: int, fid: String, n: int, from_owner: int, added: Array[Dictionary]) -> void:
	if not enabled(state) or n <= 0:
		return
	var stray := 0
	for i in n:
		var dest := refuge_for(state, sid, fid, [from_owner])
		if dest != null:
			welcome(state, dest, fid)
		else:
			stray += 1
	if stray > 0:
		_new_convoy(state, sid, fid, stray, from_owner, added)


## Monde conquis : 1 habitant sur 5 de chaque espèce qui n'est pas celle du conquérant s'enfuit.
@warning_ignore("integer_division")
static func on_conquest(state: GameState, sid: int, conqueror: int, added: Array[Dictionary]) -> void:
	if not enabled(state):
		return
	var cf := Peoples.founder_of(state, conqueror)
	var div := maxi(1, int(data().get("conquest_flee_div", 5)))
	for pid in state.galaxy.systems[sid].planet_ids:
		var c: Colony = state.colonies.get(pid)
		if c == null or c.owner != conqueror or not c.is_colony():
			continue
		var cnt := Peoples.counts(state, c)
		for fid in Peoples._sorted_keys(cnt):
			if fid == cf:
				continue
			flee(state, c, fid, int(cnt[fid]) / div, [conqueror], added)
	_loot(state, sid, conqueror)


## Horde : quelques vaincus suivent le butin jusqu'à la capitale (talent loot_pops).
static func _loot(state: GameState, sid: int, conqueror: int) -> void:
	var n := int(talent(state, conqueror).get("loot_pops", 0))
	if n <= 0:
		return
	var e := state.get_empire(conqueror)
	var cap: Colony = state.colonies.get(e.capital_planet) if e.capital_planet >= 0 else null
	if cap == null or _sid(state, cap) == sid:
		return
	for pid in state.galaxy.systems[sid].planet_ids:
		var c: Colony = state.colonies.get(pid)
		if c == null or c.owner != conqueror or c.species.is_empty():
			continue
		for fid in Peoples._sorted_keys(c.species):
			while n > 0 and c.population > 1 and int(c.species.get(fid, 0)) > 0:
				remove_one(state, c, fid)
				add_one(state, cap, fid, 0)
				n -= 1
	return


## Sécession : 1 sur 5 des fidèles (l'espèce de l'ancien maître) fuient vers lui ou ailleurs.
@warning_ignore("integer_division")
static func on_secession(state: GameState, sid: int, old_owner: int, new_owner: int, added: Array[Dictionary]) -> void:
	if not enabled(state):
		return
	var of := Peoples.founder_of(state, old_owner)
	if of == "":
		return
	for pid in state.galaxy.systems[sid].planet_ids:
		var c: Colony = state.colonies.get(pid)
		if c == null or c.owner != new_owner or not c.is_colony():
			continue
		var n := count_of(state, c, of) / maxi(1, int(data().get("conquest_flee_div", 5)))
		flee(state, c, of, n, [new_owner], added)


## Famine : l'habitant perdu s'enfuit au lieu de mourir (appelé à la place de la perte habituelle).
static func on_famine(state: GameState, c: Colony, added: Array[Dictionary]) -> bool:
	if not enabled(state) or c.population <= 1:
		return false
	var fid := _leaver(state, c, "pleine")
	return flee(state, c, fid, 1, [c.owner], added) > 0


# --- Convois de réfugiés (proposition 20) --------------------------------------------------------

static func convoys(state: GameState) -> Array:
	if not state.moves.has("convoys"):
		state.moves["convoys"] = []
	return state.moves["convoys"]


static func _new_convoy(state: GameState, sid: int, fid: String, n: int, from_owner: int, added: Array[Dictionary]) -> void:
	# Un convoi de la même espèce déjà dans le système grossit plutôt que d'en créer un autre.
	for cv: Dictionary in convoys(state):
		if int(cv["sid"]) == sid and String(cv["fid"]) == fid:
			cv["n"] = int(cv["n"]) + n
			return
	var id := int(state.moves.get("next_id", 1))
	state.moves["next_id"] = id + 1
	convoys(state).append({"id": id, "fid": fid, "n": n, "sid": sid, "born": state.tick, "from": from_owner})
	added.append(state.add_chronicle("Un convoi de %d réfugiés %s quitte %s sans savoir où aller. Ils ont emporté des couvertures, des souvenirs et très peu de carburant." % [
			n, Peoples.label(fid), state.galaxy.systems[sid].system_name], Espionage.public_to(state, [])))


## Convois présents dans un système (pour la carte).
static func convoys_at(state: GameState, sid: int) -> Array:
	var out := []
	for cv: Dictionary in convoys(state):
		if int(cv["sid"]) == sid:
			out.append(cv)
	return out


static func _armed_guard(state: GameState, sid: int) -> bool:
	for f in Fleets.fleets_at(state, sid):
		if not GameState.is_npc(f.owner) and f.owner != GameState.PIRATE_ID and Combat.is_armed(f):
			return true
	return false


## Un mois de convoi : trouver un refuge, sinon errer d'un saut ; les pirates guettent ; au bout de
## 3 ans, se poser sur le monde libre le plus proche (colonie Sans-Bannière).
static func _convoys_month(state: GameState, added: Array[Dictionary]) -> void:
	var keep := []
	for cv: Dictionary in convoys(state):
		var sid := int(cv["sid"])
		var fid := String(cv["fid"])
		var n := int(cv["n"])
		var dest := refuge_for(state, sid, fid, [int(cv["from"])])
		if dest != null:
			welcome(state, dest, fid, n)
			added.append(state.add_chronicle("Le convoi de réfugiés %s trouve enfin refuge sur %s (%s) : %d habitants débarquent, épuisés et reconnaissants." % [
					Peoples.label(fid), state.galaxy.get_planet(dest.planet_id).display_name(state.galaxy), state.get_empire(dest.owner).short_name(), n], Espionage.public_to(state, [dest.owner])))
			continue
		if Pirates.is_lair(state, sid) and not _armed_guard(state, sid):
			added.append(state.add_chronicle("Des pirates capturent le convoi de réfugiés %s près de %s. Ils parlent déjà de rançon." % [
					Peoples.label(fid), state.galaxy.systems[sid].system_name], Espionage.public_to(state, [])))
			continue
		if state.tick - int(cv["born"]) >= int(data().get("convoy_days", 1080)):
			if _settle(state, cv, added):
				continue
		var nb: Array = state.galaxy.systems[sid].neighbors.duplicate()
		nb.sort()
		if not nb.is_empty():
			cv["sid"] = int(nb[absi(hash([state.seed_value, state.tick, int(cv["id"]), "convoi"])) % nb.size()])
		keep.append(cv)
	state.moves["convoys"] = keep


static func _settle(state: GameState, cv: Dictionary, added: Array[Dictionary]) -> bool:
	var fid := String(cv["fid"])
	var jumps := FactionTraits.jumps_from(state.galaxy, int(cv["sid"]))
	var best: Planet = null
	var bj := 99
	for s in state.galaxy.systems:
		var j := int(jumps.get(s.id, 99))
		if j >= bj or state.system_owner(s.id) >= 0:
			continue
		for pid in s.planet_ids:
			if state.colonies.has(pid):
				continue
			var p := state.galaxy.get_planet(pid)
			if Economy.habitability(p.type, GameData.faction(fid)) >= Peoples.BIRTH_HAB:
				best = p
				bj = j
				break
	if best == null:
		return false
	var c := Colony.new()
	c.planet_id = best.id
	c.owner = GameState.NPC_ID
	c.kind = Colony.KIND_COLONY
	c.population = int(cv["n"])
	c.species = {fid: int(cv["n"])}
	state.add_colony(c)
	state.rebuild_ownership()
	added.append(state.add_chronicle("Après trois ans d'errance, les réfugiés %s se posent sur %s et y fondent une colonie libre. Personne ne leur a demandé leur avis ; c'est la première fois depuis longtemps." % [
			Peoples.label(fid), best.display_name(state.galaxy)], Espionage.public_to(state, [])))
	return true


# --- Diaspora, renaissance, revendications (propositions 21 et 21 bis) ---------------------------

## Empire disparu d'une espèce (une IA éliminée), null sinon.
static func dead_empire(state: GameState, fid: String) -> Empire:
	for e in state.empires:
		if e.faction_id == fid and e.eliminated and e.is_ai():
			return e
	return null


## Habitants d'une espèce dans toute la galaxie (Sans-Bannière compris).
static func diaspora(state: GameState, fid: String) -> int:
	var n := 0
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.is_established():
			n += int(Peoples.counts(state, c).get(fid, 0)) if not GameState.is_npc(c.owner) else int(c.species.get(fid, 0))
	return n


## Espèce majoritaire d'un système (colonies établies d'un propriétaire) et sa part en %.
@warning_ignore("integer_division")
static func majority(state: GameState, sid: int, owner: int) -> Array:
	var cnt := {}
	for pid in state.galaxy.systems[sid].planet_ids:
		var c: Colony = state.colonies.get(pid)
		if c == null or c.owner != owner or not c.is_colony() or not c.is_established():
			continue
		var cc := Peoples.counts(state, c) if not GameState.is_npc(owner) else c.species
		for fid in cc:
			cnt[fid] = int(cnt.get(fid, 0)) + int(cc[fid])
	var total := 0
	var best := ""
	for fid in Peoples._sorted_keys(cnt):
		total += int(cnt[fid])
		if best == "" or int(cnt[fid]) > int(cnt[best]):
			best = fid
	if best == "" or total <= 0:
		return ["", 0]
	return [best, int(cnt[best]) * 100 / total]


## Fait renaître un empire disparu dans un système (qui lui est transféré).
static func revive(state: GameState, e: Empire, sid: int, from_owner: int, added: Array[Dictionary]) -> void:
	e.eliminated = false
	Stability._transfer(state, sid, from_owner, e.id)
	var best := -1
	var bp := -1
	for pid in state.galaxy.systems[sid].planet_ids:
		var c: Colony = state.colonies.get(pid)
		if c != null and c.owner == e.id and c.population > bp:
			best = pid
			bp = c.population
	e.capital_planet = best
	var start: Dictionary = data().get("revival_resources", {})
	for r in start:
		e.resources[r] = maxi(int(e.resources.get(r, 0)), int(start[r]))
	e.explored[sid] = true
	for n in state.galaxy.systems[sid].neighbors:
		e.explored[n] = true
	if not GameState.is_npc(from_owner) and not e.contacts.has(from_owner):
		e.contacts.append(from_owner)
		var fo := state.get_empire(from_owner)
		if fo != null and not fo.contacts.has(e.id):
			fo.contacts.append(e.id)
	state.stability.erase(sid)
	if state.politics_on and Politics.applies(state, e.id):
		Politics._emp_w(state, e.id)
	added.append(state.add_chronicle("Renaissance ! %s renaît à %s. Ses peuples dispersés n'avaient jamais cessé de chanter ses hymnes, un peu faux." % [
			e.display_name(), state.galaxy.systems[sid].system_name], Espionage.public_to(state, [e.id])))


## Bilan mensuel des diasporas : renaissance sur un monde majoritaire en Révolte (ou libre).
static func _renaissance(state: GameState, added: Array[Dictionary]) -> void:
	var need := int(data().get("diaspora_min", 15))
	for e in state.empires:
		if not e.eliminated or not e.is_ai():
			continue
		var fid := e.faction_id
		var need_e := need - (int(data().get("refused_bonus", 5)) if bool(_m(state, "refused").get(fid, false)) else 0)
		if diaspora(state, fid) < need_e:
			continue
		for s in state.galaxy.systems:
			var owner := state.system_owner(s.id)
			if owner < 0:
				continue
			var free := GameState.is_npc(owner)
			if not free and (owner == GameState.PIRATE_ID or Stability.tier_id(state, s.id) != "revolte"):
				continue
			var mj := majority(state, s.id, owner)
			if String(mj[0]) != fid or int(mj[1]) <= 50:
				continue
			revive(state, e, s.id, owner, added)
			break


## Revendication de diaspora en cours dans un empire ({} aucune) : {"fid", "end"}.
static func claim(state: GameState, empire_id: int) -> Dictionary:
	return _m(state, "claims").get(str(empire_id), {})


@warning_ignore("integer_division")
static func _claims(state: GameState, e: Empire, added: Array[Dictionary]) -> void:
	var key := str(e.id)
	var cur := claim(state, e.id)
	if not cur.is_empty():
		if state.tick >= int(cur["end"]):
			answer_claim(state, e.id, "refus", added)
		return
	if state.tick < int(_m(state, "claim_next").get(key, 0)):
		return
	var pop := maxi(1, Laws.empire_pop(state, e.id))
	var fp := Peoples.foreign_pop(state, e.id)
	for fid in Peoples._sorted_keys(fp):
		var n := int(fp[fid])
		if dead_empire(state, fid) == null or n < int(data().get("diaspora_min", 15)) or n * 100 < pop * int(data().get("claim_pct", 10)):
			continue
		_m(state, "claims")[key] = {"fid": fid, "end": state.tick + int(data().get("claim_days", 720))}
		if not e.is_ai():
			added.append(state.add_chronicle("%s : la diaspora %s (%d habitants) demande une terre à elle : un de vos systèmes, ou le droit de s'installer sur un monde libre voisin (écran Colonies)." % [
					e.short_name(), Peoples.label(fid), n], Espionage.private_to(state, [e.id])))
		return


## Système de l'empire où la diaspora est la plus nombreuse (-1 aucun).
static func claim_system(state: GameState, empire_id: int, fid: String) -> int:
	var best := -1
	var bn := 0
	for sid in Stability.systems_of(state, empire_id):
		if sid == FactionTraits.capital_system(state, empire_id):
			continue
		var n := 0
		for pid in state.galaxy.systems[sid].planet_ids:
			var c: Colony = state.colonies.get(pid)
			if c != null and c.owner == empire_id:
				n += int(c.species.get(fid, 0))
		if n > bn:
			best = sid
			bn = n
	return best


## Monde libre voisin (système sans maître, à 3 sauts au plus de l'empire) où la diaspora peut vivre.
static func claim_planet(state: GameState, empire_id: int, fid: String) -> int:
	var best := -1
	var bk := 1 << 30
	var f := GameData.faction(fid)
	for sid in Stability.systems_of(state, empire_id):
		var jumps := FactionTraits.jumps_from(state.galaxy, sid)
		for s in state.galaxy.systems:
			var j := int(jumps.get(s.id, 99))
			if j > int(data().get("claim_jumps", 3)) or state.system_owner(s.id) >= 0:
				continue
			for pid in s.planet_ids:
				if state.colonies.has(pid):
					continue
				var p := state.galaxy.get_planet(pid)
				var h := Economy.habitability(p.type, f)
				if h < Peoples.BIRTH_HAB:
					continue
				var k := j * 1000 - h * 5 + pid % 997
				if k < bk:
					bk = k
					best = pid
	return best


static func check_claim(state: GameState, empire_id: int, choice: String) -> String:
	var cl := claim(state, empire_id)
	if cl.is_empty():
		return "aucune revendication de diaspora en cours"
	var fid := String(cl["fid"])
	match choice:
		"systeme":
			if claim_system(state, empire_id, fid) < 0:
				return "aucun système (hors capitale) où vivent les %s" % Peoples.label(fid)
		"neutre":
			if claim_planet(state, empire_id, fid) < 0:
				return "aucun monde libre à leur offrir à moins de %d sauts" % int(data().get("claim_jumps", 3))
		"refus":
			pass
		_:
			return "réponse inconnue : %s" % choice
	return ""


@warning_ignore("integer_division")
static func answer_claim(state: GameState, empire_id: int, choice: String, added: Array[Dictionary]) -> void:
	var cl := claim(state, empire_id)
	if cl.is_empty():
		return
	var fid := String(cl["fid"])
	var key := str(empire_id)
	_m(state, "claims").erase(key)
	_m(state, "claim_next")[key] = state.tick + int(data().get("claim_cooldown", 1800))
	var e := state.get_empire(empire_id)
	var dead := dead_empire(state, fid)
	var fx: Array = _m(state, "fx").get(key, [])
	if choice == "refus" or dead == null:
		_m(state, "refused")[fid] = true
		fx.append({"fid": fid, "v": int(data().get("claim_refused", -5)), "end": state.tick + int(data().get("claim_fx_days", 720))})
		_m(state, "fx")[key] = fx
		added.append(state.add_chronicle("%s refuse une terre à la diaspora %s. Elle s'en souviendra, et parle désormais de renaissance à voix haute." % [
				e.short_name(), Peoples.label(fid)], Espionage.public_to(state, [empire_id])))
		return
	if choice == "systeme":
		var sid := claim_system(state, empire_id, fid)
		revive(state, dead, sid, empire_id, added)
	else:
		var pid := claim_planet(state, empire_id, fid)
		var n := mini(int(data().get("claim_settlers", 5)), int(Peoples.foreign_pop(state, empire_id).get(fid, 0)))
		var c := Colony.new()
		c.planet_id = pid
		c.owner = GameState.NPC_ID
		c.kind = Colony.KIND_COLONY
		c.population = 0
		state.add_colony(c)
		# Les colons viennent des colonies de l'empire où ils sont les plus nombreux.
		var taken := 0
		while taken < n:
			var src: Colony = null
			for xpid in state.sorted_colony_ids():
				var x: Colony = state.colonies[xpid]
				if x.owner == empire_id and x.population > 1 and int(x.species.get(fid, 0)) > 0 \
						and (src == null or int(x.species[fid]) > int(src.species[fid])):
					src = x
			if src == null:
				break
			remove_one(state, src, fid)
			taken += 1
		c.population = maxi(1, taken)
		c.species = {fid: c.population}
		state.rebuild_ownership()
		revive(state, dead, state.galaxy.get_planet(pid).system_id, GameState.NPC_ID, added)
	# Accord : la paix entre l'hôte et le peuple qui renaît, et leur gratitude.
	var r := Diplomacy._rel_w(state, empire_id, dead.id)
	r["pact"] = Diplomacy.PEACE
	r["since"] = state.tick
	r["truce"] = state.tick + Diplomacy.days("truce_days", 360)
	Diplomacy.remember(state, dead.id, empire_id, "diaspora_granted")
	fx.append({"fid": fid, "v": int(data().get("claim_granted", 5)), "end": state.tick + int(data().get("claim_fx_days", 720))})
	_m(state, "fx")[key] = fx
	added.append(state.add_chronicle("%s accorde une terre à la diaspora %s : %s renaît, en paix avec son hôte. On signe, on pleure un peu, on promet de s'écrire." % [
			e.short_name(), Peoples.label(fid), dead.display_name()], Espionage.public_to(state, [empire_id, dead.id])))


# --- Sécession par affinité (proposition 22) -----------------------------------------------------

## Empire vers lequel un système en sécession bascule (-1 : les Sans-Bannière, comme avant).
static func affinity_target(state: GameState, sid: int, owner: int) -> int:
	if not enabled(state):
		return -1
	var mj := majority(state, sid, owner)
	var fid := String(mj[0])
	if fid == "" or fid == Peoples.founder_of(state, owner) or int(mj[1]) <= 50:
		return -1
	for e in state.empires:
		if e.eliminated or e.faction_id != fid or e.id == owner or e.is_npc():
			continue
		for n in state.galaxy.systems[sid].neighbors:
			if state.system_owner(n) == e.id:
				return e.id
	return -1


# --- Stabilité (réfugiés, revendications, frictions attisées) ------------------------------------

@warning_ignore("integer_division")
static func stability_parts(state: GameState, sid: int, owner: int) -> Array:
	var out := []
	if not enabled(state) or state.moves.is_empty():
		return out
	var rf: Dictionary = state.moves.get("refuge", {})
	if not rf.is_empty():
		var n := 0
		var pop := 0
		for pid in state.galaxy.systems[sid].planet_ids:
			var c: Colony = state.colonies.get(pid)
			if c == null or c.owner != owner:
				continue
			pop += c.population
			var r: Array = rf.get(str(pid), [])
			if not r.is_empty() and int(r[1]) > state.tick:
				n += mini(int(r[0]), c.population)
		if n > 0 and pop > 0:
			var v := maxi(1, int(data().get("refugee_stability", 10)) * n / pop)
			out.append(["Réfugiés reconnaissants (%d)" % n, v])
	var fx: Array = (state.moves.get("fx", {}) as Dictionary).get(str(owner), [])
	if not fx.is_empty():
		var cnt: Dictionary = Peoples.system_counts(state, sid, owner)["cnt"]
		for f: Dictionary in fx:
			if int(f["end"]) > state.tick and int(cnt.get(String(f["fid"]), 0)) > 0:
				out.append(["Diaspora %s %s" % [Peoples.label(String(f["fid"])), "exaucée" if int(f["v"]) > 0 else "éconduite"], int(f["v"])])
	var fr: Dictionary = state.moves.get("frict", {})
	if int(fr.get(str(sid), 0)) > state.tick:
		out.append(["Frictions attisées par des agents étrangers", int(data().get("stir_stability", -15))])
	return out


# --- Bilan mensuel -------------------------------------------------------------------------------

@warning_ignore("integer_division")
static func monthly(state: GameState, added: Array[Dictionary]) -> void:
	if not enabled(state):
		return
	var month := state.tick / int(GameData.rules()["month_days"])
	# Révolte : un habitant par colonie et par mois s'enfuit (la plus nombreuse des autres espèces).
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if GameState.is_npc(c.owner) or c.owner == GameState.PIRATE_ID or not c.is_colony() or not c.is_established() or c.population <= 1:
			continue
		if Stability.tier_id(state, _sid(state, c)) != "revolte":
			continue
		var fid := ""
		var bn := 0
		for x in Peoples._sorted_keys(c.species):
			if int(c.species[x]) > bn:
				fid = x
				bn = int(c.species[x])
		if fid == "":
			fid = Peoples.founder_of(state, c.owner)
		flee(state, c, fid, 1, [c.owner], added)
	if migrations_on(state):
		for e in state.empires:
			if not e.eliminated and not e.is_npc():
				_migrate(state, e, month, added)
	_convoys_month(state, added)
	_renaissance(state, added)
	for e in state.empires:
		if not e.eliminated and not e.is_npc():
			_claims(state, e, added)
	# Ménage : réfugiés reconnaissants, effets échus, frictions attisées.
	var rf := _m(state, "refuge")
	for k in rf.keys():
		if int(rf[k][1]) <= state.tick or not state.colonies.has(int(k)):
			rf.erase(k)
	var fxs := _m(state, "fx")
	for k in fxs.keys():
		var keep := []
		for f: Dictionary in fxs[k]:
			if int(f["end"]) > state.tick:
				keep.append(f)
		if keep.is_empty():
			fxs.erase(k)
		else:
			fxs[k] = keep
	for key in ["frict", "xeno"]:
		var fr := _m(state, key)
		for k in fr.keys():
			if int(fr[k]) <= state.tick:
				fr.erase(k)


# --- Espionnage (proposition 23) -----------------------------------------------------------------

## Système le plus mêlé d'un empire (-1 aucun) : la plus forte part d'autres espèces.
@warning_ignore("integer_division")
static func most_mixed(state: GameState, empire_id: int) -> int:
	var best := -1
	var bs := 0
	for sid in Stability.systems_of(state, empire_id):
		var cnt: Dictionary = Peoples.system_counts(state, sid, empire_id)["cnt"]
		var total := 0
		for fid in cnt:
			total += int(cnt[fid])
		var own := int(cnt.get(Peoples.founder_of(state, empire_id), 0))
		if total <= 0 or total == own:
			continue
		var s := (total - own) * 100 / total
		if s > bs:
			bs = s
			best = sid
	return best


## Propagande xénophobe : jours restants chez l'empire (0 aucune).
static func xeno_left(state: GameState, empire_id: int) -> int:
	return maxi(0, int((state.moves.get("xeno", {}) as Dictionary).get(str(empire_id), 0)) - state.tick)


static func xeno(state: GameState, empire_id: int) -> void:
	_m(state, "xeno")[str(empire_id)] = state.tick + int(data().get("xeno_days", 720))
	if state.politics_on and Politics.applies(state, empire_id):
		for sid in Stability.systems_of(state, empire_id):
			for cur in ["glaive", "autel"]:
				Politics.push(state, sid, Politics.index_of(cur), int(data().get("xeno_push", 6)))


static func stir(state: GameState, sid: int) -> void:
	_m(state, "frict")[str(sid)] = state.tick + int(data().get("stir_days", 360))


## Appel au retour : des habitants de l'espèce de a qui vivent chez b émigrent vers a.
static func call_home(state: GameState, a: int, b: int) -> int:
	var fid := state.get_empire(a).faction_id
	var n := int(data().get("call_home", 3))
	var moved := 0
	while moved < n:
		var src: Colony = null
		for pid in state.sorted_colony_ids():
			var c: Colony = state.colonies[pid]
			if c.owner == b and c.population > 1 and int(c.species.get(fid, 0)) > 0 and (src == null or int(c.species[fid]) > int(src.species[fid])):
				src = c
		if src == null:
			break
		var dest := migration_dest(state, src, fid, [a])
		if dest == null:
			var ea := state.get_empire(a)
			dest = state.colonies.get(ea.capital_planet) if ea.capital_planet >= 0 else null
		if dest == null:
			break
		remove_one(state, src, fid)
		add_one(state, dest, fid, 100)
		moved += 1
	return moved


# --- Sauvegarde ----------------------------------------------------------------------------------

static func setup(state: GameState, mode: String) -> void:
	state.migrations_on = mode == "actives"
	state.moves = {}


static func to_dict(state: GameState) -> Dictionary:
	var d := state.moves.duplicate(true)
	d["on"] = state.migrations_on
	return d


static func from_dict(state: GameState, d: Dictionary) -> void:
	state.migrations_on = bool(d.get("on", false))
	state.moves = d.duplicate(true)
	state.moves.erase("on")
	if state.moves.has("next_id"):
		state.moves["next_id"] = int(state.moves["next_id"])
	var cvs: Array = state.moves.get("convoys", [])
	var out := []
	for cv: Dictionary in cvs:
		out.append({"id": int(cv["id"]), "fid": String(cv["fid"]), "n": int(cv["n"]), "sid": int(cv["sid"]), "born": int(cv["born"]), "from": int(cv["from"])})
	if state.moves.has("convoys"):
		state.moves["convoys"] = out
	var rf: Dictionary = state.moves.get("refuge", {})
	for k in rf:
		rf[k] = [int(rf[k][0]), int(rf[k][1])]
	for key in ["claim_next", "frict", "xeno"]:
		var m: Dictionary = state.moves.get(key, {})
		for k in m:
			m[k] = int(m[k])
	var cl: Dictionary = state.moves.get("claims", {})
	for k in cl:
		cl[k] = {"fid": String(cl[k]["fid"]), "end": int(cl[k]["end"])}
	var fx: Dictionary = state.moves.get("fx", {})
	for k in fx:
		var arr := []
		for f: Dictionary in fx[k]:
			arr.append({"fid": String(f["fid"]), "v": int(f["v"]), "end": int(f["end"])})
		fx[k] = arr
