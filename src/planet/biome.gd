class_name Biome
extends RefCounted
## Biome ids and how each one is drawn. Stored per tile in PlanetData.biome.

enum { OCEAN, POLAR, TUNDRA, GRASSLAND, DESERT, JUNGLE, MOUNTAIN }

const NAMES := ["Ocean", "Polar ice", "Tundra / pine", "Grassland", "Desert", "Jungle / marsh", "Mountains"]

## Palette swatch for the side of a terrace, by biome.
const CLIFF_SWATCH := ["seabed_cliff", "ice_cliff", "stone", "dirt", "sandstone", "dirt_dark", "stone_dark"]
