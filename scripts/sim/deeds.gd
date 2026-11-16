class_name Deeds
extends RefCounted
## Hauts faits galactiques (étude « Hauts faits galactiques », 2026-11-16 ; data/deeds.json).
## Un haut fait est une course à un seul gagnant (Endless Space 2, Humankind) : on n'y construit rien,
## on accomplit. Trois sortes principales : les Premières (« premier à… », ouvertes dès le début), les
## records d'ère (seuil chiffré, ouverts quand l'empire atteint l'ère, tirés au hasard en début de partie)
## et les hauts faits de couche (liés à un registre, un credo, un archétype ou un gouvernement), plus les
## infâmes (Infamie) et les secrets (cachés jusqu'à l'obtention). Le premier qui l'accomplit gagne de la
## Gloire (jamais perdue) et choisit une récompense parmi trois tirées ; égalité le même jour : les deux.
## Après lui, ceux qui l'accomplissent l'inscrivent dans leurs Annales avec 25 % de la Gloire.
## Ce qui est mesuré : DeedsEval. Ponts (grands moments, âges d'or, héros, Légende, Rayonnement,
## Amphictyonie, ombres, victoire des Annales) : DeedsBridges.
##
## État : state.deeds = {"mode", "pool": [hauts faits en jeu], "cnt": {"e": {mesure: n}}, "base":
##  {"e": {haut fait: base d'ouverture}}, "won": {haut fait: {"by": [empires], "day"}}, "late": {haut fait:
##  {"e": jour}}, "glory": {"e": n}, "titles": {titre: empire}, "inbox": {"e": [boîte]}, "next_id",
##  "trophies": {trophée: empire}, "streak": {"e": n}, "peace": {"e": jour}, "quiet": {"e": jour},
##  "warn": {"haut fait>e": quart}, "infamy": {"e": jour de fin}, "annals": [entrées], "golden": {...},
##  "falsified": {"haut fait>e": n}}.
## Une entrée de boîte : {"id", "deed", "ch": [récompenses], "tick", "until"}.

const SORTS := ["first", "record", "layer", "infamous", "secret"]


static func data() -> Dictionary:
	return GameData.deeds()


static func rules() -> Dictionary:
	return data()["rules"]


static func r_int(key: String) -> int:
	return int(rules().get(key, 0))


static func def(id: String) -> Dictionary:
	return (data()["deeds"] as Dictionary).get(id, {})


static func label(id: String) -> String:
	return String(def(id).get("label", id))


static func sort_of(id: String) -> String:
	return String(def(id).get("sort", "first"))


static func family(id: String) -> String:
	return String(def(id).get("family", "exploration"))


static func family_label(fam: String) -> String:
	return String((data()["families"] as Dictionary).get(fam, {}).get("label", fam))


static func family_color(fam: String) -> Color:
	return Color(String((data()["families"] as Dictionary).get(fam, {}).get("color", "#cccccc")))


static func title_label(t: String) -> String:
	return String((data()["titles"] as Dictionary).get(t, {}).get("label", t))


static func reward_def(rid: String) -> Dictionary:
	return (data()["rewards"] as Dictionary).get(rid, {})


static func trophy_def(tid: String) -> Dictionary:
	return (data()["trophies"] as Dictionary).get(tid, {})


static func is_trophy(id: String) -> bool:
	return (data()["trophies"] as Dictionary).has(id)


static var _ids: Array[String] = []


## Tout le catalogue, dans l'ordre du fichier.
static func all_ids() -> Array[String]:
	if _ids.is_empty():
		for k in data()["deeds"]:
			_ids.append(String(k))
	return _ids


static func mode_defs() -> Array:
	return data().get("modes", [])


static func default_mode() -> String:
	return String(data().get("default_mode", "aucun"))


# --- Réglage, sauvegarde -----------------------------------------------------------------------

static func mode(state: GameState) -> String:
	return String(state.deeds.get("mode", "aucun"))


