import sys, subprocess, os, numpy as np
from PIL import Image, ImageDraw, ImageFont
from concurrent.futures import ProcessPoolExecutor
ROOT = sys.argv[1]
CL = f"{ROOT}/clips"; FR = f"{ROOT}/frames"; SH = f"{ROOT}/sheets"
os.makedirs(FR, exist_ok=True); os.makedirs(SH, exist_ok=True)
font = ImageFont.truetype("/usr/share/fonts/opentype/inter/Inter-SemiBold.otf", 26)
def one(name):
    eid = name[:-4]
    out = f"{FR}/{eid}"; os.makedirs(out, exist_ok=True)
    # 12 samples, every 0.25 s
    subprocess.run(["ffmpeg","-v","error","-y","-i",f"{CL}/{name}","-vf","select='not(mod(n\\,9))'","-vsync","0",f"{out}/s%02d.png"],check=True)
    files = sorted(os.listdir(out))
    ims = [Image.open(f"{out}/{f}").convert("RGB") for f in files]
    box=None
    for im in ims:
        a = np.asarray(im).max(axis=2) > 18
        ys, xs = np.where(a)
        if len(xs)==0: continue
        b=(xs.min(),ys.min(),xs.max(),ys.max())
        box = b if box is None else (min(box[0],b[0]),min(box[1],b[1]),max(box[2],b[2]),max(box[3],b[3]))
    w,h=ims[0].size
    if box is None: box=(0,0,w-1,h-1)
    p=20; box=(max(0,box[0]-p),max(0,box[1]-p),min(w,box[2]+p),min(h,box[3]+p))
    crops=[im.crop(box) for im in ims]
    th=360; tw=int(crops[0].width*th/crops[0].height)
    cols=5
    rows=(len(crops)+cols-1)//cols
    sheet=Image.new("RGB",(cols*tw,rows*(th+34)),(20,20,22))
    d=ImageDraw.Draw(sheet)
    for i,c in enumerate(crops):
        x=(i%cols)*tw; y=(i//cols)*(th+34)
        sheet.paste(c.resize((tw,th)),(x,y+34))
        d.text((x+8,y+2),f"#{i}  {i*0.3:.1f}s",fill=(255,200,120),font=font)
    if sheet.width>1800:
        sheet=sheet.resize((1800,int(sheet.height*1800/sheet.width)))
    sheet.save(f"{SH}/{eid}.jpg",quality=82)
    return eid,len(crops)
if __name__=="__main__":
    names=sorted(f for f in os.listdir(CL) if f.endswith(".mp4"))
    with ProcessPoolExecutor(4) as ex:
        res=list(ex.map(one,names))
    print(len(res), set(n for _,n in res))
