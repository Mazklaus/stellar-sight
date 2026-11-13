class_name Laws
extends RefCounted
## Lois (étude « Politique des peuples », lot 2 : propositions 6 à 8, 10 et 11).
## Chaque courant a une loi de pouvoir, gratuite, imposée tant qu'il est en tête du gouvernement, et
## 4 lois de niveau 1 à 4 qu'on adopte tant qu'il est au pouvoir et que son niveau le permet (un
## niveau par mandat, 4 au plus, gardé dans l'opposition). Elles tombent quand il perd le pouvoir.
## Six lois indépendantes, gratuites, ont toujours un défaut ; la ruche n'a qu'elles (ses Instincts).
## Effets au format des technologies : ils passent par Research.effects (sauf la stabilité, qui a sa
## propre ligne dans l'Ordre intérieur). Données : data/politics.json "laws", "independent_laws",
## "law_rules", "actions", "heroes".
##
## Dans l'entrée d'empire de Politics : "laws" (lois adoptées, dans l'ordre), "xp" (niveau des six
## courants), "act" (action électorale du cycle, "" aucune), "cm" (mois au pouvoir, conscience).

static var _index := {}


static func data() -> Dictionary:
	return Politics.data()


static func rules() -> Dictionary:
	return data()["law_rules"]


## L'empire a-t-il des lois ? (option de partie, pas de PNJ ; la ruche aussi, avec ses Instincts.)
static func applies(state: GameState, empire_id: int) -> bool:
	if not state.politics_on:
		return false
	var e := state.get_empire(empire_id)
	return e != null and not e.is_npc() and not e.eliminated


## Définition d'une loi, avec "current" (indice du courant, -1 indépendante) et "power" (loi de pouvoir).
static func law_def(id: String) -> Dictionary:
	if _index.is_empty():
		var lw: Dictionary = data()["laws"]
		for cid in lw:
			var i := Politics.index_of(String(cid))
			var pw: Dictionary = (lw[cid]["power"] as Dictionary).duplicate()
			pw["current"] = i
			pw["power"] = true
			_index[String(pw["id"])] = pw
			for l: Dictionary in lw[cid]["laws"]:
				var d := l.duplicate()
				d["current"] = i
				d["power"] = false
				_index[String(d["id"])] = d
		for l: Dictionary in data()["independent_laws"]:
			var d := l.duplicate()
			d["current"] = -1
			d["power"] = false
			_index[String(d["id"])] = d
	return _index.get(id, {})


static func current_laws(i: int) -> Array:
	return (data()["laws"] as Dictionary).get(Politics.current_id(i), {}).get("laws", [])


static func power_law(i: int) -> Dictionary:
	return (data()["laws"] as Dictionary).get(Politics.current_id(i), {}).get("power", {})


static func independent() -> Array:
	return data()["independent_laws"]


# --- Lectures ----------------------------------------------------------------------------------

static func enacted(state: GameState, empire_id: int) -> Array:
	return (Politics.emp(state, empire_id).get("laws", []) as Array).duplicate()


static func is_enacted(state: GameState, empire_id: int, id: String) -> bool:
	return (Politics.emp(state, empire_id).get("laws", []) as Array).has(id)


## Niveau d'un courant (expérience politique, 0 à 4).
static func level(state: GameState, empire_id: int, i: int) -> int:
	var xp: Array = Politics.emp(state, empire_id).get("xp", [])
	return int(xp[i]) if i >= 0 and i < xp.size() else 0


## Loi de pouvoir en vigueur (celle du courant en tête), "" sans courant.
static func power_active(state: GameState, empire_id: int) -> String:
	if not Politics.applies(state, empire_id) or Grievances.interregnum(state, empire_id):
		return ""
	var l := Politics.lead(state, empire_id)
	return String(power_law(l).get("id", "")) if l >= 0 else ""


