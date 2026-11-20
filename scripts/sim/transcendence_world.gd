class_name TranscendenceWorld
extends RefCounted
## La Transcendance et la galaxie (lot 2 ; voir Transcendence, data/transcendence.json).
##
## Avant l'Exodium : signes par voie (prop. 9), Renoncement (prop. 10), les Restants (prop. 11), Lieux
## minces (prop. 12), Guide du Passage et désertions (prop. 14).
## Pendant le Passage : effacement et voile de l'Orée (prop. 18), réactions de la galaxie (opinion selon
## le credo, famille « oree » de l'Amphictyonie, motif et but de guerre « Ascension », prop. 19), bêtes
## de passage (prop. 20), espionnage (prop. 37).
## En issue Départ : État successeur (prop. 21), la Curée et ses reliques de savoir (prop. 22), les
## Partis, leurs interventions, leur culte, la Descente et la Légende (prop. 23-26).
## Renoncer : crise de stabilité, les Restants au pouvoir (prop. 30).
## Mode Complète seulement (Transcendence.full) ; « Victoire seule » n'a que le moteur et le départ sec.


static func _month(state: GameState) -> int:
	@warning_ignore("integer_division")
	return state.tick / Transcendence.month_days()


static func _yearly(state: GameState, salt: int) -> bool:
	return posmod(_month(state), 12) == posmod(salt, 12)


# --- Lieux minces (prop. 12) -------------------------------------------------------------------

static func place_minces(state: GameState) -> void:
	var m := Transcendence.cfg("minces")
	var caps: Array[int] = []
	for e in state.empires:
		var c := FactionTraits.capital_system(state, e.id)
		if c >= 0:
			caps.append(c)
	var far := {}
	for c in caps:
		var j := FactionTraits.jumps_from(state.galaxy, c)
		for sid in j:
			if int(j[sid]) < int(m.get("min_jumps_capitals", 3)):
				far[int(sid)] = false
	var cands: Array[int] = []
	for s in state.galaxy.systems:
		if not far.has(s.id) and state.system_owner(s.id) < 0:
			cands.append(s.id)
	var lo := int(m.get("count_min", 3))
	var n := lo + Transcendence._h(state, ["minces"]) % maxi(1, int(m.get("count_max", 6)) - lo + 1)
	var out := Transcendence.sub(state, "minces")
	var i := 0
	while out.size() < n and not cands.is_empty():
		var k := Transcendence._h(state, ["mince", i]) % cands.size()
		out[str(cands[k])] = 1
		cands.remove_at(k)
		i += 1


static func minces(state: GameState) -> Array[int]:
	var out: Array[int] = []
	for k in Transcendence.sub(state, "minces"):
		out.append(int(k))
	out.sort()
	return out


static func is_mince(state: GameState, sid: int) -> bool:
	return Transcendence.sub(state, "minces").has(str(sid))


static func minces_held(state: GameState, eid: int) -> int:
	var n := 0
	for sid in minces(state):
		if state.system_owner(sid) == eid:
			n += 1
	return n


static func gain_parts(state: GameState, eid: int) -> Array:
	var out := []
	var n := minces_held(state, eid)
	if n > 0:
		out.append(["Lieux minces tenus (%d)" % n, n * Transcendence.c_int("minces", "gauge", 15)])
	if not state.megas.is_empty():
		out.append_array(MegasBridges.gain_parts(state, eid))  # Cerveau Matriochka
	return out


# --- Amphictyonie (prop. 19) -------------------------------------------------------------------

static func moratorium(state: GameState, eid := -1) -> bool:
	return state.amph_on and Amphictyony.banned(state, "oree_moratorium") and (eid < 0 or Amphictyony.is_member(state, eid))


static func relays_banned(state: GameState, eid := -1) -> bool:
	return state.amph_on and Amphictyony.banned(state, "oree_relay") and (eid < 0 or Amphictyony.is_member(state, eid))


static func bless_days(state: GameState, eid: int) -> int:
	if not state.amph_on or not Amphictyony.is_member(state, eid):
		return 0
	return Amphictyony.level_sum(state, "oree_bless")


# --- Les Restants (prop. 11) -------------------------------------------------------------------

static func restants(state: GameState, eid: int) -> int:
	return int(Transcendence.sub(state, "rest").get(str(eid), 0))


