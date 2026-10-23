"""Shared helpers for the car build. All geometry is authored in world space
(Blender: X right, Y forward, Z up, metres) and parented with the inverse
matrix so positions never move. Origins are moved to pivots with set_origin().
Left side of the car is -X, right is +X, front is +Y."""
import bpy, bmesh, math
from math import pi, sin, cos
from mathutils import Vector, Matrix

MATS = {}


def clear():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    MATS.clear()


def mat(name, color, metal=0.0, rough=0.5, alpha=1.0, emit=None):
    if name in MATS:
        return MATS[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1)
    b.inputs["Metallic"].default_value = metal
    b.inputs["Roughness"].default_value = rough
    if alpha < 1:
        b.inputs["Alpha"].default_value = alpha
        if hasattr(m, "surface_render_method"):
            m.surface_render_method = 'BLENDED'
    if emit:
        b.inputs["Emission Color"].default_value = (*emit, 1)
        b.inputs["Emission Strength"].default_value = 1.0
    m.diffuse_color = (*color, alpha)
    MATS[name] = m
    return m


def M(key):
    """Named material palette."""
    P = {
        'paint': dict(color=(0.04, 0.12, 0.45), metal=0.6, rough=0.25),
        'glass': dict(color=(0.35, 0.5, 0.55), metal=0.0, rough=0.05, alpha=0.35),
        'black': dict(color=(0.02, 0.02, 0.02), rough=0.6),
        'plastic': dict(color=(0.05, 0.05, 0.055), rough=0.7),
        'rubber': dict(color=(0.015, 0.015, 0.015), rough=0.9),
        'steel': dict(color=(0.45, 0.45, 0.47), metal=1.0, rough=0.45),
        'darksteel': dict(color=(0.12, 0.12, 0.13), metal=0.9, rough=0.5),
        'chrome': dict(color=(0.85, 0.85, 0.88), metal=1.0, rough=0.1),
        'alloy': dict(color=(0.6, 0.62, 0.65), metal=1.0, rough=0.25),
        'disc': dict(color=(0.35, 0.3, 0.28), metal=0.9, rough=0.55),
        'caliper': dict(color=(0.7, 0.05, 0.03), metal=0.3, rough=0.4),
        'spring': dict(color=(0.9, 0.55, 0.05), metal=0.6, rough=0.4),
        'damper': dict(color=(0.08, 0.08, 0.09), metal=0.8, rough=0.35),
        'rod': dict(color=(0.8, 0.8, 0.82), metal=1.0, rough=0.15),
        'engine': dict(color=(0.22, 0.23, 0.25), metal=0.8, rough=0.55),
        'alum': dict(color=(0.55, 0.56, 0.58), metal=1.0, rough=0.4),
        'floor': dict(color=(0.1, 0.1, 0.11), rough=0.9),
        'seat': dict(color=(0.15, 0.13, 0.11), rough=0.8),
        'dash': dict(color=(0.07, 0.07, 0.08), rough=0.6),
        'lamp': dict(color=(0.9, 0.9, 0.85), metal=0.0, rough=0.05, alpha=0.6),
        'tail': dict(color=(0.7, 0.02, 0.02), metal=0.0, rough=0.1, alpha=0.8),
        'orange': dict(color=(0.9, 0.35, 0.02), rough=0.3),
        'rust': dict(color=(0.25, 0.1, 0.05), metal=0.5, rough=0.7),
        'plate': dict(color=(0.9, 0.9, 0.9), rough=0.5),
        'headliner': dict(color=(0.55, 0.52, 0.47), rough=0.9),
        'rimcolor': dict(color=(0.05, 0.05, 0.055), metal=0.9, rough=0.3),
        'gold': dict(color=(0.95, 0.68, 0.12), metal=1.0, rough=0.25),
        'carbon': dict(color=(0.012, 0.012, 0.016), metal=0.3, rough=0.3),
        'red': dict(color=(0.75, 0.03, 0.02), rough=0.4),
        'harness': dict(color=(0.8, 0.05, 0.03), rough=0.8),
        'ledwhite': dict(color=(1.0, 1.0, 1.0), rough=0.1, emit=(1.0, 1.0, 0.95)),
        'ledred': dict(color=(1.0, 0.0, 0.0), rough=0.1, emit=(1.0, 0.02, 0.02)),
        'cage': dict(color=(0.55, 0.56, 0.6), metal=1.0, rough=0.35),
        'screen': dict(color=(0.0, 0.0, 0.0), rough=0.1, emit=(0.0, 0.5, 0.9)),
    }
    return mat(key, **P[key])


