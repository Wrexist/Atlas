#!/usr/bin/env python3
"""Render the smooth SKIN body layer for the muscle map (two-layer look).

The map composites two layers: this skin body is the resting base, and the
grayscale écorché (from render_zanatomy.py) is tinted + masked per muscle
so trained muscles reveal through the skin. Both must share the SAME locked
camera as the masks — the camera here is framed on the full écorché bbox to
match render_zanatomy.py exactly.

Skin is a voxel-remeshed envelope of the muscle geometry (no real skin mesh
ships with Z-Anatomy); the face/skull is capped with a smooth head proxy.
Writes anatomy_body_front.png / anatomy_body_back.png into $ATLAS_ANATOMY_OUT.
Source/licence: Z-Anatomy, CC BY-SA 4.0 (see AnatomyAssets.attribution).
"""
import bpy, os, math, mathutils, bmesh
OUT="/tmp/atlas_pack"; os.makedirs(OUT,exist_ok=True)
RES_X,RES_Y=1200,2880
def log(*a): print(*a,flush=True)
bpy.ops.wm.open_mainfile(filepath="/tmp/zanatomy/Z-Anatomy/Startup.blend"); log("opened")
sc=bpy.context.scene; vl=bpy.context.view_layer
parent={}
def index(lc):
    for ch in lc.children: parent[ch]=lc; index(ch)
index(vl.layer_collection)
def se(lc,v):
    for ch in lc.children: ch.exclude=v; se(ch,v)
se(vl.layer_collection,True)
def inc(lc):
    lc.exclude=False
    for ch in lc.children: inc(ch)
for lc in list(parent):
    if lc.collection and lc.collection.name=="Muscular system":
        cur=lc
        while cur is not None: cur.exclude=False; cur=parent.get(cur)
        inc(lc)
def bbox(objs):
    mn,mx=[1e9]*3,[-1e9]*3
    for o in objs:
        for v in o.bound_box:
            w=o.matrix_world@mathutils.Vector(v)
            for i in range(3): mn[i]=min(mn[i],w[i]); mx[i]=max(mx[i],w[i])
    return mn,mx
def setin(b,n,v):
    if n in b.inputs: b.inputs[n].default_value=v
musc=bpy.data.collections.get("Muscular system")
allm=[o for o in musc.all_objects if o.type=="MESH"]
SKIP=["fascia","bursa","septum","membrane","retinaculum","sheath","aponeurosis","raphe","tendon","ligament"]
bel=[o for o in allm if not any(k in o.name.lower() for k in SKIP)]   # full ecorche -> camera (matches masks)
remesh_src=[o for o in bel if bbox([o])[0][2]<=1.5]
head=[o for o in bel if bbox([o])[0][2]>1.5]
# camera from FULL ecorche bbox so skin aligns with the committed masks/gray layer
bmn,bmx=bbox(bel); cx=(bmn[0]+bmx[0])/2; cyc=(bmn[1]+bmx[1])/2
center=[cx,cyc,(bmn[2]+bmx[2])/2]; height=bmx[2]-bmn[2]; dist=height*3+1
oscale=max(height,(bmx[0]-bmn[0])*RES_Y/RES_X)*1.05
sc.use_nodes=False; sc.render.use_compositing=False; sc.render.use_sequencer=False; sc.render.use_multiview=False
sc.render.use_persistent_data=False
sc.render.engine="CYCLES"; sc.cycles.device="CPU"; sc.render.film_transparent=True
sc.render.image_settings.file_format="PNG"; sc.render.image_settings.color_mode="RGBA"
sc.render.resolution_x=RES_X; sc.render.resolution_y=RES_Y
def cam(name,y,flip):
    cd=bpy.data.cameras.new(name); cd.type="ORTHO"; cd.ortho_scale=oscale
    c=bpy.data.objects.new(name,cd); sc.collection.objects.link(c)
    c.location=(center[0],y,center[2]); c.rotation_euler=(math.radians(90),0,math.radians(180) if flip else 0); return c
