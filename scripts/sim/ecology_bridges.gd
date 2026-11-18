class_name EcologyBridges
extends RefCounted
## L'écologie et le reste du jeu (extensions 15 à 30 de l'étude, validées le 2026-11-18 ; voir Ecology,
## données : section « _doc_ext » de data/ecology.json). La prop. 27 (la biosphère pèse sur l'humeur
## d'un monde vivant) est portée par LivingWorlds.
##
## 15 catastrophes selon le climat ; 16 mégastructures énergétiques qui allègent les centrales ;
## 17 démantèlement qui blesse les biosphères du système ; 18 réfugiés climatiques ; 19 trait d'espèce
## Tolérance (champ de faction eco_tolerant) ; 20 précepte Sacralité du vivant ; 21 famille Biosphères
## de l'Amphictyonie ; 22 opération Sabotage écologique ; 23 siège et terre brûlée ; 24 Monde-usine ;
## 25 hauts faits ; 26 événements écologiques ; 28 biosphères remarquables ; 29 opinion entre doctrines ;
## 30 teinte de la planète dans la vue système.
##
## État (dans state.ecology) : "cat" {pid: [fin, type de catastrophe]}, "factory" {pid: 1},
## "sabot" {pid: fin}, "rem" {pid: 1}, "flee" {pid: mois}, "anger" {eid: fin},
## "stat" {eid: {"regreen", "shift", "scorched", "cat"}}.

const SUBS := ["cat", "factory", "sabot", "rem", "flee", "anger", "stat"]


static func cfg(section: String) -> Dictionary:
	return Ecology.data().get(section, {})


static func c_int(section: String, key: String, def := 0) -> int:
	return int(cfg(section).get(key, def))


static func _h(state: GameState, parts: Array) -> int:
	return absi(hash([state.seed_value, "ecologie"] + parts))


# --- Statistiques (hauts faits, prop. 25) -------------------------------------------------------

static func stat(state: GameState, eid: int, key: String) -> int:
	if not Ecology.enabled(state):
		return 0
	return int((Ecology.sub(state, "stat").get(str(eid), {}) as Dictionary).get(key, 0))


static func _add_stat(state: GameState, eid: int, key: String, n := 1) -> void:
	if eid < 0 or GameState.is_npc(eid):
		return
	var st := Ecology.sub(state, "stat")
	var me: Dictionary = st.get(str(eid), {})
	me[key] = int(me.get(key, 0)) + n
	st[str(eid)] = me


# --- Biosphères remarquables (prop. 28) ---------------------------------------------------------

## À la création de la partie : environ un monde vivant sur six porte une vie indigène riche (jamais
## un monde déjà colonisé).
static func pick_remarkable(state: GameState) -> void:
	var one_in := maxi(1, c_int("remarkable", "one_in", 6))
	var rem := Ecology.sub(state, "rem")
	for s in state.galaxy.systems:
		for pid in s.planet_ids:
			var p := state.galaxy.get_planet(pid)
			if p == null or state.colonies.has(pid):
				continue  # les mondes natals ne sont jamais remarquables (départs égaux)
			if Ecology.living_type(p.type) and p.type != "gaia" and _h(state, ["rem", pid]) % one_in == 0:
				rem[str(pid)] = 1


static func remarkable(state: GameState, pid: int) -> bool:
	return Ecology.enabled(state) and Ecology.sub(state, "rem").has(str(pid))


## Vitalité en plus d'un monde remarquable.
static func vitality_bonus(state: GameState, pid: int) -> int:
	return c_int("remarkable", "vitality", 20) if remarkable(state, pid) else 0


# --- Monde-usine (prop. 24) ---------------------------------------------------------------------

static func is_factory(state: GameState, pid: int) -> bool:
	return Ecology.enabled(state) and Ecology.sub(state, "factory").has(str(pid))


