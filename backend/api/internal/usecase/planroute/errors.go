package planroute

import (
	"errors"
	"fmt"
)

// Kind classifies an error; the delivery layer maps it to a transport status.
type Kind int

const (
	KindInvalid         Kind = iota // request cannot be planned as given
	KindUnauthenticated             // caller identity rejected by the data source
	KindUnavailable                 // a dependency failed; retrying may help
)

// ErrUnauthenticated is wrapped by adapters when the data source rejects the caller.
// Any other dependency error is treated as unavailable.
var ErrUnauthenticated = errors.New("unauthenticated")

// Error is the spec 12.8 error body.
type Error struct {
	Kind    Kind   `json:"-"`
	Code    string `json:"code"`
	Message string `json:"message"`
	Details any    `json:"details,omitempty"`
	cause   error
}

func (e *Error) Error() string { return e.Code + ": " + e.Message }
func (e *Error) Unwrap() error { return e.cause }

func invalid(code, format string, a ...any) *Error {
	return &Error{Kind: KindInvalid, Code: code, Message: fmt.Sprintf(format, a...)}
}
