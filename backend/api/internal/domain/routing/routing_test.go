package routing

import (
	"fmt"
	"math"
	"testing"

	"nelayan-route/internal/domain/physics"
)

// ~500 m spacing at the equator; cells listed in land are left out of the grid.
const step = 0.0045

func testGrid(w, h int, land map[[2]int]bool) *Grid {
	var cells []Cell
	for x := 0; x < w; x++ {
		for y := 0; y < h; y++ {
			if land[[2]int{x, y}] {
				continue
			}
			cells = append(cells, Cell{fmt.Sprintf("X%d_Y%d", x, y), x, y, Point{float64(x) * step, float64(y) * step}})
		}
	}
	return NewGrid(cells)
}

func at(x, y int) Point { return Point{float64(x) * step, float64(y) * step} }

func params() LegParams { return LegParams{STW: 3, RateLPH: 6, MinProgress: 0.1} }

func TestStraightLegMatchesClosedForm(t *testing.T) {
	g := testGrid(5, 1, nil)
	leg, err := g.Route(at(0, 0), at(4, 0), params())
	if err != nil {
		t.Fatal(err)
	}
	want := Distance(at(0, 0), at(4, 0))
	if math.Abs(leg.DistanceM-want) > 1e-6 || math.Abs(leg.DurationS-want/3) > 1e-6 ||
		math.Abs(leg.FuelL-6*want/3/3600) > 1e-9 {
		t.Fatalf("got %+v, want dist %v", leg, want)
	}
}

func TestCurrentMakesLegsAsymmetric(t *testing.T) {
	g := testGrid(5, 1, nil)
	p := params()
	p.Current = physics.VectorTo(1, 90) // flowing east
	out, _ := g.Route(at(0, 0), at(4, 0), p)
	back, _ := g.Route(at(4, 0), at(0, 0), p)
	if !(out.FuelL < back.FuelL) {
		t.Fatalf("downstream %v should be cheaper than upstream %v", out.FuelL, back.FuelL)
	}
}

func TestDetoursAroundLandWithoutCuttingCorners(t *testing.T) {
	// wall at x=2 except the top row
	land := map[[2]int]bool{{2, 0}: true, {2, 1}: true, {2, 2}: true}
	g := testGrid(5, 4, land)
	leg, err := g.Route(at(0, 0), at(4, 0), params())
	if err != nil {
		t.Fatal(err)
	}
	for _, p := range leg.Path {
		if p == at(2, 0) || p == at(2, 1) || p == at(2, 2) {
			t.Fatalf("path enters land: %v", leg.Path)
		}
	}
	if leg.DistanceM <= Distance(at(0, 0), at(4, 0)) {
		t.Fatal("detour must be longer than the straight line")
	}
}

func TestClosedZoneBlocksAndCanDisconnect(t *testing.T) {
	g := testGrid(5, 1, nil)
	p := params()
	box := NewPolygon([][]Point{{{1.5 * step, -1}, {2.5 * step, -1}, {2.5 * step, 1}, {1.5 * step, 1}, {1.5 * step, -1}}})
	p.Obstacles = []Polygon{box}
	if _, err := g.Route(at(0, 0), at(4, 0), p); err != ErrNoRoute {
		t.Fatalf("want ErrNoRoute, got %v", err)
	}
}

func TestCrossCurrentStrongerThanSTWBlocks(t *testing.T) {
	g := testGrid(5, 1, nil)
	p := params()
	p.Current = physics.VectorTo(3.5, 0)
	if _, err := g.Route(at(0, 0), at(4, 0), p); err != ErrNoRoute {
		t.Fatalf("want ErrNoRoute, got %v", err)
	}
}

func TestConnectorTooFar(t *testing.T) {
	g := testGrid(3, 1, nil)
	if _, err := g.Route(Point{1, 1}, at(2, 0), params()); err != ErrNoConnector {
		t.Fatalf("want ErrNoConnector, got %v", err)
	}
}

func TestPolygonHoleAndTouch(t *testing.T) {
	sq := func(a, b float64) []Point { return []Point{{a, a}, {b, a}, {b, b}, {a, b}, {a, a}} }
	p := NewPolygon([][]Point{sq(0, 10), sq(4, 6)})
	if !p.Contains(Point{1, 1}) || p.Contains(Point{5, 5}) || p.Contains(Point{11, 1}) {
		t.Fatal("contains wrong")
	}
	if !p.Blocks(Point{-5, 10}, Point{0, 10}) {
		t.Fatal("touching a vertex must block")
	}
	if p.Blocks(Point{-5, -5}, Point{-1, -1}) {
		t.Fatal("outside segment must not block")
	}
}
