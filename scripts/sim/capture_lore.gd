class_name CaptureLore
extends RefCounted
## Prises de guerre, lots 2 et 3 : épaves, récupération, rétro-ingénierie (voir Capture, data/capture.json).
##
## Sous-états (dans state.capture, seulement en mode Complète) :
##  "fields": {système: [{"o": empire, "s": vaisseau}...]} champ d'épaves composé (prop. 21) ;
##  "loot": {empire: {"list": [{"s", "sid", "until", "o"}...], "auto": bool}} butin en attente (prop. 22, 44) ;
##  "ana": {empire: {modèle: %}} analyse des modèles ennemis (prop. 31, 35) ;
##  "studies": {empire: {coque: n}} études de coques de peuple (prop. 32) ; "copies": {empire: {coque: 1}} ;
##  "tomb": Vaisseau-tombe (prop. 27, voir CaptureTomb).

const SUBS := ["fields", "loot", "ana", "studies", "copies", "tomb"]
const COPY := "~copie"


static func _r(key: String, def := 0) -> int:
	return Capture.rule(key, def)


# --- Politique d'épaves (prop. 23, 37) --------------------------------------------------------------

static func policy_def(id: String) -> Dictionary:
	for p: Dictionary in Capture.data().get("policies", []):
		if String(p["id"]) == id:
			return p
	return {}


static func policy(state: GameState, eid: int) -> String:
	if not Capture.full(state):
		return "etudier"
	if Capture.layer(state, eid, "scrappers"):
		return "both"  # les ferrailleurs font les deux d'office (prop. 37)
	var p := String(Capture.sub(state, "pol").get(str(eid), "etudier"))
	if p == "both" and check_policy(state, eid, "both") != "":
		return "etudier"
	return p


static func studies(state: GameState, eid: int) -> bool:
	return policy(state, eid) != "ferrailler"


static func scavenges(state: GameState, eid: int) -> bool:
	return policy(state, eid) != "etudier"


static func check_policy(state: GameState, player: int, x: String) -> String:
	var d := policy_def(x)
	if d.is_empty():
		return "politique inconnue"
	var req: Dictionary = d.get("requires", {})
	if req.is_empty():
		return ""
	if Capture.layer(state, player, "scrappers") or Research.knows(state, player, String(req.get("tech", ""))):
		return ""
	return "réservé au credo Profit, au gouvernement Syndicat ou à la technologie Ingénierie inverse"


# --- Champ d'épaves composé (prop. 21) --------------------------------------------------------------

static func field(state: GameState, sid: int) -> Array:
	if not Capture.full(state):
		return []
	return Capture.sub(state, "fields").get(str(sid), [])


static func _add_wreck(state: GameState, sid: int, owner: int, ship: String) -> void:
	var fl: Array = Capture.sub(state, "fields").get_or_add(str(sid), [])
	fl.append({"o": owner, "s": ship})
	while fl.size() > _r("field_cap", 60):
		fl.pop_front()


static func graveyard(state: GameState, sid: int) -> bool:
	return Terrain.active(state) and Terrain.zone(state, sid) == "cimetiere"


## Texte court d'un champ pour la lentille Terrain (prop. 46).
static func field_text(state: GameState, sid: int) -> String:
	var fl := field(state, sid)
	if fl.is_empty():
		return ""
	var by := {}
	for w: Dictionary in fl:
		var e := state.get_empire(int(w["o"]))
		var n := e.short_name() if e != null else "?"
		by[n] = int(by.get(n, 0)) + 1
	var parts := PackedStringArray()
	var keys := by.keys()
	keys.sort()
	for k in keys:
		parts.append("%s %d" % [k, int(by[k])])
	return "Champ d'épaves : %d coques (%s)" % [fl.size(), ", ".join(parts)]


# --- Fin de bataille : champ, récupération, politique (prop. 21 à 23, 29 à 34) ----------------------

