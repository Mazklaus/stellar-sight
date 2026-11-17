class_name RulersDynasty
extends RefCounted
## La lignée (étude « Souverain et dynastie », bloc C, prop. 10, 17-26, 38, 39).
## - Lois féodales : Primogéniture (l'aîné), Partage (un cadet reçoit un fief lointain qui devient
##   vassal), Élection des lignées (la Diète choisit parmi les trois plus loyaux, +10 de légitimité).
## - Héritiers : dans les régimes héréditaires, des enfants naissent tant que le souverain a un consort
##   (couvées chez les reptiliens, jamais chez les synthétiques, assemblés adultes) ; à 10 ans on choisit
##   leur éducation, à la majorité ils deviennent héros. Les trois premiers forment la Cour et donnent
##   la moitié de leurs aptitudes à l'empire.
## - Régence : un héritier mineur règne sous un régent ; pas de déclaration de guerre, légitimité -1 par
##   mois ; un régent ambitieux peut refuser de rendre le pouvoir.
## - Mariages dynastiques entre régimes héréditaires : opinion +20, revendication réciproque ; une lignée
##   éteinte passe à l'autre en union personnelle (l'empire devient sujet).
## - Renom de la lignée et héritages sur 5 voies (Traditions d'État hors des régimes héréditaires).
## - Étoile montante et prétendants (sécession : un nouvel empire IA naît), extinction sans fin de
##   partie, abdication.
## Héritier : {"id", "name", "g", "born", "apt", "edu", "portrait", "hero" (-1 avant la majorité)}.

static func _h(state: GameState, parts: Array) -> int:
	return absi(hash([state.seed_value, "lignee"] + parts))


static func rules() -> Dictionary:
	return Rulers.rules()


static func r_int(k: String) -> int:
	return Rulers.r_int(k)


# --- Héritages ---------------------------------------------------------------------------------

static func legacy_defs() -> Dictionary:
	return Rulers.data()["legacies"]


static func legacy_label(state: GameState, eid: int) -> String:
	if Rulers.hereditary(state, eid):
		return "Héritages de la maison %s" % String(Rulers.entry(state, eid).get("house", ""))
	return String(Rulers.data().get("traditions_label", "Traditions d'État"))


## Somme d'une valeur des niveaux achetés (legit, apt, life).
static func legacy_sum(state: GameState, eid: int, key: String) -> int:
	var en := Rulers.entry(state, eid)
	if en.is_empty():
		return 0
	var n := 0
	var bought: Dictionary = en.get("legacies", {})
	for t in bought:
		var levels: Array = legacy_defs().get(String(t), {}).get("levels", [])
		for i in mini(int(bought[t]), levels.size()):
			n += int((levels[i] as Dictionary).get(key, 0))
	return n


## Effets cumulés des héritages (stabilité comprise).
static func legacy_fx(state: GameState, eid: int, _stab := false) -> Dictionary:
	var out := {}
	var en := Rulers.entry(state, eid)
	if en.is_empty():
		return out
	var bought: Dictionary = en.get("legacies", {})
	var ks := bought.keys()
	ks.sort()
	for t in ks:
		var levels: Array = legacy_defs().get(String(t), {}).get("levels", [])
		for i in mini(int(bought[t]), levels.size()):
			Research._merge(out, (levels[i] as Dictionary).get("fx", {}).duplicate(true))
	return out


static func legacy_next(state: GameState, eid: int, track: String) -> Dictionary:
	var lv := int((Rulers.entry(state, eid).get("legacies", {}) as Dictionary).get(track, 0))
	var levels: Array = legacy_defs().get(track, {}).get("levels", [])
	return levels[lv] if lv < levels.size() else {}


# --- Cour --------------------------------------------------------------------------------------

static func heirs(state: GameState, eid: int) -> Array:
	return Rulers.entry(state, eid).get("heirs", [])


static func child_age(state: GameState, c: Dictionary) -> int:
	@warning_ignore("integer_division")
	return (state.tick - int(c["born"])) / Rulers.DAYS_PER_YEAR


## La moitié des aptitudes des trois premiers héritiers (plafond 3 par aptitude).
static func court_apts(state: GameState, eid: int) -> Dictionary:
	var out := {}
	var hs := heirs(state, eid)
	var pct := r_int("court_pct")
	for i in mini(r_int("court_size"), hs.size()):
		var c: Dictionary = hs[i]
		for a in Rulers.APTS:
			out[a] = int(out.get(a, 0)) + int(c["apt"].get(a, 0)) * pct
	for a in out:
		@warning_ignore("integer_division")
		out[a] = mini(3, int(out[a]) / 100)
	return out


