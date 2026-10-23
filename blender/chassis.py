"""Wheels, suspension (springs, dampers, arms, shafts), brakes, frame, front-mid V8, rear-drive line."""
from lib import *
from body import WHEEL_R, AXLE_F, AXLE_R, TRACK_X, NOSE, TAIL
from variants import S

RIM_R = 0.2413          # 19 inch rim
TIRE_HALF = 0.1375      # 275 mm wide


def tire_profile():
    half = [(RIM_R, 0.118), (0.268, 0.1375), (0.305, 0.140), (0.330, 0.128), (0.3385, 0.105),
            (0.340, 0.075), (0.3405, 0.0)]
    pts = [(r, -a) for r, a in half]
    pts += [(r, a) for r, a in reversed(half[:-1])]
    pts += [(RIM_R - 0.006, 0.112), (RIM_R - 0.006, -0.112)]
    return pts


def build_wheel_parts(tag, sx, C, wheel_node, steer_node):
    tire = revolve(f"Tire_{tag}", tire_profile(), 'rubber', segs=72)
    tire.location = C
    reparent(tire, wheel_node)
    barrel_prof = [(0.250, -0.118), (RIM_R, -0.108), (RIM_R, 0.108), (0.250, 0.118),
                   (0.232, 0.118), (0.226, 0.108), (0.226, -0.108), (0.232, -0.118)]
    parts = [revolve("_barrel", barrel_prof, 'rimcolor', segs=64)]
    # ten thin spokes, dished outwards, centre-lock nut
    for k in range(10):
        th = k * 2 * pi / 10
        sp = box("_spoke", (0.022, 0.034, 0.185), (sx * (0.085 - 0.012 * (k % 2)), 0, 0.14), 'rimcolor')
        sp.data.transform(Matrix.Rotation(th, 4, 'X'))
        parts.append(sp)
    parts.append(cyl("_hubdisc", 0.085, 0.03, (sx * 0.078, 0, 0), 'X', 'rimcolor', seg=28))
    parts.append(cyl("_nut", 0.048, 0.04, (sx * 0.098, 0, 0), 'X', 'gold', seg=6))
    parts.append(cyl("_ring", 0.062, 0.012, (sx * 0.085, 0, 0), 'X', 'gold', seg=28))
    for p in parts:
        p.location = Vector(p.location) + C
    rim = join(parts, f"Rim_{tag}")
    set_origin(rim, C)
    reparent(rim, wheel_node)
    prof = [(0.185, -0.016), (0.185, 0.016), (0.112, 0.016), (0.100, 0.050), (0.050, 0.050),
            (0.050, 0.034), (0.092, 0.034), (0.102, -0.016)]
    disc = revolve(f"Disc_{tag}", [(r, sx * (a - 0.075)) for r, a in prof], 'disc', segs=64)
    disc.location = C
    reparent(disc, wheel_node)


def build_caliper_knuckle(tag, sx, C, hub, steer, front):
    ys = 0.0 if front else 0.0
    cal = [box("_c1", (0.085, 0.10, 0.15), (C.x - sx * 0.075, C.y - 0.14, C.z + 0.04), 'caliper'),
           box("_c2", (0.02, 0.12, 0.20), (C.x - sx * 0.12, C.y - 0.14, C.z + 0.04), 'caliper'),
           box("_c3", (0.02, 0.12, 0.20), (C.x - sx * 0.035, C.y - 0.14, C.z + 0.04), 'caliper'),
           cyl("_bleed", 0.006, 0.03, (C.x - sx * 0.075, C.y - 0.14, C.z + 0.13), 'Z', 'steel', seg=8)]
    caliper = join(cal, f"Caliper_{tag}")
    set_origin(caliper, C)
    reparent(caliper, steer)
    kn = [box("_k1", (0.05, 0.14, 0.34), (C.x - sx * 0.125, C.y, C.z + 0.08), 'darksteel'),
          cyl("_hubnut", 0.055, 0.05, (C.x - sx * 0.10, C.y, C.z), 'X', 'darksteel', seg=20),
          cyl("_bearing", 0.065, 0.03, (C.x - sx * 0.05, C.y, C.z), 'X', 'steel', seg=20),
          box("_duct", (0.04, 0.05, 0.12), (C.x - sx * 0.10, C.y + 0.16, C.z - 0.02), 'carbon')]
    knuckle = join(kn, f"Knuckle_{tag}")
    set_origin(knuckle, C)
    reparent(knuckle, steer)


