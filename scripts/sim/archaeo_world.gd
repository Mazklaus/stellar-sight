class_name ArchaeoWorld
extends RefCounted
## Archéologie, lot 2 : les Disparus (prop. 26-32), le musée agrandi (22), les Reconstitutions (23), les
## sites scellés (17), les pillards (19), et du lot 1 les sites nés de l'histoire (9) et les mondes-reliques (10).
## Données : data/archaeology.json ; état : state.archaeo (voir Archaeology).
##
## Vestiges (prop. 27) : tr[eid][Disparu] ; une antiquité vaut 1, un site fini 2 (rules.vestige_site).
## À 3, un site de piste que l'empire seul voit ; à 6, le Monde-berceau se révèle et la Chute se lit.
## Mondes-berceaux : cr[Disparu] = {"s": système, "rev": [empires], "first": premier venu (-1)}.
## Secrets : sec[eid][Disparu] = jour de fin (-1 = achevés). Technologies anciennes : anc[eid]["d:civ"|"d:ship"].
## Gabarits : gab[eid][Disparu] = 1. Avertissements : warn[eid][crise] = 1. Reconstitutions : reco[eid][Disparu].
## Mondes-reliques : rw[planète] = {"s", "done", "made"} ; sites à naître : archaeo["hist"] = [{"day", "s", "or", "at"}].


static func _h(state: GameState, parts: Array) -> int:
	return absi(hash([state.seed_value, "archeo_w"] + parts))


static func _far_candidates(state: GameState, min_jumps: int) -> Array:
	var starts: Array = []
	for e in state.empires:
		var cap := FactionTraits.capital_system(state, e.id)
		if cap >= 0:
			starts.append(FactionTraits.jumps_from(state.galaxy, cap))
	var cands: Array = []
	for sys in state.galaxy.systems:
		if sys.planet_ids.is_empty() or state.system_owner(sys.id) >= 0 or Pirates.is_lair(state, sys.id) or state.digs.has(sys.id):
			continue
		var near := 999
		for d: Dictionary in starts:
			near = mini(near, int(d.get(sys.id, 999)))
		if near < min_jumps:
			continue
		cands.append(sys.id)
	return cands


static func _pick(state: GameState, cands: Array, salt: Array) -> int:
	if cands.is_empty():
		return -1
	var best := -1
	var best_h := -1
	for sid in cands:
		var v := _h(state, salt + [int(sid)]) % 1000003
		if v > best_h:
			best_h = v
			best = int(sid)
	return best


# --- Mise en place -------------------------------------------------------------------------------

## Trois Disparus par partie (prop. 26).
static func pick_disparus(state: GameState) -> void:
	var ids: Array = Archaeology.disparus().keys()
	ids.sort()
	var ranked: Array = []
	for d in ids:
		ranked.append([_h(state, ["disparu", String(d)]) % 100000, String(d)])
	ranked.sort()
	var out: Array = []
	for i in mini(int(Archaeology.data().get("disparus_per_game", 3)), ranked.size()):
		out.append(String(ranked[i][1]))
	out.sort()
	state.archaeo["disp"] = out


## Mondes-reliques (prop. 10) : 1 à 3 selon la taille de la galaxie, sur une planète solide d'un système libre.
static func place_relic_worlds(state: GameState) -> void:
	var n := 1
	var size := state.galaxy.systems.size()
	var tiers: Variant = Archaeology.rule("relic_worlds")
	if tiers is Array:
		for pair in tiers:
			if size <= int(pair[0]):
				n = int(pair[1])
				break
	var cands := _far_candidates(state, int(Relics.data()["digs"]["min_jumps"]))
	for i in n:
		var sid := _pick(state, cands, ["rw", i])
		if sid < 0:
			return
		cands.erase(sid)
		var pid := _solid_planet(state, sid)
		if pid < 0:
			continue
		Archaeology.sub(state, "rw")[str(pid)] = {"s": sid, "done": 0, "made": 1, "next": -1}
		Archaeology.create_site(state, sid, {"rw": 1})


