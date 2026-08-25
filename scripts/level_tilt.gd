extends AnimatableBody3D

@export var max_tilt_degrees := 20.0
@export var tilt_response := 25.0
@export var max_tilt_rate_degrees := 150.0

@export var thumbstick_path: NodePath
@export var pivot_target_path: NodePath

var _tilt := Vector2.ZERO
var _stick: Thumbstick
var _pivot_target: Node3D
var _ball_radius := 0.5
var _rest_transform := Transform3D()

## How far the ball may drop below the floor it was last standing on before it
## counts as off the stage and stops dragging the pivot down with it. Comfortably
## clear of any bounce, well under the height of a real fall.
@export var fall_grace := 3.0

## The furthest the stage may travel in one physics tick, measured on the floor
## under the ball. Has to stay comfortably under the ball's radius -- that is
## what stops a triangle crossing it in a single step. See `_capped_step()`.
@export var max_step_per_tick := 0.08

var _last_pivot_local := Vector3.ZERO
var _last_grounded_y := 0.0

# NEW: Prevents the script from tilting until the physics server is synced
var _is_physics_synced := false

## Set once the level is done moving for good -- see `freeze()`.
var _frozen := false

func _ready() -> void:
	# Named rather than wired up per level, so the goal ring can reach the body
	# it is riding on without every level scene having to point at it.
	add_to_group("level_tilt")

	# The level is PLACED every tick, not driven, so the physics server must not
	# read a velocity out of how far it moved.
	#
	# `sync_to_physics` makes an AnimatableBody3D kinematic: the engine works out
	# the speed that would carry it from its old transform to its new one, and
	# hands that speed to anything resting on it. That is right for a moving
	# platform, and badly wrong here. This body is rotated about the BALL's
	# contact point, so the pivot chases the ball -- during a long fall it moves
	# most of a metre a tick, which at full tilt shifts the level's origin about
	# a third of that, and the engine reads the floor as travelling at ten metres
	# a second. The first frame the ball touches down it is handed all of it and
	# fired across the stage. Slopes do the same thing more slowly.
	#
	# Off, the body is simply teleported: contacts resolve by pushing the ball
	# out, which the engine caps, instead of by launching it. The tilt still
	# works, because the ball rolls under gravity on a sloped floor rather than
	# by being shoved along by it.
	#
	# Set here rather than on each level scene so a new level cannot be built
	# without it -- the script that moves this body is what makes it necessary.
	sync_to_physics = false

	# Wait exactly one tick for Godot to link nested AnimatableBody3Ds together.
	# This prevents child moving platforms from detaching on Frame 1.
	await get_tree().physics_frame
	
	_rest_transform = global_transform

	_stick = get_node_or_null(thumbstick_path) as Thumbstick
	_pivot_target = get_node_or_null(pivot_target_path) as Node3D
	
	if _pivot_target != null:
		_ball_radius = _sphere_radius_of(_pivot_target)

		# Seed the pivot, so the frames before the ball first touches down are
		# pivoting about the ball rather than about the level's origin.
		var start := _rest_transform.affine_inverse() * _pivot_target.global_position
		_last_pivot_local = start - Vector3(0.0, _ball_radius, 0.0)
		_last_grounded_y = _last_pivot_local.y
		
	_is_physics_synced = true


func _sphere_radius_of(node: Node) -> float:
	for child in node.find_children("*", "CollisionShape3D", true, false):
		var shape: Shape3D = (child as CollisionShape3D).shape
		if shape is SphereShape3D:
			return (shape as SphereShape3D).radius
	return 0.5


func _physics_process(delta: float) -> void:
	if _frozen or not _is_physics_synced:
		return

	var wanted := _stick.value if _stick != null else Vector2.ZERO

	var eased := _tilt.lerp(wanted, 1.0 - exp(-tilt_response * delta))
	var max_step := max_tilt_rate_degrees * delta / max_tilt_degrees
	_tilt += (eased - _tilt).limit_length(max_step)

	var downhill := Vector3(_tilt.x, 0.0, -_tilt.y)
	
	# Camera-relative tilt logic
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		var camera_basis := camera.global_transform.basis
		var camera_forward := Basis(Vector3.UP, camera_basis.get_euler().y)
		downhill = camera_forward * downhill

	var amount := downhill.length()
	var tilted := Basis()
	if amount >= 0.001:
		var axis := Vector3.UP.cross(downhill.normalized())
		tilted = Basis(axis, deg_to_rad(max_tilt_degrees) * amount)

	var pivot := _contact_point()
	var about_pivot := Transform3D(tilted, pivot - tilted * pivot)
	global_transform = _capped_step(about_pivot * _rest_transform)


