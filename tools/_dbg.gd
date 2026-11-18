extends SceneTree
func _initialize() -> void:
	var st := GameState.create(21, 150, 1800.0, "ossarane", {"ai_level": "", "capture": "complete"})
	var me := st.empires[0].id
	var foe := (me + 1) % st.empires.size()
	var sid := -1
	for s in st.galaxy.systems:
		if st.system_owner(s.id) == -1 and s.neighbors.size() >= 2:
			sid = s.id
			break
	for p in [[me, foe], [foe, me]]:
		if not st.get_empire(p[0]).contacts.has(p[1]):
			st.get_empire(p[0]).contacts.append(p[1])
	Combat.start_war(st, me, foe)
	Research.grant(st, me, ["equipes_prise"])
	GameData.register_custom_ship("t_pods", {"label": "Capsulier", "size": "medium", "hp": 100, "troops": 20, "assault_pods": true, "military": true, "weapons": {"kinetic": 5}})
	var pods := st.spawn_ship(me, "t_pods", sid)
	pods.troops = 20
	Capture.set_posture(st, pods.id, true)
	var lone := st.spawn_ship(foe, "corvette", sid)
	lone.hp[0] = 1
	var fl: Array[Fleet] = [pods, lone]
	print("posture ", Capture.posture(st, pods), " flag ", Combat._fleet_has_flag(pods, "assault_pods"), " can ", Capture.can_board(st, pods, lone, 0, fl), " hostile ", Combat.hostile_fleets(st, pods, lone), " chance ", Capture.chance(st, pods, lone, 0), " skill ", Capture._ai_skill(st, me))
	quit()
