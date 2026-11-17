class_name Psionics
extends RefCounted
## Pouvoirs psioniques (étude du 2026-11-17, 42 propositions validées ; données : data/psionics.json).
##
## Deux étages (prop. 1) : la technologie Théorie psionique rend Latentes les espèces vivantes de
## l'empire ; la voie d'élévation « L'Éveil » (5e voie du Génome, exclusive) rend l'espèce fondatrice
## Éveillée, puis Transcendante au couronnement. Échelle (prop. 2) : Sourde 0, Latente 1, Éveillée 2,
## Transcendante 3. Les synthétiques sont sourds et immunisés, les ruches plafonnent à Latente, les
## énergétiques naissent Latents (prop. 3). Une espèce cybernétique plafonne à Latente (prop. 4).
##
## Les sensitifs donnent la RÉSONANCE (prop. 5), réserve d'empire plafonnée qui n'est pas un bien :
## elle ne se commerce pas et ne figure pas dans Empire.resources. Les pouvoirs (prop. 16-23,
## catalogue ouvert) la dépensent ; chacun risque une FÊLURE (prop. 8).
##
## Formes de psionisme (consigne du 2026-11-17) : catalogue ouvert « forms » ; le Songe est la
## première. Un pouvoir appartient à une forme ; un empire n'use que des pouvoirs de la sienne.
##
## Réglage « Pouvoirs psioniques » : Complet, Discret (sans Songe, pactes ni crise), Désactivé
## (state.psionics vide). Sans l'option (tests, bancs) : désactivé.
##
## État : state.psionics = {"mode", "res": {"eid": Résonance}, "awake": {"eid": jour de l'Éveil},
##  "crown": {"eid": jour du couronnement}, "cd": {"eid:pouvoir": jour où il revient},
##  "fx": {"eid": [effet actif {"id", "until", "target"?, "sys"?, "v"?}]}, "st": {"eid": {statistiques}}}.
## Tout est déterministe : entiers, tirages par hachage de la graine, ordres par SimCommands.

const SUBS := ["res", "awake", "crown", "cd", "fx", "st", "open", "pact", "offer", "reform", "haunted"]

static var _talent_cache := {}


static func data() -> Dictionary:
	return GameData.psionics()


static func cfg(section: String) -> Dictionary:
	var v: Variant = data().get(section, {})
	return v if v is Dictionary else {}


static func c_int(section: String, key: String, def := 0) -> int:
	return int(cfg(section).get(key, def))


static func mode_defs() -> Array:
	return data().get("modes", [])


static func default_mode() -> String:
	return String(data().get("default_mode", "complet"))


static func mode(state: GameState) -> String:
	return String(state.psionics.get("mode", "desactive"))


static func enabled(state: GameState) -> bool:
	return state != null and not state.psionics.is_empty()


## Mode Complet : le Songe, les pactes et la crise sont en jeu.
static func full(state: GameState) -> bool:
	return enabled(state) and mode(state) == "complet"


static func applies(state: GameState, eid: int) -> bool:
	var e := state.get_empire(eid) if enabled(state) and eid >= 0 else null
	return e != null and not e.is_npc() and not e.eliminated


static func mode_label(state: GameState) -> String:
	for m: Dictionary in mode_defs():
		if String(m["id"]) == mode(state):
			return String(m["label"])
	return "Désactivé"


# --- Réglage, sauvegarde -----------------------------------------------------------------------

static func setup(state: GameState, mode_id: String) -> void:
	state.psionics = {}
	var ok := false
	for m: Dictionary in mode_defs():
		if String(m["id"]) == mode_id:
			ok = true
	if not ok or mode_id == "desactive":
		return
	state.psionics = {"mode": mode_id}
	for k in SUBS:
		state.psionics[k] = {}


static func worth_saving(state: GameState) -> bool:
	return enabled(state)


static func to_dict(state: GameState) -> Dictionary:
	return state.psionics.duplicate(true)


static func from_dict(state: GameState, d: Dictionary) -> void:
	if d.is_empty():
		state.psionics = {}
		return
	state.psionics = GameData._to_ints(d.duplicate(true))
	for k in SUBS:
		if not state.psionics.has(k):
			state.psionics[k] = {}


static func sub(state: GameState, k: String) -> Dictionary:
	if state.psionics.is_empty():
		return {}  # pilier désactivé : ne jamais le rallumer en écrivant
	if not state.psionics.has(k):
		state.psionics[k] = {}
	return state.psionics[k]


