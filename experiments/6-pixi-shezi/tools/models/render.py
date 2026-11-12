# تصوير النموذج من فوق: كاميرا عمودية، وشمس من أعلى اليسار (الظل لأسفل اليمين مثل اللعبة)، وخلفية شفافة
import bpy, sys, math, mathutils, json
argv = sys.argv[sys.argv.index('--') + 1:]
src, out, res = argv[0], argv[1], int(argv[2]) if len(argv) > 2 else 512
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
objs = [o for o in bpy.context.scene.objects if o.type == 'MESH']
mn = mathutils.Vector((1e9,) * 3); mx = -mn
for o in objs:
    for c in o.bound_box:
        w = o.matrix_world @ mathutils.Vector(c); mn = mathutils.Vector(map(min, mn, w)); mx = mathutils.Vector(map(max, mx, w))
size = mx - mn; ctr = (mx + mn) / 2
print('BBOX', tuple(round(v, 2) for v in size), 'meshes', len(objs))
sc = bpy.context.scene
sc.render.engine = 'CYCLES'; sc.cycles.samples = 48; sc.cycles.use_denoising = True; sc.cycles.device = 'CPU'
sc.render.film_transparent = True; sc.render.resolution_x = sc.render.resolution_y = res
sc.view_settings.view_transform = 'Standard'
L = max(size.x, size.y) * 1.15
cam = bpy.data.objects.new('cam', bpy.data.cameras.new('cam')); sc.collection.objects.link(cam); sc.camera = cam
cam.data.type = 'ORTHO'; cam.data.ortho_scale = L
cam.location = (ctr.x, ctr.y, mx.z + 20); cam.rotation_euler = (0, 0, 0)
sun = bpy.data.objects.new('sun', bpy.data.lights.new('sun', 'SUN')); sc.collection.objects.link(sun)
sun.data.energy = 4.2; sun.data.angle = math.radians(1.5)
# الشمس: ارتفاع 50 درجة، من أعلى يسار الصورة
sun.rotation_euler = mathutils.Euler((math.radians(40), 0, math.radians(-148)), 'XYZ')
w = bpy.data.worlds.new('w'); sc.world = w; w.use_nodes = True; w.node_tree.nodes['Background'].inputs[0].default_value = (.55, .6, .7, 1); w.node_tree.nodes['Background'].inputs[1].default_value = .55
# أرض تلتقط الظل فقط
bpy.ops.mesh.primitive_plane_add(size=L * 3, location=(ctr.x, ctr.y, mn.z)); g = bpy.context.active_object; g.is_shadow_catcher = True
sc.render.filepath = out; bpy.ops.render.render(write_still=True)
print('OK', out)
