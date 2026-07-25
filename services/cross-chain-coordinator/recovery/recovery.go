// Package recovery implements policy-bound tombstone-before-compensation.
package recovery

import (
	"bytes"
	"encoding/binary"
	"encoding/hex"
	"errors"
	"math/big"
	"sort"
	"sync"
	"time"

	"github.com/decred/dcrd/dcrec/secp256k1/v4"
	secp256k1ecdsa "github.com/decred/dcrd/dcrec/secp256k1/v4/ecdsa"
	"golang.org/x/crypto/sha3"
)

var (
	ErrExecuted             = errors.New("destination already executed")
	ErrNotTombstoned        = errors.New("finalized destination tombstone required")
	ErrAlreadyCompensated   = errors.New("source compensation already recorded")
	ErrRecoveryConflict     = errors.New("recovery identity conflict")
	ErrInsufficientApproval = errors.New("insufficient recovery approvals")
)

type State string

const (
	Requested             State = "REQUESTED"
	DestinationTombstoned State = "DESTINATION_TOMBSTONED"
	SourceCompensated     State = "SOURCE_COMPENSATED"
	Recovered             State = "RECOVERED"
	Disputed              State = "DISPUTED"
)

type Approval struct {
	SignerID  string
	Signature []byte
}

type Request struct {
	RecoveryID                 string
	OriginalMessageID          [32]byte
	ImmutableEnvelopeHash      [32]byte
	RecoveryNonce              uint64
	RouteVersion               uint64
	OriginalActionType         uint8
	OriginalActionPayload      []byte
	AssetID                    string
	Units                      string
	CompensationRecipient      string
	CompensationPayload        []byte
	ReasonCode                 string
	SourceStateCommitment      [32]byte
	DestinationStateCommitment [32]byte
	AuthorizerPolicyHash       [32]byte
	RoutePolicyHash            [32]byte
	AssetAmountCommitment      [32]byte
	CompensationPayloadHash    [32]byte
	MessageExpiresAt           uint64
	Action                     uint8
	AuthorizerSetVersion       uint32
	Authorization              *Authorization
	Approvals                  []Approval
	RequestedAt                time.Time
}

// Authorization is byte-for-byte domain-equivalent to
// CrossChainRecoveryController.recoveryAuthorizationDigest.
type Authorization struct {
	ProtocolID             [32]byte
	SourceChainID          string
	SourceCoordinator      [20]byte
	DestinationChainID     string
	DestinationCoordinator [20]byte
	Request                AuthorizationRequest
}

type AuthorizationRequest struct {
	MessageID                  [32]byte
	EnvelopeHash               [32]byte
	RoutePolicyHash            [32]byte
	AssetAmountCommitment      [32]byte
	SourceStateCommitment      [32]byte
	DestinationStateCommitment [32]byte
	CompensationPayloadHash    [32]byte
	MessageExpiresAt           uint64
	RecoveryNonce              uint64
	ReasonCode                 [32]byte
	Action                     uint8
	AuthorizerSetHash          [32]byte
	AuthorizerSetVersion       uint32
}

type Authorizer interface {
	Verify(Request) error
}

// Secp256k1Policy is the frozen 2-of-3 Ethereum-address recovery policy.
// Signers are 20-byte addresses derived from uncompressed secp256k1 public
// keys. No private-key material is accepted by the runtime authorizer.
type Secp256k1Policy struct {
	PolicyHash [32]byte
	Signers    map[string][20]byte
}

type Secp256k1Authorizer struct {
	policies map[[32]byte]Secp256k1Policy
}

func NewSecp256k1Authorizer(
	policies ...Secp256k1Policy,
) (*Secp256k1Authorizer, error) {
	result := &Secp256k1Authorizer{
		policies: make(map[[32]byte]Secp256k1Policy, len(policies)),
	}
	for _, policy := range policies {
		if policy.PolicyHash == ([32]byte{}) || len(policy.Signers) != 3 {
			return nil, errors.New("recovery policy must be 2-of-3 secp256k1")
		}
		copied := Secp256k1Policy{
			PolicyHash: policy.PolicyHash,
			Signers:    make(map[string][20]byte, 3),
		}
		seenAddresses := make(map[[20]byte]struct{}, 3)
		for signerID, address := range policy.Signers {
			if signerID == "" || address == ([20]byte{}) {
				return nil, errors.New("invalid recovery signer")
			}
			if _, duplicate := seenAddresses[address]; duplicate {
				return nil, errors.New("duplicate recovery signer address")
			}
			seenAddresses[address] = struct{}{}
			copied.Signers[signerID] = address
		}
		if _, duplicate := result.policies[policy.PolicyHash]; duplicate {
			return nil, errors.New("duplicate recovery policy")
		}
		result.policies[policy.PolicyHash] = copied
	}
	return result, nil
}

