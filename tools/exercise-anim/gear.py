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


def prone(incline=35, **extra):
    """Chest down on an incline bench: the free-standing bent-over lean comes off, arms keep their world keys."""
    def patch(spec):
        spec["posture"] = dict({"type": "prone_incline", "incline": incline}, **extra)
        spec.pop("body", None)
        cam = spec.setdefault("camera", {})
        cam.update(az=cam.get("az", 60), el=max(cam.get("el", 8), 10))
        return spec
    return patch


def one_arm(spec):
    spec["arm"].update(sides="L", rest=key((0.15, 0.05, -1), (0.1, 0.05, -1), (0, 1, 0)))
    spec["hands"] = "L"
    return spec


def compose(*fns):
    def patch(spec):
        for f in fns:
            spec = f(spec)
        return spec
    return patch


CURL_HANG = key((0.1, 0.03, -1), (0.12, 0.08, -1), (1, 0, 0))            # world: arm hanging, palm forward
CURL_TOP = key((0.1, 0.03, -1), (0.1, 0.55, 0.83), (1, 0, 0))            # forearm curled up in front


def spider_curl(spec):
    spec = prone(45)(spec)
    spec.update(implement="dumbbell", arm={"frame": "world", "keys": [CURL_HANG, CURL_TOP], "elbow_out": [0.2, -1, 0]},
                camera={"az": 75, "el": 10})
    return spec


def incline_raises(spec):
    """Prone on the incline, straight arms swing from hanging up in line with the body."""
    spec = prone(35)(spec)
    spec.update(implement="dumbbell", arm={"frame": "world", "keys": [
        key((0.12, 0.05, -1), (0.12, 0.08, -1), (0, 1, 0.05)),
        key((0.3, 0.8, 0.55), (0.3, 0.82, 0.55), (0, -0.55, 0.82))], "elbow_out": [1, 0, 0.3]},
        camera={"az": 70, "el": 12})
    return spec


def middle_back_shrug(spec):
    spec = prone(35)(spec)
    spec.update(implement="dumbbell", body={"keys": [{"retract": -10}, {"retract": 22}], "head_level": 0},
                arm={"frame": "world", "keys": [key((0.1, 0.03, -1), (0.06, 0.05, -1), (0, 1, 0))],
                     "elbow_out": [1, 0, 0]}, camera={"az": 160, "el": 25})
    return spec


def incline_back(deg):
    """Lying back on an incline bench, arms hanging straight down (world keys), as for incline / lying curls."""
    def patch(spec):
        spec["posture"] = {"type": "seat", "back_deg": deg}
        spec.pop("body", None)
        spec["arm"]["frame"] = "world"
        spec["camera"] = {"az": 70, "el": 8}
        return spec
    return patch


def front_incline_raise(spec):
    spec.update(posture={"type": "seat", "back_deg": 45}, implement="dumbbell",
                arm={"keys": [key((0.12, 0.1, -1), (0.12, 0.15, -1), (-1, 0, 0)),
                              key((0.15, 1, 0.1), (0.15, 1, 0.15), (-1, 0, 0))], "elbow_out": [1, -0.3, 0]},
                camera={"az": 75, "el": 10})
    return spec


def seated_lean(lean=55):
    """Sitting on the end of a bench, chest leaning out over the thighs (seated bent-over raises/extensions)."""
    def patch(spec):
        spec["posture"] = {"type": "seat", "lean": lean, "feet_fwd": 1.1}
        spec.pop("body", None)
        return spec
    return patch


def decline(spec, deg=-22):
    """On a decline bench: head down, knees hooked over the pad (thighs up the seat, shins hanging under the
    roller)."""
    spec["posture"] = {"type": "seat", "back_deg": deg, "feet_free": True}
    keys = spec["body"]["keys"]
    for k in keys:
        k.setdefault("hip", 35 + k.get("lean", 0))      # thighs stay on the pad while the trunk rises
        k.setdefault("knee", 105)
    spec["pad"] = "front"
    spec["pad_post"] = True
    spec["camera"] = {"az": 70, "el": 12}
    return spec


def on_bench(spec):
    spec["posture"].update(bench_z=0.45)
    spec["camera"] = {"az": 70, "el": 12}
    return spec


def pullover(back_deg=0, grip=0.2, bent=True):
    """Lying across the bench line, the bar travels from over the chest back over the head and returns."""
    if bent:
        keys = [key((0.3, 1, 0.15), (0.1, 0.55, 0.83), (-1, 0, 0)), key((0.3, 0.25, 1), (0.1, -0.6, 0.8), (-1, 0, 0))]
    else:
        keys = [key((0.25, 1, 0.1), (0.25, 1, 0.12), (-1, 0, 0)), key((0.25, 0.15, 1), (0.25, 0.1, 1), (-1, 0, 0))]

    def patch(spec):
        spec.update(posture={"type": "seat", "back_deg": back_deg}, implement="barbell",
                    arm={"grip": grip, "palm": [0, -1, 0], "keys": keys, "elbow_out": [0.6, -0.2, -1]},
                    camera={"az": 75, "el": 14})
        return spec
    return patch


