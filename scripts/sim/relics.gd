class_name Relics
extends RefCounted
## Fouilles et reliques (lot 2 de « Événements, quêtes et reliques », propositions 11 à 15).
##
## Fouilles : state.digs[système] = {"relic", "name", "chapters", "ch" (chapitres finis), "clues",
##   "diff", "by" (empire qui fouille, -1 personne), "next" (jour du prochain jet, -1 à l'arrêt),
##   "done" (-1 en cours, sinon empire qui a fini), "pillage" (jour du dernier pillage)}.
##   Un empire qui possède le système lance la fouille ; une phase dure 90 jours ; à la fin, jet
##   1-10 + indices + compétence − difficulté (règle de Stellaris). Un conquérant reprend la fouille.
## Reliques : state.relics[id] = {"owner" (-1 enfouie, -2 marché noir), "hero" (porteur, -1 au
##   Reliquaire), "found", "ready" (jour où le Triomphe se recharge)}.
## Par empire : state.relic_meta[empire] = {"frag", "tri" (relique du Triomphe en cours), "until",
##   "fakes": [{"relic", "until"}]} (fausses reliques refilées par un réseau retourné).
## Les effets passifs et ceux du Triomphe en cours s'ajoutent à ceux des technologies
## (Research.effects) ; state.relic_rev change à chaque mouvement pour en vider le cache.

const MARKET := -2

static var _defs := {}


static func data() -> Dictionary:
	return GameData.relics()


static func def(id: String) -> Dictionary:
	if _defs.is_empty():
		for r: Dictionary in data()["relics"]:
			_defs[String(r["id"])] = r
	return _defs.get(id, {})


static func ids() -> Array[String]:
	var out: Array[String] = []
	for r: Dictionary in data()["relics"]:
		out.append(String(r["id"]))
	return out


static func rules() -> Dictionary:
	return data()["rules"]


static func _h(state: GameState, parts: Array) -> int:
	return absi(hash([state.seed_value, "relique"] + parts))


static func meta(state: GameState, empire_id: int) -> Dictionary:
	if not state.relic_meta.has(empire_id):
		state.relic_meta[empire_id] = {"frag": 0, "tri": "", "until": 0, "fakes": []}
	return state.relic_meta[empire_id]


static func fragments(state: GameState, empire_id: int) -> int:
	return int(state.relic_meta[empire_id]["frag"]) if state.relic_meta.has(empire_id) else 0


static func add_fragments(state: GameState, empire_id: int, n: int) -> void:
	var e := state.get_empire(empire_id)
	if e == null or e.is_npc() or n == 0:
		return
	var m := meta(state, empire_id)
	m["frag"] = maxi(0, int(m["frag"]) + n)


static func touch(state: GameState) -> void:
	state.relic_rev += 1


# --- Mise en place ------------------------------------------------------------------------------

static func setup(state: GameState) -> void:
	state.digs.clear()
	state.relics.clear()
	var per := int((data()["digs"]["per_systems"] as Dictionary).get(state.curio_density, 0))
	if per <= 0:
		return
	for id in ids():
		state.relics[id] = {"owner": -1, "hero": -1, "found": -1, "ready": 0}
	var starts: Array = []
	for e in state.empires:
		var cap := FactionTraits.capital_system(state, e.id)
		if cap >= 0:
			starts.append(FactionTraits.jumps_from(state.galaxy, cap))
	@warning_ignore("integer_division")
	var want := maxi(1, state.galaxy.systems.size() / per)
	var cands: Array = []
	for sys in state.galaxy.systems:
		if sys.planet_ids.is_empty() or state.system_owner(sys.id) >= 0 or Pirates.is_lair(state, sys.id):
			continue
		var near := 999
		for d: Dictionary in starts:
			near = mini(near, int(d.get(sys.id, 999)))
		if near < int(data()["digs"]["min_jumps"]):
			continue
		cands.append([_h(state, ["site", sys.id]) % 100000, sys.id])
	cands.sort()
	for i in mini(want, cands.size()):
		create_site(state, int(cands[i][1]))