## Holds the level back to a short step per tick, measured where it matters:
## on the piece of floor the ball is sitting over.
##
## The stage collides as a ConcavePolygonShape3D -- a sheet of triangles with no
## thickness and no inside. Nothing pushes a ball back out of it, so a face that
## sweeps clean past the ball between two ticks does not bump it: it leaves it on
## the far side, which reads as the ball phasing through the floor and being
## flung. The ball's own `continuous_cd` cannot help, because it is not the ball
## that moved -- it is the world.
##
## The pivot chases the ball, so during a long fall it can travel most of a metre
## a tick, which at full tilt drags the stage a good fraction of that. Capped
## well under the ball's radius, no triangle can cross it in a single step.
##
## Nothing is lost by capping: the level converges on where it wanted to be over
## the next few ticks. And in ordinary play the cap never engages at all, because
## the level turns about the ball -- the floor directly under it barely moves,
## however hard the stage is tilting.
func _capped_step(wanted: Transform3D) -> Transform3D:
	if _pivot_target == null:
		return wanted

	# The point of the level currently under the ball, and where this step would
	# carry it. This is the material point that must not jump past the ball.
	var ball := _pivot_target.global_position
	var local := global_transform.affine_inverse() * ball
	var travel := (wanted * local).distance_to(ball)

	if travel <= max_step_per_tick or travel <= 0.0001:
		return wanted

	return global_transform.interpolate_with(wanted, max_step_per_tick / travel)


## Where the level sits with no tilt applied. Anything that needs a fixed point
## on the level -- a spawn point, say -- has to be read through this, because the
## live transform swings about wherever the ball happens to be.
func rest_transform() -> Transform3D:
	return _rest_transform


func _contact_point() -> Vector3:
	if _pivot_target == null:
		return _rest_transform.origin

	# Find where the ball is right now
	var pos := _pivot_target.global_position

	# Convert that position to the level's LOCAL space
	var local_pos := _rest_transform.affine_inverse() * pos

	# Drop from the ball's centre to the floor under it, at whatever height that
	# floor happens to be. Pinning this to the level's own y = 0 instead puts the
	# pivot metres below the ball anywhere the track climbs, and every change of
	# tilt then heaves the ground out from under it.
	var contact_local := local_pos - Vector3(0.0, _ball_radius, 0.0)

	# Remember the last floor the ball actually stood on. Only used to tell a
	# bounce from a fall -- the pivot itself tracks the ball whether it is
	# touching down or not.
	if _is_grounded():
		_last_grounded_y = contact_local.y

	# The pivot has to move CONTINUOUSLY. The level's placement is a rotation
	# about it, so any jump in the pivot is a jump in the level -- it teleports
	# by roughly the jump times twice the sine of half the tilt, which on a bouncy
	# ball means the geometry lurching into it and batting it away. So follow the
	# ball through the air as well as along the ground, and only stop once it has
	# dropped clear of the stage, where its position runs away and there is no
	# landing left to keep smooth.
	if contact_local.y > _last_grounded_y - fall_grace:
		_last_pivot_local = contact_local

	# Convert it back to global space to use as the pivot
	return _rest_transform * _last_pivot_local


## Whether the ball is touching anything. Needs `contact_monitor` on the ball,
## with room for at least one contact.
func _is_grounded() -> bool:
	var body := _pivot_target as RigidBody3D
	if body == null:
		return true
	return body.get_contact_count() > 0


## Stops the level dead, wherever it currently stands. Called the instant the
## ball touches the goal ring.
##
## Letting go of the stick is not enough: the tilt eases back towards flat over
## the following moments, and the pivot keeps chasing the ball as it is vacuumed
## into the ring and thrown. Both keep moving the whole level -- the ring
## included -- underneath a celebration that has already been aimed at where
## everything was on contact, which is what pulls the ball and the ring out of
## line with each other.
func freeze() -> void:
	_frozen = true


## Puts the level flat and back where it started, with the pivot re-seeded from
## wherever the ball now is. Used on respawn: the pivot is about to jump right
## across the level, and letting that happen under a tilt would shove the
## geometry through the ball.
func reset_to_rest() -> void:
	# A respawn is the level starting again, so whatever stopped it is over.
	_frozen = false
	_tilt = Vector2.ZERO
	global_transform = _rest_transform

	if _pivot_target != null:
		var local := _rest_transform.affine_inverse() * _pivot_target.global_position
		_last_pivot_local = local - Vector3(0.0, _ball_radius, 0.0)
		_last_grounded_y = _last_pivot_local.y