static func in_regency(state: GameState, eid: int) -> bool:
	return not (Rulers.entry(state, eid).get("regent", {}) as Dictionary).is_empty()


# --- Couronnement, fin de règne ----------------------------------------------------------------

static func on_crown(state: GameState, eid: int, r: Dictionary) -> void:
	var en := Rulers.entry(state, eid)
	Court.on_new_ruler(state, eid, r)
	if Rulers.hereditary(state, eid) and Rulers.mortal(state):
		if int(en.get("spouse", -1)) < 0:
			var nm := Rulers._name_pick(state, eid, ["consort", eid, state.tick], "f" if String(r["g"]) == "m" else "m")
			en["consort"] = String(nm[0])
		en["next_child"] = state.tick + _birth_gap(state, eid)


static func _birth_gap(state: GameState, eid: int) -> int:
	var b: Array = rules()["birth_every_days"]
	return int(b[0]) + _h(state, ["gap", eid, state.tick]) % maxi(1, int(b[1]) - int(b[0]))


static func on_reign_end(state: GameState, eid: int, r: Dictionary, legit: int, _how: String) -> void:
	var en := Rulers.entry(state, eid)
	@warning_ignore("integer_division")
	en["renown"] = int(en.get("renown", 0)) + (legit + (r.get("cogs", []) as Array).size() * r_int("renown_per_cognomen")) / maxi(1, r_int("renown_death_div"))
	en["star"] = -1


# --- Succession dynastique ---------------------------------------------------------------------

## Le prochain souverain d'une dynastie selon la loi : héritier désigné (Lignées d'Ossarane), aîné des
## enfants, Diète ; sinon union personnelle ou nouvelle maison.
static func heir_succession(state: GameState, eid: int, how: String, added: Array[Dictionary]) -> void:
	var en := Rulers.entry(state, eid)
	var e := state.get_empire(eid)
	var law := String(en.get("law", "primogeniture"))
	var r: Dictionary = {}
	var minor_child := {}
	var bastard := false
	if law == "election":
		r = _diet(state, eid)
	if r.is_empty():
		var hh := Heroes.heir_of(state, eid)
		if not hh.is_empty():
			r = Rulers.from_hero(state, eid, hh, "heritier")
			e.heir_loyalty = int(Diplomacy.ability("heir")["start"]) if Diplomacy.has_ability(state, eid, "heir") else e.heir_loyalty
	if r.is_empty():
		var hs := heirs(state, eid)
		if not hs.is_empty():
			var c: Dictionary = hs[0]
			hs.remove_at(0)
			r = _from_child(state, eid, c, "heritier")
			bastard = int(c.get("bastard", 0)) > 0
			if child_age(state, c) < r_int("majority"):
				minor_child = c
			if law == "partage":
				_partage(state, eid, added)
	if r.is_empty():
		_extinction(state, eid, added)
		return
	if how == "abdicate":
		Rulers.crown(state, eid, r, added)
		Rulers.adjust(state, eid, r_int("abdicate_adj"))
	else:
		Rulers.crown(state, eid, r, added)
	if bastard:
		Rulers.adjust(state, eid, -15)
	if not minor_child.is_empty():
		_start_regency(state, eid, added)


static func _from_child(state: GameState, eid: int, c: Dictionary, how: String) -> Dictionary:
	var hid := int(c.get("hero", -1))
	var arch := Rulers._arch_for_cls(state, eid, String(c.get("edu", "intendant")) if String(c.get("edu", "")) != "" else "intendant", ["c", int(c["id"])])
	if state.heroes.has(hid):
		state.heroes.erase(hid)
		Relics.on_hero_gone(state, hid)
	return {"name": String(c["name"]), "g": String(c["g"]), "portrait": Rulers._pick_portrait(state, eid, ["child", int(c["id"])]),
			"born": int(c["born"]), "life": Rulers.life_of(state, eid), "arch": arch, "apt": (c["apt"] as Dictionary).duplicate(),
			"cogs": [], "post": "", "target": -1, "how": how, "house": String(Rulers.entry(state, eid).get("house", "")), "ord": 1,
			"from": state.tick, "hero": -1}


## Élection des lignées : la Diète choisit parmi les trois plus loyaux (héros et héritiers adultes).
static func _diet(state: GameState, eid: int) -> Dictionary:
	var best := {}
	var bv := -1
	var pool: Array[Dictionary] = []
	for id in Heroes.ids_of(state, eid):
		var h: Dictionary = state.heroes[id]
		if not Heroes.is_prisoner(h) and int(h.get("lender", -1)) < 0:
			pool.append(h)
	pool.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("loy", 50)) > int(b.get("loy", 50)))
	pool = pool.slice(0, 3)
	for h in pool:
		var v := int(h["lvl"]) * 10 + int(h.get("loy", 50))
		if v > bv:
			bv = v
			best = h
	if best.is_empty() or Heroes.ids_of(state, eid).size() < 2:
		return {}
	var hs := heirs(state, eid)
	for c in hs:
		if int(c.get("hero", -1)) == int(best["id"]):
			hs.erase(c)
			return _from_child(state, eid, c, "elu")
	return Rulers.from_hero(state, eid, best, "elu")


