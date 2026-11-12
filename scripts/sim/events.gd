class_name Events
extends RefCounted
## Événements (étude « Événements, quêtes et reliques », 2026-11-12, propositions 3 à 7 et 17) : un
## paquet de cartes à la Old World. Chaque carte a un déclencheur (bilan mensuel, curiosité sondée,
## premier contact), des sujets tirés dans l'état (système, rival, héros), des conditions, un poids et
## un à trois choix aux effets chiffrés. Les cartes s'enchaînent par des marques posées par l'une et
## lues par les autres, jamais par une arborescence. Certains choix sont réservés à une couche
## d'espèce (registre, archétype, gouvernement, credo), donc valables pour les peuples créés. Une
## carte tirée attend dans la boîte de l'empire ; sans réponse au bout de answer_days, son choix par
## défaut s'applique (la partie ne s'arrête jamais en réseau). Règles et cartes : data/events.json.
## Tirages par hachage de la graine, aucun appel à state.rng.
##
## state.ev_meta[empire] = {"next": premier jour possible du prochain tirage mensuel, "seen": {carte:
##   jour}, "marks": {marque: jour où elle a été posée}, "inbox": [{"id", "card", "tick", "until",
##   "system", "planet", "rival", "hero"}], "log": [{"card", "title", "choice", "label", "tick"}]}.

const LAYERS := ["registre", "archetype", "gouvernement", "credo"]

static var _cards: Dictionary = {}


static func data() -> Dictionary:
	return GameData.events()


static func frequencies() -> Array:
	return data()["frequencies"]


static func freq_def(id: String) -> Dictionary:
	for d: Dictionary in frequencies():
		if String(d["id"]) == id:
			return d
	return {}


static func default_frequency() -> String:
	return String(data().get("default_frequency", "normaux"))


static func enabled(state: GameState) -> bool:
	return int(freq_def(state.event_freq).get("pct", 0)) > 0


static func card(id: String) -> Dictionary:
	if _cards.is_empty():
		for c: Dictionary in data()["cards"]:
			_cards[String(c["id"])] = c
	return _cards.get(id, {})


static func card_ids(trigger: String) -> Array[String]:
	var out: Array[String] = []
	for c: Dictionary in data()["cards"]:
		if String(c.get("trigger", "monthly")) == trigger:
			out.append(String(c["id"]))
	return out


static func _h(state: GameState, parts: Array) -> int:
	return absi(hash([state.seed_value, "evenement"] + parts))


static func meta(state: GameState, empire_id: int) -> Dictionary:
	if not state.ev_meta.has(empire_id):
		state.ev_meta[empire_id] = {"next": int(data().get("first_day", 180)), "seen": {}, "marks": {}, "inbox": [], "log": []}
	return state.ev_meta[empire_id]


## Montant multiplié par l'ère de l'empire (les récompenses suivent l'avancement de la partie).
static func era_scaled(state: GameState, empire_id: int, n: int) -> int:
	var pcts: Array = data()["era_pct"]
	var era := clampi(Research.current_era(state, empire_id), 1, pcts.size())
	@warning_ignore("integer_division")
	return n * int(pcts[era - 1]) / 100


## Pousse la recherche en cours de pct % de son coût (sinon du Savoir en réserve). Renvoie le texte.
static func give_research(state: GameState, empire_id: int, pct: int) -> String:
	var e := state.get_empire(empire_id)
	if not e.research_queue.is_empty():
		var tid := e.research_queue[0]
		@warning_ignore("integer_division")
		var n := maxi(1, Research.cost(state, empire_id, tid) * pct / 100)
		Research.add_progress(state, empire_id, tid, n)
		return "+%d Savoir pour %s" % [n, String(Research.tech(tid).get("label", tid))]
	var n2 := era_scaled(state, empire_id, pct * 3)
	e.resources["knowledge"] = int(e.resources.get("knowledge", 0)) + n2
	return "+%d Savoir" % n2


# --- Marques ----------------------------------------------------------------------------------------

