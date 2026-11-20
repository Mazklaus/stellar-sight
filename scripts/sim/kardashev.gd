class_name Kardashev
extends RefCounted
## L'échelle de Kardashev (étude du 2026-11-17, version resserrée validée le 2026-11-18 ; données :
## data/kardashev.json). Pilier à part (prop. 1) : l'indice des mégastructures y a déménagé ;
## Megastructures.kardashev*() renvoient ici.
##
## Chaque mois, l'indice (×100, 0 à 300) se calcule sur la Puissance captée (prop. 2) : énergie brute
## des colonies, plus la puissance des étapes de mégastructures achevées, versée au trésor ou non (le
## Cerveau Matriochka ne fait plus baisser l'indice). Entre deux ancres, la décimale suit une échelle
## logarithmique (prop. 3, formule de Sagan) calculée en entiers (_log2_fx) pour rester identique sur
## toutes les machines ; on part vers 0,70 (prop. 4). Un type entier ne se franchit qu'avec son verrou
## (prop. 5) : sinon l'indice plafonne à x,99.
##
## Mode Complète (prop. 47) : prérogatives à chaque demi-palier (prop. 12, dormantes sous leur palier,
## prop. 24), rattrapage (prop. 15), signature thermique et Sobriété (prop. 21-22), Âge sombre et Âge
## héroïque (prop. 25). Mode Indice seul : la mesure, ses verrous, l'affichage et le rang (prop. 26).
## Aucun palier ne donne de bonus de combat direct (prop. 16).
##
## État : state.kardashev = {"mode", "pace", "k": {eid: indice ×100}, "best": {eid: meilleur type},
##  "half": {eid: meilleur demi-palier 0-5}, "perks": {eid: [ids]}, "pend": {eid: [niveaux à choisir]},
##  "first": {"type": [eids dans l'ordre de passage]}, "dark": {eid: type perdu}, "sober": {eid: 1},
##  "veil": {eid: jour de fin}, "veil_cd": {eid: jour où il redevient possible}, "stars": {sid: type},
##  "relight": {eid: {"s", "until"}}, "power": {eid: puissance captée}}.

const SUBS := ["ai", "k", "best", "half", "perks", "pend", "first", "dark", "sober", "veil", "veil_cd", "stars", "relight", "power"]


static func data() -> Dictionary:
	return GameData.kardashev()


static func cfg(section: String) -> Dictionary:
	var v: Variant = data().get(section, {})
	return v if v is Dictionary else {}


static func c_int(section: String, key: String, def := 0) -> int:
	return int(cfg(section).get(key, def))


# --- Réglage, sauvegarde -----------------------------------------------------------------------

static func mode_defs() -> Array:
	return data().get("modes", [])


static func pace_defs() -> Array:
	return data().get("paces", [])


static func default_mode() -> String:
	return String(data().get("default_mode", "complete"))


static func default_pace() -> String:
	return String(data().get("default_pace", "normal"))


static func setup(state: GameState, mode_id: String, pace_id := "") -> void:
	state.kardashev = {}
	if mode_id == "desactivee" or not _ids(mode_defs()).has(mode_id):
		return
	var p := pace_id if _ids(pace_defs()).has(pace_id) else default_pace()
	state.kardashev = {"mode": mode_id, "pace": p}
	for k in SUBS:
		state.kardashev[k] = {}
	for e in state.empires:
		if not e.is_npc():
			sub(state, "k")[str(e.id)] = int(cfg("power").get("start_k", 70))


static func _ids(defs: Array) -> Array[String]:
	var out: Array[String] = []
	for d: Dictionary in defs:
		out.append(String(d["id"]))
	return out


static func enabled(state: GameState) -> bool:
	return state != null and not state.kardashev.is_empty()


## Mode Complète : prérogatives, rattrapage, chaleur, Âge sombre.
static func full(state: GameState) -> bool:
	return enabled(state) and String(state.kardashev.get("mode", "")) == "complete"


