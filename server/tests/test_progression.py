"""Tests for server/progression.py — Progression class."""

import pytest

from server.progression import LevelUpEvent, Progression

# ── Helpers ───────────────────────────────────────────────────────────────────


def make(role: str = "") -> Progression:
    return Progression(get_role_fn=lambda _: role)


def make_with_peer(role: str = "", peer: int = 1) -> tuple[Progression, int]:
    p = make(role)
    p.register_peer(peer)
    return p, peer


def level_up_to(p: Progression, peer: int, target_level: int) -> None:
    """Award enough XP to reach exactly *target_level*."""
    while p.get_level(peer) < target_level:
        needed = p.get_xp_needed(peer)
        p.award_xp(peer, needed - p.get_xp(peer))


# ── register / clear ─────────────────────────────────────────────────────────


def test_register_initialises_level_1():
    p, peer = make_with_peer()
    assert p.get_level(peer) == 1


def test_register_initialises_zero_xp():
    p, peer = make_with_peer()
    assert p.get_xp(peer) == 0


def test_register_initialises_zero_points():
    p, peer = make_with_peer()
    assert p.get_unspent_points(peer) == 0


def test_register_idempotent():
    p, peer = make_with_peer()
    p.award_xp(peer, 50)
    p.register_peer(peer)  # second call must not reset state
    assert p.get_xp(peer) == 50


def test_clear_peer_removes_state():
    p, peer = make_with_peer()
    p.clear_peer(peer)
    assert p.get_level(peer) == 1  # default fallback
    assert p.get_xp(peer) == 0


def test_clear_peer_unknown_is_noop():
    p = make()
    p.clear_peer(999)  # must not raise


def test_clear_all():
    p = make()
    p.register_peer(1)
    p.register_peer(2)
    p.clear_all()
    assert p.get_xp(1) == 0
    assert p.get_xp(2) == 0


# ── award_xp / levelling ──────────────────────────────────────────────────────


def test_award_xp_accumulates():
    p, peer = make_with_peer()
    p.award_xp(peer, 30)
    p.award_xp(peer, 20)
    assert p.get_xp(peer) == 50


def test_award_xp_auto_registers_unknown_peer():
    p = make()
    events = p.award_xp(999, 10)
    assert p.get_xp(999) == 10
    assert events == []


def test_first_level_up_at_70_xp():
    p, peer = make_with_peer()
    events = p.award_xp(peer, 70)
    assert p.get_level(peer) == 2
    assert len(events) == 1
    assert isinstance(events[0], LevelUpEvent)
    assert events[0].new_level == 2
    assert events[0].pts_awarded == Progression.POINTS_PER_LEVEL[0]


def test_xp_carry_over_after_level_up():
    p, peer = make_with_peer()
    p.award_xp(peer, 80)  # 70 needed → 10 left
    assert p.get_xp(peer) == 10


def test_multiple_level_ups_in_one_award():
    p, peer = make_with_peer()
    # Level 1→2: 70, Level 2→3: 140.  Award 210 at once.
    events = p.award_xp(peer, 210)
    assert p.get_level(peer) == 3
    assert len(events) == 2


def test_no_level_up_below_threshold():
    p, peer = make_with_peer()
    events = p.award_xp(peer, 69)
    assert p.get_level(peer) == 1
    assert events == []


def test_max_level_cap():
    p, peer = make_with_peer()
    level_up_to(p, peer, Progression.MAX_LEVEL)
    assert p.get_level(peer) == Progression.MAX_LEVEL
    events = p.award_xp(peer, 999_999)
    assert p.get_level(peer) == Progression.MAX_LEVEL
    assert events == []


def test_xp_needed_at_max_level_is_sentinel():
    p, peer = make_with_peer()
    level_up_to(p, peer, Progression.MAX_LEVEL)
    assert p.get_xp_needed(peer) == 999_999


def test_points_awarded_per_level():
    p, peer = make_with_peer()
    total_pts = 0
    for i in range(1, Progression.MAX_LEVEL):
        level_up_to(p, peer, i + 1)
        total_pts += Progression.POINTS_PER_LEVEL[i - 1]
    assert p.get_unspent_points(peer) == total_pts


# ── spend_point — role-neutral ────────────────────────────────────────────────


def test_spend_point_success():
    p, peer = make_with_peer(role="Fighter")
    p.award_xp(peer, 70)  # level 2, +1 pt
    result = p.spend_point(peer, "hp")
    assert result is True
    assert p.get_attrs(peer)["hp"] == 1
    assert p.get_unspent_points(peer) == 0


def test_spend_point_no_points_returns_false():
    p, peer = make_with_peer(role="Fighter")
    assert p.spend_point(peer, "hp") is False


