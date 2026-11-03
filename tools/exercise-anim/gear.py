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


FOOT_Y = -0.09          # middle of a standing foot (heel +0.06 .. toes -0.24) at rest


def box_at(w, d, h, x=0.0, y=FOOT_Y):
    return {"size": [w, d, h], "at": [x, y, h / 2]}


ARMS_DOWN = key((0.1, 0.1, -1), (0.05, 0.15, -1), (0, 1, 0))
ARMS_BACK = key((0.15, -0.6, -0.8), (0.1, -0.5, -0.85), (0, 1, 0))
ARMS_UP = key((0.15, 0.85, 0.5), (0.1, 0.8, 0.6), (0, 0, 1))
ARMS_FWD = key((0.12, 0.8, -0.55), (0.08, 0.9, -0.3), (0, 0, 1))


def feet(dx=0.0, dy=0.0, dz=0.0):
    return {f"f{a}_{s}": v for s in "LR" for a, v in (("x", dx), ("y", dy), ("z", dz)) if v}


def jump_onto(h, d, w=0.7, depth=0.5, lateral=False, arms=True):
    """Two-foot jump `d` m forward (or sideways) onto a box `h` m high: crouch, swing, fly, land soft, stand tall;
    the loop plays it back, so the athlete hops back down the way he came."""
    dx, dy = (d, 0.0) if lateral else (0.0, -d)
    move = lambda f: dict(feet(dx * f, dy * f), back=dy * f, side=dx * f)
    keys = [{}, {"drop": 0.3, "back": 0.08, "lean": 28},
            dict(move(0.5), air=h + 0.18, lean=8, **{k: v for k, v in feet(dz=0.1).items()}),
            dict(move(1), air=h, drop=0.22, lean=24), dict(move(1), air=h)]
    spec = {"posture": {"type": "stand", "width": 0.16, "toe_out": 12, "feet_move": True}, "implement": "none",
            "bottom": 46, "hold": 8, "body": {"keys": keys, "head_level": 0.8},
            "arm": {"keys": [ARMS_DOWN, ARMS_BACK, ARMS_UP, ARMS_FWD, ARMS_DOWN], "elbow_out": [1, -0.3, 0]},
            "boxes": [box_at(depth if lateral else w, w if lateral else depth, h, x=dx, y=FOOT_Y + dy)],
            "camera": {"az": 20 if lateral else 75, "el": 8}}
    return spec


def depth_jump(h, d=0.6, leap=0.0):
    """Step off a box `h` m high, land soft `d` m in front and rebound straight up (or `leap` m forward)."""
    on = {"air": h}
    keys = [on, dict(feet(dy=-d * 0.5), air=h * 0.5, back=-d * 0.5, lean=5),
            dict(feet(dy=-d), back=-d + 0.08, drop=0.32, lean=30),
            dict(feet(dy=-d - leap, dz=0.12), back=-d - leap, air=0.3, lean=6)]
    return {"posture": {"type": "stand", "width": 0.16, "toe_out": 12, "feet_move": True}, "implement": "none",
            "bottom": 50, "hold": 4, "body": {"keys": keys, "head_level": 0.8},
            "arm": {"keys": [ARMS_DOWN, ARMS_FWD, ARMS_BACK, ARMS_UP], "elbow_out": [1, -0.3, 0]},
            "boxes": [box_at(0.7, 0.5, h)], "camera": {"az": 75, "el": 8}}


def hurdle(x=0.0, y=FOOT_Y - 0.3, h=0.3, cone=False):
    if cone:
        return [{"size": [0.18, 0.18, 0.04], "at": [x, y, 0.02]}, {"size": [0.08, 0.08, h], "at": [x, y, h / 2]}]
    return [{"size": [0.03, 0.12, h], "at": [x + sx * 0.4, y, h / 2]} for sx in (1, -1)] + \
        [{"size": [0.83, 0.025, 0.025], "at": [x, y, h]}]


def hops(cone=False):
    spec = jump_onto(0.0, 0.6)
    spec["body"]["keys"][2]["air"] = 0.42
    spec["boxes"] = hurdle(cone=cone)
    return spec


