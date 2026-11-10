"""Agrège la sortie de tools/balance_bench.gd (lignes « BENCH {json} ») par peuple.

    python3 tools/balance_report.py sortie1.txt [sortie2.txt ...]
"""
import json
import sys
from collections import defaultdict

games = []
for path in sys.argv[1:]:
    for line in open(path, encoding="utf-8"):
        if line.startswith("BENCH "):
            games.append(json.loads(line[6:]))

stats = defaultdict(lambda: defaultdict(list))
wins = defaultdict(list)
for g in games:
    w = g.get("winner")
    if w:
        wins[w["faction"]].append((w["victory"], w["year"]))
    for e in g["empires"]:
        s = stats[e["faction"]]
        s["dead"].append(e["dead"])
        sysy = e["systems"]
        for yr in (5, 10, 15, 20, 25):
            if len(sysy) >= yr:
                s["sys%d" % yr].append(sysy[yr - 1])
        s["peak"].append(max(sysy) if sysy else 0)

print("%d parties, %d avec un vainqueur, durée moyenne %.0f s" % (
    len(games), sum(1 for g in games if g.get("winner")), sum(g["ms"] for g in games) / max(1, len(games)) / 1000))
print("%-9s %5s %6s %5s %6s %6s %6s %6s %5s  %s" % ("peuple", "parts", "morts", "<an10", "sys5", "sys10", "sys15", "sys20", "pic", "victoires (type an)"))
for f, s in sorted(stats.items()):
    n = len(s["dead"])
    dead = sum(1 for d in s["dead"] if d > 0)
    early = sum(1 for d in s["dead"] if 0 < d <= 10)

    def avg(k):
        v = s[k]
        return "%.1f" % (sum(v) / len(v)) if v else "-"

    wl = ", ".join("%s %d" % (v[:4], y) for v, y in sorted(wins[f], key=lambda t: t[1]))
    print("%-9s %5d %6d %5d %6s %6s %6s %6s %5s  %d : %s" % (f, n, dead, early, avg("sys5"), avg("sys10"), avg("sys15"), avg("sys20"), avg("peak"), len(wins[f]), wl))
