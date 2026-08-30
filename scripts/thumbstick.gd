class_name Thumbstick
extends Control

## On-screen dynamic thumbstick, drawn from primitives so it needs no art assets.
## `value` is clamped to unit length: +X is right, +Y is up the screen.

## Controls that get first refusal on a touch landing inside them. The stick
## reads raw touches in `_input`, which Godot runs before it hands the event to
## the UI, so a button sitting over the stick's box -- the camera reset, in the
## bottom corner -- would otherwise be swallowed whole and never see the press.
const BLOCKER_GROUP := "blocks_thumbstick"

@export var knob_travel := 250.0 
@export var knob_radius := 90.0
@export var dead_zone := 0.1

var value := Vector2.ZERO

var _touch_index := -1
var _knob_offset := Vector2.ZERO

var _is_active := false
var _base_pos := Vector2.ZERO
var _global_base_pos := Vector2.ZERO


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			if _touch_index == -1 and get_global_rect().has_point(event.position) \
					and not _blocked_at(event.position):
				_touch_index = event.index
				_is_active = true
				_global_base_pos = event.position
				_base_pos = event.position - global_position 
				_move_knob(event.position)
		elif event.index == _touch_index:
			_release()
	elif event is InputEventScreenDrag and event.index == _touch_index:
		_move_knob(event.position)


## Drops any touch in progress and stops listening for new ones. Used when the
## level ends, so the stick neither steers the level nor draws over the menu.
func disable() -> void:
	_release()
	set_process_input(false)
	hide()


## Whether a control that outranks the stick is sitting under this point.
func _blocked_at(pos: Vector2) -> bool:
	for node in get_tree().get_nodes_in_group(BLOCKER_GROUP):
		var control := node as Control
		if control != null and control.is_visible_in_tree() \
				and control.get_global_rect().has_point(pos):
			return true
	return false


func _move_knob(pos: Vector2) -> void:
	_knob_offset = (pos - _global_base_pos).limit_length(knob_travel)
	var v := _knob_offset / knob_travel
	
	value = Vector2(v.x, -v.y)
	if value.length() < dead_zone:
		value = Vector2.ZERO
		
	queue_redraw()


func _release() -> void:
	_touch_index = -1
	_knob_offset = Vector2.ZERO
	value = Vector2.ZERO
	_is_active = false
	queue_redraw()


func _draw() -> void:
	if not _is_active:
		return

	var centre := _base_pos
	draw_circle(centre, knob_travel, Color(1, 1, 1, 0.08))
	draw_arc(centre, knob_travel, 0.0, TAU, 48, Color(1, 1, 1, 0.30), 3.0, true)
	
	var knob := centre + _knob_offset
	draw_circle(knob, knob_radius, Color(1, 1, 1, 0.25))
	draw_arc(knob, knob_radius, 0.0, TAU, 32, Color(1, 1, 1, 0.60), 3.0, true)
