@tool
class_name DestructibleSurface
extends StaticBody3D

## A pane that gives way when the ball hits it hard enough, and comes apart the
## way glass does: a web of cracks spreading from wherever it was struck, and
## shards cut along those same cracks.
##
## Drop it under the Level body and set `size`. The collider and the pane you can
## see are both built from that one number, because they have to agree exactly --
## the shards are cut out of the same box.
##
## It has to be its OWN body, for the reason the ice surface is one too: breaking
## takes its collider out of the world, and that is a property of the body rather
## than of one shape among several. StaticBody3D on purpose -- it never moves
## relative to the level, and a nested AnimatableBody3D would bring the
## `sync_to_physics` trap with it if the level were ever moved.
##
## The shards are deliberately NOT put under the level. A RigidBody3D is owned by
## the physics server, and parenting one to another body fights the solver. They
## go into the scene root instead, where all they have to do is fall -- and they
## fall the way the player is steering, because it is the whole space's gravity
## that leans. See `gravity_tilt.gd`.

## How the pane comes apart.
##
## GLASS throws a web out from the point of impact: spokes running to the edges,
## rings crossing them, and shards cut from the cells between. Near the strike
## the cells are small and the shards are slivers; further out they open up. That
## uneven spread is what reads as glass rather than as tiles coming loose.
##
## CHUNKS is the blunt alternative -- a ragged grid, the same wherever it was
## hit. For crates and plaster.
enum Pattern { GLASS, CHUNKS }

## What the pane is cut to.
##
## PANE is the rectangle everything else here assumes: a floor, a window, a wall.
## DISC is the same pane cut round, for a porthole or the middle of a goal ring,
## and it is built flat in XZ with its thickness on Y -- stand one up by turning
## the node, the way you would a pane.
enum Shape { PANE, DISC }

## The crack itself. There is no glass smash in the audio library, so this is the
## sharpest thing in it; the tinkle underneath is built in `_smash()` out of the
## tally clink, pitched well up and scattered.
const CRACK_SOUND := preload("res://audio/BumpIce.WAV")
const TINKLE_SOUND := preload("res://audio/Clink.wav")

## What CHUNKS breaks with instead -- a dull wooden crack rather than a bright one.
const SPLINTER_SOUND := preload("res://audio/TrapWood.wav")

## The shards answer to nothing but the stage and each other. Kept off the
## player's mask on purpose: a ball batted about by falling glass is chaos, and
## the interesting thing about a broken floor is the hole, not the shrapnel.
const DEBRIS_LAYER := 8   # Debris
const DEBRIS_MASK := 9    # Static | Debris

## How close counts as touching, on top of the ball's own reach. A hair, so a
## ball that has already settled against a pane is not read as arriving at it.
const CONTACT_SLOP := 0.02

## This pane's own copy of [member surface_material], tinted to [member colour].
## Built on demand and thrown away whenever the material is swapped, so a pane
## that is never recoloured never makes one.
var _tinted: Material = null

## Whether the pane is cut square or round.
@export var shape := Shape.PANE:
	set(value):
		shape = value
		_rebuild()

## How big the pane is. Set the shape with this rather than with the node's
## scale: the shards are cut from these numbers, and a scaled node would hand
## them a size that does not match what is on screen.
##
## For a DISC, X and Z are the diameter and the wider of the two wins, with Y the
## thickness as before.
##
## Thin by default, the way glass is. A pane much thicker than this stops reading
## as glass however it breaks.
@export var size := Vector3(4.0, 0.12, 4.0):
	set(value):
		size = Vector3(maxf(value.x, 0.01), maxf(value.y, 0.01), maxf(value.z, 0.01))
		_rebuild()

## What the pane is made of. The shards are drawn with it too, so the pane and
## its wreckage always match with nothing else to set up.
##
## Shared with every other pane using it, so it is never written to -- see
## [member colour], which does the changing on a copy.
@export var surface_material: Material = preload("res://materials/glass.tres"):
	set(value):
		surface_material = value
		_tinted = null
		_rebuild()

## The colour of the pane, and of every shard it throws.
##
## Set per pane, so one level can have a green pane over the drop and a red one
## across the shortcut without either needing a material of its own. It replaces
## the albedo of [member surface_material] rather than multiplying it, so a pane
## can be any colour whatever the material was authored as -- and the ALPHA is
## part of it, which for glass is the difference between a pane you can plan a
## route through and one you cannot.
##
## The material on disk is never touched. Each pane tints its own copy, or the
## first green pane in a level would turn every pane in the project green.
@export var colour := Color(0.68, 0.85, 0.92, 0.34):
	set(value):
		colour = value
		_retint()
		_rebuild()

