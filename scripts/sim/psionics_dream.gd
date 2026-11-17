class_name PsionicsDream
extends RefCounted
## Pouvoirs psioniques, lot 2 : le Songe et la guerre (voir Psionics, data/psionics.json).
##
## La Voix (prop. 18) et la Domination mentale (prop. 19), pouvoirs du catalogue ; la Navigation par
## le Songe (prop. 22, ordre jump) ; l'Élu (prop. 11, h.psi = 3, un par empire). En réglage Complet :
## Ouvrir le Songe (prop. 24, ordre open), plonger (ordre dive, trois postures, prop. 25) et tirer une
## vision (prop. 26), rencontrer une Puissance et pactiser (prop. 27, ordres pact et break), payer son
## prix (prop. 28), la Dernière Puissance et le Solde (prop. 29, crise « solde » du catalogue des
## crises), les fêlures graves (prop. 30) et le souverain élu (prop. 31, ordre reform).
##
## État (dans state.psionics) : "open" {eid: jour}, "pact" {eid: {"p", "favor", "since", "price",
## "tier"}}, "offer" {eid: {"p", "until"}}, "reform" {eid: id du héros}. Bienfaits, malédictions et
## prix sont des effets actifs (fx) portant leurs effets "fx" (mêmes clés que les technologies) :
## Research.effects les fusionne (empreinte state.relic_rev).

const OFFER_DAYS := 180


static func cfg(k: String) -> Dictionary:
	return Psionics.cfg(k)


static func _h(state: GameState, parts: Array) -> int:
	return Psionics._h(state, parts)


## Identifiants des flottes, dans l'ordre (déterministe).
static func fleet_ids(state: GameState) -> Array:
	return state.sorted_fleet_ids()


static func _private(state: GameState, eid: int, sid := -1) -> Array:
	return Espionage.private_to(state, [eid], sid)


# --- Pouvoirs du lot 2 -------------------------------------------------------------------------

static func check_power(state: GameState, eid: int, power: String, target: int) -> String:
	var pd := Psionics.power_def(power)
	match String(pd.get("target", "self")):
		"empire":
			if power == "voix" and Psionics.immune(state, target):
				return "%s n'a pas d'esprit à convaincre" % state.get_empire(target).display_name()
		"enemy_system":
			return _check_domination(state, eid, pd, target)
	return ""


## Flotte d'un stratège sensitif assez puissant, dans le système : [flotte, héros] ou [].
static func dominator(state: GameState, eid: int, sid: int, min_power: int) -> Array:
	for f in Fleets.fleets_at(state, sid, eid):
		var h := Heroes.at_post(state, "fleet", f.id, eid)
		if not h.is_empty() and Psionics.hero_power(state, h) >= min_power:
			return [f, h]
	return []


static func _check_domination(state: GameState, eid: int, pd: Dictionary, sid: int) -> String:
	if sid < 0 or sid >= state.galaxy.systems.size():
		return "il faut viser un système"
	var owner := state.system_owner(sid)
	if owner < 0 or owner == eid or state.get_empire(owner) == null or state.get_empire(owner).is_npc():
		return "il faut viser le système d'un empire"
	if not Combat.at_war(state, eid, owner):
		return "il faut être en guerre avec %s" % state.get_empire(owner).display_name()
	if Psionics.immune(state, owner):
		return "les esprits de %s sont sourds au Songe" % state.get_empire(owner).display_name()
	var scr := String(Psionics.cfg("screens").get("building", "ecran_psychique"))
	for pid in state.galaxy.systems[sid].planet_ids:
		var c: Colony = state.colonies.get(pid)
		if c != null and c.owner == owner and c.buildings.has(scr):
			return "un écran psychique protège ce système"
	if Combat.garrison(state, sid) > int(pd.get("garrison_max", 30)):
		return "la garnison est trop forte (%d, au plus %d)" % [Combat.garrison(state, sid), int(pd.get("garrison_max", 30))]
	if dominator(state, eid, sid, int(pd.get("min_hero", 2))).is_empty():
		return "il faut la flotte d'un stratège sensitif de puissance %d dans ce système" % int(pd.get("min_hero", 2))
	return ""


static func effect(state: GameState, eid: int, power: String, target: int, added: Array[Dictionary]) -> void:
	var pd := Psionics.power_def(power)
	var e := state.get_empire(eid)
	match power:
		"voix":
			var b := state.get_empire(target)
			Psionics._add_fx(state, eid, {"id": "voix", "until": state.tick + int(pd.get("days", 720)), "target": target, "v": int(pd.get("opinion", 25))})
			added.append(state.add_chronicle("La Voix de %s résonne dans les conseils de %s : soudain, tout ce qu'elle propose paraît raisonnable." % [e.display_name(), b.display_name()],
					_private(state, eid)))
			_maybe_caught(state, eid, target, pd, "voix", added)
		"domination":
			var owner := state.system_owner(target)
			var name := state.galaxy.systems[target].system_name
			added.append_array(Combat.capture_system(state, target, eid))
			Psionics._stat(state, eid, "dominations", 1)
			added.append(state.add_chronicle("Sur %s, la garnison de %s pose les armes d'un seul geste, les yeux vides. Le système appartient désormais à %s." % [
					name, state.get_empire(owner).display_name(), e.display_name()], Espionage.public_to(state, [eid, owner])))
			_maybe_caught(state, eid, owner, pd, "domination", added)


