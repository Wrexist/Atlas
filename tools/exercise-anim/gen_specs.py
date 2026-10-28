# Writes a kit.py spec (specs/gen/<id>.json) for every exercise in exercises.json that a movement template covers,
# and lists the rest, which keep the muscle map in the app.
# python3 gen_specs.py [--list-missing]
import json, math, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "..", "..", "Peptide", "Resources", "exercises.json")
OUT = os.path.join(HERE, "specs", "gen")
FAMILIES = json.load(open(os.path.join(HERE, "families.json")))

MUSCLES = {"abdominals": "abs", "lats": "lats", "middle back": "middle_back", "lower back": "lower_back",
           "quadriceps": "quads", "hamstrings": "hamstrings", "glutes": "glutes", "calves": "calves",
           "chest": "chest", "biceps": "biceps", "triceps": "triceps", "forearms": "forearms", "traps": "traps",
           "neck": "traps", "adductors": "adductors", "abductors": "glutes"}


def delts(name, family):
    n = name.lower()
    if re.search(r"rear|reverse fl|face pull|bent.over.*(raise|fly)|back fly", n):
        return "rear_delts"
    if family in ("raise",) and not re.search(r"front", n):
        return "side_delts"
    if family in ("row", "vpull"):
        return "rear_delts"
    return "front_delts"


def muscles(e, family):
    def conv(names):
        return [delts(e["name"], family) if m == "shoulders" else MUSCLES[m] for m in names if m in MUSCLES or
                m == "shoulders"]
    primary = conv(e["primaryMuscles"])
    secondary = [m for m in conv(e["secondaryMuscles"]) if m not in primary]
    return primary, secondary


# ---------------------------------------------------------------- key-pose helpers (torso or world frame)
def fore(theta_deg, out=0.2):
    """Forearm direction swung from straight down (0) forward and up (180) in the sagittal plane."""
    t = math.radians(theta_deg)
    return [out, round(math.sin(t), 4), round(-math.cos(t), 4)]


def key(upper, fore_, thumb):
    return {"upper": list(upper), "fore": list(fore_), "thumb": list(thumb)}


HANG_W = [key((0.12, 0.03, -1), (0.04, 0.04, -1), (0, 1, 0))]            # world: arms hanging, neutral hands
HANG_OUT = [key((0.24, 0, -1), (0.06, 0, -1), (0, 1, 0))]              # world: hanging clear of the thighs
HANG_BAR = [key((0.1, 0.04, -1), (0.03, 0.05, -1), (-1, 0, 0))]          # world: hanging onto a bar, overhand
HANG_T = [key((0.12, 0.03, -1), (0.04, 0.04, -1), (0, 1, 0))]           # torso: arms hanging at the sides
HEAD_HANDS = [key((0.95, 0.05, 0.35), (-0.75, 0.25, 0.6), (0, 0, 1))]   # torso: hands behind the head
STAND = {"type": "stand"}


def has(n, *words):
    return any(re.search(w, n) for w in words)


# ---------------------------------------------------------------- templates per family
def curl(n, eq):
    if has(n, "wrist|finger"):
        return None     # the rig keeps wrists straight, so these would play as a biceps curl
    thumb = (0, 1, 0) if has(n, "hammer", "cross body", "rope") else (-1, 0, 0) if has(n, "reverse") else (1, 0, 0)
    if has(n, "preacher") and not has(n, "machine|cable|one arm|reverse|hammer|zottman"):
        keys = [key((0.12, 0.75, -0.65), fore(55), thumb), key((0.12, 0.75, -0.65), fore(160), thumb)]
        spec = {"posture": {"type": "seat"}, "camera": {"az": 70, "el": 8},
                "arm": {"keys": keys, "elbow_out": [0.1, -0.6, -1], "pad": True}}
        if eq == "dumbbell" or has(n, "dumbbell"):
            spec["implement"] = "dumbbell"
        else:
            spec.update(implement="ezbar")
            spec["arm"].update(grip=0.2, palm=[0, -1, 0])
        return spec
    if has(n, "^concentration curl"):
        keys = [key((-0.05, 0.35, -1), (0.05, 0.25, -1), (1, 0, 0)), key((-0.05, 0.35, -1), (-0.1, -0.2, 1), (1, 0, 0))]
        return {"posture": {"type": "seat", "lean": 35, "knees_apart": 0.3}, "implement": "dumbbell", "hands": "L",
                "arm": {"frame": "world", "sides": "L", "keys": keys, "elbow_out": [1, 0, 0],
                        "rest": key((0.1, 0.4, -1), (0.0, 0.5, -1), (0, 1, 0))}, "camera": {"az": 40, "el": 10}}
    if has(n, "preacher", "concentration", "spider", "drag", "zottman", "prone", "lying", "high cable",
           "overhead", "machine", "plate", "towel", "21"):
        return None
    upper = (0.035, -0.02, -1) if eq == "dumbbell" else (0.1, -0.03, -1)
    keys = [key(upper, fore(12), thumb), key(upper, fore(132), thumb)]
    spec = {"arm": {"keys": keys, "elbow_out": [0.1, -1, -0.2]}, "camera": {"az": 35, "el": 6}}
    if has(n, "incline"):
        spec["posture"] = {"type": "seat", "back_deg": 45}
        spec["arm"]["keys"] = [key((0.1, -0.35, -1), fore(-5), thumb), key((0.1, -0.35, -1), fore(120), thumb)]
        spec["camera"] = {"az": 60, "el": 10}
    elif has(n, "seated"):
        spec["posture"] = {"type": "seat"}
    else:
        spec["posture"] = STAND
    if eq in ("barbell", "e-z curl bar") or has(n, "barbell", "ez"):
        spec.update(implement="ezbar" if has(n, "ez", "e-z") or eq == "e-z curl bar" else "barbell")
        spec["arm"].update(grip=0.17 if has(n, "close") else 0.3 if has(n, "wide") else 0.24, palm=[0, -1, 0])
    elif eq == "cable" or has(n, "cable"):
        spec.update(implement="cable_rope" if has(n, "rope") else "cable_bar", cable={"anchor": [0, 0.45, -1.45]})
        spec["arm"].update(grip=0.2, palm=[0, -1, 0])
    elif eq == "kettlebells":
        spec.update(implement="kettlebell")
    elif eq == "dumbbell" or has(n, "dumbbell"):
        spec.update(implement="dumbbell")
        if has(n, "alternat"):
            spec["alternate"] = True
    else:
        return None
    return spec


BENCH_BOTTOM_DB = key((0.85, -0.3, -0.25), (0.05, 1, 0.05), (-1, 0, 0.2))
BENCH_TOP_DB = key((0.18, 1, 0.02), (0.1, 1, 0.02), (-1, 0, 0.2))


def bench_posture(n):
    if has(n, "incline"):
        return {"type": "seat", "back_deg": 40}
    if has(n, "decline"):
        return {"type": "seat", "back_deg": -15}
    if has(n, "floor"):
        return {"type": "floor_supine", "knees": 90}
    return {"type": "seat", "back_deg": 0}


def hpress(n, eq):
    if has(n, "push.?up"):
        if has(n, "clap|plyo|single|\\bone\\b|knee|handstand|dive|spider|isometric|medicine|reverse grip"):
            return None
        wide = 0.34 if has(n, "wide") else 0.14 if has(n, "close|diamond|triangle") else 0.22
        alpha, posture, arm = 22, {"type": "plank"}, {}
        if has(n, "incline"):
            alpha, arm = 40, {"hand_z": 0.45, "hand_box": True}
        elif has(n, "decline"):
            alpha, posture = 4, {"type": "plank", "feet_z": 0.5}
        return {"posture": dict(posture, alpha=alpha), "implement": "floor",
                "body": {"keys": [{"alpha": 0}, {"alpha": -15}], "head_level": 0},
                "arm": dict(arm, frame="world", keys=[key((wide, 0.02, -1), (0.05, 0.03, -1), (-1, 0, 0))],
                            elbow_out=[0.7, -0.5, 0.2]), "camera": {"az": 65, "el": 14}}
    if has(n, "^dips|dip -|dips -|parallel bar dip"):
        lean = 18 if has(n, "chest") else 4
        return {"posture": {"type": "support", "bar_z": 1.25, "knees": 75}, "implement": "dip_bars",
                "body": {"keys": [{"drop": 0}, {"drop": 0.3, "lean": lean}], "head_level": 0.5},
                "arm": {"frame": "world", "keys": [key((0.12, 0, -1), (0.05, 0, -1), (0, 1, 0))],
                        "elbow_out": [0.25, -1, 0]}, "camera": {"az": 60, "el": 8}}
    if has(n, "standing cable chest press|cable chest press") and not has(n, "incline"):
        return {"posture": {"type": "stand", "lean": 8}, "implement": "cable", "cable": {"anchor": [0.55, -0.7, -0.05]},
                "arm": {"keys": [BENCH_BOTTOM_DB, BENCH_TOP_DB], "elbow_out": [0.6, -1, -0.3]},
                "camera": {"az": 40, "el": 8}}
    if has(n, "fly|flye") and eq == "dumbbell" and not has(n, "twist"):
        return fly(n, eq)
    if has(n, "fly|flye|svend|squeeze|guillotine|neck|around|leg-over|kettlebell"):
        return None
    if has(n, "machine|leverage") or eq == "machine":
        return {"posture": {"type": "seat", "back_deg": 85}, "implement": "handle",
                "arm": {"keys": [BENCH_BOTTOM_DB, BENCH_TOP_DB], "elbow_out": [0.6, -1, -0.3]},
                "camera": {"az": 60, "el": 8}}
    if has(n, "cable"):
        return None
    posture = bench_posture(n)
    cam = {"az": 56, "el": 30}
    if eq == "dumbbell" or has(n, "dumbbell"):
        keys = [BENCH_BOTTOM_DB, BENCH_TOP_DB]
        if has(n, "hammer grip|palm.in|neutral"):
            keys = [dict(k, thumb=[0, 0, 1]) for k in keys]
        spec = {"posture": posture, "implement": "dumbbell",
                "arm": {"keys": keys, "elbow_out": [0.6, -1, -0.3]}, "camera": cam}
        if has(n, "alternat"):
            spec["alternate"] = True
        if has(n, "one arm|one-arm|single"):
            spec["hands"] = "L"
            spec["arm"].update(sides="L", rest=key((0.35, -0.5, -0.8), (0.2, -0.2, -1), (0, 1, 0)))
        return spec
    if eq == "barbell" or has(n, "barbell|bench press"):
        close = has(n, "close")
        wide = has(n, "wide")
        upper_b = (0.4, -0.4, -0.3) if close else (0.8, -0.35, -0.2)
        return {"posture": posture, "implement": "barbell",
                "arm": {"grip": 0.16 if close else 0.36 if wide else 0.27, "palm": [0, -1, 0],
                        "keys": [key(upper_b, (0.1, 1, 0.1), (-1, 0, 0.1)), key((0.22, 1, 0.05), (0.1, 1, 0.02),
                                                                                (-1, 0, 0.1))],
                        "elbow_out": [0.6, -1, -0.3]}, "camera": cam}
    return None