## Emplacements de lois : selon le gouvernement, +1 aux ères III et V.
static func slots(state: GameState, empire_id: int) -> int:
	var r := rules()
	var g := Politics.government_of(state, empire_id)
	var n := int((r["slots"] as Dictionary).get(g, (r["slots"] as Dictionary).get("republique", 3)))
	var era := Research.current_era(state, empire_id)
	for e in r["slot_eras"]:
		if era >= int(e):
			n += 1
	return n


static func used(state: GameState, empire_id: int) -> int:
	return (Politics.emp(state, empire_id).get("laws", []) as Array).size()


static func empire_pop(state: GameState, empire_id: int) -> int:
	var n := 0
	for pid in state.colonies:
		var c: Colony = state.colonies[pid]
		if c.owner == empire_id and c.is_colony():
			n += c.population
	return n


static func adopt_cost(id: String) -> Dictionary:
	var lv := int(law_def(id).get("level", 0))
	if lv <= 0:
		return {}
	return {"influence": int(rules()["adopt_cost"]) * lv}


## Entretien mensuel d'une loi en influence : niveau × (1 + population de l'empire / diviseur).
static func law_upkeep(state: GameState, empire_id: int, id: String, pop := -1) -> int:
	var lv := int(law_def(id).get("level", 0))
	if lv <= 0:
		return 0
	if pop < 0:
		pop = empire_pop(state, empire_id)
	@warning_ignore("integer_division")
	return lv * (1 + pop / maxi(1, int(rules()["upkeep_pop_div"])))


static func upkeep(state: GameState, empire_id: int) -> int:
	if not state.politics_on:
		return 0
	var ls: Array = Politics.emp(state, empire_id).get("laws", [])
	if ls.is_empty():
		return 0
	var pop := empire_pop(state, empire_id)
	var n := 0
	for id in ls:
		n += law_upkeep(state, empire_id, String(id), pop)
	return n


## Effets des lois en vigueur (adoptées et loi de pouvoir), au format des technologies.
static func effects(state: GameState, empire_id: int) -> Dictionary:
	var out := {}
	if not state.politics_on:
		return out
	var ids: Array = (Politics.emp(state, empire_id).get("laws", []) as Array).duplicate()
	var pw := power_active(state, empire_id)
	if pw != "":
		ids.append(pw)
	for id in ids:
		Research._merge(out, law_def(String(id)).get("fx", {}))
	return out


## Les mêmes, sans la stabilité (Research.effects : elle a sa propre ligne, voir stability_parts).
static func research_effects(state: GameState, empire_id: int) -> Dictionary:
	var fx := effects(state, empire_id)
	fx.erase("stability")
	fx.erase("stability_pop_div")
	return fx


static func no_war_weariness(state: GameState, empire_id: int) -> bool:
	return state.politics_on and Research.fx_int(state, empire_id, "no_war_weariness") > 0


## Revenu des traités (loi « Dividende de la paix ») : par pacte et accord commercial en vigueur.
static func treaty_income(state: GameState, empire_id: int) -> Dictionary:
	var out := {}
	if not state.politics_on:
		return out
	var per: Dictionary = Research.effects(state, empire_id).get("per_treaty", {})
	if per.is_empty():
		return out
	var e := state.get_empire(empire_id)
	var n := 0
	for o in e.contacts:
		var oe := state.get_empire(int(o))
		if oe == null or oe.eliminated:
			continue
		if Diplomacy.pact(state, empire_id, int(o)) != Diplomacy.COLD:
			n += 1
		if Diplomacy.has_trade(state, empire_id, int(o)):
			n += 1
	for r in per:
		out[r] = int(per[r]) * n
	return out


## Lignes de stabilité des lois pour un système : [[libellé, valeur], …] (voir Stability.parts).
static func stability_parts(state: GameState, sid: int, owner: int) -> Array:
	var out := []
	if not applies(state, owner):
		return out
	var fx := effects(state, owner)
	var v := int(fx.get("stability", 0))
	if v != 0:
		out.append(["Lois en vigueur", v])
	var div := int(fx.get("stability_pop_div", 0))
	if div > 0:
		@warning_ignore("integer_division")
		var p := Stability.system_pop(state, sid, owner) / div
		if p > 0:
			out.append(["Examens forcés (%d habitants)" % Stability.system_pop(state, sid, owner), -p])
	var en := Politics.emp(state, owner)
	if String(en.get("act", "")) == "intimidation" and int(en.get("pick", -1)) >= 0:
		var op := Politics.opinion(state, sid)
		if not op.is_empty() and Politics._argmax(op) != int(en["pick"]):
			out.append(["Intimidation électorale", int(action_def("intimidation").get("stability", -10))])
	return out