## Crée un site de fouille dans ce système avec une relique encore enfouie (ou passée au marché noir).
## Renvoie false s'il n'y a plus de relique à cacher.
static func create_site(state: GameState, sid: int) -> bool:
	if state.digs.has(sid):
		return false
	var free: Array[String] = []
	for id in ids():
		var r: Dictionary = state.relics[id]
		# Les reliques de quête (tag « quete ») et les trophées (« trophee ») ne s'enfouissent qu'après être
		# passés au marché noir.
		if int(r["owner"]) == -1 and (is_quest(id) or is_trophy(id)):
			continue
		if (int(r["owner"]) == -1 or int(r["owner"]) == MARKET) and not _buried(state, id):
			free.append(id)
	if free.is_empty():
		return false
	var rid := free[_h(state, ["pick", sid]) % free.size()]
	state.relics[rid]["owner"] = -1
	var dg: Dictionary = data()["digs"]
	var ch: Array = dg["chapters"]
	var bd: Array = dg["base_diff"]
	state.digs[sid] = {"relic": rid, "name": _h(state, ["name", sid]) % (dg["names"] as Array).size(),
			"chapters": int(ch[0]) + _h(state, ["chap", sid]) % (int(ch[1]) - int(ch[0]) + 1),
			"ch": 0, "clues": 0, "diff": int(bd[0]) + _h(state, ["diff", sid]) % (int(bd[1]) - int(bd[0]) + 1),
			"by": -1, "next": -1, "done": -1, "pillage": -999}
	return true


static func _buried(state: GameState, rid: String) -> bool:
	for sid in state.digs:
		if String(state.digs[sid]["relic"]) == rid and int(state.digs[sid]["done"]) < 0:
			return true
	return false


# --- Fouilles -----------------------------------------------------------------------------------

static func site_name(state: GameState, sid: int) -> String:
	var d: Dictionary = state.digs[sid]
	var names: Array = data()["digs"]["names"]
	return String(names[int(d["name"]) % names.size()])


static func is_open(state: GameState, sid: int) -> bool:
	return state.digs.has(sid) and int(state.digs[sid]["done"]) < 0


## Le site est-il connu de cet empire (système exploré) ?
static func knows(state: GameState, empire_id: int, sid: int) -> bool:
	var e := state.get_empire(empire_id)
	return state.digs.has(sid) and e != null and not e.is_npc() and e.explored.has(sid)


## Les détails d'une fouille d'un autre empire sont cachés si son peuple est énergétique (le Voile).
static func hidden_from(state: GameState, viewer: int, sid: int) -> bool:
	var by := int(state.digs[sid]["by"])
	if by < 0 or by == viewer:
		return false
	return Events.layer_value(state, by, "archetype") == "energetique"


static func known_sites(state: GameState, empire_id: int) -> Array[int]:
	var out: Array[int] = []
	var keys := state.digs.keys()
	keys.sort()
	for sid in keys:
		if knows(state, empire_id, int(sid)):
			out.append(int(sid))
	return out


static func difficulty(state: GameState, sid: int) -> int:
	var d: Dictionary = state.digs[sid]
	return int(d["diff"]) + int(d["ch"])


## Compétence : niveau du gouverneur Intendant du système, sinon 1.
static func skill(state: GameState, empire_id: int, sid: int) -> int:
	var h := Heroes.at_post(state, "system", sid, empire_id)
	if not h.is_empty() and String(h["cls"]) == "intendant":
		return maxi(1, int(h["lvl"]))
	return 1


## Chance (en %) que la prochaine phase finisse le chapitre.
static func success_pct(state: GameState, empire_id: int, sid: int) -> int:
	var need := int(data()["digs"]["success_at"]) - int(state.digs[sid]["clues"]) - skill(state, empire_id, sid) + difficulty(state, sid)
	return clampi((11 - need) * 10, 0, 100)


static func check_start(state: GameState, empire_id: int, sid: int) -> String:
	if not is_open(state, sid):
		return "pas de fouille ouverte ici"
	if state.system_owner(sid) != empire_id:
		return "il faut posséder le système"
	var d: Dictionary = state.digs[sid]
	if int(d["by"]) == empire_id and int(d["next"]) >= 0:
		return "la fouille est déjà en cours"
	var e := state.get_empire(empire_id)
	var cost: Dictionary = data()["digs"]["start_cost"]
	for r in cost:
		if int(e.resources.get(r, 0)) < int(cost[r]):
			return "pas assez de %s" % GameData.resource_label(String(r)).to_lower()
	return ""


static func start(state: GameState, empire_id: int, sid: int) -> void:
	var e := state.get_empire(empire_id)
	var cost: Dictionary = data()["digs"]["start_cost"]
	for r in cost:
		e.resources[r] = int(e.resources.get(r, 0)) - int(cost[r])
	var d: Dictionary = state.digs[sid]
	d["by"] = empire_id
	d["next"] = state.tick + int(data()["digs"]["phase_days"])
	state.add_chronicle("%s ouvre le chantier de fouilles de %s, à %s." % [e.short_name(), site_name(state, sid), state.galaxy.systems[sid].system_name],
			Espionage.private_to(state, [empire_id], sid))