## Partage : le cadet adulte reçoit le système le plus lointain, qui devient un empire vassal.
static func _partage(state: GameState, eid: int, added: Array[Dictionary]) -> void:
	var hs := heirs(state, eid)
	var made := 0
	var i := 0
	while i < hs.size() and made < r_int("partage_fiefs"):
		var c: Dictionary = hs[i]
		if child_age(state, c) < r_int("majority"):
			i += 1
			continue
		var sid := _far_system(state, eid)
		if sid < 0:
			return
		hs.remove_at(i)
		var r := _from_child(state, eid, c, "heritier")
		var nid := spawn_empire(state, eid, [sid], r, "fief", added)
		if nid >= 0:
			made += 1


## Le système possédé le plus loin de la capitale (hors capitale), -1 s'il n'y en a qu'un.
static func _far_system(state: GameState, eid: int, skip: Array = []) -> int:
	var cap := FactionTraits.capital_system(state, eid)
	var best := -1
	var bd := -1
	for sid in state.galaxy.systems.size():
		if state.system_owner(sid) != eid or sid == cap or skip.has(sid):
			continue
		var d := 0
		if cap >= 0:
			d = int(state.galaxy.systems[sid].position.distance_to(state.galaxy.systems[cap].position))
		if d > bd:
			bd = d
			best = sid
	return best


## Lignée éteinte : union personnelle avec l'empire du conjoint, sinon une nouvelle maison naît d'un héros.
static func _extinction(state: GameState, eid: int, added: Array[Dictionary]) -> void:
	var en := Rulers.entry(state, eid)
	var e := state.get_empire(eid)
	var sp := int(en.get("spouse", -1))
	var se := state.get_empire(sp)
	if se != null and not se.eliminated and Rulers.has_ruler(state, sp) and Rulers.legitimacy(state, sp) >= 50 \
			and not Vassals.is_subject(state, sp) and not Vassals.is_subject(state, eid):
		var r := Rulers.make_ruler(state, eid, ["union", eid, state.tick], "union")
		r["house"] = String(Rulers.entry(state, sp).get("house", ""))
		Rulers.crown(state, eid, r, added)
		if r_int("union_vassal") > 0:
			Vassals.bind(state, sp, eid, "vassal", Vassals.preset_clauses("vassal"), 60, true)
		added.append(state.add_chronicle("La lignée de %s s'éteint. Par le sang de son mariage, %s réclame le trône : union personnelle, %s devient son sujet." % [
				e.display_name(), se.display_name(), e.short_name()], Espionage.public_to(state, [eid, sp])))
		return
	var houses: Array = Rulers.data()["houses"]
	en["house"] = String(houses[_h(state, ["nouvelle", eid, state.tick]) % houses.size()])
	var gh := Court.strongest_house(state, eid)
	if not gh.is_empty():
		en["house"] = String(gh["name"])  # une Grande Maison monte sur le trône
	var best := RulersSuccession._best_hero(state, eid, "intendant")
	var r2: Dictionary
	if not best.is_empty() and Heroes.ids_of(state, eid).size() >= 2:
		r2 = Rulers.from_hero(state, eid, best, "nouvelle_maison")
	else:
		r2 = Rulers.make_ruler(state, eid, ["maison", eid, state.tick], "nouvelle_maison")
	r2["house"] = String(en["house"])
	Rulers.crown(state, eid, r2, added)
	en["unrest"] = state.tick + r_int("extinction_unrest_days")
	added.append(state.add_chronicle("La lignée de %s s'éteint sans héritier. La partie continue : la maison %s prend le trône avec %s, sous les murmures." % [
			e.display_name(), String(en["house"]), Rulers.full_name(state, eid)], Espionage.public_to(state, [eid])))


# --- Régence -----------------------------------------------------------------------------------