def leg_pull_in(spec):
    spec["body"]["keys"] = [{"hip": 8, "knee": 5}, {"hip": 105, "knee": 115, "curl": -6}]
    return spec


def seated_tucks(spec):
    spec.update(posture={"type": "seat", "lean": -35, "feet_free": True, "feet_fwd": 1.2}, implement="none",
                body={"keys": [{"hip": 20, "knee": 10}, {"hip": 110, "knee": 120}], "head_level": 0.4},
                arm={"keys": [key((0.4, -0.55, -0.75), (0.1, -0.35, -0.95), (0, 1, 0))], "elbow_out": [0.2, -1, 0]},
                camera={"az": 75, "el": 8})
    return spec


def decline_band_situp(spec):
    spec = decline(spec, -20)
    spec["lines"] = [{"a": {"obj": h}, "b": {"world": [sx * 0.2, 0.6, 0.05], "under": {"bone": "spine05"}}}
                     for h, sx in (("L", 1), ("R", -1))]
    return spec




NEUTRAL = (0, 1, 0)
SIDE_HANDLE = key((0.14, 0.02, -1), (0.06, 0.02, -1), NEUTRAL)          # world: arms hang, palms in
TRAP_BAR = {"posture": {"type": "stand", "width": 0.12}, "implement": "frame", "frame": "hex",
            "body": {"keys": [{"drop": 0.34, "back": 0.1, "lean": 38}, {}], "head_level": 0.5},
            "arm": {"frame": "world", "keys": [SIDE_HANDLE], "elbow_out": [1, 0, 0]}, "camera": {"az": 35, "el": 8}}
def seated_calf(pad):
    """Seated calf raise: heels rise under a pad (or bar) across the knees, hands resting on it."""
    return {"posture": {"type": "seat", "feet_fwd": 0.9}, "implement": "none",
            "body": {"keys": [{"heel": 0}, {"heel": 32}]},
            "pads": [{"bone": "upperleg02.L", "t": 0.85, "off": [-0.1, 0, 0.1], "size": pad, "tilt": False}],
            "arm": {"keys": [key((0.12, 0.35, -0.93), (0.02, 0.6, -0.8), (0, 0, 1))], "elbow_out": [1, 0, -0.3]},
            "camera": {"az": 60, "el": 8}}


MB_UP = key((0.2, 0.2, 0.96), (-0.35, 0.15, 0.92), (0, -1, 0))   # ball overhead between the palms


def cable(impl, anchor=None, **extra):
    """Swap the implement for a cable attachment (`cable` handles, `cable_bar`, `cable_rope`) on a pulley at
    `anchor` (torso-frame offset from the shoulders at frame 1)."""
    def patch(spec):
        spec["implement"] = impl
        if anchor is not None:
            spec["cable"] = dict({"anchor": list(anchor)}, **extra)
        spec.pop("bar_floor", None)
        if impl != "cable_bar":
            for k in ("grip", "palm", "slide"):
                spec.get("arm", {}).pop(k, None)
        return spec
    return patch


def thumbs(t):
    def patch(spec):
        for k in spec["arm"]["keys"]:
            k["thumb"] = list(t)
        return spec
    return patch


def close_hands(x=0.04):
    """Hands a V-handle apart: the keys' outward reach is cut so the wrists nearly meet in front."""
    def patch(spec):
        for k in spec["arm"]["keys"]:
            k["fore"][0] = -abs(x * 3)
        return spec
    return patch


def v_handle(spec):
    spec["lines"] = spec.get("lines", []) + [{"a": {"obj": "L"}, "b": {"obj": "R"}, "steel": True}]
    return spec


def keys(*ks, frame=None, **arm):
    def patch(spec):
        spec["arm"] = dict(spec.get("arm", {}), keys=list(ks), **arm)
        if frame:
            spec["arm"]["frame"] = frame
        return spec
    return patch


def posture(**p):
    def patch(spec):
        spec["posture"] = p
        return spec
    return patch


def camera(az, el=8):
    def patch(spec):
        spec["camera"] = {"az": az, "el": el}
        return spec
    return patch


ROPE_ROW = [key((0.15, 1, 0.05), (0.1, 1, 0.05), (0, 0, 1)), key((1, -0.25, 0.05), (0.15, 1, 0.1), (0, 0, 1))]
NECK_ROW = key((1, -0.3, 0.15), (0.1, 1, 0.45), (0, 0, 1))
CHEST_PRESS = [key((0.85, -0.35, -0.2), (0.1, 1, 0.05), (0, 0, 1)), key((0.22, 1, 0.02), (0.1, 1, 0.02), (0, 0, 1))]
PULL_THROUGH = [key((0.05, 0.25, -1), (-0.05, 0.15, -1), NEUTRAL)]
TWIST_HANDS = key((0.15, 0.6, -0.8), (-0.75, 0.65, -0.1), (0, 0, 1))