static func _h(state: GameState, parts: Array) -> int:
	return absi(hash([state.seed_value, "psi"] + parts))


static func _stat(state: GameState, eid: int, k: String, n: int) -> void:
	var st := sub(state, "st")
	if st.is_empty() and state.psionics.is_empty():
		return
	var d: Dictionary = st.get(str(eid), {})
	d[k] = int(d.get(k, 0)) + n
	st[str(eid)] = d


static func stat(state: GameState, eid: int, k: String) -> int:
	return int((sub(state, "st").get(str(eid), {}) as Dictionary).get(k, 0))


# --- Formes, talents ---------------------------------------------------------------------------

static func form_defs() -> Array:
	return cfg("forms").get("list", [])


static func form_def(id: String) -> Dictionary:
	for f: Dictionary in form_defs():
		if String(f["id"]) == id:
			return f
	return {}


## Talent psionique du peuple (catalogue « talents » par couche, lot 3) : champs fusionnés.
static func talent(state: GameState, eid: int) -> Dictionary:
	var e := state.get_empire(eid)
	if e == null:
		return {}
	var f := e.faction()
	var sp := FactionTraits.species(f)
	var key := "%s|%s|%s|%s|%s|%s" % [e.faction_id, f.get("registre", ""), sp.get("archetype", ""), sp.get("gouvernement", ""), sp.get("credo", ""), ",".join(PackedStringArray(sp.get("traits", [])))]
	if _talent_cache.has(key):
		return _talent_cache[key]
	var out := {}
	var tl := cfg("talents")
	var layers := {"registre": String(f.get("registre", "")), "archetype": String(sp.get("archetype", "")),
			"gouvernement": String(sp.get("gouvernement", "")), "credo": String(sp.get("credo", ""))}
	for layer in ["registre", "archetype", "gouvernement", "credo"]:
		var t: Variant = (tl.get(layer, {}) as Dictionary).get(layers[layer], null)
		if t is Dictionary:
			for k in t:
				if k == "label" or k == "text":
					var labels: Array = out.get("_labels", [])
					if k == "label":
						labels.append([String(t["label"]), String(t.get("text", ""))])
					out["_labels"] = labels
				elif t[k] is int or t[k] is float:
					out[k] = int(out.get(k, 0)) + int(t[k])
				else:
					out[k] = t[k]
	for tid in sp.get("traits", []):
		var t: Variant = (tl.get("traits", {}) as Dictionary).get(String(tid), null)
		if t is Dictionary:
			var labels: Array = out.get("_labels", [])
			labels.append([String(t.get("label", tid)), String(t.get("text", ""))])
			out["_labels"] = labels
			for k in t:
				if k != "label" and k != "text":
					out[k] = (int(out.get(k, 0)) + int(t[k])) if (t[k] is int or t[k] is float) else t[k]
	_talent_cache[key] = out
	return out


static func talent_labels(state: GameState, eid: int) -> Array:
	return talent(state, eid).get("_labels", [])


## Forme de psionisme d'un empire (talent, sinon forme par défaut).
static func form(state: GameState, eid: int) -> String:
	var t := String(talent(state, eid).get("form", ""))
	return t if t != "" and not form_def(t).is_empty() else String(cfg("forms").get("default", "songe"))


static func form_label(state: GameState, eid: int) -> String:
	return String(form_def(form(state, eid)).get("label", "le Songe"))


# --- Échelle des espèces -----------------------------------------------------------------------

static func level_label(n: int) -> String:
	for l: Dictionary in data().get("levels", []):
		if int(l["id"]) == n:
			return String(l["label"])
	return "?"


static func tech_for(power: String) -> String:
	var t := cfg("techs")
	for k in t:
		if String(t[k]) == power:
			return String(k)
	return ""


static func has_tech(state: GameState, eid: int, power: String) -> bool:
	var e := state.get_empire(eid)
	var t := tech_for(power)
	return e != null and t != "" and e.techs.has(t)


static func awake(state: GameState, eid: int) -> bool:
	return sub(state, "awake").has(str(eid))


static func crowned(state: GameState, eid: int) -> bool:
	return sub(state, "crown").has(str(eid))


static func arch_def(f: Dictionary) -> Dictionary:
	var v: Variant = cfg("archetypes").get(String(FactionTraits.species(f).get("archetype", "humanoide")), {})
	return v if v is Dictionary else {}


