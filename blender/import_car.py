"""Put a downloaded car body (Sketchfab, CC BY - see docs/CREDITS.md) on our chassis.

The downloaded model gives the shell, glass, lamps and interior; our own script adds the
suspension, wheels, brakes and the named parts the game needs (doors, bonnet, boot, bumpers,
lamps, mirrors, glass, steering wheel, race numbers). The body is scaled so its wheel
centres sit on our hardpoints (wheelbase 2.75 m, track 1.66 m, wheel centre 0.34 m).

Run: CAR_VARIANT=midship CAR_SRC=path/saba.glb blender -b --python blender/import_car.py
"""
import sys, os, math
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import bpy, bmesh
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree
from lib import clear, empty, reparent, M, setup_paint_livery, assign_livery_uvs, text_mesh, link
import chassis
from body import WHEEL_R, AXLE_F, AXLE_R, TRACK_X
from variants import S, NAME

ROOT = os.path.dirname(HERE)
SRC = os.environ["CAR_SRC"]
GLB = os.environ.get("CAR_OUT", S["glb"])
OUT_GLB = os.path.join(ROOT, "godot", "assets", GLB)
OUT_BLEND = os.path.join(ROOT, "exports", GLB.replace(".glb", ".blend"))
CFG = S.get("import", {})

clear()
setup_paint_livery()
root = empty("Car", size=0.3)
susp = empty("Suspension", parent=root)
for t in ("FL", "FR", "RL", "RR"):
    chassis.build_corner(root, susp, t[1], t[0] == "F")
ours = set(bpy.data.objects)

# ------------------------------------------------------------------ import and fit
bpy.ops.import_scene.gltf(filepath=SRC)
new = [o for o in bpy.data.objects if o not in ours]
for o in new:
    if o.type == "MESH":
        mw = o.matrix_world.copy()
        o.parent = None
        o.matrix_world = mw
for o in list(new):
    if o.type != "MESH":
        bpy.data.objects.remove(o, do_unlink=True)
new = [o for o in bpy.data.objects if o not in ours]
bpy.context.view_layer.update()


def bounds(objs):
    pts = [o.matrix_world @ Vector(c) for o in objs for c in o.bound_box]
    return (Vector([min(p[i] for p in pts) for i in range(3)]), Vector([max(p[i] for p in pts) for i in range(3)]))


wheels = {}
for o in new:
    for tag in ("FL", "FR", "RL", "RR", "BL", "BR"):
        if o.name.startswith("Wheel_" + tag):
            mn, mx = bounds([o])
            wheels[tag.replace("B", "R")] = (mn + mx) / 2
front = (wheels["FL"] + wheels["FR"]) / 2
rear = (wheels["RL"] + wheels["RR"]) / 2
fwd = (front - rear)
fwd.z = 0
fwd.normalize()
turn = Matrix.Rotation(math.atan2(fwd.x, fwd.y), 4, "Z")      # front -> +Y
f2 = turn @ front
r2 = turn @ rear
track = (abs((turn @ wheels["FL"]).x - (turn @ wheels["FR"]).x) + abs((turn @ wheels["RL"]).x - (turn @ wheels["RR"]).x)) / 2
sy = (AXLE_F - AXLE_R) / (f2.y - r2.y)
sx = min(max(2 * TRACK_X / track, 0.97), 1.10) * CFG.get("widen", 1.0)
sz = sy * CFG.get("taller", 1.0)
wz = (f2.z + r2.z) / 2
fit = (Matrix.Translation((0, (AXLE_F + AXLE_R) / 2, WHEEL_R + CFG.get("lift", 0.0)))
       @ Matrix.Diagonal((sx, sy, sz, 1.0))
       @ Matrix.Translation((-(f2.x + r2.x) / 2, -(f2.y + r2.y) / 2, -wz)) @ turn)
