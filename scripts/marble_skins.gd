class_name MarbleSkins
extends RefCounted

## Every marble the player can wear.
##
## Laid out the same way as `LevelManager`: one const catalogue that the menus,
## the save file and the ball itself all read from, so adding a skin is a single
## entry here and nothing else.
##
## A skin is a ShaderMaterial on disk. The three families are the three marble
## shaders -- solid_marble, glass_marble and nebula_marble -- and the family is
## only used to group the picker, never to decide anything.
##
## `tint` is what the picker paints its tile with. It is authored here rather
## than read back off the material because the three shaders name their colours
## differently, and a tile should not have to know which shader it is showing.

const SOLID := "Solid"
const ORGANIC := "Organic"
const ANIMATED := "Animated"

## The order families appear in the picker.
const FAMILIES := [SOLID, ORGANIC, ANIMATED]

## What the ball falls back to: a skin that was removed from the catalogue, a
## save from before skins existed, or a first run. Matches the material
## `player.tscn` is authored with, so the fallback never looks like a change.
const DEFAULT := "solid_black"

## id -> the skin. The id is what goes in the save file, so it outlives both the
## display name and the path -- rename either and existing saves still resolve.
const CATALOG := {
	"solid_black": {
		"name": "Black",
		"family": SOLID,
		"tint": Color(0.05, 0.05, 0.06),
		"path": "res://materials/marble/solid/solid_black.tres",
	},
	"solid_white": {
		"name": "White",
		"family": SOLID,
		"tint": Color(0.93, 0.94, 0.96),
		"path": "res://materials/marble/solid/solid_white.tres",
	},
	"solid_red": {
		"name": "Red",
		"family": SOLID,
		"tint": Color(0.85, 0.2, 0.22),
		"path": "res://materials/marble/solid/solid_red.tres",
	},
	"solid_orange": {
		"name": "Orange",
		"family": SOLID,
		"tint": Color(0.95, 0.42, 0.06),
		"path": "res://materials/marble/solid/solid_orange.tres",
	},
	"solid_yellow": {
		"name": "Yellow",
		"family": SOLID,
		"tint": Color(0.96, 0.76, 0.09),
		"path": "res://materials/marble/solid/solid_yellow.tres",
	},
	"solid_green": {
		"name": "Green",
		"family": SOLID,
		"tint": Color(0.0, 0.584, 0.183),
		"path": "res://materials/marble/solid/solid_green.tres",
	},
	"solid_blue": {
		"name": "Blue",
		"family": SOLID,
		"tint": Color(0.166, 0.427, 1.0),
		"path": "res://materials/marble/solid/solid_blue.tres",
	},
	"solid_purple": {
		"name": "Purple",
		"family": SOLID,
		"tint": Color(0.45, 0.18, 0.72),
		"path": "res://materials/marble/solid/solid_purple.tres",
	},
	"solid_brown": {
		"name": "Brown",
		"family": SOLID,
		"tint": Color(0.42, 0.24, 0.12),
		"path": "res://materials/marble/solid/solid_brown.tres",
	},
	"solid_silver": {
		"name": "Silver",
		"family": SOLID,
		"tint": Color(0.78, 0.8, 0.84),
		"path": "res://materials/marble/solid/solid_silver.tres",
	},
	"solid_gold": {
		"name": "Gold",
		"family": SOLID,
		"tint": Color(1.0, 0.78, 0.34),
		"path": "res://materials/marble/solid/solid_gold.tres",
	},
	"organic_bluegreen": {
		"name": "Blue Green",
		"family": ORGANIC,
		"tint": Color(0.16, 0.62, 0.35),
		"path": "res://materials/marble/organic/organic_bluegreen.tres",
	},
	"animated_nebula": {
		"name": "Nebula",
		"family": ANIMATED,
		"tint": Color(0.55, 0.25, 0.95),
		"path": "res://materials/marble/animated/animated_nebula.tres",
	},
}

## Materials already pulled off disk, keyed by id.
##
## A ShaderMaterial is shared, not copied, so every marble wearing a skin is the
## same resource -- and loading one twice would otherwise hand out two, which on
## the animated skin means two lots of shader compilation for the same picture.
static var _loaded := {}


## Every skin id, grouped and in catalogue order. What the picker walks.
static func ids() -> Array:
	var ordered: Array = []

	for family in FAMILIES:
		for id: String in CATALOG:
			if CATALOG[id]["family"] == family:
				ordered.append(id)

	return ordered


static func has(id: String) -> bool:
	return CATALOG.has(id)


## The id to actually use for a stored one. Anything the catalogue does not know
## about -- a removed skin, a corrupted save -- comes back as the default rather
## than as an empty marble.
static func resolve(id: String) -> String:
	return id if CATALOG.has(id) else DEFAULT


static func name_for(id: String) -> String:
	return CATALOG.get(resolve(id), {}).get("name", "Marble")


static func family_for(id: String) -> String:
	return CATALOG.get(resolve(id), {}).get("family", SOLID)


static func tint_for(id: String) -> Color:
	return CATALOG.get(resolve(id), {}).get("tint", Color.WHITE)


## The material for a skin, loaded once and shared from then on.
static func material_for(id: String) -> Material:
	var key := resolve(id)
	if _loaded.has(key):
		return _loaded[key]

	var path: String = CATALOG[key]["path"]
	var material := load(path) as Material
	if material == null:
		push_error("MarbleSkins: could not load '%s' for skin '%s'" % [path, key])
		return null

	_loaded[key] = material
	return material
