class_name PsionicsDreamUi
extends RefCounted
## Écran Songe, lot 2 : l'Élu, la Navigation par le Songe, la plongée (trois postures), la Puissance
## qui propose un pacte, le pacte en cours (faveur, palier, prix) et la réforme de l'Élu (voir PsionicsDream).


static func build(es: EmpireScreens, col: VBoxContainer) -> void:
	var state := es._state
	var player := es._player
	var w := 760.0
	# L'Élu.
	var h := PsionicsDream.elu(state, player)
	if not h.is_empty():
		var eb := Widgets.Block.new("L'Élu")
		col.add_child(eb)
		var pat := String(h.get("patron", ""))
		eb.body.add_child(UiTheme.paragraph("%s (%s, niveau %d), puissance 3%s." % [h["name"], String(Heroes.class_def(String(h["cls"])).get("label", h["cls"])), int(h["lvl"]),
				(", Élu de %s" % PsionicsDream.entity_label(pat)) if pat != "" else ""], w, 13))
	# Navigation par le Songe.
	var nd := PsionicsDream.nav()
	if state.get_empire(player).techs.has(String(nd.get("tech", "navigation_songe"))):
		var nb := Widgets.Block.new(String(nd.get("label", "Navigation par le Songe")))
		col.add_child(nb)
		nb.body.add_child(UiTheme.paragraph("%s Coût : %d Résonance ; recharge : %d jours ; fêlure : %d %%." % [String(nd.get("text", "")), PsionicsDream.nav_cost(state, player),
				int(nd.get("cooldown", 120)), PsionicsDream.jump_felure(state, player)], w, 12))
		var shown := 0
		for fid in PsionicsDream.fleet_ids(state):
			var f: Fleet = state.fleets[fid]
			if f.owner != player or f.is_moving() or shown >= 6:
				continue
			shown += 1
			var row := HFlowContainer.new()
			row.add_theme_constant_override("h_separation", 6)
			nb.body.add_child(row)
			var lab := Label.new()
			lab.text = "%s (%s)" % [f.fleet_name, state.galaxy.systems[f.system_id].system_name]
			lab.custom_minimum_size = Vector2(300, 0)
			row.add_child(lab)
			for sid in jump_targets(state, f):
				var why := PsionicsDream.check_jump(state, player, f.id, sid)
				row.add_child(PsionicsScreen._btn(es, state.galaxy.systems[sid].system_name, why, "Plonger dans le Songe et ressortir à %s." % state.galaxy.systems[sid].system_name,
						SimCommands.psi_act(player, "jump", {"fleet": f.id, "sys": sid}), "jump:%d:%d" % [f.id, sid]))
		if shown == 0:
			nb.body.add_child(UiTheme.dim("Aucune flotte à l'arrêt.", 13))
	if not Psionics.full(state):
		return
	# Le Songe : ouverture et plongée.
	var db := Widgets.Block.new("Plonger dans le Songe")
	col.add_child(db)
	if not PsionicsDream.opened(state, player):
		db.body.add_child(UiTheme.paragraph("Ouvrir le Songe coûte %d de Savoir (500, plus 100 par colonie). Ensuite, chaque plongée coûte %d Résonance et demande %d ans de repos." % [
				PsionicsDream.open_cost(state, player), PsionicsDream.dive_cost(state, player), PsionicsDream.dive_years(state, player)], w, 12))
		db.body.add_child(PsionicsScreen._btn(es, "Ouvrir le Songe", PsionicsDream.check_open(state, player), "Projet en Savoir : %d." % PsionicsDream.open_cost(state, player),
				SimCommands.psi_act(player, "open"), "open"))
	else:
		db.body.add_child(UiTheme.paragraph("Une plongée coûte %d Résonance et demande %d ans de repos. Chaque posture tire un bienfait, rien ou une malédiction ; l'audace ouvre les meilleures visions, et les rencontres de Puissances." % [
				PsionicsDream.dive_cost(state, player), PsionicsDream.dive_years(state, player)], w, 12))
		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", 8)
		db.body.add_child(row)
		for p: Dictionary in PsionicsDream.dream().get("postures", []):
			var o: Array = p.get("odds", [0, 0, 0])
			row.add_child(PsionicsScreen._btn(es, "%s (%d/%d/%d)" % [String(p["label"]), int(o[0]), int(o[1]), int(o[2])], PsionicsDream.check_dive(state, player, String(p["id"])),
					"%s\nBienfait %d %%, rien %d %%, malédiction %d %%." % [String(p.get("text", "")), int(o[0]), int(o[1]), int(o[2])],
					SimCommands.psi_act(player, "dive", {"posture": String(p["id"])}), "dive:%s" % String(p["id"])))
	# La Puissance qui attend une réponse.
	var off := PsionicsDream.offer(state, player)
	if not off.is_empty():
		var ob := Widgets.Block.new("Une Puissance propose un pacte")
		col.add_child(ob)
		var ed := PsionicsDream.entity(String(off["p"]))
		ob.body.add_child(UiTheme.paragraph("%s (%s). %s Réponse attendue avant le %s." % [String(ed.get("label", "")), String(ed.get("domain", "")), String(ed.get("text", "")),
				GameCalendar.date_string(int(off["until"]))], w, 13))
		var row2 := HFlowContainer.new()
		row2.add_theme_constant_override("h_separation", 8)
		ob.body.add_child(row2)
		row2.add_child(PsionicsScreen._btn(es, "Pactiser", PsionicsDream.check_pact(state, player, true), _pact_tip(ed), SimCommands.psi_act(player, "pact", {"accept": true}), "pact:yes"))
		row2.add_child(PsionicsScreen._btn(es, "Décliner", PsionicsDream.check_pact(state, player, false), "Le Songe se referme poliment.", SimCommands.psi_act(player, "pact", {"accept": false}), "pact:no"))
	# Le pacte en cours.
	var pc := PsionicsDream.pact(state, player)
	var pb := Widgets.Block.new("Pacte")
	col.add_child(pb)
	if pc.is_empty():
		pb.body.add_child(UiTheme.dim("Aucun pacte. Les Puissances se rencontrent en plongée.", 13))
	else:
		var ed2 := PsionicsDream.entity(String(pc["p"]))
		if PsionicsDream.is_last(String(pc["p"])):
			pb.body.add_child(UiTheme.paragraph("%s : tout, tout de suite, jusqu'au %s. Ensuite, le Solde." % [String(ed2["label"]), GameCalendar.date_string(int(pc.get("until", 0)))], w, 13))
		else:
			var tiers: Array = ed2.get("tiers", [])
			var nxt := ""
			if int(pc.get("tier", 0)) + 1 < tiers.size():
				nxt = " ; palier suivant à %d" % int((tiers[int(pc.get("tier", 0)) + 1] as Dictionary).get("favor", 0))
			pb.body.add_child(UiTheme.paragraph("%s (%s) : faveur %d (+%d par mois), palier %d%s. Effets : %s. Prochain prix le %s." % [String(ed2["label"]), String(ed2.get("domain", "")),
					int(pc["favor"]), PsionicsDream.favor_gain(state, player, ed2), int(pc.get("tier", 0)) + 1, nxt,
					_fx_text((tiers[clampi(int(pc.get("tier", 0)), 0, tiers.size() - 1)] as Dictionary).get("fx", {})) if not tiers.is_empty() else "aucun",
					GameCalendar.date_string(int(pc.get("price", 0)))], w, 13))
		pb.body.add_child(PsionicsScreen._btn(es, "Rompre le pacte", PsionicsDream.check_break(state, player),
				"Stabilité en baisse pendant trois ans.%s" % (" Rompre avec la Dernière Puissance appelle le Solde tout de suite." if PsionicsDream.is_last(String(pc["p"])) else ""),
				SimCommands.psi_act(player, "break"), "break"))
	# La réforme de l'Élu.
	if PsionicsDream.check_reform(state, player) == "":
		var rb := Widgets.Block.new("Le souverain élu")
		col.add_child(rb)
		rb.body.add_child(UiTheme.paragraph("L'Élu de votre Puissance propose de refonder l'empire en théocratie de son culte. Refuser fait des mécontents.", w, 13))
		var row3 := HFlowContainer.new()
		row3.add_theme_constant_override("h_separation", 8)
		rb.body.add_child(row3)
		row3.add_child(PsionicsScreen._btn(es, "Accepter", "", "Le gouvernement devient une théocratie.", SimCommands.psi_act(player, "reform", {"accept": true}), "reform:yes"))
		row3.add_child(PsionicsScreen._btn(es, "Refuser", "", "Stabilité en baisse pendant deux ans.", SimCommands.psi_act(player, "reform", {"accept": false}), "reform:no"))