def vpress(n, eq):
    if has(n, "^dumbbell one-arm shoulder press|^standing palm-in one-arm"):
        spec = vpress("dumbbell shoulder press", "dumbbell")
        spec["hands"] = "L"
        spec["arm"].update(sides="L", rest=HIPS_HANDS)
        return spec
    if has(n, "handstand|push press|jerk|bradford|cuban|landmine|\\bone\\b|single|kettlebell|"
           "behind"):
        return None
    seated = has(n, "seated|machine")
    posture = {"type": "seat", "backrest": 85} if seated else STAND
    thumb = (-1, 0.1, 0)
    if has(n, "arnold"):
        keys = [key((0.25, 0.6, -0.75), (0.1, 0.1, 1), (1, 0.2, 0)), key((0.7, 0.3, -0.2), (0.05, 0.1, 1), (0, 1, 0)),
                key((0.3, 0.05, 1), (0.1, 0, 1), thumb)]
    else:
        keys = [key((0.8, 0.3, -0.5), (0.05, 0.1, 1), thumb), key((0.3, 0.05, 1), (0.1, 0, 1), thumb)]
    spec = {"posture": posture, "arm": {"keys": keys, "elbow_out": [1, 0, -0.4]}, "camera": {"az": 35, "el": 8}}
    if eq == "machine" or has(n, "machine"):
        spec["implement"] = "handle"
    elif eq == "barbell" or has(n, "barbell|military"):
        spec["implement"] = "barbell"
        spec["arm"].update(grip=0.26, palm=[0, -1, 0.2],
                           keys=[key((0.45, 0.6, -0.65), (0.1, 0.25, 1), thumb), key((0.25, 0.1, 1), (0.1, 0, 1), thumb)])
    elif eq == "dumbbell" or has(n, "dumbbell|arnold"):
        spec["implement"] = "dumbbell"
        if has(n, "alternat"):
            spec["alternate"] = True
    elif eq == "cable":
        spec["implement"] = "cable"
        spec["cable"] = {"anchor": [0.6, 0, -1.2]}
        if has(n, "alternat"):
            spec["alternate"] = True
    else:
        return None
    return spec


def face_pull():
    keys = [key((0.15, 1, 0.15), (0.1, 1, 0.1), (0, 0, 1)), key((1, -0.1, 0.15), (0.05, 0.4, 1), (0, 0, 1))]
    return {"posture": {"type": "stand", "lean": -4}, "implement": "cable_rope", "cable": {"anchor": [0, 1.6, 0.15]},
            "arm": {"keys": keys, "elbow_out": [0.4, -0.2, -1]}, "camera": {"az": 60, "el": 8}}


def raise_(n, eq):
    if has(n, "face pull"):
        return face_pull() if eq == "cable" else None
    if has(n, "shrug"):
        impl = "barbell" if eq == "barbell" or has(n, "barbell") else "dumbbell"
        spec = {"posture": STAND, "implement": impl, "body": {"keys": [{"shrug": 0}, {"shrug": 30}]},
                "arm": {"frame": "world", "keys": HANG_BAR if impl == "barbell" else HANG_W,
                        "elbow_out": [1, -0.2, 0]}, "camera": {"az": 150, "el": 10}}
        if impl == "barbell":
            spec["arm"].update(grip=0.24, palm=[0, 1, 0])
        return spec if eq in ("barbell", "dumbbell") else None
    if has(n, "^smith machine upright row"):
        return raise_("upright barbell row", "barbell")
    if has(n, "upright"):
        if eq not in ("barbell", "dumbbell") or has(n, "one-arm|one arm|single"):
            return None
        if eq == "dumbbell":
            return {"posture": STAND, "implement": "dumbbell",
                    "arm": {"elbow_out": [1, 0.1, 0.4],
                            "keys": [key((0.12, 0.15, -1), (-0.1, 0.1, -1), (-1, 0, 0)),
                                     key((1, 0.15, 0.2), (-0.6, 0.25, -0.75), (-1, 0, 0))]},
                    "camera": {"az": 30, "el": 6}}
        return {"posture": STAND, "implement": "barbell",
                "arm": {"grip": 0.12, "palm": [0, 1, 0], "elbow_out": [1, 0.1, 0.4],
                        "keys": [key((0.12, 0.15, -1), (-0.05, 0.1, -1), (-1, 0, 0)),
                                 key((1, 0.15, 0.2), (-0.6, 0.25, -0.75), (-1, 0, 0))]}, "camera": {"az": 30, "el": 6}}
    seated = has(n, "seated side lateral|seated lateral")
    if not seated and has(n, "lying|incline|seated|\\bone\\b|single|band|machine|plate|power|kettlebell|external|internal|"
           "cuban|arm circles|rotation|y raise|lu raise|scaption"):
        return None
    if eq not in ("dumbbell", "cable"):
        return None
    impl = "dumbbell" if eq == "dumbbell" else "cable"
    if has(n, "front"):
        keys = [key((0.12, 0.15, -1), (0.12, 0.2, -1), (-1, 0, 0)), key((0.15, 1, 0.12), (0.15, 1, 0.18), (-1, 0, 0))]
        spec = {"posture": STAND, "implement": impl, "arm": {"keys": keys, "elbow_out": [1, -0.3, 0]},
                "camera": {"az": 55, "el": 6}}
        anchor = [0, -0.2, -1.4]
    elif has(n, "rear|reverse|bent"):
        keys = [key((0.15, 0.05, -1), (0.3, 0.1, -1), (0, 1, 0)), key((1, 0.05, -0.15), (1, 0.2, -0.2), (0, 1, 0))]
        spec = {"posture": {"type": "stand", "lean": 55, "width": 0.14}, "body": {"keys": [{"drop": 0.08}]},
                "implement": impl, "arm": {"frame": "world", "keys": keys, "elbow_out": [0.3, 0, 1]},
                "camera": {"az": 30, "el": 12}}
        anchor = [-0.9, 0.6, -0.5]
    else:
        keys = [key((0.2, 0.08, -1), (0.3, 0.15, -1), (0, 1, 0)), key((1, 0.1, -0.05), (1, 0.25, 0), (0, 1, -0.1))]
        spec = {"posture": {"type": "seat"} if seated else STAND, "implement": impl,
                "arm": {"keys": keys, "elbow_out": [0.2, -0.2, 1]}, "camera": {"az": 20, "el": 6}}
        anchor = [-0.35, 0.1, -1.4]
    if impl == "cable":
        spec["cable"] = {"anchor": anchor}
    if has(n, "alternat"):
        spec["alternate"] = True
    return spec


def fly(n, eq):
    if has(n, "butterfly|pec deck"):
        keys = [key((1, -0.05, -0.05), (0.05, 0.1, 1), (0, 0, 1)), key((0.35, 1, -0.05), (0.02, 0.15, 1), (0, 0, 1))]
        return {"posture": {"type": "seat", "back_deg": 85}, "implement": "handle",
                "arm": {"keys": keys, "elbow_out": [0.2, -0.3, -1]}, "camera": {"az": 30, "el": 8}}
    if has(n, "crossover") or (eq == "cable" and has(n, "fly|flye")):
        if has(n, "low|single|\\bone\\b"):
            return None
        keys = [key((1, 0.15, 0.3), (1, 0.3, 0.2), (0, 1, 0.3)), key((0.2, 1, -0.5), (-0.1, 1, -0.45), (0, 1, 0.3))]
        return {"posture": {"type": "stand", "lean": 15}, "implement": "cable",
                "cable": {"anchor": [0.9, 0, 0.7]}, "arm": {"keys": keys, "elbow_out": [0.3, -0.6, 1]},
                "camera": {"az": 30, "el": 6}}
    if has(n, "reverse|rear|back fl"):
        return raise_("rear delt raise", "dumbbell")
    if eq == "dumbbell":
        keys = [key((0.15, 1, 0.05), (0.15, 1, 0.1), (0, 0, 1)), key((1, 0.25, -0.15), (0.9, 0.45, 0), (0, 0, 1))]
        return {"posture": bench_posture(n), "implement": "dumbbell",
                "arm": {"keys": keys, "elbow_out": [0.3, -0.3, -1]}, "camera": {"az": 56, "el": 30}}
    return None


ROW_BOTTOM = key((0.08, 0.05, -1), (0.03, 0.05, -1), (-1, 0, 0))
ROW_TOP = key((0.25, -0.7, -0.45), (0.05, 0.1, -1), (-1, 0, 0))


def row(n, eq):
    if has(n, "upright"):
        return raise_(n, eq)
    if has(n, "face pull"):
        return raise_(n, eq)
    if has(n, "seated cable|cable seated|seated row"):
        keys = [key((0.08, 1, -0.2), (0, 1, -0.05), (0, 0, 1)), key((0.15, -0.7, -0.7), (0.02, 1, 0.05), (0, 0, 1))]
        return {"posture": {"type": "seat", "feet_fwd": 1.5, "lean": 8}, "implement": "cable",
                "cable": {"anchor": [0, 1.6, -0.45]}, "arm": {"keys": keys, "elbow_out": [0.4, -0.3, -1]},
                "camera": {"az": 80, "el": 8}}
    if has(n, "inverted|renegade|landmine|machine|lying|incline|chest supported|"
           "alternating|gorilla|meadows|sled|plate|leverage|elevated|face|suspended|bodyweight|shotgun|rope|"
           "kneeling|pulley|upright|iso"):
        return None
    lean = 50 if eq == "barbell" else 60
    spec = {"posture": {"type": "stand", "lean": lean, "width": 0.14}, "body": {"keys": [{"drop": 0.08}]},
            "arm": {"frame": "world", "keys": [ROW_BOTTOM, ROW_TOP], "elbow_out": [0.4, -1, 0]},
            "camera": {"az": 70, "el": 10}}
    if eq == "barbell" or has(n, "barbell|t-bar"):
        under = has(n, "reverse|underhand")
        thumb = (1, 0, 0) if under else (-1, 0, 0)
        spec["implement"] = "barbell"
        spec["arm"]["keys"] = [dict(k, thumb=list(thumb)) for k in spec["arm"]["keys"]]
        spec["arm"].update(grip=0.1 if has(n, "t-bar") else 0.24, palm=[0, 1, 0])
    elif eq in ("dumbbell", "kettlebells") or has(n, "dumbbell"):
        spec["implement"] = "kettlebell" if eq == "kettlebells" else "dumbbell"
        spec["arm"]["keys"] = [dict(k, thumb=[0, 1, 0]) for k in spec["arm"]["keys"]]
        if has(n, "one.arm|one arm|single"):
            spec["arm"].update(sides="L", rest=key((0.15, 0.35, -1), (0.05, 0.3, -1), (0, 1, 0)))
            spec["hands"] = "L"
    else:
        return None
    return spec


