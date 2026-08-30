class_name MovingPart
extends AnimatableBody3D

## Base for anything that moves inside the level -- spinners, lifts,
## platforms on rails, whatever comes next.
##
## Moving a body by hand inside the level goes wrong in three ways, and this
## class exists so nobody has to remember them again:
##
## 1. `sync_to_physics` has to be OFF. A nested AnimatableBody3D with it on stops
##    inheriting its parent and drifts out of the level the moment it tilts.
##    Forced off here rather than left to each scene to get right.
##
## 2. With it off, the body no longer drags riders along -- that was the job
##    `sync_to_physics` was doing. The surface velocity has to be handed to the
##    solver instead, and this class works it out from the motion itself, so
##    subclasses never touch `constant_linear_velocity`.
##
## 3. The motion has to be CONTINUOUS. The level's placement is a rotation about
##    the ball, so a body that jumps by d lurches through roughly d * 2sin(θ/2)
##    of world space in one frame and bats the ball away. Subclasses must never
##    teleport: no snapping to a new spot, no wrapping an open path end to end.
##
## Subclasses override `_advance()` and move themselves relative to the level.

@export var motion_enabled := true

## Whether the surface drags the ball along with it.
@export var carries_riders := true

var _level: Node3D
var _last_in_level := Transform3D()


func _ready() -> void:
	# Rule 1.
	sync_to_physics = false

	_level = _find_level()
	if _level == null:
		push_warning("%s: no level body above it; motion will be measured in world space" % name)

	_last_in_level = _transform_in_level()


func _physics_process(delta: float) -> void:
	if motion_enabled:
		_advance(delta)

	var now := _transform_in_level()
	if carries_riders:
		_publish_surface_velocity(now, delta)
	else:
		constant_linear_velocity = Vector3.ZERO
		constant_angular_velocity = Vector3.ZERO

	_last_in_level = now


## Move the part here, relative to the level. Must be continuous -- see rule 3.
func _advance(_delta: float) -> void:
	pass


## This part's placement measured against the level, so a level that is moved
## or animated does not read as the part moving.
func _transform_in_level() -> Transform3D:
	if _level == null:
		return global_transform
	return _level.global_transform.affine_inverse() * global_transform


func _find_level() -> Node3D:
	var node := get_parent()
	while node != null:
		if node.has_method("rest_transform"):
			return node as Node3D
		node = node.get_parent()
	return null


## Tells the solver how fast this surface is travelling, so friction can drag a
## ball along with it.
##
## Measured against the level and then turned into world directions, so what a
## rider is told is the part's own travel and not the level's.
func _publish_surface_velocity(now: Transform3D, delta: float) -> void:
	if delta <= 0.0:
		return

	var to_world := _level.global_transform.basis if _level != null else Basis()

	constant_linear_velocity = to_world * ((now.origin - _last_in_level.origin) / delta)

	var turn := Quaternion(now.basis.orthonormalized()) \
			* Quaternion(_last_in_level.basis.orthonormalized()).inverse()
	if turn.w < 0.0:
		turn = -turn  # same rotation, shortest way round

	var angle := turn.get_angle()
	if angle < 0.000001:
		constant_angular_velocity = Vector3.ZERO
	else:
		constant_angular_velocity = to_world * (turn.get_axis() * (angle / delta))
