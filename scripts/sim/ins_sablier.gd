class_name InsSablier
extends RefCounted
## Gardiens du Sablier Fêlé (props 83 à 88 ; voir Insolites, data/insolites.json "sablier").
## Ils peuvent annuler un événement passé, mais chaque paradoxe déchire la réalité locale.
##   - Le Registre : reg_days jours d'événements annulables qui les touchent, avec de quoi les défaire :
##     vaisseau perdu au combat, système conquis, héros mort, technologie volée. Rien n'est rejoué : on
##     applique l'inverse, donc tout reste déterministe (multijoueur compris). Les choix d'événements ne
##     sont pas annulables (leurs effets ne se défont pas de façon générale).
##   - Annuler coûte du Sable (réserve propre, sand_month par mois) : le vaisseau revient à la capitale,
##     le système revient, le héros se relève, la technologie n'a jamais été volée. Les points fixes ne
##     s'annulent pas : victoires, crises, souverains, et la mort du Gardien chronal.
##   - Déchirures : chaque annulation ouvre une déchirure dans le système (production -tear_pct %),
##     qui guérit en tear_days ; parfois des créatures du Hiatus en sortent. À tear_collapse annulations
##     dans un même système avant guérison : effondrement local (la population y est divisée par deux).
##   - Bulles temporelles : Compression (+25 %) sur un de leurs systèmes, Dilatation (-25 %) sur un
##     système étranger, payées en Sable.
##   - Longévité : croissance lente (brique), héros qui vivent life_pct % plus longtemps ; forme psionique
##     nouvelle, la Chronopathie (data/psionics.json, catalogue ouvert des formes).
##   - Victoire : le Paradoxe stable. La Boucle, loop_stages projets successifs, demande le Gardien chronal
##     vivant ; s'il tombe, la Boucle se défait et un autre Gardien vient au bout de chrono_days.
##
## État (Insolites.emp) : "sand", "reg": [{"k", "t", "sid", …}], "loop" (étapes faites), "lp" (étape
## en cours {"left"}), "hero" (Gardien chronal), "back" (jour de son retour), "bub" (jour où une bulle
## est de nouveau possible). Galaxie : state.insolites "tears": {sid: {"n", "until"}}, "bubbles":
## {sid: {"pct", "until", "o"}}.


static func _c(key: String, def := 0) -> int:
	return Insolites.c_int("sablier", key, def)


static func found(_state: GameState, _e: Empire, _sid: int, ed: Dictionary) -> void:
	ed["sand"] = _c("sand_start", 40)
	ed["reg"] = []
	ed["loop"] = 0
	ed["lp"] = {}
	ed["hero"] = -1
	ed["back"] = 0
	ed["bub"] = 0


static func guardians(state: GameState) -> Array[int]:
	var out: Array[int] = []
	for eid in Insolites.nomad_ids(state):
		if Insolites.kind(state, eid) == "sablier":
			out.append(eid)
	return out


static func is_guardian(state: GameState, eid: int) -> bool:
	return not state.insolites.is_empty() and Insolites.kind(state, eid) == "sablier"


# --- Gardien chronal ---------------------------------------------------------------------------------

static func after_setup(state: GameState, eid: int) -> void:
	_spawn_hero(state, eid)


static func _spawn_hero(state: GameState, eid: int) -> void:
	var cand := Heroes.make_candidate(state, eid, "stratege", ["chronal", eid, state.tick])
	cand["name"] = String(Insolites.cfg("sablier").get("hero_name", "le Gardien chronal"))
	cand["age"] = 40
	var id := Heroes.recruit(state, eid, cand)
	var h: Dictionary = state.heroes[id]
	h["lvl"] = maxi(int(h["lvl"]), 2)
	h["life"] = 100000
	h["chronal"] = true
	Insolites.emp(state, eid)["hero"] = id


static func hero(state: GameState, eid: int) -> Dictionary:
	var id := int(Insolites.emp(state, eid).get("hero", -1))
	return state.heroes.get(id, {}) if id >= 0 else {}


