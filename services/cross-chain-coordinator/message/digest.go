// Package message implements the canonical Phase 8 message identity and
// at-most-once destination execution boundary.
package message

import (
	"bytes"
	"encoding/binary"
	"errors"
	"fmt"
	"math/big"

	unifiedv1 "github.com/unified-finance/unified/packages/generated/go/unified/v1"
	"golang.org/x/crypto/sha3"
	"google.golang.org/protobuf/proto"
)

const domainTag = "UNIFIED_XCHAIN_MESSAGE_V1"

var (
	ErrInvalidEnvelope = errors.New("invalid cross-chain envelope")
	ErrDigestMismatch  = errors.New("cross-chain message id mismatch")
)

// ComputeMessageID returns keccak256(abi.encode(preimage)). The message_id
// field is deliberately excluded from the preimage.
func ComputeMessageID(envelope *unifiedv1.CrossChainMessageEnvelope) ([32]byte, error) {
	var zero [32]byte
	if err := validateEnvelope(envelope, false); err != nil {
		return zero, err
	}

	sourceChain, err := uint256(envelope.GetSourceChainId(), "source_chain_id")
	if err != nil {
		return zero, err
	}
	destinationChain, err := uint256(envelope.GetDestinationChainId(), "destination_chain_id")
	if err != nil {
		return zero, err
	}

	const argumentCount = 23
	head := make([]byte, 0, argumentCount*32)
	head = append(head, uintWord(uint64(argumentCount*32))...)
	head = append(head, uintWord(uint64(envelope.GetSchemaVersion()))...)
	head = append(head, envelope.GetProtocolId()...)
	head = append(head, sourceChain...)
	head = append(head, addressWord(envelope.GetSourceCoordinator())...)
	head = append(head, addressWord(envelope.GetSourceComponent())...)
	head = append(head, destinationChain...)
	head = append(head, addressWord(envelope.GetDestinationCoordinator())...)
	head = append(head, addressWord(envelope.GetDestinationComponent())...)
	head = append(head, envelope.GetLaneId()...)
	head = append(head, uintWord(envelope.GetSourceNonce())...)
	head = append(head, envelope.GetAggregateId()...)
	head = append(head, uintWord(uint64(envelope.GetActionType()))...)
	head = append(head, envelope.GetPayloadHash()...)
	head = append(head, uintWord(uint64(envelope.GetCreatedAt().GetSeconds()))...)
	head = append(head, uintWord(uint64(envelope.GetExpiresAt().GetSeconds()))...)
	head = append(head, envelope.GetRoutePolicyHash()...)
	head = append(head, envelope.GetAdapterSetPolicyHash()...)
	head = append(head, envelope.GetSourceFinalityPolicyHash()...)
	head = append(head, envelope.GetDestinationFinalityPolicyHash()...)
	head = append(head, envelope.GetCorrelationId()...)
	head = append(head, envelope.GetCausationMessageId()...)
	head = append(head, envelope.GetSupersededMessageId()...)

	tag := []byte(domainTag)
	tail := append(uintWord(uint64(len(tag))), tag...)
	if remainder := len(tail) % 32; remainder != 0 {
		tail = append(tail, make([]byte, 32-remainder)...)
	}
	return keccak(append(head, tail...)), nil
}

// ValidateEnvelope checks the exact digest, typed-payload commitment, domains,
// fixed-width identifiers, and validity interval.
func ValidateEnvelope(envelope *unifiedv1.CrossChainMessageEnvelope) error {
	if err := validateEnvelope(envelope, true); err != nil {
		return err
	}
	expected, err := ComputeMessageID(envelope)
	if err != nil {
		return err
	}
	if !bytes.Equal(envelope.GetMessageId(), expected[:]) {
		return ErrDigestMismatch
	}
	return nil
}

