class_name Capture
extends RefCounted
## Prises de guerre (étude du 2026-11-18, 50 propositions validées ; données : data/capture.json).
##
## Trois voies, un pilier (prop. 1) : l'abordage pendant la bataille (bloc B), les prises et leurs
## avaries (bloc C), puis les épaves et la rétro-ingénierie (blocs D et E, voir CaptureLore).
##
## Réglage de partie (prop. 2) : Complète (défaut du menu), Classique (seul l'Éperon d'abordage, comme
## avant ; défaut de GameState pour les anciennes sauvegardes et les tests), Désactivée (aucune prise).
##
## Pas de nouvelle ressource (prop. 3) : l'abordage dépense les troupes que les flottes portent déjà.
## Toutes les chances passent par state.rng et s'affichent avant l'ordre (prop. 4).
##
## Une PRISE est un vaisseau dont l'identifiant porte un tilde : « base~masque ». La base est la classe
## ou le modèle d'origine (modèle étranger, non modifiable) ; le masque est la somme des bits des
## avaries (rang dans data/capture.json « avaries »). « base~0 » : une prise sans avarie. Ses
## caractéristiques se calculent depuis la base (prize_stats), si bien que tout le jeu (combat,
## entretien, rapports) les lit comme une classe ordinaire, sans tableau parallèle dans Fleet.
##
## État : state.capture = {} en Classique ou Désactivée (le mode se lit dans "mode") ; en Complète :
## {"mode", "post": {flotte: 1|0} posture d'abordage, "pol": {empire: politique d'épaves},
##  "sur": {empire: "accept"|"refuse"}, "troph": {empire: jour}, "refused": {empire: jour},
##  "st": {empire: {clé: n}} statistiques, et les sous-états des épaves (voir CaptureLore.SUBS)}.

const SUBS := ["post", "pol", "sur", "troph", "refused", "st"]
const FIXED_PREFIXES := ["bete_", "crise_", "ancien_", "vivant_", "def_"]

static var _prize_cache := {}


static func data() -> Dictionary:
	return GameData.capture()


static func rule(key: String, def := 0) -> int:
	return int(data().get("rules", {}).get(key, def))


static func size_rule(size: String, key: String) -> int:
	var s: Dictionary = data().get("sizes", {}).get(size, data().get("sizes", {}).get("medium", {}))
	return int(s.get(key, 0))


# --- Réglage, sauvegarde ---------------------------------------------------------------------------

static func mode_defs() -> Array:
	return data().get("modes", [])


static func default_mode() -> String:
	return String(data().get("default_mode", "complete"))


static func setup(state: GameState, mode_id: String) -> void:
	state.capture = {}
	state.capture_mode = "classique"
	var ok := false
	for m: Dictionary in mode_defs():
		ok = ok or String(m["id"]) == mode_id
	if not ok:
		return
	state.capture_mode = mode_id
	if mode_id != "complete":
		return
	state.capture = {"mode": mode_id}
	for k in SUBS + CaptureLore.SUBS:
		state.capture[k] = {}


## Mode Complète : tout le pilier.
static func full(state: GameState) -> bool:
	return state != null and not state.capture.is_empty()


## Aucune prise du tout (pas même l'Éperon).
static func disabled(state: GameState) -> bool:
	return state != null and state.capture_mode == "desactivee"


static func mode_label(state: GameState) -> String:
	for m: Dictionary in mode_defs():
		if String(m["id"]) == state.capture_mode:
			return String(m["label"])
	return "Classique"


static func to_dict(state: GameState) -> Dictionary:
	var d := state.capture.duplicate(true)
	d["mode"] = state.capture_mode
	return d


static func from_dict(state: GameState, d: Dictionary) -> void:
	state.capture = {}
	state.capture_mode = String(d.get("mode", "classique"))
	if state.capture_mode != "complete":
		return
	state.capture = GameData._to_ints(d.duplicate(true))
	for k in SUBS + CaptureLore.SUBS:
		if not state.capture.has(k):
			state.capture[k] = {}


static func sub(state: GameState, key: String) -> Dictionary:
	return state.capture[key]


static func note_stat(state: GameState, eid: int, key: String, n := 1) -> void:
	if not full(state):
		return
	var st: Dictionary = sub(state, "st").get_or_add(str(eid), {})
	st[key] = int(st.get(key, 0)) + n


static func stat(state: GameState, eid: int, key: String) -> int:
	if not full(state):
		return 0
	return int(sub(state, "st").get(str(eid), {}).get(key, 0))


# --- Couches d'espèce (bloc F) ---------------------------------------------------------------------

static func layer(state: GameState, eid: int, key: String) -> bool:
	var e := state.get_empire(eid)
	if e == null or e.is_npc():
		return false
	var req: Variant = data().get("layers", {}).get(key, {})
	if req is Array:
		for r in req:
			if FactionTraits.species_matches(e.faction(), r):
				return true
		return false
	return not (req as Dictionary).is_empty() and FactionTraits.species_matches(e.faction(), req)


