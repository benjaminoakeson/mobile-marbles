extends CanvasLayer

## Victory overlay. The goal ring spawns this once the ball is airborne.
##
## The score is counted up rather than stated. Each award the level was worth
## shows on its own for a beat, flies into the running total, and the total
## kicks and throbs while it eats the points -- so the player watches the number
## being earned instead of reading a finished sum. A tap anywhere hurries it.
##
## What the awards are, and the order they land in, is entirely the goal ring's
## business: this reads `GameState.last_award` and plays whatever is in it.

## How long the panel takes to fade up, so it does not snap over the celebration.
@export var fade_duration := 0.4

## How long an award sits on screen by itself before it flies into the total.
@export var award_hold := 0.4

## How long the flight into the total takes.
@export var award_fly := 0.3

## Roughly how long the total takes to eat one award, whatever its size. Held
## about the same for a fifty and a fifty thousand, so the pace of the tally
## does not depend on how well the level went.
@export var award_count := 0.55

## What a tap multiplies the pace of the rest of the tally by.
@export var tap_speed_up := 5.0

@onready var _panel: Control = %Panel
@onready var _next_button: Button = %NextLevelButton
@onready var _menu_button: Button = %MenuButton
@onready var _total_label: Label = %TotalValue
@onready var _chip: Control = %AwardChip
@onready var _chip_name: Label = %AwardName
@onready var _chip_value: Label = %AwardValue

## Where the chip sits before it flies. Read once the panel has been laid out,
## since the chip is moved about by hand afterwards.
var _chip_home := Vector2.ZERO

## The total as shown, which trails `_target` while the count catches up. Kept
## as a float so a slow count still moves every frame.
var _shown := 0.0
var _target := 0

## Points a second the count is currently running at.
var _rate := 0.0

## How much of the last award's kick is left, and the clock the throb runs on.
var _impact := 0.0
var _throb_time := 0.0

var _speed := 1.0
var _tallying := false
var _has_next := false


func _ready() -> void:
	_menu_button.pressed.connect(_change_scene.bind(LevelManager.MENU))

	# The last level -- and the scratch test level -- have nowhere to go next.
	var next_path := LevelManager.next_after(_current_level_path())
	_has_next = not next_path.is_empty()
	if _has_next:
		_next_button.pressed.connect(_change_scene.bind(next_path))

	Audio.wire_clicks(self)

	# Both buttons stay away until the tally is done. A tap anywhere hurries the
	# count along, and a button sitting under that tap would swallow it and send
	# the player to the next level instead of speeding anything up.
	_next_button.hide()
	_menu_button.hide()

	_chip.hide()
	_total_label.text = "0"

	_panel.modulate.a = 0.0
	var fade := create_tween()
	fade.tween_property(_panel, "modulate:a", 1.0, fade_duration)
	await fade.finished

	# Anchors have settled by now, so this is the chip's real resting place.
	_chip_home = _chip.position

	await _run_tally()

	# Held back to here rather than played on open, so the news lands on the
	# finished number instead of over the counting.
	if GameState.beat_best:
		Audio.play(Audio.NEW_RECORD)

	_reveal_buttons()


func _process(delta: float) -> void:
	var counting := _shown < float(_target)

	if counting:
		_shown = minf(_shown + _rate * _speed * delta, float(_target))
		_refresh_total()

	# The kick from an award landing, dying away, plus a throb for as long as
	# the total is still eating. Both drive the same scale, so they are worked
	# out together here rather than fought over by two tweens.
	_impact = move_toward(_impact, 0.0, delta * 2.5 * _speed)
	_throb_time += delta * _speed

	var throb := sin(_throb_time * 26.0) * 0.035 if counting else 0.0
	_total_label.pivot_offset = _total_label.size * 0.5
	_total_label.scale = Vector2.ONE * (1.0 + _impact + throb)