def test_spend_point_unknown_peer_returns_false():
    p = make()
    assert p.spend_point(999, "hp") is False


def test_spend_point_invalid_attr_returns_false():
    p, peer = make_with_peer(role="Fighter")
    p.award_xp(peer, 70)
    assert p.spend_point(peer, "flying_ability") is False


def test_spend_point_cap():
    p, peer = make_with_peer(role="")  # no role gate
    # Earn enough pts to hit cap
    level_up_to(p, peer, Progression.MAX_LEVEL)
    for _ in range(Progression.ATTR_CAP):
        p.spend_point(peer, "hp")
    assert p.spend_point(peer, "hp") is False
    assert p.get_attrs(peer)["hp"] == Progression.ATTR_CAP


# ── spend_point — role gating ─────────────────────────────────────────────────


def test_fighter_cannot_spend_supporter_attr():
    p, peer = make_with_peer(role="Fighter")
    p.award_xp(peer, 70)
    assert p.spend_point(peer, "tower_hp") is False


def test_supporter_cannot_spend_fighter_attr():
    p, peer = make_with_peer(role="Supporter")
    p.award_xp(peer, 70)
    assert p.spend_point(peer, "hp") is False


def test_no_role_gate_allows_any_attr():
    p, peer = make_with_peer(role="")
    p.award_xp(peer, 70)
    assert p.spend_point(peer, "tower_hp") is True


# ── stat bonus helpers ────────────────────────────────────────────────────────


def test_bonus_hp():
    p, peer = make_with_peer()
    assert p.get_bonus_hp(peer) == pytest.approx(0.0)
    p.award_xp(peer, 70)
    p.spend_point(peer, "hp")
    assert p.get_bonus_hp(peer) == pytest.approx(Progression.HP_PER_POINT)


def test_bonus_speed_mult():
    p, peer = make_with_peer()
    p.award_xp(peer, 70)
    p.spend_point(peer, "speed")
    assert p.get_bonus_speed_mult(peer) == pytest.approx(Progression.SPEED_PER_POINT)


def test_bonus_damage_mult():
    p, peer = make_with_peer()
    p.award_xp(peer, 70)
    p.spend_point(peer, "damage")
    assert p.get_bonus_damage_mult(peer) == pytest.approx(Progression.DAMAGE_PER_POINT)


def test_bonus_stamina():
    p, peer = make_with_peer()
    p.award_xp(peer, 70)
    p.spend_point(peer, "stamina")
    assert p.get_bonus_stamina(peer) == pytest.approx(Progression.STAMINA_PER_POINT)


def test_bonus_tower_hp_mult():
    p, peer = make_with_peer(role="Supporter")
    p.award_xp(peer, 70)
    p.spend_point(peer, "tower_hp")
    assert p.get_bonus_tower_hp_mult(peer) == pytest.approx(Progression.TOWER_HP_PER_POINT)


def test_bonus_placement_range_mult():
    p, peer = make_with_peer(role="Supporter")
    p.award_xp(peer, 70)
    p.spend_point(peer, "placement_range")
    assert p.get_bonus_placement_range_mult(peer) == pytest.approx(
        Progression.PLACEMENT_RANGE_PER_POINT
    )


def test_bonus_tower_fire_rate_mult():
    p, peer = make_with_peer(role="Supporter")
    p.award_xp(peer, 70)
    p.spend_point(peer, "tower_fire_rate")
    assert p.get_bonus_tower_fire_rate_mult(peer) == pytest.approx(
        Progression.TOWER_FIRE_RATE_PER_POINT
    )


def test_bonuses_zero_for_unknown_peer():
    p = make()
    assert p.get_bonus_hp(42) == 0.0
    assert p.get_bonus_speed_mult(42) == 0.0
    assert p.get_bonus_damage_mult(42) == 0.0
    assert p.get_bonus_stamina(42) == 0.0
    assert p.get_bonus_tower_hp_mult(42) == 0.0
    assert p.get_bonus_placement_range_mult(42) == 0.0
    assert p.get_bonus_tower_fire_rate_mult(42) == 0.0


# ── XP_PER_LEVEL table integrity ─────────────────────────────────────────────


def test_xp_per_level_length():
    # MAX_LEVEL - 1 thresholds needed (level 1→2 through 11→12)
    assert len(Progression.XP_PER_LEVEL) == Progression.MAX_LEVEL - 1


def test_xp_per_level_is_increasing():
    for i in range(len(Progression.XP_PER_LEVEL) - 1):
        assert Progression.XP_PER_LEVEL[i] < Progression.XP_PER_LEVEL[i + 1]


def test_points_per_level_length():
    assert len(Progression.POINTS_PER_LEVEL) == Progression.MAX_LEVEL - 1