# --- Prises : identifiants et caractéristiques (bloc C) ---------------------------------------------

static func is_prize(ship_id: String) -> bool:
	return ship_id.contains("~") and not ship_id.ends_with("~copie")


static func base_of(ship_id: String) -> String:
	return ship_id.get_slice("~", 0) if is_prize(ship_id) else ship_id


static func mask_of(ship_id: String) -> int:
	return int(ship_id.get_slice("~", 1)) if is_prize(ship_id) else 0


static func prize_id(base: String, mask: int) -> String:
	return "%s~%d" % [base_of(base), mask]


static func avarie_defs() -> Array:
	return data().get("avaries", [])


## Avaries d'une prise (définitions, dans l'ordre du catalogue).
static func avaries_of(ship_id: String) -> Array:
	var out: Array = []
	var m := mask_of(ship_id)
	var defs := avarie_defs()
	for i in defs.size():
		if m & (1 << i):
			out.append(defs[i])
	return out


static func avarie_count(ship_id: String) -> int:
	return avaries_of(ship_id).size()


static func clear_cache() -> void:
	_prize_cache.clear()


## Caractéristiques d'une prise : celles de sa base, avaries appliquées (prop. 16).
@warning_ignore("integer_division")
static func prize_stats(ship_id: String) -> Dictionary:
	if _prize_cache.has(ship_id):
		return _prize_cache[ship_id]
	var base := base_of(ship_id)
	var b := GameData.ship(base)
	if b.is_empty():
		return {}
	var sd := b.duplicate(true)
	var avs := avaries_of(ship_id)
	for av: Dictionary in avs:
		var fx: Dictionary = av.get("fx", {})
		for k in fx:
			var pct := int(fx[k])
			match String(k):
				"weapons":
					var w: Dictionary = sd.get("weapons", {})
					for wk in w.keys():
						w[wk] = maxi(1, int(w[wk]) * (100 + pct) / 100)
				"vision_flat":
					sd["vision"] = maxi(0, int(sd.get("vision", 0)) + pct)
				_:
					if sd.has(k):
						var v := int(sd[k]) * (100 + pct) / 100
						sd[k] = maxi(1, v) if String(k) == "hp" else maxi(0, v)
	var up: Dictionary = (sd.get("upkeep", {}) as Dictionary).duplicate()
	var cut := mini(90, avs.size() * rule("upkeep_per_avarie_pct", 10))
	for r in up.keys():
		up[r] = int(up[r]) * (100 - cut) / 100
	sd["upkeep"] = up
	sd["label"] = "%s (prise)" % String(b.get("label", base))
	sd["plural"] = "%s (prises)" % String(b.get("plural", b.get("label", base)))
	sd["prize"] = true
	sd["prize_of"] = base
	sd.erase("unique_per_empire")  # une méga prise ne compte pas dans « une par empire » (prop. 10)
	var names := PackedStringArray()
	for av: Dictionary in avs:
		names.append(String(av["label"]))
	sd["avaries"] = Array(names)
	_prize_cache[ship_id] = sd
	return sd


## Origine lisible d'une prise : l'empire qui a conçu le modèle, s'il est connu.
static func origin_owner(ship_id: String) -> int:
	return int(GameData.ship(base_of(ship_id)).get("owner", -1))


static func base_cost(ship_id: String) -> Dictionary:
	return GameData.ship(base_of(ship_id)).get("cost", {})


@warning_ignore("integer_division")
static func scaled_cost(cost: Dictionary, pct: int) -> Dictionary:
	var out := {}
	for r in cost:
		var v := int(cost[r]) * pct / 100
		if v > 0:
			out[r] = v
	return out


## Tire n avaries (entre lo et hi) qui s'ajoutent à celles du masque.
static func roll_avaries(state: GameState, mask: int, lo: int, hi: int) -> int:
	var n := state.rng.randi_range(lo, maxi(lo, hi))
	var defs := avarie_defs().size()
	for _i in n:
		var free: Array[int] = []
		for b in defs:
			if not (mask & (1 << b)):
				free.append(b)
		if free.is_empty():
			break
		mask |= 1 << free[state.rng.randi_range(0, free.size() - 1)]
	return mask


static func fixed_unit(ship_id: String) -> bool:
	for p in FIXED_PREFIXES:
		if ship_id.begins_with(p):
			return true
	return false


static func hull_of(ship_id: String) -> String:
	return String(GameData.ship(base_of(ship_id)).get("hull", base_of(ship_id)))


static func unboardable(ship_id: String) -> bool:
	return fixed_unit(ship_id) or (data().get("unboardable_hulls", []) as Array).has(hull_of(ship_id))


# --- Posture d'abordage (prop. 5) -------------------------------------------------------------------

## Peut-on se mettre en posture ? Technologie Équipes de prise, doctrine Abordage ou Éperon.
static func posture_open(state: GameState, f: Fleet) -> bool:
	if not full(state) or layer(state, f.owner, "no_board"):
		return false
	return Research.knows(state, f.owner, "equipes_prise") or Research.knows(state, f.owner, "abordage") \
			or PeopleHulls.fleet_flag(f, "boarding") or layer(state, f.owner, "trophies")