# --- Adopter, abroger (ordres) ------------------------------------------------------------------

static func check_adopt(state: GameState, empire_id: int, id: String) -> String:
	if not applies(state, empire_id):
		return "votre peuple n'a pas de vie politique"
	var d := law_def(id)
	if d.is_empty():
		return "loi inconnue : %s" % id
	if bool(d["power"]):
		return "une loi de pouvoir s'impose d'elle-même quand son courant est en tête"
	if bool(d.get("peoples", false)) and not state.peoples_on:
		return "les peuples mêlés ne sont pas actifs dans cette partie"
	if Grievances.interregnum(state, empire_id):
		return "interrègne : aucune loi jusqu'au %s" % GameCalendar.date_string(int(Politics.emp(state, empire_id)["inter"]))
	if is_enacted(state, empire_id, id):
		return "déjà en vigueur"
	for x in d.get("excludes", []):
		if is_enacted(state, empire_id, String(x)):
			return "incompatible avec %s" % String(law_def(String(x)).get("label", x))
	if used(state, empire_id) >= slots(state, empire_id):
		return "plus d'emplacement libre (%d)" % slots(state, empire_id)
	var i := int(d["current"])
	if i >= 0:
		if not Politics.applies(state, empire_id):
			return "pas de courants : seuls les Instincts s'adoptent"
		if not Politics.in_power(state, empire_id, i):
			return "%s n'est pas au pouvoir" % Politics.label(state, empire_id, i)
		if level(state, empire_id, i) < int(d["level"]):
			return "il faut que %s atteigne le niveau %d (niveau %d)" % [Politics.label(state, empire_id, i), int(d["level"]), level(state, empire_id, i)]
	var cost := adopt_cost(id)
	if not cost.is_empty() and not Economy.can_afford(state.get_empire(empire_id), cost):
		return "pas assez d'influence (%s)" % GameData.format_amounts(cost)
	return ""


static func adopt(state: GameState, empire_id: int, id: String) -> void:
	var cost := adopt_cost(id)
	if not cost.is_empty():
		Economy.pay(state.get_empire(empire_id), cost)
	var en := _w(state, empire_id)
	(en["laws"] as Array).append(id)
	state.relic_rev += 1


static func check_revoke(state: GameState, empire_id: int, id: String) -> String:
	if not applies(state, empire_id):
		return "votre peuple n'a pas de vie politique"
	if not is_enacted(state, empire_id, id):
		return "cette loi n'est pas en vigueur"
	return ""


static func revoke(state: GameState, empire_id: int, id: String) -> void:
	(_w(state, empire_id)["laws"] as Array).erase(id)
	state.relic_rev += 1


# --- Actions électorales (ordres) ---------------------------------------------------------------

static func action_def(id: String) -> Dictionary:
	var a: Variant = (data()["actions"] as Dictionary).get(id, {})
	return a if a is Dictionary else {}


## Actions permises par le régime de l'empire, dans l'ordre des données.
static func actions_for(state: GameState, empire_id: int) -> Array:
	var out := []
	if not Politics.applies(state, empire_id) or Politics.mode(state, empire_id) != "vote":
		return out
	var rid := Politics.regime_id(state, empire_id)
	for k in data()["actions"]:
		if String(k).begins_with("_"):
			continue
		if (data()["actions"][k].get("regimes", []) as Array).has(rid):
			out.append(String(k))
	return out


static func action(state: GameState, empire_id: int) -> String:
	return String(Politics.emp(state, empire_id).get("act", ""))


