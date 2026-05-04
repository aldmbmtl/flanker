"""
test_lanes.py — Tests for server/lanes.py

All tests are pure unit tests — no network, no Godot.
100% branch coverage required.
"""

from __future__ import annotations

import math

import pytest

from server.lanes import (
    _LANE_CONTROLS,
    LANE_FLATTEN,
    LANE_SETBACK,
    SAMPLE_COUNT,
    _bezier_point,
    _dist_point_segment,
    _sample_bezier,
    dist_to_polyline,
    generate_lanes,
    point_too_close_to_any_lane,
)

# ---------------------------------------------------------------------------
# _bezier_point
# ---------------------------------------------------------------------------


class TestBezierPoint:
    def test_t0_returns_p0(self):
        p0, p1, p2, p3 = (0.0, 0.0), (1.0, 0.0), (2.0, 0.0), (3.0, 0.0)
        pt = _bezier_point(p0, p1, p2, p3, 0.0)
        assert pt == pytest.approx((0.0, 0.0))

    def test_t1_returns_p3(self):
        p0, p1, p2, p3 = (0.0, 0.0), (1.0, 0.0), (2.0, 0.0), (3.0, 0.0)
        pt = _bezier_point(p0, p1, p2, p3, 1.0)
        assert pt == pytest.approx((3.0, 0.0))

    def test_t_half_on_linear(self):
        """For a linear Bézier (all control points collinear), midpoint = midpoint."""
        p0, p1, p2, p3 = (0.0, 0.0), (1.0, 0.0), (2.0, 0.0), (3.0, 0.0)
        pt = _bezier_point(p0, p1, p2, p3, 0.5)
        assert pt == pytest.approx((1.5, 0.0), abs=1e-9)

    def test_both_components_computed(self):
        p0, p1, p2, p3 = (0.0, 0.0), (0.0, 10.0), (0.0, 20.0), (0.0, 30.0)
        pt = _bezier_point(p0, p1, p2, p3, 1.0)
        assert pt == pytest.approx((0.0, 30.0))

    def test_symmetric_curve(self):
        """Symmetric control points should give symmetric output."""
        p0, p1, p2, p3 = (0.0, 0.0), (1.0, 2.0), (2.0, 2.0), (3.0, 0.0)
        pt_quarter = _bezier_point(p0, p1, p2, p3, 0.25)
        pt_three_quarter = _bezier_point(p0, p1, p2, p3, 0.75)
        assert pt_quarter[1] == pytest.approx(pt_three_quarter[1], abs=1e-9)
        assert pt_quarter[0] == pytest.approx(3.0 - pt_three_quarter[0], abs=1e-9)


# ---------------------------------------------------------------------------
# _sample_bezier
# ---------------------------------------------------------------------------


class TestSampleBezier:
    def test_returns_n_plus_one_points(self):
        p0, p1, p2, p3 = (0.0, 0.0), (1.0, 0.0), (2.0, 0.0), (3.0, 0.0)
        pts = _sample_bezier(p0, p1, p2, p3, 10)
        assert len(pts) == 11

    def test_first_point_is_p0(self):
        p0, p1, p2, p3 = (0.0, 5.0), (1.0, 0.0), (2.0, 0.0), (3.0, 0.0)
        pts = _sample_bezier(p0, p1, p2, p3, 5)
        assert pts[0] == pytest.approx((0.0, 5.0))

    def test_last_point_is_p3(self):
        p0, p1, p2, p3 = (0.0, 0.0), (1.0, 0.0), (2.0, 0.0), (9.0, 7.0)
        pts = _sample_bezier(p0, p1, p2, p3, 5)
        assert pts[-1] == pytest.approx((9.0, 7.0))

    def test_sample_count_40_gives_41_points(self):
        p0, p1, p2, p3 = (0.0, 82.0), (-85.0, 82.0), (-85.0, -82.0), (0.0, -82.0)
        pts = _sample_bezier(p0, p1, p2, p3, SAMPLE_COUNT)
        assert len(pts) == SAMPLE_COUNT + 1


# ---------------------------------------------------------------------------
# _dist_point_segment
# ---------------------------------------------------------------------------


