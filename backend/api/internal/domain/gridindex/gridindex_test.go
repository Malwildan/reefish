package gridindex

import (
	"encoding/json"
	"math"
	"os"
	"testing"
)

type vector struct {
	Label    string  `json:"label"`
	Lon      float64 `json:"lon"`
	Lat      float64 `json:"lat"`
	Easting  float64 `json:"easting"`
	Northing float64 `json:"northing"`
	GridX    int     `json:"grid_x"`
	GridY    int     `json:"grid_y"`
	InPilot  bool    `json:"in_pilot_range"`
	GridID   *string `json:"grid_id"`
	CellID   string  `json:"cell_id"`
}

func loadVectors(t *testing.T) ([]vector, map[string]float64) {
	t.Helper()
	b, err := os.ReadFile("../../../../../contracts/fixtures/grid-index-vectors.json")
	if err != nil {
		t.Fatal(err)
	}
	var f struct {
		Tolerance map[string]float64 `json:"tolerance"`
		Vectors   []vector           `json:"vectors"`
	}
	if err := json.Unmarshal(b, &f); err != nil {
		t.Fatal(err)
	}
	return f.Vectors, f.Tolerance
}

func TestVectors(t *testing.T) {
	vs, tol := loadVectors(t)
	if len(vs) < 10 {
		t.Fatalf("only %d vectors", len(vs))
	}
	for _, v := range vs {
		// projection both ways against PostGIS
		e, n := ToUTM(v.Lat, v.Lon)
		if math.Abs(e-v.Easting) > tol["utm_m"] || math.Abs(n-v.Northing) > tol["utm_m"] {
			t.Errorf("%s: ToUTM = %.4f, %.4f want %.4f, %.4f", v.Label, e, n, v.Easting, v.Northing)
		}
		lat, lon := ToLatLon(v.Easting, v.Northing)
		if math.Abs(lat-v.Lat) > tol["lonlat_deg"] || math.Abs(lon-v.Lon) > tol["lonlat_deg"] {
			t.Errorf("%s: ToLatLon = %.9f, %.9f want %.9f, %.9f", v.Label, lat, lon, v.Lat, v.Lon)
		}

		// indexing uses the exact UTM coordinates of the vector (edges are decided in metres)
		c := FromUTM(v.Easting, v.Northing)
		if c.X != v.GridX || c.Y != v.GridY || c.InPilot() != v.InPilot || c.Canonical() != v.CellID {
			t.Errorf("%s: cell %+v %s in=%v, want %d,%d %s in=%v", v.Label, c, c.Canonical(), c.InPilot(), v.GridX, v.GridY, v.CellID, v.InPilot)
		}
		if v.GridID != nil && c.ID() != *v.GridID {
			t.Errorf("%s: id %s want %s", v.Label, c.ID(), *v.GridID)
		}
		if p, err := ParseCanonical(v.CellID); err != nil || p != c {
			t.Errorf("%s: ParseCanonical(%s) = %+v, %v", v.Label, v.CellID, p, err)
		}
	}
}

func TestParse(t *testing.T) {
	c, err := ParseXY("X149_Y001")
	if err != nil || c != (Cell{149, 1}) || c.Canonical() != "tp-id-utm49s-500m:v2:rp17976:cp1423" {
		t.Fatalf("%+v %v", c, err)
	}
	for _, bad := range []string{"X149_Y1", "x149_Y001", "X149_Y001x", ""} {
		if _, err := ParseXY(bad); err == nil {
			t.Errorf("ParseXY(%q) accepted", bad)
		}
	}
	for _, bad := range []string{"tp-id-utm49s-500m:v2:rp017976:cp1423", "tp-id-utm49s-500m:v1:rp17976:cp1423", "tp-id-utm49s-500m:v2:rp17976:cp1423:x"} {
		if _, err := ParseCanonical(bad); err == nil {
			t.Errorf("ParseCanonical(%q) accepted", bad)
		}
	}
	if e, n := (Cell{149, 1}).Center(); e != 711750 || n != 8988250 {
		t.Errorf("centre %v %v", e, n)
	}
}