print("FIT wheelbase %.3f track %.3f -> scale x %.3f y %.3f z %.3f" % (f2.y - r2.y, track, sx, sy, sz))
for o in list(new):
    if o.name.startswith("Wheel_"):
        bpy.data.objects.remove(o, do_unlink=True)
        continue
    o.data.transform(fit @ o.matrix_world)
    o.matrix_world = Matrix.Identity(4)
    if fit.determinant() < 0:
        o.data.flip_normals()
new = [o for o in bpy.data.objects if o not in ours]

# ------------------------------------------------------------------ materials
def mclass(m):
    n = (m.name if m else "").lower()
    for key, cls in CFG.get("mats", {}).items():
        if key.lower() in n:
            return cls
    if "bodymat" in n or "paint" in n or "body" in n:
        return "paint"
    if "transperent" in n or "transparent" in n or "glass" in n:
        return "glass"
    if "light" in n or "lamp" in n:
        return "lamp"
    if "interior" in n:
        return "interior"
    if "tire" in n or "tyre" in n:
        return "tire"
    if "numberplate" in n or "plate" in n:
        return "plate"
    return "trim"


# ------------------------------------------------------------------ split into islands
pieces = []
for o in new:
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    if len(o.data.polygons) > 0:
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.mesh.separate(type="LOOSE")
        bpy.ops.object.mode_set(mode="OBJECT")
    pieces += list(bpy.context.selected_objects)
pieces = list({p.name: p for p in pieces}.values())

info = {}
for p in pieces:
    me = p.data
    cnt = {}
    area = {}
    nsum = Vector()
    for f in me.polygons:
        c = mclass(me.materials[f.material_index] if me.materials else None)
        cnt[c] = cnt.get(c, 0) + 1
        area[c] = area.get(c, 0.0) + f.area
        nsum += f.normal * f.area
    cls = max(area, key=area.get) if area else "trim"
    if p.name.startswith("BrakeLights"):
        cls = "brake"
    mn, mx = bounds([p])
    info[p.name] = dict(cls=cls, mn=mn, mx=mx, c=(mn + mx) / 2, d=mx - mn, area=sum(area.values()), n=nsum)

allmn, allmx = bounds(pieces)
NOSE_Y, TAIL_Y = allmx.y, allmn.y
HALF_W = max(abs(allmn.x), abs(allmx.x))
print("BODY nose %.2f tail %.2f half width %.2f top %.2f" % (NOSE_Y, TAIL_Y, HALF_W, allmx.z))


def P(name):
    return info[name]


# windscreen: the biggest glass piece ahead of the roof's middle, high up, near the centre line
glass = [k for k, v in info.items() if v["cls"] == "glass"]
cab_glass = [k for k in glass if P(k)["c"].z > 0.8 and abs(P(k)["c"].x) < 0.35 and P(k)["d"].x > 0.9]
cab_glass.sort(key=lambda k: -P(k)["area"])
ws = max(cab_glass[:3], key=lambda k: P(k)["c"].y)
cabin_mid = P(ws)["mn"].y - 0.55
rg = [k for k in cab_glass if k != ws and P(k)["c"].y < cabin_mid - 0.1]
rear_glass = rg[0] if rg else None
side_glass = [k for k in glass if abs(P(k)["c"].x) > 0.45 and P(k)["c"].z > 0.75 and P(k)["d"].x < 0.45]
# the door window is the side glass piece just behind the windscreen
door_win = {}
for side, sgn in (("L", -1), ("R", 1)):
    cands = [k for k in side_glass if P(k)["c"].x * sgn > 0 and P(k)["mn"].y < P(ws)["mn"].y + 0.25]
    if cands:
        # four-door cars: the front door's window is the big one nearest the windscreen
        big = max(P(k)["area"] for k in cands)
        cands = [k for k in cands if P(k)["area"] > 0.4 * big]
        door_win[side] = max(cands, key=lambda k: P(k)["mx"].y)
