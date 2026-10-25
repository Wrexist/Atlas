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
HEAD_HANDS = [key((0.95, 0.05, 0.35), (-0.75, 0.25, 0.6), (0, 0, 1))]   # torso: hands behind the head
STAND = {"type": "stand"}


def has(n, *words):
    return any(re.search(w, n) for w in words)


# ---------------------------------------------------------------- templates per family
def curl(n, eq):
    thumb = (0, 1, 0) if has(n, "hammer", "cross body", "rope") else (-1, 0, 0) if has(n, "reverse") else (1, 0, 0)
    if has(n, "preacher", "concentration", "spider", "drag", "zottman", "prone", "lying", "high cable",
           "overhead", "machine", "band", "plate", "towel", "21"):
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
        if has(n, "clap|plyo|single|\\bone\\b|decline|incline|knee|handstand|dive|spider|isometric|medicine"):
            return None
        wide = 0.34 if has(n, "wide") else 0.14 if has(n, "close|diamond|triangle") else 0.22
        return {"posture": {"type": "plank", "alpha": 22}, "implement": "floor",
                "body": {"keys": [{"alpha": 0}, {"alpha": -15}], "head_level": 0},
                "arm": {"frame": "world", "keys": [key((wide, 0.02, -1), (0.05, 0.03, -1), (-1, 0, 0))],
                        "elbow_out": [0.7, -0.5, 0.2]}, "camera": {"az": 65, "el": 14}}
    if has(n, "^dips|dip -|dips -|parallel bar dip"):
        lean = 18 if has(n, "chest") else 4
        return {"posture": {"type": "support", "bar_z": 1.25, "knees": 75}, "implement": "dip_bars",
                "body": {"keys": [{"drop": 0}, {"drop": 0.3, "lean": lean}], "head_level": 0.5},
                "arm": {"frame": "world", "keys": [key((0.12, 0, -1), (0.05, 0, -1), (0, 1, 0))],
                        "elbow_out": [0.25, -1, 0]}, "camera": {"az": 60, "el": 8}}
    if has(n, "fly|flye|svend|squeeze|guillotine|neck|smith|board|pin|chain|band|bands|leverage|one arm|"
           "one-arm|single|around|hammer grip"):
        return None
    if has(n, "machine") or eq == "machine":
        return {"posture": {"type": "seat", "back_deg": 85}, "implement": "handle",
                "arm": {"keys": [BENCH_BOTTOM_DB, BENCH_TOP_DB], "elbow_out": [0.6, -1, -0.3]},
                "camera": {"az": 60, "el": 8}}
    if has(n, "cable"):
        return None
    posture = bench_posture(n)
    cam = {"az": 56, "el": 30}
    if eq == "dumbbell" or has(n, "dumbbell"):
        spec = {"posture": posture, "implement": "dumbbell",
                "arm": {"keys": [BENCH_BOTTOM_DB, BENCH_TOP_DB], "elbow_out": [0.6, -1, -0.3]}, "camera": cam}
        if has(n, "alternat"):
            spec["alternate"] = True
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
    if has(n, "handstand|push press|jerk|bradford|cuban|landmine|\\bone\\b|single|kettlebell|band|smith|leverage|"
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
    if has(n, "upright"):
        if eq != "barbell":
            return None
        return {"posture": STAND, "implement": "barbell",
                "arm": {"grip": 0.12, "palm": [0, 1, 0], "elbow_out": [1, 0.1, 0.4],
                        "keys": [key((0.12, 0.15, -1), (-0.05, 0.1, -1), (-1, 0, 0)),
                                 key((1, 0.15, 0.2), (-0.6, 0.25, -0.75), (-1, 0, 0))]}, "camera": {"az": 30, "el": 6}}
    if has(n, "lying|incline|seated|\\bone\\b|single|band|machine|plate|power|kettlebell|external|internal|"
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
        spec = {"posture": STAND, "implement": impl, "arm": {"keys": keys, "elbow_out": [0.2, -0.2, 1]},
                "camera": {"az": 20, "el": 6}}
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
    if has(n, "inverted|renegade|kettlebell|landmine|machine|lying|incline|chest supported|smith|band|"
           "alternating|gorilla|meadows|pendlay|sled|plate|leverage|elevated|face"):
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
    elif eq == "dumbbell" or has(n, "dumbbell"):
        spec["implement"] = "dumbbell"
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
    if has(n, "skull|lying triceps|lying .*extension|french"):
        if has(n, "cable|decline|incline|\\bone\\b|single"):
            return None
        keys = [key((0.12, 0.95, 0.3), (0.05, 1, 0.05), (-1, 0, 0)), key((0.12, 0.95, 0.3), (0.05, -0.15, 1),
                                                                        (-1, 0, 0))]
        spec = {"posture": {"type": "seat", "back_deg": 0}, "arm": {"keys": keys, "elbow_out": [0.1, 0.2, 1]},
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
        if eq not in ("dumbbell", "cable") or has(n, "\\bone\\b|single|kneeling|lying|low"):
            return None
        keys = [key((0.15, 0.15, 1), (0.05, 0.1, 1), (0, 1, 0)), key((0.15, 0.15, 1), (0.05, -0.35, -0.9), (0, 1, 0))]
        spec = {"posture": {"type": "seat", "backrest": 85} if has(n, "seated") else STAND,
                "arm": {"keys": keys, "elbow_out": [0.3, 1, 0.2]}, "camera": {"az": 70, "el": 6}}
        if eq == "cable":
            spec.update(implement="cable_rope", cable={"anchor": [0, -0.9, -1.2]})
            spec["posture"] = {"type": "stand", "lean": 25}
        else:
            spec["implement"] = "dumbbell"
        return spec
    if has(n, "kickback"):
        if eq != "dumbbell":
            return None
        keys = [key((0.1, -1, 0.2), (0.05, 0.1, -1), (0, 1, 0)), key((0.1, -1, 0.2), (0.05, -1, 0.25), (0, 1, 0))]
        return {"posture": {"type": "stand", "lean": 55, "width": 0.14}, "body": {"keys": [{"drop": 0.08}]},
                "implement": "dumbbell", "arm": {"frame": "world", "keys": keys, "elbow_out": [0, 0, 1]},
                "camera": {"az": 80, "el": 8}}
    if has(n, "close.grip.*bench|bench press"):
        return hpress("close-grip " + n, "barbell")
    if has(n, "^dips|dips -"):
        return hpress(n, eq)
    return None


def squat(n, eq):
    if has(n, "hack|machine|smith|jump|pistol|single|\\bone\\b|split|overhead|zercher|box|band|plie|chain|"
           "sissy|wall|bodyweight|kettlebell|goblet|landmine|bench|speed|pause|anderson|frankenstein|"
           "leverage|sled|squat clean|to bench|thruster|pin|rack|ball"):
        return None
    deep = {"keys": [{"drop": 0}, {"drop": 0.42, "back": 0.14, "lean": 35}], "head_level": 0.85}
    if has(n, "front"):
        return {"posture": {"type": "stand", "width": 0.19, "toe_out": 16}, "implement": "barbell_back",
                "body": {"keys": [{"drop": 0}, {"drop": 0.44, "back": 0.08, "lean": 18}], "head_level": 0.85},
                "arm": {"frame": "torso", "grip": 0.24, "bar_on": [0, 0.1, 0.0], "palm": [0, 0, 1],
                        "elbow_out": [0, 1, -0.2]}, "camera": {"az": 50, "el": 6}}
    if eq == "barbell" or has(n, "barbell"):
        return {"posture": {"type": "stand", "width": 0.2, "toe_out": 18}, "implement": "barbell_back", "body": deep,
                "arm": {"frame": "torso", "elbow_out": [0.3, -1, -1]}, "camera": {"az": 50, "el": 6}}
    if eq == "dumbbell" or has(n, "dumbbell"):
        return {"posture": {"type": "stand", "width": 0.17, "toe_out": 15}, "implement": "dumbbell",
                "body": {"keys": [{"drop": 0}, {"drop": 0.4, "back": 0.06, "lean": 12}], "head_level": 0.8},
                "arm": {"frame": "world", "keys": HANG_OUT}, "camera": {"az": 40, "el": 6}}
    return None


def hinge(n, eq):
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
        if eq != "barbell" or has(n, "seated|band|chain|pull through|off pins"):
            return None
        return {"posture": {"type": "stand", "width": 0.16}, "implement": "barbell_back",
                "body": {"keys": [{"lean": 0}, {"lean": 70, "back": 0.12, "drop": 0.04}], "head_level": 0.6},
                "arm": {"frame": "torso", "elbow_out": [0.3, -1, -1]}, "camera": {"az": 80, "el": 6}}
    if not has(n, "deadlift|rdl"):
        return None
    if has(n, "single|\\bone\\b|deficit|rack|trap|hex|band|chain|kettlebell|snatch|axle|car|platform|smith|"
           "reeves|sumo deadlift with|clean|stiff leg barbell good"):
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
    if eq == "barbell" or has(n, "barbell"):
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
    if has(n, "jump|side|lateral|curtsy|crossover|bench|bulgarian|elevated|kettlebell|smith|walking|"
           "overhead|rear foot|single|band|lunge pass|twist|reverse"):
        if not has(n, "walking|reverse"):
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
                "body": {"keys": [{"heel": 0}, {"heel": -28}]},
                "arm": {"keys": [key((0.2, 0.45, -0.9), (0.05, 0.7, -0.7), (0, 1, 0))], "elbow_out": [1, -0.3, 0]},
                "camera": {"az": 70, "el": 6}}
    if has(n, "donkey|press|single|\\bone\\b|smith|rocking|toe|tibialis|ankle|leg press"):
        return None
    spec = {"posture": {"type": "stand", "width": 0.13}, "body": {"keys": [{"heel": 0}, {"heel": -32, "drop": -0.08}]},
            "camera": {"az": 70, "el": 4}}
    if eq == "barbell":
        spec.update(implement="barbell_back", arm={"frame": "torso", "elbow_out": [0.3, -1, -1]})
    elif eq == "dumbbell":
        spec.update(implement="dumbbell", arm={"frame": "world", "keys": HANG_W})
    else:
        spec.update(implement="none", arm={"frame": "world", "keys": HANG_W})
    return spec


def legcurl_ext(n, eq):
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
    if has(n, "^leg raise|lying leg raise|flat bench leg raise"):
        return {"posture": {"type": "floor_supine", "feet_free": True}, "implement": "none",
                "body": {"keys": [{"hip": 5}, {"hip": 85}], "head_level": 0},
                "arm": {"keys": [key((0.25, -0.15, -1), (0.2, -0.1, -1), (0, 1, 0))]}, "camera": {"az": 70, "el": 14}}
    return None


FAMILY_TEMPLATES = {"curl": curl, "hpress": hpress, "vpress": vpress, "raise": raise_, "fly": fly, "row": row,
                    "vpull": vpull, "triceps": triceps, "squat": squat, "hinge": hinge, "lunge": lunge,
                    "calf": calf, "legcurl_ext": legcurl_ext, "core": core}


NAME_FAMILIES = [(r"seated dumbbell press|shoulder press|military press|overhead press", "vpress"),
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


def main():
    exercises = json.load(open(DATA))
    os.makedirs(OUT, exist_ok=True)
    made, missing = [], []
    for e in exercises:
        spec, family = generate(e)
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