static func enabled(state: GameState) -> bool:
	return not state.deeds.is_empty() and mode(state) != "aucun"


static func worth_saving(state: GameState) -> bool:
	return not state.deeds.is_empty()


static func setup(state: GameState, mode_id: String, golden := true) -> void:
	state.deeds = {}
	var ok := false
	for m: Dictionary in mode_defs():
		if String(m["id"]) == mode_id:
			ok = true
	if not ok or mode_id == "aucun":
		return
	state.deeds = {"mode": mode_id, "pool": [], "cnt": {}, "base": {}, "won": {}, "late": {}, "glory": {}, "titles": {},
			"inbox": {}, "next_id": 1, "trophies": {}, "streak": {}, "peace": {}, "quiet": {}, "warn": {}, "infamy": {},
			"annals": [], "golden": {"on": 1 if golden else 0, "last": {}, "e": {}}, "falsified": {}}
	_draw(state)


## Tirage (prop. 4) : toutes les Premières, quelques records par ère, couches, infâmes et secrets.
static func _draw(state: GameState) -> void:
	var pool: Array = []
	var by_era := {}
	for id in all_ids():
		var s := sort_of(id)
		if s == "record":
			if mode(state) != "tous":
				continue
			var era := int(def(id).get("era", 1))
			if not by_era.has(era):
				by_era[era] = []
			(by_era[era] as Array).append(id)
		elif s == "first" or mode(state) == "tous":
			pool.append(id)
	var eras := by_era.keys()
	eras.sort()
	for era in eras:
		var ids: Array = by_era[era]
		ids.sort_custom(func(a: Variant, b: Variant) -> bool:
			return absi(hash([state.seed_value, "haut_fait", a])) < absi(hash([state.seed_value, "haut_fait", b])))
		for i in mini(r_int("records_per_era"), ids.size()):
			pool.append(ids[i])
	state.deeds["pool"] = pool


static func to_dict(state: GameState) -> Dictionary:
	return Ancients._sorted(state.deeds)


static func from_dict(state: GameState, d: Dictionary) -> void:
	state.deeds = {}
	if d.is_empty():
		return
	state.deeds = GameData._to_ints(d.duplicate(true))


static func _m(state: GameState, key: String) -> Dictionary:
	if not state.deeds.has(key):
		state.deeds[key] = {}
	return state.deeds[key]


static func _me(state: GameState, key: String, eid: int) -> Dictionary:
	var m := _m(state, key)
	if not m.has(str(eid)):
		m[str(eid)] = {}
	return m[str(eid)]


static func in_pool(state: GameState, id: String) -> bool:
	return (state.deeds.get("pool", []) as Array).has(id)


static func pool(state: GameState) -> Array:
	return state.deeds.get("pool", [])


# --- Compteurs (DeedsEval.COUNTERS) -------------------------------------------------------------

static func count(state: GameState, eid: int, key: String) -> int:
	return int((state.deeds.get("cnt", {}) as Dictionary).get(str(eid), {}).get(key, 0))


## Un acte de l'empire : compteurs des hauts faits, premiers moments des Annales, Gloire des grands
## moments (prop. 14). Appelé par Heroes.act (tous les actes et statistiques) et par quelques ponts.
static func note(state: GameState, eid: int, key: String, n := 1) -> void:
	if not enabled(state) or n <= 0:
		return
	var e := state.get_empire(eid)
	if e == null or e.is_npc():
		return
	var cnt := _me(state, "cnt", eid)
	var first := int(cnt.get(key, 0)) == 0
	cnt[key] = int(cnt.get(key, 0)) + n
	DeedsBridges.on_note(state, eid, key, n, first)


# --- Lecture ------------------------------------------------------------------------------------

static func glory(state: GameState, eid: int) -> int:
	return int((state.deeds.get("glory", {}) as Dictionary).get(str(eid), 0))


static func add_glory(state: GameState, eid: int, n: int) -> void:
	if n == 0 or not enabled(state):
		return
	var g := _m(state, "glory")
	g[str(eid)] = maxi(0, int(g.get(str(eid), 0)) + n)