## La cible s'aperçoit du pouvoir (caught_pct %) : grief « Viol des esprits ».
static func _maybe_caught(state: GameState, eid: int, target: int, pd: Dictionary, power: String, added: Array[Dictionary]) -> void:
	if _h(state, ["caught", eid, power, target, state.tick]) % 100 >= int(pd.get("caught_pct", 0)):
		return
	Diplomacy.remember(state, target, eid, "psi_viol")
	Psionics._stat(state, eid, "caught", 1)
	added.append(state.add_chronicle("%s a senti des doigts dans ses pensées : %s est accusé de viol des esprits." % [
			state.get_empire(target).display_name(), state.get_empire(eid).display_name()], Espionage.public_to(state, [eid, target])))


## Opinion de a sur b : la Voix de b (lue par Diplomacy.opinion_parts).
static func opinion_parts(state: GameState, a: int, b: int) -> Array:
	var fx := Psionics.fx_active(state, b, "voix", a)
	return [] if fx.is_empty() else [["La Voix de %s" % state.get_empire(b).short_name(), int(fx.get("v", 0))]]


# --- Navigation par le Songe -------------------------------------------------------------------

static func nav() -> Dictionary:
	return cfg("navigation")


static func nav_cost(state: GameState, eid: int) -> int:
	@warning_ignore("integer_division")
	return maxi(1, int(nav().get("cost", 40)) * (100 + int(Psionics.talent(state, eid).get("power_cost_pct", 0))) / 100)


static func check_jump(state: GameState, eid: int, fid: int, sid: int) -> String:
	var e := state.get_empire(eid)
	var t := String(nav().get("tech", "navigation_songe"))
	if not e.techs.has(t):
		return "il faut la technologie %s" % Research.tech(t).get("label", t)
	if Psionics.best_level(state, eid) <= 0:
		return "aucune de vos espèces n'entend %s" % Psionics.form_label(state, eid).to_lower()
	if Psionics.law_fx(state, eid, "no_powers") > 0:
		return "la Persécution des sensitifs interdit tout pouvoir"
	var f: Fleet = state.fleets.get(fid)
	if f == null or f.owner != eid:
		return "flotte inconnue"
	if f.is_moving():
		return "la flotte doit être à l'arrêt"
	if sid < 0 or sid >= state.galaxy.systems.size() or sid == f.system_id:
		return "il faut viser un autre système"
	var j := int(FactionTraits.jumps_from(state.galaxy, f.system_id).get(sid, 999))
	if j > int(nav().get("max_jumps", 4)):
		return "trop loin (%d sauts, au plus %d)" % [j, int(nav().get("max_jumps", 4))]
	var cd := Psionics.cooldown_until(state, eid, "jump")
	if state.tick < cd:
		return "le Songe se referme : prochain saut le %s" % GameCalendar.date_string(cd)
	if Psionics.resonance(state, eid) < nav_cost(state, eid):
		return "Résonance insuffisante (%d / %d)" % [Psionics.resonance(state, eid), nav_cost(state, eid)]
	return ""


static func jump(state: GameState, eid: int, fid: int, sid: int, added: Array[Dictionary]) -> void:
	var f: Fleet = state.fleets[fid]
	var n := nav()
	Psionics.add_resonance(state, eid, -nav_cost(state, eid))
	Psionics.sub(state, "cd")["%d:jump" % eid] = state.tick + int(n.get("cooldown", 120))
	Psionics._stat(state, eid, "jumps", 1)
	var dest := sid
	var lost := not bool(Psionics.talent(state, eid).get("sure_jump", false)) and _h(state, ["lost", eid, fid, state.tick]) % 100 < int(n.get("lost_pct", 15))
	if lost:
		var nbs: Array = state.galaxy.systems[sid].neighbors.duplicate()
		nbs.sort()
		if not nbs.is_empty():
			dest = int(nbs[_h(state, ["lostto", eid, fid]) % nbs.size()])
		for i in f.hp.size():
			@warning_ignore("integer_division")
			f.hp[i] = maxi(1, f.hp[i] * (100 - int(n.get("lost_hp_pct", 25))) / 100)
	f.system_id = dest
	f.path.clear()
	f.progress = 0
	f.standing_order = ""
	f.patrol.clear()
	Ground.sync_fleet(state, f)
	for o in state.empires:
		o.path_cache.clear()
	var nm := state.galaxy.systems[dest].system_name
	if lost:
		added.append(state.add_chronicle("Le %s plonge dans le Songe et s'y égare : il ressort à %s, coques fissurées, l'équipage persuadé d'avoir passé dix ans dans une forêt." % [f.fleet_name, nm],
				_private(state, eid, dest)))
	else:
		added.append(state.add_chronicle("Le %s plonge dans le Songe et ressort à %s, sans avoir suivi une seule route." % [f.fleet_name, nm], _private(state, eid, dest)))
	if _h(state, ["beast", eid, fid, state.tick]) % 100 < int(n.get("beast_pct", 8)):
		spawn_beast(state, dest)
		added.append(state.add_chronicle("Quelque chose a suivi le %s hors du Songe. Une bête du Songe rôde à %s." % [f.fleet_name, nm], _private(state, eid, dest)))
	var fc := jump_felure(state, eid)
	if fc > 0 and _h(state, ["jfel", eid, fid, state.tick]) % 100 < fc:
		Psionics.felure(state, eid, "jump", added)