# --- Le Registre (prop. 83) --------------------------------------------------------------------------

static func ledger(state: GameState, eid: int) -> Array:
	return Insolites.emp(state, eid).get("reg", [])


static func _note(state: GameState, eid: int, entry: Dictionary) -> void:
	var ed := Insolites.emp(state, eid)
	if ed.is_empty():
		return
	entry["t"] = state.tick
	var reg: Array = ed.get("reg", [])
	reg.append(entry)
	while reg.size() > _c("reg_max", 24):
		reg.pop_front()
	ed["reg"] = reg


static func on_ship_lost(state: GameState, f: Fleet, i: int) -> void:
	if is_guardian(state, f.owner):
		_note(state, f.owner, {"k": "ship", "ship": f.ships[i], "sid": f.system_id})


## Un système va changer de main (Combat.capture_system, avant le transfert).
static func on_capture(state: GameState, sid: int, new_owner: int, old: int) -> void:
	if not is_guardian(state, old) or new_owner == old:
		return
	var pops := {}
	for pid in state.galaxy.systems[sid].planet_ids:
		var c: Colony = state.colonies.get(pid)
		if c != null and c.owner == old:
			pops[str(pid)] = c.population
	_note(state, old, {"k": "colony", "sid": sid, "by": new_owner, "pops": pops})


static func on_hero_death(state: GameState, h: Dictionary, out: Array[Dictionary]) -> void:
	var eid := int(h["owner"])
	if not is_guardian(state, eid):
		return
	var ed := Insolites.emp(state, eid)
	if bool(h.get("chronal", false)):
		# Point fixe : la mort du Gardien chronal ne s'annule pas, et la Boucle se défait.
		ed["hero"] = -1
		ed["back"] = state.tick + _c("chrono_days", 1800)
		var had := int(ed.get("loop", 0)) > 0 or not (ed.get("lp", {}) as Dictionary).is_empty()
		ed["loop"] = 0
		ed["lp"] = {}
		out.append(state.add_chronicle("Le Gardien chronal est mort. C'est un point fixe : le Sablier n'y peut rien.%s" % (" La Boucle se défait, étape après étape, comme si elle n'avait jamais été construite." if had else ""),
				Espionage.public_to(state, [eid])))
		return
	if bool(h.get("revenant", false)):
		return
	_note(state, eid, {"k": "hero", "name": String(h["name"]), "cls": String(h.get("cls", "stratege")), "lvl": int(h.get("lvl", 1)),
			"portrait": String(h.get("portrait", "")), "sid": FactionTraits.capital_system(state, eid)})


static func on_tech_stolen(state: GameState, thief: int, victim: int, tid: String, amount: int) -> void:
	if is_guardian(state, victim):
		_note(state, victim, {"k": "tech", "by": thief, "tid": tid, "n": amount, "sid": FactionTraits.capital_system(state, victim)})


static func entry_text(state: GameState, en: Dictionary) -> String:
	var when := GameCalendar.date_string(int(en["t"]))
	match String(en["k"]):
		"ship":
			return "%s : %s perdu à %s" % [when, String(GameData.ship(String(en["ship"])).get("label", en["ship"])), state.galaxy.systems[int(en["sid"])].system_name]
		"colony":
			var by := state.get_empire(int(en["by"]))
			return "%s : %s pris par %s" % [when, state.galaxy.systems[int(en["sid"])].system_name, by.short_name() if by else "?"]
		"hero":
			return "%s : mort de %s" % [when, String(en["name"])]
		"tech":
			var th := state.get_empire(int(en["by"]))
			return "%s : « %s » volée par %s" % [when, String(Research.tech(String(en["tid"])).get("label", en["tid"])), th.short_name() if th else "?"]
	return when


static func undo_cost(en: Dictionary) -> int:
	return int((Insolites.cfg("sablier").get("undo_cost", {}) as Dictionary).get(String(en["k"]), 50))


