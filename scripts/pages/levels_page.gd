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
## One button starts a level, and the two tabs over it choose what starting one
## means: PLAY, which is the game itself -- one level, as many goes as it takes,
## and the next level opened by finishing it -- or CHALLENGE, a whole chapter on
## three lives in one sitting. The tabs only swap the button; the run itself
## begins on the button, so no single tap can commit to a mode.
##
## The dev tools are on the profile sheet, which is reachable from every tab.
## They were next to the start button, where they took up half the room the one
## button the player actually presses had to sit in.

@onready var _name_label: Label = %NameLabel
@onready var _preview_button: Button = %PreviewButton
@onready var _prev_button: Button = %PrevButton
@onready var _next_button: Button = %NextButton
@onready var _play_tab: Button = %PlayTab
@onready var _challenge_tab: Button = %ChallengeTab
@onready var _play_button: Button = %PlayButton
@onready var _challenge_button: Button = %ChallengeButton
@onready var _challenge_gloss: Panel = %Gloss
@onready var _challenge_crown: TextureRect = %Crown
@onready var _challenge_lock: TextureRect = %Lock
@onready var _status: Label = %Status
@onready var _crowns: HBoxContainer = %Crowns
@onready var _crown_template: Button = %CrownTemplate

@onready var _crown_info: Control = %CrownInfo
@onready var _crown_info_scrim: Button = %CrownInfoScrim
@onready var _crown_info_name: Label = %CrownName
@onready var _crown_info_ask: Label = %CrownAsk
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


func _ready() -> void:
	# The picture is the way in to the selector. The arrows are later siblings, so
	# a tap that lands on one goes there instead of here.
	_preview_button.pressed.connect(_open_selector)
	_prev_button.pressed.connect(_step_level.bind(-1))
	_next_button.pressed.connect(_step_level.bind(1))
	_play_button.pressed.connect(_play)
	_challenge_button.pressed.connect(_start_challenge)

	# The tabs only ever change what the button under them is. Nothing starts
	# from a tab -- the mode is chosen and then started, in two taps, because a
	# tab that launched a run would make a mis-tap cost a chapter.
	_play_tab.pressed.connect(_choose_mode.bind(GameState.Mode.PLAY))
	_challenge_tab.pressed.connect(_choose_mode.bind(GameState.Mode.CHALLENGE))

	# Tapping the dimmed page around a popup puts it away, which is the way out
	# every other app on the phone has trained a thumb to expect. The crown card
	# goes one further: the sheet behind it covers the whole page, so anywhere at
	# all -- including another crown -- puts it away.
	_popup_scrim.pressed.connect(_close_popup)
	_crown_info_scrim.pressed.connect(_close_crown_info)
	_crown_info.hide()

	_world_prev.pressed.connect(_step_browse_world.bind(-1))
	_world_next.pressed.connect(_step_browse_world.bind(1))
	_chapter_track.chapter_picked.connect(_browse_chapter_at)

	# The menu keeps all three pages alive and only hides them, so this one can
	# be minutes stale by the time it is looked at again.
	visibility_changed.connect(_on_visibility_changed)

	# The dev tools are on the profile sheet, which opens OVER this page without
	# ever hiding it -- so the check above never fires for them. This is how a
	# page with the world unlocked out from under it hears about it.
	GameState.progress_changed.connect(_on_progress_changed)

	_restore_selection()
	_refresh()


func _on_visibility_changed() -> void:
	if not visible:
		return

	# Left open behind a tab change, the card would be the first thing back.
	_close_crown_info()

	_restore_selection()
	_refresh()


## Whatever the dev tools just did, the world, chapter and level this page is
## showing may not have survived it.
func _on_progress_changed() -> void:
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
	var built := LevelManager.built_chapters(world)
	if built.is_empty():
		return ""
	var furthest: String = built[0]

	for chapter: String in built:
		if not GameState.is_set_unlocked(world, chapter):
			break

		furthest = chapter
		if not GameState.is_set_complete(world, chapter):
			break

	return furthest


