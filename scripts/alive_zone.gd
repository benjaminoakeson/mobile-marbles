extends Area3D

## The volume the player is allowed to be in. Leaving it counts as falling off
## the stage, and puts the ball back on the spawn point.

## Where a fallen player is put back. Defaults to a sibling named Spawnpoint.
@export var spawn_path: NodePath = ^"../Level/Spawnpoint"

var _spawn: Node3D
var _level: Node3D
## Set once the level is over, however it ended -- goal reached, or lives gone.
## Either way the ball must stop being hauled back to the spawn.
var _level_over := false


func _ready() -> void:
	_spawn = get_node_or_null(spawn_path) as Node3D
	if _spawn == null:
		push_warning("AliveZone: no spawn point at '%s'; falls will not respawn" % spawn_path)
	else:
		_level = _find_tilting_level(_spawn)

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
	if _level_over or _spawn == null:
		return

	if not (body is RigidBody3D and body.is_in_group("player")):
		return

	# body_exited arrives part way through the physics step, where a rigid body's
	# transform is not ours to set -- the solver would overwrite it. Deferring
	# puts the move just after the step, where it sticks.
	_respawn.call_deferred(body)


func _respawn(player: RigidBody3D) -> void:
	# Deferred from the physics step, so the scene may have changed underneath us
	# in between -- a game over sends the player to another screen entirely.
	if _level_over or not is_inside_tree() or not is_instance_valid(player):
		return

	player.linear_velocity = Vector3.ZERO
	player.angular_velocity = Vector3.ZERO
	player.global_transform = Transform3D(Basis(), _spawn_position())

	# A ball that fell a long way may have been put to sleep on the way down.
	player.sleeping = false

	# The stick may still be held over from the fall. Let go of the lean before
	# the ball is put back, or it starts its new life already rolling.
	if _level != null and _level.has_method("reset_to_rest"):
		_level.reset_to_rest()

	# Anything the ball smashed on the way down goes back, or a level with a
	# breakable floor over the only route through it is unfinishable from the
	# second life onwards. A slab set not to come back stays broken.
	for surface in get_tree().get_nodes_in_group("destructible"):
		if surface.has_method("restore") and surface.get("restores_on_respawn"):
			surface.restore()

	GameState.lose_life()

	# The rig chased the ball all the way down, so it is now below the stage and
	# facing whichever way the fall went. Put it back over the spawn.
	var camera := get_tree().get_first_node_in_group("camera_rig") as CameraFollow
	if camera != null:
		camera.reset_to_start()


## Walks up from the spawn point to whatever is steering the level.
func _find_tilting_level(from: Node) -> Node3D:
	var node := from.get_parent()
	while node != null:
		if node.has_method("rest_transform"):
			return node as Node3D
		node = node.get_parent()
	return null


## Where the spawn point sits, read through the level's rest transform.
##
## The level holds still now, so this is the spawn point's own global position by
## another name. It is still read the long way round because the level is the
## thing that owns where its points are, and a level that is one day animated
## would put the spawn somewhere else by the time the ball fell off.
func _spawn_position() -> Vector3:
	if _level == null:
		return _spawn.global_position

	var spawn_on_level := _level.global_transform.affine_inverse() * _spawn.global_transform
	return (_level.rest_transform() * spawn_on_level).origin