static func _solid_planet(state: GameState, sid: int) -> int:
	var best := -1
	var best_size := -1
	for pid in state.galaxy.systems[sid].planet_ids:
		var p := state.galaxy.get_planet(pid)
		if p.type in ["gas_giant", "asteroids", "anneau"]:
			continue
		if p.size > best_size:
			best_size = p.size
			best = pid
	return best


## Monde-relique de ce système (planète, -1 sinon).
static func relic_world_in(state: GameState, sid: int) -> int:
	var rw := Archaeology.sub(state, "rw")
	for k in rw:
		if int((rw[k] as Dictionary).get("s", -1)) == sid:
			return int(k)
	return -1


## Coloniser un monde-relique : seulement après rules.relic_world_unlock sites finis (prop. 10).
static func colony_block(state: GameState, pid: int) -> String:
	if not Archaeology.enabled(state):
		return ""
	var w: Variant = Archaeology.sub(state, "rw").get(str(pid), null)
	if not (w is Dictionary):
		return ""
	var need := Archaeology.r_int("relic_world_unlock", 2)
	if int((w as Dictionary).get("done", 0)) >= need:
		return ""
	return "monde-relique : il faut d'abord y finir %d fouilles (%d faites)" % [need, int((w as Dictionary).get("done", 0))]


## Un Monde-berceau par Disparu de la partie, loin des départs.
static func place_cradles(state: GameState) -> void:
	var cands := _far_candidates(state, int(Relics.data()["digs"]["min_jumps"]) + 1)
	for d in Archaeology.in_game_disparus(state):
		var sid := _pick(state, cands, ["cradle", d])
		if sid < 0:
			return
		cands.erase(sid)
		Archaeology.sub(state, "cr")[d] = {"s": sid, "rev": [], "first": -1}


## Héritiers (prop. 32) : un peuple mineur peut descendre d'un Disparu (au plus un par Disparu).
static func pick_heirs(state: GameState) -> void:
	if not Minors.enabled(state):
		return
	var mids := Minors.ids(state)
	var used := {}
	for d in Archaeology.in_game_disparus(state):
		if _h(state, ["heir?", d]) % 100 >= 50:
			continue
		var pool: Array = []
		for m in mids:
			if not used.has(m):
				pool.append(m)
		var mid := _pick(state, pool, ["heir", d])
		if mid < 0:
			return
		used[mid] = true
		Archaeology.sub(state, "heirs")[str(mid)] = d


static func heir_of(state: GameState, d: String) -> int:
	var hs := Archaeology.sub(state, "heirs")
	for k in hs:
		if String(hs[k]) == d:
			return int(k)
	return -1


# --- Pistes et Monde-berceau (prop. 27, 28, 31) -------------------------------------------------------

static func vestiges(state: GameState, eid: int, d: String) -> int:
	return int((Archaeology.sub(state, "tr").get(str(eid), {}) as Dictionary).get(d, 0))


static func add_vestiges(state: GameState, eid: int, d: String, n: int, added: Array[Dictionary]) -> void:
	if d == "" or n <= 0 or not Archaeology.applies(state, eid) or Archaeology.disparu_def(d).is_empty():
		return
	var t := Archaeology.emp(state, "tr", eid)
	var before := int(t.get(d, 0))
	var now := before + n
	t[d] = now
	var label := String(Archaeology.disparu_def(d).get("label", d))
	var at := Archaeology.r_int("trail_site_at", 3)
	if before < at and now >= at:
		var cands: Array = []
		var e := state.get_empire(eid)
		for sid in e.explored:
			var s := int(sid)
			if not state.digs.has(s) and state.system_owner(s) in [-1, eid] and not state.galaxy.systems[s].planet_ids.is_empty() and not Pirates.is_lair(state, s):
				cands.append(s)
		cands.sort()
		var sid2 := _pick(state, cands, ["trail", eid, d])
		if sid2 >= 0 and Archaeology.create_site(state, sid2, {"or": "d:" + d, "only": eid, "relic": false}):
			added.append(state.add_chronicle("La piste %s mène vos archéologues à %s : un site que personne d'autre ne connaît." % [
					Archaeology._de(label), state.galaxy.systems[sid2].system_name], Espionage.private_to(state, [eid])))
	var need := Archaeology.r_int("vestiges_for_cradle", 6)
	if before < need and now >= need:
		_reveal_cradle(state, eid, d, added)


