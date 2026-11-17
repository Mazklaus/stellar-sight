class_name Transcendence
extends RefCounted
## La Transcendance (étude du 2026-11-17, 42 propositions validées ; données : data/transcendence.json).
##
## Fin de partie où un peuple quitte la galaxie matérielle. Trois étapes (prop. 5) :
## 1. l'Orée : la technologie « oree » ouvre le choix d'une VOIE (catalogue ouvert « paths », prop. 1-2)
##    et une jauge d'Élévation de 0 à 100 (en dixièmes : 0-1000) nourrie par la source de la voie ;
## 2. l'Exodium de la voie (Dormitoire, Substrat, Trône vide, Chrysalide, Arche de la Bordure) : trois
##    étapes payées, dans un système tenu (prop. 15) ;
## 3. le Passage : compte à rebours (5 ans) que les Relais et les Lieux minces raccourcissent, que les
##    empires joints allongent, et qui recule quand le système de l'Exodium est occupé (prop. 7, 13, 16).
##    Le Grand Départ finit par un voyage : l'Arche doit rallier un système de bordure (prop. 17).
##
## Issue réglable (prop. 6) : « victoire » (la partie s'arrête, victoire partagée avec les joints) ou
## « depart » (l'espèce fondatrice quitte la galaxie, voir TranscendenceWorld).
##
## Nom : l'étude parle de « Grand Œuvre » ; le jeu dit « l'Exodium » pour ne pas confondre avec la
## victoire des Grands Œuvres (merveilles).
##
## Réglage « Transcendance » : Complète, Victoire seule, Désactivée (state.transcendence vide).
## Sans l'option (tests, bancs) : désactivée.
##
## État : state.transcendence = {"mode", "outcome", "path": {"eid": voie}, "gauge": {"eid": 0-1000},
##  "oeuvre": {"eid": {"stage": étapes finies 0-3, "until": fin de l'étape en cours (0 = aucune),
##  "sys": système}}, "passage": {"eid": {"prog": jours tenus, "start", "occ": mois d'occupation}},
##  "ark": {"eid": {"fleet", "target"}}, "joined": {"eid": hôte}, "done": {"eid": jour},
##  "renounced": {"eid": jour}, "st": {"eid": {statistiques}}, et les sous-états du monde (lot 2-3).
## Tout est déterministe : entiers, tirages par hachage de la graine, ordres par SimCommands.

const SUBS := ["path", "gauge", "oeuvre", "passage", "ark", "joined", "done", "renounced", "st", "signs", "rest", "minces", "partis", "ruins", "fxsig", "contracts", "shortcut", "offered", "desc", "curse", "aid"]


static func data() -> Dictionary:
	return GameData.transcendence()


static func cfg(section: String) -> Dictionary:
	var v: Variant = data().get(section, {})
	return v if v is Dictionary else {}


static func c_int(section: String, key: String, def := 0) -> int:
	return int(cfg(section).get(key, def))


static func mode_defs() -> Array:
	return data().get("modes", [])


static func default_mode() -> String:
	return String(data().get("default_mode", "complete"))


static func outcome_defs() -> Array:
	return data().get("outcomes", [])


static func default_outcome() -> String:
	return String(data().get("default_outcome", "victoire"))


static func mode(state: GameState) -> String:
	return String(state.transcendence.get("mode", "desactivee"))


static func outcome(state: GameState) -> String:
	return String(state.transcendence.get("outcome", "victoire"))


static func enabled(state: GameState) -> bool:
	return state != null and not state.transcendence.is_empty()


## Mode Complet : signes, Restants, Lieux minces, réactions, héritage, Partis, Avorté, Raccourci.
static func full(state: GameState) -> bool:
	return enabled(state) and mode(state) == "complete"


## Issue « Départ » : l'espèce fondatrice quitte la galaxie, la partie continue.
static func departs(state: GameState) -> bool:
	return enabled(state) and outcome(state) == "depart"


static func applies(state: GameState, eid: int) -> bool:
	var e := state.get_empire(eid) if enabled(state) and eid >= 0 else null
	return e != null and not e.is_npc() and not e.eliminated


static func mode_label(state: GameState) -> String:
	for m: Dictionary in mode_defs():
		if String(m["id"]) == mode(state):
			return String(m["label"])
	return "Désactivée"


static func outcome_label(state: GameState) -> String:
	for m: Dictionary in outcome_defs():
		if String(m["id"]) == outcome(state):
			return String(m["label"])
	return "Victoire"


# --- Réglage, sauvegarde -----------------------------------------------------------------------

static func setup(state: GameState, mode_id: String, outcome_id := "") -> void:
	state.transcendence = {}
	var ok := false
	for m: Dictionary in mode_defs():
		if String(m["id"]) == mode_id:
			ok = true
	if not ok or mode_id == "desactivee":
		return
	var oc := outcome_id
	var oc_ok := false
	for m: Dictionary in outcome_defs():
		if String(m["id"]) == oc:
			oc_ok = true
	if not oc_ok:
		oc = default_outcome()
	state.transcendence = {"mode": mode_id, "outcome": oc}
	for k in SUBS:
		state.transcendence[k] = {}
	if full(state):
		TranscendenceWorld.place_minces(state)


