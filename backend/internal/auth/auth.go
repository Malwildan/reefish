// Package auth carries the caller's bearer token from delivery to data adapters via context.
package auth

import "context"

type tokenKey struct{}

func WithToken(ctx context.Context, token string) context.Context {
	return context.WithValue(ctx, tokenKey{}, token)
}

func Token(ctx context.Context) string {
	t, _ := ctx.Value(tokenKey{}).(string)
	return t
}