static func has_mark(state: GameState, empire_id: int, m: String) -> bool:
	return (meta(state, empire_id)["marks"] as Dictionary).has(m)


static func mark_age(state: GameState, empire_id: int, m: String) -> int:
	var marks: Dictionary = meta(state, empire_id)["marks"]
	return state.tick - int(marks[m]) if marks.has(m) else -1


# --- Chaque jour ------------------------------------------------------------------------------------

static func daily(state: GameState, added: Array[Dictionary]) -> void:
	if state.ev_meta.is_empty() and not enabled(state):
		return
	# Réponses en retard : le choix par défaut s'applique.
	var ids := state.ev_meta.keys()
	ids.sort()
	for eid in ids:
		var inbox: Array = state.ev_meta[eid]["inbox"]
		var i := 0
		while i < inbox.size():
			var item: Dictionary = inbox[i]
			if state.tick >= int(item["until"]):
				_auto_answer(state, int(eid), item, added)
				if i < inbox.size() and inbox[i] == item:
					inbox.remove_at(i)
				continue
			i += 1
	if not enabled(state):
		return
	var month := int(GameData.rules()["month_days"])
	var fd := freq_def(state.event_freq)
	for e in state.empires:
		if e.eliminated or posmod(state.tick + e.id * 7, month) != 0:
			continue
		var m := meta(state, e.id)
		if state.tick < int(m["next"]) or not (m["inbox"] as Array).is_empty():
			continue
		if _h(state, ["roll", e.id, state.tick]) % 100 >= int(fd["pct"]):
			continue
		if draw(state, e.id, "monthly", {}, added) != "":
			m["next"] = state.tick + int(fd["cooldown"])


static func _auto_answer(state: GameState, empire_id: int, item: Dictionary, added: Array[Dictionary]) -> void:
	var c := card(String(item["card"]))
	var opts := choices(state, empire_id, item)
	var pick := -1
	var def := int(c.get("default", 0))
	if def < opts.size() and bool(opts[def]["ok"]):
		pick = def
	else:
		for o: Dictionary in opts:
			if bool(o["ok"]):
				pick = int(o["index"])
				break
	if pick >= 0:
		choose(state, empire_id, int(item["id"]), pick, added)
	else:
		_close(state, empire_id, item, -1, "sans réponse")


# --- Tirage ---------------------------------------------------------------------------------------

## Tire une carte valide pour ce déclencheur, la met dans la boîte. Renvoie son identifiant ("" sinon).
static func draw(state: GameState, empire_id: int, trigger: String, given: Dictionary, added: Array[Dictionary]) -> String:
	var m := meta(state, empire_id)
	var pool: Array = []
	var total := 0
	for id in card_ids(trigger):
		var c := card(id)
		if (m["seen"] as Dictionary).has(id) and not bool(c.get("repeat", false)):
			continue
		var subj := pick_subjects(state, empire_id, c, given)
		if subj.is_empty() or not conditions_ok(state, empire_id, c.get("if", {}), subj):
			continue
		var w := int(c.get("weight", 10))
		pool.append([id, w, subj])
		total += w
	if total <= 0:
		return ""
	var roll := _h(state, ["draw", empire_id, state.tick, trigger]) % total
	for entry in pool:
		roll -= int(entry[1])
		if roll < 0:
			push(state, empire_id, String(entry[0]), entry[2], added)
			return String(entry[0])
	return ""


## Met une carte dans la boîte de l'empire, avec ses sujets.
static func push(state: GameState, empire_id: int, card_id: String, subj: Dictionary, _added: Array[Dictionary]) -> void:
	var m := meta(state, empire_id)
	(m["seen"] as Dictionary)[card_id] = state.tick
	var item := {"id": state.next_event_id, "card": card_id, "tick": state.tick,
			"until": state.tick + int(data().get("answer_days", 30)),
			"system": int(subj.get("system", -1)), "planet": int(subj.get("planet", -1)),
			"rival": int(subj.get("rival", -1)), "hero": int(subj.get("hero", -1))}
	state.next_event_id += 1
	(m["inbox"] as Array).append(item)