static func _reveal_cradle(state: GameState, eid: int, d: String, added: Array[Dictionary]) -> void:
	var c: Dictionary = Archaeology.sub(state, "cr").get(d, {})
	var dd := Archaeology.disparu_def(d)
	if not c.is_empty():
		var rev: Array = c["rev"]
		if not rev.has(eid):
			rev.append(eid)
		var e := state.get_empire(eid)
		var sid := int(c["s"])
		if not e.explored.has(sid):
			e.explored[sid] = true
		added.append(state.add_chronicle("Les vestiges %s se recoupent : leur Monde-berceau est à %s. Une flotte suffira pour y poser le pied." % [
				Archaeology._de(String(dd.get("label", d))), state.galaxy.systems[sid].system_name], Espionage.private_to(state, [eid])))
	# La Chute (prop. 31) : pourquoi ils ont disparu ; si c'est une crise du jeu, l'Avertissement.
	var fall := String(dd.get("fall", ""))
	var text := String(dd.get("fall_text", ""))
	if fall != "" and Crisis.kind_def(fall).size() > 0:
		Archaeology.emp(state, "warn", eid)[fall] = 1
		Archaeology.touch(state)
		text += " Avertissement : le présage de %s vous parviendra plus tôt, et vos flottes sauront où frapper (+%d %% de dégâts)." % [
				Crisis.name_of(fall), Archaeology.r_int("warn_damage_pct", 15)]
	added.append(state.add_chronicle("La Chute %s. %s" % [Archaeology._de(String(dd.get("label", d))), text], Espionage.private_to(state, [eid])))


static func cradle_of(state: GameState, d: String) -> Dictionary:
	var v: Variant = Archaeology.sub(state, "cr").get(d, {})
	return v if v is Dictionary else {}


static func cradle_known(state: GameState, eid: int, d: String) -> bool:
	var c := cradle_of(state, d)
	return not c.is_empty() and (c["rev"] as Array).has(eid)


static func _cradles_daily(state: GameState, added: Array[Dictionary]) -> void:
	var cr := Archaeology.sub(state, "cr")
	var keys := cr.keys()
	keys.sort()
	for d in keys:
		var c: Dictionary = cr[d]
		if int(c.get("first", -1)) >= 0:
			continue
		var sid := int(c["s"])
		for eid in c["rev"]:
			if Archaeology.has_camp(state, int(eid), sid):
				_first_landing(state, int(eid), String(d), added)
				break


static func _first_landing(state: GameState, eid: int, d: String, added: Array[Dictionary]) -> void:
	var c := cradle_of(state, d)
	c["first"] = eid
	var e := state.get_empire(eid)
	var gift: Dictionary = Archaeology.rule("cradle_first") if Archaeology.rule("cradle_first") is Dictionary else {}
	var got := {}
	for r in gift:
		var n := Events.era_scaled(state, eid, int(gift[r]))
		e.resources[r] = int(e.resources.get(r, 0)) + n
		got[r] = n
	var dd := Archaeology.disparu_def(d)
	var rid := String(dd.get("relic", ""))
	var extra := ""
	if rid != "" and state.relics.has(rid) and int(state.relics[rid]["owner"]) < 0:
		Relics.gain(state, eid, rid)
		extra = ", et %s" % String(Relics.def(rid).get("name", rid))
	Archaeology.emp(state, "gab", eid)[d] = 1
	Archaeology._stat(state, eid, "cradles")
	Research.count_stat(state, eid, "archaeo_cradle")
	Archaeology.touch(state)
	added.append(state.add_chronicle("%s est le premier à fouler le Monde-berceau %s : %s%s, et le Gabarit d'une de leurs coques." % [
			e.display_name(), Archaeology._de(String(dd.get("label", d))), GameData.format_amounts(got), extra], Espionage.public_to(state, [eid])))


