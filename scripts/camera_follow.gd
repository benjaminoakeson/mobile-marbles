class_name CameraFollow
extends Node3D

## Follows a target. The SpringArm3D child holds the camera back from this rig
## and pulls it in when something gets between the camera and the target.

signal manual_yaw_changed(is_manual: bool)

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

@export_group("Vertical Follow")

## How far the shot swings to get behind a climb or a dive, as a share of the
## angle the ball is actually travelling at. At 1 it lines up dead behind the
## ball's real heading; at 0 it stays flat, which is how the shot used to work.
@export var climb_follow := 0.8

## The most it may swing either way, in degrees off the resting pitch. A ball
## dropping straight down would otherwise ask the shot to sit directly overhead.
@export var climb_pitch_limit := 32.0

## How fast the ball has to be going for a climb or a dive to count for its full
## worth, in metres a second. Below it the shot leans in proportionately less,
## and a ball barely moving does not lean it at all.
##
## Steepness on its own is not enough to act on: a ball settling onto a ledge is
## briefly going straight down, and so is one falling off a cliff. What tells
## them apart is how fast, so the shot only swings for travel that is actually
## happening.
@export var climb_full_speed := 10.0

## How long after a respawn the shot ignores the ball's climb entirely, in
## seconds.
##
## Every level authors its ball above the floor, so a respawn drops it and lets
## it bounce -- and that drop is not the player going anywhere. Without this the
## shot dives to follow it, recovers, and dives again as it settles, which reads
## as the camera shaking itself apart just as you get control back.
@export var respawn_hold := 0.6

## How long the ball has to keep climbing or diving before the shot commits to
## it, in seconds.
##
## This is the whole reason the pitch can follow the ball at all. Vertical
## movement used to be thrown away outright, because a bouncing ball alternates
## up and down every few frames and feeding that straight into the shot rocks it
## sickeningly. Averaged over this long a bounce comes to nothing -- it is as
## much up as down -- while a real fall or a real climb does not, so what is left
## is the movement worth following.
@export var climb_settle := 0.3

@export_group("Tilt Illusion")

## The level does not move any more -- gravity leans instead (see
## [GravityTilt]) -- so the camera is what sells the lean. Pitching and rolling
## the SHOT the opposite way to the stick puts the tilt back on screen: the
## ground swings under a steady horizon instead of the other way round, and the
## player reads it the same either way.
##
## How far the shot pitches at full stick, in degrees. Pushing away from the
## player rotates it back, which drops the ground ahead out of frame the way a
## track tipping away from them used to.
@export var tilt_pitch_degrees := 12.0

## How far it rolls at full stick, in degrees. Steering right rolls the shot to
## the left and steering left rolls it to the right, so the horizon swings
## against the thumb.
##
## Well under the twenty degrees the stage used to physically turn through. The
## eye reads a rolling horizon far more strongly than a rolling floor, and
## matching the old angle one-for-one is enough to make people seasick.
@export var tilt_roll_degrees := 7.0

## How fast the shot eases towards the tilt the stick is asking for.
@export var tilt_response := 60.0

## Whether the sky is held still while the shot tilts under it.
##
## This is what makes the illusion pay off rather than merely happen. Rolling the
## camera rolls EVERYTHING -- the track and the horizon together -- and a picture
## that turns as one piece reads as a camera being rolled, which is exactly what
## it is. What said "the level is tilting" in the old build was the DIFFERENCE
## between the two: the horizon stayed where it was and the ground swung under
## it.
##
## So the sky is turned back by however much the thumb has tilted the shot,
## which puts it back where it would have been and leaves the level appearing to
## lean against it. Only the thumb's share is undone -- the shot swinging round
## behind a dive is the camera really moving, and the sky should move with that.
@export var sky_holds_still := true

@export_group("Manual Yaw")

## How fast the rig swings back to the automatic heading once the player hands
## the camera back. Faster than `turn_speed`, because this is a button press
## asking for the shot back rather than the shot quietly keeping up.
@export var recentre_speed := 6.0

## How close to the automatic heading counts as arrived, in degrees. Past this
## the recentre ends and the ordinary speed-scaled turning takes over, so the
## handover has no visible seam.
@export var recentre_arrived_degrees := 1.0

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