static func mode(state: GameState) -> String:
	return String(state.kardashev.get("mode", "desactivee"))


static func mode_label(state: GameState) -> String:
	for m: Dictionary in mode_defs():
		if String(m["id"]) == mode(state):
			return String(m["label"])
	return "Désactivée"


static func pace_label(state: GameState) -> String:
	for m: Dictionary in pace_defs():
		if String(m["id"]) == String(state.kardashev.get("pace", "")):
			return String(m["label"])
	return ""


static func pace_pct(state: GameState) -> int:
	for m: Dictionary in pace_defs():
		if String(m["id"]) == String(state.kardashev.get("pace", "")):
			return int(m.get("pct", 100))
	return 100


static func applies(state: GameState, eid: int) -> bool:
	if not enabled(state) or eid < 0 or GameState.is_npc(eid):
		return false
	var e := state.get_empire(eid)
	return e != null and not e.eliminated


static func worth_saving(state: GameState) -> bool:
	return enabled(state)


static func to_dict(state: GameState) -> Dictionary:
	return state.kardashev.duplicate(true)


static func from_dict(state: GameState, d: Dictionary) -> void:
	if d.is_empty():
		state.kardashev = {}
		return
	state.kardashev = GameData._to_ints(d.duplicate(true))
	for k in SUBS:
		if not state.kardashev.has(k):
			state.kardashev[k] = {}


## Anciennes sauvegardes (avant la 92) : l'indice vivait chez les mégastructures. Une partie qui les
## avait en jeu reçoit l'échelle en mode Complète ; l'indice se recalcule au premier mois.
@warning_ignore("integer_division")
static func migrate(state: GameState) -> void:
	if enabled(state) or state.megas.is_empty():
		return
	setup(state, "complete", default_pace())
	var old: Dictionary = state.megas.get("kard", {})
	for k in old:
		sub(state, "k")[String(k)] = int(old[k]) * 10
		var t := int(old[k]) / 10
		sub(state, "best")[String(k)] = t
	state.megas.erase("kard")


static func sub(state: GameState, k: String) -> Dictionary:
	if state.kardashev.is_empty():
		return {}  # pilier désactivé : ne jamais le rallumer en écrivant
	if not state.kardashev.has(k):
		state.kardashev[k] = {}
	return state.kardashev[k]


static func _gi(state: GameState, k: String, eid: int, def := 0) -> int:
	return int(sub(state, k).get(str(eid), def))


static func touch(state: GameState) -> void:
	state.relic_rev += 1  # les effets (Research.effects) se recalculent


# --- L'indice ----------------------------------------------------------------------------------

## Indice ×100 (0 à 300).
static func index100(state: GameState, eid: int) -> int:
	return _gi(state, "k", eid, int(cfg("power").get("start_k", 70)))


@warning_ignore("integer_division")
static func tier(state: GameState, eid: int) -> int:
	if not enabled(state):
		return 0
	return mini(3, index100(state, eid) / 100)


## Demi-palier atteint (0 à 5 : 1,0 ; 1,5 ; 2,0 ; 2,5 ; 3,0).
static func half_level(state: GameState, eid: int) -> int:
	return half_of(index100(state, eid))


static func half_of(k: int) -> int:
	var n := 0
	for v in data().get("levels", [100, 150, 200, 250, 300]):
		if k >= int(v):
			n += 1
	return n


@warning_ignore("integer_division")
static func value_text(k: int) -> String:
	return "%d,%02d" % [k / 100, k % 100]


static func title(t: int) -> String:
	var titles: Array = data().get("titles", [])
	return String(titles[t]) if t >= 0 and t < titles.size() else ""


static func text(state: GameState, eid: int) -> String:
	if not enabled(state):
		return "—"
	var t := tier(state, eid)
	var s := value_text(index100(state, eid))
	return "%s (%s)" % [s, title(t)] if title(t) != "" else s


static func roman(t: int) -> String:
	return ["0", "I", "II", "III"][clampi(t, 0, 3)]


