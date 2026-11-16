class_name Crisis
extends RefCounted
## Crises de fin de partie (étude « Crises de fin de partie », 2026-11-15 ; data/crises.json).
## Une puissance hostile à tous (GameState.CRISIS_ID), tirée dans un catalogue ouvert. La fin de partie
## commence à une date réglable ; ensuite, un tirage tous les deux ans à chance croissante (par hachage
## de la graine, jamais l'aléatoire du jeu). Une crise s'annonce en une à trois étapes (fenêtre
## d'événement + chronique), puis arrive avec une force calée sur les flottes du moment.
## Les systèmes qu'elle fait tomber (siège mené à terme) subissent son « sort » (corail, scellés,
## population bue) tant qu'une de ses flottes y reste. Ses points faibles sont des stations : les
## détruire la ralentit, détruire son cœur la vainc. Contribution de chaque empire, Front commun,
## récompenses partagées, relique au coup final ; si elle tient la moitié des systèmes, la galaxie a perdu.
##
## État : state.crisis = {} (aucune crise dans la partie) ou
## {"mode", "start", "str", "kinds": [autorisées], "pull", "pulled": {déclencheur: jour}, "roll",
##  "count", "done": [sortes passées], "gap", "cur": crise en cours ({} sinon), "past": [bilans],
##  "boons": {empire: [{"label", "fx", "until"}]}, "post": {"until", "stab"}}.
## cur = {"kind", "stage" ("notice" | "active"), "since", "steps": [jours], "step", "origin", "power",
##  "base_owned", "war": [flottes], "st": {flotte: {"role", "sid"}}, "held": {système: {...}},
##  "contrib": {empire: points}, "front": {empire: jour}, "aloof": {empire: jour}, "reinf", "fallen", "freed"}.

const ROLE_HEART := "heart"
const ROLE_STATION := "station"


static func data() -> Dictionary:
	return GameData.crises()


static func kind_def(kind: String) -> Dictionary:
	return (data().get("kinds", {}) as Dictionary).get(kind, {})


static func kind_ids() -> Array[String]:
	var out: Array[String] = []
	for k in data().get("kinds", {}):
		out.append(String(k))
	out.sort()
	return out


static func mode_defs() -> Array:
	return data().get("modes", [])


static func start_defs() -> Array:
	return data().get("starts", [])


static func strength_defs() -> Array:
	return data().get("strengths", [])


static func default_mode() -> String:
	return String(data().get("default_mode", "une"))


static func default_start() -> String:
	return String(data().get("default_start", "an30"))


static func default_strength() -> String:
	return String(data().get("default_strength", "normale"))


static func _find(list: Array, id: String) -> Dictionary:
	for d: Dictionary in list:
		if String(d["id"]) == id:
			return d
	return {}


static func _h(state: GameState, parts: Array) -> int:
	return absi(hash([state.seed_value, "crise"] + parts))


# --- Lecture ----------------------------------------------------------------------------------------

## Des crises sont-elles prévues dans cette partie ?
static func enabled(state: GameState) -> bool:
	return not state.crisis.is_empty()


static func cur(state: GameState) -> Dictionary:
	return state.crisis.get("cur", {}) if enabled(state) else {}


## Une crise est-elle en cours (annoncée ou arrivée) ?
static func ongoing(state: GameState) -> bool:
	return not cur(state).is_empty()


## L'empire sait-il qu'une crise approche ? Pendant le présage privé (talent), seuls ceux qui la sentent.
static func known(state: GameState, eid: int) -> bool:
	var c := cur(state)
	if c.is_empty():
		return false
	if String(c["stage"]) == "notice" and c.has("seers") and int(c["step"]) <= 1:
		return (c["seers"] as Array).has(eid)
	return true


## Une crise est-elle arrivée et encore en vie ?
static func active(state: GameState) -> bool:
	return String(cur(state).get("stage", "")) == "active"


static func kind(state: GameState) -> String:
	return String(cur(state).get("kind", ""))


static func name_of(kind_id: String) -> String:
	return String(kind_def(kind_id).get("name", "La Crise"))


## Jour où commence la fin de partie (déclencheurs précoces compris).
static func endgame_day(state: GameState) -> int:
	if not enabled(state):
		return -1
	return maxi(0, int(state.crisis["start"]) - int(state.crisis.get("pull", 0)))


static func is_crisis_fleet(f: Fleet) -> bool:
	return f != null and f.owner == GameState.CRISIS_ID


## Rôle d'une flotte de la crise : "heart", "station" ou "" (flotte de guerre).
static func role_of(state: GameState, fid: int) -> String:
	var st: Dictionary = cur(state).get("st", {})
	return String((st.get(fid, {}) as Dictionary).get("role", ""))


static func held(state: GameState) -> Dictionary:
	return cur(state).get("held", {})


static func is_held(state: GameState, sid: int) -> bool:
	return held(state).has(sid)


static func contrib(state: GameState, eid: int) -> int:
	return int((cur(state).get("contrib", {}) as Dictionary).get(eid, 0))


static func in_front(state: GameState, eid: int) -> bool:
	return (cur(state).get("front", {}) as Dictionary).has(eid)


## Deux empires du Front commun (vision partagée, passage libre).
static func front_pair(state: GameState, a: int, b: int) -> bool:
	if not active(state) or a == b:
		return false
	var fr: Dictionary = cur(state).get("front", {})
	return fr.has(a) and fr.has(b)


## Flottes en vie de la crise, triées : [flotte de guerre…] puis stations.
static func war_fleets(state: GameState) -> Array[Fleet]:
	var out: Array[Fleet] = []
	for fid in cur(state).get("war", []):
		var f: Fleet = state.fleets.get(int(fid))
		if f != null and not f.ships.is_empty():
			out.append(f)
	return out


static func stations(state: GameState) -> Array[Fleet]:
	var out: Array[Fleet] = []
	var st: Dictionary = cur(state).get("st", {})
	var ids := st.keys()
	ids.sort()
	for fid in ids:
		var f: Fleet = state.fleets.get(int(fid))
		if f != null and not f.ships.is_empty():
			out.append(f)
	return out


## Puissance totale de la crise en vie.
static func total_power(state: GameState) -> int:
	var p := 0
	for f in war_fleets(state):
		p += Combat.fleet_power(f)
	for f in stations(state):
		p += Combat.fleet_power(f)
	return p


## Avancée de la crise, en % du seuil de défaite commune.
static func menace_pct(state: GameState) -> int:
	var c := cur(state)
	if c.is_empty() or String(c["stage"]) != "active":
		return 0
	var need := _defeat_need(state)
	@warning_ignore("integer_division")
	return mini(100, held(state).size() * 100 / maxi(1, need))


static func _defeat_need(state: GameState) -> int:
	@warning_ignore("integer_division")
	return maxi(3, int(cur(state).get("base_owned", 10)) * int(data().get("defeat_pct", 50)) / 100)


## Production d'un système tombé (sort de la crise), en %.
static func production_pct(state: GameState, sid: int) -> int:
	if state.crisis.is_empty():
		return 100
	var pct := CrisisKinds.trace_pct(state, sid)  # traces durables, nuit, faillites du Krach
	if active(state) and is_held(state, sid):
		@warning_ignore("integer_division")
		pct = pct * CrisisAllies.fate_prod(state, state.system_owner(sid), int(fate_of(state).get("prod_pct", 100))) / 100
	return pct


## L'empire a-t-il pactisé avec la crise en cours (prop. 21) ?
static func pacted(state: GameState, eid: int) -> bool:
	return eid >= 0 and (cur(state).get("pact", {}) as Dictionary).has(eid)


## Trêve sacrée (prop. 15) : les guerres entre membres du Front commun sont gelées.
static func truce(state: GameState, a: int, b: int) -> bool:
	if state.crisis.is_empty() or not bool(data()["front"].get("truce", true)):
		return false
	return front_pair(state, a, b)


## Une guerre éclate entre deux empires (Combat.start_war) : rompre la trêve sacrée coûte cher.
static func on_war(state: GameState, a: int, b: int) -> void:
	if not truce(state, a, b):
		return
	(cur(state)["front"] as Dictionary).erase(a)
	for e in state.empires:
		if not e.eliminated and e.id != a:
			Diplomacy.remember(state, e.id, a, "truce_breaker")
	var bs: Dictionary = state.crisis["boons"]
	if not bs.has(a):
		bs[a] = []
	(bs[a] as Array).append({"label": "Trêve sacrée rompue", "fx": {"stability": -10}, "until": state.tick + 720})
	Relics.touch(state)
	state.add_chronicle("%s rompt la trêve sacrée et quitte le Front commun. Toute la galaxie retient ce nom-là." % state.get_empire(a).display_name())
	for e in state.empires:
		e.path_cache.clear()


