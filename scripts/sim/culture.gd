class_name Culture
extends RefCounted
## Rayonnement culturel (étude « Rayonnement culturel », 2026-11-15 ; data/culture.json).
## Chaque empire produit un Rayonnement mensuel : population sereine, Musée galactique et reliques
## exposées, merveilles culturelles, stations de villégiature (beauté du système), foi, Conservateurs et
## héros (Civ VI : Tourisme ; Distant Worlds 2 : stations de villégiature). Ce Rayonnement part vers chaque
## empire rencontré, modulé par les liens (routes commerciales, passage, foi d'État, gouvernements et
## credos, luxes exportés ; Humankind : l'influence suit les routes de l'exportateur) et se cumule cible
## par cible. Le cumul se compare au Patrimoine de la cible (influence cumulée, œuvres, lois, âge des
## colonies) : le rapport donne six paliers (Civ V : 10/30/60/100/200 %).
## Les effets des paliers, merveilles, osmoses, défection culturelle et victoire sont dans CultureLife
## (lot 2) ; les actions, lois, opérations, Amphictyonie, talents et ponts dans CultureBridges (lot 3).
##
## État : state.culture = {} (aucun) ou {"mode", "defect", "rad": {empire: n}, "cum": {"a>b": n},
##  "last": {"a>b": n}, "pat": {empire: n}, "tier": {"a>b": palier}, "exp": {empire: [reliques]},
##  "inc": {empire: {ressource: n}}, "seen": {planète: jour}, "inf": {empire: influence du mois}, ...}.
## Toutes les clés sont des chaînes (la sauvegarde JSON les rend ainsi), tous les nombres des entiers.
## Les cibles sont des empires, ou des peuples mineurs (version simple : prop. 3).

const MONTH := 30
const OFFSET := 17  ## jour du mois du bilan culturel (après le bilan économique du jour 0)


static func data() -> Dictionary:
	return GameData.culture()


static func mode_defs() -> Array:
	return data().get("modes", [])


static func defect_defs() -> Array:
	return data().get("defect_modes", [])


static func default_mode() -> String:
	return String(data().get("default_mode", "actif"))


static func default_defect() -> String:
	return String(data().get("default_defect", "rare"))


static func tiers() -> Array:
	return data()["tiers"]


static func tier_label(i: int) -> String:
	return String(tiers()[clampi(i, 0, tiers().size() - 1)]["label"])


static func tier_color(i: int) -> Color:
	return Color(String(tiers()[clampi(i, 0, tiers().size() - 1)].get("color", "#cccccc")))


static func tier_for_pct(pct: int) -> int:
	var out := 0
	for i in tiers().size():
		if pct >= int(tiers()[i]["min"]):
			out = i
	return out


# --- Réglage, sauvegarde -----------------------------------------------------------------------

static func enabled(state: GameState) -> bool:
	return not state.culture.is_empty()


static func worth_saving(state: GameState) -> bool:
	return not state.culture.is_empty()


static func setup(state: GameState, mode: String, defect := "") -> void:
	state.culture = {}
	if mode != "actif":
		return
	var dm := defect if defect != "" else default_defect()
	var ok := false
	for d: Dictionary in defect_defs():
		if String(d["id"]) == dm:
			ok = true
	state.culture = {"mode": mode, "defect": dm if ok else default_defect(), "rad": {}, "cum": {}, "last": {}, "pat": {},
			"tier": {}, "exp": {}, "inc": {}, "seen": {}, "inf": {}}
	var start := int(data().get("start_heritage", 60))
	for e in state.empires:
		if not e.is_npc():
			state.culture["pat"][str(e.id)] = start


static func to_dict(state: GameState) -> Dictionary:
	return Ancients._sorted(state.culture)


static func from_dict(state: GameState, d: Dictionary) -> void:
	state.culture = {}
	if d.is_empty():
		return
	state.culture = GameData._to_ints(d.duplicate(true))


static func defect_mode(state: GameState) -> String:
	return String(state.culture.get("defect", "aucune"))


static func _m(state: GameState, key: String) -> Dictionary:
	if not state.culture.has(key):
		state.culture[key] = {}
	return state.culture[key]


static func _k(a: int, b: int) -> String:
	return "%d>%d" % [a, b]


# --- Lecture ------------------------------------------------------------------------------------

