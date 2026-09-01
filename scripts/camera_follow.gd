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

@export_group("Opening Shot")

## Before the level starts, the camera takes one turn around the whole of it and
## then comes down behind the ball -- so the player is shown what they are about
## to be dropped into rather than having to work it out from a chase camera
## already in their face.
##
## The turn and the coming down are ONE movement: the yaw sweeps its full circle
## across both, so the shot never stops turning and then start again. What the
## second half adds is everything else -- the rig closing on the ball, the arm
## coming in, the pitch dropping to the chase's.
##
## The level does not start until it lands -- see [method GameState.end_intro].

## How long the wide circling lasts, and how long the fall in behind the ball
## takes after it.
##
## Short on purpose. This is a look at the level, not a fly-through of it: one
## turn, and the end of that turn is the camera arriving behind the ball. Nothing
## here is worth watching twice, and it is watched again every time the level is
## opened.
@export var intro_orbit_seconds := 1.6
@export var intro_settle_seconds := 1.1

## How far round the level the shot travels, over both of those together: one
## whole turn, whose last stretch is the fall in behind the ball. A whole turn
## also leaves the heading exactly where the level authored it, so the shot ends
## on the chase's own framing rather than swinging to find it.
@export var intro_turn_degrees := 360.0

## How far down at the level the wide shot looks.
##
## Read as a look DOWN, which on the arm itself is a negative pitch -- the rig's
## resting pitch is about -30 for the same reason. Given as a positive number
## here so the knob says what it does.
@export var intro_pitch_degrees := 34.0

## How much room to leave around the level in the wide shot.
##
## One would stand far enough off that the longest way across the level touches
## the sides of the frame -- which, since a level is far longer than it is wide,
## is a long way off for the half of the turn where it is seen end-on. Under one
## stands closer and lets the ends run out of frame at the broadside angles; the
## shot is moving, so the whole of the level is still seen on the way round.
@export var intro_margin := 0.72

## What a thumb on the screen multiplies the pace of the opening shot by.
##
## Hurried, not skipped: the shot still turns the whole way round and still comes
## down behind the ball, and the player still sees the level -- they have simply
## said they would rather get on with it. Cutting straight to play would drop them
## into a level they had been shown half of.
@export var intro_hurry_speed := 4.0

@export_group("Reverse Hold")

## Pulling straight back drives the ball AT the camera. It rolls through the shot
## and out behind it, and the heading it leaves behind swings through a
## half-circle on the way past -- so the shot chases it round, and the player who
## only asked to back up finds the camera whipping about them.
##
## So a thumb pulling back holds the heading still. Not a switch: it is a hold
## that comes off by degrees as the thumb swings away from straight back, so a
## player easing out of a reverse into a turn gets the shot back gradually rather
## than having it handed to them all at once, in the middle of a roll.

## The cone the hold is total in, either side of straight back. Narrow: this is
## meant to cover a thumb held straight back and not much else.
@export var reverse_hold_degrees := 10.0

## And where it has faded to nothing. Between the two the shot turns, but slowly,
## in proportion to how far round the thumb has come.
@export var reverse_free_degrees := 45.0

## How quickly the hold itself comes and goes, as the ordinary exponential rate.
## Smoothed over time as well as over angle, so a thumb flicked across the gate
## does not snap the shot loose.
@export var reverse_response := 9.0

## How far the thumb has to be pushed before any of this is read at all. Under
## this the stick is saying nothing, and nothing holds the shot.
@export var reverse_deadzone := 0.35

@export_group("Victory Orbit")

## How fast the rig circles the player once the level is won, in degrees a second.
@export var orbit_speed_degrees := 35.0

## How far back the camera pulls during the victory orbit.
@export var orbit_distance := 7.0

# --- The fallout shot ---
## Where the camera cuts to when the ball leaves the world: one fixed spot beside
## where the ball went over, turning to watch it drop away, held until the level
## is taken again.
##
## It is a CUT, not a swing. The ball is already gone by the time this is called,
## and easing across to it would spend the whole fall travelling.
##
## The camera then STAYS there. It is the one shot in the game that does not
## travel with the ball -- which is the whole of what it is for: a camera that
## fell alongside would show a marble hanging still against a blur, and say
## nothing about how far down it was going.

## How far the shot swings round from wherever the chase left off. A different
## angle is most of what makes it read as another camera rather than the same one
## still trying to follow.
@export var fallout_yaw_degrees := 55.0

## How far the camera stands off where the ball went over, and how far under it
## the shot sits. Looking slightly UP at it is what sells the drop: the ball goes
## on falling past a camera that has stopped.
@export var fallout_distance := 9.0
@export var fallout_pitch_degrees := -14.0

var _target: Node3D
var _last_target_pos := Vector3.ZERO
var _is_orbiting := false