## Le vainqueur ne réétudie pas les marques si sa politique est de ferrailler (CombatSystem).
static func studies_marks(state: GameState, winner: int) -> bool:
	return not Capture.full(state) or studies(state, winner)


static func after_battle(state: GameState, sid: int, b: Dictionary, winner: int, report: Dictionary, added: Array[Dictionary]) -> void:
	if not Capture.full(state):
		return
	var lost: Array = []  # [empire, vaisseau]
	for s: Dictionary in b["sides"]:
		var ids: Array = (s.get("lost", {}) as Dictionary).keys()
		ids.sort()
		for ship in ids:
			for _k in int(s["lost"][ship]):
				lost.append([int(s["empire"]), String(ship)])
	if lost.is_empty():
		return
	var rec_list: Array = []
	var studied := {}
	var learned := PackedStringArray()
	var mats := 0
	var salvage := winner >= 0 and _has_salvage(state, sid, winner)
	for pair in lost:
		var owner := int(pair[0])
		var ship := String(pair[1])
		if Capture.data().get("no_wreck_hulls", []).has(Capture.hull_of(ship)):
			continue  # l'Onde-nef ne laisse rien (prop. 41)
		var enemy := winner >= 0 and owner != winner
		# Récupération (prop. 22) : le camp qui tient le champ remet en service, les siens compris.
		if winner >= 0 and not Capture.fixed_unit(ship) and not state.get_empire(winner).is_npc():
			var ch := Capture.size_rule(Combat.ship_size(ship), "recover")
			if salvage:
				ch *= _r("salvage_double", 2)
			if state.rng.randi_range(0, 99) < ch:
				var m := Capture.mask_of(ship)
				if owner == winner:
					m = Capture.roll_avaries(state, m, _r("own_avaries", 1), _r("own_avaries", 1))
				else:
					m = Capture.roll_avaries(state, m, _r("wreck_avaries_min", 2), _r("wreck_avaries_max", 4))
				rec_list.append({"s": Capture.prize_id(Capture.base_of(ship), m), "o": owner})
				continue
		_add_wreck(state, sid, owner, ship)
		if not enemy or state.get_empire(winner).is_npc():
			continue
		if scavenges(state, winner):
			@warning_ignore("integer_division")
			mats += maxi(1, int(Capture.base_cost(ship).get("materials", 0)) * _r("scavenge_pct", 10) / 100)
			Capture.note_stat(state, winner, "wrecks")
		var base := Capture.base_of(ship)
		if studies(state, winner) and not studied.has(base):
			studied[base] = true
			var t := study_ship(state, winner, ship, false)
			if t != "":
				learned.append(t)
	if winner < 0:
		return
	var we := state.get_empire(winner)
	if mats > 0:
		we.resources["materials"] = int(we.resources.get("materials", 0)) + mats
		Capture.note_stat(state, winner, "salvaged", mats)
	var sec := {"mats": mats, "learned": Array(learned), "recovered": []}
	for r: Dictionary in rec_list:
		(sec["recovered"] as Array).append(String(r["s"]))
		_offer_loot(state, winner, sid, String(r["s"]), int(r["o"]), added)
	report["capture_lore"] = sec
	if not we.is_ai() and not pending_loot(state, winner).is_empty() and not rec_list.is_empty():
		Announce.next(state, "battle_loot", {"actor": winner, "system": sid})
		added.append(state.add_chronicle("Après la bataille de %s, les équipes de %s fouillent le champ : %d coque(s) peuvent être remises en service. Voir le Butin de bataille." % [
				state.galaxy.systems[sid].system_name, we.short_name(), rec_list.size()], [winner]))


static func _has_salvage(state: GameState, sid: int, eid: int) -> bool:
	for f in Fleets.fleets_at(state, sid, eid):
		if Combat._fleet_has_flag(f, "salvage"):
			return true
	return false


# --- Butin de bataille (prop. 22, 44) ---------------------------------------------------------------

