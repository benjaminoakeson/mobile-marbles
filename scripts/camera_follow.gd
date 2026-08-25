class_name CameraFollow
extends Node3D

## Follows a target. The SpringArm3D child holds the camera back from this rig
## and pulls it in when something gets between the camera and the target.

@export var target_path: NodePath = ^"../Player"

## How fast the rig catches up to the player's position.
@export var follow_speed := 10.0

## How fast the camera swings around behind the player when they change
## direction, once the ball is at full pelt.
@export var turn_speed := 8.0

## The swing rate when the ball is barely moving. Keeping this low is what stops
## the camera twitching during precise play: at a crawl the ball's heading is
## mostly noise, and turning gently there averages that noise out instead of
## chasing it.
@export var turn_speed_min := 0.75

## Ball speed, in metres a second, that earns the full `turn_speed`.
@export var turn_full_speed := 8.0

@export_group("Look Ahead")

## How far the camera tilts off its resting pitch at full stick, in degrees.
@export var look_ahead_degrees := 4.0

## How fast the pitch eases towards the tilt the stick is asking for.
@export var pitch_response := 60.0

@export_group("Victory Orbit")

## How fast the rig circles the player once the level is won, in degrees a second.
@export var orbit_speed_degrees := 35.0

## How far back the camera pulls during the victory orbit.
@export var orbit_distance := 7.0

var _target: Node3D
var _last_target_pos := Vector3.ZERO
var _is_orbiting := false
var _rest_pitch := 0.0
var _start_yaw := 0.0
var _stick: Thumbstick

@onready var _spring: SpringArm3D = $CameraSpring


func _ready() -> void:
	# The pitch and heading authored in the scene are the neutral ones. Leans are
	# measured from the pitch, and a respawn puts the heading back to the yaw, so
	# the resting shot stays whatever the scene says it is.
	_rest_pitch = _spring.rotation.x
	_start_yaw = global_rotation.y

	# The stick lives on the level's UI layer, not under this rig, so it is found
	# by group rather than by path -- that way no level has to wire it up.
	_stick = get_tree().get_first_node_in_group("thumbstick") as Thumbstick
	if _stick == null:
		push_warning("CameraFollow: no Thumbstick in group 'thumbstick'; pitch will not lean")

	_target = get_node_or_null(target_path) as Node3D
	if _target == null:
		push_warning("CameraFollow: nothing found at '%s'" % target_path)
		return
	_exclude_from_spring(_target)
	
	# Start on target so the first frame isn't a swoop in
	global_position = _target.global_position
	_last_target_pos = _target.global_position


func _exclude_from_spring(node: Node3D) -> void:
	if node is CollisionObject3D:
		_spring.add_excluded_object((node as CollisionObject3D).get_rid())


func set_target(node: Node3D) -> void:
	if _target is CollisionObject3D:
		_spring.remove_excluded_object((_target as CollisionObject3D).get_rid())
	_target = node
	_exclude_from_spring(node)


## Hands the camera over to the level-finished shot: a slow circle around the
## player instead of a chase from behind. There is no way back -- the level is
## over, and the next one brings a fresh camera.
func start_victory_orbit() -> void:
	_is_orbiting = true


## Puts the camera back exactly where it opens the level: the scene's heading and
## pitch, sitting on the target. Call this after moving the ball to its spawn.
func reset_to_start() -> void:
	if _is_orbiting or _target == null:
		return

	global_rotation.y = _start_yaw
	global_position = _target.global_position
	_spring.rotation.x = _rest_pitch

	# Next frame reads the ball's movement against this. Left holding the spot
	# where the ball fell, it would measure one enormous step across the level
	# and immediately swing the rig round to face it, undoing the reset.
	_last_target_pos = _target.global_position


func _physics_process(delta: float) -> void:
	if _target == null:
		return

	# 1. Catch up to the ball's position smoothly
	var pos_weight := 1.0 - exp(-follow_speed * delta)
	global_position = global_position.lerp(_target.global_position, pos_weight)

	if _is_orbiting:
		# Circle at a steady rate and ease back to a wider shot. Movement-based
		# turning is skipped so the drifting ball cannot yank the camera around.
		global_rotation.y += deg_to_rad(orbit_speed_degrees) * delta
		_spring.spring_length = lerp(_spring.spring_length, orbit_distance, pos_weight)
		# Unwind whatever lean the last roll left behind, so the victory shot is
		# the same framing every time.
		_spring.rotation.x = lerp(_spring.rotation.x, _rest_pitch, pos_weight)
		return

	# 2. Figure out which way the ball is moving
	var movement := _target.global_position - _last_target_pos
	movement.y = 0.0 # Ignore bouncing up and down so the camera doesn't spin wildly

	# 3. If the ball is moving fast enough, swing the camera around to look that way
	var distance := movement.length()
	if distance > 0.01:
		var direction := movement / distance

		# --- THE FIX IS HERE ---
		# We make X and Z negative because Godot cameras look down the -Z axis.
		# This aligns the camera's lens, rather than its back, to the movement.
		var target_yaw := atan2(-direction.x, -direction.z)
		# -----------------------

		# Scale the swing with how fast the ball is actually going. A crawling
		# ball's heading wanders, so turning gently there smooths it away; at
		# speed the camera has to keep up, so it turns hard.
		var speed := distance / delta
		var blend := clampf(speed / turn_full_speed, 0.0, 1.0)
		var rate := lerpf(turn_speed_min, turn_speed, blend)

		# Smoothly rotate the camera rig towards the new angle
		var turn_weight := 1.0 - exp(-rate * delta)
		global_rotation.y = lerp_angle(global_rotation.y, target_yaw, turn_weight)

	# 4. Lean the pitch with the stick, not with the ball. The view answers the
	#    thumb straight away instead of waiting on the ball to pick up speed, and
	#    it holds the lean while the ball is stalled against a wall. Stick +Y is
	#    already "away from the camera" -- the same direction the level tilts --
	#    so it needs no reprojecting. The spring swings about this rig, which
	#    sits on the ball, so the pivot never leaves it.
	var lean := _stick.value.y if _stick != null else 0.0
	var wanted_pitch := _rest_pitch - deg_to_rad(look_ahead_degrees) * lean
	var pitch_weight := 1.0 - exp(-pitch_response * delta)
	_spring.rotation.x = lerp(_spring.rotation.x, wanted_pitch, pitch_weight)

	# Save the position for the next frame's math
	_last_target_pos = _target.global_position
