import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from lib import *
import body

clear()
root = empty("Car")
grp, parts, doors = body.build_body(root)
out = os.environ.get("PREVIEW_DIR", os.path.dirname(__file__))
render_views(os.path.join(out, "body"), [
    ("front34", (6.0, 6.5, 2.6), (0, 0, 0.8), 40),
    ("rear34", (-6.0, -6.5, 2.6), (0, 0, 0.8), 40),
    ("side", (9.0, 0, 1.0), (0, 0, 0.8), 40),
])
print("PARTS", len(parts), sorted(parts))