static func fate_of(state: GameState) -> Dictionary:
	return kind_def(kind(state)).get("fate", {})


## La crise empêche-t-elle de s'installer ici ? (système tombé, ou point faible)
static func colony_block(state: GameState, sid: int) -> String:
	if not active(state):
		return ""
	if CrisisKinds.is_dark(state, sid):
		return "l'étoile est éteinte par la Nuit lente"
	if is_held(state, sid):
		return "%s tient ce système : libérez-le d'abord" % name_of(kind(state))
	for f in stations(state):
		if f.system_id == sid:
			return "un point faible %s occupe ce système : détruisez-le d'abord" % de_name(name_of(kind(state)))
	return ""


## Date limite repoussée tant qu'une crise est arrivée (prop. 26).
static func deadline(state: GameState, base: int) -> int:
	if base <= 0 or not active(state):
		return base
	return maxi(base, mini(base + int(data().get("deadline_max_days", 7200)), state.tick + 1))


# --- Nouvelle partie --------------------------------------------------------------------------------

## mode : aucune / une / toutes ; start : identifiant de « starts » ; strength : de « strengths » ;
## kinds : sortes autorisées (vide = toutes).
static func setup(state: GameState, mode: String, start := "", strength := "", kinds: Array = []) -> void:
	state.crisis = {}
	if _find(mode_defs(), mode).is_empty() or mode == "aucune":
		return
	var sd := _find(start_defs(), start if start != "" else default_start())
	if sd.is_empty():
		sd = _find(start_defs(), default_start())
	if _find(strength_defs(), strength).is_empty():
		strength = default_strength()
	var allowed: Array = []
	for k in kind_ids():
		if kinds.is_empty() or kinds.has(k):
			allowed.append(k)
	if allowed.is_empty():
		return
	state.crisis = {"mode": mode, "start": int(sd["day"]), "start_id": String(sd["id"]), "str": strength, "kinds": allowed,
			"pull": 0, "pulled": {}, "roll": 0, "count": 0, "done": [], "gap": 0, "cur": {}, "past": [], "boons": {}, "post": {}}


# --- Chaque jour ------------------------------------------------------------------------------------

static func daily(state: GameState) -> Array[Dictionary]:
	var added: Array[Dictionary] = []
	if not enabled(state):
		return added
	_expire_boons(state)
	CrisisKinds.traces_day(state, added)
	CrisisNemesis.daily(state, added)
	var c := cur(state)
	if c.is_empty():
		_maybe_start(state, added)
		return added
	if String(c["stage"]) == "notice":
		_notice(state, added)
		return added
	_active_day(state, added)
	return added


## Tirage de la fin de partie (prop. 2), une crise à la fois.
static func _maybe_start(state: GameState, added: Array[Dictionary]) -> void:
	var cr := state.crisis
	var day0 := roll_day(state)
	if day0 < 0 or state.tick < day0 or state.tick < int(cr["gap"]):
		return
	var rl: Dictionary = data()["roll"]
	var every := maxi(1, int(rl["every_days"]))
	if (state.tick - day0) % every != 0:
		return
	var pct := int(rl["pct"])
	for st: Array in rl.get("steps", []):
		if state.tick - day0 >= int(st[0]):
			@warning_ignore("integer_division")
			pct = pct * int(st[1]) / 100
	if _h(state, ["tirage", state.tick]) % 100 >= pct:
		return
	var k := _pick_kind(state)
	if k == "":
		return
	begin(state, k, added)


## Premier jour de tirage : la fin de partie, ou plus tôt pour une crise de milieu de partie
## (« from_day », le Roi-Corsaire dès l'an 15) ; -1 s'il ne reste rien à tirer.
static func roll_day(state: GameState) -> int:
	var day := endgame_day(state)
	if String(state.crisis["mode"]) == "une" and int(state.crisis["count"]) >= 1:
		day = -1  # la grande crise de la partie est passée ; une crise de milieu peut encore venir
	for k in state.crisis.get("kinds", []):
		var kd := kind_def(String(k))
		if bool(kd.get("mid", false)) and not (state.crisis["done"] as Array).has(k):
			day = int(kd.get("from_day", 0)) if day < 0 else mini(day, int(kd.get("from_day", 0)))
	return day


## Sortes possibles aujourd'hui (autorisées, pas encore passées, conditions remplies).
static func eligible_kinds(state: GameState) -> Array[String]:
	var out: Array[String] = []
	var endgame := state.tick >= endgame_day(state) and not (String(state.crisis["mode"]) == "une" and int(state.crisis["count"]) >= 1)
	for k in state.crisis.get("kinds", []):
		var kd := kind_def(String(k))
		if kd.is_empty() or (state.crisis["done"] as Array).has(k):
			continue
		var mid := bool(kd.get("mid", false))
		if (mid and state.tick < int(kd.get("from_day", 0))) or (not mid and not endgame):
			continue
		if String(kd.get("origin", "")) == "trade" and CrisisKinds.krach_origin(state) < 0:
			continue
		if int(kd.get("eligible_era5", 0)) > 0 and _era5_total(state) < int(kd["eligible_era5"]):
			continue
		if String(kd.get("origin", "")) == "storm" and _origin(state, String(k)) < 0:
			continue
		out.append(String(k))
	return out


static func _pick_kind(state: GameState) -> String:
	var ks := eligible_kinds(state)
	if ks.is_empty():
		return ""
	return ks[_h(state, ["sorte", state.tick, int(state.crisis["count"])]) % ks.size()]


## Technologies de l'ère V connues dans toute la galaxie (Inspection Générale).
static func _era5_total(state: GameState) -> int:
	var n := 0
	for e in state.empires:
		if e.eliminated:
			continue
		for tid in e.techs:
			if int(Research.tech(String(tid)).get("era", 0)) == 5:
				n += 1
	return n


## Lance une crise : préavis (ou arrivée immédiate pour une crise sans préavis).
static func begin(state: GameState, k: String, added: Array[Dictionary]) -> void:
	var kd := kind_def(k)
	var steps: Array = []
	var seers := CrisisAllies.foreseers(state, k)
	for x in MinorsBridges.presage_seers(state):  # Préscience de Quellis (peuple mineur)
		if not seers.has(x):
			seers.append(x)
	var ahead := maxi(CrisisAllies.foresight_days(k), MinorsBridges.presage_days(state, seers)) if not seers.is_empty() and (kd.get("notice", [0]) as Array).size() <= 1 else 0
	for d in kd.get("notice", [0]):
		steps.append(state.tick + ahead + int(d))
	if ahead > 0:
		steps.push_front(state.tick)  # présage privé des peuples qui sentent la crise (prop. 27)
	state.crisis["cur"] = {"kind": k, "stage": "notice", "since": state.tick, "steps": steps, "step": 0, "origin": _origin(state, k),
			"power": 0, "base_owned": 0, "war": [], "st": {}, "held": {}, "contrib": {}, "front": {}, "aloof": {}, "reinf": 0, "fallen": 0, "freed": 0,
			"pact": {}, "convoys": {}, "arms": {}, "fund": 0, "measures": []}
	if ahead > 0:
		cur(state)["seers"] = seers
	if String(kd.get("origin", "")) == "trade":
		var oe := CrisisKinds.krach_origin(state)
		cur(state)["origin_e"] = oe
		cur(state)["origin"] = FactionTraits.capital_system(state, oe) if oe >= 0 else -1
	if not bool(kd.get("mid", false)):
		state.crisis["count"] = int(state.crisis["count"]) + 1  # une crise de milieu ne compte pas pour « Une »
	(state.crisis["done"] as Array).append(k)
	_notice(state, added)


static func _notice(state: GameState, added: Array[Dictionary]) -> void:
	var c := cur(state)
	var steps: Array = c["steps"]
	while int(c["step"]) < steps.size() and state.tick >= int(steps[int(c["step"])]):
		var i := int(c["step"])
		c["step"] = i + 1
		var last := i == steps.size() - 1
		if i == 0 and c.has("seers"):
			_omen(state, c, added)
			continue
		var text := step_text(state, i - (1 if c.has("seers") else 0))
		added.append(state.add_chronicle(("CRISE. " if last else "Présage. ") + text))
		var card := "crise_arrivee" if last else ("crise_alerte_1" if i == 0 else "crise_alerte_2")
		_push_all(state, card, int(c["origin"]), added)
		if last:
			arrive(state, added)
			return


