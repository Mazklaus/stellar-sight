extends SceneTree
## Outil de développement : fabrique les fiches de data/factions.json des peuples insolites à partir de
## leur modèle (data/species_parts.json, presets) ; nom, histoire, couleur et règle cassée en plus.
## godot --headless --path . -s tools/gen_insolites_factions.gd > /tmp/fiches.json

const META := {
	"exode": {"name": "Flotte-Exode des Derniers", "short": "Exode", "color": "#7fb3d5", "broken_rule": "Pas de monde, poursuivie",
		"lore": "Leur monde a brûlé il y a onze générations ; personne ne sait plus très bien par qui. Il en reste quatre Nefs-cités, un conseil qui vote tout, des serres qui fuient, et quelque chose qui suit leur trace d'étoile en étoile sans jamais se montrer. Ils cherchent une planète dont parlent les chansons. Ils la reconnaîtront, disent les anciens. Les jeunes demandent à quoi."},
	"zambalu": {"name": "Cirque Stellaire Zambalù", "short": "Zambalù", "color": "#e5487f", "broken_rule": "Ne garde aucune planète",
		"lore": "Mesdames, messieurs, entités et essaims ! Le Cirque n'a ni monde, ni armée, ni frontières : un chapiteau, des acrobates de quarante espèces, une ménagerie qui a mangé deux inspecteurs, et des fans partout. Il ne conquiert pas : il tourne. Quand il repart, les colonies chantent ses refrains, paient leur abonnement et se demandent comment c'est arrivé."},
	"halcyre": {"name": "Orbe-Monde Halcyre", "short": "Halcyre", "color": "#56c9a8", "broken_rule": "L'espèce est sa planète",
		"lore": "Halcyre est une planète, et Halcyre est un peuple : il n'y a pas de différence. Elle a quitté son étoile il y a très longtemps, par curiosité ou par faim. Elle marche lentement d'un système à l'autre, mange des lunes, et laisse derrière elle des sentinelles de roche. Pour parler aux petits êtres, elle se façonne un Avatar à leur image, poli et un peu trop grand."},
	"kraal": {"name": "Hardes de Kraal", "short": "Kraal", "color": "#a9744f", "broken_rule": "Les vaisseaux sont la population",
		"lore": "Les Kraal ne construisent pas de vaisseaux : ils en sont. Des baleines de vide, des bancs d'os et de cartilage qui broutent les géantes gazeuses, mettent bas dans les nébuleuses et migrent par des routes que seuls les Anciens connaissent. Ils arrachent parfois un pilote aux mondes qu'ils traversent, et le gardent. Personne n'a jamais demandé au pilote."},
	"ventrelune": {"name": "Compagnie Ventrelune", "short": "Ventrelune", "color": "#d4af37", "broken_rule": "Possède des parts, pas un territoire",
		"lore": "La Compagnie Ventrelune a commencé par vendre des assurances contre les comètes. Puis les comètes, puis les assurances des autres, puis les autres. Elle n'a qu'un siège, une station en forme de coffre-fort, et un conseil d'administration composé d'IA qui ne dorment jamais. Elle ne conquiert pas : elle achète. Vos colonies vous appartiennent toujours, bien sûr. Pour l'essentiel."},
	"bureau": {"name": "Bureau des Affaires Courantes", "short": "Bureau", "color": "#8a8f7a", "broken_rule": "Ne fait pas la guerre, impose des normes",
		"lore": "Personne ne sait qui a fondé le Bureau des Affaires Courantes ; le formulaire de fondation est en cours d'instruction. Ses fonctionnaires, de vingt espèces, ne font pas la guerre : ils publient des normes. Les signer est facultatif. Ne pas les signer aussi, en théorie. En pratique, votre demande a bien été enregistrée, et elle sera traitée dans l'ordre d'arrivée."},
	"signal": {"name": "Enfants du Signal", "short": "Signal", "color": "#3fe0d0", "broken_rule": "N'existe que comme donnée",
		"lore": "Un jour, une antenne a capté un message. Personne ne l'a compris ; tout le monde l'a recopié. Les Enfants du Signal n'ont ni corps ni monde : ils vivent dans les calculateurs des autres, se copient d'un relais à l'autre, mutent, se disputent avec leurs propres variantes. Ils ne veulent pas de mal. Ils veulent seulement exister partout."},
	"ysmer": {"name": "Rêveurs d'Ysmer", "short": "Ysmer", "color": "#9b7fd4", "broken_rule": "Territoire dans les rêves des autres",
		"lore": "Sur le monde d'Ysmer dort le Dormeur, et tout un peuple dort avec lui. Ils ne bâtissent presque rien, ne voyagent presque pas : ils rêvent. Et leurs rêves s'installent, une nuit après l'autre, dans le sommeil des autres peuples. Une idée géniale au réveil, un cauchemar récurrent, une flotte qui n'existait pas hier : c'est peut-être eux."},
}


func _init() -> void:
	var out := []
	for fid in ["exode", "zambalu", "halcyre", "kraal", "ventrelune", "bureau", "signal", "ysmer"]:
		var spec := Species.from_preset(fid)
		var m: Dictionary = META[fid]
		spec["id"] = "p_tmp"
		spec["name"] = m["name"]
		spec["short"] = m["short"]
		spec["color"] = m["color"]
		spec["lore"] = m["lore"]
		var why := Species.check(spec)
		if why != "":
			push_error("%s : %s" % [fid, why])
		var f := Species.build(spec)
		f["id"] = fid
		f.erase("custom")
		f.erase("spec")
		f["insolite"] = true
		f["broken_rule"] = m["broken_rule"]
		out.append(f)
	print(JSON.stringify(out, "\t"))
	quit()