## How the shards land -- slippery and a little bouncy for glass. Handed to every
## shard as it is thrown.
@export var debris_physics: PhysicsMaterial = preload("res://materials/physics_materials/glass.tres")

@export_group("Breaking")

@export var pattern := Pattern.GLASS

## How hard the ball has to hit it, as the impulse the pane would have to absorb
## -- the ball's mass times the speed it is closing on the face at.
##
## Only speed INTO the face counts, which is the whole point: it is blunt force
## being measured, not pace. A ball tearing along a pane is asking nothing of it
## and leaves it standing, however fast it goes. Measured off the real ball, at
## the gravity the game actually plays at:
##
##     rolling flat out ALONG it, at any speed ....  0
##     rolling into one stood up as a wall, 6 m/s . 30
##     dropped onto it from half a metre .......... 27
##     dropped onto it from one metre ............. 38
##     dropped onto it from three metres .......... 66
##
## The default sits above every step and every gentle nudge a track is likely to
## have in it, and below a run-up or a drop the player had to line up, so a pane
## breaks when it is aimed at.
@export var break_impulse := 45.0

## Whether a hit that is not quite enough leaves a crack behind.
##
## Glass fails twice: it crazes, and then it goes. Splitting it in two is what
## lets a pane warn the player without swallowing them -- and the crack is drawn
## from the very web the pane will break along, so it says where as well as
## whether.
@export var cracks_before_breaking := true

## What share of `break_impulse` cracks it. Below this the hit does nothing.
@export_range(0.0, 1.0) var crack_share := 0.4

## What a cracked pane's threshold falls to, as a share of the whole. Cracked
## glass is weaker glass; the second hit does not have to be the first one again.
@export_range(0.05, 1.0) var cracked_strength := 0.4

## What the ball keeps of its speed for going through.
##
## The pane is taken out of the world before the step that would have hit it, so
## the glass costs the ball nothing of its own -- this is the entire price, and
## it is a shave off the speed rather than anything the player feels as a stop.
## One is a free pass; low numbers are a wall by another name.
@export_range(0.0, 1.0) var shatter_momentum_kept := 0.9

@export_group("Web")

## Spokes thrown out from the strike, on top of the one that every corner of the
## pane gets. Rings crossing them, counting the strike itself as the innermost.
##
## The two multiply out into the shard count: the default is about thirty.
@export_range(3, 16) var spokes := 6
@export_range(1, 5) var rings := 3

## How far a spoke wanders off an even share of the circle, and how far a ring
## wanders off its own radius. Zero for both is a dartboard.
@export_range(0.0, 1.0) var spoke_jitter := 0.55
@export_range(0.0, 1.0) var ring_jitter := 0.6

## How the rings crowd towards the strike. One spaces them evenly; higher packs
## them in tight where the ball landed, which is where real glass shatters
## finest.
@export_range(1.0, 4.0) var ring_growth := 2.0

## For CHUNKS: cuts across each of the pane's two long sides, and how ragged
## they are. Ignored by GLASS, which uses the web above.
@export_range(2, 6) var chunk_cuts := 3
@export_range(0.0, 0.9) var chunk_jitter := 0.35

@export_group("Cracks")

## How wide a crack is drawn, and how far it floats above the face so it is not
## fighting the pane for the same pixels.
##
## Hairline on purpose. Levels light themselves with glow turned on, and an
## unshaded near-white ribbon blooms out well past its own width -- draw these at
## anything like the width they look, and the pane ends up webbed with pipes.
@export var crack_width := 0.022
@export var crack_lift := 0.004

## Kept off pure white, and well short of opaque, for the same reason.
@export var crack_colour := Color(0.82, 0.91, 0.97, 0.45)

@export_group("Shards")

## How hard the shards are thrown: out from wherever the ball struck, and off the
## face of the pane.
@export var burst_out := 3.4
@export var burst_off_face := 1.6
@export var burst_spin := 11.0

## Kilograms a cubic metre. Nothing but the shards themselves feels this -- they
## meet the stage, which is immovable, and each other, where only the ratio
## between them counts. It is here so a big shard shoulders a sliver aside rather
## than the two trading places.
@export var debris_density := 80.0

## How hard the shards fall, against the ball. The ball plays under gravity wound
## well past life-size, and debris left on the world's own setting drifts down in
## slow motion beside it -- so this follows the ball rather than the world, and
## one is the same rate the ball drops at.
@export var debris_gravity_scale := 1.0

## How long the shards lie about before they shrink away, and how long that takes.
@export var debris_lifetime := 2.5
@export var debris_fade := 0.35