## Posture active : choisie, ou par défaut chez la Horde (prop. 36) ; l'Éperon aborde toujours.
static func posture(state: GameState, f: Fleet) -> bool:
	if not posture_open(state, f):
		return false
	var v: Variant = sub(state, "post").get(str(f.id))
	if v != null:
		return int(v) == 1
	return layer(state, f.owner, "trophies")


static func set_posture(state: GameState, fid: int, on: bool) -> void:
	sub(state, "post")[str(fid)] = 1 if on else 0


static func check_posture(state: GameState, player: int, fid: int) -> String:
	if not full(state):
		return "les prises de guerre complètes ne sont pas en jeu dans cette partie"
	var f: Fleet = state.fleets.get(fid)
	if f == null or f.owner != player:
		return "cette flotte ne vous appartient pas"
	if layer(state, player, "no_board"):
		return "votre peuple n'aborde pas : une onde n'a pas de mains"
	if not posture_open(state, f):
		return "il faut la technologie Équipes de prise (ou la doctrine Abordage)"
	return ""


# --- Résolution de l'abordage (prop. 6 à 10, 13, 14) ------------------------------------------------

static func troops_needed(ship_id: String) -> int:
	return size_rule(Combat.ship_size(ship_id), "troops")


static func hp_threshold_ok(g: Fleet, i: int) -> bool:
	var sid := g.ships[i]
	return g.hp[i] > 0 and g.hp[i] * 100 <= Fleet.max_hp_of(sid) * size_rule(Combat.ship_size(sid), "hp_pct")


## Force d'abordage d'une flotte contre un vaisseau (troupes engagées et bonus).
@warning_ignore("integer_division")
static func force(state: GameState, f: Fleet, target: String) -> int:
	var t := troops_needed(target)
	var intrusion := f.troops < t and layer(state, f.owner, "intrusion")
	var base := t
	if intrusion:
		base = size_rule(Combat.ship_size(target), "crew") * rule("intrusion_pct", 50) / 100
	var pct := 100
	if Combat._fleet_has_flag(f, "grapple"):
		pct += rule("grapple_pct", 25)
	if PeopleHulls.fleet_flag(f, "boarding"):
		pct += rule("eperon_pct", 50)
	pct += Research.fx_int(state, f.owner, "board_pct")
	var h := Heroes.assigned_to(state, "fleet", f.id, f.owner)
	if not h.is_empty():
		pct += Heroes.trait_fx(h, "board_pct")
	return maxi(1, base * pct / 100)


@warning_ignore("integer_division")
static func defense(state: GameState, g: Fleet, i: int) -> int:
	var sid := g.ships[i]
	var pct := 100
	if bool(GameData.ship(sid).get("board_def", false)):
		pct += rule("board_def_pct", 50)
	if layer(state, g.owner, "no_surrender_def"):
		pct += rule("foi_def_pct", 50)
	return maxi(1, size_rule(Combat.ship_size(sid), "crew") * pct / 100)


static func chance(state: GameState, f: Fleet, g: Fleet, i: int) -> int:
	var fo := force(state, f, g.ships[i])
	var de := defense(state, g, i)
	@warning_ignore("integer_division")
	return clampi(fo * 100 / (fo + de), rule("chance_min", 5), rule("chance_max", 90))


static func has_mega_prize(state: GameState, eid: int) -> bool:
	for fid in state.sorted_fleet_ids():
		var f: Fleet = state.fleets[fid]
		if f.owner != eid:
			continue
		for s in f.ships:
			if is_prize(s) and Combat.ship_size(s) == "titan":
				return true
	return false


static func _ai_skill(state: GameState, eid: int) -> int:
	var e := state.get_empire(eid)
	if e == null or not e.is_ai() or e.is_npc():
		return -1
	return int(AiLevels.level(e.ai_level).get("military", {}).get("skill", 1))


## Peut-on aborder ce vaisseau (sans la chance) ?
static func can_board(state: GameState, f: Fleet, g: Fleet, i: int, fighters: Array) -> bool:
	var sid := g.ships[i]
	if unboardable(sid) or not hp_threshold_ok(g, i):
		return false
	if f.troops < troops_needed(sid) and not layer(state, f.owner, "intrusion"):
		return false
	if Combat.ship_size(sid) == "titan" and has_mega_prize(state, f.owner):
		return false
	if g.ships.size() < 2:
		for o in fighters:
			if o != g and (o as Fleet).owner == g.owner and not (o as Fleet).ships.is_empty():
				return false  # on ne vide pas une flotte tant que son camp en a d'autres (prop. 10)
	return true


