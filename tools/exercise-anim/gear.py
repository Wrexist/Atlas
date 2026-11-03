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


def key(upper, fore, thumb):
    return {"upper": list(upper), "fore": list(fore), "thumb": list(thumb)}


SLEEVE_X = 0.95         # bands and chains go round the bar's sleeves, just outside the plates
UNDER_FOOT = {s: {"world": [0, 0, 0.012], "under": {"bone": f"foot.{s}", "t": 0.4}} for s in "LR"}
SHOULDER_HOLD = key((0.3, 0.35, -0.9), (-0.05, 0.3, 1), (-1, 0, 0))     # torso: band ends held at the shoulders


def bar_lines(spec, kind, x=SLEEVE_X):
    ends = [{"obj": "bar", "at": [sx * x, 0, 0]} for sx in (1, -1)]
    if kind == "chain":
        lines = [{"a": e, "b": e, "chain": True, "length": 1.4} for e in ends]
    elif kind == "reverse":             # hung from the top of the rack, unloading the bottom
        lines = [{"a": e, "b": {"world": [0, 0, 2.4], "under": e, "post": True}} for e in ends]
    else:                               # pegged to the floor under the bar
        lines = [{"a": e, "b": {"world": [0, 0, 0.012], "under": e}} for e in ends]
    spec["lines"] = spec.get("lines", []) + lines
    return spec


def bands(kind, x=SLEEVE_X):
    return lambda spec: bar_lines(spec, kind, x)


def hand_bands(spec, hold=None, to=UNDER_FOOT):
    """Band ends in the fists instead of the implement, each stretched to its anchor (under the feet by default)."""
    spec["implement"] = "band_handle"
    spec.pop("cable", None)
    for k in ("grip", "palm", "slide"):
        spec["arm"].pop(k, None)
    if hold:
        spec["arm"].update(frame="torso", keys=[hold])
    spec["lines"] = [{"a": {"obj": s}, "b": to[s]} for s in spec.get("hands", "LR")]
    return spec


def pull_apart(spec):
    """Band held in front at shoulder height in straight arms, pulled apart until the arms point out sideways."""
    spec.update(posture={"type": "stand", "width": 0.13}, implement="band_handle", hands="LR",
                arm={"frame": "torso", "keys": [key((0.1, 1, 0.05), (0.1, 1, 0.05), (-1, 0, 0)),
                                                key((1, 0.12, 0.05), (1, 0.12, 0.05), (0, 1, 0))],
                     "elbow_out": [0.3, -0.3, -1]},
                lines=[{"a": {"obj": "L"}, "b": {"obj": "R"}}], camera={"az": 30, "el": 8})
    spec.pop("body", None)
    return spec


BAR_BANDS = {
    "Squat_with_Bands": ("Barbell Squat", "band"), "Squat_with_Chains": ("Barbell Squat", "chain"),
    "Reverse_Band_Power_Squat": ("Barbell Squat", "reverse"),
    "Box_Squat_with_Bands": ("Box Squat", "band"), "Box_Squat_with_Chains": ("Box Squat", "chain"),
    "Reverse_Band_Box_Squat": ("Box Squat", "reverse"),
    "Deadlift_with_Bands": ("Barbell Deadlift", "band"), "Deadlift_with_Chains": ("Barbell Deadlift", "chain"),
    "Sumo_Deadlift_with_Bands": ("Sumo Deadlift", "band"), "Sumo_Deadlift_with_Chains": ("Sumo Deadlift", "chain"),
    "Reverse_Band_Sumo_Deadlift": ("Sumo Deadlift", "reverse"),
    "Bench_Press_with_Chains": ("Barbell Bench Press - Medium Grip", "chain"),
    "Reverse_Band_Bench_Press": ("Barbell Bench Press - Medium Grip", "reverse"),
}

PATCHES = {sid: (base, smith) for sid, base in SMITH.items()}
PATCHES.update({sid: (base, bands(kind)) for sid, (base, kind) in BAR_BANDS.items()})
PATCHES.update({
    "Close-Grip_EZ-Bar_Curl_with_Band": ("Close-Grip EZ Bar Curl", bands("band", 0.5)),
    "Band_Pull_Apart": (None, pull_apart),
    "Back_Flyes_-_With_Bands": (None, pull_apart),
    "Lateral_Raise_-_With_Bands": ("Side Lateral Raise", hand_bands),
    "Upright_Row_-_With_Bands": ("Upright Barbell Row", hand_bands),
    "Calf_Raises_-_With_Bands": ("Standing Calf Raises", lambda s: hand_bands(s, SHOULDER_HOLD)),
    "Squats_-_With_Bands": ("Bodyweight Squat", lambda s: hand_bands(s, SHOULDER_HOLD)),
    "Band_Good_Morning": ("Good Morning", lambda s: hand_bands(s, SHOULDER_HOLD)),
    "Band_Skull_Crusher": ("EZ-Bar Skullcrusher", lambda s: hand_bands(
        s, to={h: {"world": [0, 0.75, 0.05], "under": {"bone": "head"}} for h in "LR"})),
    "Speed_Band_Overhead_Triceps": ("Cable Rope Overhead Triceps Extension", lambda s: hand_bands(
        s, to={h: {"world": [0, 0.35, 0.012], "under": {"bone": f"foot.{h}"}} for h in "LR"})),
    "Band_Assisted_Pull-Up": ("Pullups", lambda s: dict(s, camera={"az": 25, "el": 6}, lines=[
        {"a": {"obj": h, "at": [x, 0, 0]}, "b": {"bone": f"lowerleg01.{h}", "t": 0.1, "off": [0, -0.06, 0]},
         "via": [{"bone": "spine03", "t": 0.5, "off": [x, -0.2, 0]}]}       # hangs clear of the chest
        for h, x in (("L", 0.04), ("R", -0.04))])),
})


def base_name(e):
    return PATCHES[e["id"]][0]


def build(e, by_name, base_spec):
    """Spec for exercise `e` if this module covers it, else None. `base_spec(entry)` makes a template spec."""
    if e["id"] not in PATCHES:
        return None
    base, patch = PATCHES[e["id"]]
    spec = base_spec(by_name[base]) if base else {"primary": [], "secondary": []}
    if not spec:
        return None
    spec = patch(copy.deepcopy(spec))
    spec.update(name=e["name"], slug=e["id"])
    return spec
