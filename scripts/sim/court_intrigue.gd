class_name CourtIntrigue
extends RefCounted
## La cour, deuxième volet (voir Court) : choix des maisons de départ, missions des grands offices
## (présents, pacification, emprisonnement, secrets et leviers, ambassades, intercession), exil,
## courtisan élevé au rang de héros, mariages, grandes fêtes et train de la cour, Étoile montante,
## Fronde, ultimatum et guerre civile par sécession, maisons des vaincus, opérations d'espionnage.


static func r_int(key: String) -> int:
	return Court.r_int(key)


static func rules() -> Dictionary:
	return Court.rules()


static func _h(state: GameState, parts: Array) -> int:
	return absi(hash([state.seed_value, "cour_intrigue"] + parts))


static func _chron(state: GameState, eid: int, text: String, added: Array[Dictionary], public := false) -> void:
	added.append(state.add_chronicle(text, Espionage.public_to(state, [eid]) if public else Espionage.private_to(state, [eid])))


static func _cd_ok(en: Dictionary, key: String, state: GameState) -> bool:
	return int((en["cd"] as Dictionary).get(key, 0)) <= state.tick


static func _set_cd(en: Dictionary, key: String, state: GameState, days: int) -> void:
	(en["cd"] as Dictionary)[key] = state.tick + days


# --- Choix des maisons de départ ---------------------------------------------------------------

## Premier bilan : quatre familles se présentent, le trône en renvoie une (carte court_houses).
static func offer_houses(state: GameState, eid: int, added: Array[Dictionary]) -> void:
	var en := Court.entry(state, eid)
	if int(en.get("sel", 1)) != 0:
		return
	en["sel"] = 2  # carte en attente
	var offer: Array = en.get("offer", [])
	if offer.size() < 2:
		en["sel"] = 1
		return
	var lines := PackedStringArray()
	for hid in offer:
		var h := Court.house(state, eid, int(hid))
		var v := Court.voc_def(String(h["voc"]))
		lines.append("• %s, des %s : %s Siège : %s." % [String(h["name"]), String(v.get("label", "")).to_lower(),
				String(v.get("text", "")), String(v.get("seat_text", ""))])
	Court.push_card(state, eid, "court_houses", {"offer": offer.duplicate(), "houses_text": "\n".join(lines)}, added)


# --- Chaque mois -------------------------------------------------------------------------------

## Avant les bilans d'empire : systèmes passés d'une cour à l'autre (maisons des vaincus).
static func conquests(state: GameState, added: Array[Dictionary]) -> void:
	var sys: Dictionary = state.court["sys"]
	var lost := {}  # "P:hid" -> [P, hid, Q]
	var keys := sys.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return int(a) < int(b))
	for k in keys:
		var sid := int(k)
		var prev := int(sys[k])
		var cur := state.system_owner(sid)
		if cur == prev or cur < 0 or GameState.is_npc(cur):
			continue
		var hid := int((Court.entry(state, prev).get("fiefs", {}) as Dictionary).get(str(k), -1))
		if hid < 0 or not Court.applies(state, cur):
			continue
		lost["%d:%d" % [prev, hid]] = [prev, hid, cur]
	for key in lost:
		var p := int(lost[key][0])
		var hid2 := int(lost[key][1])
		var q := int(lost[key][2])
		var left := 0
		for sid2 in Court.fiefs_of(state, p, hid2):
			if state.system_owner(sid2) == p:
				left += 1
		var pe := state.get_empire(p)
		if left > 0 and pe != null and not pe.eliminated:
			continue
		var h := Court.house(state, p, hid2)
		if h.is_empty() or Court.houses(state, q).size() >= r_int("conquered_max") + Court.start_count(state, q) - 3 + 2:
			continue
		var pname := pe.display_name() if pe != null else "?"
		Court.push_card(state, q, "court_conquered", {"src": p, "src_h": hid2, "conq_house": String(h["name"]),
				"conq_text": "Les fiefs de %s %s, des %s de %s, sont tombés entre nos mains. Ses membres attendent, dans la poussière de leur salle d'armes, de savoir ce que nous ferons d'eux." % [
					String(Court.words(state, p)["the"]), String(h["name"]), String(Court.voc_def(String(h["voc"])).get("label", "")).to_lower(), pname]}, added)


static func monthly_all(_state: GameState, _added: Array[Dictionary]) -> void:
	pass