static func check_clue(state: GameState, empire_id: int, sid: int) -> String:
	if not is_open(state, sid) or int(state.digs[sid]["by"]) != empire_id:
		return "ce n'est pas votre fouille"
	if int(state.digs[sid]["clues"]) >= int(data()["digs"]["clue_max"]):
		return "assez d'indices pour cette phase"
	if fragments(state, empire_id) < int(data()["digs"]["clue_fragments"]):
		return "pas assez de fragments"
	return ""


static func buy_clue(state: GameState, empire_id: int, sid: int) -> void:
	add_fragments(state, empire_id, -int(data()["digs"]["clue_fragments"]))
	state.digs[sid]["clues"] = int(state.digs[sid]["clues"]) + 1


## Chaque jour : reprise par un conquérant, pillage des hordes, jets de fin de phase.
static func daily_digs(state: GameState, added: Array[Dictionary]) -> void:
	var keys := state.digs.keys()
	keys.sort()
	for k in keys:
		var sid := int(k)
		var d: Dictionary = state.digs[sid]
		if int(d["done"]) >= 0 or int(d["by"]) < 0:
			continue
		var owner := state.system_owner(sid)
		if owner != int(d["by"]):
			# Un conquérant reprend la fouille où elle en est ; un système perdu sans repreneur la met en pause.
			if owner >= 0 and not GameState.is_npc(owner):
				d["by"] = owner
				d["next"] = maxi(int(d["next"]), state.tick + 1) if int(d["next"]) >= 0 else state.tick + int(data()["digs"]["phase_days"])
				added.append(state.add_chronicle("%s reprend la fouille de %s là où elle en était." % [state.get_empire(owner).short_name(), site_name(state, sid)],
						Espionage.private_to(state, [owner], sid)))
			else:
				d["next"] = -1
				continue
		if posmod(state.tick, 30) == 0:
			_pillage(state, sid, added)
		if int(d["next"]) < 0 or state.tick < int(d["next"]) or state.battles.has(sid):
			continue
		_roll(state, sid, added)


static func _roll(state: GameState, sid: int, added: Array[Dictionary]) -> void:
	var d: Dictionary = state.digs[sid]
	var eid := int(d["by"])
	var dg: Dictionary = data()["digs"]
	var dice := 1 + _h(state, ["jet", sid, state.tick]) % 10
	var total := dice + int(d["clues"]) + skill(state, eid, sid) - difficulty(state, sid)
	d["next"] = state.tick + int(dg["phase_days"])
	var who := Espionage.private_to(state, [eid], sid)
	if total >= int(dg["success_at"]):
		d["ch"] = int(d["ch"]) + 1
		d["clues"] = 0
		if int(d["ch"]) >= int(d["chapters"]):
			_finish(state, sid, added)
			return
		add_fragments(state, eid, int(dg["chapter_fragments"]))
		var texts: Array = dg["chapter_texts"]
		added.append(state.add_chronicle("Fouilles de %s, chapitre %d sur %d : %s (+%d fragments)" % [site_name(state, sid), int(d["ch"]), int(d["chapters"]),
				String(texts[(int(d["ch"]) - 1) % texts.size()]), int(dg["chapter_fragments"])], who))
	elif total <= int(dg["incident_at"]):
		d["clues"] = 0
		var inc: Array = dg["incidents"]
		var text := String(inc[_h(state, ["incident", sid, state.tick]) % inc.size()])
		var h := Heroes.at_post(state, "system", sid, eid)
		if not h.is_empty() and _h(state, ["blessure", sid, state.tick]) % 100 < int(dg["wound_pct"]):
			var out: Array[Dictionary] = []
			Heroes._wound(state, h, out, "blessé dans un éboulement")
			added.append_array(out)
		added.append(state.add_chronicle("Fouilles de %s : %s" % [site_name(state, sid), text], who))
	else:
		d["clues"] = mini(int(dg["clue_max"]), int(d["clues"]) + 1)


## Dernier chapitre : la relique sort de terre, avec des fragments.
static func _finish(state: GameState, sid: int, added: Array[Dictionary]) -> void:
	var d: Dictionary = state.digs[sid]
	var eid := int(d["by"])
	var e := state.get_empire(eid)
	d["done"] = eid
	d["next"] = -1
	var rid := String(d["relic"])
	add_fragments(state, eid, int(data()["digs"]["final_fragments"]))
	gain(state, eid, rid)
	Guardians.on_dig_finished(state, sid, eid, added)
	Research.count_stat(state, eid, "digs")
	added.append(state.add_chronicle("%s achève les fouilles de %s et en remonte %s. Les archéologues pleurent ; les comptables aussi, mais de joie." % [
			e.display_name(), site_name(state, sid), String(def(rid)["name"])], Espionage.public_to(state, [eid])))


