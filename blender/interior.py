"""Race cabin: bucket seats, roll cage, dash, steering wheel, pedals, door cards;
trunk with fuel/battery; lights, aero kit and small exterior parts."""
from lib import *
from body import AXLE_F, AXLE_R, BELT, Y_DECK, Y_COWL, NOSE, TAIL, HUMP
from variants import S, top_at, roof_at

FY = NOSE - 2.35          # shift of nose-mounted parts relative to the original car
RY = TAIL + 2.33          # shift of tail-mounted parts


def bucket_seat(name, x, y):
    p = [box("_base", (0.46, 0.46, 0.09), (x, y, 0.33), 'seat'),
         box("_back", (0.43, 0.10, 0.52), (x, y - 0.22, 0.62), 'seat', rot=(0.22, 'X')),
         box("_head", (0.30, 0.09, 0.26), (x, y - 0.29, 0.97), 'seat', rot=(0.22, 'X')),
         box("_rail1", (0.04, 0.42, 0.03), (x - 0.15, y, 0.27), 'darksteel'),
         box("_rail2", (0.04, 0.42, 0.03), (x + 0.15, y, 0.27), 'darksteel')]
    for s in (-1, 1):
        p.append(box("_wing", (0.07, 0.40, 0.22), (x + s * 0.22, y - 0.02, 0.45), 'seat', rot=(-0.05, 'X')))
        p.append(box("_wingb", (0.07, 0.12, 0.40), (x + s * 0.22, y - 0.22, 0.68), 'seat', rot=(0.22, 'X')))
        # harness shoulder straps
        p.append(tube("_str", [(x + s * 0.12, y - 0.25, 0.90), (x + s * 0.10, y - 0.12, 0.66), (x + s * 0.12, y + 0.06, 0.44)],
                      0.016, 'harness', seg=4))
    p.append(tube("_lap", [(x - 0.20, y - 0.05, 0.40), (x + 0.20, y - 0.05, 0.40)], 0.015, 'harness', seg=4))
    return join(p, name)


def roll_cage():
    pts = []
    t = []

    def bar(*points):
        t.append(tube("_cage", list(points), 0.022, 'cage', seg=8))

    for sx in (-1, 1):
        # A-hoop: floor -> A pillar -> roof rail -> B pillar -> floor
        bar((sx * 0.84, 0.62, 0.25), (sx * 0.70, 0.60, 0.80), (sx * 0.60, 0.40, 1.08), (sx * 0.58, -0.10, 1.13),
            (sx * 0.62, -0.50, 1.10), (sx * 0.80, -0.55, 0.25))
        # door bars
        for z in (0.44, 0.60, 0.76):
            bar((sx * 0.78, 0.60, z), (sx * 0.78, -0.50, z))
        bar((sx * 0.78, 0.60, 0.44), (sx * 0.78, -0.50, 0.76))
        bar((sx * 0.78, 0.60, 0.76), (sx * 0.78, -0.50, 0.44))
        # rear stays
        bar((sx * 0.62, -0.50, 1.10), (sx * 0.50, -1.12, 0.42))
        bar((sx * 0.80, -0.55, 0.45), (sx * 0.50, -1.12, 0.42))
        # A-pillar to dash bar
        bar((sx * 0.62, 0.55, 0.92), (sx * 0.62, 0.68, 0.60))
    # cross bars
    bar((-0.60, 0.40, 1.08), (0.60, 0.40, 1.08))
    bar((-0.62, -0.50, 1.10), (0.62, -0.50, 1.10))
    bar((-0.62, -0.50, 1.10), (0.62, -0.50, 0.30))
    bar((0.62, -0.50, 1.10), (-0.62, -0.50, 0.30))
    bar((-0.58, -0.10, 1.13), (0.58, -0.10, 1.13))
    bar((-0.70, 0.60, 0.80), (0.70, 0.60, 0.80))
    return join(t, "RollCage")


