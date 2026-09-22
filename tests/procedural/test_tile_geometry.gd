extends SceneTree
## Check mesh surfaces, not only unique GridMap cell coordinates.

const EPS := 0.0001
var failures := 0
var checks := 0


func _initialize() -> void:
	var library := load("res://assets/grid_map/forest_procedural_library.tres") as MeshLibrary

	for id in library.get_item_list():
		var name := library.get_item_name(id)
		var mesh := library.get_item_mesh(id)
		if name.begins_with("cliff_"):
			_check_wall(mesh, int(name.trim_prefix("cliff_")), name)
		elif name.begins_with("path_") or name.begins_with("floor_ground_"):
			var triangles: Array[PackedVector2Array] = []

			for face in _faces(mesh):
				var projected := PackedVector2Array()

				for vertex in face:
					_check(absf(vertex.y - 1.0) < EPS, name + " floor height")
					projected.append(Vector2(vertex.x, vertex.z))

				triangles.append(projected)

			_check_surface(triangles, name)
		elif name in ["stair_small_left", "stair_small_right"]:
			var seam := 1.0 if name.ends_with("left") else -1.0

			for face in _faces(mesh):
				_check(
					not (
						absf(face[0].x - seam) < EPS
						and absf(face[1].x - seam) < EPS
						and absf(face[2].x - seam) < EPS
					),
					name + " has no internal joining face"
				)

	print("Tile geometry: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _check_wall(mesh: Mesh, mask: int, label: String) -> void:
	var sides := [[], [], [], []]
	var outward := [Vector3.FORWARD, Vector3.RIGHT, Vector3.BACK, Vector3.LEFT]

	for face in _faces(mesh):
		var side := -1

		for direction in range(4):
			var normal: Vector3 = outward[direction]
			if (
				absf(face[0].dot(normal) - 1.0) < EPS
				and absf(face[1].dot(normal) - 1.0) < EPS
				and absf(face[2].dot(normal) - 1.0) < EPS
			):
				side = direction

		_check(
			side >= 0 and (mask & (1 << side)) != 0,
			label + " face lies only on an exposed cell boundary"
		)
		if side < 0:
			continue

		var projected := PackedVector2Array()

		for vertex in face:
			projected.append(Vector2(vertex.x if side % 2 == 0 else vertex.z, vertex.y))

		sides[side].append(projected)

	for side in range(4):
		if mask & (1 << side):
			_check_surface(sides[side], "%s side %d" % [label, side])


func _check_surface(triangles: Array, label: String) -> void:
	var area := 0.0
	var overlap := 0.0

	for i in range(triangles.size()):
		var triangle: PackedVector2Array = triangles[i]
		area += _area(triangle)

		for point in triangle:
			_check(
				absf(point.x) <= 1.0 + EPS and absf(point.y) <= 1.0 + EPS,
				label + " stays inside cell"
			)

		for j in range(i):
			for intersection in Geometry2D.intersect_polygons(triangle, triangles[j]):
				overlap += _area(intersection)

	_check(absf(area - 4.0) < EPS, label + " covers exactly one 2x2 face")
	_check(overlap < EPS, label + " triangles do not overlap")


func _area(polygon: PackedVector2Array) -> float:
	var area := 0.0

	for i in range(polygon.size()):
		area += polygon[i].cross(polygon[(i + 1) % polygon.size()])

	return absf(area) * 0.5


func _faces(mesh: Mesh) -> Array[PackedVector3Array]:
	var result: Array[PackedVector3Array] = []

	for surface in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = (
			arrays[Mesh.ARRAY_INDEX]
			if arrays[Mesh.ARRAY_INDEX] != null
			else PackedInt32Array(range(vertices.size()))
		)

		for i in range(0, indices.size(), 3):
			result.append(
				PackedVector3Array(
					[vertices[indices[i]], vertices[indices[i + 1]], vertices[indices[i + 2]]]
				)
			)

	return result


func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		if failures <= 12:
			printerr("FAIL: ", message)