## Horde : une flotte armée d'une horde en guerre avec le fouilleur, à l'arrêt sur le site, pille.
static func _pillage(state: GameState, sid: int, added: Array[Dictionary]) -> void:
	var d: Dictionary = state.digs[sid]
	var eid := int(d["by"])
	for fid in state.sorted_fleet_ids():
		var f: Fleet = state.fleets[fid]
		if f.system_id != sid or f.is_moving() or GameState.is_npc(f.owner) or f.owner == eid or not Combat.is_armed(f):
			continue
		if not Combat.at_war(state, f.owner, eid) or Events.layer_value(state, f.owner, "gouvernement") != "horde":
			continue
		d["clues"] = 0
		var n := mini(fragments(state, eid), int(data()["digs"]["pillage_fragments"]))
		add_fragments(state, eid, -n)
		add_fragments(state, f.owner, int(data()["digs"]["pillage_fragments"]))
		d["pillage"] = state.tick
		added.append(state.add_chronicle("%s pille le chantier de %s : les indices partent en fumée, les trouvailles en soute." % [
				state.get_empire(f.owner).short_name(), site_name(state, sid)], Espionage.private_to(state, [eid, f.owner], sid)))
		return


# --- Reliques -----------------------------------------------------------------------------------

static func gain(state: GameState, empire_id: int, rid: String) -> void:
	var r: Dictionary = state.relics[rid]
	r["owner"] = empire_id
	r["hero"] = -1
	r["found"] = state.tick
	r["ready"] = 0
	Research.count_stat(state, empire_id, "relics")
	Research.count_stat(state, empire_id, "collection")
	touch(state)
	# Une relique sainte peut révéler une grande foi (voir Faiths).
	if is_holy(rid) and state.faith_on:
		Faiths.reveal(state, empire_id, "relique", -1, [] as Array[Dictionary])


## Reliques de l'empire, triées (au Reliquaire ou portées par un héros).
static func owned(state: GameState, empire_id: int) -> Array[String]:
	var out: Array[String] = []
	for id in ids():
		if int(state.relics.get(id, {}).get("owner", -1)) == empire_id:
			out.append(id)
	return out


static func in_reliquary(state: GameState, empire_id: int) -> Array[String]:
	var out: Array[String] = []
	for id in owned(state, empire_id):
		if int(state.relics[id]["hero"]) < 0:
			out.append(id)
	return out


static func is_quest(rid: String) -> bool:
	return (def(rid).get("tags", []) as Array).has("quete")


## Trophée de gardien (tag « trophee ») : ne s'obtient qu'en l'abattant.
static func is_trophy(rid: String) -> bool:
	return (def(rid).get("tags", []) as Array).has("trophee")


static func is_holy(rid: String) -> bool:
	return (def(rid).get("tags", []) as Array).has("sainte")


## Foi : les reliques saintes comptent une fois et demie.
static func holy_mult(state: GameState, empire_id: int, rid: String) -> int:
	if is_holy(rid) and Events.layer_value(state, empire_id, "credo") == "foi":
		return int(rules()["holy_mult_pct"])
	return 100


## Effets des reliques et du Triomphe en cours, au format des technologies (ajoutés par Research.effects).
static func effects(state: GameState, empire_id: int) -> Dictionary:
	var out := {}
	if state.relics.is_empty():
		return out
	for rid in owned(state, empire_id):
		_merge_scaled(out, def(rid).get("fx", {}), holy_mult(state, empire_id, rid))
	if state.relic_meta.has(empire_id):
		var m: Dictionary = state.relic_meta[empire_id]
		if String(m["tri"]) != "" and int(m["until"]) > state.tick:
			_merge_scaled(out, (def(String(m["tri"]))["triumph"] as Dictionary).get("fx", {}), 100)
	return out


static func _merge_scaled(into: Dictionary, fx: Dictionary, pct: int) -> void:
	for k in fx:
		var v: Variant = fx[k]
		if v is Dictionary:
			var sub: Dictionary = into.get(k, {})
			_merge_scaled(sub, v, pct)
			into[k] = sub
		else:
			@warning_ignore("integer_division")
			into[k] = int(into.get(k, 0)) + int(v) * pct / 100