## Un jour de bataille : chaque flotte qui aborde tente une prise. Renvoie
## [[flotte preneuse, identifiant pris (ou ""), empire victime, classe d'origine]...].
static func boarding(state: GameState, b: Dictionary, fighters: Array[Fleet], phase: int, day_log: Dictionary, added: Array[Dictionary]) -> Array:
	if disabled(state):
		return []
	if not full(state):
		var out0: Array = []
		for cap in PeopleHulls.boarding(state, fighters, phase):
			out0.append([cap[0], cap[1], cap[2], cap[1]])
		return out0
	var out: Array = []
	for f in fighters:
		if f.ships.is_empty() or not state.fleets.has(f.id):
			continue
		var eperon := PeopleHulls.fleet_flag(f, "boarding")
		if not eperon and not posture(state, f):
			continue
		var skill := _ai_skill(state, f.owner)
		if skill == 0 and not eperon:
			continue  # la Recrue n'aborde jamais (prop. 14)
		var intrusion := layer(state, f.owner, "intrusion")
		if phase < 2 and not (phase == 1 and (Combat._fleet_has_flag(f, "assault_pods") or intrusion)):
			continue  # au contact, sauf capsules d'assaut et intrusion (prop. 8, 40)
		var best: Array = []
		var best_v := -1
		for g in fighters:
			if g == f or g.ships.is_empty() or not Combat.hostile_fleets(state, f, g):
				continue
			for i in g.ships.size():
				if not can_board(state, f, g, i, fighters):
					continue
				var v := Combat.ship_strength(base_of(g.ships[i]))
				if skill >= 2 and (Combat.ship_size(g.ships[i]) == "titan" or PeopleHulls.is_people_hull(hull_of(g.ships[i]))):
					v *= 3  # le Vétéran vise ce qui rapporte
				if v > best_v:
					best_v = v
					best = [g, i]
		if best.is_empty():
			continue
		var tg: Fleet = best[0]
		var ti: int = best[1]
		var ch := chance(state, f, tg, ti)
		if skill == 1 and ch < rule("normal_ai_min", 60) and not eperon:
			continue
		if skill >= 2 and ch < 35 and not eperon:
			continue
		var res := _attempt(state, b, f, tg, ti, ch, intrusion, added)
		if not res.is_empty():
			out.append(res)
		if day_log.has("shots"):
			day_log.get_or_add("boards", []).append([CombatSystem._unit(b, f.id, 0), CombatSystem._unit(b, tg.id, ti), 1 if not res.is_empty() else 0])
	return out


static func _attempt(state: GameState, b: Dictionary, f: Fleet, g: Fleet, i: int, ch: int, intrusion: bool, added: Array[Dictionary]) -> Array:
	var cls := g.ships[i]
	var need := troops_needed(cls)
	var spent := 0 if (intrusion and f.troops < need) else need
	var roll := state.rng.randi_range(0, 99)
	note_stat(state, f.owner, "boardings")
	if roll >= ch:
		f.troops = maxi(0, f.troops - spent)
		return []
	f.troops = maxi(0, f.troops - spent * rule("keep_pct", 50) / 100)
	var top := HeroFall.top_strength(g)
	var flagship := Combat.ship_strength(cls) >= top and top > 0
	var victim := g.owner
	var sname := state.galaxy.systems[int(b["system"])].system_name
	# Charge d'autodestruction (prop. 9) : le vaisseau saute plutôt que de se rendre.
	if bool(GameData.ship(cls).get("self_destruct_capture", false)):
		var dmg := Fleet.max_hp_of(cls) * rule("self_destruct_pct", 25) / 100
		var k := state.rng.randi_range(0, f.ships.size() - 1)
		f.hp[k] = maxi(1, f.hp[k] - dmg)
		f.troops = maxi(0, f.troops - spent)
		g.remove_at(i)
		return [f, "", victim, cls]
	# Coques synthétiques : elles s'effacent plutôt que de servir un autre (prop. 40).
	if layer(state, victim, "intrusion") and not layer(state, f.owner, "intrusion"):
		g.remove_at(i)
		CaptureLore.study_ship(state, f.owner, cls, false)  # la coque muette s'étudie encore
		if not state.get_empire(f.owner).is_ai():
			added.append(state.add_chronicle("À %s, le %s abordé s'efface lui-même : quand vos soldats atteignent la passerelle, il ne reste qu'une coque muette." % [
					sname, String(GameData.ship(cls).get("label", cls))], Espionage.private_to(state, [f.owner], int(b["system"]))))
		return [f, "", victim, cls]
	var hp := g.hp[i]
	g.remove_at(i)
	var pid := prize_id(cls, roll_avaries(state, mask_of(cls), rule("board_avaries_min", 1), rule("board_avaries_max", 2)))
	f.add_ship(pid, mini(hp, Fleet.max_hp_of(pid)), -1)
	on_prize(state, f.owner, victim, pid, int(b["system"]), added)
	earn_trait(state, Heroes.assigned_to(state, "fleet", f.id, f.owner), "abordeur", "ab_n", added)
	if flagship:
		var h := Heroes.assigned_to(state, "fleet", g.id, g.owner)
		if not h.is_empty():
			Heroes._wound(state, h, added, "son vaisseau amiral a été pris à l'abordage", f.owner)  # prisonnier (prop. 13)
		Diplomacy.remember(state, victim, f.owner, "flagship_taken")
	return [f, pid, victim, cls]