## Chance (en %) d'une fêlure au saut : celle des données, avec les mêmes modificateurs qu'un pouvoir.
static func jump_felure(state: GameState, eid: int) -> int:
	var pct := 0
	for x in Psionics.felure_chance(state, eid, "jump")[1]:
		pct += int(x[1])
	@warning_ignore("integer_division")
	return maxi(0, int(nav().get("felure", 6)) * maxi(0, 100 + pct) / 100)


static func spawn_beast(state: GameState, sid: int, sp := "") -> void:
	var c := cfg("combat")
	Fauna.spawn_herd(state, sp if sp != "" else String(c.get("beast", "betes_songe")), sid, -1, state.tick + int(c.get("beast_days", 720)))


# --- L'Élu -------------------------------------------------------------------------------------

static func elu(state: GameState, eid: int) -> Dictionary:
	for id in Heroes.ids_of(state, eid):
		var h: Dictionary = state.heroes[id]
		if int(h.get("psi", 0)) >= 3:
			return h
	return {}


## Fait d'un héros l'Élu (le plus haut niveau, sensitif d'abord) ; {} s'il n'y a personne ou déjà un Élu.
static func make_elu(state: GameState, eid: int, patron := "", added: Array[Dictionary] = []) -> Dictionary:
	if not elu(state, eid).is_empty():
		return {}
	var best := {}
	var key := -1
	for id in Heroes.ids_of(state, eid):
		var h: Dictionary = state.heroes[id]
		if Heroes.is_prisoner(h):
			continue
		var k := Psionics.hero_power(state, h) * 100 + int(h["lvl"])
		if k > key:
			key = k
			best = h
	if best.is_empty():
		return {}
	best["psi"] = 3
	if patron != "":
		best["patron"] = patron
	var tr := String(Psionics.cfg("heroes").get("trait", "psionique"))
	if not (best["traits"] as Array).has(tr):
		(best["traits"] as Array).append(tr)
	Heroes.gain_xp(state, best, int(cfg("elu").get("xp", 100)))
	Psionics._stat(state, eid, "elu", 1)
	var by := (" par %s" % entity_label(patron)) if patron != "" else ""
	added.append(state.add_chronicle("%s est l'Élu%s. Les sensitifs de %s le savaient avant lui ; ils l'avaient rêvé." % [best["name"], by, state.get_empire(eid).display_name()],
			Espionage.public_to(state, [eid])))
	return best


# --- Ouvrir le Songe, plonger ------------------------------------------------------------------

static func dream() -> Dictionary:
	return cfg("dream")


static func opened(state: GameState, eid: int) -> bool:
	return Psionics.sub(state, "open").has(str(eid))


static func open_cost(state: GameState, eid: int) -> int:
	var cols := 0
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner == eid and c.is_colony() and c.is_established():
			cols += 1
	@warning_ignore("integer_division")
	return (int(dream().get("open_base", 500)) + int(dream().get("open_colony", 100)) * cols) * (100 + PsionicsBridges.open_pct(state, eid)) / 100


static func posture(id: String) -> Dictionary:
	for p: Dictionary in dream().get("postures", []):
		if String(p["id"]) == id:
			return p
	return {}


static func dive_cost(state: GameState, eid: int) -> int:
	@warning_ignore("integer_division")
	return maxi(1, int(dream().get("dive_cost", 60)) * (100 + int(Psionics.talent(state, eid).get("power_cost_pct", 0))) / 100)


static func _check_dream(state: GameState, eid: int) -> String:
	if not Psionics.full(state):
		return "le Songe n'est pas en jeu (réglage Discret)"
	var t := Psionics.tech_for("dream")
	if not state.get_empire(eid).techs.has(t):
		return "il faut la technologie %s" % Research.tech(t).get("label", t)
	if Psionics.best_level(state, eid) <= 0:
		return "aucune de vos espèces n'entend le Songe"
	if Psionics.law_fx(state, eid, "no_powers") > 0:
		return "la Persécution des sensitifs interdit de plonger"
	return ""


static func check_open(state: GameState, eid: int) -> String:
	var why := _check_dream(state, eid)
	if why != "":
		return why
	if opened(state, eid):
		return "le Songe est déjà ouvert"
	var c := open_cost(state, eid)
	if int(state.get_empire(eid).resources.get("knowledge", 0)) < c:
		return "il faut %d de Savoir" % c
	return ""


