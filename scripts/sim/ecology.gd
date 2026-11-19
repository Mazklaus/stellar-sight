class_name Ecology
extends RefCounted
## Écologie et climat des mondes (étude du 2026-11-18, version resserrée validée : propositions 1 à 14 ;
## données : data/ecology.json).
##
## Chaque monde VIVANT (continental, océanique, glaciaire, désertique, toxique, monde-jardin) a une
## Biosphère de 0 à 100 (prop. 2). Les mondes morts (stérile, géante, astéroïdes) et les mondes faits de
## main (écuménopole, anneau, mondes de la Forge) n'en ont pas : l'industrie peut s'y installer sans
## dégâts. Chaque mois, la jauge glisse d'un point vers un équilibre affiché (prop. 3) :
##     vitalité du type + soins − (empreinte − absorption) × excess_pct %
## L'empreinte (prop. 4) additionne le poids des bâtiments et la population au-delà de ce que le monde
## nourrit sans peine ; l'absorption vaut 4 par cran de taille (Master of Orion II). Technologies
## (fx eco_footprint_pct) et doctrine (prop. 10) la modulent.
##
## Cinq paliers (prop. 5) changent la nourriture de la colonie, la stabilité du système (le pire monde
## compte) et la croissance. Mode Complète : un monde Effondré 24 mois perd un cran de climat (prop. 6,
## avis à 12 mois) ; un désert, une banquise ou un monde toxique Florissant 60 mois en gagne un (prop. 7).
## Une planète sans revendication se remet seule vers sa vitalité.
##
## État : state.ecology = {"mode", "bio": {pid: valeur}, "low": {pid: mois Effondrée},
##  "high": {pid: mois Florissante}, "warn": {pid: 1}, "doc": {eid: doctrine}, "doc_at": {eid: jour}}.
## API pour les autres piliers (Mondes vivants) : Ecology.health(state, pid) -> 0-100, ou -1 sans biosphère.
##
## Extensions (props. 15 à 30, validées le 2026-11-18) : EcologyBridges (catastrophes, centrales
## allégées, démantèlement, réfugiés, Tolérance, foi, Amphictyonie, sabotage, siège et terre brûlée,
## Monde-usine, hauts faits, événements, biosphères remarquables, opinion, décor).

const SUBS := ["bio", "low", "high", "warn", "doc", "doc_at", "cat", "factory", "sabot", "rem", "flee", "anger", "stat"]


static func data() -> Dictionary:
	return GameData.ecology()


static func rule(key: String, def := 0) -> int:
	return int(data().get("rules", {}).get(key, def))


# --- Réglage, sauvegarde -----------------------------------------------------------------------

static func mode_defs() -> Array:
	return data().get("modes", [])


static func default_mode() -> String:
	return String(data().get("default_mode", "complete"))


static func setup(state: GameState, mode_id: String) -> void:
	state.ecology = {}
	var ok := false
	for m: Dictionary in mode_defs():
		ok = ok or String(m["id"]) == mode_id
	if mode_id == "desactivee" or not ok:
		return
	state.ecology = {"mode": mode_id}
	for k in SUBS:
		state.ecology[k] = {}
	EcologyBridges.pick_remarkable(state)  # prop. 28


static func enabled(state: GameState) -> bool:
	return state != null and not state.ecology.is_empty()


## Mode Complète : basculement et reverdissement.
static func full(state: GameState) -> bool:
	return enabled(state) and String(state.ecology.get("mode", "")) == "complete"


static func mode_label(state: GameState) -> String:
	var id := String(state.ecology.get("mode", "desactivee"))
	for m: Dictionary in mode_defs():
		if String(m["id"]) == id:
			return String(m["label"])
	return "Désactivée"


static func worth_saving(state: GameState) -> bool:
	return enabled(state)


static func to_dict(state: GameState) -> Dictionary:
	return state.ecology.duplicate(true)