func (authorizer *Secp256k1Authorizer) Verify(request Request) error {
	if authorizer == nil {
		return ErrInsufficientApproval
	}
	policy, ok := authorizer.policies[request.AuthorizerPolicyHash]
	if !ok || request.Authorization == nil || len(request.Approvals) < 2 ||
		request.Authorization.Request.MessageID != request.OriginalMessageID ||
		request.Authorization.Request.EnvelopeHash != request.ImmutableEnvelopeHash ||
		request.Authorization.Request.RecoveryNonce != request.RecoveryNonce ||
		request.Authorization.Request.RoutePolicyHash != request.RoutePolicyHash ||
		request.Authorization.Request.AssetAmountCommitment != request.AssetAmountCommitment ||
		request.Authorization.Request.SourceStateCommitment != request.SourceStateCommitment ||
		request.Authorization.Request.DestinationStateCommitment !=
			request.DestinationStateCommitment ||
		request.Authorization.Request.CompensationPayloadHash !=
			request.CompensationPayloadHash ||
		request.Authorization.Request.MessageExpiresAt != request.MessageExpiresAt ||
		request.Authorization.Request.ReasonCode != ReasonCodeCommitment(request.ReasonCode) ||
		request.Authorization.Request.Action != request.Action ||
		request.Authorization.Request.AuthorizerSetHash != request.AuthorizerPolicyHash ||
		request.Authorization.Request.AuthorizerSetVersion != request.AuthorizerSetVersion {
		return ErrInsufficientApproval
	}
	if err := validateRecoveryEconomics(request); err != nil {
		return ErrInsufficientApproval
	}
	recoveryID, err := RecoveryID(request.Authorization.Request)
	if err != nil ||
		request.RecoveryID != hex.EncodeToString(recoveryID[:]) {
		return ErrInsufficientApproval
	}
	digest, err := DigestAuthorization(*request.Authorization)
	if err != nil {
		return ErrInsufficientApproval
	}
	seen := make(map[string]struct{}, len(request.Approvals))
	valid := 0
	for _, approval := range request.Approvals {
		expected, registered := policy.Signers[approval.SignerID]
		if !registered {
			return ErrInsufficientApproval
		}
		if _, duplicate := seen[approval.SignerID]; duplicate {
			return ErrInsufficientApproval
		}
		seen[approval.SignerID] = struct{}{}
		recovered, err := VerifyEthereumSignature(digest, approval.Signature)
		if err != nil || recovered != expected {
			return ErrInsufficientApproval
		}
		valid++
	}
	if valid < 2 {
		return ErrInsufficientApproval
	}
	return nil
}

// DigestAuthorization mirrors CrossChainRecoveryController's frozen V2 ABI.
func DigestAuthorization(authorization Authorization) ([32]byte, error) {
	var zero [32]byte
	sourceChain, err := abiUint256(authorization.SourceChainID)
	if err != nil {
		return zero, ErrInsufficientApproval
	}
	destinationChain, err := abiUint256(authorization.DestinationChainID)
	if err != nil || authorization.ProtocolID == ([32]byte{}) ||
		authorization.SourceCoordinator == ([20]byte{}) ||
		authorization.DestinationCoordinator == ([20]byte{}) ||
		!validAuthorizationRequest(authorization.Request) {
		return zero, ErrInsufficientApproval
	}
	// The static 13-word tuple is expanded in place by abi.encode.
	const headWords = 19
	encoded := make([]byte, 0, (headWords+2)*32)
	encoded = append(encoded, abiUint64(headWords*32)...)
	encoded = append(encoded, authorization.ProtocolID[:]...)
	encoded = append(encoded, sourceChain...)
	encoded = append(encoded, abiAddress(authorization.SourceCoordinator)...)
	encoded = append(encoded, destinationChain...)
	encoded = append(encoded, abiAddress(authorization.DestinationCoordinator)...)
	encoded = append(encoded, authorizationWords(authorization.Request)...)
	domain := []byte("UNIFIED_XCHAIN_RECOVERY_AUTHORIZATION_V2")
	encoded = append(encoded, abiUint64(uint64(len(domain)))...)
	encoded = append(encoded, domain...)
	if remainder := len(encoded) % 32; remainder != 0 {
		encoded = append(encoded, make([]byte, 32-remainder)...)
	}
	hasher := sha3.NewLegacyKeccak256()
	_, _ = hasher.Write(encoded)
	hasher.Sum(zero[:0])
	return zero, nil
}