static func check_dive(state: GameState, eid: int, posture_id: String) -> String:
	var why := _check_dream(state, eid)
	if why != "":
		return why
	if not opened(state, eid):
		return "il faut d'abord ouvrir le Songe"
	if posture(posture_id).is_empty():
		return "posture inconnue"
	var cd := Psionics.cooldown_until(state, eid, "dive")
	if state.tick < cd:
		return "les plongeurs se reposent jusqu'au %s" % GameCalendar.date_string(cd)
	if Psionics.resonance(state, eid) < dive_cost(state, eid):
		return "Résonance insuffisante (%d / %d)" % [Psionics.resonance(state, eid), dive_cost(state, eid)]
	return ""


static func dive_years(state: GameState, eid: int) -> int:
	return maxi(1, int(dream().get("dive_years", 5)) + int(Psionics.talent(state, eid).get("dive_years", 0)))


static func dive(state: GameState, eid: int, posture_id: String, added: Array[Dictionary]) -> void:
	var pd := posture(posture_id)
	Psionics.add_resonance(state, eid, -dive_cost(state, eid))
	Psionics.sub(state, "cd")["%d:dive" % eid] = state.tick + dive_years(state, eid) * Heroes.DAYS_PER_YEAR
	Psionics._stat(state, eid, "dives", 1)
	var odds: Array = pd.get("odds", [70, 20, 10])
	var r := _h(state, ["dive", eid, state.tick]) % 100
	var kind := "boon" if r < int(odds[0]) else ("none" if r < int(odds[0]) + int(odds[1]) else "curse")
	if kind == "boon" and _h(state, ["meet", eid, state.tick]) % 100 < int(dream().get("meet_pct", 25)) and not Psionics.sub(state, "pact").has(str(eid)):
		_meet(state, eid, added)
		return
	var v := pick_vision(state, eid, kind, int(pd.get("tier", 0)))
	added.append(state.add_chronicle("Plongée %s dans le Songe pour %s : %s." % [String(pd["label"]).to_lower(), state.get_empire(eid).display_name(), String(v.get("label", "?")).to_lower()],
			_private(state, eid)))
	apply_vision(state, eid, v, added)


## Vision tirée dans le catalogue (sorte, palier de posture).
static func pick_vision(state: GameState, eid: int, kind: String, tier: int) -> Dictionary:
	var pool := []
	var total := 0
	for v: Dictionary in cfg("visions").get("list", []):
		if String(v.get("kind", "none")) == kind and int(v.get("tier", 0)) <= tier:
			pool.append(v)
			total += int(v.get("weight", 1))
	if pool.is_empty() or total <= 0:
		return {"id": "rien", "kind": "none", "label": "Rien", "text": "Rien."}
	var r := _h(state, ["vision", eid, kind, state.tick]) % total
	for v: Dictionary in pool:
		r -= int(v.get("weight", 1))
		if r < 0:
			return v
	return pool[0]


static func apply_vision(state: GameState, eid: int, v: Dictionary, added: Array[Dictionary]) -> void:
	var e := state.get_empire(eid)
	var until := state.tick + int(dream().get("boon_years", 5)) * Heroes.DAYS_PER_YEAR
	var kind := String(v.get("kind", "none"))
	if v.has("fx"):
		add_fx_effect(state, eid, {"id": kind, "until": until, "label": String(v["label"]), "fx": (v["fx"] as Dictionary).duplicate(true)})
	if v.has("empire_stability"):
		Psionics._add_fx(state, eid, {"id": "f_empire", "until": until, "v": int(v["empire_stability"]), "label": String(v["label"])})
	match String(v.get("do", "")):
		"resonance":
			Psionics.add_resonance(state, eid, Psionics.cap(state, eid))
		"resonance_loss":
			Psionics.add_resonance(state, eid, -Psionics.resonance(state, eid))
		"regard":
			var cs: Array = e.contacts.filter(func(c: int) -> bool: return state.get_empire(c) != null and not state.get_empire(c).eliminated and not state.get_empire(c).is_npc())
			if not cs.is_empty():
				var b := int(cs[_h(state, ["regard", eid, state.tick]) % cs.size()])
				e.dossiers[b] = Espionage._report(state, eid, b, (Espionage.data()["tiers"] as Array).size())
		"tech":
			for t in ["ecrans_psychiques", "precognition", "navigation_songe", "ouverture_songe"]:
				if not e.techs.has(t):
					Research.grant(state, eid, [t])
					break
		"avatar":
			var cap := FactionTraits.capital_system(state, eid)
			var at := String(cfg("combat").get("avatar", "avatar_songe"))
			if Ground.full(state) and cap >= 0:
				Ground._new_regiment(state, eid, at, Peoples.founder_of(state, eid), cap)
			else:
				add_fx_effect(state, eid, {"id": "boon", "until": until, "label": "Ombre de l'Avatar", "fx": {"damage_pct": 10}})
		"elu":
			if make_elu(state, eid, "", added).is_empty():
				Psionics.add_resonance(state, eid, Psionics.cap(state, eid))
		"beast", "corrupt":
			var sid := FactionTraits.capital_system(state, eid)
			if sid >= 0:
				spawn_beast(state, sid, String(cfg("combat").get("corrupt", "avatar_corrompu")) if String(v.get("do", "")) == "corrupt" else "")
		"hero_death":
			_kill_sensitive(state, eid, "n'est pas remonté du Songe", added)
		"felure_grave":
			var g: Array = Psionics.cfg("felures").get("grave", [])
			if not g.is_empty():
				Psionics.apply_felure(state, eid, g[_h(state, ["fgrave", eid, state.tick]) % g.size()], added)
	added.append(state.add_chronicle(String(v.get("text", "")), _private(state, eid)))


