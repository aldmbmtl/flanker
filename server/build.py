"""
build.py — Tower placement authority (Phase 4).

Python port of the logic sections of BuildSystem.gd.

Owns the "live towers" state dict and validates placement requests against:
  - Registry membership  (unknown type → rejected)
  - Cost                 (delegates to injected spend_points_fn)
  - Team-half check      (team 0 must place at z > 0; team 1 at z < 0)
  - Spacing              (min distance from every existing live tower)

Lane setback (towers must be ≥ 8 units from lane centre-lines) is deferred
to Phase 5 when lane_points.json is exported.  A TODO comment marks the gap.

Name generation mirrors the GDScript naming convention so tower names are
stable across the Python/Godot boundary.

Cross-system callables are injected at construction (same pattern as
combat.py) so the module is testable without the full server stack.
"""

from __future__ import annotations

import math
from collections.abc import Callable
from dataclasses import dataclass, field

from server.lanes import LANE_SETBACK, point_too_close_to_any_lane
from server.registry import DROP_REGISTRY, TOWER_REGISTRY, WEAPON_REGISTRY, WeaponDef

# ── Update / event objects ────────────────────────────────────────────────────


@dataclass
class TowerSpawnedUpdate:
    name: str
    tower_type: str
    team: int
    pos: tuple[float, float, float]
    health: float
    max_health: float


@dataclass
class TowerDamagedUpdate:
    name: str
    health: float


@dataclass
class TowerDespawnedUpdate:
    name: str
    tower_type: str
    team: int


@dataclass
class PlacementRejectedUpdate:
    reason: str  # "unknown_type" | "insufficient_funds" | "spacing" | "team_half"


@dataclass
class TowerVisualUpdate:
    """Opaque visual broadcast relayed unchanged to all clients."""

    vtype: str
    params: dict = field(default_factory=dict)


@dataclass
class DropConsumedUpdate:
    """Emitted when a drop is successfully consumed; tells clients to despawn it."""

    name: str
    team: int


# ── Internal tower state ──────────────────────────────────────────────────────


@dataclass
class TowerState:
    name: str
    tower_type: str
    team: int
    pos: tuple[float, float, float]
    health: float
    max_health: float
    placer_peer_id: int = -1


# ── Build ─────────────────────────────────────────────────────────────────────

# Map boundaries
_MAP_HALF: float = 100.0  # map is 200×200; team half boundary is z=0
_SPACING_FLOOR: float = 3.0  # absolute minimum spacing (SPACING_PASSIVE)


