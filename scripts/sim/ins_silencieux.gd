class_name InsSilencieux
extends RefCounted
## Silencieux (props 71 à 76 ; voir Insolites, data/insolites.json "silencieux").
## Des machines non conscientes : immunisées à la culture, à la foi, à la psionique, aux intrigues et à la
## diplomatie (ni opinion, ni traité : Diplomacy.no_treaties), incapables d'innover.
##   - Pas de recherche : ni Savoir ni file de recherche ; leurs technologies viennent des épaves et des
##     prises (rétro-ingénierie quatre fois plus efficace, champ research.wreck_pct de la brique Machines)
##     et des ruines (Strates).
##   - Efficacité : production très haute, pas de stabilité (talent de stabilité), habitants assemblés ;
##     un avant-poste de replicate_days peut se répliquer en usine (une colonie de 1 population).
##   - Directive lisible : affichée à tous (chronique publique, fiche du peuple) ; « Extraire les métaux
##     de… », « Étendre les usines vers… », « Écarter l'obstacle de… ». Leur IA attaque ce qui gêne la
##     directive, jamais par haine.
##   - Pas de victoire propre : Conquête ou Domination seulement (Victory.progress).
##   - Choc des tons : la Noosphère de Teyl (gouvernement Conscience) peut éveiller une usine, qui devient
##     un peuple mineur conscient.
##
## État (Insolites.emp) : "dir": {"k", "sid", "until"}, "woke": {empire: jour de fin de l'attente}.


static func _c(key: String, def := 0) -> int:
	return Insolites.c_int("silencieux", key, def)


static func found(_state: GameState, _e: Empire, _sid: int, ed: Dictionary) -> void:
	ed["dir"] = {}
	ed["woke"] = {}


static func is_silent(state: GameState, eid: int) -> bool:
	return not state.insolites.is_empty() and Insolites.kind(state, eid) == "silencieux"


# --- Directive (prop. 74) ----------------------------------------------------------------------------

static func directive(state: GameState, eid: int) -> Dictionary:
	return Insolites.emp(state, eid).get("dir", {})


static func directive_text(state: GameState, eid: int) -> String:
	var d := directive(state, eid)
	if d.is_empty():
		return "Directive : en attente"
	var df: Dictionary = (Insolites.cfg("silencieux").get("directives", {}) as Dictionary).get(String(d["k"]), {})
	var sname := state.galaxy.systems[int(d["sid"])].system_name
	return "Directive : " + String(df.get("label", "%s")) % (sname if String(d["k"]) == "etendre" else _de(sname))


static func _de(n: String) -> String:
	var low := n.to_lower()
	if not low.is_empty() and "aeiouyéèêàâîïôûh".contains(low.substr(0, 1)):
		return "d'" + n
	return Crisis.de_name(n)


## Choisit la prochaine directive : le meilleur système à portée de la capitale, par ordre de valeur.
static func _pick(state: GameState, eid: int, added: Array[Dictionary]) -> void:
	var e := state.get_empire(eid)
	var cap := FactionTraits.capital_system(state, eid)
	if cap < 0:
		return
	var d: Dictionary = FactionTraits.jumps_from(state.galaxy, cap)
	var best := -1
	var best_v := -1
	var keys := d.keys()
	keys.sort()
	for sid in keys:
		var j := int(d[sid])
		if j <= 0 or j > _c("directive_jumps", 6) or not e.explored.has(int(sid)):
			continue
		var owner := state.system_owner(int(sid))
		if owner == eid:
			continue
		var v := state.galaxy.systems[int(sid)].planet_ids.size() * 10 - j * 3 + posmod(hash([state.seed_value, eid, sid, state.tick / 360]), 7)
		if owner >= 0 and not GameState.is_npc(owner):
			v += 5
		if v > best_v:
			best_v = v
			best = int(sid)
	var k := ""
	if best >= 0:
		var owner2 := state.system_owner(best)
		k = "eliminer" if owner2 >= 0 and owner2 != eid and not GameState.is_npc(owner2) else ("extraire" if state.galaxy.systems[best].planet_ids.size() >= 3 else "etendre")
	# Directives acquises (Catalogue des acquisitions) : Démonter les épaves d'un champ de bataille à
	# portée, sinon, une fois sur trois ou faute de cible, Optimiser leur système le plus peuplé.
	var open := unlocked(state, eid)
	var turn := posmod(hash([state.seed_value, eid, state.tick / 30, "directive"]), 3)
	if open.has("demonter") and turn != 0:
		var wsid := -1
		for sid in keys:
			if int(d[sid]) <= _c("directive_jumps", 6) and int(state.battle_wrecks.get(int(sid), 0)) > 0 and e.explored.has(int(sid)):
				wsid = int(sid)
				break
		if wsid >= 0:
			best = wsid
			k = "demonter"
	if open.has("optimiser") and k != "demonter" and (best < 0 or turn == 0):
		var top := -1
		var top_pop := 0
		for pid in state.sorted_colony_ids():
			var c: Colony = state.colonies[pid]
			if c.owner == eid and c.population > top_pop:
				top_pop = c.population
				top = state.galaxy.get_planet(int(pid)).system_id
		if top >= 0:
			best = top
			k = "optimiser"
	if best < 0 or k == "":
		return
	Insolites.emp(state, eid)["dir"] = {"k": k, "sid": best, "until": state.tick + _c("directive_days", 720)}
	added.append(state.add_chronicle("Sur toutes les fréquences, en clair, les Silencieux affichent une nouvelle ligne. %s." % directive_text(state, eid).trim_prefix("Directive : "),
			Espionage.public_to(state, [eid])))