// Seal clones an envelope and sets its canonical message ID.
func Seal(envelope *unifiedv1.CrossChainMessageEnvelope) (*unifiedv1.CrossChainMessageEnvelope, error) {
	if envelope == nil {
		return nil, fmt.Errorf("%w: nil", ErrInvalidEnvelope)
	}
	sealed := proto.Clone(envelope).(*unifiedv1.CrossChainMessageEnvelope)
	sealed.MessageId = nil
	id, err := ComputeMessageID(sealed)
	if err != nil {
		return nil, err
	}
	sealed.MessageId = append([]byte(nil), id[:]...)
	return sealed, nil
}

// DeterministicBytes returns the exact immutable bytes persisted before any
// provider attempt.
func DeterministicBytes(envelope *unifiedv1.CrossChainMessageEnvelope) ([]byte, error) {
	if err := ValidateEnvelope(envelope); err != nil {
		return nil, err
	}
	return proto.MarshalOptions{Deterministic: true}.Marshal(envelope)
}

func validateEnvelope(envelope *unifiedv1.CrossChainMessageEnvelope, requireID bool) error {
	if envelope == nil {
		return fmt.Errorf("%w: nil", ErrInvalidEnvelope)
	}
	if envelope.GetSchemaVersion() == 0 ||
		envelope.GetSourceNonce() == 0 ||
		envelope.GetActionType() == unifiedv1.CrossChainActionType_CROSS_CHAIN_ACTION_TYPE_UNSPECIFIED {
		return fmt.Errorf("%w: schema, nonce, and action are required", ErrInvalidEnvelope)
	}
	if requireID {
		if err := exactLength(envelope.GetMessageId(), 32, "message_id"); err != nil {
			return err
		}
	} else if len(envelope.GetMessageId()) != 0 && len(envelope.GetMessageId()) != 32 {
		return fmt.Errorf("%w: message_id must be empty or 32 bytes", ErrInvalidEnvelope)
	}
	for name, value := range map[string][]byte{
		"protocol_id":                      envelope.GetProtocolId(),
		"lane_id":                          envelope.GetLaneId(),
		"aggregate_id":                     envelope.GetAggregateId(),
		"payload_hash":                     envelope.GetPayloadHash(),
		"route_policy_hash":                envelope.GetRoutePolicyHash(),
		"adapter_set_policy_hash":          envelope.GetAdapterSetPolicyHash(),
		"source_finality_policy_hash":      envelope.GetSourceFinalityPolicyHash(),
		"destination_finality_policy_hash": envelope.GetDestinationFinalityPolicyHash(),
		"correlation_id":                   envelope.GetCorrelationId(),
		"causation_message_id":             envelope.GetCausationMessageId(),
		"superseded_message_id":            envelope.GetSupersededMessageId(),
	} {
		if err := exactLength(value, 32, name); err != nil {
			return err
		}
	}
	for name, value := range map[string][]byte{
		"source_coordinator":      envelope.GetSourceCoordinator(),
		"source_component":        envelope.GetSourceComponent(),
		"destination_coordinator": envelope.GetDestinationCoordinator(),
		"destination_component":   envelope.GetDestinationComponent(),
	} {
		if err := exactLength(value, 20, name); err != nil {
			return err
		}
	}
	if _, err := uint256(envelope.GetSourceChainId(), "source_chain_id"); err != nil {
		return err
	}
	if _, err := uint256(envelope.GetDestinationChainId(), "destination_chain_id"); err != nil {
		return err
	}
	if envelope.GetCreatedAt() == nil || envelope.GetExpiresAt() == nil ||
		envelope.GetCreatedAt().GetNanos() != 0 || envelope.GetExpiresAt().GetNanos() != 0 ||
		envelope.GetCreatedAt().GetSeconds() < 0 ||
		envelope.GetExpiresAt().GetSeconds() <= envelope.GetCreatedAt().GetSeconds() {
		return fmt.Errorf("%w: timestamps must be whole nonnegative seconds with expiry after creation", ErrInvalidEnvelope)
	}
	encodedPayload, err := EncodeTypedActionABI(envelope)
	if err != nil {
		return err
	}
	if !bytes.Equal(encodedPayload, envelope.GetTypedActionPayload()) {
		return fmt.Errorf("%w: typed_action_payload is not the canonical ABI encoding", ErrInvalidEnvelope)
	}
	payloadHash := keccak(encodedPayload)
	if !bytes.Equal(payloadHash[:], envelope.GetPayloadHash()) {
		return fmt.Errorf("%w: typed payload hash mismatch", ErrInvalidEnvelope)
	}
	return nil
}

