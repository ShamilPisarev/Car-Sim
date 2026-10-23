"""Outer body of a two-door GT / race coupe: panels cut from lofted sheet-metal shells.
Coordinates: X right, Y forward, Z up. Left side = -X."""
from lib import *
from variants import S

T = 0.005            # sheet thickness
WHEEL_R = 0.34
AXLE_F, AXLE_R = 1.38, -1.37
TRACK_X = 0.83
BELT = S["belt"]     # beltline height (top of doors)
Y_COWL = S["cowl"]   # front shell / mid shell seam (hood rear edge, fender rear edge)
Y_DECK = S["deck"]   # mid shell / rear shell seam (trunk front edge)
NOSE, TAIL = S["nose"], S["tail"]
HUMP = S["hump"]     # front wings standing proud of the bonnet


def closed_section(w, zb, zt, hump=0.0):
    # every station of one shell needs the same point count, so the hump profile is
    # used along the whole front whenever the car has raised wings (even where hump = 0)
    if HUMP <= 0.0:
        pts = [(w - 0.012, zb), (w, zb + 0.10), (w, (zb + zt) / 2 - 0.02), (w * 0.985, zt - 0.05),
               (w * 0.82, zt - 0.008), (w * 0.38, zt + 0.010), (0.0, zt + 0.016)]
    else:
        # raised wing tops with the bonnet dipping between them
        pts = [(w - 0.012, zb), (w, zb + 0.10), (w, (zb + zt) / 2 - 0.02 + hump * 0.5), (w * 0.975, zt - 0.04 + hump),
               (w * 0.86, zt + hump), (w * 0.72, zt + hump * 0.55), (w * 0.55, zt + 0.004), (0.0, zt + 0.016)]
    return chaikin(pts, 2)


def side_section(w, zb):
    pts = [(w - 0.012, zb), (w, zb + 0.10), (w, 0.55), (w * 0.99, BELT - 0.07), (w * 0.965, BELT - 0.005), (0.87, BELT + 0.005)]
    return chaikin(pts, 2)


def cabin_section(zt, wb, wr):
    zt = max(zt, BELT + 0.012)
    pts = [(wb, BELT + 0.005), (wb - 0.015, (BELT + zt) / 2), (wr, zt - 0.05), (wr * 0.45, zt - 0.008), (0.0, zt)]
    return chaikin(pts, 2)


def build_shells():
    front_rows = S["front"]
    n = len(front_rows) - 1
    st = []
    for k, (y, w, zb, zt) in enumerate(catmull(front_rows, 4)):
        # wings fade into the nose so the bumper face stays a clean shape
        h = HUMP * max(0.0, min(1.0, (NOSE - 0.12 - y) / 0.35))
        st.append((y, closed_section(w, zb, zt, h)))
    front = loft("shell_front", st, 'paint', cap_last=True)

    mid_rows = S["mid"]
    st = [(y, side_section(w, zb)) for y, w, zb in catmull(mid_rows, 6)]
    mid = loft("shell_mid", st, 'paint')

    rear_rows = S["rear"]
    st = [(y, closed_section(w, zb, zt)) for y, w, zb, zt in catmull(rear_rows, 4)]
    rear = loft("shell_rear", st, 'paint', cap_last=True)

    cab_rows = S["cab"]
    st = [(y, cabin_section(zt, wb, wr)) for y, zt, wb, wr in catmull(cab_rows, 4)]
    cab = loft("shell_cabin", st, 'paint')
    for s in (front, mid, rear, cab):
        solidify(s, T)
    return front, mid, rear, cab


def arch_cutters():
    out = []
    for ay in (AXLE_F, AXLE_R):
        for sx in (-1, 1):
            out.append(cyl("_arch", 0.40, 0.46, (sx * 0.90, ay, WHEEL_R), 'X', None, seg=32))
    return out


