# Préparation hors jeu des portraits rigués (méthode 3). Demande : pip install rembg onnxruntime opencv-python-headless scipy pillow.
# Les masques de silhouette viennent de rembg (modèle isnet-general-use) ; repères (tête, cou, yeux, menton) saisis à la main ci-dessous.
# Découpe trois portraits en calques + maillage pondéré (essai « méthode 3 »).
import json, sys, numpy as np, cv2
from PIL import Image
from scipy.spatial import Delaunay
SRC="/home/user/stellar-sight/assets/art/essais/"
MASKS="/tmp/claude-0/-home-user/40943410-c22e-5400-8468-7fb10813c082/scratchpad/up/seg/"
OUT="/home/user/stellar-sight/assets/art/essais/rig/"
P={
 "essai_mystique":dict(head=[350,330,125,215],neck=[360,545],face=[360,388,78],chest=600,
   eyes=[[309,334],[400,345]],eye=[17,8],glow="#ffc27a",
   chin=[[318,436],[333,431],[355,433],[378,430],[394,436],[398,465],[385,495],[358,505],[332,497],[318,468]]),
 "essai_noble":dict(head=[368,205,108,175],neck=[370,400],face=[370,240,72],chest=460,
   eyes=[[321,198],[415,202]],eye=[17,7],glow="#a8e4ff",
   chin=[[305,302],[330,298],[355,300],[380,298],[405,303],[408,330],[395,360],[365,372],[335,364],[312,335]]),
 "essai_cornu":dict(head=[350,330,285,250],neck=[370,665],face=[368,480,88],chest=690,
   eyes=[[318,430],[425,442]],eye=[13,7],glow="#ff5a2a",
   chin=[[295,520],[330,514],[365,517],[400,513],[436,520],[430,560],[405,592],[368,604],[330,592],[305,560]]),
}
# Repères saisis dans l'artefact « Repères de portrait » : python3 tools/portrait_rig_prep.py reperes.json
# (chaque « image » doit se trouver dans assets/art/essais/ ; le masque est alors calculé par rembg).
def from_reperes(path):
    out={}
    for r in json.load(open(path))["reperes_portraits"]:
        W,H=r["taille"]; px=lambda k:[r[k][0]*W,r[k][1]*H]
        g,d,s,m=px("tete_g"),px("tete_d"),px("sommet"),px("menton")
        el,er=px("oeil_g"),px("oeil_d"); ed=abs(er[0]-el[0])
        e=dict(head=[(g[0]+d[0])/2,(s[1]+m[1])/2,abs(d[0]-g[0])/2,abs(m[1]-s[1])/2],neck=px("cou"),
               face=px("nez")+[0.45*abs(d[0]-g[0])],chest=px("epaules")[1],
               eyes=[[int(el[0]),int(el[1])],[int(er[0]),int(er[1])]],eye=[max(6,int(ed*0.19)),max(4,int(ed*0.08))],glow="#ffd9a0")
        if "bouche_g" in r and "bouche_d" in r:
            bg,bd=px("bouche_g"),px("bouche_d"); cx=(bg[0]+bd[0])/2
            e["chin"]=[[int(bg[0]),int(bg[1])],[int(cx-(cx-bg[0])/2),int(bg[1]-3)],[int(cx),int(bg[1]-2)],[int(cx+(bd[0]-cx)/2),int(bd[1]-3)],[int(bd[0]),int(bd[1])],
                       [int(bd[0]+4),int((bd[1]+m[1])/2)],[int(cx+(bd[0]-cx)*0.6),int(m[1]-8)],[int(cx),int(m[1])],[int(cx-(cx-bg[0])*0.6),int(m[1]-8)],[int(bg[0]-4),int((bg[1]+m[1])/2)]]
        out[r["image"].rsplit(".",1)[0]]=e
    return out
if len(sys.argv)>1:
    P=from_reperes(sys.argv[1])
    import os
    for n in P:
        if not os.path.exists(MASKS+n+"_mask.png"):
            from rembg import remove, new_session
            os.makedirs(MASKS,exist_ok=True)
            remove(Image.open(SRC+n+".jpg").convert("RGB"),session=new_session("isnet-general-use"),only_mask=True).save(MASKS+n+"_mask.png")

def ss(a,b,x):
    t=np.clip((x-a)/(b-a),0,1); return t*t*(3-2*t)