## How many clinks are scattered under the crack as the glass comes down, and the
## window they are spread over.
@export var tinkle_count := 5
@export var tinkle_window := 0.55

@onready var _shape: CollisionShape3D = $Shape
@onready var _mesh: MeshInstance3D = $Mesh

var _ball: RigidBody3D
var _broken := false
var _cracked := false

## How far the ball reaches, so the pane knows when it is about to be touched
## rather than waiting to be told that it was.
var _ball_radius := 0.5

## Set once a run at the pane has been answered, and cleared when the ball turns
## away from it. One approach is one blow.
##
## Reading ahead is what makes this necessary. The pane decides a tick or so
## before the ball lands, and the ball is still closing on the very next tick --
## so the same run at it would be read a second time, against the lower
## threshold the crack it just left behind had dropped it to. Every crack would
## break the pane on the tick after it appeared, which is no crack at all.
var _hit_answered := false

## The ball's own gravity, which the shards are given so they fall alongside it.
var _play_gravity := 1.0

## The web the pane cracked along, kept so it breaks along the same one. A pane
## that shatters on the first hit works one out on the spot.
var _web: Array[PackedVector2Array] = []

## The drawn cracks, and the shards thrown, so restoring the pane can take both
## away rather than leave a whole floor with a web across it and rubble under it.
var _crack_mesh: MeshInstance3D
var _debris: Array[Node3D] = []

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rebuild()

	if Engine.is_editor_hint():
		return

	_ball = get_tree().get_first_node_in_group("player") as RigidBody3D
	if _ball == null:
		push_warning("%s: no player in group 'player'; it will never break" % name)
		set_physics_process(false)
		return

	_play_gravity = _ball.gravity_scale
	_ball_radius = _measure_ball()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or _ball == null:
		return

	# Nothing left to break, or the ball is pinned on the level's opening drop
	# and has not started playing yet.
	if _broken or _ball.freeze:
		return

	var blow := _blow_coming(delta)
	if blow <= 0.0:
		# Away from the pane, across it, or nowhere near it. Whatever it does
		# next is a new run at the glass.
		_hit_answered = false
		return

	if _hit_answered:
		return

	var threshold := break_impulse * (cracked_strength if _cracked else 1.0)

	if blow >= threshold:
		_shatter(_ball.global_position)

		# The whole cost of going through, and the only thing done to the ball.
		# The pane is out of the world before the step that would have hit it,
		# so there is no contact to survive: the ball carries straight on, a
		# shade slower. Nothing here changes its heading, which is what keeps
		# the chase camera pointed where it was already looking.
		_ball.linear_velocity *= shatter_momentum_kept

	elif cracks_before_breaking and not _cracked and blow >= break_impulse * crack_share:
		# The pane held, so it is a wall like any other and the solver bounces
		# the ball off it in its own time -- off the real angle it struck at,
		# with the pane's own physics material. Nothing is added on top of that.
		_craze(_ball.global_position)
		_hit_answered = true


## The blow the pane is about to take, or zero if it is about to take none.
##
## Read the tick BEFORE it lands, which is the whole reason this looks ahead
## instead of looking at contacts. A contact can only be seen after the solver
## has already dealt with it -- by which time a pane the ball was going to go
## straight through has stopped it dead for a tick, and a stopped ball is a
## visible hitch and a camera swinging round to face a heading that came out of
## nowhere. Deciding first means the collider is gone before there is anything
## to solve, and the ball never touches the glass at all.
##
## Only the speed into the face counts. See `break_impulse`.
func _blow_coming(delta: float) -> float:
	var thin := _thin_axis()
	var here := to_local(_ball.global_position)

	# The face on the ball's side of the pane, so a floor is hit from above and
	# from below by the same arithmetic.
	var face := _face_normal() * (1.0 if here[thin] >= 0.0 else -1.0)

	var closing := -_ball.linear_velocity.dot(face)
	if closing <= 0.0:
		return 0.0

	# Off the end of the pane: whatever the ball is doing, it is not doing it
	# here. Its own reach is allowed for, so a hit on the very edge still counts.
	if shape == Shape.DISC:
		# A disc is set into something -- a frame, a wall, the middle of a goal
		# ring -- and its rim is buried in whatever that is. So the ball has to be
		# properly over the glass, inset by its own reach, rather than merely
		# within reach of the edge: out there it is going to meet the frame, and a
		# pane that breaks when the ball was never going to touch it shatters
		# under hits that visibly bounce off the ring.
		if Vector2(here[(thin + 1) % 3], here[(thin + 2) % 3]).length() \
				> maxf(_disc_radius() - _ball_radius, _disc_radius() * 0.1):
			return 0.0
	else:
		for axis in [(thin + 1) % 3, (thin + 2) % 3]:
			if absf(here[axis]) > size[axis] * 0.5 + _ball_radius:
				return 0.0

	# Still short of the pane once this step has run. Nothing yet.
	var gap := absf(here[thin]) - size[thin] * 0.5 - _ball_radius
	if gap > closing * delta + CONTACT_SLOP:
		return 0.0

	return _ball.mass * closing