# --- Annuler (prop. 84) ------------------------------------------------------------------------------

static func check_undo(state: GameState, eid: int, i: int) -> String:
	if not is_guardian(state, eid):
		return "seuls les Gardiens du Sablier défont le passé"
	var reg := ledger(state, eid)
	if i < 0 or i >= reg.size():
		return "rien de tel dans le Registre"
	var en: Dictionary = reg[i]
	if state.tick - int(en["t"]) > _c("reg_days", 180):
		return "trop ancien : le sable a figé ce moment"
	if int(Insolites.emp(state, eid).get("sand", 0)) < undo_cost(en):
		return "Sable insuffisant (%d / %d)" % [int(Insolites.emp(state, eid).get("sand", 0)), undo_cost(en)]
	match String(en["k"]):
		"ship":
			if FactionTraits.capital_system(state, eid) < 0:
				return "il faut une capitale où faire revenir le vaisseau"
		"colony":
			if state.system_owner(int(en["sid"])) != int(en["by"]):
				return "le système a changé de main depuis : ce passé-là n'existe plus"
		"hero":
			if Heroes.ids_of(state, eid).size() >= Heroes.cap(state, eid):
				return "plus de place pour un héros"
	return ""


static func undo(state: GameState, eid: int, i: int, added: Array[Dictionary]) -> void:
	var ed := Insolites.emp(state, eid)
	var reg: Array = ed["reg"]
	var en: Dictionary = reg[i]
	reg.remove_at(i)
	ed["sand"] = int(ed.get("sand", 0)) - undo_cost(en)
	var e := state.get_empire(eid)
	var sid := int(en.get("sid", -1))
	var text := ""
	match String(en["k"]):
		"ship":
			var cap := FactionTraits.capital_system(state, eid)
			state.spawn_ship(eid, String(en["ship"]), cap)
			text = "Un %s des Gardiens, détruit à %s, est soudain amarré à la capitale, intact, l'équipage un peu pâle." % [
					String(GameData.ship(String(en["ship"])).get("label", en["ship"])).to_lower(), state.galaxy.systems[sid].system_name]
		"colony":
			var pops: Dictionary = en.get("pops", {})
			for pid in state.galaxy.systems[sid].planet_ids:
				var c: Colony = state.colonies.get(pid)
				if c == null or c.owner != int(en["by"]) or not pops.has(str(pid)):
					continue
				Peoples.on_owner_change(state, c, c.owner, eid)
				c.owner = eid
				c.population = maxi(c.population, int(pops[str(pid)]))
				c.construction = ""
				c.construction_days = 0
				c.ship_build = ""
				c.ship_days = 0
			state.rebuild_ownership()
			Stability.on_capture(state, sid)
			var by := state.get_empire(int(en["by"]))
			text = "La conquête de %s par %s n'a jamais eu lieu. Les occupants se réveillent chez eux, avec le souvenir très net d'une victoire qu'aucun registre ne mentionne." % [
					state.galaxy.systems[sid].system_name, by.short_name() if by else "?"]
		"hero":
			var cand := Heroes.make_candidate(state, eid, String(en["cls"]), ["sablier", eid, state.tick, i])
			cand["name"] = String(en["name"])
			if String(en["portrait"]) != "":
				cand["portrait"] = String(en["portrait"])
			var id := Heroes.recruit(state, eid, cand)
			var h: Dictionary = state.heroes[id]
			h["lvl"] = maxi(int(h["lvl"]), int(en["lvl"]))
			text = "%s rouvre les yeux. Pour lui, rien ne s'est passé ; pour les Gardiens, une fissure de plus dans le verre." % String(en["name"])
		"tech":
			var th := state.get_empire(int(en["by"]))
			var tid := String(en["tid"])
			var n := int(en["n"])
			if th != null:
				if th.techs.has(tid):
					th.resources["knowledge"] = maxi(0, int(th.resources.get("knowledge", 0)) - n)
				elif not th.research_queue.is_empty() and th.research_queue[0] == tid:
					th.research_progress = maxi(0, th.research_progress - n)
				else:
					th.research_shelf[tid] = maxi(0, int(th.research_shelf.get(tid, 0)) - n)
			text = "Les plans de « %s » n'ont jamais quitté les archives des Gardiens. Chez %s, un dossier est soudain vide, et personne ne se souvient de l'avoir rempli." % [
					String(Research.tech(tid).get("label", tid)), th.short_name() if th else "?"]
	added.append(state.add_chronicle(text, Espionage.private_to(state, [eid, int(en.get("by", eid))], sid)))
	if sid >= 0:
		_tear(state, eid, sid, added)
	ed["undone"] = int(ed.get("undone", 0)) + 1


