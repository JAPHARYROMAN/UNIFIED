package recovery

import (
	"encoding/hex"
	"errors"
	"testing"
	"time"

	"github.com/decred/dcrd/dcrec/secp256k1/v4"
	secp256k1ecdsa "github.com/decred/dcrd/dcrec/secp256k1/v4/ecdsa"
	"golang.org/x/crypto/sha3"
)

func TestSecp256k1AuthorizerEnforcesTwoOfThreeAndDomain(t *testing.T) {
	keys := []*secp256k1.PrivateKey{
		secp256k1.PrivKeyFromBytes([]byte{1}),
		secp256k1.PrivKeyFromBytes([]byte{2}),
		secp256k1.PrivKeyFromBytes([]byte{3}),
	}
	request := secp256k1Request()
	policyHash := request.AuthorizerPolicyHash
	policy := Secp256k1Policy{
		PolicyHash: policyHash,
		Signers: map[string][20]byte{
			"council-a": ethereumAddress(keys[0].PubKey()),
			"council-b": ethereumAddress(keys[1].PubKey()),
			"council-c": ethereumAddress(keys[2].PubKey()),
		},
	}
	authorizer, err := NewSecp256k1Authorizer(policy)
	if err != nil {
		t.Fatal(err)
	}
	digest, err := DigestAuthorization(*request.Authorization)
	if err != nil {
		t.Fatal(err)
	}
	request.Approvals = []Approval{
		{SignerID: "council-a", Signature: ethereumSignature(t, keys[0], digest, false)},
		{SignerID: "council-b", Signature: ethereumSignature(t, keys[1], digest, true)},
	}
	if err := authorizer.Verify(request); err != nil {
		t.Fatalf("valid 2-of-3 authorization rejected: %v", err)
	}

	one := request
	one.Approvals = one.Approvals[:1]
	if err := authorizer.Verify(one); !errors.Is(err, ErrInsufficientApproval) {
		t.Fatalf("one signer accepted: %v", err)
	}
	duplicate := request
	duplicate.Approvals = []Approval{request.Approvals[0], request.Approvals[0]}
	if err := authorizer.Verify(duplicate); !errors.Is(err, ErrInsufficientApproval) {
		t.Fatalf("duplicate signer accepted: %v", err)
	}
	mutations := map[string]func(*Request){
		"source-chain": func(value *Request) {
			value.Authorization.SourceChainID = "31338"
		},
		"source-coordinator": func(value *Request) {
			value.Authorization.SourceCoordinator[0] ^= 0xff
		},
		"destination-chain": func(value *Request) {
			value.Authorization.DestinationChainID = "31337"
		},
		"destination-coordinator": func(value *Request) {
			value.Authorization.DestinationCoordinator[0] ^= 0xff
		},
		"message": func(value *Request) {
			value.Authorization.Request.MessageID[0] ^= 0xff
			value.OriginalMessageID = value.Authorization.Request.MessageID
		},
		"envelope": func(value *Request) {
			value.Authorization.Request.EnvelopeHash[0] ^= 0xff
			value.ImmutableEnvelopeHash = value.Authorization.Request.EnvelopeHash
		},
		"nonce": func(value *Request) {
			value.Authorization.Request.RecoveryNonce++
			value.RecoveryNonce = value.Authorization.Request.RecoveryNonce
		},
		"reason": func(value *Request) {
			value.Authorization.Request.ReasonCode[0] ^= 0xff
		},
		"compensation-payload": func(value *Request) {
			value.Authorization.Request.CompensationPayloadHash[0] ^= 0xff
			value.CompensationPayloadHash =
				value.Authorization.Request.CompensationPayloadHash
		},
	}
	for name, mutate := range mutations {
		changed := request
		authorization := *request.Authorization
		changed.Authorization = &authorization
		mutate(&changed)
		if err := authorizer.Verify(changed); !errors.Is(err, ErrInsufficientApproval) {
			t.Fatalf("wrong %s domain accepted: %v", name, err)
		}
	}
	wrongPolicy := request
	wrongPolicy.AuthorizerPolicyHash = [32]byte{0x98}
	if err := authorizer.Verify(wrongPolicy); !errors.Is(err, ErrInsufficientApproval) {
		t.Fatalf("wrong policy accepted: %v", err)
	}
}