## Breaks the pane where it stands. Public so a level can spring it from a switch
## or a script; it goes as though struck in the middle.
func shatter() -> void:
	if not _broken:
		_shatter(global_position + _face_normal() * size[_thin_axis()])


func is_broken() -> bool:
	return _broken


## Whether the pane is crazed but still standing. A pane that went on to break
## is broken, not cracked -- ask `is_broken()` about that one.
func is_cracked() -> bool:
	return _cracked and not _broken


# --- Building the pane ------------------------------------------------------

## Sizes the collider and the visible pane off `size`. Runs in the editor too, so
## the box in the viewport is the box the ball will hit.
## The material to draw this pane and its shards with: [member surface_material]
## in this pane's own colour.
##
## Only a [BaseMaterial3D] has an albedo to set, so anything else -- a
## [ShaderMaterial], say -- is handed back untouched and keeps whatever colour it
## paints itself. Its own uniforms are the place to change that.
func _surface() -> Material:
	if surface_material == null:
		return null
	if not surface_material is BaseMaterial3D:
		return surface_material
	if _tinted == null:
		_tinted = surface_material.duplicate()
		_retint()
	return _tinted


## Puts [member colour] onto the copy, if there is one yet. Cheap enough to call
## whenever the colour moves, which is every frame while a colour picker is open.
func _retint() -> void:
	var painted := _tinted as BaseMaterial3D
	if painted != null:
		painted.albedo_color = colour


func _rebuild() -> void:
	if not is_node_ready():
		return

	if shape == Shape.DISC:
		var puck := _shape.shape as CylinderShape3D
		if puck == null:
			puck = CylinderShape3D.new()
			_shape.shape = puck
		puck.radius = _disc_radius()
		puck.height = size.y
		_mesh.mesh = _disc_mesh(_disc_radius(), size.y)
	else:
		var box := _shape.shape as BoxShape3D
		if box == null:
			box = BoxShape3D.new()
			_shape.shape = box
		box.size = size

		var pane := _mesh.mesh as BoxMesh
		if pane == null:
			pane = BoxMesh.new()
			_mesh.mesh = pane
		pane.size = size

	_mesh.material_override = _surface()


## A disc, built here rather than taken from [CylinderMesh] for one reason: the
## UVs.
##
## Every shard this pane breaks into is handed the coordinates it was cut at, in
## metres across the pane, as its UV -- so a material that draws anything at all
## on the glass keeps drawing it, in the right place and at the right size, on
## the pieces. A CylinderMesh maps its caps into its own corner of UV space
## instead, and a pattern would jump the moment the pane broke. Same axes as the
## cut cells use, so the two line up exactly.
##
## Wound to match the shards: outward faces, in the order Godot wants them.
func _disc_mesh(radius: float, thickness: float) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()

	var half := thickness * 0.5
	var segments := 48
	var rim := PackedVector3Array()
	for i in segments:
		var angle := TAU * float(i) / float(segments)
		rim.push_back(Vector3(cos(angle) * radius, 0.0, sin(angle) * radius))

	var flat := func(point: Vector3) -> Vector2:
		return Vector2(point.z, point.x)

	for i in segments:
		var a: Vector3 = rim[i]
		var b: Vector3 = rim[(i + 1) % segments]

		# Caps, each wound so its own face points away from the glass.
		for face in 2:
			var lift := half if face == 0 else -half
			var normal := Vector3(0.0, 1.0 if face == 0 else -1.0, 0.0)
			var one := a + Vector3(0.0, lift, 0.0)
			var two := b + Vector3(0.0, lift, 0.0)
			var middle := Vector3(0.0, lift, 0.0)
			if face == 0:
				verts.append_array([middle, one, two])
				uvs.append_array([Vector2.ZERO, flat.call(a), flat.call(b)])
			else:
				verts.append_array([middle, two, one])
				uvs.append_array([Vector2.ZERO, flat.call(b), flat.call(a)])
			for _n in 3:
				normals.push_back(normal)

		# The edge between them.
		var outward := Vector3(a.x, 0.0, a.z).normalized()
		var top_a := a + Vector3(0.0, half, 0.0)
		var top_b := b + Vector3(0.0, half, 0.0)
		var low_a := a - Vector3(0.0, half, 0.0)
		var low_b := b - Vector3(0.0, half, 0.0)
		verts.append_array([low_a, low_b, top_b, low_a, top_b, top_a])
		uvs.append_array([flat.call(a), flat.call(b), flat.call(b),
				flat.call(a), flat.call(b), flat.call(a)])
		for _n in 6:
			normals.push_back(outward)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs

	var built := ArrayMesh.new()
	built.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return built