## Effet actif portant des effets de technologies : invalide le cache des effets.
static func add_fx_effect(state: GameState, eid: int, fx: Dictionary) -> void:
	Psionics._add_fx(state, eid, fx)
	state.relic_rev += 1


static func _kill_sensitive(state: GameState, eid: int, why: String, added: Array[Dictionary]) -> bool:
	var pick := {}
	var key := -1
	for id in Heroes.ids_of(state, eid):
		var h: Dictionary = state.heroes[id]
		if Heroes.is_prisoner(h) or bool(h.get("ruler", false)):
			continue
		var k := Psionics.hero_power(state, h) * 1000 + int(_h(state, ["victim", id]) % 1000)
		if k > key:
			key = k
			pick = h
	if pick.is_empty():
		return false
	Heroes.die(state, pick, why, added)
	return true


# --- Puissances et pactes ----------------------------------------------------------------------

static func entities() -> Dictionary:
	return cfg("entities")


static func entity(id: String) -> Dictionary:
	var ld: Dictionary = entities().get("last", {})
	if id == String(ld.get("id", "derniere")):
		return ld
	for p: Dictionary in entities().get("list", []):
		if String(p["id"]) == id:
			return p
	return {}


static func entity_label(id: String) -> String:
	return String(entity(id).get("label", id))


static func is_last(id: String) -> bool:
	return id == String((entities().get("last", {}) as Dictionary).get("id", "derniere"))


static func pact(state: GameState, eid: int) -> Dictionary:
	return Psionics.sub(state, "pact").get(str(eid), {})


static func offer(state: GameState, eid: int) -> Dictionary:
	var o: Dictionary = Psionics.sub(state, "offer").get(str(eid), {})
	return o if not o.is_empty() and int(o.get("until", 0)) > state.tick else {}


## Rencontre d'une Puissance : la Dernière (last_pct %), sinon celle que le peuple attire le plus.
static func _meet(state: GameState, eid: int, added: Array[Dictionary]) -> void:
	var pid := ""
	if _h(state, ["last", eid, state.tick]) % 100 < int(dream().get("last_pct", 2)):
		pid = String((entities().get("last", {}) as Dictionary).get("id", "derniere"))
	else:
		var list: Array = entities().get("list", [])
		var best := -1
		for p: Dictionary in list:
			var s := like_score(state, eid, p) * 1000 + _h(state, ["pick", eid, String(p["id"]), state.tick]) % 1000
			if s > best:
				best = s
				pid = String(p["id"])
	if pid == "":
		return
	Psionics.sub(state, "offer")[str(eid)] = {"p": pid, "until": state.tick + OFFER_DAYS}
	Psionics._stat(state, eid, "met", 1)
	var ed := entity(pid)
	added.append(state.add_chronicle("Au fond du Songe, les plongeurs de %s rencontrent %s (%s). %s Elle propose un pacte." % [
			state.get_empire(eid).display_name(), String(ed["label"]), String(ed.get("domain", "")), String(ed.get("text", ""))], _private(state, eid)))


## Goûts d'une Puissance pour un peuple : 1 par credo ou gouvernement qui lui plaît.
static func like_score(state: GameState, eid: int, p: Dictionary) -> int:
	var sp := FactionTraits.species(state.get_empire(eid).faction())
	var likes: Dictionary = p.get("likes", {})
	var n := 0
	if (likes.get("credo", []) as Array).has(String(sp.get("credo", ""))):
		n += 1
	if (likes.get("gouvernement", []) as Array).has(String(sp.get("gouvernement", ""))):
		n += 1
	return n


static func check_pact(state: GameState, eid: int, accept: bool) -> String:
	if not Psionics.full(state):
		return "le Songe n'est pas en jeu"
	if offer(state, eid).is_empty():
		return "aucune Puissance n'attend de réponse"
	if accept and not pact(state, eid).is_empty():
		return "votre empire a déjà un pacte"
	return ""


