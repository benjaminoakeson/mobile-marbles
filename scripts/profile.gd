extends Control

## The profile button in the menu's top corner, and the sheet of settings it
## opens.
##
## It sits on the menu itself rather than on any one page, so it is there
## whichever tab is open and stays put while a page is dug through -- the same
## reasoning as the bar of tabs along the bottom.
##
## Nothing here owns a setting. Every row reads [GameState] and hands what the
## player picked straight back to it; whatever is affected hears about it from
## there, mid-level if that is where it is. This sheet is only somewhere to say
## it.
##
## The dev tools are the exception, and they are here for the same reason the
## settings are: they belong to nothing on any page, and they were taking up room
## on the levels page next to the button that actually gets pressed. They are the
## last row, in debug builds only.

## How long the sheet takes to fade up or away.
@export var fade_time := 0.14

## Borrowed from the menu's own tab bar, so a choice made here looks like the
## choice the tabs make.
const CHOSEN := Color(0.20392157, 0.5019608, 0.24705882, 1)
const UNCHOSEN := Color(0.13333334, 0.15294118, 0.17254902, 1)
const CAPTION := Color(0.63529414, 0.6784314, 0.6509804, 1)

const CHOICE_HEIGHT := 96.0
const CHOICE_RADIUS := 16
const ROW_GAP := 34

## What the wipe is labelled in. Both dev tools are built from the same pill, and
## this is the only thing telling them apart.
const DESTRUCTIVE_TEXT := Color(1, 0.63529414, 0.63529414, 1)

## The face the tools sit on. A shade up from the unchosen pill the settings use,
## which is the sheet's own colour: a switch that is off can afford to disappear
## into the background, but a button you are meant to press cannot.
const DEV_FACE := Color(0.20392157, 0.22745098, 0.25490196, 1)

## How long the wipe stays armed before it forgets it was asked. Without this the
## two taps need not be anywhere near each other in time, and one stray press
## minutes after another is enough to lose the save.
const RESET_ARMED_FOR := 3.0

@onready var _button: Button = %ProfileButton
@onready var _sheet: Control = %Sheet
@onready var _backdrop: Button = %Backdrop
@onready var _close: Button = %CloseButton
@onready var _rows: VBoxContainer = %Rows
@onready var _stats: Label = %Stats

var _fade: Tween

## The two dev buttons, held on to so pressing one can report back through its
## own label -- which saves the sheet needing a status line of its own.
var _dev_unlock_button: Button
var _dev_reset_button: Button

## The wipe asks twice. The first press only arms it; the second is the one that
## throws away every best time, every cleared level and the whole bank.
var _reset_armed := false
var _disarm_timer: SceneTreeTimer


func _ready() -> void:
	_button.pressed.connect(_open)
	_close.pressed.connect(_shut)

	# Anywhere off the sheet shuts it, which is the gesture a sheet like this is
	# expected to answer to -- the cross is for people who look for one.
	_backdrop.pressed.connect(_shut)

	_build()

	_sheet.hide()
	_sheet.modulate.a = 0.0

	# Covers the rows built above as well as the button and the cross. Harmless
	# over the ones the menu will wire again later: a click is only ever
	# connected once.
	Audio.wire_clicks(self)


func _open() -> void:
	# Read fresh on the way up rather than kept in step: this is the only thing
	# that shows them, and it has been off screen since the last time they could
	# have changed.
	_refresh_stats()

	_sheet.show()
	_fade_to(1.0)


func _shut() -> void:
	# A sheet reopened later must not start one tap from a wipe, with nothing on
	# screen saying so.
	_disarm()

	_fade_to(0.0).tween_callback(_sheet.hide)


func _fade_to(alpha: float) -> Tween:
	if _fade != null and _fade.is_valid():
		_fade.kill()

	_fade = create_tween()
	_fade.tween_property(_sheet, "modulate:a", alpha, fade_time)
	return _fade


func _build() -> void:
	_rows.add_theme_constant_override("separation", ROW_GAP)
	_refresh_stats()

	_add_choice("HANDEDNESS", ["RIGHT", "LEFT"],
			1 if GameState.left_handed else 0,
			func(pick: int) -> void: GameState.set_left_handed(pick == 1))

	# The labels are in the enum's own order, so the button's place in the row is
	# the value it stands for and nothing has to map between them.
	_add_choice("JOYSTICK", ["FREE", "8-DIR", "LAST USED"],
			GameState.stick_preference,
			func(pick: int) -> void: GameState.set_stick_preference(pick))

	_add_slider("MUSIC", GameState.music_volume, GameState.set_music_volume)
	_add_slider("EFFECTS", GameState.sfx_volume, GameState.set_sfx_volume)

	# `OS.is_debug_build()` is false in a release export, so the tools cannot
	# reach players by accident -- but a debug export still shows them, which is
	# what makes them usable on a phone.
	if OS.is_debug_build():
		_add_dev_tools()


func _refresh_stats() -> void:
	_stats.text = "%s gems banked   ·   %d levels cleared" % [
			GameState.format_gems(GameState.bank), _cleared_count()]


## How many levels have ever been finished, across every set.
func _cleared_count() -> int:
	var total := 0
	for set_name in GameState.cleared_levels:
		total += (GameState.cleared_levels[set_name] as Array).size()
	return total