# --- Cracking ---------------------------------------------------------------

## A hit that was not quite enough. The pane crazes: a web is worked out from
## where the ball landed, drawn onto the face, and kept -- so when the pane does
## go, it goes along the cracks the player was already looking at.
func _craze(impact_point: Vector3) -> void:
	_cracked = true
	_web = _weave(_strike_in_plane(impact_point))

	_draw_cracks()

	var audio := get_node_or_null(^"/root/Audio")
	if audio != null:
		audio.play(CRACK_SOUND, -6.0, _rng.randf_range(1.15, 1.35))


## Lays the web onto the face as a set of thin ribbons, floating just clear of it.
func _draw_cracks() -> void:
	if is_instance_valid(_crack_mesh):
		_crack_mesh.queue_free()

	var thin := _thin_axis()
	var lift := size[thin] * 0.5 + crack_lift

	var verts := PackedVector3Array()

	# Both faces get the web. A pane is see-through and walked over from above,
	# so the underside is on show every bit as much as the top.
	for face in [1.0, -1.0]:
		for column in _web:
			for j in column.size() - 1:
				_ribbon(verts, column[j], column[j + 1], thin, lift * face)

		for i in _web.size():
			var a := _web[i]
			var b := _web[(i + 1) % _web.size()]
			# Ring zero is the strike, where every spoke meets, so a ring drawn
			# there joins a point to itself. The last ring is the edge of the
			# pane -- its frame, not a crack in it. Both ends are skipped.
			for j in range(1, a.size() - 1):
				_ribbon(verts, a[j], b[j], thin, lift * face)

	if verts.is_empty():
		return

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	_crack_mesh = MeshInstance3D.new()
	_crack_mesh.mesh = mesh
	_crack_mesh.material_override = _crack_material()
	_crack_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_crack_mesh)


## One flat sliver of crack, from `a` to `b` across the face.
func _ribbon(into: PackedVector3Array, a: Vector2, b: Vector2, thin: int, lift: float) -> void:
	var along := b - a
	if along.length_squared() < 0.000001:
		return

	var side := Vector2(-along.y, along.x).normalized() * crack_width * 0.5

	var p0 := _in_plane(a - side, thin, lift)
	var p1 := _in_plane(b - side, thin, lift)
	var p2 := _in_plane(b + side, thin, lift)
	var p3 := _in_plane(a + side, thin, lift)

	into.append_array([p0, p1, p2, p0, p2, p3])


func _crack_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = crack_colour
	return mat


# --- Breaking ---------------------------------------------------------------

func _shatter(impact_point: Vector3) -> void:
	_broken = true

	# Deferred because this runs inside the physics step, where taking a shape
	# out from under the solver mid-solve is not allowed.
	_shape.set_deferred("disabled", true)
	_mesh.hide()

	if is_instance_valid(_crack_mesh):
		_crack_mesh.queue_free()
		_crack_mesh = null

	_smash()
	_throw_shards(impact_point)


## The break itself, and then the glass coming down: a scatter of clinks pitched
## well above where the tally uses them, spread over the moment the shards are
## landing. There is no tinkle in the audio library, so one is made here.
func _smash() -> void:
	var audio := get_node_or_null(^"/root/Audio")
	if audio == null:
		return

	if pattern == Pattern.CHUNKS:
		audio.play(SPLINTER_SOUND, 0.0, _rng.randf_range(0.9, 1.05))
		return

	audio.play(CRACK_SOUND, 0.0, _rng.randf_range(0.95, 1.1))

	var scatter := create_tween()
	for i in tinkle_count:
		scatter.tween_interval(_rng.randf_range(0.02, tinkle_window / maxf(tinkle_count, 1)))
		scatter.tween_callback(
			audio.play.bind(TINKLE_SOUND, _rng.randf_range(-14.0, -7.0), _rng.randf_range(1.5, 2.3)))


