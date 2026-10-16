// Package physics implements the kinematics and fuel model of spec section 8.
// Vectors are (east, north) in m/s; bearings are degrees from true north, clockwise.
package physics

import (
	"errors"
	"fmt"
	"math"
	"sort"
)

type Vec struct{ E, N float64 }

func (a Vec) Dot(b Vec) float64 { return a.E*b.E + a.N*b.N }
func (a Vec) Norm() float64     { return math.Hypot(a.E, a.N) }

// VectorTo converts a speed moving TO bearing deg into (east, north).
func VectorTo(speed, deg float64) Vec {
	r := deg * math.Pi / 180
	return Vec{speed * math.Sin(r), speed * math.Cos(r)}
}

// WindVector converts the public "from" wind convention into a motion vector.
func WindVector(speed, fromDeg float64) Vec { return VectorTo(speed, math.Mod(fromDeg+180, 360)) }

func Bearing(v Vec) float64 {
	return math.Mod(math.Atan2(v.E, v.N)*180/math.Pi+360, 360)
}

const radicandEps = 1e-9

var ErrCrossCurrent = errors.New("cross current cannot be countered at this STW")

// SolveTrack keeps the ground track on unit vector e at water speed stw under current c
// (spec 8.3). It returns the along-track SOG and the water-relative velocity (heading).
func SolveTrack(e Vec, stw float64, c Vec) (sogAlong float64, water Vec, err error) {
	n := Vec{-e.N, e.E}
	cPar, cCross := c.Dot(e), c.Dot(n)
	rad := stw*stw - cCross*cCross
	if rad < 0 {
		if rad < -radicandEps {
			return 0, Vec{}, ErrCrossCurrent
		}
		rad = 0
	}
	fwd := math.Sqrt(rad)
	water = Vec{fwd*e.E - cCross*n.E, fwd*e.N - cCross*n.N}
	return fwd + cPar, water, nil
}

type CurvePoint struct {
	STW     float64 `json:"stw_mps"`
	RateLPH float64 `json:"rate_lph"`
}

// FuelCurve is the piecewise linear q0(STW) table for one load class (spec 8.5).
type FuelCurve []CurvePoint

func NewFuelCurve(pts []CurvePoint) (FuelCurve, error) {
	if len(pts) == 0 {
		return nil, errors.New("fuel curve has no points")
	}
	c := append(FuelCurve(nil), pts...)
	sort.Slice(c, func(i, j int) bool { return c[i].STW < c[j].STW })
	for i, p := range c {
		if !(p.STW > 0 && p.RateLPH > 0) || math.IsInf(p.STW, 0) || math.IsInf(p.RateLPH, 0) {
			return nil, fmt.Errorf("fuel curve point %d must be positive and finite", i)
		}
		if i > 0 && p.STW == c[i-1].STW {
			return nil, fmt.Errorf("duplicate stw_mps %v in fuel curve", p.STW)
		}
	}
	return c, nil
}

// Rate interpolates L/h at stw and refuses to extrapolate outside the measured range.
func (c FuelCurve) Rate(stw float64) (float64, error) {
	if stw < c[0].STW || stw > c[len(c)-1].STW {
		return 0, fmt.Errorf("stw %.3f m/s outside fuel curve range [%.3f, %.3f]", stw, c[0].STW, c[len(c)-1].STW)
	}
	i := sort.Search(len(c), func(i int) bool { return c[i].STW >= stw })
	if c[i].STW == stw {
		return c[i].RateLPH, nil
	}
	a, b := c[i-1], c[i]
	return a.RateLPH + (b.RateLPH-a.RateLPH)*(stw-a.STW)/(b.STW-a.STW), nil
}

// Reserve is max(fixed, fraction × usable) per spec 8.7.
func Reserve(fixedL, fraction, usableL float64) float64 { return math.Max(fixedL, fraction*usableL) }
