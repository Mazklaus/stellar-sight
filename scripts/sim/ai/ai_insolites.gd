class_name AiInsolites
extends RefCounted
## IA des peuples insolites (prop. 5 ; voir Insolites). Chaque peuple joue sa règle cassée :
##   - l'Exode lève l'ancre avant les Traqueurs, suit les Chants de la route et se pose sur la Terre
##     promise, garde ses nefs ensemble et arme une escorte dans son chantier embarqué ;
##   - le Cirque envoie ses Troupes jouer chez les empires en paix et en construit d'autres ;
##   - l'Orbe-Monde va manger là où il y a à manger, laisse des Lunes-sentinelles, dévore en guerre ;
##   - les Kraal vont de pâturage en pâturage et arrachent des Pilotes chez l'ennemi ;
##   - la Compagnie propose le commerce, achète des parts, prête aux empires à court d'énergie ;
##   - le Bureau met en demeure les non-conformes ;
##   - le Signal n'a rien à décider (il se propage seul) ; ses Corps empruntés se battent comme une flotte ;
##   - les Ysmer soufflent des inspirations aux voisins, des cauchemars aux ennemis, et rêvent une flotte
##     de songe en guerre ;
##   - Asphodèle réveille les héros morts et laisse partir ses Anciens las ;
##   - le Muséum se fait sauvegarder, achète des spécimens à ses partenaires et aux mineurs, en vole ;
##   - les Silencieux suivent leur directive : avant-postes dans le système visé, guerre à qui le tient ;
##   - Quiétude pose des postes voilés au-dessus des pré-spatiaux et les élève en secret.
## Et la réaction des autres : envoyer un délégué au Grand Numéro, purger un implant, signer une norme ou
## la refuser, nationaliser des parts, tolérer le Signal (Accord d'hébergement) ; lot 3 : signer le Pacte
## funéraire d'Asphodèle, tenter d'éveiller une usine des Silencieux (Noosphère) ; lot 4 : brûler les
## colonies de Myrr en guerre, chasser le mycélium.
## Lot 4 : le Sablier défait ses pertes quand il a le Sable, bâtit la Boucle, comprime sa capitale ; les
## Lithes lancent des Œuvres, dépensent leur Temps, délibèrent contre les voisins hostiles et hibernent sous
## la menace ; Myrr lance ses comètes vers les mondes libres les plus proches ; le Hallier choisit sa saison
## (Marcheurs en guerre ou pour s'étendre, Pousses sinon) et plante des Cœurs.


static func _ai() -> Dictionary:
	return Insolites.cfg("ai")


## Flottes menées ici (AiPlayer._fleets les laisse) : Troupes du Cirque, hardes de Kraal au repos.
static func managed(state: GameState, f: Fleet) -> bool:
	if state.insolites.is_empty():
		return false
	match Insolites.kind(state, f.owner):
		"zambalu":
			return InsZambalu.is_troupe(f) or FactionTraits.is_city_fleet(f)
		"kraal":
			return InsKraal.kraal_count(f) > 0
		"exode", "halcyre":
			return FactionTraits.is_city_fleet(f) and not InsExode.arrived(state, f.owner)
	return false