def levers(pivot, ref="upperarm01", post=True):
    """Lever-machine arms: a steel arm from a fixed pivot (world offset from the `ref` joint at frame 1) to each
    handle, standing on a post. The handles move on the hands' key poses; the arms swing with them."""
    def patch(spec):
        lines = []
        for h, sx in (("L", 1), ("R", -1)):
            if h not in spec.get("hands", "LR"):
                continue
            end = {"world": [sx * pivot[0], pivot[1], pivot[2]], "under": {"bone": f"{ref}.{h}"}, "rel": True}
            if post:
                end["post"] = "in"
            lines.append({"a": {"obj": h}, "b": end, "steel": True, "r": 0.022})
        spec["lines"] = spec.get("lines", []) + lines
        return spec
    return patch


def machine_seat(back=85):
    return posture(type="seat", backrest=back) if back else posture(type="seat")


PRESS_KEYS = [key((0.85, -0.35, -0.2), (0.1, 1, 0.05), (0, 0, 1)), key((0.22, 1, 0.02), (0.1, 1, 0.02), (0, 0, 1))]
OVERHEAD_KEYS = [key((0.9, 0.1, -0.35), (0.05, 0.15, 1), (0, -1, 0)), key((0.3, 0.1, 0.95), (0.2, 0.05, 1), (0, -1, 0))]