## Présage privé (talent « Ceux qui sentent la Faille ») : une chronique et une fenêtre pour eux seuls.
static func _omen(state: GameState, c: Dictionary, added: Array[Dictionary]) -> void:
	var o := int(c.get("origin", -1))
	for eid in c["seers"]:
		var omen := ""
		for t in CrisisAllies.talents_of(state, int(eid), String(c["kind"])):
			if t.has("omen"):
				omen = String(t["omen"])
		if omen == "":
			omen = MinorsBridges.omen(state, int(eid))
		if omen == "":
			continue
		omen = omen.replace("{empire}", state.get_empire(int(eid)).display_name()).replace("{origin}", state.galaxy.systems[o].system_name if o >= 0 else "la bordure")
		added.append(state.add_chronicle("Présage. " + omen, Espionage.private_to(state, [int(eid)], -1)))
		Events.push(state, int(eid), "crise_alerte_1", {"system": o}, added)


static func step_text(state: GameState, i: int) -> String:
	var c := cur(state)
	var steps: Array = kind_def(String(c.get("kind", ""))).get("steps", [])
	if steps.is_empty():
		return name_of(String(c.get("kind", "")))
	var s := String(steps[clampi(i, 0, steps.size() - 1)])
	var o := int(c.get("origin", -1))
	var oe := state.get_empire(int(c.get("origin_e", -1)))
	s = s.replace("{origin_e}", oe.display_name() if oe != null else "l'empire le plus riche")
	return s.replace("{origin}", state.galaxy.systems[o].system_name if o >= 0 else "la bordure")


## Met une carte de crise dans la boîte de chaque empire en jeu (fenêtre d'événement chez le joueur).
static func _push_all(state: GameState, card_id: String, sid: int, added: Array[Dictionary]) -> void:
	for e in state.empires:
		if not e.eliminated:
			Events.push(state, e.id, card_id, {"system": sid}, added)


# --- Arrivée ----------------------------------------------------------------------------------------

## Puissance visée (prop. 6) : moyenne des forces armées des empires les plus armés × réglage.
static func target_power(state: GameState) -> int:
	var pw: Array[int] = []
	for e in state.empires:
		if e.eliminated:
			continue
		var p := 0
		for f in Fleets.empire_fleets(state, e.id):
			if Combat.is_armed(f):
				p += Combat.fleet_power(f)
		pw.append(p)
	pw.sort()
	pw.reverse()
	var cfg: Dictionary = data()["power"]
	var top := mini(int(cfg["top"]), pw.size())
	var sum := 0
	for i in top:
		sum += pw[i]
	@warning_ignore("integer_division")
	var avg := sum / maxi(1, top)
	var pct := int(_find(strength_defs(), String(state.crisis.get("str", "normale"))).get("pct", 200))
	@warning_ignore("integer_division")
	var v := maxi(int(cfg["min"]), avg) * pct / 100
	# « Toutes » : chaque crise une fois et demie plus forte que la précédente.
	for _i in maxi(0, int(state.crisis.get("count", 1)) - 1):
		@warning_ignore("integer_division")
		v = v * int(data().get("next_pct", 150)) / 100
	return v


static func arrive(state: GameState, added: Array[Dictionary]) -> void:
	var c := cur(state)
	var k := String(c["kind"])
	var kd := kind_def(k)
	c["stage"] = "active"
	c["arrived"] = state.tick
	c["power"] = target_power(state)
	var owned := {}
	for pid in state.sorted_colony_ids():
		var col: Colony = state.colonies[pid]
		if not GameState.is_npc(col.owner):
			owned[state.galaxy.get_planet(pid).system_id] = true
	c["base_owned"] = owned.size()
	var origin := int(c["origin"])
	if origin < 0:
		origin = _origin(state, k)
		if origin < 0 and String(kd.get("origin", "")) == "storm":
			origin = _free_system(state, k)  # pas de tempête libre : la faille s'ouvre dans un coin vide
		c["origin"] = origin
	if origin < 0:
		_finish(state, "fizzle", -1, added)
		return
	# Mesures d'urgence (prop. 22) : trois décrets, à l'arrivée puis deux et quatre ans plus tard.
	c["measures"] = [state.tick + 60, state.tick + 720, state.tick + 1440]
	if bool(kd.get("fleetless", false)):
		CrisisKinds.arrive_fleetless(state, k, added)
		_push_all(state, "crise_front", origin, added)
		return
	var cfg: Dictionary = data()["power"]
	var pw := int(c["power"])
	# Cœur (sauf l'Inspection, dont le Registre n'apparaît qu'à la fin des Bureaux).
	if String(kd.get("core", "")) != "registre":
		@warning_ignore("integer_division")
		_station(state, String(kd["heart"]), origin, pw * int(cfg["heart_pct"]) / 100, ROLE_HEART)
	# Points faibles posés à l'arrivée : Bureaux de contrôle, ancres de la Déchirure.
	var n := int(kd.get("bureaus", kd.get("anchors", kd.get("lairs", 0))))
	if n > 0:
		var sites := CrisisKinds.lair_sites(state, n) if String(kd.get("origin", "")) == "lair" else _spread_sites(state, origin, n, String(kd.get("origin", "")) == "storm")
		for sid in sites:
			@warning_ignore("integer_division")
			_station(state, String(kd["station"]), sid, pw * int(cfg["station_pct"]) / 100, ROLE_STATION)
	# Vague d'arrivée.
	var waves := maxi(1, int(cfg["wave"]))
	for i in waves:
		@warning_ignore("integer_division")
		_war_fleet(state, origin, pw / waves, i)
	c["reinf"] = state.tick + int(cfg["reinf_days"])
	for e in state.empires:
		e.path_cache.clear()
	# Front commun (prop. 14) : l'Amphictyonie (ou, sans elle, les chancelleries) le propose à tous.
	_push_all(state, "crise_front", origin, added)
	# Pacte (prop. 21) : certaines crises proposent un marché.
	if kd.has("pact"):
		_push_all(state, "crise_pacte", origin, added)


## Crée une flotte de la crise d'une sorte d'unités jusqu'à la puissance voulue.
static func _build(state: GameState, ship_id: String, sid: int, power: int) -> Fleet:
	var f := state.spawn_ship(GameState.CRISIS_ID, ship_id, sid)
	var unit := maxi(1, Combat.ship_strength(ship_id))
	while Combat.fleet_power(f) + unit / 2 < power:
		f.add_ship(ship_id, -1, -1)
	f.troops = 0
	f.fleet_name = String(GameData.ship(ship_id).get("label", ship_id))
	return f


static func _station(state: GameState, ship_id: String, sid: int, power: int, role: String) -> Fleet:
	var f := _build(state, ship_id, sid, power)
	(cur(state)["st"] as Dictionary)[f.id] = {"role": role, "sid": sid}
	return f


## Flotte de guerre : composition de la vague (« wave » : [unité, poids]) jusqu'à la puissance voulue.
static func _war_fleet(state: GameState, sid: int, power: int, n: int) -> Fleet:
	var kd := kind_def(kind(state))
	var wave: Array = kd.get("wave", [])
	if wave.is_empty():
		return null
	var f := state.spawn_ship(GameState.CRISIS_ID, String(wave[0][0]), sid)
	var i := 0
	var guard := 0
	while Combat.fleet_power(f) < power and guard < 400:
		guard += 1
		var w: Array = wave[i % wave.size()]
		for _j in int(w[1]):
			if Combat.fleet_power(f) >= power:
				break
			f.add_ship(String(w[0]), -1, -1)
		i += 1
	f.troops = 0
	f.fleet_name = "%s %d" % [String(kd.get("short", "Crise")), int(cur(state).get("wn", 0)) + 1]
	cur(state)["wn"] = int(cur(state).get("wn", 0)) + 1
	(cur(state)["war"] as Array).append(f.id)
	return f