## Niveau psionique d'une espèce chez un empire (0-3).
static func level(state: GameState, eid: int, fid: String) -> int:
	if not applies(state, eid):
		return 0
	var e := state.get_empire(eid)
	var f := Genetics.fiche(state, eid, fid)
	var ad := arch_def(f)
	var mx := int(ad.get("max", 3))
	if mx <= 0 or bool(f.get("synthetic", false)) or bool(f.get("psi_null", false)):
		return 0
	var lv := int(ad.get("innate", 0))
	if has_tech(state, eid, "latent"):
		lv = maxi(lv, 1)
	if lv > 0 and awake(state, eid) and Genetics.root(fid) == e.faction_id:
		lv = 3 if crowned(state, eid) else 2
	lv = maxi(lv, int(talent(state, eid).get("innate", 0)))
	if bool(f.get("cyber", false)):
		mx = mini(mx, 1)
	return mini(lv, mx)


static func founder_level(state: GameState, eid: int) -> int:
	var e := state.get_empire(eid)
	return 0 if e == null else level(state, eid, e.faction_id)


## Niveau le plus haut parmi les espèces qui vivent chez l'empire.
static func best_level(state: GameState, eid: int) -> int:
	var best := 0
	if not applies(state, eid):
		return 0
	for fid in Genetics.species_of(state, eid):
		best = maxi(best, level(state, eid, fid))
	return best


## L'espèce fondatrice est-elle insensible aux pouvoirs mentaux (synthétiques) ?
static func immune(state: GameState, eid: int) -> bool:
	var e := state.get_empire(eid)
	if e == null:
		return false
	var f := e.faction()
	return bool(arch_def(f).get("immune", false)) or bool(f.get("synthetic", false)) or bool(f.get("psi_null", false))


# --- Résonance ---------------------------------------------------------------------------------

static func colleges(state: GameState, eid: int) -> int:
	var b := String(cfg("college").get("building", "college_sensitifs"))
	var n := 0
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner == eid and c.buildings.has(b):
			n += 1
	return n


static func screens_built(state: GameState, eid: int) -> int:
	var b := String(cfg("screens").get("building", "ecran_psychique"))
	var n := 0
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner == eid and c.buildings.has(b):
			n += 1
	return n


static func resonance(state: GameState, eid: int) -> int:
	return int(sub(state, "res").get(str(eid), 0))


static func add_resonance(state: GameState, eid: int, n: int) -> void:
	if not applies(state, eid):
		return
	sub(state, "res")[str(eid)] = clampi(resonance(state, eid) + n, 0, cap(state, eid))


static func cap(state: GameState, eid: int) -> int:
	var r := cfg("resonance")
	var cols := 0
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner == eid and c.is_colony() and c.is_established():
			cols += 1
	return int(r.get("cap_base", 100)) + int(r.get("cap_colony", 10)) * cols + int(r.get("cap_college", 25)) * colleges(state, eid) \
			+ int(talent(state, eid).get("cap", 0))


## Somme d'un champ des lois psioniques adoptées (data « laws »).
static func law_fx(state: GameState, eid: int, key: String) -> int:
	var n := 0
	var ld := cfg("laws")
	for id in ld:
		if id.begins_with("_"):
			continue
		if Laws.is_enacted(state, eid, String(id)):
			var v: Variant = (ld[id] as Dictionary).get(key, 0)
			n += 1 if v is bool and v else (int(v) if (v is int or v is float) else 0)
	return n


## Détail du gain mensuel : [[libellé, valeur]].
@warning_ignore("integer_division")
static func gain_parts(state: GameState, eid: int) -> Array:
	var out := []
	if not applies(state, eid):
		return out
	var per: Array = cfg("resonance").get("per_pop", [0, 5, 12, 20])
	var raw := 0
	for fid in Genetics.species_of(state, eid):
		var lv := level(state, eid, fid)
		if lv <= 0:
			continue
		var n := Genetics.pop_of(state, eid, fid) * int(per[mini(lv, per.size() - 1)]) / 10
		if n > 0:
			out.append(["%s (%s)" % [Genetics.label(state, eid, fid), level_label(lv)], n])
			raw += n
	var col := colleges(state, eid) * c_int("resonance", "college", 4)
	if col > 0 and best_level(state, eid) > 0:
		out.append(["Collèges des sensitifs", col])
		raw += col
	var pct := law_fx(state, eid, "resonance_pct") + int(talent(state, eid).get("res_pct", 0))
	if pct != 0 and raw > 0:
		out.append(["Lois et talents (%+d %%)" % pct, raw * pct / 100])
	return out


