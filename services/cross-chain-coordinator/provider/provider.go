// Package provider implements transport-only, exact-byte multi-provider
// delivery. Provider receipts are operational evidence and never execution or
// finality authority.
package provider

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"sync"
	"time"

	"golang.org/x/crypto/sha3"
)

var (
	ErrNoProvider       = errors.New("no approved provider accepted delivery")
	ErrIdentityConflict = errors.New("immutable delivery identity conflict")
)

type retryableTransportError struct {
	cause error
}

func (failure retryableTransportError) Error() string {
	return "retryable transport failure: " + failure.cause.Error()
}

func (failure retryableTransportError) Unwrap() error { return failure.cause }

func (retryableTransportError) RetryableTransport() bool { return true }

// Retryable marks a transport/outage error as safe for provider failover.
// Identity, authorization, validation, and provider response failures must not
// be wrapped and therefore fail closed at the first provider.
func Retryable(cause error) error {
	if cause == nil {
		return nil
	}
	return retryableTransportError{cause: cause}
}

func IsRetryable(err error) bool {
	var classified interface {
		RetryableTransport() bool
	}
	return errors.As(err, &classified) && classified.RetryableTransport()
}

type Delivery struct {
	MessageID    [32]byte
	RoutePolicy  [32]byte
	Envelope     []byte
	EnvelopeHash [32]byte
	SourceProof  []byte
	ProofHash    [32]byte
	AttemptedAt  time.Time
}

type Receipt struct {
	ProviderID string
	Receipt    []byte
}

type Transport interface {
	ID() string
	Submit(context.Context, Delivery) (Receipt, error)
}

type Attempt struct {
	MessageID   [32]byte
	ProviderID  string
	Number      uint32
	Success     bool
	Receipt     []byte
	AttemptedAt time.Time
	Error       string
}

type Router struct {
	mu       sync.Mutex
	approved map[[32]byte][]Transport
	payloads map[[32]byte]Delivery
	attempts map[[32]byte][]Attempt
}

func NewRouter() *Router {
	return &Router{
		approved: make(map[[32]byte][]Transport),
		payloads: make(map[[32]byte]Delivery),
		attempts: make(map[[32]byte][]Attempt),
	}
}

// RegisterRoute freezes provider order for a route-policy hash. Re-registering
// the same hash with a different provider set is rejected.
func (router *Router) RegisterRoute(routePolicy [32]byte, providers ...Transport) error {
	if routePolicy == ([32]byte{}) || len(providers) == 0 {
		return errors.New("route requires at least one provider")
	}
	seen := make(map[string]struct{}, len(providers))
	for _, candidate := range providers {
		if candidate == nil || candidate.ID() == "" {
			return errors.New("provider identity is required")
		}
		if _, exists := seen[candidate.ID()]; exists {
			return fmt.Errorf("duplicate provider %q", candidate.ID())
		}
		seen[candidate.ID()] = struct{}{}
	}
	router.mu.Lock()
	defer router.mu.Unlock()
	if existing, ok := router.approved[routePolicy]; ok {
		if !sameProviders(existing, providers) {
			return ErrIdentityConflict
		}
		return nil
	}
	router.approved[routePolicy] = append([]Transport(nil), providers...)
	return nil
}

// Deliver persists immutable bytes before submission and fails over without
// modifying the message, proof, route, or message ID.
func (router *Router) Deliver(ctx context.Context, delivery Delivery) (Receipt, error) {
	if delivery.MessageID == ([32]byte{}) ||
		delivery.RoutePolicy == ([32]byte{}) ||
		delivery.EnvelopeHash == ([32]byte{}) ||
		delivery.ProofHash == ([32]byte{}) ||
		len(delivery.Envelope) == 0 || len(delivery.SourceProof) == 0 ||
		delivery.AttemptedAt.IsZero() {
		return Receipt{}, errors.New("delivery bytes, proof, and time are required")
	}
	if contentHash(delivery.Envelope) != delivery.EnvelopeHash ||
		contentHash(delivery.SourceProof) != delivery.ProofHash {
		return Receipt{}, ErrIdentityConflict
	}
	router.mu.Lock()
	providers := append([]Transport(nil), router.approved[delivery.RoutePolicy]...)
	if len(providers) == 0 {
		router.mu.Unlock()
		return Receipt{}, ErrNoProvider
	}
	if persisted, exists := router.payloads[delivery.MessageID]; exists {
		if !sameDelivery(persisted, delivery) {
			router.mu.Unlock()
			return Receipt{}, ErrIdentityConflict
		}
	} else {
		router.payloads[delivery.MessageID] = cloneDelivery(delivery)
	}
	router.mu.Unlock()

	var failures []error
	for _, transport := range providers {
		receipt, err := transport.Submit(ctx, cloneDelivery(delivery))
		attempt := Attempt{
			MessageID:   delivery.MessageID,
			ProviderID:  transport.ID(),
			AttemptedAt: delivery.AttemptedAt,
			Success:     err == nil,
		}
		if err != nil {
			attempt.Error = err.Error()
			failure := fmt.Errorf("%s: %w", transport.ID(), err)
			failures = append(failures, failure)
		} else {
			if receipt.ProviderID != transport.ID() || len(receipt.Receipt) == 0 {
				err = ErrIdentityConflict
				attempt.Success = false
				attempt.Error = err.Error()
				failures = append(failures, fmt.Errorf("%s: %w", transport.ID(), err))
			} else {
				attempt.Receipt = append([]byte(nil), receipt.Receipt...)
			}
		}
		router.appendAttempt(delivery.MessageID, attempt)
		if err == nil {
			receipt.Receipt = append([]byte(nil), receipt.Receipt...)
			return receipt, nil
		}
		if errors.Is(err, ErrIdentityConflict) || !IsRetryable(err) {
			return Receipt{}, fmt.Errorf("%s: %w", transport.ID(), err)
		}
	}
	return Receipt{}, fmt.Errorf("%w: %v", ErrNoProvider, failures)
}

func (router *Router) Attempts(messageID [32]byte) []Attempt {
	router.mu.Lock()
	defer router.mu.Unlock()
	source := router.attempts[messageID]
	result := make([]Attempt, len(source))
	for index, attempt := range source {
		result[index] = attempt
		result[index].Receipt = append([]byte(nil), attempt.Receipt...)
	}
	return result
}

func (router *Router) appendAttempt(messageID [32]byte, attempt Attempt) {
	router.mu.Lock()
	defer router.mu.Unlock()
	attempt.Number = uint32(len(router.attempts[messageID]) + 1)
	router.attempts[messageID] = append(router.attempts[messageID], attempt)
}

func sameProviders(left, right []Transport) bool {
	if len(left) != len(right) {
		return false
	}
	for index := range left {
		if left[index].ID() != right[index].ID() {
			return false
		}
	}
	return true
}

func sameDelivery(left, right Delivery) bool {
	return left.MessageID == right.MessageID &&
		left.RoutePolicy == right.RoutePolicy &&
		left.EnvelopeHash == right.EnvelopeHash &&
		left.ProofHash == right.ProofHash &&
		bytes.Equal(left.Envelope, right.Envelope) &&
		bytes.Equal(left.SourceProof, right.SourceProof)
}

func cloneDelivery(source Delivery) Delivery {
	source.Envelope = append([]byte(nil), source.Envelope...)
	source.SourceProof = append([]byte(nil), source.SourceProof...)
	return source
}

func contentHash(value []byte) [32]byte {
	hasher := sha3.NewLegacyKeccak256()
	_, _ = hasher.Write(value)
	var result [32]byte
	hasher.Sum(result[:0])
	return result
}
