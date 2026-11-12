class_name CombatSystem
extends RefCounted
## Combats, sièges et réparations, exécutés à chaque tick après les déplacements, dans un ordre fixe :
## 1. batailles : dans chaque système où se trouvent à l'arrêt des flottes d'empires en guerre
##    (dont au moins une armée), un jour de bataille. Une bataille dure 6 jours : 2 à longue portée,
##    2 à moyenne, 2 à courte, puis un rapport ; si les deux camps sont encore là, une autre commence ;
## 2. sièges : un système ennemi sans flotte armée pour le défendre est assiégé par les flottes armées
##    qui y stationnent ; sa garnison fond, ses bastions tirent, sa production est réduite ;
## 3. réparations et troupes : les flottes hors combat se réparent (vite chez elles, lentement ailleurs)
##    et refont leurs troupes dans leurs propres systèmes ;
## 4. empires disparus : un empire sans revendication disparaît, et ses flottes avec lui.
##
## Les tirs sont simultanés (les dégâts d'un jour s'appliquent ensemble). Les cibles sont tirées par
## state.rng, dans l'ordre des identifiants : la même partie sur toutes les machines.
## Une flotte peut quitter une bataille : l'ordre s'applique avant les déplacements du jour suivant,
## elle est partie avant que la bataille reprenne (pas de contrôle pendant la bataille elle-même,
## comme dans Endless Space 2).


## events reçoit les événements pour l'interface : {"type": "battle_started", "system", "empires", "renewed"},
## {"type": "battle_ended", "report"}, {"type": "siege_started", "system", "by", "owner"}.
static func process(state: GameState, events: Array = []) -> Array[Dictionary]:
	var added: Array[Dictionary] = []
	var by_sys := _stationary_by_system(state)
	var fought := {}
	var sids := by_sys.keys()
	sids.sort()
	for sid in sids:
		if _in_conflict(state, by_sys[sid]):
			fought[sid] = true
			_battle_day(state, int(sid), by_sys[sid], added, events)
	# Batailles terminées faute de combattants (fuite, destruction, flotte partie).
	var bids := state.battles.keys()
	bids.sort()
	for sid in bids:
		if not fought.has(sid):
			_end_battle(state, int(sid), added, events)
	_sieges(state, fought, added, events)
	_repairs(state, fought)
	_eliminations(state, added)
	_hunger(state, added)
	return added


## La faim de l'Essaim : une fois par mois, un Essaim sans guerre (proie digérée ou disparue) se
## choisit une nouvelle proie, l'empire rencontré le plus proche.
static func _hunger(state: GameState, added: Array[Dictionary]) -> void:
	if state.tick % 30 != 0:
		return
	for e in state.empires:
		if e.eliminated or not Combat.hunts(state, e.id) or Combat.has_live_war(state, e.id):
			continue
		var prey := Combat.nearest_prey(state, e.id)
		if prey < 0:
			continue
		Combat.start_war(state, e.id, prey, true, true)
		added.append(state.add_chronicle("%s a fini de digérer. Il flaire %s, et se met en chasse : c'est la guerre." % [
				e.display_name(), state.get_empire(prey).display_name()], Espionage.public_to(state, [e.id, prey])))


static func _stationary_by_system(state: GameState) -> Dictionary:
	var out := {}
	for fid in state.sorted_fleet_ids():
		var f: Fleet = state.fleets[fid]
		if f.is_moving():
			continue
		if not out.has(f.system_id):
			out[f.system_id] = []
		out[f.system_id].append(f)
	return out


## Deux flottes d'empires en guerre, dont au moins une armée.
static func _in_conflict(state: GameState, fleets: Array) -> bool:
	for a: Fleet in fleets:
		if not Combat.is_armed(a):
			continue
		for b: Fleet in fleets:
			if Combat.at_war(state, a.owner, b.owner):
				return true
	return false


# --- Batailles ---------------------------------------------------------------------------------