DOOR_Y1 = max(P(k)["mx"].y for k in door_win.values()) + 0.06
DOOR_Y0 = min(P(k)["mn"].y for k in door_win.values()) - 0.12
if "door" in CFG:
    DOOR_Y0, DOOR_Y1 = CFG["door"]
print("WINDSCREEN", ws, "REAR GLASS", rear_glass, "DOOR WINDOWS", door_win, "door y %.2f..%.2f" % (DOOR_Y0, DOOR_Y1))


def in_door(v, sgn):
    if v["c"].x * sgn < 0.55:
        return False
    if v["c"].z > P(door_win["L" if sgn < 0 else "R"])["mx"].z + 0.05:
        return False
    lo = max(v["mn"].y, DOOR_Y0)
    hi = min(v["mx"].y, DOOR_Y1)
    return v["d"].y < 1.9 and (hi - lo) > 0.85 * max(v["d"].y, 0.01)


groups = {}


def put(name, k):
    groups.setdefault(name, []).append(k)


ws_front = P(ws)["mx"].y
for k, v in info.items():
    c, cls = v["c"], v["cls"]
    side = "L" if c.x < 0 else "R"
    sgn = -1 if c.x < 0 else 1
    if cls == "tire":
        bpy.data.objects.remove(bpy.data.objects[k], do_unlink=True)
        continue
    if k == ws:
        put("Windshield", k)
    elif k == rear_glass:
        put("Rear_Glass", k)
    elif k in door_win.values():
        put("Window_F" + side, k)
    elif cls == "brake":
        put("Taillight_" + side, k)
    elif cls in ("lamp", "glass") and c.y > NOSE_Y - 0.75 and c.z < 1.0:
        put("Headlight_" + side, k)
    elif cls in ("lamp", "glass") and c.y < TAIL_Y + 0.6 and c.z < 1.15:
        put("Taillight_" + side, k)
    elif cls == "paint" and abs(c.x) > HALF_W - 0.25 and v["d"].y < 0.45 and v["d"].z < 0.35 \
            and c.z > 0.75 and DOOR_Y0 - 0.2 < c.y < ws_front + 0.1:
        put("Mirror_F" + side, k)
    elif in_door(v, sgn) and cls in ("paint", "interior", "trim", "glass"):
        put("Door_F" + side, k)
    elif cls in ("paint", "trim", "plate") and c.y > NOSE_Y - 0.62 and c.z < 0.62:
        put("Bumper_F", k)
    elif cls in ("paint", "trim", "plate") and c.y < TAIL_Y + 0.55 and c.z < 0.75:
        put("Bumper_R", k)
    elif cls == "paint" and abs(c.x) < CFG.get("hood_w", 0.45) and c.y > ws_front - 0.05 and c.z > 0.5 \
            and v["d"].x > 0.6 and v["n"].z > 0:
        put("Hood", k)
    elif cls == "paint" and abs(c.x) < 0.5 and c.y < cabin_mid - 0.3 and c.z > 0.6 and v["d"].x > 0.6 \
            and v["n"].z > 0 and v["d"].y > 0.3:
        put("Trunk", k)
    elif cls in ("interior", "trim") and abs(c.x) < 0.75 and DOOR_Y0 - 0.3 < c.y < ws_front and c.z > 0.15:
        put("Interior", k)
    else:
        put("Body", k)

# the steering wheel: the interior piece in front of the driver about the size of a rim
drv = [k for k in groups.get("Interior", []) if 0.28 < max(P(k)["d"].x, P(k)["d"].z) < 0.5
       and min(P(k)["d"].x, P(k)["d"].z) > 0.24 and P(k)["d"].y < 0.25 and P(k)["c"].x < -0.15 and 0.6 < P(k)["c"].z < 1.0]
drv.sort(key=lambda k: -len(bpy.data.objects[k].data.polygons))
steer = drv[0] if drv else None
if steer:
    groups["Interior"].remove(steer)
