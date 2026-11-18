#!/usr/bin/env bash
# Lance toute la suite de tests en parallèle (une tranche de tests/run_all.gd par cœur) et la résume.
#   tools/run_tests.sh                      toute la suite, autant de tranches que de cœurs
#   tools/run_tests.sh -j 2                 deux tranches
#   tools/run_tests.sh ai_tests minor_tests seulement ces fichiers (un seul processus)
#   tools/run_tests.sh --update-durations   réécrit tests/test_durations.json avec les durées mesurées
# Variables : GODOT (chemin du moteur, défaut « godot »), SS_PERF_SLACK (seuils des tests de vitesse,
# 3 conseillé dans le conteneur cloud ; défaut 3 ici si rien n'est donné).
# Code de sortie 0 si tout passe. Journaux complets dans $LOGDIR (défaut : dossier temporaire).
set -u
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
export SS_PERF_SLACK="${SS_PERF_SLACK:-3}"
JOBS="$(nproc 2>/dev/null || echo 4)"
UPDATE=0
ONLY=()
while [ $# -gt 0 ]; do
	case "$1" in
		-j) JOBS="$2"; shift 2 ;;
		-j*) JOBS="${1#-j}"; shift ;;
		--update-durations) UPDATE=1; shift ;;
		*) ONLY+=("$1"); shift ;;
	esac
done
LOGDIR="${LOGDIR:-$(mktemp -d -t stellar-tests-XXXX)}"
mkdir -p "$LOGDIR"
# Les scripts doivent être importés (classes globales) ; sans effet s'ils le sont déjà.
if [ ! -d .godot ]; then
	"$GODOT" --headless --path . --import > "$LOGDIR/import.log" 2>&1
fi
start=$(date +%s)
if [ ${#ONLY[@]} -gt 0 ]; then
	JOBS=1
	TESTS="$(IFS=,; echo "${ONLY[*]}")" "$GODOT" --headless --fixed-fps 60 --path . -s res://tests/run_all.gd > "$LOGDIR/shard1.log" 2>&1 &
else
	for i in $(seq 1 "$JOBS"); do
		SHARD="$i/$JOBS" "$GODOT" --headless --fixed-fps 60 --path . -s res://tests/run_all.gd > "$LOGDIR/shard$i.log" 2>&1 &
	done
fi
rc=0
for job in $(jobs -p); do
	wait "$job" || rc=1
done
end=$(date +%s)
echo "== Tranches"
for f in "$LOGDIR"/shard*.log; do
	line=$(grep -a "^Tranche " "$f" | tail -1)
	res=$(grep -a "^OK : \|^ÉCHEC : [0-9]" "$f" | tail -1)
	echo "  $(basename "$f" .log) : ${line:-TRANCHE INTERROMPUE (voir $f)} | ${res:-?}"
	[ -z "$line" ] && rc=1
done
echo "== Échecs"
grep -ah "^ÉCHEC : \|  ✗ " "$LOGDIR"/shard*.log | grep -v "vérification(s) sur" | sed 's/^/  /' || true
echo "== Erreurs de script (à regarder même si les vérifications passent)"
errs=$(grep -ac "SCRIPT ERROR" "$LOGDIR"/shard*.log | awk -F: '{s+=$2} END {print s+0}')
echo "  $errs"
grep -ah -A1 "SCRIPT ERROR" "$LOGDIR"/shard*.log | grep -a "at: " | sort | uniq -c | sort -rn | head -10 | sed 's/^/  /'
# Une erreur dans le lanceur lui-même rend la suite rouge (elle peut avoir sauté des tests).
grep -aq "at: .*run_all.gd" "$LOGDIR"/shard*.log && { echo "  erreur dans tests/run_all.gd : suite non fiable"; rc=1; }
echo "== Fichiers les plus lents"
grep -ah "^◀ " "$LOGDIR"/shard*.log | sed 's/^◀ //' | sort -t: -k2 -rn | head -10 | sed 's/^/  /'
python3 - "$LOGDIR" "$UPDATE" <<'EOF' || true
import json, sys, glob
logdir, update = sys.argv[1], sys.argv[2] == "1"
times = {}
for f in glob.glob(logdir + "/shard*.log"):
	for line in open(f, encoding="utf-8", errors="replace"):
		if line.startswith("DURATIONS_JSON "):
			times.update(json.loads(line[len("DURATIONS_JSON "):]))
if update and times:
	try:
		old = json.load(open("tests/test_durations.json"))
	except Exception:
		old = {}
	old.update({k: round(v, 1) for k, v in times.items()})
	# Durée d'un fichier coupé en fonctions = somme de ses fonctions (sert à décider du découpage).
	sums = {}
	for k, v in old.items():
		if ":" in k:
			sums[k.split(":")[0]] = sums.get(k.split(":")[0], 0) + v
	old.update({k: round(v, 1) for k, v in sums.items()})
	json.dump(dict(sorted(old.items())), open("tests/test_durations.json", "w"), indent="\t")
	print("tests/test_durations.json mis à jour (%d fichiers)" % len(times))
EOF
echo "== Total : $((end - start)) s sur $JOBS tranche(s), journaux dans $LOGDIR"
[ $rc -eq 0 ] && echo "SUITE VERTE" || echo "SUITE ROUGE"
exit $rc