func RecoveryID(request AuthorizationRequest) ([32]byte, error) {
	var zero [32]byte
	if !validAuthorizationRequest(request) {
		return zero, ErrInsufficientApproval
	}
	const headWords = 14
	encoded := make([]byte, 0, (headWords+2)*32)
	encoded = append(encoded, abiUint64(headWords*32)...)
	encoded = append(encoded, authorizationWords(request)...)
	domain := []byte("UNIFIED_XCHAIN_RECOVERY_ID_V1")
	encoded = append(encoded, abiUint64(uint64(len(domain)))...)
	encoded = append(encoded, domain...)
	if remainder := len(encoded) % 32; remainder != 0 {
		encoded = append(encoded, make([]byte, 32-remainder)...)
	}
	return keccakBytes(encoded), nil
}

func AssetAmountCommitment(
	actionType uint8,
	payloadHash [32]byte,
) ([32]byte, error) {
	if actionType == 0 || payloadHash == ([32]byte{}) {
		return [32]byte{}, ErrInsufficientApproval
	}
	const headWords = 3
	encoded := make([]byte, 0, (headWords+2)*32)
	encoded = append(encoded, abiUint64(headWords*32)...)
	encoded = append(encoded, abiUint64(uint64(actionType))...)
	encoded = append(encoded, payloadHash[:]...)
	domain := []byte("UNIFIED_RECOVERY_ASSET_AMOUNT_COMMITMENT_V1")
	encoded = append(encoded, abiUint64(uint64(len(domain)))...)
	encoded = append(encoded, domain...)
	if remainder := len(encoded) % 32; remainder != 0 {
		encoded = append(encoded, make([]byte, 32-remainder)...)
	}
	return keccakBytes(encoded), nil
}

// EncodeCompensationPayload freezes the signed compensation instruction as
// abi.encode(address asset, uint256 units, address recipient). Its exact
// bytes are committed by AuthorizationRequest.CompensationPayloadHash.
func EncodeCompensationPayload(
	asset [20]byte,
	units string,
	recipient [20]byte,
) ([]byte, error) {
	if asset == ([20]byte{}) || recipient == ([20]byte{}) ||
		!canonicalPositiveUint256(units) {
		return nil, ErrInsufficientApproval
	}
	number, _ := new(big.Int).SetString(units, 10)
	encoded := make([]byte, 0, 3*32)
	encoded = append(encoded, abiAddress(asset)...)
	unitWord := make([]byte, 32)
	number.FillBytes(unitWord)
	encoded = append(encoded, unitWord...)
	encoded = append(encoded, abiAddress(recipient)...)
	return encoded, nil
}

type recoveryEconomics struct {
	AssetID   string
	Units     string
	Recipient string
}

func validateRecoveryEconomics(request Request) error {
	if request.OriginalActionType == 0 || len(request.OriginalActionPayload) == 0 ||
		len(request.CompensationPayload) == 0 || request.Authorization == nil {
		return ErrInsufficientApproval
	}
	payloadHash := keccakBytes(request.OriginalActionPayload)
	commitment, err := AssetAmountCommitment(request.OriginalActionType, payloadHash)
	if err != nil || commitment != request.AssetAmountCommitment ||
		commitment != request.Authorization.Request.AssetAmountCommitment {
		return ErrInsufficientApproval
	}
	original, err := decodeActionEconomics(
		request.OriginalActionType,
		request.OriginalActionPayload,
	)
	if err != nil {
		return ErrInsufficientApproval
	}
	compensation, err := decodeCompensationPayload(request.CompensationPayload)
	compensationHash := keccakBytes(request.CompensationPayload)
	if err != nil ||
		compensationHash != request.CompensationPayloadHash ||
		compensationHash != request.Authorization.Request.CompensationPayloadHash ||
		original.AssetID != compensation.AssetID ||
		original.Units != compensation.Units ||
		request.AssetID != original.AssetID ||
		request.Units != original.Units ||
		request.CompensationRecipient != compensation.Recipient {
		return ErrInsufficientApproval
	}
	return nil
}