## Ce vers quoi tendent les Restants : la jauge, les espèces qui ne partent pas, le credo.
static func restants_target(state: GameState, eid: int) -> int:
	var r := Transcendence.cfg("restants")
	if Transcendence.renounced(state, eid):
		return 100
	if Transcendence.path_of(state, eid) == "":
		return 0
	@warning_ignore("integer_division")
	var t := Transcendence.gauge_pct(state, eid) * int(r.get("per_gauge", 1)) / 2
	var e := state.get_empire(eid)
	var tot := 0
	var foreign := 0
	for fid in Genetics.species_of(state, eid):
		var n := Genetics.pop_of(state, eid, fid)
		tot += n
		if Genetics.root(fid) != Genetics.root(e.faction_id):
			foreign += n
	if tot > 0:
		@warning_ignore("integer_division")
		t += 100 * foreign / tot * int(r.get("foreign_pct", 40)) / 100
	t += int((r.get("credo", {}) as Dictionary).get(Transcendence.credo(state, eid), 0))
	return clampi(t, 0, 100)


static func frozen(state: GameState, eid: int) -> bool:
	return Transcendence.full(state) and restants(state, eid) >= Transcendence.c_int("restants", "freeze", 60) and not Transcendence.in_passage(state, eid)


static func _tick_restants(state: GameState, eid: int) -> void:
	var cur := restants(state, eid)
	var tgt := restants_target(state, eid)
	var nxt := cur
	if cur < tgt:
		nxt = mini(tgt, cur + 3)
	elif cur > tgt:
		nxt = maxi(tgt, cur + Transcendence.c_int("restants", "drift", -2))
	if nxt != cur or Transcendence.sub(state, "rest").has(str(eid)):
		Transcendence.sub(state, "rest")[str(eid)] = nxt


# --- Effets, stabilité --------------------------------------------------------------------------

static func renoncement_steps(state: GameState, eid: int) -> int:
	var r := Transcendence.cfg("renoncement")
	var g := Transcendence.gauge(state, eid)
	if not Transcendence.full(state) or Transcendence.path_of(state, eid) == "" or g < int(r.get("from", 500)):
		return 0
	@warning_ignore("integer_division")
	return 1 + (g - int(r.get("from", 500))) / maxi(1, int(r.get("step", 250)))


static func passage_years(state: GameState, eid: int) -> int:
	var host := Transcendence.host_of(state, eid)
	var p := Transcendence.passage(state, host if host >= 0 else eid)
	if p.is_empty():
		return 0
	@warning_ignore("integer_division")
	return 1 + (state.tick - int(p.get("start", state.tick))) / Heroes.DAYS_PER_YEAR


static func effects(state: GameState, eid: int) -> Dictionary:
	var out := {}
	if not Transcendence.full(state):
		return out
	var steps := renoncement_steps(state, eid)
	if steps > 0:
		out["production_pct"] = {"all": steps * Transcendence.c_int("renoncement", "prod_pct", -5)}
	if Transcendence.leaving(state, eid):
		var f := Transcendence.cfg("fade")
		out["damage_pct"] = maxi(int(f.get("damage_min", -40)), passage_years(state, eid) * int(f.get("damage_pct_year", -10)))
		out["growth_pct"] = -100
	# Légende des Partis (prop. 26) : leurs anciens alliés rayonnent un peu plus.
	if is_legend_ally(state, eid):
		out["culture_pct"] = Transcendence.c_int("partis", "culture_pct", 10)
	return out


static func empire_stability_parts(state: GameState, eid: int) -> Array:
	var out := []
	if not Transcendence.full(state):
		return out
	var steps := renoncement_steps(state, eid)
	if steps > 0:
		out.append(["Renoncement (%d palier%s)" % [steps, "s" if steps > 1 else ""], steps * Transcendence.c_int("renoncement", "stab", 5)])
	if restants(state, eid) >= Transcendence.c_int("restants", "freeze", 60):
		out.append(["Les Restants s'agitent", Transcendence.c_int("restants", "stab_high", -5)])
	var cu: Dictionary = Transcendence.sub(state, "curse").get(str(eid), {})
	if not cu.is_empty() and int(cu.get("until", 0)) > state.tick:
		out.append([String(cu.get("label", "Les Partis")), int(cu.get("v", 0))])
	return out