static func worth_saving(state: GameState) -> bool:
	return enabled(state)


static func to_dict(state: GameState) -> Dictionary:
	return state.transcendence.duplicate(true)


static func from_dict(state: GameState, d: Dictionary) -> void:
	if d.is_empty():
		state.transcendence = {}
		return
	state.transcendence = GameData._to_ints(d.duplicate(true))
	for k in SUBS:
		if not state.transcendence.has(k):
			state.transcendence[k] = {}


static func sub(state: GameState, k: String) -> Dictionary:
	if state.transcendence.is_empty():
		return {}  # pilier désactivé : ne jamais le rallumer en écrivant
	if not state.transcendence.has(k):
		state.transcendence[k] = {}
	return state.transcendence[k]


static func _h(state: GameState, parts: Array) -> int:
	return absi(hash([state.seed_value, "tr"] + parts))


static func _stat(state: GameState, eid: int, k: String, n: int) -> void:
	if state.transcendence.is_empty():
		return
	var st := sub(state, "st")
	var d: Dictionary = st.get(str(eid), {})
	d[k] = int(d.get(k, 0)) + n
	st[str(eid)] = d


static func stat(state: GameState, eid: int, k: String) -> int:
	return int((sub(state, "st").get(str(eid), {}) as Dictionary).get(k, 0))


static func month_days() -> int:
	return int(GameData.rules()["month_days"])


# --- Talents, credo ----------------------------------------------------------------------------

## Talent de Transcendance du peuple (prop. 32, data « talents » par peuple).
static func talent(state: GameState, eid: int) -> Dictionary:
	var e := state.get_empire(eid)
	if e == null:
		return {}
	var v: Variant = cfg("talents").get(Genetics.root(e.faction_id), null)
	return v if v is Dictionary else {}


static func t_int(state: GameState, eid: int, key: String) -> int:
	var v: Variant = talent(state, eid).get(key, 0)
	return int(v) if (v is int or v is float) else 0


static func credo(state: GameState, eid: int) -> String:
	var e := state.get_empire(eid)
	return "" if e == null else String(FactionTraits.species(e.faction()).get("credo", ""))


static func archetype(state: GameState, eid: int) -> String:
	var e := state.get_empire(eid)
	return "" if e == null else String(FactionTraits.species(e.faction()).get("archetype", ""))


# --- Voies -------------------------------------------------------------------------------------

static func path_defs() -> Array:
	return cfg("paths").get("list", [])


static func path_def(id: String) -> Dictionary:
	for p: Dictionary in path_defs():
		if String(p["id"]) == id:
			return p
	return {}


static func path_of(state: GameState, eid: int) -> String:
	return String(sub(state, "path").get(str(eid), ""))


static func path_label(id: String) -> String:
	return String(path_def(id).get("label", id))


static func oeuvre_def(path_id: String) -> Dictionary:
	return path_def(path_id).get("oeuvre", {})


static func oeuvre_label(path_id: String) -> String:
	return String(oeuvre_def(path_id).get("label", "l'Exodium"))


static func knows_oree(state: GameState, eid: int) -> bool:
	var e := state.get_empire(eid)
	return e != null and e.techs.has(String(data().get("tech", "oree")))


static func renounced(state: GameState, eid: int) -> bool:
	return sub(state, "renounced").has(str(eid))


static func done(state: GameState, eid: int) -> bool:
	return sub(state, "done").has(str(eid))


## Raison pour laquelle l'empire ne peut pas prendre cette voie ("" s'il le peut). Prop. 29, 34-36.
static func path_why(state: GameState, eid: int, pid: String) -> String:
	var pd := path_def(pid)
	if pd.is_empty():
		return "voie inconnue"
	var e := state.get_empire(eid)
	if t_int(state, eid, "never") > 0:
		return "%s ne transcende jamais : il préfère manger ceux qui partent" % e.short_name()
	if CrisisNemesis.is_scourge(state, eid):
		return "le Fléau des étoiles n'a pas d'autre sortie que son grand œuvre"
	var arch := archetype(state, eid)
	var allowed: Variant = cfg("archetypes").get(arch, null)
	if allowed is Array and not (allowed as Array).has(pid):
		return "votre archétype (%s) n'ouvre pas cette voie" % arch
	if Genetics.enabled(state) and e.gene_path == "purete" and (data().get("purete_forbids", []) as Array).has(pid):
		return "le serment de Pureté l'interdit"
	match String(pd.get("needs", "")):
		"songe":
			if not Psionics.applies(state, eid):
				return "il faut les pouvoirs psioniques en jeu"
			var free := t_int(state, eid, "songe_free") > 0 or arch == "energetique"
			if not Psionics.crowned(state, eid) and not (free and Psionics.founder_level(state, eid) >= 1):
				return "il faut une espèce Transcendante (L'Éveil couronné)"
		"televersement":
			var gov := String(FactionTraits.species(e.faction()).get("gouvernement", ""))
			if not (e.gene_path == "synthetique" or arch == "synthetique" or gov == "conscience"):
				return "il faut la voie synthétique du Génome, un peuple synthétique ou une conscience distribuée"
		"apotheose":
			var fid := Faiths.founded_by(state, eid) if state.faith_on else ""
			var ok := fid != "" and int(Faiths.faith(state, fid).get("zeal", 0)) >= 75
			if not ok and t_int(state, eid, "apotheose_dynasty") > 0:
				ok = true
			if not ok:
				return "il faut avoir fondé une grande foi au zèle d'au moins 75"
		"mue":
			if not (e.gene_path == "genetique" or arch == "ruche"):
				return "il faut la voie Espèce parfaite du Génome, ou un peuple-ruche"
	return ""


