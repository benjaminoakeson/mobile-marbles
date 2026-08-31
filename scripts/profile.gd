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

@onready var _button: Button = %ProfileButton
@onready var _sheet: Control = %Sheet
@onready var _backdrop: Button = %Backdrop
@onready var _close: Button = %CloseButton
@onready var _rows: VBoxContainer = %Rows
@onready var _stats: Label = %Stats

var _fade: Tween


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
