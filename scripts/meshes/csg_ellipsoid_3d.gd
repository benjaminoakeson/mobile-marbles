@tool
class_name CSGEllipsoid3D
extends CSGMesh3D
## A CSG sphere with an independent radius per axis, wrapping [EllipsoidMesh].
##
## Use it under a [CSGCombiner3D] for domes, boulders and rounded cutouts,
## instead of putting a non-uniform scale on a [CSGSphere3D].

var _ellipsoid: EllipsoidMesh = EllipsoidMesh.new()

@export_range(0.001, 100.0, 0.001, "or_greater", "suffix:m")
var radius_x: float = 1.0:
	set(value):
		radius_x = maxf(value, 0.001)
		_ellipsoid.radius_x = radius_x

@export_range(0.001, 100.0, 0.001, "or_greater", "suffix:m")
var radius_y: float = 0.5:
	set(value):
		radius_y = maxf(value, 0.001)
		_ellipsoid.radius_y = radius_y

@export_range(0.001, 100.0, 0.001, "or_greater", "suffix:m")
var radius_z: float = 1.0:
	set(value):
		radius_z = maxf(value, 0.001)
		_ellipsoid.radius_z = radius_z

@export_range(3, 256, 1)
var radial_segments: int = 32:
	set(value):
		radial_segments = maxi(value, 3)
		_ellipsoid.radial_segments = radial_segments

@export_range(1, 256, 1)
var rings: int = 16:
	set(value):
		rings = maxi(value, 1)
		_ellipsoid.rings = rings


func _init() -> void:
	mesh = _ellipsoid


func _validate_property(property: Dictionary) -> void:
	if property.name == "mesh":
		property.usage = PROPERTY_USAGE_NONE