# --- Déchirures (prop. 85) ---------------------------------------------------------------------------

static func _tear(state: GameState, eid: int, sid: int, added: Array[Dictionary]) -> void:
	var tears := Insolites.sub(state, "tears")
	var t: Dictionary = tears.get(str(sid), {})
	var n := (int(t.get("n", 0)) if int(t.get("until", 0)) > state.tick else 0) + 1
	tears[str(sid)] = {"n": n, "until": state.tick + _c("tear_days", 720)}
	var sname := state.galaxy.systems[sid].system_name
	if n >= _c("tear_collapse", 3):
		for pid in state.galaxy.systems[sid].planet_ids:
			var c: Colony = state.colonies.get(pid)
			if c != null and c.is_colony() and c.population > 1:
				@warning_ignore("integer_division")
				Insolites.note_departure(state, int(pid), c.population - maxi(1, c.population / 2))
				@warning_ignore("integer_division")
				c.population = maxi(1, c.population / 2)
				Peoples.normalize(c)
				Faiths.normalize(c)
		tears[str(sid)] = {"n": 0, "until": state.tick + _c("tear_days", 720) * 2}
		added.append(state.add_chronicle("Effondrement local à %s : trop de passés défaits au même endroit. Le système bégaie, des villes entières n'ont jamais existé, et la moitié des habitants avec elles." % sname,
				Espionage.public_to(state, [eid])))
		return
	if posmod(hash([state.seed_value, state.tick, sid, "hiatus"]), 1000) < _c("hiatus_pmille", 300) and not Fauna.species("betes_songe").is_empty():
		var f := Fauna.spawn_herd(state, "betes_songe", sid, -1, state.tick + _c("hiatus_days", 180))
		f.fleet_name = "Créatures du Hiatus"
		added.append(state.add_chronicle("Une déchirure s'ouvre à %s, et quelque chose en sort qui n'appartient à aucune époque." % sname, Espionage.public_to(state, [eid])))


static func tear_active(state: GameState, sid: int) -> bool:
	return int((state.insolites.get("tears", {}) as Dictionary).get(str(sid), {}).get("until", 0)) > state.tick


# --- Bulles temporelles (prop. 86) -------------------------------------------------------------------

static func check_bubble(state: GameState, eid: int, sid: int, mode: String) -> String:
	if not is_guardian(state, eid):
		return "seuls les Gardiens plient le temps"
	if sid < 0 or sid >= state.galaxy.systems.size():
		return "système inconnu"
	if int(Insolites.emp(state, eid).get("bub", 0)) > state.tick:
		return "le Sablier se recharge (%d jours)" % (int(Insolites.emp(state, eid)["bub"]) - state.tick)
	var owner := state.system_owner(sid)
	match mode:
		"compression":
			if owner != eid:
				return "la Compression se pose sur un de vos systèmes"
		"dilatation":
			if owner < 0 or owner == eid or GameState.is_npc(owner):
				return "la Dilatation se pose sur le système d'un autre empire"
			if not state.get_empire(eid).explored.has(sid):
				return "système inexploré"
		_:
			return "bulle inconnue"
	if int(Insolites.emp(state, eid).get("sand", 0)) < _c("bubble_sand", 30):
		return "Sable insuffisant (%d / %d)" % [int(Insolites.emp(state, eid).get("sand", 0)), _c("bubble_sand", 30)]
	return ""


