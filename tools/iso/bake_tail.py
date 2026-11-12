# ---- خَبز طبقات المشهد: أرض بظلال كل شيء، ثم كل نموذج صورة شفافة مستقلة مع موضع قاعدته (للفرز بالعمق)
import json
OUTD = G + ('/iso/baked_big' if os.environ.get('SPRITES_ONLY') else '/iso/baked'); os.makedirs(OUTD, exist_ok=True)
RES = 2.0                                            # ضعف 1280×900
BIG = os.environ.get('BIG')
if BIG: sc.render.resolution_x = sc.render.resolution_y = 3600; cam.data.ortho_scale = 66 * 3600 / 2560
else:
    sc.render.resolution_x, sc.render.resolution_y = int(1280 * RES), int(900 * RES); cam.data.ortho_scale = 66
sc.cycles.samples = SAMPLES
bpy.context.view_layer.update()
W_, H_ = sc.render.resolution_x, sc.render.resolution_y; MPP = cam.data.ortho_scale / W_
right = (cam.matrix_world.to_3x3() @ V((1, 0, 0))).normalized(); up = (cam.matrix_world.to_3x3() @ V((0, 1, 0))).normalized()
def proj(P): d = V(P) - V(tgt); return (d.dot(right) / MPP + W_ / 2, -d.dot(up) / MPP + H_ / 2)
props = []                                           # كل الأجسام غير الأرض والطريق
ground_like = set(PRE)
groups = [(f'{nm}_{k}', [o for o in new if o.type == 'MESH']) for k, (nm, piv, new) in enumerate(PLACED)]
def vis(objs_cam):
    for o in sc.objects:
        if o.type != 'MESH': continue
        o.visible_camera = o in objs_cam
# 1) الأرض والطريق وكل الظلال
vis(ground_like); sc.render.film_transparent = False
if not os.environ.get('SPRITES_ONLY'):
    sc.render.filepath = OUTD + ('/ground_big.png' if BIG else '/ground.png'); bpy.ops.render.render(write_still=True)
    if BIG: print('OK big'); raise SystemExit
# 2) كل مجموعة صورة شفافة
sc.render.film_transparent = True
meta = {'mpp': MPP, 'W': W_, 'H': H_, 'tgt': list(tgt), 'right': list(right), 'up': list(up), 'sprites': []}
for nm, objs in groups:
    if not objs: continue
    vis(set(objs))
    pts = [o.matrix_world @ V(c) for o in objs for c in o.bound_box]
    xs = [proj(p)[0] for p in pts]; ys = [proj(p)[1] for p in pts]
    x0, x1 = max(0, int(min(xs)) - 8), min(W_, int(max(xs)) + 8); y0, y1 = max(0, int(min(ys)) - 8), min(H_, int(max(ys)) + 8)
    if x1 <= x0 or y1 <= y0: continue
    sc.render.use_border = True; sc.render.use_crop_to_border = True
    sc.render.border_min_x, sc.render.border_max_x = x0 / W_, x1 / W_; sc.render.border_min_y, sc.render.border_max_y = 1 - y1 / H_, 1 - y0 / H_
    sc.render.filepath = f'{OUTD}/{nm}.png'; bpy.ops.render.render(write_still=True)
    # مفتاح العمق: أبعد نقطة قاعدة نحو الكاميرا (أكبر y شاشة لقاعدة الجسم)
    base = [p for p in pts if p.z < min(q.z for q in pts) + .3]
    foot = max(proj(p)[1] for p in base)
    cxw = sum(p.x for p in pts) / len(pts); cyw = sum(p.y for p in pts) / len(pts)
    meta['sprites'].append({'f': nm + '.png', 'x': x0, 'y': y0, 'w': x1 - x0, 'h': y1 - y0, 'z': foot, 'wx': cxw, 'wy': cyw})
    print('SPRITE', nm, x1 - x0, y1 - y0, flush=True)
sc.render.use_border = False
json.dump(meta, open(OUTD + '/scene.json', 'w'), indent=1)
print('OK bake')