static func _new_battle(state: GameState, sid: int) -> Dictionary:
	var b := {"id": state.next_battle_id, "system": sid, "start": state.tick, "day": 0,
			"fleets": [], "sides": [], "units": [], "slots": [], "log": []}
	state.next_battle_id += 1
	state.battles[sid] = b
	return b


static func _side(b: Dictionary, empire_id: int) -> Dictionary:
	for s: Dictionary in b["sides"]:
		if int(s["empire"]) == empire_id:
			return s
	var s := {"empire": empire_id, "engaged": {}, "lost": {}, "dealt": 0}
	b["sides"].append(s)
	b["sides"].sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return int(x["empire"]) < int(y["empire"]))
	return s


## Jour d'arrivée d'une flotte dans la bataille (0 si elle n'y est pas encore).
static func _joined_day(b: Dictionary, fid: int) -> int:
	for e: Array in b["fleets"]:
		if int(e[0]) == fid:
			return int(e[1])
	return 0


static func _battle_day(state: GameState, sid: int, fleets: Array, added: Array[Dictionary], events: Array) -> void:
	var b: Dictionary = state.battles.get(sid, {})
	var fresh := b.is_empty()
	if fresh:
		b = _new_battle(state, sid)
	b["day"] = int(b["day"]) + 1
	var day := int(b["day"])
	var phase := Combat.phase_index(day)
	# Combattants : les flottes dont l'empire est en guerre avec un autre présent.
	var fighters: Array[Fleet] = []
	for f: Fleet in fleets:
		for g: Fleet in fleets:
			if Combat.at_war(state, f.owner, g.owner):
				fighters.append(f)
				break
	for f in fighters:
		if _joined_day(b, f.id) == 0:
			b["fleets"].append([f.id, day])
			var side := _side(b, f.owner)
			for s in f.ships:
				side["engaged"][s] = int(side["engaged"].get(s, 0)) + 1
	_sync_units(b, fighters)
	var day_log := {"day": day, "phase": phase, "shots": [], "kills": []}
	if fresh:
		var names := PackedStringArray()
		var ids: Array[int] = []
		for s: Dictionary in b["sides"]:
			ids.append(int(s["empire"]))
			names.append(state.get_empire(int(s["empire"])).display_name())
		# Une bataille qui reprend aussitôt après la précédente (les deux camps sont restés) n'est pas annoncée.
		var renewed := false
		for r: Dictionary in state.battle_reports:
			if int(r["system"]) == sid and int(r["end"]) >= state.tick - 1:
				renewed = true
		if not renewed:
			added.append(state.add_chronicle("Bataille à %s : %s ouvrent le feu. Les chroniqueurs taillent leurs crayons." % [
					state.galaxy.systems[sid].system_name, " et ".join(names)], Espionage.private_to(state, ids, sid)))
		events.append({"type": "battle_started", "system": sid, "empires": ids, "renewed": renewed})
	# Cibles possibles de chaque empire : les vaisseaux ennemis présents, chacun avec un poids selon
	# son rang (écran 3, ligne 2, arrière 0 : l'arrière n'est visé que quand le front est tombé).
	# Les chasseurs ignorent les rangs (poids 1 partout). Deux listes cumulées par empire.
	var targets := {}
	var raw := {}
	for f in fighters:
		if raw.has(f.owner):
			continue
		var list: Array = []
		var front := 0
		for g in fighters:
			if Combat.at_war(state, f.owner, g.owner):
				for i in g.ships.size():
					var wgt := Combat.line_weight(Combat.ship_line(g.ships[i]))
					list.append([g, i, wgt])
					front += wgt
		raw[f.owner] = [list, front]
		targets[f.owner] = {"nearest": {"lined": _cumulate(list, front == 0), "any": _cumulate(list, true)}}
	# Tirs simultanés : on cumule, puis on applique.
	var pending := {}
	var martyrs: Array = []
	for f in fighters:
		if targets[f.owner]["nearest"]["any"][1] <= 0:
			continue
		var tac := Combat.fleet_tactic(f)
		var bonus := _damage_bonus(state, b, f, sid)
		# Doctrines : portée préférée, premier jour (guerre éclair), frappe en profondeur.
		var pfx: Dictionary = Research.effects(state, f.owner).get("phase_damage_pct", {})
		var dpct := int(pfx.get(String(Combat.data()["phases"][phase]["id"]), 0))
		if day == 1:
			dpct += Research.fx_int(state, f.owner, "first_day_damage_pct")
		dpct += Heroes.damage_pct(state, f, day, state.system_owner(sid) == f.owner)
		dpct += Pirates.hunt_pct(state, f, fighters)
		if dpct != 0:
			@warning_ignore("integer_division")
			bonus = bonus * maxi(0, 100 + dpct) / 100
		var deep := Research.fx_int(state, f.owner, "deep_strike_pct")
		var side := _side(b, f.owner)
		for i in f.ships.size():
			var w := Combat.weapons(f.ships[i])
			var my_marks := Combat.ship_marks(state, f, i)
			# Priorité de cible du modèle (éditeur de vaisseaux) : elle pondère les cibles possibles.
			var prio := String(GameData.ship(f.ships[i]).get("target", "nearest"))
			if not targets[f.owner].has(prio):
				var r: Array = raw[f.owner]
				targets[f.owner][prio] = {"lined": _cumulate(r[0], int(r[1]) == 0, prio), "any": _cumulate(r[0], true, prio)}
			var lists: Dictionary = targets[f.owner][prio]
			var keys := w.keys()
			keys.sort()
			for k in keys:
				var wd: Dictionary = Combat.data()["weapons"].get(k, {})
				if Combat.weapon_eff(String(k), phase) <= 0:
					continue
				var any: bool = wd.get("ignores_lines", false)
				if not any and deep > 0 and state.rng.randi_range(0, 99) < deep:
					any = true
				var cum: Array = lists["any"] if any else lists["lined"]
				var pick: Array = _pick(cum, state.rng.randi_range(0, int(cum[1]) - 1))
				var tg: Fleet = pick[0]
				var ti: int = pick[1]
				@warning_ignore("integer_division")
				var wbonus := bonus * (100 + Combat.weapon_bonus(state, f.owner, String(k), my_marks)) / 100
				var dmg := Combat.shot_damage(String(k), int(w[k]), phase, tac, wbonus, tg.ships[ti], Combat.fleet_tactic(tg),
						Combat.fleet_pd(tg), Combat.defense_bonus(state, tg.owner, Combat.ship_marks(state, tg, ti)), Combat.fleet_shield(tg))
				var screen := Research.fx_int(state, tg.owner, "screen_taken_pct")
				if screen != 0 and Combat.ship_line(tg.ships[ti]) == "screen":
					@warning_ignore("integer_division")
					dmg = maxi(1, dmg * maxi(0, 100 + screen) / 100)  # rideau d'acier
				var key := Vector2i(tg.id, ti)
				pending[key] = int(pending.get(key, 0)) + dmg
				side["dealt"] = int(side["dealt"]) + dmg
				day_log["shots"].append([_unit(b, f.id, i), _unit(b, tg.id, ti), String(k), dmg])
				if wd.get("self_destruct", false):
					martyrs.append([f, i, int(wd.get("fervor", 0))])
	# Les martyrs disparaissent dans leur charge (après les tirs du jour, qui sont simultanés).
	for m in martyrs:
		var mf: Fleet = m[0]
		var key := Vector2i(mf.id, int(m[1]))
		pending[key] = int(pending.get(key, 0)) + Fleet.max_hp_of(mf.ships[int(m[1])]) * 10
		var e := state.get_empire(mf.owner)
		if int(m[2]) > 0 and e.faction().has("fervor"):
			e.fervor = mini(int(e.faction()["fervor"]["max"]), e.fervor + int(m[2]))
	_apply_damage(state, b, fighters, pending, day_log)
	b["log"].append(day_log)
	if day >= Combat.battle_days():
		_end_battle(state, sid, added, events)