static func bubble(state: GameState, eid: int, sid: int, mode: String, added: Array[Dictionary]) -> void:
	var ed := Insolites.emp(state, eid)
	ed["sand"] = int(ed["sand"]) - _c("bubble_sand", 30)
	ed["bub"] = state.tick + _c("bubble_cd_days", 360)
	var pct := _c("bubble_pct", 25) * (1 if mode == "compression" else -1)
	Insolites.sub(state, "bubbles")[str(sid)] = {"pct": pct, "until": state.tick + _c("bubble_days", 360), "o": eid}
	var sname := state.galaxy.systems[sid].system_name
	added.append(state.add_chronicle(("À %s, le temps se resserre : les journées des Gardiens durent un peu plus que celles des autres." if pct > 0 else "À %s, les horloges ralentissent ; les ouvriers jurent qu'ils ont travaillé toute la journée, et les registres disent le contraire.") % sname,
			Espionage.private_to(state, [eid, state.system_owner(sid)], sid)))


## Production d'un système en points de % (déchirure, bulle).
static func system_pct(state: GameState, sid: int) -> int:
	var n := 0
	if tear_active(state, sid):
		n -= _c("tear_pct", 25)
	var b: Dictionary = (state.insolites.get("bubbles", {}) as Dictionary).get(str(sid), {})
	if not b.is_empty() and int(b["until"]) > state.tick:
		n += int(b["pct"])
	return n


static func stability_parts(state: GameState, sid: int, out: Array) -> void:
	if tear_active(state, sid):
		out.append(["Déchirure du temps", _c("tear_stab", -5)])


# --- Longévité et Chronopathie (prop. 87) ------------------------------------------------------------

static func life_pct(state: GameState, eid: int) -> int:
	return _c("life_pct", 250) if is_guardian(state, eid) else 100


## Pouvoirs de la Chronopathie (Psionics._effect).
static func psi_effect(state: GameState, eid: int, power: String, target: int, added: Array[Dictionary]) -> void:
	var e := state.get_empire(eid)
	match power:
		"sable_rendu":
			var ed := Insolites.emp(state, eid)
			if not ed.is_empty():
				ed["sand"] = mini(_c("sand_max", 200), int(ed.get("sand", 0)) + _c("psi_sand", 40))
			added.append(state.add_chronicle("Les chronopathes de %s se souviennent d'un futur où ils avaient plus de temps ; ils en rapportent un peu." % e.display_name(), Espionage.private_to(state, [eid])))
		"deja_vu":
			var b := state.get_empire(target)
			e.dossiers[target] = Espionage._report(state, eid, target, (Espionage.data()["tiers"] as Array).size())
			added.append(state.add_chronicle("Les chronopathes de %s ont déjà vu ce que %s va faire. Ils l'ont même déjà oublié, puis s'en sont souvenus." % [
					e.display_name(), b.display_name()], Espionage.private_to(state, [eid])))


# --- La Boucle : victoire du Paradoxe stable (prop. 88) ----------------------------------------------

static func loop_cost(state: GameState, eid: int) -> Dictionary:
	var costs: Array = Insolites.cfg("sablier").get("loop_costs", [])
	var k := int(Insolites.emp(state, eid).get("loop", 0))
	return costs[mini(k, costs.size() - 1)] if not costs.is_empty() else {}