static func _start_regency(state: GameState, eid: int, added: Array[Dictionary]) -> void:
	var en := Rulers.entry(state, eid)
	if Rulers._sp_arch(state, eid) == "synthetique":
		return
	var h := RulersSuccession._best_hero(state, eid, "orateur")
	en["regent"] = _regent_from(h)
	var dh := Court.devoted_head(state, eid)
	if h.is_empty() and not dh.is_empty():
		en["regent"] = {"hero": -1, "name": String(dh["name"]), "apt": dh["apt"]}
		h = {"name": String(dh["name"])}
	var ev := state.next_event_id
	Events.push(state, eid, "ruler_regency", {}, added)
	var r: Dictionary = en["r"]
	Rulers._note(state, eid, ev, {"regency_text": "%s n'a que %d ans. Jusqu'à sa majorité, un régent gouvernera : pas de déclaration de guerre, et la légitimité s'use chaque mois." % [
			Rulers.full_name(state, eid), Rulers.age(state, r)], "regent": String(h.get("name", "un conseil")), "hero": int(h.get("id", -1))})
	Relics.touch(state)


static func _regent_from(h: Dictionary) -> Dictionary:
	if h.is_empty():
		return {"hero": -1, "name": "Conseil de régence", "apt": {"gestion": 2, "guerre": 1, "eloquence": 2, "intrigue": 1}}
	var apt := {"gestion": 1, "guerre": 1, "eloquence": 1, "intrigue": 1}
	apt[Rulers.apt_of_cls(String(h["cls"]))] = mini(6, int(h["lvl"]) + 1)
	return {"hero": int(h["id"]), "name": String(h["name"]), "apt": apt}


static func _regency_month(state: GameState, eid: int, en: Dictionary, added: Array[Dictionary]) -> void:
	var rg: Dictionary = en.get("regent", {})
	if rg.is_empty():
		return
	var r: Dictionary = en["r"]
	if r.is_empty():
		en["regent"] = {}
		return
	Rulers.adjust(state, eid, r_int("regency_month_adj"))
	if Rulers.age(state, r) < r_int("majority"):
		return
	# Majorité : le régent rend le pouvoir… ou pas.
	var hid := int(rg.get("hero", -1))
	en["regent"] = {}
	Relics.touch(state)
	var e := state.get_empire(eid)
	if state.heroes.has(hid) and int(state.heroes[hid]["owner"]) == eid and _h(state, ["refus", eid, state.tick]) % 100 < r_int("regent_refuse_pct"):
		var h: Dictionary = state.heroes[hid]
		var nr := Rulers.from_hero(state, eid, h, "usurpateur")
		Rulers.die(state, eid, "est écarté du trône par son régent", added, "seized", -1, nr)
		added.append(state.add_chronicle("Coup de palais chez %s : le régent refuse de rendre le pouvoir et se proclame %s." % [
				e.display_name(), Rulers.full_name(state, eid)], Espionage.public_to(state, [eid])))
		return
	added.append(state.add_chronicle("%s atteint sa majorité et gouverne seul. Le régent rend les sceaux, avec un soupir." % Rulers.full_name(state, eid),
			Espionage.private_to(state, [eid])))


# --- Chaque mois -------------------------------------------------------------------------------

static func monthly_all(state: GameState, added: Array[Dictionary]) -> void:
	var keys := (state.rulers["e"] as Dictionary).keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return int(a) < int(b))
	for k in keys:
		var eid := int(k)
		var e := state.get_empire(eid)
		if e == null or e.eliminated:
			continue
		var en: Dictionary = state.rulers["e"][k]
		if (en["r"] as Dictionary).is_empty():
			continue
		var l := Rulers.legitimacy(state, eid)
		@warning_ignore("integer_division")
		en["renown"] = int(en.get("renown", 0)) + l / maxi(1, r_int("renown_month_legit"))
		_regency_month(state, eid, en, added)
		if not Rulers.mortal(state):
			continue
		_births(state, eid, en, added)
		_grow(state, eid, en, added)
		_star(state, eid, en, l, added)
		_pretender(state, eid, en, l, added)


static func _births(state: GameState, eid: int, en: Dictionary, added: Array[Dictionary]) -> void:
	if not Rulers.hereditary(state, eid) or Rulers._sp_arch(state, eid) == "synthetique":
		return
	var r: Dictionary = en["r"]
	var a := Rulers.age(state, r)
	if a < 18 or a > 60 or (String(en.get("consort", "")) == "" and int(en.get("spouse", -1)) < 0):
		return
	if state.tick < int(en.get("next_child", 0)) or heirs(state, eid).size() >= r_int("max_children"):
		return
	en["next_child"] = state.tick + _birth_gap(state, eid)
	var n := 2 if Rulers._sp_arch(state, eid) == "reptilien" else 1
	var names := PackedStringArray()
	for i in n:
		if heirs(state, eid).size() >= r_int("max_children"):
			break
		var cid := int(en.get("child_n", 0))
		en["child_n"] = cid + 1
		var salt := ["enfant", eid, cid]
		var nm := Rulers._name_pick(state, eid, salt)
		var apt := Rulers.roll_apts(state, salt, Rulers._pick_arch(state, eid, salt), legacy_sum(state, eid, "apt"))
		for k in apt:
			@warning_ignore("integer_division")
			apt[k] = int(apt[k]) / 2 + legacy_sum(state, eid, "apt")
		(en["heirs"] as Array).append({"id": cid, "name": String(nm[0]), "g": String(nm[1]), "born": state.tick, "apt": apt, "edu": "", "hero": -1})
		names.append(String(nm[0]))
	if not names.is_empty():
		added.append(state.add_chronicle("Naissance à la cour de %s : %s. On compte déjà les doigts, et les prétentions." % [
				state.get_empire(eid).display_name(), " et ".join(names)], Espionage.private_to(state, [eid])))


