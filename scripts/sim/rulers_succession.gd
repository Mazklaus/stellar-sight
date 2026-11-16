class_name RulersSuccession
extends RefCounted
## Succession selon la couche gouvernement (étude « Souverain et dynastie », bloc B, prop. 9-16).
## - Féodalité : la dynastie (loi de succession, héritiers, régence, extinction : RulersDynasty).
## - Théocratie : « Siège vacant » 60 jours, puis le Conclave élit un Orateur ou un héros de la foi ;
##   plus la ferveur est haute, plus l'élu est légitime.
## - République : le Premier Archonte est élu pour 1080 jours, deux mandats au plus ; une mort en cours
##   de mandat avance l'élection ; son archétype suit le courant en tête.
## - Syndicat : le Directeur général, nommé parmi les héros d'ambition Fortune ; motion de défiance si le
##   revenu d'énergie baisse deux trimestres de suite (parachute doré).
## - Horde : l'Épreuve du Khan, 90 jours d'interrègne, le meilleur Stratège l'emporte, un vaincu peut
##   partir avec une flotte.
## - Ruche : la Reine-mère ne meurt que si la capitale tombe ; un an de « Ruche sans reine ».
## - Conscience : le Nœud premier ne meurt pas ; tous les 20 ans, une itération change son archétype.

static func _h(state: GameState, parts: Array) -> int:
	return absi(hash([state.seed_value, "succession"] + parts))


## Le trône vient de se libérer (mort, abdication, défiance, fin de mandat).
static func on_vacancy(state: GameState, eid: int, how: String, added: Array[Dictionary]) -> void:
	var en := Rulers.entry(state, eid)
	var e := state.get_empire(eid)
	if en.is_empty() or e == null or e.eliminated:
		return
	var k := Rulers.kind(state, eid)
	var days: Dictionary = Rulers.rules()["vacancy_days"]
	match k:
		"dynastie":
			RulersDynasty.heir_succession(state, eid, how, added)
		"conclave", "epreuve", "reine":
			en["vacant"] = state.tick + int(days.get(k, 60))
			en["vacant_kind"] = k
			var txt := {"conclave": "Siège vacant chez %s : le Conclave se réunira dans %d jours. On ferme les portes, on attend la fumée.",
					"epreuve": "Interrègne chez %s : les prétendants s'affrontent pendant %d jours. Le plus coriace prendra les rênes.",
					"reine": "%s est une ruche sans reine : la production chute, et une couvée royale n'éclora pas avant %d jours."}
			added.append(state.add_chronicle(String(txt[k]) % [e.display_name(), int(days.get(k, 60))], Espionage.public_to(state, [eid])))
		"election":
			Rulers.crown(state, eid, elect(state, eid, ["elu", eid, state.tick]), added)
			added.append(state.add_chronicle("Élection anticipée chez %s : %s prend la tête de la République." % [e.display_name(), Rulers.full_name(state, eid)],
					Espionage.public_to(state, [eid])))
		"conseil":
			Rulers.crown(state, eid, director(state, eid), added)
			added.append(state.add_chronicle("Le conseil des actionnaires de %s nomme %s. Le cours remonte de trois points à l'annonce." % [
					e.display_name(), Rulers.full_name(state, eid)], Espionage.public_to(state, [eid])))
		_:
			Rulers.crown(state, eid, Rulers.make_ruler(state, eid, ["iter", eid, state.tick], "iteration"), added)


