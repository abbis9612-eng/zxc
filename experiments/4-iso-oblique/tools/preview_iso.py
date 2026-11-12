# تصوير نموذج بالزاوية المائلة (40°) مع مقياس: إنسان 1.8 م بجانبه، وطباعة أبعاده
import bpy, sys, math, mathutils, glob
argv = sys.argv[sys.argv.index('--') + 1:]
src, out = argv[0], argv[1]
bpy.ops.wm.read_factory_settings(use_empty=True)
if src.endswith('.glb') or src.endswith('.gltf'): bpy.ops.import_scene.gltf(filepath=src)
objs = [o for o in bpy.context.scene.objects if o.type == 'MESH']
V = mathutils.Vector
pts = [o.matrix_world @ V(c) for o in objs for c in o.bound_box]
mn = V([min(p[i] for p in pts) for i in range(3)]); mx = V([max(p[i] for p in pts) for i in range(3)]); size = mx - mn; ctr = (mn + mx) / 2
print('SIZE', [round(v, 2) for v in size], 'meshes', len(objs))
sc = bpy.context.scene
bpy.ops.mesh.primitive_cylinder_add(radius=.25, depth=1.8, location=(mx.x + .8, ctr.y, mn.z + .9)); man = bpy.context.active_object
m = bpy.data.materials.new('r'); m.diffuse_color = (1, 0, 0, 1); m.use_nodes = True; m.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value = (1, .1, .1, 1); man.data.materials.append(m)
bpy.ops.mesh.primitive_plane_add(size=max(size.x, size.y) * 3 + 10, location=(ctr.x, ctr.y, mn.z))
sun = bpy.data.objects.new('sun', bpy.data.lights.new('sun', 'SUN')); sc.collection.objects.link(sun); sun.data.energy = 4; sun.rotation_euler = mathutils.Euler((math.radians(52), 0, math.radians(-35)), 'XYZ')
w = bpy.data.worlds.new('w'); sc.world = w; w.use_nodes = True; w.node_tree.nodes['Background'].inputs[1].default_value = .6
cam = bpy.data.objects.new('cam', bpy.data.cameras.new('cam')); sc.collection.objects.link(cam); sc.camera = cam; cam.data.type = 'ORTHO'
cam.data.ortho_scale = max(size.x, size.y, size.z) * 1.6 + 3
el, az = math.radians(40), math.radians(35); d = V((math.sin(az) * math.cos(el), -math.cos(az) * math.cos(el), math.sin(el)))
cam.location = ctr + d * 300; cam.rotation_euler = (-d).to_track_quat('-Z', 'Y').to_euler(); cam.data.clip_end = 1000
sc.render.engine = 'CYCLES'; sc.cycles.samples = 12; sc.cycles.use_denoising = True; sc.render.resolution_x = sc.render.resolution_y = 420
sc.view_settings.view_transform = 'AgX'
sc.render.filepath = out; bpy.ops.render.render(write_still=True)