func _throw_shards(impact_point: Vector3) -> void:
	var host := get_tree().current_scene
	if host == null:
		return

	var thin := _thin_axis()
	var cells := _chunk_cells() if pattern == Pattern.CHUNKS else _glass_cells(impact_point)

	# Orthonormalised so a pane someone scaled anyway cannot hand the shards a
	# doubled size -- they are already built at the size the cuts say.
	var placement := global_transform.orthonormalized()
	var face := placement.basis[thin].normalized()

	for cell in cells:
		_throw_one(host, placement, face, cell, thin, impact_point)


## The glass web, cut into cells. Near the strike they are slivers; out at the
## edges they are panes in their own right.
func _glass_cells(impact_point: Vector3) -> Array[PackedVector2Array]:
	if _web.is_empty():
		_web = _weave(_strike_in_plane(impact_point))

	var cells: Array[PackedVector2Array] = []
	var count := _web.size()

	for i in count:
		var a := _web[i]
		var b := _web[(i + 1) % count]

		# The wedge at the strike itself: both spokes start from the same point,
		# so this one is a triangle rather than a quad.
		cells.append(PackedVector2Array([a[0], a[1], b[1]]))

		for j in range(1, a.size() - 1):
			cells.append(PackedVector2Array([a[j], a[j + 1], b[j + 1], b[j]]))

	return cells


## Where the ball struck, in the pane's own flat coordinates, held just inside
## the edge so the web always has room to open out around it.
func _strike_in_plane(impact_point: Vector3) -> Vector2:
	var thin := _thin_axis()
	var u := (thin + 1) % 3
	var v := (thin + 2) % 3

	var local := global_transform.affine_inverse() * impact_point
	var flat := Vector2(local[u], local[v])

	if shape == Shape.DISC:
		return flat.limit_length(_disc_radius() * 0.82)

	var half_u := size[u] * 0.5
	var half_v := size[v] * 0.5

	return Vector2(
		clampf(flat.x, -half_u * 0.82, half_u * 0.82),
		clampf(flat.y, -half_v * 0.82, half_v * 0.82))


## Builds the web: a point for every spoke crossed with every ring.
##
## Neighbouring cells read the SAME points out of this, which is what makes the
## shards tile the pane exactly -- cut one web, and no two shards can overlap and
## no gap can open between them.
func _weave(strike: Vector2) -> Array[PackedVector2Array]:
	var thin := _thin_axis()
	var half_u := size[(thin + 1) % 3] * 0.5
	var half_v := size[(thin + 2) % 3] * 0.5

	var web: Array[PackedVector2Array] = []

	for angle in _spoke_angles(strike, half_u, half_v):
		var reach := _reach(strike, angle, half_u, half_v)
		var direction := Vector2(cos(angle), sin(angle))

		# Where this spoke's rings fall, as shares of its own run to the edge.
		# Sorted rather than clamped, so the wobble cannot put ring three inside
		# ring two and fold the cells between them inside out.
		var shares: Array[float] = []
		for j in range(1, rings):
			var even := pow(float(j) / rings, ring_growth)
			shares.append(clampf(
				even + _rng.randf_range(-0.5, 0.5) * ring_jitter / rings, 0.04, 0.96))
		shares.sort()

		var column := PackedVector2Array([strike])
		for share in shares:
			column.append(strike + direction * reach * share)
		column.append(strike + direction * reach)

		web.append(column)

	return web


## Which way the spokes run.
##
## Every corner of the pane gets one, and that is not decoration. Between two
## neighbouring spokes the web's outer edge is a straight chord, and a chord
## drawn across a corner cuts it off -- leaving a triangle of pane that no shard
## accounts for. A spoke pinned to each corner puts every chord along an edge.
func _spoke_angles(strike: Vector2, half_u: float, half_v: float) -> PackedFloat32Array:
	var raw: Array[float] = []

	# A disc has no corners to pin anything to; its outer edge is chords all the
	# way round, and the slivers they cut off are the rim of a circle rather than
	# a whole corner of pane.
	if shape != Shape.DISC:
		for corner_u in [-half_u, half_u]:
			for corner_v in [-half_v, half_v]:
				raw.append(atan2(corner_v - strike.y, corner_u - strike.x))

	var step := TAU / spokes
	for i in spokes:
		raw.append(wrapf(i * step + _rng.randf_range(-0.5, 0.5) * step * spoke_jitter, -PI, PI))

	raw.sort()

	# Two spokes almost on top of each other make a shard too thin to be worth
	# handing the solver, so the later one goes.
	var kept := PackedFloat32Array()
	for angle in raw:
		if kept.is_empty() or angle - kept[kept.size() - 1] > 0.05:
			kept.append(angle)

	# And the same check around the join, where the last spoke meets the first.
	if kept.size() > 3 and kept[0] + TAU - kept[kept.size() - 1] < 0.05:
		kept.remove_at(kept.size() - 1)

	return kept