static func monthly(state: GameState, eid: int, added: Array[Dictionary]) -> void:
	var en := Court.entry(state, eid)
	_star(state, eid, en, added)
	for k in (en["levers"] as Dictionary).keys():
		if int(en["levers"][k]) <= state.tick:
			(en["levers"] as Dictionary).erase(k)
	for k in (en["pacified"] as Dictionary).keys():
		if int(en["pacified"][k]) <= state.tick:
			(en["pacified"] as Dictionary).erase(k)
	if Court.peaceful(state):
		(en["fronde"] as Dictionary).clear()
		return
	var ult: Dictionary = en["ult"]
	if not ult.is_empty() and Court.house(state, eid, int(ult["h"])).is_empty():
		en["ult"] = {}
	for h: Dictionary in Court.houses(state, eid).duplicate():
		var key := str(int(h["id"]))
		var fr: Dictionary = en["fronde"]
		if fr.has(key):
			if int(fr[key]) > state.tick:
				continue
			fr.erase(key)
			Relics.touch(state)
			if Court.favor(h) <= r_int("fronde_fav") and (en["ult"] as Dictionary).is_empty() and int(en.get("ult_cd", 0)) <= state.tick:
				_ultimatum(state, eid, h, added)
			else:
				_chron(state, eid, "La %s de %s s'essouffle : on rentre les bannières, on garde les rancunes." % [
						String(Court.words(state, eid)["fronde"]).to_lower(), String(h["name"])], added)
			continue
		if Court.favor(h) > r_int("fronde_fav") or (en["levers"] as Dictionary).has(key):
			continue
		@warning_ignore("integer_division")
		var pct := r_int("fronde_pct") * (100 + int(Court.talent(state, eid).get("fronde_pct", 0))) / 100
		if _h(state, ["fronde", eid, int(h["id"]), state.tick]) % 100 >= pct:
			continue
		fr[key] = state.tick + r_int("fronde_days")
		Relics.touch(state)
		_chron(state, eid, "%s : %s %s se dresse contre le trône de %s. Ses fiefs grondent, ses gens d'armes refusent les ordres." % [
				String(Court.words(state, eid)["fronde"]), String(Court.words(state, eid)["the"]), String(h["name"]),
				state.get_empire(eid).display_name()], added, true)


static func _ultimatum(state: GameState, eid: int, h: Dictionary, added: Array[Dictionary]) -> void:
	var en := Court.entry(state, eid)
	en["ult"] = {"h": int(h["id"]), "until": state.tick + r_int("ultimatum_days")}
	var n := Court.fiefs_of(state, eid, int(h["id"])).size()
	var text := "%s, %s de %s %s, se présente au trône, l'épée au côté : « Rendez-nous justice, ou nous la prendrons. » Ses %d fief(s) suivront sa bannière si vous refusez." % [
			String(Court.head(h).get("name", "?")), String(Court.words(state, eid)["head"]), String(Court.words(state, eid)["the"]), String(h["name"]), n]
	Court.push_card(state, eid, "court_ultimatum", {"h": int(h["id"]), "ult_text": text,
			"concede_cost": GameData.format_amounts(rules()["concede_cost"])}, added)


## Étoile montante : un courtisan ambitieux et brillant se fait remarquer (une carte par membre).
static func _star(state: GameState, eid: int, en: Dictionary, added: Array[Dictionary]) -> void:
	if int(en.get("star", -1)) >= 0:
		return
	var seen: Array = en.get("star_seen", [])
	for h: Dictionary in Court.houses(state, eid):
		for m: Dictionary in h["members"]:
			if seen.has(int(m["id"])) or Court.trait_sum(m, "star") <= 0:
				continue
			var a := Court.apts(m)
			var sum := 0
			for k in a:
				sum += int(a[k])
			if sum < r_int("star_sum"):
				continue
			seen.append(int(m["id"]))
			en["star_seen"] = seen
			en["star"] = int(m["id"])
			Court.push_card(state, eid, "court_star", {"h": int(h["id"]), "m": int(m["id"]),
					"star_text": "%s %s, de %s, a %d ans et une ambition qui ne tient plus dans les couloirs. On le dit capable de tout, y compris de mieux faire que vous." % [
						String(m["name"]), String(h["name"]), String(Court.voc_def(String(h["voc"])).get("label", "")).to_lower(), Court.age(state, m)],
					"star_cost": GameData.format_amounts(rules()["star_cost"])}, added)
			return


# --- Missions et intrigues ---------------------------------------------------------------------