static func check_factory(state: GameState, eid: int, pid: int) -> String:
	var c: Colony = state.colonies.get(pid)
	if c == null or c.owner != eid or not c.is_established() or not c.is_colony():
		return "seulement sur une de vos colonies"
	if is_factory(state, pid):
		return "c'est déjà un monde-usine"
	if not Ecology.has_biosphere(state, pid):
		return "ce monde n'a pas de biosphère à sacrifier"
	var p := state.galaxy.get_planet(pid)
	var f := cfg("factory")
	if not (f.get("from_types", []) as Array).has(p.type) and String(Ecology.tier(state, pid).get("id", "")) != String(f.get("from_tier", "effondree")):
		return "seulement sur un monde toxique ou à la biosphère effondrée"
	return ""


static func make_factory(state: GameState, eid: int, pid: int) -> void:
	var p := state.galaxy.get_planet(pid)
	for s in ["bio", "low", "high", "warn"]:
		Ecology.sub(state, s).erase(str(pid))
	for s in ["cat", "sabot", "flee"]:
		Ecology.sub(state, s).erase(str(pid))
	Ecology.sub(state, "factory")[str(pid)] = 1
	var e := state.get_empire(eid)
	state.add_chronicle("%s fait de %s un monde-usine : on ne sauvera plus son ciel, on le remplira de cheminées. La production y gagne ce que les poumons y perdent." % [
			e.short_name(), p.display_name(state.galaxy)], Espionage.private_to(state, [eid], p.system_id))


# --- Terre brûlée (prop. 23) --------------------------------------------------------------------

static func evacuating(state: GameState, pid: int) -> bool:
	if state.forge.is_empty():
		return false
	for id in WorldForge.job_ids(state):
		var j := WorldForge.get_job(state, id)
		if String(j.get("op", "")) == "evacuer" and int(j.get("p", -1)) == pid:
			return true
	return false


static func check_scorch(state: GameState, eid: int, pid: int) -> String:
	var c: Colony = state.colonies.get(pid)
	if c == null or c.owner != eid or not c.is_established():
		return "seulement sur une de vos colonies"
	if not Ecology.has_biosphere(state, pid):
		return "ce monde n'a pas de biosphère"
	if Ecology.health(state, pid) <= 0:
		return "il n'y a plus rien à brûler"
	var p := state.galaxy.get_planet(pid)
	if not evacuating(state, pid) and not Combat.is_besieged(state, p.system_id):
		return "seulement sur un monde en cours d'évacuation ou assiégé"
	return ""


static func scorch(state: GameState, eid: int, pid: int) -> void:
	var p := state.galaxy.get_planet(pid)
	Ecology._set_health(state, pid, 0)
	if Ecology.full(state) and Ecology.data().get("shift", {}).has(p.type):
		Ecology.sub(state, "low")[str(pid)] = maxi(0, Ecology.rule("shift_months", 24) - 1)
		Ecology.sub(state, "warn")[str(pid)] = 1
	_add_stat(state, eid, "scorched")
	var e := state.get_empire(eid)
	state.add_chronicle("%s pratique la terre brûlée sur %s : forêts rasées, nappes empoisonnées. Ce qu'on ne peut garder, l'ennemi ne l'aura pas non plus." % [
			e.short_name(), p.display_name(state.galaxy)], Espionage.public_to(state, [eid]))


# --- Empreinte (props. 16, 22, 28) --------------------------------------------------------------

## Mégastructures énergétiques achevées de l'empire (prop. 16).
static func energy_megas(state: GameState, eid: int) -> int:
	if state.megas.is_empty() or eid < 0:
		return 0
	var kinds: Array = cfg("kardashev").get("kinds", [])
	var n := 0
	for m in Megastructures.owned_by(state, eid):
		if kinds.has(String(m["k"])) and Megastructures.complete(m):
			n += 1
	return n


## Poids d'une centrale allégé par les mégastructures énergétiques (en %, 100 = intact).
static func plant_pct(state: GameState, eid: int, bid: String) -> int:
	if not (cfg("kardashev").get("buildings", []) as Array).has(bid):
		return 100
	var n := energy_megas(state, eid)
	if n <= 0:
		return 100
	return maxi(c_int("kardashev", "min_pct", 25), 100 + n * c_int("kardashev", "per_mega_pct", -25))


