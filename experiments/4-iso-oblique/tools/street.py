# تجربة: شارع من بلدة عراقية بزاوية مائلة (مثل Defilade): أرض، طريق، بيتان بأحواش، أشجار، دبابة أبرامز
import bpy, bmesh, math, mathutils, sys, os, random
argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
OUT = argv[0] if argv else 'street.png'
SAMPLES = int(argv[1]) if len(argv) > 1 else 64
G = '/tmp/claude-0/-home-user-zxc/6f6fece3-c046-5882-9d45-337485949872/scratchpad'
random.seed(4)
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
V = mathutils.Vector
# ---------- خامات
def mat_tex(name, img, scale=1.0, tint=(1, 1, 1), rough=.9, bump=.4):
    m = bpy.data.materials.new(name); m.use_nodes = True; nt = m.node_tree; b = nt.nodes['Principled BSDF']
    tc = nt.nodes.new('ShaderNodeTexCoord'); geo = nt.nodes.new('ShaderNodeNewGeometry'); mp = nt.nodes.new('ShaderNodeMapping'); mp.inputs['Scale'].default_value = (scale, scale, scale)
    t = nt.nodes.new('ShaderNodeTexImage'); t.image = bpy.data.images.load(img); t.projection = 'BOX'; t.projection_blend = .3
    nt.links.new(tc.outputs['Object'] if False else geo.outputs['Position'], mp.inputs['Vector']); nt.links.new(mp.outputs['Vector'], t.inputs['Vector'])
    mix = nt.nodes.new('ShaderNodeMix'); mix.data_type = 'RGBA'; mix.blend_type = 'MULTIPLY'; mix.inputs['Factor'].default_value = 1
    mix.inputs['B'].default_value = (*tint, 1)
    # تنويع لوني واسع بضجيج (يكسر التكرار)
    nz = nt.nodes.new('ShaderNodeTexNoise'); nz.inputs['Scale'].default_value = .04; nz.inputs['Detail'].default_value = 4; nt.links.new(geo.outputs['Position'], nz.inputs['Vector'])
    mv = nt.nodes.new('ShaderNodeMix'); mv.data_type = 'RGBA'; mv.blend_type = 'MULTIPLY'; mv.inputs['Factor'].default_value = .35
    nt.links.new(t.outputs['Color'], mv.inputs['A']); nt.links.new(nz.outputs['Color'], mv.inputs['B'])
    nt.links.new(mv.outputs['Result'], mix.inputs['A']); nt.links.new(mix.outputs['Result'], b.inputs['Base Color'])
    bm = nt.nodes.new('ShaderNodeBump'); bm.inputs['Strength'].default_value = bump; nt.links.new(t.outputs['Color'], bm.inputs['Height']); nt.links.new(bm.outputs['Normal'], b.inputs['Normal'])
    b.inputs['Roughness'].default_value = rough
    return m
def mat_col(name, col, rough=.85, metal=0):
    m = bpy.data.materials.new(name); m.use_nodes = True; b = m.node_tree.nodes['Principled BSDF']
    b.inputs['Base Color'].default_value = (*col, 1); b.inputs['Roughness'].default_value = rough; b.inputs['Metallic'].default_value = metal; return m