## log2(x) × 1024 en entiers (x >= 1) : partie entière par décalages, puis 10 bits de fraction par
## élévations au carré successives d'une mantisse en virgule fixe (1 << 16). Identique partout.
static func _log2_fx(x: int) -> int:
	var v := maxi(1, x)
	var ip := 0
	var n := v
	while n >= 2:
		n >>= 1
		ip += 1
	var m := (v << 16) >> ip  # mantisse dans [1, 2) en virgule fixe 16 bits
	var frac := 0
	for i in 10:
		m = (m * m) >> 16
		frac <<= 1
		if m >= (2 << 16):
			m >>= 1
			frac |= 1
	return ip * 1024 + frac


## Ancres de puissance (0,70 ; 1,00 ; 2,00 ; 3,00), les trois dernières selon le rythme.
@warning_ignore("integer_division")
static func anchors(state: GameState) -> Array[int]:
	var a: Array = cfg("power").get("anchors", [15, 300, 8000, 120000])
	var out: Array[int] = [int(a[0])]
	var pct := pace_pct(state)
	for i in range(1, a.size()):
		out.append(maxi(out[-1] + 1, int(a[i]) * pct / 100))
	return out


## Indice ×100 brut (sans verrou) pour une puissance donnée.
@warning_ignore("integer_division")
static func index_of_power(state: GameState, p: int) -> int:
	var a := anchors(state)
	var sk := int(cfg("power").get("start_k", 70))
	var lp := _log2_fx(maxi(1, p))
	if p < a[1]:
		var l0 := _log2_fx(a[0])
		var l1 := _log2_fx(a[1])
		return clampi(sk + (100 - sk) * (lp - l0) / maxi(1, l1 - l0), int(cfg("power").get("min_k", 0)), 99)
	for t in range(1, a.size() - 1):
		if p < a[t + 1]:
			var la := _log2_fx(a[t])
			var lb := _log2_fx(a[t + 1])
			return t * 100 + clampi(100 * (lp - la) / maxi(1, lb - la), 0, 99)
	return 300


## Puissance captée par les mégastructures (prop. 2) : par étape achevée qui compte.
@warning_ignore("integer_division")
static func mega_power(state: GameState, eid: int) -> int:
	if state.megas.is_empty():
		return 0
	var cap := cfg("power").get("capture", {}) as Dictionary
	var total := 0
	for m in Megastructures.owned_by(state, eid):
		var n := Megastructures.eff_stage(m)
		if n <= 0:
			continue
		var k := String(m["k"])
		var per := int(cap.get(k, -1))
		if per < 0:
			var era := int(Megastructures.kind_def(k).get("era", 1))
			per = int(cap.get("era5", 0)) if era >= 5 else (int(cap.get("era4", 0)) if era >= 4 else 0)
		total += per * n * Megastructures.star_pct(state, m) / 100
	return total


## Mondes forgés ou démantelés (pilier de la Forge des mondes ; 0 quand l'option est coupée).
static func worldforge_count(state: GameState, eid: int) -> int:
	return WorldForge.kardashev_count(state, eid)


## Puissance captée (prop. 2), détaillée : {"colonies", "megas", "worlds", "sober_pct", "total"}.
@warning_ignore("integer_division")
static func power_parts(state: GameState, eid: int) -> Dictionary:
	var gross := int((Economy.empire_income(state, eid)["gross"] as Dictionary).get("energy", 0))
	var megas := mega_power(state, eid)
	var worlds := worldforge_count(state, eid) * int(cfg("power").get("worldforge", 0))
	var pct := c_int("signature", "sober_power_pct", 85) if sober(state, eid) else 100
	var total := (maxi(0, gross) + megas + worlds) * pct / 100
	return {"colonies": gross, "megas": megas, "worlds": worlds, "sober_pct": pct, "total": total}


# --- Verrous (prop. 5) -------------------------------------------------------------------------

