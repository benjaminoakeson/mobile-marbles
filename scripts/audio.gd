extends Node

## Every sound the game makes, in one place that outlives the scene that asked
## for it.
##
## Music has to live here: a level change tears the scene down, and the track is
## meant to play straight through it. Asking for the track that is already on
## does nothing at all, which is what keeps "Next Level" from starting it over.
##
## Autoloaded as `Audio`.

# --- Sounds ---
# Small enough to keep loaded. The music is far bigger, so it is loaded only
# when it is asked for.
const GEM := preload("res://audio/Gem.wav")
const DIAMOND_GEM := preload("res://audio/DiamondGem.wav")
const BUMP := preload("res://audio/BumpWood.wav")
const ROLL := preload("res://audio/RollWood.wav")
const FANFARE := preload("res://audio/Fanfare.WAV")

## The pop of the goal ring's confetti going off. Deliberately short: it lands
## on top of the fanfare, and two long jingles at once is a mess.
const CONFETTI := null
const NEW_RECORD := preload("res://audio/HighScore.wav")

## One award landing on the victory panel's running total, and the heavier
## thump of a multiplier landing on it.
## A destructible slab giving way under the ball.
const BREAK := preload("res://audio/TrapWood.wav")

const TALLY := preload("res://audio/Clink.wav")
const MULTIPLIER := preload("res://audio/DoubleBonus.wav")
const EXTRA_LIFE := preload("res://audio/ExtraBall.wav")
const CLICK := preload("res://audio/Highlight.wav")

const MUSIC_BUS := "Music"
const SFX_BUS := "SFX"

## What plays in the menus.
const MENU_MUSIC := "res://audio/music/ConesWorldTheme.mp3"

## What plays in each world's levels. A world with nothing listed falls back to
## the track below, so a new world is never silent while it is being built.
const WORLD_MUSIC := {
	1: "res://audio/music/NiceDay Theme.mp3",
	2: "res://audio/music/CastleWorldTheme.mp3",
	3: "res://audio/music/BrickWorldTheme.mp3",
	4: "res://audio/music/CastleWorldTheme.mp3",
	5: "res://audio/music/CheeseWorldTheme.mp3",
	6: "res://audio/music/ConesWorldTheme.mp3",
	7: "res://audio/music/IceWorldTheme.mp3",
	8: "res://audio/music/SpikeWorldTheme.mp3",
	9: "res://audio/music/ElectronicWorldTheme.mp3",
	10: "res://audio/music/Labyrinth Theme Music.mp3",
}

const DEFAULT_LEVEL_MUSIC := "res://audio/music/Thump Theme.mp3"

## How many one-shots can overlap. Past this the oldest is cut off, which is
## what a fistful of gems taken at once should sound like anyway.
const VOICES := 8

## What `default_bus_layout.tres` sets each bus to, read once before anything
## here has touched them.
##
## The player's sliders are a scale ON these rather than a replacement for them:
## the mix is authored with the music well under the effects, and both sliders at
## the top has to mean the game as it was built to sound.
var _music_baseline := 0.0
var _sfx_baseline := 0.0

var _music: AudioStreamPlayer
var _voices: Array[AudioStreamPlayer] = []
var _next_voice := 0

## What `_music` was last asked for. Compared before anything is touched, so
## asking twice for the same track leaves it playing where it is.
var _music_path := ""


func _ready() -> void:
	# Sound carries on over the game-over and victory panels, which are the
	# moments most worth hearing.
	process_mode = Node.PROCESS_MODE_ALWAYS

	_music = AudioStreamPlayer.new()
	_music.bus = MUSIC_BUS
	add_child(_music)

	for index in VOICES:
		var voice := AudioStreamPlayer.new()
		voice.bus = SFX_BUS
		add_child(voice)
		_voices.append(voice)

	# The level itself does not have to ask for its music: starting one is
	# already announced, and which world it belongs to is enough to know.
	_music_baseline = _bus_volume(MUSIC_BUS)
	_sfx_baseline = _bus_volume(SFX_BUS)

	# GameState is the autoload before this one, so its save is already loaded
	# and these are the player's own levels rather than the defaults.
	GameState.audio_levels_changed.connect(_apply_levels)
	_apply_levels()

	GameState.level_started.connect(_on_level_started)
	GameState.extra_life_earned.connect(_on_extra_life_earned)


