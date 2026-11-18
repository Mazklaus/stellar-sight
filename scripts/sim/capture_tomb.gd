class_name CaptureTomb
extends RefCounted
## Vaisseau-tombe (prises de guerre, prop. 27 ; voir data/capture.json "tomb") : un amas errant de coques
## soudées qui dérive de système en système. À partir de l'an 5, chaque année, une chance qu'il
## apparaisse (un seul à la fois). On l'aborde avec beaucoup de troupes (60) et l'on tire sur une table :
## savoir, relique, coque intacte, créatures (troupes perdues, il reste là) ou pirates.
## État : state.capture["tomb"] = {"sid", "next" (prochain déplacement), "until" (disparition), "n"}.


static func _r(key: String, def := 0) -> int:
	return Capture.rule(key, def)


static func tomb(state: GameState) -> Dictionary:
	if not Capture.full(state):
		return {}
	return Capture.sub(state, "tomb")


static func active(state: GameState) -> bool:
	return tomb(state).has("sid")


static func system(state: GameState) -> int:
	return int(tomb(state).get("sid", -1))


static func label() -> String:
	return String(Capture.data().get("tomb", {}).get("label", "Vaisseau-tombe"))


static func daily(state: GameState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var t := tomb(state)
	var year_days := 360
	if not t.has("sid"):
		if state.tick > 0 and state.tick % year_days == 0 and state.tick >= _r("tomb_year", 5) * year_days \
				and state.rng.randi_range(0, 99) < _r("tomb_chance", 25):
			_spawn(state, out)
		return out
	if state.tick >= int(t["until"]):
		out.append(state.add_chronicle("Le %s quitte la galaxie comme il est venu : sans prévenir, et avec tout ce qu'il contenait." % label().to_lower()))
		t.clear()
		return out
	if state.tick >= int(t["next"]):
		var s: StarSystem = state.galaxy.systems[int(t["sid"])]
		if not s.neighbors.is_empty():
			var nb := s.neighbors.duplicate()
			nb.sort()
			t["sid"] = int(nb[state.rng.randi_range(0, nb.size() - 1)])
		t["next"] = state.tick + _r("tomb_move_days", 90)
	return out


static func _spawn(state: GameState, out: Array[Dictionary]) -> void:
	var n := state.galaxy.systems.size()
	if n == 0:
		return
	var sid := state.rng.randi_range(0, n - 1)
	var t := tomb(state)
	t["sid"] = sid
	t["next"] = state.tick + _r("tomb_move_days", 90)
	t["until"] = state.tick + _r("tomb_life_days", 1800)
	t["n"] = int(t.get("n", 0)) + 1
	Announce.next(state, "tomb_seen", {"system": sid})
	out.append(state.add_chronicle("Un %s dérive près de %s. %s" % [label().to_lower(), state.galaxy.systems[sid].system_name,
			String(Capture.data().get("tomb", {}).get("text", ""))]))


## Force l'apparition (tests, outil de captures).
static func force_spawn(state: GameState, sid: int) -> void:
	var t := tomb(state)
	t["sid"] = sid
	t["next"] = state.tick + _r("tomb_move_days", 90)
	t["until"] = state.tick + _r("tomb_life_days", 1800)


static func check(state: GameState, player: int, d: Dictionary) -> String:
	if not active(state):
		return "aucun %s en vue" % label().to_lower()
	var f: Fleet = state.fleets.get(int(d.get("fleet", -1)))
	if f == null or f.owner != player:
		return "cette flotte ne vous appartient pas"
	if f.system_id != system(state) or f.is_moving():
		return "la flotte doit être à l'arrêt dans le système du %s" % label().to_lower()
	if Capture.layer(state, player, "no_board"):
		return "votre peuple n'aborde pas"
	if f.troops < _r("tomb_troops", 60):
		return "il faut %d troupes à bord (la flotte en a %d)" % [_r("tomb_troops", 60), f.troops]
	return ""


static func apply(state: GameState, player: int, d: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var f: Fleet = state.fleets[int(d["fleet"])]
	var e := state.get_empire(player)
	var sid := f.system_id
	f.troops -= _r("tomb_troops", 60)
	var row := _roll(state)
	var what := ""
	var spent := true
	match String(row.get("id", "")):
		"savoir":
			what = _knowledge(state, player)
		"relique":
			what = _relic(state, player)
			if what == "":
				what = _knowledge(state, player)
		"coque":
			var ship := Capture.prize_id("cuirasse" if not GameData.ship("cuirasse").is_empty() else "croiseur",
					Capture.roll_avaries(state, 0, _r("wreck_avaries_min", 2), _r("wreck_avaries_max", 4)))
			CaptureLore.spawn_prize(state, player, ship, sid)
			what = "%s remis en service" % String(GameData.ship(Capture.base_of(ship)).get("label", ship))
		"creatures":
			what = "les troupes ne reviennent pas"
			spent = false
		"pirates":
			var pf := state.spawn_ship(GameState.PIRATE_ID, "corvette", sid)
			pf.add_ship("fregate", -1, 1)
			pf.add_ship("fregate", -1, 1)
			pf.troops = 0
			pf.fleet_name = "Locataires du %s" % label().to_lower()
			what = "trois vaisseaux pirates s'en échappent"
	Capture.note_stat(state, player, "tomb")
	out.append(state.add_chronicle("%s aborde le %s à %s : %s. %s" % [e.short_name(), label().to_lower(), state.galaxy.systems[sid].system_name,
			String(row.get("label", "")), what[0].to_upper() + what.substr(1) + "."]))
	if spent:
		tomb(state).clear()
	return out


static func _roll(state: GameState) -> Dictionary:
	var table: Array = Capture.data().get("tomb", {}).get("table", [])
	var total := 0
	for r: Dictionary in table:
		total += int(r["w"])
	if total <= 0:
		return {}
	var x := state.rng.randi_range(0, total - 1)
	for r: Dictionary in table:
		x -= int(r["w"])
		if x < 0:
			return r
	return table[0]


## Trois technologies (file de recherche d'abord) avancent de moitié.
@warning_ignore("integer_division")
static func _knowledge(state: GameState, eid: int) -> String:
	var e := state.get_empire(eid)
	var picks: Array[String] = []
	for tid in e.research_queue:
		if picks.size() < 3 and not Research.knows(state, eid, tid):
			picks.append(tid)
	if picks.is_empty():
		return Events.give_research(state, eid, 50)
	var names := PackedStringArray()
	for tid in picks:
		Research.add_progress(state, eid, tid, maxi(1, Research.cost(state, eid, tid) / 2))
		names.append(String(Research.tech(tid).get("label", tid)))
	return "progrès sur " + ", ".join(names)


static func _relic(state: GameState, eid: int) -> String:
	var ids := state.relics.keys()
	ids.sort()
	for rid in ids:
		var r: Dictionary = state.relics[rid]
		var id := String(rid)
		if int(r.get("owner", -1)) == -1 and not Relics._buried(state, id) and not Relics.is_quest(id) and not Relics.is_trophy(id) \
				and not Relics.is_ancient_relic(id) and not Relics.is_disparu(id) and not Archaeology.relic_locked(state, id):
			Relics.gain(state, eid, String(rid))
			return "la relique %s" % String(Relics.def(String(rid)).get("label", rid))
	return ""
