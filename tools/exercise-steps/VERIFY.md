# Step-image verification: second, independent jury

A first judge approved these exercises for Atlas (iOS fitness app). You are the second judge and you did
not see the first judge's reasoning. The owner rejected an earlier sample where a squat looked as if only
one leg bent and the depth was too shallow. He wants every exercise shown only if it is 100% correct
against correct technique as online references show it, and the step texts must be clear and good.
Be adversarial: your job is to catch what the first judge missed. A wrong image is worse than none (the
fallback is a muscle map).

For each exercise in your batch (JSON with id, name, equipment, instructions):
1. Open CARDS/<id>.sv.jpg: the exact card the user will see (2-3 cropped stills, numbered, Swedish title and
   cue under each). Also open CARDS/<id>.en.jpg to check the English text.
2. Open SHEETS/<id>.jpg: 10 frames of the whole clip (the video the user can play).
3. Judge the stills and the clip against correct technique for the named exercise. Use WebSearch for a
   reliable description when unsure. Fail on: wrong movement/position/equipment/grip/stance; one side not
   doing a bilateral movement or hidden by the camera; unilateral done bilaterally; short range of motion;
   body parts passing through equipment/floor/body; hands off the bar or handle; floating equipment;
   joints bending wrongly; bad or unsafe form; stills that don't read clearly; a still that doesn't show
   what its title/cue says. The clay figure, black background, glow and muscle tints are the app style.
4. Judge the text: Swedish must be natural, correct gym Swedish (as a Swedish PT would say it), imperative,
   correct spelling and å/ä/ö; title 1-3 words; cue one concrete sentence <= 60 chars with the key form
   point; no filler; matches the still. Same for English. If the text is weak but the images are right,
   write improved text (keep the frames) rather than failing it.

Score 1-10 for the images+clip and 1-10 for the text. "pass" requires image_score >= 8 AND text_score >= 8
(after your rewrite, if you rewrote).

Output JSON list (path in your task), one object per exercise in batch order:
{"id": "...", "verdict": "pass"|"fail", "score": <image_score>, "text_score": n, "issues": "short English",
 "rewrite": null or [{"title_sv","cue_sv","title_en","cue_en"} per step, same count and order as the card]}
Validate with python3 -c "import json,sys;print(len(json.load(open(sys.argv[1]))))" <file>.
Reply with only pass/fail counts and the failed ids with one-line reasons.
