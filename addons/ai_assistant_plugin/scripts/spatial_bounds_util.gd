extends RefCounted

# Shared AABB helpers for index cache + editor tools / Utilidades AABB compartidas

static func has_volume(aabb: AABB) -> bool:
	return aabb.size.length_squared() > 0.000001

static func vector3_to_array(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

static func bounds_dict_from_aabb(aabb: AABB) -> Dictionary:
	return {
		"size": vector3_to_array(aabb.size),
		"center": vector3_to_array(aabb.get_center()),
	}

static func shape_local_aabb(shape: Shape3D) -> AABB:
	if shape == null:
		return AABB()
	if shape is BoxShape3D:
		var box := shape as BoxShape3D
		var half := box.size * 0.5
		return AABB(-half, box.size)
	if shape is SphereShape3D:
		var radius: float = (shape as SphereShape3D).radius
		var diameter := Vector3.ONE * radius * 2.0
		return AABB(-Vector3.ONE * radius, diameter)
	if shape is CapsuleShape3D:
		var cap := shape as CapsuleShape3D
		var r: float = cap.radius
		var h: float = cap.height
		return AABB(Vector3(-r, -h * 0.5, -r), Vector3(r * 2.0, h, r * 2.0))
	if shape is CylinderShape3D:
		var cyl := shape as CylinderShape3D
		var cr: float = cyl.radius
		var ch: float = cyl.height
		return AABB(Vector3(-cr, -ch * 0.5, -cr), Vector3(cr * 2.0, ch, cr * 2.0))
	return AABB()

static func merge_aabb(existing: AABB, has_bounds: bool, addition: AABB) -> Dictionary:
	if not has_volume(addition):
		return {"aabb": existing, "has_bounds": has_bounds}
	if not has_bounds:
		return {"aabb": addition, "has_bounds": true}
	return {"aabb": existing.merge(addition), "has_bounds": true}

static func compute_subtree_local_aabb(node: Node, parent_transform: Transform3D = Transform3D.IDENTITY) -> AABB:
	var xf := parent_transform
	if node is Node3D:
		xf = parent_transform * (node as Node3D).transform
	var merged := AABB()
	var has_bounds := false
	if node is VisualInstance3D:
		var local_aabb := (node as VisualInstance3D).get_aabb()
		var merged_result := merge_aabb(merged, has_bounds, xf * local_aabb)
		merged = merged_result["aabb"]
		has_bounds = bool(merged_result["has_bounds"])
	elif node is CollisionShape3D:
		var shape_aabb := shape_local_aabb((node as CollisionShape3D).shape)
		var collision_result := merge_aabb(merged, has_bounds, xf * shape_aabb)
		merged = collision_result["aabb"]
		has_bounds = bool(collision_result["has_bounds"])
	for child in node.get_children():
		var child_aabb := compute_subtree_local_aabb(child, xf)
		var child_result := merge_aabb(merged, has_bounds, child_aabb)
		merged = child_result["aabb"]
		has_bounds = bool(child_result["has_bounds"])
	return merged if has_bounds else AABB()

static func compute_subtree_world_aabb(node: Node3D) -> AABB:
	var result := _merge_world_aabb_recursive(node, AABB(), false)
	return result["aabb"] if bool(result["has_bounds"]) else AABB()

static func _merge_world_aabb_recursive(node: Node, merged: AABB, has_bounds: bool) -> Dictionary:
	if node is VisualInstance3D:
		var vi := node as VisualInstance3D
		var local_aabb := vi.get_aabb()
		var world_aabb := vi.global_transform * local_aabb
		var visual_result := merge_aabb(merged, has_bounds, world_aabb)
		merged = visual_result["aabb"]
		has_bounds = bool(visual_result["has_bounds"])
	elif node is CollisionShape3D and node is Node3D:
		var collision_node := node as Node3D
		var shape_aabb := shape_local_aabb((node as CollisionShape3D).shape)
		var world_collision := collision_node.global_transform * shape_aabb
		var collision_result := merge_aabb(merged, has_bounds, world_collision)
		merged = collision_result["aabb"]
		has_bounds = bool(collision_result["has_bounds"])
	for child in node.get_children():
		var child_result := _merge_world_aabb_recursive(child, merged, has_bounds)
		merged = child_result["aabb"]
		has_bounds = bool(child_result["has_bounds"])
	return {"aabb": merged, "has_bounds": has_bounds}

static func compute_from_scene_path(scene_path: String) -> Dictionary:
	if scene_path.is_empty() or not scene_path.begins_with("res://"):
		return {}
	if not FileAccess.file_exists(scene_path):
		return {}
	var packed: PackedScene = load(scene_path)
	if packed == null:
		return {}
	var temp: Node = packed.instantiate()
	var local_aabb := compute_subtree_local_aabb(temp)
	temp.free()
	if not has_volume(local_aabb):
		return {}
	return bounds_dict_from_aabb(local_aabb)
