class_name InsMyrr
extends RefCounted
## Sporemère de Myrr (props 94 à 99 ; voir Insolites, data/insolites.json "myrr").
## Aucun vaisseau : elle ensemence des comètes et colonise lentement, mais irrémédiablement.
##   - Comètes-semences : lancées vers un système à comet_jumps sauts au plus d'une de ses colonies, elles
##     voyagent comet_days_per_jump jours par saut ; à l'arrivée, le mycélium s'installe sur une planète libre.
##     Une seconde comète vers le même système divise par deux le temps qui reste. Ni vaisseau ni
##     revendication, jamais (Insolites.ship_block, claim_block).
##   - Irrémédiable : chaque mois, dans un système ensemencé et pas brûlé, le mycélium gagne une planète :
##     une planète libre devient une colonie de Myrr, un avant-poste étranger change de main, une colonie
##     étrangère reçoit un implant « mycélium » qui lui prend un habitant par mois (Myrr en gagne un) ;
##     à un seul habitant, la colonie est absorbée. Seul le feu l'arrête : purger le mycélium (le brûler,
##     dégâts écologiques), brûler une colonie de Myrr depuis l'orbite (ordre « Brûler » d'une flotte en
##     guerre), ou la bombarder (combat au sol complet) : le système ne pousse plus pendant burn_days.
##     Et on n'envahit pas un système de Myrr qui n'a pas brûlé (invade_block) : le mycélium repousse.
##   - Réseau mycorhizien : les systèmes de Myrr reliés de proche en proche à la capitale produisent
##     normalement ; ceux que le feu a isolés produisent iso_pct %.
##   - Défense sans flotte : les spores usent chaque jour les flottes ennemies dans ses systèmes (spore_pct %
##     de la coque, sans jamais achever un vaisseau) ; garnisons renforcées (brique) ; défenses planétaires
##     connues d'emblée (defense_techs : citadelles, bastions, boucliers planétaires).
##   - Symbiose : chaque espèce absorbée donne un trait de symbiose (data : symbiosis, par archétype).
##   - Victoire : la Biosphère unique (biosphere.pct % des planètes habitables de la galaxie), ouverte aussi
##     aux végétaux de survie (le Hallier de Vergemonde).
##
## État (Insolites.emp) : "comets": [{"sid", "left"}], "sym": [espèces absorbées], "iso": [systèmes isolés],
## "absorbed". Galaxie : state.insolites "burned": {sid: jour de fin}.


static func _c(key: String, def := 0) -> int:
	return Insolites.c_int("myrr", key, def)


static func found(_state: GameState, e: Empire, _sid: int, ed: Dictionary) -> void:
	# Défense sans flotte (prop. 97) : la Sporemère sait d'emblée armer ses mondes.
	for t in Insolites.cfg("myrr").get("defense_techs", []):
		e.techs[String(t)] = true
	e.tech_fx_n = -1
	ed["comets"] = []
	ed["sym"] = []
	ed["iso"] = []
	ed["absorbed"] = 0


static func is_myrr(state: GameState, eid: int) -> bool:
	return not state.insolites.is_empty() and Insolites.kind(state, eid) == "myrr"


static func mothers(state: GameState) -> Array[int]:
	var out: Array[int] = []
	for eid in Insolites.nomad_ids(state):
		if Insolites.kind(state, eid) == "myrr":
			out.append(eid)
	return out


## Systèmes où Myrr a au moins une colonie fondée, triés.
static func seeded(state: GameState, eid: int) -> Array[int]:
	var out: Array[int] = []
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner == eid and c.is_established():
			var sid := state.galaxy.get_planet(int(pid)).system_id
			if not out.has(sid):
				out.append(sid)
	out.sort()
	return out


static func burned(state: GameState, sid: int) -> bool:
	return int((state.insolites.get("burned", {}) as Dictionary).get(str(sid), 0)) > state.tick


static func _free_planets(state: GameState, sid: int) -> Array[int]:
	var out: Array[int] = []
	for pid in state.galaxy.systems[sid].planet_ids:
		if not state.colonies.has(pid) and not Insolites.is_eaten(state, int(pid)) and Insolites.colony_block(state, int(pid)) == "":
			out.append(int(pid))
	return out


