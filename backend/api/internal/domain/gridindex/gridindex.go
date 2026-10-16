// Package gridindex is the reference implementation of the shared 500 m grid (contracts/grid-index.md):
// WGS84 lon/lat <-> UTM zone 49S (EPSG:32749) <-> cell X{xxx}_Y{yyy} <-> main's canonical
// tp-id-utm49s-500m:v2:rp{row}:cp{col}. Clients must reproduce contracts/fixtures/grid-index-vectors.json.
package gridindex

import (
	"fmt"
	"math"
)

const (
	OriginE  = 637500.0  // lower-left corner of X001_Y001, metres EPSG:32749
	OriginN  = 8988000.0 // (guide section 7)
	CellSize = 500.0
	Cols     = 187
	Rows     = 177

	// main's canonical grid counts cells from projected (0, 0): col = E/500, row = N/500
	colOffset       = int(OriginE/CellSize) - 1 // 1274
	rowOffset       = int(OriginN/CellSize) - 1 // 17975
	canonicalPrefix = "tp-id-utm49s-500m:v2"
)

// Cell is a grid cell by 1-based indices; X grows east, Y grows north.
type Cell struct{ X, Y int }

// FromUTM returns the cell containing (e, n). Edges are left/bottom inclusive.
func FromUTM(e, n float64) Cell {
	return Cell{int(math.Floor((e-OriginE)/CellSize)) + 1, int(math.Floor((n-OriginN)/CellSize)) + 1}
}

func FromLatLon(lat, lon float64) Cell { return FromUTM(ToUTM(lat, lon)) }

// InPilot reports whether the cell lies in the 187 x 177 index range. Not every cell in range has data.
func (c Cell) InPilot() bool { return c.X >= 1 && c.X <= Cols && c.Y >= 1 && c.Y <= Rows }

func (c Cell) ID() string { return fmt.Sprintf("X%03d_Y%03d", c.X, c.Y) }

func (c Cell) Canonical() string {
	return fmt.Sprintf("%s:rp%d:cp%d", canonicalPrefix, c.Y+rowOffset, c.X+colOffset)
}

// Center returns the cell centre in UTM metres.
func (c Cell) Center() (e, n float64) {
	return OriginE + (float64(c.X)-0.5)*CellSize, OriginN + (float64(c.Y)-0.5)*CellSize
}

func ParseXY(s string) (Cell, error) {
	var c Cell
	var rest string
	if n, _ := fmt.Sscanf(s, "X%d_Y%d%s", &c.X, &c.Y, &rest); n != 2 || s != c.ID() {
		return Cell{}, fmt.Errorf("grid id %q: want X{xxx}_Y{yyy}", s)
	}
	return c, nil
}

func ParseCanonical(s string) (Cell, error) {
	var row, col int
	var rest string
	if n, _ := fmt.Sscanf(s, canonicalPrefix+":rp%d:cp%d%s", &row, &col, &rest); n != 2 {
		return Cell{}, fmt.Errorf("cell id %q: want %s:rp{row}:cp{col}", s, canonicalPrefix)
	}
	c := Cell{col - colOffset, row - rowOffset}
	if c.Canonical() != s {
		return Cell{}, fmt.Errorf("cell id %q is not canonical", s)
	}
	return c, nil
}

// WGS84 and UTM zone 49 south.
const (
	a        = 6378137.0
	flat     = 1 / 298.257223563
	k0       = 0.9996
	lon0     = 111.0 * math.Pi / 180
	falseE   = 500000.0
	falseN   = 10000000.0
	degToRad = math.Pi / 180
)

var (
	e2  = flat * (2 - flat)
	ep2 = e2 / (1 - e2)
)

func meridianArc(phi float64) float64 {
	e4, e6 := e2*e2, e2*e2*e2
	return a * ((1-e2/4-3*e4/64-5*e6/256)*phi -
		(3*e2/8+3*e4/32+45*e6/1024)*math.Sin(2*phi) +
		(15*e4/256+45*e6/1024)*math.Sin(4*phi) -
		(35*e6/3072)*math.Sin(6*phi))
}

// ToUTM projects WGS84 lat/lon (degrees) to EPSG:32749 (Snyder, USGS PP 1395, eq. 8-9..8-10).
func ToUTM(lat, lon float64) (e, n float64) {
	phi, lam := lat*degToRad, lon*degToRad
	sin, cos, tan := math.Sin(phi), math.Cos(phi), math.Tan(phi)
	nu := a / math.Sqrt(1-e2*sin*sin)
	t := tan * tan
	c := ep2 * cos * cos
	A := (lam - lon0) * cos
	e = falseE + k0*nu*(A+(1-t+c)*math.Pow(A, 3)/6+(5-18*t+t*t+72*c-58*ep2)*math.Pow(A, 5)/120)
	n = falseN + k0*(meridianArc(phi)+nu*tan*(A*A/2+(5-t+9*c+4*c*c)*math.Pow(A, 4)/24+
		(61-58*t+t*t+600*c-330*ep2)*math.Pow(A, 6)/720))
	return e, n
}

// ToLatLon is the inverse of ToUTM (Snyder eq. 8-18..8-25).
func ToLatLon(e, n float64) (lat, lon float64) {
	m := (n - falseN) / k0
	e4, e6 := e2*e2, e2*e2*e2
	mu := m / (a * (1 - e2/4 - 3*e4/64 - 5*e6/256))
	e1 := (1 - math.Sqrt(1-e2)) / (1 + math.Sqrt(1-e2))
	phi1 := mu + (3*e1/2-27*math.Pow(e1, 3)/32)*math.Sin(2*mu) +
		(21*e1*e1/16-55*math.Pow(e1, 4)/32)*math.Sin(4*mu) +
		(151*math.Pow(e1, 3)/96)*math.Sin(6*mu) +
		(1097*math.Pow(e1, 4)/512)*math.Sin(8*mu)
	sin, cos, tan := math.Sin(phi1), math.Cos(phi1), math.Tan(phi1)
	c1 := ep2 * cos * cos
	t1 := tan * tan
	n1 := a / math.Sqrt(1-e2*sin*sin)
	r1 := a * (1 - e2) / math.Pow(1-e2*sin*sin, 1.5)
	d := (e - falseE) / (n1 * k0)
	phi := phi1 - (n1*tan/r1)*(d*d/2-(5+3*t1+10*c1-4*c1*c1-9*ep2)*math.Pow(d, 4)/24+
		(61+90*t1+298*c1+45*t1*t1-252*ep2-3*c1*c1)*math.Pow(d, 6)/720)
	lam := lon0 + (d-(1+2*t1+c1)*math.Pow(d, 3)/6+(5-2*c1+28*t1-3*c1*c1+8*ep2+24*t1*t1)*math.Pow(d, 5)/120)/cos
	return phi / degToRad, lam / degToRad
}