T = G + '/geo/tex/'
def mat_ground():
    # أرض: نسيج تفاصيل (4 م) × نسيج جوي واسع (20 م) × ضجيج، حتى لا يظهر التكرار
    m = bpy.data.materials.new('ground'); m.use_nodes = True; nt = m.node_tree; b = nt.nodes['Principled BSDF']; geo = nt.nodes.new('ShaderNodeNewGeometry')
    def tx(img, sc_):
        mp = nt.nodes.new('ShaderNodeMapping'); mp.inputs['Scale'].default_value = (sc_, sc_, sc_); nt.links.new(geo.outputs['Position'], mp.inputs['Vector'])
        t = nt.nodes.new('ShaderNodeTexImage'); t.image = bpy.data.images.load(img); nt.links.new(mp.outputs['Vector'], t.inputs['Vector']); return t
    a = tx(T + 'dry_ground_rocks.jpg', 1 / 4.0); c = tx(T + 'aerial_ground_rock.jpg', 1 / 20.0); e = tx(T + 'dry_ground_01.jpg', 1 / 5.0)
    nz = nt.nodes.new('ShaderNodeTexNoise'); nz.inputs['Scale'].default_value = .05; nz.inputs['Detail'].default_value = 3; nt.links.new(geo.outputs['Position'], nz.inputs['Vector'])
    m1 = nt.nodes.new('ShaderNodeMix'); m1.data_type = 'RGBA'; nt.links.new(nz.outputs['Fac'], m1.inputs['Factor']); nt.links.new(a.outputs['Color'], m1.inputs['A']); nt.links.new(e.outputs['Color'], m1.inputs['B'])
    m2 = nt.nodes.new('ShaderNodeMix'); m2.data_type = 'RGBA'; m2.blend_type = 'OVERLAY'; m2.inputs['Factor'].default_value = .6; nt.links.new(m1.outputs['Result'], m2.inputs['A']); nt.links.new(c.outputs['Color'], m2.inputs['B'])
    hs = nt.nodes.new('ShaderNodeHueSaturation'); hs.inputs['Saturation'].default_value = .55; hs.inputs['Value'].default_value = 1.05; nt.links.new(m2.outputs['Result'], hs.inputs['Color'])
    nt.links.new(hs.outputs['Color'], b.inputs['Base Color']); b.inputs['Roughness'].default_value = 1
    bm = nt.nodes.new('ShaderNodeBump'); bm.inputs['Strength'].default_value = .7; nt.links.new(a.outputs['Color'], bm.inputs['Height']); nt.links.new(bm.outputs['Normal'], b.inputs['Normal'])
    return m
M_ground = mat_ground()
M_dirt = mat_tex('dirt', T + 'dry_ground_01.jpg', 1 / 4.0, (.95, .9, .82), bump=.5)
M_asph = mat_tex('asph', T + 'aerial_asphalt_01.jpg', 1 / 12.0, (.9, .88, .85), rough=.8, bump=.3)
M_plaster = mat_tex('plaster', T + 'cracked_concrete.jpg', 1 / 3.0, (1.08, 1.0, .88), rough=.95, bump=.15)
M_plaster2 = mat_tex('plaster2', T + 'cracked_concrete.jpg', 1 / 3.0, (1.0, .9, .76), rough=.95, bump=.15)
M_roof = mat_tex('roof', T + 'cracked_concrete.jpg', 1 / 2.0, (.92, .9, .86), rough=.95, bump=.25)
M_dark = mat_col('dark', (.03, .03, .035), .6)
M_tank = mat_col('watertank', (.85, .86, .84), .4)
M_tankb = mat_col('watertank_b', (.12, .14, .16), .5)
M_metal = mat_col('metal', (.45, .43, .4), .5, .6)
M_door = mat_col('door', (.25, .32, .38), .5, .3)
M_leaf = mat_col('leaf', (.018, .032, .01), .8)
M_leaf2 = mat_col('leaf2', (.035, .05, .016), .8)
M_bark = mat_col('bark', (.18, .13, .09), .9)
M_curb = mat_col('curb', (.62, .6, .55), .9)
M_sand = mat_col('sandbag', (.52, .46, .34), .95)
def add(o, m):
    o.data.materials.append(m); return o
def box(name, size, loc, m, rot=0):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc); o = bpy.context.active_object; o.name = name
    o.scale = size; o.rotation_euler[2] = rot; bpy.ops.object.transform_apply(scale=True)
    bev = o.modifiers.new('b', 'BEVEL'); bev.width = .03; bev.segments = 2
    return add(o, m)
def cyl(name, r, h, loc, m, v=24):
    bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=h, location=loc, vertices=v); o = bpy.context.active_object; o.name = name; return add(o, m)
# ---------- الأرض والطريق
bpy.ops.mesh.primitive_plane_add(size=160, location=(0, 0, 0)); gnd = add(bpy.context.active_object, M_ground)
gnd.modifiers.new('sub', 'SUBSURF').levels = 0
bpy.ops.mesh.primitive_plane_add(size=1, location=(0, 0, .02)); road = bpy.context.active_object; road.scale = (8, 160, 1); bpy.ops.object.transform_apply(scale=True); add(road, M_asph)
for s in (-1, 1):
    box('curb', (.25, 160, .15), (s * 4.1, 0, .07), M_curb)
    bpy.ops.mesh.primitive_plane_add(size=1, location=(s * 6.2, 0, .015)); sw = bpy.context.active_object; sw.scale = (4, 160, 1); bpy.ops.object.transform_apply(scale=True); add(sw, M_dirt)