# --- Journal de bataille (pour la vue qui rejoue la bataille) -----------------------------------
# "units" : un vaisseau engagé par entrée, [empire, classe, rang, jour d'arrivée] ; son indice sert
# d'identifiant stable. "slots" : [[flotte, [unités alignées sur ses vaisseaux]]...], tenu à jour.
# "log" : un jour par entrée, {day, phase, shots: [[tireur, cible, arme, dégâts]...], kills: [unités]}.
# Rien de tout cela n'influence la bataille : c'est un enregistrement.

static func _slots_of(b: Dictionary, fid: int) -> Array:
	for pair: Array in b["slots"]:
		if int(pair[0]) == fid:
			return pair[1]
	var fresh: Array = []
	b["slots"].append([fid, fresh])
	return fresh


## Aligne les unités du journal sur les vaisseaux de chaque flotte (nouvelle flotte, renforts fusionnés).
static func _sync_units(b: Dictionary, fighters: Array[Fleet]) -> void:
	for f in fighters:
		var slots := _slots_of(b, f.id)
		var units: Array = b["units"]
		var aligned := slots.size() == f.ships.size()
		if aligned:
			for i in slots.size():
				if String(units[int(slots[i])][1]) != f.ships[i]:
					aligned = false
					break
		if aligned:
			continue
		# Réalignement : on garde les unités déjà connues de la même classe, dans l'ordre.
		var pool := {}
		for u in slots:
			var cls := String(units[int(u)][1])
			if not pool.has(cls):
				pool[cls] = []
			pool[cls].append(int(u))
		slots.clear()
		for sh in f.ships:
			if pool.has(sh) and not pool[sh].is_empty():
				slots.append(pool[sh].pop_front())
			else:
				units.append([f.owner, sh, Combat.ship_line(sh), int(b["day"])])
				slots.append(units.size() - 1)