static func available_paths(state: GameState, eid: int) -> Array[String]:
	var out: Array[String] = []
	for p: Dictionary in path_defs():
		if path_why(state, eid, String(p["id"])) == "":
			out.append(String(p["id"]))
	return out


static func check_path(state: GameState, eid: int, pid: String) -> String:
	if not applies(state, eid):
		return "la Transcendance n'est pas en jeu"
	if not knows_oree(state, eid):
		return "il faut la technologie %s" % String(Research.tech(String(data().get("tech", "oree"))).get("label", "L'Orée"))
	if renounced(state, eid):
		return "votre peuple a renoncé à l'Orée : il ne la franchira plus"
	if path_of(state, eid) != "":
		return "votre empire s'est déjà voué à une voie"
	if sub(state, "joined").has(str(eid)):
		return "votre empire a rejoint le Passage d'un autre"
	return path_why(state, eid, pid)


static func choose_path(state: GameState, eid: int, pid: String, added: Array[Dictionary]) -> void:
	var e := state.get_empire(eid)
	sub(state, "path")[str(eid)] = pid
	sub(state, "gauge")[str(eid)] = 0
	_stat(state, eid, "path", 1)
	state.relic_rev += 1
	added.append(state.add_chronicle("%s franchit l'Orée et se voue à %s. %s" % [e.display_name(), path_label(pid).to_lower(), String(path_def(pid).get("text", "")).get_slice(".", 0) + "."],
			Espionage.public_to(state, [eid])))


# --- Jauge d'Élévation -------------------------------------------------------------------------

static func gauge(state: GameState, eid: int) -> int:
	return int(sub(state, "gauge").get(str(eid), 0))


static func gauge_max() -> int:
	return c_int("gauge", "max", 1000)


static func gauge_pct(state: GameState, eid: int) -> int:
	@warning_ignore("integer_division")
	return 100 * gauge(state, eid) / maxi(1, gauge_max())


static func add_gauge(state: GameState, eid: int, n: int) -> void:
	if path_of(state, eid) == "":
		return
	sub(state, "gauge")[str(eid)] = clampi(gauge(state, eid) + n, 0, gauge_max())


static func source_value(state: GameState, eid: int, src: String) -> int:
	match src:
		"resonance":
			return Psionics.monthly_gain(state, eid) if Psionics.applies(state, eid) else 0
		"knowledge":
			return int((Economy.empire_income(state, eid)["gross"] as Dictionary).get("knowledge", 0))
		"faith":
			var fid := Faiths.founded_by(state, eid) if state.faith_on else ""
			return Faiths.followers(state, fid) if fid != "" else 0
		"pop":
			var n := 0
			for pid in state.sorted_colony_ids():
				var c: Colony = state.colonies[pid]
				if c.owner == eid and c.is_colony():
					n += c.population
			return n
		"industry":
			var g: Dictionary = Economy.empire_income(state, eid)["gross"]
			return int(g.get("materials", 0)) + int(g.get("energy", 0))
	return 0


static func source_label(src: String) -> String:
	return {"resonance": "Résonance", "knowledge": "Savoir", "faith": "Fidèles de votre foi", "pop": "Population", "industry": "Matériaux et énergie"}.get(src, src)


## Détail du gain mensuel de jauge (dixièmes de %) : [[libellé, valeur]].
@warning_ignore("integer_division")
static func gain_parts(state: GameState, eid: int) -> Array:
	var out := []
	var pid := path_of(state, eid)
	if pid == "" or not applies(state, eid):
		return out
	var pd := path_def(pid)
	out.append(["Élan de l'Orée", c_int("gauge", "base", 4)])
	var src := String(pd.get("source", ""))
	var v := source_value(state, eid, src) / maxi(1, int(pd.get("div", 1)))
	if v > 0:
		out.append([source_label(src), v])
	if pid == "apotheose" and t_int(state, eid, "heir_gauge") > 0 and (not state.faith_on or Faiths.founded_by(state, eid) == ""):
		out.append(["La Lignée monte", t_int(state, eid, "heir_gauge")])
	var guide := guide_hero(state, eid)
	if not guide.is_empty():
		out.append(["Guide du Passage : %s" % String(guide["name"]), int(guide.get("lvl", 1)) * c_int("gauge", "guide_per_level", 2)])
	for x in TranscendenceWorld.gain_parts(state, eid):
		out.append(x)
	var raw := 0
	for x in out:
		raw += int(x[1])
	var pct := int((talent(state, eid).get("path_pct", {}) as Dictionary).get(pid, 0)) + t_int(state, eid, "gauge_pct")
	if credo(state, eid) == String(cfg("credo").get("id", "transcendance")):
		pct += c_int("gauge", "credo_pct", 25)
	if pct != 0 and raw > 0:
		out.append(["Talent et credo (%+d %%)" % pct, raw * pct / 100])
	return out