static func answer_pact(state: GameState, eid: int, accept: bool, added: Array[Dictionary]) -> void:
	var o := offer(state, eid)
	Psionics.sub(state, "offer").erase(str(eid))
	var pid := String(o["p"])
	var e := state.get_empire(eid)
	if not accept:
		added.append(state.add_chronicle("%s décline l'offre de %s. Le Songe se referme poliment." % [e.display_name(), entity_label(pid)], _private(state, eid)))
		return
	var py := int(entities().get("price_years", 15))
	var p := {"p": pid, "favor": 0, "since": state.tick, "price": state.tick + py * Heroes.DAYS_PER_YEAR, "tier": 0}
	if is_last(pid):
		p["until"] = state.tick + int(entity(pid).get("last_years", 50)) * Heroes.DAYS_PER_YEAR
		p.erase("price")
	Psionics.sub(state, "pact")[str(eid)] = p
	Psionics._stat(state, eid, "pacts", 1)
	state.relic_rev += 1
	PsionicsBridges.on_pact(state, eid)
	added.append(state.add_chronicle("%s pactise avec %s. %s" % [e.display_name(), entity_label(pid),
			"Cinquante ans de tout, tout de suite. Le compte est ouvert." if is_last(pid) else "La faveur montera avec les actes qui lui plaisent ; le prix viendra aussi."],
			_private(state, eid)))


static func check_break(state: GameState, eid: int) -> String:
	if pact(state, eid).is_empty():
		return "votre empire n'a pas de pacte"
	return ""


static func break_pact(state: GameState, eid: int, added: Array[Dictionary]) -> void:
	var p := pact(state, eid)
	var pid := String(p["p"])
	Psionics.sub(state, "pact").erase(str(eid))
	Psionics.sub(state, "reform").erase(str(eid))
	state.relic_rev += 1
	Psionics._stat(state, eid, "broken", 1)
	var ent := entities()
	Psionics._add_fx(state, eid, {"id": "f_empire", "until": state.tick + int(ent.get("break_days", 1080)), "v": int(ent.get("break_stability", -10)), "label": "Pacte rompu"})
	added.append(state.add_chronicle("%s rompt son pacte avec %s. Les rêves de tout l'empire deviennent très, très silencieux." % [state.get_empire(eid).display_name(), entity_label(pid)],
			_private(state, eid)))
	if is_last(pid):
		solde(state, eid, added)


## Palier de faveur atteint (index dans tiers).
static func tier_of(p: Dictionary, favor: int) -> int:
	var t := 0
	var tiers: Array = p.get("tiers", [])
	for i in tiers.size():
		if favor >= int((tiers[i] as Dictionary).get("favor", 0)):
			t = i
	return t


## Faveur gagnée ce mois : base, goûts, actes.
static func favor_gain(state: GameState, eid: int, ed: Dictionary) -> int:
	var ent := entities()
	var e := state.get_empire(eid)
	var n := int(ent.get("favor_month", 1)) + like_score(state, eid, ed) * int(ent.get("like_favor", 1))
	var acts: Dictionary = ed.get("acts", {})
	for a in acts:
		var ok := false
		match String(a):
			"war":
				ok = not e.wars.is_empty()
			"peace":
				ok = e.wars.is_empty()
			"genome":
				ok = e.gene_path != "" or not e.genome.is_empty()
			"lecture":
				ok = not Psionics.fx_active(state, eid, "lecture").is_empty()
			"prescience":
				ok = not Psionics.fx_active(state, eid, "prescience").is_empty()
			"powers":
				ok = Psionics.stat(state, eid, "powers") > 0
		if ok:
			n += int(acts[a])
	return n


static func _pact_month(state: GameState, e: Empire, added: Array[Dictionary]) -> void:
	var p := pact(state, e.id)
	if p.is_empty():
		return
	var pid := String(p["p"])
	var ed := entity(pid)
	if is_last(pid):
		if state.tick >= int(p.get("until", 0)):
			Psionics.sub(state, "pact").erase(str(e.id))
			state.relic_rev += 1
			solde(state, e.id, added)
		return
	p["favor"] = mini(int(entities().get("max_favor", 150)), int(p["favor"]) + favor_gain(state, e.id, ed))
	var t := tier_of(ed, int(p["favor"]))
	if t != int(p.get("tier", 0)):
		p["tier"] = t
		state.relic_rev += 1
		var td: Dictionary = (ed.get("tiers", []) as Array)[t]
		added.append(state.add_chronicle("%s sourit à %s : la faveur atteint un nouveau palier." % [String(ed["label"]), e.display_name()], _private(state, e.id)))
		if bool(td.get("elu", false)) and not bool(p.get("elu", false)):
			var h := make_elu(state, e.id, pid, added)
			if not h.is_empty():
				p["elu"] = true
				_propose_reform(state, e, h, added)
	if state.tick >= int(p.get("price", 0)):
		p["price"] = state.tick + int(entities().get("price_years", 15)) * Heroes.DAYS_PER_YEAR
		_pay_price(state, e, ed, added)


