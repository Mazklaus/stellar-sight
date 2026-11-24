extends SceneTree
## Captures du pilier buts de guerre et traités de paix, avec le rendu réel :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_wars.gd
## Écrit les images dans le dossier donné par CAPTURE_DIR (par défaut user://captures).
## Scénario : Vael (joueur) revendique un système d'un voisin (écran Diplomatie : motifs, revendications),
## lui déclare la guerre pour une conquête, gagne batailles et système (panneau de guerre : score en %,
## buts, reddition exigée avec l'avis de l'adversaire). Lot 2 : lentille de guerre, registre des traités.
## Lot 3 : crise diplomatique (ralliés, préavis, ultimatums, talents) et kanly.


func _initialize() -> void:
	var out := OS.get_environment("CAPTURE_DIR")
	if out == "":
		out = ProjectSettings.globalize_path("user://captures")
	DirAccess.make_dir_recursive_absolute(out)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.save_path = "user://saves/capture_quicksave.json"
	main.start_with_menu = false
	root.add_child(main)
	await _frames(10)
	main.player_faction = "vael"
	main.game_options = {"vassals": "actifs", "koinon": "actif", "wargoals": "actifs", "occupation": "occupation"}
	main.new_game(4242)
	await _frames(5)
	var sim: Simulation = main.simulation
	var st: GameState = sim.state
	var me: int = main.view_empire
	sim.advance(240)
	Wars.data()["claims"]["max_jumps"] = 99  # galaxie de démonstration : voisins éloignés
	var others: Array[int] = []
	for e in st.empires:
		if e.is_npc():
			continue
		for o in st.empires:
			if o.id != e.id and not o.is_npc() and not e.contacts.has(o.id):
				e.contacts.append(o.id)
		if e.id != me and not Diplomacy.no_treaties(st, e.id) and not e.eliminated:
			others.append(e.id)
	for o in others:
		if Combat.at_war(st, me, o):
			Diplomacy.sign_treaty(st, me, o, Diplomacy.PEACE)
		Diplomacy._rel_w(st, me, o)["truce"] = 0
		Diplomacy._rel_w(st, me, o)["pact"] = Diplomacy.COLD
	var foe := others[0]
	st.get_empire(me).resources["influence"] = 600
	var cap := FactionTraits.capital_system(st, foe)
	var cand: Array = Wars.claim_candidates(st, me, foe, 8).filter(func(x: Array) -> bool: return int(x[0]) != cap)
	if not cand.is_empty():
		Wars.claim(st, me, int(cand[0][0]))
	Diplomacy.remember(st, me, foe, "declared_war")
	st.proposals = []
	main.set_process(false)
	for t in main._hud._toasts.get_children():
		t.queue_free()
	main._refresh_all()
	await _frames(6)
	var screens: EmpireScreens = main._empire_screens
	screens.diplo_selected = foe
	main.toggle_empire_screen("diplomacy")
	await _frames(10)
	await _scroll_to(main, "Motifs de guerre")
	await _shot(out + "/ecran-motifs-de-guerre.png")
	# La guerre : conquête annoncée, batailles gagnées, revendication prise et tenue.
	Wars.set_pending(st, me, foe, "revendication", "conquete")
	Combat.start_war(st, me, foe)
	var rec := Wars.war(st, me, foe)
	rec["t"] = st.tick - 150
	Wars.on_battle(st, me, foe, 220)
	Wars.on_battle(st, foe, me, 60)
	if not cand.is_empty():
		Combat.capture_system(st, int(cand[0][0]), me)
	rec["hold"][0] = 4
	main._refresh_all()
	screens.diplo_selected = foe
	screens.show_screen("diplomacy")
	await _frames(10)
	await _scroll_to(main, "Score de guerre")
	await _shot(out + "/ecran-guerre-score.png")
	# Lot 2 : la riposte occupe un de vos systèmes ; la lassitude monte. La lentille de guerre.
	var home := FactionTraits.capital_system(st, me)
	for sid in EmpireReport.owned_systems(st, me):
		if sid != home and WarPeace.occupier(st, sid) < 0:
			WarPeace.invade(st, sid, foe)
			break
	rec["ex"] = [22, 47]
	main.toggle_empire_screen("diplomacy")
	await _frames(4)
	main._hud.set_lens("war")
	main._view.queue_redraw()
	var occd := WarPeace.occupied_of(st, me)
	if not occd.is_empty():
		st.get_empire(me).explored[occd[0]] = true
		main._go_to_system(occd[0])
	await _frames(60)
	await _shot(out + "/lentille-guerre.png")
	main._hud.set_lens("")
	# Traité à conditions : zone démilitarisée et limite de flotte, inscrits au registre.
	Wars.data()["treaty"]["dmz_jumps"] = 99
	Vassals.apply_terms(st, me, foe, {"dmz": true, "fleet": true, "trib": true})
	main._refresh_all()
	screens.diplo_selected = foe
	main.toggle_empire_screen("diplomacy")
	await _frames(10)
	await _scroll_to(main, "Traités signés")
	await _shot(out + "/ecran-registre-traites.png")
	# Lot 3 : crise diplomatique avec un second voisin (un tiers rallié), préavis repéré par les espions.
	if others.size() >= 3:
		var foe2 := others[1]
		var spy_on := others[2]
		main.toggle_empire_screen("diplomacy")
		await _frames(4)
		var cap2 := FactionTraits.capital_system(st, foe2)
		var cand2: Array = Wars.claim_candidates(st, me, foe2, 8).filter(func(x: Array) -> bool: return int(x[0]) != cap2)
		st.get_empire(me).resources["influence"] = 600
		var s := "agression|humiliation"
		if not cand2.is_empty():
			Wars.claim(st, me, int(cand2[0][0]))
			s = "revendication|conquete"
		WarLaws.open_crisis(st, me, foe2, s)
		var cr := WarLaws.crisis_between(st, me, foe2)
		if not cr.is_empty():
			cr["end"] = st.tick + 18
			for t3 in WarLaws.rally_candidates(st, cr, foe2):
				(cr["rd"] as Array).append(t3)
				break
		st.networks[Espionage.key(me, foe2)] = {"a": me, "b": foe2, "inf": 100, "cells": 1}
		WarLaws.prepare(st, foe2, me)
		main._refresh_all()
		screens.diplo_selected = foe2
		main.toggle_empire_screen("diplomacy")
		await _frames(10)
		await _scroll_to(main, "Crise diplomatique")
		await _shot(out + "/ecran-crise-diplomatique.png")
	# Kanly : une maison féodale lance une querelle limitée.
	var oss := -1
	for e in st.empires:
		if WarLaws.has_talent(st, e.id, "kanly") and e.id != me and not Combat.at_war(st, e.id, me):
			oss = e.id
	if oss >= 0:
		main.toggle_empire_screen("diplomacy")
		await _frames(4)
		Diplomacy._rel_w(st, me, oss)["truce"] = 0
		Wars.set_pending(st, oss, me, "kanly", "kanly", true)
		Combat.start_war(st, oss, me)
		Wars.on_battle(st, oss, me, 80)
		Wars.on_battle(st, me, oss, 120)
		main._refresh_all()
		screens.diplo_selected = oss
		main.toggle_empire_screen("diplomacy")
		await _frames(10)
		await _scroll_to(main, "Guerre limitée")
		await _shot(out + "/ecran-kanly.png")
	quit()


