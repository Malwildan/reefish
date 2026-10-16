// Package routing searches fuel-minimal legs over the 500 m sea grid (spec 9–11),
// static_snapshot mode with a spatially uniform environment.
package routing

import (
	"container/heap"
	"errors"
	"math"

	"nelayan-route/internal/domain/physics"
)

const (
	earthR = 6371008.8
	// Max length of the virtual connector from a real point (harbour, spot) into the grid.
	ConnectorMaxM = 1000.0
)

var (
	ErrNoRoute     = errors.New("NO_ROUTE_IN_SEARCH_GRAPH")
	ErrNoConnector = errors.New("no sea cell reachable within connector distance")
)

type Point struct{ Lon, Lat float64 }

// Cell is one sea cell centre; X/Y are grid indices (missing cells are land/no data).
type Cell struct {
	ID   string
	X, Y int
	Point
}

type Grid struct {
	cells []Cell
	index map[[2]int]int
}

func NewGrid(cells []Cell) *Grid {
	g := &Grid{cells: cells, index: make(map[[2]int]int, len(cells))}
	for i, c := range cells {
		g.index[[2]int{c.X, c.Y}] = i
	}
	return g
}

func (g *Grid) Len() int { return len(g.cells) }

// metric returns the east/north offset in metres from a to b.
// shortcut: local equirectangular projection, accurate for 500 m edges inside the pilot area; switch to UTM (spec 9.1) for large areas.
func metric(a, b Point) (dE, dN float64) {
	lat := (a.Lat + b.Lat) / 2 * math.Pi / 180
	return (b.Lon - a.Lon) * math.Pi / 180 * earthR * math.Cos(lat), (b.Lat - a.Lat) * math.Pi / 180 * earthR
}

func Distance(a, b Point) float64 { return math.Hypot(metric(a, b)) }

type LegParams struct {
	STW         float64     // m/s through water
	RateLPH     float64     // q0 at STW and load class
	Current     physics.Vec // uniform, motion "to"
	MinProgress float64     // m/s, minimum along-track SOG
	Obstacles   []Polygon   // closed zones; touching counts as blocked
}

type Leg struct {
	Path      []Point
	DistanceM float64
	DurationS float64
	FuelL     float64
}

// edge evaluates the directed segment a→b; ok=false means the edge is not traversable.
func (p LegParams) edge(a, b Point) (dist, dur float64, ok bool) {
	dE, dN := metric(a, b)
	dist = math.Hypot(dE, dN)
	if dist == 0 {
		return 0, 0, true
	}
	sog, _, err := physics.SolveTrack(physics.Vec{E: dE / dist, N: dN / dist}, p.STW, p.Current)
	if err != nil || sog < p.MinProgress {
		return 0, 0, false
	}
	for _, o := range p.Obstacles {
		if o.Blocks(a, b) {
			return 0, 0, false
		}
	}
	return dist, dist / sog, true
}

var dirs = [8][2]int{{1, 0}, {-1, 0}, {0, 1}, {0, -1}, {1, 1}, {1, -1}, {-1, 1}, {-1, -1}}

// Route runs Dijkstra (h = 0) from a real point to a real point through virtual connectors.
// Fuel rate is constant within a leg, so the fuel-minimal path is also the time-minimal one.
func (g *Grid) Route(from, to Point, p LegParams) (Leg, error) {
	n := len(g.cells)
	src, dst := n, n+1
	pt := func(i int) Point {
		switch i {
		case src:
			return from
		case dst:
			return to
		}
		return g.cells[i].Point
	}

	var startEdges []int
	goalCells := map[int]bool{}
	for i, c := range g.cells {
		if Distance(from, c.Point) <= ConnectorMaxM {
			startEdges = append(startEdges, i)
		}
		if Distance(c.Point, to) <= ConnectorMaxM {
			goalCells[i] = true
		}
	}
	if len(startEdges) == 0 || len(goalCells) == 0 {
		return Leg{}, ErrNoConnector
	}

	cost := make([]float64, n+2)
	for i := range cost {
		cost[i] = math.Inf(1)
	}
	prev := make([]int, n+2)
	stepDist := make([]float64, n+2)
	stepDur := make([]float64, n+2)
	cost[src] = 0
	pq := &queue{{src, 0}}

	relax := func(u, v int) {
		dist, dur, ok := p.edge(pt(u), pt(v))
		if !ok {
			return
		}
		if c := cost[u] + p.RateLPH*dur/3600; c < cost[v] {
			cost[v], prev[v], stepDist[v], stepDur[v] = c, u, dist, dur
			heap.Push(pq, item{v, c})
		}
	}

	for pq.Len() > 0 {
		cur := heap.Pop(pq).(item)
		u := cur.node
		if cur.cost > cost[u] {
			continue
		}
		if u == dst {
			break
		}
		if u == src {
			for _, v := range startEdges {
				relax(u, v)
			}
			continue
		}
		c := g.cells[u]
		for _, d := range dirs {
			v, ok := g.index[[2]int{c.X + d[0], c.Y + d[1]}]
			if !ok {
				continue
			}
			if d[0] != 0 && d[1] != 0 { // diagonal may not cut a land corner
				_, okA := g.index[[2]int{c.X + d[0], c.Y}]
				_, okB := g.index[[2]int{c.X, c.Y + d[1]}]
				if !okA || !okB {
					continue
				}
			}
			relax(u, v)
		}
		if goalCells[u] {
			relax(u, dst)
		}
	}
	if math.IsInf(cost[dst], 1) {
		return Leg{}, ErrNoRoute
	}

	leg := Leg{FuelL: cost[dst]}
	for v := dst; v != src; v = prev[v] {
		leg.Path = append(leg.Path, pt(v))
		leg.DistanceM += stepDist[v]
		leg.DurationS += stepDur[v]
	}
	leg.Path = append(leg.Path, from)
	for i, j := 0, len(leg.Path)-1; i < j; i, j = i+1, j-1 {
		leg.Path[i], leg.Path[j] = leg.Path[j], leg.Path[i]
	}
	return leg, nil
}

type item struct {
	node int
	cost float64
}
type queue []item

func (q queue) Len() int           { return len(q) }
func (q queue) Less(i, j int) bool { return q[i].cost < q[j].cost }
func (q queue) Swap(i, j int)      { q[i], q[j] = q[j], q[i] }
func (q *queue) Push(x any)        { *q = append(*q, x.(item)) }
func (q *queue) Pop() any          { o := *q; it := o[len(o)-1]; *q = o[:len(o)-1]; return it }