static func from_dict(state: GameState, d: Dictionary) -> void:
	if d.is_empty():
		state.ecology = {}
		return
	state.ecology = GameData._to_ints(d.duplicate(true))
	for k in SUBS:
		if not state.ecology.has(k):
			state.ecology[k] = {}


static func sub(state: GameState, key: String) -> Dictionary:
	return state.ecology[key]


# --- Biosphère ---------------------------------------------------------------------------------

static func type_def(planet_type: String) -> Dictionary:
	return data().get("types", {}).get(planet_type, {})


## Le type de monde porte-t-il une biosphère ?
static func living_type(planet_type: String) -> bool:
	return not type_def(planet_type).is_empty()


static func has_biosphere(state: GameState, pid: int) -> bool:
	if not enabled(state) or pid < 0:
		return false
	var p := state.galaxy.get_planet(pid)
	return p != null and living_type(p.type) and not EcologyBridges.is_factory(state, pid)


static func vitality(planet_type: String) -> int:
	return int(type_def(planet_type).get("vitality", 0))


## Vitalité d'un monde : celle de son type, plus une biosphère remarquable (prop. 28).
static func planet_vitality(state: GameState, pid: int) -> int:
	return mini(100, vitality(state.galaxy.get_planet(pid).type) + EcologyBridges.vitality_bonus(state, pid))


## Santé de la biosphère (0-100), ou -1 si le monde n'en a pas (ou si l'écologie est coupée).
static func health(state: GameState, pid: int) -> int:
	if not has_biosphere(state, pid):
		return -1
	var k := str(pid)
	var b := sub(state, "bio")
	if b.has(k):
		return int(b[k])
	return planet_vitality(state, pid)


static func _set_health(state: GameState, pid: int, v: int) -> void:
	sub(state, "bio")[str(pid)] = clampi(v, 0, 100)


static func tiers() -> Array:
	return data().get("tiers", [])


static func tier_for(v: int) -> Dictionary:
	for t: Dictionary in tiers():
		if v >= int(t["min"]):
			return t
	return tiers().back()


## Palier du monde ({} sans biosphère).
static func tier(state: GameState, pid: int) -> Dictionary:
	var v := health(state, pid)
	return {} if v < 0 else tier_for(v)


static func tier_color(t: Dictionary) -> Color:
	var c: Array = t.get("color", [0.8, 0.8, 0.8])
	return Color(float(c[0]), float(c[1]), float(c[2]))


# --- Empreinte, soins, équilibre ---------------------------------------------------------------

static func doctrine_defs() -> Array:
	return data().get("doctrines", [])


static func doctrine_def(id: String) -> Dictionary:
	for d: Dictionary in doctrine_defs():
		if String(d["id"]) == id:
			return d
	return {}


static func doctrine(state: GameState, eid: int) -> String:
	if not enabled(state):
		return ""
	var d := String(sub(state, "doc").get(str(eid), data().get("default_doctrine", "equilibre")))
	if d == "extraction" and EcologyBridges.extraction_banned(state, eid):
		return String(data().get("default_doctrine", "equilibre"))  # Convention des biosphères (prop. 21)
	return d


## Multiplicateur de l'empreinte (en %) : technologies et doctrine de l'empire.
static func footprint_pct(state: GameState, eid: int) -> int:
	if eid < 0 or GameState.is_npc(eid):
		return 100
	return maxi(0, 100 + Research.fx_int(state, eid, "eco_footprint_pct") + int(doctrine_def(doctrine(state, eid)).get("footprint_pct", 0)))


