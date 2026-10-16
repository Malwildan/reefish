package supabase

import "testing"

func TestParseOutlinesSplitsMultiPolygon(t *testing.T) {
	b := []byte(`[{"type":"MultiPolygon","coordinates":[
		[[[112.6,-8.5],[112.7,-8.5],[112.7,-8.4],[112.6,-8.5]]],
		[[[112.8,-8.5],[112.9,-8.5],[112.9,-8.4],[112.8,-8.5]],[[112.85,-8.48],[112.86,-8.48],[112.86,-8.47],[112.85,-8.48]]]
	]}]`)
	polys, err := parseOutlines(b)
	if err != nil {
		t.Fatal(err)
	}
	if len(polys) != 2 || len(polys[0].Rings) != 1 || len(polys[1].Rings) != 2 {
		t.Fatalf("got %d polygons: %+v", len(polys), polys)
	}
	if p := polys[1].Rings[0][1]; p.Lon != 112.9 || p.Lat != -8.5 {
		t.Errorf("lon/lat order: %+v", p)
	}
}

func TestParseOutlinesEmpty(t *testing.T) {
	polys, err := parseOutlines([]byte(`[]`))
	if err != nil || len(polys) != 0 {
		t.Fatalf("%v %v", polys, err)
	}
}