# ---------- بيت عراقي: كتلة خرسانية مسطحة، حاجز سطح، شبابيك، باب، خزانات ماء، مكيفات، حوش بسياج وبوابة
def window(x, y, z, w, h, rot):
    o = box('win', (w, .12, h), (x, y, z), M_dark, rot); return o
def house(cx, cy, w, d, floors, m, rot=0, seed=0):
    rnd = random.Random(seed); H = 3.3 * floors
    c, s = math.cos(rot), math.sin(rot)
    P = lambda x, y, z: (cx + x * c - y * s, cy + x * s + y * c, z)
    box('house', (w, d, H), P(0, 0, H / 2), m, rot)
    # حاجز السطح
    for (x, y, sw, sd) in ((0, d / 2 - .1, w, .2), (0, -d / 2 + .1, w, .2), (w / 2 - .1, 0, .2, d), (-w / 2 + .1, 0, .2, d)):
        box('parapet', (sw, sd, .9), P(x, y, H + .45), m, rot)
    box('roofslab', (w - .4, d - .4, .08), P(0, 0, H + .04), M_roof, rot)
    # بيت الدرج على السطح
    box('stair', (2.6, 3.2, 2.6), P(w / 2 - 1.8, d / 2 - 2.1, H + 1.3), m, rot)
    box('stairdoor', (.12, 1.0, 2.0), P(w / 2 - 3.15, d / 2 - 2.1, H + 1.0), M_door, rot)
    # خزانات الماء ومكيفات
    for k in range(rnd.randint(1, 3)):
        o = cyl('tank', .55, 1.3, P(-w / 2 + 1.2 + k * 1.3, d / 2 - 1.0, H + .9), M_tank if k % 2 == 0 else M_tankb); o.rotation_euler[2] = rot
        box('stand', (1.2, 1.2, .3), P(-w / 2 + 1.2 + k * 1.3, d / 2 - 1.0, H + .2), M_metal, rot)
    for k in range(rnd.randint(1, 3)):
        box('ac', (.9, .6, .6), P(-w / 2 + 1 + k * 1.4, -d / 2 + .8, H + .3), M_metal, rot)
    # شبابيك وباب على الواجهة الأمامية (-y) والجانب
    for f in range(floors):
        z = 1.6 + f * 3.3
        for x in [-w / 2 + 1.6 + i * 2.6 for i in range(int((w - 2) / 2.6))]:
            window(*P(x, -d / 2 - .02, z), 1.1, 1.3, rot)
        for y in [-d / 2 + 1.8 + i * 3 for i in range(int((d - 2) / 3))]:
            o = box('winS', (.12, 1.1, 1.3), P(-w / 2 - .02, y, z), M_dark, rot)
    box('door', (1.3, .14, 2.3), P(0, -d / 2 - .03, 1.15), M_door, rot)
    return P
def yard(cx, cy, w, d, rot, m):
    c, s = math.cos(rot), math.sin(rot); P = lambda x, y, z: (cx + x * c - y * s, cy + x * s + y * c, z)
    for (x, y, sw, sd) in ((0, d / 2, w, .25), (w / 2, 0, .25, d), (-w / 2, 0, .25, d)):
        box('yardwall', (sw, sd, 2.2), P(x, y, 1.1), m, rot)
    # الواجهة الأمامية: سياج بفتحة بوابة
    gw = 3.2
    for side in (-1, 1):
        L = (w - gw) / 2; box('yardwall', (L, .25, 2.2), P(side * (gw / 2 + L / 2), -d / 2, 1.1), m, rot)
    box('gate', (gw, .1, 2.0), P(0, -d / 2 - .05, 1.0), M_metal, rot)
    bpy.ops.mesh.primitive_plane_add(size=1, location=P(0, 0, .03)); f = bpy.context.active_object; f.scale = (w - .3, d - .3, 1); f.rotation_euler[2] = rot; bpy.ops.object.transform_apply(scale=True); add(f, M_dirt)
