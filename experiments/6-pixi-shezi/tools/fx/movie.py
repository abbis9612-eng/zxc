import json, numpy as np, subprocess, sys
from PIL import Image, ImageDraw
d = 'out_h155b'; m = json.load(open(f'{d}/meta.json')); T = m['times']
F = [np.array(Image.open(f'{d}/f{i:02d}.png'), np.float32) / 255 for i in range(len(T))]
Sh = [np.array(Image.open(f'{d}/s{i:02d}.png'), np.float32) / 255 for i in range(len(T))]
W = F[0].shape[0]; cx, cy = int(W * .36), int(W * .40); half = 100
rng = np.random.default_rng(2)
# أرض: رمل وحصى بتباين خفيف
g = np.zeros((W, W, 3), np.float32) + np.array([.77, .70, .57], np.float32)
from scipy.ndimage import gaussian_filter
g *= (1 + .07 * gaussian_filter(rng.standard_normal((W, W)), 6)[..., None] + .05 * rng.standard_normal((W, W, 1)))
OUT = 640; fps = 30; dur = 32
p = subprocess.Popen(['ffmpeg', '-y', '-loglevel', 'error', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-s', f'{OUT}x{OUT}', '-r', str(fps), '-i', '-',
                      '-i', '/home/user/zxc/assets/sounds/real/range_blast.mp3', '-filter_complex', '[1:a]adelay=1000|1000,apad[a]', '-map', '0:v', '-map', '[a]',
                      '-t', str(dur), '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-crf', '20', '-c:a', 'aac', '-b:a', '128k', 'h155_preview.mp4'], stdin=subprocess.PIPE)
for k in range(fps * dur):
    t = k / fps - 1.0                      # ثانية هدوء قبل السقوط
    img = g.copy()
    if t >= 0:
        j = np.searchsorted(T, t); 
        if j == 0: a, b, w = 0, 0, 0
        elif j >= len(T): a, b, w = len(T) - 1, len(T) - 1, 0
        else: a, b = j - 1, j; w = (t - T[a]) / (T[b] - T[a])
        if t < T[0]: a = b = 0; w = 0
        f = F[a] * (1 - w) + F[b] * w; s = Sh[a] * (1 - w) + Sh[b] * w
        fade = 1 if t < T[-1] else max(0, 1 - (t - T[-1]) / 2)
        img *= 1 - (s * .55 * fade)[..., None]
        al = f[..., 3:] * fade
        img = img * (1 - al) + f[..., :3] * al
    crop = img[cy - half:cy + half + 60, cx - half:cx + half + 60]
    im = Image.fromarray((np.clip(crop, 0, 1) * 255).astype(np.uint8)).resize((OUT, OUT), Image.LANCZOS)
    dr = ImageDraw.Draw(im); dr.text((10, 10), f't = {max(0, t):5.2f} s', fill=(20, 20, 20))
    # مقياس 10 أمتار
    px10 = OUT / ((2 * half + 60) * m['size_m'] / W) * 10
    dr.line((20, OUT - 20, 20 + px10, OUT - 20), fill=(20, 20, 20), width=3); dr.text((20, OUT - 38), '10 m', fill=(20, 20, 20))
    p.stdin.write(im.tobytes())
p.stdin.close(); p.wait(); print('ok')