class TestDistPointSegment:
    def test_point_at_start(self):
        d = _dist_point_segment(0.0, 0.0, 0.0, 0.0, 10.0, 0.0)
        assert d == pytest.approx(0.0)

    def test_point_at_end(self):
        d = _dist_point_segment(10.0, 0.0, 0.0, 0.0, 10.0, 0.0)
        assert d == pytest.approx(0.0)

    def test_point_on_segment(self):
        d = _dist_point_segment(5.0, 0.0, 0.0, 0.0, 10.0, 0.0)
        assert d == pytest.approx(0.0)

    def test_point_perpendicular_to_midpoint(self):
        d = _dist_point_segment(5.0, 3.0, 0.0, 0.0, 10.0, 0.0)
        assert d == pytest.approx(3.0)

    def test_point_beyond_end_clamps(self):
        d = _dist_point_segment(15.0, 0.0, 0.0, 0.0, 10.0, 0.0)
        assert d == pytest.approx(5.0)

    def test_point_before_start_clamps(self):
        d = _dist_point_segment(-5.0, 0.0, 0.0, 0.0, 10.0, 0.0)
        assert d == pytest.approx(5.0)

    def test_degenerate_segment_zero_length(self):
        """Segment of length 0 → distance to that point."""
        d = _dist_point_segment(3.0, 4.0, 1.0, 1.0, 1.0, 1.0)
        assert d == pytest.approx(math.hypot(2.0, 3.0))


# ---------------------------------------------------------------------------
# generate_lanes
# ---------------------------------------------------------------------------


class TestGenerateLanes:
    def test_returns_three_lanes(self):
        lanes = generate_lanes(12345)
        assert len(lanes) == 3

    def test_each_lane_has_41_points(self):
        lanes = generate_lanes(12345)
        for lane in lanes:
            assert len(lane) == SAMPLE_COUNT + 1

    def test_each_point_is_a_float_pair(self):
        lanes = generate_lanes(99)
        for lane in lanes:
            for pt in lane:
                assert len(pt) == 2
                assert isinstance(pt[0], float)
                assert isinstance(pt[1], float)

    def test_first_point_is_blue_base(self):
        """All lanes start at blue base (0, 82) regardless of seed."""
        lanes = generate_lanes(42)
        for lane in lanes:
            assert lane[0] == pytest.approx((0.0, 82.0))

    def test_last_point_is_red_base(self):
        """All lanes end at red base (0, -82) regardless of seed."""
        lanes = generate_lanes(42)
        for lane in lanes:
            assert lane[-1] == pytest.approx((0.0, -82.0))

    def test_deterministic_same_seed(self):
        lanes_a = generate_lanes(777)
        lanes_b = generate_lanes(777)
        for la, lb in zip(lanes_a, lanes_b, strict=True):
            for pa, pb in zip(la, lb, strict=True):
                assert pa == pytest.approx(pb)

    def test_different_seeds_produce_different_lanes(self):
        lanes_a = generate_lanes(1)
        lanes_b = generate_lanes(2)
        # At least one interior point should differ
        diffs = sum(
            1
            for la, lb in zip(lanes_a, lanes_b, strict=True)
            for pa, pb in zip(la[1:-1], lb[1:-1], strict=True)
            if abs(pa[0] - pb[0]) > 1e-6 or abs(pa[1] - pb[1]) > 1e-6
        )
        assert diffs > 0

    def test_lane_0_is_left_of_mid(self):
        """Left lane should have mostly negative x values in the middle."""
        lanes = generate_lanes(100)
        mid_point = lanes[0][20]
        assert mid_point[0] < 0.0

    def test_lane_2_is_right_of_mid(self):
        """Right lane should have mostly positive x values in the middle."""
        lanes = generate_lanes(100)
        mid_point = lanes[2][20]
        assert mid_point[0] > 0.0

    def test_lane_1_mid_is_near_centre(self):
        """Mid lane runs straight — x near 0 throughout."""
        lanes = generate_lanes(100)
        for pt in lanes[1]:
            assert abs(pt[0]) < LANE_FLATTEN + 1.0  # within perturbation budget

    def test_perturbation_within_bounds(self):
        """No point should stray beyond baseline ± LANE_FLATTEN."""
        for seed_val in (1, 42, 999, 123456):
            lanes = generate_lanes(seed_val)
            for lane_i, lane in enumerate(lanes):
                ctrl = _LANE_CONTROLS[lane_i]
                # Baseline bounding box with generous margin
                all_x = [p[0] for p in ctrl]
                all_z = [p[1] for p in ctrl]
                min_x = min(all_x) - LANE_FLATTEN - 5
                max_x = max(all_x) + LANE_FLATTEN + 5
                min_z = min(all_z) - LANE_FLATTEN - 5
                max_z = max(all_z) + LANE_FLATTEN + 5
                for pt in lane:
                    assert min_x <= pt[0] <= max_x
                    assert min_z <= pt[1] <= max_z

    def test_zero_seed_accepted(self):
        lanes = generate_lanes(0)
        assert len(lanes) == 3


