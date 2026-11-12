# تصوير مركبة بـ 32 اتجاه بالزاوية المائلة: البدن والبرج منفصلان، مع ظلهما، وموضع محور البرج لكل اتجاه
import bpy, bmesh, sys, math, mathutils, json, os
argv = sys.argv[sys.argv.index('--') + 1:]
src, name, zcut, R, MATS, OPT = argv[0], argv[1], float(argv[2]), float(argv[3]), (argv[4].split(',') if argv[4] != '-' else None), argv[5].split(',')
NDIR = 32; MPP = 66 / 2560; SIZE = 12.0; RES = int(SIZE / MPP)
G = '/tmp/claude-0/-home-user-zxc/6f6fece3-c046-5882-9d45-337485949872/scratchpad'
OUT = f'{G}/iso/units/{name}'; os.makedirs(OUT, exist_ok=True)
V = mathutils.Vector
bpy.ops.wm.read_factory_settings(use_empty=True); sc = bpy.context.scene
bpy.ops.import_scene.gltf(filepath=src)
meshes = [o for o in sc.objects if o.type == 'MESH']
# حذف الأجزاء المكررة
def bbx(o):
    w = [o.matrix_world @ V(c) for c in o.bound_box]; return tuple(round(f(p[i] for p in w), 2) for i in range(3) for f in (min, max))
seen = {}
for o in sorted(meshes, key=lambda o: -len(o.data.vertices)):
    k = bbx(o)
    if k in seen: bpy.data.objects.remove(o)
    else: seen[k] = o
meshes = [o for o in sc.objects if o.type == 'MESH']
for o in sc.objects: o.select_set(o in meshes)
bpy.context.view_layer.objects.active = meshes[0]
bpy.ops.object.parent_clear(type='CLEAR_KEEP_TRANSFORM'); bpy.ops.object.transform_apply(location=True, rotation=True, scale=True); bpy.ops.object.join(); M = bpy.context.active_object
def bounds():
    co = [v.co for v in M.data.vertices]; mn = V([min(c[i] for c in co) for i in range(3)]); mx = V([max(c[i] for c in co) for i in range(3)]); return mn, mx, mx - mn, (mx + mn) / 2
mn, mx, size, ctr = bounds()
ax = 0 if size.x > size.y else 1; ox = 1 - ax
strip = [v.co for v in M.data.vertices if v.co.z > zcut and abs(v.co[ox] - ctr[ox]) < .3]
gs = 1 if max(c[ax] for c in strip) - ctr[ax] > ctr[ax] - min(c[ax] for c in strip) else -1
if 'flip' in OPT: gs = -gs
rot = {(0, 1): -math.pi / 2, (0, -1): math.pi / 2, (1, 1): 0, (1, -1): math.pi}[(ax, gs)]
M.data.transform(mathutils.Matrix.Rotation(rot, 4, 'Z'))
mn, mx, size, ctr = bounds()
M.data.transform(mathutils.Matrix.Translation(V((-ctr.x, -ctr.y, -mn.z)))); zc = zcut - mn.z
mn, mx, size, ctr = bounds()
names = [m.name if m else '' for m in M.data.materials]
bm = bmesh.new(); bm.from_mesh(M.data); bm.faces.ensure_lookup_table()
hullmat = lambda f: any(names[f.material_index].startswith(p) for p in MATS)
if MATS: pts = [v.co for f in bm.faces if not hullmat(f) for v in f.verts]
else: pts = [v.co for v in bm.verts if v.co.z > zc and abs(v.co.x) < .9 and abs(v.co.y) < 2.2]
pv = V(((0 if 'center' in OPT else sum(p.x for p in pts) / len(pts)), sum(p.y for p in pts) / len(pts), zc))
gun = lambda c: abs(c.x - pv.x) < (.5 if MATS else .3) and c.y > pv.y + .8 and c.z > zc + (.25 if MATS else -.05)
if MATS: tur = set(f.index for f in bm.faces if not hullmat(f) or all(gun(v.co) for v in f.verts))
else:
    bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:], plane_co=(0, 0, zc), plane_no=(0, 0, 1)); bm.faces.ensure_lookup_table()
    up_ = [f for f in bm.faces if f.calc_center_median().z > zc]; ups = set(f.index for f in up_); seen2 = set(); tur = set()
    for f0 in up_:
        if f0.index in seen2: continue
        st = [f0]; part = []; seen2.add(f0.index)
        while st:
            f = st.pop(); part.append(f)
            for e in f.edges:
                for g in e.link_faces:
                    if g.index in ups and g.index not in seen2: seen2.add(g.index); st.append(g)
        cs = [f.calc_center_median() for f in part]; c = sum(cs, V()) / len(cs)
        if math.hypot(c.x - pv.x, c.y - pv.y) < R or all(gun(x) for x in cs): tur.update(f.index for f in part)