## Vainqueurs d'un haut fait ([] s'il est encore à prendre).
static func winners(state: GameState, id: String) -> Array:
	return (state.deeds.get("won", {}) as Dictionary).get(id, {}).get("by", [])


static func won_day(state: GameState, id: String) -> int:
	return int((state.deeds.get("won", {}) as Dictionary).get(id, {}).get("day", -1))


static func is_won(state: GameState, id: String) -> bool:
	return not winners(state, id).is_empty()


## Hauts faits tenus par un empire (gagnés en premier).
static func held_by(state: GameState, eid: int) -> Array[String]:
	var out: Array[String] = []
	for id in pool(state):
		if winners(state, id).has(eid):
			out.append(String(id))
	return out


static func title_holder(state: GameState, t: String) -> int:
	return int((state.deeds.get("titles", {}) as Dictionary).get(t, -1))


static func titles_of(state: GameState, eid: int) -> Array[String]:
	var out: Array[String] = []
	var t: Dictionary = state.deeds.get("titles", {})
	var keys := t.keys()
	keys.sort()
	for k in keys:
		if int(t[k]) == eid:
			out.append(String(k))
	return out


## Couche d'espèce d'un empire concernée par un haut fait de couche ? (prop. 19)
static func layer_match(state: GameState, eid: int, id: String) -> bool:
	var lay: Dictionary = def(id).get("layer", {})
	if lay.is_empty():
		return false
	for k in lay:
		if Events.layer_value(state, eid, String(k)) == String(lay[k]):
			return true
	return false


## Le haut fait est-il ouvert pour cet empire ? Premières, infâmes, secrets : dès le début ; records :
## à leur ère ; couche : dès le début pour la couche concernée, à l'ère III pour les autres.
static func is_open(state: GameState, eid: int, id: String) -> bool:
	match sort_of(id):
		"record":
			return Research.current_era(state, eid) >= int(def(id).get("era", 1))
		"layer":
			return layer_match(state, eid, id) or Research.current_era(state, eid) >= 3
	return true


## Haut fait visible par cet empire dans l'onglet : les secrets non obtenus restent « ??? ».
static func revealed(state: GameState, eid: int, id: String) -> bool:
	if sort_of(id) != "secret":
		return true
	return winners(state, id).has(eid) or (state.deeds.get("late", {}) as Dictionary).get(id, {}).has(str(eid))


## Avancement brut [valeur, seuil] (la base d'ouverture déjà retirée, falsifications comprises).
static func progress(state: GameState, eid: int, id: String) -> Array:
	var d := def(id)
	var k := String(d["k"])
	var v := DeedsEval.value(state, eid, k, d.get("x", null))
	if DeedsEval.is_counter(k):
		v -= int((state.deeds.get("base", {}) as Dictionary).get(str(eid), {}).get(id, 0))
	v -= int((state.deeds.get("falsified", {}) as Dictionary).get("%s>%d" % [id, eid], 0))
	return [maxi(0, v), int(d["n"])]


static func pct(state: GameState, eid: int, id: String) -> int:
	if not is_open(state, eid, id):
		return 0
	var p := progress(state, eid, id)
	@warning_ignore("integer_division")
	return mini(100, int(p[0]) * 100 / maxi(1, int(p[1])))


## Quart d'avancement (0 à 4) : ce que voient les rivaux (prop. 5, comme les merveilles).
static func quarter(state: GameState, eid: int, id: String) -> int:
	@warning_ignore("integer_division")
	return mini(4, pct(state, eid, id) / maxi(1, r_int("quarter")))


