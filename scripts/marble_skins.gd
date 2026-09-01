class_name MarbleSkins
extends RefCounted

## Every marble the player can wear.
##
## Laid out the same way as `LevelManager`: one const catalogue that the menus,
## the save file and the ball itself all read from, so adding a skin is a single
## entry here and nothing else.
##
## A skin is a ShaderMaterial on disk. What groups them here is RARITY -- how
## hard a marble is to come by -- and not what it is made of: which shader draws
## a skin has nothing to do with which tier it sits in, and the tiers hold a
## mixture. Rarity is what the shop charges for and what the menus colour by,
## and a level never asks about either.
##
## The tiers run Common to Transcendent. The last three are empty on purpose --
## they are where the marbles still to be drawn will go. An empty tier costs
## nothing: the picker skips it and the shop simply never rolls one.
##
## `tint` is what the picker paints its tile with. It is authored here rather
## than read back off the material because the shaders all name their colours
## differently, and a tile should not have to know which one it is showing.
##
## `trail` and `trail_glow` are what the marble leaves on the ground behind it --
## see [RollMarks]. Authored here for the same reason as the tint: what a lava
## marble smears across the floor is a fact about the skin, and the marks have no
## business reading a shader to work it out. A skin with no trail of its own
## presses a plain dent, which is what every solid and every set-glass marble
## does; the animated ones are the ones that leave something behind them.

const COMMON := "Common"
const UNCOMMON := "Uncommon"
const RARE := "Rare"
const EPIC := "Epic"
const LEGENDARY := "Legendary"
const MYTHIC := "Mythic"
const CELESTIAL := "Celestial"
const TRANSCENDENT := "Transcendent"

## The tiers, commonest first. This is the order the picker stacks them in and
## the order the shop weighs them by, so it is the one place that decides what
## "rarer" means.
const RARITIES := [
	COMMON,
	UNCOMMON,
	RARE,
	EPIC,
	LEGENDARY,
	MYTHIC,
	CELESTIAL,
	TRANSCENDENT,
]

## What the menus paint a tier in. The ladder players already know from
## everywhere else -- grey, green, blue, purple, orange -- carried up through red
## and gold to white at the top.
##
## Lifted off the pure hues: a saturated blue or purple on a dark menu reads as
## a hole rather than a colour, and these have to work as text as well as trim.
const RARITY_COLOURS := {
	COMMON: Color(0.62, 0.65, 0.68),
	UNCOMMON: Color(0.36, 0.78, 0.38),
	RARE: Color(0.31, 0.6, 0.96),
	EPIC: Color(0.67, 0.38, 0.94),
	LEGENDARY: Color(1.0, 0.58, 0.16),
	MYTHIC: Color(0.94, 0.28, 0.31),
	CELESTIAL: Color(1.0, 0.84, 0.2),
	TRANSCENDENT: Color(1.0, 1.0, 1.0),
}

## What a marble costs in the shop, in gems, by tier.
##
## Priced by RARITY rather than one at a time: eight numbers to keep in step
## instead of sixty-three, and a price a player can predict from the colour of
## the tile before they have read it.
##
## The ladder is roughly fifteen levels' gems for a common one and a hundred for
## a legendary, which is what the three families it replaced were worth. The top
## three are priced for marbles that do not exist yet, so they are a guess -- but
## a guess nothing can be bought with until something is put in those tiers.
const PRICES := {
	COMMON: 300,
	UNCOMMON: 500,
	RARE: 800,
	EPIC: 1200,
	LEGENDARY: 2000,
	MYTHIC: 3500,
	CELESTIAL: 6000,
	TRANSCENDENT: 10000,
}

## What the ball falls back to: a skin that was removed from the catalogue, a
## save from before skins existed, or a first run. Matches the material
## `player.tscn` is authored with, so the fallback never looks like a change.
const DEFAULT := "solid_black"