def vpull(n, eq):
    if has(n, "kipping|muscle|rope climb|sternum|\\bone\\b|single|weighted|band|assisted|machine|kneeling|"
           "rocky|v-bar|mixed|side to side|behind|ab crunch"):
        return None
    if has(n, "chin"):
        return {"posture": {"type": "hang", "bar_z": 2.6, "knees": 25}, "implement": "pullup_bar",
                "body": {"keys": [{"drop": 0}, {"drop": -0.5}], "head_level": 0},
                "arm": {"frame": "world", "grip": 0.2, "palm": [0, 1, 0],
                        "keys": [key((0.2, 0, 1), (0.05, 0, 1), (1, 0, 0))], "elbow_out": [0.5, -1, 0]},
                "camera": {"az": 30, "el": 5}}
    if has(n, "pull.?up"):
        grip = 0.42 if has(n, "wide") else 0.2 if has(n, "close") else 0.34
        return {"posture": {"type": "hang", "bar_z": 2.6, "knees": 25}, "implement": "pullup_bar",
                "body": {"keys": [{"drop": 0}, {"drop": -0.5}], "head_level": 0},
                "arm": {"frame": "world", "grip": grip, "palm": [0, -1, 0],
                        "keys": [key((grip - 0.04, 0, 1), (0.08, 0, 1), (-1, 0, 0))], "elbow_out": [1, -0.4, 0]},
                "camera": {"az": 160, "el": 5}}
    if has(n, "straight.arm"):
        keys = [key((0.2, 0.85, 0.5), (0.2, 0.9, 0.45), (-1, 0, 0)), key((0.15, 0.05, -1), (0.12, 0.08, -1),
                                                                          (-1, 0, 0))]
        return {"posture": {"type": "stand", "lean": 25}, "implement": "cable_bar",
                "cable": {"anchor": [0, 0.6, 0.9]},
                "arm": {"frame": "world", "grip": 0.25, "palm": [0, -1, 0], "keys": keys, "elbow_out": [1, -0.5, 0]},
                "camera": {"az": 75, "el": 6}}
    if has(n, "pulldown"):
        under = has(n, "underhand|reverse|supinat")
        grip = 0.42 if has(n, "wide") else 0.15 if has(n, "close|narrow") else 0.32
        thumb = (1, 0, 0) if under else (-1, 0, 0)
        keys = [key((0.45, 0.05, 1), (0.2, 0, 1), thumb), key((0.9, -0.15, -0.4), (0.12, 0.05, 1), thumb)]
        return {"posture": {"type": "seat"}, "implement": "cable_bar", "cable": {"anchor": [0, 0.05, 1.5]},
                "arm": {"frame": "world", "grip": grip, "palm": [0, 1, 0] if under else [0, -1, 0], "keys": keys,
                        "elbow_out": [1, -0.3, -0.2]}, "camera": {"az": 30, "el": 6}}
    return None


def triceps(n, eq):
    if has(n, "pushdown|push-down|pressdown"):
        rope = has(n, "rope")
        thumb = (0, 1, 0) if rope else (1, 0, 0) if has(n, "reverse|underhand") else (-1, 0, 0)
        keys = [key((0.05, 0.08, -1), (0.1, 0.95, 0.3), thumb), key((0.05, 0.08, -1), (0.05, 0.12, -1), thumb)]
        spec = {"posture": {"type": "stand", "lean": 8}, "cable": {"anchor": [0, 0.35, 1.0]},
                "arm": {"keys": keys, "elbow_out": [0.1, -1, -0.1]}, "camera": {"az": 60, "el": 6}}
        if rope:
            spec["implement"] = "cable_rope"
        else:
            spec["implement"] = "cable_bar"
            spec["arm"].update(grip=0.12, palm=[0, 0.3, -1])
        return spec
    if has(n, "parallel bar dip|ring dips"):
        return hpress("dips - triceps version", eq)
    if has(n, "weighted bench dip"):
        return triceps("bench dips", eq)
    if has(n, "push-ups - close triceps"):
        return hpress("close push-up", eq)
    if has(n, "bent-over .*triceps extension") and not has(n, "seated"):
        return triceps("kickback" + (" one arm" if has(n, "one-arm") else ""), "dumbbell")
    if has(n, "^standing (one-arm )?dumbbell triceps extension|^dumbbell one-arm triceps extension"):
        return triceps("overhead " + n, "dumbbell")
    if has(n, "skull|lying triceps|lying .*extension|french|press to chin|incline barbell triceps"):
        if has(n, "cable|decline|\\bone\\b|single"):
            return None
        keys = [key((0.12, 0.95, 0.3), (0.05, 1, 0.05), (-1, 0, 0)), key((0.12, 0.95, 0.3), (0.05, -0.15, 1),
                                                                        (-1, 0, 0))]
        spec = {"posture": {"type": "seat", "back_deg": 35 if has(n, "incline") else 0},
                "arm": {"keys": keys, "elbow_out": [0.1, 0.2, 1]},
                "camera": {"az": 65, "el": 20}}
        if eq == "dumbbell":
            spec["implement"] = "dumbbell"
            for k in keys:
                k["thumb"] = [0, 0, 1]
        else:
            spec["implement"] = "ezbar" if has(n, "ez") or eq == "e-z curl bar" else "barbell"
            spec["arm"].update(grip=0.15, palm=[0, -1, 0])
        return spec
    if has(n, "overhead|seated triceps press|standing triceps press"):
        if has(n, "barbell") and eq == "barbell":
            keys = [key((0.15, 0.15, 1), (0.05, 0.1, 1), (-1, 0, 0)),
                    key((0.15, 0.15, 1), (0.05, -0.35, -0.9), (-1, 0, 0))]
            return {"posture": STAND, "implement": "barbell",
                    "arm": {"keys": keys, "grip": 0.12, "palm": [0, 0.3, 1], "elbow_out": [0.3, 1, 0.2]},
                    "camera": {"az": 70, "el": 6}}
        one = has(n, "one-arm|one arm")
        if eq not in ("dumbbell", "cable") or has(n, "single|kneeling|lying|low") or (one and eq != "dumbbell"):
            return None
        keys = [key((0.15, 0.15, 1), (0.05, 0.1, 1), (0, 1, 0)), key((0.15, 0.15, 1), (0.05, -0.35, -0.9), (0, 1, 0))]
        spec = {"posture": {"type": "seat", "backrest": 85} if has(n, "seated") else STAND,
                "arm": {"keys": keys, "elbow_out": [0.3, 1, 0.2]}, "camera": {"az": 70, "el": 6}}
        if eq == "cable":
            spec.update(implement="cable_rope", cable={"anchor": [0, -0.9, -1.2]})
            spec["posture"] = {"type": "stand", "lean": 25}
        else:
            spec["implement"] = "dumbbell"
        if one:
            spec["hands"] = "L"
            spec["arm"].update(sides="L", rest=HIPS_HANDS)
        return spec
    if has(n, "kickback"):
        if eq != "dumbbell":
            return None
        keys = [key((0.1, -1, 0.2), (0.05, 0.1, -1), (0, 1, 0)), key((0.1, -1, 0.2), (0.05, -1, 0.25), (0, 1, 0))]
        spec = {"posture": {"type": "stand", "lean": 55, "width": 0.14}, "body": {"keys": [{"drop": 0.08}]},
                "implement": "dumbbell", "arm": {"frame": "world", "keys": keys, "elbow_out": [0, 0, 1]},
                "camera": {"az": 80, "el": 8}}
        if has(n, "one arm"):
            spec["hands"] = "L"
            spec["arm"].update(sides="L", rest=key((0.15, 0.35, -1), (0.05, 0.3, -1), (0, 1, 0)))
        return spec
    if has(n, "^bench dips"):
        return {"posture": {"type": "bench_dip"}, "implement": "floor",
                "body": {"keys": [{"drop": 0}, {"drop": 0.24, "back": 0.03}], "head_level": 0.3},
                "arm": {"frame": "world", "hand_z": 0.45,
                        "keys": [key((0.14, -0.25, -1), (0.05, -0.1, -1), (-1, 0, 0))], "elbow_out": [0.1, -1, 0]},
                "camera": {"az": 70, "el": 8}}
    if has(n, "close.grip.*bench|bench press"):
        return hpress("close-grip " + n, "barbell")
    if has(n, "^dips|dips -"):
        return hpress(n, eq)
    return None


def goblet(n):
    """One dumbbell held upright against the chest in both hands."""
    return {"posture": {"type": "stand", "width": 0.19, "toe_out": 18}, "implement": "dumbbell", "hands": "L",
            "body": {"keys": [{"drop": 0}, {"drop": 0.44, "back": 0.1, "lean": 22}], "head_level": 0.85},
            "arm": {"keys": [key((0.25, 0.5, -0.85), (-0.85, 0.35, 0.4), (0, 0, 1))], "elbow_out": [0.3, 0, -1]},
            "camera": {"az": 40, "el": 6}}


def squat(n, eq):
    if has(n, "^goblet squat"):
        return goblet(n)
    if has(n, "split squat with dumbbells"):
        return lunge("dumbbell lunge", "dumbbell")
    if has(n, "^smith machine squat"):
        return squat("barbell squat", "barbell")
    if has(n, "hack|machine|jump|pistol|single|\\bone\\b|split|overhead|zercher|plie|"
           "sissy|wall|kettlebell|goblet|landmine|pause|anderson|frankenstein|leg press|"
           "leverage|sled|squat clean|thruster|pin|rack|ball|lying|suspended|turkish|calf"):
        return None
    if has(n, "box|to a bench|chair"):
        deep_box = [{"size": [0.42, 0.42, 0.42], "at": [0, 0.27, 0.21]}]
    else:
        deep_box = []
    if has(n, "bodyweight|chair|^squats?$|speed squat") and not has(n, "barbell|dumbbell"):
        return {"posture": {"type": "stand", "width": 0.18, "toe_out": 16}, "implement": "none", "boxes": deep_box,
                "body": {"keys": [{"drop": 0}, {"drop": 0.42, "back": 0.12, "lean": 30}], "head_level": 0.85},
                "arm": {"keys": [key((0.15, 1, -0.05), (0.1, 1, 0.0), (0, 0, 1))], "elbow_out": [1, 0, -0.3]},
                "camera": {"az": 50, "el": 6}}
    deep = {"keys": [{"drop": 0}, {"drop": 0.42, "back": 0.14, "lean": 35}], "head_level": 0.85}
    if has(n, "front"):
        return {"posture": {"type": "stand", "width": 0.19, "toe_out": 16}, "implement": "barbell_back",
                "body": {"keys": [{"drop": 0}, {"drop": 0.44, "back": 0.08, "lean": 18}], "head_level": 0.85},
                "arm": {"frame": "torso", "grip": 0.24, "bar_on": [0, 0.1, 0.0], "palm": [0, 0, 1],
                        "elbow_out": [0, 1, -0.2]}, "camera": {"az": 50, "el": 6}}
    if eq == "barbell" or has(n, "barbell|smith"):
        return {"posture": {"type": "stand", "width": 0.2, "toe_out": 18}, "implement": "barbell_back", "body": deep,
                "boxes": deep_box,
                "arm": {"frame": "torso", "elbow_out": [0.3, -1, -1]}, "camera": {"az": 50, "el": 6}}
    if eq == "dumbbell" or has(n, "dumbbell"):
        return {"posture": {"type": "stand", "width": 0.17, "toe_out": 15}, "implement": "dumbbell", "boxes": deep_box,
                "body": {"keys": [{"drop": 0}, {"drop": 0.4, "back": 0.06, "lean": 12}], "head_level": 0.8},
                "arm": {"frame": "world", "keys": HANG_OUT}, "camera": {"az": 40, "el": 6}}
    return None


