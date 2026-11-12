# سد الفتحات السوداء في صورة البدن (مكان البرج المرفوع) بلون السطح المحيط
import sys, numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter, binary_dilation
for f in sys.argv[1:]:
    a = np.array(Image.open(f).convert('RGBA')).astype(np.float32) / 255
    lum = a[..., :3].mean(2); op = a[..., 3] > .97
    hole = op & (lum < .09)
    hole = binary_dilation(hole, iterations=2) & op
    good = op & ~hole
    rgb = a[..., :3].copy(); w = good.astype(np.float32)
    acc = rgb * w[..., None]
    for s in (2, 4, 8, 16, 32):
        num = gaussian_filter(acc, (s, s, 0)); den = gaussian_filter(w, s)[..., None]
        fill = num / np.maximum(den, 1e-4)
        m = hole & (den[..., 0] > .02)
        rgb[m] = fill[m] * .78          # أغمق قليلاً: داخل حلقة البرج ظل
        acc[m] = rgb[m]; w[m] = 1; hole &= ~m
    a[..., :3] = rgb
    Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8)).save(f)
    print('filled', f)
