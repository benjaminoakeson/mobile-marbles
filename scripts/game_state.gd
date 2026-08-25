extends Node

## Tracks the run -- score, lives, and how long the current level has taken --
## and remembers a best score and best time for every level played, along with
## how far the player has got through each set of levels.
##
## Autoloaded as `GameState`, so menus and levels read the same numbers.

signal score_changed(score: int)
signal lives_changed(lives: int)

## Gems banked, for the shop to draw on.
signal bank_changed(bank: int)

## Gems counted towards the next extra life, and what they have to add up to.
signal gem_progress_changed(collected: int, target: int)

## Out of lives. Handled here by sending the player back to the level list.
signal run_ended

## Fired when the player picks a different marble. The menu's preview listens so
## the marble on the page changes under the picker as it is tapped.
signal marble_skin_changed(skin_id: String)

## A level has been loaded and is about to be played. What it is worth hearing
## about is which world it belongs to, so the music can match.
signal level_started(level_path: String)

## The run's gems have paid for an extra life.
signal extra_life_earned

## The player has steered for the first time this level, so the clock is now
## running. What the ball waits on before it is allowed to move -- see
## `player.gd`.
signal timing_started

const SAVE_PATH := "user://progress.cfg"

## Lives are handed out per set, not per level: three of them cover all ten
## levels of a chapter. Running out means the set is attempted again.
const STARTING_LIVES := 3

## What a level's gems have to add up to for the first extra life of a run.
const FIRST_EXTRA_LIFE := 250

## How much higher the bar goes each time a life is earned. The count starts
## over from nothing after every life, so the second of a run costs 350 gems on
## top of the first, the third 450 on top of that, and so on.
const EXTRA_LIFE_STEP := 100

# --- The current run ---
var score := 0
var lives := STARTING_LIVES
var level_time := 0.0
var current_level := ""

## Points banked from gems this level, kept apart from the rest of the score so
## an all-gems bonus can be worked out from it.
##
## Reset by every level. The bank below is what keeps them.
var gem_score := 0

## Gems counted towards the next extra life. This one carries from level to
## level, so a run keeps climbing towards a life across the whole set -- but it
## is dropped the moment the player leaves for the menu. See `leave_run()`.
##
## Back to nothing every time a life is earned, so what it holds is always the
## gems found since the last one.
var run_gems := 0

## What `run_gems` has to reach for the next extra life. Raised with each life
## earned, and put back to `FIRST_EXTRA_LIFE` whenever the climb starts over, so
## the further into a run the player is, the dearer a life gets.
var extra_life_target := FIRST_EXTRA_LIFE

## How the current level is being played.
##
## FREE is the level list: any level of an unlocked chapter, on its own, with
## its own three lives. Nothing is unlocked by it.
##
## CHALLENGE is one continuous attempt at a whole set, starting at its first
## level and carrying the same lives all the way through. Finishing it is the
## ONLY thing that unlocks the next chapter; running out of lives part way
## fails the run and unlocks nothing.
enum Mode { FREE, CHALLENGE }

var run_mode := Mode.FREE

## The set the current level belongs to, and its place in that set. Empty for a
## level that is not registered -- see `_enter_set()`.
var run_set := ""
var run_index := 0
var run_world := 0
var run_chapter := ""

## Whether the level just finished beat a best score or a best time. Read by the
## victory panel, which is where that news is worth hearing.
var beat_best := false

## What the level just finished was worth, itemised for the victory panel to
## count up one award at a time. Filled in by the goal ring -- the shape of an
## entry is described on `goal_ring.gd::_award_breakdown()`.
var last_award: Array[Dictionary] = []

# --- Remembered between sessions ---
## Level path -> value.
var best_score := {}
var best_time := {}

## Set id -> the level numbers beaten in it at least once, in whatever order
## they were played. Shown by the menus; nothing is gated on it, since free play
## lets the levels of an unlocked chapter be taken in any order.
var cleared_levels := {}

## Set id -> true once its challenge run has been finished. This is the only
## thing that unlocks anything.
var challenges_done := {}

## Every gem ever collected, banked for good and spent in the shop. A level's
## own gem tally resets with the level; this never does.
var bank := 0

## Which marble the player is wearing, as a `MarbleSkins` id. Purely cosmetic --
## nothing is gated on it and every skin is always available.
var marble_skin := MarbleSkins.DEFAULT