## Gloire que rapporterait ce haut fait à cet empire (affinité ×2, rattrapage compris).
static func glory_for(state: GameState, eid: int, id: String) -> int:
	var g: Dictionary = rules()["glory"]
	var n := 0
	match sort_of(id):
		"record":
			var eras: Array = g["record_era"]
			n = int(eras[clampi(int(def(id).get("era", 1)) - 1, 0, eras.size() - 1)])
		_:
			n = int(g.get(sort_of(id), 100))
	if DeedsBridges.affinity(state, eid, family(id)):
		n *= r_int("affinity_mult")
	@warning_ignore("integer_division")
	n = n * (100 + DeedsBridges.catchup_pct(state, eid)) / 100
	return n


# --- Chaque jour ------------------------------------------------------------------------------

static func daily(state: GameState) -> Array[Dictionary]:
	var added: Array[Dictionary] = []
	if not enabled(state):
		return added
	_expire_inbox(state, added)
	DeedsBridges.daily(state, added)
	if posmod(state.tick, r_int("check_days")) != r_int("offset"):
		return added
	_track(state)
	_open_new(state)
	_check(state, added)
	DeedsBridges.monthly(state, added)
	return added


## Paix continue et silence (prop. catalogue « Grande Paix », « Le long silence »).
static func _track(state: GameState) -> void:
	var peace := _m(state, "peace")
	for e in state.empires:
		if e.eliminated or e.is_npc():
			continue
		var met := DeedsEval._met_alive(state, e)
		var ok := met.size() >= 4
		for r in met:
			if Combat.at_war(state, e.id, r):
				ok = false
		if not ok:
			peace.erase(str(e.id))
		elif not peace.has(str(e.id)):
			peace[str(e.id)] = state.tick
		var quiet := _m(state, "quiet")
		if not e.wars.is_empty():
			quiet[str(e.id)] = state.tick
		elif not quiet.has(str(e.id)):
			quiet[str(e.id)] = state.tick


static func peace_days(state: GameState, eid: int) -> int:
	var p: Dictionary = state.deeds.get("peace", {})
	return state.tick - int(p[str(eid)]) if p.has(str(eid)) else 0


static func quiet_days(state: GameState, eid: int) -> int:
	var q: Dictionary = state.deeds.get("quiet", {})
	return state.tick - int(q.get(str(eid), 0))


## Une opération d'espionnage subie remet le silence à zéro.
static func on_spied(state: GameState, victim: int) -> void:
	if enabled(state):
		_m(state, "quiet")[str(victim)] = state.tick


## Les records et hauts faits de couche s'ouvrent : la base des compteurs est notée ce jour-là.
static func _open_new(state: GameState) -> void:
	for e in state.empires:
		if e.eliminated or e.is_npc():
			continue
		var base := _me(state, "base", e.id)
		for id in pool(state):
			if base.has(id) or not is_open(state, e.id, String(id)):
				continue
			var k := String(def(String(id))["k"])
			base[id] = DeedsEval.value(state, e.id, k) if DeedsEval.is_counter(k) and _counts_from_open(state, e.id, String(id)) else 0


## Les Premières, infâmes et secrets comptent depuis le début, comme les records d'ère I et les hauts
## faits de couche pour la couche concernée (ouverts dès le début) ; les autres depuis leur ouverture.
static func _counts_from_open(state: GameState, eid: int, id: String) -> bool:
	match sort_of(id):
		"record":
			return int(def(id).get("era", 1)) > 1
		"layer":
			return not layer_match(state, eid, id)
	return false


static func _check(state: GameState, added: Array[Dictionary]) -> void:
	for id in pool(state):
		var sid := String(id)
		var cands: Array[int] = []
		for e in state.empires:
			if e.eliminated or e.is_npc() or not (_m(state, "base") as Dictionary).get(str(e.id), {}).has(sid):
				continue
			if winners(state, sid).has(e.id) or (state.deeds.get("late", {}) as Dictionary).get(sid, {}).has(str(e.id)):
				continue
			var p := progress(state, e.id, sid)
			if int(p[0]) >= int(p[1]):
				cands.append(e.id)
		if cands.is_empty():
			continue
		if is_won(state, sid):
			for eid in cands:
				_late(state, sid, eid, added)
		else:
			_award(state, sid, cands, added)
	_warn(state, added)


