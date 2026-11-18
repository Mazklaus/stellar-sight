class_name WorldForgeBridges
extends RefCounted
## La Forge des mondes et le reste du jeu : démantèlement (prop. 16-21), évacuation (prop. 18), mondes
## qu'on ne touche pas (prop. 19), Convention des mondes et Forge commune (prop. 22), réputation (prop.
## 31), sabotage (prop. 32), hauts faits et annonces (prop. 39), Grande Braderie (prop. 42).

static func _r(key: String, def := 0) -> int:
	return WorldForge.r_int(key, def)


static func _member(state: GameState, eid: int) -> bool:
	return state.amph_on and Amphictyony.founded(state) and Amphictyony.is_member(state, eid)


# --- Coûts, interdits -------------------------------------------------------------------------------

## Pour cent de coût : Atelier commun de l'Amphictyonie (prop. 22).
static func cost_pct(state: GameState, eid: int) -> int:
	var pct := 0
	if _member(state, eid):
		pct += Amphictyony.level_sum(state, "forge_shared_pct")
	return pct


## Interdits de la Convention des mondes (prop. 22), pour un membre de l'Amphictyonie.
static func site_reason(state: GameState, eid: int, op: String, _sid: int, pid: int) -> String:
	if not _member(state, eid) or not bool(WorldForge.op_def(op).get("dismantle", false)):
		return ""
	if Amphictyony.banned(state, "forge_all") and op == "demanteler":
		return "interdit par le Moratoire des mondes (Amphictyonie)"
	if op == "evacuer" and Amphictyony.banned(state, "forge_populated"):
		return "interdit par la Convention des mondes : on n'évacue plus un monde pour le défaire (Amphictyonie)"
	if op == "demanteler" and pid >= 0:
		var c: Colony = state.colonies.get(pid)
		if c != null and c.is_colony() and c.population > 0 and Amphictyony.banned(state, "forge_populated"):
			return "interdit par la Convention des mondes (Amphictyonie)"
		var t := state.galaxy.get_planet(pid).type
		if Amphictyony.banned(state, "forge_habitable") and int(GameData.planet_type(t).get("base_hab", 0)) > 0:
			return "interdit par la Convention des mondes : un monde habitable ne se démantèle pas (Amphictyonie)"
	return ""


## Une flotte ennemie (en guerre) dans le système suspend le chantier (prop. 32).
static func enemy_present(state: GameState, eid: int, sid: int) -> bool:
	for fid in state.sorted_fleet_ids():
		var f: Fleet = state.fleets[fid]
		if f.system_id == sid and not f.is_moving() and f.owner != eid and Combat.is_warfleet(f) and Combat.at_war(state, eid, f.owner):
			return true
	return false


# --- Démantèlement ------------------------------------------------------------------------------

static func _group(t: String) -> String:
	return "gas" if t == "gas_giant" else "rock"


## Ce que rend un mois de démantèlement (dont "mass").
static func dismantle_monthly(state: GameState, j: Dictionary) -> Dictionary:
	var p := state.galaxy.get_planet(int(j["p"]))
	if p == null:
		return {}
	var per: Dictionary = ((WorldForge.op_def("demanteler").get("monthly", {}) as Dictionary).get(_group(p.type), {}) as Dictionary)
	var out := {}
	for r in per:
		out[r] = int(per[r]) * maxi(1, p.size)
	return out


## Chaque jour : une géante perd une taille par an (levage, prop. 17).
static func dismantle_day(state: GameState, j: Dictionary, _added: Array[Dictionary]) -> void:
	var p := state.galaxy.get_planet(int(j["p"]))
	if p == null or p.type != "gas_giant" or p.size <= 1:
		return
	var done := int(j["tot"]) - int(j["w"])
	if done > 0 and done % 360 == 0:
		WorldForge.reshape(state, p.id, p.type, p.size - 1)


