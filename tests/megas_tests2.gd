class_name MegasTests2
extends RefCounted
## Tests des mégastructures, lot 2 : catalogue (sites et limites), ruines et leur restauration, Forteresse
## dormante, événements de chantier, Catapulte quantique, superarmes, talents, IA.

const T := preload("res://tests/megas_tests.gd")

var _check: Callable


static func run(check: Callable) -> void:
	var t := MegasTests2.new()
	t._check = check
	print("  - catalogue")
	t._test_catalogue()
	print("  - ruins")
	t._test_ruins()
	print("  - catapult")
	t._test_catapult()
	print("  - weapons")
	t._test_weapons()
	print("  - events_talents")
	t._test_events_talents()
	print("  - ai")
	t._test_ai()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


func _test_catalogue() -> void:
	var st := T.new_game()
	var sid := T.home_sys(st, 0)
	Research.grant_all(st, 0)
	T.rich(st, 0)
	var home := st.get_empire(0).capital_planet
	_ok(Megastructures.site_reason(st, 0, "forteresse_dormante", sid, -1).contains("ruine"), "la Forteresse dormante ne se bâtit pas")
	_ok(Megastructures.site_reason(st, 0, "siphon_geante", sid, home) != "", "Siphon : seulement sur une géante gazeuse")
	var gp := T.free_planet(st, sid, "gas_giant")
	if gp >= 0:
		_ok(Megastructures.site_reason(st, 0, "siphon_geante", sid, gp) == "", "Siphon possible sur une géante gazeuse libre")
		var id := T.build_full(st, 0, "siphon_geante", sid, gp)
		_ok(Logistics.has_depot(st, sid, 0), "Siphon achevé : dépôt de ravitaillement")
		st.override_planet(gp, {"type": "barren"})
		_ok(Megastructures.site_reason(st, 0, "forge_noyau", sid, gp).contains("porte déjà"), "une planète, une mégastructure")
		Megastructures.entries(st).erase(str(id))
	var star := st.galaxy.systems[sid].star_type
	_ok(Megastructures.site_reason(st, 0, "catapulte_quantique", sid, -1) == "" if star == "neutron" else Megastructures.site_reason(st, 0, "catapulte_quantique", sid, -1).contains("seulement"), "Catapulte : seulement autour d'une étoile à neutrons")
	_ok(Megastructures.site_reason(st, 0, "decompresseur", sid, -1) == "" if star == "black_hole" else Megastructures.site_reason(st, 0, "decompresseur", sid, -1).contains("seulement"), "Décompresseur : seulement autour d'un trou noir")
	_ok(Megastructures.site_reason(st, 0, "matriochka", sid, -1).contains("Sphère"), "Matriochka : seulement sur sa Sphère achevée")
	T.build_full(st, 0, "mega_chantier", sid)
	_ok(Megastructures.site_reason(st, 0, "reseau_veille", sid, -1).contains("porte déjà"), "une étoile, une mégastructure")
	_ok(Research.fx_int(st, 0, "titan_days_pct") < 0, "Méga-chantier naval : titans plus rapides")
	var titan := ""
	for sh in GameData.ship_ids():
		if String(GameData.ship(sh).get("size", "")) == "titan" and int(GameData.ship(sh).get("days", 1)) >= 20:
			titan = sh
			break
	if titan != "":
		var base := int(GameData.ship(titan).get("days", 1))
		_ok(Fleets.ship_days(st, 0, titan) < base, "un titan sort plus vite (%d < %d jours)" % [Fleets.ship_days(st, 0, titan), base])
	# Limite par empire.
	var limited := ""
	for k in Megastructures.kind_ids():
		if int((Megastructures.kind_def(k).get("limit", {}) as Dictionary).get("empire", 0)) == 1 and Megastructures.body(k) == "star" and not bool(Megastructures.kind_def(k).get("ruin_only", false)) and k != "mega_chantier":
			limited = k
			break
	var other := T.build_full(st, 0, limited, int(st.galaxy.systems[sid].neighbors[0]))
	_ok(Megastructures.site_reason(st, 0, limited, sid, -1).contains("limite") or Megastructures.site_reason(st, 0, limited, sid, -1).contains("porte déjà"), "une seule %s par empire" % Megastructures.label(limited))
	Megastructures.entries(st).erase(str(other))
	# Effets plafonnés et Œuvre monumentale.
	var st2 := T.new_game()
	var s2 := T.home_sys(st2, 0)
	var stab := Research.fx_int(st2, 0, "stability")
	T.build_full(st2, 0, "oeuvre_monumentale", s2)
	_ok(Research.fx_int(st2, 0, "stability") > stab, "Œuvre monumentale : stabilité")
	T.build_full(st2, 0, "forum_interstellaire", int(st2.galaxy.systems[s2].neighbors[0]))
	_ok(Megastructures.voix_pct(st2, 0) > 0, "Forum interstellaire : voix amphictyoniques")