## Dev override: every world and chapter reads as open, whatever has actually
## been finished. Set from the levels page's dev tools and cleared by resetting.
##
## Kept apart from the real records rather than faking them, so the menus go on
## telling the truth about what has been cleared and challenged, and turning it
## off puts everything back exactly where it was.
var dev_unlock_all := false

var _timing := false
var _timer_started := false
var _run_over := false


func _ready() -> void:
	# The trackers have to outlive every scene change, including the one that
	# happens the instant a level is finished.
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_progress()


func _process(delta: float) -> void:
	if _timing:
		level_time += delta


## Starts a fresh attempt at a level.
##
## Called once per level load, from the HUD. Replaying the level you just failed
## or finished is a new attempt like any other, so this deliberately does NOT
## skip the reset when the path is unchanged -- doing so carried the last run's
## clock and score straight into the next one.
func start_level(level_path: String) -> void:
	current_level = level_path
	level_time = 0.0
	gem_score = 0
	beat_best = false
	last_award = []
	_run_over = false
	set_score(0)

	# Armed, not running. The clock waits for the player -- see `begin_timing()`.
	_timing = false
	_timer_started = false

	_enter_set(level_path)

	# After the set, not before: a fresh attempt puts the climb towards an extra
	# life back to the bottom.
	gem_progress_changed.emit(run_gems, extra_life_target)

	level_started.emit(level_path)


## Works out where the level sits: which set it belongs to, and whether it is
## carrying on a challenge run already under way.
##
## Done from the level's own path rather than handed over by the menu, so a
## level opened straight from the editor lands somewhere sensible too.
func _enter_set(level_path: String) -> void:
	var place := LevelManager.locate(level_path)
	if place.is_empty():
		# Not part of any set -- the scratch test level, or one built but not
		# registered yet. Nothing to unlock, and no run for it to belong to, but
		# it still gets lives so it can be played like anything else.
		run_set = ""
		run_index = 0
		run_world = 0
		run_chapter = ""
		run_mode = Mode.FREE
		_deal_lives()
		return

	var set_id := LevelManager.set_id(place.world, place.chapter)

	# A challenge run keeps its lives, and its climb towards the next extra one,
	# for as long as it is running -- that is what makes it one attempt at the
	# whole set rather than a set of separate levels.
	#
	# Belonging to the run is decided by the SET, not by the level number. An
	# earlier version asked whether this level was the one straight after the
	# last, which quietly broke the moment anything reached a level by another
	# route, and handed out a fresh three lives mid-run.
	#
	# The lives are dealt by `begin_challenge()` when the run starts, so there is
	# nothing to deal here.
	var carries_on: bool = run_mode == Mode.CHALLENGE and set_id == run_set

	if run_mode == Mode.CHALLENGE and not carries_on:
		# A level outside the set the challenge was running in. Whatever that run
		# was, it is not this, so it does not get to bank a challenge on the way
		# past.
		run_mode = Mode.FREE

	run_set = set_id
	run_index = place.index
	run_world = place.world
	run_chapter = place.chapter

	# Free play is every level on its own, with its own three lives.
	if not carries_on:
		_deal_lives()


## Begins a free-play attempt. One level, three lives, nothing riding on it.
## Called by the level list just before it swaps to the level.
func begin_free_play() -> void:
	run_mode = Mode.FREE


## Begins a challenge run at the top of a set. The caller is expected to send
## the player to its first level -- a challenge cannot be joined part way
## through.
##
## The lives are dealt HERE, once, rather than when the first level loads. That
## is what lets every level of the run leave them alone.
func begin_challenge(world: int, chapter: String) -> void:
	run_mode = Mode.CHALLENGE
	run_world = world
	run_chapter = chapter
	run_set = LevelManager.set_id(world, chapter)
	_deal_lives()


## Whether a challenge run is under way, so the game-over screen knows whether
## it is reporting a failed run or just a spent level.
func is_challenge_run() -> bool:
	return run_mode == Mode.CHALLENGE


## Hands out a full set of lives for a fresh attempt, and starts the climb
## towards an extra life over from the bottom.
func _deal_lives() -> void:
	lives = STARTING_LIVES
	_restart_extra_life_climb()
	lives_changed.emit(lives)


## The player has left a level for the menu. Whatever they had built up towards
## the next extra life goes with it: a run is climbed in one sitting.
##
## Called by the menu itself rather than by whatever sent them there, so every
## way back -- the button on the victory panel, a game over, or closing the game
## part way through a level -- lands on the same reset.
##
## The bank is untouched. Those gems are spent, not staked.
func leave_run() -> void:
	# Walking out on a challenge abandons it. Without this the mode would still
	# be set the next time a level loaded, and a single level picked from the
	# list would quietly count as carrying on a run that was already given up.
	run_mode = Mode.FREE

	_restart_extra_life_climb()
	save_progress()


