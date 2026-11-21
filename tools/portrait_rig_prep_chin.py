import json, numpy as np, cv2
from PIL import Image
SRC="/home/user/stellar-sight/assets/art/essais/"
OUT=SRC+"rig/"
for n in ["essai_mystique","essai_noble","essai_cornu"]:
    rig=json.load(open(OUT+n+"/rig.json"))
    im=np.asarray(Image.open(SRC+n+".jpg").convert("RGB"))
    H,W=im.shape[:2]
    if not rig.get("chin"):
        continue
    poly=np.array(rig["chin"],np.int32)
    x0,y0=poly.min(0)-12; x1,y1=poly.max(0)+12
    m=np.zeros((H,W),np.uint8); cv2.fillPoly(m,[poly],255)
    # bords adoucis sauf le haut (lèvre)
    soft=cv2.GaussianBlur(m,(0,0),5)
    top=poly[:int(rig.get("seam_n",5))]
    edge=np.zeros_like(m)
    cv2.polylines(edge,[top.reshape(-1,1,2)],False,255,1)
    # sous la ligne des lèvres on garde l'alpha net sur 6 px
    sharp=cv2.dilate(m,np.ones((1,1),np.uint8))
    yy=np.arange(H)[:,None]
    seam_y=np.interp(np.arange(W),top[:,0],top[:,1])[None,:]
    near_top=(yy-seam_y<8)&(yy-seam_y>=0)
    a=np.where(near_top,sharp,soft).astype(np.uint8)
    a=np.minimum(a,cv2.dilate(m,np.ones((9,9),np.uint8)))
    chin=np.dstack([im,a])[y0:y1,x0:x1]
    Image.fromarray(chin).save(OUT+n+"/machoire.png")
    # intérieur de la bouche : sombre, de la lèvre jusqu'à 14 px dessous, coins adoucis
    mw=np.zeros((H,W),np.uint8)
    pts=np.vstack([top,top[::-1]+[0,16]]).astype(np.int32)
    cv2.fillPoly(mw,[pts],255)
    mw=cv2.GaussianBlur(mw,(0,0),2.5)
    col=np.zeros((H,W,3),np.uint8); col[...]=(22,8,10)
    mouth=np.dstack([col,mw])[y0:y1,x0:x1]
    Image.fromarray(mouth).save(OUT+n+"/bouche.png")
    rig["chin_box"]=[int(x0),int(y0),int(x1-x0),int(y1-y0)]
    rig["seam"]=[float(top[:,0].mean()),float(top[:,1].mean())]
    json.dump(rig,open(OUT+n+"/rig.json","w"))
    print(n,rig["chin_box"])