static func monthly_gain(state: GameState, eid: int) -> int:
	var n := 0
	for p in gain_parts(state, eid):
		n += int(p[1])
	return clampi(n, 0, c_int("gauge", "max_month", 60))


## Guide du Passage (prop. 14) : le héros le plus capé du Conseil.
static func guide_hero(state: GameState, eid: int) -> Dictionary:
	if state.heroes.is_empty():
		return {}
	var best := {}
	for h in Heroes.council(state, eid):
		if best.is_empty() or int(h.get("lvl", 1)) > int(best.get("lvl", 1)):
			best = h
	return best


# --- L'Exodium -----------------------------------------------------------------------------------

static func oeuvre(state: GameState, eid: int) -> Dictionary:
	return sub(state, "oeuvre").get(str(eid), {})


static func stage(state: GameState, eid: int) -> int:
	return int(oeuvre(state, eid).get("stage", 0))


static func stage_running(state: GameState, eid: int) -> bool:
	return int(oeuvre(state, eid).get("until", 0)) > 0


static func oeuvre_sys(state: GameState, eid: int) -> int:
	return int(oeuvre(state, eid).get("sys", -1))


static func stage_def(path_id: String, n: int) -> Dictionary:
	var st: Array = oeuvre_def(path_id).get("stages", [])
	return st[n] if n >= 0 and n < st.size() else {}


static func stage_count(path_id: String) -> int:
	return (oeuvre_def(path_id).get("stages", []) as Array).size()


## Système où l'Exodium s'élèverait (site de la voie) ; -1 si aucun ne convient.
static func site_for(state: GameState, eid: int, path_id: String, want := -1) -> int:
	var e := state.get_empire(eid)
	var cap := FactionTraits.capital_system(state, eid)
	match String(oeuvre_def(path_id).get("site", "capital")):
		"star":
			if want >= 0 and state.system_owner(want) == eid:
				return want
			return cap
		"holy":
			var fid := Faiths.founded_by(state, eid) if state.faith_on else ""
			if fid != "":
				var hp := int(Faiths.faith(state, fid).get("holy", -1))
				var hc: Colony = state.colonies.get(hp)
				if hc != null and hc.owner == eid:
					return state.galaxy.get_planet(hp).system_id
				if t_int(state, eid, "apotheose_dynasty") <= 0:
					return -1
			return cap
	if e != null and e.capital_planet < 0 and String(oeuvre_def(path_id).get("site", "capital")) == "capital":
		return -1
	return cap


static func stage_cost(state: GameState, eid: int) -> Dictionary:
	return stage_def(path_of(state, eid), stage(state, eid)).get("cost", {})


static func check_oeuvre(state: GameState, eid: int, want := -1) -> String:
	if not applies(state, eid):
		return "la Transcendance n'est pas en jeu"
	var pid := path_of(state, eid)
	if pid == "":
		return "il faut d'abord se vouer à une voie"
	if gauge(state, eid) < gauge_max():
		return "la jauge d'Élévation doit être pleine (%d %%)" % gauge_pct(state, eid)
	if stage_running(state, eid):
		return "une étape est déjà en chantier"
	if stage(state, eid) >= stage_count(pid):
		return "%s est achevé" % oeuvre_label(pid)
	if pid == "depart" and t_int(state, eid, "city_ark") > 0:
		return "la flotte-ville sert d'Arche : il n'y a rien à bâtir"
	if stage(state, eid) == 0 and TranscendenceWorld.moratorium(state, eid):
		return "l'Amphictyonie a voté un Moratoire sur l'Orée"
	var vs := t_int(state, eid, "referendum_stab")
	if vs > 0 and stage(state, eid) == 0 and Stability.applies(state, eid) and Stability.empire_value(state, eid) < vs:
		return "le Référendum de l'Orée échoue : il faut une stabilité moyenne de %d" % vs
	var sys := oeuvre_sys(state, eid) if stage(state, eid) > 0 else site_for(state, eid, pid, want)
	if sys < 0 or state.system_owner(sys) != eid:
		return "aucun site tenu pour %s" % oeuvre_label(pid)
	var e := state.get_empire(eid)
	var cost := stage_cost(state, eid)
	if not Economy.can_afford(e, cost):
		return "il faut %s" % GameData.format_amounts(cost)
	return ""


static func start_stage(state: GameState, eid: int, want: int, added: Array[Dictionary]) -> void:
	var e := state.get_empire(eid)
	var pid := path_of(state, eid)
	var o := oeuvre(state, eid).duplicate()
	if int(o.get("stage", 0)) == 0 and not o.has("sys"):
		o["sys"] = site_for(state, eid, pid, want)
	o["stage"] = int(o.get("stage", 0))
	var sd := stage_def(pid, int(o["stage"]))
	Economy.pay(e, sd.get("cost", {}))
	o["until"] = state.tick + int(sd.get("days", 180))
	sub(state, "oeuvre")[str(eid)] = o
	if int(o["stage"]) == 0:
		added.append(state.add_chronicle(String(path_def(pid).get("start", "%s commence son Exodium.")) % e.display_name(), Espionage.public_to(state, [eid])))