static func monthly_gain(state: GameState, eid: int) -> int:
	var n := 0
	for p in gain_parts(state, eid):
		n += int(p[1])
	return maxi(0, n)


# --- Voie L'Éveil ------------------------------------------------------------------------------

static func path_def() -> Dictionary:
	return cfg("path")


static func check_path(state: GameState, eid: int) -> String:
	if not applies(state, eid):
		return "les pouvoirs psioniques ne sont pas en jeu"
	var e := state.get_empire(eid)
	if awake(state, eid):
		return "votre espèce est déjà éveillée"
	if e.gene_path != "":
		return "votre empire s'est déjà voué à une autre voie"
	for t in path_def().get("techs", []):
		if not e.techs.has(String(t)):
			return "il faut la technologie %s" % Research.tech(String(t)).get("label", t)
	var f := e.faction()
	if int(arch_def(f).get("max", 3)) < 2:
		return "votre espèce ne peut pas s'éveiller (%s)" % ("sourde au Songe" if int(arch_def(f).get("max", 3)) <= 0 else "un seul esprit pour toute la ruche")
	if bool(f.get("cyber", false)):
		return "une espèce cybernétique n'entend le Songe qu'à moitié"
	if Genetics.enabled(state) and Genetics.sub(state, "renounce").has(str(eid)):
		return "un serment renié ne se reprend pas"
	return ""


static func awaken(state: GameState, eid: int, added: Array[Dictionary] = []) -> void:
	var e := state.get_empire(eid)
	sub(state, "awake")[str(eid)] = state.tick
	if Genetics.applies(state, eid):
		e.gene_path = String(path_def().get("id", "eveil"))
		e.genome_rev += 1
	_stat(state, eid, "awake", 1)
	added.append(state.add_chronicle("%s s'éveille : %s entend %s. « Il a toujours parlé, disent les anciens. Nous avions simplement les oreilles bouchées. »" % [
			e.display_name(), Genetics.label(state, eid, e.faction_id), form_label(state, eid).to_lower()], Espionage.private_to(state, [eid])))


## Couronnement : Transcendance de l'espèce fondatrice.
static func crown_ready(state: GameState, eid: int) -> bool:
	if not awake(state, eid) or crowned(state, eid):
		return false
	var e := state.get_empire(eid)
	var cd := path_def().get("crown", {}) as Dictionary
	for t in cd.get("techs", []):
		if not e.techs.has(String(t)):
			return false
	return state.tick - int(sub(state, "awake")[str(eid)]) >= int(cd.get("years", 10)) * Heroes.DAYS_PER_YEAR


# --- Héros sensitifs ---------------------------------------------------------------------------

static func hero_species(state: GameState, h: Dictionary) -> String:
	var sp := String(h.get("sp", ""))
	return sp if sp != "" else state.get_empire(int(h["owner"])).faction_id


## Puissance psionique d'un héros (0-3).
static func hero_power(state: GameState, h: Dictionary) -> int:
	var owner := int(h.get("owner", -1))
	if h.is_empty() or not applies(state, owner):
		return 0
	if int(h.get("psi", 0)) >= 3:
		return 3  # l'Élu (lot 2)
	var lv := level(state, owner, hero_species(state, h))
	if lv <= 0 or bool(arch_def(Genetics.fiche(state, owner, hero_species(state, h))).get("collective", false)):
		return 0
	var hd := cfg("heroes")
	var base := 1 if (h.get("traits", []) as Array).has(String(hd.get("trait", "psionique"))) or lv >= 2 else 0
	if base == 0:
		return 0
	if int(h.get("lvl", 1)) >= int(hd.get("level_up", 4)) or Heroes.age(state, h) >= int(hd.get("age_up", 60)) or lv >= 3:
		base += 1
	return mini(base, int(hd.get("max_plain", 2)))


## Héros actif de la classe d'un pouvoir (le plus puissant), {} sinon.
static func power_hero(state: GameState, eid: int, power: String) -> Dictionary:
	var cls := String(power_def(power).get("hero", ""))
	if cls == "":
		return {}
	var best := {}
	var bp := 0
	for id in Heroes.ids_of(state, eid):
		var h: Dictionary = state.heroes[id]
		if String(h["cls"]) != cls or not Heroes.active(state, h):
			continue
		var p := hero_power(state, h)
		if p > bp:
			bp = p
			best = h
	return best