## Coût du Triomphe : influence, dont jusqu'à la moitié payable en fragments.
static func triumph_cost(rid: String) -> int:
	return int(def(rid)["triumph"]["cost"])


static func triumph_split(state: GameState, empire_id: int, rid: String) -> Array[int]:
	var cost := triumph_cost(rid)
	var rate := int(data()["fragments"]["triumph_rate"])
	@warning_ignore("integer_division")
	var frag := mini(fragments(state, empire_id), cost / 2 / rate)
	return [cost - frag * rate, frag]


static func check_triumph(state: GameState, empire_id: int, rid: String) -> String:
	var r: Dictionary = state.relics.get(rid, {})
	if r.is_empty() or int(r["owner"]) != empire_id:
		return "cette relique n'est pas à vous"
	if int(r["ready"]) > state.tick:
		return "Triomphe en recharge (encore %d ans)" % ceili(float(int(r["ready"]) - state.tick) / 360.0)
	var m := meta(state, empire_id)
	if String(m["tri"]) != "" and int(m["until"]) > state.tick:
		return "un Triomphe est déjà en cours"
	var split := triumph_split(state, empire_id, rid)
	if int(state.get_empire(empire_id).resources.get("influence", 0)) < split[0]:
		return "pas assez d'influence"
	return ""


static func triumph(state: GameState, empire_id: int, rid: String, added: Array[Dictionary]) -> void:
	var e := state.get_empire(empire_id)
	var t: Dictionary = def(rid)["triumph"]
	var split := triumph_split(state, empire_id, rid)
	e.resources["influence"] = int(e.resources.get("influence", 0)) - split[0]
	add_fragments(state, empire_id, -split[1])
	# Loi « Processions » : les Triomphes reviennent plus vite.
	state.relics[rid]["ready"] = state.tick + Research.scaled(int(rules()["triumph_cooldown"]), Research.fx_int(state, empire_id, "triumph_cooldown_pct"))
	var m := meta(state, empire_id)
	if int(t.get("days", 0)) > 0:
		m["tri"] = rid
		m["until"] = state.tick + int(t["days"])
	var item := {"id": -1, "card": "", "system": -1, "planet": -1, "rival": -1, "hero": int(state.relics[rid]["hero"])}
	Events.apply_fx(state, empire_id, item, t.get("now", []), added)
	if is_holy(rid) and FactionTraits.has_fervor(e.faction()):
		e.fervor = mini(int(e.faction()["fervor"].get("max", 100)), e.fervor + int(rules()["holy_triumph_fervor"]))
	touch(state)
	Research.count_stat(state, empire_id, "triumphs")
	added.append(state.add_chronicle("%s célèbre le Triomphe de %s : %s. Les foules se pressent, les marchands de souvenirs aussi." % [
			e.display_name(), String(def(rid)["name"]), String(t["label"]).to_lower()], Espionage.public_to(state, [empire_id])))


## Effets du Triomphe en texte (pour l'interface).
static func triumph_text(state: GameState, empire_id: int, rid: String) -> String:
	var t: Dictionary = def(rid)["triumph"]
	var parts := PackedStringArray()
	var fx_t := fx_text(t.get("fx", {}))
	if fx_t != "":
		parts.append("%s pendant %s" % [fx_t, _days_text(int(t.get("days", 0)))])
	var item := {"id": -1, "card": "", "system": -1, "planet": -1, "rival": -1, "hero": -1}
	for l in Events.fx_lines(state, empire_id, item, t.get("now", [])):
		parts.append(l)
	return ", ".join(parts)


static func _days_text(days: int) -> String:
	if days >= 360 and days % 360 == 0:
		@warning_ignore("integer_division")
		return "%d an%s" % [days / 360, "s" if days >= 720 else ""]
	return "%d jours" % days


const FX_LABELS := {"stability": "stabilité %+d", "damage_pct": "dégâts %+d %%", "growth_pct": "croissance %+d %%",
	"fleet_speed_pct": "vitesse des flottes %+d %%", "ship_cost_pct": "coût des vaisseaux %+d %%", "opinion_all": "opinion de tous %+d",
	"trade_income_pct": "commerce %+d %%", "building_cost_pct": "coût des bâtiments %+d %%", "ship_days_pct": "durée de construction des vaisseaux %+d %%",
	"troops_pct": "troupes %+d %%", "curio_detect": "détection des curiosités %+d", "curio_power": "puissance d'expédition %+d",
	"council_seats": "sièges au conseil %+d", "repair_pct": "réparations %+d %%", "upkeep_pct": "entretien %+d %%",
	"claim_vision": "vision des revendications", "garrison_pct": "garnisons %+d %%"}