// decodeActionEconomics extracts the asset and amount from the frozen static
// ABI payloads. Unsupported and non-economic actions cannot enter recovery.
func decodeActionEconomics(actionType uint8, payload []byte) (recoveryEconomics, error) {
	var assetWord, amountWord, expectedWords int
	switch actionType {
	case 1:
		assetWord, amountWord, expectedWords = 2, 6, 7
	case 2:
		assetWord, amountWord, expectedWords = 5, 6, 8
	case 3:
		assetWord, amountWord, expectedWords = 4, 6, 7
	case 4:
		assetWord, amountWord, expectedWords = 1, 3, 5
	case 5, 6, 7, 9, 10:
		assetWord, amountWord, expectedWords = 5, 6, 8
	case 8:
		assetWord, amountWord, expectedWords = 6, 8, 9
	case 15:
		assetWord, amountWord, expectedWords = 4, 5, 6
	default:
		return recoveryEconomics{}, ErrInsufficientApproval
	}
	if len(payload) != expectedWords*32 {
		return recoveryEconomics{}, ErrInsufficientApproval
	}
	asset, err := decodeABIAddress(payload, assetWord)
	if err != nil {
		return recoveryEconomics{}, err
	}
	units, err := decodeABIUint256(payload, amountWord)
	if err != nil {
		return recoveryEconomics{}, err
	}
	return recoveryEconomics{AssetID: canonicalAddress(asset), Units: units}, nil
}

func decodeCompensationPayload(payload []byte) (recoveryEconomics, error) {
	if len(payload) != 3*32 {
		return recoveryEconomics{}, ErrInsufficientApproval
	}
	asset, err := decodeABIAddress(payload, 0)
	if err != nil {
		return recoveryEconomics{}, err
	}
	units, err := decodeABIUint256(payload, 1)
	if err != nil {
		return recoveryEconomics{}, err
	}
	recipient, err := decodeABIAddress(payload, 2)
	if err != nil {
		return recoveryEconomics{}, err
	}
	return recoveryEconomics{
		AssetID:   canonicalAddress(asset),
		Units:     units,
		Recipient: canonicalAddress(recipient),
	}, nil
}

func decodeABIAddress(payload []byte, word int) ([20]byte, error) {
	var result [20]byte
	offset := word * 32
	if word < 0 || offset+32 > len(payload) ||
		!bytes.Equal(payload[offset:offset+12], make([]byte, 12)) {
		return result, ErrInsufficientApproval
	}
	copy(result[:], payload[offset+12:offset+32])
	if result == ([20]byte{}) {
		return [20]byte{}, ErrInsufficientApproval
	}
	return result, nil
}

func decodeABIUint256(payload []byte, word int) (string, error) {
	offset := word * 32
	if word < 0 || offset+32 > len(payload) {
		return "", ErrInsufficientApproval
	}
	number := new(big.Int).SetBytes(payload[offset : offset+32])
	if number.Sign() <= 0 {
		return "", ErrInsufficientApproval
	}
	return number.String(), nil
}

func canonicalAddress(address [20]byte) string {
	return "0x" + hex.EncodeToString(address[:])
}

func AuthorizerSetHash(
	version uint32,
	signers [3][20]byte,
) ([32]byte, error) {
	if version == 0 || signers[0] == ([20]byte{}) ||
		signers[1] == ([20]byte{}) || signers[2] == ([20]byte{}) {
		return [32]byte{}, ErrInsufficientApproval
	}
	for left := 0; left < len(signers)-1; left++ {
		for right := left + 1; right < len(signers); right++ {
			if bytes.Compare(signers[left][:], signers[right][:]) > 0 {
				signers[left], signers[right] = signers[right], signers[left]
			}
		}
	}
	if signers[0] == signers[1] || signers[1] == signers[2] {
		return [32]byte{}, ErrInsufficientApproval
	}
	const headWords = 6
	encoded := make([]byte, 0, (headWords+2)*32)
	encoded = append(encoded, abiUint64(headWords*32)...)
	encoded = append(encoded, abiUint64(uint64(version))...)
	encoded = append(encoded, abiUint64(2)...)
	for _, signer := range signers {
		encoded = append(encoded, abiAddress(signer)...)
	}
	domain := []byte("UNIFIED_XCHAIN_RECOVERY_AUTHORIZER_SET_V1")
	encoded = append(encoded, abiUint64(uint64(len(domain)))...)
	encoded = append(encoded, domain...)
	if remainder := len(encoded) % 32; remainder != 0 {
		encoded = append(encoded, make([]byte, 32-remainder)...)
	}
	return keccakBytes(encoded), nil
}