# --- Secrets (prop. 28) et technologies anciennes (prop. 29) --------------------------------------

static func check_secrets(state: GameState, eid: int, d: String) -> String:
	var c := cradle_of(state, d)
	if c.is_empty():
		return "ce Disparu n'est pas de la partie"
	if not (c["rev"] as Array).has(eid):
		return "il faut d'abord trouver leur Monde-berceau (6 vestiges)"
	if int(c.get("first", -1)) == eid:
		return "vous avez déjà tout emporté la première fois"
	if int(c.get("first", -1)) < 0:
		return "personne n'y a encore posé le pied : une flotte suffit"
	if (Archaeology.sub(state, "sec").get(str(eid), {}) as Dictionary).has(d):
		return "Secrets déjà lancés ici"
	var need := Archaeology.r_int("secrets_fragments", 300)
	if Relics.fragments(state, eid) < need:
		return "il faut %d fragments" % need
	return ""


static func start_secrets(state: GameState, eid: int, d: String, added: Array[Dictionary]) -> void:
	Relics.add_fragments(state, eid, -Archaeology.r_int("secrets_fragments", 300))
	Archaeology.emp(state, "sec", eid)[d] = state.tick + Archaeology.r_int("secrets_days", 720)
	added.append(state.add_chronicle("%s ouvre le chantier des Secrets %s. Deux ans de patience, dit-on." % [
			state.get_empire(eid).short_name(), Archaeology._de(String(Archaeology.disparu_def(d).get("label", d)))], Espionage.private_to(state, [eid])))


static func _secrets_daily(state: GameState, added: Array[Dictionary]) -> void:
	var sec := Archaeology.sub(state, "sec")
	var keys := sec.keys()
	keys.sort()
	for k in keys:
		var m: Dictionary = sec[k]
		var ds := m.keys()
		ds.sort()
		for d in ds:
			var until := int(m[d])
			if until < 0 or state.tick < until:
				continue
			m[d] = -1
			var eid := int(k)
			var anc := grant_ancient(state, eid, String(d), added)
			Archaeology.touch(state)
			added.append(state.add_chronicle("Les Secrets %s sont percés chez %s : %s%s." % [
					Archaeology._de(String(Archaeology.disparu_def(String(d)).get("label", d))), state.get_empire(eid).short_name(),
					String((Archaeology.disparu_def(String(d)).get("secrets", {}) as Dictionary).get("label", "un savoir oublié")),
					(", et %s" % anc) if anc != "" else ""], Espionage.private_to(state, [eid])))


static func secrets_done(state: GameState, eid: int, d: String) -> bool:
	return int((Archaeology.sub(state, "sec").get(str(eid), {}) as Dictionary).get(d, 0)) == -1


static func has_ancient(state: GameState, eid: int, d: String, kind: String) -> bool:
	return (Archaeology.sub(state, "anc").get(str(eid), {}) as Dictionary).has("%s:%s" % [d, kind])


## Donne la technologie ancienne civile, sinon le module de vaisseau, d'un Disparu ; renvoie son nom.
static func grant_ancient(state: GameState, eid: int, d: String, _added: Array[Dictionary]) -> String:
	for kind in ["civ", "ship"]:
		if not has_ancient(state, eid, d, kind):
			Archaeology.emp(state, "anc", eid)["%s:%s" % [d, kind]] = 1
			Archaeology.touch(state)
			return "la technologie ancienne %s" % String((Archaeology.disparu_def(d).get(kind, {}) as Dictionary).get("label", kind))
	return ""


## Rétro-ingénierie (prop. 24) : une technologie ancienne d'un Disparu dont l'empire suit la piste.
static func grant_random_ancient(state: GameState, eid: int, added: Array[Dictionary]) -> String:
	var pool: Array = []
	for d in Archaeology.in_game_disparus(state):
		if vestiges(state, eid, d) > 0 and not (has_ancient(state, eid, d, "civ") and has_ancient(state, eid, d, "ship")):
			pool.append(d)
	if pool.is_empty():
		return ""
	return grant_ancient(state, eid, String(pool[_h(state, ["rev", eid, state.tick]) % pool.size()]), added)