# --- Pouvoirs ----------------------------------------------------------------------------------

static func power_defs() -> Array:
	return data().get("powers", [])


static func power_def(id: String) -> Dictionary:
	for p: Dictionary in power_defs():
		if String(p["id"]) == id:
			return p
	return {}


## Pouvoirs de la forme d'un empire.
static func powers_of(state: GameState, eid: int) -> Array:
	var out := []
	var fm := form(state, eid)
	for p: Dictionary in power_defs():
		if String(p.get("form", "songe")) == fm and (not bool(p.get("dream", false)) or full(state)):
			out.append(p)
	return out


@warning_ignore("integer_division")
static func power_cost(state: GameState, eid: int, power: String) -> int:
	var pd := power_def(power)
	var c := int(pd.get("cost", 0))
	var h := power_hero(state, eid, power)
	var pct := int(talent(state, eid).get("power_cost_pct", 0))
	if not h.is_empty():
		pct += hero_power(state, h) * c_int("heroes", "cost_pct", -10)
	return maxi(1, c * (100 + pct) / 100)


static func cooldown_until(state: GameState, eid: int, power: String) -> int:
	return int(sub(state, "cd").get("%d:%s" % [eid, power], 0))


static func check_power(state: GameState, eid: int, power: String, target: int) -> String:
	if not applies(state, eid):
		return "les pouvoirs psioniques ne sont pas en jeu"
	var pd := power_def(power)
	if pd.is_empty():
		return "pouvoir inconnu : %s" % power
	if String(pd.get("form", "songe")) != form(state, eid):
		return "ce pouvoir n'appartient pas à votre forme de psionisme"
	if bool(pd.get("dream", false)) and not full(state):
		return "le Songe n'est pas en jeu (réglage Discret)"
	var e := state.get_empire(eid)
	var t := String(pd.get("tech", ""))
	if t != "" and not e.techs.has(t):
		return "il faut la technologie %s" % Research.tech(t).get("label", t)
	if best_level(state, eid) <= 0:
		return "aucune de vos espèces n'entend %s" % form_label(state, eid).to_lower()
	if law_fx(state, eid, "no_powers") > 0:
		return "la Persécution des sensitifs interdit tout pouvoir"
	if state.tick < cooldown_until(state, eid, power):
		return "le pouvoir revient le %s" % GameCalendar.date_string(cooldown_until(state, eid, power))
	if resonance(state, eid) < power_cost(state, eid, power):
		return "Résonance insuffisante (%d / %d)" % [resonance(state, eid), power_cost(state, eid, power)]
	match String(pd.get("target", "self")):
		"empire":
			var b := state.get_empire(target)
			if b == null or target == eid or b.eliminated:
				return "il faut viser un autre empire"
			if not e.contacts.has(target):
				return "il faut avoir rencontré cet empire"
		"system":
			if target < 0 or target >= state.galaxy.systems.size() or state.system_owner(target) != eid:
				return "il faut viser un de vos systèmes"
	return PsionicsDream.check_power(state, eid, power, target)


## Chance (en %) qu'un pouvoir visé échoue contre une cible (écrans, immunité).
static func screen_pct(state: GameState, target: int) -> int:
	if target < 0 or state.get_empire(target) == null:
		return 0
	if immune(state, target):
		return 100
	var s := cfg("screens")
	var n := 0
	if state.get_empire(target).techs.has(tech_for("screens")):
		n = int(s.get("tech", 30)) + int(s.get("per_building", 10)) * screens_built(state, target)
	n += int(talent(state, target).get("screen", 0))
	return clampi(n, 0, int(s.get("max", 90)) if n < 100 else 100)


## Chance (en %) d'une fêlure pour un pouvoir : [chance, détail].
@warning_ignore("integer_division")
static func felure_chance(state: GameState, eid: int, power: String) -> Array:
	var base := int(power_def(power).get("felure", 0))
	var parts := []
	var pct := 0
	var l := law_fx(state, eid, "felure_pct")
	if l != 0:
		parts.append(["Loi", l])
		pct += l
	if awake(state, eid):
		var a := int(path_def().get("felure_pct", -25))
		parts.append(["L'Éveil", a])
		pct += a
	var col := maxi(c_int("felures", "college_min_pct", -30), colleges(state, eid) * c_int("felures", "college_pct", -5))
	if col != 0:
		parts.append(["Collèges", col])
		pct += col
	var h := power_hero(state, eid, power)
	if not h.is_empty():
		var hp := hero_power(state, h) * c_int("felures", "hero_pct", -10)
		parts.append(["%s (sensitif)" % h["name"], hp])
		pct += hp
	var tp := int(talent(state, eid).get("felure_pct", 0))
	if tp != 0:
		parts.append(["Talent", tp])
		pct += tp
	return [maxi(0, base * maxi(0, 100 + pct) / 100), parts]


