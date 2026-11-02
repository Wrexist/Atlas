# Generates the MPFB muscular male + default rig (with finger bones) and saves human.blend.
import bpy, sys, os, importlib

mpfb = importlib.import_module(next(f"bl_ext.{repo}.mpfb" for repo in ("blender_org", "user_default")
                                    if importlib.util.find_spec(f"bl_ext.{repo}.mpfb")))
HumanService = importlib.import_module(mpfb.__name__ + ".services.humanservice").HumanService
TargetService = importlib.import_module(mpfb.__name__ + ".services.targetservice").TargetService

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "human.blend")

bpy.ops.wm.read_factory_settings(use_empty=True)
macro = TargetService.get_default_macro_info_dict()
print("DEFAULT MACRO", macro)
# ATLAS_BODY picks the build. "bulky" is the original (exaggerated V-taper, lats, glutes and thighs that read as
# inhuman on a light card); "athletic" and "fit" keep real-world proportions with less added muscle.
BODIES = {
    "bulky": ({"muscle": 1.0, "weight": 0.6, "height": 0.6},
              {"dorsi": 0.9, "pectoral": 0.8, "vshape": 0.7, "shoulder": 0.35, "abs": 1.0, "upperarm": 0.45,
               "thigh": 0.3, "calf": 0.3, "glutes": 1.0, "head": 0.3, "limb_muscle": 1.0}),
    "athletic": ({"muscle": 0.8, "weight": 0.5, "height": 0.6},
                 {"dorsi": 0.25, "pectoral": 0.4, "vshape": 0.2, "shoulder": 0.15, "abs": 0.8, "upperarm": 0.2,
                  "thigh": 0.0, "calf": 0.1, "glutes": 0.35, "head": 0.1, "limb_muscle": 0.5}),
    "defined": ({"muscle": 0.95, "weight": 0.48, "height": 0.6},
                {"dorsi": 0.3, "pectoral": 0.55, "vshape": 0.25, "shoulder": 0.15, "abs": 1.0, "upperarm": 0.25,
                 "thigh": 0.0, "calf": 0.15, "glutes": 0.4, "head": 0.1, "limb_muscle": 0.8}),
    "fit": ({"muscle": 0.7, "weight": 0.45, "height": 0.6},
            {"dorsi": 0.0, "pectoral": 0.2, "vshape": 0.0, "shoulder": 0.0, "abs": 0.6, "upperarm": 0.0,
             "thigh": 0.0, "calf": 0.0, "glutes": 0.2, "head": 0.05, "limb_muscle": 0.3}),
}
build, d = BODIES[os.environ.get("ATLAS_BODY", "athletic")]
macro.update({"gender": 1.0, "age": 0.5, "proportions": 1.0, **build})
basemesh = HumanService.create_human(macro_detail_dict=macro, scale=0.1)

TARGETS = os.path.join(os.path.dirname(mpfb.__file__), "data", "targets")
DETAIL = {"torso/torso-muscle-dorsi-incr": d["dorsi"], "torso/torso-muscle-pectoral-incr": d["pectoral"],
          "torso/torso-vshape-incr": d["vshape"], "torso/measure-shoulder-dist-incr": d["shoulder"],
          "stomach/stomach-tone-incr": d["abs"], "neck/neck-scale-horiz-incr": 0.1,
          "arms/measure-upperarm-circ-incr": d["upperarm"], "legs/measure-thigh-circ-incr": d["thigh"],
          "legs/measure-calf-circ-incr": d["calf"], "buttocks/buttocks-volume-incr": d["glutes"],
          "head/head-scale-horiz-incr": d["head"], "head/head-scale-vert-incr": d["head"],
          "head/head-scale-depth-incr": d["head"]}
for side in ("l", "r"):
    m = d["limb_muscle"]
    DETAIL.update({f"arms/{side}-upperarm-muscle-incr": m, f"arms/{side}-upperarm-shoulder-muscle-incr": m,
                   f"arms/{side}-lowerarm-muscle-incr": 0.8 * m, f"legs/{side}-upperleg-muscle-incr": m,
                   f"legs/{side}-lowerleg-muscle-incr": 0.8 * m})
for name, w in DETAIL.items():
    if not w:
        continue
    TargetService.load_target(basemesh, os.path.join(TARGETS, name + ".target.gz"), weight=w)
rig = HumanService.add_builtin_rig(basemesh, "default")
SHOES = os.path.join(os.path.dirname(os.path.abspath(__file__)), "dl", "shoes02", "clothes", "punkduck_running_shoes_01", "punkduck_running_shoes_01.mhclo")
shoes = HumanService.add_mhclo_asset(SHOES, basemesh, asset_type="Clothes", subdiv_levels=0, material_type="MAKESKIN")
shoes.name = "Shoes"
print("SHOES", shoes.name, len(shoes.data.vertices), [m.type for m in shoes.modifiers], [m.name for m in basemesh.modifiers])
# ATLAS_CLOTHES: comma-separated name patterns of MakeHuman system clothes (CC0) under ATLAS_CLOTHES_DIR,
# e.g. "short,tank". Training clothes make the figure read as a person instead of a mannequin.
import glob, re
clothes_dir = os.environ.get("ATLAS_CLOTHES_DIR", "")
available = sorted(glob.glob(os.path.join(clothes_dir, "**", "*.mhclo"), recursive=True)) if clothes_dir else []
print("CLOTHES AVAILABLE", [os.path.basename(c) for c in available])
for i, pattern in enumerate(filter(None, os.environ.get("ATLAS_CLOTHES", "").split(","))):
    match = next((c for c in available if re.search(pattern, os.path.basename(c), re.I)), None)
    if not match:
        sys.exit(f"no clothes match {pattern!r}")
    item = HumanService.add_mhclo_asset(match, basemesh, asset_type="Clothes", subdiv_levels=0, material_type="MAKESKIN")
    item.name = f"Clothes.{i}"
    print("CLOTHES", item.name, os.path.basename(match), len(item.data.vertices))
print("DIMS", basemesh.dimensions[:])
bpy.ops.wm.save_as_mainfile(filepath=OUT)