## Postes d'empreinte en plus : sabotage en cours (prop. 22).
static func extra_parts(state: GameState, pid: int) -> Array:
	var out: Array = []
	var sb := Ecology.sub(state, "sabot")
	if sb.has(str(pid)) and int(sb[str(pid)]) > state.tick:
		out.append(["Sabotage écologique", c_int("spy", "footprint", 12)])
	return out


## Multiplicateur d'empreinte propre au monde (biosphère remarquable : plus fragile).
static func world_pct(state: GameState, pid: int) -> int:
	return c_int("remarkable", "footprint_pct", 150) if remarkable(state, pid) else 100


# --- Rendements (props. 15, 19, 24, 28) ---------------------------------------------------------

static func tolerant(state: GameState, eid: int) -> bool:
	var e := state.get_empire(eid)
	return e != null and not e.is_npc() and bool(e.faction().get("eco_tolerant", false))


@warning_ignore("integer_division")
static func adjust_yields(state: GameState, c: Colony, gross: Dictionary) -> void:
	var pid := c.planet_id
	var k := str(pid)
	if is_factory(state, pid):
		var fp := c_int("factory", "yield_pct", 25)
		for r in ["materials", "energy"]:
			if int(gross.get(r, 0)) > 0:
				gross[r] = int(gross[r]) * (100 + fp) / 100
	var cat := Ecology.sub(state, "cat")
	if cat.has(k) and int((cat[k] as Array)[0]) > state.tick:
		var yp := c_int("catastrophes", "yield_pct", -25)
		for r in ["food", "materials", "energy"]:
			if int(gross.get(r, 0)) > 0:
				gross[r] = int(gross[r]) * (100 + yp) / 100
	if remarkable(state, pid) and c.is_colony() and Ecology.health(state, pid) >= c_int("remarkable", "min_health", 60):
		gross["knowledge"] = int(gross.get("knowledge", 0)) + c_int("remarkable", "knowledge", 3)


# --- Stabilité (props. 20, 24) ------------------------------------------------------------------

static func _precept_holder(state: GameState, eid: int) -> bool:
	if not state.faith_on:
		return false
	var fid := Faiths.state_faith(state, eid)
	return fid != "" and Faiths.has_precept(state, fid, String(cfg("faith").get("precept", "sacralite_vivant")))


static func stability_parts(state: GameState, sid: int, owner: int) -> Array:
	var out: Array = []
	var factory := false
	var bloom := false
	var living := false
	for pid in state.galaxy.systems[sid].planet_ids:
		var c: Colony = state.colonies.get(pid)
		if c == null or c.owner != owner or not c.is_established():
			continue
		if is_factory(state, pid) and c.is_colony():
			factory = true
		if Ecology.has_biosphere(state, pid):
			living = true
			if String(Ecology.tier(state, pid).get("id", "")) == "florissante":
				bloom = true
	if factory:
		var fs := c_int("factory", "stab", -10)
		if Amphictyony.is_member(state, owner) and Amphictyony.level_sum(state, "eco_factory_free") > 0:
			fs = 0
		if fs != 0:
			out.append(["Monde-usine", fs])
	if _precept_holder(state, owner):
		if bloom:
			out.append(["Sacralité du vivant : monde florissant", c_int("faith", "bloom_stab", 3)])
		var an := Ecology.sub(state, "anger")
		if living and an.has(str(owner)) and int(an[str(owner)]) > state.tick:
			out.append(["Sacralité du vivant : un monde a basculé", c_int("faith", "anger_stab", -5)])
	return out


# --- Le mois (props. 15, 18, 21, 23) ------------------------------------------------------------

## Appelé par Ecology.monthly pour chaque colonie à biosphère, après le glissement de la jauge.
static func colony_monthly(state: GameState, c: Colony, added: Array[Dictionary]) -> void:
	var pid := c.planet_id
	var p := state.galaxy.get_planet(pid)
	if Combat.is_besieged(state, p.system_id):
		Ecology._set_health(state, pid, Ecology.health(state, pid) - c_int("siege", "monthly", 5))
	_catastrophe(state, c, added)
	_refugees(state, c, added)


