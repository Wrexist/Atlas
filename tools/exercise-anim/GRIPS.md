# How each grip family should look

Reference for the grip templates in `kit.py` / `gen_specs.py`. Every clip is checked
against this before a re-render (hand close-ups via `body_preview.json`).

Every full grip: four fingers round the bar, thumb wrapped round the opposite side
until it meets the index finger. A thumb hanging off the bar is a defect.

| Family | Bar in the hand | Wrist | Width / elbows | In the kit |
|---|---|---|---|---|
| Back squat, lunge, good morning | Heel of the palm, palm facing forward, fingers over the top | Straight, on the forearm's line | Just outside the shoulders; elbows down and slightly back under the bar | `BackBar.rack_grip`, `RACK_SLIDE` |
| Front squat | Fingertips under the bar, bar on the front delts | Extended (normal in a front rack) | Elbows high and forward | `BackBar` with `bar_on` |
| Bench press, overhead press, skull crusher | Low in the palm, over the forearm bones, not in the fingers | Straight, stacked over the forearm | Bench: forearms vertical at the chest. Press: hands just outside shoulders, forearms vertical | `arm.slide = PRESS_SLIDE` |
| Deadlift, row, shrug, farmer's walk | Base of the fingers, hook-like | Neutral, arms straight down | Hands just outside the legs | default slide |
| Pull-up, chin-up, lat pulldown | Base of the fingers | Neutral | Pull-up/pulldown: wider than shoulders; chin-up: shoulder width, palms toward you | `pullup_bar`, lat bar length from the grip |
| Curls (barbell, dumbbell, EZ) | Palm, thumb over the top of the bar | Straight, no curling of the wrist | Elbows pinned at the sides | `curl` |
| Dumbbell press / bench | Low in the palm | Straight | Forearms vertical | `arm.slide = PRESS_SLIDE` |

Sources: powerliftingtechnique.com (squat hand position), barbell-logic.com (bench
and press grip), Starting Strength (deadlift grip).
