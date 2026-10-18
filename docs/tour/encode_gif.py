"""Encodes rendered frames into a compact looping GIF."""
import glob, os, sys
from PIL import Image
src, out = sys.argv[1], sys.argv[2]
fs = sorted(glob.glob(os.path.join(src, 'f*.png')))
frames = [Image.open(f).convert('RGB') for f in fs]
sample = Image.new('RGB', (800, 500 * 12))
for i, idx in enumerate(list(range(0, len(frames), max(1, len(frames) // 12)))[:12]):
    sample.paste(frames[idx], (0, 500 * i))
pal = sample.quantize(colors=200, method=Image.Quantize.MEDIANCUT)
q = [f.quantize(palette=pal, dither=Image.Dither.NONE) for f in frames]
q[0].save(out, save_all=True, append_images=q[1:], duration=int(1000 / 12), loop=0, optimize=True, disposal=1)
print(len(frames), 'frames ->', out, round(os.path.getsize(out) / 1e6, 2), 'MB')