## Trait de héros gagné à la troisième prise ou récupération (prop. 13).
static func earn_trait(state: GameState, h: Dictionary, trait_id: String, counter: String, added: Array[Dictionary]) -> void:
	if h.is_empty():
		return
	h[counter] = int(h.get(counter, 0)) + 1
	var traits: Array = h.get("traits", [])
	if int(h[counter]) < 3 or traits.has(trait_id) or traits.size() >= int(Heroes.data().get("max_traits", 6)):
		return
	traits.append(trait_id)
	h["traits"] = traits
	added.append(state.add_chronicle("%s y prend goût : le voilà %s." % [String(h["name"]), String(Heroes.data()["traits"][trait_id]["label"])],
			Espionage.private_to(state, [int(h["owner"])])))


## Une prise vient de changer de camp (abordage, reddition, récupération) : effets des peuples.
static func on_prize(state: GameState, taker: int, victim: int, pid: String, sid: int, added: Array[Dictionary]) -> void:
	Research.count_stat(state, taker, "prizes")
	note_stat(state, taker, "prizes")
	if Combat.ship_size(pid) == "titan":
		note_stat(state, taker, "mega_prizes")
		Announce.next(state, "mega_prize", {"actor": taker, "target": victim, "system": sid})
		added.append(state.add_chronicle("%s prend %s à %s : une méga-coque change de pavillon. Les chantiers des deux camps prennent des notes." % [
				state.get_empire(taker).display_name(), String(GameData.ship(base_of(pid)).get("label", pid)),
				state.get_empire(victim).short_name() if state.get_empire(victim) != null else "l'ennemi"], Espionage.public_to(state, [taker, victim])))
	if layer(state, taker, "trophies"):
		sub(state, "troph")[str(taker)] = state.tick  # trophée de clan (prop. 36)
		if not state.hero_meta.is_empty():
			var hm := Heroes.meta(state, taker)
			hm["renown"] = int(hm["renown"]) + 10
	var e := state.get_empire(taker)
	if e != null and FactionTraits.has_fervor(e.faction()) and layer(state, taker, "no_surrender_def"):
		e.fervor = mini(int(e.faction()["fervor"]["max"]), e.fervor + rule("fervor_per_prize", 3))  # conversion (prop. 38)
	if (data().get("layers", {}).get("sacred_hulls", []) as Array).has(hull_of(pid)):
		_sacrilege(state, taker, victim, added)


## Prendre une Cathédrale : toute la foi s'en souvient (prop. 38).
static func _sacrilege(state: GameState, taker: int, victim: int, added: Array[Dictionary]) -> void:
	for o in state.empires:
		if o.eliminated or o.id == taker or not layer(state, o.id, "no_surrender_def"):
			continue
		Diplomacy.remember(state, o.id, taker, "sacrilege")
	added.append(state.add_chronicle("Sacrilège : %s a pris une Cathédrale de %s. Dans tous les temples de la foi, on prie contre eux ; ailleurs, on prie pour ne pas être confondu avec eux." % [
			state.get_empire(taker).display_name(), state.get_empire(victim).short_name() if state.get_empire(victim) != null else "la foi"], Espionage.public_to(state, [taker, victim])))


# --- Reddition (prop. 11, 38, 42) -------------------------------------------------------------------

static func surrender_pct(state: GameState, eid: int) -> int:
	var e := state.get_empire(eid)
	if e == null or e.is_npc():
		return 0
	var sd: Dictionary = data().get("surrender", {})
	for r: Dictionary in sd.get("by_layer", []):
		if FactionTraits.species_matches(e.faction(), r["species"]):
			return int(r["pct"])
	return int(sd.get("base", 30))


@warning_ignore("integer_division")
static func fleet_power(f: Fleet) -> int:
	var n := 0
	for i in f.ships.size():
		n += maxi(1, Combat.ship_strength(f.ships[i]) * f.hp[i] / Fleet.max_hp_of(f.ships[i]))
	return n