func validAuthorizationRequest(request AuthorizationRequest) bool {
	return request.MessageID != ([32]byte{}) &&
		request.EnvelopeHash != ([32]byte{}) &&
		request.RoutePolicyHash != ([32]byte{}) &&
		request.AssetAmountCommitment != ([32]byte{}) &&
		request.SourceStateCommitment != ([32]byte{}) &&
		request.DestinationStateCommitment != ([32]byte{}) &&
		request.CompensationPayloadHash != ([32]byte{}) &&
		request.MessageExpiresAt != 0 && request.RecoveryNonce != 0 &&
		request.ReasonCode != ([32]byte{}) && request.Action == 1 &&
		request.AuthorizerSetHash != ([32]byte{}) &&
		request.AuthorizerSetVersion != 0
}

func authorizationWords(request AuthorizationRequest) []byte {
	result := make([]byte, 0, 13*32)
	result = append(result, request.MessageID[:]...)
	result = append(result, request.EnvelopeHash[:]...)
	result = append(result, request.RoutePolicyHash[:]...)
	result = append(result, request.AssetAmountCommitment[:]...)
	result = append(result, request.SourceStateCommitment[:]...)
	result = append(result, request.DestinationStateCommitment[:]...)
	result = append(result, request.CompensationPayloadHash[:]...)
	result = append(result, abiUint64(request.MessageExpiresAt)...)
	result = append(result, abiUint64(request.RecoveryNonce)...)
	result = append(result, request.ReasonCode[:]...)
	result = append(result, abiUint64(uint64(request.Action))...)
	result = append(result, request.AuthorizerSetHash[:]...)
	result = append(result, abiUint64(uint64(request.AuthorizerSetVersion))...)
	return result
}

func abiUint256(value string) ([]byte, error) {
	number, ok := new(big.Int).SetString(value, 10)
	if !ok || number.Sign() <= 0 || number.BitLen() > 256 ||
		number.String() != value {
		return nil, ErrInsufficientApproval
	}
	result := make([]byte, 32)
	number.FillBytes(result)
	return result, nil
}

func abiAddress(value [20]byte) []byte {
	result := make([]byte, 32)
	copy(result[12:], value[:])
	return result
}

func keccakBytes(value []byte) [32]byte {
	hasher := sha3.NewLegacyKeccak256()
	_, _ = hasher.Write(value)
	var result [32]byte
	hasher.Sum(result[:0])
	return result
}

func abiUint64(value uint64) []byte {
	result := make([]byte, 32)
	binary.BigEndian.PutUint64(result[24:], value)
	return result
}

// VerifyEthereumSignature enforces the 65-byte Ethereum signature layout,
// V in {0,1,27,28}, strict scalar ranges, and low-S before recovering the
// 20-byte signer address.
func VerifyEthereumSignature(
	digest [32]byte,
	signature []byte,
) ([20]byte, error) {
	var zero [20]byte
	if len(signature) != 65 {
		return zero, ErrInsufficientApproval
	}
	var r, s secp256k1.ModNScalar
	if r.SetByteSlice(signature[:32]) || r.IsZero() ||
		s.SetByteSlice(signature[32:64]) || s.IsZero() ||
		s.IsOverHalfOrder() {
		return zero, ErrInsufficientApproval
	}
	recoveryID := signature[64]
	if recoveryID == 27 || recoveryID == 28 {
		recoveryID -= 27
	}
	if recoveryID > 1 {
		return zero, ErrInsufficientApproval
	}
	compact := make([]byte, 65)
	compact[0] = 27 + recoveryID
	copy(compact[1:33], signature[:32])
	copy(compact[33:], signature[32:64])
	publicKey, _, err := secp256k1ecdsa.RecoverCompact(compact, digest[:])
	if err != nil {
		return zero, ErrInsufficientApproval
	}
	serialized := publicKey.SerializeUncompressed()
	hasher := sha3.NewLegacyKeccak256()
	_, _ = hasher.Write(serialized[1:])
	sum := hasher.Sum(nil)
	copy(zero[:], sum[len(sum)-20:])
	return zero, nil
}