## Rayonnement mensuel de l'empire (dernier bilan).
static func radiance(state: GameState, eid: int) -> int:
	if state.culture.is_empty():
		return 0
	return int(state.culture.get("rad", {}).get(str(eid), 0))


## Patrimoine de l'empire (ou du peuple mineur).
static func heritage(state: GameState, eid: int) -> int:
	if state.culture.is_empty():
		return 0
	return maxi(1, int(state.culture.get("pat", {}).get(str(eid), int(data().get("start_heritage", 60))))) + DeedsBridges.heritage_bonus(state, eid)


## Rayonnement cumulé de a reçu par b.
static func cumul(state: GameState, a: int, b: int) -> int:
	if state.culture.is_empty():
		return 0
	return int(state.culture.get("cum", {}).get(_k(a, b), 0))


## Rayonnement de a reçu par b le mois dernier (tendance).
static func last(state: GameState, a: int, b: int) -> int:
	if state.culture.is_empty():
		return 0
	return int(state.culture.get("last", {}).get(_k(a, b), 0))


## Rapport cumul ÷ Patrimoine de la cible, en pour cent.
static func ratio_pct(state: GameState, a: int, b: int) -> int:
	@warning_ignore("integer_division")
	return cumul(state, a, b) * 100 / heritage(state, b)


## Palier de a chez b (0 Inconnu … 5 Dominant).
static func tier(state: GameState, a: int, b: int) -> int:
	if state.culture.is_empty():
		return 0
	return int(state.culture.get("tier", {}).get(_k(a, b), 0))


## Plus haut palier atteint chez b, et par qui : [palier, empire] (-1 si personne).
static func top_influencer(state: GameState, b: int) -> Array:
	var best := [0, -1]
	for e in state.empires:
		if e.id == b or e.is_npc():
			continue
		var t := tier(state, e.id, b)
		if t > int(best[0]) or (t == int(best[0]) and t > 0 and cumul(state, e.id, b) > cumul(state, int(best[1]), b)):
			best = [t, e.id]
	return best


## Mois avant le palier suivant, au rythme du dernier mois (-1 = jamais à ce rythme, 0 = au plus haut).
static func months_to_next(state: GameState, a: int, b: int) -> int:
	var t := tier(state, a, b)
	if t >= tiers().size() - 1:
		return 0
	var need := int(tiers()[t + 1]["min"]) * heritage(state, b) / 100 - cumul(state, a, b)
	var rate := last(state, a, b) - _heritage_rate(state, b) * int(tiers()[t + 1]["min"]) / 100
	if need <= 0:
		return 1
	if rate <= 0:
		return -1
	@warning_ignore("integer_division")
	return (need + rate - 1) / rate


static func _heritage_rate(state: GameState, b: int) -> int:
	return int(state.culture.get("hrate", {}).get(str(b), 0))


static func living(state: GameState) -> Array[int]:
	var out: Array[int] = []
	for e in state.empires:
		if not e.eliminated and not e.is_npc():
			out.append(e.id)
	return out


## Cibles d'un empire : empires rencontrés vivants, puis peuples mineurs en contact (version simple).
static func targets(state: GameState, a: int) -> Array[int]:
	var out: Array[int] = []
	var e := state.get_empire(a)
	if e == null:
		return out
	for o in e.contacts:
		var oe := state.get_empire(o)
		if oe != null and not oe.eliminated and not oe.is_npc() and not Insolites.silent(state, o):  # les Silencieux n'écoutent pas
			out.append(o)
	if not state.minors.is_empty():
		for mid in Minors.ids(state):
			if Minors.in_contact(state, mid, a):
				out.append(mid)
	return out


# --- Talents par couche d'espèce (prop. 34) -----------------------------------------------------

static var _talent_cache := {}


static func talent(state: GameState, eid: int) -> Dictionary:
	var e := state.get_empire(eid)
	if e == null or e.is_npc():
		return {}
	var ck := "%s:%d" % [e.faction_id, GameData.factions_gen]
	if _talent_cache.has(ck):
		return _talent_cache[ck]
	var out := {}
	var sp: Dictionary = FactionTraits.species(e.faction())
	var table: Dictionary = data().get("talents", {})
	var rows: Array = []
	for layer in ["archetype", "gouvernement", "credo", "registre"]:
		rows.append((table.get(layer, {}) as Dictionary).get(String(sp.get(layer, "")), {}))
	for t in sp.get("traits", []):
		rows.append((table.get("traits", {}) as Dictionary).get(String(t), {}))
	rows.append((table.get("peoples", {}) as Dictionary).get(e.faction_id, {}))
	for t: Dictionary in rows:
		for k in t:
			if k == "label" or k == "text":
				continue
			var v: Variant = t[k]
			out[k] = v if v is bool else int(out.get(k, 0)) + int(v)
	_talent_cache[ck] = out
	return out