static func loot_of(state: GameState, eid: int) -> Dictionary:
	return Capture.sub(state, "loot").get_or_add(str(eid), {"list": [], "auto": false})


static func pending_loot(state: GameState, eid: int) -> Array:
	if not Capture.full(state):
		return []
	return loot_of(state, eid)["list"]


static func _offer_loot(state: GameState, eid: int, sid: int, ship: String, origin: int, added: Array[Dictionary]) -> void:
	var e := state.get_empire(eid)
	var entry := {"s": ship, "sid": sid, "until": state.tick + _r("loot_days", 30), "o": origin}
	if e.is_ai() or bool(loot_of(state, eid)["auto"]):
		_resolve_loot(state, eid, entry, _auto_choice(state, eid, ship), added)
		return
	(loot_of(state, eid)["list"] as Array).append(entry)


## Choix automatique : on garde ce qui est presque intact, sinon la politique d'épaves décide.
static func _auto_choice(state: GameState, eid: int, ship: String) -> String:
	if Capture.avarie_count(ship) <= 2 and check_keep(state, eid, ship) == "":
		return "keep"
	return "study" if studies(state, eid) else "scrap"


static func check_keep(state: GameState, eid: int, ship: String) -> String:
	if Combat.ship_size(ship) == "titan" and Capture.has_mega_prize(state, eid):
		return "vous tenez déjà une méga-coque prise"
	return ""


static func _resolve_loot(state: GameState, eid: int, entry: Dictionary, how: String, added: Array[Dictionary]) -> String:
	var e := state.get_empire(eid)
	var ship := String(entry["s"])
	var sid := int(entry["sid"])
	match how:
		"keep":
			var f := spawn_prize(state, eid, ship, sid)
			@warning_ignore("integer_division")
			f.hp[0] = maxi(1, Fleet.max_hp_of(ship) * _r("loot_hp_pct", 50) / 100)
			Capture.on_prize(state, eid, int(entry.get("o", -1)), ship, sid, added)
			return "remis en service"
		"scrap":
			var g := Capture.scrap_gain(state, eid, ship)
			for r in g:
				e.resources[r] = int(e.resources.get(r, 0)) + int(g[r])
			Capture.note_stat(state, eid, "scrapped")
			Research.count_stat(state, eid, "scrapped")
			return "démantelé (%s)" % GameData.format_amounts(g)
		"study":
			var t := study_ship(state, eid, ship, true)
			return "étudié" + ((" : %s" % t) if t != "" else "")
	return ""


## Une prise rejoint l'empire dans une flotte à elle (sans compter dans les vaisseaux construits).
static func spawn_prize(state: GameState, eid: int, ship: String, sid: int) -> Fleet:
	var f := Fleet.new()
	f.id = state.next_fleet_id
	state.next_fleet_id += 1
	f.owner = eid
	f.fleet_name = "Prise : %s" % String(GameData.ship(Capture.base_of(ship)).get("label", ship))
	f.add_ship(ship, -1, Research.mark_gen(state, eid))
	f.troops = 0
	f.system_id = sid
	state.fleets[f.id] = f
	return f


## Prises en service d'un empire (haut fait Flotte de prises).
static func prizes_in_service(state: GameState, eid: int) -> int:
	if not Capture.full(state):
		return 0
	var n := 0
	for f in Fleets.empire_fleets(state, eid):
		for s in f.ships:
			if Capture.is_prize(s):
				n += 1
	return n


# --- Diplomatie : rendre les prises (prop. 47) ------------------------------------------------------