## Au lancement : mondes qu'on ne touche pas (prop. 19), digestion Kh'thari (prop. 36), voisins (prop. 31).
static func on_dismantle_start(state: GameState, eid: int, pid: int, added: Array[Dictionary]) -> void:
	var p := state.galaxy.get_planet(pid)
	var e := state.get_empire(eid)
	var nm := WorldForge.world_name(state, pid)
	var reasons := untouchable(state, eid, pid)
	var c: Colony = state.colonies.get(pid)
	var announced := false
	if c != null and c.is_colony() and c.population > 0:
		# Kh'thari : la population est digérée en nourriture.
		var food := c.population * _r("digest_food_per_pop", 25)
		e.resources["food"] = int(e.resources.get("food", 0)) + food
		for b in c.buildings:
			if Wonders.is_wonder(b):
				reasons.append("une merveille")
		state.colonies.erase(pid)
		state.rebuild_ownership()
		for x in state.empires:
			if x.id != eid and not x.is_npc() and not x.eliminated:
				Diplomacy.remember(state, x.id, eid, "world_digested")
		Announce.next(state, "forge_unmade", {"actor": eid, "system": p.system_id})
		announced = true
		added.append(state.add_chronicle("%s digère %s et ses habitants (+%d nourriture). L'Essaim appelle cela « rentabiliser » ; la galaxie entière a un autre mot." % [
				e.short_name(), nm, food]))
	if not reasons.is_empty():
		for x in state.empires:
			if x.id != eid and not x.is_npc() and not x.eliminated:
				Diplomacy.remember(state, x.id, eid, "world_unmade")
		if not announced:
			Announce.next(state, "forge_unmade", {"actor": eid, "system": p.system_id})
		added.append(state.add_chronicle("Indignation : %s a entrepris de démanteler %s (%s). Les chancelleries convoquent leurs ambassadeurs." % [
				e.short_name(), nm, ", ".join(PackedStringArray(reasons))]))
	# Voisins : un monde habitable défait à leurs portes.
	if int(GameData.planet_type(p.type).get("base_hab", 0)) > 0:
		var j := FactionTraits.jumps_from(state.galaxy, p.system_id)
		var near := {}
		for k in j:
			if int(j[k]) <= _r("near_jumps", 2):
				var o := state.system_owner(int(k))
				if o >= 0 and o != eid and not GameState.is_npc(o):
					near[o] = true
		var ids := near.keys()
		ids.sort()
		for o in ids:
			Diplomacy.remember(state, int(o), eid, "world_dismantled_near")
		if p.type == "gaia":
			for x in state.empires:
				if x.id != eid and not x.is_npc() and not x.eliminated and not near.has(x.id):
					Diplomacy.remember(state, x.id, eid, "world_dismantled_near")


## Raisons d'indignation (prop. 19) : lieu saint, monde d'origine d'un autre peuple, peuple mineur,
## site de fouille encore ouvert, monde-jardin.
static func untouchable(state: GameState, eid: int, pid: int) -> Array:
	var out: Array = []
	var p := state.galaxy.get_planet(pid)
	if state.faith_on:
		var fl: Dictionary = state.faiths.get("list", {})
		for k in fl:
			if int((fl[k] as Dictionary).get("holy", -1)) == pid:
				out.append("un lieu saint")
				break
	for x in state.empires:
		if x.id != eid and x.home_planet == pid:
			out.append("le monde d'origine des %s" % x.short_name())
	if Minors.enabled(state):
		for mid in Minors.ids(state):
			if int(Minors.get_m(state, mid).get("planet", -1)) == pid:
				out.append("le monde d'un peuple mineur")
				break
	if Relics.is_open(state, p.system_id):
		out.append("un site de fouille encore ouvert")
	if p.type == "gaia":
		out.append("un monde-jardin")
	if LivingWorlds.is_living(state, pid):
		out.append("un monde vivant")
	return out