def hinge(n, eq):
    if has(n, "^butt lift"):
        return {"posture": {"type": "bridge"}, "implement": "none",
                "body": {"keys": [{"lift": 0}, {"lift": 1}], "head_level": 0.7},
                "arm": {"keys": LYING_ARMS}, "camera": {"az": 80, "el": 10}}
    if has(n, "thrust|bridge"):
        if has(n, "single|\\bone\\b|leg|band|machine|kettlebell|march|dumbbell"):
            return None
        bench = has(n, "thrust")
        if eq == "barbell" or has(n, "barbell"):
            return {"posture": {"type": "bridge", "shoulders_z": 0.42} if bench else {"type": "bridge"},
                    "implement": "barbell_back", "body": {"keys": [{"lift": 0}, {"lift": 1}], "head_level": 0.7},
                    "arm": {"frame": "torso", "bar_at": "hips", "grip": 0.45, "elbow_out": [1, 0.2, 0]},
                    "camera": {"az": 80, "el": 10}}
        return None
    if has(n, "good morning"):
        if eq not in ("barbell", "bands") or has(n, "seated|pull through|off pins"):
            return None
        return {"posture": {"type": "stand", "width": 0.16}, "implement": "barbell_back",
                "body": {"keys": [{"lean": 0}, {"lean": 70, "back": 0.12, "drop": 0.04}], "head_level": 0.6},
                "arm": {"frame": "torso", "elbow_out": [0.3, -1, -1]}, "camera": {"az": 80, "el": 6}}
    if has(n, "^rack pulls$"):
        return {"posture": {"type": "stand", "width": 0.12}, "implement": "barbell",
                "body": {"keys": [{"drop": 0.1, "back": 0.06, "lean": 32}, {}], "head_level": 0.5},
                "arm": {"frame": "world", "grip": 0.24, "palm": [0, 1, 0], "keys": HANG_BAR,
                        "elbow_out": [0.4, -1, 0]}, "camera": {"az": 70, "el": 6}}
    if not has(n, "deadlift|rdl"):
        return None
    if has(n, "single|\\bone\\b|rack|trap|hex|kettlebell|snatch|axle|car|platform|cable|leverage|"
           "reeves|clean|stiff leg barbell good"):
        return None
    if has(n, "sumo"):
        body = [{"drop": 0.38, "back": 0.05, "lean": 30}, {}]
        posture = {"type": "stand", "width": 0.33, "toe_out": 35}
        grip = 0.17
    elif has(n, "romanian|rdl|stiff"):
        body = [{}, {"lean": 75 if has(n, "stiff") else 68, "back": 0.15, "drop": 0.06}]
        posture = {"type": "stand", "width": 0.12}
        grip = 0.24
    else:
        body = [{"drop": 0.32, "back": 0.1, "lean": 48}, {}]
        posture = {"type": "stand", "width": 0.12}
        grip = 0.24
    spec = {"posture": posture, "body": {"keys": body, "head_level": 0.5}, "camera": {"az": 70, "el": 6}}
    if eq in ("barbell", "bands") or has(n, "barbell|smith"):
        spec["implement"] = "barbell"
        spec["bar_floor"] = not has(n, "romanian|rdl|stiff")
        spec["arm"] = {"frame": "world", "grip": grip, "palm": [0, 1, 0], "keys": HANG_BAR,
                       "elbow_out": [0.4, -1, 0]}
    elif eq == "dumbbell" or has(n, "dumbbell"):
        spec["implement"] = "dumbbell"
        spec["arm"] = {"frame": "world", "keys": [key((0.12, 0.03, -1), (0.04, 0.04, -1), (-1, 0, 0))],
                       "elbow_out": [0.4, -1, 0]}
    else:
        return None
    return spec


def lunge(n, eq):
    if has(n, "jump|side|lateral|curtsy|crossover|bench|bulgarian|elevated|kettlebell|"
           "overhead|rear foot|single|band|lunge pass|twist|suspended|sprint"):
        return None
    spec = {"posture": {"type": "split"}, "body": {"keys": [{"drop": 0.03}, {"drop": 0.38}]},
            "camera": {"az": 75, "el": 5}}
    if eq == "barbell" or has(n, "barbell"):
        spec.update(implement="barbell_back", arm={"frame": "torso", "elbow_out": [0.3, -1, -1]})
    elif eq == "dumbbell" or has(n, "dumbbell"):
        spec.update(implement="dumbbell", arm={"frame": "world", "keys": HANG_W})
    elif eq == "body only" or eq is None:
        spec.update(implement="none", arm={"keys": [key((0.6, 0.2, -0.75), (-0.75, 0.6, 0.1), (0, 0, 1))],
                                           "elbow_out": [1, -0.3, 0]})
    else:
        return None
    return spec


def calf(n, eq):
    if has(n, "seated"):
        return {"posture": {"type": "seat"}, "implement": "none",
                "body": {"keys": [{"heel": 0}, {"heel": 28}]},
                "arm": {"keys": [key((0.15, 0.25, -1), (0.05, 0.75, -0.65), (0, 1, 0))], "elbow_out": [1, -0.3, 0]},
                "camera": {"az": 70, "el": 6}}
    if has(n, "^smith machine calf raise"):
        return calf("barbell calf raise", "barbell")
    if has(n, "donkey|press|single|\\bone\\b|smith|rocking|toe|tibialis|ankle|leg press"):
        return None
    spec = {"posture": {"type": "stand", "width": 0.13}, "body": {"keys": [{"heel": 0}, {"heel": 32, "drop": -0.08}]},
            "camera": {"az": 70, "el": 4}}
    if eq == "barbell":
        spec.update(implement="barbell_back", arm={"frame": "torso", "elbow_out": [0.3, -1, -1]})
    elif eq == "dumbbell":
        spec.update(implement="dumbbell", arm={"frame": "world", "keys": HANG_W})
    else:
        spec.update(implement="none", arm={"frame": "world", "keys": HANG_W})
    return spec


def legcurl_ext(n, eq):
    if has(n, "^single-leg leg extension"):
        return dict(legcurl_ext("leg extensions", eq), body={"keys": [{"hip": 88, "knee_L": 95, "knee_R": 95},
                                                                     {"hip": 88, "knee_L": 5, "knee_R": 95}]})
    if has(n, "extension"):
        if has(n, "single|\\bone\\b|band"):
            return None
        return {"posture": {"type": "seat", "feet_free": True, "backrest": 75}, "implement": "handle", "pad": "front",
                "body": {"keys": [{"hip": 88, "knee": 95}, {"hip": 88, "knee": 5}]},
                "arm": {"keys": [key((0.2, -0.1, -1), (0.1, 0.6, -0.6), (0, 1, 0))]}, "camera": {"az": 80, "el": 6}}
    if has(n, "lying leg curl"):
        return {"posture": {"type": "prone"}, "implement": "handle", "pad": "back",
                "body": {"keys": [{"knee": 0}, {"knee": 110}]},
                "arm": {"frame": "world", "keys": [key((0.25, 0.35, -1), (0.1, 0.3, -1), (-1, 0, 0))]},
                "camera": {"az": 80, "el": 10}}
    if has(n, "seated leg curl"):
        return {"posture": {"type": "seat", "feet_free": True, "backrest": 75}, "implement": "handle", "pad": "back",
                "body": {"keys": [{"hip": 88, "knee": 5}, {"hip": 88, "knee": 100}]},
                "arm": {"keys": [key((0.2, -0.1, -1), (0.1, 0.6, -0.6), (0, 1, 0))]}, "camera": {"az": 80, "el": 6}}
    return None


def core(n, eq):
    if has(n, "^crunch|^crunches|floor crunch|basic crunch"):
        return {"posture": {"type": "floor_supine", "knees": 90}, "implement": "none",
                "body": {"keys": [{"curl": 0}, {"curl": 38}], "head_level": 0}, "arm": {"keys": HEAD_HANDS},
                "camera": {"az": 70, "el": 14}}
    if has(n, "^plank$"):
        return {"posture": {"type": "plank", "alpha": 10}, "implement": "floor", "bottom": 45, "hold": 30,
                "body": {"keys": [{"alpha": 0}, {"alpha": 1.2}], "head_level": 0},
                "arm": {"frame": "world", "keys": [key((0.15, 0, -1), (0.03, 1, 0.0), (-1, 0, 0))],
                        "elbow_out": [0.3, -1, 0]}, "camera": {"az": 70, "el": 12}}
    if has(n, "hanging leg raise|hanging knee raise"):
        knee = 95 if has(n, "knee") else 0
        return {"posture": {"type": "hang", "bar_z": 2.6, "knees": 25}, "implement": "pullup_bar",
                "body": {"keys": [{"hip": 0, "knee": 0}, {"hip": 95, "knee": knee}], "head_level": 0},
                "arm": {"frame": "world", "grip": 0.3, "palm": [0, -1, 0],
                        "keys": [key((0.26, 0, 1), (0.08, 0, 1), (-1, 0, 0))], "elbow_out": [1, -0.4, 0]},
                "camera": {"az": 75, "el": 5}}
    if has(n, "^cable crunch|kneeling cable crunch"):
        keys = [key((0.5, 0.75, 0.3), (-0.55, 0.3, 0.75), (0, 1, 0))]
        return {"posture": {"type": "kneel", "lean": 25}, "implement": "cable_rope",
                "cable": {"anchor": [0, 0.5, 1.1]}, "body": {"keys": [{"curl": 0}, {"curl": 50, "lean": 15}],
                                                             "head_level": 0},
                "arm": {"keys": keys, "elbow_out": [0.3, 1, -0.5]}, "camera": {"az": 75, "el": 6}}
    if has(n, "^sit-up|^3/4 sit-up|^sit up|weighted sit-ups|press sit-up"):
        return {"posture": {"type": "floor_supine", "knees": 90}, "implement": "none",
                "body": {"keys": [{"lean": 0, "curl": 0}, {"lean": 62, "curl": 20}], "head_level": 0},
                "arm": {"keys": HEAD_HANDS}, "camera": {"az": 70, "el": 12}}
    if has(n, "russian twist|seated barbell twist|plate twist"):
        keys = [key((0.15, 0.5, -0.85), (-0.65, 0.75, -0.1), (0, 0, 1))]
        return {"posture": {"type": "floor_supine", "knees": 80}, "implement": "none",
                "body": {"keys": [{"lean": 50, "twist": -35}, {"lean": 50, "twist": 35}], "head_level": 0},
                "arm": {"keys": keys, "elbow_out": [1, 0, -0.4]}, "camera": {"az": 25, "el": 12}}
    if has(n, "dumbbell side bend|barbell side bend"):
        spec = {"posture": STAND, "body": {"keys": [{"side": 10}, {"side": -22}]}, "camera": {"az": 10, "el": 6}}
        if eq == "dumbbell":
            spec.update(implement="dumbbell", hands="L", arm={"frame": "torso", "keys": HANG_T, "sides": "L",
                                                            "rest": key((0.9, -0.1, 0.4), (-0.75, 0.25, 0.6), (0, 0, 1))})
        else:
            spec.update(implement="barbell_back", arm={"frame": "torso", "elbow_out": [0.3, -1, -1]})
        return spec
    if has(n, "^reverse crunch"):
        return {"posture": {"type": "floor_supine", "feet_free": True}, "implement": "none",
                "body": {"keys": [{"hip": 60, "knee": 90}, {"hip": 115, "knee": 95, "curl": -8}], "head_level": 0},
                "arm": {"keys": [key((0.25, -0.15, -1), (0.2, -0.1, -1), (0, 1, 0))]}, "camera": {"az": 70, "el": 14}}
    if has(n, "^flutter kicks"):
        return {"posture": {"type": "floor_supine", "feet_free": True}, "implement": "none",
                "body": {"keys": [{"hip_L": 10, "hip_R": 32}, {"hip_L": 32, "hip_R": 10}], "head_level": 0},
                "arm": {"keys": [key((0.25, -0.15, -1), (0.2, -0.1, -1), (0, 1, 0))]}, "camera": {"az": 70, "el": 14}}
    if has(n, "^oblique crunches|cross-body crunch|^weighted crunches|^tuck crunch"):
        twist = 0 if has(n, "weighted|tuck") else 25
        return {"posture": {"type": "floor_supine", "knees": 90}, "implement": "none",
                "body": {"keys": [{"curl": 0}, {"curl": 34, "twist": twist}], "head_level": 0},
                "arm": {"keys": HEAD_HANDS}, "camera": {"az": 70, "el": 14}}
    if has(n, "^leg raise|lying leg raise|flat bench leg raise"):
        return {"posture": {"type": "floor_supine", "feet_free": True}, "implement": "none",
                "body": {"keys": [{"hip": 5}, {"hip": 85}], "head_level": 0},
                "arm": {"keys": [key((0.25, -0.15, -1), (0.2, -0.1, -1), (0, 1, 0))]}, "camera": {"az": 70, "el": 14}}
    return None