static func check_action(state: GameState, empire_id: int, id: String) -> String:
	if not Politics.applies(state, empire_id):
		return "votre peuple n'a pas de vie politique"
	if not actions_for(state, empire_id).has(id):
		return "action impossible sous ce régime"
	if Politics.pick(state, empire_id) < 0:
		return "soutenez d'abord un courant"
	if action(state, empire_id) != "":
		return "une action électorale est déjà en cours pour ce vote"
	var cost: Dictionary = action_def(id).get("cost", {})
	if not Economy.can_afford(state.get_empire(empire_id), cost):
		return "pas assez de ressources (%s)" % GameData.format_amounts(cost)
	return ""


static func do_action(state: GameState, empire_id: int, id: String) -> void:
	Economy.pay(state.get_empire(empire_id), action_def(id).get("cost", {}))
	Politics._emp_w(state, empire_id)["act"] = id


## Poids en plus des tirages (pour mille) : action électorale sur le courant soutenu, héros du Conseil.
static func vote_weights(state: GameState, empire_id: int) -> Array:
	var w := [0, 0, 0, 0, 0, 0]
	var en := Politics.emp(state, empire_id)
	var pick := int(en.get("pick", -1))
	var act := String(en.get("act", ""))
	if pick >= 0 and act != "":
		w[pick] += int(action_def(act).get("weight", 0))
		# Registre Picaresque : la réputation fait campagne aussi.
		var e := state.get_empire(empire_id)
		var tl: Dictionary = data()["talents"]
		if act == "campagne" and e != null and Reputation.has(e.faction()):
			@warning_ignore("integer_division")
			w[pick] += mini(int(tl["rep_weight_max"]), e.reputation * int(tl["rep_weight_pct"]) / 100)
	# Élection truquée par des espions étrangers (opération « Truquer l'élection »).
	var rig: Dictionary = en.get("rig", {})
	if not rig.is_empty() and int(rig.get("c", -1)) >= 0:
		w[int(rig["c"])] += int(data()["rig_weight"])
	# Héritier déloyal (féodalité) : il soutient le plus fort courant d'opposition à la Diète.
	var eh := state.get_empire(empire_id)
	if eh != null and Diplomacy.has_heir(state, empire_id) and eh.heir_loyalty >= 0 \
			and eh.heir_loyalty < int(Stability.talent(state, empire_id).get("heir_below", 30)):
		var opp := Grievances.opposition(state, empire_id, true)
		if opp >= 0:
			w[opp] += int(data()["talents"]["heir_weight"])
	if not state.heroes.is_empty():
		var hw := int(data()["heroes"]["vote_weight"])
		for h in Heroes.council(state, empire_id):
			var c := hero_current(state, h)
			if c >= 0:
				w[c] += hw
	return w


# --- Héros chefs de courant ---------------------------------------------------------------------

## Courant d'un héros : sa classe (Orateurs : Concorde), sinon son ambition ; -1 pour un Avatar.
static func hero_current(state: GameState, h: Dictionary) -> int:
	if not state.politics_on:
		return -1
	var hd: Dictionary = data()["heroes"]
	var by_cls: Dictionary = hd["class"]
	if by_cls.has(String(h.get("cls", ""))):
		return Politics.index_of(String(by_cls[String(h["cls"])]))
	var amb := String(h.get("amb", ""))
	if amb == "":
		return -1
	return Politics.index_of(String((hd["ambition"] as Dictionary).get(amb, "")))


## Le courant du héros gouverne-t-il ? (1 oui, -1 non, 0 sans objet : pas de courants, Avatar.)
static func hero_backing(state: GameState, h: Dictionary) -> int:
	if not state.politics_on:
		return 0
	var owner := int(h["owner"])
	if not Politics.applies(state, owner):
		return 0
	var c := hero_current(state, h)
	if c < 0:
		return 0
	var r: Array = Politics.emp(state, owner).get("ruling", [])
	return 1 if r.has(c) else -1