func _restart_extra_life_climb() -> void:
	run_gems = 0
	extra_life_target = FIRST_EXTRA_LIFE
	gem_progress_changed.emit(run_gems, extra_life_target)


## Starts the clock, once. Called the first time the player actually steers, so
## a level is not timed while they are still sizing it up.
func begin_timing() -> void:
	if _timer_started or _run_over:
		return

	_timer_started = true
	_timing = true
	timing_started.emit()


## Whether the clock has been started yet this level.
func is_timing_started() -> bool:
	return _timer_started


func stop_timing() -> void:
	_timing = false


## A gem was picked up. It counts three times over: towards this level's score,
## towards the bank the shop spends, and towards the next extra life.
func collect_gem(points: int) -> void:
	gem_score += points
	add_score(points)

	bank += points
	bank_changed.emit(bank)

	run_gems += points
	_award_extra_life()
	gem_progress_changed.emit(run_gems, extra_life_target)

	# Banked the moment it is picked up, so quitting part way through a level
	# does not cost the player gems they have already collected.
	save_progress()


## Hands out an extra life once the run's gems have reached the bar, then puts
## the count back to nothing with the bar raised.
##
## The gems counted carry from level to level, so the count picks up where the
## last level left it. A set's first extra life comes at 250 gems, the next at
## 350 more, then 450 more -- and a long run may well end before the player has
## found another.
func _award_extra_life() -> void:
	if _run_over:
		return

	if run_gems < extra_life_target:
		return

	lives += 1
	extra_life_target += EXTRA_LIFE_STEP

	# Back to nothing rather than down by the bar: what the counter holds is
	# always the gems found since the last life, which is what it reads as.
	run_gems = 0

	lives_changed.emit(lives)
	extra_life_earned.emit()


## Whether every gem in the level has been taken.
##
## Counted from what is still lying around rather than from a tally gems register
## at startup -- that would depend on whether the gems or the HUD happen to be
## readied first, and would break silently the day someone reorders the scene.
func all_gems_collected() -> bool:
	for gem in get_tree().get_nodes_in_group("gem"):
		if gem.has_method("is_taken") and not gem.is_taken():
			return false
	return true


func add_score(points: int) -> void:
	set_score(score + points)


func set_score(value: int) -> void:
	score = value
	score_changed.emit(score)


## Called when the ball reaches the goal. Banks the run's bests and its place in
## the set, then saves.
##
## The points for clearing are worked out by the goal ring, not here -- what a
## level is worth, and how much a fast run multiplies it, is a property of that
## level rather than of the tracker.
func finish_level(clear_points: int) -> void:
	_timing = false

	add_score(clear_points)

	if current_level.is_empty():
		return

	var beat_score: bool = score > best_score.get(current_level, -1)
	if beat_score:
		best_score[current_level] = score

	var previous_best: float = best_time.get(current_level, INF)
	var beat_time := level_time < previous_best
	if beat_time:
		best_time[current_level] = level_time

	beat_best = beat_score or beat_time

	_bank_progress()
	save_progress()


## Marks the level off, and -- when this was the last level of a challenge run
## -- marks the whole challenge done. That flag is what opens the next
## chapter, so it is the one piece of progress free play can never write.
func _bank_progress() -> void:
	if run_set.is_empty():
		return

	var cleared: Array = cleared_levels.get(run_set, [])
	if not cleared.has(run_index):
		cleared.append(run_index)
		cleared_levels[run_set] = cleared

	if run_mode != Mode.CHALLENGE:
		return

	var length := LevelManager.levels_in(run_world, run_chapter).size()
	if length > 0 and run_index >= length - 1:
		challenges_done[run_set] = true


## Called when the ball falls off the stage.
func lose_life() -> void:
	# Once the run is over it stays over. A ball still tumbling behind the
	# game-over screen would otherwise keep spending lives it does not have, and
	# stack up a fresh game-over screen for each one.
	if _run_over:
		return

	lives -= 1
	lives_changed.emit(lives)

	if lives <= 0:
		# Lives stay at zero while the game-over screen is up, so the HUD behind
		# it reads honestly. They are handed back when the player leaves, in
		# `reset_run()`.
		_run_over = true
		_timing = false
		save_progress()
		run_ended.emit()
		_show_game_over()
		return

	save_progress()