# --- Opinion (prop. 19) -------------------------------------------------------------------------

## Opinion de a envers b quand b est sur le départ : selon le credo de a, et la foi partagée.
static func opinion_parts(state: GameState, a: int, b: int) -> Array:
	var out := []
	if not Transcendence.full(state) or not Transcendence.leaving(state, b):
		return out
	var v := int((Transcendence.cfg("reactions").get("opinion", {}) as Dictionary).get(Transcendence.credo(state, a), 0))
	if v != 0:
		out.append([("Ferveur devant son Passage" if v > 0 else "Crainte de son Passage"), v])
	if state.faith_on and Faiths.has_state_faith(state, a) and Faiths.state_faith(state, a) == Faiths.state_faith(state, b):
		out.append(["Sa foi monte au ciel avec lui", Transcendence.c_int("reactions", "same_faith", 15)])
	return out


# --- Événements du Passage ---------------------------------------------------------------------

## Annonce du Passage : désertions du Guide et des héros peu loyaux (prop. 14).
static func on_passage(state: GameState, eid: int, added: Array[Dictionary]) -> void:
	if state.heroes.is_empty():
		return
	var e := state.get_empire(eid)
	var g := Transcendence.cfg("guide")
	for id in Heroes.ids_of(state, eid):
		var h: Dictionary = state.heroes[id]
		if Heroes.is_prisoner(h):
			continue
		var sp := String(h.get("sp", ""))
		var foreign := sp != "" and Genetics.root(sp) != Genetics.root(e.faction_id)
		if not foreign and int(h.get("loy", 100)) >= int(g.get("desert_loyalty", 50)):
			continue
		if Transcendence._h(state, ["desert", id, state.tick]) % 100 >= int(g.get("desert_pct", 50)):
			continue
		var to := -1
		for c in e.contacts:
			var o := state.get_empire(c)
			if o != null and not o.eliminated and not o.is_npc() and not Transcendence.leaving(state, c) and (to < 0 or Diplomacy.opinion(state, c, eid) < Diplomacy.opinion(state, to, eid)):
				to = c
		if to < 0:
			continue
		h["owner"] = to
		h["post"] = ""
		h["target"] = -1
		h["loy"] = 60
		h["served"] = state.tick
		Transcendence.add_gauge(state, to, int(g.get("secret_gauge", 100)))
		added.append(state.add_chronicle("%s refuse de partir avec %s : il passe chez %s avec les carnets du Passage. « Quelqu'un doit bien rester pour éteindre la lumière. »" % [
				h["name"], e.display_name(), state.get_empire(to).display_name()], Espionage.public_to(state, [eid, to])))


static func note_aid(state: GameState, host: int, eid: int, n: int) -> void:
	if state.transcendence.is_empty() or n == 0:
		return
	var a := Transcendence.sub(state, "aid")
	var d: Dictionary = a.get(str(host), {})
	d[str(eid)] = int(d.get(str(eid), 0)) + n
	a[str(host)] = d


static func on_renounce(state: GameState, eid: int) -> void:
	if not Transcendence.full(state):
		return
	Transcendence.sub(state, "rest")[str(eid)] = 100
	var r := Transcendence.cfg("renounce")
	Transcendence.sub(state, "curse")[str(eid)] = {"until": state.tick + int(r.get("days", 1800)), "v": int(r.get("stab", -20)), "label": "Renoncement à l'Orée"}


# --- Départ, succession, Curée (prop. 21-22) ---------------------------------------------------