func _scroll_to(main: Node, text: String) -> void:
	var l := _find_label(main, text)
	if l == null:
		# Refonte : la section peut être dans un autre volet de la fiche d'empire, ou dans un autre onglet.
		var es: EmpireScreens = main._empire_screens
		if es.current == "diplomacy" and es.diplo_tab == "empires":
			for pane: String in ["deal", "war", "relation"]:
				es.set_diplo_pane(pane)
				await _frames(4)
				l = _find_label(main, text)
				if l != null:
					break
		if l == null:
			for addr: String in ["diplomacy:league", "diplomacy:neighbors", "diplomacy:assembly", "diplomacy:empires"]:
				es.show_address(addr)
				await _frames(8)
				l = _find_label(main, text)
				if l != null:
					break
	if l == null:
		return
	var sc: Node = l.get_parent()
	while sc != null and not sc is ScrollContainer:
		sc = sc.get_parent()
	if sc == null:
		return
	var s := sc as ScrollContainer
	s.scroll_vertical = int(l.global_position.y - s.global_position.y) + s.scroll_vertical - 300
	await _frames(6)


func _find_label(n: Node, text: String) -> Control:
	for c in n.find_children("*", "", true, false):
		if c is Label and (c as Label).is_visible_in_tree() and (c as Label).text.to_upper().contains(text.to_upper()):
			return c
		if c is Button and (c as Button).is_visible_in_tree() and (c as Button).text.to_upper().contains(text.to_upper()):
			return c
	return null


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(path)
	print("capture : ", path)
