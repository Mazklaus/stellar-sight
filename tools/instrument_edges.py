#!/usr/bin/env python3
"""Instrumente une COPIE du jeu pour tools/deep_profile_edges.gd (ne jamais lancer sur le dépôt lui-même).

Comme tools/instrument_profile.py, avec en plus les arêtes appelant > appelé : pour chaque fonction, qui
l'appelle et ce qu'elle appelle (nombre d'appels et temps). Le profil sort en JSON, lu par
tools/profile_report.py. Les temps instrumentés sont environ cinq fois les temps réels (la sonde pèse
sur chaque appel) : ils servent à comparer, pas à chiffrer.

  rm -rf /tmp/ss-prof && cp -r . /tmp/ss-prof && rm -rf /tmp/ss-prof/.git
  python3 tools/instrument_edges.py /tmp/ss-prof
  cd /tmp/ss-prof && godot --headless --path . --import
  LOAD=partie.json DAYS=60 OUT=/tmp/profil.json godot --headless --path . -s res://tools/deep_profile_edges.gd
  python3 tools/profile_report.py /tmp/profil.json top 40
  python3 tools/profile_report.py /tmp/profil.json fn Economy.max_pop
  python3 tools/profile_report.py /tmp/profil.json tree AiPlayer.think 3 8

Sans instrumentation (dans le dépôt), deep_profile_edges.gd donne le temps réel par système et par jour,
et l'empreinte finale (« checksum ») pour vérifier qu'une optimisation n'a pas changé la partie.
"""
import os, re, sys
root = sys.argv[1]
if os.path.isdir(os.path.join(root, '.git')):
    sys.exit('Refus : ce dossier a un .git, instrumentez une copie (voir plus haut).')
sig = re.compile(r'^(\s*)(static\s+)?func\s+([A-Za-z_]\w*)\s*\(')
n = 0
for dp, dn, fn in os.walk(os.path.join(root, 'scripts', 'sim')):
    for f in fn:
        if not f.endswith('.gd'): continue
        p = os.path.join(dp, f)
        lines = open(p, encoding='utf-8').read().split('\n')
        cls = None
        for l in lines:
            m = re.match(r'^class_name\s+(\w+)', l)
            if m: cls = m.group(1); break
        cls = cls or f[:-3]
        out = []; i = 0
        while i < len(lines):
            l = lines[i]; m = sig.match(l)
            if not m:
                out.append(l); i += 1; continue
            # trouve la fin de la signature (ligne finissant par ':' hors commentaire)
            j = i; depth = 0; end = None
            while j < len(lines):
                code = lines[j].split('#')[0].rstrip()
                depth += code.count('(') - code.count(')')
                if depth <= 0 and code.endswith(':'):
                    end = j; break
                if depth <= 0 and ':' in code and not code.endswith(':'):
                    break  # fonction sur une ligne
                j += 1
            if end is None:
                out.append(l); i += 1; continue
            out.extend(lines[i:end+1])
            # indentation du corps
            k = end + 1
            while k < len(lines) and lines[k].strip() == '': k += 1
            if k >= len(lines): i = end + 1; continue
            ind = re.match(r'^(\s*)', lines[k]).group(1)
            if len(ind) <= len(m.group(1)):
                i = end + 1; continue
            name = m.group(3)
            if name in ('_init', '_notification') or cls == 'ProfScope':
                i = end + 1; continue
            out.append(f'{ind}var __ps := ProfScope.new("{cls}.{name}")')
            n += 1
            i = end + 1
        open(p, 'w', encoding='utf-8').write('\n'.join(out))
open(os.path.join(root, 'scripts', 'sim', 'prof_scope.gd'), 'w').write("""class_name ProfScope
extends RefCounted
static var stats := {}
static var edges := {}
static var childs: Array[int] = []
static var keys: Array[String] = []
static var enabled := false
var key: String
var t0: int

func _init(k: String) -> void:
	key = k
	childs.append(0)
	keys.append(k)
	t0 = Time.get_ticks_usec()

func _notification(what: int) -> void:
	if what != NOTIFICATION_PREDELETE:
		return
	var dt := Time.get_ticks_usec() - t0
	var c: int = childs.pop_back()
	keys.pop_back()
	if not childs.is_empty():
		childs[childs.size() - 1] += dt
	if not enabled:
		return
	var s: Array = stats.get(key, [0, 0, 0])
	s[0] += 1
	s[1] += dt
	s[2] += dt - c
	stats[key] = s
	var ek: String = (keys[keys.size() - 1] if not keys.is_empty() else "ROOT") + " > " + key
	var e: Array = edges.get(ek, [0, 0])
	e[0] += 1
	e[1] += dt
	edges[ek] = e
""")
print('sondes', n)
