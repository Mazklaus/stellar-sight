class_name AiCourt
extends RefCounted
## Cour des empires IA (étude « La cour et les familles nobles », prop. 36) : grands offices et postes
## mineurs pourvus (la meilleure aptitude, avec un faible pour les maisons fâchées), présents et
## intercession pour les maisons qui grondent, leviers utilisés avant une Fronde, pacification des fiefs
## en Fronde, mariage avec la maison la plus puissante, grande fête et train de cour quand le trésor le
## permet. Les cartes (choix des maisons, ultimatum, étoile montante, vaincus, événements) passent par
## AiEvents.

static func think(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if state.court.is_empty() or not Court.applies(state, e.id):
		return
	# Un passage par mois environ, quel que soit le rythme de réflexion du niveau (think_days).
	var every := maxi(1, int(ctx["lv"].get("think_days", 10)))
	if posmod(state.tick + e.id * 7, 30) >= mini(every, 30):
		return
	_offices(ctx, state, e)
	_minor(ctx, state, e)
	_soothe(ctx, state, e)
	_luxury(ctx, state, e)
	if posmod(state.tick + e.id * 13, 360) < 30 + every:
		_wed(ctx, state, e)


static func _try(ctx: Dictionary, state: GameState, e: Empire, act: String, x := -1, y := -1, s := "") -> bool:
	if Court.check_act(state, e.id, act, x, y, s) != "":
		return false
	AiPlayer._issue(ctx, SimCommands.court_act(e.id, act, x, y, s))
	return true


## Grands offices vacants : le meilleur courtisan pour l'aptitude, les maisons fâchées d'abord à talent égal.
static func _offices(ctx: Dictionary, state: GameState, e: Empire) -> void:
	var taken := {}
	var en := Court.entry(state, e.id)
	for k in (en["offices"] as Dictionary):
		taken[int(en["offices"][k]["id"])] = true
	for oid in Court.office_ids(state, e.id):
		if not Court.holder(state, e.id, oid).is_empty():
			continue
		var apt := String(Court.office_def(oid).get("apt", "gestion"))
		var best := -1
		var bv := -100000
		for h: Dictionary in Court.houses(state, e.id):
			for m: Dictionary in h["members"]:
				if taken.has(int(m["id"])):
					continue
				@warning_ignore("integer_division")
				var v := int(Court.apts(m)[apt]) * 10 - Court.favor(h) / 5
				if v > bv:
					bv = v
					best = int(m["id"])
		if best >= 0 and _try(ctx, state, e, "appoint", best, 0, oid):
			taken[best] = true
			return  # un ordre par bilan suffit


static func _minor(ctx: Dictionary, state: GameState, e: Empire) -> void:
	var en := Court.entry(state, e.id)
	var used := {}
	for k in (en["minor"] as Dictionary):
		used[int(en["minor"][k])] = true
	for k in (en["offices"] as Dictionary):
		if String(en["offices"][k]["k"]) == "m":
			used[int(en["offices"][k]["id"])] = true
	for p: Dictionary in Court.data()["minor_posts"]:
		var pid := String(p["id"])
		if int((en["minor"] as Dictionary).get(pid, -1)) >= 0 and not Court.member(state, e.id, int(en["minor"][pid])).is_empty():
			continue
		var best := -1
		var bv := 0
		for h: Dictionary in Court.houses(state, e.id):
			for m: Dictionary in h["members"]:
				var v := int(Court.apts(m)[String(p["apt"])])
				if not used.has(int(m["id"])) and v > bv:
					bv = v
					best = int(m["id"])
		if best >= 0 and _try(ctx, state, e, "minor", best, -1, pid):
			return


## Maisons qui grondent : levier, présent, intercession, pacification des fiefs en Fronde, secret.
static func _soothe(ctx: Dictionary, state: GameState, e: Empire) -> void:
	var en := Court.entry(state, e.id)
	var worst: Dictionary = {}
	for h: Dictionary in Court.houses(state, e.id):
		if worst.is_empty() or Court.favor(h) < Court.favor(worst):
			worst = h
	if worst.is_empty():
		return
	var wid := int(worst["id"])
	if (en["fronde"] as Dictionary).has(str(wid)):
		for sid in Court.fiefs_of(state, e.id, wid):
			if _try(ctx, state, e, "pacify", sid):
				return
	if Court.favor(worst) > -30:
		return
	if Court.favor(worst) <= Court.r_int("fronde_fav") + 10 and _try(ctx, state, e, "lever", wid):
		return
	if _try(ctx, state, e, "gift", wid):
		return
	var best := Court.strongest_house(state, e.id)
	if not best.is_empty() and _try(ctx, state, e, "intercede", wid, int(best["id"])):
		return
	_try(ctx, state, e, "secret", wid)


## Grande fête et train de cour quand le trésor déborde ; train rangé quand il se vide.
static func _luxury(ctx: Dictionary, state: GameState, e: Empire) -> void:
	var en_res := int(e.resources.get("energy", 0))
	var en := Court.entry(state, e.id)
	if en_res > 1200 and int(e.resources.get("influence", 0)) > 200 and int(en["faste"]) < 50 and _try(ctx, state, e, "fete"):
		return
	var lvl := int((en["train"] as Dictionary).get("table", 0))
	if en_res > 900 and lvl < 2:
		_try(ctx, state, e, "train", lvl + 1, -1, "table")
	elif en_res < 200 and lvl > 0:
		_try(ctx, state, e, "train", 0, -1, "table")


static func _wed(ctx: Dictionary, state: GameState, e: Empire) -> void:
	for h: Dictionary in Court.houses(state, e.id):
		if int(h.get("kin", 0)) == 1:
			return
	var best := Court.strongest_house(state, e.id)
	var most := -1
	var target := -1
	for h: Dictionary in Court.houses(state, e.id):
		var n := Court.fiefs_of(state, e.id, int(h["id"])).size()
		if n > most:
			most = n
			target = int(h["id"])
	if target < 0 and not best.is_empty():
		target = int(best["id"])
	if target >= 0:
		_try(ctx, state, e, "wed", target)
