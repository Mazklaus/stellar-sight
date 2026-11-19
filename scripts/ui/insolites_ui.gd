class_name InsolitesUi
extends RefCounted
## Peuples insolites côté interface : actions de la fiche de planète (Lune-sentinelle, dévorer, purger un
## implant, l'Arrivée de l'Exode) et menu « Peuple » de la fiche de flotte (chantier embarqué, Pilotes des
## Kraal, délégué au Grand Numéro). Les ordres passent par SimCommands.ins_act.


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
	if c != null and c.owner == player and not Insolites.implant(state, p.id).is_empty() and Insolites.implant_visible(state, p.id, player):
		var df := Insolites.implant_def(String(Insolites.implant(state, p.id)["k"]))
		out.append(WondersUi._act(state, SimCommands.ins_act(player, "purge", d), "Purger le %s" % String(df.get("label", "implant")).to_lower(),
				GameData.format_amounts(df.get("purge_cost", {})),
				"Chasser l'implant d'un autre peuple de cette planète. La stabilité du système souffre quelques mois.", emit))
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
