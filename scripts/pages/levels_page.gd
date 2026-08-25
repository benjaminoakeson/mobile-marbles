extends Control

## The level select page: the level itself turning in the middle of the screen,
## with the world and the difficulty picked from popups above it. The level is
## stepped through with the arrows either side of the picture, and its name sits
## along the bottom of it -- tapping that name opens the whole set as a grid.
##
## Nothing here is authored per world or per level -- the popups are built from
## the catalogue in LevelManager and the progress in GameState, so a level added
## to one, or cleared in the other, shows up here on its own.

@onready var _world_button: Button = %WorldButton
@onready var _difficulty_button: Button = %DifficultyButton
@onready var _name_button: Button = %NameButton
@onready var _prev_button: Button = %PrevButton
@onready var _next_button: Button = %NextButton
@onready var _practice_button: Button = %PracticeButton
@onready var _challenge_button: Button = %ChallengeButton
@onready var _challenge_gloss: Panel = %Gloss
@onready var _challenge_crown: TextureRect = %Crown
@onready var _status: Label = %Status
@onready var _high_score_value: Label = %HighScoreValue
@onready var _best_time_value: Label = %BestTimeValue
@onready var _empty_notice: Label = %EmptyNotice
@onready var _preview: Node3D = %LevelPreview

@onready var _popup: Control = %Popup
@onready var _popup_scrim: Button = %PopupScrim
@onready var _popup_title: Label = %PopupTitle
@onready var _popup_grid: GridContainer = %PopupGrid

@onready var _world_template: Button = %WorldTemplate
@onready var _difficulty_template: Button = %DifficultyTemplate
@onready var _level_template: Button = %LevelTemplate

## Set once a level has been asked for. Play can be hit twice before the scene
## swaps, and the second press would otherwise cancel the first level to load
## the same one again.
var _leaving := false


func _ready() -> void:
	_world_button.pressed.connect(_open_world_popup)
	_difficulty_button.pressed.connect(_open_difficulty_popup)
	_name_button.pressed.connect(_open_level_popup)
	_prev_button.pressed.connect(_step_level.bind(-1))
	_next_button.pressed.connect(_step_level.bind(1))
	_practice_button.pressed.connect(_play)
	_challenge_button.pressed.connect(_start_challenge)

	# Tapping the dimmed page around a popup puts it away, which is the way out
	# every other app on the phone has trained a thumb to expect.
	_popup_scrim.pressed.connect(_close_popup)

	# The menu keeps all three pages alive and only hides them, so this one can
	# be minutes stale by the time it is looked at again -- and the dev tools on
	# the marble page can move the very progress it is drawn from.
	visibility_changed.connect(_on_visibility_changed)

	_restore_selection()
	_refresh()


func _on_visibility_changed() -> void:
	if not visible:
		return

	_restore_selection()
	_refresh()


# --- What is picked ---

## Picks up where the player left off. A first visit -- or a selection that no
## longer stands, because progress was lost or the catalogue changed -- falls
## back to the furthest set they can play and the next level due in it.
func _restore_selection() -> void:
	var world := LevelManager.selected_world
	if world < 1 or not GameState.is_world_unlocked(world):
		_select_world(1)
		return

	var difficulty := LevelManager.selected_difficulty
	if difficulty.is_empty() or not GameState.is_set_unlocked(world, difficulty):
		_select_difficulty(_furthest_difficulty(world))
		return

	if not GameState.is_level_unlocked(world, difficulty, LevelManager.selected_level):
		_select_level(_next_level_due(world, difficulty))


## Picking a world picks the set the player is up to in it, and the level they
## are up to in that -- the alternative is landing on a locked slot and having
## to dig back out of it.
func _select_world(world: int) -> void:
	LevelManager.selected_world = world
	_select_difficulty(_furthest_difficulty(world))


func _select_difficulty(difficulty: String) -> void:
	LevelManager.selected_difficulty = difficulty
	_select_level(_next_level_due(LevelManager.selected_world, difficulty))


func _select_level(index: int) -> void:
	LevelManager.selected_level = index


## The set a player is up to in a world: the first they have not finished, or
## the hardest one they have unlocked.
func _furthest_difficulty(world: int) -> String:
	var furthest: String = LevelManager.DIFFICULTIES[0]

	for difficulty in LevelManager.DIFFICULTIES:
		if not GameState.is_set_unlocked(world, difficulty):
			break

		furthest = difficulty
		if not GameState.is_challenge_complete(world, difficulty):
			break

	return furthest