static func use_power(state: GameState, eid: int, power: String, target: int, added: Array[Dictionary]) -> void:
	var pd := power_def(power)
	var e := state.get_empire(eid)
	add_resonance(state, eid, -power_cost(state, eid, power))
	sub(state, "cd")["%d:%s" % [eid, power]] = state.tick + int(pd.get("cooldown", 90))
	_stat(state, eid, "powers", 1)
	var h := power_hero(state, eid, power)
	if not h.is_empty():
		Heroes.gain_xp(state, h, 20)
	var screened := bool(pd.get("screened", false)) and target >= 0 and _h(state, ["scr", eid, power, state.tick]) % 100 < screen_pct(state, target)
	if screened:
		added.append(state.add_chronicle("%s tend l'esprit vers %s et ne rencontre qu'un mur de bruit blanc. (%s échoue contre les écrans.)" % [
				e.display_name(), state.get_empire(target).display_name(), pd["label"]], Espionage.private_to(state, [eid])))
	else:
		_effect(state, eid, power, target, added)
	var fc: int = felure_chance(state, eid, power)[0]
	if fc > 0 and _h(state, ["fel", eid, power, state.tick]) % 100 < fc:
		felure(state, eid, power, added)


static func _effect(state: GameState, eid: int, power: String, target: int, added: Array[Dictionary]) -> void:
	var pd := power_def(power)
	var e := state.get_empire(eid)
	var until := state.tick + int(pd.get("days", 0))
	match power:
		"lecture":
			var b := state.get_empire(target)
			e.dossiers[target] = Espionage._report(state, eid, target, (Espionage.data()["tiers"] as Array).size())
			_add_fx(state, eid, {"id": "lecture", "until": until, "target": target})
			added.append(state.add_chronicle("Les sensitifs de %s lisent dans les esprits de %s : le dossier complet est sur la table, avec les arrière-pensées en annexe." % [
					e.display_name(), b.display_name()], Espionage.private_to(state, [eid])))
		"prescience":
			_add_fx(state, eid, {"id": "prescience", "until": until})
			added.append(state.add_chronicle("%s voit venir : pendant six mois, aucune flotte ne prendra la route vers ses mondes sans qu'on le sache." % e.display_name(),
					Espionage.private_to(state, [eid])))
		"apaisement":
			_add_fx(state, eid, {"id": "apaisement", "until": until, "sys": target, "v": int(pd.get("stability", 10))})
			added.append(state.add_chronicle("Sur %s, une douceur inexplicable gagne les foules ; les émeutiers rentrent chez eux faire la sieste." % state.galaxy.systems[target].system_name,
					Espionage.private_to(state, [eid])))
		_:
			PsionicsDream.effect(state, eid, power, target, added)


static func _add_fx(state: GameState, eid: int, fx: Dictionary) -> void:
	var fxs := sub(state, "fx")
	var l: Array = fxs.get(str(eid), [])
	l.append(fx)
	fxs[str(eid)] = l


static func fx_list(state: GameState, eid: int) -> Array:
	return sub(state, "fx").get(str(eid), [])


## Effet actif (le premier de cet id, ou visant target si target >= 0), {} sinon.
static func fx_active(state: GameState, eid: int, id: String, target := -1) -> Dictionary:
	for fx: Dictionary in fx_list(state, eid):
		if String(fx["id"]) == id and int(fx["until"]) > state.tick and (target < 0 or int(fx.get("target", fx.get("sys", -1))) == target):
			return fx
	return {}


# --- Fêlures -----------------------------------------------------------------------------------

static func felure_table(state: GameState) -> Array:
	var out: Array = (cfg("felures").get("table", []) as Array).duplicate()
	if full(state):
		out.append_array(cfg("felures").get("grave", []))
	return out


