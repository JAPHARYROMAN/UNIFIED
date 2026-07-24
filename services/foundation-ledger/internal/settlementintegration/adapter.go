// Package settlementintegration translates the payment coordinator's finalized
// projection into the foundation ledger's accounting-safe input.
package settlementintegration

import (
	"errors"

	"github.com/unified-finance/unified/services/foundation-ledger/internal/settlementaccounting"
	"github.com/unified-finance/unified/services/payment-orchestrator/settlement"
)

var ErrInvalidConfirmation = errors.New("invalid settlement integration confirmation")

// AdaptConfirmation preserves the coordinator's instruction and chain identity while
// requiring the durable canonicalization and conversion records owned by the ledger.
func AdaptConfirmation(
	authority settlementaccounting.DurableConfirmationAuthority,
	input settlement.Confirmation,
) (settlementaccounting.VerifiedConfirmation, error) {
	verified, err := settlementaccounting.VerifyConfirmation(
		authority,
		input,
	)
	if err != nil {
		return settlementaccounting.VerifiedConfirmation{},
			errors.Join(ErrInvalidConfirmation, err)
	}
	return verified, nil
}

// AdaptVerifiedReorg is the only ledger integration entry point for reorganization
// compensation. The opaque authority can only be minted by the coordinator
// after its durable incident transition commits.
func AdaptVerifiedReorg(
	metadata settlementaccounting.ReorgMetadata,
	confirmation settlement.Confirmation,
	authority settlement.DurableReorgAuthority,
) (settlementaccounting.VerifiedReorg, error) {
	return settlementaccounting.VerifyReorg(metadata, confirmation, authority)
}
