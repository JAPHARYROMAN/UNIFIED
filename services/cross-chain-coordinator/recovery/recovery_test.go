package recovery

import (
	"errors"
	"testing"
	"time"

	"github.com/decred/dcrd/dcrec/secp256k1/v4"
	secp256k1ecdsa "github.com/decred/dcrd/dcrec/secp256k1/v4/ecdsa"
)

type fakeDestination struct {
	executed bool
}

func (destination *fakeDestination) ExecutionResult([32]byte) ([32]byte, bool) {
	return [32]byte{9}, destination.executed
}

func (destination *fakeDestination) CreateTombstone(request Request) (Tombstone, error) {
	return Tombstone{
		OriginalMessageID: request.OriginalMessageID,
		Hash:              [32]byte{3},
		FinalityProofHash: [32]byte{4},
		FinalizedAt:       request.RequestedAt.Add(time.Minute),
	}, nil
}

type authorizationFixture struct {
	manager *Manager
	request Request
	keys    map[string]*secp256k1.PrivateKey
}

func requestFixture(t *testing.T) authorizationFixture {
	t.Helper()
	keys := make(map[string]*secp256k1.PrivateKey)
	addresses := make(map[string][20]byte)
	for index, signerID := range []string{"signer-a", "signer-b", "signer-c"} {
		privateKey := secp256k1.PrivKeyFromBytes([]byte{byte(index + 1)})
		keys[signerID] = privateKey
		addresses[signerID] = ethereumAddress(privateKey.PubKey())
	}
	request := secp256k1Request()
	policyHash := request.AuthorizerPolicyHash
	authorizer, err := NewSecp256k1Authorizer(Secp256k1Policy{
		PolicyHash: policyHash,
		Signers:    addresses,
	})
	if err != nil {
		t.Fatalf("authorizer: %v", err)
	}
	manager, err := NewManager(authorizer)
	if err != nil {
		t.Fatalf("manager: %v", err)
	}
	request = signed(request, keys, "signer-a", "signer-b")
	return authorizationFixture{manager: manager, request: request, keys: keys}
}

func signed(
	request Request,
	keys map[string]*secp256k1.PrivateKey,
	signerIDs ...string,
) Request {
	request.Approvals = nil
	digest, err := DigestAuthorization(*request.Authorization)
	if err != nil {
		panic(err)
	}
	for _, signerID := range signerIDs {
		compact := secp256k1ecdsa.SignCompact(keys[signerID], digest[:], false)
		if compact[0] < 27 || compact[0] > 28 {
			panic("unexpected secp256k1 test signature recovery id")
		}
		signature := make([]byte, 65)
		copy(signature[:32], compact[1:33])
		copy(signature[32:64], compact[33:65])
		signature[64] = compact[0] - 27
		request.Approvals = append(request.Approvals, Approval{
			SignerID:  signerID,
			Signature: signature,
		})
	}
	return request
}

func TestExecutedDestinationPreventsTombstone(t *testing.T) {
	fixture := requestFixture(t)
	if _, err := fixture.manager.Request(fixture.request); err != nil {
		t.Fatalf("request: %v", err)
	}
	if _, err := fixture.manager.Tombstone(
		fixture.request.OriginalMessageID,
		&fakeDestination{executed: true},
	); !errors.Is(err, ErrExecuted) {
		t.Fatalf("expected executed rejection, got %v", err)
	}
}

func TestPolicyBoundApprovalsRejectForgeryDuplicateAndWrongPolicy(t *testing.T) {
	fixture := requestFixture(t)
	forged := fixture.request
	forged.Approvals[0].Signature[0] ^= 0xff
	if _, err := fixture.manager.Request(forged); !errors.Is(err, ErrInsufficientApproval) {
		t.Fatalf("expected forged signature rejection, got %v", err)
	}

	duplicate := signed(fixture.request, fixture.keys, "signer-a", "signer-a")
	if _, err := fixture.manager.Request(duplicate); !errors.Is(err, ErrInsufficientApproval) {
		t.Fatalf("expected duplicate signer rejection, got %v", err)
	}

	wrongPolicy := fixture.request
	wrongPolicy.AuthorizerPolicyHash = [32]byte{0x99}
	wrongPolicy = signed(wrongPolicy, fixture.keys, "signer-a", "signer-b")
	if _, err := fixture.manager.Request(wrongPolicy); !errors.Is(err, ErrInsufficientApproval) {
		t.Fatalf("expected wrong policy rejection, got %v", err)
	}
}

