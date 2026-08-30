@tool
class_name TriangularPyramidMesh
extends PrimitiveMesh
## A tetrahedron: 4 flat faces (a triangular base and 3 triangular sides).
##
## Shares its base with [TriangularPrismMesh] — same triangle, tapered to a
## point instead of extruded. Good for spikes, corner fills and chiselled
## cutouts. Closed and watertight, so [CSGMesh3D] booleans it cleanly inside a
## [CSGCombiner3D]. See [CSGTriangularPyramid3D] for the ready-made CSG node.

@export var size: Vector3 = Vector3.ONE:
	set(value):
		size = Vector3(maxf(value.x, 0.001), maxf(value.y, 0.001), maxf(value.z, 0.001))
		request_update()

## Slides the base triangle's far corner along X. 0 is isosceles; -1 and 1 put
## the corner directly over an end of the base.
@export_range(-1.0, 1.0, 0.001, "or_greater", "or_less")
var apex_offset: float = 0.0:
	set(value):
		apex_offset = value
		request_update()

## Moves the tip across the base, as a fraction of the half-extents. Zero puts
## it straight above the centre; push it out to lean the spike over.
@export var tip_offset: Vector2 = Vector2.ZERO:
	set(value):
		tip_offset = value
		request_update()


func _create_mesh_array() -> Array:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var tangents := PackedFloat32Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	var half := size * 0.5
	var base_ring: Array[Vector3] = [
		Vector3(-half.x, -half.y, -half.z),
		Vector3(half.x, -half.y, -half.z),
		Vector3(apex_offset * half.x, -half.y, half.z),
	]
	var tip := Vector3(tip_offset.x * half.x, half.y, tip_offset.y * half.z)

	# Base, wound to face -Y.
	_add_face(verts, normals, tangents, uvs, indices, base_ring[0], base_ring[1], base_ring[2])

	# Sides. Walking the base edges in that same order keeps the solid on the
	# inside, so each edge lifted to the tip faces outward.
	for i in 3:
		var j := (i + 1) % 3
		_add_face(verts, normals, tangents, uvs, indices, base_ring[i], tip, base_ring[j])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays


## Emits a flat triangle. Points are given counter-clockwise as seen from
## outside the solid; the indices are reversed on the way out because Godot's
## front faces are wound opposite the right-hand normal.
func _add_face(verts: PackedVector3Array, normals: PackedVector3Array,
		tangents: PackedFloat32Array, uvs: PackedVector2Array, indices: PackedInt32Array,
		p0: Vector3, p1: Vector3, p2: Vector3) -> void:
	var base := verts.size()
	if not _push_planar(verts, normals, tangents, uvs, [p0, p1, p2]):
		return
	indices.append_array([base, base + 2, base + 1])


## Writes one flat polygon's vertices with a shared face normal and a
## metre-scaled planar UV projection. Returns false for a degenerate face.
func _push_planar(verts: PackedVector3Array, normals: PackedVector3Array,
		tangents: PackedFloat32Array, uvs: PackedVector2Array, points: Array) -> bool:
	var edge_u: Vector3 = points[1] - points[0]
	var edge_v: Vector3 = points[points.size() - 1] - points[0]
	var normal := edge_u.cross(edge_v)
	if normal.length_squared() < 1e-16 or edge_u.length_squared() < 1e-16:
		return false
	normal = normal.normalized()
	var tangent := edge_u.normalized()
	var bitangent := normal.cross(tangent)
	for p in points:
		var d: Vector3 = p - points[0]
		verts.push_back(p)
		normals.push_back(normal)
		uvs.push_back(Vector2(d.dot(tangent), -d.dot(bitangent)))
		tangents.push_back(tangent.x)
		tangents.push_back(tangent.y)
		tangents.push_back(tangent.z)
		# V runs against the bitangent, so the binormal sign is negative.
		tangents.push_back(-1.0)
	return true
