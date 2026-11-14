class_name FaithNaturePanel
extends RefCounted
## Bloc « nature » de l'écran Foi (lot 3) : la jauge et les gestes propres à la nature classique
## de la foi d'État (Collège et bulles, icônes, piété et écoles, karma, harmonie, panthéon,
## ancêtres, Dette de sang, Dieu présent) puis des natures lourdes du lot 4 (oracles, chantier du dieu,
## horloge de la fin, Communion, systèmes sacrés), et le bloc des vocations de foi des héros.
## Sobre : la refonte d'interface viendra plus tard.


static func build(es: EmpireScreens) -> Control:
	var state := es._state
	var player := es._player
	var sf := Faiths.state_faith(state, player)
	var nat := FaithNatures.emp_nature(state, player)
	if not FaithNatures.CLASSIC.has(nat) and not FaithHeavy.HEAVY.has(nat):
		return null
	var c := FaithNatures.cd()
	var nd := FaithWars.nature_def(nat)
	var b := Widgets.Block.new(String(nd.get("label", nat)))
	b.body.add_child(UiTheme.paragraph(String(nd.get("text", "")), 760.0, 13))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 10)
	flow.add_theme_constant_override("v_separation", 6)
	var add := func(key: String, text: String, act: String, args: Dictionary, tip: String) -> void:
		var btn := FaithScreen._btn(text, FaithNatures.check(state, player, act, args), tip)
		btn.pressed.connect(func() -> void: es.command_requested.emit(SimCommands.faith_nat(player, act, args)))
		flow.add_child(btn)
		es.faith_buttons["nat:" + key] = btn
	match nat:
		"eglise_universelle":
			var fd := FaithNatures._peek_faith(state, sf)
			var pe := state.get_empire(Faiths.head(state, sf))
			b.body.add_child(UiTheme.dim("Collège : %d / %d sièges pris, %d à vous. Primat : %s, jusqu'au %s. Désir de réforme : %d / 100." % [
					FaithNatures.seats_taken(state, sf), int(c["eglise"]["seats"]), int(fd.get("seats", {}).get(str(player), 0)),
					pe.short_name() if pe != null else "aucun", GameCalendar.date_string(int(fd.get("term_end", 0))), FaithNatures.reform(state, sf)], 13))
			var bl: Dictionary = fd.get("bull", {})
			if not bl.is_empty() and int(bl["end"]) > state.tick:
				b.body.add_child(UiTheme.dim("Bulle en vigueur : %s, jusqu'au %s." % [String(c["eglise"]["bulls"][String(bl["kind"])]["label"]), GameCalendar.date_string(int(bl["end"]))], 13))
			add.call("seat", "Acheter un siège", "seat", {}, "Un siège de plus au Collège (%s). Le plus de sièges fait le Primat à l'élection." % GameData.format_amounts(FaithNatures.seat_cost(state, sf, player)))
			for k in c["eglise"]["bulls"]:
				var bd: Dictionary = c["eglise"]["bulls"][k]
				add.call("bull:" + String(k), "Bulle : %s" % String(bd["label"]), "bull", {"kind": String(k)}, String(bd["text"]) + " Cinq ans ; +%d de désir de réforme." % int(c["eglise"]["reform_bull"]))
		"patriarcats":
			var ed := FaithNatures._peek_emp(state, player)
			var line := "Autorité patriarcale : %d / 100." % FaithNatures.authority(state, player)
			var ic: Dictionary = ed.get("icon", {})
			if not ic.is_empty() and int(ic["end"]) > state.tick:
				line += " Icône vénérée : %s, jusqu'au %s." % [String(c["patriarcats"]["icons"][String(ic["kind"])]["label"]), GameCalendar.date_string(int(ic["end"]))]
			var m := int(ed.get("metro", -1))
			if m >= 0:
				line += " Métropolite : %s." % state.galaxy.get_planet(m).display_name(state.galaxy)
			b.body.add_child(UiTheme.dim(line, 13))
			for k in c["patriarcats"]["icons"]:
				var idf: Dictionary = c["patriarcats"]["icons"][k]
				add.call("icon:" + String(k), String(idf["label"]), "icon", {"kind": String(k)}, "Vingt ans : %s (%d d'autorité)." % [Relics.fx_text(idf.get("fx", {})) if not idf.get("fx", {}).is_empty() else "+%d de stabilité" % int(idf.get("stab", 0)), int(c["patriarcats"]["icon_cost"])])
			var n := 0
			for pid in state.sorted_colony_ids():
				if n >= 4:
					break
				if FaithNatures.check(state, player, "metro", {"planet": pid}) == "":
					add.call("metro:%d" % pid, "Métropolite à %s" % state.galaxy.get_planet(pid).display_name(state.galaxy), "metro", {"planet": pid},
							"La colonie prêche %d fois plus fort, comme un petit monde saint (%d d'autorité)." % [int(c["patriarcats"]["metro_x"]), int(c["patriarcats"]["metro_cost"])])
					n += 1
		"loi_extase":
			var p := FaithNatures.piety(state, player)
			var th := int(c["loi_extase"]["threshold"])
			var where := "Voie de la Loi (stabilité, lois moins chères)" if p >= th else ("Voie de l'Extase (missions moins chères, héros plus vite aguerris)" if p <= -th else "entre les deux voies, sans bonus")
			var sc := FaithNatures.school(state, player)
			b.body.add_child(UiTheme.dim("Piété : %d (de -100, Extase, à +100, Loi) : %s. École : %s." % [p, where, String(c["loi_extase"]["schools"].get(sc, {}).get("label", "aucune"))], 13))
			for k in c["loi_extase"]["schools"]:
				var sd: Dictionary = c["loi_extase"]["schools"][k]
				add.call("school:" + String(k), String(sd["label"]), "school", {"school": String(k)},
						"%s Estime l'%s, rejette l'%s. Un changement tous les dix ans." % [String(sd["text"]), String(c["loi_extase"]["schools"][String(sd["esteems"])]["label"]).to_lower(), String(c["loi_extase"]["schools"][String(sd["rejects"])]["label"]).to_lower()])
		"karma":
			var k := FaithNatures.karma(state, player)
			var bal := int(c["karma"]["balance"])
			var where := "en équilibre (stabilité, estime des fidèles)" if absi(k) <= bal else ("lumineux (tout le monde vous aime, mais la guerre coûte de la stabilité)" if k > 0 else "sombre (+10 % de dégâts, on se méfie de vous)")
			b.body.add_child(UiTheme.dim("Karma : %d, %s. La paix et les libérations l'élèvent ; guerres, conquêtes et exterminations l'abaissent." % [k, where], 13))
		"harmonie":
			var ed := FaithNatures._peek_emp(state, player)
			var extra: Array = FaithNatures._peek_faith(state, sf).get("extra", [])
			var names := []
			for pid in extra:
				names.append(String(Faiths.precept_def(String(pid)).get("label", pid)))
			b.body.add_child(UiTheme.dim("Harmonie : %d / 100 (à %d et plus, les autres fois ne coûtent pas de stabilité). Préceptes harmonisés : %s." % [
					FaithNatures.harmony(state, player), int(c["harmonie"]["threshold"]), ", ".join(names) if not names.is_empty() else "aucun"], 13))
			for h: Dictionary in ed.get("harm", []):
				b.body.add_child(UiTheme.dim("Harmonisation de %s en cours, jusqu'au %s." % [Faiths.name_of(state, String(h["fid"])), GameCalendar.date_string(int(h["end"]))], 13))
			for fid in Faiths.ids(state):
				if fid == sf:
					continue
				for pid in Faiths.faith(state, fid).get("precepts", []):
					var args := {"faith": fid, "precept": String(pid)}
					if FaithNatures.check(state, player, "harmonize", args) == "":
						add.call("harm:%s:%s" % [fid, pid], "Harmoniser %s (%s)" % [Faiths.name_of(state, fid), String(Faiths.precept_def(String(pid)).get("label", pid))], "harmonize", args,
								"Dix ans : la foi cesse d'être hostile et votre foi gagne ce précepte (%d d'harmonie)." % int(c["harmonie"]["cost"]))
		"pantheon":
			var fd := FaithNatures._peek_faith(state, sf)
			var gods: Array = fd.get("gods", [])
			var gl := []
			for g in gods:
				gl.append(String(c["pantheon"]["domains"].get(String(g), {}).get("label", g)))
			var line := "Panthéon : %s." % ", ".join(gl)
			var hg: Dictionary = fd.get("hero_god", {})
			if not hg.is_empty():
				line += " Héros divinisé : %s." % String(hg["name"])
			var wl := []
			for w in fd.get("welcome", []):
				wl.append(Faiths.name_of(state, String(w)))
			if not wl.is_empty():
				line += " Dieux accueillis : %s." % ", ".join(wl)
			b.body.add_child(UiTheme.dim(line, 13))
			for g in gods:
				var gd: Dictionary = c["pantheon"]["domains"][String(g)]
				add.call("omen:" + String(g), "Présage : %s" % String(gd["label"]), "omen", {"kind": String(g)},
						"Un an : effet du dieu triplé (%s), %d de zèle. Un présage tous les cinq ans." % [Relics.fx_text(gd["fx"]), -int(c["pantheon"]["omen_zeal"])])
			var opt := OptionButton.new()
			opt.focus_mode = Control.FOCUS_NONE
			var free := []
			for d in c["pantheon"]["domains"]:
				if not gods.has(d):
					free.append(String(d))
					opt.add_item(String(c["pantheon"]["domains"][d]["label"]))
			if not free.is_empty() and Faiths.head(state, sf) == player:
				flow.add_child(opt)
				for g in gods:
					var old := String(g)
					var sb := FaithScreen._btn("Détrôner : %s" % String(c["pantheon"]["domains"][old]["label"]), "",
							"Remplace ce dieu par celui choisi (stabilité %d pendant un an)." % int(c["pantheon"]["swap_stab"]))
					sb.pressed.connect(func() -> void:
						if opt.selected >= 0 and opt.selected < free.size():
							es.command_requested.emit(SimCommands.faith_nat(player, "god_swap", {"old": old, "new": String(free[opt.selected])})))
					flow.add_child(sb)
			for fid in Faiths.ids(state):
				if fid != sf and FaithNatures.check(state, player, "welcome", {"faith": fid}) == "":
					add.call("welcome:" + fid, "Accueillir le dieu de %s" % Faiths.name_of(state, fid), "welcome", {"faith": fid},
							"Ses fidèles ne coûtent plus de stabilité chez vous, mais se convertissent moins vite.")
		"ancetres":
			var names := []
			for a in FaithNatures.active_ancestors(state, player):
				names.append(String(a["name"]))
			var line := "Ancêtres actifs : %s." % (", ".join(names) if not names.is_empty() else "aucun (un héros mort rejoint les ancêtres)")
			if not FaithNatures.has_mausoleum(state, player):
				line += " Sans mausolée (capitale ou monde saint), les ancêtres dorment."
			b.body.add_child(UiTheme.dim(line, 13))
		"dette_sang":
			var dd: Dictionary = c["dette"]
			b.body.add_child(UiTheme.dim("Dette de sang : %d / %d. À %d et moins : +10 %% de dégâts et du zèle. À %d, un héros du chef de foi est sacrifié. Vaisseaux ennemis détruits, invasions et offrandes la paient." % [
					FaithNatures.debt(state, sf), int(dd["max"]), int(dd["low"]), int(dd["max"])], 13))
			var cap: Colony = state.colonies.get(state.get_empire(player).capital_planet)
			if cap != null:
				add.call("offer", "Offrande à %s" % state.galaxy.get_planet(cap.planet_id).display_name(state.galaxy), "offer", {"planet": cap.planet_id},
						"Un habitant est offert au dieu : %d de dette." % int(dd["offer"]))
		"dieu_present":
			_god(es, b, add, sf)
		"chronolatrie":
			var o := FaithHeavy.oracle(state, sf)
			if o.is_empty():
				var nx := int(FaithNatures._peek_faith(state, sf).get("oracle_next", 0))
				b.body.add_child(UiTheme.dim("Aucun oracle en attente. Prochaine lecture du temps vers le %s (une élection ou une flotte en route)." % GameCalendar.date_string(nx), 13))
			else:
				b.body.add_child(UiTheme.dim("Oracle : %s Accompli, il donne du zèle ; l'empire qui le fait mentir verra ses fidèles faire sécession." % _cap1(FaithHeavy.oracle_text(state, o)), 13))
		"dieu_en_chantier":
			var stg: Array = FaithHeavy.hd()["chantier"]["stages"]
			var k := FaithHeavy.stage(state, sf)
			var labels := []
			for i in stg.size():
				labels.append(("✓ " if i < k else "") + String(stg[i]["label"]))
			b.body.add_child(UiTheme.dim("Étages : %s (%d sur %d)." % [", ".join(labels), k, stg.size()], 13))
			var bld: Dictionary = FaithNatures._peek_faith(state, sf).get("build", {})
			if not bld.is_empty():
				b.body.add_child(UiTheme.dim("En chantier : %s, achevé le %s." % [String(stg[k]["label"]), GameCalendar.date_string(int(bld["end"]))], 13))
			if k < stg.size():
				add.call("stage", "Bâtir : %s" % String(stg[k]["label"]), "stage", {},
						"%s, %d jours. Pouvoir : %s." % [GameData.format_amounts(FaithHeavy.stage_cost(state, sf, player)), int(stg[k]["days"]),
						Relics.fx_text(stg[k].get("fx", {})) + (" ; le dieu s'éveille" if k == stg.size() - 1 else "")])
			else:
				if FaithHeavy.disobeys(state, sf):
					b.body.add_child(UiTheme.dim("Le zèle est tombé sous %d : le dieu n'obéit plus, il erre et trouble les mondes autour de lui." % int(FaithHeavy.hd()["chantier"]["obey_zeal"]), 13))
				_god(es, b, add, sf)
		"entropisme":
			var ed: Dictionary = FaithHeavy.hd()["entropie"]
			var ge := int(FaithNatures._peek_faith(state, sf).get("glory_end", 0))
			if ge > 0:
				b.body.add_child(UiTheme.dim("La Fin du cycle : vos fidèles sont la colère de l'univers jusqu'au %s (%s). Ensuite, la foi s'éteint." % [GameCalendar.date_string(ge), Relics.fx_text(ed["glory_fx"])], 13))
			else:
				b.body.add_child(UiTheme.dim("Horloge de la fin : %d / %d, visible de tous. Elle avance chaque mois, et plus vite avec les vaisseaux ennemis détruits, les créatures tuées et les conquêtes." % [FaithHeavy.clock(state, sf), int(ed["end"])], 13))
		"communion":
			var mem := FaithNatures.members(state, sf)
			var names := []
			for eid in mem:
				names.append(state.get_empire(eid).short_name())
			var pull := int(FaithNatures._peek_faith(state, sf).get("pull", {}).get(str(player), 0))
			b.body.add_child(UiTheme.dim("En communion : %s. Chacun verse %d %% de sa production au fonds commun, partagé à parts égales ; la stabilité tire vers la moyenne (%+d pour vous)." % [
					", ".join(names), int(FaithHeavy.hd()["communion"]["share_pct"]), pull], 13))
		"astres_vivants":
			var names := []
			for s2 in FaithHeavy.sacred(state, sf):
				names.append(state.galaxy.systems[int(s2)].system_name + (" (avatar)" if Guardians.awake_at(state, int(s2)) != "" else ""))
			var prof := []
			for eid in FaithNatures._peek_faith(state, sf).get("profaners", []):
				prof.append(state.get_empire(int(eid)).short_name())
			b.body.add_child(UiTheme.dim("Systèmes sacrés : %s. Ils prêchent comme des mondes saints ; un avant-poste ou une mine y profane les Astres%s." % [
					", ".join(names), (" (profanateurs : %s)" % ", ".join(prof)) if not prof.is_empty() else ""], 13))
	if flow.get_child_count() > 0:
		b.body.add_child(flow)
	return b