type Tombstone struct {
	OriginalMessageID [32]byte
	Hash              [32]byte
	FinalityProofHash [32]byte
	FinalizedAt       time.Time
}

type Compensation struct {
	OriginalMessageID [32]byte
	TombstoneHash     [32]byte
	Payload           []byte
	ResultHash        [32]byte
	AssetID           string
	Recipient         string
	Units             string
	CompensatedAt     time.Time
}

type Record struct {
	Request      Request
	State        State
	Tombstone    *Tombstone
	Compensation *Compensation
	RecoveryAck  [32]byte
	SupersededBy [32]byte
}

type Destination interface {
	ExecutionResult([32]byte) (resultHash [32]byte, executed bool)
	CreateTombstone(Request) (Tombstone, error)
}

type Manager struct {
	mu         sync.Mutex
	authorizer Authorizer
	records    map[[32]byte]Record
}

func NewManager(authorizer Authorizer) (*Manager, error) {
	if authorizer == nil {
		return nil, errors.New("recovery authorizer is required")
	}
	return &Manager{authorizer: authorizer, records: make(map[[32]byte]Record)}, nil
}

func (manager *Manager) Request(request Request) (Record, error) {
	if request.RecoveryID == "" || request.RecoveryNonce == 0 || request.RouteVersion == 0 ||
		request.AssetID == "" || !canonicalPositiveUint256(request.Units) ||
		request.CompensationRecipient == "" || request.ReasonCode == "" ||
		request.RequestedAt.IsZero() || request.AuthorizerPolicyHash == ([32]byte{}) {
		return Record{}, ErrInsufficientApproval
	}
	if err := validateRecoveryEconomics(request); err != nil {
		return Record{}, ErrInsufficientApproval
	}
	if err := manager.authorizer.Verify(request); err != nil {
		return Record{}, ErrInsufficientApproval
	}
	request.Approvals = canonicalApprovals(request.Approvals)
	manager.mu.Lock()
	defer manager.mu.Unlock()
	if existing, ok := manager.records[request.OriginalMessageID]; ok {
		if !sameRequest(existing.Request, request) {
			return Record{}, ErrRecoveryConflict
		}
		return cloneRecord(existing), nil
	}
	record := Record{Request: cloneRequest(request), State: Requested}
	manager.records[request.OriginalMessageID] = record
	return cloneRecord(record), nil
}

func ReasonCodeCommitment(reason string) [32]byte {
	hasher := sha3.NewLegacyKeccak256()
	_, _ = hasher.Write([]byte(reason))
	var result [32]byte
	hasher.Sum(result[:0])
	return result
}

func canonicalPositiveUint256(value string) bool {
	number, ok := new(big.Int).SetString(value, 10)
	return ok && number.Sign() > 0 && number.BitLen() <= 256 &&
		number.String() == value
}

func (manager *Manager) Tombstone(messageID [32]byte, destination Destination) (Record, error) {
	if destination == nil {
		return Record{}, errors.New("destination evidence source is required")
	}
	manager.mu.Lock()
	defer manager.mu.Unlock()
	record, ok := manager.records[messageID]
	if !ok {
		return Record{}, ErrRecoveryConflict
	}
	if _, executed := destination.ExecutionResult(messageID); executed {
		return Record{}, ErrExecuted
	}
	if record.Tombstone != nil {
		return cloneRecord(record), nil
	}
	tombstone, err := destination.CreateTombstone(record.Request)
	if err != nil {
		return Record{}, err
	}
	if tombstone.OriginalMessageID != messageID || tombstone.FinalizedAt.IsZero() ||
		tombstone.Hash == ([32]byte{}) || tombstone.FinalityProofHash == ([32]byte{}) {
		return Record{}, ErrRecoveryConflict
	}
	record.State = DestinationTombstoned
	record.Tombstone = &tombstone
	manager.records[messageID] = record
	return cloneRecord(record), nil
}

