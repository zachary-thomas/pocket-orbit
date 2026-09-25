"""Builds Pocket Orbit's low-poly models in Blender and exports them as .glb.

Run from the repo root:

    blender -b -P tools/blender/build_assets.py -- [asset names...]

With no names, every asset is rebuilt. Each asset is written twice into
assets/models/: <name>.glb for close up and <name>_lod1.glb, a much simpler
version drawn when the camera is far away.

How the models follow the art rules in GAME_PLAN.md:
- Colour comes only from the shared palette. Every face's UVs point at the
  centre of one swatch; the swatch list is read from src/render/palette.gd.
- Flat shading with soft gradients: faces are flat-shaded, and ambient
  occlusion (how hidden each corner is from the sky) is baked into vertex
  colours, which the game multiplies into the palette colour. That gives the
  soft darkening in creases and at the ground seen in the concept art,
  without any lighting cost on the phone.
- Chunky, rounded shapes: geodesic spheres with a little noise, bevelled
  boxes, lathed (turned) walls and roofs.

Models are built Z-up in metres with the origin on the ground at the centre.
Fronts face -Y, which the glTF exporter turns into Godot's +Z.
"""

import math
import os
import re
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector, noise
from mathutils.bvhtree import BVHTree

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT_DIR = os.path.join(REPO, "assets", "models")
PALETTE_SOURCE = os.path.join(REPO, "src", "render", "palette.gd")
GRID = 16
GLOW_ROW = 15


# --- Palette -------------------------------------------------------------------