## Set once the ball has left the world -- see [method start_fallout_watch]. Like
## the orbit, it is a one-way door: the level is reloaded from here, never
## resumed.
var _is_fallout := false

## Set while the opening shot is running, and never set again once it has landed.
var _is_intro := false

## Where the wide shot turns about, how far off it stands, and how far through it
## is. The middle of the level and enough room to see it -- see
## [method _frame_the_level].
var _intro_centre := Vector3.ZERO
var _intro_distance := 0.0
var _intro_time := 0.0

## What the shot's clock is running at: one until a thumb lands on the screen,
## and [member intro_hurry_speed] from then on. Latched rather than held, so a tap
## and a held thumb both say the same thing -- get on with it.
var _intro_speed := 1.0

## What the shot is coming home to: the arm length and heading the level authored
## for the chase, and what the arm bumps into once it is chasing again. All read
## before the intro moves any of them.
var _chase_length := 0.0
var _chase_collision := 0
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

## How much of the automatic turning the thumb is currently holding back: 1 is
## held still, 0 is following the ball as it always did, and everything between
## turns at that fraction of the rate it would have. See
## [member reverse_hold_degrees].
var _yaw_hold := 0.0

## Straight back on the stick. Stick +Y is away from the camera, so pulling back
## is -Y -- which is also what `Vector2.UP` happens to be, and reads as exactly
## the wrong thing here.
const PULLED_BACK := Vector2(0.0, -1.0)

## How steeply the ball is travelling, smoothed: the sine of the angle its
## heading makes with the horizontal, so -1 is straight down and +1 straight up.
## Smoothed rather than read raw -- see [member climb_settle].
var _climb := 0.0

## The two halves of the arm's pitch, settled separately: what the thumb is
## leaning the shot by, and what the ball's climb is.
##
## They are kept apart for the SKY. The sky has to undo the thumb's half and
## leave the climb's alone -- the lean is an illusion standing in for a level
## that no longer turns, where the climb is the camera really moving -- and the
## only way to hand it exactly one of them is to settle each on its own. Working
## the thumb's share out by taking the climb back off the settled total mixes a
## lagged number with an unlagged one, and leaves the sky answering to a lean the
## shot is not at.
var _settled_tilt := 0.0
var _settled_climb := 0.0


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
	_chase_length = _spring.spring_length
	_chase_collision = _spring.collision_mask

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

	# And then, on a level being seen for the first time, back off and look at the
	# whole of it. Asked for BEFORE the level's deferred start runs, which is what
	# holds the level shut until the shot has landed.
	if GameState.may_play_intro():
		_begin_intro()


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
# --- The opening shot ---

## Whether the opening shot is still running. What holds the level shut -- see
## [method GameState.is_intro_held].
func is_running_intro() -> bool:
	return _is_intro


## Backs the camera off to where the whole level fits the frame, and starts the
## turn around it. See [member intro_orbit_seconds].
func _begin_intro() -> void:
	if not _frame_the_level():
		# Nothing to look at, so nothing to look round. The level starts at once
		# rather than being held shut for a shot of empty air.
		GameState.end_intro()
		return

	_is_intro = true
	_intro_time = 0.0
	_intro_speed = 1.0
	_set_manual_yaw(false)
	_recentring = false

	# The wide shot swings on an arm long enough to see the whole level, and it
	# swings that arm THROUGH the level -- the rig sits in the middle of it. Left
	# on, the arm would bump into the floor on the first frame and haul the
	# camera in against it, which is a shot of grass rather than of the level.
	_spring.collision_mask = 0


## Works out where the level is and how big it is, from the meshes that will
## actually be drawn -- the same measure the menu's preview takes of it.
##
## Answers whether there was anything there to measure.
func _frame_the_level() -> bool:
	var level := get_tree().current_scene
	if level == null:
		return false

	var bounds := AABB()
	var found := false

	for node in level.find_children("*", "GeometryInstance3D", true, false):
		var geometry := node as GeometryInstance3D
		if not geometry.is_visible_in_tree() or geometry.is_in_group("player"):
			continue

		var box := geometry.global_transform * geometry.get_aabb()
		bounds = box if not found else bounds.merge(box)
		found = true

	if not found:
		return false

	_intro_centre = bounds.get_center()

	# How far back the whole of it has to be seen from, measured against whichever
	# way the viewport is narrower -- on a phone held upright that is across, not
	# up, and a level is far longer than it is wide.
	#
	# Measured FLAT: a level is a sheet, and its height is a kerb. Taking the
	# height into the reckoning would stand the camera off as though the level
	# were a ball as tall as it is long.
	var flat := Vector2(bounds.size.x, bounds.size.z)
	var radius := maxf(flat.length() * 0.5, 0.001)

	var half_up := deg_to_rad(_camera.fov) * 0.5
	var frame := get_viewport().get_visible_rect().size
	var half_across := atan(tan(half_up) * frame.x / maxf(frame.y, 1.0))

	_intro_distance = radius * intro_margin / tan(minf(half_up, half_across))
	return true


