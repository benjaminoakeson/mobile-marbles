extends CanvasLayer

## Shown when the lives run out.
##
## What that means depends on how the level was being played. A free-play level
## is just spent -- the way out is the menu. A challenge run has FAILED: the set
## has to be taken again from its first level for the next chapter to open,
## so that run is offered straight from here.

## How long the panel takes to fade up.
@export var fade_duration := 0.4

@onready var _panel: Control = %Panel
@onready var _subtitle: Label = %Subtitle
@onready var _retry_button: Button = %RetryButton
@onready var _menu_button: Button = %MenuButton

## Read before anything is reset -- `reset_run()` drops the run back to free
## play, which would make a failed challenge look like an ordinary game over.
var _failed_challenge := false


func _ready() -> void:
	_failed_challenge = GameState.is_challenge_run()

	_menu_button.pressed.connect(_go_back)
	_retry_button.pressed.connect(_retry)
	_retry_button.visible = _failed_challenge

	_subtitle.text = "Out of lives.\nThe run failed." if _failed_challenge else "Out of lives."

	Audio.wire_clicks(self)

	# The run is over, so the stick should stop steering the level behind this.
	var stick := get_tree().get_first_node_in_group("thumbstick") as Thumbstick
	if stick != null:
		stick.disable()

	# The camera drag goes the same way, and takes its reset button off the
	# screen before this panel fades up over it.
	var camera_control := get_tree().get_first_node_in_group("camera_control") as CameraDrag
	if camera_control != null:
		camera_control.disable()

	_panel.modulate.a = 0.0
	create_tween().tween_property(_panel, "modulate:a", 1.0, fade_duration)


## Takes the same challenge on again from the top of its set.
func _retry() -> void:
	_lock()

	var first := GameState.restart_challenge()
	if first.is_empty():
		# Nothing to go back to, which should not happen from a challenge -- but
		# stranding the player on a dead screen would be worse than the menu.
		_go_back()
		return

	if get_tree().change_scene_to_file(first) != OK:
		push_error("GameOver: could not load '%s'" % first)
		_unlock()


func _go_back() -> void:
	_lock()

	GameState.reset_run()

	var result := get_tree().change_scene_to_file(LevelManager.MENU)
	if result != OK:
		push_error("GameOver: could not load '%s' (error %d)" % [LevelManager.MENU, result])
		_unlock()


## Both buttons go dead together: a fat finger can land on each of them before
## the scene swaps, and the second press would cancel the first.
func _lock() -> void:
	_retry_button.disabled = true
	_menu_button.disabled = true


func _unlock() -> void:
	_retry_button.disabled = false
	_menu_button.disabled = false