HIPS_HANDS = key((0.8, -0.15, -0.55), (-0.55, 0.35, -0.3), (0, 1, 0))     # torso: hands on hips
LYING_ARMS = [key((0.25, -0.15, -1), (0.2, -0.1, -1), (0, 1, 0))]        # torso: arms by the sides, lying
HOLD = {"bottom": 30, "hold": 40}                                       # stretches: ease in, hold, ease out


def floor_seat(lean_keys, **posture):
    """Sitting on the floor: the floor_supine posture sat up by a body `lean` (90 = upright)."""
    return dict({"type": "floor_supine", "knees": 0}, **posture), lean_keys


def standing_mobility(n):
    """Leg swings and wall calf stretches, built on keyed feet."""
    swings = {"front leg raises": {"fy_L": -0.62, "fz_L": 0.4, "lean": -4},
              "rear leg raises": {"fy_L": 0.55, "fz_L": 0.22, "lean": 12},
              "side leg raises": {"fx_L": 0.5, "fz_L": 0.18, "side": 8}}
    if n in swings:
        return {"posture": {"type": "stand", "width": 0.12, "feet_move": True}, "implement": "none", "cycle": True,
                "body": {"keys": [{}, swings[n], {}]}, "arm": {"keys": [HIPS_HANDS], "elbow_out": [1, -0.3, 0]},
                "camera": {"az": 20 if n.startswith("side") else 80, "el": 6}}
    if has(n, "^calf stretch (hands|elbows) against wall|^standing gastrocnemius"):
        elbows = "elbows" in n
        reach = key((0.15, 1, 0.1), (0.1, 0.2, 1), (0, 0, -1)) if elbows else key((0.15, 1, 0.25), (0.15, 1, 0.3), (0, 0, -1))
        return {"posture": {"type": "stand", "width": 0.14, "feet_move": True}, "implement": "none",
                "boxes": [{"size": [1.2, 0.08, 2.0], "at": [0, -0.75 if elbows else -0.85, 1.0]}],
                "body": {"keys": [{"fy_L": -0.15, "fy_R": 0.3, "lean": 12},
                                  {"fy_L": -0.2, "fy_R": 0.42, "lean": 22, "drop": 0.03}]},
                "arm": {"keys": [reach], "elbow_out": [1, -0.3, 0]}, "camera": {"az": 85, "el": 6}}
    return None


def stretch(n, eq):
    S = standing_mobility(n)
    if S:
        return S
    S = None
    if n == "standing toe touches":
        S = {"posture": {"type": "stand", "width": 0.12}, "implement": "none",
             "body": {"keys": [{}, {"lean": 95, "back": 0.12, "drop": 0.02, "curl": 20}], "head_level": 0.2},
             "arm": {"frame": "world", "keys": HANG_W}, "camera": {"az": 80, "el": 6}}
    elif n in ("overhead stretch", "upward stretch"):
        S = {"posture": STAND, "implement": "none", "body": {"keys": [{}, {"heel": 12, "drop": -0.03}]},
             "arm": {"keys": [key((0.25, 0.05, -1), (0.2, 0.05, -1), (0, 1, 0)),
                              key((0.12, 0.0, 1), (0.03, -0.05, 1), (-1, 0, 0))], "elbow_out": [1, 0, 0]},
             "camera": {"az": 30, "el": 6}}
    elif n == "standing lateral stretch":
        S = {"posture": {"type": "stand", "width": 0.16}, "implement": "none",
             "body": {"keys": [{}, {"side": -32}]},
             "arm": {"sides": "L", "keys": [key((0.45, 0.0, 0.9), (-0.25, 0.0, 0.95), (0, 0, 1))], "rest": HIPS_HANDS,
                     "elbow_out": [1, 0.2, 0.3]}, "camera": {"az": 5, "el": 6}}
    elif n in ("triceps stretch", "overhead triceps", "overhead lat"):
        S = {"posture": STAND, "implement": "none",
             "arm": {"sides": "L", "keys": [key((0.25, 0.1, 0.95), (-0.6, -0.3, -0.4), (0, 0, 1)),
                                           key((0.1, -0.05, 1), (-0.65, -0.35, -0.3), (0, 0, 1))],
                     "elbow_out": [1, -0.5, 0.4]},
             "camera": {"az": 140, "el": 8}}
    elif n == "shoulder stretch":
        S = {"posture": STAND, "implement": "none",
             "arm": {"sides": "L", "keys": [key((0.3, 0.6, -0.75), (0.2, 0.6, -0.75), (0, 1, 0)),
                                           key((-0.65, 0.75, -0.1), (-0.8, 0.55, 0.0), (0, 0, 1))],
                     "rest": key((0.15, 0.55, -0.8), (-0.75, 0.6, 0.25), (0, 0, 1)), "elbow_out": [0, -1, -0.3]},
             "camera": {"az": 25, "el": 6}}
    elif n == "elbows back":
        S = {"posture": STAND, "implement": "none",
             "arm": {"keys": [key((0.7, -0.45, -0.55), (-0.45, -0.3, -0.8), (0, 0, -1)),
                              key((0.45, -0.75, -0.5), (-0.5, -0.2, -0.8), (0, 0, -1))], "elbow_out": [1, -1, 0]},
             "camera": {"az": 150, "el": 8}}
    elif n == "standing biceps stretch":
        S = {"posture": STAND, "implement": "none",
             "arm": {"keys": [key((0.1, -0.35, -1), (-0.2, -0.3, -1), (1, 0, 0)),
                              key((0.1, -0.85, -0.55), (-0.15, -0.85, -0.5), (1, 0, 0))], "elbow_out": [1, 0, 0]},
             "body": {"keys": [{}, {"lean": 10}]}, "camera": {"az": 110, "el": 6}}
    elif n == "upper back stretch":
        S = {"posture": STAND, "implement": "none", "body": {"keys": [{}, {"curl": 22, "back": 0.03}]},
             "arm": {"keys": [key((0.2, 0.6, -0.8), (0.1, 0.6, -0.8), (0, 1, 0)),
                              key((0.15, 1, -0.05), (-0.25, 1, -0.05), (0, 0, -1))], "elbow_out": [1, 0, -0.5]},
             "camera": {"az": 60, "el": 6}}
    elif n in ("middle back stretch", "torso rotation"):
        arms = [HIPS_HANDS] if n.startswith("middle") else [key((0.4, 1, -0.15), (0.05, 1, 0), (0, 0, 1))]
        S = {"posture": {"type": "stand", "width": 0.16}, "implement": "none", "cycle": True,
             "body": {"keys": [{"twist": 0}, {"twist": 40}, {"twist": 0}, {"twist": -40}, {"twist": 0}]},
             "arm": {"keys": arms, "elbow_out": [1, -0.3, 0]}, "camera": {"az": 20, "el": 10}}
    elif n == "arm circles":
        ring = [key((1, 0.22 * math.cos(a), 0.22 * math.sin(a)), (1, 0.22 * math.cos(a), 0.22 * math.sin(a)),
                    (0, 0, -1)) for a in [i * math.pi / 3 for i in range(6)] + [0]]
        S = {"posture": STAND, "implement": "none", "cycle": True,
             "arm": {"keys": ring, "elbow_out": [0, -0.3, 1]}, "camera": {"az": 30, "el": 6}}
    elif n == "side neck stretch":
        S = {"posture": STAND, "implement": "none", "body": {"keys": [{}, {"tilt": -35}], "head_level": 0},
             "arm": {"keys": [key((0.12, 0.03, -1), (0.06, 0.06, -1), (0, 1, 0))]}, "camera": {"az": 10, "el": 6}}
    elif n == "chin to chest stretch":
        S = {"posture": STAND, "implement": "none", "body": {"keys": [{}, {"nod": 40}], "head_level": 0},
             "arm": {"keys": [key((0.75, 0.55, 0.35), (-0.7, 0.05, 0.7), (0, 0, 1))], "elbow_out": [0.2, 1, 0]},
             "camera": {"az": 70, "el": 6}}
    elif n == "child's pose":
        S = {"posture": {"type": "kneel"}, "implement": "none",
             "body": {"keys": [{}, {"drop": 0.3, "back": 0.12, "lean": 85}], "head_level": 0.1},
             "arm": {"keys": [key((0.15, 0.25, 1), (0.1, 0.25, 1), (0, 0, 1))], "elbow_out": [1, 0, 0]},
             "camera": {"az": 80, "el": 10}}
    elif n == "cat stretch":
        S = {"posture": {"type": "kneel", "lean": 88}, "implement": "floor",
             "body": {"keys": [{"curl": -14, "nod": -15}, {"curl": 28, "nod": 30}], "head_level": 0},
             "arm": {"frame": "world", "keys": [key((0.14, 0, -1), (0.04, 0.02, -1), (-1, 0, 0))],
                     "elbow_out": [0.3, -1, 0]}, "camera": {"az": 80, "el": 8}}
    elif n == "superman":
        S = {"posture": {"type": "prone", "top": 0.0, "no_bench": True}, "implement": "none",
             "body": {"keys": [{}, {"curl": -16, "hip": -14, "nod": -10}], "head_level": 0},
             "arm": {"keys": [key((0.25, 0.05, 1), (0.15, 0.05, 1), (0, 0, 1)),
                              key((0.25, -0.35, 1), (0.15, -0.35, 1), (0, 0, 1))], "elbow_out": [1, 0, 0]},
             "camera": {"az": 70, "el": 14}}
    elif n in ("hug knees to chest", "one knee to chest"):
        one = n.startswith("one")
        top = {"hip_L": 120, "knee_L": 125} if one else {"hip": 120, "knee": 125}
        start = {"hip_L": 70, "knee_L": 100} if one else {"hip": 70, "knee": 100}
        S = {"posture": {"type": "floor_supine", "feet_free": True}, "implement": "none",
             "body": {"keys": [dict(start, curl=0), dict(top, curl=12)], "head_level": 0},
             "arm": {"keys": [key((0.25, 0.4, -0.9), (0.0, 0.45, -0.9), (0, 0, 1)),
                              key((0.15, 0.5, -0.85), (-0.05, 0.6, -0.8), (0, 0, 1))], "elbow_out": [1, 0, 0]},
             "camera": {"az": 75, "el": 14}}
    elif n in ("hamstring stretch", "lying hamstring", "leg-up hamstring stretch"):
        S = {"posture": {"type": "floor_supine", "feet_free": True}, "implement": "none",
             "body": {"keys": [{"hip_L": 20}, {"hip_L": 85}], "head_level": 0},
             "arm": {"keys": LYING_ARMS}, "camera": {"az": 75, "el": 12}}
    elif n in ("kneeling hip flexor", "standing hip flexors"):
        kneel_deep = n.startswith("kneeling")
        S = {"posture": {"type": "split", "front": 0.55 if kneel_deep else 0.35, "back": 0.6 if kneel_deep else 0.35},
             "implement": "none",
             "body": {"keys": [{"drop": 0.42 if kneel_deep else 0.08}, {"drop": 0.5 if kneel_deep else 0.15,
                                                                       "back": -0.06, "lean": -6}]},
             "arm": {"keys": [HIPS_HANDS], "elbow_out": [1, -0.3, 0]}, "camera": {"az": 80, "el": 6}}
    elif n in ("seated hamstring", "seated floor hamstring stretch", "the straddle"):
        apart = 0.42 if n == "the straddle" else 0.12
        posture, _ = floor_seat(None, feet_apart=apart)
        S = {"posture": posture, "implement": "none",
             "body": {"keys": [{"lean": 88}, {"lean": 128, "curl": 22}], "head_level": 0.3},
             "arm": {"frame": "world", "keys": [key((0.18, 0.75, -0.65), (0.12, 0.8, -0.6), (0, 0, 1)),
                                                key((0.2, 0.95, -0.3), (0.15, 0.95, -0.3), (0, 0, 1))],
                     "elbow_out": [1, 0, 0]}, "camera": {"az": 70, "el": 10}}
    if S:
        S.update({k: v for k, v in HOLD.items() if k not in S and not S.get("cycle")})
    return S


