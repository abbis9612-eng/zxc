import bpy, sys, math, mathutils
argv = sys.argv[sys.argv.index('--') + 1:]
src, out = argv[0], argv[1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
objs = [o for o in bpy.context.scene.objects if o.type == 'MESH']
mn = mathutils.Vector((1e9,) * 3); mx = -mn
for o in objs:
    for c in o.bound_box:
        w = o.matrix_world @ mathutils.Vector(c); mn = mathutils.Vector(map(min, mn, w)); mx = mathutils.Vector(map(max, mx, w))
ctr = (mx + mn) / 2; size = mx - mn
long_x = size.x > size.y
sc = bpy.context.scene; sc.render.engine = 'CYCLES'; sc.cycles.samples = 8; sc.render.resolution_x = 900; sc.render.resolution_y = 450
sc.render.film_transparent = False
cam = bpy.data.objects.new('c', bpy.data.cameras.new('c')); sc.collection.objects.link(cam); sc.camera = cam
cam.data.type = 'ORTHO'; cam.data.ortho_scale = max(size.x, size.y) * 1.1
if long_x: cam.location = (ctr.x, mn.y - 30, ctr.z); cam.rotation_euler = (math.radians(90), 0, 0)
else: cam.location = (mx.x + 30, ctr.y, ctr.z); cam.rotation_euler = (math.radians(90), 0, math.radians(90))
w = bpy.data.worlds.new('w'); sc.world = w; w.use_nodes = True; w.node_tree.nodes['Background'].inputs[1].default_value = 2.5
# خطوط ارتفاع كل 10 سم من القاعدة
for i in range(0, int(size.z * 10) + 1):
    z = mn.z + i * .1
    bpy.ops.mesh.primitive_cube_add(size=1, location=(ctr.x, ctr.y, z)); c = bpy.context.active_object
    c.scale = (size.x * 1.3 if long_x else .002, .002 if long_x else size.y * 1.3, .004 if i % 5 else .012)
    m = bpy.data.materials.new('l'); m.diffuse_color = (1, 0, 0, 1) if i % 5 == 0 else (0, .4, 1, 1); c.data.materials.append(m)
    if long_x: c.location.y = mn.y - 5
    else: c.location.x = mx.x + 5
sc.render.filepath = out; bpy.ops.render.render(write_still=True)
print('ZMIN', round(mn.z, 2), 'ZMAX', round(mx.z, 2))