## Where to land in a set. The first level not yet beaten, which is both what the
## player most likely came for and the furthest one they are allowed to open.
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
	_show_crowns(path)

	# Nothing to step to in a set holding one level, or none at all.
	var built: int = LevelManager.levels_in(world, chapter).size()
	_prev_button.visible = built > 1
	_next_button.visible = built > 1

	# Which face of the start button is on show, and which tab is lit. Both are
	# read back off GameState rather than kept here, so a page rebuilt after a
	# level -- or after the dev tools have been through it -- comes back on the
	# mode the player left it on.
	var challenge: bool = GameState.preferred_mode == GameState.Mode.CHALLENGE
	_play_tab.button_pressed = not challenge
	_challenge_tab.button_pressed = challenge
	_play_button.visible = not challenge
	_challenge_button.visible = challenge

	_play_button.disabled = path.is_empty() \
		or not GameState.is_level_unlocked(world, chapter, index)

	var can_challenge := GameState.can_start_challenge(world, chapter)
	_challenge_button.disabled = not can_challenge
	_challenge_button.text = "Challenge Run \u2713" \
		if GameState.is_challenge_complete(world, chapter) else "Challenge Run"

	# The shine and the crown belong to the gold face. Left on over the grey
	# disabled one they would read as a button that is still on offer. The
	# padlock is the other half of that: it takes the crown's place, so a locked
	# run is grey, shut, and says so with a symbol as well as with the line under
	# the level.
	_challenge_gloss.visible = can_challenge
	_challenge_crown.visible = can_challenge
	_challenge_lock.visible = not can_challenge

	_preview.show_level(path)
	_empty_notice.visible = path.is_empty()


## The line under the level: what is on offer here, or why it cannot be taken.
## The best time used to live here too; it has a readout of its own now.
func _status_text(world: int, chapter: String, path: String) -> String:
	if path.is_empty():
		return "Nothing built for this slot yet"

	if not GameState.is_set_unlocked(world, chapter):
		var built := LevelManager.built_chapters(world)
		var step := built.find(chapter)
		if step > 0:
			return "Finish %s first" % LevelManager.chapter_name(
				world, built[step - 1])
		return "Locked"

	# The challenge is the whole chapter, so what it says has nothing to do with
	# whichever level the page happens to be showing.
	if GameState.preferred_mode == GameState.Mode.CHALLENGE:
		var length := LevelManager.levels_in(world, chapter).size()

		# The chapter is open, so the only thing left that can be holding the
		# run shut is not having been all the way through it yet.
		if not GameState.can_start_challenge(world, chapter):
			return "Beat all %d levels to unlock the challenge" % length

		return "Challenge - %d lives for all %d levels, in one go" % [
			GameState.STARTING_LIVES,
			length,
		]

	var index := LevelManager.selected_level
	if not GameState.is_level_unlocked(world, chapter, index):
		# Named rather than numbered: "Beat 2 - Open Wide first" is a level the
		# player can go and find, where "beat the level before this one" is not.
		var previous := LevelManager.level_at(world, chapter, index - 1)
		return "Beat %s first" % LevelManager.numbered_name(previous, index - 1)

	return "Play - unlimited lives"


## The five crowns this level has to give, earned ones in their own colour and
## the rest as empty slots.
##
## All five are always on show, including on a level that has never been played
## and on an empty slot with no level in it at all. A crown that only appeared
## once it was won would be a prize nobody knew was there -- and every one of
## them can be tapped to ask what it is, won or not, for the same reason.
##
## Rebuilt rather than repainted: five nodes is nothing, and it keeps this the
## only place that has to know how a crown is drawn.
func _show_crowns(path: String) -> void:
	_clear(_crowns)

	var earned := GameState.crowns_for(path) if not path.is_empty() else 0

	for crown: int in Crowns.ORDER:
		var badge: Button = _crown_template.duplicate()
		badge.unique_name_in_owner = false
		badge.visible = true
		badge.modulate = Crowns.colour_for(crown) if earned & crown else Crowns.UNEARNED
		badge.pressed.connect(_open_crown_info.bind(crown))

		# Built after the menu was given its clicks, so it asks for its own.
		Audio.wire_clicks(badge)

		_crowns.add_child(badge)