## Prises que holder tient sur origin : modèles d'origin, ou classes de son peuple que holder ne bâtit pas.
static func prizes_from(state: GameState, holder: int, origin: int) -> Array:
	var out: Array = []
	if not Capture.full(state):
		return out
	var oe := state.get_empire(origin)
	var he := state.get_empire(holder)
	if oe == null or he == null:
		return out
	var theirs := FactionTraits.ship_ids_for(oe.faction_id)
	var mine := FactionTraits.ship_ids_for(he.faction_id)
	for f in Fleets.empire_fleets(state, holder):
		for i in f.ships.size():
			var s := f.ships[i]
			if not Capture.is_prize(s):
				continue
			var base := Capture.base_of(s)
			if Capture.origin_owner(s) == origin or (theirs.has(base) and not mine.has(base)):
				out.append([f.id, s])
	return out


## Clause de paix : les prises rentrent chez leur propriétaire (capitale), les héros prisonniers aussi.
static func return_prizes(state: GameState, holder: int, origin: int) -> int:
	var list := prizes_from(state, holder, origin)
	var oe := state.get_empire(origin)
	var dest := -1
	var cp = state.galaxy.get_planet(oe.capital_planet) if oe.capital_planet >= 0 else null
	if cp != null:
		dest = int(cp.system_id)
	for pair in list:
		var f: Fleet = state.fleets.get(int(pair[0]))
		if f == null:
			continue
		var i := f.ships.find(String(pair[1]))
		if i < 0:
			continue
		var sid := dest if dest >= 0 else f.system_id
		var ship := String(pair[1])
		if f.ships.size() == 1:
			state.fleets.erase(f.id)
		else:
			f.remove_at(i)
		spawn_prize(state, origin, ship, sid)
	WarLaws.release_one_way(state, holder, origin)
	if not list.is_empty():
		Diplomacy.remember(state, origin, holder, "prizes_returned")
	return list.size()


# --- Épaves à la dérive (prop. 26) -------------------------------------------------------------------

## Événement d'exploration : remettre en service (une prise avec avaries) ou démonter pour la technologie.
## Hors mode Complète, la remise en service donne le vaisseau tel quel et le démontage des points.
static func derelict(state: GameState, eid: int, ship: String, sid: int, keep: bool) -> void:
	if keep:
		if Capture.full(state):
			spawn_prize(state, eid, Capture.prize_id(ship, Capture.roll_avaries(state, 0, _r("wreck_avaries_min", 2), _r("wreck_avaries_max", 4))), sid)
		else:
			state.spawn_ship(eid, ship, sid)
		return
	var e := state.get_empire(eid)
	@warning_ignore("integer_division")
	e.resources["materials"] = int(e.resources.get("materials", 0)) + maxi(1, int(GameData.ship(ship).get("cost", {}).get("materials", 0)) * _r("scrap_pct", 30) / 100)
	if Capture.full(state):
		study_ship(state, eid, ship, true)
	elif Research.grant_find(state, eid, "capture") == "":  # trouvaille (prop. 10 de l'arbre)
		Events.give_research(state, eid, 15)


# --- Actions : butin, Vaisseau-tombe ----------------------------------------------------------------

static func check_act(state: GameState, player: int, act: String, d: Dictionary) -> String:
	match act:
		"loot":
			var x := String(d.get("x", ""))
			if x == "auto":
				return ""
			var list := pending_loot(state, player)
			var i := int(d.get("i", -1))
			if i < 0 or i >= list.size():
				return "ce butin n'existe plus"
			if not ["keep", "scrap", "study"].has(x):
				return "choix inconnu"
			if x == "keep":
				return check_keep(state, player, String(list[i]["s"]))
			return ""
		"tomb":
			return CaptureTomb.check(state, player, d)
	return "action inconnue : %s" % act


static func apply_act(state: GameState, player: int, act: String, d: Dictionary) -> Array[Dictionary]:
	var added: Array[Dictionary] = []
	match act:
		"loot":
			var x := String(d["x"])
			if x == "auto":
				loot_of(state, player)["auto"] = bool(d.get("on", true))
				return added
			var list: Array = loot_of(state, player)["list"]
			var entry: Dictionary = list[int(d["i"])]
			list.remove_at(int(d["i"]))
			var what := _resolve_loot(state, player, entry, x, added)
			added.append(state.add_chronicle("Butin de %s : %s %s." % [state.galaxy.systems[int(entry["sid"])].system_name,
					String(GameData.ship(Capture.base_of(String(entry["s"]))).get("label", entry["s"])), what], [player]))
		"tomb":
			added.append_array(CaptureTomb.apply(state, player, d))
	return added


