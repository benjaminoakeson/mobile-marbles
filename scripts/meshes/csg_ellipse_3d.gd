@tool
class_name CSGEllipse3D
extends CSGMesh3D
## A CSG oval prism, the elliptical sibling of [CSGCylinder3D].
##
## Drop it under a [CSGCombiner3D] and set the radii directly on the node — no
## mesh resource to wire up, and no non-uniform scale on the node (which CSG
## booleans handle badly). It wraps an [EllipseMesh] internally.

var _ellipse: EllipseMesh = EllipseMesh.new()

@export_range(0.001, 100.0, 0.001, "or_greater", "suffix:m")
var radius_x: float = 1.0:
	set(value):
		radius_x = maxf(value, 0.001)
		_ellipse.radius_x = radius_x

@export_range(0.001, 100.0, 0.001, "or_greater", "suffix:m")
var radius_z: float = 0.5:
	set(value):
		radius_z = maxf(value, 0.001)
		_ellipse.radius_z = radius_z

@export_range(0.001, 100.0, 0.001, "or_greater", "suffix:m")
var height: float = 0.5:
	set(value):
		height = maxf(value, 0.001)
		_ellipse.height = height

@export_range(3, 256, 1)
var radial_segments: int = 32:
	set(value):
		radial_segments = maxi(value, 3)
		_ellipse.radial_segments = radial_segments

@export_range(1, 64, 1)
var rings: int = 1:
	set(value):
		rings = maxi(value, 1)
		_ellipse.rings = rings


func _init() -> void:
	mesh = _ellipse


func _validate_property(property: Dictionary) -> void:
	# The mesh is owned by this node; showing or saving it would just let it
	# drift out of sync with the exported radii.
	if property.name == "mesh":
		property.usage = PROPERTY_USAGE_NONE
