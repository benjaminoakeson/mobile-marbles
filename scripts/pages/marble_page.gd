extends Control

## The marble page, and the dev tools parked at the bottom of it.
##
## The tools are only built in a debug build. `OS.is_debug_build()` is false in
## a release export, so they cannot reach players by accident -- but a debug
## export still shows them, which is what makes them usable on a phone.

@onready var _dev_tools: Control = %DevTools
@onready var _unlock_button: Button = %UnlockAllButton
@onready var _reset_button: Button = %ResetProgressButton
@onready var _dev_status: Label = %DevStatus

## How long the reset stays armed before it forgets it was asked. Without this
## the two taps need not be anywhere near each other in time, and one stray
## press hours after another is enough to wipe the save.
const RESET_ARMED_FOR := 3.0

## Reset asks twice. It throws away every best time, every cleared level and the
## whole bank, and a thumb landing on it while spinning the marble should not be
## able to do that.
var _reset_armed := false
var _disarm_timer: SceneTreeTimer


func _ready() -> void:
	_dev_tools.visible = OS.is_debug_build()
	if not _dev_tools.visible:
		return

	_unlock_button.pressed.connect(_unlock_everything)
	_reset_button.pressed.connect(_reset_progress)

	_disarm()


func _unlock_everything() -> void:
	GameState.dev_unlock_everything()

	# Arming the reset and then wandering off to this button should not leave it
	# armed for whenever the page is next opened.
	_disarm()
	_dev_status.text = "Every world and difficulty unlocked"


func _reset_progress() -> void:
	if not _reset_armed:
		_arm()
		return

	GameState.dev_reset_progress()
	_disarm()
	_dev_status.text = "Progress wiped"


## Asks for the second tap, and gives up waiting for it shortly afterwards.
func _arm() -> void:
	_reset_armed = true
	_reset_button.text = "Tap again to wipe"
	_dev_status.text = "Clears cleared levels, challenges, best times and the bank"

	# The timer is held on to so a second arming cannot leave an older one still
	# running, ready to disarm the new one out from under the player's thumb.
	_disarm_timer = get_tree().create_timer(RESET_ARMED_FOR)
	var armed_with := _disarm_timer

	await armed_with.timeout

	if _reset_armed and _disarm_timer == armed_with:
		_disarm()


func _disarm() -> void:
	_reset_armed = false
	_disarm_timer = null
	_reset_button.text = "Reset All Progress"
	_dev_status.text = ""