static func lock_def(t: int) -> Dictionary:
	var v: Variant = cfg("locks").get(str(t), {})
	return v if v is Dictionary else {}


static func capital_buildings(state: GameState, eid: int) -> int:
	var sid := FactionTraits.capital_system(state, eid)
	if sid < 0:
		return 0
	var best := 0
	for pid in state.galaxy.systems[sid].planet_ids:
		var c: Colony = state.colonies.get(pid)
		if c != null and c.owner == eid and c.is_colony():
			best = maxi(best, c.buildings.size())
	return best


static func great_counts(state: GameState, eid: int) -> Array[int]:
	var great := 0
	var era5 := 0
	if state.megas.is_empty():
		return [0, 0]
	for m in Megastructures.owned_by(state, eid):
		if Megastructures.complete(m):
			var era := int(Megastructures.kind_def(String(m["k"])).get("era", 1))
			if era >= 4:
				great += 1
				if era >= 5:
					era5 += 1
	return [great, era5]


## Ce qui manque pour le verrou du type t (vide = levé).
@warning_ignore("integer_division")
static func lock_missing(state: GameState, eid: int, t: int) -> Array[String]:
	var out: Array[String] = []
	var d := lock_def(t)
	match t:
		1:
			for tid in d.get("techs", []):
				if not Research.knows(state, eid, String(tid)):
					out.append("la technologie %s" % String(Research.tech(String(tid)).get("label", tid)))
			var nb := int(d.get("capital_buildings", 4))
			if capital_buildings(state, eid) < nb:
				out.append("%d bâtiments sur la capitale (%d)" % [nb, capital_buildings(state, eid)])
		2:
			if state.megas.is_empty():
				out.append("une étoile emmaillotée (les mégastructures ne sont pas en jeu)")
			elif Megastructures.complete_count(state, eid, "sphere_dyson") < int(d.get("spheres", 1)) \
					and Megastructures.complete_count(state, eid, "essaim_dyson") < int(d.get("swarms", 3)):
				out.append("une Sphère de Dyson achevée ou %d Essaims achevés (%d)" % [int(d.get("swarms", 3)), Megastructures.complete_count(state, eid, "essaim_dyson")])
		3:
			out.append_array(lock_missing(state, eid, 2))
			var gc := great_counts(state, eid)
			if gc[0] < int(d.get("great", 6)) or gc[1] < int(d.get("era5", 3)):
				out.append("%d grandes mégastructures achevées dont %d de l'ère V (%d, dont %d)" % [int(d.get("great", 6)), int(d.get("era5", 3)), gc[0], gc[1]])
			var need := maxi(1, state.galaxy.systems.size() * int(d.get("systems_pct", 10)) / 100)
			var have := EmpireReport.owned_systems(state, eid).size()
			if have < need:
				out.append("%d systèmes (%d)" % [need, have])
	return out


static func lock_ok(state: GameState, eid: int, t: int) -> bool:
	return lock_missing(state, eid, t).is_empty()


## Indice ×100 avec les verrous (prop. 5).
## power : puissance déjà calculée (power_parts()["total"]) pour ne pas refaire le bilan, -1 sinon.
static func compute(state: GameState, eid: int, power := -1) -> int:
	var raw := index_of_power(state, power if power >= 0 else int(power_parts(state, eid)["total"]))
	for t in range(1, 4):
		if raw >= t * 100 and not lock_ok(state, eid, t):
			return t * 100 - 1
	return raw


# --- Chaque mois -------------------------------------------------------------------------------

## Appelé chaque jour : chaque empire est mis à jour à son jour du mois (EconomySystem.month_day,
## le 1er pour les humains), la part commune (KardashevWorld) le 1er.
static func monthly(state: GameState, added: Array[Dictionary]) -> void:
	if not enabled(state):
		return
	for e in state.empires:
		if e.is_npc() or e.eliminated or not EconomySystem.month_day(state, e):
			continue
		_update(state, e.id, added)
	if full(state) and state.tick % int(GameData.rules()["month_days"]) == 0:
		KardashevWorld.monthly(state, added)