## gift (x = maison) | pacify (x = système) | imprison (x = membre) | secret (x = maison) | lever (x)
## | embassy (x = empire) | intercede (x = maison, y = maison qui intercède) | exile (x = membre)
## | raise (x = membre) | wed (x = maison) | fete | train (s = table | fetes | garde, x = 0-3).
static func check_act(state: GameState, eid: int, act: String, x: int, y: int, s: String) -> String:
	var en := Court.entry(state, eid)
	var e := state.get_empire(eid)
	match act:
		"gift":
			if Court.house(state, eid, x).is_empty():
				return "maison introuvable"
			if Court.holder(state, eid, "intendant").is_empty():
				return "il faut un %s" % Court.office_label(state, eid, "intendant")
			if not _cd_ok(en, "gift:%d" % x, state):
				return "un présent vient d'être fait"
			return "" if Economy.can_afford(e, rules()["gift_cost"]) else "pas assez d'énergie"
		"pacify":
			if Court.fief_house(state, x, eid).is_empty():
				return "ce système n'est pas un fief"
			if Court.holder(state, eid, "intendant").is_empty():
				return "il faut un %s" % Court.office_label(state, eid, "intendant")
			if not _cd_ok(en, "pacify", state):
				return "l'Intendant est déjà en tournée"
			return "" if Economy.can_afford(e, rules()["pacify_cost"]) else "pas assez d'influence"
		"imprison":
			var h := Court.house_of_member(state, eid, x)
			if h.is_empty():
				return "courtisan introuvable"
			if Court.holder(state, eid, "murmures").is_empty():
				return "il faut un %s" % Court.office_label(state, eid, "murmures")
			if not _cd_ok(en, "imprison", state):
				return "les geôles ne désemplissent pas"
			return "" if Economy.can_afford(e, rules()["imprison_cost"]) else "pas assez d'influence"
		"secret":
			if Court.house(state, eid, x).is_empty():
				return "maison introuvable"
			if Court.holder(state, eid, "murmures").is_empty():
				return "il faut un %s" % Court.office_label(state, eid, "murmures")
			if (en["levers"] as Dictionary).has(str(x)):
				return "nous tenons déjà un secret sur elle"
			if not _cd_ok(en, "secret", state):
				return "nos fouineurs reprennent leur souffle"
			return "" if Economy.can_afford(e, rules()["secret_cost"]) else "pas assez d'influence"
		"lever":
			return "" if (en["levers"] as Dictionary).has(str(x)) else "aucun secret sur elle"
		"embassy":
			var o := state.get_empire(x)
			if o == null or o.eliminated or o.id == eid or not e.contacts.has(x):
				return "empire inconnu"
			if Court.holder(state, eid, "heraut").is_empty():
				return "il faut un %s" % Court.office_label(state, eid, "heraut")
			if not _cd_ok(en, "embassy", state):
				return "le Héraut est encore en voyage"
			return "" if Economy.can_afford(e, rules()["embassy_cost"]) else "pas assez d'influence"
		"intercede":
			var t := Court.house(state, eid, x)
			var by := Court.house(state, eid, y)
			if t.is_empty() or by.is_empty() or x == y:
				return "maison introuvable"
			if Court.favor(by) < r_int("intercede_min"):
				return "%s n'est pas assez dévouée pour intercéder" % String(by["name"])
			if (by.get("rivals", []) as Array).has(x):
				return "on n'intercède pas pour sa rivale"
			if not _cd_ok(en, "intercede", state):
				return "une intercession vient d'avoir lieu"
			return "" if Economy.can_afford(e, rules()["intercede_cost"]) else "pas assez d'influence"
		"exile":
			return "" if not Court.house_of_member(state, eid, x).is_empty() else "courtisan introuvable"
		"raise":
			if Court.house_of_member(state, eid, x).is_empty():
				return "courtisan introuvable"
			if Heroes.ids_of(state, eid).size() >= Heroes.cap(state, eid):
				return "plus de place parmi les héros"
			return "" if Economy.can_afford(e, rules()["raise_cost"]) else "pas assez d'influence"
		"wed":
			var hw := Court.house(state, eid, x)
			if hw.is_empty():
				return "maison introuvable"
			if int(Court.talent(state, eid).get("no_marriage", 0)) > 0:
				return "votre peuple ne se marie pas"
			if int(hw.get("kin", 0)) == 1:
				return "elle est déjà liée au trône"
			if not _cd_ok(en, "wed", state):
				return "un mariage vient d'être célébré"
			return ""
		"fete":
			if not _cd_ok(en, "fete", state):
				return "la dernière fête n'est pas encore digérée"
			return "" if Economy.can_afford(e, fete_cost(state, eid)) else "pas assez de ressources"
		"train":
			if not (rules()["train"] as Dictionary).has(s) or x < 0 or x > 3:
				return "train inconnu"
			return ""
	return "ordre inconnu"


