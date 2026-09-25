# Pocket Orbit: Little Haven

A cozy low-poly life sim: run a trading post on a tiny planet you can walk all the way around. The full plan is in [GAME_PLAN.md](GAME_PLAN.md).

Built with **Godot 4.7** (GDScript, Mobile renderer) for iOS and Android. The PC build is for development only.

## Running it

Open the folder in Godot 4.7 and press **Play** (F5). Or from a terminal:

```sh
godot --path .
```

### Playing

You've just arrived on Little Haven owing Vessa, the smuggler who got you here, 8,000 Stardust. Gather things, put them on your market stall's four shelves, set prices, and pay her back from what travellers buy.

- **Fish** from the shore: cast, wait for the bobber to dip, then press the action button. Colder seas and night time have different fish.
- **Bugs** flutter around. Walk (don't run) up to one and swing the net.
- **Trees and rocks**: shake a fruit tree once a day, chop wood, mine rocks for minerals.
- **The stall**: stock shelves from your backpack and set each price with the slider. Customers compare it with what the item is worth today (see the demand board). Fair prices build reputation, which brings more customers.
- **Vessa** stands by the stall: talk to her to pay down your debt or get tips. Your cargo-pod home has a storage chest.

Once word gets around (reputation), Little Haven becomes a sanctuary:

- **Mail** (top left): refugees write asking to move in. Welcome them into an empty cottage or a burrow house you've built. Mossbacks come first; Glims need a landing pad, Burrls an Archive. Villagers walk about, shop (paying more for what their kind likes) and give you gifts as you become friends.
- **Village plots** (the roped-off squares): build a landing pad, the Archive or a burrow house. The stall upgrades to a **general shop** with 12 shelves and your own opening hours.
- **Drone mail**: with a landing pad, order anything you've found before from the catalogue in the Mail menu. It lands on the pad the next morning.
- **The Archive** collects one of every fish, bug, mineral, fossil and shore find.
- **Dig spots** (little cracked mounds) turn up every day: dig for fossils and clay.
- **Tides** follow the moon: at low tide the sea drops off the shallow shore and **tide pools** can be searched.
- **Seasons** follow the calendar (opposite in the south): some fish and bugs only come in some seasons, leaves turn in autumn and snow settles in winter. Rain, snow, fireflies and falling leaves come and go.
- **Inspector Grell** of the Confederation turns up now and then (a letter warns you the day before). Answer the questions without raising suspicion, and don't leave the inspector waiting.

The game saves by itself (every 45 seconds when something changed, and on quit) to `user://save.json`. Start over with `-- --new-game`.

### Controls

| Input | Action |
| --- | --- |
| Tap / click the ground | Walk there (tap a tree, bug, the stall or Vessa to walk up and use it) |
| WASD / arrows, or the on-screen stick | Walk |
| Shift / Space | Run / jump |
| E (or the big button) | Action: fish, catch, chop, mine, dig, search, build, shop, talk |
| I / B (or the Bag button) | Backpack |
| Right-drag (or touch-drag) | Turn and tilt the camera |
| Mouse wheel / Z, C | Zoom / turn the camera |
| Tab | Orbit view |
| Esc | Close a menu |
| F1 | Developer panel: FPS, time controls, new game on another seed |
| `[` `]` | Time back / forward one hour |

The sun follows your real clock. The developer panel's time slider and speeds (x60 and up) switch to a simulated clock; a fast clock also moves the days on (new demand, trees to harvest again). **Real** switches back.

## Checks

```sh
godot --headless --import                        # once, so Godot registers the classes
godot --headless --script res://tests/run_tests.gd
```

The tests cover the hex sphere (2,562 tiles, 12 pentagons, shared edges), tile lookup, generator determinism and biomes, mesh size, walking rules, items and inventory, the economy, every command, saving and loading, pathfinding and props, how customers decide, seasons and tides, and the sanctuary rules (move-ins, building, drone mail, the Archive, friendship, the inspector's schedule).

To play through the Phase 1 and 2 loops automatically (meet Vessa, gather, fish, catch a bug, stock the stall, sell, pay the debt; then build a landing pad, order by drone mail, welcome a villager and chat, upgrade to the general shop, dig, search a tide pool at low tide and get through an inspection), with screenshots and a report:

```sh
godot --path . -- --playtest=/some/folder
```

To save a set of screenshots at different times of day, the finished village, a tide pool, autumn and winter (and a walk over the north pole), run:

```sh
godot --path . -- --tour=/some/folder
```

## Models

Trees, rocks, bushes, cacti, palms, ice spires, shrines, the market stall and general shop, cottages, the cargo-pod home, the landing pad, the Archive, burrow houses, tide pools, fences, plot markers and the lamp post are built by a Blender script and exported to `assets/models/` (stored with Git LFS):

```sh
blender -b -P tools/blender/build_assets.py              # all models
blender -b -P tools/blender/build_assets.py -- cottage   # just one
```

Each model gets a close-up version and a much simpler far-away one (`_lod1`). Colours come from the shared palette in `src/render/palette.gd`, and the soft corner shading is baked into vertex colours. After rebuilding, run `godot --headless --import`. To see every model lit by the game's shader, run:

```sh
godot --path . --script res://tools/model_gallery.gd -- --out=gallery.png [--focus=cottage]
```

## Layout

```
data/         items.json (every fish, bug, mineral, material, fruit, fossil and shore find)
              village.json (refugee species, buildings, the inspector's questions)
src/planet/   HexSphere, PlanetGenerator, PlanetData, PropPlacer, PlanetMesher, Planet, TileGraph
src/game/     rules: GameState, Commands, Economy, ItemDatabase, Inventory, CatchTables, SaveSystem,
                     VillageData, VillageRules, Seasons, Tides
              in the world: Game, Interactions, Fishing, BugSwarm, Customers, WorldItems, Village, DigSpots, Weather
src/actors/   GravityBody (walking on a sphere, routes), Player, Npc (customers, Vessa, villagers, the inspector)
src/camera/   PlanetCamera (tangent-frame third-person camera, orbit view)
src/sky/      SkySystem (clock, sun, moon and tides, space sky), CloudLayer
src/render/   Palette (the shared palette texture), MeshData (mesh building), PropLibrary (loads models), ItemMeshes
src/ui/       GameHud and its menus (backpack, shop, storage, Vessa, mail, build, Archive, villager, inspection), UiTheme, ItemIcon, DebugHud, TouchStick
shaders/      planet surface, water, atmosphere, space sky
tests/        headless checks
tools/        screenshot tour, playtest, model gallery, blender/ (model build script)
```

Concept art lives in `images art direction/` and `images ui direction/`. Those folders contain a `.gdignore` file so Godot doesn't import them. New game assets (models, textures, audio) go under `assets/` and are stored with Git LFS.
