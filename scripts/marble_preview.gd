extends Control

## Catches drags over the menu's marble and rolls it. Sits on top of the
## SubViewportContainer so the touch never reaches the 3D viewport underneath.
##
## The marble turns like a trackball: it rolls whichever way the finger goes, as
## far as the finger takes it, with no upright to snap back to.

## Radians of roll per pixel dragged.
@export var drag_sensitivity := 0.002

## How fast the marble turns on its own while nobody is touching it, in degrees
## a second. Zero holds it still.
@export var idle_spin_degrees := 12.0

@export var marble_path: NodePath = ^"../SubViewport/Marble"

var _marble: Node3D
var _is_dragging := false


func _ready() -> void:
	_marble = get_node_or_null(marble_path) as Node3D
	if _marble == null:
		push_warning("MarblePreview: no marble at '%s'" % marble_path)


func _process(delta: float) -> void:
	if _marble == null or _is_dragging:
		return

	_turn(Vector3.UP * deg_to_rad(idle_spin_degrees) * delta)


func _gui_input(event: InputEvent) -> void:
	if _marble == null:
		return

	# Whether the finger is down is tracked separately from the movement, so the
	# roll never has to trust a motion event's button mask -- synthesised events
	# routinely arrive with that field empty.
	if event is InputEventScreenTouch:
		_is_dragging = (event as InputEventScreenTouch).pressed
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT:
			_is_dragging = button.pressed
	elif event is InputEventScreenDrag:
		_spin((event as InputEventScreenDrag).relative)
	elif event is InputEventMouseMotion and _is_dragging:
		_spin((event as InputEventMouseMotion).relative)


func _spin(relative: Vector2) -> void:
	# Roll about the axis at right angles to the drag, lying in the plane of the
	# screen. Dragging right rolls the face right, dragging down rolls it down,
	# and a diagonal drag does both at once -- so the surface under the finger
	# travels with the finger. Screen Y counts downwards, which is already the
	# direction a positive turn about X carries the front of the marble.
	_turn(Vector3(relative.y, relative.x, 0.0) * drag_sensitivity)


## Rolls the marble by an axis-angle turn, given as an axis scaled by its angle.
func _turn(turn: Vector3) -> void:
	var angle := turn.length()
	if angle < 0.00001:
		return

	# Multiplying on the LEFT turns the marble about the camera's axes rather
	# than its own, which is what keeps a drag meaning the same thing however far
	# the marble has already rolled. Composing rotations forever accumulates
	# rounding error, so the basis is squared up again each time.
	_marble.basis = (Basis(turn / angle, angle) * _marble.basis).orthonormalized()