static func tal(state: GameState, eid: int, key: String) -> int:
	return int(talent(state, eid).get(key, 0))


static func talent_labels(state: GameState, eid: int) -> Array:
	var e := state.get_empire(eid)
	var out := []
	if e == null or e.is_npc():
		return out
	var sp: Dictionary = FactionTraits.species(e.faction())
	var table: Dictionary = data().get("talents", {})
	var rows: Array = []
	for layer in ["archetype", "gouvernement", "credo", "registre"]:
		rows.append((table.get(layer, {}) as Dictionary).get(String(sp.get(layer, "")), {}))
	for t in sp.get("traits", []):
		rows.append((table.get("traits", {}) as Dictionary).get(String(t), {}))
	rows.append((table.get("peoples", {}) as Dictionary).get(e.faction_id, {}))
	for t: Dictionary in rows:
		if not t.is_empty():
			out.append([String(t["label"]), String(t["text"])])
	return out


# --- Beauté (prop. 10) --------------------------------------------------------------------------

## Beauté d'un système, de 0 à 10 : étoile, terrain, mondes-jardins, curiosités, gardiens.
static func beauty(state: GameState, sid: int) -> int:
	return _sum(beauty_parts(state, sid))


static func beauty_parts(state: GameState, sid: int) -> Array:
	var b: Dictionary = data()["beauty"]
	var out := []
	var s: StarSystem = state.galaxy.systems[sid]
	var st := int(b["stars"].get(s.star_type, 0))
	if st != 0:
		out.append(["Étoile remarquable", st])
	for t in Terrain.at(state, sid):
		var v := int(b["terrains"].get(t, 0))
		if v != 0:
			out.append([Terrain.label(t), v])
	var pl := 0
	var cur := 0
	for pid in s.planet_ids:
		pl += int(b["planets"].get(state.galaxy.get_planet(pid).type, 0))
		if not state.curios.is_empty() and state.curios.has(pid):
			cur += int(b["curio"])
	if pl != 0:
		out.append(["Mondes remarquables", mini(pl, 4)])
	if cur != 0:
		out.append(["Curiosités", cur])
	if not state.fauna.is_empty():
		for gid in Guardians.ids(state):
			if Guardians.fleet_system(state, gid) == sid:
				out.append(["Gardien", int(b["guardian"])])
				break
	return out


static func _sum(parts: Array) -> int:
	var n := 0
	for p in parts:
		n += int(p[1])
	return clampi(n, 0, int(data()["beauty"]["max"]))


# --- Sources du Rayonnement (props 7-12) --------------------------------------------------------

## Colonies de l'empire qui ont un bâtiment, triées.
static func _with_building(state: GameState, eid: int, bid: String) -> Array[int]:
	var out: Array[int] = []
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner == eid and c.is_established() and c.buildings.has(bid):
			out.append(pid)
	return out


static func has_museum(state: GameState, eid: int) -> bool:
	return not _with_building(state, eid, "musee_galactique").is_empty()


## Reliques exposées au Musée galactique (au plus trois ; un thème complet d'abord).
static func exposed(state: GameState, eid: int) -> Array[String]:
	var out: Array[String] = []
	if state.relics.is_empty() or not has_museum(state, eid):
		return out
	var slots := int(data()["sources"]["museum_slots"])
	var pool := Relics.in_reliquary(state, eid)
	var by_tag := {}
	for rid in pool:
		for t in Relics.def(rid).get("tags", []):
			if not by_tag.has(t):
				by_tag[t] = []
			by_tag[t].append(rid)
	var tags := by_tag.keys()
	tags.sort()
	for t in tags:
		if (by_tag[t] as Array).size() >= slots:
			for i in slots:
				out.append(String(by_tag[t][i]))
			return out
	for rid in pool:
		if out.size() < slots:
			out.append(rid)
	return out