## Issue Départ : l'espèce fondatrice part ; un État successeur prend ce qui reste, ou les mondes
## deviennent délaissés (ruines à fouiller). L'empire devient un Parti.
static func depart(state: GameState, eid: int, path_id: String, added: Array[Dictionary]) -> void:
	var e := state.get_empire(eid)
	if e == null or e.eliminated:
		return
	var root := Genetics.root(e.faction_id)
	var consume := bool(Transcendence.path_def(path_id).get("consume", false))
	var keep_sids: Array[int] = []
	var left := {}
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner != eid:
			continue
		var sid := state.galaxy.get_planet(pid).system_id
		if c.is_colony():
			var rest := 0
			for fid in c.species.keys():
				if Genetics.root(String(fid)) == root:
					c.species.erase(fid)
				else:
					rest += int(c.species[fid])
					left[String(fid)] = int(left.get(String(fid), 0)) + int(c.species[fid])
			c.population = rest
			if consume and pid == e.capital_planet:
				c.population = 0
			if c.population <= 0:
				_to_ruin(state, eid, c)
				continue
		if not keep_sids.has(sid):
			keep_sids.append(sid)
	state.rebuild_ownership()
	_contracts(state, eid, added)
	# Partis : la mémoire de l'empire parti (prop. 23).
	var aid: Dictionary = Transcendence.sub(state, "aid").get(str(eid), {})
	Transcendence.sub(state, "partis")[str(eid)] = {"tick": state.tick, "name": e.display_name(), "path": path_id, "aid": aid.duplicate(), "desc": 0}
	if Transcendence.full(state):
		Crisis.pull(state, "transcendance", eid)  # le vide attire (prop. 31)
	var succ := -1
	if Transcendence.full(state) and not keep_sids.is_empty() and not left.is_empty():
		succ = _successor(state, eid, keep_sids, left, added)
	if succ < 0:
		for pid in state.sorted_colony_ids():
			var c: Colony = state.colonies[pid]
			if c.owner == eid:
				if c.is_colony() and c.population > 0:
					_to_ruin(state, eid, c)
				else:
					state.colonies.erase(pid)
		state.rebuild_ownership()
	CombatSystem.eliminate(state, e)
	Relics.touch(state)


static func _to_ruin(state: GameState, eid: int, c: Colony) -> void:
	if Transcendence.full(state):
		Transcendence.sub(state, "ruins")[str(c.planet_id)] = {"from": eid, "until": state.tick + Transcendence.c_int("curee", "ruin_days", 3600), "b": c.buildings.duplicate()}
	state.colonies.erase(c.planet_id)


static func _successor(state: GameState, eid: int, sids: Array[int], left: Dictionary, added: Array[Dictionary]) -> int:
	var e := state.get_empire(eid)
	var best := ""
	var ks := left.keys()
	ks.sort()
	for fid in ks:
		if best == "" or int(left[fid]) > int(left[best]):
			best = String(fid)
	var nid := RulersDynasty.spawn_empire(state, eid, sids, {}, "transcend", added)
	if nid < 0:
		return -1
	var ne := state.get_empire(nid)
	if best != "" and not GameData.faction(best).is_empty():
		ne.faction_id = best
		var rank := 0
		for o in state.empires:
			if o.faction_id == best and o.id != nid:
				rank += 1
		ne.name_suffix = GameState.ROMAN[mini(rank, GameState.ROMAN.size() - 1)]
	# Flottes : une part passe au successeur (toutes si les Restants ont forcé la scission).
	var fl := Fleets.empire_fleets(state, eid)
	var pct := 100 if restants(state, eid) >= Transcendence.c_int("restants", "split", 80) else Transcendence.c_int("succession", "fleets_pct", 50)
	@warning_ignore("integer_division")
	var n := fl.size() * pct / 100
	for i in mini(n, fl.size()):
		var f: Fleet = fl[i]
		if Transcendence.is_ark(state, f) or FactionTraits.is_city_fleet(f):
			continue
		f.owner = nid
	ne.reputation = e.reputation
	state.rebuild_ownership()
	added.append(state.add_chronicle(String(Transcendence.cfg("succession").get("chronicle", "%s laisse %s.")) % [e.display_name(), ne.display_name()], Espionage.public_to(state, [eid, nid])))
	return nid


## Brisecomète : contrats d'héritage avec un empire qui part (talent contract_pct).
static func _contracts(state: GameState, eid: int, added: Array[Dictionary]) -> void:
	var e := state.get_empire(eid)
	for o in state.empires:
		var pct := Transcendence.t_int(state, o.id, "contract_pct")
		if pct <= 0 or o.eliminated or o.id == eid or int(Diplomacy.rel(state, o.id, eid).get("trade", 0)) <= 0:
			continue
		var got := {}
		for r in ["energy", "materials", "influence", "crystals"]:
			@warning_ignore("integer_division")
			var v := maxi(0, int(e.resources.get(r, 0))) * pct / 100
			if v > 0:
				o.resources[r] = int(o.resources.get(r, 0)) + v
				got[r] = v
		if not got.is_empty():
			added.append(state.add_chronicle("%s présente son contrat d'héritage signé d'avance : %s, réglés avant que %s ne parte. On ne part pas sans payer." % [
					o.display_name(), GameData.format_amounts(got), e.short_name()], Espionage.private_to(state, [o.id])))