for n,c in P.items():
    im=np.asarray(Image.open(SRC+n+".jpg").convert("RGB"))
    H,W=im.shape[:2]
    m=np.asarray(Image.open(MASKS+n+"_mask.png").convert("L")).astype(np.uint8)
    m=(m>60).astype(np.uint8)*255
    # bas du cadre toujours plein (buste coupé par le cadre) ; trous bouchés
    k=cv2.getStructuringElement(cv2.MORPH_ELLIPSE,(25,25))
    m=cv2.morphologyEx(m,cv2.MORPH_CLOSE,k)
    ff=m.copy(); h2=np.zeros((H+2,W+2),np.uint8); cv2.floodFill(ff,h2,(0,0),255); m=m|cv2.bitwise_not(ff)
    soft=cv2.GaussianBlur(m,(0,0),1.5)
    # fond : la silhouette effacée et repeinte
    hole=cv2.dilate(m,cv2.getStructuringElement(cv2.MORPH_ELLIPSE,(31,31)))
    bg=cv2.inpaint(cv2.cvtColor(im,cv2.COLOR_RGB2BGR),hole,21,cv2.INPAINT_TELEA)
    bg=cv2.GaussianBlur(bg,(0,0),3)
    import os; os.makedirs(OUT+n,exist_ok=True)
    cv2.imwrite(OUT+n+"/fond.jpg",bg,[cv2.IMWRITE_JPEG_QUALITY,88])
    fig=np.dstack([im,soft])
    Image.fromarray(fig).save(OUT+n+"/corps.png",optimize=True)
    # paupières : peau prise au-dessus de chaque œil
    lids=[]
    ew,eh=c["eye"]
    for i,(ex,ey) in enumerate(c["eyes"]):
        w,h=int(ew*2.6),int(eh*3.0)
        sy=int(ey-eh*2.4)-h//2
        patch=im[sy:sy+h, ex-w//2:ex-w//2+w].astype(float)*0.9
        yy,xx=np.mgrid[0:h,0:w]
        a=1-ss(0.7,1.0,np.sqrt(((xx-w/2)/(w/2))**2+((yy-h/2)/(h/2))**2))
        # trait de cils au bas de la paupière
        lash=np.exp(-((yy-(h*0.8))/(h*0.08))**2)*(a>0.3)
        patch*= (1-0.5*lash)[...,None]
        Image.fromarray(np.dstack([patch.clip(0,255),a*255]).astype(np.uint8)).save(OUT+n+f"/paupiere_{i}.png")
        lids.append(dict(pos=[ex,ey],size=[w,h]))
    # maillage : grille dans la silhouette + contour
    pts=[]
    step=16
    inside=cv2.erode(m,np.ones((3,3),np.uint8))
    for y in range(0,H+1,step):
        for x in range(0,W+1,step):
            xx,yy=min(x,W-1),min(y,H-1)
            if inside[yy,xx]>0: pts.append([x,y])
    cnts,_=cv2.findContours(m,cv2.RETR_EXTERNAL,cv2.CHAIN_APPROX_NONE)
    for cn in cnts:
        cn=cn[:,0,:]
        for p in cn[::10]: pts.append([int(p[0]),int(p[1])])
    # points denses autour du visage
    fx,fy,fr=c["face"]
    for a in np.linspace(0,2*np.pi,36,endpoint=False):
        for r in (fr*0.5,fr):
            pts.append([fx+r*np.cos(a),fy+r*np.sin(a)])
    pts=np.unique(np.array(pts,float).round(1),axis=0)
    tri=Delaunay(pts)
    keep=[]
    dil=cv2.dilate(m,np.ones((9,9),np.uint8))
    for t in tri.simplices:
        cx,cy=pts[t].mean(0)
        if dil[int(min(cy,H-1)),int(min(cx,W-1))]>0: keep.append(t.tolist())
    # poids : tête (ellipse), visage (rotation 3D simulée), poitrine (respiration)
    hx,hy,rx,ry=c["head"]
    d=np.sqrt(((pts[:,0]-hx)/rx)**2+((pts[:,1]-hy)/ry)**2)
    w_head=1-ss(0.85,1.15,d)
    nx,ny=c["neck"]
    w_head=np.maximum(w_head*(1-ss(ny-40,ny+30,pts[:,1])), 0)
    df=np.sqrt((pts[:,0]-fx)**2+(pts[:,1]-fy)**2)/fr
    w_face=np.exp(-df**2*1.6)
    w_chest=1-ss(c["chest"],H,pts[:,1])
    rig=dict(size=[W,H],verts=pts.tolist(),tris=keep,w_head=w_head.round(4).tolist(),
             w_face=w_face.round(4).tolist(),w_chest=w_chest.round(4).tolist(),
             head=c["head"],neck=c["neck"],face=c["face"],chest=c["chest"],chin=c.get("chin",[]),
             lids=lids,eye=c["eye"],glow=c["glow"])
    json.dump(rig,open(OUT+n+"/rig.json","w"))
    print(n,len(pts),len(keep))