## Héritiers qui grandissent : éducation par défaut à 10 ans si personne n'a choisi, héros à la majorité.
static func _grow(state: GameState, eid: int, en: Dictionary, added: Array[Dictionary]) -> void:
	var hs: Array = en["heirs"]
	var i := 0
	while i < hs.size():
		var c: Dictionary = hs[i]
		var hid := int(c.get("hero", -1))
		if hid >= 0 and not state.heroes.has(hid):
			hs.remove_at(i)  # mort, capturé puis exécuté, passé à l'ennemi
			continue
		if hid >= 0 and int(state.heroes[hid]["owner"]) != eid:
			hs.remove_at(i)
			continue
		var a := child_age(state, c)
		if String(c["edu"]) == "" and a >= r_int("education_age") + 2:
			_educate(state, c, _best_cls(c), eid)
		if hid < 0 and a >= r_int("majority"):
			var cls := String(c["edu"]) if String(c["edu"]) != "" else _best_cls(c)
			var cand := {"name": "%s %s" % [String(c["name"]), String(en.get("house", ""))], "portrait": Heroes.portraits_for(Heroes._archetype(state, eid))[_h(state, ["hp", eid, int(c["id"])]) % maxi(1, Heroes.portraits_for(Heroes._archetype(state, eid)).size())] if not Heroes.portraits_for(Heroes._archetype(state, eid)).is_empty() else "",
					"cls": cls, "age": a, "traits": [], "amb": ""}
			var nid := Heroes.recruit(state, eid, cand)
			Heroes.meta(state, eid)["got"] = int(Heroes.meta(state, eid)["got"]) - 1
			state.heroes[nid]["blood"] = 1
			state.heroes[nid]["loy"] = 80
			c["hero"] = nid
			added.append(state.add_chronicle("%s atteint sa majorité et rejoint les %s de %s." % [String(c["name"]), Heroes.noun(state, eid, true).to_lower(),
					state.get_empire(eid).display_name()], Espionage.private_to(state, [eid])))
		i += 1


static func _best_cls(c: Dictionary) -> String:
	var best := "gestion"
	for a in Rulers.APTS:
		if int(c["apt"].get(a, 0)) > int(c["apt"].get(best, 0)):
			best = a
	return String(Rulers.data()["aptitudes"][best]["cls"])


static func _educate(state: GameState, c: Dictionary, cls: String, eid := -1) -> void:
	c["edu"] = cls
	var a := Rulers.apt_of_cls(cls)
	var bonus := 0
	if eid >= 0 and _h(state, ["precepteur", eid, int(c.get("id", 0))]) % 100 < Court.tutor_pct(state, eid):
		bonus = 1  # le Précepteur de la cour
	c["apt"][a] = mini(int(Rulers.data().get("apt_max", 6)), int(c["apt"].get(a, 0)) + 2 + bonus)


# --- Étoile montante, prétendants --------------------------------------------------------------

## Renom d'un héros comparé à la légitimité : niveau × 20.
static func hero_renown(h: Dictionary) -> int:
	return int(h.get("lvl", 1)) * 20


static func _star(state: GameState, eid: int, en: Dictionary, legit: int, added: Array[Dictionary]) -> void:
	if int(en.get("star", -1)) >= 0 or Rulers.immortal_kind(state, eid):
		return
	var seen: Array = en.get("star_seen", [])
	for id in Heroes.ids_of(state, eid):
		var h: Dictionary = state.heroes[id]
		if seen.has(id) or Heroes.is_prisoner(h) or int(h.get("heir", 0)) > 0 or int(h.get("blood", 0)) > 0 or int(h.get("lender", -1)) >= 0:
			continue
		if hero_renown(h) <= legit + r_int("star_margin"):
			continue
		en["star"] = id
		seen.append(id)
		en["star_seen"] = seen
		var ev := state.next_event_id
		Events.push(state, eid, "ruler_star", {"hero": id}, added)
		Rulers._note(state, eid, ev, {"star_text": "%s, %s de niveau %d, éclipse %s : son renom dépasse la légitimité du trône (%d). La cour murmure. Que faire ?" % [
				h["name"], String(Heroes.class_def(String(h["cls"])).get("label", "")).to_lower(), int(h["lvl"]), Rulers.full_name(state, eid), legit],
				"star_cost": GameData.format_amounts(rules()["star_buy"]), "hero": id})
		return


