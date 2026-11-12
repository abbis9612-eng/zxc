# فصل البرج عن البدن وتصوير كل جزء من فوق بنفس المقياس وشمس اللعبة
# الاستعمال: split.py -- model.glb outdir zcut res R [بادئات خامات البدن]
import bpy, bmesh, sys, math, mathutils, json
argv = sys.argv[sys.argv.index('--') + 1:]
src, outdir, zcut, res = argv[0], argv[1], float(argv[2]), int(argv[3])
R = float(argv[4]) if len(argv) > 4 else 1.3
MATS = argv[5].split(',') if len(argv) > 5 and argv[5] not in ('', '-') else None
OPT = argv[6].split(',') if len(argv) > 6 else []   # flip: اقلب اتجاه المدفع، center: البرج في منتصف العرض
V = mathutils.Vector
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']
# حذف الأجزاء المكررة المطبوگة فوق بعض (تسبب بقعاً سوداء): نفس الصندوق المحيط تقريباً
def bbx(o):
    w = [o.matrix_world @ V(c) for c in o.bound_box]
    return tuple(round(f(p[i] for p in w), 2) for i in range(3) for f in (min, max))
groups = {}
for o in meshes: groups.setdefault(bbx(o), []).append(o)
for k, g in groups.items():
    if len(g) > 1:
        g.sort(key=lambda o: -len(o.data.vertices))
        for o in g[1:]: print('DUP removed', o.name, len(o.data.vertices)); bpy.data.objects.remove(o)
meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']
for o in bpy.context.scene.objects: o.select_set(o in meshes)
bpy.context.view_layer.objects.active = meshes[0]
bpy.ops.object.parent_clear(type='CLEAR_KEEP_TRANSFORM')
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
bpy.ops.object.join(); M = bpy.context.active_object
def bounds():
    co = [v.co for v in M.data.vertices]
    mn = V([min(c[i] for c in co) for i in range(3)]); mx = V([max(c[i] for c in co) for i in range(3)])
    return mn, mx, mx - mn, (mx + mn) / 2
mn, mx, size, ctr = bounds()
# اتجاه المدفع: أبعد نقطة فوق القطع في الشريط الأوسط الضيق (السبطانة تخرج عن البدن)
ax = 0 if size.x > size.y else 1; ox = 1 - ax
strip = [v.co for v in M.data.vertices if v.co.z > zcut and abs(v.co[ox] - ctr[ox]) < .3]
gun_sign = 1 if max(c[ax] for c in strip) - ctr[ax] > ctr[ax] - min(c[ax] for c in strip) else -1
if 'flip' in OPT: gun_sign = -gun_sign
rot = {(0, 1): -math.pi / 2, (0, -1): math.pi / 2, (1, 1): 0, (1, -1): math.pi}[(ax, gun_sign)]
M.data.transform(mathutils.Matrix.Rotation(rot, 4, 'Z'))
mn, mx, size, ctr = bounds()
names = [m.name if m else '' for m in M.data.materials]
bm = bmesh.new(); bm.from_mesh(M.data); bm.faces.ensure_lookup_table()
def is_hull_mat(f): return any(names[f.material_index].startswith(p) for p in MATS)
# مركز حلقة البرج
if MATS:
    low = [v.co for f in bm.faces if not is_hull_mat(f) for v in f.verts if v.co.z < zcut]   # سلة البرج داخل البدن
    pts = low if len(low) > 50 else [v.co for f in bm.faces if not is_hull_mat(f) for v in f.verts]
else:
    pts = [v.co for v in bm.verts if v.co.z > zcut and abs(v.co.x - ctr.x) < .9 and abs(v.co.y - ctr.y) < 2.2]
pv = V((ctr.x if 'center' in OPT else sum(p.x for p in pts) / len(pts), sum(p.y for p in pts) / len(pts), zcut))
def gun(c): return abs(c.x - pv.x) < (.5 if MATS else .3) and c.y > pv.y + .8 and c.z > zcut + (.25 if MATS else -.05)
if MATS:
    tur = set(f.index for f in bm.faces if not is_hull_mat(f) or all(gun(v.co) for v in f.verts))
