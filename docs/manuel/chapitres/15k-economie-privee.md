---
titre: L'économie privée
numero: 29
image: MJ-46
epigraphe: L'État trace les routes, pose les balises et lève l'impôt. Nous, nous mettons des cargos dessus. Devinez qui s'enrichit.
signature: Orvane Kessh, président des Messageries de Tal-Ruun, devant la commission des Finances
---
Tout ne passe plus par l'État. Avec l'économie privée en jeu, chaque empire a un **secteur privé** : une caisse à part du Trésor, nourrie par l'activité de la population, une part des routes commerciales, des stations minières sous licence, des stations touristiques et des filiales à l'étranger. Il paie ses cargos, ses paquebots et ses stations, et l'État prélève un **impôt sur ses bénéfices**. Vous orientez (licences, commandes, subventions, chartes, lois, impôt), vous ne pilotez pas : le privé investit seul, selon la **confiance des investisseurs**. L'onglet **Privé** de l'écran Commerce ([[C]]) rassemble tout.

Le modèle vient de **Distant Worlds 2** (secteur privé autonome, licences minières, cargos et paquebots civils, stations de villégiature, chantiers loués, confiscation des comptes, comptabilité créative, plafond doux du tourisme), d'**Aurora 4X** (impôt sur les bénéfices, bouton Subventionner, colonies minières civiles, zones interdites aux civils), de **Victoria 3** (investissement autonome, compagnies, prospérité, chartes, dirigeants, nationalisation), de **Stellaris** (filiales, motif d'expropriation, héritage criminel), d'**Endless Space 2** (routes commerciales et marché), de **X4** (cargos visibles, pertes aux pirates) et de **Civilization VI** (monopoles et corporations).

::: capture docs/apercu-economie-privee.png|L'onglet Privé : la caisse, la confiance des investisseurs, les comptes du mois, les stations et les gisements
:::

### Le réglage

Le bloc Règles de la nouvelle partie propose le réglage **Économie privée**. **Désactivée** garde l'économie d'avant : tout appartient à l'État.

{{priv_modes}}

Les peuples mineurs, les pirates, les créatures et les anciennes n'ont pas de secteur privé ; la ruche non plus (rien n'est privé, tout appartient au Tout).

### La caisse privée

Chaque mois, le privé encaisse :

- **l'activité de la population** : 1 énergie par tranche de 2 habitants dans chaque colonie d'au moins 3 habitants, multipliée par (50 + confiance) % ;
- **une part du commerce** : 20 % du revenu de vos routes commerciales, en plus de ce que touche l'État ;
- **ses stations minières** et **ses stations touristiques** (plus bas) ;
- **ses filiales à l'étranger**, les **contrats de ravitaillement** et les **indemnités de réquisition** que l'État lui verse.

Il dépense l'entretien de ses cargos, paquebots et stations (renchéri par l'inflation), puis paie l'**impôt sur ses bénéfices**. Ce qui reste va dans la caisse, et la caisse sert à investir. Le bloc **Comptes du privé** détaille chaque ligne ; ce que le privé verse à l'État apparaît aussi dans le budget du Trésor (chapitre 28), ligne **Économie privée**.

{{priv_impot}}

Sans la fiscalité en jeu, l'impôt reste au cran Normal (30 %). Avec la corruption (chapitre 27), une part de l'impôt privé **fuit** : la moitié de la corruption moyenne de l'empire, au plus 50 %.

### La confiance des investisseurs