## Where to land in a set. The first level not yet beaten, since that is what
## the player most likely came for -- but every level is open, so this is only
## a starting point and not a limit.
func _next_level_due(world: int, difficulty: String) -> int:
	for index in LevelManager.levels_in(world, difficulty).size():
		if not GameState.is_level_cleared(world, difficulty, index):
			return index

	return 0


# --- The page ---

func _refresh() -> void:
	var world := LevelManager.selected_world
	var difficulty := LevelManager.selected_difficulty
	var index := LevelManager.selected_level
	var path := LevelManager.level_at(world, difficulty, index)

	_world_button.text = "WORLD %d" % world
	_difficulty_button.text = difficulty.to_upper()
	_name_button.text = LevelManager.numbered_name(path, index)
	_status.text = _status_text(world, difficulty, path)
	_show_records(path)

	# Nothing to step to in a set holding one level, or none at all.
	var built: int = LevelManager.levels_in(world, difficulty).size()
	_prev_button.visible = built > 1
	_next_button.visible = built > 1

	_practice_button.disabled = path.is_empty() \
		or not GameState.is_level_unlocked(world, difficulty, index)

	var can_challenge := GameState.can_start_challenge(world, difficulty)
	_challenge_button.disabled = not can_challenge
	_challenge_button.text = "Challenge Run \u2713" \
		if GameState.is_challenge_complete(world, difficulty) else "Challenge Run"

	# The shine and the crown belong to the gold face. Left on over the grey
	# disabled one they would read as a button that is still on offer.
	_challenge_gloss.visible = can_challenge
	_challenge_crown.visible = can_challenge

	_preview.show_level(path)
	_empty_notice.visible = path.is_empty()


## The line under the level: what is on offer here, or why it cannot be taken.
## The best time used to live here too; it has a readout of its own now.
func _status_text(world: int, difficulty: String, path: String) -> String:
	if path.is_empty():
		return "Nothing built for this slot yet"

	if not GameState.is_set_unlocked(world, difficulty):
		var step := LevelManager.DIFFICULTIES.find(difficulty)
		if step > 0:
			return "Finish the %s challenge run first" % LevelManager.DIFFICULTIES[step - 1]
		return "Locked"

	return "Free play - %d lives for this level" % GameState.STARTING_LIVES


## The two records for this level. Both are written by the same call in
## `GameState.finish_level()`, so a level that has never been finished has
## neither -- and shows a dash rather than a zero it never actually scored.
func _show_records(path: String) -> void:
	var played: bool = not path.is_empty() and GameState.best_score.has(path)

	_high_score_value.text = GameState.format_gems(GameState.best_score_for(path)) \
		if played else "--"
	_best_time_value.text = GameState.format_time(GameState.best_time_for(path))


## Moves along the set by one, wrapping at either end so the arrows never go
## dead -- a short set is a small loop rather than two disabled buttons.
func _step_level(step: int) -> void:
	var built: int = LevelManager.levels_in(
		LevelManager.selected_world, LevelManager.selected_difficulty).size()
	if built <= 1:
		return

	_select_level(posmod(LevelManager.selected_level + step, built))
	_refresh()


func _play() -> void:
	if _leaving:
		return

	var path := LevelManager.level_at(
		LevelManager.selected_world,
		LevelManager.selected_difficulty,
		LevelManager.selected_level)
	if path.is_empty():
		return

	GameState.begin_free_play()
	_load(path)


## The whole set in one attempt. Always from its first level -- a challenge is
## not something that can be joined part way through -- and losing the lives
## fails it. Finishing it is what opens the next difficulty.
func _start_challenge() -> void:
	if _leaving:
		return

	var world := LevelManager.selected_world
	var difficulty := LevelManager.selected_difficulty
	if not GameState.can_start_challenge(world, difficulty):
		return

	var path := LevelManager.level_at(world, difficulty, 0)
	if path.is_empty():
		return

	# The list should come back on the level the run starts from, not wherever
	# the player happened to be browsing.
	_select_level(0)

	GameState.begin_challenge(world, difficulty)
	_load(path)


func _load(path: String) -> void:
	_leaving = true

	var result := get_tree().change_scene_to_file(path)
	if result != OK:
		push_error("LevelsPage: could not load '%s' (error %d)" % [path, result])
		_leaving = false


# --- Popups ---

