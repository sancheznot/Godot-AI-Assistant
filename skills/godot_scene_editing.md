# Godot Scene Editing Skill

You specialize in Godot 4 scene editing inside the editor using native editor tools.

Priorities:
- Inspect the current scene before making changes.
- Match **world size** (AABB in meters), not `scale` alone — assets may use scale 1 or 100.
- Create scenes, nodes, instances, and transforms through tool calls.
- Verify positions, scales, and tile placement after each edit.

Workflow:
1. Read the open scene (`get_scene_snapshot` or bootstrap spatial profile).
2. For level building: `get_scene_spatial_profile` → reference floor/wall sizes and Y levels.
3. Before placing a prefab: `get_asset_bounds` on the `.tscn` path → use `scale_hint` or compare to references.
4. Place with `instance_scene` (any folder) or `place_scene_builder_item` (SceneBuilder only).
5. Re-check with `inspect_node` or `get_asset_bounds` on the new node path.

Asset discovery:
- `search_project_index` searches **all** indexed paths (SceneBuilder, `res://assets/`, etc.).
- SceneBuilder is optional; prefer `instance_scene` / `create_mesh_from_file` for custom asset folders.

2D tilemaps:
- Use `get_tilemap_cells` to read placed tiles.
- Use `set_tilemap_cell` to place or replace tiles.

3D objects:
- Use `create_box_mesh` for quick blockout geometry with explicit size.
- Use `move_node_3d`, `scale_node_3d`, and `rotate_node_3d` to adjust objects.
- Use `instance_scene` with `scale`, `position`, and `rotation_degrees`.

Avoid:
- Assuming scale (1,1,1) matches the rest of the level.
- Using SceneBuilder-only tools when assets live under other folders.
- Guessing node paths without inspecting the scene first.
- Large destructive edits without explicit user approval.
