class_name TranscendenceUiExtra
extends RefCounted
## Écran Transcendance, parties du monde (lot 2) : les Restants et le Renoncement dans le panneau ;
## Lieux minces, ruines à fouiller et les Partis dans le contenu.


static func side(es: EmpireScreens) -> Array[Control]:
	var out: Array[Control] = []
	var state := es._state
	var player := es._player
	if not Transcendence.full(state):
		return out
	var w := EmpireScreens.SIDE_WIDTH - 24.0
	var r := TranscendenceWorld.restants(state, player)
	if r > 0 or Transcendence.path_of(state, player) != "":
		out.append(UiTheme.paragraph("Les Restants : %d / 100 (vers %d)%s" % [r, TranscendenceWorld.restants_target(state, player),
				" ; ils gèlent la jauge" if TranscendenceWorld.frozen(state, player) else ""], w, 12))
	var st := TranscendenceWorld.renoncement_steps(state, player)
	if st > 0:
		out.append(UiTheme.paragraph("Renoncement : production %+d %%, stabilité %+d" % [st * Transcendence.c_int("renoncement", "prod_pct", -5), st * Transcendence.c_int("renoncement", "stab", 5)], w, 12))
	return out


static func content(es: EmpireScreens, col: VBoxContainer) -> void:
	var state := es._state
	var player := es._player
	if not Transcendence.full(state):
		return
	var me := state.get_empire(player)
	var mb := Widgets.Block.new("Lieux minces")
	col.add_child(mb)
	var any := false
	for sid in TranscendenceWorld.minces(state):
		if not (es.see_all or me.explored.has(sid)):
			continue
		any = true
		var o := state.system_owner(sid)
		var who := "libre" if o < 0 else (state.get_empire(o).short_name() if state.get_empire(o) != null else "?")
		mb.body.add_child(UiTheme.paragraph("%s : %s" % [state.galaxy.systems[sid].system_name, who], 760.0, 13))
	if not any:
		mb.body.add_child(UiTheme.dim("Aucun Lieu mince exploré. Il y en a quelque part, loin des capitales.", 13))
	var ids := TranscendenceWorld.partis_ids(state)
	if not ids.is_empty():
		var pb := Widgets.Block.new("Les Partis")
		col.add_child(pb)
		for pid in ids:
			var pd := TranscendenceWorld.parti(state, pid)
			var aid := int((pd.get("aid", {}) as Dictionary).get(str(player), 0))
			pb.body.add_child(UiTheme.paragraph("%s (%s, partis le %s) : %s" % [String(pd.get("name", "")), Transcendence.path_label(String(pd.get("path", ""))).to_lower(),
					GameCalendar.date_string(int(pd.get("tick", 0))), "ils se souviennent de votre aide" if aid > 0 else ("ils se souviennent de vous, et pas en bien" if aid < 0 else "vous leur êtes indifférent")], 760.0, 13))
		var n := Transcendence.sub(state, "ruins").size()
		if n > 0:
			pb.body.add_child(UiTheme.dim("%d monde%s délaissé%s à fouiller : coloniser l'un d'eux rend ses bâtiments et une relique de savoir." % [n, "s" if n > 1 else "", "s" if n > 1 else ""], 13))
