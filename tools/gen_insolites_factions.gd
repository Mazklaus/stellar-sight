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
	"asphodele": {"name": "Asphodèle, Cité des Trépassés", "short": "Asphodèle", "color": "#b8b2a7", "broken_rule": "Sa population ne naît pas",
		"lore": "Asphodèle ne fait pas d'enfants : elle reçoit des morts. Ceux des batailles, des famines, des pestes, de tous les peuples, recopiés dans la pierre-mémoire et réveillés dans ses nécropoles, avec leur espèce, leurs manies et leurs vieilles rancunes. Le Nécro-conseil gouverne : des morts illustres, très anciens, très fatigués. On les laisse partir quand ils le demandent. On leur dit merci. Ils répondent rarement."},
	"cassivel": {"name": "Muséum de Sire Cassivel", "short": "Cassivel", "color": "#c9853a", "broken_rule": "Un seul dirigeant, à jamais",
		"lore": "Sire Cassivel est vieux comme une étoile moyenne et poli comme un commissaire-priseur. Il veut un exemplaire de tout : chaque espèce, chaque relique, chaque bête, chaque vaisseau, et quelques héros, bien nourris, dans des vitrines confortables. Ses serviteurs époussettent, étiquettent et rattrapent ce qui s'évade. Il n'a pas d'héritier. Il n'en a jamais eu besoin. Pour l'instant."},
	"silencieux": {"name": "Silencieux", "short": "Silencieux", "color": "#7d8a99", "broken_rule": "Ne négocie pas, n'invente pas",
		"lore": "Personne ne sait qui a construit les Silencieux, ni pourquoi. Ils ne parlent pas, ne prient pas, ne rêvent pas : ils extraient, assemblent, se répliquent. Ils ne haïssent personne ; ils écartent ce qui gêne. Leur directive s'affiche sur toutes les fréquences, en clair, comme un panneau de chantier. On peut la lire. On ne peut pas la discuter."},
	"quietude": {"name": "Observateurs de Quiétude", "short": "Quiétude", "color": "#8fb9a8", "broken_rule": "Gagne en se cachant",
		"lore": "Les lithes de Quiétude vivent lentement, pensent longtemps, et regardent. Au-dessus des jeunes peuples qui n'ont pas encore quitté leur monde, ils posent des postes voilés, prennent des notes, et parfois, très discrètement, poussent un peu. Ils ont un principe : ne jamais être vus. Ils ont aussi un problème : ils aiment beaucoup leurs protégés."},
	"sablier": {"name": "Gardiens du Sablier Fêlé", "short": "Sablier", "color": "#e0c27a", "broken_rule": "Annule le passé",
		"lore": "Les Gardiens vivent trois fois plus longtemps que les autres humains et se souviennent de choses qui ne sont pas encore arrivées. Ils gardent un sablier fêlé, très ancien, dont le sable coule parfois à l'envers. Avec lui, ils réparent ce qui n'aurait pas dû se passer : une flotte perdue, un héros tombé. Chaque réparation laisse une fissure. Ils le savent. Ils le font quand même, avec beaucoup de regrets et beaucoup de soin."},
	"gravea": {"name": "Lithes de Gravéa", "short": "Gravéa", "color": "#9a8f7d", "broken_rule": "Agit en décennies",
		"lore": "Un Lithe de Gravéa met un an à finir une phrase et un siècle à changer d'avis. Ils ne sont pas lents : ils sont à l'échelle. Pendant que les autres empires se font et se défont, ils déplacent une planète, fondent une ceinture d'astéroïdes, refroidissent une étoile. On les croit endormis. On a tort. On a seulement l'impression d'avoir raison pendant très longtemps."},
	"myrr": {"name": "Sporemère de Myrr", "short": "Myrr", "color": "#c7b7e8", "broken_rule": "Aucun vaisseau",
		"lore": "Myrr est un seul champignon, grand comme un système, qui pense lentement et ne meurt pas vraiment. Elle n'a jamais construit de vaisseau : elle lance des comètes chargées de spores, qui tombent là où personne ne regarde. Quelques mois plus tard, il y a une forêt blanche. Quelques années plus tard, il y a Myrr, partout, et les anciens habitants qui font partie de quelque chose de plus grand."},
	"vergemonde": {"name": "Hallier de Vergemonde", "short": "Vergemonde", "color": "#6fbf5a", "broken_rule": "Transforme lentement les mondes",
		"lore": "Le Hallier est une forêt qui a appris à marcher. Ses Pousses écoutent et apprennent, ses Marcheurs travaillent et voyagent, ses Enracinés, les plus vieux, ne bougent plus et décident. Partout où il s'installe, le monde verdit, lentement, sur trois générations. Il ne fait pas la guerre s'il peut l'éviter. Quand il ne peut pas, il se souvient que les racines tiennent mieux que les murs."},
}


func _init() -> void:
	var out := []
	for fid in ["exode", "zambalu", "halcyre", "kraal", "ventrelune", "bureau", "signal", "ysmer", "asphodele", "cassivel", "silencieux", "quietude", "sablier", "gravea", "myrr", "vergemonde"]:
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