static func _cap1(s: String) -> String:
	return s.left(1).to_upper() + s.substr(1) if s != "" else s


## Le dieu qui marche (Dieu présent, Dieu en chantier achevé) : où il est, et où le guider.
static func _god(es: EmpireScreens, b: Widgets.Block, add: Callable, sf: String) -> void:
	var state := es._state
	var player := es._player
	var c := FaithNatures.cd()
	var g := FaithNatures.live_god(state, sf)
	var raw: Dictionary = FaithNatures._peek_faith(state, sf).get("god", {})
	if g.is_empty():
		b.body.add_child(UiTheme.dim("Le dieu n'est plus parmi nous ; il reviendra au monde saint le %s." % GameCalendar.date_string(int(raw.get("dead_until", 0))), 13))
	else:
		var host := state.get_empire(Faiths.head(state, sf))
		b.body.add_child(UiTheme.dim("%s se trouve à %s (hôte : %s). Son dominion (%d sauts) prêche fort et affaiblit les flottes ennemies de son hôte." % [
				_cap1(String(g["name"])), state.galaxy.systems[int(g["sid"])].system_name, host.short_name() if host != null else "personne", int(c["dieu"]["dominion"])], 13))
		var cap := state.galaxy.get_planet(state.get_empire(player).capital_planet).system_id if state.get_empire(player).capital_planet >= 0 else -1
		if cap >= 0 and cap != int(g["sid"]):
			add.call("god_home", "Ramener le dieu à la capitale", "god_move", {"system": cap}, "Il avance d'un saut par mois.")
		var dist := FactionTraits.jumps_from(state.galaxy, int(g["sid"]))
		var n := 0
		for s in state.galaxy.systems.size():
			if n >= 4:
				break
			if int(dist.get(s, 99)) == 3 and state.system_owner(s) >= 0 and state.system_owner(s) != player and FaithNatures.check(state, player, "god_move", {"system": s}) == "":
				add.call("god:%d" % s, "Guider le dieu vers %s" % state.galaxy.systems[s].system_name, "god_move", {"system": s}, "Il avance d'un saut par mois ; sans escorte face à un ennemi, il peut mourir.")
				n += 1