static func gabarits_of(state: GameState, eid: int) -> Array[String]:
	var out: Array[String] = []
	if not Archaeology.enabled(state):
		return out
	for d in (Archaeology.sub(state, "gab").get(str(eid), {}) as Dictionary):
		out.append(String(d))
	out.sort()
	return out


# --- Musée (prop. 22) et Reconstitutions (prop. 23) --------------------------------------------------

static func museum_slots(state: GameState, eid: int) -> int:
	if not Culture.enabled(state) or not Culture.has_museum(state, eid):
		return 0
	return Archaeology.r_int("museum_slots_per_level", 3) * maxi(1, Archaeology.lvl(state, eid))


## Antiquités exposées : les plus anciennes acquises, dans la limite des places.
static func displayed(state: GameState, eid: int) -> Array[int]:
	var mine := Archaeology.antiqs_of(state, eid)
	var out: Array[int] = []
	for i in mini(mine.size(), museum_slots(state, eid)):
		out.append(mine[i])
	return out


## Thème complet (comme Civilization VI) : 3 pièces d'un même Disparu de strates différentes, ou 3 d'une
## même strate de Disparus différents. Une fausse antiquité (opération Faussaire) le brise.
static func has_theme(state: GameState, eid: int) -> bool:
	if int(Archaeology.sub(state, "fakes").get(str(eid), 0)) > state.tick:
		return false
	var by_d := {}
	var by_sr := {}
	for id in displayed(state, eid):
		var a := Archaeology.antiq(state, id)
		var d := String(a.get("d", ""))
		var sr := int(a.get("sr", 1))
		if d != "":
			if not by_d.has(d):
				by_d[d] = {}
			by_d[d][sr] = true
			if not by_sr.has(sr):
				by_sr[sr] = {}
			by_sr[sr][d] = true
	for d in by_d:
		if (by_d[d] as Dictionary).size() >= 3:
			return true
	for sr in by_sr:
		if (by_sr[sr] as Dictionary).size() >= 3:
			return true
	return false


static func museum_parts(state: GameState, eid: int) -> Array:
	var shown := displayed(state, eid)
	if shown.is_empty():
		return []
	var v := shown.size() * Archaeology.r_int("antiq_radiance", 2)
	var th := has_theme(state, eid)
	if th:
		v *= 2
	return [["Antiquités exposées (%d)%s" % [shown.size(), " : salle à thème" if th else ""], v]]


static func reco_need(state: GameState, eid: int) -> int:
	var t := Archaeology.t_int(state, eid, "reco_need")
	return t if t > 0 else int(Archaeology.data().get("reco_need", 3))


static func antiqs_of_disparu(state: GameState, eid: int, d: String) -> Array[int]:
	var out: Array[int] = []
	for id in Archaeology.antiqs_of(state, eid):
		if String(Archaeology.antiq(state, id).get("d", "")) == d:
			out.append(id)
	return out


static func check_reco(state: GameState, eid: int, d: String) -> String:
	if Archaeology.disparu_def(d).is_empty():
		return "Disparu inconnu"
	if Archaeology.lvl(state, eid) < 2:
		return "il faut la technologie Déchiffrement des Strates"
	if (Archaeology.sub(state, "reco").get(str(eid), {}) as Dictionary).has(d):
		return "déjà reconstitué"
	var need := reco_need(state, eid)
	if antiqs_of_disparu(state, eid, d).size() < need:
		return "il faut %d antiquités %s" % [need, Archaeology._de(String(Archaeology.disparu_def(d).get("label", d)))]
	return ""