## Empreinte brute d'une planète, poste par poste : [[libellé, points]], avant le multiplicateur.
@warning_ignore("integer_division")
static func footprint_parts(state: GameState, pid: int) -> Array:
	var out: Array = []
	var c: Colony = state.colonies.get(pid)
	if c == null or not c.is_established():
		return out
	var fp: Dictionary = data().get("footprint", {})
	var counts := {}
	for b0 in c.buildings:
		var b := b0 if fp.has(b0) else GameData.building_kind(b0)  # bâtiment de peuple : celui qu'il remplace
		if fp.has(b):
			counts[b] = int(counts.get(b, 0)) + 1
	var keys := counts.keys()
	keys.sort()
	for b in keys:
		var n := int(counts[b])
		var label := String(GameData.building(b).get("label", b))
		var pts := int(fp[b]) * n
		var pp := EcologyBridges.plant_pct(state, c.owner, b)  # mégastructures énergétiques (prop. 16)
		if pp != 100:
			pts = pts * pp / 100
		label = label if n == 1 else "%s ×%d" % [label, n]
		if pp != 100:
			label += " (allégée par vos mégastructures)"
		out.append([label, pts])
	if c.is_colony():
		var p := state.galaxy.get_planet(pid)
		var over := c.population - rule("pop_free_per_size", 3) * p.size
		if over > 0:
			out.append(["Population au-delà de %d" % (rule("pop_free_per_size", 3) * p.size), over])
	out.append_array(EcologyBridges.extra_parts(state, pid))  # sabotage écologique (prop. 22)
	return out


@warning_ignore("integer_division")
static func footprint(state: GameState, pid: int) -> int:
	var raw := 0
	for part: Array in footprint_parts(state, pid):
		raw += int(part[1])
	var c: Colony = state.colonies.get(pid)
	raw = raw * EcologyBridges.world_pct(state, pid) / 100  # biosphère remarquable (prop. 28)
	return raw * (footprint_pct(state, c.owner) if c != null else 100) / 100


static func absorption(state: GameState, pid: int) -> int:
	return rule("absorb_per_size", 4) * state.galaxy.get_planet(pid).size


static func care(state: GameState, pid: int) -> int:
	var c: Colony = state.colonies.get(pid)
	if c == null or not c.is_established():
		return 0
	var cd: Dictionary = data().get("care", {})
	var out := 0
	for b in c.buildings:
		out += int(cd.get(b, 0))
	return out


## Équilibre vers lequel glisse la biosphère (0-100).
@warning_ignore("integer_division")
static func equilibrium(state: GameState, pid: int) -> int:
	var excess := maxi(0, footprint(state, pid) - absorption(state, pid))
	return clampi(planet_vitality(state, pid) + care(state, pid) - excess * rule("excess_pct", 150) / 100, 0, 100)


## Flèche de tendance : 1 monte, -1 descend, 0 stable.
static func trend(state: GameState, pid: int) -> int:
	var v := health(state, pid)
	var eq := equilibrium(state, pid)
	return 1 if eq > v else (-1 if eq < v else 0)


static func arrow(state: GameState, pid: int) -> String:
	return {1: "↑", -1: "↓", 0: "="}[trend(state, pid)]


# --- Effets des paliers ------------------------------------------------------------------------

## Production d'une colonie (appelé par Economy.colony_yields) : nourriture du palier, matériaux et
## énergie de la doctrine.
@warning_ignore("integer_division")
static func adjust_yields(state: GameState, c: Colony, gross: Dictionary) -> void:
	if not enabled(state):
		return
	var t := tier(state, c.planet_id)
	if not t.is_empty() and c.is_colony():
		var fp := int(t.get("food_pct", 0))
		if fp < 0 and EcologyBridges.tolerant(state, c.owner):
			fp = 0  # trait Tolérance (prop. 19)
		if fp != 0 and int(gross.get("food", 0)) > 0:
			gross["food"] = int(gross["food"]) * (100 + fp) / 100
	var yp := int(doctrine_def(doctrine(state, c.owner)).get("yield_pct", 0))
	if yp != 0 and not GameState.is_npc(c.owner):
		for r in ["materials", "energy"]:
			if int(gross.get(r, 0)) > 0:
				gross[r] = int(gross[r]) * (100 + yp) / 100
	EcologyBridges.adjust_yields(state, c, gross)  # catastrophe, monde-usine, biosphère remarquable