# no separate rim (some models weld it to the column): at least find where the driver's hands are
hands = None
if not steer:
    near = [k for k in groups.get("Interior", []) + groups.get("Body", []) if 0.15 < max(P(k)["d"].x, P(k)["d"].z) < 0.5
            and P(k)["c"].x < -0.2 and 0.65 < P(k)["c"].z < 1.1 and P(ws)["mx"].y - 1.0 < P(k)["c"].y < P(ws)["mx"].y
            ]
    near = [k for k in near if P(k)["c"].y < P(ws)["mx"].y - 0.25]
    near.sort(key=lambda k: -P(k)["c"].y)
    hands = Vector(P(near[0])["c"]) if near else Vector((-0.40, P(ws)["mx"].y - 0.45, 0.95))
    print("HANDS", hands)
print("STEERING", steer, P(steer)["c"] if steer else None)
for name, ks in sorted(groups.items()):
    print("GROUP %-14s %3d pieces" % (name, len(ks)))


def merge(keys, name):
    objs = [bpy.data.objects[k] for k in keys if k in bpy.data.objects]
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    if len(objs) > 1:
        bpy.ops.object.join()
    o = bpy.context.view_layer.objects.active
    o.name = name
    o.data.name = name
    return o


def origin_to(o, p):
    p = Vector(p)
    o.data.transform(Matrix.Translation(-p))
    o.location = p


body_grp = empty("Body", parent=root)
parts = {}
for name, ks in groups.items():
    parts[name] = merge(ks, name)

# materials: our paint (team liveries), our glass (cracks), our red brake-light glow
for o in parts.values():
    for i, m in enumerate(o.data.materials):
        c = mclass(m)
        if c == "paint":
            o.data.materials[i] = M("paint")
        elif c == "glass" and o.name in ("Windshield", "Rear_Glass", "Window_FL", "Window_FR"):
            o.data.materials[i] = M("glass")
        elif c == "brake":
            o.data.materials[i] = M("ledred")
for nm in ("Taillight_L", "Taillight_R"):
    if nm in parts:
        o = parts[nm]
        for i, m in enumerate(o.data.materials):
            if m and m.name.startswith("BrakeLights") or (m and "brake" in m.name.lower()):
                o.data.materials[i] = M("ledred")

# hinge points: doors at their front edge, bonnet at its back edge, boot lid at its front edge
for side in ("L", "R"):
    d = parts.get("Door_F" + side)
    if d:
        mn, mx = bounds([d])
        origin_to(d, ((mn.x + mx.x) / 2, mx.y - 0.02, (mn.z + mx.z) / 2))
        reparent(d, body_grp)
        w = parts.get("Window_F" + side)
        if w:
            reparent(w, d)
        m = parts.get("Mirror_F" + side)
        if m:
            reparent(m, body_grp)
for nm, edge in (("Hood", "min"), ("Trunk", "max")):
    o = parts.get(nm)
    if o:
        mn, mx = bounds([o])
        y = mn.y if edge == "min" else mx.y
        origin_to(o, (0, y, mx.z - 0.02))
for nm, o in parts.items():
    if o.parent is None:
        reparent(o, body_grp)

# steering wheel on a tilt node: its local Y is the column axis (the game spins it about that)
it = empty("Interior_Grp", parent=root)
if steer:
    sw = bpy.data.objects[steer]
    pts = [v.co for v in sw.data.vertices]
    cen = sum(pts, Vector()) / len(pts)
    cov = [[sum((p[i] - cen[i]) * (p[j] - cen[j]) for p in pts) for j in range(3)] for i in range(3)]
    import numpy as np
    w_, v_ = np.linalg.eigh(np.array(cov))
    ax = Vector(v_[:, 0])                    # smallest spread = column axis
    if ax.y < 0:
        ax = -ax
    up = Vector((0, 0, 1))
    xax = ax.cross(up).normalized()
    zax = xax.cross(ax).normalized()
    mtx = Matrix((xax, ax, zax)).transposed().to_4x4()
    mtx.translation = cen
    tilt = empty("SteeringTilt", parent=None)
    tilt.matrix_world = mtx
    reparent(tilt, it)
    sw.data.transform(mtx.inverted())
    sw.name = "SteeringWheel"
    sw.data.name = "SteeringWheel"
    sw.parent = tilt
    sw.matrix_parent_inverse = Matrix.Identity(4)
    sw.matrix_basis = Matrix.Identity(4)