## One turn around the level, and a fall in behind the ball at the end of it.
##
## The yaw sweeps its whole circle across BOTH halves, so the turn does not stop
## and start again; what the second half adds is the rig closing on the ball, the
## arm coming in and the pitch dropping to the chase's.
func _run_intro(delta: float) -> void:
	_intro_time += delta * _intro_speed

	var total := intro_orbit_seconds + intro_settle_seconds
	var along := clampf(_intro_time / maxf(total, 0.01), 0.0, 1.0)
	global_rotation.y = _start_yaw + deg_to_rad(intro_turn_degrees) * along

	# Nothing but the turn until the circling is over.
	var settle := clampf((_intro_time - intro_orbit_seconds)
			/ maxf(intro_settle_seconds, 0.01), 0.0, 1.0)
	var eased := smoothstep(0.0, 1.0, settle)

	global_position = _intro_centre.lerp(_target.global_position, eased)
	_spring.spring_length = lerpf(_intro_distance, _chase_length, eased)
	_spring.rotation.x = lerpf(-deg_to_rad(intro_pitch_degrees), _rest_pitch, eased)
	_camera.rotation.z = 0.0
	_lean_the_sky(0.0, 0.0)

	if settle < 1.0:
		return

	# Landed exactly where the level authored the chase, so there is no seam
	# between the shot ending and the game taking over. The arm takes its
	# collision back with it: from here it is the chase's, and the chase has to
	# duck under whatever the level puts between the ball and the camera.
	_is_intro = false
	_spring.collision_mask = _chase_collision

	# The chase adds its pitch up out of these two, and the shot has just been
	# flown by hand. Both are nothing: the arm has landed on the resting pitch.
	_settled_tilt = 0.0
	_settled_climb = 0.0
	_auto_yaw = _start_yaw
	global_rotation.y = _start_yaw
	_last_target_pos = _target.global_position

	GameState.end_intro()


## Winds the rest of the opening shot on faster. Called when a thumb lands on the
## screen -- see [member intro_hurry_speed].
##
## Once hurried it stays hurried: a tap and a thumb held on the stick are the
## same request, and the second of them should not have to be held down for the
## rest of the shot to mean it.
func hurry_intro() -> void:
	if not _is_intro:
		return

	_intro_speed = intro_hurry_speed


## Cuts to the fallout shot and turns to watch the ball for as long as it keeps
## falling. There is no way back: the level is about to be reloaded, and that
## brings a fresh camera with it.
func start_fallout_watch() -> void:
	if _target == null:
		return

	_is_fallout = true

	# Whatever the player had set up was framing a stretch of track they have
	# just fallen off.
	_set_manual_yaw(false)
	_recentring = false
	_camera.rotation.z = 0.0
	_lean_the_sky(0.0, 0.0)

	# Framed first, the way the chase would have framed it: the rig on the ball,
	# swung round, and held off at arm's length. That puts the camera itself
	# exactly where the shot wants to stand.
	global_rotation.y = wrapf(global_rotation.y + deg_to_rad(fallout_yaw_degrees), -PI, PI)
	global_position = _target.global_position
	_spring.spring_length = fallout_distance
	_spring.rotation.x = deg_to_rad(fallout_pitch_degrees)
	_spring.force_update_transform()

	# And then the arm is taken away and the rig is left standing where the
	# CAMERA was. From here the rig IS the camera: turning it turns the shot on
	# the spot instead of swinging it round a pivot that is no longer there.
	var eye := _camera.global_position
	_spring.spring_length = 0.0
	_spring.rotation.x = 0.0
	global_position = eye
	_settled_tilt = 0.0
	_settled_climb = 0.0

	_watch_the_fall()


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

	# Asked for by hand, so it outranks a thumb that happens to be pulling back.
	_yaw_hold = 0.0


func _set_manual_yaw(on: bool) -> void:
	if _manual_yaw == on:
		return
	_manual_yaw = on
	manual_yaw_changed.emit(on)