def build_strut(tag, sx, ay, front, hub, grp):
    if front:
        x, y, top_z, slen = sx * 0.60, ay, 0.72, 0.26
        sx_, sy_, sp_z = x, y, top_z - 0.01
    else:
        x, y, top_z, slen = sx * 0.66, ay - 0.10, 0.72, 0.24
        sx_, sy_, sp_z = sx * 0.56, ay + 0.12, 0.62
    spring = helix(f"Spring_{tag}", 0.062, 0.0075, 6.0, slen, 'spring', seg_per_turn=14)
    spring.location = (sx_, sy_, sp_z)
    reparent(spring, grp)
    mount = join([cyl("_m1", 0.075, 0.02, (sx_, sy_, sp_z + 0.01), 'Z', 'darksteel', seg=20),
                  cyl("_m2", 0.03, 0.04, (x, y, top_z + 0.03), 'Z', 'darksteel', seg=12)], f"TopMount_{tag}")
    reparent(mount, grp)
    rod_top = top_z + 0.01
    rod = cyl(f"DamperRod_{tag}", 0.011, 0.42, (x, y, rod_top - 0.21), 'Z', 'rod', seg=12)
    set_origin(rod, (x, y, rod_top))
    reparent(rod, grp)
    tube_top = rod_top - 0.28
    dt = join([cyl("_t1", 0.032, 0.26, (x, y, tube_top - 0.13), 'Z', 'gold', seg=16),
               cyl("_t2", 0.038, 0.03, (x, y, tube_top - 0.015), 'Z', 'red', seg=16),
               cyl("_t3", 0.045, 0.02, (x, y, tube_top - 0.26), 'Z', 'darksteel', seg=16),
               cyl("_res", 0.022, 0.12, (x + sx * 0.05, y, tube_top - 0.05), 'Z', 'gold', seg=12)], f"DamperTube_{tag}")
    set_origin(dt, (x, y, tube_top))
    reparent(dt, hub)
    seat_z = sp_z - slen
    seat = cyl(f"SpringSeat_{tag}", 0.08, 0.015, (sx_, sy_, seat_z - 0.0075), 'Z', 'red', seg=20)
    reparent(seat, hub)
    Cx = sx * TRACK_X
    br = tube("StrutBracket_" + tag, [(Cx - sx * 0.125, ay, 0.46), (x, y, tube_top - 0.20)], 0.015, 'darksteel')
    reparent(br, hub)
    if not front:
        br2 = tube("StrutBracket2_" + tag, [(Cx - sx * 0.125, ay, 0.40), (sx_, sy_, seat_z - 0.02)], 0.015, 'darksteel')
        reparent(br2, hub)
    bs = cyl(f"BumpStop_{tag}", 0.02, 0.05, (x, y, top_z - 0.06), 'Z', 'rubber', seg=10)
    reparent(bs, grp)


def build_arm(tag, sx, ay, front, grp):
    bj = Vector((sx * (TRACK_X - 0.085), ay, 0.27))
    pivot = Vector((sx * 0.34, ay, 0.30))
    dy1, dy2 = (0.26, -0.24) if front else (0.22, -0.22)
    p1 = Vector((sx * 0.34, ay + dy1, 0.30))
    p2 = Vector((sx * 0.34, ay + dy2, 0.30))
    parts = [tube("_a1", [p1, bj], 0.018, 'carbon'), tube("_a2", [p2, bj], 0.018, 'carbon'),
             sphere("_bj", 0.032, bj, 'steel', seg=10),
             cyl("_b1", 0.026, 0.06, p1, 'Y', 'gold', seg=12), cyl("_b2", 0.026, 0.06, p2, 'Y', 'gold', seg=12)]
    arm = join(parts, f"Arm_{tag}")
    set_origin(arm, pivot)
    reparent(arm, grp)