# بيت 1 (طابقين) غرب الطريق، وبيت 2 (طابق) شرقه
yard(-17, 6, 18, 20, 0, M_plaster); house(-17, 9, 12, 11, 2, M_plaster, 0, 1)
yard(16, -8, 16, 18, math.pi, M_plaster2); house(16, -11, 11, 10, 1, M_plaster2, math.pi, 2)
yard(18, 18, 14, 14, math.pi, M_plaster); house(18, 20, 9, 8, 1, M_plaster, math.pi, 3)
# ---------- أشجار زيتون/سدر: تاج من كرات متكتلة وجذع
def tree(x, y, s=1.0, seed=0):
    rnd = random.Random(seed)
    o = cyl('trunk', .18 * s, 2.2 * s, (x, y, 1.1 * s), M_bark, 8)
    for k in range(14):
        a = rnd.random() * 6.28; r = rnd.random() * 1.3 * s
        bpy.ops.mesh.primitive_ico_sphere_add(radius=(.7 + rnd.random() * .6) * s, subdivisions=2, location=(x + math.cos(a) * r, y + math.sin(a) * r, (2.6 + rnd.random() * 1.2) * s))
        o = bpy.context.active_object; o.scale = (1, 1, .8); d = o.modifiers.new('d', 'DISPLACE'); t = bpy.data.textures.new('n', 'CLOUDS'); t.noise_scale = .35; d.texture = t; d.strength = .6; o.modifiers.new('s', 'SUBSURF').levels = 1; bpy.ops.object.shade_smooth()
        add(o, M_leaf if k % 2 else M_leaf2)