## Étape finie (bilan mensuel) ; la dernière ouvre le Passage.
static func _advance_oeuvre(state: GameState, eid: int, added: Array[Dictionary]) -> void:
	var o := oeuvre(state, eid)
	if o.is_empty() or int(o.get("until", 0)) <= 0 or state.tick < int(o["until"]):
		return
	o["until"] = 0
	o["stage"] = int(o.get("stage", 0)) + 1
	if int(o["stage"]) >= stage_count(path_of(state, eid)):
		begin_passage(state, eid, added)


# --- Le Passage --------------------------------------------------------------------------------

static func passage(state: GameState, eid: int) -> Dictionary:
	return sub(state, "passage").get(str(eid), {})


static func in_passage(state: GameState, eid: int) -> bool:
	return sub(state, "passage").has(str(eid))


## Empire en Passage, ou joint au Passage d'un autre.
static func leaving(state: GameState, eid: int) -> bool:
	return in_passage(state, eid) or sub(state, "joined").has(str(eid))


static func relay_building() -> String:
	return String(cfg("relay").get("building", "relais_passage"))


## Relais qui comptent pour le Passage : bâtis chez l'hôte et chez les joints, réseau de Teyl,
## merveilles qui servent de Relais (prop. 13, 32, 38).
static func relays(state: GameState, eid: int) -> int:
	var who := joined_to(state, eid)
	who.append(eid)
	var b := relay_building()
	var n := 0
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if who.has(c.owner) and c.buildings.has(b):
			n += 1
	if not TranscendenceWorld.relays_banned(state, eid):
		n += TranscendenceBridges.extra_relays(state, eid)
	else:
		n = 0
	return n


## Durée du Passage (jours) : base de la voie, moins Relais et Lieux minces (plancher), plus un an par joint.
static func passage_need(state: GameState, eid: int) -> int:
	var pid := path_of(state, eid)
	var p := cfg("passage")
	var base := int(cfg("arche").get("days", 1080)) if pid == "depart" else int(p.get("days", 1800))
	if not passage(state, eid).is_empty() and passage(state, eid).has("short"):
		return int(passage(state, eid)["short"])  # Raccourci (lot 3)
	var cut := relays(state, eid) * int(p.get("relay_days", 60)) + TranscendenceWorld.minces_held(state, eid) * int(p.get("minces_days", 90))
	cut += TranscendenceWorld.bless_days(state, eid)
	var need := maxi(mini(base, int(p.get("min_days", 720))), base - cut)
	return need + joined_to(state, eid).size() * int(p.get("per_joined_days", 360))


static func passage_prog(state: GameState, eid: int) -> int:
	return int(passage(state, eid).get("prog", 0))


static func passage_pct(state: GameState, eid: int) -> int:
	@warning_ignore("integer_division")
	return mini(100, 100 * passage_prog(state, eid) / maxi(1, passage_need(state, eid)))


static func begin_passage(state: GameState, eid: int, added: Array[Dictionary], shortcut := 0) -> void:
	var e := state.get_empire(eid)
	var p := {"prog": 0, "start": state.tick, "occ": 0}
	if shortcut > 0:
		p["short"] = shortcut
	sub(state, "passage")[str(eid)] = p
	_stat(state, eid, "passage", 1)
	state.relic_rev += 1
	added.append(state.add_chronicle("Alerte galactique : %s entre dans le Passage. Dans %s, son peuple ne sera plus de ce monde ; d'ici là, %s doit tenir." % [
			e.display_name(), Victory._days_text(passage_need(state, eid)), oeuvre_label(path_of(state, eid))], Espionage.public_to(state, [eid])))
	if full(state):
		TranscendenceWorld.on_passage(state, eid, added)


## Passage brisé (Exodium perdu, Arche abattue) : tout recule, et l'Avorté peut naître (lot 3).
static func break_passage(state: GameState, eid: int, why: String, stages_lost: int, added: Array[Dictionary]) -> void:
	var e := state.get_empire(eid)
	var pct := passage_pct(state, eid) if in_passage(state, eid) else 0
	sub(state, "passage").erase(str(eid))
	sub(state, "ark").erase(str(eid))
	var o := oeuvre(state, eid)
	if not o.is_empty():
		o["stage"] = maxi(0, int(o.get("stage", 0)) - stages_lost)
		o["until"] = 0
		if int(o["stage"]) == 0:
			sub(state, "oeuvre").erase(str(eid))
	state.relic_rev += 1
	_stat(state, eid, "broken", 1)
	added.append(state.add_chronicle("Le Passage de %s est brisé : %s." % [e.display_name(), why], Espionage.public_to(state, [eid])))
	if full(state):
		TranscendenceBridges.on_break(state, eid, pct, added)