// EncodeTypedActionABI independently reconstructs the exact Solidity
// abi.encode(struct) bytes for the frozen Phase 8 economic action table.
// Reserved recovery/governance ordinals are intentionally not accepted as
// economic envelope payloads until their Solidity ABI is frozen.
func EncodeTypedActionABI(
	envelope *unifiedv1.CrossChainMessageEnvelope,
) ([]byte, error) {
	if envelope == nil {
		return nil, fmt.Errorf("%w: nil", ErrInvalidEnvelope)
	}
	switch envelope.GetActionType() {
	case unifiedv1.CrossChainActionType_CROSS_CHAIN_ACTION_TYPE_CANONICAL_UFT_LOCKED_V1:
		action, ok := envelope.GetTypedAction().(*unifiedv1.CrossChainMessageEnvelope_CanonicalUftLock)
		if !ok {
			return nil, actionMismatch()
		}
		return encodeStatic(
			bytes32ABI(action.CanonicalUftLock.GetLockId(), "lock_id"),
			bytes32ABI(action.CanonicalUftLock.GetLoanId(), "loan_id"),
			addressABI(action.CanonicalUftLock.GetCanonicalToken(), "canonical_token"),
			addressABI(action.CanonicalUftLock.GetHomeBridgeHub(), "home_bridge_hub"),
			addressABI(action.CanonicalUftLock.GetWrappedToken(), "wrapped_token"),
			addressABI(action.CanonicalUftLock.GetDestinationRecipient(), "destination_recipient"),
			uint256ABI(action.CanonicalUftLock.GetAmount(), "amount"),
		)
	case unifiedv1.CrossChainActionType_CROSS_CHAIN_ACTION_TYPE_WRAPPED_UFT_MINTED_V1:
		action, ok := envelope.GetTypedAction().(*unifiedv1.CrossChainMessageEnvelope_WrappedUftMinted)
		if !ok {
			return nil, actionMismatch()
		}
		return encodeStatic(
			bytes32ABI(action.WrappedUftMinted.GetLoanId(), "loan_id"),
			bytes32ABI(action.WrappedUftMinted.GetLockId(), "lock_id"),
			addressABI(action.WrappedUftMinted.GetHomeLoanAccount(), "home_loan_account"),
			addressABI(action.WrappedUftMinted.GetBorrower(), "borrower"),
			addressABI(action.WrappedUftMinted.GetLender(), "lender"),
			addressABI(action.WrappedUftMinted.GetWrappedToken(), "wrapped_token"),
			uint256ABI(action.WrappedUftMinted.GetAmount(), "amount"),
			bytes32ABI(action.WrappedUftMinted.GetPolicyHash(), "policy_hash"),
		)
	case unifiedv1.CrossChainActionType_CROSS_CHAIN_ACTION_TYPE_WRAPPED_UFT_BURNED_V1:
		action, ok := envelope.GetTypedAction().(*unifiedv1.CrossChainMessageEnvelope_WrappedUftBurned)
		if !ok {
			return nil, actionMismatch()
		}
		return encodeStatic(
			bytes32ABI(action.WrappedUftBurned.GetBurnId(), "burn_id"),
			bytes32ABI(action.WrappedUftBurned.GetBackingRoutePolicyHash(), "backing_route_policy_hash"),
			addressABI(action.WrappedUftBurned.GetCanonicalToken(), "canonical_token"),
			addressABI(action.WrappedUftBurned.GetHomeBridgeHub(), "home_bridge_hub"),
			addressABI(action.WrappedUftBurned.GetWrappedToken(), "wrapped_token"),
			addressABI(action.WrappedUftBurned.GetRecipient(), "recipient"),
			uint256ABI(action.WrappedUftBurned.GetAmount(), "amount"),
		)
	case unifiedv1.CrossChainActionType_CROSS_CHAIN_ACTION_TYPE_CANONICAL_UFT_RELEASED_V1:
		action, ok := envelope.GetTypedAction().(*unifiedv1.CrossChainMessageEnvelope_CanonicalUftReleased)
		if !ok {
			return nil, actionMismatch()
		}
		return encodeStatic(
			bytes32ABI(action.CanonicalUftReleased.GetBurnId(), "burn_id"),
			addressABI(action.CanonicalUftReleased.GetCanonicalToken(), "canonical_token"),
			addressABI(action.CanonicalUftReleased.GetRecipient(), "recipient"),
			uint256ABI(action.CanonicalUftReleased.GetAmount(), "amount"),
			bytes32ABI(action.CanonicalUftReleased.GetWrappedBurnMessageId(), "wrapped_burn_message_id"),
		)
	case unifiedv1.CrossChainActionType_CROSS_CHAIN_ACTION_TYPE_SATELLITE_COLLATERAL_LOCKED_V1:
		action, ok := envelope.GetTypedAction().(*unifiedv1.CrossChainMessageEnvelope_SatelliteCollateralLocked)
		if !ok {
			return nil, actionMismatch()
		}
		return encodeLoanAction(
			action.SatelliteCollateralLocked.GetLoanId(),
			action.SatelliteCollateralLocked.GetCollateralId(),
			action.SatelliteCollateralLocked.GetHomeLoanAccount(),
			action.SatelliteCollateralLocked.GetBorrower(),
			action.SatelliteCollateralLocked.GetLender(),
			action.SatelliteCollateralLocked.GetCollateralToken(),
			action.SatelliteCollateralLocked.GetAmount(),
			action.SatelliteCollateralLocked.GetPolicyHash(),
			"collateral_id", "collateral_token",
		)
	case unifiedv1.CrossChainActionType_CROSS_CHAIN_ACTION_TYPE_HOME_DISBURSEMENT_AUTHORIZED_V1:
		action, ok := envelope.GetTypedAction().(*unifiedv1.CrossChainMessageEnvelope_HomeDisbursementAuthorized)
		if !ok {
			return nil, actionMismatch()
		}
		return encodeLoanAction(
			action.HomeDisbursementAuthorized.GetLoanId(),
			action.HomeDisbursementAuthorized.GetFundingLockId(),
			action.HomeDisbursementAuthorized.GetHomeLoanAccount(),
			action.HomeDisbursementAuthorized.GetBorrower(),
			action.HomeDisbursementAuthorized.GetLender(),
			action.HomeDisbursementAuthorized.GetWrappedToken(),
			action.HomeDisbursementAuthorized.GetAmount(),
			action.HomeDisbursementAuthorized.GetPolicyHash(),
			"funding_lock_id", "wrapped_token",
		)
	case unifiedv1.CrossChainActionType_CROSS_CHAIN_ACTION_TYPE_SATELLITE_DISBURSEMENT_SETTLED_V1:
		action, ok := envelope.GetTypedAction().(*unifiedv1.CrossChainMessageEnvelope_SatelliteDisbursementSettled)
		if !ok {
			return nil, actionMismatch()
		}
		return encodeLoanAction(
			action.SatelliteDisbursementSettled.GetLoanId(),
			action.SatelliteDisbursementSettled.GetFundingLockId(),
			action.SatelliteDisbursementSettled.GetHomeLoanAccount(),
			action.SatelliteDisbursementSettled.GetBorrower(),
			action.SatelliteDisbursementSettled.GetLender(),
			action.SatelliteDisbursementSettled.GetWrappedToken(),
			action.SatelliteDisbursementSettled.GetAmount(),
			action.SatelliteDisbursementSettled.GetPolicyHash(),
			"funding_lock_id", "wrapped_token",
		)
	case unifiedv1.CrossChainActionType_CROSS_CHAIN_ACTION_TYPE_SATELLITE_REPAYMENT_BURNED_V1:
		action, ok := envelope.GetTypedAction().(*unifiedv1.CrossChainMessageEnvelope_SatelliteRepaymentBurned)
		if !ok {
			return nil, actionMismatch()
		}
		return encodeStatic(
			bytes32ABI(action.SatelliteRepaymentBurned.GetBurnId(), "burn_id"),
			bytes32ABI(action.SatelliteRepaymentBurned.GetLoanId(), "loan_id"),
			bytes32ABI(action.SatelliteRepaymentBurned.GetPaymentId(), "payment_id"),
			bytes32ABI(action.SatelliteRepaymentBurned.GetBackingRoutePolicyHash(), "backing_route_policy_hash"),
			addressABI(action.SatelliteRepaymentBurned.GetCanonicalToken(), "canonical_token"),
			addressABI(action.SatelliteRepaymentBurned.GetHomeBridgeHub(), "home_bridge_hub"),
			addressABI(action.SatelliteRepaymentBurned.GetWrappedToken(), "wrapped_token"),
			addressABI(action.SatelliteRepaymentBurned.GetLender(), "lender"),
			uint256ABI(action.SatelliteRepaymentBurned.GetAmount(), "amount"),
		)
	case unifiedv1.CrossChainActionType_CROSS_CHAIN_ACTION_TYPE_HOME_COLLATERAL_RELEASE_AUTHORIZED_V1:
		action, ok := envelope.GetTypedAction().(*unifiedv1.CrossChainMessageEnvelope_HomeCollateralReleaseAuthorized)
		if !ok {
			return nil, actionMismatch()
		}
		return encodeLoanAction(
			action.HomeCollateralReleaseAuthorized.GetLoanId(),
			action.HomeCollateralReleaseAuthorized.GetCollateralId(),
			action.HomeCollateralReleaseAuthorized.GetHomeLoanAccount(),
			action.HomeCollateralReleaseAuthorized.GetBorrower(),
			action.HomeCollateralReleaseAuthorized.GetLender(),
			action.HomeCollateralReleaseAuthorized.GetCollateralToken(),
			action.HomeCollateralReleaseAuthorized.GetAmount(),
			action.HomeCollateralReleaseAuthorized.GetPolicyHash(),
			"collateral_id", "collateral_token",
		)
	case unifiedv1.CrossChainActionType_CROSS_CHAIN_ACTION_TYPE_SATELLITE_COLLATERAL_RELEASED_V1:
		action, ok := envelope.GetTypedAction().(*unifiedv1.CrossChainMessageEnvelope_SatelliteCollateralReleased)
		if !ok {
			return nil, actionMismatch()
		}
		return encodeLoanAction(
			action.SatelliteCollateralReleased.GetLoanId(),
			action.SatelliteCollateralReleased.GetCollateralId(),
			action.SatelliteCollateralReleased.GetHomeLoanAccount(),
			action.SatelliteCollateralReleased.GetBorrower(),
			action.SatelliteCollateralReleased.GetLender(),
			action.SatelliteCollateralReleased.GetCollateralToken(),
			action.SatelliteCollateralReleased.GetAmount(),
			action.SatelliteCollateralReleased.GetPolicyHash(),
			"collateral_id", "collateral_token",
		)
	case unifiedv1.CrossChainActionType_CROSS_CHAIN_ACTION_TYPE_CANCELLATION_REQUESTED_V1:
		action, ok := envelope.GetTypedAction().(*unifiedv1.CrossChainMessageEnvelope_LoanCancellationRequested)
		if !ok {
			return nil, actionMismatch()
		}
		return encodeStatic(
			bytes32ABI(action.LoanCancellationRequested.GetCancellationId(), "cancellation_id"),
			bytes32ABI(action.LoanCancellationRequested.GetLoanId(), "loan_id"),
			bytes32ABI(action.LoanCancellationRequested.GetFundingLockId(), "funding_lock_id"),
			bytes32ABI(
				action.LoanCancellationRequested.GetDisbursementMessageId(),
				"disbursement_message_id",
			),
			bytes32ABI(
				action.LoanCancellationRequested.GetDisbursementTombstoneHash(),
				"disbursement_tombstone_hash",
			),
			addressABI(
				action.LoanCancellationRequested.GetHomeLoanAccount(),
				"home_loan_account",
			),
			addressABI(action.LoanCancellationRequested.GetLender(), "lender"),
			addressABI(action.LoanCancellationRequested.GetWrappedToken(), "wrapped_token"),
			uint256ABI(action.LoanCancellationRequested.GetAmount(), "amount"),
			bytes32ABI(action.LoanCancellationRequested.GetPolicyHash(), "policy_hash"),
			bytes32ABI(action.LoanCancellationRequested.GetReasonCode(), "reason_code"),
		)
	case unifiedv1.CrossChainActionType_CROSS_CHAIN_ACTION_TYPE_SOURCE_COMPENSATED_V1:
		action, ok := envelope.GetTypedAction().(*unifiedv1.CrossChainMessageEnvelope_SatelliteFundingCancelled)
		if !ok {
			return nil, actionMismatch()
		}
		return encodeStatic(
			bytes32ABI(action.SatelliteFundingCancelled.GetCancellationId(), "cancellation_id"),
			bytes32ABI(action.SatelliteFundingCancelled.GetLoanId(), "loan_id"),
			bytes32ABI(action.SatelliteFundingCancelled.GetFundingLockId(), "funding_lock_id"),
			bytes32ABI(
				action.SatelliteFundingCancelled.GetDisbursementMessageId(),
				"disbursement_message_id",
			),
			bytes32ABI(
				action.SatelliteFundingCancelled.GetDisbursementTombstoneHash(),
				"disbursement_tombstone_hash",
			),
			bytes32ABI(
				action.SatelliteFundingCancelled.GetEscrowBurnResultHash(),
				"escrow_burn_result_hash",
			),
			addressABI(
				action.SatelliteFundingCancelled.GetHomeLoanAccount(),
				"home_loan_account",
			),
			addressABI(action.SatelliteFundingCancelled.GetLender(), "lender"),
			addressABI(action.SatelliteFundingCancelled.GetWrappedToken(), "wrapped_token"),
			uint256ABI(action.SatelliteFundingCancelled.GetAmount(), "amount"),
			bytes32ABI(action.SatelliteFundingCancelled.GetPolicyHash(), "policy_hash"),
		)
	case unifiedv1.CrossChainActionType_CROSS_CHAIN_ACTION_TYPE_SATELLITE_UFT_PERMANENT_BURNED_V1:
		action, ok := envelope.GetTypedAction().(*unifiedv1.CrossChainMessageEnvelope_SatelliteUftPermanentBurned)
		if !ok {
			return nil, actionMismatch()
		}
		return encodeStatic(
			bytes32ABI(action.SatelliteUftPermanentBurned.GetBurnId(), "burn_id"),
			bytes32ABI(action.SatelliteUftPermanentBurned.GetBackingRoutePolicyHash(), "backing_route_policy_hash"),
			addressABI(action.SatelliteUftPermanentBurned.GetCanonicalToken(), "canonical_token"),
			addressABI(action.SatelliteUftPermanentBurned.GetHomeBridgeHub(), "home_bridge_hub"),
			addressABI(action.SatelliteUftPermanentBurned.GetWrappedToken(), "wrapped_token"),
			uint256ABI(action.SatelliteUftPermanentBurned.GetAmount(), "amount"),
		)
	default:
		return nil, fmt.Errorf(
			"%w: action %d has no frozen economic ABI payload",
			ErrInvalidEnvelope, envelope.GetActionType(),
		)
	}
}

