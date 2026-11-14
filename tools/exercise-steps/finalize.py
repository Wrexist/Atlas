import json,sys
src,dst=sys.argv[1],sys.argv[2]
d=json.load(open(src))
# Lead's own review: cable anchored to a block floating in mid-air, no machine.
for k in ["Seated_Cable_Rows","Triceps_Pushdown"]: d.pop(k,None)
# A static hold: one picture, not two identical ones.
p=d["Plank"]; p["steps"]=[{"time":p["steps"][0]["time"],
 "en":{"title":"Hold the plank","cue":"Elbows under shoulders, straight line, tight core."},
 "sv":{"title":"Håll plankan","cue":"Armbågarna under axlarna, rak linje, spänd bål."}}]
json.dump(d,open(dst,'w'),ensure_ascii=False,indent=1,sort_keys=True); open(dst,'a').write("\n")
print(len(d))
