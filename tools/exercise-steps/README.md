# Exercise step pictures

`Peptide/Resources/exercise-steps.json` lists the exercises whose rendered clip passed a technique
review, with the moments (seconds into the 3 s clip) the app cuts as step pictures, a 4:5 crop, and
a title and cue per step in English and Swedish. An exercise not listed shows only the muscle map:
the list also gates its video.

How the list was made (2026-11-14):
1. `sheets.py WORK` extracts 10 frames (every 0.3 s) of each clip in `WORK/clips` (the
   `exercise-videos` branch) into `WORK/frames` and a contact sheet into `WORK/sheets`.
2. Round 1: judges following `JURY.md` checked every sheet against correct technique, picked frames
   and wrote cues (`WORK/results/*.json`).
3. Round 2: independent judges following `VERIFY.md` re-checked each pass on the rendered cards
   (`build.py WORK out.json --cards`) and the clip, and rewrote weak text (`WORK/verify/*.json`).
4. `build.py WORK out.json --final` keeps only exercises both rounds scored >= 8 (images and text);
   `finalize.py` applies the last manual review and writes the bundled file.

`review.json` records every exercise's verdicts and reasons: 40 of 615 shipped. The rest need a
re-render (wrong or missing equipment, reused generic clips, one-sided camera views, short range).