// EncodeLoanCancellationAuthorizationABI independently reconstructs the exact
// 12-word Solidity abi.encode(LoanCancellationAuthorization) layout. Signatures
// are separate call authority and are intentionally absent.
func EncodeLoanCancellationAuthorizationABI(
	authorization *unifiedv1.LoanCancellationAuthorization,
) ([]byte, error) {
	if authorization == nil {
		return nil, fmt.Errorf("%w: nil loan cancellation authorization", ErrInvalidEnvelope)
	}
	return encodeStatic(
		addressABI(authorization.GetLoanRouter(), "loan_router"),
		bytes32ABI(authorization.GetLoanId(), "loan_id"),
		bytes32ABI(authorization.GetFundingLockId(), "funding_lock_id"),
		bytes32ABI(
			authorization.GetDisbursementMessageId(),
			"disbursement_message_id",
		),
		bytes32ABI(
			authorization.GetDisbursementTombstoneHash(),
			"disbursement_tombstone_hash",
		),
		uint256ABI(authorization.GetAmount(), "amount"),
		bytes32ABI(authorization.GetPolicyHash(), "policy_hash"),
		abiWord{value: uintWord(authorization.GetAuthorizationNonce())},
		abiWord{value: uintWord(authorization.GetValidUntil())},
		bytes32ABI(authorization.GetReasonCode(), "reason_code"),
		bytes32ABI(authorization.GetAuthorizerSetHash(), "authorizer_set_hash"),
		abiWord{value: uintWord(uint64(authorization.GetAuthorizerSetVersion()))},
	)
}