elif hands is not None:
    tilt = empty("SteeringTilt", parent=None)
    tilt.matrix_world = Matrix.Translation(hands) @ Matrix.Rotation(-0.4, 4, "X")
    reparent(tilt, it)
if "Interior" in parts:
    reparent(parts["Interior"], it)

# ------------------------------------------------------------------ race numbers on the doors and bonnet
def surface_hit(o, origin, direction):
    bvh = BVHTree.FromObject(o, bpy.context.evaluated_depsgraph_get())
    mw = o.matrix_world
    inv = mw.inverted()
    loc, nor, idx, dist = bvh.ray_cast(inv @ Vector(origin), (inv.to_3x3() @ Vector(direction)).normalized())
    if loc is None:
        return None, None
    return mw @ loc, (mw.to_3x3() @ nor).normalized()


bpy.context.view_layer.update()
for side, sgn in (("L", -1), ("R", 1)):
    d = parts.get("Door_F" + side)
    if not d:
        continue
    y = min(max(0.0, DOOR_Y0 + 0.35), DOOR_Y1 - 0.35)
    win = parts.get("Window_F" + side)
    z = (bounds([win])[0].z if win else 0.95) - 0.30
    hit, nor = surface_hit(d, (sgn * 3.0, y, z), (-sgn, 0, 0))
    if hit is None:
        continue
    n = text_mesh("Number_" + side, "7", 0.30, "black")
    me = n.data
    me.transform(Matrix.Rotation(math.pi / 2, 4, "X"))
    me.transform(Matrix.Rotation(-math.pi / 2 if sgn > 0 else math.pi / 2, 4, "Z"))
    me.transform(Matrix.Translation(hit + nor * 0.004))
    reparent(n, d)
hood = parts.get("Hood")
if hood:
    hn_, hx_ = bounds([hood])
    hy = (hn_.y + hx_.y) / 2
    hit, nor = surface_hit(hood, (0, hy, 3.0), (0, 0, -1))
    if hit is not None:
        n = text_mesh("Number_Hood", "7", 0.30, "black")
        n.data.transform(Matrix.Translation(hit + Vector((0, 0, 0.006))))
        reparent(n, hood)

def livery_uvs(o):
    """our livery projection (lib.assign_livery_uvs) on the painted faces only: the other faces keep
    the downloaded model's texture coordinates (lamps, grilles, plates, door cards)"""
    bm = bmesh.new()
    bm.from_mesh(o.data)
    uv = bm.loops.layers.uv.verify()
    mw = o.matrix_world
    pi_ = {i for i, m_ in enumerate(o.data.materials) if m_ and m_.name == "paint"}
    for f in bm.faces:
        if f.material_index not in pi_:
            continue
        n = (mw.to_3x3() @ f.normal).normalized()
        side_face = abs(n.x) > 0.55 and abs(n.x) > abs(n.z) * 0.8
        for lp in f.loops:
            p = mw @ lp.vert.co
            if side_face:
                lp[uv].uv = ((-p.y if n.x < 0 else p.y) / 5.0 + 0.5, 0.5 * min(max(p.z / 1.4, 0.0), 1.0) * 0.98)
            else:
                lp[uv].uv = (min(max(p.x / 2.2 + 0.5, 0.0), 1.0), min(max(0.5 + 0.5 * ((p.y + 2.5) / 5.0), 0.5), 1.0))
    bm.to_mesh(o.data)
    bm.free()