## The heading the automatic shot wants. Tracked every tick whether or not it is
## the one being used, so the moment the player hands the camera back there is
## somewhere to swing to -- including when they hand it back with the ball
## sitting still, which is when they most need the shot put right.
var _auto_yaw := 0.0

## Set while the player is steering the camera. Nothing else may touch the yaw
## until they press reset.
var _manual_yaw := false

## Set by the reset press, cleared once the rig has caught up with `_auto_yaw`.
var _recentring := false

## How steeply the ball is travelling, smoothed: the sine of the angle its
## heading makes with the horizontal, so -1 is straight down and +1 straight up.
## Smoothed rather than read raw -- see [member climb_settle].
var _climb := 0.0

## Seconds left of ignoring the climb after a respawn. See [member respawn_hold].
var _climb_held := 0.0

## This level's own copy of its environment, so turning the sky in one level does
## not turn it in every other level sharing the resource on disk.
##
## A shallow copy: the Sky and its material stay shared, which is what we want --
## `sky_rotation` lives on the Environment, and there is no sense in every level
## carrying its own copy of a sky shader.
var _environment: Environment = null

@onready var _spring: SpringArm3D = $CameraSpring

## The roll goes on the camera rather than on the arm. Rolling the arm would
## swing the camera bodily around the ball; rolling the camera turns the picture
## on the spot, which is what a tilting world looks like.
@onready var _camera: Camera3D = $CameraSpring/Camera3D


func _ready() -> void:
	# The pitch and heading authored in the scene are the neutral ones. Leans are
	# measured from the pitch, and a respawn puts the heading back to the yaw, so
	# the resting shot stays whatever the scene says it is.
	_rest_pitch = _spring.rotation.x
	_start_yaw = global_rotation.y
	_auto_yaw = _start_yaw

	# The stick lives on the level's UI layer, not under this rig, so it is found
	# by group rather than by path -- that way no level has to wire it up.
	_stick = get_tree().get_first_node_in_group("thumbstick") as Thumbstick
	if _stick == null:
		push_warning("CameraFollow: no Thumbstick in group 'thumbstick'; pitch will not lean")

	# The goal ring is solid, so the ball has to go through the hole rather than
	# at it -- but that also makes it something for the spring to bump into, and
	# the run up to the goal is the last moment the camera should be jumping. Its
	# glass is a body of its own, so the whole branch goes, not just the ring.
	# Found by group, so no level has to wire it up.
	for ring in get_tree().get_nodes_in_group("goal_ring"):
		_exclude_branch_from_spring(ring as Node3D)

	_hold_the_sky_still()

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


## The same, for everything hanging off a node as well as the node itself. Some
## things the camera has to see past are built from more than one body.
func _exclude_branch_from_spring(node: Node3D) -> void:
	if node == null:
		return
	_exclude_from_spring(node)
	for child in node.get_children():
		_exclude_branch_from_spring(child as Node3D)


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

	# The orbit drives the yaw itself, so the player's heading is over with. Said
	# out loud rather than just dropped, so the reset button goes away with it.
	_set_manual_yaw(false)
	_recentring = false


## Whether the player is currently holding the camera off the automatic shot.
func is_manual_yaw() -> bool:
	return _manual_yaw


## Swings the rig by `radians` and keeps it there. The automatic turning stands
## down for good once this is called, so the shot is exactly where the player
## left it until `release_manual_yaw()` -- the reset button -- asks for it back.
func rotate_yaw(radians: float) -> void:
	# The victory orbit owns the yaw, and there is no going back to play from it.
	if _is_orbiting:
		return

	_recentring = false
	_set_manual_yaw(true)
	global_rotation.y = wrapf(global_rotation.y + radians, -PI, PI)


## Hands the camera back to the automatic shot, swinging round to meet it rather
## than cutting, so the player can see where the view went.
func release_manual_yaw() -> void:
	if not _manual_yaw:
		return

	_set_manual_yaw(false)
	_recentring = true


func _set_manual_yaw(on: bool) -> void:
	if _manual_yaw == on:
		return
	_manual_yaw = on
	manual_yaw_changed.emit(on)


