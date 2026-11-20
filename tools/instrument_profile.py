#!/usr/bin/env python3
"""Instrumente une COPIE du jeu pour tools/deep_profile.gd (ne jamais lancer sur le dépôt lui-même).

Chaque fonction nommée de scripts/sim reçoit en première ligne une sonde ProfScope (RefCounted) ;
sa destruction en fin de fonction enregistre le nombre d'appels, le temps inclusif et le temps propre.

  rm -rf /tmp/ss-prof && cp -r . /tmp/ss-prof && rm -rf /tmp/ss-prof/.git /tmp/ss-prof/.godot
  python3 tools/instrument_profile.py /tmp/ss-prof
  cd /tmp/ss-prof && godot --headless --path . --import
  LOAD=/tmp/an12.json OUT=/tmp/profil.txt godot --headless --path . -s res://tools/deep_profile.gd
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
static var childs: Array[int] = []
static var enabled := false
var key: String
var t0: int

func _init(k: String) -> void:
	key = k
	childs.append(0)
	t0 = Time.get_ticks_usec()

func _notification(what: int) -> void:
	if what != NOTIFICATION_PREDELETE:
		return
	var dt := Time.get_ticks_usec() - t0
	var c: int = childs.pop_back()
	if not childs.is_empty():
		childs[childs.size() - 1] += dt
	if not enabled:
		return
	var s: Array = stats.get(key, [0, 0, 0])
	s[0] += 1
	s[1] += dt
	s[2] += dt - c
	stats[key] = s
""")
print('sondes', n)