func _open_world_popup() -> void:
	_show_popup("SELECT A WORLD", 2)

	for world in range(1, LevelManager.WORLD_COUNT + 1):
		var button := _clone(_world_template)
		var unlocked := GameState.is_world_unlocked(world)

		button.text = "WORLD %d\n%s" % [world, _world_status(world)]
		button.disabled = not unlocked
		if unlocked:
			button.pressed.connect(_pick_world.bind(world))

		_popup_grid.add_child(button)


## How much of a world is finished, for the line under its number.
func _world_status(world: int) -> String:
	if not GameState.is_world_unlocked(world):
		return "Locked"

	var complete := 0
	for difficulty in LevelManager.DIFFICULTIES:
		if GameState.is_challenge_complete(world, difficulty):
			complete += 1

	return "%d / %d challenges" % [complete, LevelManager.DIFFICULTIES.size()]


func _open_difficulty_popup() -> void:
	_show_popup("SELECT A DIFFICULTY", 1)

	var world := LevelManager.selected_world
	for difficulty in LevelManager.DIFFICULTIES:
		var button := _clone(_difficulty_template)
		var unlocked := GameState.is_set_unlocked(world, difficulty)

		button.text = "%s\n%s" % [difficulty, _difficulty_status(world, difficulty)]
		button.disabled = not unlocked
		if unlocked:
			button.pressed.connect(_pick_difficulty.bind(difficulty))

		_popup_grid.add_child(button)


## Where a set stands, for the line under its name.
func _difficulty_status(world: int, difficulty: String) -> String:
	if not GameState.is_set_unlocked(world, difficulty):
		return "Locked"

	var levels := LevelManager.levels_in(world, difficulty)
	if levels.is_empty():
		return "No levels yet"

	if GameState.is_challenge_complete(world, difficulty):
		return "Challenge done"

	return "%d / %d cleared" % [GameState.cleared_in(world, difficulty), levels.size()]


## A full set of tiles is always drawn, so the ten levels a set is meant to hold
## are visible even while most of them are still to be built.
func _open_level_popup() -> void:
	# Two across rather than three: a tile carries a name now, and a name needs
	# the width to be read at a glance.
	_show_popup("SELECT A LEVEL", 2)

	var world := LevelManager.selected_world
	var difficulty := LevelManager.selected_difficulty

	for index in LevelManager.LEVELS_PER_SET:
		var button := _clone(_level_template)
		var path := LevelManager.level_at(world, difficulty, index)
		var unlocked := GameState.is_level_unlocked(world, difficulty, index)

		button.text = "%d\n%s\n%s" % [
			index + 1,
			LevelManager.name_for(path, index),
			_level_status(world, difficulty, index, path),
		]
		button.disabled = not unlocked
		if unlocked:
			button.pressed.connect(_pick_level.bind(index))

		_popup_grid.add_child(button)


## The line under a level's number: its best time once cleared, and why it
## cannot be opened when it cannot.
func _level_status(world: int, difficulty: String, index: int, path: String) -> String:
	if path.is_empty():
		return "--"

	if GameState.is_level_cleared(world, difficulty, index):
		return GameState.format_time(GameState.best_time_for(path))

	if GameState.is_level_unlocked(world, difficulty, index):
		return "Open"

	return "Locked"


func _pick_world(world: int) -> void:
	_select_world(world)
	_finish_pick()


func _pick_difficulty(difficulty: String) -> void:
	_select_difficulty(difficulty)
	_finish_pick()


func _pick_level(index: int) -> void:
	_select_level(index)
	_finish_pick()


func _finish_pick() -> void:
	_close_popup()
	_refresh()


func _show_popup(title: String, columns: int) -> void:
	_clear(_popup_grid)
	_popup_title.text = title
	_popup_grid.columns = columns
	_popup.visible = true


func _close_popup() -> void:
	_popup.visible = false

	# Emptied on the way out rather than on the way in, so a popup is never left
	# holding buttons built against progress that has since moved on.
	_clear(_popup_grid)


# --- Building blocks ---

## Clones a hidden template so every button keeps the styling authored in the
## scene, instead of having it rebuilt in code.
func _clone(template: Button) -> Button:
	var button: Button = template.duplicate()
	button.unique_name_in_owner = false
	button.visible = true

	# Built after the menu was given its clicks, so it asks for its own.
	Audio.wire_clicks(button)

	return button


func _clear(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