func _test_ruins() -> void:
	var st := T.new_game("completes", "beaucoup")
	var ruins: Array[Dictionary] = []
	for x in MegasWorld.ruins(st):
		if st.galaxy.systems[int(x["s"])].planet_ids.size() >= 2:
			ruins.append(x)
	if ruins.is_empty():
		_ok(false, "des ruines à relever")
		return
	var m: Dictionary = ruins[0]
	var id := int(m["id"])
	var sid := int(m["s"])
	T.rich(st, 0)
	_ok(MegasWorld.check_restore(st, 0, id).contains("tenir"), "relever une ruine : il faut tenir le système")
	# Un avant-poste dans le système de la ruine.
	var c := Colony.new()
	for pid in st.galaxy.systems[sid].planet_ids:
		if not st.colonies.has(pid) and pid != int(m["p"]):
			c.planet_id = pid
			break
	if c.planet_id < 0:
		c.planet_id = st.galaxy.systems[sid].planet_ids[0]
	c.owner = 0
	c.kind = Colony.KIND_OUTPOST
	st.add_colony(c)
	_ok(MegasWorld.check_restore(st, 0, id).contains("architecte"), "il faut un Vaisseau-architecte sur place")
	T.architect(st, 0, sid)
	Research.grant(st, 0, ["mega_ingenierie"])
	var why := MegasWorld.check_restore(st, 0, id)
	_ok(why == "", "restauration possible (%s)" % why)
	if why != "":
		return
	var st_before := int(m["st"])
	_ok(T.cmd(st, 0, "restore", {"id": id}) == "", "restauration lancée")
	_ok(int(Megastructures.get_m(st, id)["o"]) == 0 and Megastructures.busy(st, 0) == 1, "la ruine est à nous, une étape en chantier")
	T.finish_running(st, id)
	var r := Megastructures.get_m(st, id)
	_ok(not Megastructures.is_ruin(r) and int(r["st"]) == st_before, "relevée avec les étapes qu'elle gardait (%d)" % st_before)
	# Brisecomètes : moitié prix, deux fois plus vite.
	var bc := T.new_game("completes", "beaucoup", "brisecomete")
	var beid := T.eid_of(bc, "brisecomete")
	var rr := MegasWorld.ruins(bc)
	if not rr.is_empty():
		var a := MegasWorld.restore_cost(bc, beid, rr[0])
		var b := MegasWorld.restore_cost(bc, 0 if beid != 0 else 1, rr[0])
		_ok(int(a.get("materials", 0)) < int(b.get("materials", 0)) or b.is_empty(), "Brisecomètes : ruines à moitié prix")
		_ok(MegasWorld.restore_days(bc, beid) < Megastructures.r_int("restore_days", 360), "Brisecomètes : deux fois plus vite")
	# Forteresse dormante : l'Éveil attend une puissance ancienne.
	var fst := T.new_game()
	var fs := T.home_sys(fst, 0)
	Research.grant(fst, 0, ["mega_ingenierie"])
	T.rich(fst, 0)
	var fid := T.build_full(fst, 0, "forteresse_dormante", fs)
	var fm := Megastructures.get_m(fst, fid)
	fm["st"] = 2
	Megastructures.touch(fst)
	_ok(Research.fx_int(fst, 0, "repair_pct") >= 50, "Forteresse relevée : base navale (réparations)")
	_ok(T.cmd(fst, 0, "advance", {"id": fid}).contains("Éveil"), "l'Éveil attend le réveil d'une puissance ancienne")