def machine_press(top, pivot=(0.3, 0.35, 0.55)):
    return compose(machine_seat(), cable("handle"), keys(PRESS_KEYS[0], top, elbow_out=[0.6, -1, -0.3]),
                   levers(pivot), camera(55, 10))


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
    "Dumbbell_Incline_Row": ("Bent Over Two-Dumbbell Row", prone(35)),
    "Incline_Bench_Pull": ("Bent Over Barbell Row", prone(40)),
    "Lying_Cambered_Barbell_Row": ("Bent Over Barbell Row", prone(8, hip_z=0.98)),
    "Dumbbell_Lying_Rear_Lateral_Raise": ("Bent Over Dumbbell Rear Delt Raise With Head On Bench", prone(30)),
    "Lying_Rear_Delt_Raise": ("Bent Over Dumbbell Rear Delt Raise With Head On Bench", prone(30)),
    "Dumbbell_Lying_One-Arm_Rear_Lateral_Raise": ("Bent Over Dumbbell Rear Delt Raise With Head On Bench",
                                                  compose(prone(30), one_arm)),
    "Seated_Bent-Over_Rear_Delt_Raise": ("Bent Over Dumbbell Rear Delt Raise With Head On Bench", seated_lean()),
    "Seated_Bent-Over_One-Arm_Dumbbell_Triceps_Extension": ("Standing Bent-Over One-Arm Dumbbell Triceps Extension",
                                                            seated_lean()),
    "Seated_Bent-Over_Two-Arm_Dumbbell_Triceps_Extension": ("Standing Bent-Over Two-Arm Dumbbell Triceps Extension",
                                                            seated_lean()),
    "Spider_Curl": (None, spider_curl),
    "Straight_Raises_on_Incline_Bench": (None, incline_raises),
    "Middle_Back_Shrug": (None, middle_back_shrug),
    "Barbell_Curls_Lying_Against_An_Incline": ("Barbell Curl", incline_back(45)),
    "Front_Incline_Dumbbell_Raise": (None, front_incline_raise),
    "Decline_Crunch": ("Crunches", decline),
    "Decline_Oblique_Crunch": ("Oblique Crunches", decline),
    "Decline_Reverse_Crunch": ("Reverse Crunch", lambda s: {k: v for k, v in decline(s, -15).items() if k != "pad"}),
    "Flat_Bench_Lying_Leg_Raise": ("Flat Bench Lying Leg Raise", on_bench),
    "Bent-Arm_Barbell_Pullover": (None, pullover()),
    "Wide-Grip_Decline_Barbell_Pullover": (None, pullover(-15, 0.36, bent=False)),
    "Flat_Bench_Leg_Pull-In": ("Flat Bench Lying Leg Raise", compose(on_bench, leg_pull_in)),
    "Seated_Leg_Tucks": (None, seated_tucks),
    "Weighted_Sit-Ups_-_With_Bands": ("Sit-Up", decline_band_situp),
    "Triceps_Pushdown_-_V-Bar_Attachment": ("Triceps Pushdown", compose(
        cable("cable"), thumbs((0, 0.3, 0.95)), close_hands(), v_handle)),
    "V-Bar_Pulldown": ("Close-Grip Front Lat Pulldown", compose(
        cable("cable"), thumbs((0, -1, 0)), close_hands(), v_handle)),
    "Rope_Straight-Arm_Pulldown": ("Straight-Arm Pulldown", compose(cable("cable_rope"), thumbs((0, 1, 0)))),
    "Cable_Hammer_Curls_-_Rope_Attachment": ("Standing Biceps Cable Curl", compose(
        cable("cable_rope", (0, 0.45, -1.45)), keys(
            key((0.1, -0.03, -1), (0.05, 0.2, -1), (0, 1, 0.2)), key((0.1, -0.03, -1), (0.02, 0.74, 0.67), (0, 0.67, -0.74)),
            elbow_out=[0.1, -1, -0.2]))),
    "Standing_One-Arm_Cable_Curl": ("Standing Biceps Cable Curl", compose(
        cable("cable", (0.15, 0.45, -1.45)), keys(key((0.1, -0.03, -1), (0.2, 0.21, -0.98), (1, 0, 0)),
                                                  key((0.1, -0.03, -1), (0.2, 0.74, 0.67), (1, 0, 0)),
                                                  elbow_out=[0.1, -1, -0.2]), one_arm)),
    "One_Arm_Lat_Pulldown": ("Close-Grip Front Lat Pulldown", compose(
        cable("cable", (0.3, 0.05, 1.5)), keys(key((0.45, 0.05, 1), (0.25, 0, 1), (0, -1, 0)),
                                               key((0.7, -0.35, -0.62), (0.12, 0.2, 1), (0, -1, 0)),
                                               frame="world", elbow_out=[1, -0.3, -0.2]), one_arm)),
    "Upright_Cable_Row": ("Upright Barbell Row", cable("cable_bar", (0, 0.35, -1.45))),
    "Cable_Shrugs": ("Barbell Shrug", cable("cable_bar", (0, 0.4, -1.45))),
    "Cable_Deadlifts": ("Romanian Deadlift", cable("cable_bar", (0, 0.55, -1.5))),
    "Cable_Rope_Rear-Delt_Rows": (None, compose(
        posture(type="stand", width=0.14, lean=5), cable("cable_rope", (0, 1.4, -0.05)),
        keys(*ROPE_ROW, elbow_out=[1, -0.2, 0.3]), camera(40))),
    "Low_Pulley_Row_To_Neck": ("Seated Cable Rows", lambda s: dict(s, arm=dict(
        s["arm"], keys=[s["arm"]["keys"][0], NECK_ROW], elbow_out=[1, -0.2, 0.3]))),
    "Cable_Chest_Press": (None, compose(
        posture(type="stand", lean=8, width=0.14), cable("cable", (0.55, -0.7, -0.05)),
        keys(*CHEST_PRESS, elbow_out=[0.6, -1, -0.3]), camera(72))),
    "Standing_Cable_Chest_Press": (None, compose(
        posture(type="stand", lean=8, width=0.14), cable("cable", (0.55, -0.7, -0.05)),
        keys(*CHEST_PRESS, elbow_out=[0.6, -1, -0.3]), camera(72))),
    "Incline_Cable_Chest_Press": (None, compose(
        posture(type="seat", back_deg=40), cable("cable", (0.6, -0.4, -0.9)),
        keys(*CHEST_PRESS, elbow_out=[0.6, -1, -0.3]), camera(56, 20))),
    "Flat_Bench_Cable_Flyes": ("Dumbbell Flyes", cable("cable", (1.1, -0.2, -0.3))),
    "Incline_Cable_Flye": ("Incline Dumbbell Flyes", cable("cable", (1.1, -0.2, -0.6))),
    "Low_Cable_Crossover": ("Cable Crossover", compose(cable("cable", (0.9, 0.1, -1.35)), keys(
        key((0.95, 0.2, -0.3), (0.95, 0.3, -0.25), (0, 1, 0)), key((0.2, 1, 0.35), (-0.05, 1, 0.45), (0, 0.4, 1)),
        elbow_out=[0.3, -0.6, -1]))),
    "Cable_Rear_Delt_Fly": (None, compose(
        posture(type="stand", width=0.13), cable("cable", (-0.7, 1.0, 0.25)),
        keys(key((-0.1, 1, 0.08), (-0.1, 1, 0.08), (-1, 0, 0)), key((1, 0.12, 0.05), (1, 0.12, 0.05), (0, 1, 0)),
             elbow_out=[0.3, -0.3, -1]), camera(30))),
    "Bent_Over_Low-Pulley_Side_Lateral": ("Bent Over Dumbbell Rear Delt Raise With Head On Bench", compose(
        cable("cable", (-0.5, 0.25, -1.1)),
        posture(type="stand", lean=55, width=0.14))),
    "Cable_Preacher_Curl": ("Preacher Curl", cable("cable_bar", (0, 1.0, -0.9))),
    "Cable_Lying_Triceps_Extension": ("EZ-Bar Skullcrusher", cable("cable_bar", (0, -0.35, 1.25))),
    "Cable_Incline_Triceps_Extension": ("Incline Barbell Triceps Extension", cable("cable_bar", (0, -0.5, 1.25))),
    "Kneeling_Cable_Triceps_Extension": ("Cable Rope Overhead Triceps Extension", lambda s: dict(
        s, posture={"type": "kneel", "lean": 20})),
    "Pull_Through": (None, compose(
        posture(type="stand", width=0.3, toe_out=20), cable("cable_rope", (0, -0.8, -1.45)),
        lambda s: dict(s, body={"keys": [{"drop": 0.12, "back": 0.14, "lean": 70}, {}], "head_level": 0.5}),
        keys(*PULL_THROUGH, frame="world", elbow_out=[1, 0, 0]), camera(75))),
    "Band_Good_Morning_Pull_Through": (None, compose(
        posture(type="stand", width=0.3, toe_out=20),
        lambda s: dict(s, body={"keys": [{"drop": 0.12, "back": 0.14, "lean": 70}, {}], "head_level": 0.5},
                       implement="band_handle",
                       lines=[{"a": {"obj": h}, "b": {"world": [0, 0.9, 0.05], "under": {"bone": "root"}}}
                              for h in "LR"]),
        keys(*PULL_THROUGH, frame="world", elbow_out=[1, 0, 0]), camera(75))),
    "Cable_Russian_Twists": ("Russian Twist", compose(cable("cable", (1.3, 0.35, -0.25), mirror=False),
                                                       keys(TWIST_HANDS, elbow_out=[1, 0, -0.4]))),
    "One-Arm_High-Pulley_Cable_Side_Bends": ("Dumbbell Side Bend", compose(
        cable("cable", (0.35, 0.05, 1.3)), keys(key((0.6, 0.0, 0.8), (0.2, 0.0, 1), (0, -1, 0)), sides="L",
                                                rest=key((0.9, -0.1, 0.4), (-0.75, 0.25, 0.6), (0, 0, 1)),
                                                frame="torso"),
        lambda s: dict(s, body={"keys": [{"side": -10}, {"side": 22}]}))),
    "Leverage_Chest_Press": (None, machine_press(PRESS_KEYS[1])),
    "Machine_Bench_Press": (None, machine_press(PRESS_KEYS[1])),
    "Leverage_Incline_Chest_Press": (None, machine_press(key((0.22, 0.8, 0.55), (0.1, 0.8, 0.55), (0, 0, 1)),
                                                         (0.3, 0.45, 0.2))),
    "Leverage_Decline_Chest_Press": (None, machine_press(key((0.22, 0.9, -0.4), (0.1, 0.9, -0.4), (0, 0, 1)),
                                                         (0.3, 0.3, 0.75))),
    "Leverage_Shoulder_Press": (None, compose(machine_seat(), cable("handle"), keys(*OVERHEAD_KEYS, elbow_out=[1, 0, -0.3]),
                                              levers((0.32, 0.55, -0.05)), camera(50, 8))),
    "Machine_Shoulder_Military_Press": (None, compose(machine_seat(), cable("handle"),
                                                      keys(*OVERHEAD_KEYS, elbow_out=[1, 0, -0.3]),
                                                      levers((0.32, 0.55, -0.05)), camera(50, 8))),
    "Leverage_High_Row": (None, compose(machine_seat(0), cable("handle"), keys(
        key((0.2, 0.75, 0.65), (0.15, 0.75, 0.65), (0, 0, 1)), key((0.4, -0.6, -0.7), (0.05, 0.75, 0.65), (0, 0, 1)),
        elbow_out=[0.6, -0.3, -1]), levers((0.35, 0.55, 0.85)), camera(70, 8))),
    "Leverage_Iso_Row": (None, compose(machine_seat(0), cable("handle"), keys(
        key((0.12, 1, -0.2), (0.05, 1, -0.05), (0, 0, 1)), key((0.2, -0.7, -0.7), (0.03, 1, 0.05), (0, 0, 1)),
        elbow_out=[0.4, -0.3, -1]), levers((0.3, -0.95, -0.55)),
        lambda s: dict(s, boxes=[{"size": [0.34, 0.08, 0.4], "at": [0, -0.32, 0.95]}]), camera(70, 8))),
    "Leverage_Shrug": ("Dumbbell Shrug", compose(cable("handle"), levers((0.1, -0.75, -0.55), ref="lowerarm02"),
                                                 camera(40, 8))),
    "Leverage_Deadlift": ("Barbell Deadlift", compose(
        cable("handle"), keys(key((0.25, 0.03, -1), (0.12, 0.04, -1), NEUTRAL), frame="world", elbow_out=[1, 0, 0]),
        levers((0.12, -0.8, 0.05), ref="lowerarm02"), camera(40, 8))),
    "Dip_Machine": (None, compose(machine_seat(), cable("handle"), keys(
        key((0.25, -0.75, -0.6), (0.05, 0.6, -0.8), NEUTRAL), key((0.2, -0.1, -1), (0.12, 0.05, -1), NEUTRAL),
        elbow_out=[0.3, 1, 0]), levers((0.3, 0.55, -0.5)), camera(60, 8))),
    "Reverse_Machine_Flyes": (None, compose(
        posture(type="seat"), cable("handle"),
        keys(key((0.1, 1, 0.05), (0.1, 1, 0.05), (0, 0, 1)), key((1, 0.12, 0.05), (1, 0.12, 0.05), (0, 0, 1)),
             elbow_out=[0.3, -0.3, -1]), levers((0.05, 0.0, 0.45)),
        lambda s: dict(s, boxes=[{"size": [0.34, 0.08, 0.45], "at": [0, -0.3, 1.0]}]), camera(150, 14))),
    "Butterfly": (None, compose(
        machine_seat(), cable("handle"),
        keys(key((1, 0.1, 0.05), (0.75, 0.3, 0.6), (0, 1, 0)), key((0.3, 1, 0.05), (-0.2, 0.6, 0.75), (0, 0, 1)),
             elbow_out=[0.3, -0.3, -1]), levers((0.05, 0.05, 0.5)), camera(40, 14))),
    "Hack_Squat": (None, compose(
        posture(type="stand", width=0.16, lean=-32, toe_out=12), cable("handle"),
        lambda s: dict(s, body={"keys": [{"back": 0.18}, {"back": 0.5, "drop": 0.42}], "head_level": 0.4},
                       pads=[{"bone": "spine03", "off": [0, -0.16, 0.05], "size": [0.4, 0.08, 0.7], "rail": 1.5},
                             {"bone": "clavicle.L", "off": [0, -0.02, 0.07], "size": [0.12, 0.25, 0.06]},
                             {"bone": "clavicle.R", "off": [0, -0.02, 0.07], "size": [0.12, 0.25, 0.06]}]),
        keys(key((0.5, 0.35, -0.8), (-0.05, 0.3, 1), (-1, 0, 0)), elbow_out=[0.4, 0.2, -1]), camera(75, 6))),
    "Narrow_Stance_Hack_Squats": (None, compose(
        posture(type="stand", width=0.09, lean=-32, toe_out=8), cable("handle"),
        lambda s: dict(s, body={"keys": [{"back": 0.18}, {"back": 0.5, "drop": 0.42}], "head_level": 0.4},
                       pads=[{"bone": "spine03", "off": [0, -0.16, 0.05], "size": [0.4, 0.08, 0.7], "rail": 1.5},
                             {"bone": "clavicle.L", "off": [0, -0.02, 0.07], "size": [0.12, 0.25, 0.06]},
                             {"bone": "clavicle.R", "off": [0, -0.02, 0.07], "size": [0.12, 0.25, 0.06]}]),
        keys(key((0.5, 0.35, -0.8), (-0.05, 0.3, 1), (-1, 0, 0)), elbow_out=[0.4, 0.2, -1]), camera(75, 6))),
    "Front_Plate_Raise": ("Front Dumbbell Raise", lambda s: dict(s, implement="plate", arm={
        "keys": [key((-0.1, 0.25, -1), (-0.15, 0.3, -1), (0, 0, 1)), key((-0.1, 1, 0.12), (-0.15, 1, 0.18), (0, 0, 1))],
        "elbow_out": [1, -0.3, 0]})),
    "Plate_Twist": ("Russian Twist", lambda s: dict(s, implement="plate", arm={
        "keys": [key((0.12, 0.6, -0.8), (-0.3, 0.95, 0.05), (0, 0, 1))], "elbow_out": [1, 0, -0.4]})),
    "Car_Drivers": (None, lambda s: dict(s, posture={"type": "stand", "width": 0.14}, implement="plate", cycle=True,
        arm={"keys": [key((-0.05, 1, 0.22), (-0.1, 1, 0.25), (0, 0, 1)), key((-0.05, 1, -0.12), (-0.1, 1, -0.1), (0, 0, 1)),
                      key((-0.05, 1, 0.22), (-0.1, 1, 0.25), (0, 0, 1))], "offset_R": 0.5, "elbow_out": [1, -0.3, 0]},
        camera={"az": 40, "el": 6})),
    "Reverse_Plate_Curls": (None, lambda s: dict(s, posture={"type": "stand", "width": 0.14}, implement="plate",
        arm={"frame": "world", "keys": [key((0.0, 0.08, -1), (-0.12, 0.25, -1), (0, 0, 1)),
                                        key((0.0, 0.08, -1), (-0.12, 0.6, 0.8), (0, 0, 1))], "elbow_out": [0.3, -1, 0]},
        camera={"az": 70, "el": 6})),
    "Weighted_Ball_Side_Bend": (None, lambda s: dict(s, posture={"type": "stand", "width": 0.16}, implement="ball",
        body={"keys": [{"side": 22}, {"side": -22}], "head_level": 0.6}, cycle=False,
        arm={"keys": [MB_UP], "elbow_out": [1, 0, 0.2]}, camera={"az": 10, "el": 6})),
    "Push-Ups_With_Feet_On_An_Exercise_Ball": ("Push-Ups With Feet Elevated", lambda s: dict(
        s, posture=dict(s["posture"], feet_z=0.6, feet_ball=0.3))),
    "Crunch_-_Legs_On_Exercise_Ball": ("Crunches", lambda s: dict(
        s, posture={"type": "floor_supine", "feet_free": True},
        body={"keys": [{"hip": 90, "knee": 90}, {"hip": 90, "knee": 90, "curl": 38}], "head_level": 0},
        spheres=[{"r": 0.3, "bone": "lowerleg01.L", "t": 0.7, "off": [0, 0, -0.33], "x": 0}])),
    "Trap_Bar_Deadlift": (None, lambda s: dict(s, **TRAP_BAR)),
    "Car_Deadlift": (None, lambda s: dict(s, **dict(TRAP_BAR, frame="rickshaw", camera={"az": 60, "el": 8}))),
    "Rickshaw_Deadlift": (None, lambda s: dict(s, **dict(TRAP_BAR, frame="rickshaw", camera={"az": 60, "el": 8}))),
    "Rickshaw_Carry": ("Farmer's Walk", lambda s: dict(s, implement="frame", frame="rickshaw",
                                                      arm=dict(s["arm"], keys=[SIDE_HANDLE]))),
    "Sled_Push": ("Prowler Sprint", lambda s: s),
    "Ring_Dips": ("Dips - Triceps Version", lambda s: dict(s, arm=dict(s["arm"], rings=True), camera={"az": 40, "el": 8})),
    "Suspended_Push-Up": ("Pushups", lambda s: dict(s, implement="dip_bars", posture=dict(s["posture"], alpha=38),
                                                   arm=dict(s["arm"], rings=True))),
    "Inverted_Row_with_Straps": ("Inverted Row", lambda s: dict(s, implement="dip_bars", arm=dict(
        s["arm"], rings=True, hang=True, keys=[key((0.2, 0.15, 1), (0.04, 0.15, 1), NEUTRAL)]))),
    "Seated_Calf_Raise": (None, lambda s: dict(s, **seated_calf([0.45, 0.16, 0.08]))),
    "Barbell_Seated_Calf_Raise": (None, lambda s: dict(s, **seated_calf([1.3, 0.035, 0.035]))),
    "Donkey_Calf_Raises": (None, lambda s: dict(
        s, posture={"type": "stand", "width": 0.13}, implement="floor",
        body={"keys": [{"lean": 78, "heel": 0}, {"lean": 78, "heel": 32, "drop": -0.08}], "head_level": 0.4},
        arm={"frame": "world", "hand_z": 1.0, "hand_box": True, "elbow_out": [0.6, -0.5, -0.4],
             "keys": [key((0.12, 0.3, -0.95), (0.08, 0.98, 0.0), (-1, 0, 0))]}, camera={"az": 75, "el": 6})),
    "Calf-Machine_Shoulder_Shrug": (None, lambda s: dict(
        s, posture={"type": "stand", "width": 0.13}, implement="none",
        body={"keys": [{"shrug": 0}, {"shrug": 30}]},
        pads=[{"bone": f"clavicle.{h}", "off": [0, -0.02, 0.07], "size": [0.12, 0.25, 0.06]} for h in "LR"],
        boxes=[{"size": [0.1, 0.1, 1.7], "at": [0, 0.35, 0.85]}, {"size": [0.6, 0.08, 0.08], "at": [0, 0.3, 1.62]}],
        arm={"keys": [ARMS_DOWN]}, camera={"az": 40, "el": 8})),
    "T-Bar_Row_with_Handle": ("Bent Over Barbell Row", lambda s: dict(
        s, implement="frame", frame="tbar", arm={"frame": "world", "elbow_out": [0.4, -1, 0], "keys": [
            key((0.02, 0.1, -1), (-0.03, 0.08, -1), NEUTRAL), key((0.3, -0.85, -0.1), (-0.03, 0.25, -1), NEUTRAL)]})),
    "Barbell_Hack_Squat": ("Barbell Deadlift", lambda s: dict(
        s, body={"keys": [{"drop": 0.42, "back": 0.04, "lean": 22}, {}], "head_level": 0.8},
        arm=dict(s["arm"], palm=[0, -1, 0], keys=[key((0.1, -0.2, -1), (0.04, -0.12, -1), (-1, 0, 0))]),
        camera={"az": 80, "el": 6})),
    "Weighted_Pull_Ups": ("Pullups", lambda s: dict(s, camera={"az": 25, "el": 5}, pads=[
        {"bone": "upperleg01.L", "t": 0.45, "off": [-0.1, 0.12, -0.05], "disc": 0.17, "face_fwd": True}])),
    "Weighted_Bench_Dip": ("Bench Dips", lambda s: dict(s, pads=[
        {"bone": "upperleg01.L", "t": 0.5, "off": [-0.1, 0, 0.08], "disc": 0.2}])),
    "Knee_Hip_Raise_On_Parallel_Bars": ("Dips - Triceps Version", lambda s: dict(
        s, body={"keys": [{"hip": 5, "knee": 20}, {"hip": 100, "knee": 95}], "head_level": 0.5})),
    "Weighted_Crunches": ("Crunches", lambda s: dict(s, implement="plate", arm={
        "keys": [key((0.35, 0.45, -0.82), (-0.55, 0.8, 0.25), (0, 0, 1))], "elbow_out": [1, 0, -0.4]})),
    "Crunch_-_Hands_Overhead": ("Crunches", lambda s: dict(s, arm={
        "keys": [key((0.15, 0.1, 0.98), (0.1, 0.12, 1), (-1, 0, 0))], "elbow_out": [1, 0, 0]})),
    "Tuck_Crunch": ("Crunches", lambda s: dict(s, posture={"type": "floor_supine", "feet_free": True},
        body={"keys": [{"hip": 70, "knee": 80}, {"hip": 105, "knee": 110, "curl": 34}], "head_level": 0})),
    "Leg_Pull-In": ("Reverse Crunch", lambda s: dict(s, body={"keys": [{"hip": 25, "knee": 20},
                                                                      {"hip": 105, "knee": 115}], "head_level": 0})),
    "Hanging_Pike": ("Hanging Leg Raise", lambda s: dict(s, body={"keys": [{"hip": 0, "knee": 0},
                                                                          {"hip": 150, "knee": 0, "curl": 20}],
                                                                 "head_level": 0})),
    "Gorilla_Chin_Crunch": ("Pullups", lambda s: dict(s, body={"keys": [{"drop": 0, "hip": 10, "knee": 20},
                                                                       {"drop": -0.45, "hip": 105, "knee": 115}],
                                                              "head_level": 0})),
    "Scapular_Pull-Up": ("Pullups", lambda s: dict(s, body={"keys": [{"drop": 0.02}, {"drop": -0.07}],
                                                           "head_level": 0})),
    "Gironda_Sternum_Chins": ("Pullups", lambda s: dict(s, body={"keys": [{"drop": 0}, {"drop": -0.42, "lean": -28}],
                                                                "head_level": 0.3})),
    "Jackknife_Sit-Up": ("Crunches", lambda s: dict(
        s, posture={"type": "floor_supine", "knees": 0, "feet_free": True},
        body={"keys": [{"hip": 0}, {"hip": 70, "curl": 45}], "head_level": 0},
        arm={"keys": [key((0.15, 0.1, 0.98), (0.1, 0.12, 1), (-1, 0, 0)), key((0.15, 0.95, 0.25), (0.1, 1, 0.2), (-1, 0, 0))],
             "elbow_out": [1, 0, 0]})),
    "Alternate_Heel_Touchers": ("Crunches", lambda s: dict(
        s, cycle=True, body={"keys": [{"curl": 22, "side": 18}, {"curl": 22, "side": -18}, {"curl": 22, "side": 18}],
                             "head_level": 0},
        arm={"keys": [key((0.25, 0.25, -0.93), (0.15, 0.3, -0.94), (0, 1, 0))], "elbow_out": [1, 0, 0]})),
    "Clean_Pull": ("Barbell Deadlift", lambda s: dict(s, body={"keys": [{"drop": 0.24, "back": 0.16, "lean": 62},
                                                                     {"heel": 28, "shrug": 25, "lean": -4}],
                                                              "head_level": 0.5})),
    "Snatch_Pull": ("Barbell Deadlift", lambda s: dict(s, arm=dict(s["arm"], grip=0.42),
                                                      body={"keys": [{"drop": 0.28, "back": 0.16, "lean": 58},
                                                                     {"heel": 28, "shrug": 25, "lean": -4}],
                                                            "head_level": 0.5})),
    "Drag_Curl": ("Barbell Curl", lambda s: dict(s, arm=dict(s["arm"], keys=[
        s["arm"]["keys"][0], key((0.15, -0.75, -0.6), (0.1, 0.25, 0.96), (1, 0, 0))]))),
    "Reverse_Triceps_Bench_Press": ("Close-Grip Barbell Bench Press", thumbs((1, 0, 0.1))),
    "Reverse_Barbell_Preacher_Curls": ("Preacher Curl", thumbs((-1, 0, 0))),
    "One_Arm_Floor_Press": ("Dumbbell Floor Press", one_arm),
    "Wind_Sprints": ("Trail Running/Walking", lambda s: dict(s, body=dict(s["body"], keys=[
        dict(k, lean=16, **{a: v * (1.35 if a.startswith("fy") else 1.2) for a, v in k.items() if a[:2] in ("fy", "fz")})
        for k in s["body"]["keys"]]))),
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