# --- Rétro-ingénierie (prop. 29 à 34, 41) ----------------------------------------------------------

## Technologies d'un vaisseau : coque et modules (modèle) ou modèle d'origine (classe).
static func ship_techs(ship: String) -> Array:
	var base := Capture.base_of(ship)
	var sd := GameData.ship(base)
	var out: Array = []
	for t in sd.get("requires_tech", []):
		if not out.has(t):
			out.append(t)
	var o := Designs.origin(base)
	if not o.is_empty():
		for t in Designs.required_techs(String(o.get("hull", "")), o.get("modules", [])):
			if not out.has(t):
				out.append(t)
	var h := Designs.hull(Capture.hull_of(ship))
	for t in h.get("requires_tech", []):
		if not out.has(t):
			out.append(t)
	return out


@warning_ignore("integer_division")
static func study_pct(state: GameState, eid: int, intact: bool) -> int:
	var pct := _r("scrap_study_pct", 25) if intact else _r("study_pct", 10)
	var bonus := 100 + Research.fx_int(state, eid, "study_pct")
	if Capture.layer(state, eid, "remote_study"):
		bonus += _r("study_bonus_energetic_pct", 50)  # les Murmurants lisent les épaves à distance (prop. 41)
	var e := state.get_empire(eid)
	return maxi(1, pct * bonus / 100 * Research.wreck_mult(e.faction()) / 100)


## Ce que l'empire peut apprendre de ce vaisseau : chaque technologie inconnue de ses modules, ou son
## prérequis manquant (prop. 29).
static func study_targets(state: GameState, eid: int, ship: String) -> Array[String]:
	var e := state.get_empire(eid)
	var out: Array[String] = []
	for t in ship_techs(ship):
		var tid := String(t)
		if Research.knows(state, eid, tid) or not Research.is_visible(e.faction(), tid):
			continue
		var pick := _first_open(state, eid, e.faction(), tid, 8)
		if pick != "" and not out.has(pick):
			out.append(pick)
	return out


## Remonte les prérequis jusqu'à une technologie dont tous les prérequis sont connus.
static func _first_open(state: GameState, eid: int, faction: Dictionary, tid: String, depth: int) -> String:
	if depth <= 0:
		return ""
	for p in Research.tech(tid).get("pre", []):
		if not Research.knows(state, eid, String(p)) and Research.is_visible(faction, String(p)):
			return _first_open(state, eid, faction, String(p), depth - 1)
	return tid


## Étudie un vaisseau (épave, prise démantelée ou étudiée). Renvoie ce qui a été appris, ou "".
@warning_ignore("integer_division")
static func study_ship(state: GameState, eid: int, ship: String, intact: bool) -> String:
	if not Capture.full(state):
		return ""
	var e := state.get_empire(eid)
	if e == null or e.is_npc():
		return ""
	var base := Capture.base_of(ship)
	var parts := PackedStringArray()
	if base.begins_with("bete_"):
		return _carcass(state, eid)
	var targets := study_targets(state, eid, ship)
	if intact:
		targets = targets.slice(0, _r("scrap_study_max", 3))
	var pct := study_pct(state, eid, intact)
	for tid in targets:
		var n := maxi(1, Research.cost(state, eid, tid) * pct / 100)
		var done := Research.add_progress(state, eid, tid, n)
		parts.append(String(Research.tech(tid).get("label", tid)) + (" (découverte)" if done else ""))
	if targets.is_empty() and not Capture.fixed_unit(ship):
		parts.append(Events.give_research(state, eid, _r("nothing_research_pct", 3)))  # prop. 30
	Capture.note_stat(state, eid, "studied")
	_analyse(state, eid, base, _r("analysis_pct", 5))
	_study_hull(state, eid, ship)
	if base.begins_with("ancien_") or Designs.hull(Capture.hull_of(ship)).has("gabarit"):
		if state.rng.randi_range(0, 99) < 25:
			var anc := ArchaeoWorld.grant_random_ancient(state, eid, [])
			if anc != "":
				parts.append(anc)  # pont avec les Strates (prop. 33)
	return ", ".join(parts)