## Premier contact : chaque empire reçoit la carte de la paire de registres, et chacun garde d'office
## le souvenir du choc (proposition 7).
static func on_contact(state: GameState, a: Empire, b: Empire, added: Array[Dictionary]) -> void:
	if a.is_npc() or b.is_npc() or not enabled(state):
		return
	var ra := String(a.faction().get("registre", ""))
	var rb := String(b.faction().get("registre", ""))
	for p: Dictionary in data()["tones"]["pairs"]:
		var pa := String(p["a"])
		var pb := String(p["b"])
		if not ((ra == pa and rb == pb) or (ra == pb and rb == pa)):
			continue
		if String(p.get("memory", "")) != "":
			Diplomacy.remember(state, a.id, b.id, String(p["memory"]))
			Diplomacy.remember(state, b.id, a.id, String(p["memory"]))
		for pair in [[a, b], [b, a]]:
			var me: Empire = pair[0]
			if not (meta(state, me.id)["seen"] as Dictionary).has(String(p["card"])):
				push(state, me.id, String(p["card"]), {"rival": (pair[1] as Empire).id}, added)
		return


# --- Sujets et conditions ---------------------------------------------------------------------------

## Sujets d'une carte : ceux déjà donnés (curiosité, contact) puis ceux tirés selon "subjects".
## {} si un sujet manque (la carte n'est pas jouable maintenant).
static func pick_subjects(state: GameState, empire_id: int, c: Dictionary, given: Dictionary) -> Dictionary:
	var subj := given.duplicate()
	subj["ok"] = true
	var wanted: Dictionary = c.get("subjects", {})
	for key in ["system", "rival", "hero"]:
		if not wanted.has(key) or subj.has(key):
			continue
		var cands: Array[int] = []
		match key:
			"system":
				cands = _systems(state, empire_id, String(wanted[key]))
			"rival":
				cands = _rivals(state, empire_id, String(wanted[key]))
			"hero":
				cands = _heroes(state, empire_id, String(wanted[key]))
		if cands.is_empty():
			return {}
		subj[key] = cands[_h(state, ["subj", key, empire_id, state.tick, String(c["id"])]) % cands.size()]
	return subj


static func own_systems(state: GameState, empire_id: int) -> Array[int]:
	var seen := {}
	var out: Array[int] = []
	for pid in state.sorted_colony_ids():
		var col: Colony = state.colonies[pid]
		if col.owner != empire_id or not col.is_colony() or not col.is_established():
			continue
		var sid := state.galaxy.get_planet(pid).system_id
		if not seen.has(sid):
			seen[sid] = true
			out.append(sid)
	out.sort()
	return out


static func _systems(state: GameState, empire_id: int, mode: String) -> Array[int]:
	var own := own_systems(state, empire_id)
	var cap := FactionTraits.capital_system(state, empire_id)
	var out: Array[int] = []
	match mode:
		"capital":
			if cap >= 0:
				out.append(cap)
		"low_stab":
			if Stability.applies(state, empire_id):
				var worst := -1
				var wv := 50
				for sid in own:
					if sid != cap and Stability.value(state, sid) < wv:
						wv = Stability.value(state, sid)
						worst = sid
				if worst >= 0:
					out.append(worst)
		"rich":
			var best := -1
			var bp := -1
			for sid in own:
				var p := Stability.system_pop(state, sid, empire_id)
				if p > bp:
					bp = p
					best = sid
			if best >= 0:
				out.append(best)
		"frontier":
			if cap >= 0:
				var jumps := FactionTraits.jumps_from(state.galaxy, cap)
				var far := -1
				var fj := -1
				for sid in own:
					if sid != cap and int(jumps.get(sid, 0)) > fj:
						fj = int(jumps.get(sid, 0))
						far = sid
				if far >= 0:
					out.append(far)
				elif not own.is_empty():
					out.append(own[0])
		_:
			out = own
	return out