## Le premier (ou les premiers, le même jour) : Gloire, titre, récompense, Annales.
static func _award(state: GameState, id: String, eids: Array[int], added: Array[Dictionary]) -> void:
	_m(state, "won")[id] = {"by": eids.duplicate(), "day": state.tick}
	var names: Array[String] = []
	for eid in eids:
		var e := state.get_empire(eid)
		names.append(e.display_name())
		var g := glory_for(state, eid, id)
		add_glory(state, eid, g)
		annal(state, eid, "deed", id, g)
		var t := String(def(id).get("title", ""))
		if t != "" and title_holder(state, t) < 0:
			_m(state, "titles")[t] = eid
			Rulers.give_cognomen(state, eid, "deed:" + t)  # le titre devient un surnom du souverain régnant
		if sort_of(id) == "infamous":
			_m(state, "infamy")[str(eid)] = state.tick + r_int("infamy_days")
		DeedsBridges.on_award(state, eid, id, added)
		_offer(state, eid, id, added)
	var who := " et ".join(names)
	var txt := "Haut fait : %s accomplit « %s » (%s). %s" % [who, label(id), String(def(id).get("text", "")).trim_suffix("."),
			String(def(id).get("flavor", ""))]
	if sort_of(id) == "infamous":
		txt += " Toute la galaxie s'en souviendra, et pas en bien."
	added.append(state.add_chronicle(txt))


## Après le premier : Annales et un quart de la Gloire, sans récompense (prop. 7).
static func _late(state: GameState, id: String, eid: int, added: Array[Dictionary]) -> void:
	var late := _m(state, "late")
	if not late.has(id):
		late[id] = {}
	late[id][str(eid)] = state.tick
	@warning_ignore("integer_division")
	var g := glory_for(state, eid, id) * r_int("late_pct") / 100
	add_glory(state, eid, g)
	annal(state, eid, "late", id, g)
	added.append(state.add_chronicle("%s accomplit à son tour « %s ». Moins de fanfares que pour le premier, mais les Annales en gardent la trace (+%d Gloire)." % [
			state.get_empire(eid).short_name(), label(id), g], Espionage.private_to(state, [eid])))


## Un rival connu passe 75 % d'un haut fait encore à prendre : alerte, une fois par quart (prop. 5).
static func _warn(state: GameState, added: Array[Dictionary]) -> void:
	var warn := _m(state, "warn")
	for id in pool(state):
		var sid := String(id)
		if is_won(state, sid) or sort_of(sid) == "secret":
			continue
		for e in state.empires:
			if e.eliminated or e.is_npc():
				continue
			var q := quarter(state, e.id, sid)
			var key := "%s>%d" % [sid, e.id]
			if q * r_int("quarter") < r_int("warn_pct") or int(warn.get(key, 0)) >= q:
				continue
			warn[key] = q
			var watchers: Array = []
			for o in state.empires:
				if o.id != e.id and not o.eliminated and not o.is_npc() and o.contacts.has(e.id):
					watchers.append(o.id)
			if watchers.is_empty():
				continue
			added.append(state.add_chronicle("%s approche du haut fait « %s » (trois quarts du chemin). Il est encore temps de le devancer." % [
					e.display_name(), label(sid)], Espionage.private_to(state, watchers)))


# --- Annales (prop. 22) -------------------------------------------------------------------------

## Inscrit une entrée dans les Annales : kind = "deed", "late", "moment", "golden", "first".
static func annal(state: GameState, eid: int, kind: String, id: String, g := 0) -> void:
	if not enabled(state):
		return
	var a: Array = state.deeds["annals"]
	a.append({"d": state.tick, "e": eid, "k": kind, "id": id, "g": g})
	while a.size() > 600:
		a.pop_front()


static func annals_of(state: GameState, eid: int) -> Array:
	var out: Array = []
	for x: Dictionary in state.deeds.get("annals", []):
		if int(x["e"]) == eid:
			out.append(x)
	return out