static func _unit(b: Dictionary, fid: int, i: int) -> int:
	var slots := _slots_of(b, fid)
	return int(slots[i]) if i < slots.size() else -1


static func _drop_unit(b: Dictionary, fid: int, i: int) -> void:
	var slots := _slots_of(b, fid)
	if i < slots.size():
		slots.remove_at(i)


## Liste de cibles [[flotte, indice, poids]...] en tableau cumulé [entrées, total] : `flat` donne le
## même poids (1) à toutes, sinon chaque cible garde le poids de son rang.
## prio (priorité de cible du tireur) multiplie ces poids : « les plus gros » (x1 à x6 selon la taille),
## « les plus petits » (l'inverse), « porteurs et arrière » (x4 pour l'arrière et les porteurs) ;
## une cible de poids nul (l'arrière, tant que le front tient) le reste.
static func _cumulate(list: Array, flat: bool, prio := "nearest") -> Array:
	var out: Array = []
	var total := 0
	for t in list:
		var wgt := 1 if flat else int(t[2])
		if wgt <= 0:
			continue
		if prio != "nearest":
			wgt *= _prio_weight(prio, (t[0] as Fleet).ships[int(t[1])])
		total += wgt
		out.append([t[0], t[1], total])
	return [out, total]


const PRIO_SIZES := {"largest": {"small": 1, "medium": 2, "large": 4, "titan": 6}, "smallest": {"small": 4, "medium": 2, "large": 1, "titan": 1}}


static func _prio_weight(prio: String, ship_id: String) -> int:
	if PRIO_SIZES.has(prio):
		return int(PRIO_SIZES[prio].get(Combat.ship_size(ship_id), 1))
	if prio == "rear":
		var sd := GameData.ship(ship_id)
		return 4 if Combat.ship_line(ship_id) == "rear" or sd.get("weapons", {}).has("fighters") else 1
	return 1


