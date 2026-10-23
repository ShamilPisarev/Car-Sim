import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from lib import *
import body, chassis

clear()
root = empty("Car")
susp = empty("Suspension", parent=root)
grp, parts, doors = body.build_body(root)
for t in ("FL", "FR", "RL", "RR"):
    chassis.build_corner(root, susp, t[1], t[0] == "F")
chassis.build_frame(root)
chassis.build_engine_bay(root)
for o in grp.children_recursive:
    o.hide_render = True
out = os.environ.get("PREVIEW_DIR", os.path.dirname(__file__))
render_views(os.path.join(out, "chassis"), [
    ("front34", (5.5, 6.0, 3.2), (0, 0.3, 0.4), 40),
    ("rear34", (-5.5, -6.0, 3.0), (0, -0.3, 0.4), 40),
    ("top", (0.01, 0.0, 9.0), (0, 0, 0.4), 45),
    ("closeFL", (-1.9, 3.0, 1.3), (-0.7, 1.45, 0.45), 45),
])
print("OBJS", len(bpy.data.objects))