static func _rivals(state: GameState, empire_id: int, mode: String) -> Array[int]:
	var e := state.get_empire(empire_id)
	var out: Array[int] = []
	for o in e.contacts:
		var oe := state.get_empire(o)
		if oe == null or oe.eliminated or oe.is_npc():
			continue
		var at_war := e.wars.has(o)
		if (mode == "war" and not at_war) or (mode == "peace" and at_war):
			continue
		out.append(o)
	return out


static func _heroes(state: GameState, empire_id: int, mode: String) -> Array[int]:
	var out: Array[int] = []
	for id in Heroes.ids_of(state, empire_id):
		var h: Dictionary = state.heroes[id]
		if not Heroes.active(state, h) or Heroes.is_prisoner(h):
			continue
		if mode != "any" and String(h["cls"]) != mode:
			continue
		out.append(id)
	return out


static func layer_value(state: GameState, empire_id: int, layer: String) -> String:
	var f := state.get_empire(empire_id).faction()
	if layer == "registre":
		return String(f.get("registre", ""))
	return String(f.get("species", {}).get(layer, ""))


static func _layers_ok(state: GameState, empire_id: int, want: Dictionary) -> bool:
	for layer in want:
		if not (want[layer] as Array).has(layer_value(state, empire_id, String(layer))):
			return false
	return true


static func conditions_ok(state: GameState, empire_id: int, cond: Dictionary, subj: Dictionary) -> bool:
	var e := state.get_empire(empire_id)
	@warning_ignore("integer_division")
	var year := state.tick / GameCalendar.DAYS_PER_YEAR
	for k in cond:
		var v: Variant = cond[k]
		match String(k):
			"layers":
				if not _layers_ok(state, empire_id, v):
					return false
			"not_layers":
				for layer in v:
					if (v[layer] as Array).has(layer_value(state, empire_id, String(layer))):
						return false
			"min_year":
				if year < int(v):
					return false
			"max_year":
				if year > int(v):
					return false
			"war":
				if bool(v) != (not e.wars.is_empty()):
					return false
			"stability":
				if bool(v) != Stability.applies(state, empire_id):
					return false
			"stab_below", "stab_above":
				var sid := int(subj.get("system", -1))
				if sid < 0 or not Stability.applies(state, empire_id):
					return false
				var sv := Stability.value(state, sid)
				if (k == "stab_below" and sv >= int(v)) or (k == "stab_above" and sv <= int(v)):
					return false
			"min_colonies":
				if own_systems(state, empire_id).size() < int(v):
					return false
			"marks":
				for m in v:
					if not has_mark(state, empire_id, String(m)) or mark_age(state, empire_id, String(m)) < int(cond.get("mark_days", 0)):
						return false
			"no_marks":
				for m in v:
					if has_mark(state, empire_id, String(m)):
						return false
			"stock_below":
				for r in v:
					if int(e.resources.get(r, 0)) >= int(v[r]):
						return false
			"stock_above":
				for r in v:
					if int(e.resources.get(r, 0)) <= int(v[r]):
						return false
			"lairs_known":
				if bool(v) == Pirates.known_lairs(state, empire_id).is_empty():
					return false
			"ports_known":
				if bool(v) == Pirates.known_ports(state, empire_id).is_empty():
					return false
			"recent_battle":
				if not _recent_battle(state, empire_id, String(v)):
					return false
			"researching":
				if bool(v) == e.research_queue.is_empty():
					return false
	return true


static func _recent_battle(state: GameState, empire_id: int, how: String) -> bool:
	for r in state.battle_reports:
		if state.tick - int(r.get("end", -9999)) > 180:
			continue
		var took_part := false
		for s: Dictionary in r.get("sides", []):
			if int(s["empire"]) == empire_id:
				took_part = true
		if not took_part:
			continue
		var w := int(r.get("winner", -1))
		if (how == "won" and w == empire_id) or (how == "lost" and w >= 0 and w != empire_id):
			return true
	return false


# --- Choix -----------------------------------------------------------------------------------------

