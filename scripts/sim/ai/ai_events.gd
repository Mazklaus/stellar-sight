class_name AiEvents
extends RefCounted
## Événements des empires IA (voir Events, proposition 17) : chaque carte de la boîte reçoit une
## réponse le jour même. Normale et au-dessus : le choix qui rapporte le plus selon une valeur simple
## des effets (ressources, stabilité, opinion, héros…), pondérée par le tempérament (un belliqueux se
## moque des affronts, un pacifique les évite) et par le goût du risque. Recrue : un choix sur trois
## au hasard (mal choisir n'est pas ignorer). Les curiosités, elles, se sondent toutes seules : les
## éclaireurs en exploration automatique s'arrêtent le temps qu'il faut (Curios.wants_to_stay).

## Valeur d'une unité de chaque ressource.
const RES_VALUE := {"energy": 10, "materials": 10, "food": 8, "influence": 30, "crystals": 40, "knowledge": 10}


static func think(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if not state.ev_meta.has(e.id):
		return
	var box: Array = Events.inbox(state, e.id)
	if box.is_empty():
		return
	var skill := int(ctx["lv"].get("faction_use", 1))
	var temper := clampi(AiLevels.aggression(e), -2, 2)
	for item: Dictionary in box.duplicate():
		var opts := Events.choices(state, e.id, item)
		var best := -1
		var best_v := -1000000
		var ok_list: Array = []
		for o: Dictionary in opts:
			if not bool(o["ok"]):
				continue
			ok_list.append(int(o["index"]))
			var v := value(state, e.id, item, int(o["index"]), temper)
			if v > best_v:
				best_v = v
				best = int(o["index"])
		if best < 0:
			continue
		if skill == 0 and Events._h(state, ["ai", e.id, int(item["id"])]) % 3 == 0:
			best = int(ok_list[Events._h(state, ["ai-pick", e.id, int(item["id"])]) % ok_list.size()])
		AiPlayer._issue(ctx, SimCommands.event_choose(e.id, int(item["id"]), best))


## Valeur d'un choix pour l'IA (plus c'est haut, mieux c'est). temper : -2 pacifique … +2 belliqueux.
static func value(state: GameState, empire_id: int, item: Dictionary, index: int, temper: int) -> int:
	var ch: Dictionary = (Events.card(String(item["card"]))["choices"] as Array)[index]
	var v := _fx_value(state, empire_id, ch.get("fx", []), temper)
	if ch.has("risky"):
		var rk: Dictionary = ch["risky"]
		var pct := int(rk["pct"])
		@warning_ignore("integer_division")
		v += (_fx_value(state, empire_id, rk["win"], temper) * pct + _fx_value(state, empire_id, rk["lose"], temper) * (100 - pct)) / 100
		v += temper * 30  # les belliqueux aiment les paris
	return v


static func _fx_value(state: GameState, empire_id: int, fxs: Array, temper: int) -> int:
	var e := state.get_empire(empire_id)
	var f := e.faction()
	var v := 0
	for fx: Dictionary in fxs:
		match String(fx["k"]):
			"res":
				for r in fx["res"]:
					v += Events.era_scaled(state, empire_id, int(fx["res"][r])) * int(RES_VALUE.get(r, 10))
			"stab":
				if Stability.applies(state, empire_id):
					var n := Events.own_systems(state, empire_id).size() if String(fx.get("scope", "system")) == "empire" else 1
					@warning_ignore("integer_division")
					v += int(fx["v"]) * 25 * mini(n, 6) * int(fx["days"]) / 360
			"fervor":
				if FactionTraits.has_fervor(f):
					v += int(fx["v"]) * 25
			"rep":
				if Reputation.has(f):
					v += int(fx["v"]) * 40
			"echoes":
				if Echoes.has(f):
					v += int(fx["v"]) * 15
			"biomass":
				if f.has("biomass"):
					v += int(fx["v"]) * 5
			"opinion":
				var md: Dictionary = Diplomacy.data()["memories"].get(String(fx["kind"]), {})
				var ov := int(md.get("value", 0)) * 25
				# Un belliqueux se soucie peu de ce qu'on pense de lui.
				@warning_ignore("integer_division")
				v += ov * (3 - clampi(temper, -2, 2)) / 3
			"pop":
				v += int(fx["v"]) * 400
			"ship":
				v += Combat.ship_strength(String(fx["ship"])) * 8
			"research":
				v += int(fx["pct"]) * 40
			"renown":
				v += int(fx["v"]) * 5
			"hero_xp":
				v += int(fx["v"]) * 3
			"hero_wound":
				v -= 900
			"deposit":
				v += 1200
			"pirates":
				v -= 800
	return v
