extends SceneTree
## Mesure le coût de chaque système de simulation sur une partie entre IA :
##   godot --headless --path . -s res://tools/profile_ai.gd
func _initialize() -> void:
	var st := GameState.create(3, 150, 1800.0, "", {"spectator": true})
	var t := {"eco": 0, "fleet": 0, "chron": 0, "ai": 0}
	for i in 3600:
		st.tick += 1
		var a := Time.get_ticks_usec()
		EconomySystem.process(st)
		var b := Time.get_ticks_usec()
		FleetSystem.process(st)
		var c := Time.get_ticks_usec()
		ChronicleSystem.process(st)
		var d := Time.get_ticks_usec()
		AiSystem.process(st)
		var e := Time.get_ticks_usec()
		t["eco"] += b - a
		t["fleet"] += c - b
		t["chron"] += d - c
		t["ai"] += e - d
		if i % 600 == 599:
			print("an %d : %s ms | colonies %d flottes %d" % [(i + 1) / 360, str(t.values().map(func(v): return v / 1000)), st.colonies.size(), st.fleets.size()])
	for e in st.empires:
		print(e.short_name(), " ", EmpireReport.totals(st, e.id), " expl ", e.explored.size(), " ", e.ai_intent)
	quit()
