# Illustrations

Déposez ici les images d'habillage (PNG, JPG ou WebP). Chaque emplacement de l'interface (`Widgets.ArtSlot`)
cherche un fichier portant son identifiant et l'affiche à la place du motif dessiné. Aucun code à changer.

Tant que le fichier manque, un emplacement nommé montre un **tableau provisoire** (ciel, astre, horizon) tiré de
son identifiant, avec ce nom dans le coin (Options, Affichage, « Nom des images provisoires »).

- `EMPLACEMENTS.md` : la liste complète des 400 emplacements, par famille, avec le nom de fichier et le format.
- `CONSIGNES.md` : une consigne de génération par emplacement (sujet, cadrage, palette).
- Dans le jeu : Codex, « Galerie des illustrations », qui dit pour chacun s'il est provisoire ou définitif.
- Ces deux fichiers se régénèrent par `godot --headless --path . -s res://tools/art_list.gd`.

Le tableau ci-dessous garde les familles d'origine et leurs usages.

| Identifiant | Où | Format conseillé |
| --- | --- | --- |
| `faction_<id>` (ossarane, choeur, vael, khthari, teyl, ferrocornes, brisecomete, murmurants) | Portrait d'un peuple : choix de faction, colonne de l'écran Économie | portrait, 3:4 |
| `faction_<id>_scene` | Grande illustration à droite du choix de faction | paysage, 16:9 |
| `faction_random` | Case « Au hasard » du choix de faction | portrait, 3:4 |
| `new_game_galaxy` | Bandeau du bloc Galaxie de la nouvelle partie | bandeau, 4:1 |
| `planet_<type>` (continental, ocean, desert, arctic, toxic, gas_giant, barren, asteroids) | Colonie choisie (écran Colonies) | paysage, 4:3 |
| `screen_colonies`, `screen_research`, `screen_diplomacy` | Colonne de gauche des écrans d'empire | bandeau, 2:1 |
| `main_menu` | Fond du menu principal (sinon la galaxie qui dérive) | 16:9 |
| `annonces/<type>` (types de data/announcements.json : war_declared, hero_death, crisis_start…) | Fenêtre des annonces et Fanfares, sous le bandeau de famille ; Fanfares en priorité | bandeau, 3:1 (Fanfare plein cadre) |