## « Énergie +8 %, stabilité +4 » à partir d'effets au format des technologies.
static func fx_text(fx: Dictionary, pct := 100) -> String:
	var parts := PackedStringArray()
	var keys := fx.keys()
	keys.sort()
	for k in keys:
		var v: Variant = fx[k]
		match String(k):
			"production_pct":
				for r in v:
					@warning_ignore("integer_division")
					var n := int(v[r]) * pct / 100
					parts.append("%s %+d %%" % ["production" if String(r) == "all" else GameData.resource_label(String(r)), n])
			"defense_pct":
				var lbl := {"armor": "blindage", "shield": "boucliers", "pd": "défense rapprochée"}
				for s in v:
					@warning_ignore("integer_division")
					parts.append("%s %+d %%" % [lbl.get(s, s), int(v[s]) * pct / 100])
			"hab_bonus":
				parts.append("habitabilité %+d" % int((v as Dictionary).get("all", 0)))
			_:
				@warning_ignore("integer_division")
				var n := int(v) * pct / 100
				var f := String(FX_LABELS.get(k, String(k) + " %+d"))
				parts.append(f % n if f.find("%") >= 0 else f)
	return ", ".join(parts)


# --- Porteurs, vols, dons, ventes ----------------------------------------------------------------

static func check_assign(state: GameState, empire_id: int, rid: String, hero_id: int) -> String:
	var r: Dictionary = state.relics.get(rid, {})
	if r.is_empty() or int(r["owner"]) != empire_id:
		return "cette relique n'est pas à vous"
	if hero_id < 0:
		return "" if int(r["hero"]) >= 0 else "déjà au Reliquaire"
	var h: Dictionary = state.heroes.get(hero_id, {})
	if h.is_empty() or int(h["owner"]) != empire_id or Heroes.is_prisoner(h):
		return "héros indisponible"
	for id in owned(state, empire_id):
		if int(state.relics[id]["hero"]) == hero_id:
			return "ce héros porte déjà une relique"
	return ""


static func assign(state: GameState, rid: String, hero_id: int) -> void:
	state.relics[rid]["hero"] = hero_id


static func bearer_of(state: GameState, hero_id: int) -> String:
	for id in ids():
		if int(state.relics.get(id, {}).get("hero", -1)) == hero_id:
			return id
	return ""


## Un héros capturé perd sa relique au profit de son geôlier (les pirates la revendent au marché noir).
static func on_hero_captured(state: GameState, h: Dictionary, captor: int) -> void:
	var rid := bearer_of(state, int(h["id"]))
	if rid == "":
		return
	if GameState.is_npc(captor):
		state.relics[rid]["owner"] = MARKET
		state.relics[rid]["hero"] = -1
	else:
		steal(state, captor, rid)
	touch(state)


## Un héros mort : sa relique rentre au Reliquaire.
static func on_hero_gone(state: GameState, hero_id: int) -> void:
	var rid := bearer_of(state, hero_id)
	if rid != "":
		state.relics[rid]["hero"] = -1


## Une relique du Reliquaire au hasard (déterministe), "" s'il n'y en a pas.
static func pick_reliquary(state: GameState, empire_id: int, salt: Array) -> String:
	var list := in_reliquary(state, empire_id)
	if list.is_empty():
		return ""
	return list[_h(state, ["pick"] + salt) % list.size()]


## Vol : la relique passe à thief ; exploit Picaresque.
static func steal(state: GameState, thief: int, rid: String) -> void:
	gain(state, thief, rid)
	Research.count_stat(state, thief, "relics_stolen")
	Reputation.exploit(state, thief, "relique_" + rid)


## Prise d'une capitale : chance de voler une relique du Reliquaire (plus pour une horde).
static func on_capital_lost(state: GameState, victim: int, taker: int, added: Array[Dictionary]) -> void:
	if state.relics.is_empty() or GameState.is_npc(taker) or GameState.is_npc(victim):
		return
	var pct := int(rules()["steal_capital_horde_pct"]) if Events.layer_value(state, taker, "gouvernement") == "horde" else int(rules()["steal_capital_pct"])
	if _h(state, ["capitale", victim, taker, state.tick]) % 100 >= pct:
		return
	var rid := pick_reliquary(state, victim, ["capitale", state.tick])
	if rid == "":
		return
	steal(state, taker, rid)
	added.append(state.add_chronicle("Dans les caves de la capitale de %s, %s trouve %s et l'emporte, avec ses vitrines." % [
			state.get_empire(victim).short_name(), state.get_empire(taker).short_name(), String(def(rid)["name"])], Espionage.public_to(state, [victim, taker])))