## Croissance (points de %) : Dégradée ralentit.
static func growth_pct(state: GameState, pid: int) -> int:
	var t := tier(state, pid)
	return 0 if t.is_empty() else maxi(-99, int(t.get("growth_pct", 0)))


## Effondrée : plus de croissance du tout.
static func growth_blocked(state: GameState, pid: int) -> bool:
	var t := tier(state, pid)
	return not t.is_empty() and int(t.get("growth_pct", 0)) <= -100


## Stabilité du système : le pire monde vivant du propriétaire compte (une ligne).
static func stability_parts(state: GameState, sid: int, owner: int) -> Array:
	if not enabled(state):
		return []
	var extra := EcologyBridges.stability_parts(state, sid, owner)  # monde-usine, Sacralité du vivant
	var worst := 0
	var name := ""
	var label := ""
	var best := 0
	var best_name := ""
	for pid in state.galaxy.systems[sid].planet_ids:
		var c: Colony = state.colonies.get(pid)
		if c == null or c.owner != owner or not c.is_colony() or not c.is_established():
			continue
		var t := tier(state, pid)
		if t.is_empty():
			continue
		var s := int(t.get("stab", 0))
		if s < worst:
			worst = s
			name = state.galaxy.get_planet(pid).display_name(state.galaxy)
			label = String(t["label"])
		if s > best:
			best = s
			best_name = state.galaxy.get_planet(pid).display_name(state.galaxy)
	if worst < 0:
		return [["Biosphère %s (%s)" % [label.to_lower(), name], worst]] + extra
	if best > 0:
		return [["Biosphère florissante (%s)" % best_name, best]] + extra
	return extra


# --- Le mois -----------------------------------------------------------------------------------

static func monthly(state: GameState, added: Array[Dictionary]) -> void:
	if not enabled(state):
		return
	var drift := rule("drift", 1)
	var bio := sub(state, "bio")
	# Planètes sans revendication : elles se remettent seules vers leur vitalité.
	var keys := bio.keys()
	keys.sort_custom(func(a, b) -> bool: return int(a) < int(b))
	for k in keys:
		var pid := int(k)
		if state.colonies.has(pid):
			continue
		var p := state.galaxy.get_planet(pid)
		if p == null or not living_type(p.type):
			_forget(state, pid)
			continue
		var v := int(bio[k])
		var vt := planet_vitality(state, pid)
		v = mini(vt, v + drift) if v < vt else maxi(vt, v - drift)
		if v == vt:
			_forget(state, pid)
		else:
			bio[k] = v
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if not c.is_established() or not has_biosphere(state, pid):
			continue
		var v := health(state, pid)
		var eq := equilibrium(state, pid)
		v = mini(eq, v + drift) if v < eq else maxi(eq, v - drift)
		_set_health(state, pid, v)
		EcologyBridges.colony_monthly(state, c, added)  # siège, catastrophes, réfugiés
		if full(state):
			_climate(state, c, health(state, pid), added)
	EcologyBridges.empire_monthly(state)  # Convention des biosphères


static func _forget(state: GameState, pid: int) -> void:
	var k := str(pid)
	for s in ["bio", "low", "high", "warn"]:
		sub(state, s).erase(k)


