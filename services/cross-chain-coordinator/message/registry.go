package message

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"sync"
	"time"

	unifiedv1 "github.com/unified-finance/unified/packages/generated/go/unified/v1"
)

var (
	ErrNonceConflict  = errors.New("lane nonce was reused with changed content")
	ErrOutOfOrder     = errors.New("message arrived out of lane order")
	ErrMessageExpired = errors.New("message expired")
	ErrInvalidState   = errors.New("invalid message state transition")
)

type Handler func(context.Context, *unifiedv1.CrossChainMessageEnvelope) ([]byte, error)

type Execution struct {
	MessageID []byte
	State     unifiedv1.CrossChainMessageState
	Result    []byte
	Replay    bool
	Version   uint64
}

type record struct {
	envelope []byte
	state    unifiedv1.CrossChainMessageState
	result   []byte
	version  uint64
}

// Registry is an in-memory reference kernel for the same compare-and-set and
// at-most-once properties enforced by the coordinator contract and SQL store.
type Registry struct {
	mu        sync.Mutex
	byMessage map[string]*record
	byNonce   map[string]string
	nextNonce map[string]uint64
	now       func() time.Time
}

func NewRegistry() *Registry {
	return NewRegistryWithClock(func() time.Time { return time.Now().UTC() })
}

func NewRegistryWithClock(now func() time.Time) *Registry {
	if now == nil {
		panic("message registry clock is required")
	}
	return &Registry{
		byMessage: make(map[string]*record),
		byNonce:   make(map[string]string),
		nextNonce: make(map[string]uint64),
		now:       now,
	}
}

func (registry *Registry) Execute(
	ctx context.Context,
	envelope *unifiedv1.CrossChainMessageEnvelope,
	handler Handler,
) (Execution, error) {
	if err := ValidateEnvelope(envelope); err != nil {
		return Execution{}, err
	}
	if handler == nil {
		return Execution{}, errors.New("nil execution handler")
	}
	serialized, err := DeterministicBytes(envelope)
	if err != nil {
		return Execution{}, err
	}
	messageKey := string(envelope.GetMessageId())
	laneKey := string(envelope.GetLaneId())
	nonceKey := fmt.Sprintf("%x:%d", envelope.GetLaneId(), envelope.GetSourceNonce())

	registry.mu.Lock()
	defer registry.mu.Unlock()

	if existing, ok := registry.byMessage[messageKey]; ok {
		if !bytes.Equal(existing.envelope, serialized) {
			return Execution{}, ErrDigestMismatch
		}
		if existing.state == unifiedv1.CrossChainMessageState_CROSS_CHAIN_MESSAGE_STATE_EXECUTED {
			return toExecution(envelope.GetMessageId(), existing, true), nil
		}
		if existing.state == unifiedv1.CrossChainMessageState_CROSS_CHAIN_MESSAGE_STATE_EXPIRED {
			return toExecution(envelope.GetMessageId(), existing, true), ErrMessageExpired
		}
	}
	if existingMessage, ok := registry.byNonce[nonceKey]; ok && existingMessage != messageKey {
		return Execution{}, ErrNonceConflict
	}
	next := registry.nextNonce[laneKey]
	if next == 0 {
		next = 1
	}
	if envelope.GetSourceNonce() > next {
		return Execution{}, ErrOutOfOrder
	}
	if envelope.GetSourceNonce() < next {
		return Execution{}, ErrNonceConflict
	}

	current := registry.byMessage[messageKey]
	if !registry.now().Before(envelope.GetExpiresAt().AsTime()) &&
		!IsReportAction(envelope.GetActionType()) {
		if current == nil {
			current = &record{
				envelope: append([]byte(nil), serialized...),
				state:    unifiedv1.CrossChainMessageState_CROSS_CHAIN_MESSAGE_STATE_EXPIRED,
				version:  1,
			}
			registry.byMessage[messageKey] = current
			registry.byNonce[nonceKey] = messageKey
		} else {
			current.state = unifiedv1.CrossChainMessageState_CROSS_CHAIN_MESSAGE_STATE_EXPIRED
			current.version++
		}
		return toExecution(envelope.GetMessageId(), current, false), ErrMessageExpired
	}
	if current == nil {
		current = &record{
			envelope: append([]byte(nil), serialized...),
			state:    unifiedv1.CrossChainMessageState_CROSS_CHAIN_MESSAGE_STATE_VERIFIED,
			version:  1,
		}
		registry.byMessage[messageKey] = current
		registry.byNonce[nonceKey] = messageKey
	}
	result, executionErr := handler(ctx, envelope)
	if executionErr != nil {
		current.state = unifiedv1.CrossChainMessageState_CROSS_CHAIN_MESSAGE_STATE_FAILED
		current.version++
		return toExecution(envelope.GetMessageId(), current, false), executionErr
	}
	current.result = append([]byte(nil), result...)
	current.state = unifiedv1.CrossChainMessageState_CROSS_CHAIN_MESSAGE_STATE_EXECUTED
	current.version++
	registry.nextNonce[laneKey] = next + 1
	return toExecution(envelope.GetMessageId(), current, false), nil
}