@warning_ignore("integer_division")
static func _update(state: GameState, eid: int, added: Array[Dictionary]) -> void:
	var before := tier(state, eid)
	var half_before := _gi(state, "half", eid)
	var p := power_parts(state, eid)
	sub(state, "power")[str(eid)] = int(p["total"])
	var k := compute(state, eid, int(p["total"]))
	var old_k := index100(state, eid)
	sub(state, "k")[str(eid)] = k
	var t := tier(state, eid)
	var e := state.get_empire(eid)
	if t > before:
		touch(state)
		var firsts: Dictionary = sub(state, "first")
		for tt in range(before + 1, t + 1):
			var order: Array = firsts.get(str(tt), [])
			if not order.has(eid):
				order.append(eid)
				firsts[str(tt)] = order
		if t > _gi(state, "best", eid):
			Announce.next(state, "kardashev", {"actor": eid})
			added.append(state.add_chronicle("%s franchit le type %s de l'échelle de Kardashev : %s. Les astronomes voisins notent une étoile un peu moins brillante que prévu." % [
					e.short_name(), roman(t), title(t)]))
			MegasBridges.on_kardashev(state, eid, t, added)
	elif t < before:
		touch(state)
	if t > _gi(state, "best", eid):
		sub(state, "best")[str(eid)] = t
	if full(state):
		KardashevWorld.on_update(state, eid, before, t, half_before, added)
	if half_of(old_k) != half_of(k):
		touch(state)  # une prérogative s'endort ou se réveille (prop. 24)


# --- Effets ------------------------------------------------------------------------------------

## Effets pour Research.effects : Rayonnement du type, prérogatives éveillées, Âge sombre.
static func effects(state: GameState, eid: int) -> Dictionary:
	var out := {}
	if not applies(state, eid):
		return out
	var t := tier(state, eid)
	var cp: Array = data().get("culture_pct", [])
	if t > 0 and t < cp.size() and int(cp[t]) != 0:
		out["culture_pct"] = int(cp[t])
	if full(state):
		KardashevWorld.effects(state, eid, out)
	return out


## Rang dans l'opinion (prop. 26) : ce que a pense de b à cause de l'écart de type et des prérogatives
## de b. [[libellé, valeur]].
static func opinion_parts(state: GameState, a: int, b: int) -> Array:
	var out := []
	if state.kardashev.is_empty() or GameState.is_npc(a) or GameState.is_npc(b):
		return out
	var ta := tier(state, a)
	var tb := tier(state, b)
	var st := Diplomacy.status(state, a, b)
	if tb > ta:
		var rk := cfg("rank")
		if st == Diplomacy.ALLIANCE or st == Diplomacy.PEACE:
			out.append(["Révérence : type %s de Kardashev" % roman(tb), int(rk.get("reverence", 8))])
		else:
			out.append(["Crainte : type %s de Kardashev" % roman(tb), int(rk.get("fear", -8)) * (tb - ta)])
	if full(state) and st != "war":
		var lower := 0
		var peace := 0
		for pid in awake_perks(state, b):
			var pd := perk_def(pid)
			lower += int(pd.get("opinion_lower", 0))
			peace += int(pd.get("opinion_peace", 0))
		if lower != 0 and tb > ta:
			out.append(["Prestige de la puissance", lower])
		if peace != 0:
			out.append(["Phare de la galaxie", peace])
	return out


# --- Prérogatives (prop. 12, 24) ----------------------------------------------------------------

static func perk_ids() -> Array[String]:
	var out: Array[String] = []
	for k in cfg("perks"):
		if not String(k).begins_with("_"):
			out.append(String(k))
	return out


static func perk_def(pid: String) -> Dictionary:
	var v: Variant = cfg("perks").get(pid, {})
	return v if v is Dictionary else {}


