class_name InsolitesUi
extends RefCounted
## Peuples insolites côté interface : actions de la fiche de planète (Lune-sentinelle, dévorer, purger un
## implant, l'Arrivée de l'Exode, acheter des parts, nationaliser, souffler un rêve), menu « Peuple » de la
## fiche de flotte (chantier embarqué, Pilotes des Kraal, délégué au Grand Numéro) et menu des peuples
## (clic sur la ligne d'état de l'empire : normes du Bureau, Mises en demeure, Accord d'hébergement du
## Signal, flotte de songe ; lot 3 : Pacte funéraire et Nécro-conseil d'Asphodèle, sauvegarde et
## acquisitions du Muséum, postes voilés et élévations de Quiétude ; lot 4 : Registre et Boucle du Sablier,
## Consensus et Patience des Lithes, comètes de Myrr, Saisons du Hallier ; sur la planète : Œuvres lentes,
## Hibernation, bulles temporelles, comète, brûler le mycélium, planter un Cœur). Les ordres passent par
## SimCommands.ins_act.


static func system_actions(state: GameState, player: int, p: Planet, emit: Callable) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if state == null or player < 0 or state.insolites.is_empty():
		return out
	var d := {"pid": p.id}
	var k := Insolites.kind(state, player)
	var c: Colony = state.colonies.get(p.id)
	if k == "halcyre":
		var o := InsHalcyre.orbe(state, player)
		if o != null and o.system_id == p.system_id:
			if c == null:
				out.append(WondersUi._act(state, SimCommands.ins_act(player, "sentinel", d), "Lune-sentinelle", "-%d Masse" % Insolites.c_int("halcyre", "sentinel_mass", 4),
						"Halcyre laisse un éclat de lui-même sur ce corps : un avant-poste armé qui garde le système (Masse rendue au monde).", emit))
			elif c.owner != player:
				out.append(WondersUi._act(state, SimCommands.ins_act(player, "devour", d), "Dévorer ce monde", "en guerre seulement",
						"L'Orbe-Monde mange une colonie ennemie : sa population devient de la Masse, la planète disparaît de la carte.", emit))
	if k == "exode" and not InsExode.arrived(state, player) and Victory.promised_planet(state, player) == p.id:
		out.append(WondersUi._act(state, SimCommands.ins_act(player, "settle", {}), "L'Arrivée", "l'Exode se pose ici",
				"La Flotte-Exode se pose sur la Terre promise : les nefs deviennent une capitale, les Traqueurs lancent leur dernière chasse.", emit))
	if c != null and c.owner == player:
		for im: Dictionary in Insolites.implants_on(state, p.id):
			var ik := String(im["k"])
			if not Insolites.implant_visible(state, p.id, player, ik):
				continue
			var df := Insolites.implant_def(ik)
			out.append(WondersUi._act(state, SimCommands.ins_act(player, "purge", {"pid": p.id, "k": ik}), "Purger : %s" % String(df.get("label", "implant")).to_lower(),
					GameData.format_amounts(df.get("purge_cost", {})),
					"Chasser l'implant d'un autre peuple de cette planète. La stabilité du système souffre quelques semaines.", emit))
		if InsVentrelune.holder(state, p.id) >= 0:
			out.append(WondersUi._act(state, SimCommands.ins_act(player, "nationalize", d), "Nationaliser", "%d %% de parts" % InsVentrelune.share(state, InsVentrelune.holder(state, p.id), p.id),
					"Saisir les parts de la Compagnie Ventrelune sur ce monde : plus de dividendes à verser, mais une lourde perte d'opinion et un motif de guerre pour elle.", emit))
	if k == "ventrelune" and c != null and c.owner != player and c.is_colony():
		out.append(WondersUi._act(state, SimCommands.ins_act(player, "buy", d), "Acheter 10 %% (%d %% détenus)" % InsVentrelune.share(state, player, p.id), "%d énergie" % InsVentrelune.price(state, player, p.id),
				"Acheter une tranche de parts à la Bourse (accord commercial requis) : dividendes chaque mois, vue à 25 %, impôt à 51 %.", emit))
	if k == "ysmer" and c != null and int(Insolites.implant(state, p.id, "reverie").get("o", -1)) == player:
		out.append(WondersUi._act(state, SimCommands.ins_act(player, "inspire", d), "Souffler une inspiration", GameData.format_amounts(Insolites.cfg("ysmer").get("inspire_cost", {})),
				"Un rêve utile : l'hôte gagne du Savoir et s'en souvient avec gratitude.", emit))
		out.append(WondersUi._act(state, SimCommands.ins_act(player, "nightmare", d), "Envoyer des cauchemars", GameData.format_amounts(Insolites.cfg("ysmer").get("nightmare_cost", {})),
				"Toute la colonie rêve la même nuit d'un couloir sans fin : stabilité -10 dans le système pendant six mois.", emit))
	# Lot 3 : éveiller une usine des Silencieux (Noosphère), postes voilés et élévations de Quiétude.
	if c != null and c.is_colony() and InsSilencieux.is_silent(state, c.owner) and String(state.get_empire(player).faction().get("species", {}).get("gouvernement", "")) == "conscience":
		out.append(WondersUi._act(state, SimCommands.ins_act(player, "awaken", d), "Éveiller l'usine", GameData.format_amounts(Insolites.cfg("silencieux").get("awaken_cost", {})),
				"La Noosphère tend la main vers une usine des Silencieux. Si elle répond, elle devient un peuple mineur conscient.", emit))
	if k == "quietude" and c != null and GameState.is_minor(c.owner) and not state.minors.is_empty() and Minors.is_pre(state, c.owner):
		var md := {"m": c.owner}
		if InsQuietude.post_on(state, c.owner).is_empty():
			out.append(WondersUi._act(state, SimCommands.ins_act(player, "post", md), "Poser un poste voilé", GameData.format_amounts(Insolites.cfg("quietude").get("post_cost", {})),
					"Un poste d'observation caché au-dessus de ce jeune peuple : du Savoir chaque mois, et le droit de l'élever en secret. Gare à qui le découvre.", emit))
		else:
			out.append(WondersUi._act(state, SimCommands.ins_act(player, "uplift", md), "Élever en secret", GameData.format_amounts(Insolites.cfg("quietude").get("uplift_cost", {})),
					"Un rêve, une idée, une roue meilleure : le jeune peuple avance d'un an et demi, mais sa conscience monte.", emit))
	# Lot 4 : Œuvres lentes et Hibernation des Lithes, bulles du Sablier, comètes et feu de Myrr, Cœur du Hallier.
	if k == "gravea" and state.system_owner(p.system_id) == player:
		for w in InsGravea.work_ids():
			if InsGravea.targets(state, w, p.id).is_empty():
				continue
			var wd := InsGravea.work_def(w)
			@warning_ignore("integer_division")
			out.append(WondersUi._act(state, SimCommands.ins_act(player, "work", {"w": w, "pid": p.id}), "Œuvre : %s" % String(wd.get("label", w)), "%s, %d ans" % [GameData.format_amounts(wd.get("cost", {})), int(wd.get("days", 3600)) / 360],
					String(wd.get("text", "")) + " Une Œuvre lente : elle changera la forme du monde, dans dix ou quinze ans.", emit))
		if c != null and c.owner == player and c.is_colony():
			out.append(WondersUi._act(state, SimCommands.ins_act(player, "sleep", d), "Hiberner", "%d jours" % Insolites.c_int("gravea", "sleep_days", 1080),
					"Le monde attaqué s'endort : plus d'invasion possible dans ce système, mais plus de production non plus.", emit))
	if k == "sablier":
		if state.system_owner(p.system_id) == player:
			out.append(WondersUi._act(state, SimCommands.ins_act(player, "bubble", {"s": p.system_id, "mode": "compression"}), "Bulle de Compression", "%d Sable" % Insolites.c_int("sablier", "bubble_sand", 30),
					"Le temps se resserre sur ce système : production +%d %% pendant un an." % Insolites.c_int("sablier", "bubble_pct", 25), emit))
		elif state.system_owner(p.system_id) >= 0 and not GameState.is_npc(state.system_owner(p.system_id)):
			out.append(WondersUi._act(state, SimCommands.ins_act(player, "bubble", {"s": p.system_id, "mode": "dilatation"}), "Bulle de Dilatation", "%d Sable" % Insolites.c_int("sablier", "bubble_sand", 30),
					"Les horloges de ce système étranger ralentissent : production -%d %% pendant un an." % Insolites.c_int("sablier", "bubble_pct", 25), emit))
	if k == "myrr" and c == null and not InsMyrr.seeded(state, player).has(p.system_id):
		out.append(WondersUi._act(state, SimCommands.ins_act(player, "comet", {"s": p.system_id}), "Comète-semence", GameData.format_amounts(Insolites.cfg("myrr").get("comet_cost", {})),
				"Lancer une comète chargée de spores vers ce système : elle y tombe au bout de quelques mois et une colonie pousse. Une seconde comète vers le même système arrive deux fois plus vite.", emit))
	if c != null and InsMyrr.is_myrr(state, c.owner) and c.owner != player:
		out.append(WondersUi._act(state, SimCommands.ins_act(player, "burn", d), "Brûler le mycélium", "en guerre, flotte sur place",
				"Le feu depuis l'orbite : la colonie de Myrr perd des habitants (ou disparaît), le système ne pousse plus pendant un an, la biosphère en souffre.", emit))
	if k == "vergemonde" and c != null and c.owner == player and p.type == "gaia":
		out.append(WondersUi._act(state, SimCommands.ins_act(player, "heart", d), "Planter un Cœur", GameData.format_amounts(Insolites.cfg("vergemonde").get("heart_cost", {})),
				"Éveiller ce monde-jardin : il devient un monde vivant, bienveillant d'emblée envers le Hallier.", emit))
	return out