static func dismantle_done(state: GameState, j: Dictionary, added: Array[Dictionary]) -> void:
	var pid := int(j["p"])
	var eid := int(j.get("b", j["o"]))
	var p := state.galaxy.get_planet(pid)
	var e := state.get_empire(eid)
	var sid := p.system_id
	var nm := WorldForge.world_name(state, pid)
	LivingWorlds.on_murder(state, pid, eid, added)  # un monde vivant démantelé : crime galactique
	var vanished := p.type == "asteroids" or p.type == "gas_giant"
	if vanished:
		WorldForge.remove_body(state, pid)
	else:
		if state.colonies.has(pid):
			state.colonies.erase(pid)
			state.rebuild_ownership()
		WorldForge.reshape(state, pid, "asteroids", 1)
		state.override_planet(pid, {"deposits": []})
		WorldForge.sub(state, "worlds").erase(str(pid))
	EcologyBridges.on_dismantle(state, sid, added)  # les biosphères du système encaissent (écologie, prop. 17)
	WorldForge._stat(state, eid, "dism", 1)
	state.forge["total_dism"] = int(state.forge.get("total_dism", 0)) + 1
	Announce.next(state, "forge_dismantled", {"actor": eid, "system": sid})
	added.append(state.add_chronicle("%s achève de démanteler %s : %s." % [e.short_name() if e != null else "?", nm,
			"il n'en reste rien, pas même un caillou" if vanished else "il n'en reste qu'une ceinture de cailloux"], WorldForge._who(state, eid, sid)))
	if state.galaxy.systems[sid].planet_ids.is_empty() and not WorldForge.sub(state, "void").has(str(sid)):
		WorldForge.sub(state, "void")[str(sid)] = eid
		WorldForge._stat(state, eid, "void", 1)
		added.append(state.add_chronicle("Le Grand Vide : il ne reste plus autour de %s que son étoile. %s y bâtira une Sphère ou un Essaim de Dyson à moindres frais." % [
				state.galaxy.systems[sid].system_name, e.short_name() if e != null else "Son maître"]))
	_braderie(state, added)


## Prop. 42 : la galaxie a démantelé beaucoup de mondes, les matériaux s'effondrent au marché.
static func _braderie(state: GameState, added: Array[Dictionary]) -> void:
	var n := int(state.forge.get("total_dism", 0))
	var every := _r("braderie_after", 10)
	if every <= 0 or n % every != 0 or int(state.forge.get("braderie", 0)) > state.tick:
		return
	state.forge["braderie"] = state.tick + _r("braderie_days", 1800)
	Announce.next(state, "forge_braderie", {})
	added.append(state.add_chronicle("La Grande Braderie : %d mondes démantelés, et la galaxie croule sous les cailloux. Le prix des matériaux s'effondre au marché pour cinq ans ; les mineurs manifestent, les architectes sabrent le champagne." % n))


# --- Évacuation (prop. 18) ----------------------------------------------------------------------

static func evacuate(state: GameState, eid: int, pid: int, added: Array[Dictionary]) -> void:
	var c: Colony = state.colonies.get(pid)
	var e := state.get_empire(eid)
	if c == null or e == null or c.owner != eid:
		return
	var p := state.galaxy.get_planet(pid)
	var sid := p.system_id
	var nm := WorldForge.world_name(state, pid)
	var groups: Array = []  # [espèce, nombre, intégration]
	var founder := Peoples.founder_of(state, eid)
	var own := c.population
	var sp := c.species.keys()
	sp.sort()
	for fid in sp:
		var n := int(c.species[fid])
		own -= n
		groups.append([String(fid), n, Peoples.integration(c, String(fid))])
	groups.push_front([founder, maxi(0, own), 100])
	var wonder := false
	for b in c.buildings:
		if Wonders.is_wonder(b):
			wonder = true
	state.colonies.erase(pid)
	state.rebuild_ownership()
	var moved := 0
	var refused := 0
	var k := 0
	var refuse_every := maxi(1, 100 / maxi(1, _r("evac_refuse_pct", 25)))
	for g: Array in groups:
		for i in int(g[1]):
			k += 1
			if k % refuse_every == 0:
				refused += 1
				Movements.flee_from(state, sid, String(g[0]), 1, eid, added)
				continue
			var dest := _dest(state, eid, String(g[0]))
			if dest == null:
				refused += 1
				Movements.flee_from(state, sid, String(g[0]), 1, eid, added)
				continue
			Movements.add_one(state, dest, String(g[0]), int(g[2]))
			moved += 1
	var item := {"id": -1, "card": "", "system": sid, "planet": -1, "rival": -1, "hero": -1}
	Events.apply_fx(state, eid, item, [{"k": "stab", "v": _r("evac_stab", -2), "days": _r("evac_stab_days", 360), "scope": "empire"}], added)
	if wonder:
		for x in state.empires:
			if x.id != eid and not x.is_npc() and not x.eliminated:
				Diplomacy.remember(state, x.id, eid, "world_unmade")
	Announce.next(state, "forge_evacuated", {"actor": eid, "system": sid})
	added.append(state.add_chronicle("Évacuation de %s achevée : %d habitants relogés dans les autres colonies de %s, %d ont refusé et sont partis sur les routes. Le monde est vide ; plus rien n'empêche de le défaire." % [
			nm, moved, e.short_name(), refused], WorldForge._who(state, eid, sid)))


