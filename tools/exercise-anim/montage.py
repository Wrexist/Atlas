# python montage.py out.png img1 img2 ... (2 rows)
import sys
from PIL import Image
ims = [Image.open(p).convert("RGB") for p in sys.argv[2:]]
w, h = ims[0].size
cols = (len(ims) + 1) // 2
sheet = Image.new("RGB", (w * cols, h * 2))
for i, im in enumerate(ims):
    sheet.paste(im.resize((w, h)), ((i % cols) * w, (i // cols) * h))
sheet.save(sys.argv[1])