for (x, y, s) in ((-9, -6, 1.1), (-24, 18, 1.0), (9, 4, .9), (24, -20, 1.2), (-6, 24, .8)): tree(x, y, s, int(x * 7 + y))
# أكياس رمل عند زاوية الطريق
for i in range(6): box('sand', (1.0, .5, .35), (-6.5 + (i % 3) * 1.0, -16 + (i // 3) * .05, .18 + (i // 3) * .35), M_sand, .05)
# أعمدة كهرباء وأسلاك
for y in (-30, -6, 18, 42):
    cyl('pole', .14, 8, (-4.8, y, 4), M_metal, 8); box('arm', (1.6, .12, .12), (-4.8, y, 7.6), M_metal)
# سيارة بيك أب محترقة
M_burnt = mat_col('burnt', (.04, .035, .03), .9)
box('car', (2.0, 4.6, 1.1), (5.5, 22, .7), M_burnt, .25); box('cab', (1.8, 1.9, .8), (5.42, 21.2, 1.55), M_burnt, .25)
# حفر القذائف: قرص داكن غائر وحافة تراب
M_crater = mat_col('crater', (.07, .055, .04), 1)
M_rim = mat_tex('rim', T + 'dry_ground_rocks.jpg', 1 / 2.0, (.7, .6, .48), bump=1.2)
def scorch(x, y, r, seed):
    m = bpy.data.materials.new('scorch'); m.use_nodes = True; m.blend_method = 'BLEND'; nt = m.node_tree; b = nt.nodes['Principled BSDF']
    tc = nt.nodes.new('ShaderNodeTexCoord'); nz = nt.nodes.new('ShaderNodeTexNoise'); nz.inputs['Scale'].default_value = 3; nz.inputs['Detail'].default_value = 6; nt.links.new(tc.outputs['Object'], nz.inputs['Vector'])
    gr = nt.nodes.new('ShaderNodeTexGradient'); gr.gradient_type = 'SPHERICAL'; nt.links.new(tc.outputs['Object'], gr.inputs['Vector'])
    ad = nt.nodes.new('ShaderNodeMath'); ad.operation = 'ADD'; nt.links.new(gr.outputs['Fac'], ad.inputs[0]); nt.links.new(nz.outputs['Fac'], ad.inputs[1])
    rp = nt.nodes.new('ShaderNodeValToRGB'); nt.links.new(ad.outputs[0], rp.inputs['Fac'])
    rp.color_ramp.elements[0].position = .45; rp.color_ramp.elements[0].color = (0, 0, 0, 1); rp.color_ramp.elements[1].position = .95; rp.color_ramp.elements[1].color = (1, 1, 1, 1)
    b.inputs['Base Color'].default_value = (.025, .02, .015, 1); b.inputs['Roughness'].default_value = 1
    nt.links.new(rp.outputs['Color'], b.inputs['Alpha'])
    bpy.ops.mesh.primitive_plane_add(size=2, location=(x, y, .035)); o = bpy.context.active_object; o.scale = (r, r, 1); o.rotation_euler[2] = seed; add(o, m)
    # حفرة صغيرة في الوسط وكتل تراب حولها
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r * .35, location=(x, y, -r * .22)); add(bpy.context.active_object, M_crater)
    rnd = random.Random(seed)
    for k in range(int(18 * r)):
        a = rnd.random() * 6.28; d = r * (.4 + rnd.random() * 1.1)
        bpy.ops.mesh.primitive_ico_sphere_add(radius=.06 + rnd.random() * .14, subdivisions=1, location=(x + math.cos(a) * d, y + math.sin(a) * d, .04)); add(bpy.context.active_object, M_rim)
for (x, y, r, sd) in ((-3, 14, 3.0, 1), (9, -24, 2.2, 2), (-12, -22, 3.4, 3), (2.5, 30, 1.8, 4)): scorch(x, y, r, sd)
# ---------- انفجار: كرة نار مضيئة ودخان أسود وغبار بني، حجمي (Principled Volume بضجيج)
def blast(x, y, R, seed):
    m = bpy.data.materials.new('vol'); m.use_nodes = True; nt = m.node_tree; nt.nodes.remove(nt.nodes['Principled BSDF'])
    out = nt.nodes['Material Output']; pv = nt.nodes.new('ShaderNodeVolumePrincipled'); nt.links.new(pv.outputs[0], out.inputs['Volume'])
    tc = nt.nodes.new('ShaderNodeTexCoord'); nz = nt.nodes.new('ShaderNodeTexNoise'); nz.inputs['Scale'].default_value = 2.2; nz.inputs['Detail'].default_value = 8; nz.inputs['Roughness'].default_value = .65
    nz.noise_dimensions = '4D'; nz.inputs['W'].default_value = seed; nt.links.new(tc.outputs['Object'], nz.inputs['Vector'])
    # تلاشٍ نحو الحواف
    gr = nt.nodes.new('ShaderNodeTexGradient'); gr.gradient_type = 'SPHERICAL'; nt.links.new(tc.outputs['Object'], gr.inputs['Vector'])
    mul = nt.nodes.new('ShaderNodeMath'); mul.operation = 'MULTIPLY'; nt.links.new(nz.outputs['Fac'], mul.inputs[0]); nt.links.new(gr.outputs['Fac'], mul.inputs[1])
    ramp = nt.nodes.new('ShaderNodeValToRGB'); nt.links.new(mul.outputs[0], ramp.inputs['Fac'])
    ramp.color_ramp.elements[0].position = .08; ramp.color_ramp.elements[0].color = (0, 0, 0, 1); ramp.color_ramp.elements[1].position = .32; ramp.color_ramp.elements[1].color = (1, 1, 1, 1)
    dens = nt.nodes.new('ShaderNodeMath'); dens.operation = 'MULTIPLY'; dens.inputs[1].default_value = 7; nt.links.new(ramp.outputs['Color'], dens.inputs[0]); nt.links.new(dens.outputs[0], pv.inputs['Density'])
    pv.inputs['Color'].default_value = (.11, .095, .08, 1); pv.inputs['Absorption Color'].default_value = (.05, .045, .04, 1)
    # كرة النار: إشعاع في القلب حيث الكثافة عالية والتدرج قريب من المركز
    core = nt.nodes.new('ShaderNodeValToRGB'); nt.links.new(gr.outputs['Fac'], core.inputs['Fac'])
    core.color_ramp.elements[0].position = .55; core.color_ramp.elements[0].color = (0, 0, 0, 1); core.color_ramp.elements[1].position = .85; core.color_ramp.elements[1].color = (1, 1, 1, 1)
    em = nt.nodes.new('ShaderNodeMath'); em.operation = 'MULTIPLY'; em.inputs[1].default_value = 40; nt.links.new(core.outputs['Color'], em.inputs[0])
    em2 = nt.nodes.new('ShaderNodeMath'); em2.operation = 'MULTIPLY'; nt.links.new(em.outputs[0], em2.inputs[0]); nt.links.new(ramp.outputs['Color'], em2.inputs[1])
    nt.links.new(em2.outputs[0], pv.inputs['Emission Strength']); pv.inputs['Emission Color'].default_value = (1, .45, .12, 1)
    bpy.ops.mesh.primitive_uv_sphere_add(radius=1, location=(x, y, R * .9)); o = bpy.context.active_object; o.scale = (R, R, R * 1.05); add(o, m)
    # عمود دخان أسود فوقه، وغبار بني منتشر عند القاعدة
    m2 = m.copy(); m2.node_tree.nodes['Principled Volume'].inputs['Emission Strength'].default_value = 0
    for l in m2.node_tree.links:
        if l.to_socket.name == 'Emission Strength': m2.node_tree.links.remove(l); break
    bpy.ops.mesh.primitive_uv_sphere_add(radius=1, location=(x - R * .3, y + R * .5, R * 2.3)); o = bpy.context.active_object; o.scale = (R * 1.2, R * 1.2, R * 1.4); add(o, m2)
    m3 = m2.copy(); m3.node_tree.nodes['Principled Volume'].inputs['Color'].default_value = (.42, .33, .22, 1); m3.node_tree.nodes['Principled Volume'].inputs['Absorption Color'].default_value = (.35, .27, .17, 1)
    bpy.ops.mesh.primitive_uv_sphere_add(radius=1, location=(x, y, R * .45)); o = bpy.context.active_object; o.scale = (R * 2.4, R * 2.4, R * .6); add(o, m3)
    pl = bpy.data.objects.new('fire', bpy.data.lights.new('fire', 'POINT')); sc.collection.objects.link(pl); pl.location = (x, y, R); pl.data.energy = 60000 * R; pl.data.color = (1, .55, .2)
# ---------- الدبابة
bpy.ops.import_scene.gltf(filepath=G + '/models/m1a1/m1a1.glb')
parts = [o for o in bpy.context.selected_objects]
root = [o for o in parts if o.parent is None]
for r in root: r.rotation_euler[2] += math.radians(-12); r.location = (1.2, -4, 0)
bpy.context.view_layer.update()
mn = min((o.matrix_world @ V(c)).z for o in parts if o.type == 'MESH' for c in o.bound_box)
for r in root: r.location.z -= mn
# ---------- الإضاءة: شمس عصر قوية، وسماء
sun = bpy.data.objects.new('sun', bpy.data.lights.new('sun', 'SUN')); sc.collection.objects.link(sun)
sun.data.energy = 5.5; sun.data.angle = math.radians(1.2); sun.data.color = (1, .95, .86)
sun.rotation_euler = mathutils.Euler((math.radians(52), 0, math.radians(-35)), 'XYZ')
w = bpy.data.worlds.new('w'); sc.world = w; w.use_nodes = True; bg = w.node_tree.nodes['Background']
sky = w.node_tree.nodes.new('ShaderNodeTexSky'); w.node_tree.links.new(sky.outputs['Color'], bg.inputs['Color']); bg.inputs['Strength'].default_value = .35
# ---------- الكاميرا: متعامدة مائلة 40° (مثل ألعاب الاستراتيجية الأيزومترية)
cam = bpy.data.objects.new('cam', bpy.data.cameras.new('cam')); sc.collection.objects.link(cam); sc.camera = cam
cam.data.type = 'ORTHO'; cam.data.ortho_scale = 62
el, az = math.radians(40), math.radians(35)
tgt = V((0, 2, 0)); dirv = V((math.sin(az) * math.cos(el), -math.cos(az) * math.cos(el), math.sin(el)))
cam.location = tgt + dirv * 200
cam.rotation_euler = (-dirv).to_track_quat('-Z', 'Y').to_euler()
sc.render.engine = 'CYCLES'; sc.cycles.samples = SAMPLES; sc.cycles.use_denoising = True; sc.cycles.device = 'CPU'
sc.render.resolution_x, sc.render.resolution_y = 1280, 900
sc.view_settings.view_transform = 'AgX'; sc.view_settings.look = 'AgX - Medium High Contrast'; sc.view_settings.exposure = -.35
from bpy_extras.object_utils import world_to_camera_view
for nm, pos in (('blast', (0.5, 10, 0)), ('up1m', (0.5, 10, 1))):
    v = world_to_camera_view(sc, cam, V(pos)); print('PIX', nm, v.x * sc.render.resolution_x, (1 - v.y) * sc.render.resolution_y)
print('MPP', cam.data.ortho_scale / sc.render.resolution_x)
sc.render.filepath = OUT; bpy.ops.render.render(write_still=True); print('OK', OUT)
