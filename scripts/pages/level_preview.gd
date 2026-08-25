extends Node3D

## Shows a level in the menu, turning slowly on the spot so it can be looked
## over before it is played.
##
## The level scene is loaded whole and then stripped back to the parts worth
## looking at -- the ball, the level's own camera, the on-screen controls and
## the trigger volumes all go -- and what is left is frozen. Nothing here plays
## the level: it only poses for the picture.

## How fast the view goes round the level, in degrees a second.
@export var spin_degrees := 8.0

## How far above the level the camera sits, in degrees off the horizontal.
##
## Steep, because levels are long thin runs: from low down one turns end-on and
## all but disappears, while from above it keeps its length whichever way it is
## facing.
@export var pitch_degrees := 50.0

## Slack left around the level, as a multiple of its size. Above 1.0 so a long
## level does not brush the edges of the frame as it comes round.
@export var margin := 1.05

@onready var _stage: Node3D = $Stage
@onready var _rig: Node3D = $Rig
@onready var _camera: Camera3D = $Rig/Camera3D

## Half the diagonal of what is on show. The level is framed as a ball of this
## size, so it fits at every angle of the turn rather than only the one it
## started at.
var _radius := 1.0

## What is on the stage, so asking for the same level twice does not rebuild it.
var _shown := ""


func _ready() -> void:
	# How far back the camera has to sit depends on how wide the viewport is,
	# which is not settled until the page has been laid out -- and changes again
	# whenever the window does.
	get_viewport().size_changed.connect(_aim_camera)


func _process(delta: float) -> void:
	_rig.rotate_y(deg_to_rad(spin_degrees) * delta)


## Puts a level on show. An empty path clears the stage, for a slot with nothing
## built for it yet.
func show_level(path: String) -> void:
	if path == _shown:
		return
	_shown = path

	_clear_stage()
	if path.is_empty():
		return

	var scene := load(path) as PackedScene
	if scene == null:
		push_error("LevelPreview: could not load '%s'" % path)
		return

	var level := scene.instantiate() as Node3D
	if level == null:
		push_error("LevelPreview: '%s' is not a 3D scene" % path)
		return

	_strip(level)

	# Frozen before it ever reaches the tree, so the level's own scripts never
	# get a frame in which to tilt it, bob its gems or breathe its goal ring.
	level.process_mode = Node.PROCESS_MODE_DISABLED
	_stage.add_child(level)

	_measure(level)
	_aim_camera()

	# Every level starts its turn from the same angle, so switching between two
	# of them compares like with like.
	_rig.rotation = Vector3.ZERO


func _clear_stage() -> void:
	for child in _stage.get_children():
		_stage.remove_child(child)
		child.queue_free()


## Throws away the parts of a level that would try to play it rather than pose
## in it. Done before the level is in the tree, so none of them ever run.
func _strip(level: Node3D) -> void:
	for child in level.get_children():
		if _is_scenery(child):
			continue

		level.remove_child(child)
		child.free()


## Whether a level's top-level node is part of the view.
##
## Out go the on-screen controls, the camera rig, the ball, and the volumes that
## watch for a ball that is no longer there. Hidden CSG goes too:
## it is the shape a level was cut from, already baked into the mesh that shows,
## and rebuilding it for a picture nobody sees is wasted work.
func _is_scenery(node: Node) -> bool:
	if node is CanvasLayer or node is Area3D:
		return false

	# The level's camera arrives as a rig with the camera buried inside it, so
	# looking at the child's own type is not enough. Left in, it would try to
	# chase a ball that is not there, and could take the view over from ours.
	if node is Camera3D or not node.find_children("*", "Camera3D", true, false).is_empty():
		return false

	if node is CSGShape3D and not (node as CSGShape3D).visible:
		return false

	return not node.is_in_group("player")


## Works out where the level is and how big it is, from the meshes that will
## actually be drawn.
func _measure(level: Node3D) -> void:
	var bounds := AABB()
	var found := false

	for node in level.find_children("*", "GeometryInstance3D", true, false):
		var geometry := node as GeometryInstance3D
		if not geometry.is_visible_in_tree():
			continue

		var box := geometry.global_transform * geometry.get_aabb()
		bounds = box if not found else bounds.merge(box)
		found = true

	if not found:
		# Nothing to look at. Better to leave the camera where it was than to
		# dive into the middle of an empty stage.
		return

	_rig.global_position = bounds.get_center()
	_radius = maxf(bounds.size.length() * 0.5, 0.001)


## Hangs the camera off the rig at a fixed angle and distance. The rig sits in
## the middle of the level and turns, which walks the camera round it.
func _aim_camera() -> void:
	var pitch := deg_to_rad(pitch_degrees)
	var distance := _fit_distance()

	_camera.position = Vector3(0.0, distance * sin(pitch), distance * cos(pitch))
	_camera.rotation = Vector3(-pitch, 0.0, 0.0)


## How far back the camera has to sit for a ball of `_radius` to fit the frame,
## measured against whichever way the viewport is narrower. On a phone held
## upright that is across, not up.
func _fit_distance() -> float:
	var half_up := deg_to_rad(_camera.fov) * 0.5
	var size := get_viewport().get_visible_rect().size
	var half_across := atan(tan(half_up) * size.x / maxf(size.y, 1.0))

	return _radius * margin / sin(minf(half_up, half_across))