## Ruines : qui colonise un monde délaissé retrouve ses bâtiments et fouille une relique de savoir.
static func _tick_ruins(state: GameState, added: Array[Dictionary]) -> void:
	var r := Transcendence.sub(state, "ruins")
	var ks := r.keys()
	ks.sort()
	for k in ks:
		var ru: Dictionary = r[k]
		var c: Colony = state.colonies.get(int(k))
		if c == null:
			if int(ru.get("until", 0)) <= state.tick:
				r.erase(k)
			continue
		if GameState.is_npc(c.owner) or c.owner == int(ru["from"]):
			continue
		for b in ru.get("b", []):
			if not c.buildings.has(String(b)) and not GameData.building(String(b)).is_empty():
				c.buildings.append(String(b))
		var finder := state.get_empire(c.owner)
		var parted := state.get_empire(int(ru["from"]))
		var n := 1 + maxi(0, Transcendence.t_int(state, c.owner, "curee_x") - 1)
		var got := PackedStringArray()
		if parted != null:
			var cands: Array = []
			for t in parted.techs:
				if not finder.techs.has(t) and not Research.tech(String(t)).is_empty():
					cands.append(String(t))
			cands.sort()
			for i in n:
				if cands.is_empty():
					break
				var t := String(cands[Transcendence._h(state, ["ruin", k, i]) % cands.size()])
				cands.erase(t)
				finder.techs[t] = true
				got.append(String(Research.tech(t).get("label", t)))
		Transcendence._stat(state, c.owner, "tr_ruins", 1)
		r.erase(k)
		added.append(state.add_chronicle("%s fouille les ruines de %s sur %s%s." % [finder.display_name(), parted.short_name() if parted != null else "un peuple parti",
				state.galaxy.get_planet(int(k)).display_name(state.galaxy),
				(" : relique de savoir, %s" % ", ".join(got)) if not got.is_empty() else ""], Espionage.private_to(state, [c.owner])))


# --- Les Partis (prop. 23-26) ------------------------------------------------------------------

static func has_partis(state: GameState) -> bool:
	return not state.transcendence.is_empty() and not (state.transcendence.get("partis", {}) as Dictionary).is_empty()


static func partis_ids(state: GameState) -> Array[int]:
	var out: Array[int] = []
	for k in Transcendence.sub(state, "partis"):
		out.append(int(k))
	out.sort()
	return out


static func parti(state: GameState, pid: int) -> Dictionary:
	return Transcendence.sub(state, "partis").get(str(pid), {})


## Empire le plus aidé (aid > 0) ou le plus gênant (aid < 0) d'un Parti : [eid, valeur].
static func favorite(state: GameState, pid: int) -> Array:
	var aid: Dictionary = parti(state, pid).get("aid", {})
	var best := -1
	var bv := 0
	var ks := aid.keys()
	ks.sort()
	for k in ks:
		var o := state.get_empire(int(k))
		if o == null or o.eliminated:
			continue
		if absi(int(aid[k])) > absi(bv):
			best = int(k)
			bv = int(aid[k])
	return [best, bv]


static func is_legend_ally(state: GameState, eid: int) -> bool:
	for pid in partis_ids(state):
		if int((parti(state, pid).get("aid", {}) as Dictionary).get(str(eid), 0)) > 0:
			return true
	return false


## Fidèles du culte des Partis (nature de foi « culte_partis ») chez un empire.
static func cult_followers(state: GameState, eid: int) -> int:
	if not state.faith_on:
		return 0
	var n := 0
	for fid in Faiths.ids(state):
		if String(Faiths.faith(state, fid).get("nature", "")) == "culte_partis":
			n += int(Faiths.followers_by_owner(state, fid).get(eid, 0))
	return n


