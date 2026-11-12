extends SceneTree
## Banc des curiosités, des événements, des reliques et des quêtes : parties de spectateurs (IA
## Normale) de 5 ans (YEARS=… pour changer), avec et sans le pilier, sur plusieurs graines. Mesure le
## temps par jour, les événements tranchés, les curiosités sondées (par qui), les fouilles, les
## chapitres de quête, les retournements galactiques et l'écart de score.
##   godot --headless --path . -s res://tools/event_bench.gd
var YEARS := int(OS.get_environment("YEARS")) if OS.get_environment("YEARS") != "" else 5
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
	var chapters := 0
	var done := 0
	var credo := 0
	for id in st.quests:
		var q: Dictionary = st.quests[id]
		chapters += (q["path"] as Array).size()
		if String(q["status"]) == "done":
			done += 1
			if Quests.is_credo(q):
				credo += 1
	var gal := []
	for l: Dictionary in st.galactic.get("log", []):
		var w := st.get_empire(int(l["winner"]))
		gal.append("%s→%s" % [String(l["id"]), w.short_name() if w != null else "personne"])
	if not Quests.current(st).is_empty():
		gal.append(String(Quests.current(st)["id"]) + " en cours")
	return {"ms": ms, "answered": answered, "cards": cards.size(), "probed": probed, "open": open, "score": score, "relics": found, "digs": "%d/%d" % [started, st.digs.size()],
			"quests": "%d chapitres, %d quêtes achevées dont %d de peuple" % [chapters, done, credo], "galactic": ", ".join(gal)}


func _initialize() -> void:
	for sd in SEEDS:
		var off := _run(sd, {})
		var on := _run(sd, {"curios": "normales", "events": "normaux", "quests": "toutes"})
		print("graine %d : sans %.2f ms/j score %d | avec %.2f ms/j score %d, %d événements tranchés (%d cartes différentes), curiosités sondées %s, %d encore ouvertes, fouilles lancées %s, reliques trouvées %d, quêtes : %s, retournements : %s" % [
				sd, off["ms"], off["score"], on["ms"], on["score"], on["answered"], on["cards"], str(on["probed"]), on["open"], on["digs"], on["relics"], on["quests"], on["galactic"]])
	quit()