## Thème complet au musée : les reliques exposées partagent toutes une étiquette.
static func theme_of(rids: Array) -> String:
	if rids.size() < int(data()["sources"]["museum_slots"]):
		return ""
	var common: Array = (Relics.def(String(rids[0])).get("tags", []) as Array).duplicate()
	for rid in rids:
		var tg: Array = Relics.def(String(rid)).get("tags", [])
		common = common.filter(func(t: Variant) -> bool: return tg.has(t))
	return "" if common.is_empty() else String(common[0])


## Rayonnement d'une merveille culturelle pour son propriétaire (valeur + 1 par ère franchie depuis).
static func wonder_value(state: GameState, eid: int, bid: String) -> int:
	var b := GameData.building(bid)
	var v := int(b.get("culture_wonder", 0))
	if v <= 0:
		# Toute merveille rayonne un peu (prop. 17 des merveilles) : base + 1 par ère de la merveille.
		if not Wonders.is_wonder(bid):
			return 0
		v = Wonders.r_int("radiance_base") + int(b.get("era", 1)) * Wonders.r_int("radiance_per_era")
	v += maxi(0, Research.current_era(state, eid) - int(b.get("era", 1))) * int(data()["sources"]["wonder_era_bonus"])
	return v + tal(state, eid, "wonder_bonus")


## Détail du Rayonnement brut : [[libellé, points], …] puis le pourcentage total.
static func source_parts(state: GameState, eid: int) -> Array:
	var out := []
	var e := state.get_empire(eid)
	if e == null or e.is_npc() or e.eliminated or state.culture.is_empty():
		return out
	if bool(talent(state, eid).get("no_radiance", false)):
		return out
	var src: Dictionary = data()["sources"]
	# Population sereine (prop. 7) : pleine si stable, moitié si agitée, rien en révolte.
	var pop := 0
	for sid in Stability.systems_of(state, eid):
		var p := Stability.system_pop(state, sid, eid)
		if p <= 0:
			continue
		var tid := Stability.tier_id(state, sid) if Stability.applies(state, eid) else "calme"
		if tid == "revolte":
			continue
		@warning_ignore("integer_division")
		pop += p * (int(src["pop_tense_pct"]) if tid == "agitation" else 100) / 100
	@warning_ignore("integer_division")
	var vp := pop * int(src["pop_pct"]) / 100
	if vp > 0:
		out.append(["Population sereine (%d)" % pop, vp])
	# Musée galactique et reliques exposées (prop. 8).
	if has_museum(state, eid):
		out.append(["Musée galactique", int(src["museum"])])
		var ex := exposed(state, eid)
		if not ex.is_empty():
			var per := int(src["relic"])
			var v := 0
			for rid in ex:
				var rv := per
				if bool(talent(state, eid).get("royal_x2", false)) and (Relics.def(rid).get("tags", []) as Array).has("royale"):
					rv *= 2
				v += rv
			var th := theme_of(ex)
			if th != "":
				v *= int(src["theme_mult"])
			out.append(["Reliques exposées (%d)%s" % [ex.size(), " : thème complet" if th != "" else ""], v])
	# Merveilles culturelles (prop. 9) et stations de villégiature (prop. 10), Conservateurs (prop. 12).
	var won := 0
	var sta := 0
	var cons := 0
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner != eid or not c.is_established():
			continue
		var sid := state.galaxy.get_planet(pid).system_id
		var here := 0
		for bid in c.buildings:
			here += wonder_value(state, eid, bid)
		if c.buildings.has("villegiature"):
			sta += beauty(state, sid) * int(src["station_per_beauty"])
		if here > 0:
			won += here
			cons += CultureBridges.conservator_bonus(state, eid, sid, here)
	if won > 0:
		out.append(["Merveilles culturelles", won])
	if sta > 0:
		out.append(["Stations de villégiature (beauté)", sta])
	if cons > 0:
		out.append(["Conservateurs", cons])
	# Foi (prop. 11) et héros (prop. 12) : lot 3.
	out.append_array(CultureBridges.extra_sources(state, eid))
	out.append_array(Archaeology.culture_parts(state, eid))  # Hauts lieux, musée des antiquités
	out.append_array(Insolites.culture_parts(state, eid))  # Collection du Muséum de Sire Cassivel
	# Arènes des Ferrocornes : batailles gagnées le mois dernier.
	var br := tal(state, eid, "battle_radiance")
	if br > 0:
		var won_b := int(e.stats.get("battles_won", 0)) - int(_m(state, "bw").get(str(eid), int(e.stats.get("battles_won", 0))))
		if won_b > 0:
			out.append(["Arènes : victoires du mois", br * won_b])
	return out


