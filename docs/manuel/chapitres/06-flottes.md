---
titre: Exploration et flottes
numero: 4
image: MJ-08
epigraphe: Une carte n'est jamais fausse. Elle est seulement en retard.
signature: Maître-navigateur Elkan d'Ossarane
---
Au début de la partie, presque toute la galaxie est cachée. Vos flottes la découvrent, vos colonies la surveillent, et ce que vous en savez vieillit dès que vous détournez le regard.

### Déplacer une flotte

Sélectionnez une flotte d'un clic sur son chevron (ou [[F]] et [[Maj]]+[[F]] pour passer de l'une à l'autre), puis cliquez droit sur un système. La flotte prend le plus court chemin connu et avance chaque jour à la vitesse de son vaisseau le plus lent. Le trajet et le délai s'affichent en pointillés. Avec l'option Frontières, le chemin contourne l'espace où la flotte n'a pas le droit d'aller, et prévient d'une **intrusion** s'il ne peut l'éviter (chapitre 8). Avec l'option Terrain, les routes qui touchent une nébuleuse ou un trou noir sont plus longues, et le chemin les contourne quand c'est plus court (chapitre 7). Un contre-ordre en plein trajet est accepté : la flotte finit sa route ou fait demi-tour, selon ce qui est le plus court. **Arrêter** la pose au système le plus proche.

**Les distances.** L'espace est grand : au réglage **Distances normales**, un éclaireur met un peu plus de deux semaines par saut, une frégate trois, un titan plus d'un mois, et traverser la galaxie prend des années avec les moteurs de départ. Le réglage se choisit à la création de la partie (Galaxie, réglages avancés) : **proches**, **normales** ou **vastes**. Il change la durée des trajets, pas la carte.

**La mise en route.** Avant de quitter un système par une route, une flotte charge ses moteurs à l'arrêt : **1 jour** pour les petites coques, **2** pour les moyennes, **4** pour les grandes, **6** pour les titans (la plus grande coque de la flotte compte). Elle recommence à chaque étape du trajet, et le délai affiché en tient compte. Une flotte qui rompt un combat reste sous le feu tant que ses moteurs chargent. Trous de ver, portails et portes stellaires n'en demandent pas.

**Les moteurs.** Trois générations de moteurs rétrécissent l'espace à mesure qu'on le maîtrise : les **Propulseurs à fusion** (vitesse ×1,25), les **Moteurs à hyperflux** (×1,6) et le **Saut de précision** (×2,5). Leurs trois Maîtrises raccourcissent chacune la mise en route d'un quart.

**Les étapes.** [[Ctrl]]+clic droit ajoute une **étape** : la flotte ira là après sa destination actuelle (huit étapes au plus). Un ordre ordinaire ou Arrêter efface les étapes.

**La consigne d'engagement.** Le bouton **Consigne** de la fiche de flotte fixe ce qu'elle fait sans vous quand un combat s'engage : **engager** (par défaut), **éviter le combat** (elle part vers votre système le plus proche), ou **se replier si elle est surclassée** (elle part si l'ennemi pèse plus d'une fois et demie vos forces sur place).

**Le point de ralliement.** Le bouton **Ralliement ici** d'une flotte armée à l'arrêt fait de son système le point de ralliement de vos chantiers : chaque vaisseau armé neuf s'y rend de lui-même. Un second clic l'enlève.

La fiche de flotte, en bas à gauche, permet aussi de **rassembler** les flottes à l'arrêt dans un même système, d'en **détacher** un vaisseau, de **coloniser** avec un vaisseau colon et de mettre la flotte en **patrouille** ([[Maj]]+clic droit) entre deux systèmes.

::: capture docs/apercu-flottes-liste.png|Liste des flottes et exploration automatique
:::

### Ne perdre aucune flotte de vue

La **liste des flottes**, à droite sous la chronique, montre toutes vos flottes et leur état : en route, en exploration, en attente d'ordres. Le bouton des **flottes inactives**, au-dessus du cadran, et la touche [[I]] amènent à la prochaine flotte qui attend vos ordres.

L'**exploration automatique** ([[E]]) est un ordre permanent : la flotte vise le système pas encore reconnu le plus proche, change de cible si un autre de vos vaisseaux y est passé entre-temps, évite celles qu'un autre explorateur vise déjà, et s'arrête quand il n'y a plus rien à atteindre. Un ordre manuel la coupe.

### Le brouillard de guerre

Vous ne voyez que ce qu'observent vos revendications (un saut autour d'elles) et vos flottes, selon leur vision. Un système vu une fois reste **exploré**. Un éclaireur voit à **un saut** ; la **Télémétrie à longue base** (Génie spatial, senseurs) porte sa vue à deux.

**Voir n'est pas connaître.** D'un système seulement aperçu de loin, vous connaissez l'étoile et le propriétaire. Ses planètes, ses gisements et ses curiosités ne se lisent qu'une fois le système **reconnu** : un de vos vaisseaux y est passé, vous y tenez une revendication, ou un échange de cartes vous l'a donné. L'exploration automatique va donc partout. Hors de vue, il est assombri et les flottes étrangères y sont invisibles. Avec l'option Terrain, le voile des nébuleuses arrête la vue (chapitre 7).

### La dernière information connue

Chaque empire garde un **relevé daté** de chaque système qu'il a vu : propriétaire, colonies, population, siège, bataille. Hors de vue, la carte et les fiches montrent ce relevé, pas la réalité. Un rival qui s'installe au loin n'apparaît qu'au prochain passage, et la fiche dit « Hors de vue : vu il y a 3 mois ».

Une flotte étrangère aperçue laisse une **silhouette datée** là où on l'a vue, avec ce qu'on en sait (« 3 vaisseaux armés, aperçus il y a 12 jours »). Elle s'efface quand on revoit l'endroit vide, ou au bout de 90 jours.

Les **alliés partagent leur vision** en direct, et chaque mois la carte de leur territoire. Les IA ont exactement les mêmes yeux que vous : elles jugent sur leur mémoire, et un voisin discret peut les surprendre.

::: capture docs/apercu-memoire.png|Dernière information connue : un système vu libre il y a deux mois, alors qu'un rival s'y est installé
:::

::: transmission Éclaireur Mouette-4, Lignées d'Ossarane
Système Kalun : libre, trois planètes, aucune présence. Je répète : aucune présence. Fin du relevé. Note personnelle : j'ai un drôle de pressentiment, mais ce n'est pas réglementaire de le consigner.
:::

### Premier contact

Quand un empire aperçoit pour la première fois un système ou une flotte d'un autre, la chronique raconte la rencontre. Les deux empires entrent alors en **guerre froide** (voir le chapitre 8) : pas encore de combat, mais plus d'ignorance.

::: conseil
Une sonde, depuis la vue d'un système connu hors de vue, rafraîchit son relevé sans y envoyer de flotte. Utile avant de lancer une invasion sur la foi d'une information vieille de six mois.
:::
