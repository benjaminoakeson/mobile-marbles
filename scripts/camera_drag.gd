class_name CameraDrag
extends Control

## Hands the camera to the player mid-roll. A drag that starts above the
## thumbstick's area swings the rig round with the finger, and the shot then
## stays exactly where they left it -- the automatic chase stands down -- until
## the reset button in the bottom corner gives it back.
##
## The two zones never overlap, so steering and looking are separate touches and
## can run at the same time: the stick owns its own box, this owns everything
## above it.
##
## Touches are read in `_input` rather than `_gui_input` for the same reason the
## stick does it: a drag has to keep being followed after the finger wanders out
## of the control it started in.

## How far the camera turns for each pixel the finger travels sideways, measured
## in the project's 1080-wide reference space. At this rate a swipe right across
## the screen comes to about three quarters of a turn.
@export var drag_degrees_per_pixel := 0.25

## How far sideways a touch must travel before it counts as a camera drag. Below
## this it is a tap on the scenery, and the shot is left alone.
@export var drag_slop := 12.0

## Where the drag area stops when there is no thumbstick to measure against, as
## a fraction of the screen height.
@export var fallback_zone_height := 0.5

## How long the reset button takes to fade in or out.
@export var button_fade := 0.15

@onready var _reset_button: Button = %ResetCameraButton

var _camera: CameraFollow
var _stick: Control

var _touch_index := -1
var _last_x := 0.0
var _travelled := 0.0
var _turning := false
var _fade: Tween


func _ready() -> void:
	# Reached by group when the level ends, alongside the stick -- see
	# `disable()`.
	add_to_group("camera_control")

	# Both live elsewhere in the level: the rig is a 3D node beside the UI layer,
	# the stick is a sibling of the HUD. Found by group so no level has to wire
	# either of them up.
	_camera = get_tree().get_first_node_in_group("camera_rig") as CameraFollow
	_stick = get_tree().get_first_node_in_group("thumbstick") as Control

	if _camera == null:
		push_warning("CameraDrag: no CameraFollow in group 'camera_rig'; drags will do nothing")
	if _stick == null:
		push_warning("CameraDrag: no Thumbstick in group 'thumbstick'; falling back to a fixed drag zone")

	_reset_button.pressed.connect(_on_reset_pressed)
	Audio.wire_clicks(_reset_button)

	# Nothing to reset until the player has moved the camera themselves.
	_reset_button.hide()
	_reset_button.modulate.a = 0.0

	if _camera != null:
		_camera.manual_yaw_changed.connect(_on_manual_yaw_changed)


## Drops any drag in progress and stops listening. Called when the level ends,
## so the camera cannot be dragged around behind the victory or game over menu.
func disable() -> void:
	_touch_index = -1
	_turning = false
	set_process_input(false)
	_hide_reset()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			if _touch_index == -1 and _in_drag_zone(event.position):
				_touch_index = event.index
				_last_x = event.position.x
				_travelled = 0.0
				_turning = false
		elif event.index == _touch_index:
			_touch_index = -1
			_turning = false
	elif event is InputEventScreenDrag and event.index == _touch_index:
		# Stepped off the last position rather than read from `relative`, which
		# is only filled in by events the platform itself generated -- anything
		# replayed through `Input.parse_input_event` arrives with it at zero.
		var drag := event as InputEventScreenDrag
		var sideways := drag.position.x - _last_x
		_last_x = drag.position.x
		_drag(sideways)


func _drag(sideways: float) -> void:
	if _camera == null:
		return

	# Hold off until the finger has committed to going sideways, then follow it
	# for the rest of the touch -- the slop is spent once, not on every wobble.
	if not _turning:
		_travelled += absf(sideways)
		if _travelled < drag_slop:
			return
		_turning = true

	# Dragging right turns the view right, the way turning your head does, which
	# slides the world left under the finger. Godot's yaw runs the other way
	# round -- positive is anticlockwise seen from above -- hence the sign.
	_camera.rotate_yaw(-deg_to_rad(drag_degrees_per_pixel * sideways))


## Everything clear above the stick's box. Deliberately measured off the stick
## rather than fixed, because levels place the stick themselves and the line has
## to move with it.
func _in_drag_zone(pos: Vector2) -> bool:
	if _reset_button.visible and _reset_button.get_global_rect().has_point(pos):
		return false

	var bottom := fallback_zone_height * get_viewport_rect().size.y
	if _stick != null and _stick.is_visible_in_tree():
		bottom = _stick.get_global_rect().position.y

	return pos.y < bottom


func _on_reset_pressed() -> void:
	if _camera != null:
		_camera.release_manual_yaw()


func _on_manual_yaw_changed(is_manual: bool) -> void:
	if is_manual:
		_show_reset()
	else:
		_hide_reset()


func _show_reset() -> void:
	_reset_button.show()
	_fade_button_to(1.0)


func _hide_reset() -> void:
	if not _reset_button.visible:
		return

	# Hidden outright at the end rather than just faded out: while it is visible
	# it goes on taking touches off the thumbstick underneath it.
	_fade_button_to(0.0).tween_callback(_reset_button.hide)


func _fade_button_to(alpha: float) -> Tween:
	if _fade != null and _fade.is_valid():
		_fade.kill()
	_fade = create_tween()
	_fade.tween_property(_reset_button, "modulate:a", alpha, button_fade)
	return _fade