static func _dest(state: GameState, eid: int, fid: String) -> Colony:
	var best: Colony = null
	var best_room := 0
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner != eid or not c.is_colony() or not c.is_established():
			continue
		var room := Movements._room(state, c, fid)
		if room > best_room:
			best_room = room
			best = c
	return best


# --- Mondes créés, commandes ---------------------------------------------------------------------

static func on_made(state: GameState, eid: int, _pid: int, _op: String, added: Array[Dictionary]) -> void:
	var stab := WorldForge.t_int(state, eid, "made_stab")
	if stab > 0:
		var item := {"id": -1, "card": "", "system": -1, "planet": -1, "rival": -1, "hero": -1}
		Events.apply_fx(state, eid, item, [{"k": "stab", "v": stab, "days": 360, "scope": "empire"}], added)
	WorldForge.touch(state)


## Commande de monde terminée (prop. 13) : le monde est à l'acheteur, le bâtisseur s'en souvient.
static func on_order_done(state: GameState, j: Dictionary, pid: int, added: Array[Dictionary]) -> void:
	var buyer := int(j["for"])
	var seller := int(j.get("b", -1))
	if buyer < 0 or seller < 0:
		return
	WorldForge.mark_world(state, pid, "custom", buyer)
	Diplomacy.remember(state, buyer, seller, "world_ordered")
	WorldForge._stat(state, seller, "orders", 1)
	added.append(state.add_chronicle("%s livre à %s la planète commandée : %s. Satisfait ou remboursé, dit le contrat ; personne n'a jamais rendu une planète." % [
			state.get_empire(seller).short_name(), state.get_empire(buyer).short_name(), WorldForge.world_name(state, pid)], Espionage.private_to(state, [buyer, seller], int(j["s"]))))


# --- Mois après mois ----------------------------------------------------------------------------

static func monthly(state: GameState, added: Array[Dictionary]) -> void:
	# Masse des démantèlements (talent Brisecomète, Forge commune du Koinon).
	for id in WorldForge.job_ids(state):
		var j := WorldForge.get_job(state, id)
		if String(j["op"]) != "demanteler":
			continue
		var eid := int(j.get("b", j["o"]))
		var y := dismantle_monthly(state, j)
		var m := int(y.get("mass", 0))
		var p := state.galaxy.get_planet(int(j["p"]))
		if p != null and WorldForge.sub(state, "debris").has(str(p.id)):
			m += 2
		m = m * (100 + WorldForge.t_int(state, eid, "mass_pct")) / 100
		_share_mass(state, eid, m)
	_integrity(state, added)


static func _share_mass(state: GameState, eid: int, m: int) -> void:
	if m <= 0:
		return
	if state.koinon_on and Koinon.is_member(state, eid):
		var others: Array[int] = []
		for x in Koinon.members_of(state, Koinon.league_of(state, eid)):
			if x != eid:
				others.append(x)
		if not others.is_empty():
			var share := m * _r("koinon_share_pct", 25) / 100
			var each := share / others.size()
			if each > 0:
				for x in others:
					WorldForge.add_mass(state, x, each)
				m -= each * others.size()
	WorldForge.add_mass(state, eid, m)


