class_name BetaLot1Tests
extends RefCounted
## Lot 1 du bêta-test (corrections visibles) : offrandes décrites
## selon le peuple (1.5), gestion d'un système chargé (1.4), confirmation avant de charger (8.1).
## Les infobulles (1.1) se vérifient dans smoke_test (il faut des images pour la mise en page).
##   tools/run_tests.sh beta_lot1_tests

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Bêta-test, lot 1…")
	_test_offerings()
	_test_manage_panel()
	_test_save_list_confirm()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


## 1.5 : la barre du haut décrit les offrandes avec les chiffres des règles, celle d'un fidèle et,
## en théocratie, celle de stabilité.
func _test_offerings() -> void:
	var od: Dictionary = Stability.data()["offering"]
	for fid in ["murmurants", "choeur"]:
		var st := GameState.create(7, 40, 900.0, fid)
		var tip := String(FactionTraits.gauge(st, 0).get("tip", ""))
		_ok(tip.contains("Offrande d'un fidèle") and tip.contains("+%d ferveur" % FactionTraits.sacrifice_gain(st, 0)), "%s : l'offrande d'un fidèle est décrite (%s)" % [fid, tip])
		var theo := bool(Stability.talent(st, 0).get("offering", false))
		_ok(tip.contains("%d stabilité" % int(od["stability"])) == theo and tip.contains("%+d ferveur" % int(od["fervor"])) == theo,
				"%s : l'offrande de stabilité n'apparaît que si le peuple peut la faire, avec les chiffres de stability.json" % fid)
	var mur := GameState.create(7, 40, 900.0, "murmurants")
	_ok(bool(Stability.talent(mur, 0).get("offering", false)), "Murmurants : théocratie, l'offrande de stabilité existe (cas du bêta-test)")


## 1.4 : sept planètes dans la largeur d'un écran de 1600 : la rangée tient entre ses bords.
func _test_manage_panel() -> void:
	var st := GameState.create(11, 60, 1200.0, "teyl")
	var big: StarSystem = null
	for s in st.galaxy.systems:
		if big == null or s.planet_ids.size() > big.planet_ids.size():
			big = s
	var root: Window = Engine.get_main_loop().root
	var holder := Control.new()
	holder.size = Vector2(942, 600)
	root.add_child(holder)
	var panel := SystemManagePanel.new()
	panel.size = Vector2(942, 600)
	holder.add_child(panel)
	panel.set_system(st, big, 0)
	var need := panel._row.get_combined_minimum_size().x
	_ok(big.planet_ids.size() >= 5 and need <= 942.0 + 1.0, "gestion : %d planètes tiennent dans 942 px (%d px demandés)" % [big.planet_ids.size(), int(need)])
	holder.free()


## 8.1 : avec une partie non sauvegardée, « Charger » demande un second clic et dit ce qui serait perdu.
func _test_save_list_confirm() -> void:
	var dir := "user://test_saves_beta1"
	for old: Dictionary in SaveGame.list(dir):
		SaveGame.remove(String(old["path"]))
	var st := GameState.create(5)
	var path := SaveGame.new_path(dir)
	SaveGame.save_state(st, path, {}, {}, {"empire": "Essai", "kind": "manual"})
	var list := SaveList.new()
	list.dir = dir
	Engine.get_main_loop().root.add_child(list)
	var asked: Array[String] = []
	list.load_requested.connect(func(p: String) -> void: asked.append(p))
	var lost := "La partie en cours n'est pas sauvegardée depuis 3 jours de jeu : charger les efface."
	list.unsaved_check = func() -> String: return lost
	var b: Button = list.get_tree().get_nodes_in_group("save_list_load").filter(func(n: Node) -> bool: return list.is_ancestor_of(n))[0]
	b.pressed.emit()
	var warn: Label = b.get_meta("warn")
	_ok(asked.is_empty() and b.text == "Confirmer" and warn.visible and warn.text == lost, "charger : le premier clic prévient au lieu de charger")
	b.pressed.emit()
	_ok(asked == [path], "charger : le second clic charge")
	asked.clear()
	list.refresh()
	list.unsaved_check = func() -> String: return ""
	b = list.get_tree().get_nodes_in_group("save_list_load").filter(func(n: Node) -> bool: return list.is_ancestor_of(n) and not n.is_queued_for_deletion())[0]
	b.pressed.emit()
	_ok(asked == [path], "charger : rien à perdre, un seul clic suffit")
	list.free()
	SaveGame.remove(path)