## Lieu d'arrivée selon la sorte : bordure, tempête, ou cœur de galaxie (Bureaux dispersés).
static func _origin(state: GameState, k: String) -> int:
	var kd := kind_def(k)
	var near := _near_capitals(state)
	var free: Array[int] = []
	for s in state.galaxy.systems:
		if state.system_owner(s.id) < 0 and not state.lairs.has(s.id) and int(near.get(s.id, 99)) >= 4:
			free.append(s.id)
	if free.is_empty():
		for s in state.galaxy.systems:
			if state.system_owner(s.id) < 0:
				free.append(s.id)
	if free.is_empty():
		return -1
	var center := Vector2.ZERO
	for s in state.galaxy.systems:
		center += s.position
	center /= maxf(1.0, float(state.galaxy.systems.size()))
	match String(kd.get("origin", "edge")):
		"lair":
			var lairs := Pirates.lair_ids(state)
			if not lairs.is_empty():
				return lairs[_h(state, ["roi", k]) % lairs.size()]
			return free[_h(state, ["roi", k]) % free.size()]
		"trade":
			var oe := CrisisKinds.krach_origin(state)
			return FactionTraits.capital_system(state, oe) if oe >= 0 else -1
		"storm":
			for stm: Dictionary in Terrain.storms(state):
				var cs := int(stm["c"])
				if state.system_owner(cs) < 0:
					return cs
			if Terrain.storms_on(state) and Terrain.active(state):
				return -1  # on attendra une tempête
			return free[_h(state, ["faille", k]) % free.size()]
		"bureaus":
			var best := -1
			var best_d := INF
			for sid in free:
				var d := state.galaxy.systems[sid].position.distance_to(center)
				if d < best_d:
					best_d = d
					best = sid
			return best
		_:
			var best := -1
			var best_d := -1.0
			for sid in free:
				var d := state.galaxy.systems[sid].position.distance_to(center) + float(_h(state, ["bord", sid]) % 100)
				if d > best_d:
					best_d = d
					best = sid
			return best


static func _free_system(state: GameState, k: String) -> int:
	var free: Array[int] = []
	var near := _near_capitals(state)
	for s in state.galaxy.systems:
		if state.system_owner(s.id) < 0 and not state.lairs.has(s.id) and int(near.get(s.id, 99)) >= 3:
			free.append(s.id)
	return free[_h(state, ["vide", k]) % free.size()] if not free.is_empty() else -1


static func _near_capitals(state: GameState) -> Dictionary:
	var near := {}
	for e in state.empires:
		var cap := FactionTraits.capital_system(state, e.id)
		if cap < 0:
			continue
		var j := FactionTraits.jumps_from(state.galaxy, cap)
		for s in j:
			near[int(s)] = mini(int(near.get(int(s), 99)), int(j[s]))
	return near


## n systèmes libres pour des points faibles : autour de l'origine (ancres, 2 à 5 sauts) ou dispersés
## dans la galaxie (Bureaux : le plus loin possible les uns des autres).
static func _spread_sites(state: GameState, origin: int, n: int, around: bool) -> Array[int]:
	var out: Array[int] = []
	var cands: Array[int] = []
	var jo := FactionTraits.jumps_from(state.galaxy, origin)
	for s in state.galaxy.systems:
		if s.id == origin or state.system_owner(s.id) >= 0 or state.lairs.has(s.id):
			continue
		if around and (int(jo.get(s.id, 99)) < 2 or int(jo.get(s.id, 99)) > 5):
			continue
		cands.append(s.id)
	if cands.is_empty():
		return out
	if around:
		cands.sort_custom(func(a: int, b: int) -> bool: return _h(state, ["ancre", a]) < _h(state, ["ancre", b]))
		for i in mini(n, cands.size()):
			out.append(cands[i])
		return out
	var taken: Array[int] = [origin]
	for _i in n:
		var best := -1
		var best_d := -1
		for sid in cands:
			if out.has(sid):
				continue
			var j := FactionTraits.jumps_from(state.galaxy, sid)
			var d := 999
			for t in taken:
				d = mini(d, int(j.get(t, 999)))
			d = d * 1000 + _h(state, ["bureau", sid]) % 1000
			if d > best_d:
				best_d = d
				best = sid
		if best < 0:
			break
		out.append(best)
		taken.append(best)
	return out


# --- Crise en cours ---------------------------------------------------------------------------------

static func _active_day(state: GameState, added: Array[Dictionary]) -> void:
	var c := cur(state)
	_measures(state, added)
	CrisisKinds.pacts_day(state, added)
	if bool(kind_def(String(c["kind"])).get("fleetless", false)):
		CrisisKinds.fleetless_day(state, added)
		return
	_prune(state)
	_held_day(state, added)
	_falls(state, added)
	_orders(state)
	_reinforce(state, added)
	CrisisKinds.convoys_day(state, added)
	CrisisAllies.fauna_day(state, added)
	_core_rules(state, added)
	if String(cur(state).get("stage", "")) != "active":
		return
	if _core_dead(state):
		_finish(state, "victoire", int(c.get("last_hit", -1)), added)
		return
	if held(state).size() >= _defeat_need(state) and state.winner.is_empty():
		_finish(state, "defaite", -1, added)


## Mesures d'urgence (prop. 22) : un décret de plus à chaque échéance, pour chaque empire.
static func _measures(state: GameState, added: Array[Dictionary]) -> void:
	var c := cur(state)
	var ms: Array = c.get("measures", [])
	for i in ms.size():
		if state.tick == int(ms[i]):
			_push_all(state, "crise_mesure_%d" % (i + 1), int(c["origin"]), added)


## Oublie les flottes détruites.
static func _prune(state: GameState) -> void:
	var c := cur(state)
	var war: Array = []
	for fid in c["war"]:
		var f: Fleet = state.fleets.get(int(fid))
		if f != null and not f.ships.is_empty():
			war.append(int(fid))
	c["war"] = war


## Systèmes tombés : sort du jour (corail, scellés, population bue) et libération s'il n'y a plus de
## flotte de la crise depuis lapse_days jours.
static func _held_day(state: GameState, added: Array[Dictionary]) -> void:
	var c := cur(state)
	var h: Dictionary = c["held"]
	var fate := fate_of(state)
	var lapse := int(data()["hold"]["lapse_days"])
	var ids := h.keys()
	ids.sort()
	for k in ids:
		var sid := int(k)
		var en: Dictionary = h[sid]
		var guarded := false
		for f in Fleets.fleets_at(state, sid, GameState.CRISIS_ID):
			if Combat.is_armed(f):
				guarded = true
				break
		if guarded:
			en["seen"] = state.tick
		elif state.tick - int(en["seen"]) >= lapse:
			_liberate(state, sid, added)
			continue
		_fate_day(state, sid, en, fate, added)


static func _fate_day(state: GameState, sid: int, en: Dictionary, fate: Dictionary, added: Array[Dictionary]) -> void:
	var fid := String(fate.get("id", ""))
	var dd := int(fate.get("drain_days", 0))
	if dd > 0 and (state.tick - int(en["since"])) % dd == 0 and state.tick > int(en["since"]):
		_drain(state, sid, int(fate.get("drain_pop", 1)), bool(fate.get("erase", false)), String(fate.get("station", "")), added)
	if fid == "seal":
		var month := int(GameData.rules()["month_days"])
		if (state.tick - int(en["since"])) % month == 0 and state.tick > int(en["since"]):
			_fine(state, sid, CrisisAllies.scaled(int(fate.get("fine_pct", 5)), CrisisAllies.tal(state, state.system_owner(sid), "fine_pct")))
		var cd := int(fate.get("confiscate_days", 0))
		if cd > 0 and state.tick - int(en["since"]) == cd:
			_confiscate(state, sid, added)


## Population bue ou recouverte : chaque colonie perd pop habitants ; une colonie vidée disparaît
## (jamais une capitale, qui garde un habitant) ; le Récif y fait pousser un Monde-Récif.
static func _drain(state: GameState, sid: int, pop: int, erase: bool, station: String, added: Array[Dictionary]) -> void:
	var gone := 0
	for pid in state.galaxy.systems[sid].planet_ids:
		var col: Colony = state.colonies.get(pid)
		if col == null or GameState.is_npc(col.owner):
			continue
		var e := state.get_empire(col.owner)
		var capital := e != null and e.capital_planet == pid
		if CrisisAllies.resists_drain(state, col.owner, sid):
			continue  # ruche sourde au chant du Récif
		if col.population > pop or capital or not erase:
			col.population = maxi(1, col.population - pop)
		else:
			state.colonies.erase(pid)
			gone += 1
	if gone > 0:
		state.rebuild_ownership()
		if station != "":
			var has := false
			for f in stations(state):
				if f.system_id == sid:
					has = true
			if not has:
				@warning_ignore("integer_division")
				_station(state, station, sid, int(cur(state)["power"]) * int(data()["power"]["station_pct"]) / 100, ROLE_STATION)
		added.append(state.add_chronicle("%s : %d colonie%s de %s rayée%s de la carte." % [name_of(kind(state)), gone, "s" if gone > 1 else "",
				state.galaxy.systems[sid].system_name, "s" if gone > 1 else ""]))


