"""Merge jury results -> crops, exercise-steps.json, preview cards."""
import json, os, sys, glob, numpy as np
from PIL import Image, ImageDraw, ImageFont
ROOT=sys.argv[1]; OUT_JSON=sys.argv[2]; CARDS=f"{ROOT}/cards"; os.makedirs(CARDS,exist_ok=True)
FR=f"{ROOT}/frames"
F="/usr/share/fonts/opentype/inter/"
fT=ImageFont.truetype(F+"Inter-SemiBold.otf",40); fS=ImageFont.truetype(F+"Inter-SemiBold.otf",34)
fC=ImageFont.truetype(F+"Inter-Regular.otf",28); fN=ImageFont.truetype(F+"Inter-SemiBold.otf",26)
ex={e['id']:e for e in json.load(open(os.path.join(os.path.dirname(__file__), '../../Peptide/Resources/exercises.json')))}
results={}
for f in sorted(glob.glob(f"{ROOT}/results/*.json")):
    for r in json.load(open(f)): results[r['id']]=r
# optional verdict overrides from round 2
v2={}
for f in sorted(glob.glob(f"{ROOT}/verify/*.json")):
    for r in json.load(open(f)): v2[r['id']]=r
def frame(eid,i): return Image.open(f"{FR}/{eid}/s{i+1:02d}.png").convert("RGB")
def crop_for(eid, idxs):
    box=None
    for i in idxs:
        a=np.asarray(frame(eid,i)).max(axis=2)>18
        ys,xs=np.where(a)
        if len(xs)==0: continue
        b=(xs.min(),ys.min(),xs.max(),ys.max())
        box=b if box is None else (min(box[0],b[0]),min(box[1],b[1]),max(box[2],b[2]),max(box[3],b[3]))
    W,H=720,900
    if box is None: return [0,0,1,1]
    x0,y0,x1,y1=box; pad=36
    x0-=pad;y0-=pad;x1+=pad;y1+=pad
    w=x1-x0; h=y1-y0
    if w/h>0.8: nh=w/0.8; y0-= (nh-h)/2; h=nh
    else: nw=h*0.8; x0-=(nw-w)/2; w=nw
    if w>W: w=W; h=W/0.8
    if h>H: h=H; w=H*0.8
    x0=min(max(0,x0),W-w); y0=min(max(0,y0),H-h)
    return [round(x0/W,4),round(y0/H,4),round(w/W,4),round(h/H,4)]
def wrap(d,text,font,width):
    words=text.split(); lines=[]; cur=""
    for w in words:
        t=(cur+" "+w).strip()
        if d.textlength(t,font=font)<=width: cur=t
        else: lines.append(cur); cur=w
    if cur: lines.append(cur)
    return lines
def card(eid,r,crop,lang="sv"):
    steps=r['steps']; n=len(steps); tw=480 if n==2 else 330; gap=32; th=int(tw*1.25)
    W=48*2+n*tw+(n-1)*gap
    img=Image.new("RGB",(W,th+380),(0,0,0)); d=ImageDraw.Draw(img)
    d.text((48,40),ex[eid]['name'],fill="white",font=fT)
    for k,s in enumerate(steps):
        x=48+k*(tw+gap); y=120
        fr=frame(eid,s['frame']); X,Y,Wc,Hc=crop
        c=fr.crop((int(X*720),int(Y*900),int((X+Wc)*720),int((Y+Hc)*900))).resize((tw,th))
        m=Image.new("L",(tw,th),0); ImageDraw.Draw(m).rounded_rectangle((0,0,tw-1,th-1),28,fill=255)
        img.paste(c,(x,y),m); d.rounded_rectangle((x,y,x+tw-1,y+th-1),28,outline=(48,48,52),width=2)
        cy=y+th+28
        d.ellipse((x,cy,x+44,cy+44),fill=(44,44,48)); d.text((x+22,cy+22),str(k+1),fill="white",font=fN,anchor="mm")
        d.text((x+58,cy+22),s['title_'+lang],fill="white",font=fS,anchor="lm")
        for j,l in enumerate(wrap(d,s['cue_'+lang],fC,tw)):
            d.text((x,cy+62+j*36),l,fill=(150,150,156),font=fC)
    img.save(f"{CARDS}/{eid}.{lang}.jpg",quality=85)
out={}; stats={'pass':0,'fail':0,'nores':0}
for eid in sorted(os.listdir(FR)):
    r=results.get(eid)
    if r is None: stats['nores']+=1; continue
    ok=r['verdict']=='pass' and r['score']>=8 and r['steps']
    if '--final' in sys.argv and eid not in v2: ok=False
    if eid in v2:
        ok = ok and v2[eid]['verdict']=='pass' and v2[eid]['score']>=8 and v2[eid].get('text_score',10)>=8
        rw=v2[eid].get('rewrite')
        if ok and rw and len(rw)==len(r['steps']):
            for s,t in zip(r['steps'],rw): s.update({k:t[k] for k in ('title_sv','cue_sv','title_en','cue_en')})
    if not ok: stats['fail']+=1; continue
    stats['pass']+=1
    idxs=[s['frame'] for s in r['steps']]
    crop=crop_for(eid,idxs)
    if '--cards' in sys.argv:
        card(eid,r,crop,'sv'); card(eid,r,crop,'en')
    out[eid]={"crop":crop,"steps":[{"time":round(s['frame']*0.3,3),
        "en":{"title":s['title_en'],"cue":s['cue_en']},"sv":{"title":s['title_sv'],"cue":s['cue_sv']}} for s in r['steps']]}
json.dump(out,open(OUT_JSON,'w'),ensure_ascii=False,indent=1,sort_keys=True)
print(stats)