## Basculement (prop. 6) et reverdissement (prop. 7).
static func _climate(state: GameState, c: Colony, v: int, added: Array[Dictionary]) -> void:
	var pid := c.planet_id
	var k := str(pid)
	var p := state.galaxy.get_planet(pid)
	var t := tier_for(v)
	var low := sub(state, "low")
	var high := sub(state, "high")
	var shift: Dictionary = data().get("shift", {})
	var regreen: Dictionary = data().get("regreen", {})
	var e := state.get_empire(c.owner)
	var pname := p.display_name(state.galaxy)
	if String(t["id"]) == "effondree" and shift.has(p.type):
		low[k] = int(low.get(k, 0)) + 1
		if int(low[k]) >= rule("warn_months", 12) and not sub(state, "warn").has(k):
			sub(state, "warn")[k] = 1
			Announce.next(state, "eco_tipping", {"actor": c.owner, "system": p.system_id})
			added.append(state.add_chronicle("%s : le climat de %s vacille. Encore un an d'effondrement et le monde ne sera plus le même." % [
					e.short_name(), pname], Espionage.private_to(state, [c.owner], p.system_id)))
		if int(low[k]) >= rule("shift_months", 24):
			var before := p.type_label()
			_change_type(state, pid, String(shift[p.type]))
			EcologyBridges.on_shift(state, c.owner)
			low.erase(k)
			sub(state, "warn").erase(k)
			Announce.next(state, "eco_shift", {"actor": c.owner, "system": p.system_id})
			added.append(state.add_chronicle("%s : %s a basculé. Le monde %s n'est plus qu'un monde %s ; les anciens parlent de pluie comme d'une légende." % [
					e.short_name(), pname, before.to_lower(), p.type_label().to_lower()], Espionage.private_to(state, [c.owner], p.system_id)))
	else:
		low.erase(k)
		sub(state, "warn").erase(k)
	if String(t["id"]) == "florissante" and regreen.has(p.type):
		high[k] = int(high.get(k, 0)) + 1
		if int(high[k]) >= rule("regreen_months", 60):
			var before := p.type_label()
			_change_type(state, pid, String(regreen[p.type]))
			EcologyBridges.on_regreen(state, c.owner)
			high.erase(k)
			Announce.next(state, "eco_regreen", {"actor": c.owner, "system": p.system_id})
			added.append(state.add_chronicle("%s : %s a reverdi. Cinq ans de soins, et le monde %s est devenu %s. Kynes aurait souri, brièvement." % [
					e.short_name(), pname, before.to_lower(), p.type_label().to_lower()], Espionage.public_to(state, [c.owner])))
	else:
		high.erase(k)


static func _change_type(state: GameState, pid: int, target: String) -> void:
	state.override_planet(pid, {"type": target})
	var c: Colony = state.colonies.get(pid)
	if c != null:
		var e := state.get_empire(c.owner)
		if e != null:
			e.hab_cache.clear()


## Terraformation (prop. 12) : la biosphère repart à terraform_reset ; monde-jardin à 100 ;
## l'écuménopole (et tout type sans biosphère) n'en a plus.
static func on_terraform(state: GameState, pid: int) -> void:
	if not enabled(state):
		return
	var p := state.galaxy.get_planet(pid)
	_forget(state, pid)
	if living_type(p.type):
		_set_health(state, pid, 100 if p.type == "gaia" else rule("terraform_reset", 60))


## Ingénierie climatique (prop. 9) : +heal d'un coup.
static func heal(state: GameState, pid: int) -> void:
	if has_biosphere(state, pid):
		_set_health(state, pid, health(state, pid) + rule("heal", 25))


## Bâtiments de l'écologie (Réserve naturelle, Ingénierie climatique) : seulement sur un monde vivant.
static func check_build(state: GameState, _eid: int, c: Colony, _p: Planet, _bid: String) -> String:
	if not enabled(state):
		return "l'écologie n'est pas en jeu dans cette partie"
	if not has_biosphere(state, c.planet_id):
		return "seulement sur un monde vivant (ce monde n'a pas de biosphère)"
	return ""


# --- Doctrine (prop. 10) -----------------------------------------------------------------------

