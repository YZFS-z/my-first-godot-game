extends SceneTree
## 探查 AH-64 glb 节点树结构，确认 MainRotorPivot/MainRotor 父子关系和 Turret1 位置

func _init():
	var gltf = GLTFDocument.new()
	var state = GLTFState.new()
	var err = gltf.append_from_file("res://assets/models/ah64_helicopter.glb", state, 0, "")
	if err != OK:
		print("Error loading GLB: ", err)
		quit()
		return
	var scene = gltf.generate_scene(state)
	if not scene:
		print("Failed to generate scene")
		quit()
		return

	print("=== AH-64 glb Node Tree ===")
	_print_tree(scene, 0)

	# 检查 MainRotorPivot 是否存在
	var mrp = scene.find_child("MainRotorPivot", true, false)
	print("\n=== MainRotorPivot exists: ", mrp != null)

	var mr = scene.find_child("MainRotor", true, false)
	print("=== MainRotor exists: ", mr != null)

	if mrp and mr:
		var parent = mr.get_parent()
		print("=== MainRotor parent: ", parent.name if parent else "null")
		print("=== MainRotor is child of MainRotorPivot: ", parent == mrp)

	if mr and mr is MeshInstance3D and mr.mesh:
		var aabb = (mr as MeshInstance3D).get_aabb()
		print("=== MainRotor AABB: ", aabb)
		print("=== MainRotor AABB center: ", aabb.get_center())

	# 检查 Turret1
	var t1 = scene.find_child("Turret1", true, false)
	print("\n=== Turret1 exists: ", t1 != null)
	if t1:
		print("=== Turret1 class: ", t1.get_class())
		if t1 is Node3D:
			print("=== Turret1 position: ", (t1 as Node3D).position)
		if t1 is MeshInstance3D and t1.mesh:
			var aabb = (t1 as MeshInstance3D).get_aabb()
			print("=== Turret1 AABB: ", aabb)
			print("=== Turret1 AABB center: ", aabb.get_center())

	# 检查 Turret2
	var t2 = scene.find_child("Turret2", true, false)
	print("\n=== Turret2 exists: ", t2 != null)
	if t2:
		print("=== Turret2 class: ", t2.get_class())

	quit()

func _print_tree(node: Node, depth: int):
	var prefix = ""
	for i in depth:
		prefix += "  "
	var info = prefix + str(node.name) + " (" + node.get_class() + ")"
	if node is Node3D:
		var n = node as Node3D
		info += " pos=" + str(n.position) + " rot=" + str(n.rotation) + " scale=" + str(n.scale)
	if node is MeshInstance3D:
		var mi = node as MeshInstance3D
		if mi.mesh:
			info += "\n" + prefix + "  -> AABB=" + str(mi.get_aabb())
	print(info)
	for child in node.get_children():
		_print_tree(child, depth + 1)