static func fete_cost(state: GameState, eid: int) -> Dictionary:
	var pct := 100 + int(Court.talent(state, eid).get("fete_pct", 0))
	var out := {}
	for r in rules()["fete_cost"]:
		@warning_ignore("integer_division")
		out[r] = int(rules()["fete_cost"][r]) * pct / 100
	return out


## Chance d'une mission du Maître des Murmures (emprisonner, chercher un secret).
static func chance(state: GameState, eid: int, kind: String) -> int:
	var apt := Court.office_apt(state, eid, "murmures")
	var n := r_int(kind + "_base") + apt * r_int(kind + "_per")
	if kind == "secret":
		n += int(Court.talent(state, eid).get("secret_pct", 0))
	return clampi(n, 5, 95)


static func act(state: GameState, eid: int, act_: String, x: int, y: int, s: String, added: Array[Dictionary]) -> void:
	var en := Court.entry(state, eid)
	var e := state.get_empire(eid)
	match act_:
		"gift":
			Economy.pay(e, rules()["gift_cost"])
			_set_cd(en, "gift:%d" % x, state, r_int("gift_cd"))
			var h := Court.house(state, eid, x)
			var mult := 2 if Court.trait_max(Court.head(h), "gift_x") >= 2 else 1
			Court.adjust(state, eid, x, r_int("gift_adj") * mult)
		"pacify":
			Economy.pay(e, rules()["pacify_cost"])
			_set_cd(en, "pacify", state, r_int("pacify_cd"))
			(en["pacified"] as Dictionary)[str(x)] = state.tick + r_int("pacify_days")
			Court.adjust(state, eid, int(Court.fief_house(state, x, eid)["id"]), r_int("pacify_adj"))
		"imprison":
			Economy.pay(e, rules()["imprison_cost"])
			_set_cd(en, "imprison", state, r_int("imprison_cd"))
			var h2 := Court.house_of_member(state, eid, x)
			var m := Court.member(state, eid, x)
			if _h(state, ["prison", eid, x, state.tick]) % 100 < chance(state, eid, "imprison"):
				Court.remove_member(state, eid, x)
				Court.adjust(state, eid, int(h2["id"]), r_int("imprison_adj"))
				_chron(state, eid, "%s %s est arrêté à l'aube et jeté dans une cellule sans fenêtre. %s %s jure de s'en souvenir." % [
						String(m["name"]), String(h2["name"]), Court.ucfirst(String(Court.words(state, eid)["the"])), String(h2["name"])], added)
			else:
				@warning_ignore("integer_division")
				Court.adjust(state, eid, int(h2["id"]), r_int("imprison_adj") / 2)
				_chron(state, eid, "%s %s a filé avant l'arrivée des gardes, prévenu par un cousin bavard. L'affront est fait, la cible court toujours." % [
						String(m["name"]), String(h2["name"])], added)
		"secret":
			Economy.pay(e, rules()["secret_cost"])
			_set_cd(en, "secret", state, r_int("secret_cd"))
			var h3 := Court.house(state, eid, x)
			if _h(state, ["secret", eid, x, state.tick]) % 100 < chance(state, eid, "secret"):
				(en["levers"] as Dictionary)[str(x)] = state.tick + r_int("lever_days")
				_chron(state, eid, "Le %s rapporte un secret sur %s %s : de quoi la tenir en laisse quelques années. Elle ne frondera pas." % [
						Court.office_label(state, eid, "murmures"), String(Court.words(state, eid)["the"]), String(h3["name"])], added)
			else:
				_chron(state, eid, "Les fouilles du %s chez %s ne donnent rien, sinon une collection de chaussettes dépareillées." % [
						Court.office_label(state, eid, "murmures"), String(h3["name"])], added)
		"lever":
			(en["levers"] as Dictionary).erase(str(x))
			Court.adjust(state, eid, x, r_int("lever_adj"))
			_chron(state, eid, "On rappelle discrètement un vieux secret à %s %s. Elle se découvre soudain un grand amour du trône." % [
					String(Court.words(state, eid)["the"]), String(Court.house(state, eid, x)["name"])], added)
		"embassy":
			Economy.pay(e, rules()["embassy_cost"])
			_set_cd(en, "embassy", state, r_int("embassy_cd"))
			Diplomacy.remember(state, x, eid, "court_embassy")
			_chron(state, eid, "Le %s mène une ambassade fastueuse chez %s : discours, cadeaux, et pas un seul incident protocolaire." % [
					Court.office_label(state, eid, "heraut"), state.get_empire(x).display_name()], added)
		"intercede":
			Economy.pay(e, rules()["intercede_cost"])
			_set_cd(en, "intercede", state, r_int("intercede_cd"))
			Court.adjust(state, eid, x, r_int("intercede_adj"))
			_chron(state, eid, "%s intercède en faveur de %s auprès du trône. Les vieilles querelles s'apaisent un peu." % [
					String(Court.house(state, eid, y)["name"]), String(Court.house(state, eid, x)["name"])], added)
		"exile":
			var h4 := Court.house_of_member(state, eid, x)
			var m4 := Court.member(state, eid, x)
			Court.remove_member(state, eid, x)
			Court.adjust(state, eid, int(h4["id"]), r_int("exile_adj"))
			_chron(state, eid, "%s %s est banni de la cour. On lui accorde une navette, un sac et trois minutes." % [String(m4["name"]), String(h4["name"])], added)
		"raise":
			Economy.pay(e, rules()["raise_cost"])
			raise_hero(state, eid, x, added)
		"wed":
			for h5: Dictionary in Court.houses(state, eid):
				h5["kin"] = 0
			var hw := Court.house(state, eid, x)
			hw["kin"] = 1
			_set_cd(en, "wed", state, 720)
			Court.adjust(state, eid, x, r_int("marriage_adj") + int(Court.talent(state, eid).get("marriage_bonus", 0)), false)
			Court.adjust_all(state, eid, r_int("marriage_others"), x)
			_chron(state, eid, "Grand mariage à la cour de %s : le trône s'allie à %s %s. Les autres familles applaudissent du bout des gants." % [
					e.display_name(), String(Court.words(state, eid)["the"]), String(hw["name"])], added)
		"fete":
			Economy.pay(e, fete_cost(state, eid))
			_set_cd(en, "fete", state, r_int("fete_cd"))
			en["faste"] = mini(r_int("faste_max"), int(en["faste"]) + r_int("fete_faste"))
			en["fete_until"] = state.tick + r_int("fete_culture_days")
			Court.adjust_all(state, eid, r_int("fete_adj"))
			Relics.touch(state)
			_chron(state, eid, "Grande fête à la cour de %s : bals en apesanteur, feux d'artifice sur la lune, et un buffet dont on parlera trois générations." % e.display_name(), added, true)
		"train":
			(en["train"] as Dictionary)[s] = x
			Relics.touch(state)