## Cible tirée : la première entrée dont le cumul dépasse `roll` (0 ≤ roll < total).
static func _pick(cum: Array, roll: int) -> Array:
	var entries: Array = cum[0]
	var lo := 0
	var hi := entries.size() - 1
	while lo < hi:
		@warning_ignore("integer_division")
		var mid := (lo + hi) / 2
		if int(entries[mid][2]) > roll:
			hi = mid
		else:
			lo = mid + 1
	return entries[lo]


## Bonus de dégâts des traits de peuple (en %) : bonus général, Ossarane chez elle, Vael arrivée en renfort.
static func _damage_bonus(state: GameState, b: Dictionary, f: Fleet, sid: int) -> int:
	# Bonus général du peuple (trait Canonniers, défaut Piètres soldats des peuples créés).
	var pct := int(Combat.trait_value(state, f.owner, "damage_pct", 100))
	if state.system_owner(sid) == f.owner:
		@warning_ignore("integer_division")
		pct = pct * (int(Combat.trait_value(state, f.owner, "home_damage_pct", 100)) + Research.fx_int(state, f.owner, "home_damage_pct")) / 100
	if _joined_day(b, f.id) > 1:
		var rp := int(Combat.trait_value(state, f.owner, "reinforcement_pct", 100))
		var rt := Research.fx_int(state, f.owner, "reinforcement_pct")
		if rp != 100 or rt != 0:
			@warning_ignore("integer_division")
			pct = pct * (rp + rt) / 100
	return pct


static func _apply_damage(state: GameState, b: Dictionary, fighters: Array[Fleet], pending: Dictionary, day_log := {}) -> void:
	for f in fighters:
		var lost_any := false
		for i in range(f.ships.size() - 1, -1, -1):
			var dmg := int(pending.get(Vector2i(f.id, i), 0))
			if dmg <= 0:
				continue
			f.hp[i] -= dmg
			if f.hp[i] <= 0:
				var side := _side(b, f.owner)
				side["lost"][f.ships[i]] = int(side["lost"].get(f.ships[i], 0)) + 1
				_credit_kill(state, b, f.owner)
				if day_log.has("kills"):
					day_log["kills"].append(_unit(b, f.id, i))
				_drop_unit(b, f.id, i)
				f.remove_at(i)
				lost_any = true
		if lost_any:
			f.troops = mini(f.troops, Combat.max_troops(f, state))
		if f.ships.is_empty():
			state.fleets.erase(f.id)


## Croisade du Chœur : chaque vaisseau détruit nourrit le dieu-machine des empires qui le combattaient.
static func _credit_kill(state: GameState, b: Dictionary, victim: int) -> void:
	Research.count_stat(state, victim, "ships_lost")
	for s: Dictionary in b["sides"]:
		var eid := int(s["empire"])
		if not Combat.at_war(state, eid, victim):
			continue
		var e := state.get_empire(eid)
		Research.count_stat(state, eid, "kills")
		var gain := int(Combat.trait_value(state, eid, "fervor_per_kill", 0))
		if gain > 0:
			e.fervor = mini(int(e.faction()["fervor"]["max"]), e.fervor + gain)
		# Reliques saintes du Chœur, mémoire génétique de l'Essaim : on apprend des épaves.
		var know := int(e.faction().get("research", {}).get("knowledge_per_kill", 0))
		if know > 0:
			e.resources["knowledge"] = int(e.resources.get("knowledge", 0)) + know