static func _tick_passage(state: GameState, eid: int, added: Array[Dictionary]) -> void:
	var p := passage(state, eid)
	if p.is_empty():
		return
	var pid := path_of(state, eid)
	if sub(state, "ark").has(str(eid)):
		_tick_ark(state, eid, added)
		return
	var sys := oeuvre_sys(state, eid)
	if p.has("short") or pid == "depart" and t_int(state, eid, "city_ark") > 0 or sys < 0 or state.system_owner(sys) == eid:
		p["occ"] = 0
		p["prog"] = int(p["prog"]) + month_days()
	else:
		p["occ"] = int(p.get("occ", 0)) + 1
		p["prog"] = maxi(0, int(p["prog"]) - c_int("passage", "occupied_back_days", 360))
		if int(p["occ"]) >= c_int("passage", "destroy_months", 6):
			break_passage(state, eid, "%s est tombé aux mains de l'ennemi et a été détruit" % oeuvre_label(pid), 1, added)
			return
		if int(p["occ"]) == 1:
			added.append(state.add_chronicle("%s de %s est occupé : le Passage recule." % [oeuvre_label(pid).capitalize(), state.get_empire(eid).short_name()],
					Espionage.public_to(state, [eid])))
	if int(p["prog"]) >= passage_need(state, eid):
		if pid == "depart":
			launch_ark(state, eid, added)
		else:
			complete(state, eid, added)


# --- L'Arche de la Bordure ---------------------------------------------------------------------

static func ark(state: GameState, eid: int) -> Dictionary:
	return sub(state, "ark").get(str(eid), {})


static func ark_fleet(state: GameState, eid: int) -> Fleet:
	var a := ark(state, eid)
	return state.fleets.get(int(a.get("fleet", -1))) if not a.is_empty() else null


## Système de bordure : le plus loin du centre de la galaxie parmi ceux à min_jumps sauts ou plus.
static func border_target(state: GameState, eid: int, from: int) -> int:
	var cap := FactionTraits.capital_system(state, eid)
	if cap < 0:
		cap = from
	var jumps := FactionTraits.jumps_from(state.galaxy, cap)
	var center := Vector2.ZERO
	for s in state.galaxy.systems:
		center += s.position
	center /= maxf(1.0, float(state.galaxy.systems.size()))
	var best := -1
	var best_d := -1.0
	var mj := c_int("arche", "min_jumps", 6)
	for sid in jumps:
		if int(jumps[sid]) < mj:
			continue
		var d: float = (state.galaxy.systems[int(sid)].position - center).length()
		if d > best_d or (is_equal_approx(d, best_d) and int(sid) < best):
			best_d = d
			best = int(sid)
	if best < 0:
		for sid in jumps:  # petite galaxie : le plus loin qu'on puisse
			if best < 0 or int(jumps[sid]) > int(jumps[best]) or (int(jumps[sid]) == int(jumps[best]) and int(sid) < best):
				best = int(sid)
	return best


static func launch_ark(state: GameState, eid: int, added: Array[Dictionary]) -> void:
	var e := state.get_empire(eid)
	var f: Fleet = null
	if t_int(state, eid, "city_ark") > 0:
		f = FactionTraits.city_fleet(state, eid)
	var sys := oeuvre_sys(state, eid)
	if sys < 0:
		sys = FactionTraits.capital_system(state, eid)
	if f == null:
		f = state.spawn_ship(eid, String(cfg("arche").get("ship", "arche_bordure")), sys)
	var target := border_target(state, eid, f.system_id)
	sub(state, "ark")[str(eid)] = {"fleet": f.id, "target": target}
	added.append(state.add_chronicle("Alerte galactique : l'Arche de %s quitte son chantier et met le cap sur la Bordure (%s). Si elle tombe en route, tout est à refaire." % [
			e.display_name(), state.galaxy.systems[target].system_name], Espionage.public_to(state, [eid])))


static func _tick_ark(state: GameState, eid: int, added: Array[Dictionary]) -> void:
	var f := ark_fleet(state, eid)
	if f == null or f.owner != eid:
		sub(state, "oeuvre").erase(str(eid))
		break_passage(state, eid, "l'Arche a été abattue en route vers la Bordure ; tout est à refaire", 3, added)
		return
	if f.system_id == int(ark(state, eid)["target"]) and not f.is_moving():
		complete(state, eid, added)


## La flotte est-elle l'Arche d'un Passage en cours ?
static func is_ark(state: GameState, f: Fleet) -> bool:
	return int(ark(state, f.owner).get("fleet", -1)) == f.id


## Système de l'Exodium d'un empire qui a passé l'alerte (IA : cible de guerre, prop. 40).
static func strike_target(state: GameState, owner: int, sid: int) -> bool:
	if owner < 0 or oeuvre_sys(state, owner) != sid:
		return false
	var e := state.get_empire(owner)
	return e != null and int(e.victory.get("transcendance", {}).get("pct", 0)) >= c_int("ai", "strike_at", 50)


# --- Transcendance commune ---------------------------------------------------------------------

static func host_of(state: GameState, eid: int) -> int:
	return int(sub(state, "joined").get(str(eid), -1))


static func joined_to(state: GameState, host: int) -> Array[int]:
	var out: Array[int] = []
	var j := sub(state, "joined")
	var ks := j.keys()
	ks.sort()
	for k in ks:
		if int(j[k]) == host:
			out.append(int(k))
	return out