// BindTypedActionABI materializes the canonical ABI bytes and their Keccak
// commitment from the typed oneof. Builders call this before Seal.
func BindTypedActionABI(envelope *unifiedv1.CrossChainMessageEnvelope) error {
	encoded, err := EncodeTypedActionABI(envelope)
	if err != nil {
		return err
	}
	envelope.TypedActionPayload = encoded
	hash := keccak(encoded)
	envelope.PayloadHash = append([]byte(nil), hash[:]...)
	return nil
}

type abiWord struct {
	value []byte
	err   error
}

func actionMismatch() error {
	return fmt.Errorf("%w: action_type and typed_action oneof disagree", ErrInvalidEnvelope)
}

func encodeLoanAction(
	loanID, operationID, homeLoan, borrower, lender, asset []byte,
	amount string,
	policyHash []byte,
	operationName, assetName string,
) ([]byte, error) {
	return encodeStatic(
		bytes32ABI(loanID, "loan_id"),
		bytes32ABI(operationID, operationName),
		addressABI(homeLoan, "home_loan_account"),
		addressABI(borrower, "borrower"),
		addressABI(lender, "lender"),
		addressABI(asset, assetName),
		uint256ABI(amount, "amount"),
		bytes32ABI(policyHash, "policy_hash"),
	)
}

