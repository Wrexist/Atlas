#!/bin/sh
# Render stills + loop for every exercise. Usage: sh render_all.sh [exercise ...]
B="${BLENDER:-/c/Program Files/Blender Foundation/Blender 5.2/blender.exe}"
cd "$(dirname "$0")"
for e in ${@:-squat deadlift bench curl lateral_raise}; do
  start=$(date +%s)
  "$B" -b human.blend -P $e.py -- --stills --anim 2>&1 | grep -E "^(RENDERED|VIDEO|CHECK|THUMB|BOTTOM|BENCH|CAMERA|GRIP)|Error|Traceback"
  echo "TOTAL $e $(( $(date +%s) - start )) s"
done
