package supabase

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"

	"nelayan-route/internal/usecase/nelayan"
)

// postgrestError is PostgREST's error body. api_* RPCs raise P0001 with message = API code,
// hint = user-facing message, detail = JSON details (migration 20261016100500_nelayan private.fail).
type postgrestError struct {
	Code    string `json:"code"`
	Message string `json:"message"`
	Details string `json:"details"`
	Hint    string `json:"hint"`
}

// Call implements nelayan.Store.
func (c *Client) Call(ctx context.Context, fn string, args any) (json.RawMessage, error) {
	if args == nil {
		args = struct{}{}
	}
	body, err := json.Marshal(args)
	if err != nil {
		return nil, err
	}
	status, res, err := c.send(ctx, http.MethodPost, "/rest/v1/rpc/"+fn, bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	if status == http.StatusOK {
		return res, nil
	}
	var pe postgrestError
	_ = json.Unmarshal(res, &pe)
	switch {
	case pe.Code == "P0001":
		e := &nelayan.Error{Code: pe.Message, Message: pe.Hint}
		if e.Message == "" {
			e.Message = pe.Message
		}
		var details any
		if pe.Details != "" && json.Unmarshal([]byte(pe.Details), &details) == nil {
			e.Details = details
		}
		return nil, e
	case status == http.StatusUnauthorized || pe.Code == "PGRST301" || pe.Code == "PGRST303":
		return nil, &nelayan.Error{Code: "UNAUTHORIZED", Message: "Silakan login ulang"}
	}
	return nil, fmt.Errorf("supabase rpc %s: HTTP %d: %.300s", fn, status, res)
}
