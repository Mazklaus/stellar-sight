class_name AiHeroes
extends RefCounted
## Héros des empires IA (voir Heroes) : choisir dans l'offre, puis donner un poste à chaque héros.
##
## Recrue : prend le premier candidat et place ses héros sans regarder leur classe (maladroit, mais
## jamais oisif). Normale et au-dessus : prend le candidat dont la classe sert le plus (en guerre, un
## Stratège), place chaque héros d'abord au poste de sa classe : Stratège sur la plus forte flotte de
## guerre sans amiral, Intendant sur le système le plus peuplé sans gouverneur, Orateur au conseil,
## Ombre sur le réseau le plus infiltré ; ce qui reste va au conseil, puis à un système.
## Une fois par mois, décalé selon l'empire.


static func think(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	# Une fenêtre de think_days jours par mois : l'IA ne réfléchit qu'un jour sur think_days.
	var every := maxi(1, int(ctx["lv"].get("think_days", 10)))
	if posmod(state.tick + e.id * 11, 30) >= mini(every, 30):
		return
	var skill := int(ctx["lv"].get("faction_use", 1))
	_pick(ctx, skill)
	_assign(ctx, skill)


static func _pick(ctx: Dictionary, skill: int) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var offer: Array = Heroes.meta(state, e.id)["offer"]
	if offer.is_empty():
		return
	if Heroes.ids_of(state, e.id).size() >= Heroes.cap(state, e.id):
		# Plus de place : renvoie le plus faible s'il est de niveau 1, sinon décline.
		var weakest := -1
		for id in Heroes.ids_of(state, e.id):
			if int(state.heroes[id]["lvl"]) == 1 and String(state.heroes[id]["post"]) == "":
				weakest = id
				break
		if weakest < 0 or skill == 0:
			AiPlayer._issue(ctx, SimCommands.hero_pick(e.id, -1))
			return
		AiPlayer._issue(ctx, SimCommands.hero_dismiss(e.id, weakest))
	var best := 0
	if skill > 0:
		var best_score := -1000
		for i in offer.size():
			var sc := _class_score(state, e, String(offer[i]["cls"]))
			if sc > best_score:
				best_score = sc
				best = i
	AiPlayer._issue(ctx, SimCommands.hero_pick(e.id, best))


## Ce qu'une classe apporte à l'empire en ce moment (plus c'est haut, mieux c'est).
static func _class_score(state: GameState, e: Empire, cls: String) -> int:
	var have := 0
	for id in Heroes.ids_of(state, e.id):
		if String(state.heroes[id]["cls"]) == cls:
			have += 1
	var s := 10 - have * 6
	match cls:
		"stratege":
			s += 12 if not e.wars.is_empty() else 0
		"intendant":
			s += 6
		"orateur":
			s += 4
		"ombre":
			s += 4 if Espionage.cells_used(state, e.id) > Espionage.home_cells(state, e.id) else -6
	return s


static func _assign(ctx: Dictionary, skill: int) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	for id in Heroes.ids_of(state, e.id):
		var h: Dictionary = state.heroes[id]
		if String(h["post"]) != "" or Heroes.is_wounded(state, h):
			continue
		var tries: Array = []
		var own := String(Heroes.class_def(String(h["cls"])).get("post", "council"))
		if skill == 0:
			tries = ["system", "fleet", "council"]
		else:
			tries = [own, "council", "system", "fleet"]
		for post in tries:
			var target := _target(state, e, String(post))
			if target >= 0 and AiPlayer._issue(ctx, SimCommands.hero_assign(e.id, id, String(post), target)):
				break


## Meilleure cible libre pour un poste, -1 s'il n'y en a pas.
static func _target(state: GameState, e: Empire, post: String) -> int:
	match post:
		"fleet":
			var best := -1
			var power := 0
			for fid in state.sorted_fleet_ids():
				var f: Fleet = state.fleets[fid]
				if f.owner != e.id or not Combat.is_warfleet(f) or not Heroes.assigned_to(state, "fleet", f.id, e.id).is_empty():
					continue
				var p := Combat.fleet_power(f)
				if p > power:
					power = p
					best = f.id
			return best
		"system":
			var pops := {}
			for pid in state.sorted_colony_ids():
				var c: Colony = state.colonies[pid]
				if c.owner == e.id and c.is_colony():
					var sid := state.galaxy.get_planet(pid).system_id
					pops[sid] = int(pops.get(sid, 0)) + c.population
			var best := -1
			var most := 0
			var ks := pops.keys()
			ks.sort()
			for sid in ks:
				if int(pops[sid]) > most and Heroes.assigned_to(state, "system", int(sid), e.id).is_empty():
					most = int(pops[sid])
					best = int(sid)
			return best
		"council":
			for seat in Heroes.seats(state, e.id):
				if Heroes.assigned_to(state, "council", seat, e.id).is_empty():
					return seat
			return -1
		"agent":
			var best := -1
			var inf := -1
			for o in e.contacts:
				if Espionage.cells_on(state, e.id, o) > 0 and Heroes.assigned_to(state, "agent", o, e.id).is_empty():
					var i := Espionage.infiltration(state, e.id, o)
					if i > inf:
						inf = i
						best = o
			return best
	return -1