## Fin d'un interrègne (Conclave, Épreuve, couvée royale).
static func resolve(state: GameState, eid: int, added: Array[Dictionary]) -> void:
	var en := Rulers.entry(state, eid)
	var e := state.get_empire(eid)
	var vk := String(en.get("vacant_kind", ""))
	en["vacant"] = 0
	match vk:
		"conclave":
			var h := _best_hero(state, eid, "orateur")
			var r: Dictionary
			if not h.is_empty() and Heroes.ids_of(state, eid).size() >= 2:
				r = Rulers.from_hero(state, eid, h, "conclave", "zelote")
			else:
				r = Rulers.make_ruler(state, eid, ["conclave", eid, state.tick], "conclave", -1, "zelote")
			Rulers.crown(state, eid, r, added)
			if FactionTraits.has_fervor(e.faction()):
				@warning_ignore("integer_division")
				Rulers.adjust(state, eid, e.fervor / 5)
			added.append(state.add_chronicle("Fumée blanche chez %s : le Conclave élit %s." % [e.display_name(), Rulers.full_name(state, eid)],
					Espionage.public_to(state, [eid])))
		"epreuve":
			_trial(state, eid, added)
		"reine":
			Rulers.crown(state, eid, Rulers.make_ruler(state, eid, ["reine", eid, state.tick], "reine", 1), added)
			Relics.touch(state)
			added.append(state.add_chronicle("Une couvée royale éclot chez %s : %s prend la place de la défunte. La ruche se remet à bourdonner." % [
					e.display_name(), Rulers.full_name(state, eid)], Espionage.public_to(state, [eid])))
		_:
			Rulers.crown(state, eid, Rulers.make_ruler(state, eid, ["vac", eid, state.tick], "elu"), added)


## L'Épreuve du Khan : les deux ou trois Stratèges les plus aguerris s'affrontent.
static func _trial(state: GameState, eid: int, added: Array[Dictionary]) -> void:
	var e := state.get_empire(eid)
	var cands: Array[Dictionary] = []
	for id in Heroes.ids_of(state, eid):
		var h: Dictionary = state.heroes[id]
		if Heroes.is_prisoner(h) or int(h.get("heir", 0)) > 0:
			continue
		if String(h["cls"]) == "stratege":
			cands.append(h)
	cands.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["lvl"]) * 1000 + int(a["xp"]) > int(b["lvl"]) * 1000 + int(b["xp"]))
	cands = cands.slice(0, 3)
	var r: Dictionary
	var loser := {}
	if cands.size() >= 2 or (cands.size() == 1 and Heroes.ids_of(state, eid).size() >= 2):
		var total := 0
		for h in cands:
			total += int(h["lvl"]) + 1
		var roll := _h(state, ["epreuve", eid, state.tick]) % maxi(1, total)
		var win: Dictionary = cands[0]
		for h in cands:
			roll -= int(h["lvl"]) + 1
			if roll < 0:
				win = h
				break
		for h in cands:
			if h != win:
				loser = h
				break
		r = Rulers.from_hero(state, eid, win, "epreuve", "conquerant")
	else:
		r = Rulers.make_ruler(state, eid, ["epreuve", eid, state.tick], "epreuve", -1, "conquerant")
		r["apt"]["guerre"] = mini(int(Rulers.data().get("apt_max", 6)), int(r["apt"]["guerre"]) + 2)
	Rulers.crown(state, eid, r, added)
	var txt := "L'Épreuve est jugée chez %s : %s prend les rênes." % [e.display_name(), Rulers.full_name(state, eid)]
	# Un vaincu peut partir avec une flotte.
	if not loser.is_empty() and _h(state, ["vaincu", eid, state.tick]) % 2 == 0:
		var fl := _smallest_armed(state, eid)
		state.heroes.erase(int(loser["id"]))
		Relics.on_hero_gone(state, int(loser["id"]))
		if fl != null:
			fl.owner = GameState.NPC_ID
			fl.fleet_name = "Dissidents de %s" % String(loser["name"]).split(" ")[0]
			txt += " %s refuse le verdict et part avec %s." % [loser["name"], fl.fleet_name]
		else:
			txt += " %s refuse le verdict et quitte la horde." % loser["name"]
		state.rebuild_ownership()
	added.append(state.add_chronicle(txt, Espionage.public_to(state, [eid])))


static func _smallest_armed(state: GameState, eid: int) -> Fleet:
	var armed: Array[Fleet] = []
	for fid in state.sorted_fleet_ids():
		var f: Fleet = state.fleets[fid]
		if f.owner == eid and Combat.is_armed(f) and not Rulers.commands(state, eid, f.id) and not FactionTraits.is_city_fleet(f):
			armed.append(f)
	if armed.size() < 2:
		return null
	var best: Fleet = armed[0]
	for f in armed:
		if f.ships.size() < best.ships.size():
			best = f
	return best