def link(o):
    bpy.context.collection.objects.link(o)
    return o


def mesh_obj(name, verts, faces, material=None, smooth=True):
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], [], faces)
    me.update()
    o = bpy.data.objects.new(name, me)
    link(o)
    if material:
        me.materials.append(M(material) if isinstance(material, str) else material)
    if smooth:
        for p in me.polygons:
            p.use_smooth = True
    return o


def empty(name, loc=(0, 0, 0), parent=None, size=0.05):
    e = bpy.data.objects.new(name, None)
    e.empty_display_size = size
    e.location = loc
    link(e)
    if parent:
        reparent(e, parent)
    return e


def reparent(o, parent):
    bpy.context.view_layer.update()
    mw = o.matrix_world.copy()
    o.parent = parent
    o.matrix_parent_inverse = parent.matrix_world.inverted()
    o.matrix_world = mw


def set_origin(o, p):
    p = Vector(p)
    o.data.transform(Matrix.Translation(-p))
    o.location = o.location + p


def box(name, size, center, material, rot=None):
    sx, sy, sz = [s / 2 for s in size]
    v = [(-sx, -sy, -sz), (sx, -sy, -sz), (sx, sy, -sz), (-sx, sy, -sz),
         (-sx, -sy, sz), (sx, -sy, sz), (sx, sy, sz), (-sx, sy, sz)]
    f = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (2, 3, 7, 6), (1, 2, 6, 5), (3, 0, 4, 7)]
    o = mesh_obj(name, v, f, material, smooth=False)
    if rot:
        o.data.transform(Matrix.Rotation(rot[0], 4, rot[1]))
    o.data.transform(Matrix.Translation(center))
    return o


def cyl(name, r, depth, center, axis, material, seg=24, r2=None):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=seg, radius1=r,
                          radius2=r if r2 is None else r2, depth=depth)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    link(o)
    if axis == 'X':
        me.transform(Matrix.Rotation(pi / 2, 4, 'Y'))
    elif axis == 'Y':
        me.transform(Matrix.Rotation(pi / 2, 4, 'X'))
    me.transform(Matrix.Translation(center))
    if material:
        me.materials.append(M(material))
    for p in me.polygons:
        p.use_smooth = True
    return o