static func reco(state: GameState, eid: int, d: String, added: Array[Dictionary]) -> void:
	var pieces := antiqs_of_disparu(state, eid, d)
	for i in mini(reco_need(state, eid), pieces.size()):
		Archaeology.remove_antiq(state, pieces[i])
	Archaeology.emp(state, "reco", eid)[d] = state.tick
	Archaeology._stat(state, eid, "reco")
	Research.count_stat(state, eid, "archaeo_reco")
	Archaeology.touch(state)
	var rd: Dictionary = Archaeology.disparu_def(d).get("reco", {})
	added.append(state.add_chronicle("%s assemble %s : %s" % [state.get_empire(eid).short_name(), String(rd.get("label", "une Reconstitution")),
			String(rd.get("text", ""))], Espionage.public_to(state, [eid])))


## Système où « Interroger les Strates » cache un site : exploré, libre ou à soi, sans site.
static func query_target(state: GameState, eid: int) -> int:
	var e := state.get_empire(eid)
	if e == null:
		return -1
	var cands: Array = []
	for sid in e.explored:
		var s := int(sid)
		if s >= 0 and s < state.galaxy.systems.size() and not state.digs.has(s) and state.system_owner(s) in [-1, eid] \
				and not state.galaxy.systems[s].planet_ids.is_empty() and not Pirates.is_lair(state, s):
			cands.append(s)
	cands.sort()
	return _pick(state, cands, ["query", eid, state.tick])


# --- Fin d'un site : scellés (prop. 17), gabarits (30), mondes-reliques (10) ----------------------------

static func on_finish(state: GameState, sid: int, eid: int, added: Array[Dictionary]) -> void:
	var d: Dictionary = state.digs[sid]
	var dn := Archaeology.disparu_of(String(d.get("or", "")))
	# Épave enfouie d'un Disparu : parfois le Gabarit d'une coque.
	if String(d.get("at", "")) == "epave" and dn != "" and _h(state, ["gab", sid, eid]) % 100 < Archaeology.r_int("gabarit_epave_pct", 10):
		Archaeology.emp(state, "gab", eid)[dn] = 1
		added.append(state.add_chronicle("Au fond de l'épave de %s, un Gabarit intact : %s." % [Relics.site_name(state, sid),
				String(Designs.hull(String(Archaeology.disparu_def(dn).get("hull", ""))).get("label", "une coque ancienne"))], Espionage.private_to(state, [eid])))
	# Monde-relique : un site de plus fait, le suivant viendra.
	var pid := relic_world_in(state, sid)
	if pid >= 0:
		var w: Dictionary = Archaeology.sub(state, "rw")[str(pid)]
		w["done"] = int(w.get("done", 0)) + 1
		if int(w.get("made", 1)) < Archaeology.r_int("relic_world_sites", 3):
			w["next"] = state.tick + Archaeology.r_int("relic_world_next_days", 360)
		if int(w["done"]) == Archaeology.r_int("relic_world_unlock", 2):
			added.append(state.add_chronicle("Le monde-relique de %s est assez déblayé pour qu'on s'y installe." % state.galaxy.systems[sid].system_name))
	# Site scellé : le finir peut réveiller ce qui dormait (Prudente divise le risque par deux).
	if int(d.get("seal", 0)) == 1:
		var risk := Archaeology.r_int("seal_risk_pct", 50)
		if String(d.get("me", "")) == "prudente":
			@warning_ignore("integer_division")
			risk = risk / 2
		if _h(state, ["seal?", sid, state.tick]) % 100 < risk:
			_awaken(state, sid, eid, added)
		else:
			added.append(state.add_chronicle("À %s, le sceau tient. Ce qui dormait dort encore, et personne n'a envie de vérifier." % Relics.site_name(state, sid),
					Espionage.private_to(state, [eid], sid)))


