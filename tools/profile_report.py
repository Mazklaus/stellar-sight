#!/usr/bin/env python3
"""Lit un profil de tools/deep_profile_edges.gd : top N | fn Fonction... | tree Fonction profondeur seuil | days."""
import json,sys,collections
d=json.load(open(sys.argv[1])); cmd=sys.argv[2] if len(sys.argv)>2 else 'top'
st=d.get('stats',{}); ed=d.get('edges',{}); days=d['days']; tot=d['total_ms']
def ms(us): return us/1000.0/days
callers=collections.defaultdict(list); callees=collections.defaultdict(list)
for k,(n,t) in ed.items():
    a,b=k.split(' > '); callers[b].append((t,n,a)); callees[a].append((t,n,b))
if cmd=='top':
    print('total %.0f ms/j instr, %d jours'%(tot/days,days)); print(d['counts']); print(d['counts_end'])
    print('SYS'); 
    for k,v in sorted(d['per_sys_ms_day'].items(),key=lambda x:-x[1])[:25]: print('  %-20s %8.1f %5.1f%%'%(k,v,100*v*days/tot))
    n=int(sys.argv[3]) if len(sys.argv)>3 else 60
    print('SELF (appels/j, incl ms/j, self ms/j, self %)')
    for k,v in sorted(st.items(),key=lambda x:-x[1][2])[:n]: print('  %-55s %9.0f %8.1f %8.1f %5.1f%%'%(k,v[0]/days,ms(v[1]),ms(v[2]),100*v[2]/1000/tot))
    print('INCL')
    for k,v in sorted(st.items(),key=lambda x:-x[1][1])[:n]: print('  %-55s %9.0f %8.1f %8.1f %5.1f%%'%(k,v[0]/days,ms(v[1]),ms(v[2]),100*v[1]/1000/tot))
elif cmd=='fn':
    for f in sys.argv[3:]:
        v=st.get(f); 
        if not v: print('?',f); continue
        print('%s : %.0f appels/j, incl %.1f ms/j (%.1f%%), self %.1f'%(f,v[0]/days,ms(v[1]),100*v[1]/1000/tot,ms(v[2])))
        print('  APPELANTS'); 
        for t,n,a in sorted(callers[f],reverse=True)[:12]: print('    %-55s %9.0f %8.1f'%(a,n/days,ms(t)))
        print('  APPELÉS');
        for t,n,b in sorted(callees[f],reverse=True)[:18]: print('    %-55s %9.0f %8.1f'%(b,n/days,ms(t)))
elif cmd=='tree':
    f=sys.argv[3]; depth=int(sys.argv[4]) if len(sys.argv)>4 else 3; thr=float(sys.argv[5]) if len(sys.argv)>5 else 1.0
    def rec(a,lvl,seen):
        for t,n,b in sorted(callees[a],reverse=True):
            if ms(t)<thr: break
            print('%s%-50s %9.0f %8.1f'%('  '*lvl,b,n/days,ms(t)))
            if lvl<depth and b not in seen: rec(b,lvl+1,seen|{b})
    v=st[f]; print('%s %.0f appels/j incl %.1f self %.1f'%(f,v[0]/days,ms(v[1]),ms(v[2]))); rec(f,1,{f})
elif cmd=='days':
    for r in d['per_day']: print(r['tick'],r['dom'],'%.0f'%r['ms'],{k:round(v) for k,v in r['sys'].items() if v>50})