static func check_join(state: GameState, eid: int, host: int) -> String:
	if not applies(state, eid) or not applies(state, host) or eid == host:
		return "la Transcendance n'est pas en jeu"
	if not knows_oree(state, eid):
		return "il faut avoir franchi l'Orée (technologie)"
	if renounced(state, eid) or t_int(state, eid, "never") > 0:
		return "votre peuple ne partira pas"
	if in_passage(state, eid) or sub(state, "joined").has(str(eid)):
		return "votre empire est déjà sur le départ"
	if not in_passage(state, host):
		return "%s n'est pas en Passage" % state.get_empire(host).short_name()
	if not (Diplomacy.allied(state, eid, host) or Koinon.same_league(state, eid, host)):
		return "il faut être allié, ou du même Koinon"
	if joined_to(state, host).size() + 1 >= c_int("passage", "max_joined", 3):
		return "trois empires au plus partent ensemble"
	var free := t_int(state, eid, "join_free") > 0 or t_int(state, host, "join_free") > 0
	if not free:
		var b := relay_building()
		var has := false
		for pid in state.sorted_colony_ids():
			var c: Colony = state.colonies[pid]
			if c.owner == eid and c.buildings.has(b):
				has = true
				break
		if not has:
			return "il faut un Relais du Passage chez vous"
	return ""


static func join(state: GameState, eid: int, host: int, added: Array[Dictionary]) -> void:
	sub(state, "joined")[str(eid)] = host
	state.relic_rev += 1
	_stat(state, eid, "joined", 1)
	TranscendenceWorld.note_aid(state, host, eid, c_int("partis", "aid_join", 3))
	added.append(state.add_chronicle("%s rejoint le Passage de %s : ils partiront ensemble." % [state.get_empire(eid).display_name(), state.get_empire(host).short_name()],
			Espionage.public_to(state, [eid, host])))


# --- Fin du Passage ----------------------------------------------------------------------------

static func complete(state: GameState, eid: int, added: Array[Dictionary]) -> void:
	var e := state.get_empire(eid)
	var pid := path_of(state, eid)
	if full(state) and TranscendenceBridges.trap(state, eid, added):
		return  # le Raccourci était un piège (lot 3)
	sub(state, "done")[str(eid)] = state.tick
	sub(state, "passage").erase(str(eid))
	sub(state, "ark").erase(str(eid))
	for j in joined_to(state, eid):
		sub(state, "done")[str(j)] = state.tick
	_stat(state, eid, "done", 1)
	if talent(state, eid).has("couplet"):
		added.append(state.add_chronicle("Le chroniqueur du Chœur annonce, la voix brisée, que le deuxième couplet est enfin terminé. Personne n'ose demander s'il y en a un troisième.", Espionage.public_to(state, [eid])))
	if not departs(state):
		return  # la victoire est proclamée par VictorySystem (Victory.progress « transcendance »)
	added.append(state.add_chronicle(String(path_def(pid).get("win", "%s quitte la galaxie.")) % e.display_name(), Espionage.public_to(state, [eid])))
	var leavers: Array[int] = [eid]
	leavers.append_array(joined_to(state, eid))
	for l in leavers:
		TranscendenceWorld.depart(state, l, pid, added)


## Avancée vers la victoire « transcendance » (Victory.progress) : jauge 0-49 %, Exodium 50-74 %,
## Passage 75-99 %, 100 au départ.
@warning_ignore("integer_division")
static func victory(state: GameState, e: Empire, out: Dictionary) -> void:
	var eid := e.id
	if t_int(state, eid, "never") > 0:
		out["lines"].append("Ce peuple ne transcende jamais.")
		return
	var host := host_of(state, eid)
	if host >= 0:
		out["lines"].append("Joint au Passage de %s" % state.get_empire(host).short_name())
		eid = host
	if done(state, e.id) or done(state, eid):
		out["pct"] = 100
		out["won"] = not departs(state) and host < 0  # l'hôte est proclamé, les joints partagent
		out["lines"].append("Transcendé")
		return
	var pid := path_of(state, eid)
	if renounced(state, eid):
		out["lines"].append("A renoncé à l'Orée")
		return
	if pid == "":
		out["lines"].append("Voie : aucune%s" % ("" if knows_oree(state, eid) else " (technologie L'Orée requise)"))
		return
	out["lines"].append("Voie : %s" % path_label(pid))
	if in_passage(state, eid):
		var a := ark(state, eid)
		if not a.is_empty():
			out["pct"] = 99
			out["lines"].append("L'Arche fait route vers %s" % state.galaxy.systems[int(a["target"])].system_name)
		else:
			out["pct"] = 75 + 24 * passage_prog(state, eid) / maxi(1, passage_need(state, eid))
			out["lines"].append("Passage : %s restants" % Victory._days_text(maxi(0, passage_need(state, eid) - passage_prog(state, eid))))
		out["cond"] = true
		return
	if gauge(state, eid) >= gauge_max():
		var n := stage_count(pid)
		out["pct"] = 50 + 25 * stage(state, eid) / maxi(1, n)
		out["lines"].append("%s : étape %d sur %d%s" % [oeuvre_label(pid).capitalize(), stage(state, eid) + (1 if stage_running(state, eid) else 0), n, " en chantier" if stage_running(state, eid) else ""])
		return
	out["pct"] = mini(49, gauge_pct(state, eid) / 2)
	out["lines"].append("Jauge d'Élévation : %d %%" % gauge_pct(state, eid))


# --- Renoncer ----------------------------------------------------------------------------------