## Plays a one-shot. Each call takes the next voice round, so sounds that land
## together overlap instead of cutting one another off.
##
## Returns how long the sound will be audible for, in seconds, so a caller with
## something to say afterwards can hold off until this one has finished -- the
## victory panel's record fanfare does exactly that. Ignore it freely; almost
## every sound in the game is meant to overlap whatever else is going on.
func play(stream: AudioStream, volume_db := 0.0, pitch := 1.0) -> float:
	if stream == null:
		return 0.0

	var voice := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()

	voice.stream = stream
	voice.volume_db = volume_db
	voice.pitch_scale = pitch
	voice.play()

	# Pitched up, a sound is over sooner -- and what the caller is waiting on is
	# how long it will be heard for, not how long it was recorded at.
	return stream.get_length() / maxf(pitch, 0.01)


## Puts a track on, or leaves the one that is playing exactly where it is when
## it is the same track. That second half is the whole point of this living in
## an autoload -- see the note at the top.
func play_music(path: String) -> void:
	if path == _music_path and _music.playing:
		return

	_music_path = path

	if path.is_empty():
		_music.stop()
		return

	var stream := load(path) as AudioStream
	if stream == null:
		push_warning("Audio: no music at '%s'" % path)
		_music.stop()
		return

	# Set here rather than on the import, so dropping a new track in is enough
	# to have it loop.
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true

	_music.stream = stream
	_music.play()


func stop_music() -> void:
	play_music("")


## Which track a level plays: whatever its world plays.
##
## A level outside the catalogue -- the scratch test level, or one opened
## straight from the editor -- keeps whatever was already on rather than
## dropping into silence.
func music_for_level(level_path: String) -> String:
	var place := LevelManager.locate(level_path)
	if place.is_empty():
		return _music_path

	return WORLD_MUSIC.get(place.world, DEFAULT_LEVEL_MUSIC)


## Puts the player's two levels onto the buses.
func _apply_levels() -> void:
	_set_level(MUSIC_BUS, _music_baseline, GameState.music_volume)
	_set_level(SFX_BUS, _sfx_baseline, GameState.sfx_volume)


## A slider is linear in how loud a thing SEEMS; a bus is in decibels. The
## conversion is what makes the bottom half of the slider do as much work as the
## top half, rather than everything happening in the last few pixels.
##
## Nothing is ever turned down to true silence in decibels -- it has no bottom --
## so a slider at zero mutes the bus outright instead.
func _set_level(bus: String, baseline_db: float, level: float) -> void:
	var index := AudioServer.get_bus_index(bus)
	if index < 0:
		push_warning("Audio: no '%s' bus to set" % bus)
		return

	AudioServer.set_bus_mute(index, level <= 0.001)
	AudioServer.set_bus_volume_db(index, baseline_db + linear_to_db(maxf(level, 0.001)))


func _bus_volume(bus: String) -> float:
	var index := AudioServer.get_bus_index(bus)
	return AudioServer.get_bus_volume_db(index) if index >= 0 else 0.0


## Gives every button under a menu its click, so no button has to remember to
## make a noise itself. Safe to call again over buttons built later.
func wire_clicks(root: Node) -> void:
	_wire_click(root)
	for node in root.find_children("*", "Button", true, false):
		_wire_click(node)


func _wire_click(node: Node) -> void:
	var button := node as Button
	if button != null and not button.pressed.is_connected(_play_click):
		button.pressed.connect(_play_click)


func _play_click() -> void:
	play(CLICK)


func _on_level_started(level_path: String) -> void:
	play_music(music_for_level(level_path))


func _on_extra_life_earned() -> void:
	play(EXTRA_LIFE)