for o in bpy.data.objects:
    if o.type == "MESH" and any(m_ and m_.name == "paint" for m_ in o.data.materials):
        if o.name.startswith("Number_"):
            continue
        livery_uvs(o)
# faces that look forwards or backwards low down (grilles, bumper faces, lamp surrounds) get plain
# paint: the stripes are drawn from above and would smear across them
for o in parts.values():
    if not any(m_ and m_.name == "paint" for m_ in o.data.materials):
        continue
    bm = bmesh.new()
    bm.from_mesh(o.data)
    uv = bm.loops.layers.uv.verify()
    mw = o.matrix_world
    pi_ = [i for i, m_ in enumerate(o.data.materials) if m_ and m_.name == "paint"]
    for f in bm.faces:
        if f.material_index not in pi_:
            continue
        n = (mw.to_3x3() @ f.normal).normalized()
        cz = mw @ f.calc_center_median()
        if cz.z < 0.8 and n.z < 0.7 and (cz.y > NOSE_Y - 0.55 or cz.y < TAIL_Y + 0.5 or abs(n.y) > 0.55):
            for lp in f.loops:
                lp[uv].uv = (0.82, 0.75)
    bm.to_mesh(o.data)
    bm.free()
# the downloaded interiors are partly single-sided: draw both sides so nothing goes missing from the cockpit
# and solid: some interior textures carry an alpha channel that would make parts see-through in the game
for m_ in bpy.data.materials:
    if mclass(m_) in ("interior", "trim"):
        m_.use_backface_culling = False
        if m_.use_nodes:
            for nd in m_.node_tree.nodes:
                if nd.type == "BSDF_PRINCIPLED":
                    for l in list(nd.inputs["Alpha"].links):
                        m_.node_tree.links.remove(l)
                    nd.inputs["Alpha"].default_value = 1.0
        # the plain black interiors read as holes in the game's light: lift them to a very dark grey
        if m_.use_nodes and "black" in m_.name.lower():
            for nd in m_.node_tree.nodes:
                if nd.type == "BSDF_PRINCIPLED" and not nd.inputs["Base Color"].links:
                    nd.inputs["Base Color"].default_value = (0.045, 0.045, 0.05, 1)

# numbers for the game's collision hull: nose/tail overhang, roof height, cabin span
roof = max((bounds([o])[1].z for o in parts.values()), default=1.2)
print("SPEC nose %.2f tail %.2f roof %.3f cab [%.2f, %.2f]" % (NOSE_Y, -TAIL_Y, roof, -(P(ws)["mx"].y), -(cabin_mid - 0.6)))

os.makedirs(os.path.dirname(OUT_BLEND), exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND)
bpy.ops.export_scene.gltf(filepath=OUT_GLB, export_format="GLB", export_apply=False, export_yup=True,
                          export_extras=True, export_cameras=False, export_lights=False,
                          export_image_format="AUTO")
print("DONE exported", OUT_GLB, os.path.getsize(OUT_GLB))

# ------------------------------------------------------------------ check pictures: every part its own colour
prev = os.environ.get("PREVIEW_DIR")
if prev:
    import random
    random.seed(4)
    for o in bpy.data.objects:
        if o.type == "MESH":
            o.color = (random.random(), random.random(), random.random(), 1)
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.render.resolution_x, sc.render.resolution_y = 960, 540
    sc.display.shading.light = "STUDIO"
    sc.display.shading.color_type = "OBJECT"
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    link(cam)
    sc.camera = cam
    for nm, loc in (("front", (5.0, 5.5, 2.2)), ("rear", (-5.0, -5.5, 2.2)), ("left", (-6.5, 0.3, 1.2))):
        cam.location = loc
        cam.rotation_euler = (Vector((0, 0, 0.6)) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
        cam.data.lens = 35
        sc.render.filepath = os.path.join(prev, GLB.replace(".glb", "") + "_parts_" + nm + ".png")
        bpy.ops.render.render(write_still=True)