## Fin d'une bataille : rapport, chronicle, événement. Le vainqueur est le seul camp encore présent.
static func _end_battle(state: GameState, sid: int, added: Array[Dictionary], events: Array) -> void:
	var b: Dictionary = state.battles.get(sid, {})
	if b.is_empty():
		return
	state.battles.erase(sid)
	var present := {}
	for f in Fleets.fleets_at(state, sid):
		present[f.owner] = true
	var standing: Array[int] = []
	for s: Dictionary in b["sides"]:
		if present.has(int(s["empire"])):
			standing.append(int(s["empire"]))
	var winner := standing[0] if standing.size() == 1 else -1
	var report := b.duplicate(true)
	report["end"] = state.tick
	report["winner"] = winner
	report["system_name"] = state.galaxy.systems[sid].system_name
	report.erase("slots")
	state.battle_reports.append(report)
	var keep := int(Combat.data().get("reports_max", 12))
	while state.battle_reports.size() > keep:
		state.battle_reports.pop_front()
	# Score de guerre : la puissance détruite de chaque camp revient à ceux qui le combattaient.
	for s: Dictionary in b["sides"]:
		var pts := 0
		for ship in s["lost"]:
			pts += Combat.ship_strength(String(ship)) * int(s["lost"][ship])
		for o: Dictionary in b["sides"]:
			Diplomacy.add_war_score(state, int(o["empire"]), int(s["empire"]), pts)
	Reputation.battle(state, b, winner)
	Heroes.on_battle(state, b, winner)
	Relics.on_battle(state, b, winner, added)
	# Épaves : le vainqueur étudie les armes et les doctrines des vaincus.
	if winner >= 0:
		Research.count_stat(state, winner, "battles_won")
		var studied := PackedStringArray()
		var found := PackedStringArray()
		for s: Dictionary in b["sides"]:
			var loser := int(s["empire"])
			if loser == winner or not Combat.at_war(state, winner, loser) or Combat.count_ships(s["engaged"]) == 0:
				continue
			for r in Research.study_wrecks(state, winner, loser):
				var lbl := String(Research.tech(String(r[0])).get("label", r[0]))
				if bool(r[2]):
					found.append(lbl)
				elif not studied.has(lbl):
					studied.append(lbl)
		report["wrecks"] = Array(studied) + Array(found)
		_trophies(state, b, winner, report)
		var we := state.get_empire(winner)
		if not we.is_ai() and not found.is_empty():
			added.append(state.add_chronicle("Les épaves de %s livrent leurs secrets : %s découvre %s." % [
					state.galaxy.systems[sid].system_name, we.short_name(), ", ".join(found)], Espionage.private_to(state, [winner], sid)))
	var losses := PackedStringArray()
	for s: Dictionary in b["sides"]:
		losses.append("%s %d" % [state.get_empire(int(s["empire"])).short_name(), Combat.count_ships(s["lost"])])
	var sname := state.galaxy.systems[sid].system_name
	if winner >= 0:
		added.append(state.add_chronicle("Bataille de %s : victoire de %s. Pertes : %s. Les vainqueurs comptent leurs morts, les vaincus leurs excuses." % [
				sname, state.get_empire(winner).display_name(), ", ".join(losses)], Espionage.private_to(state, Espionage.battle_sides(b), sid)))
	else:
		added.append(state.add_chronicle("Bataille de %s : rien n'est décidé après %d jours de feu. Pertes : %s." % [
				sname, int(b["day"]), ", ".join(losses)], Espionage.private_to(state, Espionage.battle_sides(b), sid)))
	events.append({"type": "battle_ended", "report": report})


# --- Sièges ------------------------------------------------------------------------------------