static func _new_colony(state: GameState, eid: int, pid: int, days: int) -> Colony:
	var p := state.galaxy.get_planet(pid)
	var c := Colony.new()
	c.planet_id = pid
	c.owner = eid
	c.kind = Colony.KIND_COLONY if Economy.max_pop(state, p, eid) > 0 else Colony.KIND_OUTPOST
	c.population = 1 if c.kind == Colony.KIND_COLONY else 0
	c.days_left = days
	state.colonies[pid] = c
	state.rebuild_ownership()
	return c


# --- Comètes-semences (prop. 94) ---------------------------------------------------------------------

static func comet_range(state: GameState, eid: int, sid: int) -> int:
	var best := 999
	for s in seeded(state, eid):
		best = mini(best, int(FactionTraits.jumps_from(state.galaxy, s).get(sid, 999)))
	return best


static func check_comet(state: GameState, eid: int, sid: int) -> String:
	if not is_myrr(state, eid):
		return "seule la Sporemère lance des comètes-semences"
	if sid < 0 or sid >= state.galaxy.systems.size():
		return "système inconnu"
	if not state.get_empire(eid).explored.has(sid):
		return "système inexploré"
	if seeded(state, eid).has(sid):
		return "le mycélium y pousse déjà"
	var o := state.system_owner(sid)
	if o >= 0 and o != eid:
		return "système revendiqué par un autre empire : le mycélium y viendra de proche en proche"
	if _free_planets(state, sid).is_empty():
		return "aucune planète libre où tomber"
	if comet_range(state, eid, sid) > _c("comet_jumps", 5):
		return "trop loin (%d sauts au plus d'une colonie)" % _c("comet_jumps", 5)
	var comets: Array = Insolites.emp(state, eid).get("comets", [])
	var stacking := false
	for cm: Dictionary in comets:
		stacking = stacking or int(cm["sid"]) == sid
	if not stacking and comets.size() >= _c("comet_max", 2):
		return "trop de comètes en vol (%d au plus)" % _c("comet_max", 2)
	var cost: Dictionary = Insolites.cfg("myrr").get("comet_cost", {})
	if not Economy.can_afford(state.get_empire(eid), cost):
		return "ressources insuffisantes (il faut %s)" % GameData.format_amounts(cost)
	return ""


static func comet(state: GameState, eid: int, sid: int, added: Array[Dictionary]) -> void:
	Economy.pay(state.get_empire(eid), Insolites.cfg("myrr").get("comet_cost", {}))
	var comets: Array = Insolites.emp(state, eid)["comets"]
	for cm: Dictionary in comets:
		if int(cm["sid"]) == sid:
			@warning_ignore("integer_division")
			cm["left"] = maxi(1, int(cm["left"]) / 2)
			added.append(state.add_chronicle("Une seconde comète de Myrr file vers %s, dans le sillage de la première : elles arriveront plus tôt, ensemble." % state.galaxy.systems[sid].system_name,
					Espionage.private_to(state, [eid])))
			return
	var days := comet_range(state, eid, sid) * _c("comet_days_per_jump", 60)
	comets.append({"sid": sid, "left": days})
	added.append(state.add_chronicle("La Sporemère de Myrr lance une comète vers %s. Elle mettra %d jours ; elle ne fait pas de bruit, elle a tout son temps." % [state.galaxy.systems[sid].system_name, days],
			Espionage.private_to(state, [eid])))


static func _land(state: GameState, eid: int, sid: int, added: Array[Dictionary]) -> void:
	var free := _free_planets(state, sid)
	if free.is_empty() or (state.system_owner(sid) >= 0 and state.system_owner(sid) != eid):
		added.append(state.add_chronicle("Une comète de Myrr s'écrase à %s sur un monde déjà pris. Le mycélium attend." % state.galaxy.systems[sid].system_name, Espionage.private_to(state, [eid])))
		return
	var best := free[0]
	var best_m := -1
	for pid in free:
		var m := Economy.max_pop(state, state.galaxy.get_planet(pid), eid)
		if m > best_m:
			best_m = m
			best = pid
	_new_colony(state, eid, best, _c("comet_settle_days", 90))
	added.append(state.add_chronicle("Une comète de Myrr tombe sur %s. Dans quelques mois, il y aura une forêt de champignons là où il n'y avait que de la roche." % state.galaxy.get_planet(best).display_name(state.galaxy),
			Espionage.public_to(state, [eid])))