## Le bouton « Peuple » de la fiche de flotte est-il utile pour cette flotte ?
static func fleet_has_actions(state: GameState, player: int, f: Fleet) -> bool:
	if state == null or f == null or f.owner != player or state.insolites.is_empty():
		return false
	if InsZambalu.open_call(state) >= 0 and InsZambalu.check_delegate(state, player) == "":
		return true
	var k := Insolites.kind(state, player)
	if k == "kraal":
		return InsKraal.kraal_count(f) > 0
	if Insolites.yard_allowed(state, player):
		return FactionTraits.city_fleet(state, player) == f
	return false


static func fleet_button_text(state: GameState, player: int) -> String:
	match Insolites.kind(state, player):
		"kraal":
			return "PILOTES"
		"exode", "zambalu":
			return "CHANTIER EMBARQUÉ"
	return "GRAND NUMÉRO"


static func open_fleet_menu(main: Node, state: GameState, player: int, f: Fleet) -> void:
	if not fleet_has_actions(state, player, f):
		return
	var menu := PopupMenu.new()
	menu.name = "InsolitesMenu"
	var cmds: Array[Dictionary] = []
	if Insolites.yard_allowed(state, player) and FactionTraits.city_fleet(state, player) == f:
		var yard: Dictionary = Insolites.emp(state, player).get("yard", {})
		menu.add_separator("Chantier embarqué" + (" · %s, %d j" % [Designs.label(String(yard["ship"])), int(yard["left"])] if not yard.is_empty() else ""))
		for sid in GameData.ship_ids():
			var sd := GameData.ship(sid)
			if bool(sd.get("spawn_only", false)) or bool(sd.get("colonizer", false)) or not Designs.can_build_id(state, player, sid):
				continue
			if not Fleets.ship_unlocked(state, player, sid):
				continue
			_item(menu, cmds, state, player, "build", {"ship": sid}, "%s (%s)" % [Designs.label(sid), GameData.format_amounts(Fleets.ship_cost(state, player, sid))])
	if Insolites.kind(state, player) == "kraal" and InsKraal.kraal_count(f) > 0:
		menu.add_separator("Pilotes")
		_item(menu, cmds, state, player, "pilot", {"fleet": f.id}, "Lier un Pilote (un habitant ennemi du système)")
	if InsZambalu.open_call(state) >= 0:
		menu.add_separator("Grand Numéro")
		_item(menu, cmds, state, player, "delegate", {}, "Envoyer un délégué (trêve entre délégués, influence)")
	menu.id_pressed.connect(func(id: int) -> void:
		if id >= 0 and id < cmds.size() and main.has_method("_submit"):
			main.call("_submit", cmds[id])
		menu.queue_free())
	menu.popup_hide.connect(func() -> void:
		if is_instance_valid(menu):
			menu.queue_free.call_deferred())
	main.add_child(menu)
	menu.popup_centered()


