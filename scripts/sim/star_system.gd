class_name StarSystem
extends RefCounted
## Un système stellaire. Donnée de simulation pure : aucune notion d'affichage.
## Les coordonnées sont en 2D ; le passage en 2,5D ne changera que la vue.

var id: int = -1
var system_name: String = ""
var position: Vector2 = Vector2.ZERO
var star_type: String = "yellow"
var planet_count: int = 0
var neighbors: Array[int] = []
## Identifiants des planètes du système (dans Galaxy.planets), de la plus proche à la plus lointaine.
var planet_ids: Array[int] = []
