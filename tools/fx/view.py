import sys, json, numpy as np
from PIL import Image
d = sys.argv[1]; m = json.load(open(f'{d}/meta.json')); idx = [int(x) for x in sys.argv[2].split(',')] if len(sys.argv) > 2 else range(len(m['times']))
out = []
for i in idx:
    f = Image.open(f'{d}/f{i:02d}.png'); s = Image.open(f'{d}/s{i:02d}.png'); W = f.size[0]
    g = np.array(Image.new('RGB', (W, W), (196, 178, 146))).astype(np.float32)
    g += (np.random.default_rng(1).random((W, W, 1)) - .5) * 14
    sh = np.array(s).astype(np.float32)[..., None] / 255 * .55
    g *= 1 - sh
    fa = np.array(f).astype(np.float32); a = fa[..., 3:] / 255
    g = g * (1 - a) + fa[..., :3] * a
    im = Image.fromarray(np.clip(g, 0, 255).astype(np.uint8)).resize((256, 256), Image.LANCZOS)
    from PIL import ImageDraw; ImageDraw.Draw(im).text((4, 4), f"{m['times'][i]}s", fill=(0, 0, 0))
    out.append(im)
cols = 6; rows = (len(out) + cols - 1) // cols
S = Image.new('RGB', (256 * cols, 256 * rows), 'white')
for k, im in enumerate(out): S.paste(im, ((k % cols) * 256, (k // cols) * 256))
S.save(sys.argv[3] if len(sys.argv) > 3 else f'{d}_sheet.png'); print(S.size)