# --- Récompenses (prop. 10, 11) -----------------------------------------------------------------

## Récompenses possibles pour cet empire, dans l'ordre du catalogue.
static func reward_options(state: GameState, eid: int) -> Array[String]:
	var out: Array[String] = []
	for rid in data()["rewards"]:
		var r := reward_def(String(rid))
		match String(r["k"]):
			"trophy":
				if free_trophies(state).is_empty() or FactionTraits.capital_system(state, eid) < 0 or _capital_colony(state, eid) == null:
					continue
			"hero":
				if state.heroes.is_empty() and state.hero_meta.is_empty():
					continue
				if Heroes.ids_of(state, eid).size() >= Heroes.cap(state, eid):
					continue
			"ships":
				if FactionTraits.capital_system(state, eid) < 0:
					continue
		out.append(String(rid))
	return out


## Trois récompenses tirées pour ce haut fait (graine, empire, haut fait).
static func draw_rewards(state: GameState, eid: int, id: String) -> Array:
	var opts := reward_options(state, eid)
	opts.sort_custom(func(a: String, b: String) -> bool:
		return absi(hash([state.seed_value, "recompense", eid, id, a])) < absi(hash([state.seed_value, "recompense", eid, id, b])))
	return opts.slice(0, mini(r_int("choices"), opts.size()))


static func _offer(state: GameState, eid: int, id: String, added: Array[Dictionary]) -> void:
	var ch := draw_rewards(state, eid, id)
	if ch.is_empty():
		return
	var e := state.get_empire(eid)
	if e.ai_level != "":
		apply_reward(state, eid, AiDeeds.pick(state, eid, ch), id, added)
		return
	var item := {"id": int(state.deeds["next_id"]), "deed": id, "ch": ch, "tick": state.tick, "until": state.tick + r_int("answer_days")}
	state.deeds["next_id"] = int(state.deeds["next_id"]) + 1
	var box := _m(state, "inbox")
	if not box.has(str(eid)):
		box[str(eid)] = []
	(box[str(eid)] as Array).append(item)


static func inbox(state: GameState, eid: int) -> Array:
	return (state.deeds.get("inbox", {}) as Dictionary).get(str(eid), [])


static func find_item(state: GameState, eid: int, item_id: int) -> Dictionary:
	for it: Dictionary in inbox(state, eid):
		if int(it["id"]) == item_id:
			return it
	return {}


static func check_choose(state: GameState, eid: int, item_id: int, index: int) -> String:
	if not enabled(state):
		return "pas de hauts faits dans cette partie"
	var it := find_item(state, eid, item_id)
	if it.is_empty():
		return "récompense inconnue"
	if index < 0 or index >= (it["ch"] as Array).size():
		return "choix impossible"
	if not reward_options(state, eid).has(String(it["ch"][index])):
		return "cette récompense n'est plus disponible"
	return ""


static func choose(state: GameState, eid: int, item_id: int, index: int, added: Array[Dictionary]) -> void:
	var it := find_item(state, eid, item_id)
	if it.is_empty():
		return
	(inbox(state, eid) as Array).erase(it)
	apply_reward(state, eid, String(it["ch"][index]), String(it["deed"]), added)


## Sans réponse au bout de 30 jours : la première récompense encore possible (prop. 33).
static func _expire_inbox(state: GameState, added: Array[Dictionary]) -> void:
	var box: Dictionary = state.deeds.get("inbox", {})
	var keys := box.keys()
	keys.sort()
	for k in keys:
		var items: Array = box[k]
		var i := 0
		while i < items.size():
			var it: Dictionary = items[i]
			if state.tick < int(it["until"]):
				i += 1
				continue
			items.remove_at(i)
			var opts := reward_options(state, int(k))
			for rid in it["ch"]:
				if opts.has(String(rid)):
					apply_reward(state, int(k), String(rid), String(it["deed"]), added)
					break


