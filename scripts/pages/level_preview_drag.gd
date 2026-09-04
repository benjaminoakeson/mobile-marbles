extends Control

## Catches drags over the menu's level preview and turns it, the way the marble
## page's overlay rolls its marble. Sits on top of the preview's
## SubViewportContainer and above the invisible button that opens the selector,
## so a touch never reaches the 3D viewport underneath.
##
## A TAP still opens the selector. The button underneath owns that, so a press
## that never travels is handed back to it rather than reimplemented here; only
## a press that travels becomes a drag, and a drag never opens anything.

## How far a finger may wander, in pixels, and still count as a tap.
@export var tap_slop := 12.0

@export var preview_path: NodePath = ^"../Preview/SubViewport/LevelPreview"
@export var tap_button_path: NodePath = ^"../PreviewButton"

var _preview: Node3D
var _tap_button: BaseButton
var _pressed := false
var _travelled := 0.0

## Where the finger was last seen. Movement is measured between positions
## rather than read off an event's own `relative`, which a synthesised or
## replayed event is free to leave at zero.
var _last_position := Vector2.ZERO


func _ready() -> void:
	_preview = get_node_or_null(preview_path) as Node3D
	_tap_button = get_node_or_null(tap_button_path) as BaseButton
	if _preview == null:
		push_warning("LevelPreviewDrag: no preview at '%s'" % preview_path)


func _gui_input(event: InputEvent) -> void:
	if _preview == null:
		return

	# Whether the finger is down is tracked separately from the movement, so the
	# turn never has to trust a motion event's button mask -- synthesised events
	# routinely arrive with that field empty.
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		_set_pressed(touch.pressed, touch.position)
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT:
			_set_pressed(button.pressed, button.position)
	elif event is InputEventScreenDrag:
		_move((event as InputEventScreenDrag).position)
	elif event is InputEventMouseMotion and _pressed:
		_move((event as InputEventMouseMotion).position)


func _set_pressed(down: bool, at: Vector2) -> void:
	if down:
		_pressed = true
		_travelled = 0.0
		_last_position = at
		return

	if not _pressed:
		return
	_pressed = false
	_preview.end_drag()

	# Never went anywhere: that was a tap, and the tap is the button's.
	if _travelled < tap_slop and _tap_button != null:
		_tap_button.pressed.emit()


func _move(to: Vector2) -> void:
	if not _pressed:
		return

	var relative := to - _last_position
	_last_position = to
	_travelled += relative.length()
	if _travelled < tap_slop:
		return

	_preview.begin_drag()
	_preview.turn(relative)