## id -> the skin. The id is what goes in the save file, so it outlives both the
## display name and the path -- rename either and existing saves still resolve.
const CATALOG := {
	"solid_black": {
		"name": "Black",
		"rarity": COMMON,
		"tint": Color(0.05, 0.05, 0.06),
		"path": "res://materials/marble/solid/solid_black.tres",
	},
	"solid_white": {
		"name": "White",
		"rarity": COMMON,
		"tint": Color(0.93, 0.94, 0.96),
		"path": "res://materials/marble/solid/solid_white.tres",
	},
	"solid_red": {
		"name": "Red",
		"rarity": COMMON,
		"tint": Color(0.85, 0.2, 0.22),
		"path": "res://materials/marble/solid/solid_red.tres",
	},
	"solid_orange": {
		"name": "Orange",
		"rarity": COMMON,
		"tint": Color(0.95, 0.42, 0.06),
		"path": "res://materials/marble/solid/solid_orange.tres",
	},
	"solid_yellow": {
		"name": "Yellow",
		"rarity": COMMON,
		"tint": Color(0.96, 0.76, 0.09),
		"path": "res://materials/marble/solid/solid_yellow.tres",
	},
	"solid_green": {
		"name": "Green",
		"rarity": COMMON,
		"tint": Color(0.0, 0.584, 0.183),
		"path": "res://materials/marble/solid/solid_green.tres",
	},
	"solid_blue": {
		"name": "Blue",
		"rarity": COMMON,
		"tint": Color(0.166, 0.427, 1.0),
		"path": "res://materials/marble/solid/solid_blue.tres",
	},
	"solid_purple": {
		"name": "Purple",
		"rarity": COMMON,
		"tint": Color(0.45, 0.18, 0.72),
		"path": "res://materials/marble/solid/solid_purple.tres",
	},
	"solid_brown": {
		"name": "Brown",
		"rarity": COMMON,
		"tint": Color(0.42, 0.24, 0.12),
		"path": "res://materials/marble/solid/solid_brown.tres",
	},
	"solid_silver": {
		"name": "Silver",
		"rarity": COMMON,
		"tint": Color(0.78, 0.8, 0.84),
		"path": "res://materials/marble/solid/solid_silver.tres",
	},
	"solid_gold": {
		"name": "Gold",
		"rarity": COMMON,
		"tint": Color(1.0, 0.78, 0.34),
		"path": "res://materials/marble/solid/solid_gold.tres",
	},
	"glass_cats_eye": {
		"name": "Cat's Eye",
		"rarity": UNCOMMON,
		"tint": Color(0.86, 0.82, 0.25),
		"path": "res://materials/marble/glass/glass_cats_eye.tres",
	},
	"glass_corkscrew": {
		"name": "Corkscrew",
		"rarity": UNCOMMON,
		"tint": Color(0.88, 0.25, 0.28),
		"path": "res://materials/marble/glass/glass_corkscrew.tres",
	},
	"glass_cobalt_swirl": {
		"name": "Cobalt Swirl",
		"rarity": UNCOMMON,
		"tint": Color(0.15, 0.32, 0.9),
		"path": "res://materials/marble/glass/glass_cobalt_swirl.tres",
	},
	"glass_latticinio": {
		"name": "Latticinio",
		"rarity": UNCOMMON,
		"tint": Color(0.92, 0.93, 0.95),
		"path": "res://materials/marble/glass/glass_latticinio.tres",
	},
	"glass_onionskin": {
		"name": "Onionskin",
		"rarity": UNCOMMON,
		"tint": Color(0.98, 0.55, 0.12),
		"path": "res://materials/marble/glass/glass_onionskin.tres",
	},
	"glass_banded_agate": {
		"name": "Banded Agate",
		"rarity": UNCOMMON,
		"tint": Color(0.68, 0.5, 0.3),
		"path": "res://materials/marble/glass/glass_banded_agate.tres",
	},
	"glass_oxblood": {
		"name": "Oxblood",
		"rarity": UNCOMMON,
		"tint": Color(0.45, 0.08, 0.06),
		"path": "res://materials/marble/glass/glass_oxblood.tres",
	},
	"glass_lutz": {
		"name": "Lutz",
		"rarity": RARE,
		"tint": Color(0.15, 0.72, 0.72),
		"path": "res://materials/marble/glass/glass_lutz.tres",
	},
	"glass_clearie": {
		"name": "Clearie",
		"rarity": RARE,
		"tint": Color(0.3, 0.85, 0.55),
		"path": "res://materials/marble/glass/glass_clearie.tres",
	},
	"glass_opal": {
		"name": "Opal",
		"rarity": RARE,
		"tint": Color(0.86, 0.84, 0.95),
		"path": "res://materials/marble/glass/glass_opal.tres",
	},
	"glass_galaxy": {
		"name": "Galaxy",
		"rarity": RARE,
		"tint": Color(0.42, 0.18, 0.7),
		"path": "res://materials/marble/glass/glass_galaxy.tres",
	},
	"glass_sparkler": {
		"name": "Sparkler",
		"rarity": RARE,
		"tint": Color(0.78, 0.85, 0.92),
		"path": "res://materials/marble/glass/glass_sparkler.tres",
	},
	"glass_peppermint": {
		"name": "Peppermint",
		"rarity": UNCOMMON,
		"tint": Color(0.9, 0.25, 0.35),
		"path": "res://materials/marble/glass/glass_peppermint.tres",
	},
	"glass_ribbon_core": {
		"name": "Ribbon Core",
		"rarity": UNCOMMON,
		"tint": Color(1, 0.6, 0.15),
		"path": "res://materials/marble/glass/glass_ribbon_core.tres",
	},
	"glass_sea_glass": {
		"name": "Sea Glass",
		"rarity": UNCOMMON,
		"tint": Color(0.55, 0.8, 0.72),
		"path": "res://materials/marble/glass/glass_sea_glass.tres",
	},
	"glass_millefiori": {
		"name": "Millefiori",
		"rarity": RARE,
		"tint": Color(0.85, 0.3, 0.42),
		"path": "res://materials/marble/glass/glass_millefiori.tres",
	},
	"glass_crackle": {
		"name": "Crackle",
		"rarity": RARE,
		"tint": Color(0.75, 0.86, 0.95),
		"path": "res://materials/marble/glass/glass_crackle.tres",
	},
	"glass_bubble": {
		"name": "Seed Bubbles",
		"rarity": RARE,
		"tint": Color(0.6, 0.8, 0.88),
		"path": "res://materials/marble/glass/glass_bubble.tres",
	},
	"glass_aventurine": {
		"name": "Goldstone",
		"rarity": EPIC,
		"tint": Color(0.7, 0.35, 0.12),
		"path": "res://materials/marble/glass/glass_aventurine.tres",
	},
	"glass_sulphide": {
		"name": "Sulphide",
		"rarity": RARE,
		"tint": Color(0.88, 0.9, 0.94),
		"path": "res://materials/marble/glass/glass_sulphide.tres",
	},
	"glass_moonstone": {
		"name": "Moonstone",
		"rarity": UNCOMMON,
		"tint": Color(0.82, 0.86, 0.95),
		"path": "res://materials/marble/glass/glass_moonstone.tres",
	},
	"glass_tiger_eye": {
		"name": "Tiger Eye",
		"rarity": EPIC,
		"tint": Color(0.72, 0.48, 0.12),
		"path": "res://materials/marble/glass/glass_tiger_eye.tres",
	},
	"glass_confetti": {
		"name": "Confetti",
		"rarity": RARE,
		"tint": Color(0.9, 0.55, 0.75),
		"path": "res://materials/marble/glass/glass_confetti.tres",
	},
	"glass_prism": {
		"name": "Prism",
		"rarity": RARE,
		"tint": Color(0.78, 0.88, 0.98),
		"path": "res://materials/marble/glass/glass_prism.tres",
	},
	"glass_helix": {
		"name": "Helix",
		"rarity": UNCOMMON,
		"tint": Color(0.25, 0.75, 0.85),
		"path": "res://materials/marble/glass/glass_helix.tres",
	},
	"organic_bluegreen": {
		"name": "Blue Green",
		"rarity": EPIC,
		"tint": Color(0.16, 0.62, 0.35),
		"path": "res://materials/marble/animated/organic_bluegreen.tres",
		"trail": Color(0.2, 0.8, 0.55),
		"trail_glow": 0.4,
	},
	"animated_lava": {
		"name": "Lava",
		"rarity": EPIC,
		"tint": Color(0.9, 0.35, 0.05),
		"path": "res://materials/marble/animated/animated_lava.tres",
		"trail": Color(1, 0.32, 0.04),
		"trail_glow": 0.95,
	},
	"animated_plasma": {
		"name": "Plasma",
		"rarity": LEGENDARY,
		"tint": Color(0.35, 0.6, 1),
		"path": "res://materials/marble/animated/animated_plasma.tres",
		"trail": Color(0.45, 0.7, 1),
		"trail_glow": 0.85,
	},
	"animated_aurora": {
		"name": "Aurora",
		"rarity": LEGENDARY,
		"tint": Color(0.2, 0.85, 0.6),
		"path": "res://materials/marble/animated/animated_aurora.tres",
		"trail": Color(0.25, 0.95, 0.6),
		"trail_glow": 0.7,
	},
	"animated_ember": {
		"name": "Ember",
		"rarity": RARE,
		"tint": Color(0.85, 0.4, 0.1),
		"path": "res://materials/marble/animated/animated_ember.tres",
		"trail": Color(1, 0.36, 0.08),
		"trail_glow": 0.6,
	},
	"animated_deep_sea": {
		"name": "Deep Sea",
		"rarity": LEGENDARY,
		"tint": Color(0.05, 0.45, 0.55),
		"path": "res://materials/marble/animated/animated_deep_sea.tres",
		"trail": Color(0.15, 0.7, 0.7),
		"trail_glow": 0.35,
	},
	"animated_storm": {
		"name": "Storm",
		"rarity": LEGENDARY,
		"tint": Color(0.5, 0.55, 0.65),
		"path": "res://materials/marble/animated/animated_storm.tres",
		"trail": Color(0.7, 0.75, 0.85),
		"trail_glow": 0.3,
	},
	"animated_toxic": {
		"name": "Toxic",
		"rarity": LEGENDARY,
		"tint": Color(0.45, 0.85, 0.15),
		"path": "res://materials/marble/animated/animated_toxic.tres",
		"trail": Color(0.55, 0.95, 0.15),
		"trail_glow": 0.75,
	},
	"animated_sunburst": {
		"name": "Sunburst",
		"rarity": LEGENDARY,
		"tint": Color(1, 0.7, 0.15),
		"path": "res://materials/marble/animated/animated_sunburst.tres",
		"trail": Color(1, 0.72, 0.18),
		"trail_glow": 0.9,
	},
	"animated_frost": {
		"name": "Frost",
		"rarity": EPIC,
		"tint": Color(0.75, 0.9, 1),
		"path": "res://materials/marble/animated/animated_frost.tres",
		"trail": Color(0.75, 0.9, 1),
		"trail_glow": 0.3,
	},
	"animated_void": {
		"name": "Void",
		"rarity": LEGENDARY,
		"tint": Color(0.15, 0.08, 0.3),
		"path": "res://materials/marble/animated/animated_void.tres",
		"trail": Color(0.45, 0.2, 0.85),
		"trail_glow": 0.35,
	},
	"animated_whirlpool": {
		"name": "Whirlpool",
		"rarity": LEGENDARY,
		"tint": Color(0.1, 0.6, 0.75),
		"path": "res://materials/marble/animated/animated_whirlpool.tres",
		"trail": Color(0.2, 0.7, 0.9),
		"trail_glow": 0.35,
	},
	"animated_oil_slick": {
		"name": "Oil Slick",
		"rarity": LEGENDARY,
		"tint": Color(0.55, 0.5, 0.85),
		"path": "res://materials/marble/animated/animated_oil_slick.tres",
		"trail": Color(0.6, 0.35, 0.9),
		"trail_glow": 0.4,
	},
	"animated_firefly": {
		"name": "Firefly",
		"rarity": LEGENDARY,
		"tint": Color(0.4, 0.6, 0.2),
		"path": "res://materials/marble/animated/animated_firefly.tres",
		"trail": Color(1, 0.92, 0.45),
		"trail_glow": 0.6,
	},
	"animated_jellyfish": {
		"name": "Jellyfish",
		"rarity": LEGENDARY,
		"tint": Color(0.9, 0.5, 0.8),
		"path": "res://materials/marble/animated/animated_jellyfish.tres",
		"trail": Color(1, 0.5, 0.85),
		"trail_glow": 0.5,
	},
	"animated_smoke": {
		"name": "Smoke",
		"rarity": EPIC,
		"tint": Color(0.55, 0.57, 0.62),
		"path": "res://materials/marble/animated/animated_smoke.tres",
		"trail": Color(0.55, 0.57, 0.62),
		"trail_glow": 0.15,
	},
	"animated_rainfall": {
		"name": "Rainfall",
		"rarity": LEGENDARY,
		"tint": Color(0.45, 0.6, 0.72),
		"path": "res://materials/marble/animated/animated_rainfall.tres",
		"trail": Color(0.55, 0.72, 0.9),
		"trail_glow": 0.2,
	},
	"animated_fireworks": {
		"name": "Fireworks",
		"rarity": LEGENDARY,
		"tint": Color(0.95, 0.5, 0.35),
		"path": "res://materials/marble/animated/animated_fireworks.tres",
		"trail": Color(1, 0.7, 0.35),
		"trail_glow": 0.6,
	},
	"animated_clockwork": {
		"name": "Clockwork",
		"rarity": EPIC,
		"tint": Color(0.75, 0.58, 0.25),
		"path": "res://materials/marble/animated/animated_clockwork.tres",
		"trail": Color(0.85, 0.65, 0.3),
		"trail_glow": 0.25,
	},
	"animated_kaleidoscope": {
		"name": "Kaleidoscope",
		"rarity": LEGENDARY,
		"tint": Color(0.7, 0.35, 0.85),
		"path": "res://materials/marble/animated/animated_kaleidoscope.tres",
		"trail": Color(0.9, 0.25, 0.8),
		"trail_glow": 0.55,
	},
	"animated_ripples": {
		"name": "Ripples",
		"rarity": LEGENDARY,
		"tint": Color(0.3, 0.65, 0.8),
		"path": "res://materials/marble/animated/animated_ripples.tres",
		"trail": Color(0.35, 0.75, 0.95),
		"trail_glow": 0.3,
	},
	"animated_blizzard": {
		"name": "Blizzard",
		"rarity": EPIC,
		"tint": Color(0.8, 0.88, 0.95),
		"path": "res://materials/marble/animated/animated_blizzard.tres",
		"trail": Color(0.9, 0.95, 1),
		"trail_glow": 0.3,
	},
	"animated_wormhole": {
		"name": "Wormhole",
		"rarity": LEGENDARY,
		"tint": Color(0.35, 0.2, 0.7),
		"path": "res://materials/marble/animated/animated_wormhole.tres",
		"trail": Color(0.5, 0.25, 0.95),
		"trail_glow": 0.5,
	},
	"animated_little_world": {
		"name": "Little World",
		"rarity": LEGENDARY,
		"tint": Color(0.25, 0.55, 0.4),
		"path": "res://materials/marble/animated/animated_little_world.tres",
		"trail": Color(0.3, 0.7, 0.5),
		"trail_glow": 0.3,
	},
	"animated_heartbeat": {
		"name": "Heartbeat",
		"rarity": LEGENDARY,
		"tint": Color(0.8, 0.15, 0.25),
		"path": "res://materials/marble/animated/animated_heartbeat.tres",
		"trail": Color(0.95, 0.2, 0.25),
		"trail_glow": 0.55,
	},
	"animated_static": {
		"name": "Static",
		"rarity": LEGENDARY,
		"tint": Color(0.6, 0.62, 0.65),
		"path": "res://materials/marble/animated/animated_static.tres",
		"trail": Color(0.8, 0.82, 0.85),
		"trail_glow": 0.45,
	},
	"animated_nebula": {
		"name": "Nebula",
		"rarity": LEGENDARY,
		"tint": Color(0.55, 0.25, 0.95),
		"path": "res://materials/marble/animated/animated_nebula.tres",
		"trail": Color(0.75, 0.35, 1),
		"trail_glow": 0.6,
	},
}