## Sous 25 de légitimité pendant un an : un prétendant se proclame, des systèmes font sécession.
static func _pretender(state: GameState, eid: int, en: Dictionary, legit: int, added: Array[Dictionary]) -> void:
	if legit > r_int("pretender_legit") or Rulers.immortal_kind(state, eid):
		en["low_since"] = 0
		return
	if int(en.get("low_since", 0)) <= 0:
		en["low_since"] = state.tick
		return
	if state.tick - int(en["low_since"]) < r_int("pretender_days"):
		return
	en["low_since"] = 0
	var sids: Array = []
	var total := 0
	for sid in state.galaxy.systems.size():
		if state.system_owner(sid) == eid:
			total += 1
	if total < 4:
		return
	@warning_ignore("integer_division")
	var want := maxi(1, total / 4)
	for i in want:
		var s := _far_system(state, eid, sids)
		if s < 0:
			break
		sids.append(s)
	var r := Rulers.make_ruler(state, eid, ["pretendant", eid, state.tick], "usurpateur")
	var nid := spawn_empire(state, eid, sids, r, "pretender", added)
	if nid >= 0:
		Rulers.adjust(state, eid, 10)  # l'abcès est crevé


# --- Nouvel empire en cours de partie ----------------------------------------------------------

## Crée un empire IA à partir de systèmes de parent (fief du Partage ou prétendant) ; renvoie son id.
static func spawn_empire(state: GameState, parent: int, sids: Array, r: Dictionary, why: String, added: Array[Dictionary]) -> int:
	var pe := state.get_empire(parent)
	var nid := state.empires.size()
	if pe == null or nid >= GameState.NPC_ID - 10 or sids.is_empty():
		return -1
	var e := Empire.new()
	e.id = nid
	e.faction_id = pe.faction_id
	var rank := 0
	for o in state.empires:
		if o.faction_id == e.faction_id:
			rank += 1
	e.name_suffix = GameState.ROMAN[mini(rank, GameState.ROMAN.size() - 1)]
	var used: Array[Color] = []
	for o in state.empires:
		used.append(o.color())
	for hex in Empire.PALETTE:
		if not Empire.color_taken(Color.html(hex), used):
			e.color_hex = hex
			break
	var rules_g := GameData.rules()
	for res in GameData.resource_ids():
		@warning_ignore("integer_division")
		e.resources[res] = int(rules_g["start_resources"].get(res, 0)) / 2
	e.techs = pe.techs.duplicate()
	e.marks_log = pe.marks_log.duplicate(true)
	e.explored = pe.explored.duplicate()
	e.ai_level = pe.ai_level if pe.ai_level != "" else AiLevels.default_id()
	e.ai_temperament = AiLevels.default_temperament()
	if FactionTraits.has_fervor(e.faction()):
		e.fervor = int(e.faction()["fervor"]["start"])
	state.empires.append(e)
	for sid in sids:
		Stability._transfer(state, int(sid), parent, nid)
		state.stability.erase(int(sid))
	# Capitale : la plus grande colonie reçue.
	var best := -1
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner == nid and c.is_colony() and (best < 0 or c.population > (state.colonies[best] as Colony).population):
			best = pid
	e.capital_planet = best
	e.home_planet = best
	for o in [parent] + pe.contacts:
		var oe := state.get_empire(int(o))
		if oe == null or int(o) == nid:
			continue
		if not e.contacts.has(int(o)):
			e.contacts.append(int(o))
		if not oe.contacts.has(nid):
			oe.contacts.append(nid)
			oe.contacts.sort()
	e.contacts.sort()
	state.rebuild_ownership()
	FleetSystem.update_exploration(state)
	if not state.rulers.is_empty() and not r.is_empty():
		var en := Rulers._blank(state, nid)
		en["parent"] = parent
		(state.rulers["e"] as Dictionary)[str(nid)] = en
		Rulers.crown(state, nid, r, [], false)
	Relics.touch(state)
	if why == "fief":
		Vassals.bind(state, parent, nid, "vassal", Vassals.preset_clauses("vassal"), 80, true)
		added.append(state.add_chronicle("Partage : %s reçoit %s en fief. Ainsi naît %s, vassal de %s ; l'empire se morcelle, mais reste en famille." % [
				Rulers.full_name(state, nid), state.galaxy.systems[int(sids[0])].system_name, e.display_name(), pe.display_name()],
				Espionage.public_to(state, [parent, nid])))
	elif why == "fronde":
		Combat.start_war(state, nid, parent)  # guerre civile (voir CourtIntrigue.civil_war)
	elif why == "transcend":
		pass  # État successeur d'un peuple parti (voir TranscendenceWorld) : pas de guerre
	else:
		Combat.start_war(state, nid, parent)
		added.append(state.add_chronicle("Un prétendant se lève contre %s : %s entraîne %d système(s) dans la sécession et fonde %s. La guerre de succession commence." % [
				pe.display_name(), Rulers.full_name(state, nid), sids.size(), e.display_name()], Espionage.public_to(state, [parent, nid])))
	return nid