# --- Irrémédiable (prop. 95) -------------------------------------------------------------------------

static func _spread(state: GameState, eid: int, added: Array[Dictionary]) -> void:
	for sid in seeded(state, eid):
		if burned(state, sid) or posmod(hash([state.seed_value, state.tick, sid, eid, "myc"]), 1000) >= _c("spread_pmille", 400):
			continue
		var free := _free_planets(state, sid)
		if not free.is_empty():
			_new_colony(state, eid, free[0], _c("spread_settle_days", 30))
			continue
		for pid in state.galaxy.systems[sid].planet_ids:
			var c: Colony = state.colonies.get(pid)
			if c == null or c.owner == eid or c.owner < 0 or GameState.is_npc(c.owner) or not c.is_established():
				continue
			if not c.is_colony():
				var was := c.owner
				Peoples.on_owner_change(state, c, was, eid)
				c.owner = eid
				state.rebuild_ownership()
				added.append(state.add_chronicle("L'avant-poste de %s sur %s ne répond plus. Le mycélium de Myrr l'a recouvert, antennes comprises." % [
						state.get_empire(was).short_name(), state.galaxy.get_planet(int(pid)).display_name(state.galaxy)], Espionage.private_to(state, [eid, was], sid)))
				break
			if Insolites.implant(state, int(pid), "mycelium").is_empty():
				Insolites.add_implant(state, int(pid), "mycelium", eid)
				added.append(state.add_chronicle("Sur %s, des filaments blancs sortent des égouts. Le mycélium de Myrr est arrivé." % state.galaxy.get_planet(int(pid)).display_name(state.galaxy),
						Espionage.private_to(state, [eid, c.owner], sid)))
				break


## Le mycélium ronge les colonies étrangères infectées ; à un habitant, il les absorbe.
static func _feed(state: GameState, eid: int, added: Array[Dictionary]) -> void:
	for pid in Insolites.implants_of(state, eid, "mycelium"):
		var c: Colony = state.colonies.get(pid)
		if c == null or c.owner == eid or not c.is_colony():
			Insolites.remove_implant(state, pid, "mycelium")
			continue
		var sid := state.galaxy.get_planet(pid).system_id
		if burned(state, sid) or posmod(hash([state.seed_value, state.tick, pid, "feed"]), 1000) >= _c("feed_pmille", 500):
			continue
		if c.population > 1:
			c.population -= 1
			c.growth = 0
			Peoples.normalize(c)
			Faiths.normalize(c)
			for q in state.galaxy.systems[sid].planet_ids:
				var mc: Colony = state.colonies.get(q)
				if mc != null and mc.owner == eid and mc.is_colony() and mc.population < Economy.max_pop(state, state.galaxy.get_planet(int(q)), eid):
					mc.population += 1
					break
			continue
		_absorb(state, eid, c, added)


static func _absorb(state: GameState, eid: int, c: Colony, added: Array[Dictionary]) -> void:
	var was := c.owner
	var we := state.get_empire(was)
	Insolites.remove_implant(state, c.planet_id, "mycelium")
	Peoples.on_owner_change(state, c, was, eid)
	c.owner = eid
	c.construction = ""
	c.construction_days = 0
	c.ship_build = ""
	c.ship_days = 0
	state.rebuild_ownership()
	var ed := Insolites.emp(state, eid)
	ed["absorbed"] = int(ed.get("absorbed", 0)) + 1
	var sym: Array = ed.get("sym", [])
	var fid := we.faction_id if we != null else ""
	var new_sym := fid != "" and not sym.has(fid)
	if new_sym:
		sym.append(fid)
		ed["sym"] = sym
	Diplomacy.remember(state, was, eid, "ins_absorbed")
	added.append(state.add_chronicle("%s est absorbée par la Sporemère de Myrr. Les derniers habitants de %s ne sont pas morts : ils font partie de quelque chose de plus grand, qui pense lentement.%s" % [
			state.galaxy.get_planet(c.planet_id).display_name(state.galaxy), we.short_name() if we else "?",
			(" Myrr y gagne une symbiose : %s." % symbiosis_label(fid)) if new_sym else ""], Espionage.public_to(state, [eid, was])))