static func find_item(state: GameState, empire_id: int, event_id: int) -> Dictionary:
	if not state.ev_meta.has(empire_id):
		return {}
	for item: Dictionary in state.ev_meta[empire_id]["inbox"]:
		if int(item["id"]) == event_id:
			return item
	return {}


static func inbox(state: GameState, empire_id: int) -> Array:
	return state.ev_meta[empire_id]["inbox"] if state.ev_meta.has(empire_id) else []


## Les choix d'une carte pour cet empire : [{"index", "label", "tag", "ok", "why", "lines", "risky"}].
## Un choix réservé à une autre couche d'espèce n'apparaît pas.
static func choices(state: GameState, empire_id: int, item: Dictionary) -> Array:
	var c := card(String(item["card"]))
	var out := []
	var opts: Array = c.get("choices", [])
	for i in opts.size():
		var ch: Dictionary = opts[i]
		var cond: Dictionary = ch.get("if", {})
		if cond.has("layers") and not _layers_ok(state, empire_id, cond["layers"]):
			continue
		var tag := ""
		if cond.has("layers"):
			for layer in cond["layers"]:
				var lv := layer_value(state, empire_id, String(layer))
				tag = _layer_label(String(layer), lv)
		var why := _cost_problem(state, empire_id, item, ch)
		out.append({"index": i, "label": fill(state, empire_id, item, String(ch["label"])), "tag": tag, "ok": why == "", "why": why,
				"lines": fx_lines(state, empire_id, item, ch.get("fx", [])), "risky": ch.has("risky"),
				"pct": int((ch.get("risky", {}) as Dictionary).get("pct", 100)),
				"win": fx_lines(state, empire_id, item, (ch.get("risky", {}) as Dictionary).get("win", [])),
				"lose": fx_lines(state, empire_id, item, (ch.get("risky", {}) as Dictionary).get("lose", []))})
	return out


static func _layer_label(layer: String, value: String) -> String:
	for b: Dictionary in GameData.species_parts().get(layer, []):
		if String(b.get("id", b.get("name", ""))) == value:
			return String(b.get("label", b.get("name", value)))
	return value.capitalize()


## Ce qui empêche un choix : ressource qui manque, sujet disparu. "" si possible.
static func _cost_problem(state: GameState, empire_id: int, item: Dictionary, ch: Dictionary) -> String:
	var e := state.get_empire(empire_id)
	var need := {}
	for fx: Dictionary in ch.get("fx", []):
		if String(fx["k"]) == "res":
			for r in fx["res"]:
				var n := era_scaled(state, empire_id, int(fx["res"][r]))
				if n < 0:
					need[r] = int(need.get(r, 0)) - n
	for r in need:
		if int(e.resources.get(r, 0)) < int(need[r]):
			return "pas assez de %s" % GameData.resource_label(String(r)).to_lower()
	for fx: Dictionary in _all_fx(ch):
		match String(fx["k"]):
			"hero_xp", "hero_wound":
				if not state.heroes.has(int(item.get("hero", -1))):
					return "le héros n'est plus là"
			"opinion":
				var r := state.get_empire(int(item.get("rival", -1)))
				if r == null or r.eliminated:
					return "cet empire a disparu"
	return ""


static func _all_fx(ch: Dictionary) -> Array:
	var out: Array = (ch.get("fx", []) as Array).duplicate()
	var rk: Dictionary = ch.get("risky", {})
	out.append_array(rk.get("win", []))
	out.append_array(rk.get("lose", []))
	return out


static func check_choose(state: GameState, empire_id: int, event_id: int, index: int) -> String:
	var item := find_item(state, empire_id, event_id)
	if item.is_empty():
		return "événement inconnu"
	for o: Dictionary in choices(state, empire_id, item):
		if int(o["index"]) == index:
			return String(o["why"])
	return "choix impossible"