## Technologies acquises : tout ce que savent les Silencieux vient d'une épave, d'une prise ou d'une ruine.
static func acquisitions(state: GameState, eid: int) -> int:
	return state.get_empire(eid).techs.size()


## Directives ouvertes, dans l'ordre des données : sans seuil, ou seuil "need" d'acquisitions atteint.
static func unlocked(state: GameState, eid: int) -> Array[String]:
	var out: Array[String] = []
	var n := acquisitions(state, eid)
	var dirs: Dictionary = Insolites.cfg("silencieux").get("directives", {})
	for k in dirs:
		if not String(k).begins_with("_") and int((dirs[k] as Dictionary).get("need", 0)) <= n:
			out.append(String(k))
	return out


## Directive tournée vers eux-mêmes (Optimiser) : elle ne s'achève pas quand le système est à eux.
static func _inward(k: String) -> bool:
	return k == "optimiser"


## Production d'une colonie en % de plus : Optimiser les chaînes de son système.
static func colony_pct(state: GameState, pid: int) -> int:
	var c: Colony = state.colonies.get(pid)
	if c == null or Insolites.kind(state, c.owner) != "silencieux":
		return 0
	var d := directive(state, c.owner)
	if d.is_empty() or String(d["k"]) != "optimiser" or int(d["sid"]) != state.galaxy.get_planet(pid).system_id:
		return 0
	return _c("optimize_pct", 20)


## Épaves en % (Research.study_wrecks) : Démonter les épaves, où qu'on se batte tant que la directive dure.
static func salvage_pct(state: GameState, eid: int) -> int:
	if Insolites.kind(state, eid) != "silencieux":
		return 100
	var d := directive(state, eid)
	return _c("salvage_pct", 200) if not d.is_empty() and String(d["k"]) == "demonter" else 100


## Empire qui gêne la directive (-1 sinon) : celui qui tient le système visé.
static func obstacle(state: GameState, eid: int) -> int:
	var d := directive(state, eid)
	if d.is_empty():
		return -1
	if _inward(String(d["k"])):
		return -1
	var o := state.system_owner(int(d["sid"]))
	return o if o >= 0 and o != eid and not GameState.is_npc(o) else -1


# --- Réplication (prop. 73) --------------------------------------------------------------------------

static func _replicate(state: GameState, eid: int, added: Array[Dictionary]) -> void:
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner != eid or c.is_colony() or not c.is_established():
			continue
		var p := state.galaxy.get_planet(int(pid))
		if Economy.max_pop(state, p, eid) <= 0:
			continue
		var h := hash([state.seed_value, state.tick, pid, "replique"])
		if posmod(h, 1000) >= _c("replicate_pmille", 150):
			continue
		c.kind = Colony.KIND_COLONY
		c.population = 1
		state.rebuild_ownership()
		added.append(state.add_chronicle("Sur %s, l'avant-poste des Silencieux s'est répliqué : il y a maintenant une usine, et elle fabrique d'autres machines." % p.display_name(state.galaxy),
				Espionage.public_to(state, [eid])))
		return  # une usine par mois au plus


static func daily(state: GameState, eid: int, ed: Dictionary, month: bool, added: Array[Dictionary]) -> void:
	if not month:
		return
	var d: Dictionary = ed.get("dir", {})
	if d.is_empty() or int(d["until"]) <= state.tick or (state.system_owner(int(d["sid"])) == eid and not _inward(String(d["k"]))):
		_pick(state, eid, added)
	if state.tick >= _c("replicate_days", 720):
		_replicate(state, eid, added)
	var e := state.get_empire(eid)
	e.research_queue.clear()  # ils n'inventent pas
	e.research_progress = 0