func TestSecp256k1AuthorizerRejectsHighSMalleability(t *testing.T) {
	key := secp256k1.PrivKeyFromBytes([]byte{1})
	request := secp256k1Request()
	digest, err := DigestAuthorization(*request.Authorization)
	if err != nil {
		t.Fatal(err)
	}
	signature := ethereumSignature(t, key, digest, false)
	var s secp256k1.ModNScalar
	if s.SetByteSlice(signature[32:64]) {
		t.Fatal("test signature S overflow")
	}
	s.Negate()
	highS := s.Bytes()
	copy(signature[32:64], highS[:])
	policy, err := NewSecp256k1Authorizer(Secp256k1Policy{
		PolicyHash: request.AuthorizerPolicyHash,
		Signers: map[string][20]byte{
			"a": ethereumAddress(key.PubKey()),
			"b": [20]byte{2},
			"c": [20]byte{3},
		},
	})
	if err != nil {
		t.Fatal(err)
	}
	request.Approvals = []Approval{
		{SignerID: "a", Signature: signature},
		{SignerID: "b", Signature: make([]byte, 65)},
	}
	if err := policy.Verify(request); !errors.Is(err, ErrInsufficientApproval) {
		t.Fatalf("high-S signature accepted: %v", err)
	}
}

func TestRecoveryAuthorizationDigestSolidityGolden(t *testing.T) {
	authorization := Authorization{
		ProtocolID:             repeated32(0x01),
		SourceChainID:          "31337",
		SourceCoordinator:      repeated20(0x02),
		DestinationChainID:     "31338",
		DestinationCoordinator: repeated20(0x04),
		Request: AuthorizationRequest{
			MessageID:                  repeated32(0xaa),
			EnvelopeHash:               repeated32(0xbb),
			RoutePolicyHash:            repeated32(0xcc),
			AssetAmountCommitment:      repeated32(0xdd),
			SourceStateCommitment:      repeated32(0xee),
			DestinationStateCommitment: repeated32(0xff),
			CompensationPayloadHash:    repeated32(0x12),
			MessageExpiresAt:           1_700_003_600,
			RecoveryNonce:              7,
			ReasonCode:                 repeated32(0x13),
			Action:                     1,
			AuthorizerSetHash:          repeated32(0x14),
			AuthorizerSetVersion:       1,
		},
	}
	digest, err := DigestAuthorization(authorization)
	if err != nil {
		t.Fatal(err)
	}
	const expected = "2ca5318f1079c2d3c45a5cefb7c5cf784728956bd328df3ee36feeb9b16af0ad"
	if actual := hex.EncodeToString(digest[:]); actual != expected {
		t.Fatalf("recovery authorization digest changed: got %s want %s", actual, expected)
	}
	recoveryID, err := RecoveryID(authorization.Request)
	if err != nil {
		t.Fatal(err)
	}
	const expectedID = "049c45f9e5e106b33a2932b696fc45bdf394b35bb7b94e2b79e837cdfc4b0763"
	if actual := hex.EncodeToString(recoveryID[:]); actual != expectedID {
		t.Fatalf("recovery ID changed: got %s want %s", actual, expectedID)
	}
}