## Fin de phase : un camp à bout, dominé à 3 contre 1, peut se rendre. Renvoie les prises
## [[flotte preneuse, identifiant, empire victime, classe d'origine]...].
@warning_ignore("integer_division")
static func surrenders(state: GameState, b: Dictionary, fighters: Array[Fleet], day: int, added: Array[Dictionary]) -> Array:
	var out: Array = []
	if not full(state) or day % 2 != 0 or day >= Combat.battle_days():
		return out
	var done: Array = b.get_or_add("sur_done", [])
	var owners: Array[int] = []
	for f in fighters:
		if not owners.has(f.owner) and not f.ships.is_empty():
			owners.append(f.owner)
	owners.sort()
	for loser in owners:
		if done.has(loser) or GameState.is_npc(loser):
			continue
		var mine := 0
		var spent := true
		var foes := {}
		for f in fighters:
			if f.ships.is_empty():
				continue
			if f.owner == loser:
				mine += fleet_power(f)
				for i in f.ships.size():
					if f.hp[i] * 100 > Fleet.max_hp_of(f.ships[i]) * rule("surrender_hp_pct", 50):
						spent = false
			elif Combat.at_war(state, loser, f.owner):
				foes[f.owner] = int(foes.get(f.owner, 0)) + fleet_power(f)
		if not spent or foes.is_empty() or mine <= 0:
			continue
		var winner := -1
		var top := 0
		var total := 0
		var ks := foes.keys()
		ks.sort()
		for k in ks:
			total += int(foes[k])
			if int(foes[k]) > top and not GameState.is_npc(int(k)):
				top = int(foes[k])
				winner = int(k)
		if winner < 0 or total < mine * rule("surrender_ratio", 3):
			continue
		if state.rng.randi_range(0, 99) >= surrender_pct(state, loser):
			continue
		done.append(loser)
		out.append_array(_resolve_surrender(state, b, fighters, loser, winner, added))
	return out


static func surrender_policy(state: GameState, eid: int) -> String:
	return String(sub(state, "sur").get(str(eid), "accept")) if full(state) else "accept"


static func _resolve_surrender(state: GameState, b: Dictionary, fighters: Array[Fleet], loser: int, winner: int, added: Array[Dictionary]) -> Array:
	var out: Array = []
	var sid := int(b["system"])
	var sname := state.galaxy.systems[sid].system_name
	var accept := surrender_policy(state, winner) != "refuse"
	if state.get_empire(winner).is_ai():
		accept = true
	if not accept:
		if layer(state, winner, "honor"):
			sub(state, "refused")[str(winner)] = state.tick  # refuser quartier coûte (prop. 42)
		WarLaws.war_crime(state, winner, loser, "surrender_refused")  # Convention des prises (prop. 47)
		added.append(state.add_chronicle("À %s, %s offre sa reddition ; %s la refuse. Le feu reprend. Les historiens noteront, les survivants aussi." % [
				sname, state.get_empire(loser).short_name(), state.get_empire(winner).short_name()], Espionage.private_to(state, [winner, loser], sid)))
		return out
	var into: Fleet = null
	for f in fighters:
		if f.owner == winner and not f.ships.is_empty() and (into == null or f.ships.size() > into.ships.size()):
			into = f
	if into == null:
		return out
	var honors := layer(state, winner, "honor")
	var n := 0
	for f in fighters:
		if f.owner != loser:
			continue
		var h := Heroes.assigned_to(state, "fleet", f.id, f.owner)
		if not h.is_empty():
			Heroes._wound(state, h, added, "sa flotte s'est rendue", winner)
		while not f.ships.is_empty():
			var cls := f.ships[0]
			var hp := f.hp[0]
			f.remove_at(0)
			if unboardable(cls):
				continue
			var mask := mask_of(cls) if honors else roll_avaries(state, mask_of(cls), rule("board_avaries_min", 1), rule("board_avaries_max", 2))
			var pid := prize_id(cls, mask)
			into.add_ship(pid, mini(hp, Fleet.max_hp_of(pid)), -1)
			Research.count_stat(state, winner, "prizes")
			note_stat(state, winner, "prizes")
			out.append([into, pid, loser, cls])
			n += 1
		state.fleets.erase(f.id)
	b["surrender"] = [loser, winner, n]
	note_stat(state, winner, "surrenders")
	added.append(state.add_chronicle("À %s, %s se rend à %s%s : %d vaisseau%s changent de pavillon." % [
			sname, state.get_empire(loser).short_name(), state.get_empire(winner).short_name(),
			" avec les honneurs" if honors else "", n, "x" if n > 1 else ""], Espionage.private_to(state, [winner, loser], sid)))
	return out


# --- Réparations (prop. 15) --------------------------------------------------------------------------

## Une prise ne se répare qu'à un chantier à vous.
static func repair_blocked(state: GameState, f: Fleet, ship_id: String) -> bool:
	if not full(state) or not is_prize(ship_id):
		return false
	return f.is_moving() or not Fleets.has_own_yard(state, f.owner, f.system_id)


# --- Actions sur les prises (prop. 17 à 20) ---------------------------------------------------------

static func _yard_check(state: GameState, player: int, f: Fleet) -> String:
	if f == null or f.owner != player:
		return "cette flotte ne vous appartient pas"
	if f.is_moving() or not Fleets.has_own_yard(state, player, f.system_id):
		return "il faut être à l'arrêt dans un système où vous avez une colonie (son chantier fait le travail)"
	if state.battles.has(f.system_id):
		return "impossible en pleine bataille"
	return ""


static func repair_cost(ship_id: String) -> Dictionary:
	return scaled_cost(base_cost(ship_id), rule("repair_cost_pct", 25))


static func refit_cost(design_id: String) -> Dictionary:
	return scaled_cost(GameData.ship(design_id).get("cost", {}), rule("refit_cost_pct", 50))


