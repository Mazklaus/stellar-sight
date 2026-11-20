# Performance : référence et points lents

## Grande passe d'optimisation (2026-11-19, PR #152)

Étude : https://claude.ai/artifact/8Yp78SgMZRpyGfNSvCR8Hw. Seules les propositions qui laissent la partie
identique ont été retenues : l'empreinte finale (graine 3, 14 ans) reste `5ae4f7b8cdc5fe6d`, la même que sur
main avant la passe ; 30 jours depuis la sauvegarde de l'an 12 donnent `f68b9ef06cd68e54` des deux côtés.

| An | avant (ms/jour) | après | pire jour avant | après |
| --- | --- | --- | --- | --- |
| 1 | 102 | 58 | 567 | 322 |
| 6 | 215 | 142 | 1 288 | 925 |
| 9 | 357 | 229 | 2 368 | 1 592 |
| 12 | 418 | 263 | 2 491 | 1 911 |
| 14 | 462 | 263 | 2 899 | 1 860 |

Moyenne sur 14 ans (ms/jour), avant → après : IA 89,6 → 60,6 · Logistique 39,4 → 14,9 · Flottes 38,3 → 31,1 ·
Économie 32,3 → 24,6 · Combat au sol 29,3 → 7,9.

Ce qui a changé : ère courante comptée en un passage (`Research.open_eras`), partie commune des zones de
ravitaillement (`Logistics._shared`) et bouts de corridor mémorisés, régiments triés par flotte seulement,
détection calculée une fois par flotte vue, plafonds des régiments mémorisés pendant la récupération,
héros filtrés avant le tri, bilan Kardashev une fois par mois, `get_empire` / `is_npc` / `GameData.building`
plus directs.

Ce qui reste (fin de partie, conteneur) : l'IA (≈ 100 ms/jour), les revenus des empires recalculés par chaque
traitement mensuel le 1er du mois (pic ≈ 1,9 s), la vision. Les gains suivants demandent de changer le rythme
de la simulation (propositions 14, 17, 18 de l'étude, écartées pour l'instant).

Outils : `tools/profile_game.gd` (suit `Simulation.daily_systems()`, `SAVE_AT` pour garder une sauvegarde),
`tools/instrument_profile.py` + `tools/deep_profile.gd` (temps de chaque fonction, sur une copie instrumentée),
banc `tests/endgame_perf_tests.gd` (sauvegarde de l'an 12 dans `tests/data/fin_de_partie.json.gz`).

## Petite passe (2026-11-18)

Mesure du 2026-11-18 (petite passe d'optimisation), à refaire avant et après la grande passe.
Rapport complet : https://claude.ai/artifact/DhzaeHwU8Hnm6gtqm3mGwK

## Comment mesurer

- `godot --headless --path . -s res://tools/profile_game.gd` : partie entre IA avec les réglages par
  défaut de Nouvelle partie (8 empires, tous les piliers, spectateur), coût de chaque système par jour,
  année par année, mémoire et sauvegardes. Variables : `YEARS` (40), `SEED` (3), `LEVEL`, `SAVE_EVERY`, `OUT`.
- La dernière ligne donne l'empreinte finale : même graine et même durée = même empreinte, sinon
  l'optimisation a changé la partie. Graine 3, 12 ans, IA Normale : `0c8b7e6848fd74a1` (au 2026-11-18).
- Rediriger la sortie vers un fichier (vers un tube, Godot la tamponne).

## Référence (conteneur cloud, environ deux fois plus lent qu'un PC de jeu)

| An | ms par jour | Pire jour (ms) | Colonies |
| --- | --- | --- | --- |
| 1 | 59 | 271 | 85 |
| 3 | 102 | 532 | 150 |
| 6 | 236 | 1 396 | 298 |
| 9 | 438 | 2 634 | 437 |
| 12 | 539 | 3 460 | 450 |
| 14 | 674 | 4 523 | 461 |

À la vitesse 5, un jour dure 40 ms. Mémoire statique : 120 Mo (an 1), 134 Mo (an 14). Sauvegarde :
220 Ko au départ, 1,7 Mo l'an 12 ; empreinte (checksum) 17 ms puis 131 ms.

## Coût moyen par système sur 12 ans (ms par jour)

IA 68,7 · Logistique 50,6 · Économie 39,6 · Flottes 36,8 · Combat au sol 27,3 · Combat 9,9 ·
Hauts faits 5,4 · Diplomatie 5,1 · Commerce 3,4 · Culture 2,6 · Spatioports 2,5 · le reste sous 2,2.

## Pistes pour la grande passe

1. IA : découper le coût par décision, puis espacer les décisions lentes (mensuelles, étalées).
2. Logistique : zones de ravitaillement recalculées chaque jour pour chaque empire, `log_cache` vidé en
   plein jour ; ne recalculer qu'au changement de possession ou de tête de pont.
3. Économie : continue de monter quand la galaxie est pleine (76 → 155 ms entre l'an 10 et l'an 14).
4. Flottes : chantiers, exploration et vision recalculées chaque jour.
5. Combat au sol : `aboard()` / `used_places()` trient tous les régiments pour chaque flotte.
6. Débuts de mois : tous les traitements mensuels le même jour (pires jours de 3 à 4,5 s).
7. Chercher systématiquement les `Array(x)` qui partagent un tableau (voir tests/data_integrity_tests.gd).
