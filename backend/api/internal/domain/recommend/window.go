package recommend

import "nelayan-route/internal/domain/weather"

// riskRank orders weather risk; unknown (missing data) is worse than medium but better than high.
var riskRank = map[string]int{"low": 0, "medium": 1, "unknown": 2, "high": 3}

// WorstRisk is the highest risk among hours ("unknown" for an empty slice).
func WorstRisk(hours []weather.Hour) string {
	worst := ""
	for _, h := range hours {
		if worst == "" || riskRank[h.Risk] > riskRank[worst] {
			worst = h.Risk
		}
	}
	if worst == "" {
		return "unknown"
	}
	return worst
}

// BestWindow picks the start offset whose window hours[start : start+length] has the lowest worst risk,
// earliest on ties (AGENTS.md 10.4: departure with the lowest weather risk). Starts are limited to
// 0..maxStart. ok is false when no full window fits; hours must already carry Risk (weather.Enrich).
func BestWindow(hours []weather.Hour, length, maxStart int) (start int, risk string, ok bool) {
	best := -1
	for s := 0; s <= maxStart && s+length <= len(hours); s++ {
		r := WorstRisk(hours[s : s+length])
		if best < 0 || riskRank[r] < riskRank[risk] {
			best, risk = s, r
		}
	}
	return best, risk, best >= 0
}
