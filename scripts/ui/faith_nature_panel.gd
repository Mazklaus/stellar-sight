class_name FaithNaturePanel
extends RefCounted
## Bloc « nature » de l'écran Foi (lot 3) : la jauge et les gestes propres à la nature classique
## de la foi d'État (Collège et bulles, icônes, piété et écoles, karma, harmonie, panthéon,
## ancêtres, Dette de sang, Dieu présent). Sobre : la refonte d'interface viendra plus tard.


static func build(es: EmpireScreens) -> Control:
	var state := es._state
	var player := es._player
	var sf := Faiths.state_faith(state, player)
	var nat := FaithNatures.emp_nature(state, player)
	if not FaithNatures.CLASSIC.has(nat):
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
	if flow.get_child_count() > 0:
		b.body.add_child(flow)
	return b


static func _cap1(s: String) -> String:
	return s.left(1).to_upper() + s.substr(1) if s != "" else s
