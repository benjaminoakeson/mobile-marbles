@tool
class_name EllipseMesh
extends PrimitiveMesh
## An extruded ellipse: an oval prism with flat caps.
##
## Behaves like [CylinderMesh] but with independent X and Z radii, so it can be
## an oval platform, a squashed pillar, or a lens-shaped cutout. The surface is
## closed and watertight, which is what [CSGMesh3D] needs to boolean cleanly
## inside a [CSGCombiner3D]. Set [member radius_x] equal to [member radius_z]
## and it is just a cylinder.

@export_range(0.001, 100.0, 0.001, "or_greater", "suffix:m")
var radius_x: float = 1.0:
	set(value):
		radius_x = maxf(value, 0.001)
		request_update()

@export_range(0.001, 100.0, 0.001, "or_greater", "suffix:m")
var radius_z: float = 0.5:
	set(value):
		radius_z = maxf(value, 0.001)
		request_update()

@export_range(0.001, 100.0, 0.001, "or_greater", "suffix:m")
var height: float = 0.5:
	set(value):
		height = maxf(value, 0.001)
		request_update()

## Number of slices around the rim. Bump this up for large ovals, drop it to
## 6-12 for a faceted low-poly look.
@export_range(3, 256, 1)
var radial_segments: int = 32:
	set(value):
		radial_segments = maxi(value, 3)
		request_update()

## Horizontal subdivisions of the side wall. 1 is enough unless a shader or
## vertex lighting needs the extra density.
@export_range(1, 64, 1)
var rings: int = 1:
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

	# Side wall, built top-down so the winding matches the engine primitives.
	for j in rings + 2:
		var v := float(j) / float(rings + 1)
		var y := height * 0.5 - height * v
		for i in radial_segments + 1:
			var u := float(i) / float(radial_segments)
			var angle := u * TAU
			var sx := sin(angle)
			var sz := cos(angle)
			verts.push_back(Vector3(sx * radius_x, y, sz * radius_z))
			# Ellipse normal is the gradient of x^2/a^2 + z^2/b^2, not the position.
			normals.push_back(Vector3(sx / radius_x, 0.0, sz / radius_z).normalized())
			_push_tangent(tangents, Vector3(sz * radius_x, 0.0, -sx * radius_z).normalized(), 1.0)
			uvs.push_back(Vector2(u, v * 0.5))
			point += 1

			if i > 0 and j > 0:
				indices.append_array([
					prevrow + i - 1, prevrow + i, thisrow + i - 1,
					prevrow + i, thisrow + i, thisrow + i - 1,
				])
		prevrow = thisrow
		thisrow = point

	# Top cap.
	var top_y := height * 0.5
	thisrow = point
	verts.push_back(Vector3(0.0, top_y, 0.0))
	normals.push_back(Vector3.UP)
	_push_tangent(tangents, Vector3.RIGHT, 1.0)
	uvs.push_back(Vector2(0.25, 0.75))
	point += 1
	for i in radial_segments + 1:
		var angle := float(i) / float(radial_segments) * TAU
		var sx := sin(angle)
		var sz := cos(angle)
		verts.push_back(Vector3(sx * radius_x, top_y, sz * radius_z))
		normals.push_back(Vector3.UP)
		_push_tangent(tangents, Vector3.RIGHT, 1.0)
		uvs.push_back(Vector2((sx + 1.0) * 0.25, 0.5 + (sz + 1.0) * 0.25))
		point += 1
		if i > 0:
			indices.append_array([thisrow, point - 1, point - 2])

	# Bottom cap.
	var bottom_y := height * -0.5
	thisrow = point
	verts.push_back(Vector3(0.0, bottom_y, 0.0))
	normals.push_back(Vector3.DOWN)
	_push_tangent(tangents, Vector3.LEFT, 1.0)
	uvs.push_back(Vector2(0.75, 0.75))
	point += 1
	for i in radial_segments + 1:
		var angle := float(i) / float(radial_segments) * TAU
		var sx := sin(angle)
		var sz := cos(angle)
		verts.push_back(Vector3(sx * radius_x, bottom_y, sz * radius_z))
		normals.push_back(Vector3.DOWN)
		_push_tangent(tangents, Vector3.LEFT, 1.0)
		uvs.push_back(Vector2(0.5 + (sx + 1.0) * 0.25, 1.0 - (sz + 1.0) * 0.25))
		point += 1
		if i > 0:
			indices.append_array([thisrow, point - 2, point - 1])

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