static func check(state: GameState, eid: int, act: String, d: Dictionary) -> String:
	if not enabled(state):
		return "l'écologie n'est pas en jeu dans cette partie"
	var e := state.get_empire(eid)
	if e == null or e.eliminated or GameState.is_npc(eid):
		return "empire inconnu"
	match act:
		"doctrine":
			var id := String(d.get("id", ""))
			if doctrine_def(id).is_empty():
				return "doctrine inconnue"
			if id == doctrine(state, eid) and sub(state, "doc").has(str(eid)):
				return "c'est déjà votre doctrine"
			if id == "extraction" and EcologyBridges.extraction_banned(state, eid):
				return "interdit par la Convention des biosphères (Amphictyonie)"
			var left := doctrine_wait(state, eid)
			if left > 0:
				return "encore %d jours avant de pouvoir en changer" % left
			return ""
		"factory":
			return EcologyBridges.check_factory(state, eid, int(d.get("pid", -1)))
		"scorch":
			return EcologyBridges.check_scorch(state, eid, int(d.get("pid", -1)))
	return "action inconnue"


static func doctrine_wait(state: GameState, eid: int) -> int:
	var at := sub(state, "doc_at")
	if not at.has(str(eid)):
		return 0
	return maxi(0, int(at[str(eid)]) + rule("doctrine_cooldown", 1800) - state.tick)


static func apply(state: GameState, eid: int, act: String, d: Dictionary) -> void:
	if check(state, eid, act, d) != "":
		return
	match act:
		"doctrine":
			var id := String(d["id"])
			sub(state, "doc")[str(eid)] = id
			sub(state, "doc_at")[str(eid)] = state.tick
			var e := state.get_empire(eid)
			state.add_chronicle("%s adopte la doctrine environnementale « %s »." % [e.display_name(), String(doctrine_def(id)["label"])], Espionage.public_to(state, [eid]))
		"factory":
			EcologyBridges.make_factory(state, eid, int(d["pid"]))
		"scorch":
			EcologyBridges.scorch(state, eid, int(d["pid"]))


# --- Affichage ---------------------------------------------------------------------------------

## Ligne courte : « Biosphère 62 (Saine) ↓ équilibre 48 ».
static func line(state: GameState, pid: int) -> String:
	var v := health(state, pid)
	if v < 0:
		return ""
	var t := tier_for(v)
	var eq := equilibrium(state, pid)
	if eq == v:
		return "Biosphère %d (%s), stable" % [v, String(t["label"])]
	return "Biosphère %d (%s) %s équilibre %d" % [v, String(t["label"]), arrow(state, pid), eq]


## Infobulle détaillée (prop. 11) : vitalité, soins, empreinte poste par poste, absorption, effets.
static func tooltip(state: GameState, pid: int) -> String:
	if not has_biosphere(state, pid):
		return ""
	var p := state.galaxy.get_planet(pid)
	var c: Colony = state.colonies.get(pid)
	var lines := PackedStringArray()
	lines.append(line(state, pid))
	lines.append("Vitalité du monde %s : +%d" % [p.type_label().to_lower(), planet_vitality(state, pid)])
	var cr := care(state, pid)
	if cr > 0:
		lines.append("Soins (réserves) : +%d" % cr)
	var parts := footprint_parts(state, pid)
	if not parts.is_empty():
		lines.append("Empreinte :")
		for part: Array in parts:
			lines.append("   %s : %d" % [String(part[0]), int(part[1])])
		if c != null and footprint_pct(state, c.owner) != 100:
			lines.append("   Technologies et doctrine : ×%d %%" % footprint_pct(state, c.owner))
	lines.append("Absorbé par le monde (taille %d) : %d" % [p.size, absorption(state, pid)])
	var excess := maxi(0, footprint(state, pid) - absorption(state, pid))
	if excess > 0:
		lines.append("Empreinte non absorbée : %d, soit −%d sur l'équilibre" % [excess, excess * rule("excess_pct", 150) / 100])
	var t := tier(state, pid)
	var fx := PackedStringArray()
	if int(t.get("food_pct", 0)) != 0:
		fx.append("%s %% nourriture" % _signed(int(t["food_pct"])))
	if int(t.get("stab", 0)) != 0:
		fx.append("%s stabilité" % _signed(int(t["stab"])))
	if int(t.get("growth_pct", 0)) <= -100:
		fx.append("croissance arrêtée")
	elif int(t.get("growth_pct", 0)) != 0:
		fx.append("%s %% croissance" % _signed(int(t["growth_pct"])))
	lines.append("Effets : " + (", ".join(fx) if not fx.is_empty() else "aucun"))
	if full(state):
		var k := str(pid)
		if sub(state, "low").has(k) and data().get("shift", {}).has(p.type):
			lines.append("Effondrée depuis %d mois : basculement à %d." % [int(sub(state, "low")[k]), rule("shift_months", 24)])
		if sub(state, "high").has(k) and data().get("regreen", {}).has(p.type):
			lines.append("Florissante depuis %d mois : reverdissement à %d." % [int(sub(state, "high")[k]), rule("regreen_months", 60)])
	lines.append_array(EcologyBridges.tooltip_lines(state, pid))
	return "\n".join(lines)