## Puts the player back on their feet after a game over.
##
## Progress is left alone. There is nothing to take away: a failed challenge
## simply never wrote its done flag, and free play was never risking anything in
## the first place.
func reset_run() -> void:
	_run_over = false
	run_mode = Mode.FREE
	_deal_lives()
	save_progress()


## Takes the same challenge on again from the top of its set, and hands back the
## level to load. Empty if there is nothing to go back to.
func restart_challenge() -> String:
	var first := LevelManager.level_at(run_world, run_chapter, 0)
	if first.is_empty():
		return ""

	_run_over = false
	run_mode = Mode.CHALLENGE

	# Dealt here for the same reason as `begin_challenge()`: loading the first
	# level will not do it, because that level belongs to the run.
	_deal_lives()

	return first


func _show_game_over() -> void:
	var scene := load(LevelManager.GAME_OVER) as PackedScene
	if scene == null:
		push_error("GameState: could not load '%s'" % LevelManager.GAME_OVER)
		return

	var current := get_tree().current_scene
	if current != null:
		current.add_child(scene.instantiate())


# --- Progress through the sets ---

## How many of a set's levels have been beaten, in any order and either mode.
## For the menus to show; nothing is gated on it.
func cleared_in(world: int, chapter: String) -> int:
	var cleared: Array = cleared_levels.get(LevelManager.set_id(world, chapter), [])
	return cleared.size()


## Whether one level has been beaten at least once.
func is_level_cleared(world: int, chapter: String, index: int) -> bool:
	var cleared: Array = cleared_levels.get(LevelManager.set_id(world, chapter), [])
	return cleared.has(index)


## Whether this set's challenge run has been finished -- the whole set in one
## attempt without running out of lives.
##
## A set with nothing built for it never counts, so an empty chapter cannot
## unlock the one after it.
func is_challenge_complete(world: int, chapter: String) -> bool:
	if LevelManager.levels_in(world, chapter).is_empty():
		return false

	return challenges_done.get(LevelManager.set_id(world, chapter), false)


## Whether a chapter can be played at all. The easiest one opens as soon as
## its world does; every one after it waits on the CHALLENGE of the chapter
## before it, which is the only thing that unlocks anything.
func is_set_unlocked(world: int, chapter: String) -> bool:
	if dev_unlock_all:
		return true

	var step := LevelManager.CHAPTERS.find(chapter)
	if step > 0:
		return is_challenge_complete(world, LevelManager.CHAPTERS[step - 1])

	return is_world_unlocked(world)


## Whether a level can be opened from the list. Once a chapter is unlocked
## every level in it is, in any order -- the run that has to be done in order is
## the challenge, and that one starts itself at the top.
func is_level_unlocked(world: int, chapter: String, index: int) -> bool:
	if LevelManager.level_at(world, chapter, index).is_empty():
		return false

	return is_set_unlocked(world, chapter)


## Whether a challenge run can be started: the chapter is open and there is
## something in it to run.
func can_start_challenge(world: int, chapter: String) -> bool:
	if LevelManager.levels_in(world, chapter).is_empty():
		return false

	return is_set_unlocked(world, chapter)


## World 1 is always open. Every world after it waits on the whole of the world
## before it -- every chapter's challenge finished. A chapter with no
## levels in it never counts as done, so this stays shut until a world is
## actually built out.
func is_world_unlocked(world: int) -> bool:
	if dev_unlock_all or world <= 1:
		return true

	for chapter in LevelManager.CHAPTERS:
		if not is_challenge_complete(world - 1, chapter):
			return false

	return true


func best_time_for(level_path: String) -> float:
	return best_time.get(level_path, INF)


func best_score_for(level_path: String) -> int:
	return best_score.get(level_path, 0)


## Minutes and seconds, or just seconds under a minute, down to the hundredth.
## Used by the HUD and the menus so a time always reads the same way.
##
## Only the display is rounded. `level_time` and every best time kept in
## `best_time` are full-precision floats, so two runs a millisecond apart are
## still ranked apart even where they read the same.
static func format_time(seconds: float) -> String:
	if is_inf(seconds):
		return "--"

	# Rounded BEFORE the minute is decided. Asking the raw value whether it is
	# under a minute, then rounding it, prints a time a hair short of the minute
	# as "60.00s" instead of turning it over to "1:00.00".
	var rounded := snappedf(seconds, 0.01)

	if rounded < 60.0:
		return "%.2fs" % rounded

	return "%d:%05.2f" % [int(rounded) / 60, fmod(rounded, 60.0)]