## Amende de l'Inspection : une part des réserves d'énergie du propriétaire.
static func _fine(state: GameState, sid: int, pct: int) -> void:
	var owner := state.system_owner(sid)
	var e := state.get_empire(owner)
	if e == null or GameState.is_npc(owner):
		return
	@warning_ignore("integer_division")
	e.resources["energy"] = maxi(0, int(e.resources.get("energy", 0)) - maxi(5, int(e.resources.get("energy", 0)) * pct / 100))


static func _confiscate(state: GameState, sid: int, added: Array[Dictionary]) -> void:
	var gone := 0
	for pid in state.galaxy.systems[sid].planet_ids:
		var col: Colony = state.colonies.get(pid)
		if col == null or GameState.is_npc(col.owner):
			continue
		var e := state.get_empire(col.owner)
		if e != null and e.capital_planet == pid:
			continue
		state.colonies.erase(pid)
		gone += 1
	if gone > 0:
		state.rebuild_ownership()
		added.append(state.add_chronicle("L'Inspection Générale confisque %s après deux ans de scellés. « Dossier clos », dit le tampon." % state.galaxy.systems[sid].system_name))


## Sièges menés à terme par la crise : le système tombe (garnison à zéro, ou siège qui dure).
static func _falls(state: GameState, added: Array[Dictionary]) -> void:
	# Début du siège vu par la crise : une bataille ne le remet pas à zéro (le siège du jeu, si).
	var c := cur(state)
	if not c.has("siege"):
		c["siege"] = {}
	var seen: Dictionary = c["siege"]
	var keys := state.sieges.keys()
	keys.sort()
	var now := {}
	for k in keys:
		var sid := int(k)
		var sg: Dictionary = state.sieges[k]
		if int(sg.get("by", -1)) != GameState.CRISIS_ID or is_held(state, sid) or pacted(state, state.system_owner(sid)):
			continue
		now[sid] = true
		if not seen.has(sid):
			seen[sid] = state.tick
		if Combat.garrison(state, sid) <= 0 or state.tick - int(seen[sid]) >= int(data()["hold"].get("siege_days", 90)):
			seen.erase(sid)
			fall(state, sid, added)
	# Plus aucune flotte de la crise devant la place : le siège repartira de zéro.
	for k in seen.keys():
		if not now.has(k) and Fleets.fleets_at(state, int(k), GameState.CRISIS_ID).is_empty():
			seen.erase(k)


static func fall(state: GameState, sid: int, added: Array[Dictionary]) -> void:
	var c := cur(state)
	var owner := state.system_owner(sid)
	(c["held"] as Dictionary)[sid] = {"since": state.tick, "seen": state.tick, "owner": owner}
	c["fallen"] = int(c.get("fallen", 0)) + 1
	var fate := fate_of(state)
	var text := String(fate.get("fall", "%s tombe.")) % state.galaxy.systems[sid].system_name
	added.append(state.add_chronicle(text))
	CrisisAllies.on_fall(state, sid, owner, added)
	if Stability.applies(state, owner):
		var en := Stability._entry_w(state, sid)
		en["hit"] = state.tick


static func _liberate(state: GameState, sid: int, added: Array[Dictionary]) -> void:
	var c := cur(state)
	(c["held"] as Dictionary).erase(sid)
	c["freed"] = int(c.get("freed", 0)) + 1
	var by: Array[int] = []
	for f in Fleets.fleets_at(state, sid):
		if not GameState.is_npc(f.owner) and Combat.is_armed(f) and not by.has(f.owner):
			by.append(f.owner)
	by.sort()
	var pts := int(data()["contrib"]["liberate"])
	for eid in by:
		add_contrib(state, eid, pts)
	if state.system_owner(sid) >= 0:
		added.append(state.add_chronicle("%s est libéré %s. On enlève les scellés, on balaie le corail, on recompte les vivants." % [
				state.galaxy.systems[sid].system_name, de_name(name_of(kind(state)))]))


static func add_contrib(state: GameState, eid: int, pts: int) -> void:
	if eid < 0 or GameState.is_npc(eid) or pts <= 0:
		return
	var ct: Dictionary = cur(state)["contrib"]
	ct[eid] = int(ct.get(eid, 0)) + pts


## Ordres des flottes de guerre : assiéger la colonie la plus proche (selon la préférence de la crise),
## sinon tenir un système tombé.
static func _orders(state: GameState) -> void:
	for f in war_fleets(state):
		if f.is_moving() or state.battles.has(f.system_id):
			continue
		var here := f.system_id
		var owner := state.system_owner(here)
		# En plein siège : on reste jusqu'à la chute.
		if owner >= 0 and not GameState.is_npc(owner) and not is_held(state, here):
			continue
		# Un système tombé doit garder au moins une flotte : la première arrivée reste.
		if is_held(state, here) and _first_guard(state, here) == f.id and not _needs_more(state):
			continue
		var t := _target(state, f)
		if t >= 0 and t != here:
			var route := Fleets.plan_route(state, f, t)
			if not route.is_empty():
				f.system_id = int(route["system"])
				f.path.assign(route["path"])
				f.progress = int(route["progress"])


static func _first_guard(state: GameState, sid: int) -> int:
	for g in Fleets.fleets_at(state, sid, GameState.CRISIS_ID):
		if role_of(state, g.id) == "":
			return g.id
	return -1


## Les flottes de garde repartent quand les gardes manquent ailleurs (peu de flottes de guerre).
static func _needs_more(state: GameState) -> bool:
	return war_fleets(state).size() <= held(state).size()


## Prochaine proie : système colonisé d'un empire, ni tombé, ni déjà visé par une autre flotte.
static func _target(state: GameState, f: Fleet) -> int:
	var kd := kind_def(kind(state))
	var prefer := _preferred(state, String(kd.get("prefer", "")))
	var jumps := FactionTraits.jumps_from(state.galaxy, f.system_id)
	var aimed := {}
	for g in war_fleets(state):
		if g.id != f.id and g.is_moving():
			aimed[g.path[-1] if not g.path.is_empty() else g.system_id] = true
	var best := -1
	var best_score := 1 << 40
	var seen := {}
	for pid in state.sorted_colony_ids():
		var col: Colony = state.colonies[pid]
		if GameState.is_npc(col.owner) or pacted(state, col.owner):
			continue
		var sid := state.galaxy.get_planet(pid).system_id
		if seen.has(sid) or is_held(state, sid):
			continue
		seen[sid] = true
		var j := int(jumps.get(sid, 999))
		if j >= 999:
			continue
		var score := j * 1000 + _h(state, ["proie", f.id, sid]) % 500
		if WondersCatalog.fx(state, col.owner, "crisis_last") > 0:
			score += 50000  # Rempart de l'Aube : visé en dernier
		if prefer >= 0 and col.owner != prefer:
			score += 4000
		if aimed.has(sid):
			score += 2500
		if score < best_score:
			best_score = score
			best = sid
	return best


static func _preferred(state: GameState, how: String) -> int:
	if how == "":
		return -1
	var best := -1
	var best_v := -1
	for e in state.empires:
		if e.eliminated:
			continue
		var v := 0
		if how == "advanced":
			v = e.techs.size()
		else:
			for pid in state.sorted_colony_ids():
				var col: Colony = state.colonies[pid]
				if col.owner == e.id:
					v += col.population
		if v > best_v:
			best_v = v
			best = e.id
	return best


## Renforts : chaque station en vie envoie une flotte tous les reinf_days jours.
static func _reinforce(state: GameState, added: Array[Dictionary]) -> void:
	var c := cur(state)
	var cfg: Dictionary = data()["power"]
	if state.tick < int(c["reinf"]):
		return
	c["reinf"] = state.tick + int(cfg["reinf_days"])
	var sts := stations(state)
	if sts.is_empty():
		return
	var room := int(cfg["reinf_max"]) - war_fleets(state).size()
	if room <= 0:
		return
	@warning_ignore("integer_division")
	var pw := maxi(200, int(c["power"]) * int(cfg["reinf_pct"]) / 100)
	var n := 0
	for st in sts:
		if n >= room:
			break
		_war_fleet(state, st.system_id, pw, n)
		n += 1
	if n > 0:
		added.append(state.add_chronicle("%s se renforce : %d nouvelle%s flotte%s." % [name_of(kind(state)), n, "s" if n > 1 else "", "s" if n > 1 else ""]))