@warning_ignore("integer_division")
static func scrap_gain(state: GameState, eid: int, ship_id: String) -> Dictionary:
	var pct := rule("scrap_pct", 30)
	if layer(state, eid, "living"):
		pct *= 2  # la ruche digère ses prises (prop. 39)
	var m := int(base_cost(ship_id).get("materials", 0)) * pct / 100
	return {"materials": maxi(1, m)}


@warning_ignore("integer_division")
static func sell_price(state: GameState, eid: int, ship_id: String, how: String) -> int:
	var c := base_cost(ship_id)
	var v := int(c.get("materials", 0)) + int(c.get("energy", 0))
	var pct := rule("sell_market_pct", 40)
	match how:
		"pirates":
			pct = rule("sell_pirates_pct", 60)
		"empire":
			pct = rule("sell_empire_pct", 50)
	if layer(state, eid, "scrappers"):
		pct = pct * (100 + rule("profit_sell_pct", 50)) / 100  # revente (prop. 37)
	v = v * pct / 100
	return maxi(1, v * (100 - avarie_count(ship_id) * rule("upkeep_per_avarie_pct", 10)) / 100)


## Vérifie une action sur une prise. act : "repair", "refit" (x = modèle), "scrap", "sell" (x = market,
## pirates ou empire, y = empire acheteur).
static func check_act(state: GameState, player: int, act: String, d: Dictionary) -> String:
	if not full(state):
		return "les prises de guerre complètes ne sont pas en jeu dans cette partie"
	match act:
		"posture":
			return check_posture(state, player, int(d.get("fleet", -1)))
		"policy":
			return CaptureLore.check_policy(state, player, String(d.get("x", "")))
		"surrender":
			return "" if ["accept", "refuse"].has(String(d.get("x", ""))) else "choix inconnu"
		"loot", "tomb":
			return CaptureLore.check_act(state, player, act, d)
	var f: Fleet = state.fleets.get(int(d.get("fleet", -1)))
	var ship := String(d.get("ship", ""))
	if f == null or f.owner != player:
		return "cette flotte ne vous appartient pas"
	if not f.ships.has(ship):
		return "ce vaisseau n'est pas dans la flotte"
	if not is_prize(ship) and act != "scrap":
		return "ce n'est pas une prise"
	var why := _yard_check(state, player, f)
	if why != "" and act != "sell":
		return why
	var e := state.get_empire(player)
	match act:
		"repair":
			if avarie_count(ship) == 0:
				return "aucune avarie à réparer"
			if not Economy.can_afford(e, repair_cost(ship)):
				return "ressources insuffisantes (il faut %s)" % GameData.format_amounts(repair_cost(ship))
		"refit":
			var to := String(d.get("x", ""))
			if not Designs.can_build_id(state, player, to):
				return "modèle inconnu ou que vous ne construisez pas"
			if Combat.ship_size(to) != Combat.ship_size(ship):
				return "la refonte garde la taille de la coque"
			if not Economy.can_afford(e, refit_cost(to)):
				return "ressources insuffisantes (il faut %s)" % GameData.format_amounts(refit_cost(to))
		"scrap":
			if f.ships.size() < 2:
				return "démanteler le dernier vaisseau d'une flotte : séparez-le d'abord"
		"sell":
			if f.ships.size() < 2:
				return "vendre le dernier vaisseau d'une flotte : séparez-le d'abord"
			var how := String(d.get("x", "market"))
			if not ["market", "pirates", "empire"].has(how):
				return "acheteur inconnu"
			if how == "empire":
				var to2 := state.get_empire(int(d.get("y", -1)))
				if to2 == null or to2.eliminated or to2.id == player or to2.is_npc() or Combat.at_war(state, player, to2.id):
					return "il faut un empire en paix avec vous"
				if int(to2.resources.get("energy", 0)) < sell_price(state, player, ship, how):
					return "%s n'a pas de quoi payer" % to2.short_name()
				if not to2.is_ai():
					return "seuls les empires de l'IA achètent sur-le-champ"
		_:
			return "action inconnue : %s" % act
	return ""


