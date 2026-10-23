extends SceneTree

func dump(n: Node, depth: int, out: Array) -> void:
	var line := "  ".repeat(depth) + n.name + " [" + n.get_class() + "]"
	if n is Node3D:
		line += " pos=" + str((n as Node3D).position.snapped(Vector3(0.001, 0.001, 0.001)))
	out.append(line)
	for c in n.get_children():
		dump(c, depth + 1, out)

func _init() -> void:
	var ps: PackedScene = load("res://assets/cutlass.glb")
	var root := ps.instantiate()
	var out := []
	dump(root, 0, out)
	var mats := {}
	for m in root.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var mt := mi.mesh.surface_get_material(i)
			if mt is BaseMaterial3D:
				mats[mt.resource_name] = (mt as BaseMaterial3D).transparency
	var f := FileAccess.open("res://inspect_out.txt", FileAccess.WRITE)
	f.store_string("\n".join(out) + "\nMATS " + str(mats) + "\n")
	f.close()
	quit()