## Puts the camera back exactly where it opens the level: the scene's heading and
## pitch, sitting on the target. Call this after moving the ball to its spawn.
##
## A respawn is the level starting again, so it also takes the camera back off
## the player: the shot they set was framing a stretch of track they are no
## longer standing on, and the authored opening shot is the one that frames the
## spawn.
func reset_to_start() -> void:
	if _is_orbiting or _target == null:
		return

	_set_manual_yaw(false)
	_recentring = false

	global_rotation.y = _start_yaw
	_auto_yaw = _start_yaw
	global_position = _target.global_position
	_spring.rotation.x = _rest_pitch
	_camera.rotation.z = 0.0
	_lean_the_sky(0.0, 0.0)
	# The ball fell a long way to get here; that dive is not the new life's. And
	# the drop onto the spawn that is about to happen is not either, so the climb
	# is held off entirely until the ball has settled on the floor.
	_climb = 0.0
	_climb_held = respawn_hold

	# Next frame reads the ball's movement against this. Left holding the spot
	# where the ball fell, it would measure one enormous step across the level
	# and immediately swing the rig round to face it, undoing the reset.
	_last_target_pos = _target.global_position


## Gives this level its own Environment, so the sky can be turned without turning
## it in every other level that shares the resource.
func _hold_the_sky_still() -> void:
	if not sky_holds_still:
		return

	# One per level, found by walking rather than wired up, so no level scene has
	# to know the camera wants it.
	for node in get_tree().get_nodes_in_group("world_environment"):
		var holder := node as WorldEnvironment
		if holder != null and holder.environment != null:
			_environment = holder.environment.duplicate()
			holder.environment = _environment
			return

	var root := get_tree().current_scene
	if root == null:
		return
	for child in root.get_children():
		var holder := child as WorldEnvironment
		if holder != null and holder.environment != null:
			_environment = holder.environment.duplicate()
			holder.environment = _environment
			return


