extends RigidBody3D

## The ball, and the one thing it has to be told: stay put until you are asked
## to move.
##
## Every level authors the ball half a metre above its floor, so play opens with
## it dropping onto the stage. Where the ground under the spawn is not perfectly
## flat -- and on several levels it is not -- the landing turns into a bounce and
## then a slow creep downhill, all of it before a finger has touched the screen.
## That is free ground, and free gems, on a clock that has not started yet.
##
## So the ball is pinned the instant it first touches down, and let go again by
## the very input that starts the clock. The drop still happens; it is only the
## landing that is made dead.

## Cleared once the ball has been released, so a later bounce cannot pin it all
## over again mid-level.
var _waiting := true

@onready var _mesh: MeshInstance3D = $PlayerCollider/PlayerMesh


func _ready() -> void:
	GameState.timing_started.connect(_release)
	_wear_chosen_skin()


## Puts the player's chosen marble on the ball.
##
## Done here rather than authored into the scene so every level picks the skin up
## without knowing anything about it. The material in `player.tscn` is the one
## that shows in the editor and stands in if the catalogue cannot supply one.
func _wear_chosen_skin() -> void:
	var skin_material := MarbleSkins.material_for(GameState.marble_skin)
	if skin_material != null:
		_mesh.material_override = skin_material


func _physics_process(_delta: float) -> void:
	if not _waiting or freeze:
		return

	# Pinned on first contact rather than at load: freezing it before the drop
	# would leave the ball hanging in mid-air over the stage until the player
	# moved, which reads as a bug rather than as a start.
	#
	# Needs `contact_monitor` with room for a contact, which player.tscn sets.
	if get_contact_count() > 0:
		_pin()


## Kills the landing outright. The velocities go first: freezing keeps whatever
## the body was carrying, and it would be handed straight back on release.
func _pin() -> void:
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	freeze = true


func _release() -> void:
	_waiting = false
	freeze = false