## How far it is from the strike to the edge of the pane along one spoke.
func _reach(strike: Vector2, angle: float, half_u: float, half_v: float) -> float:
	var direction := Vector2(cos(angle), sin(angle))

	if shape == Shape.DISC:
		# Where the spoke leaves the circle: the positive root of
		# |strike + t * direction| = radius, which always exists because the
		# strike is held inside the rim.
		var radius := _disc_radius()
		var along := strike.dot(direction)
		var gap := along * along - strike.length_squared() + radius * radius
		return maxf(-along + sqrt(maxf(gap, 0.0)), 0.001)

	var nearest := INF

	if absf(direction.x) > 0.000001:
		var run := ((half_u if direction.x > 0.0 else -half_u) - strike.x) / direction.x
		if run > 0.0:
			nearest = minf(nearest, run)

	if absf(direction.y) > 0.000001:
		var run := ((half_v if direction.y > 0.0 else -half_v) - strike.y) / direction.y
		if run > 0.0:
			nearest = minf(nearest, run)

	return nearest if nearest < INF else maxf(half_u, half_v)


## The blunt pattern: a ragged grid, the same wherever the pane was hit.
func _chunk_cells() -> Array[PackedVector2Array]:
	var thin := _thin_axis()
	var cuts_u := _cuts(size[(thin + 1) % 3])
	var cuts_v := _cuts(size[(thin + 2) % 3])

	var cells: Array[PackedVector2Array] = []
	for i in cuts_u.size() - 1:
		for j in cuts_v.size() - 1:
			cells.append(PackedVector2Array([
				Vector2(cuts_u[i], cuts_v[j]),
				Vector2(cuts_u[i + 1], cuts_v[j]),
				Vector2(cuts_u[i + 1], cuts_v[j + 1]),
				Vector2(cuts_u[i], cuts_v[j + 1])]))

	return cells