func encodeStatic(words ...abiWord) ([]byte, error) {
	encoded := make([]byte, 0, len(words)*32)
	for _, word := range words {
		if word.err != nil {
			return nil, word.err
		}
		encoded = append(encoded, word.value...)
	}
	return encoded, nil
}

func bytes32ABI(value []byte, name string) abiWord {
	if err := exactLength(value, 32, name); err != nil {
		return abiWord{err: err}
	}
	return abiWord{value: append([]byte(nil), value...)}
}

func addressABI(value []byte, name string) abiWord {
	if err := exactLength(value, 20, name); err != nil {
		return abiWord{err: err}
	}
	return abiWord{value: addressWord(value)}
}

func uint256ABI(value, name string) abiWord {
	word, err := uint256(value, name)
	return abiWord{value: word, err: err}
}

func exactLength(value []byte, size int, name string) error {
	if len(value) != size {
		return fmt.Errorf("%w: %s must be %d bytes", ErrInvalidEnvelope, name, size)
	}
	return nil
}

func uint256(value string, name string) ([]byte, error) {
	number, ok := new(big.Int).SetString(value, 10)
	if !ok || number.Sign() <= 0 || number.BitLen() > 256 || number.String() != value {
		return nil, fmt.Errorf("%w: %s must be a canonical positive uint256", ErrInvalidEnvelope, name)
	}
	word := make([]byte, 32)
	number.FillBytes(word)
	return word, nil
}

func uintWord(value uint64) []byte {
	word := make([]byte, 32)
	binary.BigEndian.PutUint64(word[24:], value)
	return word
}

func addressWord(address []byte) []byte {
	word := make([]byte, 32)
	copy(word[12:], address)
	return word
}

func keccak(value []byte) [32]byte {
	hash := sha3.NewLegacyKeccak256()
	_, _ = hash.Write(value)
	var result [32]byte
	hash.Sum(result[:0])
	return result
}