static func _signed(v: int) -> String:
	return ("+%d" % v) if v > 0 else str(v)


## Mondes vivants d'un empire, du plus malade au plus sain : [pid, ...].
static func worlds_of(state: GameState, eid: int) -> Array:
	var out: Array = []
	if not enabled(state):
		return out
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner == eid and c.is_established() and has_biosphere(state, pid):
			out.append(pid)
	out.sort_custom(func(a, b) -> bool:
		var ha := health(state, a)
		var hb := health(state, b)
		return ha < hb or (ha == hb and int(a) < int(b)))
	return out


# --- IA (prop. 13) -----------------------------------------------------------------------------

## Doctrine selon le tempérament, une fois.
static func ai(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if not enabled(state) or sub(state, "doc").has(str(e.id)):
		return
	var temper := clampi(AiLevels.aggression(e), -2, 2)
	var want := String(data().get("default_doctrine", "equilibre"))
	for d: Dictionary in doctrine_defs():
		if d.has("aggression_min") and int(d["aggression_min"]) > 0 and temper >= int(d["aggression_min"]):
			want = String(d["id"])
		elif d.has("aggression_max") and int(d["aggression_max"]) < 0 and temper <= int(d["aggression_max"]):
			want = String(d["id"])
	if check(state, e.id, "doctrine", {"id": want}) == "":
		AiPlayer._issue(ctx, SimCommands.eco_act(e.id, "doctrine", {"id": want}))


## Chantiers d'une colonie revus par l'écologie : réserve et ingénierie sur un monde qui souffre,
## industrie lourde évitée sur un monde vivant fragile quand l'empire a des mondes morts.
static func ai_filter(ctx: Dictionary, c: Colony, wishes: Array[String]) -> Array[String]:
	var state: GameState = ctx["state"]
	if not enabled(state) or not has_biosphere(state, c.planet_id) or not c.is_colony():
		return wishes
	var cfg: Dictionary = data().get("ai", {})
	var v := health(state, c.planet_id)
	var eq := equilibrium(state, c.planet_id)
	var out: Array[String] = []
	if mini(v, eq) < int(cfg.get("reserve_below", 45)) and not c.buildings.has("reserve_naturelle"):
		out.append("reserve_naturelle")
	if v < int(cfg.get("heal_below", 30)):
		out.append("ingenierie_climatique")
	var spare := eq < int(cfg.get("spare_below", 60)) and _has_dead_world(ctx)
	var heavy: Array = cfg.get("heavy", [])
	for w in wishes:
		if spare and heavy.has(w):
			continue
		out.append(w)
	return out


static func _has_dead_world(ctx: Dictionary) -> bool:
	if ctx.has("eco_dead"):
		return bool(ctx["eco_dead"])
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var found := false
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner == e.id and c.is_colony() and c.is_established() and not has_biosphere(state, pid):
			found = true
			break
	ctx["eco_dead"] = found
	return found