## Règles du cœur : la Faille se répare tant que ses ancres tiennent ; le Registre central de
## l'Inspection apparaît quand le dernier Bureau ferme.
static func _core_rules(state: GameState, added: Array[Dictionary]) -> void:
	var c := cur(state)
	var kd := kind_def(String(c["kind"]))
	match String(kd.get("core", "")):
		"faille":
			var anchors := 0
			var heart: Fleet = null
			for f in stations(state):
				if role_of(state, f.id) == ROLE_STATION:
					anchors += 1
				elif role_of(state, f.id) == ROLE_HEART:
					heart = f
			if anchors > 0 and heart != null:
				for i in heart.ships.size():
					heart.hp[i] = Fleet.max_hp_of(heart.ships[i])
		"registre":
			if bool(c.get("registre", false)):
				return
			var bureaus := 0
			for f in stations(state):
				if role_of(state, f.id) == ROLE_STATION:
					bureaus += 1
			if bureaus == 0 and state.tick > int(c.get("arrived", 0)):
				c["registre"] = true
				@warning_ignore("integer_division")
				_station(state, String(kd["heart"]), int(c["origin"]), int(c["power"]) * int(data()["power"]["heart_pct"]) / 100, ROLE_HEART)
				added.append(state.add_chronicle("Le dernier Bureau de contrôle ferme. Le Registre central s'ouvre près de %s, furieux et en trois exemplaires." % state.galaxy.systems[int(c["origin"])].system_name))


## Le cœur de la crise est-il détruit ?
static func _core_dead(state: GameState) -> bool:
	var c := cur(state)
	var kd := kind_def(String(c["kind"]))
	var hearts := 0
	var others := 0
	for f in stations(state):
		if role_of(state, f.id) == ROLE_HEART:
			hearts += 1
		else:
			others += 1
	match String(kd.get("core", "")):
		"registre":
			return bool(c.get("registre", false)) and hearts == 0
		"heart_and_stations":
			return hearts == 0 and others == 0
		_:
			return hearts == 0


# --- Batailles --------------------------------------------------------------------------------------

## Fin de bataille : contribution de chaque camp (au prorata des dégâts infligés), points faibles détruits.
static func on_battle(state: GameState, b: Dictionary, winner: int, added: Array[Dictionary]) -> void:
	if not active(state):
		return
	var crisis_side: Dictionary = {}
	for s: Dictionary in b["sides"]:
		if int(s["empire"]) == GameState.CRISIS_ID:
			crisis_side = s
	if crisis_side.is_empty():
		return
	CrisisAllies.on_battle(state, b)
	var lost := 0
	for ship in crisis_side["lost"]:
		lost += Combat.ship_strength(String(ship)) * int(crisis_side["lost"][ship])
	var dealt := {}
	var total := 0
	for s: Dictionary in b["sides"]:
		var eid := int(s["empire"])
		if GameState.is_npc(eid):
			continue
		dealt[eid] = int(s.get("dealt", 0)) + 1
		total += int(dealt[eid])
	var keys := dealt.keys()
	keys.sort()
	for k in keys:
		@warning_ignore("integer_division")
		add_contrib(state, int(k), lost * int(dealt[k]) / maxi(1, total))
	# Stations détruites.
	var c := cur(state)
	var st: Dictionary = c["st"]
	var ids := st.keys()
	ids.sort()
	var top := -1
	var top_v := -1
	for k in keys:
		if int(dealt[k]) > top_v:
			top_v = int(dealt[k])
			top = int(k)
	if winner >= 0 and not GameState.is_npc(winner):
		top = winner
	CrisisKinds.on_battle_convoys(state, top, added)
	for fid in ids:
		var f: Fleet = state.fleets.get(int(fid))
		if f != null and not f.ships.is_empty():
			continue
		var role := String(st[fid]["role"])
		var sid := int(st[fid]["sid"])
		st.erase(fid)
		state.fleets.erase(int(fid))
		if role == ROLE_HEART and CrisisKinds.escape(state, sid, top, added):
			continue  # le Roi-Corsaire s'échappe (une fois)
		var pts := int(data()["contrib"]["heart" if role == ROLE_HEART else "station"])
		add_contrib(state, top, pts)
		CrisisAllies.slayer(state, b, top, added)
		if role == ROLE_HEART:
			c["last_hit"] = top
		var who := state.get_empire(top).display_name() if top >= 0 and not GameState.is_npc(top) else "on ne sait qui"
		added.append(state.add_chronicle("%s détruit %s à %s. %s" % [who, "le cœur de la crise" if role == ROLE_HEART else "un point faible %s" % de_name(name_of(String(c["kind"]))),
				state.galaxy.systems[sid].system_name, "La galaxie retient son souffle." if role == ROLE_HEART else "Elle faiblit."]))
	for e in state.empires:
		e.path_cache.clear()
	CrisisKinds.arms_check(state, added)


## Bonus de dégâts contre la crise : Front commun, talents de peuple, Commandant du Front, traits.
static func damage_pct(state: GameState, f: Fleet, sid: int) -> int:
	if state.crisis.is_empty():
		return 0
	var nem := CrisisNemesis.damage_pct(state, f, sid)  # contre le Fléau des étoiles (prop. 23)
	if not active(state) or GameState.is_npc(f.owner):
		return nem
	for g in Fleets.fleets_at(state, sid, GameState.CRISIS_ID):
		if not g.ships.is_empty():
			return (int(data()["front"]["damage_pct"]) if in_front(state, f.owner) else 0) + CrisisAllies.damage_pct(state, f) + nem
	return nem


# --- Fin de crise -----------------------------------------------------------------------------------

## Parts de contribution : [[empire, %]], du plus grand au plus petit.
static func shares(state: GameState) -> Array:
	var ct: Dictionary = cur(state).get("contrib", {})
	var total := 0
	for k in ct:
		total += int(ct[k])
	var out: Array = []
	if total <= 0:
		return out
	for k in ct:
		@warning_ignore("integer_division")
		out.append([-int(ct[k]) * 100 / total, int(k)])
	out.sort()
	return out.map(func(x: Array) -> Array: return [int(x[1]), -int(x[0])])


## result : "victoire" (le cœur est tombé), "defaite" (la galaxie a perdu), "fizzle" (pas de lieu).
static func _finish(state: GameState, result: String, by: int, added: Array[Dictionary]) -> void:
	var c := cur(state)
	var k := String(c["kind"])
	var sh := shares(state)
	var text := ""
	if by < 0 and result == "victoire" and not sh.is_empty():
		by = int(sh[0][0])  # crise sans cœur (Nuit, Krach) : le plus grand contributeur
	CrisisKinds.on_finish(state, result, added)
	match result:
		"victoire":
			CrisisAllies.on_victory(state, added)
			DeedsBridges.on_crisis_victory(state, sh)
			var v: Dictionary = data()["victory"]
			state.crisis["post"] = {"until": state.tick + int(v["days"]), "stab": int(v["stab"]), "kind": k}
			var parts: Array[String] = []
			for s: Array in sh:
				var eid := int(s[0])
				var pct := int(s[1])
				var e := state.get_empire(eid)
				if e == null or e.eliminated or pct < int(data()["contrib"]["min_share"]):
					continue
				@warning_ignore("integer_division")
				e.resources["influence"] = int(e.resources.get("influence", 0)) + int(v["influence"]) * pct / 100
				parts.append("%s (%d %%)" % [e.short_name(), pct])
			var relic := String(kind_def(k).get("relic", ""))
			var relic_txt := ""
			if relic != "" and by >= 0 and not GameState.is_npc(by):
				relic_txt = " Relique pour le coup final : %s à %s." % [Quests.give_relic(state, by, relic), state.get_empire(by).short_name()]
			text = "%s est vaincue ! Toute la galaxie respire : +%d de stabilité pendant dix ans. Le partage de la gloire : %s.%s" % [
					name_of(k), int(v["stab"]), ", ".join(parts) if not parts.is_empty() else "personne en particulier", relic_txt]
			Relics.touch(state)
		"defaite":
			var pact: Array = []
			for e in state.empires:
				if not e.eliminated and (c.get("pact", {}) as Dictionary).has(e.id):
					pact.append(e.id)
			state.winner = {"empire": GameState.CRISIS_ID, "victory": "crise", "tick": state.tick, "allies": pact}
			text = "DÉFAITE COMMUNE. %s tient la moitié des mondes de la galaxie. Les chroniqueurs rangent leurs plumes : il n'y aura bientôt plus personne pour les lire." % name_of(k)
		"depression":
			text = "Six ans de Krach, et personne n'a su relancer la galaxie : c'est la Grande Dépression. Elle laissera des traces pendant cinq ans."
		_:
			text = "%s ne trouve pas de prise sur la galaxie et se dissipe." % name_of(k)
	added.append(state.add_chronicle(text))
	# Les flottes de la crise se dissipent (sauf les restes sauvages, voir CrisisKinds).
	var keep: Dictionary = state.crisis.get("remnants", {})
	for fid in state.sorted_fleet_ids():
		var f: Fleet = state.fleets[fid]
		if f.owner == GameState.CRISIS_ID and not keep.has(fid):
			state.fleets.erase(fid)
	# Préparatifs liés à la crise (mesures d'urgence, armes du désespoir, pactes) : ils s'arrêtent avec elle.
	for eid in (state.crisis["boons"] as Dictionary).keys():
		var list: Array = state.crisis["boons"][eid]
		for i in range(list.size() - 1, -1, -1):
			if bool((list[i] as Dictionary).get("end", false)):
				list.remove_at(i)
	for sid in state.sieges.keys():
		if int(state.sieges[sid].get("by", -1)) == GameState.CRISIS_ID:
			state.sieges.erase(sid)
	for e in state.empires:
		e.path_cache.clear()
	(state.crisis["past"] as Array).append({"kind": k, "result": result, "tick": state.tick, "since": int(c["since"]),
			"by": by, "shares": sh, "fallen": int(c.get("fallen", 0)), "freed": int(c.get("freed", 0))})
	state.crisis["cur"] = {}
	state.crisis["gap"] = state.tick + int(data().get("gap_days", 3600))
	if result == "victoire":
		state.crisis["end_text"] = text
		_push_all(state, "crise_victoire", -1, added)