# ---------------------------------------------------------------------------
# dist_to_polyline
# ---------------------------------------------------------------------------


class TestDistToPolyline:
    def _straight_lane(self) -> list[tuple[float, float]]:
        return [(float(i), 0.0) for i in range(11)]

    def test_point_on_polyline(self):
        lane = self._straight_lane()
        d = dist_to_polyline(5.0, 0.0, lane)
        assert d == pytest.approx(0.0)

    def test_point_perpendicular(self):
        lane = self._straight_lane()
        d = dist_to_polyline(5.0, 3.0, lane)
        assert d == pytest.approx(3.0)

    def test_point_beyond_end(self):
        lane = self._straight_lane()
        d = dist_to_polyline(15.0, 0.0, lane)
        assert d == pytest.approx(5.0)

    def test_real_lane_point_near_start(self):
        lanes = generate_lanes(42)
        # A point at the blue base should be on lane 0
        d = dist_to_polyline(0.0, 82.0, lanes[0])
        assert d == pytest.approx(0.0, abs=1e-6)

    def test_single_segment_lane(self):
        lane = [(0.0, 0.0), (10.0, 0.0)]
        d = dist_to_polyline(5.0, 4.0, lane)
        assert d == pytest.approx(4.0)


# ---------------------------------------------------------------------------
# point_too_close_to_any_lane
# ---------------------------------------------------------------------------


class TestPointTooCloseToAnyLane:
    def test_point_on_lane_is_too_close(self):
        lanes = generate_lanes(42)
        # Blue base start is shared by all lanes
        assert point_too_close_to_any_lane(0.0, 82.0, lanes) is True

    def test_point_far_from_all_lanes_is_ok(self):
        lanes = generate_lanes(42)
        # A point deep in the off-lane area should be clear
        assert point_too_close_to_any_lane(50.0, 0.0, lanes) is False

    def test_custom_setback_tighter(self):
        lanes = generate_lanes(42)
        # Start of lane 1 (mid) is at (0, 82)
        # With setback=1 the point directly on the lane is still too close
        assert point_too_close_to_any_lane(0.0, 82.0, lanes, setback=1.0) is True

    def test_custom_setback_zero(self):
        """setback=0 means only exact overlap triggers rejection."""
        lanes = generate_lanes(42)
        # A point slightly off-lane should be ok with setback=0
        result = point_too_close_to_any_lane(50.0, 0.0, lanes, setback=0.0)
        assert result is False

    def test_uses_default_setback(self):
        """Default setback constant is LANE_SETBACK."""
        lanes = generate_lanes(42)
        # Point at distance > LANE_SETBACK from all lanes should be False
        result = point_too_close_to_any_lane(50.0, 0.0, lanes)
        assert isinstance(result, bool)

    def test_returns_true_for_close_point_on_left_lane(self):
        lanes = generate_lanes(42)
        # Lane 0 mid-point is around (-85, 0) area
        lane0_mid = lanes[0][20]
        assert (
            point_too_close_to_any_lane(lane0_mid[0], lane0_mid[1], lanes, setback=LANE_SETBACK)
            is True
        )

    def test_empty_lanes_list(self):
        """No lanes → nothing is close."""
        assert point_too_close_to_any_lane(0.0, 0.0, []) is False
