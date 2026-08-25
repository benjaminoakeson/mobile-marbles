extends Control

## The level select page: the level itself turning in the middle of the screen,
## with one line above it saying where that is -- "1:1 - First Roll". The level is
## stepped through with the arrows either side of the picture, and tapping the
## picture anywhere else opens the selector.
##
## The world and chapter buttons that used to sit across the top are gone. They
## were on screen permanently to be used about once a session, and between them
## and the records and the two play buttons the page had four separate things
## competing to be read first. Everything about choosing where to play now lives
## in the selector, and the page itself is the level, its name, and how to start.
##
## Nothing here is authored per world or per level -- the selector is built from
## the catalogue in LevelManager and the progress in GameState, so a level added
## to one, or cleared in the other, shows up here on its own.
##
## The dev tools sit next to Practice, and open as another popup. They used to be
## on the marble page; they are here because this is the page whose state they
## actually move.

@onready var _name_label: Label = %NameLabel
@onready var _preview_button: Button = %PreviewButton
@onready var _prev_button: Button = %PrevButton
@onready var _next_button: Button = %NextButton
@onready var _practice_button: Button = %PracticeButton
@onready var _challenge_button: Button = %ChallengeButton
@onready var _dev_button: Button = %DevToolsButton
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
@onready var _selector_chrome: Control = %SelectorChrome

@onready var _world_prev: Button = %WorldPrev
@onready var _world_next: Button = %WorldNext
@onready var _world_label: Label = %WorldLabel
@onready var _chapter_track: Control = %ChapterTrack
@onready var _chapter_name: Label = %ChapterName
@onready var _chapter_difficulty: Label = %ChapterDifficulty

@onready var _level_template: Button = %LevelTemplate

## Set once a level has been asked for. Play can be hit twice before the scene
## swaps, and the second press would otherwise cancel the first level to load
## the same one again.
var _leaving := false

## Where the selector is currently looking, which is not the same as what the
## page is showing.
##
## The player is allowed to read ahead -- walk the world's chapters past the one
## they have reached, or step into a world they have not opened -- and none of
## that should move the page behind the popup. Only picking an actual level
## commits, so backing out of the selector leaves everything as it was.
var _browse_world := 1
var _browse_chapter := ""

## Reset asks twice. It throws away every best time, every cleared level and the
## whole bank, and one stray press should not be able to do that.
var _reset_armed := false
var _disarm_timer: SceneTreeTimer

## How long the reset stays armed before it forgets it was asked. Without this
## the two taps need not be anywhere near each other in time, and one stray
## press minutes after another is enough to wipe the save.
const RESET_ARMED_FOR := 3.0

## What the wipe is labelled in. The dev popup builds both tools from one
## template, and this is the only thing telling them apart.
const DESTRUCTIVE_TEXT := Color(1, 0.63529414, 0.63529414, 1)


func _ready() -> void:
	# The picture is the way in to the selector. The arrows are later siblings, so
	# a tap that lands on one goes there instead of here.
	_preview_button.pressed.connect(_open_selector)
	_prev_button.pressed.connect(_step_level.bind(-1))
	_next_button.pressed.connect(_step_level.bind(1))
	_practice_button.pressed.connect(_play)
	_challenge_button.pressed.connect(_start_challenge)

	# `OS.is_debug_build()` is false in a release export, so the tools cannot
	# reach players by accident -- but a debug export still shows them, which is
	# what makes them usable on a phone.
	_dev_button.visible = OS.is_debug_build()
	if _dev_button.visible:
		_dev_button.pressed.connect(_open_dev_popup)

	# Tapping the dimmed page around a popup puts it away, which is the way out
	# every other app on the phone has trained a thumb to expect.
	_popup_scrim.pressed.connect(_close_popup)

	_world_prev.pressed.connect(_step_browse_world.bind(-1))
	_world_next.pressed.connect(_step_browse_world.bind(1))
	_chapter_track.chapter_picked.connect(_browse_chapter_at)

	# The menu keeps all three pages alive and only hides them, so this one can
	# be minutes stale by the time it is looked at again.
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

	var chapter := LevelManager.selected_chapter
	if chapter.is_empty() or not GameState.is_set_unlocked(world, chapter):
		_select_chapter(_furthest_chapter(world))
		return

	if not GameState.is_level_unlocked(world, chapter, LevelManager.selected_level):
		_select_level(_next_level_due(world, chapter))


## Picking a world picks the set the player is up to in it, and the level they
## are up to in that -- the alternative is landing on a locked slot and having
## to dig back out of it.
func _select_world(world: int) -> void:
	LevelManager.selected_world = world
	_select_chapter(_furthest_chapter(world))


func _select_chapter(chapter: String) -> void:
	LevelManager.selected_chapter = chapter
	_select_level(_next_level_due(LevelManager.selected_world, chapter))


func _select_level(index: int) -> void:
	LevelManager.selected_level = index