def build_interior(root, doors, parts, body_grp):
    it = empty("Interior", parent=root)

    def add(o, name, parent=None):
        o.name = name
        o.data.name = name
        reparent(o, parent or it)
        return o

    add(bucket_seat("_s", -0.38, -0.22), "Seat_FL")
    add(bucket_seat("_s", 0.38, -0.22), "Seat_FR")
    add(roll_cage(), "RollCage")

    # dash, console, drift handbrake, shifter
    dash = [box("_d1", (1.62, 0.22, 0.10), (0, 0.64, 0.74), 'carbon'),
            box("_d2", (1.62, 0.05, 0.30), (0, 0.72, 0.60), 'carbon'),
            box("_scr", (0.28, 0.02, 0.12), (-0.38, 0.52, 0.80), 'screen'),
            box("_sw", (0.34, 0.03, 0.10), (0.0, 0.54, 0.70), 'plastic')]
    for i in range(6):
        dash.append(box("_btn", (0.025, 0.015, 0.02), (-0.14 + 0.055 * i, 0.52, 0.70), 'orange' if i % 2 else 'red'))
    add(join(dash, "_dash"), "Dashboard")
    cons = [box("_c", (0.28, 1.05, 0.16), (0, 0.10, 0.34), 'carbon'),
            cyl("_sh", 0.012, 0.22, (0.0, 0.32, 0.55), 'Z', 'chrome', seg=8),
            sphere("_kn", 0.026, (0.0, 0.32, 0.67), 'black', seg=12),
            box("_hb", (0.025, 0.04, 0.24), (0.07, -0.05, 0.52), 'red', rot=(-0.35, 'X')),
            cyl("_ex", 0.045, 0.28, (0.42, 0.40, 0.40), 'Z', 'red', seg=14),
            box("_kill", (0.05, 0.03, 0.05), (0.0, 0.56, 0.60), 'red')]
    add(join(cons, "_cons"), "CenterConsole")

    # steering wheel with tilt node (flat-bottomed, quick release)
    piv = Vector((-0.38, 0.30, 0.86))
    tilt = empty("SteeringTilt", piv, parent=None)
    tilt.rotation_euler = (-0.42, 0, 0)
    reparent(tilt, it)
    ring = [Vector((0.15 * cos(a), 0, max(0.15 * sin(a), -0.115))) for a in [2 * pi * i / 32 for i in range(32)]]
    sw_parts = [tube("_ring", ring, 0.017, 'black', seg=8, closed=True),
                cyl("_hub", 0.05, 0.05, (0, 0, 0), 'Y', 'carbon', seg=18),
                box("_sp1", (0.25, 0.012, 0.03), (0, 0, 0.0), 'carbon'),
                box("_sp2", (0.03, 0.012, 0.11), (0, 0, 0.065), 'carbon'),
                box("_btn", (0.03, 0.014, 0.014), (0.06, 0.006, 0.0), 'red'),
                box("_btn2", (0.03, 0.014, 0.014), (-0.06, 0.006, 0.0), 'orange')]
    for o in sw_parts:
        o.location = (0, 0, 0)
    sw = join(sw_parts, "SteeringWheel")
    sw.parent = tilt
    sw.matrix_parent_inverse = Matrix.Identity(4)
    sw.location = (0, 0, 0)
    col = tube("SteeringColumn", [piv, (-0.38, 0.72, 0.62)], 0.027, 'carbon', seg=10)
    reparent(col, it)

    for nm, px in (("Pedal_Brake", -0.47), ("Pedal_Gas", -0.29)):
        p = box("_p", (0.07, 0.02, 0.13), (px, 0.70, 0.27), 'alum')
        pad = box("_pad", (0.08, 0.025, 0.04), (px, 0.68, 0.22), 'rubber')
        j = join([p, pad], nm)
        set_origin(j, (px, 0.70, 0.34))
        reparent(j, it)
    add(box("_foot", (0.14, 0.18, 0.02), (-0.62, 0.60, 0.26), 'alum', rot=(-0.4, 'X')), "Footrest")

    # doors: card, strap, handle, mirror, hinge blocks
    # whole cockpit moves with the cabin; low cars get a lower seat and cage
    dz = -(1.0 - S["cage_z"]) * 0.5
    for o in list(it.children):
        o.location.y += S["cab_dy"]
        if o.name == "RollCage":
            o.data.transform(Matrix.Translation((0, 0, -0.25)))
            o.data.transform(Matrix.Scale(S["cage_z"], 4, (0, 0, 1)))
            o.data.transform(Matrix.Translation((0, 0, 0.25)))
        else:
            o.location.z += dz

    dy0, dy1 = S["door"]
    dmid = (dy0 + dy1) * 0.5
    for tag, dobj in doors.items():
        side = tag[1]
        sx = -1 if side == 'L' else 1
        card = [box("_card", (0.03, dy1 - dy0 - 0.25, 0.42), (sx * 0.915, dmid, BELT - 0.22), 'carbon'),
                box("_str", (0.02, 0.18, 0.04), (sx * 0.90, dmid + 0.30, BELT - 0.10), 'harness'),
                box("_pull", (0.03, 0.14, 0.03), (sx * 0.90, dmid - 0.30, BELT - 0.04), 'alum')]
        c = join(card, f"DoorCard_{tag}")
        reparent(c, dobj)
        h = box(f"Handle_{tag}", (0.014, 0.12, 0.022), (sx * 0.985, dy0 + 0.45, BELT - 0.06), 'carbon')
        reparent(h, dobj)
        for hz, hn in ((0.40, "a"), (0.72, "b")):
            hg = box(f"Hinge_{tag}_{hn}", (0.03, 0.05, 0.08), (sx * 0.96, Y_COWL - 0.015, hz), 'darksteel')
            reparent(hg, body_grp)
        my, mz = S["mirror_y"], BELT + 0.11
        m = [box("_mh", (0.15, 0.07, 0.09), (sx * 1.03, my, mz), 'carbon'),
             tube("_st", [(sx * 0.90, my + 0.08, mz - 0.07), (sx * 0.98, my + 0.02, mz - 0.02)], 0.014, 'carbon', seg=6),
             box("_gl", (0.12, 0.012, 0.07), (sx * 1.03, my - 0.036, mz), 'glass')]
        mj = join(m, f"Mirror_{tag}")
        reparent(mj, dobj)
    return it


