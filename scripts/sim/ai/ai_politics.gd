class_name AiPolitics
extends RefCounted
## Politique intérieure des empires IA (voir Politics) : le soutien officiel avant chaque élection
## (ou le courant nommé, en théocratie et en horde). Une fois par mois, décalé selon l'empire, dans
## les 90 jours qui précèdent le vote.
## Recrue : son courant principal, toujours. Normale et au-dessus : le Glaive si elle est belliqueuse
## (agressivité 2 ou plus), la Concorde si elle est pacifique (-2 ou moins), sinon son courant
## principal ; mais si trop de ses systèmes ne sont pas représentés (rally_pct), elle soutient le
## courant le plus fort de son opinion pour les rallier.
## Lot 2 (voir Laws) : chaque mois, elle adopte une loi si un emplacement est libre et que son influence
## le permet (réserve, revenu après entretien), choisie selon son tempérament et ses besoins ; la
## Recrue prend la première venue. Normale et au-dessus : une campagne avant le vote si elle est riche.


static func think(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	# Une fois par mois : la fenêtre a la longueur du rythme de réflexion du niveau, donc l'IA y
	# réfléchit exactement une fois.
	var every := maxi(1, int(ctx["lv"].get("think_days", 10)))
	if Laws.applies(state, e.id) and posmod(state.tick + e.id * 11 + 15, 30) < every:
		_laws(ctx, int(ctx["lv"].get("faction_use", 1)))
	if not Politics.applies(state, e.id) or Politics.mode(state, e.id) == "continuous":
		return
	if posmod(state.tick + e.id * 11, 30) >= every:
		return
	var nxt := Politics.next_election(state, e.id)
	if nxt < 0 or nxt - state.tick > 90:
		return
	var skill := int(ctx["lv"].get("faction_use", 1))
	if Politics.pick(state, e.id) < 0:
		AiPlayer._issue(ctx, SimCommands.politics_support(e.id, choose(state, e, skill)))
		return
	if skill >= 1 and Laws.action(state, e.id) == "" and int(e.resources.get("influence", 0)) >= int(Politics.data()["ai"]["campaign_at"]):
		for a in Laws.actions_for(state, e.id):
			if Laws.check_action(state, e.id, String(a)) == "":
				AiPlayer._issue(ctx, SimCommands.politics_action(e.id, String(a)))
				break


## Lois : une adoption au plus par mois.
static func _laws(ctx: Dictionary, skill: int) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if Laws.used(state, e.id) >= Laws.slots(state, e.id):
		return
	var ai: Dictionary = Politics.data()["ai"]
	var inf := int(e.resources.get("influence", 0))
	var net := int(Economy.empire_income(state, e.id)["net"].get("influence", 0))
	var stab := Stability.empire_value(state, e.id)
	var ag := AiLevels.aggression(e)
	var at_war := not e.wars.is_empty()
	var has_currents := Politics.applies(state, e.id)
	var best := ""
	var bs := -1000
	var cands: Array = []
	if has_currents:
		for i in Politics.ruling(state, e.id):
			for l: Dictionary in Laws.current_laws(int(i)):
				cands.append(String(l["id"]))
	for l: Dictionary in Laws.independent():
		cands.append(String(l["id"]))
	for id in cands:
		if Laws.check_adopt(state, e.id, id) != "":
			continue
		var cost := int(Laws.adopt_cost(id).get("influence", 0))
		if cost > 0 and (inf - cost < int(ai["reserve"]) or net - Laws.law_upkeep(state, e.id, id) < int(ai["min_net"])):
			continue
		var sc := _score(state, e, id, stab, ag, at_war, has_currents)
		if skill <= 0:
			sc = 100 - int(Laws.law_def(id).get("level", 0))  # la Recrue prend la première venue
		if sc > bs:
			bs = sc
			best = id
	if best != "" and bs > 0:
		AiPlayer._issue(ctx, SimCommands.law_adopt(e.id, best))


static func _score(state: GameState, e: Empire, id: String, stab: int, ag: int, at_war: bool, has_currents: bool) -> int:
	var d := Laws.law_def(id)
	var fx: Dictionary = d.get("fx", {})
	if bool(d.get("peoples", false)):
		return AiPeoples.law_score(state, e, id, ag)
	var st := int(fx.get("stability", 0)) - (3 if fx.has("stability_pop_div") else 0)
	if st < 0 and stab + st < 50:
		return -1
	var sc := int(d.get("level", 0)) * 10
	if int(d["current"]) < 0:
		# Lois indépendantes : seulement quand elles répondent à un besoin (la ruche n'a qu'elles).
		sc = 5 if not has_currents else -20
	if st > 0 and stab < 50:
		sc += st * 4
	var cur := Politics.current_id(int(d["current"]))
	if cur == "glaive":
		sc += ag * 6 + (15 if at_war else 0)
	elif cur == "concorde":
		sc -= ag * 6
	if at_war and (fx.has("troops_pct") or fx.has("damage_pct") or fx.has("garrison_pct")):
		sc += 10
	if fx.has("trade_income_pct"):
		var trades := 0
		for o in e.contacts:
			if Diplomacy.has_trade(state, e.id, int(o)):
				trades += 1
		sc += -10 if trades == 0 else trades * 4
	if fx.has("growth_pct") and int(fx["growth_pct"]) < 0 and not at_war:
		sc -= 20
	return sc


## Courant que l'IA soutient.
static func choose(state: GameState, e: Empire, skill: int) -> int:
	var main := Politics.principal(state, e.id)
	if skill <= 0:
		return main
	# Conclave, Kurultaï : un seul courant gouverne, nommer celui que le peuple préfère garde le plus de
	# systèmes représentés (et ne coûte pas de ferveur).
	if Politics.mode(state, e.id) == "appoint":
		return Politics._argmax(Politics.empire_opinion(state, e.id))
	var ag := AiLevels.aggression(e)
	if ag >= 2:
		return Politics.index_of("glaive")
	if ag <= -2:
		return Politics.index_of("concorde")
	var out := 0
	var tot := 0
	for sid in Stability.systems_of(state, e.id):
		var en := Politics.sys_entry(state, sid)
		if en.is_empty() or int(en.get("rep", -1)) < 0:
			continue
		tot += 1
		if not Politics.in_power(state, e.id, int(en["rep"])):
			out += 1
	if tot > 0 and out * 100 >= tot * int(Politics.data()["ai"]["rally_pct"]):
		return Politics._argmax(Politics.empire_opinion(state, e.id))
	return main