def build_axle_shaft(tag, sx, ay, grp):
    """Rear half shaft: origin at the differential end, extends to the hub."""
    inner = Vector((sx * 0.30, ay, 0.34))
    outer = Vector((sx * (TRACK_X - 0.10), ay, WHEEL_R))
    parts = [tube("_sh", [inner, outer], 0.017, 'steel', seg=10),
             cyl("_cv1", 0.042, 0.07, inner + Vector((sx * 0.06, 0, 0)), 'X', 'rubber', seg=14),
             cyl("_cv2", 0.045, 0.06, outer - Vector((sx * 0.05, 0, 0)), 'X', 'rubber', seg=14)]
    sh = join(parts, f"Axle_{tag}")
    set_origin(sh, inner)
    reparent(sh, grp)


def build_corner(root, grp, side, front):
    sx = -1 if side == 'L' else 1
    ay = AXLE_F if front else AXLE_R
    tag = ('F' if front else 'R') + side
    C = Vector((sx * TRACK_X, ay, WHEEL_R))
    hub = empty(f"Hub_{tag}", C, parent=grp)
    steer = empty(f"Steer_{tag}", C, parent=hub)
    wheel = empty(f"Wheel_{tag}", C, parent=steer)
    build_wheel_parts(tag, sx, C, wheel, steer)
    build_caliper_knuckle(tag, sx, C, hub, steer, front)
    build_strut(tag, sx, ay, front, hub, grp)
    build_arm(tag, sx, ay, front, grp)
    if not front:
        build_axle_shaft(tag, sx, ay, grp)
    return hub


def build_frame(grp):
    ch = empty("Chassis", parent=grp)

    def add(o, name):
        o.name = name
        reparent(o, ch)
        return o

    pan = [box("_p", (1.78, 3.0, 0.012), (0, -0.45, 0.215), 'carbon'),
           box("_t", (0.34, 2.2, 0.14), (0, -0.05, 0.28), 'carbon')]
    add(join(pan, "FloorPan"), "FloorPan")
    add(box("_f", (1.78, 0.012, 0.65), (0, 0.76, 0.54), 'carbon'), "Firewall")
    for sx in (-1, 1):
        s = "L" if sx < 0 else "R"
        add(box("_r", (0.09, 1.50, 0.13), (sx * 0.40, 1.50, 0.34), 'darksteel'), f"FrontRail_{s}")
        add(box("_r", (0.09, 1.30, 0.12), (sx * 0.40, -1.65, 0.34), 'darksteel'), f"RearRail_{s}")
        add(box("_s", (0.10, 2.2, 0.12), (sx * 0.90, -0.05, 0.31), 'carbon'), f"Sill_{s}")
    for name, y0 in (("SubframeF", AXLE_F), ("SubframeR", AXLE_R)):
        parts = [box("_a", (0.82, 0.06, 0.06), (0, y0 - 0.24, 0.25), 'darksteel'),
                 box("_b", (0.82, 0.06, 0.06), (0, y0 + 0.26, 0.25), 'darksteel'),
                 box("_c", (0.06, 0.56, 0.06), (-0.40, y0 + 0.01, 0.25), 'darksteel'),
                 box("_d", (0.06, 0.56, 0.06), (0.40, y0 + 0.01, 0.25), 'darksteel')]
        add(join(parts, name), name)
    add(box("_cb", (1.45, 0.09, 0.12), (0, NOSE - 0.23, 0.46), 'darksteel'), "CrashBeam_F")
    add(box("_cb", (1.45, 0.09, 0.12), (0, TAIL + 0.15, 0.50), 'darksteel'), "CrashBeam_R")
    # fuel cell, rear differential, driveshaft, exhaust
    add(box("_fc", (0.80, 0.55, 0.20), (0, -1.88, 0.33), 'darksteel'), "FuelCell")
    diff = [box("_d", (0.30, 0.34, 0.26), (0, AXLE_R, 0.34), 'alum'),
            cyl("_dc", 0.10, 0.05, (0, AXLE_R + 0.20, 0.34), 'Y', 'alum', seg=16)]
    add(join(diff, "RearDiff"), "RearDiff")
    add(tube("_ds", [(0, 0.45, 0.30), (0, AXLE_R + 0.2, 0.34)], 0.04, 'darksteel', seg=12), "Driveshaft")
    exh = []
    for sx in (-1, 1):
        # pipes run under the floor, silencers sit up above the diffuser roof (out of sight),
        # and open titanium tips exit through the diffuser
        ex, ez = S["exhaust"]
        exh.append(tube("_e", [(sx * 0.22, 1.00, 0.30), (sx * 0.20, 0.5, 0.20), (sx * 0.18, -0.6, 0.18),
                               (sx * 0.24, TAIL + 0.75, 0.30), (sx * ex, TAIL + 0.22, ez)], 0.032, 'steel'))
        exh.append(cyl("_mu", 0.075, 0.42, (sx * 0.26, TAIL + 0.70, 0.36), 'Y', 'steel', seg=20))
        exh.append(cyl("_tip", 0.052, 0.20, (sx * ex, TAIL + 0.06, ez), 'Y', 'titanium', seg=20))
        exh.append(cyl("_hole", 0.041, 0.012, (sx * ex, TAIL - 0.041, ez), 'Y', 'soot', seg=20))
    add(join(exh, "Exhaust"), "Exhaust")
    for nm, ay, sy in (("SwayBar_F", AXLE_F, -0.22), ("SwayBar_R", AXLE_R, 0.22)):
        pts = [(-0.74, ay + sy * 0.4, 0.32), (-0.58, ay + sy, 0.30), (0.58, ay + sy, 0.30), (0.74, ay + sy * 0.4, 0.32)]
        add(tube("_sw", pts, 0.013, 'red', seg=8), nm)
    add(cyl("_rack", 0.026, 0.66, (0, AXLE_F - 0.14, 0.38), 'X', 'alum', seg=14), "SteeringRack")
    return ch


