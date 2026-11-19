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
}


func _init() -> void:
	var out := []
	for fid in ["exode", "zambalu", "halcyre", "kraal"]:
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
