---
titre: Les spatioports
numero: 30
image: MJ-47
epigraphe: Une planète qui produit sans port, c'est un grenier sans porte. On peut y entasser tout ce qu'on veut : personne n'en mange.
signature: Maîtresse des quais Ysolde Harn, Grand port orbital de Tessaril
---
Produire ne suffit plus : il faut que la production arrive. Avec les spatioports en jeu, chaque colonie est plus ou moins bien **desservie** par un port de votre empire, et seule la part desservie de sa production matérielle (énergie, matériaux, nourriture, cristaux de saut) rejoint le stock de l'empire. Le Savoir et l'Influence ne voyagent pas en cale : ils ne sont jamais touchés. Le stock reste unique, aucun cargo n'est à piloter : vous placez des ports, vous les reliez, vous les défendez. L'onglet **Réseau** de l'écran Commerce ([[C]]) et le troisième mode de la lentille du commerce ([[G]]) montrent tout.

Le modèle vient de **Distant Worlds 2** (les ressources vont d'abord aux spatioports, puis sont redistribuées ; un spatioport par monde comme plaque de l'économie ; le blocus qui affame un monde ; le tableau d'approvisionnement Adéquat, Bas, Critique), de **Victoria 3** (un territoire n'accède au marché que par un chemin jusqu'à la capitale ; des convois requis contre des convois disponibles ; les enclaves isolées), de **Starsector** (l'accessibilité d'une colonie, faite surtout par son spatioport, rognée par les pirates), de **Stellaris** (la portée de collecte des bases stellaires) et d'**Aurora 4X** (les compagnies civiles qui ne vont pas plus loin que quelques systèmes, les relais).

::: capture docs/apercu-spatioports.png|L'onglet Réseau : le tableau d'approvisionnement, le fret, vos ports et les colonies mal desservies
:::

### Le réglage

Le bloc Règles de la nouvelle partie propose le réglage **Spatioports**. **Désactivée** garde l'économie d'avant : toute la production rejoint le stock, quelle que soit la distance.

{{port_modes}}

### Les ports

Un port par système. Le **Comptoir** que vous connaissez est le premier niveau ; il s'améliore sur place en **Spatioport** (Logistique impériale), qui s'améliore en **Grand port orbital** (Compagnies marchandes, 5 habitants). Une amélioration ne prend pas d'emplacement de plus et garde la route commerciale du Comptoir. La **Balise de fret** est un simple relais, même sur un avant-poste : elle ne dessert aucune planète mais relie deux ports éloignés. Votre capitale naît avec un Spatioport.

{{port_niveaux}}

La portée se compte en sauts. Une nébuleuse compte pour deux sauts, une tempête ou une nébuleuse ionisée ne se traverse pas. Lignes de ravitaillement ajoute un saut à tous vos ports.

### La desserte

Une colonie dans la portée d'un port relié est desservie à **100 %**. Au-delà, elle perd **15 %** par saut, jamais sous le **plancher de 50 %** : une colonie lointaine rapporte moins, jamais rien. Quatre états se lisent d'un coup d'œil :

| État | Desserte | Ce que cela change (réglage complet) |
| --- | --- | --- |
| **Desservie** | 90 % et plus | Rien |
| **Limite** | 60 à 89 % | Chantiers de bâtiments : un jour sur 4 perdu ; luxes à moitié |
| **Isolée** | sous 60 % | Chantiers : un jour sur 2 perdu ; luxes sans effet |
| **Enclave** | plancher | Comme Isolée, et la colonie doit se nourrir seule |

L'infobulle de chaque colonie, dans l'onglet Réseau, donne les causes : distance, pirates, fret, enclave.

### Le réseau

Un port ne compte que s'il est **relié à la capitale** : sa zone doit toucher celle d'un port déjà relié, de proche en proche. Les chemins passent par votre territoire, l'espace libre et celui des empires qui vous ravitaillent (alliés, équipe, suzerain, Koinon, droit de passage). Le territoire d'un voisin fermé coupe la chaîne. Les ports que rien ne relie forment une **enclave** : leurs colonies tombent au plancher.

::: conseil
Un port lointain non relié ne sert à rien tant qu'une balise ne fait pas le lien. Avant de coloniser loin, posez vos relais.
:::

### Le fret (réglage complet)

Le réseau a besoin de cargos : **1 par colonie** hors du système d'un port, **+1 par saut** au-delà de la portée. Il en dispose de **4 par niveau de port relié**, plus **2 par cargo** de l'économie privée si elle est en jeu (Bourses interstellaires : +25 %). Sous le besoin, la part de desserte au-dessus du plancher baisse d'autant.

### Entrepôts, blocus et pirates (réglage complet)

Chaque port garde une **réserve** : 30 jours par niveau, doublée pour le Grand port (et par Spatioports de transit). Un port **coupé** du réseau, ou **bloqué** par une flotte armée ennemie en guerre dans son système, continue de desservir tant que sa réserve dure ; reliée, elle se recharge de 3 jours par jour.

- **Blocus** : annoncé par le chroniqueur ; chaque mois, l'empire qui bloque **pille** 10 énergie et 10 matériaux par niveau de port. Une station de défense qui tient l'orbite empêche le blocus (chapitre 31).
- **Liaisons coupées** : une flotte ennemie qui tient un système sur le chemin coupe la chaîne ; ce qui est derrière vit sur ses réserves, puis devient une enclave.
- **Pirates** : le risque pirate d'un système retire de 5 à 20 % de desserte à ses colonies.
- **Ravitaillement** : un Spatioport ou un Grand port sert de dépôt de flotte (logistique en jeu).
- **L'IA** vise en priorité les ports ennemis, et le Spatioport fait ses vaisseaux 25 % plus vite (50 % pour le Grand port).

### Les ponts (réglage complet)

- **Commerce** : vos routes rapportent +10 % par niveau de votre meilleur port relié au-delà du premier.
- **Fiscalité** : chaque niveau de port relié rapporte 1 énergie de **droits de port** par mois, de 50 % (cran Très bas) à 150 % (Écrasant).
- **Économie privée** : les cargos privés comptent dans le fret, les stations minières livrent au port le plus proche (leur part suit la desserte), le privé touche des **droits de quai** et paie l'entretien des balises (**balises sous licence**).
- **Espionnage** : l'opération **Désorganiser les docks** coupe le meilleur port de la cible pendant 60 jours.
- **Administration** : là où la corruption dépasse 40 %, la contrebande aux docks ronge 10 jours de réserve par mois.
- **Événements de port** : grève des dockers, entrepôt incendié, afflux de marchands, port saturé.

### Les talents des peuples

{{port_talents}}

::: marge
Les dockers de Tessaril ont voté la grève le jour où l'on a inauguré le Grand port. Ils réclamaient des grues plus grandes. On les leur a données. Ils ont voté une autre grève, pour le principe.
:::