## A gem count with its thousands split up, so a full bank stays readable.
static func format_gems(value: int) -> String:
	var digits := str(absi(value))
	var grouped := ""

	while digits.length() > 3:
		grouped = "," + digits.right(3) + grouped
		digits = digits.left(-3)

	grouped = digits + grouped
	return "-" + grouped if value < 0 else grouped


## Picks a marble. Saved straight away: a skin chosen and then never followed by
## a finished level would otherwise be forgotten on quit, and picking one is the
## sort of thing a player expects to stick the moment they do it.
func select_marble_skin(skin_id: String) -> void:
	var resolved := MarbleSkins.resolve(skin_id)
	if resolved == marble_skin:
		return

	marble_skin = resolved
	marble_skin_changed.emit(marble_skin)
	save_progress()


func save_progress() -> void:
	var file := ConfigFile.new()
	file.set_value("run", "lives", lives)
	file.set_value("run", "extra_life_target", extra_life_target)
	file.set_value("bank", "gems", bank)
	file.set_value("best", "score", best_score)
	file.set_value("best", "time", best_time)
	file.set_value("progress", "cleared", cleared_levels)
	file.set_value("progress", "challenges", challenges_done)
	file.set_value("marble", "skin", marble_skin)
	file.set_value("dev", "unlock_all", dev_unlock_all)

	var result := file.save(SAVE_PATH)
	if result != OK:
		push_error("GameState: could not save to '%s' (error %d)" % [SAVE_PATH, result])


func load_progress() -> void:
	var file := ConfigFile.new()
	if file.load(SAVE_PATH) != OK:
		# No save yet, which is the normal state on a first run.
		return

	lives = file.get_value("run", "lives", STARTING_LIVES)
	extra_life_target = file.get_value("run", "extra_life_target", FIRST_EXTRA_LIFE)
	if lives <= 0:
		# Saved part way through a game over. Start the next session playable.
		lives = STARTING_LIVES
	bank = file.get_value("bank", "gems", 0)
	best_score = file.get_value("best", "score", {})
	best_time = file.get_value("best", "time", {})
	cleared_levels = file.get_value("progress", "cleared", {})
	challenges_done = file.get_value("progress", "challenges", {})
	# Resolved on the way in, so a save naming a skin that no longer exists comes
	# back as the default instead of as a marble with no material at all.
	marble_skin = MarbleSkins.resolve(file.get_value("marble", "skin", MarbleSkins.DEFAULT))
	dev_unlock_all = file.get_value("dev", "unlock_all", false)

	# Saves written before challenge runs existed kept one running count
	# per set instead. Carried over so nobody is sent back to the start.
	var legacy: Dictionary = file.get_value("progress", "sets", {})
	if not legacy.is_empty() and cleared_levels.is_empty():
		_adopt_legacy_progress(legacy)
	lives_changed.emit(lives)
	bank_changed.emit(bank)


## Turns the old "how many cleared, in order" count into the level list the
## menus now read, and credits the challenge to any set that count had finished.
func _adopt_legacy_progress(legacy: Dictionary) -> void:
	for set_id: String in legacy:
		var count := int(legacy[set_id])

		var cleared: Array = []
		for index in count:
			cleared.append(index)
		cleared_levels[set_id] = cleared

		var parts := set_id.split("/", true, 1)
		if parts.size() != 2:
			continue

		var length := LevelManager.levels_in(int(parts[0]), parts[1]).size()
		if length > 0 and count >= length:
			challenges_done[set_id] = true


# --- Dev tools ---
# Driven by the dev popup on the levels page, which only opens in a debug build.

## Wipes the save back to a first run: nothing cleared, no challenges, no best
## times or scores, an empty bank, the marble back to the default one, and the
## dev unlock off again.
##
## Written to disk straight away rather than left for the next save, so quitting
## immediately afterwards cannot resurrect the old progress.
func dev_reset_progress() -> void:
	cleared_levels = {}
	challenges_done = {}
	best_score = {}
	best_time = {}
	bank = 0
	dev_unlock_all = false
	marble_skin = MarbleSkins.DEFAULT

	_run_over = false
	run_mode = Mode.FREE
	_deal_lives()

	bank_changed.emit(bank)
	marble_skin_changed.emit(marble_skin)
	save_progress()


## Opens every world and chapter at once. Nothing is marked as finished --
## see `dev_unlock_all` for why -- so `dev_reset_progress()` is the way back off.
func dev_unlock_everything() -> void:
	dev_unlock_all = true
	save_progress()