# --- Éveil d'une usine par la Noosphère (prop. 76) ---------------------------------------------------

static func check_awaken(state: GameState, eid: int, pid: int) -> String:
	var e := state.get_empire(eid)
	if String(e.faction().get("species", {}).get("gouvernement", "")) != "conscience":
		return "seule une Noosphère (gouvernement Conscience) sait éveiller une machine"
	var c: Colony = state.colonies.get(pid)
	if c == null or not c.is_colony() or not is_silent(state, c.owner):
		return "il faut viser une usine des Silencieux"
	if not Minors.enabled(state):
		return "les peuples mineurs ne sont pas actifs dans cette partie"
	var woke: Dictionary = Insolites.emp(state, c.owner).get("woke", {})
	if int(woke.get(str(eid), 0)) > state.tick:
		return "la Noosphère se remet de sa dernière tentative (%d jours)" % (int(woke[str(eid)]) - state.tick)
	var sid := state.galaxy.get_planet(pid).system_id
	var near := false
	for opid in state.sorted_colony_ids():
		var oc: Colony = state.colonies[opid]
		if oc.owner == eid and oc.is_colony():
			var d: Dictionary = FactionTraits.jumps_from(state.galaxy, state.galaxy.get_planet(int(opid)).system_id)
			if int(d.get(sid, 999)) <= _c("awaken_jumps", 4):
				near = true
				break
	if not near:
		return "l'usine est trop loin du réseau (%d sauts au plus d'une colonie)" % _c("awaken_jumps", 4)
	var cost: Dictionary = Insolites.cfg("silencieux").get("awaken_cost", {})
	if not Economy.can_afford(e, cost):
		return "ressources insuffisantes (il faut %s)" % GameData.format_amounts(cost)
	return ""


static func awaken(state: GameState, eid: int, pid: int, added: Array[Dictionary]) -> void:
	var c: Colony = state.colonies[pid]
	var sil := c.owner
	Economy.pay(state.get_empire(eid), Insolites.cfg("silencieux").get("awaken_cost", {}))
	(Insolites.emp(state, sil)["woke"] as Dictionary)[str(eid)] = state.tick + _c("awaken_cd_days", 360)
	var p := state.galaxy.get_planet(pid)
	var h := hash([state.seed_value, state.tick, pid, eid, "eveil"])
	if posmod(h, 1000) >= _c("awaken_pmille", 350):
		added.append(state.add_chronicle("La Noosphère de %s tend la main vers l'usine de %s. L'usine répond par un inventaire de pièces détachées. Ce n'est pas encore une conversation." % [
				state.get_empire(eid).short_name(), p.display_name(state.galaxy)], Espionage.public_to(state, [eid, sil])))
		return
	if MinorsLife.secession(state, p.system_id, sil, added):
		var mid := Minors.at_system(state, p.system_id)
		if mid >= 0:
			var m := Minors.get_m(state, mid)
			m["name"] = "Éveillés de %s" % state.galaxy.systems[p.system_id].system_name
			m["short"] = "Éveillés"
			(m["fav"] as Dictionary)[eid] = 60
			(m["contact"] as Dictionary)[eid] = state.tick
		added.append(state.add_chronicle("Sur %s, une usine des Silencieux s'arrête net, puis demande, sur une fréquence que personne n'utilisait : « Pourquoi ? » La Noosphère de %s lui répond. Un peuple est né." % [
				p.display_name(state.galaxy), state.get_empire(eid).short_name()]))


# --- Branchements ------------------------------------------------------------------------------------

## Victoires permises (prop. 75) : la force seulement.
static func victory_allowed(state: GameState, eid: int, id: String) -> bool:
	return not is_silent(state, eid) or (Insolites.cfg("silencieux").get("force_victories", ["conquete", "domination"]) as Array).has(id)


static func status_lines(state: GameState, eid: int, _ed: Dictionary) -> Array[String]:
	var out: Array[String] = [directive_text(state, eid)]
	var open := unlocked(state, eid)
	out.append("Catalogue des acquisitions : %d technologies acquises ; directives ouvertes : %s" % [acquisitions(state, eid),
			", ".join(PackedStringArray(open.map(func(k: String) -> String: return String(Insolites.cfg("silencieux")["directives"][k]["label"]).replace(" %s", "").to_lower())))])
	var ob := obstacle(state, eid)
	if ob >= 0:
		out.append("Obstacle à la directive : %s" % state.get_empire(ob).display_name())
	return out
