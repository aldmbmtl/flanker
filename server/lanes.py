"""
lanes.py — Deterministic lane generation (Phase 5).

Python port of LaneData.gd's cubic Bézier lane generator.

Python is the canonical source of lane geometry.  Each game start triggers
generate_lanes(map_seed), which produces 3 × 41 XZ points.  Those points are
broadcast to all Godot clients inside the game_started payload so that every
peer (host and remote) uses identical lane data.

The random offsets use Python's standard ``random`` module seeded the same
way as GDScript: ``seed(map_seed + 100*(lane_index + 1))``.  Because Python
now *owns* the randomness we no longer need to replicate Godot's PCG64; the
authority is Python's output, and Godot reads it from the wire.

Constants mirror LaneData.gd exactly:
  SAMPLE_COUNT = 40  → 41 points (indices 0..40)
  LANE_FLATTEN = 50  → max perturbation per control point component
  LANE_SETBACK = 8   → minimum clearance from a lane polyline for placement

Public API
----------
generate_lanes(map_seed: int) -> list[list[tuple[float, float]]]
    Returns 3 lanes; each lane is a list of 41 (x, z) tuples.

dist_to_polyline(px: float, pz: float, lane: list[tuple[float, float]]) -> float
    Minimum distance from point (px, pz) to the given lane polyline.

point_too_close_to_any_lane(
    px: float, pz: float,
    lanes: list[list[tuple[float, float]]],
    setback: float = LANE_SETBACK,
) -> bool
    Returns True if (px, pz) is within *setback* units of any lane.
"""

from __future__ import annotations

import math
import random

# ---------------------------------------------------------------------------
# Constants (mirror LaneData.gd)
# ---------------------------------------------------------------------------

SAMPLE_COUNT: int = 40  # segments → 41 sample points
LANE_FLATTEN: float = 50.0  # max ± perturbation per XZ component
LANE_SETBACK: float = 8.0  # min clearance from lane centre-line

# Fixed Bézier control points [P0, P1, P2, P3] as (x, z) tuples.
# These mirror LANE_CONTROLS in LaneData.gd.
_LANE_CONTROLS: list[list[tuple[float, float]]] = [
    # Lane 0 — Left
    [(0.0, 82.0), (-85.0, 82.0), (-85.0, -82.0), (0.0, -82.0)],
    # Lane 1 — Mid (effectively linear)
    [(0.0, 82.0), (0.0, 27.0), (0.0, -27.0), (0.0, -82.0)],
    # Lane 2 — Right
    [(0.0, 82.0), (85.0, 82.0), (85.0, -82.0), (0.0, -82.0)],
]


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------


def _bezier_point(
    p0: tuple[float, float],
    p1: tuple[float, float],
    p2: tuple[float, float],
    p3: tuple[float, float],
    t: float,
) -> tuple[float, float]:
    """Evaluate a cubic Bézier at parameter *t* ∈ [0, 1]."""
    mt = 1.0 - t
    x = mt**3 * p0[0] + 3 * mt**2 * t * p1[0] + 3 * mt * t**2 * p2[0] + t**3 * p3[0]
    z = mt**3 * p0[1] + 3 * mt**2 * t * p1[1] + 3 * mt * t**2 * p2[1] + t**3 * p3[1]
    return (x, z)


def _sample_bezier(
    p0: tuple[float, float],
    p1: tuple[float, float],
    p2: tuple[float, float],
    p3: tuple[float, float],
    n: int,
) -> list[tuple[float, float]]:
    """Sample a cubic Bézier into n+1 evenly-spaced points."""
    return [_bezier_point(p0, p1, p2, p3, i / n) for i in range(n + 1)]


def _dist_point_segment(
    px: float,
    pz: float,
    ax: float,
    az: float,
    bx: float,
    bz: float,
) -> float:
    """Shortest distance from point (px, pz) to segment (ax,az)→(bx,bz)."""
    dx, dz = bx - ax, bz - az
    len_sq = dx * dx + dz * dz
    if len_sq == 0.0:
        return math.hypot(px - ax, pz - az)
    t = max(0.0, min(1.0, ((px - ax) * dx + (pz - az) * dz) / len_sq))
    cx = ax + t * dx
    cz = az + t * dz
    return math.hypot(px - cx, pz - cz)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


def generate_lanes(map_seed: int) -> list[list[tuple[float, float]]]:
    """
    Generate 3 perturbed lane polylines from *map_seed*.

    Mirrors LaneData._generate_if_needed():
      - For each lane i, seed Python's PRNG with map_seed + 100*(i+1).
      - Draw four uniform samples in [-LANE_FLATTEN, +LANE_FLATTEN] for
        the X and Z offsets of P1 and P2.
      - P0 and P3 are fixed (base and opposing base positions).
      - Sample the resulting Bézier at SAMPLE_COUNT+1 points.

    Returns a list of 3 lanes; each lane is a list of 41 (x, z) tuples.
    """
    lanes: list[list[tuple[float, float]]] = []
    for i, ctrl in enumerate(_LANE_CONTROLS):
        rng = random.Random(map_seed + 100 * (i + 1))
        p1_dx = rng.uniform(-LANE_FLATTEN, LANE_FLATTEN)
        p1_dz = rng.uniform(-LANE_FLATTEN, LANE_FLATTEN)
        p2_dx = rng.uniform(-LANE_FLATTEN, LANE_FLATTEN)
        p2_dz = rng.uniform(-LANE_FLATTEN, LANE_FLATTEN)

        p0 = ctrl[0]
        p1 = (ctrl[1][0] + p1_dx, ctrl[1][1] + p1_dz)
        p2 = (ctrl[2][0] + p2_dx, ctrl[2][1] + p2_dz)
        p3 = ctrl[3]

        lanes.append(_sample_bezier(p0, p1, p2, p3, SAMPLE_COUNT))
    return lanes


def dist_to_polyline(
    px: float,
    pz: float,
    lane: list[tuple[float, float]],
) -> float:
    """
    Minimum distance from point (px, pz) to the lane polyline.

    The polyline is defined by consecutive (x, z) pairs in *lane*.
    """
    min_d = math.inf
    for j in range(len(lane) - 1):
        ax, az = lane[j]
        bx, bz = lane[j + 1]
        d = _dist_point_segment(px, pz, ax, az, bx, bz)
        if d < min_d:
            min_d = d
    return min_d


def point_too_close_to_any_lane(
    px: float,
    pz: float,
    lanes: list[list[tuple[float, float]]],
    setback: float = LANE_SETBACK,
) -> bool:
    """
    Return True if (px, pz) is within *setback* units of any lane polyline.

    Used by Build._lane_setback_ok() to reject tower placements that would
    block minion pathing.
    """
    for lane in lanes:
        if dist_to_polyline(px, pz, lane) < setback:
            return True
    return False
