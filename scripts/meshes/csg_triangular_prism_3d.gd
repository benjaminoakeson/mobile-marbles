@tool
class_name CSGTriangularPrism3D
extends CSGMesh3D
## A CSG triangular prism — 5 faces, wrapping [TriangularPrismMesh].
##
## Drop it under a [CSGCombiner3D] alongside [CSGBox3D] and [CSGEllipse3D]. Set
## the shape with [member size] rather than the node's scale, which CSG booleans
## handle badly. Rotate -90 degrees on X for a ramp.

var _prism: TriangularPrismMesh = TriangularPrismMesh.new()

@export var size: Vector3 = Vector3.ONE:
	set(value):
		size = Vector3(maxf(value.x, 0.001), maxf(value.y, 0.001), maxf(value.z, 0.001))
		_prism.size = size

@export_range(-1.0, 1.0, 0.001, "or_greater", "or_less")
var apex_offset: float = 0.0:
	set(value):
		apex_offset = value
		_prism.apex_offset = apex_offset


func _init() -> void:
	mesh = _prism


func _validate_property(property: Dictionary) -> void:
	# The mesh is owned by this node; showing or saving it would just let it
	# drift out of sync with the exported shape.
	if property.name == "mesh":
		property.usage = PROPERTY_USAGE_NONE