static func _capital_colony(state: GameState, eid: int) -> Colony:
	var e := state.get_empire(eid)
	if e == null or e.capital_planet < 0:
		return null
	var c: Colony = state.colonies.get(e.capital_planet)
	return c if c != null and c.owner == eid and c.is_established() else null


## Trophées que personne ne tient encore (un exemplaire chacun dans la galaxie).
static func free_trophies(state: GameState) -> Array[String]:
	var out: Array[String] = []
	var held := trophies_held(state)
	for tid in data()["trophies"]:
		if not held.has(String(tid)):
			out.append(String(tid))
	return out


## Trophées posés : {trophée: planète}. Lu dans les colonies (ils changent de mains avec elles).
static func trophies_held(state: GameState) -> Dictionary:
	var out := {}
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		for b in c.buildings:
			if is_trophy(b):
				out[b] = pid
	return out


## Texte court d'une récompense pour cet empire.
static func reward_text(state: GameState, eid: int, rid: String) -> String:
	var r := reward_def(rid)
	match String(r["k"]):
		"res":
			var amounts := {}
			for res in r["res"]:
				amounts[res] = Events.era_scaled(state, eid, int(r["res"][res]))
			return GameData.format_amounts(amounts)
		"research":
			return "%d %% de la recherche en cours" % int(r["pct"])
		"trophy":
			var free := free_trophies(state)
			if free.is_empty():
				return "plus aucun Trophée libre"
			var tid := _trophy_for(state, eid, free)
			return "%s : %s" % [String(trophy_def(tid)["label"]), String(trophy_def(tid).get("text", ""))]
		"ships":
			return "%d %s à la capitale" % [int(r["n"]), String(GameData.ship(_honor_ship(state, eid)).get("plural", "vaisseaux")).to_lower()]
		"hero":
			return "un héros qui rejoint l'empire, déjà expérimenté"
	return ""


static func _trophy_for(state: GameState, eid: int, free: Array[String]) -> String:
	var best := free[0]
	var best_h := absi(hash([state.seed_value, "trophee", eid, best]))
	for t in free:
		var h := absi(hash([state.seed_value, "trophee", eid, t]))
		if h < best_h:
			best = t
			best_h = h
	return best


static func _honor_ship(state: GameState, eid: int) -> String:
	var e := state.get_empire(eid)
	return "croiseur" if e != null and e.techs.has("coques_lourdes") else "fregate"


static func apply_reward(state: GameState, eid: int, rid: String, deed_id: String, added: Array[Dictionary]) -> void:
	var r := reward_def(rid)
	var e := state.get_empire(eid)
	var txt := reward_text(state, eid, rid)
	match String(r["k"]):
		"res":
			for res in r["res"]:
				e.resources[res] = int(e.resources.get(res, 0)) + Events.era_scaled(state, eid, int(r["res"][res]))
		"research":
			txt = Events.give_research(state, eid, int(r["pct"]))
		"trophy":
			var free := free_trophies(state)
			var c := _capital_colony(state, eid)
			if free.is_empty() or c == null:
				return
			var tid := _trophy_for(state, eid, free)
			c.buildings.append(tid)
			txt = String(trophy_def(tid)["label"])
		"ships":
			var sid := FactionTraits.capital_system(state, eid)
			if sid < 0:
				return
			for i in int(r["n"]):
				state.spawn_ship(eid, _honor_ship(state, eid), sid)
		"hero":
			var cls: String = Heroes.CLASSES[absi(hash([state.seed_value, "heros_haut_fait", eid, deed_id])) % Heroes.CLASSES.size()]
			var hid := Heroes.recruit(state, eid, Heroes.make_candidate(state, eid, cls, ["haut_fait", eid, deed_id]))
			if state.heroes.has(hid):
				Heroes.gain_xp(state, state.heroes[hid], int(r.get("xp", 0)))
				txt = String(state.heroes[hid].get("name", "un héros"))
	added.append(state.add_chronicle("%s choisit sa récompense pour « %s » : %s." % [e.short_name(), label(deed_id), txt],
			Espionage.private_to(state, [eid])))