def step_up(h=0.45, knee=False):
    """Left foot on a box, drive up until standing on it (the right knee driving high with `knee`)."""
    d = 0.38
    up = dict(feet(dy=-d, dz=h), drop=-h, back=-d + 0.02, lean=3)
    if knee:
        up.update(fy_R=-d - 0.25, fz_R=h + 0.45)
    keys = [{"fy_L": -d, "fz_L": h, "drop": 0.06, "back": -0.12, "lean": 18}, up]
    return {"posture": {"type": "stand", "width": 0.13, "feet_move": True}, "body": {"keys": keys, "head_level": 0.8},
            "boxes": [box_at(0.6, 0.45, h, y=FOOT_Y - d)], "camera": {"az": 75, "el": 6}}


def with_load(spec, load):
    if load == "barbell":
        spec.update(implement="barbell_back", arm={"frame": "torso", "elbow_out": [0.3, -1, -1]})
    elif load == "dumbbell":
        spec.update(implement="dumbbell", arm={"frame": "world", "keys": [key((0.12, 0.03, -1), (0.04, 0.04, -1),
                                                                               (0, 1, 0))]})
    else:
        spec.update(implement="none", arm={"keys": [ARMS_DOWN], "elbow_out": [1, -0.3, 0]})
    return spec


def rests_on(kind):
    """Bar starts from blocks under the plates or from rack pins; the rack is filmed from the front quarter so its
    near post doesn't hide the lifter."""
    def patch(spec):
        spec["rests_on"] = kind
        if kind == "pins":
            spec["camera"] = dict(spec.get("camera", {}), az=28)
        return spec
    return patch


def deficit(spec):
    spec["posture"]["floor_z"] = 0.08
    return spec


def box_behind(spec):
    spec["boxes"] = [{"size": [0.42, 0.42, 0.42], "at": [0, 0.27, 0.21]}]
    return spec


def on_dumbbell(spec):
    spec["arm"].update(hand_z=0.12, on_dumbbell=True)
    return spec


def elevated_lunge(spec):
    spec["posture"]["front_z"] = 0.15
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
    "Front_Box_Jump": (None, lambda s: dict(s, **jump_onto(0.5, 0.55))),
    "Box_Jump_Multiple_Response": (None, lambda s: dict(s, **jump_onto(0.5, 0.55))),
    "Bench_Jump": (None, lambda s: dict(s, **jump_onto(0.45, 0.5, w=1.1, depth=0.32))),
    "Lateral_Box_Jump": (None, lambda s: dict(s, **jump_onto(0.4, 0.55, lateral=True))),
    "Depth_Jump_Leap": (None, lambda s: dict(s, **depth_jump(0.5, leap=0.5))),
    "Linear_Depth_Jump": (None, lambda s: dict(s, **depth_jump(0.5))),
    "Hurdle_Hops": (None, lambda s: dict(s, **hops())),
    "Front_Cone_Hops_or_hurdle_hops": (None, lambda s: dict(s, **hops(cone=True))),
    "Barbell_Step_Ups": (None, lambda s: dict(s, **with_load(step_up(), "barbell"))),
    "Dumbbell_Step_Ups": (None, lambda s: dict(s, **with_load(step_up(), "dumbbell"))),
    "Step-up_with_Knee_Raise": (None, lambda s: dict(s, **with_load(step_up(knee=True), None))),
    "Clean_from_Blocks": ("Hang Clean - Below the Knees", rests_on("blocks")),
    "Power_Clean_from_Blocks": ("Hang Clean - Below the Knees", rests_on("blocks")),
    "Snatch_from_Blocks": ("Hang Snatch - Below Knees", rests_on("blocks")),
    "Power_Snatch_from_Blocks": ("Hang Snatch - Below Knees", rests_on("blocks")),
    "Good_Morning_off_Pins": ("Good Morning", rests_on("pins")),
    "Hanging_Bar_Good_Morning": ("Good Morning", lambda s: dict(rests_on("straps")(s), camera={"az": 28, "el": 6})),
    "Rack_Pull_with_Bands": ("Rack Pulls", lambda s: rests_on("pins")(bar_lines(s, "band"))),
    "Deficit_Deadlift": ("Barbell Deadlift", deficit),
    "Front_Barbell_Squat_To_A_Bench": ("Front Barbell Squat", box_behind),
    "Push-Ups_With_Feet_Elevated": ("Decline Push-Up", lambda s: s),
    "Close-Grip_Push-Up_off_of_a_Dumbbell": ("Push-Ups - Close Triceps Position", on_dumbbell),
    "Elevated_Back_Lunge": ("Barbell Lunge", elevated_lunge),
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