def build_engine_bay(grp):
    eb = empty("EngineBay", parent=grp)

    def add(o, name):
        o.name = name
        reparent(o, eb)
        return o

    def gj(parts, name):
        return add(join(parts, name), name)

    # longitudinal engine: front-mid, mid (behind the cabin) or rear (behind the axle)
    ey = S["engine_y"]
    fwd = 1.0 if ey > 0.0 else -1.0       # which way the gearbox sits: towards the cabin
    if ey < -1.75:
        fwd = 1.0                          # rear-engined: transaxle ahead of the engine
    gj([box("_b", (0.50, 0.66, 0.26), (0, ey, 0.46), 'engine'),
        box("_hl", (0.20, 0.62, 0.10), (-0.20, ey, 0.64), 'engine'),
        box("_hr", (0.20, 0.62, 0.10), (0.20, ey, 0.64), 'engine'),
        box("_cl", (0.17, 0.58, 0.05), (-0.20, ey, 0.71), 'red'),
        box("_cr", (0.17, 0.58, 0.05), (0.20, ey, 0.71), 'red'),
        box("_oil", (0.42, 0.55, 0.09), (0, ey, 0.30), 'alum'),
        box("_ft", (0.42, 0.06, 0.34), (0, ey + 0.35, 0.50), 'alum')], "Engine")
    gj([box("_plen", (0.30, 0.52, 0.06), (0, ey, 0.80), 'carbon')] +
       [cyl("_tr%d" % i, 0.026, 0.07, (sx * 0.1, ey - 0.21 + 0.14 * i, 0.74), 'Z', 'carbon', seg=10)
        for i in range(4) for sx in (-1, 1)], "IntakeManifold")
    hdr = []
    for sx in (-1, 1):
        for i in range(4):
            yy = ey - 0.21 + 0.14 * i
            hdr.append(tube("_h", [(sx * 0.27, yy, 0.62), (sx * 0.34, yy, 0.50), (sx * 0.30, yy, 0.38),
                                   (sx * 0.22, ey - 0.45, 0.26)], 0.018, 'rust', seg=8))
    gj(hdr, "Headers")
    gy = ey - fwd * 0.64 if ey > 0.0 else ey + (0.64 if fwd > 0 else -0.52)
    gj([box("_g", (0.34, 0.62, 0.30), (0, gy, 0.40), 'alum'),
        box("_bh", (0.40, 0.26, 0.34), (0, (gy + ey) * 0.5, 0.42), 'alum')], "Gearbox")
    gj([cyl("_alt", 0.05, 0.10, (0.28, ey + 0.30, 0.45), 'Y', 'alum', seg=16),
        cyl("_ps", 0.05, 0.09, (-0.28, ey + 0.30, 0.45), 'Y', 'darksteel', seg=16)], "Accessories")
    if ey > 0.0:
        gj([box("_ab", (0.34, 0.26, 0.16), (0, 1.95, 0.70), 'carbon'),
            cyl("_scoop", 0.09, 0.2, (0, 2.02, 0.72), 'Y', 'carbon', seg=16)], "Airbox")
        add(cyl("_dst", 0.07, 0.30, (-0.58, 1.95, 0.55), 'Z', 'alum', seg=16), "DrySumpTank")
    else:
        gj([box("_ab", (0.34, 0.26, 0.10), (0, ey + 0.30, 0.78), 'carbon')], "Airbox")
        add(cyl("_dst", 0.07, 0.30, (-0.58, ey, 0.55), 'Z', 'alum', seg=16), "DrySumpTank")
    # cooling
    gj([box("_r", (1.0, 0.06, 0.42), (0, 2.00, 0.50), 'darksteel'),
        box("_ts", (1.04, 0.03, 0.05), (0, 2.00, 0.74), 'plastic'),
        box("_bs", (1.04, 0.03, 0.05), (0, 2.00, 0.27), 'plastic')], "Radiator")
    gj([box("_sh", (0.50, 0.04, 0.38), (0.0, 1.94, 0.50), 'carbon'),
        cyl("_hub", 0.04, 0.04, (0.0, 1.92, 0.50), 'Y', 'darksteel', seg=14)], "FanShroud")
    fan = [cyl("_fh", 0.045, 0.03, (0.0, 1.89, 0.50), 'Y', 'black', seg=14)]
    for k in range(7):
        b = box("_bl", (0.03, 0.012, 0.15), (0, 1.89, 0.59), 'black')
        b.data.transform(Matrix.Translation((0, -1.89, -0.50)))
        b.data.transform(Matrix.Rotation(k * 2 * pi / 7, 4, 'Y'))
        b.data.transform(Matrix.Translation((0, 1.89, 0.50)))
        fan.append(b)
    gj(fan, "Fan")
    add(tube("_h1", [(-0.45, 2.00, 0.70), (-0.38, 1.8, 0.66), (-0.20, 1.65, 0.62)], 0.028, 'black', seg=10), "RadHose_Top")
    add(tube("_h2", [(0.45, 2.00, 0.30), (0.34, 1.8, 0.34), (0.22, 1.65, 0.36)], 0.028, 'black', seg=10), "RadHose_Bottom")
    add(box("_oc", (0.34, 0.05, 0.22), (0.62, 2.08, 0.40), 'darksteel'), "OilCooler")
    # low noses: squash the cooling package (radiator, fan, shroud, cooler) under the bonnet
    from variants import top_at
    room = top_at(S["front"], 2.0) - 0.06
    k = min(1.0, (room - 0.27) / (0.765 - 0.27))
    if k < 1.0:
        for nm in ("Radiator", "FanShroud", "Fan", "OilCooler", "RadHose_Top", "RadHose_Bottom"):
            o = bpy.data.objects.get(nm)
            if o is not None:
                me = o.data
                mw = o.matrix_world.copy()
                me.transform(mw)
                me.transform(Matrix.Translation((0, 0, -0.27)))
                me.transform(Matrix.Scale(k, 4, (0, 0, 1)))
                me.transform(Matrix.Translation((0, 0, 0.27)))
                me.transform(mw.inverted())
    for sx in (-1, 1):
        s = "L" if sx < 0 else "R"
        add(cyl("_tw", 0.085, 0.14, (sx * 0.60, AXLE_F, 0.64), 'Z', 'darksteel', seg=20), f"StrutTower_{s}")
    add(box("_bat", (0.20, 0.14, 0.17), (0.0, -2.0, 0.45), 'plastic'), "Battery")
    return eb
