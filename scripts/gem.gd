@tool
extends Area3D

## A pickup worth points. One scene covers every gem -- pick the kind in the
## inspector and the matching mesh is the one that shows.
##
## Taking one sprays a burst of mini gems of that same kind, then the gem itself
## disappears.

enum Kind { EMERALD, SAPPHIRE, RUBY, TOPAZ, AMETHYST, DIAMOND }

const VALUES := {
	Kind.EMERALD: 10,
	Kind.SAPPHIRE: 25,
	Kind.RUBY: 50,
	Kind.TOPAZ: 100,
	Kind.AMETHYST: 150,
	Kind.DIAMOND: 250,
}

## The sound a gem makes on the way out. Preloaded rather than reached for
## through the Audio autoload, which a @tool script cannot name -- see below.
const PICKUP_SOUND := preload("res://audio/Gem.wav")

## What the diamond takes instead. It is the rarest gem and worth the most, so
## it gets its own sound; every other kind uses the one above.
const DIAMOND_PICKUP_SOUND := preload("res://audio/DiamondGem.wav")

const MESH_NAMES := {
	Kind.EMERALD: "Emerald",
	Kind.SAPPHIRE: "Sapphire",
	Kind.RUBY: "Ruby",
	Kind.TOPAZ: "Topaz",
	Kind.AMETHYST: "Amethyst",
	Kind.DIAMOND: "Diamond",
}

## Which gem this one is. Changing it swaps the mesh in the editor too, so a
## level reads at a glance.
@export var kind := Kind.EMERALD:
	set(value):
		kind = value
		_show_only_the_chosen_gem()

## How long the gem takes to pop out of existence once taken.
@export var collect_duration := 0.18

@export_group("Idle Motion")

## How far the gem drifts above and below where it was placed, in metres.
@export var bob_height := 0.08

## How quickly it breathes, in radians a second.
@export var bob_speed := 2.0

## Phase shift per metre of placement, so a row of gems breathes out of step
## instead of moving as one block. Zero puts them all in lockstep. The same
## offset sets each gem's starting angle, so neighbours do not face identically.
@export var bob_stagger := 0.6

## How fast the gem turns on the spot, in degrees a second. Negative reverses it.
@export var spin_degrees := 60.0

var _taken := false
var _bob_time := 0.0
var _rest_y := 0.0
var _rest_yaw := 0.0
var _bob_phase := 0.0
var _spin_angle := 0.0

@onready var _burst: GPUParticles3D = get_node_or_null("Burst") as GPUParticles3D


func _ready() -> void:
	_show_only_the_chosen_gem()

	# Where the gem was placed. The hover is measured from here, so it drifts
	# around its authored spot rather than away from it.
	_rest_y = position.y
	_rest_yaw = rotation.y
	_bob_phase = (position.x + position.z) * bob_stagger

	# The rest is gameplay, and the editor has no business running it.
	if Engine.is_editor_hint():
		return

	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	# Never in the editor -- a gem that wanders while you are placing it is a
	# nuisance, and it would leave the scene looking modified. And once taken it
	# is on its way out, so there is nothing left worth breathing.
	if Engine.is_editor_hint() or _taken:
		return

	# Bobbing in LOCAL space, so "up" is the level's up. The gem hangs off the
	# tilting body, and a world-space bob would drift it through the floor as
	# soon as the track leaned over.
	_bob_time += delta
	position.y = _rest_y + sin(_bob_time * bob_speed + _bob_phase) * bob_height

	# Turned about the LOCAL up for the same reason, and rebuilt from an angle
	# rather than nudged, so the yaw cannot drift. Wrapping a full turn is not a
	# jump -- a full turn and none at all leave the gem facing the same way.
	_spin_angle = wrapf(_spin_angle + deg_to_rad(spin_degrees) * delta, 0.0, TAU)
	rotation.y = _rest_yaw + _bob_phase + _spin_angle


## Whether this gem has already been picked up. Read by the all-gems check,
## which has to tell a gem still waiting from one mid-way through its pop.
func is_taken() -> bool:
	return _taken


func _show_only_the_chosen_gem() -> void:
	var shapes := get_node_or_null("CollisionShape3D")
	if shapes == null:
		return

	for gem_kind in MESH_NAMES:
		var mesh := shapes.get_node_or_null(MESH_NAMES[gem_kind]) as MeshInstance3D
		if mesh != null:
			mesh.visible = gem_kind == kind


func _on_body_entered(body: Node3D) -> void:
	if _taken:
		return
	if not (body is RigidBody3D and body.is_in_group("player")):
		return

	_taken = true

	# Looked up by path rather than by the bare `GameState` name. This is a @tool
	# script, and autoloads do not exist in the editor, so the name does not even
	# compile there. This line only ever runs in game, where the path resolves.
	var state := get_node_or_null(^"/root/GameState")
	if state != null:
		state.collect_gem(VALUES[kind])

	# Looked up the same way and for the same reason as GameState above.
	var audio := get_node_or_null(^"/root/Audio")
	if audio != null:
		audio.play(DIAMOND_PICKUP_SOUND if kind == Kind.DIAMOND else PICKUP_SOUND)

	# Stop watching straight away, or a ball still inside the shape can trip the
	# gem again on the way out. Both deferred because we are inside the area's
	# own signal, part way through the physics step. Taking the shape out as well
	# as the monitoring means the pop below is never handed to the solver.
	set_deferred("monitoring", false)
	var shape := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape != null:
		shape.set_deferred("disabled", true)

	_spray()
	_pop()


## One burst of mini gems, in every direction. The shards are drawn with this
## gem's own mesh, which carries its own material, so an emerald throws emerald
## shards and a ruby throws ruby ones with nothing else to set up.
func _spray() -> void:
	if _burst == null:
		return

	var mesh := _chosen_mesh()
	if mesh != null:
		_burst.draw_pass_1 = mesh.mesh

	_burst.restart()


## A quick swell and shrink, so a gem reads as taken rather than blinking out of
## existence mid-frame.
##
## Only the mesh is scaled, never the gem itself: the burst hangs off this node,
## and shrinking the node would shrink the spray along with it.
func _pop() -> void:
	var mesh := _chosen_mesh()
	var swell := collect_duration * 0.4

	var tween := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	if mesh != null:
		tween.tween_property(mesh, "scale", mesh.scale * 1.5, swell)
		tween.tween_property(mesh, "scale", mesh.scale * 0.02, collect_duration - swell)

	# The particles belong to this node, so freeing it early would cut the spray
	# off mid-flight. Wait the burst out first.
	tween.tween_interval(_burst_duration())
	tween.tween_callback(queue_free)


func _chosen_mesh() -> MeshInstance3D:
	var shapes := get_node_or_null("CollisionShape3D")
	if shapes == null:
		return null
	return shapes.get_node_or_null(MESH_NAMES[kind]) as MeshInstance3D


## Longest a shard can live, plus a little slack.
func _burst_duration() -> float:
	if _burst == null:
		return 0.0
	return _burst.lifetime * (1.0 + _burst.randomness) + 0.1