## Réseau retourné : l'espion croit voler une relique ; c'est une copie, sans effet, qui se révèle un an après.
static func give_fake(state: GameState, a: int, b: int) -> String:
	var rid := pick_reliquary(state, b, ["faux", a, state.tick])
	if rid == "":
		return ""
	(meta(state, a)["fakes"] as Array).append({"relic": rid, "until": state.tick + int(rules()["fake_days"])})
	return rid


static func check_gift(state: GameState, empire_id: int, rid: String, to: int) -> String:
	var r: Dictionary = state.relics.get(rid, {})
	if r.is_empty() or int(r["owner"]) != empire_id:
		return "cette relique n'est pas à vous"
	return _gift_target_problem(state, empire_id, to)


static func _gift_target_problem(state: GameState, empire_id: int, to: int) -> String:
	var t := state.get_empire(to)
	if t == null or t.eliminated or t.is_npc() or to == empire_id:
		return "destinataire inconnu"
	if not state.get_empire(empire_id).contacts.has(to):
		return "empire jamais rencontré"
	if Combat.at_war(state, empire_id, to):
		return "on n'offre rien à un ennemi"
	return ""


static func gift(state: GameState, empire_id: int, rid: String, to: int, added: Array[Dictionary]) -> void:
	gain(state, to, rid)
	Diplomacy.remember(state, to, empire_id, String(rules()["gift_memory"]))
	added.append(state.add_chronicle("%s offre %s à %s. Le cadeau est apprécié ; la facture, elle, reste chez le donateur." % [
			state.get_empire(empire_id).short_name(), String(def(rid)["name"]), state.get_empire(to).short_name()], Espionage.public_to(state, [empire_id, to])))


static func check_gift_fragments(state: GameState, empire_id: int, to: int) -> String:
	if fragments(state, empire_id) < int(data()["fragments"]["gift_lot"]):
		return "pas assez de fragments"
	return _gift_target_problem(state, empire_id, to)


static func gift_fragments(state: GameState, empire_id: int, to: int) -> void:
	var n := int(data()["fragments"]["gift_lot"])
	add_fragments(state, empire_id, -n)
	add_fragments(state, to, n)
	Diplomacy.remember(state, to, empire_id, "ev_gift")


## Profit : vendre des fragments, ou une relique au marché noir.
static func can_trade(state: GameState, empire_id: int) -> bool:
	return Events.layer_value(state, empire_id, "credo") == "profit"


static func check_sell_fragments(state: GameState, empire_id: int) -> String:
	if not can_trade(state, empire_id):
		return "seul un peuple du Profit tient boutique"
	if fragments(state, empire_id) < int(data()["fragments"]["sell_lot"]):
		return "pas assez de fragments"
	return ""


static func sell_fragments(state: GameState, empire_id: int) -> void:
	var fr: Dictionary = data()["fragments"]
	add_fragments(state, empire_id, -int(fr["sell_lot"]))
	var e := state.get_empire(empire_id)
	e.resources["energy"] = int(e.resources.get("energy", 0)) + Events.era_scaled(state, empire_id, int(fr["sell_energy"]))


static func check_sell(state: GameState, empire_id: int, rid: String) -> String:
	if not can_trade(state, empire_id):
		return "seul un peuple du Profit tient boutique"
	var r: Dictionary = state.relics.get(rid, {})
	if r.is_empty() or int(r["owner"]) != empire_id:
		return "cette relique n'est pas à vous"
	return ""


static func sell(state: GameState, empire_id: int, rid: String, added: Array[Dictionary]) -> void:
	var e := state.get_empire(empire_id)
	e.resources["energy"] = int(e.resources.get("energy", 0)) + Events.era_scaled(state, empire_id, int(rules()["sell_energy"]))
	e.resources["influence"] = int(e.resources.get("influence", 0)) + int(rules()["sell_influence"])
	state.relics[rid]["owner"] = MARKET
	state.relics[rid]["hero"] = -1
	touch(state)
	added.append(state.add_chronicle("%s vend %s au marché noir. Elle réapparaîtra sans doute un jour, dans une ruine bien commode." % [
			e.short_name(), String(def(rid)["name"])], Espionage.private_to(state, [empire_id])))


