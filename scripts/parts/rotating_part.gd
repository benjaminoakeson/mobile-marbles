class_name RotatingPart
extends MovingPart

## Spins in place. Turntables, fan blades, revolving doors.

## Degrees a second. Negative spins the other way.
@export var spin_degrees := 45.0

## Axis to spin about, in the part's own space. UP spins it flat, like a
## turntable; FORWARD or RIGHT stand it up like a wheel.
@export var spin_axis := Vector3.UP

var _angle := 0.0
var _rest_basis := Basis()


func _ready() -> void:
	super()
	_rest_basis = basis


func _advance(delta: float) -> void:
	if spin_axis.is_zero_approx():
		return

	# Rebuilt from an angle rather than nudged each frame: composing rotations
	# forever skews the basis, and a skewed collider is a bad time. Wrapping at a
	# full turn keeps the number small, and is not a jump -- a full turn and none
	# at all are the same orientation.
	_angle = wrapf(_angle + deg_to_rad(spin_degrees) * delta, 0.0, TAU)
	basis = _rest_basis * Basis(spin_axis.normalized(), _angle)