## Contrepartie tirée dans la table de la Puissance (prop. 28).
static func _pay_price(state: GameState, e: Empire, ed: Dictionary, added: Array[Dictionary]) -> void:
	var table: Array = ed.get("price", [])
	var total := 0
	for x: Dictionary in table:
		total += int(x.get("weight", 1))
	if total <= 0:
		return
	var r := _h(state, ["price", e.id, state.tick]) % total
	var pick: Dictionary = table[0]
	for x: Dictionary in table:
		r -= int(x.get("weight", 1))
		if r < 0:
			pick = x
			break
	Psionics._stat(state, e.id, "prices", 1)
	var what := ""
	match String(pick["id"]):
		"pop":
			what = "%d habitants disparaissent dans leur sommeil" % lose_pop(state, e.id, int(pick.get("n", 3)))
		"hero":
			what = "un héros ne se réveille pas" if _kill_sensitive(state, e.id, "a été réclamé par %s" % String(ed["label"]), added) else "personne à prendre, cette fois"
		"stability":
			Psionics._add_fx(state, e.id, {"id": "f_empire", "until": state.tick + int(pick.get("days", 720)), "v": int(pick.get("v", -10)), "label": String(pick["label"])})
			what = "stabilité %d pendant %d ans" % [int(pick.get("v", -10)), int(pick.get("days", 720)) / Heroes.DAYS_PER_YEAR]
		"resonance":
			Psionics.add_resonance(state, e.id, -Psionics.resonance(state, e.id))
			what = "la Résonance est bue jusqu'à la dernière goutte"
		"mutation":
			add_fx_effect(state, e.id, {"id": "price", "until": state.tick + 36000, "label": String(pick["label"]), "fx": (pick.get("fx", {}) as Dictionary).duplicate(true)})
			what = "l'espèce change un peu, pour toujours"
	added.append(state.add_chronicle("Le prix du pacte : %s. %s." % [String(pick["label"]).to_lower(), what], _private(state, e.id)))


## Retire n habitants aux colonies les plus peuplées ; renvoie le nombre retiré.
static func lose_pop(state: GameState, eid: int, n: int) -> int:
	var lost := 0
	var guard := 0
	while lost < n and guard < n * 4:
		guard += 1
		var best: Colony = null
		for pid in state.sorted_colony_ids():
			var c: Colony = state.colonies[pid]
			if c.owner == eid and c.is_colony() and c.population > 1 and (best == null or c.population > best.population):
				best = c
		if best == null:
			break
		best.population -= 1
		Peoples.normalize(best)
		lost += 1
	return lost


## Le souverain élu (prop. 31) : l'Élu d'une Puissance propose la théocratie de son culte.
static func _propose_reform(state: GameState, e: Empire, h: Dictionary, added: Array[Dictionary]) -> void:
	var gov := String(entities().get("reform_gov", "theocratie"))
	if String(FactionTraits.species(e.faction()).get("gouvernement", "")) == gov:
		return
	Psionics.sub(state, "reform")[str(e.id)] = int(h["id"])
	added.append(state.add_chronicle("%s, Élu de %s, propose de refonder %s : une théocratie de son culte, avec lui pour guide." % [h["name"], entity_label(String(h.get("patron", ""))), e.display_name()],
			_private(state, e.id)))


static func check_reform(state: GameState, eid: int) -> String:
	if not Psionics.sub(state, "reform").has(str(eid)):
		return "aucune réforme n'est proposée"
	return ""


static func answer_reform(state: GameState, eid: int, accept: bool, added: Array[Dictionary]) -> void:
	var hid := int(Psionics.sub(state, "reform")[str(eid)])
	Psionics.sub(state, "reform").erase(str(eid))
	var e := state.get_empire(eid)
	var h := Heroes.get_hero(state, hid)
	var who := String(h.get("name", "L'Élu"))
	if accept:
		var gov := String(entities().get("reform_gov", "theocratie"))
		var g: Dictionary = e.genome.get(e.faction_id, {})
		g["gov"] = gov
		e.genome[e.faction_id] = g
		e.genome_rev += 1
		state.relic_rev += 1
		Psionics._stat(state, eid, "reform", 1)
		added.append(state.add_chronicle("%s devient une théocratie : %s guide l'empire au nom de %s." % [e.display_name(), who, entity_label(String(h.get("patron", "")))],
				Espionage.public_to(state, [eid])))
	else:
		var ent := entities()
		Psionics._add_fx(state, eid, {"id": "f_empire", "until": state.tick + int(ent.get("reform_refused_days", 720)), "v": int(ent.get("reform_refused_stability", -10)), "label": "Réforme de l'Élu refusée"})
		if not h.is_empty():
			h["loy"] = maxi(0, int(h.get("loy", 50)) - 30)
		added.append(state.add_chronicle("%s refuse la réforme de %s. L'Élu se tait ; ses fidèles, beaucoup moins." % [e.display_name(), who], _private(state, eid)))


# --- La Dernière Puissance et le Solde ---------------------------------------------------------

static func solde(state: GameState, eid: int, added: Array[Dictionary]) -> void:
	var e := state.get_empire(eid)
	var sd: Dictionary = (entities().get("last", {}) as Dictionary).get("solde", {})
	Psionics._stat(state, eid, "solde", 1)
	var pct := int(sd.get("pop_pct", 50))
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner == eid and c.is_colony() and c.population > 1:
			@warning_ignore("integer_division")
			c.population = maxi(1, c.population - c.population * pct / 100)
			Peoples.normalize(c)
	Psionics.add_resonance(state, eid, -Psionics.resonance(state, eid))
	Psionics._add_fx(state, eid, {"id": "f_empire", "until": state.tick + int(sd.get("days", 1800)), "v": int(sd.get("stability", -30)), "label": "Le Solde"})
	added.append(state.add_chronicle("Le compte de %s est échu. La Dernière Puissance vient solder : la moitié du peuple ne se réveille pas, et le Songe déborde." % e.display_name(),
			Espionage.public_to(state, [eid])))
	var k := String(sd.get("crisis", "solde"))
	if Crisis.enabled(state) and Crisis.cur(state).is_empty() and not (state.crisis.get("done", []) as Array).has(k) and not Crisis.kind_def(k).is_empty():
		state.crisis["summoner"] = eid
		Crisis.begin(state, k, added)


