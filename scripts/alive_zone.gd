extends Area3D

## The volume the player is allowed to be in. Leaving it is a fall, and a fall
## takes the level back to the top.
##
## The ball used to be lifted back onto the spawn point with the level left
## standing around it -- gems gone, floor broken, clock still running. It is the
## whole level that starts again now, which is one `reload_current_scene()` in
## [GameState] and nothing to put back by hand here.
##
## What this does own is the FALL itself: the camera cuts to the ball dropping
## away, the sound marks it, and the level waits there until the player asks for
## it again. The waiting is the HUD's -- it is the one with a screen to take a
## tap on -- and the asking is `GameState.restart_level()`.

## Where the ball starts. Only read for the warning below: nothing is put back
## here any more, but a level with no spawn point at all is still worth saying
## something about, because the reload will drop the ball into the same nothing.
@export var spawn_path: NodePath = ^"../Level/Spawnpoint"

var _spawn: Node3D

## Set once the level is over, however it ended -- goal reached, lives gone, or a
## fall being watched. Either way this volume has nothing left to report: the
## ball is not coming back to it.
var _level_over := false


func _ready() -> void:
	_spawn = get_node_or_null(spawn_path) as Node3D
	if _spawn == null:
		push_warning("AliveZone: no spawn point at '%s'; the ball has nowhere to start" % spawn_path)

	body_exited.connect(_on_body_exited)

	# Winning throws the ball straight up, which can carry it out through the top
	# of this volume. A finished level must not haul the player back to the start
	# in the middle of the celebration.
	var ring := get_tree().get_first_node_in_group("goal_ring")
	if ring != null and ring.has_signal("level_completed"):
		ring.connect("level_completed", _on_level_over)

	# And a run that is out of lives is over too. Without this the ball keeps
	# falling behind the game-over screen, respawning and losing lives it does
	# not have.
	GameState.run_ended.connect(_on_level_over)


func _on_level_over() -> void:
	_level_over = true


func _on_body_exited(body: Node3D) -> void:
	if _level_over:
		return

	if not (body is RigidBody3D and body.is_in_group("player")):
		return

	# One fall per level. The ball goes on falling under the shot below, and
	# leaving a stretched-out collision shape behind can report it leaving twice.
	_level_over = true

	_watch_them_fall(body as RigidBody3D)


## The fall, as the player sees it: hands off the ball, a cut to it dropping
## away, and the sound that says the level is being handed back.
##
## Whether the run can afford the fall at all is [GameState]'s -- if that was the
## last life there is a game-over screen going up instead, and none of this
## belongs over the top of it.
func _watch_them_fall(player: RigidBody3D) -> void:
	if player.has_method("stop_driving"):
		player.stop_driving()

	# The stick cannot steer a ball nobody is driving, and a stick still drawn
	# over the fall reads as one that should be doing something.
	var stick := get_tree().get_first_node_in_group("thumbstick")
	if stick != null and stick.has_method("disable"):
		stick.disable()

	if not GameState.fall_out():
		return

	var camera := get_tree().get_first_node_in_group("camera_rig") as CameraFollow
	if camera != null:
		camera.start_fallout_watch()

	Audio.play(Audio.BALL_APPEAR)
