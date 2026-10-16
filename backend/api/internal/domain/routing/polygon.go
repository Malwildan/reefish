package routing

import "math"

// Polygon is a closed zone in lon/lat; ring 0 is the shell, the rest are holes.
type Polygon struct {
	Rings                  [][]Point
	minX, minY, maxX, maxY float64
}

func NewPolygon(rings [][]Point) Polygon {
	p := Polygon{Rings: rings, minX: math.Inf(1), minY: math.Inf(1), maxX: math.Inf(-1), maxY: math.Inf(-1)}
	for _, r := range rings {
		for _, q := range r {
			p.minX, p.maxX = math.Min(p.minX, q.Lon), math.Max(p.maxX, q.Lon)
			p.minY, p.maxY = math.Min(p.minY, q.Lat), math.Max(p.maxY, q.Lat)
		}
	}
	return p
}

// Contains uses the even-odd rule, so holes are excluded.
func (p Polygon) Contains(pt Point) bool {
	in := false
	for _, r := range p.Rings {
		for i, j := 0, len(r)-1; i < len(r); j, i = i, i+1 {
			a, b := r[i], r[j]
			if (a.Lat > pt.Lat) != (b.Lat > pt.Lat) &&
				pt.Lon < (b.Lon-a.Lon)*(pt.Lat-a.Lat)/(b.Lat-a.Lat)+a.Lon {
				in = !in
			}
		}
	}
	return in
}

// Blocks reports whether segment a→b enters, crosses or touches the polygon.
func (p Polygon) Blocks(a, b Point) bool {
	if math.Max(a.Lon, b.Lon) < p.minX || math.Min(a.Lon, b.Lon) > p.maxX ||
		math.Max(a.Lat, b.Lat) < p.minY || math.Min(a.Lat, b.Lat) > p.maxY {
		return false
	}
	if p.Contains(a) || p.Contains(b) {
		return true
	}
	for _, r := range p.Rings {
		for i, j := 0, len(r)-1; i < len(r); j, i = i, i+1 {
			if segmentsTouch(a, b, r[j], r[i]) {
				return true
			}
		}
	}
	return false
}

func orient(a, b, c Point) float64 {
	return (b.Lon-a.Lon)*(c.Lat-a.Lat) - (b.Lat-a.Lat)*(c.Lon-a.Lon)
}

func onSegment(a, b, c Point) bool {
	return math.Min(a.Lon, b.Lon) <= c.Lon && c.Lon <= math.Max(a.Lon, b.Lon) &&
		math.Min(a.Lat, b.Lat) <= c.Lat && c.Lat <= math.Max(a.Lat, b.Lat)
}

func segmentsTouch(p1, p2, q1, q2 Point) bool {
	d1, d2 := orient(q1, q2, p1), orient(q1, q2, p2)
	d3, d4 := orient(p1, p2, q1), orient(p1, p2, q2)
	if ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) && ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0)) {
		return true
	}
	return (d1 == 0 && onSegment(q1, q2, p1)) || (d2 == 0 && onSegment(q1, q2, p2)) ||
		(d3 == 0 && onSegment(p1, p2, q1)) || (d4 == 0 && onSegment(p1, p2, q2))
}