## Where the cuts fall along one side, edge to edge. Only the interior ones
## wander; the outside edges are the pane's own.
func _cuts(length: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var step := length / chunk_cuts

	out.append(-length * 0.5)
	for i in range(1, chunk_cuts):
		var wobble := _rng.randf_range(-1.0, 1.0) * step * chunk_jitter * 0.5
		out.append(-length * 0.5 + step * i + wobble)
	out.append(length * 0.5)

	return out


# --- One shard --------------------------------------------------------------

func _throw_one(host: Node, placement: Transform3D, face: Vector3,
		cell: PackedVector2Array, thin: int, impact_point: Vector3) -> void:
	var area := _area(cell)
	# A cell this thin is a crack, not a shard. Handing the solver a hull with no
	# width in it is asking for trouble, and nobody would see it anyway.
	if area < 0.0004:
		return

	var middle := _centroid(cell)
	var built := _prism(cell, middle, thin)

	var body := RigidBody3D.new()
	body.collision_layer = DEBRIS_LAYER
	body.collision_mask = DEBRIS_MASK
	body.mass = maxf(area * size[thin] * debris_density, 0.05)
	body.gravity_scale = _play_gravity * debris_gravity_scale
	body.physics_material_override = debris_physics

	var shape := CollisionShape3D.new()
	var hull := ConvexPolygonShape3D.new()
	hull.points = built["points"]
	shape.shape = hull
	body.add_child(shape)

	# The mesh is a child rather than the body itself, so the shrink at the end
	# has something to scale. A RigidBody3D's own transform belongs to the
	# physics server, which writes over anything put there.
	var mesh_node := MeshInstance3D.new()
	mesh_node.mesh = built["mesh"]
	mesh_node.material_override = _surface()
	body.add_child(mesh_node)

	host.add_child(body)
	body.global_transform = Transform3D(placement.basis, placement * _in_plane(middle, thin, 0.0))

	# Thrown away from the strike and off the face. The ball's centre sits above
	# the pane it just came through, so "away" carries a downward lean of its own
	# -- the glass is punched through rather than lifted off.
	var away := body.global_position - impact_point
	away = away.normalized() if away.length_squared() > 0.0001 else face

	var spread := _rng.randf_range(0.7, 1.3)
	body.linear_velocity = (away * burst_out + face * burst_off_face) * spread
	body.angular_velocity = Vector3(
		_rng.randf_range(-1.0, 1.0),
		_rng.randf_range(-1.0, 1.0),
		_rng.randf_range(-1.0, 1.0)) * burst_spin

	_debris.append(body)
	_retire(body, shape, mesh_node)


## Stands a flat cell up into a solid: the cell for a top face, the same for a
## bottom, and a wall joining them all the way round.
##
## Every face gets its own copies of the corners it uses, so each can be given
## the one normal that belongs to it. Shared corners would average those together
## and round a shard of glass off into a pebble.
func _prism(cell: PackedVector2Array, middle: Vector2, thin: int) -> Dictionary:
	var half := size[thin] * 0.5
	var count := cell.size()

	var top := PackedVector3Array()
	var bottom := PackedVector3Array()
	for point in cell:
		var flat := point - middle
		top.append(_in_plane(flat, thin, half))
		bottom.append(_in_plane(flat, thin, -half))

	var up := Vector3.ZERO
	up[thin] = 1.0

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()

	for k in range(1, count - 1):
		verts.append_array([top[0], top[k], top[k + 1]])
		uvs.append_array([cell[0], cell[k], cell[k + 1]])
		for _n in 3:
			normals.append(up)

	for k in range(1, count - 1):
		verts.append_array([bottom[0], bottom[k + 1], bottom[k]])
		uvs.append_array([cell[0], cell[k + 1], cell[k]])
		for _n in 3:
			normals.append(-up)

	for k in count:
		var next := (k + 1) % count
		var along := cell[next] - cell[k]
		var outward := _in_plane(Vector2(along.y, -along.x).normalized(), thin, 0.0)

		verts.append_array([bottom[k], bottom[next], top[next], bottom[k], top[next], top[k]])
		uvs.append_array([cell[k], cell[next], cell[next], cell[k], cell[next], cell[k]])
		for _n in 6:
			normals.append(outward)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var hull := PackedVector3Array()
	hull.append_array(top)
	hull.append_array(bottom)

	return {"mesh": mesh, "points": hull}


## Lets a shard lie where it landed, then shrinks it out of existence. The
## collider goes first: a shard halfway through shrinking is still full size to
## the solver, and would hold others up on a floor that is no longer there.
func _retire(body: RigidBody3D, shape: CollisionShape3D, mesh_node: MeshInstance3D) -> void:
	var life := body.create_tween()
	life.tween_interval(debris_lifetime)
	life.tween_callback(shape.set_deferred.bind("disabled", true))
	life.tween_property(mesh_node, "scale", Vector3.ONE * 0.01, debris_fade)
	life.tween_callback(body.queue_free)


# --- Flat and solid ---------------------------------------------------------

## The pane's thinnest side, which is the one nothing is cut across. Found rather
## than assumed, so a wall panel breaks up the same way a floor does.
## How far the ball reaches from its middle. Read off its own collider rather
## than assumed, so a marble built at another size is still met at its surface.
func _measure_ball() -> float:
	for child in _ball.get_children():
		var collider := child as CollisionShape3D
		if collider == null:
			continue
		var sphere := collider.shape as SphereShape3D
		if sphere != null:
			var stretch := collider.global_transform.basis.get_scale()
			return sphere.radius * maxf(stretch.x, maxf(stretch.y, stretch.z))

	push_warning("%s: no sphere collider on the player; assuming a half-metre ball" % name)
	return 0.5


func _thin_axis() -> int:
	# A disc is a cylinder, and a cylinder's axis is Y. Working it out from the
	# size instead would let a disc that happened to be wider than it is round
	# claim a face it has no way of drawing.
	if shape == Shape.DISC:
		return 1
	if size.x <= size.y and size.x <= size.z:
		return 0
	return 1 if size.y <= size.z else 2


## How far a DISC reaches from its middle.
func _disc_radius() -> float:
	return maxf(size.x, size.z) * 0.5


## A point on the pane's flat plane, lifted `off` clear of it.
func _in_plane(flat: Vector2, thin: int, off: float) -> Vector3:
	var out := Vector3.ZERO
	out[(thin + 1) % 3] = flat.x
	out[(thin + 2) % 3] = flat.y
	out[thin] = off
	return out


func _face_normal() -> Vector3:
	var out := Vector3.ZERO
	out[_thin_axis()] = 1.0
	return (global_transform.basis * out).normalized()


func _area(cell: PackedVector2Array) -> float:
	var twice := 0.0
	for i in cell.size():
		var a := cell[i]
		var b := cell[(i + 1) % cell.size()]
		twice += a.x * b.y - b.x * a.y
	return absf(twice) * 0.5


func _centroid(cell: PackedVector2Array) -> Vector2:
	var middle := Vector2.ZERO
	for point in cell:
		middle += point
	return middle / cell.size()
