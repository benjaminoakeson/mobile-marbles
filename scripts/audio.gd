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
	2: "res://audio/music/BilliardWorldTheme.mp3",
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
	GameState.level_started.connect(_on_level_started)
	GameState.extra_life_earned.connect(_on_extra_life_earned)


## Plays a one-shot. Each call takes the next voice round, so sounds that land
## together overlap instead of cutting one another off.
func play(stream: AudioStream, volume_db := 0.0, pitch := 1.0) -> void:
	if stream == null:
		return

	var voice := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()

	voice.stream = stream
	voice.volume_db = volume_db
	voice.pitch_scale = pitch
	voice.play()


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