# --- Stabilité, effets, cartes ----------------------------------------------------------------------

## Lignes de stabilité de tout l'empire (victoire sur la crise).
static func stability_parts(state: GameState, eid: int) -> Array:
	var out := []
	if not enabled(state):
		return out
	var post: Dictionary = state.crisis.get("post", {})
	if not post.is_empty() and state.tick < int(post["until"]):
		out.append(["Victoire sur %s" % obj_name(name_of(String(post.get("kind", "")))), int(post["stab"])])
	if pacted(state, eid) and not CrisisAllies.tal_flag(state, eid, "pact_free"):
		out.append(["Pacte avec %s (factions hostiles)" % obj_name(name_of(kind(state))), int(data().get("pact_stab", -5))])
	out.append_array(CrisisKinds.stability_parts(state, eid))
	return out


## Effets (mêmes clés que les technologies) : préparatifs choisis dans les fenêtres de crise.
static func effects(state: GameState, eid: int) -> Dictionary:
	var out := {}
	if not enabled(state):
		return out
	for b: Dictionary in (state.crisis.get("boons", {}) as Dictionary).get(eid, []):
		Research._merge(out, b["fx"])
	if pacted(state, eid):
		Research._merge(out, kind_def(kind(state)).get("pact", {}).get("fx", {}))
	Research._merge(out, CrisisNemesis.effects(state, eid))
	return out


static func boons(state: GameState, eid: int) -> Array:
	return (state.crisis.get("boons", {}) as Dictionary).get(eid, []) if enabled(state) else []


static func _expire_boons(state: GameState) -> void:
	var bs: Dictionary = state.crisis.get("boons", {})
	var changed := false
	for k in bs.keys():
		var list: Array = bs[k]
		var i := 0
		while i < list.size():
			if int(list[i]["until"]) <= state.tick:
				list.remove_at(i)
				changed = true
				continue
			i += 1
	if changed:
		Relics.touch(state)


## Préparatif ou décret : days > 0 pour une durée, -1 jusqu'à la fin de la crise.
static func add_boon(state: GameState, eid: int, label: String, fx: Dictionary, days: int) -> void:
	var bs: Dictionary = state.crisis["boons"]
	if not bs.has(eid):
		bs[eid] = []
	var b := {"label": label, "fx": fx.duplicate(true), "until": state.tick + days if days > 0 else 1 << 40}
	if days < 0:
		b["end"] = true
	(bs[eid] as Array).append(b)
	Relics.touch(state)


## Effet « crisis » d'une carte (voir Events.apply_fx).
static func card_fx(state: GameState, eid: int, _item: Dictionary, fx: Dictionary, added: Array[Dictionary]) -> void:
	if not enabled(state):
		return
	match String(fx.get("act", "")):
		"boon":
			var bs: Dictionary = state.crisis["boons"]
			if not bs.has(eid):
				bs[eid] = []
			(bs[eid] as Array).append({"label": String(fx["label"]), "fx": (fx.get("fx", {}) as Dictionary).duplicate(true), "until": state.tick + int(fx.get("days", 360))})
			Relics.touch(state)
		"front":
			if active(state):
				(cur(state)["front"] as Dictionary)[eid] = state.tick
				added.append(state.add_chronicle("%s rejoint le Front commun contre %s." % [state.get_empire(eid).display_name(), obj_name(name_of(kind(state)))]))
				for e in state.empires:
					e.path_cache.clear()
		"aloof":
			if active(state):
				(cur(state)["aloof"] as Dictionary)[eid] = state.tick
		"measure":
			var mfx: Dictionary = (fx.get("fx", {}) as Dictionary).duplicate(true)
			if CrisisKinds.is_big(state, eid):
				mfx["stability"] = int(mfx.get("stability", 0)) - int(data().get("big_stab", 3))
			add_boon(state, eid, String(fx["label"]), mfx, -1)
		"pact":
			CrisisKinds.pact(state, eid, added)
		"resist":
			pass
		"arks":
			if active(state):
				(cur(state)["arks"] as Dictionary)[eid] = state.tick

## Texte d'un effet « crisis » dans la fenêtre d'événement.
static func fx_line(fx: Dictionary) -> String:
	match String(fx.get("act", "")):
		"boon":
			return "%s : %s pendant %d mois" % [String(fx["label"]), Relics.fx_text(fx.get("fx", {})), int(fx.get("days", 360)) / 30]
		"front":
			return "Vision partagée et passage libre avec le Front, +%d %% de dégâts contre la crise" % int(data()["front"]["damage_pct"])
		"aloof":
			return "Vous gardez les mains libres (et vos secrets)"
		"measure":
			return "%s jusqu'à la fin de la crise" % Relics.fx_text(fx.get("fx", {}))
		"pact":
			return "La crise vous épargne ; opinion des autres empires -30, stabilité -5, pas de Front commun"
		"resist":
			return "Vous restez libre de la combattre"
		"arks":
			return "Les habitants des mondes éteints rejoignent votre capitale au lieu de se perdre"
	return ""


## Valeur d'un effet « crisis » pour l'IA (AiEvents).
static func ai_value(fx: Dictionary, temper: int, state: GameState = null, eid := -1) -> int:
	var v := int(fx.get("ai", 0)) * 25  # même échelle que les ressources (10 par unité)
	match String(fx.get("act", "")):
		"front":
			v -= temper * 250  # un belliqueux rejoint moins volontiers
		"pact":
			# Pactise selon son tempérament (les pacifiques plus volontiers) et la menace : une crise bien
			# plus forte que lui qui arrive à ses portes.
			v = -400 - temper * 200
			if state != null and eid >= 0:
				var mine := 0
				for f in Fleets.empire_fleets(state, eid):
					mine += Combat.fleet_power(f)
				if total_power(state) > mine * 4:
					v += 700
	return v


## Jetons des cartes de crise : {crisis}, {crisis_step}, {crisis_weak}, {crisis_tip}, {crisis_wants},
## {crisis_front}, {crisis_end}.
static func fill(state: GameState, s: String) -> String:
	if not s.contains("{crisis"):
		return s
	var k := kind(state)
	if k == "" and not (state.crisis.get("past", []) as Array).is_empty():
		k = String((state.crisis["past"] as Array)[-1]["kind"])
	var kd := kind_def(k)
	var c := cur(state)
	var out := s.replace("{crisis_step}", step_text(state, maxi(0, int(c.get("step", 1)) - 1)) if not c.is_empty() else "")
	out = out.replace("{crisis_weak}", String(kd.get("weak", "")))
	out = out.replace("{crisis_tip}", String(kd.get("tip", "")))
	out = out.replace("{crisis_wants}", String(kd.get("wants", "")))
	out = out.replace("{crisis_end}", String(state.crisis.get("end_text", "")))
	var front := "Les chancelleries proposent une coalition contre %s." % obj_name(name_of(k))
	if state.amph_on and not state.amph.is_empty():
		front = "L'Amphictyonie se réunit en session extraordinaire, sans frais pour personne : elle propose un Front commun contre %s." % obj_name(name_of(k))
	out = out.replace("{crisis_front}", front)
	var pd: Dictionary = kd.get("pact", {})
	out = out.replace("{crisis_pact_label}", String(pd.get("label", "Pactiser")))
	out = out.replace("{crisis_pact}", String(pd.get("text", "")))
	out = out.replace("{crisis_de}", de_name(name_of(k)))
	out = out.replace("{crisis}", name_of(k))
	return out


