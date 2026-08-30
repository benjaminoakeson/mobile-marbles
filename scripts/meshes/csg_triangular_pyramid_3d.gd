@tool
class_name CSGTriangularPyramid3D
extends CSGMesh3D
## A CSG tetrahedron — 4 faces, wrapping [TriangularPyramidMesh].
##
## Drop it under a [CSGCombiner3D] for spikes, corner fills and chiselled
## cutouts. Set the shape with [member size] rather than the node's scale, which
## CSG booleans handle badly.

var _pyramid: TriangularPyramidMesh = TriangularPyramidMesh.new()

@export var size: Vector3 = Vector3.ONE:
	set(value):
		size = Vector3(maxf(value.x, 0.001), maxf(value.y, 0.001), maxf(value.z, 0.001))
		_pyramid.size = size

@export_range(-1.0, 1.0, 0.001, "or_greater", "or_less")
var apex_offset: float = 0.0:
	set(value):
		apex_offset = value
		_pyramid.apex_offset = apex_offset

@export var tip_offset: Vector2 = Vector2.ZERO:
	set(value):
		tip_offset = value
		_pyramid.tip_offset = tip_offset


func _init() -> void:
	mesh = _pyramid


func _validate_property(property: Dictionary) -> void:
	if property.name == "mesh":
		property.usage = PROPERTY_USAGE_NONE