static func apply_act(state: GameState, player: int, act: String, d: Dictionary) -> Array[Dictionary]:
	var added: Array[Dictionary] = []
	match act:
		"posture":
			set_posture(state, int(d["fleet"]), bool(d.get("on", true)))
			return added
		"policy":
			sub(state, "pol")[str(player)] = String(d["x"])
			return added
		"surrender":
			sub(state, "sur")[str(player)] = String(d["x"])
			return added
		"loot", "tomb":
			return CaptureLore.apply_act(state, player, act, d)
	var f: Fleet = state.fleets[int(d["fleet"])]
	var ship := String(d["ship"])
	var e := state.get_empire(player)
	var i := f.ships.find(ship)
	match act:
		"repair":
			Economy.pay(e, repair_cost(ship))
			var avs := avaries_of(ship)
			var m := mask_of(ship)
			var defs := avarie_defs()
			for bit in defs.size():
				if m & (1 << bit):
					m &= ~(1 << bit)
					break
			var hp := f.hp[i]
			var gen := f.gen[i]
			f.remove_at(i)
			var nid := prize_id(ship, m)
			f.add_ship(nid, mini(hp, Fleet.max_hp_of(nid)), gen)
			f.refit_left = maxi(f.refit_left, rule("repair_days", 20))
			note_stat(state, player, "repairs")
			if not avs.is_empty() and not e.is_ai():
				added.append(state.add_chronicle("Chantier de %s : %s perd son avarie « %s ». Le reste attendra la prochaine facture." % [
						state.galaxy.systems[f.system_id].system_name, String(GameData.ship(base_of(ship)).get("label", ship)), String(avs[0]["label"])], [player]))
		"refit":
			var to := String(d["x"])
			Economy.pay(e, refit_cost(to))
			f.remove_at(i)
			f.add_ship(to, -1, Research.mark_gen(state, player))
			note_stat(state, player, "refits")
		"scrap":
			for r in scrap_gain(state, player, ship):
				e.resources[r] = int(e.resources.get(r, 0)) + int(scrap_gain(state, player, ship)[r])
			f.remove_at(i)
			note_stat(state, player, "scrapped")
			Research.count_stat(state, player, "scrapped")
			var learned := CaptureLore.study_ship(state, player, ship, true)
			if layer(state, player, "living"):
				var larva := String(data().get("layers", {}).get("larva_ship", ""))
				if larva != "" and Designs.hull_ids_of(state, player).has(larva):
					f.add_ship(larva, -1, Research.mark_gen(state, player))
			if not e.is_ai():
				added.append(state.add_chronicle("%s démonte %s au chantier de %s : %s%s." % [e.short_name(), String(GameData.ship(base_of(ship)).get("label", ship)),
						state.galaxy.systems[f.system_id].system_name, GameData.format_amounts(scrap_gain(state, player, ship)),
						(" ; les ingénieurs en tirent %s" % learned) if learned != "" else ""], [player]))
		"sell":
			var how := String(d.get("x", "market"))
			var price := sell_price(state, player, ship, how)
			f.remove_at(i)
			e.resources["energy"] = int(e.resources.get("energy", 0)) + price
			note_stat(state, player, "sold")
			if how == "empire":
				var to2 := state.get_empire(int(d["y"]))
				to2.resources["energy"] = int(to2.resources.get("energy", 0)) - price
				var cap := f.system_id
				var cp = state.galaxy.get_planet(to2.capital_planet) if to2.capital_planet >= 0 else null
				if cp != null:
					cap = int(cp.system_id)
				state.spawn_ship(to2.id, ship, cap)
			elif how == "pirates":
				for o in state.empires:
					if not o.eliminated and o.id != player and not o.is_npc():
						Diplomacy.remember(state, o.id, player, "black_market")
			if not e.is_ai():
				added.append(state.add_chronicle("%s vend %s %s pour %d énergie. Le marché de l'occasion ne pose pas de questions%s." % [
						e.short_name(), String(GameData.ship(base_of(ship)).get("label", ship)),
						{"market": "au marché", "pirates": "aux pirates", "empire": "à un voisin"}[how], price,
						", surtout celui-là" if how == "pirates" else ""], [player]))
	return added


# --- Le temps qui passe -------------------------------------------------------------------------

static func daily(state: GameState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not full(state):
		return out
	if state.tick % 30 == 0:
		_living_decay(state)
		_prune_postures(state)
	out.append_array(CaptureLore.daily(state))
	return out


## Les vaisseaux vivants d'une ruche dépérissent entre des mains étrangères (prop. 39).
@warning_ignore("integer_division")
static func _living_decay(state: GameState) -> void:
	for fid in state.sorted_fleet_ids():
		var f: Fleet = state.fleets[fid]
		if layer(state, f.owner, "living"):
			continue
		for i in f.ships.size():
			if not is_prize(f.ships[i]):
				continue
			var req: Dictionary = Designs.hull(hull_of(f.ships[i])).get("requires", {}).get("species", {})
			if (req.get("archetype", []) as Array).has("ruche"):
				f.hp[i] = maxi(1, f.hp[i] - maxi(1, Fleet.max_hp_of(f.ships[i]) * rule("ruche_decay_pct", 5) / 100))


static func _prune_postures(state: GameState) -> void:
	var p := sub(state, "post")
	for k in p.keys():
		if not state.fleets.has(int(k)):
			p.erase(k)


## Stabilité : trophées de clan, quartier refusé (prop. 36, 42).
static func stability_parts(state: GameState, _sid: int, owner: int) -> Array:
	var out: Array = []
	if not full(state):
		return out
	var t := int(sub(state, "troph").get(str(owner), -100000))
	if state.tick - t < rule("trophy_days", 360):
		out.append(["Trophées de clan", rule("trophy_stability", 3)])
	var r := int(sub(state, "refused").get(str(owner), -100000))
	if state.tick - r < rule("refused_days", 360):
		out.append(["Quartier refusé", rule("refused_stability", -5)])
	return out