func TestTombstoneCompensationAcknowledgementAndReplacementLifecycle(t *testing.T) {
	fixture := requestFixture(t)
	if _, err := fixture.manager.Request(fixture.request); err != nil {
		t.Fatalf("request: %v", err)
	}
	record, err := fixture.manager.Tombstone(fixture.request.OriginalMessageID, &fakeDestination{})
	if err != nil || record.State != DestinationTombstoned {
		t.Fatalf("tombstone: state=%s err=%v", record.State, err)
	}
	compensation := Compensation{
		OriginalMessageID: fixture.request.OriginalMessageID,
		TombstoneHash:     record.Tombstone.Hash,
		Payload:           append([]byte(nil), fixture.request.CompensationPayload...),
		ResultHash:        [32]byte{7},
		AssetID:           fixture.request.AssetID,
		Recipient:         fixture.request.CompensationRecipient,
		Units:             fixture.request.Units,
		CompensatedAt:     fixture.request.RequestedAt.Add(2 * time.Minute),
	}
	record, err = fixture.manager.Compensate(compensation)
	if err != nil || record.State != SourceCompensated {
		t.Fatalf("compensate: state=%s err=%v", record.State, err)
	}
	changedPayload := compensation
	changedPayload.Payload = []byte("compensate:101")
	if _, err := fixture.manager.Compensate(changedPayload); !errors.Is(
		err,
		ErrAlreadyCompensated,
	) {
		t.Fatalf("changed compensation payload replay accepted: %v", err)
	}
	if err := fixture.manager.AuthorizeReplacement(
		fixture.request.OriginalMessageID,
		[32]byte{8},
	); !errors.Is(err, ErrNotTombstoned) {
		t.Fatalf("replacement before recovery acknowledgement was allowed: %v", err)
	}
	record, err = fixture.manager.Finalize(fixture.request.OriginalMessageID, [32]byte{9})
	if err != nil || record.State != Recovered {
		t.Fatalf("finalize: state=%s err=%v", record.State, err)
	}
	if _, err := fixture.manager.Finalize(
		fixture.request.OriginalMessageID,
		[32]byte{9},
	); err != nil {
		t.Fatalf("exact final acknowledgement replay: %v", err)
	}
	if err := fixture.manager.AuthorizeReplacement(
		fixture.request.OriginalMessageID,
		[32]byte{8},
	); err != nil {
		t.Fatalf("replacement: %v", err)
	}
	if err := fixture.manager.AuthorizeReplacement(
		fixture.request.OriginalMessageID,
		[32]byte{10},
	); !errors.Is(err, ErrRecoveryConflict) {
		t.Fatalf("expected replacement conflict, got %v", err)
	}
}

func TestRequestBindsEconomicFieldsAndCanonicalizesApprovalReplay(t *testing.T) {
	for name, mutate := range map[string]func(*Request){
		"asset": func(request *Request) {
			request.AssetID = canonicalAddress([20]byte{0x77})
		},
		"units": func(request *Request) {
			request.Units = "101"
		},
		"recipient": func(request *Request) {
			request.CompensationRecipient = canonicalAddress([20]byte{0x78})
		},
		"action-payload": func(request *Request) {
			request.OriginalActionPayload[0] ^= 0xff
		},
		"compensation-payload": func(request *Request) {
			request.CompensationPayload[0] ^= 0xff
		},
	} {
		t.Run(name, func(t *testing.T) {
			fixture := requestFixture(t)
			changed := cloneRequest(fixture.request)
			mutate(&changed)
			if _, err := fixture.manager.Request(changed); !errors.Is(
				err,
				ErrInsufficientApproval,
			) {
				t.Fatalf("unsigned %s mutation accepted: %v", name, err)
			}
		})
	}

	fixture := requestFixture(t)
	if _, err := fixture.manager.Request(fixture.request); err != nil {
		t.Fatalf("request: %v", err)
	}
	reordered := cloneRequest(fixture.request)
	reordered.Approvals[0], reordered.Approvals[1] =
		reordered.Approvals[1], reordered.Approvals[0]
	if _, err := fixture.manager.Request(reordered); err != nil {
		t.Fatalf("reordered exact authorization replay rejected: %v", err)
	}
}

func TestCompensationRejectsAlteredAssetAndUnits(t *testing.T) {
	for name, mutate := range map[string]func(*Compensation){
		"asset": func(compensation *Compensation) {
			compensation.AssetID = canonicalAddress([20]byte{0x77})
		},
		"units": func(compensation *Compensation) {
			compensation.Units = "101"
		},
	} {
		t.Run(name, func(t *testing.T) {
			fixture := requestFixture(t)
			if _, err := fixture.manager.Request(fixture.request); err != nil {
				t.Fatalf("request: %v", err)
			}
			record, err := fixture.manager.Tombstone(
				fixture.request.OriginalMessageID,
				&fakeDestination{},
			)
			if err != nil {
				t.Fatalf("tombstone: %v", err)
			}
			compensation := Compensation{
				OriginalMessageID: fixture.request.OriginalMessageID,
				TombstoneHash:     record.Tombstone.Hash,
				Payload:           append([]byte(nil), fixture.request.CompensationPayload...),
				ResultHash:        [32]byte{7},
				AssetID:           fixture.request.AssetID,
				Recipient:         fixture.request.CompensationRecipient,
				Units:             fixture.request.Units,
				CompensatedAt:     fixture.request.RequestedAt.Add(2 * time.Minute),
			}
			mutate(&compensation)
			if _, err := fixture.manager.Compensate(compensation); !errors.Is(
				err,
				ErrRecoveryConflict,
			) {
				t.Fatalf("altered compensation %s accepted: %v", name, err)
			}
		})
	}
}
