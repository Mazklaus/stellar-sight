# Performance : référence et points lents

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