def make(nm, keep):
    b2 = bm.copy(); b2.faces.ensure_lookup_table(); bmesh.ops.delete(b2, geom=[f for f in b2.faces if (f.index in tur) != keep], context='FACES')
    me = bpy.data.meshes.new(nm); b2.to_mesh(me); b2.free()
    for m in M.data.materials: me.materials.append(m)
    o = bpy.data.objects.new(nm, me); sc.collection.objects.link(o); return o
T = make('turret', True); H = make('hull', False); bpy.data.objects.remove(M)
# غطاء داخل حلقة البرج بلون البدن (حتى لا تظهر فتحة سوداء حين يدور البرج)
tp = [T.matrix_world @ v.co for v in T.data.vertices if v.co.z < zc + .3]
rr = max(.6, min(1.3, sorted(math.hypot(p.x - pv.x, p.y - pv.y) for p in tp)[int(len(tp) * .6)] if tp else 1.0))
bpy.ops.mesh.primitive_cylinder_add(radius=rr, depth=.12, location=(pv.x, pv.y, zc - .08), vertices=32); cap = bpy.context.active_object
cm = bpy.data.materials.new('cap'); cm.use_nodes = True; cm.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value = (.36, .32, .24, 1); cm.node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value = .9; cap.data.materials.append(cm); cap.parent = H
# الأرض تلتقط الظل فقط
bpy.ops.mesh.primitive_plane_add(size=40); Gd = bpy.context.active_object; Gd.is_shadow_catcher = True
sun = bpy.data.objects.new('sun', bpy.data.lights.new('sun', 'SUN')); sc.collection.objects.link(sun)
sun.data.energy = 5.5; sun.data.angle = math.radians(1.2); sun.data.color = (1, .95, .86); sun.rotation_euler = mathutils.Euler((math.radians(52), 0, math.radians(-35)), 'XYZ')
w = bpy.data.worlds.new('w'); sc.world = w; w.use_nodes = True; bg = w.node_tree.nodes['Background']; sky = w.node_tree.nodes.new('ShaderNodeTexSky'); w.node_tree.links.new(sky.outputs['Color'], bg.inputs['Color']); bg.inputs['Strength'].default_value = .35
cam = bpy.data.objects.new('cam', bpy.data.cameras.new('cam')); sc.collection.objects.link(cam); sc.camera = cam; cam.data.type = 'ORTHO'; cam.data.ortho_scale = SIZE
el, az = math.radians(40), math.radians(35); d = V((math.sin(az) * math.cos(el), -math.cos(az) * math.cos(el), math.sin(el)))
cam.location = V((0, 0, 1.2)) + d * 100; cam.rotation_euler = (-d).to_track_quat('-Z', 'Y').to_euler()
sc.render.engine = 'CYCLES'; sc.cycles.samples = 14; sc.cycles.use_denoising = True; sc.render.film_transparent = True
sc.render.resolution_x = sc.render.resolution_y = RES; sc.view_settings.view_transform = 'AgX'; sc.view_settings.look = 'AgX - Medium High Contrast'; sc.view_settings.exposure = -.35
bpy.context.view_layer.update()
right = (cam.matrix_world.to_3x3() @ V((1, 0, 0))).normalized(); upv = (cam.matrix_world.to_3x3() @ V((0, 1, 0))).normalized()
def proj(P): q = V(P) - V((0, 0, 1.2)); return (q.dot(right) / MPP + RES / 2, -q.dot(upv) / MPP + RES / 2)
meta = {'res': RES, 'mpp': MPP, 'ndir': NDIR, 'origin': proj((0, 0, 0)), 'pivot': [], 'len': size.y, 'wid': size.x}
for k in range(NDIR):
    a = k * 2 * math.pi / NDIR                      # الزاوية: 0 = المدفع نحو +Y العالمي (شمال الشارع)
    for o in (H, T): o.rotation_euler = (0, 0, a)
    bpy.context.view_layer.update()
    pw = mathutils.Matrix.Rotation(a, 4, 'Z') @ pv; meta['pivot'].append(proj(pw))
    H.hide_render, T.hide_render = False, True; cap.hide_render = False; sc.render.filepath = f'{OUT}/h{k:02d}.png'; bpy.ops.render.render(write_still=True)
    # البرج: يدور حول محوره، فنصوّره بحيث يكون محوره في مركز الصورة
    H.hide_render, T.hide_render = True, False; cap.hide_render = True
    T.location = -(mathutils.Matrix.Rotation(a, 4, 'Z') @ V((pv.x, pv.y, 0))); bpy.context.view_layer.update()
    sc.render.filepath = f'{OUT}/t{k:02d}.png'; bpy.ops.render.render(write_still=True); T.location = (0, 0, 0)
    meta.setdefault('tpivot', proj(V((0, 0, zc))))
    print('DIR', k, flush=True)
json.dump(meta, open(f'{OUT}/meta.json', 'w')); print('OK units', name)
