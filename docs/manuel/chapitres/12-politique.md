---
titre: Stabilité et politique
numero: 14
image: MJ-14
epigraphe: Le peuple ne demande que deux choses : du pain, et qu'on arrête de lui demander son avis. Hélas, il varie sur la seconde.
signature: Régent Aldric de Vaux-Argent
---
Un empire ne se tient pas seulement par ses flottes. Chaque système a sa **stabilité**, et chaque peuple sa vie politique, avec ses courants, ses élections et ses lois.

### La stabilité

Chaque système revendiqué a une stabilité de 0 à 100, qui glisse chaque mois vers une **cible** : la somme de tout ce qui le rassure ou l'inquiète. L'écran Ordre intérieur ([[F12]]) détaille chaque ligne.

{{stabilite}}

| Ce qui la fait monter | Valeur |
| --- | --- |
| Le système capital | +10 |
| Une garnison (flotte armée sur place) | +5 |
| Un forum ou une préfecture | +10 chacun |
| Une cathédrale | +5 |
| Un Intendant gouverneur | +5, +2 par niveau |
| Une cellule de contre-espionnage chez vous | +5 |

| Ce qui la fait baisser | Valeur |
| --- | --- |
| La distance à la capitale | -2 par saut au-delà de 4, jusqu'à -10 |
| Un empire trop étendu | Administration désactivée : -1 par système au-delà de 12, jusqu'à -15. Sinon, -2 par tranche de 10 % de charge au-delà de la capacité, jusqu'à -15 (chapitre 27) |
| La surpopulation | -1 par habitant au-delà de 80 % du plafond, jusqu'à -5 |
| Une famine ou une pénurie d'énergie | -20 |
| Une attaque subie | -15 pendant 90 jours |
| La guerre qui dure | -1 par trimestre de la plus longue guerre, jusqu'à -6 |
| Une conquête récente | -15, qui s'efface en cinq ans |
| Des agitateurs étrangers | -15 pendant un an |

S'y ajoutent les luxes, les lois, les décrets, la foi, les peuples mêlés, les sujets, les reliques et les talents de votre peuple : l'infobulle les nomme tous.

La moyenne de vos systèmes, pondérée par la population, donne la **stabilité d'empire** : au-dessus de 50, chaque point augmente votre Savoir et votre influence de 0,3 % (jusqu'à +15 %) ; en dessous, chaque point les rogne d'autant.

### Les décrets

Trois décrets, de six mois chacun, rattrapent un système qui glisse :

| Décret | Coût | Effet |
| --- | --- | --- |
| Loi martiale | 30 influence | +25 stabilité, -25 % de production. Une flotte armée doit être sur place |
| Fêtes publiques | 15 influence, 60 énergie | +15 stabilité. Le pain et les jeux se paient |
| Concessions locales | 20 influence | +20 stabilité, mais le système ne produit plus d'influence |

### La sécession

Un système qui reste trop bas entre en **révolte**. La chronique vous prévient à six mois puis à dix mois ; au bout d'un an, il fait **sécession** et rejoint les **Sans-Bannière**, des mondes libres qui arment leurs propres corvettes. Un monde libre qui touche votre territoire se **réintègre** contre de l'influence, si votre stabilité d'empire atteint 60 et qu'aucune flotte rebelle ne le garde.

::: transmission Préfecture de Lenn IV, dernier message officiel
Les manifestants réclament la baisse de l'impôt, la fin de la loi martiale et le retour de la fête des moissons. Nous avons accordé la fête des moissons. Ils l'ont célébrée en hissant leur propre drapeau. Fin de transmission, et probablement de préfecture.
:::

### Les courants

Six courants se partagent l'opinion de vos systèmes, rangés sur une roue : chacun a deux voisins avec qui il s'entend et un opposé qu'il ne supporte pas. Vos actes les déplacent (une guerre nourrit les uns, un traité les autres), et chaque système revient lentement vers le penchant naturel de votre peuple.

{{courants}}

### Les élections

Tous les trois ans, chaque système élit ses représentants. Les courants battus donnent leurs voix au voisin le plus proche sur la roue, jamais à l'opposé. Les règles du vote dépendent de votre gouvernement :

| Gouvernement | Assemblée | Règle |
| --- | --- | --- |
| République | Assemblée | Trois courants gouvernent ; un représentant par habitant ; vous ne faites que soutenir |
| Féodalité | Diète des maisons | Deux courants ; les grandes maisons pèsent plus que le peuple |
| Théocratie | Conclave | Vous nommez le courant ; contredire le vote coûte 15 ferveur |
| Syndicat | Assemblée des actionnaires | Deux courants ; les voix se comptent à la production |
| Horde | Kurultaï des clans | Vous choisissez le clan ; les autres grognent, sauf près de la flotte-ville |
| Conscience | Consensus des nœuds | Pas d'élection : les nœuds reliés décident chaque mois |
| Ruche | Instincts | Une seule volonté, pas de vote |

Une fois par élection, une **action électorale** appuie le courant que vous soutenez : campagne, intimidation des maisons, rachat de voix. Le Sénat ([[P]]) montre l'opinion, les sièges et le prochain scrutin.