# --- Le feu (prop. 95) -------------------------------------------------------------------------------

static func check_burn(state: GameState, eid: int, pid: int) -> String:
	var c: Colony = state.colonies.get(pid)
	if c == null or not is_myrr(state, c.owner) or c.owner == eid:
		return "il faut viser une colonie de la Sporemère"
	if not Combat.at_war(state, eid, c.owner):
		return "il faut être en guerre avec Myrr"
	var sid := state.galaxy.get_planet(pid).system_id
	var armed := false
	for f in Fleets.fleets_at(state, sid):
		if f.owner == eid and Combat.is_armed(f) and not f.is_moving():
			armed = true
	if not armed:
		return "il faut une flotte armée à l'arrêt dans le système"
	if burned(state, sid):
		return "le système brûle déjà"
	return ""


static func burn(state: GameState, eid: int, pid: int, added: Array[Dictionary]) -> void:
	var c: Colony = state.colonies[pid]
	var myrr := c.owner
	var sid := state.galaxy.get_planet(pid).system_id
	_scorch(state, sid, pid)
	var gone := not c.is_colony() or c.population <= _c("burn_pop", 3)
	if gone:
		state.colonies.erase(pid)
		state.rebuild_ownership()
	else:
		c.population -= _c("burn_pop", 3)
		Peoples.normalize(c)
		Faiths.normalize(c)
	added.append(state.add_chronicle("%s brûle le mycélium de %s depuis l'orbite. %s" % [state.get_empire(eid).display_name(),
			state.galaxy.get_planet(pid).display_name(state.galaxy), "Il ne reste qu'une croûte noire, et une odeur de pain grillé." if gone else "Les forêts de champignons fument ; elles repousseront, mais pas tout de suite."],
			Espionage.public_to(state, [eid, myrr])))


## Feu sur un système : il ne pousse plus pendant burn_days, et la biosphère de la planète en souffre.
static func _scorch(state: GameState, sid: int, pid: int) -> void:
	Insolites.sub(state, "burned")[str(sid)] = state.tick + _c("burn_days", 360)
	if pid >= 0 and Ecology.has_biosphere(state, pid):
		Ecology._set_health(state, pid, maxi(0, Ecology.health(state, pid) - _c("burn_eco", 30)))


## Bombardement orbital d'un système (GroundSiege) : si c'est un système de Myrr, il brûle.
static func on_bombard(state: GameState, sid: int, owner: int) -> void:
	if is_myrr(state, owner) and not burned(state, sid):
		_scorch(state, sid, -1)


## Raison qui empêche d'envahir ce système ("" sinon) : chez Myrr, seul le feu arrête le mycélium. Tant
## que le système n'a pas brûlé (ordre « Brûler » ou bombardement), il repousse sous les pas des troupes.
static func invade_block(state: GameState, sid: int) -> String:
	if not is_myrr(state, state.system_owner(sid)) or burned(state, sid):
		return ""
	return "le mycélium repousse sous les pas des troupes : il faut d'abord brûler le système (ordre « Brûler » ou bombardement)"


# --- Réseau mycorhizien (prop. 96) -------------------------------------------------------------------

static func _network(state: GameState, eid: int, ed: Dictionary) -> void:
	var mine := {}
	for sid in seeded(state, eid):
		if not burned(state, sid):
			mine[sid] = true
	var cap := FactionTraits.capital_system(state, eid)
	var seen := {}
	if mine.has(cap):
		var queue: Array[int] = [cap]
		seen[cap] = true
		while not queue.is_empty():
			var s: int = queue.pop_front()
			for n in state.galaxy.systems[s].neighbors:
				if mine.has(n) and not seen.has(n):
					seen[n] = true
					queue.append(n)
	var iso: Array = []
	for sid in seeded(state, eid):
		if not seen.has(sid):
			iso.append(sid)
	ed["iso"] = iso


static func colony_pct(state: GameState, pid: int) -> int:
	var c: Colony = state.colonies.get(pid)
	if c == null or not is_myrr(state, c.owner):
		return 100
	var iso: Array = Insolites.emp(state, c.owner).get("iso", [])
	return _c("iso_pct", 50) if iso.has(state.galaxy.get_planet(pid).system_id) else 100