## The set a player is up to in a world: the first they have not finished, or
## the hardest one they have unlocked.
func _furthest_chapter(world: int) -> String:
	var furthest: String = LevelManager.CHAPTERS[0]

	for chapter in LevelManager.CHAPTERS:
		if not GameState.is_set_unlocked(world, chapter):
			break

		furthest = chapter
		if not GameState.is_challenge_complete(world, chapter):
			break

	return furthest


## Where to land in a set. The first level not yet beaten, since that is what
## the player most likely came for -- but every level is open, so this is only
## a starting point and not a limit.
func _next_level_due(world: int, chapter: String) -> int:
	for index in LevelManager.levels_in(world, chapter).size():
		if not GameState.is_level_cleared(world, chapter, index):
			return index

	return 0


# --- The page ---

func _refresh() -> void:
	var world := LevelManager.selected_world
	var chapter := LevelManager.selected_chapter
	var index := LevelManager.selected_level
	var path := LevelManager.level_at(world, chapter, index)

	_name_label.text = LevelManager.headline(world, index, path)
	_status.text = _status_text(world, chapter, path)
	_show_records(path)

	# Nothing to step to in a set holding one level, or none at all.
	var built: int = LevelManager.levels_in(world, chapter).size()
	_prev_button.visible = built > 1
	_next_button.visible = built > 1

	_practice_button.disabled = path.is_empty() \
		or not GameState.is_level_unlocked(world, chapter, index)

	var can_challenge := GameState.can_start_challenge(world, chapter)
	_challenge_button.disabled = not can_challenge
	_challenge_button.text = "Challenge Run \u2713" \
		if GameState.is_challenge_complete(world, chapter) else "Challenge Run"

	# The shine and the crown belong to the gold face. Left on over the grey
	# disabled one they would read as a button that is still on offer.
	_challenge_gloss.visible = can_challenge
	_challenge_crown.visible = can_challenge

	_preview.show_level(path)
	_empty_notice.visible = path.is_empty()


## The line under the level: what is on offer here, or why it cannot be taken.
## The best time used to live here too; it has a readout of its own now.
func _status_text(world: int, chapter: String, path: String) -> String:
	if path.is_empty():
		return "Nothing built for this slot yet"

	if not GameState.is_set_unlocked(world, chapter):
		var step := LevelManager.chapter_index(chapter)
		if step > 0:
			return "Finish %s first" % LevelManager.chapter_name(
				world, LevelManager.CHAPTERS[step - 1])
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
		LevelManager.selected_world, LevelManager.selected_chapter).size()
	if built <= 1:
		return

	_select_level(posmod(LevelManager.selected_level + step, built))
	_refresh()


func _play() -> void:
	if _leaving:
		return

	var path := LevelManager.level_at(
		LevelManager.selected_world,
		LevelManager.selected_chapter,
		LevelManager.selected_level)
	if path.is_empty():
		return

	GameState.begin_free_play()
	_load(path)


## The whole set in one attempt. Always from its first level -- a challenge is
## not something that can be joined part way through -- and losing the lives
## fails it. Finishing it is what opens the next chapter.
func _start_challenge() -> void:
	if _leaving:
		return

	var world := LevelManager.selected_world
	var chapter := LevelManager.selected_chapter
	if not GameState.can_start_challenge(world, chapter):
		return

	var path := LevelManager.level_at(world, chapter, 0)
	if path.is_empty():
		return

	# The list should come back on the level the run starts from, not wherever
	# the player happened to be browsing.
	_select_level(0)

	GameState.begin_challenge(world, chapter)
	_load(path)


func _load(path: String) -> void:
	_leaving = true

	var result := get_tree().change_scene_to_file(path)
	if result != OK:
		push_error("LevelsPage: could not load '%s' (error %d)" % [path, result])
		_leaving = false


# --- The selector ---
# One popup now, instead of three. The world is stepped along the top, the
# chapters are the road under it, and the levels of whichever chapter is being
# looked at fill the rest.

## Opens the selector on whatever the page is currently showing.
func _open_selector() -> void:
	_browse_world = maxi(LevelManager.selected_world, 1)
	_browse_chapter = LevelManager.selected_chapter
	if _browse_chapter.is_empty():
		_browse_chapter = LevelManager.CHAPTERS[0]

	_show_popup("SELECT A LEVEL", 2)
	_refresh_selector()


## Steps to the next world along, wrapping at either end.
##
## Every world can be looked at, locked or not -- the point of the selector is to
## show what the game holds, and a locked world that cannot even be seen teaches
## the player nothing about what they are working towards.
func _step_browse_world(step: int) -> void:
	_browse_world = posmod(
		_browse_world - 1 + step, LevelManager.WORLD_COUNT) + 1

	# Chapters are per world, so reading into a new one starts at its beginning
	# rather than keeping a position that meant something in the last one.
	_browse_chapter = LevelManager.CHAPTERS[0]
	_refresh_selector()


func _browse_chapter_at(index: int) -> void:
	_browse_chapter = LevelManager.CHAPTERS[index]
	_refresh_selector()