func _test_catapult() -> void:
	var st := T.new_game()
	var sid := T.home_sys(st, 0)
	var e := st.get_empire(0)
	T.rich(st, 0)
	var id := T.build_full(st, 0, "catapulte_quantique", sid)
	var f: Fleet = null
	for fid in st.sorted_fleet_ids():
		var x: Fleet = st.fleets[fid]
		if x.owner == 0 and x.system_id == sid and not x.is_moving():
			f = x
			break
	if f == null:
		f = st.spawn_ship(0, GameData.ship_ids()[0], sid)
	var j := FactionTraits.jumps_from(st.galaxy, sid)
	var far := -1
	var unexplored := -1
	for s in j:
		if int(j[s]) >= 4 and int(j[s]) <= 16:
			if Fleets.is_explored(st, 0, int(s)):
				far = int(s)
			else:
				unexplored = int(s)
	if unexplored >= 0:
		_ok(MegasWorld.check_launch(st, 0, id, f.id, unexplored).contains("inexplorée"), "destination inexplorée : refusée")
	if far < 0 and unexplored >= 0:
		e.explored[unexplored] = true
		far = unexplored
	if far < 0:
		_ok(true, "pas de destination lointaine (test sauté)")
		return
	var energy := int(e.resources["energy"])
	var why := T.cmd(st, 0, "launch", {"id": id, "f": f.id, "t": far})
	_ok(why == "", "flotte catapultée (%s)" % why)
	_ok(f.system_id == far or st.galaxy.systems[far].neighbors.has(f.system_id), "elle arrive au but, ou juste à côté")
	_ok(int(e.resources["energy"]) < energy, "le tir coûte de l'énergie")
	f.system_id = sid
	_ok(MegasWorld.check_launch(st, 0, id, f.id, far).contains("recharge"), "puis recharge")


func _test_weapons() -> void:
	var st := T.new_game()
	var sid := T.home_sys(st, 0)
	T.rich(st, 0)
	var foe := 1
	var bp := T.free_planet(st, sid, "barren")
	if bp < 0:
		_ok(true, "pas de planète libre pour le Brise-monde (test sauté)")
		return
	var id := T.build_full(st, 0, "brise_monde", sid, bp)
	var j := FactionTraits.jumps_from(st.galaxy, sid)
	var target := -1
	var capital := st.get_empire(foe).capital_planet
	for pid in st.sorted_colony_ids():
		var c: Colony = st.colonies[pid]
		if c.owner == foe and pid != capital and int(j.get(st.galaxy.get_planet(pid).system_id, 99)) <= 8:
			target = pid
			break
	if target < 0:
		# Une colonie ennemie à portée, pour le test.
		var near := int(st.galaxy.systems[sid].neighbors[0])
		for pid in st.galaxy.systems[near].planet_ids:
			if not st.colonies.has(pid):
				var c := Colony.new()
				c.planet_id = pid
				c.owner = foe
				c.population = 3
				st.add_colony(c)
				target = pid
				break
	if target < 0:
		_ok(true, "pas de cible (test sauté)")
		return
	_ok(MegasWorld.check_fire(st, 0, id, target).contains("guerre"), "Brise-monde : pas sur un empire en paix")
	st.get_empire(0).wars.append(foe)
	st.get_empire(foe).wars.append(0)
	if int(j.get(st.galaxy.get_planet(capital).system_id, 99)) <= 8:
		_ok(MegasWorld.check_fire(st, 0, id, capital).contains("capitale"), "une capitale résiste")
	var why := T.cmd(st, 0, "fire", {"id": id, "t": target})
	_ok(why == "", "Brise-monde : tir (%s)" % why)
	_ok(not st.colonies.has(target) and st.galaxy.get_planet(target).type == "asteroids", "la planète n'est plus qu'une ceinture de cailloux")
	var mem := false
	for x: Dictionary in st.memories:
		if String(x["kind"]) == "world_breaker" and int(x["about"]) == 0:
			mem = true
	_ok(mem, "toute la galaxie s'en souvient (souvenir « A brisé un monde »)")
	_ok(MegasWorld.check_fire(st, 0, id, target) != "", "puis cinq ans de recharge")
	# Point faible : une flotte ennemie qui tient le système 30 jours le fait sauter.
	for fid in st.sorted_fleet_ids():
		var f: Fleet = st.fleets[fid]
		if f.owner == 0 and f.system_id == sid:
			f.system_id = int(st.galaxy.systems[sid].neighbors[0])
	for sh in GameData.ship_ids():
		if Combat.is_armed_ship(sh):
			st.spawn_ship(foe, sh, sid)
			break
	var added: Array[Dictionary] = []
	for i in 31:
		MegasWorld.daily(st, added)
	_ok(Megastructures.get_m(st, id).is_empty(), "point faible : le Brise-monde saute")
	# Anneau d'extinction : seulement pendant une crise.
	var st2 := T.new_game()
	T.rich(st2, 0)
	var rid := T.build_full(st2, 0, "anneau_extinction", T.home_sys(st2, 0))
	_ok(T.cmd(st2, 0, "purge", {"id": rid}).contains("crise"), "Anneau d'extinction : seulement pendant une crise")
	var sa := T.new_game("sans_armes")
	T.rich(sa, 0)
	var sid2 := T.build_full(sa, 0, "anneau_extinction", T.home_sys(sa, 0))
	_ok(T.cmd(sa, 0, "purge", {"id": sid2}).contains("superarmes"), "Sans superarmes : rien à allumer")


