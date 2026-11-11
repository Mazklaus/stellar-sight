#!/usr/bin/env bash
# Test du multijoueur en vrai réseau sur cette machine : un hôte et deux clients (tools/net_bot.gd)
# jouent DAYS jours à la vitesse maximale en donnant des ordres au hasard, puis on compare leurs
# empreintes finales. Usage : tools/net_selftest.sh [DAYS] (défaut 1800, soit 5 ans).
# Variable GODOT : chemin de l'exécutable (défaut : godot). BRUNO_QUITS_AT=<jour> : un client quitte
# en cours de route (son empire passe à l'IA, sauvegarde automatique) ; les deux autres doivent finir pareil.
# BRUNO_REJOINS=1 (avec BRUNO_QUITS_AT) : il revient aussitôt et doit retrouver son empire.
# TURNS=<jours> : tours simultanés au lieu du temps réel.
set -u
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
DAYS="${1:-1800}"
PORT="${PORT:-24571}"
LOG="$(mktemp -d)"
TURNS="${TURNS:-}" ROLE=host CLIENTS=2 DAYS="$DAYS" PORT="$PORT" NAME=Hote "$GODOT" --headless --path . -s res://tools/net_bot.gd >"$LOG/host.txt" 2>&1 &
sleep 2
for n in Alice Bruno; do
  QUIT=""
  if [ "$n" = Bruno ] && [ -n "${BRUNO_QUITS_AT:-}" ]; then QUIT="$BRUNO_QUITS_AT"; fi
  if [ -n "$QUIT" ] && [ -n "${BRUNO_REJOINS:-}" ]; then
    ( QUIT_AT="$QUIT" ROLE=client ADDR=127.0.0.1 DAYS="$DAYS" PORT="$PORT" NAME="$n" "$GODOT" --headless --path . -s res://tools/net_bot.gd >"$LOG/$n-1.log" 2>&1
      sleep 1
      ROLE=client ADDR=127.0.0.1 DAYS="$DAYS" PORT="$PORT" NAME="$n" "$GODOT" --headless --path . -s res://tools/net_bot.gd >"$LOG/$n.txt" 2>&1 ) &
  else
    QUIT_AT="$QUIT" ROLE=client ADDR=127.0.0.1 DAYS="$DAYS" PORT="$PORT" NAME="$n" "$GODOT" --headless --path . -s res://tools/net_bot.gd >"$LOG/$n.txt" 2>&1 &
  fi
  sleep 1
done
wait
grep -h "choisit\|entré\|retrouve\|rejoint" "$LOG"/*.txt "$LOG"/*.log 2>/dev/null
grep -h "FINAL\|Désynchro\|refusé\|quitté\|ERROR" "$LOG"/*.txt
COUNT=$(grep -h "^FINAL" "$LOG"/*.txt | awk '{print $3, $4}' | sort -u | wc -l)
TOTAL=$(grep -h "^FINAL" "$LOG"/*.txt | wc -l)
EXPECTED=3
if [ -n "${BRUNO_QUITS_AT:-}" ] && [ -z "${BRUNO_REJOINS:-}" ]; then EXPECTED=2; fi
if [ "$TOTAL" -eq "$EXPECTED" ] && [ "$COUNT" -eq 1 ]; then
  echo "OK : les $EXPECTED machines finissent au même jour avec la même empreinte."
  exit 0
fi
echo "ÉCHEC : empreintes ou jours différents (journaux dans $LOG)."
exit 1