static func _tick_partis(state: GameState, added: Array[Dictionary]) -> void:
	var p := Transcendence.cfg("partis")
	for pid in partis_ids(state):
		var pd := parti(state, pid)
		if not _yearly(state, pid + 5):
			continue
		var fav := favorite(state, pid)
		var who := int(fav[0])
		if who >= 0:
			@warning_ignore("integer_division")
			var chance := int(p.get("pct", 20)) + mini(int(p.get("cult_max", 40)), cult_followers(state, who) / 10 * int(p.get("cult_pct", 2)))
			if Transcendence._h(state, ["parti", pid, state.tick]) % 100 < chance:
				var we := state.get_empire(who)
				if int(fav[1]) > 0:
					for r in p.get("gift", {}):
						we.resources[r] = int(we.resources.get(r, 0)) + int(p["gift"][r])
					Transcendence.sub(state, "curse")[str(who)] = {"until": state.tick + int(p.get("curse_days", 720)), "v": int(p.get("gift_stab", 5)), "label": "Bénédiction des Partis"}
					added.append(state.add_chronicle("Les Partis (%s) ne devraient pas intervenir. Ils interviennent quand même : %s reçoit, une nuit, ce dont il avait besoin, et un rêve très poli." % [
							String(pd.get("name", "")), we.display_name()], Espionage.private_to(state, [who])))
				else:
					Transcendence.sub(state, "curse")[str(who)] = {"until": state.tick + int(p.get("curse_days", 720)), "v": int(p.get("curse_stab", -10)), "label": "Malédiction des Partis"}
					added.append(state.add_chronicle("Les Partis (%s) se souviennent de %s. Rien de visible : seulement une rancune dans le ciel, et des enfants qui pleurent sans savoir pourquoi." % [
							String(pd.get("name", "")), we.display_name()], Espionage.public_to(state, [who])))
		_descent(state, pid, added)


## La Descente (prop. 25) : une fois, un Parti revient en héros légendaire chez son favori.
static func _descent(state: GameState, pid: int, added: Array[Dictionary]) -> void:
	var p := Transcendence.cfg("partis")
	var pd := parti(state, pid)
	if int(pd.get("desc", 0)) > 0:
		return
	if state.tick - int(pd.get("tick", 0)) < int(p.get("descent_years", 5)) * Heroes.DAYS_PER_YEAR:
		return
	if Transcendence._h(state, ["descent", pid, state.tick]) % 100 >= int(p.get("descent_pct", 10)):
		return
	var who := int(favorite(state, pid)[0])
	if who < 0 or int(favorite(state, pid)[1]) <= 0:
		return
	var parted := state.get_empire(pid)
	var cand := Heroes.make_candidate(state, who, "orateur", ["descente", pid], parted.faction_id if parted != null else "")
	var hid := Heroes.recruit(state, who, cand)
	var h: Dictionary = state.heroes[hid]
	h["lvl"] = int(p.get("descent_lvl", 4))
	h["name"] = "%s, revenu d'au-delà" % String(h["name"])
	pd["desc"] = state.tick
	Transcendence._stat(state, who, "tr_descent", 1)
	added.append(state.add_chronicle("Un inconnu frappe à la porte du palais de %s. Il ne se souvient de rien, sinon d'une lumière ; il parle comme %s parlait. %s, revenu d'au-delà, entre au service." % [
			state.get_empire(who).display_name(), String(pd.get("name", "les Partis")), String(h["name"]).get_slice(",", 0)], Espionage.public_to(state, [who])))


# --- Signes, bêtes, lassitude des guerres -----------------------------------------------------

static func _tick_signs(state: GameState, eid: int, added: Array[Dictionary]) -> void:
	var s := Transcendence.cfg("signs")
	var sg := Transcendence.sub(state, "signs")
	if sg.has(str(eid)) or Transcendence.gauge(state, eid) < int(s.get("at", 250)):
		return
	sg[str(eid)] = state.tick
	var card := String((s.get("cards", {}) as Dictionary).get(Transcendence.path_of(state, eid), ""))
	if card != "" and not Events.card(card).is_empty():
		Events.push(state, eid, card, {}, added)