# --- Fêlures graves ----------------------------------------------------------------------------

static func felure(state: GameState, eid: int, f: Dictionary, added: Array[Dictionary]) -> void:
	match String(f.get("do", "")):
		"possession":
			var h := {}
			for id in Heroes.ids_of(state, eid):
				var x: Dictionary = state.heroes[id]
				if Psionics.hero_power(state, x) > 0 and not bool(x.get("ruler", false)) and int(x.get("psi", 0)) < 3:
					h = x
					break
			if not h.is_empty():
				var sid := FactionTraits.capital_system(state, eid)
				Heroes.die(state, h, "est possédé : une nuit, il quitte le palais avec une autre voix, et ce qui l'habite prend forme dans le vide", added)
				if sid >= 0:
					spawn_beast(state, sid)
		"beast":
			var best := -1
			var best_pop := -1
			for pid in state.sorted_colony_ids():
				var c: Colony = state.colonies[pid]
				if c.owner == eid and c.is_colony() and c.population > best_pop:
					best_pop = c.population
					best = state.galaxy.get_planet(pid).system_id
			if best >= 0:
				spawn_beast(state, best)
	if bool(f.get("haunt", false)):
		for fx: Dictionary in Psionics.fx_list(state, eid):
			if String(fx["id"]) == "f_system" and String(fx.get("label", "")) == String(f["label"]) and int(fx.get("until", 0)) > state.tick + 30000:
				Psionics.sub(state, "haunted")[str(fx["sys"])] = eid


## Systèmes hantés (Cratère du Songe) : {sid: empire}.
static func haunted(state: GameState) -> Dictionary:
	return Psionics.sub(state, "haunted")


# --- Effets (Research.effects) -----------------------------------------------------------------

static func effects(state: GameState, eid: int) -> Dictionary:
	var out := {}
	if not Psionics.applies(state, eid):
		return out
	for fx: Dictionary in Psionics.fx_list(state, eid):
		if fx.has("fx") and int(fx["until"]) > state.tick:
			Research._merge(out, fx["fx"])
	var p := pact(state, eid)
	if not p.is_empty():
		var ed := entity(String(p["p"]))
		if is_last(String(p["p"])):
			Research._merge(out, ed.get("fx", {}))
		else:
			var tiers: Array = ed.get("tiers", [])
			if not tiers.is_empty():
				Research._merge(out, (tiers[clampi(int(p.get("tier", 0)), 0, tiers.size() - 1)] as Dictionary).get("fx", {}))
	return out


# --- Commandes ---------------------------------------------------------------------------------

static func check(state: GameState, eid: int, act: String, d: Dictionary) -> String:
	match act:
		"open":
			return check_open(state, eid)
		"dive":
			return check_dive(state, eid, String(d.get("posture", "")))
		"pact":
			return check_pact(state, eid, bool(d.get("accept", false)))
		"break":
			return check_break(state, eid)
		"reform":
			return check_reform(state, eid)
		"jump":
			return check_jump(state, eid, int(d.get("fleet", -1)), int(d.get("sys", -1)))
	return "ordre psionique inconnu : %s" % act


static func apply(state: GameState, eid: int, act: String, d: Dictionary, added: Array[Dictionary]) -> void:
	match act:
		"open":
			var e := state.get_empire(eid)
			e.resources["knowledge"] = int(e.resources.get("knowledge", 0)) - open_cost(state, eid)
			Psionics.sub(state, "open")[str(eid)] = state.tick
			added.append(state.add_chronicle("%s ouvre le Songe : ses plongeurs peuvent descendre. Les autres empires ont mal dormi cette nuit-là, sans savoir pourquoi." % e.display_name(),
					_private(state, eid)))
		"dive":
			dive(state, eid, String(d["posture"]), added)
		"pact":
			answer_pact(state, eid, bool(d.get("accept", false)), added)
		"break":
			break_pact(state, eid, added)
		"reform":
			answer_reform(state, eid, bool(d.get("accept", false)), added)
		"jump":
			jump(state, eid, int(d["fleet"]), int(d["sys"]), added)


static func monthly(state: GameState, added: Array[Dictionary]) -> void:
	if not Psionics.full(state):
		return
	for e in state.empires:
		if not Psionics.applies(state, e.id):
			continue
		_pact_month(state, e, added)
		var o: Dictionary = Psionics.sub(state, "offer").get(str(e.id), {})
		if not o.is_empty() and int(o.get("until", 0)) <= state.tick:
			Psionics.sub(state, "offer").erase(str(e.id))