## Un courtisan devient héros (il garde sa maison : sa loyauté suivra la faveur).
static func raise_hero(state: GameState, eid: int, mid: int, added: Array[Dictionary]) -> int:
	var h := Court.house_of_member(state, eid, mid)
	var m := Court.member(state, eid, mid)
	if m.is_empty():
		return -1
	var a := Court.apts(m)
	var best := "gestion"
	for k in Court.APTS:
		if int(a[k]) > int(a[best]):
			best = k
	var pics := Heroes.portraits_for(Heroes._archetype(state, eid))
	var cand := {"name": "%s %s" % [String(m["name"]), String(h["name"])], "portrait": pics[_h(state, ["hp", eid, mid]) % pics.size()] if not pics.is_empty() else "",
			"cls": String(Rulers.data()["aptitudes"][best]["cls"]), "age": Court.age(state, m), "traits": [], "amb": ""}
	var hid := Heroes.recruit(state, eid, cand)
	state.heroes[hid]["house"] = int(h["id"])
	state.heroes[hid]["lvl"] = maxi(int(state.heroes[hid]["lvl"]), 1 + int(a[best]) / 2)
	Court.remove_member(state, eid, mid)
	Court.adjust(state, eid, int(h["id"]), r_int("raise_adj"))
	_chron(state, eid, "%s quitte les salons de %s pour servir l'empire : un héros de plus, et une famille fière." % [String(cand["name"]), String(h["name"])], added)
	return hid


# --- Cartes ------------------------------------------------------------------------------------

