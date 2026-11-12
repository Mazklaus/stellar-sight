extends SceneTree
## Banc des curiosités, des événements et des reliques : parties de spectateurs (IA Normale) de 5 ans, avec et sans
## le pilier, sur plusieurs graines. Mesure le temps par jour, les événements tranchés, les curiosités
## sondées (par qui) et l'écart de score.
##   godot --headless --path . -s res://tools/event_bench.gd
const YEARS := 5
const SEEDS := [3, 17, 99]


func _run(sd: int, opts: Dictionary) -> Dictionary:
	var o := {"spectator": true, "ai_level": OS.get_environment("LEVEL") if OS.get_environment("LEVEL") != "" else "normal"}
	o.merge(opts)
	var sim := Simulation.new(GameState.create(sd, 150, 1800.0, "", o))
	var t0 := Time.get_ticks_msec()
	sim.advance(360 * YEARS)
	var ms := float(Time.get_ticks_msec() - t0) / (360.0 * YEARS)
	var st := sim.state
	var answered := 0
	var cards := {}
	for eid in st.ev_meta:
		for x: Dictionary in st.ev_meta[eid]["log"]:
			answered += 1
			cards[String(x["card"])] = true
	var probed := {}
	var open := 0
	for pid in st.curios:
		var d := int(st.curios[pid]["done"])
		if d >= 0:
			var n := st.get_empire(d).short_name()
			probed[n] = int(probed.get(n, 0)) + 1
		else:
			open += 1
	var found := 0
	for id in st.relics:
		if int(st.relics[id]["owner"]) >= 0:
			found += 1
	var started := 0
	for sid in st.digs:
		if int(st.digs[sid]["by"]) >= 0:
			started += 1
	var score := 0
	for e in st.empires:
		score += EmpireReport.score(st, e.id)
	return {"ms": ms, "answered": answered, "cards": cards.size(), "probed": probed, "open": open, "score": score, "relics": found, "digs": "%d/%d" % [started, st.digs.size()]}


func _initialize() -> void:
	for sd in SEEDS:
		var off := _run(sd, {})
		var on := _run(sd, {"curios": "normales", "events": "normaux"})
		print("graine %d : sans %.2f ms/j score %d | avec %.2f ms/j score %d, %d événements tranchés (%d cartes différentes), curiosités sondées %s, %d encore ouvertes, fouilles lancées %s, reliques trouvées %d" % [
				sd, off["ms"], off["score"], on["ms"], on["score"], on["answered"], on["cards"], str(on["probed"]), on["open"], on["digs"], on["relics"]])
	quit()