static func _catastrophe(state: GameState, c: Colony, added: Array[Dictionary]) -> void:
	var pid := c.planet_id
	var k := str(pid)
	var cat := Ecology.sub(state, "cat")
	if cat.has(k):
		if int((cat[k] as Array)[0]) > state.tick:
			return
		cat.erase(k)
	if not c.is_colony():
		return
	var t := Ecology.tier(state, pid)
	var chance := int((cfg("catastrophes").get("chance_pct", {}) as Dictionary).get(String(t.get("id", "")), 0))
	if chance <= 0 or _h(state, ["cat", pid, state.tick]) % 100 >= chance:
		return
	var p := state.galaxy.get_planet(pid)
	var kd: Dictionary = (cfg("catastrophes").get("kinds", {}) as Dictionary).get(p.type, {})
	if kd.is_empty():
		return
	var e := state.get_empire(c.owner)
	var pname := p.display_name(state.galaxy)
	var label := String(kd.get("label", "catastrophe"))
	for b in cfg("catastrophes").get("shield", []):
		if c.buildings.has(String(b)):
			added.append(state.add_chronicle("%s : une %s s'abat sur %s, mais le bouclier planétaire tient. On rouvre les volets." % [
					e.short_name(), label, pname], Espionage.private_to(state, [c.owner], p.system_id)))
			return
	_add_stat(state, c.owner, "cat")
	if String(kd.get("hit", "yield")) == "pop" and c.population > 1:
		var cnt := Peoples.counts(state, c)
		var fid := ""
		var best := -1
		for f in Peoples._sorted_keys(cnt):
			if int(cnt[f]) > best:
				best = int(cnt[f])
				fid = f
		if fid != "" and Movements.remove_one(state, c, fid):
			added.append(state.add_chronicle("%s : %s sur %s, un habitant perdu. La biosphère fatiguée ne retient plus les eaux." % [
					e.short_name(), label.substr(0, 1).to_upper() + label.substr(1), pname], Espionage.private_to(state, [c.owner], p.system_id)))
			return
	cat[k] = [state.tick + c_int("catastrophes", "days", 90), p.type]
	added.append(state.add_chronicle("%s : %s sur %s. La production tombe de %d %% pendant trois mois." % [
			e.short_name(), label.substr(0, 1).to_upper() + label.substr(1), pname, -c_int("catastrophes", "yield_pct", -25)], Espionage.private_to(state, [c.owner], p.system_id)))


## Catastrophe en cours sur ce monde ("" sinon) : libellé.
static func catastrophe(state: GameState, pid: int) -> String:
	var cat := Ecology.sub(state, "cat") if Ecology.enabled(state) else {}
	if not cat.has(str(pid)) or int((cat[str(pid)] as Array)[0]) <= state.tick:
		return ""
	var kd: Dictionary = (cfg("catastrophes").get("kinds", {}) as Dictionary).get(String((cat[str(pid)] as Array)[1]), {})
	return String(kd.get("label", "catastrophe"))


static func _refugees(state: GameState, c: Colony, added: Array[Dictionary]) -> void:
	var pid := c.planet_id
	var k := str(pid)
	var fl := Ecology.sub(state, "flee")
	if String(Ecology.tier(state, pid).get("id", "")) != String(cfg("refugees").get("flee_tier", "effondree")) or not c.is_colony():
		fl.erase(k)
		return
	fl[k] = int(fl.get(k, 0)) + 1
	if int(fl[k]) < c_int("refugees", "flee_months", 12) or c.population <= 1:
		return
	fl[k] = 0
	var fid := Movements._leaver(state, c, "")
	if fid != "" and Movements.flee(state, c, fid, 1, [c.owner], added) > 0:
		var p := state.galaxy.get_planet(pid)
		added.append(state.add_chronicle("%s : des réfugiés climatiques quittent %s, dont la terre ne nourrit plus personne." % [
				state.get_empire(c.owner).short_name(), p.display_name(state.galaxy)], Espionage.private_to(state, [c.owner], p.system_id)))


