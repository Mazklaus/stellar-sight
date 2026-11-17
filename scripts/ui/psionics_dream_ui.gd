class_name PsionicsDreamUi
extends RefCounted
## Écran Songe, lot 2 : plongée, pacte, Élu (voir PsionicsDream).


static func build(_es: EmpireScreens, _col: VBoxContainer) -> void:
	pass


static func fx_label(_state: GameState, fx: Dictionary) -> String:
	return String(fx.get("label", fx["id"]))


static func targets(_state: GameState, _player: int, _p: Dictionary, out: Array) -> Array:
	return out