// IsReportAction mirrors CrossChainTypes.isReportAction. These actions attest
// effects that already finalized on their source chain, so transport expiry
// must not prevent their authenticated ingestion.
func IsReportAction(action unifiedv1.CrossChainActionType) bool {
	switch action {
	case unifiedv1.CrossChainActionType_CROSS_CHAIN_ACTION_TYPE_WRAPPED_UFT_MINTED_V1,
		unifiedv1.CrossChainActionType_CROSS_CHAIN_ACTION_TYPE_SATELLITE_COLLATERAL_LOCKED_V1,
		unifiedv1.CrossChainActionType_CROSS_CHAIN_ACTION_TYPE_SATELLITE_DISBURSEMENT_SETTLED_V1,
		unifiedv1.CrossChainActionType_CROSS_CHAIN_ACTION_TYPE_SATELLITE_COLLATERAL_RELEASED_V1:
		return true
	default:
		return false
	}
}

func (registry *Registry) Get(messageID []byte) (Execution, bool) {
	registry.mu.Lock()
	defer registry.mu.Unlock()
	current, ok := registry.byMessage[string(messageID)]
	if !ok {
		return Execution{}, false
	}
	return toExecution(messageID, current, true), true
}

func toExecution(messageID []byte, current *record, replay bool) Execution {
	return Execution{
		MessageID: append([]byte(nil), messageID...),
		State:     current.state,
		Result:    append([]byte(nil), current.result...),
		Replay:    replay,
		Version:   current.version,
	}
}

// CanTransition is the canonical transition policy shared by stores.
func CanTransition(
	from unifiedv1.CrossChainMessageState,
	to unifiedv1.CrossChainMessageState,
	retryable bool,
) bool {
	const (
		created               = unifiedv1.CrossChainMessageState_CROSS_CHAIN_MESSAGE_STATE_CREATED
		sourceFinalizing      = unifiedv1.CrossChainMessageState_CROSS_CHAIN_MESSAGE_STATE_SOURCE_FINALIZING
		sourceFinal           = unifiedv1.CrossChainMessageState_CROSS_CHAIN_MESSAGE_STATE_SOURCE_FINAL
		sent                  = unifiedv1.CrossChainMessageState_CROSS_CHAIN_MESSAGE_STATE_SENT
		relayed               = unifiedv1.CrossChainMessageState_CROSS_CHAIN_MESSAGE_STATE_RELAYED
		verified              = unifiedv1.CrossChainMessageState_CROSS_CHAIN_MESSAGE_STATE_VERIFIED
		executed              = unifiedv1.CrossChainMessageState_CROSS_CHAIN_MESSAGE_STATE_EXECUTED
		ackPending            = unifiedv1.CrossChainMessageState_CROSS_CHAIN_MESSAGE_STATE_ACK_PENDING
		acknowledged          = unifiedv1.CrossChainMessageState_CROSS_CHAIN_MESSAGE_STATE_ACKNOWLEDGED
		rejected              = unifiedv1.CrossChainMessageState_CROSS_CHAIN_MESSAGE_STATE_REJECTED
		failed                = unifiedv1.CrossChainMessageState_CROSS_CHAIN_MESSAGE_STATE_FAILED
		expired               = unifiedv1.CrossChainMessageState_CROSS_CHAIN_MESSAGE_STATE_EXPIRED
		recoveryPending       = unifiedv1.CrossChainMessageState_CROSS_CHAIN_MESSAGE_STATE_RECOVERY_PENDING
		destinationTombstoned = unifiedv1.CrossChainMessageState_CROSS_CHAIN_MESSAGE_STATE_DESTINATION_TOMBSTONED
		sourceCompensated     = unifiedv1.CrossChainMessageState_CROSS_CHAIN_MESSAGE_STATE_SOURCE_COMPENSATED
		recovered             = unifiedv1.CrossChainMessageState_CROSS_CHAIN_MESSAGE_STATE_RECOVERED
		disputed              = unifiedv1.CrossChainMessageState_CROSS_CHAIN_MESSAGE_STATE_DISPUTED
	)
	allowed := map[unifiedv1.CrossChainMessageState][]unifiedv1.CrossChainMessageState{
		created:               {sourceFinalizing},
		sourceFinalizing:      {sourceFinal, expired, disputed},
		sourceFinal:           {sent, disputed},
		sent:                  {relayed, failed, rejected, expired, disputed},
		relayed:               {verified, failed, rejected, expired, disputed},
		verified:              {executed, failed, rejected, disputed},
		executed:              {ackPending, disputed},
		ackPending:            {acknowledged, disputed},
		rejected:              {recoveryPending, disputed},
		expired:               {recoveryPending, disputed},
		recoveryPending:       {destinationTombstoned, disputed},
		destinationTombstoned: {sourceCompensated, disputed},
		sourceCompensated:     {recovered, disputed},
	}
	if from == failed {
		if retryable && to == sent {
			return true
		}
		return to == recoveryPending || to == disputed
	}
	for _, candidate := range allowed[from] {
		if candidate == to {
			return true
		}
	}
	return false
}
