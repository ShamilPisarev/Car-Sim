"""Build the whole sedan, save .blend, export .glb into the Godot project and render previews."""
import sys, os
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from lib import *
import body, chassis, interior
from variants import S, NAME

ROOT = os.path.dirname(HERE)
OUT_GLB = os.path.join(ROOT, "godot", "assets", S["glb"])
OUT_BLEND = os.path.join(ROOT, "exports", S["glb"].replace(".glb", ".blend"))

clear()
setup_paint_livery()
root = empty("Car", size=0.3)
susp = empty("Suspension", parent=root)
body_grp, parts, doors = body.build_body(root)
for t in ("FL", "FR", "RL", "RR"):
    chassis.build_corner(root, susp, t[1], t[0] == "F")
chassis.build_frame(root)
chassis.build_engine_bay(root)
interior.build_interior(root, doors, parts, body_grp)
interior.build_trunk_and_lights(root, parts, body_grp)
interior.build_aero_and_lights(root, parts, body_grp)
assign_livery_uvs([o for o in bpy.data.objects if o.type == 'MESH'])

# stats
nobj = len([o for o in bpy.data.objects if o.type == 'MESH'])
ntri = sum(len(o.data.polygons) for o in bpy.data.objects if o.type == 'MESH')
print("OBJS meshes:", nobj, "faces:", ntri)

os.makedirs(os.path.dirname(OUT_GLB), exist_ok=True)
os.makedirs(os.path.dirname(OUT_BLEND), exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND)
bpy.ops.export_scene.gltf(filepath=OUT_GLB, export_format='GLB', export_apply=False,
                          export_yup=True, export_extras=True, export_cameras=False,
                          export_lights=False, export_image_format='AUTO')
print("DONE exported", OUT_GLB, os.path.getsize(OUT_GLB))

prev = os.environ.get("PREVIEW_DIR")
if prev:
    render_views(os.path.join(prev, NAME + "_car"), [
        ("front34", (6.0, 6.5, 2.4), (0, 0, 0.7), 40),
        ("rear34", (-6.0, -6.5, 2.4), (0, 0, 0.7), 40),
        ("side", (9.0, 0.0, 0.9), (0, 0, 0.7), 35),
    ])
    # open everything to show the insides
    import math as _m
    for n in ("Door_FL", "Door_FR"):
        bpy.data.objects[n].rotation_euler[2] = 0.9 if n.endswith("L") else -0.9
    bpy.data.objects["Hood"].rotation_euler[0] = 0.9
    bpy.data.objects["Trunk"].rotation_euler[0] = -0.9
    render_views(os.path.join(prev, NAME + "_open"), [
        ("front34", (6.0, 6.5, 3.4), (0, 0, 0.7), 40),
        ("rear34", (-6.0, -6.5, 3.4), (0, 0, 0.7), 40),
        ("top", (0.01, 0.0, 9.5), (0, 0, 0.7), 45),
    ])