def sphere(name, r, center, material, seg=16, scale=(1, 1, 1)):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=max(6, seg // 2), radius=r)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.transform(Matrix.Diagonal((*scale, 1)))
    me.transform(Matrix.Translation(center))
    o = bpy.data.objects.new(name, me)
    link(o)
    if material:
        me.materials.append(M(material))
    for p in me.polygons:
        p.use_smooth = True
    return o


def tube(name, pts, r, material, seg=10, closed=False):
    """Round pipe along a polyline."""
    verts, faces = [], []
    pts = [Vector(p) for p in pts]
    for i, p in enumerate(pts):
        if closed:
            a, b = pts[i - 1], pts[(i + 1) % len(pts)]
        else:
            a = pts[max(i - 1, 0)]
            b = pts[min(i + 1, len(pts) - 1)]
        t = (b - a).normalized()
        n = t.cross(Vector((0, 0, 1)))
        if n.length < 1e-4:
            n = t.cross(Vector((1, 0, 0)))
        n.normalize()
        bn = t.cross(n).normalized()
        for k in range(seg):
            th = 2 * pi * k / seg
            verts.append(p + r * (cos(th) * n + sin(th) * bn))
    nseg = len(pts) if closed else len(pts) - 1
    for i in range(nseg):
        i2 = (i + 1) % len(pts)
        for k in range(seg):
            a = i * seg + k
            b = i * seg + (k + 1) % seg
            faces.append((a, b, i2 * seg + (k + 1) % seg, i2 * seg + k))
    if closed:
        return mesh_obj(name, verts, faces, material)
    # caps
    c0 = len(verts)
    verts.append(pts[0])
    verts.append(pts[-1])
    for k in range(seg):
        faces.append((c0, (k + 1) % seg, k))
        o = (len(pts) - 1) * seg
        faces.append((c0 + 1, o + k, o + (k + 1) % seg))
    ob = mesh_obj(name, verts, faces, material)
    return ob


def helix(name, r, wire, turns, height, material, seg_per_turn=16, ring=6):
    """Coil spring. Origin at the top end, body extends along -Z by `height`."""
    verts, faces = [], []
    n = int(turns * seg_per_turn)
    for i in range(n + 1):
        t = i / n
        a = t * turns * 2 * pi
        c = Vector((r * cos(a), r * sin(a), -t * height))
        tan = Vector((-r * sin(a) * 2 * pi * turns, r * cos(a) * 2 * pi * turns, -height)).normalized()
        rad = Vector((cos(a), sin(a), 0))
        bn = tan.cross(rad).normalized()
        for k in range(ring):
            th = 2 * pi * k / ring
            verts.append(c + wire * (cos(th) * rad + sin(th) * bn))
    for i in range(n):
        for k in range(ring):
            a = i * ring + k
            b = i * ring + (k + 1) % ring
            faces.append((a, b, b + ring, a + ring))
    return mesh_obj(name, verts, faces, material)


def revolve(name, profile, material, segs=48, closed=True):
    """Revolve (radius, axial) profile around the X axis."""
    verts, faces = [], []
    n = len(profile)
    for s in range(segs):
        th = 2 * pi * s / segs
        for r, a in profile:
            verts.append((a, r * cos(th), r * sin(th)))
    for s in range(segs):
        s2 = (s + 1) % segs
        rng = range(n) if closed else range(n - 1)
        for i in rng:
            j = (i + 1) % n
            faces.append((s * n + i, s * n + j, s2 * n + j, s2 * n + i))
    o = mesh_obj(name, verts, faces, material)
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(o.data)
    bm.free()
    return o


def chaikin(pts, it=2):
    for _ in range(it):
        out = [pts[0]]
        for a, b in zip(pts[:-1], pts[1:]):
            out.append((0.75 * a[0] + 0.25 * b[0], 0.75 * a[1] + 0.25 * b[1]))
            out.append((0.25 * a[0] + 0.75 * b[0], 0.25 * a[1] + 0.75 * b[1]))
        out.append(pts[-1])
        pts = out
    return pts


def catmull(rows, per_seg):
    """Smoothly resample a list of equal-length parameter tuples."""
    out = []
    n = len(rows)
    for i in range(n - 1):
        p0 = rows[max(i - 1, 0)]
        p1, p2 = rows[i], rows[i + 1]
        p3 = rows[min(i + 2, n - 1)]
        for k in range(per_seg):
            t = k / per_seg
            t2, t3 = t * t, t * t * t
            out.append(tuple(
                0.5 * ((2 * b) + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (-a + 3 * b - 3 * c + d) * t3)
                for a, b, c, d in zip(p0, p1, p2, p3)))
    out.append(rows[-1])
    return out


def loft(name, stations, material, cap_first=False, cap_last=False):
    """stations: list of (y, [(x, z), ...] right half, bottom -> centre).
    Mirrors to the left. Returns smooth open shell with outward normals."""
    verts, faces, rowlen = [], [], None
    for y, half in stations:
        right = [(x, y, z) for x, z in half]
        left = [(-x, y, z) for x, z in reversed(half) if abs(x) > 1e-6]
        ring = right + left
        rowlen = len(ring)
        verts += ring
    for j in range(len(stations) - 1):
        for i in range(rowlen - 1):
            a = j * rowlen + i
            faces.append((a, a + 1, a + 1 + rowlen, a + rowlen))
    for first, flag in ((True, cap_first), (False, cap_last)):
        if not flag:
            continue
        j = 0 if first else len(stations) - 1
        ring = verts[j * rowlen:(j + 1) * rowlen]
        c = Vector((0, 0, 0))
        for v in ring:
            c += Vector(v)
        c /= len(ring)
        ci = len(verts)
        verts.append(tuple(c))
        for i in range(rowlen - 1):
            a = j * rowlen + i
            faces.append((a + 1, a, ci) if first else (a, a + 1, ci))
    o = mesh_obj(name, verts, faces, material)
    # make normals point away from the car centre-line / upwards
    me = o.data
    me.update()
    up = 0
    for p in me.polygons:
        c = p.center
        out = Vector((c.x, 0, max(c.z - 0.6, 0)))
        up += 1 if p.normal.dot(out) > 0 else -1
    if up < 0:
        me.flip_normals()
    return o


def bake(o):
    dg = bpy.context.evaluated_depsgraph_get()
    ev = o.evaluated_get(dg)
    me = bpy.data.meshes.new_from_object(ev)
    old = o.data
    o.data = me
    o.modifiers.clear()
    bpy.data.meshes.remove(old)
    for p in me.polygons:
        p.use_smooth = True
    return o


def solidify(o, t):
    m = o.modifiers.new("solid", 'SOLIDIFY')
    m.thickness = t
    m.offset = -1
    m.use_even_offset = True
    return bake(o)


def boolean(o, other, op):
    m = o.modifiers.new("b", 'BOOLEAN')
    m.object = other
    m.operation = op
    m.solver = 'EXACT'
    return bake(o)


def dup(o, name):
    n = o.copy()
    n.data = o.data.copy()
    n.name = name
    link(n)
    return n


def delete(o):
    d = o.data
    bpy.data.objects.remove(o, do_unlink=True)
    if d and d.users == 0:
        if isinstance(d, bpy.types.Mesh):
            bpy.data.meshes.remove(d)


def slice_panel(src, name, region, shrink=0.0, material=None):
    """Copy of src intersected with the box `region` = (xmin,xmax,ymin,ymax,zmin,zmax)."""
    x0, x1, y0, y1, z0, z1 = region
    b = box("_cut", (x1 - x0 - 2 * shrink, y1 - y0 - 2 * shrink, z1 - z0 - 2 * shrink),
            ((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), None)
    p = dup(src, name)
    boolean(p, b, 'INTERSECT')
    delete(b)
    return p


def cut_out(src, region, grow=0.0):
    x0, x1, y0, y1, z0, z1 = region
    b = box("_cut", (x1 - x0 + 2 * grow, y1 - y0 + 2 * grow, z1 - z0 + 2 * grow),
            ((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), None)
    boolean(src, b, 'DIFFERENCE')
    delete(b)
    return src


def render_views(path_prefix, views, res=(1280, 720), engine='BLENDER_WORKBENCH'):
    sc = bpy.context.scene
    sc.render.engine = engine
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.display.shading.light = 'STUDIO'
    sc.display.shading.color_type = 'MATERIAL'
    sc.display.shading.show_cavity = True
    sc.world = bpy.data.worlds.new("w")
    sc.world.color = (0.55, 0.6, 0.65)
    cam_d = bpy.data.cameras.new("cam")
    cam = bpy.data.objects.new("cam", cam_d)
    link(cam)
    sc.camera = cam
    for name, loc, target, lens in views:
        cam_d.lens = lens
        cam.location = loc
        d = Vector(target) - Vector(loc)
        cam.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
        sc.render.filepath = f"{path_prefix}_{name}.png"
        bpy.ops.render.render(write_still=True)


def join(objs, name, parent=None):
    """Merge objects into one mesh (world space), keeping materials."""
    bpy.context.view_layer.update()
    verts, faces, mi, sm, mats = [], [], [], [], []
    for o in objs:
        mw = o.matrix_world
        me = o.data
        off = len(verts)
        verts += [tuple(mw @ v.co) for v in me.vertices]
        remap = {}
        for i, m_ in enumerate(me.materials):
            if m_ not in mats:
                mats.append(m_)
            remap[i] = mats.index(m_)
        for p in me.polygons:
            faces.append(tuple(v + off for v in p.vertices))
            mi.append(remap.get(p.material_index, 0))
            sm.append(p.use_smooth)
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    for m_ in mats:
        me.materials.append(m_)
    for p, i, s_ in zip(me.polygons, mi, sm):
        p.material_index = i
        p.use_smooth = s_
    me.update()
    n = bpy.data.objects.new(name, me)
    link(n)
    for o in objs:
        delete(o)
    if parent:
        reparent(n, parent)
    return n


# ---------------------------------------------------------------- livery / extras
def make_livery_image(path=None, size=2048):
    """Top half of the atlas = top projection (x, y), bottom half = side projection (y, z)."""
    import numpy as np
    n = size
    u = (np.arange(n) + 0.5) / n
    v = (np.arange(n) + 0.5) / n
    U, V = np.meshgrid(u, v)          # V=0 at the bottom row
    img = np.zeros((n, n, 4), dtype=np.float32)
    base = np.array([0.025, 0.07, 0.30, 1.0])
    img[:] = base
    top = V >= 0.5
    # ---- top projection: x in [-1.1, 1.1], y in [-2.5, 2.5]
    x = (U - 0.5) * 2.2
    y = ((V - 0.5) / 0.5 - 0.5) * 5.0
    ax = np.abs(x)
    white = np.array([0.93, 0.93, 0.95, 1.0])
    orange = np.array([1.0, 0.38, 0.02, 1.0])
    s1 = top & (ax > 0.07) & (ax < 0.22)
    s2 = top & (ax > 0.25) & (ax < 0.29)
    img[s1] = white
    img[s2] = orange
    # fade stripes out under the rear wing / front splitter for a cleaner look
    # ---- side projection: y in [-2.5, 2.5] -> u ; z in [0, 1.4] -> v*2
    ys = (U - 0.5) * 5.0
    zs = (V / 0.5) * 1.4
    side = ~top
    lower = side & (zs < 0.34)
    img[lower] = np.array([0.02, 0.02, 0.025, 1.0])
    band = side & (zs > 0.34) & (zs < 0.38)
    img[band] = orange
    swoosh = side & (zs > 0.52) & (zs < 0.60) & (ys > -2.2) & (ys < 1.0 + (zs - 0.52) * 6.0)
    img[swoosh] = white
    roundel = side & (((ys - 0.0) ** 2 + (zs - 0.62) ** 2) < 0.26 ** 2) & (ys > -0.45) & (ys < 0.45)
    img[roundel] = white
    # ---- hood/roof number plate patches on the top projection
    for (cx, cy, r) in ((0.0, 1.35, 0.30), (0.0, -0.3, 0.30)):
        patch = top & ((x - cx) ** 2 + (y - cy) ** 2 < r * r)
        img[patch] = white
    img[..., 3] = 1.0
    im = bpy.data.images.new("livery", n, n, alpha=False)
    im.pixels.foreach_set(img.reshape(-1))
    im.pack()
    return im


def setup_paint_livery():
    im = make_livery_image()
    m = bpy.data.materials.new("paint")
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = im
    tex.interpolation = 'Smart'
    nt.links.new(tex.outputs["Color"], b.inputs["Base Color"])
    b.inputs["Metallic"].default_value = 0.55
    b.inputs["Roughness"].default_value = 0.22
    MATS['paint'] = m
    return m


def assign_livery_uvs(objs):
    for o in objs:
        me = o.data
        if not any(m_ and m_.name == 'paint' for m_ in me.materials):
            continue
        bm = bmesh.new()
        bm.from_mesh(me)
        uv = bm.loops.layers.uv.verify()
        mw = o.matrix_world
        for f in bm.faces:
            n = (mw.to_3x3() @ f.normal).normalized()
            side_face = abs(n.x) > 0.55 and abs(n.x) > abs(n.z) * 0.8
            for lp in f.loops:
                p = mw @ lp.vert.co
                if side_face:
                    yy = p.y if n.x > 0 else p.y      # same orientation both sides (mirrored text is acceptable)
                    uu = (-yy if n.x < 0 else yy) / 5.0 + 0.5
                    vv = 0.5 * min(max(p.z / 1.4, 0.0), 1.0) * 0.98
                    lp[uv].uv = (uu, vv)
                else:
                    uu = p.x / 2.2 + 0.5
                    vv = 0.5 + 0.5 * ((p.y + 2.5) / 5.0)
                    lp[uv].uv = (min(max(uu, 0.0), 1.0), min(max(vv, 0.5), 1.0))
        bm.to_mesh(me)
        bm.free()


def airfoil(name, profile, x0, x1, material):
    """Extrude a closed (y, z) profile along X from x0 to x1."""
    verts, faces = [], []
    n = len(profile)
    for x in (x0, x1):
        for y, z in profile:
            verts.append((x, y, z))
    for i in range(n):
        j = (i + 1) % n
        faces.append((i, j, n + j, n + i))
    c0 = len(verts)
    cy = sum(p[0] for p in profile) / n
    cz = sum(p[1] for p in profile) / n
    verts.append((x0, cy, cz))
    verts.append((x1, cy, cz))
    for i in range(n):
        j = (i + 1) % n
        faces.append((c0, j, i))
        faces.append((c0 + 1, n + i, n + j))
    o = mesh_obj(name, verts, faces, material, smooth=False)
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(o.data)
    bm.free()
    return o


def text_mesh(name, text, size, material, thickness=0.004):
    cu = bpy.data.curves.new(name, 'FONT')
    cu.body = text
    cu.size = size
    cu.align_x = 'CENTER'
    cu.align_y = 'CENTER'
    cu.extrude = thickness / 2
    ob = bpy.data.objects.new(name, cu)
    link(ob)
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
    bpy.data.objects.remove(ob)
    bpy.data.curves.remove(cu)
    o = bpy.data.objects.new(name, me)
    link(o)
    me.materials.append(M(material))
    return o