## Applique le choix index de l'événement event_id.
static func choose(state: GameState, empire_id: int, event_id: int, index: int, added: Array[Dictionary]) -> void:
	var item := find_item(state, empire_id, event_id)
	if item.is_empty():
		return
	var c := card(String(item["card"]))
	var ch: Dictionary = (c["choices"] as Array)[index]
	var result := ""
	apply_fx(state, empire_id, item, ch.get("fx", []), added)
	if ch.has("risky"):
		var rk: Dictionary = ch["risky"]
		var win := _h(state, ["risk", int(item["id"]), empire_id]) % 100 < int(rk["pct"])
		apply_fx(state, empire_id, item, rk["win"] if win else rk["lose"], added)
		result = "réussite" if win else "échec"
		var lines := fx_lines(state, empire_id, item, rk["win"] if win else rk["lose"])
		var e := state.get_empire(empire_id)
		added.append(state.add_chronicle("%s : « %s », %s. %s" % [e.short_name(), String(c["title"]),
				"le pari est gagné" if win else "le pari tourne mal", ", ".join(lines) + "." if not lines.is_empty() else ""],
				Espionage.private_to(state, [empire_id])))
	_close(state, empire_id, item, index, fill(state, empire_id, item, String(ch["label"])) + ((" (%s)" % result) if result != "" else ""))


static func _close(state: GameState, empire_id: int, item: Dictionary, index: int, label: String) -> void:
	var m := meta(state, empire_id)
	(m["inbox"] as Array).erase(item)
	var log: Array = m["log"]
	log.append({"card": String(item["card"]), "title": String(card(String(item["card"])).get("title", "")),
			"choice": index, "label": label, "tick": state.tick, "system": int(item.get("system", -1))})
	while log.size() > int(data().get("log_max", 30)):
		log.pop_front()


# --- Effets ----------------------------------------------------------------------------------------

static func _target_system(state: GameState, empire_id: int, item: Dictionary, scope: String) -> int:
	var sid := int(item.get("system", -1))
	if scope == "capital" or sid < 0 or state.system_owner(sid) != empire_id:
		return FactionTraits.capital_system(state, empire_id)
	return sid


static func _sys_name(state: GameState, sid: int) -> String:
	return state.galaxy.systems[sid].system_name if sid >= 0 else "?"


static func _duration_text(days: int) -> String:
	if days >= 360 and days % 360 == 0:
		@warning_ignore("integer_division")
		return "%d an%s" % [days / 360, "s" if days >= 720 else ""]
	@warning_ignore("integer_division")
	return "%d mois" % maxi(1, days / 30)


## Lignes lisibles des effets (proposition 4) ; les effets sans objet pour ce peuple sont omis.
static func fx_lines(state: GameState, empire_id: int, item: Dictionary, fxs: Array) -> Array[String]:
	var e := state.get_empire(empire_id)
	var f := e.faction()
	var out: Array[String] = []
	for fx: Dictionary in fxs:
		match String(fx["k"]):
			"res":
				var amounts := {}
				for r in fx["res"]:
					amounts[r] = era_scaled(state, empire_id, int(fx["res"][r]))
				out.append(GameData.format_amounts(amounts, true))
			"stab":
				if not Stability.applies(state, empire_id):
					continue
				var scope := String(fx.get("scope", "system"))
				var where := "dans tout l'empire" if scope == "empire" else "à %s" % _sys_name(state, _target_system(state, empire_id, item, scope))
				out.append("Stabilité %+d %s pendant %s" % [int(fx["v"]), where, _duration_text(int(fx["days"]))])
			"fervor":
				if FactionTraits.has_fervor(f):
					out.append("Ferveur %+d" % int(fx["v"]))
			"rep":
				if Reputation.has(f):
					out.append("Réputation %+d" % int(fx["v"]))
			"echoes":
				if Echoes.has(f):
					out.append("Échos %+d" % int(fx["v"]))
			"biomass":
				if f.has("biomass"):
					out.append("Biomasse %+d" % int(fx["v"]))
			"opinion":
				var md: Dictionary = Diplomacy.data()["memories"].get(String(fx["kind"]), {})
				out.append("%s : opinion %+d (%s)" % [_rival_name(state, item), int(md.get("value", 0)), String(md.get("label", "")).to_lower()])
			"mark", "unmark":
				pass
			"pop":
				out.append("Population %+d à %s" % [int(fx["v"]), _sys_name(state, _target_system(state, empire_id, item, "system"))])
			"ship":
				out.append("Un vaisseau : %s" % String(GameData.ship(String(fx["ship"])).get("label", fx["ship"])))
			"research":
				out.append("Recherche en cours : +%d %% de son coût" % int(fx["pct"]))
			"renown":
				if not state.hero_meta.is_empty():
					out.append("Renom %+d" % int(fx["v"]))
			"hero_xp":
				out.append("%s : %+d expérience" % [_hero_name(state, item), int(fx["v"])])
			"hero_wound":
				out.append("%s blessé" % _hero_name(state, item))
			"deposit":
				out.append("Gisement : %s" % String(GameData.deposit(String(fx["what"])).get("label", fx["what"])))
			"pirates":
				out.append("Des pirates surgissent")
	return out