# --- Diplomatie --------------------------------------------------------------------------------

static func opinion_parts(state: GameState, a: int, b: int) -> Array:
	var out := []
	var eb := Rulers.entry(state, b)
	if eb.is_empty():
		return out
	var el := int(Rulers.apts(state, b)["eloquence"])
	if el > 0:
		out.append(["Éloquence de son souverain", el])
	if int(eb.get("spouse", -1)) == a:
		out.append(["Mariage dynastique", r_int("marriage_opinion")])
	return out


static func married(state: GameState, a: int, b: int) -> bool:
	return int(Rulers.entry(state, a).get("spouse", -1)) == b


# --- Ordres ------------------------------------------------------------------------------------

static func check_act(state: GameState, eid: int, act: String, x: int, s: String) -> String:
	var en := Rulers.entry(state, eid)
	var e := state.get_empire(eid)
	match act:
		"law":
			if Rulers.kind(state, eid) != "dynastie":
				return "seule une dynastie a une loi de succession"
			if not (Rulers.data()["laws"] as Dictionary).has(s):
				return "loi inconnue"
			if String(en.get("law", "")) == s:
				return "c'est déjà la loi"
			if not Economy.can_afford(e, rules()["law_change"]):
				return "pas assez d'influence"
			return ""
		"educate":
			for c in en.get("heirs", []):
				if int(c["id"]) == x:
					if String(c["edu"]) != "":
						return "son éducation est déjà faite"
					if child_age(state, c) < r_int("education_age"):
						return "trop jeune : l'éducation commence à %d ans" % r_int("education_age")
					if not Heroes.CLASSES.has(s):
						return "éducation inconnue"
					return ""
			return "héritier inconnu"
		"legacy":
			var nx := legacy_next(state, eid, s)
			if not legacy_defs().has(s):
				return "voie inconnue"
			if nx.is_empty():
				return "voie achevée"
			if int(en.get("renown", 0)) < int(nx["cost"]):
				return "il faut %d de renom" % int(nx["cost"])
			return ""
		"marry":
			if not Rulers.mortal(state):
				return "les souverains immortels ne se marient pas"
			if not Rulers.hereditary(state, eid):
				return "seule une dynastie arrange des mariages"
			var t := state.get_empire(x)
			if t == null or t.eliminated or x == eid or not e.contacts.has(x):
				return "empire inconnu"
			if not Rulers.hereditary(state, x) or Rulers.entry(state, x).is_empty():
				return "cet empire n'a pas de dynastie"
			if int(en.get("spouse", -1)) >= 0 or int(Rulers.entry(state, x).get("spouse", -1)) >= 0:
				return "déjà lié par un mariage"
			if Combat.at_war(state, eid, x):
				return "on ne marie pas ses ennemis"
			if (en["r"] as Dictionary).is_empty() or Rulers.ruler(state, x).is_empty():
				return "un trône est vacant"
			return ""
		"abdicate":
			if not Rulers.mortal(state) or Rulers.immortal_kind(state, eid):
				return "ce souverain ne quitte pas le trône"
			if (en["r"] as Dictionary).is_empty():
				return "le trône est vacant"
			if Rulers.kind(state, eid) == "dynastie" and Heroes.heir_of(state, eid).is_empty() and heirs(state, eid).is_empty():
				return "il faut un héritier pour abdiquer"
			return ""
	return "ordre inconnu"