Une jauge de 0 à 100, qui s'approche chaque mois de sa cible d'au plus 5 points. La cible part de 50, puis : stabilité moyenne élevée (+10) ou basse (-15), paix (+5) ou guerre (-5, et -15 si l'ennemi est sur votre sol), cote de crédit excellente (+10) ou désastreuse (-15), faillite de l'État (-40), chartes accordées (+3 chacune, au plus 9), Laissez-faire (+15), nationalisation récente (-30 pendant dix ans), corruption, cargos perdus le mois dernier, Grand Krach (-20), subventions, réquisition sans indemnité (-10), syndicats du crime, rumeurs. Le détail s'affiche au survol de la jauge.

Sous **25**, le privé n'investit plus. À partir de **60**, il pose de lui-même des mines sur les meilleurs gisements. À partir de **75**, il investit deux fois par mois.

**Subventionner.** Une fois par mois, 100 énergie du Trésor vont dans la caisse privée, et la confiance gagne 2 points (au plus 10 en tout ; deux fois plus avec le Dirigisme), qui s'effacent d'un point par mois.

### Ce que le privé investit

Chaque mois, si la confiance le permet et selon le cran de l'impôt, le privé choisit dans l'ordre : des **cargos** s'il en manque plus de la moitié du besoin, une **station minière** sur un gisement où vous avez accordé une **licence**, le reste des cargos, une **station touristique**, des **paquebots**, une **mine spontanée** (confiance 60), puis un **bâtiment civil** (Centrale à fusion, Comptoir) dans une colonie dont le chantier est libre. Une guilde marchande (gouvernement Syndicat) choisit elle-même la priorité.

**Chantiers loués.** Chaque construction privée verse 10 % de son prix au Trésor.

**Cargos.** Un cargo coûte 60 énergie et sort en 30 jours. Il en faut un pour deux colonies fondées ou routes envoyées, plus un par station privée. Sous le besoin, les mines ne livrent qu'au prorata du fret, et les **chantiers à plus de six sauts** de la capitale et de vos comptoirs perdent un jour sur quatre.

**Paquebots.** 80 énergie, 45 jours ; un pour trois colonies et un par station touristique. Quand ils suffisent, la **migration** porte deux sauts plus loin et le tourisme tourne à plein.

**Licences et commandes d'État.** Dans le bloc **Gisements libres** : une **licence** (10 influence) autorise le privé à bâtir une station minière sur ce gisement, à ses frais ; une **commande d'État** (150 énergie, 25 % de moins avec le Dirigisme) la fait bâtir tout de suite, à vos frais ; **Interdire** tient le privé à l'écart d'un système. Une station minière (150 énergie, 90 jours) livre à l'État le rendement du gisement, en plus de ce qu'en tire une colonie, et rapporte au privé 2 énergie par unité (4 pour les cristaux). Un gisement de luxe ou stratégique rapporte en plus. Une station dans un système infesté de pirates ne produit rien ce mois-là.

**Stations touristiques.** 200 énergie, 120 jours, dans un système d'au moins 3 de beauté (rayonnement culturel, chapitre 22). Elle vit de la population à quatre sauts, de la beauté du système (8 % par point, la moitié au-delà de 25 %), des partenaires commerciaux proches, et des paquebots.

**Vaisseaux commandés au privé.** Le bloc **Vaisseaux commandés au privé** fait bâtir un vaisseau de guerre à la capitale par un chantier privé : 20 % plus cher, 30 % plus rapide, sans occuper le chantier de la colonie. Ni vaisseau colon, ni méga-vaisseau.

### Les compagnies

En économie privée complète, quand la caisse atteint **300 énergie**, une **compagnie** naît (elle en coûte 150), au plus trois (plus une avec *Compagnies marchandes*, une avec le Laissez-faire). Elle porte un nom tiré de son **siège**, la colonie la plus peuplée (une franchise fiscale attire les sièges), un **secteur** choisi selon ce que le privé possède déjà, et un **dirigeant**.

**Prospérité.** De 0 à 100, elle s'approche de sa cible de 5 par mois : 50, plus 5 par actif de son secteur (cargos pour le fret, stations pour les mines et le tourisme, commandes pour les chantiers…), plus la moitié de l'écart de la confiance à 50, la charte, le dirigeant, la franchise du siège, sa loi en vigueur, le Krach, l'espionnage, sa Maison. À partir de **60**, la compagnie donne l'effet de son secteur à tout l'empire. Sous **15** pendant six mois, c'est la faillite.

{{priv_secteurs}}

**Chartes.** Deux chartes à distribuer (une de plus avec *Compagnies marchandes*, une avec le credo Profit), une par compagnie, réattribuable une fois par an. Le **Monopole** double l'effet du secteur d'une compagnie seule dans son secteur.

{{priv_chartes}}

**Le dirigeant.** **Recruter le dirigeant** le fait entrer au conseil comme héros intendant ; la compagnie en nomme un autre. Un dirigeant dont la compagnie fait faillite offre de lui-même ses talents au conseil, s'il y a de la place.

**Le lobbying.** Chaque compagnie réclame une loi (tableau des secteurs). En vigueur, elle rapporte 1 influence par mois (2 avec un dirigeant lobbyiste) et 5 de prospérité. Une loi contraire en vigueur depuis cinq ans, et la compagnie **déménage son siège** chez votre meilleur partenaire commercial.

**Nationaliser** (40 influence) : la compagnie ne prospère plus et n'a plus de charte, mais verse au Trésor 15 % du bénéfice privé ; la confiance prend -30 pendant dix ans. Interdit sous le Laissez-faire.

**Les actions.** Le bloc **Filiales et actions** permet d'acheter des parts de 10 % des compagnies des empires avec qui vous avez des comptoirs (50 énergie + 3 par point de prospérité, au plus 50 % du capital vendu). Chaque part rapporte chaque année la moitié de la prospérité en énergie.

**Le prêteur.** Une compagnie prospère (70 et plus) devient un prêteur du Trésor (chapitre 28) : jusqu'à 400 énergie, 15 % moins cher que la Banque intérieure ; elle prête sa caisse et récupère ses mensualités.

### Les filiales

Avec un accord commercial, une compagnie peut ouvrir une **filiale** dans la colonie d'un autre empire qui a un secteur privé : 100 énergie de la caisse privée (+10 % par saut au-delà de trois depuis le siège) et 20 influence. La filiale rapporte chaque mois la population de la colonie divisée par deux (au plus 8) au pays d'origine, et 1 énergie à l'hôte, qui s'en souvient en bien.

L'hôte peut **exproprier** une filiale : six mois de son revenu tout de suite, mais le pays d'origine s'en souvient (-30) et gagne pendant cinq ans le motif de guerre **Expropriation** (buts Ouvrir les marchés, Rançon, Humiliation). En guerre, **Confisquer les comptes** de l'ennemi saisit toutes ses filiales chez vous (un an de revenu chacune), avec le même motif pour lui.

**Ouvrir les marchés** (but de guerre) : le vaincu signe un accord commercial, vos meilleures compagnies ouvrent deux filiales gratuites chez lui, et il ne peut plus les exproprier pendant dix ans.

### La flotte marchande en guerre

- **Cargos perdus.** Chaque route envoyée risque de perdre un cargo chaque mois : le pire risque pirate du trajet divisé par quatre, +25 % si une flotte hostile (pirates, ennemis) croise sur le chemin. Un dirigeant ancien corsaire divise les pertes par deux.
- **Zones militaires.** Le bloc **Zones militaires** interdit un système aux civils : plus de cargo perdu sur ses routes, mais ses stations s'arrêtent et aucune station touristique ne s'y ouvre.
- **Réquisition.** En guerre, 30 % des cargos servent l'armée : portée de ravitaillement +1 (logistique, chapitre 7). Indemnisée, elle coûte 2 énergie par cargo et par mois au Trésor ; sans indemnité, la confiance prend -10.
- **Ravitaillement sous contrat.** Une flotte hors de sa zone de ravitaillement, mais pas coupée, refait ses réserves grâce aux cargos privés (au moins deux), contre 3 énergie par flotte et par mois.
- **Conquête.** Une station privée dans un système conquis passe au privé du conquérant ; la horde touche 100 énergie de pillage par station.

### Les ombres

**Syndicats du crime.** Un repaire peut naître chaque mois dans le système le plus corrompu d'un empire (corruption 40 et plus) ou à trois sauts d'un port franc pirate, au plus un par an et par empire. Chaque repaire vole 2 énergie par mois (plus un dixième de la corruption du système), ajoute 5 de corruption, inquiète les investisseurs, et essaime une fois l'an dans un système voisin corrompu. Il ferme de lui-même quand la corruption tombe à zéro (5 % par mois, 10 % sous une Grande enquête). **Descente de police** : 30 influence, 60 % de réussite. Le bloc **Syndicats du crime** de l'onglet les liste, et la lentille les marque d'une croix.

**Comptabilité créative.** Une fois par an : trois mois d'impôt privé d'avance, pris dans la caisse privée, contre +10 de corruption à la capitale pendant un an.

**Espionnage industriel** (chapitre 11, famille Intrigue) : **Voler un procédé** (votre compagnie du même secteur +10, la sienne -5), **Saboter une compagnie** (-25 à sa plus prospère), **Débaucher un dirigeant** (son meilleur dirigeant prend la tête de votre compagnie la plus faible, +10), **Rumeur sur les actions** (toutes ses compagnies -15, et ses investisseurs doutent un an).

### Les lois

Trois lois indépendantes (chapitre 14), exclusives entre elles :

- **Laissez-faire** : impôt sur les bénéfices -10 points, confiance +15, une compagnie de plus, pas de nationalisation.
- **Dirigisme** : commandes d'État -25 %, subventions deux fois plus rassurantes, stabilité +1.
- **Économie planifiée** : 70 % de l'activité privée va directement au Trésor ; plus d'investissement privé, plus de compagnie nouvelle, plus de chantier privé ; énergie -5 %.

### Ponts

- **Fiscalité.** Le cran de l'impôt fixe l'impôt sur les bénéfices et la cadence d'investissement ; la cote de crédit et la faillite pèsent sur la confiance ; les compagnies prêtent au Trésor ; une franchise fiscale attire les sièges.
- **Cour.** Une Maison marchande (marchands, libres marchands, consortium, cartel) prend une compagnie qui naît : sa prospérité lui plaît (+10 de faveur) ou la fâche, et une nationalisation la met en rage (-20).
- **Souverain.** Surnoms **l'Actionnaire** (trois compagnies nées sous son règne) et **le Nationalisateur** (deux nationalisations).
- **Crises.** Le Grand Krach coûte 20 de confiance et 30 de prospérité à chaque compagnie de l'empire touché.
- **Technologies.** *Bourses interstellaires* : tourisme +10 %. *Compagnies marchandes* : une compagnie et une charte de plus.
- **Hauts faits.** **Société anonyme** (première compagnie de la galaxie), **Multinationale** (filiales chez cinq empires), **Destination de rêve** (40 énergie de tourisme par mois) et **Le cimetière des cargos** (infâme : vingt cargos perdus).
- **IA.** Les empires IA subventionnent quand la confiance s'effondre, accordent des licences, distribuent les chartes (armement en guerre), réquisitionnent en guerre, lancent des descentes de police, ouvrent des filiales et confisquent les comptes ennemis.

La lentille du commerce ([[G]]) a un **mode Économie privée** au second appui : stations minières (losange orange), stations touristiques (rose), filiales (carré bleu), zones militaires (anneau rouge), repaires (croix), et un cargo qui avance le long de chacune de vos routes.

### Les talents des peuples

{{priv_talents}}

### Conseils

- Accordez des licences tôt : une station minière privée rapporte à l'État sans lui coûter un sou de construction.
- Une confiance au-dessus de 60 fait travailler le privé tout seul ; une subvention de temps en temps coûte moins qu'une commande d'État.
- En guerre, réquisitionnez en payant : la portée de ravitaillement vaut bien quelques indemnités, et la confiance tient.
- Une zone militaire sur le système pirate qui coupe vos routes protège vos cargos, au prix de ses stations.
- Avant d'exproprier une filiale, regardez la flotte de son pays d'origine.