func (manager *Manager) Compensate(compensation Compensation) (Record, error) {
	manager.mu.Lock()
	defer manager.mu.Unlock()
	record, ok := manager.records[compensation.OriginalMessageID]
	if !ok || record.Tombstone == nil {
		return Record{}, ErrNotTombstoned
	}
	if record.Compensation != nil {
		if !sameCompensation(*record.Compensation, compensation) {
			return Record{}, ErrAlreadyCompensated
		}
		return cloneRecord(record), nil
	}
	if compensation.TombstoneHash != record.Tombstone.Hash ||
		!bytes.Equal(compensation.Payload, record.Request.CompensationPayload) ||
		keccakBytes(compensation.Payload) != record.Request.CompensationPayloadHash ||
		compensation.ResultHash == ([32]byte{}) || compensation.Recipient == "" ||
		compensation.AssetID != record.Request.AssetID ||
		compensation.Recipient != record.Request.CompensationRecipient ||
		compensation.Units != record.Request.Units || compensation.CompensatedAt.IsZero() {
		return Record{}, ErrRecoveryConflict
	}
	record.State = SourceCompensated
	record.Compensation = &compensation
	manager.records[compensation.OriginalMessageID] = record
	return cloneRecord(record), nil
}

// Finalize records the finalized recovery acknowledgement after source
// compensation and exposes the required intermediate state.
func (manager *Manager) Finalize(messageID, acknowledgementHash [32]byte) (Record, error) {
	if acknowledgementHash == ([32]byte{}) {
		return Record{}, ErrRecoveryConflict
	}
	manager.mu.Lock()
	defer manager.mu.Unlock()
	record, ok := manager.records[messageID]
	if ok && record.State == Recovered && record.RecoveryAck == acknowledgementHash {
		return cloneRecord(record), nil
	}
	if !ok || record.State != SourceCompensated || record.Compensation == nil {
		return Record{}, ErrRecoveryConflict
	}
	record.State = Recovered
	record.RecoveryAck = acknowledgementHash
	manager.records[messageID] = record
	return cloneRecord(record), nil
}

func (manager *Manager) AuthorizeReplacement(original, replacement [32]byte) error {
	manager.mu.Lock()
	defer manager.mu.Unlock()
	record, ok := manager.records[original]
	if !ok || record.State != Recovered || record.Tombstone == nil || record.Compensation == nil {
		return ErrNotTombstoned
	}
	if replacement == ([32]byte{}) || replacement == original {
		return ErrRecoveryConflict
	}
	if record.SupersededBy != ([32]byte{}) && record.SupersededBy != replacement {
		return ErrRecoveryConflict
	}
	record.SupersededBy = replacement
	manager.records[original] = record
	return nil
}

func (manager *Manager) Record(messageID [32]byte) (Record, bool) {
	manager.mu.Lock()
	defer manager.mu.Unlock()
	record, ok := manager.records[messageID]
	return cloneRecord(record), ok
}

func DigestRequest(request Request) [32]byte {
	var encoded []byte
	appendField := func(value []byte) {
		var size [8]byte
		binary.BigEndian.PutUint64(size[:], uint64(len(value)))
		encoded = append(encoded, size[:]...)
		encoded = append(encoded, value...)
	}
	appendField([]byte("UNIFIED_XCHAIN_RECOVERY_V1"))
	appendField([]byte(request.RecoveryID))
	appendField(request.OriginalMessageID[:])
	appendField(request.ImmutableEnvelopeHash[:])
	var number [8]byte
	binary.BigEndian.PutUint64(number[:], request.RecoveryNonce)
	appendField(number[:])
	binary.BigEndian.PutUint64(number[:], request.RouteVersion)
	appendField(number[:])
	appendField([]byte{request.OriginalActionType})
	appendField(request.OriginalActionPayload)
	appendField([]byte(request.AssetID))
	appendField([]byte(request.Units))
	appendField([]byte(request.CompensationRecipient))
	appendField(request.CompensationPayload)
	appendField([]byte(request.ReasonCode))
	appendField(request.SourceStateCommitment[:])
	appendField(request.DestinationStateCommitment[:])
	appendField(request.RoutePolicyHash[:])
	appendField(request.AssetAmountCommitment[:])
	appendField(request.CompensationPayloadHash[:])
	appendField(request.AuthorizerPolicyHash[:])
	binary.BigEndian.PutUint64(number[:], request.MessageExpiresAt)
	appendField(number[:])
	appendField([]byte{request.Action})
	var setVersion [4]byte
	binary.BigEndian.PutUint32(setVersion[:], request.AuthorizerSetVersion)
	appendField(setVersion[:])
	binary.BigEndian.PutUint64(number[:], uint64(request.RequestedAt.Unix()))
	appendField(number[:])
	hasher := sha3.NewLegacyKeccak256()
	_, _ = hasher.Write(encoded)
	var result [32]byte
	hasher.Sum(result[:0])
	return result
}