class Build:
    """
    Owns the set of live towers and authoritative placement/damage logic.

    Injected callables (all default to safe no-ops):
      spend_points_fn(team, amount) -> bool   — deduct cost; returns False if insufficient
      award_xp_fn(peer_id, amount)            — called on tower death
      add_team_points_fn(team, amount)        — called on tower kill (team points)
      get_team_points_fn(team) -> int         — read back for TeamPointsUpdate

    Optional:
      lane_points — list of 3 lane polylines from lanes.generate_lanes().
                    When provided, placement within LANE_SETBACK units of any
                    lane is rejected with reason="lane_setback".
                    If None (default), the setback check is skipped.
    """

    # Max-health values match TowerBase .tscn @export values documented in AGENTS.md
    _MAX_HEALTH: dict[str, float] = {
        "cannon": 900.0,
        "mortar": 700.0,
        "machinegun": 600.0,
        "slow": 500.0,
        "barrier": 1200.0,
        "launcher_missile": 600.0,
    }
    # XP awarded to killer on tower death (matches LevelSystem.XP_TOWER = 200)
    XP_TOWER: int = 200

    def __init__(
        self,
        spend_points_fn: Callable[[int, int], bool] | None = None,
        award_xp_fn: Callable[[int, int], None] | None = None,
        add_team_points_fn: Callable[[int, int], None] | None = None,
        get_team_points_fn: Callable[[int], int] | None = None,
        lane_points: list[list[tuple[float, float]]] | None = None,
    ) -> None:
        self._spend_points = spend_points_fn or (lambda t, a: True)
        self._award_xp = award_xp_fn or (lambda pid, a: None)
        self._add_team_points = add_team_points_fn or (lambda t, a: None)
        self._get_team_points = get_team_points_fn or (lambda t: 0)
        self._lane_points: list[list[tuple[float, float]]] | None = lane_points

        # name → TowerState
        self._towers: dict[str, TowerState] = {}

        # name → team: pickups registered as live and available to consume
        self._live_drops: dict[str, int] = {}
        # names already consumed this round (prevent double-pickup)
        self._consumed_drops: set[str] = set()

    def set_lane_points(self, lane_points: list[list[tuple[float, float]]]) -> None:
        """Update lane geometry used for setback checks (called after game_started)."""
        self._lane_points = lane_points

    # ── Queries ───────────────────────────────────────────────────────────────

    def get_live_towers(self) -> list[TowerState]:
        return list(self._towers.values())

    def get_tower(self, name: str) -> TowerState | None:
        return self._towers.get(name)

    # ── Placement ────────────────────────────────────────────────────────────

    def place_tower(
        self,
        pos: tuple[float, float, float],
        team: int,
        item_type: str,
        placer_peer_id: int = -1,
        forced_name: str = "",
        spacing_mult: float = 1.0,
    ) -> list:
        """
        Validate and place a tower or drop.

        Returns a list containing either:
          [TowerSpawnedUpdate]      — success
          [PlacementRejectedUpdate] — validation failure (no state change)
        """
        # ── Registry check ────────────────────────────────────────────────────
        defn = (
            TOWER_REGISTRY.get(item_type)
            or DROP_REGISTRY.get(item_type)
            or WEAPON_REGISTRY.get(item_type)
        )
        # "weapon" is the generic weapon-drop type used by BuildSystem.gd when
        # no specific subtype is given; treat it as a WeaponDef with default cost.
        if defn is None and item_type == "weapon":
            defn = WeaponDef(weapon_type="weapon", cost=0)
        if defn is None:
            return [PlacementRejectedUpdate(reason="unknown_type")]

        # ── Team-half check ───────────────────────────────────────────────────
        z = pos[2]
        if team == 0 and z <= 0.0:
            return [PlacementRejectedUpdate(reason="team_half")]
        if team == 1 and z >= 0.0:
            return [PlacementRejectedUpdate(reason="team_half")]

        # ── Lane setback check ────────────────────────────────────────────────
        if self._lane_points is not None and point_too_close_to_any_lane(
            pos[0], pos[2], self._lane_points, setback=LANE_SETBACK
        ):
            return [PlacementRejectedUpdate(reason="lane_setback")]

        # ── Spacing check ─────────────────────────────────────────────────────
        if isinstance(defn, WeaponDef):
            spacing = 5.0  # matches BuildSystem.gd WEAPON spacing
        else:
            spacing = defn.spacing
        if not self._spacing_ok(pos, spacing, spacing_mult):
            return [PlacementRejectedUpdate(reason="spacing")]

        # ── Cost check ───────────────────────────────────────────────────────
        cost = defn.cost
        if cost > 0 and not self._spend_points(team, cost):
            return [PlacementRejectedUpdate(reason="insufficient_funds")]

        # ── Create tower ─────────────────────────────────────────────────────
        name = forced_name or _make_name(item_type, pos)
        max_hp = self._MAX_HEALTH.get(item_type, 500.0)
        state = TowerState(
            name=name,
            tower_type=item_type,
            team=team,
            pos=pos,
            health=max_hp,
            max_health=max_hp,
            placer_peer_id=placer_peer_id,
        )
        self._towers[name] = state

        return [
            TowerSpawnedUpdate(
                name=name,
                tower_type=item_type,
                team=team,
                pos=pos,
                health=max_hp,
                max_health=max_hp,
            )
        ]

    # ── Damage ────────────────────────────────────────────────────────────────

    def damage_tower(
        self,
        name: str,
        amount: float,
        source_team: int,
        shooter_peer_id: int = -1,
    ) -> list:
        """
        Apply *amount* damage to tower *name*.

        Friendly-fire guard: if source_team == tower.team → no-op.

        Returns:
          []                                     — unknown tower or friendly fire
          [TowerDamagedUpdate]                   — alive after hit
          [TowerDamagedUpdate, TowerDespawnedUpdate] — killed
        """
        state = self._towers.get(name)
        if state is None:
            return []
        if source_team == state.team:
            return []

        new_hp = max(0.0, state.health - amount)
        state.health = new_hp
        updates: list = [TowerDamagedUpdate(name=name, health=new_hp)]

        if new_hp <= 0.0:
            self._towers.pop(name, None)
            updates.append(
                TowerDespawnedUpdate(name=name, tower_type=state.tower_type, team=state.team)
            )
            # Award XP and team points to killer
            if shooter_peer_id > 0:
                self._award_xp(shooter_peer_id, self.XP_TOWER)

        return updates

    # ── Forced removal ────────────────────────────────────────────────────────

    def remove_tower(self, name: str, source_team: int = -1) -> list:
        """
        Forcibly remove a tower (e.g. push-rollback despawn).

        source_team is informational only — no friendly-fire guard here.
        Returns [TowerDespawnedUpdate] or [] if the tower is unknown.
        """
        state = self._towers.pop(name, None)
        if state is None:
            return []
        return [TowerDespawnedUpdate(name=name, tower_type=state.tower_type, team=state.team)]

    # ── Reset ─────────────────────────────────────────────────────────────────

    def reset(self) -> None:
        self._towers.clear()
        self._live_drops.clear()
        self._consumed_drops.clear()

    # ── Drop registration / consumption ──────────────────────────────────────

    def register_drop(self, name: str, team: int) -> None:
        """
        Mark a pickup as live on the map.

        Calling register_drop for an existing name (e.g. respawn after 90 s)
        re-enables it by removing it from _consumed_drops.
        """
        self._live_drops[name] = team
        self._consumed_drops.discard(name)

    def consume_drop(self, name: str) -> list:
        """
        Attempt to consume (pick up) a drop.

        Returns [DropConsumedUpdate] on success, [] on failure (unknown name
        or already consumed).
        """
        if name not in self._live_drops:
            return []
        if name in self._consumed_drops:
            return []
        team = self._live_drops.pop(name)
        self._consumed_drops.add(name)
        return [DropConsumedUpdate(name=name, team=team)]

    # ── Private helpers ───────────────────────────────────────────────────────

    def _spacing_ok(
        self, pos: tuple[float, float, float], required: float, spacing_mult: float = 1.0
    ) -> bool:
        """Return True if *pos* is at least *required* units from every live tower.

        *spacing_mult* is a [0, 1] multiplier applied after the effective spacing is
        computed (mirrors the ``range_mult`` in ``BuildSystem.can_place_item``).  The
        result is floored at ``_SPACING_FLOOR`` so towers can never fully overlap.
        """
        for t in self._towers.values():
            d = _dist3(pos, t.pos)
            existing_def = TOWER_REGISTRY.get(t.tower_type) or DROP_REGISTRY.get(t.tower_type)
            existing_spacing = existing_def.spacing if existing_def is not None else required
            effective = max(required, existing_spacing, _SPACING_FLOOR) * spacing_mult
            effective = max(effective, _SPACING_FLOOR)
            if d < effective:
                return False
        return True


# ── Module helpers ────────────────────────────────────────────────────────────


def _dist3(a: tuple[float, float, float], b: tuple[float, float, float]) -> float:
    return math.sqrt((a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2 + (a[2] - b[2]) ** 2)


def _make_name(item_type: str, pos: tuple[float, float, float]) -> str:
    """Generate a deterministic node name matching GDScript convention."""
    sx = int(pos[0])
    sz = int(pos[2])
    if item_type in ("cannon", "mortar", "slow", "machinegun"):
        return f"Tower_{item_type}_{sx}_{sz}"
    if item_type == "healstation":
        return f"HealStation_{sx}_{sz}"
    if item_type in ("healthpack", "weapon"):
        return f"Drop_{item_type}_{sx}_{sz}"
    if item_type.startswith("launcher_"):
        suffix = item_type.replace("launcher_", "")
        return f"Launcher_{suffix}_{sx}_{sz}"
    # Fallback for future tower types
    return f"Tower_{item_type}_{sx}_{sz}"