static func _awaken(state: GameState, sid: int, eid: int, added: Array[Dictionary]) -> void:
	var opts: Array[String] = ["gardien"]
	var kheb := Ancients.id_of_kind(state, "kheb") if Ancients.enabled(state) else -1
	if kheb >= 0 and (Ancients.get_a(state, kheb) as Dictionary).has("tomb_next"):
		opts.append("kheb")
	var pick := opts[_h(state, ["awake", sid]) % opts.size()]
	match pick:
		"kheb":
			var a: Dictionary = Ancients.get_a(state, kheb)
			a["tomb_next"] = mini(int(a["tomb_next"]), state.tick + 1)
			added.append(state.add_chronicle("Le sceau de %s se brise, et quelque part un tombeau de Kheb répond. Il ouvrira les yeux bientôt." % Relics.site_name(state, sid)))
		_:
			@warning_ignore("integer_division")
			var f := Curios.spawn_trap(state, sid, clampi(1 + Research.current_era(state, eid) / 2, 1, 4))
			f.fleet_name = "Gardien des Strates"
			added.append(state.add_chronicle("Le sceau de %s se brise : le Gardien des Strates se lève, et il n'a pas l'air content d'être dérangé." % Relics.site_name(state, sid),
					Espionage.private_to(state, [eid], sid)))


# --- Sites nés de l'histoire (prop. 9) ----------------------------------------------------------------

## Met en file un site qui naîtra dans rules.hist_delay_days (strate Récente, origine = ce peuple).
static func queue_history(state: GameState, sid: int, origin: String, t: String) -> void:
	if not Archaeology.enabled(state) or sid < 0:
		return
	var q: Array = state.archaeo.get("hist", [])
	for x: Dictionary in q:
		if int(x["s"]) == sid:
			return
	q.append({"day": state.tick + Archaeology.r_int("hist_delay_days", 7200), "s": sid, "or": origin, "at": t})
	state.archaeo["hist"] = q


static func on_eliminated(state: GameState, e: Empire) -> void:
	if not Archaeology.enabled(state) or e.is_npc():
		return
	var cap := FactionTraits.capital_system(state, e.id)
	if cap >= 0:
		queue_history(state, cap, "e:%d:%s" % [e.id, e.display_name()], "cite")


static func on_battle_end(state: GameState, sid: int) -> void:
	if Archaeology.enabled(state) and int(state.battle_wrecks.get(sid, 0)) >= Archaeology.r_int("hist_wrecks", 30):
		queue_history(state, sid, "b", "champ")


static func _history_daily(state: GameState, added: Array[Dictionary]) -> void:
	var q: Array = state.archaeo.get("hist", [])
	if q.is_empty() or state.tick - int(state.archaeo.get("hist_last", -99999)) < Archaeology.r_int("hist_gap_days", 1825):
		return
	for i in q.size():
		var x: Dictionary = q[i]
		if state.tick < int(x["day"]):
			continue
		var sid := int(x["s"])
		if Relics.is_open(state, sid):
			continue
		q.remove_at(i)
		if Archaeology.create_site(state, sid, {"or": String(x["or"]), "at": String(x["at"]), "sr": 2, "hist": 1, "relic": false}):
			state.archaeo["hist_last"] = state.tick
			added.append(state.add_chronicle("À %s, le temps a fait son œuvre : %s est devenu un site de fouilles. L'histoire de cette partie a déjà ses archéologues." % [
					state.galaxy.systems[sid].system_name, Archaeology.origin_label(state, String(x["or"]))]))
		return


static func _relic_worlds_daily(state: GameState) -> void:
	var rw := Archaeology.sub(state, "rw")
	var keys := rw.keys()
	keys.sort()
	for k in keys:
		var w: Dictionary = rw[k]
		if int(w.get("next", -1)) < 0 or state.tick < int(w["next"]):
			continue
		var sid := int(w["s"])
		if Relics.is_open(state, sid):
			continue
		w["next"] = -1
		if Archaeology.create_site(state, sid, {"rw": 1}):
			w["made"] = int(w.get("made", 1)) + 1


# --- Pillards (prop. 19) -------------------------------------------------------------------------------