## Redraws the whole selector for wherever it is now looking.
func _refresh_selector() -> void:
	_world_label.text = "WORLD %d" % _browse_world

	# A world whose chapters have not been named yet falls back to the difficulty
	# for the name. Printing it again underneath reads as a bug rather than as a
	# subtitle, so the second line drops out until there is a real name above it.
	var chapter_name := LevelManager.chapter_name(_browse_world, _browse_chapter)
	_chapter_name.text = chapter_name
	_chapter_difficulty.text = \
		"" if chapter_name == _browse_chapter else _browse_chapter

	_chapter_track.show_world(_browse_world, _browse_chapter)
	_build_level_grid()


## A full set of tiles is always drawn, so the ten levels a chapter is meant to
## hold are visible even while most of them are still to be built.
##
## A tile carries its number and its name and nothing else. The best time and the
## reason a locked level was locked used to ride along underneath, which turned
## the grid into a wall of small print at exactly the moment the player was
## trying to find one level in it.
func _build_level_grid() -> void:
	_clear(_popup_grid)

	for index in LevelManager.LEVELS_PER_SET:
		var button := _clone(_level_template)
		var path := LevelManager.level_at(_browse_world, _browse_chapter, index)
		var playable := not path.is_empty() \
			and GameState.is_level_unlocked(_browse_world, _browse_chapter, index)

		# An empty slot is its number alone. Falling back to the placeholder name
		# would print "3" twice, once as the number and once as the name.
		button.text = "%d\n%s" % [index + 1, LevelManager.name_for(path, index)] \
			if not path.is_empty() else "%d" % (index + 1)

		button.disabled = not playable
		if playable:
			button.pressed.connect(_pick_level_at.bind(index))

		_popup_grid.add_child(button)


## Taking a level is the only thing in the selector that commits. Everything up
## to here was reading; this is the point the page moves.
func _pick_level_at(index: int) -> void:
	LevelManager.selected_world = _browse_world
	LevelManager.selected_chapter = _browse_chapter
	_select_level(index)

	_close_popup()
	_refresh()


## Opens the shared popup. `with_chrome` is what tells the level selector apart
## from the dev tools: both fill the same grid, but only one of them wants a
## world, a chapter road and a chapter name above it.
func _show_popup(title: String, columns: int, with_chrome := true) -> void:
	_clear(_popup_grid)
	_popup_title.text = title
	_popup_grid.columns = columns
	_selector_chrome.visible = with_chrome
	_popup.visible = true


func _close_popup() -> void:
	_popup.visible = false

	# The reset lives on a button inside the popup, which is about to be freed.
	# Leaving it armed would mean a popup reopened later starts one tap from a
	# wipe, with nothing on screen saying so.
	_disarm()

	# Emptied on the way out rather than on the way in, so a popup is never left
	# holding buttons built against progress that has since moved on.
	_clear(_popup_grid)


# --- Dev tools ---
# Debug builds only. Both tools reach straight into GameState, so the page is
# rebuilt afterwards -- the world, chapter and level it is showing may not
# survive what they just did.

## Two buttons, built the same way every other popup here is built. Held on to
## so pressing one can report back through its own label, which saves the popup
## needing a status line of its own.
var _dev_unlock_button: Button
var _dev_reset_button: Button


func _open_dev_popup() -> void:
	_show_popup("DEV TOOLS", 1, false)

	_dev_unlock_button = _clone(_level_template)
	_dev_unlock_button.text = "Unlock Everything"
	_dev_unlock_button.pressed.connect(_unlock_everything)
	_popup_grid.add_child(_dev_unlock_button)

	_dev_reset_button = _clone(_level_template)
	_dev_reset_button.text = "Delete Everything"
	_dev_reset_button.pressed.connect(_reset_progress)

	# The two tools come off the same template, so without this the one that
	# wipes the save looks exactly like the one that does not.
	_dev_reset_button.add_theme_color_override("font_color", DESTRUCTIVE_TEXT)
	_dev_reset_button.add_theme_color_override("font_hover_color", DESTRUCTIVE_TEXT)

	_popup_grid.add_child(_dev_reset_button)


func _unlock_everything() -> void:
	GameState.dev_unlock_everything()

	# Arming the wipe and then reaching for this button instead should not leave
	# it armed behind the popup.
	_disarm()
	_dev_unlock_button.text = "Unlocked \u2713"

	_restore_selection()
	_refresh()


## Asks twice. The first press only arms it; the second is the one that wipes.
func _reset_progress() -> void:
	if not _reset_armed:
		_arm()
		return

	GameState.dev_reset_progress()
	_reset_armed = false
	_disarm_timer = null
	_dev_reset_button.text = "Deleted \u2713"

	_restore_selection()
	_refresh()


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


## Puts the wipe back to needing two taps. Also called when the popup closes, by
## which point the button it was labelling has been freed -- hence the check.
func _disarm() -> void:
	_reset_armed = false
	_disarm_timer = null

	if is_instance_valid(_dev_reset_button):
		_dev_reset_button.text = "Delete Everything"


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