static func _tick_fauna(state: GameState, eid: int, added: Array[Dictionary]) -> void:
	if not Fauna.active(state) or not _yearly(state, eid + 3):
		return
	var sys := Transcendence.oeuvre_sys(state, eid)
	if sys < 0 or Transcendence._h(state, ["faune", eid, state.tick]) % 100 >= Transcendence.c_int("fauna", "pct", 35):
		return
	var near := -1
	for n in state.galaxy.systems[sys].neighbors:
		if state.system_owner(n) < 0:
			near = n
			break
	if near < 0:
		return
	var sp := "betes_songe" if Transcendence.path_of(state, eid) == "songe" and not Fauna.species("betes_songe").is_empty() else "nuees"
	if Fauna.species(sp).is_empty():
		return
	Fauna.spawn_herd(state, sp, near, -1, state.tick + 360)
	added.append(state.add_chronicle("Des bêtes s'agitent près %s : quelque chose, dans le Passage de %s, les attire comme une lumière attire les phalènes." % [
			GameData.de(Transcendence.oeuvre_label(Transcendence.path_of(state, eid))), state.get_empire(eid).short_name()], Espionage.private_to(state, [eid])))


## Chaque année de Passage, ceux qui lui font la guerre déplaisent aux futurs Partis (prop. 23).
static func _tick_harm(state: GameState, eid: int) -> void:
	if not _yearly(state, eid + 7):
		return
	var e := state.get_empire(eid)
	for w in e.wars:
		note_aid(state, eid, int(w), -Transcendence.c_int("partis", "harm_war", 3))
	for c in state.sorted_colony_ids():
		var col: Colony = state.colonies[c]
		if col.owner != eid and not GameState.is_npc(col.owner) and col.buildings.has(Transcendence.relay_building()) and Transcendence.host_of(state, col.owner) == eid:
			note_aid(state, eid, col.owner, Transcendence.c_int("partis", "aid_relay", 1))


# --- Espionnage (prop. 37) ---------------------------------------------------------------------

static func spy_check(state: GameState, a: int, b: int, op_id: String) -> String:
	if not Transcendence.enabled(state):
		return "la Transcendance n'est pas en jeu dans cette partie"
	match op_id:
		"feler_oeuvre":
			if Transcendence.stage(state, b) <= 0 and not Transcendence.stage_running(state, b):
				return "son Exodium n'a pas d'étape à fêler"
		"voler_carnets":
			if Transcendence.path_of(state, b) == "":
				return "il ne s'est voué à aucune voie"
			if Transcendence.path_of(state, a) == "":
				return "il faut s'être voué à une voie pour lire ses carnets"
	return ""


static func spy_apply(state: GameState, a: int, b: int, o: Dictionary) -> String:
	var be := state.get_empire(b)
	match String(o.get("id", "")):
		"feler_oeuvre":
			note_aid(state, b, a, -Transcendence.c_int("partis", "harm_spy", 2))
			var oe := Transcendence.oeuvre(state, b)
			if Transcendence.in_passage(state, b):
				Transcendence.break_passage(state, b, "des saboteurs ont fêlé %s" % Transcendence.oeuvre_label(Transcendence.path_of(state, b)), 1, [])
			elif Transcendence.stage_running(state, b):
				oe["until"] = 0
			else:
				oe["stage"] = maxi(0, int(oe.get("stage", 0)) - 1)
			return "nos agents ont fêlé %s de %s : une étape est perdue." % [Transcendence.oeuvre_label(Transcendence.path_of(state, b)), be.display_name()]
		"voler_carnets":
			Transcendence.add_gauge(state, a, Transcendence.c_int("guide", "secret_gauge", 100))
			Transcendence._stat(state, a, "stolen_notes", 1)
			return "nous avons copié les carnets de l'Orée de %s : notre jauge monte, mais ce savoir volé rend notre propre Passage plus fragile." % be.display_name()
	return ""


# --- Bilan mensuel -----------------------------------------------------------------------------

static func monthly(state: GameState, added: Array[Dictionary]) -> void:
	for e in state.empires:
		if not Transcendence.applies(state, e.id):
			continue
		_tick_restants(state, e.id)
		if Transcendence.path_of(state, e.id) == "":
			continue
		_tick_signs(state, e.id, added)
		if Transcendence.in_passage(state, e.id):
			_tick_fauna(state, e.id, added)
			_tick_harm(state, e.id)
	_tick_ruins(state, added)
	_tick_partis(state, added)
	var cu := Transcendence.sub(state, "curse")
	var ks := cu.keys()
	ks.sort()
	for k in ks:
		if int((cu[k] as Dictionary).get("until", 0)) <= state.tick:
			cu.erase(k)