## Bloc « Héros de foi » : les héros à l'ambition Foi reçoivent une vocation (commande faith_voc).
static func vocations(es: EmpireScreens) -> Control:
	var state := es._state
	var player := es._player
	if Faiths.faith(state, Faiths.state_faith(state, player)).is_empty():
		return null
	var bdg := FaithBridges.bd()
	var heroes := []
	var named := []
	for hid in Heroes.ids_of(state, player):
		var h: Dictionary = state.heroes[hid]
		if Heroes.is_prisoner(h):
			continue
		if FaithBridges.vocation(h) != "":
			named.append("%s (%s)" % [String(h["name"]), String(bdg["vocations"][FaithBridges.vocation(h)]["label"])])
		elif String(h.get("amb", "")) == String(bdg["vocation_amb"]):
			heroes.append(h)
	if heroes.is_empty() and named.is_empty():
		return null
	var b := Widgets.Block.new("Héros de foi")
	b.body.add_child(UiTheme.dim("Un héros à l'ambition Foi peut entendre l'appel (%s, une vocation de chaque par empire ; elle n'agit que s'il est en poste). Vocations : %s." % [
			GameData.format_amounts(bdg["vocation_cost"]), ", ".join(named) if not named.is_empty() else "aucune"], 13))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 10)
	flow.add_theme_constant_override("v_separation", 6)
	for h in heroes:
		for v in bdg["vocations"]:
			var vd: Dictionary = bdg["vocations"][v]
			var hid := int(h["id"])
			var btn := FaithScreen._btn("%s : %s" % [String(h["name"]), String(vd["label"])], FaithBridges.check_voc(state, player, hid, String(v)), String(vd.get("text", "")))
			btn.pressed.connect(func() -> void: es.command_requested.emit(SimCommands.faith_voc(player, hid, String(v))))
			flow.add_child(btn)
			es.faith_buttons["voc:%d:%s" % [hid, String(v)]] = btn
	if flow.get_child_count() > 0:
		b.body.add_child(flow)
	return b