static func check_renounce(state: GameState, eid: int) -> String:
	if not applies(state, eid):
		return "la Transcendance n'est pas en jeu"
	if path_of(state, eid) == "":
		return "votre empire n'a pas de voie à abandonner"
	return ""


static func renounce(state: GameState, eid: int, added: Array[Dictionary]) -> void:
	var e := state.get_empire(eid)
	if in_passage(state, eid):
		for j in joined_to(state, eid):
			sub(state, "joined").erase(str(j))
	for k in ["path", "gauge", "oeuvre", "passage", "ark"]:
		sub(state, k).erase(str(eid))
	sub(state, "renounced")[str(eid)] = state.tick
	_stat(state, eid, "renounced", 1)
	state.relic_rev += 1
	TranscendenceWorld.on_renounce(state, eid)
	added.append(state.add_chronicle("%s renonce à l'Orée. Les Restants prennent le pouvoir, la jauge s'éteint, et les ascètes rentrent chez eux un peu gênés." % e.display_name(),
			Espionage.public_to(state, [eid])))


# --- Bâtiments, effets -------------------------------------------------------------------------

## Bâtiment de Transcendance (economy.check_special) : le Relais du Passage.
static func check_build(state: GameState, eid: int, c: Colony, building_id: String) -> String:
	if not applies(state, eid):
		return "la Transcendance n'est pas en jeu dans cette partie"
	if building_id == relay_building():
		if not c.is_colony():
			return "seulement sur une colonie"
		if TranscendenceWorld.relays_banned(state, eid):
			return "l'Amphictyonie interdit les Relais"
		if path_of(state, eid) == "" and host_of(state, eid) < 0:
			var ally := false
			for other in state.empires:
				if in_passage(state, other.id) and (Diplomacy.allied(state, eid, other.id) or Koinon.same_league(state, eid, other.id)):
					ally = true
			if not ally:
				return "il faut s'être voué à une voie, ou un allié en Passage"
	return ""


## Effets lus par Research.effects (production, croissance, dégâts).
static func effects(state: GameState, eid: int) -> Dictionary:
	var out := {}
	if not applies(state, eid):
		return out
	Research._merge(out, TranscendenceWorld.effects(state, eid))
	Research._merge(out, TranscendenceBridges.effects(state, eid))
	return out


static func empire_stability_parts(state: GameState, eid: int) -> Array:
	if not applies(state, eid):
		return []
	return TranscendenceWorld.empire_stability_parts(state, eid)


## Bombardement contre un monde voilé par l'Orée (prop. 18), en % du normal.
static func bombard_pct(state: GameState, owner: int) -> int:
	if not full(state) or not leaving(state, owner):
		return 100
	return c_int("fade", "bombard_pct", 50)


# --- Commandes ---------------------------------------------------------------------------------

static func check(state: GameState, eid: int, act: String, d: Dictionary) -> String:
	if not applies(state, eid):
		return "la Transcendance n'est pas en jeu"
	match act:
		"path":
			return check_path(state, eid, String(d.get("path", "")))
		"oeuvre":
			return check_oeuvre(state, eid, int(d.get("sys", -1)))
		"join":
			return check_join(state, eid, int(d.get("host", -1)))
		"renounce":
			return check_renounce(state, eid)
	return TranscendenceBridges.check(state, eid, act, d)


static func apply(state: GameState, eid: int, act: String, d: Dictionary) -> Array[Dictionary]:
	var added: Array[Dictionary] = []
	match act:
		"path":
			choose_path(state, eid, String(d["path"]), added)
		"oeuvre":
			start_stage(state, eid, int(d.get("sys", -1)), added)
		"join":
			join(state, eid, int(d["host"]), added)
		"renounce":
			renounce(state, eid, added)
		_:
			TranscendenceBridges.apply(state, eid, act, d, added)
	return added


## Bilan mensuel : jauge, étapes de l'Exodium, Passage, Arche ; puis le monde (lot 2) et les ponts (lot 3).
static func monthly(state: GameState, added: Array[Dictionary]) -> void:
	if not enabled(state):
		return
	for e in state.empires:
		if not applies(state, e.id):
			continue
		if path_of(state, e.id) != "" and not done(state, e.id):
			if not TranscendenceWorld.frozen(state, e.id):
				add_gauge(state, e.id, monthly_gain(state, e.id))
			_advance_oeuvre(state, e.id, added)
			_tick_passage(state, e.id, added)
	# Les joints dont l'hôte a renoncé ou disparu se détachent.
	var j := sub(state, "joined")
	var ks := j.keys()
	ks.sort()
	for k in ks:
		var host := int(j[k])
		if not in_passage(state, host) and not done(state, host):
			j.erase(k)
	if full(state):
		TranscendenceWorld.monthly(state, added)
		TranscendenceBridges.monthly(state, added)
	_refresh_fx(state)


## Effets à recalculer quand leur signature change (paliers de jauge, Passage, années d'effacement).
static func _refresh_fx(state: GameState) -> void:
	var sig := sub(state, "fxsig")
	for e in state.empires:
		if not applies(state, e.id):
			continue
		var s := str(effects(state, e.id).hash())
		if String(sig.get(str(e.id), "")) != s:
			sig[str(e.id)] = s
			state.relic_rev += 1