static func _sieges(state: GameState, fought: Dictionary, added: Array[Dictionary], events: Array) -> void:
	var gcfg: Dictionary = Combat.data()["garrison"]
	# Systèmes à examiner : ceux qui ont une garnison entamée, un siège en cours, ou des flottes.
	var check := {}
	for k in state.garrisons:
		check[k] = true
	for k in state.sieges:
		check[k] = true
	for fid in state.sorted_fleet_ids():
		var f: Fleet = state.fleets[fid]
		if not f.is_moving():
			check[f.system_id] = true
	var ids := check.keys()
	ids.sort()
	for k in ids:
		var sid := int(k)
		var owner := state.system_owner(sid)
		if owner < 0:
			state.garrisons.erase(sid)
			state.sieges.erase(sid)
			continue
		var by: Array[Fleet] = []
		if not fought.has(sid):
			by = Combat.besiegers(state, sid)
		if by.is_empty():
			if state.sieges.has(sid):
				state.sieges.erase(sid)
				if not fought.has(sid):
					added.append(state.add_chronicle("Le siège de %s est levé. On rouvre les volets, on recompte les provisions." % state.galaxy.systems[sid].system_name, Espionage.private_to(state, [owner], sid)))
			if state.garrisons.has(sid):
				var g := int(state.garrisons[sid]) + int(gcfg["regen_per_day"])
				if g >= Combat.garrison_max(state, sid):
					state.garrisons.erase(sid)
				else:
					state.garrisons[sid] = g
			continue
		var lead: Fleet = by[0]
		if not state.sieges.has(sid):
			state.sieges[sid] = {"system": sid, "by": lead.owner, "start": state.tick}
			added.append(state.add_chronicle("%s met le siège devant %s. La garnison serre les dents, la population les rations." % [
					state.get_empire(lead.owner).display_name(), state.galaxy.systems[sid].system_name], Espionage.private_to(state, [lead.owner, owner], sid)))
			events.append({"type": "siege_started", "system": sid, "by": lead.owner, "owner": owner})
			Research.count_stat(state, owner, "besieged")
		var before := Combat.garrison(state, sid)
		# Les bastions tirent tant que la garnison tient.
		if before > 0:
			_battery_fire(state, sid, by)
		var power := 0
		for f: Fleet in by:
			if state.fleets.has(f.id):
				power += Combat.siege_power(f, state)
		state.garrisons[sid] = maxi(0, before - power)


## Les batteries des bastions tirent à moyenne portée sur les assiégeants.
static func _battery_fire(state: GameState, sid: int, by: Array[Fleet]) -> void:
	var bat := Combat.battery(state, sid)
	if bat.is_empty():
		return
	var owner := state.system_owner(sid)
	var list: Array = []
	for f: Fleet in by:
		for i in f.ships.size():
			list.append([f, i])
	var pending := {}
	var keys := bat.keys()
	keys.sort()
	for k in keys:
		var pick: Array = list[state.rng.randi_range(0, list.size() - 1)]
		var tg: Fleet = pick[0]
		@warning_ignore("integer_division")
		var bb := (int(Combat.trait_value(state, owner, "home_damage_pct", 100)) + Research.fx_int(state, owner, "home_damage_pct")) \
				* (100 + Combat.weapon_bonus(state, owner, String(k))) / 100
		var dmg := Combat.shot_damage(String(k), int(bat[k]), 1, Combat.default_tactic(), bb, tg.ships[pick[1]],
				Combat.fleet_tactic(tg), 0, Combat.defense_bonus(state, tg.owner, Combat.ship_marks(state, tg, int(pick[1]))))
		var key := Vector2i(tg.id, int(pick[1]))
		pending[key] = int(pending.get(key, 0)) + dmg
	for f: Fleet in by:
		for i in range(f.ships.size() - 1, -1, -1):
			var dmg := int(pending.get(Vector2i(f.id, i), 0))
			if dmg > 0:
				f.hp[i] -= dmg
				if f.hp[i] <= 0:
					f.remove_at(i)
		f.troops = mini(f.troops, Combat.max_troops(f, state))
		if f.ships.is_empty():
			state.fleets.erase(f.id)