## Carcasses de créatures (prop. 34) : de quoi pousser la recherche ; la ruche les greffe (matériaux).
static func _carcass(state: GameState, eid: int) -> String:
	var t := Events.give_research(state, eid, _r("carcass_pct", 10))
	if Capture.layer(state, eid, "living"):
		var e := state.get_empire(eid)
		e.resources["materials"] = int(e.resources.get("materials", 0)) + 20
		t += ", greffes (+20 matériaux)"
	return t


# --- Analyse d'un modèle ennemi (prop. 31, 35) -------------------------------------------------------

static func analysis(state: GameState, eid: int, design: String) -> int:
	if not Capture.full(state):
		return 0
	return int(Capture.sub(state, "ana").get(str(eid), {}).get(design, 0))


static func _analyse(state: GameState, eid: int, design: String, n: int) -> void:
	if Capture.fixed_unit(design):
		return
	var a: Dictionary = Capture.sub(state, "ana").get_or_add(str(eid), {})
	a[design] = mini(_r("analysis_max", 15), int(a.get(design, 0)) + n)


## Dégâts d'un tir contre un modèle analysé (une nouvelle version du modèle a un autre identifiant :
## l'analyse repart de zéro).
@warning_ignore("integer_division")
static func analysis_shot(state: GameState, shooter: int, target: String, dmg: int) -> int:
	if state.capture.is_empty():
		return dmg
	var a := analysis(state, shooter, Capture.base_of(target))
	return dmg if a <= 0 else dmg * (100 + a) / 100


static func analyses_of(state: GameState, eid: int) -> Dictionary:
	if not Capture.full(state):
		return {}
	return Capture.sub(state, "ana").get(str(eid), {})


static func spy_check(state: GameState, _a: int, b: int, _op_id: String) -> String:
	if not Capture.full(state):
		return "les prises de guerre complètes ne sont pas en jeu dans cette partie"
	if _top_design(state, b) == "":
		return "aucun vaisseau de guerre à copier"
	return ""


static func spy_apply(state: GameState, a: int, b: int, _o: Dictionary) -> String:
	var d := _top_design(state, b)
	_analyse(state, a, d, _r("analysis_spy_pct", 10))
	return "les plans de %s : analyse %d %%." % [String(GameData.ship(d).get("label", d)), analysis(state, a, d)]


static func _top_design(state: GameState, eid: int) -> String:
	var count := {}
	for f in Fleets.empire_fleets(state, eid):
		for s in f.ships:
			var base := Capture.base_of(s)
			if bool(GameData.ship(base).get("military", false)) and not Capture.fixed_unit(base):
				count[base] = int(count.get(base, 0)) + 1
	var best := ""
	var keys := count.keys()
	keys.sort()
	for k in keys:
		if best == "" or int(count[k]) > int(count[best]):
			best = String(k)
	return best


# --- Coques de peuple étrangères (prop. 32) ---------------------------------------------------------