func sameRequest(left, right Request) bool {
	return left.RecoveryID == right.RecoveryID &&
		left.OriginalMessageID == right.OriginalMessageID &&
		left.ImmutableEnvelopeHash == right.ImmutableEnvelopeHash &&
		left.RecoveryNonce == right.RecoveryNonce &&
		left.RouteVersion == right.RouteVersion &&
		left.OriginalActionType == right.OriginalActionType &&
		bytes.Equal(left.OriginalActionPayload, right.OriginalActionPayload) &&
		left.AssetID == right.AssetID &&
		left.Units == right.Units &&
		left.CompensationRecipient == right.CompensationRecipient &&
		bytes.Equal(left.CompensationPayload, right.CompensationPayload) &&
		left.ReasonCode == right.ReasonCode &&
		left.SourceStateCommitment == right.SourceStateCommitment &&
		left.DestinationStateCommitment == right.DestinationStateCommitment &&
		left.RoutePolicyHash == right.RoutePolicyHash &&
		left.AssetAmountCommitment == right.AssetAmountCommitment &&
		left.CompensationPayloadHash == right.CompensationPayloadHash &&
		left.MessageExpiresAt == right.MessageExpiresAt &&
		left.Action == right.Action &&
		left.AuthorizerSetVersion == right.AuthorizerSetVersion &&
		left.AuthorizerPolicyHash == right.AuthorizerPolicyHash &&
		sameAuthorization(left.Authorization, right.Authorization) &&
		left.RequestedAt.Equal(right.RequestedAt) &&
		sameApprovals(left.Approvals, right.Approvals)
}

func sameAuthorization(left, right *Authorization) bool {
	if left == nil || right == nil {
		return left == nil && right == nil
	}
	return *left == *right
}

func sameApprovals(left, right []Approval) bool {
	if len(left) != len(right) {
		return false
	}
	for index := range left {
		if left[index].SignerID != right[index].SignerID ||
			!bytes.Equal(left[index].Signature, right[index].Signature) {
			return false
		}
	}
	return true
}

func canonicalApprovals(source []Approval) []Approval {
	result := append([]Approval(nil), source...)
	sort.Slice(result, func(left, right int) bool {
		return result[left].SignerID < result[right].SignerID
	})
	return result
}

func sameCompensation(left, right Compensation) bool {
	return left.OriginalMessageID == right.OriginalMessageID &&
		left.TombstoneHash == right.TombstoneHash &&
		bytes.Equal(left.Payload, right.Payload) &&
		left.ResultHash == right.ResultHash &&
		left.AssetID == right.AssetID &&
		left.Recipient == right.Recipient &&
		left.Units == right.Units &&
		left.CompensatedAt.Equal(right.CompensatedAt)
}

func cloneRequest(source Request) Request {
	if source.Authorization != nil {
		authorization := *source.Authorization
		source.Authorization = &authorization
	}
	source.OriginalActionPayload = append([]byte(nil), source.OriginalActionPayload...)
	source.CompensationPayload = append([]byte(nil), source.CompensationPayload...)
	source.Approvals = append([]Approval(nil), source.Approvals...)
	for index := range source.Approvals {
		source.Approvals[index].Signature = append([]byte(nil), source.Approvals[index].Signature...)
	}
	return source
}

func cloneRecord(source Record) Record {
	source.Request = cloneRequest(source.Request)
	if source.Tombstone != nil {
		value := *source.Tombstone
		source.Tombstone = &value
	}
	if source.Compensation != nil {
		value := *source.Compensation
		value.Payload = append([]byte(nil), source.Compensation.Payload...)
		source.Compensation = &value
	}
	return source
}

func EqualEnvelopeHash(left, right []byte) bool {
	return bytes.Equal(left, right)
}