def build_trunk_and_lights(root, parts, body_grp):
    tr = empty("Trunk_Interior", parent=root)
    reparent(box("TrunkFloor", (1.30, 0.85, 0.012), (0, -1.88 + RY, 0.55), 'carbon'), tr)
    for sx in (-1, 1):
        wb = box("_wb", (0.10, 0.85, 0.28), (sx * 0.66, -1.88 + RY, 0.68), 'carbon')
        reparent(wb, tr)
        wb.name = "TrunkSide_" + ("L" if sx < 0 else "R")
    reparent(box("TrunkBattery", (0.22, 0.16, 0.18), (0.45, -1.80 + RY, 0.64), 'plastic'), tr)
    reparent(cyl("TrunkExtinguisher", 0.04, 0.26, (-0.45, -1.80 + RY, 0.70), 'Z', 'red', seg=12), tr)
    return tr


def build_aero_and_lights(root, parts, body_grp):
    """Front splitter, canards, hood vents, wing, diffuser, lights, plates."""
    trunk = parts["Trunk"]
    bf = parts["Bumper_F"]
    br = parts["Bumper_R"]
    bs = parts["Body_Sides"]
    # front splitter + endplates + canards
    sp = join([box("_sp", (1.90, 0.45, 0.014), (0, 2.28 + FY, 0.17), 'carbon'),
               box("_e1", (0.012, 0.45, 0.07), (-0.95, 2.28 + FY, 0.20), 'carbon'),
               box("_e2", (0.012, 0.45, 0.07), (0.95, 2.28 + FY, 0.20), 'carbon'),
               box("_lip", (1.90, 0.02, 0.04), (0, 2.50 + FY, 0.19), 'carbon')], "Splitter")
    reparent(sp, bf)
    for sx in (-1, 1):
        s = "L" if sx < 0 else "R"
        cn = join([box("_c1", (0.22, 0.12, 0.012), (sx * 0.84, 2.12 + FY, 0.36), 'carbon', rot=(sx * 0.35, 'Y')),
                   box("_c2", (0.20, 0.10, 0.012), (sx * 0.86, 2.16 + FY, 0.41), 'carbon', rot=(sx * 0.35, 'Y'))], f"Canard_{s}")
        reparent(cn, bf)
    # bumper intakes, grille mesh, headlights, lamps
    gz = min(0.44, top_at(S["front"], NOSE) - 0.05)
    gh = 0.20 if S["glb"] == "longhood.glb" else 0.12       # the long-nose car gets a big shark-mouth grille
    gr = join([box("_g1", (0.86, 0.03, gh), (0, 2.345 + FY, gz), 'black'),
               box("_g2", (0.36, 0.03, 0.08), (-0.56, 2.30 + FY, 0.33), 'black'),
               box("_g3", (0.36, 0.03, 0.08), (0.56, 2.30 + FY, 0.33), 'black')] +
              [box("_s", (0.86, 0.035, 0.006), (0, 2.346 + FY, gz - gh * 0.4 + gh * 0.25 * i), 'carbon') for i in range(4)], "Grille")
    reparent(gr, bf)
    for sx in (-1, 1):
        s = "L" if sx < 0 else "R"
        if S["lamps"] == "round":
            # upright oval lamps at the front of the raised wings, ringed by an LED halo
            ly = NOSE - 0.38
            lz = top_at(S["front"], ly) + HUMP * 0.75 - 0.045
            ring = [(sx * 0.665 + 0.085 * cos(a), ly + 0.035, lz + 0.08 * sin(a)) for a in [2 * pi * i / 16 for i in range(16)]]
            hl = join([sphere("_l", 0.095, (sx * 0.665, ly, lz), 'lamp', seg=18, scale=(1.0, 0.55, 0.95)),
                       sphere("_h", 0.105, (sx * 0.665, ly - 0.02, lz), 'chrome', seg=18, scale=(1.0, 0.5, 0.95)),
                       tube("_drl", ring, 0.008, 'ledwhite', seg=6, closed=True)], f"Headlight_{s}")
            reparent(hl, parts[f"Fender_{s}"])
        else:
            ly = 2.19 + FY
            lz = top_at(S["front"], ly) - 0.02
            hl = join([sphere("_l", 0.06, (sx * 0.64, ly, lz), 'lamp', seg=14, scale=(2.4, 0.5, 0.62)),
                       box("_drl", (0.30, 0.02, 0.014), (sx * 0.62, ly + 0.025, lz - 0.055), 'ledwhite'),
                       sphere("_h", 0.068, (sx * 0.64, ly - 0.02, lz), 'chrome', seg=14, scale=(2.5, 0.5, 0.65))], f"Headlight_{s}")
            reparent(hl, bf)
        tz = top_at(S["rear"], TAIL) + 0.06
        if S["tail_lamps"] == "full":
            # full-width light strip across the tail
            tl = join([box("_t", (0.86, 0.03, 0.05), (sx * 0.44, TAIL + 0.02, tz - 0.02), 'tail'),
                       box("_led", (0.84, 0.02, 0.010), (sx * 0.44, TAIL + 0.005, tz - 0.02), 'ledred')], f"Taillight_{s}")
        else:
            tl = join([box("_t", (0.38, 0.03, 0.06), (sx * 0.60, TAIL + 0.02, tz), 'tail'),
                       box("_led", (0.34, 0.02, 0.012), (sx * 0.60, TAIL + 0.005, tz), 'ledred')], f"Taillight_{s}")
        reparent(tl, parts["Body_Rear"])
    # hood vents and scoop, roof scoop
    vy = NOSE - 0.23 - 0.72
    vz = top_at(S["front"], vy + 0.12) + 0.015
    if S["vents"]:
        vents = [box("_v%d" % i, (0.20, 0.30, 0.006), (sx * 0.30, vy + 0.12, vz - 0.015), 'black') for i, sx in enumerate((-1, 1))]
        for sx in (-1, 1):
            for k in range(5):
                vents.append(box("_sl", (0.20, 0.012, 0.025), (sx * 0.30, vy + 0.06 * k, vz), 'carbon', rot=(0.3, 'X')))
        reparent(join(vents, "HoodVents"), parts["Hood"])
    if S["scoop"]:
        roof_scoop = join([box("_rs", (0.30, 0.34, 0.07), (0, 0.20, 1.18), 'carbon'),
                           box("_rs2", (0.26, 0.04, 0.05), (0, 0.38, 1.17), 'black')], "RoofScoop")
        reparent(roof_scoop, parts["Roof_Pillars"])
    # side skirts
    for sx in (-1, 1):
        s = "L" if sx < 0 else "R"
        sk = box(f"SideSkirt_{s}", (0.06, 2.1, 0.07), (sx * 0.985, -0.02, 0.255), 'carbon')
        reparent(sk, body_grp)
    # rear wing: airfoil, endplates, uprights, gurney flap
    prof = [(0.02, 0.012), (-0.02, 0.028), (-0.10, 0.036), (-0.20, 0.022), (-0.28, 0.008), (-0.29, -0.004),
            (-0.20, -0.010), (-0.10, -0.016), (0.0, -0.014), (0.045, -0.002)]
    cy, cz, span = S["wing"]
    prof = [(cy + y, cz + z) for y, z in prof]
    wing = airfoil("_w", [(y, z) for y, z in prof], -span, span, 'carbon')
    flap = box("_gf", (span * 2.0, 0.008, 0.035), (0, cy - 0.285, cz + 0.02), 'carbon')
    plates = [box("_p1", (0.012, 0.42, 0.20), (-span - 0.01, cy - 0.12, cz + 0.02), 'carbon'),
              box("_p2", (0.012, 0.42, 0.20), (span + 0.01, cy - 0.12, cz + 0.02), 'carbon')]
    base_y = cy + 0.12
    base_z = top_at(S["rear"], base_y) - 0.03
    if S["lamps"] == "round":
        # swan-neck mounts: rise behind the wing and hang it from the top surface
        ups = [tube("_u%d" % i, [(sx * 0.42, base_y + 0.10, base_z), (sx * 0.42, cy + 0.02, cz + 0.10),
                                 (sx * 0.42, cy - 0.12, cz + 0.035)], 0.022, 'carbon', seg=8)
               for i, sx in enumerate((-1, 1))]
    else:
        ups = [tube("_u%d" % i, [(sx * 0.50, base_y, base_z), (sx * 0.50, cy - 0.10, cz - 0.02)], 0.022, 'carbon', seg=8)
               for i, sx in enumerate((-1, 1))]
    wing_all = join([wing, flap] + plates + ups, "RearWing")
    reparent(wing_all, trunk)
    # diffuser with strakes
    dif = [box("_df", (1.40, 0.55, 0.012), (0, -2.12 + RY, 0.20), 'carbon', rot=(0.18, 'X'))]
    for i in range(5):
        dif.append(box("_st", (0.012, 0.55, 0.10), (-0.55 + 0.275 * i, -2.12 + RY, 0.24), 'carbon', rot=(0.18, 'X')))
    reparent(join(dif, "Diffuser"), br)
    # plates / numbers
    reparent(box("Plate_F", (0.46, 0.012, 0.10), (0, 2.355 + FY, 0.26), 'plate'), bf)
    reparent(box("TowHook", (0.04, 0.06, 0.04), (0.5, 2.36 + FY, 0.31), 'red'), bf)
    reparent(box("TowHookR", (0.04, 0.06, 0.04), (-0.5, -2.34 + RY, 0.34), 'red'), br)
    # race numbers
    for sx in (-1, 1):
        s = "L" if sx < 0 else "R"
        n = text_mesh(f"Number_{s}", "7", 0.30, 'black')
        n.data.transform(Matrix.Rotation(pi / 2, 4, 'Y' if sx > 0 else 'Y'))
        n.data.transform(Matrix.Rotation(pi / 2 if sx > 0 else -pi / 2, 4, 'X') if False else Matrix.Identity(4))
        # text lies in XY looking +Z; stand it up on the door facing outwards
        n.data.transform(Matrix.Identity(4))
        n.rotation_euler = (0, 0, 0)
        # rotate mesh so text faces sideways: rotate about Z then X
        me = n.data
        me.transform(Matrix.Rotation(pi / 2, 4, 'X'))          # now in XZ plane facing -Y
        me.transform(Matrix.Rotation(-pi / 2 if sx > 0 else pi / 2, 4, 'Z'))  # face +X / -X
        me.transform(Matrix.Translation((sx * 0.9835, (S["door"][0] + S["door"][1]) * 0.5, BELT - 0.20)))
        reparent(n, parts[f"Door_F{s}"])
    hn = text_mesh("Number_Hood", "7", 0.34, 'black')
    hy = NOSE - 1.0
    hn.data.transform(Matrix.Translation((0, hy, top_at(S["front"], hy) - 0.775 + 0.018)))
    hn.data.transform(Matrix.Translation((0, 0, 0.0)))
    # hood number lies flat: mesh is in XY plane facing +Z already; lift it onto the hood
    hn.data.transform(Matrix.Translation((0, 0, 0.775)))
    reparent(hn, parts["Hood"])
    return None