static func _study_hull(state: GameState, eid: int, ship: String) -> void:
	var hid := Capture.hull_of(ship)
	var h := Designs.hull(hid)
	if h.is_empty() or not bool(h.get("people", false)) or String(h.get("size", "")) == "titan" or h.has("echelon"):
		return
	if Designs.hull_ids_of(state, eid).has(hid) or has_copy(state, eid, hid):
		return
	var st: Dictionary = Capture.sub(state, "studies").get_or_add(str(eid), {})
	st[hid] = int(st.get(hid, 0)) + 1
	if int(st[hid]) >= _r("copy_studies", 3):
		(Capture.sub(state, "copies").get_or_add(str(eid), {}) as Dictionary)[hid] = 1
		var e := state.get_empire(eid)
		if not e.is_ai():
			state.add_chronicle("Les ingénieurs de %s ont assez démonté de %s pour en bâtir une copie. Elle n'aura jamais l'âme de l'original, mais elle flotte." % [
					e.short_name(), String(h.get("label", hid)).to_lower()], [eid])


static func has_copy(state: GameState, eid: int, hid: String) -> bool:
	if state.capture.is_empty():
		return false
	return (Capture.sub(state, "copies").get(str(eid), {}) as Dictionary).has(hid)


static func copies_of(state: GameState, eid: int) -> Array[String]:
	var out: Array[String] = []
	if not Capture.full(state):
		return out
	var keys := (Capture.sub(state, "copies").get(str(eid), {}) as Dictionary).keys()
	keys.sort()
	for k in keys:
		out.append(String(k) + COPY)
	return out


static func study_count(state: GameState, eid: int, hid: String) -> int:
	if not Capture.full(state):
		return 0
	return int(Capture.sub(state, "studies").get(str(eid), {}).get(hid, 0))


## Coque copiée : celle du peuple d'origine, module intégré à moitié d'effet, coût +30 %, structure 80 %.
@warning_ignore("integer_division")
static func copy_hull(hid: String) -> Dictionary:
	var base := Designs.data().get("hulls", {}).get(hid.trim_suffix(COPY), {}) as Dictionary
	if base.is_empty():
		return {}
	var h := base.duplicate(true)
	h["label"] = "%s (copie)" % String(base.get("label", hid))
	h.erase("requires")
	h.erase("people")
	h["copy_of"] = hid.trim_suffix(COPY)
	h["variant_of"] = hid.trim_suffix(COPY)  # même silhouette que l'original
	h["half_integrated"] = h.get("integrated", [])
	h["integrated"] = []
	var cost: Dictionary = h.get("cost", {})
	for r in cost:
		cost[r] = int(cost[r]) * _r("copy_cost_pct", 130) / 100
	h["hp"] = maxi(1, int(h.get("hp", 1)) * _r("copy_hp_pct", 80) / 100)
	return h


# --- Le temps qui passe : butin expiré, récolte, pillards, effacement (prop. 21, 24, 25, 28) -------