### Les lois

Chaque courant au pouvoir impose sa **loi de pouvoir**, gratuite, et ouvre quatre lois de niveau 1 à 4, que vous adoptez contre de l'influence dans vos emplacements (de 2 à 4 selon le gouvernement, un de plus aux ères III et V). Un courant gagne un niveau par mandat. Quand il perd le pouvoir, ses lois tombent avec lui.

Quelques lois n'appartiennent à aucun courant : Impôt exceptionnel, Examens forcés, Pain et jeux, Levée en masse, Couvre-feu, et trois lois du commerce. Le **Libre-échange** double le revenu des routes mais coûte 15 % de matériaux. Le **Protectionnisme**, son contraire, double tarifs et douanes et rend 10 % de matériaux ; les deux ne vont pas ensemble. Les **Compagnies à charte** ajoutent une route commerciale contre 3 de stabilité. Signer un libre-échange plaît à la Concorde ; décréter un embargo plaît au Glaive. Avec les peuples mêlés viennent deux lois de plus, incompatibles entre elles : l'**Hospitalité** (les autres espèces s'intègrent 50 % plus vite, la Concorde gagne du terrain, mais -2 de stabilité là où votre peuple est majoritaire) et la **Préférence native** (+5 de stabilité là où votre peuple est majoritaire, -5 ailleurs, le Glaive et l'Autel en profitent). Avec les religions, deux lois de culte encore, elles aussi incompatibles : la **Tolérance** et l'**Inquisition** (chapitre 15). Avec l'Amphictyonie enfin, la **Souveraineté** : une fois par an, elle soustrait votre empire, pour un an, à une famille de résolutions (chapitre 12), et le Glaive l'applaudit. Avec le Koinon, l'**Hégémonie** : dans une ligue que vous présidez, la centralisation se vote un rang plus tôt et ne coûte plus de cohésion ; le Glaive aime, la Concorde moins (chapitre 11).

Toutes les lois, avec leur niveau et leur effet :

{{lois}}

Les citoyens d'autres espèces votent selon leur propre credo : l'opinion d'un système mêlé glisse vers le penchant de ses habitants, au prorata. Un empire de la foi qui accueille des peuples de raison verra l'Académie monter. Les résidents et les assujettis, eux, ne votent pas.

### Doléances et crises

Le plus grand courant d'opposition formule une **doléance** à la fois : la satisfaire dans les deux ans le renforce et calme ses fidèles, l'ignorer les agite. Si la stabilité d'empire reste sous 25 pendant un an, c'est la **crise de régime** : le courant opposé à celui qui gouverne prend seul le pouvoir, toutes les lois sont révoquées et six mois passent sans loi. Avec les souverains en jeu (chapitre 25), la crise renverse aussi un souverain dont la légitimité est sous 50, et un **coup d'État** installe un usurpateur. L'archétype du souverain pousse chaque mois son courant à la capitale.

### Les talents de stabilité

Chaque peuple vit l'ordre intérieur à sa façon. Ces talents suivent les couches d'espèce :

| Couche | Talent |
| --- | --- |
| Féodalité | **Serments des fiefs** : la dissidence (faute de cristaux) coûte 20 de stabilité aux fiefs lointains au lieu de diviser leur production ; un héritier à moins de 30 de loyauté coûte 10 de stabilité partout |
| Théocratie | **Ferveur et ordre** : en Exaltation, +10 partout ; ferveur à 0, -15. L'Offrande sacrifie 20 de stabilité d'un système contre 15 de ferveur |
| République | **Opinion publique** : la lassitude de guerre compte double ; deux ans sans guerre, +5 partout |
| Conscience | **Réseau sans centre** : pas de malus de distance ; un nœud en révolte coûte 5 aux nœuds voisins |
| Ruche | **Une seule volonté** : pas de stabilité, mais une colonie à plus de 6 sauts de tout monde-ruche (la capitale ou une colonie d'au moins 10 habitants) redevient sauvage au bout d'un an |
| Horde | **Les clans aiment le butin** : pas de malus de distance ; un pillage dans les six derniers mois, +10 partout ; rien depuis un an, -5 |
| Syndicat | **Paix sociale achetée** : Fêtes publiques à moitié prix |
| Credo Honneur | **Parole donnée** : un parjure coûte 10 partout pendant un an |
| Credo Foi | **Les infidèles** : le malus des mondes conquis compte double |
| Credo Profit | **Les affaires marchent** : du commerce avec au moins un empire, +5 partout |
| Credo Survie | **Habitués à la disette** : famine et pénuries ne coûtent pas de stabilité |
| Synthétique | **Châssis empilables** : pas de malus de surpopulation |

::: marge
J'ai ignoré une doléance une fois. Elle m'a coûté une province, deux préfets et le droit de me montrer en public sur Lenn IV.
:::

::: conseil
La stabilité se gagne avant la révolte, pas pendant. Un forum dans chaque système lointain coûte moins cher qu'une loi martiale perpétuelle.
:::