static func fx_lines(state: GameState, eid: int, _item: Dictionary, fx: Dictionary, n: Dictionary) -> Array[String]:
	var out: Array[String] = []
	match String(fx.get("act", "")):
		"drop":
			var offer: Array = n.get("offer", [])
			var i := int(fx.get("i", 0))
			if i < offer.size():
				var h := Court.house(state, eid, int(offer[i]))
				out.append("%s retourne sur ses terres ; les autres reçoivent les fiefs" % String(h.get("name", "?")))
		"concede":
			out.append("Coût : %s ; faveur %+d" % [GameData.format_amounts(rules()["concede_cost"]), r_int("concede_adj")])
		"give_fief":
			out.append("Un fief pris à la maison la mieux dotée ; faveur %+d" % r_int("grant_adj"))
		"refuse":
			var fs := Court.fiefs_of(state, eid, int(n.get("h", -1))).size()
			out.append("Guerre civile : %d fief(s) font sécession" % fs if fs >= r_int("civil_war_min_systems") else "Sans fiefs, la maison est brisée")
		"star_raise":
			out.append("Il devient héros (sa maison faveur %+d)" % r_int("raise_adj"))
		"star_buy":
			out.append("Coût : %s ; il devient loyal, sa maison faveur %+d" % [GameData.format_amounts(rules()["star_cost"]), r_int("star_buy_op")])
		"star_away":
			out.append("Il quitte la cour ; sa maison faveur %d" % r_int("star_away_adj"))
		"integrate":
			out.append("Elle rejoint nos maisons (faveur de départ %d)" % r_int("integrate_adj"))
		"humiliate":
			out.append("Nos maisons faveur +5 ; le vaincu s'en souviendra")
		"flee":
			out.append("Elle rejoint ce qui reste de son empire")
	return out


static func fx_problem(state: GameState, eid: int, _item: Dictionary, fx: Dictionary, n: Dictionary) -> String:
	var e := state.get_empire(eid)
	match String(fx.get("act", "")):
		"drop":
			var offer: Array = n.get("offer", [])
			var i := int(fx.get("i", 0))
			if i >= offer.size() or Court.house(state, eid, int(offer[i])).is_empty():
				return "indisponible"
		"concede":
			if not Economy.can_afford(e, rules()["concede_cost"]):
				return "pas assez d'influence"
		"give_fief":
			if Court.house(state, eid, int(n.get("h", -1))).is_empty() or _richest(state, eid, int(n.get("h", -1))) < 0:
				return "aucun fief à donner"
		"star_buy":
			if not Economy.can_afford(e, rules()["star_cost"]):
				return "pas assez d'influence"
		"star_raise":
			if Heroes.ids_of(state, eid).size() >= Heroes.cap(state, eid):
				return "plus de place parmi les héros"
			if Court.member(state, eid, int(n.get("m", -1))).is_empty():
				return "il n'est plus là"
		"integrate":
			if Court.house(state, int(n.get("src", -1)), int(n.get("src_h", -1))).is_empty():
				return "la maison a disparu"
		"humiliate", "flee":
			pass
	return ""