static func felure(state: GameState, eid: int, power: String, added: Array[Dictionary]) -> void:
	var table := felure_table(state)
	var total := 0
	for f: Dictionary in table:
		total += int(f.get("weight", 1))
	if total <= 0:
		return
	var r := _h(state, ["felt", eid, power, state.tick]) % total
	var pick: Dictionary = table[0]
	for f: Dictionary in table:
		r -= int(f.get("weight", 1))
		if r < 0:
			pick = f
			break
	apply_felure(state, eid, pick, added)


static func apply_felure(state: GameState, eid: int, f: Dictionary, added: Array[Dictionary]) -> void:
	var e := state.get_empire(eid)
	_stat(state, eid, "felures", 1)
	var until := state.tick + int(f.get("days", 180))
	if f.has("empire_stability"):
		_add_fx(state, eid, {"id": "f_empire", "until": until, "v": int(f["empire_stability"]), "label": String(f["label"])})
	if f.has("resonance_loss_pct"):
		@warning_ignore("integer_division")
		add_resonance(state, eid, -resonance(state, eid) * int(f["resonance_loss_pct"]) / 100)
	if f.has("system_stability"):
		var best := -1
		var best_pop := -1
		for pid in state.sorted_colony_ids():
			var c: Colony = state.colonies[pid]
			if c.owner == eid and c.is_colony() and c.population > best_pop:
				best_pop = c.population
				best = state.galaxy.get_planet(pid).system_id
		if best >= 0:
			_add_fx(state, eid, {"id": "f_system", "until": until, "sys": best, "v": int(f["system_stability"]), "label": String(f["label"])})
	PsionicsDream.felure(state, eid, f, added)
	added.append(state.add_chronicle("Fêlure chez %s : %s. %s" % [e.display_name(), String(f["label"]).to_lower(), String(f.get("text", ""))], Espionage.private_to(state, [eid])))


# --- Effets lus ailleurs -----------------------------------------------------------------------

static func empire_stability_parts(state: GameState, eid: int) -> Array:
	var out := []
	if not applies(state, eid):
		return out
	for fx: Dictionary in fx_list(state, eid):
		if String(fx["id"]) == "f_empire" and int(fx["until"]) > state.tick:
			out.append(["Fêlure : %s" % String(fx.get("label", "")), int(fx.get("v", 0))])
	return out


static func system_stability_parts(state: GameState, sid: int, owner: int) -> Array:
	var out := []
	if not applies(state, owner):
		return out
	for fx: Dictionary in fx_list(state, owner):
		if int(fx["until"]) <= state.tick or int(fx.get("sys", -1)) != sid:
			continue
		match String(fx["id"]):
			"apaisement":
				out.append(["Apaisement psionique", int(fx.get("v", 0))])
			"f_system":
				out.append(["Fêlure : %s" % String(fx.get("label", "")), int(fx.get("v", 0))])
	var b := String(cfg("college").get("building", "college_sensitifs"))
	var n := 0
	for pid in state.galaxy.systems[sid].planet_ids:
		var c: Colony = state.colonies.get(pid)
		if c != null and c.owner == owner and c.buildings.has(b):
			n += 1
	if n > 0:
		out.append(["Collège des sensitifs", n * c_int("college", "stability", 1)])
	return out


## Préscience : viewer voit-il cette flotte étrangère qui vient vers lui ?
static func foresees(state: GameState, viewer: int, fleet: Fleet) -> bool:
	if viewer < 0 or state.psionics.is_empty() or fleet.owner == viewer or not fleet.is_moving():
		return false
	if fx_active(state, viewer, "prescience").is_empty():
		return false
	return state.system_owner(fleet.destination()) == viewer


## Empires dont la Préscience est active (présage des crises).
static func crisis_seers(state: GameState) -> Array[int]:
	var out: Array[int] = []
	if state.psionics.is_empty():
		return out
	for e in state.empires:
		if not fx_active(state, e.id, "prescience").is_empty():
			out.append(e.id)
	return out


static func presage_days(state: GameState, seers: Array[int]) -> int:
	for s in crisis_seers(state):
		if seers.has(s):
			return int(power_def("prescience").get("presage_days", 120))
	return 0


## Réussite en plus (points de %) des opérations de a contre b (Lecture des esprits).
static func op_bonus(state: GameState, a: int, b: int) -> int:
	if state.psionics.is_empty():
		return 0
	var fx := fx_active(state, a, "lecture", b)
	return 0 if fx.is_empty() else int(power_def("lecture").get("op_bonus", 10))