def load_palette():
    """Swatch name -> (u, v) in Blender UV space, mirroring palette.gd."""
    text = open(PALETTE_SOURCE, encoding="utf-8").read()
    regular, glow = text.split("const GLOW_COLORS", 1)
    pattern = re.compile(r'"(\w+)":\s*Color\("[0-9a-fA-F]{6}"\)')
    cells = {}
    for i, name in enumerate(pattern.findall(regular)):
        cells[name] = (i % GRID, i // GRID)
    for i, name in enumerate(pattern.findall(glow)):
        cells[name] = (i, GLOW_ROW)
    # Godot's v runs down from the top; Blender's runs up from the bottom and
    # the glTF exporter flips it back.
    return {name: ((x + 0.5) / GRID, 1.0 - (y + 0.5) / GRID) for name, (x, y) in cells.items()}


PALETTE = load_palette()
SWATCHES = list(PALETTE)


# --- Building ----------------------------------------------------------------------

def rot(x=0.0, y=0.0, z=0.0):
    """Rotation matrix from Euler angles in degrees."""
    return (Matrix.Rotation(math.radians(z), 4, "Z")
            @ Matrix.Rotation(math.radians(y), 4, "Y")
            @ Matrix.Rotation(math.radians(x), 4, "X"))


def scale(x, y, z):
    return Matrix.Diagonal((x, y, z, 1.0))


def at(x, y, z):
    return Matrix.Translation((x, y, z))


class Builder:
    """Collects parts into one bmesh, remembering each face's swatch."""

    def __init__(self):
        self.bm = bmesh.new()
        self.swatch = self.bm.faces.layers.int.new("swatch")

    def _tag(self, swatch):
        index = SWATCHES.index(swatch) + 1
        for face in self.bm.faces:
            if face[self.swatch] == 0:
                face[self.swatch] = index

    def _begin(self):
        """Index where the next part's vertices will start."""
        return len(self.bm.verts)

    def _end(self, before, swatch, jitter=0.0, seed=0.0, flatten_below=None, smooth=False):
        """Finish a part: roughen it with noise, flatten its base, tag its
        swatch. Parts are flat-shaded unless `smooth` is set."""
        self.bm.verts.ensure_lookup_table()
        new = self.bm.verts[before:]
        if smooth:
            for face in {f for v in new for f in v.link_faces}:
                face.smooth = True
        if jitter:
            offset = Vector((seed * 7.1, seed * 3.3, seed * 5.7))
            for v in new:
                v.co += noise.noise_vector(v.co * 1.8 + offset) * jitter
        if flatten_below is not None:
            for v in new:
                v.co.z = max(v.co.z, flatten_below)
        self._tag(swatch)

    def sphere(self, matrix, radius, swatch, subdivisions=2, jitter=0.0, seed=0.0, flatten_below=None):
        before = self._begin()
        bmesh.ops.create_icosphere(self.bm, subdivisions=subdivisions, radius=radius, matrix=matrix)
        self._end(before, swatch, jitter * radius, seed, flatten_below)

    def cone(self, matrix, r_bottom, r_top, height, segments, swatch, jitter=0.0, seed=0.0):
        """Cylinder or cone standing on the XY plane of `matrix`."""
        before = self._begin()
        bmesh.ops.create_cone(self.bm, cap_ends=True, cap_tris=False, segments=segments,
                              radius1=r_bottom, radius2=max(r_top, 0.0), depth=height,
                              matrix=matrix @ at(0, 0, height / 2))
        self._end(before, swatch, jitter, seed)

    def box(self, matrix, size, swatch, bevel=0.0):
        """Box centred on `matrix`'s origin; `bevel` rounds its edges."""
        before = self._begin()
        bmesh.ops.create_cube(self.bm, size=1.0, matrix=matrix @ scale(*size))
        if bevel:
            self.bm.verts.ensure_lookup_table()
            new_verts = self.bm.verts[before:]
            edges = list({e for v in new_verts for e in v.link_edges})
            bmesh.ops.bevel(self.bm, geom=new_verts[:] + edges, offset=bevel, offset_type="OFFSET",
                            segments=1, profile=0.5, affect="EDGES", clamp_overlap=True)
        self._end(before, swatch)

    def lathe(self, matrix, profile, segments, swatch, cap_bottom=True, cap_top=True, jitter=0.0, seed=0.0, smooth=False):
        """Surface of revolution around Z from a list of (radius, z) points,
        bottom to top. A radius of 0 at an end closes it to a point."""
        before = self._begin()
        rings = []
        for r, z in profile:
            if r <= 1e-4:
                rings.append([self.bm.verts.new(matrix @ Vector((0, 0, z)))])
                continue
            ring = []
            for i in range(segments):
                a = 2 * math.pi * i / segments
                ring.append(self.bm.verts.new(matrix @ Vector((r * math.cos(a), r * math.sin(a), z))))
            rings.append(ring)
        for lower, upper in zip(rings, rings[1:]):
            for i in range(segments):
                j = (i + 1) % segments
                if len(lower) == 1:
                    self.bm.faces.new((lower[0], upper[j], upper[i]))
                elif len(upper) == 1:
                    self.bm.faces.new((lower[i], lower[j], upper[0]))
                else:
                    self.bm.faces.new((lower[i], lower[j], upper[j], upper[i]))
        if cap_bottom and len(rings[0]) > 1:
            self.bm.faces.new(list(reversed(rings[0])))
        if cap_top and len(rings[-1]) > 1:
            self.bm.faces.new(rings[-1])
        self._end(before, swatch, jitter, seed, smooth=smooth)

    def half_disc(self, matrix, radius, thickness, segments, swatch):
        """Half a disc hanging below `matrix`'s origin in its XZ plane, with
        `thickness` along Y. Used for scalloped awning edges."""
        before = self._begin()
        front, back = [], []
        for i in range(segments + 1):
            a = math.pi * i / segments
            p = Vector((radius * math.cos(a), 0, -radius * math.sin(a)))
            front.append(self.bm.verts.new(matrix @ (p + Vector((0, -thickness / 2, 0)))))
            back.append(self.bm.verts.new(matrix @ (p + Vector((0, thickness / 2, 0)))))
        self.bm.faces.new(front)
        self.bm.faces.new(list(reversed(back)))
        for i in range(segments):
            self.bm.faces.new((front[i], back[i], back[i + 1], front[i + 1]))
        self.bm.faces.new((front[-1], back[-1], back[0], front[0]))
        self._end(before, swatch)

    def flower(self, matrix, size, petal="flower_white", centre="flower_yellow"):
        """A flat five-sided blossom with a raised centre, in the XY plane of
        `matrix`. Kept to about 20 triangles since there are many of them."""
        self.cone(matrix, size, size * 0.85, size * 0.14, 5, petal)
        self.cone(matrix @ at(0, 0, size * 0.1), size * 0.36, size * 0.2, size * 0.12, 5, centre)

    def leaf(self, matrix, size, swatch="leaf_light"):
        self.sphere(matrix @ scale(1.0, 0.55, 0.22), size, swatch, 0)


# --- Assets ----------------------------------------------------------------------
# Each takes lod (0 = close up, 1 = far away) and adds parts to a Builder.

def tree_round(b, lod):
    # Tapered trunk with a flared base, leaning very slightly.
    b.cone(at(0, 0, 0), 0.52, 0.3, 0.45, 7 if lod == 0 else 5, "trunk_dark")
    b.cone(at(0, 0, 0.3) @ rot(y=3), 0.34, 0.22, 2.0, 7 if lod == 0 else 5, "trunk")
    if lod == 0:
        b.cone(at(0.1, 0, 1.75) @ rot(y=48), 0.14, 0.08, 0.75, 5, "trunk")
        b.cone(at(-0.08, 0.05, 1.9) @ rot(y=-42, z=20), 0.12, 0.07, 0.6, 5, "trunk")
    # One big faceted canopy, as in the concept sheet.
    b.sphere(at(0.06, 0, 3.15) @ scale(1, 1, 0.92), 1.55, "leaf", 2 if lod == 0 else 1, jitter=0.07, seed=1)
    if lod == 0:
        for i, (az, el) in enumerate([(20, 10), (95, 35), (160, -5), (230, 25), (300, 0), (340, 45), (60, -20), (200, -25)]):
            d = Vector((math.cos(math.radians(az)) * math.cos(math.radians(el)),
                        math.sin(math.radians(az)) * math.cos(math.radians(el)),
                        math.sin(math.radians(el))))
            pos = Vector((0.06, 0, 3.15)) + Vector((d.x, d.y, d.z * 0.92)) * 1.5
            facing = d.to_track_quat("Z", "Y").to_matrix().to_4x4()
            b.leaf(Matrix.Translation(pos) @ facing @ rot(z=35 * i), 0.26)
        for az, el in [(-70, 15), (-120, 40), (-30, -10)]:
            d = Vector((math.cos(math.radians(az)) * math.cos(math.radians(el)),
                        math.sin(math.radians(az)) * math.cos(math.radians(el)),
                        math.sin(math.radians(el))))
            pos = Vector((0.06, 0, 3.15)) + Vector((d.x, d.y, d.z * 0.92)) * 1.52
            b.flower(Matrix.Translation(pos) @ d.to_track_quat("Z", "Y").to_matrix().to_4x4(), 0.2)


def tree_pine(b, lod):
    segments = 10 if lod == 0 else 6
    b.cone(at(0, 0, 0), 0.34, 0.22, 1.1, 6 if lod == 0 else 4, "trunk")
    tiers = [(0.8, 1.45, 1.45), (1.55, 1.12, 1.3), (2.25, 0.8, 1.2)]
    for i, (z, radius, height) in enumerate(tiers):
        swatch = "pine" if i < 2 else "pine_light"
        before = b._begin()
        b.cone(at(0, 0, z), radius, 0.0, height, segments, swatch)
        if lod == 0:
            # Droop every other rim point for the scalloped edge of the concept pine.
            b.bm.verts.ensure_lookup_table()
            rim = [v for v in b.bm.verts[before:] if abs(v.co.z - z) < 1e-4 and v.co.xy.length > radius * 0.5]
            for v in rim:
                angle = math.atan2(v.co.y, v.co.x)
                if round(angle / (2 * math.pi / segments)) % 2 == 0:
                    v.co.z -= 0.2
                    v.co.xy *= 1.04
    b.cone(at(0, 0, 3.2), 0.36, 0.0, 0.55, segments, "pine_light")


def rock(b, lod):
    b.sphere(at(0, 0, 0.42) @ scale(1.25, 1.0, 0.8), 0.72, "boulder", 2 if lod == 0 else 1, jitter=0.2, seed=3, flatten_below=0.0)
    if lod == 0:
        b.sphere(at(0.85, -0.35, 0.1), 0.3, "rock_dark", 1, jitter=0.25, seed=4, flatten_below=0.0)
        b.sphere(at(-0.7, -0.5, 0.08), 0.22, "boulder", 1, jitter=0.25, seed=5, flatten_below=0.0)
        b.leaf(at(0.6, 0.45, 0.2) @ rot(x=60, z=30), 0.22, "leaf")
        b.leaf(at(0.72, 0.3, 0.18) @ rot(x=70, z=-20), 0.18, "leaf_light")


def bush(b, lod):
    detail = 1
    b.sphere(at(0, 0, 0.45), 0.55, "leaf_dark", detail, jitter=0.12, seed=6, flatten_below=0.0)
    b.sphere(at(0.45, 0.15, 0.35), 0.42, "leaf", detail, jitter=0.12, seed=7, flatten_below=0.0)
    b.sphere(at(-0.4, -0.1, 0.32), 0.4, "leaf", detail, jitter=0.12, seed=8, flatten_below=0.0)
    if lod == 0:
        b.flower(at(0.1, -0.45, 0.72) @ rot(x=-50), 0.14)
        b.flower(at(-0.45, -0.3, 0.6) @ rot(x=-40, y=-30), 0.12, "flower")


def lamp_post(b, lod):
    b.cone(at(0, 0, 0), 0.2, 0.16, 0.18, 6, "lamp_post")
    b.cone(at(0, 0, 0.18), 0.07, 0.06, 2.0, 6 if lod == 0 else 4, "lamp_post")
    # Lantern: glowing glass under a little roof.
    b.box(at(0, 0, 2.3), (0.3, 0.3, 0.36), "lamp_glow", bevel=0.03 if lod == 0 else 0.0)
    b.cone(at(0, 0, 2.47) @ rot(z=45), 0.28, 0.04, 0.2, 4, "lamp_post")
    b.cone(at(0, 0, 2.08) @ rot(z=45), 0.2, 0.2, 0.05, 4, "lamp_post")
    if lod == 0:
        b.sphere(at(0, 0, 2.7), 0.06, "gold", 1)


def market_stall(b, lod):
    bevel = 0.03 if lod == 0 else 0.0
    # Counter
    b.box(at(0, 0, 0.5), (2.4, 0.95, 0.9), "wood", bevel)
    b.box(at(0, -0.02, 0.98), (2.6, 1.1, 0.1), "wood_light", bevel)
    if lod == 0:
        for z in (0.2, 0.5, 0.8):
            b.box(at(0, -0.49, z), (2.3, 0.06, 0.22), "wood_dark", 0.02)
        # Draped cloth over the front of the counter.
        b.box(at(0.35, -0.57, 0.82), (1.1, 0.04, 0.35), "cloth_pink", 0.015)
    # Posts: taller at the back so the awning slopes forward.
    for x in (-1.18, 1.18):
        b.box(at(x, 0.42, 1.35), (0.14, 0.14, 2.7), "wood_dark", bevel)
        b.box(at(x, -0.48, 1.2), (0.14, 0.14, 2.4), "wood_dark", bevel)
    # Striped awning sloping down to the front, with a scalloped edge.
    stripes = 6
    width = 2.7 / stripes
    depth = 1.5
    slope = math.atan2(0.45, 1.3)
    front_y = -0.15 - depth / 2 * math.cos(slope)
    front_z = 2.58 - depth / 2 * math.sin(slope)
    for i in range(stripes):
        x = -1.35 + width * (i + 0.5)
        swatch = "awning_red" if i % 2 == 0 else "awning_white"
        b.box(at(x, -0.15, 2.58) @ rot(x=math.degrees(slope)), (width + 0.005, depth, 0.07), swatch)
        if lod == 0:
            b.half_disc(at(x, front_y, front_z + 0.02), width / 2, 0.05, 6, swatch)
    if lod == 0:
        # Crates of fruit on the counter.
        for cx, fruit in ((-0.6, "apple"), (0.25, "orange")):
            b.box(at(cx, 0.05, 1.18), (0.62, 0.46, 0.3), "wood_light", 0.02)
            for j in range(6):
                fx = cx - 0.18 + (j % 3) * 0.18
                fy = -0.07 + (j // 3) * 0.2
                b.sphere(at(fx, fy, 1.36), 0.11, fruit, 1)
        # Flower pot.
        b.cone(at(0.9, 0.05, 1.03), 0.14, 0.18, 0.25, 8, "terracotta")
        b.sphere(at(0.9, 0.05, 1.33), 0.2, "leaf", 1, jitter=0.1, seed=9)
        b.flower(at(0.88, -0.05, 1.47), 0.09)
        b.flower(at(0.98, 0.1, 1.44) @ rot(y=25), 0.08, "flower")
        # Hanging star sign.
        b.cone(at(-0.9, -0.78, 1.95) @ rot(x=90), 0.14, 0.14, 0.04, 5, "gold")
    b.box(at(1.55, 0.2, 0.25), (0.55, 0.55, 0.5), "wood", bevel)


def cottage(b, lod):
    segments = 16 if lod == 0 else 8
    # Softly bulging walls.
    wall = [(1.72 + 0.14 * math.sin(math.pi * t), 2.3 * t) for t in [i / 5 for i in range(6)]]
    b.lathe(Matrix.Identity(4), wall, segments, "wall_cream", cap_bottom=False, cap_top=False, smooth=True)
    # Roof: overlapping rows of tiles, each ring a little inside the one below.
    # Each row's lower edge sits just proud of the row below, like tile courses.
    rows = [(2.35, 2.05), (1.85, 2.75), (1.25, 3.35), (0.6, 3.85)]
    if lod == 0:
        b.lathe(Matrix.Identity(4), [(1.7, 2.12), (2.35, 2.05)], segments, "roof_red_dark", cap_bottom=True, cap_top=False)
        for i, (r, z) in enumerate(rows):
            nxt = rows[i + 1] if i + 1 < len(rows) else (0.0, 4.1)
            profile = [(r, z), (r * 0.99, z + 0.1), (nxt[0] * 1.03, nxt[1] + 0.1)]
            b.lathe(Matrix.Identity(4), profile, segments, "roof_red",
                    cap_bottom=False, cap_top=False, smooth=True)
        b.sphere(at(0, 0, 4.15), 0.16, "roof_red_dark", 1)
    else:
        b.lathe(Matrix.Identity(4), [(2.3, 2.05), (0.0, 4.1)], segments, "roof_red")
    # Chimney.
    b.box(at(0.95, 0.55, 3.35), (0.5, 0.5, 1.3), "stone_light", 0.04 if lod == 0 else 0.0)
    b.box(at(0.95, 0.55, 4.05), (0.62, 0.62, 0.14), "stone", 0.03 if lod == 0 else 0.0)

    def on_wall(angle, z, out=0.0):
        """Matrix on the wall surface at `angle` degrees around from the
        front (-Y), with local -Y pointing out of the wall."""
        r = 1.72 + 0.14 * math.sin(math.pi * z / 2.3) + out
        return rot(z=angle) @ at(0, -r, z)

    # Door: arched, recessed into a wooden frame, with a stone step.
    b.box(on_wall(0, 0.72, 0.02), (1.02, 0.14, 1.44), "wood_dark", 0.03 if lod == 0 else 0.0)
    b.cone(on_wall(0, 1.44, -0.05) @ rot(x=90), 0.51, 0.51, 0.14, 12 if lod == 0 else 6, "wood_dark")
    b.box(on_wall(0, 0.7, 0.07), (0.8, 0.1, 1.36), "wood", 0.02 if lod == 0 else 0.0)
    b.cone(on_wall(0, 1.38, 0.02) @ rot(x=90), 0.4, 0.4, 0.1, 12 if lod == 0 else 6, "wood")
    b.box(at(0, -2.05, 0.08), (1.3, 0.55, 0.16), "stone_light", 0.04 if lod == 0 else 0.0)
    if lod == 0:
        b.sphere(on_wall(0, 0.8, 0.12) @ at(0.25, 0, 0), 0.06, "gold", 1)
        b.cone(on_wall(0, 1.25, 0.1) @ rot(x=90), 0.14, 0.14, 0.04, 10, "window_glow")
        b.box(on_wall(0, 1.25, 0.13), (0.3, 0.04, 0.04), "wood_dark")
        b.box(on_wall(0, 1.25, 0.13), (0.04, 0.04, 0.3), "wood_dark")
    # Round glowing windows with frames and flower boxes.
    for angle in (-58, 58, 180):
        b.cone(on_wall(angle, 1.35, -0.02) @ rot(x=90), 0.42, 0.42, 0.12, 12 if lod == 0 else 6, "wood")
        b.cone(on_wall(angle, 1.35, 0.03) @ rot(x=90), 0.32, 0.32, 0.1, 12 if lod == 0 else 6, "window_glow")
        if lod == 0:
            b.box(on_wall(angle, 1.35, 0.1), (0.62, 0.05, 0.05), "wood")
            b.box(on_wall(angle, 1.35, 0.1), (0.05, 0.05, 0.62), "wood")
            b.box(on_wall(angle, 0.86, 0.14), (0.8, 0.22, 0.2), "wood_dark", 0.02)
            for k in range(3):
                b.sphere(on_wall(angle, 1.0, 0.16) @ at(-0.25 + k * 0.25, 0, 0), 0.13, "leaf", 1, jitter=0.1, seed=20 + k)
            for k in range(2):
                b.flower(on_wall(angle, 1.08, 0.3) @ at(-0.13 + k * 0.26, 0, 0) @ rot(x=-70), 0.08,
                         "flower" if k == 1 else "flower_white")
    # Wall lantern beside the door.
    b.box(on_wall(-28, 1.75, 0.2), (0.2, 0.2, 0.26), "lamp_glow", 0.02 if lod == 0 else 0.0)
    b.cone(on_wall(-28, 1.88, 0.2) @ rot(z=45), 0.18, 0.03, 0.14, 4, "lamp_post")
    if lod == 0:
        # A ring of foundation stones.
        for i in range(14):
            angle = 360 * i / 14 + 8
            if abs(((angle + 180) % 360) - 180) < 22:
                continue  # leave the doorway clear
            b.sphere(rot(z=angle) @ at(0, -1.8, 0.12) @ scale(1.3, 0.8, 0.7), 0.24, "stone" if i % 3 else "stone_light",
                     0, jitter=0.15, seed=30 + i, flatten_below=0.0)


def cargo_pod(b, lod):
    """The player's first home: a cargo pod from the smuggling run, lying on
    its side on stubby legs, with a door cut in the front, portholes, patched
    panels and a little antenna."""
    segments = 14 if lod == 0 else 8
    length = 4.2
    radius = 1.35
    # Body: a capsule along X (lathed around Z, then turned on its side).
    # Profile: a quarter circle up from one end, straight along, a quarter
    # circle back down to the other end.
    profile = [(0.0, -length / 2)]
    for i in range(1, 5):
        a = math.pi / 2 * i / 4
        profile.append((radius * math.sin(a), -length / 2 + radius * (1 - math.cos(a))))
    for i in range(3, -1, -1):
        a = math.pi / 2 * i / 4
        profile.append((radius * math.sin(a), length / 2 - radius * (1 - math.cos(a))))
    lying = at(0, 0, radius + 0.35) @ rot(y=90)
    b.lathe(lying, profile, segments, "wall_cream", cap_bottom=False, cap_top=False, smooth=True)
    # Coloured bands around the hull.
    for x in (-1.2, 1.2):
        b.cone(at(x, 0, radius + 0.35) @ rot(y=90) @ at(0, 0, -0.14), radius + 0.04, radius + 0.04, 0.28, segments, "roof_blue")
    # Legs.
    for x in (-1.3, 1.3):
        for y in (-0.7, 0.7):
            b.cone(at(x, y, 0), 0.22, 0.14, 0.55, 6, "lamp_post")
    # Door on the front (-Y) with a frame, step and lamp.
    b.box(at(0, -radius + 0.02, 1.2), (1.0, 0.2, 1.55), "roof_blue", 0.05 if lod == 0 else 0.0)
    b.box(at(0, -radius - 0.06, 1.18), (0.78, 0.12, 1.35), "wood", 0.03 if lod == 0 else 0.0)
    b.box(at(0, -radius - 0.45, 0.12), (1.1, 0.6, 0.24), "stone_light", 0.04 if lod == 0 else 0.0)
    b.box(at(0.7, -radius - 0.02, 1.95), (0.2, 0.2, 0.24), "lamp_glow", 0.02 if lod == 0 else 0.0)
    # Portholes either side of the door.
    for x in (-1.45, 1.45):
        b.cone(at(x, -radius * 0.93, 1.55) @ rot(x=90), 0.36, 0.36, 0.12, 12 if lod == 0 else 6, "lamp_post")
        b.cone(at(x, -radius * 0.93 - 0.05, 1.55) @ rot(x=90), 0.26, 0.26, 0.1, 12 if lod == 0 else 6, "window_glow")
    # Antenna with a blinking tip.
    b.cone(at(-1.0, 0.2, radius * 2 + 0.3), 0.05, 0.03, 0.9, 5, "lamp_post")
    b.sphere(at(-1.0, 0.2, radius * 2 + 1.25), 0.1, "awning_red", 1)
    if lod == 0:
        # Patches and rivets.
        b.box(at(1.0, -0.4, radius * 2 + 0.28) @ rot(x=-18), (0.6, 0.45, 0.06), "stone_light", 0.02)
        b.box(at(-0.3, 0.9, radius * 1.6 + 0.35) @ rot(x=40), (0.5, 0.4, 0.06), "roof_blue", 0.02)
        for i in range(8):
            ang = 2 * math.pi * i / 8
            for x in (-1.2, 1.2):
                p = Vector((x, math.cos(ang) * (radius + 0.06), radius + 0.35 + math.sin(ang) * (radius + 0.06)))
                b.sphere(Matrix.Translation(p), 0.05, "gold", 0)
        # A flower pot by the door.
        b.cone(at(-0.85, -radius - 0.35, 0), 0.16, 0.2, 0.3, 8, "terracotta")
        b.sphere(at(-0.85, -radius - 0.35, 0.42), 0.22, "leaf", 1, jitter=0.1, seed=40)
        b.flower(at(-0.85, -radius - 0.45, 0.58) @ rot(x=-40), 0.1, "flower")


def cactus(b, lod):
    """Saguaro: a ribbed column with two raised arms and a pink flower on top."""
    if lod == 1:
        b.cone(at(0, 0, 0), 0.34, 0.24, 2.1, 5, "cactus")
        b.cone(at(0.1, 0, 0.8) @ rot(y=90), 0.16, 0.14, 0.55, 4, "cactus")
        b.cone(at(0.65, 0, 0.68), 0.15, 0.1, 0.85, 4, "cactus")
        b.cone(at(-0.1, 0, 1.15) @ rot(y=-90), 0.15, 0.13, 0.45, 4, "cactus")
        b.cone(at(-0.55, 0, 1.03), 0.14, 0.1, 0.7, 4, "cactus")
        return
    seg = 8 if lod == 0 else 5
    prof = [(0.34, 0.0), (0.33, 1.2), (0.3, 1.85), (0.2, 2.05), (0.0, 2.12)]
    b.lathe(at(0, 0, 0), prof, seg, "cactus", cap_top=False)
    for side, h, reach, up in [(1, 0.8, 0.55, 0.7), (-1, 1.15, 0.45, 0.55)]:
        # Elbow out sideways, then up.
        b.cone(at(0.1 * side, 0, h) @ rot(y=90 * side), 0.17, 0.15, reach, seg if lod == 0 else 4, "cactus")
        arm = [(0.16, 0.0), (0.15, up), (0.1, up + 0.13), (0.0, up + 0.17)]
        b.lathe(at((0.1 + reach) * side, 0, h - 0.12), arm, seg if lod == 0 else 4, "cactus", cap_top=False)
    if lod == 0:
        # Pale ribs down the main column.
        for i in range(4):
            a = math.radians(45 + 90 * i)
            b.box(at(math.cos(a) * 0.32, math.sin(a) * 0.32, 1.0) @ rot(z=45 + 90 * i), (0.05, 0.05, 1.7), "leaf_light")
        b.flower(at(0, 0, 2.08), 0.2, "flower", "flower_yellow")
        b.sphere(at(0.55, -0.05, 1.5), 0.08, "flower", 0)


def jungle_tree(b, lod):
    """Palm: a curved ringed trunk, big drooping fronds and coconuts."""
    seg = 6 if lod == 0 else 4
    pieces = 6 if lod == 0 else 3
    top = Vector((0, 0, 0))
    lean = 0.0
    for i in range(pieces):
        length = 3.4 / pieces
        r = 0.26 - 0.1 * i / pieces
        b.cone(Matrix.Translation(top) @ rot(y=lean), r, r * 0.86, length, seg, "trunk" if i % 2 == 0 else "trunk_dark")
        top = top + Vector((math.sin(math.radians(lean)), 0, math.cos(math.radians(lean)))) * length
        lean += 4.0
    crown = top
    fronds = 7 if lod == 0 else 5
    for i in range(fronds):
        az = 360 * i / fronds + 15
        swatch = "palm" if i % 2 == 0 else "leaf_dark"
        # Each frond: two leaf blobs, the outer one drooping lower.
        d = Vector((math.cos(math.radians(az)), math.sin(math.radians(az)), 0))
        inner = crown + d * 0.7 + Vector((0, 0, 0.12))
        outer = crown + d * 1.55 + Vector((0, 0, -0.35))
        if lod == 1:
            # A flat three-sided wedge per frond is enough from afar.
            b.cone(Matrix.Translation(crown) @ rot(z=az) @ rot(y=100) @ scale(0.15, 0.6, 1.0), 1.0, 0.0, 1.9, 3, swatch)
            continue
        b.sphere(Matrix.Translation(inner) @ rot(z=az) @ rot(y=12) @ scale(1.0, 0.42, 0.14), 0.85, swatch, 1)
        b.sphere(Matrix.Translation(outer) @ rot(z=az) @ rot(y=38) @ scale(1.0, 0.36, 0.12), 0.7, swatch, 1)
    if lod == 0:
        for i in range(3):
            a = math.radians(120 * i + 40)
            b.sphere(Matrix.Translation(crown + Vector((math.cos(a) * 0.22, math.sin(a) * 0.22, -0.2))), 0.15, "trunk_dark", 1)
        b.sphere(Matrix.Translation(crown + Vector((0, 0, 0.05))), 0.28, "palm", 1)


def ice_spire(b, lod):
    """A cluster of faceted blue crystals with snow on their shoulders."""
    crystals = [(0, 0, 0.55, 2.7, 0, 0), (0.55, 0.2, 0.34, 1.6, 18, 40), (-0.45, 0.3, 0.3, 1.3, -20, 150),
                (0.1, -0.5, 0.26, 1.0, 22, -80)]
    if lod == 1:
        crystals = crystals[:2]
    for i, (x, y, r, h, tilt, az) in enumerate(crystals):
        m = at(x, y, -0.05) @ rot(z=az) @ rot(y=tilt)
        body = [(r, 0.0), (r * 1.05, h * 0.62), (0.0, h)]
        b.lathe(m, body, 5 if lod == 0 else 4, "ice" if i % 2 == 0 else "ice_cliff", cap_bottom=True)
        if lod == 0:
            # Snow cap on the shoulder of each crystal.
            b.lathe(m @ at(0, 0, h * 0.58), [(r * 1.12, 0.0), (r * 0.8, h * 0.12), (0.0, h * 0.18)], 5, "snow")
    b.sphere(at(0, 0, 0.0) @ scale(1.4, 1.2, 0.35), 0.75, "snow", 1, jitter=0.1, seed=12, flatten_below=0.0)


def shrine(b, lod):
    """Ancient stone shrine on a pentagon: stepped base, pillar, floating crystal."""
    b.cone(at(0, 0, 0), 1.4, 1.25, 0.3, 5, "shrine_stone")
    b.cone(at(0, 0, 0.3), 1.0, 0.9, 0.25, 5, "stone_light")
    b.cone(at(0, 0, 0.55), 0.42, 0.32, 1.9, 5, "shrine_stone")
    b.cone(at(0, 0, 2.45), 0.5, 0.42, 0.15, 5, "stone_light")
    # The glowing crystal floats above the pillar.
    b.lathe(at(0, 0, 2.75), [(0.0, 0.0), (0.32, 0.4), (0.0, 1.05)], 5, "shrine_glow")
    if lod == 0:
        for i in range(5):
            a = math.radians(72 * i + 36)
            p = Vector((math.cos(a) * 1.05, math.sin(a) * 1.05, 0.3))
            b.cone(Matrix.Translation(p), 0.12, 0.1, 0.55, 5, "shrine_stone")
            b.sphere(Matrix.Translation(p + Vector((0, 0, 0.62))), 0.09, "shrine_glow", 0)
            b.leaf(Matrix.Translation(p * 1.15 + Vector((0, 0, -0.2))) @ rot(x=60, z=72 * i), 0.2, "leaf")


def general_shop(b, lod):
    """The general shop that replaces the stall: a timber-framed shop with a
    wide serving window under a striped awning, a sign board on the roof, and
    crates and a barrel out front. About 4.6 m wide."""
    bevel = 0.04 if lod == 0 else 0.0
    segs = 12 if lod == 0 else 6
    # Stone footing and walls.
    b.box(at(0, 0.3, 0.15), (4.6, 3.4, 0.3), "stone_light", bevel)
    b.box(at(0, 0.3, 1.55), (4.3, 3.1, 2.5), "wall_cream", bevel)
    # Timber frame: corner posts and a beam along the front.
    for x in (-2.12, 2.12):
        for y in (-1.22, 1.82):
            b.box(at(x, y, 1.55), (0.2, 0.2, 2.5), "wood_dark", bevel)
    b.box(at(0, -1.22, 2.75), (4.44, 0.22, 0.2), "wood_dark", bevel)
    # Gabled roof, ridge along X, with overhangs.
    for side in (-1, 1):
        b.box(at(0, 0.3 + side * 1.05, 3.5) @ rot(x=-side * 34), (4.9, 2.6, 0.16), "roof_teal", bevel)
    b.box(at(0, 0.3, 4.22), (4.95, 0.3, 0.2), "wood_dark", bevel)
    # Gable ends: triangles filling the space under the roof.
    for x in (-2.12, 2.12):
        b.box(at(x, 0.3, 2.8) @ scale(1, 1, 0.9) @ rot(x=45), (0.2, 2.19, 2.19), "wall_cream")
    # Serving window with a counter.
    b.box(at(0, -1.26, 1.6), (2.8, 0.1, 1.1), "window_glow")
    b.box(at(0, -1.5, 0.98), (3.1, 0.55, 0.12), "wood_light", bevel)
    b.box(at(0, -1.38, 0.55), (3.0, 0.32, 0.8), "wood", bevel)
    if lod == 0:
        for x in (-0.7, 0.7):
            b.box(at(x, -1.3, 1.6), (0.08, 0.08, 1.1), "wood_dark")
        b.box(at(0, -1.3, 1.6), (2.8, 0.08, 0.08), "wood_dark")
    # Striped awning over the window.
    stripes = 7
    width = 3.4 / stripes
    for i in range(stripes):
        x = -1.7 + width * (i + 0.5)
        sw = "awning_red" if i % 2 == 0 else "awning_white"
        b.box(at(x, -1.75, 2.45) @ rot(x=22), (width + 0.005, 1.1, 0.06), sw)
        if lod == 0:
            b.half_disc(at(x, -2.26, 2.26), width / 2, 0.05, 6, sw)
    # Door on the right side, with a lamp.
    b.box(at(2.18, 0.9, 1.05), (0.12, 1.0, 1.8), "wood", bevel)
    b.box(at(2.3, 0.2, 2.2), (0.2, 0.2, 0.26), "lamp_glow", 0.02 if lod == 0 else 0.0)
    # Sign board on the front of the roof, with a gold star.
    b.box(at(0, -0.6, 4.05) @ rot(x=-20), (2.2, 0.12, 0.7), "wood", bevel)
    b.cone(at(0, -0.69, 4.05) @ rot(x=70), 0.24, 0.24, 0.06, 5, "gold")
    # Chimney.
    b.box(at(-1.4, 1.3, 4.0), (0.5, 0.5, 1.2), "stone", bevel)
    if lod == 0:
        # A display shelf across the window (the counter and this shelf hold
        # the shop's 12 shelves of goods), with brackets.
        b.box(at(0, -1.4, 1.5), (2.8, 0.22, 0.06), "wood_light", 0.01)
        for x in (-1.2, 0.0, 1.2):
            b.box(at(x, -1.33, 1.42), (0.06, 0.08, 0.14), "wood_dark")
        # Crates and a barrel out front.
        for k, (cx, cy) in enumerate(((-2.1, -1.9), (-1.6, -2.3))):
            b.box(at(cx, cy, 0.28) @ rot(z=12 * k), (0.56, 0.56, 0.56), "wood_light", 0.03)
        b.cone(at(2.0, -1.9, 0), 0.32, 0.34, 0.8, segs, "wood")
        for z in (0.2, 0.55):
            b.cone(at(2.0, -1.9, z), 0.35, 0.35, 0.06, segs, "wood_dark")
        b.cone(at(-2.4, 1.7, 0), 0.2, 0.24, 0.35, 8, "terracotta")
        b.sphere(at(-2.4, 1.7, 0.5), 0.3, "leaf", 1, jitter=0.1, seed=50)
        b.flower(at(-2.4, 1.55, 0.72) @ rot(x=-40), 0.1, "flower")


def landing_pad(b, lod):
    """A round drone landing pad: a metal disc on a stone rim with a yellow
    H, a ring of chevrons, corner lights and a beacon mast at the back."""
    segs = 20 if lod == 0 else 10
    b.cone(at(0, 0, 0), 2.1, 2.0, 0.14, segs, "stone_light")
    b.cone(at(0, 0, 0.14), 1.75, 1.72, 0.06, segs, "pad_metal")
    b.box(at(-0.45, 0, 0.21), (0.16, 1.1, 0.02), "pad_stripe")
    b.box(at(0.45, 0, 0.21), (0.16, 1.1, 0.02), "pad_stripe")
    b.box(at(0, 0, 0.21), (0.9, 0.16, 0.02), "pad_stripe")
    if lod == 0:
        for i in range(12):
            b.box(rot(z=360 * i / 12) @ at(0, 1.45, 0.205), (0.35, 0.12, 0.02), "pad_stripe" if i % 2 == 0 else "lamp_post")
        for i in range(4):
            a = math.radians(45 + 90 * i)
            b.sphere(Matrix.Translation(Vector((math.cos(a) * 1.9, math.sin(a) * 1.9, 0.2))), 0.09, "lamp_glow", 1)
    b.cone(at(0, 2.35, 0), 0.12, 0.08, 1.8, 6, "lamp_post")
    b.sphere(at(0, 2.35, 1.9), 0.14, "awning_red", 1)
    b.box(at(0, 2.35, 1.2), (0.5, 0.06, 0.35), "pad_stripe")


def archive(b, lod):
    """The Archive: a little domed museum with columns, steps and a
    telescope on the roof, where donated finds are kept."""
    segs = 16 if lod == 0 else 8
    b.cone(at(0, 0, 0), 2.3, 2.2, 0.25, segs, "stone")
    b.cone(at(0, 0, 0.25), 2.05, 2.0, 0.2, segs, "stone_light")
    b.cone(at(0, 0, 0.45), 1.7, 1.7, 2.1, segs, "wall_cream")
    b.cone(at(0, 0, 2.55), 1.95, 1.9, 0.22, segs, "stone_light")
    b.lathe(at(0, 0, 2.77), [(1.7, 0.0), (1.55, 0.6), (1.15, 1.15), (0.6, 1.5), (0.0, 1.62)], segs, "roof_teal",
            cap_bottom=True, cap_top=False, smooth=True)
    # Columns round the front.
    n = 7 if lod == 0 else 4
    for i in range(n):
        a = math.radians(-160 + i * 140 / (n - 1))
        b.cone(Matrix.Translation(Vector((math.cos(a) * 1.88, math.sin(a) * 1.88, 0.45))), 0.14, 0.12, 2.1, 6, "stone_light")
    # Door and steps at the front (-Y).
    b.box(at(0, -1.7, 1.0), (0.9, 0.14, 1.3), "wood_dark", 0.03 if lod == 0 else 0.0)
    b.cone(at(0, -1.7, 1.65) @ rot(x=90), 0.45, 0.45, 0.14, 10 if lod == 0 else 5, "wood_dark")
    b.box(at(0, -2.35, 0.1), (1.4, 0.5, 0.2), "stone_light")
    for x in (-1.1, 1.1):
        b.cone(at(x, -1.3, 1.5) @ rot(x=90), 0.3, 0.3, 0.1, 10 if lod == 0 else 5, "window_glow")
    # Telescope on top.
    b.cone(at(0, 0, 4.35), 0.2, 0.16, 0.25, 8, "lamp_post")
    b.cone(at(0, 0, 4.55) @ rot(x=-50), 0.14, 0.2, 1.1, 8, "gold")
    if lod == 0:
        b.cone(at(-1.9, -1.9, 0), 0.2, 0.24, 0.35, 8, "terracotta")
        b.sphere(at(-1.9, -1.9, 0.5), 0.3, "leaf", 1, jitter=0.1, seed=60)


def burrow_house(b, lod):
    """A burrow house: a grassy mound with a round door, round windows, a
    chimney pipe and flowers on top."""
    segs = 16 if lod == 0 else 8
    b.lathe(Matrix.Identity(4), [(2.1, 0.0), (2.05, 0.6), (1.8, 1.4), (1.2, 2.1), (0.0, 2.45)], segs, "moss",
            cap_bottom=False, cap_top=False, smooth=True)
    # Round door with a stone surround at the front (-Y).
    b.cone(at(0, -1.85, 0.9) @ rot(x=90), 0.78, 0.78, 0.3, 12 if lod == 0 else 6, "stone_light")
    b.cone(at(0, -2.12, 0.9) @ rot(x=90), 0.6, 0.6, 0.12, 12 if lod == 0 else 6, "roof_green")
    b.sphere(at(0.3, -2.26, 0.85), 0.06, "gold", 1)
    b.box(at(0, -2.3, 0.08), (1.2, 0.5, 0.16), "stone_light")
    for angle in (-55, 55):
        m = rot(z=angle) @ at(0, -1.9, 1.05) @ rot(x=65)
        b.cone(m, 0.34, 0.34, 0.16, 10 if lod == 0 else 5, "wood")
        b.cone(m @ at(0, 0, 0.1), 0.25, 0.25, 0.08, 10 if lod == 0 else 5, "window_glow")
    b.cone(at(0.8, 0.6, 1.7), 0.14, 0.14, 1.0, 6, "lamp_post")
    b.cone(at(0.8, 0.6, 2.7), 0.2, 0.2, 0.1, 6, "lamp_post")
    if lod == 0:
        for i in range(6):
            a = math.radians(60 * i + 20)
            b.flower(Matrix.Translation(Vector((math.cos(a), math.sin(a), 2.1))) @ rot(x=-15), 0.12,
                     "flower" if i % 2 else "flower_yellow")
        for i in range(9):
            a = 360 * i / 9 + 30
            if abs(((a + 180) % 360) - 180) < 30:
                continue
            b.sphere(rot(z=a) @ at(0, -2.1, 0.1) @ scale(1.3, 0.8, 0.7), 0.22, "stone", 0, jitter=0.15, seed=70 + i,
                     flatten_below=0.0)


def tide_pool(b, lod):
    """A rock pool: a ring of wet rocks round a little basin of clear water,
    with a starfish and a shell."""
    b.cone(at(0, 0, -0.05), 1.0, 0.95, 0.1, 10 if lod == 0 else 6, "pool_water")
    count = 9 if lod == 0 else 5
    for i in range(count):
        s = 0.28 + 0.1 * math.sin(i * 2.3)
        b.sphere(rot(z=360 * i / count + 13) @ at(0, 1.0, 0.0) @ scale(1.3, 0.9, 0.6), s,
                 "rock_dark" if i % 2 else "boulder", 1 if lod == 0 else 0, jitter=0.2, seed=80 + i, flatten_below=-0.05)
    if lod == 0:
        for k in range(5):
            b.box(at(0.25, -0.15, 0.06) @ rot(z=72 * k) @ at(0, 0.1, 0), (0.07, 0.2, 0.04), "awning_red")
        b.sphere(at(-0.3, 0.25, 0.06) @ scale(1, 0.8, 0.4), 0.12, "shell", 1)
        b.leaf(at(0.35, 0.45, 0.05) @ rot(z=40), 0.18, "leaf_dark")


def plot_marker(b, lod):
    """An empty building plot: corner stakes with rope and a little sign."""
    half = 2.0
    for x in (-half, half):
        for y in (-half, half):
            b.box(at(x, y, 0.3), (0.12, 0.12, 0.6), "wood", 0.02 if lod == 0 else 0.0)
    for (x0, y0, x1, y1) in ((-half, -half, half, -half), (-half, half, half, half),
                             (-half, -half, -half, half), (half, -half, half, half)):
        length = math.hypot(x1 - x0, y1 - y0)
        angle = math.degrees(math.atan2(y1 - y0, x1 - x0))
        b.box(at((x0 + x1) / 2, (y0 + y1) / 2, 0.45) @ rot(z=angle), (length, 0.03, 0.03), "canvas")
    b.box(at(0.6, -half - 0.05, 0.45), (0.08, 0.08, 0.9), "wood_dark")
    b.box(at(0.6, -half - 0.1, 0.85) @ rot(z=-6), (0.8, 0.06, 0.45), "wood_light", 0.02 if lod == 0 else 0.0)


def fence(b, lod):
    """One 2 m length of low picket fence, along X."""
    for x in (-1.0, 1.0):
        b.box(at(x, 0, 0.4), (0.12, 0.12, 0.8), "wood_dark", 0.02 if lod == 0 else 0.0)
    for z in (0.3, 0.6):
        b.box(at(0, 0, z), (2.0, 0.05, 0.08), "wood")
    if lod == 0:
        for i in range(6):
            x = -0.75 + i * 0.3
            b.box(at(x, -0.05, 0.36), (0.1, 0.04, 0.72), "wood_light")

ASSETS = {
    "tree_round": tree_round,
    "tree_pine": tree_pine,
    "rock": rock,
    "bush": bush,
    "lamp_post": lamp_post,
    "market_stall": market_stall,
    "cottage": cottage,
    "cargo_pod": cargo_pod,
    "cactus": cactus,
    "jungle_tree": jungle_tree,
    "ice_spire": ice_spire,
    "shrine": shrine,
    "general_shop": general_shop,
    "landing_pad": landing_pad,
    "archive": archive,
    "burrow_house": burrow_house,
    "tide_pool": tide_pool,
    "plot_marker": plot_marker,
    "fence": fence,
}

# How far (metres) ambient occlusion rays look for blockers, per asset.
AO_REACH = {"cottage": 0.7, "market_stall": 0.9, "cargo_pod": 0.8, "general_shop": 0.9, "archive": 0.8, "burrow_house": 0.7}


# --- Baking and export ----------------------------------------------------------

def hemisphere_directions(count):
    """Evenly spread directions over the +Z hemisphere (Fibonacci spiral)."""
    dirs = []
    golden = math.pi * (3 - math.sqrt(5))
    for i in range(count):
        z = 1 - (i + 0.5) / count
        r = math.sqrt(1 - z * z)
        a = golden * i
        dirs.append(Vector((r * math.cos(a), r * math.sin(a), z)))
    return dirs


AO_DIRECTIONS = hemisphere_directions(32)


def bake_ambient_occlusion(bm, reach):
    """Per face corner: share of directions above the surface that aren't
    blocked by the model itself or the ground (z = 0) within `reach` metres."""
    tree = BVHTree.FromBMesh(bm)
    values = []
    for face in bm.faces:
        n = face.normal
        basis = n.to_track_quat("Z", "Y").to_matrix()
        for loop in face.loops:
            origin = loop.vert.co.lerp(face.calc_center_median(), 0.08) + n * 0.01
            open_sky = 0.0
            for local in AO_DIRECTIONS:
                d = basis @ local
                if d.z < 0 and origin.z + d.z * reach < 0:
                    continue  # hits the ground
                hit = tree.ray_cast(origin, d, reach)
                if hit[0] is None:
                    open_sky += 1.0
            ao = open_sky / len(AO_DIRECTIONS)
            values.append(0.5 + 0.5 * min(1.0, ao * 1.15))
    return values


def build(name, lod):
    b = Builder()
    ASSETS[name](b, lod)
    bm = b.bm
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    ao = bake_ambient_occlusion(bm, AO_REACH.get(name, 0.9))
    swatch_of_face = [SWATCHES[f[b.swatch] - 1] for f in bm.faces]

    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    uv = mesh.uv_layers.new(name="UVMap")
    color = mesh.color_attributes.new("Col", "FLOAT_COLOR", "CORNER")
    for poly in mesh.polygons:
        u, v = PALETTE[swatch_of_face[poly.index]]
        for li in poly.loop_indices:
            uv.data[li].uv = (u, v)
            shade = ao[li]
            color.data[li].color = (shade, shade, shade, 1.0)
    mesh.color_attributes.active_color = color
    if "swatch" in mesh.attributes:
        mesh.attributes.remove(mesh.attributes["swatch"])

    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def export(obj, path):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_normals=True,
        export_texcoords=True,
        export_vertex_color="ACTIVE",
        export_materials="NONE",
        export_animations=False,
    )


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    names = args or list(ASSETS)
    os.makedirs(OUT_DIR, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for name in names:
        for lod in (0, 1):
            obj = build(name, lod)
            path = os.path.join(OUT_DIR, name + ("" if lod == 0 else "_lod1") + ".glb")
            export(obj, path)
            print("%-14s lod%d  %5d triangles  -> %s" % (
                name, lod, sum(len(p.vertices) - 2 for p in obj.data.polygons), os.path.relpath(path, REPO)))
            bpy.data.objects.remove(obj)


main()
