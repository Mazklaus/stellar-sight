class_name LivingUi
extends RefCounted
## Mondes vivants dans la vue système (prop. 30-31 ; voir LivingWorlds) : pas d'écran à part. La fiche de
## la planète dit son nom, son origine, son tempérament, son humeur envers vous (un « ? » tant qu'une
## Énigme n'a pas été écoutée), ses goûts si vos sensitifs l'ont écoutée et sa demande en cours ; les
## ordres (inviter, écouter, cueillir une nef-graine, fusionner) rejoignent la liste des actions.


## Lignes ajoutées à la fiche d'une planète (vides si ce n'est pas un monde vivant connu du joueur).
static func lines(state: GameState, player: int, p: Planet) -> Array[String]:
	var out: Array[String] = []
	if state == null or state.living.is_empty() or p == null or not LivingWorlds.is_living(state, p.id):
		return out
	var spectator := player < 0
	if not spectator and not LivingWorlds.knows(state, p.id, player):
		return out
	var w := LivingWorlds.world(state, p.id)
	var od := LivingWorlds.origin_def(String(w["o"]))
	var td := LivingWorlds.temper_def(String(w["t"]))
	if int(w.get("ego", 0)) == 1:
		out.append("Monde vivant : %s, le Monde affamé. Il transforme ses voisins ; seul un feu concentré sur son noyau l'arrêtera." % LivingWorlds.name_of(state, p.id))
		return out
	out.append("Monde vivant : %s (%s, %s)" % [LivingWorlds.name_of(state, p.id), String(od.get("label", "?")), String(td.get("label", "?")).to_lower()])
	if spectator:
		for e in state.empires:
			if not e.is_npc() and not e.eliminated:
				out.append("  %s : %s (%d)" % [e.short_name(), String(LivingWorlds.tier(state, p.id, e.id).get("label", "")), LivingWorlds.mood(state, p.id, e.id)])
		return out
	if LivingWorlds.mood_known(state, p.id, player):
		var t := LivingWorlds.tier(state, p.id, player)
		out.append("Humeur envers vous : %s (%+d)" % [String(t.get("label", "")), LivingWorlds.mood(state, p.id, player)])
	else:
		out.append("Humeur envers vous : ? (une Énigme : il faut l'écouter)")
	if (w["deep"] as Dictionary).has(str(player)):
		var fav := String(w.get("fav", ""))
		var nope := String(w.get("nope", ""))
		out.append("Il aime les %s ; il supporte mal les %s." % [Peoples.label(fav) if fav != "" else "peuples variés", Peoples.label(nope) if nope != "" else "personne"])
	var req: Dictionary = w.get("req", {})
	if not req.is_empty() and int(req.get("e", -1)) == player:
		out.append("Demande en cours : %s" % String((LivingWorlds.cfg("requests").get(String(req["k"]), {}) as Dictionary).get("label", "?")))
	if int(w.get("fused", -1)) == player:
		out.append("Fusionné avec votre peuple : personne ne part, et il refuse vos guerres contre ses amis.")
	if LivingWorlds.hates(state, p.id, player):
		out.append("Il vous est Hostile : il rejette vos colons et lâche ses anticorps sur vos flottes.")
	return out


## Ordres sur un monde vivant (vue système).
@warning_ignore("integer_division")
static func system_actions(state: GameState, player: int, p: Planet, emit: Callable) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if state == null or state.living.is_empty() or player < 0 or not LivingWorlds.is_living(state, p.id) or not LivingWorlds.knows(state, p.id, player):
		return out
	var d := {"p": p.id}
	var nm := LivingWorlds.name_of(state, p.id)
	if not state.colonies.has(p.id) and LivingWorlds.mood(state, p.id, player) >= LivingWorlds.r_int("invite_min", 25):
		out.append(WondersUi._act(state, SimCommands.living_act(player, "invite", d), "Inviter %s chez vous" % nm,
				GameData.format_amounts(LivingWorldsWar.invite_cost(state, player)),
				"Le monde quitte son système et vient se poser dans le plus proche des vôtres. Il faut qu'il vous soit au moins Bienveillant.", emit))
	if not (LivingWorlds.world(state, p.id)["deep"] as Dictionary).has(str(player)) or LivingWorlds.check(state, player, "listen", d) == "":
		out.append(WondersUi._act(state, SimCommands.living_act(player, "listen", d), "Écouter %s" % nm,
				"%d de Résonance" % LivingWorlds.r_int("listen_cost", 30),
				"Vos sensitifs écoutent le monde : vous saurez ce qu'il aime, ce qu'il déteste et ce qu'il pense de vous (humeur +%d)." % LivingWorlds.r_int("listen_mood", 10), emit))
	if LivingWorlds.host(state, p.id) == player and LivingWorlds.tier_index(state, p.id, player) >= 4:
		out.append(WondersUi._act(state, SimCommands.living_act(player, "seed", d), "Cueillir une nef-graine",
				"vaisseau vivant", "Un monde Lié offre à ses hôtes un vaisseau vivant qui se répare partout (%d au plus)." % LivingWorlds.r_int("seed_max", 3), emit))
		if int(LivingWorlds.world(state, p.id).get("fused", -1)) < 0:
			out.append(WondersUi._act(state, SimCommands.living_act(player, "fuse", d), "Fusionner avec %s" % nm,
					"irréversible", "Après %d ans de lien, la colonie et le monde ne font plus qu'un : population, production et stabilité en hausse, personne ne part plus, et le monde refuse vos guerres contre les empires qu'il aime." % (LivingWorlds.r_int("fuse_days", 3600) / 360), emit))
	return out