## Materials already pulled off disk, keyed by id.
##
## A ShaderMaterial is shared, not copied, so every marble wearing a skin is the
## same resource -- and loading one twice would otherwise hand out two, which on
## the animated skin means two lots of shader compilation for the same picture.
static var _loaded := {}


## Every skin id, grouped by tier commonest first and in catalogue order within
## a tier. What the picker walks.
static func ids() -> Array:
	var ordered: Array = []

	for rarity: String in RARITIES:
		ordered.append_array(ids_in(rarity))

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


## Which tier a skin sits in. Anything the catalogue does not know comes back as
## the commonest, which is the only answer that can never overcharge a player.
static func rarity_for(id: String) -> String:
	return CATALOG.get(resolve(id), {}).get("rarity", COMMON)


## What to paint a skin's tier in -- see [constant RARITY_COLOURS].
static func colour_for(id: String) -> Color:
	return colour_of(rarity_for(id))


## The same, for a tier that is not being asked about through a skin: a heading
## over a group, say, or a tier with nothing in it yet.
static func colour_of(rarity: String) -> Color:
	return RARITY_COLOURS.get(rarity, Color.WHITE)


## Every id in one tier, in catalogue order. Empty for a tier nothing has been
## put in yet, which is a real answer and not a mistake.
static func ids_in(rarity: String) -> Array:
	var ordered: Array = []

	for id: String in CATALOG:
		if CATALOG[id]["rarity"] == rarity:
			ordered.append(id)

	return ordered


static func tint_for(id: String) -> Color:
	return CATALOG.get(resolve(id), {}).get("tint", Color.WHITE)


## What a skin costs. Zero for anything the catalogue does not know, which is
## also what the default marble is worth -- it is owned before the shop opens.
static func price_for(id: String) -> int:
	return PRICES.get(rarity_for(id), 0)


## What a skin leaves on the ground: the colour of it, and how much of that is
## light rather than only colour. A glow of zero is a plain dent in the floor,
## which is what a skin with nothing to leave behind comes back as.
static func trail_for(id: String) -> Dictionary:
	var skin: Dictionary = CATALOG.get(resolve(id), {})
	return {
		"colour": skin.get("trail", Color.WHITE) as Color,
		"glow": skin.get("trail_glow", 0.0) as float,
	}


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