static func _item(menu: PopupMenu, cmds: Array[Dictionary], state: GameState, player: int, act: String, d: Dictionary, text: String) -> void:
	var cmd := SimCommands.ins_act(player, act, d)
	var why := SimCommands.validate(state, cmd)
	var id := cmds.size()
	cmds.append(cmd)
	menu.add_item(text, id)
	if why != "":
		var idx := menu.get_item_index(id)
		menu.set_item_disabled(idx, true)
		menu.set_item_tooltip(idx, why)


# --- Menu des peuples (ligne d'état de l'empire) -------------------------------------------------------

## Le menu des peuples a-t-il quelque chose à proposer ?
static func has_people_menu(state: GameState, player: int) -> bool:
	if state == null or player < 0 or state.insolites.is_empty():
		return false
	var e := state.get_empire(player)
	if e == null:
		return false
	var k := Insolites.kind(state, player)
	if ["bureau", "ysmer", "asphodele", "cassivel", "sablier", "gravea", "myrr", "vergemonde"].has(k):
		return true
	for eid in Insolites.nomad_ids(state):
		if eid != player and e.contacts.has(eid) and ["bureau", "signal", "asphodele"].has(Insolites.kind(state, eid)):
			return true
	return false


static func open_people_menu(main: Node, state: GameState, player: int) -> void:
	if not has_people_menu(state, player):
		return
	var e := state.get_empire(player)
	var menu := PopupMenu.new()
	menu.name = "InsolitesPeopleMenu"
	var cmds: Array[Dictionary] = []
	var k := Insolites.kind(state, player)
	for b in InsBureau.bureaus(state):
		if b == player or not e.contacts.has(b):
			continue
		menu.add_separator("Normes du %s (non-conformité : %d %%)" % [state.get_empire(b).short_name(), InsBureau.nonconf_pct(state, player)])
		for norm in InsBureau.published(state, b):
			var nd := InsBureau.norm_def(String(norm))
			if InsBureau.signed(state, b, player).has(norm):
				var i := menu.item_count
				menu.add_item("✓ %s" % String(nd.get("label", norm)), -1)
				menu.set_item_disabled(i, true)
				menu.set_item_tooltip(i, String(nd.get("text", "")))
				continue
			_item(menu, cmds, state, player, "sign", {"b": b, "norm": String(norm)}, "Signer « %s »" % String(nd.get("label", norm)))
			menu.set_item_tooltip(menu.item_count - 1, "%s Redevance : %d énergie par mois." % [String(nd.get("text", "")), Insolites.c_int("bureau", "fee", 2)])
	if k == "bureau":
		menu.add_separator("Mises en demeure")
		for o in state.empires:
			if o.id != player and not o.is_npc() and not o.eliminated and e.contacts.has(o.id) and not InsBureau.conforms(state, player, o.id):
				_item(menu, cmds, state, player, "summon", {"target": o.id}, "Mettre en demeure %s (%d norme(s) non signée(s))" % [o.short_name(), InsBureau.unsigned(state, player, o.id).size()])
	for s in Insolites.nomad_ids(state):
		if s == player or not e.contacts.has(s) or Insolites.kind(state, s) != "signal":
			continue
		menu.add_separator("Enfants du Signal")
		var on := not InsSignal.hosted(state, s, player)
		_item(menu, cmds, state, player, "host" if on else "unhost", {"s": s},
				"Signer un Accord d'hébergement (plus de symptômes, du Savoir par nœud)" if on else "Rompre l'Accord d'hébergement")
	if k == "ysmer":
		menu.add_separator("Rêveurs d'Ysmer")
		_item(menu, cmds, state, player, "dream_fleet", {}, "Rêver une flotte de songe (%s, 90 jours)" % GameData.format_amounts(Insolites.cfg("ysmer").get("dream_fleet_cost", {})))
	for a in InsAsphodele.asphodeles(state):
		if a == player or not e.contacts.has(a):
			continue
		menu.add_separator("Asphodèle, Cité des Trépassés")
		var on := not InsAsphodele.pacted(state, a, player)
		_item(menu, cmds, state, player, "pact" if on else "unpact", {"a": a},
				"Signer le Pacte funéraire (Ossuaires : stabilité +3, piété ; vos morts vont à Asphodèle)" if on else "Rompre le Pacte funéraire")
	if k == "asphodele":
		menu.add_separator("Nécro-conseil")
		var council: Array = Insolites.emp(state, player).get("council", [])
		for i in council.size():
			_item(menu, cmds, state, player, "release", {"i": i}, "Laisser partir %s (%d mois d'Usure)" % [String(council[i]["n"]), InsAsphodele.lassitude(state, council[i])])
		menu.add_separator("Revenants (%s)" % GameData.format_amounts(Insolites.cfg("asphodele").get("raise_cost", {})))
		var fl := InsAsphodele.fallen(state)
		for i in fl.size():
			_item(menu, cmds, state, player, "raise", {"i": i}, "Réveiller %s (niveau %d)" % [String(fl[i]["name"]), int(fl[i]["lvl"])])
	if k == "cassivel":
		menu.add_separator("Muséum de Sire Cassivel")
		_item(menu, cmds, state, player, "backup", {}, "Copie de sauvegarde de Sire Cassivel (%s)" % GameData.format_amounts(Insolites.cfg("cassivel").get("backup_cost", {})))
		var who: Array[int] = []
		for o in e.contacts:
			who.append(int(o))
		if not state.minors.is_empty():
			who.append_array(Minors.met(state, player))
		who.sort()
		for w in who:
			var fid := InsCassivel.species_of(state, w)
			if fid == "" or InsCassivel.species_held(state, player).has(fid):
				continue
			var nm := Minors.name_of(state, w) if GameState.is_npc(w) else state.get_empire(w).short_name()
			_item(menu, cmds, state, player, "acquire", {"w": w}, "Acheter un spécimen à %s (%s)" % [nm, GameData.format_amounts(Insolites.cfg("cassivel").get("buy_cost", {}))])
	_lot4_menu(menu, cmds, state, player, k)
	menu.id_pressed.connect(func(id: int) -> void:
		if id >= 0 and id < cmds.size() and main.has_method("_submit"):
			main.call("_submit", cmds[id])
		menu.queue_free())
	menu.popup_hide.connect(func() -> void:
		if is_instance_valid(menu):
			menu.queue_free.call_deferred())
	main.add_child(menu)
	menu.popup_centered()