## A tap hurries the rest of the tally. Handled as unhandled input so it only
## ever picks up taps nothing else wanted.
func _unhandled_input(event: InputEvent) -> void:
	if not _tallying:
		return

	var tapped: bool = (event is InputEventScreenTouch and event.pressed) \
			or (event is InputEventMouseButton and event.pressed)
	if tapped:
		_speed = maxf(_speed, tap_speed_up)


func _run_tally() -> void:
	_tallying = true

	for award in GameState.last_award:
		if award.has("factor"):
			await _play_multiplier(award)
		else:
			await _play_points(award)

	_tallying = false


## A lump of points: shown, thrown at the total, then eaten.
func _play_points(award: Dictionary) -> void:
	var points := int(award.get("points", 0))
	if points <= 0:
		return

	await _present(str(award.get("label", "")), "+" + GameState.format_gems(points))

	Audio.play(Audio.TALLY)
	_impact = 0.14
	await _count_to(_target + points)


## A multiplier on everything counted so far. Lands harder than a lump of points
## because it is usually worth a great deal more.
func _play_multiplier(award: Dictionary) -> void:
	var factor := float(award.get("factor", 1.0))
	if factor <= 1.0 or _target <= 0:
		return

	await _present(str(award.get("label", "")), "x" + _trim_zeroes(factor))

	Audio.play(Audio.MULTIPLIER)
	_impact = 0.34
	await _count_to(int(round(_target * factor)))


## Pops the chip up with this award on it, holds it there long enough to be
## read, then flies it into the total and puts it away.
func _present(label: String, value: String) -> void:
	_chip_name.text = label
	_chip_value.text = value

	_chip.pivot_offset = _chip.size * 0.5
	_chip.position = _chip_home
	_chip.scale = Vector2.ZERO
	_chip.modulate.a = 1.0
	_chip.show()

	var pop := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	pop.tween_property(_chip, "scale", Vector2.ONE, 0.22 / _speed)
	await pop.finished

	await get_tree().create_timer(award_hold / _speed).timeout

	# Aimed at the middle of the total, allowing for the chip shrinking on the
	# way in -- otherwise it lands off to one side.
	var landing := _total_label.get_global_rect().get_center() - _chip.size * 0.125

	var fly := create_tween().set_parallel(true).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
	fly.tween_property(_chip, "global_position", landing, award_fly / _speed)
	fly.tween_property(_chip, "scale", Vector2.ONE * 0.25, award_fly / _speed)
	fly.tween_property(_chip, "modulate:a", 0.0, award_fly / _speed)
	await fly.finished

	_chip.hide()


## Runs the total up to `value` and waits for it to arrive. The climb itself is
## done in `_process`, so a tap part way through speeds up the count already
## under way rather than only the next one.
func _count_to(value: int) -> void:
	_target = value
	_rate = maxf(float(_target) - _shown, 0.0) / maxf(award_count, 0.01)

	while _shown < float(_target):
		await get_tree().process_frame

	_refresh_total()


func _refresh_total() -> void:
	_total_label.text = GameState.format_gems(int(round(_shown)))


## "2" rather than "2.0", but "2.5" kept as it is -- multipliers are written the
## way they would be said.
func _trim_zeroes(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(round(value)))
	return "%.1f" % value


func _reveal_buttons() -> void:
	if _has_next:
		_next_button.show()
	_menu_button.show()

	for button: Button in [_next_button, _menu_button]:
		if not button.visible:
			continue
		button.modulate.a = 0.0
		create_tween().tween_property(button, "modulate:a", 1.0, 0.25)


func _current_level_path() -> String:
	var scene := get_tree().current_scene
	return scene.scene_file_path if scene != null else ""


func _change_scene(scene_path: String) -> void:
	# A fat finger can land on both buttons before the swap happens, so shut the
	# overlay down before asking for the next scene.
	_next_button.disabled = true
	_menu_button.disabled = true

	var result := get_tree().change_scene_to_file(scene_path)
	if result != OK:
		push_error("LevelComplete: could not load '%s' (error %d)" % [scene_path, result])
		_next_button.disabled = false
		_menu_button.disabled = false