def machine(n, eq):
    if has(n, "^(narrow stance |smith machine )?leg press$"):
        return {"posture": {"type": "leg_press", "width": 0.09 if has(n, "narrow") else 0.15}, "implement": "handle",
                "body": {"keys": [{"press": 0}, {"press": 1}], "head_level": 0},
                "arm": {"keys": [key((0.45, 0.05, -1), (0.1, 0.6, -0.8), (0, 1, 0))]}, "camera": {"az": 80, "el": 8}}
    if has(n, "^hyperextensions \\(back|^weighted ball hyperextension"):
        return {"posture": {"type": "prone", "top": 0.9, "pad_under": "thighs"}, "implement": "none", "pad": "back",
                "body": {"keys": [{"lean": 55, "hip": 55}, {"lean": 0, "hip": 0}], "head_level": 0.4},
                "arm": {"keys": [key((0.6, 0.3, -0.75), (-0.8, 0.5, 0.2), (0, 0, 1))], "elbow_out": [1, 0, 0]},
                "camera": {"az": 80, "el": 8}}
    return None


def gait(stride, lift, swing, drop, lean, treadmill):
    """One stride cycle per loop, feet keyed: each foot plants `stride` m ahead, pushes off behind and swings
    through `lift` m up; the arms swing opposite the legs."""
    def contact(lead, rear):
        return {"drop": drop, "lean": lean, "fy_" + lead: -stride, "fy_" + rear: stride, "fz_" + rear: lift * 0.25}

    def passing(stance, swing_leg):
        return {"drop": drop * 1.5, "lean": lean, "fy_" + stance: 0.0,
                "fy_" + swing_leg: -stride * lift / 0.42, "fz_" + swing_leg: lift}
    keys = [contact("L", "R"), passing("L", "R"), contact("R", "L"), passing("R", "L"), contact("L", "R")]
    fwd = key((0.1, swing * 0.6, -0.95), (0.05, 0.6, 0.8), (0, 0, 1))
    back = key((0.1, -swing, -0.85), (0.05, 0.75, -0.6), (0, 0, 1))
    spec = {"posture": {"type": "stand", "width": 0.1, "toe_out": 4, "feet_move": True}, "implement": "none",
            "cycle": True, "body": {"keys": keys, "head_level": 0.9},
            "arm": {"keys": [back, fwd, back], "offset_R": 0.5, "elbow_out": [0.3, -1, 0]}, "camera": {"az": 80, "el": 5}}
    if treadmill:
        spec["boxes"] = [{"size": [0.75, 2.0, 0.02], "at": [0, 0, 0.01]}]
    return spec


def cardio(n, eq):
    treadmill = has(n, "treadmill")
    if has(n, "^running|^trail running"):
        return gait(0.32, 0.42, 0.5, 0.06, 8, treadmill)
    if has(n, "^jogging|single leg butt kick"):
        return gait(0.24, 0.32, 0.4, 0.04, 5, treadmill)
    if has(n, "^walking"):
        return gait(0.28, 0.12, 0.3, 0.01, 2, treadmill)
    return None


def plyo(n, eq):
    arms_down = key((0.1, 0.1, -1), (0.05, 0.15, -1), (0, 1, 0))
    arms_back = key((0.15, -0.6, -0.8), (0.1, -0.5, -0.85), (0, 1, 0))
    arms_up = key((0.15, 0.85, 0.5), (0.1, 0.8, 0.6), (0, 0, 1))
    squat = {"drop": 0.36, "back": 0.1, "lean": 30}
    air = {"air": 0.28}
    arms = [arms_down, arms_back, arms_up]
    if has(n, "knee tuck jump"):
        air = {"air": 0.4, "fz_L": 0.3, "fz_R": 0.3, "fy_L": -0.15, "fy_R": -0.15}
        arms = [arms_down, arms_back, key((0.15, 0.9, -0.1), (0.1, 0.9, 0.1), (0, 0, 1))]
    elif has(n, "star jump"):
        squat = {"drop": 0.2, "back": 0.05, "lean": 15}
        air = {"air": 0.25, "fx_L": 0.3, "fx_R": -0.3}
        arms = [arms_down, arms_down, key((0.85, 0.1, 0.5), (0.8, 0.1, 0.6), (0, 1, 0))]
    elif has(n, "double leg butt kick"):
        air = {"air": 0.3, "fz_L": 0.3, "fz_R": 0.3, "fy_L": 0.2, "fy_R": 0.2}
    elif has(n, "^(split|scissors) jump"):
        def lunge(lead, rear):
            return {"drop": 0.3, "lean": 5, "fy_" + lead: -0.35, "fy_" + rear: 0.4, "fz_" + rear: 0.08}
        up = {"air": 0.22, "drop": 0.0}
        return {"posture": {"type": "stand", "width": 0.12, "feet_move": True}, "implement": "none", "cycle": True,
                "body": {"keys": [lunge("L", "R"), up, lunge("R", "L"), up, lunge("L", "R")], "head_level": 0.9},
                "arm": {"keys": [key((0.1, -0.5, -0.85), (0.05, 0.75, -0.6), (0, 0, 1)),
                                 key((0.1, 0.3, -0.95), (0.05, 0.6, 0.8), (0, 0, 1)),
                                 key((0.1, -0.5, -0.85), (0.05, 0.75, -0.6), (0, 0, 1))], "offset_R": 0.5,
                        "elbow_out": [0.3, -1, 0]}, "camera": {"az": 80, "el": 6}}
    elif has(n, "rope jumping"):
        hop = key((0.25, 0.05, -1), (0.35, 0.5, -0.4), (0, 1, 0))
        return {"posture": {"type": "stand", "width": 0.1, "feet_move": True}, "implement": "none", "cycle": True,
                "body": {"keys": [{}, {"drop": 0.05}, {"air": 0.1}, {}], "head_level": 0.9},
                "arm": {"keys": [hop]}, "camera": {"az": 40, "el": 5}}
    elif not has(n, "^(freehand|weighted) jump squat|rocket jump"):
        return None
    if has(n, "rocket"):
        arms = [arms_down, arms_down, arms_up]
    return {"posture": {"type": "stand", "width": 0.17, "toe_out": 14, "feet_move": True}, "implement": "none",
            "bottom": 36, "hold": 2, "body": {"keys": [{}, squat, air], "head_level": 0.85},
            "arm": {"keys": arms, "elbow_out": [1, -0.3, 0]}, "camera": {"az": 50, "el": 6}}


OLY_HANG = key((0.1, 0.04, -1), (0.03, 0.05, -1), (-1, 0, 0))
OLY_PULL = key((0.35, 0.2, -0.9), (0.0, 0.3, -0.95), (-1, 0, 0))
OLY_RACK = key((0.45, 0.6, -0.65), (0.1, 0.25, 1), (-1, 0.1, 0))
OLY_OVERHEAD = key((0.35, 0.05, 0.95), (0.2, 0.0, 1), (-1, 0.1, 0))