# --- Spores (prop. 97) -------------------------------------------------------------------------------

static func _spores(state: GameState, eid: int) -> void:
	var pct := _c("spore_pct", 2)
	for fid in state.sorted_fleet_ids():
		var f: Fleet = state.fleets[fid]
		if f.owner == eid or f.is_moving() or f.owner < 0 or GameState.is_npc(f.owner) or state.system_owner(f.system_id) != eid:
			continue
		if not Combat.at_war(state, f.owner, eid):
			continue
		for i in f.ships.size():
			@warning_ignore("integer_division")
			var dmg := maxi(1, Fleet.max_hp_of(f.ships[i]) * pct / 100)
			f.hp[i] = maxi(1, f.hp[i] - dmg)


# --- Symbiose (prop. 98) -----------------------------------------------------------------------------

static func symbiosis_def(fid: String) -> Dictionary:
	var arch := String(GameData.faction(fid).get("species", {}).get("archetype", ""))
	var sm: Dictionary = Insolites.cfg("myrr").get("symbiosis", {})
	return sm.get(arch, sm.get("_default", {}))


static func symbiosis_label(fid: String) -> String:
	return String(symbiosis_def(fid).get("label", "symbiose"))


static func production_bonus(state: GameState, eid: int, resource: String) -> int:
	var n := 0
	for fid in Insolites.emp(state, eid).get("sym", []):
		n += int((symbiosis_def(String(fid)).get("pct", {}) as Dictionary).get(resource, 0))
	return n


# --- Chaque jour -------------------------------------------------------------------------------------

static func daily(state: GameState, eid: int, ed: Dictionary, month: bool, added: Array[Dictionary]) -> void:
	var comets: Array = ed.get("comets", [])
	for i in range(comets.size() - 1, -1, -1):
		var cm: Dictionary = comets[i]
		cm["left"] = int(cm["left"]) - 1
		if int(cm["left"]) <= 0:
			comets.remove_at(i)
			_land(state, eid, int(cm["sid"]), added)
	_spores(state, eid)
	if not month:
		return
	_spread(state, eid, added)
	_feed(state, eid, added)
	_network(state, eid, ed)
	if state.insolites.has("burned"):
		var b: Dictionary = state.insolites["burned"]
		for k in b.keys():
			if int(b[k]) <= state.tick:
				b.erase(k)


# --- Victoire : la Biosphère unique (prop. 99) -------------------------------------------------------

## [planètes habitables de la galaxie, celles que l'empire tient].
static func habitable_share(state: GameState, eid: int) -> Array[int]:
	var total := 0
	var mine := 0
	for sys in state.galaxy.systems:
		for pid in sys.planet_ids:
			var p := state.galaxy.get_planet(pid)
			if int(GameData.planet_type(p.type).get("base_hab", 0)) <= 0:
				continue
			total += 1
			var c: Colony = state.colonies.get(pid)
			if c != null and c.owner == eid:
				mine += 1
	return [total, mine]


static func victory(state: GameState, e: Empire, out: Dictionary) -> void:
	var want := int(Insolites.cfg("victories").get("biosphere", {}).get("pct", 40))
	var hs := habitable_share(state, e.id)
	@warning_ignore("integer_division")
	var pct := int(hs[1]) * 100 / maxi(1, int(hs[0]))
	out["lines"].append("Planètes habitables tenues : %d / %d (%d %%, %d %% voulus)" % [hs[1], hs[0], pct, want])
	out["cond"] = pct >= want
	Victory._timed(out, mini(pct, want), want)


static func status_lines(state: GameState, eid: int, ed: Dictionary) -> Array[String]:
	var out: Array[String] = []
	out.append("Systèmes ensemencés : %d (isolés : %d) ; comètes en vol : %d" % [seeded(state, eid).size(), (ed.get("iso", []) as Array).size(), (ed.get("comets", []) as Array).size()])
	var names := PackedStringArray()
	for fid in ed.get("sym", []):
		names.append(symbiosis_label(String(fid)))
	out.append("Mondes absorbés : %d ; symbioses : %s" % [int(ed.get("absorbed", 0)), ", ".join(names) if not names.is_empty() else "aucune"])
	return out