## Turns the sky back by the shot's own tilt, so on screen it does not move.
##
## The two angles are the illusion's share and nothing else: the pitch the thumb
## added on top of the resting shot, and the roll. Both are undone about the
## CAMERA's axes and then expressed in world ones, because that is the frame the
## sky is read in.
func _lean_the_sky(pitch: float, roll: float) -> void:
	if _environment == null:
		return

	# What the camera would be pointing if the thumb had never touched it. Undoing
	# the roll first and then the pitch is the order they were applied in, run
	# backwards -- the arm pitches and the camera rolls inside it.
	var actual := _camera.global_transform.basis
	var clean := actual * Basis(Vector3.BACK, -roll) * Basis(Vector3.RIGHT, -pitch)

	# The turn that carries the clean view back onto the real one. Godot reads the
	# sky by turning the eye direction by the INVERSE of `sky_rotation`, so the
	# basis handed over is the one that maps clean onto actual, not the other way
	# about. Get that backwards and the sky swings the opposite way to the shot
	# instead of holding still, which doubles the tilt rather than cancelling it.
	_environment.sky_rotation = (actual * clean.inverse()).get_euler()


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
		# Unwind whatever tilt the last roll left behind, so the victory shot is
		# the same framing every time.
		_spring.rotation.x = lerp(_spring.rotation.x, _rest_pitch, pos_weight)
		_camera.rotation.z = lerp(_camera.rotation.z, 0.0, pos_weight)
		return

	# 2. Figure out which way the ball is moving. The two axes of the shot want
	#    different halves of it, so they are split here rather than one being
	#    thrown away: the heading comes off the FLAT travel and the pitch off how
	#    steeply the ball is going.
	var movement := _target.global_position - _last_target_pos
	var travelled := movement.length()

	# How steep, smoothed, and weighted by how fast the ball is actually going.
	#
	# Three things have to be true before the shot leans: the ball is going
	# somewhere (`travelled`), going somewhere QUICKLY (`carries`), and has kept
	# it up (`climb_settle`). A ball on the ground bounces up as much as it comes
	# down, so the last of those averages it to nothing; a ball settling onto its
	# spawn is going nowhere fast, so the second one does. A real dive down a
	# wall passes all three. A ball that has stopped eases back to level rather
	# than holding the last thing it saw.
	_climb_held = maxf(_climb_held - delta, 0.0)
	var settle := 1.0 - exp(-delta / maxf(climb_settle, 0.001))
	var steepness := 0.0
	if travelled > 0.001 and _climb_held <= 0.0:
		var carries := clampf(travelled / maxf(delta, 0.0001) / maxf(climb_full_speed, 0.001),
				0.0, 1.0)
		steepness = movement.y / travelled * carries
	_climb = lerpf(_climb, steepness, settle)

	# The heading is taken FLAT. A ball dropping down a wall has not changed
	# which way it is facing, and folding the fall in here would spin the shot
	# right round on every bounce -- which is what the pitch is for instead.
	var flat := Vector3(movement.x, 0.0, movement.z)
	var distance := flat.length()

	# 3. Remember the heading the automatic shot wants, even while the player has
	#    the camera. It is what the reset button swings back to, and a ball that
	#    has come to rest offers no heading of its own to work one out from.
	if distance > 0.01:
		var direction := flat / distance

		# --- THE FIX IS HERE ---
		# We make X and Z negative because Godot cameras look down the -Z axis.
		# This aligns the camera's lens, rather than its back, to the movement.
		_auto_yaw = atan2(-direction.x, -direction.z)
		# -----------------------

	# 4. Swing the rig towards it, unless the player is steering. A recentre
	#    turns even with the ball still, because it was asked for by hand;
	#    otherwise a still ball leaves the shot alone, as it always has.
	if not _manual_yaw and (distance > 0.01 or _recentring):
		# Scale the swing with how fast the ball is actually going. A crawling
		# ball's heading wanders, so turning gently there smooths it away; at
		# speed the camera has to keep up, so it turns hard.
		var speed := distance / delta
		var blend := clampf(speed / turn_full_speed, 0.0, 1.0)
		var rate := lerpf(turn_speed_min, turn_speed, blend)
		if _recentring:
			rate = maxf(rate, recentre_speed)

		# Smoothly rotate the camera rig towards the new angle
		var turn_weight := 1.0 - exp(-rate * delta)
		global_rotation.y = lerp_angle(global_rotation.y, _auto_yaw, turn_weight)

		# Once it has arrived, ordinary turning takes over at its own pace.
		if _recentring:
			var off := absf(angle_difference(global_rotation.y, _auto_yaw))
			if off < deg_to_rad(recentre_arrived_degrees):
				_recentring = false

	# 5. Tilt the shot with the stick, not with the ball. The view answers the
	#    thumb straight away instead of waiting on the ball to pick up speed, and
	#    it holds the tilt while the ball is stalled against a wall. Stick +Y is
	#    already "away from the camera" -- the same direction gravity leans -- so
	#    neither axis needs reprojecting.
	#
	#    Both run against the thumb, because the camera is standing in for a level
	#    that no longer turns. Pushing away rotates the shot back, which swings
	#    the ground ahead downward out of frame exactly as a track tipping away
	#    from the player used to; steering right rolls the shot left, and left
	#    rolls it right. The pivot never leaves the ball: the arm swings about
	#    this rig, which sits on it, and the roll turns the camera on the spot.
	var stick := _stick.value if _stick != null else Vector2.ZERO
	var tilt_weight := 1.0 - exp(-tilt_response * delta)

	# The climb rides on top of the thumb's tilt rather than replacing it, so a
	# player steering down a ramp gets both: the lean they asked for, and the
	# shot swinging round behind the dive. Going down asks the camera to sit
	# above and look down, which is a NEGATIVE pitch here -- the same direction
	# pulling the stick back gives.
	var climb_pitch := clampf(asin(clampf(_climb, -1.0, 1.0)) * climb_follow,
			-deg_to_rad(climb_pitch_limit), deg_to_rad(climb_pitch_limit))

	var wanted_pitch := _rest_pitch + deg_to_rad(tilt_pitch_degrees) * stick.y + climb_pitch
	_spring.rotation.x = lerp(_spring.rotation.x, wanted_pitch, tilt_weight)

	var wanted_roll := deg_to_rad(tilt_roll_degrees) * stick.x
	_camera.rotation.z = lerp(_camera.rotation.z, wanted_roll, tilt_weight)

	# 6. And turn the sky back out from under the tilt, so it stays put while the
	#    level appears to lean. The values used are the SETTLED ones off the
	#    nodes, not what the stick just asked for, so the sky lags exactly as the
	#    shot does and the two never come apart mid-swing.
	_lean_the_sky(_spring.rotation.x - _rest_pitch - climb_pitch, _camera.rotation.z)

	# Save the position for the next frame's math
	_last_target_pos = _target.global_position