def olympic(n, eq):
    """Cleans, snatches and jerks as key sequences: pull from the floor (or the hang), extend, drop under the bar
    into the catch, then stand up (and drive it overhead for the jerk variants)."""
    if has(n, "one-arm|alternating|balance|rack delivery|kneeling|overhead squat|bottoms-up|open palm|dead clean|heaving"):
        return None
    if eq in ("kettlebells", "dumbbell"):
        return None
    implement = "barbell"
    stand = {}
    snatch = has(n, "snatch")
    jerk = has(n, "jerk|and press")
    if has(n, "^(power |squat |split )?jerk$"):
        dip = {"drop": 0.1, "lean": 2}
        catch = {"drop": 0.16, "fy_L": -0.3, "fy_R": 0.35} if has(n, "split") else {"drop": 0.14}
        return {"posture": {"type": "stand", "width": 0.14, "toe_out": 10, "feet_move": True}, "implement": implement,
                "bottom": 30, "hold": 8, "body": {"keys": [stand, dip, {"heel": 10}, catch, stand], "head_level": 0.8},
                "arm": {"frame": "world", "grip": 0.26, "palm": [0, 1, 0],
                        "keys": [OLY_RACK, OLY_RACK, OLY_RACK, OLY_OVERHEAD, OLY_OVERHEAD], "elbow_out": [1, 0, -0.4]},
                "camera": {"az": 50, "el": 6}}
    if not has(n, "clean|snatch"):
        return None
    if has(n, "below the knees|below knees|from blocks"):
        start = {"drop": 0.2, "back": 0.08, "lean": 40}
    elif has(n, "hang"):
        start = {"drop": 0.08, "back": 0.04, "lean": 25}
    else:
        start = {"drop": 0.32, "back": 0.1, "lean": 48}
    if has(n, "muscle"):
        catch = {"drop": 0.02}
    elif has(n, "split"):
        catch = {"drop": 0.3, "fy_L": -0.35, "fy_R": 0.4, "lean": 4}
    elif has(n, "power|^(kettlebell|dumbbell|two-arm|double)"):
        catch = {"drop": 0.22, "back": 0.06, "lean": 12}
    else:
        catch = {"drop": 0.44, "back": 0.08, "lean": 15}
    finish = OLY_OVERHEAD if snatch else OLY_RACK
    body = [start, {"heel": 10, "drop": -0.02, "lean": -4}, catch, stand]
    arms = [OLY_HANG, OLY_HANG, OLY_PULL, finish, finish]
    if jerk:
        body += [{"drop": 0.1, "lean": 2}, {"heel": 8}, stand]
        arms = [OLY_HANG, OLY_HANG, OLY_PULL, OLY_RACK, OLY_RACK, OLY_RACK, OLY_OVERHEAD, OLY_OVERHEAD]
    spec = {"posture": {"type": "stand", "width": 0.14, "toe_out": 10, "feet_move": has(n, "split")},
            "implement": implement, "bottom": 32, "hold": 8, "body": {"keys": body, "head_level": 0.7},
            "arm": {"frame": "world", "grip": 0.4 if snatch else 0.24, "palm": [0, 1, 0], "keys": arms,
                    "elbow_out": [0.6, -0.2, 0]}, "camera": {"az": 60, "el": 6}}
    if start["drop"] > 0.3 and implement == "barbell":
        spec["bar_floor"] = True
    return spec


def strongman(n, eq):
    """Loaded carries reuse the walking gait with the arms holding the load still."""
    walk = gait(0.24, 0.12, 0.3, 0.02, 3, False)
    walk["arm"] = {"frame": "world", "keys": [OLY_HANG], "elbow_out": [0.4, -1, 0]}
    if has(n, "^farmer"):
        return dict(walk, implement="dumbbell", camera={"az": 60, "el": 6})
    if has(n, "^yoke"):
        return dict(walk, implement="barbell_back", arm={"frame": "torso", "elbow_out": [0.3, -1, -1]},
                    camera={"az": 50, "el": 6})
    return None


FAMILY_TEMPLATES = {"strongman": strongman, "olympic": olympic, "cardio": cardio, "plyo": plyo, "machine": machine, "curl": curl, "hpress": hpress, "vpress": vpress, "raise": raise_, "fly": fly, "row": row,
                    "vpull": vpull, "triceps": triceps, "squat": squat, "hinge": hinge, "lunge": lunge,
                    "calf": calf, "legcurl_ext": legcurl_ext, "core": core,
                    "stretch": stretch}

