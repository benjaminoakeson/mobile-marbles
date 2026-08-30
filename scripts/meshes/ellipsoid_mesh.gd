@tool
class_name EllipsoidMesh
extends PrimitiveMesh
## A sphere with an independent radius on each axis.
##
## The 3D counterpart to [EllipseMesh]: use it for domes, egg shapes, squashed
## boulders, or as a rounded cutout in a [CSGCombiner3D]. The poles are stitched
## as real triangle fans rather than degenerate quads, so the surface stays
## watertight for [CSGMesh3D].

@export_range(0.001, 100.0, 0.001, "or_greater", "suffix:m")
var radius_x: float = 1.0:
	set(value):
		radius_x = maxf(value, 0.001)
		request_update()

@export_range(0.001, 100.0, 0.001, "or_greater", "suffix:m")
var radius_y: float = 0.5:
	set(value):
		radius_y = maxf(value, 0.001)
		request_update()

@export_range(0.001, 100.0, 0.001, "or_greater", "suffix:m")
var radius_z: float = 1.0:
	set(value):
		radius_z = maxf(value, 0.001)
		request_update()

## Number of slices around the Y axis.
@export_range(3, 256, 1)
var radial_segments: int = 32:
	set(value):
		radial_segments = maxi(value, 3)
		request_update()

## Number of horizontal bands between the two poles.
@export_range(1, 256, 1)
var rings: int = 16:
	set(value):
		rings = maxi(value, 1)
		request_update()


func _create_mesh_array() -> Array:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var tangents := PackedFloat32Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	var point := 0
	var thisrow := 0
	var prevrow := 0
	var last_row := rings + 1

	for j in rings + 2:
		var v := float(j) / float(rings + 1)
		var band := sin(PI * v)
		var y := radius_y * cos(PI * v)
		for i in radial_segments + 1:
			var u := float(i) / float(radial_segments)
			var angle := u * TAU
			var sx := sin(angle)
			var sz := cos(angle)
			var p := Vector3(sx * band * radius_x, y, sz * band * radius_z)
			verts.push_back(p)
			# Gradient of x^2/a^2 + y^2/b^2 + z^2/c^2 gives the true ellipsoid normal.
			normals.push_back(Vector3(
				p.x / (radius_x * radius_x),
				p.y / (radius_y * radius_y),
				p.z / (radius_z * radius_z)).normalized())
			_push_tangent(tangents, Vector3(sz * radius_x, 0.0, -sx * radius_z).normalized(), 1.0)
			uvs.push_back(Vector2(u, v))
			point += 1

			if i > 0 and j > 0:
				# The pole rows collapse to a single position, so emit a fan there
				# instead of a quad with a zero-area half.
				if j == 1:
					indices.append_array([prevrow + i - 1, thisrow + i, thisrow + i - 1])
				elif j == last_row:
					indices.append_array([prevrow + i - 1, prevrow + i, thisrow + i - 1])
				else:
					indices.append_array([
						prevrow + i - 1, prevrow + i, thisrow + i - 1,
						prevrow + i, thisrow + i, thisrow + i - 1,
					])
		prevrow = thisrow
		thisrow = point

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays


func _push_tangent(tangents: PackedFloat32Array, tangent: Vector3, binormal_sign: float) -> void:
	tangents.push_back(tangent.x)
	tangents.push_back(tangent.y)
	tangents.push_back(tangent.z)
	tangents.push_back(binormal_sign)