static func _best_hero(state: GameState, eid: int, cls: String, amb := "") -> Dictionary:
	var best := {}
	var bv := -1
	for id in Heroes.ids_of(state, eid):
		var h: Dictionary = state.heroes[id]
		if Heroes.is_prisoner(h) or int(h.get("heir", 0)) > 0 or int(h.get("lender", -1)) >= 0 or int(h.get("blood", 0)) > 0:
			continue
		var v := int(h["lvl"]) * 10
		if String(h["cls"]) == cls:
			v += 25
		if amb != "" and String(h.get("amb", "")) == amb:
			v += 40
		if v > bv:
			bv = v
			best = h
	return best


## Un Premier Archonte : l'archétype suit le courant en tête de l'opinion.
static func elect(state: GameState, eid: int, salt: Array) -> Dictionary:
	var cur := ""
	if Politics.applies(state, eid):
		cur = Politics.current_id(Politics.lead(state, eid))
	var arch := Rulers._pick_arch(state, eid, salt, cur)
	return Rulers.make_ruler(state, eid, salt, "elu", -1, arch)


## Un Directeur général : un héros d'ambition Fortune s'il y en a, sinon un financier.
static func director(state: GameState, eid: int) -> Dictionary:
	var h := _best_hero(state, eid, "intendant", "fortune")
	if not h.is_empty() and String(h.get("amb", "")) == "fortune" and Heroes.ids_of(state, eid).size() >= 2:
		return Rulers.from_hero(state, eid, h, "conseil", "marchand")
	return Rulers.make_ruler(state, eid, ["dg", eid, state.tick], "conseil", -1, "marchand")


## Chaque mois : mandats, défiance, itérations.
static func monthly(state: GameState, eid: int, added: Array[Dictionary]) -> void:
	if not Rulers.mortal(state):
		return
	var en := Rulers.entry(state, eid)
	var e := state.get_empire(eid)
	var rl := Rulers.rules()
	match Rulers.kind(state, eid):
		"election":
			if state.tick < int(en.get("term_end", 0)):
				return
			if int(en.get("terms", 1)) < int(rl["republic_max_terms"]) and Rulers.legitimacy(state, eid) >= 50:
				en["terms"] = int(en["terms"]) + 1
				en["term_end"] = state.tick + int(rl["republic_term_days"])
				added.append(state.add_chronicle("%s est réélu à la tête de %s. Les affiches de campagne resservent." % [
						Rulers.full_name(state, eid), e.display_name()], Espionage.public_to(state, [eid])))
				return
			Rulers.die(state, eid, "achève son mandat et rend les sceaux", added, "term")
		"conseil":
			if posmod(state.tick, 90) >= int(rl["check_days"]):
				return
			var net := int(Economy.empire_income(state, eid)["net"].get("energy", 0))
			var inc: Array = en.get("inc", [])
			inc.append(net)
			while inc.size() > int(rl["noconfidence_quarters"]) + 1:
				inc.pop_front()
			en["inc"] = inc
			if inc.size() < int(rl["noconfidence_quarters"]) + 1 or Rulers.reign_years(state, en["r"]) < 1:
				return
			for i in range(1, inc.size()):
				if int(inc[i]) >= int(inc[i - 1]):
					return
			var para: Dictionary = rl["parachute"]
			for res in para:
				e.resources[res] = maxi(0, int(e.resources.get(res, 0)) - int(para[res]))
			Rulers.die(state, eid, "est renversé par une motion de défiance et part avec un parachute doré (%s)" % GameData.format_amounts(para), added, "deposed")
		"iteration":
			if state.tick < int(en.get("iter_next", 0)) or int(en.get("iter_next", 0)) <= 0:
				return
			en["iter_next"] = state.tick + int(rl["iteration_years"]) * Rulers.DAYS_PER_YEAR
			var r: Dictionary = en["r"]
			var ids: Array = Rulers.arch_ids().duplicate()
			ids.erase(String(r["arch"]))
			ids.sort_custom(func(a: Variant, b: Variant) -> bool:
				return _h(state, ["it", eid, state.tick, a]) < _h(state, ["it", eid, state.tick, b]))
			var ev := state.next_event_id
			Events.push(state, eid, "ruler_iteration", {}, added)
			Rulers._note(state, eid, ev, {"arch": ids.slice(0, 3)})
