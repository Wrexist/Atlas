# Specs for exercises whose equipment the family templates in gen_specs.py don't draw: each one starts from the
# spec of a related free-weight exercise and adds the equipment (Smith machine, bands, boxes, ...) and any change
# of movement it needs.
import copy

SMITH = {
    "Smith_Machine_Bench_Press": "Barbell Bench Press - Medium Grip",
    "Smith_Machine_Close-Grip_Bench_Press": "Close-Grip Barbell Bench Press",
    "Smith_Machine_Incline_Bench_Press": "Barbell Incline Bench Press - Medium Grip",
    "Smith_Machine_Decline_Press": "Decline Barbell Bench Press",
    "Decline_Smith_Press": "Decline Barbell Bench Press",
    "Smith_Machine_Overhead_Shoulder_Press": "Seated Barbell Military Press",
    "Smith_Machine_Squat": "Barbell Squat",
    "Smith_Machine_Calf_Raise": "Standing Barbell Calf Raise",
    "Smith_Machine_Behind_the_Back_Shrug": "Barbell Shrug Behind The Back",
    "Smith_Machine_Bent_Over_Row": "Bent Over Barbell Row",
    "Smith_Machine_Upright_Row": "Upright Barbell Row",
    "Smith_Machine_Stiff-Legged_Deadlift": "Stiff-Legged Barbell Deadlift",
    "Smith_Machine_Hang_Power_Clean": "Hang Clean",
}


def smith(spec):
    """The bar runs on the Smith machine's rails. Standing lifts are filmed from nearer the front so the near rail
    and plates don't cover the body."""
    spec["smith"] = True
    if spec["posture"]["type"] == "stand":
        cam = spec.setdefault("camera", {})
        cam["az"] = min(cam.get("az", 35), 25)
    return spec


PATCHES = {sid: (base, smith) for sid, base in SMITH.items()}


def base_name(e):
    return PATCHES[e["id"]][0]


def build(e, by_name, base_spec):
    """Spec for exercise `e` if this module covers it, else None. `base_spec(entry)` makes a template spec."""
    if e["id"] not in PATCHES:
        return None
    base, patch = PATCHES[e["id"]]
    spec = base_spec(by_name[base]) if base else {}
    if not spec:
        return None
    spec = patch(copy.deepcopy(spec))
    spec.update(name=e["name"], slug=e["id"])
    return spec
