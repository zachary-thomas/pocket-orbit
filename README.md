# Pocket Orbit: Little Haven

A cozy low-poly life sim: run a trading post on a tiny planet you can walk all the way around. The full plan is in [GAME_PLAN.md](GAME_PLAN.md).

Built with **Godot 4.7** (GDScript, Mobile renderer) for iOS and Android. The PC build is for development only.

## Running it

Open the folder in Godot 4.7 and press **Play** (F5). Or from a terminal:

```sh
godot --path .
```

### Controls (look test)

| Input | Action |
| --- | --- |
| WASD / arrows, or the on-screen stick | Walk |
| Shift / Space | Run / jump |
| Right-drag (or left-drag / touch-drag) | Turn and tilt the camera |
| Mouse wheel / Q, E | Zoom / turn the camera |
| Tab | Orbit view |
| `[` `]` | Time back / forward one hour |
| F1 | Hide the debug panel |

The debug panel (top right) shows FPS and triangles on screen, local time and the current tile. It also has a time-of-day slider, clock speeds, and a seed box to regenerate the planet. The sun follows your real clock until you touch the time controls. **Real** switches back to it.

## Checks

```sh
godot --headless --import                        # once, so Godot registers the classes
godot --headless --script res://tests/run_tests.gd
```

The tests cover the hex sphere (2,562 tiles, 12 pentagons, shared edges), tile lookup, generator determinism and biomes, mesh size, and walking rules.

To save a set of screenshots at different times of day (and a walk over the north pole), run:

```sh
godot --path . -- --tour=/some/folder
```

## Layout

```
src/planet/   HexSphere, PlanetGenerator, PlanetData, PlanetMesher, Planet
src/actors/   GravityBody (walking on a sphere), Player
src/camera/   PlanetCamera (tangent-frame third-person camera, orbit view)
src/sky/      SkySystem (clock, sun, space sky), CloudLayer
src/render/   Palette (the shared palette texture), MeshData (mesh building)
src/ui/       DebugHud, TouchStick
shaders/      planet surface, water, atmosphere, space sky
tests/        headless checks
tools/        screenshot tour
```

Concept art lives in `images art direction/` and `images ui direction/`. Those folders contain a `.gdignore` file so Godot doesn't import them. New game assets (models, textures, audio) go under `assets/` and are stored with Git LFS.