def build_body(root):
    grp = empty("Body", parent=root)
    front, mid, rear, cab = build_shells()
    for c in arch_cutters():
        for s in (front, mid, rear):
            boolean(s, c, 'DIFFERENCE')
        delete(c)

    parts = {}

    def add(o, name, parent=None):
        o.name = name
        o.data.name = name
        reparent(o, parent or grp)
        parts[name] = o
        return o

    # ---- front end
    hb = NOSE - 0.23                     # bonnet / bumper split
    hood = slice_panel(front, "Hood", (-0.76, 0.76, Y_COWL + 0.02, hb, 0.40, 1.3), shrink=0.002)
    bump_f = slice_panel(front, "Bumper_F", (-1.2, 1.2, hb, 2.7, 0.0, 1.5))
    fl = slice_panel(front, "Fender_L", (-1.2, -0.76, Y_COWL - 0.01, hb, 0.0, 1.5))
    fr = slice_panel(front, "Fender_R", (0.76, 1.2, Y_COWL - 0.01, hb, 0.0, 1.5))
    delete(front)
    set_origin(hood, (0, Y_COWL + 0.03, BELT + 0.0))
    add(hood, "Hood")
    add(bump_f, "Bumper_F")
    add(fl, "Fender_L")
    add(fr, "Fender_R")

    # ---- doors (two big coupe doors) / sides
    doors = {}
    dy0, dy1 = S["door"]
    for side, sx in (("L", -1), ("R", 1)):
        x0, x1 = (-1.1, -0.5) if sx < 0 else (0.5, 1.1)
        d = slice_panel(mid, f"Door_F{side}", (x0, x1, dy0, dy1, 0.2, BELT + 0.05), shrink=0.002)
        set_origin(d, (sx * 0.955, Y_COWL - 0.02, 0.55))
        doors[f"F{side}"] = add(d, f"Door_F{side}")
    for side, sx in (("L", -1), ("R", 1)):
        x0, x1 = (-1.1, -0.5) if sx < 0 else (0.5, 1.1)
        cut_out(mid, (x0, x1, dy0, dy1, 0.2, BELT + 0.05), grow=0.003)
    add(mid, "Body_Sides")

    # ---- rear end
    tb = TAIL + 0.11                     # deck lid rear edge
    deck_z = max(r[3] for r in S["rear"]) - 0.10
    trunk = slice_panel(rear, "Trunk", (-0.78, 0.78, tb, Y_DECK - 0.015, deck_z - 0.20, 1.4), shrink=0.002)
    cut_out(rear, (-0.78, 0.78, tb, Y_DECK - 0.015, deck_z - 0.20, 1.4), grow=0.003)
    bump_r = slice_panel(rear, "Bumper_R", (-1.2, 1.2, -2.7, TAIL + 0.21, 0.0, 1.5))
    cut_out(rear, (-1.2, 1.2, -2.7, TAIL + 0.21, 0.0, 1.5), grow=0.0)
    set_origin(trunk, (0, Y_DECK - 0.025, deck_z + 0.06))
    add(trunk, "Trunk")
    add(bump_r, "Bumper_R")
    add(rear, "Body_Rear")

    # ---- greenhouse
    ws0, ws1 = S["windshield"]
    rg0, rg1 = S["rear_glass"]
    wind = slice_panel(cab, "Windshield", (-0.58, 0.58, ws0, ws1, BELT + 0.012, 1.5))
    rg = slice_panel(cab, "Rear_Glass", (-0.58, 0.58, rg0, rg1, BELT + 0.012, 1.5))
    cut_out(cab, (-0.58, 0.58, ws0, ws1, BELT + 0.012, 1.5))
    cut_out(cab, (-0.58, 0.58, rg0, rg1, BELT + 0.012, 1.5))
    for m_ in (wind, rg):
        m_.data.materials.clear()
        m_.data.materials.append(M('glass'))
    add(wind, "Windshield")
    add(rg, "Rear_Glass")
    for side, sx in (("L", -1), ("R", 1)):
        x0, x1 = (-1.0, -0.58) if sx < 0 else (0.58, 1.0)
        sg0, sg1 = S["side_glass"]
        top = max(r[1] for r in S["cab"]) - 0.085
        w = slice_panel(cab, f"Window_F{side}", (x0, x1, sg0, sg1, BELT + 0.02, top))
        cut_out(cab, (x0, x1, sg0, sg1, BELT + 0.02, top))
        w.data.materials.clear()
        w.data.materials.append(M('glass'))
        add(w, f"Window_F{side}", parent=doors[f"F{side}"])
    add(cab, "Roof_Pillars")
    return grp, parts, doors