## Pourcentage appliqué au Rayonnement brut (technologies, talents, lois).
static func radiance_pct(state: GameState, eid: int) -> int:
	return 100 + Research.fx_int(state, eid, "culture_pct") + tal(state, eid, "radiance_pct") + CultureBridges.law_pct(state, eid, "radiance_pct") + DeedsBridges.radiance_pct(state, eid)


## Rayonnement mensuel calculé à cet instant (sans le cache du bilan).
static func compute_radiance(state: GameState, eid: int) -> int:
	var n := 0
	for p in source_parts(state, eid):
		n += int(p[1])
	@warning_ignore("integer_division")
	return maxi(0, n * radiance_pct(state, eid) / 100)


# --- Diffusion (props 15-20) --------------------------------------------------------------------

static func _routes_between(state: GameState, a: int, b: int) -> int:
	var n := 0
	for r: Dictionary in state.trade.get("routes", []):
		if String(r["kind"]) != "ext" or bool(r.get("blocked", false)):
			continue
		if (int(r["from"]) == a and int(r["to"]) == b) or (int(r["from"]) == b and int(r["to"]) == a):
			n += 1
	return n


static func _luxuries_to(state: GameState, a: int, b: int) -> int:
	var n := 0
	for l: Dictionary in state.goods.get("lic", []):
		if int(l["seller"]) == a and int(l["buyer"]) == b:
			n += 1
	return n


static func at_war(state: GameState, a: int, b: int) -> bool:
	var e := state.get_empire(a)
	return e != null and e.wars.has(b)


## Détail des modificateurs de diffusion de a vers b : {"parts": [[libellé, %], …], "cut": raison ou "",
## "link": lien établi (route, alliance ou commerce)}.
static func flow_parts(state: GameState, a: int, b: int) -> Dictionary:
	var out := {"parts": [], "cut": "", "link": false}
	var md: Dictionary = data()["mods"]
	if GameState.is_minor(b):
		out["parts"].append(["Peuple mineur", int(md["minor_pct"]) - 100])
		out["link"] = true
		return out
	if at_war(state, a, b):
		out["cut"] = "en guerre"
		return out
	if not state.trade.is_empty() and Trade.embargoed(state, a, b) and not bool(talent(state, a).get("ignore_embargo", false)):
		out["cut"] = "embargo"
		return out
	var parts: Array = out["parts"]
	var nr := _routes_between(state, a, b)
	if nr > 0:
		parts.append(["Routes commerciales (%d)" % nr, mini(int(md["route_max"]), nr * int(md["route"]))])
	if Borders.active(state):
		var pol := Borders.policy(state, b, a)
		if pol == Borders.CLOSED:
			parts.append(["Frontières fermées", int(md["closed"])])
		elif Borders.grants(state, b, a):
			parts.append(["Droit de passage", int(md["passage"])])
	if state.faith_on and Faiths.has_state_faith(state, a) and Faiths.state_faith(state, a) == Faiths.state_faith(state, b):
		parts.append(["Même foi d'État", int(md["same_faith"])])
	var sa := FactionTraits.species(state.get_empire(a).faction())
	var sb := FactionTraits.species(state.get_empire(b).faction())
	var op: Dictionary = Diplomacy.data()["opinion"]
	var ga := String(sa.get("gouvernement", ""))
	var gb := String(sb.get("gouvernement", ""))
	if ga != gb:
		if Diplomacy._pair_value(op["gouvernement_pairs"], ga, gb) < 0:
			parts.append(["Gouvernements opposés", int(md["gov_opposed"])])
		else:
			parts.append(["Gouvernements différents", int(md["gov_diff"])])
	var ca := String(sa.get("credo", ""))
	var cb := String(sb.get("credo", ""))
	if ca != cb and Diplomacy._pair_value(op["credo_pairs"], ca, cb) < 0:
		parts.append(["Credos opposés", int(md["credo_opposed"])])
	if ca != cb and tal(state, a, "other_credo_pct") != 0:
		parts.append(["Talent : vers un autre credo", tal(state, a, "other_credo_pct")])
	var lx := _luxuries_to(state, a, b)
	if lx > 0:
		var per := int(md["luxury"]) + tal(state, a, "luxury_extra")
		parts.append(["Luxes exportés (%d licences)" % lx, mini(int(md["luxury_max"]) + tal(state, a, "luxury_extra") * 3, lx * per)])
	var link := nr > 0 or Diplomacy.allied(state, a, b) or Diplomacy.has_trade(state, a, b)
	out["link"] = link
	if link and tal(state, a, "link_pct") != 0:
		parts.append(["Talent : conversation galactique", tal(state, a, "link_pct")])
	parts.append_array(CultureBridges.flow_extra(state, a, b))
	if not link:
		parts.append(["Aucun lien (route, commerce ou alliance) : moitié", -int(md["no_link_pct"])])
	return out


