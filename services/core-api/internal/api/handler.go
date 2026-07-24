package api

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strings"
	"time"
)

var (
	ErrNotFound  = errors.New("projection not found")
	ErrForbidden = errors.New("principal is not authorized")
)

type Principal struct {
	ID    string
	Roles map[string]bool
}

type Authenticator interface {
	Authenticate(token string) (Principal, bool)
}

type ProjectionStore interface {
	Tender(id string) (TenderProjection, error)
	Loan(id string) (LoanProjection, error)
	Portfolio(partyID string) ([]LoanProjection, error)
}

type OfferCommands interface {
	SubmitOffer(principal Principal, command SubmitOfferCommand) (CommandReceipt, error)
}

type TransactionPreparer interface {
	PrepareAcceptance(
		principal Principal,
		request PrepareAcceptanceRequest,
	) (TransactionPreparation, error)
}

type TenderProjection struct {
	ID              string `json:"id"`
	BorrowerID      string `json:"borrower_id"`
	State           string `json:"state"`
	SelectedOfferID string `json:"selected_offer_id,omitempty"`
	Finality        string `json:"finality"`
}

type LoanProjection struct {
	ID               string `json:"id"`
	BorrowerID       string `json:"borrower_id"`
	LenderID         string `json:"lender_id"`
	AssetID          string `json:"asset_id"`
	PrincipalUnits   string `json:"principal_units"`
	OutstandingUnits string `json:"outstanding_units"`
	Status           string `json:"status"`
	Finality         string `json:"finality"`
}

type SubmitOfferCommand struct {
	CommandID      string `json:"command_id"`
	OfferID        string `json:"offer_id"`
	TenderID       string `json:"tender_id"`
	LenderID       string `json:"lender_id"`
	TermsHash      string `json:"terms_hash"`
	Signature      string `json:"signature"`
	IdempotencyKey string `json:"idempotency_key"`
}

type CommandReceipt struct {
	CommandID string `json:"command_id"`
	Status    string `json:"status"`
}

type PrepareAcceptanceRequest struct {
	TenderID string `json:"tender_id"`
	OfferID  string `json:"offer_id"`
}

type TransactionPreparation struct {
	PreparationID     string    `json:"preparation_id"`
	ChainDomain       string    `json:"chain_domain"`
	To                string    `json:"to"`
	CallData          string    `json:"call_data"`
	ValueUnits        string    `json:"value_units"`
	ExpectedTermsHash string    `json:"expected_terms_hash"`
	ExpiresAt         time.Time `json:"expires_at"`
}

type Handler struct {
	auth        Authenticator
	projections ProjectionStore
	offers      OfferCommands
	preparer    TransactionPreparer
}

type principalContextKey struct{}

func NewHandler(
	auth Authenticator,
	projections ProjectionStore,
	offers OfferCommands,
	preparer TransactionPreparer,
) http.Handler {
	handler := &Handler{
		auth: auth, projections: projections, offers: offers, preparer: preparer,
	}
	mux := http.NewServeMux()
	mux.HandleFunc("GET /v1/tenders/{id}", handler.getTender)
	mux.HandleFunc("POST /v1/offers", handler.submitOffer)
	mux.HandleFunc("GET /v1/loans/{id}", handler.getLoan)
	mux.HandleFunc("GET /v1/portfolio", handler.getPortfolio)
	mux.HandleFunc("POST /v1/transactions/prepare-acceptance", handler.prepareAcceptance)
	return handler.authenticate(mux)
}

func (handler *Handler) authenticate(next http.Handler) http.Handler {
	return http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		header := request.Header.Get("Authorization")
		if !strings.HasPrefix(header, "Bearer ") {
			writeError(response, http.StatusUnauthorized, "missing bearer credential")
			return
		}
		principal, ok := handler.auth.Authenticate(strings.TrimPrefix(header, "Bearer "))
		if !ok || principal.ID == "" {
			writeError(response, http.StatusUnauthorized, "invalid bearer credential")
			return
		}
		contextWithPrincipal := context.WithValue(
			request.Context(), principalContextKey{}, principal,
		)
		next.ServeHTTP(response, request.WithContext(contextWithPrincipal))
	})
}

func (handler *Handler) principal(request *http.Request) Principal {
	principal, _ := request.Context().Value(principalContextKey{}).(Principal)
	return principal
}

func (handler *Handler) getTender(response http.ResponseWriter, request *http.Request) {
	tender, err := handler.projections.Tender(request.PathValue("id"))
	writeResult(response, tender, err)
}

func (handler *Handler) submitOffer(response http.ResponseWriter, request *http.Request) {
	var command SubmitOfferCommand
	if !decode(response, request, &command) {
		return
	}
	if command.CommandID == "" || command.OfferID == "" || command.TenderID == "" ||
		command.LenderID == "" || command.TermsHash == "" || command.Signature == "" ||
		command.IdempotencyKey == "" {
		writeError(response, http.StatusBadRequest, "incomplete offer command")
		return
	}
	if command.LenderID != handler.principal(request).ID {
		writeError(response, http.StatusForbidden, ErrForbidden.Error())
		return
	}
	receipt, err := handler.offers.SubmitOffer(handler.principal(request), command)
	if err != nil {
		writeResult(response, receipt, err)
		return
	}
	writeJSON(response, http.StatusAccepted, receipt)
}

func (handler *Handler) getLoan(response http.ResponseWriter, request *http.Request) {
	loan, err := handler.projections.Loan(request.PathValue("id"))
	writeResult(response, loan, err)
}

func (handler *Handler) getPortfolio(response http.ResponseWriter, request *http.Request) {
	loans, err := handler.projections.Portfolio(handler.principal(request).ID)
	writeResult(response, loans, err)
}

func (handler *Handler) prepareAcceptance(response http.ResponseWriter, request *http.Request) {
	var preparation PrepareAcceptanceRequest
	if !decode(response, request, &preparation) {
		return
	}
	if preparation.TenderID == "" || preparation.OfferID == "" {
		writeError(response, http.StatusBadRequest, "incomplete acceptance preparation")
		return
	}
	result, err := handler.preparer.PrepareAcceptance(handler.principal(request), preparation)
	writeResult(response, result, err)
}

func decode(response http.ResponseWriter, request *http.Request, target any) bool {
	decoder := json.NewDecoder(http.MaxBytesReader(response, request.Body, 64<<10))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(target); err != nil {
		writeError(response, http.StatusBadRequest, "invalid request body")
		return false
	}
	if err := decoder.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		writeError(response, http.StatusBadRequest, "request body must contain one JSON value")
		return false
	}
	return true
}

func writeResult(response http.ResponseWriter, value any, err error) {
	if errors.Is(err, ErrNotFound) {
		writeError(response, http.StatusNotFound, err.Error())
		return
	}
	if errors.Is(err, ErrForbidden) {
		writeError(response, http.StatusForbidden, err.Error())
		return
	}
	if err != nil {
		writeError(response, http.StatusConflict, err.Error())
		return
	}
	writeJSON(response, http.StatusOK, value)
}

func writeError(response http.ResponseWriter, status int, message string) {
	writeJSON(response, status, map[string]string{"error": message})
}

func writeJSON(response http.ResponseWriter, status int, value any) {
	response.Header().Set("Content-Type", "application/json")
	response.WriteHeader(status)
	_ = json.NewEncoder(response).Encode(value)
}

type StaticAuthenticator map[string]Principal

func (auth StaticAuthenticator) Authenticate(token string) (Principal, bool) {
	principal, ok := auth[token]
	return principal, ok
}