## Menu des peuples, lot 4 : Registre et Boucle du Sablier, Consensus et Patience des Lithes, comètes de
## Myrr (rappel), Saisons du Hallier.
static func _lot4_menu(menu: PopupMenu, cmds: Array[Dictionary], state: GameState, player: int, k: String) -> void:
	var e := state.get_empire(player)
	var ed := Insolites.emp(state, player)
	match k:
		"sablier":
			menu.add_separator("Registre (Sable : %d)" % int(ed.get("sand", 0)))
			var reg := InsSablier.ledger(state, player)
			for i in range(reg.size() - 1, -1, -1):
				_item(menu, cmds, state, player, "undo", {"i": i}, "Annuler : %s (%d Sable)" % [InsSablier.entry_text(state, reg[i]), InsSablier.undo_cost(reg[i])])
			menu.add_separator("La Boucle (%d / %d)" % [int(ed.get("loop", 0)), Insolites.c_int("sablier", "loop_stages", 3)])
			_item(menu, cmds, state, player, "loop", {}, "Commencer l'étape suivante (%s)" % GameData.format_amounts(InsSablier.loop_cost(state, player)))
		"gravea":
			menu.add_separator("Consensus séculaire")
			var cons: Dictionary = ed.get("cons", {})
			for o in state.empires:
				if o.id == player or o.is_npc() or o.eliminated or not e.contacts.has(o.id):
					continue
				if cons.has(str(o.id)):
					var i := menu.item_count
					var left := int(cons[str(o.id)]) - state.tick
					menu.add_item("%s : %s" % [o.short_name(), ("délibère encore (%d j)" % left) if left > 0 else "consensus mûr, guerre possible"], -1)
					menu.set_item_disabled(i, true)
					continue
				_item(menu, cmds, state, player, "deliberate", {"t": o.id}, "Délibérer d'une guerre contre %s (deux ans)" % o.short_name())
			menu.add_separator("Patience (%d jours de Temps)" % int(ed.get("time", 0)))
			var works: Array = ed.get("works", [])
			for i in works.size():
				var x: Dictionary = works[i]
				_item(menu, cmds, state, player, "hasten", {"i": i}, "Dépenser le Temps sur l'Œuvre de %s (%d j restants)" % [state.galaxy.systems[int(x["sid"])].system_name, int(x["left"])])
		"myrr":
			menu.add_separator("Comètes-semences (%d en vol)" % (ed.get("comets", []) as Array).size())
			var n := 0
			for sid in state.galaxy.systems.size():
				if n >= 12:
					break
				if InsMyrr.check_comet(state, player, sid) == "":
					_item(menu, cmds, state, player, "comet", {"s": sid}, "Lancer une comète vers %s (%d sauts)" % [state.galaxy.systems[sid].system_name, InsMyrr.comet_range(state, player, sid)])
					n += 1
			if n == 0:
				var i := menu.item_count
				menu.add_item("Aucun système à portée pour l'instant", -1)
				menu.set_item_disabled(i, true)
		"vergemonde":
			menu.add_separator("Saisons du Hallier")
			for s in InsVergemonde.SEASONS:
				_item(menu, cmds, state, player, "season", {"s": String(s)}, "Entrer dans la %s" % String(InsVergemonde.SEASON_LABEL[s]).to_lower())
