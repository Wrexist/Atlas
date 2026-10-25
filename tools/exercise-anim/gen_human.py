# Generates the MPFB muscular male + default rig (with finger bones) and saves human.blend.
import bpy, sys, os
from bl_ext.blender_org import mpfb
from bl_ext.blender_org.mpfb.services.humanservice import HumanService
from bl_ext.blender_org.mpfb.services.targetservice import TargetService

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "human.blend")

bpy.ops.wm.read_factory_settings(use_empty=True)
macro = TargetService.get_default_macro_info_dict()
print("DEFAULT MACRO", macro)
macro.update({"gender": 1.0, "age": 0.5, "muscle": 1.0, "weight": 0.6, "proportions": 1.0, "height": 0.6})
basemesh = HumanService.create_human(macro_detail_dict=macro, scale=0.1)

# athletic detail on top of the macros, to approach the Atlas anatomy sculpt
TARGETS = os.path.join(os.path.dirname(mpfb.__file__), "data", "targets")
DETAIL = {"torso/torso-muscle-dorsi-incr": 0.9, "torso/torso-muscle-pectoral-incr": 0.8,
          "torso/torso-vshape-incr": 0.7, "torso/measure-shoulder-dist-incr": 0.35,
          "stomach/stomach-tone-incr": 1.0, "neck/neck-scale-horiz-incr": 0.1,
          "arms/measure-upperarm-circ-incr": 0.45, "legs/measure-thigh-circ-incr": 0.3,
          "legs/measure-calf-circ-incr": 0.3, "buttocks/buttocks-volume-incr": 1.0,
          "head/head-scale-horiz-incr": 0.3, "head/head-scale-vert-incr": 0.3, "head/head-scale-depth-incr": 0.3}
for side in ("l", "r"):
    DETAIL.update({f"arms/{side}-upperarm-muscle-incr": 1.0, f"arms/{side}-upperarm-shoulder-muscle-incr": 1.0,
                   f"arms/{side}-lowerarm-muscle-incr": 0.8, f"legs/{side}-upperleg-muscle-incr": 1.0,
                   f"legs/{side}-lowerleg-muscle-incr": 0.8})
for name, w in DETAIL.items():
    TargetService.load_target(basemesh, os.path.join(TARGETS, name + ".target.gz"), weight=w)
rig = HumanService.add_builtin_rig(basemesh, "default")
SHOES = os.path.join(os.path.dirname(os.path.abspath(__file__)), "dl", "shoes02", "clothes", "punkduck_running_shoes_01", "punkduck_running_shoes_01.mhclo")
shoes = HumanService.add_mhclo_asset(SHOES, basemesh, asset_type="Clothes", subdiv_levels=0, material_type="MAKESKIN")
shoes.name = "Shoes"
print("SHOES", shoes.name, len(shoes.data.vertices), [m.type for m in shoes.modifiers], [m.name for m in basemesh.modifiers])
print("DIMS", basemesh.dimensions[:])
bpy.ops.wm.save_as_mainfile(filepath=OUT)
