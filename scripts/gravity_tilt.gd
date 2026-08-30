class_name GravityTilt
extends StaticBody3D

## The level stands still and GRAVITY leans instead.
##
## Steering used to swing the whole stage about the ball's contact point, with
## the world holding still. This does the same job from the other side: the stage
## is bolted down, and the pull on everything standing on it is what tips --
## towards wherever the stick is pushed, up to [member max_lean_degrees].
##
## The two are the same physics, which is why the game plays as it did. A floor
## tilted by an angle under straight-down gravity, and a flat floor under gravity
## leaned by that same angle, both hand the ball `g * sin(angle)` along the floor
## and `g * cos(angle)` into it. Nothing the ball does can tell them apart. What
## changes is only what the player sees: the horizon stays put and the ball is
## pulled about, rather than the whole world rolling under it.
##
## Almost everything the old version needed is gone with it. There is no pivot to
## chase, so nothing has to be capped to stop the geometry sweeping past the ball
## between two ticks; no swinging origin, so a point on the level means the same
## thing every tick; and the body is a plain [StaticBody3D] rather than an
## animatable one, which takes the `sync_to_physics` trap off the table for good
## -- there is no longer anything here that moves for it to catch. This node
## keeps its old shape only so the levels, the goal and the respawn can go on
## asking it the same questions.

## Which way the stick leans the pull, at full stick, in degrees off straight
## down. The old tilt limit, and the same number: this is the angle the floor
## used to be turned by, now applied to gravity instead.
@export var max_lean_degrees := 20.0

## How quickly the pull follows the stick.
@export var lean_response := 25.0

## And the ceiling on that, in degrees a second, so slamming the stick over
## swings the pull rather than snapping it.
@export var max_lean_rate_degrees := 150.0

@export var thumbstick_path: NodePath

## Where the stick has got to, as a vector in the unit disc. +Y is away from the
## camera, matching the stick's own reading.
var _lean := Vector2.ZERO

var _stick: Thumbstick

## The space whose gravity is being leaned, and the gravity it had before this
## level touched it.
##
## The whole space rather than the ball alone, because the ball is not the only
## thing that used to feel the floor at an angle: the glass a broken pane throws
## slid down the tilted stage too, and it should still slide. Leaning the pull on
## everything is what keeps that true. Nothing else in a level is a free body, so
## nothing else notices.
var _space: RID
var _rest_gravity := Vector3.DOWN

## Where the level sits. Captured once and never changed -- the level does not
## move any more -- but still reported, because the spawn point and the moving
## parts are both read through it.
var _rest_transform := Transform3D()

## Set once the level is done being steered for good -- see [method freeze].
var _frozen := false


func _ready() -> void:
	# Named rather than wired up per level, so the goal ring can reach the body
	# it is riding on without every level scene having to point at it.
	add_to_group("level_body")

	_rest_transform = global_transform

	_space = get_world_3d().space
	_rest_gravity = PhysicsServer3D.area_get_param(
			_space, PhysicsServer3D.AREA_PARAM_GRAVITY_VECTOR)

	_stick = get_node_or_null(thumbstick_path) as Thumbstick


## Gravity belongs to the SPACE, and the space outlives the level: a scene change
## swaps the tree out under the same viewport, so the same World3D and the same
## space carry straight on into the menu and into the next level. A level left
## mid-lean would hand its steering to whatever came next.
func _exit_tree() -> void:
	_set_gravity(_rest_gravity)


func _physics_process(delta: float) -> void:
	if _frozen:
		return

	var wanted := _stick.value if _stick != null else Vector2.ZERO

	var eased := _lean.lerp(wanted, 1.0 - exp(-lean_response * delta))
	var max_step := max_lean_rate_degrees * delta / max_lean_degrees
	_lean += (eased - _lean).limit_length(max_step)

	_set_gravity(_pull())


## Which way the pull is going, as a unit vector.
##
## Straight down with the stick centred, and leaned off it by up to
## [member max_lean_degrees] towards whichever way the stick is pushed. The lean
## is measured against the CAMERA, not the level, so pushing the stick away from
## the player sends the ball away from the player whichever way the shot has
## swung round to.
func _pull() -> Vector3:
	var downhill := Vector3(_lean.x, 0.0, -_lean.y)

	var camera := get_viewport().get_camera_3d()
	if camera != null:
		downhill = Basis(Vector3.UP, camera.global_transform.basis.get_euler().y) * downhill

	var amount := downhill.length()
	if amount < 0.001:
		return Vector3.DOWN

	# Tipped off straight down towards `downhill`, which leaves the ball
	# `g * sin(angle)` of pull along the floor -- exactly what the floor turning
	# under it used to give.
	var angle := deg_to_rad(max_lean_degrees) * minf(amount, 1.0)
	return Vector3.DOWN * cos(angle) + downhill.normalized() * sin(angle)


func _set_gravity(direction: Vector3) -> void:
	# A node freed before it was ever readied has no space to hand this to.
	if not _space.is_valid():
		return
	PhysicsServer3D.area_set_param(
			_space, PhysicsServer3D.AREA_PARAM_GRAVITY_VECTOR, direction)


## Where the level sits. Anything that needs a fixed point on the level -- a
## spawn point, a moving part's home -- reads it through this.
##
## It is the live transform now, because the level no longer moves. Kept as its
## own call rather than folded away so the things that ask for it go on saying
## what they mean, and so a level that is one day animated has somewhere to say
## where it started.
func rest_transform() -> Transform3D:
	return _rest_transform


## Stops the steering dead and lets go of gravity, putting it back to straight
## down. Called the instant the ball touches the goal ring.
##
## Letting go of the stick is not enough: the lean eases back towards level over
## the following moments, and the celebration has already been aimed at where
## everything stood on contact.
func freeze() -> void:
	_frozen = true
	_lean = Vector2.ZERO
	_set_gravity(_rest_gravity)


## Puts the pull back to straight down with the stick's lean forgotten. Used on
## respawn, so a ball dropped at the spawn under a stick that is still held over
## starts from level rather than already rolling.
func reset_to_rest() -> void:
	# A respawn is the level starting again, so whatever stopped it is over.
	_frozen = false
	_lean = Vector2.ZERO
	_set_gravity(_rest_gravity)