## Pourcentage total de diffusion de a vers b (0 si coupée). Le « sans lien » est un multiplicateur.
static func flow_pct(state: GameState, a: int, b: int, fp := {}) -> int:
	if fp.is_empty():
		fp = flow_parts(state, a, b)
	if String(fp["cut"]) != "":
		return 0
	var add := 0
	for p in fp["parts"]:
		if not String(p[0]).begins_with("Aucun lien"):
			add += int(p[1])
	var pct := maxi(0, 100 + add)
	if not bool(fp["link"]):
		@warning_ignore("integer_division")
		pct = pct * (100 - int(data()["mods"]["no_link_pct"])) / 100
	return pct


# --- Bilan mensuel ------------------------------------------------------------------------------

## Revenu culturel du mois (Savoir des routes, énergie des stations…) : lu par Economy.empire_income.
static func income(state: GameState, eid: int) -> Dictionary:
	if state.culture.is_empty():
		return {}
	return state.culture.get("inc", {}).get(str(eid), {})


## Appelé par le bilan économique : l'influence brute du mois nourrit le Patrimoine (prop. 1).
static func note_influence(state: GameState, eid: int, gross_influence: int) -> void:
	if state.culture.is_empty():
		return
	_m(state, "inf")[str(eid)] = maxi(0, gross_influence)


static func daily(state: GameState) -> Array[Dictionary]:
	var added: Array[Dictionary] = []
	if state.culture.is_empty():
		return added
	if state.tick % MONTH == OFFSET:
		monthly(state, added)
	CultureLife.daily(state, added)
	return added


static func monthly(state: GameState, added: Array[Dictionary]) -> void:
	var ids := living(state)
	# 1. Rayonnement de chacun.
	var rad := _m(state, "rad")
	for eid in ids:
		rad[str(eid)] = compute_radiance(state, eid)
		var e := state.get_empire(eid)
		_m(state, "bw")[str(eid)] = int(e.stats.get("battles_won", 0))
	_m(state, "exp").clear()
	for eid in ids:
		var ex := exposed(state, eid)
		if not ex.is_empty():
			state.culture["exp"][str(eid)] = ex
	# 2. Patrimoine (prop. 1 et 14).
	_heritage(state, ids)
	# 3. Diffusion, cumul et paliers.
	var cum := _m(state, "cum")
	var lst := _m(state, "last")
	var tr := _m(state, "tier")
	lst.clear()
	for a in ids:
		var base := int(rad[str(a)]) + CultureBridges.ally_share(state, a)
		for b in targets(state, a):
			var k := _k(a, b)
			var got := 0
			if base > 0:
				var fp := flow_parts(state, a, b)
				@warning_ignore("integer_division")
				got = (base * flow_pct(state, a, b, fp) + 50) / 100
				got = CultureBridges.adjust_received(state, a, b, got)
			if got > 0:
				cum[k] = int(cum.get(k, 0)) + got
				lst[k] = got
			if not cum.has(k):
				continue
			var nt := tier_for_pct(ratio_pct(state, a, b))
			var old := int(tr.get(k, 0))
			if nt != old:
				tr[k] = nt
				_announce(state, a, b, old, nt, added)
	# 4. Revenu culturel du mois, effets des paliers, défection, victoire.
	var inc := _m(state, "inc")
	inc.clear()
	for eid in ids:
		var r := CultureLife.income_of(state, eid)
		if not r.is_empty():
			inc[str(eid)] = r
	CultureLife.monthly(state, ids, added)
	CultureBridges.monthly(state, ids, added)