## Intégrité (prop. 15) : sans entretien, la jauge baisse ; à zéro, le monde retombe.
static func _integrity(state: GameState, added: Array[Dictionary]) -> void:
	var w := WorldForge.sub(state, "worlds")
	var keys := w.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return int(a) < int(b))
	for k in keys:
		var pid := int(k)
		var wd: Dictionary = w[k]
		var up := int((WorldForge.cfg("worlds").get(String(wd.get("k", "")), {}) as Dictionary).get("upkeep", 0))
		if up <= 0:
			continue
		var o := WorldForge.holder(state, pid)
		var e := state.get_empire(o) if o >= 0 else null
		var integ := int(wd.get("integ", 100))
		var before := integ
		if e == null or GameState.is_npc(o) or int(e.resources.get("energy", 0)) <= 0:
			integ -= _r("integrity_loss", 10)
		else:
			integ = mini(100, integ + _r("integrity_gain", 5))
		wd["integ"] = integ
		var nm := WorldForge.world_name(state, pid)
		var sid := state.galaxy.get_planet(pid).system_id
		if before >= _r("breach_at", 50) and integ < _r("breach_at", 50):
			Announce.next(state, "forge_breach", {"target": o, "system": sid})
			added.append(state.add_chronicle("Brèche sur %s : faute d'entretien, la structure craque (intégrité %d %%). Payez l'énergie, ou elle cédera." % [nm, integ],
					Espionage.private_to(state, [o] if o >= 0 else [], sid)))
		if integ <= 0:
			_fall(state, pid, String(wd.get("k", "")), added)


static func _fall(state: GameState, pid: int, k: String, added: Array[Dictionary]) -> void:
	var fall := String((WorldForge.cfg("worlds").get(k, {}) as Dictionary).get("fall", ""))
	var p := state.galaxy.get_planet(pid)
	var nm := WorldForge.world_name(state, pid)
	var c: Colony = state.colonies.get(pid)
	if c != null and c.is_colony() and c.population > 0:
		var n := c.population
		var fid := Peoples.founder_of(state, c.owner)
		var owner := c.owner
		state.colonies.erase(pid)
		state.rebuild_ownership()
		Movements.flee_from(state, p.system_id, fid, n, owner, added)
	elif c != null:
		state.colonies.erase(pid)
		state.rebuild_ownership()
	WorldForge.sub(state, "worlds").erase(str(pid))
	if fall != "":
		WorldForge.reshape(state, pid, fall, 1 if fall == "asteroids" else -1)
	added.append(state.add_chronicle("%s s'effondre : la structure n'a plus tenu. Ses habitants ont fui ; il ne reste qu'un monde %s." % [nm, Megastructures.planet_label(fall if fall != "" else p.type)]))


# --- Renseignement (prop. 32) ---------------------------------------------------------------------

static func spy_check(state: GameState, _a: int, b: int, op_id: String) -> String:
	if not WorldForge.enabled(state):
		return "la Forge des mondes n'est pas en jeu dans cette partie"
	if op_id == "breche_monde" and _breach_target(state, b) == -1:
		return "il ne tient ni chantier planétaire ni monde façonné"
	return ""


static func spy_apply(state: GameState, _a: int, b: int, o: Dictionary) -> String:
	if String(o.get("id", "")) != "breche_monde":
		return ""
	var be := state.get_empire(b)
	for id in WorldForge.job_ids(state):
		var j := WorldForge.get_job(state, id)
		if int(j["o"]) == b:
			j["w"] = int(j["w"]) + 120
			return "nos agents ont ouvert une brèche dans le chantier planétaire de %s : 120 jours de retard." % be.display_name()
	var pid := _breach_target(state, b)
	if pid < 0:
		return ""
	var wd := WorldForge.world(state, pid)
	wd["integ"] = maxi(1, int(wd.get("integ", 100)) - 40)
	return "nos agents ont ouvert une brèche dans %s, monde façonné de %s : intégrité %d %%." % [WorldForge.world_name(state, pid), be.display_name(), int(wd["integ"])]


static func _breach_target(state: GameState, b: int) -> int:
	for id in WorldForge.job_ids(state):
		if int(WorldForge.get_job(state, id)["o"]) == b:
			return -2
	var w := WorldForge.sub(state, "worlds")
	var keys := w.keys()
	keys.sort_custom(func(x: Variant, y: Variant) -> bool: return int(x) < int(y))
	for k in keys:
		var up := int((WorldForge.cfg("worlds").get(String((w[k] as Dictionary).get("k", "")), {}) as Dictionary).get("upkeep", 0))
		if up > 0 and WorldForge.holder(state, int(k)) == b:
			return int(k)
	return -1


# --- Hauts faits (prop. 39) ---------------------------------------------------------------------

static func deed_value(state: GameState, eid: int, k: String) -> int:
	if not WorldForge.enabled(state):
		return 0
	match k:
		"forge_made":
			return WorldForge.stat(state, eid, "made")
		"forge_void":
			return WorldForge.stat(state, eid, "void")
	return 0