## Chaque mois, au dernier chapitre d'un site : une bande pirate peut venir, sauf flotte du fouilleur sur place.
static func _raids(state: GameState, added: Array[Dictionary]) -> void:
	if state.pirate_density == "aucun":
		return
	var keys := state.digs.keys()
	keys.sort()
	for k in keys:
		var d: Dictionary = state.digs[k]
		var by := int(d.get("by", -1))
		if int(d.get("done", -1)) >= 0 or by < 0 or int(d.get("next", -1)) < 0 or int(d["ch"]) < int(d["chapters"]) - 1:
			continue
		var sid := int(k)
		if Archaeology.has_camp(state, by, sid):
			continue
		if _h(state, ["raid", sid, state.tick]) % 100 >= Archaeology.r_int("pirate_raid_pct", 10):
			continue
		d["clues"] = 0
		var lost := mini(Relics.fragments(state, by), int(Relics.data()["digs"]["pillage_fragments"]))
		Relics.add_fragments(state, by, -lost)
		added.append(state.add_chronicle("Des pirates descendent sur le chantier de %s : indices perdus, %d fragments en moins. Une flotte sur place les aurait découragés." % [
				Relics.site_name(state, sid), lost], Espionage.private_to(state, [by], sid)))


# --- Crises (prop. 31) ---------------------------------------------------------------------------------

static func warned(state: GameState, eid: int, k: String) -> bool:
	return Archaeology.enabled(state) and (Archaeology.sub(state, "warn").get(str(eid), {}) as Dictionary).has(k)


## Empires qui ont lu la Chute de cette crise : ils voient son présage plus tôt.
static func crisis_seers(state: GameState, k: String) -> Array:
	var out: Array = []
	if not Archaeology.enabled(state):
		return out
	for e in state.empires:
		if not e.eliminated and warned(state, e.id, k):
			out.append(e.id)
	return out


static func presage_days(state: GameState, seers: Array, k: String) -> int:
	for eid in seers:
		if warned(state, int(eid), k):
			return Archaeology.r_int("warn_presage_days", 1800)
	return 0


static func crisis_damage_pct(state: GameState, eid: int) -> int:
	if not Archaeology.enabled(state) or not Crisis.active(state):
		return 0
	return Archaeology.r_int("warn_damage_pct", 15) if warned(state, eid, Crisis.kind(state)) else 0


# --- Effets (sans appel à Research : appelés pendant Research.effects) --------------------------------

static func effects(state: GameState, eid: int) -> Dictionary:
	var out := {}
	var anc: Dictionary = Archaeology.sub(state, "anc").get(str(eid), {})
	for key in anc:
		var parts := String(key).split(":")
		if parts.size() == 2:
			Research._merge(out, (Archaeology.disparu_def(parts[0]).get(parts[1], {}) as Dictionary).get("fx", {}))
	for d in (Archaeology.sub(state, "sec").get(str(eid), {}) as Dictionary):
		if secrets_done(state, eid, String(d)):
			Research._merge(out, (Archaeology.disparu_def(String(d)).get("secrets", {}) as Dictionary).get("fx", {}))
	for d in (Archaeology.sub(state, "reco").get(str(eid), {}) as Dictionary):
		Research._merge(out, (Archaeology.disparu_def(String(d)).get("reco", {}) as Dictionary).get("fx", {}))
	# Monde-relique peuplé : +10 % de Savoir.
	for k in Archaeology.sub(state, "rw"):
		var c: Colony = state.colonies.get(int(k))
		if c != null and c.owner == eid:
			Research._merge(out, {"production_pct": {"knowledge": Archaeology.r_int("relic_world_knowledge_pct", 10)}})
	return out


# --- Chaque jour --------------------------------------------------------------------------------------

static func daily(state: GameState, added: Array[Dictionary]) -> void:
	_cradles_daily(state, added)
	_secrets_daily(state, added)
	if posmod(state.tick, 30) != 0:
		return
	_history_daily(state, added)
	_relic_worlds_daily(state)
	_raids(state, added)
	# Généalogistes d'Ossarane : +1 d'influence par mois et par antiquité exposée.
	for e in state.empires:
		if e.eliminated or e.is_npc():
			continue
		var per := Archaeology.t_int(state, e.id, "antiq_influence")
		if per > 0:
			var n := displayed(state, e.id).size() * per
			if n > 0:
				e.resources["influence"] = int(e.resources.get("influence", 0)) + n
		if int(e.stats.get("archaeo_theme", 0)) == 0 and has_theme(state, e.id):
			Research.count_stat(state, e.id, "archaeo_theme")