static func perks_of_level(level: int) -> Array[String]:
	var out: Array[String] = []
	for pid in perk_ids():
		if int(perk_def(pid).get("level", 0)) == level:
			out.append(pid)
	return out


static func perks(state: GameState, eid: int) -> Array:
	return sub(state, "perks").get(str(eid), [])


static func has_perk(state: GameState, eid: int, pid: String) -> bool:
	return perks(state, eid).has(pid)


## Prérogatives éveillées : celles dont le demi-palier est encore atteint (prop. 24).
static func awake_perks(state: GameState, eid: int) -> Array[String]:
	var out: Array[String] = []
	var hl := half_level(state, eid)
	for pid in perks(state, eid):
		if int(perk_def(String(pid)).get("level", 99)) <= hl:
			out.append(String(pid))
	return out


static func awake(state: GameState, eid: int, pid: String) -> bool:
	return full(state) and awake_perks(state, eid).has(pid)


static func pending(state: GameState, eid: int) -> Array:
	return sub(state, "pend").get(str(eid), [])


## Prérogatives qu'on peut choisir maintenant : celles d'un niveau en attente (0 = Âge héroïque : un
## niveau déjà atteint, au choix), non prises.
static func offer(state: GameState, eid: int) -> Array[String]:
	var out: Array[String] = []
	var pend := pending(state, eid)
	if pend.is_empty():
		return out
	var lv := int(pend[0])
	var hl := half_level(state, eid)
	for pid in perk_ids():
		var pl := int(perk_def(pid).get("level", 0))
		if has_perk(state, eid, pid):
			continue
		if (lv > 0 and pl == lv) or (lv == 0 and pl <= hl):
			out.append(pid)
	return out


# --- Commandes ---------------------------------------------------------------------------------

## Raison pour laquelle l'action est impossible ("" = possible). act : "perk" (id), "sober" (on),
## "veil", "relight" (s).
static func check(state: GameState, eid: int, act: String, d: Dictionary) -> String:
	if not applies(state, eid):
		return "l'échelle de Kardashev n'est pas en jeu"
	if not full(state):
		return "réglage Indice seul : pas de prérogatives ni de chaleur"
	match act:
		"perk":
			var pid := String(d.get("id", ""))
			if perk_def(pid).is_empty():
				return "prérogative inconnue"
			if not offer(state, eid).has(pid):
				return "cette prérogative n'est pas à choisir maintenant"
			return ""
		"sober":
			return ""
		"veil", "relight":
			return KardashevWorld.check(state, eid, act, d)
	return "action inconnue"


static func apply(state: GameState, eid: int, act: String, d: Dictionary) -> Array[Dictionary]:
	var added: Array[Dictionary] = []
	var e := state.get_empire(eid)
	match act:
		"perk":
			var pid := String(d["id"])
			var list: Array = perks(state, eid).duplicate()
			list.append(pid)
			sub(state, "perks")[str(eid)] = list
			var pend: Array = pending(state, eid).duplicate()
			pend.remove_at(0)
			if pend.is_empty():
				sub(state, "pend").erase(str(eid))
			else:
				sub(state, "pend")[str(eid)] = pend
			touch(state)
			added.append(state.add_chronicle("%s choisit sa prérogative : %s. %s" % [e.short_name(), String(perk_def(pid)["label"]), String(perk_def(pid).get("text", ""))],
					Espionage.private_to(state, [eid])))
		"sober":
			if bool(d.get("on", true)):
				sub(state, "sober")[str(eid)] = 1
			else:
				sub(state, "sober").erase(str(eid))
			added.append(state.add_chronicle("%s %s la Sobriété thermique." % [e.short_name(), "proclame" if bool(d.get("on", true)) else "lève"], Espionage.private_to(state, [eid])))
		"veil", "relight":
			KardashevWorld.apply(state, eid, act, d, added)
	return added


static func sober(state: GameState, eid: int) -> bool:
	return full(state) and _gi(state, "sober", eid) > 0