static func _heritage(state: GameState, ids: Array[int]) -> void:
	var pat := _m(state, "pat")
	var hr := _m(state, "hrate")
	var hd: Dictionary = data()["heritage"]
	var seen := _m(state, "seen")
	var old_ticks := int(hd["colony_years"]) * 360
	var by_owner := {}
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if not c.is_colony() or not c.is_established() or GameState.is_npc(c.owner):
			seen.erase(str(pid))
			continue
		if not seen.has(str(pid)):
			seen[str(pid)] = state.tick
		elif state.tick - int(seen[str(pid)]) >= old_ticks:
			by_owner[c.owner] = int(by_owner.get(c.owner, 0)) + 1
	for eid in ids:
		var n := int(_m(state, "inf").get(str(eid), 0))
		if state.politics_on:
			n += Laws.enacted(state, eid).size() * int(hd["per_law"])
		if not state.relics.is_empty():
			n += Relics.owned(state, eid).size() * int(hd["per_relic"])
		n += int(by_owner.get(eid, 0)) * int(hd["per_old_colony"])
		# Merveilles : le Patrimoine reste au bâtisseur, même après une conquête (prop. 17 des merveilles).
		for pid in state.sorted_colony_ids():
			var c: Colony = state.colonies[pid]
			for bid in c.buildings:
				if Wonders.is_wonder(bid):
					var who := Wonders.builder_of(state, bid, pid)
					if (who if who >= 0 else c.owner) == eid:
						n += int(hd["per_wonder"])
		@warning_ignore("integer_division")
		n = n * maxi(0, 100 + tal(state, eid, "heritage_pct") + CultureBridges.law_pct(state, eid, "heritage_pct")) / 100
		n *= maxi(1, tal(state, eid, "heritage_mult"))
		pat[str(eid)] = int(pat.get(str(eid), int(data().get("start_heritage", 60)))) + n
		hr[str(eid)] = n
	# Peuples mineurs : un Patrimoine qui croît doucement (version simple).
	if not state.minors.is_empty():
		for mid in Minors.ids(state):
			var cur := int(pat.get(str(mid), int(data().get("start_heritage", 60))))
			pat[str(mid)] = cur + 3
			hr[str(mid)] = 3


static func target_name(state: GameState, b: int) -> String:
	if GameState.is_minor(b):
		return Minors.name_of(state, b)
	var e := state.get_empire(b)
	return e.display_name() if e != null else "?"


static func _announce(state: GameState, a: int, b: int, old: int, nt: int, added: Array[Dictionary]) -> void:
	if nt < 2 and old < 2:
		return
	var ea := state.get_empire(a)
	var who := [a] if GameState.is_minor(b) else [a, b]
	var txt := ""
	if nt > old:
		txt = "La culture de %s devient « %s » chez %s." % [ea.display_name(), tier_label(nt), target_name(state, b)]
		if nt == 5:
			txt += " Leurs enfants rêvent désormais dans une langue qui n'est pas la leur."
		elif nt == 4:
			txt += " Leurs feuilletons, leurs modes et leurs fêtes pèsent plus lourd que les nôtres."
	else:
		txt = "La culture de %s retombe à « %s » chez %s." % [ea.display_name(), tier_label(nt), target_name(state, b)]
	added.append(state.add_chronicle(txt, who))


# --- Effets lus ailleurs ------------------------------------------------------------------------

## Opinion (prop. 22) : ce que a pense de b gagne 3 par palier de b chez a à partir de Familier.
static func opinion_parts(state: GameState, a: int, b: int) -> Array:
	if state.culture.is_empty():
		return []
	var t := tier(state, b, a)
	var ef: Dictionary = data()["effects"]
	if t < int(ef["opinion_from"]):
		return []
	return [["Culture « %s » chez nous" % tier_label(t), (t - int(ef["opinion_from"]) + 1) * int(ef["opinion_per_tier"])]]


## Score (prop. 33) : le Rayonnement compte.
static func score(state: GameState, eid: int) -> int:
	if state.culture.is_empty():
		return 0
	var n := 0
	for b in living(state):
		if b != eid:
			n += tier(state, eid, b)
	@warning_ignore("integer_division")
	return n * 5 + radiance(state, eid) / int(data()["effects"]["score_div"])


## Empire éliminé ou système pris : rien à faire au niveau du cœur (les cumuls restent, comme l'histoire).
static func on_capture(state: GameState, sid: int, new_owner: int, old_owner: int, added: Array[Dictionary]) -> void:
	if state.culture.is_empty():
		return
	CultureLife.on_capture(state, sid, new_owner, old_owner, added)