## Méga-modules de peuple du vainqueur : le reliquaire nourrit la ferveur, le ventre digesteur change
## les épaves ennemies en matériaux (un quart de ce qu'elles avaient coûté).
static func _trophies(state: GameState, b: Dictionary, winner: int, report: Dictionary) -> void:
	var relic := false
	var digest := false
	for s: Dictionary in b["sides"]:
		if int(s["empire"]) == winner:
			for ship in s["engaged"]:
				var sd := GameData.ship(String(ship))
				relic = relic or bool(sd.get("reliquary", false))
				digest = digest or bool(sd.get("digester", false))
	if not relic and not digest:
		return
	var e := state.get_empire(winner)
	if relic and FactionTraits.has_fervor(e.faction()):
		e.fervor = mini(int(e.faction()["fervor"]["max"]), e.fervor + int(Combat.data().get("reliquary_fervor", 10)))
		report["relic"] = true
	if digest:
		var mats := 0
		for s: Dictionary in b["sides"]:
			if int(s["empire"]) != winner and Combat.at_war(state, winner, int(s["empire"])):
				for ship in s["lost"]:
					mats += int(GameData.ship(String(ship)).get("cost", {}).get("materials", 0)) * int(s["lost"][ship])
		@warning_ignore("integer_division")
		var gain := mats * int(Combat.data().get("digester_pct", 25)) / 100
		if gain > 0:
			e.resources["materials"] = int(e.resources.get("materials", 0)) + gain
			report["digested"] = gain


# --- Réparations et troupes --------------------------------------------------------------------

static func _repairs(state: GameState, fought: Dictionary) -> void:
	var home := int(Combat.data()["repair_pct_home"])
	var away := int(Combat.data()["repair_pct_away"])
	var regen := int(Combat.data()["troops_regen_pct"])
	for fid in state.sorted_fleet_ids():
		var f: Fleet = state.fleets[fid]
		var sid := f.system_id
		if not f.is_moving() and (fought.has(sid) or state.sieges.has(sid) and state.system_owner(sid) != f.owner):
			continue  # en pleine bataille ou en plein siège
		var at_home := not f.is_moving() and state.system_owner(sid) == f.owner
		var damaged := false
		for i in f.ships.size():
			if f.hp[i] < Fleet.max_hp_of(f.ships[i]):
				damaged = true
				break
		if damaged:
			# Forge mobile (Léviathan) : la flotte se répare partout comme chez elle.
			var anywhere := at_home or bool(Combat.trait_value(state, f.owner, "repair_anywhere", false)) or Combat._fleet_has_flag(f, "fleet_repair")
			var pct := home if anywhere else away
			pct = Research.scaled(pct, Research.fx_int(state, f.owner, "repair_pct"))  # guerre d'usure
			for i in f.ships.size():
				var mx := Fleet.max_hp_of(f.ships[i])
				if f.hp[i] < mx:
					@warning_ignore("integer_division")
					f.hp[i] = mini(mx, f.hp[i] + maxi(1, mx * pct / 100))
		var tmax := Combat.max_troops(f, state)
		# Cité de bord (Nef-monde) : les troupes se reforment même loin de chez elles.
		if f.troops < tmax and (at_home or Combat._fleet_has_flag(f, "fleet_barracks")):
			@warning_ignore("integer_division")
			f.troops = mini(tmax, f.troops + maxi(1, tmax * regen / 100))


# --- Empires disparus --------------------------------------------------------------------------

static func _eliminations(state: GameState, added: Array[Dictionary]) -> void:
	var alive := {}
	for pid in state.sorted_colony_ids():
		alive[state.colonies[pid].owner] = true
	for e in state.empires:
		# Horde : tant que la flotte-ville vogue, le clan vit, même sans une seule planète.
		if not e.eliminated and not alive.has(e.id) and FactionTraits.city_fleet(state, e.id) != null:
			alive[e.id] = true
	for e in state.empires:
		if e.eliminated or alive.has(e.id):
			continue
		eliminate(state, e)
		added.append(state.add_chronicle("%s disparaît de la galaxie. Il en reste des épaves, des chansons, et quelques dettes impayées." % e.display_name(), Espionage.public_to(state, [e.id])))


static func eliminate(state: GameState, e: Empire) -> void:
	e.eliminated = true
	e.capital_planet = -1
	for f in Fleets.empire_fleets(state, e.id):
		state.fleets.erase(f.id)
	for other in state.empires:
		other.wars.erase(e.id)
	e.wars.clear()