static func _pact_tip(ed: Dictionary) -> String:
	if ed.has("fx"):
		return "Effets : %s pendant %d ans. Puis le Solde." % [_fx_text(ed["fx"]), int(ed.get("last_years", 50))]
	var parts := PackedStringArray()
	for t: Dictionary in ed.get("tiers", []):
		parts.append("faveur %d : %s" % [int(t.get("favor", 0)), _fx_text(t.get("fx", {}))])
	return "Paliers : %s. Un prix tous les quinze ans environ." % " ; ".join(parts)


static func _fx_text(fx: Dictionary) -> String:
	var parts := PackedStringArray()
	for k in fx:
		var v: Variant = fx[k]
		if v is Dictionary:
			for r in v:
				parts.append("%s %s %+d %%" % [k.replace("_pct", ""), r, int(v[r])])
		else:
			parts.append("%s %+d" % [k, int(v)])
	return ", ".join(parts) if not parts.is_empty() else "aucun"


## Destinations proposées pour un saut : jusqu'à six systèmes à portée, les plus lointains d'abord.
static func jump_targets(state: GameState, f: Fleet) -> Array:
	var mx := int(PsionicsDream.nav().get("max_jumps", 4))
	var jumps := FactionTraits.jumps_from(state.galaxy, f.system_id)
	var cands := []
	for sid in jumps:
		var j := int(jumps[sid])
		if j >= 2 and j <= mx:
			cands.append([-j, int(sid)])
	cands.sort()
	var out := []
	for c in cands:
		if out.size() >= 6:
			break
		out.append(int(c[1]))
	return out


static func fx_label(state: GameState, fx: Dictionary) -> String:
	match String(fx["id"]):
		"voix":
			return "La Voix : %s" % state.get_empire(int(fx["target"])).display_name()
		"boon":
			return "Bienfait du Songe : %s" % String(fx.get("label", ""))
		"curse":
			return "Malédiction du Songe : %s" % String(fx.get("label", ""))
		"price":
			return "Prix du pacte : %s" % String(fx.get("label", ""))
	return String(fx.get("label", fx["id"]))


## Cibles des pouvoirs du lot 2 (Domination : systèmes ennemis où mouille un stratège sensitif).
static func targets(state: GameState, player: int, p: Dictionary, out: Array) -> Array:
	if String(p.get("target", "")) == "enemy_system":
		var seen := {}
		for fid in PsionicsDream.fleet_ids(state):
			var f: Fleet = state.fleets[fid]
			if f.owner != player or seen.has(f.system_id):
				continue
			var o := state.system_owner(f.system_id)
			if o >= 0 and o != player and Combat.at_war(state, player, o):
				seen[f.system_id] = true
				out.append([f.system_id, state.galaxy.systems[f.system_id].system_name])
	return out