## Bâtiment psionique : vérification (economy.check_special).
static func check_build(state: GameState, eid: int, c: Colony, building_id: String) -> String:
	if not applies(state, eid):
		return "les pouvoirs psioniques ne sont pas en jeu dans cette partie"
	if building_id == String(cfg("college").get("building", "college_sensitifs")):
		if not c.is_colony():
			return "seulement sur une colonie"
		var ok := false
		var cnt := Peoples.counts(state, c) if not c.species.is_empty() else {state.get_empire(eid).faction_id: c.population}
		for fid in cnt:
			if int(cnt[fid]) > 0 and level(state, eid, String(fid)) > 0:
				ok = true
		if not ok:
			return "aucune espèce de cette colonie n'entend %s" % form_label(state, eid).to_lower()
		if law_fx(state, eid, "no_powers") > 0:
			return "la Persécution des sensitifs interdit les Collèges"
	return ""


# --- Commandes ---------------------------------------------------------------------------------

static func check(state: GameState, eid: int, act: String, d: Dictionary) -> String:
	if not applies(state, eid):
		return "les pouvoirs psioniques ne sont pas en jeu"
	match act:
		"path":
			if Genetics.applies(state, eid):
				return Genetics.check_path(state, eid, String(path_def().get("id", "eveil")))
			return check_path(state, eid)
		"power":
			return check_power(state, eid, String(d.get("power", "")), int(d.get("target", -1)))
	return PsionicsDream.check(state, eid, act, d)


static func apply(state: GameState, eid: int, act: String, d: Dictionary) -> Array[Dictionary]:
	var added: Array[Dictionary] = []
	match act:
		"path":
			if Genetics.applies(state, eid):
				Genetics.choose_path(state, eid, String(path_def().get("id", "eveil")), added)
			else:
				awaken(state, eid, added)
		"power":
			use_power(state, eid, String(d["power"]), int(d.get("target", -1)), added)
		_:
			PsionicsDream.apply(state, eid, act, d, added)
	return added


## Bilan mensuel : Résonance, couronnement, effets expirés, sensitifs qui se révèlent.
static func monthly(state: GameState, added: Array[Dictionary]) -> void:
	if not enabled(state):
		return
	@warning_ignore("integer_division")
	var month := state.tick / int(GameData.rules()["month_days"])
	for e in state.empires:
		if not applies(state, e.id):
			continue
		add_resonance(state, e.id, monthly_gain(state, e.id))
		if crown_ready(state, e.id):
			sub(state, "crown")[str(e.id)] = state.tick
			added.append(state.add_chronicle("%s transcende : son peuple pense désormais à moitié dans %s. On le croise dans les rêves des autres, poli mais insistant." % [
					e.display_name(), form_label(state, e.id).to_lower()], Espionage.public_to(state, [e.id])))
		var fxs := sub(state, "fx")
		if fxs.has(str(e.id)):
			var keep := []
			for fx: Dictionary in fxs[str(e.id)]:
				if int(fx["until"]) > state.tick:
					keep.append(fx)
				elif fx.has("fx"):
					state.relic_rev += 1  # bienfait ou malédiction du Songe expiré : effets à recalculer
			fxs[str(e.id)] = keep
		if posmod(month, 12) == posmod(e.id, 12):
			_reveal_sensitives(state, e, added)
	PsionicsDream.monthly(state, added)


## Une fois par an : un héros d'une espèce Latente peut se révéler sensitif.
static func _reveal_sensitives(state: GameState, e: Empire, added: Array[Dictionary]) -> void:
	var tr := String(cfg("heroes").get("trait", "psionique"))
	var pct := c_int("heroes", "latent_pct", 8) + int(talent(state, e.id).get("hero_pct", 0))
	for id in Heroes.ids_of(state, e.id):
		var h: Dictionary = state.heroes[id]
		if (h["traits"] as Array).has(tr) or Heroes.is_prisoner(h):
			continue
		var fid := hero_species(state, h)
		if level(state, e.id, fid) != 1 or bool(arch_def(Genetics.fiche(state, e.id, fid)).get("collective", false)):
			continue
		if _h(state, ["rev", int(h["id"]), state.tick]) % 100 < pct:
			(h["traits"] as Array).append(tr)
			added.append(state.add_chronicle("%s se réveille un matin en connaissant les rêves de toute sa garde. %s est sensitif." % [h["name"], h["name"]],
					Espionage.private_to(state, [e.id])))