func secp256k1Request() Request {
	keys := []*secp256k1.PrivateKey{
		secp256k1.PrivKeyFromBytes([]byte{1}),
		secp256k1.PrivKeyFromBytes([]byte{2}),
		secp256k1.PrivKeyFromBytes([]byte{3}),
	}
	setHash, err := AuthorizerSetHash(1, [3][20]byte{
		ethereumAddress(keys[0].PubKey()),
		ethereumAddress(keys[1].PubKey()),
		ethereumAddress(keys[2].PubKey()),
	})
	if err != nil {
		panic(err)
	}
	asset := [20]byte{0x55}
	recipient := [20]byte{0x66}
	actionPayload := make([]byte, 7*32)
	copy(actionPayload[2*32:3*32], abiAddress(asset))
	actionPayload[7*32-1] = 100
	assetAmount, err := AssetAmountCommitment(1, keccakBytes(actionPayload))
	if err != nil {
		panic(err)
	}
	compensationPayload, err := EncodeCompensationPayload(asset, "100", recipient)
	if err != nil {
		panic(err)
	}
	compensationPayloadHash := keccakBytes(compensationPayload)
	authorization := &Authorization{
		ProtocolID:             [32]byte{0x10},
		SourceChainID:          "31337",
		SourceCoordinator:      [20]byte{0xaa},
		DestinationChainID:     "31338",
		DestinationCoordinator: [20]byte{0xbb},
		Request: AuthorizationRequest{
			MessageID:                  [32]byte{1},
			EnvelopeHash:               [32]byte{2},
			RoutePolicyHash:            [32]byte{3},
			AssetAmountCommitment:      assetAmount,
			SourceStateCommitment:      [32]byte{5},
			DestinationStateCommitment: [32]byte{6},
			CompensationPayloadHash:    compensationPayloadHash,
			MessageExpiresAt:           1_700_003_600,
			RecoveryNonce:              1,
			ReasonCode:                 ReasonCodeCommitment("SYNTHETIC_TEST"),
			Action:                     1,
			AuthorizerSetHash:          setHash,
			AuthorizerSetVersion:       1,
		},
	}
	recoveryID, err := RecoveryID(authorization.Request)
	if err != nil {
		panic(err)
	}
	return Request{
		RecoveryID:                 hex.EncodeToString(recoveryID[:]),
		OriginalMessageID:          [32]byte{1},
		ImmutableEnvelopeHash:      [32]byte{2},
		RecoveryNonce:              1,
		RouteVersion:               1,
		OriginalActionType:         1,
		OriginalActionPayload:      actionPayload,
		AssetID:                    canonicalAddress(asset),
		Units:                      "100",
		CompensationRecipient:      canonicalAddress(recipient),
		CompensationPayload:        compensationPayload,
		ReasonCode:                 "SYNTHETIC_TEST",
		SourceStateCommitment:      [32]byte{5},
		DestinationStateCommitment: [32]byte{6},
		AuthorizerPolicyHash:       setHash,
		RoutePolicyHash:            [32]byte{3},
		AssetAmountCommitment:      assetAmount,
		CompensationPayloadHash:    compensationPayloadHash,
		MessageExpiresAt:           1_700_003_600,
		Action:                     1,
		AuthorizerSetVersion:       1,
		Authorization:              authorization,
		RequestedAt:                time.Unix(1_700_000_000, 0).UTC(),
	}
}

func repeated32(value byte) (result [32]byte) {
	for index := range result {
		result[index] = value
	}
	return result
}

func repeated20(value byte) (result [20]byte) {
	for index := range result {
		result[index] = value
	}
	return result
}

func ethereumSignature(
	t *testing.T,
	key *secp256k1.PrivateKey,
	digest [32]byte,
	legacyV bool,
) []byte {
	t.Helper()
	compact := secp256k1ecdsa.SignCompact(key, digest[:], false)
	if compact[0] < 27 || compact[0] > 28 {
		t.Fatalf("test generated unsupported Ethereum recovery id %d", compact[0])
	}
	result := make([]byte, 65)
	copy(result[:32], compact[1:33])
	copy(result[32:64], compact[33:65])
	result[64] = compact[0] - 27
	if legacyV {
		result[64] += 27
	}
	return result
}

func ethereumAddress(publicKey *secp256k1.PublicKey) [20]byte {
	serialized := publicKey.SerializeUncompressed()
	hasher := sha3.NewLegacyKeccak256()
	_, _ = hasher.Write(serialized[1:])
	sum := hasher.Sum(nil)
	var result [20]byte
	copy(result[:], sum[len(sum)-20:])
	return result
}
