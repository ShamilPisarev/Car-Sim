"""Body specs for the car line-up. All cars share the chassis (wheelbase 2.75 m, track,
suspension hardpoints) so the physics stays the same; the shells, glass, lights, wing and
cabin position differ. Shapes are loosely modelled on current GT3 race cars (proportions
only, no brand features). Choose one with the CAR_VARIANT environment variable.

Rows: front/rear (y, half width, bottom z, top-centre z), mid (y, half width, bottom z),
cabin (y, roof z, half width at belt, half width at roof). Blender axes: Y forward, Z up."""
import os

SPECS = {
    # front-engined GT coupe (the original car)
    "gt": dict(
        exhaust=(0.24, 0.27),
        engine_y=1.42,
        glb="sedan.glb", nose=2.35, tail=-2.33, cowl=0.75, deck=-1.45, belt=0.84, hump=0.0,
        door=(-0.80, None),
        front=[(0.75, .975, .24, .84), (1.15, .975, .24, .80), (1.55, .965, .24, .74),
               (1.95, .94, .24, .68), (2.15, .90, .25, .62), (2.27, .85, .26, .56), (2.35, .76, .30, .46)],
        mid=[(0.75, .975, .25), (-0.2, .975, .25), (-1.0, .975, .25), (-1.45, .965, .25)],
        rear=[(-1.45, .965, .25, .86), (-1.7, .96, .26, .90), (-1.95, .94, .27, .90),
              (-2.15, .91, .28, .87), (-2.26, .86, .29, .82), (-2.33, .78, .32, .70)],
        cab=[(0.68, 0.85, .80, .66), (0.52, 0.96, .82, .64), (0.30, 1.07, .83, .63), (0.05, 1.16, .83, .62),
             (-0.30, 1.215, .83, .61), (-0.70, 1.20, .83, .61), (-0.98, 1.15, .83, .63),
             (-1.22, 1.04, .82, .66), (-1.40, 0.92, .80, .70), (-1.47, 0.86, .78, .72)],
        windshield=(0.06, 0.74), rear_glass=(-1.6, -0.88), side_glass=(-0.76, 0.56),
        cab_dy=0.0, cage_z=1.0, lamps="slim", tail_lamps="bar", wing=(-2.12, 1.20, 0.88), mirror_y=0.52,
        scoop=True, vents=True,
    ),
    # rear-engined fastback: sloping short nose between raised fenders, round lamps,
    # roof running in one curve down to the tail, wide hips, tall swan-neck wing
    "fastback": dict(
        exhaust=(0.1, 0.28),
        engine_y=-1.80,
        glb="fastback.glb", nose=2.33, tail=-2.31, cowl=0.80, deck=-1.72, belt=0.82, hump=0.085,
        door=(-0.80, None),
        front=[(0.80, .955, .24, .82), (1.15, .96, .24, .745), (1.55, .955, .25, .64),
               (1.92, .935, .26, .57), (2.13, .90, .27, .52), (2.26, .84, .28, .47), (2.33, .74, .31, .41)],
        mid=[(0.80, .965, .25), (-0.2, .975, .25), (-1.0, .995, .25), (-1.72, 1.01, .25)],
        rear=[(-1.72, 1.01, .25, .90), (-1.92, 1.015, .26, .86), (-2.08, 1.0, .27, .81),
              (-2.20, .97, .28, .75), (-2.27, .92, .30, .69), (-2.31, .82, .33, .61)],
        cab=[(0.72, 0.84, .79, .66), (0.55, 0.97, .81, .64), (0.32, 1.09, .82, .63), (0.05, 1.185, .82, .62),
             (-0.30, 1.235, .82, .61), (-0.70, 1.20, .83, .60), (-1.00, 1.125, .84, .60),
             (-1.25, 1.035, .85, .62), (-1.50, 0.955, .86, .64), (-1.74, 0.90, .86, .66)],
        windshield=(0.10, 0.78), rear_glass=(-1.62, -0.98), side_glass=(-0.72, 0.60),
        cab_dy=0.0, cage_z=1.0, lamps="round", tail_lamps="full", wing=(-2.02, 1.30, 0.92), mirror_y=0.56,
        scoop=False, vents=False,
    ),
    # long-bonnet front-mid V8: cabin pushed far back, tall shark nose, short high tail
    "longhood": dict(
        exhaust=(0.34, 0.25),
        engine_y=1.3,
        glb="longhood.glb", nose=2.40, tail=-2.32, cowl=0.45, deck=-1.60, belt=0.86, hump=0.0,
        door=(-1.08, None),
        front=[(0.45, .975, .24, .86), (0.95, .98, .24, .85), (1.45, .975, .24, .82),
               (1.90, .955, .25, .77), (2.15, .92, .26, .72), (2.31, .86, .28, .65), (2.40, .78, .31, .57)],
        mid=[(0.45, .975, .25), (-0.4, .975, .25), (-1.1, .975, .25), (-1.60, .97, .25)],
        rear=[(-1.60, .97, .25, .91), (-1.82, .965, .26, .95), (-2.02, .95, .27, .955),
              (-2.18, .92, .28, .93), (-2.27, .87, .30, .86), (-2.32, .78, .33, .74)],
        cab=[(0.38, 0.88, .84, .66), (0.22, 0.98, .85, .64), (0.0, 1.09, .86, .63), (-0.25, 1.165, .86, .62),
             (-0.60, 1.20, .86, .61), (-0.98, 1.17, .86, .62), (-1.26, 1.09, .85, .65),
             (-1.46, 0.99, .84, .69), (-1.62, 0.93, .82, .72)],
        windshield=(-0.22, 0.46), rear_glass=(-1.72, -1.14), side_glass=(-1.04, 0.26),
        cab_dy=-0.30, cage_z=1.0, lamps="slim", tail_lamps="bar", wing=(-2.08, 1.24, 0.90), mirror_y=0.24,
        scoop=False, vents=True,
    ),
    # mid-engined: very low, cab-forward, short nose with proud front wings, long engine deck
    "midship": dict(
        exhaust=(0.15, 0.28),
        engine_y=-1.45,
        glb="midship.glb", nose=2.32, tail=-2.33, cowl=0.95, deck=-1.15, belt=0.76, hump=0.07,
        door=(-0.55, None),
        front=[(0.95, .97, .22, .76), (1.30, .97, .22, .675), (1.70, .955, .23, .585),
               (2.00, .925, .24, .525), (2.20, .875, .25, .465), (2.32, .78, .28, .40)],
        mid=[(0.95, .975, .24), (0.2, .975, .24), (-0.6, .985, .24), (-1.15, .99, .24)],
        rear=[(-1.15, .99, .24, .86), (-1.50, 1.0, .25, .875), (-1.85, .995, .26, .86),
              (-2.10, .965, .27, .82), (-2.25, .91, .29, .76), (-2.33, .81, .32, .66)],
        cab=[(0.90, 0.78, .74, .66), (0.72, 0.90, .76, .63), (0.50, 1.00, .77, .62), (0.20, 1.065, .77, .61),
             (-0.20, 1.075, .78, .60), (-0.55, 1.035, .79, .62), (-0.80, 0.97, .80, .66),
             (-1.00, 0.905, .80, .70), (-1.17, 0.87, .79, .72)],
        windshield=(0.12, 0.92), rear_glass=(-1.06, -0.66), side_glass=(-0.48, 0.74),
        cab_dy=0.20, cage_z=0.88, lamps="slim", tail_lamps="full", wing=(-2.14, 1.10, 0.94), mirror_y=0.70,
        scoop=False, vents=True,
    ),
}

NAME = os.environ.get("CAR_VARIANT", "gt")
S = SPECS[NAME]
if S["door"][1] is None:
    S["door"] = (S["door"][0], S["cowl"] - 0.02)


def top_at(rows, y):
    """Centre-line top height of a front/rear row table at y (linear between rows)."""
    rs = sorted(rows, key=lambda r: r[0])
    if y <= rs[0][0]:
        return rs[0][3]
    for a, b in zip(rs[:-1], rs[1:]):
        if a[0] <= y <= b[0]:
            t = (y - a[0]) / (b[0] - a[0])
            return a[3] + (b[3] - a[3]) * t
    return rs[-1][3]


def roof_at(y):
    rs = sorted(S["cab"], key=lambda r: r[0])
    for a, b in zip(rs[:-1], rs[1:]):
        if a[0] <= y <= b[0]:
            t = (y - a[0]) / (b[0] - a[0])
            return a[1] + (b[1] - a[1]) * t
    return rs[0][1] if y < rs[0][0] else rs[-1][1]