cams={"front":cam("CF",bmn[1]-dist,False),"back":cam("CB",bmx[1]+dist,True)}
def sun(name,frm,e,col):
    ld=bpy.data.lights.new(name,"SUN"); ld.energy=e; ld.color=col; ld.angle=0.4
    lo=bpy.data.objects.new(name,ld); sc.collection.objects.link(lo)
    lo.rotation_euler=(mathutils.Vector(center)-mathutils.Vector(frm)).to_track_quat('-Z','Y').to_euler()
sun("kF",(center[0]-height*0.6,bmn[1]-dist,center[2]+height*0.55),2.8,(1.0,0.94,0.85))
sun("fF",(center[0]+height*0.8,bmn[1]-dist*0.8,center[2]-height*0.1),1.4,(0.96,0.97,1.0))
sun("rF",(center[0],bmx[1]+dist,center[2]+height*0.7),1.8,(1,1,1))
sun("kB",(center[0]-height*0.6,bmx[1]+dist,center[2]+height*0.55),2.8,(1.0,0.94,0.85))
sun("fB",(center[0]+height*0.8,bmx[1]+dist*0.8,center[2]-height*0.1),1.4,(0.96,0.97,1.0))
sun("rB",(center[0],bmn[1]-dist,center[2]+height*0.7),1.8,(1,1,1))
w=bpy.data.worlds.new("w"); w.use_nodes=True; w.node_tree.nodes["Background"].inputs["Strength"].default_value=0.25
w.node_tree.nodes["Background"].inputs["Color"].default_value=(0.06,0.065,0.07,1); sc.world=w
def render(key,path):
    sc.view_settings.view_transform="AgX"; sc.view_settings.exposure=0.32
    sc.cycles.samples=64; sc.cycles.use_denoising=True
    sc.camera=cams[key]; sc.render.filepath=path; bpy.ops.render.render(write_still=True); log("wrote",os.path.basename(path))
def skin_mat(name):
    m=bpy.data.materials.new(name); m.use_nodes=True; b=m.node_tree.nodes["Principled BSDF"]
    setin(b,"Base Color",(0.80,0.60,0.50,1)); setin(b,"Roughness",0.55)
    setin(b,"Specular IOR Level",0.4); setin(b,"Specular",0.4)
    setin(b,"Subsurface Weight",0.35); setin(b,"Subsurface",0.35)
    setin(b,"Subsurface Radius",(0.10,0.05,0.03)); setin(b,"Subsurface Scale",0.05)
    return m
for o in list(bpy.data.objects):
    if o.type not in ("CAMERA","LIGHT"): o.hide_render=True
verts=[]; faces=[]
for o in remesh_src:
    me=o.data; mw=o.matrix_world; base=len(verts)
    verts.extend([(mw@v.co)[:] for v in me.vertices])
    for p in me.polygons: faces.append(tuple(base+i for i in p.vertices))
mm=bpy.data.meshes.new("m"); mm.from_pydata(verts,[],faces); mm.update()
merged=bpy.data.objects.new("m",mm); sc.collection.objects.link(merged); merged.hide_render=False
rm=merged.modifiers.new("r","REMESH"); rm.mode="VOXEL"; rm.voxel_size=0.018; rm.use_smooth_shade=True
sm=merged.modifiers.new("s","SMOOTH"); sm.factor=0.5; sm.iterations=6
skin=skin_mat("skin"); merged.data.materials.append(skin)
# attached, centered head proxy
hmn,hmx=bbox(head)
bm=bmesh.new()
try: bmesh.ops.create_icosphere(bm,subdivisions=4,radius=0.5)
except TypeError: bmesh.ops.create_icosphere(bm,subdivisions=4,diameter=1.0)
hme=bpy.data.meshes.new("head"); bm.to_mesh(hme); bm.free()
for p in hme.polygons: p.use_smooth=True
hobj=bpy.data.objects.new("head",hme); sc.collection.objects.link(hobj)
hobj.scale=(0.155,0.205,0.30); hobj.location=(cx,cyc,1.58); hobj.data.materials.append(skin); hobj.hide_render=False
render("front",OUT+"/anatomy_body_front.png")
render("back",OUT+"/anatomy_body_back.png")
log("DONE")