## Migration intérieure (Movements.push_reason) : un monde Dégradé ou Effondré pousse ses habitants.
static func push_reason(state: GameState, c: Colony) -> String:
	if not Ecology.has_biosphere(state, c.planet_id):
		return ""
	if (cfg("refugees").get("push_tiers", []) as Array).has(String(Ecology.tier(state, c.planet_id).get("id", ""))):
		return "climat"
	return ""


## Fin du mois, une fois pour tout l'empire : Convention des biosphères (influence aux plus propres).
static func empire_monthly(state: GameState) -> void:
	if not state.amph_on or not Amphictyony.founded(state):
		return
	var n := Amphictyony.level_sum(state, "eco_clean_influence")
	if n <= 0:
		return
	for eid in Amphictyony.members(state):
		if Ecology.doctrine(state, eid) == "preservation":
			var e := state.get_empire(eid)
			if e != null and not e.eliminated:
				e.resources["influence"] = int(e.resources.get("influence", 0)) + n


# --- Basculement et reverdissement (props. 20, 25) ---------------------------------------------

static func on_shift(state: GameState, eid: int) -> void:
	_add_stat(state, eid, "shift")
	if _precept_holder(state, eid):
		Ecology.sub(state, "anger")[str(eid)] = state.tick + c_int("faith", "anger_days", 360)


static func on_regreen(state: GameState, eid: int) -> void:
	_add_stat(state, eid, "regreen")


# --- Amphictyonie (prop. 21) --------------------------------------------------------------------

## Convention des biosphères : un membre ne peut plus suivre la doctrine Extraction.
static func extraction_banned(state: GameState, eid: int) -> bool:
	return state.amph_on and Amphictyony.is_member(state, eid) and Amphictyony.banned(state, "eco_extraction")


# --- Forge des mondes (prop. 17) ----------------------------------------------------------------

## Un démantèlement achevé : les mondes vivants du système encaissent le choc.
static func on_dismantle(state: GameState, sid: int, added: Array[Dictionary]) -> void:
	if not Ecology.enabled(state):
		return
	var hit := c_int("forge", "dismantle_hit", 20)
	var hurt := 0
	for pid in state.galaxy.systems[sid].planet_ids:
		if Ecology.has_biosphere(state, pid):
			Ecology._set_health(state, pid, Ecology.health(state, pid) - hit)
			hurt += 1
	if hurt > 0:
		added.append(state.add_chronicle("Les débris du démantèlement retombent sur les mondes vivants de %s : %d biosphère%s blessée%s (−%d)." % [
				state.galaxy.systems[sid].system_name, hurt, "" if hurt == 1 else "s", "" if hurt == 1 else "s", hit]))


# --- Renseignement (prop. 22) -------------------------------------------------------------------

static func _sabotage_target(state: GameState, b: int) -> int:
	var best := -1
	var bp := -1
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner == b and c.is_colony() and c.is_established() and Ecology.has_biosphere(state, pid) and c.population > bp:
			bp = c.population
			best = pid
	return best


static func spy_check(state: GameState, _a: int, b: int, _op_id: String) -> String:
	if not Ecology.enabled(state):
		return "l'écologie n'est pas en jeu dans cette partie"
	if _sabotage_target(state, b) < 0:
		return "il n'a aucun monde vivant à saboter"
	return ""


static func spy_apply(state: GameState, _a: int, b: int, _o: Dictionary) -> String:
	var pid := _sabotage_target(state, b)
	if pid < 0:
		return ""
	Ecology.sub(state, "sabot")[str(pid)] = state.tick + c_int("spy", "days", 360)
	return "nos agents ont empoisonné les nappes de %s (%s) : son empreinte pèse %d points de plus pendant un an." % [
			state.galaxy.get_planet(pid).display_name(state.galaxy), state.get_empire(b).display_name(), c_int("spy", "footprint", 12)]


# --- Diplomatie (prop. 29) ----------------------------------------------------------------------