## A caption over a row of buttons, one of which is on. `on_pick` is handed the
## index of whichever was tapped.
func _add_choice(caption: String, options: Array, chosen: int, on_pick: Callable) -> void:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.add_child(_caption(caption))

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 14)

	# One group, so turning one on turns the others off without any of them
	# having to know how many there are.
	var group := ButtonGroup.new()

	for index in options.size():
		var button := Button.new()
		button.text = options[index]
		button.toggle_mode = true
		button.button_group = group
		button.custom_minimum_size = Vector2(0.0, CHOICE_HEIGHT)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 34)
		button.add_theme_color_override("font_color", CAPTION)
		button.add_theme_color_override("font_hover_color", Color.WHITE)
		button.add_theme_color_override("font_pressed_color", Color.WHITE)
		button.add_theme_stylebox_override("normal", _pill(UNCHOSEN))
		button.add_theme_stylebox_override("hover", _pill(UNCHOSEN))
		button.add_theme_stylebox_override("pressed", _pill(CHOSEN))
		button.add_theme_stylebox_override("focus", _pill(Color(0, 0, 0, 0)))

		# Set without the signal: which one is already on is a fact being shown,
		# not a choice being made all over again.
		button.set_pressed_no_signal(index == chosen)
		button.pressed.connect(on_pick.bind(index))

		bar.add_child(button)

	row.add_child(bar)
	_rows.add_child(row)


## A caption over a slider, with what it is set to read out beside it.
##
## `on_move` is called the whole way through the drag so the change is heard as
## it is made -- a volume that only answered when the finger came off would be
## set by guesswork. Only the writing to disk waits for the end of it.
func _add_slider(caption: String, level: float, on_move: Callable) -> void:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var header := HBoxContainer.new()
	var name_label := _caption(caption)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(name_label)

	var readout := _caption("")
	readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(readout)
	row.add_child(header)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = level
	slider.custom_minimum_size = Vector2(0.0, 72.0)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	readout.text = _percent(level)
	slider.value_changed.connect(func(moved: float) -> void:
		readout.text = _percent(moved)
		on_move.call(moved))

	# One write when the finger comes off, rather than one per pixel of the drag.
	slider.drag_ended.connect(func(changed: bool) -> void:
		if changed:
			GameState.save_progress())

	row.add_child(slider)
	_rows.add_child(row)


# --- Dev tools ---
# Debug builds only. Both reach straight into GameState and move the world under
# whatever page is open behind this sheet, which is why GameState says so -- see
# `progress_changed`.

func _add_dev_tools() -> void:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.add_child(_caption("DEV TOOLS"))

	_dev_unlock_button = _action("Unlock Everything", Color.WHITE, _unlock_everything)
	row.add_child(_dev_unlock_button)

	_dev_reset_button = _action("Delete Everything", DESTRUCTIVE_TEXT, _reset_progress)
	row.add_child(_dev_reset_button)

	_rows.add_child(row)


func _unlock_everything() -> void:
	GameState.dev_unlock_everything()

	# Arming the wipe and then reaching for this button instead should not leave
	# it armed behind a shut sheet.
	_disarm()
	_dev_unlock_button.text = "Unlocked \u2713"

	_refresh_stats()


## Asks twice. The first press only arms it; the second is the one that wipes.
func _reset_progress() -> void:
	if not _reset_armed:
		_arm()
		return

	GameState.dev_reset_progress()
	_reset_armed = false
	_disarm_timer = null
	_dev_reset_button.text = "Deleted \u2713"

	_refresh_stats()


func _arm() -> void:
	_reset_armed = true
	_dev_reset_button.text = "Tap again to wipe"

	# The timer is held on to so a second arming cannot leave an older one still
	# running, ready to disarm the new one out from under the player's thumb.
	_disarm_timer = get_tree().create_timer(RESET_ARMED_FOR)
	var armed_with := _disarm_timer

	await armed_with.timeout

	if _reset_armed and _disarm_timer == armed_with:
		_disarm()


## Puts the wipe back to needing two taps.
func _disarm() -> void:
	_reset_armed = false
	_disarm_timer = null

	if is_instance_valid(_dev_reset_button):
		_dev_reset_button.text = "Delete Everything"


## One full-width pill that does something when tapped, built off the same parts
## as the choice rows so a tool looks like it belongs on this sheet.
func _action(text: String, colour: Color, on_press: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0.0, CHOICE_HEIGHT)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 34)
	button.add_theme_color_override("font_color", colour)
	button.add_theme_color_override("font_hover_color", colour)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_stylebox_override("normal", _pill(DEV_FACE))
	button.add_theme_stylebox_override("hover", _pill(DEV_FACE))
	button.add_theme_stylebox_override("pressed", _pill(CHOSEN))
	button.add_theme_stylebox_override("focus", _pill(Color(0, 0, 0, 0)))
	button.pressed.connect(on_press)

	return button


func _percent(level: float) -> String:
	return "%d%%" % roundi(level * 100.0)


func _caption(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 30)
	label.add_theme_color_override("font_color", CAPTION)
	return label


func _pill(colour: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = colour
	box.corner_radius_top_left = CHOICE_RADIUS
	box.corner_radius_top_right = CHOICE_RADIUS
	box.corner_radius_bottom_right = CHOICE_RADIUS
	box.corner_radius_bottom_left = CHOICE_RADIUS
	return box