static func check_loop(state: GameState, eid: int) -> String:
	if not is_guardian(state, eid):
		return "seuls les Gardiens bâtissent la Boucle"
	var ed := Insolites.emp(state, eid)
	if int(ed.get("loop", 0)) >= _c("loop_stages", 3):
		return "la Boucle est fermée"
	if not (ed.get("lp", {}) as Dictionary).is_empty():
		return "une étape de la Boucle est en chantier"
	if hero(state, eid).is_empty():
		return "il faut le Gardien chronal vivant"
	if not state.get_empire(eid).techs.has("paradoxe_stable"):
		return "il faut la technologie Le Paradoxe stable"
	var cost := loop_cost(state, eid)
	if not Economy.can_afford(state.get_empire(eid), cost):
		return "ressources insuffisantes (il faut %s)" % GameData.format_amounts(cost)
	return ""


static func loop(state: GameState, eid: int, added: Array[Dictionary]) -> void:
	Economy.pay(state.get_empire(eid), loop_cost(state, eid))
	var ed := Insolites.emp(state, eid)
	ed["lp"] = {"left": _c("loop_days", 720)}
	added.append(state.add_chronicle("Les Gardiens commencent l'étape %d de la Boucle : un projet dont les plans leur viendront de lui-même, plus tard, c'est-à-dire avant." % (int(ed.get("loop", 0)) + 1),
			Espionage.public_to(state, [eid])))


static func daily(state: GameState, eid: int, ed: Dictionary, month: bool, added: Array[Dictionary]) -> void:
	var lp: Dictionary = ed.get("lp", {})
	if not lp.is_empty():
		lp["left"] = int(lp["left"]) - 1
		if int(lp["left"]) <= 0:
			ed["lp"] = {}
			ed["loop"] = int(ed.get("loop", 0)) + 1
			added.append(state.add_chronicle("Une étape de la Boucle se ferme (%d / %d). Quelque part dans le passé des Gardiens, une technologie arrive, envoyée par elle-même." % [int(ed["loop"]), _c("loop_stages", 3)],
					Espionage.public_to(state, [eid])))
	if int(ed.get("hero", -1)) < 0 and int(ed.get("back", 0)) > 0 and state.tick >= int(ed["back"]):
		ed["back"] = 0
		_spawn_hero(state, eid)
		added.append(state.add_chronicle("Un nouveau Gardien chronal prend le Sablier. Il a l'air de savoir déjà comment tout cela finit, et il ne dit rien.", Espionage.public_to(state, [eid])))
	if not month:
		return
	ed["sand"] = mini(_c("sand_max", 200), int(ed.get("sand", 0)) + _c("sand_month", 5))
	var reg: Array = ed.get("reg", [])
	while not reg.is_empty() and state.tick - int((reg[0] as Dictionary)["t"]) > _c("reg_days", 180):
		reg.pop_front()
	var tears: Dictionary = state.insolites.get("tears", {})
	for k in tears.keys():
		if int(tears[k]["until"]) <= state.tick:
			tears.erase(k)
	var bub: Dictionary = state.insolites.get("bubbles", {})
	for k in bub.keys():
		if int(bub[k]["until"]) <= state.tick:
			bub.erase(k)


static func victory(state: GameState, e: Empire, out: Dictionary) -> void:
	var want := _c("loop_stages", 3)
	var n := int(Insolites.emp(state, e.id).get("loop", 0))
	out["lines"].append("Étapes de la Boucle : %d / %d%s" % [n, want, "" if not hero(state, e.id).is_empty() else " (Gardien chronal tombé)"])
	out["cond"] = n >= want and not hero(state, e.id).is_empty()
	Victory._timed(out, mini(n, want), want)


static func status_lines(state: GameState, eid: int, ed: Dictionary) -> Array[String]:
	var out: Array[String] = []
	out.append("Sable : %d / %d ; Registre : %d événement(s) annulable(s)" % [int(ed.get("sand", 0)), _c("sand_max", 200), ledger(state, eid).size()])
	var lp: Dictionary = ed.get("lp", {})
	out.append("Boucle : %d / %d%s" % [int(ed.get("loop", 0)), _c("loop_stages", 3), (" (étape en cours, %d j)" % int(lp["left"])) if not lp.is_empty() else ""])
	return out
