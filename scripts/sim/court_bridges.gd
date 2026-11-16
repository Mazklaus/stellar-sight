class_name CourtBridges
extends RefCounted
## La cour, troisième volet (voir Court) : faste et train de la cour, styles de cour selon le credo,
## ponts avec les autres piliers (foi, ferveur, trésorerie, crise, politique), événements de cour.


static func r_int(key: String) -> int:
	return Court.r_int(key)


static func rules() -> Dictionary:
	return Court.rules()


static func _h(state: GameState, parts: Array) -> int:
	return absi(hash([state.seed_value, "cour_ponts"] + parts))


# --- Faste -------------------------------------------------------------------------------------

static func faste(state: GameState, eid: int) -> int:
	return int(Court.entry(state, eid).get("faste", 0))


## Palier de faste atteint ({} sous le premier) : fav, influence, culture_pct, label.
static func faste_tier(state: GameState, eid: int) -> Dictionary:
	var f := faste(state, eid)
	var best := {}
	for t: Dictionary in rules()["faste_tiers"]:
		if f >= int(t["min"]):
			best = t
	return best


## Faste vers lequel la cour tend : base, train de la cour, courtisans prodigues et mécènes.
static func faste_target(state: GameState, eid: int) -> int:
	var en := Court.entry(state, eid)
	var n := r_int("faste_base")
	var tr: Dictionary = rules()["train"]
	for k in tr:
		var lvl := clampi(int((en.get("train", {}) as Dictionary).get(k, 0)), 0, 3)
		n += int(tr[k]["faste"][lvl])
	for h: Dictionary in Court.houses(state, eid):
		for m: Dictionary in h["members"]:
			n += Court.trait_sum(m, "faste")
	return clampi(n, 0, r_int("faste_max"))


## Entretien mensuel du train de la cour (énergie).
static func train_upkeep(state: GameState, eid: int) -> int:
	var en := Court.entry(state, eid)
	var n := 0
	var tr: Dictionary = rules()["train"]
	for k in tr:
		var lvl := clampi(int((en.get("train", {}) as Dictionary).get(k, 0)), 0, 3)
		n += int(tr[k]["upkeep"][lvl])
	return n


## Style de la cour selon le credo du peuple ({} sans credo connu).
static func style_def(state: GameState, eid: int) -> Dictionary:
	return (Court.data()["styles"] as Dictionary).get(Events.layer_value(state, eid, "credo"), {})


## Le style ne joue qu'à partir d'une Cour brillante (faste 50).
static func style_on(state: GameState, eid: int) -> bool:
	return faste(state, eid) >= 50 and not style_def(state, eid).is_empty()


# --- Ponts -------------------------------------------------------------------------------------

static func favor_parts(state: GameState, eid: int, h: Dictionary) -> Array:
	var out := []
	var ft := faste_tier(state, eid)
	if int(ft.get("fav", 0)) != 0:
		out.append([String(ft["label"]), int(ft["fav"])])
	var tal := Court.talent(state, eid)
	var e := state.get_empire(eid)
	if state.faith_on and Faiths.state_faith(state, eid) != "":
		var ff := int(tal.get("faith_fav", 0)) + Court.trait_sum(Court.head(h), "faith")
		if ff != 0:
			out.append(["Une foi d'État", ff])
	if int(tal.get("fervor_fav", 0)) != 0 and e != null and FactionTraits.has_fervor(e.faction()):
		var mx := maxi(1, int(e.faction()["fervor"].get("max", 100)))
		if e.fervor * 100 / mx >= 70:
			out.append(["Ferveur ardente", int(tal["fervor_fav"])])
		elif e.fervor * 100 / mx <= 20:
			out.append(["Ferveur éteinte", -int(tal["fervor_fav"])])
	if int(tal.get("dividends", 0)) != 0 and e != null:
		var en_res := int(e.resources.get("energy", 0))
		if en_res >= 1000:
			out.append(["Dividendes (trésor plein)", int(tal["dividends"])])
		elif en_res < 100:
			out.append(["Dividendes impayés (trésor vide)", -int(tal["dividends"])])
	if Crisis.active(state):
		out.append(["La galaxie brûle (crise de fin de partie)", r_int("crisis_month") * 5])
	if not state.finance.is_empty():
		out.append_array(FinanceBridges.favor_parts(state, eid, h))  # créancière, exemption, répudiation
	return out