static func opinion_parts(state: GameState, a: int, b: int) -> Array:
	var out := []
	if not Ecology.enabled(state) or GameState.is_npc(a) or GameState.is_npc(b):
		return out
	if Ecology.doctrine(state, a) == "preservation" and Ecology.doctrine(state, b) == "extraction":
		out.append(["Pille ses mondes (doctrine Extraction)", c_int("opinion", "preservation_vs_extraction", -10)])
	return out


# --- Événements (prop. 26) ----------------------------------------------------------------------

## Systèmes de l'empire qui portent un de ses mondes vivants (sujet « living_world »).
static func event_systems(state: GameState, eid: int) -> Array[int]:
	var out: Array[int] = []
	if not Ecology.enabled(state):
		return out
	for pid in Ecology.worlds_of(state, eid):
		var sid := state.galaxy.get_planet(pid).system_id
		if not out.has(sid):
			out.append(sid)
	out.sort()
	return out


static func event_worlds(state: GameState, eid: int, sid: int) -> Array:
	var out: Array = []
	if sid < 0 or not Ecology.enabled(state):
		return out
	for pid in state.galaxy.systems[sid].planet_ids:
		var c: Colony = state.colonies.get(pid)
		if c != null and c.owner == eid and Ecology.has_biosphere(state, pid):
			out.append(pid)
	return out


static func event_fx(state: GameState, eid: int, sid: int, v: int) -> void:
	for pid in event_worlds(state, eid, sid):
		Ecology._set_health(state, pid, Ecology.health(state, pid) + v)


# --- Décor (prop. 30) ---------------------------------------------------------------------------

## Teinte de la planète selon le palier : [Color, part] ou [] si rien à changer.
static func tint(state: GameState, pid: int) -> Array:
	if not Ecology.has_biosphere(state, pid):
		return []
	var d: Dictionary = cfg("decor")
	var t := String(Ecology.tier(state, pid).get("id", ""))
	if not d.has(t):
		return []
	var a: Array = d[t]
	return [Color(float(a[0]), float(a[1]), float(a[2])), float(a[3])]


# --- IA ----------------------------------------------------------------------------------------

## Un monde toxique effondré ne se relèvera pas : l'IA en fait un monde-usine (Extraction seulement,
## ou tout tempérament quand le monde est effondré depuis longtemps).
@warning_ignore("integer_division")
static func ai(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if not Ecology.enabled(state) or posmod(state.tick / 30 + e.id, 6) != 0:
		return
	for pid in Ecology.worlds_of(state, e.id):
		if String(Ecology.tier(state, pid).get("id", "")) != "effondree" or Ecology.equilibrium(state, pid) >= 20:
			continue
		if check_factory(state, e.id, pid) == "":
			AiPlayer._issue(ctx, SimCommands.eco_act(e.id, "factory", {"pid": pid}))
			return


# --- Affichage ----------------------------------------------------------------------------------

## Lignes en plus pour l'infobulle de la biosphère.
static func tooltip_lines(state: GameState, pid: int) -> PackedStringArray:
	var out := PackedStringArray()
	if remarkable(state, pid):
		out.append("Biosphère remarquable : vitalité +%d, empreinte ×%d %%, +%d Savoir par mois tant qu'elle reste au-dessus de %d." % [
				c_int("remarkable", "vitality", 20), c_int("remarkable", "footprint_pct", 150), c_int("remarkable", "knowledge", 3), c_int("remarkable", "min_health", 60)])
	var cat := catastrophe(state, pid)
	if cat != "":
		out.append("Catastrophe en cours : %s (production %d %%)." % [cat, c_int("catastrophes", "yield_pct", -25)])
	var p := state.galaxy.get_planet(pid)
	if Combat.is_besieged(state, p.system_id):
		out.append("Siège : −%d par mois." % c_int("siege", "monthly", 5))
	var c: Colony = state.colonies.get(pid)
	if c != null and tolerant(state, c.owner):
		out.append("Peuple tolérant : les paliers ne retirent pas de nourriture.")
	return out