## Gives this level its own Environment, so the sky can be turned without turning
## it in every other level that shares the resource.
## Turns the whole rig to face wherever the ball has fallen to. The rig sits at
## the camera's own position by now, so this is the camera turning on the spot --
## no part of it travels.
##
## The up vector is swapped out when the ball is almost straight down, which it
## works towards as it falls: with the two in line there is no way to tell which
## way up the shot should be, and asking for one is an error rather than a guess.
func _watch_the_fall() -> void:
	if _target == null:
		return

	var to_ball := _target.global_position - global_position
	if to_ball.length_squared() < 0.0001:
		return

	var facing := to_ball.normalized()
	var up := Vector3.UP if absf(facing.dot(Vector3.UP)) < 0.999 else Vector3.FORWARD

	global_basis = Basis.looking_at(facing, up)

	# The yaw the rest of the rig reads is now whatever the turn left behind, so
	# nothing downstream measures its next move against a heading from before the
	# fall. Nothing else runs while this shot is up, but the level is reloaded
	# from here and a stale reading is a bad thing to leave lying around.
	_auto_yaw = global_rotation.y


## Reads the thumb for how much of the turning it is holding back -- see
## [member reverse_hold_degrees].
##
## The angle is measured against straight back as one angle rather than each axis
## on its own, so a thumb pulling back and slightly off-square is still pulling
## back, and a thumb pulling diagonally is mostly not.
func _read_reverse_hold(stick: Vector2, delta: float) -> void:
	var wanted := 0.0

	# A recentre is the player asking for the shot back by hand. Nothing about
	# where their thumb is outranks that, so it holds nothing.
	if not _recentring and stick.length() >= reverse_deadzone:
		var off_back := rad_to_deg(absf(stick.angle_to(PULLED_BACK)))
		wanted = clampf(inverse_lerp(reverse_free_degrees, reverse_hold_degrees,
				off_back), 0.0, 1.0)

	_yaw_hold = lerpf(_yaw_hold, wanted, 1.0 - exp(-reverse_response * delta))


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

	# Standing still, turning to keep the ball in frame. Nothing else in the
	# shot moves: see `start_fallout_watch()`.
	if _is_fallout:
		_watch_the_fall()
		return

	# Looking the level over before any of it starts. Nothing below this runs:
	# there is no ball to chase yet, and no thumb worth answering.
	if _is_intro:
		_run_intro(delta)
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
	var settle := 1.0 - exp(-delta / maxf(climb_settle, 0.001))
	var steepness := 0.0
	if travelled > 0.001:
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

	# 4. Swing the rig towards it, unless the player is steering, or backing up.
	#    A recentre turns even with the ball still, because it was asked for by
	#    hand; otherwise a still ball leaves the shot alone, as it always has.
	var stick := _stick.value if _stick != null else Vector2.ZERO
	_read_reverse_hold(stick, delta)

	if not _manual_yaw and (distance > 0.01 or _recentring):
		# Scale the swing with how fast the ball is actually going. A crawling
		# ball's heading wanders, so turning gently there smooths it away; at
		# speed the camera has to keep up, so it turns hard.
		var speed := distance / delta
		var blend := clampf(speed / turn_full_speed, 0.0, 1.0)
		var rate := lerpf(turn_speed_min, turn_speed, blend)

		# Backing up slows the turn rather than stopping the shot dead. At a full
		# hold this is nothing and the heading stands still; part way out of the
		# cone it is a fraction, and the shot comes round gently while the thumb
		# is still deciding.
		rate *= 1.0 - _yaw_hold

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
	var tilt_weight := 1.0 - exp(-tilt_response * delta)

	# The climb rides on top of the thumb's tilt rather than replacing it, so a
	# player steering down a ramp gets both: the lean they asked for, and the
	# shot swinging round behind the dive. Going down asks the camera to sit
	# above and look down, which is a NEGATIVE pitch here -- the same direction
	# pulling the stick back gives.
	var climb_pitch := clampf(asin(clampf(_climb, -1.0, 1.0)) * climb_follow,
			-deg_to_rad(climb_pitch_limit), deg_to_rad(climb_pitch_limit))

	# Settled apart and then added, rather than added and then settled. The two
	# come to the same arm -- easing a sum at one rate is easing its parts at
	# that rate -- but only this way is the thumb's share of it a number rather
	# than a subtraction, which is what the sky needs. See `_settled_tilt`.
	_settled_tilt = lerp(_settled_tilt, deg_to_rad(tilt_pitch_degrees) * stick.y, tilt_weight)
	_settled_climb = lerp(_settled_climb, climb_pitch, tilt_weight)
	_spring.rotation.x = _rest_pitch + _settled_tilt + _settled_climb

	var wanted_roll := deg_to_rad(tilt_roll_degrees) * stick.x
	_camera.rotation.z = lerp(_camera.rotation.z, wanted_roll, tilt_weight)

	# 6. And turn the sky back out from under the tilt, so it stays put while the
	#    level appears to lean. Handed the SETTLED lean off the nodes, not what
	#    the stick just asked for, so the sky moves exactly as the shot does and
	#    the two never come apart mid-swing.
	_lean_the_sky(_settled_tilt, _camera.rotation.z)

	# Save the position for the next frame's math
	_last_target_pos = _target.global_position