## Effets du faste, du style et des grandes fêtes (format des technologies).
static func effects(state: GameState, eid: int) -> Dictionary:
	var out := {}
	var cp := int(faste_tier(state, eid).get("culture_pct", 0))
	if int(Court.entry(state, eid).get("fete_until", 0)) > state.tick:
		cp += r_int("fete_culture_pct")
	if cp != 0:
		out["culture_pct"] = cp
	if style_on(state, eid):
		Research._merge(out, (style_def(state, eid).get("fx", {}) as Dictionary).duplicate(true))
	return out


static func stability_parts(state: GameState, eid: int) -> Array:
	var out := []
	if style_on(state, eid):
		var st := int(style_def(state, eid).get("fx", {}).get("stability", 0))
		if st != 0:
			out.append([String(style_def(state, eid)["label"]), st])
	return out


# --- Chaque mois -------------------------------------------------------------------------------

static func monthly(state: GameState, eid: int, added: Array[Dictionary]) -> void:
	var en := Court.entry(state, eid)
	var e := state.get_empire(eid)
	# Train de la cour : l'entretien, sinon il retombe.
	var up := train_upkeep(state, eid)
	if up > 0:
		if int(e.resources.get("energy", 0)) >= up:
			e.resources["energy"] = int(e.resources["energy"]) - up
		else:
			for k in (en["train"] as Dictionary).keys():
				en["train"][k] = 0
			added.append(state.add_chronicle("Le trésor de %s ne peut plus payer le train de la cour : on remballe l'argenterie." % e.display_name(),
					Espionage.private_to(state, [eid])))
	# Faste : il tend vers sa cible.
	var old_tier := String(faste_tier(state, eid).get("label", ""))
	var old_style := style_on(state, eid)
	var f := int(en["faste"])
	var t := faste_target(state, eid)
	if f < t:
		f = mini(t, f + r_int("faste_drift"))
	elif f > t:
		f = maxi(t, f - r_int("faste_drift"))
	en["faste"] = f
	if String(faste_tier(state, eid).get("label", "")) != old_tier or style_on(state, eid) != old_style:
		Relics.touch(state)
	# Les maisons tirent leurs fiefs vers leur courant.
	if Politics.applies(state, eid) and r_int("politics_push") > 0:
		for h: Dictionary in Court.houses(state, eid):
			if not Court.serves(h):
				continue
			var ci := Politics.index_of(String(Court.voc_def(String(h["voc"])).get("current", "")))
			for sid in Court.fiefs_of(state, eid, int(h["id"])):
				Politics.push(state, sid, ci, r_int("politics_push"))
	# Événements de cour.
	if state.tick >= int(en.get("next_ev", 0)):
		en["next_ev"] = state.tick + Court._ev_gap(state, eid)
		draw_event(state, eid, added)


## Tire un événement de cour (cartes court_ev_*) avec une maison et sa rivale.
static func draw_event(state: GameState, eid: int, added: Array[Dictionary]) -> String:
	var hs := Court.houses(state, eid)
	if hs.size() < 2:
		return ""
	var seen: Dictionary = Events.meta(state, eid)["seen"]
	var pool: Array[String] = []
	for c: Dictionary in Court.data()["cards"]:
		var id := String(c["id"])
		if not id.begins_with("court_ev_"):
			continue
		if seen.has(id) and state.tick - int(seen[id]) < 1800:
			continue
		pool.append(id)
	if pool.is_empty():
		return ""
	var id2 := pool[_h(state, ["ev", eid, state.tick]) % pool.size()]
	var h: Dictionary = hs[_h(state, ["ev_h", eid, state.tick]) % hs.size()]
	var rid := -1
	var rv: Array = h.get("rivals", [])
	if not rv.is_empty():
		rid = int(rv[0])
	else:
		for o: Dictionary in hs:
			if int(o["id"]) != int(h["id"]):
				rid = int(o["id"])
				break
	Court.push_card(state, eid, id2, {"h": int(h["id"]), "r": rid}, added)
	return id2