static func apply_fx(state: GameState, eid: int, _item: Dictionary, fx: Dictionary, n: Dictionary, added: Array[Dictionary]) -> void:
	var en := Court.entry(state, eid)
	var e := state.get_empire(eid)
	var hid := int(n.get("h", -1))
	match String(fx.get("act", "")):
		"drop":
			var offer: Array = n.get("offer", [])
			var i := int(fx.get("i", 0))
			if i < offer.size():
				var h := Court.house(state, eid, int(offer[i]))
				var nm := String(h.get("name", "?"))
				Court.remove_house(state, eid, int(offer[i]))
				_chron(state, eid, "%s %s est renvoyée sur ses terres ; les autres familles se partagent les faveurs du trône." % [
						Court.ucfirst(String(Court.words(state, eid)["the"])), nm], added)
			en["sel"] = 1
			en["offer"] = []
			Court.reconcile(state, eid)
			Court.refresh(state, eid)
		"concede":
			Economy.pay(e, rules()["concede_cost"])
			Court.adjust(state, eid, hid, r_int("concede_adj"))
			_end_ult(state, eid)
		"give_fief":
			var src := _richest(state, eid, hid)
			if src >= 0:
				var sid: int = Court.fiefs_of(state, eid, src)[0]
				Court.adjust(state, eid, src, r_int("revoke_fief_adj") / 2, false)
				Court.set_fief(state, eid, sid, hid)
			Court.adjust(state, eid, hid, r_int("grant_adj"))
			_end_ult(state, eid)
		"refuse":
			_end_ult(state, eid)
			civil_war(state, eid, hid, added)
		"star_raise":
			en["star"] = -1
			raise_hero(state, eid, int(n.get("m", -1)), added)
		"star_buy":
			en["star"] = -1
			Economy.pay(e, rules()["star_cost"])
			var m := Court.member(state, eid, int(n.get("m", -1)))
			if not m.is_empty():
				(m["traits"] as Array).erase("ambitieux")
				if not (m["traits"] as Array).has("loyal"):
					(m["traits"] as Array).append("loyal")
			Court.adjust(state, eid, hid, r_int("star_buy_op"))
		"star_away":
			en["star"] = -1
			Court.remove_member(state, eid, int(n.get("m", -1)))
			Court.adjust(state, eid, hid, r_int("star_away_adj"))
		"integrate":
			var p := int(n.get("src", -1))
			var src_h := Court.house(state, p, int(n.get("src_h", -1)))
			if src_h.is_empty():
				return
			var nh := Court.add_house(state, eid, String(src_h["voc"]), p)
			nh["name"] = String(src_h["name"])
			nh["members"] = (src_h["members"] as Array).duplicate(true)
			nh["head"] = int(src_h["head"])
			nh["adj"] = r_int("integrate_adj")
			Court.remove_house(state, p, int(src_h["id"]))
			Court.reconcile(state, eid)
			Court.refresh(state, eid)
			_chron(state, eid, "%s %s, venue de %s, plie le genou devant %s. On lui trouve une place, loin des fenêtres." % [
					Court.ucfirst(String(Court.words(state, eid)["the"])), String(nh["name"]), state.get_empire(p).display_name() if state.get_empire(p) else "?",
					e.display_name()], added, true)
		"humiliate":
			var p2 := int(n.get("src", -1))
			Court.adjust_all(state, eid, 5)
			Court.remove_house(state, p2, int(n.get("src_h", -1)))
			if state.get_empire(p2) != null and not state.get_empire(p2).eliminated:
				Diplomacy.remember(state, p2, eid, "court_humiliated")
			_chron(state, eid, "La famille vaincue de %s est promenée dans les rues de la capitale. La foule rit ; l'histoire, moins." % String(n.get("conq_house", "?")), added, true)
		"flee":
			var p3 := int(n.get("src", -1))
			if r_int("flee_grief") > 0 or bool(rules().get("flee_grief", false)):
				Court.adjust(state, p3, int(n.get("src_h", -1)), 10)


static func _end_ult(state: GameState, eid: int) -> void:
	var en := Court.entry(state, eid)
	en["ult"] = {}
	en["ult_cd"] = state.tick + r_int("ultimatum_cd")


## La maison la mieux dotée en fiefs, hors except (-1 si aucune n'en a).
static func _richest(state: GameState, eid: int, except: int) -> int:
	var best := -1
	var bn := 0
	for h: Dictionary in Court.houses(state, eid):
		if int(h["id"]) == except:
			continue
		var n := Court.fiefs_of(state, eid, int(h["id"])).size()
		if n > bn:
			bn = n
			best = int(h["id"])
	return best


## Ultimatum refusé : la maison fait sécession avec ses fiefs (guerre civile), ou se brise sans fiefs.
static func civil_war(state: GameState, eid: int, hid: int, added: Array[Dictionary]) -> int:
	var h := Court.house(state, eid, hid)
	if h.is_empty():
		return -1
	var e := state.get_empire(eid)
	var sids: Array = []
	for sid in Court.fiefs_of(state, eid, hid):
		if state.system_owner(sid) == eid:
			sids.append(sid)
	var total := Stability.systems_of(state, eid).size()
	var name := String(h["name"])
	if sids.size() < r_int("civil_war_min_systems") or sids.size() >= total:
		Court.remove_house(state, eid, hid)
		Court.adjust_all(state, eid, -5)
		_chron(state, eid, "%s %s, sans fiefs pour la suivre, est brisée : ses membres sont dispersés, ses titres effacés des registres." % [
				Court.ucfirst(String(Court.words(state, eid)["the"])), name], added, true)
		return -1
	var r := {}
	if not state.rulers.is_empty():
		var hd := Court.head(h)
		r = Rulers.make_ruler(state, eid, ["fronde", eid, hid, state.tick], "usurpateur")
		if not hd.is_empty():
			r["name"] = String(hd["name"])
			r["g"] = String(hd.get("g", r["g"]))
			r["born"] = int(hd["born"])
		r["house"] = name
	Court.remove_house(state, eid, hid)
	var nid := RulersDynasty.spawn_empire(state, eid, sids, r, "fronde", added)
	if nid >= 0:
		_chron(state, eid, "Guerre civile ! %s %s refuse l'autorité de %s et entraîne %d système(s) dans la sécession : ainsi naît %s." % [
				Court.ucfirst(String(Court.words(state, eid)["the"])), name, e.display_name(), sids.size(), state.get_empire(nid).display_name()], added, true)
	return nid