static func _rival_name(state: GameState, item: Dictionary) -> String:
	var r := state.get_empire(int(item.get("rival", -1)))
	return r.display_name() if r != null else "?"


static func _hero_name(state: GameState, item: Dictionary) -> String:
	var h: Dictionary = state.heroes.get(int(item.get("hero", -1)), {})
	return String(h.get("name", "?"))


static func apply_fx(state: GameState, empire_id: int, item: Dictionary, fxs: Array, added: Array[Dictionary]) -> void:
	var e := state.get_empire(empire_id)
	var f := e.faction()
	var m := meta(state, empire_id)
	for fx: Dictionary in fxs:
		match String(fx["k"]):
			"res":
				for r in fx["res"]:
					e.resources[r] = maxi(0, int(e.resources.get(r, 0)) + era_scaled(state, empire_id, int(fx["res"][r])))
			"stab":
				if not Stability.applies(state, empire_id):
					continue
				var scope := String(fx.get("scope", "system"))
				var sids: Array = own_systems(state, empire_id) if scope == "empire" else [_target_system(state, empire_id, item, scope)]
				for sid in sids:
					if sid < 0:
						continue
					var en := Stability._entry_w(state, sid)
					en["ev"] = int(fx["v"])
					en["ev_end"] = state.tick + int(fx["days"])
					en["ev_card"] = String(item["card"])
			"fervor":
				if FactionTraits.has_fervor(f):
					e.fervor = clampi(e.fervor + int(fx["v"]), 0, int(f["fervor"].get("max", 100)))
			"rep":
				Reputation.add(state, empire_id, int(fx["v"]))
			"echoes":
				if Echoes.has(f):
					e.echoes = maxi(0, e.echoes + int(fx["v"]))
			"biomass":
				if f.has("biomass"):
					e.biomass = maxi(0, e.biomass + int(fx["v"]))
			"opinion":
				Diplomacy.remember(state, int(item.get("rival", -1)), empire_id, String(fx["kind"]))
			"mark":
				(m["marks"] as Dictionary)[String(fx["m"])] = state.tick
			"unmark":
				(m["marks"] as Dictionary).erase(String(fx["m"]))
			"pop":
				var col := _colony_in(state, empire_id, _target_system(state, empire_id, item, "system"))
				if col != null:
					col.population = maxi(1, col.population + int(fx["v"]))
			"ship":
				var sid := _target_system(state, empire_id, item, "system")
				if sid >= 0:
					state.spawn_ship(empire_id, String(fx["ship"]), sid)
			"research":
				give_research(state, empire_id, int(fx["pct"]))
			"renown":
				if not state.hero_meta.is_empty():
					var hm := Heroes.meta(state, empire_id)
					hm["renown"] = maxi(0, int(hm["renown"]) + int(fx["v"]))
			"hero_xp":
				var h: Dictionary = state.heroes.get(int(item.get("hero", -1)), {})
				if not h.is_empty():
					if int(fx["v"]) > 0:
						Heroes.gain_xp(state, h, int(fx["v"]))
					else:
						h["xp"] = maxi(0, int(h["xp"]) + int(fx["v"]))
			"hero_wound":
				var h2: Dictionary = state.heroes.get(int(item.get("hero", -1)), {})
				if not h2.is_empty() and Heroes.active(state, h2):
					Heroes._wound(state, h2, added, String(card(String(item["card"])).get("title", "")).to_lower())
			"deposit":
				var pid := int(item.get("planet", -1))
				var p := state.galaxy.get_planet(pid) if pid >= 0 else null
				var dep := String(fx["what"])
				if p != null and not p.deposits.has(dep):
					var deps: Array = Array(p.deposits)
					deps.append(dep)
					state.override_planet(pid, {"deposits": deps})
			"pirates":
				var sid2 := int(item.get("system", -1))
				if sid2 < 0:
					sid2 = _target_system(state, empire_id, item, "system")
				var lvl := int((state.curios.get(int(item.get("planet", -1)), {}) as Dictionary).get("lvl", 2))
				if sid2 >= 0:
					Curios.spawn_trap(state, sid2, lvl)


