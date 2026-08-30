class_name LevelParticles
extends GPUParticles3D

## Particles that belong to the LEVEL rather than to the world.
##
## This was written when steering swung the whole stage about the ball, which
## dragged anything left in world space out from under the floor within a few
## frames. Gravity leans instead now and the level holds still, so the two frames
## agree and none of this is load-bearing any more -- it is kept because it costs
## nothing, and because it is what a level that is one day animated would need.
## Emitting in world space would do just as well today.
##
## The emitter is moved onto the level and switched to `local_coords`. That
## carries live particles along with the node, which means the node itself must
## then hold still -- it is pinned to the level's origin, and where each particle
## should start is handed to the process material as an offset instead. See
## [method _aim].
##
## Subclasses decide when to emit and what to aim at. All this does is put the
## emitter somewhere its particles can be left behind properly, and translate a
## world point and direction into the frame they are stored in.

@export_group("Drawing")

## How far around the aim point the particles are kept drawn, in metres.
##
## Particles are culled against a box on the emitter, and once the emitter is
## pinned to the level's origin that box is nowhere near them, so it is moved
## onto the aim point instead. Wide enough to hold everything still alive: for a
## trail that is however far the ball travels within one particle lifetime.
@export var draw_reach := 16.0

## This instance's own copy of the process material, which is what the aiming and
## any per-tick tuning is written to.
var _burst: ParticleProcessMaterial

## Set once the emitter has been moved onto the level and is emitting in its
## frame. Until then -- and in any scene with no level body in it -- particles
## are thrown into the world, which is no great loss: with nothing moving the
## floor, the two frames agree.
var _rides_level := false


## Call this from `_ready`. Returns immediately; the move onto the level lands a
## frame later, because the level puts itself in its group from its own `_ready`
## and it sits below the ball in the scene, so it has not run yet. The tick or
## two before then emits into the world, which nobody is going to catch.
func _bind_to_level() -> void:
	# The material is tuned per-burst, so this instance needs its own copy: the
	# resource on disk is shared with anything else that ever uses it.
	_burst = (process_material as ParticleProcessMaterial).duplicate()
	process_material = _burst
	emitting = false

	await get_tree().process_frame
	if not is_inside_tree():
		return

	var level := get_tree().get_first_node_in_group("level_body") as Node3D
	if level == null:
		return

	# Local transform kept, then cleared: this node is authored wherever it made
	# sense to author it, and what it needs now is the level's own frame.
	reparent(level, false)
	transform = Transform3D.IDENTITY
	local_coords = true
	_rides_level = true


## Points the next particles at [param point], thrown along [param direction].
## Both in world space; what happens to them depends on which frame this emitter
## ended up in.
func _aim(point: Vector3, direction: Vector3) -> void:
	if _rides_level:
		_aim_on_the_level(point, direction)
	else:
		_aim_in_the_world(point, direction)


## The emitter is pinned to the level, so it cannot be stood on the point --
## moving it would take every live particle with it. The spawn point and the
## throw are handed to the material in the level's own coordinates instead, which
## is the same thing said in the one frame that is allowed to move.
func _aim_on_the_level(point: Vector3, direction: Vector3) -> void:
	# The emitter sits at the level's origin, so its transform IS the level's.
	var to_level := global_transform.affine_inverse()
	var local_point := to_level * point

	_burst.emission_shape_offset = local_point
	_burst.direction = (to_level.basis * direction).normalized()

	# Culling follows the aim point rather than the level's origin, which it may
	# be a long way from. Without this the particles simply stop being drawn.
	visibility_aabb = AABB(
			local_point - Vector3.ONE * draw_reach, Vector3.ONE * (draw_reach * 2.0))


## No level to ride: stand the emitter on the point with its up -- which is the
## way the material throws -- along [param direction].
func _aim_in_the_world(point: Vector3, direction: Vector3) -> void:
	var side := direction.cross(Vector3.UP)
	if side.length_squared() < 0.0001:
		side = direction.cross(Vector3.RIGHT)
	side = side.normalized()

	global_transform = Transform3D(Basis(side, direction, side.cross(direction)), point)