## Nom après une préposition (contre, avec, sur) : l'article passe en minuscule.
static func obj_name(n: String) -> String:
	for art in ["Le ", "La ", "Les ", "L'"]:
		if n.begins_with(art):
			return art.to_lower() + n.substr(art.length())
	return n


## « de » + nom, avec l'article contracté : du Récif chantant, de la Déchirure, de l'Inspection Générale.
static func de_name(n: String) -> String:
	if n.begins_with("Le "):
		return "du " + n.substr(3)
	if n.begins_with("Les "):
		return "des " + n.substr(4)
	if n.begins_with("La ") or n.begins_with("L'"):
		return "de " + n.substr(0, 1).to_lower() + n.substr(1)
	return "de " + n


# --- Déclencheurs précoces (prop. 4) ----------------------------------------------------------------

## Un acte qui attire l'attention : la fin de partie avance de « days » jours (une fois par déclencheur).
static func pull(state: GameState, trigger: String, eid: int) -> void:
	if not enabled(state) or (state.crisis["pulled"] as Dictionary).has(trigger):
		return
	var ed: Dictionary = data()["early"]
	var before := int(state.crisis["pull"])
	var now := mini(int(ed["max"]), before + int(ed["days"]))
	if now == before:
		return
	state.crisis["pull"] = now
	state.crisis["pulled"][trigger] = state.tick
	var e := state.get_empire(eid)
	state.add_chronicle("Quelque chose, très loin, a remarqué ce que vient de faire %s. Les astronomes parlent d'un frisson dans le vide." % (e.display_name() if e != null else "quelqu'un"))


## Technologie terminée : est-elle interdite ?
static func on_tech(state: GameState, eid: int, tid: String) -> void:
	if enabled(state) and (data()["early"]["techs"] as Array).has(tid):
		pull(state, "tech:" + tid, eid)
		CrisisNemesis.gain(state, eid, int(CrisisNemesis.data().get("gain", {}).get("tech", 0)))


static func is_forbidden_tech(tid: String) -> bool:
	return (data().get("early", {}).get("techs", []) as Array).has(tid)


static func on_relic(state: GameState, eid: int, rid: String) -> void:
	if enabled(state) and (data()["early"]["relics"] as Array).has(rid):
		pull(state, "relic:" + rid, eid)


static func on_atrocity(state: GameState, eid: int) -> void:
	pull(state, "atrocite", eid)
	CrisisNemesis.gain(state, eid, int(CrisisNemesis.data().get("gain", {}).get("atrocity", 0)))


# --- Sauvegarde -------------------------------------------------------------------------------------

## Tables {entier: entier} de la crise en cours et de l'état général, sauvegardées en paires triées.
const CUR_PAIRS := ["contrib", "front", "aloof", "pact", "convoys", "arms", "arks", "dark", "infected", "siege", "vets", "woke"]
const TOP_PAIRS := ["remnants", "dark_after"]


static func to_dict(state: GameState) -> Dictionary:
	if not enabled(state):
		return {}
	var d := state.crisis.duplicate(true)
	var c: Dictionary = d.get("cur", {})
	if not c.is_empty():
		c["st"] = _map_to_list(c["st"])
		c["held"] = _map_to_list(c["held"])
		for k in CUR_PAIRS:
			if c.has(k):
				c[k] = _pairs(c[k])
	for k in TOP_PAIRS:
		if d.has(k):
			d[k] = _pairs(d[k])
	if d.has("scars"):
		d["scars"] = _map_to_list(d["scars"])
	var bs: Dictionary = d.get("boons", {})
	var bl := []
	var keys := bs.keys()
	keys.sort()
	for k in keys:
		bl.append({"e": int(k), "list": bs[k]})
	d["boons"] = bl
	d["pulled"] = _sorted_dict(d.get("pulled", {}))
	return d


static func from_dict(state: GameState, d: Dictionary) -> void:
	state.crisis = {}
	if d.is_empty():
		return
	var out: Dictionary = GameData._to_ints(d.duplicate(true))
	for k in ["mode", "start_id", "str", "end_text"]:
		if d.has(k):
			out[k] = String(d[k])
	out["kinds"] = (d.get("kinds", []) as Array).map(func(x: Variant) -> String: return String(x))
	out["done"] = (d.get("done", []) as Array).map(func(x: Variant) -> String: return String(x))
	var pulled := {}
	for k in d.get("pulled", {}):
		pulled[String(k)] = int(d["pulled"][k])
	out["pulled"] = pulled
	var past: Array = []
	for p: Dictionary in d.get("past", []):
		var q: Dictionary = GameData._to_ints(p)
		q["kind"] = String(p["kind"])
		q["result"] = String(p["result"])
		past.append(q)
	out["past"] = past
	var post: Dictionary = GameData._to_ints(d.get("post", {}))
	if post.has("kind"):
		post["kind"] = String(d["post"]["kind"])
	out["post"] = post
	for k in TOP_PAIRS:
		if d.has(k):
			out[k] = _unpairs(d[k])
	if d.has("scars"):
		out["scars"] = _list_to_map(d["scars"], ["label"])
	if d.has("dep"):
		var dep: Dictionary = GameData._to_ints(d["dep"])
		dep["who"] = (d["dep"].get("who", []) as Array).map(func(x: Variant) -> int: return int(x))
		out["dep"] = dep
	var bs := {}
	for x: Dictionary in d.get("boons", []):
		var list: Array = []
		for b: Dictionary in x["list"]:
			var nb := {"label": String(b["label"]), "fx": GameData._to_ints(b["fx"]), "until": int(b["until"])}
			if bool(b.get("end", false)):
				nb["end"] = true
			list.append(nb)
		bs[int(x["e"])] = list
	out["boons"] = bs
	var c: Dictionary = d.get("cur", {})
	if c.is_empty():
		out["cur"] = {}
	else:
		var oc: Dictionary = GameData._to_ints(c.duplicate(true))
		oc["kind"] = String(c["kind"])
		oc["stage"] = String(c["stage"])
		oc["st"] = _list_to_map(c.get("st", []), ["role"])
		oc["held"] = _list_to_map(c.get("held", []), [])
		for k in CUR_PAIRS:
			if c.has(k):
				oc[k] = _unpairs(c[k])
		for k in ["war", "steps", "measures"]:
			if c.has(k):
				oc[k] = (c[k] as Array).map(func(v: Variant) -> int: return int(v))
		out["cur"] = oc
	state.crisis = out


static func _map_to_list(m: Dictionary) -> Array:
	var keys := m.keys()
	keys.sort()
	var out := []
	for k in keys:
		var v: Dictionary = (m[k] as Dictionary).duplicate(true)
		v["id"] = int(k)
		out.append(v)
	return out


static func _list_to_map(list: Array, strings: Array) -> Dictionary:
	var out := {}
	for x: Dictionary in list:
		var v: Dictionary = GameData._to_ints(x)
		for s in strings:
			if x.has(s):
				v[s] = String(x[s])
		var id := int(v["id"])
		v.erase("id")
		out[id] = v
	return out


static func _pairs(d: Dictionary) -> Array:
	var keys := d.keys()
	keys.sort()
	return keys.map(func(k: Variant) -> Array: return [int(k), int(d[k])])


static func _unpairs(a: Array) -> Dictionary:
	var out := {}
	for p: Array in a:
		out[int(p[0])] = int(p[1])
	return out


static func _sorted_dict(d: Dictionary) -> Dictionary:
	var keys := d.keys()
	keys.sort()
	var out := {}
	for k in keys:
		out[k] = d[k]
	return out


## Flottes de la crise encore sur la carte (toutes sortes).
static func fleets_left(state: GameState) -> int:
	var n := 0
	for fid in state.sorted_fleet_ids():
		if (state.fleets[fid] as Fleet).owner == GameState.CRISIS_ID:
			n += 1
	return n