func _test_events_talents() -> void:
	var st := T.new_game()
	var sid := T.home_sys(st, 0)
	Research.grant(st, 0, ["architectes_stellaires"])
	T.rich(st, 0)
	T.architect(st, 0, sid)
	T.cmd(st, 0, "plan", {"k": "ascenseur_orbital", "s": sid, "p": st.get_empire(0).capital_planet})
	var m: Dictionary = Megastructures.owned_by(st, 0)[0]
	m["w"] = 5000
	var events := 0
	var before := st.chronicle.size()
	for i in 120:
		st.tick += 30
		var a: Array[Dictionary] = []
		MegasWorld._event(st, m, a)
		events += a.size()
	_ok(events > 0 and events < 60, "événements de chantier, de temps en temps (%d en 120 mois)" % events)
	_ok(st.chronicle.size() > before, "racontés dans la chronique")
	# Murmurants : chantiers cachés.
	var mu := T.new_game("completes", "aucune", "murmurants")
	var meid := T.eid_of(mu, "murmurants")
	_ok(Megastructures._who(mu, meid, T.home_sys(mu, meid)) is Array and (Megastructures._who(mu, meid, T.home_sys(mu, meid)) as Array) == [meid], "Murmurants : chantiers cachés")
	# Teyl : Matriochka moins chère.
	var te := T.new_game("completes", "aucune", "teyl")
	var teid := T.eid_of(te, "teyl")
	_ok(Megastructures.cost_pct(te, teid, "matriochka") < 0, "Teyl : Cerveau Matriochka moins cher")


func _test_ai() -> void:
	var st := T.new_game()
	var ai := -1
	for e in st.empires:
		if e.is_ai():
			ai = e.id
			break
	if ai < 0:
		_ok(true, "pas d'IA (test sauté)")
		return
	Research.grant(st, ai, ["architectes_stellaires", "essaim_dyson", "forge_noyau", "anneau_orbital"])
	T.rich(st, ai)
	var sid := T.home_sys(st, ai)
	T.architect(st, ai, sid)
	for i in 3:
		st.tick += 30
		AiPlayer.think(st, st.get_empire(ai))
	_ok(not Megastructures.owned_by(st, ai).is_empty() or not Megastructures.sub(st, "plans").is_empty(), "IA : elle pose un chantier (%d)" % Megastructures.owned_by(st, ai).size())
	var never := true
	for m in Megastructures.owned_by(st, ai):
		if bool(Megastructures.kind_def(String(m["k"])).get("weapon", false)):
			never = false
	_ok(never, "IA : jamais de superarme")