static func _colony_in(state: GameState, empire_id: int, sid: int) -> Colony:
	if sid < 0:
		return null
	var best: Colony = null
	for pid in state.galaxy.systems[sid].planet_ids:
		var c: Colony = state.colonies.get(pid)
		if c != null and c.owner == empire_id and c.is_colony() and c.is_established():
			if best == null or c.population > best.population:
				best = c
	return best


## Texte d'une carte avec ses sujets : {system}, {planet}, {rival}, {hero}, {empire}.
static func fill(state: GameState, empire_id: int, item: Dictionary, s: String) -> String:
	var sid := int(item.get("system", -1))
	var pid := int(item.get("planet", -1))
	var out := s.replace("{empire}", state.get_empire(empire_id).display_name())
	out = out.replace("{system}", _sys_name(state, sid if sid >= 0 else FactionTraits.capital_system(state, empire_id)))
	out = out.replace("{planet}", state.galaxy.get_planet(pid).display_name(state.galaxy) if pid >= 0 else "?")
	out = out.replace("{rival}", _rival_name(state, item))
	out = out.replace("{hero}", _hero_name(state, item))
	return out


# --- Sauvegarde ----------------------------------------------------------------------------------

static func meta_to_list(state: GameState) -> Array:
	var ids := state.ev_meta.keys()
	ids.sort()
	var out := []
	for eid in ids:
		var m: Dictionary = state.ev_meta[eid]
		out.append({"e": int(eid), "next": int(m["next"]), "seen": _pairs(m["seen"]), "marks": _pairs(m["marks"]),
				"inbox": (m["inbox"] as Array).duplicate(true), "log": (m["log"] as Array).duplicate(true)})
	return out


static func meta_from_list(state: GameState, list: Array) -> void:
	state.ev_meta.clear()
	for d: Dictionary in list:
		var inbox := []
		for it: Dictionary in d.get("inbox", []):
			var v: Dictionary = GameData._to_ints(it)
			v["card"] = String(v["card"])
			inbox.append(v)
		var log := []
		for it: Dictionary in d.get("log", []):
			var v2: Dictionary = GameData._to_ints(it)
			v2["card"] = String(v2["card"])
			v2["title"] = String(v2.get("title", ""))
			v2["label"] = String(v2.get("label", ""))
			log.append(v2)
		state.ev_meta[int(d["e"])] = {"next": int(d.get("next", 0)), "seen": _unpairs(d.get("seen", [])),
				"marks": _unpairs(d.get("marks", [])), "inbox": inbox, "log": log}


static func _pairs(d: Dictionary) -> Array:
	var ks := d.keys()
	ks.sort()
	var out := []
	for k in ks:
		out.append([String(k), int(d[k])])
	return out


static func _unpairs(a: Array) -> Dictionary:
	var out := {}
	for p in a:
		out[String(p[0])] = int(p[1])
	return out