static func daily(state: GameState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not Capture.full(state):
		return out
	_expire_loot(state, out)
	if state.tick % 30 == 15:
		_harvest(state, out)
	if state.tick % 360 == 180:
		_decay_fields(state)
	out.append_array(CaptureTomb.daily(state))
	return out


static func _expire_loot(state: GameState, out: Array[Dictionary]) -> void:
	var lt := Capture.sub(state, "loot")
	var keys := lt.keys()
	keys.sort()
	for k in keys:
		var eid := int(k)
		var list: Array = lt[k]["list"]
		var i := 0
		while i < list.size():
			if state.tick >= int(list[i]["until"]):
				var entry: Dictionary = list[i]
				list.remove_at(i)
				_resolve_loot(state, eid, entry, "study" if studies(state, eid) else "scrap", out)
			else:
				i += 1


## Récolte mensuelle : qui tient le système récolte (grue de récupération, ferrailleurs) ; un champ
## laissé sans garde se fait gratter par les pirates (prop. 24, 25, 28).
static func _harvest(state: GameState, out: Array[Dictionary]) -> void:
	var sids := {}
	for k in Capture.sub(state, "fields"):
		sids[int(k)] = true
	for sid in state.battle_wrecks:
		if graveyard(state, int(sid)):
			sids[int(sid)] = true
	var order := sids.keys()
	order.sort()
	for sid in order:
		var harvesters := _harvesters(state, sid)
		var owner := state.system_owner(sid)
		var fl: Array = Capture.sub(state, "fields").get(str(sid), [])
		if harvesters.is_empty():
			if owner >= 0 and not fl.is_empty() and not state.get_empire(owner).is_npc() and Fleets.fleets_at(state, sid, owner).is_empty():
				fl.pop_front()  # pillards d'épaves
			continue
		for eid in harvesters:
			_harvest_one(state, eid, sid, fl, out)
		if fl.is_empty():
			Capture.sub(state, "fields").erase(str(sid))


static func _harvesters(state: GameState, sid: int) -> Array[int]:
	var out: Array[int] = []
	for fid in state.sorted_fleet_ids():
		var f: Fleet = state.fleets[fid]
		if f.system_id != sid or f.is_moving() or out.has(f.owner) or state.get_empire(f.owner).is_npc():
			continue
		if Combat._fleet_has_flag(f, "salvage") or Capture.layer(state, f.owner, "scrappers"):
			out.append(f.owner)
	var owner := state.system_owner(sid)
	if out.has(owner):
		return [owner]  # qui tient le système récolte
	out.sort()
	return out


@warning_ignore("integer_division")
static func _harvest_one(state: GameState, eid: int, sid: int, fl: Array, out: Array[Dictionary]) -> void:
	var e := state.get_empire(eid)
	var mats := 0
	var taken := 0
	while taken < _r("salvage_per_month", 2) and not fl.is_empty():
		var w: Dictionary = fl.pop_front()
		mats += maxi(1, int(Capture.base_cost(String(w["s"])).get("materials", 0)) * _r("scavenge_pct", 10) / 100)
		Capture.note_stat(state, eid, "wrecks")
		if taken == 0 and int(w["o"]) != eid and studies(state, eid):
			study_ship(state, eid, String(w["s"]), false)
		taken += 1
	if graveyard(state, sid):
		mats += _r("graveyard_materials", 20)
		if state.rng.randi_range(0, 99) < _r("intact_chance", 2):
			var ship := _intact_wreck(state, eid)
			if ship != "":
				spawn_prize(state, eid, ship, sid)
				Capture.note_stat(state, eid, "intact")
				if not e.is_ai():
					out.append(state.add_chronicle("Au cimetière de %s, une coque presque intacte sort des carcasses : %s rejoint %s." % [
							state.galaxy.systems[sid].system_name, String(GameData.ship(Capture.base_of(ship)).get("label", ship)), e.short_name()], [eid]))
	if mats > 0:
		e.resources["materials"] = int(e.resources.get("materials", 0)) + mats
		Capture.note_stat(state, eid, "salvaged", mats)
		Capture.note_stat(state, eid, "harvests")


static func _intact_wreck(state: GameState, eid: int) -> String:
	var pool := ["fregate", "croiseur", "corvette"]
	var ok: Array = []
	for p in pool:
		if not GameData.ship(p).is_empty():
			ok.append(p)
	if ok.is_empty():
		return ""
	var base := String(ok[state.rng.randi_range(0, ok.size() - 1)])
	return Capture.prize_id(base, Capture.roll_avaries(state, 0, _r("wreck_avaries_min", 2), _r("wreck_avaries_max", 4)))


## Hors cimetière, un champ perd la moitié de ses coques chaque année (prop. 21).
@warning_ignore("integer_division")
static func _decay_fields(state: GameState) -> void:
	var fs := Capture.sub(state, "fields")
	for k in fs.keys():
		if graveyard(state, int(k)):
			continue
		var fl: Array = fs[k]
		var keep := fl.size() * (100 - _r("field_decay_pct", 50)) / 100
		while fl.size() > keep:
			fl.pop_front()
		if fl.is_empty():
			fs.erase(k)