static func think(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if state.insolites.is_empty() or e.is_npc() or e.eliminated:
		return
	_react(ctx)
	if AiPlayer._use(ctx) <= 0:
		return
	match Insolites.kind(state, e.id):
		"exode":
			_exode(ctx)
		"zambalu":
			_zambalu(ctx)
		"halcyre":
			_halcyre(ctx)
		"kraal":
			_kraal(ctx)
		"ventrelune":
			_ventrelune(ctx)
		"bureau":
			_bureau(ctx)
		"ysmer":
			_ysmer(ctx)
		"asphodele":
			_asphodele(ctx)
		"cassivel":
			_cassivel(ctx)
		"silencieux":
			_silencieux(ctx)
		"quietude":
			_quietude(ctx)
		"sablier":
			_sablier(ctx)
		"gravea":
			_gravea(ctx)
		"myrr":
			_myrr(ctx)
		"vergemonde":
			_vergemonde(ctx)


static func _go(ctx: Dictionary, f: Fleet, sid: int, why := "") -> bool:
	if sid < 0 or sid == f.system_id:
		return false
	var e: Empire = ctx["e"]
	if AiPlayer._issue(ctx, SimCommands.move_fleet(e.id, f.id, sid)):
		if why != "":
			AiPlayer._intent(ctx, why)
		return true
	return false


## Puissance armée ennemie (en guerre) dans un système.
static func _foe_power(state: GameState, eid: int, sid: int) -> int:
	var n := 0
	for fid in state.sorted_fleet_ids():
		var f: Fleet = state.fleets[fid]
		if f.system_id == sid and f.owner != eid and Combat.is_armed(f) and Combat.at_war(state, f.owner, eid):
			n += Combat.fleet_power(f)
	return n


## Systèmes joignables triés par distance (sauts), à max_jumps au plus : [[sauts, sid], …].
static func _near(state: GameState, from: int, max_jumps: int) -> Array:
	var d: Dictionary = FactionTraits.jumps_from(state.galaxy, from)
	var out := []
	for sid in d:
		if int(d[sid]) > 0 and int(d[sid]) <= max_jumps:
			out.append([int(d[sid]), int(sid)])
	out.sort()
	return out


## Meilleur vaisseau de guerre que le chantier embarqué peut construire ("" sinon).
static func _yard_warship(state: GameState, eid: int) -> String:
	var best := ""
	var best_s := -1
	var ids: Array = FactionTraits.ship_ids_for(state.get_empire(eid).faction_id)
	ids.append_array(Designs.buildable_ids(state, eid))
	for sid in ids:
		var sd := GameData.ship(String(sid))
		if not bool(sd.get("military", false)) and sd.get("weapons", {}).is_empty():
			continue
		if Insolites.check_build(state, eid, String(sid)) != "":
			continue
		var s := Combat.ship_strength(String(sid))
		if s > best_s:
			best_s = s
			best = String(sid)
	return best


# --- Réactions de tous les empires ---------------------------------------------------------------

static func _react(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	# Grand Numéro : un délégué si l'on est pacifique, ou si l'on a une guerre à suspendre.
	if InsZambalu.open_call(state) >= 0 and InsZambalu.check_delegate(state, e.id) == "":
		if AiLevels.aggression(e) <= 0 or not e.wars.is_empty():
			AiPlayer._issue(ctx, SimCommands.ins_act(e.id, "delegate"))
	# Implants : on purge celui d'un ennemi, ou quand on a de quoi (le Signal toléré reste).
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner != e.id:
			continue
		var done := false
		for im: Dictionary in Insolites.implants_on(state, int(pid)):
			var k := String(im["k"])
			var owner := int(im["o"])
			if not Insolites.implant_visible(state, int(pid), e.id, k):
				continue
			var want := Combat.at_war(state, e.id, owner)
			match k:
				"fan_club", "guichet":
					want = want or int(e.resources.get("influence", 0)) >= 150
				"noeud":
					if not want and AiLevels.aggression(e) <= 0 and InsSignal.check_host(state, e.id, owner, true) == "":
						AiPlayer._issue(ctx, SimCommands.ins_act(e.id, "host", {"s": owner}))
						done = true
						break
					want = want or not InsSignal.hosted(state, owner, e.id)
				"reverie":
					want = want or int(e.resources.get("influence", 0)) >= 60
				"mycelium":
					want = true  # il ronge la colonie : on le chasse dès qu'on peut
			if want and Insolites.check_purge(state, e.id, int(pid), k) == "":
				AiPlayer._issue(ctx, SimCommands.ins_act(e.id, "purge", {"pid": int(pid), "k": k}))
				done = true
				break
		if done:
			break
	# Normes du Bureau : on signe la première si l'on ne déteste pas le Bureau ; chaque norme déjà signée
	# demande une meilleure opinion pour la suivante (équilibrage, lot 6 : tout signer donnait la victoire).
	for b in InsBureau.bureaus(state):
		if b == e.id or not e.contacts.has(b):
			continue
		var bar := int(_ai().get("sign_opinion", -20)) + int(_ai().get("sign_opinion_per_norm", 0)) * InsBureau.signed(state, b, e.id).size()
		if Diplomacy.opinion(state, e.id, b) < bar:
			continue
		for norm in InsBureau.unsigned(state, b, e.id):
			if InsBureau.check_sign(state, e.id, b, String(norm)) == "":
				AiPlayer._issue(ctx, SimCommands.ins_act(e.id, "sign", {"b": b, "norm": String(norm)}))
				break
	# Pacte funéraire : on confie ses morts à Asphodèle si on ne la déteste pas.
	for a in InsAsphodele.asphodeles(state):
		if a != e.id and InsAsphodele.check_pact(state, e.id, a, true) == "" and Diplomacy.opinion(state, e.id, a) >= int(_ai().get("pact_opinion", -10)):
			AiPlayer._issue(ctx, SimCommands.ins_act(e.id, "pact", {"a": a}))
			break
	# Noosphère : tenter d'éveiller une usine des Silencieux, quand on a du Savoir à revendre.
	if int(e.resources.get("knowledge", 0)) >= 300 and posmod(hash([state.seed_value, state.tick, e.id, "eveil"]), 1000) < int(_ai().get("teyl_awaken_pmille", 150)):
		for pid in state.sorted_colony_ids():
			var sc: Colony = state.colonies[pid]
			if InsSilencieux.is_silent(state, sc.owner) and InsSilencieux.check_awaken(state, e.id, int(pid)) == "":
				AiPlayer._issue(ctx, SimCommands.ins_act(e.id, "awaken", {"pid": int(pid)}))
				break
	# Feu contre Myrr : en guerre avec la Sporemère, une flotte à l'arrêt sur une de ses colonies la brûle.
	for m in InsMyrr.mothers(state):
		if m == e.id or not Combat.at_war(state, e.id, m):
			continue
		var burned := false
		for f in Fleets.empire_fleets(state, e.id):
			if f.is_moving() or not Combat.is_armed(f):
				continue
			for pid in state.galaxy.systems[f.system_id].planet_ids:
				var mc: Colony = state.colonies.get(pid)
				if mc != null and mc.owner == m and InsMyrr.check_burn(state, e.id, int(pid)) == "":
					burned = AiPlayer._issue(ctx, SimCommands.ins_act(e.id, "burn", {"pid": int(pid)}))
					break
			if burned:
				break
	# Parts de la Compagnie : on nationalise en guerre, ou quand elle a pris la majorité d'un monde.
	if Insolites.kind(state, e.id) != "ventrelune":
		for pid in state.sorted_colony_ids():
			var c: Colony = state.colonies[pid]
			if c.owner != e.id:
				continue
			var h := InsVentrelune.holder(state, int(pid))
			if h < 0:
				continue
			if Combat.at_war(state, e.id, h) or (AiLevels.aggression(e) > 0 and InsVentrelune.share(state, h, int(pid)) >= 51):
				AiPlayer._issue(ctx, SimCommands.ins_act(e.id, "nationalize", {"pid": int(pid)}))
				break


# --- Compagnie Ventrelune ------------------------------------------------------------------------

static func _ventrelune(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var reserve := int(_ai().get("ventrelune_buy_reserve", 150))
	# Le commerce d'abord : c'est la licence.
	for o in state.empires:
		if o.id != e.id and not o.is_npc() and not o.eliminated and e.contacts.has(o.id) and not Diplomacy.has_trade(state, e.id, o.id) \
				and not Combat.at_war(state, e.id, o.id) and Diplomacy.check_terms(state, e.id, o.id, Diplomacy.TRADE) == "":
			if AiPlayer._issue(ctx, SimCommands.propose_treaty(e.id, o.id, Diplomacy.TRADE)):
				break
	# Acheter des parts : la plus grosse colonie qu'on peut payer sans entamer la réserve.
	var best := -1
	var best_pop := -1
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner == e.id or c.population <= best_pop:
			continue
		if InsVentrelune.check_buy(state, e.id, int(pid)) != "":
			continue
		if int(e.resources.get("energy", 0)) - InsVentrelune.price(state, e.id, int(pid)) < reserve:
			continue
		best = int(pid)
		best_pop = c.population
	if best >= 0 and AiPlayer._issue(ctx, SimCommands.ins_act(e.id, "buy", {"pid": best})):
		AiPlayer._intent(ctx, "Achète des parts de %s" % state.galaxy.get_planet(best).display_name(state.galaxy))
	# Prêteur galactique : prêter à qui manque d'énergie (le défaut se paie en parts).
	if not state.finance.is_empty() and int(e.resources.get("energy", 0)) >= reserve * 3:
		for o in state.empires:
			if o.id == e.id or o.is_npc() or o.eliminated:
				continue
			if Finance.ai_wants_loan(state, o.id, 100) and Finance.check_lend(state, e.id, o.id, 100) == "":
				AiPlayer._issue(ctx, SimCommands.finance_lend(e.id, o.id, 100))
				break


# --- Bureau des Affaires Courantes -----------------------------------------------------------------

static func _bureau(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if not bool(_ai().get("bureau_publish", true)):
		return
	for o in state.empires:
		if InsBureau.check_summon(state, e.id, o.id) == "" and InsBureau.unsigned(state, e.id, o.id).size() >= 2:
			if AiPlayer._issue(ctx, SimCommands.ins_act(e.id, "summon", {"target": o.id})):
				AiPlayer._intent(ctx, "Met en demeure %s" % o.short_name())
				break


# --- Rêveurs d'Ysmer -----------------------------------------------------------------------------

static func _ysmer(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if not e.wars.is_empty() and InsYsmer.check_dream_fleet(state, e.id) == "":
		if AiPlayer._issue(ctx, SimCommands.ins_act(e.id, "dream_fleet")):
			AiPlayer._intent(ctx, "Rêve une flotte de songe")
			return
	var rv := InsYsmer.reveries(state, e.id)
	if rv.is_empty():
		return
	var pid := rv[posmod(state.tick / 30, rv.size())]
	var owner := (state.colonies[pid] as Colony).owner
	if Combat.at_war(state, e.id, owner):
		if InsYsmer.check_breath(state, e.id, "nightmare", pid) == "":
			AiPlayer._issue(ctx, SimCommands.ins_act(e.id, "nightmare", {"pid": pid}))
	elif posmod(hash([state.tick, e.id, "inspire"]), 1000) < int(_ai().get("ysmer_inspire_pmille", 300)) \
			and int(e.resources.get("influence", 0)) >= 60 and InsYsmer.check_breath(state, e.id, "inspire", pid) == "":
		AiPlayer._issue(ctx, SimCommands.ins_act(e.id, "inspire", {"pid": pid}))


# --- Flotte-Exode --------------------------------------------------------------------------------

static func _exode(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if InsExode.arrived(state, e.id):
		return
	if InsExode.check_settle(state, e.id) == "":
		if AiPlayer._issue(ctx, SimCommands.ins_act(e.id, "settle")):
			AiPlayer._intent(ctx, "Se pose sur la Terre promise")
			return
	var nefs := InsExode.nef_fleets(state, e.id)
	if nefs.is_empty():
		return
	var cf: Fleet = nefs[0]
	# Les nefs restent ensemble.
	for i in range(1, nefs.size()):
		var f: Fleet = nefs[i]
		if f.is_moving():
			continue
		if f.system_id == cf.system_id and not cf.is_moving():
			AiPlayer._issue(ctx, SimCommands.merge_fleets(e.id, f.id, cf.id))
		elif not cf.is_moving():
			_go(ctx, f, cf.system_id)
	# Escorte : le chantier embarqué arme l'Exode (six vaisseaux de guerre au plus).
	var armed := 0
	for f in Fleets.empire_fleets(state, e.id):
		if not FactionTraits.is_city_fleet(f):
			for s in f.ships:
				if Combat.is_armed_ship(s):
					armed += 1
	if armed < 6 and int(e.resources.get("materials", 0)) >= 150 and not AiPlayer._forgets(ctx):
		var ship := _yard_warship(state, e.id)
		if ship != "":
			AiPlayer._issue(ctx, SimCommands.ins_act(e.id, "build", {"ship": ship}))
	# L'escorte suit les nefs en temps de paix.
	if e.wars.is_empty() and not cf.is_moving():
		for f in Fleets.empire_fleets(state, e.id):
			if f.is_idle() and Combat.is_armed(f) and not FactionTraits.is_city_fleet(f) and f.system_id != cf.system_id:
				_go(ctx, f, cf.system_id)
	if cf.is_moving():
		return
	var ed := Insolites.emp(state, e.id)
	var anc: Dictionary = ed.get("anc", {})
	var stay := state.tick - int(anc.get("t", state.tick))
	var promised := Victory.promised_planet(state, e.id) if Victory.has_tech(state, e.id, "terre_promise") else -1
	if promised >= 0:
		var psid := state.galaxy.get_planet(promised).system_id
		var dist := int(FactionTraits.jumps_from(state.galaxy, cf.system_id).get(psid, 999))
		if dist <= int(Victory.info("terre_promise")["reveal_jumps"]) and psid != cf.system_id:
			if _go(ctx, cf, psid, "Fait route vers la Terre promise"):
				return
	var here := _anchor_value(state, e.id, cf.system_id)
	var threatened := _foe_power(state, e.id, cf.system_id) > 0
	if stay < int(_ai().get("exode_flee_days", 600)) and here > 0 and not threatened:
		return
	var best := -1
	var best_v := -999999
	var pd := FactionTraits.jumps_from(state.galaxy, state.galaxy.get_planet(promised).system_id) if promised >= 0 else {}
	for pair in _near(state, cf.system_id, 4):
		var sid := int(pair[1])
		if _foe_power(state, e.id, sid) > 0 or not e.explored.has(sid):
			continue
		var v := _anchor_value(state, e.id, sid) * 10 - int(pair[0]) * 3
		if state.system_owner(sid) >= 0:
			v -= 5
		if not pd.is_empty():
			v -= int(pd.get(sid, 30)) * 4
		if v > best_v:
			best_v = v
			best = sid
	_go(ctx, cf, best, "Lève l'ancre avant les Traqueurs")


static func _anchor_value(state: GameState, eid: int, sid: int) -> int:
	var v := 0
	for pid in state.galaxy.systems[sid].planet_ids:
		var w := InsExode.planet_work(state, eid, pid)
		for r in w:
			v += int(w[r])
	return v


# --- Cirque Zambalù ------------------------------------------------------------------------------

static func _zambalu(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var ed := Insolites.emp(state, e.id)
	var troupes: Array[Fleet] = []
	for f in Fleets.empire_fleets(state, e.id):
		if InsZambalu.is_troupe(f):
			troupes.append(f)
	if troupes.size() < 4 and int(e.resources.get("materials", 0)) >= 80 and not AiPlayer._forgets(ctx):
		AiPlayer._issue(ctx, SimCommands.ins_act(e.id, "build", {"ship": InsZambalu.TROUPE}))
	var taken := {}
	var shows: Dictionary = ed.get("shows", {})
	for k in shows:
		taken[int(shows[k]["s"])] = true
	for f in troupes:
		if f.is_moving():
			taken[f.destination()] = true
	for f in troupes:
		if f.is_moving() or shows.has(str(f.id)):
			continue
		var best := -1
		# D'abord le public proche ; s'il n'y en a pas (espace vaste, voisins lointains), la troupe
		# part en grande tournée plutôt que d'attendre au Chapiteau.
		for reach: int in [8, 30]:
			for pair in _near(state, f.system_id, reach):
				var sid := int(pair[1])
				if taken.has(sid) or not e.explored.has(sid):
					continue
				var b := InsZambalu.host_of(state, e.id, sid)
				if b < 0 or Combat.at_war(state, e.id, b) or InsZambalu.banned(state, b):
					continue
				if int((state.insolites.get("stage", {}) as Dictionary).get(str(sid), 0)) > state.tick:
					continue
				best = sid
				break
			if best >= 0:
				break
		if best >= 0 and _go(ctx, f, best, "Part en tournée"):
			taken[best] = true
	# Le Chapiteau fuit les flottes ennemies.
	var cf := FactionTraits.city_fleet(state, e.id)
	if cf != null and not cf.is_moving() and _foe_power(state, e.id, cf.system_id) > 0:
		for pair in _near(state, cf.system_id, 2):
			if _foe_power(state, e.id, int(pair[1])) == 0 and e.explored.has(int(pair[1])):
				_go(ctx, cf, int(pair[1]), "Le Chapiteau plie bagage")
				break


# --- Orbe-Monde Halcyre --------------------------------------------------------------------------

static func _halcyre(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var o := InsHalcyre.orbe(state, e.id)
	if o == null or o.is_moving():
		return
	var ed := Insolites.emp(state, e.id)
	if not (ed.get("eat", {}) as Dictionary).is_empty():
		return
	var sid := o.system_id
	# En guerre, l'Orbe dévore une colonie ennemie de son système.
	if InsHalcyre.mass(state, e.id) >= 40:
		for pid in state.galaxy.systems[sid].planet_ids:
			if InsHalcyre.check_devour(state, e.id, pid) == "":
				if AiPlayer._issue(ctx, SimCommands.ins_act(e.id, "devour", {"pid": pid})):
					AiPlayer._intent(ctx, "Dévore un monde ennemi")
					return
	var edible := InsHalcyre.edible(state, sid)
	# Lune-sentinelle : un éclat laissé dans un système libre quand la Masse le permet.
	if InsHalcyre.mass(state, e.id) >= int(_ai().get("halcyre_sentinel_mass", 50)) and state.system_owner(sid) < 0:
		for pid in state.galaxy.systems[sid].planet_ids:
			if edible.has(pid) and edible.size() > 1 and pid == edible[0]:
				continue
			if InsHalcyre.check_sentinel(state, e.id, pid) == "":
				if AiPlayer._issue(ctx, SimCommands.ins_act(e.id, "sentinel", {"pid": pid})):
					return
	if not edible.is_empty():
		return  # il reste à manger ici : l'Orbe mangera demain
	for pair in _near(state, sid, 6):
		var to := int(pair[1])
		var owner := state.system_owner(to)
		if owner >= 0 and owner != e.id and Combat.at_war(state, owner, e.id):
			continue
		if InsHalcyre.edible(state, to).is_empty() or _foe_power(state, e.id, to) > 0:
			continue
		if _go(ctx, o, to, "L'Orbe-Monde part manger ailleurs"):
			return
	if o.is_idle():
		AiPlayer._issue(ctx, SimCommands.set_fleet_order(e.id, o.id, Fleet.ORDER_EXPLORE))  # rien à manger en vue : l'Orbe erre


# --- Hardes de Kraal -----------------------------------------------------------------------------

static func _kraal(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var want := int(_ai().get("kraal_min_graze", 30))
	var taken := {}
	var known: Dictionary = Insolites.emp(state, e.id).get("known", {})
	for f in Fleets.empire_fleets(state, e.id):
		if InsKraal.kraal_count(f) == 0 or f.is_moving() or state.battles.has(f.system_id):
			continue
		if InsKraal.check_pilot(state, e.id, f.id) == "":
			AiPlayer._issue(ctx, SimCommands.ins_act(e.id, "pilot", {"fleet": f.id}))
			continue
		if not e.wars.is_empty() and Combat.is_warfleet(f) and state.system_owner(f.system_id) >= 0 and Combat.at_war(state, e.id, state.system_owner(f.system_id)):
			continue  # en chasse chez l'ennemi
		if InsKraal.is_pasture(state, f.system_id) and InsKraal.graze(state, e.id, f.system_id) >= want and not taken.has(f.system_id):
			taken[f.system_id] = true
			continue
		var moved := false
		for pair in _near(state, f.system_id, 8):
			var to := int(pair[1])
			if taken.has(to) or not InsKraal.is_pasture(state, to) or InsKraal.graze(state, e.id, to) < want:
				continue
			var owner := state.system_owner(to)
			if (owner >= 0 and owner != e.id) or _foe_power(state, e.id, to) > 0:
				continue
			if _go(ctx, f, to, "La Harde migre vers un pâturage"):
				taken[to] = true
				moved = true
				break
		if not moved and not known.has(str(f.system_id)) and f.is_idle():
			AiPlayer._issue(ctx, SimCommands.set_fleet_order(e.id, f.id, Fleet.ORDER_EXPLORE))  # chercher de nouveaux pâturages


# --- Asphodèle -----------------------------------------------------------------------------------

static func _asphodele(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var council: Array = Insolites.emp(state, e.id).get("council", [])
	for i in council.size():
		if InsAsphodele.lassitude(state, council[i]) >= Insolites.c_int("asphodele", "lassitude_max", 60) and InsAsphodele.check_release(state, e.id, i) == "":
			if AiPlayer._issue(ctx, SimCommands.ins_act(e.id, "release", {"i": i})):
				return
	if int(e.resources.get("influence", 0)) < int(_ai().get("asphodele_raise_influence", 80)):
		return
	var fl := InsAsphodele.fallen(state)
	var best := -1
	var lvl := 0
	for i in fl.size():
		if int((fl[i] as Dictionary)["lvl"]) > lvl:
			lvl = int((fl[i] as Dictionary)["lvl"])
			best = i
	if best >= 0 and InsAsphodele.check_raise(state, e.id, best) == "":
		if AiPlayer._issue(ctx, SimCommands.ins_act(e.id, "raise", {"i": best})):
			AiPlayer._intent(ctx, "Réveille un héros mort")


# --- Muséum de Sire Cassivel ---------------------------------------------------------------------

static func _cassivel(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if int(e.resources.get("energy", 0)) >= int(_ai().get("cassivel_backup_reserve", 400)) and InsCassivel.check_backup(state, e.id) == "":
		AiPlayer._issue(ctx, SimCommands.ins_act(e.id, "backup"))
		return
	if int(e.resources.get("energy", 0)) < int(_ai().get("cassivel_buy_reserve", 120)) + 120:
		return
	var who: Array[int] = []
	for o in e.contacts:
		who.append(int(o))
	if not state.minors.is_empty():
		who.append_array(Minors.met(state, e.id))
	who.sort()
	for w in who:
		if InsCassivel.check_acquire(state, e.id, w) == "":
			if AiPlayer._issue(ctx, SimCommands.ins_act(e.id, "acquire", {"w": w})):
				AiPlayer._intent(ctx, "Achète un spécimen pour la Collection")
				return
	# Sans accord commercial : une Acquisition discrète.
	for o in e.contacts:
		if InsCassivel.species_of(state, int(o)) != "" and not InsCassivel.species_held(state, e.id).has(InsCassivel.species_of(state, int(o))):
			if SimCommands.validate(state, SimCommands.spy_op(e.id, int(o), "acquisition_discrete")) == "":
				AiPlayer._issue(ctx, SimCommands.spy_op(e.id, int(o), "acquisition_discrete"))
				return


# --- Silencieux ----------------------------------------------------------------------------------

static func _silencieux(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var d := InsSilencieux.directive(state, e.id)
	if d.is_empty():
		return
	var ob := InsSilencieux.obstacle(state, e.id)
	if ob >= 0:
		# Garde-fou : pas de guerre pour la directive avant l'an 5 (chacun doit survivre jusque-là).
		if not Combat.at_war(state, e.id, ob) and state.tick >= int(_ai().get("silencieux_war_min_days", 1800)):
			var mine := 0
			var theirs := 0
			for f in Fleets.empire_fleets(state, ob):
				theirs += Combat.fleet_power(f)
			for f in Fleets.empire_fleets(state, e.id):
				mine += Combat.fleet_power(f)
			if mine * 100 >= theirs * int(_ai().get("silencieux_war_power_pct", 120)) and SimCommands.validate(state, SimCommands.declare_war(e.id, ob)) == "":
				if AiPlayer._issue(ctx, SimCommands.declare_war(e.id, ob)):
					AiPlayer._intent(ctx, "Écarte l'obstacle à la directive")
		return
	for pid in state.galaxy.systems[int(d["sid"])].planet_ids:
		if state.colonies.has(pid):
			continue
		if SimCommands.validate(state, SimCommands.colonize(e.id, pid, Colony.KIND_OUTPOST)) == "":
			if AiPlayer._issue(ctx, SimCommands.colonize(e.id, pid, Colony.KIND_OUTPOST)):
				AiPlayer._intent(ctx, "Suit la directive")
				return


# --- Observateurs de Quiétude --------------------------------------------------------------------

static func _quietude(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if state.minors.is_empty():
		return
	for mid in Minors.ids(state):
		if InsQuietude.check_uplift(state, e.id, mid) == "" and int(e.resources.get("influence", 0)) >= int(_ai().get("quietude_uplift_influence", 60)):
			if AiPlayer._issue(ctx, SimCommands.ins_act(e.id, "uplift", {"m": mid})):
				return
	if int(e.resources.get("influence", 0)) < 60:
		return
	for mid in Minors.ids(state):
		if InsQuietude.check_post(state, e.id, mid) == "":
			if AiPlayer._issue(ctx, SimCommands.ins_act(e.id, "post", {"m": mid})):
				AiPlayer._intent(ctx, "Pose un poste voilé")
				return


# --- Gardiens du Sablier Fêlé --------------------------------------------------------------------

static func _sablier(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var ed := Insolites.emp(state, e.id)
	if InsSablier.check_loop(state, e.id) == "":
		if AiPlayer._issue(ctx, SimCommands.ins_act(e.id, "loop")):
			AiPlayer._intent(ctx, "Bâtit une étape de la Boucle")
			return
	if int(ed.get("sand", 0)) >= int(_ai().get("sablier_undo_sand", 60)):
		# Ce qui coûte le plus d'abord (système, héros), en partant du plus récent.
		var reg := InsSablier.ledger(state, e.id)
		var best := -1
		var best_c := -1
		for i in range(reg.size() - 1, -1, -1):
			var c := InsSablier.undo_cost(reg[i])
			if c > best_c and InsSablier.check_undo(state, e.id, i) == "":
				best_c = c
				best = i
		if best >= 0 and AiPlayer._issue(ctx, SimCommands.ins_act(e.id, "undo", {"i": best})):
			AiPlayer._intent(ctx, "Défait le passé")
			return
	var cap := FactionTraits.capital_system(state, e.id)
	if cap >= 0 and int(ed.get("sand", 0)) >= int(_ai().get("sablier_undo_sand", 60)) + Insolites.c_int("sablier", "bubble_sand", 30) and InsSablier.check_bubble(state, e.id, cap, "compression") == "":
		AiPlayer._issue(ctx, SimCommands.ins_act(e.id, "bubble", {"s": cap, "mode": "compression"}))


# --- Lithes de Gravéa ----------------------------------------------------------------------------

static func _gravea(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var ed := Insolites.emp(state, e.id)
	# Hibernation : un monde attaqué s'endort.
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner == e.id and InsGravea.check_sleep(state, e.id, int(pid)) == "":
			if AiPlayer._issue(ctx, SimCommands.ins_act(e.id, "sleep", {"pid": int(pid)})):
				AiPlayer._intent(ctx, "Un monde menacé s'endort")
				return
	# Patience : le Temps accumulé va à l'Œuvre la plus avancée.
	var works: Array = ed.get("works", [])
	if int(ed.get("time", 0)) * 2 >= Insolites.c_int("gravea", "time_max", 720) and not works.is_empty():
		var bi := 0
		for i in works.size():
			if int(works[i]["left"]) < int(works[bi]["left"]):
				bi = i
		if InsGravea.check_hasten(state, e.id, bi) == "" and AiPlayer._issue(ctx, SimCommands.ins_act(e.id, "hasten", {"i": bi})):
			return
	# Consensus : on délibère contre les voisins hostiles (le siècle n'attend pas).
	if AiLevels.aggression(e) >= 0:
		for o in state.empires:
			if o.id != e.id and not o.is_npc() and not o.eliminated and e.contacts.has(o.id) and Diplomacy.opinion(state, e.id, o.id) < int(_ai().get("gravea_deliberate_opinion", -30)):
				if InsGravea.check_deliberate(state, e.id, o.id) == "" and AiPlayer._issue(ctx, SimCommands.ins_act(e.id, "deliberate", {"t": o.id})):
					return
	# Œuvres lentes : une de plus quand on en a les moyens.
	if works.size() >= Insolites.c_int("gravea", "works_max", 3):
		return
	var seen := {}
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner != e.id:
			continue
		var sid := state.galaxy.get_planet(int(pid)).system_id
		if seen.has(sid):
			continue
		seen[sid] = true
		for q in state.galaxy.systems[sid].planet_ids:
			for w in InsGravea.work_ids():
				if InsGravea.check_work(state, e.id, w, int(q)) == "":
					if AiPlayer._issue(ctx, SimCommands.ins_act(e.id, "work", {"w": w, "pid": int(q)})):
						AiPlayer._intent(ctx, "Entreprend une Œuvre lente")
						return


# --- Sporemère de Myrr ---------------------------------------------------------------------------

static func _myrr(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var cost: Dictionary = Insolites.cfg("myrr").get("comet_cost", {})
	# Défense sans flotte (prop. 97) : les matériaux qu'aucun chantier naval ne prend vont aux défenses
	# planétaires, en guerre d'abord dans les systèmes menacés, sinon à la capitale.
	if int(e.resources.get("materials", 0)) >= int(_ai().get("myrr_defense_materials", 300)):
		var order: Array[int] = []
		var cap := FactionTraits.capital_system(state, e.id)
		for pid in state.sorted_colony_ids():
			var c: Colony = state.colonies[pid]
			if c.owner != e.id or not c.is_colony() or c.construction != "":
				continue
			var sid := state.galaxy.get_planet(int(pid)).system_id
			if _foe_power(state, e.id, sid) > 0 or (not e.wars.is_empty() and sid == cap):
				order.push_front(int(pid))
			elif sid == cap or not e.wars.is_empty():
				order.append(int(pid))
		for pid in order:
			for bid in _ai().get("myrr_defenses", ["citadelle", "bastion", "batterie_planetaire", "bouclier_planetaire"]):
				if SimCommands.validate(state, SimCommands.build(e.id, pid, String(bid))) == "":
					if AiPlayer._issue(ctx, SimCommands.build(e.id, pid, String(bid))):
						AiPlayer._intent(ctx, "Arme ses mondes (aucune flotte)")
						return
	if int(e.resources.get("materials", 0)) < int(cost.get("materials", 0)) + int(_ai().get("myrr_comet_materials", 120)):
		return
	if (Insolites.emp(state, e.id).get("comets", []) as Array).size() >= Insolites.c_int("myrr", "comet_max", 2):
		return
	# Distance de chaque système à la plus proche colonie (une seule passe par système ensemencé).
	var dist := {}
	for s in InsMyrr.seeded(state, e.id):
		var d: Dictionary = FactionTraits.jumps_from(state.galaxy, s)
		for k in d:
			if not dist.has(k) or int(d[k]) < int(dist[k]):
				dist[k] = int(d[k])
	var cands := []
	for k in dist:
		if int(dist[k]) > 0 and int(dist[k]) <= Insolites.c_int("myrr", "comet_jumps", 5):
			cands.append([int(dist[k]), int(k)])
	cands.sort()
	for cd in cands:
		var sid := int(cd[1])
		if InsMyrr.check_comet(state, e.id, sid) == "":
			if AiPlayer._issue(ctx, SimCommands.ins_act(e.id, "comet", {"s": sid})):
				AiPlayer._intent(ctx, "Lance une comète-semence")
				return


# --- Hallier de Vergemonde -----------------------------------------------------------------------

static func _vergemonde(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var ed := Insolites.emp(state, e.id)
	var cols := 0
	for pid in state.sorted_colony_ids():
		if (state.colonies[pid] as Colony).owner == e.id:
			cols += 1
	var want := "pousses"
	if not e.wars.is_empty() or cols < 4:
		want = "marcheurs"
	elif int(e.resources.get("influence", 0)) < 30:
		want = "enracines"
	if String(ed.get("season", "")) != want and InsVergemonde.check_season(state, e.id, want) == "":
		if AiPlayer._issue(ctx, SimCommands.ins_act(e.id, "season", {"s": want})):
			return
	if int(e.resources.get("influence", 0)) < int(_ai().get("vergemonde_heart_influence", 150)):
		return
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner == e.id and InsVergemonde.check_heart(state, e.id, int(pid)) == "":
			if AiPlayer._issue(ctx, SimCommands.ins_act(e.id, "heart", {"pid": int(pid)})):
				AiPlayer._intent(ctx, "Plante un Cœur")
				return