static func act(state: GameState, eid: int, act_: String, x: int, s: String, added: Array[Dictionary]) -> void:
	var en := Rulers.entry(state, eid)
	var e := state.get_empire(eid)
	match act_:
		"law":
			Economy.pay(e, rules()["law_change"])
			en["law"] = s
			Rulers.adjust(state, eid, r_int("law_change_adj"))
			added.append(state.add_chronicle("%s change la loi de succession : %s." % [e.display_name(), String(Rulers.data()["laws"][s]["label"])],
					Espionage.private_to(state, [eid])))
		"educate":
			for c in en.get("heirs", []):
				if int(c["id"]) == x:
					_educate(state, c, s, eid)
		"legacy":
			var nx := legacy_next(state, eid, s)
			en["renown"] = int(en["renown"]) - int(nx["cost"])
			var lg: Dictionary = en["legacies"]
			lg[s] = int(lg.get(s, 0)) + 1
			Relics.touch(state)
			added.append(state.add_chronicle("%s : nouvel héritage, %s." % [legacy_label(state, eid), String(nx["label"])], Espionage.private_to(state, [eid])))
		"marry":
			var t := state.get_empire(x)
			if t.is_ai():
				if Diplomacy.opinion(state, x, eid) >= 0:
					marry(state, eid, x, added)
				else:
					added.append(state.add_chronicle("%s décline la demande en mariage de %s. Poliment, mais fermement." % [t.display_name(), e.display_name()],
							Espionage.public_to(state, [eid, x])))
			else:
				var ev := state.next_event_id
				Events.push(state, x, "ruler_marriage", {"rival": eid}, added)
				Rulers._note(state, x, ev, {"marriage_text": "%s demande la main de notre souverain pour %s. Une alliance de sang : opinion +%d, et chaque lignée pourra réclamer le trône de l'autre si elle s'éteint." % [
						e.display_name(), Rulers.full_name(state, eid), r_int("marriage_opinion")], "from": eid})
		"abdicate":
			Rulers.die(state, eid, "abdique en faveur de son héritier", added, "abdicate")


static func marry(state: GameState, a: int, b: int, added: Array[Dictionary]) -> void:
	var ea := Rulers.entry(state, a)
	var eb := Rulers.entry(state, b)
	ea["spouse"] = b
	eb["spouse"] = a
	ea["consort"] = String(Rulers.ruler(state, b).get("name", ""))
	eb["consort"] = String(Rulers.ruler(state, a).get("name", ""))
	added.append(state.add_chronicle("Mariage dynastique : %s et %s unissent leurs lignées. Les ambassadeurs pleurent, les juristes prennent des notes." % [
			state.get_empire(a).display_name(), state.get_empire(b).display_name()], Espionage.public_to(state, [a, b])))


## Choix des cartes de la lignée (Étoile montante, mariage, régence).
static func apply_fx(state: GameState, eid: int, item: Dictionary, fx: Dictionary, n: Dictionary, added: Array[Dictionary]) -> void:
	var en := Rulers.entry(state, eid)
	var e := state.get_empire(eid)
	match String(fx.get("act", "")):
		"star_crown":
			var hid := int(n.get("hero", -1))
			en["star"] = -1
			if state.heroes.has(hid) and int(state.heroes[hid]["owner"]) == eid and Rulers.has_ruler(state, eid):
				var nr := Rulers.from_hero(state, eid, state.heroes[hid], "elu")
				Rulers.die(state, eid, "abdique en faveur de l'étoile montante", added, "abdicate", -1, nr)
		"star_buy":
			en["star"] = -1
			Economy.pay(e, rules()["star_buy"])
			var hid2 := int(n.get("hero", -1))
			if state.heroes.has(hid2):
				state.heroes[hid2]["loy"] = mini(100, int(state.heroes[hid2].get("loy", 50)) + 20)
		"star_away":
			en["star"] = -1
			var hid3 := int(n.get("hero", -1))
			if state.heroes.has(hid3) and int(state.heroes[hid3]["owner"]) == eid:
				state.heroes.erase(hid3)
				Relics.on_hero_gone(state, hid3)
				for id in Heroes.ids_of(state, eid):
					var h: Dictionary = state.heroes[id]
					h["loy"] = clampi(int(h.get("loy", 50)) + r_int("star_set_aside_loyalty"), 0, 100)
		"marry_yes":
			var from := int(n.get("from", -1))
			if check_act(state, from, "marry", eid, "") == "":
				marry(state, from, eid, added)
		"marry_no":
			var from2 := int(n.get("from", -1))
			if state.get_empire(from2) != null:
				added.append(state.add_chronicle("%s décline la demande en mariage de %s." % [e.display_name(), state.get_empire(from2).display_name()],
						Espionage.public_to(state, [eid, from2])))
		"regent_yes":
			pass
		"regent_council":
			if not (en.get("regent", {}) as Dictionary).is_empty():
				en["regent"] = _regent_from({})
				Relics.touch(state)
