package api

import (
	"bytes"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

type fakeBackend struct {
	tender  TenderProjection
	loan    LoanProjection
	command SubmitOfferCommand
}

func (backend *fakeBackend) Tender(id string) (TenderProjection, error) {
	if id != backend.tender.ID {
		return TenderProjection{}, ErrNotFound
	}
	return backend.tender, nil
}

func (backend *fakeBackend) Loan(id string) (LoanProjection, error) {
	if id != backend.loan.ID {
		return LoanProjection{}, ErrNotFound
	}
	return backend.loan, nil
}

func (backend *fakeBackend) Portfolio(partyID string) ([]LoanProjection, error) {
	if partyID != backend.loan.BorrowerID && partyID != backend.loan.LenderID {
		return nil, nil
	}
	return []LoanProjection{backend.loan}, nil
}

func (backend *fakeBackend) SubmitOffer(
	principal Principal,
	command SubmitOfferCommand,
) (CommandReceipt, error) {
	if command.CommandID == "" || command.Signature == "" || command.TermsHash == "" ||
		command.IdempotencyKey == "" {
		return CommandReceipt{}, errors.New("incomplete offer command")
	}
	backend.command = command
	return CommandReceipt{CommandID: command.CommandID, Status: "ACCEPTED"}, nil
}

func (backend *fakeBackend) PrepareAcceptance(
	principal Principal,
	request PrepareAcceptanceRequest,
) (TransactionPreparation, error) {
	if principal.ID != backend.tender.BorrowerID {
		return TransactionPreparation{}, ErrForbidden
	}
	return TransactionPreparation{
		PreparationID:     "prepare-1",
		ChainDomain:       "eip155:31337",
		To:                "0x0000000000000000000000000000000000000042",
		CallData:          "0x1234",
		ValueUnits:        "0",
		ExpectedTermsHash: "0xabcd",
		ExpiresAt:         time.Unix(1_900_000_000, 0).UTC(),
	}, nil
}

func fixture() (http.Handler, *fakeBackend) {
	backend := &fakeBackend{
		tender: TenderProjection{
			ID: "tender-1", BorrowerID: "borrower-1", State: "OPEN", Finality: "FINAL",
		},
		loan: LoanProjection{
			ID: "loan-1", BorrowerID: "borrower-1", LenderID: "lender-1",
			AssetID: "asset:local:usdc", PrincipalUnits: "1000",
			OutstandingUnits: "1000", Status: "ACTIVE", Finality: "PROVISIONAL",
		},
	}
	auth := StaticAuthenticator{
		"borrower-token": {ID: "borrower-1", Roles: map[string]bool{"BORROWER": true}},
		"lender-token":   {ID: "lender-1", Roles: map[string]bool{"LENDER": true}},
	}
	return NewHandler(auth, backend, backend, backend), backend
}

func TestEveryRouteRequiresAuthentication(t *testing.T) {
	handler, _ := fixture()
	request := httptest.NewRequest(http.MethodGet, "/v1/tenders/tender-1", nil)
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)
	if response.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", response.Code)
	}
}

func TestLenderCanSubmitAttributableSignedOffer(t *testing.T) {
	handler, backend := fixture()
	body := []byte(`{
		"command_id":"command-1",
		"offer_id":"offer-1",
		"tender_id":"tender-1",
		"lender_id":"lender-1",
		"terms_hash":"0xabcd",
		"signature":"0x1234",
		"idempotency_key":"offer-1"
	}`)
	request := httptest.NewRequest(http.MethodPost, "/v1/offers", bytes.NewReader(body))
	request.Header.Set("Authorization", "Bearer lender-token")
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)
	if response.Code != http.StatusAccepted {
		t.Fatalf("expected 202, got %d: %s", response.Code, response.Body.String())
	}
	if backend.command.OfferID != "offer-1" {
		t.Fatal("offer command was not handed to the command boundary")
	}
}

func TestBorrowerGetsUnsignedBoundedAcceptancePreparation(t *testing.T) {
	handler, _ := fixture()
	body := []byte(`{"tender_id":"tender-1","offer_id":"offer-1"}`)
	request := httptest.NewRequest(
		http.MethodPost,
		"/v1/transactions/prepare-acceptance",
		bytes.NewReader(body),
	)
	request.Header.Set("Authorization", "Bearer borrower-token")
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)
	if response.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", response.Code, response.Body.String())
	}
	if bytes.Contains(response.Body.Bytes(), []byte("private_key")) {
		t.Fatal("transaction preparation leaked signing material")
	}
}

func TestPrincipalCannotSubmitAnOfferForAnotherLender(t *testing.T) {
	handler, _ := fixture()
	body := []byte(`{
		"command_id":"command-1",
		"offer_id":"offer-1",
		"tender_id":"tender-1",
		"lender_id":"someone-else",
		"terms_hash":"0xabcd",
		"signature":"0x1234",
		"idempotency_key":"offer-1"
	}`)
	request := httptest.NewRequest(http.MethodPost, "/v1/offers", bytes.NewReader(body))
	request.Header.Set("Authorization", "Bearer lender-token")
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)
	if response.Code != http.StatusForbidden {
		t.Fatalf("expected 403, got %d", response.Code)
	}
}