## Honneur : vaincre plus fort que soi rapporte un trophée (des fragments).
static func on_battle(state: GameState, b: Dictionary, winner: int, added: Array[Dictionary]) -> void:
	if winner < 0 or GameState.is_npc(winner) or state.relics.is_empty():
		return
	# Épaves : quelques fragments dans les carcasses ennemies (un par vaisseau détruit, dix au plus).
	var wrecks := 0
	for s: Dictionary in b["sides"]:
		if int(s["empire"]) != winner:
			wrecks += Combat.count_ships(s["lost"])
	add_fragments(state, winner, mini(10, wrecks))
	if Events.layer_value(state, winner, "credo") != "honneur":
		return
	var own := 0
	var foes := 0
	for s: Dictionary in b["sides"]:
		var power := 0
		for ship in s["engaged"]:
			power += Combat.ship_strength(String(ship)) * int(s["engaged"][ship])
		if int(s["empire"]) == winner:
			own += power
		elif Combat.at_war(state, winner, int(s["empire"])):
			foes += power
	if own <= 0 or foes <= own:
		return
	add_fragments(state, winner, int(rules()["trophy_fragments"]))
	Research.count_stat(state, winner, "trophies")
	added.append(state.add_chronicle("%s rapporte un trophée de sa victoire contre plus fort que lui (+%d fragments). Il trône déjà au Reliquaire, entre deux reliques jalouses." % [
			state.get_empire(winner).short_name(), int(rules()["trophy_fragments"])], Espionage.private_to(state, [winner])))


## Chaque mois : porteurs (expérience, renom), fausses reliques démasquées, fin des Triomphes.
static func daily(state: GameState, added: Array[Dictionary]) -> void:
	if state.relics.is_empty():
		return
	daily_digs(state, added)
	var mkeys := state.relic_meta.keys()
	mkeys.sort()
	for k in mkeys:
		var m: Dictionary = state.relic_meta[k]
		if String(m["tri"]) != "" and int(m["until"]) <= state.tick:
			m["tri"] = ""
			touch(state)
		var fakes: Array = m["fakes"]
		var i := 0
		while i < fakes.size():
			if int(fakes[i]["until"]) <= state.tick:
				var rid := String(fakes[i]["relic"])
				fakes.remove_at(i)
				added.append(state.add_chronicle("%s a fini par comprendre : sa %s était une copie, et les experts qui l'avaient authentifiée ont changé de nom." % [
						state.get_empire(int(k)).short_name(), String(def(rid)["name"])], Espionage.private_to(state, [int(k)])))
				continue
			i += 1
	if posmod(state.tick, 30) != 0:
		return
	for id in ids():
		var r: Dictionary = state.relics[id]
		var hid := int(r["hero"])
		if hid < 0:
			continue
		var h: Dictionary = state.heroes.get(hid, {})
		if h.is_empty() or int(h["owner"]) != int(r["owner"]):
			r["hero"] = -1
			continue
		if not Heroes.is_prisoner(h):
			Heroes.gain_xp(state, h, int(rules()["bearer_xp"]))
			Heroes.act(state, int(r["owner"]), "relic_borne")


# --- Sauvegarde ----------------------------------------------------------------------------------

static func to_dict(state: GameState) -> Dictionary:
	var digs := []
	var keys := state.digs.keys()
	keys.sort()
	for sid in keys:
		var d: Dictionary = (state.digs[sid] as Dictionary).duplicate()
		d["sid"] = int(sid)
		digs.append(d)
	var metas := []
	var mk := state.relic_meta.keys()
	mk.sort()
	for k in mk:
		var m: Dictionary = (state.relic_meta[k] as Dictionary).duplicate(true)
		m["e"] = int(k)
		metas.append(m)
	return {"digs": digs, "relics": state.relics.duplicate(true), "meta": metas}


static func from_dict(state: GameState, d: Dictionary) -> void:
	state.digs.clear()
	state.relics.clear()
	state.relic_meta.clear()
	for x: Dictionary in d.get("digs", []):
		var site: Dictionary = GameData._to_ints(x)
		site["relic"] = String(x["relic"])
		var sid := int(site["sid"])
		site.erase("sid")
		state.digs[sid] = site
	var rel: Dictionary = d.get("relics", {})
	for id in rel:
		state.relics[String(id)] = GameData._to_ints(rel[id])
	for x: Dictionary in d.get("meta", []):
		var fakes: Array = []
		for f: Dictionary in x.get("fakes", []):
			fakes.append({"relic": String(f["relic"]), "until": int(f["until"])})
		state.relic_meta[int(x["e"])] = {"frag": int(x.get("frag", 0)), "tri": String(x.get("tri", "")), "until": int(x.get("until", 0)), "fakes": fakes}