# Same movement as an exercise a template already covers: render that one's spec under this name.
ALIASES = {
    "Barbell Curls Lying Against An Incline": "Barbell Curl",
    "One-Legged Cable Kickback": "Rear Leg Raises",
    "Hack Squat": "Smith Machine Squat",
    "Narrow Stance Hack Squats": "Smith Machine Squat",
    "Zercher Squats": "Front Barbell Squat",
    "Upright Cable Row": "Upright Row - With Bands",
    "Isometric Neck Exercise - Sides": "Side Neck Stretch",
    "Isometric Neck Exercise - Front And Back": "Chin To Chest Stretch",
    "Car Drivers": "Front Plate Raise",
    "Hip Lift with Band": "Butt Lift (Bridge)",
    "Hip Extension with Bands": "Rear Leg Raises",
    "Hip Flexion with Band": "Front Leg Raises",
    "Elliptical Trainer": "Walking, Treadmill",
    "Standing Hamstring and Calf Stretch": "Standing Toe Touches",
    "Runner's Stretch": "Kneeling Hip Flexor",
    "Pyramid": "Standing Toe Touches",
    "Groin and Back Stretch": "The Straddle",
    "Lower Back Curl": "Hug Knees To Chest",
    "Pelvic Tilt Into Bridge": "Butt Lift (Bridge)",
    "Rickshaw Carry": "Farmer's Walk",
    "Clean Deadlift": "Barbell Deadlift",
    "Snatch Deadlift": "Barbell Deadlift",
    "Clean Pull": "Barbell Deadlift",
    "Snatch Pull": "Barbell Deadlift",
    "Clean Shrug": "Barbell Shrug",
    "Snatch Shrug": "Barbell Shrug",
    "Push Press": "Standing Military Press",
    "Push Press - Behind the Neck": "Standing Military Press",
    "Power Jerk": "Standing Military Press",
    "Jerk Dip Squat": "Standing Military Press",
    "Squat Jerk": "Standing Military Press",
    "Olympic Squat": "Barbell Full Squat",
    "Frankenstein Squat": "Front Barbell Squat",
    "Wide Stance Stiff Legs": "Stiff-Legged Barbell Deadlift",
    "Two-Arm Kettlebell Jerk": "Two-Arm Kettlebell Military Press",
    "Double Kettlebell Jerk": "Two-Arm Kettlebell Military Press",
    "One-Arm Kettlebell Jerk": "Dumbbell One-Arm Shoulder Press",
    "One-Arm Kettlebell Push Press": "Dumbbell One-Arm Shoulder Press",
    "One-Arm Kettlebell Military Press To The Side": "Dumbbell One-Arm Shoulder Press",
    "Axle Deadlift": "Barbell Deadlift",
    "Rickshaw Deadlift": "Trap Bar Deadlift",
    "Car Deadlift": "Trap Bar Deadlift",
    "Log Lift": "Standing Military Press",
    "Circus Bell": "Dumbbell One-Arm Shoulder Press",
    "Crucifix": "Side Lateral Raise",
    "Donkey Calf Raises": "Standing Calf Raises",
    "Smith Machine Reverse Calf Raises": "Smith Machine Calf Raise",
    "Cable Reverse Crunch": "Reverse Crunch",
    "Jackknife Sit-Up": "Sit-Up",
    "Side Jackknife": "Oblique Crunches - On The Floor",
    "Suspended Reverse Crunch": "Reverse Crunch",
    "Seated Leg Tucks": "Tuck Crunch",
    "Physioball Hip Bridge": "Butt Lift (Bridge)",
    "One-Arm High-Pulley Cable Side Bends": "Dumbbell Side Bend",
    "Bosu Ball Cable Crunch With Side Bends": "Exercise Ball Crunch",
    "Decline Crunch": "Crunches",
    "Decline Oblique Crunch": "Oblique Crunches",
    "Decline Reverse Crunch": "Reverse Crunch",
    "Elbow to Knee": "Cross-Body Crunch",
    "Alternate Heel Touchers": "Oblique Crunches - On The Floor",
    "Leg Lift": "Flat Bench Lying Leg Raise",
    "Leg Pull-In": "Flat Bench Lying Leg Raise",
    "Flat Bench Leg Pull-In": "Flat Bench Lying Leg Raise",
    "Hanging Pike": "Hanging Leg Raise",
    "Cocoons": "Tuck Crunch",
    "Knee/Hip Raise On Parallel Bars": "Hanging Leg Raise",
    "Bent-Knee Hip Raise": "Reverse Crunch",
    "Drag Curl": "Barbell Curl",
    "Spider Curl": "Preacher Curl",
    "Lying Supine Dumbbell Curl": "Incline Dumbbell Curl",
    "Zottman Preacher Curl": "One Arm Dumbbell Preacher Curl",
    "Cable Incline Triceps Extension": "Cable Lying Triceps Extension",
    "Tate Press": "Lying Dumbbell Tricep Extension",
    "JM Press": "Close-Grip Barbell Bench Press",
    "Close-Grip EZ-Bar Press": "Close-Grip Barbell Bench Press",
    "Band Good Morning (Pull Through)": "Band Good Morning",
    "Kettlebell One-Legged Deadlift": "Stiff-Legged Dumbbell Deadlift",
    "Pull Through": "Cable Deadlifts",
    "Single Leg Glute Bridge": "Butt Lift (Bridge)",
    "Elevated Back Lunge": "Dumbbell Rear Lunge",
    "Lunge Pass Through": "Dumbbell Lunges",
    "Lunge Sprint": "Bodyweight Walking Lunge",
    "Suspended Split Squat": "Split Squats",
    "Single-Arm Push-Up": "Pushups",
    "Plyo Kettlebell Pushups": "Pushups",
    "Plyo Push-up": "Pushups",
    "Drop Push": "Pushups",
    "Incline Push-Up Depth Jump": "Incline Push-Up",
    "Weighted Pull Ups": "Pullups",
    "Side To Side Chins": "Pullups",
    "One Arm Chin-Up": "Chin-Up",
    "Barbell Rear Delt Row": "Bent Over Barbell Row",
    "Dumbbell Lying Rear Lateral Raise": "Bent Over Dumbbell Rear Delt Raise With Head On Bench",
    "Dumbbell Lying One-Arm Rear Lateral Raise": "Bent Over Dumbbell Rear Delt Raise With Head On Bench",
    "Lying Rear Delt Raise": "Bent Over Dumbbell Rear Delt Raise With Head On Bench",
    "Dumbbell One-Arm Upright Row": "Standing Dumbbell Upright Row",
    "Smith Machine One-Arm Upright Row": "Smith Machine Upright Row",
    "Cable Rope Rear-Delt Rows": "Face Pull",
    "Leverage High Row": "Seated Cable Rows",
    "Leverage Iso Row": "Seated Cable Rows",
    "Low Pulley Row To Neck": "Seated Cable Rows",
    "Lying Cambered Barbell Row": "Straight Bar Bench Mid Rows",
    "Lying T-Bar Row": "Straight Bar Bench Mid Rows",
    "Shotgun Row": "Seated One-arm Cable Pulley Rows",
    "Alternating Kettlebell Press": "Standing Alternating Dumbbell Press",
    "Kettlebell Seated Press": "Seated Dumbbell Press",
    "Kettlebell Seesaw Press": "Standing Alternating Dumbbell Press",
    "See-Saw Press (Alternating Side Press)": "Standing Alternating Dumbbell Press",
    "Standing Barbell Press Behind Neck": "Standing Military Press",
    "One-Arm Side Laterals": "Side Lateral Raise",
    "Dumbbell Scaption": "Front Two-Dumbbell Raise",
    "Band Pull Apart": "Back Flyes - With Bands",
    "Bent Over Low-Pulley Side Lateral": "Cable Rear Delt Fly",
    "Power Partials": "Side Lateral Raise",
    "Cable Iron Cross": "Cable Crossover",
    "Cross Over - With Bands": "Cable Crossover",
    "Chain Press": "Bench Press with Chains",
    "Bent-Arm Barbell Pullover": "Wide-Grip Decline Barbell Pullover",
    "Front Box Jump": "Freehand Jump Squat",
    "Box Jump (Multiple Response)": "Freehand Jump Squat",
    "Bench Jump": "Freehand Jump Squat",
    "Hurdle Hops": "Freehand Jump Squat",
    "Front Cone Hops (or hurdle hops)": "Freehand Jump Squat",
    "Standing Long Jump": "Freehand Jump Squat",
    "Linear Depth Jump": "Freehand Jump Squat",
    "Depth Jump Leap": "Freehand Jump Squat",
    "Quick Leap": "Freehand Jump Squat",
    "Single Leg Butt Kick": "Trail Running/Walking",
    "Fast Skipping": "Trail Running/Walking",
    "Wind Sprints": "Trail Running/Walking",
    "90/90 Hamstring": "Lying Hamstring", "Seated Hamstring and Calf Stretch": "Seated Hamstring",
    "Intermediate Hip Flexor and Quad Stretch": "Kneeling Hip Flexor", "Scissor Kick": "Flutter Kicks",
    "Standing Soleus And Achilles Stretch": "Standing Gastrocnemius Calf Stretch",
    "Tricep Side Stretch": "Triceps Stretch", "Chest And Front Of Shoulder Stretch": "Elbows Back",
    "Crossover Reverse Lunge": "Bodyweight Walking Lunge", "Frog Hops": "Freehand Jump Squat",
    "Sit Squats": "Bodyweight Squat", "Toe Touchers": "Standing Toe Touches",
    "Split Squats": "Bodyweight Walking Lunge",
    "Weighted Squat": "Bodyweight Squat", "Squats - With Bands": "Squat with Bands",
    "Plie Dumbbell Squat": "Goblet Squat", "Front Squats With Two Kettlebells": "Goblet Squat",
    "Barbell Hack Squat": "Barbell Deadlift", "Two-Arm Kettlebell Military Press": "Dumbbell Shoulder Press",
    "Double Kettlebell Push Press": "Standing Dumbbell Press", "Kettlebell Arnold Press": "Arnold Dumbbell Press",
    "Standing Bradford Press": "Standing Military Press", "Bradford/Rocky Presses": "Seated Barbell Military Press",
    "Alternating Kettlebell Row": "Two-Arm Kettlebell Row", "Seated One-arm Cable Pulley Rows": "Seated Cable Rows",
    "Elevated Cable Rows": "Seated Cable Rows", "Smith Machine Bent Over Row": "Bent Over Barbell Row",
    "V-Bar Pulldown": "Close-Grip Front Lat Pulldown", "Wide-Grip Pulldown Behind The Neck": "Wide-Grip Lat Pulldown",
    "Mixed Grip Chin": "Chin-Up", "V-Bar Pullup": "Chin-Up", "Gironda Sternum Chins": "Chin-Up",
    "Band Assisted Pull-Up": "Pullups", "Rocky Pull-Ups/Pulldowns": "Pullups",
    "Cable Shrugs": "Barbell Shrug", "Leverage Shrug": "Barbell Shrug",
    "Smith Machine Behind the Back Shrug": "Barbell Shrug Behind The Back",
    "Front Plate Raise": "Front Two-Dumbbell Raise", "Single Dumbbell Raise": "Front Two-Dumbbell Raise",
    "Lateral Raise - With Bands": "Side Lateral Raise", "Upright Row - With Bands": "Upright Barbell Row",
    "Seated Bent-Over Rear Delt Raise": "Bent Over Dumbbell Rear Delt Raise With Head On Bench",
    "Machine Preacher Curls": "Preacher Curl", "Cable Preacher Curl": "Preacher Curl",
    "Reverse Barbell Preacher Curls": "Preacher Curl", "Machine Bicep Curl": "Preacher Curl",
    "One Arm Dumbbell Preacher Curl": "Two-Arm Dumbbell Preacher Curl",
    "Preacher Hammer Dumbbell Curl": "Two-Arm Dumbbell Preacher Curl",
    "Zottman Curl": "Dumbbell Alternate Bicep Curl", "Reverse Plate Curls": "Reverse Barbell Curl",
    "Standing Concentration Curl": "Concentration Curls",
    "Seated Close-Grip Concentration Barbell Curl": "Concentration Curls",
    "Cable One Arm Tricep Extension": "Cable Rope Overhead Triceps Extension",
    "Standing Low-Pulley One-Arm Triceps Extension": "Cable Rope Overhead Triceps Extension",
    "Kneeling Cable Triceps Extension": "Cable Rope Overhead Triceps Extension",
    "Low Cable Triceps Extension": "Cable Rope Overhead Triceps Extension",
    "Standing Towel Triceps Extension": "Standing Dumbbell Triceps Extension",
    "Speed Band Overhead Triceps": "Standing Dumbbell Triceps Extension",
    "Decline EZ Bar Triceps Extension": "EZ-Bar Skullcrusher", "Decline Close-Grip Bench To Skull Crusher": "EZ-Bar Skullcrusher",
    "Decline Dumbbell Triceps Extension": "Lying Dumbbell Tricep Extension",
    "Dumbbell Tricep Extension -Pronated Grip": "Lying Dumbbell Tricep Extension",
    "One Arm Pronated Dumbbell Triceps Extension": "Lying Dumbbell Tricep Extension",
    "One Arm Supinated Dumbbell Triceps Extension": "Lying Dumbbell Tricep Extension",
    "Cable Lying Triceps Extension": "Lying Triceps Press",
    "Seated Bent-Over One-Arm Dumbbell Triceps Extension": "Standing Bent-Over One-Arm Dumbbell Triceps Extension",
    "Seated Bent-Over Two-Arm Dumbbell Triceps Extension": "Standing Bent-Over Two-Arm Dumbbell Triceps Extension",
    "Trap Bar Deadlift": "Barbell Deadlift", "Leverage Deadlift": "Barbell Deadlift", "Cable Deadlifts": "Barbell Deadlift",
    "Rack Pull with Bands": "Rack Pulls", "Good Morning off Pins": "Good Morning",
    "Rocking Standing Calf Raise": "Standing Calf Raises",
    "Rope Crunch": "Cable Crunch", "Exercise Ball Crunch": "Crunches", "Frog Sit-Ups": "Sit-Up",
    "Janda Sit-Up": "Sit-Up", "Weighted Ball Side Bend": "Dumbbell Side Bend",
    "Alternating Floor Press": "Dumbbell Floor Press", "One-Arm Kettlebell Floor Press": "One Arm Floor Press",
    "Extended Range One-Arm Kettlebell Floor Press": "One Arm Floor Press", "Leg-Over Floor Press": "Floor Press",
    "Barbell Guillotine Bench Press": "Wide-Grip Barbell Bench Press", "Incline Push-Up Reverse Grip": "Incline Push-Up",
    "Incline Cable Chest Press": "Incline Dumbbell Press", "Incline Cable Flye": "Incline Dumbbell Flyes",
    "Incline Dumbbell Flyes - With A Twist": "Incline Dumbbell Flyes",
    "Low Cable Crossover": "Cable Crossover",
    "Smith Machine Bench Press": "Barbell Bench Press - Medium Grip",
    "Smith Machine Close-Grip Bench Press": "Close-Grip Barbell Bench Press",
    "Smith Machine Decline Press": "Decline Barbell Bench Press",
    "Smith Machine Incline Bench Press": "Barbell Incline Bench Press - Medium Grip", "Single-Arm Cable Crossover": "Cable Crossover",
}


NAME_FAMILIES = [(r"^standing .*dumbbell press", "vpress"),
                 (r"walking lunge", "lunge"),
                 (r"leg press$|hyperextension", "machine"),
                 (r"seated dumbbell press|shoulder press|military press|overhead press", "vpress"),
                 (r"front squat|back squat|^barbell squat", "squat"),
                 (r"leg raise|knee raise|crunch|^plank", "core"),
                 (r"deadlift|good morning|hip thrust|glute bridge", "hinge")]


def generate(e):
    family = FAMILIES.get(e["name"])
    n = e["name"].lower()
    spec = None
    for fam in [f for p, f in NAME_FAMILIES if re.search(p, n)] + [family]:
        fn = FAMILY_TEMPLATES.get(fam)
        spec = fn(n, e.get("equipment")) if fn else None
        if spec:
            family = fam
            break
    if not spec:
        return None, family
    primary, secondary = muscles(e, family)
    spec = dict(spec, name=e["name"], slug=e["id"], primary=primary, secondary=secondary)
    return spec, family


def aliased(e, by_name):
    """An alias renders its source's movement; a kettlebell version swaps the dumbbells for kettlebells."""
    name = e["name"]
    while name in ALIASES:
        name = ALIASES[name]
    source = by_name.get(name)
    spec, family = generate(source) if source else (None, None)
    if not spec:
        return None, FAMILIES.get(e["name"])
    if e.get("equipment") == "kettlebells" and spec.get("implement") == "dumbbell":
        spec["implement"] = "kettlebell"
    primary, secondary = muscles(e, family)
    return dict(spec, name=e["name"], slug=e["id"], primary=primary, secondary=secondary), family


def main():
    exercises = json.load(open(DATA))
    by_name = {e["name"]: e for e in exercises}
    os.makedirs(OUT, exist_ok=True)
    made, missing = [], []
    for e in exercises:
        spec, family = aliased(e, by_name) if e["name"] in ALIASES else generate(e)
        if spec:
            with open(os.path.join(OUT, e["id"] + ".json"), "w") as f:
                json.dump(spec, f, indent=1)
            made.append(e["id"])
        else:
            missing.append((family, e["name"]))
    print(f"{len(made)} specs written, {len(missing)} without a template")
    if "--list-missing" in sys.argv:
        for fam, name in sorted(missing, key=lambda x: (str(x[0]), x[1])):
            print(f"  {fam}: {name}")


if __name__ == "__main__":
    main()