## Bonus de Conseil d'un héros dont le courant gouverne (pourcentage en plus).
static func council_pct(state: GameState, h: Dictionary) -> int:
	return int(data()["heroes"]["council_pct"]) if hero_backing(state, h) > 0 else 0


# --- Simulation --------------------------------------------------------------------------------

static func _w(state: GameState, empire_id: int) -> Dictionary:
	var en := Politics._emp_w(state, empire_id)
	if not en.has("laws"):
		en["laws"] = []
	if not en.has("xp"):
		var xp := [0, 0, 0, 0, 0, 0]
		for i in en.get("ruling", []):
			xp[int(i)] = 1
		en["xp"] = xp
	if not en.has("act"):
		en["act"] = ""
	return en


## Après une élection : un niveau de plus pour chaque courant au pouvoir, les lois des battus tombent.
static func after_election(state: GameState, empire_id: int) -> String:
	var en := _w(state, empire_id)
	var xp: Array = en["xp"]
	var r: Array = en["ruling"]
	var mx := int(rules()["xp_max"])
	for i in r:
		xp[int(i)] = mini(mx, int(xp[int(i)]) + 1)
	en["act"] = ""
	state.relic_rev += 1  # la loi de pouvoir a pu changer
	return _drop_fallen(state, empire_id, en)


## Retire les lois dont le courant n'est plus au pouvoir ; renvoie leurs noms (« » si aucune).
static func _drop_fallen(state: GameState, empire_id: int, en: Dictionary) -> String:
	var r: Array = en.get("ruling", [])
	var keep := []
	var fallen := PackedStringArray()
	for id in en["laws"]:
		var c := int(law_def(String(id)).get("current", -1))
		if c >= 0 and not r.has(c):
			fallen.append(String(law_def(String(id)).get("label", id)))
		else:
			keep.append(id)
	if not fallen.is_empty():
		en["laws"] = keep
		state.relic_rev += 1
	return ", ".join(fallen)


## Bilan mensuel des lois : conscience (niveau par 36 mois au pouvoir, lois des courants sortis),
## lois abrogées faute d'influence pour les entretenir.
static func monthly(state: GameState, empire_id: int, added: Array[Dictionary]) -> void:
	var en := _w(state, empire_id)
	var e := state.get_empire(empire_id)
	if Politics.applies(state, empire_id) and Politics.mode(state, empire_id) == "continuous":
		var cm: Array = en.get("cm", [0, 0, 0, 0, 0, 0])
		var xp: Array = en["xp"]
		for i in Politics.N:
			if (en["ruling"] as Array).has(i):
				cm[i] = int(cm[i]) + 1
				if int(cm[i]) % 36 == 0:
					xp[i] = mini(int(rules()["xp_max"]), int(xp[i]) + 1)
				xp[i] = maxi(1, int(xp[i]))
		en["cm"] = cm
		var f := _drop_fallen(state, empire_id, en)
		if f != "" and not e.is_ai():
			added.append(state.add_chronicle("%s : le consensus a changé, et avec lui la loi. Abrogé : %s." % [e.short_name(), f], Espionage.private_to(state, [empire_id])))
	var ls: Array = en["laws"]
	if ls.is_empty() or int(e.resources.get("influence", 0)) > 0:
		return
	if int(Economy.empire_income(state, empire_id)["net"].get("influence", 0)) >= 0:
		return
	var worst := ""
	var wl := -1
	for id in ls:
		var lv := int(law_def(String(id)).get("level", 0))
		if lv > wl:
			wl = lv
			worst = String(id)
	if wl <= 0:
		return
	revoke(state, empire_id, worst)
	added.append(state.add_chronicle("%s : les caisses de l'influence sont vides, « %s » est abrogée. Les juristes rangent leurs plumes." % [
			e.short_name(), String(law_def(worst).get("label", worst))], Espionage.private_to(state, [empire_id])))


static func setup(state: GameState) -> void:
	for e in state.empires:
		if applies(state, e.id):
			_w(state, e.id)
	state.relic_rev += 1  # les lois de pouvoir entrent dans Research.effects
