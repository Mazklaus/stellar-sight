extends SceneTree
## Banc de la faune : parties de spectateurs (IA Normale par défaut, LEVEL=… pour changer) de 8 ans
## (YEARS=…), sans créatures puis avec la densité DENSITY (normales par défaut), sur plusieurs graines.
## Mesure le temps par jour, l'expansion (systèmes tenus), les empires éliminés, les créatures abattues,
## les nids détruits, les gardiens abattus, les études et attitudes prises par les IA.
##   godot --headless --path . -s res://tools/creature_bench.gd
var YEARS := int(OS.get_environment("YEARS")) if OS.get_environment("YEARS") != "" else 8
var DENSITY := OS.get_environment("DENSITY") if OS.get_environment("DENSITY") != "" else "normales"
const SEEDS := [3, 17, 42, 99, 123, 256]


func _run(sd: int, density: String) -> Dictionary:
	var o := {"spectator": true, "ai_level": OS.get_environment("LEVEL") if OS.get_environment("LEVEL") != "" else "normal", "creatures": density}
	var sim := Simulation.new(GameState.create(sd, 150, 1800.0, "", o))
	var nests := Fauna.nest_ids(sim.state).size()
	var t0 := Time.get_ticks_msec()
	sim.advance(360 * YEARS)
	var ms := float(Time.get_ticks_msec() - t0) / (360.0 * YEARS)
	var st := sim.state
	var owned := 0
	var dead := 0
	var kills := 0
	var studies := 0
	var stances := {}
	for e in st.empires:
		owned += EmpireReport.owned_systems(st, e.id).size()
		if e.eliminated:
			dead += 1
		for sp in Fauna.species_ids():
			kills += Fauna.kills(st, e.id, sp)
			if Fauna.study_end(st, e.id, sp) != 0:
				studies += 1
			var s := Fauna.stance(st, e.id, sp)
			if s != "":
				stances[s] = int(stances.get(s, 0)) + 1
	var gdead := 0
	for gid in Guardians.ids(st):
		if String(Guardians.list(st)[gid]["status"]) == "dead":
			gdead += 1
	return {"guard": "%d/%d" % [gdead, Guardians.ids(st).size()], "ms": ms, "owned": owned, "dead": dead, "kills": kills, "nests": "%d/%d" % [Fauna.nest_ids(st).size(), nests],
			"herds": Fauna.herd_ids(st).size(), "studies": studies, "stances": stances}


func _initialize() -> void:
	var sum_off := 0
	var sum_on := 0
	for sd in SEEDS:
		var off := _run(sd, "aucune")
		var on := _run(sd, DENSITY)
		sum_off += int(off["owned"])
		sum_on += int(on["owned"])
		print("graine %d : sans %.2f ms/j, %d systèmes, %d éliminés | avec %.2f ms/j, %d systèmes, %d éliminés, nids %s, %d troupeaux, %d créatures abattues, %d études, attitudes %s, gardiens abattus %s" % [
				sd, off["ms"], off["owned"], off["dead"], on["ms"], on["owned"], on["dead"], on["nests"], on["herds"], on["kills"], on["studies"], str(on["stances"]), on["guard"]])
	print("total des systèmes tenus : sans %d, avec %d (%+d %%)" % [sum_off, sum_on, (sum_on - sum_off) * 100 / maxi(1, sum_off)])
	quit()