else:
    bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=(0, 0, zcut), plane_no=(0, 0, 1))
    bm.faces.ensure_lookup_table(); bm.verts.ensure_lookup_table()
    up = [f for f in bm.faces if f.calc_center_median().z > zcut]
    # قطع متصلة فوق القطع: القريبة من مركز البرج أو على خط المدفع = برج، والباقي (صناديق، هوائيات، سطح محرك) = بدن
    upset = set(f.index for f in up); seen = set(); tur = set()
    for f0 in up:
        if f0.index in seen: continue
        stack = [f0]; part = []; seen.add(f0.index)
        while stack:
            f = stack.pop(); part.append(f)
            for e in f.edges:
                for g in e.link_faces:
                    if g.index in upset and g.index not in seen: seen.add(g.index); stack.append(g)
        cs = [f.calc_center_median() for f in part]; c = sum(cs, V()) / len(cs)
        if math.hypot(c.x - pv.x, c.y - pv.y) < R or all(gun(x) for x in cs): tur.update(f.index for f in part)
# مركز الحلقة الحقيقي: وسط رؤوس البرج عند مستوى التقائه بالبدن
bm.faces.ensure_lookup_table()
rv = {v.index: v.co for i in tur for v in bm.faces[i].verts if zcut - .25 < v.co.z < zcut + .15}
if len(rv) > 30 and not MATS:   # الأبرامز: مركز سلة البرج أدق
    xs = [c.x for c in rv.values()]; ys = [c.y for c in rv.values()]
    # منتصف المدى أدق من المتوسط (الرؤوس غير موزعة بالتساوي)
    pv = V((ctr.x if 'center' in OPT else (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2, zcut))
def make(name, keep):
    b2 = bm.copy(); b2.faces.ensure_lookup_table()
    bmesh.ops.delete(b2, geom=[f for f in b2.faces if (f.index in tur) != keep], context='FACES')
    me = bpy.data.meshes.new(name); b2.to_mesh(me); b2.free()
    for m in M.data.materials: me.materials.append(m)
    o = bpy.data.objects.new(name, me); bpy.context.scene.collection.objects.link(o); return o
T = make('turret', True); H = make('hull', False); M.hide_render = True
sc = bpy.context.scene
sc.render.engine = 'CYCLES'; sc.cycles.samples = 64; sc.cycles.use_denoising = True
sc.render.film_transparent = True; sc.render.resolution_x = sc.render.resolution_y = res; sc.view_settings.view_transform = 'Standard'
L = max(size.x, size.y) * 1.08
cam = bpy.data.objects.new('cam', bpy.data.cameras.new('cam')); sc.collection.objects.link(cam); sc.camera = cam
cam.data.type = 'ORTHO'; cam.data.ortho_scale = L; cam.location = (ctr.x, ctr.y, mx.z + 20)
sun = bpy.data.objects.new('sun', bpy.data.lights.new('sun', 'SUN')); sc.collection.objects.link(sun)
sun.data.energy = 4.2; sun.data.angle = math.radians(1.5); sun.rotation_euler = mathutils.Euler((math.radians(40), 0, math.radians(-148)), 'XYZ')
w = bpy.data.worlds.new('w'); sc.world = w; w.use_nodes = True; w.node_tree.nodes['Background'].inputs[0].default_value = (.55, .6, .7, 1); w.node_tree.nodes['Background'].inputs[1].default_value = .55
bpy.ops.mesh.primitive_plane_add(size=L * 4, location=(ctr.x, ctr.y, mn.z)); G = bpy.context.active_object; G.is_shadow_catcher = True
def shot(name, h, t, g):
    H.hide_render, T.hide_render, G.hide_render = not h, not t, not g
    sc.render.filepath = f'{outdir}/{name}.png'; bpy.ops.render.render(write_still=True)
shot('full', 1, 1, 1); shot('hull', 1, 0, 1); shot('turret', 0, 1, 0)
mpp = L / res
json.dump({'m_per_px': mpp, 'size_m': [size.x, size.y, size.z], 'pivot_px': [(pv.x - ctr.x) / mpp + res / 2, res / 2 - (pv.y - ctr.y) / mpp], 'zcut': zcut, 'res': res}, open(f'{outdir}/sprite.json', 'w'))
print('DONE', outdir, 'size', [round(v, 2) for v in size], 'pivot', [round(pv.x - ctr.x, 2), round(pv.y - ctr.y, 2)], 'turret faces', len(tur))