static func ai_value(state: GameState, eid: int, _item: Dictionary, fx: Dictionary, n: Dictionary) -> int:
	match String(fx.get("act", "")):
		"drop":
			# Renvoyer la vocation la moins utile : celle dont le courant est le plus loin du pouvoir.
			var offer: Array = n.get("offer", [])
			var i := int(fx.get("i", 0))
			if i < offer.size():
				var h := Court.house(state, eid, int(offer[i]))
				return 10 + _h(state, ["drop", eid, int(offer[i])]) % 20 - (10 if String(Court.voc_def(String(h.get("voc", ""))).get("apt", "")) == "guerre" else 0)
		"concede":
			return 40
		"give_fief":
			return 30
		"refuse":
			var fs := Court.fiefs_of(state, eid, int(n.get("h", -1))).size()
			return 60 if fs == 0 else -40 - fs * 10
		"star_raise":
			return 50
		"star_buy":
			return 30
		"star_away":
			return 0
		"integrate":
			return 40
		"humiliate":
			return 15
		"flee":
			return 10
	return 0


# --- Espionnage (opérations marquées "court") --------------------------------------------------

## La maison la plus fâchée de b ({} s'il n'a pas de cour).
static func _sorest(state: GameState, b: int) -> Dictionary:
	var best: Dictionary = {}
	for h: Dictionary in Court.houses(state, b):
		if best.is_empty() or Court.favor(h) < Court.favor(best):
			best = h
	return best


static func spy_check(state: GameState, a: int, b: int, op_id: String) -> String:
	if not Court.applies(state, b):
		return "il n'a pas de cour"
	match op_id:
		"financer_fronde":
			if Court.peaceful(state):
				return "les maisons sont apaisées dans cette partie"
		"debaucher_maison":
			if not Court.applies(state, a):
				return "nous n'avons pas de cour pour l'accueillir"
			var h := _sorest(state, b)
			if h.is_empty() or Court.favor(h) > -20:
				return "aucune de ses maisons n'est assez fâchée"
	return ""


static func spy_apply(state: GameState, a: int, b: int, o: Dictionary) -> String:
	var h := _sorest(state, b)
	if h.is_empty():
		return "rien ne se passe."
	var nm := String(h["name"])
	match String(o["id"]):
		"attiser_maison":
			Court.adjust(state, b, int(h["id"]), -25)
			return "des lettres anonymes attisent la colère de %s contre son trône (faveur %d)." % [nm, Court.favor(Court.house(state, b, int(h["id"])))]
		"financer_fronde":
			var en := Court.entry(state, b)
			if Court.favor(h) <= -20:
				(en["fronde"] as Dictionary)[str(int(h["id"]))] = state.tick + r_int("fronde_days")
				Relics.touch(state)
				return "notre or arme %s : elle entre en %s." % [nm, String(Court.words(state, b)["fronde"]).to_lower()]
			Court.adjust(state, b, int(h["id"]), -15)
			return "notre or achète des rancunes chez %s ; pas encore une révolte." % nm
		"debaucher_maison":
			var nh := Court.add_house(state, a, String(h["voc"]), b)
			nh["name"] = nm
			nh["members"] = (h["members"] as Array).duplicate(true)
			nh["head"] = int(h["head"])
			Court.remove_house(state, b, int(h["id"]))
			Court.reconcile(state, a)
			Court.refresh(state, a)
			return "%s quitte sa cour avec armes et bagages et vient se mettre à notre service." % nm
	return "rien ne se passe."


static func spy_exposed(state: GameState, a: int, b: int, op_id: String, ok: bool) -> void:
	if ok and op_id == "debaucher_maison":
		Diplomacy.remember(state, b, a, "court_poached")