## What that crown is and what it takes, in its own colour.
##
## The same card either way: a crown already won still answers "what was that one
## for again?", and the answer does not change for having been earned.
func _open_crown_info(crown: int) -> void:
	_crown_info_name.text = Crowns.name_for(crown)
	_crown_info_name.add_theme_color_override("font_color", Crowns.colour_for(crown))
	_crown_info_ask.text = Crowns.ask_for(crown)

	_crown_info.show()


func _close_crown_info() -> void:
	_crown_info.hide()


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

	GameState.begin_play()
	_load(path)


## The whole set in one attempt. Always from its first level -- a challenge is
## not something that can be joined part way through -- and losing the lives ends
## it. Finishing it opens nothing that playing the same levels would not have
## opened; it is recorded as done and shown as a tick, and that is all it is
## worth for now.
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


## Puts the start button on one mode or the other. Saved rather than kept on the
## page, so it survives the level the player is about to play -- coming back from
## a level rebuilds this page from nothing.
func _choose_mode(mode: GameState.Mode) -> void:
	if GameState.preferred_mode == mode:
		return

	GameState.preferred_mode = mode
	GameState.save_progress()
	_refresh()


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
		_browse_chapter = _first_built_chapter(_browse_world)

	_show_popup("SELECT A LEVEL", 2)
	_refresh_selector()


## Steps to the next BUILT world along, wrapping at either end.
##
## Every world that exists can be looked at, locked or not -- the point of the
## selector is to show what the game holds, and a locked world that cannot even
## be seen teaches the player nothing about what they are working towards. A
## world that does not exist yet teaches them less than nothing, so those are not
## in the walk at all.
func _step_browse_world(step: int) -> void:
	var worlds := LevelManager.built_worlds()
	if worlds.is_empty():
		return

	var at := maxi(worlds.find(_browse_world), 0)
	_browse_world = worlds[posmod(at + step, worlds.size())]

	# Chapters are per world, so reading into a new one starts at its beginning
	# rather than keeping a position that meant something in the last one.
	_browse_chapter = _first_built_chapter(_browse_world)
	_refresh_selector()


func _browse_chapter_at(index: int) -> void:
	var built := LevelManager.built_chapters(_browse_world)
	if index < 0 or index >= built.size():
		return
	_browse_chapter = built[index]
	_refresh_selector()


## The easiest chapter a world actually has, or "" for a world with nothing in
## it -- which the selector should never be looking at, but which costs one line
## to survive.
func _first_built_chapter(world: int) -> String:
	var built := LevelManager.built_chapters(world)
	return built[0] if not built.is_empty() else ""


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

	# Nothing to page to in a game with one world in it, and an arrow that only
	# ever brings you back where you started is worse than no arrow.
	var many_worlds := LevelManager.built_worlds().size() > 1
	_world_prev.visible = many_worlds
	_world_next.visible = many_worlds

	_chapter_track.show_world(_browse_world, _browse_chapter)
	_build_level_grid()


## One tile per level the set actually holds -- see
## [method LevelManager.slots_in].
##
## A tile carries its number and its name and nothing else. The best time and the
## reason a locked level was locked used to ride along underneath, which turned
## the grid into a wall of small print at exactly the moment the player was
## trying to find one level in it.
func _build_level_grid() -> void:
	_clear(_popup_grid)

	for index in LevelManager.slots_in(_browse_world, _browse_chapter):
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


## Opens the selector popup. There used to be a second thing built in it -- the
## dev tools -- which is what the chrome could be turned off for; the chrome is
## simply always on now.
func _show_popup(title: String, columns: int) -> void:
	_clear(_popup_grid)
	_popup_title.text = title
	_popup_grid.columns = columns
	_selector_chrome.visible = true
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
